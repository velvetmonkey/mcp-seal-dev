# Policy format (v1 shipped binary)

This is the policy JSON consumed by the **v1 stdio `seal` binary** (`seal --policy <file> -- <server cmd>`).
It is a different schema from the v2 manifest / `action` binding described in
[CLAIMS.md](../CLAIMS.md); the v2 config crosses the FFI seam as a JSON envelope
(see [FFI.md](FFI.md)). Parsing lives in `Seal/Policy.lean`; classification in
`Seal/Classify.lean`; approval ingestion in `Seal/Channel.lean`.

## Top-level shape

```json
{
  "approval": {
    "control_file": "/path/to/approvals.ndjson",
    "ttl_seconds": 120
  },
  "tools": [ { "name": "...", "mode": "...", "match": { ... }, "target": [ ... ] } ]
}
```

| Field | Type | Meaning |
|---|---|---|
| `approval.control_file` | string, required | Path to the NDJSON approvals file (the human/approver writes records here; see below). Created empty with mode `0600` if absent. A symlink is rejected at read time (fail-closed). |
| `approval.ttl_seconds` | number, default `120` | Approval lifetime. **Clamped to 300 s** (`maxApprovalTtlSeconds`, mirroring SealV2's `maxApprovalTtl`); longer configured values are silently shortened, never lengthened. |
| `tools[]` | array, required | One rule per tool name. Evaluated by exact `name` match. |

## Tool rules

| Field | Type | Meaning |
|---|---|---|
| `name` | string | Exact MCP tool name (`params.name` of `tools/call`). |
| `mode` | `"guarded"` \| `"deny"` | `guarded`: requires a live matching approval. `deny`: always blocked. Any other value is a policy parse error. |
| `match` | object, default `{"type": "always"}` | When the rule applies. `{"type": "always"}`, or `{"type": "contains_any_ci", "arg": "<dot.path>", "needles": ["..."]}` — case-insensitive (ASCII) substring test of the string scalar at `arguments.<dot.path>` against any needle. |
| `target` | array, default `[]` | The parts a human approval binds to. Each part is `{"literal": "<string>"}` or `{"arg": "<dot.path>"}` (a string/number/bool scalar in `arguments`; objects and arrays do not resolve). |

## Decision semantics (all failure paths deny)

For each `tools/call`, `classifyToolCall` (`Seal/Classify.lean`) produces:

1. **Tool not listed in `tools[]`** → block (`unknown tool`). Unlisted tools are
   NOT passed through — the policy is a fail-closed allowlist for `tools/call`.
2. Rule listed but `match` does not fire (including: the `arg` path is missing
   or not a scalar) → block (`unmatched policy for <tool>`).
3. `mode: "deny"` → block (`flat deny: <tool>`).
4. `mode: "guarded"` and any `target` part's `arg` path is missing → block
   (`missing target field: <tool>`).
5. Otherwise the target commitment is computed as
   `stableHashParts (toolName :: parts)` — **the tool name is automatically
   prepended**, so an approval never transfers between tools even if their
   configured parts collide. The commitment is lowercase 64-hex SHA-256 over the
   injective netstring `encodeParts` (see [CONFORMANCE.md](CONFORMANCE.md)).
   The block message for an unapproved guarded call prints this hex target — it
   is exactly the value an approval record must carry.

Non-`tools/call` traffic (`initialize`, `tools/list`, responses, notifications)
is relayed unchanged; see [THREAT_MODEL.md](../THREAT_MODEL.md).

## Approvals file (NDJSON, one record per line)

```json
{"target": "<64-hex sha256>", "issuedAt": 1751840000000}
```

- `target` — required, the hex commitment printed in the block message. Must be
  a string; a JSON number is ignored (the record is dropped).
- `issuedAt` — optional, epoch **milliseconds** the approval was minted. The
  expiry deadline is `min(issuedAt, now) + ttl`: a past `issuedAt` shortens the
  ticket's remaining life (mint-time semantics), a future or absent one falls
  back to ingest time. Fail-safe: a record can only expire sooner than
  `now + ttl`, never later.
- Each approval is **one-shot**: consumed by the first allowed call.
- Malformed lines and blank lines are skipped (fail-closed: no approval is
  minted from a bad record).

## Annotated example (`config/policy.example.json`)

```json
{
  "approval": {
    "control_file": "/tmp/seal-approvals.ndjson",  // approver writes NDJSON records here
    "ttl_seconds": 120                              // 2 minutes; values > 300 are clamped
  },
  "tools": [
    {
      "name": "db.execute",                         // guard db.execute ...
      "mode": "guarded",
      "match": {                                    // ... but only when the sql argument
        "type": "contains_any_ci",                  //     contains a destructive keyword
        "arg": "sql",                               //     (case-insensitive substring)
        "needles": ["drop", "delete", "truncate"]
      },
      "target": [                                   // approval binds to, in order:
        { "literal": "db" },                        //   the literal "db",
        { "arg": "database" },                      //   which database,
        { "literal": "write" },                     //   the literal "write",
        { "arg": "sql" }                            //   and the exact SQL text
      ]                                             // (tool name "db.execute" is prepended
    },                                              //  automatically before hashing)
    {
      "name": "payments.send",                      // every payments.send needs approval
      "mode": "guarded",
      "match": { "type": "always" },
      "target": [
        { "literal": "payment" },
        { "arg": "to" },                            // bound to recipient and amount:
        { "arg": "amount" }                         // approving one payment approves
      ]                                             // exactly that recipient+amount once
    },
    {
      "name": "shell.run",                          // never allowed, approval or not
      "mode": "deny",
      "match": { "type": "always" },
      "target": []
    }
  ]
}
```

Note: a `db.execute` whose `sql` contains no needle does not fire the
`contains_any_ci` match and is therefore **blocked by rule 2 above** (unmatched
policy), not silently allowed. To allow benign calls to a tool while guarding
destructive ones, list the tool once with the narrowing match only if blocking
the non-matching remainder is acceptable; otherwise use `match: always` and let
approvals gate everything.
