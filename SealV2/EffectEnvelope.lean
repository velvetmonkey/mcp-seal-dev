/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.Decide

/-!
# V2.3 effect envelope — `seal.effect/v2` (Stage B strip, E1★ ballot)

**What this module is.** The V2.3 signed message shape and its proof package.
Seal bumps the signed request envelope from V2.2 (`seal/v2.2/principal-envelope`,
host-side `Host/Principal.lean` in seal-host) to ONE signed object carrying the
fields that are actually authenticated AND interpreted. The original
`seal.effect/v1` layout (council `bf01363f`) seated every candidate field; the
E1★ ballot (Ben, 2026-07-22) killed the uninterpreted seats and Stage B strips
them from the signed message:

**Killed and STRIPPED (E1★):** F4 `idempotency_key`, F5 `policy_version`,
F6 `on_behalf_of` / `parent_capability_ref`, and the eighth-field trio
`audience` / `causality_token` / `expires_at`. Why they are gone, not seated:
* A null seat does NOT save the repin it exists for: if v4 were to give a
  today-ignored field semantics, the same bytes would carry two meanings, and
  distinguishing them needs a domain-tag bump — which IS the repin. The seat
  defers nothing and costs seven unvalidated authenticated fields.
* Malleability: receipts identical in every meaningful respect but differing
  in a seat are distinct signatures over distinct messages — two objects for
  one decision to anything that dedupes or identity-keys receipts.
* `expires_at` was signed, security-sounding, and never checked — a
  claim-drift trap in an artifact headed for a 90-day freeze.

**Bound fields, retained (unchanged in meaning from `seal.effect/v1`):**
* BIND `line` by value — the exact judged bytes, never digest-downgraded,
  framed (`u64be(len) ‖ bytes`) like every variable-width field.
* BIND `authority` (32 raw bytes), `keyId`, `nonce` (32 raw bytes), `issuedAt`
  — the V2.2 Fix B config-authority bind, folded in unchanged in meaning.
* BIND F1 `adapter{type,version}` — host must equality-check against the
  adapter that actually mediated (`adapter_bind` / `adapter_mismatch_blocks`).
* BIND (conditional) F2 `principal.session` — the approval/replay-namespace
  SESSION PLANE (`ApprovalState.session`, the value the SIGNED CONFIG names —
  the same plane as `Host.Provenance.bootAssigner` and
  `replayNamespace_trusted_plane`), explicitly NOT the receipt pid string.
  Implemented as equality-when-nonempty (`session_plane_equality`,
  `session_spoof_blocks`); empty = seat, so if client-visible session issuance
  slips the cycle nothing breaks and the slot needs no re-bump.
* BIND-optional F3 `effect{resource,action,args}` — ADVISORY but INTERPRETED:
  equality-enforced against the parser-derived effect (`mcp_effect_equality`),
  never the decision value (`effect_step_presence_not_value`). The F3 triple
  is under a SEPARATE, FLAGGED strip decision (the ballot realized F3 as the
  kernel-computed `effect_commitment`); it is deliberately NOT stripped here.
* BIND F7 `revocation_subject` — retained by the ballot's keep-list.
* Encoding: every variable-width field `u64be(len) ‖ bytes`; fixed-width
  fields raw (authority 32, nonce 32, u64be at 8).

**The proof package** (full-tuple injectivity alone is necessary, NOT
sufficient — both council seats):
1. `effect_message_injective` — equal messages ⇒ equal (authority, full field
   tuple), under wire-width constraints; `verified_effect_injective` discharges
   the width constraints from the runtime checks, so for VERIFIED envelopes
   injectivity is unconditional.
2. Framing lemmas — `u64be_inj` (width-checked), `u64be_cancel`,
   `sized_cancel`, `frame_cancel`, `frame_inj`: every variable-width field is
   length-framed and append-injective; no field can splice into another.
3. Advisory non-influence — `effect_step_presence_not_value` /
   `advisory_non_influence` / `allow_value_from_line_and_state`: the decision
   VALUE is `SealV2.decide e.line state` — a function of the judged line and
   the trusted config/state only. Envelope fields (advisory ones included) gate
   only WHETHER a decision is produced, never WHICH bytes are allowed.
4. MCP effect-equality — `mcp_effect_equality` / `mcp_effect_mismatch_blocks` /
   `nonmcp_nonempty_effect_blocks`: a non-empty signed effect must equal the
   effect derived from the judged line by the VERIFIED parser, else fail
   closed. Without this, injectivity would authenticate a lie (confused
   deputy): the signature would bind an effect claim nobody checked.
5. Session-plane equality — `session_plane_equality` / `session_spoof_blocks`:
   a client-signed session never ENTERS the judgment plane; it is
   equality-checked against the boot/config session and otherwise blocks.
6. Cross-version + cross-plane separation — `effect_cross_version_v1_separated`
   (the Stage B strip is a REAL version bump: no `seal.effect/v1` receipt can
   verify under `seal.effect/v2`, nor vice versa),
   `effect_cross_version_v22_separated`, `effect_cross_version_v21_separated`,
   `effect_cross_plane_separated`: no byte string is both a `seal.effect/v2`
   message and a v1/V2.2/V2.1 envelope message or a `{`-prefixed
   canonical-JSON payload (config plane AND the approval signed-message
   plane — both are canonical JSON objects).

**Trusted, named, never proven (the crypto TCB at this seam)** — unchanged
from V2.2: `ed25519Verify` extern faithfulness; Ed25519 existential
unforgeability; nonce-freshness (A3, Rust seam); key custody / rotation /
revocation-by-re-sign; that the `authority` bytes threaded in ARE the config
trust root (pinned by construction at init, host-side).
-/

namespace SealV2.Effect

/-! ## Wire primitives: u64be and the length frame -/

/-- 8-byte big-endian encoding of a (u64-ranged) natural — fixed-width so the
    signed message framing is injective without separators. Same layout as the
    V2.2 `Host.u64be`; restated kernel-side because V2.3 makes the shape a
    kernel contract. -/
def u64be (n : Nat) : ByteArray :=
  ByteArray.mk #[
    UInt8.ofNat (n >>> 56), UInt8.ofNat (n >>> 48), UInt8.ofNat (n >>> 40),
    UInt8.ofNat (n >>> 32), UInt8.ofNat (n >>> 24), UInt8.ofNat (n >>> 16),
    UInt8.ofNat (n >>> 8), UInt8.ofNat n]

theorem u64be_size (n : Nat) : (u64be n).size = 8 := rfl

/-- `u64be` is injective below `2^64` (the wire range). The framing lemma every
    length prefix stands on. -/
theorem u64be_inj {n m : Nat} (hn : n < 2 ^ 64) (hm : m < 2 ^ 64)
    (h : u64be n = u64be m) : n = m := by
  have hl : [UInt8.ofNat (n >>> 56), UInt8.ofNat (n >>> 48), UInt8.ofNat (n >>> 40),
      UInt8.ofNat (n >>> 32), UInt8.ofNat (n >>> 24), UInt8.ofNat (n >>> 16),
      UInt8.ofNat (n >>> 8), UInt8.ofNat n]
      = [UInt8.ofNat (m >>> 56), UInt8.ofNat (m >>> 48), UInt8.ofNat (m >>> 40),
      UInt8.ofNat (m >>> 32), UInt8.ofNat (m >>> 24), UInt8.ofNat (m >>> 16),
      UInt8.ofNat (m >>> 8), UInt8.ofNat m] :=
    congrArg (fun b : ByteArray => b.data.toList) h
  simp only [List.cons.injEq, and_true] at hl
  obtain ⟨h7, h6, h5, h4, h3, h2, h1, h0⟩ := hl
  have e7 := congrArg UInt8.toNat h7
  have e6 := congrArg UInt8.toNat h6
  have e5 := congrArg UInt8.toNat h5
  have e4 := congrArg UInt8.toNat h4
  have e3 := congrArg UInt8.toNat h3
  have e2 := congrArg UInt8.toNat h2
  have e1 := congrArg UInt8.toNat h1
  have e0 := congrArg UInt8.toNat h0
  simp only [UInt8.toNat_ofNat', Nat.shiftRight_eq_div_pow] at e7 e6 e5 e4 e3 e2 e1 e0
  omega

/-- One variable-width field on the wire: `u64be(byte length) ‖ UTF-8 bytes`. -/
def frame (s : String) : ByteArray :=
  u64be s.utf8ByteSize ++ s.toUTF8

/-! ## Framing cancellation lemmas — the anti-splice kit

Each lemma peels ONE field off the front of an equal pair of messages and
returns the field equality plus the equality of the remainders. Missing one
variable-width field's frame is exactly the splice the council flagged; the
kit makes every field's peel explicit. -/

/-- Fixed-width peel: equal-size prefixes cancel. -/
theorem sized_cancel {k : Nat} {a₁ a₂ r₁ r₂ : ByteArray}
    (h₁ : a₁.size = k) (h₂ : a₂.size = k)
    (h : a₁ ++ r₁ = a₂ ++ r₂) : a₁ = a₂ ∧ r₁ = r₂ := by
  have ha : a₁ = a₂ := ByteArray.append_inj_left h (h₁.trans h₂.symm)
  rw [ha, ByteArray.append_right_inj] at h
  exact ⟨ha, h⟩

/-- u64be peel: the 8-byte prefix cancels and the values agree (wire range). -/
theorem u64be_cancel {n₁ n₂ : Nat} {r₁ r₂ : ByteArray}
    (h₁ : n₁ < 2 ^ 64) (h₂ : n₂ < 2 ^ 64)
    (h : u64be n₁ ++ r₁ = u64be n₂ ++ r₂) : n₁ = n₂ ∧ r₁ = r₂ := by
  have hb : u64be n₁ = u64be n₂ := ByteArray.append_inj_left h rfl
  have hn : n₁ = n₂ := u64be_inj h₁ h₂ hb
  rw [hb, ByteArray.append_right_inj] at h
  exact ⟨hn, h⟩

/-- Variable-width peel: a length-framed field cancels — the length prefixes
    agree (u64be injectivity), so the field bytes split at the same boundary,
    so the fields agree (UTF-8 injectivity) and the remainders agree. THE
    anti-splice lemma: no tail of one field can leak into the next. -/
theorem frame_cancel {s₁ s₂ : String} {r₁ r₂ : ByteArray}
    (h₁ : s₁.utf8ByteSize < 2 ^ 64) (h₂ : s₂.utf8ByteSize < 2 ^ 64)
    (h : frame s₁ ++ r₁ = frame s₂ ++ r₂) : s₁ = s₂ ∧ r₁ = r₂ := by
  unfold frame at h
  simp only [ByteArray.append_assoc] at h
  obtain ⟨hsz, h⟩ := u64be_cancel h₁ h₂ h
  have hu : s₁.toUTF8 = s₂.toUTF8 := ByteArray.append_inj_left h (by
    simpa [String.toUTF8_eq_toByteArray, String.size_toByteArray] using hsz)
  rw [hu, ByteArray.append_right_inj] at h
  refine ⟨?_, h⟩
  simpa [String.toUTF8_eq_toByteArray, String.toByteArray_inj] using hu

/-- Terminal-field peel: equal frames with NOTHING after them force equal
    strings — `frame_cancel` specialized to empty remainders, for the last
    field of the message. -/
theorem frame_inj {s₁ s₂ : String}
    (h₁ : s₁.utf8ByteSize < 2 ^ 64) (h₂ : s₂.utf8ByteSize < 2 ^ 64)
    (h : frame s₁ = frame s₂) : s₁ = s₂ :=
  (frame_cancel h₁ h₂ (congrArg (· ++ ByteArray.empty) h)).1

/-! ## Domain tags -/

/-- Domain-separation tag for Stage B effect envelopes: `seal.effect/v2`.
    The v1→v2 bump IS the strip: `seal.effect/v1` signed seven fields this
    layout no longer carries, so a tag bump is mandatory — otherwise one byte
    string could be a valid v1 message and a valid stripped message with
    different semantics. Distinct from the retired `effectTagV1` at byte 13
    (`'2'` vs `'1'`), from both retired principal-envelope tags at byte 4
    (`.` vs `/`), and from every canonical-JSON plane at byte 0 (`s` vs `{`).
    The trailing NUL terminates the tag unambiguously.

    NOT in this lineage: the Stage A commitment preimage tag
    `seal.effect/v3` (`Seal.effectDomainTag`). That string is part 0 of a
    NETSTRING-framed hash preimage — on the wire it only ever appears inside
    `encodeParts` output, which begins with an ASCII digit and carries no
    NUL — never as a raw signed-message prefix. The two planes are
    byte-separated at offset 0; the version numbers are lineage-local. -/
def effectTag : String := "seal.effect/v2\x00"

/-- The RETIRED Stage A/`bf01363f` envelope tag. SPEC-ONLY: kept so the
    v1→v2 cross-version separation is a theorem, not a changelog note. Every
    retired-layout message is `effectTagV1.toUTF8 ++ rest` for some `rest`,
    so `effect_cross_version_v1_separated` covers the entire retired layout
    without restating its 18-field shape. -/
def effectTagV1 : String := "seal.effect/v1\x00"

/-- The RETIRED V2.2 tag. SPEC-ONLY: kept so cross-version separation is a
    theorem, not a changelog note. -/
def envelopeTagV22 : String := "seal/v2.2/principal-envelope\x00"

/-- The RETIRED V2.1 tag. SPEC-ONLY, same purpose. -/
def envelopeTagV21 : String := "seal/v2.1/principal-envelope\x00"

/-! ## The envelope and its message bytes -/

/-- The Stage B effect envelope — every field both authenticated AND
    interpreted; the E1★ killed seats (F4, F5, F6, eighth-field trio) are
    STRIPPED from the structure, so a killed field cannot even be expressed,
    let alone signed. Raw request fields exactly as marshalled; only
    `verifyEffect` gives them meaning. `authority` is NOT a field: it is the
    config trust root, threaded in by the session (never request data). -/
structure EffectEnvelope where
  /-- Wire-claimed registry id (Fix B bind). -/
  keyId : String
  /-- 32 raw bytes (width enforced by `verifyEffect`). -/
  nonce : ByteArray
  issuedAt : Nat
  /-- THE judged line, bound BY VALUE (non-negotiable). -/
  line : String
  /-- F1: the adapter the client believes is mediating. -/
  adapterType : String
  adapterVersion : String
  /-- F2: session plane; `""` = seat (unset). -/
  session : String
  /-- F3 (advisory, INTERPRETED — separate flagged strip decision):
      claimed effect; all-`""` = unset. -/
  effectResource : String
  effectAction : String
  effectArgs : String
  /-- F7: revocation subject (ballot keep-list). -/
  revocationSubject : String
  deriving BEq

/-- **The canonical signed message** — the cross-language contract:

        tag ‖ authority(32) ‖ frame(keyId) ‖ nonce(32) ‖ u64be(issuedAt)
            ‖ frame(line)
            ‖ frame(adapterType) ‖ frame(adapterVersion)
            ‖ frame(session)
            ‖ frame(effectResource) ‖ frame(effectAction) ‖ frame(effectArgs)
            ‖ frame(revocationSubject)

    with `frame(s) = u64be(|s| in UTF-8 bytes) ‖ s-bytes`. Every field is
    either fixed-width or length-framed, so the encoding is injective in the
    FULL tuple (`effect_message_injective`); no separate digest needed
    (Ed25519 hashes internally). -/
def effectMessage (authority : ByteArray) (e : EffectEnvelope) : ByteArray :=
  effectTag.toUTF8 ++ authority
    ++ frame e.keyId ++ e.nonce ++ u64be e.issuedAt
    ++ frame e.line
    ++ frame e.adapterType ++ frame e.adapterVersion
    ++ frame e.session
    ++ frame e.effectResource ++ frame e.effectAction ++ frame e.effectArgs
    ++ frame e.revocationSubject

/-- The RETIRED V2.2 message layout (spec-only; layout frozen in
    `Host/Principal.lean`), kept so cross-version separation is a theorem. -/
def envelopeMessageV22 (authority : ByteArray) (keyId : String)
    (nonce : ByteArray) (issuedAt : Nat) (line : String) : ByteArray :=
  envelopeTagV22.toUTF8 ++ authority ++ u64be keyId.utf8ByteSize ++ keyId.toUTF8
    ++ nonce ++ u64be issuedAt ++ line.toUTF8

/-- The RETIRED V2.1 message layout (spec-only). -/
def envelopeMessageV21 (nonce : ByteArray) (issuedAt : Nat) (line : String) :
    ByteArray :=
  envelopeTagV21.toUTF8 ++ nonce ++ u64be issuedAt ++ line.toUTF8

/-! ## Wire-width constraints -/

/-- The wire-range side conditions injectivity needs: nonce fixed at 32,
    every u64be argument (lengths, issuedAt) in u64 range.
    `verifyEffect` CHECKS all of these at runtime (`wireSizedB`), so verified
    envelopes satisfy them by theorem (`verifyEffect_wireSized`). -/
structure WireSized (e : EffectEnvelope) : Prop where
  nonce32 : e.nonce.size = 32
  keyId : e.keyId.utf8ByteSize < 2 ^ 64
  issuedAt : e.issuedAt < 2 ^ 64
  line : e.line.utf8ByteSize < 2 ^ 64
  adapterType : e.adapterType.utf8ByteSize < 2 ^ 64
  adapterVersion : e.adapterVersion.utf8ByteSize < 2 ^ 64
  session : e.session.utf8ByteSize < 2 ^ 64
  effectResource : e.effectResource.utf8ByteSize < 2 ^ 64
  effectAction : e.effectAction.utf8ByteSize < 2 ^ 64
  effectArgs : e.effectArgs.utf8ByteSize < 2 ^ 64
  revocationSubject : e.revocationSubject.utf8ByteSize < 2 ^ 64

/-- Decidable form of `WireSized`, checked by `verifyEffect` at runtime. -/
def wireSizedB (e : EffectEnvelope) : Bool :=
  (e.nonce.size == 32)
    && Decidable.decide (e.keyId.utf8ByteSize < 2 ^ 64)
    && Decidable.decide (e.issuedAt < 2 ^ 64)
    && Decidable.decide (e.line.utf8ByteSize < 2 ^ 64)
    && Decidable.decide (e.adapterType.utf8ByteSize < 2 ^ 64)
    && Decidable.decide (e.adapterVersion.utf8ByteSize < 2 ^ 64)
    && Decidable.decide (e.session.utf8ByteSize < 2 ^ 64)
    && Decidable.decide (e.effectResource.utf8ByteSize < 2 ^ 64)
    && Decidable.decide (e.effectAction.utf8ByteSize < 2 ^ 64)
    && Decidable.decide (e.effectArgs.utf8ByteSize < 2 ^ 64)
    && Decidable.decide (e.revocationSubject.utf8ByteSize < 2 ^ 64)

theorem wireSizedB_spec {e : EffectEnvelope} (h : wireSizedB e = true) :
    WireSized e := by
  unfold wireSizedB at h
  simp only [Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at h
  obtain ⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨h0, h1⟩, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩, h7⟩, h8⟩, h9⟩, h10⟩ := h
  exact ⟨h0, h1, h2, h3, h4, h5, h6, h7, h8, h9, h10⟩

/-! ## 1 + 2: full-tuple injectivity, by sequential peel -/

/-- **The Stage B bind, at the encoding.** Equal messages force equal
    authority AND an equal FULL field tuple — the `seal.effect/v1` theorem
    re-proven over the narrowed tuple, same strength. Each variable-width
    field is peeled by `frame_cancel` (terminal field by `frame_inj`); miss
    one and adjacent fields would splice — this proof is the machine-checked
    witness that none is missed. -/
theorem effect_message_injective {authority₁ authority₂ : ByteArray}
    {e₁ e₂ : EffectEnvelope}
    (ha₁ : authority₁.size = 32) (ha₂ : authority₂.size = 32)
    (hw₁ : WireSized e₁) (hw₂ : WireSized e₂)
    (h : effectMessage authority₁ e₁ = effectMessage authority₂ e₂) :
    authority₁ = authority₂ ∧ e₁ = e₂ := by
  unfold effectMessage at h
  simp only [ByteArray.append_assoc] at h
  rw [ByteArray.append_right_inj] at h
  obtain ⟨hauth, h⟩ := sized_cancel ha₁ ha₂ h
  obtain ⟨hkeyId, h⟩ := frame_cancel hw₁.keyId hw₂.keyId h
  obtain ⟨hnonce, h⟩ := sized_cancel hw₁.nonce32 hw₂.nonce32 h
  obtain ⟨hissuedAt, h⟩ := u64be_cancel hw₁.issuedAt hw₂.issuedAt h
  obtain ⟨hline, h⟩ := frame_cancel hw₁.line hw₂.line h
  obtain ⟨hadapterType, h⟩ := frame_cancel hw₁.adapterType hw₂.adapterType h
  obtain ⟨hadapterVersion, h⟩ :=
    frame_cancel hw₁.adapterVersion hw₂.adapterVersion h
  obtain ⟨hsession, h⟩ := frame_cancel hw₁.session hw₂.session h
  obtain ⟨heffectResource, h⟩ :=
    frame_cancel hw₁.effectResource hw₂.effectResource h
  obtain ⟨heffectAction, h⟩ := frame_cancel hw₁.effectAction hw₂.effectAction h
  obtain ⟨heffectArgs, h⟩ := frame_cancel hw₁.effectArgs hw₂.effectArgs h
  have hrevocationSubject : e₁.revocationSubject = e₂.revocationSubject :=
    frame_inj hw₁.revocationSubject hw₂.revocationSubject h
  refine ⟨hauth, ?_⟩
  cases e₁; cases e₂
  simp only [EffectEnvelope.mk.injEq]
  exact ⟨hkeyId, hnonce, hissuedAt, hline, hadapterType, hadapterVersion,
    hsession, heffectResource, heffectAction, heffectArgs, hrevocationSubject⟩

/-! ## 6: cross-version + cross-plane domain separation -/

/-- Two byte strings with a distinguishing byte inside both prefixes never
    agree, whatever the tails — the one-lemma core of every separation
    theorem below. -/
theorem prefix_byte_separated {p₁ p₂ : ByteArray} {i : Nat}
    (hi₁ : i < p₁.size) (hi₂ : i < p₂.size)
    (hne : p₁[i]'hi₁ ≠ p₂[i]'hi₂) :
    ∀ r₁ r₂ : ByteArray, p₁ ++ r₁ ≠ p₂ ++ r₂ := by
  intro r₁ r₂ h
  apply hne
  have hL : i < (p₁ ++ r₁).size := by
    rw [ByteArray.size_append]; omega
  have hR : i < (p₂ ++ r₂).size := by
    rw [ByteArray.size_append]; omega
  calc p₁[i]'hi₁ = (p₁ ++ r₁)[i]'hL := (ByteArray.getElem_append_left hi₁).symm
    _ = (p₂ ++ r₂)[i]'hR := by simp only [h]
    _ = p₂[i]'hi₂ := ByteArray.getElem_append_left hi₂

/-- **Cross-version separation, v2 vs v1 — the Stage B acceptance theorem.**
    No byte string is both a `seal.effect/v2` message and ANY
    `seal.effect/v1`-tagged byte string (the retired 18-field layout signed
    messages of exactly that form): the tags differ at byte 13 (`'2'` vs
    `'1'`). A receipt signed under the seated v1 layout can never verify as a
    stripped v2 envelope, nor vice versa, modulo only Ed25519 verifying the
    exact message bytes. Quantifying over an ARBITRARY tail makes this
    stronger than a layout-to-layout statement: every retired v1 message is
    an instance of `effectTagV1.toUTF8 ++ rest`. -/
theorem effect_cross_version_v1_separated (authority : ByteArray)
    (e : EffectEnvelope) (rest : ByteArray) :
    effectMessage authority e ≠ effectTagV1.toUTF8 ++ rest := by
  unfold effectMessage
  simp only [ByteArray.append_assoc]
  exact prefix_byte_separated (i := 13) (by decide) (by decide) (by decide) _ rest

/-- **Cross-version separation, V2.3 vs V2.2.** No byte string is both a
    `seal.effect/v2` message and a `seal/v2.2/principal-envelope` message:
    the tags differ at byte 4 (`.` vs `/`). A V2.2 principal signature can
    never verify as a V2.3 effect envelope, nor vice versa, modulo only
    Ed25519 verifying the exact message bytes. -/
theorem effect_cross_version_v22_separated (authority : ByteArray)
    (e : EffectEnvelope) (a' : ByteArray) (k' : String) (n' : ByteArray)
    (t' : Nat) (l' : String) :
    effectMessage authority e ≠ envelopeMessageV22 a' k' n' t' l' := by
  unfold effectMessage envelopeMessageV22
  simp only [ByteArray.append_assoc]
  exact prefix_byte_separated (i := 4) (by decide) (by decide) (by decide) _ _

/-- **Cross-version separation, V2.3 vs V2.1.** Same distinguishing byte. -/
theorem effect_cross_version_v21_separated (authority : ByteArray)
    (e : EffectEnvelope) (n' : ByteArray) (t' : Nat) (l' : String) :
    effectMessage authority e ≠ envelopeMessageV21 n' t' l' := by
  unfold effectMessage envelopeMessageV21
  simp only [ByteArray.append_assoc]
  exact prefix_byte_separated (i := 4) (by decide) (by decide) (by decide) _ _

/-- **Cross-plane separation.** Every canonical-JSON plane signs bytes that
    begin with `{` (0x7b): the config plane (raw canonical payload) AND the
    V2 approval plane (`signedMessageRaw`, a canonical JSON object). An
    effect-envelope message begins with the tag byte `s` (0x73). So no byte
    string is both — an effect signature can never double as a config or
    approval signature, or vice versa. (The Stage A commitment preimage plane
    is separated the same way: `encodeParts` output begins with an ASCII
    digit, never `s`.) -/
theorem effect_cross_plane_separated (authority : ByteArray)
    (e : EffectEnvelope) (rest : ByteArray) :
    effectMessage authority e ≠ "{".toUTF8 ++ rest := by
  unfold effectMessage
  simp only [ByteArray.append_assoc]
  exact prefix_byte_separated (i := 0) (by decide) (by decide) (by decide) _ rest

/-! ## The verifier: registry, widths, signature — fail-closed -/

/-- One registered principal (id, Ed25519 verifying-key hex). The registry
    rides INSIDE the signed config — out-of-band trust, never request data.
    Kernel-side twin of `Host.PrincipalKey`. -/
structure PrincipalKey where
  id : String
  pubkey : String
  deriving Repr, BEq

abbrev PrincipalRegistry := List PrincipalKey

/-- The authenticated caller id. Private constructor: the sole producer in
    this module is `verifyEffect` — observation is free, construction is not
    (same discipline as `Host.AuthenticatedPrincipal`). -/
structure AuthenticatedId where
  private mk ::
  id : String
  deriving Repr, BEq, DecidableEq

/-- Exported because the constructor is private. -/
theorem AuthenticatedId.ext_id {p q : AuthenticatedId} (h : p.id = q.id) :
    p = q := by
  cases p; cases q; simpa using h

/-- **The sole smart constructor.** Fail-closed `none` on: unregistered keyId,
    malformed hex (key or sig), authority/pubkey width, ANY wire-width check
    (`wireSizedB` — nonce 32, every u64be argument in range), or verification
    failure. `some ⟨k.id⟩` ONLY when the registered key verifies the signature
    over `effectMessage authority e` — the full Stage B tuple. The extern
    result is only ever cased on as an opaque `Bool` (crypto TCB). -/
def verifyEffect (authority : ByteArray) (reg : PrincipalRegistry)
    (e : EffectEnvelope) (sigHex : String) : Option AuthenticatedId :=
  match reg.find? (fun k => k.id == e.keyId) with
  | none => none
  | some k =>
      match hexDecode? k.pubkey, hexDecode? sigHex with
      | some pk, some sig =>
          if authority.size == 32 && pk.size == 32 && wireSizedB e
              && ed25519Verify pk (effectMessage authority e) sig
          then some ⟨k.id⟩ else none
      | _, _ => none

/-- Verified envelopes satisfy every wire-width constraint: the runtime checks
    discharge the injectivity side conditions. -/
theorem verifyEffect_wireSized {authority : ByteArray}
    {reg : PrincipalRegistry} {e : EffectEnvelope} {sigHex : String}
    {p : AuthenticatedId}
    (h : verifyEffect authority reg e sigHex = some p) :
    authority.size = 32 ∧ WireSized e := by
  unfold verifyEffect at h
  split at h
  · cases h
  · split at h
    · split at h
      · next hcond =>
          simp only [Bool.and_eq_true, beq_iff_eq] at hcond
          exact ⟨hcond.1.1.1, wireSizedB_spec hcond.1.2⟩
      · cases h
    · cases h

/-- **Injectivity, unconditionally, for anything that verifies.** Two verified
    envelopes with equal message bytes are equal in authority and in the FULL
    field tuple — no width side conditions left: `verifyEffect` checked them.
    With Ed25519 verifying exact message bytes (TCB), one signature can only
    ever speak for ONE tuple. -/
theorem verified_effect_injective {authority₁ authority₂ : ByteArray}
    {reg₁ reg₂ : PrincipalRegistry} {e₁ e₂ : EffectEnvelope}
    {sig₁ sig₂ : String} {p₁ p₂ : AuthenticatedId}
    (h₁ : verifyEffect authority₁ reg₁ e₁ sig₁ = some p₁)
    (h₂ : verifyEffect authority₂ reg₂ e₂ sig₂ = some p₂)
    (hmsg : effectMessage authority₁ e₁ = effectMessage authority₂ e₂) :
    authority₁ = authority₂ ∧ e₁ = e₂ :=
  have hw₁ := verifyEffect_wireSized h₁
  have hw₂ := verifyEffect_wireSized h₂
  effect_message_injective hw₁.1 hw₂.1 hw₁.2 hw₂.2 hmsg

/-- **The envelope gates PRESENCE, never VALUE** (V2.2 idiom, V2.3 surface):
    whenever `verifyEffect` returns `some p`, `p.id` is the registry entry the
    keyId selected — a function of the config registry and the keyId lookup
    ONLY. Every other envelope field decides only whether `some` appears. -/
theorem effect_gates_presence_not_value (authority : ByteArray)
    (reg : PrincipalRegistry) (e : EffectEnvelope) (sigHex : String)
    (p : AuthenticatedId)
    (h : verifyEffect authority reg e sigHex = some p) :
    ∃ k, reg.find? (fun k => k.id == e.keyId) = some k ∧ p.id = k.id := by
  unfold verifyEffect at h
  split at h
  · cases h
  · next k hf =>
      refine ⟨k, hf, ?_⟩
      split at h
      · split at h
        · injection h with h
          subst h
          rfl
        · cases h
      · cases h

/-- Fail-closed: an unregistered keyId yields `none`. -/
theorem verifyEffect_none_of_unregistered (authority : ByteArray)
    (reg : PrincipalRegistry) (e : EffectEnvelope) (sigHex : String)
    (h : reg.find? (fun k => k.id == e.keyId) = none) :
    verifyEffect authority reg e sigHex = none := by
  unfold verifyEffect
  rw [h]

/-- Registry closure: every produced id is a registered id. -/
theorem verifyEffect_id_registered (authority : ByteArray)
    (reg : PrincipalRegistry) (e : EffectEnvelope) (sigHex : String)
    (p : AuthenticatedId)
    (h : verifyEffect authority reg e sigHex = some p) :
    ∃ k ∈ reg, k.id = p.id := by
  obtain ⟨k, hf, hid⟩ :=
    effect_gates_presence_not_value authority reg e sigHex p h
  exact ⟨k, List.mem_of_find?_eq_some hf, hid.symm⟩

/-! ## 3 + 4 + 5: the judgment pipeline and its gates

`effectStep` is the V2.3 judgment spec the host binds to at repin: verify the
envelope, equality-check the host-known facts (mediating adapter, boot/config
session, parser-derived effect), then judge the LINE with the verified kernel.
The gates are equality checks against TRUSTED values; none of them ever
substitutes a client-signed value into the judgment. -/

/-- The adapter identity the HOST knows actually mediated this call — a
    trusted input (deployment fact), never request data. -/
structure AdapterId where
  type : String
  version : String
  deriving Repr, BEq, DecidableEq

/-- The adapter type whose effect derivation this kernel defines. -/
def mcpAdapterType : String := "mcp"

/-- The effect the VERIFIED parser derives from the judged line:
    (resource = tool, action, canonical args serialization) of the parsed
    `tools/call`. `none` when the line does not parse as a capability request.
    Kernel twin of the host receipt's `seal.effect-view/v0` (which is
    explicitly `authoritative: false`); THIS derivation is the authoritative
    comparand for the F3 equality gate. -/
def deriveEffect (line : RawBytes) : Option (String × String × String) :=
  match parse line with
  | none => none
  | some ast =>
      match requestFromAst ast with
      | none => none
      | some req => some (req.tool, req.action, serializeAstValue req.arguments)

/-- All three advisory effect fields unset. -/
def advisoryEmpty (e : EffectEnvelope) : Bool :=
  e.effectResource == "" && e.effectAction == "" && e.effectArgs == ""

/-- F1 gate: the signed adapter claim must equal the adapter that actually
    mediated. -/
def adapterGate (mediator : AdapterId) (e : EffectEnvelope) : Bool :=
  e.adapterType == mediator.type && e.adapterVersion == mediator.version

/-- F2 gate: a nonempty signed session must equal the boot/config session
    (the `ApprovalState.session` plane — `bootAssigner`'s plane, not the
    receipt pid). Empty = seat, accepted. -/
def sessionGate (state : ApprovalState) (e : EffectEnvelope) : Bool :=
  e.session == "" || e.session == state.session

/-- F3 gate: an empty advisory effect always passes (seat). A nonempty one
    passes ONLY under the MCP adapter and ONLY if it equals the
    parser-derived effect of the judged line. Any other combination — a
    mismatch, an unparseable line, or a non-MCP adapter claiming an effect
    this kernel cannot derive — FAILS CLOSED: accepting an uncheckable claim
    would authenticate a lie. -/
def effectGate (mediator : AdapterId) (e : EffectEnvelope) : Bool :=
  if advisoryEmpty e then true
  else if mediator.type == mcpAdapterType then
    deriveEffect e.line == some (e.effectResource, e.effectAction, e.effectArgs)
  else false

/-- **The V2.3 judgment step** — the spec the host binds to at repin. -/
def effectStep (authority : ByteArray) (reg : PrincipalRegistry)
    (mediator : AdapterId) (e : EffectEnvelope) (sigHex : String)
    (state : ApprovalState) : Decision :=
  match verifyEffect authority reg e sigHex with
  | none => .Block
  | some _ =>
      if adapterGate mediator e && sessionGate state e && effectGate mediator e
      then decide e.line state
      else .Block

/-- Anything that is not blocked passed every gate. -/
theorem effect_step_gates {authority : ByteArray} {reg : PrincipalRegistry}
    {mediator : AdapterId} {e : EffectEnvelope} {sigHex : String}
    {state : ApprovalState}
    (h : effectStep authority reg mediator e sigHex state ≠ .Block) :
    (∃ p, verifyEffect authority reg e sigHex = some p)
      ∧ adapterGate mediator e = true
      ∧ sessionGate state e = true
      ∧ effectGate mediator e = true := by
  unfold effectStep at h
  split at h
  · exact absurd rfl h
  · next p hp =>
      split at h
      · next hg =>
          simp only [Bool.and_eq_true] at hg
          exact ⟨⟨p, hp⟩, hg.1.1, hg.1.2, hg.2⟩
      · exact absurd rfl h

/-- Decidability of blocking, constructively: the step is `.Block` or provably
    not — the case split every fail-closed theorem below stands on (no
    classical contradiction needed). -/
theorem effect_step_block_or_not (authority : ByteArray)
    (reg : PrincipalRegistry) (mediator : AdapterId) (e : EffectEnvelope)
    (sigHex : String) (state : ApprovalState) :
    effectStep authority reg mediator e sigHex state = .Block
      ∨ effectStep authority reg mediator e sigHex state ≠ .Block := by
  cases h : effectStep authority reg mediator e sigHex state with
  | Block => exact .inl rfl
  | Allow out => exact .inr fun hc => Decision.noConfusion hc

/-- **Presence, not value** — the factorization at the pipeline level: the
    step either blocks or returns EXACTLY `SealV2.decide e.line state`. The
    decision VALUE is a function of the judged line and the trusted
    config/state alone; every envelope field — the advisory F3 effect, the
    F7 revocation subject, all of them — gates only WHETHER a decision is
    produced. Advisory fields cannot appear in `SealV2.decide`: it never
    receives them. -/
theorem effect_step_presence_not_value (authority : ByteArray)
    (reg : PrincipalRegistry) (mediator : AdapterId) (e : EffectEnvelope)
    (sigHex : String) (state : ApprovalState) :
    effectStep authority reg mediator e sigHex state = .Block
      ∨ effectStep authority reg mediator e sigHex state
          = decide e.line state := by
  unfold effectStep
  split
  · exact .inl rfl
  · split
    · exact .inr rfl
    · exact .inl rfl

/-- Every Allow the pipeline emits is the kernel's own verdict on the line. -/
theorem allow_value_from_line_and_state {authority : ByteArray}
    {reg : PrincipalRegistry} {mediator : AdapterId} {e : EffectEnvelope}
    {sigHex : String} {state : ApprovalState} {out : CanonicalBytes}
    (h : effectStep authority reg mediator e sigHex state = .Allow out) :
    decide e.line state = .Allow out := by
  rcases effect_step_presence_not_value authority reg mediator e sigHex state
    with hb | hd
  · rw [h] at hb; cases hb
  · rw [← hd, h]

/-- **Advisory non-influence.** Two envelopes carrying the SAME judged line —
    under different registries, authorities, mediators, signatures, advisory
    effects, revocation subjects, everything — that both pass the gates
    produce the SAME decision. The advisory fields have no influence channel
    into the decision value. -/
theorem advisory_non_influence {authority₁ authority₂ : ByteArray}
    {reg₁ reg₂ : PrincipalRegistry} {mediator₁ mediator₂ : AdapterId}
    {e₁ e₂ : EffectEnvelope} {sig₁ sig₂ : String} {state : ApprovalState}
    (hline : e₁.line = e₂.line)
    (h₁ : effectStep authority₁ reg₁ mediator₁ e₁ sig₁ state ≠ .Block)
    (h₂ : effectStep authority₂ reg₂ mediator₂ e₂ sig₂ state ≠ .Block) :
    effectStep authority₁ reg₁ mediator₁ e₁ sig₁ state
      = effectStep authority₂ reg₂ mediator₂ e₂ sig₂ state := by
  rcases effect_step_presence_not_value authority₁ reg₁ mediator₁ e₁ sig₁ state
    with hb₁ | hd₁
  · exact absurd hb₁ h₁
  · rcases effect_step_presence_not_value authority₂ reg₂ mediator₂ e₂ sig₂
      state with hb₂ | hd₂
    · exact absurd hb₂ h₂
    · rw [hd₁, hd₂, hline]

/-- **F1: the adapter bind.** Anything not blocked signed the identity of the
    adapter that actually mediated. -/
theorem adapter_bind {authority : ByteArray} {reg : PrincipalRegistry}
    {mediator : AdapterId} {e : EffectEnvelope} {sigHex : String}
    {state : ApprovalState}
    (h : effectStep authority reg mediator e sigHex state ≠ .Block) :
    e.adapterType = mediator.type ∧ e.adapterVersion = mediator.version := by
  obtain ⟨_, hg, _, _⟩ := effect_step_gates h
  unfold adapterGate at hg
  simp only [Bool.and_eq_true, beq_iff_eq] at hg
  exact hg

/-- F1 fail-closed: an adapter-claim mismatch blocks. -/
theorem adapter_mismatch_blocks {authority : ByteArray}
    {reg : PrincipalRegistry} {mediator : AdapterId} {e : EffectEnvelope}
    {sigHex : String} {state : ApprovalState}
    (hne : e.adapterType ≠ mediator.type ∨ e.adapterVersion ≠ mediator.version) :
    effectStep authority reg mediator e sigHex state = .Block := by
  rcases effect_step_block_or_not authority reg mediator e sigHex state
    with hb | hnb
  · exact hb
  · have := adapter_bind hnb
    rcases hne with hne | hne
    · exact absurd this.1 hne
    · exact absurd this.2 hne

/-- **F2: session-plane equality.** Anything not blocked carries either no
    session claim (seat) or EXACTLY the boot/config session. A client-signed
    session value never enters the judgment plane: `decide` reads
    `state.session` (trusted config), never the envelope field. -/
theorem session_plane_equality {authority : ByteArray}
    {reg : PrincipalRegistry} {mediator : AdapterId} {e : EffectEnvelope}
    {sigHex : String} {state : ApprovalState}
    (h : effectStep authority reg mediator e sigHex state ≠ .Block) :
    e.session = "" ∨ e.session = state.session := by
  obtain ⟨_, _, hg, _⟩ := effect_step_gates h
  unfold sessionGate at hg
  simp only [Bool.or_eq_true, beq_iff_eq] at hg
  exact hg

/-- F2 fail-closed: a session claim that is neither empty nor the boot/config
    session blocks — the spoof theorem. -/
theorem session_spoof_blocks {authority : ByteArray}
    {reg : PrincipalRegistry} {mediator : AdapterId} {e : EffectEnvelope}
    {sigHex : String} {state : ApprovalState}
    (hne : e.session ≠ "") (hnm : e.session ≠ state.session) :
    effectStep authority reg mediator e sigHex state = .Block := by
  rcases effect_step_block_or_not authority reg mediator e sigHex state
    with hb | hnb
  · exact hb
  · rcases session_plane_equality hnb with h' | h'
    · exact absurd h' hne
    · exact absurd h' hnm

/-- **F3: MCP effect-equality.** Under the MCP mediator, anything not blocked
    that carries a nonempty effect claim carries EXACTLY the parser-derived
    effect of the judged line. The signature never authenticates an effect
    nobody checked — the confused-deputy closure. -/
theorem mcp_effect_equality {authority : ByteArray} {reg : PrincipalRegistry}
    {mediator : AdapterId} {e : EffectEnvelope} {sigHex : String}
    {state : ApprovalState}
    (hm : mediator.type = mcpAdapterType) (hne : advisoryEmpty e = false)
    (h : effectStep authority reg mediator e sigHex state ≠ .Block) :
    deriveEffect e.line
      = some (e.effectResource, e.effectAction, e.effectArgs) := by
  obtain ⟨_, _, _, hg⟩ := effect_step_gates h
  unfold effectGate at hg
  rw [hne] at hg
  simp only [Bool.false_eq_true, if_false, hm, beq_self_eq_true, if_true] at hg
  exact eq_of_beq hg

/-- F3 fail-closed, mismatch: a nonempty effect claim that differs from the
    parser-derived effect blocks (this includes an unparseable line, where
    `deriveEffect = none`). -/
theorem mcp_effect_mismatch_blocks {authority : ByteArray}
    {reg : PrincipalRegistry} {mediator : AdapterId} {e : EffectEnvelope}
    {sigHex : String} {state : ApprovalState}
    (hm : mediator.type = mcpAdapterType) (hne : advisoryEmpty e = false)
    (hmis : deriveEffect e.line
      ≠ some (e.effectResource, e.effectAction, e.effectArgs)) :
    effectStep authority reg mediator e sigHex state = .Block := by
  rcases effect_step_block_or_not authority reg mediator e sigHex state
    with hb | hnb
  · exact hb
  · exact absurd (mcp_effect_equality hm hne hnb) hmis

/-- F3 fail-closed, non-MCP: an adapter this kernel defines no effect
    derivation for cannot carry a nonempty effect claim at all. -/
theorem nonmcp_nonempty_effect_blocks {authority : ByteArray}
    {reg : PrincipalRegistry} {mediator : AdapterId} {e : EffectEnvelope}
    {sigHex : String} {state : ApprovalState}
    (hm : mediator.type ≠ mcpAdapterType) (hne : advisoryEmpty e = false) :
    effectStep authority reg mediator e sigHex state = .Block := by
  rcases effect_step_block_or_not authority reg mediator e sigHex state
    with hb | hnb
  · exact hb
  · obtain ⟨_, _, _, hg⟩ := effect_step_gates hnb
    unfold effectGate at hg
    rw [hne] at hg
    simp only [Bool.false_eq_true, if_false] at hg
    rw [if_neg (by simpa [beq_iff_eq] using hm)] at hg
    cases hg

/-! ## Golden vector — the cross-language signed-message contract

These `#eval` pins are ALSO the kernel-side negative control for the strip:
re-adding any killed field to the structure or message changes the golden
hex (and the Rust twin corpus), so reverting the strip breaks the build
here, not just review. -/

/-- Hex of a byte array (lowercase) — for golden-vector pins. -/
def bytesToHex (b : ByteArray) : String :=
  String.ofList (b.toList.flatMap fun byte =>
    let hi := byte.toNat / 16
    let lo := byte.toNat % 16
    let digit := fun (n : Nat) =>
      if n < 10 then Char.ofNat (48 + n) else Char.ofNat (87 + n)
    [digit hi, digit lo])

/-- info: "7365616c2e6566666563742f763200" -/
#guard_msgs in
#eval bytesToHex effectTag.toUTF8

/--
info: "7365616c2e6566666563742f763200a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf0000000000000005616c696365000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f00000000000004d200000000000000077b226d223a317d00000000000000036d6370000000000000000a323032352d30362d31380000000000000006736573732d31000000000000000a64622e65786563757465000000000000000463616c6c00000000000000077b2271223a317d0000000000000000"
-/
#guard_msgs in
#eval bytesToHex (effectMessage
  (ByteArray.mk (Array.range 32 |>.map fun i => UInt8.ofNat (0xa0 + i)))
  { keyId := "alice"
    nonce := ByteArray.mk (Array.range 32 |>.map UInt8.ofNat)
    issuedAt := 1234
    line := "{\"m\":1}"
    adapterType := "mcp"
    adapterVersion := "2025-06-18"
    session := "sess-1"
    effectResource := "db.execute"
    effectAction := "call"
    effectArgs := "{\"q\":1}"
    revocationSubject := "" })

/-! ## Axiom pins — the honesty razor, machine-checked

Every theorem in the package sits on the standard trio (or less). No new
axioms; `ed25519Verify` is `opaque` (TCB seam), not an axiom. -/

/-- info: 'SealV2.Effect.u64be_inj' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms u64be_inj

/-- info: 'SealV2.Effect.sized_cancel' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms sized_cancel

/-- info: 'SealV2.Effect.u64be_cancel' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms u64be_cancel

/-- info: 'SealV2.Effect.frame_cancel' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms frame_cancel

/-- info: 'SealV2.Effect.frame_inj' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms frame_inj

/-- info: 'SealV2.Effect.wireSizedB_spec' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms wireSizedB_spec

/-- info: 'SealV2.Effect.effect_message_injective' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms effect_message_injective

/-- info: 'SealV2.Effect.prefix_byte_separated' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms prefix_byte_separated

/-- info: 'SealV2.Effect.effect_cross_version_v1_separated' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms effect_cross_version_v1_separated

/-- info: 'SealV2.Effect.effect_cross_version_v22_separated' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms effect_cross_version_v22_separated

/-- info: 'SealV2.Effect.effect_cross_version_v21_separated' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms effect_cross_version_v21_separated

/-- info: 'SealV2.Effect.effect_cross_plane_separated' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms effect_cross_plane_separated

/-- info: 'SealV2.Effect.verifyEffect_wireSized' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms verifyEffect_wireSized

/-- info: 'SealV2.Effect.verified_effect_injective' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms verified_effect_injective

/-- info: 'SealV2.Effect.effect_gates_presence_not_value' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms effect_gates_presence_not_value

/-- info: 'SealV2.Effect.verifyEffect_none_of_unregistered' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms verifyEffect_none_of_unregistered

/-- info: 'SealV2.Effect.verifyEffect_id_registered' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms verifyEffect_id_registered

/-- info: 'SealV2.Effect.AuthenticatedId.ext_id' depends on axioms: [propext] -/
#guard_msgs in
#print axioms AuthenticatedId.ext_id

/-- info: 'SealV2.Effect.effect_step_gates' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms effect_step_gates

/-- info: 'SealV2.Effect.effect_step_block_or_not' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms effect_step_block_or_not

/-- info: 'SealV2.Effect.effect_step_presence_not_value' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms effect_step_presence_not_value

/-- info: 'SealV2.Effect.allow_value_from_line_and_state' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms allow_value_from_line_and_state

/-- info: 'SealV2.Effect.advisory_non_influence' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms advisory_non_influence

/-- info: 'SealV2.Effect.adapter_bind' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms adapter_bind

/-- info: 'SealV2.Effect.adapter_mismatch_blocks' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms adapter_mismatch_blocks

/-- info: 'SealV2.Effect.session_plane_equality' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms session_plane_equality

/-- info: 'SealV2.Effect.session_spoof_blocks' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms session_spoof_blocks

/-- info: 'SealV2.Effect.mcp_effect_equality' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms mcp_effect_equality

/-- info: 'SealV2.Effect.mcp_effect_mismatch_blocks' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms mcp_effect_mismatch_blocks

/-- info: 'SealV2.Effect.nonmcp_nonempty_effect_blocks' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms nonmcp_nonempty_effect_blocks

end SealV2.Effect
