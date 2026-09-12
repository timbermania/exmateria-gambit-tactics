extends SceneTree
## Convention search scored by ALTAR-PLANE framing stability
## (handoff_camera_framing_pivot.md). For an ortho cam the framed subject is
## where the centre-ray crosses the subject plane. We sweep rotation
## conventions + back-rotation modes and score each by how tightly the chapel
## swoop frames' centre-rays cluster where they cross the altar floor
## (y=ALTAR_Y). The winner frames one stable, in-map tile across the yaw swoop
## => that pins the convention AND confirms H1(+H2). offset is set to 0 here
## (we want the convergence tile; a constant offset then re-centres it).
##
## Run (NOT headless):  godot --path . -s res://tools/diag_camera_framing.gd

const DIVISOR := 112.0
const ALTAR_Y := 3.04
const MAP_X := 14
const MAP_Z := 10

var _frames: Array = []

func _init() -> void:
	var f := FileAccess.open("res://assets/scenarios/scenario_1_chunk.json", FileAccess.READ)
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	var swoop_offsets := [122, 139, 156, 173, 190, 207]  # exclude PC56 establisher
	for inst in doc["instructions"]:
		if inst.get("name") != "Camera" or not swoop_offsets.has(int(inst.get("offset", -1))):
			continue
		var pm := {}
		for p in inst["params"]:
			pm[p["name"]] = int(p["value"])
		_frames.append({
			"x": _s16(pm["X"]), "z": _s16(pm["Z"]), "y": _s16(pm["Y"]),
			"angle": _s16(pm["Angle"]), "map_rot": _s16(pm["Map Rotation"]),
			"cam_rot": _s16(pm.get("Camera Rotation", 0)),
		})

	print("=== Altar-plane convention search (%d swoop frames, y=%.2f) ===" % [_frames.size(), ALTAR_Y])
	var results: Array = []
	for euler_order in ["YXZ", "XYZ", "ZYX", "YZX"]:
		for yaw_mode in ["yaw", "-yaw"]:
			for pitch_sign in [-1, 1]:
				for backrot in ["RAW", "FWD", "INV"]:
					var fit := _eval(euler_order, yaw_mode, pitch_sign, backrot)
					results.append({
						"label": "%s %s p%+d %s" % [euler_order, yaw_mode, pitch_sign, backrot],
						"radius": fit["radius"], "c": fit["c"], "inmap": fit["inmap"]})
	results.sort_custom(func(a, b): return a["radius"] < b["radius"])
	print("%-22s %9s  %-7s  centroid (x,z)" % ["convention", "radius", "in-map"])
	for i in mini(18, results.size()):
		var r = results[i]
		print("%-22s %9.3f  %-7s  (%.2f, %.2f)" % [
			r["label"], r["radius"], "YES" if r["inmap"] else "no", r["c"].x, r["c"].y])
	quit()


func _eval(euler_order: String, yaw_mode: String, pitch_sign: int, backrot: String) -> Dictionary:
	var hits: Array = []  # Vector2(x,z) on altar plane
	for fr in _frames:
		var godot_rot := _rot(fr, yaw_mode, pitch_sign)
		var order := _order(euler_order)
		var basis := Basis.from_euler(godot_rot, order)
		var remapped := Vector3(
			 float(fr["x"]) / DIVISOR, -float(fr["z"]) / DIVISOR, float(fr["y"]) / DIVISOR)
		var body: Vector3
		match backrot:
			"RAW": body = remapped
			"FWD": body = basis * remapped
			"INV": body = basis.inverse() * remapped
		var dir := (-basis.z).normalized()
		if absf(dir.y) < 1e-5:
			return {"radius": 1e9, "c": Vector2.ZERO, "inmap": false}
		var t := (ALTAR_Y - body.y) / dir.y
		var hit := body + dir * t
		hits.append(Vector2(hit.x, hit.z))
	var c := Vector2.ZERO
	for h in hits: c += h
	c /= float(hits.size())
	var maxd := 0.0
	for h in hits: maxd = maxf(maxd, h.distance_to(c))
	var inmap := c.x >= -1.0 and c.x <= float(MAP_X) and c.y >= -1.0 and c.y <= float(MAP_Z)
	return {"radius": maxd, "c": c, "inmap": inmap}


func _rot(fr: Dictionary, yaw_mode: String, pitch_sign: int) -> Vector3:
	var pitch_deg := float(fr["angle"]) * 360.0 / 4096.0
	var yaw_deg := float(fr["map_rot"]) * 360.0 / 4096.0
	var y := (-yaw_deg) if yaw_mode == "-yaw" else yaw_deg
	return Vector3(deg_to_rad(pitch_sign * pitch_deg), deg_to_rad(y), 0.0)


func _order(s: String) -> int:
	match s:
		"XYZ": return EULER_ORDER_XYZ
		"ZYX": return EULER_ORDER_ZYX
		"YZX": return EULER_ORDER_YZX
		_: return EULER_ORDER_YXZ


func _s16(v: int) -> int:
	return v - 65536 if v >= 32768 else v
