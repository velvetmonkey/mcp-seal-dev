# M3 serialize scaffold notes

Status: WIP scaffold for Aristotle proof handoff.

M3 defines `IsCanonical` as a standalone structural predicate over `AST`. It does not reference `parse` or `serialize`.

`serializeAst` takes `{ast // IsCanonical ast}` and computes only on the AST value. `serialize` lifts from the M2 validation witness by using the new `ast_canonical` field on `ValidCapability`.

The M2 signed-message seam now uses the same canonical serializer:

```lean
signedMessageAst -> signedMessageCanonical? -> serializeAst
```

The prior `repr`-based stub has been removed.

## Proof obligations

`SealV2/SerializationTheorems.lean` intentionally contains named WIP `sorry`s for Groups A-D:

- Group A: parser canonicality and parser worker induction.
- Group B: serializer/parser roundtrip per AST shape.
- Group C: `serializeAst` determinism and proof independence.
- Group D: ValidCapability-backed roundtrip lift.

Main remains blocked from merging this branch until all M3 `sorry`s are discharged.

## Claim discipline

`canonical_roundtrip` is seal self-consistency only. A2, target-parse equivalence, remains the per-server obligation, minimised by construction and the differential fixture, not eliminated.
