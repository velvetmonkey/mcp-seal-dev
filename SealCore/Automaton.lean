/- SPDX-License-Identifier: Apache-2.0 -/

import SealCore.Event
import Std.Data.HashMap

namespace SealCore

/-- `approved` maps a target hash to an absolute expiry deadline (monotonic
    milliseconds). A target is live while the current time is strictly before
    its deadline. The deadline is stamped by the runtime when the approval is
    ingested (`now + ttlMs`); the engine never trusts a caller-supplied time. -/
structure State where
  approved : Std.HashMap Hash Nat := ∅
  deriving Repr

def State.empty : State := {}

/-- A target is live iff it has an approval whose deadline has not yet passed
    at time `now`. -/
def live (s : State) (target : Hash) (now : Nat) : Bool :=
  match s.approved[target]? with
  | some deadline => now < deadline
  | none => false

/-- Drop every approval whose deadline is at or before `now`. Memory hygiene
    only: lazy `live` already refuses expired entries, so pruning changes no
    decision. -/
def prune (now : Nat) (approved : Std.HashMap Hash Nat) : Std.HashMap Hash Nat :=
  approved.fold (init := ∅) fun acc target deadline =>
    if now < deadline then acc.insert target deadline else acc

def step (now : Nat) (ttlMs : Nat) (s : State) (e : Event) : Decision × State :=
  match e with
  | .approval target => (.allow, { approved := s.approved.insert target (now + ttlMs) })
  | .guarded target =>
      if live s target now then
        (.allow, { approved := s.approved.erase target })
      else
        (.block, s)
  | .benign => (.allow, s)
  | .defaultDeny => (.block, s)

def run (now : Nat) (ttlMs : Nat) (s : State) (events : List Event) : State :=
  events.foldl (fun st e => (step now ttlMs st e).2) s

end SealCore
