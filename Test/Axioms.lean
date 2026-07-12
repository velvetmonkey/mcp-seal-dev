/- SPDX-License-Identifier: Apache-2.0 -/

import SealCore
import Seal.PolicyV2Theorems
import Seal.PolicyScan

#print axioms SealCore.default_deny_never_allowed
#print axioms SealCore.no_allow_guarded_without_matching_approval_in_state
#print axioms SealCore.approval_binds_to_target
#print axioms Seal.adding_deny_cannot_allow
#print axioms Seal.adding_guard_cannot_explicitly_allow
#print axioms Seal.ambiguous_guard_targets_block
#print axioms Seal.full_arguments_preimage_changes
#print axioms Seal.scan_pass_sound
#print axioms Seal.scan_pass_no_orphan_allow
#print axioms SealCore.consumed_approval_not_live
#print axioms SealCore.expired_not_live
#print axioms SealCore.fresh_approval_live

def main : IO UInt32 := pure 0
