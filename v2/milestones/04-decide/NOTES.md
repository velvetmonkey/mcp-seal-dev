# M4 mediated decide and non-bypass — milestone notes

Status: complete; merged to `main`. Zero `sorry`, no `admit`, no `native_decide`,
axiom gate green.

## Lean source

- `SealV2/Decide.lean` — `Decision` (`Block` | `Allow CanonicalBytes`) and the single
  mediated entrypoint `decide : RawBytes -> ApprovalState -> Decision`. Fail-closed by
  exhaustive case analysis: `Block` if parse fails or validate fails; `Allow` only on
  bytes produced by `serialize` from the proof-carrying `validate` witness.
- `SealV2/DecideTheorems.lean` — `non_bypass`, `default_deny`, `decide_emit_unique`.
- `SealV2/ValidationTheorems.lean` — `signed_parse_canonical` (signed-approval
  canonicality closure).
- `Test/V2M4Axioms.lean` — build-breaking `#guard_msgs` axiom guard (the enforcement
  point; wired as exe `v2_m4_axiom_check`, a default target).

## Named theorems (all locked to `[propext, Classical.choice, Quot.sound]`)

- `non_bypass` — `decide raw state = Allow out` implies the output came through
  `parse` then a `ValidApproval` witness then `serialize`. No other path yields `Allow`.
- `default_deny` — parse-fail or validate-fail implies `decide = Block`.
- `decide_emit_unique` — `decide = Allow out` iff the full mediated path holds, and the
  emitted bytes are exactly `serialize` of that witness.
- plus `canonical_roundtrip`, `serialize_validCapability_roundtrip`, `signed_parse_canonical`.

See `axioms.txt` for the captured `#print axioms` evidence.

## Acceptance (end-to-end, not a unit stub)

`test/v2/m4_adversarial_mcp_fixture.py` drives the public `decide` entrypoint via the
`v2_decide_line` exe against the `Test.V2ValidationFixtures.baseState` approval state:

- the one legitimate mediated call → `Allow`;
- 15 adversarial / malformed / non-canonical / near-miss lines → `Block` each
  (parse-fail, trailing/exponent/leading-zero numerics, unknown tool/action, target
  and argument mismatches, missing action, wrong method).

`fixture-run.txt` is the pass record; `decide-corpus.txt` enumerates every line and its
decision. Reproduce all of it with `bash v2/milestones/04-decide/run.sh`.

## Claim discipline

`non_bypass` is **seal-internal complete mediation**: within seal, `Allow` is reachable
only through the single validated canonical path. This is NOT the A2 parser-differential
(target-server parse equivalence), which remains a per-server obligation, minimised by
construction (one canonical serializer, fail-closed strict parser), never eliminated.

Honest claim: **complete mediation modulo A1–A3, with A2 minimised by construction.**
A1 = channel exclusivity, A2 = server-parse equivalence, A3 = TCB. Signed-approval
verification (M2 stub today, real Ed25519 at M5) proves ORIGIN, not INTENT.
