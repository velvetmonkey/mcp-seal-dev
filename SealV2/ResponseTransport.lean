/- SPDX-License-Identifier: Apache-2.0 -/

import SealV2.ResponseNI

/-!
# P6 on a transport-enriched model — REFUTED, with the fail-closed residue proven

`SealV2/ResponseNI.lean` proves P6 in a model whose `.response` arm is
state-identity and decision-silent by definition; the adversarial frisk showed
that this defines away what the deployed seal-host relay actually does with a
child response. This file enriches the model just enough to EXPRESS that
behavior, and then:

* **refutes** the P6 purge/insertion property on the enriched model, with a
  concrete witness (`transport_p6_refuted`, witness `killRun`), and
* **proves** the property that survives (`p6_fail_closed`,
  `response_approval_invariant`): responses can kill the session — a
  fail-closed denial/termination effect — but can never create, alter, or
  reorder an Allow.

What is added, mirroring seal-host behavior (cited read-only; seal-host was
not modified):
* `Framing`: complete / EOF / unterminated / oversized / IO-error — the
  outcomes of `read_bounded_frame` (seal-host `rust/src/limits.rs:16-68`)
  plus the read-error arm (`rust/src/main.rs:1170-1178`). A failed enqueue of
  a COMPLETE frame also kills the transport (`main.rs:1143-1148`); model that
  case as `.ioError`, not `.complete`.
* `HostState.dead`: seal-host's `downstream_dead` + readiness pair collapsed
  to one flag. Every non-complete outcome sets it (`main.rs:1143-1177`).
* The request arm of `runTrace` observes `dead` BEFORE any decision and, if
  set, emits `.seamError` and terminates the run — mirroring
  `main.rs:1209-1216` (SEAM_ERROR_RESPONSE, readiness false, loop break).

The approval-plane dynamics are literally `ResponseNI`'s
(`ResponseNI.stepState` / `ResponseNI.observeDecision` are reused), so the
two models differ exactly where the frisk found the old one blind.

**Honesty boundary, unchanged in kind:** this is still a hand-written
abstraction of seal-host, NOT a refinement proof from the compiled Rust.
Unmodeled: the 64-slot output queue's backpressure and interleaving
(`rust/src/output.rs`), seal-host's multi-kernel state and registry, the
A3 host-owned inputs, and the raw `Vec<u8>` carrier (the `.complete` payload
is a `String` stand-in and is never inspected). No theorem here transfers to
the deployed binary; what these theorems settle is that P6 as previously
stated is not salvageable once the transport channel is expressible, and
that the fail-closed weakening is provable.
-/

namespace SealV2.ResponseTransport

open SealV2

/-- Framing outcome of one child-response read, per seal-host
    `read_bounded_frame` (`rust/src/limits.rs:16-68`) plus the IO-error arms
    of the relay loop (`rust/src/main.rs:1141-1179`). -/
inductive Framing where
  | complete (bytes : String)
  | eof
  | unterminated
  | oversized
  | ioError

/-- Which framing outcomes kill the transport: every arm except a
    successfully relayed complete frame (`main.rs:1143-1177`). -/
def framingKills : Framing → Bool
  | .complete _ => false
  | _ => true

/-- Session state: the approval plane of `ResponseNI`, plus the one bit the
    old model could not express — transport death (seal-host's
    `downstream_dead` + readiness, collapsed). -/
structure HostState where
  approval : Option ApprovalState
  dead : Bool

/-- Host-boundary events. `init`/`approve`/`request` are as in `ResponseNI`;
    `response` now carries its framing outcome instead of an inert string. -/
inductive HostEvent where
  | init (cfg : ApprovalState)
  | approve (rawSigned : String) (sigHex : String)
  | request (raw : RawBytes) (now : Nat)
  | response (f : Framing)

def isResponse : HostEvent → Bool
  | .response _ => true
  | _ => false

/-- Transition: the approval plane steps exactly as `ResponseNI.stepState`;
    a response touches ONLY the dead flag (monotonically). -/
def stepState (s : HostState) : HostEvent → HostState
  | .init cfg => { s with approval := ResponseNI.stepState s.approval (.init cfg) }
  | .approve r sig => { s with approval := ResponseNI.stepState s.approval (.approve r sig) }
  | .request raw now => { s with approval := ResponseNI.stepState s.approval (.request raw now) }
  | .response f => { s with dead := s.dead || framingKills f }

/-- The decision a live request yields — exactly `ResponseNI`'s request
    observation (always `some`; `.Block` default is unreachable). -/
def reqDecision (a : Option ApprovalState) (raw : RawBytes) (now : Nat) : Decision :=
  (ResponseNI.observeDecision a (.request raw now)).getD .Block

/-- What the client observes per event: an authorization decision, or the
    seam-error frame seal-host emits for a request that arrives after
    transport death (`main.rs:1213-1216`). -/
inductive Obs where
  | decision (d : Decision)
  | seamError

/-- Observable trace. A request that finds the transport dead yields
    `.seamError` and TERMINATES the run (seal-host breaks its request loop
    and kills the child); everything after the break does not happen. -/
def runTrace (s : HostState) : List HostEvent → List Obs
  | [] => []
  | .init cfg :: t => runTrace (stepState s (.init cfg)) t
  | .approve r sig :: t => runTrace (stepState s (.approve r sig)) t
  | .response f :: t => runTrace (stepState s (.response f)) t
  | .request raw now :: t =>
      if s.dead then [.seamError]
      else .decision (reqDecision s.approval raw now)
        :: runTrace (stepState s (.request raw now)) t

/-- Drop every response event (same purge as `ResponseNI`). -/
def purgeResponses (t : List HostEvent) : List HostEvent :=
  t.filter (fun ev => !isResponse ev)

/-! ## Refutation: the P6 purge property fails on this model

The witness is the frisk's concrete failure story: the child emits an
oversized (> 1 MiB) terminated frame, the relay sets `downstream_dead`, and
the next client request is answered with a seam error instead of being
decided. Purging the response makes that request get decided. -/

/-- The witness run: one oversized child response, then one client request. -/
def killRun : List HostEvent := [.response .oversized, .request "" 0]

/-- Purged, the request is decided (here: `.Block` — empty raw, no session). -/
theorem killRun_purged_decides :
    runTrace ⟨none, false⟩ (purgeResponses killRun) = [.decision .Block] := rfl

/-- Unpurged, the oversized response kills the transport and the same request
    is answered with the seam error; the session terminates. -/
theorem killRun_seam_errors :
    runTrace ⟨none, false⟩ killRun = [.seamError] := rfl

/-- **The P6 purge property of `ResponseNI` is FALSE on this model.**
    Deleting a response event changes the observable trace. -/
theorem transport_p6_refuted :
    ∃ (s : HostState) (t : List HostEvent),
      runTrace s (purgeResponses t) ≠ runTrace s t := by
  refine ⟨⟨none, false⟩, killRun, ?_⟩
  rw [killRun_purged_decides, killRun_seam_errors]
  intro h
  exact Obs.noConfusion (List.cons.inj h).1

/-- **The P6 insertion property is FALSE too:** inserting an oversized
    response before a request changes what the request observes. -/
theorem transport_p6_insertion_refuted :
    ∃ (s : HostState) (t₁ t₂ : List HostEvent) (f : Framing),
      runTrace s (t₁ ++ .response f :: t₂) ≠ runTrace s (t₁ ++ t₂) := by
  refine ⟨⟨none, false⟩, [], [.request "" 0], .oversized, ?_⟩
  intro h
  exact Obs.noConfusion (List.cons.inj h).1

/-! ## The surviving property: fail-closed

Responses never touch the approval plane, and their only influence on the
trace is truncation at a seam error: the Allow outputs of any run form a
prefix of the Allow outputs of the response-purged run. Responses can deny
or terminate; they cannot create, alter, or reorder an Allow. -/

/-- A response event never touches the approval plane — only `dead`. -/
theorem response_approval_invariant (s : HostState) (f : Framing) :
    (stepState s (.response f)).approval = s.approval := rfl

/-- Transport death is monotone: no event revives a dead transport. -/
theorem dead_is_terminal (s : HostState) (ev : HostEvent) (h : s.dead = true) :
    (stepState s ev).dead = true := by
  cases ev <;> simp [stepState, h]

/-- The Allow outputs of a trace, in order. -/
def allowsOf : List Obs → List CanonicalBytes
  | [] => []
  | .decision (.Allow out) :: t => out :: allowsOf t
  | .decision .Block :: t => allowsOf t
  | .seamError :: t => allowsOf t

private theorem prefix_refl (l : List CanonicalBytes) : l <+: l :=
  ⟨[], List.append_nil l⟩

private theorem nil_prefix (l : List CanonicalBytes) : [] <+: l :=
  ⟨l, rfl⟩

private theorem prefix_cons (a : CanonicalBytes) {l₁ l₂ : List CanonicalBytes}
    (h : l₁ <+: l₂) : a :: l₁ <+: a :: l₂ := by
  obtain ⟨u, hu⟩ := h
  exact ⟨u, by rw [List.cons_append, hu]⟩

/-- A dead transport allows nothing: the first request seam-errors and the
    run terminates, so no Allow is ever emitted. -/
theorem dead_no_allows :
    ∀ (t : List HostEvent) (s : HostState), s.dead = true →
      allowsOf (runTrace s t) = [] := by
  intro t
  induction t with
  | nil => intro s _; rfl
  | cons ev t ih =>
      intro s h
      cases ev with
      | init cfg => exact ih _ (by simp [stepState, h])
      | approve r sig => exact ih _ (by simp [stepState, h])
      | response f => exact ih _ (by simp [stepState, h])
      | request raw now => simp [runTrace, h, allowsOf]

/-- **Fail-closed: the surviving P6 residue.** For ANY start state and ANY
    event sequence, the Allow outputs of the run form a prefix of the Allow
    outputs of the response-purged run. Response events can only truncate
    the Allow stream (by killing the session); they cannot create an Allow
    the purged run would not have produced, nor change or reorder one. -/
theorem p6_fail_closed :
    ∀ (t : List HostEvent) (s : HostState),
      allowsOf (runTrace s t) <+: allowsOf (runTrace s (purgeResponses t)) := by
  intro t
  induction t with
  | nil => intro s; exact prefix_refl _
  | cons ev t ih =>
      intro s
      cases ev with
      | init cfg =>
          have hp : purgeResponses (HostEvent.init cfg :: t)
              = .init cfg :: purgeResponses t := by
            simp [purgeResponses, isResponse]
          rw [hp]
          simp only [runTrace]
          exact ih _
      | approve r sig =>
          have hp : purgeResponses (HostEvent.approve r sig :: t)
              = .approve r sig :: purgeResponses t := by
            simp [purgeResponses, isResponse]
          rw [hp]
          simp only [runTrace]
          exact ih _
      | response f =>
          have hp : purgeResponses (HostEvent.response f :: t)
              = purgeResponses t := by
            simp [purgeResponses, isResponse]
          rw [hp]
          simp only [runTrace]
          obtain ⟨a, d⟩ := s
          cases d with
          | true =>
              rw [dead_no_allows t _ (by simp [stepState])]
              exact nil_prefix _
          | false =>
              cases hk : framingKills f with
              | true =>
                  rw [dead_no_allows t _ (by simp [stepState, hk])]
                  exact nil_prefix _
              | false =>
                  have hs : stepState ⟨a, false⟩ (.response f) = ⟨a, false⟩ := by
                    simp [stepState, hk]
                  rw [hs]
                  exact ih _
      | request raw now =>
          have hp : purgeResponses (HostEvent.request raw now :: t)
              = .request raw now :: purgeResponses t := by
            simp [purgeResponses, isResponse]
          rw [hp]
          obtain ⟨a, d⟩ := s
          cases d with
          | true =>
              simp only [runTrace]
              simp [allowsOf]
          | false =>
              simp only [runTrace]
              simp only [Bool.false_eq_true, if_false]
              cases hD : reqDecision a raw now with
              | Block => simpa [allowsOf] using ih _
              | Allow out =>
                  simp only [allowsOf]
                  exact prefix_cons _ (ih _)

/-! ## Axiom pins -/

/-- info: 'SealV2.ResponseTransport.transport_p6_refuted' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms transport_p6_refuted

/-- info: 'SealV2.ResponseTransport.transport_p6_insertion_refuted' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms transport_p6_insertion_refuted

/-- info: 'SealV2.ResponseTransport.p6_fail_closed' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms p6_fail_closed

/-- info: 'SealV2.ResponseTransport.response_approval_invariant' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms response_approval_invariant

/-- info: 'SealV2.ResponseTransport.dead_no_allows' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms dead_no_allows

end SealV2.ResponseTransport
