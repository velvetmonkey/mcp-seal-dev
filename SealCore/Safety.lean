/- SPDX-License-Identifier: Apache-2.0 -/

import SealCore.Automaton
import Std.Data.HashMap.Lemmas

namespace SealCore

theorem default_deny_never_allowed (ttl : Nat) (s : State) :
    (step ttl s .defaultDeny).1 = .block := by
  rfl

theorem benign_preserves_approved (ttl : Nat) (s : State) :
    (step ttl s .benign).2.approved = s.approved := by
  rfl

theorem guarded_allow_iff_live (ttl : Nat) (s : State) (target : Hash) :
    (step ttl s (.guarded target)).1 = .allow ↔ live s target = true := by
  unfold step
  by_cases h : live s target
  · simp [h]
  · simp [h]

theorem no_allow_guarded_without_matching_approval_in_state
    (ttl : Nat) (s : State) (target : Hash) :
    (step ttl s (.guarded target)).1 = .allow → live s target = true := by
  intro h
  exact (guarded_allow_iff_live ttl s target).1 h

theorem approval_binds_to_target
    (ttl : Nat) (approvedTarget guardedTarget : Hash)
    (hneq : approvedTarget ≠ guardedTarget) :
    live { approved := (∅ : Std.HashMap Hash Nat).insert approvedTarget ttl } guardedTarget = false := by
  unfold live
  rw [Std.HashMap.getElem?_insert]
  have hbeq : (approvedTarget == guardedTarget) = false := by
    exact beq_false_of_ne hneq
  simp [hbeq]

theorem confused_deputy_blocks_from_single_other_approval
    (ttl : Nat) (approvedTarget guardedTarget : Hash)
    (hneq : approvedTarget ≠ guardedTarget) :
    (step ttl { approved := (∅ : Std.HashMap Hash Nat).insert approvedTarget ttl }
      (.guarded guardedTarget)).1 = .block := by
  have hLive := approval_binds_to_target ttl approvedTarget guardedTarget hneq
  unfold step
  simp [hLive]

theorem consumed_approval_not_live (ttl : Nat) (s : State) (target : Hash) :
    (step ttl (step ttl s (.guarded target)).2 (.guarded target)).1 = .allow →
      (step ttl s (.guarded target)).1 = .block := by
  intro h
  unfold step at h ⊢
  by_cases hlive : live s target
  · simp [hlive] at h
    unfold live at h
    rw [Std.HashMap.getElem?_erase_self] at h
    contradiction
  · simp [hlive]

end SealCore
