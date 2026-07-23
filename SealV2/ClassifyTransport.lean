/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.ResponseTransport
import Seal.Classify
import Seal.JsonUtil

/-!
# The wire-classify seam widened onto the transport model (K3/K4)

## Why this file exists (the honesty gap being closed)

Every request model in this repository so far — `ResponseNI.HostEvent.request`
and its byte-transport enrichment in `ResponseTransport` — decides EVERY
request event: `reqDecision` is total and the request arm of `runTrace`
always emits a `.decision`. That mirrors mcp-seal-dev's own FFI
(`Ffi.decideImpl` fails closed), and the `ResponseNI` header says so. But the
deployed seal-host router does NOT hand every wire line to a kernel. It
classifies first (seal-host `Host/Canonical.lean:42-66`, exported as
`seal_host_classify`, consumed at `rust/src/main.rs:1339-1361`):

* `.act`        → mediated: the line reaches a kernel gate;
* `.passthrough`→ the line is written to the CHILD's stdin verbatim, with no
                  decision of any kind (`main.rs:1340-1350`: "the INNER bytes
                  flow to the child", no approval poll, no nonce burn);
* `.refuse`     → the line is answered with a seam error and never forwarded
                  (`main.rs:1352-1361`).

A model whose alphabet cannot express the `.passthrough` transition proves
mediation properties over a world in which passthrough does not exist. This
file WIDENS the model: the observation alphabet gains `.forwarded` (child-
bound bytes, undecided) and `.refused`, and the request transition routes
through the classifier. The point is not that passthrough is safe or unsafe;
it is the exact boundary — which byte class escapes undecided — stated as a
theorem with both sides witnessed.

## Binding the right object

seal-host's `classifyLine` is a thin composition of functions DEFINED IN THIS
REPOSITORY: `Seal.JsonUtil.wireNumbersSafe` (`Seal/JsonUtil.lean:95`),
`Lean.Json.parse`, and `Seal.toolsCall?` (`Seal/Classify.lean:113`). The
`classifyWire` mirror below composes those same definitions — not namesakes —
in the same order as `Host/Canonical.lean:42-66` (trim, number-guard refuse,
parse, tools-call match). What remains hand-mirrored (cited, not proven) is
only the composition itself and the router's use of it; there is no
refinement proof from seal-host or from the compiled Rust, and no theorem
here transfers to the deployed binary.

## The strict/lenient split (K4)

Routing is STRICT: a line is mediated iff a strict JSON parse of the trimmed
line yields the byte-exact `tools/call` shape. The named assumption
A-strict-child (seal-host `RUST_BRIDGE.md:18-24`, `TCB.md` T10) is that the
child parses its protocol equally strictly. A LENIENT child — one that
tolerates a UTF-8 BOM (RFC 8259 §8.1 allows implementations to ignore one),
matches the method case-insensitively, or executes JSON-RPC 2.0 §6 batch
arrays — can interpret as a call a line the router classified as non-call
traffic and forwarded undecided. `lenientCalls` below is a REFERENCE lenient
reading made of exactly those three documented leniencies. It is a lower
bound on what some lenient child may execute, not a model of every possible
child (the child is arbitrary; no such model exists). The class
`undecidedCallClass = escapesClass ∧ lenientClass` is therefore the proved
LOWER BOUND on the strict-monitor/lenient-child gap — the byte class that
provably escapes undecided AND is executed as a call by the reference
lenient reading. Prior art calls this failure family a parser differential
(LangSec, Sassaman–Patterson–Bratus); the escape hazard here is the
mediation-side instance of it.

## Modeling conventions, stated so they can be frisked

* One `.request raw now` event is one wire line arriving at the ROUTER — not
  (as in `ResponseNI`/`ResponseTransport`) one call to the kernel's decide.
  The widened model places the classifier between the two.
* The mediated arm's decision function stays `reqDecision` — this repo's
  kernel composition. The deployed seal-host Mediate arm gates through its
  own kernel registry; only the ROUTING is mirrored from seal-host here.
* Refused and passthrough lines leave the approval plane untouched and burn
  no nonce (`main.rs:1332-1338`); the model's arms are state-identity.
* Unmodeled, honestly: failure of the child-stdin write on a passthrough
  forward (`main.rs:1345-1348` — death + seam error; the mediated forward
  has the same unmodeled arm), failure of the seam-error client write on
  refuse (`main.rs:1357-1359`), the envelope inner-byte substitution on
  enveloped lines (`main.rs:1321-1328`: the child receives the INNER bytes;
  this model forwards the wire line), and everything the `ResponseTransport`
  honesty boundary already lists.
* `Lean.Json.parse` is `partial`: the kernel cannot reduce it, so concrete
  class membership of a specific line is pinned by `#guard` (compiler-
  evaluated) and re-confirmed at runtime by `Test/ClassifyEnum.lean`; the
  theorems quantify over lines with the class as a hypothesis.
-/

namespace SealV2.ClassifyTransport

open SealV2 Lean

/-! ## The byte classes: R (refused), S (mediated), and the escape class

Each is a predicate on the input bytes alone. None mentions the router or
the transport model — the theorems connect them to the model's behavior, so
the characterisation cannot collapse into "the router forwards what the
router forwards". -/

/-- The line as the classifier sees it: ASCII-trimmed, exactly
    `Host/Canonical.lean:44` (`line.trimAscii.toString`). -/
def trimmed (line : String) : String := line.trimAscii.toString

/-- **R** — the refused class: the pre-parse number guard rejects the line
    (a pathological decimal exponent; `Seal/JsonUtil.lean:95`,
    `Host/Canonical.lean:48-55`). Refused lines are neither mediated nor
    forwarded. -/
def refusedClass (line : String) : Bool :=
  !Seal.JsonUtil.wireNumbersSafe (trimmed line)

/-- The strict `tools/call` shape, stated structurally on the parsed JSON
    value: a `method` member that is the string `"tools/call"` byte-exactly,
    and a `params.name` string member. Stated independently of
    `Seal.toolsCall?`; `strictCallShape_eq_toolsCall?` proves it equals the
    deployed matcher. -/
def strictCallShape (j : Json) : Bool :=
  ((j.getObjVal? "method").toOption.bind (·.getStr?.toOption) == some "tools/call")
    && ((j.getObjVal? "params").toOption.bind
          (fun p => (p.getObjVal? "name").toOption.bind (·.getStr?.toOption))).isSome

/-- **S** — the mediated class: number-guard safe, strict-parses, and has the
    strict `tools/call` shape. A line is decided before forwarding iff it is
    in S (`forwarded_iff_escapes` and friends below). -/
def mediatedClass (line : String) : Bool :=
  Seal.JsonUtil.wireNumbersSafe (trimmed line)
    && (match Json.parse (trimmed line) with
        | .error _ => false
        | .ok j => strictCallShape j)

/-- **The escape class** — the exact byte class that is forwarded to the
    child with no decision: not refused, not mediated. Includes malformed
    JSON, BOM-prefixed JSON, non-byte-exact method spellings
    (`"TOOLS/CALL"`), JSON-RPC batch arrays — and ALL legitimate non-call
    traffic (`initialize`, `tools/list`, notifications), whose passthrough
    is the protocol working as designed. The hazard is not this class; it is
    its intersection with what a lenient child executes
    (`undecidedCallClass`). -/
def escapesClass (line : String) : Bool :=
  !refusedClass line && !mediatedClass line

/-! ## The classifier mirror -/

/-- Wire-line routing verdict, constructor-for-constructor seal-host's
    `Host.LineClass` (`Host/Canonical.lean:26-35`); `.act` carries the
    matched tool name and arguments instead of seal-host's
    `CanonicalAction` record (whose remaining fields — `ast?`, `raw`,
    `requestId` — feed audit and approval binding, not routing). -/
inductive WireClass where
  | passthrough
  | act (tool : String) (args : Json)
  | refuse

/-- The router mirror: the same `wireNumbersSafe → Json.parse → toolsCall?`
    composition as `Host/Canonical.lean:42-66`, over THIS repository's own
    `Seal.JsonUtil.wireNumbersSafe` and `Seal.toolsCall?` — the very
    definitions seal-host imports. -/
def classifyWire (line : String) : WireClass :=
  if !Seal.JsonUtil.wireNumbersSafe (trimmed line) then
    .refuse
  else
    match Json.parse (trimmed line) with
    | .error _ => .passthrough
    | .ok json =>
        match Seal.toolsCall? json with
        | none => .passthrough
        | some (toolName, toolArgs) => .act toolName toolArgs

/-! ## The reference lenient reading (K4's other half) -/

/-- Strip one leading U+FEFF. RFC 8259 §8.1: implementations MAY ignore a
    byte-order mark; many real parsers do. The strict router does not
    (`Json.parse` fails on it), so a BOM-prefixed call escapes. -/
def stripBom (s : String) : String :=
  if s.startsWith "\uFEFF" then (s.drop 1).toString else s

/-- Case-insensitive method match — the leniency named by seal-host's own
    A-strict-child example (`RUST_BRIDGE.md:20`: `"TOOLS/CALL"`). -/
def lenientMethodIsCall (m : String) : Bool :=
  m.toLower == "tools/call"

/-- One object read leniently: as `Seal.toolsCall?` but with the
    case-insensitive method match. -/
def lenientCallOf? (j : Json) : Option (String × Json) := do
  let methodJson ← (j.getObjVal? "method").toOption
  let method ← methodJson.getStr?.toOption
  if !lenientMethodIsCall method then
    none
  else
    let params ← (j.getObjVal? "params").toOption
    let nameJson ← (params.getObjVal? "name").toOption
    let name ← nameJson.getStr?.toOption
    let args := (params.getObjVal? "arguments").toOption.getD Json.null
    some (name, args)

/-- The calls the reference lenient child executes from one parsed value:
    a JSON-RPC 2.0 §6 batch array executes each element's call (MCP revision
    2025-03-26 inherited batching from JSON-RPC; revision 2025-06-18 removed
    it — a child on the older revision, or any generic JSON-RPC server,
    executes batches); a single object executes its own call, if any. The
    strict matcher sees no call in ANY array (`toolsCall?_arr_none`). -/
def lenientCalls : Json → List (String × Json)
  | .arr elems => elems.toList.filterMap lenientCallOf?
  | j => (lenientCallOf? j).toList

/-- The lenient parse: the strict parse if it succeeds, else one retry with
    the BOM stripped. Defined over the SAME `Json.parse (trimmed line)` call
    as `mediatedClass`, so strict ⊆ lenient is provable rather than assumed. -/
def lenientParse (line : String) : Except String Json :=
  match Json.parse (trimmed line) with
  | .ok j => .ok j
  | .error e =>
      match Json.parse (stripBom (trimmed line)) with
      | .ok j => .ok j
      | .error _ => .error e

/-- **L** — the reference lenient child executes at least one call from the
    line. -/
def lenientClass (line : String) : Bool :=
  match lenientParse line with
  | .error _ => false
  | .ok j => !(lenientCalls j).isEmpty

/-- **The K4 class: forwarded undecided AND executable as a call by the
    reference lenient child.** The proved lower bound on the
    strict-monitor/lenient-child gap. -/
def undecidedCallClass (line : String) : Bool :=
  escapesClass line && lenientClass line

end SealV2.ClassifyTransport
