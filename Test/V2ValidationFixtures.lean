/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2

open SealV2

namespace Test.V2ValidationFixtures

def requestRaw (tool action args : String) : String :=
  "{\"method\":\"tools/call\",\"params\":{\"name\":\"" ++ tool ++
    "\",\"action\":\"" ++ action ++
    "\",\"arguments\":" ++ args ++ "}}"

def baseArgs : AST :=
  .object [("database", .string "prod"), ("table", .string "users"), ("amount", .number {
    negative := false,
    intDigits := "12",
    fracDigits := some "34"
  })]

def toolSpec : ToolSpec :=
  { tool := "db.execute", version := "v1", actions := ["write"] }

def target : Target :=
  {
    tool := "db.execute",
    action := "write",
    toolVersion := "v1",
    manifestDigest := "manifest-001",
    arguments := baseArgs
  }

-- Literal 64-lowercase-hex nonces for fixtures and tests.
def hex64a : String := String.ofList (List.replicate 64 'a')
def hex64b : String := String.ofList (List.replicate 64 'b')

def nonceA : Nonce := { value := hex64a, canonical := by decide }
def nonceB : Nonce := { value := hex64b, canonical := by decide }

def unsignedApproval : Approval :=
  let message : SignedMessage := {
    target := target,
    session := "session-1",
    issuedAt := 0,
    expiry := 120,
    nonce := nonceA
  }
  {
    target := target,
    session := "session-1",
    issuedAt := 0,
    expiresAt := 120,
    consumed := false,
    signedMessageRaw := signedMessageRawFor message,
    signature := "",
    nonce := nonceA
  }

def signedApproval (approval : Approval) : Approval :=
  { approval with signature := stubSignatureFor "pubkey-1" (signedMessage approval) }

/-- Re-derive both the signed-message bytes and the stub signature from an approval's
    own fields, so callers can vary issuedAt / expiresAt / nonce and stay self-consistent. -/
def signApprovalFully (approval : Approval) : Approval :=
  { approval with
    signedMessageRaw := signedMessageRawFor (signedMessage approval),
    signature := stubSignatureFor "pubkey-1" (signedMessage approval) }

def validApproval : Approval :=
  signedApproval unsignedApproval

def baseState : ApprovalState :=
  {
    session := "session-1",
    now := 10,
    publicKey := "pubkey-1",
    manifestDigest := "manifest-001",
    tools := [toolSpec],
    approvals := [validApproval],
    policyVersion := "policy-1"
  }

def validRaw : String :=
  requestRaw "db.execute" "write" "{\"database\":\"prod\",\"table\":\"users\",\"amount\":12.34}"

end Test.V2ValidationFixtures
