#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

lake build
lake exe v2_parse_tests
lake env lean v2/milestones/01-parse/print_axioms.lean 2>&1 | grep -E 'depends on axioms|does not depend' | tee v2/milestones/03-serialize/m1-axioms.txt
! grep -E 'sorryAx|Lean\.ofReduceBool' v2/milestones/03-serialize/m1-axioms.txt
lake exe v2_validate_tests
lake env lean v2/milestones/02-validate/print_axioms.lean 2>&1 | grep -E 'depends on axioms|does not depend' | tee v2/milestones/03-serialize/m2-axioms.txt
! grep -E 'sorryAx|Lean\.ofReduceBool' v2/milestones/03-serialize/m2-axioms.txt
lake exe v2_serialize_tests | tee v2/milestones/03-serialize/serialize-corpus.txt
lake env lean v2/milestones/03-serialize/parser-print.lean 2>&1 | grep -E 'depends on axioms|does not depend' | tee v2/milestones/03-serialize/parser-axioms.txt
! grep -E 'sorryAx|Lean\.ofReduceBool' v2/milestones/03-serialize/parser-axioms.txt
lake env lean v2/milestones/03-serialize/print_axioms.lean 2>&1 | grep -E 'depends on axioms|does not depend' | tee v2/milestones/03-serialize/axioms.txt
! grep -E 'sorryAx|Lean\.ofReduceBool' v2/milestones/03-serialize/axioms.txt
python3 test/v2/m3_serialization_fixture.py | tee v2/milestones/03-serialize/fixture-run.txt
