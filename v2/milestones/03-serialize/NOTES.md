# M3 serialize scaffold notes

Status: WIP scaffold for Aristotle proof handoff.

M3 defines `IsCanonical` as a standalone structural predicate over `AST`. It does not reference `parse` or `serialize`.

M3 parser tightening moved this predicate next to `AST` in `SealV2/Parser.lean` so public parser workers can strict-reject non-canonical results. `SealV2/Canonical.lean` remains a compatibility import shim.

`serializeAst` takes `{ast // IsCanonical ast}` and computes only on the AST value. `serialize` lifts from the M2 validation witness by using the new `ast_canonical` field on `ValidCapability`.

The M2 signed-message seam now uses the same canonical serializer:

```lean
signedMessageAst -> signedMessageCanonical? -> serializeAst
```

The prior `repr`-based stub has been removed.

## Proof obligations

`SealV2/SerializationTheorems.lean` contains named obligations for Groups A-D:

- Group A: parser canonicality and parser worker induction, proved after M3 parser tightening.
- Group B: serializer/parser roundtrip per AST shape, still WIP.
- Group C: `serializeAst` determinism and proof independence, still WIP.
- Group D: ValidCapability-backed roundtrip lift, still WIP.

Main remains blocked from merging this branch until all M3 `sorry`s are discharged.

## Claim discipline

`canonical_roundtrip` is seal self-consistency only. A2, target-parse equivalence, remains the per-server obligation, minimised by construction and the differential fixture, not eliminated.
