extends Node
## Slice 3 — the colour picker (ADR-0089 colour-keyframe amendment, decision 4, amended
## 2026-08-21: the picker authors the CURVE, and the sprite's bound is REPORTED rather than
## applied to the pick).
##
## The picked RGB IS the three curve values, 0..255 → 0..1 per channel. Nothing here consults
## the sprite texel `S` on the way in; `S` is what `renders_as()` muxes through and what
## `dead_channels()` reports. This proves:
##   • seeding clamps to the unit cube and NOTHING else — the fix for the fighting control,
##     since the page re-seeds on every drag frame;
##   • a pick anywhere in [0,1]³ is returned as picked, for a sprite that would have crushed it;
##   • a dead channel (S.k == 0) is REPORTED, and the pick in that channel is still authored —
##     it renders black, which is the sprite's doing, not the widget's;
##   • `renders_as()` is the sprite's multiply, so the picker can state the bound it no longer
##     imposes;
##   • the emitted `curve_picked` colour equals the picked colour.
##
## Run: godot --path . --quit-after 30 res://tests/ColourBoxPickerTest.tscn

const ColourBoxPicker = preload("res://src/effects/studio/ColourBoxPicker.gd")

var _passed: int = 0
var _failed: int = 0
var _last_picked: Color = Color.BLACK
var _pick_count: int = 0


func _ready() -> void:
	_test_picker_is_an_inline_grid()
	_test_seed_keeps_what_it_is_given()
	_test_pick_keeps_the_whole_cube()
	_test_dead_channel_is_reported_not_locked()
	_test_pick_emits_the_picked_colour()

	print("\n=== ColourBoxPickerTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourBoxPickerTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourBoxPickerTest")
		get_tree().quit(0)


func _make(s: Color) -> ColourBoxPicker:
	var p := ColourBoxPicker.new()
	add_child(p)
	p.set_gamut(s)
	return p


## ADR-0089 editing-UX amendment (decision 1): the picker is the FULL inline colour grid
## (a ColorPicker), not a swatch button that opens a popup — expand once, it stays. It keeps
## the same authoring API (pick/seed/gamut/dead_channels), so only the widget shape changed.
func _test_picker_is_an_inline_grid() -> void:
	var p := _make(Color(0.6, 0.6, 0.6, 1.0))
	# A ColorPicker IS the inline grid; a ColorPickerButton (the old popup swatch) is a Button and
	# is NOT a ColorPicker, so this positive check distinguishes the two shapes.
	_assert_true(p is ColorPicker, "the picker IS an inline ColorPicker grid, not a popup swatch button")
	p.queue_free()


## SEEDING CLAMPS TO THE UNIT CUBE AND NOTHING ELSE, and that is the whole of the fighting
## control. `EffectStudioPage._update_colour_picker_panel` re-seeds on EVERY drag frame; while
## the seed was `clamp_to_box`, each mouse-move toward a bright colour was overwritten with the
## darker in-box value and the grid crawled back under the cursor. A seed still fires NO pick
## (the screen-picker convention).
func _test_seed_keeps_what_it_is_given() -> void:
	var p := _make(Color(0.8, 0.6, 0.4, 1.0))  # a sprite that WOULD have clamped every channel
	_pick_count = 0
	p.seed_curve(Color(1.0, 0.5, 0.9, 1.0))
	_assert_approx(p.color.r, 1.0, "seed R survives a dark sprite")
	_assert_approx(p.color.g, 0.5, "seed G unchanged")
	_assert_approx(p.color.b, 0.9, "seed B survives a dark sprite")
	_assert_eq(_pick_count, 0, "seed fires no pick")
	# A seed genuinely out of range is still bounded — a curve sample is a byte.
	p.seed_curve(Color(1.6, -0.2, 0.5, 1.0))
	_assert_approx(p.color.r, 1.0, "seed R clamped to 1")
	_assert_approx(p.color.g, 0.0, "seed G clamped to 0")
	p.queue_free()


## EVERY CURVE VALUE IS AUTHORABLE, WHATEVER THE SPRITE — the author's ask, as an assertion.
## Against a sprite that would previously have clamped all three channels, white comes back as
## white: curve (1,1,1), the sprite unmodified, the brightest ALBEDO the multiply can make.
## Censused, 97.5% of the 3213 corpus colour emitters had NO channel whose byte slider could
## hold 255 under the old model.
func _test_pick_keeps_the_whole_cube() -> void:
	var p := _make(Color(0.8, 0.6, 0.4, 1.0))
	var got: Color = p.pick(Color(1.0, 1.0, 1.0, 1.0))
	_assert_approx(got.r, 1.0, "picked R survives")
	_assert_approx(got.g, 1.0, "picked G survives")
	_assert_approx(got.b, 1.0, "picked B survives")
	# …and the bound is STATED instead: what that pick renders as is the sprite itself.
	p.color = Color(1.0, 1.0, 1.0, 1.0)
	var renders: Color = p.renders_as()
	_assert_approx(renders.r, 0.8, "renders_as R = the sprite's own value")
	_assert_approx(renders.g, 0.6, "renders_as G = the sprite's own value")
	_assert_approx(renders.b, 0.4, "renders_as B = the sprite's own value")
	p.queue_free()


## A dead channel (S.k == 0) is REPORTED, not locked. The curve is still authored there and
## still saved; it renders black because a multiply cannot add light the sprite lacks. The note
## is `dead_channels()` finally having a caller — it was written as "informational … callers use
## it to explain the limit" and had none for the whole life of the muxed picker.
func _test_dead_channel_is_reported_not_locked() -> void:
	var p := _make(Color(0.8, 0.0, 0.5, 1.0))  # green dead
	var dead: Dictionary = p.dead_channels()
	_assert_eq(int(dead.get("r", -1)), 0, "R alive")
	_assert_eq(int(dead.get("g", -1)), 1, "G dead")
	_assert_eq(int(dead.get("b", -1)), 0, "B alive")
	var got: Color = p.pick(Color(0.5, 0.9, 0.5, 1.0))
	_assert_approx(got.g, 0.9, "the dead channel's pick is still authored")
	p.color = got
	_assert_approx(p.renders_as().g, 0.0, "…and still renders black")
	_assert_true(p.dead_channel_tag() == "no G", "the tag NAMES the dead channel")
	_assert_true(p.dead_channel_note().find("G") >= 0, "…and the tooltip explains it")
	_assert_true(_make(Color(0.8, 0.4, 0.5, 1.0)).dead_channel_tag() == "",
		"a sprite that lights all three says nothing")
	p.queue_free()


## The signal fans the PICKED curve colour, and `picked()` reports the same thing from the
## swatch — the seam the ⬥ button reads, because a pick on an interpolated age authors nothing
## and there is no last signal to remember.
func _test_pick_emits_the_picked_colour() -> void:
	var p := _make(Color(0.6, 0.6, 0.6, 1.0))
	_last_picked = Color.BLACK
	p.curve_picked.connect(_on_picked)
	var got: Color = p.pick(Color(0.9, 0.3, 0.1, 1.0))
	_assert_approx(_last_picked.r, got.r, "emitted R == picked")
	_assert_approx(_last_picked.g, got.g, "emitted G == picked")
	_assert_approx(_last_picked.b, got.b, "emitted B == picked")
	p.color = Color(0.9, 0.3, 0.1, 1.0)
	_assert_approx(p.picked().r, 0.9, "picked() reads the swatch, unprojected")
	p.queue_free()


func _on_picked(c: Color) -> void:
	_last_picked = c
	_pick_count += 1


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)


func _assert_eq(got: int, expected: int, label: String) -> void:
	if got == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %d, expected %d)" % [label, got, expected])


func _assert_approx(got: float, expected: float, label: String) -> void:
	if is_equal_approx(got, expected) or absf(got - expected) < 0.0006:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %f, expected %f)" % [label, got, expected])
