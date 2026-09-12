extends Node
## TDD guard for the per-opcode thumbnail (#247) that turns the sequence inspector's
## existing one-row-per-opcode list into the vertical film strip.
##
## SINCE ADR-0103 A THUMBNAIL IS THE REAL RENDER, MINUS WORLD POSITION AND CAMERA — so
## this file guards the tint, the blend and the backdrop alongside the geometry, and the
## fixture sprite no longer reads back as its own texel colour: it is drawn ADDITIVELY
## (93.5% of corpus frames are), so what lands on screen is the sprite over the backdrop.
## `_drawn` is that arithmetic, and an assertion that expects the raw texel colour is
## asserting the flat-opaque lie the ADR removed.
##
## The invariant worth guarding is the SHARED BOX. Every thumbnail in a sequence is
## handed the same `SequenceTimeline.bounds`, so a row whose opcode only MOVED the
## sprite renders visibly differently from the row above it. Derive the box per
## thumbnail instead and each one re-centres, making those rows identical — which is
## precisely the information the offset opcodes carry. Asserted by rendering and
## measuring, not by reading the code.
##
## Run: <GODOT> --path . --quit-after 30 res://tests/EffectStudioSequenceThumbnailTest.tscn
## (20 was enough before the fencepost amendment added two more rendered cells; a budget
## that is too small makes this print NOTHING and still exit 0.)

const EffectCurve = ExMateriaEffects.EffectCurve

const SequenceThumbnail = preload("res://src/effects/studio/SequenceThumbnail.gd")
const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")
const FramesetCanvas = preload("res://src/effects/studio/FramesetCanvas.gd")

const SPRITE_COLOR := Color(1, 0, 1)
const BlendLayer = preload("res://src/effects/studio/SequenceBlendLayer.gd")
const SpritePainter = preload("res://src/effects/studio/SequenceSpritePainter.gd")
const EffectCurveClass = ExMateriaEffects.EffectCurve
## The minimum rendered separation between consecutive states of the falling fixture.
## The true value is ~23px in a 64px viewport; render noise is ~0.02px.
const MIN_FALL_PX := 5.0

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_a_thumbnail_renders_its_own_opcode_state()
	await _test_move_only_opcodes_render_differently_through_the_shared_box()
	await _test_the_first_cell_is_the_first_frame_pixel_for_pixel()
	await _test_an_animation_with_no_frame_at_all_draws_nothing()
	_test_a_cell_names_the_tick_it_parks_at()
	_test_it_carries_no_height_surprise_into_a_row()
	await _test_the_colour_curve_tints_what_is_drawn()
	await _test_a_curve_at_zero_makes_the_particle_vanish()
	_test_the_quads_are_partitioned_by_blend_mode()
	await _test_the_backdrop_is_a_tunable_and_defaults_to_todays_grey()

	print("\n=== EffectStudioSequenceThumbnailTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSequenceThumbnailTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSequenceThumbnailTest")
		get_tree().quit(0)


func _test_a_thumbnail_renders_its_own_opcode_state() -> void:
	var img: Image = await _render(1)
	_assert_true(_count(img, _drawn(SPRITE_COLOR)) > 0,
		"a FRAME opcode's thumbnail draws its sprite (%d texels)" % _count(img, _drawn(SPRITE_COLOR)))


func _test_move_only_opcodes_render_differently_through_the_shared_box() -> void:
	# Cells 1, 3 and 5 hold the SAME frameset and differ only by offset. Through one
	# shared box they must render at different heights; per-thumbnail boxes would
	# re-centre them into three identical pictures.
	var rows: Array = []
	for i in [1, 3, 5]:
		var img: Image = await _render(i)
		var mean: float = _mean_row(img, _drawn(SPRITE_COLOR))
		_assert_true(mean >= 0.0, "cell %d rendered" % i)
		rows.append(mean)
	# A STRICT GAP, not just `<`: an ordering comparison alone is satisfied by ~0.02px
	# of render noise, so it would pass even against a painter that drew every state at
	# offset zero (this is exactly how the sibling canvas guard was found to be weak).
	# The real separation here is ~23px in a 64px viewport.
	_assert_true(rows[1] - rows[0] > MIN_FALL_PX and rows[2] - rows[1] > MIN_FALL_PX,
		"the same frameset sits progressively lower down the list (rows %s, need >%.0fpx apart)"
			% [rows, MIN_FALL_PX])


func _test_the_first_cell_is_the_first_frame_pixel_for_pixel() -> void:
	# THE REVERSAL, AT THE PIXEL (2026-08-20, the ADR-0102 fencepost amendment). Cell 0's
	# opcode is a SET_OFFSET, and it used to draw an empty box with a crosshair on the
	# grounds that a cell is a state readout. It now stands for t=0 — and what the game
	# puts on screen at t=0 is the first FRAME's sprite, at the first FRAME's offset. So
	# the two cells must be the SAME PICTURE, not merely both non-empty: a cell that
	# borrowed the sprite but kept its own offset would pass "draws something" and draw
	# the animation's first frame in a place it is never at.
	var first: Image = await _render(0)
	var frame: Image = await _render(1)
	var n: int = _count(first, _drawn(SPRITE_COLOR))
	_assert_true(n > 0, "cell 0 draws the sprite that is up at t=0 (%d texels)" % n)
	_assert_eq(n, _count(frame, _drawn(SPRITE_COLOR)),
		"exactly as many texels as the first FRAME's own cell")
	_assert_true(absf(_mean_row(first, _drawn(SPRITE_COLOR))
			- _mean_row(frame, _drawn(SPRITE_COLOR))) < 0.5,
		"at the same height in the shared box — the OFFSET is adopted with the frameset")
	_assert_eq(_count(first, SpritePainter.CROSSHAIR_COLOR), 0,
		"and no crosshair: there is no longer an absent sprite to stand in for")


func _test_an_animation_with_no_frame_at_all_draws_nothing() -> void:
	# The only shape that still yields a spriteless cell. No corpus animation is one, but
	# E509/E510 prove the strip has to stay navigable with nothing to draw — and the strip
	# has to say so rather than borrow a picture from somewhere.
	var tr: Array = SequenceTimeline.trace(_offsets_only_anim())
	_assert_eq(bool(tr[0].get("has_sprite", true)), false,
		"there is no first frame to adopt, so nothing is invented")
	_assert_eq(SpritePainter.blend_keys(tr[0], _framesets()), [],
		"and a spriteless cell needs no blend layer at all")
	var img: Image = await _render(0, {}, _offsets_only_anim())
	_assert_eq(_count(img, _drawn(SPRITE_COLOR)), 0, "nothing is drawn")


func _test_a_cell_names_the_tick_it_parks_at() -> void:
	# The row's TITLE names the opcode ("0: SET_OFFSET x=0 y=0"), which after the
	# amendment is no longer what the picture beside it is of. The tooltip is where that
	# is said — ADR-0102's own precedent for a sentence that would otherwise cost width.
	var tr: Array = SequenceTimeline.trace(_fall_anim())
	var t = SequenceThumbnail.new()
	_assert_eq(t.tooltip_text, SequenceThumbnail.TOOLTIP_UNBOUND,
		"an unbound cell has no tick to name yet")
	t.bind_state(tr[5], _framesets(), SequenceTimeline.bounds(tr, _framesets()), _sheet())
	_assert_eq(t.tooltip_text, "Click to park the player at tick %d" % int(tr[5].get("pos_tick")),
		"a bound one names the position it parks at, not its row index")
	t.free()


func _test_it_carries_no_height_surprise_into_a_row() -> void:
	# A thumbnail lives inside an inspector row, and a child whose combined minimum
	# exceeds the height the host assigns is what makes a container overflow — the
	# trap the canvas panel already documents. Square and small, by construction.
	var t = SequenceThumbnail.new()
	_assert_eq(t.get_combined_minimum_size(), Vector2(SequenceThumbnail.SIDE, SequenceThumbnail.SIDE),
		"the thumbnail's minimum is exactly its declared square")
	# It DOES take clicks now (ADR-0100): a click parks the player on this opcode. The
	# row it sits in no longer carries a link to compete with — the sequence header's
	# per-opcode link rows are gone and the thumbnail rides a section title instead.
	_assert_eq(t.mouse_filter, Control.MOUSE_FILTER_STOP,
		"and it takes the click that parks the player on this opcode")
	var parked := [false]
	t.clicked.connect(func(): parked[0] = true)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	t._gui_input(ev)
	_assert_true(parked[0], "a left press emits `clicked`")
	t.free()


func _test_the_colour_curve_tints_what_is_drawn() -> void:
	# ADR-0103 dec. 1: the painter's vertex colour is the particle's RESOLVED COLOUR, and
	# `draw_polygon` multiplies the texture by it — the same operation as the shader's
	# `ALBEDO = col.rgb * COLOR.rgb`. Cell 1 starts at age 0, and the PSX pairs frame k with
	# sample k (dec. 6-CORRECTED), so the fixture puts the values at index 0.
	var img: Image = await _render(1, _curves_at(0, Color(0.5, 1.0, 0.25)))
	var want := _drawn(Color(SPRITE_COLOR.r * 0.5, SPRITE_COLOR.g * 1.0, SPRITE_COLOR.b * 0.25))
	_assert_true(_count(img, want) > 50,
		"the sprite is drawn through the curve's colour, not through white (%d texels of %s)"
			% [_count(img, want), want])
	_assert_eq(_count(img, _drawn(SPRITE_COLOR)), 0,
		"and the untinted white it used to draw is gone")


func _test_a_curve_at_zero_makes_the_particle_vanish() -> void:
	# THE HEADLINE CONSEQUENCE. 35.9% of colour-enabled emitters drive their resolved
	# colour to <=8/255 somewhere in the life, and additive at `src -> 0` is the particle
	# VANISHING. Drawn flat-opaque the same moment was a black silhouette on grey — a
	# clearly visible shape at the instant the real particle is gone — which is why the
	# tint and the blend are one feature and not two.
	var lit: Image = await _render(1, _curves_at(0, Color(1, 1, 1)))
	var dark: Image = await _render(1, _curves_at(0, Color(0, 0, 0)))
	# MEASURED, not guessed: the fixture sheet is magenta on its top half only, and the
	# shared box is 8x28 (three FRAMEs, 10 units apart), so the lit sprite comes out 128
	# texels in a 64px viewport. The floor sits well under that and well over zero.
	_assert_true(_brighter_than_backdrop(lit) > 50,
		"a curve at full drives a visible sprite (%d texels)" % _brighter_than_backdrop(lit))
	_assert_eq(_brighter_than_backdrop(dark), 0,
		"a curve at zero leaves NOTHING — no silhouette, no shape, just the backdrop")
	_assert_eq(_darker_than_backdrop(dark), 0,
		"…and nothing darker than it either, which is what a black silhouette would be")


func _test_the_quads_are_partitioned_by_blend_mode() -> void:
	# Dec. 7, asserted at the level the cost model lives at: 95.3% of cells need exactly
	# ONE layer, so the common case must not pay for the mixed one. Godot's blend mode is
	# per-CanvasItem, which is what makes a layer the unit here.
	var entry: Dictionary = SequenceTimeline.trace(_fall_anim())[1]
	_assert_eq(SpritePainter.blend_keys(entry, _framesets()), [1],
		"a single-mode frameset needs exactly one layer")
	_assert_eq(SpritePainter.blend_keys(entry, _mixed_framesets()), [1, 2],
		"a frameset mixing ADD and SUB needs two, in first-appearance order")
	_assert_eq(SpritePainter.blend_keys(SequenceTimeline.trace(_offsets_only_anim())[0],
		_framesets()), [], "and a spriteless cell needs none at all")
	# `semi_trans_on` false is its OWN group: the renderer writes that frame to the opaque
	# pass and it never blends, so folding it into ADD would light it up wrongly.
	_assert_eq(SpritePainter.blend_key({"semi_trans_on": false, "semi_trans_mode": 1}),
		SpritePainter.BLEND_OPAQUE, "an opaque frame is not mode 1")
	# The PSX levels live on the SOURCE, because Godot's canvas ADD/SUB is `dst +- src*a`.
	_assert_eq(SpritePainter.blend_alpha(3), 0.25, "ADD_25 draws its source at a quarter")
	_assert_eq(SpritePainter.blend_alpha(0), 0.5, "BLEND_50 draws its source at a half")
	# And the node count follows the partition, not the frame count.
	for spec in [[_framesets(), 1], [_mixed_framesets(), 2]]:
		var t = SequenceThumbnail.new()
		add_child(t)
		t.bind_state(entry, spec[0], SequenceTimeline.bounds([entry], spec[0]), _sheet())
		_assert_eq(t.layer_count(), int(spec[1]),
			"the cell stands up %d blend layer(s)" % int(spec[1]))
		t.queue_free()


func _test_the_backdrop_is_a_tunable_and_defaults_to_todays_grey() -> void:
	# Dec. 8: the backdrop is a VIEWING CONDITION, not data — no single value serves both
	# blend families. The default keeps the strip looking as it did, and the reason to
	# scrub it to black is right here: additive over black is the particle's true colour
	# unclipped, which is the direct read-out that the blend is real.
	_assert_eq(SequenceThumbnail.backdrop, SequenceThumbnail.BG,
		"the code default is today's dark grey, so the strip arrives unchanged")
	var grey: Image = await _render(1, _curves_at(0, Color(1, 1, 1)))
	_assert_true(_count(grey, _drawn(SPRITE_COLOR)) > 50,
		"over grey, the additive sprite carries the backdrop's green with it")
	SequenceThumbnail.backdrop = Color(0, 0, 0)
	var black: Image = await _render(1, _curves_at(0, Color(1, 1, 1)))
	SequenceThumbnail.backdrop = SequenceThumbnail.BG
	_assert_true(_count(black, SPRITE_COLOR) > 50,
		"over black the SAME sprite reads its true colour, unclipped (%d texels)"
			% _count(black, SPRITE_COLOR))
	_assert_eq(_count(black, _drawn(SPRITE_COLOR)), 0,
		"…and the grey-backdrop reading is gone, so the backdrop really did move")


# --- fixtures ---------------------------------------------------------------

## What an ADDITIVE quad of colour `src` actually lands as: `dst + src`, clamped. 93.5% of
## corpus frames are additive and the fixture frames carry no explicit mode, so this is the
## arithmetic every sprite assertion in this file goes through.
func _drawn(src: Color) -> Color:
	var bg: Color = SequenceThumbnail.backdrop
	return Color(minf(1.0, bg.r + src.r), minf(1.0, bg.g + src.g), minf(1.0, bg.b + src.b))


## Three curves that resolve to `c` at index `at` and to zero everywhere else, in the
## `{r, g, b}` shape `SequenceThumbnail.bind_colour` takes.
func _curves_at(at: int, c: Color) -> Dictionary:
	return {"r": _spike(at, c.r), "g": _spike(at, c.g), "b": _spike(at, c.b)}


func _spike(at: int, v: float) -> EffectCurve:
	var vals: Array = []
	vals.resize(160)
	vals.fill(0.0)
	vals[at] = v
	return EffectCurveClass.from_array(vals)


## The same frameset, but its two member frames blend differently — the PSX double-draw
## shape (`ADD` + one other) that 4.72% of corpus framesets actually have.
func _mixed_framesets() -> Array:
	var fs: Dictionary = (_framesets()[0] as Dictionary).duplicate(true)
	var second: Dictionary = (fs["frames"][0] as Dictionary).duplicate(true)
	fs["frames"][0]["semi_trans_mode"] = 1
	second["semi_trans_mode"] = 2
	fs["frames"].append(second)
	return [fs]


func _fall_anim() -> Dictionary:
	return {"index": 0, "opcodes": [
		{"type": "SET_OFFSET", "x": 0, "y": 0},
		{"type": "FRAME", "frameset": 0, "duration": 2, "depth_mode": 1},
		{"type": "ADD_OFFSET", "dx": 0, "dy": 10},
		{"type": "FRAME", "frameset": 0, "duration": 2, "depth_mode": 1},
		{"type": "ADD_OFFSET", "dx": 0, "dy": 10},
		{"type": "FRAME", "frameset": 0, "duration": 2, "depth_mode": 1},
	]}


func _framesets() -> Array:
	return [{"frames": [{
		"uv": {"x": 0, "y": 0, "width": 8, "height": 8},
		"vertices": {"top_left": [-4, -4], "top_right": [3, -4],
			"bottom_left": [-4, 3], "bottom_right": [3, 3]},
	}]}]


func _sheet() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	for y in range(4):
		for x in range(8):
			img.set_pixel(x, y, SPRITE_COLOR)
	return ImageTexture.create_from_image(FramesetCanvas.display_image(img))


## Render ONE thumbnail, bound to cell `i` but through the WHOLE sequence's box —
## which is the point.
## An animation that never reaches a FRAME. The ONLY way to get a spriteless cell after
## the 2026-08-20 amendment: every cell before the first FRAME adopts it, and every cell
## after one inherits it, so a strip with any FRAME in it has a picture in every row.
func _offsets_only_anim() -> Dictionary:
	return {"index": 0, "opcodes": [
		{"type": "SET_OFFSET", "x": 0, "y": 0},
		{"type": "LOOP"},
	]}


func _render(i: int, curves: Dictionary = {}, anim: Dictionary = {}) -> Image:
	var trace: Array = SequenceTimeline.trace(_fall_anim() if anim.is_empty() else anim)
	var box: Rect2i = SequenceTimeline.bounds(trace, _framesets())
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var t = SequenceThumbnail.new()
	t.size = Vector2(64, 64)
	vp.add_child(t)
	t.bind_state(trace[i], _framesets(), box, _sheet())
	if not curves.is_empty():
		t.bind_colour(curves, 0)
	t.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


# --- harness ----------------------------------------------------------------

func _count(img: Image, want: Color) -> int:
	var n: int = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if absf(c.r - want.r) < 0.06 and absf(c.g - want.g) < 0.06 and absf(c.b - want.b) < 0.06:
				n += 1
	return n


## Texels inside the cell (past the 2px the backdrop and border own) that are LIGHTER
## than the backdrop — i.e. something additive was drawn there. Colour-agnostic on
## purpose: "did anything show up" is the question a vanishing particle answers.
func _brighter_than_backdrop(img: Image) -> int:
	return _off_backdrop(img, 1)


## …and DARKER, which is what a black silhouette on grey would be — the exact artefact
## ADR-0103 says un-blended tinting would have produced.
func _darker_than_backdrop(img: Image) -> int:
	return _off_backdrop(img, -1)


func _off_backdrop(img: Image, sign: int) -> int:
	var bg: Color = SequenceThumbnail.backdrop
	var n: int = 0
	for y in range(3, img.get_height() - 3):
		for x in range(3, img.get_width() - 3):
			var c := img.get_pixel(x, y)
			var d: float = maxf(maxf(c.r - bg.r, c.g - bg.g), c.b - bg.b) if sign > 0 \
				else maxf(maxf(bg.r - c.r, bg.g - c.g), bg.b - c.b)
			if d > 0.03:
				n += 1
	return n


func _mean_row(img: Image, want: Color) -> float:
	var total: float = 0.0
	var n: int = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if absf(c.r - want.r) < 0.06 and absf(c.g - want.g) < 0.06 and absf(c.b - want.b) < 0.06:
				total += float(y)
				n += 1
	return -1.0 if n == 0 else total / float(n)


func _assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s\n         expected: %s\n         actual:   %s" % [msg, expected, actual])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
