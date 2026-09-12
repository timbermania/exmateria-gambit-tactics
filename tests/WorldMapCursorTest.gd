extends Node
## The cursor's MOVEMENT, against the console's own per-vsync trace.
##
## WARNING [b]This test twice asserted the wrong thing, and the second time it was this
## file's own confident correction of the first.[/b] Worth reading before touching it.
##
## `capture_travel.lua`'s header says *"a held direction takes 8 frames to start moving"*
## and *"a 2-frame tap moves the cursor ZERO pixels"*. Round one ported that as a literal
## 8-frame dead zone, which made the cursor feel broken. Round two opened
## `round10_travel_trace.csv`, found the cursor moving on frame 1 of the press it had
## picked out, declared the prose wrong, and asserted a fitted curve
## `1,1,2,2,3,3,4,4,4,3,3,2,2,1,1` instead.
##
## Both rounds were wrong, and the prose was right. Two ROM mechanisms explain every frame
## in that file:
##
## 1. [b]The ramp is a ROM constant, not a fit.[/b] `FUN_80068E70` is an 8.8 accelerator;
##    the world map's setup writes `max = 0x400`, `accel = decel = 0x80` at `0x8006C6B8`
##    onward. Half a pixel of acceleration per vsync, capped at four. Frame 1 of a press
##    therefore moves ZERO pixels -- acc is 0x80, and `0x80 >> 8` is 0.
## 2. [b]There is a magnetic snap[/b] (`FUN_8008D194`) pulling the cursor up to 2 px/vsync
##    onto the resting point of whatever node it is inside. The cursor always STARTS on a
##    node, and the pull cancels the ramp exactly for its first five frames -- which is
##    the "8 frames to start moving", and which is why a 2-frame tap from a node really
##    does move zero pixels.
##
## Round two's frame 1 was five vsyncs late. [method _test_trace_leaving_gariland] and
## [method _test_trace_arriving_at_igros] replay the trace itself rather than a summary of
## it: 17 and 10 consecutive vsyncs, position compared per frame, no curve in sight. If
## you change the dynamics and those two still pass, the change is defensible.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/WorldMapCursorTest.tscn

## The ramp, off a node, from a press to the plateau: `min(0x80*k, 0x400) >> 8`. The
## leading ZERO is the whole correction -- acc is 0x80 after one vsync and that shifts to
## nothing.
const PROFILE := [0, 1, 1, 2, 2, 3, 3, 4, 4]
## ...and from release to a stop, `0x400` down by `0x80` a frame.
const RELEASE := [3, 3, 2, 2, 1, 1]

## `round10_travel_trace.csv`, vsyncs 49..65: the cursor parked on Gariland (node 7, screen
## (-4,0), resting at (-4,-4)) with LEFT held for eleven vsyncs and then released. The
## five leading -4s are the snap eating the ramp; the -16 is the frame the cursor clears
## the 21-wide box and the pull stops.
const TRACE_GARILAND_X := [-4, -4, -4, -4, -4, -5, -6, -8, -10, -12, -16,
		-19, -22, -24, -26, -27, -28]
const TRACE_GARILAND_HELD := 11

## Same file, vsyncs 168..177: UP held for five vsyncs from (-65,-41), which is outside
## Igros Castle (node 3, screen (-60,-49), resting at (-60,-53)) and two vsyncs' travel
## from its box. The x column moves although x is never pressed -- that is the snap, and
## it lands on the resting point and then absorbs the entire coast.
const TRACE_IGROS := [Vector2i(-65, -41), Vector2i(-65, -42), Vector2i(-63, -45),
		Vector2i(-61, -49), Vector2i(-60, -53), Vector2i(-60, -53), Vector2i(-60, -53),
		Vector2i(-60, -53), Vector2i(-60, -53), Vector2i(-60, -53)]
const TRACE_IGROS_HELD := 5

## Wide enough that nothing below is clipped by it — the clamp is tested separately.
const OPEN := Rect2i(-1000, -1000, 2000, 2000)
const RIGHT := Vector2i(1, 0)
const NONE := Vector2i.ZERO

var _passed := 0
var _failed := 0


func _ready() -> void:
	_test_profile()
	_test_tap()
	_test_release()
	_test_top_speed()
	_test_reversal_runs_through_zero()
	_test_edge_clamp()
	_test_pull_is_capped_and_never_overshoots()
	_test_hit_test_still_agrees()
	_test_trace_leaving_gariland()
	_test_trace_arriving_at_igros()
	_test_the_snap_is_what_makes_the_prose_true()

	if _failed > 0:
		print("[FAIL] WorldMapCursorTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapCursorTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


func _hold(c: WorldMapCursor, dir: Vector2i, ticks: int) -> void:
	for _i in ticks:
		c.step(dir, OPEN)


## The load-bearing one: the per-vsync step sequence must BE the console's.
func _test_profile() -> void:
	var c := WorldMapCursor.new()
	c.place(Vector2i.ZERO)
	var got: Array = []
	var last := 0
	for _i in PROFILE.size():
		c.step(RIGHT, OPEN)
		got.append(c.position.x - last)
		last = c.position.x
	_eq("the press profile is the console's", got, PROFILE)


## One pixel, off a node: frame 1 of the ramp is 0 and frame 2 is 1. (ON a node it is
## zero, which is §27.6's claim — see [method _test_the_snap_is_what_makes_the_prose_true].)
func _test_tap() -> void:
	var c := WorldMapCursor.new()
	c.place(Vector2i.ZERO)
	_hold(c, RIGHT, 2)
	_eq("a 2-frame tap moves 1 px off a node", c.position.x, PROFILE[0] + PROFILE[1])
	# ...and stops there. Releasing at speed 1 drops it to 0 on the next ramp step, so a
	# tap has no coast — the coast is the same ramp, not a separate impulse.
	_hold(c, NONE, 20)
	_eq("and a tap has no coast, because the ramp IS the coast", c.position.x, 1)


## Release from top speed: the speed falls the way it rose, which is what makes the coast
## "~12 px over 6 frames" rather than that being a separate rule.
func _test_release() -> void:
	var c := WorldMapCursor.new()
	c.place(Vector2i.ZERO)
	_hold(c, RIGHT, 20)
	var at_release := c.position.x
	var got: Array = []
	var last := at_release
	for _i in RELEASE.size():
		c.step(NONE, OPEN)
		got.append(c.position.x - last)
		last = c.position.x
	_eq("the release profile is the console's", got, RELEASE)
	_eq("which is §27.6's 12 px over 6 frames", c.position.x - at_release, 12)
	_hold(c, NONE, 30)
	_eq("and then it is stopped, not crawling", c.position.x, last)


## The plateau: 4 px per vsync, held indefinitely.
func _test_top_speed() -> void:
	var c := WorldMapCursor.new()
	c.place(Vector2i.ZERO)
	_hold(c, RIGHT, 40)
	var before := c.position.x
	_hold(c, RIGHT, 10)
	_eq("top speed is 4 px per vsync", (c.position.x - before) / 10,
			WorldMapCursor.MAX_SPEED)
	# x and y are separate globals (0x8009EF7C / 0x8009F194), so a diagonal runs both at
	# full speed rather than sharing a budget.
	var d := WorldMapCursor.new()
	d.place(Vector2i.ZERO)
	_hold(d, Vector2i(1, 1), 40)
	var p := d.position
	_hold(d, Vector2i(1, 1), 10)
	_eq("and a diagonal runs both axes at it", d.position - p,
			Vector2i(10 * WorldMapCursor.MAX_SPEED, 10 * WorldMapCursor.MAX_SPEED))


## §21.1 — the view never scrolls: the cursor runs to the edge and stops. It must also
## STOP, not keep piling speed into the wall and fly off when released.
func _test_edge_clamp() -> void:
	var box := Rect2i(-20, -20, 40, 40)
	var c := WorldMapCursor.new()
	c.place(Vector2i.ZERO)
	for _i in 60:
		c.step(RIGHT, box)
	_eq("it clamps at the edge", c.position.x, box.end.x)
	_hold(c, NONE, 10)
	_eq("and releasing at the edge neither springs back nor overshoots",
			c.position.x, box.end.x)


## The cursor and the hit test have to keep agreeing after all of the above.
func _test_hit_test_still_agrees() -> void:
	var assets := WorldMapAssets.new()
	if not assets.load_all():
		print("  skip  hit test — run tools/parse_world_map.py")
		return
	var p := WorldMapProgress.new_campaign()
	var n: Dictionary = assets.node(6)       # 1-based node 7, Gariland, the party's
	var c := WorldMapCursor.new()
	c.place(WorldMapCursor.rest_at(Vector2i(int(n["screen"][0]), int(n["screen"][1]))))
	_eq("parked on node 7 it hit-tests to 7",
			WorldMapCursor.node_under(assets, p, c.position), 7)
	# `rest_at`'s -4 is `addiu v0,v0,-4` at 0x8006C3B8 — the ROM's own instruction.
	_eq("and rests four pixels above the node, as FUN_8006C350 writes it",
			c.position, Vector2i(int(n["screen"][0]), int(n["screen"][1]) - 4))
	_hold(c, RIGHT, 40)
	_eq("walking off it deselects", WorldMapCursor.node_under(assets, p, c.position), 0)
	# §27.4's "the box follows the art, drawn above its anchor" is about the PIN, not the
	# cursor — pin 106 is x −6..6 y −8..4 inside the 21×21 box, the cursor's hand trails
	# down-left at x −17..1 y −5..13. Conflating them made an earlier version of this test
	# assert something false.
	var pin := assets.cel_bounds(assets.static_cel(int(assets.node(6)["marker_frame"])))
	_true("the pin's art fits inside the hit box (%s)" % pin,
			pin.position.x >= -WorldMapCursor.HIT_X and pin.end.x <= WorldMapCursor.HIT_X
			and pin.position.y >= -WorldMapCursor.HIT_UP
			and pin.end.y <= WorldMapCursor.HIT_DOWN)
	_true("and leans above its anchor, which is why the box does",
			-pin.position.y > pin.end.y)
	var art := assets.cel_bounds(assets.static_cel(WorldMapPrimitives.CURSOR_FRAME))
	_true("the cursor's own art trails down-left of its anchor (%s)" % art,
			art.position.x < 0 and art.end.y > 0)


## The accumulator carries the sign, so turning around decelerates THROUGH zero rather
## than restarting the ramp — and `0x80068F90`'s negate-shift-negate rounds the other way
## from `0x80068EE8`'s bare `sra` while the two disagree in sign.
func _test_reversal_runs_through_zero() -> void:
	var c := WorldMapCursor.new()
	c.place(Vector2i.ZERO)
	_hold(c, RIGHT, 20)
	var at_turn := c.position.x
	var got: Array = []
	var last := at_turn
	for _i in 10:
		c.step(Vector2i(-1, 0), OPEN)
		got.append(c.position.x - last)
		last = c.position.x
	# acc walks 0x400 -> -0x100 by 0x80 a vsync. Note the rounding: while LEFT is held,
	# +0x380 reads as 4 px, where on a release it reads as 3 — so a reversal coasts 16 px
	# past the turn where letting go coasts 12.
	_eq("a reversal coasts through zero on the momentum it had",
			got, [4, 3, 3, 2, 2, 1, 1, 0, 0, -1])
	_eq("and overshoots further than a release does, by the rounding alone",
			c.position.x - at_turn, 15)
	_hold(c, Vector2i(-1, 0), 10)
	_true("then it is genuinely going the other way", c.position.x < at_turn)


## `FUN_8008D194`'s arithmetic on its own: capped at 2, and the last step LANDS rather
## than stepping past. The landing is the whole point — it is why both savestates read the
## cursor at exactly `rest_at(node)`.
func _test_pull_is_capped_and_never_overshoots() -> void:
	var t := Vector2i(0, 0)
	_eq("far away it pulls the cap", WorldMapCursor.pull_toward(t, Vector2i(-40, 30)),
			Vector2i(2, -2))
	_eq("at exactly the cap it still lands", WorldMapCursor.pull_toward(t, Vector2i(-2, 2)),
			Vector2i(2, -2))
	_eq("one away it lands, it does not step 2 and come back",
			WorldMapCursor.pull_toward(t, Vector2i(-1, 1)), Vector2i(1, -1))
	_eq("on it, nothing", WorldMapCursor.pull_toward(t, t), Vector2i.ZERO)


## THE load-bearing one. `round10_travel_trace.csv` vsyncs 49..65, position per vsync, the
## console's own RAM. Nothing here is a curve or a summary.
func _test_trace_leaving_gariland() -> void:
	var rig := _rig()
	if rig.is_empty():
		return
	var c: WorldMapCursor = rig["cursor"]
	c.place(WorldMapCursor.rest_at(Vector2i(-4, 0)))
	var got: Array = []
	for i in TRACE_GARILAND_X.size():
		var dir := Vector2i(-1, 0) if i < TRACE_GARILAND_HELD else NONE
		c.step(dir, OPEN, rig["assets"], rig["progress"])
		got.append(c.position.x)
	_eq("17 vsyncs of the console, leaving Gariland with LEFT held", got,
			TRACE_GARILAND_X)
	_eq("and the y axis never budges, because the snap holds it on the resting row",
			c.position.y, -4)


## Same file, vsyncs 168..177 — a vertical press that arrives at Igros. The x column is
## pure snap: LEFT and RIGHT are never touched and the cursor still slides 5 px sideways
## onto the node, then stops dead instead of coasting past it.
func _test_trace_arriving_at_igros() -> void:
	var rig := _rig()
	if rig.is_empty():
		return
	var c: WorldMapCursor = rig["cursor"]
	c.place(Vector2i(-65, -41))
	var got: Array = []
	for i in TRACE_IGROS.size():
		var dir := Vector2i(0, -1) if i < TRACE_IGROS_HELD else NONE
		c.step(dir, OPEN, rig["assets"], rig["progress"])
		got.append(c.position)
	_eq("10 vsyncs of the console, arriving at Igros with UP held", got, TRACE_IGROS)
	_eq("it parks on the resting point, which is what both savestates read",
			c.position, WorldMapCursor.rest_at(Vector2i(-60, -49)))
	_eq("and the node is selected", c.hit_node, 3)


## §27.6's two "wrong" statements, reproduced. They are about a cursor on a node, and the
## cursor is always on a node when you start pressing.
func _test_the_snap_is_what_makes_the_prose_true() -> void:
	var rig := _rig()
	if rig.is_empty():
		return
	var c: WorldMapCursor = rig["cursor"]
	var rest := WorldMapCursor.rest_at(Vector2i(-4, 0))
	c.place(rest)
	c.step(Vector2i(-1, 0), OPEN, rig["assets"], rig["progress"])
	c.step(Vector2i(-1, 0), OPEN, rig["assets"], rig["progress"])
	_eq("§27.6: a 2-frame tap on a node moves the cursor ZERO pixels", c.position, rest)
	_hold(c, NONE, 30)
	_eq("and it settles back exactly onto the node, not near it", c.position, rest)

	c.place(rest)
	var moved_on := 0
	for i in 12:
		if c.step(Vector2i(-1, 0), OPEN, rig["assets"], rig["progress"]):
			moved_on = i + 1
			break
	# The pull is +/-2 and the ramp only clears 2 px/vsync on its sixth frame. §27.6 read
	# this as "8 frames"; it is six, and the mechanism is not a dead zone at all.
	_eq("§27.6: a held direction takes several frames to start moving — six", moved_on, 6)


## The assets are gitignored ROM output; skip rather than fail when they are absent.
func _rig() -> Dictionary:
	var assets := WorldMapAssets.new()
	if not assets.load_all():
		print("  skip  trace replay — run tools/parse_world_map.py")
		return {}
	var p := WorldMapProgress.ss1_fixture()
	if not p.is_node_known(2) or not p.is_node_known(6):
		print("  skip  trace replay — the ss1 fixture does not know Igros and Gariland")
		return {}
	return {"assets": assets, "progress": p, "cursor": WorldMapCursor.new()}


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
