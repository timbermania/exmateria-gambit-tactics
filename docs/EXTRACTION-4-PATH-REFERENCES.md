# Extraction #4 — every `res://` path reference into and out of `Sprite Rig`

Loop **pass 2** deliverables 2 and 3 of extraction #4. Measured at trunk **`571e4e3bd`**,
2026-08-31. Regenerate with `uv run python tools/path_refs.py "Sprite Rig"`; the
raw rows are `docs/EXTRACTION-4-PATH-REFERENCES.tsv` (`--tsv`).

This discharges **ADR-0213 soft spot S3**, which asked for the count to be
re-taken *"with the real tool before any move is budgeted"*. It was not a
formality: **the answer moves the conclusion.**

**Read this before pass 4 moves a file.** A `class_name` move is caught by the
parser. A `res://` path move is caught by nothing that runs first — and a `.tscn`
whose script `ext_resource` points at a moved path still **loads**: Godot prints
a parse error to stderr, mounts the node stripped of its script, and the failure
surfaces at whatever line first touches a property (ADR-0157 → *Soft spots*,
Spike A).

## The count

`Sprite Rig` is **29 classified files, 0 scenes supplied.** Unlike `Battlefield`,
which owns two `.tscn` outside `classify_blueprint.walk()` and has to declare
them by name, this system owns **no scene of its own** — every scene that mounts
it belongs to somebody else. That is a fact about the seam, not an omission, and
it is why `--scene` is empty here.

| | references | files |
|---|---:|---:|
| inbound, production | **12** | 7 |
| inbound, `tests/` | **11** | 7 |
| **inbound, total** | **23** | 14 |
| outbound (all targets) | **22** | 13 |
| outbound after ADR-0141 dec. 2's exclusions | **0** | |
| **total** | **45** | |

Inbound referrer buckets: `?` 15, `Battle` 6, `Cutscene` 1, `assembler` 1. The
fifteen `?` are eleven references from seven `tests/` files plus four from two
resources the classifier does not book — `assets/animation_resolution/map.tres`
(3) and `assets/materials/unit.tres` (1). The `files` column counts distinct
REFERRERS, so production 7 + tests 7 is 14 distinct files, not 15 references.

## S3 — the comparison ADR-0213 dec. 6 asked for, on one instrument

Dec. 6 claimed *"a ratio of 7.7"* against `Battlefield` from a source that was
not `path_refs.py`. Here both systems are read by the same tool. `Battlefield`'s
register is `docs/EXTRACTION-3-PATH-REFERENCES.tsv`, taken at `778183181` over a
49-file / 8,247-line system.

| | `Battlefield` (pass 2) | `Sprite Rig` (pass 2) | ratio |
|---|---:|---:|---:|
| inbound | 259 | **23** | **11.3×** |
| outbound | 33 | **22** | **1.5×** |
| total | 292 | **45** | 6.5× |
| lines in system | 8,247 | 5,343 | |
| inbound per 100 lines | 3.14 | **0.43** | 7.3× |
| outbound per 100 lines | 0.40 | **0.41** | **0.98× — a wash** |

**And two of those cells compare unlike denominators.** `path_refs.py` counts
references INTO a system, but a system's own `.tscn` scenes are outside
`classify_blueprint.walk()` — they enter only through `--scene`, which the tool
hardcodes for `Battlefield` (`DEFAULT_SCENES`: `PlayerCamera.tscn`,
`TileCursor.tscn`) and cannot supply for `Sprite Rig`, **which owns no scene at
all**. So **120 of `Battlefield`'s 259** inbound rows — and **12 of its 29**
production rows — target one of those two scenes, and `Sprite Rig` has no such
row to have. Counting only script, shader and resource targets:

| | `Battlefield` | `Sprite Rig` | ratio |
|---|---:|---:|---:|
| inbound, non-scene targets | 139 | 23 | **6.0×** |
| inbound excl. `tests/`, non-scene targets | 17 | 12 | **1.4×** |

Both readings are true; they answer different questions. The raw row is *"how
many references does a move have to re-point"*, and a scene is a real file with a
real path, so **11.3× is the honest re-pointing cost**. The non-scene row is
*"how coupled is the code"*, and there the production gap is **1.4×, not 2.4×** —
nearly a wash, the same shape the outbound row already shows. Owning no scene is
a genuine property of `Sprite Rig` and not a tool artifact, but reading 2.4× as
*coupling* credits it for a scene it never had. Both rows stay on the record.

**Two readings, and they do not agree.**

The **inbound** advantage is real and *larger* than dec. 6 claimed: 11.3× raw,
7.3× per line. Twenty-three inbound path references against two hundred and
fifty-nine is the difference between a seam you can enumerate on one screen and
one you cannot. On this axis S3 confirms the ADR and improves it.

The **outbound** advantage is **not there**. Twenty-two against thirty-three is
1.5× on a system that is 35% smaller, which per line is a dead heat — `Sprite Rig`
emits marginally *more* outbound path references per line of itself than
`Battlefield` did. Dec. 6's single ratio averaged two numbers that point in
opposite directions, and the direction that matters for a move is the one it
hid: **inbound references are other people's files to re-point, outbound
references are this system's own claims about where the world is.** The second
kind travels with the code and breaks silently in the new location.

### Where the outbound weight is: 17 of 22 point at `assets/`

| target class | refs | targets |
|---|---:|---|
| `assets/sprites/…` and `assets/animation_resolution/…` | **17** | textures, palettes, `map.tres`, three JSON tables, `02.png`, an EVTCHR frame index |
| `addons/exmateria_schema/…` `.gdshaderinc` | 3 | `psx_ot_depth`, `psx_color_stack` |
| `addons/exmateria_platform/…` `.gdshaderinc` | 2 | `psx_par` |

Only the five `addons/` rows are cross-package includes, and ADR-0141 dec. 2
excludes `schema` and `platform`, which is why the tool's *"what is left"* list
prints `(none)`. **That zero is not the same as no outbound coupling.** The
seventeen `assets/` rows are a hard-coded content address in nine files, and
`SpriteLayerManager.gd` alone holds seven of them, including one absolute sprite
sheet (`assets/sprites/02.png:275`).

This is **goal #6's question, not goal #5's**, and pass 3 owes an answer: when
`Sprite Rig` becomes an addon, do the sprite tables and textures go with it, stay
in the host, or become a declared dependency? Nothing in this register decides
that. What it establishes is that the content shadow — not the class graph — is
the largest single thing the move has to relocate, and ADR-0213 never counted it
because `touch_matrix.py` cannot see a string.

## Inbound — production (12)

| referrer | bucket | target | line |
|---|---|---|---:|
| `assets/scenes/Unit.tscn` | `Battle` | `assets/shaders/unit.gdshader` | 5 |
| `assets/scenes/Unit.tscn` | `Battle` | `src/animation/SpriteLayerManager.gd` | 7 |
| `assets/scenes/Unit.tscn` | `Battle` | `src/animation/AnimationStateController.gd` | 9 |
| `assets/scenes/Unit.tscn` | `Battle` | `src/animation/CameraRelativeRenderer.gd` | 11 |
| `src/units/Unit.gd` | `Battle` | `src/animation/DistortMovementController.gd` | 15 |
| `src/gpu/CombatLoop.gd` | `Battle` | `src/animation/WeaponAnimationSelector.gd` | 37 |
| `src/scenarios/ScenarioVM.gd` | `Cutscene` | `src/animation/SpriteLayerManager.gd` | 4509 |
| `assets/scenes/SequenceViewer.tscn` | `assembler` | `assets/shaders/unit.gdshader` | 4 |
| `assets/materials/unit.tres` | `?` | `assets/shaders/unit.gdshader` | 3 |
| `assets/animation_resolution/map.tres` | `?` | `…/resources/AnimationResolutionMapResource.gd` | 3 |
| `assets/animation_resolution/map.tres` | `?` | `…/resources/SpriteTypeResource.gd` | 4 |
| `assets/animation_resolution/map.tres` | `?` | `…/resources/ActivityRowResource.gd` | 5 |

**`assets/scenes/Unit.tscn` is the seam.** One scene, booked `Battle`, names four
`Sprite Rig` files by `ext_resource` — a shader, the layer manager, the state
controller and the camera-relative renderer. Nothing in `touch_matrix.py` can see
it, because a `.tscn` is not walked and a path is not a typed symbol. It is the
single densest inbound object in the tree and it is invisible to every instrument
ADR-0213 used.

`assets/animation_resolution/map.tres` is the mirror image on the outbound side:
a resource file that *is* an instance of three of this system's own classes, and
that three of this system's own files load by path. It travels with the system or
the system does not load.

## Inbound — `tests/` (11 across 7 files)

`UnitMaterialVariantTest.gd` is four of them on its own (three shaders plus
`SpriteLayerManager.gd`); `ScenarioDeadUnitFadeTest.gd` two;
`CinematicLowRangeSeqKeyTest`, `CrystalSpriteCompositorTest`, `DepthCenterBboxTest`,
`FormationPlacementTest` and `UnitShaderPanelTuneFieldTest` one each.

Eleven is a small number and it is the *reason* the comparison with `Battlefield`
is lopsided: 230 of `Battlefield`'s 259 inbound references were `tests/`. Strip
tests from both and the raw inbound ratio is 29 : 12 — **2.4×**, not 11.3×; strip
the scene targets `Sprite Rig` has no equivalent of and it is 17 : 12, **1.4×**.
Those readings belong in the record too, and they are the least flattering of the
four.

## The closure, from the root set — pass 2 deliverable 3

`refactor-loop.md` row 2 asks for three things and this is the third: the closure
from the **declared** root set, `docs/ROOT_SET.tsv`'s 13 `root` rows, walked with
`closure.py`'s seven static edges from each root's scene *and* its script.

| reaches | root |
|---:|---|
| 28 | `GPUArena`, `NavigatorMain`, `Formation`, `AllTemplatesFormation`, `DetailScreen`, `FormationDetailTransition`, `FormationDev`, `ScenarioPlayer`, `EffectViewer`, `SequenceViewer`, `TrapViewer` |
| 0 | `OpeningScene`, `WorldMap` |

**Eleven of thirteen roots reach the system, and they all reach the same 28
files.** Not overlapping subsets — the identical set, every time. `Battlefield`'s
closure at extraction #3 was partial and per-root; this one is **total**. Two
consequences follow directly:

* No root can be used to scope a smaller move. There is no "the part of
  `Sprite Rig` that only `Formation` needs".
* Any test that boots any of the eleven loads the whole system, so a change
  anywhere in it is in-scope for all of them. That is a floor on what
  `scoped_tests.py` will select, not a surprise about it.

**The two zeroes are a fact about the seam, not a gap.**
`assets/scenes/OpeningScene.tscn` and `assets/scenes/WorldMap.tscn` reach nothing
in `Sprite Rig`. Neither draws a unit; both are already on the far side of the
line a move would draw.

**One file no declared root reaches: `src/animation/ResourceHotReload.gd` (47
lines).** The scope is 29 files and the closure is 28. Its only path in is
`assets/scenes/UnitAnimationViewerScene.tscn` →
`src/scenes/UnitAnimationViewerScene.gd` → `ResourceHotReload.gd`, and that scene
is `declined` in `ROOT_SET.tsv` on ADR-0135 dec. 6. This is **pass 5's deletion
question**, the same shape `Battlefield` presented. It is not being called dead
here: UNREACHED is a **ceiling** on deadness, never a floor (ADR-0112 dec. 1),
and a runtime-built path is invisible to every edge this walk has.

### `Unit` is the articulation point

Delete `src/units/Unit.gd` and `assets/scenes/Unit.tscn` from the walk and the
totality dissolves into a spread:

| reach without `Unit` | roots |
|---:|---|
| 21 | `GPUArena`, `NavigatorMain`, `SequenceViewer` |
| 16 | `Formation`, `AllTemplatesFormation`, `DetailScreen`, `FormationDetailTransition`, `FormationDev` |
| 15 | `ScenarioPlayer` |
| 2 | `EffectViewer` — `DisplayActivity.gd`, `SpritePaletteResolver.gd` |
| 1 | `TrapViewer` — `SpritePaletteResolver.gd` |

`Unit` is not a gate: 21 of 28 files survive its removal on three roots. It is
what makes the closure *total* — seven files reach the tree only through it, and
the two viewer roots reach essentially nothing without it. A worked path shows
how far away the entry is:

```
DetailScreen.tscn -> DetailSceneBoot.gd -> Character.gd -> UnitProgression.gd
                  -> StatCalculator.gd -> Unit.gd -> UnitDisplay.gd
```

Five `Battle` / `Character Catalogue` hops before the first `Sprite Rig` file.
This is the **third** independent instrument to land on `Unit` this pass: the
typed-symbol matrix has it as a reach, this document's production inbound table
has `Unit.tscn` as the densest single referring object, and the closure has it as
the articulation point. Registered in the pass-2 ADR as decision 11.

## What this does not cover

- **Duck-typed and runtime-built paths.** A `"res://…/%s.gd" % name` is not a
  literal and is not here. The register is a **floor**.
- **`docs/` and `tools/` as referrers** are excluded by the tool. Five
  `tools/*.py` guards name unit shader paths; they are real coupling and are
  recorded in the BLUEPRINT audit instead, where they falsify a stronger claim.
- **The class graph.** That is `touch_matrix.py`'s reading, corrected in the
  pass-2 ADR. This document and that one measure different things and neither
  substitutes for the other — which is the whole reason ADR-0157 called path
  references *"the fourth reading"*.
