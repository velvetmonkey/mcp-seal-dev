#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Link the self-contained seal v2 FFI shared library (M7).
#
# Strategy (mirrors seal-host): every Lake package's compiled module objects go
# into a thin archive; the linker pulls exactly the objects the Ffi initializer
# chain references. Lean runtime + Init/Std/Lean symbols stay undefined and
# resolve against libleanshared.so at load. The vendored ed25519 leaf
# (c/build/libsealcrypto.o) is linked in so `ed25519Verify` resolves.
#
# Self-contained: builds the crypto leaf, compiles the Ffi lib (emits .c.o.export),
# then hand-links the .so.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.lake/build/lib/libsealv2ffi.so"
TMP="$ROOT/.lake/build/ffi-archives"
LEAN_PREFIX="$(lean --print-prefix)"
mkdir -p "$TMP" "$ROOT/.lake/build/lib"

# Build the C crypto leaf + the ffi_shared exe (forces C codegen of Ffi → .c.o.export).
[ -f "$ROOT/c/build/libsealcrypto.o" ] || bash "$ROOT/c/build.sh"
( cd "$ROOT" && lake build ffi_shared )

# Project objects: Ffi + SealV2 + Seal modules. Exclude Test/* and Seal/Main —
# both emit their own `main`, which collides with the `main` in Ffi.c.o.export
# (ffi_shared's throwaway exe root). The rest of Seal/* must stay in: since
# SealV2/ClassifyTransport imports Seal.Classify and Seal.JsonUtil, they are in
# the FFI transitive closure and the .so leaves their symbols undefined without
# them (rust-lld links with --no-allow-shlib-undefined and rejects that).
mapfile -t PROJ_OBJS < <(find "$ROOT/.lake/build/ir" -name '*.c.o.export' \
  ! -path '*/Test/*' ! -name 'Test.c.o.export' ! -path '*/Seal/Main.c.o.export' | sort)
[ "${#PROJ_OBJS[@]}" -gt 0 ] || { echo "no project objects; run lake build ffi_shared first" >&2; exit 1; }

ARCHIVES=()
for pkgdir in "$ROOT"/.lake/packages/*/; do
  pkg="$(basename "$pkgdir")"
  irdir="$pkgdir/.lake/build/ir"
  [ -d "$irdir" ] || continue
  objs="$(find "$irdir" -name '*.c.o.export' | sort)"
  [ -n "$objs" ] || continue
  archive="$TMP/lib_${pkg}.a"
  if [ ! -f "$archive" ] || [ "$(find "$irdir" -name '*.c.o.export' -newer "$archive" | head -1)" ]; then
    rm -f "$archive"
    printf '%s\0' $objs | xargs -0 ar qT "$archive"
    ar sT "$archive"
  fi
  ARCHIVES+=("$archive")
done

cc -O2 -fPIC -I "$LEAN_PREFIX/include" -c "$ROOT/scripts/ffi_shim.c" -o "$TMP/ffi_shim.o"

cc -shared -o "$OUT" \
  "$TMP/ffi_shim.o" \
  "${PROJ_OBJS[@]}" \
  "$ROOT/c/build/libsealcrypto.o" \
  -Wl,--start-group "${ARCHIVES[@]}" -Wl,--end-group \
  -L "$LEAN_PREFIX/lib/lean" -lleanshared -lLake_shared \
  -Wl,-rpath,"$LEAN_PREFIX/lib/lean"

echo "built $OUT"
# Capture nm output ONCE, then grep the in-memory copy. (Piping `nm bigfile | grep -q`
# under set -o pipefail flakily fails: grep -q closes the pipe early -> nm gets SIGPIPE
# -> pipefail reports the pipeline as failed even though the symbol was found. The same
# early-exit bites `printf bigstring | grep -q`, so grep must consume the whole stream:
# no -q, redirect to /dev/null instead.)
SYMS="$(nm -D "$OUT")"
for sym in seal_v2_init seal_v2_add_approval seal_v2_decide seal_v2_challenge seal_v2_echo seal_v2_crypto_probe \
           seal_v2_ffi_initialize seal_lean_string_cstr seal_lean_io_result_is_ok seal_lean_dec seal_lean_mk_string; do
  printf '%s\n' "$SYMS" | grep -E " T ${sym}\$" >/dev/null || { echo "FATAL: export $sym missing" >&2; exit 1; }
done
echo "all exports present"
