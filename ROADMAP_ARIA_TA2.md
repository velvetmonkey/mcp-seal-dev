# Roadmap: ARIA Safeguarded AI TA2 (Cybersecurity)

How `seal` maps to ARIA's Safeguarded AI TA2 Cybersecurity call, and the plan
from the current shipped/proven state to a production-grade verified component
over the grant period.

## Framing

**Initial target: a Verified MCP Tool-Invocation Boundary.** A drop-in MCP
broker ensuring every externally effective `tools/call` from an AI agent
traverses a verified decision path before reaching the target server.

This is **Track 1 / Blue Team**: a production-grade, security-critical software
component whose key security properties are backed by machine-checked proofs,
under a clear threat model, validated by red teaming. It is **not** "an MCP side
project" and **not** pure tooling: the end-to-end security component (the
verified boundary) is the deliverable.

Maps to:
- **Example 4 (Verified Output Mediation for AI Inference)** — the primary fit. Every tool call passes a check chain before leaving the inference system; threat model includes prompt injection invoking tools without approval; proof target is structural non-bypass, not semantic filter correctness.
- **Example 6 (Verified Capability-Mediated Runtime for AI Agents)** — the ambitious follow-on; `seal` is a narrower, tractable instance at the MCP tool boundary, laddering toward a capability broker.

Theme: **the model is untrusted; the tool boundary is trusted only if proved.**

## Current state (evidence in hand, today)

- **v1 shipped** — native stdio sidecar, axiom-clean core (default-deny, approval requirement, target binding, one-shot). The honest demonstrator.
- **v2 proof-carrying core** — `parse -> validate -> serialize -> decide`, M1-M4 proven and axiom-clean; signature seam closed (`signed_parse_canonical`); A3 nonce + replay set + TTL cap landed. See [ASSURANCE_CASE.md](ASSURANCE_CASE.md).
- **CI on clean runners** — build + all axiom checks + integration test, green every commit.
- **End-to-end demonstrator** — seal x Canary (a real LangGraph agent): destructive call blocked at the gate, reproducible offline, proven in container CI. Machine-independent.
- **Claim discipline** — [THREAT_MODEL.md](THREAT_MODEL.md) names every residual.

## Grant-period plan (8-week sprints: ~6 build / 1 red-team / 1 review)

**Sprint 1 — Boundary hardening.** Production host integration beyond stdio; harden the policy loader; lock the canonical arg-tree hash + tool-version + [[manifest]]-digest. Deliver the v2 core as the enforced path.

**Sprint 2 — Signed approvals end to end.** Ed25519 over (target, session, expiry, nonce); key management story; the full canonical signed-message path in production, not just the proof.

**Sprint 3 — A2 differential harness (headline research output).** The hardest honest problem at this boundary, and we lead with it rather than defer it. `seal` classifies bytes; the upstream server executes bytes. If those interpretations diverge (the HTTP-request-smuggling / parser-differential family), the non-bypass theorem holds while the mediated event is the wrong event. This is the one residual a formal-methods referee will press, so it is a primary deliverable, not a footnote:
- **Measure** the differential: a fuzzing rig that feeds adversarial / ambiguous / non-canonical payloads to `seal`'s strict-subset parser and to real upstream MCP servers (Python, Node), and diffs the resulting target interpretation.
- **Bound** it: canonical arg-tree hash + tool-version + manifest-digest pinned at the boundary, so the equivalence assumption is explicit and the residual is a measured surface, not a hand-wave.
- **Publish** the methodology and corpus openly, as a reusable conformance oracle other Blue Teams can apply.

This turns the threat model's "standing red-team line" into a funded, evidenced work-package, the exact thing ARIA's Track 2 Red Team would otherwise attack.

**Sprint 4 — Capability classes.** Generalise the reference-monitor pattern to filesystem, network egress, command execution, credential release, and spend/rate budgets — the ladder toward Example 6's capability broker.

**Sprint 5 — Deployment + [[pilot]].** Integrate with a regulated-finance adoption partner using MCP in anger; gather red-team evidence under a real threat model; assurance case updated with field evidence.

**Sprint 6+ — Production assurance.** Conformance oracle, certified builds, audit-evidence packaging, upstreaming the spec.

Each sprint ends with: updated assurance case, red-team report, and open
publication of specs + proof artifacts.

## AI-enabled workflow (load-bearing, an ARIA criterion)

Proof production is AI-assisted via the Aristotle workflow over the Lean core,
with a kernel-checked axiom gate as ground truth. The throughput of
AI-assisted formalisation is what makes a small team credible at this scope; it
is central to the method, not decoration.

## Team plan

ARIA wants security/systems engineering + formal methods + AI-assisted
engineering + deployment judgement. Target structure:
- **Ben** — [[architecture]], MCP implementation, Lean workflow, product direction.
- **Formal-methods collaborator** — proof depth and review.
- **Security / red-team** — adversarial validation (distinct from the ARIA Track 2 red team).
- **Adoption / integration partner** — MCP in production (the commercial-advisor leg).

## IP and openness

Implementations retained/licensed as stated; **specifications and proof
artifacts published openly** (Apache-2.0). This satisfies ARIA's open-proof
requirement and matches the existing repo licence.

## What we will NOT claim

Per [THREAT_MODEL.md](THREAT_MODEL.md): never "safe agents", "semantic safety",
"prompt injection solved", "MCP secured end-to-end", or "the whole runtime is
verified". Only: **a formally verified structural approval boundary for MCP tool
invocation**, with the classifier and target-parser equivalence as named,
actively-reduced residuals.

## Key dates

- 1 July 2026 14:00 BST — submission deadline (single-stage, 5-page proposal).
- ~27 June — clarification-question cutoff.
- ~31 July — notification; ~1 September — kickoff.

Full submission mechanics and the pre-submission checklist live alongside this
roadmap in the project vault (`mcp-seal-bid-checklist`).
