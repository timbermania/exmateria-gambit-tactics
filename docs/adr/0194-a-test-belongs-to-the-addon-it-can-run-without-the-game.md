# A test belongs to the addon it can run without the game

Eleven tests in `godot-learning/tests/` already reach nothing but an addon. They boot the
host project anyway, are scored by a 692-entry assembly suite, and prove nothing about
whether the addon they exercise could be installed anywhere else. This ADR moves them into
the addon and runs them in a **stranger project** — a Godot project that did nothing for the
addon — so that the guard travels with the thing it guards.

The finding is not the move. It is that **the portability demonstration this repo has been
owed since extraction #2 already exists, fully argued, in
`exmateria-sound/workspace/acceptance/`** — and no in-walk addon has one. `docs/GOALS.tsv`
scores `Audio` goal #4 `open` in exactly these words: *"no guard enters this package, so
every guard is green because it no longer looks … a reading is not a guard."*
[#405](https://github.com/timbermania/fft-monorepo/issues/405) chose to **print** the blind
spot rather than make the guard travel. This makes it travel, for the four addons that never
left the walk.

Status: accepted (2026-08-27). Tracked by
[#652](https://github.com/timbermania/fft-monorepo/issues/652). Builds on
[ADR-0115](0115-a-system-is-a-bundle-that-ships.md) (the ship test),
[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
dec. 3/4 (exclusion at report time, never walk time),
[ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md) (the
failure this ADR must not commit), and
[ADR-0151](0151-an-addon-reaches-no-system-and-a-declarative-panel-is-not-built.md) /
[ADR-0169](0169-platform-ships-to-its-own-address-and-shipping-a-file-is-not-shipping-a-shader.md)
dec. 5 / [ADR-0171](0171-the-display-port-is-platforms-and-render-is-the-fold-bracket.md)
dec. 5 (`check_addon_portability.py`'s four arms). Designed in a `/grill-with-docs` session;
slices are enumerated in #652 and **each decision below carries its own state**. **All twelve are built** across slices 1–5 (decision 1's loop has run twice, for `exmateria_schema` and
`exmateria_battlefield`); Amendments 1–5 record what building them found, including four things this
document asserted that did not survive contact.

> ⚠️ **`0194` was free across every remote ref and every local worktree at this commit.**
> `godot-learning/docs/adr/` reads `0187` on trunk alone, which is the miscount that has now
> fired six times; the true high-water is `0193`, held on branches that have not merged here.
> Counted with `git for-each-ref` over every remote ref **and** an `ls` across all 23 local
> worktrees, not with a local directory listing.
> [#605](https://github.com/timbermania/fft-monorepo/issues/605) tracks the underlying defect.

## Context

The prompt was the user's: *"put our tests with the code they are testing."* The handoff that
carried it into this session proposed a per-system loop that surveys the suite, **thins** each
candidate down to what it really needs, relocates it, and deprecates the assembly entry.

Four of that handoff's load-bearing facts did not survive re-measurement on trunk, and two of
the four change the design rather than the prose:

| the handoff said | trunk `4b7f30433` says |
|---|---|
| the suite is **410** tests | **692**. [#417](https://github.com/timbermania/fft-monorepo/issues/417) adopted 275 previously-unlisted scenes (`e31ca4944`, *"287 scenes were run by nothing"*). 56 `.tscn` under `tests/` are still unlisted |
| batching thinned tests into one scene per system is *"where a 50-minute suite becomes a 1-minute one"* | already run and **refuted**. `run_tests_parallel.py`: *"the gambit runner batches, and Vulkan local-device creation fails 54 of 82 times inside that one process, emitting 43,492 device errors under a green suite"* ([#430](https://github.com/timbermania/fft-monorepo/issues/430)) |
| a *"bare project with only that addon enabled"* is the clause to build | **already built and named.** `stranger_sound/project.godot`: *"A stranger's project, not this repo's. No autoloads, no bus layout, no assets — the point is what the addon does in a project that did nothing for it"* |
| triage on *"no host autoloads"* | wrong axis. `addons/exmateria_platform/README.md`: an `[autoload]` line *"can only be written by the consuming game's `project.godot`. That is an install step, not an interface"* |

The 410 came from `docs/TEST-BASELINE-E2-POST.tsv`'s `# suite_size 410` at `5bed84653` — a
commit that **is** on trunk, 282 tests ago. It is also still written into `scoped_tests.py`
(*"410 engine startups"*), `run_tests_parallel.py` (*"412 times"*, *"~44 minutes"*) and
`_runner_tests.py` (*"410 stems each"*). A number nobody re-derives is a number nobody can
re-derive; three docstrings went stale together because they each recorded it rather than
reading it.

`stranger` is not new vocabulary. It is this repo's established word for a downstream
consumer — ADRs 0117, 0118, 0122, 0126, 0127, 0128 and 0153 all use it, and
`workspace/acceptance/stranger_sound/` is already the noun form on disk.

## Measurement

All figures re-taken on `4b7f30433` in a detached worktree of trunk.

**The candidate set, by `closure.py`'s own walk** — seeds `tests/<stem>.tscn` and
`tests/<stem>.gd`, over the 692 stems `_runner_tests.runner_tests()` expands from the array:

```
692 listed tests
589 reach at least one file under an in-walk addon root
 15 reach one with ZERO src/ and ZERO assets/ in their closure
```

A first attempt at this number, by grep, returned **86**, and it was wrong. `GPUFormula01Test`
counted as `exmateria_battlefield`-owned because its `.tscn` names `MapComposer.gd` and
`PlayerCamera.tscn` — while its script `extends GPUCombatTestBase`, an edge a one-hop scan does
not follow and which drags in the whole host combat engine. The closure walk is the instrument;
a grep over the test file is not. Recorded because the wrong number was five times the right one
and looked entirely plausible.

Of the 15, by host autoload and `RenderingDevice` reach:

| | n | tests |
|---|---|---|
| fully clean | **11** | `ColorRecipeTest` `ColorStackGpuParityTest` `DepthModeTest` `MapAtlasDilateTest` `MapIlluminationDDATest` `MapPaletteFieldObjectTest` `MapStateSelectorTest` `MapTextureAnimatorTest` `MapUVClampBakeTest` `ScenarioEventPathfinderTest` `TileCursorCompositorTest` |
| names an autoload | 3 | `ColorStackTest` (`ScreenEffectOverlay`), `FoldSurfaceTest` (`CompositorAutopilot`), `TunePortTest` (`Tune`, `PSXDisplay`) |
| touches `RenderingDevice` | 2 | `FoldSurfaceTest`, `FoldQuantizePolicyTest` |

Closures are 3–13 files; `tests=2` — the `.gd` and its `.tscn` — for every one of the 11.
**They are already pure addon tests sitting in the wrong directory.** There is nothing to thin.

**What an addon edit costs today**, `scoped_tests.py --files`, ≤3 static hops, of 748 scenes:

```
exmateria_schema/…/ColorRecipe.gd     179
exmateria_battlefield/…/MapComposer.gd 175
exmateria_platform/…/DisplayPort.gd   109
exmateria_render/…/FoldSurface.gd       2
```

The 179 are **consumers** — `GPUArenaTest`, `GPUBerserkTest`, `GPUAOECombatTest`. Moving 11
tests out does not remove them, and this ADR does not claim it does.

**Assertion reporting, across the 11:** 9 print a `%d passed, %d failed` counter; 6 carry the
`ran zero assertions → [FAIL]` guard; `DepthModeTest` and `TileCursorCompositorTest` carry
neither.

**Census exposure:** the 11 test `.gd` are **1,796 lines** against a 169,761-line baseline.

**Engine dependency**, live code and not comments:

| addon | fork-only | evidence |
|---|---|---|
| `exmateria_render` | yes | `fold_bracket/FoldSurface.gd:280` `render_layers = [Fold.FOLD_LAYER]`; `:289` `get_layer_texture(Fold.FOLD_LAYER)` |
| `exmateria_battlefield` | yes | `cursor/cursor_fold_{add,mix,sub}.gdshader`, `overlay/tile_decal_fold.gdshader` — `render_mode … compositor_layer` |
| `exmateria_platform` | no | — |
| ~~`exmateria_schema`~~ | ~~no~~ **yes** | **wrong — see Amendment 2.** `compositing_key/fold_layer.tres` is a `CompositorRenderLayer`; on stock 4.7.1 it does not load and `Fold.gd:22` `const FOLD_LAYER := preload(…)` is a parse error |

`tile_decal_fold.gdshader:13` states it: *"Forward+ / fork only (compositor_layer + engine
Pass B)."* An earlier draft of this ADR cited `compositor_fold` in `FoldSurface.gd` — that
string is in a **comment** recording a migration *off* it, and the citation was this repo's
assertion-matches-its-own-comment defect committed while writing the file that names it.

## Decision

**1. The subject is the addon root, not the system. FILED, not built.**
`classify_blueprint.SYSTEMS` is eleven; only three have an addon (`Battlefield`, `Render`,
`Audio`), and two of the five addon roots (`schema`, `platform`) are `OTHER` buckets and not
systems at all. Eight of eleven systems have **no destination**, so a per-system loop spends
most of its iterations with nowhere to put anything. The loop iterates over the five addon
roots that exist, and gains one each time an extraction lands. It is a ratchet paired to the
extraction line, not a sweep over the suite.

**2. An addon-owned test lives at `addons/<name>/tests/` and ships. BUILT — slice 3, `exmateria_schema`.**
The shipping story is the point: a test that does not travel with the addon cannot be run by
the stranger who installs it. The four in-walk addons already carry `plugin.cfg` + `README.md`
and are shaped as shippable units. `exmateria-sound` excludes `workspace/` from publication —
it ships the addon, not its rig — and that distinction is preserved by dec. 3, not by keeping
tests out.

**3. The rig lives outside the addon, at `tests/stranger/<addon>/`. BUILT — slice 2.**
`run.sh` + `project.godot` are harness, not product; a rig inside the shipped tree would ship a
script naming monorepo paths. Mirrors `exmateria-sound/workspace/acceptance/`.

**4. The stranger run is the guard. The 692-suite does not run these as host scenes. FILED.**
`run_all_tests.sh` hardcodes `SCENE="res://tests/${TEST}.tscn"` (line 2669) from a flat array of
bare stems, so folding addon tests in means teaching it paths — and it would run them **in the
host project**, which is precisely the project whose fixtures the exercise exists to prove
unnecessary. Inclusion in the assembly suite proves nothing new. What closes `Audio` goal #4 is
not *"a guard entered the package"*; it is *"a guard exists that can only be green if the
package stands alone."*

**5. The rig copies the SOURCE tree, and says so on every run. BUILT — slice 2, `exmateria_schema`.**
`stranger_sound` stages the **published** tree through the real manifest, on the argument that
*"copying the source tree instead would test a shape nobody installs"* — and that argument is
airtight **for `exmateria-sound`**, whose published tree differs materially from its source
(`fft_smd.gdextension` is withheld, so the class does not register and the GDScript music driver
runs downstream instead). No such asymmetry exists for the four in-walk addons: `addons/<name>/`
**is** the shipped unit, a manifest would exclude `.godot/` and nothing else, and all six
existing manifests name a top-level monorepo directory with a real public `REPO=` — which none
of these four has. Writing one would assert a publication that does not exist.

The two rigs therefore buy **different claims**, and the rig prints which one it is measuring,
the way `tools/residue.py` prints its own limit rather than reporting a clean register:

- source-copy — *"this addon works in a project that did nothing for it"*
- publish-staged — *"this addon installs the way the ZIP installs"*

The second is strictly stronger. Blurring them is how goal #5 gets oversold.

**6. Staging mode follows PUBLICATION STATUS, not addon identity. BUILT — slice 2, `exmateria_schema`.**
One rig shape for all five — same temp dir, same import pass, same `[PASS]` verdict, same exit
codes, same banner — with exactly **one line** differing: how the tree is obtained. Source-copy
today for the four in-walk addons; an addon graduates to publish-staging on the day it
publishes. `exmateria_sound` is already graduated and its rig is not modified.

A uniform *source-copy everywhere* rule was rejected on measurement: it would hand
`stranger_sound/install_check.gd` a tree containing `fft_smd.gdextension`, failing
`_check_published_shape()` outright — and if that check were then deleted to make it pass, the
C++ sequencer would register and the rig would go green on a code path **no downstream user
runs**. Consistency in the rig; honesty in the one variable line.

**7. Each addon DECLARES its engine, and a fork declaration is CHECKED. BUILT — slice 2, `exmateria_schema`; the arm could not be written as worded here, see Amendment 2.**
`stranger_sound` deliberately runs **stock** Godot and exits 2 rather than pass on the fork.
That is right for an addon with no fork dependency and wrong for two of these four. The engine
requirement is declared in `plugin.cfg` + `README.md`; the rig runs the declared binary. For a
`fork`-declared addon the rig **additionally** boots stock once and asserts
`RenderingServer.is_compositor_layer_supported()` is false.

That last arm is what stops this being a README note. It turns *"we think this needs the fork"*
into a checked fact, and the day the fork's primitives land upstream the check goes **red** and
reports that the addon can be downgraded — a win nobody would otherwise notice. Cost is two
extra boots across the whole rig set, not per test.

`check_addon_portability.py`'s four arms — reach, standalone parse, `#include` path, shader
globals — are **all blind to an engine dependency**. Goal #5's literal words, *"a system could
ship to another tactics RPG with its interface intact"*, are true of `Render` and `Battlefield`
only if that RPG also runs a forked Godot. This is the first instrument in the repo that can
say so.

**8. THINNESS IS THE ENTRY TICKET. The loop moves; it does not thin. BUILT — slice 3; see Amendment 3, where the entry ticket had to be re-cut.**
A test qualifies for the move **because** it is already thin. A non-thin test does not get
thinned — it does not move at all, and reports why.

This is enforced mechanically and not by prose: `check_addon_portability.py` selects its files
with `addon.rglob("*")` — the **whole addon root, recursively** — so a test landing in
`addons/<name>/tests/` is scanned like any other addon file. Arm 1 (names a symbol the
classifier books to a system) and arm 2 (names a bare identifier only an autoload block
declares) reject a non-thin test on arrival. The guard already exists and is already pointed at
the right directory.

An autoload is **not** automatically disqualifying. `addons/exmateria_platform/README.md`
settles it: an `[autoload]` line *"can only be written by the consuming game's `project.godot`.
That is an install step, not an interface."* `TunePortTest` names `Tune` and `PSXDisplay`
precisely because it tests the soft-binding façade that exists for that reason — the README
names it as the guard, and says it *"manufactures the absent case by renaming the autoload
node."* The rule is: **a documented install step is allowed; an undocumented reach is not.**

Thinning is v2, entered deliberately, with the freeze/diff pattern and seeded-defect direction
tests. It is the one step that can leave a test green while it stops testing anything, and with
eleven free moves available it is premature to spend that risk.

**9. `addons/*/tests/` books to a `tests` bucket, EXCLUDED at report time. BUILT — slice 1.**
`classify_blueprint.WALK_ROOTS` is `src, assets` plus the four addon roots. `tests/` is kept out
of the line census *by construction* — it is simply not a walk root. But
`addons/exmateria_schema/tests/` **is inside one**, so moved tests would be walked and
classified as production source: **+1,796 lines** onto a 169,761-line baseline, booked into
`Battlefield` / `schema` / `platform` / `render`, inflating system counts and moving goal scores.
It would read as the refactor adding 1,796 lines of system code, when it wrote none.

ADR-0131 dec. 3/4 is explicit — *"exclusion at REPORT time, never at walk time"* — so the fix is
a classifier **rule plus an `EXCLUDED` entry**, never a walk-time skip. The two instruments then
want opposite things and both get them: portability still scans the tests (dec. 8), the census
subtracts them at report time.

**Sequencing consequence: this lands before any test moves.** Move first and the very first
commit corrupts the baseline register. It is a no-op on today's tree — nothing matches the rule
yet — and the commit that adds it must show the census total unchanged.

> **Built.** The census total is unchanged (169,761 lines in 626 files, before and after), and
> the rule is proven by a seeded positive rather than by that absence: with one real `.gd` under
> `addons/exmateria_schema/tests/`, the classifier books it `tests`, prints it as its own row,
> and the BASELINE line still reads 169,761 / 626. Amendment 1 records the two further
> instruments the same probe found, and the frozen-register question the change forced.

**10. Coverage continuity: the landing run invokes the rigs, and the register carries both counts. BUILT — slices 3 and 5, and BOTH runner arms, not the one this decision names (Amendment 5).**
After the moves `run_all_tests.sh` drops from 692 to 681 and nothing invokes the rigs. A green
681-suite would then be green *because it stopped looking* — ADR-0148's named failure, and the
same sentence `Audio` goal #4 is already scored `open` for.

- `run_all_tests.sh` grows a **final phase** that shells out to each `tests/stranger/<addon>/run.sh`
  and folds the verdicts into the same tally. This does not contradict dec. 4: dec. 4 forbids
  running the tests **as `res://tests/X.tscn` in the host project**; invoking a rig that builds
  its own stranger project is a different act. The cost lands on the **landing** run, which was
  already 692 boots, and is zero on the iterate cycle.
- `freeze_test_baseline.py`'s header gains a `stranger` line beside `suite_size`, so a drop of 11
  in one count is visibly paired with a rise of 11 in the other, **in the same file**. A number
  that moves alone is a number nobody can audit.
- The ledger gains a `# moved` kind — stem, destination, commit — and `check_test_baseline.py`
  arm 3 accepts it alongside `# deleted`, with a new sub-arm: a `# moved` entry must name a path
  that **exists**. A move is not a deletion (the run happened *and* the test still exists), and
  `docs/TEST-BASELINE-E2.tsv` already got into trouble by *"two policies at once and no way to
  say so"*. Recording a move as a deletion would repeat that in the one register built to stop it.

**11. `scoped_tests.py` learns the rigs. BUILT — slice 5.**
When a change is confined to one addon root, the tool stops printing 179 host stems first and
prints the cheap thing first plus the expensive thing still owed:

```
change is confined to addons/exmateria_schema
  run:  tests/stranger/exmateria_schema/run.sh          (4 tests, one boot)
  before landing, also: 179 consumer tests + 1 smoke
```

This is what delivers *"run only what you changed"* as a **command the tool gives you** rather
than a discipline to remember, and it sits inside `scoped_tests.py`'s own two-tier rule —
*"Iterate on the scoped set. Verify a ticket on the full suite."* It also puts the scoreboard in
the instrument: the gap between those two numbers is the measure of whether this loop is paying
off, and an instrument cannot go stale the way a docstring can.

**12. Per-move verification is three arms, and only one costs anything. BUILT — slices 2–3.**
The move-specific risk is not thinning — it is that the test now runs in a **different project**,
and a test that early-returns when a node is absent will pass by doing nothing. A green test
describes the tree it ran in.

1. **Assertion-count parity** — `N passed` in the assembly before equals `N passed` in the
   stranger after. Free; the number is already in the log.
2. **The zero-assertion guard is present on every moved test.** For the two that lack a counter
   entirely it is added in the move commit. This is the **only** edit permitted inside a
   move-only loop, and it is permitted because it is what makes the move auditable — leaving a
   ratchet behind: every addon-owned test can report the event, by construction.
3. **The rig is proven red once per rig** — break the addon on purpose, confirm non-zero exit,
   restore. That the harness reports is a different claim from any test passing.

Seeded-defect testing **per test** is deferred to v2 with thinning: under move-only the
assertions are byte-identical to ones already passing, so arms 1 and 2 cover the real risk.

## Consequences

- **The loop's first eleven iterations require no thinning**, and the eleventh is not the end of
  the work — it is the end of the *free* work. When the clean set is dry the loop stops and
  reports rather than escalating into thinning on its own.
- **`Audio` goal #4 does not close here.** This ADR builds the guard for four in-walk addons;
  `exmateria_sound` already has two rigs, and what goal #4 is scored `open` for is that
  `run_all_tests.sh` invokes neither. Dec. 10's stranger phase is the arm that can close it, and
  it is slice 5.
- **None of this shows on the progress bar.** ADR-0131 excludes `tests/` from the reach
  instruments at report time. Budgeted in #652, not in the metric.
- **`check_addon_portability.py` is owed a fifth arm's worth of claim** — the engine
  declaration — which dec. 7 mechanizes in the rig rather than in the guard. If the rigs are ever
  the wrong home for it, the arm moves to the guard; the claim does not go away.
- **The 15 are a ceiling, not a promise.** `closure.py`'s edges are static, so a runtime-built
  path into `src/` is invisible to the walk. If one of the 11 has one it surfaces as a red at
  slice 3, which is the right place for it to surface, but "11" is not a number to build a
  schedule on.
- **Three tool docstrings are stale on the suite size** (`scoped_tests.py`,
  `run_tests_parallel.py`, `_runner_tests.py`) and one register header records 410 truthfully
  for a commit 282 tests ago. Not repaired here — repairing a number by writing a new number is
  the defect. `_runner_tests.runner_tests()` is the reading that cannot disagree, and the
  docstrings should cite it rather than quote it.

## Considered alternatives

**`godot-learning/tests/<system>/` instead of `addons/<name>/tests/`.** Cheaper and it does not
put test code in a shipped bundle. Rejected: it does not travel, so it cannot be run by a
stranger, and under an architecture-primary goal a directory that scores nothing is a rename.
It would be the right answer if wall clock were the measure — which is part of why wall clock
is not the measure.

**Wall clock as the primary goal.** Rejected. Its headline number just proved unstable (410 →
692 inside one branch), its one large lever is refuted by #430, and relocation alone does not
change boot count — 692 boots stay 692 boots, spread across more directories. Kept as a
consequence with a scoreboard (dec. 11) rather than a promise.

**Batching thinned pure-logic tests into one scene per system.** Rejected on the repo's own
measurement (#430, 54 of 82 local-device failures under a green suite). The refutation is about
repeated `RenderingDevice` creation and might not generalise to pure-logic tests — but
`run_tests_parallel.py` concluded *"process isolation is buying real protection"* and this ADR
does not reopen a settled experiment to save boots it is not measured on.

**Publish manifests for the four in-walk addons, so every rig stages a published tree.** The
uniform answer, and rejected as premature: it asserts a publication that does not exist, and the
manifest would encode nothing except that `.godot/` is excluded. Revisited by dec. 6 the day an
addon publishes.

**Folding addon tests into the 692-entry `TESTS` array.** Rejected by dec. 4 — it runs them in
the host project, which is the project whose absence is the entire claim.

**Splitting the instrument repairs (dec. 9–11) into their own ADR.** Rejected: they are not
independently reversible and would be nonsense without the move. Written as numbered decisions
with their own states rather than as Consequences prose, because this repo has been bitten by
deferred legs hiding in a Consequences section.


## Amendment (2026-08-28): dec. 9 named ONE instrument, and a seeded probe found THREE

Decision 9 is built. Building it found that the classifier was not the only instrument that
keeps tests out of a reading **by top-level path**, and the other two fail in ways dec. 9's
argument did not anticipate — one of them silently, and one of them into the register a human
reads before deleting a file.

The instrument that found them is not a grep. It is a **seeded probe**: put a real
`addons/exmateria_schema/tests/ProbeTest.gd` + `.tscn` in the tree, run every
`godot-learning/tools/check_*.py`, and diff the whole output against the same run without it.
Anything that changes is an instrument with an opinion about an addon-owned test. dec. 9 was
reasoned from `WALK_ROOTS`, which is why it found the one instrument that reads `WALK_ROOTS`
and missed the two that do not.

| instrument | what it does with an addon-owned test | how it fails |
|---|---|---|
| `classify_blueprint.py` | books it to the addon's system | loud in the census, silent in the register: **+1,796 lines** read as system source. dec. 9's own case |
| `check_root_set.py` | `p.parts[0] not in ("tests", "tools")` | **twice.** Check 1 calls the test scene an `UNDECLARED SCENE` — loud. The same expression is also `referrer()`, so a moved test starts counting as a **composition site** and a `component` row it mounts stops being uncomposed — silent, and worse than the loud half |
| `closure.py` → `residue.py` | `SUBJECT` *is* `WALK_ROOTS`, so the test enters the unreached set | nothing reaches a test from a declared root — that is what a test **is** — so every moved test books `orphan`, *"no static claim of any kind"*, in the register that exists to inform deletion |

`residue.py` fails a fourth way, one level down: its evidence origin is `c.split("/")[0]`, so an
addon-owned test's claims book to `addons` — which is EVIDENCE but not a CLASS. Measured with a
probe that names one existing unclaimed file: with the repair the register reads
`src/debug/EffectTimelineView.gd  test  evidence test:1,doc:3`; with the repair disabled and the
same probe in place it reads **`orphan`**, evidence `addons:1`, and the orphan count rises from
4 to 5. `orphan` is the class with no claim on the file at all.

**The general form, and the repair.** An exclusion written as *"the `tests/` directory"* stops
holding the moment a test moves; written as *"a test"* it survives. All four sites now ask
whether a file **is a test**, keyed on `tests/` **or** `addons/<name>/tests/`. This is the same
sentence ADR-0148 is about, applied to instruments rather than to a walk.

**Two things a provisioned rule costs, both paid.**

*`check_blueprint_walk.py` check 2 cannot judge dec. 9's rules.* Its `DEAD DIRECTORY RULE` arm
requires every directory rule to match something walked, and these four deliberately match
nothing on the day they land — that is dec. 9. Check 2 exempts exactly them, and **check 5**
replaces it with the question check 2 never asked: does the rule *fire*. It asserts one rule per
addon walk root, that `classify()` returns `tests` for each (which is the directory-over-directory
shadow check 2 does not look for — a tests rule ordered after its addon's own prefix rule is
dead and books the tests to the system), that `tests` is in `EXCLUDED`, and that it is in `OTHER`
so it is printed before it is subtracted. Proved red five ways: rule shadowed, rule missing,
not excluded, not reported, and a control confirming an ordinary dead directory rule still fires.

*`BASELINE.tsv` is frozen, and adding a bucket is a schema change.* `check_baseline.py` check 2
fired on the first run and asked the question it is built to ask — *"A bucket changed under a
frozen baseline. Decide what that does to the series."* The answer is that it does nothing:
at `de055dc49` the walk was `src/` + `assets/` and `godot-learning/addons/` **did not exist in
the tree at all** (`git ls-tree -r de055dc49 -- godot-learning/addons` is empty), so no file
could have been booked to a `tests` bucket. The row is a MEASURED zero, not a placeholder. The
schema widened; no number moved; `# data_sha256` was recomputed over that one row and nothing
else. The freeze still bites — changing the new row's file count alone goes red.

**What this does not change.** Every other decision is untouched, and the 11 candidates were not
re-measured here. The `closure.py` limit line that states the new carve-out is **conditional on
there being one** — it says nothing today and states itself in the same commit that first puts a
test under an addon, because a note asking a future session to remember is how a stated limit
rots into an unstated one.


## Amendment (2026-08-28): the first rig, and the four things it corrected

Decisions 3, 5, 6 and 7 are built for `exmateria_schema`
(`tests/stranger/exmateria_schema/run.sh`, #652 slice 2). The rig is
`exmateria-sound/workspace/acceptance/stranger_{sound,spu}/run.sh` generalised, with
their contract kept exactly — `mktemp -d` + `trap`, staged fresh every run, one
`-e --quit` import pass before any test, verdict = `^[PASS]`, exit 0/1/**2 loudly
not a pass**. Four things this ADR asserted did not survive contact.

**1. `exmateria_schema` is FORK-ONLY, and the Measurement table said no.** The
table's evidence column was empty for that row, which was the tell.
`compositing_key/fold_layer.tres` is a `CompositorRenderLayer` — a class stock
Godot does not have. Booted on stock 4.7.1 the resource fails to load and takes
`Fold.gd`'s `const FOLD_LAYER := preload(…)` down with it as a parse error, so the
script does not load at all. The other three members (`ColorRecipe`, `ColorStack`,
`DepthMode`) load on stock unchanged. **One member of nine is what makes this
addon fork-only** — which is a more useful reading than "fork-only" and is exactly
the shape a downgrade would have to attack.

The handoff into this work chose `exmateria_schema` as the first rig *"because it
needs no GPU, no fork, and no autoloads"*. Half of that is false and the choice
survives it: no GPU and no autoloads still hold, it is nine files, and it is now
the rig carrying the first checked engine declaration in the repo.

**2. Dec. 7's arm CANNOT BE WRITTEN AS THIS ADR WORDS IT.** The decision says the
rig *"boots stock once and asserts `RenderingServer.is_compositor_layer_supported()`
is false"*. That line is a **parse error** on stock — `Static function
"is_compositor_layer_supported()" not found in base "GDScriptNativeClass"` — so the
script does not load and the arm reports nothing at all, which is the one outcome
worse than reporting the wrong thing. The primitive is absent, not false. The arm
is `RenderingServer.has_method("is_compositor_layer_supported")` **or**
`ClassDB.class_exists("CompositorRenderLayer")`, and it fails if either is true on
the stock engine. The claim dec. 7 wanted is unchanged and is now checkable: run
on the fork, the arm reports `[FAIL] … the primitives landed upstream and the
addon's engine="fork" declaration can be dropped`.

**3. `load()` is not a witness that a GDScript compiled**, and the first version
of the rig's central arm was built on it. A script with a hard parse error still
comes back from `load()` as a non-null `GDScript` — measured on stock, where
`Fold.gd` genuinely fails. `Script.get_instance_base_type()` is empty for exactly
that script and non-empty for every one that compiled, so it is the arm. Seeded
with a member preloading into `res://src/`, the `load()` version was green and the
`get_instance_base_type()` version reports two files by name.

**4. The rig committed dec. 12's own named failure while being written to enforce
it.** The resource arm read `if not ResourceLoader.exists(path): return`. Delete
`fold_layer.tres` and it scored **20 passed, 0 failed** and printed `[PASS]` — *"a
test that early-returns when a node is absent will pass by doing nothing"*, in the
file whose docstring quotes that sentence. Only run.sh's `SCRIPT ERROR` grep caught
it. Both halves are repaired: no early return, and the arm derives its file list
from the staged tree rather than naming `fold_layer.tres`, so the addon's
membership list is not kept in a second place.

**Proved red five ways** (dec. 12 arm 3), each restored:

| seed | reported |
|---|---|
| a member `preload`s `res://src/data/JobDatabase.gd` | 2 files named, `24 passed, 2 failed`, exit 1 |
| a shader seam stops compiling | the include by name, exit 1 |
| `fold_layer.tres` deleted | `Fold.gd` did not COMPILE, exit 1 |
| the addon staged with no source files | *"the staged tree carries no source file"*, `3 passed, 2 failed`, exit 1 |
| the engine arm run on the FORK | `[FAIL]` naming both readings of the outcome |

**Two instruments the rig ran into, both answered without weakening them.**

`tools/check_res_paths.py` resolves every quoted `res://` source literal against
the HOST root. `stranger_sound` stages its harness flat at the staged project's
root and can, because no guard reads that package's tree; staged flat here, all
three of the rig's own literals are unresolved and the guard is red on a correct
checkout — which is how a guard gets ignored. The rig therefore **keeps the
harness's repo-relative path inside the staged project**
(`res://tests/stranger/<addon>/…`), so every literal is true in both. Zero guard
changes; one `mkdir -p` in `run.sh`.

`tools/check_test_list_coverage.py` quantifies over every `.tscn` under `tests/`
with no filter, and its skip vocabulary is closed on the stated grounds that *"a
new KIND of exclusion is a decision, and it should cost a code change"*. Dec. 4 is
exactly such a kind, so the vocabulary gains **`stranger`** — not excluded for a
defect, a cost or a checkout, but because the scene asserts something the assembly
project cannot host. Each rig scene carries a row naming the rig that runs it.
Sharing a stem across rigs would silently overwrite (`scene_stems` is a
`{stem: path}` dict), so rig scene names are prefixed.

**One finding filed rather than fixed:
[#658](https://github.com/timbermania/fft-monorepo/issues/658).**
`check_addon_portability.py` — all four arms — is blind to a `res://` **path**
reach out of an addon. The seeded `preload("res://src/data/JobDatabase.gd")` above
leaves the guard at rc 0 printing *"reach no system"*. Arm 1 reads `class_name`
symbols; a path carries none. That sentence is true of type-shaped reaches only,
and has never been about path-shaped ones. A fifth arm lands green on `schema`,
`render` and `platform` and needs a named burn-down of **11** `res://assets/…`
lines on `battlefield`, which is a triage question and therefore a ticket. The rig
catches it dynamically for the one addon that has a rig; the guard runs on all
four, which is why the claim does not go away.


## Amendment (2026-08-28): the first three moves, and the entry ticket re-cut

`ColorRecipeTest`, `ColorStackGpuParityTest` and `DepthModeTest` live in
`addons/exmateria_schema/tests/` and are run by the rig (#652 slice 3). Dec. 9's
whole argument is now a reading rather than a prediction: **623 lines of test code
landed inside a walk root, booked to `tests`, printed as their own row — and the
BASELINE line still says 169,761 lines in 626 files, with `schema` unchanged at
6 / 1,100.** Assertion parity held exactly, 79 → 79 and 11 → 11.

**THE CLEAN SET IS 8, NOT 11, AND THE INSTRUMENT WAS RIGHT — THE CHECKOUT WAS
NOT.** `MapPaletteFieldObjectTest`, `MapStateSelectorTest` and
`MapTextureAnimatorTest` reach six files under `assets/maps/` between them
(MAP104, MAP056, MAP062). Measured in this worktree they disqualify on the ADR's
own criterion. Measured for the Measurement section above they did not, and the
difference is not the tree: `godot-learning/assets/maps` is a **symlink to a
sibling worktree**, created by `tools/link_worktree_godot_assets.sh`, holding
ROM-derived content git does not track. The figures above were taken *"in a
detached worktree of trunk"*, which has no such link — so `closure.py` could not
see the files, and every test reaching `assets/maps/` read as clean. The reading
was of a checkout missing exactly the files that decide the question.

The general form is worth more than the correction: **a closure walk's answer is a
property of the checkout, not only of the code**, whenever any part of the tree is
gitignored or linked. A candidate census taken on a bare checkout systematically
UNDER-reports reach, and under-reporting reach is the direction that manufactures
candidates.

**"ZERO `src/` AND ZERO `assets/`" IS NOT SUFFICIENT, AND SLICE 3 IS WHERE THAT
SURFACED.** `ColorStackGpuParityTest` loads `res://tests/color_stack_gpu_probe.gdshader`
— a tracked fixture, `#include`ing only the addon's own shader seam, and under
`tests/`, which the criterion does not mention. Moved without it the test fails in
the stranger project with `Cannot load shader`, `0 passed, 11 failed`. The rig
caught it on the first run, which is the outcome this ADR's Consequences predicted
for slice 3 for a different reason. The criterion is: zero `src/`, zero `assets/`,
and **every `tests/` file in the closure is the test's own fixture and moves with
it**. Of the eleven, this is the only one; it was 1 file.

**`TileCursorCompositorTest` IS `exmateria_battlefield`'s, decided on its
subject.** Its closure spans schema + platform + battlefield, and the handoff into
this work flagged it as the loop's first triage judgement. It is not close: the
file it preloads is `addons/exmateria_battlefield/cursor/TileCursorCompositor.gd`
and every one of its assertions is about that producer's fold contract. A file
count would have said battlefield too, but for the wrong reason — the rule that
generalises is dec. 1's, that the subject is the addon, and the subject of a test
is what it asserts about. So `exmateria_schema` took **three** tests, not the four
the handoff listed.

**Dec. 12 arm 2, and the one edit it permits.** `DepthModeTest` threaded a
`failed` boolean and never counted, so a green line described a run of unknown
size. It now carries `_passed`/`_failed` inside its existing `_expect`, prints
`=== DepthModeTest: 35 passed, 0 failed ===`, and fails on zero. No assertion was
touched. There is no pre-move number to compare 35 against, which is the reason
arm 2 exists at all.

**The array keeps a pointer, not a hole.** `tests/run_all_tests.sh` drops from 692
to 689, and where the three entries were there is now a comment naming where they
went and which rig runs them. Three entries vanishing without a trace is how
*moved* and *quietly dropped* become indistinguishable — the same failure the
`# moved` ledger kind exists to prevent one register down.


## Amendment (2026-08-28): the second rig, five more moves, and a fourth instrument

`exmateria_battlefield` has a rig and five addon-owned tests
(`TileCursorCompositorTest`, `MapAtlasDilateTest`, `MapIlluminationDDATest`,
`MapUVClampBakeTest`, `ScenarioEventPathfinderTest`). `run_all_tests.sh` is 692 →
684. Assertion parity held for the four that had counters (7, 27, 2, 32);
`TileCursorCompositorTest` gained one and reports 19.

**The rig is one implementation now.** `tests/stranger/shared/rig.sh`, with
`tests/stranger/<addon>/run.sh` a three-line shim. `plugin.cfg` gains `deps=`
beside `engine=` — the sibling addons the rig stages, which for battlefield is its
own README's *"Dependencies it is allowed to have"*. Both are declarations the rig
READS: an addon that declares no engine, or a dep that is not there, exits 2. This
is dec. 5/6's "one rig shape, one variable line" holding up under a second subject.

**THREE OF BATTLEFIELD'S 29 SCRIPTS DO NOT COMPILE IN A STRANGER PROJECT, AND TWO
OF THEM ARE `ARM1_BURN_DOWN`'s OWN ROWS.** `Tile.gd` (`Could not find type "Unit"`,
ADR-0166 dec. 2/3) and `TileOverlayCompositor.gd` (`Identifier "TileOverlayColor"`,
ADR-0164 dec. 1/2) are booked by `check_addon_portability.py` as *"reach line(s)
leave an addon for a SYSTEM"* — which reads as coupling to be tidied on some later
pass. Off this game they are a **hard compile failure**: the script does not load
at all. Same defect, and the rig is what prices it. The third, `TileCursor.gd`'s
`preload("res://assets/materials/tile_cursor_opaque.tres")`, is
[#658](https://github.com/timbermania/fft-monorepo/issues/658)'s blind spot found
for real rather than seeded.

Debt gets a `known_failures.tsv`, not a threshold: `path`, `ticket`, `error
signature`, `why`, checked in **three** directions — an unlisted file that stops
compiling, a listed file that starts (*"delete the row"*), and a row naming a file
the addon does not have. The signature column is load-bearing, because a broken
script throws whenever anything naming it is loaded and the rig has to be able to
say which throws the list already explains; every other `SCRIPT ERROR` is still the
finding. The banner refuses the flattering sentence: *"stands up in a project that
did nothing for it EXCEPT for 3 named file(s) it does not … Goal #5 is UNMET for
this addon."*

**A FOURTH INSTRUMENT, AND THE ARMING PROBE COULD NOT HAVE FOUND IT.**
`check_move_manifest.py` arm 3 is set equality between
`docs/EXTRACTION-3-MOVE-MANIFEST.tsv` and the addon tree, so five moved tests read
as five files pass 6 moved and did not record. It is the same *a test is not
production source* exclusion as dec. 9's, and Amendment 1's seeded probe missed it
for a reason worth keeping: **that guard is scoped to `exmateria_battlefield`
alone, and the probe was seeded in `exmateria_schema`.** A probe that seeds one
addon cannot find an instrument scoped to another, and the fix for the probe is
not a longer list of guards — it is to seed the addon the next move actually
targets.

**Two arms of the rig's own baseline check were wrong before any of this was
true.** Counting an INCLUDE's uniforms called a seam that declares none broken and
could not tell *compiled, declares nothing* from *did not compile*; and a probe
that supplies a `fragment()` body redeclares a function for a seam that brings its
own. Seven reported failures, three real. Both repaired by asking the question
directly — the probe declares its own uniform after the include, and tries
`spatial` and a bare variant as well.


## Amendment (2026-08-28): coverage continuity, and dec. 10 named the wrong runner

Decisions 10 and 11 are built (#652 slice 5).

**The register carries both counts, in the same file.**
`docs/TEST-BASELINE-E2.tsv`'s header now reads

```
# suite_size   684   tests in the runner's TESTS array
# stranger     2 rig(s), 8 addon-owned test(s)   ... suite_size + these = every test this repo has
```

684 + 8 = 692, which is where this started. Both numbers are DERIVED at write
time by `_runner_tests.stranger_rigs()` / `.addon_owned_tests()` — never stored,
because a stored number is what "410" was in six docstrings on this branch.

**Dec. 10 names `run_all_tests.sh`, and that is not the runner a landing run
uses.** The sequential arm is ~61 minutes; `run_tests_parallel.py` is ~10, and it
is what anyone actually invokes to land. A phase only the slow arm runs is a phase
nobody runs, and *"green because it stopped looking"* is a property of a suite, not
of one script. **Both arms grew the phase.** The parallel arm runs the rigs
sequentially after the pool has drained — each rig stages a project and boots
Godot two or three times, which is exactly the contention its sequential lane
exists for.

**The rigs do not enter the per-test register in either arm**, and this is the
constraint that shaped the phase rather than a detail of it.
`freeze_test_baseline.verdicts()` pairs `^\[\d+/\d+\] Running X\.\.\.` with
`^  -> WORD`, and every archived-run replay reads that pairing; the parallel arm's
`records` list is one row per test, keyed by a stem that names a
`tests/<stem>.tscn`, and `tools/suite_register.py` reads it. **A rig is neither.**
So it prints `[rig i/n] <addon>` and `  => WORD` — visibly the same information,
deliberately a different shape — joins the human-facing SUMMARY and the exit code,
and stays out of `--jsonl`. Verified rather than assumed: `verdicts()` run over a
log containing two rig blocks returns the one real test, and `_banner` still finds
its two-line provenance match.

**Dec. 11, and the scoreboard is real.** For a change confined to one addon root,
`scoped_tests.py` now prints the cheap complete answer first and the expensive one
still owed:

```
CHANGE IS CONFINED TO addons/exmateria_schema
  run:   bash tests/stranger/exmateria_schema/run.sh
         (2 addon-owned test(s), one boot, no host project)
  owed:  177 consumer test(s) + 1 smoke, before landing.
```

That is the 179 this ADR measured, split. An addon with no rig gets told so by
name rather than getting the old undifferentiated list.

**A hole this opened and closed in the same commit.** `scoped_tests.scene_paths()`
enumerated `tests/**/*.tscn` — so the moment eight tests moved into their addons,
a change to `ColorRecipe.gd` scoped to **zero** of the tests written to catch it.
The enumeration now unions `_runner_tests.addon_owned_tests()`, and `--run` emits
each scene's real path instead of assuming `res://tests/<stem>.tscn`. This is the
same defect as dec. 9's, in the one tool whose entire job is to answer *what can
this change break* — and it would have answered "nothing".
