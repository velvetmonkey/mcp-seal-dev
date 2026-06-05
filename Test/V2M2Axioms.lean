/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2

#print axioms SealV2.validate_none_no_witness_result
#print axioms SealV2.valid_capability_has_unused_approval
#print axioms SealV2.valid_capability_has_unexpired_approval
#print axioms SealV2.valid_capability_has_signature_verified
#print axioms SealV2.valid_capability_target_bound
#print axioms SealV2.valid_capability_session_bound

def main : IO UInt32 := pure 0
