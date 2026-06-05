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
    for name, raw in BLOCK_CORPUS:
        got = parse(raw)
        if got != "none":
            raise AssertionError(f"{name}: expected none, got {got}")
    for name, raw in ALLOW_CORPUS:
        got = parse(raw)
        if got != "some":
            raise AssertionError(f"{name}: expected some, got {got}")
    print(
        f"M1 adversarial MCP fixture passed: {len(BLOCK_CORPUS)} rejected, "
        f"{len(ALLOW_CORPUS)} accepted"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
