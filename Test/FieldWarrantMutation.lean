/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2
import Test.V2ValidationFixtures
import Test.FieldWarrantCorpus

/-!
# Field-warrant NEGATIVE-WITNESS harness (council requirement, 2026-07-23 01:56)

The mechanical form of the F1 tamper matrix. Instead of 14 hand edits, this
runs a reusable *negative witness* over the whole control corpus
(`Test.FieldWarrant.corpus`, the single source the SHOW suite also consumes):

1. **Drift guard** — re-derive each corpus row's real `effectStep` verdict and
   its reason's sub-assertions; if any row does not reproduce the SHOW suite's
   PASS, fail loudly. Ties the corpus to the shipped fixtures.
2. **Negative witness** — for each row, compute its sensitivity profile
   (flips-under-signature-mutant, gates-that-flip-it) and check it matches the
   declared reason (`Control.profileMatches`). A mismatch is a control passing
   for the wrong reason — the machine form of frisk F1.
3. **Claim-list join** — a HAND-AUTHORED list of every signed field that MUST
   have a profile-passing signature witness. Existence in the corpus is not
   adequacy: a required field with no passing witness renders LOUDLY (`MISSING`)
   and fails the run, rather than silently not appearing.
4. **Frisk reproduction** — run the same profile over the pre-F1 naive-forgery
   corpus and count how many pass for the wrong reason, recovering frisk F1's
   9-of-14 mechanically.
-/

open SealV2 SealV2.Effect Test.V2ValidationFixtures Test.FieldWarrant

namespace Test.FieldWarrantMutation

def gateName? : Reason → Option GateSel
  | .gate g => some g
  | _ => none

/-- Reproduce the SHOW suite's verdict for one corpus row from the real
    `effectStep` + `verifyEffect`, matching the reason's sub-assertions. The
    drift guard: if the shipped fixtures change under the corpus, this fails. -/
def reproducesSuiteVerdict (c : Control) : Bool :=
  let blocked := match effectStep authority c.reg c.med c.e c.sig c.st with
    | .Allow _ => false | .Block => true
  let verified := (verifyEffect authority c.reg c.e c.sig).isSome
  let allGatesPass := allGates.all (fun g => gateValue g c.med c.st c.e)
  match c.reason with
  | .signature => blocked && !verified && allGatesPass
  | .gate g => blocked && verified && (gateValue g c.med c.st c.e == false)
  | .registry => blocked && !verified

/-- The HAND-AUTHORED adequacy claim: every signed field that must carry a
    step-level signature witness. Joined against the generated corpus below;
    a field here with no profile-passing `.signature` control renders LOUDLY. -/
def requiredSignatureFields : List String :=
  ["keyId", "nonce", "issuedAt", "expiresAt", "line", "adapterType",
   "adapterVersion", "policyVersion", "effectPresence"]

/-- Signed material with NO step-level signature witness — the NAMED GAPS, each
    with its REASON. Witnessed instead by MESSAGE DISTINCTNESS (recomputed
    below) plus the kernel injectivity proofs. Listed EXPLICITLY so the gap
    renders rather than hides.

    * `authority` — not an `EffectEnvelope` field (config trust root threaded
      separately); no per-field step forgery to construct.
    * `effect.resource/action/args` — `effectGate` pins a present claim to
      `deriveEffect` of the UNCHANGED signed line, so no verifier config makes
      the gate pass while only a sub-field's signature discriminates.
    * `session` — coupled into the decision layer's SIGNED approval
      (`approvalLiveFor` re-verifies the approval, which covers session), so no
      state alignment isolates the envelope signature at the step without
      minting a fresh approval fixture. -/
def encodingOnlyFields : List (String × String) :=
  [ ("authority", "not an envelope field")
  , ("effect.resource", "effectGate pins claim to deriveEffect(line)")
  , ("effect.action", "effectGate pins claim to deriveEffect(line)")
  , ("effect.args", "effectGate pins claim to deriveEffect(line)")
  , ("session", "coupled to decide's signed approval") ]

/-- MESSAGE DISTINCTNESS witnesses for the encoding-only fields, recomputed
    here so the claim-list is self-contained. Each pair differs ONLY in the
    named field and must produce different `effectMessage` bytes. -/
def encodingWitness (field : String) : Option Bool :=
  let m := effectMessage authority baseEnvelope
  let auth2 := ByteArray.mk (Array.range 32 |>.map fun i => UInt8.ofNat (0xb0 + i))
  match field with
  | "authority" => some (m != effectMessage auth2 baseEnvelope)
  | "effect.resource" => some
      (m != effectMessage authority { baseEnvelope with effect := some { baseClaim with resource := "db.executex" } })
  | "effect.action" => some
      (m != effectMessage authority { baseEnvelope with effect := some { baseClaim with action := "writex" } })
  | "effect.args" => some
      (m != effectMessage authority { baseEnvelope with effect := some { baseClaim with args := "{}" } })
  | "session" => some
      (m != effectMessage authority { baseEnvelope with session := "session-1x" })
  | _ => none

def main : IO UInt32 := do
  let mut fails : Nat := 0

  IO.println "== DRIFT GUARD (corpus reproduces the SHOW-suite verdict) =="
  for c in corpus do
    let ok := reproducesSuiteVerdict c
    if !ok then fails := fails + 1
    IO.println s!"{if ok then "PASS" else "FAIL"}  [{c.reason.describe}] {c.name}"

  IO.println "\n== NEGATIVE WITNESS (sensitivity profile matches declared reason) =="
  for c in corpus do
    let ok := c.profileMatches
    if !ok then fails := fails + 1
    let sens := (c.sensGates.map (·.name))
    IO.println s!"{if ok then "PASS" else "FAIL"}  [{c.reason.describe}] {c.name}: flipSig={c.flipSig} sensGates={sens}"

  IO.println "\n== CLAIM-LIST JOIN (every required field has a passing signature witness) =="
  for field in requiredSignatureFields do
    let witnesses := corpus.filter (fun c =>
      c.field == field && c.reason == Reason.signature && c.profileMatches)
    match witnesses with
    | [] =>
        fails := fails + 1
        IO.println s!"FAIL  MISSING SIGNATURE WITNESS: {field}"
    | w :: _ =>
        IO.println s!"PASS  {field}: witnessed by \"{w.name}\""

  IO.println "\n== NAMED GAPS (no step-level sig control — MESSAGE DISTINCTNESS + kernel proofs) =="
  for (field, why) in encodingOnlyFields do
    match encodingWitness field with
    | some true => IO.println s!"PASS  {field}: named gap ({why}); bytes distinct"
    | some false =>
        fails := fails + 1
        IO.println s!"FAIL  {field}: MESSAGE DISTINCTNESS witness collapsed"
    | none =>
        fails := fails + 1
        IO.println s!"FAIL  {field}: no encoding witness defined"

  IO.println "\n== FRISK REPRODUCTION (pre-F1 naive forgeries, all CLAIM .signature) =="
  let mut wrongReason : Nat := 0
  for c in naiveCorpus do
    let ok := c.profileMatches
    if !ok then wrongReason := wrongReason + 1
    let why := if ok then "measures signature"
      else if c.flipSig then "sig-sensitive but gate-coupled"
      else s!"NOT sig-sensitive — masked by {(c.gateFalseSet.map (·.name))}/registry"
    IO.println s!"{if ok then "honest" else "WRONG-REASON"}  {c.name}: {why}"
  IO.println s!"frisk reproduction: {wrongReason} of {naiveCorpus.length} naive controls pass for the WRONG reason"
  let pct := wrongReason * 100 / naiveCorpus.length
  IO.println s!"  = {pct}% (frisk hand-analysis said 9/14; council threshold was ≥20% more than honest)"

  IO.println s!"\nnegative-witness harness: {fails} failures across drift+profile+claim-list+gap"
  if fails == 0 then
    IO.println "REPAIRED CORPUS: 0 controls pass for the wrong reason; every required field witnessed."
  pure (if fails == 0 then 0 else 1)

end Test.FieldWarrantMutation

def main : IO UInt32 := Test.FieldWarrantMutation.main
