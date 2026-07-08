# Architecture

`mcp-seal-dev` is the private Lean source of the Seal rulebook.

## Components

- `SealCore`: the small approval automaton, target hash type, live approval map, and safety theorems.
- `Seal`: policy classification, target-part encoding, target commitment, and channel parsing.
- `SealCore/Sha256.lean`: executable SHA-256 used for the deployed target commitment.
- `SealV2`: the v2 verified canonical core — parser, validation, serialization, and the proof-carrying decision pipeline (see [CLAIMS.md](../CLAIMS.md)).
- `Test`: executable tests and axiom-print entry points.

## v1 and v2

Two proof lines share this repo. **v1** (`SealCore/` + `Seal/`) is the target-commitment automaton that ships today as the stdio `seal` binary: policy-selected parts, SHA-256 target commitment, one-shot approvals. **v2** (`SealV2/`) is the verified canonical core that [CLAIMS.md](../CLAIMS.md) and [ASSURANCE_CASE.md](../ASSURANCE_CASE.md) describe: a proof-carrying `parse -> validate -> serialize -> decide` pipeline whose `Allow` path is a theorem, exported over C FFI (`Ffi.lean`, `rust/`; surface documented in [FFI.md](FFI.md)) to the Rust host. The milestone-by-milestone v2 build record is [v2/STATUS.md](../v2/STATUS.md); theorem names and locations are indexed in [PROOF-REFERENCE.md](PROOF-REFERENCE.md).

## Data flow

1. A policy chooses target parts from an MCP tool call (format: [POLICY.md](POLICY.md)).
2. `Seal.encodeParts` frames those parts as `<charCount>:<part>` strings.
3. `Seal.stableHashParts` hashes the encoded string as UTF-8 with SHA-256 and returns `TargetHash`.
4. `SealCore.step` compares that target against live approvals and returns allow or block.
5. Audit `certHash` paths use `Seal.auditHashParts`, a separate UInt64 helper kept out of the target commitment.

## Trust boundaries

This repo proves kernel properties. It does not deploy MCP transport, key management, browser code, or Rust host behavior. Those appear in the sibling repos and are tied back by conformance tests.
