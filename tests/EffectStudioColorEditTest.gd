extends Node
## TDD guard for Effect Studio Screen-colour authoring — the #255 edit choke point made
## reachable by a human, now via a WYSIWYG **target-colour picker**. The mode-5 screen Blend
## param is a SIGNED byte applied doubled, so ±128 is not a colour chart; instead the author
## picks the colour the backdrop TOP should BECOME at the parked frame and a BlendTargetSolver
## back-solves the param through the REAL forward blend fold (BlendTargetSolverTest guards the
## search). This test guards the WIDGET seam — projector → inspector picker → page → host:
##
##   (1) ScreenTweenProjector.sections(kf, field_ctx) emits an EDITABLE Blend "Color" cell
##       (shape "edit", editor "target_color") carrying the three per-component field_refs
##       {channel:"screen", context, event_index, field:"start_r"|"start_g"|"start_b"} — the
##       write-side addresses the solver's chosen bytes lower through.
##   (2) EffectKeyframeInspector renders an "edit"/"target_color" cell as ONE ColorPickerButton
##       (RGB only, no alpha) SEEDED with the cell's `seed` colour (the live resulting top
##       colour, injected by the page). Seeding fires NO pick; a colour change fans (field_refs,
##       picked_colour) to the on_pick_target callback, whose returned ACHIEVED colour updates a
##       read-only "actual" swatch (the honest feedback when a target is unreachable).
##   (3) EffectStudioPage's pick callback forwards (field_refs, colour) to the host via
##       studio_pick_target, and the page injects the seed from the host's studio_screen_top_color.
##   (4) End-to-end: selecting a screen span renders the picker, and a colour change lowers ONE
##       solve+apply to the host — the whole inspector → page → host authoring path.
##
## The live in-place repaint + the solve/apply correctness are HEADFUL-verified separately
## (tools/verify_target_color_pick). See CONTEXT.md "Authoring model".
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioColorEditTest.tscn

const ScreenData = ExMateriaEffects.ScreenData

const Projector = preload("res://src/effects/studio/ScreenTweenProjector.gd")
const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_blend_color_cell_is_a_target_color_editor_with_field_refs()
	_test_inspector_renders_a_seeded_picker_and_fans_picks_with_actual_feedback()
	_test_inspector_renders_gradient_stop_pickers_that_fan_byte_writes()
	await _test_page_pick_forwards_to_host_and_injects_seed()
	await _test_selecting_screen_span_wires_target_pick_to_host()
	await _test_screen_delta_edit_materializes_into_the_row()

	print("\n=== EffectStudioColorEditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioColorEditTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioColorEditTest")
		get_tree().quit(0)


# --- Seam 1: projector emits the editable target-colour cell ---------------

## A Blend tween's "Color" cell is EDITABLE as a target-colour editor (shape "edit", editor
## "target_color") carrying one field_ref per component so the solver's chosen bytes can lower
## each raw byte through the choke point. The cell authors the RESULT, not the raw param.
func _test_blend_color_cell_is_a_target_color_editor_with_field_refs() -> void:
	var ctx := {"context": "for_each", "event_index": 0}
	var secs := Projector.sections(_blend_kf_raw(26, 31, 200), ctx)
	var cell := _field(secs[0], "Color")

	_assert_eq(cell.get("shape", ""), "edit", "the Blend Color cell is editable")
	_assert_eq(cell.get("editor", ""), "target_color", "it is a target-colour editor")

	var refs: Dictionary = cell.get("field_refs", {})
	_assert_true(refs.get("r", {}) == {"channel": "screen", "context": "for_each", "event_index": 0, "field": "start_r"},
		"the R component field_ref addresses start_r on this screen tween")
	_assert_true(refs.get("g", {}) == {"channel": "screen", "context": "for_each", "event_index": 0, "field": "start_g"},
		"the G component field_ref addresses start_g")
	_assert_true(refs.get("b", {}) == {"channel": "screen", "context": "for_each", "event_index": 0, "field": "start_b"},
		"the B component field_ref addresses start_b")


# --- Seam 2: inspector renders a seeded picker & fans picks -----------------

## The inspector renders an "edit"/"target_color" cell as ONE RGB ColorPickerButton seeded with
## the cell's `seed` colour. Seeding fires NO pick; changing the colour fans (field_refs,
## picked_colour) to on_pick_target, and the ACHIEVED colour it returns updates the read-only
## "actual" swatch.
func _test_inspector_renders_a_seeded_picker_and_fans_picks_with_actual_feedback() -> void:
	var seed := Color(0.2, 0.4, 0.6)
	var achieved := Color(0.9, 0.1, 0.3)   # the (fake) solver's best-achievable result
	var secs := _blend_sections_with_seed(_blend_kf_raw(26, 31, 200), {"context": "for_each", "event_index": 0}, seed)
	var insp = Inspector.new()
	add_child(insp)

	var picks: Array = []
	insp.show_target(Target.span("screen:for_each#0"),
		[], secs,
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_ref, _raw): pass,
		func(refs, col): picks.append([refs, col]); return achieved)

	var widgets: Array = insp.pick_widgets()
	_assert_eq(widgets.size(), 1, "the Blend Color cell renders ONE colour picker")
	if widgets.is_empty():
		return

	var picker = widgets[0]
	_assert_true(picker.color.is_equal_approx(seed), "the picker is seeded with the live top colour")
	_assert_eq(picker.edit_alpha, false, "the picker edits RGB only (no alpha — the backdrop is opaque)")
	_assert_eq(picks.size(), 0, "seeding the picker fires NO spurious pick")

	# A colour change fans the picked colour + this tween's field_refs to on_pick_target.
	var picked := Color(0.8, 0.5, 0.2)
	picker.color = picked
	picker.color_changed.emit(picked)
	_assert_eq(picks.size(), 1, "changing the picker fires exactly one pick")
	if picks.is_empty():
		return
	_assert_true(picks[0][1].is_equal_approx(picked), "the picked target colour is forwarded verbatim")
	var refs: Dictionary = picks[0][0]
	_assert_true(refs.get("r", {}).get("field", "") == "start_r" and refs.get("r", {}).get("channel", "") == "screen",
		"the pick carries the tween's write-side field_refs")

	# The achieved colour the callback returns updates the read-only actual swatch.
	var swatch = insp.actual_swatch()
	_assert_true(swatch != null and swatch.color.is_equal_approx(achieved),
		"the achieved colour updates the actual-result swatch (honest 'nearest match' feedback)")


# --- Seam 2b: inspector renders the Gradient stop pickers ------------------

## A Gradient tween's two stop cells render as plain RGB ColorPickerButtons (editor
## "gradient_color") — one per stop, each SEEDED to its stop colour. Unlike the Blend
## target_color cell there is NO solver: a Gradient stop is an unsigned ABSOLUTE colour, so a
## colour change fans THREE direct byte writes (round(c·255)) for the stop's r/g/b field_refs
## through the BYTE choke point (_on_mutate), not the target-solve path (_on_pick_target).
func _test_inspector_renders_gradient_stop_pickers_that_fan_byte_writes() -> void:
	var secs := Projector.sections(_gradient_kf_raw(10, 20, 30, 40, 50, 60), {"context": "for_each", "event_index": 0})
	var insp = Inspector.new()
	add_child(insp)

	var mutations: Array = []
	var picks: Array = []
	insp.show_target(Target.span("screen:for_each#0"),
		[], secs,
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(ref, raw): mutations.append([ref, raw]),
		func(refs, col): picks.append([refs, col]); return Color.BLACK)

	var pickers: Array = insp.gradient_pickers()
	_assert_eq(pickers.size(), 2, "the Gradient tween renders TWO stop pickers (top + bottom)")
	if pickers.size() != 2:
		return
	_assert_true(pickers[0].color.is_equal_approx(Color(10 / 255.0, 20 / 255.0, 30 / 255.0)),
		"the Top picker is seeded to start_color")
	_assert_true(pickers[1].color.is_equal_approx(Color(40 / 255.0, 50 / 255.0, 60 / 255.0)),
		"the Bottom picker is seeded to end_color")
	_assert_eq(pickers[0].edit_alpha, false, "the stop pickers edit RGB only (opaque backdrop)")
	_assert_eq(mutations.size(), 0, "seeding the pickers fires NO spurious write")
	_assert_eq(picks.size(), 0, "a Gradient stop uses the byte choke point, NOT the solver pick path")

	# Change the BOTTOM stop → three direct byte writes to end_r/g/b, each round(c·255).
	var picked := Color(200 / 255.0, 100 / 255.0, 50 / 255.0)
	pickers[1].color = picked
	pickers[1].color_changed.emit(picked)
	_assert_eq(mutations.size(), 3, "one stop change fans exactly three component byte writes")
	_assert_eq(picks.size(), 0, "still no solver pick — Gradient is a direct absolute set")
	var by_field := {}
	for m in mutations:
		by_field[m[0].get("field", "")] = m[1]
	_assert_eq(by_field.get("end_r", -1), 200, "end_r written as round(0.784·255)=200")
	_assert_eq(by_field.get("end_g", -1), 100, "end_g written as round(0.392·255)=100")
	_assert_eq(by_field.get("end_b", -1), 50, "end_b written as round(0.196·255)=50")


# --- Seam 3: page pick → host.studio_pick_target + seed injection ----------

## The page's pick callback forwards (field_refs, colour) straight to the host's
## studio_pick_target, and the page injects the picker seed from the host's live top colour.
func _test_page_pick_forwards_to_host_and_injects_seed() -> void:
	var page = await _page()
	var host = page._host
	host.reset()

	var refs := {"r": {"channel": "screen", "context": "for_each", "event_index": 0, "field": "start_r"}}
	var col := Color(0.3, 0.6, 0.9)
	var out = page._pick_target(refs, col)

	_assert_eq(host.pick_calls, 1, "the page pick callback forwards to the host once")
	_assert_true(host.last_pick_refs == refs, "the field_refs are forwarded verbatim")
	_assert_true(host.last_pick_color.is_equal_approx(col), "the picked colour is forwarded verbatim")
	_assert_true(out is Color and out.is_equal_approx(host.pick_return),
		"the page returns the host's achieved colour to the widget")


# --- Seam 4: end-to-end select → pick → host -------------------------------

## Selecting a screen span renders the target-colour picker seeded from the host's live top
## colour, and a colour change lowers ONE solve+apply to the host.
func _test_selecting_screen_span_wires_target_pick_to_host() -> void:
	var page = await _page()
	page._load_effect(_effect_dir(page, "E001"))   # has Blend screen spans
	var host = page._host
	host.reset()

	var span_id := _first_screen_span(page)
	_assert_true(span_id != "", "the loaded effect has a screen span to select")
	if span_id == "":
		return
	page._on_span_selected(span_id)

	var widgets: Array = page._inspector.pick_widgets()
	_assert_eq(widgets.size(), 1, "the selected screen span renders one target-colour picker")
	if widgets.is_empty():
		return
	_assert_true(widgets[0].color.is_equal_approx(host.pick_return),
		"the picker is seeded from the host's live top colour")

	var picked := Color(0.7, 0.2, 0.5)
	widgets[0].color = picked
	widgets[0].color_changed.emit(picked)

	_assert_eq(host.pick_calls, 1, "the colour change lowers ONE solve+apply to the host")
	_assert_true(host.last_pick_refs.get("r", {}).get("channel", "") == "screen",
		"the host receives screen-channel field_refs")


# --- Seam 5: the screen Δ row materializes like palette's (ADR-0087 dec. 12) ----

## Selecting a screen Blend span renders the signed-Δ row + "No tint" reset over the SAME
## start_r/g/b bytes the picker solves. An edit through the page (here: the reset, which fans
## three zero writes but never touches the boxes itself) must MATERIALIZE back into the row —
## the boxes can only reach 0 through the page's screen tint-refresh loop — and, since the
## reset was not the picker, move the picker to the achieved (live top) colour too.
func _test_screen_delta_edit_materializes_into_the_row() -> void:
	var page = await _page()
	page._load_effect(_effect_dir(page, "E001"))
	var host = page._host
	host.reset()
	host.bind_data(page._effect_data)
	page._on_span_selected(_first_screen_span(page))

	var boxes: Array = page._inspector.signed_rgb_widgets()
	_assert_eq(boxes.size(), 3, "the screen Blend section renders the three signed-Δ boxes")
	var reset = page._inspector.signed_rgb_reset_button()
	_assert_true(reset != null, "…and the No-tint reset")
	if boxes.size() != 3 or reset == null:
		return

	# Type a non-zero Δ first so the materialize-to-zero below is observable.
	boxes[0].value_changed.emit(-10.0)
	reset.pressed.emit()

	for i in range(3):
		_assert_eq(int(boxes[i].value), 0, "reset materializes Δ[%d] = 0 back into the row" % i)
	_assert_true(not page._inspector.pick_widgets().is_empty()
			and page._inspector.pick_widgets()[0].color.is_equal_approx(host.pick_return),
		"the picker (not the source) moves to the live achieved colour")


# --- fixtures -------------------------------------------------------------

## Build the projector sections for a Blend tween and inject `seed` into the Color cell (the
## page does this from the host's live top colour before handing sections to the inspector).
func _blend_sections_with_seed(kf, ctx: Dictionary, seed: Color) -> Array:
	var secs := Projector.sections(kf, ctx)
	for sec in secs:
		for f in sec.get("fields", []):
			if f.get("editor", "") == "target_color":
				f["seed"] = seed
	return secs


func _page():
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame   # let _ready build the UI + load the default effect
	page.bind_host(_FakeHost.new())
	return page


func _effect_dir(page, name: String) -> String:
	for d in page._effect_dirs:
		if String(d).ends_with(name):
			return d
	return ""


func _first_screen_span(page) -> String:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") == "screen" and not lane["spans"].is_empty():
			return lane["spans"][0]["id"]
	return ""


class _FakeHost extends RefCounted:
	const _Session = preload("res://src/effects/studio/EffectEditSession.gd")
	var pick_calls: int = 0
	var last_pick_refs: Dictionary = {}
	var last_pick_color: Color = Color.BLACK
	# The achieved colour the host would return AND the live top colour it seeds with (one
	# sentinel keeps the fake simple — both flow through the same picker in these seams).
	var pick_return: Color = Color(0.15, 0.35, 0.55)
	# Optional real choke point over the page's live data (seam 5 — the Δ-row byte writes).
	var _session = null

	func bind_data(ed) -> void:
		_session = _Session.new(ed)

	func studio_apply_edit(field_ref: Dictionary, new_raw, defer_refold = false) -> Dictionary:
		return _session.apply_edit(field_ref, new_raw) if _session != null else {}

	func reset() -> void:
		pick_calls = 0
		last_pick_refs = {}
		last_pick_color = Color.BLACK

	func studio_pick_target(field_refs: Dictionary, target: Color) -> Color:
		pick_calls += 1
		last_pick_refs = field_refs
		last_pick_color = target
		return pick_return

	func studio_screen_top_color() -> Color:
		return pick_return

	func studio_select_effect(_effect_id: int) -> void:
		pass

	func studio_seek(_frame: int) -> void:
		pass

	func studio_set_playing(_playing: bool) -> void:
		pass

	func studio_current_frame() -> int:
		return 0

	func studio_set_audibility(_audibility: Dictionary) -> void:
		pass


func _blend_kf_raw(r: int, g: int, b: int):
	var kf = ScreenData.Keyframe.new()
	kf.mode = ScreenData.ScreenMode.BLEND
	kf.blend_mode = 5
	kf.duration_frames = 8
	kf.start_r_raw = r; kf.start_g_raw = g; kf.start_b_raw = b
	kf.start_color = Color(r / 255.0, g / 255.0, b / 255.0)
	return kf


func _gradient_kf_raw(sr: int, sg: int, sb: int, er: int, eg: int, eb: int):
	var kf = ScreenData.Keyframe.new()
	kf.mode = ScreenData.ScreenMode.GRADIENT
	kf.duration_frames = 8
	kf.start_r_raw = sr; kf.start_g_raw = sg; kf.start_b_raw = sb
	kf.end_r_raw = er; kf.end_g_raw = eg; kf.end_b_raw = eb
	kf.start_color = Color(sr / 255.0, sg / 255.0, sb / 255.0)
	kf.end_color = Color(er / 255.0, eg / 255.0, eb / 255.0)
	return kf


func _field(section: Dictionary, name: String) -> Dictionary:
	for f in section.get("fields", []):
		if f.get("name", "") == name:
			return f
	return {}


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
