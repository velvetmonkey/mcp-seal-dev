/- SPDX-License-Identifier: Apache-2.0 -/

import SealCore.Event
import SealCore.Sha256

namespace Seal

open SealCore

private def modulus : Nat := 18446744073709551616

/-- Legacy 64-bit FNV-style audit hash. This is deliberately kept for `certHash`
    and record/audit demo paths; it is not the target commitment. -/
def auditHashString (s : String) : Hash :=
  UInt64.ofNat <| s.foldl
    (fun acc ch => ((acc * 1099511628211) + ch.val.toNat) % modulus)
    14695981039346656037

/-- Injective canonical encoding of a part-list (netstring-style framing).
Each part `s` becomes `<charCount>:<s>`, and the frames are concatenated. A
frame is self-delimiting — read the decimal length up to `:`, then take exactly
that many characters as the datum — so distinct part-lists never share an
encoding: `encodeParts` is injective over `List String`.

This replaces the previous `"|".intercalate parts`, which was NOT injective:
any part containing the separator collided (e.g. `["a", "b"]` and `["a|b"]` both
encoded to `"a|b"`), letting an attacker-supplied part-list alias a distinct
authorized one before the hash even ran. The formal `Function.Injective
encodeParts` proof is discharged in seal-host `Host/CapabilityAdequacy` as the
structural half of the unconditional (all-pg, no `pg∈U`) capability theorem. -/
def encodeParts (parts : List String) : String :=
  String.join (parts.map fun s => toString s.length ++ ":" ++ s)

def auditHashParts (parts : List String) : Hash :=
  auditHashString (encodeParts parts)

def stableHashString (s : String) : SealCore.TargetHash :=
  Sha256.sha256Digest s.toUTF8

def stableHashParts (parts : List String) : SealCore.TargetHash :=
  stableHashString (encodeParts parts)

end Seal
