#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

"""Field-warrant SHOW fixture: Ed25519 signatures over Stage B2
(`seal.effect/v2`, reconciled shape) effect-envelope message bytes
(`SealV2.Effect.effectMessage`), for `Test/FieldWarrant.lean`.

Two signature classes:

  * `sig_base` — the GREEN control: a fully gate-passing envelope.
  * gate-tamper variants — an attacker WITH the registered key signs an
    envelope that fails exactly ONE gate. These prove the gates block even
    VALID signatures (the theorems' fail-closed direction, run for real).

The forgery class (tampered field, signature NOT re-minted) needs no output
from this script: `Test/FieldWarrant.lean` reuses `sig_base` against tampered
envelopes and expects verification failure.

The byte encoder below is a Python twin of `effectMessage`. It is
SELF-CHECKED against the `#guard_msgs` golden-vector hexes pinned in
`SealV2/EffectEnvelope.lean` before any signature is minted; drift fails
loudly here rather than minting signatures over wrong bytes.

Stage B2 shape notes (vs the field-warrant campaign fixture this ports):

  * expiresAt and policyVersion are RESCUED into the tuple and MANDATORY —
    the empty/zero seat form is now a gate red, not a green.
  * session is MANDATORY (empty was a fail-open bypass).
  * The F3 effect claim is `Option`-encoded with a signed presence byte
    (0x00 absent / 0x01 present) — absence is declared, not spelled as
    three empty strings. `("", "", "", absent-meta)` is now a CLAIM and gets
    checked. A present claim also carries the complete validated metadata.
  * revocationSubject is STRIPPED (SEAT, wrong plane).

Keys: the fixed, documented test seed 0x000102..1f (NOT a real key), the
same keypair as `Test/V2ValidationFixtures.testPublicKeyHex`.

Run:  python3 test/v2/field_warrant_sign_fixture.py
Emits the Lean definitions to paste into `Test/FieldWarrant.lean`.
Run with --golden to print the two golden-vector hexes for the
`#guard_msgs` pins instead.
"""

from __future__ import annotations

import sys

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

SEED = bytes(range(32))
EXPECTED_PUB_HEX = "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8"

EFFECT_TAG = b"seal.effect/v2\x00"

# The golden-vector pins from SealV2/EffectEnvelope.lean (#guard_msgs over
# `bytesToHex (effectMessage ...)`). The encoder twin must reproduce both:
# one with the effect claim PRESENT (leading 0x01 block) and one with it
# DECLARED ABSENT (the signed 0x00 presence byte).
GOLDEN_HEX_EFFECT_PRESENT = (
    "7365616c2e6566666563742f763200"
    "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"
    "0000000000000005616c696365"
    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    "00000000000004d2"
    "000000000000162e"
    "00000000000000077b226d223a317d"
    "00000000000000036d6370"
    "000000000000000a323032352d30362d3138"
    "0000000000000006736573732d31"
    "0000000000000005706f6c2d31"
    "01"
    "000000000000000a64622e65786563757465"
    "000000000000000463616c6c"
    "00000000000000077b2271223a317d"
    "00"
)
GOLDEN_HEX_EFFECT_ABSENT = (
    "7365616c2e6566666563742f763200"
    "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"
    "0000000000000005616c696365"
    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    "00000000000004d2"
    "000000000000162e"
    "00000000000000077b226d223a317d"
    "00000000000000036d6370"
    "000000000000000a323032352d30362d3138"
    "0000000000000006736573732d31"
    "0000000000000005706f6c2d31"
    "00"
)


def u64be(n: int) -> bytes:
    return n.to_bytes(8, "big")


def frame(s: str) -> bytes:
    b = s.encode("utf-8")
    return u64be(len(b)) + b


def opt_meta(meta: str | None) -> bytes:
    """0x00 = metadata absent; 0x01 ++ frame(canonical object) = present."""
    if meta is None:
        return b"\x00"
    return b"\x01" + frame(meta)


def opt_effect(effect: tuple[str, str, str, str | None] | None) -> bytes:
    """Wire form of the Option-encoded F3 claim: 0x00 = declared absent;
    0x01 ++ frame(resource) ++ frame(action) ++ frame(args)
    ++ opt_meta(metadata) = present."""
    if effect is None:
        return b"\x00"
    resource, action, args, meta = effect
    return (
        b"\x01" + frame(resource) + frame(action) + frame(args)
        + opt_meta(meta)
    )


def effect_message(authority: bytes, e: dict) -> bytes:
    assert len(authority) == 32 and len(e["nonce"]) == 32
    return (
        EFFECT_TAG + authority
        + frame(e["keyId"]) + e["nonce"]
        + u64be(e["issuedAt"]) + u64be(e["expiresAt"])
        + frame(e["line"])
        + frame(e["adapterType"]) + frame(e["adapterVersion"])
        + frame(e["session"])
        + frame(e["policyVersion"])
        + opt_effect(e["effect"])
    )


GOLDEN_AUTHORITY = bytes(0xA0 + i for i in range(32))

GOLDEN_ENVELOPE = {
    "keyId": "alice",
    "nonce": bytes(range(32)),
    "issuedAt": 1234,
    "expiresAt": 5678,
    "line": '{"m":1}',
    "adapterType": "mcp",
    "adapterVersion": "2025-06-18",
    "session": "sess-1",
    "policyVersion": "pol-1",
    "effect": ("db.execute", "call", '{"q":1}', None),
}

GOLDEN_ENVELOPE_NO_EFFECT = dict(GOLDEN_ENVELOPE, effect=None)

# The warrant base: passes EVERY gate against Test/V2ValidationFixtures
# baseState (session-1, now=10, policy-1, maxApprovalTtl=300) + MCP mediator
# ("mcp", "2025-06-18") + registry [alice -> test pubkey]. All mandatory
# bindings populated; the F3 claim rides PRESENT so the green exercises the
# strong form of every gate.
VALID_LINE = (
    '{"method":"tools/call","params":{"name":"db.execute","action":"write",'
    '"arguments":{"database":"prod","table":"users","amount":12.34}}}'
)
VALID_ARGS = '{"database":"prod","table":"users","amount":12.34}'

BASE = {
    "keyId": "alice",
    "nonce": bytes(range(32)),
    "issuedAt": 5,
    "expiresAt": 100,
    "line": VALID_LINE,
    "adapterType": "mcp",
    "adapterVersion": "2025-06-18",
    "session": "session-1",
    "policyVersion": "policy-1",
    "effect": ("db.execute", "write", VALID_ARGS, None),
}

SWAPPED_LINE = (
    '{"method":"tools/call","params":{"name":"fs.read","action":"read",'
    '"arguments":{}}}'
)

# Gate-tamper variants:
# (lean name suffix, field, tampered value, gate expected to trip)
GATE_VARIANTS = [
    ("AdapterType", "adapterType", "cli", "adapterGate"),
    ("AdapterVersion", "adapterVersion", "9999-01-01", "adapterGate"),
    ("EmptySession", "session", "", "sessionGate (mandatory — bypass killed)"),
    ("Session", "session", "session-2", "sessionGate"),
    ("EmptyPolicyVersion", "policyVersion", "",
     "policyVersionGate (mandatory — bypass killed)"),
    ("PolicyVersion", "policyVersion", "policy-2", "policyVersionGate"),
    ("ZeroExpiry", "expiresAt", 0, "expiryGate (mandatory — bypass killed)"),
    ("Expired", "expiresAt", 1, "expiryGate"),
    ("FutureIssued", "issuedAt", 11, "issuedAtGate"),
    ("EmptyStringClaim", "effect", ("", "", "", None),
     "effectGate (the retired all-empty sentinel is now a checked claim)"),
    ("EffectResource", "effect", ("fs.read", "write", VALID_ARGS, None), "effectGate"),
    ("EffectAction", "effect", ("db.execute", "delete", VALID_ARGS, None), "effectGate"),
    ("EffectArgs", "effect",
     ("db.execute", "write",
      '{"database":"prod","table":"users","amount":99}', None), "effectGate"),
    ("Line", "line", SWAPPED_LINE, "effectGate"),
    ("NoEffectClaim", "effect", None,
     "none — F3 declared absent is a legitimate green (declared optionality)"),
    # stale: issuedAt stays 5; the Lean test judges it at state.now = 400
    # (400 - 5 > 300); signature-wise identical to base, no variant needed.
]


def main() -> int:
    sk = Ed25519PrivateKey.from_private_bytes(SEED)
    pub_hex = sk.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    ).hex()
    if pub_hex != EXPECTED_PUB_HEX:
        raise AssertionError(f"test pubkey drift: {pub_hex}")

    golden_present = effect_message(GOLDEN_AUTHORITY, GOLDEN_ENVELOPE).hex()
    golden_absent = effect_message(GOLDEN_AUTHORITY, GOLDEN_ENVELOPE_NO_EFFECT).hex()

    if "--golden" in sys.argv:
        print(f"effect-present: {golden_present}")
        print(f"effect-absent:  {golden_absent}")
        return 0

    if GOLDEN_HEX_EFFECT_PRESENT is not None:
        if golden_present != GOLDEN_HEX_EFFECT_PRESENT:
            raise AssertionError(
                "encoder twin drifted from the Lean golden vector (present):\n"
                f"  lean:   {GOLDEN_HEX_EFFECT_PRESENT}\n  python: {golden_present}"
            )
        if golden_absent != GOLDEN_HEX_EFFECT_ABSENT:
            raise AssertionError(
                "encoder twin drifted from the Lean golden vector (absent):\n"
                f"  lean:   {GOLDEN_HEX_EFFECT_ABSENT}\n  python: {golden_absent}"
            )

    print("-- generated by test/v2/field_warrant_sign_fixture.py (encoder twin")
    print("-- self-checked against the EffectEnvelope.lean golden-vector pins)")
    sig = sk.sign(effect_message(GOLDEN_AUTHORITY, BASE)).hex()
    print(f'def sigBase : String :=\n  "{sig}"')
    for name, field, value, gate in GATE_VARIANTS:
        e = dict(BASE)
        e[field] = value
        sig = sk.sign(effect_message(GOLDEN_AUTHORITY, e)).hex()
        print(f'/-- {field} := {value!r} — {gate}. -/')
        print(f'def sig{name} : String :=\n  "{sig}"')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
