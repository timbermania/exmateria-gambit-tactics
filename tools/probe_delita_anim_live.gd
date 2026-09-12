extends SceneTree
## [Live Delita anim watch] Runs scn6 CONTINUOUSLY through the carry beat and
## logs Delita(5)'s current_anim_id every VM frame around PC 216, WITHOUT pausing.
## Decides: is the probe-reported 520 a paused-capture artifact (live settles to
## 519, the opcode value) or a real off-by-one (live stays 520)?
##
## Run (NOT headless):
##   godot --path . -s res://tools/probe_delita_anim_live.gd
## Env: FROM(210) TO(232) — pc window to log; MAXF(6000) frame budget.

var _scene: Node
var _vm: Node
var _f := 0
var _from := 210
var _to := 232
var _maxf := 6000
var _done := false
var _last_line := ""

func _initialize() -> void:
	if OS.has_environment("FROM"): _from = int(OS.get_environment("FROM"))
	if OS.has_environment("TO"): _to = int(OS.get_environment("TO"))
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
		# NOTE: do NOT set rewind_target_pc — we want a continuous run, no park.
	else:
		push_error("[dal] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	print("[dal] booting scn6 live, logging Delita anim for pc in [%d,%d]" % [_from, _to])

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

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
		return
	# Never let it park: if the session paused us at a target, resume.
	if _vm.get("_paused"):
		_vm.set("_paused", false)
	var pc: int = _vm.get_pc()
	if pc >= _from and pc <= _to:
		var ubid = _vm.get("units_by_id")
		if ubid != null and ubid.has(5) and is_instance_valid(ubid[5]):
			var d = ubid[5]
			var oid = -1
			if ubid.has(12) and is_instance_valid(ubid[12]): oid = ubid[12].current_anim_id
			var line := "f=%d pc=%d Delita.anim=%d(0x%X) Ovelia.anim=%d" % [
				_f, pc, d.current_anim_id, d.current_anim_id, oid]
			if line != _last_line:
				print("[dal] " + line)
				_last_line = line
	if pc > _to or _f > _maxf:
		print("[dal] DONE (pc=%d f=%d)" % [pc, _f])
		_done = true

func _init() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
