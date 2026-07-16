# Policy-v2: match, decision, target

Policy-v2 is evaluated inside Lean by `Seal.matchSpec`, `evaluateRule`, and
`resolveRuleDecisions`. Rust transports the resulting event; it does not
reimplement policy meaning.

## The model

Each rule answers two separate questions:

1. **Match:** when does this rule apply, and is the result `allow`, `guard`,
   or `deny`?
2. **Target:** for a guarded call, which exact values does a human approval
   bind?

No match denies. Among matching rules, precedence is:

```text
deny or invalid target > guard > explicit allow > no match (deny)
```

Multiple matching guards must derive the same target. Different guard targets
are ambiguous and block.

## Schema

```json
{
  "epoch": 1,
  "server": "stable-server-identity@version",
  "safety": {
    "approval": {"control_file": "/absolute/path", "ttl_seconds": 120},
    "tools": [
      {
        "name": "file_operation",
        "mode": "allow",
        "match": {
          "type": "all",
          "matches": [
            {"type": "equals", "arg": "operation", "value": "read"},
            {"type": "starts_with", "arg": "path", "value": "/workspace/"}
          ]
        }
      },
      {
        "name": "file_operation",
        "mode": "guard",
        "match": {"type": "equals", "arg": "operation", "value": "write"},
        "target": [{"full_arguments": true}]
      },
      {
        "name": "file_operation",
        "mode": "deny",
        "match": {"type": "starts_with", "arg": "path", "value": "/secrets/"}
      }
    ]
  }
}
```

Modes are `allow`, `guard` (`guarded` remains accepted for v1
compatibility), and `deny`.

Match forms:

- `always`
- `equals`: exact scalar string equality at `arg`
- `starts_with`: scalar string prefix at `arg`
- `contains_any_ci`: case-insensitive substring search; this is not a parser
- `all` / `any`: recursive composition through `matches`

Target parts:

- `{"literal":"..."}`
- `{"arg":"dot.path"}` for scalar values
- `{"full_arguments":true}` for the canonical compact JSON argument object

When `server` is present, a guarded target is:

```text
SHA256(encodeParts([server, tool, ...resolved target parts]))
```

`full_arguments` is the recommended safe default because any change to the
canonical Lean JSON value changes the pre-image. Object-key reordering alone is
not a value change: `Lean.Json` canonicalizes object keys before `compress`.
Concluding that the SHA-256 digest also changes uses the named
collision-resistance assumption A-CR.

## The 7-kernel bundle

`Seal.parsePolicyBundle` (`Seal/PolicyBundle.lean`) parses the whole 7-kernel
policy surface: the envelope above plus one optional declarative section per
non-Safety kernel. The deployed host (seal-host) maps a parsed bundle onto its
proven kernel registry; the `bundle_*_registered_iff` tripwires there pin that
a bundle activates exactly the kernels it configures.

Unknown keys are hard errors at the payload, section, and entry levels: a typo
such as `temporral` must not silently leave a kernel off. The one interior the
bundle parser does not police is each safety rule's body (`match`/`target`
internals), which stays the authoring signer's boundary.

Enable semantics, per kernel — honesty first:

| Kernel | Presence | `enabled` | Off means |
|---|---|---|---|
| S Safety | required | rejected key | never off (`safety_always_registered`) |
| T Temporal | optional | default `true` | vacuous (registered, empty policy list) |
| C Consensus | optional | default `true` | unregistered |
| V Convergence | optional | default `true` | unregistered |
| K Calibration | optional | default **`false`** (EXPERIMENTAL) | present-but-disabled, a distinct pinned state |
| L Linear | optional | default `true` | unregistered |
| B Budget | optional | default `true` | unregistered |

S and T are registered unconditionally by the host's proven registry
selection; they are configurable but not de-registrable. `enabled: false` on
any other section is equivalent to deleting the section (the `effective*`
functions collapse it before the host mapping), except Calibration, whose
present-but-disabled state is deliberately preserved (opt-in twice).

Section shapes (wire keys are frozen; each also accepts `enabled`):

```json
{
  "temporal": {"policies": [
    {"name": "freeze-after-revoke", "type": "no_after",
     "trigger": ["revoke"], "forbidden": ["write_item"]}]},
  "consensus": {"roster": [1, 2, 3],
    "votes_file": "/path/votes.ndjson", "high_stakes": ["deploy"]},
  "convergence": {"tools": [
    {"tool": "store.update", "op_arg": "operation.kind"}]},
  "calibration": {"enabled": false, "delta_num": 1, "delta_den": 20,
    "min_samples": 100, "records_file": "/path/forecasts.ndjson",
    "gated_tools": ["auto_publish"]},
  "linear": {"grants_file": "/path/grants.ndjson",
    "tools": [{"tool": "spend", "cap_arg": "capability.id"}]},
  "budget": {"budgets": [
    {"name": "write-units", "cap": 100, "tools": ["write_item"],
     "cost_arg": "usage.units"}]}
}
```

Field semantics, guarantees per kernel, and authoring recipes are documented
in `seal-host/CONFIG.md`; the parser is this repository's
`Seal.parsePolicyBundle`, so there is one config vocabulary across the native,
wasm, and model lanes.

### Budget × Linear: pinned known gap

Surfacing Budget (B) and Linear (L) here does not upgrade their composition
claim. What is proven (seal-host `Host/Commit.lean`, pure two-phase commit
model): a call denied by the composed verdict commits no decide-phase state —
a Safety-denied call spends no budget and consumes no linear grant
(`pureCommit_deny_no_decide_commit`, `budget_commitStep_deny`), and committed
traces stay within caps (`budget_committed_trace_within_cap_of_consistent`,
`linear_committed_trace_no_double_spend`), with the deployed loop body bound
by the `phase1Held_*` lemmas. What is NOT proven: the IO realization of that
commit discipline through the FFI boundary (mirrored, not proven), and any
caller dimension — budget counters and linear grants are global, so one
caller can exhaust another's allowance. The budget×linear proof is a queued
follow-up goal; until it lands, treat B and L guarantees as per-config-global,
not per-caller.

## Proven properties

`Seal.PolicyV2Theorems` establishes:

- no matching rule blocks;
- explicit allow has an explicit origin;
- guard dominates explicit allow;
- a blocking decision dominates composition;
- appending deny cannot allow;
- appending guard cannot produce explicit allow;
- distinct simultaneous guard targets block as ambiguous;
- changed canonical full arguments change the target pre-image.

The existing `SealCore` theorems continue to establish that a resolved
guarded target cannot allow without a live exact-target approval, that approval
for another target does not authorize it, and that approvals expire and are
single-use.

## Boundaries

- String predicates do not understand SQL, shell, URLs, paths, or Git refs.
- Policy authors and starter manifests remain responsible for coverage and
  effect annotations.
- The Rust/wasm/JavaScript conformance corpus is finite evidence, not a proof
  of cross-runtime equivalence.
- The deployed host must update its pinned `mcp-seal-dev` revision before it
  can execute this language. Until then, policy-v2 profiles are authoring and
  scan fixtures, not deployable host configs.
