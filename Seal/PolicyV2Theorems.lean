/- SPDX-License-Identifier: Apache-2.0 -/

import Seal.Classify

namespace Seal

open Lean SealCore

theorem no_matching_rule_blocks :
    resolveRuleDecisions [] = .event .defaultDeny "no matching policy rule" := rfl

theorem explicit_allow_is_an_origin :
    resolveRuleDecisions [.allow] = .event .benign "explicit policy allow" := rfl

theorem guard_dominates_explicit_allow (target : TargetHash) (text : String) :
    resolveRuleDecisions [.allow, .guard target text] = .event (.guarded target) text := by
  simp [resolveRuleDecisions, firstBlocking?, guardDecisions, sameGuardTarget]

theorem blocking_decision_dominates {decisions : List RuleDecision} {reason : String}
    (h : firstBlocking? decisions = some reason) :
    resolveRuleDecisions decisions = .event .defaultDeny reason := by
  simp [resolveRuleDecisions, h]

theorem firstBlocking_append_deny (decisions : List RuleDecision) (reason : String) :
    ∃ found, firstBlocking? (decisions ++ [.deny reason]) = some found := by
  induction decisions with
  | nil => exact ⟨reason, rfl⟩
  | cons decision rest ih =>
      cases decision with
      | deny found => exact ⟨found, rfl⟩
      | invalid found => exact ⟨found, rfl⟩
      | allow => simpa [firstBlocking?] using ih
      | guard target text => simpa [firstBlocking?] using ih

theorem adding_deny_cannot_allow (decisions : List RuleDecision) (reason : String) :
    resolveRuleDecisions (decisions ++ [.deny reason]) ≠
      .event .benign "explicit policy allow" := by
  obtain ⟨found, h⟩ := firstBlocking_append_deny decisions reason
  rw [blocking_decision_dominates h]
  intro contradiction
  cases contradiction

theorem guardDecisions_append_guard (decisions : List RuleDecision)
    (target : TargetHash) (text : String) :
    guardDecisions (decisions ++ [.guard target text]) =
      guardDecisions decisions ++ [(target, text)] := by
  induction decisions with
  | nil => rfl
  | cons decision rest ih =>
      cases decision <;> simp [guardDecisions]

theorem adding_guard_cannot_explicitly_allow (decisions : List RuleDecision)
    (target : TargetHash) (text : String) :
    resolveRuleDecisions (decisions ++ [.guard target text]) ≠
      .event .benign "explicit policy allow" := by
  unfold resolveRuleDecisions
  split
  · intro contradiction; cases contradiction
  · rw [guardDecisions_append_guard]
    cases hguards : guardDecisions decisions with
    | nil => simp [sameGuardTarget]
    | cons first rest =>
        simp only [List.cons_append]
        split <;> intro contradiction <;> cases contradiction

theorem ambiguous_guard_targets_block (a b : TargetHash) (aText bText : String)
    (hne : (b == a) = false) :
    resolveRuleDecisions [.guard a aText, .guard b bText] =
      .event .defaultDeny "ambiguous guard target" := by
  simp [resolveRuleDecisions, firstBlocking?, guardDecisions, sameGuardTarget, hne]

/-- The structural half of full-arguments binding. A changed canonical JSON
    serialization changes the target pre-image. Concluding unequal SHA-256
    digests additionally uses the named collision-resistance assumption A-CR. -/
theorem full_arguments_preimage_changes (left right : Json)
    (h : left.compress ≠ right.compress) :
    [left.compress] ≠ [right.compress] := by
  intro equality
  injection equality with equalCompress
  exact h equalCompress

end Seal
