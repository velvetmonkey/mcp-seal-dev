/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.Validation
import SealV2.SerializationLemmas

namespace SealV2

/- GROUP A: parser canonicality, worker induction. -/

theorem guardCanonicalResult_returns_canonical
    (result : Option (AST × List Char)) (ast : AST) (rest : List Char) :
    guardCanonicalResult result = some (ast, rest) →
      IsCanonical ast := by
  intro hResult
  unfold guardCanonicalResult at hResult
  split at hResult
  · split at hResult
    · cases hResult
      assumption
    · contradiction
  · contradiction

theorem guardCanonicalStringResult_returns_canonical
    (result : Option (String × List Char)) (value : String) (rest : List Char) :
    guardCanonicalStringResult result = some (value, rest) →
      isCanonicalString value = true := by
  intro hResult
  unfold guardCanonicalStringResult at hResult
  split at hResult
  · split at hResult
    · cases hResult
      assumption
    · contradiction
  · contradiction

theorem parseStringChars_preserves_canonical
    (acc value : String) (chars rest : List Char) :
    isCanonicalString acc = true →
      parseStringChars acc chars = some (value, rest) →
        isCanonicalString value = true := by
  intro _ hParse
  exact guardCanonicalStringResult_returns_canonical (parseStringCharsUnchecked acc chars) value rest hParse

theorem parseNumber_returns_canonical
    (chars rest : List Char) (ast : AST) :
    parseNumber chars = some (ast, rest) →
      IsCanonical ast := by
  exact guardCanonicalResult_returns_canonical (parseNumberUnchecked chars) ast rest

theorem parseArrayFuel_returns_canonical
    (fuel : Nat) (acc : List AST) (chars rest : List Char) (ast : AST) :
    isCanonicalArray acc = true →
      parseArrayFuel fuel acc chars = some (ast, rest) →
        IsCanonical ast := by
  intro _ hParse
  exact guardCanonicalResult_returns_canonical (parseArrayFuelUnchecked fuel acc chars) ast rest hParse

theorem parseObjectFuel_returns_canonical
    (fuel : Nat) (acc : List (String × AST)) (chars rest : List Char) (ast : AST) :
    isCanonicalObject acc = true →
      parseObjectFuel fuel acc chars = some (ast, rest) →
        IsCanonical ast := by
  intro _ hParse
  exact guardCanonicalResult_returns_canonical (parseObjectFuelUnchecked fuel acc chars) ast rest hParse

theorem parse_returns_canonical (raw : RawBytes) (ast : AST) :
    parse raw = some ast →
      IsCanonical ast := by
  intro hParse
  unfold parse at hParse
  dsimp at hParse
  split at hParse
  · split at hParse
    · split at hParse
      · cases hParse
        assumption
      · contradiction
    · contradiction
  · contradiction

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
