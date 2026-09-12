extends Node3D
## Calibration + regression harness for the unified Ordering-Table depth model
## (ADR-0009). Renders one quad per DepthMode at the SAME world point through the
## shared ot_depth seam, so their front/back ordering is directly visible and
## the calibration constants can be eyeballed and tuned live.
##
## Expected ordering, front -> back (Godot reversed-Z: larger DEPTH = nearer):
##   FIXED_FRONT > FIXED_16 > {UNIT, TILE_OVERLAY, PULL_FORWARD_16, PULL_FORWARD_8}
##   > STANDARD > MAP_SKIRT > FIXED_BACK
## (the relative pulls depend on the calibration; STANDARD is the reference.)
##
## Keys: Up/Down tune UNITS_PER_OT_BUCKET, Left/Right tune UNIT_FORWARD,
##       P prints the current calibration, R resets to DepthMode defaults.

const DepthModeScript = ExMateriaSchema.DepthMode
const DEBUG_SHADER = preload("res://addons/exmateria_render/debug/depth_debug.gdshader")

# mode, label, color — drawn left-to-right; all share one world point so the
# overlap zone reveals their DEPTH ordering.
const ROWS := [
	[0, "STANDARD",       Color(0.5, 0.5, 0.5)],
	[1, "PULL_FORWARD_8", Color(0.2, 0.8, 0.2)],
	[5, "PULL_FORWARD_16",Color(0.1, 1.0, 0.4)],
	[6, "UNIT",           Color(0.3, 0.6, 1.0)],
	[7, "TILE_OVERLAY",   Color(0.6, 0.4, 1.0)],
	[8, "MAP_SKIRT",      Color(0.4, 0.3, 0.2)],
	[2, "FIXED_FRONT",    Color(1.0, 0.2, 0.2)],
	[4, "FIXED_16",       Color(1.0, 0.6, 0.1)],
	[3, "FIXED_BACK",     Color(0.2, 0.2, 0.2)],
]

var _materials: Array[ShaderMaterial] = []
var _units_per_bucket := DepthModeScript.UNITS_PER_OT_BUCKET
var _unit_forward := DepthModeScript.UNIT_FORWARD
var _label: Label


func _ready() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 8.0
	cam.position = Vector3(0, 0, 10)
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	# Quads fan across X but all sit at z = 0 (same depth), so each has a visible
	# sliver and a shared central overlap that exposes the ordering.
	var n := ROWS.size()
	for i in range(n):
		var row = ROWS[i]
		var x := (float(i) - float(n - 1) / 2.0) * 0.7
		_add_quad(int(row[0]), row[2] as Color, Vector3(x, 0, 0))

	_label = Label.new()
	_label.position = Vector2(12, 12)
	var layer := CanvasLayer.new()
	layer.add_child(_label)
	add_child(layer)
	_refresh_label()


func _add_quad(mode: int, color: Color, pos: Vector3) -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.2, 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos

	var mat := ShaderMaterial.new()
	mat.shader = DEBUG_SHADER
	mat.set_shader_parameter("debug_color", color)
	mat.set_shader_parameter("depth_mode", mode)
	# Push the authoritative calibration (mirrors DepthMode.apply()).
	DepthModeScript.apply(mat, mode)
	mat.set_shader_parameter("depth_mode", mode)  # apply() set it; keep explicit

	mi.material_override = mat
	add_child(mi)
	_materials.append(mat)


func _apply_calibration() -> void:
	for mat in _materials:
		mat.set_shader_parameter("ot_units_per_bucket", _units_per_bucket)
		mat.set_shader_parameter("ot_unit_forward", _unit_forward)
	_refresh_label()


func _refresh_label() -> void:
	if not _label:
		return
	var lines := ["DEPTH DEBUG (ADR-0009)  —  reversed-Z: larger = nearer",
		"UNITS_PER_OT_BUCKET = %.4f  (Up/Down)" % _units_per_bucket,
		"UNIT_FORWARD        = %.4f  (Left/Right)" % _unit_forward,
		"P: print   R: reset", ""]
	for row in ROWS:
		lines.append("  %d  %s" % [int(row[0]), row[1]])
	_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_UP:    _units_per_bucket += 0.01; _apply_calibration()
		KEY_DOWN:  _units_per_bucket = max(0.0, _units_per_bucket - 0.01); _apply_calibration()
		KEY_RIGHT: _unit_forward += 0.01; _apply_calibration()
		KEY_LEFT:  _unit_forward = max(0.0, _unit_forward - 0.01); _apply_calibration()
		KEY_R:
			_units_per_bucket = DepthModeScript.UNITS_PER_OT_BUCKET
			_unit_forward = DepthModeScript.UNIT_FORWARD
			_apply_calibration()
		KEY_P:
			print("[DepthDebug] UNITS_PER_OT_BUCKET = %.4f, UNIT_FORWARD = %.4f"
				% [_units_per_bucket, _unit_forward])
