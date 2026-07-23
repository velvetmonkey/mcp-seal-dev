# Assurance Case

A structured argument that `seal`'s top-level security claim holds, with the
evidence for each sub-claim and the trusted base made explicit. This is an
honest assurance case, not a marketing claim: every leaf is either a
machine-checked theorem, a test, or a stated trust assumption.

## Top claim (G0)

> Every externally effective **guarded** `tools/call` from the agent traverses a
> verified decision path; an `Allow` is emitted only via `parse -> validate ->
> serialize`; all other requests are denied by default.

This is **structural non-bypass + complete mediation**, scoped to the MCP
`tools/call` boundary. It is explicitly **not** semantic safety, prompt-injection
prevention, or end-to-end runtime verification.

## Strategy

Decompose G0 into the seven security properties below. Discharge each by a Lean
theorem (machine-checked, axiom-gated in CI) or name it as a trust assumption.
The v2 proof-carrying core (`parse -> validate -> serialize -> decide`) is the
ARIA-relevant object; v1 is the shipped demonstrator. Theorem names and
file:line locations are indexed in
[docs/PROOF-REFERENCE.md](docs/PROOF-REFERENCE.md); the repo layout in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Sub-claims and evidence

| # | Property | Evidence | Status |
|---|---|---|---|
| 1 | **Complete mediation**: every guarded invocation passes the monitor | MITM transport: only `tools/call` inspected, all else relayed unchanged; `decide` is the single entry to Allow | **Architectural** (see note) |
| 2 | **Non-bypass**: `Allow` only via parse -> validate -> serialize | `non_bypass`, `decide_emit_unique` | Proven |
| 3 | **Default deny**: malformed / unmatched / expired / unsigned / replayed / non-canonical block | `default_deny`; M1 strict parser total + fail-closed (`parse raw = some ast -> IsCanonical ast`) | Proven |
| 4 | **Target binding**: approval for A cannot authorize B | `approval_binds_to_target` (v1 core); v2 `ValidCapability` witness binds exact target | Proven |
| 5 | **Session binding**: approval scoped to a session | `ValidCapability` witness binds session | Proven |
| 6 | **One-shot consume + approval expiry**: a consumed (v1) or expired approval is rejected at validation | v1 one-shot consumption; `valid_capability_has_unexpired_approval` | Proven |
| 6b | **Cross-message replay set + TTL cap**: a re-presented nonce is refused and stale approvals are capped | v2 A3 `validateAndConsumeWithStore`, `ttlWithinCap`, `nonceConsumed` over an in-memory, per-session fail-closed replay store (`listReplayStore`; cross-restart persistence is on the roadmap) | Host-enforced, fail-closed; the no-replay-after-consume lifecycle invariant (A5, state monotonicity) is on the sprint plan, not yet a theorem |
| 7 | **Canonical signed approval**: signature over exact canonical `(target, session, issuedAt, expiry, nonce)` bytes | `signed_parse_canonical` (byte-guard: `raw == serializeAst` + `eq_of_beq`) | Proven |

### Note on "complete mediation" (property 1): stated plainly

Properties 2-5, 6 and 7 are **machine-checked theorems** about the decision core.
Property 6b (cross-message replay set + TTL cap) is **host-enforced and
fail-closed**, not a Lean theorem: its no-replay-after-consume lifecycle
invariant (A5, state monotonicity) is on the sprint plan, and the host replay
store is part of the trusted base.
Property 1 is different in kind, and we say so rather than let a reviewer catch
it: complete mediation is an **architectural** guarantee, not a Lean theorem. It
holds because `seal` is the stdio man-in-the-middle, every guarded `tools/call`
on that path traverses `decide`, and `decide` is the single source of `Allow`.

What this guarantee is **conditional on**, and therefore in the trusted base:
the agent has no effective path to the tools that bypasses the monitored stdio
transport (no shell, no direct network, no alternate MCP config, no cached tool
handle, no in-process effect). Those out-of-band channels are explicitly
out of scope here (see [THREAT_MODEL.md](THREAT_MODEL.md)) and are the subject of
the Example 6 capability-broker follow-on, where confinement is enforced rather
than assumed. So: **non-bypass is proven; completeness is architectural and
scoped to the `tools/call` boundary.** We do not claim "complete" as a proof.

### Proof-carrying pipeline (v2)
- **M1 parse** `RawBytes -> Option AST`: total, fail-closed; canonical decimal grammar; `IsCanonical` proven on success.
- **M2 validate** `AST -> ApprovalState -> Option (Σ ast, ValidCapability ast state)`: success returns a proof-carrying witness binding request, tool spec, exact target, exact approval, session, `consumed = false`, expiry, signature.
- **M3 serialize**: one canonical serializer for output bytes and the signed-message shape; roundtrip + canonicality proven.
- **M4 decide** `RawBytes -> ApprovalState -> Decision`: single fail-closed emit path.

## Axiom footprint (the kept-honest TCB at the proof layer)

All discharged theorems depend only on:

```
[propext, Classical.choice, Quot.sound]
```

No `sorryAx`. No `Lean.ofReduceBool` (kernel `decide`, not `native_decide`). CI
gates this on every commit:

```
lake exe axiom_check
lake exe v2_m1_axiom_check
lake exe v2_m2_axiom_check
lake exe v2_m3_axiom_check
lake exe v2_m4_axiom_check
```
with grep guards that fail the build if `sorryAx` or `Lean.ofReduceBool` appear.

## Verification evidence beyond the kernel

- `lake exe automaton_tests`, `lake exe v2_parse_tests`, `v2_validate_tests`, `v2_serialize_tests`.
- `python3 test/integration/test_seal.py`, `seal` as a live stdio MITM against a mock server.
- Adversarial MCP fixtures (`test/v2/m1_*`, `m2_*`, `m3_*`).
- All of the above run on clean GitHub `ubuntu-latest` runners every commit (machine-independent, not author's box).
- End-to-end demonstrator (seal x Canary): a destructive `note/delete` blocked at the gate while a legitimate `note/create` is approved; reproducible offline, proven in container CI.

## Trusted base (explicit residuals)

Not proven, and stated so reviewers can weigh them:
1. **Classifier / policy completeness**: the runtime policy must identify the calls that matter.
2. **Target-parser equivalence (A2)**: `seal`'s parse of the target vs the upstream server's execution; minimised (canonical arg-tree hash + differential fixture), not eliminated. The standing red-team line.
3. **Approval origin**: control-file permissions (v1) / signing-key management (v2); and that the human understood what they approved.
4. **Lean compiler + kernel, child-process I/O, host/transport, OS.**
5. **Out-of-band effects** that never emit `tools/call` through `seal`.
6. **Revocation latency (revocation-by-re-sign).** `seal` has exactly one revocation channel: delete a `PrincipalKeyEntry` from the signed config's `principals` registry and re-sign. Verification is a registry lookup on the envelope's `keyId` (`SealV2/EffectEnvelope.lean:591`), so removing one entry revokes **that principal only** and leaves every other principal working. Granularity is per-principal, which is the finest unit that currently has meaning: sessions are config-scoped (`sessionGate` requires `e.session == state.session`, `SealV2/EffectEnvelope.lean:724`) and delegation is deliberately absent from the model. **The residual is latency, not granularity**: every revocation needs an authority signing ceremony plus a config push to every host, so revocation latency equals config-push latency. No fast path, no partial rollout, no "kill now and re-sign properly later". Accepted cost of keeping revocation on the authority plane rather than in request data (see THREAT_MODEL.md).

## Confidence statement

Within the stated boundary, the structural claim is machine-checked with a
minimal, audited axiom footprint. Outside it, the residuals are named and
addressed by claim discipline and adversarial testing, not concealed. See
[THREAT_MODEL.md](THREAT_MODEL.md) for the adversary and [ROADMAP_ARIA_TA2.md](ROADMAP_ARIA_TA2.md)
for the plan to drive the residuals down.
