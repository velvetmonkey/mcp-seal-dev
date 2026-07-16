/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Data.Json
import Seal.Policy
import Seal.JsonUtil

/-!
# The 7-kernel policy bundle — the policy-v2 DX surface

The live gate is seven proven AND-composed kernels (S/T/C/V/K/L/B), but until
this module the verified policy-v2 vocabulary (`Seal.Policy`,
`parsePolicyJson`) expressed only Safety; the six other kernel sections were
parsed by ad-hoc, theorem-free parsers on the host side. This module makes the
whole 7-kernel configuration part of the verified policy language:

* one declarative structure per kernel section, mirroring the wire schema the
  host already documents (`seal-host/CONFIG.md`) — wire key names are frozen
  so every existing signed payload keeps parsing;
* a uniform `enabled` flag per optional section (default `true`;
  `enabled := false` collapses the section to absent via the `effective*`
  functions BEFORE any host mapping, so "disabled" and "absent" are
  indistinguishable downstream). Calibration is the deliberate exception: its
  `enabled` default stays `false` (EXPERIMENTAL, opt-in twice) and a present
  `enabled := false` section stays *present-but-disabled* — a distinct,
  theorem-pinned state on the host side (`calibration_registered_iff`);
* hard errors on unknown keys at the payload, section, and entry levels
  (`Seal.JsonUtil.expectObjKeys`) — parser-boundary discipline: a typo such
  as `temporral` must not silently leave a kernel off.

Safety (S) and Temporal (T) are registered unconditionally by the host
(`safety_always_registered` / `temporal_always_registered`); they are
configurable but not de-registrable, so `safety` carries no `enabled` key and
a disabled/absent `temporal` section merely leaves T vacuous (empty policy
list), never unregistered.

The host wires `PolicyBundle` into the proven kernel registry
(`seal-host/Host/Config.lean` `ofBundle` and the `bundle_*_registered_iff`
tripwires in `FfiSpec.lean`).
-/

namespace Seal

open Lean
open Seal.JsonUtil

/-- One temporal LTL safety rule: after any `trigger` tool executes, every
    `forbidden` tool is denied for the rest of the session (`no_after`). -/
structure TemporalRule where
  name : String
  trigger : List String
  forbidden : List String
  deriving Repr, BEq

structure TemporalSection where
  enabled : Bool := true
  policies : List TemporalRule
  deriving Repr, BEq

structure ConsensusSection where
  enabled : Bool := true
  roster : List Nat
  votesFile : String
  highStakes : List String
  deriving Repr, BEq

/-- A replicated-store tool gated by the Convergence kernel; `opArg` is the
    dotted argument path resolving the CRDT operation name. -/
structure ConvergentTool where
  tool : String
  opArg : List String
  deriving Repr, BEq

structure ConvergenceSection where
  enabled : Bool := true
  tools : List ConvergentTool
  deriving Repr, BEq

/-- EXPERIMENTAL. `enabled` defaults to `false`: calibration must be opted
    into twice (present AND enabled), preserving the host's existing
    double-gate semantics. -/
structure CalibrationSection where
  enabled : Bool := false
  deltaNum : Nat
  deltaDen : Nat
  minSamples : Nat
  recordsFile : String
  gatedTools : List String
  deriving Repr, BEq

structure LinearGrantTool where
  tool : String
  capArg : List String
  deriving Repr, BEq

structure LinearSection where
  enabled : Bool := true
  grantsFile : String
  tools : List LinearGrantTool
  deriving Repr, BEq

structure BudgetRule where
  name : String
  cap : Nat
  tools : List String
  costArg : Option (List String) := none
  deriving Repr, BEq

structure BudgetSection where
  enabled : Bool := true
  budgets : List BudgetRule
  deriving Repr, BEq

/-- The 7-kernel policy bundle: the policy-v2 DX surface. Safety is the
    existing verified `Policy`; the six kernel sections are declarative and
    optional. -/
structure PolicyBundle where
  epoch : Nat
  safety : Policy
  temporal : Option TemporalSection := none
  consensus : Option ConsensusSection := none
  convergence : Option ConvergenceSection := none
  calibration : Option CalibrationSection := none
  linear : Option LinearSection := none
  budget : Option BudgetSection := none
  deriving Repr

/-! ## Effective sections

`enabled := false` collapses to absent BEFORE any host mapping. Calibration is
deliberately NOT collapsed: present-but-disabled is a distinct state the host
pins with its own theorem (`calibration_registered_iff` double gate). -/

def PolicyBundle.effectiveTemporal (b : PolicyBundle) : List TemporalRule :=
  match b.temporal with
  | some s => if s.enabled then s.policies else []
  | none => []

def PolicyBundle.effectiveConsensus (b : PolicyBundle) : Option ConsensusSection :=
  match b.consensus with
  | some s => if s.enabled then some s else none
  | none => none

def PolicyBundle.effectiveConvergence (b : PolicyBundle) : List ConvergentTool :=
  match b.convergence with
  | some s => if s.enabled then s.tools else []
  | none => []

def PolicyBundle.effectiveLinear (b : PolicyBundle) : Option LinearSection :=
  match b.linear with
  | some s => if s.enabled then some s else none
  | none => none

def PolicyBundle.effectiveBudget (b : PolicyBundle) : List BudgetRule :=
  match b.budget with
  | some s => if s.enabled then s.budgets else []
  | none => []

/-! ## Enablement lemmas

Executable-twin statements for the host-side registration tripwires: the
`effective*` view is exactly "section present and enabled". -/

theorem effectiveConsensus_isSome_iff (b : PolicyBundle) :
    b.effectiveConsensus.isSome ↔ ∃ s, b.consensus = some s ∧ s.enabled = true := by
  cases h : b.consensus with
  | none => simp [PolicyBundle.effectiveConsensus, h]
  | some s =>
      cases he : s.enabled <;>
        simp [PolicyBundle.effectiveConsensus, h, he]

theorem effectiveLinear_isSome_iff (b : PolicyBundle) :
    b.effectiveLinear.isSome ↔ ∃ s, b.linear = some s ∧ s.enabled = true := by
  cases h : b.linear with
  | none => simp [PolicyBundle.effectiveLinear, h]
  | some s =>
      cases he : s.enabled <;>
        simp [PolicyBundle.effectiveLinear, h, he]

theorem effectiveTemporal_nil_of_disabled (b : PolicyBundle) (s : TemporalSection)
    (h : b.temporal = some s) (hd : s.enabled = false) :
    b.effectiveTemporal = [] := by
  simp [PolicyBundle.effectiveTemporal, h, hd]

theorem effectiveConvergence_ne_nil_iff (b : PolicyBundle) :
    b.effectiveConvergence ≠ [] ↔
      ∃ s, b.convergence = some s ∧ s.enabled = true ∧ s.tools ≠ [] := by
  cases h : b.convergence with
  | none => simp [PolicyBundle.effectiveConvergence, h]
  | some s =>
      cases he : s.enabled <;>
        simp [PolicyBundle.effectiveConvergence, h, he]

theorem effectiveBudget_ne_nil_iff (b : PolicyBundle) :
    b.effectiveBudget ≠ [] ↔
      ∃ s, b.budget = some s ∧ s.enabled = true ∧ s.budgets ≠ [] := by
  cases h : b.budget with
  | none => simp [PolicyBundle.effectiveBudget, h]
  | some s =>
      cases he : s.enabled <;>
        simp [PolicyBundle.effectiveBudget, h, he]

/-! ## Parser -/

private def parseStringList (json : Json) : Except String (List String) := do
  let arr ← json.getArr?
  arr.toList.mapM (fun j => j.getStr?)

/-- Optional `enabled` flag with a per-section default. -/
private def parseEnabled (json : Json) (default : Bool) : Except String Bool := do
  match ← getObjValOpt json "enabled" with
  | some v => v.getBool?
  | none => pure default

private def parseTemporalRule (json : Json) : Except String TemporalRule := do
  expectObjKeys json ["name", "type", "trigger", "forbidden"] "temporal policy"
  let name ← getObjString json "name"
  let kind ← getObjString json "type"
  if kind != "no_after" then
    throw s!"unsupported temporal policy type: {kind}"
  let trigger ← parseStringList (← json.getObjVal? "trigger")
  let forbidden ← parseStringList (← json.getObjVal? "forbidden")
  pure { name, trigger, forbidden }

def parseTemporalSection (json : Json) : Except String TemporalSection := do
  expectObjKeys json ["enabled", "policies"] "temporal section"
  let enabled ← parseEnabled json true
  let policiesJson ← (← json.getObjVal? "policies").getArr?
  let policies ← policiesJson.toList.mapM parseTemporalRule
  pure { enabled, policies }

def parseConsensusSection (json : Json) : Except String ConsensusSection := do
  expectObjKeys json ["enabled", "roster", "votes_file", "high_stakes"]
    "consensus section"
  let enabled ← parseEnabled json true
  let rosterJson ← (← json.getObjVal? "roster").getArr?
  let roster ← rosterJson.toList.mapM (fun j => j.getNat?)
  let votesFile ← getObjString json "votes_file"
  let highStakes ← parseStringList (← json.getObjVal? "high_stakes")
  pure { enabled, roster, votesFile, highStakes }

def parseConvergenceSection (json : Json) : Except String ConvergenceSection := do
  expectObjKeys json ["enabled", "tools"] "convergence section"
  let enabled ← parseEnabled json true
  let toolsJson ← (← json.getObjVal? "tools").getArr?
  let tools ← toolsJson.toList.mapM fun j => do
    expectObjKeys j ["tool", "op_arg"] "convergence tool"
    let tool ← getObjString j "tool"
    let opArg ← getObjString j "op_arg"
    pure { tool, opArg := splitPath opArg : ConvergentTool }
  pure { enabled, tools }

def parseCalibrationSection (json : Json) : Except String CalibrationSection := do
  expectObjKeys json
    ["enabled", "delta_num", "delta_den", "min_samples", "records_file",
     "gated_tools"] "calibration section"
  let enabled ← parseEnabled json false
  let deltaNum ← (← json.getObjVal? "delta_num").getNat?
  let deltaDen ← (← json.getObjVal? "delta_den").getNat?
  if deltaNum == 0 || deltaDen ≤ deltaNum then
    throw "calibration delta must satisfy 0 < delta < 1"
  let minSamples ← (← json.getObjVal? "min_samples").getNat?
  let recordsFile ← getObjString json "records_file"
  let gatedTools ← parseStringList (← json.getObjVal? "gated_tools")
  pure { enabled, deltaNum, deltaDen, minSamples, recordsFile, gatedTools }

def parseLinearSection (json : Json) : Except String LinearSection := do
  expectObjKeys json ["enabled", "grants_file", "tools"] "linear section"
  let enabled ← parseEnabled json true
  let grantsFile ← getObjString json "grants_file"
  let toolsJson ← (← json.getObjVal? "tools").getArr?
  let tools ← toolsJson.toList.mapM fun j => do
    expectObjKeys j ["tool", "cap_arg"] "linear tool"
    let tool ← getObjString j "tool"
    let capArg ← getObjString j "cap_arg"
    pure { tool, capArg := splitPath capArg : LinearGrantTool }
  pure { enabled, grantsFile, tools }

def parseBudgetSection (json : Json) : Except String BudgetSection := do
  expectObjKeys json ["enabled", "budgets"] "budget section"
  let enabled ← parseEnabled json true
  let budgetsJson ← (← json.getObjVal? "budgets").getArr?
  let budgets ← budgetsJson.toList.mapM fun j => do
    expectObjKeys j ["name", "cap", "tools", "cost_arg"] "budget spec"
    let name ← getObjString j "name"
    let cap ← (← j.getObjVal? "cap").getNat?
    let tools ← parseStringList (← j.getObjVal? "tools")
    let costArg ← match ← getObjValOpt j "cost_arg" with
      | some v => pure (some (splitPath (← v.getStr?)))
      | none => pure none
    pure { name, cap, tools, costArg : BudgetRule }
  pure { enabled, budgets }

private def parseOptSection {α : Type} (json : Json) (key : String)
    (parse : Json → Except String α) : Except String (Option α) := do
  match ← getObjValOpt json key with
  | none => pure none
  | some section_ => pure (some (← parse section_))

/-- The keys a bundle payload may carry at the top level. -/
def bundleTopLevelKeys : List String :=
  ["epoch", "server", "safety", "temporal", "consensus", "convergence",
   "calibration", "linear", "budget"]

/-- The shallow keys of the `safety` section. The interior of `tools` rules
    stays the existing `parsePolicyJson` boundary (its strictness is the
    authoring signer's job); `approval` additionally admits `replay_store`,
    the documented host-layer replay-store pointer whose interior the host
    consumes. -/
def safetyShallowKeys : List String := ["approval", "tools", "server"]

def approvalKeys : List String := ["control_file", "ttl_seconds", "replay_store"]

/-- Top-level bundle parser: the whole 7-kernel policy-v2 config surface.

    Strict keys at the payload, section, and entry levels. Safety's interior
    is parsed by the existing verified `parsePolicyJson`; a top-level `server`
    is copied into the safety policy when the safety section carries none, and
    a conflict between the two is a hard error (identical semantics to the
    host enrichment this parser replaces). -/
def parsePolicyBundle (json : Json) : Except String PolicyBundle := do
  expectObjKeys json bundleTopLevelKeys "policy bundle"
  let epoch ← (← json.getObjVal? "epoch").getNat?
  if epoch == 0 then
    throw "config epoch must be ≥ 1"
  let safetyJson ← json.getObjVal? "safety"
  expectObjKeys safetyJson safetyShallowKeys "safety section"
  expectObjKeys (← safetyJson.getObjVal? "approval") approvalKeys "safety approval"
  let outerServer ← match ← getObjValOpt json "server" with
    | some value => pure (some (← value.getStr?))
    | none => pure none
  let innerServer ← match ← getObjValOpt safetyJson "server" with
    | some value => pure (some (← value.getStr?))
    | none => pure none
  if outerServer.isSome && innerServer.isSome && outerServer != innerServer then
    throw "server identity conflicts between trusted config and safety policy"
  let safetyJson := match outerServer, innerServer with
    | some server, none => safetyJson.setObjVal! "server" (.str server)
    | _, _ => safetyJson
  let safety ← parsePolicyJson safetyJson
  let temporal ← parseOptSection json "temporal" parseTemporalSection
  let consensus ← parseOptSection json "consensus" parseConsensusSection
  let convergence ← parseOptSection json "convergence" parseConvergenceSection
  let calibration ← parseOptSection json "calibration" parseCalibrationSection
  let linear ← parseOptSection json "linear" parseLinearSection
  let budget ← parseOptSection json "budget" parseBudgetSection
  pure { epoch, safety, temporal, consensus, convergence, calibration, linear,
         budget }

/-! ## Axiom pins -/

/-- info: 'Seal.effectiveConsensus_isSome_iff' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms effectiveConsensus_isSome_iff

/-- info: 'Seal.effectiveLinear_isSome_iff' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms effectiveLinear_isSome_iff

/-- info: 'Seal.effectiveTemporal_nil_of_disabled' depends on axioms: [propext] -/
#guard_msgs in
#print axioms effectiveTemporal_nil_of_disabled

/-- info: 'Seal.effectiveConvergence_ne_nil_iff' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms effectiveConvergence_ne_nil_iff

/-- info: 'Seal.effectiveBudget_ne_nil_iff' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms effectiveBudget_ne_nil_iff

end Seal
