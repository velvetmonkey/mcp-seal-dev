# Architecture

`mcp-seal-dev` is the private Lean source of the Seal rulebook.

## Components

- `SealCore`: the small approval automaton, target hash type, live approval map, and safety theorems.
- `Seal`: policy classification, target-part encoding, target commitment, and channel parsing.
- `SealCore/Sha256.lean`: executable SHA-256 used for the deployed target commitment.
- `SealV2`: parser, validation, serialization, and proof-carrying decision pipeline experiments.
- `Test`: executable tests and axiom-print entry points.

## Data flow

1. A policy chooses target parts from an MCP tool call.
2. `Seal.encodeParts` frames those parts as `<charCount>:<part>` strings.
3. `Seal.stableHashParts` hashes the encoded string as UTF-8 with SHA-256 and returns `TargetHash`.
4. `SealCore.step` compares that target against live approvals and returns allow or block.
5. Audit `certHash` paths use `Seal.auditHashParts`, a separate UInt64 helper kept out of the target commitment.

## Trust boundaries

This repo proves kernel properties. It does not deploy MCP transport, key management, browser code, or Rust host behavior. Those appear in the sibling repos and are tied back by conformance tests.
