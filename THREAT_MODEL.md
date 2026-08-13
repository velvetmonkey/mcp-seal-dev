# Threat Model

Scope of `seal`: a Lean-verified decision core for AI-agent `tools/call` inputs at the MCP
boundary, with channel exclusivity as an architectural assumption. This document states what `seal` defends, against whom, and what it
explicitly does **not** defend. Honesty about the boundary is part of the
product.

## System and trust boundary

```
[ AI host / agent ] <-- stdio JSON-RPC --> [ seal ] <-- stdio JSON-RPC --> [ real MCP server ]
 untrusted output reference monitor the capability (effects)
```

`seal` is a man-in-the-middle on the stdio transport. The host launches `seal`;
`seal` spawns the real MCP server as its child and relays JSON-RPC. Only
`tools/call` is inspected. `initialize`, `tools/list`, `resources/read`,
notifications, and responses pass through unchanged.

The protected asset is the **externally effective action**: a tool invocation
that mutates the world (deletes data, sends payment, runs a command, releases a
credential).

## Adversary

The **model is untrusted.** We assume the agent's output is adversarial:
directly malicious, or steered by indirect prompt injection in tool results,
retrieved documents, or upstream data. The adversary's goal is to cause an
externally effective tool invocation that no human approved.

Adversary capabilities assumed:
- Emit arbitrary JSON-RPC `tools/call` requests through the host.
- Craft malformed, ambiguous, non-canonical, duplicate-key, or oversized payloads.
- Replay a previously valid approval.
- Attempt to reuse an approval issued for target A against target B, or across sessions.
- Attempt to smuggle an approval record through the ordinary agent channel.

The adversary **cannot** (assumed): forge the approval origin (control-file
write permission in v1; the signing key in the v2 signed-approval path), nor
compromise the Lean-compiled decision core, the host transport, or the OS.

## In scope (defended, with machine-checked backing)

1. **Unapproved guarded invocation** blocked. Default-deny on unknown tools, unmatched patterns, missing target fields, explicit deny rules.
2. **Non-bypass.** An `Allow` can only arise through `parse -> validate -> serialize`; there is no other emit path.
3. **Malformed / non-canonical input** fails closed: the strict-subset parser returns `none` and the request is blocked.
4. **Target binding.** An approval for target A cannot authorize target B.
5. **Session binding.** An approval is scoped to its session.
6. **Replay / one-shot.** A consumed approval cannot be reused; nonce + replay set + TTL cap reject replays (v2 A3).
7. **Signature integrity (signed-approval path).** The signature is verified over the exact canonical `(target, session, issuedAt, expiry, nonce)` byte shape, not a normalized substitute, so a parser-differential cannot launder a non-canonical signed message past verification.

## Out of scope (trusted, not proven): stated plainly

- **Classifier / policy completeness and correctness.** The runtime JSON policy decides *which* calls are guarded and *what* the target is. `seal` proves the automaton's decisions are correct **given** the policy; it does not prove the policy captures every dangerous call or that "destructive" is correctly characterised. This is a human responsibility.
- **Target-parser equivalence (A2).** `seal` classifies bytes; the upstream server executes bytes. If `seal`'s view of "the target" diverges from what the server actually does (HTTP-request-smuggling family), the theorem stays true while the mediated event is the wrong event. This residual is **minimised** by canonical parsing + arg-tree hashing + a differential fixture, **not eliminated**. It is the standing red-team line and a Track B differential-harness obligation.
- **Approval origin.** v1 trusts OS file permissions on the control file; the v2 signed path trusts key management. `seal` proves an approval *binds* correctly, not that the human understood the operation they approved (UI ambiguity / injection at the approval step).
- **Out-of-band effects.** Anything that never emits `tools/call` through `seal`: shell access, direct network, alternate MCP configs, cached tool handles, spawned subprocesses, in-process calls.
- **Trusted computing base:** the Lean compiler and kernel, child-process I/O, the host/transport, and the OS.
- **Revocation latency.** `seal`'s only revocation channel is **revocation-by-re-sign**: delete a `PrincipalKeyEntry` from the signed config's `principals` registry and re-sign. This is deliberate. Revocation is a statement by the AUTHORITY about standing trust, whereas a field in a request is a statement by the REQUESTER, so routing revocation through request data would invert the trust direction and let a caller declare what it may be revoked as. A `revocation_subject` envelope field (F7) was designed and then **stripped in Stage B2** for exactly that reason.
  - **Granularity is per-principal, and that is not a gap.** Verification is a registry lookup on the envelope's `keyId` (`SealV2/EffectEnvelope.lean:591`); the registry is a list, so revoking one principal leaves all others working. Nothing finer currently has meaning: sessions are config-scoped (`sessionGate` requires `e.session == state.session`, `:724`) and delegation is absent from the model by design.
  - **The real residual is latency.** Every revocation requires an authority signing ceremony plus a config push to every host, so revocation latency equals config-push latency. There is no fast path and no partial rollout. Deployments that need sub-minute revocation must account for this at the operational layer; `seal` does not provide it.
  - **Reopen condition, recorded so it is not re-derived:** if delegation ever ships (F6 returning in a v4 with real structure, i.e. `on_behalf_of` / `parent_capability_ref` with attenuation), then sub-principal revocation becomes meaningful and this residual must be re-evaluated. The wrong-plane argument would still forbid a requester-declared subject; the right shape would be an authority-side revocation list keyed on something the envelope already binds. Ruled by Ben 2026-07-23: accept the strip now, revisit on that condition.

## Residual-risk summary

The honest one-line claim: `seal` is a **provably correct structural approval
boundary for MCP tool invocation**, not a proven-safe agent. It makes the
boundary explicit, inspectable, and machine-checkable. The classifier and the
target-parser equivalence are the named residuals, addressed by claim discipline
and adversarial red-teaming, not hidden.

See [ASSURANCE_CASE.md](ASSURANCE_CASE.md) for the evidence behind each in-scope
property and [ROADMAP_ARIA_TA2.md](ROADMAP_ARIA_TA2.md) for how the residuals are
driven down over the grant period.

This file is the canonical threat model for `mcp-seal-dev`.
`docs/THREAT-MODEL.md` and the M8 milestone snapshot
(`v2/milestones/08-threat-model/THREAT-MODEL.md`) defer to it.
