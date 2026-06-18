#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# M8 capstone runner: re-verify the M1-M7 footprint the threat model rests on, and
# byte-diff the canonical claim string across the doc artifacts. Run from repo root:
#   bash v2/milestones/08-threat-model/run.sh

set -euo pipefail

DIR="v2/milestones/08-threat-model"

# 1. Rebuild the C crypto leaf + Lean core.
bash c/build.sh
lake build

# 2. All axiom-check guards (build-breaking #guard_msgs). M5's signed_parse_canonical is
#    locked inside the m4 gate — there is no separate v2_m5_axiom_check.
for c in v2_m1_axiom_check v2_m2_axiom_check v2_m3_axiom_check v2_m3_parser_axiom_check \
         v2_m4_axiom_check v2_m6_axiom_check; do
  lake exe "$c" >/dev/null
done

# 3. Capture the full named-theorem footprint from a live #print axioms run (quoted, not asserted).
#    Guards are explicit `if` (NOT `! grep` — set -e ignores `!`-inverted failures).
lake env lean "$DIR/print_axioms.lean" 2>&1 | grep -E 'depends on axioms|does not depend' | tee "$DIR/axioms.txt"
if grep -E 'sorryAx|native_decide|Lean\.ofReduceBool' "$DIR/axioms.txt"; then
  echo "FATAL: forbidden axiom/term in footprint" >&2; exit 1; fi
if grep -E 'depends on axioms' "$DIR/axioms.txt" | grep -vqE '\[propext, Classical\.choice, Quot\.sound\]$'; then
  echo "FATAL: axiom footprint drift" >&2; exit 1; fi

# 4. Byte-diff the CANONICAL CLAIM STRING (fixed-string match) across the doc artifacts.
CLAIM='complete mediation modulo A1-A4, with A2 minimised by construction; A6 (durability) stated, not hidden.'
for f in "$DIR/THREAT-MODEL.md" "$DIR/NOTES.md" v2/STATUS.md; do
  grep -Fq "$CLAIM" "$f" || { echo "FATAL: canonical claim string missing or altered in $f" >&2; exit 1; }
done
echo "canonical claim string byte-identical in THREAT-MODEL.md, NOTES.md, v2/STATUS.md"

# (Claim discipline — no overclaim words used as claims — is a semantic check left to the
#  review gate; an automated grep false-matches the ledger's own meta-sentence about those words.)

echo "M8 threat-model runner: OK"
