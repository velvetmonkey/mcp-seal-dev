#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

lake build
lake exe v2_parse_tests
lake exe v2_m1_axiom_check 2>&1 | tee v2/milestones/03-serialize/m1-axioms.txt
! grep -E 'sorryAx|Lean\.ofReduceBool' v2/milestones/03-serialize/m1-axioms.txt
lake exe v2_validate_tests
lake exe v2_m2_axiom_check 2>&1 | tee v2/milestones/03-serialize/m2-axioms.txt
! grep -E 'sorryAx|Lean\.ofReduceBool' v2/milestones/03-serialize/m2-axioms.txt
lake exe v2_serialize_tests | tee v2/milestones/03-serialize/serialize-corpus.txt
lake exe v2_m3_axiom_check 2>&1 | tee v2/milestones/03-serialize/axioms.txt
! grep -E 'Lean\.ofReduceBool' v2/milestones/03-serialize/axioms.txt
python3 test/v2/m3_serialization_fixture.py | tee v2/milestones/03-serialize/fixture-run.txt
