# M8 threat model — milestone notes

Status: complete; merged to `main`. The bid-facing capstone. Adds NO theorems — it WRITES
`THREAT-MODEL.md` (the document the ARIA bid quotes) and re-verifies the M1–M7 axiom footprint the
threat model rests on. This closes the seal v2 build.

## What was filed

- `THREAT-MODEL.md` — five parts: (1) the adversary (a compromised/malicious agent driving the target
  to an unapproved or misinterpreted action; capabilities + out-of-scope mapped to A1/A3/A4/A6),
  (2) the trust boundary (verified core vs trusted glue A3), (3) every named theorem with its GUARANTEE
  and its NON-guarantee, (4) the A1–A6 residual ledger, (5) the claim.
- `print_axioms.lean` + `axioms.txt` — the full named-theorem footprint, captured from a live
  `#print axioms` run (re-verified, not asserted).
- `run.sh` — rebuilds, runs all `v2_m*_axiom_check` guards, captures the footprint, and byte-diffs the
  canonical claim string across the three doc artifacts.

## Footprint (re-verified)

All 16 named theorems carry `[propext, Classical.choice, Quot.sound]` and nothing else;
`ed25519Verify` depends on no axioms. Zero `sorry`/`admit`/`native_decide`. The `v2_m*_axiom_check`
`#guard_msgs` gates are build-breaking (M5's `signed_parse_canonical` is locked inside the m4 gate;
there is no separate `v2_m5_axiom_check`). See `axioms.txt`.

## The claim (canonical string — must be byte-identical everywhere)

> complete mediation modulo A1-A4, with A2 minimised by construction; A6 (durability) stated, not hidden.

Framing it earns:

> We do not prove the agent is safe; we prove the environment is safe from the agent.

Discipline: never "eliminated"/"entirely closed". A2 is minimised by construction, NEVER closed.
A5 was discharged by construction at M7 (the deployed store IS `listReplayStore`). A6 is a
deployment-config property (in-memory by design), stated not hidden. Ed25519 proves origin, not intent
(the "cryptographically valid rubber stamp" / human-oracle limit, named in §4 of the threat model).
Reproduce the footprint + claim-string check with `bash v2/milestones/08-threat-model/run.sh`.
