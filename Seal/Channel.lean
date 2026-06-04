/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Data.Json
import SealCore.Event
import Seal.JsonUtil

namespace Seal

open Lean
open SealCore
open Seal.JsonUtil

private def parseApprovalLine (line : String) : Option Event :=
  let trimmed := line.trimAscii.toString
  if trimmed.isEmpty then none else
    match Json.parse trimmed with
    | .ok json =>
        match (json.getObjVal? "target").toOption with
        | some targetJson =>
            match targetJson with
            | .num n =>
                match (toString n).toNat? with
                | some target => some (.approval (UInt64.ofNat target))
                | none => none
            | .str s =>
                match s.toNat? with
                | some target => some (.approval (UInt64.ofNat target))
                | none => none
            | _ => none
        | none => none
    | .error _ => none

def readApprovals (path : System.FilePath) : IO (List Event) := do
  if (← path.pathExists) then
    let fileMeta ← System.FilePath.symlinkMetadata path
    if fileMeta.type == .symlink then
      throw <| IO.userError s!"approval control file must not be a symlink: {path}"
    let text ← IO.FS.readFile path
    pure <| text.splitOn "\n" |>.filterMap parseApprovalLine
  else
    pure []

def readApprovalsFrom (path : System.FilePath) (seenRecords : Nat) : IO (Nat × List Event) := do
  if (← path.pathExists) then
    let fileMeta ← System.FilePath.symlinkMetadata path
    if fileMeta.type == .symlink then
      throw <| IO.userError s!"approval control file must not be a symlink: {path}"
    let text ← IO.FS.readFile path
    let records := text.splitOn "\n" |>.filter (fun line => !(line.trimAscii.toString).isEmpty)
    let fresh := records.drop seenRecords
    pure (records.length, fresh.filterMap parseApprovalLine)
  else
    pure (seenRecords, [])

def ensureApprovalFile (path : System.FilePath) : IO Unit := do
  unless (← path.pathExists) do
    IO.FS.writeFile path ""
  discard <| IO.Process.output {
    cmd := "chmod",
    args := #["600", path.toString],
    stdin := .null,
    stdout := .null,
    stderr := .null
  }

end Seal
