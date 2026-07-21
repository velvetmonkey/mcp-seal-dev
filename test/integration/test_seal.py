#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def write_policy(tmp: Path, approval_file: Path) -> Path:
    policy = {
        "approval": {"control_file": str(approval_file), "ttl_seconds": 120},
        "tools": [
            {
                "name": "db.execute",
                "mode": "guarded",
                "match": {
                    "type": "contains_any_ci",
                    "arg": "sql",
                    "needles": ["drop", "delete", "truncate"],
                },
                "target": [{"full_arguments": True}],
            },
            {"name": "approve", "mode": "deny", "match": {"type": "always"}, "target": []},
        ],
    }
    path = tmp / "policy.json"
    path.write_text(json.dumps(policy), encoding="utf-8")
    return path


def rpc(mid, name, arguments):
    return {"jsonrpc": "2.0", "id": mid, "method": "tools/call", "params": {"name": name, "arguments": arguments}}


def run_case(messages, approval_records=()):
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        approvals = tmp / "approvals.ndjson"
        approvals.write_text("".join(json.dumps(r) + "\n" for r in approval_records), encoding="utf-8")
        policy = write_policy(tmp, approvals)
        proc = subprocess.Popen(
            [
                str(ROOT / ".lake" / "build" / "bin" / "seal"),
                "--policy",
                str(policy),
                "--",
                "python3",
                str(ROOT / "test" / "integration" / "mock_mcp_server.py"),
            ],
            cwd=ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )
        assert proc.stdin is not None
        assert proc.stdout is not None
        lines = []
        for msg in messages:
            proc.stdin.write(json.dumps(msg, separators=(",", ":")) + "\n")
            proc.stdin.flush()
            lines.append(json.loads(proc.stdout.readline()))
        proc.stdin.close()
        proc.wait(timeout=5)
        return lines


def main() -> int:
    blocked = run_case([rpc(1, "db.execute", {"database": "prod", "sql": "drop table users"})])
    assert blocked[0]["result"]["isError"] is True
    assert "approval required" in blocked[0]["result"]["content"][0]["text"]

    # Derive the approval target from seal's own block message so it never goes
    # stale on a hash-scheme change (mirrors demo/blocked_call_smoke.py).
    target = blocked[0]["result"]["content"][0]["text"].split(": ", 1)[1].strip()
    approved = run_case(
        [
            rpc(1, "db.execute", {"database": "prod", "sql": "drop table users"}),
            rpc(2, "db.execute", {"database": "prod", "sql": "drop table users"}),
        ],
        approval_records=[{"target": target}],
    )
    assert approved[0]["result"]["isError"] is False
    assert approved[1]["result"]["isError"] is True

    self_approval = run_case(
        [
            rpc(1, "approve", {"target": target}),
            rpc(2, "db.execute", {"database": "prod", "sql": "drop table users"}),
        ]
    )
    assert self_approval[0]["result"]["isError"] is True
    assert self_approval[1]["result"]["isError"] is True
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
