extends SceneTree
## Scenario-beat capture WITH the MapGridOverlay tile grid enabled — the Godot
## half of the PSX-vs-Godot tile-grid A/B (see
## research/working_documents/psx_tile_grid/reproject_tile_grid.md).
##
## Same deterministic replay-and-hold as capture_scenario_beat.gd (holds via the
## dialogue gate with animation LIVE; NEVER sets `paused`), but before the grab it
## builds a MapGridOverlay on the ProceduralMap — replicating
## ScenarioUnitAlignmentDebugPanel._rebuild_grid() so the grid renders without the
## interactive F3 toggle. Cyan = tile borders, amber = per-tile center crosses.
##
## Run (NOT headless):
##   # from the package root
##   SCEN=2 TARGET_PC=283 SHOT=/tmp/godot_grid.png \
##     godot --path . -s res://tools/capture_grid_beat.gd

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const MapGridOverlay = ExMateriaBattlefield.MapGridOverlay


# `MapGridOverlay` is named as a TYPE, not preloaded by path — ADR-0208 dec. 2 + dec. 3.
# It is on the addon's DECLARED_PUBLISHED set, and a standalone entry point (`-s`, this
# script IS the top of the tree) has no mount available to it: a mount needs a consumer
# scene. A published name is the only faithful route left, and this is it.

var _scene: Node
var _vm: Node
var _f := 0
var _frozen_at := -1
var _did := false
var _quit := false
var _grid_built := false
var _shot := "/tmp/godot_grid.png"
var _target_pc := 283
var _rewind_sent := false
var _settle := 90
var _maxf := 3000

func _initialize() -> void:
	if OS.has_environment("SHOT"): _shot = OS.get_environment("SHOT")
	if OS.has_environment("TARGET_PC"): _target_pc = int(OS.get_environment("TARGET_PC"))
	if OS.has_environment("SETTLE"): _settle = int(OS.get_environment("SETTLE"))
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	var scen := 2
	if OS.has_environment("SCEN"): scen = int(OS.get_environment("SCEN"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = scen
	else:
		push_error("[grid] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	RenderingServer.global_shader_parameter_set("psx_dither_enabled", false)
	print("[grid] booting scenario %d, target_pc=%d, shot -> %s" % [scen, _target_pc, _shot])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		return

	if not _rewind_sent:
		if _vm.is_fast_playing():
			pass
		else:
			_vm.dialog_auto_advance = false
			_vm.set_rewind_target(_target_pc)
			if _vm.is_fast_playing() or _vm.get_pc() >= _target_pc:
				_rewind_sent = true
				print("[grid] rewind → pc=%d sent at f=%d" % [_target_pc, _f])
		return

	if _frozen_at < 0:
		if not _vm.is_fast_playing() and _vm.get_pc() >= _target_pc:
			_frozen_at = _f
			_vm.dialog_auto_advance = false
			print("[grid] halted (gated) at pc=%d, f=%d" % [_vm.get_pc(), _f])

	# Build the grid once we've halted (map is fully loaded by then).
	if _frozen_at >= 0 and not _grid_built:
		_build_grid()

	var ready: bool = (_frozen_at >= 0 and _f >= _frozen_at + _settle) or (_f >= _maxf)
	if ready and not _did:
		_did = true
		if not _grid_built:
			_build_grid()
		_capture()
		_quit = true

func _build_grid() -> void:
	var map := _find_procedural_map(_scene)
	if map == null or not map.has_method("get_all_tiles"):
		push_warning("[grid] no ProceduralMap.get_all_tiles(); grid skipped")
		_grid_built = true
		return
	var grid = MapGridOverlay.new()
	map.add_child(grid)
	grid.build_from_tiles(map.get_all_tiles())
	_grid_built = true
	print("[grid] MapGridOverlay built from %d tiles" % map.get_all_tiles().size())

func _find_procedural_map(n: Node) -> Node:
	if n.name == "ProceduralMap" and n.has_method("get_all_tiles"):
		return n
	for c in n.get_children():
		var r := _find_procedural_map(c)
		if r != null:
			return r
	return null

func _capture() -> void:
	var img := root.get_texture().get_image()
	img.save_png(_shot)
	print("[grid] ===== CAPTURED f=%d frozen_at=%d grid_built=%s =====" % [
		_f, _frozen_at, str(_grid_built)])
	_dump_units()

func _dump_units() -> void:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var vp := root.get_viewport().get_visible_rect().size
	for iid in _vm.units_by_id:
		var u: Node = _vm.units_by_id[iid]
		if u != null and u is Node3D:
			var p: Vector3 = (u as Node3D).global_position
			var scr := "n/a"
			if cam != null and not cam.is_position_behind(p):
				var s: Vector2 = cam.unproject_position(p)
				scr = "scr256=(%.1f, %.1f)" % [s.x / vp.x * 256.0, s.y / vp.y * 240.0]
			print("[grid] iid=%s %s pos=(%.3f, %.3f, %.3f) %s" % [
				str(iid), u.name, p.x, p.y, p.z, scr])

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null
