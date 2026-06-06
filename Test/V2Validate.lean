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

def approvalSignedOverRaw (raw : RawBytes) : Approval :=
  { unsignedApproval with
    signedMessageRaw := raw,
    signature := s!"stub-ed25519:pubkey-1:{raw}"
  }

def expectSignedPathRejects (name raw : String) : IO Unit := do
  match signedParse raw with
  | none =>
    expectNoneValidate name validRaw { baseState with approvals := [approvalSignedOverRaw raw] }
    match decide validRaw { baseState with approvals := [approvalSignedOverRaw raw] } with
    | .Block => pure ()
    | .Allow out => throw <| IO.userError s!"{name}: expected mediated decision block, got {out}"
  | some _ =>
    throw <| IO.userError s!"{name}: expected signedParse rejection"

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
  expectSignedPathRejects "signed trailing whitespace" (validApproval.signedMessageRaw ++ " ")
  expectSignedPathRejects "signed leading whitespace" (" " ++ validApproval.signedMessageRaw)
  expectSignedPathRejects "signed interior whitespace"
    "{\"target\": {\"tool\":\"db.execute\",\"action\":\"write\",\"toolVersion\":\"v1\",\"manifestDigest\":\"manifest-001\",\"arguments\":{\"database\":\"prod\",\"table\":\"users\",\"amount\":12.34}},\"session\":\"session-1\",\"expiry\":120}"
  IO.println "M2 validation corpus passed: 1 accepted, 11 rejected"
  pure 0
