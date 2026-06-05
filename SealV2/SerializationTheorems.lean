/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.Validation

namespace SealV2

/- GROUP A: parser canonicality, worker induction. -/

theorem parseStringChars_preserves_canonical
    (acc value : String) (chars rest : List Char) :
    isCanonicalString acc = true →
      parseStringChars acc chars = some (value, rest) →
        isCanonicalString value = true := by
  sorry

theorem parseNumber_returns_canonical
    (chars rest : List Char) (ast : AST) :
    parseNumber chars = some (ast, rest) →
      IsCanonical ast := by
  sorry

theorem parseArrayFuel_returns_canonical
    (fuel : Nat) (acc : List AST) (chars rest : List Char) (ast : AST) :
    isCanonicalArray acc = true →
      parseArrayFuel fuel acc chars = some (ast, rest) →
        IsCanonical ast := by
  sorry

theorem parseObjectFuel_returns_canonical
    (fuel : Nat) (acc : List (String × AST)) (chars rest : List Char) (ast : AST) :
    isCanonicalObject acc = true →
      parseObjectFuel fuel acc chars = some (ast, rest) →
        IsCanonical ast := by
  sorry

theorem parse_returns_canonical (raw : RawBytes) (ast : AST) :
    parse raw = some ast →
      IsCanonical ast := by
  sorry

/- GROUP B: serializer/parser roundtrip, per type. -/

theorem serialize_roundtrip_null :
    parse (serializeAst ⟨.null, rfl⟩) = some .null := by
  sorry

theorem serialize_roundtrip_bool (value : Bool) :
    parse (serializeAst ⟨.bool value, rfl⟩) = some (.bool value) := by
  sorry

theorem serialize_roundtrip_number (value : Decimal)
    (h : IsCanonical (.number value)) :
    parse (serializeAst ⟨.number value, h⟩) = some (.number value) := by
  sorry

theorem serialize_roundtrip_string (value : String)
    (h : IsCanonical (.string value)) :
    parse (serializeAst ⟨.string value, h⟩) = some (.string value) := by
  sorry

theorem serialize_roundtrip_array (items : List AST)
    (h : IsCanonical (.array items)) :
    parse (serializeAst ⟨.array items, h⟩) = some (.array items) := by
  sorry

theorem serialize_roundtrip_object (fields : List (String × AST))
    (h : IsCanonical (.object fields)) :
    parse (serializeAst ⟨.object fields, h⟩) = some (.object fields) := by
  sorry

theorem canonical_roundtrip (ast : {ast // IsCanonical ast}) :
    parse (serializeAst ast) = some ast.val := by
  sorry

/- GROUP C: serializeAst determinism. -/

theorem serializeAst_deterministic (ast : AST)
    (left right : IsCanonical ast) :
    serializeAst ⟨ast, left⟩ = serializeAst ⟨ast, right⟩ := by
  sorry

/- GROUP D: ValidCapability-backed lift. -/

theorem serialize_validCapability_roundtrip {state : ApprovalState}
    (ast : AST) (witness : ValidCapability ast state) :
    parse (serialize ⟨ast, witness⟩) = some ast := by
  sorry

end SealV2
