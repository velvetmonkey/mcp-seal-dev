/- SPDX-License-Identifier: Apache-2.0 -/

import SealCore
import Seal.PolicyV2Theorems
import Seal.PolicyBundle
import Seal.NumberGuardTheorems
import Seal.PolicyScan
import Seal.Scaffold
import Seal.GoldenPath
import Seal.SignedPolicy
import SealV2.TamperTheorems

#print axioms SealCore.default_deny_never_allowed
#print axioms SealCore.no_allow_guarded_without_matching_approval_in_state
#print axioms SealCore.approval_binds_to_target
#print axioms Seal.adding_deny_cannot_allow
#print axioms Seal.adding_guard_cannot_explicitly_allow
#print axioms Seal.ambiguous_guard_targets_block
#print axioms Seal.full_arguments_preimage_changes
#print axioms Seal.evalTargetParts_congr
#print axioms Seal.evalTargetParts_indep_of_unnamed_paths
#print axioms Seal.evaluateRule_target_congr
#print axioms Seal.p0_2_policy_target_ignores_unnamed
#print axioms Seal.JsonUtil.numberScanStep_worst_le_of_no_digit
#print axioms Seal.effectiveConsensus_isSome_iff
#print axioms Seal.effectiveLinear_isSome_iff
#print axioms Seal.effectiveTemporal_nil_of_disabled
#print axioms Seal.effectiveConvergence_ne_nil_iff
#print axioms Seal.effectiveBudget_ne_nil_iff
#print axioms Seal.scan_pass_sound
#print axioms Seal.scan_pass_no_orphan_allow
#print axioms SealCore.consumed_approval_not_live
#print axioms SealCore.expired_not_live
#print axioms SealCore.fresh_approval_live

-- Golden-path spec: scaffolder soundness
#print axioms Seal.scaffold_safety
#print axioms Seal.scaffold_safety_not_benign
#print axioms Seal.dangerous_annotation_guarded
#print axioms Seal.scaffoldMode_ne_deny
#print axioms Seal.scaffold_unknown_tool_default_deny
#print axioms Seal.scaffold_readonly_flows

-- Golden-path spec: shell reference cell
#print axioms Seal.shell_exec_requires_live_approval
#print axioms Seal.shell_rm_rf_requires_live_approval
#print axioms Seal.shell_rm_rf_blocks_on_fresh_state
#print axioms Seal.shell_rm_rf_allows_with_fresh_approval
#print axioms Seal.shell_read_flows

-- Golden-path spec: tamper ⇒ fail-closed
#print axioms Seal.tampered_policy_fail_closed
#print axioms Seal.tampered_policy_blocks
#print axioms SealV2.tampered_approvals_validate_none
#print axioms SealV2.tampered_approvals_deny
#print axioms SealV2.allow_implies_witness_signature_verified

def main : IO UInt32 := pure 0
