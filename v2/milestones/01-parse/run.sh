#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

OUT_DIR="v2/milestones/01-parse"

lake exe v2_parse_tests | tee "$OUT_DIR/parse-corpus.txt"
lake exe v2_m1_axiom_check 2>&1 | tee "$OUT_DIR/axioms.txt"
! grep -E 'sorryAx|Lean\.ofReduceBool' "$OUT_DIR/axioms.txt"
python3 test/v2/m1_adversarial_mcp_fixture.py | tee "$OUT_DIR/fixture-run.txt"
