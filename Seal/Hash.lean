/- SPDX-License-Identifier: Apache-2.0 -/

import SealCore.Event

namespace Seal

open SealCore

private def modulus : Nat := 18446744073709551616

def stableHashString (s : String) : Hash :=
  UInt64.ofNat <| s.foldl
    (fun acc ch => ((acc * 1099511628211) + ch.val.toNat) % modulus)
    14695981039346656037

def stableHashParts (parts : List String) : Hash :=
  stableHashString ("|".intercalate parts)

end Seal
