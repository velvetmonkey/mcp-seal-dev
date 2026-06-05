#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

OUT_DIR="v2/milestones/02-validate"

lake exe v2_validate_tests | tee "$OUT_DIR/validate-corpus.txt"
lake exe v2_m2_axiom_check 2>&1 | tee "$OUT_DIR/axioms.txt"
! grep -E 'sorryAx|Lean\.ofReduceBool' "$OUT_DIR/axioms.txt"
python3 test/v2/m2_adversarial_mcp_fixture.py | tee "$OUT_DIR/fixture-run.txt"
