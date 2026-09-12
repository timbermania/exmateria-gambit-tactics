extends Node
## The START menu's Move row — [WorldMapPlaceList] against WORLD_MAP_SCREEN.md §33.3 row 0.
##
## [b]What makes this a real check and not a tautology.[/b] The list's RULE comes from
## §33.3, which read `FUN_80105E04` walking `n = 0..0x2A` and keeping `var[0x200 + n] != 0`
## — and the flags it walks are the same reveal bits §29.4 found by an entirely separate
## route (43 nodes x 3 savestates, zero mismatches), which `WorldMapProgressTest` already
## pins. So the expectations here (nodes 3 / 7 / 25 on the ss1 opening, party on 7) are a
## measurement, and the code path under them is a rule read off the disassembly. Neither
## side was written from the other.
##
## The record's own numbers come from `tools/parse_world_map.py` reading WORLD.BIN window
## record 6 off the disc; the wants below are transcribed from §33.3 and from the record
## table §33.2 prints.
##
## Run: <GODOT> --path . --quit-after 12 res://tests/WorldMapPlaceListTest.tscn

## WORLD.BIN window record 6. `h` is 0 on disc — the driver sizes it from the row count.
const WANT_ORIGIN := Vector2i(-64, -72)
const WANT_W := 128
const WANT_VISIBLE := 7
const WANT_PITCH := 16
const WANT_CLOSE := 1
const WANT_HELP := 17
## Every row of record 6's table is `0x100D`; `FUN_800EBB08` strips `0x1000` as a
## presentation flag, so every row opens window 13 — the record whose handler is the pick.
const WANT_OPENS := 13
## §29.4 / §30: the opening save knows nodes {2, 6, 24} zero-based, and the marker is on 6.
const WANT_LIST := [3, 7, 25]
const WANT_PARTY := 7

var _passed := 0
var _failed := 0
var _assets: WorldMapAssets
var _list: WorldMapPlaceList


func _ready() -> void:
	_assets = WorldMapAssets.new()
	if not _assets.load_all():
		print("[FAIL] WorldMapPlaceListTest — assets: %s" % _assets.error)
		get_tree().quit(1)
		return
	_list = WorldMapPlaceList.new()
	if not _list.setup(_assets, WorldMapPrimitives.new(_assets),
			WorldMapProgress.ss1_fixture()):
		print("[FAIL] WorldMapPlaceListTest — model.json has no place_list block")
		get_tree().quit(1)
		return
	add_child(_list)

	_check_record()
	_check_the_walk()
	_check_the_refused_row()
	_check_pick_lands_in_the_walk()
	_check_wrap_and_scroll()

	if _failed > 0:
		print("[FAIL] WorldMapPlaceListTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapPlaceListTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


func _check_record() -> void:
	_eq("window origin", _list.origin(), WANT_ORIGIN)
	_eq("window width", int(_list.record["w"]), WANT_W)
	_eq("h is 0 on disc — the driver sizes it", int(_list.record["h"]), 0)
	_eq("rows visible at a time", int(_list.record["visible_rows"]), WANT_VISIBLE)
	_eq("row pitch", int(_list.record["row_pitch"]), WANT_PITCH)
	_eq("levels closed on X", int(_list.record["close_levels"]), WANT_CLOSE)
	_eq("SELECT help topic", int(_list.record["help_topic"]), WANT_HELP)
	var opens: Array = Array(_list.record["opens"])
	_eq("one table entry per visible row", opens.size(), WANT_VISIBLE)
	var all_pick := true
	for w in opens:
		if int(w) != WANT_OPENS:
			all_pick = false
	_eq("every row opens window %d after the 0x1000 flag is stripped" % WANT_OPENS,
			all_pick, true)
	_eq("...which is what the model calls the pick window",
			int(_list.record["pick_window"]), WANT_OPENS)


## `FUN_80105E04` walks ALL 43 nodes, not the drawn ones and not the routed ones.
func _check_the_walk() -> void:
	_eq("the ss1 list", _list.nodes, WANT_LIST)
	_eq("...is the whole of it", _list.rows(), WANT_LIST.size())
	# The rule, not the fixture: flip one flag and the list must follow it.
	var p := WorldMapProgress.ss1_fixture()
	p.set_node_known(40)                                # node 41, 1-based
	_eq("a newly known node joins the list",
			WorldMapPlaceList.known_nodes(p), [3, 7, 25, 41])
	p.set_node_known(2, false)
	_eq("...and an unknown one leaves it",
			WorldMapPlaceList.known_nodes(p), [7, 25, 41])
	# All 43 known is the walk's upper bound and the only case that scrolls.
	var all_p := WorldMapProgress.ss1_fixture()
	for n in WorldMapProgress.NODE_COUNT:
		all_p.set_node_known(n)
	_eq("every node known is 43 rows",
			WorldMapPlaceList.known_nodes(all_p).size(), WorldMapProgress.NODE_COUNT)


## §33.3: the walk marks the row where `n == var[0x31]` with a 4, and `FUN_80105F7C`
## REFUSES that row. It is on the list and cannot be taken — a reading that drops it
## instead would be one row shorter and renumber everything under it.
func _check_the_refused_row() -> void:
	var at := _list.nodes.find(WANT_PARTY)
	_eq("the party's node is ON the list", at >= 0, true)
	_eq("...and its row is refused", _list.is_refused(at), true)
	for r in _list.rows():
		if r != at:
			_eq("row %d is not refused" % r, _list.is_refused(r), false)

	var picks: Array[int] = []
	_list.picked.connect(func(n: int) -> void: picks.append(n))
	_list.row = at
	_list.confirm()
	_eq("confirming the refused row emits nothing", picks.size(), 0)
	_list.row = 0 if at != 0 else 1
	_list.confirm()
	_eq("confirming any other row emits its node", picks, [_list.node_at(_list.row)])

	# ...and it is DRAWN like every other row. `WORLD.BIN` materialises the per-row flag
	# array `0x8016E500` in exactly two places — the walk that writes it (`0x80105E20`)
	# and one `lh` + `beq ...,4` in the pick (`0x80105FA0`) — with no `lui rX,0x8016` and
	# no `ori ...,0xE500` anywhere in the overlay to alias it. The flag never reaches the
	# renderer, so the refusal is silent AND invisible, and a port that dims the row is
	# inventing feedback the console does not give. See [WorldMapPlaceList]'s class note.
	_list.row = at
	_list._build()
	var refused_quads := _row_quads(at)
	var other := 0 if at != 0 else 1
	var plain_quads := _row_quads(other)
	_eq("the refused row draws SOME quads at all", refused_quads.size() > 0, true)
	_eq("...as many as any other row", refused_quads.size(), plain_quads.size())
	var same := true
	for q in refused_quads:
		if int(q["rgb"]) != WorldMapPrimitives.DEFAULT_RGB:
			same = false
	_eq("...at the console's own 1.0x modulation, undimmed", same, true)
	var cluts_match := true
	for i in refused_quads.size():
		if int(refused_quads[i]["clut"]) != int(plain_quads[i]["clut"]):
			cluts_match = false
	_eq("...through the same CLUT as an ordinary row", cluts_match, true)


## The quads the list's own generator emits for the node-name cel on row [param r].
func _row_quads(r: int) -> Array:
	var gen := WorldMapPrimitives.new(_assets)
	var cid := _assets.static_cel(
			_list.node_at(r) + WorldMapPrimitives.NAME_FRAME_BASE)
	return gen.cel_quads(cid, _list.row_top_left(r)) if cid >= 0 else []


## ADR-0117 dec. 8 / §33.10 point 2: Move ends in `FUN_8008E2BC`, the SAME departure ○
## over a node already ends in. The list's whole output is a node id, and every id it can
## emit has to be one the existing walk can plan — otherwise it would be a second
## mechanism wearing the first one's name.
func _check_pick_lands_in_the_walk() -> void:
	var p := WorldMapProgress.ss1_fixture()
	var ok := true
	for r in _list.rows():
		var n := _list.node_at(r)
		if n == p.party_node():
			continue                                    # refused; never reaches the walk
		if WorldMapTravel.plan(_assets, p, p.party_node(), n) == null:
			ok = false
	_eq("every takeable row is a node the existing walk can plan", ok, true)


func _check_wrap_and_scroll() -> void:
	_list.row = 0
	_list.move(-1)
	_eq("up from row 0 wraps to the last", _list.row, _list.rows() - 1)
	_list.move(1)
	_eq("down from the last wraps to 0", _list.row, 0)
	# A three-row list never scrolls; the 43-row one is the case that does.
	_eq("a short list is not scrolled", _list.top, 0)
	_eq("...and shows every row", _list.visible_rows(), _list.rows())

	var all_p := WorldMapProgress.ss1_fixture()
	for n in WorldMapProgress.NODE_COUNT:
		all_p.set_node_known(n)
	var big := WorldMapPlaceList.new()
	big.setup(_assets, WorldMapPrimitives.new(_assets), all_p)
	_eq("43 rows still show only the record's %d" % WANT_VISIBLE,
			big.visible_rows(), WANT_VISIBLE)
	var inside := true
	big.row = 0
	big.top = 0
	for _i in WorldMapProgress.NODE_COUNT + 3:
		big.move(1)
		if big.row < big.top or big.row >= big.top + big.visible_rows():
			inside = false
	_eq("the cursor stays inside the visible window all the way round", inside, true)
	_eq("...and the window never runs past the end",
			big.top <= WorldMapProgress.NODE_COUNT - WANT_VISIBLE, true)
	big.free()


func _eq(what: String, got: Variant, want: Variant) -> void:
	var g: Variant = Array(got) if got is Array else got
	var w: Variant = Array(want) if want is Array else want
	if str(g) == str(w):
		_passed += 1
		return
	_failed += 1
	print("  [x] %s: got %s, want %s" % [what, g, w])
