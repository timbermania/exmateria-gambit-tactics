# A guard the suite does not list is a guard nobody runs, and the list is a register

`tests/run_all_tests.sh` names every static guard it runs, one `if !` block at a time, by hand.
There is no discovery loop anywhere in it. So a guard is run because somebody remembered to add
a line, and a guard that nobody remembered is a file that looks exactly like a guard, ships with
the repo, is cited by ADRs, has its own tests — and has never once been executed.

This is the fourth time the repo has found this shape and the first time it is being measured
across the whole population rather than one file:

- [#565](https://github.com/timbermania/fft-monorepo/issues/565) found `check_vault_anchors.py`
  invoked by nothing.
- root ADR-0003 dec. 7 found `check_addon_portability.py` the same way, and named the file.
- [ADR-0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md)
  arms 3 and 4 found two more.
- [ADR-0232](0232-goal-5-is-a-conjunction-and-neither-instrument-may-claim-the-word-alone.md)
  found that `tools/test_score_goals.py` had never run, so eleven seeded arms from
  [ADR-0228](0228-the-rig-scores-six-of-nine-and-it-is-the-first-system-with-no-per-domain-escape.md)
  dec. 5 were inert from the day they landed. That census is
  [#876](https://github.com/timbermania/fft-monorepo/issues/876) and it is about **test files**.

Each was paid by adding one line to the runner. None of them made the next instance impossible,
which is what a register is for.

Status: accepted (2026-09-05). Reads
[ADR-0205](0205-a-path-reach-is-the-same-axis-as-a-type-reach.md) dec. 7 for the
reported-versus-enforcing split and
[ADR-0209](0209-one-ruling-over-three-rows-that-needed-three-and-a-file-can-be-ruled-back.md) for
why a row is not a place to put things. Tickets:
[#770](https://github.com/timbermania/fft-monorepo/issues/770) (the finding, generalised here),
[#728](https://github.com/timbermania/fft-monorepo/issues/728) (its red, already paid),
[#823](https://github.com/timbermania/fft-monorepo/issues/823) (the sibling half of the same
cluster), and the four debts this register opens:
[#879](https://github.com/timbermania/fft-monorepo/issues/879),
[#880](https://github.com/timbermania/fft-monorepo/issues/880),
[#881](https://github.com/timbermania/fft-monorepo/issues/881),
[#882](https://github.com/timbermania/fft-monorepo/issues/882).

## Context

### The population, measured

On `origin/main` at `de8ae7af4`:

| | count |
|---|---|
| `godot-learning/tools/check_*.py` | **57** |
| invoked by `tests/run_all_tests.sh` | **48** |
| **invoked by nothing** | **9** |

The nine, run by hand:

| guard | rc | wall |
|---|---|---|
| `check_addon_sync.py` | 0 | <1 s |
| `check_adr_quotes.py` | 0 | <1 s |
| `check_baseline.py` | 0 | <1 s |
| `check_blueprint_walk.py` | 0 | <1 s |
| `check_no_global_rd_for_compute.py` | 0 | 2 s |
| `check_focus_anchor.py` | **1** | <1 s |
| `check_residue.py` | **1** | 4 s |
| `check_root_set.py` | **1** | 5 s |
| `check_test_baseline.py` | **1** | <1 s |

**Cost is not why any of them was left out.** All nine together are under ten seconds against a
pre-flight that takes 342. The five green ones are wired in by this change and the register does
not name them.

### The four reds were on trunk, unseen, and none of them is new debt

- `check_focus_anchor.py` reports four problems that are **two files at two addresses**:
  `PlayerCamera.gd` and `TileCursor.gd` moved into `addons/exmateria_battlefield/` and
  [ADR-0177](0177-focus-is-a-stack-of-states-and-godot-can-make-the-bad-state-unrepresentable.md)'s grandfather list still names
  them under `src/scenes/`. A move, not a regression.
- `check_test_baseline.py` reports `MOVED TO NOWHERE`, which traces to commit `5f8703961`
  renaming `ScenarioEventPathfinderTest` to `EventPathfinderTest` inside the addon;
  `docs/TEST-BASELINE-E2.tsv:49` still names the old destination.
- `check_residue.py` and `check_root_set.py` are the two slow ones and their reds were not
  diagnosed here.

`check_blueprint_walk.py` is the guard [#728](https://github.com/timbermania/fft-monorepo/issues/728)
and [#770](https://github.com/timbermania/fft-monorepo/issues/770) were written about. Its red is
**already paid** — it reads rc 0 with zero unclassified today. Only the wiring was still owed,
which is exactly the failure mode: the debt got fixed and nothing noticed, because nothing was
looking.

### What a bare grep would have got wrong

Two guards are invoked as `python3 "$PROJECT_DIR/tools/check_addon_globals.py"` rather than
`uv run python tools/…`, and a predicate that knew only the second spelling reports both as
unwired. The runner also **names** `check_tune_owner_self_registration.py` and
`check_test_list_coverage.py` in prose beside other rules, and a substring search scores a
mention as a run — the same confusion this ADR is about, one level down. The predicate strips
whole-line shell comments and then requires an actual `python… <name>` call.

## Decision

**1. `tools/check_guard_registry.py` exists, and it is in the pre-flight.** Its subject is every
`check_*.py` under `godot-learning/tools/`, graded against `tests/run_all_tests.sh`. It grades
itself; a registry exempt from its own rule is the rule with a hole in it.

**2. The register is `NOT_IN_PREFLIGHT`, keyed by guard basename, and every row carries a kind,
a dated owner and a reason.** This is the reviewed-literal idiom the repo already uses for
`SCENE_BURN_DOWN` and `DECLARED_MOUNTS`: a row is an argument somebody signed, not a suppression.

**3. There are exactly two kinds, and the difference between them is whether anybody owes
anything.** `EXEMPT` is a permanent argument — this file is not a pre-flight guard and never will
be — and needs no ticket, because there is nothing to point at. `OWED` is a promise, and a
promise with no address is indistinguishable from a promise nobody is going to keep, so **an
`OWED` row must name an issue** and the guard reds if it does not. The register ships with 0
exempt and 4 owed.

**4. Arms 1, 2 and 3 ENFORCE; arm 4 REPORTS.** Arm 1: a guard in no pre-flight and on no row is
red. Arm 2 is the ratchet's **other direction**, and it has two halves — a row naming a guard
that no longer exists is red, and a row excusing a guard the pre-flight **now invokes** is red.
Without that second half the excuse list can only grow, and paying a debt would leave its row
behind forever. Arm 3 is the missing-issue red of dec. 3. Arm 4 prints the owed count on every
run and says in the same breath that it is not a pass, on
[ADR-0205](0205-a-path-reach-is-the-same-axis-as-a-type-reach.md) dec. 7's grounds — a reported
channel that prints a number and lets the run read clean is how a number stops being read.

**5. Five guards are wired in rather than declared, and four are declared rather than wired.**
The line between them is exactly the line between green and red in the table above. That is not a
coincidence to hide: wiring a red guard into the gate aborts the full suite for everyone, which
is what [#871](https://github.com/timbermania/fft-monorepo/issues/871) had been doing. The four
reds are filed as [#879](https://github.com/timbermania/fft-monorepo/issues/879) (focus anchor),
[#880](https://github.com/timbermania/fft-monorepo/issues/880) (residue),
[#881](https://github.com/timbermania/fft-monorepo/issues/881) (root set) and
[#882](https://github.com/timbermania/fft-monorepo/issues/882) (test baseline). Paying one means
deleting its row, and arm 2 is what forces that.

**6. The registry answers ONE question and its three blind spots are written into its own
docstring rather than discovered later.** It does not know whether a guard's own **tests** run —
that is [#876](https://github.com/timbermania/fft-monorepo/issues/876) and it is a different
population with a different runner. It does not know whether an invoked guard is **enforcing** or
merely printing. And its subject stops at `godot-learning/tools/`, so
`../exmateria-sound/tools/check_globals.py` is outside it and is named as outside it. An
instrument that quietly answers less than its name suggests is the defect one layer up.

## Consequences

The pre-flight gains six guard invocations and about ten seconds.

`tools/test_check_guard_registry.py` is 17 arms and **every red one constructs the state it
grades** — a seeded `tools/check__registry_seed.py` written into the real tree, a seeded row, a
seeded runner script. Not one arm reads a row off the shipped register to prove an arm fires, so
all of them keep firing on the day the owed set reaches zero. Three arms exercise the invocation
predicate directly (a comment mention is not a call; both real spellings are), and six read the
shipped rows on purpose, because claims about the rows cannot be made by a constructed one.

The seeded-row helper had a bug worth recording: replacing `NOT_IN_PREFLIGHT` wholesale made the
four real owed guards read as unregistered, so arm 1 fired for a reason the arm under test had
nothing to do with, and two arms looked like they were passing on their own subject. Seed rows
are now **added** to the shipped register, never substituted for it.

This does not stop a guard from being added and wired to nothing — it makes that state **red at
the moment it lands** instead of at the moment somebody happens to look. The four earlier
instances each went unseen for months.

## Alternatives considered

**Discover and run every `check_*.py` automatically.** Rejected on the same grounds
[ADR-0232](0232-goal-5-is-a-conjunction-and-neither-instrument-may-claim-the-word-alone.md)
dec. 2 rejected a glob for rigs: a discovered population cannot express an exemption, and this
one demonstrably needs four. It would also have wired four red guards into the gate on the day it
landed and aborted the suite for everyone — the failure this cluster exists to end. A declared
table beats a discovered one whenever a member can legitimately be out.

**Report instead of enforce.** Rejected. The finding is that a report nobody reads is how all
four earlier instances survived; making the fifth a report would reproduce it exactly.

**Make the guard read whether the invoked guard is ENFORCING.** Rejected as scope, and recorded
in dec. 6 as a blind spot rather than left implicit. A guard that is invoked and prints a warning
is a real and separate hole, but conflating it with "is it run at all" would make one number
answer two questions, which is
[ADR-0232](0232-goal-5-is-a-conjunction-and-neither-instrument-may-claim-the-word-alone.md)
dec. 1's finding.
