#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def wire(literal: str, request_id: int) -> str:
    return (
        f'{{"jsonrpc":"2.0","id":{request_id},"method":"tools/call",'
        '"params":{"name":"external.json_corpus","arguments":['
        + literal
        + "]}}"
    )


def main() -> int:
    probe_only = sys.argv[1:] == ["--probe"]
    cases = [
        ("MEASURED", "-1e9999", 1, False, "-1e9999"),
        ("NEGATIVE CTRL", "1e308", 2, True, "observer received v=1e+308"),
        ("BOUNDARY SAFE", "9007199254740991", 3, True,
         "observer received v=9007199254740991"),
        ("BOUNDARY UNSAFE", "9007199254740993", 4, False,
         "9007199254740993"),
    ]
    if probe_only:
        cases = cases[:1]
    with tempfile.TemporaryDirectory() as directory:
        tmp = Path(directory)
        approval_file = tmp / "approvals.ndjson"
        approval_file.write_text("", encoding="utf-8")
        policy_file = tmp / "policy.json"
        policy_file.write_text(json.dumps({
            "approval": {
                "control_file": str(approval_file),
                "ttl_seconds": 120,
            },
            "tools": [{
                "name": "external.json_corpus",
                "mode": "allow",
                "match": {"type": "always"},
                "target": [],
            }],
        }), encoding="utf-8")

        process = subprocess.Popen(
            [
                str(ROOT / ".lake" / "build" / "bin" / "seal"),
                "--policy", str(policy_file), "--",
                "node", str(ROOT / "test" / "integration" /
                            "numeric_agreement_observer.mjs"),
            ],
            cwd=ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )
        assert process.stdin is not None
        assert process.stdout is not None
        for label, literal, request_id, accepted, needle in cases:
            request = wire(literal, request_id)
            process.stdin.write(request + "\n")
            process.stdin.flush()
            response_line = process.stdout.readline().rstrip("\n")
            response = json.loads(response_line)
            text = response["result"]["content"][0]["text"]
            is_error = response["result"]["isError"]
            if not probe_only and (is_error == accepted or needle not in text):
                raise AssertionError(
                    f"{label}: accepted={accepted}, response={response_line}"
                )
            if not probe_only and not accepted and "approval required" in text:
                raise AssertionError(f"{label}: refusal became an approval offer")
            print(f"{label} REQUEST: {request}")
            print(f"{label} RESPONSE: {response_line}")

        process.stdin.close()
        return_code = process.wait(timeout=5)
        # The standalone host deliberately kills its child at stdin EOF and
        # returns that wait status (137 on Linux); this is its existing shutdown
        # contract, not a request-path failure.
        if return_code not in (0, 137):
            raise RuntimeError(f"seal exited {return_code}")
    print("NUMGUARD-ABLATION-PROBE: COMPLETE" if probe_only
          else "NUMGUARD-INTEGRATION-RUN: GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
