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

# Project objects: Ffi + SealV2 modules. Exclude Test/* and Seal/Main (own `main`).
mapfile -t PROJ_OBJS < <(find "$ROOT/.lake/build/ir" -name '*.c.o.export' \
  ! -path '*/Test/*' ! -name 'Test.c.o.export' ! -path '*/Seal/*' | sort)
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
for sym in seal_v2_init seal_v2_add_approval seal_v2_decide seal_v2_echo seal_v2_crypto_probe; do
  nm -D "$OUT" | grep -qE " T ${sym}\$" || { echo "FATAL: export $sym missing" >&2; exit 1; }
done
echo "all exports present"
