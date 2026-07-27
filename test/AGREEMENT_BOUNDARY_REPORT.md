# Agreement boundary probe

> **STATUS, added on harvest 2026-07-27.** This report is the measurement from
> `RUN boundtrue-2026-07-26`. It was written on branch
> `test/agreement-boundary-probe` and stranded there: main took a newer version
> of the probe script and the show-test but never took this write-up, so the code
> landed and the reasoning did not. Harvested here verbatim, body unedited, on
> Ben's ruling.
>
> **One row has since been acted on.** The table marks `9007199254740992` (2^53)
> as a refusal whose verdict is **NOT** correct: Node and Python both extract it
> exactly, so every reader agrees and the kernel refused anyway. Ben ruled on
> 2026-07-27 11:05 that the coefficient conjunct causing it be dropped, leaving
> exact binary64 representability to decide. Implemented on
> `fix/coefficient-conjunct-demoted` (`b467c7d`), **not yet merged**: it is red on
> one deliberately preserved assertion that pins the old rule. Independently
> re-run at that commit, this literal is now ACCEPT and `UNDER_REFUSALS` remains
> empty.
>
> **The rest of the table stands.** In particular `9007199254740993` (2^53+1),
> where Node gives `...992` and Python gives `...993`, is unaffected and still
> correctly refused.
>
> Read the table below as the state at `RUN boundtrue-2026-07-26`, not as the
> current guard. That is the point of keeping it.

METHOD: Kernel readings came from the freshly rebuilt
`.lake/build/bin/numeric_agreement_show "${literals[@]}"`.  Reader readings came
from these commands, once per literal:

```text
node -e 'console.log(JSON.stringify(JSON.parse(process.argv[1])))' -- "$literal"
python3 -c 'import json,sys; v=json.loads(sys.argv[1]); print(repr(v)); print(type(v).__name__)' "$literal"
```

`test/agreement_boundary_probe.py` runs those commands and preserves their
stdout.  For a Python `int`, it compares that exact integer with Node's exact
binary64 rational, not just Node's shortest display.  For a finite Python
`float`, it compares the exact binary64 ratios after round-trip parsing Node's
`JSON.stringify` output.  Positive and negative zero denote the same
mathematical value.  Node's `null` serialization of infinity does not denote
Python's `inf` or `-inf`; this is also the negative control.

TABLE:

| literal | kernel verdict | node value | python value | python type | AGREE? | verdict CORRECT? |
|---|---:|---:|---:|---|---:|---:|
| `1e17` | ACCEPT | `100000000000000000` | `1e+17` | `float` | YES | YES |
| `100000000000000000` | ACCEPT | `100000000000000000` | `100000000000000000` | `int` | YES | YES |
| `1e16` | ACCEPT | `10000000000000000` | `1e+16` | `float` | YES | YES |
| `10000000000000000` | ACCEPT | `10000000000000000` | `10000000000000000` | `int` | YES | YES |
| `9007199254740992` | REFUSE | `9007199254740992` | `9007199254740992` | `int` | YES | **NO** |
| `0.1` | ACCEPT | `0.1` | `0.1` | `float` | YES | YES |
| `1.5e3` | ACCEPT | `1500` | `1500.0` | `float` | YES | YES |
| `1E2` | ACCEPT | `100` | `100.0` | `float` | YES | YES |
| `1.0` | ACCEPT | `1` | `1.0` | `float` | YES | YES |
| `100.0` | ACCEPT | `100` | `100.0` | `float` | YES | YES |
| `2.5` | ACCEPT | `2.5` | `2.5` | `float` | YES | YES |
| `1e2` | ACCEPT | `100` | `100.0` | `float` | YES | YES |
| `3.14159` | ACCEPT | `3.14159` | `3.14159` | `float` | YES | YES |
| `0.30000000000000004` | ACCEPT | `0.30000000000000004` | `0.30000000000000004` | `float` | YES | YES |
| `-0.1` | ACCEPT | `-0.1` | `-0.1` | `float` | YES | YES |
| `-0` | ACCEPT | `0` | `0` | `int` | YES | YES |
| `0` | ACCEPT | `0` | `0` | `int` | YES | YES |
| `0.0` | ACCEPT | `0` | `0.0` | `float` | YES | YES |
| `-0.0` | ACCEPT | `0` | `-0.0` | `float` | YES | YES |
| `0e0` | ACCEPT | `0` | `0.0` | `float` | YES | YES |
| `-0e-0` | ACCEPT | `0` | `-0.0` | `float` | YES | YES |
| `5e-324` | ACCEPT | `5e-324` | `5e-324` | `float` | YES | YES |
| `1e-400` | REFUSE | `0` | `0.0` | `float` | YES | **NO** |
| `1.7976931348623157e308` | ACCEPT | `1.7976931348623157e+308` | `1.7976931348623157e+308` | `float` | YES | YES |
| `1e309` | REFUSE | `null` | `inf` | `float` | NO | YES |
| `1e308` | ACCEPT | `1e+308` | `1e+308` | `float` | YES | YES |
| `9007199254740993` | REFUSE | `9007199254740992` | `9007199254740993` | `int` | NO | YES |
| `9007199254740991` | ACCEPT | `9007199254740991` | `9007199254740991` | `int` | YES | YES |
| `123456789012345678901234567890` | REFUSE | `1.2345678901234568e+29` | `123456789012345678901234567890` | `int` | NO | YES |
| `1.7976931348623158e308` | REFUSE | `1.7976931348623157e+308` | `1.7976931348623157e+308` | `float` | YES | **NO** |
| `0.1000000000000000055511151231257827` | REFUSE | `0.1` | `0.1` | `float` | YES | **NO** |
| `-1e9999` | REFUSE | `null` | `-inf` | `float` | NO | YES |
| `1e-324` | REFUSE | `0` | `0.0` | `float` | YES | **NO** |
| `0.10000000000000001` | REFUSE | `0.1` | `0.1` | `float` | YES | **NO** |
| `100000000000000001` | REFUSE | `100000000000000000` | `100000000000000001` | `int` | NO | YES |
| `9999999999999999` | REFUSE | `10000000000000000` | `9999999999999999` | `int` | NO | YES |
| `999999999999999` | ACCEPT | `999999999999999` | `999999999999999` | `int` | YES | YES |
| `1.0000000000000002` | ACCEPT | `1.0000000000000002` | `1.0000000000000002` | `float` | YES | YES |
| `2.2250738585072014e-308` | ACCEPT | `2.2250738585072014e-308` | `2.2250738585072014e-308` | `float` | YES | YES |
| `1e-323` | ACCEPT | `1e-323` | `1e-323` | `float` | YES | YES |
| `9999999999999990` | ACCEPT | `9999999999999990` | `9999999999999990` | `int` | YES | YES |
| `90071992547409910` | ACCEPT | `90071992547409900` | `90071992547409910` | `int` | NO | **NO** |
| `999999999999999000` | ACCEPT | `999999999999999000` | `999999999999999000` | `int` | NO | **NO** |

UNDER-REFUSALS: **TWO FOUND ACROSS 43 LITERALS.**

- **`90071992547409910`** — ACCEPTED and SIGNABLE.  Required Node stdout is
  `90071992547409900`; Python stdout is `90071992547409910` / `int`.  Node
  `toFixed(0)` additionally exposes the exact binary64 integer as
  `90071992547409904`.
- **`999999999999999000`** — ACCEPTED and SIGNABLE.  The required shortest
  outputs happen to look identical, but they do not denote the same extracted
  value: Python keeps exact integer `999999999999999000`, while Node's exact
  binary64 integer, exposed by `toFixed(0)`, is `999999999999998976`.

OVER-REFUSALS:

- `9007199254740992`
- `1e-400`
- `1.7976931348623158e308`
- `0.1000000000000000055511151231257827`
- `1e-324`
- `0.10000000000000001`

Neither `0.1` nor `1.5e3` is over-refused.  The six names above are the full
over-refusal list across this 43-literal corpus.

1e17 PAIR: There is no verdict asymmetry in the checked-in implementation.
`1e17` is ACCEPTED; Node prints `100000000000000000`; Python prints, verbatim:

```text
1e+17
float
```

`100000000000000000` is also ACCEPTED; Node prints
`100000000000000000`; Python prints, verbatim:

```text
100000000000000000
int
```

Both Node binary64 values are exactly `100000000000000000`, so both reader
pairs agree mathematically.  The brief's proposed asymmetry is absent, and
refusing the integer spelling would have been an over-refusal for these
readers.  Acceptance of this particular pair is justified; the same
trailing-zero normalization is unsafe for the two under-refusals above.

BOUNDARY TRUE?: **NO.**  The two under-refusals are false receipts.  The
integer branch checks the normalized significant coefficient against
`maxSafeInteger` but does not apply the normalized decimal exponent before
deciding.  Multiplication by removed powers of ten can require more than 53
binary significant bits.  The boundary also has the six enumerated
over-refusals, but those are safe loss; the two accepted disagreements are the
ruling defect.

TOTALITY: No panic, hang, divergence, or timeout occurred.  The 43-literal
kernel executable run completed in `ELAPSED=0.32`, including the 30-digit
integer and exponent `-400`.  Separate process-level runs of `1e-400`, the
30-digit integer, a 21-digit exponent, malformed `not-a-number`, a 10,000-digit
integer, and a 10,000-digit exponent each completed with exit 0 in
`0.24`–`0.28` seconds.  No literal was observably slow.  The predicate itself
is a structurally total `Option Bool` computation; this is an empirical stress
check, not a universal performance proof.

The syntax-survival cases are build-time `#guard`s: a quoted monster literal,
a numeric-looking key, an array, a nested object, and numeric text adjacent to
an escaped quote.  All elaborated successfully.

NEGATIVE CTRL: The harness detected the known disagreement:

```text
NEGATIVE_CONTROL literal=-1e9999 node=null python='-inf\nfloat' agree=FALSE
```

The two underlying reader commands printed, verbatim:

```text
null
```

```text
-inf
float
```

LEAN BUILD: Builds ran sequentially through `/home/monkey/bin/leanbuild`; no
raw `lake`, outer lock, or bypass was used.

```text
Build completed successfully (38 jobs).
EXIT_FILE=0
Build completed successfully (71 jobs).
EXIT_FILE=0
```

The exit files were `/tmp/boundtrue_numeric_build.exit` and
`/tmp/boundtrue_axiom_build.exit`.  The second build covers the added
`Seal.NumberGuardTheorems` `#guard`s through `axiom_check`.

DISAGREEMENTS:

- The brief says `100000000000000000` is expected REFUSED.  It is ACCEPTED
  because `parseWireDecimal?` removes trailing zeroes before the integer branch
  checks `parsed.digits.length` and magnitude.
- The same is true of `10000000000000000`; it is ACCEPTED, not REFUSED.
- Consequently the claimed `1e17`/integer-spelling verdict asymmetry does not
  exist on this `main`.
- The hypothesis that the integer spelling disagrees merely because Python
  returns `int` is not true for `10^17`: that integer is exactly representable
  in binary64.  Type is decisive only when the binary64 value differs, as in
  the two under-refusals.

COMMIT: Recorded by the final lane handoff after commit creation (a commit
cannot contain its own SHA).  Branch `test/agreement-boundary-probe`.  Not
merged, not pushed, and `seal-host` was not repinned.

FAILED ATTEMPTS:

- `/home/monkey/bin/leanbuild numeric_agreement_show` failed immediately with
  `error: unknown command 'numeric_agreement_show'`; corrected to
  `/home/monkey/bin/leanbuild build numeric_agreement_show`.
- The first external harness run reached `-0.1`, where Node treated the
  negative literal as a CLI option and exited 9.  Adding Node's `--`
  end-of-options marker fixed the invocation; the complete rerun exited 0.
- An initial reading from the pre-existing executable was discarded because
  its timestamp predated `Seal/JsonUtil.lean`; all table verdicts above come
  from the fresh 38-job build.

UNVERIFIED: Other JSON implementations, other Node/Python versions, NaN
(not JSON syntax), end-to-end signing by `seal-host`, and every possible input
outside the enumerated/stress corpus were not physically reproduced.  The
frozen `/home/monkey/src/mcp-seal` tree and `seal-host` pin were not touched.

Evidence: RUN boundtrue-2026-07-26
