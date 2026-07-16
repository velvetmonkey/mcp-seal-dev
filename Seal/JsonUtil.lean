/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Data.Json

namespace Seal.JsonUtil

open Lean

def getObjValOpt (json : Json) (key : String) : Except String (Option Json) := do
  let obj ← json.getObj?
  pure (obj.get? key)

def getObjString (json : Json) (key : String) : Except String String := do
  (← json.getObjVal? key).getStr?

def getObjNatD (json : Json) (key : String) (default : Nat) : Except String Nat := do
  match ← getObjValOpt json key with
  | some v => v.getNat?
  | none => pure default

partial def atPath (json : Json) (path : List String) : Option Json :=
  match path with
  | [] => some json
  | key :: rest =>
      match json with
      | .obj obj =>
          match obj.get? key with
          | some child => atPath child rest
          | none => none
      | _ => none

def jsonScalarToString : Json → Option String
  | .str s => some s
  | .num n => some (toString n)
  | .bool b => some (if b then "true" else "false")
  | .null => some "null"
  | _ => none

/-- Longest decimal-exponent digit run a wire number may carry before it is
    treated as pathological. Legitimate JSON numbers never approach this — the
    f64 range is ~`1e±308` (3 exponent digits), and arbitrary-precision decimal
    arguments carry no larger exponent in practice. A longer run means
    `Json.parse` would evaluate `10^exponent` and abort with
    "Nat.pow exponent is too big" (native + Lean interpreter) or diverge in the
    emscripten build — the Lane C native-vs-wasm divergence the three-way
    differential found. Six is comfortably above every legitimate value and
    below the whole abort/timeout region. -/
def maxExponentDigits : Nat := 6

/-- One character of the exponent-length scan (`wireNumbersSafe`). Pure, total,
    allocation-bounded — NO parse, NO `Nat.pow`. Tracks whether we are inside a
    JSON string (whose content is inert: a string value `"1e9999999999"` is
    harmless — only an UNQUOTED numeric literal drives the parser's
    `10^exponent`) and, when outside a string, the length of the current
    exponent digit run and the longest seen so far.

    `e`/`E` outside a string only begins a number exponent (JSON has no other
    unquoted `e`; the letters in `true`/`false` are followed by no digits, so
    they contribute a zero-length run and never trip the bound). -/
structure NumberScan where
  inString : Bool := false
  escaped  : Bool := false
  inExp    : Bool := false
  expLen   : Nat  := 0
  worst    : Nat  := 0
  deriving Repr

def numberScanStep (st : NumberScan) (c : Char) : NumberScan :=
  if st.inString then
    if st.escaped then { st with escaped := false }
    else if c == '\\' then { st with escaped := true }
    else if c == '"' then { st with inString := false }
    else st
  else if c == '"' then
    { st with inString := true, inExp := false, expLen := 0 }
  else if st.inExp then
    if c.isDigit then
      let l := st.expLen + 1
      { st with expLen := l, worst := Nat.max st.worst l }
    else if c == '+' || c == '-' then
      st            -- optional sign immediately after `e`; still in the exponent
    else
      { st with inExp := false, expLen := 0 }
  else if c == 'e' || c == 'E' then
    { st with inExp := true, expLen := 0 }
  else
    st

/-- `false` iff the raw wire line carries an unquoted JSON number whose decimal
    exponent is longer than `maxExponentDigits` digits — a pathological value
    the kernel must refuse to parse (fail closed) rather than abort on. Pure and
    total: a `List.foldl` state machine over the characters, never `Json.parse`,
    never `Nat.pow`. Used by `Host.classifyLine` (seal-host) and the standalone
    `Seal` host to gate the parse. -/
def wireNumbersSafe (s : String) : Bool :=
  (s.toList.foldl numberScanStep {}).worst ≤ maxExponentDigits

def splitPath (s : String) : List String :=
  s.splitOn "." |>.filter (fun part => part ≠ "")

/-- Parser-boundary discipline: every key of `json` (which must be an object)
    must be in `allowed`. A stray key is a hard error naming the key and the
    context — a typo such as `temporral` must not silently leave a kernel
    unconfigured. -/
def expectObjKeys (json : Json) (allowed : List String) (ctx : String) :
    Except String Unit := do
  let obj ← json.getObj?
  match obj.keys.filter (fun k => !allowed.contains k) with
  | [] => pure ()
  | k :: _ => throw s!"unknown key '{k}' in {ctx}"

end Seal.JsonUtil
