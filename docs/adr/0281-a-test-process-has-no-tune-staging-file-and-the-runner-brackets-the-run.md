# A test process has no Tune staging file, and the runner brackets the run

[#1149](https://github.com/timbermania/fft-monorepo/issues/1149) reported that a
test writes `config/tune_overrides.json` to the **real** path mid-run, and that
nine later tests went red for it — reds that were attributed to the branch under
test. The ticket left one question open for a ruling: *should the runner assert
the file is absent before the run and fail if a test leaves one behind?* This ADR
answers it **no**, and replaces it with a different predicate.

Status: accepted (2026-09-10). Reads
[ADR-0068](0068-tunables-bind-a-slug-to-a-code-default-with-a-coalescing-override-layer.md) for the
staging file, the three persistence classes and the AUTOSAVE gesture this cuts;
[ADR-0051](0051-scene-configuration-lives-in-debug-panels-not-env-vars.md)
for why the test-process detection is a command-line read and not an environment
variable; and
[ADR-0254](0254-an-unattended-loop-may-delete-a-test-and-a-named-survivor-is-what-makes-that-safe.md) dec. 5,
which ruled on the same hazard for the audit loop — *"A loop that inherited that
would have audited a false red."* — and solved it by cutting a fresh worktree, a
remedy the suite does not have.

## Context

**`config/tune_overrides.json` is machine state, and it has poisoned this repo
three times.** ADR-0068 dec. 4 introduced it as a git-tracked, in-repo staging
file: the sparse set of slugs a developer has pinned, shared through the repo so a
dialed value can be drained into code (R6). It stopped being shared on
`90e593900` and is now gitignored, so what it actually holds is the pins of **one
human, on one box**.

| when | what happened |
|---|---|
| #614 | `TileOverlayConfigTuneTest` drove a real `TilesDebugPanel`; its AUTOSAVE edit committed and the tracked file went from **ten entries to one**, taking a deliberate `scenario.active_id` pick with it. `git status` showed a modified file and nothing said a test had done it. |
| `90e593900` | the file churned on every boot and **blocked three consecutive pulls** on the asset hub. Fixed by untracking it — which cured the churn and removed the last signal that a run had written it, because an untracked-and-ignored file is reported nowhere. |
| #1149 | the same test, now leaking into an **absent** file, produced **nine false reds** mid-suite. Which tests flipped depended only on where the write landed in the schedule, so two runs of the same tree disagreed. |

**The leak is one early return.** `TileOverlayConfigTuneTest` already carried a
snapshot-and-restore, and `90e593900`'s commit message cites it as a reason
untracking was safe: *"already carries an `_overrides_existed` flag and restores
the absent case correctly."* It does not. `_restore_overrides` opened with

```gdscript
if not _overrides_existed:
    return
```

so the one transition it never repaired is **absent → present** — which was
harmless while the file was tracked and always existed, and became the *only*
reachable case the moment untracking made absence normal. The defence and the
defect shipped in the same function, and it passed every run it ever made.
Measured here at `f0f9f4d41`: with the file absent, one run of
`TileOverlayConfigTuneTest` reported **11 passed / 0 failed**, and
`config/tune_overrides.json` present afterwards holding `{"tile.selected_type":
2}` — byte-identical to what #1149 found mid-suite.

**The file reaches a test in BOTH directions, and only one of them was noticed.**

* **WRITE.** `TuneField._write` commits an AUTOSAVE slug on every edit, passing
  the *production* default path. A panel constructs its own `TuneField`s, so a
  test that mounts one never gets to pass the documented temp-path seam. One test
  does this today; **nine debug panels** register AUTOSAVE rows, so the next one
  is a normal thing to write, not an unlikely accident.
* **READ.** `Tune._ready` calls `load_overrides()` on every boot, so a pin a human
  dialed in the F3 panel is a silent input to every test in the suite. Four tests
  already carry a hand-written defence against one slug each —
  `NavigatorFormationViewTest`, `NavigatorCommandModeProofTest`,
  `NavigatorGarilandVictoryTest`, `NavigatorTurnDirectorMountTest`, each pinning
  `navigator.stop_on_turn` false because *"a session that ticked it in the F3
  panel leaves it TRUE … and a walk that stops on every turn with nobody to press
  Space does not fail here, it HANGS."* Four gates, one question, discovered one
  hang at a time.

## Decision

1. **A test process has no staging file at all.** `Tune._staging_path` is
   `OVERRIDE_PATH` in the game and **empty** in a test, and empty means *there is
   no file* — not *a different file*. The no-argument verbs (`load_overrides`,
   `save_overrides`, `commit`, `commit_slug`) resolve through it; the two I/O
   primitives treat an empty path as "read nothing, write nothing".

2. **A disabled commit SUCCEEDS.** `_write_dict("")` returns `true`, so the
   in-memory committed baseline still advances and `is_dirty`, the Pin/Reset menu
   and the dirty marker behave exactly as they do in the game. The single
   behavioural difference is that no bytes reach disk, and it is stated in one
   sentence at the seam. A disabled commit reporting *failure* would leave every
   AUTOSAVE slug permanently dirty and red the panel tests that read the marker.

3. **One seam cuts both directions.** Redirecting the path is not a write fix with
   a read fix bolted on: `load_overrides()` and `commit_slug()` resolve through
   the same member, so the boot read and the panel write are cut by the same line.
   This is why the remedy is not a per-test snapshot/restore — a per-test remedy
   is a gate per test, and the four Navigator pins are what that looks like after
   four discoveries.

4. **"Am I a test?" is read off the command line.** `res://tests/` as a prefix of
   any `OS.get_cmdline_args()` entry. That is the one thing every invocation form
   shares — the sequential runner, the parallel runner, `scoped_tests.py`, and a
   hand-typed `godot --path . res://tests/X.tscn` all name the scene as a
   positional argument. Not an environment variable: ADR-0051 bans those for
   exactly this kind of invisible, shell-scoped configuration, and
   `check_no_env_vars.py` enforces it.

5. **An explicit path always wins.** `_resolve_staging` only substitutes for an
   *empty* argument, so `TuneTest` / `TuneFieldTest` / `TuneColorTest` /
   `ScenarioActiveIdAutosaveTest`, which round-trip real files through explicit
   temp paths, are untouched by the redirect and keep testing the persistence
   machinery for real.

6. **The runner brackets the run, and it COMPARES rather than asserting absence.**
   `tools/machine_state_sentinel.py` digests bytes-or-absence of the watched paths
   before the test loop and again after, and reports what moved. Absence is the
   wrong predicate: a developer with pins dialed in has the file legitimately, and
   a check that aborts on its existence makes ADR-0068 R6's sanctioned workflow —
   scrub, then drain into code — unrunnable beside the suite. What a run may never
   do is **change** it. That predicate is true for the developer with pins and for
   a fresh clone alike.

7. **It is not a pre-flight guard, and it could not be one.** A pre-flight guard
   asks a question about the **tree** and runs before any Godot; this one asks what
   the **run** did, so it has to straddle the test loop. It is therefore not named
   `check_*.py` and carries no `check_guard_registry.py` row — but **both arms
   invoke it**, because a check only the arm nobody runs performs is #565's
   finding, and the parallel runner inheriting the guards but not the import-cache
   rebuild is the same shape one level down.

8. **Only the parallel runner scores it red.** It adds one to the red count and
   prints *"the verdicts above are not about this tree"*, because a green tally
   printed beside a changed machine file is precisely the reading #1149 produced.
   The sequential arm reports it and does not fail on it: that arm has never had an
   exit code, and inventing one in the edit that adds a check would change what
   `--sequential` means as a side effect.

9. **The test that leaked is now the direction test for the seam.** The repair is
   deleted from `TileOverlayConfigTuneTest` and a verdict stands in its place. It
   asserts `Tune.staging_path()` is empty **first** — *"no file appeared"* from a
   test whose seam never fired is a zero from a blind instrument — then that the
   real path's presence-and-bytes are unchanged. It is the only test that drives a
   real AUTOSAVE panel row, so it is the only place the seam can be direction-
   tested against the production write path rather than against a mock.

## Considered alternatives

**Fix the early return.** One line: delete the file when it was absent before.
Rejected. It repairs the one test that was caught and leaves the mechanism intact
for the next of the nine AUTOSAVE panels, and it keeps the read direction — the
four Navigator pins — entirely unaddressed. It also leaves the repair inside the
test, where #614 and #1149 have now both shown a repair can carry a defect and
still pass.

**Assert the file is absent in the pre-flight,** which is what #1149 proposed.
Rejected on dec. 6: it is false for a developer with legitimate pins, it fails
*before* the run that would create the file rather than after, and a static
pre-flight cannot see a write that has not happened yet.

**Redirect the test path to `user://` instead of disabling it.** Rejected. `user://`
is shared by every process in the project, so eight parallel workers would write
one file and re-create the cross-contamination one level down; per-PID filenames
avoid that and litter `user://` with ~736 files per suite run. Disabling is also the
more honest statement: a test has no staging file, rather than a secret one.

**Retire the four Navigator pins in the same change.** Deferred, not rejected —
see Soft spots.

**Make `TuneField`'s `path` mandatory at every panel call site,** so a panel must
name its file. Rejected: nine panels and ~40 rows would each carry a path argument
that is the same constant, the failure mode (a new panel that passes the
production path) is unchanged, and it is a gate per call site — the shape dec. 3
exists to refuse.

## Consequences

* A test process reads code defaults, deterministically, on every box. Two runs of
  the same tree can no longer disagree because of what someone dialed in F3.
* An AUTOSAVE gesture inside a test still works end-to-end and still marks clean;
  it simply reaches no disk.
* `TuneField._write`, `TuneField.add`, `add_dropdown`, `build_control`, the two
  context-menu helpers and `DebugConfig.set_active_scenario_id` now default their
  `path` argument to `""` rather than `Tune.OVERRIDE_PATH`. Their docstrings say
  what empty means; `Tune.OVERRIDE_PATH` is no longer a default anywhere.
* A run that changes machine state is now a **red run**, not a set of unexplained
  per-test reds several hundred lines apart.
* `tests/logs/machine_state.json` is written at the start of a run and consumed at
  the end, so a killed run cannot referee the next one.
* `.gitignore`'s comment claiming the file *"stays tracked"* has been false since
  `90e593900` and is corrected here.

## Verification

Four measurements, all at `f0f9f4d41` in one worktree with one warm class cache.

| arm | before the run | after the run | test verdict |
|---|---|---|---|
| **the defect**, seam absent | `config/tune_overrides.json` absent | **present**, `{"tile.selected_type": 2}` | 11 passed / 0 failed |
| **fixed**, absent before | absent | **absent** | 13 passed / 0 failed |
| **fixed**, present before | present, md5 `d20e0b97…` | present, md5 `d20e0b97…` | 14 passed / 0 failed |
| **seeded break** — `if false and _is_test_process()` | absent | **present** | **11 passed / 2 failed** |

The seeded break is the arm that matters: it reds *"the seam fired: a test process
has no staging file"* **and** *"config/tune_overrides.json is absent, exactly as it
was before the panel scrub"*, so the two assertions fail together and neither can
pass by accident. The 13-vs-14 difference between the two fixed arms is the
byte-compare assertion, which only runs when the file existed.

The sentinel is direction-tested on its own 2x2 in
`tools/test_machine_state_sentinel.py` (11 arms): absent→absent and unchanged are
clean, absent→present says CREATED, present→absent says DELETED, a rewrite names
both digests, a missing snapshot is *not* a verdict, and `--compare` consumes the
statefile. Its end-to-end behaviour was measured by hand too: clean exits 0; a
seeded `{"tile.selected_type": 2}` written between snapshot and compare exits 1
naming the creation.

## Soft spots

* **S1 — the four Navigator pins are now redundant and are left standing.** With
  the read direction cut, `navigator.stop_on_turn` cannot arrive from a developer's
  file, so each pin defends against nothing. They are kept deliberately: removing
  four load-bearing-looking lines in the same change that removes the reason for
  them means a hole in the seam would show up as four hangs rather than as one
  failed assertion. They are named here so a later session can retire them in one
  commit instead of rediscovering them one hang at a time.
* **S2 — the detection is a string prefix.** A test scene that does not live under
  `res://tests/` — an addon's own test, run by path — is not detected and keeps the
  production staging file. `addons/exmateria_battlefield/tests/` is exactly that
  shape. No such scene drives an AUTOSAVE panel row today, and the sentinel catches
  it if one ever does, which is the division of labour this ADR intends: the seam
  prevents the known channel, the sentinel reports the unknown one.
* **S3 — one path is watched.** The list is the extension point and the criteria
  are written at it (machine-scoped, untracked, read by a test process). A file a
  test legitimately regenerates must not be added: a false red costs more than it
  catches.
* **S4 — the sequential arm reports and does not fail** (dec. 8). If that arm ever
  grows an exit code, this is one of the things it should carry.
