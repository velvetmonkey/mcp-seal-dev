# M3 serialize scaffold notes

Status: WIP scaffold for Aristotle proof handoff.

M3 defines `IsCanonical` as a standalone structural predicate over `AST`. It does not reference `parse` or `serialize`.

M3 parser tightening moved this predicate next to `AST` in `SealV2/Parser.lean` so public parser workers can strict-reject non-canonical results. `SealV2/Canonical.lean` remains a compatibility import shim.

`serializeAst` takes `{ast // IsCanonical ast}` and computes only on the AST value. `serialize` lifts from the M2 validation witness by using the new `ast_canonical` field on `ValidApproval`.

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
- Group D: ValidApproval-backed roundtrip lift, still WIP.

Main remains blocked from merging this branch until all M3 `sorry`s are discharged.

## Claim discipline

`canonical_roundtrip` is seal self-consistency only. A2, target-parse equivalence, remains the per-server obligation, minimised by construction and the differential fixture, not eliminated.

## Container roundtrip proof plan (accepted 2026-06-06)

Status: number/string/null/bool roundtrips PROVED and axiom-clean (`propext`, `Classical.choice`, `Quot.sound`). Only two sorrys remain in `SerializationTheorems.lean`: `serialize_roundtrip_array` and `serialize_roundtrip_object` (the fuel mutual induction). Aesop is a Lake dependency on this branch; no Mathlib.

Plan agreed by a 4-seat council (codex / gemini / claude / grok, harmonic, all valid JSON; accepted by Ben). Reusable by a hand proof and an Aristotle run alike.

### Structure

1. Induction: strong induction on `sizeOf` for the value-level lemma; plain structural `List` induction for the array/object helpers. These are NOT mutual: each list helper calls the value lemma at a strictly smaller `sizeOf`, so `decreasing_by` is trivial. Do not use raw `AST.rec` (no usable IH for the `List AST` / `List (String x AST)` payload).

2. Core accumulator-reverse helper, one per collection. Array shape:

   `parseArrayFuelUnchecked fuel acc (serializeArrayValue items ++ "]" ++ rest) = some (.array (acc.reverse ++ items), rest)`

   proved by induction on `items`, split THREE ways: `[]`, `[x]`, `x :: y :: ys`. `serializeArrayValue` closes a singleton with `]` but a longer list with `,`, so the singleton and cons-cons branches hit different parser arms. Do not try to prove the comma branch for an arbitrary `item :: rest`. Object helper is the same shape plus key / colon / dup-key handling.

3. Fuel: carry an explicit bound `fuel >= (serializeAstValue ast).length + 1` through the induction hypotheses. Do NOT prove a fuel-monotonicity lemma first (it is effectively the same proof twice). `parse` seeds `fuel = input.length + 1`, an exact match to the bound. (Codex and Claude both recommend explicit-bound over monotonicity; Gemini preferred monotonicity, Grok hybrid.)

4. Aesop: use it to close post-`simp only` canonicity `if`-guards, the empty-list base case, and small Bool / dup-key goals. It will NOT survive an un-reduced `match skipWs ...`; reduce those manually first.

### Landmines (handle before the parser proof)

- Un-reduced `match skipWs (serialized ++ rest)`. Prove `skipWs_of_no_ws_head` and "first serialized char is never whitespace" (`{`, `[`, `"`, `n`, `t`, `f`, `-`, digit, and the separators `,` `:` `]` `}`) and tag `@[simp]` so the outer match collapses.
- Canonicity-prefix preservation: `isCanonicalArray_append` / `isCanonicalObject_append`. The object dup-key prefix lemma is the predicted single biggest by-hand time sink.

### Ordered checklist

1. `skipWs_of_no_ws_head` + `serialize*_head_no_ws` simp lemmas.
2. `serializeArrayValue` nil / singleton / cons-cons `rfl` helpers (object analog).
3. `isCanonicalArray_append` / `isCanonicalObject_append` prefix preservation (object includes dup-key propagation).
4. Size lemmas: `x in items -> sizeOf x < sizeOf (.array items)` and the object analog.
5. Serialized-length / fuel bounds enough for `omega` to discharge fuel arithmetic.
6. `parseArray_serialize_acc` (the accumulator helper, 3-way split).
7. `parseObject_serialize_acc` (reuses the proved string roundtrip for keys).
8. `serialize_roundtrip_value` by `sizeOf` strong induction, dispatching to the proved primitives and to 6 / 7.
9. `serialize_roundtrip_array` and `serialize_roundtrip_object` as one-line corollaries of 8.

Estimate ~2-3 working days by hand. Parallel Aristotle run: project `93eeb7ed` (point it at steps 3, 6, 7). Verify `#print axioms` is exactly `[propext, Classical.choice, Quot.sound]` before importing anything. Anchors: council `25a8fd71`, plan checkpoints `ckpt-5f34ca93ab60381b` (evidence) and `ckpt-618bb4b2b7284d` (accepted reflection).
