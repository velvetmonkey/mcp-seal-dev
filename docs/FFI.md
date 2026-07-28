# FFI surface (v2 core → Rust host)

The verified v2 core is exported to the Rust host as a self-contained shared
library. The seam is string-in/string-out JSON — no structs cross the boundary.
Lean owns everything decision-bearing (verified parse/validate/serialize/decide,
the Ed25519 leaf, the M6 lifecycle consume); the host owns transport, key
custody, the wall clock, and call serialisation (assumption A4 — the exports are
NOT thread-safe). Source of truth: the module docstring and exports in
[`Ffi.lean`](../Ffi.lean); host-side bindings in `rust/src/lean.rs` and
`rust/src/main.rs`.

## Axiom footprint and scope

`Ffi` is the only module assigned to the unsafe compiled-code-root baseline
`[propext, Classical.choice, Quot.sound, lcProof]`. The 24 explicitly assigned
regular kernel modules retain their separate baseline
`[propext, Classical.choice, Quot.sound]`; Seal does not claim one uniform
three-name baseline over both groups. The six exported wrappers carry exactly
`[lcProof]` outside the kernel baseline. This characterizes kernel logical
soundness of regular declarations only and says nothing about runtime,
memory-safety, or observational purity of those wrappers.

## Exports

All functions take and return Lean strings (JSON envelopes). Errors are
`{"ok": false, "error": "<msg>"}`; success shapes below.

| Export | Arguments | Returns on success |
|---|---|---|
| `seal_v2_init` | config JSON (below) | `{"ok": true}` — (re)initialises the session state; fail-closed on any parse error |
| `seal_v2_add_approval` | canonical signed-message bytes, hex signature | `{"ok": true}` — approval reconstructed via the verified `signedParse`; the signature itself is checked later, inside `decide` |
| `seal_v2_decide` | raw request bytes, clock (`now` as decimal string) | `{"ok": true, "decision": "Allow", "out": "<canonical bytes>"}` or `{"ok": true, "decision": "Block"}`; on Allow the consumed-nonce store is written back (single-use) |
| `seal_v2_challenge` | raw request, issuedAt, expiry, 64-hex nonce | `{"ok": true, "signed_bytes": "<canonical signed-message bytes>"}` — STATELESS; the only sanctioned source of the bytes the off-box signer signs |
| `seal_v2_echo` | any string | the same string (bring-up self-test) |
| `seal_v2_crypto_probe` | hex pubkey, message, hex signature | `{"ok": true, "verified": <bool>}` (proves the Ed25519 leaf resolved) |

Config envelope for `seal_v2_init`:

```json
{
  "session": "<id>",
  "publicKey": "<hex>",
  "manifestDigest": "<hex>",
  "policyVersion": "<string>",
  "maxApprovalTtl": 300,
  "tools": [ { "tool": "<name>", "version": "<v>", "actions": ["<action>", "..."] } ]
}
```

The shim (`scripts/ffi_shim.c`) additionally exports `seal_v2_ffi_initialize`
(the Lean module initializer under a stable name) and the `lean.h` static-inline
helpers Rust cannot call directly: `seal_lean_string_cstr`,
`seal_lean_io_result_is_ok`, `seal_lean_dec`, `seal_lean_mk_string`.

## Build chain

```sh
bash c/build.sh                  # vendored TweetNaCl + shim -> c/build/libsealcrypto.o
bash scripts/build_ffi_so.sh     # lake build ffi_shared, then hand-links
                                 #   .lake/build/lib/libsealv2ffi.so
                                 # and checks the exported symbols
cd rust && cargo run             # host selftest: init -> challenge -> sign ->
                                 #   add_approval -> decide (Allow once, Block replay)
```

`rust/build.rs` locates the artifacts via two environment variables:
`SEAL_FFI_LIB_DIR` (directory containing `libsealv2ffi.so`; defaults to
`../.lake/build/lib`) and `LEAN_LIB_DIR` (the toolchain's `lib/lean`; defaults
via `lean --print-prefix`). A minimal "call decide from Rust" walkthrough is the
selftest in `rust/src/main.rs`.
