#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

"""M4 end-to-end adversarial fixture.

Drives the public `decide` entrypoint (via the `v2_decide_line` exe) against the
fixture `baseState` from `Test.V2ValidationFixtures`. The single legitimate
mediated call must `Allow`; every adversarial / malformed / non-canonical line
must `Block`.

This exercises the M4 mediation claim operationally:
  - `default_deny`: any parse-fail or validate-fail path returns `Block`.
  - `non_bypass`:   `Allow` is reachable ONLY through the one fully-validated
                    canonical path; no malformed or near-miss request slips through.

Claim discipline: this is seal-INTERNAL complete mediation, modulo A1-A3. It is
NOT the A2 parser-differential (target server parse-equivalence), which stays a
per-server obligation, minimised by construction, never eliminated.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

# The one legitimate mediated call: matches baseState's target exactly
# (db.execute / write / prod / users / amount 12.34), live approval, right session.
VALID = '{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"users","amount":12.34}}}'

# Every entry must Block. Grouped by the mediation failure it probes.
BLOCK_CORPUS = [
    # --- parse-fail (default_deny via parse = none) ---
    ("truncated json", '{"method":"tools/call"'),
    ("not json", 'definitely not json'),
    ("empty", ''),
    ("trailing bytes", '{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"users","amount":12.34}}} trailing'),
    # --- non-canonical numerics (parser fail-closed, no normalisation) ---
    ("trailing-zero fraction", '{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"users","amount":12.340}}}'),
    ("integer-as-decimal 1.0", '{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"users","amount":1.0}}}'),
    ("exponent form", '{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"users","amount":1e3}}}'),
    ("leading zero", '{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"users","amount":01.34}}}'),
    # --- validate-fail (default_deny via validate = none) ---
    ("unknown tool", '{"method":"tools/call","params":{"name":"db.query","action":"write","arguments":{"database":"prod","table":"users","amount":12.34}}}'),
    ("unknown action", '{"method":"tools/call","params":{"name":"db.execute","action":"read","arguments":{"database":"prod","table":"users","amount":12.34}}}'),
    ("target table mismatch", '{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"payments","amount":12.34}}}'),
    ("target db mismatch", '{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"staging","table":"users","amount":12.34}}}'),
    ("amount mismatch", '{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"users","amount":99.99}}}'),
    ("missing action", '{"method":"tools/call","params":{"name":"db.execute","arguments":{"database":"prod","table":"users","amount":12.34}}}'),
    ("wrong method", '{"method":"resources/read","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"users","amount":12.34}}}'),
]


def decide(raw: str) -> str:
    result = subprocess.run(
        ["lake", "exe", "v2_decide_line", "--", raw],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def dump() -> int:
    """Print every corpus line and the decision `decide` returns for it."""
    print(f"{'DECISION':<6} {'EXPECT':<6} CASE")
    print(f"{decide(VALID):<6} {'Allow':<6} legitimate mediated call")
    for name, raw in BLOCK_CORPUS:
        print(f"{decide(raw):<6} {'Block':<6} {name}")
    return 0


def main() -> int:
    if "--dump" in sys.argv[1:]:
        return dump()
    got = decide(VALID)
    if got != "Allow":
        raise AssertionError(f"valid mediated call: expected Allow, got {got!r}")
    for name, raw in BLOCK_CORPUS:
        got = decide(raw)
        if got != "Block":
            raise AssertionError(f"{name}: expected Block, got {got!r}")
    print(f"M4 adversarial MCP fixture passed: {len(BLOCK_CORPUS)} blocked, 1 allowed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
