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
  let ttl := 2
  let empty := State.empty
  assertEq "default deny" (step ttl empty .defaultDeny).1 .block
  assertEq "guarded before approval" (step ttl empty (.guarded targetA)).1 .block
  let approved := (step ttl empty (.approval targetA)).2
  assertEq "approved target allowed" (step ttl approved (.guarded targetA)).1 .allow
  assertEq "confused deputy blocked" (step ttl approved (.guarded targetB)).1 .block
  let consumed := (step ttl approved (.guarded targetA)).2
  assertEq "replay blocked" (step ttl consumed (.guarded targetA)).1 .block
  let expired := (step ttl (step ttl approved .tick).2 .tick).2
  assertEq "expired approval blocked" (step ttl expired (.guarded targetA)).1 .block
  assertEq "benign allowed" (step ttl empty .benign).1 .allow
  pure 0
