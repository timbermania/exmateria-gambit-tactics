extends SceneTree
## [DEBUG-wall6] Standalone MAP state renderer — no scenario, fully deterministic.
## Instantiates MapComposer, loads a map+state, frames the whole map with an
## orthographic camera at the FFT iso angle (orbitable via YAW), optionally forces
## map_light_debug / restores the ambient*1.5 fudge, then screenshots and reports
## the mean/max luma of the darkest quadrant (the shadowed wall).
##
## Run (NOT headless):
##   # from the package root
##   MAP=MAP056 W=2 N=0 YAW=225 MAPDBG=0 AMB15=0 SHOT=/tmp/m.png \
##     godot --path . -s res://tools/render_map_state.gd
## Env: MAP, W(weather_raw), N(night), YAW(deg), ELEV(deg,default 30),
##      MAPDBG(-1..5), AMB15(1=restore ambient*1.5), SHOT, DITHER(1=PSX snap on).

var _mc: Node3D
var _cam: Camera3D
var _f := 0
var _did := false
var _quit := false
var _dither := false

func _initialize() -> void:
	var map := OS.get_environment("MAP") if OS.has_environment("MAP") else "MAP056"
	var w := int(OS.get_environment("W")) if OS.has_environment("W") else 2
	var n := int(OS.get_environment("N")) if OS.has_environment("N") else 0
	_mc = load("res://assets/scenes/ProceduralMap.tscn").instantiate()  # the host mount, ADR-0207 dec. 1
	root.add_child(_mc)
	var ok = _mc.change_map(map, w, n, 0)
	print("[rms] change_map(%s,w=%d,n=%d) -> %s" % [map, w, n, str(ok)])
	# Camera + light setup on next frames (after mesh built).
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(_cam)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	# Dither/quantize OFF by default: this rig's luma report wants the un-snapped value.
	# DITHER=1 turns the PSX framebuffer snap back on for a side-by-side of it.
	_dither = OS.has_environment("DITHER") and int(OS.get_environment("DITHER")) != 0
	RenderingServer.global_shader_parameter_set("psx_dither_enabled", _dither)

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _aabb(n: Node, acc: AABB, has: Array) -> AABB:
	if n is VisualInstance3D:
		var vi := n as VisualInstance3D
		var b := vi.get_aabb()
		b = vi.global_transform * b
		if not has[0]:
			acc = b; has[0] = true
		else:
			acc = acc.merge(b)
	for c in n.get_children():
		acc = _aabb(c, acc, has)
	return acc

func _on_post_draw() -> void:
	_f += 1
	if _f == 3:
		_frame_camera()
		# Re-assert after the autoloads have had their _ready: DebugConfig binds the
		# `render.psx_dither_enabled` tunable and pushes the global itself, which would
		# otherwise stomp whatever _initialize set.
		RenderingServer.global_shader_parameter_set("psx_dither_enabled", _dither)
		print("[rms] psx_dither_enabled=%s" % str(
			RenderingServer.global_shader_parameter_get("psx_dither_enabled")))
	if _f == 6 and not _did:
		_did = true
		_apply_debug_and_capture()
		_quit = true

func _frame_camera() -> void:
	var has := [false]
	var box := _aabb(_mc, AABB(), has)
	var c := box.get_center()
	var r := box.size.length() * 0.5 + 1.0
	var yaw := deg_to_rad(float(OS.get_environment("YAW")) if OS.has_environment("YAW") else 225.0)
	var elev := deg_to_rad(float(OS.get_environment("ELEV")) if OS.has_environment("ELEV") else 30.0)
	var dir := Vector3(cos(elev) * sin(yaw), sin(elev), cos(elev) * cos(yaw))
	_cam.global_position = c + dir * (r * 3.0)
	_cam.look_at(c, Vector3.UP)
	_cam.size = r * 2.0
	print("[rms] aabb center=%s size=%s cam=%s size=%.1f" % [str(c), str(box.size), str(_cam.global_position), _cam.size])

func _apply_debug_and_capture() -> void:
	var mapdbg := int(OS.get_environment("MAPDBG")) if OS.has_environment("MAPDBG") else 0
	var amb15 := OS.has_environment("AMB15") and OS.get_environment("AMB15") == "1"
	var mats := _collect_map_mats(_mc)
	for m in mats:
		if mapdbg >= 0:
			m.set_shader_parameter("map_light_debug", mapdbg)
		if amb15:
			var a = m.get_shader_parameter("ambient_light")
			if a != null:
				m.set_shader_parameter("ambient_light", a * 1.5)
	print("[rms] %d map mats, mapdbg=%d amb15=%s" % [mats.size(), mapdbg, str(amb15)])
	# one more frame so uniforms apply
	await RenderingServer.frame_post_draw
	var shot := OS.get_environment("SHOT") if OS.has_environment("SHOT") else "/tmp/rms.png"
	var img := root.get_texture().get_image()
	img.save_png(shot)
	print("[rms] ===== CAPTURED -> %s =====" % shot)

func _collect_map_mats(n: Node, acc: Array = []) -> Array:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		var mat := mi.material_override
		if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.get_active_material(0)
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null \
				and (mat as ShaderMaterial).shader.resource_path.findn("indexed_color") >= 0:
			acc.append(mat)
	for c in n.get_children():
		_collect_map_mats(c, acc)
	return acc
