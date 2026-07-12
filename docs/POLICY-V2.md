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
