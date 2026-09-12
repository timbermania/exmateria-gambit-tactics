extends Node3D

## Guard (headful): the Change-Job job-title plate (§15.24) migrated to ADR-0088
## registered elements — window element `changejob.title` (MENU_TILE chrome via the
## frame criterion + the shared BOX_OPEN beat + OWN_APERTURE) with the cream "Lv. N"
## line as an UNCLIPPED child element (`changejob.level` — its poke above the frame
## becomes a DECLARED answer, not a shader-default omission).
##   A. REGRESSION — golden position multiset captured from the pre-migration build.
##   B. CAPABILITY — window() element; moving it moves chrome + name + Lv line.
##   C. REGISTRATION AUDIT — zero unowned payload under the plate.
##   D. CLIP HONESTY — shut aperture reaches the body (chrome + name) but never the
##      Lv cells; reopening restores the body.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/ChangeJobTitleElementTest.tscn

const ChangeJobScreen = preload("res://src/ui3/changejob/ChangeJobScreen.gd")

## Captured 2026-08-11 from the pre-migration build (this guard's print-on-fail regen
## aid): set_job("Chemist", 8), autoplay_open=false, 2 settled frames.
const GOLDEN := [
	"4.7200,-8.8400,6.2700", "4.9600,-8.8400,6.2700", "4.9800,-8.3200,6.6500", "5.1200,-8.8400,6.2700",
	"5.1200,-8.8200,5.8900", "5.2800,-8.8400,6.2700", "5.4600,-8.2800,6.6500", "5.5200,-8.8400,6.2700",
	"5.6000,-8.8400,6.2700", "5.7600,-8.8400,6.2700",
]

var _failed := 0
var _passed := 0


func _ready() -> void:
	var cj: ChangeJobScreen = ChangeJobScreen.new()
	cj.autoplay_open = false
	cj.set_job("Chemist", 8)
	add_child(cj)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- A. regression -----------------------------------------------------------
	var observed := _collect_positions(cj)
	var golden := _parse_golden()
	_expect(observed.size() == golden.size(),
		"plate quad count drifted: observed %d vs golden %d" % [observed.size(), golden.size()])
	if observed.size() == golden.size():
		var worst := 0.0
		for i in observed.size():
			worst = maxf(worst, (observed[i] - golden[i]).length())
		_expect(worst < 0.001, "plate content drifted from golden (worst %.4f)" % worst)
	if _failed > 0:
		print("[ChangeJobTitleElementTest] observed multiset (GOLDEN format):")
		var line := ""
		for i in observed.size():
			line += "\"%.4f,%.4f,%.4f\", " % [observed[i].x, observed[i].y, observed[i].z]
			if (i + 1) % 4 == 0 or i == observed.size() - 1:
				print("\t" + line.strip_edges())
				line = ""

	# --- B. capability -----------------------------------------------------------
	if not cj.has_method("window"):
		_expect(false, "window() missing — plate not migrated to a registered element")
	else:
		var origin: Node3D = cj.call("window")
		_expect(origin != null and is_instance_valid(origin), "window element missing")
		if origin != null:
			var before := _collect_positions(origin)
			_expect(before.size() == observed.size(),
				"content outside the window element: %d of %d quads ride it" % [before.size(), observed.size()])
			var delta := Vector3(1.234, -0.567, 0.0)
			origin.position += delta
			var after := _collect_positions(origin)
			var ok := after.size() == before.size()
			if ok:
				for i in before.size():
					if ((after[i] - before[i]) - delta).length() >= 0.001:
						ok = false
						break
			_expect(ok, "plate content did not ride the window element move")
			origin.position -= delta

			# --- D. clip honesty -------------------------------------------------
			cj.set_open_frame(-1)
			var body: Array = cj.body_materials()
			_expect(body.size() > 0, "no body materials")
			var body_shut := true
			for m in body:
				var cw = m.get_shader_parameter("clip_world")
				if cw == null or cw.x < 1e19:
					body_shut = false
			_expect(body_shut, "shut aperture did not reach the plate body (chrome + name)")
			var e_level: UI3Element = cj.call("level_element") if cj.has_method("level_element") else null
			_expect(e_level != null, "level_element() missing (Lv line not an UNCLIPPED element)")
			if e_level != null:
				for m in e_level.payload_materials():
					var cw = m.get_shader_parameter("clip_world")
					_expect(cw == null or cw.x < 1e19, "Lv cell was box-open-clipped (must stay unclipped)")

				# --- Amendment 4 §2: changejob.level DECLARES its one real knob as a driver
				# (was a derived([]) dead-end), and scrubbing it moves the element live
				# (write-back → static var → re-place origin → glyph payload rides).
				var lrow := _rect_row(e_level)
				_expect((lrow.get("drivers", []) as Array).has("changejob.level_label_top_y"),
					"changejob.level must declare changejob.level_label_top_y, got %s" % [lrow])
				var y0 := e_level.rect().position.y
				var glyph0 = _first_glyph_y(e_level)
				Tune.set_value("changejob.level_label_top_y", y0 + 12.0)
				_expect(abs(e_level.rect().position.y - (y0 + 12.0)) < 0.001,
					"scrubbing the level knob must move the element rect, got %s" % e_level.rect().position.y)
				var glyph1 = _first_glyph_y(e_level)
				_expect(glyph0 != null and glyph1 != null and abs((glyph0 - glyph1) - 12.0 * 0.04) < 0.001,
					"the Lv glyphs must ride the level scrub by the same delta (world), got %s -> %s" % [glyph0, glyph1])
				Tune.clear("changejob.level_label_top_y")
			cj.set_open_frame(1000)
			var reopened := false
			for m in cj.body_materials():
				var cw = m.get_shader_parameter("clip_world")
				if cw != null and cw.x < 1e19:
					reopened = true
			_expect(reopened, "settled reopen left the plate shut")

	# --- C. registration audit ----------------------------------------------------
	var audit_errors: Array = UI3RegistrationAudit.check(cj, [])
	for e in audit_errors:
		_expect(false, "registration audit: %s" % e)

	cj.queue_free()
	print("\n=== ChangeJobTitleElementTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ChangeJobTitleElementTest")
		get_tree().quit(1)
	else:
		print("[PASS] ChangeJobTitleElementTest: changejob.title + changejob.level registered elements (golden no-op + grab + audit + declared clip)")
		get_tree().quit(0)


func _rect_row(e: UI3Element) -> Dictionary:
	for r: Dictionary in e.criteria():
		if String(r["field"]) == "rect":
			return r
	return {}


## The global Y of the first payload glyph mesh under `root` (null when none) — for the
## write-through: the "Lv" glyphs must ride a level scrub by the same delta as the element.
func _first_glyph_y(root: Node):
	if root is MeshInstance3D:
		return (root as MeshInstance3D).global_position.y
	for c in root.get_children():
		var y = _first_glyph_y(c)
		if y != null:
			return y
	return null


func _collect_positions(root: Node) -> Array:
	var out: Array = []
	if root != null and is_instance_valid(root):
		_collect(root, out)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if not is_equal_approx(a.x, b.x): return a.x < b.x
		if not is_equal_approx(a.y, b.y): return a.y < b.y
		return a.z < b.z)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append((n as MeshInstance3D).global_position)
	for c in n.get_children():
		_collect(c, out)


func _parse_golden() -> Array:
	var out: Array = []
	for s: String in GOLDEN:
		var p := s.split(",")
		out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if not is_equal_approx(a.x, b.x): return a.x < b.x
		if not is_equal_approx(a.y, b.y): return a.y < b.y
		return a.z < b.z)
	return out


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[ChangeJobTitleElementTest] %s" % msg)
		print("  [x] " + msg)
