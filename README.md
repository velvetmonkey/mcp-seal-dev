# mcp-seal

[![CI](https://github.com/velvetmonkey/mcp-seal/actions/workflows/ci.yml/badge.svg)](https://github.com/velvetmonkey/mcp-seal/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Lean 4](https://img.shields.io/badge/Lean-4-blueviolet.svg)](https://lean-lang.org/)
[![MCP](https://img.shields.io/badge/MCP-stdio-lightgrey.svg)](https://modelcontextprotocol.io/)

`mcp-seal` is a verified MCP approval-gate sidecar. The `seal` binary sits between an MCP host and a real MCP server, forwards ordinary JSON-RPC traffic unchanged, and blocks configured `tools/call` actions until a human approval exists for the exact target hash.

The claim is deliberately narrow: this is a provably-correct policy monitor, not a proven-safe agent.

## Why It Exists

Agents are useful because they can call tools. They are risky for the same reason. `seal` puts a small, auditable boundary in front of those tools: initialize, tools/list, resources/read, notifications, and responses pass through byte-for-byte; only `tools/call` is inspected.

For guarded calls, `seal` computes a target from the runtime JSON policy and asks the Lean-proven engine for a decision:

- `ALLOW`: forward the original request upstream.
- `BLOCK`: return a JSON-RPC `isError: true` result with `approval required`, without touching upstream.

The v1 transport is a stdio wrapper, so adoption is a one-line host config change: launch `seal` instead of the real MCP server, and let `seal` spawn the real server.

## What Is Proven

The Lean core proves the safety rules for the compiled automaton:

- Default-deny events are never allowed.
- Guarded calls cannot be allowed unless a matching live approval is already in state.
- Approvals bind to target, so approval for hash A cannot authorize hash B.
- Approvals are one-shot at the engine boundary: an allowed guarded call consumes the matching approval.

The CI axiom gate runs:

```text
lake exe axiom_check
```

Expected axiom footprint:

```text
'SealCore.default_deny_never_allowed' depends on axioms: [propext, Quot.sound]
'SealCore.no_allow_guarded_without_matching_approval_in_state' depends on axioms: [propext, Quot.sound]
'SealCore.approval_binds_to_target' depends on axioms: [propext, Classical.choice, Quot.sound]
```

## What Is Trusted

Honesty is part of the product. The proof covers the engine, not the world around it.

Trusted, not proven:

- Approval origin, enforced in v1 by a permissions-protected control file.
- Classifier completeness and correctness: the runtime JSON policy must identify the calls you care about.
- Lean compiler/runtime, JSON parsing, child-process I/O, and host/server behavior.
- The MCP boundary. In-process calls that never emit `tools/call` are out of scope.

## v2: Verified Capability Pipeline (in progress)

v2 builds a stronger, proof-carrying core alongside the shipped v1 sidecar. The v1 `seal` binary is unchanged; v2 lives in `SealV2` and is documented in [v2/STATUS.md](v2/STATUS.md). The pipeline is `parse -> validate -> serialize`, with each stage proven:

- **M1 strict-subset parser** (`parse : RawBytes -> Option AST`): total and fail-closed. Malformed, ambiguous, duplicate-key, non-ASCII, partial, trailing-byte, or non-canonical numeric inputs return `none`. Numbers use a fixed canonical decimal grammar (no exponents, no leading/trailing-zero forms). `parse raw = some ast -> IsCanonical ast` is proved.
- **M2 constructive validation** (`validate : AST -> ApprovalState -> Option (Σ ast, ValidCapability ast state)`): success returns a proof-carrying witness, not a boolean. The `ValidCapability` witness binds the decoded request, tool spec, exact target, exact approval, session, `consumed = false`, expiry, and signature.
- **M3 canonical serialization** (`serialize : (Σ ast, ValidCapability ast state) -> CanonicalBytes`): one proof-gated canonical serializer for both output bytes and the M5 signed-message shape. The roundtrip and canonicality theorems are proved.
- **M4 mediated decide** (`decide : RawBytes -> ApprovalState -> Decision`): a single fail-closed emit path. `Allow out` can only arise through `parse -> validate -> serialize`.

M1 through M4 are axiom-clean for their discharged theorems, with footprint `[propext, Classical.choice, Quot.sound]`. Verify with:

```text
lake exe v2_m1_axiom_check
lake exe v2_m2_axiom_check
lake exe v2_m3_axiom_check
lake exe v2_m4_axiom_check
```

Claim discipline: `canonical_roundtrip` means seal self-consistency only. A2, target-parser equivalence, remains the per-server obligation, minimised by construction and by the differential fixture, not eliminated. The signed-approval path rejects non-canonical signed-message bytes instead of normalising them before signature verification.

## Architecture

`seal` has two separate layers:

- **Rules as data**: `config/policy.example.json` classifies tool calls, target fields, deny rules, and approval control-file settings at runtime.
- **Engine as code**: `SealCore` contains the compiled Lean automaton and the zero-`sorry` invariants.

Approvals arrive only through the trusted control file as newline-delimited JSON records. An approval sent as an ordinary agent tool call is ignored by the classifier and remains blocked by default.

## Usage

Build:

```bash
lake build
```

Run `seal` in front of a real stdio MCP server:

```bash
.lake/build/bin/seal --policy config/policy.example.json -- python3 test/integration/mock_mcp_server.py
```

Append a trusted approval record to the configured control file:

```json
{"target":7653913048106253087}
```

The control file is re-read on each `tools/call` in v1. File permissions are the origin check.

## Config

Runtime config is JSON via Lean's built-in parser. Policies are data, not baked into Lean source.

Unknown tools, unmatched patterns, missing target fields, and explicit deny rules all block by default.

See [config/policy.example.json](config/policy.example.json).

## Tests And Demo

```bash
lake build
lake exe automaton_tests
lake exe axiom_check
python3 test/integration/test_seal.py
python3 demo/langgraph_injection_demo.py
```

The demo shows a prompt-injected request to drop a production table: first blocked cold, then allowed once after a trusted human approval, then blocked again when the one-shot approval has been consumed.

## End-to-End Demo (seal x Canary)

The flagship demo wraps `seal` in front of a real LangGraph agent ([Canary](https://github.com/velvetmonkey/canary), an ESG regulatory-change pipeline) writing to an MCP vault server. It runs Canary through `seal` (the legitimate report `note/create` is approved and succeeds), then proves a destructive `note/delete` dies at the gate: deleted without `seal`, blocked and the file survives byte-identical with `seal`.

Honest claim: a default-deny gate blocks the destructive action at a verified boundary the model cannot influence, and every allowed action is explicitly approved. This does **not** claim prompt-injection prevention or additive-only containment. The model can still be fooled; the demo shows the action dies.

### Dependencies (fresh machine)

The demo spans three repositories and runs fully offline (no LLM key):

1. **Lean toolchain** for `seal` itself. Install [`elan`](https://github.com/leanprover/elan); it pins `leanprover/lean4:v4.28.0` from `lean-toolchain`. Then in this repo:
   ```bash
   lake build          # produces .lake/build/bin/seal
   ```
2. **Node.js v22.x** for the upstream MCP server. (nvm: `nvm install 22`.)
3. **flywheel-memory** (the real MCP server `seal` spawns):
   ```bash
   git clone https://github.com/velvetmonkey/flywheel-memory
   cd flywheel-memory && npm ci && npm run build
   # server entry: packages/mcp-server/dist/index.js
   ```
4. **Canary** (the LangGraph host + demo runner), Python 3.12 via [`uv`](https://github.com/astral-sh/uv):
   ```bash
   git clone https://github.com/velvetmonkey/canary
   cd canary && uv sync
   ```
   Python deps (resolved by `uv`): langgraph, langchain-anthropic, langchain-mcp-adapters, mcp, beautifulsoup4, lxml, pydantic, pyyaml, httpx, tenacity.
5. **No API key, no network.** The demo runs fully offline. The regulation corpus is frozen on disk (`canary/demo/corpus`), and Canary's [[extraction]] step is replayed from a frozen fixture (`CANARY_FIXTURE_EXTRACTION`, set automatically by the runner), so no `ANTHROPIC_API_KEY` and no EUR-Lex fetch are required. The seal kill/restore proof never touches an LLM in the first place.

### Run

```bash
cd canary
uv run python demo/run_p3.py
```

The runner rebuilds a disposable workspace under `/tmp/seal-demo-p3` (fresh vault, policy, approvals control file, change-detection DB), runs Canary through `seal`, performs the kill/restore proof, and prints `P3-REPORT.md` ending in a PASS/FAIL line.

### Portability

`run_p3.py` resolves its dependencies at runtime, so it is not bound to any one machine. It checks environment overrides first, then falls back to the sibling repos and `PATH`:

- `SEAL_BIN` — the `seal` binary (default: `../mcp-seal/.lake/build/bin/seal`)
- `FLYWHEEL_SERVER` — the flywheel-memory `dist/index.js` (default: `../flywheel-memory/packages/mcp-server/dist/index.js`)
- `NODE_BIN` — the node binary (default: `node` on `PATH`)

It exits with a clear message if a dependency cannot be found. Verified: full PASS with all overrides and `ANTHROPIC_API_KEY` unset, every path resolved by discovery. The verified core and seal's gating behaviour are additionally proven on clean GitHub `ubuntu-latest` runners every commit (`lake build`, axiom checks, and `test/integration/test_seal.py`).

## License

Apache License 2.0. See [LICENSE](LICENSE).
