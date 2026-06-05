# seal v2 status

## M1 strict-subset parser

Status: implemented; local review gate passed.

M1 adds the v2 parser beside the shipped v1 sidecar. The v1 `seal` binary remains unchanged. The parser entrypoint is:

```lean
parse : RawBytes -> Option AST
```

The parser is total and fail-closed into `Option`. Malformed, ambiguous, duplicate-key, non-ASCII, partial, trailing-byte, or non-canonical numeric inputs return `none`.

### Canonical decimal grammar

M1 uses fixed decimal form rather than integers-only:

```text
number ::= "-"? int frac?
int    ::= "0" | [1-9][0-9]*
frac   ::= "." [0-9]* [1-9]
```

Rules:

- Exponents are rejected.
- Leading zeroes are rejected except the literal `0`.
- Negative zero is rejected.
- Fractions require at least one digit and must not end in `0`.
- Accepted examples: `0`, `12`, `-12`, `0.5`, `-0.5`, `0.05`, `12.34`.
- Rejected examples: `-0`, `00`, `01`, `1.0`, `1.20`, `1.`, `.5`, `1e3`.

### A2 number residuals for M3 and threat model

- No exponent support means values such as `6.022e23` and `1e-9` are intentionally unrepresentable and blocked.
- Numeric fidelity remains an A2 per-server obligation. A canonical decimal such as `0.12345678901234567890` can still diverge if the target server parses into `float64` or another bounded numeric representation.

### Review notes

- The parser differential is named as A2 and remains a per-server obligation.
- M1 does not claim target-parser agreement.
- M1 does not build Plan C transport.

## M2 constructive validation

Status: implemented; local review gate passed.

M2 adds:

```lean
validate : AST -> ApprovalState -> Option (Σ ast, ValidCapability ast state)
```

Validation is constructive. A successful result carries a `ValidCapability` witness, not a boolean. The witness contains the decoded request, matching tool spec, exact target binding, exact approval, session binding, `consumed = false`, expiry proof, and `SignatureVerified`.

### Signed message seam for M5

M2 defines the signed message as exactly:

```text
(target, session, expiry)
```

The message is represented as a canonical AST-shaped value through `signedMessageAst`. M2's crypto is stubbed by `stubSignatureFor`, but it signs/verifies this message shape only. M3 must serialize this same canonical message value; M5 must verify Ed25519 over those canonical bytes, not over a separate ad-hoc encoding.

### M6 atomic consume carry-forward

`ValidCapability` proves `approval.consumed = false`; M2 does not consume. M6 must make the validate-and-consume transition atomic inside `decide`, with no TOCTOU window between proving an approval live and consuming it. The M6 `state_monotonicity` theorem must connect directly to the `consumed = false` fact carried by the M2 witness.
