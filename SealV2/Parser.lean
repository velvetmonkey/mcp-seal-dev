/- SPDX-License-Identifier: Apache-2.0 -/

namespace SealV2

abbrev RawBytes := String
abbrev CanonicalBytes := String

structure Decimal where
  negative : Bool
  intDigits : String
  fracDigits : Option String := none
  deriving Repr, BEq, DecidableEq

inductive AST where
  | null
  | bool (value : Bool)
  | number (value : Decimal)
  | string (value : String)
  | array (items : List AST)
  | object (fields : List (String × AST))
  deriving Repr, BEq

private def isWs : Char → Bool
  | ' ' | '\n' | '\r' | '\t' => true
  | _ => false

private def isDigit (c : Char) : Bool :=
  '0'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat

private def isNonZeroDigit (c : Char) : Bool :=
  '1'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat

private def isAsciiStringChar (c : Char) : Bool :=
  0x20 ≤ c.toNat && c.toNat ≤ 0x7e && c != '"' && c != '\\'

private def skipWs : List Char → List Char
  | c :: rest => if isWs c then skipWs rest else c :: rest
  | [] => []

private def takeDigits (chars : List Char) : String × List Char :=
  match chars with
  | c :: rest =>
      if isDigit c then
        let (digits, tail) := takeDigits rest
        (String.singleton c ++ digits, tail)
      else
        ("", chars)
  | [] => ("", [])

private def parseLiteral (literal : List Char) (value : AST) (chars : List Char) :
    Option (AST × List Char) :=
  if chars.take literal.length == literal then
    some (value, chars.drop literal.length)
  else
    none

private def parseStringChars (acc : String) (chars : List Char) :
    Option (String × List Char) :=
  match chars with
  | '"' :: rest => some (acc, rest)
  | c :: rest =>
      if isAsciiStringChar c then
        parseStringChars (acc ++ String.singleton c) rest
      else
        none
  | [] => none

private def parseString (chars : List Char) : Option (String × List Char) :=
  match chars with
  | '"' :: rest => parseStringChars "" rest
  | _ => none

private def parseIntegerDigits (chars : List Char) : Option (String × List Char) :=
  match chars with
  | '0' :: rest =>
      match rest with
      | c :: _ => if isDigit c then none else some ("0", rest)
      | [] => some ("0", [])
  | c :: rest =>
      if isNonZeroDigit c then
        let (digits, tail) := takeDigits rest
        some (String.singleton c ++ digits, tail)
      else
        none
  | [] => none

private def parseFraction (chars : List Char) : Option (Option String × List Char) :=
  match chars with
  | '.' :: rest =>
      let (digits, tail) := takeDigits rest
      match digits.toList.reverse with
      | last :: _ =>
          if last == '0' then none else some (some digits, tail)
      | [] => none
  | _ => some (none, chars)

private def parseNumber (chars : List Char) : Option (AST × List Char) :=
  let (negative, rest) :=
    match chars with
    | '-' :: rest => (true, rest)
    | _ => (false, chars)
  match parseIntegerDigits rest with
  | none => none
  | some (intDigits, afterInt) =>
      match parseFraction afterInt with
      | none => none
      | some (fracDigits, tail) =>
          if negative && intDigits == "0" && fracDigits.isNone then
            none
          else
            some (.number { negative, intDigits, fracDigits }, tail)

private def duplicateKey (key : String) (fields : List (String × AST)) : Bool :=
  fields.any (fun field => field.fst == key)

mutual

private def parseValueFuel (fuel : Nat) (chars : List Char) : Option (AST × List Char) :=
  match fuel with
  | 0 => none
  | Nat.succ fuel' =>
      match skipWs chars with
      | [] => none
      | 'n' :: _ => parseLiteral ['n', 'u', 'l', 'l'] .null (skipWs chars)
      | 't' :: _ => parseLiteral ['t', 'r', 'u', 'e'] (.bool true) (skipWs chars)
      | 'f' :: _ => parseLiteral ['f', 'a', 'l', 's', 'e'] (.bool false) (skipWs chars)
      | '"' :: _ =>
          match parseString (skipWs chars) with
          | some (s, rest) => some (.string s, rest)
          | none => none
      | '[' :: rest => parseArrayFuel fuel' [] (skipWs rest)
      | '{' :: rest => parseObjectFuel fuel' [] (skipWs rest)
      | '-' :: _ => parseNumber (skipWs chars)
      | c :: _ => if isDigit c then parseNumber (skipWs chars) else none

private def parseArrayFuel (fuel : Nat) (acc : List AST) (chars : List Char) :
    Option (AST × List Char) :=
  match fuel with
  | 0 => none
  | Nat.succ fuel' =>
      match skipWs chars with
      | ']' :: rest => some (.array acc.reverse, rest)
      | rest =>
          match parseValueFuel fuel' rest with
          | none => none
          | some (value, afterValue) =>
              match skipWs afterValue with
              | ',' :: afterComma =>
                  match skipWs afterComma with
                  | ']' :: _ => none
                  | checkedAfterComma => parseArrayFuel fuel' (value :: acc) checkedAfterComma
              | ']' :: afterClose => some (.array (value :: acc).reverse, afterClose)
              | _ => none

private def parseObjectFuel (fuel : Nat) (acc : List (String × AST)) (chars : List Char) :
    Option (AST × List Char) :=
  match fuel with
  | 0 => none
  | Nat.succ fuel' =>
      match skipWs chars with
      | '}' :: rest => some (.object acc.reverse, rest)
      | rest =>
          match parseString rest with
          | none => none
          | some (key, afterKey) =>
              if duplicateKey key acc then
                none
              else
                match skipWs afterKey with
                | ':' :: afterColon =>
                    match parseValueFuel fuel' afterColon with
                    | none => none
                    | some (value, afterValue) =>
                        match skipWs afterValue with
                        | ',' :: afterComma =>
                            match skipWs afterComma with
                            | '}' :: _ => none
                            | checkedAfterComma =>
                                parseObjectFuel fuel' ((key, value) :: acc) checkedAfterComma
                        | '}' :: afterClose => some (.object ((key, value) :: acc).reverse, afterClose)
                        | _ => none
                | _ => none

end

def parse (raw : RawBytes) : Option AST :=
  let chars := raw.toList
  match parseValueFuel (chars.length + 1) chars with
  | some (ast, rest) =>
      match skipWs rest with
      | [] => some ast
      | _ => none
  | none => none

end SealV2
