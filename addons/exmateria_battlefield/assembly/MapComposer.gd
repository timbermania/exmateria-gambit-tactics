@tool
extends Node3D

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const TunePort = ExMateriaPlatform.TunePort

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const ColorRecipe = ExMateriaSchema.ColorRecipe
const ColorStack = ExMateriaSchema.ColorStack

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const BattlefieldContent = preload("res://addons/exmateria_battlefield/install/BattlefieldContent.gd")
const Doodad = preload("res://addons/exmateria_battlefield/doodad/Doodad.gd")
const DoodadLibrary = preload("res://addons/exmateria_battlefield/doodad/DoodadLibrary.gd")
const DynamicGeometryBuilder = preload("res://addons/exmateria_battlefield/terrain/DynamicGeometryBuilder.gd")
const DynamicTerrainBuilder = preload("res://addons/exmateria_battlefield/terrain/DynamicTerrainBuilder.gd")
const IndexedAtlasDilator = preload("res://addons/exmateria_battlefield/texturing/IndexedAtlasDilator.gd")
const Lattice = preload("res://addons/exmateria_battlefield/lattice/Lattice.gd")
const MapStateSelector = preload("res://addons/exmateria_battlefield/assembly/MapStateSelector.gd")
const MapTextureAnimator = preload("res://addons/exmateria_battlefield/texturing/MapTextureAnimator.gd")
const PaletteTextureGenerator = preload("res://addons/exmateria_battlefield/texturing/PaletteTextureGenerator.gd")
const TileHighlights = preload("res://addons/exmateria_battlefield/overlay/TileHighlights.gd")
const VisualGeometryIndex = preload("res://addons/exmateria_battlefield/terrain/VisualGeometryIndex.gd")


const MapConstants = preload("res://addons/exmateria_battlefield/lattice/MapConstants.gd")
# The tile store has no `class_name` (ADR-0192 dec. 4) — it is `preload`ed by the
# three addon files that build, fill or wrap it, and named by nothing outside.
const TerrainIndexStore = preload("res://addons/exmateria_battlefield/lattice/TerrainIndex.gd")
const SceneTreeManager = preload("res://addons/exmateria_battlefield/assembly/SceneTreeManager.gd")

## Dynamic procedural map composer with doodad placement support.
##
## Orchestrates doodad placement and removal by coordinating specialized modules:
## - DynamicGeometryBuilder: Builds visual geometry meshes
## - DynamicTerrainBuilder: Builds terrain tile nodes
## - SceneTreeManager: Manages tile nodes in scene tree
## - Animation updates: Shader uniforms for water/palette every frame
##
## This class focuses on high-level orchestration and provides a clean API
## for dynamic map composition at runtime.
##
## Features:
## - Dynamic doodad placement at runtime
## - Doodad removal with soft-deletion
## - Mesh rebuilding after changes
## - Tile-based terrain with collision
## Vault: [[Color Tint Luma Modes]]
## Vault: [[Event Opcode Catalog]]
## Vault: [[Map Animation Systems]]
## Vault: [[Map Darkness Opcode]]
## Vault: [[Map State Selection]]

# Signals for tile lifecycle management
signal map_cleared()  # Emitted BEFORE clearing tiles (listeners should cleanup)
signal map_loaded(map_name: String)  # Emitted AFTER new map is ready

## The two outputs #589 inverted, published from the composer rather than from
## the file that computes them, because the composer is the stable subscription
## point: `dynamic_geo_builder` is REPLACED on every `_build_map`, so anything
## connected to the builder directly would silently drop on the next map change.
##
## `map_material_created` is forwarded verbatim from the builder;
## `map_gradient_resolved` is this file's own. Both have a replay half
## (`map_materials()`, `map_gradient()`) for the subscriber that arrives after
## composition — which is every scene root, since both are produced inside
## `_build_map`. `BattlefieldWiring.wire_map` uses both halves.
signal map_material_created(material: ShaderMaterial)
signal map_gradient_resolved(top: Color, bottom: Color)
# When true, _ready() builds the default map itself. GPUArena.tscn sets this
# false so the scene drives the first (scenario) load — no MAP042-then-reload
# flash (ADR-0030). Default true preserves the four other scenes that embed
# MapComposer. (Setter required: @tool @export properties must have one.)
@export var auto_build_on_ready := true:
	set(value):
		if auto_build_on_ready == value:
			return
		auto_build_on_ready = value

# Public properties (exposed for gameplay systems)
## THE PORT (ADR-0118 dec. 2, ADR-0164 dec. 1). The one handle a host outside this
## addon may take off the map, and the only member of this class any of them names.
## Consumers annotate `var lattice: Lattice = map.lattice` — one untyped step at the
## seam, typed from there on, which is the clean form ADR-0192 dec. 3 fixes because
## criterion 1 forbids publishing `MapComposer`, so `map` can never be typed.
## Built ONCE, at declaration, and REBOUND on every map load rather than replaced —
## see `Lattice._bind`. A consumer takes this handle at boot and keeps it across every
## `change_map`; replacing the object would leave it answering for the old map.
var lattice: Lattice = Lattice.new()

## THE HIGHLIGHT PUBLISH (ADR-0164 dec. 1). Same lifetime rule as `lattice`: built
## once, rebound per map load, so a host that took it at boot keeps painting the map
## it is looking at.
var highlights: TileHighlights = TileHighlights.new()

## The unpublished store. Underscored because a host that reached it would be
## holding `Tile` nodes again — the exact shape `check_lattice_ports.py`'s fetch arm
## exists to catch, and the reason ADR-0192 dec. 3 counts a FETCH and not just a call.
var _terrain_index: TerrainIndexStore
var visual_index: VisualGeometryIndex
var geometry_mesh: MeshInstance3D
var is_built: bool = false

# Dynamic builders
var dynamic_geo_builder: DynamicGeometryBuilder
var dynamic_terrain_builder: DynamicTerrainBuilder

# Render tunables are bound once, from whichever map entry point (_build_map or
# change_map) runs first. The F3 panels that VIEW them are mounted host-side by
# `MapDebugPanels` (#555) — this system names neither them nor DebugOverlay.
var _render_setup_done: bool = false

# The background gradient resolved from the manifest (#589). Held rather than
# pushed: `ScreenEffectOverlay.set_default_gradient` was this system's only
# `Effects` reach, and it had exactly ONE caller in the tree, so there is no
# second consumer to keep happy. `_gradient_resolved` is what stops
# `BattlefieldWiring` replaying the FALLBACK blue over a host that has not
# composed a map yet — "no gradient" and "the fallback gradient" are different
# facts and only the second one is worth pushing.
var _gradient_top: Color = Color(0.1, 0.15, 0.3)
var _gradient_bottom: Color = Color(0.3, 0.5, 0.7)
var _gradient_resolved: bool = false

# The un-dilated source atlas Image, captured at load. Atlas edge-padding (dilation) is
# always re-applied from THIS original when the passes tunable changes, so a live scrub
# doesn't compound (dilating an already-dilated image drifts). null if not CPU-readable.
var _indexed_atlas_src: Image = null

# Cache of the last dilated atlas so re-applying on every mesh build is cheap: we only
# re-run the dilation when the source image or the passes count actually changes.
var _dilated_atlas_tex: Texture2D = null
var _dilated_atlas_src: Image = null
var _dilated_atlas_passes: int = -1
var doodad_library: DoodadLibrary

# Scene tree management
var scene_tree_manager: SceneTreeManager
var palette_texture: Texture2D  # Can be ImageTexture or CompressedTexture2D (from PNG)
# Per-state indexed atlas (texture_<hash>.tga) selected by _apply_selected_state;
# null = use the default base_doodad.texture (texture_indexed.tga). Reset each load.
var state_texture: Texture2D
var manifest_data: Dictionary

# Field-object texture animator (event-script {55} Use Field Object). Lazily set
# up on the first play_texture_animation() call so non-scenario maps pay nothing.
var _texture_animator: MapTextureAnimator = null


func _ready():
	if auto_build_on_ready and not is_built:
		_build_map()


func _process(_delta: float):
	if not is_built or not geometry_mesh:
		return
	_update_animation_time()
	if _texture_animator and _texture_animator.has_active():
		_texture_animator.tick(_delta)


## Play map texture-animation slot `id` (event-script {55} Use Field Object).
## The slot index IS the Field Object ID. Lazily clones the indexed atlas into a
## mutable texture on first use and repoints the map materials at it.
func play_texture_animation(id: int) -> void:
	if not _ensure_texture_animator():
		return
	_texture_animator.play(id)


## Whether field-object texture animation `id` is still playing — the completion
## signal {57} Wait Field Object barriers on.
func is_animation_active(id: int) -> bool:
	return _texture_animator != null and _texture_animator.is_active(id)


func _ensure_texture_animator() -> bool:
	if _texture_animator and _texture_animator.is_ready():
		return true
	if dynamic_geo_builder == null or geometry_mesh == null:
		push_warning("[MapComposer] play_texture_animation before map built")
		return false
	var slots: Array = []
	var anims: Dictionary = manifest_data.get("animations", {})
	slots = anims.get("texture_animations", [])
	if slots.is_empty():
		push_warning("[MapComposer] map '%s' has no texture_animations (stale export?)" % name)
		return false
	_texture_animator = MapTextureAnimator.new()
	var work_tex := _texture_animator.setup(
		slots, dynamic_geo_builder.indexed_texture, dynamic_geo_builder.palette_texture)
	if work_tex == null:
		_texture_animator = null
		return false
	# Repoint every map material at the mutable atlas so UV-kind blits become
	# visible.
	dynamic_geo_builder.swap_indexed_texture(work_tex)
	# And at the mutable palette, so palette-kind blits (the Balbanes death fade,
	# {55} mode 0x0D) recolor the map. Null work texture = map has no palette to
	# animate; UV slots still work.
	var pal_work_tex := _texture_animator.get_work_palette_texture()
	if pal_work_tex != null:
		dynamic_geo_builder.swap_palette_texture(pal_work_tex)
		# Keep our own reference on the SAME object the geometry now samples, so a
		# later {66} Commit Palette / {33} field-tint (commit_field_tint reads and
		# updates self.palette_texture) lands on the live texture instead of an
		# orphaned copy the materials no longer reference.
		palette_texture = pal_work_tex
	return true


func _build_map():
	_clear_children()
	doodad_library = DoodadLibrary.new()

	if not _load_and_place_map():
		return

	_ensure_render_setup()


## Load a map doodad, create builders, and place it as the base map.
##
## `weather_raw` / `is_night` / `arrangement` select which GNS map state's
## environment (sky gradient + ambient + lights + palette) to render (ADR-0056).
## Defaults reproduce the historic Primary/Day/None load for the four scenes that
## embed MapComposer without a scenario.
func _load_and_place_map(map_name: String = "MAP042", weather_raw: int = 0,
		is_night: int = 0, arrangement: int = 0) -> bool:
	_terrain_index = TerrainIndexStore.new()
	lattice._bind(_terrain_index)
	highlights._bind(_terrain_index)
	visual_index = VisualGeometryIndex.new()
	state_texture = null

	var base_doodad = _load_base_map(doodad_library, map_name)
	if not base_doodad:
		return false

	palette_texture = base_doodad.palette_texture
	manifest_data = _load_scene_manifest(map_name)
	if base_doodad.manifest.has("animations"):
		manifest_data["animations"] = base_doodad.manifest["animations"]

	# Select-at-load: fold the chosen map state's environment into manifest_data /
	# palette_texture BEFORE building materials, so the initial pass renders the
	# right sky — no default-then-swap flash (ADR-0056).
	_apply_selected_state(map_name, weather_raw, is_night, arrangement)

	# The per-state texture (night/weather terrain atlas) overrides the default
	# base_doodad.texture when _apply_selected_state selected one (ADR-0056).
	var indexed_atlas: Texture2D = state_texture if state_texture != null else base_doodad.texture
	# Capture the CPU image so atlas edge-padding can be (re)applied from the original. The
	# dilated texture is installed via _apply_atlas_dilate (bound to map.atlas_dilate_passes)
	# once the materials exist; the mesh is built with the raw atlas for one pre-display pass.
	_indexed_atlas_src = indexed_atlas.get_image() if indexed_atlas else null
	if _indexed_atlas_src == null:
		push_warning("[MapComposer] indexed atlas not CPU-readable — atlas edge-padding (map.atlas_dilate_passes) disabled")

	dynamic_geo_builder = DynamicGeometryBuilder.new()
	# Forward, so a subscriber binds ONCE to the composer and survives every
	# rebuild that replaces the builder underneath it.
	dynamic_geo_builder.map_material_created.connect(map_material_created.emit)
	dynamic_geo_builder.initialize(
		visual_index,
		palette_texture,
		indexed_atlas,
		load("res://addons/exmateria_battlefield/texturing/indexed_color.gdshader"),
		manifest_data
	)

	dynamic_terrain_builder = DynamicTerrainBuilder.new()
	dynamic_terrain_builder.initialize(_terrain_index)

	scene_tree_manager = SceneTreeManager.new()
	scene_tree_manager.initialize(self)

	dynamic_geo_builder.map_bounds = base_doodad.get_bounds()

	_place_doodad_internal(base_doodad, "base", Vector2i(0, 0))

	if not Engine.is_editor_hint():
		_apply_gradient_from_manifest(manifest_data)

	is_built = true
	return true


## Internal: Place doodad with all the logic.
func _place_doodad_internal(doodad: Doodad, doodad_id: String, position: Vector2i) -> void:
	# Calculate bounds
	var doodad_bounds = doodad.get_bounds()
	var world_bounds = Rect2i(
		position.x + doodad_bounds.position.x,
		position.y + doodad_bounds.position.y,
		doodad_bounds.size.x,
		doodad_bounds.size.y
	)


	# Remove existing geometry in bounds (soft-delete)
	var replaced_triangle_ids = dynamic_geo_builder.remove_geometry_in_bounds(world_bounds)

	# Remove existing terrain tiles in bounds (keep them for restoration)
	var removed_tiles = dynamic_terrain_builder.remove_terrain_in_bounds(world_bounds)
	scene_tree_manager.detach_tiles(removed_tiles)


	# Add new geometry
	dynamic_geo_builder.add_geometry(doodad.geometry, doodad_id, position)

	# Add new terrain tiles
	var new_tiles = dynamic_terrain_builder.add_terrain(doodad.terrain, doodad_id, position)
	scene_tree_manager.add_tiles(new_tiles)

	# Rebuild geometry mesh
	_rebuild_geometry_mesh()


## Public method to rebuild geometry mesh (for debug panel use).
func rebuild_map() -> void:
	_rebuild_geometry_mesh()


## Rebuild geometry mesh from active triangles.
func _rebuild_geometry_mesh() -> void:
	# Remove old mesh
	if geometry_mesh and geometry_mesh.is_inside_tree():
		remove_child(geometry_mesh)
		geometry_mesh.queue_free()

	# Build new mesh
	geometry_mesh = dynamic_geo_builder.rebuild_mesh()
	geometry_mesh.name = "GeometryMesh"
	add_child(geometry_mesh)

	# Re-push the render tunables onto the fresh mesh (new surface materials would otherwise
	# carry the shader/atlas defaults until the next scrub). Atlas dilation especially must
	# re-apply per load — the Tune.bind immediate-apply only fires once per session.
	_apply_uv_snap()
	_apply_atlas_dilate()


func _clear_children():
	# Notify observers before clearing (allows cleanup of tile references)
	map_cleared.emit()

	# Clear terrain index so stale external references return null instead of freed tiles.
	# `lattice` is NOT dropped: it wraps this same store, so a host holding the port
	# keeps answering null/[] across a rebuild instead of holding a freed object.
	if _terrain_index:
		_terrain_index.clear()

	if scene_tree_manager:
		scene_tree_manager.clear_all()

	for child in get_children():
		remove_child(child)
		child.queue_free()
	is_built = false


# `get_tile` / `get_all_tiles` USED TO BE HERE, and their absence is ADR-0170 dec. 1.
# Both were three-line null-guarded forwarders to the store — not, as ADR-0164 dec. 3
# and #567 both called them, a second implementation of the same query. A forwarder
# cannot close the door by construction: while the query lives on this NODE its
# receiver is whatever `$ProceduralMap` yields, which infers `Node`, so every
# consumer keeps an untyped handle and the register never moves. It also passes
# criterion 1 by being invisible to it — there is no annotation to find — which is
# ADR-0164 dec. 4(b)'s hole in a third dress. Ask `map.lattice` instead; the null
# guard the forwarder carried lives in `Lattice` itself, which answers null/[] before
# the map builds.


## Change to a different map at runtime.
##
## Clears the current map and loads the new one.
##
## Args:
##     map_name: Name of the map to load (e.g., "MAP001", "MAP022")
##
## Returns:
##     true if map loaded successfully, false otherwise
func change_map(map_name: String, weather_raw: int = 0, is_night: int = 0,
		arrangement: int = 0) -> bool:
	_clear_children()
	if not doodad_library:
		doodad_library = DoodadLibrary.new()

	if not _load_and_place_map(map_name, weather_raw, is_night, arrangement):
		push_error("Failed to load map: %s" % map_name)
		return false

	# change_map is the Effect Viewer / scenario entry point (distinct from the _ready
	# auto-build). Bind the render tunables here too so the map.uv_clamp_* live-scrub
	# works in those scenes; the once-guard inside prevents a double bind when a scene
	# uses both paths.
	_ensure_render_setup()

	map_loaded.emit(map_name)
	return true


## Get list of available maps.
##
## Returns:
##     Array of map names that can be loaded
func get_available_maps() -> Array[String]:
	if not doodad_library:
		doodad_library = DoodadLibrary.new()
	return doodad_library.list_doodads()


## Fold the selected map state's environment into manifest_data + palette_texture.
##
## Picks the `states[]` entry matching (weather_raw, is_night, arrangement) via
## MapStateSelector and overwrites the default `lighting` (sky gradient + ambient
## + directional lights) and — when the state ships its own palette — the map
## palette texture. A single-state map (no `states[]`) or a benign selector miss
## leaves the default environment untouched.
func _apply_selected_state(map_name: String, weather_raw: int, is_night: int,
		arrangement: int) -> void:
	var states: Array = manifest_data.get("states", [])
	if states.is_empty():
		return  # single-state map — the default lighting is already loaded.

	var state := MapStateSelector.select(states, weather_raw, is_night, arrangement)
	if state.is_empty():
		return  # selector already warned (missing arrangement); keep default env.

	if state.has("lighting"):
		manifest_data["lighting"] = state["lighting"]

	var palette_file = state.get("palette_file")
	if palette_file is String and palette_file != "":
		var tex := _load_state_palette(map_name, palette_file)
		if tex != null:
			palette_texture = tex

	# Texture is orthogonal to palette: a night/weather state can ship its own
	# terrain atlas (texture_<hash>.tga), its own palette, or both.
	var texture_file = state.get("texture_file")
	if texture_file is String and texture_file != "":
		var atlas := _load_state_texture(map_name, texture_file)
		if atlas != null:
			state_texture = atlas

	print("[MapComposer] state weather_raw=%d night=%d arr=%d → palette=%s texture=%s"
		% [weather_raw, is_night, arrangement, str(palette_file), str(texture_file)])


## Load a per-state palette sidecar (palettes_<hash>.json) as a palette texture.
func _load_state_palette(map_name: String, palette_file: String) -> Texture2D:
	var path = BattlefieldContent.maps_dir() + map_name + "/" + palette_file
	if not FileAccess.file_exists(path):
		push_warning("[MapComposer] palette sidecar missing: %s (stale export?)" % path)
		return null
	var data := _load_json(path)
	if data.is_empty():
		return null
	return PaletteTextureGenerator.create_palette_texture(data)


## Load a per-state texture sidecar (texture_<hash>.tga) as the indexed atlas.
##
## Mirrors _load_state_palette but for the orthogonal texture layer. The sidecar
## is a Godot-imported .tga, so this loads the imported resource (gated on
## ResourceLoader.exists, matching DoodadLibrary); a missing/un-imported sidecar
## warns and returns null so the default base texture is kept.
func _load_state_texture(map_name: String, texture_file: String) -> Texture2D:
	var path = BattlefieldContent.maps_dir() + map_name + "/" + texture_file
	if not ResourceLoader.exists(path):
		push_warning("[MapComposer] texture sidecar missing/un-imported: %s (stale export? run godot --import)" % path)
		return null
	return load(path)


## Apply background gradient from manifest lighting data.
##
## Reads the gradient colors from the manifest and applies them to the
## ScreenEffectOverlay. Falls back to default blue gradient if no gradient
## data is present.
func _apply_gradient_from_manifest(manifest: Dictionary) -> void:
	var top_color = Color(0.1, 0.15, 0.3)   # Fallback dark blue
	var bottom_color = Color(0.3, 0.5, 0.7)  # Fallback light blue
	var source = "fallback"

	if manifest.has("lighting") and manifest["lighting"].has("gradient"):
		var gradient = manifest["lighting"]["gradient"]
		if gradient.has("top"):
			top_color = Color(
				gradient["top"]["r"] / 255.0,
				gradient["top"]["g"] / 255.0,
				gradient["top"]["b"] / 255.0
			)
			source = "manifest"
		if gradient.has("bottom"):
			bottom_color = Color(
				gradient["bottom"]["r"] / 255.0,
				gradient["bottom"]["g"] / 255.0,
				gradient["bottom"]["b"] / 255.0
			)

	print("[Gradient] Applying %s gradient: top=%s bottom=%s" % [source, top_color, bottom_color])
	_gradient_top = top_color
	_gradient_bottom = bottom_color
	_gradient_resolved = true
	map_gradient_resolved.emit(top_color, bottom_color)


## Every map `ShaderMaterial` built so far — the replay half of
## `map_material_created`. Empty before the first `_build_map`.
func map_materials() -> Array[ShaderMaterial]:
	if dynamic_geo_builder == null:
		return []
	return dynamic_geo_builder.map_materials()


## The manifest background gradient as `[top, bottom]`, or an EMPTY array if no
## map has resolved one yet. Empty is the honest answer: see `_gradient_resolved`.
func map_gradient() -> Array[Color]:
	if not _gradient_resolved:
		return []
	var out: Array[Color] = [_gradient_top, _gradient_bottom]
	return out


## Bind the render tunables exactly once, regardless of which map entry point
## (_build_map auto-build or change_map) loaded first.
##
## This used to mount the two F3 panels as well. It does not any more (#555): the panels
## are `src/debug/` classes, and a production owner that owns the tunable data AND
## instantiates its view breaks the very rule (ADR-0068 R1) cited below to justify
## keeping the data here. `MapDebugPanels.register_map_panels(map)` now mounts them from
## the host scene, after the map is composed — the same moment this method used to fire.
func _ensure_render_setup() -> void:
	if _render_setup_done or Engine.is_editor_hint():
		return
	_render_setup_done = true
	_bind_render_tunables()


# Map render tunables — OWNED HERE (ADR-0068 R1), not in the debug panel: MapComposer is the
# production owner that binds, pull-reads, and pushes these to the shader. The slug names, the
# scrubbable `static var` defaults (materialize's home — the R6 follower rewrites the literal
# initializer), and the panel hints all live on the owner. MapRenderDebugPanel is a pure VIEW:
# it names these slugs and reads default+hint back from the Tune registry. All snap defaults are
# identity (centroid 0 / perimeter 1) so the snap is off until dialed; offx/offy were
# materialized to 0.5 (the texel-center that closes the boulder neighbor-bleed seam).
const _UV_SNAP_OFFX_SLUG := "map.uv_snap_offx"
const _UV_SNAP_OFFY_SLUG := "map.uv_snap_offy"
const _UV_SNAP_CENTROID_SLUG := "map.uv_snap_centroid"
const _UV_SNAP_PERIMETER_SLUG := "map.uv_snap_perimeter"
static var _uv_snap_offx_default := 0.5
static var _uv_snap_offy_default := 0.5
static var _uv_snap_centroid_default := 0.0
static var _uv_snap_perimeter_default := 1.0
const _UV_SNAP_OFF_HINT := {"min": -2.0, "max": 2.0, "step": 0.05}
const _UV_SNAP_CENTROID_HINT := {"min": 0.0, "max": 4.0, "step": 0.05}
const _UV_SNAP_PERIMETER_HINT := {"min": 0.25, "max": 8.0, "step": 0.25}
const _ATLAS_DILATE_PASSES_SLUG := "map.atlas_dilate_passes"
# Default OFF: 1 pass closed the cyan seam holes, but the dilator can't tell a 1px seam-crack
# from legitimate interior dark content — index 0 is dual-purpose (transparent AND the black
# that fills most dark textures), so it floods dark roof/ceiling faces brown (Orbonne MAP062
# regression). Machinery stays for F3 scrub; re-enable per-map once dilation is patch-aware.
static var _atlas_dilate_passes_default := 0
const _ATLAS_DILATE_PASSES_HINT := {"min": 0, "max": 4, "step": 1}


## Register the map render slugs at class load (ADR-0068 R2), so a runtime map bake
## (_apply_uv_snap / _apply_atlas_dilate pull-read via get_value) always resolves them —
## even before an instance's _bind_render_tunables runs (mesh rebuild can precede it).
## Editor-guarded (Tune is a non-@tool placeholder and MapComposer is @tool); the
## per-instance on_update PUSH stays in _bind_render_tunables.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## The map render binds, split out from _static_init as this owner's named registration entry
## point (ADR-0173): _static_init calls it at class load — the ONLY thing that does — and the
## guards call it to read back which slugs this owner binds. Editor-guarded by the caller. Each bind
## carries the panel hint (meta) so the pure-view panel reads min/max/step from the registry.
## The default is a bare `_x` static-var ref (a class can't qualify its own class_name); the
## R6 materialize follower resolves it in this file (owner==binder) to rewrite the literal.
static func register_tunables() -> void:
	TunePort.bind(_UV_SNAP_OFFX_SLUG, _uv_snap_offx_default, _UV_SNAP_OFF_HINT)
	TunePort.bind(_UV_SNAP_OFFY_SLUG, _uv_snap_offy_default, _UV_SNAP_OFF_HINT)
	TunePort.bind(_UV_SNAP_CENTROID_SLUG, _uv_snap_centroid_default, _UV_SNAP_CENTROID_HINT)
	TunePort.bind(_UV_SNAP_PERIMETER_SLUG, _uv_snap_perimeter_default, _UV_SNAP_PERIMETER_HINT)
	TunePort.bind(_ATLAS_DILATE_PASSES_SLUG, _atlas_dilate_passes_default, _ATLAS_DILATE_PASSES_HINT)


## Push the indexed_color render tunables (ADR-0068 decision 12): MapComposer OWNS the
## values and pushes each onto every live map material, so a committed override applies at
## boot in any scene (not only while the debug panel is open). The `on_update` applies once
## immediately (mesh already built) and again on every scrub. Registration is the `bind` in
## register_tunables (the single static-var home, at class load); here we add ONLY the
## per-instance push (ADR-0068 R3 — bind separate from update). Using on_update, not
## bind_update, avoids a rival re-bind default: bind_update re-declared the literal here
## (inline 0.0/1.0), a second materialize home that could drift from the static var.
func _bind_render_tunables() -> void:
	if Engine.is_editor_hint():
		return
	for slug in [_UV_SNAP_OFFX_SLUG, _UV_SNAP_OFFY_SLUG, _UV_SNAP_CENTROID_SLUG, _UV_SNAP_PERIMETER_SLUG]:
		TunePort.on_update(self, slug, func(_v): _apply_uv_snap())
	TunePort.on_update(self, _ATLAS_DILATE_PASSES_SLUG, func(_v): _apply_atlas_dilate())
	# `map.water_waves` is OWNED by DynamicGeometryBuilder (it decides per surface type
	# which materials may wave, and holds the surface-keyed cache that makes the water
	# subset addressable). MapComposer supplies only the node lifetime the `on_update`
	# hook needs — the same split as `_apply_uv_snap`, which also loops the builder's
	# materials. The bind itself is the builder's `_static_init`, not here.
	TunePort.on_update(self, DynamicGeometryBuilder._WATER_WAVES_SLUG, func(_v): _apply_water_waves())


## Install the atlas dilated to the current `map.atlas_dilate_passes` (edge-padding seam
## fix) on every live map material. Called on every mesh build AND on tunable change, so a
## fresh map load always gets padded (not just the first, once-bound one). The dilation is
## re-derived from the un-dilated source — cached, so repeat calls with the same source +
## passes only re-swap, never re-dilate.
## Re-push `enable_waves` after a `map.water_waves` scrub. Delegates: only the builder
## knows which of its materials are water.
func _apply_water_waves() -> void:
	if dynamic_geo_builder == null:
		return
	dynamic_geo_builder.apply_water_waves()


func _apply_atlas_dilate() -> void:
	if not dynamic_geo_builder or _indexed_atlas_src == null:
		return
	# Pull-read the bound value (bound by _bind_render_tunables); editor-fallback since Tune is
	# a non-@tool placeholder in-editor and the bind is editor-guarded (ADR-0068 R5).
	var passes: int = _atlas_dilate_passes_default if Engine.is_editor_hint() \
		else TunePort.get_value(_ATLAS_DILATE_PASSES_SLUG, _atlas_dilate_passes_default)
	if _dilated_atlas_tex == null or _dilated_atlas_src != _indexed_atlas_src or _dilated_atlas_passes != passes:
		var img: Image = _indexed_atlas_src if passes <= 0 else IndexedAtlasDilator.dilate(_indexed_atlas_src, passes)
		_dilated_atlas_tex = ImageTexture.create_from_image(img)
		_dilated_atlas_src = _indexed_atlas_src
		_dilated_atlas_passes = passes
	# While the texture animator owns the material's indexed_texture (it swapped in
	# its own mutable work canvas at play_texture_animation), a static swap here would
	# repoint the materials off that canvas and freeze the animation — both paths write
	# the same `indexed_texture` uniform. Re-seed the animator's base instead so the
	# edge-padding change lands in place; only swap directly when no animation is live.
	if _texture_animator and _texture_animator.is_ready():
		_texture_animator.reseed_indexed_source(_dilated_atlas_tex)
	else:
		dynamic_geo_builder.swap_indexed_texture(_dilated_atlas_tex)


## Push the perimeter-aware UV-snap tunables onto every map material's shader uniforms.
func _apply_uv_snap() -> void:
	if not geometry_mesh:
		return
	var mesh = geometry_mesh.mesh
	if not mesh:
		return
	# Pull-read the bound values (bound by _bind_render_tunables); editor-fallback to the code
	# defaults since Tune is a non-@tool placeholder in-editor and the bind is editor-guarded.
	var editor := Engine.is_editor_hint()
	var offx: float = _uv_snap_offx_default if editor else TunePort.get_value(_UV_SNAP_OFFX_SLUG, _uv_snap_offx_default)
	var offy: float = _uv_snap_offy_default if editor else TunePort.get_value(_UV_SNAP_OFFY_SLUG, _uv_snap_offy_default)
	var centroid: float = _uv_snap_centroid_default if editor else TunePort.get_value(_UV_SNAP_CENTROID_SLUG, _uv_snap_centroid_default)
	var perimeter: float = _uv_snap_perimeter_default if editor else TunePort.get_value(_UV_SNAP_PERIMETER_SLUG, _uv_snap_perimeter_default)
	for i in range(mesh.get_surface_count()):
		var material = mesh.surface_get_material(i)
		if material and material is ShaderMaterial:
			material.set_shader_parameter("uv_snap_offx", offx)
			material.set_shader_parameter("uv_snap_offy", offy)
			material.set_shader_parameter("uv_snap_centroid", centroid)
			material.set_shader_parameter("uv_snap_perimeter", perimeter)


# --- Inlined from MapAnimator ---

## Update animation time for all materials on the geometry mesh.
## Converts milliseconds to "ticks" (frames at PSX NTSC framerate).
func _update_animation_time() -> void:
	var mesh = geometry_mesh.mesh
	if not mesh:
		return
	var time_ms = Time.get_ticks_msec()
	var animation_time = (time_ms / 1000.0) * MapConstants.ANIMATION_TICKS_PER_SECOND
	for i in range(mesh.get_surface_count()):
		var material = mesh.surface_get_material(i)
		if material and material is ShaderMaterial:
			material.set_shader_parameter("animation_time", animation_time)


## ADR-0067 unified path (parallel, flag-gated): mirror the {33} field spec into the
## color-stack uniforms so indexed_color.gdshader can fold it via color_apply. The
## whole field is ONE layer — affine {scale,bias} at progress 1, or a base-source luma
## at progress = the cross-fade weight — byte-exact vs the PSX field math per
## ColorStack.fold's parity oracle. No quantize (luma quantizes internally; affine float).
func set_field_color_stack(scale: Vector3, bias: Vector3, div: int, delta5: Vector3i,
		from_current: bool, mix: float) -> void:
	if not geometry_mesh:
		return
	var mesh = geometry_mesh.mesh
	if not mesh:
		return
	var stack := ColorStack.new()
	if div > 0:
		stack.push_fixed_layer(ColorRecipe.luma(div, delta5, not from_current), mix)
	else:
		stack.push_fixed_layer(ColorRecipe.affine(scale, bias), 1.0)
	for i in range(mesh.get_surface_count()):
		var material = mesh.surface_get_material(i)
		if material and material is ShaderMaterial:
			stack.apply(material, 0)


## Event-script {0x66} Commit Palette — bake the live {33} Color Field field-tint
## into the BASE map palette so it PERSISTS. Handles both field shapes: an affine
## `(scale,bias)` OR a luma (div>0) sepia/grey wash at cross-fade weight `mix`. PSX
## FUN_8008f63c copies the working CLUT strip over the base copy (DAT_80099d76); the
## Godot analogue folds the field recipe into palette_texture. After this call the map
## samples the committed colours, so the caller (ScenarioVM) resets the transient
## field-tint uniform to identity — a later flash's mode-8 restore then lands on the
## committed base, not the raw warm palette (the scenario-3/4/5/6 map-hue bug).
func commit_field_tint(scale: Vector3, bias: Vector3, div: int = 0,
		delta5: Vector3i = Vector3i.ZERO, from_current: bool = false, mix: float = 1.0) -> void:
	if palette_texture == null:
		return
	var baked := bake_field_tint(palette_texture.get_image(), scale, bias, div, delta5, from_current, mix)
	if palette_texture is ImageTexture:
		# Same texture object all materials reference — update-in-place repaints
		# every geometry surface with no re-point needed.
		palette_texture.update(baked)
	else:
		# A CompressedTexture2D (PNG-loaded) has no update(); swap in a mutable
		# ImageTexture and re-point every geometry surface material at it.
		palette_texture = ImageTexture.create_from_image(baked)
		if geometry_mesh and geometry_mesh.mesh:
			var mesh = geometry_mesh.mesh
			for i in range(mesh.get_surface_count()):
				var material = mesh.surface_get_material(i)
				if material and material is ShaderMaterial:
					material.set_shader_parameter("palette_texture", palette_texture)


## Fold a {33} Color Field field-tint affine into a copy of a palette image and
## return the baked copy — the pure core of {0x66} Commit Palette. Each palette
## entry is a BGR555 CLUT colour (5 bits/channel); the PSX committer rewrites it
## `entry → clamp(entry*scale + bias, 0, 31)` in 5-bit space. This now delegates to
## ColorStack.commit_bake (the unified fold, ADR-0067) with a single affine layer, so
## the {66} commit shares the one colour model — and generalizes to luma commits for
## free. Byte-exact vs the old inline bake (guarded by ScenarioCommitPaletteTest).
static func bake_field_tint(src: Image, scale: Vector3, bias: Vector3, div: int = 0,
		delta5: Vector3i = Vector3i.ZERO, from_current: bool = false, mix: float = 1.0) -> Image:
	if src == null:
		return null
	var stack := ColorStack.new()
	if div > 0:
		# A LUMA field (modes 2/3/6/7) commits its sepia/grey wash — the layer folds at
		# progress = mix, exactly the shape set_field_color_stack broadcasts live.
		stack.push_fixed_layer(ColorRecipe.luma(div, delta5, not from_current), mix)
	else:
		stack.push_fixed_layer(ColorRecipe.affine(scale, bias), 1.0)
	return stack.commit_bake(src, 0)


# --- Inlined from MapResourceLoader ---

# ⚠️ Was `const _MAPS_PATH: String = "res://assets/…"`. `maps/` is the one gitignored
# target — a symlink into the asset hub — so the addon can never ship it and the LITERAL
# was the defect (ADR-0202 dec. 5 Class B). Composed from the host-injected content root
# now; see `BattlefieldContent`.


func _load_scene_manifest(map_name: String = "MAP042") -> Dictionary:
	var path = BattlefieldContent.maps_dir() + map_name + "/scene_manifest.json"
	if FileAccess.file_exists(path):
		return _load_json(path)
	push_error("MapComposer: scene_manifest.json not found for '%s'" % map_name)
	return {}


func _load_base_map(p_doodad_library: DoodadLibrary, map_name: String = "MAP042") -> Doodad:
	var base_doodad = p_doodad_library.load_doodad(map_name)
	if not base_doodad or not base_doodad.is_valid():
		push_error("Failed to load %s" % map_name)
		return null
	return base_doodad


func _load_json(file_path: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("MapComposer: Could not open %s" % file_path)
		return {}
	var text = file.get_as_text()
	file.close()
	var data = JSON.parse_string(text)
	if data == null:
		push_error("MapComposer: Failed to parse %s" % file_path)
		return {}
	return data
