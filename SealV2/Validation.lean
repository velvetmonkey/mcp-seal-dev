/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.Serialization
import SealV2.Crypto

namespace SealV2

abbrev SessionId := String
abbrev PublicKey := String
abbrev Signature := String
abbrev ManifestDigest := String
abbrev ToolVersion := String
abbrev Action := String
abbrev ToolName := String

structure CapabilityRequest where
  tool : ToolName
  action : Action
  arguments : AST
  deriving Repr, BEq

structure ToolSpec where
  tool : ToolName
  version : ToolVersion
  actions : List Action
  deriving Repr, BEq

structure Target where
  tool : ToolName
  action : Action
  toolVersion : ToolVersion
  manifestDigest : ManifestDigest
  arguments : AST
  deriving Repr, BEq

/-- A nonce is a fixed-width 32-byte value rendered as exactly 64 lowercase hex characters. -/
def isLowerHexChar (c : Char) : Bool :=
  ('0'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat) ||
  ('a'.toNat ≤ c.toNat && c.toNat ≤ 'f'.toNat)

def isCanonicalNonceString (s : String) : Bool :=
  s.toList.length == 64 && s.toList.all isLowerHexChar

/-- A canonical nonce carries the proof that its string form is exactly 64 lowercase hex chars. -/
structure Nonce where
  value : String
  canonical : isCanonicalNonceString value = true

instance : BEq Nonce where
  beq a b := a.value == b.value

instance : Repr Nonce where
  reprPrec n p := reprPrec n.value p

structure SignedMessage where
  target : Target
  session : SessionId
  issuedAt : Nat
  expiry : Nat
  nonce : Nonce
  deriving Repr, BEq

structure Approval where
  target : Target
  session : SessionId
  issuedAt : Nat
  expiresAt : Nat
  consumed : Bool
  signedMessageRaw : RawBytes
  signature : Signature
  nonce : Nonce
  deriving Repr, BEq

/-- The namespace a consumed nonce lives in: a replay is only a replay within the
    same public key, target, session, and policy version. -/
structure ReplayNamespace where
  publicKey : PublicKey
  target : Target
  session : SessionId
  policyVersion : String
  deriving Repr, BEq

/-- A spent nonce, bound to its namespace, with the time it may be pruned after. -/
structure ConsumedNonce where
  ns : ReplayNamespace
  nonce : Nonce
  expiresAt : Nat
  deriving Repr, BEq

structure ApprovalState where
  session : SessionId
  now : Nat
  publicKey : PublicKey
  manifestDigest : ManifestDigest
  tools : List ToolSpec
  approvals : List Approval
  policyVersion : String := ""
  maxApprovalTtl : Nat := 300
  consumedNonces : List ConsumedNonce := []
  deriving Repr, BEq

def signedMessage (approval : Approval) : SignedMessage :=
  { target := approval.target, session := approval.session,
    issuedAt := approval.issuedAt, expiry := approval.expiresAt, nonce := approval.nonce }

def signedMessageAst (message : SignedMessage) : AST :=
  .object [
    ("target", .object [
      ("tool", .string message.target.tool),
      ("action", .string message.target.action),
      ("toolVersion", .string message.target.toolVersion),
      ("manifestDigest", .string message.target.manifestDigest),
      ("arguments", message.target.arguments)
    ]),
    ("session", .string message.session),
    ("issuedAt", .number { negative := false, intDigits := toString message.issuedAt, fracDigits := none }),
    ("expiry", .number { negative := false, intDigits := toString message.expiry, fracDigits := none }),
    ("nonce", .string message.nonce.value)
  ]

/-- Recover a non-negative integer from a canonical decimal AST node. -/
def astNat? : AST → Option Nat
  | .number d => if d.negative then none else (if d.fracDigits.isSome then none else d.intDigits.toNat?)
  | _ => none

/-- Structural inverse of `signedMessageAst`. Requires the trailing nonce field to be
    a `.string` satisfying `isCanonicalNonceString`; rejects everything else. This is
    where nonce canonicality is enforced on the parsed signed-message path. -/
def signedMessageFromAst? (ast : AST) : Option SignedMessage :=
  match ast with
  | .object [
      ("target", .object [
        ("tool", .string tool),
        ("action", .string action),
        ("toolVersion", .string toolVersion),
        ("manifestDigest", .string manifestDigest),
        ("arguments", arguments)]),
      ("session", .string session),
      ("issuedAt", issuedAtAst),
      ("expiry", expiryAst),
      ("nonce", .string nonceStr)] =>
    match astNat? issuedAtAst, astNat? expiryAst with
    | some issuedAt, some expiry =>
        if h : isCanonicalNonceString nonceStr = true then
          some {
            target := { tool, action, toolVersion, manifestDigest, arguments },
            session := session,
            issuedAt := issuedAt,
            expiry := expiry,
            nonce := { value := nonceStr, canonical := h }
          }
        else
          none
    | _, _ => none
  | _ => none

def signedMessageCanonical? (message : SignedMessage) : Option {ast // IsCanonical ast} :=
  let ast := signedMessageAst message
  if h : IsCanonical ast then
    some ⟨ast, h⟩
  else
    none

def signedParse (raw : RawBytes) : Option {ast // IsCanonical ast} :=
  match parse raw with
  | none => none
  | some ast =>
      if h : IsCanonical ast then
        if raw == serializeAst ⟨ast, h⟩ then
          some ⟨ast, h⟩
        else
          none
      else
        none

def signedMessageRawFor (message : SignedMessage) : RawBytes :=
  match signedMessageCanonical? message with
  | some ast => serializeAst ast
  | none => "<noncanonical>"

def verifySignature (publicKey : PublicKey) (approval : Approval) : Bool :=
  match signedParse approval.signedMessageRaw with
  | some ast =>
      (signedMessageFromAst? ast.val == some (signedMessage approval)) &&
        ast.val == signedMessageAst (signedMessage approval) &&
        -- M5: real Ed25519 over EXACTLY the canonical signed-message bytes
        -- (`signedMessageRaw`, pinned canonical by `signed_parse_canonical`). The
        -- public key and signature are hex; fail-closed if either is malformed.
        -- Crypto correctness is the TCB(A3) assumption — see SealV2/Crypto.lean.
        (match hexDecode? publicKey, hexDecode? approval.signature with
         | some pkBytes, some sigBytes =>
             ed25519Verify pkBytes approval.signedMessageRaw.toUTF8 sigBytes
         | _, _ => false)
  | none => false

structure SignatureVerified (publicKey : PublicKey) (approval : Approval) : Prop where
  verified : verifySignature publicKey approval = true
  signed_message_is_target_session_expiry :
    signedMessage approval =
      { target := approval.target, session := approval.session,
        issuedAt := approval.issuedAt, expiry := approval.expiresAt, nonce := approval.nonce }

def lookupObj (key : String) (fields : List (String × AST)) : Option AST :=
  match fields with
  | [] => none
  | (k, v) :: rest => if k == key then some v else lookupObj key rest

def astString? : AST → Option String
  | .string value => some value
  | _ => none

def requestFromAst (ast : AST) : Option CapabilityRequest :=
  match ast with
  | .object fields => do
      let method ← lookupObj "method" fields >>= astString?
      if method != "tools/call" then
        none
      else
        match lookupObj "params" fields with
        | some (.object params) =>
            let tool ← lookupObj "name" params >>= astString?
            let action ← lookupObj "action" params >>= astString?
            let arguments ← lookupObj "arguments" params
            some { tool, action, arguments }
        | _ => none
  | _ => none

def findToolSpec (state : ApprovalState) (request : CapabilityRequest) : Option ToolSpec :=
  state.tools.find? fun spec => spec.tool == request.tool && spec.actions.any (fun action => action == request.action)

def targetFor (state : ApprovalState) (request : CapabilityRequest) (spec : ToolSpec) : Target :=
  {
    tool := request.tool,
    action := request.action,
    toolVersion := spec.version,
    manifestDigest := state.manifestDigest,
    arguments := request.arguments
  }

/-- The default ceiling on an approval's lifetime, in seconds. -/
def defaultMaxApprovalTtl : Nat := 300

/-- Drop consumed-nonce entries whose pruning time has passed. Kept entries are
    those still live at `now`. -/
def pruneConsumedNonces (now : Nat) (entries : List ConsumedNonce) : List ConsumedNonce :=
  entries.filter (fun e => now <= e.expiresAt)

def replayNamespace (state : ApprovalState) (target : Target) : ReplayNamespace :=
  { publicKey := state.publicKey,
    target := target,
    session := state.session,
    policyVersion := state.policyVersion }

/-- True iff this approval's nonce has already been spent in the same pruned namespace. -/
def nonceConsumed (state : ApprovalState) (target : Target) (approval : Approval) : Bool :=
  let ns := replayNamespace state target
  let pruned := pruneConsumedNonces state.now state.consumedNonces
  pruned.any (fun e => e.ns == ns && e.nonce == approval.nonce)

/-- True iff the approval's claimed lifetime is well-formed and within the state's cap. -/
def ttlWithinCap (state : ApprovalState) (approval : Approval) : Bool :=
  approval.issuedAt <= approval.expiresAt &&
    (approval.expiresAt - approval.issuedAt) <= state.maxApprovalTtl

def approvalLiveFor (state : ApprovalState) (target : Target) (approval : Approval) : Bool :=
  approval.target == target &&
    approval.session == state.session &&
    approval.consumed == false &&
    state.now <= approval.expiresAt &&
    ttlWithinCap state approval &&
    !nonceConsumed state target approval &&
    verifySignature state.publicKey approval

def findApproval (state : ApprovalState) (target : Target) : Option Approval :=
  state.approvals.find? (approvalLiveFor state target)

structure ValidCapability (ast : AST) (state : ApprovalState) where
  ast_canonical : IsCanonical ast
  request : CapabilityRequest
  request_from_ast : requestFromAst ast = some request
  toolSpec : ToolSpec
  tool_spec_in_state : state.tools.contains toolSpec = true
  action_allowed : toolSpec.actions.contains request.action = true
  target : Target
  target_matches : target = targetFor state request toolSpec
  approval : Approval
  approval_in_state : state.approvals.contains approval = true
  approval_target_matches : (approval.target == target) = true
  approval_session_matches : approval.session = state.session
  approval_unused : approval.consumed = false
  approval_unexpired : state.now <= approval.expiresAt
  signature_verified : SignatureVerified state.publicKey approval

def validate (ast : AST) (state : ApprovalState) : Option (Σ checkedAst, ValidCapability checkedAst state) :=
  if hCanonical : IsCanonical ast then
    match hReq : requestFromAst ast with
    | none => none
    | some request =>
        match findToolSpec state request with
        | none => none
        | some spec =>
            let target := targetFor state request spec
            match findApproval state target with
            | none => none
            | some approval =>
                if hSig : verifySignature state.publicKey approval then
                  if hTools : state.tools.contains spec then
                    if hAction : spec.actions.contains request.action then
                      if hApprovals : state.approvals.contains approval then
                        if hTarget : approval.target == target then
                          if hSession : approval.session = state.session then
                            if hUnused : approval.consumed = false then
                              if hExpiry : state.now <= approval.expiresAt then
                                some ⟨ast, {
                                  ast_canonical := hCanonical,
                                  request := request,
                                  request_from_ast := hReq,
                                  toolSpec := spec,
                                  tool_spec_in_state := hTools,
                                  action_allowed := hAction,
                                  target := target,
                                  target_matches := rfl,
                                  approval := approval,
                                  approval_in_state := hApprovals,
                                  approval_target_matches := hTarget,
                                  approval_session_matches := hSession,
                                  approval_unused := hUnused,
                                  approval_unexpired := hExpiry,
                                  signature_verified := {
                                    verified := hSig,
                                    signed_message_is_target_session_expiry := rfl
                                  }
                                }⟩
                              else none
                            else none
                          else none
                        else none
                      else none
                    else none
                  else none
                else none
  else
    none

def serialize {state : ApprovalState} (checked : Σ ast, ValidCapability ast state) : CanonicalBytes :=
  serializeAst ⟨checked.fst, checked.snd.ast_canonical⟩

/-- Errors a host-side replay store may report. Any error is treated as a denial. -/
inductive ReplayStoreError where
  | conflict
  | backend (message : String)
  deriving Repr, BEq

/-- The host-provided, durable replay store seam.

    Contract (fail-closed): a successful approval requires the approval's nonce to be
    persisted atomically *before* the validation witness is returned. Any store error,
    or a `contains?` hit, denies the request. `validateAndConsumeWithStore` is the only
    sanctioned path; it never returns a witness without a successful `insertConsumed`. -/
structure ReplayStoreOps (σ : Type) where
  contains? : σ → ReplayNamespace → Nonce → Except ReplayStoreError Bool
  insertConsumed : σ → ConsumedNonce → Except ReplayStoreError σ
  pruneExpired : σ → Nat → Except ReplayStoreError σ

/-- Validate, then consume the nonce against a durable store. Fail-closed: validation
    failure, any store error, or a replay hit all return `none` (deny). On success the
    nonce is persisted before the witness is handed back, and the updated store is
    returned alongside it. -/
def validateAndConsumeWithStore {σ : Type}
    (ops : ReplayStoreOps σ) (store : σ)
    (ast : AST) (state : ApprovalState) :
    Option (σ × Σ checkedAst, ValidCapability checkedAst state) :=
  match validate ast state with
  | none => none
  | some checked =>
      let approval := checked.snd.approval
      let target := checked.snd.target
      let ns := replayNamespace state target
      match ops.pruneExpired store state.now with
      | .error _ => none
      | .ok pruned =>
          match ops.contains? pruned ns approval.nonce with
          | .error _ => none
          | .ok true => none
          | .ok false =>
              let entry : ConsumedNonce :=
                { ns := ns, nonce := approval.nonce, expiresAt := approval.expiresAt }
              match ops.insertConsumed pruned entry with
              | .error _ => none
              | .ok store' => some (store', checked)

/-- In-memory `List ConsumedNonce` replay store, for tests and reference. -/
def listReplayStore : ReplayStoreOps (List ConsumedNonce) where
  contains? entries ns nonce :=
    .ok (entries.any (fun e => e.ns == ns && e.nonce == nonce))
  insertConsumed entries entry := .ok (entry :: entries)
  pruneExpired entries now := .ok (pruneConsumedNonces now entries)

end SealV2
