/- SPDX-License-Identifier: Apache-2.0 -/

import SealCore

#print axioms SealCore.default_deny_never_allowed
#print axioms SealCore.no_allow_guarded_without_matching_approval_in_state
#print axioms SealCore.approval_binds_to_target
#print axioms SealCore.consumed_approval_not_live
#print axioms SealCore.expired_not_live
#print axioms SealCore.fresh_approval_live

def main : IO UInt32 := pure 0
