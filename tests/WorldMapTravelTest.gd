extends Node
## The traversal, against §29.6 — the walk that was actually WATCHED on the console.
##
## That section drove `ss1` to node 2, pressed ○ once, and recorded 2,709 vsyncs
## (`round12_walk_trace.csv`). `travel.py walk 6 2` predicts the same walk from
## `WLDCORE.BIN` alone and the two agree waypoint for waypoint. The literals below are
## the console's, transcribed from §29.6's own table — so this asserts the PORT against
## the recording, not against itself.
##
## [codeblock]
## v227  ○ pressed, heading set, frame list still 16
## v228  frame list 26 — the FAST bank engages, the marker starts moving
## v272  marker node 6 -> 24, route 3 hands off to route 1
## v321  marker node 24 -> 2.  94 vsyncs, two routes, twelve waypoints
## [/codeblock]
##
## ⚠ What this does NOT assert: the per-vsync rounding of the interpolation BETWEEN
## waypoints. Fitting nine candidate models against the trace put the best at 73 of 95
## vsyncs exact and the rest within 1 px; every waypoint ARRIVAL, heading, frame list and
## leg duration is exact under it. See [method WorldMapTravel.step].
##
## Run: <GODOT> --path . --quit-after 4 res://tests/WorldMapTravelTest.tscn

## §29.6's table, both routes, in traversal order. Twelve of twelve.
const HEADINGS := [951, 1183, 1407, 1362, 1078, 1799, 1326, 1183, 1643, 2140, 2311, 2129]
const FRAME_LISTS := [26, 26, 27, 27, 26, 28, 27, 26, 27, 28, 29, 28]
## v227 -> v321.
const WALK_VSYNCS := 94
## 1-based. Gariland Magic City is node 7 (index 6), Igros Castle node 3 (index 2).
const GARILAND := 7
const IGROS := 3
const MANDALIA := 25

var _passed := 0
var _failed := 0
var _assets: WorldMapAssets


func _ready() -> void:
	_assets = WorldMapAssets.new()
	if not _assets.load_all():
		print("[SKIP] WorldMapTravelTest — %s" % _assets.error)
		get_tree().quit(0)
		return
	_test_path()
	_test_legs()
	_test_duration()
	_test_walk()
	_test_refusals()

	if _failed > 0:
		print("[FAIL] WorldMapTravelTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapTravelTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


func _p() -> WorldMapProgress:
	return WorldMapProgress.new_campaign()


## §29.6: "two routes, both reversed". `travel.py walk 6 2` gives [(3, True), (1, True)].
func _test_path() -> void:
	var hops := WorldMapTravel.route_path(_assets, _p(), GARILAND, IGROS)
	_eq("Gariland -> Igros is route 3 then route 1, both reversed", hops,
			[[3, true], [1, true]])
	var back := WorldMapTravel.route_path(_assets, _p(), IGROS, GARILAND)
	_eq("and the return trip is the same two, forward", back, [[1, false], [3, false]])


## The twelve legs, each with the heading and frame list the console showed.
func _test_legs() -> void:
	var t := WorldMapTravel.plan(_assets, _p(), GARILAND, IGROS)
	if t == null:
		_fail("no walk planned")
		return
	_eq("twelve waypoints", t.legs.size(), HEADINGS.size())
	if t.legs.size() != HEADINGS.size():
		return
	var h: Array = []
	var f: Array = []
	for leg in t.legs:
		h.append(int(leg["heading"]))
		f.append(WorldMapTravel.frame_list_for(int(leg["heading"]), true))
	_eq("the twelve headings", h, HEADINGS)
	_eq("the twelve frame lists", f, FRAME_LISTS)
	# §29.6: "0x800D0B30 is the CURRENT ROUTE's waypoint count, not the path's" — 5 then
	# 7, and nothing in the trace ever holds "2 hops".
	_eq("route 3 contributes 5 legs and route 1 contributes 7",
			[_leg_count(3, true), _leg_count(1, true)], [5, 7])
	# The fast bank is the only one entered — the slow bank 16..23 never appears.
	var slow := 0
	for fl in f:
		if fl < WorldMapTravel.FAST_BANK:
			slow += 1
	_eq("the slow bank is never entered", slow, 0)


func _leg_count(r: int, reversed: bool) -> int:
	return WorldMapTravel._legs_of(_assets, r, reversed).size()


## Σ (2·d + 1) over the twelve legs must be the 94 vsyncs the recording measured.
func _test_duration() -> void:
	var t := WorldMapTravel.plan(_assets, _p(), GARILAND, IGROS)
	_eq("the walk is 94 vsyncs", t.total_ticks(), WALK_VSYNCS)
	# 1.6 s at 60 Hz, which is what §29.6 states.
	_eq("which is 1.6 s", snappedf(WALK_VSYNCS / 60.0, 0.1), 1.6)


## Step it to completion and check where it goes, and where it is on the way.
func _test_walk() -> void:
	var t := WorldMapTravel.plan(_assets, _p(), GARILAND, IGROS)
	var start: Vector2i = _map_of(GARILAND)
	_eq("it starts on Gariland's own map position", t.position, start)
	# §29.6: the heading is set one vsync BEFORE the bank switches — v227 shows frame
	# list 16 with the heading already 951.
	_eq("the first rendered frame still shows the idle bank", t.frame_list(),
			WorldMapTravel.SLOW_BANK)
	_eq("with the first leg's heading already set", t.heading, HEADINGS[0])

	# Every waypoint arrival, in order. A leg is 2*d steps then one held vsync, so the
	# marker is standing on waypoint k after Σ(2d+1) of the first k legs.
	var ticks := 0
	var seen_headings: Array = []
	for i in t.legs.size():
		var leg: Dictionary = t.legs[i]
		var want: Vector2i = leg["to"]
		var n: int = int(leg["steps"]) + 1
		for _s in n:
			t.step()
			ticks += 1
		if t.position != want:
			_fail("waypoint %d: at %s, want %s" % [i, t.position, want])
			return
		seen_headings.append(int(leg["heading"]))
	_pass("all twelve waypoint arrivals land exactly")
	_eq("it took the whole 94 vsyncs", ticks, WALK_VSYNCS)
	_eq("the headings came in the console's order", seen_headings, HEADINGS)
	_true("the walk is finished", t.finished)
	_eq("and it ends on Igros Castle's map position", t.position, _map_of(IGROS))
	_eq("reporting arrival at Igros", t.at_node, IGROS)
	_eq("and dropping back to the idle bank", t.frame_list(), WorldMapTravel.SLOW_BANK)
	# Mandalia is the hand-off node halfway: the marker must pass exactly through it.
	var mid := WorldMapTravel.plan(_assets, _p(), GARILAND, MANDALIA)
	_eq("Gariland -> Mandalia is route 3 alone", mid.legs.size(), 5)


## What it must refuse. §21.2's cursor is free, so `_confirm` can aim at nothing at all;
## and the graph is restricted to routes whose BOTH endpoints the party knows.
func _test_refusals() -> void:
	var p := _p()
	_eq("no path to an unknown node",
			WorldMapTravel.route_path(_assets, p, GARILAND, 1), [])
	_eq("no path from nothing", WorldMapTravel.route_path(_assets, p, 0, IGROS), [])
	_eq("no path to itself", WorldMapTravel.route_path(_assets, p, IGROS, IGROS), [])
	_true("and plan() returns null rather than an empty walk",
			WorldMapTravel.plan(_assets, p, GARILAND, 1) == null)


func _map_of(node_1based: int) -> Vector2i:
	var n: Dictionary = _assets.node(node_1based - 1)
	return Vector2i(int(n["map"][0]), int(n["map"][1]))


func _eq(what: String, got: Variant, want: Variant) -> void:
	if str(got) == str(want):
		_passed += 1
		return
	_failed += 1
	print("  FAIL %s: got %s, want %s" % [what, got, want])


func _true(what: String, ok: bool) -> void:
	if ok:
		_passed += 1
		return
	_failed += 1
	print("  FAIL %s" % what)


func _pass(what: String) -> void:
	_passed += 1
	print("  ok   %s" % what)


func _fail(msg: String) -> void:
	_failed += 1
	print("  FAIL %s" % msg)
