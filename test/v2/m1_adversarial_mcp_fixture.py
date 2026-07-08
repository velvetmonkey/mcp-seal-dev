#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

BLOCK_CORPUS = [
    ("duplicate tool keys", '{"jsonrpc":"2.0","id":1,"method":"tools/call","method":"resources/read"}'),
    ("non-ascii tool name", '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"db.éxecute"}}'),
    ("escaped argument string", '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"db.execute","arguments":{"sql":"drop\\n table users"}}}'),
    ("negative zero target value", '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"pay","arguments":{"amount":-0}}}'),
    ("leading zero amount", '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"pay","arguments":{"amount":01}}}'),
    ("trailing fractional zero", '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"pay","arguments":{"amount":1.20}}}'),
    ("exponent value", '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"pay","arguments":{"amount":1e-9}}}'),
    ("trailing bytes", '{"jsonrpc":"2.0","id":1,"method":"tools/call"} // smuggle'),
    ("partial json", '{"jsonrpc":"2.0","id":1,"method":"tools/call"'),
]

ALLOW_CORPUS = [
    ("canonical guarded call", '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"db.execute","arguments":{"amount":12.34,"dryRun":false}}}'),
]


def parse(raw: str) -> str:
    result = subprocess.run(
        ["lake", "exe", "v2_parse_line", "--", raw],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def main() -> int:
    # Reclassified 2026-07-08: commit 0b2c1f4 ("Extend SealV2 canonical string
    # grammar to full escaped Unicode") intentionally taught the parser to accept a
    # valid escaped-newline string argument, so it now parses to "some". Proved
    # behaviour, not a regression: the policy gate still blocks the "drop" content
    # downstream, so parser acceptance loses no safety. Every other adversarial
    # case below is still rejected.
    now_allowed = {"escaped argument string"}
    for name, raw in BLOCK_CORPUS:
        got = parse(raw)
        expected = "some" if name in now_allowed else "none"
        if got != expected:
            raise AssertionError(f"{name}: expected {expected}, got {got}")
    for name, raw in ALLOW_CORPUS:
        got = parse(raw)
        if got != "some":
            raise AssertionError(f"{name}: expected some, got {got}")
    reclassified = len(now_allowed)
    print(
        f"M1 adversarial MCP fixture passed: {len(BLOCK_CORPUS) - reclassified} rejected, "
        f"{len(ALLOW_CORPUS) + reclassified} accepted "
        f"({reclassified} reclassified allow after grammar extension 0b2c1f4)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
