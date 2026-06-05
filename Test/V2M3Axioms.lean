/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2

#print axioms SealV2.parseStringChars_preserves_canonical
#print axioms SealV2.parseNumber_returns_canonical
#print axioms SealV2.parseArrayFuel_returns_canonical
#print axioms SealV2.parseObjectFuel_returns_canonical
#print axioms SealV2.parse_returns_canonical
#print axioms SealV2.serialize_roundtrip_null
#print axioms SealV2.serialize_roundtrip_bool
#print axioms SealV2.serialize_roundtrip_number
#print axioms SealV2.serialize_roundtrip_string
#print axioms SealV2.serialize_roundtrip_array
#print axioms SealV2.serialize_roundtrip_object
#print axioms SealV2.canonical_roundtrip
#print axioms SealV2.serializeAst_deterministic
#print axioms SealV2.serialize_validCapability_roundtrip

def main : IO UInt32 := pure 0
