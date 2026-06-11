/- SPDX-License-Identifier: Apache-2.0 -/

import SealCore

open SealCore

def assertEq [BEq α] [ToString α] (name : String) (actual expected : α) : IO Unit := do
  unless actual == expected do
    throw <| IO.userError s!"{name}: expected {expected}, got {actual}"

instance : ToString Decision where
  toString
  | .allow => "allow"
  | .block => "block"

def targetA : Hash := 1001
def targetB : Hash := 2002

def main : IO UInt32 := do
  let ttl := 1000          -- ttlMs: an approval minted at `now` expires at now+1000
  let now := 0
  let empty := State.empty
  assertEq "default deny" (step now ttl empty .defaultDeny).1 .block
  assertEq "guarded before approval" (step now ttl empty (.guarded targetA)).1 .block
  let approved := (step now ttl empty (.approval targetA)).2   -- deadline = 1000
  assertEq "approved target allowed" (step now ttl approved (.guarded targetA)).1 .allow
  assertEq "confused deputy blocked" (step now ttl approved (.guarded targetB)).1 .block
  let consumed := (step now ttl approved (.guarded targetA)).2
  assertEq "replay blocked" (step now ttl consumed (.guarded targetA)).1 .block
  -- Time-based expiry: the same approval, evaluated at different clock readings.
  assertEq "not-yet-expired allowed" (step 999 ttl approved (.guarded targetA)).1 .allow
  assertEq "expired approval blocked" (step 1000 ttl approved (.guarded targetA)).1 .block
  assertEq "long-expired approval blocked" (step 5000 ttl approved (.guarded targetA)).1 .block
  assertEq "benign allowed" (step now ttl empty .benign).1 .allow
  pure 0
