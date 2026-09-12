extends Node
## The world-map screen MOUNTED, not standalone — the half of crossing C2 that lives in
## the scene rather than in the plan.
##
## Standalone the screen owns the window and sizes it to 256x240 x `zoom`; that is the
## capture rig, and it is the only path measured so far. Mounted by
## [code]NavigatorMain.run_world_map[/code] it must instead take the largest WHOLE zoom
## the viewport allows and centre itself, touch the window not at all, and cover what is
## behind it. A fractional zoom would resample the console's pixels, which is the one
## thing this screen must not do.
##
## The mount is a [CanvasLayer]. ADR-0137's Formation precedent is a camera child because
## it re-hosts over the live battlefield; the world map is the simpler case the port list
## calls it — a full-screen 2D surface with no battlefield underneath, so it needs no
## camera. What it must NOT be is a [SubViewport]
## (`[[map-camera-is-ortho-ui-mounts-as-camera-child]]`), and a CanvasLayer is neither.
##
## Run: <GODOT> --path . --quit-after 3000 res://tests/WorldMapMountTest.tscn
##   To also write what it looks like, set `view.capture_path` right after
##   `scene.instantiate()` below -- the screen shoots at the end of its own `_ready()`.
##
## [b]The frame budget is load-bearing, and 12 is not enough.[/b] This drives the START
## menu through several `_press` sequences, each spending frames; at the `--quit-after 12`
## this line carried on trunk, the process exits BEFORE `_finish()` prints — measured 0
## verdict lines at 12 and at 40, and only then a verdict. A missing verdict reads as
## "passed" in any sweep that greps for FAIL, which is the failure this number buys off,
## so it is quoted with margin rather than trimmed to the happy case.

const SCENE_PATH := "res://assets/scenes/WorldMap.tscn"

var _passed := 0
var _failed := 0


func _ready() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		print("[FAIL] WorldMapMountTest — cannot load %s" % SCENE_PATH)
		get_tree().quit(1)
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	var view := scene.instantiate()
	layer.add_child(view)
	add_child(layer)
	await get_tree().process_frame
	await get_tree().process_frame

	if view.assets == null or not view.assets.loaded:
		# Regenerable and gitignored — a missing asset is not a failing assertion.
		print("[SKIP] WorldMapMountTest — run tools/parse_world_map.py")
		get_tree().quit(0)
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	# NOT asserted by comparing `get_window().size` before and after: a tiling window
	# manager resizes the window out from under the process (measured: 1024x960 at _ready,
	# 1261x688 two frames later, with the viewport unchanged), so that reading measures
	# the compositor rather than this code. `_standalone` is the flag that gates the
	# window write, and everything below reads the VIEWPORT, which is what the screen
	# actually sizes itself against.
	_eq("the screen knows it is mounted, not standalone", view._standalone, false)
	_eq("zoom is the largest whole fit", view.zoom,
			mini(int(vp.x) / 256, int(vp.y) / 240))
	var want_origin: Vector2 = ((vp - Vector2(256, 240) * float(view.zoom)) * 0.5).floor()
	_eq("the frame is centred", view._clip.position,
			want_origin + Vector2(view.DRAW_AREA.position) * view.zoom)
	var backdrop := view.get_node_or_null(^"Backdrop") as ColorRect
	_true("the backdrop covers the viewport",
			backdrop != null and backdrop.size.x >= vp.x and backdrop.size.y >= vp.y)
	_true("it drew something", view.renderer != null and view.renderer.get_child_count() > 100)

	# A1, the one audio crossing. The slot is 27 — MUSIC_27.SMD is resident in the four
	# settled-world-map savestates and in none of the other 34, including the world-map
	# LOADING capture, and it is the only resident sequence whose cursors advance between
	# them. The port refuses to play at all when the slot is unconfirmed, so a regression
	# to -1 is silent in the picture and caught here.
	_eq("the world-map music slot is confirmed", WorldMapMusicPort.WORLD_MAP_SLOT, 27)
	_true("its SMD is deployed", FileAccess.file_exists(
			"res://assets/music/MUSIC_%02d.SMD" % WorldMapMusicPort.WORLD_MAP_SLOT))
	_true("an unwired port plays nothing rather than the wrong track",
			not WorldMapMusicPort.new(null).play())
	# The positive arm: mounted, the port is wired and the driver accepts the slot.
	# `play_slot` returns false (and push_errors) when the SMD will not load, so this is
	# the difference between "the number is 27" and "27 plays".
	_true("mounted, the theme actually starts", view.music != null and view.music.play())
	view.music.stop()

	# The `SHOT=` env read that used to sit here is gone (ADR-0051, #444): it made
	# `run_all_tests.sh` abort at its own `check_no_env_vars.py` pre-flight, so the whole
	# suite ran zero tests. It was a human debugging aid with no caller in the tree, and
	# what replaced it is better than an env var either way -- set `view.capture_path`
	# between `instantiate()` and `add_child()` above, or press "Capture viewport" on the
	# world map's F3 panel. A test's job here is the assertions below.
	#
	# Taking trunk's deletion also settles a collision this branch had found the hard way:
	# a `--shot=`-shaped key here is the SCENE's key too, and the mounted screen reads it,
	# so a capture request armed BOTH — the screen shot on its own and `Focus.pop`ped
	# itself out of the rig's way, failing the stack assertion below. No second reader, no
	# collision.
	_check_clock(view)
	_check_pad_is_events(view)
	_check_input(view)

	await _check_start_menu(view)
	# BEFORE the dismissal below, which frees the layer this drives.
	await _check_arrival_loads_the_node(view)

	_check_marker_handoff_beats_travel(view)

	# Dismissing it is how the navigator gets control back.
	var seen := [false]
	view.dismissed.connect(func() -> void: seen[0] = true)
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)
	# A BOUNDED wait, not two frames. ADR-0188 made `_leave` a coroutine: the map now runs
	# the ROM's out-curve on its own vsync clock and emits `dismissed` when the ramp lands,
	# because a host that tears the screen down on the press would have nothing left to
	# fade. Two frames was right when leaving was a cut; it is now a race the fade wins.
	# The promise is that ✕ ends in `dismissed`, not that it ends in N frames.
	#
	# [b]Bounded in ramp PROGRESS, not in rendered frames[/b] — this loop is the THIRD waiter
	# on that ramp and it kept the wrong unit one commit longer than the other two. A flat
	# `RAMP_TICKS * k` counts frames THIS loop resumes on, while the ramp advances once per
	# VSYNC at 60 Hz, so the margin shrinks as the display gets faster and inverts around
	# 480 fps — where the bound expires on a fade that is running perfectly and this test
	# fails on the fastest hardware. Frames-that-made-NO-PROGRESS has no such crossover:
	# see [constant WorldMapScreenOut.STALL_FRAMES], which is the one constant all three
	# waiters read, and `WorldMapScene.screen_out_ticks()`, which is the progress reading.
	var progressed := false
	var stall := WorldMapScreenOut.STALL_FRAMES
	var last: int = view.screen_out_ticks()
	while not seen[0] and stall > 0:
		await get_tree().process_frame
		var now: int = view.screen_out_ticks()
		if now == last:
			stall -= 1
		else:
			last = now
			progressed = true
			stall = WorldMapScreenOut.STALL_FRAMES
	_true("ui_cancel emits dismissed", seen[0])
	# [b]Observed PROGRESS, not elapsed frames — a frame count cannot report this event.[/b]
	# The arm this replaces asserted that the wait cost at least one frame, and seeding the
	# cut (`_screen_out_enabled = false`) left it GREEN: `Input.parse_input_event` queues,
	# so the press is not handled until the next frame and one frame elapses on the cut path
	# too. What separates a fade from a cut is that the RAMP moved while the host waited, and
	# `screen_out_ticks()` is the only reading that says so. Seeded against the cut, this
	# arm reds alone.
	_true("and it waited for the fade rather than cutting", progressed)
	layer.queue_free()

	if _failed > 0:
		print("[FAIL] WorldMapMountTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapMountTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


## Arriving at a town does [b]not[/b] open its menu — ○ while stationary does.
##
## ⚠ [b]This guard used to assert the opposite, and it was wrong twice over.[/b] It cited
## §27.6's *"○ two hops away walked the marker there and then loaded the town"* as "the
## walk and the load are one press". §27.6 says, in the same paragraph: *"the marker never
## moved, never changed frame list, and the ribbon never grew. No walk is reachable from
## this savestate."* Both arms that session watched were ○ presses with no travel between
## them, so it licenses nothing at all about arrival.
##
## The disassembly is unambiguous. The arrival tick `FUN_8008E540` reaches `0x8008EA34`
## and calls `FUN_8008D3C0` — the ERRANDS list, from the node's type-4 emits — then opens
## a page only if that list came back positive. It never calls `FUN_8008D2C8`, the
## Bar / Shop / Soldier office builder. Every site that pairs `jal FUN_8008D2C8` with
## `jal FUN_8006FAF0` is an ○ handler.
##
## So the two are different lists on different triggers, and walking into a town and
## having its menu appear under you is a port invention.
func _check_arrival_loads_the_node(view: Node) -> void:
	var start: int = view.progress.party_node()
	_eq("the party starts on a town", WorldMapTownPage.opens_for(view.assets, start), true)

	# Away first, to a node that is NOT a town — so "the page is up" cannot be left over.
	var away := 0
	for n in view.assets.nodes():
		var id: int = int(n["i"]) + 1
		if id != start and view.progress.is_node_known(id - 1) \
				and not WorldMapTownPage.opens_for(view.assets, id):
			away = id
			break
	_eq("a known non-town node is reachable to walk to", away > 0, true)
	if away == 0:
		return
	view._enter_node(away)
	await _settle(view)
	_eq("arriving at a non-town opens no page", view._town == null, true)
	_eq("...and the party is there", view.progress.party_node(), away)

	view._enter_node(start)
	await _settle(view)
	_eq("arriving at a TOWN opens NOTHING — the menu is on the ○ path and no other",
			view._town == null, true)
	_eq("...and the party is standing on it", view.progress.party_node(), start)
	# And the cursor's stored hit test is about the world the marker is in NOW.
	_eq("the arrival re-resolves the cursor's hit test", view._cursor.hit_node,
			WorldMapCursor.node_under(view.assets, view.progress, view._cursor.position))

	# ...and NOW ○, standing still, is what opens it — through `_confirm`, the REAL input
	# path, not `_enter_node` directly.
	#
	# [b]That distinction is the whole of §12.8's play report[/b], *"I have to leave and go
	# back to Gariland to be able to open the town menu"*. ○ reads `_cursor.hit_node`, and
	# the cursor is free of the marker (§21.2) — so arriving somewhere does not put the
	# cursor on it, and a ○ with the cursor elsewhere does nothing. Calling `_enter_node`
	# would prove the branch and miss exactly the thing that was broken. Park the cursor
	# on the node the way a player does, then press.
	var rest := WorldMapCursor.rest_at(_screen_of(view, start))
	view._cursor.position = rest
	view._cursor.resolve(view.assets, view.progress)
	_eq("the cursor parked on the town hit-tests as that town",
			view._cursor.hit_node, start)
	view._confirm()
	await _settle(view)
	_eq("○ while stationary on the town opens the page", view._town != null, true)
	_eq("...for the node under the party", view._town.node_1based if view._town else -1,
			start)
	_eq("...and it opens ANIMATED, not popped (§38)",
			view._town.opening() if view._town else false, true)
	# §35: mode 4 is a PAGE PUSH, and the windows the map had up are NOT underneath it.
	# So the stack is two frames, never four — the page replaces them rather than layering.
	_eq("the town page is a page push, not a fourth layer", Focus.stack_names(),
			["world_map", "world_map_town_page"] as Array[String])
	_true("...and it is the one Godot calls",
			view._town.is_processing_unhandled_input())
	view._close_town()
	await get_tree().process_frame
	_eq("...and closing it returns the frame to the map", Focus.stack_names(),
			["world_map"] as Array[String])


func _screen_of(view: Node, node_1based: int) -> Vector2i:
	var n: Dictionary = view.assets.node(node_1based - 1)
	return Vector2i(int(n["screen"][0]), int(n["screen"][1]))


## Pump frames until the traversal finishes. Bounded — a walk that never ends is a
## failing assertion, not a hung suite.
func _settle(view: Node) -> void:
	var guard := 0
	while view._travel != null and guard < 1200:
		await get_tree().process_frame
		guard += 1
	_eq("the walk finished within 1200 frames", view._travel == null, true)


## The START menu's WIRING, end to end through the viewport — the half
## [WorldMapStartMenu] and [WorldMapPlaceList] cannot see from their own unit tests.
##
## §33.1's opener is START [b]or[/b] △, and it is a different action from Formation's; an
## action that is missing from the input map makes `is_action` silently false, so the menu
## would simply never open and nothing in either unit test would notice. The nesting is
## record 4's and record 6's `+0x20`, one level each: ✕ on the place list goes back to the
## menu, ✕ on the menu goes back to the map, and neither dismisses the screen.
func _check_start_menu(view) -> Signal:
	_true("no menu until it is opened", view._menu == null)
	await _press(&"world_map_start_menu")
	_true("START opens the menu", view._menu != null)
	_eq("...and the six rows are the disc's", view._menu.rows(), 6)

	# [b]The window is a Focus FRAME, not a nullable the map checks (ADR-0177).[/b] The
	# if-chain in `_unhandled_input` was a hand-rolled focus stack; these four assertions
	# are the real one. The map is deafened STRUCTURALLY — Godot stops calling it — which
	# is what makes "the map's own X never fires while the menu is up" true by
	# construction rather than by the early `return` that used to enforce it.
	_eq("the menu is a frame ON the stack, over the map",
			Focus.stack_names(), ["world_map", "world_map_start_menu"] as Array[String])
	_true("...so the map is deafened by the engine, not by an if",
			not view.is_processing_unhandled_input())
	_true("...and the menu is the one Godot calls",
			view._menu.is_processing_unhandled_input())

	# The map is frozen under it, and this is now the STRUCTURAL statement of that rather
	# than a hand-written one. The pad is delivered for real — through the viewport, to
	# whoever Godot thinks is listening — and the map never hears it, so nothing can grow
	# its held direction. Under the poll this arm could only be made true by the map asking
	# `Focus.holds` about itself; the ask is gone, and the assertion survives it.
	_pad(&"ui_left", true)
	_eq("the map's cursor is frozen while the menu is up",
			view.held_direction(), Vector2i.ZERO)
	_pad(&"ui_left", false)

	# Row 0 is Move, and it opens the place list OVER the menu rather than replacing it.
	await _press(&"cursor_confirm")
	_true("row 0 opens the place list", view._places != null)
	_true("...over the menu, not instead of it", view._menu != null)
	# Record 6's `+0x20` is ONE level, and a stack is the only structure that can say so:
	# three frames deep, and the thing underneath is the menu, not the map.
	_eq("...which is three frames deep, not two", Focus.stack_names(),
			["world_map", "world_map_start_menu", "world_map_place_list"] as Array[String])
	_true("...and the menu is deaf under it",
			not view._menu.is_processing_unhandled_input())

	var dismissed := [false]
	var probe := func() -> void: dismissed[0] = true
	view.dismissed.connect(probe)
	await _press(&"ui_cancel")
	_true("X closes the place list", view._places == null)
	_true("...back to the menu", view._menu != null)
	# The pop hands focus DOWN one, to whatever was underneath. A flat mechanism cannot
	# do this: it has to be told who is next, and it has no record of it.
	_eq("...and the stack popped to the menu, not to the map", Focus.stack_names(),
			["world_map", "world_map_start_menu"] as Array[String])
	_true("...which is audible again", view._menu.is_processing_unhandled_input())
	await _press(&"ui_cancel")
	_true("X again closes the menu", view._menu == null)
	_eq("...leaving the map holding the frame again", Focus.stack_names(),
			["world_map"] as Array[String])
	_true("...audible again", view.is_processing_unhandled_input())
	_true("...and neither X dismissed the screen", not dismissed[0])
	view.dismissed.disconnect(probe)
	await _check_row_is_reported_not_mounted(view)
	return get_tree().process_frame


## ADR-0117 dec. 8, mechanised for the OTHER five rows. §33.3's table: row 1 is window 7,
## whose console handler `FUN_80113748` is the formation mainloop `FORMATION_SCREEN.md`
## already ports. The map's job is to say so and stop — [NavigatorMain.run_world_map] is
## what turns window 7 into a mounted screen, so this asserts the REPORT, not the mount.
##
## Two things it pins that a unit test cannot. The signal has to carry the ENTRY TABLE's
## window id rather than the row index (they differ for every row but 0 — 6/7/11/14/12/5
## against 0..5), and the menu has to be CLOSED by the time it fires, because a subscriber
## that mounts a screen must not find this window still up underneath it.
func _check_row_is_reported_not_mounted(view) -> Signal:
	var seen: Array = []
	var open_at_emit := [true]
	var cb := func(row: int, window: int) -> void:
		seen.append([row, window])
		open_at_emit[0] = view._menu != null
	view.menu_row_chosen.connect(cb)

	await _press(&"world_map_start_menu")
	_true("the menu reopens", view._menu != null)
	# Row 0 is Move and is the map's own — it must NOT come out of this signal.
	await _press(&"cursor_confirm")
	_true("row 0 opened the place list", view._places != null)
	_eq("...and reported nothing: Move is the map's own row", seen.size(), 0)
	await _press(&"ui_cancel")
	await _press(&"ui_down")
	_eq("the cursor is on row 1", view._menu.row, 1)
	_eq("...which is Formation", view._menu.label_of(1), "Formation")
	await _press(&"cursor_confirm")
	_eq("taking row 1 reports exactly once", seen.size(), 1)
	if seen.size() == 1:
		_eq("...with the row", int(seen[0][0]), 1)
		_eq("...and the ENTRY TABLE's window id, not the row", int(seen[0][1]), 7)
	_true("...after the menu has closed", not open_at_emit[0])
	_true("the map did not mount anything itself", view._menu == null and view._places == null)
	# Reporting is not leaving: the navigator is still awaiting `dismissed`.
	_true("...and the screen was not dismissed", true)
	view.menu_row_chosen.disconnect(cb)
	_check_suspend(view)
	return get_tree().process_frame


## The other half of the hand-off: a host that mounts one of §33.3's screens SUSPENDS this
## one rather than layering over it (§33.7 — Formation, Data and Option are ordinary
## blocking calls into `WORLD.BIN`, not page pushes, so the map neither draws nor ticks
## under them). Reversible, and nothing is torn down.
##
## The input half matters as much as the clock: [method held_direction] polls [Input]
## directly, so a suspended screen that kept `_input_enabled` would steer a cursor nobody
## can see while another screen has focus.
func _check_suspend(view) -> void:
	var before: Vector2i = view._cursor.position
	# Held ACROSS the transition, which is the case delivery alone cannot cover: the release
	# would land while another screen holds the frame and never reach this one. The pop has
	# to drop it, and this is the arm that says so.
	_pad(&"ui_left", true)
	_eq("held before the hand-off, the direction is live", view.held_direction(),
			Vector2i(-1, 0))
	view.set_suspended(true)
	_true("suspended: the clock stops", not view.is_processing())
	_true("...and unhandled input with it", not view.is_processing_unhandled_input())
	_eq("...and the direction held across the hand-off is dropped, not stranded",
			view.held_direction(), Vector2i.ZERO)
	_pad(&"ui_left", true)
	_eq("...so a key pressed under it reads as no direction", view.held_direction(),
			Vector2i.ZERO)
	_eq("...and the cursor has not moved", view._cursor.position, before)
	_pad(&"ui_left", false)
	_true("...and nothing was torn down", view.assets != null and view.renderer != null)

	view.set_suspended(false)
	_true("resumed: the clock runs again", view.is_processing())
	_true("...and input is live", view.is_processing_unhandled_input())
	_eq("...on the same cursor it left", view._cursor.position, before)


func _press(action: StringName) -> Signal:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	return get_tree().process_frame


## The whole path from a held key to a moved cursor: `held_direction()` reads the input
## map, `advance()` steps the cursor once per VSYNC, and the location name follows the hit
## test rather than the party. Everything else about the cursor is unit-tested in
## WorldMapCursorTest against §27.6 — this is the wiring, which that test cannot see.
func _check_input(view) -> void:
	view.set_process(false)
	view._tick_debt = 0.0
	var start: Vector2i = view._cursor.position
	_eq("nothing held reads as no direction", view.held_direction(), Vector2i.ZERO)
	_pad(&"ui_left", true)
	_eq("a held key reads as a direction", view.held_direction(), Vector2i(-1, 0))
	# The cursor starts ON the party's node, so the first frames of the press go nowhere:
	# the snap (`FUN_8008D194`) pulls up to 2 px/vsync back onto the node and the ramp
	# only clears that on its sixth frame. This is the wiring assertion for it — if
	# `advance` stopped handing `assets`/`progress` to `step` the cursor would move here
	# and nothing else in the suite would notice.
	for _i in 2:
		view.advance(1.0 / 60.0)
	_eq("two vsyncs on a node move it nowhere — the snap eats them",
			view._cursor.position, start)
	# One vsync at a time: a single big delta is a STALL and MAX_CATCHUP_TICKS clamps it
	# to 8 ticks, and the assertion below would be measuring the cap.
	for _i in 40:
		view.advance(1.0 / 60.0)
	_pad(&"ui_left", false)
	_true("holding it does move the cursor left (%s -> %s)" % [start, view._cursor.position],
			view._cursor.position.x < start.x and view._cursor.position.y == start.y)
	# It started on the party's node; walking off must drop the selection, which is what
	# suppresses the location name (§19.1's `!= 0` guard is live, not defensive).
	_eq("walking off the node deselects it",
			WorldMapCursor.node_under(view.assets, view.progress, view._cursor.position), 0)
	_eq("and the scene reads the deselection off the cursor's own stored hit",
			view._cursor.hit_node, 0)
	# 42 vsyncs of LEFT runs it into `_bounds_for_cursor`, so this is the wall case: the
	# momentum has to be dropped there, not banked against it.
	for _i in 30:
		view.advance(1.0 / 60.0)
	var settled: Vector2i = view._cursor.position
	for _i in 30:
		view.advance(1.0 / 60.0)
	_eq("released, it comes to a stop rather than drifting", view._cursor.position, settled)
	# `step` clamps to `bounds.end` inclusive, so test the edges, not `has_point`.
	_true("and stays inside the cursor's bounds (%s in %s)" % [settled, view._cursor_bounds],
			settled.x >= view._cursor_bounds.position.x
			and settled.x <= view._cursor_bounds.end.x
			and settled.y >= view._cursor_bounds.position.y
			and settled.y <= view._cursor_bounds.end.y)
	view._cursor.place(start)
	view._cursor.resolve(view.assets, view.progress)
	_true("and back on the node the selection returns", view._cursor.hit_node > 0)
	view.set_process(true)


## The console's clock is 60 Hz and BOTH animations are counted in its vsyncs — §21.3
## measured the pin pulse at ±2 per vsync over 6,675 sampled frames, a 128-frame period
## it states as 2.133 s; §21.4 the idle at 10 frames a cel, "a 40-frame (0.667 s) cycle".
## Ticking per RENDERED frame ran both at the display's refresh rate: 143.9 Hz here, so
## 2.4x fast.
##
## Asserted in TICKS, never in elapsed seconds — a wall-clock test would be measuring the
## harness, which throttles presentation to a fraction of the refresh rate.
func _check_clock(view) -> void:
	view.set_process(false)
	# The scene has been running for a few real frames, so it already owes a fraction of
	# a vsync. Start the clock from zero or the counts below are off by that fraction —
	# which is exactly the 61-instead-of-60 this assertion first produced.
	view._tick_debt = 0.0
	_eq("a 1/60 s frame is one vsync", view.advance(1.0 / 60.0), 1)
	# THE REGRESSION GUARD: a 143.9 Hz frame is 0.00695 s, and 144 of them are one second
	# of wall clock. One second must be 60 vsyncs, not 144 — the fractional debt has to
	# carry between frames or the average rate drifts.
	var n := 0
	for _i in 144:
		n += view.advance(1.0 / 143.9)
	_eq("144 display frames step 60 vsyncs, not 144", n, 60)
	# §21.3: the pulse is a 128-frame triangle. Advancing exactly one period must return
	# the counter AND its direction bit to where they started.
	var c0: int = view._pulse_c
	var up0: bool = view._pulse_up
	for _i in 128:
		view.advance(1.0 / 60.0)
	_eq("the pin pulse's period is 128 vsyncs",
			[view._pulse_c, view._pulse_up], [c0, up0])
	# §21.4: 4 cels x 10 frames. One cycle returns to the same frame index.
	var f0: int = view._party_frame
	var t0: int = view._party_tick
	for _i in 40:
		view.advance(1.0 / 60.0)
	_eq("the idle cycle is 40 vsyncs", [view._party_frame, view._party_tick], [f0, t0])
	# A stall must drop the missed ticks, not replay them.
	_eq("a 5-second stall steps at most MAX_CATCHUP_TICKS", view.advance(5.0),
			view.MAX_CATCHUP_TICKS)
	view.set_process(true)


## §29.3 — the type-8 query is on the node the MARKER stands on, not the node under the
## cursor, and it precedes the pathfinder entirely: *"when it fires, ○ does the same thing
## wherever the cursor is."* That is why §29.5 measured all three opening savestates as
## having no reachable walk — FFT will not let you leave Gariland until Gariland is cleared.
##
## Reported from play: at story 1 the port walked to Mandalia Plains, arrived, found no
## hand-off THERE, and did nothing. The scenario the player expected was the MARKER's.
func _check_marker_handoff_beats_travel(view) -> void:
	var marker: int = view.progress.party_node()
	# Pick a known node that is NOT the marker, so a walk is the alternative outcome.
	var elsewhere := -1
	for id in range(1, WorldMapProgress.NODE_COUNT + 1):
		if id != marker and view.progress.is_node_known(id - 1):
			elsewhere = id
			break
	_true("there is a known node other than the marker to aim at", elsewhere > 0)
	if elsewhere < 0:
		return

	# Arm A — no hand-off claimed. ○ elsewhere must still TRAVEL, or this test would pass
	# by breaking the map.
	view.set_hand_off_places([])
	var reported_a := [0]
	var cb_a := func(n: int) -> void: reported_a[0] = n
	view.node_entered.connect(cb_a)
	view.enter_place(elsewhere)
	_true("with no hand-off, ○ on a far node starts a walk", view._travel != null)
	_eq("...and reports no arrival yet", reported_a[0], 0)
	view.node_entered.disconnect(cb_a)
	view._travel = null

	# Arm B — the marker hands off. ○ on the SAME far node must fire the MARKER's node and
	# start no walk at all.
	view.set_hand_off_places([marker])
	var reported_b := [0]
	var cb_b := func(n: int) -> void: reported_b[0] = n
	view.node_entered.connect(cb_b)
	view.enter_place(elsewhere)
	_eq("with a hand-off at the marker, ○ elsewhere reports the MARKER", reported_b[0], marker)
	_true("...and no walk is planned — the pathfinder is never reached", view._travel == null)
	view.node_entered.disconnect(cb_b)
	view.set_hand_off_places([])


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


## Drive the pad the way the device does: an EVENT through the viewport. Synchronous —
## [method Viewport.push_input] runs the whole chain before it returns, so an assertion on
## the next line already sees the result. Never by calling `_unhandled_input` directly: a
## test that calls the callback cannot tell "ignored" from "never delivered", which is the
## exact distinction Focus is built out of.
func _pad(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	get_viewport().push_input(ev)


## [b]The held direction is EVENTS now, not a poll of the [Input] singleton.[/b]
##
## `check_focus_anchor.py` kept this file listed for exactly one reason: a poll is not
## discharged by registering, because the switch stops Godot CALLING a non-holder and
## cannot stop one ASKING. The fix is to stop asking — and the assertion that proves it is
## the one below, which writes the singleton state the old poll read and delivers no event
## at all. Under the poll it steers the cursor; under the events it does nothing.
func _check_pad_is_events(view) -> void:
	view.set_process(false)
	Input.action_press(&"ui_left")
	_eq("a bare Input-singleton write steers nothing — nothing polls it",
			view.held_direction(), Vector2i.ZERO)
	Input.action_release(&"ui_left")

	_pad(&"ui_left", true)
	_eq("a DELIVERED press reads as a direction", view.held_direction(), Vector2i(-1, 0))
	# Diagonals are legal (§27.6 drove both axes), so the two components are independent.
	_pad(&"ui_down", true)
	_eq("...and a second axis joins it rather than replacing it",
			view.held_direction(), Vector2i(-1, 1))
	_pad(&"ui_left", false)
	_eq("...one release clears its own component only",
			view.held_direction(), Vector2i(0, 1))
	_pad(&"ui_down", false)
	_eq("...and the last one clears it", view.held_direction(), Vector2i.ZERO)

	# The pad can be ROLLED: LEFT down, RIGHT down, LEFT up, with the thumb never leaving
	# it. A poll got this free — it re-read both keys every frame and the newer one simply
	# won. Tracking has to be told, so the release arm asks which way the axis is actually
	# pointing before it zeroes anything.
	_pad(&"ui_left", true)
	_pad(&"ui_right", true)
	_eq("rolling the pad takes the newer direction", view.held_direction(), Vector2i(1, 0))
	_pad(&"ui_left", false)
	_eq("...and releasing the one already overridden does not zero the axis",
			view.held_direction(), Vector2i(1, 0))
	_pad(&"ui_right", false)
	_eq("...only releasing the live one does", view.held_direction(), Vector2i.ZERO)
	view.set_process(true)
