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

def unsignedApproval : Approval :=
  {
    target := target,
    session := "session-1",
    expiresAt := 120,
    consumed := false,
    signature := ""
  }

def signedApproval (approval : Approval) : Approval :=
  { approval with signature := stubSignatureFor "pubkey-1" (signedMessage approval) }

def validApproval : Approval :=
  signedApproval unsignedApproval

def baseState : ApprovalState :=
  {
    session := "session-1",
    now := 10,
    publicKey := "pubkey-1",
    manifestDigest := "manifest-001",
    tools := [toolSpec],
    approvals := [validApproval]
  }

def validRaw : String :=
  requestRaw "db.execute" "write" "{\"database\":\"prod\",\"table\":\"users\",\"amount\":12.34}"

end Test.V2ValidationFixtures
