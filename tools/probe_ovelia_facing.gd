extends SceneTree
## [facing probe] Dump facing/octant/flip resolution for Delita(5)+Ovelia(12)
## at a parked scn6 PC, to compare against PSX +0x6C/6E/70/12.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController
var _scene: Node
var _vm: Node
var _pc := 117
var _done := false
var _rep := false
func _initialize() -> void:
	if OS.has_environment("PC"): _pc = int(OS.get_environment("PC"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
		sess.rewind_target_pc = _pc
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
func _process(_dt: float) -> bool:
	if _done: quit(); return true
	return false
func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n): return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
func _dump(uid: int, u) -> void:
	if u == null or not is_instance_valid(u): print("U%d absent" % uid); return
	var fd = u.get("facing_direction")
	var fa = -1
	if "facing_angle" in u: fa = u.get("facing_angle")
	var quad = 0
	if u.has_method("get_camera_quadrant"): quad = u.get_camera_quadrant()
	var psx = -1
	var variant = AnimationStateController.get_camera_variant(fd, quad)
	var octant = -1
	var grev = null
	var mat = u.get("material")
	if mat != null: grev = mat.get_shader_parameter("global_reversion")
	print("U%d: facing_direction=%s facing_angle=%s(0x%X) camera_quad=%d psx_cam=0x%X | get_camera_variant.revert=%s use_back=%s | pose_octant=%d | shader global_reversion=%s current_anim=0x%X" % [
		uid, str(fd), str(fa), (fa if fa>=0 else 0), quad, (psx if psx>=0 else 0),
		str(variant["revert"]), str(variant["use_back"]), octant, str(grev), u.current_anim_id])
func _report() -> void:
	var ubid = _vm.get("units_by_id")
	print("[facing] ===== PARKED pc=%d =====" % _vm.get_pc())
	print("[facing] ubid keys=%s" % str(ubid.keys()))
	for uid in [5, 12]:
		_dump(uid, ubid[uid] if ubid.has(uid) else null)
func _on_post_draw() -> void:
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
		return
	if not _rep and _vm.get_pc() >= _pc and _vm.get("_paused"):
		var ubid = _vm.get("units_by_id")
		if ubid.has(5) and ubid.has(12):
			_rep = true; _report(); _done = true
func _init() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
