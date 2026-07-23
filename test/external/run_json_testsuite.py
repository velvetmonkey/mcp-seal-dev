#!/usr/bin/env python3
"""Run vendored JSONTestSuite parsing cases through v2_parse_line."""

from __future__ import annotations

import argparse
import collections
import errno
import hashlib
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CORPUS = ROOT / "test/external/vendor/json-testsuite/test_parsing"
DEFAULT_EXE = ROOT / ".lake/build/bin/v2_parse_line"
DEFAULT_SNAPSHOT = ROOT / "test/external/json-y-accepted.txt"
EXPECTED_COUNTS = {"y": 95, "n": 188, "i": 35}
EXPECTED_MANIFEST_SHA256 = (
    "7e8dccd1635abaf1aa4f03bcb9e752cf3aa790104411cf2416775e2f8ed3c63f"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    parser.add_argument(
        "--no-snapshot-check",
        action="store_true",
        help="Emit the initial acceptance profile without comparing a snapshot.",
    )
    return parser.parse_args()


def pre_parser_reason(raw: bytes) -> str | None:
    if b"\x00" in raw:
        return "embedded NUL cannot be represented in argv"
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError as error:
        return (
            "invalid UTF-8 cannot be represented in a Lean String "
            f"(byte {error.start})"
        )
    return None


def parse(exe: Path, raw: bytes) -> bool:
    proc = subprocess.run(
        [str(exe), raw.decode("utf-8")],
        check=False,
        capture_output=True,
        text=True,
    )
    output = proc.stdout.strip()
    if proc.returncode != 0 or output not in {"some", "none"}:
        raise RuntimeError(
            f"parse socket failed (exit {proc.returncode}, "
            f"stdout={output!r}, stderr={proc.stderr.strip()!r})"
        )
    return output == "some"


def main() -> int:
    args = parse_args()
    files = sorted(path for path in args.corpus.iterdir() if path.is_file())
    manifest = "".join(
        f"{hashlib.sha256(path.read_bytes()).hexdigest()}  "
        f"test_parsing/{path.name}\n"
        for path in files
    ).encode("utf-8")
    actual_manifest_sha256 = hashlib.sha256(manifest).hexdigest()
    if actual_manifest_sha256 != EXPECTED_MANIFEST_SHA256:
        raise RuntimeError(
            "corpus manifest digest mismatch: expected "
            f"{EXPECTED_MANIFEST_SHA256}, got {actual_manifest_sha256}"
        )
    by_prefix = collections.Counter(path.name[0] for path in files)
    actual_counts = {prefix: by_prefix[prefix] for prefix in EXPECTED_COUNTS}
    if actual_counts != EXPECTED_COUNTS or len(files) != sum(EXPECTED_COUNTS.values()):
        raise RuntimeError(
            f"unexpected corpus inventory: {actual_counts}, total={len(files)}"
        )

    buckets: dict[str, collections.Counter[str]] = {
        prefix: collections.Counter() for prefix in EXPECTED_COUNTS
    }
    pre_parser_cases = []
    accepted_n_findings = []
    accepted_y = []

    for path in files:
        prefix = path.name[0]
        raw = path.read_bytes()
        reason = pre_parser_reason(raw)
        if reason is not None:
            buckets[prefix]["rejected-pre-parser"] += 1
            pre_parser_cases.append(
                {"file": path.name, "prefix": prefix, "reason": reason}
            )
            continue

        try:
            accepted = parse(args.exe, raw)
        except OSError as error:
            if error.errno != errno.E2BIG:
                raise
            buckets[prefix]["rejected-pre-parser"] += 1
            pre_parser_cases.append(
                {
                    "file": path.name,
                    "prefix": prefix,
                    "reason": "input exceeds the operating-system argv argument limit",
                }
            )
            continue
        bucket = "accepted" if accepted else "rejected-by-parser"
        buckets[prefix][bucket] += 1
        if prefix == "y" and accepted:
            accepted_y.append(path.name)
        if prefix == "n" and accepted:
            accepted_n_findings.append(
                {
                    "file": path.name,
                    "inputHex": raw.hex(),
                    "corpusVerdict": "must reject",
                    "sealVerdict": "accepted",
                }
            )

    snapshot = {
        "checked": not args.no_snapshot_check,
        "matches": None,
        "added": [],
        "removed": [],
    }
    if not args.no_snapshot_check:
        expected_y = sorted(
            line
            for line in args.snapshot.read_text(encoding="utf-8").splitlines()
            if line
        )
        accepted_set = set(accepted_y)
        expected_set = set(expected_y)
        snapshot.update(
            {
                "matches": accepted_y == expected_y,
                "added": sorted(accepted_set - expected_set),
                "removed": sorted(expected_set - accepted_set),
            }
        )

    output = {
        "corpus": str(args.corpus.relative_to(ROOT)),
        "inventory": actual_counts,
        "buckets": {
            prefix: {
                "total": sum(counts.values()),
                "rejectedByParser": counts["rejected-by-parser"],
                "rejectedPreParser": counts["rejected-pre-parser"],
                "accepted": counts["accepted"],
            }
            for prefix, counts in sorted(buckets.items())
        },
        "acceptedY": accepted_y,
        "acceptedYCount": len(accepted_y),
        "snapshot": snapshot,
        "preParserCases": pre_parser_cases,
        "findings": accepted_n_findings,
    }
    json.dump(output, sys.stdout, indent=2)
    sys.stdout.write("\n")

    snapshot_failed = snapshot["checked"] and not snapshot["matches"]
    return 1 if accepted_n_findings or snapshot_failed else 0


if __name__ == "__main__":
    sys.exit(main())
