extends SceneTree
## Dump the horizontal-flip state of every scenario-6 carry unit at PC=316:
##   * current_anim_id (>=0x1F4 = EVTCHR cinematic frame)
##   * global_reversion (the whole-sprite UV flip = slm.apply_reversion)
##   * type1_reversions (per-block revert flags baked from EVTCHR frame data)
##   * facing_angle + camera quadrant / pose octant inputs
## Ovelia hangs off the WRONG side vs PSX — this shows whether it's the stale
## global_reversion or the baked per-block reverts that mirror her.
##
## Run: godot --path . -s res://tools/probe_scenario6_reversion.gd   (NOT headless)

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _rewound := false
var _settle_at := -1
var _pc := 316

func _initialize() -> void:
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null: sess.selected_scenario_id = 6
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _process(_d: float) -> bool:
	if _quit: quit(); return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null: _vm.dialog_auto_advance = false
		return
	if not _rewound:
		if _vm.has_method("set_rewind_target"):
			_vm.set_rewind_target(_pc); _rewound = true
		return
	var paused = _vm.get("paused")
	var ff = _vm.get("_ff_active")
	if _settle_at < 0:
		if (paused == true) and (ff == false or ff == null):
			_settle_at = _f
		return
	if _f < _settle_at + 40:
		return
	_dump()
	_quit = true

func _dump() -> void:
	var ubid = _vm.get("units_by_id")
	print("\n[rev] ================ SCENARIO-6 REVERSION DUMP @ PC=%d ================" % _pc)
	for k in ubid.keys():
		var u = ubid[k]
		if u == null or not is_instance_valid(u) or not u.visible:
			continue
		var mat: ShaderMaterial = u.get("material")
		if mat == null:
			continue
		var aid = u.get("current_anim_id")
		var gr = mat.get_shader_parameter("global_reversion")
		var revs = mat.get_shader_parameter("type1_reversions")
		var invs = mat.get_shader_parameter("type1_inversions")
		var fa = u.get("facing_angle")
		var slm = u.get("sprite_layers")
		var slm_ar = slm.get("apply_reversion") if slm != null else null
		var tex := mat.get_shader_parameter("type1_tex") as Texture2D
		var atlas := tex.resource_path.get_file() if tex != null else "<none>"
		print("[rev] uid=0x%02X '%s'  anim=0x%03X  atlas=%s" % [int(k), u.name, int(aid) if aid != null else -1, atlas])
		print("[rev]     facing_angle=0x%03X  global_reversion=%s  slm.apply_reversion=%s" % [
			int(fa) & 0xFFF if fa != null else -1, str(gr), str(slm_ar)])
		print("[rev]     type1_reversions=%s" % str(revs))
		print("[rev]     type1_inversions=%s" % str(invs))
	print("[rev] ==================================================================\n")

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
