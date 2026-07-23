<!-- SPDX-License-Identifier: Apache-2.0 -->
# mcp-seal-dev: claims map

Single source of truth for the v2 verified canonical core. Scoped to
`mcp-seal-dev`. Sibling map: `seal-host/CLAIMS.md` (multi-kernel host).
Nothing in any demo, README, or pitch may exceed a row marked
"can say publicly = yes".

Repo layout: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Theorem index with
file and line locations: [docs/PROOF-REFERENCE.md](docs/PROOF-REFERENCE.md).

## The one line

> Policy-covered, unapproved request-effects cannot execute through the
> mediated MCP boundary.

NOT: "the agent is safe" / "the whole stack is verified" / "theorems cannot be
bypassed."

## Claims matrix

| Claim | Artifact | Proof status | Trusted assumptions | Known residuals | Say publicly? |
|---|---|---|---|---|---|
| An `Allow` implies a parsed AST + a `ValidCapability` witness, and the output is the canonical serialization of that witness | `SealV2/DecideTheorems.lean` non_bypass | Lean theorem, axiom-gated `{propext, Classical.choice, Quot.sound}` | Lean kernel/runtime | none | yes (for the v2 canonical core only) |
| Default-deny: output bytes are unreachable unless a `ValidCapability` term is built | `default_deny` | Lean theorem | as above | none | yes |
| Canonical serialize/parse roundtrip is self-consistent and deterministic | `canonical_roundtrip` | Lean theorem | as above | round-trip fidelity in-core is NOT parse-equivalence to the target server (A2) | yes |
| Approval lifecycle: issue -> target-bind -> one-shot consume -> TTL expiry, no replay after expiry | `LifecycleTheorems.lean` | Lean theorem | as above | A6 cross-restart durability | yes |
| Ed25519 signature verification over canonical `(target, session, issuedAt, expiry, nonce)` signed-message bytes | `SealV2/Crypto.lean` `ed25519Verify` (`@[extern]`, TweetNaCl leaf) | code + trusted crypto leaf | TweetNaCl verify computes the cofactorless group equation; it does **not** enforce the RFC 8032 §5.1.7 S-range check, so signatures are malleable — see **A3-S** | S-range/malleability deviation: **A3-S** below (not "none"). Blast radius bounded — replay identity is the nonce, not the signature | yes (with A3-S stated) |
| Principal non-influence: for a fixed judged line and approval state, the decision VALUE is invariant under the authenticated principal — the policy language cannot express "who is asking" (model property; WHETHER a decision is produced still depends on the principal) | `SealV2/PrincipalNonInfluence.lean` `principal_non_influence` + runnable control `lake exe principal_non_influence_show` | Lean theorem, axiom-gated `{propext, Classical.choice, Quot.sound}`; witness conditional on the crypto seam, discharged at runtime with real Ed25519 | Lean kernel/runtime, TweetNaCl (SHOW leg) | approval issuance and host-side behaviour may depend on the principal; scope stated in the module docstring | yes (scoped exactly as stated) |
| This does NOT prove every deployed MCP server is mediated | n/a | n/a | n/a | n/a | this is a NON-claim, state it |

## The parser is a canonical mediation profile, NOT "the JSON parser"

`SealV2/Parser.lean` accepts a **strict canonical subset**, not arbitrary JSON:
strings may denote any Unicode scalar sequence, but non-ASCII and control
characters must use SealV2's canonical lowercase escape form (`\uXXXX` plus the
short escapes), with exactly one canonical byte representation per string;
numbers reject exponent notation, trailing-zero fractions, leading-zero forms,
and negative zero; no duplicate keys. Literal non-ASCII bytes, non-canonical
escapes (uppercase hex, long form where a short or literal form is required,
lone or misordered surrogates), and malformed or ambiguous bytes evaluate to
`none` (fail-closed).

Call it the **canonical mediation profile**. If you call it "the JSON parser" a
reviewer will throw Unicode, escapes, exponent numbers, duplicate keys, or
ordinary noncanonical JSON at it and think they found a flaw. They found the
profile boundary, working as specified.

## MCP action binding (define it, do not surprise the reviewer)

seal's capability abstraction uses an **`action`** field. Standard MCP
`tools/call` carries `params.name` + `params.arguments`; seal additionally reads
`params.action`. This is a seal extension, not a change to MCP. The binding:

```
MCP wire request:
  { "method": "tools/call",
    "params": { "name": <tool>, "action": <action>, "arguments": { ... } } }

Capability target:
  tool   <- params.name
  action <- params.action
  args   <- selected fields of params.arguments

Validated against the pinned manifest entry:
  { "tool": <tool>, "version": <v>, "actions": [ <allowed actions> ] }
```

(`Ffi.lean` request extraction; `Test/V2ValidationFixtures.lean` request shape.)
An unknown `(tool, action)` pair validates to `none` (fail-closed).

The v1 shipped binary uses a different, simpler policy format (tool rules +
target parts + control-file approvals): [docs/POLICY.md](docs/POLICY.md).

## Residuals

- **A2** numeric/parse fidelity minimised by construction; per-server equivalence obligation remains.
- **A3-S** Ed25519 S-range / signature malleability. The vendored TweetNaCl
  verify leaf (`c/tweetnacl.c` `crypto_sign_open`, reached via
  `SealV2/Crypto.lean` `ed25519Verify` → `c/seal_ed25519.c:30`) is
  **cofactorless** and **omits the RFC 8032 §5.1.7 `0 ≤ S < L` check**
  (`c/tweetnacl.c:796` feeds `S` straight to `scalarbase`, no range test, no
  reduction). RFC 8032 §5.1.7 *mandates* that check ("If any of the decodings
  fail (including S being out of range), the signature is invalid"); §8.4 names
  it as what makes Ed25519 non-malleable. So the leaf is **non-conformant to
  RFC 8032 on this point and accepts malleated signatures** (`S' = S + m·L`).
  Measured on Wycheproof v1 `ed25519_test.json` @ `b61843a9`: **5 of 62
  must-reject signatures accepted** — 4 `SignatureMalleability` (tcId 63-66) +
  1 S-above-bound (tcId 85); the other **57 of 62 invalid rejected, all 88 valid
  accepted**. What it buys an attacker: many verifying signatures for one
  message. What it does **not** buy: a double-spend. Seal's replay identity is
  the **nonce**, not the signature bytes — `ConsumedNonce = {ns, nonce,
  expiresAt}` (`SealV2/Validation.lean:88-92`), the namespace excludes the
  signature (`:260-270`), and `replay_denied` (`SealV2/LifecycleTheorems.lean:84`)
  proves re-presentation of a consumed nonce Blocks. Verified live end-to-end: a
  valid approval Allows and consumes the nonce, then the malleated variant
  (same nonce) **Blocks**; the malleated variant alone Allows a fresh token,
  confirming the Block is a replay block, not a rejection. No record in this repo
  keys on signature bytes. Full variant label and citations: `docs/TCB.md`
  ("Trusted crypto leaf"). Adding an `S < L` check to `c/seal_ed25519.c` would
  restore conformance and is a separate decision (not taken here).
- **A6** cross-restart replay durability: in-process store discharges A5 for the live process only; durable store is a stated deployment residual, first funded hardening item.

## Response egress

seal mediates **request-effects**, not responses. Never say "seal prevents
leaks." It prevents unapproved effects through the mediated request boundary.
