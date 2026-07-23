#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

"""Principal non-influence signature fixture (K2).

Regenerates the real Ed25519 witness signatures pinned in
`SealV2/PrincipalNonInfluence.lean` (`wSigAHex`, `wSigBHex`) and
`Test/PrincipalNonInfluence.lean` (`sigAliceFxHex`), then runs the SHOW
control end to end.

Message bytes come from the compiled kernel itself
(`lake exe principal_non_influence_show messages`), so the fixture can never
sign the wrong framing: if the pinned Lean-side message hex and the exe
disagree, the build's `#guard_msgs` pin already went red.

Keys are the documented test seeds (NOT real keys):
  alice seed = 0x00 01 02 .. 1f   (same seed as testPublicKeyHex / m5)
  bob   seed = 0x01 02 03 .. 20
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

ROOT = Path(__file__).resolve().parents[2]

ALICE_SEED = bytes(range(32))
BOB_SEED = bytes(range(1, 33))
EXPECTED_ALICE_PUB = "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8"
EXPECTED_BOB_PUB = "79b5562e8fe654f94078b112e8a98ba7901f853ae695bed7e0e3910bad049664"


def pub_hex(sk: Ed25519PrivateKey) -> str:
    return sk.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    ).hex()


def main() -> int:
    sk_alice = Ed25519PrivateKey.from_private_bytes(ALICE_SEED)
    sk_bob = Ed25519PrivateKey.from_private_bytes(BOB_SEED)
    assert pub_hex(sk_alice) == EXPECTED_ALICE_PUB, "alice pubkey drift"
    assert pub_hex(sk_bob) == EXPECTED_BOB_PUB, "bob pubkey drift"

    out = subprocess.run(
        ["lake", "exe", "principal_non_influence_show", "messages"],
        cwd=ROOT, check=True, text=True, capture_output=True,
    ).stdout
    msgs = dict(line.split(" ", 1) for line in out.strip().splitlines())

    sig_a = sk_alice.sign(bytes.fromhex(msgs["alice"])).hex()
    sig_b = sk_bob.sign(bytes.fromhex(msgs["bob"])).hex()
    sig_fx = sk_alice.sign(bytes.fromhex(msgs["alice-effectful"])).hex()

    print("pin these:")
    print(f"  SealV2/PrincipalNonInfluence.lean wSigAHex      = {sig_a}")
    print(f"  SealV2/PrincipalNonInfluence.lean wSigBHex      = {sig_b}")
    print(f"  Test/PrincipalNonInfluence.lean   sigAliceFxHex = {sig_fx}")

    show = subprocess.run(
        ["lake", "exe", "principal_non_influence_show"],
        cwd=ROOT, text=True, capture_output=True,
    )
    sys.stdout.write(show.stdout)
    if show.returncode != 0:
        print("SHOW control RED (stale pins? paste the values above and rebuild)")
        return 1
    print("SHOW control GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
