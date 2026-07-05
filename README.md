# mcp-seal

[![CI](https://github.com/velvetmonkey/mcp-seal/actions/workflows/ci.yml/badge.svg)](https://github.com/velvetmonkey/mcp-seal/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Lean 4](https://img.shields.io/badge/Lean-4-blueviolet.svg)](https://lean-lang.org/)
[![MCP](https://img.shields.io/badge/MCP-stdio-lightgrey.svg)](https://modelcontextprotocol.io/)

`mcp-seal` is a verified MCP approval-gate sidecar. The `seal` binary sits between an MCP host and a real MCP server, forwards ordinary JSON-RPC traffic unchanged, and blocks configured `tools/call` actions until a human approval exists for the exact request.

The claim is deliberately narrow: this is a provably-correct policy monitor, not a proven-safe agent. Four safety rules are [proven in Lean](#what-is-proven); you can [watch them hold](#demos) in about a minute.

## In Plain English

Think of `seal` as a bouncer on the door of your tools. An AI agent can ask to use any tool it likes, but every sensitive request has to stop at the door. The bouncer checks a guest list (an approval file) that only a human is allowed to write to. No matching ticket on the list, no entry.

Each ticket is single-use. One approved tool call spends it, and the very next identical request is stopped again until a human adds another ticket. The agent cannot forge a ticket or add itself to the list: tickets only count when they arrive through the trusted file, never through the agent's own traffic.

What makes `seal` different from an ordinary check is that the bouncer is mathematically proven, in Lean, to follow four rules without exception: never let an unticketed guest through, never reuse a spent ticket, never accept a ticket made for a different guest, and never wave anyone past without looking.

### The one rule to hold in your head: one approval row = one tool call

- A `guarded` tool is **blocked by default**. It is allowed only when a matching approval is already present in the control file.
- Each approval is a **one-shot ticket**. The first matching `tools/call` consumes it; the next identical call is blocked again.
- An unused ticket also **expires** on a wall-clock TTL (`ttl_seconds`, default 120, capped 300), whether or not it was ever spent.

```
N approval rows in the control file  =  N authorized tool calls
```

The gate runs forever; each individual ticket is single-use. Think turnstile tickets, not a one-time keyswitch: you (the human) mint tickets by appending lines to the control file, and every passage spends one. With that rule in hand, the demos below will make sense on sight.

## Demos

Four ways to watch the gate work, ordered simplest to richest. Each is self-contained with copy-paste commands. Start at the top.

Every demo needs the `seal` binary, so build it once:

```bash
lake build          # produces .lake/build/bin/seal
```

### Demo 1: approval + TTL policy, fully scripted

The fastest proof. `demo/ttl_demo.py` drives the real `seal` binary in front of the official zero-auth reference server ([`@modelcontextprotocol/server-everything`](https://www.npmjs.com/package/@modelcontextprotocol/server-everything)), prints the exact policy JSON it uses, and checks every approval and TTL behaviour live. Needs only Node/npx; no API key, no network beyond a one-time `npx` fetch.

```bash
python3 demo/ttl_demo.py
```

Expected output (exits non-zero if any check misbehaves):

```
=== Policy A (ttl_seconds = 120): default-deny + one-shot ticket ===
  [PASS] 1. default-deny (no approval): got BLOCK ...
  [PASS] 2a. one ticket -> first call allowed: got ALLOW ...
  [PASS] 2b. same ticket -> second call blocked (consumed): got BLOCK
=== Policy B (ttl_seconds = 2): an unused ticket expires by the clock ===
  [PASS] 3. unused ticket blocked after TTL elapsed: got BLOCK
=== Policy C (ttl_seconds = 60): issuedAt binds TTL to mint time ===
  [PASS] 4a. stale mint (issuedAt = now-120s) blocked on first use: got BLOCK
  [PASS] 4b. fresh mint (issuedAt = now) allowed: got ALLOW
  PASS: 6/6 checks passed
```

That is default-deny, the one-shot ticket, wall-clock expiry, and mint-time `issuedAt`, all demonstrated against the shipped binary in one command.

### Demo 2: gate a server by hand

Same gate, driven yourself over stdio, so you can see there is no trick. This needs no host and no reload. It blocks a call, you mint a ticket, the same call is allowed once.

```bash
: > /tmp/seal-approvals.ndjson          # start with an empty guest list
{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"sealtest","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"echo","arguments":{"message":"hello seal"}}}'
  sleep 3 ; } \
| .lake/build/bin/seal --policy config/policy.everything.json -- \
    npx -y @modelcontextprotocol/server-everything stdio
```

The trailing `sleep 3` holds the pipe open so the `npx` child can boot on a cold first run. Expect `initialize` forwarded with a real upstream reply, and `id:2` returning a seal block (`isError: true`, `approval required: 13354254271524378478`) because no approval exists yet. The block error hands you the exact target hash you need (see [Reference: policies and the target hash](#reference-policies-and-the-target-hash)).

Now mint that hash and re-run:

```bash
echo '{"target":13354254271524378478}' >> /tmp/seal-approvals.ndjson
```

The second run returns `Echo: hello seal`; a third run (ticket consumed) blocks again. To bind the ticket to when *you* minted it rather than when `seal` reads it, add `issuedAt` (Unix epoch ms): `echo '{"target":13354254271524378478,"issuedAt":'$(date +%s%3N)'}' >> /tmp/seal-approvals.ndjson`.

**Wire it into a real host** the same way: in your host config (e.g. `~/.claude.json`), replace the server entry with `seal` spawning it. Back up your config first.

```jsonc
"everything": {
  "command": "/abs/path/mcp-seal/.lake/build/bin/seal",
  "args": [
    "--policy", "/abs/path/mcp-seal/config/policy.everything.json",
    "--",
    "npx", "-y", "@modelcontextprotocol/server-everything", "stdio"
  ]
}
```

The trailing `stdio` argument matters: without it the launcher prints a banner that corrupts the JSON-RPC stream. `seal` forwards `initialize` / `tools/list` / notifications byte-for-byte (tools still appear in discovery) and gates only `tools/call`. Reload MCP to pick up the change. To roll back, restore your backed-up config entry and reload; nothing else is touched. (A remote HTTP server works too: bridge it to stdio with [`mcp-remote`](https://www.npmjs.com/package/mcp-remote) as seal's child instead of the `npx` line.)

### Demo 3: scripted block smoke test (zero deps)

A scripted malicious `tools/call` that tries to drop a production table, run three times against the verified core, with zero external dependencies. (Scripted JSON-RPC, no LLM and no LangGraph — the live-agent case is Demo 4.) It shows the full lifecycle of a single ticket: blocked cold, allowed once after a trusted human approval is appended, then blocked again once that one-shot approval is consumed.

```bash
lake exe automaton_tests
lake exe axiom_check
python3 test/integration/test_seal.py
python3 demo/blocked_call_smoke.py
```

### Demo 4: flagship, seal x Canary

The applied demo: `seal` wrapped in front of a real LangGraph agent ([Canary](https://github.com/velvetmonkey/canary), an ESG regulatory-change pipeline) writing to an MCP vault server. Canary's legitimate report `note/create` is approved and succeeds; a destructive `note/delete` then dies at the gate. Without `seal` the file is deleted; with `seal` it is blocked and the file survives byte-identical. This is the artefact for a pitch or an ARIA reviewer: it proves the gate on a real agent doing a real task, not just in a unit test.

The runner lives in the [Canary](https://github.com/velvetmonkey/canary) repo and orchestrates three repositories: Canary (the host), `seal` (this repo), and [flywheel-memory](https://github.com/velvetmonkey/flywheel-memory) (the MCP server being gated). It runs fully offline (no LLM key).

> Scope note: a single container (in the Canary repo) bundles all three repos so the multi-repo *demo* runs reproducibly with one command. That container is a demo harness only. `seal` itself is a single native binary with no container or runtime dependencies; adoption is a one-line host config change.

**Honest claim**: a default-deny gate blocks the destructive action at a verified boundary the model cannot influence, and every allowed action is explicitly approved. This does **not** claim prompt-injection prevention or additive-only containment. The model can still be fooled; the demo shows the action dies anyway.

#### Dependencies (fresh machine)

1. **Lean toolchain** for `seal` itself. Install [`elan`](https://github.com/leanprover/elan); it pins `leanprover/lean4:v4.28.0` from `lean-toolchain`. Then in this repo: `lake build`.
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
5. **No API key, no network.** The regulation corpus is frozen on disk (`canary/demo/corpus`), and Canary's extraction step is replayed from a frozen fixture (`CANARY_FIXTURE_EXTRACTION`, set automatically by the runner), so no `ANTHROPIC_API_KEY` and no EUR-Lex fetch are required. The seal kill/restore proof never touches an LLM in the first place.

#### Run

```bash
cd canary
uv run python demo/run_p3.py
```

The runner rebuilds a disposable workspace under `/tmp/seal-demo-p3` (fresh vault, policy, approvals control file, change-detection DB), runs Canary through `seal`, performs the kill/restore proof, and prints `P3-REPORT.md` ending in a PASS/FAIL line.

`run_p3.py` resolves its dependencies at runtime via environment overrides (`SEAL_BIN`, `FLYWHEEL_SERVER`, `NODE_BIN`), then sibling repos and `PATH`, so it is not bound to any one machine. Verified: full PASS with all overrides and `ANTHROPIC_API_KEY` unset. The verified core and seal's gating behaviour are additionally proven on clean GitHub `ubuntu-latest` runners every commit (`lake build`, axiom checks, `test/integration/test_seal.py`).

## How It Works

Agents are useful because they can call tools. They are risky for the same reason. `seal` puts a small, auditable boundary in front of those tools: `initialize`, `tools/list`, `resources/read`, notifications, and responses pass through byte-for-byte; only `tools/call` is inspected.

For a guarded call, `seal` computes the target hash from the runtime JSON policy and asks the Lean-proven engine for a decision:

- `ALLOW`: forward the original request upstream unchanged.
- `BLOCK`: return a JSON-RPC `isError: true` result carrying `approval required: <hash>`, without ever touching upstream.

The v1 transport is a stdio wrapper, so adoption is a one-line host config change: launch `seal` instead of the real MCP server and let `seal` spawn the real server. To run it in front of any local stdio server directly:

```bash
.lake/build/bin/seal --policy config/policy.example.json -- python3 test/integration/mock_mcp_server.py
```

## What Is Proven

The Lean core proves the safety rules for the compiled automaton:

- Default-deny events are never allowed.
- Guarded calls cannot be allowed unless a matching live approval is already in state.
- Approvals bind to target, so approval for hash A cannot authorize hash B.
- Approvals are one-shot at the engine boundary: an allowed guarded call consumes the matching approval.
- Expired approvals are not live: once an approval's deadline has passed, the gate blocks (`expired_not_live`), and a freshly minted approval is live at mint time (`fresh_approval_live`). TTL expiry is a **liveness** bound; it never weakens the safety rules above.

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
- The wall-clock. The runtime supplies a Unix-epoch timestamp (`Std.Time.Timestamp.now`, milliseconds) to the verified decision function; Lean proves the decision relative to that timestamp, it does not verify the OS clock. Wall-clock (rather than a monotonic clock) is required so a record-supplied `issuedAt` is comparable. A clock that jumps, skews, or is wrong can only change *when* an already human-approved ticket expires. It can never cause an unapproved call to be allowed. Expiry is best-effort liveness, never safety.
- The MCP boundary. In-process calls that never emit `tools/call` are out of scope.

## Performance

A verified gate is worth little if it is slow. It is not. Per-call mediation overhead on the gate hot path (a guarded `tools/call` hitting default-deny: parse + classify + decide + emit), measured over ~1900 calls on commodity hardware:

| metric | latency |
|---|---|
| mean | ~0.20 ms |
| p50 | ~0.19 ms |
| p90 | ~0.23 ms |
| p99 | ~0.30 ms |

Sub-millisecond. The verified boundary is not where your latency goes.

Honest scope: this is the **decision path**. An *allowed* call additionally forwards to the upstream server, whose latency is not seal's overhead. Reproduce it yourself:

```bash
lake build
python3 test/bench/latency_bench.py
```

## Architecture

`seal` has two separate layers:

- **Rules as data**: `config/policy.example.json` classifies tool calls, target fields, deny rules, and approval control-file settings at runtime.
- **Engine as code**: `SealCore` contains the compiled Lean automaton and the zero-`sorry` invariants.

Approvals arrive only through the trusted control file as newline-delimited JSON records, re-read on each `tools/call` in v1. File permissions are the origin check. An approval sent as an ordinary agent tool call is ignored by the classifier and remains blocked by default. Runtime config is JSON via Lean's built-in parser, so policies are data, not baked into Lean source. Unknown tools, unmatched patterns, missing target fields, and explicit deny rules all block by default.

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

## Reference: policies and the target hash

### Policy files

Three ready-made policies ship in `config/`:

- [`config/policy.deny-all.json`](config/policy.deny-all.json): `"tools": []`. Every `tools/call` hits default-deny and is blocked unconditionally. The pure-block test.
- [`config/policy.everything.json`](config/policy.everything.json): marks two harmless server-everything tools (`echo`, `add`) as `guarded` with `"match": { "type": "always" }` and an empty `target`. Used by Demos 1 and 2.
- [`config/policy.example.json`](config/policy.example.json): the generic template.

A minimal guarded rule:

```json
{ "name": "echo", "mode": "guarded", "match": { "type": "always" }, "target": [] }
```

The `approval` block sets the control file and `ttl_seconds` (default 120, capped 300). Approval records are newline-delimited JSON: `{"target": <hash>}`, optionally with `"issuedAt": <epoch-ms>` to bind the TTL to mint time.

### What the target hash is, exactly

A ticket on the guest list is a single 64-hex fingerprint: the **target hash**. It is a commitment to the request you are approving, so an approval for one action cannot quietly unlock a different one.

It is computed deterministically (SHA-256, no secret) over a **self-delimiting** encoding of the tool name plus any chosen argument values. Each part is framed `<charCount>:<part>` and the frames are concatenated, so distinct part-lists can never collide at the encoding layer:

```
target = SHA-256( "<len>:<toolName>" ++ "<len>:<part1>" ++ ... )   // lowercase 64-hex
```

- With `"target": []` (name only), the encoding is just the framed tool name, so every call to that tool shares one hash. Worked example: the tool `echo` (encoded `"4:echo"`) always hashes to `d75d9cecde13d161ae07ee440860ef7007ff664334f4d043eff81f95d4643c6f`, on any machine, every run. That is the value the block error hands you.
- With `"target": ["arguments.message"]` and message `hello`, the encoding is `"4:echo5:hello"` → `e1785433529ec63e8edc69863be181cdaf37f1ad1fd7db306272778e0c0282e0`, so a ticket minted for `hello` will not authorize an `echo` of `goodbye`. Each distinct argument value gets its own hash and therefore its own ticket.

So the hash is a stable, unguessable-by-accident name for "this exact request". The block error hands it to you directly: you are not decoding anything, you are reading the name of the thing you are choosing to let through, then writing that same name onto the guest list. Empty `target` is the coarsest grain (one ticket per tool); adding `target` parts drawn from the call arguments binds approvals to specific argument values for finer control.

## Related repositories

Part of the velvetmonkey verified-cognition stack:

- **mcp-seal** (this repo): the verified MCP approval-gate sidecar.
- [canary](https://github.com/velvetmonkey/canary): a LangGraph compliance pipeline that hosts the flagship [seal x Canary demo](#demo-4-flagship-seal-x-canary).
- [flywheel-memory](https://github.com/velvetmonkey/flywheel-memory): the knowledge-graph MCP server that `seal` gates in that demo.

## License

Apache License 2.0. See [LICENSE](LICENSE).
