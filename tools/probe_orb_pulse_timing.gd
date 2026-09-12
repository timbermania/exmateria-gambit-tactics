extends SceneTree

## Throwaway timing rig: boots Formation.tscn and samples the SELECTED orb's
## `brightness` shader parameter every frame with a wall-clock timestamp for ~3 s,
## then dumps (t, brightness) to /tmp and quits. Reads the material param directly
## (no framebuffer readback), so it runs at full framerate and measures the pulse
## itself. Confirms the live period vs the ROM's 42-frame / 0.70 s ramp (§10.2).
## Run: godot --path . --script res://tools/probe_orb_pulse_timing.gd

var _t := 0.0
var _rows: Array = []
var _scene: Node


func _initialize() -> void:
	get_root().size = Vector2i(512, 480)
	_scene = load("res://assets/scenes/Formation.tscn").instantiate()
	get_root().add_child(_scene)


func _process(delta: float) -> bool:
	_t += delta
	var mats: Array = _scene.get("_selected_orb_mats")
	var mat: ShaderMaterial = mats[0] if mats != null and not mats.is_empty() else null
	if mat != null:
		_rows.append("%.4f,%.5f" % [_t, mat.get_shader_parameter("brightness")])
	if _t >= 3.0:
		var f := FileAccess.open("/tmp/orb_pulse.csv", FileAccess.WRITE)
		f.store_string("t,brightness\n" + "\n".join(_rows) + "\n")
		f.close()
		print("ORB_PULSE_TIMING_SAVED %d rows over %.2fs -> /tmp/orb_pulse.csv" % [_rows.size(), _t])
		return true
	return false
