extends Node
## ADR-0231 — the [b]reveal animation[/b]. ADR-0230 built the pass and left one thing
## owed: `WorldMapScene` called `step()` in a `while` loop and the whole beat landed
## inside one frame. This is that loop paced onto the vsync clock, and the picture each
## step draws while it is on screen.
##
## [b]The oracle is the console, and it was read rather than invented.[/b] Every hold
## below is a WLDCORE constant: `0x10` at `0x8006DE58` is the node page's sixteen vsyncs,
## `sra v0,v0,5` at `0x8008DBC0` is the ribbon's per-quad hold, and page `0x32` popping on
## its own first tick with no camera pan armed (`0x8006D928`) is the look-at's one.
##
## [b]The store is built from `new_campaign()`, never seeded[/b] — the rule
## `CampaignRevealPassTest` states and for the same reason. The erase arm walks the
## campaign in order, because every erase is guarded on the bit it clears and no isolated
## beat can reach one.
##
## Run: <GODOT> --path . --quit-after 10 res://tests/WorldMapRevealAnimationTest.tscn

var _passed := 0
var _failed := 0

const WORLD_MAP_SCENE := "res://assets/scenes/WorldMap.tscn"
const MODEL_PATH := "res://assets/world_map/model.json"

## The counter-4 beat — the reported defect, and the beat ADR-0230's Prediction 1 is
## about — as `[kind, subject, vsyncs]`. Igros owes four steps and the timing is entirely
## the console's: route 12 is five ribbon quads at one vsync each, route 11 is six, and
## each node is the page's sixteen.
const COUNTER_4 := [
	["reveal_route", 12, 5],
	["reveal_node", 26, 16],
	["reveal_route", 11, 6],
	["reveal_node", 9, 16],
]
const COUNTER_4_VSYNCS := 43

var _assets: WorldMapAssets = null


func _ready() -> void:
	_assets = WorldMapAssets.new()
	if not _assets.load_all():
		print("[FAIL] WorldMapRevealAnimationTest — assets: %s" % _assets.error)
		get_tree().quit(1)
		return
	_test_the_holds_are_the_consoles()
	_test_the_counter_4_beat_is_paced()
	_test_the_look_at_is_the_pen()
	_test_the_erase_holds_its_picture()
	_test_settle_is_the_old_drain()
	_test_the_frame_hides_the_route_it_is_drawing()
	await _test_the_arrival_waits_for_the_animation()
	await _test_the_screen_is_deaf_while_it_draws()
	await _test_the_frame_really_loses_the_quads()

	if _failed > 0:
		print("[FAIL] WorldMapRevealAnimationTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapRevealAnimationTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


# ---------------------------------------------------------------- the clock

## The three holds, against the instructions they were read from — and the ribbon table
## against the whole shipped route set, which is where the ported formula earns its keep.
func _test_the_holds_are_the_consoles() -> void:
	_eq("a node page holds 16 vsyncs (0x10 at 0x8006DE58)",
			WorldMapRevealAnimation.NODE_VSYNCS, 16)
	_eq("a look-at holds 1 (page 0x32 pops on its own first tick with no pan)",
			WorldMapRevealAnimation.LOOK_AT_VSYNCS, 1)
	var model := _json(MODEL_PATH)
	var routes: Array = model.get("routes", [])
	_eq("the model ships 48 routes", routes.size(), 48)
	var slow := 0
	var quads := 0
	for r in routes.size():
		var d := WorldMapRevealAnimation.quad_vsyncs(_assets, r)
		var poly: Array = routes[r].get("polyline", [])
		_eq("route %d: one hold per ribbon quad" % r, d.size(), poly.size() / 2 - 1)
		quads += d.size()
		for v in d:
			if v > 1:
				slow += 1
	# The measured fact, and the reason the ported `>> 5` currently evaluates to a
	# constant: the longest segment in `model.json` is 31.1 px and the shift needs 32. The
	# formula is kept because that is a fact about the DATA — a regenerated model with a
	# longer route would otherwise silently lose the slow arm.
	_eq("every shipped quad is one vsync (>> 5 needs 32 px; the longest is 31.1)", slow, 0)
	_eq("...over 254 ribbon quads", quads, 254)


## The counter-4 beat, tick by tick: which step is on screen, how far the ribbon has come,
## and the vsync each boundary lands on.
func _test_the_counter_4_beat_is_paced() -> void:
	var p := WorldMapProgress.new_campaign()
	p.set_story_counter(4)
	var anim := _animate(2, p)
	_true("counter 4: Igros owes an animation at all", anim.is_active())
	var at := 0
	for row in COUNTER_4:
		var kind: String = row[0]
		var subject: int = row[1]
		var hold: int = row[2]
		_eq("v%d: the step is %s %d" % [at, kind, subject], _describe(anim.step),
				"%s %d" % [kind, subject])
		if kind == "reveal_route":
			# The bit is already written — ADR-0230 dec. 3 — so the frame must be told to
			# hold the finished ribbon back and draw the growing one instead.
			_true("v%d: route %d is drawn in the store already" % [at, subject],
					p.is_route_drawn(subject))
			_eq("v%d: ...and hidden from the frame" % at, anim.hidden_route(), subject)
			for k in hold:
				_eq("v%d: %d of %d quads" % [at + k, k, hold],
						int(anim.ribbon_quads().get("quads", -1)), k)
				anim.tick()
			at += hold
		else:
			_eq("v%d: no route is hidden" % at, anim.hidden_route(), -1)
			for k in hold - 1:
				anim.tick()
				_true("v%d: the node page is still up" % [at + k + 1],
						_describe(anim.step) == "%s %d" % [kind, subject])
			anim.tick()
			at += hold
	_eq("the beat is %d vsyncs" % COUNTER_4_VSYNCS, at, COUNTER_4_VSYNCS)
	_true("...and the pass is finished", not anim.is_active())
	_eq("...having shown four steps", anim.steps_shown, COUNTER_4.size())
	_eq("...landing the same known set the drain did", str(p.known_nodes()),
			"[2, 6, 9, 24, 26]")
	_true("one more tick on a finished animation is a no-op", not anim.tick())


## The look-at is the pen, and the pen STAYS where it was put. Counter 47 (Bethla
## Garrison, ADR-0230's worked example) is four triplets: point, draw the road, light the
## town, move the pen.
func _test_the_look_at_is_the_pen() -> void:
	var p := WorldMapProgress.new_campaign()
	p.set_story_counter(47)
	var anim := _animate(21, p)
	var look_ats := 0
	var others := 0
	var regarding := -1
	var seen: Array = []
	var shown := 0
	while anim.is_active():
		if anim.steps_shown == shown:
			# Mid-step: the pen has not moved, and that is the assertion below.
			_eq("the pen does not drift inside a step", anim.regarding, regarding)
			anim.tick()
			continue
		shown = anim.steps_shown
		var kind: StringName = anim.step.get("kind", &"")
		if kind == CampaignRevealPass.KIND_LOOK_AT:
			look_ats += 1
			regarding = int(anim.step["node"])
			_eq("a look-at points the pen at its own operand", anim.regarding, regarding)
			seen.append(regarding)
		else:
			others += 1
			# The whole point of a persistent pen: the console's look-at writes the
			# selected-place word `DAT_800D0BB4` and a word stays written, so the label
			# stands over the node being regarded while the road under it is drawn.
			_eq("...and it stays there through the next step", anim.regarding, regarding)
		anim.tick()
	_eq("counter 47 is four look-ats", look_ats, 4)
	_eq("...and eight steps that move a bit", others, 8)
	_eq("...pointing at nodes 5, 14, 42, 41 in order", str(seen), "[5, 14, 42, 41]")
	_true("a look-at moves no bit of its own", not p.is_node_known(5))


## The erase direction, reachable only by walking the campaign in order. Counter 18 takes
## back the node and the road counter 16 drew.
func _test_the_erase_holds_its_picture() -> void:
	var p := WorldMapProgress.new_campaign()
	for row in [[16, 9], [18, 35]]:
		p.set_story_counter(int(row[0]))
		if int(row[0]) != 18:
			var warm := _animate(int(row[1]), p)
			warm.settle()
			continue
		var anim := _animate(int(row[1]), p)
		var ghosted := 0
		var shrank := 0
		while anim.is_active():
			var kind: StringName = anim.step.get("kind", &"")
			if kind == CampaignRevealPass.KIND_UNREVEAL_NODE:
				var n := int(anim.step["node"])
				_eq("the erase takes node 21", n, 21)
				# The store lost the bit on the step (dec. 3); the console clears it on
				# the page's LAST frame (`0x8006E048`), so the pin has to stand for the
				# hold or the place leaves the map as a dropped frame.
				_true("...the store has already lost it", not p.is_node_known(n))
				_eq("...and the frame is told to draw it anyway", anim.ghost_node(), n)
				ghosted += 1
			elif kind == CampaignRevealPass.KIND_UNREVEAL_ROUTE:
				var r := int(anim.step["route"])
				_eq("the erase takes route 22", r, 22)
				_true("...the store has already lost it", not p.is_route_drawn(r))
				var q := int(anim.ribbon_quads().get("quads", -1))
				if shrank == 0:
					_eq("...and the road starts whole", q, 5)
				shrank += 1
				_eq("...shrinking one quad per vsync", q, 5 - shrank + 1)
			else:
				_eq("nothing else is ghosted", anim.ghost_node(), -1)
			anim.tick()
		_eq("counter 18 ghosts the pin for its whole hold", ghosted,
				WorldMapRevealAnimation.NODE_VSYNCS)
		_eq("...and shrinks the road over its five quads", shrank, 5)
		# The opening capture's {2, 6, 24}, plus counter 16's {21, 32, 35} and counter
		# 18's {3, 10, 37}, MINUS the 21 that counter 18 takes back. A monotonic drain
		# would leave 21 in this list.
		_eq("...leaving the walk's own known set", str(p.known_nodes()),
				"[2, 3, 6, 10, 24, 32, 35, 37]")


## Settling is the pre-ADR-0231 behaviour exactly — the capture rig and any host that
## wants one landed frame get the state the drain lands on.
func _test_settle_is_the_old_drain() -> void:
	for counter in [4, 41, 47]:
		var a := WorldMapProgress.new_campaign()
		var b := WorldMapProgress.new_campaign()
		a.set_story_counter(counter)
		b.set_story_counter(counter)
		var host := 2 if counter == 4 else (1 if counter == 41 else 21)
		var drained := 0
		var reveals := Campaign.reveal_pass(host, a)
		while not reveals.step().is_empty():
			drained += 1
		var anim := _animate(host, b)
		anim.settle()
		_eq("counter %d: settling shows every step the drain applied" % counter,
				anim.steps_shown, drained)
		_eq("counter %d: ...and the same known set" % counter, str(b.known_nodes()),
				str(a.known_nodes()))
		_eq("counter %d: ...and the same drawn set" % counter, str(b.drawn_routes()),
				str(a.drawn_routes()))
		_true("counter %d: ...and it is finished" % counter, not anim.is_active())


# ---------------------------------------------------------------- the frame

## The two primitive overrides, on the generator rather than through the screen: a hidden
## route is absent from the ribbon, a partial one is exactly as long as it is asked for,
## and the pen writes the location name over the node it is regarding.
func _test_the_frame_hides_the_route_it_is_drawing() -> void:
	var gen := WorldMapPrimitives.new(_assets)
	var p := WorldMapProgress.new_campaign()
	p.set_story_counter(4)
	var anim := _animate(2, p)
	var whole := gen.path_quads(p).size()
	var without := gen.path_quads(p, 12).size()
	var route_12 := gen.ribbon_quads(12).size()
	_eq("route 12 is five quads", route_12, 5)
	_eq("skipping it takes exactly those out", whole - without, route_12)
	for k in 6:
		_eq("a partial ribbon of %d is %d quads" % [k, k],
				gen.ribbon_quads(12, k).size(), mini(k, 5))
	# The reversed arm: same count, the other end of the road. The two overlap only at the
	# full length, which is what makes the comparison meaningful.
	var head := gen.ribbon_quads(12, 2)
	var tail := gen.ribbon_quads(12, 2, true)
	_eq("the reversed ribbon is the same length", tail.size(), head.size())
	_true("...and not the same quads", str(head[0]["xy"]) != str(tail[0]["xy"]))
	# The pen. `regarding` is 1-based here because that is the space `DAT_800D0BB4` and the
	# name-cel derivation live in (§19.1). The cursor at (-4, -4) is resting on place 7,
	# which the opening capture knows — so the frame already carries a name and the
	# override is not a COUNT, it is which node the one name is over.
	var cursor := Vector2i(-4, -4)
	_eq("the cursor is over place 7 to begin with",
			WorldMapCursor.node_under(_assets, p, cursor), 7)
	var plain: Array = gen.main_list(p, cursor, 40)
	var same: Array = gen.main_list(p, cursor, 40, 16, null, 0, 7)
	var moved: Array = gen.main_list(p, cursor, 40, 16, null, 0, 25)
	_eq("regarding the node the cursor is on changes nothing", str(same), str(plain))
	_true("regarding another node does", str(moved) != str(plain))
	_eq("...and the frame is the same length either way", moved.size(), plain.size())
	# ...and the name lands ON the node being regarded, which is the whole picture: §19.1
	# draws the name cel at the node's own projected point.
	var n25: Dictionary = _assets.node(24)
	var want: Array = gen.cel_quads(
			_assets.static_cel(25 + WorldMapPrimitives.NAME_FRAME_BASE),
			Vector2i(int(n25["screen"][0]), int(n25["screen"][1])))
	_true("the name is drawn over the regarded node",
			want.size() > 0 and str(moved).contains(str(want[0])))
	# The ghost. Node 26 is known at counter 4 only because the pass above ran, so take a
	# store that never ran one.
	var fresh := WorldMapProgress.new_campaign()
	var bare := gen.main_list(fresh, Vector2i(-4, -4), 40).size()
	var ghosted := gen.main_list(fresh, Vector2i(-4, -4), 40, 16, null, 0, 0, 26).size()
	_true("a ghosted node adds a marker the store does not know", ghosted > bare)
	anim.settle()


# ---------------------------------------------------------------- the screen

## The interlock. Arriving runs a pass, and the arrival's own ending — the town-page
## return, or [signal WorldMapScene.node_entered] handing the node to Campaign — must not
## land over a reveal that is still drawing.
func _test_the_arrival_waits_for_the_animation() -> void:
	var p := WorldMapProgress.new_campaign()
	p.set_story_counter(31)
	p.set_party_node(2)                                  # Lesalia, not Dorter
	var view := await _mount(p)
	view.call("settle_screen_in")
	var entered: Array = []
	view.connect("node_entered", func(n: int) -> void: entered.append(n))
	view.call("_arrive_at", 10)                          # Dorter, whose beat this is
	_true("arriving starts an animation", view.call("reveal_active"))
	_eq("...and nothing has been handed off", entered.size(), 0)
	for _i in 4:
		view.call("advance", 1.0 / 60.0)
	_true("four vsyncs in it is still drawing", view.call("reveal_active"))
	_eq("...and still nothing has been handed off", entered.size(), 0)
	view.call("settle_reveal")
	_true("settling ends it", not view.call("reveal_active"))
	_eq("...and the beat's four steps landed", str(p.known_nodes()), "[0, 2, 6, 8, 24]")
	# Dorter is a town, so the arrival's ending is to stand there — the map does not open
	# the page on arrival (that is the ○ path and no other), and it must not report either.
	_eq("Dorter is a town, so arrival reports nothing even after the wait",
			entered.size(), 0)
	view.queue_free()
	await get_tree().process_frame

	# ...and the other ending, on a node that is not a town: there the report itself is
	# what waits. Bethla Garrison (place 22) is counter 47's host and opens no menu, so
	# both halves of `_finish_arrival` are exercised across the two arms.
	var q := WorldMapProgress.new_campaign()
	q.set_story_counter(47)
	q.set_party_node(1)                                  # Lesalia, whose beat is 34
	var view2 := await _mount(q)
	view2.call("settle_screen_in")
	_true("opening the map where nothing is owed starts no animation",
			not view2.call("reveal_active"))
	var entered2: Array = []
	view2.connect("node_entered", func(n: int) -> void: entered2.append(n))
	view2.call("_arrive_at", 22)
	_true("arriving at Bethla Garrison starts one", view2.call("reveal_active"))
	_eq("...and reports nothing yet", entered2.size(), 0)
	for _i in 4:
		view2.call("advance", 1.0 / 60.0)
	_eq("...still nothing four vsyncs in", entered2.size(), 0)
	view2.call("settle_reveal")
	_eq("...and reports exactly once when it finishes", str(entered2), "[22]")
	view2.queue_free()
	await get_tree().process_frame


## While a reveal draws, the screen listens to nothing — the console's own rule, expressed
## as the animation page sitting above mode 0 in the page stack rather than as a flag.
func _test_the_screen_is_deaf_while_it_draws() -> void:
	var p := WorldMapProgress.new_campaign()
	p.set_story_counter(4)
	p.set_party_node(3)
	var view := await _mount(p)
	view.call("settle_screen_in")
	_true("the map opens into an animation", view.call("reveal_active"))
	var departed: Array = []
	view.connect("departed", func(n: int) -> void: departed.append(n))
	view.call("_unhandled_input", _action(&"ui_right", true))
	_eq("a direction held mid-reveal steers nothing", str(view.call("held_direction")),
			str(Vector2i.ZERO))
	view.call("_unhandled_input", _action(&"cursor_confirm", true))
	_eq("...and ○ starts no walk", departed.size(), 0)
	view.call("_unhandled_input", _action(&"world_map_start_menu", true))
	_true("...and START opens no menu", view.get("_menu") == null)
	# ✕ is the one of the four that NOTHING else guards — `_leave` has only its own
	# one-way latch — so this is the arm that scores the gate in [method
	# WorldMapScene._unhandled_input] rather than the three game-state guards under it.
	var dismissed: Array = []
	view.connect("dismissed", func() -> void: dismissed.append(true))
	view.call("_unhandled_input", _action(&"ui_cancel", true))
	_true("...and ✕ does not strike the screen mid-reveal", not view.get("_leaving"))
	_eq("...so nothing is dismissed", dismissed.size(), 0)
	view.call("settle_reveal")
	# The pad is tracked THROUGH the reveal even though it steers nothing — the gate sits
	# below `_track_pad` on purpose, because a release that landed during the animation
	# would otherwise never be seen and the cursor would walk away when it ended.
	_eq("the direction was tracked all along, and takes effect when the pass ends",
			str(view.call("held_direction")), str(Vector2i(1, 0)))
	view.call("_unhandled_input", _action(&"ui_right", false))
	_eq("...and the release still lands", str(view.call("held_direction")),
			str(Vector2i.ZERO))
	view.queue_free()
	await get_tree().process_frame


## End to end, through `_repaint`: the frame the renderer is actually holding has fewer
## primitives mid-ribbon than the settled one, by exactly the quads not drawn yet. Counted
## on the renderer's children rather than on the generator's return, so nothing here can
## be satisfied by the animation agreeing with itself.
func _test_the_frame_really_loses_the_quads() -> void:
	var p := WorldMapProgress.new_campaign()
	p.set_story_counter(4)
	p.set_party_node(3)
	var view := await _mount(p)
	view.call("settle_screen_in")
	var renderer: Node = view.get("renderer")
	view.call("_repaint")
	var opening := renderer.get_child_count()
	# Two vsyncs into route 12: two of its five quads are drawn, and the store's own copy
	# of the road is held back.
	view.call("advance", 1.0 / 60.0)
	view.call("advance", 1.0 / 60.0)
	view.call("_repaint")
	var mid := renderer.get_child_count()
	view.call("settle_reveal")
	view.call("_repaint")
	var settled := renderer.get_child_count()
	# [b]What the beat is WORTH, derived rather than restated[/b]: the two roads' ribbon
	# quads plus one marker cel each for the two nodes it lights. The opening frame must
	# be exactly that much smaller than the settled one — which is the assertion a frame
	# that forgot to hold the finished road back fails, because it would have drawn route
	# 12 whole from the store on the very first frame.
	var gen: WorldMapPrimitives = view.get("gen")
	var owed := gen.ribbon_quads(12).size() + gen.ribbon_quads(11).size()
	for i in [25, 8]:
		var n: Dictionary = _assets.node(i)
		owed += gen.cel_quads(_assets.static_cel(int(n["marker_frame"])),
				Vector2i.ZERO).size()
	_eq("the map opens with the whole beat still undrawn", settled - opening, owed)
	# ...and two vsyncs in it is two ribbon quads further on. Not "more": the store holds
	# route 12 as drawn already (the step wrote the bit), so the frame must be drawing the
	# growing ribbon INSTEAD of it and not as well as it.
	_eq("...and two vsyncs in the frame has exactly two ribbon quads more", mid,
			opening + 2)
	view.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- helpers

func _animate(node_index: int, store: WorldMapProgress) -> WorldMapRevealAnimation:
	return WorldMapRevealAnimation.new(
			Campaign.reveal_pass(node_index, store), _assets)


func _mount(store: WorldMapProgress) -> Node:
	var view: Node = (load(WORLD_MAP_SCENE) as PackedScene).instantiate()
	view.call("set_progress", store)                     # crossing C3: the map is HANDED it
	add_child(view)
	await get_tree().process_frame
	return view


func _action(name: StringName, pressed: bool) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = pressed
	return e


func _describe(s: Dictionary) -> String:
	var kind: StringName = s.get("kind", &"?")
	if kind == CampaignRevealPass.KIND_REVEAL_ROUTE \
			or kind == CampaignRevealPass.KIND_UNREVEAL_ROUTE:
		return "%s %d" % [kind, int(s.get("route", -1))]
	return "%s %d" % [kind, int(s.get("node", -1))]


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("%s missing — run tools/parse_world_map.py" % path)
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}


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


func _fail(msg: String) -> void:
	_failed += 1
	print("  FAIL %s" % msg)
