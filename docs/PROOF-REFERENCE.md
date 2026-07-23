# Proof Reference

The file and line numbers below were verified by grep in this repository.

## V1 kernel (SealCore) theorems

| Claim | Theorem | Location | Axiom footprint |
|---|---|---|---|
| Default-deny events never allow | `SealCore.default_deny_never_allowed` | `SealCore/Safety.lean:8`; axiom print entry `Test/Axioms.lean:5` | `{propext, Quot.sound}` |
| Guarded calls need a matching live approval | `SealCore.no_allow_guarded_without_matching_approval_in_state` | `SealCore/Safety.lean:23`; axiom print entry `Test/Axioms.lean:6` | `{propext, Quot.sound}` |
| Approval for one target does not authorize another | `SealCore.approval_binds_to_target` | `SealCore/Safety.lean:29`; axiom print entry `Test/Axioms.lean:7` | `{propext, Classical.choice, Quot.sound}` |
| Consumed approvals are not live | `SealCore.consumed_approval_not_live` | `SealCore/Safety.lean:48` | Subset of `{propext, Classical.choice, Quot.sound}` in the host gate |
| Expired approvals are not live | `SealCore.expired_not_live` | `SealCore/Safety.lean:62` | Subset of `{propext, Classical.choice, Quot.sound}` in the host gate |
| Fresh approvals are live at mint time | `SealCore.fresh_approval_live` | `SealCore/Safety.lean:72` | Subset of `{propext, Classical.choice, Quot.sound}` in the host gate |

## V2 proof-carrying pipeline (the verified canonical core)

These are the theorems [CLAIMS.md](../CLAIMS.md) and [ASSURANCE_CASE.md](../ASSURANCE_CASE.md) rest on. All five are printed by `lake exe v2_m4_axiom_check`, whose `#guard_msgs` blocks make the exact axiom set a build-time kernel check, not just a runtime grep. Approval-lifecycle theorems are gated the same way by `lake exe v2_m6_axiom_check`.

| Claim | Theorem | Location | Axiom footprint |
|---|---|---|---|
| An `Allow` implies a parsed AST plus a `ValidApproval` witness, and the output is the canonical serialization of that witness | `SealV2.non_bypass` | `SealV2/DecideTheorems.lean:67` | `{propext, Classical.choice, Quot.sound}` |
| Output bytes are unreachable unless a `ValidApproval` term is built (default deny) | `SealV2.default_deny` | `SealV2/DecideTheorems.lean:77` | `{propext, Classical.choice, Quot.sound}` |
| The decide path emits exactly one output for a given input and state | `SealV2.decide_emit_unique` | `SealV2/DecideTheorems.lean:42` | `{propext, Classical.choice, Quot.sound}` |
| Canonical serialize/parse roundtrip is self-consistent and deterministic | `SealV2.canonical_roundtrip` | `SealV2/SerializationTheorems.lean:1257` | `{propext, Classical.choice, Quot.sound}` |
| The signature is checked over exactly the canonical signed-message bytes | `SealV2.signed_parse_canonical` | `SealV2/ValidationTheorems.lean:39` | `{propext, Classical.choice, Quot.sound}` |
| Approval lifecycle: nonce recorded on consume, replay denied, consume preserves liveness of others, only unexpired consumed, TTL capped | `SealV2.consume_records_nonce`, `SealV2.replay_denied`, `SealV2.consume_preserves_live`, `SealV2.consume_only_unexpired`, `SealV2.live_within_ttl_cap` | `SealV2/LifecycleTheorems.lean` (printed by `v2_m6_axiom_check`) | `{propext, Classical.choice, Quot.sound}` |

## Golden-path spec (scaffolder + shell reference cell + tamper fail-closed)

The theorem set behind [GOLDEN-PATH-SPEC.md](GOLDEN-PATH-SPEC.md); all printed by `lake exe axiom_check`.

| Claim | Theorem | Location | Axiom footprint |
|---|---|---|---|
| A scaffolded policy classifies every guarded-mode manifest tool `.guarded` for all arguments (never benign) | `Seal.scaffold_safety`, `Seal.scaffold_safety_not_benign` | `Seal/Scaffold.lean` | `{propext, Classical.choice, Quot.sound}` |
| Destructive / unknown / absent / conflicting annotations scaffold to guarded; scaffolder never emits deny | `Seal.dangerous_annotation_guarded`, `Seal.scaffoldMode_ne_deny` | `Seal/Scaffold.lean` | `{propext}` |
| Exact names only: a tool absent from the manifest is default-denied | `Seal.scaffold_unknown_tool_default_deny` | `Seal/Scaffold.lean` | `{propext, Classical.choice, Quot.sound}` |
| Readonly-annotated tools classify benign (golden-path liveness) | `Seal.scaffold_readonly_flows` | `Seal/Scaffold.lean` | `{propext, Classical.choice, Quot.sound}` |
| Shell cell: a destructive `shell_exec` call cannot reach the wire without a live approval for exactly its target | `Seal.shell_exec_requires_live_approval`, `Seal.shell_rm_rf_requires_live_approval` | `Seal/GoldenPath.lean` | `{propext, Classical.choice, Quot.sound}` |
| Shell cell: blocked on fresh state; flows after a matching unexpired approval; readonly leg never waits | `Seal.shell_rm_rf_blocks_on_fresh_state`, `Seal.shell_rm_rf_allows_with_fresh_approval`, `Seal.shell_read_flows` | `Seal/GoldenPath.lean` | `{propext, Classical.choice, Quot.sound}` |
| A policy whose signature does not verify classifies every call default-deny and blocks at the wire | `Seal.tampered_policy_fail_closed`, `Seal.tampered_policy_blocks` | `Seal/SignedPolicy.lean` | `{propext, Classical.choice, Quot.sound}` |
| With only unverifiable approvals in state, `decide` blocks every request | `SealV2.tampered_approvals_deny` | `SealV2/TamperTheorems.lean` | `{propext, Classical.choice, Quot.sound}` |
| Every Allow carries a witness approval whose signature verified — a tampered token can never be the passing witness | `SealV2.allow_implies_witness_signature_verified` | `SealV2/TamperTheorems.lean` | `{propext, Classical.choice, Quot.sound}` |

## V2.3 effect envelope — principal non-influence (K2)

Axiom footprints are pinned in-module by `#guard_msgs` blocks (build-time
kernel check). The runnable control is `lake exe principal_non_influence_show`
(RED if the decision value ever becomes principal-dependent).

| Claim | Theorem | Location | Axiom footprint |
|---|---|---|---|
| `effectStep` equals an expression in which the authenticated principal occurs only as a presence bit (`Option.isSome`) | `SealV2.Effect.effect_step_presence_form` | `SealV2/PrincipalNonInfluence.lean` | `{propext, Classical.choice, Quot.sound}` |
| Principal non-influence: for a fixed judged line and approval state, two authenticated, gate-passing runs produce the same decision, whatever their principals (model property; the presence channel remains principal-dependent) | `SealV2.Effect.principal_non_influence` | `SealV2/PrincipalNonInfluence.lean` | `{propext, Classical.choice, Quot.sound}` |
| Non-vacuity witness: two concrete DISTINCT authenticated principals instantiate the theorem, conditional only on two `ed25519Verify = true` facts (discharged at runtime by the SHOW control with real signatures) | `SealV2.Effect.witness_principal_non_influence` | `SealV2/PrincipalNonInfluence.lean` | `{propext, Classical.choice, Quot.sound}` |

## Host-level theorems

Host-level theorems such as `Host.step_forward_non_bypass`, `Host.Record.tamper_evident`, `Host.Encoding.encodeParts_injective`, `Host.CapabilityAdequacy.approval_authorizes_only_its_target'`, `Host.NonInterference.observe_noninterference`, and `Host.ReplayIsolation.replay_isolation_trace` live in `seal-host`; their line references are recorded in that repository's `docs/PROOF-REFERENCE.md`.
