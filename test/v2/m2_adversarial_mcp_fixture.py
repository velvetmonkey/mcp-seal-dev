#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

VALID = '{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"users","amount":12.34}}}'

BLOCK_CORPUS = [
    ("unknown tool", '{"method":"tools/call","params":{"name":"db.query","action":"write","arguments":{"database":"prod","table":"users","amount":12.34}}}'),
    ("unknown action", '{"method":"tools/call","params":{"name":"db.execute","action":"read","arguments":{"database":"prod","table":"users","amount":12.34}}}'),
    ("target mismatch", '{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"payments","amount":12.34}}}'),
    ("missing action", '{"method":"tools/call","params":{"name":"db.execute","arguments":{"database":"prod","table":"users","amount":12.34}}}'),
    ("wrong method", '{"method":"resources/read","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"users","amount":12.34}}}'),
]


def validate(raw: str) -> str:
    result = subprocess.run(
        ["lake", "exe", "v2_validate_line", "--", raw],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def main() -> int:
    got = validate(VALID)
    if got != "some":
        raise AssertionError(f"valid payload: expected some, got {got}")
    for name, raw in BLOCK_CORPUS:
        got = validate(raw)
        if got != "none":
            raise AssertionError(f"{name}: expected none, got {got}")
    print(f"M2 adversarial MCP fixture passed: {len(BLOCK_CORPUS)} rejected, 1 accepted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
