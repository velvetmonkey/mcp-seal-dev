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

M3 scaffold strengthening: `ValidCapability` now carries `ast_canonical : IsCanonical ast`. This is additive to M2's witness facts; the six M2 witness lemmas remain unchanged. The strengthening is required so `serialize` can be proof-gated without making canonicality circular through `parse` or `serialize`.

### M6 atomic consume carry-forward

`ValidCapability` proves `approval.consumed = false`; M2 does not consume. M6 must make the validate-and-consume transition atomic inside `decide`, with no TOCTOU window between proving an approval live and consuming it. The M6 `state_monotonicity` theorem must connect directly to the `consumed = false` fact carried by the M2 witness.

## M3 canonical serialization

Status: complete; merged to `main`. All M3 obligations are discharged with zero `sorry`, no `native_decide`, and the axiom gate is green.

M3 adds a standalone structural canonicality predicate and proof-gated serialization:

```lean
IsCanonical : AST -> Prop
serializeAst : {ast // IsCanonical ast} -> CanonicalBytes
serialize : (Σ ast, ValidCapability ast state) -> CanonicalBytes
```

`IsCanonical` is structural only. It does not reference `parse` or `serialize`. `serializeAst` computes on the AST value only, so proof terms cannot influence emitted bytes.

The M2 signed-message stub now routes through the same `serializeAst` path on `signedMessageAst`; the previous `repr` stub is removed. There is one canonical serializer for both output bytes and signed-message bytes.

M3 scaffold contained named obligations for Groups A-D in `SealV2/SerializationTheorems.lean`. All are now proved: Group A canonicality after parser tightening, and Groups B-D the value, array, and object serialization roundtrips via fuel-based mutual induction. The keystone `value_roundtrip_size` closes the recursion. Zero `sorry`, no `native_decide`.

### M3 axiom footprint (verified)

`lake exe v2_m3_axiom_check` confirms all 14 M3 theorems depend only on `[propext, Classical.choice, Quot.sound]`. No `sorryAx`. Covered theorems include `parse_returns_canonical`, `serialize_roundtrip_{null,bool,number,string,array,object}`, `canonical_roundtrip`, `serializeAst_deterministic`, and `serialize_validCapability_roundtrip`.

Claim discipline: `canonical_roundtrip` means seal self-consistency only. A2, target-parse equivalence, remains the per-server obligation, minimised by construction and by the differential fixture, not eliminated.

### M3 parser tightening

Aristotle found that the original Group A worker obligations were not strong enough around number parsing counterexamples such as `-0.0` and `-00.0`. M3 tightened the public parser workers so every successful public parse worker result is guarded by `IsCanonical`.

The parser remains fail-closed and does not normalise. Non-canonical numeric forms such as `-0`, `-0.0`, `-00.0`, `00`, `01`, `-00`, `1.0`, `1.20`, `1.`, `.5`, `1e3`, `1E3`, and `6.022e23` return `none`. The strict Group A theorem `parse raw = some ast -> IsCanonical ast` is now proved with no `sorry`.

## M4 mediated decide and non-bypass

Status: complete on `feat/v2-m4-nonbypass`. All M4 obligations are discharged with zero `sorry`, no `admit`, no `native_decide`, and the axiom gate is green.

M4 adds the single mediated decision path:

```lean
Decision.Block : Decision
Decision.Allow : CanonicalBytes -> Decision
decide : RawBytes -> ApprovalState -> Decision
```

`decide` is fail-closed by exhaustive case analysis. It blocks if parsing fails or validation fails, and it allows only bytes produced by `serialize` from the proof-carrying `validate` witness.

M4 proves:

```lean
non_bypass :
  decide raw state = Decision.Allow out ->
    ∃ ast, parse raw = some ast ∧
      ∃ w : ValidCapability ast state, out = serialize ⟨ast, w⟩

default_deny :
  (parse raw = none ∨
    ∃ ast, parse raw = some ast ∧ validate ast state = none) ->
  decide raw state = Decision.Block

decide_emit_unique :
  decide raw state = Decision.Allow out ↔
    ∃ ast, parse raw = some ast ∧
      ∃ w : ValidCapability ast state,
        validate ast state = some ⟨ast, w⟩ ∧
          out = serialize ⟨ast, w⟩
```

### M4 axiom footprint (verified)

`lake exe v2_m4_axiom_check` is now a build-breaking guard, not just a printer. It locks `canonical_roundtrip`, `serialize_validCapability_roundtrip`, `decide_emit_unique`, `non_bypass`, and `default_deny` to `[propext, Classical.choice, Quot.sound]`.

## Signed-approval canonicality closure

Status: implemented; one theorem is intentionally left for Aristotle.

The general JSON-RPC parser remains whitespace-tolerant. The signed-approval path is stricter:

```lean
signedParse : RawBytes -> Option {ast // IsCanonical ast}
signedMessageRawFor : SignedMessage -> RawBytes
```

`signedParse` parses the raw signed-message bytes and then rejects unless `raw == serializeAst parsedAst`. `Approval` now carries `signedMessageRaw`, and `verifySignature` checks the signature against that exact raw field only after `signedParse` accepts it and the parsed signed-message AST matches `(target, session, expiry)`.

This closes the reviewed bypass where non-canonical bytes could be accepted by parsing, normalised to canonical bytes, and then verified over the normalised payload. Non-canonical witnesses such as trailing whitespace, leading whitespace, and interior insignificant whitespace are rejected by the signed path and make `decide` return `Block`.

Deferred proof obligation:

```lean
signed_parse_canonical :
  signedParse raw = some ast -> raw = serializeAst ast
```

This theorem is intentionally tagged in Lean for Aristotle as the remaining proof obligation.
