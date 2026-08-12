<!-- SPDX-License-Identifier: Apache-2.0 -->
# seal v2 — Threat Model

> **Milestone snapshot** (M8, the document the ARIA bid quotes). The canonical,
> maintained threat model is [`THREAT_MODEL.md`](../../../THREAT_MODEL.md) at the
> repository root.

> **We do not prove the agent is safe; we prove only modeled-route authorization behavior.**

seal v2 is a **verified compiler for approved payloads, not a filter.** It does not forward the
agent's bytes. It parses them to an AST, validates that AST to a *proof term*, re-serialises a fresh
canonical byte stream, and forwards only that. The target server never sees the agent's original
bytes. This document names the adversary, draws the trust boundary, states what each machine-checked
theorem does and does NOT guarantee, ledgers the residual assumptions A1–A6, and fixes the single
claim that may appear anywhere in the bid. The core it describes is re-verified: every named theorem
below carries axiom footprint `[propext, Classical.choice, Quot.sound]` and nothing else (see
`axioms.txt`, captured from a live `#print axioms` run, not asserted).

---

## 1. The adversary

**Who.** A compromised or malicious agent (or a prompt-injected one) driving a target MCP tool toward
an **unapproved or misinterpreted action**. The agent is assumed fully hostile and in control of the
byte stream it emits.

**Capabilities (in scope — seal must hold against all of these):**
- Arbitrary raw bytes at the seal entrypoint, including malformed, ambiguous, oversized, non-ASCII,
  duplicate-key, and non-canonical-numeric payloads.
- **Replay** — re-presenting a previously valid approval token.
- **Target mismatch** — a request whose tool/action/arguments do not match any live approval.
- **Expired-token reuse** — presenting a token past its TTL, or one whose lifetime exceeds the cap.
- **Forged or tampered signatures** — an approval token with a bad, wrong-key, or mutated signature.

Against this adversary the verified core is **fail-closed**: anything that is not a fully validated,
signed, live, single-use approval for the exact target becomes `Block`. The agent's bytes are never
forwarded; only bytes seal itself re-serialised from a validated AST reach the target.

**Out of scope (mapped to the residual assumptions, §4):**
- **Out-of-band access to the tool** — the agent reaching the target by any path that does not go
  through seal. → **A1 (channel exclusivity).**
- **Compromise of the Trusted Computing Base** — the Lean 4 kernel/compiler/runtime, the Ed25519
  implementation and approver-key custody, or the host I/O glue. → **A3 (TCB).**
- **OS-level concurrency beyond the host's serialisation** — preemption races the host's single
  mediation lock does not cover. → **A4 (store atomicity).**
- **Cross-restart replay** — a host restart that resets the in-memory store. → **A6 (durability).**
- **Whether the human approver understood what they signed** — seal proves origin, not intent
  (the "cryptographically valid rubber stamp"; see §4). 

---

## 2. The trust boundary

```
                 hostile agent bytes
                          │
                          ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │  TRUSTED GLUE  (A3 — engineered, fail-closed, NOT a theorem)      │
 │  Rust host: transport (stdio relay), approver-key custody,        │
 │  wall clock, single-thread + Mutex (A4); C ABI seam; JSON         │
 │  control marshalling; vendored TweetNaCl Ed25519 leaf.            │
 └─────────────────────────────┬─────────────────────────────────────┘
                  raw request bytes │  (control: config / approvals as JSON)
                                    ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │  VERIFIED CORE  (Lean 4, axiom-frozen M1–M7:                      │
 │                  [propext, Classical.choice, Quot.sound])         │
 │  parse → validate (→ ValidApproval proof term) → decide →       │
 │  serialize ; lifecycle consume over listReplayStore.              │
 │  The agent's raw bytes STOP here. Only re-serialised canonical    │
 │  bytes leave.                                                     │
 └─────────────────────────────┬─────────────────────────────────────┘
                                ▼
                fresh canonical bytes → target server
                                          (A2: target must parse them as seal intends)
```

The decision-bearing logic is the **verified core**. Everything that "grew" to make seal deployable —
the Rust host, the C ABI, the JSON seam for host *control* (config and approval intake; never the
security parser), the Ed25519 C leaf and key custody — is **declared trusted glue (A3), by design.** A
marshalling bug in the glue bypasses no Lean proof (Lean still decides); a *routing* bug (forwarding a
line seal said to block) would, which is why the glue is kept small and fail-closed. The pure-Lean
stdio sidecar remains the cleanest assurance story; the FFI host trades a larger TCB for deployability.

---

## 3. The named theorems — what each does and does NOT guarantee

All are machine-checked; all carry footprint `[propext, Classical.choice, Quot.sound]` only (the v1
footprint), build-locked by the `v2_m*_axiom_check` `#guard_msgs` gates.

### Fail-closed by totality, and parser canonicality
- **Guarantees:** the parser is a total function into `Option`; malformed/ambiguous bytes map to
  `none` unconditionally, and `decide` maps every `none` to `Block` (`Decision` has only `Block` and
  `Allow` — no third constructor) — there is no input for which the core "falls through". Moreover,
  every SUCCESSFUL public parse yields a CANONICAL AST: the accepted language is the strict,
  unambiguous subset (no duplicate keys, strict numeric bounds, canonical lowercase-escaped Unicode), so a non-canonical form
  cannot enter the pipeline.
- **Does NOT guarantee:** this covers the Lean CORE only — the host glue's own fail-closed behaviour is
  an engineered obligation (**A3**), not a theorem. And canonicality is seal-INTERNAL structure: it
  does NOT mean the target server parses those canonical bytes as seal intends (**A2**).
- **Formal:** `parse_total`, `parse_failure_has_no_ast`, `parse_returns_canonical`.

### `default_deny`
- **Guarantees:** if `parse` fails or `validate` rejects, `decide` returns `Block` — output bytes are
  unreachable. The only constructor that emits bytes requires a `ValidApproval` proof term.
- **Does NOT guarantee:** it says nothing about whether a *validated* request is what the human meant
  (that is the human-oracle limit, §4).
- **Formal:** `default_deny`.

### `non_bypass` — the capstone
- **Guarantees:** `decide raw state = Allow out` implies there exists an AST with `parse raw = some
  ast`, a `ValidApproval ast state` witness, and `out = serialize ⟨ast, witness⟩`. Every ALLOW
  reaches the target *only* through the verified parse → validate → serialize path, by construction.
- **Does NOT guarantee (stated as loudly as `canonical_roundtrip`):** this is **complete
  seal-INTERNAL mediation**. It does **NOT** prove the target server interprets the re-serialised
  canonical bytes the way seal validated them — that is **A2**, the per-server parser-differential.
  `non_bypass` closes the bypass *inside* seal; it does not and cannot close A2.
- **Formal:** `non_bypass`.

### `canonical_roundtrip`
- **Guarantees:** seal's own parse/serialize pair is self-consistent — re-parsing serialised canonical
  bytes yields the same AST — and `serialize` is deterministic (one representation per value).
- **Does NOT guarantee:** this is seal-internal self-consistency. It **explicitly does NOT close A2**;
  it says nothing about the *target's* parser agreeing with seal's schema. Do not describe this theorem
  as closing the differential.
- **Formal:** `canonical_roundtrip`, `serializeAst_deterministic`,
  `serialize_validCapability_roundtrip` (+ the per-shape `serialize_roundtrip_*`).

### `decide_emit_unique`
- **Guarantees:** `decide raw state = Allow out` iff the full mediated path holds and `out` is exactly
  `serialize` of that witness — the emitted bytes are uniquely determined by the validated value.
- **Does NOT guarantee:** target-side interpretation (A2) — same caveat as above.
- **Formal:** `decide_emit_unique`.

### Origin seam (M5)
- **Guarantees:** `validate` requires a real Ed25519 signature over EXACTLY the canonical
  `(target, session, issuedAt, expiry, nonce)` bytes (`signed_parse_canonical` pins those bytes to the canonical form;
  a non-canonical signed message is rejected before verification). The verify primitive itself adds NO
  axioms to the core.
- **Does NOT guarantee:** **origin, not intent.** Ed25519 proves *who signed*, not *what the human
  understood* — the "cryptographically valid rubber stamp" (§4). The crypto implementation is trusted
  (**A3**), not verified in Lean.
- **Formal:** `signed_parse_canonical`; `ed25519Verify` ("does not depend on any axioms").

### Lifecycle invariants (M6) — over the deployed store
- **Guarantees:**
  - `consume_records_nonce` — a successful consume records the nonce; the witness is never returned
    without it (atomicity in the model).
  - `replay_denied` — re-presenting a just-consumed token to the post-state is denied (single-use,
    same-clock; post-expiry denial is `consume_only_unexpired`).
  - `consume_preserves_live` (**state_monotonicity**) — live consumed entries are preserved across a
    consume; the consumed set only grows.
  - `consume_only_unexpired` — a consumed approval is unexpired (a valid signature on an expired
    approval is still denied — origin ≠ authorization).
  - `live_within_ttl_cap` — a live approval is within the configured TTL cap; over-cap is rejected.
- **Does NOT guarantee:** these hold GIVEN serialised store access (**A4** — the host Mutex makes
  read→consume→write atomic; OS-level TOCTOU-freedom is not proven) and for the LIVE process
  (**A6** — the in-memory store resets on restart).
- **Formal:** `consume_records_nonce`, `replay_denied`, `consume_preserves_live`,
  `consume_only_unexpired`, `live_within_ttl_cap` (supported by the witness projections
  `valid_capability_has_{unexpired_approval, unused_approval, signature_verified, session_bound,
  target_bound}` and `validate_none_no_witness_result`).

---

## 4. Residual assumptions ledger (A1–A6)

The bid claim is true **modulo** these. Each is named here, in code comments, and in the milestone
NOTES. None is described as "eliminated" or "entirely closed".

- **A1 — channel exclusivity.** The agent reaches the target tool ONLY via seal; out-of-band paths are
  out of scope. *Status:* stated, deployment precondition.
- **A2 — server-parse equivalence (THE parser-differential).** The target interprets `serialize(ast)`
  as seal's schema intends. *Status:* **minimised by construction — NOT closed.** Mitigation: a strict,
  unambiguous canonical subset (no duplicate keys, strict numeric bounds, canonical lowercase-escaped Unicode), manifest pinning
  at session start, and a target hash (canonicalised argument tree + tool-version + manifest-digest).
  This shrinks the differential to a per-server discharge obligation; it is **unprovable in general**
  and must never be called closed.
- **A3 — Trusted Computing Base.** The Lean 4 kernel/compiler/runtime; the **Ed25519 verifier — a
  vendored TweetNaCl detached-verify leaf** (single-file ~700-line public-domain reference, behind an
  opaque `@[extern]` seam, adding NO axioms to the core; exact version + SHA-256 pinned in
  `v2/milestones/05-sign/NOTES.md`); approver-key custody; and the host I/O glue. *Why this is
  acceptable TCB:* the crypto is small, widely reviewed, sits behind the opaque seam, and is axiom-free
  in the proof core — we trust a vetted reference impl rather than hand-rolling crypto. The TCB GREW at
  M7 to include the Rust transport, the C ABI seam, and JSON control marshalling. *Status:* stated,
  inventoried.
- **A4 — store atomicity.** The host serialises store access (single mediation thread + Mutex), making
  `read → consume → write` atomic — which is what makes `replay_denied` hold in deployment. OS-level
  TOCTOU-freedom is NOT proven; it is modelled atomic by construction. *Status:* stated;
  **concurrency-tested** at M7 (16 concurrent decides on one single-use token → exactly 1 Allow).
- **A5 — host-store refinement.** *Status:* **DISCHARGED by construction (M7).** The deployed store IS
  the verified `listReplayStore` (`List ConsumedNonce` in the Lean `IO.Ref`), mutated only via
  `validateAndConsumeWithStore`. There is no separate host store to refine, so the M6 invariants apply
  to the running store directly — discharged by NOT reimplementing it, not by proving a refinement.
- **A6 — durability.** The consumed-nonce store is an in-memory `IO.Ref`; on host restart it resets, so
  a nonce consumed before a restart re-Allows once. *Status:* **stated, not hidden.** This is a
  **deployment-configuration property (in-memory by design; a single authoritative mediation point),
  not a proof gap** — which is why it sits as "stated" rather than inside the modulo clause. If
  persistence is added it MUST restore consumed state THROUGH the Lean consume path (`seal_v2_decide`),
  never as a second authoritative store (that would re-open A5).

**The human-oracle limit (origin ≠ authorization).** Ed25519 proves an approval was signed by the
holder of the configured key. It does NOT prove the human understood, or intended, the action they
signed. A "cryptographically valid rubber stamp" — a signature obtained by deceiving the approver — is
indistinguishable, to seal, from genuine authorization. seal verifies origin; intent is outside the
formal boundary. We name this ourselves rather than leave it for a referee to find.

---

## 5. The claim

The single sentence that may appear, verbatim, anywhere in the bid:

> **Allow/forward origin-soundness within the modeled route; A1-A4, A2 minimised by construction, and A6 (durability) stated, not hidden.**

Nothing stronger is claimed anywhere. And the framing it earns:

> **We do not prove the agent is safe; we prove only modeled-route authorization behavior.**
