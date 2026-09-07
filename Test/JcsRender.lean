/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.Validation

open Lean

namespace Test.JcsRender

/-- Exact RFC 8785 section 3.2.2.2 renderings for U+0000 through U+001F. -/
private def c0Expected : Array String := #[
  "\\u0000", "\\u0001", "\\u0002", "\\u0003",
  "\\u0004", "\\u0005", "\\u0006", "\\u0007",
  "\\b",     "\\t",     "\\n",     "\\u000b",
  "\\f",     "\\r",     "\\u000e", "\\u000f",
  "\\u0010", "\\u0011", "\\u0012", "\\u0013",
  "\\u0014", "\\u0015", "\\u0016", "\\u0017",
  "\\u0018", "\\u0019", "\\u001a", "\\u001b",
  "\\u001c", "\\u001d", "\\u001e", "\\u001f"
]

private def quoted (s : String) : String := "\"" ++ s ++ "\""

private def hexByte (n : Nat) : String :=
  String.ofList [Nat.digitChar (n / 16), Nat.digitChar (n % 16)]

private def checkC0 : IO Bool := do
  let mut ok := true
  for i in [0:c0Expected.size] do
    let expected := quoted c0Expected[i]!
    let produced := Json.jcsRender (.str (String.singleton (Char.ofNat i)))
    let isMatch := produced == expected
    IO.println s!"C0 0x{hexByte i} expected={repr expected} produced={repr produced} match={isMatch}"
    if !isMatch then ok := false
  pure ok

private def checkAdditional : IO Bool := do
  let del := String.singleton (Char.ofNat 0x7f)
  let nested := Json.mkObj [
    ("z", Json.mkObj [("control", .str (String.singleton (Char.ofNat 9)))]),
    ("a", .arr #[.str del, .str "café"])
  ]
  let expectedNested :=
    "{\"a\":[\"" ++ del ++ "\",\"café\"],\"z\":{\"control\":\"\\t\"}}"
  let producedNested := Json.jcsRender nested
  let nestedOk := producedNested == expectedNested
  IO.println s!"ADDITIONAL nested-del-nonascii expected={repr expectedNested} produced={repr producedNested} match={nestedOk}"

  -- Six literal characters: reverse-solidus, u, 0, 0, 0, 8.
  let literalEscape := "\\u0008"
  let expectedLiteral := "\"\\\\u0008\""
  let producedLiteral := Json.jcsRender (.str literalEscape)
  let literalOk := producedLiteral == expectedLiteral
  IO.println s!"TRAP literal-backslash-u0008 expected={repr expectedLiteral} produced={repr producedLiteral} match={literalOk}"

  let orderingProbe := Json.mkObj [("z", .num 2), ("a", .num 1)]
  let orderingOk := orderingProbe.jcsRender == orderingProbe.compress
  IO.println s!"ORDERING unchanged-from-compress match={orderingOk} produced={repr orderingProbe.jcsRender}"
  pure (nestedOk && literalOk && orderingOk)

private def checkNormalizationRoutes : IO Bool := do
  let namedControls := String.ofList [Char.ofNat 8, Char.ofNat 9, Char.ofNat 12]
  let value := Json.mkObj [("v", .str namedControls)]
  let expected := "{\"v\":\"\\b\\t\\f\"}"
  let some object := value.getObj?.toOption
    | throw <| IO.userError "normalization route fixture was not an object"

  let stageMeta : Seal.ValidatedMeta := .present object
  let stageState : Seal.RequestState := .present value
  let stageResponses : Seal.InputResponses := .present value
  let stageOk :=
    stageMeta.preimageParts == ["meta.present", expected] &&
    stageState.preimageParts == ["requestState.present", expected] &&
    stageResponses.preimageParts == ["inputResponses.present", expected]

  let ast : SealV2.AST := .object [("v", .string namedControls)]
  let v2Meta := SealV2.MetaValue.ofStage1 stageMeta
  let v2State := SealV2.RequestState.ofStage1 stageState
  let v2Responses := SealV2.InputResponses.ofStage1 stageResponses
  let v2IngestOk :=
    SealV2.MetaValue.fromAst? (some ast) == some v2Meta &&
    SealV2.RequestState.fromAst? (some ast) == some v2State &&
    SealV2.InputResponses.fromAst? (some ast) == some v2Responses
  let v2SignedOk :=
    SealV2.MetaValue.fromSignedAst? (SealV2.MetaValue.signedAst v2Meta) == some v2Meta &&
    SealV2.RequestState.fromSignedAst? (SealV2.RequestState.signedAst expected) == some v2State &&
    SealV2.InputResponses.fromSignedAst? (SealV2.InputResponses.signedAst expected) == some v2Responses
  IO.println s!"ROUTES stage1-meta-state-responses expected={repr expected} match={stageOk}"
  IO.println s!"ROUTES v2-ofStage1-and-fromAst match={v2IngestOk}"
  IO.println s!"ROUTES v2-fromSignedAst match={v2SignedOk}"
  pure (stageOk && v2IngestOk && v2SignedOk)

def main : IO UInt32 := do
  let c0Ok <- checkC0
  let additionalOk <- checkAdditional
  let routesOk <- checkNormalizationRoutes
  if c0Ok && additionalOk && routesOk then
    IO.println "JCS STRING RENDERER GREEN: complete C0 table + recursion + routes + DEL + non-ASCII + literal-escape trap"
    pure 0
  else
    IO.eprintln "JCS STRING RENDERER RED"
    pure 1

end Test.JcsRender

def main : IO UInt32 := Test.JcsRender.main
