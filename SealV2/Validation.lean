/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.Parser

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

structure SignedMessage where
  target : Target
  session : SessionId
  expiry : Nat
  deriving Repr, BEq

structure Approval where
  target : Target
  session : SessionId
  expiresAt : Nat
  consumed : Bool
  signature : Signature
  deriving Repr, BEq

structure ApprovalState where
  session : SessionId
  now : Nat
  publicKey : PublicKey
  manifestDigest : ManifestDigest
  tools : List ToolSpec
  approvals : List Approval
  deriving Repr, BEq

def signedMessage (approval : Approval) : SignedMessage :=
  { target := approval.target, session := approval.session, expiry := approval.expiresAt }

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
    ("expiry", .number { negative := false, intDigits := toString message.expiry, fracDigits := none })
  ]

def stubSignatureFor (publicKey : PublicKey) (message : SignedMessage) : Signature :=
  s!"stub-ed25519:{publicKey}:{repr (signedMessageAst message)}"

def verifySignature (publicKey : PublicKey) (approval : Approval) : Bool :=
  approval.signature == stubSignatureFor publicKey (signedMessage approval)

structure SignatureVerified (publicKey : PublicKey) (approval : Approval) : Prop where
  verified : verifySignature publicKey approval = true
  signed_message_is_target_session_expiry :
    signedMessage approval =
      { target := approval.target, session := approval.session, expiry := approval.expiresAt }

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

def approvalLiveFor (state : ApprovalState) (target : Target) (approval : Approval) : Bool :=
  approval.target == target &&
    approval.session == state.session &&
    approval.consumed == false &&
    state.now <= approval.expiresAt &&
    verifySignature state.publicKey approval

def findApproval (state : ApprovalState) (target : Target) : Option Approval :=
  state.approvals.find? (approvalLiveFor state target)

structure ValidCapability (ast : AST) (state : ApprovalState) where
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

end SealV2
