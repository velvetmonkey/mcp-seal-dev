# v2/ — milestone evidence (internal)

This tree is the v2 development record, not library code (the Lean library is
`SealV2/`, one directory up). [STATUS.md](STATUS.md) is the index: what each
milestone M1–M8 proved, ran, and captured.

Files like `axioms.txt`, `fixture-run.txt`, and `*-corpus.txt` under
`milestones/*/` are **captured snapshots** of live runs (referenced by
STATUS.md as evidence), not build outputs; each milestone's `run.sh` regenerates
them. If a snapshot and a fresh run disagree, the fresh run wins — treat the
snapshot as stale and recapture it.
