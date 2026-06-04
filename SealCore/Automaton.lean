/- SPDX-License-Identifier: Apache-2.0 -/

import SealCore.Event
import Std.Data.HashMap

namespace SealCore

structure State where
  approved : Std.HashMap Hash Nat := ∅
  deriving Repr

def State.empty : State := {}

def live (s : State) (target : Hash) : Bool :=
  match s.approved[target]? with
  | some ttl => ttl > 0
  | none => false

def decayApproved (approved : Std.HashMap Hash Nat) : Std.HashMap Hash Nat :=
  approved.fold (init := ∅) fun acc target ttl =>
    match ttl with
    | 0 => acc
    | 1 => acc
    | Nat.succ (Nat.succ rest) => acc.insert target (Nat.succ rest)

def step (approvalTtl : Nat) (s : State) (e : Event) : Decision × State :=
  match e with
  | .approval target => (.allow, { approved := s.approved.insert target approvalTtl })
  | .guarded target =>
      if live s target then
        (.allow, { approved := s.approved.erase target })
      else
        (.block, s)
  | .benign => (.allow, s)
  | .defaultDeny => (.block, s)
  | .tick => (.allow, { approved := decayApproved s.approved })

def run (approvalTtl : Nat) (s : State) (events : List Event) : State :=
  events.foldl (fun st e => (step approvalTtl st e).2) s

end SealCore
