#!/usr/bin/env bash
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

bash c/build.sh || exit 1
leanbuild build v2_verify_line v2_parse_line || exit 1

results_tmp=$(mktemp -d)
trap 'rm -r "$results_tmp"' EXIT

set +e
python3 test/external/run_wycheproof.py > "$results_tmp/wycheproof.json"
wycheproof_status=$?
python3 test/external/run_json_testsuite.py > "$results_tmp/json-testsuite.json"
json_status=$?
set -e

jq '{
  corpus,
  invalidCaseCount,
  totals,
  groups,
  findings
}' "$results_tmp/wycheproof.json"

jq '{
  corpus,
  inventory,
  buckets,
  acceptedYCount,
  snapshot,
  preParserCases,
  findings
}' "$results_tmp/json-testsuite.json"

if (( wycheproof_status != 0 || json_status != 0 )); then
  exit 1
fi
