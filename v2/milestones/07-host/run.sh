#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# M7 milestone acceptance runner. Run from the repo root:
#   bash v2/milestones/07-host/run.sh

set -euo pipefail

DIR="v2/milestones/07-host"

# 1. Build the C crypto leaf + Lean core.
bash c/build.sh
lake build

# 2. CORE axiom footprint unchanged by the FFI work (Ffi.lean is IO glue, no theorems).
lake env lean "$DIR/print_axioms.lean" 2>&1 | grep -E 'depends on axioms|does not depend' | tee "$DIR/axioms.txt"
! grep -E 'sorryAx|native_decide|Lean\.ofReduceBool' "$DIR/axioms.txt"
! grep -E "depends on axioms" "$DIR/axioms.txt" | grep -vqE '\[propext, Classical\.choice, Quot\.sound\]$'
lake exe v2_m6_axiom_check

# 3. Build the self-contained FFI shared object (full core + ffi_shim + ed25519 leaf).
bash scripts/build_ffi_so.sh

# 4. Build + run the Rust host end-to-end acceptance (through the C ABI):
#    fresh Allow / replay Block / expired Block / tampered-sig Block / forged Block,
#    plus the A4 concurrency probe (N concurrent decides -> exactly 1 Allow). The
#    signed bytes come from the authoritative Lean producer, never a Rust copy.
SIGNED_RAW="$(lake exe v2_signed_bytes)"
SIG_A="3a288732067e139854af6462daa1dce0265bdff175dba2e7e9e0eea70a1de36b00760ce4fb9fb55a0f6228f12ca64ecee920bbe76db6392556225c5269ea3b0f"
( cd rust && cargo +1.96.0 build --quiet )
( cd rust && cargo +1.96.0 run --quiet -- selftest "$SIGNED_RAW" "$SIG_A" ) | tee "$DIR/fixture-run.txt"

echo "M7 milestone runner: OK"
