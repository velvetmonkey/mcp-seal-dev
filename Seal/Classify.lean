/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Data.Json
import SealCore.Event
import Seal.EffectCommitment
import Seal.Policy

namespace Seal

open Lean
open SealCore
open Seal.JsonUtil

inductive HostEvent where
  | event (event : Event) (targetText : String)
  deriving Repr

def HostEvent.toEvent : HostEvent → Event
  | .event e _ => e

def HostEvent.targetText : HostEvent → String
  | .event _ targetText => targetText

/-- Total (kernel-visible) match evaluation. `attach` threads the membership
    witness so the nested `all`/`any` recursion is accepted without `partial`;
    proofs about `classifyToolCall` may therefore unfold rule evaluation. -/
def matchSpec (spec : MatchSpec) (args : Json) : Bool :=
  match spec with
  | .always => true
  | .equals path expected =>
      (atPath args path >>= jsonScalarToString).any (· == expected)
  | .startsWith path prefixValue =>
      (atPath args path >>= jsonScalarToString).any (·.startsWith prefixValue)
  | .containsAnyCi path needles =>
      match atPath args path >>= jsonScalarToString with
      | some value => containsAnyCi value needles
      | none => false
  | .all specs => specs.attach.all (fun child => matchSpec child.val args)
  | .any specs => specs.attach.any (fun child => matchSpec child.val args)
termination_by sizeOf spec
decreasing_by
  all_goals
    have := List.sizeOf_lt_of_mem child.property
    simp only [MatchSpec.all.sizeOf_spec, MatchSpec.any.sizeOf_spec]
    omega

def matchRule (rule : ToolRule) (args : Json) : Bool :=
  matchSpec rule.matcher args

def evalTargetParts (parts : List TargetPart) (args : Json) : Option (List String) :=
  parts.mapM fun part =>
    match part with
    | .literal value => some value
    | .argPath path => atPath args path >>= jsonScalarToString
    | .fullArguments => some args.compress

def targetPrefix (policy : Policy) (toolName : String) : List String :=
  if policy.serverIdentity.isEmpty then [toolName]
  else [policy.serverIdentity, toolName]

/-- **PROPOSED** guard-target domain tag for the metadata-bearing target
    shape. The legacy target had no explicit domain tag. Changing this proposal
    later invalidates every target, approval, capability, and replay key that
    depends on it. -/
def guardTargetDomainTag : String := "seal.guard-target/v2-proposed-meta-all"

/-- The exact proposed guarded-target preimage. Policy matching and target-part
    selection still inspect arguments only; the complete validated metadata
    object is appended only after those decisions. -/
def guardTargetParts (policy : Policy) (toolName : String)
    (resolvedParts : List String) (metadata : ValidatedMeta) : List String :=
  [guardTargetDomainTag] ++ targetPrefix policy toolName ++ resolvedParts ++
    metadata.preimageParts

def guardTarget (policy : Policy) (toolName : String)
    (resolvedParts : List String) (metadata : ValidatedMeta) : TargetHash :=
  stableHashParts (guardTargetParts policy toolName resolvedParts metadata)

inductive RuleDecision where
  | allow
  | guard (target : TargetHash) (targetText : String)
  | deny (reason : String)
  | invalid (reason : String)
  deriving Repr, BEq

def evaluateRuleWithMeta (policy : Policy) (toolName : String) (args : Json)
    (metadata : ValidatedMeta)
    (rule : ToolRule) : Option RuleDecision :=
  if rule.name != toolName || !matchRule rule args then none
  else match rule.mode with
    | .allow => some .allow
    | .deny => some (.deny s!"flat deny: {toolName}")
    | .guarded =>
        match evalTargetParts rule.target args with
        | some parts =>
            let target := guardTarget policy toolName parts metadata
            some (.guard target target.toHex)
        | none => some (.invalid s!"missing target field: {toolName}")

/-- Legacy-era convenience surface: absence is represented explicitly and is
    therefore distinct from a call carrying `_meta: {}`. -/
def evaluateRule (policy : Policy) (toolName : String) (args : Json)
    (rule : ToolRule) : Option RuleDecision :=
  evaluateRuleWithMeta policy toolName args .absent rule

def firstBlocking? : List RuleDecision → Option String
  | [] => none
  | .deny reason :: _ => some reason
  | .invalid reason :: _ => some reason
  | _ :: rest => firstBlocking? rest

def guardDecisions (decisions : List RuleDecision) : List (TargetHash × String) :=
  decisions.filterMap fun decision => match decision with
    | .guard target text => some (target, text)
    | _ => none

def hasExplicitAllow (decisions : List RuleDecision) : Bool :=
  decisions.any (· == .allow)

def sameGuardTarget (first : TargetHash × String) (rest : List (TargetHash × String)) : Bool :=
  rest.all (fun next => next.1 == first.1)

def resolveRuleDecisions (decisions : List RuleDecision) : HostEvent :=
  match firstBlocking? decisions with
  | some reason => .event .defaultDeny reason
  | none =>
      match guardDecisions decisions with
      | first :: rest =>
          if sameGuardTarget first rest then .event (.guarded first.1) first.2
          else .event .defaultDeny "ambiguous guard target"
      | [] =>
          if hasExplicitAllow decisions then .event .benign "explicit policy allow"
          else .event .defaultDeny "no matching policy rule"

def classifyToolCallWithMeta (policy : Policy) (toolName : String) (args : Json)
    (metadata : ValidatedMeta) : HostEvent :=
  resolveRuleDecisions
    (policy.tools.filterMap (evaluateRuleWithMeta policy toolName args metadata))

/-- Legacy-era convenience surface with explicit metadata absence. -/
def classifyToolCall (policy : Policy) (toolName : String) (args : Json) : HostEvent :=
  classifyToolCallWithMeta policy toolName args .absent

/-- Compatibility equation for legacy-era proofs: the explicit-absence
    wrapper is definitionally the original rule-resolution shape. -/
theorem classifyToolCall_eq_resolve (policy : Policy) (toolName : String)
    (args : Json) :
    classifyToolCall policy toolName args =
      resolveRuleDecisions (policy.tools.filterMap (evaluateRule policy toolName args)) :=
  rfl

def toolsCall? (json : Json) : Option (String × Json) := do
  let methodJson ← (json.getObjVal? "method").toOption
  let method ← methodJson.getStr?.toOption
  if method != "tools/call" then
    none
  else
    let params ← (json.getObjVal? "params").toOption
    let nameJson ← (params.getObjVal? "name").toOption
    let name ← nameJson.getStr?.toOption
    let args := (params.getObjVal? "arguments").toOption.getD Json.null
    some (name, args)

/-- Extract a complete structurally validated `_meta` object from tool-call
    params. Absence remains a first-class value. Present null, array, scalar,
    or boolean metadata is rejected rather than collapsed into absence. Known
    field type/format and revision validation is a later protocol-boundary
    obligation; no key, including an unknown key, is projected away here. -/
def validatedMetaFromParams (params : Json) : Except String ValidatedMeta := do
  let object ← params.getObj?
  match object.get? "_meta" with
  | none => pure .absent
  | some (.obj metaObject) => pure (.present metaObject)
  | some _ => throw "`params._meta` must be an object"

/-- Metadata-aware tool-call extraction for the live V1 classifier. `none`
    still means a non-`tools/call`; `.error` is a malformed tool call that must
    fail closed before authority classification. -/
def toolsCallWithMeta? (json : Json) :
    Except String (Option (String × Json × ValidatedMeta)) := do
  match toolsCall? json with
  | none => pure none
  | some (name, args) =>
      let params ← json.getObjVal? "params"
      let metadata ← validatedMetaFromParams params
      pure (some (name, args, metadata))

/-- Whether a successfully parsed wire message is a top-level JSON array.
    MCP revisions 2025-06-18 and 2026-07-28 do not admit JSON-RPC batching,
    so host classifiers use this shape predicate as a fail-closed refusal
    boundary. Arrays nested inside an object are deliberately unaffected. -/
def isTopLevelArray : Json → Bool
  | .arr _ => true
  | _ => false

end Seal
