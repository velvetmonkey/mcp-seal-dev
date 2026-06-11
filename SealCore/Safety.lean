/- SPDX-License-Identifier: Apache-2.0 -/

import SealCore.Automaton
import Std.Data.HashMap.Lemmas

namespace SealCore

theorem default_deny_never_allowed (now ttlMs : Nat) (s : State) :
    (step now ttlMs s .defaultDeny).1 = .block := by
  rfl

theorem benign_preserves_approved (now ttlMs : Nat) (s : State) :
    (step now ttlMs s .benign).2.approved = s.approved := by
  rfl

theorem guarded_allow_iff_live (now ttlMs : Nat) (s : State) (target : Hash) :
    (step now ttlMs s (.guarded target)).1 = .allow ↔ live s target now = true := by
  unfold step
  by_cases h : live s target now
  · simp [h]
  · simp [h]

theorem no_allow_guarded_without_matching_approval_in_state
    (now ttlMs : Nat) (s : State) (target : Hash) :
    (step now ttlMs s (.guarded target)).1 = .allow → live s target now = true := by
  intro h
  exact (guarded_allow_iff_live now ttlMs s target).1 h

theorem approval_binds_to_target
    (now deadline : Nat) (approvedTarget guardedTarget : Hash)
    (hneq : approvedTarget ≠ guardedTarget) :
    live { approved := (∅ : Std.HashMap Hash Nat).insert approvedTarget deadline } guardedTarget now = false := by
  unfold live
  rw [Std.HashMap.getElem?_insert]
  have hbeq : (approvedTarget == guardedTarget) = false := by
    exact beq_false_of_ne hneq
  simp [hbeq]

theorem confused_deputy_blocks_from_single_other_approval
    (now ttlMs deadline : Nat) (approvedTarget guardedTarget : Hash)
    (hneq : approvedTarget ≠ guardedTarget) :
    (step now ttlMs { approved := (∅ : Std.HashMap Hash Nat).insert approvedTarget deadline }
      (.guarded guardedTarget)).1 = .block := by
  have hLive := approval_binds_to_target now deadline approvedTarget guardedTarget hneq
  unfold step
  simp [hLive]

theorem consumed_approval_not_live (now ttlMs : Nat) (s : State) (target : Hash) :
    (step now ttlMs (step now ttlMs s (.guarded target)).2 (.guarded target)).1 = .allow →
      (step now ttlMs s (.guarded target)).1 = .block := by
  intro h
  unfold step at h ⊢
  by_cases hlive : live s target now
  · simp [hlive] at h
    unfold live at h
    rw [Std.HashMap.getElem?_erase_self] at h
    contradiction
  · simp [hlive]

/-- An approval whose deadline is at or before `now` is not live: the gate
    blocks once a ticket has expired. -/
theorem expired_not_live (s : State) (target : Hash) (now deadline : Nat)
    (hfound : s.approved[target]? = some deadline) (hexp : deadline ≤ now) :
    live s target now = false := by
  unfold live
  rw [hfound]
  simp only [decide_eq_false_iff_not, Nat.not_lt]
  omega

/-- A freshly minted approval (positive TTL) is live at its mint time: the gate
    admits the first matching call. -/
theorem fresh_approval_live (now ttlMs : Nat) (s : State) (target : Hash)
    (h : 0 < ttlMs) :
    live (step now ttlMs s (.approval target)).2 target now = true := by
  unfold step live
  rw [Std.HashMap.getElem?_insert_self]
  simp only [decide_eq_true_eq]
  omega

end SealCore
