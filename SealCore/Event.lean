/- SPDX-License-Identifier: Apache-2.0 -/

namespace SealCore

abbrev Hash := UInt64

inductive Event where
  | approval (target : Hash)
  | guarded (target : Hash)
  | benign
  | defaultDeny
  | tick
  deriving Repr, BEq, DecidableEq

inductive Decision where
  | allow
  | block
  deriving Repr, BEq, DecidableEq

def Decision.isAllow : Decision → Bool
  | .allow => true
  | .block => false

end SealCore
