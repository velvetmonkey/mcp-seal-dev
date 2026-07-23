/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Data.Json
import Seal.Hash

/-!
# The effect commitment — pinned preimage, injectivity under named assumptions

Stage A of the effect-commitment plan. The ONE canonical commitment:

    effect_commitment = SHA256(encodeParts ["seal.effect/v3", server, tool, args.compress])
                        → lowercase hex, 64 chars

Exactly four parts, exactly that order, domain tag as part 0.

* `encodeParts` is REUSED (netstring framing, `Seal.Hash`): its injectivity
  obligation is already discharged in seal-host `Host/CapabilityAdequacy`;
  no new framing, no second obligation.
* `server` and `tool` are INSIDE the preimage: identical arguments under a
  different tool (or server) must never share a commitment.
* The version tag is INSIDE the digest: a later commitment shape is
  distinguishable from this one, and the effect preimage cannot collide
  with the approval preimage over the same alphabet.
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

/-- Pinned domain tag, part 0 of the preimage. -/
def effectDomainTag : String := "seal.effect/v3"

/-- The semantic object a commitment binds: which server, which tool, which
    (post-parse, canonical) argument value. NO kernel identity — that lives
    in the approval preimage only. -/
structure Effect where
  server : String
  tool : String
  arguments : Json

/-- The pinned four-part preimage, in pinned order. -/
def Effect.preimageParts (e : Effect) : List String :=
  [effectDomainTag, e.server, e.tool, e.arguments.compress]

/-- THE effect commitment: netstring-framed preimage, SHA-256, lowercase
    64-char hex. Reuses `stableHashParts` (= `sha256Digest ∘ String.toUTF8 ∘
    encodeParts`) and the existing `Digest256.toHex`. -/
def Effect.commitment (e : Effect) : String :=
  (stableHashParts e.preimageParts).toHex

/-- Structural pin for the frisk: the preimage is exactly
    `[tag, server, tool, args.compress]` — `server` and `tool` inside,
    `kernel_identity` nowhere (the `Effect` type has no such field). -/
theorem preimage_shape (e : Effect) :
    e.preimageParts = ["seal.effect/v3", e.server, e.tool, e.arguments.compress] := rfl

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
  obtain ⟨s₁, t₁, a₁⟩ := e₁
  obtain ⟨s₂, t₂, a₂⟩ := e₂
  simp only [Effect.preimageParts, List.cons.injEq, and_true] at hparts
  obtain ⟨-, hs, ht, hc⟩ := hparts
  cases hs; cases ht; cases hcompress _ _ hc
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
    holds the canonical argument bytes, re-parses them, and re-derives the
    commitment gets the kernel's value back. -/
theorem commitment_rederivation_stable
    (hparse : AssumptionParse) (e : Effect) (args' : Json)
    (h : Json.parse e.arguments.compress = .ok args') :
    Effect.commitment { e with arguments := args' } = e.commitment := by
  simp only [Effect.commitment, Effect.preimageParts, hparse _ _ h]

/-! ## Non-vacuity at the preimage level (no hash evaluation needed) -/

/-- Same arguments under two different tools have different preimages —
    the envelope is not decorative. (The hash level is pinned by the
    emitted vector file and the `#eval` pin below.) -/
theorem preimage_separates_tools (server : String) (args : Json)
    (t₁ t₂ : String) (h : t₁ ≠ t₂) :
    Effect.preimageParts ⟨server, t₁, args⟩ ≠ Effect.preimageParts ⟨server, t₂, args⟩ := by
  intro hparts
  simp only [Effect.preimageParts, List.cons.injEq] at hparts
  exact h hparts.2.2.1

/-- Same tool under two different servers: different preimages. -/
theorem preimage_separates_servers (tool : String) (args : Json)
    (s₁ s₂ : String) (h : s₁ ≠ s₂) :
    Effect.preimageParts ⟨s₁, tool, args⟩ ≠ Effect.preimageParts ⟨s₂, tool, args⟩ := by
  intro hparts
  simp only [Effect.preimageParts, List.cons.injEq] at hparts
  exact h hparts.2.1

/-! ## Compiled-evaluation pins (real SHA-256, build-gated) -/

/-- info: true -/
#guard_msgs in #eval
  Effect.commitment ⟨"srv", "tool_a", Json.mkObj []⟩
    != Effect.commitment ⟨"srv", "tool_b", Json.mkObj []⟩

/-- info: true -/
#guard_msgs in #eval
  let c := Effect.commitment ⟨"srv", "tool_a", Json.mkObj []⟩
  c.length == 64 && c.toList.all fun ch => ch.isDigit || ('a' ≤ ch && ch ≤ 'f')

end Seal
