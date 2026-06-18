#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# M6 milestone acceptance runner. Run from the repo root:
#   bash v2/milestones/06-lifecycle/run.sh

set -euo pipefail

DIR="v2/milestones/06-lifecycle"

# 1. Rebuild vendored C crypto (M5 leaf) + the Lean core.
bash c/build.sh
lake build

# 2. Axiom footprint evidence for the five M6 invariants (must be the v1 footprint).
lake env lean "$DIR/print_axioms.lean" 2>&1 | grep 'depends on axioms' | tee "$DIR/axioms.txt"
! grep -E 'sorryAx|native_decide|Lean\.ofReduceBool' "$DIR/axioms.txt"
! grep -E "depends on axioms" "$DIR/axioms.txt" | grep -vqE '\[propext, Classical\.choice, Quot\.sound\]$'
# The build-breaking guard also re-checks these at compile time:
lake exe v2_m6_axiom_check

# 3. Cross-milestone regression: prior accept paths still green under the re-keyed namespace.
lake exe v2_validate_tests
lake exe v2_serialize_tests
python3 test/v2/m4_adversarial_mcp_fixture.py
python3 test/v2/m5_sign_fixture.py

# 4. M6 lifecycle acceptance over the real store machine.
lake exe v2_lifecycle_tests | tee "$DIR/fixture-run.txt"
lake exe v2_lifecycle_tests --dump | tee "$DIR/lifecycle-corpus.txt"

echo "M6 milestone runner: OK"
