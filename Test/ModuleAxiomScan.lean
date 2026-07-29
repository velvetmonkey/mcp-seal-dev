/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Environment
import Lean.Util.CollectAxioms
import Lean.Util.Path
import Seal
import SealCore
import SealV2.Crypto
import SealV2.McpVersionGate
import SealV2.SerializationContainerLemmas
import SealV2.SerializationLemmas

/-!
Module-aware axiom gate implementing Ben's 2026-07-28 ruling:

* regular kernel modules retain exactly `[propext, Classical.choice, Quot.sound]`;
* the separately enumerated unsafe compiled-code root `Ffi` has the explicit
  baseline `[propext, Classical.choice, Quot.sound, lcProof]`.

This is not one uniform baseline. `Ffi` is the only module assigned to the
unsafe compiled-code-root baseline. The characterization is limited to kernel
logical soundness of regular declarations. It says nothing about runtime,
memory-safety, or observational purity of the six unsafe wrappers.
-/

namespace Test.ModuleAxiomScan

open Lean

private def kernelBaseline : Array Name :=
  #[`propext, `Classical.choice, `Quot.sound]

private def unsafeCompiledCodeRootBaseline : Array Name :=
  #[`propext, `Classical.choice, `Quot.sound, `lcProof]

private def collectAxiomsIn (env : Environment) (decl : Name) : Array Name :=
  let (_, state) := ((CollectAxioms.collect decl).run env).run {}
  state.axioms.qsort Name.lt

private def kernelBaselineModuleNames : Array Name := #[
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
  `SealV2.McpVersionGate,
  `SealV2.Parser,
  `SealV2.Serialization,
  `SealV2.SerializationContainerLemmas,
  `SealV2.SerializationLemmas,
  `SealCore,
  `Seal,
  `SealV2
]

private def unsafeCompiledCodeRootModuleNames : Array Name := #[
  `Ffi
]

private def expectedProductionModuleCount : Nat := 50
private def expectedKernelBaselineModuleCount : Nat := 24
private def expectedUnsafeCompiledCodeRootModuleCount : Nat := 1

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
  let mut failures : Array String := #[]
  unless actual == expectedProductionModuleCount do
    failures := failures.push
      s!"module scan: production module count drifted from {expectedProductionModuleCount} to {actual}; review the measured scan scope"
  unless kernelBaselineModuleNames.size == expectedKernelBaselineModuleCount do
    failures := failures.push
      s!"module scan: kernel-baseline assignment count drifted from {expectedKernelBaselineModuleCount} to {kernelBaselineModuleNames.size}"
  unless unsafeCompiledCodeRootModuleNames.size ==
      expectedUnsafeCompiledCodeRootModuleCount do
    failures := failures.push
      s!"module scan: unsafe compiled-code-root assignment count drifted from {expectedUnsafeCompiledCodeRootModuleCount} to {unsafeCompiledCodeRootModuleNames.size}"
  unless unsafeCompiledCodeRootModuleNames == #[`Ffi] do
    failures := failures.push
      "module scan: Ffi must be the only unsafe compiled-code-root module"
  for moduleName in unsafeCompiledCodeRootModuleNames do
    if kernelBaselineModuleNames.contains moduleName then
      failures := failures.push
        s!"module scan: {moduleName} is assigned to both axiom baselines"
  unless failures.isEmpty do
    throw <| IO.userError (String.intercalate "\n" failures.toList)
  IO.println s!"KERNEL_BASELINE\t{kernelBaseline.toList}"
  IO.println
    s!"UNSAFE_COMPILED_CODE_ROOT_BASELINE\t{unsafeCompiledCodeRootBaseline.toList}"
  IO.println
    s!"KERNEL_BASELINE_MODULES\t{kernelBaselineModuleNames.toList}"
  IO.println
    s!"UNSAFE_COMPILED_CODE_ROOT_MODULES\t{unsafeCompiledCodeRootModuleNames.toList}"
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

private structure ScanResult where
  declarations : Nat
  outsideKernelBaseline : Nat

def scanModule
    (env : Environment)
    (moduleName : Name)
    (baselineLabel : String)
    (baseline : Array Name) :
    IO ScanResult := do
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
  IO.println s!"MODULE_BASELINE\t{moduleName}\t{baselineLabel}\t{baseline.toList}"
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
  let mut outsideKernelBaselineCount := 0
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
    let outsideKernel :=
      axioms.filter fun axiomName => !kernelBaseline.contains axiomName
    unless outsideKernel.isEmpty do
      outsideKernelBaselineCount := outsideKernelBaselineCount + 1
      IO.println
        s!"OUTSIDE_KERNEL_BASELINE\t{moduleName}\t{decl}\t{constantKind info}\tOUTSIDE={outsideKernel.toList}\tFULL={axioms.toList}"

  for (footprint, count) in distribution do
    IO.println s!"FOOTPRINT\t{moduleName}\t{count}\t{footprint}"
  IO.println "OUTSIDE_BASELINE_COUNT\t0"
  IO.println
    s!"OUTSIDE_KERNEL_BASELINE_COUNT\t{outsideKernelBaselineCount}"
  IO.println s!"MODULE_COMPLETE\t{moduleName}\t{declarations.size}"
  pure {
    declarations := declarations.size
    outsideKernelBaseline := outsideKernelBaselineCount
  }

def scanAll : IO Unit := do
  checkModuleDrift
  initSearchPath (← findSysroot)
  let kernelStart ← IO.monoMsNow
  -- The two serialization-lemma modules both define
  -- `SealV2.skipWs_cons_of_not_ws`, so scan `SerializationLemmas` in an
  -- isolated environment to keep module provenance unambiguous.
  let sharedKernelModuleNames :=
    kernelBaselineModuleNames.filter fun moduleName =>
      moduleName != `SealV2.SerializationLemmas
  let imports : Array Import :=
    sharedKernelModuleNames.map fun moduleName => { module := moduleName }
  let env ← importModules imports {} (level := .private)
  let mut kernelDeclarationTotal := 0
  for moduleName in sharedKernelModuleNames do
    let result ← scanModule env moduleName "KERNEL" kernelBaseline
    kernelDeclarationTotal := kernelDeclarationTotal + result.declarations
  let serializationLemmasEnv ←
    importModules #[{ module := `SealV2.SerializationLemmas }] {} (level := .private)
  let serializationResult ←
    scanModule serializationLemmasEnv `SealV2.SerializationLemmas
      "KERNEL" kernelBaseline
  kernelDeclarationTotal :=
    kernelDeclarationTotal + serializationResult.declarations
  let kernelElapsedMs := (← IO.monoMsNow) - kernelStart
  IO.println
    s!"BASELINE_COMPLETE\tKERNEL\tMODULES={kernelBaselineModuleNames.size}\tDECLARATIONS={kernelDeclarationTotal}\tWALL_CLOCK_MS={kernelElapsedMs}"

  -- `Ffi` and `Seal.Main` both define root `main`, so the explicitly assigned
  -- unsafe compiled-code root is imported and scanned in an isolated environment.
  let unsafeStart ← IO.monoMsNow
  let ffiEnv ← importModules #[{ module := `Ffi }] {} (level := .private)
  let ffiResult ←
    scanModule ffiEnv `Ffi "UNSAFE_COMPILED_CODE_ROOT"
      unsafeCompiledCodeRootBaseline
  let unsafeElapsedMs := (← IO.monoMsNow) - unsafeStart
  IO.println
    s!"BASELINE_COMPLETE\tUNSAFE_COMPILED_CODE_ROOT\tMODULES={unsafeCompiledCodeRootModuleNames.size}\tDECLARATIONS={ffiResult.declarations}\tWALL_CLOCK_MS={unsafeElapsedMs}"
  IO.println
    s!"UNSAFE_COMPILED_CODE_ROOT_OUTSIDE_KERNEL_BASELINE_DECLARATIONS\t{ffiResult.outsideKernelBaseline}"
  IO.println
    s!"MODULES_COMPLETE\t{kernelBaselineModuleNames.size + unsafeCompiledCodeRootModuleNames.size}"
  IO.println
    s!"DECLARATIONS_COMPLETE\t{kernelDeclarationTotal + ffiResult.declarations}"

end Test.ModuleAxiomScan

def main : IO UInt32 := do
  try
    Test.ModuleAxiomScan.scanAll
    pure 0
  catch error =>
    IO.eprintln s!"module axiom check: FAIL: {error}"
    pure 1
