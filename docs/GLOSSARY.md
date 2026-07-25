# Glossary

**MCP**: Model Context Protocol, the tool-call boundary Seal mediates.

**PDP**: Policy decision point. In Seal, the Lean kernel is the core PDP for guarded calls.

**Approval target**: The structured pieces of a tool call that a human approval is meant to bind: usually the tool name plus policy-selected argument fields.

**Target commitment**: The deployed digest of an approval target. Seal uses lowercase 64-hex SHA-256 over the injective `encodeParts` netstring encoding.

**`certHash`**: A legacy UInt64 per-kernel audit seal. It is not the target commitment and not the production record-chain hash.

**Hash chain**: A sequence where each record head commits to the previous head and the new payload. Seal uses this to make decision records tamper-evident.

**TCB**: Trusted computing base, the pieces that must be trusted rather than proven by the Lean theorem.

**A-CR**: The named *idealised* assumption that the target-commitment hash is perfectly injective — no two distinct inputs share a digest. This is strictly stronger than, and not the same as, computational collision resistance ("no collision exists" vs "a collision is infeasible to find"), and no fixed-output hash over unbounded inputs — including real SHA-256 — can satisfy it. Theorems conditional on A-CR hold in the idealised collision-free model only; the deployed guarantee is the trust assumption that no SHA-256 collision is known or findable for the inputs Seal hashes, which Lean does not prove. Canonical statement: [ASSUMPTIONS.md](ASSUMPTIONS.md).

**Conformance corpus**: The finite set of traces used to compare model, native, wasm, Rust, and JavaScript behavior byte-for-byte.
