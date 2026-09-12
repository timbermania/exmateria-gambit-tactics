extends SceneTree

## #745 — is the drawn sprite EVER off the unit origin in a live scenario?
##
## `tools/probe_box_anchor_rename.gd` measures what renaming the mount's `UnitMesh`
## costs the two `ScenarioDialogueBoxPool` crossings, and the answer there is ZERO for a
## resting unit and 43 native px for a synthetically displaced one. The claim that turns
## that into a statement about the GAME is whether `mesh.global_position` ever differs
## from `speaker.global_position` in a real scenario. It is not obvious: FFT's carry pose
## displaces the drawn sprite, and `ScenarioDialogueBoxPool`'s comment block is twenty
## lines about tracking the *visible* sprite column.
##
## So: boot the real ScenarioPlayer, let it settle, and print the offset for every live
## unit, next to the sprite-layer offsets that DO displace the drawing. Then rename one
## unit's mount node and re-read both crossings on it.
##
## Run headful (NEVER --headless):
##     godot --path . -s res://tools/probe_box_anchor_live.gd
##
## Every line is prefixed `[live]`.

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _settled := -1


func _initialize() -> void:
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 1
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _process(_d: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _on_post_draw() -> void:
	_f += 1
	if _f > 900:
		print("[live] gave up waiting for units at frame %d" % _f)
		_quit = true
		return
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = false
		return
	var ubid = _vm.get("units_by_id")
	if ubid == null or ubid.size() == 0:
		return
	if _settled < 0:
		_settled = _f
		return
	if _f < _settled + 30:
		return
	_dump(ubid)
	_quit = true


func _dump(ubid) -> void:
	print("[live] ===== %d live unit(s) at frame %d =====" % [ubid.size(), _f])
	var speaker: Node3D = null
	var worst := 0.0
	for k in ubid.keys():
		var u = ubid[k]
		if u == null or not is_instance_valid(u) or not (u is Node3D):
			continue
		var mesh: Node3D = (u as Node3D).get_node_or_null("UnitMesh") as Node3D
		if mesh == null:
			print("[live] uid=0x%02X '%s' — NO UnitMesh" % [int(k), u.name])
			continue
		var d: Vector3 = mesh.global_position - (u as Node3D).global_position
		worst = maxf(worst, d.length())
		var slm = u.get("sprite_layers")
		var so = null
		var ao = null
		if slm != null:
			so = slm.get("sprite_offset") if ("sprite_offset" in slm) else null
			ao = slm.get("anim_offset") if ("anim_offset" in slm) else null
		print("[live] uid=0x%02X '%s' mesh-origin offset=%s  |d|=%.5f  slm.sprite_offset=%s anim_offset=%s" % [
			int(k), u.name, str(d), d.length(), str(so), str(ao)])
		if speaker == null:
			speaker = u as Node3D
	print("[live] WORST mesh-origin offset over %d unit(s): %.5f world units" % [ubid.size(), worst])

	# Exercise both crossings on a LIVE speaker, with and without the rename.
	var pool = _vm.get("box_pool")
	var cam: Camera3D = _vm.call("_active_camera") if _vm.has_method("_active_camera") else null
	if pool == null or cam == null or speaker == null:
		print("[live] no pool/camera/speaker — crossings not exercised")
		return
	var a0: Vector3 = pool.call("_sprite_billboard_anchor", cam, speaker)
	var mesh2: Node3D = speaker.get_node_or_null("UnitMesh") as Node3D
	if mesh2 != null:
		mesh2.name = "UnitMeshRENAMED"
	var a1: Vector3 = pool.call("_sprite_billboard_anchor", cam, speaker)
	print("[live] crossing A on '%s': present=%s renamed=%s  Δ=%s" % [
		speaker.name, str(a0), str(a1), str(a1 - a0)])
	if mesh2 != null:
		mesh2.name = "UnitMesh"


func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null
