# M1 parse notes

M1 implements the first v2 compiler-stage contract:

```lean
parse : RawBytes -> Option AST
```

The parser accepts a strict JSON subset and rejects malformed or ambiguous raw bytes with `none`. This is a parser boundary for later validation and canonical serialization; it is not wired into the v1 stdio relay in M1.

## Strict subset

- Objects reject duplicate keys.
- Strings are printable ASCII only and reject escapes.
- Arrays and objects reject trailing commas.
- Top-level trailing bytes reject.
- Whitespace is allowed between JSON tokens.
- Numbers use fixed canonical decimal form.

## Number grammar

```text
number ::= "-"? int frac?
int    ::= "0" | [1-9][0-9]*
frac   ::= "." [0-9]* [1-9]
```

Accepted examples: `0`, `12`, `-12`, `0.5`, `-0.5`, `0.05`, `12.34`.

Rejected examples: `-0`, `00`, `01`, `1.0`, `1.20`, `1.`, `.5`, `1e3`.

## M3 tightening annotation

During M3, Aristotle identified parser-canonicality counterexamples around worker-level number parsing, including `-0.0` and `-00.0`. The M3 branch tightened the public parser workers to strict-reject every non-canonical AST result rather than normalising.

The accepted numeric grammar remains the locked M1 grammar above. Regression fixtures now cover `-0`, `-0.0`, `-00.0`, `00`, `01`, `-00`, `1.0`, `1.20`, `1.`, `.5`, `1e3`, `1E3`, and `6.022e23`.

## A2 carry-forwards

- Exponent notation is out of the strict subset and blocks.
- Numeric fidelity is part of the A2 per-server discharge obligation for M3 and the threat-model doc.
- `canonical_roundtrip` in M3 must be described as seal self-consistency only, not target-parser agreement.
