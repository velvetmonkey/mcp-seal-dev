#!/usr/bin/env python3
"""Compare the Lean numeric gate with Node and Python JSON readers."""

from __future__ import annotations

import json
import math
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
LEAN_EXE = ROOT / ".lake" / "build" / "bin" / "numeric_agreement_show"

LITERALS = [
    "1e17", "100000000000000000", "1e16", "10000000000000000",
    "9007199254740992",
    "0.1", "1.5e3", "1E2", "1.0", "100.0", "2.5", "1e2", "3.14159",
    "0.30000000000000004", "-0.1",
    "-0", "0", "0.0", "-0.0", "0e0", "-0e-0",
    "5e-324", "1e-400", "1.7976931348623157e308", "1e309", "1e308",
    "9007199254740993", "9007199254740991",
    "123456789012345678901234567890", "1.7976931348623158e308",
    "0.1000000000000000055511151231257827",
    "-1e9999", "1e-324", "0.10000000000000001",
    "100000000000000001", "9999999999999999", "999999999999999",
    "1.0000000000000002", "2.2250738585072014e-308", "1e-323",
    "9999999999999990", "90071992547409910", "999999999999999000",
]

NODE_PROGRAM = (
    "const v=JSON.parse(process.argv[1]); "
    "console.log(JSON.stringify(v)); "
    "console.log(Number.isFinite(v)&&Number.isInteger(v)?v.toFixed(0):JSON.stringify(v))"
)
PYTHON_PROGRAM = (
    "import json,sys; v=json.loads(sys.argv[1]); "
    "print(repr(v)); print(type(v).__name__)"
)


def run(command: list[str]) -> str:
    completed = subprocess.run(
        command, cwd=ROOT, check=True, text=True, capture_output=True, timeout=20
    )
    return completed.stdout.rstrip("\n")


def kernel_verdicts() -> dict[str, bool]:
    output = run([str(LEAN_EXE), *LITERALS])
    verdicts: dict[str, bool] = {}
    for line in output.splitlines():
        literal, raw = line.split("\t", 1)
        if raw == "(some true)":
            verdicts[literal] = True
        elif raw == "(some false)":
            verdicts[literal] = False
        else:
            raise RuntimeError(f"non-Boolean kernel result for {literal}: {raw}")
    if list(verdicts) != LITERALS:
        raise RuntimeError("kernel output did not match the ordered corpus")
    return verdicts


def readers_agree(node_text: str, python_value: object) -> bool:
    if node_text == "null":
        return False
    node_value = json.loads(node_text)
    if isinstance(python_value, int):
        numerator, denominator = float(node_value).as_integer_ratio()
        return denominator == 1 and numerator == python_value
    if isinstance(python_value, float):
        if not math.isfinite(python_value):
            return False
        node_float = float(node_value)
        if node_float == 0.0 and python_value == 0.0:
            return True
        return node_float.as_integer_ratio() == python_value.as_integer_ratio()
    raise TypeError(f"unexpected Python JSON number type: {type(python_value)!r}")


def main() -> int:
    if not LEAN_EXE.is_file():
        print(f"missing Lean executable: {LEAN_EXE}", file=sys.stderr)
        return 2
    verdicts = kernel_verdicts()
    under: list[str] = []
    over: list[str] = []
    print("literal\tkernel\tnode\tnode_exact\tpython\tpython_type\tagree\tcorrect")
    for literal in LITERALS:
        node_lines = run(["node", "-e", NODE_PROGRAM, "--", literal]).splitlines()
        python_output = run(["python3", "-c", PYTHON_PROGRAM, literal])
        python_lines = python_output.splitlines()
        if len(node_lines) != 2:
            raise RuntimeError(f"unexpected Node output for {literal}: {node_lines!r}")
        if len(python_lines) != 2:
            raise RuntimeError(f"unexpected Python output for {literal}: {python_output!r}")
        node_text, node_exact = node_lines
        python_text, python_type = python_lines
        python_value = json.loads(literal)
        agree = readers_agree(node_text, python_value)
        verdict = verdicts[literal]
        if verdict and not agree:
            under.append(literal)
        if not verdict and agree:
            over.append(literal)
        print(
            f"{literal}\t{'ACCEPT' if verdict else 'REFUSE'}\t{node_text}\t"
            f"{node_exact}\t{python_text}\t{python_type}\t"
            f"{str(agree).upper()}\t{str(verdict == agree).upper()}"
        )
    print(f"LITERALS_CHECKED={len(LITERALS)}")
    print(f"UNDER_REFUSALS={json.dumps(under, separators=(',', ':'))}")
    print(f"OVER_REFUSALS={json.dumps(over, separators=(',', ':'))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
