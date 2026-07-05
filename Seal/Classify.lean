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

def matchRule (rule : ToolRule) (args : Json) : Bool :=
  match rule.matcher with
  | .always => true
  | .containsAnyCi path needles =>
      match atPath args path >>= jsonScalarToString with
      | some value => containsAnyCi value needles
      | none => false

def evalTargetParts (parts : List TargetPart) (args : Json) : Option (List String) :=
  parts.mapM fun part =>
    match part with
    | .literal value => some value
    | .argPath path => atPath args path >>= jsonScalarToString

def classifyToolCall (policy : Policy) (toolName : String) (args : Json) : HostEvent :=
  match policy.tools.find? (fun rule => rule.name == toolName) with
  | none => .event .defaultDeny "unknown tool"
  | some rule =>
      if !matchRule rule args then
        .event .defaultDeny s!"unmatched policy for {toolName}"
      else
        match rule.mode with
        | .deny => .event .defaultDeny s!"flat deny: {toolName}"
        | .guarded =>
            match evalTargetParts rule.target args with
            | some parts =>
                let target := stableHashParts (toolName :: parts)
                .event (.guarded target) target.toHex
            | none => .event .defaultDeny s!"missing target field: {toolName}"

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
