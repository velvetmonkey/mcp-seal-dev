#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

"""M5 end-to-end Ed25519 acceptance fixture.

Real signatures (Python `cryptography`, pure Ed25519 / RFC 8032) over the
AUTHORITATIVE canonical signed-message bytes emitted by `v2_signed_bytes`, fed
through the seal verification seam via `v2_verify_line`.

Demonstrates, with real crypto (no stub):
  - a valid signature over canonical bytes verifies and the request is Allowed;
  - bad signature / wrong key / tampered byte / wrong-length all reject;
  - a VALID signature on an EXPIRED approval is still Blocked — origin authenticated
    is not authorization. Origin is asserted by the channel (Ed25519), NOT proven in
    Lean: see v2/milestones/05-sign/NOTES.md (TCB assumption A3).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

ROOT = Path(__file__).resolve().parents[2]

# Fixed, documented test seed (NOT a real key). Its public key must match
# `testPublicKeyHex` in Test/V2ValidationFixtures.lean.
SEED = bytes(range(32))
EXPECTED_PUB_HEX = "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8"


def raw_pub_hex(sk: Ed25519PrivateKey) -> str:
    return sk.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    ).hex()


def signed_bytes(*args: str) -> str:
    out = subprocess.run(
        ["lake", "exe", "v2_signed_bytes", *args],
        cwd=ROOT, check=True, text=True, capture_output=True,
    ).stdout
    return out[:-1] if out.endswith("\n") else out


def verify(pub_hex: str, msg: str, sig_hex: str) -> str:
    return subprocess.run(
        ["lake", "exe", "v2_verify_line", "verify", pub_hex, msg, sig_hex],
        cwd=ROOT, check=True, text=True, capture_output=True,
    ).stdout.strip()


def decide(pub_hex: str, sig_hex: str, now: int) -> str:
    return subprocess.run(
        ["lake", "exe", "v2_verify_line", "decide", pub_hex, sig_hex, str(now)],
        cwd=ROOT, check=True, text=True, capture_output=True,
    ).stdout.strip()


def main() -> int:
    sk = Ed25519PrivateKey.from_private_bytes(SEED)
    pub_hex = raw_pub_hex(sk)
    if pub_hex != EXPECTED_PUB_HEX:
        raise AssertionError(
            f"test pubkey drift: fixture has {EXPECTED_PUB_HEX}, derived {pub_hex}"
        )

    # A second, unrelated keypair for the wrong-key case.
    wrong_sk = Ed25519PrivateKey.from_private_bytes(bytes([0xAA]) * 32)
    wrong_pub_hex = raw_pub_hex(wrong_sk)

    m_a = signed_bytes()                     # authoritative canonical bytes
    sig_a = sk.sign(m_a.encode("utf-8")).hex()

    # --- crypto layer (raw ed25519Verify over canonical bytes) ---
    checks: list[tuple[str, str, str]] = []  # (name, got, want)

    checks.append(("valid signature", verify(pub_hex, m_a, sig_a), "true"))

    bad_sig = bytearray.fromhex(sig_a)
    bad_sig[-1] ^= 0x01
    checks.append(("bad signature", verify(pub_hex, m_a, bad_sig.hex()), "false"))

    checks.append(("wrong key", verify(wrong_pub_hex, m_a, sig_a), "false"))

    tampered = ("X" + m_a[1:]) if m_a[0] != "X" else ("Y" + m_a[1:])
    checks.append(("tampered message", verify(pub_hex, tampered, sig_a), "false"))

    checks.append(("wrong-length signature", verify(pub_hex, m_a, sig_a[:-2]), "false"))

    # --- full seam + lifecycle (decide) ---
    checks.append(("e2e accept (valid sig, live)", decide(pub_hex, sig_a, 10), "Allow"))
    checks.append(("expired (valid sig, now>expiry)", decide(pub_hex, sig_a, 200), "Block"))
    checks.append(("wrong key e2e", decide(wrong_pub_hex, sig_a, 10), "Block"))

    if "--dump" in sys.argv[1:]:
        print(f"{'RESULT':<6} {'EXPECT':<6} CASE")
        for name, got, want in checks:
            print(f"{got:<6} {want:<6} {name}")
        return 0

    accepts = 0
    for name, got, want in checks:
        if got != want:
            raise AssertionError(f"{name}: expected {want!r}, got {got!r}")
        if want in ("true", "Allow"):
            accepts += 1

    rejects = len(checks) - accepts
    print(f"M5 Ed25519 fixture passed: {accepts} accepted, {rejects} rejected "
          f"(real signatures over canonical bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
