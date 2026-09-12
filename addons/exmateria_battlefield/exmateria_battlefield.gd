class_name ExMateriaBattlefield
extends RefCounted

## The whole public surface of `addons/exmateria_battlefield`, and the only name
## it puts in your project.
##
## Godot has no package scope: a `class_name` is engine-global, so every one an
## addon declares lands in YOUR global scope — and when you declare a colliding
## one, the ADDON's file is what fails to parse, pointing your error at a file
## you did not write. This addon declared **30** of them before ADR-0211. It now
## declares one, and reaches its own internals by `preload` path.
##
## A script constant is a full type — annotation, `is` check, `.new()`:
##
##     var lattice: ExMateriaBattlefield.Lattice = ...
##
## and a consumer may alias one back to a bare local name, which is what keeps
## every existing use site spelled the way it was (ADR-0211 dec. 4):
##
##     const Lattice = ExMateriaBattlefield.Lattice
##
## **This list IS the supported surface.** If a script is not named here it is
## internal, whatever its visibility says — and `tools/check_addon_globals.py`
## holds both directions: nothing else in this addon may declare a global, and
## nothing named here may dangle.
##
## 🔴 THIS IS THE SYMBOL SURFACE, NOT THE COUPLING SURFACE (ADR-0211 dec. 3).
## A name absent from this list can still be reached by a node path or a scene
## `path=`/`uid=` — `MapComposer` holds no global name and is still the addon's
## most-reached file by path, through the host's declared `ProceduralMap.tscn`
## mount. That axis is `check_lattice_scene.py`'s criterion 4 (ADR-0205), and
## "not published here" never means "nothing depends on it".
##
## Nothing here is instantiated. `ExMateriaBattlefield.new()` gives you an empty
## RefCounted; the class exists to be a namespace, not an object.

# --- the lattice: the terrain query surface the host compiles against -------

## The terrain query surface, and the most load-bearing name on this list —
## **50 references over 22 `src/` files** (ADR-0210 dec. 1). The GPU combat
## pipeline takes one as a parameter, `CombatHost`/`CombatLoop`/`ScenarioWeather`
## each hold one as a typed field, and strategy placement names it throughout.
## Host use: `src/gpu/CombatHost.gd` holds `var lattice: Lattice` at the combat seam.
const Lattice = preload("res://addons/exmateria_battlefield/lattice/Lattice.gd")

## A single tile node. ⚠️ **NO HOST NAMER SINCE ADR-0218**, and the reason it was
## published is the reason it now has none. ADR-0211 dec. 5 published it because a
## host fixture could not fake it — a `Lattice` subclass answering `_tile_at` with a
## stand-in throws `Trying to return a value of type "Node3D (_Stand)" from a
## function whose return type is "Tile"` and hands the caller `<null>` (measured,
## ADR-0210 dec. 5) — so the host's shared cursor/camera fixture had to mint real
## ones. That file is deleted: `TerrainFixture` mints them from INSIDE the addon,
## where the name needs no publishing at all. Kept published because a published-but-unnamed
## name is reported and never a defect (ADR-0196 dec. 4); whether it should now be
## withdrawn is a question for the next `check_addon_globals` pass, not for this one,
## because ADR-0218's own accounting says this list goes 14 → 15.
const Tile = preload("res://addons/exmateria_battlefield/lattice/Tile.gd")

## The terrain fixture — the addon's shipped way to stand a `Lattice` up from data,
## and the only sanctioned lattice test seam (ADR-0218 dec. 1/2). Nothing in it is
## faked: it drives `DynamicTerrainBuilder` and hands back a real `Lattice` over real
## `Tile`s, which is why the ten hand-written doubles it replaced could go.
##
## It is on this list rather than reached by path because the host idiom for the
## addon is a façade alias and `check_lattice_scene.py` enforces exactly that on
## `tests/` — a host `preload` of an addon path would launder a symbol dependency
## into a path row, which is not payment. An addon that ships no way to test its own
## port makes every consumer invent one, and this list is where "we ship one" is said.
## Host use: `tests/TileCursorIntegrationTest.gd` stands its 3×3 grid up with one.
const TerrainFixture = preload("res://addons/exmateria_battlefield/lattice/TerrainFixture.gd")

## Tile geometry constants shared with the host's motion code.
## Host use: `src/scenarios/ScenarioPathMotion.gd` scales gravity by TILE_SCALE.
const MapConstants = preload("res://addons/exmateria_battlefield/lattice/MapConstants.gd")

# --- the cursor ------------------------------------------------------------

## The cursor port (ADR-0206) — the published name that replaced two
## implementation names, `TileCursor` and `CursorController`.
## Host use: `src/debug/CursorDebugPanel.gd` takes one in `setup()` and reads SEMI_MODE_LABELS.
const CursorRig = preload("res://addons/exmateria_battlefield/cursor/CursorRig.gd")

## ⚠️ NO HOST NAMER TODAY. Declared before ADR-0200 moved it out of the effect
## pool. Kept published because a published-but-unnamed name is reported and
## never a defect (ADR-0196 dec. 4) — said out loud so the next reader does not
## read silence as use.
const TileCursorCompositor = preload("res://addons/exmateria_battlefield/cursor/TileCursorCompositor.gd")

# --- the overlay -----------------------------------------------------------

## Host use: `src/scenes/GambitBattle.gd` paints the deployment zone, the latch and the
## unavailable tiles — that is the host use, and since ADR-0258 it is the whole of it.
## `addons/exmateria_battlefield/cursor/CursorController.gd` paints the cursor's own
## marking, but it is an **in-addon namer** (ADR-0217 dec. 5): a file inside this very
## addon, so it is evidence the name is USED, not evidence a host needs it published.
## (The retired strategy phase — `PlacementPhaseController`, `StrategyPhaseManager`,
## `PlacementTileHighlighter` — used to be most of this list.)
const TileHighlights = preload("res://addons/exmateria_battlefield/overlay/TileHighlights.gd")

## Host use: `src/debug/TilesDebugPanel.gd` builds its rows from `tunable_types()` and uv_*.
const TileOverlayConfig = preload("res://addons/exmateria_battlefield/overlay/TileOverlayConfig.gd")

# --- terrain ---------------------------------------------------------------

## Host use: `src/debug/SkirtDebugPanel.gd` renders GROUP_ORDER / GROUP_TITLES / PROPERTY_META.
const SkirtConfig = preload("res://addons/exmateria_battlefield/terrain/SkirtConfig.gd")

## ⚠️ **TEST-ONLY NAMER** (ADR-0211 dec. 5). Published because it is blocked the
## same way `Tile` is: `MapComposer.dynamic_geo_builder` is TYPED and GDScript
## enforces the type on assignment, so a duck-typed stand-in throws. The only
## other working route — a host `preload` of the addon path — launders an arm-3
## row into a criterion-4 path row, which is not payment.
## Host use: `tests/MapFieldObjectPaletteWiringTest.gd` constructs one directly.
const DynamicGeometryBuilder = preload("res://addons/exmateria_battlefield/terrain/DynamicGeometryBuilder.gd")

# --- texturing -------------------------------------------------------------

## ⚠️ **TEST-ONLY NAMER** (ADR-0211 dec. 5). Published because it cannot be paid
## by a move: all four legs of its unit test need host MAP062 content, and an
## addon-owned test runs only under the stranger rig, which has no content root
## — so the move would delete the assertion outright (ADR-0194 dec. 4,
## ADR-0210 dec. 5).
## Host use: `tests/MapTextureAnimatorTest.gd` drives it against host map content.
const MapTextureAnimator = preload("res://addons/exmateria_battlefield/texturing/MapTextureAnimator.gd")

## Host use: `tests/MapPaletteFieldObjectTest.gd` calls `create_palette_texture()`
## and `tools/generate_palette_texture.gd` is the editor-side generator — published
## by ADR-0208 dec. 4 to RECORD a surface two host callers already used.
const PaletteTextureGenerator = preload("res://addons/exmateria_battlefield/texturing/PaletteTextureGenerator.gd")

## 🔴 THIS ROW HAS NO NAMER, AND THE LINE ABOVE PREDICTED IT. The citation used to
## read *"closing #1192 drains this citation along with four arm-5 lines, at which point
## this row has no namer at all"* — #1192 closed on 2026-09-12 and that is now the state.
## `Effects`' `PaletteSubsystem.build_illumination()` was the sole sibling namer and it is
## deleted: the Holy/E015 additive only ever tinted the PSX's untextured flat-colour
## terrain class, which Godot does not render, and a probe measured 0 calls across eight
## battle scenes against 2 in its own unit test as a positive control.
##
## ⚠️ WHAT IS LEFT IS `Battlefield`'s TO PRICE, NOT `Effects`'. The class and the
## `map_illum_add` uniform in `texturing/indexed_color.gdshader` stay — #1192 scopes them
## out explicitly and `MapIlluminationDDATest` still covers the class on its own. But by
## this façade's own derivation rule a published name wants an outside namer, and there is
## none now. Either this row is unpublished, or the reservation is restated as this
## package's own rather than as a host use that no longer exists.
const MapIlluminationDDA = preload("res://addons/exmateria_battlefield/texturing/MapIlluminationDDA.gd")

# --- pathfinding -----------------------------------------------------------

## The `{28} Walk To` ROUTING half — the ROM's own route planner, and
## `RomWalkStepper`'s sibling: this one turns a start and a destination into route
## bytes, that one turns route bytes into a trajectory. A transcription, not a
## model, scored against 18 live PSX captures (`EventPathfinderTest`).
## Host use: `src/scenarios/ScenarioVM.gd` owns one and plans every `{28}` with it.
const EventPathfinder = preload("res://addons/exmateria_battlefield/pathfinding/EventPathfinder.gd")

# --- terrain ---------------------------------------------------------------

## The map file as the ROM's own eight-byte tiles, PSX coordinates and all — the
## input BOTH halves of `{28} Walk To` need and neither could get from a `Lattice`,
## which carries no depth, slope or thickness. Published because the host is the
## side that knows WHICH map is loaded (`ScenarioVM.current_map_id`); the addon
## cannot ask.
## Host use: `src/scenarios/ScenarioVM._plan_walk_route` reads the current map with it.
const RomTerrain = preload("res://addons/exmateria_battlefield/terrain/RomTerrain.gd")

# --- motion ----------------------------------------------------------------

## The `{28} Walk To` RENDER half — the ROM's own per-frame walk stepper, and
## `EventPathfinder`'s sibling: that one turns a start and a destination into
## route bytes, this one turns route bytes into a trajectory. A transcription,
## not a model, scored 43 510/43 510 field-frames over thirteen PSX captures
## (`RomWalkStepperTest`).
## Host use: `src/scenarios/ScenarioPathMotion.gd` runs one behind its world-space API.
const RomWalkStepper = preload("res://addons/exmateria_battlefield/motion/RomWalkStepper.gd")

# --- debug -----------------------------------------------------------------

## Host use: `src/debug/ScenarioUnitAlignmentDebugPanel.gd` holds one and `.new()`s it,
## and `tools/capture_grid_beat.gd` builds one for the PSX tile-grid A/B — ADR-0208
## dec. 3, where a standalone entry point has no mount available and a published
## name is its only route.
const MapGridOverlay = preload("res://addons/exmateria_battlefield/debug/MapGridOverlay.gd")
