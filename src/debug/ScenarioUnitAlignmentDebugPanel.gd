class_name ScenarioUnitAlignmentDebugPanel
extends BaseDebugPanel
## F3 rig for scenario-unit render ALIGNMENT — one surface for every knob that
## moves a unit sprite relative to its tile, grouped by the axis it actually
## affects (see docs/adr/0036 PAR, 0044 sprite width, and the unit shader seam):
##
##   SPACING (feet-to-feet gap between units):
##     - pixel_aspect ....... the ONLY anchor-gap knob. anchor.x scales by pixel_aspect;
##                       widening two units' gap is purely this + world position.
##   WIDTH (sprite footprint, symmetric about the feet — does NOT move the gap):
##     - unit_stretch  billboard width multiplier layered on the pixel_aspect anchor.
##     - mesh scale ...... the UnitMesh basis scale (Unit.tscn = 8).
##   VERTICAL / PIVOT:
##     - mesh Y-lift ..... UnitMesh.position.y (Unit.tscn = 0.05).
##     - shared_loc_offset sprite-layer centering (SpriteLayerManager = 27,26).
##
## Plus a tile-GRID overlay (MapGridOverlay) so you can see how centered each
## unit's feet anchor sits on its tile, and a Print button that dumps the live
## per-unit feet-vs-tile-center offset (the PAR-independent centering ground truth).
##
## The globals (pixel_aspect / unit_stretch) also live in the Display panel; they
## are duplicated here, labeled by EFFECT, so this is a one-stop alignment rig.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice
const MapGridOverlay = ExMateriaBattlefield.MapGridOverlay

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const TerrainCell = ExMateriaSchema.TerrainCell


const TuneField = preload("res://src/debug/TuneField.gd")
# No affordance-hint constants live here anymore: this panel is a VIEW (ADR-0068 decision
# 12 / R5). Each render.* slug's literal AND its min/max/step hint are declared at the
# OWNER's bind — pixel_aspect/unit_stretch on PSXDisplay, mesh_scale/y_lift/loc_offset on
# Unit._static_init — and the rows below read them from the registry (no default passed).

var _scene_root: Node
var _get_units_func: Callable

var _par_sb: SpinBox
var _unit_stretch_sb: SpinBox
var _scale_sb: SpinBox
var _ylift_sb: SpinBox
var _loc_control: Control  # render.loc_offset is a Vector2 (per-component spinboxes, R6)

var _grid_on := false  # tile grid + center cross OFF by default (opt-in via checkbox)
var _grid: MapGridOverlay


func setup(scene_root: Node, get_units_func: Callable) -> void:
	_scene_root = scene_root
	_get_units_func = get_units_func
	panel_title = "Unit Alignment"
	panel_category = Category.SCENARIO_LOOK
	_build_ui()
	# Grid defaults ON while tuning; build it against the live map once the scene
	# has finished coming up (deferred so ProceduralMap exists), independent of
	# whether the F3 panel is ever shown.
	if _grid_on:
		_rebuild_grid.call_deferred()


## Scenario reloads on click-to-rewind; rebind to the fresh scene + units accessor.
## No knob re-push needed — the render slugs stay registered (boot-time, Unit._static_init)
## and the fresh units re-subscribe their own update at spawn, coalescing the current
## override. The old grid died with the old map — rebuild it against the new map if it was on.
func rebind(scene_root: Node, get_units_func: Callable) -> void:
	_scene_root = scene_root
	_get_units_func = get_units_func
	_grid = null
	if _grid_on:
		_rebuild_grid()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	add_child(vbox)

	add_section_title(vbox, "Spacing — feet-to-feet gap")
	# Every knob is a VIEW row (ADR-0068 decision 12 / R5): no default is passed, so
	# TuneField reads the slug's registered literal + hint + persistence class from the
	# registry — the OWNER's bind is the single source of truth. pixel_aspect/unit_stretch
	# are owned by PSXDisplay (bound at boot, driven into the shader by their setter);
	# mesh_scale/y_lift/loc_offset are owned by Unit (registered in _static_init, applied
	# per-unit by an owner-scoped update). No fan-out, no rival literal: a scrub reaches
	# every unit in THIS scene AND GPUArena via the owner's update, not this panel.
	_par_sb = TuneField.add(vbox, "pixel_aspect (gap)", "render.pixel_aspect") as SpinBox

	add_separator(vbox)
	add_section_title(vbox, "Width — sprite footprint (not the gap)")
	_unit_stretch_sb = TuneField.add(vbox, "unit_stretch", "render.unit_stretch") as SpinBox
	_scale_sb = TuneField.add(vbox, "mesh scale", "render.unit_mesh_scale") as SpinBox

	add_separator(vbox)
	add_section_title(vbox, "Vertical / pivot")
	_ylift_sb = TuneField.add(vbox, "mesh Y-lift", "render.unit_y_lift") as SpinBox
	# loc_offset is ONE Vector2 slug now (R6 — the old x/y pair collapsed), so it is a
	# single per-component row, not two float rows.
	_loc_control = TuneField.add(vbox, "loc_offset (x,y)", "render.loc_offset")

	add_separator(vbox)
	add_section_title(vbox, "Tile grid")
	# The grid-overlay toggle auto-persists (green TuneField, ADR-0068): a view pref you
	# left on comes back next launch. The coalesced value seeds _grid_on so setup()'s
	# deferred rebuild fires when it was persisted on; the toggled side-effect still
	# builds/frees the live overlay.
	var grid_chk := TuneField.add(vbox, "Grid + cross + X,Z labels",
		"scenario_align.show_grid", _grid_on, {}, Tune.Persist.AUTOSAVE) as CheckBox
	_grid_on = grid_chk.button_pressed
	grid_chk.toggled.connect(_on_grid_toggled)

	add_separator(vbox)
	var btn_row := add_button_row(vbox)
	var reset_btn := Button.new()
	reset_btn.text = "Reset defaults"
	reset_btn.pressed.connect(_on_reset)
	btn_row.add_child(reset_btn)
	var print_btn := Button.new()
	print_btn.text = "Print Values"
	print_btn.pressed.connect(_on_print_values)
	btn_row.add_child(print_btn)


func _on_grid_toggled(on: bool) -> void:
	_grid_on = on
	if on:
		_rebuild_grid()
	elif _grid and is_instance_valid(_grid):
		_grid.queue_free()
		_grid = null


func _rebuild_grid() -> void:
	if _grid and is_instance_valid(_grid):
		_grid.queue_free()
	_grid = null
	var map := _get_map()
	if map == null or not ("lattice" in map):
		push_warning("[UnitAlignment] ProceduralMap exposes no lattice; grid skipped")
		return
	var lattice: Lattice = map.lattice
	if lattice == null:
		push_warning("[UnitAlignment] ProceduralMap has not built its lattice yet; grid skipped")
		return
	_grid = MapGridOverlay.new()
	map.add_child(_grid)
	# ADR-0192 dec. 5. This used to be `build_from_tiles` fed by the map's all-tiles
	# query — an `Array[Tile]` fetched OUT of the addon by this `Cutscene` file and
	# handed straight back IN, because `MapGridOverlay` is itself an addon file. The
	# overlay takes the port now and opens the store behind it, which is a back door
	# only addon files may open; the crossing is deleted rather than re-typed.
	# (The old call's spelling is deliberately not written here: `check_lattice_doors`
	# reads RAW text, so quoting it in a comment would keep the door row alive.)
	_grid.build_from_lattice(lattice)


## The map's lattice, or null. One untyped step at the seam (ADR-0192 dec. 3):
## `_get_map()` is a by-NAME scene lookup (`get_node_or_null("ProceduralMap")`), the
## widest spelling of all and one this panel cannot narrow — ADR-0170 dec. 3 flags it
## by name. Everything past this line is typed.
func _lattice_of(map) -> Lattice:
	if map == null or not ("lattice" in map):
		return null
	var lat: Lattice = map.lattice
	return lat


func _get_map() -> Node:
	if _scene_root == null or not is_instance_valid(_scene_root):
		return null
	return _scene_root.get_node_or_null("ProceduralMap")


func _on_reset() -> void:
	# Every knob resets by DROPPING its override (ADR-0068): the coalescing read then falls
	# back to the code default, TuneField resyncs each control + marker, each Unit's update
	# re-applies the default to live units, PSXDisplay re-pushes the globals — all off the
	# one value_changed(slug, null). No rival literal is reintroduced.
	for slug in ["render.pixel_aspect", "render.unit_stretch",
			"render.unit_mesh_scale", "render.unit_y_lift", "render.loc_offset"]:
		Tune.clear(slug)


func _on_print_values() -> void:
	var cam := _scene_root.get_viewport().get_camera_3d() if _scene_root else null
	# PULL-read the live coalesced value (the owner Unit registered these at boot) — the panel
	# is a view and holds no literal of its own.
	var loc: Vector2 = Tune.get_value("render.loc_offset")
	print("")
	print("=".repeat(60))
	print("# Unit Alignment — globals")
	print("pixel_aspect = %.3f   unit_stretch = %.3f" % [PSXDisplay.live_par, PSXDisplay.live_unit_stretch])
	print("mesh_scale = %.2f   mesh_y_lift = %.3f   loc_offset = (%.0f, %.0f)"
		% [Tune.get_value("render.unit_mesh_scale"),
			Tune.get_value("render.unit_y_lift"),
			loc.x, loc.y])
	print("-".repeat(60))
	print("# Per-unit feet-vs-tile-center (world; PAR-independent)")
	if _get_units_func.is_valid():
		for unit in _get_units_func.call():
			if unit == null or not is_instance_valid(unit):
				continue
			var feet: Vector3 = unit.global_position
			var line := "  %s  feet=(%.3f, %.3f, %.3f)" % [unit.name, feet.x, feet.y, feet.z]
			var cell: Vector3i = unit.get_current_cell() \
				if unit.has_method("get_current_cell") else TerrainCell.NONE
			var lattice: Lattice = _lattice_of(_get_map())
			if cell != TerrainCell.NONE and lattice != null:
				var center: Vector3 = lattice.world_position_at(cell)
				var dx := feet.x - center.x
				var dz := feet.z - center.z
				line += "  tile=(%d,%d,L%d)  d=(%.3f, %.3f) |%.3f|" % [
					cell.x, cell.y, cell.z, dx, dz, sqrt(dx * dx + dz * dz)]
			if cam:
				var px: Vector2 = cam.unproject_position(feet)
				line += "  screen=(%.1f, %.1f)px" % [px.x, px.y]
			print(line)
	print("=".repeat(60))
	print("")
