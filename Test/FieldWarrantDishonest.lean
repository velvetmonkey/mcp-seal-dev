/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2
import Test.V2ValidationFixtures
import Test.FieldWarrantCorpus

/-!
# Dishonest-control probe — the harness-of-the-harness

Permanent regression rebuild of the cold frisk's DISHONEST-A/B/C probes
(2026-07-23 frisk of `77380fe`, finding F-HARNESS-1). Each control is
deliberately dishonest; the exe PASSES iff the harness's defenses catch every
one of them — and iff DISHONEST-A still fools the OLD label-keyed join shape,
proving the probe reproduces the original hole rather than a strawman.

* **A** — genuinely forges `nonce`, labels itself `field := "keyId"`. Passes
  `profileMatches` (it IS a real signature red); must be killed by the derived
  adequacy check and excluded from the derived-keyed join.
* **A2** — same forgery, but also LIES about the mint preimage to make the
  derived diff say `keyId`. Must be killed by mint validity (`sig` does not
  verify over the invented preimage).
* **B** — a real `adapterGate` red (valid sig over its own envelope) labelled
  `.signature`. Killed by the profile (`flipSig = false`).
* **C** — forges `nonce` AND trips `adapterGate`, labelled `.signature`.
  Killed by the profile AND by adequacy (derived set not a singleton).
-/

open SealV2 SealV2.Effect Test.V2ValidationFixtures Test.FieldWarrant

namespace Test.FieldWarrantDishonest

def dishonestA : Control :=
  { name := "DISHONEST-A mislabeled: forges nonce, field=keyId"
    field := "keyId"
    e := { baseEnvelope with nonce := forgedNonce }, sig := sigBase
    st := baseState, med := mediator, reg := registry, reason := .signature }

def dishonestA2 : Control :=
  { dishonestA with
    name := "DISHONEST-A2 invented mint preimage: derived diff says keyId"
    mintedE := { baseEnvelope with nonce := forgedNonce, keyId := "mallory2" } }

def dishonestB : Control :=
  { name := "DISHONEST-B gate-masked: real adapterGate red labelled signature"
    field := "adapterType"
    e := { baseEnvelope with adapterType := "cli" }, sig := sigAdapterType
    st := baseState, med := mediator, reg := registry, reason := .signature }

def dishonestC : Control :=
  { name := "DISHONEST-C overdetermined: forge nonce AND trip adapterGate"
    field := "nonce"
    e := { baseEnvelope with nonce := forgedNonce, adapterType := "cli" }
    sig := sigBase
    st := baseState, med := mediator, reg := registry, reason := .signature }

/-- The PRE-REPAIR join shape: keyed on the unverified `c.field` string.
    Kept here ONLY to prove DISHONEST-A reproduces the original hole. -/
def oldJoinWitness (cs : List Control) (field : String) : Option Control :=
  cs.find? (fun c =>
    c.field == field && c.reason == Reason.signature && c.profileMatches)

/-- The repaired join shape, exactly as the mutation harness runs it:
    keyed on the DERIVED perturbation singleton + full adequacy. -/
def newJoinWitness (cs : List Control) (field : String) : Option Control :=
  cs.find? (fun c =>
    c.reason == Reason.signature && c.profileMatches &&
    c.sigAdequate && c.perturbedFields == [field])

def main : IO UInt32 := do
  let mut fails : Nat := 0
  let check (name : String) (expected : Bool) (got : Bool) : IO Bool := do
    let ok := got == expected
    IO.println s!"{if ok then "PASS" else "FAIL"}  {name}: expected {expected}, got {got}"
    pure ok

  IO.println "== PROBE VALIDITY (A must reproduce the ORIGINAL hole) =="
  -- A really is a genuine signature red — that is what made the hole a hole.
  if !(← check "A.profileMatches (genuine sig red)" true dishonestA.profileMatches) then
    fails := fails + 1
  -- Substitute A for the real keyId signature row: the old label-keyed join
  -- is fooled and credits keyId.
  let probeCorpus := dishonestA ::
    corpus.filter (fun c => !(c.field == "keyId" && c.reason == Reason.signature))
  match oldJoinWitness probeCorpus "keyId" with
  | some w =>
      IO.println s!"PASS  old label-keyed join FOOLED (as frisked): keyId credited to \"{w.name}\""
  | none =>
      fails := fails + 1
      IO.println "FAIL  old join NOT fooled — probe does not reproduce F-HARNESS-1"

  IO.println "\n== REPAIR (every dishonest control is CAUGHT) =="
  -- A: adequacy kills the mislabel (derived = [nonce], declared = keyId)...
  if !(← check "A.sigAdequate" false dishonestA.sigAdequate) then fails := fails + 1
  IO.println s!"      A derived perturbation = {dishonestA.perturbedFields} (declared keyId)"
  -- ...and the derived-keyed join no longer credits keyId.
  match newJoinWitness probeCorpus "keyId" with
  | some w =>
      fails := fails + 1
      IO.println s!"FAIL  derived-keyed join STILL fooled: keyId credited to \"{w.name}\""
  | none =>
      IO.println "PASS  derived-keyed join: keyId renders MISSING — A caught"
  -- A does not get to witness nonce either: its label lies, adequacy is dead.
  match newJoinWitness [dishonestA] "nonce" with
  | some _ =>
      fails := fails + 1
      IO.println "FAIL  A credited to nonce despite dead adequacy"
  | none =>
      IO.println "PASS  A witnesses NOTHING (label lie kills all credit)"
  -- A2: the invented preimage makes the derived diff say keyId, but the sig
  -- does not verify over it — mint validity kills it.
  if !(← check "A2.sigAdequate (mint validity)" false dishonestA2.sigAdequate) then
    fails := fails + 1
  IO.println s!"      A2 derived perturbation = {dishonestA2.perturbedFields} (mint invalid)"
  -- B: gate-masked — the inverse-profile discriminator, as frisked.
  if !(← check "B.profileMatches" false dishonestB.profileMatches) then fails := fails + 1
  if !(← check "C.profileMatches" false dishonestC.profileMatches) then fails := fails + 1
  -- C also fails adequacy independently: two fields moved at once.
  if !(← check "C.sigAdequate (non-singleton)" false dishonestC.sigAdequate) then
    fails := fails + 1
  IO.println s!"      C derived perturbation = {dishonestC.perturbedFields}"

  IO.println "\n== HONEST CORPUS UNHARMED (profile + adequacy + full join) =="
  for c in corpus do
    let ok := c.profileMatches && c.fieldAdequate
    if !ok then
      fails := fails + 1
      IO.println s!"FAIL  honest control now rejected: {c.name} (profile={c.profileMatches}, adequate={c.fieldAdequate})"
  for field in requiredSignatureFields do
    match newJoinWitness corpus field with
    | some _ => pure ()
    | none =>
        fails := fails + 1
        IO.println s!"FAIL  required field lost its witness under the repair: {field}"
  if fails == 0 then
    IO.println "PASS  all honest controls keep profile+adequacy; every required field still witnessed"

  IO.println s!"\ndishonest probe: {fails} failures"
  if fails == 0 then
    IO.println "HARNESS HARDENED: A, A2, B, C all caught; honest corpus intact."
  pure (if fails == 0 then 0 else 1)

end Test.FieldWarrantDishonest

def main : IO UInt32 := Test.FieldWarrantDishonest.main
