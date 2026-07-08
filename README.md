# mcp-seal-dev

Private Lean workspace for the Seal mediation kernel: target commitments, approvals, and the safety rules that the rest of the product family must match. **Role:** The rulebook, proven.

![Lean](https://img.shields.io/badge/Lean-4.28.0-blue)
![Proofs](https://img.shields.io/badge/proofs-0%20sorry-brightgreen)
![License](https://img.shields.io/badge/license-Apache--2.0-blue)

**Seal is a proven checkpoint for AI agents.** When an AI agent tries to use a real tool over MCP (send money, delete a record, call an external service), Seal stands in the way and asks one question: did a human explicitly approve *this exact request*? No matching approval, no action. Every decision is written into a tamper-evident record you can check yourself. What makes Seal different from other guardrails: the core mediation rules aren't just tested, they're machine-checked theorems in Lean 4. The same decision logic then runs byte-for-byte in the Rust host you deploy, in the browser, and in the checker, each verified against that one proven rulebook.

That is the product line in one sentence: prove the rulebook, then check every body that runs it. Seal is built around MCP because MCP is where agent intent becomes an external effect. The proof says what the kernel must do; the conformance tests show that the Rust, wasm, and JavaScript artifacts used by the product family emit the same decisions and records over the shared corpus.

## What happens when an agent tries to delete production data

An agent asks an MCP server to run `db.execute` with a production delete. The kernel turns the policy-selected fields into a target commitment: SHA-256 over an injective netstring encoding of the tool and target parts. It then checks the approval map. If there is no live approval for that exact commitment, the automaton returns block. If there is one, it allows once and consumes the approval at the engine boundary.

This repository is where that rulebook lives. It is not the deployed host; it is the Lean source that defines the rule and proves the small, sharp properties the rest of Seal depends on.

## For evaluators and auditors

Seal's proof story is intentionally narrow. The Lean theorems cover the mediation kernel and selected model properties. The binaries and browser artifacts are connected to that proof by reproducible conformance tests, not by a theorem about every compiled instruction.

Two proof lines live in this repo. `SealV2/` is the **verified canonical core**: the proof-carrying `parse -> validate -> serialize -> decide` pipeline that [CLAIMS.md](CLAIMS.md) and [ASSURANCE_CASE.md](ASSURANCE_CASE.md) describe, with theorems `SealV2.non_bypass`, `SealV2.default_deny`, `SealV2.canonical_roundtrip`, and `SealV2.signed_parse_canonical`. `Seal/` plus `SealCore/` are the v1 target-commitment automaton that ships as the stdio `seal` binary. The milestone-by-milestone build record for v2 is [v2/STATUS.md](v2/STATUS.md).

Start with [docs/PROOF-REFERENCE.md](docs/PROOF-REFERENCE.md) for theorem names and file locations (v2 and v1), [docs/CONFORMANCE.md](docs/CONFORMANCE.md) for the byte-identity claim, [THREAT_MODEL.md](THREAT_MODEL.md) for the adversary and residuals, and [docs/TCB.md](docs/TCB.md) for what remains trusted.

Mandatory non-claims (canonical copy: [docs/LIMITATIONS.md](docs/LIMITATIONS.md)):

<!-- Canonical copy: docs/LIMITATIONS.md. Edit there first, then mirror here verbatim. -->
<!-- claims:begin -->
- Seal proves properties of the mediation KERNEL, not of the whole deployed system.
- Seal does NOT prove SHA-256 collision resistance in Lean; it is a named, scoped cryptographic assumption (A-CR).
- The deployed Rust / wasm / JS are NOT proven bug-free; they are tied to the proof by byte-exact conformance testing over a corpus, not for every possible input.
- Seal guarantees AUTHORIZATION match, not INTENT match: if a human approves a malicious-but-valid request, Seal will execute it.
- Seal does NOT prevent compromise of hosts, browsers, build systems, keys, operators, or downstream tools.
- Seal's audit chain is tamper-EVIDENT, not tamper-IMPOSSIBLE.
- Seal does NOT make the AI smarter or prevent hallucinations; it stops an unapproved effect.
- Axiom footprint {propext, Classical.choice, Quot.sound} is the minimal classical fragment; no extra axioms.
<!-- claims:end -->

## Verify in five minutes

```sh
bash c/build.sh
lake build
lake exe automaton_tests    # v1 automaton behaviour
lake exe axiom_check        # v1 safety theorems: axiom footprint
lake exe v2_parse_tests && lake exe v2_validate_tests && lake exe v2_serialize_tests && lake exe v2_lifecycle_tests
lake exe v2_m4_axiom_check  # v2 core: non_bypass, default_deny, decide_emit_unique, canonical_roundtrip, signed_parse_canonical
lake exe v2_m6_axiom_check  # v2 approval lifecycle: replay_denied, consume/TTL theorems
```

For the target commitment itself, inspect `Seal/Hash.lean` and `SealCore/Sha256.lean`: `stableHashParts` is SHA-256 over `encodeParts`, and the old UInt64 audit path is explicitly named `auditHashParts`.

## Demos

- `python3 demo/blocked_call_smoke.py` — block, approve, allow-once, block again, against a mock MCP server. Needs only python3 and a built `seal` (`bash c/build.sh && lake build`).
- `python3 demo/ttl_demo.py` — default-deny, one-shot tickets, and TTL expiry live against the official MCP reference server. Additionally needs Node/npx (fetches `@modelcontextprotocol/server-everything` once).

## The Seal family

_All Seal-family repositories are currently private; these links resolve only for authorised evaluators._

- [seal](https://github.com/velvetmonkey/seal): the private umbrella story, product map, and evaluator path.
- [mcp-seal-dev](https://github.com/velvetmonkey/mcp-seal-dev): The rulebook, proven.
- [seal-host](https://github.com/velvetmonkey/seal-host): The guard at the door.
- [seal-check](https://github.com/velvetmonkey/seal-check): Don't trust. Verify.
- [seal-live-demo](https://github.com/velvetmonkey/seal-live-demo): Watch it work.
- [seal-assurance-kit](https://github.com/velvetmonkey/seal-assurance-kit): Check your own boundary.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Threat model](THREAT_MODEL.md)
- [Assumptions](docs/ASSUMPTIONS.md)
- [Proof reference](docs/PROOF-REFERENCE.md)
- [Conformance](docs/CONFORMANCE.md)
- [Policy format, v1 binary](docs/POLICY.md)
- [FFI surface, v2 core](docs/FFI.md)
- [Trusted computing base](docs/TCB.md)
- [Glossary](docs/GLOSSARY.md)
- [Limitations](docs/LIMITATIONS.md)
- [Security policy](SECURITY.md)

## License

Apache-2.0. See [LICENSE](LICENSE).
