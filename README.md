# mcp-seal

[![CI](https://github.com/velvetmonkey/mcp-seal/actions/workflows/ci.yml/badge.svg)](https://github.com/velvetmonkey/mcp-seal/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Lean 4](https://img.shields.io/badge/Lean-4-blueviolet.svg)](https://lean-lang.org/)
[![MCP](https://img.shields.io/badge/MCP-stdio-lightgrey.svg)](https://modelcontextprotocol.io/)

`mcp-seal` is a verified MCP approval-gate sidecar. The `seal` binary sits between an MCP host and a real MCP server, forwards ordinary JSON-RPC traffic unchanged, and blocks configured `tools/call` actions until a human approval exists for the exact request.

The claim is deliberately narrow: this is a provably-correct policy monitor, not a proven-safe agent.

## In Plain English

Think of `seal` as a bouncer on the door of your tools. An AI agent can ask to use any tool it likes, but every sensitive request has to stop at the door. The bouncer checks a guest list (an approval file) that only a human is allowed to write to. No matching ticket on the list, no entry.

Each ticket is single-use. One approved tool call spends it, and the very next identical request is stopped again until a human adds another ticket. The agent cannot forge a ticket or add itself to the list: tickets only count when they arrive through the trusted file, never through the agent's own traffic.

What makes `seal` different from an ordinary check is that the bouncer is mathematically proven, in Lean, to follow four rules without exception: never let an unticketed guest through, never reuse a spent ticket, never accept a ticket made for a different guest, and never wave anyone past without looking. The rest of this README shows you how to watch that bouncer work, then how it is built.

## Try It in Five Minutes

You do not need any of the demo stack to see `seal` work. You can drop it in front of a real MCP server your host already talks to and watch it gate live tool calls. This walkthrough uses the official MCP reference server, [`@modelcontextprotocol/server-everything`](https://www.npmjs.com/package/@modelcontextprotocol/server-everything): no account, no API key, no network beyond a one-time `npx` fetch, and it speaks stdio natively so there is nothing to bridge. The shape is identical for any server.

**What you will see:** a tool that works normally suddenly refuses to run. You add one line to a file. The same tool runs exactly once, then refuses again. That one-line-equals-one-call behaviour, with a mathematical proof underneath it, is the whole product.

### The mental model: one approval row = one tool call

This is the single most important thing to understand before testing:

- A `guarded` tool is **blocked by default**. It is allowed only when a matching approval record is already present in the control file.
- Each approval is a **one-shot ticket**. The first matching `tools/call` *consumes* it (the engine erases it from state). The next identical call is blocked again.
- An unused approval also dies on **wall-clock TTL expiry**, whether or not it was ever spent. A bare `{"target": <hash>}` record expires `ttl_seconds` after `seal` first reads it. A record may also carry `"issuedAt": <epoch-ms>` (the wall-clock time you minted it), in which case it expires `ttl_seconds` after *that* moment, so a ticket you minted and forgot is already dead by the time `seal` sees it. `ttl_seconds` defaults to 120 and is capped at 300. `issuedAt` can only ever make a ticket expire sooner, never later, than `now + ttl_seconds`.

So the relationship is literal and one-to-one:

```
N approval rows in the control file  =  N authorized tool calls
```

One `seal` instance gates an unlimited number of tools and holds an unlimited number of live approvals at once. What is "once only" is each individual approval *record*, not the gate. Think single-use tickets at a turnstile, not a one-time keyswitch: the gate runs forever, every passage spends one ticket, and you (the human) mint tickets by appending lines to the control file.

### See it, do not just read it: `demo/ttl_demo.py`

Rather than take the table on faith, run the policy demo. It drives the real `seal` binary in front of server-everything, prints the exact policy JSON it uses, and checks every approval and TTL behaviour live:

```bash
lake build                  # produces .lake/build/bin/seal
python3 demo/ttl_demo.py    # needs only node/npx; no key, no network beyond one npx fetch
```

It exercises four scenarios and exits non-zero if any misbehaves:

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

That is default-deny, the one-shot ticket, wall-clock expiry, and mint-time `issuedAt`, all demonstrated against the shipped binary. The rest of this section is the same behaviour, by hand.

### 1. Build seal

```bash
lake build          # produces .lake/build/bin/seal
```

### 2. Write a policy

Two ready-made policies ship in `config/`:

- [`config/policy.deny-all.json`](config/policy.deny-all.json): `"tools": []`. Every `tools/call` hits default-deny and is blocked unconditionally. No approval can ever open it (there is no rule to match). This is the pure-block test.
- [`config/policy.everything.json`](config/policy.everything.json): marks two harmless server-everything tools (`echo`, `add`) as `guarded` with `"match": { "type": "always" }` and an empty `target`. Guarded means each call is blocked until a matching approval exists, then allowed exactly once.

A minimal guarded rule looks like:

```json
{ "name": "echo", "mode": "guarded", "match": { "type": "always" }, "target": [] }
```

#### What the target hash is, exactly

A ticket on the guest list is a single number: the **target hash**. It is a fingerprint of the request you are approving, so an approval for one action cannot quietly unlock a different one.

It is computed deterministically (a 64-bit FNV-1a hash, no crypto, no secret) over one string built from the tool name plus any chosen argument values, joined by `|`:

```
target = FNV-1a( toolName | part1 | part2 | ... )
```

- With `"target": []` (name only), the string is just the tool name, so every call to that tool shares one hash. Worked example: the tool `echo` always hashes to `13354254271524378478`, on any machine, every run. That is the number the block error hands you below.
- With `"target": ["arguments.message"]`, the string becomes `echo|hello`, so a ticket minted for the message `hello` will not authorize an `echo` of `goodbye`. Each distinct argument value gets its own hash and therefore its own ticket.

So the hash is simply a stable, unguessable-by-accident name for "this exact request". That is why the block error hands you the hash directly: you are not decoding anything, you are reading the name of the thing you are choosing to let through, then writing that same name onto the guest list. Empty `target` is the coarsest grain (one ticket per tool); adding `target` parts drawn from the call arguments binds approvals to specific argument values for finer control.

### 3. Point your host at seal

`seal` is a stdio sidecar, and so is server-everything, so `seal` simply spawns it as its child. In your host config (e.g. `~/.claude.json`), add or replace the server entry:

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

Back up your config first. The trailing `stdio` argument matters: without it the launcher prints a banner that corrupts the JSON-RPC stream. `seal` spawns the child, forwards `initialize` / `tools/list` / notifications byte-for-byte (so tools still appear in discovery), and gates only `tools/call`. Reload MCP (restart the host or reconnect) so the new stdio entry replaces the old one. (A remote HTTP server works too: bridge it to stdio with [`mcp-remote`](https://www.npmjs.com/package/mcp-remote) as seal's child instead of the `npx` line above.)

### 4. Watch it block, then mint a ticket

Call a guarded tool. It is blocked, and the error text **echoes the exact target hash you need**:

```json
{ "result": { "content": [ { "type": "text", "text": "approval required: 13354254271524378478" } ], "isError": true } }
```

Copy that hash and append one approval row to the control file named in your policy (`/tmp/seal-approvals.ndjson`):

```bash
echo '{"target":13354254271524378478}' >> /tmp/seal-approvals.ndjson
```

Call `echo` again: it is **allowed once** and returns the real result (`Echo: ...`). Call a third time without re-minting: blocked again, because the ticket was consumed. Append five rows, get five calls. That is the whole gate.

To bind the ticket to when *you* minted it rather than when `seal` reads it, add `issuedAt` (Unix epoch ms): `echo '{"target":13354254271524378478,"issuedAt":'$(date +%s%3N)'}' >> /tmp/seal-approvals.ndjson`. The ticket then expires `ttl_seconds` after that instant, so a stale mint is refused even on its first use.

### 5. Sanity-check from a shell (no host reload)

You can drive the full chain directly over stdio:

```bash
cd mcp-seal
: > /tmp/seal-approvals.ndjson          # start with an empty guest list
{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"sealtest","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"echo","arguments":{"message":"hello seal"}}}'
  sleep 3 ; } \
| .lake/build/bin/seal --policy config/policy.everything.json -- \
    npx -y @modelcontextprotocol/server-everything stdio
```

The trailing `sleep 3` holds the pipe open so the `npx` child has time to boot on a cold first run; without it stdin can close before the server replies. Expect: `initialize` forwarded with a real upstream reply; `id:2` returns a seal block (`isError: true`, `approval required: 13354254271524378478`) because no approval exists yet. Now mint a ticket and re-run to see the same call allowed:

```bash
echo '{"target":13354254271524378478}' >> /tmp/seal-approvals.ndjson
```

The second run returns `Echo: hello seal`, and a third run (ticket consumed) blocks again.

### Rollback

Restore your backed-up host config entry and reload. Nothing else is touched.

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

Approvals arrive only through the trusted control file as newline-delimited JSON records, re-read on each `tools/call` in v1. File permissions are the origin check. An approval sent as an ordinary agent tool call is ignored by the classifier and remains blocked by default.

Runtime config is JSON via Lean's built-in parser, so policies are data, not baked into Lean source. Unknown tools, unmatched patterns, missing target fields, and explicit deny rules all block by default. See [config/policy.example.json](config/policy.example.json).

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

## The Demos

Two demos ship with this repo. The first is a self-contained smoke test you can run in seconds with nothing else installed. The second is the flagship: a real agent, doing a real job, with `seal` catching a real attack. Read them as **what / why / where / when / how**.

### Quick demo: prompt-injection smoke test

- **What**: a scripted `tools/call` that tries to drop a production table, run three times against the verified core.
- **Why**: to show the lifecycle of a single ticket end to end, with zero external dependencies.
- **Where**: [`demo/langgraph_injection_demo.py`](demo) in this repo, against the mock MCP server.
- **When**: first thing, to confirm your build works and to feel the gate before wiring anything real.
- **How**:

```bash
lake build
lake exe automaton_tests
lake exe axiom_check
python3 test/integration/test_seal.py
python3 demo/langgraph_injection_demo.py
```

The destructive request is first blocked cold, then allowed once after a trusted human approval is appended, then blocked again once that one-shot approval has been consumed. Same shape as the five-minute walkthrough above, with no host to configure.

### Flagship demo: seal x Canary

- **What**: `seal` wrapped in front of a real LangGraph agent ([Canary](https://github.com/velvetmonkey/canary), an ESG regulatory-change pipeline) that writes to an MCP vault server. Canary's legitimate report `note/create` is approved and succeeds; a destructive `note/delete` then dies at the gate. Without `seal` the file is deleted; with `seal` it is blocked and the file survives byte-identical.
- **Why**: a unit test proves the gate in the lab. This proves it on a real agent doing a real task, which is the difference between "the maths works" and "it works where it matters". It is the artefact for a pitch or an ARIA reviewer.
- **Where**: the runner lives in the [Canary](https://github.com/velvetmonkey/canary) repo (`demo/run_p3.py`) and orchestrates three repositories: Canary (the host), `seal` (this repo), and [flywheel-memory](https://github.com/velvetmonkey/flywheel-memory) (the MCP server being gated).
- **When**: when you want the full story rather than the mechanism, or when you need a reproducible, key-free run on a fresh machine.
- **How**: see the run instructions below.

> Scope note: a single container (in the Canary repo) bundles all three repos so the multi-repo *demo* runs reproducibly with one command. That container is a demo harness only. `seal` itself is a single native binary with no container or runtime dependencies; adoption is a one-line host config change.

**Honest claim**: a default-deny gate blocks the destructive action at a verified boundary the model cannot influence, and every allowed action is explicitly approved. This does **not** claim prompt-injection prevention or additive-only containment. The model can still be fooled; the demo shows the action dies anyway.

#### Dependencies (fresh machine)

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
5. **No API key, no network.** The demo runs fully offline. The regulation corpus is frozen on disk (`canary/demo/corpus`), and Canary's extraction step is replayed from a frozen fixture (`CANARY_FIXTURE_EXTRACTION`, set automatically by the runner), so no `ANTHROPIC_API_KEY` and no EUR-Lex fetch are required. The seal kill/restore proof never touches an LLM in the first place.

#### Run

```bash
cd canary
uv run python demo/run_p3.py
```

The runner rebuilds a disposable workspace under `/tmp/seal-demo-p3` (fresh vault, policy, approvals control file, change-detection DB), runs Canary through `seal`, performs the kill/restore proof, and prints `P3-REPORT.md` ending in a PASS/FAIL line.

#### Portability

`run_p3.py` resolves its dependencies at runtime, so it is not bound to any one machine. It checks environment overrides first, then falls back to the sibling repos and `PATH`:

- `SEAL_BIN`: the `seal` binary (default: `../mcp-seal/.lake/build/bin/seal`)
- `FLYWHEEL_SERVER`: the flywheel-memory `dist/index.js` (default: `../flywheel-memory/packages/mcp-server/dist/index.js`)
- `NODE_BIN`: the node binary (default: `node` on `PATH`)

It exits with a clear message if a dependency cannot be found. Verified: full PASS with all overrides and `ANTHROPIC_API_KEY` unset, every path resolved by discovery. The verified core and seal's gating behaviour are additionally proven on clean GitHub `ubuntu-latest` runners every commit (`lake build`, axiom checks, and `test/integration/test_seal.py`).

## Related repositories

Part of the velvetmonkey verified-cognition stack:

- **mcp-seal** (this repo): the verified MCP approval-gate sidecar.
- [canary](https://github.com/velvetmonkey/canary): a LangGraph compliance pipeline that hosts the flagship [seal x Canary demo](#flagship-demo-seal-x-canary).
- [flywheel-memory](https://github.com/velvetmonkey/flywheel-memory): the knowledge-graph MCP server that `seal` gates in that demo.

## License

Apache License 2.0. See [LICENSE](LICENSE).
