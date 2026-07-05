# seal v2 status

## M1 strict-subset parser

Status: implemented; local review gate passed.

M1 adds the v2 parser beside the shipped v1 sidecar. The v1 `seal` binary remains unchanged. The parser entrypoint is:

```lean
parse : RawBytes -> Option AST
```

The parser is total and fail-closed into `Option`. Malformed, ambiguous, duplicate-key, non-ASCII, partial, trailing-byte, or non-canonical numeric inputs return `none`.

### Canonical decimal grammar

M1 uses fixed decimal form rather than integers-only:

```text
number ::= "-"? int frac?
int    ::= "0" | [1-9][0-9]*
frac   ::= "." [0-9]* [1-9]
```

Rules:

- Exponents are rejected.
- Leading zeroes are rejected except the literal `0`.
- Negative zero is rejected.
- Fractions require at least one digit and must not end in `0`.
- Accepted examples: `0`, `12`, `-12`, `0.5`, `-0.5`, `0.05`, `12.34`.
- Rejected examples: `-0`, `00`, `01`, `1.0`, `1.20`, `1.`, `.5`, `1e3`.

### A2 number residuals for M3 and threat model

- No exponent support means values such as `6.022e23` and `1e-9` are intentionally unrepresentable and blocked.
- Numeric fidelity remains an A2 per-server obligation. A canonical decimal such as `0.12345678901234567890` can still diverge if the target server parses into `float64` or another bounded numeric representation.

### Review notes

- The parser differential is named as A2 and remains a per-server obligation.
- M1 does not claim target-parser agreement.
- M1 does not build Plan C transport.

## M2 constructive validation

Status: implemented; local review gate passed.

M2 adds:

```lean
validate : AST -> ApprovalState -> Option (Σ ast, ValidCapability ast state)
```

Validation is constructive. A successful result carries a `ValidCapability` witness, not a boolean. The witness contains the decoded request, matching tool spec, exact target binding, exact approval, session binding, `consumed = false`, expiry proof, and `SignatureVerified`.

### Signed message seam for M5

M2 defines the signed message as exactly:

```text
(target, session, issuedAt, expiry, nonce)
```

The message is represented as a canonical AST-shaped value through `signedMessageAst`. M2's crypto was stubbed by `stubSignatureFor`, but the shape is this five-field value. M3 serializes the same canonical message value; M5 verifies Ed25519 over those canonical bytes, not over a separate ad-hoc encoding.

M3 scaffold strengthening: `ValidCapability` now carries `ast_canonical : IsCanonical ast`. This is additive to M2's witness facts; the six M2 witness lemmas remain unchanged. The strengthening is required so `serialize` can be proof-gated without making canonicality circular through `parse` or `serialize`.

### M6 atomic consume carry-forward

`ValidCapability` proves `approval.consumed = false`; M2 does not consume. M6 must make the validate-and-consume transition atomic inside `decide`, with no TOCTOU window between proving an approval live and consuming it. The M6 `state_monotonicity` theorem must connect directly to the `consumed = false` fact carried by the M2 witness.

## M3 canonical serialization

Status: complete; merged to `main`. All M3 obligations are discharged with zero `sorry`, no `native_decide`, and the axiom gate is green.

M3 adds a standalone structural canonicality predicate and proof-gated serialization:

```lean
IsCanonical : AST -> Prop
serializeAst : {ast // IsCanonical ast} -> CanonicalBytes
serialize : (Σ ast, ValidCapability ast state) -> CanonicalBytes
```

`IsCanonical` is structural only. It does not reference `parse` or `serialize`. `serializeAst` computes on the AST value only, so proof terms cannot influence emitted bytes.

The M2 signed-message stub now routes through the same `serializeAst` path on `signedMessageAst`; the previous `repr` stub is removed. There is one canonical serializer for both output bytes and signed-message bytes.

M3 scaffold contained named obligations for Groups A-D in `SealV2/SerializationTheorems.lean`. All are now proved: Group A canonicality after parser tightening, and Groups B-D the value, array, and object serialization roundtrips via fuel-based mutual induction. The keystone `value_roundtrip_size` closes the recursion. Zero `sorry`, no `native_decide`.

### M3 axiom footprint (verified)

`lake exe v2_m3_axiom_check` confirms all 14 M3 theorems depend only on `[propext, Classical.choice, Quot.sound]`. No `sorryAx`. Covered theorems include `parse_returns_canonical`, `serialize_roundtrip_{null,bool,number,string,array,object}`, `canonical_roundtrip`, `serializeAst_deterministic`, and `serialize_validCapability_roundtrip`.

Claim discipline: `canonical_roundtrip` means seal self-consistency only. A2, target-parse equivalence, remains the per-server obligation, minimised by construction and by the differential fixture, not eliminated.

### M3 parser tightening

Aristotle found that the original Group A worker obligations were not strong enough around number parsing counterexamples such as `-0.0` and `-00.0`. M3 tightened the public parser workers so every successful public parse worker result is guarded by `IsCanonical`.

The parser remains fail-closed and does not normalise. Non-canonical numeric forms such as `-0`, `-0.0`, `-00.0`, `00`, `01`, `-00`, `1.0`, `1.20`, `1.`, `.5`, `1e3`, `1E3`, and `6.022e23` return `none`. The strict Group A theorem `parse raw = some ast -> IsCanonical ast` is now proved with no `sorry`.

## M4 mediated decide and non-bypass

Status: complete; merged to `main`. All M4 obligations are discharged with zero `sorry`, no `admit`, no `native_decide`, and the axiom gate is green. Milestone artifacts are filed under `v2/milestones/04-decide/` (`run.sh`, `axioms.txt`, `fixture-run.txt`, `decide-corpus.txt`); reproduce with `bash v2/milestones/04-decide/run.sh`.

M4 adds the single mediated decision path:

```lean
Decision.Block : Decision
Decision.Allow : CanonicalBytes -> Decision
decide : RawBytes -> ApprovalState -> Decision
```

`decide` is fail-closed by exhaustive case analysis. It blocks if parsing fails or validation fails, and it allows only bytes produced by `serialize` from the proof-carrying `validate` witness.

M4 proves:

```lean
non_bypass :
  decide raw state = Decision.Allow out ->
    ∃ ast, parse raw = some ast ∧
      ∃ w : ValidCapability ast state, out = serialize ⟨ast, w⟩

default_deny :
  (parse raw = none ∨
    ∃ ast, parse raw = some ast ∧ validate ast state = none) ->
  decide raw state = Decision.Block

decide_emit_unique :
  decide raw state = Decision.Allow out ↔
    ∃ ast, parse raw = some ast ∧
      ∃ w : ValidCapability ast state,
        validate ast state = some ⟨ast, w⟩ ∧
          out = serialize ⟨ast, w⟩
```

### M4 axiom footprint (verified)

`lake exe v2_m4_axiom_check` is now a build-breaking guard, not just a printer. It locks `canonical_roundtrip`, `serialize_validCapability_roundtrip`, `decide_emit_unique`, `non_bypass`, `default_deny`, and `signed_parse_canonical` to `[propext, Classical.choice, Quot.sound]`. The captured footprint is in `v2/milestones/04-decide/axioms.txt`.

### M4 end-to-end acceptance

`test/v2/m4_adversarial_mcp_fixture.py` drives the public `decide` entrypoint (via the `v2_decide_line` exe) against the fixture approval state: the single legitimate mediated call returns `Allow`; 15 adversarial / malformed / non-canonical / near-miss lines each return `Block`. This is seal-internal complete mediation, demonstrating `default_deny` and `non_bypass` operationally — NOT the A2 parser-differential, which stays a per-server obligation, minimised by construction.

## Signed-approval canonicality closure

Status: implemented and proven. The canonicality theorem `signed_parse_canonical` is discharged in Lean (axiom-clean), so the signed path has no remaining proof obligation.

The general JSON-RPC parser remains whitespace-tolerant. The signed-approval path is stricter:

```lean
signedParse : RawBytes -> Option {ast // IsCanonical ast}
signedMessageRawFor : SignedMessage -> RawBytes
```

`signedParse` parses the raw signed-message bytes and then rejects unless `raw == serializeAst parsedAst`. `Approval` now carries `signedMessageRaw`, and `verifySignature` checks the signature against that exact raw field only after `signedParse` accepts it and the parsed signed-message AST matches `(target, session, issuedAt, expiry, nonce)`.

This closes the reviewed bypass where non-canonical bytes could be accepted by parsing, normalised to canonical bytes, and then verified over the normalised payload. Non-canonical witnesses such as trailing whitespace, leading whitespace, and interior insignificant whitespace are rejected by the signed path and make `decide` return `Block`.

Discharged proof obligation (proven):

```lean
signed_parse_canonical :
  signedParse raw = some ast -> raw = serializeAst ast
```

This theorem is **proven** in `SealV2/ValidationTheorems.lean` (complete proof, no `sorry`), and its axiom footprint is locked to `[propext, Classical.choice, Quot.sound]` by a build-breaking `#guard_msgs` check in `Test/V2M4Axioms.lean`. The signed path has no remaining proof obligation.

## M5 Ed25519 origin seam

Status: complete; merged to `main`. The M2 signature **stub** is replaced by **real
Ed25519** verification over EXACTLY the canonical `(target, session, issuedAt, expiry,
nonce)` bytes from the M3 serialiser. Zero `sorry`/`admit`/`native_decide`; axiom
footprint unchanged.

```lean
-- SealV2/Crypto.lean
@[extern "lean_seal_ed25519_verify"]
opaque ed25519Verify (publicKey message signature : ByteArray) : Bool
```

`verifySignature` hex-decodes the public key and signature and calls `ed25519Verify`
over `approval.signedMessageRaw.toUTF8` (fail-closed on malformed hex). The real
verification is performed by vendored TweetNaCl (`c/tweetnacl.*`, version 20140427,
SHA-256 pinned in `v2/milestones/05-sign/NOTES.md`) behind the FFI shim
`c/seal_ed25519.c`, linked via package `moreLinkArgs`.

### Axiom footprint (verified)

`opaque` + `@[extern]` add **no axiom**. The six named theorems still depend only on
`[propext, Classical.choice, Quot.sound]`, and `ed25519Verify` itself depends on no
axioms (captured in `v2/milestones/05-sign/axioms.txt`). The proofs consume
`verifySignature` only as a runtime `Bool` hypothesis, so the swap is proof-transparent.

### Claim discipline (origin authenticated, NOT proven)

Now allowed: **"origin authenticated via Ed25519 over the canonical
`(target, session, issuedAt, expiry, nonce)` bytes."** Origin is **NOT proven in Lean** — it rests on
the channel (the signature) and on the explicit TCB assumption **A3 = "the vendored
Ed25519 verify is correct."** The PROOF guarantees ordering/canonicality and
seal-internal mediation; the CHANNEL guarantees origin. Authenticating origin is not
authorizing intent: the M5 corpus shows a VALID signature on an EXPIRED approval is
still Blocked. Never "eliminated"; A2 stays a per-server obligation, minimised by
construction.

### Acceptance

`test/v2/m5_sign_fixture.py` (real Ed25519 via Python `cryptography`) drives
`v2_verify_line`: **2 accepted, 6 rejected** — valid sig, bad sig, wrong key, tampered
byte, wrong-length, e2e accept, expired-valid-sig, wrong-key e2e. Filed under
`v2/milestones/05-sign/`; reproduce with `bash v2/milestones/05-sign/run.sh`.

## M6 lifecycle / TTL

Status: complete; merged to `main`. Five named invariants proven over the replay store
state-machine (`validateAndConsumeWithStore` against the reference `listReplayStore`), all
axiom-clean. Zero `sorry`/`admit`/`native_decide`.

```lean
-- SealV2/LifecycleTheorems.lean
consume_records_nonce   -- atomicity: success records the nonce in the returned store
replay_denied           -- single-use: re-presenting a consumed token to the post-state denies
consume_preserves_live  -- state monotonicity: live consumed entries are preserved
consume_only_unexpired  -- expiry: a consumed approval is unexpired (origin ≠ authorization)
live_within_ttl_cap     -- TTL cap: a live approval is within the cap
```

### Replay-namespace re-key (design note)

`ReplayNamespace` now keys on the canonical string `serializeTargetKey target` (the M3 total value
serialiser) rather than the structured `Target`. The structured `AST` arguments carry a WF-recursive
derived `BEq` that does not reduce, making `(ns == ns) = true` on the replay path unprovable; keying on
the canonical string makes namespace equality `String`-only and reflexive. Semantically equivalent by
M3 canonicality; M1–M5 proofs and the full axiom footprint re-verified unchanged.

### Axiom footprint (verified)

`v2_m6_axiom_check` build-locks the five theorems to `[propext, Classical.choice, Quot.sound]`
(captured in `v2/milestones/06-lifecycle/axioms.txt`). The full M1–M6 set re-verified with no drift.

### Honesty boundary (A4, A5)

- **A4** — the invariants hold GIVEN serialized/locked store access (host obligation). Model atomicity
  is by construction; OS-level TOCTOU-freedom is NOT proven in Lean.
- **A5** — proofs are over the concrete reference `listReplayStore`; the deployed host store (M7) must
  refine its semantics, NOT yet proven (carried as an explicit M7 obligation).
- Expiry blocks even a valid signature (origin ≠ authorization). Never "eliminated"; A2 per-server,
  minimised by construction.

### Acceptance

`Test/V2Lifecycle.lean` (`v2_lifecycle_tests`) over the real store machine: **2 allowed, 3 blocked** —
fresh token (real M5 Ed25519 signature), replay → Block, consumed-nonce recorded, expired-valid-sig →
Block, ttl-over-cap → reject. Filed under `v2/milestones/06-lifecycle/`; reproduce with
`bash v2/milestones/06-lifecycle/run.sh`.

## M7 Rust host glue

Status: complete; merged to `main`. C FFI export of the verified core + a Rust host driving it
end-to-end (raw bytes → Decision), store and approver-key custody host-driven. CORE axiom footprint
UNCHANGED — `Ffi.lean` is IO glue with no theorems and adds no axioms.

C ABI surface (string-in/string-out JSON, mirrors seal-host): `Ffi.lean` holds the session in
`initialize stateRef : IO.Ref (Option ApprovalState)` and exports `seal_v2_init` / `seal_v2_add_approval`
(reconstructs an `Approval` via the verified `signedParse`+`signedMessageFromAst?`) / `seal_v2_decide`
(verified `parse → validateAndConsumeWithStore listReplayStore → serialize`). Self-contained
`libsealv2ffi.so` hand-linked by `scripts/build_ffi_so.sh` (core objects + `ffi_shim.c` +
`c/build/libsealcrypto.o`, against dynamic `libleanshared`). Rust host in `rust/` (`src/lean.rs`
runtime init + A4 Mutex; `src/main.rs` selftest + stdio `serve`).

### A5 discharged; A4 carries M6; A6 new

- **A5 DISCHARGED (live process)**: the deployed store IS the verified `listReplayStore` in the Lean
  `IO.Ref`, mutated only via `validateAndConsumeWithStore`. No separate store to refine — the M6
  invariants apply to the running store. (Reference-note A5 line: discharged at M7, store IS listReplayStore.)
- **A4 load-bearing**: the host `Mutex` makes read→consume→write atomic, which is what makes M6's
  single-use hold in deployment. Test-covered by a 16-thread concurrency probe (exactly 1 Allow).
- **A6 (new, durability)**: `stateRef` is in-memory; restart re-Allows pre-blocked nonces. Stated, not
  hidden. Persistence must restore through the consume path.
- **A3 grows**: Rust transport + C ABI + JSON marshalling + key custody are trusted glue (documented).

Claim discipline: **complete mediation modulo A1–A4, A6 stated**. Never "eliminated".

### Acceptance (end-to-end through the C ABI)

`rust/src/main.rs selftest` (real M5 test vector): fresh token **Allow**, replay **Block**, expired
(valid sig, now>expiry) **Block**, tampered signature **Block**, malformed + target-mismatch **Block**,
A4 probe **16 concurrent → 1 Allow**. Filed under `v2/milestones/07-host/`; reproduce with
`bash v2/milestones/07-host/run.sh`.

## M8 threat model — v2 build COMPLETE

Status: complete; merged to `main`. The bid-facing capstone. Adds NO theorems — it WRITES
`v2/milestones/08-threat-model/THREAT-MODEL.md` (the document the ARIA bid quotes) and re-verifies the
M1–M7 footprint it rests on. Five parts: adversary; trust boundary (verified core vs trusted glue A3);
every named theorem with its GUARANTEE and NON-guarantee (both `non_bypass` and `canonical_roundtrip`
explicitly do NOT close A2); the A1–A6 residual ledger; the claim.

### Footprint (re-verified, not asserted)

All 16 named theorems carry `[propext, Classical.choice, Quot.sound]` only; `ed25519Verify` depends on
no axioms; zero `sorry`/`admit`/`native_decide`. Captured from a live `#print axioms` run in
`v2/milestones/08-threat-model/axioms.txt`; the `v2_m*_axiom_check` `#guard_msgs` gates are
build-breaking (M5's `signed_parse_canonical` is locked inside the m4 gate).

### The claim (canonical string — byte-identical across THREAT-MODEL / NOTES / STATUS)

> complete mediation modulo A1-A4, with A2 minimised by construction; A6 (durability) stated, not hidden.

Framing: **We do not prove the agent is safe; we prove the environment is safe from the agent.**
A1–A6: A1 channel exclusivity (stated); A2 server-parse equivalence (minimised by construction, NEVER
closed); A3 TCB (Lean + TweetNaCl Ed25519 leaf + key custody + host glue); A4 store atomicity (host
Mutex; concurrency-tested); A5 host-store refinement (DISCHARGED by construction at M7); A6 durability
(in-memory by design; stated, not hidden). Origin ≠ authorization named (the human-oracle limit).
Reproduce with `bash v2/milestones/08-threat-model/run.sh`.

**seal v2 build COMPLETE: M1–M8 landed, axiom-clean, claim-disciplined.**
