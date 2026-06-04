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

def splitPath (s : String) : List String :=
  s.splitOn "." |>.filter (fun part => part ≠ "")

end Seal.JsonUtil
