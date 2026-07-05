# Proof Reference

The file and line numbers below were verified by grep in this repository.

| Claim | Theorem | Location | Axiom footprint |
|---|---|---|---|
| Default-deny events never allow | `SealCore.default_deny_never_allowed` | `SealCore/Safety.lean:8`; axiom print entry `Test/Axioms.lean:5` | `{propext, Quot.sound}` |
| Guarded calls need a matching live approval | `SealCore.no_allow_guarded_without_matching_approval_in_state` | `SealCore/Safety.lean:23`; axiom print entry `Test/Axioms.lean:6` | `{propext, Quot.sound}` |
| Approval for one target does not authorize another | `SealCore.approval_binds_to_target` | `SealCore/Safety.lean:29`; axiom print entry `Test/Axioms.lean:7` | `{propext, Classical.choice, Quot.sound}` |
| Consumed approvals are not live | `SealCore.consumed_approval_not_live` | `SealCore/Safety.lean:48` | Subset of `{propext, Classical.choice, Quot.sound}` in the host gate |
| Expired approvals are not live | `SealCore.expired_not_live` | `SealCore/Safety.lean:62` | Subset of `{propext, Classical.choice, Quot.sound}` in the host gate |
| Fresh approvals are live at mint time | `SealCore.fresh_approval_live` | `SealCore/Safety.lean:72` | Subset of `{propext, Classical.choice, Quot.sound}` in the host gate |

Host-level theorems such as `Host.step_forward_non_bypass`, `Host.Record.tamper_evident`, `Host.Encoding.encodeParts_injective`, `Host.CapabilityAdequacy.approval_authorizes_only_its_target'`, `Host.NonInterference.observe_noninterference`, and `Host.ReplayIsolation.replay_isolation_trace` live in `seal-host`; their line references are recorded in that repository's `docs/PROOF-REFERENCE.md`.
