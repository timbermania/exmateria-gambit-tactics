# The mount inverts to the host, and the fix was booked into the bucket it drains

ADR-0159 dec. 5's amendment (b) found `MapComposer` — core `Battlefield`, not a
panel — constructing and registering two of the five `src/debug/` panels that
same decision had just rebooked to `Debug`. It named the shape (*"the production
owner owns the data **and** instantiates the view"*), named the rule broken
(ADR-0068 R1), predicted the exact number (**`→ Debug` 38**), and deliberately
did **not** build it, because a behavioural change riding inside a booking
correction makes the booking's own numbers unattributable.

This is that build. It lands the predicted 38. It also pays for one thing the
prediction could not contain: **the new file the fix is written in was booked
`Battlefield` by the same stem rule the whole map has been fighting**, so the
first measurement of the severance read as **growth** — `→ Debug` 42 → **47**,
and the `DebugOverlay` residue this ticket exists to zero going 2 lines → **4**.

Status: accepted (2026-08-25). Resolves
[#555](https://github.com/timbermania/fft-monorepo/issues/555) on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560) (extraction #3,
loop pass 5). Amends **ADR-0159 dec. 5 amendment (b)** in place (proposed →
built). Cites ADR-0068 R1, ADR-0113, ADR-0140 dec. 1, ADR-0144 dec. 3, ADR-0151,
ADR-0153 dec. 3, ADR-0156 dec. 4, ADR-0164 dec. 4.

## Context

Every figure below was measured in `~/Repos/fft-monorepo-ext3-pass4` on
`refactor/extraction-3-pass-4`, before/after the working tree of this commit.
Buckets are `classify_blueprint.classify()`'s, read per file.

The four lines, at `47402835a`:

```
src/map/MapComposer.gd:475   var skirt_panel  = SkirtDebugPanel.new()
src/map/MapComposer.gd:477   DebugOverlay.register_panel(skirt_panel,  DebugOverlay.Category.SKIRTS)
src/map/MapComposer.gd:479   var render_panel = MapRenderDebugPanel.new()
src/map/MapComposer.gd:481   DebugOverlay.register_panel(render_panel, DebugOverlay.Category.SHADERS)
```

`autoload_reach.py Battlefield` scored lines 477/481 as the **entire**
`DebugOverlay` residue in the system — `DebugOverlay  2 lines / 1 files`, that
one file being `MapComposer.gd`. `touch_matrix.py` scored all four as
`Battlefield → Debug`, two `autoload` and two `class_name`.

## Decisions

### 1. The mount inverts to the HOST, not to self-registration

`#555`'s body says *"the panel registers itself with `DebugOverlay`"*. Taken
literally that has no trigger: a `Control` cannot register itself before someone
constructs it, and GDScript exposes no "a class was loaded" hook an observer
could hang the construction off.

So the mount goes to a new **Debug-side** file, `src/debug/MapDebugPanels.gd`,
with one static `register_map_panels(map_composer: Node)`. `SkirtDebugPanel` and
`MapRenderDebugPanel` are `src/debug/` classes; `Debug` already owned their
declarations, and now owns their mount. `MapComposer` names neither them nor
`DebugOverlay`.

This is the shape ADR-0153 dec. 3 already chose for extraction #2 —
`AudioHostAdapter.register_audio_tab()`, static, idempotent, called by whichever
scene wants the tab — with one difference worth stating: Audio's adapter lives in
`src/audio/` and books to `Audio`, because it consumes a *package's declarations*
(ADR-0113's inversion). There are no declarations to consume here. The panels are
**Debug's own files**, so their mount is Debug's, and **the question of where
`Battlefield`'s host adapter lives is not opened by this ticket.** That question
belongs to [#565](https://github.com/timbermania/fft-monorepo/issues/565)'s move
manifest and [#566](https://github.com/timbermania/fft-monorepo/issues/566).

Six callers, one line each, each inside the debug-panel mount block the scene
**already had**:

| caller | bucket | mount block | map node |
|---|---|---|---|
| `src/scenes/GPUArena.gd` | `assembler` | `_setup_debug_panels()` | `map` |
| `src/scenarios/ScenarioPlayerScene.gd` | `assembler` | `_register_debug_panels()` | `_map` |
| `src/scenes/EffectViewerScene.gd` | `assembler` | `_setup_debug_panel()` | `map` |
| `src/scenes/TrapViewerScene.gd` | `assembler` | `_setup_debug_panel()` | `map` |
| `src/scenes/ProgressionTester.gd` | `assembler` | `_setup_debug_panels()` | `map` |
| `src/scenes/UnitAnimationViewerScene.gd` | `assembler` | `_setup_panel()` | `_map` |

`src/scenes/FireCastReproScene.gd` extends `GPUArena` and calls
`super._setup_debug_panels()`, so it inherits the mount without a seventh line.
`src/scenarios/NavigatorMain.gd` has a `ProceduralMap` node with
`auto_build_on_ready = false` and never calls `change_map`, so it composes no map
and never mounted these panels — it does not get a call, and that is behaviour
preserved, not behaviour dropped.

### 2. The composer is PASSED IN, never looked up

`#555` warns: *"Self-registration needs the panel to find its owner, not the
reverse."* `SkirtDebugPanel` needs the live composer for exactly one thing — its
"Rebuild Mesh" button calls `rebuild_map()`.

A panel that hunts for its owner (`get_first_node_in_group`, a recursive
`find_children` by type string) would trade a **scored** reach for a
**duck-typed** one — which is precisely the hole ADR-0164 dec. 4 was written to
close, and which this map has now paid for three passes running. Every caller
above is already holding the node. It hands it over.

The parameter is typed `Node`, matching `SkirtDebugPanel._map_composer: Node` as
it already was, so `MapDebugPanels` names **no** `Battlefield` type at all.

### 3. The guard moves with the mount, and gains a rebind

`MapComposer._render_setup_done` is a **per-instance** bool. It cannot see a
panel that outlived the scene on the `DebugOverlay` autoload, so a scene reload
(Ctrl+R, click-to-rewind) built a *second* copy of both panels while the
comment above it claimed *"Panels persist on the DebugOverlay across map
changes, so re-running would duplicate them."* The guard was in the wrong place
— AudioHostAdapter's own note, arrived at independently: *"The guard belongs with
the mount, not with one of its callers."*

`register_map_panels` therefore does find-or-rebind, the repo's standard idiom
(`ScenarioPlayerScene._register_debug_panels`): an existing `SkirtDebugPanel` is
re-pointed at the freshly-built composer via a new `rebind()`, preserving its UI
state; `MapRenderDebugPanel` is stateless w.r.t. the composer (a pure `Tune`
view) and is left alone.

⚠️ **A bare `return` guard is worse than the duplicate it prevents.** It keeps
the panel and leaves its button calling into a freed node. The test's arm 2
exists for that one line and nothing else.

### 4. Why a host-side mount and not an autoload — the row that would have gone dead

`MapRenderDebugPanel`'s rows pass **no** default: they read default+hint back
from the `Tune` registry, which is ADR-0068 decision 12's pure-VIEW contract, and
`SkirtDebugPanel`'s "Debug Logging" row does the same for `skirt.land_debug`
(home: `SkirtGeometryGenerator`'s static var, ADR-0140 dec. 5).

`TuneField.add` renders an **unregistered** slug as a permanent read-only
`"(unregistered — owner not booted)"` placeholder and binds nothing — correctly,
since a phantom `null` default would first-write-wins and poison the owner's
later real bind. And `Tune.register_all()` is called **only from tests**: in
production those slugs exist because the owner's `_static_init` ran at **class
load**.

So a boot-time mount (a Debug autoload, or `DebugOverlay._ready`) would build
both panels before `MapComposer.gd` or `SkirtGeometryGenerator.gd` had loaded and
render dead rows for the rest of the session. Every one of the six call sites
above runs **after** its map is composed — verified by line order in each file
and then by probe, below — which is later than the old `_ensure_render_setup()`
mount, never earlier.

### 5. 🔴 The new file was booked into the bucket the fix drains, and the severance read as GROWTH

First measurement after the four lines were deleted:

| register | before | after (unbooked) |
|---|---|---|
| `touch_matrix.py` `Battlefield → Debug` | 42 | **47** |
| `autoload_reach.py` `DebugOverlay` | 2 lines / 1 files | **4 lines / 1 files** |

`classify("src/debug/MapDebugPanels.gd")` returns **`Battlefield`**. The
`DEBUG_OWNER` fragment `("Map", "Battlefield")` matched the filename. The four
lines the ticket deletes reappeared in the file written to delete them, in the
same bucket, plus the mount's own two `register_panel` calls — a **severance
reading as a 5-line regression.**

This is the **fifth** time `("Map", "Battlefield")` has booked a file on its
name. ADR-0140 dec. 1, ADR-0144 dec. 3, ADR-0156 dec. 4 and ADR-0159 dec. 5 each
corrected one. It is also the first time it has caught a file **written by the
fix**, which is a different and worse failure mode than the four before it:
those mis-attributed code that already existed, this one **inverted the sign of
the result** and would have been read as evidence against the change.

`"MapDebugPanels": "Debug"` is added to `DEBUG_EXACT` with the evidence, per
ADR-0140 dec. 1's own rule that a file is *"assigned to the system its own outbound edges land in"*:
this file's are `DebugOverlay`, `SkirtDebugPanel` and `MapRenderDebugPanel` —
**three `Debug`, zero `Battlefield`.**

⚠️ **This is not the shape `classify_blueprint.py:422` forbids.** Its rule — *"a
booking fix must not ride with a decision that quotes the numbers it moves"*,
recorded there as ADR-0141's `src/data/` precedent — governs the **re**-booking of
files a published series has already counted. `MapDebugPanels.gd` did not exist at
`47402835a`; this is its **first** classification, and no prior number contains
it. The four re-bookings ADR-0159 dec. 5 landed were deferred out of ADR-0147 for
exactly the reason that does not apply here.

`("Map", "Battlefield")` still fires on `MapGridOverlay`, so
`check_blueprint_walk.py` stays green (no dead or shadowed fragment) — 645 files,
0 unclassified, 143 exact rules all live.

### 6. What the instruments report, and the one thing none of them can

| register | `47402835a` | after | note |
|---|---|---|---|
| `touch_matrix` `Battlefield → Debug` | 42 | **38** | ADR-0159 dec. 5's predicted number, exactly |
| `autoload_reach` `DebugOverlay` in `Battlefield` | 2 lines / 1 files | **absent** | the residue is zero, not smaller |
| `autoload_reach` standalone-parse breaks | 104 lines / 11 files | **102 lines / 11 files** | `MapComposer` still names `Tune` + `DebugConfig`, so the file count holds |
| `touch_matrix` total cross-SYSTEM | 1044 | **1040** | |
| `touch_matrix` `Debug → Battlefield` | 23 | **23** | the mount names no `Battlefield` type (dec. 2) |
| `score_goals.py` | Audio 4 met / Render 7 met | unchanged | it scores extracted addons; `Battlefield` is not one yet |

🔴 **The limit, named rather than banked.** The six call sites of dec. 1 are
**six new lines**, and every number above is blind to all six: `src/scenes/*` and
`ScenarioPlayerScene.gd` are booked **`assembler`**, which is in
`classify_blueprint.OTHER` and not in `cb.SYSTEMS`, so `touch_matrix`'s matrix
does not have a row for it and its cross-SYSTEM total excludes it. The inversion
costs the host six lines of wiring; the register that reports the win cannot see
the cost.

That is the correct home for wiring — `assembler` is an explicitly enumerated
bucket for scene roots, and each of these six is named individually in
`classify_blueprint.RULES` — but "the right bucket" and "a bucket the scoreboard
reads" are different claims, and this map has now been bitten by the difference
three times (#561's `--delta`, ADR-0164 dec. 4's two faces, and this). **Pass 9
must not read `1044 → 1040` as `−4 net`. It is `−10 scored, +6 unscored`.**

### 7. Verification

`tests/MapDebugPanelMountTest.gd` — 12 asserts, three arms, because the first two
cannot report the event on their own:

1. the mount lands one panel in each category and "Rebuild Mesh" reaches the
   composer that was passed in;
2. a **second** call stacks nothing **and** re-points the survivor at the new
   composer (dec. 3's failure mode);
3. no file under `src/map/` names `DebugOverlay`, `SkirtDebugPanel` or
   `MapRenderDebugPanel` **in code**. Arms 1–2 pass just as well with the old
   registration still sitting beside the new one — only arm 3 reports the
   *removal*. It strips `#` comments first, because the prose in `MapComposer.gd`
   that explains this inversion names `DebugOverlay`, and a raw text match would
   fail on the comment documenting the fix (ADR-0148's shape, inverted).

**Four seeds, run and reverted, each proving one arm can go red:**

| seed | expected | observed |
|---|---|---|
| a code line under `src/map/` naming `DebugOverlay` | arm 3 red | `[FAIL] … res://src/map/MapComposer.gd:469 names DebugOverlay` |
| a **comment** naming all three symbols | arm 3 **green** | 12 passed, 0 failed |
| `register_map_panels` returns without rebinding | arm 2 red | `[FAIL] Rebuild Mesh now reaches the NEW composer (got 0, want 1)` |
| `register_map_panels` mounts nothing | arm 1 red | `[FAIL] … registers exactly one SkirtDebugPanel (got 0, want 1)` |

The comment seed is the one that matters: without it, a green arm 3 is
indistinguishable from an arm 3 that stopped looking.

**Headful, the 4.8 fork, all six scenes** — `GPUArena`, `ScenarioPlayer`,
`EffectViewer`, `TrapViewer`, `ProgressionTester`, `UnitAnimationViewerScene`.
Each printed `Registered panel: Skirts (category: Skirts)` and
`Registered panel: Map Render (category: Shaders)`, and a temporary probe at the
mount confirmed dec. 4's precondition in every one of them:

```
[PROBE] map.atlas_dilate_passes=0 map.uv_snap_centroid=0.0 skirt.land_debug=false skirt.water_skirt_depth=0.15
```

— four real defaults, no `null`, so no row rendered the placeholder.
(`ProgressionTester` prints an unrelated pre-existing
`SCRIPT ERROR: a number is required in operator '%'` from
`_update_stats_display` at `:1216`, 1100 lines from anything this commit
touches.)

Static guards green: `check_debug_panel_tunables` (the mount keeps ADR-0151's
`var X = ClassName.new()` + `register_panel(X` marker shape, deliberately),
`check_blueprint_walk`, `check_addon_portability`, `check_tune_owner_manifest`,
`check_root_set`. `docs/RESIDUE.tsv` regenerated — two line counts, no
attribution change.

## Consequences

- `Battlefield`'s `DebugOverlay` residue is **zero**. Of the four host autoloads
  it still reaches, `Tune` (59) is [#535](https://github.com/timbermania/fft-monorepo/issues/535)'s,
  out of scope by ADR-0159 dec. 3, and `DebugConfig` (32) + `GameLogger` (6) are
  untouched by this ticket and unclaimed by any other.
- ADR-0159 dec. 5's prediction 1 — *"severing a `DebugConfig` gate creates a `Tune` bind, score the two together or the win is bookkeeping"* — is discharged
  on the `Debug` side by a *severance*, which 38 is and a rebooking is not. The
  `platform` side is still open and is
  [#566](https://github.com/timbermania/fft-monorepo/issues/566)'s.
- A latent duplicate-panel bug on scene reload is fixed as a side effect. It was
  never filed; it is recorded here rather than back-filled as a ticket.
- **`assembler` is a blind spot in the cross-system total, and this is the first
  decision to state it as one.** It is not a defect — wiring belongs there — but
  any future claim of the form *"the inversion cost N lines"* must count
  `assembler` by hand. Pass 6 owes two registers already (ADR-0164 dec. 4's
  duck-typed-door 12 → 0, ADR-0166 dec. 4's Tile-door 8 → 0); this adds no third
  register, only the instruction to read the total as two numbers.
- The six call sites are `res://`-free plain `class_name` references, so
  [#565](https://github.com/timbermania/fft-monorepo/issues/565)'s move manifest
  does not inherit six new path references from this commit.
