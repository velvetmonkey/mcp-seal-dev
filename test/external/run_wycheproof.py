#!/usr/bin/env python3
"""Run the vendored Wycheproof Ed25519 vectors through v2_verify_line."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CORPUS = ROOT / "test/external/vendor/wycheproof/ed25519_test.json"
DEFAULT_EXE = ROOT / ".lake/build/bin/v2_verify_line"
EXPECTED_SHA256 = "70471c053c711731f2195ef4875b60ea7f5d6793939d99058ac12da810cb8e00"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    return parser.parse_args()


def verify(exe: Path, public_key: str, message: str, signature: str) -> bool:
    proc = subprocess.run(
        [str(exe), "verify_hex", public_key, message, signature],
        check=False,
        capture_output=True,
        text=True,
    )
    output = proc.stdout.strip()
    if proc.returncode != 0 or output not in {"true", "false"}:
        raise RuntimeError(
            f"verify socket failed (exit {proc.returncode}, "
            f"stdout={output!r}, stderr={proc.stderr.strip()!r})"
        )
    return output == "true"


def main() -> int:
    args = parse_args()
    corpus_bytes = args.corpus.read_bytes()
    actual_sha256 = hashlib.sha256(corpus_bytes).hexdigest()
    if actual_sha256 != EXPECTED_SHA256:
        raise RuntimeError(
            f"corpus digest mismatch: expected {EXPECTED_SHA256}, got {actual_sha256}"
        )
    corpus = json.loads(corpus_bytes)
    tests = [
        (group["publicKey"]["pk"], test)
        for group in corpus["testGroups"]
        for test in group["tests"]
    ]
    declared = corpus["numberOfTests"]
    if declared != len(tests):
        raise RuntimeError(f"corpus declares {declared} tests, loaded {len(tests)}")

    invalid_count = sum(test["result"] == "invalid" for _, test in tests)
    if invalid_count == 0:
        raise RuntimeError("wrong Wycheproof vintage: corpus has zero invalid tests")

    totals: dict[str, collections.Counter[str]] = collections.defaultdict(
        collections.Counter
    )
    groups: dict[tuple[str, str], collections.Counter[str]] = collections.defaultdict(
        collections.Counter
    )
    findings = []

    for public_key, test in tests:
        result = test["result"]
        accepted = verify(args.exe, public_key, test["msg"], test["sig"])
        verdict = "accepted" if accepted else "rejected"
        totals[result][verdict] += 1
        for flag in test["flags"] or ["(no flags)"]:
            groups[(result, flag)][verdict] += 1

        expected_accept = result == "valid"
        if accepted != expected_accept:
            findings.append(
                {
                    "tcId": test["tcId"],
                    "comment": test["comment"],
                    "flags": test["flags"],
                    "publicKey": public_key,
                    "msg": test["msg"],
                    "sig": test["sig"],
                    "corpusVerdict": result,
                    "sealVerdict": verdict,
                }
            )

    output = {
        "corpus": str(args.corpus.relative_to(ROOT)),
        "declaredTests": declared,
        "invalidCaseCount": invalid_count,
        "totals": {
            result: {
                "total": sum(counts.values()),
                "accepted": counts["accepted"],
                "rejected": counts["rejected"],
            }
            for result, counts in sorted(totals.items())
        },
        "groups": [
            {
                "corpusVerdict": result,
                "flag": flag,
                "total": sum(counts.values()),
                "accepted": counts["accepted"],
                "rejected": counts["rejected"],
            }
            for (result, flag), counts in sorted(groups.items())
        ],
        "findings": findings,
    }
    json.dump(output, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
