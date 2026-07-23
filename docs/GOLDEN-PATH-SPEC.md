# Golden-Path Spec — the shell reference cell, as theorems

**Audience: the scaffolder/demo builder (Codex). No Lean required.** Everything
`seal init` and the shell demo claim is anchored to a named theorem in this
repository; this document is the contract between the generated artifacts and
those proofs.

> **Sequencing constraint (build coordination).** This branch
> (`feat/golden-path-spec`) — the allow-rule grammar, the totalized
> `matchSpec`, and the scaffold proofs — is the **canonical base** once merged.
> Anything that rebuilds the native `.so` or repins seal-host must build from
> *that merged commit*, never from an independent copy of the pre-merge
> working tree: a `.so` built from the pre-totalization `Seal/Classify.lean`
> would not match the proven classifier. This repo owns `Classify.lean`;
> downstream builds consume it.

## 1. The scaffold mapping (`seal init`)

Input: the MCP tool manifest (tool names + `annotations.readOnlyHint` /
`annotations.destructiveHint`). Output: one policy rule per tool. The mapping
is the Lean function `Seal.scaffoldMode` (`Seal/Scaffold.lean`) — the
generator must reproduce it exactly:

| Manifest annotation | Generated mode | Guarantee (proven) |
|---|---|---|
| `readOnlyHint: true`, no destructive claim | `allow` | Classifies benign; flows with no approval (`scaffold_readonly_flows`). **Trust caveat below.** |
| `destructiveHint: true` | `guard` | Never reaches the wire without a live approval bound to exactly this call's full arguments (`scaffold_safety` + `shell_exec_requires_live_approval`). |
| No annotations / unknown | `guard` | Same as destructive: unknown is treated as dangerous (`dangerous_annotation_guarded`). |
| `readOnlyHint: true` **and** `destructiveHint: true` (conflict) | `guard` | Conflicting claims never resolve to allow (`dangerous_annotation_guarded`). |
| — | never `deny` | The scaffolder cannot brick a server, only interpose (`scaffoldMode_ne_deny`). |

Structural guarantees of the generated policy:

- **Exact tool names, no wildcards.** A tool absent from the manifest is
  default-denied (`scaffold_unknown_tool_default_deny`).
- **Every guard binds the full canonical arguments** (`target = full_arguments`),
  so an approval for `rm -rf /tmp/x` never authorizes `rm -rf /` — distinct
  argument bytes give distinct targets (structural half
  `full_arguments_preimage_changes`; the digest step uses A-CR, the
  idealised hash-injectivity assumption — strictly stronger than collision
  resistance, see docs/ASSUMPTIONS.md).
- **Duplicate manifest entries are safe.** If any entry for a name is
  dangerous, the name classifies guarded even if another entry says readonly
  (guard dominates allow — `guard_dominates_explicit_allow`; all scaffolded
  guards for a name share one target, so no ambiguity deny).

Generated rule shape (consumed by `Seal/Policy.lean`'s parser):

```json
{
  "server": "<server identity>",
  "approval": { "ttl_seconds": 120, "control_file": "seal-approvals.jsonl" },
  "tools": [
    { "name": "shell_exec", "mode": "guard",
      "target": [ { "full_arguments": true } ] },
    { "name": "read_file", "mode": "allow" }
  ]
}
```

> **Trust caveat (row 1, REQUIRED in generated output).** Annotations are
> trusted input: a manifest that lies about `readOnlyHint` defeats the allow
> row. The proof scopes this risk (that is why unknown defaults to guard); it
> does not remove it. `seal init` MUST label every generated `allow` rule as
> an **unverified suggestion** (comment in the generated file + stdout
> notice) so the operator reviews it before signing.

## 2. Boundary card — what the demo may claim

Three theorem groups back the demo's boundary card. Cite them by name; the
axiom footprint of every one is within `{propext, Classical.choice,
Quot.sound}` (`lake exe axiom_check`).

### Card 1 — "This block is a theorem, not a string match"
- **Plain English:** under the scaffolded shell policy, a destructive
  `shell_exec` call (any arguments, `rm -rf /` included) is classified
  guarded; the gate forwards it only if state holds a live, unconsumed,
  unexpired approval for exactly that call's target. On a fresh session it
  blocks outright. After a matching approval it flows exactly once.
- **Lean:** `Seal.shell_exec_requires_live_approval`,
  `Seal.shell_rm_rf_blocks_on_fresh_state`,
  `Seal.shell_rm_rf_allows_with_fresh_approval`,
  `SealCore.consumed_approval_not_live` — `Seal/GoldenPath.lean`,
  `SealCore/Safety.lean`.
- **Contrast leg:** `read_file` is benign and never waits
  (`Seal.shell_read_flows`).

### Card 2 — "The policy that blocked you is the policy that was signed"
- **What is signed:** the exact policy text bytes. **Which key:** the policy
  signing key (operator-held); verification is Ed25519 over those bytes.
- **Plain English:** a policy whose signature does not verify — tampered
  bytes, wrong key, malformed hex — is never parsed and never consulted:
  every call under it is default-denied and blocked at the wire. Fail-closed,
  never fail-open.
- **Lean:** `Seal.tampered_policy_fail_closed`, `Seal.tampered_policy_blocks`,
  `Seal.malformed_signature_hex_fails` — `Seal/SignedPolicy.lean`.
- **Honesty note:** `classifyUnderSignedPolicy` is the reference gate. That
  the deployed runtime calls it (verify-then-parse, in that order) is an
  engineering claim under assumption A3, asserted by the runtime self-test —
  not itself a theorem.

### Card 3 — "A tampered approval token can never be the passing witness"
- **What is signed:** the canonical signed-message bytes of the approval
  (target + session + issuedAt + expiry + nonce). **Which key:** the session
  `publicKey` in the v2 state envelope.
- **Plain English:** an approval that fails signature verification is never
  treated as live and never found by validation; if no approval in state
  verifies, every request is blocked. Positively: every Allow carries a
  validation witness whose approval signature DID verify.
- **Lean:** `SealV2.tampered_approvals_deny`,
  `SealV2.allow_implies_witness_signature_verified`,
  `SealV2.approval_live_implies_signature_verified` —
  `SealV2/TamperTheorems.lean`, resting on `SealV2.non_bypass`.

**What the receipt establishes:** the decision was derived from the signed
policy and a signature-verified approval bound to the exact argument bytes.
**What it does NOT establish:** that the underlying tool did what it said,
that the manifest annotations were honest, or anything about traffic that
never passed through the gate.

## 3. Non-claims — say these loudly

1. **Mediated path only.** Every theorem governs calls that reach the seal
   gate. An agent that bypasses the MCP server entirely — direct shell, a
   second unmediated server, in-process execution — is OUT OF SCOPE. The demo
   must state this on the boundary card, not in a footnote.
2. **Annotations are trusted input.** See the row-1 caveat: `readOnlyHint`
   is the manifest author's claim, not a verified property.
3. **Hash binding is A-CR.** "Different arguments ⇒ different target" is
   proven at the pre-image level; the digest step uses A-CR, an idealised
   perfect-injectivity assumption about the hash — strictly stronger than
   SHA-256 collision resistance and not satisfiable by any real fixed-output
   hash over unbounded inputs. The digest conclusion holds in the idealised
   collision-free model; in deployment it is the trust assumption that no
   SHA-256 collision is findable for the relevant inputs, which Lean does
   not prove (see docs/ASSUMPTIONS.md).
4. **Crypto and glue are A3.** `ed25519Verify` correctness, the C/Rust
   transport, and key custody are TCB assumptions, same posture as
   `Ffi.lean`.
5. **Lean gate ↔ runtime wiring is an engineering claim.** The proofs pin
   the reference semantics; `scaffold_tests` and the runtime self-test check
   the deployed binary agrees, but agreement is evidence, not theorem.

## 4. Runtime obligations for the demo

- Run the anti-theater self-test at startup: mutate one policy byte →
  expect deny; mutate one approval byte → expect deny. (This asserts at
  runtime what Cards 2–3 prove about the reference gate.)
- `lake exe scaffold_tests` is the compiled end-to-end harness (real
  SHA-256) for the mapping table, the block/approve/consume cycle, and the
  tampered-policy denial. CI runs it alongside `policy_v2_tests` and
  `axiom_check`.
- **Promotion gate:** a clean release-runner build (full library, not the
  dev box's incremental targets) is mandatory before any of this ships.
