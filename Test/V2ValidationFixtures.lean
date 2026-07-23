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

-- M5 real-Ed25519 test vector. The keypair is derived from the FIXED, documented
-- test seed `0x000102…1f` (NOT a real key) via Python `cryptography`; regenerate
-- with v2/milestones/05-sign/run.sh. Signatures are over the canonical
-- signed-message bytes produced by the M3 serialiser (`signedMessageRawFor`).
def testPublicKeyHex : PublicKey :=
  "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8"

/-- Ed25519 signature over the base message (M_A: issuedAt 0, expiry 120, nonce A). -/
def sigOverBaseMessage : Signature :=
  "ffbe15d60ae3d19a0f97465889f5e4927cdb3f36beebe649f546f9639fc3282966ecab0a0f7564af9cc1daa51a2903029f83f6b2668b710a7cb17dd20deeaf03"

/-- Ed25519 signature over the over-cap message (M_B: issuedAt 0, expiry 400, nonce B),
    used by the TTL-cap reject test so it rejects on TTL, not on a bad signature. -/
def sigOverTtlMessage : Signature :=
  "228b3400facb2bac68a54971754d70329885be7debfb99664303f784fdf38f19092652f51cd0bf5df7072136059c39c074024ff803bb7cee19b7cc3df1a1bb02"

/-- Set an approval's signed-message bytes to its OWN canonical message and attach
    an externally-produced Ed25519 signature hex over exactly those bytes. -/
def approvalWithSig (approval : Approval) (sig : Signature) : Approval :=
  { approval with
    signedMessageRaw := signedMessageRawFor (signedMessage approval),
    signature := sig }

def validApproval : Approval :=
  approvalWithSig unsignedApproval sigOverBaseMessage

def baseState : ApprovalState :=
  {
    session := "session-1",
    now := 10,
    publicKey := testPublicKeyHex,
    manifestDigest := "manifest-001",
    tools := [toolSpec],
    approvals := [validApproval],
    policyVersion := "policy-1"
  }

def validRaw : String :=
  requestRaw "db.execute" "write" "{\"database\":\"prod\",\"table\":\"users\",\"amount\":12.34}"

/-! ### Second Allow vector (escape-events SHOW)

Same tool/action, different arguments (`table:"orders"`), nonce B, in-cap
expiry 120 — so a single run can produce TWO Allows with DISTINGUISHABLE
canonical outputs, which is what makes the order-preservation half of
`escape_events_no_influence` witnessable at runtime. Signature minted from
the same fixed, documented test seed `0x000102…1f` (NOT a real key) via
Python `cryptography`, over the canonical bytes printed by
`lake exe v2_signed_bytes orders`. -/

def ordersArgs : AST :=
  .object [("database", .string "prod"), ("table", .string "orders"), ("amount", .number {
    negative := false,
    intDigits := "12",
    fracDigits := some "34"
  })]

def ordersTarget : Target := { target with arguments := ordersArgs }

def unsignedOrdersApproval : Approval :=
  let message : SignedMessage := {
    target := ordersTarget,
    session := "session-1",
    issuedAt := 0,
    expiry := 120,
    nonce := nonceB
  }
  {
    target := ordersTarget,
    session := "session-1",
    issuedAt := 0,
    expiresAt := 120,
    consumed := false,
    signedMessageRaw := signedMessageRawFor message,
    signature := "",
    nonce := nonceB
  }

/-- Ed25519 signature over the orders message (M_C: issuedAt 0, expiry 120,
    nonce B, target arguments `table:"orders"`). -/
def sigOverOrdersMessage : Signature :=
  "8746f2922e89c360674d79e8ed7a7013f6ee509edd9b2699fbde8ec9474f88d37d5c1358b7c0ae40a393a02fff646cfdd9eedbe5f3c6f2e6e7f608bc9ba04e09"

def validOrdersApproval : Approval :=
  approvalWithSig unsignedOrdersApproval sigOverOrdersMessage

/-- `baseState` carrying BOTH live approvals (nonce A: users; nonce B: orders). -/
def twoApprovalState : ApprovalState :=
  { baseState with approvals := [validApproval, validOrdersApproval] }

def validOrdersRaw : String :=
  requestRaw "db.execute" "write" "{\"database\":\"prod\",\"table\":\"orders\",\"amount\":12.34}"

end Test.V2ValidationFixtures
