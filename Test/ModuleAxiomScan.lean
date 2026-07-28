/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Environment
import Lean.Util.CollectAxioms
import Lean.Util.Path
import Seal
import SealCore
import SealV2.Crypto
import SealV2.SerializationContainerLemmas
import SealV2.SerializationLemmas

/-!
Module-wide axiom gate for the 24 modules measured clean at commit `186f8ee`.

`Ffi` is deliberately excluded pending Ben's ruling on its six exported
wrappers that carry `lcProof`.  See the complete characterization in
`/home/monkey/.mega-monkey/lane-reports/lcproof-report.md`.
-/

namespace Test.ModuleAxiomScan

open Lean

private def baseline : Array Name :=
  #[`propext, `Classical.choice, `Quot.sound]

private def collectAxiomsIn (env : Environment) (decl : Name) : Array Name :=
  let (_, state) := ((CollectAxioms.collect decl).run env).run {}
  state.axioms.qsort Name.lt

private def measuredModuleNames : Array Name := #[
  `Seal.Block,
  `Seal.Channel,
  `Seal.Classify,
  `Seal.Hash,
  `Seal.JsonUtil,
  `Seal.Main,
  `Seal.Policy,
  `Seal.PolicyLegacy,
  `Seal.PolicyWire,
  `SealCore.Automaton,
  `SealCore.Event,
  `SealCore.Sha256,
  `SealV2.Canonical,
  `SealV2.Crypto,
  `SealV2.Decide,
  `SealV2.EnvelopeCompleteness,
  `SealV2.Escape,
  `SealV2.Parser,
  `SealV2.Serialization,
  `SealV2.SerializationContainerLemmas,
  `SealCore,
  `Seal,
  `SealV2
]

private def expectedProductionModuleCount : Nat := 50

private def productionModuleCount : IO Nat := do
  let mut count := 0
  for root in #["Seal", "SealCore", "SealV2"] do
    let paths ← (System.FilePath.mk root).walkDir
    count := count + (paths.filter fun path => path.extension == some "lean").size
  for root in #["Seal.lean", "SealCore.lean", "SealV2.lean", "Ffi.lean"] do
    if ← (System.FilePath.mk root).pathExists then
      count := count + 1
  pure count

private def checkModuleDrift : IO Unit := do
  let actual ← productionModuleCount
  IO.println s!"PRODUCTION_MODULES_ON_DISK\t{actual}"
  IO.println s!"PRODUCTION_MODULES_EXPECTED\t{expectedProductionModuleCount}"
  unless actual == expectedProductionModuleCount do
    throw <| IO.userError
      s!"module scan: production module count drifted from {expectedProductionModuleCount} to {actual}; review the measured scan scope"
  IO.println "MODULE_DRIFT_GUARD\tPASS"

private def constantKind : ConstantInfo → String
  | .axiomInfo _  => "axiom"
  | .defnInfo _   => "definition"
  | .thmInfo _    => "theorem"
  | .opaqueInfo _ => "opaque"
  | .quotInfo _   => "quotient"
  | .inductInfo _ => "inductive"
  | .ctorInfo _   => "constructor"
  | .recInfo _    => "recursor"

private def bumpDistribution
    (distribution : List (List Name × Nat)) (footprint : List Name) :
    List (List Name × Nat) :=
  match distribution with
  | [] => [(footprint, 1)]
  | (seen, count) :: rest =>
      if seen == footprint then
        (seen, count + 1) :: rest
      else
        (seen, count) :: bumpDistribution rest footprint

def scanModule (env : Environment) (moduleName : Name) : IO Nat := do
  let some moduleIdx := env.getModuleIdx? moduleName
    | throw <| IO.userError s!"module scan: module index not found for {moduleName}"
  let some moduleData := env.header.moduleData[moduleIdx]?
    | throw <| IO.userError s!"module scan: module data not found for {moduleName}"
  let declarations :=
    env.constants.fold (init := #[]) (fun names name _ =>
      if env.getModuleIdxFor? name == some moduleIdx then names.push name else names)
    |>.qsort Name.lt
  let moduleDataDeclarations := moduleData.constNames.qsort Name.lt
  unless declarations == moduleDataDeclarations do
    throw <| IO.userError
      s!"module scan: Environment.constants and ModuleData.constNames disagree for {moduleName}"
  let privateCount := declarations.filter isPrivateName |>.size
  let internalCount := declarations.filter Name.isInternalDetail |>.size
  let irNamesWithConstantInfo :=
    moduleData.extraConstNames.filter fun name => (env.find? name).isSome

  IO.println s!"MODULE\t{moduleName}"
  IO.println s!"MODULE_INDEX\t{moduleIdx}"
  IO.println s!"DECLARATIONS\t{declarations.size}"
  IO.println "MODULE_DATA_CONSTNAMES_MATCH\ttrue"
  IO.println s!"PRIVATE_DECLARATIONS\t{privateCount}"
  IO.println s!"INTERNAL_DETAIL_DECLARATIONS\t{internalCount}"
  IO.println s!"IR_ONLY_NAMES_EXCLUDED\t{moduleData.extraConstNames.size}"
  IO.println s!"IR_NAMES_WITH_CONSTANT_INFO\t{irNamesWithConstantInfo.size}"
  unless irNamesWithConstantInfo.isEmpty do
    IO.println s!"IR_NAMES_WITH_CONSTANT_INFO_LIST\t{irNamesWithConstantInfo.toList}"

  let mut distribution : List (List Name × Nat) := []
  for decl in declarations do
    let some info := env.find? decl
      | throw <| IO.userError s!"module scan: ConstantInfo not found for {decl}"
    let axioms := collectAxiomsIn env decl
    distribution := bumpDistribution distribution axioms.toList
    let outside := axioms.filter fun axiomName => !baseline.contains axiomName
    unless outside.isEmpty do
      IO.println
        s!"OUTSIDE_BASELINE\t{moduleName}\t{decl}\t{constantKind info}\tOUTSIDE={outside.toList}\tFULL={axioms.toList}"
      throw <| IO.userError s!"module scan: outside-baseline footprint in {moduleName}.{decl}"

  for (footprint, count) in distribution do
    IO.println s!"FOOTPRINT\t{moduleName}\t{count}\t{footprint}"
  IO.println "OUTSIDE_BASELINE_COUNT\t0"
  IO.println s!"MODULE_COMPLETE\t{moduleName}\t{declarations.size}"
  pure declarations.size

def scanAll : IO Unit := do
  checkModuleDrift
  initSearchPath (← findSysroot)
  -- The two serialization-lemma modules both define
  -- `SealV2.skipWs_cons_of_not_ws`, so scan `SerializationLemmas` in an
  -- isolated environment to keep module provenance unambiguous.
  let imports : Array Import :=
    measuredModuleNames.map fun moduleName => { module := moduleName }
  let env ← importModules imports {} (level := .private)
  let mut declarationTotal := 0
  for moduleName in measuredModuleNames do
    declarationTotal := declarationTotal + (← scanModule env moduleName)
  let serializationLemmasEnv ←
    importModules #[{ module := `SealV2.SerializationLemmas }] {} (level := .private)
  declarationTotal := declarationTotal
    + (← scanModule serializationLemmasEnv `SealV2.SerializationLemmas)
  -- `Ffi` stays out pending Ben's ruling on `lcProof`; do not add an exception.
  -- Evidence: /home/monkey/.mega-monkey/lane-reports/lcproof-report.md
  IO.println "FFI_EXCLUDED\tpending Ben's ruling on lcProof; see /home/monkey/.mega-monkey/lane-reports/lcproof-report.md"
  IO.println s!"MODULES_COMPLETE\t{measuredModuleNames.size + 1}"
  IO.println s!"DECLARATIONS_COMPLETE\t{declarationTotal}"

end Test.ModuleAxiomScan

def main : IO UInt32 := do
  try
    Test.ModuleAxiomScan.scanAll
    pure 0
  catch error =>
    IO.eprintln s!"module axiom check: FAIL: {error}"
    pure 1
