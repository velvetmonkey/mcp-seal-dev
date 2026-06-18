# M6 lifecycle / TTL — milestone notes

Status: complete; merged to `main`. Five named invariants proven over the replay store
state-machine. Zero `sorry`/`admit`/`native_decide`; axiom footprint unchanged.

## Named theorems (`SealV2/LifecycleTheorems.lean`)

All locked to `[propext, Classical.choice, Quot.sound]` by `Test/V2M6Axioms.lean` (exe
`v2_m6_axiom_check`); captured in `axioms.txt`.

- `consume_records_nonce` — **atomicity**: a successful `validateAndConsumeWithStore` records the
  nonce in the returned store. The witness is never handed back without the nonce persisted;
  `validateAndConsumeWithStore` is a single state-threading transition (`store → store'`), with no
  exposed intermediate state (see the `vacws_list` normal form).
- `replay_denied` — **single-use / replay**: re-presenting a just-consumed token to the post-state
  denies. The inserted entry survives pruning (the approval is unexpired) and matches, so the second
  `contains?` hits. Scope: SAME-`now` replay; post-expiry denial is `consume_only_unexpired`.
- `consume_preserves_live` — **state monotonicity**: a consumed entry that is still live is preserved
  across a successful consume. The live consumed-nonce set only grows; expired entries may be pruned.
- `consume_only_unexpired` — **expiry**: a successful consume implies `now ≤ approval.expiresAt`. A
  valid signature on an expired approval is still denied — origin authenticated is not authorization.
- `live_within_ttl_cap` — **TTL cap**: any approval treated as live is within the configured cap;
  over-cap approvals are rejected before they can be consumed.

## Design note — replay namespace re-key

M6 changed `ReplayNamespace.target : Target` to `ReplayNamespace.targetKey : String`
(`serializeTargetKey`, the M3 total canonical value serialiser on the target). Reason: the derived
`BEq` on the structured `AST` arguments is WF-recursive and does NOT reduce (no `rfl`/`decide`/eqn
lemmas), so `(ns == ns) = true` on the replay-detection path was unprovable. Keying on the canonical
string makes `ReplayNamespace` equality `String`-only — reducible, with reflexivity provable. This is
semantically equivalent (same target ⇒ same key, by M3 canonicality) and does not touch M1–M5 proofs
or their axiom footprint (re-verified clean). A false-equal key would be an availability concern, not
a safety hole; the structural serialiser is faithful.

## Honesty boundary (TCB assumptions)

- **A4 — serialized store access (host obligation).** The invariants hold GIVEN serialized/locked
  access to the store. `validateAndConsumeWithStore` is atomic IN THE MODEL (one transition); atomicity
  against real OS concurrency / preemption is a host obligation, NOT proven in Lean. The host must call
  `validateAndConsume` under serialized access.
- **A5 — host store refinement (carried to M7).** The proofs are over the concrete reference
  `listReplayStore`. The deployed host store (M7, Rust) is a different structure; its `contains?` /
  `insertConsumed` / `pruneExpired` must refine the reference semantics. That refinement is NOT yet
  proven — it is an explicit M7 obligation.
- Claim discipline: never "eliminated". `non_bypass` is seal-internal mediation; A2 (target-server
  parse equivalence) stays a per-server obligation, minimised by construction.

## Acceptance (real store machine)

`Test/V2Lifecycle.lean` (exe `v2_lifecycle_tests`) runs the corpus over the real functions: fresh
token Allows (clearing the real M5 Ed25519 signature via the re-vectored test vector — not a stub),
same nonce replayed Blocks, consumed nonce recorded, expired-valid-sig Blocks, ttl-over-cap rejected.
2 allowed / 3 blocked. `fixture-run.txt` is the pass record; `lifecycle-corpus.txt` enumerates cases.
Reproduce with `bash v2/milestones/06-lifecycle/run.sh`.
