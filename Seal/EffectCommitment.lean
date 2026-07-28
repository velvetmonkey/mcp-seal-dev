/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Data.Json
import Seal.Hash

/-!
# The effect commitment — pinned preimage, injectivity under named assumptions

Stage A of the effect-commitment plan. The current stage-1 proposal:

    effect_commitment =
      SHA256(encodeParts
        (["seal.effect/v4-proposed-meta-all", server, tool, args.compress] ++
          metadata.preimageParts))
                        → lowercase hex, 64 chars

The metadata suffix is exactly `["meta.absent", ""]` or
`["meta.present", compress(object)]`.  The explicit presence discriminator
makes absence distinct from a present empty object.

* `encodeParts` is REUSED (netstring framing, `Seal.Hash`): its injectivity
  obligation is already discharged in seal-host `Host/CapabilityAdequacy`;
  no new framing, no second obligation.
* `server` and `tool` are INSIDE the preimage: identical arguments under a
  different tool (or server) must never share a commitment.
* The PROPOSED version tag is INSIDE the digest: a later commitment shape is
  distinguishable from this one, and the effect preimage cannot collide
  with the approval preimage over the same alphabet.  This tag and layout are
  deliberately not presented as the final cross-language byte specification:
  changing either invalidates every dependent effect vector, target, approval,
  signature, replay namespace, golden, artifact pin, and provenance record.
* `kernel_identity` is NOT here — it belongs to the approval preimage only.
  Kernels repin; commitments and stored approvals must survive that.
* Lowercase hex everywhere: the digest never exists as raw bytes outside
  the hash function; every consumer takes the 64-char hex string.

## Named assumptions

The theorems below are conditional on FOUR named assumptions, stated as
`Prop`-valued definitions and taken as hypotheses (never as axioms — the
axiom gate stays `propext`/`Classical.choice`/`Quot.sound`):

* `A-CR` (`AssumptionCR`): an IDEALISATION — perfect injectivity of the
  digest pipeline, stated at the lowercase-hex surface the system consumes.
  This is deliberately NOT computational collision resistance and is
  strictly stronger than it: collision resistance says a collision is
  infeasible to FIND; this premise says no collision EXISTS, which no
  fixed-output hash over unbounded inputs can satisfy (pigeonhole), so
  real SHA-256 does not satisfy it. Theorems conditional on A-CR hold in
  the idealised collision-free model only and do NOT instantiate as
  theorems about real SHA-256; the deployed guarantee is a TRUST
  assumption (no SHA-256 collision is known or findable for the inputs
  Seal hashes) that Lean does not and cannot prove. What the structure
  buys, honestly: the cryptographic trust is isolated to this one named
  leaf hypothesis. Stating it at the hex level avoids a separate (true
  but loop-shaped) `toHex` injectivity proof over the runtime encoder.
  See `docs/ASSUMPTIONS.md`.
* `A-ENC` (`AssumptionEncInjective`): `encodeParts` is injective over
  `List String`. True (netstring frames are self-delimiting) and since K5
  PROVED in this repo — `Seal.Encoding.assumptionEncInjective_holds`
  (`Seal/EncodingInjective.lean`, which also proves injectivity of the UTF-8
  bytes the hash consumes). Kept in the hypothesis list so the statements
  below are unchanged; use
  `Seal.Encoding.effect_commitment_injective_of_cr_compress` for the
  discharged form.
* `A-COMPRESS` (`AssumptionCompressInjective`): `Lean.Json.compress` is
  injective. This is what "the commitment binds the JSON value, not a
  string" costs: two distinct `Json` values must not share canonical bytes.
  (Strictly, `Json` values that differ only in `RBNode` balance share a
  compress image; those are semantically the same object, and the
  assumption identifies the value with its canonical bytes.)
* `A-PARSE` (`AssumptionParse`): re-parsing canonical bytes lands on a
  value with the SAME canonical bytes (`compress ∘ parse ∘ compress =
  compress`). `Json.parse` is a `partial def` with no equational lemmas, so
  this is not provable in-kernel; it is exactly what the host
  re-derivation theorem (`commitment_rederivation_stable`) buys with it —
  nothing else below uses it.

BINDER DISCIPLINE: no theorem here hypothesises `enc a ≠ enc b`,
`compress a ≠ compress b`, or `sha256 _ ≠ sha256 _` about the two objects
under discussion. The assumptions are global injectivity statements; the
theorems bind the semantic `Effect`.
-/

namespace Seal

open Lean SealCore

/-- **PROPOSED** domain tag, part 0 of the stage-1 preimage.

    The old `seal.effect/v3` tag cannot be retained after adding `_meta`:
    otherwise an old four-part preimage and a changed-shape preimage would
    inhabit the same domain.  The final tag is a later representation ruling;
    changing this proposal invalidates all dependent hashes and vectors. -/
def effectDomainTag : String := "seal.effect/v4-proposed-meta-all"

/-- A structurally validated request `_meta`.

    `present` can contain every legal or unknown key because it stores the
    complete JSON object map, not a selected projection.  Field-level MCP
    validation happens before construction at the protocol boundary; this
    kernel type enforces the stage-1 shape fact that a present value is an
    object. -/
inductive ValidatedMeta where
  | absent
  | present (object : Std.TreeMap.Raw String Json compare)

namespace ValidatedMeta

/-- The complete present object as a JSON value. -/
def toJson? : ValidatedMeta → Option Json
  | .absent => none
  | .present object => some (.obj object)

/-- **PROPOSED** explicit metadata framing.  The second part is deliberately
    empty for absence; the first part is the collision-proof discriminator. -/
def preimageParts : ValidatedMeta → List String
  | .absent => ["meta.absent", ""]
  | .present object => ["meta.present", (Json.obj object).compress]

/-- Re-parse relation used by host re-derivation.  It preserves absence and,
    for a present object, parses its complete canonical JSON bytes back to a
    present object. -/
def ReparsedFrom : ValidatedMeta → ValidatedMeta → Prop
  | .absent, .absent => True
  | .present source, .present reparsed =>
      Json.parse (Json.obj source).compress = .ok (Json.obj reparsed)
  | _, _ => False

end ValidatedMeta

/-- The semantic object a commitment binds: which server, which tool, which
    (post-parse, canonical) argument value, and which complete structurally
    validated `_meta` presence/value. NO kernel identity — that lives in the
    approval preimage only. -/
structure Effect where
  server : String
  tool : String
  arguments : Json
  metadata : ValidatedMeta

/-- The stage-1 proposed preimage, in explicit order. -/
def Effect.preimageParts (e : Effect) : List String :=
  [effectDomainTag, e.server, e.tool, e.arguments.compress] ++ e.metadata.preimageParts

/-- THE effect commitment: netstring-framed preimage, SHA-256, lowercase
    64-char hex. Reuses `stableHashParts` (= `sha256Digest ∘ String.toUTF8 ∘
    encodeParts`) and the existing `Digest256.toHex`. -/
def Effect.commitment (e : Effect) : String :=
  (stableHashParts e.preimageParts).toHex

/-- Structural pin for the frisk: the preimage is exactly the proposed new
    tag, server, tool, canonical arguments, then the explicit complete metadata
    presence/value suffix. `kernel_identity` remains nowhere. -/
theorem preimage_shape (e : Effect) :
    e.preimageParts =
      ["seal.effect/v4-proposed-meta-all", e.server, e.tool, e.arguments.compress] ++
        e.metadata.preimageParts := rfl

/-- The exact absent shape. -/
theorem preimage_shape_absent (server tool : String) (arguments : Json) :
    Effect.preimageParts ⟨server, tool, arguments, .absent⟩ =
      ["seal.effect/v4-proposed-meta-all", server, tool, arguments.compress,
        "meta.absent", ""] := rfl

/-- The exact present shape, including the complete canonical object. -/
theorem preimage_shape_present (server tool : String) (arguments : Json)
    (object : Std.TreeMap.Raw String Json compare) :
    Effect.preimageParts ⟨server, tool, arguments, .present object⟩ =
      ["seal.effect/v4-proposed-meta-all", server, tool, arguments.compress,
        "meta.present", (Json.obj object).compress] := rfl

/-! ## Named assumptions -/

/-- A-CR: idealised perfect injectivity of the digest pipeline over UTF-8
    strings, at the lowercase-hex surface
    (`(stableHashString ·).toHex = sha256HexStr ·`). Strictly stronger than
    SHA-256 collision resistance: it asserts no collision EXISTS, which a
    fixed-output hash over unbounded inputs cannot satisfy, so real SHA-256
    does not satisfy this Prop. It is consumed only as a hypothesis — never
    proved, never axiomatised — and theorems conditional on it hold in the
    idealised collision-free model, not for real SHA-256. See the module
    docstring and `docs/ASSUMPTIONS.md`. -/
def AssumptionCR : Prop :=
  ∀ a b : String, (stableHashString a).toHex = (stableHashString b).toHex → a = b

/-- A-ENC: injectivity of the netstring part framing. No longer an
    assumption in substance: `Seal.Encoding.assumptionEncInjective_holds`
    (K5, `Seal/EncodingInjective.lean`) proves it in-repo, and
    `Seal.Encoding.effect_commitment_injective_of_cr_compress` consumes the
    theorems below with this hypothesis discharged. The `Prop` stays named so
    existing statements and the seal-host discharge remain valid. -/
def AssumptionEncInjective : Prop :=
  ∀ a b : List String, encodeParts a = encodeParts b → a = b

/-- A-COMPRESS: canonical serialization is injective on `Json`. -/
def AssumptionCompressInjective : Prop :=
  ∀ a b : Json, a.compress = b.compress → a = b

/-- A-PARSE: canonical bytes are a fixed point of parse-then-compress. What
    it buys (only): `commitment_rederivation_stable` — a host that re-parses
    the canonical argument bytes recovers the same commitment. -/
def AssumptionParse : Prop :=
  ∀ (a a' : Json), Json.parse a.compress = .ok a' → a'.compress = a.compress

/-! ## Theorems -/

/-- **Injectivity of the effect commitment**, bound at the semantic
    `Effect`, conditional on A-CR + A-ENC + A-COMPRESS. Equal commitments
    force equal server, equal tool, and equal argument VALUE. -/
theorem effect_commitment_injective
    (hcr : AssumptionCR) (henc : AssumptionEncInjective)
    (hcompress : AssumptionCompressInjective)
    (e₁ e₂ : Effect) (h : e₁.commitment = e₂.commitment) : e₁ = e₂ := by
  have hstr : encodeParts e₁.preimageParts = encodeParts e₂.preimageParts :=
    hcr _ _ h
  have hparts : e₁.preimageParts = e₂.preimageParts := henc _ _ hstr
  obtain ⟨s₁, t₁, a₁, m₁⟩ := e₁
  obtain ⟨s₂, t₂, a₂, m₂⟩ := e₂
  cases m₁ with
  | absent =>
      cases m₂ with
      | absent =>
          have hs : s₁ = s₂ := by
            have hi := congrArg (fun parts : List String => parts[1]?) hparts
            simpa [Effect.preimageParts, ValidatedMeta.preimageParts] using hi
          have ht : t₁ = t₂ := by
            have hi := congrArg (fun parts : List String => parts[2]?) hparts
            simpa [Effect.preimageParts, ValidatedMeta.preimageParts] using hi
          have hc : a₁.compress = a₂.compress := by
            have hi := congrArg (fun parts : List String => parts[3]?) hparts
            simpa [Effect.preimageParts, ValidatedMeta.preimageParts] using hi
          have harguments : a₁ = a₂ := hcompress _ _ hc
          clear h hstr hparts hc
          cases hs
          cases ht
          cases harguments
          rfl
      | present object₂ =>
          simp [Effect.preimageParts, ValidatedMeta.preimageParts] at hparts
  | present object₁ =>
      cases m₂ with
      | absent =>
          simp [Effect.preimageParts, ValidatedMeta.preimageParts] at hparts
      | present object₂ =>
          have hs : s₁ = s₂ := by
            have hi := congrArg (fun parts : List String => parts[1]?) hparts
            simpa [Effect.preimageParts, ValidatedMeta.preimageParts] using hi
          have ht : t₁ = t₂ := by
            have hi := congrArg (fun parts : List String => parts[2]?) hparts
            simpa [Effect.preimageParts, ValidatedMeta.preimageParts] using hi
          have hc : a₁.compress = a₂.compress := by
            have hi := congrArg (fun parts : List String => parts[3]?) hparts
            simpa [Effect.preimageParts, ValidatedMeta.preimageParts] using hi
          have hm : (Json.obj object₁).compress = (Json.obj object₂).compress := by
            have hi := congrArg (fun parts : List String => parts[5]?) hparts
            simpa [Effect.preimageParts, ValidatedMeta.preimageParts] using hi
          have harguments : a₁ = a₂ := hcompress _ _ hc
          have hmeta : Json.obj object₁ = Json.obj object₂ :=
            hcompress _ _ hm
          clear h hstr hparts hc hm
          have hobject : object₁ = object₂ := Json.obj.inj hmeta
          clear hmeta
          cases hs
          cases ht
          cases harguments
          cases hobject
          rfl

/-- **The commitment check.** The host's re-derivation agrees with the
    kernel's value iff they are talking about the same effect. -/
theorem commitment_check_iff
    (hcr : AssumptionCR) (henc : AssumptionEncInjective)
    (hcompress : AssumptionCompressInjective)
    (kernel host : Effect) :
    kernel.commitment = host.commitment ↔ kernel = host :=
  ⟨effect_commitment_injective hcr henc hcompress kernel host,
   fun h => h ▸ rfl⟩

/-- **Host re-derivation stability** (the A-PARSE theorem): a consumer that
    holds the canonical argument bytes and the complete metadata
    presence/canonical object bytes, re-parses them, and re-derives the
    commitment gets the kernel's value back. -/
theorem commitment_rederivation_stable
    (hparse : AssumptionParse) (e : Effect) (args' : Json)
    (metadata' : ValidatedMeta)
    (hargs : Json.parse e.arguments.compress = .ok args')
    (hmeta : ValidatedMeta.ReparsedFrom e.metadata metadata') :
    Effect.commitment { e with arguments := args', metadata := metadata' } = e.commitment := by
  have hargsCompress : args'.compress = e.arguments.compress :=
    hparse _ _ hargs
  cases emeta : e.metadata with
  | absent =>
      cases metadata' with
      | absent =>
          apply congrArg (fun parts => (stableHashParts parts).toHex)
          simp [Effect.preimageParts, ValidatedMeta.preimageParts, emeta,
            hargsCompress]
      | present object =>
          simp [ValidatedMeta.ReparsedFrom, emeta] at hmeta
  | present source =>
      cases metadata' with
      | absent =>
          simp [ValidatedMeta.ReparsedFrom, emeta] at hmeta
      | present reparsed =>
          have hmetaCompress :
              (Json.obj reparsed).compress = (Json.obj source).compress :=
            hparse _ _ (by simpa [ValidatedMeta.ReparsedFrom, emeta] using hmeta)
          apply congrArg (fun parts => (stableHashParts parts).toHex)
          simp [Effect.preimageParts, ValidatedMeta.preimageParts, emeta,
            hargsCompress, hmetaCompress]

/-! ## Non-vacuity at the preimage level (no hash evaluation needed) -/

/-- Same arguments under two different tools have different preimages —
    the envelope is not decorative. (The hash level is pinned by the
    emitted vector file and the `#eval` pin below.) -/
theorem preimage_separates_tools (server : String) (args : Json)
    (metadata : ValidatedMeta) (t₁ t₂ : String) (h : t₁ ≠ t₂) :
    Effect.preimageParts ⟨server, t₁, args, metadata⟩ ≠
      Effect.preimageParts ⟨server, t₂, args, metadata⟩ := by
  intro hparts
  have hprefix :
      [effectDomainTag, server, t₁, args.compress] =
        [effectDomainTag, server, t₂, args.compress] :=
    List.append_cancel_right hparts
  simp at hprefix
  exact h hprefix

/-- Same tool under two different servers: different preimages. -/
theorem preimage_separates_servers (tool : String) (args : Json)
    (metadata : ValidatedMeta) (s₁ s₂ : String) (h : s₁ ≠ s₂) :
    Effect.preimageParts ⟨s₁, tool, args, metadata⟩ ≠
      Effect.preimageParts ⟨s₂, tool, args, metadata⟩ := by
  intro hparts
  have hprefix :
      [effectDomainTag, s₁, tool, args.compress] =
        [effectDomainTag, s₂, tool, args.compress] :=
    List.append_cancel_right hparts
  simp at hprefix
  exact h hprefix

/-! ## Compiled-evaluation pins (real SHA-256, build-gated) -/

/-- info: true -/
#guard_msgs in #eval
  Effect.commitment ⟨"srv", "tool_a", Json.mkObj [], .absent⟩
    != Effect.commitment ⟨"srv", "tool_b", Json.mkObj [], .absent⟩

/-- info: true -/
#guard_msgs in #eval
  let c := Effect.commitment ⟨"srv", "tool_a", Json.mkObj [], .absent⟩
  c.length == 64 && c.toList.all fun ch => ch.isDigit || ('a' ≤ ch && ch ≤ 'f')

end Seal
