/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.Validation

namespace SealV2

theorem validate_none_no_witness_result (ast : AST) (state : ApprovalState) :
    validate ast state = none → ¬ ∃ checked witness, validate ast state = some ⟨checked, witness⟩ := by
  intro h hSome
  rcases hSome with ⟨checked, witness, hChecked⟩
  rw [h] at hChecked
  contradiction

theorem valid_capability_has_unused_approval {ast : AST} {state : ApprovalState}
    (witness : ValidApproval ast state) :
    witness.approval.consumed = false :=
  witness.approval_unused

theorem valid_capability_has_unexpired_approval {ast : AST} {state : ApprovalState}
    (witness : ValidApproval ast state) :
    state.now <= witness.approval.expiresAt :=
  witness.approval_unexpired

theorem valid_capability_has_signature_verified {ast : AST} {state : ApprovalState}
    (witness : ValidApproval ast state) :
    SignatureVerified state.publicKey witness.approval :=
  witness.signature_verified

theorem valid_capability_target_bound {ast : AST} {state : ApprovalState}
    (witness : ValidApproval ast state) :
    (witness.approval.target == witness.target) = true :=
  witness.approval_target_matches

theorem valid_capability_session_bound {ast : AST} {state : ApprovalState}
    (witness : ValidApproval ast state) :
    witness.approval.session = state.session :=
  witness.approval_session_matches

theorem signed_parse_canonical (raw : RawBytes) (ast : {ast // IsCanonical ast}) :
    signedParse raw = some ast → raw = serializeAst ast := by
  unfold signedParse
  intro h
  split at h
  · exact absurd h (by simp)
  · rename_i a _
    split at h
    · rename_i hc
      split at h
      · rename_i hbeq
        have := Option.some.inj h
        rw [← this]
        exact eq_of_beq hbeq
      · exact absurd h (by simp)
    · exact absurd h (by simp)

end SealV2
