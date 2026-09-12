class_name BattlefieldWiring
extends RefCounted

## ADR-0134's assembler, for the three lines `Battlefield` used to push itself
## (#589, owed by ADR-0175 dec. 5). *"A composition that wires once and leaves."*
##
## The addon publishes three outputs and names nobody who wants them:
##
##     MapComposer.map_material_created / map_materials()   -> Effects.TintedSurfaces
##     MapComposer.map_gradient_resolved / map_gradient()   -> Effects.ScreenEffectOverlay
##     TileCursor.cursor_stepped                            -> Audio.SfxRouter
##
## Before this, each was a direct call from inside the addon into a host
## autoload: `DynamicGeometryBuilder` named `MapTintOverlay`, `MapComposer` named
## `ScreenEffectOverlay`, `TileCursor` named `SfxRouter`. Those three lines were
## the ENTIRE remaining scored outbound debt of extraction #3 (ADR-0157 dec. 2's
## nine, less the six the lattice work still owes) and goal #5's literal test
## fails on any of them: a tactics RPG that vendored this addon would have to
## supply three autoloads with those exact names.
##
## WHY ONE CLASS AND NOT ADR-0167's TWO. ADR-0167 built a `Debug`-side class
## called from six assembler roots, and that was right there — mounting a panel
## is real behaviour with ordering constraints. These are three hand-offs of
## values the composer has already computed, and splitting them by CONSUMER
## system would make two classes for three statements. They are split by
## SUBJECT instead — one call per thing the host owns.
##
## WHY IT IS BOOKED `assembler` AND WHY THAT MATTERS. ADR-0167's severance first
## read as GROWTH (`-> Debug` 42 -> 47) because the new file the fix was written
## in got booked to the bucket it was draining. `assembler` is not one of the
## eleven systems, so this file is scored by no system's reach count and the
## delta is attributable. That is a property of the booking, not luck — see
## `classify_blueprint.py`, where this file has its own exact rule beside the
## `*Boot.gd` wiring files ADR-0135 dec. 10 moved here for the same reason.
##
## BOTH HALVES OF EACH MAP SEAM ARE USED, AND NEITHER ALONE IS CORRECT. The
## builder is constructed inside `_build_map`, so nothing outside the addon can
## connect before the first materials and the first gradient exist — a
## connect-only wiring misses them. And materials are created lazily per surface
## type on every `rebuild_mesh`, including doodad add/remove long after the map
## composed — a drain-only wiring goes stale. So each map seam is replay THEN
## connect.


## Wire a composed map's two outputs into `Effects`. Call it from the scene root
## after the map is built — the same moment `MapDebugPanels.register_map_panels`
## already fires. Re-callable: the connect guards are idempotent, and
## `TintedSurfaces.register_surface` de-duplicates by design.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const CursorRig = ExMateriaBattlefield.CursorRig

static func wire_map(map_composer: Node) -> void:
	if map_composer == null:
		return

	# ⚠️ A MAP NODE IS DUCK-TYPED AND NOT EVERY ONE COMPOSES MATERIALS. The
	# parameter is `Node` because the addon publishes these outputs and names
	# nobody who wants them — but `TerrainFixture` (ADR-0218, the sanctioned
	# lattice seam) is also a map node by the same duck typing, satisfying
	# `ScenarioVM._lattice()` and `procedural_map_path`, and it composes no
	# materials and resolves no sky gradient. It has terrain and nothing to tint.
	#
	# Without this the call below raises "Nonexistent function 'map_materials'",
	# and a GDScript error ABORTS ITS ENCLOSING FUNCTION — so the caller's whole
	# `_ready` stops, silently, several statements before it did anything. The
	# null check above already says this function's contract is "wire what is
	# wireable"; this says the other half of it.
	if not map_composer.has_method("map_materials"):
		return

	# Tint: every material built so far, then every one built later. #1224 merged
	# `MapTintOverlay` into `TintedSurfaces` as the reserved `SURFACE_MAP` token, so the
	# map is ONE surface holding MANY materials rather than a second registry.
	for material in map_composer.map_materials():
		TintedSurfaces.register_surface(TintedSurfaces.SURFACE_MAP, material)
	if not map_composer.map_material_created.is_connected(_register_map_material):
		map_composer.map_material_created.connect(_register_map_material)

	# Sky gradient: the resolved one if there is one, then every later map's.
	var gradient: Array[Color] = map_composer.map_gradient()
	if not gradient.is_empty():
		ScreenEffectOverlay.set_default_gradient(gradient[0], gradient[1])
	if not map_composer.map_gradient_resolved.is_connected(ScreenEffectOverlay.set_default_gradient):
		map_composer.map_gradient_resolved.connect(ScreenEffectOverlay.set_default_gradient)


## Wire the tile cursor's player-driven step to its `Audio` cue. Call it from the
## scene root that OWNS the cursor — the four that build a
## `CursorRig` are the same four (`GPUArena`, `EffectViewerScene`,
## `FireCastReproScene`, `NavigatorMain`). A cursor handed onward from one of
## those (`FormationMapHost.bind_map`, `FormationDetailTransition.mount_over_map`)
## is already wired by its owner and must not be wired twice.
static func wire_cursor(rig: CursorRig) -> void:
	if rig == null:
		return
	if not rig.cursor_stepped.is_connected(_play_cursor_cue):
		rig.cursor_stepped.connect(_play_cursor_cue)


## The signal carries the MATERIAL and the merged verb takes the TOKEN FIRST
## (#1224), so the connection cannot be `register_surface` itself the way
## `register_material` was. A static adapter is the shape this file already uses for
## exactly this — see `_play_cursor_cue` below — and it keeps the argument order
## readable instead of hiding it in a `bind`.
static func _register_map_material(material: ShaderMaterial) -> void:
	TintedSurfaces.register_surface(TintedSurfaces.SURFACE_MAP, material)


## The cue name is HOST vocabulary — `OpeningMenu.gd` plays the same one for a
## menu selection that has nothing to do with the battlefield, which is the
## evidence that it never belonged inside the addon.
static func _play_cursor_cue(_grid_pos: Vector2i) -> void:
	SfxRouter.play_cue("ui.cursor_move")
