# M2 validate notes

M2 implements constructive validation:

```lean
validate : AST -> ApprovalState -> Option (Σ ast, ValidApproval ast state)
```

Success returns a proof-carrying witness. Failure returns `none`, so parse-valid but policy-invalid payloads cannot produce a `ValidApproval` term.

## Witness contents

`ValidApproval ast state` carries:

- decoded `tools/call` request from `ast`
- matching tool spec and allowed action
- target binding to tool, action, tool version, manifest digest, and argument AST
- matching approval from `ApprovalState`
- session binding
- `approval.consumed = false`
- `state.now <= approval.expiresAt`
- `SignatureVerified state.publicKey approval`

## Signed message contract

The signed message is exactly:

```text
(target, session, issuedAt, expiry, nonce)
```

M2 represents that message as `SignedMessage` and `signedMessageAst`. The M2 signature check is a stub, but it verifies only this five-field message shape. M3 must reuse the single canonical serializer for `signedMessageAst`; M5 must verify real Ed25519 over those canonical bytes.

## M6 carry-forward

M2 proves `consumed = false` in the validation witness but does not consume approvals. M6 must make validation and consumption atomic inside `decide`. `state_monotonicity` must connect the consumed transition to the `approval_unused` fact in this witness, with no TOCTOU window.

## Claim boundary

M2 does not claim complete mediation or target-parser equivalence. A2 remains a per-server obligation.
