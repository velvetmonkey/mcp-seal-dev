/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.Parser

namespace SealV2

def isPrintableAsciiStringChar (c : Char) : Bool :=
  0x20 ≤ c.toNat && c.toNat ≤ 0x7e && c != '"' && c != '\\'

def isCanonicalString (value : String) : Bool :=
  value.toList.all isPrintableAsciiStringChar

def isDigitChar (c : Char) : Bool :=
  '0'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat

def isNonZeroDigitChar (c : Char) : Bool :=
  '1'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat

def isCanonicalIntDigits (digits : String) : Bool :=
  match digits.toList with
  | ['0'] => true
  | c :: rest => isNonZeroDigitChar c && rest.all isDigitChar
  | [] => false

def isCanonicalFracDigits (digits : String) : Bool :=
  match digits.toList.reverse with
  | last :: _ => isNonZeroDigitChar last && digits.toList.all isDigitChar
  | [] => false

def isCanonicalDecimal (decimal : Decimal) : Bool :=
  isCanonicalIntDigits decimal.intDigits &&
    (match decimal.fracDigits with
     | none => true
     | some digits => isCanonicalFracDigits digits) &&
    !(decimal.negative && decimal.intDigits == "0" && decimal.fracDigits.isNone)

def hasDuplicateKey (key : String) (fields : List (String × AST)) : Bool :=
  fields.any fun field => field.fst == key

def objectKeysUnique : List (String × AST) → Bool
  | [] => true
  | (key, _) :: rest => !hasDuplicateKey key rest && objectKeysUnique rest

mutual

def isCanonicalAst : AST → Bool
  | .null => true
  | .bool _ => true
  | .number value => isCanonicalDecimal value
  | .string value => isCanonicalString value
  | .array items => isCanonicalArray items
  | .object fields => isCanonicalObject fields

def isCanonicalArray : List AST → Bool
  | [] => true
  | item :: rest => isCanonicalAst item && isCanonicalArray rest

def isCanonicalObject : List (String × AST) → Bool
  | [] => true
  | (key, value) :: rest =>
      isCanonicalString key &&
        isCanonicalAst value &&
        !hasDuplicateKey key rest &&
        isCanonicalObject rest

end

def IsCanonical (ast : AST) : Prop :=
  isCanonicalAst ast = true

instance (ast : AST) : Decidable (IsCanonical ast) :=
  inferInstanceAs (Decidable (isCanonicalAst ast = true))

end SealV2
