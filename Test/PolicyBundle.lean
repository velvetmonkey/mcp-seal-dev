/- SPDX-License-Identifier: Apache-2.0 -/

import Seal.PolicyBundle

open Lean

/-! End-to-end tests for the 7-kernel policy bundle parser: roundtrip of every
    section, unknown-key hard errors at every level, `enabled` defaults and
    collapse semantics, and the preserved envelope rules (epoch, server
    conflict/enrichment). Every positive assertion first checks the section is
    present/non-empty — no vacuous passes. -/

private def parseBundle (text : String) : Except String Seal.PolicyBundle :=
  Json.parse text >>= Seal.parsePolicyBundle

private def expectOk (label text : String) : IO Seal.PolicyBundle := do
  match parseBundle text with
  | .ok b => pure b
  | .error e => throw <| IO.userError s!"{label}: expected parse, got error: {e}"

private def expectErrContaining (label text needle : String) : IO Unit := do
  match parseBundle text with
  | .ok _ => throw <| IO.userError s!"{label}: expected rejection ({needle}), parsed"
  | .error e =>
      unless (e.splitOn needle).length > 1 do
        throw <| IO.userError s!"{label}: error missing '{needle}': {e}"

private def safetyBlock : String :=
  "\"safety\":{\"approval\":{\"control_file\":\"/tmp/approvals.ndjson\",\"ttl_seconds\":60},\"tools\":[{\"name\":\"db.execute\",\"mode\":\"guard\",\"target\":[{\"full_arguments\":true}]}]}"

/-- A payload with every kernel section present. -/
private def fullPayload : String :=
  "{\"epoch\":3,\"server\":\"srv-1\"," ++ safetyBlock ++ "," ++
  "\"temporal\":{\"policies\":[{\"name\":\"freeze\",\"type\":\"no_after\",\"trigger\":[\"revoke\"],\"forbidden\":[\"write_item\"]}]}," ++
  "\"consensus\":{\"roster\":[1,2,3],\"votes_file\":\"/tmp/votes.ndjson\",\"high_stakes\":[\"deploy\"]}," ++
  "\"convergence\":{\"tools\":[{\"tool\":\"store.update\",\"op_arg\":\"operation.kind\"}]}," ++
  "\"calibration\":{\"enabled\":true,\"delta_num\":1,\"delta_den\":20,\"min_samples\":10,\"records_file\":\"/tmp/forecasts.ndjson\",\"gated_tools\":[\"auto_publish\"]}," ++
  "\"linear\":{\"grants_file\":\"/tmp/grants.ndjson\",\"tools\":[{\"tool\":\"spend\",\"cap_arg\":\"capability.id\"}]}," ++
  "\"budget\":{\"budgets\":[{\"name\":\"write-units\",\"cap\":100,\"tools\":[\"write_item\"],\"cost_arg\":\"usage.units\"}]}}"

private def minimalPayload : String :=
  "{\"epoch\":1," ++ safetyBlock ++ "}"

private def withSection (section_ : String) : String :=
  "{\"epoch\":1," ++ safetyBlock ++ "," ++ section_ ++ "}"

def main : IO Unit := do
  -- roundtrip: all seven sections parse and every field survives
  let b ← expectOk "full roundtrip" fullPayload
  unless b.epoch == 3 do throw <| IO.userError "epoch lost"
  unless b.safety.serverIdentity == "srv-1" do
    throw <| IO.userError s!"outer server did not reach safety: {b.safety.serverIdentity}"
  unless b.safety.tools.length == 1 do throw <| IO.userError "safety tools lost"
  match b.temporal with
  | some t =>
      unless t.enabled do throw <| IO.userError "temporal enabled default not true"
      unless t.policies == [{ name := "freeze", trigger := ["revoke"],
                              forbidden := ["write_item"] }] do
        throw <| IO.userError s!"temporal fields lost: {repr t}"
  | none => throw <| IO.userError "temporal section lost"
  match b.consensus with
  | some c =>
      unless c == { enabled := true, roster := [1, 2, 3],
                    votesFile := "/tmp/votes.ndjson", highStakes := ["deploy"] } do
        throw <| IO.userError s!"consensus fields lost: {repr c}"
  | none => throw <| IO.userError "consensus section lost"
  match b.convergence with
  | some v =>
      unless v.tools == [{ tool := "store.update", opArg := ["operation", "kind"] }] do
        throw <| IO.userError s!"convergence op_arg not split: {repr v}"
  | none => throw <| IO.userError "convergence section lost"
  match b.calibration with
  | some k =>
      unless k == { enabled := true, deltaNum := 1, deltaDen := 20, minSamples := 10,
                    recordsFile := "/tmp/forecasts.ndjson",
                    gatedTools := ["auto_publish"] } do
        throw <| IO.userError s!"calibration fields lost: {repr k}"
  | none => throw <| IO.userError "calibration section lost"
  match b.linear with
  | some l =>
      unless l.tools == [{ tool := "spend", capArg := ["capability", "id"] }] do
        throw <| IO.userError s!"linear cap_arg not split: {repr l}"
  | none => throw <| IO.userError "linear section lost"
  match b.budget with
  | some bg =>
      unless bg.budgets == [{ name := "write-units", cap := 100,
                              tools := ["write_item"],
                              costArg := some ["usage", "units"] }] do
        throw <| IO.userError s!"budget fields lost: {repr bg}"
  | none => throw <| IO.userError "budget section lost"

  -- minimal payload: six sections absent, all effective views empty
  let m ← expectOk "minimal payload" minimalPayload
  unless m.temporal.isNone && m.consensus.isNone && m.convergence.isNone
      && m.calibration.isNone && m.linear.isNone && m.budget.isNone do
    throw <| IO.userError "absent sections did not stay absent"
  unless m.effectiveTemporal.isEmpty && m.effectiveConsensus.isNone
      && m.effectiveConvergence.isEmpty && m.effectiveLinear.isNone
      && m.effectiveBudget.isEmpty do
    throw <| IO.userError "effective views of absent sections not empty"

  -- unknown keys: hard errors at every level
  expectErrContaining "top-level typo"
    ("{\"epoch\":1," ++ safetyBlock ++ ",\"temporral\":{}}")
    "unknown key 'temporral'"
  expectErrContaining "unknown temporal key"
    (withSection "\"temporal\":{\"policies\":[],\"window\":9}") "unknown key 'window'"
  expectErrContaining "unknown consensus key"
    (withSection "\"consensus\":{\"roster\":[1],\"votes_file\":\"v\",\"high_stakes\":[],\"quorum\":2}")
    "unknown key 'quorum'"
  expectErrContaining "unknown convergence key"
    (withSection "\"convergence\":{\"tools\":[],\"ops\":[]}") "unknown key 'ops'"
  expectErrContaining "unknown calibration key"
    (withSection "\"calibration\":{\"delta_num\":1,\"delta_den\":2,\"min_samples\":1,\"records_file\":\"r\",\"gated_tools\":[],\"delta\":0.5}")
    "unknown key 'delta'"
  expectErrContaining "unknown linear key"
    (withSection "\"linear\":{\"grants_file\":\"g\",\"tools\":[],\"caps\":[]}")
    "unknown key 'caps'"
  expectErrContaining "unknown budget key"
    (withSection "\"budget\":{\"budgets\":[],\"cap\":1}") "unknown key 'cap'"
  expectErrContaining "unknown budget spec key"
    (withSection "\"budget\":{\"budgets\":[{\"name\":\"n\",\"cap\":1,\"tools\":[],\"costs\":1}]}")
    "unknown key 'costs'"
  expectErrContaining "unknown temporal rule key"
    (withSection "\"temporal\":{\"policies\":[{\"name\":\"n\",\"type\":\"no_after\",\"trigger\":[],\"forbidden\":[],\"after\":\"x\"}]}")
    "unknown key 'after'"
  expectErrContaining "unknown convergence tool key"
    (withSection "\"convergence\":{\"tools\":[{\"tool\":\"t\",\"op_arg\":\"o\",\"op\":\"x\"}]}")
    "unknown key 'op'"
  expectErrContaining "unknown linear tool key"
    (withSection "\"linear\":{\"grants_file\":\"g\",\"tools\":[{\"tool\":\"t\",\"cap_arg\":\"c\",\"cap\":1}]}")
    "unknown key 'cap'"
  expectErrContaining "unknown safety key"
    ("{\"epoch\":1,\"safety\":{\"approval\":{\"control_file\":\"c\"},\"tools\":[],\"enabled\":true}}")
    "unknown key 'enabled'"
  expectErrContaining "unknown approval key"
    ("{\"epoch\":1,\"safety\":{\"approval\":{\"control_file\":\"c\",\"ttl\":9},\"tools\":[]}}")
    "unknown key 'ttl'"

  -- replay_store is the documented host-layer approval key: accepted
  let _ ← expectOk "replay_store allowlisted"
    ("{\"epoch\":1,\"safety\":{\"approval\":{\"control_file\":\"c\",\"replay_store\":{\"sqlite_path\":\"/tmp/r.db\"}},\"tools\":[]}}")

  -- enabled: defaults true (except calibration), false collapses effective view
  let td ← expectOk "temporal disabled"
    (withSection "\"temporal\":{\"enabled\":false,\"policies\":[{\"name\":\"n\",\"type\":\"no_after\",\"trigger\":[\"a\"],\"forbidden\":[\"b\"]}]}")
  unless td.temporal.isSome do throw <| IO.userError "disabled temporal lost"
  unless td.effectiveTemporal.isEmpty do
    throw <| IO.userError "disabled temporal still effective"
  let cd ← expectOk "consensus disabled"
    (withSection "\"consensus\":{\"enabled\":false,\"roster\":[1],\"votes_file\":\"v\",\"high_stakes\":[\"deploy\"]}")
  unless cd.consensus.isSome do throw <| IO.userError "disabled consensus lost"
  unless cd.effectiveConsensus.isNone do
    throw <| IO.userError "disabled consensus still effective"
  let vd ← expectOk "convergence disabled"
    (withSection "\"convergence\":{\"enabled\":false,\"tools\":[{\"tool\":\"t\",\"op_arg\":\"o\"}]}")
  unless vd.effectiveConvergence.isEmpty do
    throw <| IO.userError "disabled convergence still effective"
  let ld ← expectOk "linear disabled"
    (withSection "\"linear\":{\"enabled\":false,\"grants_file\":\"g\",\"tools\":[{\"tool\":\"t\",\"cap_arg\":\"c\"}]}")
  unless ld.effectiveLinear.isNone do
    throw <| IO.userError "disabled linear still effective"
  let bd ← expectOk "budget disabled"
    (withSection "\"budget\":{\"enabled\":false,\"budgets\":[{\"name\":\"n\",\"cap\":1,\"tools\":[\"t\"]}]}")
  unless bd.effectiveBudget.isEmpty do
    throw <| IO.userError "disabled budget still effective"

  -- calibration: EXPERIMENTAL default is DISABLED; present-but-disabled stays present
  let kDefault ← expectOk "calibration default"
    (withSection "\"calibration\":{\"delta_num\":1,\"delta_den\":20,\"min_samples\":5,\"records_file\":\"r\",\"gated_tools\":[\"t\"]}")
  match kDefault.calibration with
  | some k =>
      unless k.enabled == false do
        throw <| IO.userError "calibration enabled did not default to false"
  | none => throw <| IO.userError "calibration section lost"
  let kOff ← expectOk "calibration disabled still present"
    (withSection "\"calibration\":{\"enabled\":false,\"delta_num\":1,\"delta_den\":20,\"min_samples\":5,\"records_file\":\"r\",\"gated_tools\":[\"t\"]}")
  unless kOff.calibration.isSome do
    throw <| IO.userError "disabled calibration must stay present (double gate)"

  -- envelope rules preserved
  expectErrContaining "epoch zero" ("{\"epoch\":0," ++ safetyBlock ++ "}")
    "config epoch must be ≥ 1"
  expectErrContaining "server conflict"
    "{\"epoch\":1,\"server\":\"outer\",\"safety\":{\"server\":\"inner\",\"approval\":{\"control_file\":\"c\"},\"tools\":[]}}"
    "server identity conflicts"
  let enrich ← expectOk "outer server enrichment"
    ("{\"epoch\":1,\"server\":\"only-outer\"," ++ safetyBlock ++ "}")
  unless enrich.safety.serverIdentity == "only-outer" do
    throw <| IO.userError "outer server did not enrich safety policy"
  let inner ← expectOk "matching servers"
    "{\"epoch\":1,\"server\":\"same\",\"safety\":{\"server\":\"same\",\"approval\":{\"control_file\":\"c\"},\"tools\":[]}}"
  unless inner.safety.serverIdentity == "same" do
    throw <| IO.userError "matching inner server lost"

  -- cost_arg optional; bad temporal type; bad calibration delta
  let noCost ← expectOk "budget without cost_arg"
    (withSection "\"budget\":{\"budgets\":[{\"name\":\"rate\",\"cap\":5,\"tools\":[\"t\"]}]}")
  match noCost.budget with
  | some bg =>
      unless bg.budgets.length == 1 && (bg.budgets.head?.map (·.costArg)).join.isNone do
        throw <| IO.userError "absent cost_arg must parse as none"
  | none => throw <| IO.userError "budget section lost (no cost_arg)"
  expectErrContaining "bad temporal type"
    (withSection "\"temporal\":{\"policies\":[{\"name\":\"n\",\"type\":\"eventually\",\"trigger\":[],\"forbidden\":[]}]}")
    "unsupported temporal policy type"
  expectErrContaining "bad calibration delta"
    (withSection "\"calibration\":{\"delta_num\":3,\"delta_den\":2,\"min_samples\":1,\"records_file\":\"r\",\"gated_tools\":[]}")
    "calibration delta must satisfy"

  IO.println "POLICY-BUNDLE TESTS PASS"
