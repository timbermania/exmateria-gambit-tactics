# Extraction #3 — every `res://` path reference into and out of `Battlefield`

Loop **pass 2** deliverable 3 of extraction #3
([#500](https://github.com/timbermania/fft-monorepo/issues/500)), the one #500's
body flags as *most likely to be skipped*. Measured at trunk **`778183181`**,
2026-08-24. Regenerate with `python3 tools/path_refs.py Battlefield`; the raw rows
are `docs/EXTRACTION-3-PATH-REFERENCES.tsv` (`--tsv`).

**Read this before pass 4 moves a file.** A `class_name` move is caught by the
parser. A `res://` path move is caught by nothing that runs first — and, worse
than uncaught, a `.tscn` whose script `ext_resource` points at a moved path still
**loads**: Godot prints a parse error to stderr, mounts the node stripped of its
script, and the failure surfaces at whatever line first touches a property.
Measured, headful, on the 4.8 fork — ADR-0157 → *Soft spots*, Spike A.

> ✅ **Regenerated at extraction #3's loop pass 6** (ADR-0184). Every `target` below
> now reads `addons/exmateria_battlefield/…`; the tables in this document still spell
> the pre-move `src/` and `assets/` addresses, and are left that way deliberately —
> they are a measurement of a tree that no longer exists, and rewriting the addresses
> under prose that reasons about `src/map/` would make the prose lie instead of the
> paths. **The `.tsv` beside this file is the live register; this is the reading.**
> The set is unchanged across the move — **259 inbound, 33 outbound**, before and
> after — which is the property a re-point has to have and the one a count of the new
> tree alone cannot demonstrate.

## The count, and why it is not 21

> ⚠️ **Drifted to 262 at trunk `6a25e54f7`, and pass 4 must regenerate rather
> than read this** ([ADR-0159](adr/0159-platform-is-not-a-leaf-and-battlefields-seam-waits-on-inverting-it.md)
> dec. 1). Re-running the generator at HEAD and diffing produces **exactly one new
> row** — `src/core/Tune.gd:220` → `src/map/SkirtGeometryGenerator.gd` — with
> everything else line-number drift. That row was created by `c981f928c`, a #500
> commit that severed a `Battlefield` → `Debug` reach by giving the tunable to its
> production owner and, in the same act, added a new `platform` → `Battlefield`
> path reference. The register is sound; it is a snapshot of a moving tree.


ADR-0157 dec. 6 says **21**. That figure is not reproducible from any stated
definition and it is blind to `tests/`. The definition here is stated so the
number can be checked:

> every `res://<path>` literal in a file with one of the extensions
> `.tscn .gd .tres .gdshader .gdshaderinc .glsl .glslinc .cfg .godot .import`,
> with `docs/` and `tools/` excluded **as referrers** and `.git/`, `.godot/` and
> `project-assets/` excluded entirely. `project.godot` counts — an autoload entry
> is a path reference and it breaks the same way. The unit is the **reference**,
> not the file.

`classify_blueprint.walk()` takes no `.tscn` at all, so the system's own two
scenes are outside its 49-file / 8,247-line census and are supplied by name.

| | references | files |
|---|---:|---:|
| inbound, production | **32** | 17 |
| inbound, `tests/` | **229** | 123 |
| **inbound, total** | **261** | |
| outbound (all targets) | 38 | |
| outbound after ADR-0141 dec. 2's exclusions | **1** | |

The instruments agree where they overlap: dec. 6's *"`MapComposer.gd` alone is
mounted or preloaded by path in nine places, eight of them scenes"* is exactly
the production column below. The whole gap is `tests/` plus three `project.godot`
autoload entries.

### Where the weight is

| target | total | prod | tests |
|---|---:|---:|---:|
| `src/map/MapComposer.gd` | **114** | 9 | 105 |
| `assets/scenes/PlayerCamera.tscn` | **112** | 8 | 104 |
| `assets/scenes/TileCursor.tscn` | 8 | 4 | 4 |
| `src/scenes/CursorBob.gd` | 5 | 3 | 2 |
| the other 18 targets | 22 | 8 | 14 |

**Two files carry 226 of the 261.** Neither can be moved incrementally: every
reference to them has to change in the same commit, and 209 of those references
are in the test suite, which the cross-system matrix, the classifier and the
progress bar are all blind to.

## Inbound — production (32)

| referrer | bucket | → target |
|---|---|---|
| `assets/scenes/EffectViewer.tscn:4` | assembler | `assets/scenes/PlayerCamera.tscn` |
| `assets/scenes/EffectViewer.tscn:5` | assembler | `src/map/MapComposer.gd` |
| `assets/scenes/EffectViewer.tscn:6` | assembler | `assets/scenes/TileCursor.tscn` |
| `assets/scenes/FireCastRepro.tscn:4` | assembler | `assets/scenes/PlayerCamera.tscn` |
| `assets/scenes/FireCastRepro.tscn:5` | assembler | `src/map/MapComposer.gd` |
| `assets/scenes/FireCastRepro.tscn:6` | assembler | `assets/scenes/TileCursor.tscn` |
| `assets/scenes/GPUArena.tscn:4` | assembler | `assets/scenes/PlayerCamera.tscn` |
| `assets/scenes/GPUArena.tscn:5` | assembler | `src/map/MapComposer.gd` |
| `assets/scenes/GPUArena.tscn:6` | assembler | `assets/scenes/TileCursor.tscn` |
| `assets/scenes/NavigatorMain.tscn:4` | assembler | `assets/scenes/PlayerCamera.tscn` |
| `assets/scenes/NavigatorMain.tscn:5` | assembler | `src/map/MapComposer.gd` |
| `assets/scenes/ProgressionTester.tscn:4` | assembler | `assets/scenes/PlayerCamera.tscn` |
| `assets/scenes/ProgressionTester.tscn:5` | assembler | `src/map/MapComposer.gd` |
| `assets/scenes/ScenarioPlayer.tscn:4` | assembler | `assets/scenes/PlayerCamera.tscn` |
| `assets/scenes/ScenarioPlayer.tscn:5` | assembler | `src/map/MapComposer.gd` |
| `assets/scenes/TrapViewer.tscn:4` | assembler | `assets/scenes/PlayerCamera.tscn` |
| `assets/scenes/TrapViewer.tscn:5` | assembler | `src/map/MapComposer.gd` |
| `assets/scenes/UnitAnimationViewerScene.tscn:4` | assembler | `assets/scenes/PlayerCamera.tscn` |
| `assets/scenes/UnitAnimationViewerScene.tscn:5` | assembler | `src/map/MapComposer.gd` |
| `src/scenarios/NavigatorMain.gd:94` | assembler | `assets/scenes/TileCursor.tscn` |
| `src/core/Tune.gd:215` | platform | `src/map/MapComposer.gd` |
| `src/core/Tune.gd:219` | platform | `src/scenes/PlayerCamera.gd` |
| `src/core/Tune.gd:219` | platform | `src/scenes/TileCursor.gd` |
| `src/ui3/detail/DetailScene.gd:34` | **UI** | `src/scenes/CursorBob.gd` |
| `src/ui3/detail/EquipPickerMenu.gd:35` | **UI** | `src/scenes/CursorBob.gd` |
| `src/ui3/detail/StartActionMenu.gd:41` | **UI** | `src/scenes/CursorBob.gd` |
| `src/effects/PaletteSubsystem.gd:25` | **Effects** | `src/core/MapIlluminationDDA.gd` |
| `project.godot:31` | autoload | `src/map/SkirtConfig.gd` |
| `project.godot:32` | autoload | `src/map/TileOverlayConfig.gd` |
| `project.godot:43` | autoload | `src/effects/TileOverlayCompositor.gd` |
| `assets/materials/tile_cursor_opaque.tres:6` | asset | `assets/shaders/tile_cursor_opaque.gdshader` |
| `assets/materials/tile_overlay.tres:6` | asset | `assets/shaders/tile_overlay_mode0.gdshader` |

Four of these are not `assembler` reaches and are worth pass 3's attention: the
three `UI` menus preloading `CursorBob.gd` by path are the **glove** consumers
ADR-0157 dec. 4 describes, appearing here as paths rather than as the 31 typed
lines; and `PaletteSubsystem.gd:25` is the `Effects` preload dec. 3 already
counts. The three `project.godot` autoload entries are a different animal
entirely — `SkirtConfig`, `TileOverlayConfig` and `TileOverlayCompositor` are
**host-registered singletons**, and an addon cannot register an autoload
(`addons/exmateria_render/plugin.gd` states the rule and declines to work around
it). Three of this system's files are named by the host's project file, and that
is pass 3's seam question, not pass 4's mechanical one.

## Inbound — `tests/` (229 across 123 files)

| target | refs | test files |
|---|---:|---:|
| `src/map/MapComposer.gd` | 105 | 105 |
| `assets/scenes/PlayerCamera.tscn` | 104 | 104 |
| `assets/scenes/TileCursor.tscn` | 4 | 4 |
| `src/scenes/CursorBob.gd` | 2 | 2 |
| 14 further targets, one reference each | 14 | 14 |

Rows in the TSV (`in_tests = 1`). The shape is one line per test scene: a GPU
combat test mounts `PlayerCamera.tscn` and preloads `MapComposer.gd` at lines 4
and 5 of its `.tscn`, and there are ~105 of them. This is mechanical to rewrite
and impossible to skip, and it is four fifths of the extraction's path cost.

## Outbound — 38 references, of which **one** is cross-system

| → bucket | refs | note |
|---|---:|---|
| `?` | 14 | asset files: `assets/maps/`, `assets/doodads/`, `RANGETILE.*`, `cursor_bob.json`, two `.tres` |
| `schema` | 10 | `psx_ot_depth.gdshaderinc`, `psx_color_stack.gdshaderinc`, `DepthMode.gd` — the published kernel |
| `platform` | 8 | `psx_par.gdshaderinc`, `psx_dither.gdshaderinc` |
| `Debug` | 5 | five debug panels preloading `src/debug/TuneField.gd` |
| **`UI`** | **1** | `assets/scenes/PlayerCamera.tscn:5` → `assets/scenes/CombatUI.tscn` |

ADR-0141 dec. 2 excludes `platform`, `schema` and `Debug`. What survives is one
reference, and it is a real cross-system outbound reach that dec. 2's eleven-line
table does not contain:

```
assets/scenes/PlayerCamera.tscn:5
  [ext_resource type="PackedScene" path="res://assets/scenes/CombatUI.tscn" id="3_combat_ui"]
```

`CombatUI.tscn`'s script is `src/ui3/UICombatManager.gd`, booked `UI`. ADR-0157
dec. 5 reports `PlayerCamera.gd`'s 788 lines as having no cross-system typed edge
in either direction — true of the script, and false of its scene, which mounts a
`UI` scene as a child. **The system's outbound debt is ten lines, not nine.** See
ADR-0157 → *Soft spots* C3 for what that does to dec. 2's margin.

## The closure, from the root set — pass 2 deliverable 2

`Battlefield` owns two scenes, both booked **`component`** in `docs/ROOT_SET.tsv`
under ADR-0112 dec. 1 — neither is a declared root, so ADR-0135 dec. 10's rule
that an addon cannot ship a root scene does not bite here.

`assets/scenes/PlayerCamera.tscn` is mounted by eight scenes, and **three of the
eight are declined**, i.e. dead under ADR-0112 and awaiting pass 5's deletion:

| scene mounting `PlayerCamera.tscn` | root set | also mounts |
|---|---|---|
| `assets/scenes/GPUArena.tscn` | **root**, game (`run/main_scene`) | `TileCursor.tscn`, `MapComposer.gd` |
| `assets/scenes/NavigatorMain.tscn` | **root**, game | `MapComposer.gd` |
| `assets/scenes/ScenarioPlayer.tscn` | **root**, game | `MapComposer.gd` |
| `assets/scenes/EffectViewer.tscn` | **root**, authoring | `TileCursor.tscn`, `MapComposer.gd` |
| `assets/scenes/TrapViewer.tscn` | **root**, authoring | `MapComposer.gd` |
| `assets/scenes/FireCastRepro.tscn` | *declined* | `TileCursor.tscn`, `MapComposer.gd` |
| `assets/scenes/ProgressionTester.tscn` | *declined* | `MapComposer.gd` |
| `assets/scenes/UnitAnimationViewerScene.tscn` | *declined* | `MapComposer.gd` |

`assets/scenes/TileCursor.tscn` is reached by four production sites — three of
those scenes plus `src/scenarios/NavigatorMain.gd:94`, which mounts it in code
rather than in the scene.

**So the live closure is five roots, not eight scenes**, and three of the eight
production `PlayerCamera.tscn` references are on code pass 5 deletes. Pass 4
should not spend a rewrite on them; pass 5's deletion order and pass 4's path
rewrite touch the same three files and should be sequenced deliberately rather
than raced.

## What this does not cover

- **`.uid` siblings.** Godot 4.4+ writes a `.uid` next to each script and some
  `ext_resource` lines carry `uid="uid://…"` alongside `path=`. A uid survives a
  move where a path does not, so a reference carrying both may keep working and
  mask a broken path — and a `.uid` file itself must move with its script. Not
  enumerated here; pass 4 should check whether the fork writes them for every
  moved file.
- **Duck-typed and string-built paths.** Anything assembled at runtime
  (`"res://" + var`) is invisible to a literal scan, the same floor ADR-0131
  dec. 6 states for the symbol matrix.
- **`docs/` and `tools/`.** Excluded as referrers by definition. A path citation
  in a doc rots silently; that is ADR-0111 dec. 7's argument for vault anchors,
  and pass 2 deliverable 1 is where it is handled.
