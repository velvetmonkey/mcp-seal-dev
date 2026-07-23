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
| An `Allow` implies a parsed AST + a `ValidApproval` witness, and the output is the canonical serialization of that witness | `SealV2/DecideTheorems.lean` non_bypass | Lean theorem, axiom-gated `{propext, Classical.choice, Quot.sound}` | Lean kernel/runtime | none | yes (for the v2 canonical core only) |
| Default-deny: output bytes are unreachable unless a `ValidApproval` term is built | `default_deny` | Lean theorem | as above | none | yes |
| Canonical serialize/parse roundtrip is self-consistent and deterministic | `canonical_roundtrip` | Lean theorem | as above | round-trip fidelity in-core is NOT parse-equivalence to the target server (A2) | yes |
| Approval lifecycle: issue -> target-bind -> one-shot consume -> TTL expiry, no replay after expiry | `LifecycleTheorems.lean` | Lean theorem | as above | A6 cross-restart durability | yes |
| Ed25519 signature verification over canonical `(target, session, issuedAt, expiry, nonce)` signed-message bytes | `SealV2/Crypto.lean` `ed25519Verify` (`@[extern]`) → `c/seal_ed25519.c` shim → vendored TweetNaCl | code + trusted crypto leaf | The shim enforces the RFC 8032 §5.1.7 `0 ≤ S < L` range check above TweetNaCl (which itself omits it), so malleable signatures are rejected — see **A3-S** (CLOSED) | S-range conformance RESTORED at the shim; see **A3-S** below. TweetNaCl trusted-leaf correctness remains the standing assumption | yes |
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

seal's approval abstraction uses an **`action`** field. Standard MCP
`tools/call` carries `params.name` + `params.arguments`; seal additionally reads
`params.action`. This is a seal extension, not a change to MCP. The binding:

```
MCP wire request:
  { "method": "tools/call",
    "params": { "name": <tool>, "action": <action>, "arguments": { ... } } }

Approval target:
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
- **A3-S** Ed25519 S-range / signature malleability — **FOUND then CLOSED (fix merged `a7cbbb9`, 2026-07-23).**
  HISTORY (kept for the record): the vendored TweetNaCl leaf (`c/tweetnacl.c`
  `crypto_sign_open`, `:796` feeds `S` straight to `scalarbase` with no range
  test) **omits the RFC 8032 §5.1.7 `0 ≤ S < L` check** that §8.4 names as what
  makes Ed25519 non-malleable. Surfaced by Wycheproof v1 `ed25519_test.json` @
  `b61843a9`: **5 of 62 must-reject signatures were accepted** — 4
  `SignatureMalleability` (tcId 63-66) + 1 S-above-bound (tcId 85).
  RESOLUTION: `c/seal_ed25519.c` now enforces `0 ≤ S < L` **above** the leaf,
  before `crypto_sign_open`, so the vendored `c/tweetnacl.c` stays byte-for-byte
  upstream (no fork to maintain). Post-fix the full corpus is **62/62 invalid
  rejected, 88/88 valid accepted** (runner exit 0); the boundary `S = L` is
  rejected (strict `<`), independently frisked. RFC 8032 §5.1.7 S-range
  conformance is RESTORED at the shim. The residual now is only the ordinary
  trusted-leaf assumption that TweetNaCl's group-equation arithmetic is correct
  (see `docs/TCB.md`, "Trusted crypto leaf"), NOT a malleability deviation.
  Bound that held even before the fix: seal's replay identity is the **nonce**,
  not the signature bytes (`ConsumedNonce = {ns, nonce, expiresAt}`,
  `SealV2/Validation.lean:88-92`; namespace excludes the signature; `replay_denied`,
  `SealV2/LifecycleTheorems.lean:84`), so no record keys on signature bytes and a
  malleated signature never bought a double-spend.
- **A6** cross-restart replay durability: in-process store discharges A5 for the live process only; durable store is a stated deployment residual, first funded hardening item.

## Response egress

seal mediates **request-effects**, not responses. Never say "seal prevents
leaks." It prevents unapproved effects through the mediated request boundary.
