# The test charter

**What a test in this package has to be, and why each clause is here.**

`CLAUDE.md` → "The test charter" carries the fifteen clauses as one-liners, because
a rule nobody has in context is a rule nobody follows. This file carries the
*evidence* for each, because that is the half that rots — and a clause whose reason
has been forgotten gets argued away by the next session that finds it inconvenient.

Every clause is marked **(G)** — mechanically guarded by
`tools/check_test_charter.py` — or **(J)** — judgement, audited one test at a time by
`.claude/skills/test-audit-loop`. There is no third state. Ten of fifteen are (J),
and saying so is deliberate: a heading that reads as enforced and checks nothing is
the exact failure `check_guard_registry.py` exists to delete.

---

## The number this charter is about

The suite is **736 processes**. Godot boots in each one, with 28 autoloads, before a
single assertion runs. Measured on this box at `77cf2c62e`: the cheapest test in the
tree (`JsonAssetTest` — pure logic, no GPU) is **2.31 s** warm.

`CLAUDE.md` → "Scoping a test run" records the shape of the rest: **59% of tests
finish inside 6 s**, which is roughly that boot cost, so more than half the wall
clock is engine startups — and **"cutting slow tests barely helps (80% of the clock
is 66% of the tests)."**

Two things follow, and they drive almost every clause below.

1. **Making a slow test faster is nearly worthless.** The suite is expensive because
   of how many processes it is, not how slow any of them is.
2. **Every test you add costs 2.3 s forever, and every test you remove saves 2.3 s
   forever.** The count is the number that matters.

A third thing follows that this charter states out loud because it inverts the
advice everyone arrives with: **splitting a test in two costs a whole process.** See
clause 13.

---

## Kind & cost

### 1. (G) Declare your kind

    # test-kind: logic
    # test-kind: render lane-pinned

One of `static-guard`, `logic`, `render`, `gpu`, `stranger-rig`, `perf`, optionally
followed by `lane-pinned`. Defined in `CONTEXT.md` → *Test kind*.

Without a written starting point, "is this really a GPU test?" has no prior and every
audit re-derives it from scratch. The declaration is what makes clause 2 a *move*
rather than an opinion.

### 2. (J) Take the cheapest kind that can still fail

The ladder runs `gpu` → `render` → `logic` → `static-guard`, and each rung down is
strictly cheaper. If the assertion needs no frame it is a `logic` test. **If it needs
no Godot at all it is a `static-guard` and it costs nothing** — the 2.3 s process
disappears entirely.

This is not hypothetical; the package already does it by hand. `TuneTest` guards the
tunable registry at runtime and `tools/check_tune_owner_self_registration.py` is
described in the runner as its *"static half"*. Same for the verdict channel, the
test list, the ADR shape: ~25 pre-flight guards that used to be, or could have been,
scenes.

**A hundred logic tests that are really static assertions is ~4 minutes of wall clock
and a hundred fewer processes.** That is a bigger prize than every speed-up in the
suite combined, which is why `DEMOTE` is a first-class audit verdict.

### 3. (J) Load only what you assert on

A test with a 260-file closure is slow *and* fragile: a change anywhere inside it
selects the test in a scoped run, and a break anywhere inside it reds the test with a
message about something else. `docs/TEST-AUDIT-REGISTER.tsv` carries `closure_size`
per test for exactly this reading.

---

## Termination

### 4. (G) Quit yourself

**The runner passes no `--quit-after`.** `run_tests_parallel.command_for()` is
`timeout 360 godot --path . res://tests/<stem>.tscn` and nothing else. A test that
does not call `.quit()` is killed by `timeout(1)` six minutes later and scored HUNG —
six minutes of a worker slot for no verdict.

Measured at `77cf2c62e`: **777 of 794 files under `tests/` already do this**, so the
ratchet started nearly closed. Four tests in the array do not.

### 5. (G) No unbounded waits

No `await` on a signal that may never arrive, no loop without a frame budget. A test
that can hang is a test that costs 360 s to tell you nothing.

### 6. (J) Budget in ticks, not seconds

`tests/lib/verdict.sh` rule 5 already scores this: *"TIMEOUT — the test declared its
own tick-budget timeout and asserted nothing."* A self-declared budget produces a
verdict; the runner's kill produces HUNG, which is the absence of one.

### 7. (J) Wait on the state, not on a duration

Use `tests/lib/await_until.gd`. It polls a predicate once per frame and returns the
moment the state is true, so it is **both faster than the sleep it replaces and
immune to the load that made the sleep flaky.**

`SEQUENTIAL_LANE` in `tools/run_tests_parallel.py` has exactly one entry, and this is
what it is:

> `EffectStudioDeselectScrollAcceptanceTest` — 20/20 PASS idle, **5 FAIL in 30 starts
> under an N=8 mixed load**. `window_bottom=0.0` — the deferred relayout has not
> landed when the assertion reads it.

That is a poll-for-state bug wearing a lane pin. There is no correct constant for
such a sleep: long enough to be safe under load is wasted clock on every green run,
short enough to be quick is a flake.

---

## Honesty

### 8. (G) Emit exactly one aggregate verdict

`tests/lib/verdict.sh` is the one reader, and its rule 8 makes `NO_VERDICT` its own
outcome, never folded into PASS: *"a test that produced no verdict did not run."*

### 9. (G) A green must be a run

Print an assertion count and fail on zero. `docs/TEST-BASELINE-E2.tsv`'s own header:

> **A GREEN SUMMARY IS NOT A RUN.** A coroutine error or a stale call arity aborts a
> test silently, so `asserts_pass` and `script_errors` are the evidence, not the
> verdict.

A GDScript error aborts only its enclosing function. A test whose `_ready` throws
halfway can print `[PASS]` for the assertions it reached and nothing for the ones it
never got to.

### 10. (G) Must be able to fail

    # seeded-break: set JsonAsset.load_dict to return {} — assertion 1 reds

Name the break that reds this test. This package has been bitten by unfailable tests
repeatedly and each time it took a person to notice:

* **#421** — the guard could not fail: `EditorImportPlugin.new()` is null outside an
  editor, so the scene passed regardless.
* An arm that asked the subject for its **own flag** passed a seeded defect.
* A rig that did not spell its subject's path could not have detected its absence.

The audit loop seeds a break on every test it touches anyway (ADR-0254), so this
column fills itself in as the burn-down runs.

### 11. (J) Stable under load, or lane-pinned with a measured pass rate

A test that is green alone and red at N=8 is not a flake to be re-run; it is a fact
about the test. Pin it, and write the **measured** rate into the lane comment the way
the existing entry does. A lane entry with no measurement is how a real bug gets
filed as flakiness.

There is no fixed flaky-test list in this package and there cannot be — the surface
is CPU/GPU contention, and two runs' FAIL sets have had **zero overlap**. Stability is
a per-test measurement, taken on demand.

### 12. (G) No environment reads

[ADR-0051](adr/0051-scene-configuration-lives-in-debug-panels-not-env-vars.md), already
guarded by `tools/check_no_env_vars.py`. Cited here, not restated — one rule, one
register.

---

## The two that invert received wisdom

### 13. (J) Carry every assertion that shares your setup

**This is the opposite of "one assertion per test", and the inversion is on purpose.**

In a normal suite a test is a function and splitting one costs microseconds. Here a
test is a **process with a 2.3 s floor**, so splitting one costs 2.3 s on every run
forever, and merging two that share setup saves 2.3 s forever.

Unstated, every future session will helpfully split tests apart "for clarity" and
quietly re-grow the 736. It is also what licenses the audit loop's `MERGE` verdict,
and why `docs/TEST-AUDIT-REGISTER.tsv` is ordered by closure overlap: the pairs whose
static closures agree are the mechanically-derivable merge candidates.

The limit is the word *setup*. Assertions that need different scenes, different
fixtures, or different tunable state do not share setup and merging them just builds
a test that fails for six reasons.

### 14. (G) Your verdict may not depend on wall-clock time

Three distinct sins, and the charter treats them differently:

* **Sleeping a real duration to synchronise** — `await get_tree().create_timer(0.5)
  .timeout`. Banned. Use `tests/lib/await_until.gd`. Measured at `77cf2c62e`: 37
  occurrences across 24 files, ~29 s of pure sleeping. That is small as a *speed*
  lever and large as a *flake* lever, which is the honest framing of this clause.
* **Depending on real-delta `_process` to advance state.** Banned. Drive the state,
  or await `physics_frame` — the physics step is fixed at 60 Hz of simulated time
  regardless of how long the frame took to render.
* **Asserting on a measured duration** — `Time.get_ticks_msec()` deltas. Banned
  **except** in a test whose declared kind is `perf`.

**A `perf` test is exempt and automatically lane-pinned.** The exemption and the pin
are the same fact: a real-time measurement taken under N=8 parallel load is not a
measurement. `SpuClippingMetricsTest` read **PASS solo and 2/3 FAIL interleaved on
the same tree** — solo runs blamed the branch, three interleaved runs showed trunk
failing too. So `perf` is a declaration *with a cost*, not an escape hatch.

Measured at `77cf2c62e`: 30 files read a wall clock, 20 of them outside a `perf`
declaration.

#### What is NOT banned

**Awaiting frames.** `await get_tree().process_frame` / `physics_frame` is frame-count,
not wall-clock, and it is already the dominant idiom here — **735 awaits across 266
files**. That is the pattern the other clauses point *at*, not away from.

#### `--fixed-fps` was considered and is not adopted

Godot offers `--fixed-fps N`, which forces a fixed delta and disables real-time
synchronisation. It would buy determinism suite-wide. It is **not** adopted, because
it was measured and did not pay: A/B on two tests, 2 reps each, `base` vs
`--disable-vsync` vs `--fixed-fps 60`, gave **2.31–2.44 s in every arm** — no speed
difference at all, and the theory that vsync silently caps the suite is dead with it.
Changing delta semantics for 736 tests at once is a real behaviour change; it needs a
measured payoff first. Left as a candidate the register can justify later.

---

## The step that is not a test

### 15. (J) A pre-flight step costs SERIAL time, and a guard's arms must share their walk

`tools/run_tests_parallel.py` shells out to `run_all_tests.sh --preflight-only` and
**waits**. The pre-flight is serial time at the head of every full run — it does not
overlap the N-way pool, so **a minute here is a minute of wall clock at any N**. That
is the opposite of a test, where a minute costs a minute divided by N.

Measured at `fafe193e8` with `tools/time_preflight.py` — 84 invocations, **5.7 min
total**, and the shape is as lopsided as it gets:

| | secs | share | step |
| ---: | ---: | ---: | --- |
| 1 | 253.06 | **73.5%** | `unittest test_check_addon_portability` |
| 2 | 40.43 | 11.7% | `unittest test_check_lattice_scene` |
| 3 | 19.30 | 5.6% | `check_addon_portability.py` |
| 4 | 10.19 | 3.0% | `unittest test_check_lattice_publish` |
| 5 | 4.19 | 1.2% | `unittest test_check_lattice_ports` |

**Half the pre-flight is its single slowest step of 84.** The median step is 0.05 s.

And the 253 s is not work: `test_check_addon_portability` has 69 arms, **13 of which
each re-run the same ~19.5 s whole-tree portability walk**, on a tree that does not
change between them. 13 × 19.5 ≈ 253.

This is **clause 13's twin, applied to a guard**. There the unit that gets duplicated
is a 2.3 s process; here it is a 19.5 s tree walk. Same rule: *share the setup*. Cache
the clean-tree walk once and let only the arms that deliberately seed a file walk
fresh — and note the trap, which is the reason this is (J) and not a drive-by fix:
several arms (`test_the_seed_is_what_reddens_it_and_not_the_tree`) exist precisely to
mutate the tree and re-walk it. **A cache that swallowed those would make the arms
vacuous while leaving them green**, which is the failure this whole file is about.

⚠️ **Cost is not a verdict.** A guard that costs 40 s may be worth 40 s. The three
honest outcomes for an expensive step are *make it cheaper*, *move it off the critical
path*, or *keep it and say why* — the last one in writing, next to the step.

The instrument is `tools/time_preflight.py`; the standing measurement is
`docs/PREFLIGHT-TIMING.tsv`. Both note that a real-time measurement taken while another
session holds the box is inflated, and this one was.

---

## The mechanical half

`tools/check_test_charter.py` enforces **C1, C4, C10, C14a, C14b** and runs in the
pre-flight. `tests/charter_allowlist.tsv` carries the violations that existed when
the charter landed and **may only shrink** — a row whose violation is gone is itself
reported as an error, so the list cannot rot into a permanent exemption.

The burn-down at landing (`uv run python tools/check_test_charter.py --stats`):

| clause | violating | what it means |
| --- | ---: | --- |
| C1 | 736 | nothing declares a kind yet — fills in as the loop runs |
| C4 | 4 | tests that never call `.quit()` |
| C10 | 736 | nothing records a seeded break yet — fills in as the loop runs |
| C14a | 11 | tests that sleep a real duration |
| C14b | 20 | tests that read a wall clock outside a `perf` declaration |
| | **1,507** | rows total |

C1 and C10 are 736 because they are new columns, not because 736 tests are broken.
The four real debts are C4, C14a and C14b — **35 rows**, and the audit loop clears
them as it reaches each test.
