#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    proc = subprocess.run(
        ["lake", "exe", "v2_serialize_line"],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    seen = {}
    for line in proc.stdout.splitlines():
        if "\t" not in line:
            continue
        name, payload = line.split("\t", 1)
        seen[name] = json.loads(payload)

    assert seen["object"] == {"tool": "db.execute", "amount": 12.34}
    assert seen["array"] == [None, True, "x", -12.34]
    assert seen["validated"]["method"] == "tools/call"
    assert seen["validated"]["params"]["name"] == "db.execute"
    assert seen["validated"]["params"]["arguments"]["amount"] == 12.34
    print("M3 differential serialization fixture passed")


if __name__ == "__main__":
    main()
