extends Node3D

## Guard (ADR-0077 dec. 7 — "no *unauthored depth*"): every depth-writing UI prim
## in the Status-window subtree (`_open_root`: the stats band + Eqp/Ability lower panel + the
## §15.26 delta/compare panel) must AUTHOR a rung on the depth ladder. The illegal thing is the
## `z_rung = -1` floor SENTINEL (and rung-less placement) — "nobody decided", so the prim parks at
## the Z=0 floor by accident and a subtractive fold band (the F3-draggable vitals stripe) composites
## OVER it (a band is occluded only by opaque depth that is *nearer*; opacity alone does not win).
##
## Keys on the AUTHORED rung, not the runtime world-Z: each authoring path records `set_meta("z_rung")`
## on the prim it places (UNconditionally, on OR off the fold — off-fork every rung collapses to Z=0,
## so world-Z cannot tell rung 0 from -1, and container/origin nodes sit at local Z=0 by design).
## Rung 0 (RP_BACKGROUND) is a legitimate authored back — only -1 / no-tag is banned.
##
## Slice 1: the opaque UIFrame chrome (stats / lower / delta frames). RED before the migration (stats +
## delta frames were authored at z_rung=-1); GREEN once they name a rung.
## Slice 2: the opaque depth-writing icon/label meshes (`vitals_sprite`): the Eqp/Ability/slot icons +
## weapon legend (already authored) and the stats LABELS (were z_rung=-1 → floor).
## Slice 3 (growing): the opaque glyph meshes (`formation_text_opaque` number font + `formation_font_opaque`
## FONT.BIN): the stats NUMBERS (were rung-less at the Z=0 floor) and the Eqp/Ability item-name text.
##
## Run: <GODOT> --path . --quit-after 40 res://tests/DetailUnauthoredDepthTest.tscn

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

const _VIEW := {
	"move": 4, "jump": 3, "speed": 8, "r_power": 9, "r_wev": 5, "l_power": 0, "l_wev": 0,
	"r_at": 7, "c_ev": 12, "s_ev": 0, "a_ev": 0, "l_at": 0,
	"equipment": [{"name": "Broad Sword", "palette": 0, "icon_graphic": -1}, {},
		{"name": "Leather Hat", "palette": 4, "icon_graphic": -1}, {}, {}],
	"ability_slots": [{"name": "Battle Skill"}, {"name": "White Magic"},
		{"name": "Counter"}, {"name": "Move+1"}, {"name": "Any Ground"}],
}

const _Z_FLOOR_SENTINEL := -1

## The opaque, depth-writing UI shaders that seed the fold's shared depth buffer (ADR-0077 depth-ladder
## members). A mesh drawn through one of these MUST author a rung — it occludes (or is occluded by) the
## subtractive fold bands purely by distance. Subtractive band shaders (formation_band_fold) are NOT
## here: they are MEANT to sit far and fold behind the near opaque prims.
const _DEPTH_SHADERS := ["vitals_sprite", "formation_text_opaque", "formation_font_opaque"]

var _passed := 0
var _failed := 0


func _ready() -> void:
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	d.set_stats_view(_VIEW)
	await get_tree().process_frame
	await get_tree().process_frame

	var lower := d.find_child("LowerPanel", true, false) as Node3D
	_expect(lower != null, "LowerPanel (_open_root) not found — Status-window subtree missing")
	if lower != null:
		_check_frames(lower)
		_check_meshes(lower)

	# Preview state adds the §15.26 delta/compare panel under _open_root: its own frame plus text +
	# weapon-legend clones (duplicate()s of the base). Re-walk to prove the clones carry the authored
	# rung too (duplicate() copies node meta) and the delta frame named a rung (was z_rung=-1).
	d.set_stats_preview(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var delta := d.find_child("StatsDeltaPanel", true, false)
	_expect(delta != null, "StatsDeltaPanel not built in stats-preview — delta coverage skipped")
	if lower != null:
		_check_frames(lower)
		_check_meshes(lower)

	d.queue_free()
	print("\n=== DetailUnauthoredDepthTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		printerr("[FAIL] DetailUnauthoredDepthTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailUnauthoredDepthTest: no unauthored depth in the Status-window frames")
		get_tree().quit(0)


## Every opaque UIFrame under the subtree must carry an authored rung != the floor sentinel.
func _check_frames(root: Node) -> void:
	var frames: Array[UIFrame] = []
	_collect_frames(root, frames)
	_expect(not frames.is_empty(), "no opaque UIFrame found under the Status-window subtree")
	for f in frames:
		var where := _path_of(f, root)
		_expect(f.has_meta("z_rung"),
			"UIFrame '%s' has UNAUTHORED depth (no z_rung tag)" % where)
		if f.has_meta("z_rung"):
			_expect(int(f.get_meta("z_rung")) != _Z_FLOOR_SENTINEL,
				"UIFrame '%s' parks at the z_rung=-1 floor sentinel (unauthored depth)" % where)


## Every opaque depth-writing mesh (drawn through a `_DEPTH_SHADERS` shader) must resolve to an
## authored rung != the floor sentinel. The rung is read from the nearest self-or-ancestor carrying
## the `z_rung` tag — icons/glyphs tag themselves; a UIFrame tags its node and its internal mesh
## resolves via that ancestor.
func _check_meshes(root: Node) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_depth_meshes(root, meshes)
	_expect(not meshes.is_empty(), "no opaque depth-writing mesh found under the Status-window subtree")
	for mi in meshes:
		var where := _path_of(mi, root)
		var carrier := _authored_carrier(mi, root)
		_expect(carrier != null,
			"depth-writing mesh '%s' has UNAUTHORED depth (no z_rung tag on it or any ancestor)" % where)
		if carrier != null:
			_expect(int(carrier.get_meta("z_rung")) != _Z_FLOOR_SENTINEL,
				"depth-writing mesh '%s' parks at the z_rung=-1 floor sentinel (unauthored depth)" % where)


func _collect_depth_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var m := (node as MeshInstance3D).material_override
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null \
				and (m as ShaderMaterial).shader.resource_path.get_file().get_basename() in _DEPTH_SHADERS:
			out.append(node)
	for c in node.get_children():
		_collect_depth_meshes(c, out)


## Nearest self-or-ancestor (up to `root`) carrying the `z_rung` tag, or null if none.
func _authored_carrier(node: Node, root: Node) -> Node:
	var n := node
	while n != null and n != root.get_parent():
		if n.has_meta("z_rung"):
			return n
		n = n.get_parent()
	return null


func _collect_frames(node: Node, out: Array[UIFrame]) -> void:
	if node is UIFrame and (node as UIFrame).opaque:
		out.append(node)
	for c in node.get_children():
		_collect_frames(c, out)


func _path_of(node: Node, root: Node) -> String:
	var parts: Array[String] = []
	var n := node
	while n != null and n != root:
		parts.push_front(n.name)
		n = n.get_parent()
	return "/".join(parts)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("[DetailUnauthoredDepthTest] " + msg)
		print("  [x] " + msg)
