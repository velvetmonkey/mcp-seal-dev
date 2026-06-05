/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2
import Test.V2ValidationFixtures

open SealV2
open Test.V2ValidationFixtures

def expectSomeValidate (name raw : String) (state : ApprovalState) : IO Unit := do
  match parse raw with
  | none => throw <| IO.userError s!"{name}: expected parse success"
  | some ast =>
      match validate ast state with
      | some _ => pure ()
      | none => throw <| IO.userError s!"{name}: expected validation witness"

def expectNoneValidate (name raw : String) (state : ApprovalState) : IO Unit := do
  match parse raw with
  | none => throw <| IO.userError s!"{name}: expected parse success before validation rejection"
  | some ast =>
      match validate ast state with
      | none => pure ()
      | some _ => throw <| IO.userError s!"{name}: expected validation failure"

def main : IO UInt32 := do
  expectSomeValidate "valid witness" validRaw baseState
  expectNoneValidate "unknown tool" (requestRaw "db.query" "write" "{\"database\":\"prod\",\"table\":\"users\",\"amount\":12.34}") baseState
  expectNoneValidate "unknown action" (requestRaw "db.execute" "read" "{\"database\":\"prod\",\"table\":\"users\",\"amount\":12.34}") baseState
  expectNoneValidate "no approval" validRaw { baseState with approvals := [] }
  expectNoneValidate "target mismatch" (requestRaw "db.execute" "write" "{\"database\":\"prod\",\"table\":\"payments\",\"amount\":12.34}") baseState
  expectNoneValidate "session mismatch" validRaw { baseState with session := "session-2" }
  expectNoneValidate "consumed approval" validRaw { baseState with approvals := [signedApproval { unsignedApproval with consumed := true }] }
  expectNoneValidate "expired approval" validRaw { baseState with now := 121 }
  expectNoneValidate "bad stub signature" validRaw { baseState with approvals := [{ unsignedApproval with signature := "bad-signature" }] }
  IO.println "M2 validation corpus passed: 1 accepted, 8 rejected"
  pure 0
