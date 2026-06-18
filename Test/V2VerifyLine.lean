/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2
import Test.V2ValidationFixtures

open SealV2
open Test.V2ValidationFixtures

/-- Two modes for the M5 acceptance corpus:

    `verify <pubHex> <msg> <sigHex>` — the raw Ed25519 primitive over arbitrary bytes,
      printing `true`/`false`. Drives the crypto cases (accept / bad-sig / wrong-key /
      tampered-byte / wrong-length).

    `decide <pubHex> <sigHex> <now>` — the FULL seam + lifecycle: runs `decide` on the
      base request against the base approval re-signed with `<sigHex>` under `<pubHex>`
      at clock `<now>`, printing `Allow`/`Block`. Drives the e2e accept and the
      "valid signature but expired" reject (origin ≠ authorization). -/
def main (args : List String) : IO UInt32 := do
  match args with
  | ["verify", pubHex, msg, sigHex] =>
      let ok :=
        match hexDecode? pubHex, hexDecode? sigHex with
        | some pk, some sig => ed25519Verify pk msg.toUTF8 sig
        | _, _ => false
      IO.println (if ok then "true" else "false")
      pure 0
  | ["decide", pubHex, sigHex, nowStr] =>
      let now := (nowStr.toNat?).getD 0
      let approval := { validApproval with signature := sigHex }
      let state := { baseState with publicKey := pubHex, approvals := [approval], now := now }
      match decide validRaw state with
      | .Allow _ => IO.println "Allow"; pure 0
      | .Block   => IO.println "Block"; pure 0
  | _ =>
      IO.eprintln "usage: v2_verify_line verify <pubHex> <msg> <sigHex> | decide <pubHex> <sigHex> <now>"
      pure 2
