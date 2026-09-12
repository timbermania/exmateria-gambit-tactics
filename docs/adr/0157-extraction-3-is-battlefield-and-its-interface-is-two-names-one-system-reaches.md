# Extraction #3 is `Battlefield`, and its interface is two names one system reaches

Extraction order is chosen by measured isolation
([ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md) dec. 2),
and on that method **`Battlefield` wins two of the three readings outright and
loses only on size**. Its outbound reach into systems that have not
extracted is **9 lines against 8,247**, and **70% of its inbound is two symbols
reached by a single system**. It is the nearest thing left to `Render`'s
shape, and it is also the first extraction that is not small.

Status: accepted (2026-08-23). Loop **pass 1** of extraction #3, ratifying
[#492](https://github.com/timbermania/fft-monorepo/issues/492). Amends
`docs/agents/refactor-loop.md` → *Extraction order*. Applies ADR-0141 dec. 2's
method a **second** time and reads
[ADR-0126](0126-every-system-pass-audits-before-it-designs.md) check 2 early, as
a selection input rather than as pass 3.

Code and classifier at `126dfec9b`. **Amended 2026-08-24 by loop pass 2** —
see *Soft spots* below, which is where this line's *second* was a *third* until
C1, and which records what dec. 1 rests on. Measured at trunk `778183181`.

## Context

Extraction #1 is `Render` (ADR-0141 / 0147 / 0148, merged). Extraction #2 is
`Audio` (ADR-0153, PR #445 → `import-godot-game`, trunk `c312a3fd1`). Pass 1 is a
query, and its method is fixed: three readings off `classify_blueprint.py` and
`touch_matrix.py` — **size**, **inbound concentration read by distinct symbol**,
and **outbound reach into other systems**, with `platform`, `schema` and `Debug`
excluded from the outbound count.

⚠️ **The unit is the LINE, not the file-edge** (ADR-0131 dec. 5). These numbers do
not compare term-for-term with ADR-0141 dec. 3's table, which is part file-edge.
Compare shapes, not magnitudes.

### The reading — trunk `126dfec9b`

| system | files | lines | IN | OUT | in-symbols | top inbound symbol | OUT ÷ size |
|---|---:|---:|---:|---:|---:|---|---:|
| `Effects` | 191 | 57,955 | 29 | 6 | 11 | `PSXCameraConvert` 9 | 0.01% |
| `UI` | 126 | 38,416 | 4 | 184 | 2 | `UI3RegistryView` 2 | 0.48% |
| `Battle` | 79 | 23,117 | 201 | 207 | 16 | `UnitProgression` 41 | 0.90% |
| `Cutscene` | 57 | 16,185 | 16 | 67 | 5 | `ScenarioDebugSession` 8 | 0.41% |
| **`Battlefield`** | **49** | **8,247** | **131** | **11** | **9** | **`Tile` 72 (55%)** | **0.13%** |
| `Sprite Rig` | 26 | 4,957 | 118 | 6 | 20 | `DisplayActivity` 41 | 0.12% |
| `Debug` | 15 | 2,993 | — | 2 | — | — | 0.07% |
| `Character Catalogue` | 14 | 2,138 | 21 | 47 | 6 | `CharacterCatalog` 7 | 2.20% |
| ~~`Audio`~~ *(extracted #2)* | 12 | 1,430 | 22 | 3 | 4 | `SfxRouter` 16 | 0.21% |
| `Campaign` | 7 | 1,180 | 10 | 47 | 3 | `ScenarioDirector` 5 | 3.98% |
| ~~`Render`~~ *(extracted #1)* | 5 | 684 | 28 | 0 | 2 | `PSXDisplay` 26 | 0.00% |

Cross-system total **1,104 lines**. **This is a FLOOR** (ADR-0131 dec. 6) —
duck-typed reaches carry no type name and are invisible to it.

#492's table read `Battlefield` at 8,393 in 50 files. ADR-0156 dec. 4 moved
`src/debug/WorldMapDebugPanel.gd` (146 lines) off the `("Map", "Battlefield")`
name fragment that had booked it there, and the row returns to its frozen
**8,247**: `check_baseline.py --delta` reads **`Battlefield 8247 +0`** at
`126dfec9b`. Nothing else in the table moved.

## Decision

**1. Extraction #3 is `Battlefield`.** It is chosen on outbound isolation and
inbound concentration, over `Campaign` and `Character Catalogue`, which are
smaller and reach further.

The ranking among the three readings is not neutral and this ADR states it.
**Outbound is the reading that decides**, because outbound is the only one an
extraction is obliged to *sever*: an addon cannot name a host class, so every
outbound line is a design problem that must be solved before the move.
**Inbound is not severed, it is published** — the host goes on reaching in, and
inbound concentration measures how wide the resulting API is. **Size is neither**;
it is the volume of code that relocates, a mechanical cost that scales the work
without changing its shape. ADR-0141 ranked them the same way when it rejected
size-alone ordering — *"Size and entanglement disagree, and entanglement is what
an extraction pays."*

**2. `Battlefield`'s outbound is 11 lines, and only 9 of them are debt.** The
complete list, by file:

| → | lines | site |
|---|---:|---|
| `Battle` | 4 | `src/map/Tile.gd` → `Unit` (67, 198, 210, 231) |
| `Effects` | 2 | `src/effects/TileOverlayCompositor.gd` → `TileOverlayColor` |
| `Effects` | 1 | `src/map/DynamicGeometryBuilder.gd` → `MapTintOverlay` |
| `Effects` | 1 | `src/map/MapComposer.gd` → `ScreenEffectOverlay` |
| `Audio` | 1 | `src/scenes/TileCursor.gd` → `SfxRouter` |
| ~~`Render`~~ | 2 | `src/scenes/TileCursor.gd` → `PSXDisplay` |

`PSXDisplay` is an autoload of `res://addons/exmateria_render/display_port/PSXDisplay.gd`
— extraction #1's published port. Reaching it is **the shape extraction produces**,
not debt it leaves, so the two lines are excluded from the 9. `SfxRouter` is
**not** the same case: extraction #2 moved 17,958 lines into the canonical
`exmateria-sound` package, and `SfxRouter` is one of the 1,430 lines of host-side
`Audio` that stayed, at `res://src/audio/SfxRouter.gd`. That line is debt.

⚠️ **#492's body said `Battlefield`'s outbound ratio is *"the lowest ratio of any
unextracted system"*, and on the raw column it is not.** `Sprite Rig` reads
6 ÷ 4,957 = **0.12%** against `Battlefield`'s 11 ÷ 8,247 = **0.13%**. The claim
survives only on the debt figure — 9 ÷ 8,247 = **0.109%** against `Sprite Rig`'s
0.121%, all six of whose lines reach `Battle` and are debt in full — and that is
a two-thousandths-of-a-percent margin, not an argument. **`Battlefield` is not
chosen on this margin.** It is chosen because dec. 3's inbound reading is
decisive and `Sprite Rig`'s is disqualifying (dec. 9).

**3. The published interface is `Tile` and `TerrainIndex`, and one system reaches
both.** The 131 inbound lines are **two clusters, not nine symbols spread thin**:

- **`Battle` → `Tile` 72 + `TerrainIndex` 20 = 92 lines (70%)**, over 17 files,
  15 of them in `src/strategy/` and `src/gpu/`. `Battle`'s entire row in the
  matrix is 92 — every line `Battle` reaches into `Battlefield` lands on one of
  these two names.
- **`UI` → `CursorBob` 31 + `TileCursor` 3 = 34 lines (26%)** — see dec. 4.
- The remaining 5: `Cutscene` → `MapGridOverlay` 2, `MapConstants` 1,
  `EventPathfinder` 1; `Effects` → a path preload of
  `src/core/MapIlluminationDDA.gd` 1.

ADR-0141 dec. 3 chose `Render` because *"The system is one published name,
`PSXDisplay`, over a compositor nobody outside it touches."* This is that
sentence with a two rather than a one. `src/map/` holds 18 files and **three of
them are named from outside** — `Tile.gd`, `TerrainIndex.gd`, and
`MapConstants.gd` on a single `Cutscene` line. The other **fifteen**, including
all four of the largest geometry builders (`SkirtGeometryGenerator` 786,
`MapComposer` 721, `DynamicGeometryBuilder` 623, `MapTextureAnimator` 351), are
named by **nothing across a system boundary**. The assembler is the exception
that proves it: see dec. 6.

**4. `CursorBob` is not `Battlefield`'s, and pass 3 moves it.** It is booked
`Battlefield` by an exact rule, not by a name fragment — so this is a real
misplacement, not another `DEBUG_OWNER` accident. `src/scenes/CursorBob.gd`'s own docstring says
what it is — *"Pure phase machine for the ROM-faithful cursor bob"* — and names
the second consumer in the next paragraph: *"The glove cursor (WORLD.BIN,
threshold-pair encoding) is parsed into the same JSON."* It is one `RefCounted`
reading **two** step tables from `assets/sprites/cursor_bob.json`: `tile_knife`, which `src/scenes/TileCursor.gd`
uses on 2 lines, and `glove_*`, which six `src/ui3/detail/` menus use on 31.

**All 31 of `Battlefield`'s `CursorBob` inbound lines are the glove half.** The
correct reading of the system's published surface therefore excludes it:
**IN 100 over 7 symbols, of which `Tile` + `TerrainIndex` is 92 — 92%, from one
system.** That is a better number than the headline, and it is the one pass 3
should design against.

Where `CursorBob` goes is a pass-3 seam decision this ADR does not take. It is
pure, static, holds no state, and reads one JSON asset — the shape of `platform`
or `content`, not of either system that calls it.

**5. Three of `BLUEPRINT.md` §1's six named crossings are ZERO, a fourth runs
backwards, and `Camera` is silent to the instrument.** ADR-0126 check 2 is *"Test the blueprint's claim about this
system; do not inherit it."* #492 pulled it forward into pass 1 as a selection
input. Of the six crossings `BLUEPRINT.md` names for `Battlefield`:

| named crossing | direction | measured |
|---|---|---|
| reachability, targetability and occupancy answers | out | **present** — `Tile` 72 |
| the standing surface | out | **present** — `TerrainIndex` 20 |
| the cell under the pointer | out | **present** — `TileCursor` 3 + assembler 1 |
| the camera quadrant | out | **ZERO** |
| a traversal profile | in | **ZERO** |
| camera claims | in | **ZERO** |

**Three of six do not exist as typed reaches**, and the whole `Camera` part —
`src/scenes/PlayerCamera.gd`, 788 lines, the system's largest file — has **no
cross-system typed edge in either direction**. Its only outbound is `Tune`, the
`platform` port.

Worse than absent: the one outbound edge that does exist runs **against** the
table. `Tile.gd` carries `reserved_by: Unit`, commented *"reserved_by is the ONLY
occupation tracking variable"*, plus `is_blocked(exclude_unit: Unit)`,
`try_reserve(unit: Unit)` and `release(unit: Unit)`. The blueprint has occupancy
crossing **out** — `Battlefield` *answers* it from a profile handed in. Measured,
the lattice **stores the combatant** and owns the reservation protocol, and the
profile the table says comes in does not. This is the **fourth** blueprint
sentence to fail on first contact, after `Effects`' combatant-ignorance sentence
(ADR-0126 / ADR-0127) and the `Audio` half of `Effects`' subscription sentence,
whose note in BLUEPRINT reads *"FALSIFIED for `Audio`, and UNTESTED for `Camera`
and `Body`"* (ADR-0153, extraction #2 pass 3).

ADR-0126 check 2 requires that such a failure be recorded rather than quietly
rewritten, on the `BLUEPRINT-AUDIT.md` precedent, so nobody cites the sentence
while the fix is pending. It is **recorded, not rewritten** — the note is in
`BLUEPRINT.md` §1.

**6. The move cost the cross-system matrix does not show is 49 files across seven
directories and 21 `res://` path references.** This is the reading on which
`Battlefield` is genuinely harder than either predecessor, and it is invisible in
the table above because the matrix counts **cross-system** lines and most of this
is `assembler` → `Battlefield`.

| directory | files | lines |
|---|---:|---:|
| `src/map/` | 18 | 4,511 |
| `src/scenes/` | 4 | 1,668 |
| `assets/shaders/` | 16 | 925 |
| `src/debug/` | 7 | 564 |
| `src/effects/` | 2 | 303 |
| `src/scenarios/` | 1 | 147 |
| `src/core/` | 1 | 129 |

Only `src/map/` is claimed by a directory rule; the other 33 files are named one
at a time in `classify_blueprint.RULES`. `assembler` adds **22 inbound lines** on
top of the 131 (`TileCursor`, `CursorController`, `MapComposer`), and there are
**21 `res://` path references** to `Battlefield` files from `.tscn`, `.gd` and
`.tres` — `src/map/MapComposer.gd` alone is mounted or preloaded by path in
**nine** places, eight of them scenes. Two scenes are the system's own
(`assets/scenes/PlayerCamera.tscn`, `assets/scenes/TileCursor.tscn`). A path
reference does not survive a move and does not appear in the 131.

`Render` moved 6 files; `Audio` moved 12 host files into a package. This moves 49
across seven directories, and pass 4 should budget for the paths before the
types.

**7. `Campaign` is rejected — it is the spine reaching the simulator.** 1,180
lines, the smallest unextracted system, and the most concentrated inbound in the
table: **10 lines, 3 symbols, all from `Cutscene`** (`ScenarioDirector` 5,
`ForcedDirectorState` 3, `ScenarioDirectorState` 2). Its cost is entirely
outbound: **47 lines out, 36 of them into `Battle`** — **3.98% of its own size,
the worst ratio in the table**, thirty times `Battlefield`'s. Extracting it means
severing thirty-six lines of spine-to-simulator reach first, which is a design
problem the size of the system itself.

**8. `Character Catalogue` is rejected — the objection ADR-0141 raised is still
unsettled.** ADR-0141 closed its `Character Catalogue`
alternative with *"Strong candidate for #3."* — and stated the objection in the
same paragraph: *"a store reaching the simulator is backwards, and settling that
is a boundary question the pass would have to answer before it could start."*
That question is still unanswered.

Measured now, the reach is **44 of its 47 outbound lines into `Battle`**, 2.20%
of its size — seventeen times `Battlefield`'s ratio. ⚠️ This does **not** show
growth against ADR-0141's *"reaches into `Battle` 11 times"*: that figure is
file-edges and this one is lines (ADR-0131 dec. 5). What is comparable is the
shape, and the shape is unchanged. Its inbound is also the more diffuse of the
two — 21 lines over 6 symbols with no symbol past 7, where `Battlefield` has 92
over 2. Settling the boundary is a grilling, not a measurement, which is why it
does not belong inside a pass. It stays the strongest candidate for #4.

**9. `Sprite Rig` and `Effects` are recorded, not scheduled.** `Sprite Rig` has
the lowest absolute outbound of any sizeable system — 6 lines, all into `Battle`
— and ADR-0141 dec. 2's own gloss disqualifies it: *"One symbol is a port; twelve
is a surface with no interface."* Its inbound is **118 lines over twenty distinct
symbols**. Twenty is worse than twelve. `Effects` is startlingly isolated for 30%
of the host — IN 29, OUT 6 — and is scheduled **last** by
`docs/agents/refactor-loop.md` → *Extraction order*, because wayfinder map #262
is live on that tree. Neither reading is forgotten; both are deferred for a
stated reason.

**10. Extraction #3 does not inherit a red baseline.** #492 asked that this be
decided deliberately rather than by default. It is now moot in the good
direction: `refactor/416-new-code-is-content` landed as PR #497 (trunk
`126dfec9b`), ADR-0156 booked `src/world_map/`'s nine files `content`, and the
three guards #444 named pass at trunk's own tip —
`check_no_env_vars.py`, `check_root_set.py`, and `check_blueprint_walk.py`
(*"644 source files walked (102 shaders), 0 unclassified"*). #444 is closed.
Extraction #3's pass 9 measures against a green baseline; extraction #2's did
not. The full sweep at `126dfec9b` is **32 of 33 guards passing**, the one
failure being `check_addon_sync.py`'s missing gitignored deployment copy (#414),
which is a worktree artifact in every fresh checkout.

**11. The `Campaign` / world-map collision does not arise.** #492's first open
item was that `src/world_map/WorldMapProgress.gd`'s docstring says *"When Campaign
lands, this class and its backing move together and the callers do not change"* —
so choosing `Campaign` for #3 would land extraction #3 and the live world-map
build on the same files. Selecting `Battlefield` defers that. It is **not resolved** — the port list's
crossing C3 still points `WorldMapProgress.gd` and `WorldMapVariables.gd` at
`Campaign`, and both are booked `content` today under ADR-0156 dec. 1. It becomes
live again the moment `Campaign` is scheduled, and #4's pass 1 inherits it.

## Considered alternatives

**`Character Catalogue`, on ADR-0141's own recommendation.** Rejected on the
measurement in dec. 8: 44 of 47 outbound lines into `Battle`, 2.20% of its size,
and inbound spread over six symbols. ADR-0141 recommended it *and* named the
objection; two extractions later the objection is exactly where it was left.

**`Campaign`, on smallest-first.** Rejected in dec. 7. Smallest-first optimises
the reading that costs least to be wrong about. Its 3.98% outbound ratio is the
worst in the table.

**`Sprite Rig`, on lowest absolute outbound (6 lines).** Rejected in dec. 9 by
ADR-0141 dec. 2's gloss: twenty distinct inbound symbols is a surface with no
interface. Its outbound — 6 lines, 0.12% — is genuinely the best number of any
unextracted system, better than `Battlefield`'s raw 0.13%, and dec. 2 records
that rather than hiding it. But a twenty-name API is not an API.

**Defer #3 until the `Tile.reserved_by: Unit` inversion is designed away.**
Rejected: that is pass 3's work and it is four lines. Deferring a selection until
its seam is designed inverts the loop — pass 1 selects, pass 3 designs — and the
`Character Catalogue` case in dec. 8 is the one where that is genuinely owed,
because there the reach is 44 lines and it is the whole objection.

**Split `Battlefield` and extract only `src/map/`.** Rejected for pass 1. It is a
real option and it is pass 3's to take: 18 files / 4,511 lines carrying `Tile`
and `TerrainIndex`, which is 92 of the 100 non-glove inbound lines. Naming the
split here would decide the seam before the audit that ADR-0126 requires before
designing one.

## Soft spots

> **Added 2026-08-24**, loop **pass 2** of extraction #3
> ([#500](https://github.com/timbermania/fft-monorepo/issues/500)), from the two
> spikes agreed at the end of pass 1. Measured at trunk `778183181`.
>
> ADR-0156, written a day earlier, recorded two soft spots against itself. This
> ADR recorded none, and dec. 1 is load-bearing enough that the omission was
> itself the finding. **The selection stands** — S1's last paragraph says why
> nothing here moves it. What follows is what it rests on and did not state,
> two sentences in it that are wrong, and what Spike A returned.

**S1. Dec. 1's ranking is new here, it is an argument rather than a measurement,
and the plain reading of it is contradicted by dec. 8 and dec. 9 of this same
ADR.**

Dec. 1 ranks the three readings — outbound decides, inbound is published rather
than severed, size is neither — and hands the ranking to
[ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md).
That attribution is half right. ADR-0141 dec. 2 lists the same three readings and
**does not rank them**. It ranks *within* inbound — *"Read inbound by symbol,
never by system count"* — and its
*"Size and entanglement disagree, and entanglement is what an extraction pays"*
separates **size** from **entanglement**, which is the size half of dec. 1 and
nothing more. **The inbound-versus-outbound half is this ADR's own assertion,
first stated here, and it should have been marked as new.**

**And this ADR does not follow it.** Dec. 9 rejects `Sprite Rig`, whose outbound
is the best number in the table — 6 lines, 0.12%, better than this system's raw
0.13%, and dec. 2 says so in as many words — and rejects it **on its inbound**:
118 lines over twenty symbols, *"Twenty is worse than twelve."* Dec. 8 then names
`Character Catalogue` the strongest candidate for #4 at **2.20% outbound —
eighteen times `Sprite Rig`'s ratio** — on the strength of a six-symbol inbound.
If outbound decided, #4 would be `Sprite Rig` and it is not.

So the method actually applied across dec. 8 and dec. 9 is not a ranking at all.
It is **inbound concentration as a gate that outbound cannot override, with
outbound deciding among the systems that pass it** — ADR-0141 dec. 2's
*"One symbol is a port; twelve is a surface with no interface"* doing the work
of a threshold. A filter and a tie-break, not first, second and third.

**What would falsify it**, per the form ADR-0156 set: an extraction where a
wide-but-shallow inbound surface costs more than a narrow outbound reach — where
publishing a twenty-name API turns out cheaper than severing forty-four lines.
**#4 is that experiment and it is already scheduled.** `Character Catalogue`
(OUT 47, 44 of them into `Battle`; IN 21 over 6 symbols) against `Sprite Rig`
(OUT 6, the best in the table; IN 118 over 20). Whichever #4's pass 1 takes, it
settles this, and it should say which reading decided rather than inheriting the
sentence above.

**The selection does not depend on the resolution, and that is checkable.**
`Battlefield` wins under either statement of the method: dec. 3's inbound is the
most concentrated in the table, so it passes any gate, and its outbound is
second-best raw and best on debt. The ranking is load-bearing against exactly one
rival — `Campaign`, which passes the inbound gate handily at 10 lines over 3
symbols and loses **solely** on outbound (dec. 7). That is the whole of the
ranking's reach in this ADR.

**S2. Dec. 1's premise that an addon cannot name a host class is goal #5 policy,
not an engine constraint. Measured, not argued.**

Spike A below ran the case directly: a script under `addons/` naming a
`class_name` declared under `src/` resolves, type-checks and runs. Nothing in the
engine forbids it while the addon lives inside the host project, because
`res://addons/…` and `res://src/…` are one resource space over one script-class
cache. The tree agrees — `tools/check_addon_portability.py` reports the reaches
of an addon that still lives inside the host as **debt that does not fail**, and
`addons/exmateria_render` names `Tune` on 16 lines today.

The asymmetry dec. 1 is reaching for is real, but it bites one step later: an
outbound reach is a break the first time the addon is parsed **standalone**,
which is goal #5's test, and extraction #2 shipped exactly that break twice. The
sentence should read *an addon that leaves cannot name a host class*. As written
it claims a mechanical impossibility this project's own tree disproves, and the
difference is not pedantic — a policy admits documented exceptions, and dec. 2
already takes two of them.

**S3. The method has three readings, and this extraction's dominant cost is in
none of them.**

Dec. 6 measures the move at 49 files across seven directories plus a body of
`res://` path references, and says outright that this is invisible in the
cross-system table. Dec. 1 dismisses size as *"a mechanical cost that scales the
work without changing its shape"*; the Consequences then call this
*"the first extraction that is not small"* and ask pass 9 to score whether the
method scales. Both cannot be flatly true.

They reconcile once the path references are seen for what they are: **not size**,
but a fourth reading with no term in ADR-0141 dec. 2, which merely correlates
with size. Nothing here selects a different system. What it means is that pass 9's
scale question is a question about the **method**, and that #4's pass 1 should
measure path references as a reading in its own right instead of trusting size to
cover them. Pass 2's enumeration (C3) is what that reading looks like.

**S4. Dec. 2's eleven outbound lines are right, and they are not the number that
decides whether this system can ship. That one is 120.**

Pass 2 measured the autoload surface in both directions, because an autoload name
is a bare identifier and the three host-registered singletons this system owns
(`SkirtConfig`, `TileOverlayConfig`, `TileOverlayCompositor`) looked like an
unexamined seam. They are not one, and that half is settled: **all 40 lines naming
those three are inside `Battlefield` — zero from outside it** (`SkirtConfig` 15,
`TileOverlayConfig` 20, `TileOverlayCompositor` 5), none of them wear a
`class_name` that could confuse the scan, and an
autoload pointing into an addon is shipped precedent three times over —
`PSXDisplay` into `addons/exmateria_render/`, `ExMateriaAudioEngine` and `ExMateriaEffectSfx`
into the sound package. The file travels with the system; the host keeps writing
the registration line. Three of the 261 path rewrites, not a design question.

The other direction is the finding. **`Battlefield` names a host autoload on 120
lines across 13 files:**

| name | bucket | lines | files |
|---|---|---:|---:|
| `Tune` | `platform` | 62 | 7 |
| `DebugConfig` | `Debug` | 45 | 9 |
| `GameLogger` | `Debug` | 6 | 1 |
| `DebugOverlay` | `Debug` | 2 | 1 |
| `PSXDisplay`, `MapTintOverlay`, `ScreenEffectOverlay`, `SfxRouter` | cross-system | 5 | 3 |

Only the last five count under dec. 2's exclusions, and dec. 2 already lists all
five — the matrix does see autoload reaches, so nothing in dec. 2 is wrong. **The
other 115 are excluded from the ORDERING question and are still breaks in the
SHIPPING one**, and those are different questions asked of the same lines.
`tools/check_addon_portability.py` arm 2 exists for exactly this: an autoload name
is created by a *project*, never by an addon, so a file naming one cannot parse in
a project that does not autoload it. Extraction #2 shipped that defect twice. The
guard prints extraction #1's residue today — 16 lines of `Tune` in
`exmateria_render` — and calls it *what the next extraction has to answer*. **This
is that extraction, and it arrives with 120.**

Two things narrow it, and one of them is a hypothesis that failed.

**It is not the debug panels.** The obvious escape — leave the seven `src/debug/`
files in the host and the debt goes with them — recovers **7 lines of 115**.
The other 108 are in the geometry, camera and cursor core:
`PlayerCamera.gd` 23, `MapComposer.gd` 22, `TileOverlayConfig.gd` 16,
`SkirtGeometryGenerator.gd` 12, `TileCursor.gd` 11.

**The two names are not the same problem.** The 53 `Debug` lines are one syntactic
shape — `if DebugConfig.map_debug_enabled:` and two siblings, verbose-logging
gates in front of prints. That is a formatting convention wearing a dependency's
clothes and it severs cheaply. The 62 `Tune` lines are a real API —
`bind` 22, `on_update` 13, `get_value` 11, `set_value` 5 — and `Tune` is the
`platform` port ADR-0139 dec. 12 expressly permits an addon to name. Severing it
is not the goal; deciding whether `platform` ships beside the addon or is injected
into it is, and that decision is owed by whichever extraction first ships a
package that must parse alone.

**Pass 3 inherits this as a fifth item**, and it is the largest of the five.
Neither reading in dec. 2 predicts it, because both are about which system to take
next and this is about what taking it costs.

Reproduce: `python3 tools/autoload_reach.py Battlefield --check-collisions`. The
figure is measured rather than asserted for the same reason dec. 6's *21* should
have been — see C3.

**C1. Correction — this is the second application of ADR-0141 dec. 2's method,
not the third.** The Context above says third. Extraction #2 was not selected by
the isolation reading: `docs/agents/refactor-loop.md` → *Extraction order*
schedules `Audio` as the driver-split test, on the citation it gives
([ADR-0136](0136-audio-is-one-opcode-language-in-two-containers.md) dec. 5), and
ADR-0141's alternatives list rejected putting `Audio` first for that same reason —
the slot was the calibration slot, and the choice was an argument about what to
calibrate, not a measurement of isolation. `Render` is the one prior selection the
readings have ever decided. **A ranking with a single prior application is a young
rule**, which is the second reason S1's falsifier matters.

**C2. Correction — `refactor-loop.md`'s *Extraction order* restates the headline
dec. 2 refutes.** Its #3 entry pairs *nine lines of outbound debt* with
*0.13% of its size, the lowest ratio in the table*. Both halves are wrong and in
the same direction: 9 lines is **0.109%**, not 0.13% (0.13% is the 11-line raw
figure), and at 0.13% it is **not** the lowest — `Sprite Rig` is 0.12%, which is
the entire point of dec. 2's warning. The claim survives only on the debt column
and by two thousandths of a percent. Corrected in the same commit as this
amendment.

**C3. Correction — the outbound is 10 lines of debt, not 9, and the path
references are 261, not 21.** Both are dec. 6's blind spot biting dec. 2.

`assets/scenes/PlayerCamera.tscn` — this system's own scene — carries
`[ext_resource type="PackedScene" path="res://assets/scenes/CombatUI.tscn"]`, and
`CombatUI.tscn`'s script is `src/ui3/UICombatManager.gd`, booked `UI`. That is a
cross-system outbound reach into an unextracted system. It is not in dec. 2's
table because the matrix reads typed symbols out of `.gd` and this is a scene
`ext_resource`; it is not in dec. 5 either, which reports `PlayerCamera.gd`'s 788
lines as having no cross-system edge in either direction — true of the script, and
false of its scene. **`Battlefield`'s outbound debt is ten**, and the tenth is the
one dec. 2 could not see. The ratio moves from 0.109% to 0.121%, which is
`Sprite Rig`'s, so dec. 2's two-thousandths margin does not merely fail to be an
argument — **it is gone.** Dec. 2 already declined to rest the selection on it,
and dec. 3 is what carries the choice.

The path-reference count is worse. Dec. 6's **21** is not reproducible from any
stated definition and is blind to `tests/`. Enumerated at `778183181` over
`.tscn` / `.gd` / `.tres` / shader / `project.godot`, excluding `docs/` and
`tools/`: **32 inbound references from production, and 229 more from 123 test
files**, of which `src/map/MapComposer.gd` alone carries **114** (9 production,
105 tests) and `assets/scenes/PlayerCamera.tscn` **112** (8 production, 104
tests). The production 32 do include the nine `MapComposer` sites dec. 6 names, so
the instruments agree where they overlap; the gap is entirely `tests/` and three
`project.godot` autoload entries. Pass 4 budgets for **261**, and the test suite is
where four fifths of it lives. The full enumeration is
`docs/EXTRACTION-3-PATH-REFERENCES.md`.

**Spike A — an addon can hold what `Battlefield` is made of. Measured 2026-08-24,
Godot `4.8.dev.custom_build.3e530a3e9`, headful, with the plugin deliberately not
enabled.**

Nobody had checked. No extraction has yet put a scene-tree node class or a scene
file in an addon: `addons/exmateria_render/` holds an `EditorPlugin`, an autoload
`Node` and a `RefCounted`, and zero `.tscn`; `Audio` went to a package. This
system owns `Tile extends StaticBody3D`, a `CharacterBody3D`, and two scenes. Run
in a throwaway project reproducing the shape — an addon with a `plugin.cfg` and no
`[editor_plugins]` entry, which is this project's actual state:

| claim | |
|---|---|
| `class_name` on `StaticBody3D` / `CharacterBody3D` under `addons/`, registered and constructible from host code | PASS |
| a typed declaration against that `class_name` (parser, not runtime) | PASS |
| a `.tscn` in a nested addon subdirectory, instanced into a host scene by `res://` path | PASS |
| that scene's root keeping its addon-owned script, and its exported override | PASS |
| an addon-owned `.gdshader` bound through a `ShaderMaterial` inside the addon scene | PASS |
| `load()` / `instantiate()` / `preload()` against addon paths from host code | PASS |
| an autoload pointed at an addon script | PASS |
| a script under `addons/` naming a `class_name` under `src/` (S2) | PASS |

Both node classes land in `.godot/global_script_class_cache.cfg` with the plugin
disabled — registration is the editor's resource scan and has nothing to do with
plugin enablement. The tree proves the host half independently and always did:
`FoldSurface`, a `class_name` inside the disabled `exmateria_render` addon, is
declared as a type in `src/effects/EngineFoldCompositor.gd:70` and constructed on
line 100.

**Seeded, because a harness that only prints PASS proves nothing.** Mutating the
addon scene's exported `grid_x` from 7 to 99 turned exactly one line red and left
the other ten green, so the probe reads the mounted scene rather than a default.

**The second seed is a finding pass 4 needs.** Repointing the addon scene's script
`[ext_resource]` at a path that does not exist **does not stop the scene from
loading.** Godot prints a parse error to stderr and then mounts the node anyway,
as a bare `StaticBody3D` with no script: `get_node_or_null` returns it, the `is`
test against its class is false, and the first property access dies at an
arbitrary later site. So the Consequences' *"a `res://` path move is caught by
nothing until the scene loads"* is generous — the scene **loads, successfully**,
with the node silently stripped of its script. Pass 4 must verify the 261
references by loading **and asserting**, never by observing that a scene came up.

**What Spike A does not settle.** It ran in a minimal project, so it answers
engine mechanics and this project's plugin state and nothing else. Two instrument
questions are pass 4's, not the engine's. `classify_blueprint.walk()` takes `.gd`,
`.gdshader`, `.gdshaderinc`, `.glsl` and `.glslinc` and **no `.tscn`**, so both of
this system's scenes sit outside the 49-file / 8,247-line census and would move
unmeasured — the progress bar cannot see them in either direction. And a **root**
scene remains a host-owned declaration whatever the engine permits:
[ADR-0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md)
dec. 10's rule stands untouched, because it is about `project.godot` and
`docs/ROOT_SET.tsv` rather than about whether the engine can load the file.
Neither `assets/scenes/PlayerCamera.tscn` nor `assets/scenes/TileCursor.tscn` is a
declared root; `docs/ROOT_SET.tsv` books both **`component`** under ADR-0112
dec. 1.


## Consequences

- `docs/agents/refactor-loop.md` → *Extraction order* names `Battlefield` as #3,
  with the shape and the size caveat.
- **Pass 3 inherits four named items**: where `CursorBob` goes (dec. 4); the
  `Tile.reserved_by: Unit` inversion (dec. 2/5); whether the system splits at
  `src/map/` (alternatives); and `PlayerCamera.gd`'s 788 lines, which the
  instrument cannot see across any boundary and which the blueprint's two
  camera crossings both fail to find.
- **Pass 4 inherits the 21 path references.** A `class_name` move is caught by
  the parser; a `res://` path move is caught by nothing until the scene loads.
  `MapComposer.gd`'s nine are the concentration.
- The progress bar moves by **8,247 lines** if `Battlefield` extracts whole, and
  by **4,511** if it splits at `src/map/`.
- **This is the first extraction that is not small.** #1 moved 6 files, #2 moved
  12. Where those two tested the method, this one tests whether the method scales,
  and pass 9 should score that explicitly rather than only scoring the ten goals.
- The reading is a **floor** in both directions (ADR-0131 dec. 6). A duck-typed
  reach out of `Battlefield` would be invisible here, and `PaletteSubsystem`'s
  `WeakRef` to a `Unit` — ADR-0126's own worked example of the blind spot — sits
  one directory from this system.
