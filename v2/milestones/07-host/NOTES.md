# M7 Rust host glue — milestone notes

Status: complete; merged to `main`. C FFI export of the verified v2 core + a Rust host that
drives it end-to-end (raw bytes → Decision), with the store and approver-key custody host-driven.
No new trust into the proof core; the CORE axiom footprint is unchanged.

## Architecture (mirrors the proven seal-host FFI pattern)

- **`Ffi.lean`** — the C ABI surface, string-in/string-out JSON (no structs cross the boundary).
  An `initialize stateRef : IO.Ref (Option ApprovalState)` holds the session. Exports:
  - `seal_v2_init(configJson)` — build the session `ApprovalState` (publicKey, manifestDigest,
    tools, policy, ttl; `approvals := []`, `consumedNonces := []`).
  - `seal_v2_add_approval(signedMessageRaw, sigHex)` — reconstruct an `Approval` from its canonical
    signed bytes via the VERIFIED `signedParse` + `signedMessageFromAst?` (no hand-rolled AST parse).
  - `seal_v2_decide(rawRequest, now)` — verified `parse → validateAndConsumeWithStore listReplayStore
    → serialize`; on Allow the consumed store is written back (single-use). The raw request goes
    through the verified M1 parser; the JSON seam is host CONTROL only, never the security parser.
- **`scripts/ffi_shim.c`** — re-exports the module initializer (`initialize_mcp_x2dseal_Ffi`) and the
  lean.h static-inline helpers Rust can't call directly.
- **`scripts/build_ffi_so.sh`** — hand-links `libsealv2ffi.so` from the `.c.o.export` objects + the
  vendored ed25519 leaf (`c/build/libsealcrypto.o`) + the shim, against the DYNAMIC `libleanshared`
  (the static runtime's TLS relocations cannot enter a `-shared` object). `ffi_shared` is a normal
  exe target whose only job is to force C codegen of `Ffi`.
- **`rust/`** — `src/lean.rs` (runtime init + string marshalling + the A4 `Mutex`), `src/main.rs`
  (`selftest` = the acceptance corpus; `serve <cfg>` = stdio relay), `build.rs`, `Cargo.toml`.

## Assumptions (named honestly)

- **A5 — DISCHARGED for the live process.** The deployed consumed-nonce store IS the verified
  `listReplayStore` (`List ConsumedNonce` inside `ApprovalState`), mutated only via
  `validateAndConsumeWithStore listReplayStore`. There is NO separate host store to refine, so the M6
  invariants (`replay_denied`, `consume_records_nonce`, …) apply to the running store directly.
- **A4 — load-bearing, and it CARRIES M6.** The `LeanHost` `Mutex` serialises every export call, so
  `read ref → validateAndConsume → write ref` is atomic — that is what makes M6's single-use hold in
  deployment. Without the lock it is a TOCTOU (replay breaks) and concurrent `IO.Ref` access is UB.
  **Test-covered**: the acceptance includes a 16-thread concurrency probe — concurrent decides against
  one single-use token yield EXACTLY ONE Allow.
- **A6 — durability residual (NEW).** `stateRef` is in-memory; on restart it is `consumedNonces := []`,
  so nonces blocked before a restart re-Allow once. A5 is discharged for the LIVE store only.
  Persistence, if added, MUST restore consumed state THROUGH `seal_v2_decide` (the consume path),
  never as a second authoritative store (that would re-open A5). Out of scope for this milestone.
- **A3 — grows (documented).** The Rust transport, the C ABI, the JSON marshalling and the approver-key
  custody are all trusted glue. A marshalling bug bypasses no Lean proof (Lean still decides); a routing
  bug would. The pure-Lean stdio sidecar stays the cleaner assurance story; the FFI host trades TCB for
  deployability — exactly as seal-host's TCB.md records.

Claim discipline: **Allow/forward origin-soundness within the modeled route; A1–A4 and A6 (durability) stated**. Never "eliminated";
A2 stays a per-server obligation, minimised by construction. Origin authenticated (Ed25519) ≠ intent.

## Acceptance (end-to-end through the C ABI)

`rust/src/main.rs selftest` drives the BUILT host with the real M5 test vector: init(testPublicKeyHex)
→ add_approval(real-signed) → decide. Results: fresh token **Allow**; replay **Block**; expired
(now>expiry, valid sig) **Block**; tampered signature **Block**; malformed + target-mismatch requests
**Block**; A4 probe: 16 concurrent decides → **exactly 1 Allow**. The Allow passing IS the byte-exact
seam assertion (the real Ed25519 verified over the exact canonical bytes round-tripped through JSON).
Reproduce with `bash v2/milestones/07-host/run.sh`.
