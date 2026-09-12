extends Node3D

## Guard (headful): the START action-menu (§15.20) migrated to ADR-0088 registered
## elements — the same model the equip picker proved (EquipPickerFrameGroupTest).
##   A. REGRESSION — every drawn quad lands on the exact pre-migration world position
##      (GOLDEN position multiset, captured from the hand-rolled build).
##   B. CAPABILITY — the menu exposes its registered window element (`window()`);
##      moving it moves frame chrome + rows + "Menu" title + glove by the same delta
##      (grab-the-menu, content included).
##   C. REGISTRATION AUDIT (ADR-0088 §8, piggybacked per-screen) — zero unowned
##      rendering payload under the menu; the tracked allowlist stays empty.
##   D. CONTAINER VARIANT — the window element's rect follows the host-set container
##      (the Equip sub-menu re-renders the SAME widget at EQUIP_CONTAINER, §15.23).

const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")

## Captured 2026-08-11 from the pre-migration build (throwaway golden-regen run of this
## guard's exact preamble: default container, autoplay_open=false, 2 settled frames).
## The migration behind it must be a visual no-op (ADR-0088 §9).
const GOLDEN := [
	"6.7200,-5.5200,6.8400", "6.8000,-5.6000,6.6500", "7.4400,-8.0000,6.4600", "7.4400,-7.3600,6.4600",
	"7.4400,-6.7200,6.4600", "7.4400,-6.0800,6.4600", "7.4400,-5.4400,6.4600", "7.4800,-4.9200,7.0300",
	"7.6000,-5.4400,6.4600", "7.6800,-8.0000,6.4600", "7.6800,-7.3600,6.4600", "7.6800,-6.7200,6.4600",
	"7.6800,-6.0800,6.4600", "7.7600,-5.4400,6.4600", "7.8400,-8.0000,6.4600", "7.8400,-7.3600,6.4600",
	"7.8400,-6.7200,6.4600", "7.8400,-6.0800,6.4600", "7.9200,-6.0800,6.4600", "7.9200,-5.4400,6.4600",
	"8.0000,-8.0000,6.4600", "8.0000,-6.7200,6.4600", "8.0000,-6.0800,6.4600", "8.0800,-7.3600,6.4600",
	"8.0800,-6.0800,6.4600", "8.1600,-8.0000,6.4600", "8.1600,-6.7200,6.4600", "8.2400,-7.3600,6.4600",
	"8.2400,-6.0800,6.4600", "8.3200,-6.7200,6.4600", "8.3600,-6.6200,6.0800", "8.4000,-7.3600,6.4600",
	"8.4800,-8.0000,6.4600", "8.6400,-6.7200,6.4600", "8.7200,-8.0000,6.4600", "8.7200,-7.3600,6.4600",
	"8.8800,-8.0000,6.4600", "8.8800,-6.7200,6.4600", "8.9600,-8.0000,6.4600", "8.9600,-7.3600,6.4600",
	"9.0400,-6.7200,6.4600", "9.1200,-7.3600,6.4600", "9.2000,-7.3600,6.4600",
]

var _failed := false


func _ready() -> void:
	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- A. regression -----------------------------------------------------------
	var observed := _collect_positions(m)
	var golden := _parse_golden()
	_expect(observed.size() == golden.size(),
		"start-menu quad count drifted: observed %d vs golden %d" % [observed.size(), golden.size()])
	if observed.size() == golden.size():
		var worst := 0.0
		for i in observed.size():
			worst = maxf(worst, (observed[i] - golden[i]).length())
		_expect(worst < 0.001, "start-menu content drifted from golden (worst %.4f)" % worst)
	if _failed:
		# Deliberate-regen aid: the observed multiset in GOLDEN literal form. Paste ONLY
		# after confirming the drift is an intended layout change (never to silence a bug).
		print("[StartMenuFrameGroupTest] observed multiset (GOLDEN format):")
		var line := ""
		for i in observed.size():
			line += "\"%.4f,%.4f,%.4f\", " % [observed[i].x, observed[i].y, observed[i].z]
			if (i + 1) % 4 == 0 or i == observed.size() - 1:
				print("\t" + line.strip_edges())
				line = ""

	# --- B. capability -----------------------------------------------------------
	# The movable origin IS the registered window element (ADR-0088 migration).
	if not m.has_method("window"):
		_failed = true
		push_error("[StartMenuFrameGroupTest] window() missing — menu not migrated to a registered element")
	else:
		var origin: Node3D = m.call("window")
		if origin == null or not is_instance_valid(origin):
			_failed = true
			push_error("[StartMenuFrameGroupTest] window element missing (grouping not built)")
		else:
			var before := _collect_positions(origin)
			_expect(before.size() > 0, "window element has no content children")
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
			_expect(ok, "menu content did not ride the window element move (content decoupled)")
			origin.position -= delta

	# --- Amendment 4 §2: the glove cursor answers at(location) sharing the WINDOW's
	# key-location slug (was a derived([]) dead-end over a frozen `c` capture) — so it
	# reads as AT_LOCATION named after the same home and re-homes live with the window.
	var cur := m.find_child("GloveCursor", true, false) as UI3Element
	_expect(cur != null, "start-menu glove cursor element missing")
	if cur != null:
		var row := _rect_row(cur)
		_expect(row.get("source") == UI3Element.Source.AT_LOCATION,
			"startmenu.cursor must answer at(location) → AT_LOCATION, got %s" % [row])
		_expect(String(row.get("slug")).begins_with("startmenu.loc."),
			"startmenu.cursor must ride the window's startmenu.loc.* namespace, got %s" % [row])
		_expect(String(row.get("slug")) == m.location,
			"startmenu.cursor must share the WINDOW's selected location (%s), got %s"
			% [m.location, row.get("slug")])

	# --- C. registration audit (ADR-0088 §8) --------------------------------------
	var audit_errors: Array = UI3RegistrationAudit.check(m, UI3RegistrationAudit.load_allowlist())
	for e in audit_errors:
		_expect(false, "registration audit: %s" % e)
	m.queue_free()

	# --- D. location variant (§15.23: same widget, host-picked KEY LOCATION — the
	# set-`container` handshake retired by ADR-0088 Amendment 2 §4) ------------------
	var m2: StartActionMenu = StartActionMenu.new()
	m2.autoplay_open = false
	m2.rows = StartActionMenu.ROWS_EQUIP
	m2.location = StartActionMenu.LOC_EQUIP
	add_child(m2)
	await get_tree().process_frame
	if m2.has_method("window"):
		var w: UI3Element = m2.call("window")
		_expect(w != null and w.rect() == Rect2(StartActionMenu.EQUIP_CONTAINER),
			"window element rect %s does not follow the host location %s"
			% [w.rect() if w != null else Rect2(), StartActionMenu.EQUIP_CONTAINER])
		_expect(w.aperture() == Rect2i(StartActionMenu.EQUIP_CONTAINER),
			"settled aperture %s != the Equip container" % w.aperture())
	m2.queue_free()

	if _failed:
		push_error("[FAIL] StartMenuFrameGroupTest")
		get_tree().quit(1)
	else:
		print("[PASS] StartMenuFrameGroupTest")
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
		push_error("[StartMenuFrameGroupTest] %s" % msg)
