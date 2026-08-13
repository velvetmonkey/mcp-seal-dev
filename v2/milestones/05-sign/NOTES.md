# M5 Ed25519 origin seam — milestone notes

Status: complete; merged to `main`. Real Ed25519 verification replaces the M2 stub.
Zero `sorry`/`admit`/`native_decide`; axiom footprint unchanged.

## What changed

The M2 signature **stub** (a string-equality check) is replaced by **real Ed25519**
verification over EXACTLY the canonical `(target, session, issuedAt, expiry, nonce)`
bytes produced by the M3 serialiser (`signedMessageRawFor`), the same bytes pinned
canonical by `signed_parse_canonical`.

- `SealV2/Crypto.lean` — `@[extern "lean_seal_ed25519_verify"] opaque ed25519Verify
  (publicKey message signature : ByteArray) : Bool`, plus pure-Lean `hexDecode?`.
- `SealV2/Validation.lean` — `verifySignature` now decodes the hex public key and
  signature and calls `ed25519Verify` over `approval.signedMessageRaw.toUTF8`,
  fail-closed if either hex is malformed. The `signedParse` + structural-inversion
  checks (which bind the bytes to the canonical message) are unchanged.
- `c/tweetnacl.{c,h}` (vendored) + `c/seal_ed25519.c` (FFI shim) + `c/build.sh`.

## Crypto realization (TCB / A3)

- Vendored: **TweetNaCl**, version **20140427** (https://tweetnacl.cr.yp.to/).
  - `tweetnacl.c` SHA-256 `02e65bc3013ff2168983365e55906bc783c4c7e0a60d8100f17bb303a17175c4`
  - `tweetnacl.h` SHA-256 `43f29ad721d9927b747b0100ab4160c119e7bb180c7c98a66e4bf79d31244287`
- Pure Ed25519 / RFC 8032 (no prehash, no context), SHA-512 from the same file.
- TweetNaCl ships only attached `crypto_sign_open`; the shim reconstructs
  `sm = sig‖msg` and treats a clean open as a valid detached verify.
- `randombytes` is referenced only by key/box generation (never by verify); the shim
  provides an aborting stub so any misuse fails loudly.

**A3 (explicit TCB assumption): "the vendored Ed25519 verify is correct."** The proof
core does NOT depend on this. `verifySignature` is consumed only as a runtime `Bool`
hypothesis (validate's `hSig`), and `opaque` adds no axiom — so the six named theorems
keep footprint `[propext, Classical.choice, Quot.sound]` (see `axioms.txt`). The kernel
cannot reduce `ed25519Verify`, so no proof can "compute" a crypto result.

## Claim discipline

Now allowed: **"origin authenticated via Ed25519 over the canonical
`(target, session, issuedAt, expiry, nonce)` bytes."** But origin is **NOT proven in Lean** — it rests
on the channel (the signature) and on A3 (trusted C primitive). The PROOF guarantees
ordering/canonicality and seal-internal mediation; the CHANNEL guarantees origin.

Never "eliminated". `non_bypass` remains seal-internal Allow/forward origin-soundness; A2
(target-server parse equivalence) stays a per-server obligation, minimised by
construction, not eliminated. Authenticating origin is not authorizing intent — the
M5 corpus shows a VALID signature on an EXPIRED approval is still Blocked.

## Test vector (reproducible)

Fixed test seed `0x000102…1f` (NOT a real key), via Python `cryptography` (pure
Ed25519). Public key `03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8`
in `Test/V2ValidationFixtures.lean`. Signatures are over the authoritative canonical
bytes from `v2_signed_bytes` (so the signer never reimplements serialisation).

## Acceptance (end-to-end, real signatures)

`test/v2/m5_sign_fixture.py` drives `v2_verify_line` (raw `ed25519Verify`) and the full
`decide` seam: **2 accepted, 6 rejected** — valid signature; bad signature; wrong key;
tampered message; wrong-length signature; e2e accept (valid sig, live); expired (valid
sig, `now>expiry` → Block); wrong key e2e. `fixture-run.txt` is the pass record,
`sign-corpus.txt` enumerates each case. Reproduce all with
`bash v2/milestones/05-sign/run.sh`.

## Lean source pointers

`SealV2/Crypto.lean`, `SealV2/Validation.lean` (`verifySignature`),
`Test/V2ValidationFixtures.lean` (test vector), `c/seal_ed25519.c` + `c/tweetnacl.*`.
