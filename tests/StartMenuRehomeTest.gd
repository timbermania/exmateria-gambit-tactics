extends Node3D

## Guard (§15.23 in-place re-render / ADR-0088 Amendment 2 §4): the LIVE START menu
## RE-HOMES — `place_at(loc)` + `set_rows(rows)` on a built widget must render exactly
## what a menu BUILT FRESH at that home with those rows renders. §15.23 proves the ROM
## re-renders the SAME slot-6 window in place (the "Order Unit ghost" under "List"), so
## the port's window survives a sub-menu switch instead of teardown+rebuild.
##   - set_rows: content swap + selection reset to row 0 (oracle: glove on row 0), row
##     block re-mounted anchored on the FROZEN build container (rides the moved origin).
##   - place_at: the window origin carries the move; the frame chrome re-derives its
##     SIZE from the live home (START 84×96 → EQUIP 60×80) while its position stays
##     frozen-container-relative (a live-loc position eval would double-move).
##   - container_rect() answers the LIVE home (the transition guards pin EQUIP/ABILITY
##     containers on the settled sub-menus).
## Golden = a fresh menu built at the target home: multiset of every quad's world
## position (glove subtree excluded — per-vsync bob; its ELEMENT origin is compared).

const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")

var _failed := false


func _ready() -> void:
	# Golden multisets FIRST (one menu alive at a time, like the location sweep).
	var golden_equip := await _fresh_menu_multiset(StartActionMenu.LOC_EQUIP, StartActionMenu.ROWS_EQUIP)
	var golden_ability := await _fresh_menu_multiset(StartActionMenu.LOC_ABILITY, StartActionMenu.ROWS_ABILITY)

	# The live menu: built at the START home with the 5-item set, then re-homed.
	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	m.move_down()   # selection off row 0, so the reset is observable

	# --- re-home 1: START → EQUIP (the Item→Equip §15.23 switch) -------------------
	m.place_at(StartActionMenu.LOC_EQUIP)
	m.set_rows(StartActionMenu.ROWS_EQUIP)
	_expect(m.row_count() == 4, "set_rows(ROWS_EQUIP): row_count %d != 4" % m.row_count())
	_expect(m.selected_row() == 0, "set_rows must reset the selection to row 0, got %d" % m.selected_row())
	_expect(m.container_rect() == Rect2i(StartActionMenu.EQUIP_CONTAINER),
		"container_rect() must answer the LIVE home %s, got %s"
		% [Rect2i(StartActionMenu.EQUIP_CONTAINER), m.container_rect()])
	var fr := StartActionMenu.frame_rect_for(Rect2i(StartActionMenu.EQUIP_CONTAINER))
	var chrome = m.frame_element().chrome()
	_expect(chrome != null and chrome.frame_size == Vector2(fr.size),
		"frame chrome must re-derive its SIZE from the new home: want %s, got %s"
		% [Vector2(fr.size), chrome.frame_size if chrome != null else null])
	_expect(_positions(m) == golden_equip,
		"re-homed START→EQUIP menu must render exactly a fresh EQUIP-built menu")
	_expect(m.window().get_node("GloveCursor").global_position
			== Vector3(m.window().global_position),
		"the glove element origin must sit on the re-homed window origin")

	# --- re-home 2: EQUIP → ABILITY (repeated re-homing on the same instance) ------
	m.place_at(StartActionMenu.LOC_ABILITY)
	m.set_rows(StartActionMenu.ROWS_ABILITY)
	_expect(m.row_count() == 3, "set_rows(ROWS_ABILITY): row_count %d != 3" % m.row_count())
	_expect(m.container_rect() == Rect2i(StartActionMenu.ABILITY_CONTAINER),
		"container_rect() must answer the ABILITY home, got %s" % m.container_rect())
	_expect(_positions(m) == golden_ability,
		"re-homed EQUIP→ABILITY menu must render exactly a fresh ABILITY-built menu")

	# set_rows BEFORE _ready stays the plain preset (the fresh-build handshake).
	var pre := StartActionMenu.new()
	pre.set_rows(StartActionMenu.ROWS_EQUIP)
	_expect(pre.rows == StartActionMenu.ROWS_EQUIP, "pre-build set_rows must set the preset")
	pre.free()

	m.free()
	if _failed:
		push_error("[FAIL] StartMenuRehomeTest")
		get_tree().quit(1)
	else:
		print("[PASS] StartMenuRehomeTest")
		get_tree().quit(0)


## Build a menu FRESH at `loc` with `rows` (the pre-add_child handshake), capture its
## quad-position multiset, and free it — the independent golden a re-home must match.
func _fresh_menu_multiset(loc: String, rows: Array[String]) -> Array:
	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	m.location = loc
	m.rows = rows
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	var out := _positions(m)
	m.free()
	await get_tree().process_frame
	return out


func _positions(root: Node) -> Array:
	var out: Array = []
	_collect(root, out)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if not is_equal_approx(a.x, b.x): return a.x < b.x
		if not is_equal_approx(a.y, b.y): return a.y < b.y
		return a.z < b.z)
	return out


## Collect quad world positions, EXCLUDING the glove cursor subtree — the glove bobs
## per vsync (§15.20/ADR-0046); its ride is asserted via the element origin instead.
func _collect(n: Node, out: Array) -> void:
	if n.name == "GloveCursor":
		return
	if n is MeshInstance3D:
		out.append((n as MeshInstance3D).global_position)
	for c in n.get_children():
		_collect(c, out)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[StartMenuRehomeTest] %s" % msg)
