extends Node
## TDD guard for the SEQUENCE viewport's PLAYER (`SequenceCanvas.gd`) — the assembled
## animation in the band under the inspector. Its decode is pinned by
## `EffectStudioSequenceTimelineTest`; the per-opcode reel that once lived here as a
## horizontal strip is now the inspector's own rows, guarded by
## `EffectStudioSequenceThumbnailTest` and `EffectStudioSequenceViewportTest`.
##
## SINCE ADR-0103 the player is the REAL RENDER too — the painter is shared with the film
## strip, so dec. 1 says the two satisfy that together or not at all. The sprite is
## therefore drawn ADDITIVELY (the fixture frames carry no explicit mode, and 93.5% of the
## corpus is additive), on child CanvasItems rather than on the canvas: `_drawn` is the
## `dst + src` arithmetic every colour assertion below goes through, and an assertion
## expecting the raw texel colour is asserting the flat-opaque lie the ADR removed.
##
## What this file guards is that the draw path actually puts sprite pixels on screen,
## asserted by RENDERING into a SubViewport and counting texels of a known colour rather
## than by looking at a screenshot — the path has three separate ways to silently yield
## a blank or black panel (an un-erased transparent class, pixel-space UVs where
## normalized are wanted, a zero fit scale) and every one of them parses fine. Their
## teeth were established by MUTATION: an earlier draft of this file passed while the
## canvas ignored the animation offset entirely and while `display_image` was skipped.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/EffectStudioSequenceCanvasTest.tscn

const EffectCurve = ExMateriaEffects.EffectCurve

const SequenceCanvas = preload("res://src/effects/studio/SequenceCanvas.gd")
const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")
const SpritePainter = preload("res://src/effects/studio/SequenceSpritePainter.gd")
const EffectCurveClass = ExMateriaEffects.EffectCurve

var _passed: int = 0
var _failed: int = 0
## The synthetic sheet's sprite colour — chosen so it cannot be confused with the
## canvas background, a cell background, or black.
const SPRITE_COLOR := Color(1, 0, 1)
## The minimum rendered separation between two consecutive states of the falling
## fixture. See `_test_the_player_draws_the_selected_state_not_a_fixed_one` — the true
## separation is ~80px and render noise is ~0.02px, so this threshold is what makes the
## assertion mean "the offset was applied" rather than "the renders were not identical".
const MIN_FALL_PX := 5.0


func _ready() -> void:
	_test_the_shared_box_spans_the_whole_sequence()
	_test_selecting_an_opcode_parks_the_player_on_it()
	_test_a_park_lands_on_the_position_the_row_stands_for()
	_test_clicking_the_player_toggles_play_pause()
	_test_a_sequence_with_no_framesets_does_not_crash()
	_test_the_decode_is_exposed_for_the_row_thumbnails()
	_test_speed_scales_the_clock_and_is_clamped()
	_test_stepping_walks_the_opcodes_and_wraps()
	_test_the_playhead_signal_fires_once_per_opcode_not_per_frame()
	_test_resuming_unparks_so_the_still_does_not_stick()
	await _test_the_sprite_actually_renders()
	await _test_the_player_draws_the_selected_state_not_a_fixed_one()
	await _test_the_erased_class_does_not_render_as_a_black_slab()
	await _test_the_player_is_tinted_by_the_bound_curves()
	_test_the_running_player_samples_the_real_age_and_the_parked_one_the_cut()
	await _test_the_sprite_is_on_blend_layers_under_the_chrome()

	print("\n=== EffectStudioSequenceCanvasTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSequenceCanvasTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSequenceCanvasTest")
		get_tree().quit(0)


func _test_the_shared_box_spans_the_whole_sequence() -> void:
	# `bounds` is the union over EVERY step, so it is taller than any single sprite: the
	# fixture's quad is 8 tall but the sequence falls 20 units. Every thumbnail on the
	# inspector rows is fitted through this same box, which is what stops a move-only
	# opcode from re-centring into a duplicate of the row above it.
	var c := _canvas()
	_assert_eq(c._bounds, Rect2i(-4, -4, 8, 28),
		"the shared box spans the whole fall, not one sprite")
	var probe := Rect2(0, 0, 100, 100)
	_assert_eq(c._fit(probe), c._fit(probe),
		"the fit is a pure function of the box and the rect, never of the state drawn")
	c.free()


func _test_selecting_an_opcode_parks_the_player_on_it() -> void:
	var c := _canvas()
	_assert_eq(c._playing, true, "a bound sequence plays on its own clock")
	c.select_op(3)
	_assert_eq(c._selected_op, 3, "drilling into an opcode focuses it")
	_assert_eq(c._playing, false, "and parks the animation — a still that runs away is not a look")
	_assert_eq(c._tick, float(int(c._trace[3].get("pos_tick"))),
		"with the playhead on the tick that opcode's row stands for")
	c.free()


## A PARK LANDS ON THE ROW'S POSITION, NOT ON ITS DWELL'S START (2026-08-20, the
## ADR-0102 fencepost amendment — the author's call on the open question). The fall
## fixture cannot show it: every one of its FRAMEs dwells a single tick, where the two
## are the same number, which is 83.6% of the corpus. It takes a long hold and the two
## spare end slots to see the difference at all.
func _test_a_park_lands_on_the_position_the_row_stands_for() -> void:
	var c := _canvas(_hold_anim())
	_assert_eq(SequenceTimeline.total_ticks(c._trace), 9, "4 + 4 ticks of hold, then the terminal")
	c.select_op(1)
	_assert_eq(int(c._trace[1].get("tick_start")), 0, "the first hold's dwell begins at 0")
	_assert_eq(c._tick, 3.0, "but parking on it seeks to tick 3 — the END of its duration")
	c.select_op(0)
	_assert_eq(c._tick, 0.0, "the leading SET_OFFSET parks on the animation's FIRST tick")
	c.select_op(4)
	_assert_eq(c._tick, 8.0, "and the trailing LOOP on its LAST — the two the strip could not reach")
	_assert_eq(c._tick, float(SequenceTimeline.total_ticks(c._trace) - 1),
		"which is inside the sequence, so no park can seek off the end of it")
	# Every row, mechanically: a park is always legal and always lands on `pos_tick`.
	for i in range(c._trace.size()):
		c.select_op(i)
		_assert_eq(c._tick, float(int(c._trace[i].get("pos_tick"))),
			"row %d parks on its own position" % i)
	c.free()


func _test_clicking_the_player_toggles_play_pause() -> void:
	var c := _canvas()
	c._gui_input(_click(Vector2(160, 100)))
	_assert_eq(c._playing, false, "clicking the player pauses it")
	c._gui_input(_click(Vector2(160, 100)))
	_assert_eq(c._playing, true, "and clicking again resumes")
	c.free()


func _test_a_sequence_with_no_framesets_does_not_crash() -> void:
	# E509/E510: up to 14 framesets referenced against an EMPTY frames.json.
	var c = SequenceCanvas.new()
	c.size = Vector2(320, 240)
	c.bind_sequence(null, [], _fall_anim())
	_assert_eq(c._trace.size(), 6, "the decode still yields cells")
	_assert_eq(c._bounds, Rect2i(), "with an empty shared box")
	_assert_eq(c._fit(Rect2(0, 0, 100, 100))["scale"], 0.0,
		"and a zero fit scale, which the painter treats as nothing to draw")
	c._draw()   # must not crash
	_passed += 1
	c.free()


func _test_the_decode_is_exposed_for_the_row_thumbnails() -> void:
	# The canvas is the single owner of the decode: the inspector's per-opcode
	# thumbnails draw from THESE, so a row's picture and the animation above it cannot
	# disagree, and display_image runs once per texture rather than once per row.
	var c := _canvas()
	_assert_eq(c.get_trace().size(), 6, "the trace is reachable")
	_assert_eq(c.get_bounds(), c._bounds, "so is the shared box")
	_assert_eq(c.get_framesets().size(), 1, "and the framesets")
	_assert_true(c.get_display_texture() != null,
		"and the ERASED display texture — handing out the raw sheet would paint black slabs")
	c.free()


## The pace control. TRUE game speed loops the 6-tick fixture five times a second;
## authoring needs to watch it, so the clock is multiplied — and the multiplier is
## clamped HERE, in the one place, rather than trusted to whichever widget drives it.
func _test_speed_scales_the_clock_and_is_clamped() -> void:
	var c := _live_canvas()
	c.set_speed(0.5)
	_assert_eq(c.speed(), 0.5, "the rate is taken")
	c._tick = 0.0
	c._process(1.0 / SequenceCanvas.TRANSPORT_HZ)   # exactly one tick at 1.00x
	_assert_eq(c._tick, 0.5, "and halves the ticks a frame advances")
	c.set_speed(1.0)
	c._tick = 0.0
	c._process(1.0 / SequenceCanvas.TRANSPORT_HZ)
	_assert_eq(c._tick, 1.0, "1.00x is true game speed — one tick per 1/30s")
	c.set_speed(99.0)
	_assert_eq(c.speed(), SequenceCanvas.SPEED_MAX, "an out-of-range rate clamps up")
	c.set_speed(-3.0)
	_assert_eq(c.speed(), SequenceCanvas.SPEED_MIN, "and down — never to zero or backwards")
	c.free()


## The step buttons. There are 6 opcodes in the fixture, so stepping back from 0 must
## land on 5: the sequence loops, and a transport that dead-ends at the edges of a loop
## is lying about the thing it is playing.
func _test_stepping_walks_the_opcodes_and_wraps() -> void:
	var c := _canvas()
	c.select_op(0)
	c.step_op(1)
	_assert_eq(c.selected_op(), 1, "next lands on the following opcode")
	c.step_op(-1)
	_assert_eq(c.selected_op(), 0, "prev comes back")
	c.step_op(-1)
	_assert_eq(c.selected_op(), 5, "and prev from 0 wraps to the last opcode")
	c.step_op(1)
	_assert_eq(c.selected_op(), 0, "as next from the last wraps to 0")
	_assert_eq(c._playing, false, "every step parks — the point is to look at the state")
	# From UNPARKED, a step is relative to what you were watching, not to opcode 0.
	var d := _canvas()
	d._tick = float(int(d._trace[3].get("tick_start", 0)))
	var watching: int = d.playhead_op()
	d.step_op(1)
	_assert_eq(d.selected_op(), (watching + 1) % 6,
		"an unparked step continues from the playhead, not from the start")
	c.free()
	d.free()


## The mark signal is the thumbnails' whole feed, and it runs inside `_process`. Emitting
## it every frame would repaint every thumbnail 60 times a second for a picture that
## changes a handful of times a loop; the gate is what makes it affordable.
func _test_the_playhead_signal_fires_once_per_opcode_not_per_frame() -> void:
	var c := _live_canvas()
	var seen: Array = []
	c.playhead_changed.connect(func(op): seen.append(op))
	# A quarter-tick per frame, so 60 frames cover 15 ticks. This fixture is the HARSHEST
	# case for the gate at 1.00x — a FRAME dwells `max(1, duration >> 1)` ticks, so all
	# three of its time-occupying cells dwell exactly ONE tick and the playhead genuinely
	# does move every tick there. Slow it down and the difference between "per opcode"
	# and "per frame" becomes measurable, which is also the point of the speed control.
	c.set_speed(0.25)
	c._playing = true
	c._tick = 0.0
	c._last_playhead_op = c.playhead_op()
	for _i in range(60):
		c._process(1.0 / SequenceCanvas.TRANSPORT_HZ)
	_assert_eq(c._total_ticks, 3, "the fixture runs 3 ticks (duration 2 dwells 1 tick)")
	_assert_true(seen.size() > 0, "the playhead does move (%d emissions)" % seen.size())
	_assert_true(seen.size() <= 15,
		"but at most once per TICK crossed, never once per frame — 60 frames, %d emissions"
			% seen.size())
	var repeats: int = 0
	for i in range(1, seen.size()):
		if seen[i] == seen[i - 1]:
			repeats += 1
	_assert_eq(repeats, 0, "and never twice in a row for the same opcode")
	c.free()


## `_draw` prefers the PARKED cell whenever the player is stopped. Resuming without
## clearing the park would therefore keep showing one frozen still while the tick ran
## on underneath — playback that looks broken but reports itself as playing.
func _test_resuming_unparks_so_the_still_does_not_stick() -> void:
	var c := _canvas()
	c.select_op(3)
	_assert_eq(c.selected_op(), 3, "parked")
	c._gui_input(_click(Vector2(160, 100)))
	_assert_eq(c._playing, true, "clicking the parked player resumes it")
	_assert_eq(c.selected_op(), -1, "and unparks, so the still does not stick")
	# Clicking a thumbnail for the opcode already parked, while running, must re-park.
	c.select_op(3)
	c._playing = true
	c.select_op(3)
	_assert_eq(c._playing, false, "re-picking the parked opcode while running parks again")
	c.free()


func _test_the_sprite_actually_renders() -> void:
	# The end-to-end proof. Three independent bugs (un-erased transparent class,
	# pixel-space UVs, a zero fit) each yield a blank or black panel and all parse.
	var img: Image = await _render(_canvas())
	var hits: int = _count_color(img, _drawn(SPRITE_COLOR))
	_assert_true(hits > 0, "the composited sprite reaches the framebuffer (%d texels)" % hits)


func _test_the_player_draws_the_selected_state_not_a_fixed_one() -> void:
	# Cells 1, 3 and 5 hold the SAME frameset and differ only by offset, so parking on
	# each in turn must move the sprite down the panel. A player that ignored the
	# offset — or that always drew cell 0 — renders them identically.
	var rows: Array = []
	for i in [1, 3, 5]:
		var c := _canvas()
		c.select_op(i)
		var img: Image = await _render(c)
		var mean: float = _mean_row(img, _drawn(SPRITE_COLOR), Rect2(0, 0, 320, 240))
		_assert_true(mean >= 0.0, "opcode %d rendered its sprite" % i)
		rows.append(mean)
	# A STRICT GAP, not just `<`. A bare ordering comparison passed while the painter
	# drew every state at offset zero: the three renders still differed by 0.016px of
	# pure render noise, which satisfies `<` and asserts nothing. The real signal is
	# ~80px — the fall is 10 of the box's 28 PSX units across a ~224px panel — so any
	# threshold between the two separates them, and 5px is comfortably clear of noise
	# while staying far under the true value.
	_assert_true(rows[1] - rows[0] > MIN_FALL_PX and rows[2] - rows[1] > MIN_FALL_PX,
		"the same frameset draws progressively lower as the sequence falls (rows %s, need >%.0fpx apart)"
			% [rows, MIN_FALL_PX])


func _test_the_erased_class_does_not_render_as_a_black_slab() -> void:
	# The sprite block is half black, and that black is the extractor's "erased" value.
	# It must not paint: the panel background has to show through it.
	var c := _canvas()
	c.select_op(1)
	var img: Image = await _render(c)
	_assert_true(_count_color(img, _drawn(SPRITE_COLOR)) > 0, "the visible half of the sprite draws")
	_assert_eq(_count_color(img, Color(0, 0, 0)), 0,
		"and the erased half draws NOTHING — no black slab over the background")


func _test_the_player_is_tinted_by_the_bound_curves() -> void:
	# ADR-0103 dec. 1: the player is a free rider on the shared painter, so it lights up
	# with the strip. Opcode 1 starts at age 0, and the PSX pairs frame k with sample k
	# (dec. 6-CORRECTED), so the spike goes at index 0.
	var c := _canvas()
	c.select_op(1)
	c.bind_colour(_spike(0, 0.5), _spike(0, 1.0), _spike(0, 0.25))
	var img: Image = await _render(c)
	var want := _drawn(Color(SPRITE_COLOR.r * 0.5, SPRITE_COLOR.g, SPRITE_COLOR.b * 0.25))
	_assert_true(_count_color(img, want) > 0,
		"the player draws through the curve, not through white (%d texels of %s)"
			% [_count_color(img, want), want])
	_assert_eq(_count_color(img, _drawn(SPRITE_COLOR)), 0, "and the white it drew is gone")


func _test_the_running_player_samples_the_real_age_and_the_parked_one_the_cut() -> void:
	# The player has a REAL clock, so while it runs its phase is the actual particle age
	# (`_tick` minus the cell's own `cut_start`) rather than the cut's free-running loop.
	# One expression covers both because `cell_color` wraps at the piece length.
	var c := _canvas()
	c.bind_colour(_ramp(), _ramp(), _ramp())
	c.select_op(1)   # parks; opcode 1's window is tick 0, one tick -> age 0, sample 0
	_assert_near(c.cell_modulate(1).r, 0.0,
		"a parked one-frame cell resolves to its own single age")
	c._cut_t = 7.0
	_assert_near(c.cell_modulate(1).r, 0.0,
		"…and the cut's phase cannot walk it off that one-age piece")
	# Running, the phase is the tick itself — the same number the playhead is showing.
	c._playing = true
	c._tick = 2.0
	_assert_eq(c.shown_op(), 5, "tick 2 is the third FRAME cell (the offset cells own no ticks)")
	_assert_near(c.cell_modulate(c.shown_op()).r, 2.0 / 255.0,
		"a running player samples the age the transport is actually at — tick 2 is sample 2, "
		+ "not 3 (dec. 6-CORRECTED)")
	c.free()


func _test_the_sprite_is_on_blend_layers_under_the_chrome() -> void:
	# Dec. 7 on the player: the quads move to child CanvasItems because Godot's blend mode
	# is per-CanvasItem. The transport read-out has to stay ABOVE them — children draw over
	# their parent, so a glyph left on the canvas would end up buried under a bright
	# additive sprite, and that glyph is the affordance saying a click plays.
	var c := _live_canvas()
	c.select_op(1)
	await _frames(2)
	_assert_eq(c.layer_count(), 1, "a single-mode cell draws on exactly one layer")
	_assert_eq(c.get_child(c.get_child_count() - 1), c._chrome,
		"and the transport read-out is the LAST child, so nothing paints over it")
	c.queue_free()


# --- fixtures ---------------------------------------------------------------

## What an ADDITIVE quad of colour `src` lands as over the player's background: `dst + src`,
## clamped. The fixture frames carry no explicit mode, so they take the corpus default.
func _drawn(src: Color) -> Color:
	var bg: Color = SequenceCanvas.BG_COLOR
	return Color(minf(1.0, bg.r + src.r), minf(1.0, bg.g + src.g), minf(1.0, bg.b + src.b))


## A curve that is `v` at index `at` and zero elsewhere.
func _spike(at: int, v: float) -> EffectCurve:
	var vals: Array = []
	vals.resize(160)
	vals.fill(0.0)
	vals[at] = v
	return EffectCurveClass.from_array(vals)


## A curve whose sample at index f is f/255, so a resolved channel reads back the age it
## was sampled at — which is what makes the clock question assertable at all.
func _ramp() -> EffectCurve:
	var vals: Array = []
	for i in range(160):
		vals.append(float(i) / 255.0)
	return EffectCurveClass.from_array(vals)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## The corpus shape with a LONG HOLD in it: SET_OFFSET, two 4-tick holds, a terminal
## frame, LOOP. Every FRAME in `_fall_anim` dwells one tick, where a dwell's start and
## its end are the same number — so only this fixture can tell a park at `tick_start`
## from a park at `pos_tick`.
func _hold_anim() -> Dictionary:
	return {"index": 0, "opcodes": [
		{"type": "SET_OFFSET", "x": 0, "y": 0},
		{"type": "FRAME", "frameset": 0, "duration": 8, "depth_mode": 1},
		{"type": "FRAME", "frameset": 0, "duration": 8, "depth_mode": 1},
		{"type": "FRAME", "frameset": 0, "duration": 0, "depth_mode": 1},
		{"type": "LOOP"},
	]}


## A falling sprite: SET_OFFSET then three FRAMEs of the SAME frameset at three
## offsets, then LOOP. The corpus shape (E190 anim 2) reduced to its essentials —
## the repeated frameset is what makes the offset rule testable.
func _fall_anim() -> Dictionary:
	return {"index": 0, "opcodes": [
		{"type": "SET_OFFSET", "x": 0, "y": 0},
		{"type": "FRAME", "frameset": 0, "duration": 2, "depth_mode": 1},
		{"type": "ADD_OFFSET", "dx": 0, "dy": 10},
		{"type": "FRAME", "frameset": 0, "duration": 2, "depth_mode": 1},
		{"type": "ADD_OFFSET", "dx": 0, "dy": 10},
		{"type": "FRAME", "frameset": 0, "duration": 2, "depth_mode": 1},
	]}


## An 8x8 sprite block on a 16x16 sheet, deliberately HALF BLACK: rows 0-3 are the
## sprite colour and rows 4-7 are black — INSIDE the block the UV addresses, not
## merely around it. That is what makes `display_image` load-bearing in this fixture.
## RGBA has no "erased" value so the extractor carries `0x0000` as opaque black, and
## a viewport that skipped the erase would paint those rows as a solid black slab
## rather than letting the cell background show through. A block of pure sprite
## colour cannot catch that: there would be no black texel to mis-draw.
func _sheet() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	for y in range(4):
		for x in range(8):
			img.set_pixel(x, y, SPRITE_COLOR)
	return ImageTexture.create_from_image(img)


func _framesets() -> Array:
	return [{"frames": [{
		"uv": {"x": 0, "y": 0, "width": 8, "height": 8},
		"vertices": {"top_left": [-4, -4], "top_right": [3, -4],
			"bottom_left": [-4, 3], "bottom_right": [3, 3]},
	}]}]


## A canvas IN THE TREE. `_process` bails on `is_visible_in_tree()`, so anything that
## drives the clock has to be parented or it silently measures nothing.
func _live_canvas() -> Control:
	var c := _canvas()
	add_child(c)
	return c


func _canvas(anim: Dictionary = {}) -> Control:
	var c = SequenceCanvas.new()
	c.size = Vector2(320, 240)
	c.bind_sequence(_sheet(), _framesets(), _fall_anim() if anim.is_empty() else anim)
	return c


# --- harness ----------------------------------------------------------------

func _click(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	return e


func _render(c: Control) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 240)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	add_child(vp)
	vp.add_child(c)
	c.size = Vector2(320, 240)
	c.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


## The mean framebuffer ROW of a colour inside `area`, or -1 when it is absent.
## A centroid rather than a first-hit: it moves smoothly with the sprite instead of
## snapping between texel rows.
func _mean_row(img: Image, want: Color, area: Rect2) -> float:
	var total: float = 0.0
	var n: int = 0
	var x0: int = maxi(0, int(area.position.x))
	var y0: int = maxi(0, int(area.position.y))
	var x1: int = mini(img.get_width(), int(area.position.x + area.size.x))
	var y1: int = mini(img.get_height(), int(area.position.y + area.size.y))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			if absf(c.r - want.r) < 0.06 and absf(c.g - want.g) < 0.06 and absf(c.b - want.b) < 0.06:
				total += float(y)
				n += 1
	return -1.0 if n == 0 else total / float(n)


func _count_color(img: Image, want: Color) -> int:
	return _count_color_in(img, want, Rect2(0, 0, img.get_width(), img.get_height()))


func _count_color_in(img: Image, want: Color, area: Rect2) -> int:
	var n: int = 0
	var x0: int = maxi(0, int(area.position.x))
	var y0: int = maxi(0, int(area.position.y))
	var x1: int = mini(img.get_width(), int(area.position.x + area.size.x))
	var y1: int = mini(img.get_height(), int(area.position.y + area.size.y))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			if absf(c.r - want.r) < 0.06 and absf(c.g - want.g) < 0.06 and absf(c.b - want.b) < 0.06:
				n += 1
	return n


func _assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s\n         expected: %s\n         actual:   %s" % [msg, expected, actual])


func _assert_near(actual: float, expected: float, msg: String) -> void:
	if absf(actual - expected) < 0.002:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s\n         expected: %f\n         actual:   %f" % [msg, expected, actual])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
