# Aristotle handoff: M3 serialize scaffold

This branch is `feat/v2-m3-serialize`. The theorem bodies below are intentionally `sorry` on this WIP branch only.

## IsCanonical definition

File: `SealV2/Canonical.lean:7`

```lean
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
```

## AST type and parser worker signatures

File: `SealV2/Parser.lean:8`

```lean
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
```

File: `SealV2/Parser.lean:57`

```lean
def parseStringChars (acc : String) (chars : List Char) :
    Option (String × List Char) :=
```

File: `SealV2/Parser.lean:97`

```lean
def parseNumber (chars : List Char) : Option (AST × List Char) :=
```

File: `SealV2/Parser.lean:136`

```lean
def parseArrayFuel (fuel : Nat) (acc : List AST) (chars : List Char) :
    Option (AST × List Char) :=
```

File: `SealV2/Parser.lean:155`

```lean
def parseObjectFuel (fuel : Nat) (acc : List (String × AST)) (chars : List Char) :
    Option (AST × List Char) :=
```

## serializeAst definition

File: `SealV2/Serialization.lean:7`

```lean
def serializeDecimal (decimal : Decimal) : String :=
  (if decimal.negative then "-" else "") ++
    decimal.intDigits ++
    match decimal.fracDigits with
    | none => ""
    | some digits => "." ++ digits

mutual

def serializeAstValue : AST → CanonicalBytes
  | .null => "null"
  | .bool true => "true"
  | .bool false => "false"
  | .number value => serializeDecimal value
  | .string value => "\"" ++ value ++ "\""
  | .array items => "[" ++ serializeArrayValue items ++ "]"
  | .object fields => "{" ++ serializeObjectValue fields ++ "}"

def serializeArrayValue : List AST → String
  | [] => ""
  | [item] => serializeAstValue item
  | item :: rest => serializeAstValue item ++ "," ++ serializeArrayValue rest

def serializeObjectValue : List (String × AST) → String
  | [] => ""
  | [(key, value)] => "\"" ++ key ++ "\":" ++ serializeAstValue value
  | (key, value) :: rest =>
      "\"" ++ key ++ "\":" ++ serializeAstValue value ++ "," ++ serializeObjectValue rest

end

def serializeAst (ast : {ast // IsCanonical ast}) : CanonicalBytes :=
  serializeAstValue ast.val
```

## Group A: parser canonicality, worker induction

File: `SealV2/SerializationTheorems.lean:9`

```lean
theorem parseStringChars_preserves_canonical
    (acc value : String) (chars rest : List Char) :
    isCanonicalString acc = true →
      parseStringChars acc chars = some (value, rest) →
        isCanonicalString value = true := by
```

File: `SealV2/SerializationTheorems.lean:16`

```lean
theorem parseNumber_returns_canonical
    (chars rest : List Char) (ast : AST) :
    parseNumber chars = some (ast, rest) →
      IsCanonical ast := by
```

File: `SealV2/SerializationTheorems.lean:22`

```lean
theorem parseArrayFuel_returns_canonical
    (fuel : Nat) (acc : List AST) (chars rest : List Char) (ast : AST) :
    isCanonicalArray acc = true →
      parseArrayFuel fuel acc chars = some (ast, rest) →
        IsCanonical ast := by
```

File: `SealV2/SerializationTheorems.lean:29`

```lean
theorem parseObjectFuel_returns_canonical
    (fuel : Nat) (acc : List (String × AST)) (chars rest : List Char) (ast : AST) :
    isCanonicalObject acc = true →
      parseObjectFuel fuel acc chars = some (ast, rest) →
        IsCanonical ast := by
```

File: `SealV2/SerializationTheorems.lean:36`

```lean
theorem parse_returns_canonical (raw : RawBytes) (ast : AST) :
    parse raw = some ast →
      IsCanonical ast := by
```

## Group B: serializer/parser roundtrip

File: `SealV2/SerializationTheorems.lean:43`

```lean
theorem serialize_roundtrip_null :
    parse (serializeAst ⟨.null, rfl⟩) = some .null := by
```

File: `SealV2/SerializationTheorems.lean:47`

```lean
theorem serialize_roundtrip_bool (value : Bool) :
    parse (serializeAst ⟨.bool value, rfl⟩) = some (.bool value) := by
```

File: `SealV2/SerializationTheorems.lean:51`

```lean
theorem serialize_roundtrip_number (value : Decimal)
    (h : IsCanonical (.number value)) :
    parse (serializeAst ⟨.number value, h⟩) = some (.number value) := by
```

File: `SealV2/SerializationTheorems.lean:56`

```lean
theorem serialize_roundtrip_string (value : String)
    (h : IsCanonical (.string value)) :
    parse (serializeAst ⟨.string value, h⟩) = some (.string value) := by
```

File: `SealV2/SerializationTheorems.lean:61`

```lean
theorem serialize_roundtrip_array (items : List AST)
    (h : IsCanonical (.array items)) :
    parse (serializeAst ⟨.array items, h⟩) = some (.array items) := by
```

File: `SealV2/SerializationTheorems.lean:66`

```lean
theorem serialize_roundtrip_object (fields : List (String × AST))
    (h : IsCanonical (.object fields)) :
    parse (serializeAst ⟨.object fields, h⟩) = some (.object fields) := by
```

File: `SealV2/SerializationTheorems.lean:71`

```lean
theorem canonical_roundtrip (ast : {ast // IsCanonical ast}) :
    parse (serializeAst ast) = some ast.val := by
```

## Group C: serializeAst determinism

File: `SealV2/SerializationTheorems.lean:77`

```lean
theorem serializeAst_deterministic (ast : AST)
    (left right : IsCanonical ast) :
    serializeAst ⟨ast, left⟩ = serializeAst ⟨ast, right⟩ := by
```

## Group D: ValidCapability-backed lift

File: `SealV2/SerializationTheorems.lean:84`

```lean
theorem serialize_validCapability_roundtrip {state : ApprovalState}
    (ast : AST) (witness : ValidCapability ast state) :
    parse (serialize ⟨ast, witness⟩) = some ast := by
```
