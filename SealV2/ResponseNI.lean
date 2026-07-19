/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.Decide

/-!
# P6 — response-egress non-interference (theorem, with its boundary stated)

**The question (Ben, E1.1):** seal-host documents response egress as
UNMEDIATED BY DESIGN — P6 in the `main.rs` mediation table: child stdout is
copied verbatim to client stdout by a dedicated relay thread (no parse, no
gate, no state write). Can unmediated response egress influence any
SUBSEQUENT authorization decision? If provably not, P6 is a
confidentiality-only risk; if it can, it is an integrity hole that must close
before HTTP.

**The answer: a THEOREM — `p6_response_noninterference` (with
`p6_response_insertion` and `p6_state_noninterference`).** Response egress
cannot influence any subsequent authorization decision, because no response
byte has a path into the decision-bearing state.

**Why this is a fact about the interface, not an assumption.** Lean owns ALL
decision-bearing state (`Ffi.stateRef : Option ApprovalState`, mutated only by
the exported entry points). The FFI surface has exactly four exports touching
a session: `seal_v2_init` (config), `seal_v2_add_approval` (signed approval),
`seal_v2_decide` (raw request + clock), `seal_v2_challenge` (STATELESS). There
is NO export that consumes a response. The trace model below mirrors those
entry points call-for-call — `stepState`/`observeDecision` on the
init/approve/request arms are the SAME pure kernel compositions `Ffi.lean`
runs (`parseConfig` result, `signedParse ∘ signedMessageFromAst?` approval
append, `parse → validateAndConsumeWithStore listReplayStore → serialize`) —
and adds the one event the FFI does not have: `response bytes`. The `response`
arm is the identity BY CONSTRUCTION OF THE INTERFACE: there is no function to
model. The theorems then prove that the entire decision trace, and the entire
state evolution, are invariant under deleting or inserting arbitrary response
events with arbitrary bytes.

**The boundary, stated loudly (what the theorem can and cannot say):**
* IN SCOPE, PROVEN: no response-derived data reaches `ApprovalState`, the
  replay store, the clock argument, or any `decide` input inside the model
  that mirrors the deployed FFI. Checked against the deployed Rust relay
  (`main.rs:855-873`): the P6 path is `child_out.read → stdout.write_all`,
  byte-verbatim, no state.
* TCB (A3-class, named): that the Rust host CONTINUES to conform — i.e. never
  synthesizes an `init`/`add_approval`/`decide` argument from response bytes.
  Same seam class as every other A3 obligation; the mediation-table row is the
  documented contract.
* OUT OF SCOPE, permanently: the CLIENT reads responses and may choose its
  next request accordingly. That is not an integrity channel into the
  decision: requests are adversarial by assumption, and every decision is a
  function of (request bytes, trusted state) only — `SealV2.decide`. What
  response egress DOES carry is information OUT (child → client, unfiltered):
  a CONFIDENTIALITY/exfiltration channel. Over a local pipe to the same
  client this is the documented design; over HTTP it becomes an exfiltration
  path. **Verdict: P6 is confidentiality-only — record as a named risk that
  must be re-examined at the HTTP boundary; it is NOT an integrity hole and
  does not block on integrity grounds.**
-/

namespace SealV2.ResponseNI

/-- One host-boundary event. The first three mirror the state-bearing FFI
    exports one-to-one (`seal_v2_challenge` is stateless — no event needed);
    `response` is the P6 egress the FFI deliberately has no entry point for.
    `init` carries the PARSED config: the JSON glue is host control (A3), not
    the security surface — same seam as `Ffi.parseConfig`. -/
inductive HostEvent where
  | init (cfg : ApprovalState)
  | approve (rawSigned : String) (sigHex : String)
  | request (raw : RawBytes) (now : Nat)
  | response (bytes : String)

def isResponse : HostEvent → Bool
  | .response _ => true
  | _ => false

/-- The session-state transition, arm-for-arm the writes `Ffi.lean` performs:
    * `init` — replace the session (`initImpl`);
    * `approve` — append the reconstructed approval on the verified
      `signedParse`/`signedMessageFromAst?` path, no-op on any failure
      (`addApprovalImpl`);
    * `request` — run the verified
      `parse → validateAndConsumeWithStore listReplayStore` and persist the
      consumed store (+ clock) ONLY on Allow (`decideImpl` writes `stateRef`
      only in its Allow arm);
    * `response` — IDENTITY: the FFI has no response-consuming export. This
      arm is the interface fact P6 turns on, not an assumption bolted on. -/
def stepState (s : Option ApprovalState) : HostEvent → Option ApprovalState
  | .init cfg => some cfg
  | .approve rawSigned sigHex =>
      match s with
      | none => none
      | some st =>
          match signedParse rawSigned with
          | none => some st
          | some ast =>
              match signedMessageFromAst? ast.val with
              | none => some st
              | some sm =>
                  some { st with approvals := st.approvals ++ [{
                    target := sm.target, session := sm.session,
                    issuedAt := sm.issuedAt, expiresAt := sm.expiry,
                    consumed := false, signedMessageRaw := rawSigned,
                    signature := sigHex, nonce := sm.nonce }] }
  | .request raw now =>
      match s with
      | none => none
      | some st0 =>
          let st := { st0 with now := now }
          match parse raw with
          | none => some st0
          | some ast =>
              match validateAndConsumeWithStore listReplayStore
                  st.consumedNonces ast st with
              | none => some st0
              | some (store', _) => some { st with consumedNonces := store' }
  | .response _ => s

/-- The authorization decision an event yields, if any: only `request` events
    decide (uninitialized session / parse failure / validation failure all
    deny — the FFI's fail-closed arms). -/
def observeDecision (s : Option ApprovalState) : HostEvent → Option Decision
  | .request raw now =>
      some (match s with
        | none => .Block
        | some st0 =>
            let st := { st0 with now := now }
            match parse raw with
            | none => .Block
            | some ast =>
                match validateAndConsumeWithStore listReplayStore
                    st.consumedNonces ast st with
                | none => .Block
                | some (_, checked) => .Allow (serialize checked))
  | _ => none

/-- The decision trace of a run: every authorization decision, in order. -/
def runTrace (s : Option ApprovalState) : List HostEvent → List Decision
  | [] => []
  | ev :: t =>
      match observeDecision s ev with
      | none => runTrace (stepState s ev) t
      | some d => d :: runTrace (stepState s ev) t

/-- The state after a run. -/
def runState (s : Option ApprovalState) (t : List HostEvent) :
    Option ApprovalState :=
  t.foldl stepState s

/-- Drop every response event. -/
def purgeResponses (t : List HostEvent) : List HostEvent :=
  t.filter (fun ev => !isResponse ev)

/-- A response event neither changes state… -/
theorem response_state_invariant (s : Option ApprovalState) (b : String) :
    stepState s (.response b) = s := rfl

/-- …nor yields a decision. -/
theorem response_no_decision (s : Option ApprovalState) (b : String) :
    observeDecision s (.response b) = none := rfl

/-- **P6, purge form: response egress cannot influence any subsequent
    authorization decision.** The decision trace of ANY event sequence equals
    the decision trace of the same sequence with every response event (and
    all its bytes) deleted. Unmediated response egress is
    decision-invisible. -/
theorem p6_response_noninterference (s : Option ApprovalState)
    (t : List HostEvent) : runTrace s (purgeResponses t) = runTrace s t := by
  induction t generalizing s with
  | nil => rfl
  | cons ev t ih =>
      cases ev with
      | response b =>
          show runTrace s (purgeResponses t) = runTrace s (.response b :: t)
          rw [ih s]
          rfl
      | init cfg =>
          show runTrace s (.init cfg :: purgeResponses t) = _
          simp only [runTrace, observeDecision]
          exact ih _
      | approve rawSigned sigHex =>
          show runTrace s (.approve rawSigned sigHex :: purgeResponses t) = _
          simp only [runTrace, observeDecision]
          exact ih _
      | request raw now =>
          show runTrace s (.request raw now :: purgeResponses t) = _
          simp only [runTrace, observeDecision]
          rw [ih _]

/-- **P6, insertion form:** injecting a response event with ARBITRARY bytes at
    ANY position changes no decision, before or after the injection point. -/
theorem p6_response_insertion (s : Option ApprovalState)
    (t₁ t₂ : List HostEvent) (b : String) :
    runTrace s (t₁ ++ .response b :: t₂) = runTrace s (t₁ ++ t₂) := by
  induction t₁ generalizing s with
  | nil =>
      show runTrace s (.response b :: t₂) = runTrace s t₂
      rfl
  | cons ev t ih =>
      cases hobs : observeDecision s ev with
      | none =>
          show runTrace s (ev :: (t ++ .response b :: t₂)) = _
          simp only [List.cons_append, runTrace, hobs]
          exact ih _
      | some d =>
          show runTrace s (ev :: (t ++ .response b :: t₂)) = _
          simp only [List.cons_append, runTrace, hobs]
          rw [ih _]

/-- **P6, state form:** the authorization STATE after any run is invariant
    under purging responses — nothing response-derived is retained for any
    later decision to read. -/
theorem p6_state_noninterference (s : Option ApprovalState)
    (t : List HostEvent) : runState s (purgeResponses t) = runState s t := by
  induction t generalizing s with
  | nil => rfl
  | cons ev t ih =>
      cases ev with
      | response b => exact ih s
      | init cfg => exact ih _
      | approve rawSigned sigHex => exact ih _
      | request raw now => exact ih _

/-! ## Axiom pins -/

/-- info: 'SealV2.ResponseNI.p6_response_noninterference' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms p6_response_noninterference

/-- info: 'SealV2.ResponseNI.p6_response_insertion' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms p6_response_insertion

/-- info: 'SealV2.ResponseNI.p6_state_noninterference' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms p6_state_noninterference

end SealV2.ResponseNI
