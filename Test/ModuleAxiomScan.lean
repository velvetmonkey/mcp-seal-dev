/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Environment
import Lean.Util.CollectAxioms
import Lean.Util.Path
import SealV2.Validation

/-!
Feasibility prototype for scanning every kernel declaration originating in one
module.  This is intentionally not a CI target or an allowlist gate.
-/

namespace Test.ModuleAxiomScan

open Lean

private def baseline : Array Name :=
  #[`propext, `Classical.choice, `Quot.sound]

private def collectAxiomsIn (env : Environment) (decl : Name) : Array Name :=
  let (_, state) := ((CollectAxioms.collect decl).run env).run {}
  state.axioms.qsort Name.lt

private def constantKind : ConstantInfo → String
  | .axiomInfo _  => "axiom"
  | .defnInfo _   => "definition"
  | .thmInfo _    => "theorem"
  | .opaqueInfo _ => "opaque"
  | .quotInfo _   => "quotient"
  | .inductInfo _ => "inductive"
  | .ctorInfo _   => "constructor"
  | .recInfo _    => "recursor"

def scanModule (moduleName : Name) : IO Unit := do
  initSearchPath (← findSysroot)
  -- `.private` is the default deliberately: it loads the module's private
  -- `.olean` data, not just its exported surface.
  let env ← importModules #[{ module := moduleName }] {} (level := .private)
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

  let mut outsideCount := 0
  for decl in declarations do
    let some info := env.find? decl
      | throw <| IO.userError s!"module scan: ConstantInfo not found for {decl}"
    let axioms := collectAxiomsIn env decl
    IO.println s!"DECL\t{decl}\t{constantKind info}\t{axioms.toList}"
    let outside := axioms.filter fun axiomName => !baseline.contains axiomName
    unless outside.isEmpty do
      outsideCount := outsideCount + 1
      IO.println s!"OUTSIDE_BASELINE\t{decl}\t{outside.toList}\tFULL={axioms.toList}"

  IO.println s!"OUTSIDE_BASELINE_COUNT\t{outsideCount}"

#eval scanModule `SealV2.Validation

end Test.ModuleAxiomScan
