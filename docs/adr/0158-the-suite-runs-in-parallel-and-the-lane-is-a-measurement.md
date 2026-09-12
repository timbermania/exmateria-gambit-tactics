# The suite runs in parallel, and the sequential lane is a measurement

The suite is **412 fresh `godot --path .` processes** and about half its wall clock
is the engine booting, so nothing done to an individual test touches the bulk of
it. Running those processes eight at a time takes it from **~61 minutes to 10.4**.
The reason that was not simply switched on is [#450](https://github.com/timbermania/fft-monorepo/issues/450)'s
whole thesis — a fast unreliable suite is worse than a slow reliable one — so what
this ADR adopts is not the speedup but the **proof**: one sequential arm and three
parallel arms on the same tree, diffed per test, **407 of 412 identical and zero
moved**.

The lane that holds what does move is **a measurement, never a guess**. The one
test it named was **fixed before it was laned** — and then earned the lane anyway,
because the fix made a vacuous assertion real and the real one is contention-
sensitive. That order is the decision: root-cause first, quarantine second, with a
ticket holding the receipt.

Status: accepted (2026-08-24). Resolves
[#453](https://github.com/timbermania/fft-monorepo/issues/453) under map
[#450](https://github.com/timbermania/fft-monorepo/issues/450). Retires this
package's standing *never run GPU test scenes in parallel* rule. Reads
[ADR-0153](0153-audio-extracts-into-a-package-the-walk-reports-rather-than-enters.md)'s
frozen register as preserved, not superseded.

Arms at `1e297d694`; adoption and the lane arm at `c546fbbb4`.

## Context

### What was measured, and on what

| Arm | Wall | Verdicts |
|---|---|---|
| Sequential — `bash tests/run_all_tests.sh` | **61 min** | 398 PASS · 1 FAIL · 13 THREW |
| Parallel N=8, repeat 1 | **10.5 min** | 397 · 2 · 13 |
| Parallel N=8, repeat 2 | **10.4 min** | 398 · 1 · 13 |
| Parallel N=8, repeat 3 | **11.0 min** | 399 · 0 · 13 |

**5.6–5.9×.** Every arm ran on one tree, and every verdict on both sides came from
`tests/lib/verdict.sh` — the parallel runner **sources** the reader in a subshell
rather than restating its rules in Python, so a diff of the two arms cannot be a
diff of two scoring opinions. CPU-seconds *inside* the tests rose ~7% at eight-way
concurrency (65.3 min of test time against a 61-minute sequential wall), which is
the ticket's *RAM-bound, not CPU-bound* reading holding up: the tests did not slow
down meaningfully when they ran beside each other.

The parallel wall clocks are the runner's own printed figures. The **61 minutes is
the running session's**, not the artifact's — that arm's stdout predates the
provenance banner both runners now print, which is precisely the gap dec. 4 closes.

### The diff, and why it is not `diff <(a) <(b)`

Two runs of this suite differ with nothing changed: four tests are not constant
across the three same-tree archived runs. A plain diff of one sequential run
against one parallel run reports those four as movers, and adopting on that
reading would quarantine four innocents while proving nothing. So
`tools/diff_arm_verdicts.py` takes repeats and answers a narrower question —

```
sequential arms: 1   parallel arms: 3   tests: 412

  MOVED               0
  FLAKY_PARALLEL      1
  FLAKY_SEQUENTIAL    4
  MISSING             0
  AGREE             407
```

`MOVED` is the strong finding: constant in both arms and different. **It is zero.**
The four `FLAKY_SEQUENTIAL` were unstable before parallelism was in the picture and
a verdict that was never stable cannot have been destabilised by it. That leaves
exactly one test whose stability parallelism changed.

### The population the retired rule named

This package's `CLAUDE.md` carried *never run GPU test scenes in parallel* as a
standing rule. **None of the 60 `GPU*` scenes moved.** The one test that did is
`EffectStudioDeselectScrollAcceptanceTest` — a UI scroll acceptance test. The rule
was not merely unproven, it pointed at the wrong population, and it had been
steering every session away from the six-fold win for the whole life of the file.

## Decision

**1. `tools/run_tests_parallel.py` is how the suite is run; `tests/run_all_tests.sh`
stays the reference arm.** Parallel for the iteration loop and for any run whose
purpose is *did I break something*. Sequential for taking a register, for any
number that will be compared against another number, and any time the parallel
result is surprising. Two arms, one reader, and the sequential one is the tie-break.

**2. `N` is derived from free RAM, never from core count.** 24 cores, ~1.02 GB peak
RSS per test process: a runner that read `nproc` would pick 24, want 24 GB and
swap. `worker_count()` takes `MemAvailable`, holds back 2 GB for the rest of the
box, and caps at the core count.

**3. The `SEQUENTIAL_LANE` is a measurement, and a mover is fixed before it is
laned.** An entry means *this test's verdict moved between the arms, n times out of
m* — never *this test looks timing-sensitive*. Guessing would both miss real movers
and quarantine innocents, and each silently shrinks what the register measures.

A lane entry is the **second** choice. The one test the diff named,
`EffectStudioDeselectScrollAcceptanceTest`, was root-caused instead, and the cause
was a production defect the test had never been able to see: a scroll-into-view
nudge that read a `scroll_vertical` its own `_relayout` had not yet written, so it
declined as *already visible* on every invocation the feature ever had.
Quarantining it would have preserved the green and kept the feature dead.

**And then it earned the lane anyway, for a different reason.** The fix made the
assertion real, and the real assertion turns out to be contention-sensitive.
Measured on `c546fbbb4`, same box, **concurrency the only variable**:

| arm | starts reaching a verdict | result |
|---|---:|---|
| idle, one process at a time | 20 | **20 PASS** |
| N=8 mixed load | 30 | **25 PASS · 5 FAIL** (16.7%) |

Both failing assertions read a scroll window that has no layout yet
(`window_bottom=0.0`), so the nudge correctly declines and the test correctly
reports that it did not run. **Stable sequentially, unstable in parallel** is the
lane's definition, so it is laned with that measurement as its reason and the
synchronisation defect is filed as
[#527](https://github.com/timbermania/fft-monorepo/issues/527). Closing that
ticket means taking the entry back out and re-diffing — a lane entry is a debt
with a receipt, not a resting place.

**4. A register's `runner` field is derived from the run, not asserted by the
tool.** `docs/TEST-BASELINE-E2.tsv` is **preserved byte-for-byte**: its header line
naming a sequential runner is true of the run it describes, and a frozen
measurement is not re-frozen. But that line was a hardcoded string, so a register
captured with the parallel runner would have inherited the claim unchallenged —
the exact provenance error this map has already paid for once. Both runners now
print a banner naming themselves and their concurrency;
`freeze_test_baseline.runner_provenance()` reads it, emits `parallel N=8, 0 in the
sequential lane` when that is what happened, and says `UNKNOWN` for a log with no
banner rather than inheriting a claim.

**5. `N` is blind to free VRAM, and that is a stated precondition of any parallel
number.** Measured on this box 2026-08-24 with a local LLM holding 27.8 of 32 GB:
at N=8, **six of eight `GPU*` scenes failed `Couldn't create Vulkan device`, fell
back, and still scored `PASS`** — the same eight at N=1 produced zero device
failures. Verdict identity is necessary and **not sufficient**: the verdicts were
stable while the thing under test quietly stopped being the GPU path. When the
failure lands at engine startup instead, the process dies in two seconds with no
display server and scores `NO_VERDICT`
([#526](https://github.com/timbermania/fft-monorepo/issues/526)). **Check
`nvidia-smi` before believing a parallel GPU number**, and take registers on an
idle GPU.

**6. The parallel arm's own tests are a pre-flight.** `run_all_tests.sh` runs
`test_run_tests_parallel`, `test_diff_arm_verdicts` and `test_freeze_test_baseline`
beside the verdict reader's tests. All three are load-bearing for dec. 1: the
runner reads the runner script's own `TESTS` array and sources the one reader, the
diff separates *parallelism changed it* from *it was already flaky*, and the
register derives its provenance. Untested, any of them drifts and the identity
claim stops being about this tree.

## Considered alternatives

**Batch cheap tests into shared processes.** The obvious answer to a ~3.5 s startup
floor, and this codebase has already run the experiment: the gambit runner batches,
and Vulkan local-device creation fails 54 of 82 times inside that one process,
emitting 43,492 device errors under a green suite
([#430](https://github.com/timbermania/fft-monorepo/issues/430)). Process isolation
is buying real protection. **Parallel here means N processes, never fewer.**

**Lane the four sequentially-flaky tests too.** They are unstable in both arms;
laning them would move four tests out of the parallel population and change
nothing about their stability, while making the lane read as *tests parallelism
broke*. They are ticket material, not lane material — and one of them,
`GPUStatusNoDamageTest`, turned out to be asserting something false rather than
flaking at all.

**Adopt on a single parallel repeat.** One repeat cannot separate a mover from a
first-ever flake; the diff says so in its own output by refusing to mark such a row
confirmed. Three repeats is what made `MOVED: 0` mean anything.

**Schedule the tests longest-first.** The N=8 arm's 10.4 min against an ideal 8.2
is one scheduling fact — the 245.7 s `GambitScenarioRunnerTest` sits 335th of 412
and is picked up when the pool is nearly drained. Out of scope here and settled
separately on 2026-08-23; this ADR adopts the measured 10.4, not a projection.

## Consequences

- The iteration loop is six times shorter, which is the difference between running
  the suite before a commit and not running it.
- **`docs/TEST-BASELINE-E2.tsv` does not move.** Its numbers stay comparable to
  extraction #2's, and any future register carries a provenance field that names
  its own arm.
- A parallel register is only as good as the box's free VRAM, and nothing enforces
  that — dec. 5 is a precondition a human checks, which is weaker than a guard and
  is stated as such.
- The lane holds **one entry on `c546fbbb4`**, and that is a fact with a date on
  it, not a property of the suite. Re-diffing the arms is how it changes — and
  411 of 412 tests still run eight at a time, so one entry costs ~20 seconds.
- **A lane entry is a debt, and #527 is its receipt.** The failure mode this
  guards against is a lane that grows quietly: every entry is a test the parallel
  arm no longer covers, so a lane nobody empties is a register that measures less
  each time it is taken.
