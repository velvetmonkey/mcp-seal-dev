/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Data.Json
import Seal.JsonUtil

namespace Seal

open Lean
open Seal.JsonUtil

inductive MatchSpec where
  | always
  | containsAnyCi (argPath : List String) (needles : List String)
  deriving Repr

inductive TargetPart where
  | literal (value : String)
  | argPath (path : List String)
  deriving Repr

inductive ToolMode where
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

private def parseMatch (json : Json) : Except String MatchSpec := do
  let kind ← getObjString json "type"
  match kind with
  | "always" => pure .always
  | "contains_any_ci" =>
      let argPath ← getObjString json "arg"
      let needlesJson ← (← json.getObjVal? "needles").getArr?
      let needles ← needlesJson.toList.mapM (fun j => j.getStr?)
      pure (.containsAnyCi (splitPath argPath) needles)
  | other => throw s!"unsupported match type: {other}"

private def parseTargetPart (json : Json) : Except String TargetPart := do
  match ← getObjValOpt json "literal" with
  | some value => pure (.literal (← value.getStr?))
  | none =>
      match ← getObjValOpt json "arg" with
      | some value => pure (.argPath (splitPath (← value.getStr?)))
      | none => throw "target part must contain literal or arg"

private def parseToolRule (json : Json) : Except String ToolRule := do
  let name ← getObjString json "name"
  let modeText ← getObjString json "mode"
  let mode ← match modeText with
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
  let toolsJson ← (← json.getObjVal? "tools").getArr?
  let tools ← toolsJson.toList.mapM parseToolRule
  pure { approvalTtlMs, approvalFile, tools }

def loadPolicy (path : System.FilePath) : IO Policy := do
  let text ← IO.FS.readFile path
  match Json.parse text >>= parsePolicyJson with
  | .ok policy => pure policy
  | .error err => throw <| IO.userError s!"policy parse error: {err}"

end Seal
