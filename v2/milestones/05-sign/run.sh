#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# M5 milestone acceptance runner. Builds the vendored C crypto, the Lean core, and
# files the evidence artifacts beside this script. Run from the repo root:
#   bash v2/milestones/05-sign/run.sh

set -euo pipefail

DIR="v2/milestones/05-sign"

# 1. Rebuild the vendored Ed25519 (TweetNaCl) + FFI shim from source — no stale blob.
bash c/build.sh

# 2. Build the Lean core + exes (links the C object via package moreLinkArgs).
lake build

# 3. Axiom footprint evidence. The swap to real Ed25519 sits behind an opaque
#    @[extern] seam, so the footprint must be UNCHANGED. Plain #print axioms to stdout.
lake env lean "$DIR/print_axioms.lean" 2>&1 | grep -E 'depends on axioms|does not depend' | tee "$DIR/axioms.txt"
! grep -E 'sorryAx|native_decide|Lean\.ofReduceBool' "$DIR/axioms.txt"
! grep -E "depends on axioms" "$DIR/axioms.txt" | grep -vqE '\[propext, Classical\.choice, Quot\.sound\]$'

# 4. Cross-milestone regression: prior accept paths must still accept under real crypto.
lake exe v2_validate_tests
lake exe v2_serialize_tests
python3 test/v2/m2_adversarial_mcp_fixture.py
python3 test/v2/m4_adversarial_mcp_fixture.py

# 5. M5 end-to-end Ed25519 acceptance: real signatures over canonical bytes.
python3 test/v2/m5_sign_fixture.py | tee "$DIR/fixture-run.txt"
python3 test/v2/m5_sign_fixture.py --dump | tee "$DIR/sign-corpus.txt"

echo "M5 milestone runner: OK"
