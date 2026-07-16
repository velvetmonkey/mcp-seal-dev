/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Data.Json
import Std.Sync.Mutex
import Std.Time
import SealCore
import Seal.Policy
import Seal.Classify
import Seal.Channel
import Seal.Block

namespace Seal

open Lean
open SealCore

structure Args where
  policy : System.FilePath
  cmd : String
  cmdArgs : Array String

def parseArgs (args : List String) : Except String Args :=
  match args with
  | "--policy" :: policy :: "--" :: cmd :: rest =>
      .ok { policy := System.FilePath.mk policy, cmd, cmdArgs := rest.toArray }
  | _ => .error "usage: seal --policy <policy.json> -- <server-cmd> <args...>"

def writeLocked (lock : Std.Mutex Unit) (out : IO.FS.Stream) (line : String) : IO Unit := do
  lock.atomically do
    out.putStr line
    out.flush

partial def relayChildStdout (lock : Std.Mutex Unit) (childOut : IO.FS.Handle) (hostOut : IO.FS.Stream) : IO Unit := do
  let line ← childOut.getLine
  if line.isEmpty then
    pure ()
  else
    writeLocked lock hostOut line
    relayChildStdout lock childOut hostOut

private def jsonId (json : Json) : Json :=
  (json.getObjVal? "id").toOption.getD Json.null

private def processHostLine
    (policy : Policy)
    (stateRef : IO.Ref State)
    (approvalSeenRef : IO.Ref Nat)
    (hostLine : String)
    (childIn : IO.FS.Handle)
    (hostOut : IO.FS.Stream)
    (stdoutLock : Std.Mutex Unit) : IO Unit := do
  let trimmed := hostLine.trimAscii.toString
  -- Fail closed on a pathological numeric literal BEFORE `Json.parse` sees it:
  -- a wire number with a monster decimal exponent makes `Json.parse` evaluate
  -- `10^exponent` and abort (native + interpreter) — a one-line DoS. Do NOT
  -- forward it to the child (a forward would be the fail-OPEN bypass) and do
  -- NOT parse it; block the request. (See Seal.JsonUtil.wireNumbersSafe.)
  if !JsonUtil.wireNumbersSafe trimmed then
    writeLocked stdoutLock hostOut (blockResponseLine Json.null "unsafe numeric literal")
    return
  let parsed := Json.parse trimmed
  match parsed with
  | .error _ =>
      childIn.putStr hostLine
      childIn.flush
  | .ok json =>
      match toolsCall? json with
      | none =>
          childIn.putStr hostLine
          childIn.flush
      | some (toolName, toolArgs) =>
          -- One wall-clock epoch reading (ms) per tools/call. Wall-clock (not
          -- monotonic) so a record-supplied `issuedAt` is comparable: the deadline
          -- is computed in Channel as min(issuedAt, now) + ttlMs. The same `now`
          -- decides liveness for this call, and each record is ingested exactly
          -- once (the seen counter), so deadlines are never re-stamped later.
          let nowTs ← Std.Time.Timestamp.now
          let now := nowTs.toMillisecondsSinceUnixEpoch.toInt.toNat
          let seen ← approvalSeenRef.get
          let (newSeen, approvals) ← readApprovalsFrom policy.approvalFile seen now policy.approvalTtlMs
          approvalSeenRef.set newSeen
          let st0 ← stateRef.get
          let st1 := approvals.foldl (fun st e => (step now st e).2) st0
          let hostEvent := classifyToolCall policy toolName toolArgs
          let (decision, st2) := step now st1 hostEvent.toEvent
          stateRef.set { approved := prune now st2.approved }
          match decision with
          | .allow =>
              childIn.putStr hostLine
              childIn.flush
          | .block =>
              writeLocked stdoutLock hostOut (blockResponseLine (jsonId json) hostEvent.targetText)

partial def hostLoop
    (policy : Policy)
    (stateRef : IO.Ref State)
    (approvalSeenRef : IO.Ref Nat)
    (hostIn hostOut : IO.FS.Stream)
    (childIn : IO.FS.Handle)
    (stdoutLock : Std.Mutex Unit) : IO Unit := do
  let line ← hostIn.getLine
  if line.isEmpty then
    pure ()
  else
    processHostLine policy stateRef approvalSeenRef line childIn hostOut stdoutLock
    hostLoop policy stateRef approvalSeenRef hostIn hostOut childIn stdoutLock

def main (rawArgs : List String) : IO UInt32 := do
  let parsed ←
    match parseArgs rawArgs with
    | .ok parsed => pure parsed
    | .error msg =>
        IO.eprintln msg
        return 2
  let policy ← loadPolicy parsed.policy
  ensureApprovalFile policy.approvalFile
  let child ← IO.Process.spawn {
    cmd := parsed.cmd,
    args := parsed.cmdArgs,
    stdin := .piped,
    stdout := .piped,
    stderr := .inherit
  }
  let hostIn ← IO.getStdin
  let hostOut ← IO.getStdout
  let stateRef ← IO.mkRef State.empty
  let approvalSeenRef ← IO.mkRef 0
  let stdoutLock ← Std.Mutex.new ()
  let relayTask ← IO.asTask (relayChildStdout stdoutLock child.stdout hostOut) Task.Priority.dedicated
  hostLoop policy stateRef approvalSeenRef hostIn hostOut child.stdin stdoutLock
  child.kill
  let exitCode ← child.wait
  match relayTask.get with
  | .ok _ => pure ()
  | .error err => throw err
  pure exitCode

end Seal

def main (args : List String) : IO UInt32 :=
  Seal.main args
