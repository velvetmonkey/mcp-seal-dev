/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.Validation
import Aesop


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
    · cases hResult; assumption
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
    · cases hResult; assumption
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
      · cases hParse; assumption
      · contradiction
    · contradiction
  · contradiction

/- ============================================================
   HELPER LEMMAS for roundtrip proofs
   ============================================================ -/

theorem string_singleton_append_ofList (c : Char) (cs : List Char) :
    String.singleton c ++ String.ofList cs = String.ofList (c :: cs) := by
  apply String.ext
  simp [String.toList_append, String.toList_singleton, String.toList_ofList]

private theorem ofList_toList_eq (s : String) (cs : List Char) (h : s.toList = cs) :
    String.ofList cs = s := by rw [← h, String.ofList_toList]

private theorem push_eq_append_singleton (acc : String) (c : Char) :
    acc.push c = acc ++ String.singleton c := by
  rw [← String.toList_inj]; simp [String.toList_push]

theorem takeDigits_all_digits_nil (cs : List Char) (h : cs.all isDigit = true) :
    takeDigits cs = (String.ofList cs, []) := by
  induction cs with
  | nil => simp [takeDigits]
  | cons c cs' ih =>
    have hc := List.all_eq_true.mp h c (List.mem_cons_self ..)
    have hcs' := List.all_eq_true.mpr (fun x hx => List.all_eq_true.mp h x (List.mem_cons_of_mem c hx))
    simp [takeDigits, hc, ih hcs']
    apply String.ext; simp [String.toList_append, String.toList_singleton, String.toList_ofList]

theorem takeDigits_all_digits_append (cs : List Char) (c : Char) (rest : List Char)
    (hcs : cs.all isDigit = true) (hc : isDigit c = false) :
    takeDigits (cs ++ c :: rest) = (String.ofList cs, c :: rest) := by
  induction cs with
  | nil => simp [takeDigits, hc]
  | cons d cs' ih =>
    have hd := List.all_eq_true.mp hcs d (List.mem_cons_self ..)
    have hcs' := List.all_eq_true.mpr (fun x hx => List.all_eq_true.mp hcs x (List.mem_cons_of_mem d hx))
    simp [List.cons_append, takeDigits, hd, ih hcs']
    apply String.ext; simp [String.toList_append, String.toList_singleton, String.toList_ofList]

theorem digit_not_ws (c : Char) (h : isDigit c = true) : isWs c = false := by
  unfold isDigit at h; simp +decide at h; unfold isWs
  split <;> simp_all <;> omega

theorem nonZeroDigit_isDigit (c : Char) (h : isNonZeroDigit c = true) : isDigit c = true := by
  unfold isDigit isNonZeroDigit at *; grind

theorem parseIntegerDigits_canonical (intDigits : String) (rest : List Char)
    (hcan : isCanonicalIntDigits intDigits = true)
    (hrest : rest = [] ∨ ∃ c rest', rest = c :: rest' ∧ isDigit c = false) :
    parseIntegerDigits (intDigits.toList ++ rest) = some (intDigits, rest) := by
  unfold isCanonicalIntDigits at hcan
  cases hlist : intDigits.toList with
  | nil => rw [hlist] at hcan; simp at hcan
  | cons c cs =>
    rw [hlist] at hcan
    by_cases hc0 : c = '0' ∧ cs = []
    · obtain ⟨rfl, rfl⟩ := hc0
      have hid : intDigits = "0" := by rw [← String.toList_inj]; simp [hlist]; decide
      rcases hrest with rfl | ⟨d, rest', rfl, hd⟩ <;> simp [parseIntegerDigits, hid, *]
    · have hNZC : isNonZeroDigitChar c = true ∧ cs.all isDigitChar = true := by
        split at hcan
        · exact absurd (List.cons_eq_cons.mp ‹_›) hc0
        · rename_i hne; obtain ⟨rfl, rfl⟩ := List.cons_eq_cons.mp hne
          simp +decide at hcan; exact ⟨hcan.1, List.all_eq_true.mpr hcan.2⟩
        · simp at hcan
      have hcNe0 : c ≠ '0' := by
        intro heq; subst heq; unfold isNonZeroDigitChar at hNZC; simp +decide at hNZC
      have hIntEq : String.singleton c ++ String.ofList cs = intDigits :=
        by rw [string_singleton_append_ofList, ofList_toList_eq intDigits (c :: cs) hlist]
      show parseIntegerDigits ((c :: cs) ++ rest) = some (intDigits, rest)
      simp only [List.cons_append]
      simp [parseIntegerDigits]
      refine ⟨hNZC.1, ?_⟩
      rcases hrest with rfl | ⟨d, rest', rfl, hd⟩
      · rw [List.append_nil, takeDigits_all_digits_nil cs hNZC.2]
        exact ⟨hIntEq, rfl⟩
      · rw [takeDigits_all_digits_append cs d rest' hNZC.2 hd]
        exact ⟨hIntEq, rfl⟩

theorem parseFraction_nonDot (c : Char) (rest : List Char) (hc : c ≠ '.') :
    parseFraction (c :: rest) = some (none, c :: rest) := by
  unfold parseFraction
  split
  · rename_i h; simp at h; exact absurd h.1 hc
  · rfl

theorem parseFraction_canonical (fracDigits : String) (rest : List Char)
    (hcan : isCanonicalFracDigits fracDigits = true)
    (hrest : rest = [] ∨ ∃ c rest', rest = c :: rest' ∧ isDigit c = false) :
    parseFraction ('.' :: fracDigits.toList ++ rest) = some (some fracDigits, rest) := by
  unfold isCanonicalFracDigits at hcan
  cases hrev : fracDigits.toList.reverse with
  | nil => rw [hrev] at hcan; simp at hcan
  | cons last revtail =>
    rw [hrev] at hcan; simp +decide at hcan
    have h_digits : fracDigits.toList.all isDigitChar = true := List.all_eq_true.mpr hcan.2
    have h_takeDigits : takeDigits (fracDigits.toList ++ rest) = (fracDigits, rest) := by
      rcases hrest with rfl | ⟨c, rest', rfl, hc⟩
      · rw [List.append_nil, takeDigits_all_digits_nil _ h_digits, String.ofList_toList]
      · rw [takeDigits_all_digits_append _ _ _ h_digits hc, String.ofList_toList]
    unfold parseFraction
    simp [h_takeDigits, hrev]
    have : last ≠ '0' := by intro heq; subst heq; simp +decide at hcan
    simp [this]

theorem startsExponent_nonExp (c : Char) (rest : List Char) (hc : c ≠ 'e') (hc2 : c ≠ 'E') :
    startsExponent (c :: rest) = false := by
  unfold startsExponent; grind

theorem parseNumberUnchecked_serializeDecimal (value : Decimal) (rest : List Char)
    (hcan : isCanonicalDecimal value = true)
    (hrest : rest = [] ∨ ∃ c rest', rest = c :: rest' ∧ isDigit c = false ∧ c ≠ '.' ∧ c ≠ 'e' ∧ c ≠ 'E') :
    parseNumberUnchecked ((serializeDecimal value).toList ++ rest) = some (.number value, rest) := by
  sorry

theorem serializeDecimal_firstChar_neg (value : Decimal)
    (_hcan : isCanonicalDecimal value = true) (hneg : value.negative = true) :
    ∃ rest, (serializeDecimal value).toList = '-' :: rest := by
  unfold serializeDecimal; simp [hneg]; exact ⟨_, rfl⟩

theorem serializeDecimal_firstChar_pos (value : Decimal)
    (hcan : isCanonicalDecimal value = true) (hneg : value.negative = false) :
    ∃ c rest, (serializeDecimal value).toList = c :: rest ∧ isDigit c = true := by
  obtain ⟨c, rest, h_int⟩ : ∃ c rest, value.intDigits.toList = c :: rest ∧ isDigit c = true := by
    unfold isCanonicalDecimal at hcan
    unfold isCanonicalIntDigits at hcan
    unfold isNonZeroDigitChar at hcan; unfold isDigit at *
    grind
  unfold serializeDecimal; aesop

theorem parseStringCharsUnchecked_acc (acc : String) (value : String) (rest : List Char)
    (hcan : isCanonicalString value = true) :
    parseStringCharsUnchecked acc (value.toList ++ '"' :: rest) = some (acc ++ value, rest) := by
  suffices h : ∀ (acc : String) (cs : List Char),
      cs.all isAsciiStringChar = true →
      parseStringCharsUnchecked acc (cs ++ '"' :: rest) = some (acc ++ String.ofList cs, rest) by
    specialize h acc value.toList hcan
    simp [String.ofList_toList] at h
    exact h
  intro acc cs hcs
  induction cs generalizing acc with
  | nil => simp [parseStringCharsUnchecked]
  | cons c cs' ih =>
    have hc : isAsciiStringChar c = true :=
      List.all_eq_true.mp hcs c (List.mem_cons_self ..)
    have hcs' : cs'.all isAsciiStringChar = true :=
      List.all_eq_true.mpr (fun x hx => List.all_eq_true.mp hcs x (List.mem_cons_of_mem c hx))
    have hc_ne_quote : c ≠ '"' := by
      intro heq; subst heq; unfold isAsciiStringChar at hc; simp +decide at hc
    simp only [List.cons_append]
    unfold parseStringCharsUnchecked
    simp [hc, hc_ne_quote]
    rw [push_eq_append_singleton]
    rw [ih (acc ++ String.singleton c) hcs']
    congr 1; congr 1
    rw [← String.toList_inj]
    simp [String.toList_append, String.toList_ofList]

/- ============================================================
   GROUP B: serializer/parser roundtrip, per type.
   ============================================================ -/

theorem serialize_roundtrip_null :
    parse (serializeAst ⟨.null, rfl⟩) = some .null := by rfl

theorem serialize_roundtrip_bool (value : Bool) :
    parse (serializeAst ⟨.bool value, rfl⟩) = some (.bool value) := by
  cases value <;> rfl

theorem serialize_roundtrip_number (value : Decimal)
    (h : IsCanonical (.number value)) :
    parse (serializeAst ⟨.number value, h⟩) = some (.number value) := by
  sorry

set_option maxRecDepth 8000 in
set_option maxHeartbeats 6400000 in
theorem serialize_roundtrip_string (value : String)
    (h : IsCanonical (.string value)) :
    parse (serializeAst ⟨.string value, h⟩) = some (.string value) := by
  have hcs : isCanonicalString value = true := h
  change parse ("\"" ++ value ++ "\"") = some (.string value)
  have hq : ("\"" : String).toList = ['"'] := by decide
  simp only [parse, parseValueFuel, guardCanonicalResult, String.toList_append, hq,
    List.length_append, List.length_cons, List.length_nil, List.append_assoc]
  simp only [parseValueFuelUnchecked]
  simp only [List.cons_append, skipWs, isWs]
  simp +decide
  simp only [parseString, parseStringChars, guardCanonicalStringResult]
  rw [parseStringCharsUnchecked_acc "" value [] hcs]
  simp [hcs, IsCanonical, isCanonicalAst, skipWs]

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
  obtain ⟨astVal, hCanon⟩ := ast
  simp only
  cases astVal with
  | null =>
    have : serializeAst ⟨AST.null, hCanon⟩ = serializeAst ⟨AST.null, rfl⟩ := rfl
    rw [this]; rfl
  | bool value =>
    have : serializeAst ⟨AST.bool value, hCanon⟩ = serializeAst ⟨AST.bool value, rfl⟩ := rfl
    rw [this]; cases value <;> rfl
  | number value => exact serialize_roundtrip_number value hCanon
  | string value => exact serialize_roundtrip_string value hCanon
  | array items => exact serialize_roundtrip_array items hCanon
  | object fields => exact serialize_roundtrip_object fields hCanon

/- GROUP C: serializeAst determinism. -/

theorem serializeAst_deterministic (ast : AST)
    (left right : IsCanonical ast) :
    serializeAst ⟨ast, left⟩ = serializeAst ⟨ast, right⟩ := by rfl

/- GROUP D: ValidCapability-backed lift. -/

theorem serialize_validCapability_roundtrip {state : ApprovalState}
    (ast : AST) (witness : ValidCapability ast state) :
    parse (serialize ⟨ast, witness⟩) = some ast := by
  unfold serialize
  exact canonical_roundtrip ⟨ast, witness.ast_canonical⟩

end SealV2