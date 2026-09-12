extends Node3D

## Guard (headful): the EQUIP-PICKER ("Eqp."/"ALL") window frame-group refactor — the same
## "frame = movable origin + relative content" model applied to EquipPickerMenu (the separate
## overlay the handoff flagged as untouched).
##   A. REGRESSION — every drawn quad lands on the exact pre-refactor world position (GOLDEN).
##   B. CAPABILITY — moving _frame_origin by a delta moves the frame chrome + header + rows by
##      the same delta (grab-the-picker-window, content included).

const EquipPickerMenu = preload("res://src/ui3/detail/EquipPickerMenu.gd")

## Regenerated 2026-08-11 (5th): §15.28 round 47 — the type-glyph column went PER-TYPE
## (WORLD.BIN LUT 0x8018D7FC cells, 12×12, glyph_x 79→80 / glyph_dy −1→0 per the live prims
## (80,150)); ONLY the three glyph quads moved (x −0.04 = −1 display px, y −0.02 = center of
## the 12-high cell at dy 0), 55 unchanged in count.
## Prior regen (4th): live-quicksave alignment pass (issue #290 follow-up — the
## user's "row columns not horizontally aligned"): rows rect y152→150 (name ink = oracle),
## glyph_dy −3→−1, icon_dy −4→−2, count_dy 1→−1, slash_dy 1→2 (slash bottom-aligns with
## digit ink, per VRAM texel rows), ROWS_CONTAINER y136→138 (glove down 2 — only the two
## cursor quads moved). 55 unchanged in count. Prior regen (3rd): §15.27 / issue #290 — count digits switched to the FRAME.BIN
## BIG set (SMALL slash kept): eq/owned right edges 214/235→217/238, BIG advance 7 (was 5),
## cell 8×16 (was 6×10), digits +1px count_dy / slash +1px slash_dy. Only the count-column
## quads (x≈8.28–9.40 cluster) moved; 55 unchanged in count. Prior regen (2nd, same day):
## `equipicker.window.rect` y136→137 (every quad −0.04 world y). Prior: FRAME_RECT
## y135→136/w174→169, GLYPH_X 75→79, GLYPH_DY −4→−3, NAME_X 116→120, HEADER_Y 134→132.
## Before that (round 45): strip pin materialised + the weapon TYPE-GLYPH column added
## (52→55); earlier the RP_LEFT_BAND rung-ladder renumber lifted icon/text/header/cursor Z
## one bucket.
const GOLDEN := [
	"2.8800,-6.3200,8.7400", "2.9600,-6.4000,8.5500", "3.4400,-7.6000,7.9800", "3.4400,-6.9600,7.9800",
	"3.4400,-6.3200,7.9800", "4.1400,-7.5000,7.7900", "4.1600,-7.6000,7.9800", "4.1600,-6.9600,7.9800",
	"4.1600,-6.3200,7.9800", "5.0000,-7.5600,8.1700", "5.0000,-6.9200,8.1700", "5.0000,-6.2800,8.1700",
	"5.2400,-7.5600,8.1700", "5.2400,-6.9200,8.1700", "5.2400,-6.2800,8.1700", "5.4000,-7.5600,8.1700",
	"5.4000,-6.9200,8.1700", "5.4000,-6.2800,8.1700", "5.5600,-7.5600,8.1700", "5.5600,-6.9200,8.1700",
	"5.5600,-6.2800,8.1700", "5.7200,-7.5600,8.1700", "5.7200,-6.9200,8.1700", "5.7200,-6.2800,8.1700",
	"5.8800,-7.5600,8.1700", "5.8800,-6.9200,8.1700", "5.9600,-6.9200,8.1700", "6.0400,-6.2800,8.1700",
	"6.2000,-6.9200,8.1700", "6.2800,-6.2800,8.1700", "6.4200,-7.5000,7.6000", "6.4400,-6.9200,8.1700",
	"6.5200,-6.2800,8.1700", "6.6000,-6.9200,8.1700", "6.6800,-6.9200,8.1700", "6.6800,-6.2800,8.1700",
	"6.8400,-6.9200,8.1700", "6.8400,-6.2800,8.1700", "8.2800,-7.5600,8.1700", "8.2800,-6.9200,8.1700",
	"8.2800,-6.2800,8.1700", "8.3600,-5.5600,8.3600", "8.5600,-7.5600,8.1700", "8.5600,-6.9200,8.1700",
	"8.5600,-6.2800,8.1700", "8.8000,-7.5600,8.1700", "8.8000,-6.9200,8.1700", "8.8000,-6.2800,8.1700",
	"9.1200,-7.5600,8.1700", "9.1200,-6.9200,8.1700", "9.1200,-6.2800,8.1700", "9.2000,-5.5200,8.3600",
	"9.4000,-7.5600,8.1700", "9.4000,-6.9200,8.1700", "9.4000,-6.2800,8.1700",
]

var _failed := false


func _ready() -> void:
	var m: EquipPickerMenu = EquipPickerMenu.new()
	m.autoplay_open = false
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- A. regression -----------------------------------------------------------
	var observed := _collect_positions(m)
	var golden := _parse_golden()
	_expect(observed.size() == golden.size(),
		"picker quad count drifted: observed %d vs golden %d" % [observed.size(), golden.size()])
	if observed.size() == golden.size():
		var worst := 0.0
		for i in observed.size():
			worst = maxf(worst, (observed[i] - golden[i]).length())
		_expect(worst < 0.001, "picker content drifted from golden (worst %.4f)" % worst)
	if _failed:
		# Deliberate-regen aid: the observed multiset in GOLDEN literal form. Paste ONLY
		# after confirming the drift is an intended layout change (never to silence a bug).
		print("[EquipPickerFrameGroupTest] observed multiset (GOLDEN format):")
		var line := ""
		for i in observed.size():
			line += "\"%.4f,%.4f,%.4f\", " % [observed[i].x, observed[i].y, observed[i].z]
			if (i + 1) % 4 == 0 or i == observed.size() - 1:
				print("\t" + line.strip_edges())
				line = ""

	# --- B. capability -----------------------------------------------------------
	# The movable origin IS the registered window element now (ADR-0088 migration).
	var origin: Node3D = m.window()
	if origin == null or not is_instance_valid(origin):
		_failed = true
		push_error("[EquipPickerFrameGroupTest] window element missing (grouping not built)")
	else:
		var before := _collect_positions(origin)
		_expect(before.size() > 0, "_frame_origin has no content children")
		var delta := Vector3(1.234, -0.567, 0.0)
		origin.position += delta
		var after := _collect_positions(origin)
		var ok := after.size() == before.size()
		if ok:
			for i in before.size():
				if ((after[i] - before[i]) - delta).length() >= 0.001:
					ok = false
					break
		_expect(ok, "picker content did not ride the frame origin move (content decoupled)")
		origin.position -= delta

	# --- Amendment 4 §2: the glove cursor's fixed home is an AUTHORED literal now
	# (was a derived([]) dead-end mirroring FRAME_HOME) — the repeatedly-pixel-tuned
	# home earns an editable equipicker.cursor.rect row. No empty-DERIVED audit gap.
	var cur := m.find_child("PickerGloveCursor", true, false) as UI3Element
	_expect(cur != null, "picker glove cursor element missing")
	if cur != null:
		var row := _rect_row(cur)
		_expect(row.get("source") == UI3Element.Source.AUTHORED,
			"equipicker.cursor must be an AUTHORED literal, got %s" % [row])
		_expect(String(row.get("slug")) == "equipicker.cursor.rect",
			"equipicker.cursor must mint equipicker.cursor.rect, got %s" % [row])

	# --- C. registration audit (ADR-0088 §8, piggybacked per-screen) --------------
	# The migrated picker must have ZERO unowned rendering payload — every mesh sits
	# under the window/cursor elements, and the tracked allowlist stays empty.
	var audit_errors: Array = UI3RegistrationAudit.check(m, UI3RegistrationAudit.load_allowlist())
	for e in audit_errors:
		_expect(false, "registration audit: %s" % e)

	m.queue_free()
	if _failed:
		push_error("[FAIL] EquipPickerFrameGroupTest")
		get_tree().quit(1)
	else:
		print("[PASS] EquipPickerFrameGroupTest")
		get_tree().quit(0)


func _rect_row(e: UI3Element) -> Dictionary:
	for r: Dictionary in e.criteria():
		if String(r["field"]) == "rect":
			return r
	return {}


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
	if not cond:
		_failed = true
		push_error("[EquipPickerFrameGroupTest] %s" % msg)
