# The address lands, and arm 1's debt is named rather than hidden

Extraction #3's loop **pass 6** — the build the previous nine decisions were for.
`Battlefield`'s 46 files move to `addons/exmateria_battlefield/`, the `platform` tier
takes its own address at `addons/exmateria_platform/`, and **284 `res://` references are
re-pointed in the same commit**.

The finding is not the move. It is that **arm 1 of `check_addon_portability.py` is
enforcing, the suite gate ABORTs on it, and the move makes ten pre-existing reaches
visible for the first time** — because arm 1 cannot see a file in `src/`. Nine of the ten
are [ADR-0157](0157-extraction-3-is-battlefield-and-its-interface-is-two-names-one-system-reaches.md)
dec. 2's measured outbound debt, enumerated by file and line **before** `Battlefield` was
chosen as extraction #3 and accepted then. The extraction does not create them; it
relocates the observer.

Status: accepted (2026-08-26). Extraction #3, loop pass 6, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Builds
[ADR-0168](0168-the-manifest-is-the-only-register-that-can-say-the-right-files-moved.md)
(the manifest), [ADR-0169](0169-platform-ships-to-its-own-address-and-shipping-a-file-is-not-shipping-a-shader.md)
dec. 2/3/6 and [ADR-0171](0171-the-display-port-is-platforms-and-render-is-the-fold-bracket.md)
dec. 3 (`platform`'s address and its fourth file), and #561 dec. 2/3 (the classifier
collapse and `path_refs.DEFAULT_SCENES`). **BUILT here.** Gates
[#588](https://github.com/timbermania/fft-monorepo/issues/588),
[#589](https://github.com/timbermania/fft-monorepo/issues/589) and
[#590](https://github.com/timbermania/fft-monorepo/issues/590), which were waiting on it.

Code at `c246812cd` + this branch. **Every number below was re-measured on this tree**;
the handoff into this pass said in as many words that three figures in the two before it
were stale by the time they were read.

> ⚠️ **`0184` was free across every remote ref and every local worktree at this commit,
> re-checked immediately before push.** `0176`–`0181` are `feature/world-map-input`'s and
> `0182` is `605-adr-number-collisions`'; neither line merges here.
> [#605](https://github.com/timbermania/fft-monorepo/issues/605) tracks the underlying
> defect. **ADR-0183 shipped with no `CLASSIFICATION.tsv` row** and
> `check_adr_classification.py` was red at trunk because of it — repaired here, with 0184's
> own row, because the guard has no catch-all and an unclassified ADR is a failure.

## Context

Pass 5 closed 9 of 9 and left a build with no decisions in it. What it did leave was four
registers and a warning: `docs/EXTRACTION-3-MOVE-MANIFEST.tsv` (46 rows, `src` frozen at
`cd9d6c88f`), `EXTRACTION-3-PATH-REFERENCES.tsv`, `EXTRACTION-3-VAULT-EDGES.tsv`, and
`docs/EXTRACTION-3-BUILD-TICKET-CRITERIA.md`, whose standing block says
`check_addon_portability.py` **is green** on every pass-6 ticket.

That clause and the pass's own shape are in direct contradiction, and this pass is where
the contradiction had to be settled — see dec. 4.

## Measurement

Re-derived on this branch, not read out of a document.

| | |
|---|---:|
| manifest rows moved | **46** (28 script · 16 shader · 2 scene) |
| `res://` references re-pointed | **284**, across 152 files |
| inbound path references, before → after | **259 → 259** (`out` 33 → 33) |
| `class_name`s the addon publishes | **28** |
| autoloads the addon publishes | **0** |
| arm 1 reaches into a system | **10**, on a named burn-down |
| arm 2 standalone-parse breaks, `Battlefield` | **65** — and **0 self-named**, so ADR-0183 holds |
| arm 3 host `#include` lines | **16 → 0** |
| `classify()` unclassified files | **0**; 118 exact rules all live |

The two counts that matter most are the ones a naive reading gets backwards.

**259 → 259 is the property, not a count of the new tree.** A re-point is correct when the
reference SET is preserved and every member has a new address. `path_refs.py Battlefield
--tsv` reports the same 259 inbound and 33 outbound rows before and after, with every
`target` rewritten. A count taken only after the move cannot distinguish that from having
dropped nine references and gained nine others.

**65 with 0 self-named is ADR-0183's own prediction, arriving.** Post-move arm 2 was
**92** on the pre-#564 tree — 65 reaching outward and **27 naming `Battlefield`'s own
published autoloads from inside**, the half no instrument counted. #564 took the 27 to
zero by publishing `class_name`s instead of autoloads. This tree reads 65 and 0, which is
the check that #564 did not regress and the only place it could have been made.

## Decision

**1. The address lands as ONE commit, and the guard is what decides that — not taste.**

`check_move_manifest.py` arm 3 asserts **set equality** between the addon's source files
and the manifest's `dst` column, and it turns on the moment `addons/exmateria_battlefield/`
exists. Seeded here: with `MapComposer.gd` alone moved, arm 3 reports **46 failures**. So a
directory-at-a-time pass 6 is red at every step but the last, by construction.

The independent reason is the same one #561 dec. 3 and ADR-0157 dec. 6 give from the other
side: **two files carry 226 of the 259 inbound references** — `MapComposer.gd` 115 and
`PlayerCamera.tscn` 112 — and every reference to a moved file has to change in the commit
that moves it. There is no seam inside the 46 that splits those two apart.

**2. `platform` takes its address with FOUR files, and the subdirectory names are the fact
each file encodes.**

`pixel_aspect/psx_par.gdshaderinc`, `dither/psx_dither.gdshaderinc`,
`fixed_point/PsxNum.gd`, `display_port/PSXDisplay.gd` — ADR-0169 dec. 2's three plus
ADR-0171 dec. 3's fourth, as that decision instructed. All **19 `#include` lines across six
buckets** are rewritten here, 8 of them `Battlefield`'s and 11 across `Effects`, `Battle`,
`Cutscene`, `Sprite Rig` and `UI`, on ADR-0169 dec. 3's precedent (`449463b2f` rewrote 23
lines across 71 files to promote the kernel).

ADR-0171 dec. 3 says `PSXDisplay`'s booking lands *"as an exact rule ahead of the
`addons/exmateria_render/` prefix"*. **No exact rule was needed and none was written**: the
file physically leaves that directory, so the `addons/exmateria_platform/` prefix books it
with the other three. The phrasing describes a mechanism for a booking without a move; the
decision it sits in is a move (its own dec. 6 prices `Render` at 707 → 447 lines, which is
`PSXDisplay.gd` leaving). Recorded because the two readings differ and the file is the
evidence.

Naming the directories after the *fact* rather than the file — `pixel_aspect/` for
`psx_par` — is what makes ADR-0146 dec. 2's `ls` test answerable here, and it lets
[ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md) dec. 10's *"only
`par` wants a longer name (`pixel_aspect`)"* be honoured by the **address** today without
renaming the file, which is [#583](https://github.com/timbermania/fft-monorepo/issues/583)'s.

`src/core/Tune.gd` stays in the host, so **`platform` sits at two addresses** until #535's
successor lands. Both rows key on path and both are inside the walk, so no instrument reads
a rebooking (ADR-0146 dec. 5's hole does not reopen) — but `ls addons/exmateria_platform/`
is not the bucket, and this ADR is the only place that says so.

**3. #561 dec. 2's collapse executes: ~27 hand-audited `Battlefield` rules and one
directory rule become one location assertion, and the manifest is what pays for it.**

`classify_blueprint.py` loses nine per-file rows, the `("src/map/", "Battlefield")`
directory rule, and sixteen `assets/shaders/` rows, and gains
`("addons/exmateria_battlefield/", "Battlefield")` with `plugin.gd` booked
`infrastructure` ahead of it. The cost is exactly what #561 dec. 2 named: after the
collapse **the census restates where files were PUT** rather than measuring what
`Battlefield` is, so a file wrongly moved in is booked `Battlefield`, stops being counted
by `touch_matrix.py`, passes goal #5 as the addon's own file, and reads as growth. The
manifest plus arm 3 is the only register that can still say the right files moved
(ADR-0168), and this is the commit that makes that sentence load-bearing rather than
anticipatory.

`WALK_ROOTS` gains both addons. **`check_blueprint_walk.py` caught what the collapse left
behind**: `DEBUG_OWNER`'s `("Map", "Battlefield")` and `("Deadzone", "Battlefield")` stem
rules book no `src/debug/` file once `MapGridOverlay.gd` and `DeadzoneBoxOverlay.gd`
leave. Both are deleted; the census is **byte-identical** across the deletion, which is the
proof they were dead rather than the claim.

**4. 🔴 Arm 1's debt is NAMED in the guard, not hidden and not deferred to a document.**

`ARM1_BURN_DOWN` in `check_addon_portability.py`: six rows keyed on `(addon file, symbol)`,
each carrying its owner, covering ten reach lines.

| lines | reach | owner |
|---:|---|---|
| 4 | `lattice/Tile.gd` → `Battle.Unit` | ADR-0166 dec. 2/3 |
| 2 | `overlay/TileOverlayCompositor.gd` → `Effects.TileOverlayColor` | ADR-0164 dec. 1/2 |
| 3 | `MapComposer` → `ScreenEffectOverlay`, `DynamicGeometryBuilder` → `MapTintOverlay`, `TileCursor` → `SfxRouter` | #589 |
| 1 | `camera/PlayerCamera.gd` → `Debug.DebugConfig` | #590 |

**The argument is that a strictly-green arm 1 makes a SPLIT pass 6 impossible, not merely
awkward.** Pass 6 was ruled multi-session fan-out; the four seam builds above are separately
designed, each with its own test surface. Under a strictly-green arm 1 every ticket but the
last is red by construction, so the criterion forces one unreviewable commit containing an
address change and four behavioural changes at once — which is the shape
[ADR-0167](0167-the-mount-inverts-to-the-host-and-the-fix-was-booked-into-the-bucket-it-drains.md)
already refused on its own ground, that a behavioural change inside a booking correction
makes the numbers unattributable.

This is also the first time the question could arise. Extraction #1's `exmateria_render`
had **zero** outbound system reach; extraction #2 left the walk into a package. `Battlefield`
is the first system extracted **with** outbound debt, and ADR-0157 dec. 2 chose it knowing
that, on dec. 3's inbound reading.

**It is a burn-down, not an exemption, and three properties are what make that true.** It is
a NAMED LIST, never a pattern — #424 measured on this codebase that a filter manufactures
its own debt and cannot tell a triaged break from one that merely matches. **A stale entry
FAILS**: a row whose reach was severed, or whose file is gone, is red exactly as an unlisted
reach is. And the rows PRINT, above the OK line, under a heading that says *"Not a pass:
this is goal #5 unmet, on record."* The shape is `check_par_shaders.BURN_DOWN`, which has
carried eleven `UI` shaders the same way since ADR-0060.

Three seeded arms in `tools/test_check_addon_portability.py` (25 → 28 tests): the shipped
list is live and the tree is green; a row naming no reach is STALE and red; and an unlisted
reach is still red — the last being the control without which a burn-down that swallowed
everything would pass the other two.

⚠️ **The stale arm is scoped to the WALK.** `--root` narrows the subject to one package, so
every row naming a file outside it looks stale for a reason that is not debt being paid.
This turned the tool's own `test_clean_package_exits_green` control red the first time it
ran — the arm is a claim about the walk and only the walk can falsify it.

**5. FIVE instruments were reading a hardcoded directory, and the move is what proved it.
Two were owed by an ADR; three were nobody's.**

- `path_refs.DEFAULT_SCENES` — **owed** (#561 dec. 3). `walk()` takes no `.tscn`, so a
  system's own scenes are supplied by name; unedited, the two scenes silently stop being
  counted.
- `check_par_shaders.py` — **owed** (ADR-0169 dec. 6). `res_rel.endswith(INCLUDE)` on a bare
  basename, with no `.is_file()`, plus a hardcoded fix hint. Now `SEAM_RES` + `.is_file()`.
  Seeded: an `#include` path ending in `psx_par.gdshaderinc` that resolves to **nothing**
  passed before and is red now.
- `check_color_shaders.REQUIRED_CONSUMERS` — **not owed, and nobody had looked.** Three bare
  basenames resolved against `assets/shaders/`. Two of the three moved, and the guard went
  red saying *"expected colour consumer is missing"* — right verdict, wrong fact: it cannot
  tell **missing** from **moved**. Now full project-relative paths. This is ADR-0146 dec. 8's
  rule applied to a POSITIVE arm; dec. 8 and ADR-0169 dec. 6 both state it for negative ones.

- `check_sprite_stretch_globals.PSXDISPLAY` — **not owed.** A `PROJECT_DIR / "addons" /
  "exmateria_render" / "display_port" / "PSXDisplay.gd"` constant, red with *"it is
  missing"*. That file's address has now changed twice — `src/core/` → `exmateria_render`
  at extraction #1, → `exmateria_platform` here — while the constant said it once.
- `tests/MapDebugPanelMountTest.gd`'s arm 3 — **not owed**, and the only one of the five
  that is a TEST rather than a tool. `MAP_DIR := "res://src/map/"`, a directory that this
  commit empties. It failed on **`scanned > 0`**, an assertion its own docstring puts there
  so the arm cannot pass over zero files.

The pattern across all five is one sentence: **a guard root that does not follow the
refactor loses coverage silently** (ADR-0148). What separates the three that surfaced by
themselves from the two that had to be found by reading is that each of the three asserts a
POSITIVE — *the consumer exists*, *the seam file exists*, *`scanned > 0`*. A guard that only
looks for violations goes quiet when its subject leaves; a guard that also asserts its
subject is THERE goes red. **Pass 6 of any system should grep its own guards for the
directories it is about to empty**, and this is the argument for writing the positive arm.

**And widening `WALK_ROOTS` found a sixth thing, which is the same finding inverted.**
`check_no_raw_psx_units.py` scans `src/effects`, `src/scenarios`, `src/projectiles` **plus
every addon root**. `PlayerCamera.gd` lived in `src/scenes/`, which is in none of them, and
carried `posmod(int(round(yaw_rad / TAU * 4096.0)), 4096)` — an ADR-0091 raw-magnitude
violation, byte-identical at trunk and unreported there. Moving the file into an addon put
it in scope. It is routed through `PsxNum.TURN_12BIT` here rather than exempted, because
`PsxNum` is `platform`'s and naming it from inside the addon is a port reach, free on arm 1
(ADR-0139 dec. 12) — where `PsxUnits`, the seam the guard's hint names first, is booked
`Effects` and would have created an arm-1 break to satisfy a jargon guard. `wrap12` is
`a & 0xFFF`, identical to `posmod(a, 0x1000)` for every int, so the substitution is an
identity and not a behavioural change inside a booking correction (ADR-0167's rule).

**6. A `.tscn` that loads stripped of its script is a runtime fact, so it gets a runtime
assertion AND a static one.**

ADR-0157 → *Soft spots*, Spike A measured it headful: the scene loads, Godot prints a parse
error, the node mounts with no script, and **the engine exits 0**. Watching the scene come
up is not a test and `rc` is not the verdict.

- `tools/check_res_paths.py` — **new.** Every *quoted* `res://` literal whose target is a
  source suffix must resolve: **3,730 references across 1,777 files**, one unresolved and
  that one named in `KNOWN_BREAKS` with #533 against it. Seeded: moving `MapComposer.gd`
  without re-pointing reports **115 failures**, which is its reference count.
- `tests/BattlefieldAddonAddressTest.gd` — **new**, registered in `run_all_tests.sh`. Reads
  the manifest, asserts every row is at `dst` and gone from `src`, `load()`s every `.gd` row
  the way `register_all()` does, and for each moved scene **instantiates it and reads
  `get_script()` back off the nodes**, against the script list the `.tscn` file itself
  declares. Red before this commit at **123 failures**, green after at **130 assertions**.

Three design notes, all three from measurement rather than reasoning, and the first two
were **defects the seed found in the guard itself**.

The optional `*`. `project.godot` writes an autoload as `Name="*res://path.gd"`, so one
character sits between the opening quote and the scheme — and the first version of this
guard, which required the quote to be adjacent, was blind to **every autoload entry in the
repo**. Seeding a broken `PSXDisplay` path reported nothing. Extraction #3's own register
counts three `project.godot` autoload rows among its path references, so the blind spot
covered part of this very pass. Fixed, the subject grows by 28 rows in that one file.

The `tools/` directory is **in scope**, departing from `path_refs.py`, which excludes it.
That exclusion is about `.md` prose; `tools/` also holds 120 real `.gd` probes and capture
rigs, and **three of them named a moved file** (`capture_grid_beat.gd`,
`generate_palette_texture.gd`, `render_map_state.gd`). Excluding the directory hid all
three. The false positives the exclusion protects against are Python fixtures with
synthetic `res://` keys, and `.py` is not in `REFERRER_SUFFIXES` to begin with.

The literal must be **quoted**: matching bare
`res://` reports `tests/AudioBusLayoutTest.gd:16`, where the path sits in a `##` docstring
in backticks, as prose about an engine default — this repo's own recurring
assertion-matches-its-own-comment defect, from the other side. And the universe is **source
suffixes only**: every `res://` literal is 4,387 with 16 unresolved, 13 of which are
gitignored ROM-derived assets, and a guard that is red on a correct checkout is a guard
nobody rereads.

## The suite

`tools/run_tests_parallel.py -N 4`, headful on the 4.8 fork, after
`godot --path . --import`:

    PASSED 684 / 689   FAILED 1   THREW 0   HUNG 2   NO_VERDICT 2   CRASHED 0
    30.5 min wall, 117.7 min cpu

**`THREW 0` is the tell that the run is valid** — a stale class cache reports
`Could not find type` for this repo's own `class_name`s and reads as dozens of THREW.
689 is 688 plus this pass's new test.

Every non-PASS is a known and each was checked rather than assumed:

- **HUNG** `GambitScenarioRunnerTest`, `GPUEvasionMixedTest` — pre-existing and unowned.
- **NO_VERDICT** `WorldMapMountTest`, `WorldMapPrimitivesTest` — `[SKIP]`, #586 item 3
  (`assets/world_map/` exists in no worktree).
- **FAILED** `EffectStudioColourColumnTest` — **re-run serially it is 83 passed, 0 failed,
  PASS.** The parallel run failed one assertion, *"the canvas square is UNMOVED across the
  appear ((260.0, 280.0) vs (260.0, 121.0))"*, which is #527's family: an assertion read
  before the deferred relayout has written. ADR-0160's rule applies — a register taken from
  one run reports a verdict, not a flake set — and the handoff into this pass had already
  named this exact test as a previous baseline's unstable failure.

## Consequences

- **`src/map/` no longer exists.** Eighteen files, and all eighteen were manifest rows.
- **`#588` / `#589` / `#590` are unblocked** — they were gated on this commit and each owns
  rows of dec. 4's burn-down.
- **Goal #5 is NOT met for `Battlefield`**, and the pass 9 scorecard should read it as
  partial with the burn-down as its evidence, never as met. Arms 2 and 4 are additionally
  DEBT: 65 standalone-parse lines (61 of them `Tune`, #588's) and five `[shader_globals]`
  bindings the host declares (ADR-0169 dec. 4). Both turn RED the day the addon ships with
  its own `project.godot`.
- ⚠️ **Two of pass 6's four owed instruments are still owed.** ADR-0169 dec. 5's arms 3 and 4
  were already built; ADR-0164 dec. 4's duck-typed-door register (15 → 0 over `src/`, per
  ADR-0170 dec. 5's correction) and ADR-0166 dec. 4's Tile-door register (8 → 0) are not, and
  they belong with the seam builds rather than the address — each measures a population the
  seam change creates.
- ⚠️ **`tools/test_check_addon_portability.py`'s
  `test_kernel_and_port_are_free_and_a_system_is_not` was ALREADY RED at trunk `c246812cd`**,
  verified in a detached worktree of that commit rather than reasoned about. It asserted
  `cross-addon class_name — 4 line(s)`; #594 added `exmateria_spu` to `EXTRACTED` and the free
  set became 55 with nothing failing that said so. Re-pointed onto the ROW its own docstring
  is about, because a count over a set that grows whenever an addon joins the subject tests
  the subject list, not the rule.
- **`RESIDUE.tsv` was regenerated** — the header's `derived over:` line is `WALK_ROOTS` and
  had to gain both addons. The diff is four lines: two headers, `cursor_clut_preview.gdshader`
  moving with its system, and `src/audio/SfxStressTest.gd` 213 → 216 lines, which is
  pre-existing drift `check_residue.py` was already red on at trunk. ⚠️ `residue.py --tsv`
  **writes the file itself and prints a human report to stdout** — redirecting its stdout
  into `docs/RESIDUE.tsv` replaces the register with the report.
- **`Render` goal #7 dropped from 29 platform lines to 3**, which is ADR-0171 dec. 6's
  prediction landing — 26 of the 29 were `PSXDisplay.gd`'s and they left with the file.
  `score_goals.py` now reads `Render` at 7 met / 2 n/a / 1 open. `Battlefield`'s ten goals
  report as open with no rows, which is pass 9's work.
- **`tools/seed_register_all_coverage.py`'s four path anchors were re-cut** against the
  post-move source, and all six anchors verified to match exactly once. Unedited it would
  have gone INERT — the failure mode the handoff into this pass had already measured twice in
  one week. Its `move_file` and `stale_expectation` cases now move a file OUT of the addon,
  since `src/battlefield/` stopped being a fictional destination in the useful sense.
- **`check_test_baseline.py` reports two unrecorded test deletions** (`SfxBusLimiterTest`,
  `TypewriterGoldenDiff`) — verified identical at trunk `c246812cd` and untouched here.
- **`check_root_set.py` still reports two problems**, both pre-existing and neither in the
  gate: `addons/exmateria_sound/demo/demo.tscn` and `addons/exmateria_spu/demo/demo.tscn`
  have no `ROOT_SET.tsv` row. They arrive through `walk_files`' symlink descent and are
  untouched by this commit; `ROOT_SET.tsv`'s two `Battlefield` rows were re-pointed here.
- **`docs/EXTRACTION-3-PATH-REFERENCES.md`'s tables still spell the pre-move addresses**, by
  choice: they are a measurement of a tree that no longer exists, and rewriting the paths
  under prose that reasons about `src/map/` would make the prose lie instead of the paths.
  The `.tsv` beside it is the live register and was regenerated.

## Considered alternatives

- **Sever the ten reaches in this commit and keep arm 1 strictly green.** Rejected on dec. 4:
  it merges four separately-designed seam builds into an address commit, and each of the four
  has its own test surface and its own ADR. It also inverts the gating the map already
  chose — #588/#589/#590 are *pass-6-gated*, i.e. they follow the move.
- **Record the ten as prose in this ADR and leave the guard alone.** Rejected for ADR-0169
  dec. 5's reason for making arm 3 enforcing rather than documented: the failure mode is that
  a later pass forgets one, and *"a note in a document cannot catch that."* A burn-down whose
  stale entries fail is a note the tool rereads.
- **Move the 46 a directory at a time.** Rejected by arm 3's set equality (dec. 1), and
  independently by the 226-of-259 concentration in two files.
- **Rewrite the pre-move addresses throughout `EXTRACTION-3-PATH-REFERENCES.md`, ADR-0157 and
  ADR-0169.** Rejected: those are measurements pinned to a SHA, `check_adr_quotes.py` reads
  them, and a document whose prose reasons about `src/map/` while its paths say
  `addons/exmateria_battlefield/` is worse than one that is honestly historical.
  `docs/pitfalls.md` and `CONTEXT.md` ARE updated, because they are instructions.
