/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Data.Json
import Seal.JsonUtil

namespace Seal

open Lean
open Seal.JsonUtil

inductive MatchSpec where
  | always
  | equals (argPath : List String) (value : String)
  | startsWith (argPath : List String) (prefixValue : String)
  | containsAnyCi (argPath : List String) (needles : List String)
  | all (specs : List MatchSpec)
  | any (specs : List MatchSpec)
  deriving Repr

inductive TargetPart where
  | literal (value : String)
  | argPath (path : List String)
  | fullArguments
  deriving Repr

inductive ToolMode where
  | allow
  | guarded
  | deny
  deriving Repr, BEq

structure ToolRule where
  name : String
  mode : ToolMode
  matcher : MatchSpec := .always
  target : List TargetPart := []
  deriving Repr

structure Policy where
  /-- Approval lifetime in MILLISECONDS, capped at 300s, used to stamp an
      absolute expiry deadline (`now + approvalTtlMs`) when an approval is
      ingested. -/
  approvalTtlMs : Nat
  approvalFile : System.FilePath
  /-- Stable server identity prepended to new policy-v2 targets. Empty keeps
      the legacy target pre-image for backwards-compatible policies. -/
  serverIdentity : String := ""
  tools : List ToolRule
  deriving Repr

private def asciiLowerChar (c : Char) : Char :=
  if 'A' ≤ c ∧ c ≤ 'Z' then
    Char.ofNat (c.val.toNat + 32)
  else
    c

def asciiLower (s : String) : String :=
  s.map asciiLowerChar

def containsAnyCi (haystack : String) (needles : List String) : Bool :=
  let h := asciiLower haystack
  needles.any fun needle => h.contains (asciiLower needle)

private partial def parseMatch (json : Json) : Except String MatchSpec := do
  let kind ← getObjString json "type"
  match kind with
  | "always" => pure .always
  | "equals" =>
      pure (.equals (splitPath (← getObjString json "arg")) (← getObjString json "value"))
  | "starts_with" =>
      pure (.startsWith (splitPath (← getObjString json "arg")) (← getObjString json "value"))
  | "contains_any_ci" =>
      let argPath ← getObjString json "arg"
      let needlesJson ← (← json.getObjVal? "needles").getArr?
      let needles ← needlesJson.toList.mapM (fun j => j.getStr?)
      pure (.containsAnyCi (splitPath argPath) needles)
  | "all" =>
      let specs ← (← json.getObjVal? "matches").getArr?
      pure (.all (← specs.toList.mapM parseMatch))
  | "any" =>
      let specs ← (← json.getObjVal? "matches").getArr?
      pure (.any (← specs.toList.mapM parseMatch))
  | other => throw s!"unsupported match type: {other}"

private def parseTargetPart (json : Json) : Except String TargetPart := do
  match ← getObjValOpt json "literal" with
  | some value => pure (.literal (← value.getStr?))
  | none =>
      match ← getObjValOpt json "arg", ← getObjValOpt json "full_arguments" with
      | some value, none => pure (.argPath (splitPath (← value.getStr?)))
      | none, some value =>
          if ← value.getBool? then pure .fullArguments
          else throw "full_arguments must be true"
      | _, _ => throw "target part must contain exactly one of literal, arg, full_arguments"

private def parseToolRule (json : Json) : Except String ToolRule := do
  let name ← getObjString json "name"
  let modeText ← getObjString json "mode"
  let mode ← match modeText with
    | "allow" => pure ToolMode.allow
    | "guard" => pure ToolMode.guarded
    | "guarded" => pure ToolMode.guarded
    | "deny" => pure ToolMode.deny
    | other => throw s!"unsupported tool mode: {other}"
  let matcher ←
    match ← getObjValOpt json "match" with
    | some m => parseMatch m
    | none => pure .always
  let target ←
    match ← getObjValOpt json "target" with
    | some (.arr parts) => parts.toList.mapM parseTargetPart
    | some _ => throw "target must be an array"
    | none => pure []
  pure { name, mode, matcher, target }

/-- Approvals may not outlive this many seconds, mirroring SealV2's
    `maxApprovalTtl`. Longer configured TTLs are clamped down (fail-safe:
    a shorter lifetime is strictly more restrictive). -/
def maxApprovalTtlSeconds : Nat := 300

def parsePolicyJson (json : Json) : Except String Policy := do
  let approval ← json.getObjVal? "approval"
  let approvalTtlSeconds ← getObjNatD approval "ttl_seconds" 120
  let approvalTtlMs := (min approvalTtlSeconds maxApprovalTtlSeconds) * 1000
  let approvalFile := System.FilePath.mk (← getObjString approval "control_file")
  let serverIdentity ← match ← getObjValOpt json "server" with
    | some value => value.getStr?
    | none => pure ""
  let toolsJson ← (← json.getObjVal? "tools").getArr?
  let tools ← toolsJson.toList.mapM parseToolRule
  pure { approvalTtlMs, approvalFile, serverIdentity, tools }

def loadPolicy (path : System.FilePath) : IO Policy := do
  let text ← IO.FS.readFile path
  match Json.parse text >>= parsePolicyJson with
  | .ok policy => pure policy
  | .error err => throw <| IO.userError s!"policy parse error: {err}"

end Seal
