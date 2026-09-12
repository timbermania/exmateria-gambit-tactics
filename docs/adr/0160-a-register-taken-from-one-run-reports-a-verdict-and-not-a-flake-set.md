# A register taken from one run reports a verdict, and not a flake set

`docs/TEST-BASELINE-E2.tsv` is **frozen** — extraction #2's pre-move record, which
answers one question about one move — so the suite has had no metric it could
**re-take**. This adds one: `tools/suite_register.py take` builds a per-test
register on any commit and `diff` reports a per-test delta between two.

The decision is not the file format. It is that a register **states what its own
repeat count could see**. One observation of a test is a verdict and nothing else,
so it prints `UNMEASURED×1` rather than `STABLE×1`, its `flakes` header reads
`UNMEASURED — 1 repeat` rather than `0`, and `diff` reports a difference seen once
per side as `UNCONFIRMED` rather than `MOVED`. The population that makes this
urgent already exists: [#417](https://github.com/timbermania/fft-monorepo/issues/417)
adopted **275** tests that are green **exactly once**.

Status: accepted (2026-08-25). Resolves
[#454](https://github.com/timbermania/fft-monorepo/issues/454), the last ticket on
map [#450](https://github.com/timbermania/fft-monorepo/issues/450). Reads
[ADR-0153](0153-audio-extracts-into-a-package-the-walk-reports-rather-than-enters.md)'s
frozen register as **preserved, not superseded** — that file is byte-unchanged and
`tools/check_test_baseline.py` is still green over it. Extends
[ADR-0158](0158-the-suite-runs-in-parallel-and-the-lane-is-a-measurement.md): both
arms now stamp the same provenance and print the same per-test cost lines.

Built at `92a2eef0f`; the aggregate-marker correction at `80e151a13`.

## Context

Map #450's destination has three clauses, and the third is *"the metric is
re-takeable."* Everything needed to state one honestly landed first, on purpose:
the verdict (#451), the coverage figure (#417), the second arm (#453). Built
before them, a register would have frozen three wrong answers into a new file and
given them a longer life.

Four ways to build it wrong were already paid for on this map, and each is a
decision below.

## Decision

### 1. The register does not score. It transcribes.

`tests/lib/verdict.sh` is the ONE reader (#451, ADR territory since two byte-
identical copies of the rule drifted). `take` reads that reader's output out of a
runner's stdout — the `[i/n] Running X...` / `  -> RESULT` pair — and the per-test
logs supply **evidence only**: assertion counts, `SCRIPT ERROR` counts, and the
failing assertion names.

Re-reading markers to form an opinion would silently undo two rules that exist
precisely because a log full of `[PASS]` is not always a pass: rule 7
`NOT_A_TEST` and rule 9 `THREW`. A register that re-scored would report `PASS`
for all 13 throwers and for every capture rig, and it would look right.

### 2. One repeat is `UNMEASURED`, never `STABLE`.

A blank or zero stability column reads as a clean bill of health, and #454's own
words are that such a register *"makes a single green run look like evidence when
it is not"*. So the column carries what was observed:

| repeats | cell |
|---|---|
| 1 | `UNMEASURED×1` |
| n, all agreeing | `STABLE×n` |
| n, disagreeing | `FLAKY(PASS×2,FAIL×1)` — the multiset, most-common first |

and the header says `UNMEASURED — 1 repeat` rather than `flakes 0`.

**The flake set is therefore recorded in the register rather than in prose.**
That is the same correction [#463](https://github.com/timbermania/fft-monorepo/issues/463)
made when it found nine capture rigs classified only inside
`freeze_test_baseline.RED_REASONS`: a dict of prose in a Python tool is not a
channel, and the tenth entry is one nothing forces anyone to add.

### 3. `diff` refuses to call a mover it cannot confirm.

```
MISSING      scored in one register and not the other — a coverage delta
FLAKY        either side disagreed with ITSELF; settled BEFORE a move is considered
SAME         same verdict, neither side flaky
MOVED        different, and BOTH sides stable across >= 2 repeats. The finding.
UNCONFIRMED  different, and at least one side saw it once
```

`tools/diff_arm_verdicts.py` measured this on the **arm** axis: four tests are not
constant across three *same-tree* runs, so `diff <(a) <(b)` reports four movers
and adopting on that reading quarantines four innocent tests. The commit axis has
the same hazard and gets the same refusal — deliberately spelled the same way. A
verdict that was never stable cannot have been moved by your commit, and the
remedy `UNCONFIRMED` names is *take more repeats*, not *ignore it*.

⚠️ **`FLAKY` is read FIRST, before equality.** Both sides reading `FLAKY` are equal
strings, and a naive equality test calls that `SAME` — losing the one fact the
reader needs.

### 4. Provenance is a property of the run, not of the moment you read it.

`take` runs no `git rev-parse` and stats no addon. Six fields come out of the
**runner's own banner**, because only the runner was present for the run:

| field | source |
|---|---|
| `code_commit`, `godot` | already printed by both runners (#453 §5.1) |
| `addon_sync` | `check_addon_sync.stamp()` — the tool that owns the comparison |
| `godot_cache` | `.godot/imported` count + shader cache, `tools/harness_stamp.py` |
| `test_coverage` | `check_test_list_coverage.classify()`, counted |
| harness mode | `freeze_test_baseline.runner_provenance()` |

Two run logs naming different commits are a **`ProvenanceError`**, never a merge.
That is not hypothetical: this map's original *"the tally is wrong in both
directions"* headline was a register from the 08:14 run read against a tally from
23:40, six tests fixed in between.

⚠️ **The coverage triple belongs to the run for the same reason.** The array grew
by **275 entries in one commit**; a register that derived its own coverage figure
at read time would print today's tree beside verdicts taken before it. It is also
what lets the *parallel* arm state its coverage at all — that runner runs no
pre-flights.

### 5. The wall clock is the runner's own measurement, not a log mtime.

Map #450's per-test cost figures were taken from `tests/logs/*.log` mtimes. An
mtime is when the last byte was written, so a test that hangs silently for five
minutes and is then killed reads as *fast*; under the parallel arm the mtimes
interleave and mean nothing at all. Both runners now print `  seconds` and
`  exit` per test.

⚠️ **They are SEPARATE lines and never decorations on `  -> RESULT`.** That shape
is what `freeze_test_baseline.verdicts()` pairs with a `Running` line, and every
archived run and every `replay.py` reconstruction reads it.

⚠️ **An arm that did not measure prints nothing, and the register renders `-`.**
Every archived run predates these lines; a `0.00` would read as an instant test
and poison the budget.

### 6. Registers are artifacts. They are not tracked.

`take` writes where you point it and prints to stdout by default. A register
committed to the tree is a `tests/logs/` in waiting — checked in, stale within a
week, with nothing saying so, which has already cost this map a ticket arm.

## What this does NOT decide

**The wall-clock budget.** The register *measures* cost per test and in total, and
`diff` prices the delta. Whether ~100 minutes is affordable, and what the `slow`
class in `tests/skip_tests.tsv` should hold, is a decision and wants a ticket —
not a threshold buried in a tool.

## Consequences

- `bash tests/run_all_tests.sh` gains one pre-flight (`test_suite_register`,
  `test_harness_stamp`) and three banner lines. `tools/harness_stamp.py` runs at
  boot, so a break in it breaks the suite rather than quietly degrading a register.
- **The guards are against the RUNNERS, not against synthetic logs.** A runner
  that stops printing does not turn the register red — it makes it report `-` and
  `UNKNOWN` and read exactly like a measurement. All four arms were seeded red
  against the real files.
  ⚠️ **One of them was found reading its own explanatory COMMENT** rather than the
  line bash executes, and stayed green through the deletion it was written to
  catch. Same defect as `test_run_tests_parallel`'s emptied slice, in a guard
  written in the same session that fixed it. **An assertion over a source file has
  to match something that would EXECUTE.**
- `check_addon_sync.py` grows `--stamp` off an extracted `statuses()`, so the
  banner line and the full report are two renderings of one comparison. Report
  output is byte-identical.
- `docs/TEST-BASELINE-E2.tsv` is untouched and `check_test_baseline.py` still
  reports `434 rows, tally matches`.

## Demonstrated

Six listed tests, parallel arm at N=1, two repeats per side, on a real commit that
changes one production constant (`CameraUnits.POS_TILES` 28 → 27):

```
# tally     MOVED 1  SAME 5
# wall_clock 32.7 s -> 32.0 s (-0.7 s)
CameraUnitsTest  MOVED  PASS  FAIL  -0.08  stable PASS×2 then stable FAIL×2
```

with the failing assertion names carried in the row
(`1 tile → raw 28 — expected 28, got 27`, and two more).

**The same move, taken with ONE run per side**, reports:

```
CameraUnitsTest  UNCONFIRMED  PASS  FAIL  -0.08  differs, but repeats are a=1 b=1 —
  one run per side cannot tell a mover from a coin flip. Re-take with more repeats.
```

That second reading is the decision, working. And merging the two commits' logs
into one register is refused by name.

⚠️ **The seed commit was deleted with its branch**, so `register-b.tsv`'s
`code_commit` names a commit reachable from nothing. A register's provenance can
outlive the commit it names; the field is a claim about what was run, not a
promise the tree is still there.
