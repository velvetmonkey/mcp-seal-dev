# Trusted Computing Base

Seal keeps the proof boundary small, but deployment still has a TCB.

## Trusted for the proof story

- The Lean kernel and the stated axiom footprint.
- The theorem statements and axiom gates in the Lean repositories.
- The target-commitment hash assumption A-CR — an idealised perfect-injectivity premise, strictly stronger than SHA-256 collision resistance and not satisfied by real SHA-256; deployment trusts that no SHA-256 collision is findable for the relevant inputs (see [ASSUMPTIONS.md](ASSUMPTIONS.md)).

## Trusted for deployment

- The Rust, wasm, JavaScript, Node, browser, and emscripten toolchains that build and run artifacts.
- The operating system, filesystem permissions, process isolation, clocks, and networking.
- Approval providers, signing keys, control files, and operators.
- MCP hosts and downstream tools honoring the mediated path.
- CI and release processes that pin and distribute artifacts.

## Trusted crypto leaf: Ed25519 verification (TweetNaCl)

Origin authentication rests on a **vendored Ed25519 verifier, not a Lean
theorem** (assumption A3). `SealV2/Crypto.lean`'s `ed25519Verify` is `@[extern]`
to `c/seal_ed25519.c:30`, which width-checks (pk 32 B, sig 64 B) and marshals to
TweetNaCl `crypto_sign_open` (`c/tweetnacl.c:779`). No proof in the Lean core
depends on this code being correct.

**Which EdDSA variant it is** — RFC 8032 and "Taming the many EdDSAs"
(Chalkias–Garillot–Nikolaenko, ePrint 2020/1244) vocabulary:

- **Cofactorless verification.** It checks the single-equation form
  `[S]B = R + [k]A'` — `c/tweetnacl.c:794-801` compute `[S]B − [k]A` and
  byte-compare against `R`. It never uses the cofactored `[8][S]B = [8]R +
  [8][k]A'`; there is no cofactor (×8) multiplication anywhere.
- **No S-range (canonical-S) check — a RFC 8032 §5.1.7 non-conformance, not a
  flavour choice.** The scalar `S` is passed straight to `scalarbase` with no
  `0 ≤ S < L` test and no reduction (`c/tweetnacl.c:796`). RFC 8032 §5.1.7
  *requires* decoding S "in the range 0 <= s < L" and states: "If any of the
  decodings fail (including S being out of range), the signature is invalid."
  §8.4 states that this very check is what makes Ed25519 non-malleable. Omitting
  it makes the leaf **malleable**: any `S' = S + m·L` that still encodes in 32
  bytes verifies.
- **Point / encoding handling.** The public key `A` is decoded with an on-curve
  check (`unpackneg`, `c/tweetnacl.c:743,788`); `R` is enforced canonical by
  full 32-byte encoding equality (`crypto_verify_32`, `:801`). There is **no
  small-order-`A` rejection**. Non-canonical R/A encodings and off-curve points
  are rejected.

**Measured, not assumed.** Against Wycheproof v1 `ed25519_test.json` @
`b61843a9` (150 tests): **5 of 62 must-reject signatures accepted** — 4
`SignatureMalleability` (tcId 63-66) + 1 S-above-bound (tcId 85); the other 57
invalid rejected, all 88 valid accepted. Reproduced here directly against the
leaf and end-to-end through the deployed host.

**What malleability does and does not buy.** It lets an attacker turn one valid
signature into many that also verify for the same message and key. It does
**not** buy a double-spend: seal's replay identity is the **nonce**, not the
signature bytes — `ConsumedNonce = {ns, nonce, expiresAt}`
(`SealV2/Validation.lean:88-92`); the replay namespace excludes the signature
(`:260-270`); and `replay_denied` (`SealV2/LifecycleTheorems.lean:84`) proves a
re-presented consumed nonce Blocks. Verified live: a valid approval Allows and
consumes the nonce, then the malleated variant (same nonce) **Blocks**; the
malleated variant alone Allows a fresh token, so the Block is a replay block,
not a rejection. No record in this repo keys on signature bytes.

Adding an `S < L` check to `c/seal_ed25519.c` would restore RFC 8032
conformance; that is a separate decision (see `CLAIMS.md` residual **A3-S**).

## Checked, not trusted blindly

- Artifact SHA-256 pins.
- Conformance bridge outputs over the corpus.
- Receipt re-derivation in the browser and CLI.
- Record-chain heads and tamper-evidence checks.
