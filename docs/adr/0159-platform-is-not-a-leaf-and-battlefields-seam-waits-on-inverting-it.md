# `platform` is not a leaf, and `Battlefield`'s seam waits on inverting it

Three extractions have deferred one question — *does `platform` ship beside the
addon, or get injected into it?* — and it has stayed open because **both answers
assume `platform` is a leaf**. It is not. `Tune.register_all()` names **fifteen
files across seven of the eleven systems**, by `res://` path and by `/root/` node
path, and **goal #5's own guard scores that as zero**. The question was never
*ship or inject*; it is *invert the enumeration first*, and neither answer is
available until that is done.

The rest of the seam is small and mostly already decided by documents this
project has already written. What pass 3 adds is that the four remaining items
resolve **by severance, not by placement** — `CursorBob` splits rather than
moves, five debug panels are `Debug`'s by the rule ADR-0068 already states, and
`Tile.reserved_by` becomes the opaque claim `BLUEPRINT.md`'s own contested-resource
table prescribes. Together those take `Battlefield` to **44 files / 7,923 lines,
100 inbound over 7 symbols, and 6 lines of outbound debt**.

Status: accepted (2026-08-24). Resolves
[#531](https://github.com/timbermania/fft-monorepo/issues/531) — extraction #3,
loop **pass 3**, whose map is `docs/agents/refactor-loop.md` and not a
`wayfinder:map`. Measured at trunk **`6a25e54f7`**.

⚠️ **Every figure in ADR-0157's `Soft spots` is a reading of `778183181`, and the
tree has moved.** Two of the commits in between are `Battlefield` severances
landed under [#500](https://github.com/timbermania/fft-monorepo/issues/500) —
`c981f928c` and `7b4f260b1`. See dec. 1.

## Context

Pass 1 chose the system ([#492](https://github.com/timbermania/fft-monorepo/issues/492),
[ADR-0157](0157-extraction-3-is-battlefield-and-its-interface-is-two-names-one-system-reaches.md)).
Pass 2 anchored its vault notes and enumerated its path references
([#500](https://github.com/timbermania/fft-monorepo/issues/500), PR #502), and
handed pass 3 five items. Pass 3 is
[ADR-0126](0126-every-system-pass-audits-before-it-designs.md)'s six checks
followed by the seam design and a prediction.

### The reading — trunk `6a25e54f7`

| | files | lines |
|---|---:|---:|
| `src/map/` | 18 | 4,569 |
| `src/scenes/` | 4 | 1,704 |
| `assets/shaders/` | 16 | 933 |
| `src/debug/` | 7 | 572 |
| `src/effects/` | 2 | 303 |
| `src/scenarios/` | 1 | 148 |
| `src/core/` | 1 | 131 |
| **total** | **49** | **8,360** |

**Inbound 131 cross-system** (`Battle` 92, `UI` 34, `Cutscene` 4, `Effects` 1)
plus **30 from the assembler**. **Outbound 11 cross-system**, 10 of them debt.
And, the reading neither predecessor pass took, **the non-system host surface**:

| bucket | lines | shape |
|---|---:|---|
| `Debug` | 82 | `TuneField` 32 · `DebugConfig` 32 · `GameLogger` 6 · `BaseDebugPanel` 5 · `preload` 5 · `DebugOverlay` 2 |
| `platform` | 74 | `Tune` 66 · shader `#include` 8 |
| `schema` | 23 | `class_name` 12 · `#include` 10 · `preload` 1 |

**Three registers were asked for this census and they agree.**
`classify_blueprint.walk()` counts **49 files / 8,360 lines**; `touch_matrix.py`
reads **IN 131 / OUT 11**; and `check_baseline.py --delta` independently prints
`Battlefield 8360 +113   93 -12   131 +0` against the frozen baseline. Its `out`
column is **93 = 11 cross-system + 82 `Debug`** — it folds `Debug` in and leaves
`platform` and `schema` out, so **pass 9 must not read that column as the
outbound-debt figure**. The `+113` and the `-12` are dec. 1's two severance
commits.

## Decision

**1. Every number in `Soft spots` has moved, and the direction is the finding.**
S4 measured *"120 lines across 13 files"* at `778183181` — `Tune` 62,
`DebugConfig` 45, `GameLogger` 6, `DebugOverlay` 2, plus dec. 2's five
cross-system. At `6a25e54f7` `autoload_reach.py` reads **111**: `Tune` **66**,
`DebugConfig` **32**, `GameLogger` 6, `DebugOverlay` 2, plus the same five.

Two commits landed under #500 in between — `c981f928c` *"a system logs itself"*
and `7b4f260b1` *"a system owns its own switch"* — and they did exactly what
S4's *"the two names are not the same problem"* paragraph predicts: they severed
`DebugConfig` gates by giving the tunable to its production owner.
**`DebugConfig` fell 13 and `Tune` rose 4.** That is the paragraph working, and
it is also the warning: on this seam, **severing a `Debug` reach converts it into
a `platform` reach**, so the `Debug` half cannot be scored without saying where
its residue lands.

The third effect is the one nobody would look for. `c981f928c` added
`"res://src/map/SkirtGeometryGenerator.gd"` to `Tune.register_all()`'s owner
list — **a new `platform` → `Battlefield` path reference, created by the act of
severing a `Battlefield` → `Debug` one.** Pass 2's register of 261 was 4 days old
and is now **262**; regenerated at HEAD with `python3 tools/path_refs.py
Battlefield --tsv`, the diff against `docs/EXTRACTION-3-PATH-REFERENCES.tsv` is
**exactly that one row**, everything else being line-number drift. The register
is sound; it is a snapshot of a moving tree and pass 4 must regenerate rather
than read it.

**2. `Tune.register_all()` names seven of the eleven systems, and goal #5's guard
scores it zero. This is measured, and the instrument is proven live by a seeded
control.**

`platform` is four files and 864 lines — `src/core/Tune.gd` 573,
`src/scenarios/PsxNum.gd` 176, `assets/shaders/psx_par.gdshaderinc` 70,
`assets/shaders/psx_dither.gdshaderinc` 45. `PsxNum` and the two shader includes
reach nothing. `Tune.register_all()` reaches this:

| target | bucket | shape |
|---|---|---|
| `src/units/Unit.gd`, `src/projectiles/Projectile3D.gd` | `Battle` 2 | `res://` in an array literal, `load()`ed through a loop variable |
| `src/map/MapComposer.gd`, `src/scenes/PlayerCamera.gd`, `src/scenes/TileCursor.gd`, `src/map/SkirtGeometryGenerator.gd` | `Battlefield` 4 | ” |
| `src/scenarios/ScenarioWeather.gd`, `…DialogueBoxPool.gd`, `…VM.gd` | `Cutscene` 3 | ” |
| `src/animation/SpriteLayerManager.gd` | `Sprite Rig` 1 | ” |
| `src/ui3/elements/UIChar.gd` | `UI` 1 | ” |
| `/root/PSXDisplay` | `Render` 1 | `/root/` path in an array literal, `get_node_or_null()` through a loop variable |
| `/root/SkirtConfig`, `/root/TileOverlayConfig` | `Battlefield` 2 | ” |
| `/root/AudioHostAdapter` | `Audio` 1 | ” |

**Fifteen reaches, seven systems.** Three instruments were asked and here is what
each returned:

| instrument | `platform` → systems | why |
|---|---:|---|
| `tools/touch_matrix.py` | **0** | `platform` is in `OTHER`, not `SYSTEMS`, so it has **no row** — the reach is invisible by construction, *before* any regex runs |
| `score_goals.outbound_reaches` (= `check_addon_portability.py` arm 1, goal #5) | **0** | its five shapes all require a **literal**: `load("res://…")`, `const X := "res://…"`, `get_node("/root/X"`. A path held in an array literal and dereferenced through a loop variable matches none of them |
| `tools/path_refs.py` | **4** of 6 | it scans for `res://` literals anywhere, so it catches the four scripts — and cannot catch the two `/root/` node paths, which are not `res://` |

The zero was **proven to be blindness and not absence**, on the mutation-seed
standard this map already holds. `platform`'s four files were staged as an addon
root and `outbound_reaches` run against them:

```
UNSEEDED (platform as-is):                                     0 cross-system reaches
SEEDED (one literal load of a Battlefield file):               1 cross-system reaches
    ('…/Tune.gd', 'preload', 'src/map/Tile.gd', 'Battlefield', [576])
```

The guard is live and reporting. It scores `platform` at zero while `platform`
names fifteen files across seven systems.

**And `check_addon_portability.py` cannot be pointed at `platform` at all** — it
validates `--system` against the eleven and refuses anything else, so the only
bucket in the tree whose portability is now in question is the one bucket its CLI
declines to discuss.

**3. Therefore: `platform` ships, it does not get injected — and neither is
available until `register_all()`'s enumeration is inverted. That inversion is
extraction #3's blocking precondition, and it is not `Battlefield`'s work.**

The ranking of the argument matters, so this ADR states it.

**Injection was never on the ballot for half of `platform`.** A GDShader
`#include` takes a string literal the preprocessor resolves at compile time.
There is no uniform, no export, no setter, no autoload — nothing to inject
through. `Battlefield` ships 16 shaders and 8 of their lines `#include`
`psx_par.gdshaderinc` or `psx_dither.gdshaderinc`; 19 shaders across five systems
do the same. Either that file is reachable at a path in the consuming project or
the shader does not compile. **For the shader half the question is *ship or
vendor*, and vendoring a shared codec is what `addons/exmateria_schema/` exists to
prevent** (ADR-0139). So `platform` ships, and `addons/exmateria_schema/` is the
shipped precedent for its shape: an addon other addons name, on 23 lines from
this system alone, that nobody calls debt.

**Injection is not available for the other half either, and for a better reason
than that it is awkward.** A port does not name its clients. `Tune` names four of
`Battlefield`'s files and two of its autoloads. Injecting a `Tune` handle into
the addon does not sever that; it **hides** it, because `register_all()` keeps
working through `load()` right up until pass 4 moves a file — at which point
`load()` returns null, `has_method` is false, and the owner is **silently
skipped**. The code says so in its own comment: *"Guarded by `has_method` so an
owner that has not yet split its binds into a static `register_tunables()` is
skipped rather than crashing."* That tolerance is right for a partly-migrated
codebase and it makes **a moved file indistinguishable from an un-migrated one**.
Pass 4 moves 44 files. This is [#450](https://github.com/timbermania/fft-monorepo/issues/450)'s
recurring shape arriving in the refactor line: **the guard scores a declaration.**

**The inversion is already specified, in this project's own words, for a
different noun.** `BLUEPRINT.md` → *Contested resources are capabilities, not
flags* rejects a central authority *"that owns all units"* — *"such an authority
must enumerate its hosts, dragging battle concepts into what should be generic. A
handle is opaque, so it enumerates nothing."* `register_all()` is that defect with
`Tune` in place of the clock: a central replay that must list its owners, in a
bucket whose entire purpose is to be generic. An owner registers at its own class
load already; the central replay exists so a **test** can re-register after
`Tune.reset()`. That is a test-seam problem and it has answers that enumerate
nothing.

**This ADR does not design the inversion** — it is `platform`'s work, not
`Battlefield`'s, it is owed to seven systems rather than to this one, and it
belongs to whichever pass builds `addons/exmateria_platform/`. What pass 3
settles is that **extraction #3 cannot reach goal #5 without it**, that the
inversion is a precondition rather than a follow-up, and that **`platform` ships**
once it is a leaf.

> ✅ **DESIGNED AND BUILT 2026-08-25 —
> [ADR-0173](0173-a-central-replay-existed-because-reset-destroyed-what-only-the-owners-could-rebuild.md),
> [#535](https://github.com/timbermania/fft-monorepo/issues/535).** The question
> dec. 3 declined to answer — *how does a tunable owner register without a central
> list?* — turned out to be answered by subtraction. Every owner already
> registered at its own class load; the list existed only to undo `_registry.clear()`
> inside `Tune.reset()` for the seven tests that could not live with it. They call
> the new `reset_overrides()` instead, so nothing replays and `Tune` names nobody. `platform` is a leaf: `tools/path_refs.py platform` goes
> **13 outbound references into 6 systems → 3, all of them `res://config/…`**
> (Tune's own files). Two riders for anyone reading dec. 2 forward: goal #5's guard
> is **still blind** to the array-literal shape and could never have certified this
> (`tools/seed_platform_outbound.py` keeps that measured), and *fifteen* undercounts
> the reach — it was **seventeen** by the time it was fixed, four of them `/root/`
> paths no `res://` instrument can see.

> ⚠️ **Amended 2026-08-24, before merge, by a grill of this decision
> ([#534](https://github.com/timbermania/fft-monorepo/issues/534),
> [#535](https://github.com/timbermania/fft-monorepo/issues/535)).**
> **Dec. 3's conclusion holds and its sequencing claim does not.** `platform`
> ships — the shader `#include` leg is unanswerable any other way, and the `Tune`
> leg's mechanism is real: `register_all()` guards on `owner_script != null`, so a
> moved file's `load()` returns null and the owner is skipped without a word. What
> does **not** hold is the sentence in bold above. **Extraction #3 *can* reach
> goal #5 without the inversion**, measured both directions:
>
> - **Outbound.** `Battlefield → Tune` is 66 lines and scores **0**, correctly —
>   `score_goals.outbound_reaches`'s own docstring says *"a port is what a
>   portable addon is ALLOWED to reach"* (ADR-0139 dec. 12). Staging this system's
>   four `Tune` owners as an addon root and running the scan returns **39
>   cross-system rows, 8 of them to a non-`Battlefield` system, and 0 naming
>   `Tune`.**
> - **Inbound.** `platform → Battlefield` is out of scope by **iteration**, not by
>   regex. `outbound_reaches` walks `(PROJECT_DIR / addon_rel).rglob("*")`; with
>   the classifier tables warmed first, the reach loop opens **exactly the four
>   staged files and nothing else** — `src/core/Tune.gd` is never among them.
>   (Instrumenting `Path.read_text` *without* warming the tables reads 546 files
>   including `Tune.gd`, which is `_tables()` building the bucket map, not the
>   scan. The first measurement said the opposite and was wrong.)
>
> So the enumeration is a **`platform` portability defect and a test-seam
> defect**, owed to seven systems — not a `Battlefield` one. It runs **beside**
> pass 4, not in front of it (#535). Dec. 3's own next sentence already said the
> work is not `Battlefield`'s; the *precondition* ranking is what over-reached.
> What genuinely gates pass 4 is narrower and is #534 arm 2, below.
>
> **Three things dec. 3 did not know, all measured at `d30ab194f`:**
>
> 1. **The manifest is already incomplete, and no guard says so.** Thirteen files
>    carry the listed owners' exact shape — `static func _static_init()` calling
>    `static func register_tunables()` — and `register_all()` names **eleven**.
>    Missing: `src/ui3/formation/FormationHoverAnimator.gd` and
>    `src/ui3/formation/FormationMapHost.gd` (4 `formation.*` slugs), the second
>    carrying its own ADR-0068 comment giving the same rationale as the eleven.
>    **Latent, not live** — `FormationMapHostTest` asserts those slugs but never
>    calls `Tune.reset()`, so the class-load binds still stand.
> 2. **"Silently skipped" is true for half of what pass 4 moves.** Of this
>    system's four `res://` owners, `PlayerCamera` (8 `camera.*`) and `TileCursor`
>    (4 `cursor.*`) are asserted after a `register_all()` by
>    `CameraFeelTunablesTest` / `CursorTunablesTest`, which go **red** on a stale
>    path. `MapComposer` (5 `map.*`) and `SkirtGeometryGenerator`
>    (`skirt.land_debug`) are asserted by **no test at all** — those move in
>    silence. `TuneRegisterAllTest` covers **7 of the 15** owners, and its
>    docstring excuses `MapComposer` on the ground that its binds are *"asserted
>    alongside that feature"*: **zero tests reference any `map.*` slug.** The
>    excuse names a coverage location that does not exist. This is #450's shape
>    one level up — the *docstring* scores a declaration.
> 3. **`register_all()`'s second stated home does not exist.** `Tune.gd`'s
>    docstring says *"Its home is tests (after `reset()`) and the F3 registry
>    page."* There are **eight call sites and all eight are tests**; no debug or
>    production file calls it. Dec. 3 asserted the test-seam reading and was
>    right, from a source it did not check.
>
> **And two constraints any inversion inherits, neither recorded above.** `Tune`
> is the **first autoload**, so a compile-time `class_name` edge from `Tune.gd` to
> an owner eager-loads that owner's binds during `Tune`'s own boot, against a Nil
> `Tune` — which is why the list is `load()`ed at call time, and it is a hard
> bound on the fix. And `_static_init` fires once per class load per process, so
> after `reset()` clears `_registry` it cannot re-fire: **that**, not a manifest,
> is why a replay exists at all. Of 31 tests calling `Tune.reset()`, **8** replay.
> A candidate shape and its named cost are in #535.
>
> > ⚠️ **Amended again 2026-08-24 by [#534](https://github.com/timbermania/fft-monorepo/issues/534)
> > arm 2, built.** Two of the three items above are corrected by measurement.
> >
> > - **Item 2's `PlayerCamera` ✅ does not hold.** Dropping `PlayerCamera.gd` from
> >   the manifest in a scratch worktree leaves `CameraFeelTunablesTest` **PASS**:
> >   it instantiates the camera, and the camera's own `_ready` bind runs whether
> >   or not `register_all()` replayed anything, so the removal is invisible to it.
> >   The same mutation turns `CursorTunablesTest` **red** — it scrubs a live
> >   cursor through the registry — so `TileCursor`'s half is real. **Three of the
> >   four owners pass 4 moves were silent, not two.** The `✅` was itself a
> >   coverage claim about a test that cannot report the event, which is item 2's
> >   own finding applied one level further in. Reproduce:
> >   `tools/seed_register_all_coverage.py --case drop_camera_owner`.
> > - **Item 3's sentence is fixed at source.** `Tune.gd`'s docstring no longer
> >   names the F3 registry page, so the quotation above is the pre-fix text, kept
> >   because the finding is about what it said.
> >
> > `TuneRegisterAllTest` now asserts one slug per listed owner — **17 of 17** —
> > and all three of its phases have a seeded red arm. Arm 2 is closed; the
> > inversion (#535) stays open and still runs beside pass 4, not in front of it.


**4. `CursorBob` splits; it does not move.** ADR-0157 dec. 4 asked where it goes
and left the answer to pass 3. The answer is that the question presumes one
thing where there are two.

Measured: `CursorBob` is `class_name … extends RefCounted`, **entirely static**,
holding no state, with **two disjoint APIs over two different ROM encodings**.
`load_step_table` / `cycle_length` / `phase_for_frame` / `offset_for_frame` decode
the tile knife's parallel offset/hold tables and have **one caller**,
`src/scenes/TileCursor.gd`, on 2 lines. `load_glove_pairs` / `glove_period` /
`glove_offset_for_frame` decode WORLD.BIN's threshold pairs and have **six**, all
in `src/ui3/detail/`, on 31. **The halves share no logic** — `load_glove_pairs`
re-implements the file read rather than calling `load_step_table`; the only common
symbol is the `TABLE_PATH` constant, and `assets/sprites/cursor_bob.json` is
`content`, which every system may read.

So the knife half stays with `Battlefield` and the glove half goes to `UI`.
That removes **31 of the 131 inbound lines by severance**, and it makes dec. 4's
corrected reading — *"IN 100 over 7 symbols, of which `Tile` + `TerrainIndex` is
92"* — the **actual** published surface rather than a figure arrived at by
subtracting a misplacement. Pass 2 flagged that the file's only vault anchor is
`[[Start Action Menu]]`, `UI`'s note, naming the glove half; the anchor travels
with the glove half and the knife half needs none.

> **AMENDED at loop pass 4 (2026-08-25, [#551](https://github.com/timbermania/fft-monorepo/issues/551)) — the split's unit is the DATA, not just the class. The conclusion holds; one sentence of its reasoning is false.**
>
> The paragraph above dismisses the halves' one shared symbol like this:
>
> > *"the only common symbol is the `TABLE_PATH` constant, and
> > `assets/sprites/cursor_bob.json` is `content`, which every system may read."*
>
> 🔴 **`cursor_bob.json` was never `content`.** `classify_blueprint.classify()`
> returns **`None`** for it — as it does for every `assets/sprites/*.json` —
> and `path_refs.py` reports its target bucket as **`?`**. `content` is a real
> bucket with a stated rule (ADR-0156 dec. 1); this file is in **no bucket at
> all**. The dismissal reads *absence of measurement* as *permission to share*,
> and those are opposite things.
>
> That matters because of what it hides. Splitting the class alone leaves
> `TileCursorBob` and `GloveCursorBob` **both** naming
> `res://assets/sprites/cursor_bob.json`, i.e. one `res://` literal duplicated
> across a system boundary — and **every instrument scores that at zero**:
> each system still shows exactly one outbound reference, and because the
> target is unbucketed neither reference counts as debt. The seam would read
> as severed on all five instruments while a shared asset still joined the two
> systems. This is #551's recurring shape for the second time in one pass:
> **an instrument built to price a change cannot see the duplication the
> change introduces.**
>
> **Decision: split the data with the class.** `tools/parse_cursor_bob.py` now
> writes two documents — `assets/sprites/tile_knife.json` (`tile_knife`, read
> by `Battlefield`) and `assets/sprites/glove_cursor.json` (`glove_idle` +
> `glove_select`, read by `UI`). **One generator still writes both**: the ROM is
> one source, so ROM-faithfulness stays single-sourced and provable against the
> disassembly. Verified content-identical to the retired single asset on all
> three tables at the moment of the split.
>
> **The prediction table's dec. 4 rows are unaffected in the direction that
> matters, and one is better than predicted.** Measured at build:
>
> | term | predicted | measured | |
> |---|---:|---:|---|
> | inbound, cross-system | 100 | **100** | ✅ exact |
> | outbound, cross-system | 11 | **11** | ✅ unchanged (dec. 6 not yet built) |
> | → `Debug` | 82 | **82** | ✅ unchanged (dec. 5 not yet built) |
> | lines | −42 (glove half) | **−53** | ⚠️ see below |
> | inbound path references | 262 → 258 | **266 → 262** | ⚠️ re-attributed |
>
> - **`lines` −53, not −42.** `CursorBob.gd` was 147; `TileCursorBob.gd` is 94.
>   The extra comes from documentation, not code: each half now has to say what
>   it is **not**, because the failure this split exists to prevent is a reader
>   treating the two encodings as interchangeable. `UI` gains 73. Booked
>   honestly rather than smoothed.
> - **The `262 → 258` row is right about the destination and wrong about the
>   arithmetic.** HEAD is **266**, not 262 (#551: `TuneRegisterAllTest.gd` added
>   four rows between passes). dec. 4 removes **four** on its own — three
>   redundant `preload` consts in `DetailScene` / `StartActionMenu` /
>   `EquipPickerMenu` and one in `FormationStartMenuTest`, all of which named
>   `CursorBob` by path where a `class_name` was already in scope, as the other
>   three menus did. That lands at **262**. dec. 3's inversion then removes its
>   own four to reach **258**. Same destination, different route; pass 9 must
>   not read the −4 as dec. 3's.
>
> **Prediction 2 is answered NO, and for a reason this ADR did not have.** The
> ADR proposed inlining the knife half into `TileCursor` if it has no other
> conceivable caller — which it nearly does not: 2 call sites in 1 file, and 2
> of its 5 functions (`cycle_length`, `phase_for_frame`) have **zero**
> production callers. But `TileCursorBobTest` drives all four public functions
> as **pure statics against literal ROM ground truth, with no node in the
> tree**, and `TileCursor` is a `Node3D`. Inlining converts a ROM-faithfulness
> oracle into something that needs a scene to run. ADR-0046 exists *because*
> the bob is ROM-faithful, so that testability is load-bearing. The `class_name`
> stays and inbound symbols stay at **7**, not 6.
>
> **Naming (goals #2 / #7), which is this pass's to settle:** `TileCursorBob`
> and `GloveCursorBob`. Not invented here — `CONTEXT.md` has said
> *"Tile-cursor bob"* / *"Glove-cursor bob"* and *"name the cursor when you say
> 'bob'"* since long before this extraction. The vocabulary was already correct;
> it simply had no type to hang on. ⚠️ Two docs asserted the glove half had
> **no consumer yet** — `CONTEXT.md` and `parse_cursor_bob.py`'s own docstring —
> while six `src/ui3/detail/` menus used it on 25 call sites. Both corrected.

**5. The five `src/debug/` tunable panels are `Debug`'s, by the rule ADR-0068
already states — and this is where S4's failed hypothesis actually fails.**

S4 tested *"leave the debug panels in the host and the debt goes with them"*
against the autoload count and reported it recovers **7 lines of 115**. Measured
over the whole host surface rather than the autoload half of it, it recovers
**49 of 156**:

| file | `TuneField` | `BaseDebugPanel` | `preload` | `Tune` | total |
|---|---:|---:|---:|---:|---:|
| `CursorDebugPanel.gd` | 7 | 1 | 1 | 6 | 15 |
| `CameraFeelDebugPanel.gd` | 8 | 1 | 1 | — | 10 |
| `TilesDebugPanel.gd` | 7 | 1 | 1 | 1 | 10 |
| `MapRenderDebugPanel.gd` | 6 | 1 | 1 | — | 8 |
| `SkirtDebugPanel.gd` | 4 | 1 | 1 | — | 6 |
| | | | | | **49** |

**S4's hypothesis was not wrong; it was scoped to autoloads, and 42 of these 49
lines are `class_name` and `preload`.** `TuneField` is `Debug`'s widget and it is
32 of them.

The rebooking is not opportunism about a number. It is the rule ADR-0068 and the
`tunable-compliance` loop already state — **the production owner holds the
tunable and the debug panel is a pure view** — and it is the same argument dec. 4
made for `CursorBob`: a file booked to a system by a classifier rule, whose
content belongs to its consumers. `WorldMapDebugPanel.gd` went the same way under
ADR-0156 dec. 4. The two commits in dec. 1 above are this rule being applied to
these very panels' *tunables*; this applies it to the panels.

`src/debug/MapGridOverlay.gd` (143 lines, named by `Cutscene` on 2) and
`src/debug/DeadzoneBoxOverlay.gd` (34) are **not** rebooked: they are scene-tree
overlays that draw the lattice and the camera deadzone, not views onto a
registry. They stay.

> **AMENDED at loop pass 4 (2026-08-25, [#551](https://github.com/timbermania/fft-monorepo/issues/551)) — built, and the rebooking EXPOSED an ADR-0068 violation the misbooking was hiding.**
>
> Built as five `DEBUG_EXACT` entries. Every figure this decision predicted
> reproduces **exactly**: files **44**, `Tune` **59 / 6 files**, `DebugConfig`
> **32 / 8**, `GameLogger` **6 / 1**, `DebugOverlay` **2 / 1**, → `platform`
> **67**. Prediction 1's warning — *"severing a `DebugConfig` gate creates a
> `Tune` bind, score the two together or the win is bookkeeping"* — is
> **discharged**: none of the five panels holds a single `DebugConfig`,
> `GameLogger` or `DebugOverlay` line, so the 40-line residue lives entirely in
> files this decision does not move, and the `→ platform` row already scored the
> 7 `Tune` lines that leave with the panels.
>
> **Two things the table did not predict.**
>
> **(a) The build has a mandatory second half.** Rebooking the five into
> `DEBUG_EXACT` kills four `DEBUG_OWNER` fragments — `"Camera"`, `"Tile"`,
> `"Cursor"`, `"Skirt"` — because `check_blueprint_walk.py` excludes
> `DEBUG_EXACT` stems when testing a fragment for liveness (`:78`). The guard
> goes **red with exactly those four** and must be satisfied by deleting them.
> `"Map"` and `"Deadzone"` correctly survive on `MapGridOverlay` and
> `DeadzoneBoxOverlay`, the two this decision leaves in place — so the guard also
> confirms dec. 5's *scope*, not just its arithmetic.
>
> **(b) 🔴 `→ Debug` is 42, not 40 — and the two extra lines are the finding.**
>
> ```
> src/map/MapComposer.gd:475:  var skirt_panel  = SkirtDebugPanel.new()
> src/map/MapComposer.gd:479:  var render_panel = MapRenderDebugPanel.new()
> ```
>
> `MapComposer` — core `Battlefield`, not a panel — **constructs two of the five
> panels this decision just rebooked**. While they were miscounted as
> `Battlefield`'s, those two lines were internal and invisible. Booked correctly
> they are a cross-system reach, so the drop is **−40 with +2 newly exposed**,
> not the flat −42 the table assumed.
>
> That is not an argument against the rebooking — it is the rebooking working.
> The comment immediately below the construction site is dec. 5's own evidence:
> *"Map render tunables — **OWNED HERE (ADR-0068 R1)**, not in the debug panel …
> `MapRenderDebugPanel` is a pure **VIEW**."* ADR-0068 R1 is honoured for the
> **tunables** and broken for the **wiring**: the production owner owns the data
> *and* instantiates the view. **The misclassification was hiding a violation of
> the very rule cited to justify reclassifying.**
>
> ⚠️ **Not built here, and deliberately.** Inverting it — the panel registers
> itself with `DebugOverlay` instead of `MapComposer` constructing it — would
> remove **four** lines from `Battlefield` (these 2 plus the 2
> `DebugOverlay.register_panel` calls that are the whole of the `DebugOverlay`
> autoload residue) and take `→ Debug` to **38**, below the predicted 40. It is a
> *severance*, which is what prediction 1 asked for and what a rebooking by
> itself is not. It is left out of dec. 5 because it changes **runtime**
> registration order rather than a classifier table, and dec. 5 is scoped as a
> booking correction. **Proposed as its own decision; do not let pass 9 score the
> 42 as a miss without it.**
>
> ✅ **BUILT — [#555](https://github.com/timbermania/fft-monorepo/issues/555),
> [ADR-0167](0167-the-mount-inverts-to-the-host-and-the-fix-was-booked-into-the-bucket-it-drains.md)
> (extraction #3 pass 5).** `→ Debug` is **38**, this number exactly, and the
> `DebugOverlay` residue is **absent** rather than smaller. The mount went to a
> new Debug-side `src/debug/MapDebugPanels.gd` called from the six `assembler`
> scene roots that compose a map — not to self-registration, which has no
> trigger. Two things this paragraph could not contain: the new file was itself
> booked `Battlefield` by `("Map", "Battlefield")` — the **fifth** name-booking,
> and the first written *by* the fix, which made the severance first read as
> **growth**, `→ Debug` 42 → 47 (ADR-0167 dec. 5) — and the six call sites land
> in `assembler`, a bucket the cross-SYSTEM total excludes, so the win is
> **−10 scored / +6 unscored**, not −4 net (ADR-0167 dec. 6).

**6. `Tile.reserved_by: Unit` inverts to an opaque claim, and `BLUEPRINT.md` has
already decided how.** ADR-0157 dec. 5 recorded that the lattice **stores** the
combatant where the blueprint has occupancy crossing *out*. Measured at HEAD the
edge is small and one-sided: 4 lines in `src/map/Tile.gd` (`reserved_by: Unit`,
`is_blocked(exclude_unit: Unit)`, `try_reserve(unit: Unit)`, `release(unit: Unit)`),
and **`src/units/Unit.gd` is the only caller outside the system**, on 2.

`BLUEPRINT.md` → *Contested resources are capabilities, not flags* already names
this exact claim — *"the right to stand on a cell | one combatant | move, deploy,
removal"* — and already prescribes the shape: *"Holding the handle **is** the
authority"*, with *"a **derived, read-only** back-reference to its holder for
inspection."* Applying it severs the last 4 lines of `Battlefield` → `Battle`
typed reach and takes the outbound debt from **10 to 6**. Pass 3 does not
re-derive the design; it schedules it.

⚠️ **And the contested resource has a second holder the blueprint's table does not
name.** ADR-0126 check 5 asks how many spellings a contested resource has.
`reserved_by` is one, and `Tile.gd` says so — *"reserved_by is the ONLY occupation
tracking variable"*. It is not: `src/strategy/PlacementTileSet.gd` publishes
`get_tile_ownership(tile: Tile) -> TileOwnership` with a **`CONTESTED`** value,
read by `src/strategy/AIPlacementController.gd`. Two holders, two lifetimes —
runtime reservation and placement-phase ownership — and the second is in `Battle`,
keyed on `Battlefield`'s `Tile`. The inversion must carry both or it will move one
and leave the other. Recorded, not designed here.

> **AMENDED at loop pass 4 (2026-08-25, [#551](https://github.com/timbermania/fft-monorepo/issues/551)) — NOT BUILT. Sent back for design. Two of this decision's three premises are wrong, and both are wrong in the direction that makes it bigger.**
>
> dec. 4 and dec. 5 were built in this pass. This one is not, and the reason is
> evidence, not appetite.
>
> **(a) "`src/units/Unit.gd` is the only caller outside the system, on 2" — it is
> not.** Bucketed at HEAD, the reservation surface has **9 call sites across 6
> files**:
>
> | bucket | file | lines |
> |---|---|---:|
> | `Battle` | `src/units/Unit.gd` | 2 |
> | `Battle` | `src/debug/UnitControlPanel.gd` | **3** |
> | `assembler` | `src/scenes/EffectViewerScene.gd` | 1 |
> | `assembler` | `src/scenes/ProgressionTester.gd` | 1 |
> | test | `tests/GPUCallbackE005Test.gd`, `tests/GPUCallbackE065Test.gd` | 2 |
>
> `UnitControlPanel.gd` is `Battle` by the classifier's own `("Unit", "Battle")`
> fragment and calls `Tile.release(unit)` three times. The blast radius is **4.5×**
> the stated one.
>
> **(b) The contested resource has THREE holders, not two — and the third is
> invisible to every instrument that sized this decision.**
>
> | # | holder | owner | reach |
> |---|---|---|---|
> | 1 | `Tile.reserved_by: Unit` | `Battlefield` | 4 typed lines, 9 call sites / 6 files |
> | 2 | `PlacementTileSet.get_tile_ownership() -> TileOwnership` | `Battle` | **1** reader |
> | 3 | **`PlacementTileSet.claimed_tiles: Dictionary  # Tile -> Unit`** | `Battle` | **7 lines / 5 files** |
>
> 🔴 **Holder 3 is a bare `Dictionary` keyed on `Battlefield`'s `Tile` holding
> `Battle`'s `Unit`.** An untyped reach carries no type name, so `touch_matrix.py`
> — which states it is a **FLOOR** for exactly this reason (ADR-0131 dec. 6) —
> **cannot see it at all**, and neither can the `−4 outbound / debt 10 → 6`
> prediction. It is read by `PlacementTileHighlighter` (3),
> `StrategyPhaseManager` (2), `GPUArena` (1) and `CursorConfirmEndToEndTest` (1).
> The widest holder of the occupancy concept is the one the measurement omits.
>
> This is #551's shape for the **third** time in one pass: after *the split whose
> duplication no instrument scores* (dec. 4) and *the misbooking that hid a
> violation of its own justifying rule* (dec. 5), here **the instrument that
> sized the inversion is structurally blind to its largest term.**
>
> ⚠️ Holder 2's enum is narrower than it looks: `PLAYER_ONLY` and `ENEMY_ONLY`
> are **produced and never consumed** — the sole reader,
> `AIPlacementController.gd:39`, tests `== CONTESTED`. Three-valued in
> declaration, one predicate in use. That makes holder 2 the *easy* one to carry,
> which is worth knowing before the design starts.
>
> ⚠️ `src/map/Tile.gd:68` states *"reserved_by is the ONLY occupation tracking
> variable"*. It is wrong three ways, and it is the sentence pass 1 and pass 3
> both read.
>
> **What pass 4 hands forward.** `BLUEPRINT.md`'s prescription — *"holding the
> handle **is** the authority"*, plus a derived read-only back-reference — is
> still the right shape and is **not** disturbed by any of the above. What is
> disturbed is the claim that pass 3 *"does not re-derive the design; it
> schedules it."* There is no design yet for a capability that spans three
> holders across two systems, one of them untyped. **dec. 6 needs a design pass
> before a build pass**, and the `−4 outbound / debt → 6` row should be read as
> **unearned until then** — the 4 typed lines are real and would go, but the
> concept would not be inverted, only one of its three spellings.

> **RESOLVED at loop pass 5 (2026-08-25, [#554](https://github.com/timbermania/fft-monorepo/issues/554)) by
> [ADR-0166](0166-occupancy-is-battles-in-five-spellings-and-battlefields-sixth-is-inert.md) —
> by DELETION, not by the inversion this decision prescribes. The `−4 outbound / debt 10 → 6`
> row is earned, and it is earned for a different reason than the one written here.**
>
> The design pass the amendment above asked for found **six** spellings of the occupancy
> concept, not three. **Five are `Battle`'s** — holders 2 and 3 above, plus
> `MovementComponent.current_logical_tile` / `Unit.get_current_tile()` (**56 lines / 24 files,
> 3 of them typed**), the GPU mover's `is_tile_occupied()` (15 call sites / 3 shaders), and
> `GPUArena._unit_at_grid()`. The census that produced the three followed the `Tile` **type
> name**; four of the six carry none.
>
> 🔴 **And the one it found in `Battlefield` is inert.** `reserved_by` is written once by
> `Unit.place_on_tile` and **never released or updated in gameplay** —
> `GPUVisualBridge.gd:110` moves a unit by writing `current_logical_tile` and never touches it,
> so it points at the deploy tile for the rest of the battle. `is_blocked` has **zero** external
> callers, `became_available` has **zero** listeners, and `reserved_by` is read outside
> `Tile.gd` on exactly one line — `Unit.gd:1649`, inside a `push_error` format string. Its one
> guard runs *after* `place_on_tile` has already assigned `global_position`, and **every
> production caller ignores the `false`**. `ScenarioVM.cinematic_place` already routes around it
> by name.
>
> So there was no capability to design: dec. 6's four lines are deleted, and nothing replaces
> them. ADR-0166 dec. 2 also rejects **by name** the move that would have turned this row green
> without changing anything — retyping `reserved_by` to `Node` or an int id, which every
> instrument on this map would have scored as the fix.

**7. The system does not split at `src/map/`, and the code already argues it more
strongly than the blueprint does.** `BLUEPRINT.md` → *Inside Battlefield* names
two **agreement** crossings that *"fail silently, which is why they may not span a
boundary"* — the standing surface (`Lattice` → `Environment`) and the projection
(`Camera` → `Cursor`). Those forbid splitting `Lattice`/`Environment` and
`Camera`/`Cursor`; they say nothing about `{Lattice, Environment}` against
`{Camera, Cursor}`, which is what a split at `src/map/` would be.

Measured, that split is forbidden too, and by a cycle the code goes out of its way
to hide. `src/scenes/TileCursor.gd` holds `var _player_camera` — **untyped, with
the reason in the comment: *"untyped to dodge cyclic class-name preloads"*** — and
finds it **three ways**: an `@export_node_path` (`player_camera_path`), a group
fallback (`get_first_node_in_group("player_camera")`), and, for the view
transform, `get_viewport().get_camera_3d()`, which is a **different object**.
`src/scenes/PlayerCamera.gd` pushes back through `follow_cursor()`, driven by
`TileCursor.cursor_moved`, and documents the cursor as *"authoritative when it
exists"*. **`touch_matrix.py` sees none of it** — an untyped var, a NodePath, a
group name and a signal carry no type name, which is ADR-0131 dec. 6's stated
blind spot arriving inside the system rather than across it. A cycle held together
by four untyped bindings, one of them a deliberate dodge of the type system, is
not a boundary. **One addon.**

**8. `PlayerCamera.gd`'s 821 lines are not a seam decision, and saying so is the
decision.** It is the system's largest file and it has **zero inbound lines from
any system** — its only inbound is 8 lines from the assembler, and its only
outbound is `Tune` 16, `GameLogger` 6, `DebugConfig` 1. Nothing crosses a
boundary. Splitting it changes no published surface, no crossing and no metric
term, so pass 3 has no reading that bears on it and neither `/codebase-design`
nor a prediction table would be answering a question the seam asked.

It is real work and it is internal work. It belongs to pass 6, it is **blocked
behind dec. 3**, and the reason is specific rather than procedural: the file's
largest external surface is 16 `Tune` binds, and how a file should be cut depends
on whether that surface is a shipped dependency or an injected handle. Cutting it
first means cutting it twice.

**9. Three of `BLUEPRINT.md`'s sentences about this system were tested. One
passes, one fails, and the failing one is the fifth.** ADR-0126 check 2 is *test
the blueprint's claim, do not inherit it*, and it survives ADR-0157 having read it
early: dec. 5 there tested the **§1 crossing table**; these are the *Inside
Battlefield* sentences, which no pass has touched.

| sentence | pile | verdict |
|---|---|---|
| *"The cursor is not the selection… conflating them is how targeting rules end up living in a cursor."* | behaviour | **PASSES.** `TileCursor` holds no targeting, legality or range rule. Its `RANGETILE` / `range_tex` symbols are the CLUT sheet's ROM name, which is art, not range. It publishes `cursor_moved` / `cursor_confirmed` / `cursor_inspected`, all carrying a `Tile` — a pointer event, not a commitment. **The first blueprint behaviour sentence this loop has tested and confirmed.** |
| *"The ambient condition is authoritative… 'It is raining' is a fact outcomes may read, so it lives on the `Lattice`."* | behaviour | **FAILS.** `src/map/Tile.gd` and `src/map/TerrainIndex.gd` contain **no** weather, rain or ambient field. The condition lives in `Cutscene` (`src/scenarios/ScenarioWeather.gd`) and enters `Battlefield` only as `weather_raw`, an **argument** to the static `MapStateSelector.select(states, weather_raw, is_night, arrangement)`. It is stored nowhere on the lattice, so no outcome can read it from there. |
| *"a traversal profile"* crosses **in** | behaviour | **still ZERO**, as ADR-0157 dec. 5 recorded — and now with its mechanism. `src/scenarios/EventPathfinder.gd` is terrain-only *by design*: its header cites gate `0x8017505c` and records that the ROM's `a0 = 3` build **skips the entire unit-occupancy phase**. The absent crossing is ROM-faithful, not missing. |

**This is the fifth blueprint sentence to fail on first contact**, after
`Effects`' combatant-ignorance sentence (ADR-0126 / ADR-0127), the `Audio` half of
`Effects`' subscription sentence (ADR-0153), and §1's occupancy direction
(ADR-0157 dec. 5). **Recorded, not rewritten**, on the `BLUEPRINT-AUDIT.md`
precedent — the note goes in `BLUEPRINT.md` → *Inside Battlefield* so nobody cites
the sentence while the fix is pending.

⚠️ **And the condition is an unnamed unit** — ADR-0126 check 4. `MapStateSelector`'s
docstring says selection is by raw int *"NEVER by label"* because *"the scenario
weather enum (0 None, 1 Normal, 2 Strong…) and the GNS weather enum (0 None, 1
NoneAlt, 2 Normal…) are offset"* (ADR-0056). **Two integer enums, the same English
word, values that disagree by one.** If `Environment` renders the fact the
`Lattice` is supposed to hold, it currently renders it from a different enum than
`Battlefield` keys on. The seam must publish `weather_raw` as a named type, not
an `int`.

**10. Check 3's muxed slot is `reserved_by` and the code declares it; check 6's
live set is `arrangement` and the code already agrees.**

Check 3 — the muxed storage slot. `Tile.gd` states it outright: *"It represents
both reservation AND current occupation."* One field, two meanings, one lifetime.
The demux **above** already exists and is dec. 6's second holder,
`PlacementTileSet.TileOwnership`; the demux **below** is partial —
`try_reserve()` returns a `Dictionary` carrying `blocked_by_friendly`, which is a
third meaning leaving through the return value rather than the field. The
inversion in dec. 6 is the demux, and it must produce **two** names, not one
opaque one.

Check 6 — the live set. `MapStateSelector.select` takes three keys and treats
them differently: `arrangement` is a **hard gate** (`push_error` and refuse —
*"refusing to substitute a wrong-arrangement sky"*), while `weather_raw`/`night`
fall back to the map-init default *"like the ROM"*. That is exactly
[#365](https://github.com/timbermania/fft-monorepo/issues/365)'s measurement —
geometry rides arrangement, 148 of 148, never time or weather — already encoded.
And `Tile` nodes are **sparse**, built one per `terrain.json` entry by
`DynamicTerrainBuilder._create_tile`, with `TerrainIndex.get_tile` returning null
for holes: no preallocated grid, so no dead slots to net out. **Both checks pass,
and they are recorded because a passing check is the thing this loop keeps not
writing down.**

⚠️ One check-4 residue, not a bug and not to be fixed silently: `Tile` publishes
**two** coordinate accessors that derive differently. `grid_x`/`grid_z` are the
authored grid coordinates, set by `DynamicTerrainBuilder`; `get_grid_coords()`
returns `Vector2i(int(global_position.x), int(global_position.z))`, which is
**world space cast to int** and agrees only while one tile is one world unit at
the origin. It has exactly one caller — line 249 of `Tile.gd` itself, formatting
a `release()` mismatch message. It is dead surface with a divergent unit; the seam
should not publish it.

**11. The published interface is two names and two *clients*, which is not what
dec. 3 said.** ADR-0157 dec. 3 reads the inbound as *"`Battle` → `Tile` 72 +
`TerrainIndex` 20 = 92 lines (70%), over 17 files"*, one system, one surface. Split by
consumer it is two:

| consumer | `Tile` | `TerrainIndex` | wants |
|---|---:|---:|---|
| `src/strategy/` — the placement phase | 58 | 10 | **`Tile` objects**, per cell: highlight them, set ownership, read one |
| `src/gpu/` — the simulator | 6 | 10 | **`TerrainIndex`**: bulk queries, distance fields |

**81% of the `Tile` lines are placement, not simulation.** The two want opposite
shapes — per-object mutation against bulk read — and the blueprint books
`Deployment` under `Battle`, so the heavier client is the phase that runs *before*
the battle. A single interface serving both is why `Tile` is a `StaticBody3D` with
a highlight mesh **and** the authoritative occupancy record. Pass 4 should publish
them as two, and pass 9 should score them separately. Recorded here because dec.
3's 92% is true and hides it.

## Prediction

Scored at pass 9 with `classify_blueprint.py`, `touch_matrix.py`,
`autoload_reach.py`, `path_refs.py` and `score_goals.py`. **`--delta` against
`8360`.** Decisions 4, 5 and 6 are what pass 4 builds; dec. 3's inversion is a
precondition and is scored as `platform`'s, not this system's.

| term | now (`6a25e54f7`) | predicted | from |
|---|---:|---:|---|
| files | 49 | **44** | −5 debug panels (dec. 5) |
| lines | 8,360 | **7,923** | −395 panels, −42 glove half (dec. 4) |
| inbound, cross-system | 131 | **100** | −31 `CursorBob` glove (dec. 4) |
| inbound symbols | 9 | **7** | `CursorBob` and its path form leave |
| `Tile` + `TerrainIndex` share | 70% | **92%** | same 92 lines, smaller denominator |
| outbound, cross-system | 11 | **7** | −4 `Tile` → `Unit` (dec. 6) |
| outbound **debt** | 10 | **6** | `Effects` 4, `Audio` 1, `PlayerCamera.tscn` → `CombatUI.tscn` 1 |
| debt ÷ size | 0.120% | **0.076%** | vs `Sprite Rig`'s 0.121% |
| → `Debug` | 82 | **40** | −42 (dec. 5); the residue is `DebugConfig` 32 + `GameLogger` 6 + `DebugOverlay` 2 |
| → `platform` | 74 | **67** | −7 `Tune` in two panels; `Tune` 59 + `#include` 8 |
| → `schema` | 23 | 23 | a declared addon dependency, not debt |
| `platform` → systems | **15** (0 as scored) | **0** | dec. 3's precondition |
| inbound path references | 262 | **258** | −4 `Tune.register_all()` (dec. 3) |

**Two predictions are falsifiable in the direction that would hurt**, and pass 9
should look for them rather than confirm the table:

- **The `Debug` residue may not fall to 40.** Dec. 1 measured that severing a
  `DebugConfig` gate *creates* a `Tune` bind. The 32 remaining `DebugConfig` lines
  are in `src/map/` and `PlayerCamera.gd`, i.e. in the core, and if pass 4 severs
  any of them the `platform` row rises while the `Debug` row falls. **Score the
  two together or the win is bookkeeping.**
- **`CursorBob`'s knife half may not be worth keeping.** It is ~60 lines with one
  caller inside the system. If pass 4 finds `TileCursor` is its only conceivable
  caller, the right move is to inline it and delete the `class_name`, which would
  take inbound symbols to 6 rather than 7. The prediction above assumes the file
  survives; **the more useful outcome is the one that falsifies it.**

## Consequences

**Extraction #3 acquires a blocking dependency it did not have this morning, and
it is on another bucket.** `Battlefield` cannot reach goal #5 while `platform`
enumerates it. That is a worse schedule than pass 2 handed over and a better one
than the alternative, which was discovering it during pass 6 with 44 files already
moved.

**The `ship or inject` question is closed for the third time and answered for the
first.** Extractions #1, #2 and #3 all deferred it. It stayed open because it was
asked about the wrong direction of the edge: every framing since ADR-0139 dec. 12
has been about what the **addon** is allowed to name, and the blocker is what
**`platform`** names. Whichever pass builds `addons/exmateria_platform/` inherits
one question — *how does a tunable owner register without a central list?* — and
that question has answers.

**Three instruments disagree about the same set and none of them is wrong.**
`touch_matrix.py` cannot report a `platform` row because `platform` is not a
system; `outbound_reaches` cannot see a non-literal path; `path_refs.py` sees four
of six and cannot see a `/root/` reach at all. ADR-0147 / ADR-0148's *"when two registers describe the same set,
diff them"* is the standing rule and this is its clearest instance yet — and it is
worth noting that `score_goals.py`'s own docstring records this principle being
mis-attributed to ADR-0146 once already: **the diff is the finding, and the fix is not a new scanner but a
declared subject.** Concretely — `outbound_reaches` should adopt `path_refs.py`'s
definition of a path reference, and `check_addon_portability.py` should accept a
non-system `--system` so the bucket most in question stops being the one bucket it
declines to discuss. Neither is written here; both are #4's pass-1 input.

**Four of the five inherited items resolved by severance rather than by
placement**, and the fifth resolved by being sent back. `CursorBob` splits, five
panels leave under a rule that already existed, `reserved_by` inverts to a design
`BLUEPRINT.md` already wrote, and `PlayerCamera.gd` is internal. Only item 1
needed a new argument. **Pass 4's brief is smaller than pass 2 predicted and its
precondition is larger**, which is what an audit is for.

**A blueprint behaviour sentence finally passed one.** *"The cursor is not the
selection"* is the first of these tested and confirmed, against four failures.
Sorting the sentences into two piles before inheriting them (ADR-0126 check 2, as
`refactor-loop.md` states it) is now four-for-five at finding a false one **and**
one-for-one at confirming a true one, which is the second thing a check has to do
to be worth running.

## Alternatives considered

**Inject `Tune` as a handle and ship nothing.** Rejected in dec. 3 — it cannot
address a `#include`, and against `register_all()` it hides the coupling rather
than severing it, in a shape whose failure mode is a silent skip.

**Ship `platform` as-is and accept a red goal #5.** Rejected. It would put the
only bucket that names seven systems inside an addon root, where arm 1 scores it
zero — an addon that is portable **because the guard cannot see why it is not**.
That is the ADR-0148 defect this project has named three times.

**Rebook all seven `src/debug/` files, not five.** Rejected in dec. 5.
`MapGridOverlay.gd` and `DeadzoneBoxOverlay.gd` draw the lattice and the camera
deadzone; they are scene-tree overlays, not registry views, and `Cutscene` names
`MapGridOverlay` on 2 lines. Rebooking them to hit a number is the exclusion-rule
mistake [#424](https://github.com/timbermania/fft-monorepo/issues/424) already
paid for.

**Move `CursorBob` whole to `platform` or to `UI`.** Rejected in dec. 4. To
`platform` adds a fifth file to the bucket dec. 3 has just found cannot ship; to
`UI` leaves `Battlefield` reaching `UI` for the knife half, converting 31 lines of
inbound into a new line of outbound debt in the one column this extraction is
chosen on.

**Split the system at `src/map/`.** Rejected in dec. 7, on the measured
`PlayerCamera` ↔ `TileCursor` cycle rather than on the blueprint's say-so.

**Defer item 1 a fourth time.** Rejected. Three deferrals produced no new
information because each restated the same question; this pass changed the
question by measuring the other direction, and a fourth deferral of a question
that has now been answered would be a different mistake.
