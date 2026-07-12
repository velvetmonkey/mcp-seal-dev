/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Data.Json
import SealCore.Event
import Seal.Hash
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

inductive RuleDecision where
  | allow
  | guard (target : TargetHash) (targetText : String)
  | deny (reason : String)
  | invalid (reason : String)
  deriving Repr, BEq

def evaluateRule (policy : Policy) (toolName : String) (args : Json)
    (rule : ToolRule) : Option RuleDecision :=
  if rule.name != toolName || !matchRule rule args then none
  else match rule.mode with
    | .allow => some .allow
    | .deny => some (.deny s!"flat deny: {toolName}")
    | .guarded =>
        match evalTargetParts rule.target args with
        | some parts =>
            let target := stableHashParts (targetPrefix policy toolName ++ parts)
            some (.guard target target.toHex)
        | none => some (.invalid s!"missing target field: {toolName}")

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

def classifyToolCall (policy : Policy) (toolName : String) (args : Json) : HostEvent :=
  resolveRuleDecisions (policy.tools.filterMap (evaluateRule policy toolName args))

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

end Seal
