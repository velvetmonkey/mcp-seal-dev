#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# M4 milestone acceptance runner. Reproduces the green frontier from a build and
# files the evidence artifacts beside this script. Run from the repo root:
#   bash v2/milestones/04-decide/run.sh

set -euo pipefail

DIR="v2/milestones/04-decide"

# 1. Build. The build-breaking #guard_msgs checks in Test/V2M4Axioms.lean fire
#    here: if any M4 theorem's axiom footprint drifts, this `lake build` FAILS.
lake build

# 2. Axiom footprint evidence. Plain #print axioms (un-guarded) so the footprint
#    lines reach stdout. Then assert no sorryAx / native_decide / ofReduceBool.
lake env lean "$DIR/print_axioms.lean" 2>&1 | grep 'depends on axioms' | tee "$DIR/axioms.txt"
! grep -E 'sorryAx|native_decide|Lean\.ofReduceBool' "$DIR/axioms.txt"
# Every line must be exactly the v1 footprint.
! grep -E 'depends on axioms' "$DIR/axioms.txt" | grep -vqE '\[propext, Classical\.choice, Quot\.sound\]$'

# 3. End-to-end adversarial acceptance through the public `decide` entrypoint.
#    1 legitimate mediated call Allows; every bypass/malformed line Blocks.
python3 test/v2/m4_adversarial_mcp_fixture.py | tee "$DIR/fixture-run.txt"
python3 test/v2/m4_adversarial_mcp_fixture.py --dump | tee "$DIR/decide-corpus.txt"

echo "M4 milestone runner: OK"
