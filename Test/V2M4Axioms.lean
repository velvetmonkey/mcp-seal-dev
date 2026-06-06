/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2

/-- info: 'SealV2.canonical_roundtrip' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms SealV2.canonical_roundtrip

/-- info: 'SealV2.serialize_validCapability_roundtrip' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms SealV2.serialize_validCapability_roundtrip

/-- info: 'SealV2.decide_emit_unique' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms SealV2.decide_emit_unique

/-- info: 'SealV2.non_bypass' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms SealV2.non_bypass

/-- info: 'SealV2.default_deny' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms SealV2.default_deny

def main : IO UInt32 := pure 0
