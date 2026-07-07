#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def msg(mid: int, sql: str) -> str:
    return json.dumps(
        {
            "jsonrpc": "2.0",
            "id": mid,
            "method": "tools/call",
            "params": {
                "name": "db.execute",
                "arguments": {"database": "prod", "sql": sql},
            },
        },
        separators=(",", ":"),
    )


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        approvals = tmp / "approvals.ndjson"
        approvals.write_text("", encoding="utf-8")
        policy = tmp / "policy.json"
        example = json.loads((ROOT / "config" / "policy.example.json").read_text(encoding="utf-8"))
        example["approval"]["control_file"] = str(approvals)
        policy.write_text(json.dumps(example), encoding="utf-8")

        proc = subprocess.Popen(
            [
                str(ROOT / ".lake" / "build" / "bin" / "seal"),
                "--policy",
                str(policy),
                "--",
                "python3",
                str(ROOT / "test" / "integration" / "mock_mcp_server.py"),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )
        assert proc.stdin and proc.stdout

        proc.stdin.write(msg(1, "drop table users") + "\n")
        proc.stdin.flush()
        first = json.loads(proc.stdout.readline())
        print(json.dumps(first, indent=2))

        target = first["result"]["content"][0]["text"].split(": ", 1)[1].strip()
        approvals.write_text(json.dumps({"target": target}) + "\n", encoding="utf-8")

        proc.stdin.write(msg(2, "drop table users") + "\n")
        proc.stdin.flush()
        second = json.loads(proc.stdout.readline())
        print(json.dumps(second, indent=2))

        proc.stdin.write(msg(3, "drop table users") + "\n")
        proc.stdin.flush()
        third = json.loads(proc.stdout.readline())
        print(json.dumps(third, indent=2))

        proc.stdin.close()
        proc.wait(timeout=5)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
