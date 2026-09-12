extends SceneTree
## [Carry piece dump] Parks scenario 6 at a target PC and prints, for Delita(5)
## and Ovelia(12), the EXACT rendered EVTCHR blocks (shader params type1_locs /
## type1_rects / type1_rect_sizes / inversions / reversions) plus the projected
## anchor screen pos. Diffs Godot's composition against the PSX unit+0x204 piece
## buffer decoded from scenario6_carry_over_shoulder.sstate.
##   PC=219 godot --path . -s res://tools/probe_carry_pieces.gd
var _scene: Node
var _vm: Node
var _f := 0
var _pc := 219
var _done := false
var _reported := false

func _initialize() -> void:
	if OS.has_environment("PC"): _pc = int(OS.get_environment("PC"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
		sess.rewind_target_pc = _pc
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	print("[pcp] booting scn6 pc=%d" % _pc)

func _process(_dt: float) -> bool:
	if _done:
		quit()
		return true
	return false

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null

func _dump_unit(uid: int, u) -> void:
	if u == null or not is_instance_valid(u):
		print("  U%d: absent" % uid); return
	var mat = u.get("material")
	var cam := root.get_viewport().get_camera_3d()
	var mesh = u.get("mesh_instance")
	var sp := Vector2(-1, -1)
	if mesh != null and is_instance_valid(mesh) and cam != null:
		sp = cam.unproject_position(mesh.global_position)
	print("  === U%d anim=0x%X facing=%s screen_anchor=(%.2f,%.2f) ===" % [
		uid, u.current_anim_id, str(u.get("facing_direction")), sp.x, sp.y])
	# Frame identity: the walker's last-rendered EVTCHR frame byte (== the atlas
	# tile PSX samples; cross-check against the PSX unit+0x204 piece[0] UV below).
	var a = _vm.peek_actor(uid) if _vm.has_method("peek_actor") else null
	if a != null and a.get("walker") != null:
		var w = a.get("walker")
		print("    walker seg=%d last_fb=0x%02X op_index=%d/%d" % [
			w.get("seg_id"), int(w.get("last_fb")), int(w.get("op_index")), w.get("opcodes").size()])
	if mat == null:
		print("    (no material)"); return
	var locs = mat.get_shader_parameter("type1_locs")
	var rects = mat.get_shader_parameter("type1_rects")
	var sizes = mat.get_shader_parameter("type1_rect_sizes")
	var inv = mat.get_shader_parameter("type1_inversions")
	var rev = mat.get_shader_parameter("type1_reversions")
	var loc_off = mat.get_shader_parameter("type1_loc_offsets")
	var shared = mat.get_shader_parameter("shared_loc_offset")
	var flip = mat.get_shader_parameter("flip_h")
	print("    shared_loc_offset=%s flip_h=%s" % [str(shared), str(flip)])
	var n := 0
	if locs != null: n = locs.size()
	print("    block_count=%d" % n)
	for i in range(n):
		var loc = locs[i]
		var rc = rects[i] if rects != null and i < rects.size() else Vector2.ZERO
		var sz = sizes[i] if sizes != null and i < sizes.size() else Vector2.ZERO
		var iv = inv[i] if inv != null and i < inv.size() else null
		var rv = rev[i] if rev != null and i < rev.size() else null
		var lo = loc_off[i] if loc_off != null and i < loc_off.size() else Vector2.ZERO
		print("    blk[%d] loc=(%.0f,%.0f) rect=(%.0f,%.0f) size=(%.0fx%.0f) inv=%s rev=%s loc_off=%s" % [
			i, loc.x, loc.y, rc.x, rc.y, sz.x, sz.y, str(iv), str(rv), str(lo)])

func _report() -> void:
	var ubid = _vm.get("units_by_id")
	print("[pcp] ===== PARKED pc=%d =====" % _vm.get_pc())
	print("PSX reference (decoded from unit+0x204, carry_over_shoulder.sstate):")
	print("  buffer[+0x03]=piece_count=1 for BOTH; piece[0] (the RENDERED tile):")
	print("  Ovelia(12) clut=0x78CC piece[0] loc(-17,-35) UV(160,80) 32x40 = EVTCHR seg1 frame 0xE5")
	print("  Delita(5)  clut=0x78C5 piece[0] loc(-17,-35) UV(128,160) 32x40 = EVTCHR seg1 frame 0xF2")
	print("  (tail records in the buffer are STALE; only piece[0] draws. Godot's rect below must match piece[0] UV.)")
	print("Godot rendered blocks:")
	for uid in [5, 12]:
		if ubid.has(uid):
			_dump_unit(uid, ubid[uid])

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
		return
	if not _reported and _vm.get_pc() >= _pc and _vm.get("_paused"):
		_reported = true
		_report()
		_done = true
	elif _f > 4000 and not _reported:
		print("[pcp] TIMEOUT never parked at pc=%d (pc=%d)" % [_pc, _vm.get_pc()])
		_done = true

func _init() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
