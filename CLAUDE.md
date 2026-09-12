# CLAUDE.md

Godot 4.8-fork game (compositor fork; never stock 4.7 — see the run section
below): 3D isometric, sprite-based combat rendered from ROM-derived
SEQ/SHP data, with a GPU compute-shader combat engine. Legacy PSX sprite data
is parsed and rendered in a modern 3D environment via custom shaders.

This file is a **router** — it holds only what applies across all tasks.
Subsystem detail and hard-won gotchas live in `docs/` and the 60+ ADRs under
`docs/adr/`; the pointers below say where. When you move a rule out of here,
leave the pointer so the map stays accurate.

- **Pitfalls / common mistakes** → `docs/pitfalls.md` (grouped by domain; the
  high-frequency few are also inlined below). Read it before non-trivial work.
- **Debug overlay & logging** → `docs/debug-panels.md`
- **UI3 component authoring** → `docs/ui3-guide.md`
- **Asset parsing (Python tools)** → `docs/asset-parsing.md`
- **Project vocabulary** → `CONTEXT.md`, which is an INDEX: 37 domain
  clusters under `docs/context/`, 455 terms. Look the term up in the index,
  then open only its cluster — the vocabulary was one 9,001-line file and is
  not meant to be read whole. Edit the cluster, never `CONTEXT.md`, then run
  `uv run python tools/gen_context_index.py`.
- Architectural decisions → `docs/adr/`. Cite them by number when relevant.

## Audio: use the C++ SPU hardware, NOT the C++ sequencer

The audio stack splits into two layers with different rules:

- **DO use the C++ SPU *hardware*** (`libexmateria_spu`, in the
  `exmateria_spu` addon since #384): the PSX SPU emulation (voice registers,
  ADSR, ADPCM decode, reverb). Both music and SFX run on it; shared with the
  DAW. It ships no note table — the pitch mapping is the driver's, and the
  GDScript one does it.
- **Do NOT use the C++ *sequencer*** (the FFT music driver). It is in a
  separate, monorepo-only library (`libfftsmd`) that the publish manifest
  withholds, and `sequencer.gd` reaches it through `ClassDB` by name, so a
  published install simply does not have it. The game drives the SPU with the
  `exmateria_sound` addon's **GDScript** layer — music via
  `SMDPlayer` → GDScript `Sequencer`, SFX via `EffectSoundPlayer` → GDScript
  `Runtime`.

Concretely: **never enable `Sequencer.set_use_native_core(true)`** — it swaps
in the DAW's separate C++ sequencer port, which lacks game-side fixes (e.g.
the end-of-note ADSR2 release force) and causes note-retrigger pops. It does
NOT change the SPU hardware, which runs underneath either way.

## Never run Godot headless — but DO run it headful to verify

**NEVER pass `--headless`.** That flag is the *only* thing banned — it is not
a ban on running Godot. Run it headful and a window opens on the user's
display; stdout/stderr and the log still come back to you, so parse errors and
runtime output surface just as they would headless. So **verify your own work
by running Godot** — "can't run headless, so I can't check it" is a mistake.
To check that scripts merely *parse*, load-and-quit:

```bash
# `godot` = the 4.8 compositor fork (NEVER stock /usr/bin/godot 4.7 — the
# engine-fold compositor is fork-only; under 4.7 folded effects don't render).
# `godot --version` must print 4.8.dev.custom_build. cd into this package first.
godot --path . --quit-after 2 res://assets/scenes/GPUArena.tscn
```

## Running: the always-in-context few

Full catalog in `docs/pitfalls.md`; these bite most often:

- **`--path .` from inside the package root** — never bare `godot res://…`
  (opens the project manager; autoloads/resources won't load).
- **`uv run python tools/…`** for every Python tool (deps in
  `tools/pyproject.toml`).
- **After editing a `class_name` script that subclasses extend, run
  `godot --path . --import`** to rebuild the global class cache — else the
  test runner keeps parsing the OLD base. (`--editor --quit-after N` does NOT
  work; deleting the cache file is NOT enough.)
- **4.8 compositor fork ONLY — never stock 4.7 (`/usr/bin/godot`).** The
  engine-fold compositor is fork-only; under 4.7 it self-disables and folded
  effects (particles + callbacks) silently vanish. Stock 4.7 also downgrades
  `project.godot` (stripping the `4.8` feature) and can't load
  `libexmateria_spu`, silencing the C++ SPU. `godot` on `$PATH` is the fork via
  `/usr/local/bin/godot`; `godot --version` must be `4.8.dev.custom_build`.
- **The suite runs in parallel** — `uv run python tools/run_tests_parallel.py`,
  ~10.5 min at N=8 against ~61 sequential, N derived from free RAM.
  `bash tests/run_all_tests.sh` stays the reference arm and the one to re-take a
  register with. The old rule here said *never run GPU test scenes in parallel*:
  it named the wrong population — **none of the 60 `GPU*` scenes moved** across
  3 repeats, and the one test that did is an EffectStudio scroll acceptance test
  ([ADR-0158](docs/adr/0158-the-suite-runs-in-parallel-and-the-lane-is-a-measurement.md)).
  ⚠️ **N is blind to free VRAM.** With the GPU spoken for (a local LLM holding
  27.8 of 32 GB), 6 of 8 `GPU*` scenes at N=8 fail `Couldn't create Vulkan
  device`, fall back, and **still score PASS** — check `nvidia-smi` before
  believing a parallel GPU number.
- **A battle that takes ~8 s to boot is the DRIVER's shader cache, not our code.**
  `GPUBatchSimulator.initialize()` builds a fresh local RenderingDevice and all 8
  compute pipelines on EVERY battle boot — every seek, scene reload and restart —
  so `rd.compute_pipeline_create()` is cheap only while NVIDIA's own pipeline disk
  cache (`~/.cache/nvidia/GLCache`) still holds them. That cache defaults to a **1 GB
  cap**; a run of this project writes ~25 MB into it and the 736-process parallel
  suite churns far more, so entries get evicted before they are ever re-used and
  every boot pays a cold compile. One line is the whole instrument — and it says
  `CACHE-HIT` either way, because that half is OUR SPIR-V cache, which was never the
  problem:

  ```
  [GPUBatchSimulator] All 8 stages ready in 7739 ms   # cold — GLCache missed
  [GPUBatchSimulator] All 8 stages ready in 24 ms     # warm
  ```

  Two fixes, and you need both. The first is environment, not code:
  `__GL_SHADER_DISK_CACHE_SIZE=8589934592` (8 GB) — measured on the navigator's
  pre-battle seek, 10.5 s → 1.2 s, and cold engine startup 9 s → 3.2 s. The
  second covers the case the cache cannot: **edit a shader and the cache is
  legitimately cold**, because the SPIRV changed.
  `GPUBatchSimulator.warm_pipelines_async()` — called from `NavigatorMain` and
  `GambitBattle` `_ready` — compiles all eight stages on a throwaway device on a
  `WorkerThreadPool` task, so the driver cache is filled *while the world map is
  up* and the battle's own build costs 25 ms. It does not make the compile
  cheaper; it moves it off the frozen screen (measured: 5.7 s of compiling with
  the main loop at 57.8 fps). `GPUArena` deliberately skips it — it builds its
  simulator inside its own `_ready`, so there is no gap to hide the work in.
- **No `OS.get/has_environment` in `src/` or `tests/`** — env-var config *and*
  temporary debug gating (`SCENARIO_*`, `*_DIAG`, …) are banned by
  [ADR-0051](docs/adr/0051-scene-configuration-lives-in-debug-panels-not-env-vars.md)
  and fail the build via `tools/check_no_env_vars.py`. Route toggles and
  throwaway diagnostics through an F3 `BaseDebugPanel` instead. A genuine
  process-state read opts out with a `# env-var-exempt: <reason>` marker.
  Scene config is an `@export` the panel is a VIEW onto; automation calls a METHOD
  (`WorldMapScene.capture_to()` is the worked example). **A rig that must choose
  BEFORE `_ready` runs SETS those exports from `--` user args**
  (`OS.get_cmdline_user_args()`, `--key=value`) — ADR-0051 dec. 5. Not a second
  source of truth, and not the environment: a `--` arg cannot leak in from another
  shell, which is the bug the ban exists for.

## Coordinate system

- **Grid coordinates**: integer `grid_x`, `grid_z` per tile.
- **World coordinates**: `+X = NORTH`, `-X = SOUTH`, `+Z = EAST`,
  `-Z = WEST`, `+Y = UP`.
- PSX coords rotate 180° around X at parser time —
  [ADR-0052](docs/adr/0052-psx-coords-rotate-180-around-x-at-parser-time.md).

## GTE-style depth (PSX ordering table)

**Every 3D mesh MUST use CUSTOM0-based depth.** A mesh using Godot's default
vertex-position depth sorts incorrectly against CUSTOM0 meshes — applies to
map tiles, unit sprites, effect particles, callback meshes, overlays, and any
new mesh type. One model, one implementation —
[ADR-0009](docs/adr/0009-ordering-table-depth-is-one-model.md).

For a new mesh:
1. Bake the face centroid into `CUSTOM0` (RGB_FLOAT) — every vertex of a face
   gets the same centroid (full 3D position, not ground-projected, so elevated
   geometry sorts right; quads use a 4-vertex centroid = PSX GTE AVSZ4).
2. Vertex shader:
   `vec4 c = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0); face_depth = c.z / c.w;`
3. Fragment shader: `DEPTH = face_depth;` (overlays that sit on a surface add a
   small bias, e.g. `+ 0.0001`).

**ArrayMesh required** — ImmediateMesh doesn't support CUSTOM0. Map centroids
come from the exporter (`geometry.py` → `geometry_linked.json` →
`DynamicGeometryBuilder`). Battle shaders that write `POSITION` also need the
`pixel_aspect` seam — see `docs/pitfalls.md` → rendering.

## Animation state

Animation selection is a function of **AnimationState** (IDLE, WALKING,
JUMPING, LANDING, ATTACKING, DAMAGED, DYING, DEAD…), **FacingDirection**
(N/E/S/W), and **camera quadrant** (0-3). Resolution is per-state, one atlas,
one clock per unit — ADRs [0021](docs/adr/0021-animation-resolution-is-per-state-one-atlas.md),
[0034](docs/adr/0034-unit-animation-set-replaces-animation-data.md).

**State-ownership rule:** a system that set a transient state (WALKING,
JUMPING…) must check the unit is still in that state before forcing IDLE, so
interruptions (e.g. damage during movement) are respected.

## Test scenes

- **GPUArena** (`res://assets/scenes/GPUArena.tscn`) — main scene: GPU-driven
  combat arena, strategy phase, roster units, debug panels. The compute shader
  is the single source of truth for combat logic. Controls (ADR-0137 Am. 4 —
  one intent per button, mapped from the PSX face buttons): **Enter** = ○
  CONFIRM (act on the cursored unit: deploy it during the march, open its
  screen + action menu after), **Backspace** = ✕ BACK, **Tab** = △ GO INTO
  the unit's menus (opens its screen with the menu up, never gated), **Space** =
  start the battle (pad START), **Esc** = pause (pad SELECT), Ctrl+R = reset
  (reload scene), F3 = debug overlay, **WASD/Arrows/d-pad** = move the cursor
  AND the menu selection, Q/E = rotate camera. □ is unused. Note Esc is pause
  ONLY — it is not `ui_cancel`; Backspace backs out.
- **CombatUITest** (`…/CombatUITest.tscn`) — primary UI3 test scene; all UI3
  components must be integrated here (see `docs/ui3-guide.md`).
- **ProgressionTester** (`…/ProgressionTester.tscn`) — leveling, job changes,
  stat calculations.
- `tests/` — GPU combat test scenes (GPUMeleeCombatTest, GPURangedCombatTest…);
  run via `uv run python tools/run_tests_parallel.py` (see "The suite runs in
  parallel" above). `bash tests/run_all_tests.sh` is the sequential arm and now
  refuses without `--sequential`.

## The test charter — `docs/TEST-CHARTER.md`

**The suite is 736 processes, not 736 functions.** Godot boots with 28 autoloads in
every one; the cheapest test in the tree measures **2.31 s** warm. So every test you
add costs 2.3 s forever and every one you remove saves 2.3 s forever — and making a
slow test faster is nearly worthless (*"80% of the clock is 66% of the tests"*,
below). **The count is the number that matters.**

Fifteen clauses. **(G)** = guarded by `tools/check_test_charter.py` in the
pre-flight; **(J)** = judgement, audited one test at a time by
`.claude/skills/test-audit-loop`. Evidence for every clause is in
[docs/TEST-CHARTER.md](docs/TEST-CHARTER.md) — read it before arguing one away.

1. **(G) Declare your kind** — `# test-kind: <static-guard|logic|render|gpu|stranger-rig|perf>[ lane-pinned]`.
2. **(J) Take the cheapest kind that can still fail.** No frame needed → `logic`. No
   Godot needed → `static-guard`, and the 2.3 s process disappears. This is the
   biggest lever in the suite.
3. **(J) Load only what you assert on.** A 260-file closure is slow *and* reds for
   reasons that are not yours.
4. **(G) Quit yourself.** The runner passes **no `--quit-after`** — a test that does
   not `.quit()` is killed at 360 s and scored HUNG.
5. **(G) No unbounded waits.**
6. **(J) Budget in ticks, not seconds** — a declared tick budget yields TIMEOUT (a
   verdict); the runner's kill yields HUNG (the absence of one).
7. **(J) Wait on the state, not on a duration** — `tests/lib/await_until.gd`. Faster
   than the sleep *and* immune to the load that made it flaky.
8. **(G) Emit exactly one aggregate verdict.** `NO_VERDICT` is its own outcome.
9. **(G) A green must be a run** — print an assertion count, fail on zero. *"A GREEN
   SUMMARY IS NOT A RUN."*
10. **(G) Must be able to fail** — `# seeded-break: <what to break to red this test>`.
11. **(J) Stable under load, or lane-pinned with a MEASURED pass rate.** A lane entry
    without a measurement is a real bug filed as flakiness.
12. **(G) No environment reads** — [ADR-0051](docs/adr/0051-scene-configuration-lives-in-debug-panels-not-env-vars.md).
13. **(J) Carry every assertion that shares your setup.** ⚠️ **This inverts "one
    assertion per test", on purpose** — a test here is a *process*, so splitting one
    costs 2.3 s forever and merging two that share setup saves it.
14. **(G) Your verdict may not depend on wall-clock time.** No `create_timer` sleeps,
    no real-delta-driven state, no `Time.get_ticks_*` — **except** in a `perf` test,
    which is exempt **and automatically lane-pinned** (a real-time measurement taken
    under N=8 load is not a measurement). Awaiting *frames* is fine and is already
    the dominant idiom here.

15. **(J) A pre-flight step costs SERIAL time.** `run_tests_parallel.py` *waits* on
    `--preflight-only`, so a minute there is a minute at any N. Measured: 84 steps,
    5.7 min, and **73.5% of it is one step** — `test_check_addon_portability`, whose
    13 slow arms each re-run the same ~19.5 s whole-tree walk. Clause 13's twin, on a
    guard. Instrument: `tools/time_preflight.py`; register: `docs/PREFLIGHT-TIMING.tsv`.

Auditing them: `uv run python tools/check_test_charter.py --stats` prints the
burn-down. `tests/charter_allowlist.tsv` is **shrink-only** — a row whose violation
is gone is itself an error.

## Scoping a test run — `tools/scoped_tests.py`

The full suite is **~100 minutes** serial since #417 adopted 275 previously-unrun
scenes (412 -> 687 tests; the measured cost of those 275 alone was 57.7 min at a
11.5 s mean). Most of it is not test work: 59% of
tests finish in under 6s, which is roughly Godot's boot cost, so **more than
half the wall clock is 687 engine startups**. Cutting slow tests barely helps
(80% of the clock is 66% of the tests). Running *fewer* tests is the only lever
that pays, and the only safe way to pick them is to derive them.

```
uv run python tools/scoped_tests.py                       # vs the working tree
uv run python tools/scoped_tests.py --since HEAD~3
uv run python tools/scoped_tests.py --files a.gd b.gd
uv run python tools/scoped_tests.py --depth 3 --run       # emits a runnable command
```

It seeds from the changed files and walks `closure.py`'s seven static edges
**backwards**, so a test is affected when its own closure reaches the change.
Typical result: **~50 tests instead of 687, ~8 min instead of ~100.**

Four things about it that are not incidental:

- **`--depth` is a dial, and the printed reach curve is why.** Unlimited
  transitive closure does not discriminate in this tree — one leaf file
  (`sound_opcodes.gd`) is "reached" by 551 of 744 test scenes at 12 hops and by 6
  at 2. Default 3. **Read the curve before trusting the number.**
- **It is a FLOOR, not a verdict.** Every edge is static, so a runtime-built
  path (`"res://…/%s.gd" % name`) and a duck-typed reach are invisible. A green
  scoped run says nothing about what it did not select. **Iterate on the scoped
  set; verify a ticket, a lift, or a merge on the full suite.**
- **An autoload is a load-time reach, not an assert-time one.** A file an
  autoload reaches is loaded by every test, so a parse error / dangling preload
  / stale arity there fails all of them *identically* — detecting it needs ONE
  test, not 687. The tool prints the hot autoloads and prepends a single cheap
  smoke test. Treating that as "scoping cannot help" is the mistake; it is why
  the first version of this tool bailed out on the whole audio addon.
- **It enumerates every scene under `tests/`, NOT `run_all_tests.sh`'s `TESTS=(`
  array** — and both readings now come from `tools/_runner_tests.py`, so the
  scoper, the runner and `tools/check_test_list_coverage.py` cannot disagree about
  which scenes exist. It used to run its own `glob("*.tscn")`, non-recursive,
  which is why every census said 740 while the tree holds **744** (`tests/tools/`
  has four). Affected tests the runner does not list are flagged
  `<- NOT in run_all_tests.sh`.

  ⚠️ **The array was 412 of 744 until 2026-08-24 and 287 scenes were run by
  nothing at all** (#417) — `run_scene_smoke_tests.sh` covers none of them, its
  six scenes being `assets/scenes/*.tscn`. All 300 unlisted marker-emitting scenes
  were then run once and classified; 275 green ones were adopted, and the 23 that
  did not reach green each carry a row in **`tests/skip_tests.tsv`** naming the
  ticket that holds the finding. **Every scene under `tests/` is now listed,
  declares `[NOT_A_TEST] <why>`, or is skipped with a reason**, and
  `check_test_list_coverage.py` fails the suite pre-flight if that stops being
  true — so "not run" is a decision with a name on it instead of an omission.

- **Eight tests are no longer under `tests/` at all** (ADR-0194, #652). An
  addon-owned test ships inside the addon it guards — `addons/<name>/tests/` — and
  is run by a **stranger rig**, not by the array. `scoped_tests.py` enumerates
  those too and flags them `<- run by a stranger rig, not by the array`; that is
  a different fact from `<- NOT in run_all_tests.sh`, which still means nothing
  runs it. For a change confined to one addon root the tool prints the rig first
  and the consumer tests still owed before landing.

## Stranger rigs — `tests/stranger/<addon>/run.sh` (ADR-0194, #652)

A rig stages a throwaway project that did nothing for the addon — no autoloads, no
bus layout, no assets, no host scripts — copies ONE addon in with its declared
deps, imports once, and runs that addon's own tests there. It is the guard for
`docs/GOALS.tsv` goal #5, and the only one that can go red when an addon quietly
starts needing this game.

```
bash tests/stranger/exmateria_schema/run.sh          # exit 0 pass / 1 fail / 2 could-not-run
```

Both runner arms invoke every rig as a final phase, so the moved tests are not
"absent from the array" in the sense that means *unrun*. Read
`tests/stranger/README.md` before adding one — engine and deps are DECLARATIONS in
`plugin.cfg` the rig reads, debt is a named `known_failures.tsv` and never a
threshold, and a rig has to be **proved red before it is trusted green**.

## Taking a test register — `tools/suite_register.py` (#454, ADR-0160)

`docs/TEST-BASELINE-E2.tsv` is **frozen** — extraction #2's pre-move record — and
must stay that way. To measure the suite's health *now*, take a register instead:

```sh
# one arm, N repeats of the SAME tree (repeats are what make a flake visible)
uv run python tools/run_tests_parallel.py -N 8 --log-dir /tmp/r1 > /tmp/r1.log
uv run python tools/run_tests_parallel.py -N 8 --log-dir /tmp/r2 > /tmp/r2.log
uv run python tools/suite_register.py take \
    --run-log /tmp/r1.log --run-log /tmp/r2.log \
    --log-dir /tmp/r1 --log-dir /tmp/r2 --out /tmp/reg-a.tsv

uv run python tools/suite_register.py diff /tmp/reg-a.tsv /tmp/reg-b.tsv
```

Both runners feed it — the sequential one prints the same per-test lines. Every
header field is read from the **run's own banner**, so a register is comparable
only to one taken under the same harness, and it says what its harness was.

⚠️ **A register from ONE run cannot report a flake set, and says so.** Every row
reads `UNMEASURED×1`, the `flakes` header reads `UNMEASURED — 1 repeat`, and
`diff` calls a difference seen once per side `UNCONFIRMED`, never `MOVED`. That
is not pedantry: **275 of the 687 listed tests are green exactly once** (#417),
and four tests in the archived corpus are not constant across three same-tree
runs. Want `MOVED`? Take two repeats per side.

⚠️ **Registers are artifacts — do not commit one.** A tracked register is a
`tests/logs/` in waiting: checked in, stale within a week, nothing marking it.

🔴 **Read the `environment` header before you read a single row.** A `GPU*Test`
whose own `RenderingDevice` never came up still prints its `[PASS]` marker and
still scores **PASS** — a false GREEN with 0 SCRIPT ERRORs and no failing
assertion names, so nothing else on the row shows it. The `device_lost` column
counts it, per repeat, and `diff` calls a difference against such a row
`ENVIRONMENT` rather than `MOVED` (#547; the sibling of #526, where the *engine*
never started and the row was a false RED). Give **each repeat its own
`--log-dir`** and pass them all — that column is the one thing scanned across
every repeat, and with one dir it can only see one of them.

⚠️ **On a contended GPU the register measures the box.** Free VRAM under ~1 GB is
enough to take the device away from a `GPU*` scene *at N=1, serially*; #526's
N=8 measurement is the parallel case of the same cause. Sample
`nvidia-smi --query-gpu=memory.free` alongside the run so a `FLAKY` row can be
told from a VRAM dip.

## Code organization

```
src/
  animation/   core/   data/   debug/   gpu/   movement/   projectiles/
  scenes/   ui3/   units/
assets/
  abilities/   effects/   maps/   materials/   scenes/   shaders/
  sprites/{animations,textures}/   ui/
tests/         - GPU combat test scenes
tools/         - Python parsers (run via uv; see docs/asset-parsing.md)
docs/          - topic docs + adr/
```

## Conventions

- **`"""triple-quote"""` docstrings on functions are intentional — don't
  delete them.**
- Don't prefix generic systems with "FFT" — use `UIChar`, not `FFTChar`
  (see `docs/pitfalls.md`).
