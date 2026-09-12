extends Node
## TDD guard for ScreenTweenProjector (ADR-0071) — the screen tween's inspector
## projection is a function of its KIND (Blend vs Gradient), with LIVE-FIELDS-ONLY:
## Blend exposes {Color, Blend mode, Duration}; Gradient exposes {Top color, Bottom
## color, Duration}. The fields a kind doesn't use are ABSENT (not greyed) — the
## discrimination lives in the model. Pure, no scene. See CONTEXT "Blend / Gradient".
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ScreenTweenProjectorTest.tscn

const ScreenData = ExMateriaEffects.ScreenData

const Projector = preload("res://src/effects/studio/ScreenTweenProjector.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_blend_projects_its_live_fields_only()
	_test_gradient_projects_its_live_fields_only()
	_test_summarize_distinguishes_the_kinds_in_the_lane()
	_test_both_kinds_expose_an_editable_kind_selector()
	_test_gradient_stops_are_editable_color_cells()
	_test_blend_mode_row_shows_the_shared_human_label()
	_test_duration_row_is_an_editable_int_on_both_kinds()
	_test_blend_has_a_signed_delta_row_gradient_does_not()
	_test_both_kinds_expose_an_enabled_toggle()
	_test_identity_noop_seeds_the_toggle_disabled()

	print("\n=== ScreenTweenProjectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScreenTweenProjectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScreenTweenProjectorTest")
		get_tree().quit(0)


## A Blend tween projects one "Blend" section carrying the shared RGB, the blend
## mode, and the duration — and NOT the Gradient-only top/bottom stops.
func _test_blend_projects_its_live_fields_only() -> void:
	var secs := Projector.sections(_blend_kf())
	_assert_eq(secs.size(), 1, "screen tween projects one section")
	_assert_eq(secs[0].get("title", ""), "Blend", "Blend kind titles its section")
	var names := _field_names(secs[0])
	_assert_true("Blend mode" in names, "Blend exposes its blend mode")
	_assert_true("Duration" in names, "Blend exposes its duration")
	_assert_true(_has_any(names, ["Color", "RGB"]), "Blend exposes its shared color")
	_assert_true(not _has_any(names, ["Top color", "Bottom color"]),
		"Blend does NOT leak the Gradient-only stops")


## A Gradient tween projects one "Gradient" section carrying the explicit top and
## bottom stops and the duration — and NOT the Blend-only blend mode.
func _test_gradient_projects_its_live_fields_only() -> void:
	var secs := Projector.sections(_gradient_kf())
	_assert_eq(secs.size(), 1, "screen tween projects one section")
	_assert_eq(secs[0].get("title", ""), "Gradient", "Gradient kind titles its section")
	var names := _field_names(secs[0])
	_assert_true("Top color" in names, "Gradient exposes its top stop")
	_assert_true("Bottom color" in names, "Gradient exposes its bottom stop")
	_assert_true("Duration" in names, "Gradient exposes its duration")
	_assert_true(not ("Blend mode" in names), "Gradient does NOT leak the Blend-only blend mode")


## In the lane, Blend and Gradient are told apart by LABEL + BORDER style, while the
## fill stays the color the tween produces (its top/shared stop). This is what finally
## makes a Gradient tween distinguishable from a Blend on the screen lane (ADR-0071).
func _test_summarize_distinguishes_the_kinds_in_the_lane() -> void:
	var blend := Projector.summarize(_blend_kf())
	var grad := Projector.summarize(_gradient_kf())

	_assert_eq(blend.get("label", ""), "Blend", "Blend labels its span")
	_assert_eq(grad.get("label", ""), "Grad", "Gradient labels its span distinctly")
	_assert_true(blend.get("border", "") != grad.get("border", ""),
		"the two kinds carry different border styles")
	_assert_eq(blend.get("color", Color.BLACK), _blend_kf().start_color,
		"fill stays the color the Blend tween produces")
	_assert_eq(grad.get("color", Color.BLACK), _gradient_kf().start_color,
		"fill stays the color the Gradient tween produces (its top stop)")


## Both kinds expose an editable "Kind" selector (a choice editor) so the author can flip
## the screen tween's variant in place; the fields below reshape accordingly. Choices are
## index-aligned with ScreenMode (0=Gradient, 1=Blend), seeded to the tween's current kind.
func _test_both_kinds_expose_an_editable_kind_selector() -> void:
	var ctx := {"context": "for_each", "event_index": 0}

	var b = Projector.sections(_blend_kf(), ctx)[0]
	var kb := _field(b, "Kind")
	_assert_eq(kb.get("shape", ""), "edit", "the Blend section's Kind cell is editable")
	_assert_eq(kb.get("editor", ""), "choice", "Kind is a choice editor")
	_assert_eq(int(kb.get("value", -1)), ScreenData.ScreenMode.BLEND, "Kind seeds to the current kind (Blend)")
	_assert_true(kb.get("choices", []) == ["Gradient", "Blend"],
		"choices index-align with ScreenMode (0=Gradient, 1=Blend)")
	_assert_true(kb.get("field_ref", {}) == {"channel": "screen", "context": "for_each", "event_index": 0, "field": "kind"},
		"the Kind field_ref addresses the kind on this screen tween")

	var g = Projector.sections(_gradient_kf(), ctx)[0]
	var kg := _field(g, "Kind")
	_assert_eq(kg.get("editor", ""), "choice", "the Gradient section also exposes the Kind selector")
	_assert_eq(int(kg.get("value", -1)), ScreenData.ScreenMode.GRADIENT, "Kind seeds to Gradient there")


## The two Gradient stops are EDITABLE plain-colour cells (#255 scope B): a `gradient_color`
## editor (no signed Blend solver — the stops are unsigned absolute colours). Each carries
## per-component write-side field_refs — Top → start_r/g/b, Bottom → end_r/g/b — so an author
## edit lowers through the #255 choke point, plus a `seed` colour (the stop's current value,
## known directly from the keyframe since Gradient is an absolute set) so the picker opens on it.
func _test_gradient_stops_are_editable_color_cells() -> void:
	var ctx := {"context": "for_each", "event_index": 0}
	var g = Projector.sections(_gradient_kf(), ctx)[0]

	var top := _field(g, "Top color")
	_assert_eq(top.get("shape", ""), "edit", "the Top stop cell is editable")
	_assert_eq(top.get("editor", ""), "gradient_color", "the Top stop is a plain gradient_color editor (no signed solver)")
	_assert_eq(top.get("seed", Color.BLACK), _gradient_kf().start_color, "the Top stop seeds to start_color")
	var tr: Dictionary = top.get("field_refs", {})
	_assert_true(tr.get("r", {}) == {"channel": "screen", "context": "for_each", "event_index": 0, "field": "start_r"},
		"Top.r field_ref addresses start_r")
	_assert_true(tr.get("g", {}).get("field", "") == "start_g" and tr.get("b", {}).get("field", "") == "start_b",
		"Top.g/b field_refs address start_g/start_b")

	var bot := _field(g, "Bottom color")
	_assert_eq(bot.get("shape", ""), "edit", "the Bottom stop cell is editable")
	_assert_eq(bot.get("editor", ""), "gradient_color", "the Bottom stop is a plain gradient_color editor")
	_assert_eq(bot.get("seed", Color.BLACK), _gradient_kf().end_color, "the Bottom stop seeds to end_color")
	var br: Dictionary = bot.get("field_refs", {})
	_assert_true(br.get("r", {}).get("field", "") == "end_r"
			and br.get("g", {}).get("field", "") == "end_g"
			and br.get("b", {}).get("field", "") == "end_b",
		"Bottom.r/g/b field_refs address end_r/end_g/end_b")


## The Blend-mode row GRADUATES to an editable 11-choice enum (ADR-0087 dec. 13) —
## palette's exact selector: value-carrying choices {value, label} from the one shared
## ColorModeLabels map, seeded to the keyframe's mode, addressing the screen blend_mode
## field (the picker already re-solves against the current mode).
func _test_blend_mode_row_shows_the_shared_human_label() -> void:
	const Labels = preload("res://src/effects/studio/ColorModeLabels.gd")
	var b = Projector.sections(_blend_kf(), {"context": "for_each", "event_index": 0})[0]
	var row := _field(b, "Blend mode")
	_assert_eq(row.get("shape", ""), "edit", "the Blend-mode row is editable")
	_assert_eq(row.get("editor", ""), "enum", "…a value-carrying enum")
	_assert_eq(int(row.get("value", -1)), 5, "seeded to the keyframe's current mode")
	var choices: Array = row.get("choices", [])
	_assert_eq(choices.size(), Labels.COUNT, "all 11 modes offered")
	for code in range(Labels.COUNT):
		_assert_eq(int(choices[code].get("value", -1)), code, "choice %d carries its code" % code)
		_assert_eq(str(choices[code].get("label", "")), Labels.label(code),
			"choice %d shows the shared human label" % code)
	_assert_true(row.get("field_ref", {}) == {"channel": "screen", "context": "for_each",
		"event_index": 0, "field": "blend_mode"},
		"the enum addresses the screen blend_mode field")


## The Duration row is EDITABLE on both kinds (ADR-0087 dec. 9) — an `int` cell whose
## typed value IS the boundary edit (the `duration` pseudo-field the channel routes to the
## sum-preserving trade). Seeded to the keyframe's duration, min 1 (never a zero-width span).
func _test_duration_row_is_an_editable_int_on_both_kinds() -> void:
	var ctx := {"context": "for_each", "event_index": 0}
	for kf in [_blend_kf(), _gradient_kf()]:
		var sec = Projector.sections(kf, ctx)[0]
		var kind: String = sec.get("title", "")
		var d := _field(sec, "Duration")
		_assert_eq(d.get("shape", ""), "edit", "%s Duration is editable" % kind)
		_assert_eq(d.get("editor", ""), "int", "%s Duration is an int cell" % kind)
		_assert_eq(int(d.get("value", -1)), int(kf.duration_frames),
			"%s Duration seeds to the keyframe's duration" % kind)
		_assert_eq(int(d.get("min", -1)), 1, "%s Duration floors at 1 frame" % kind)
		_assert_true(d.get("field_ref", {}) == {"channel": "screen", "context": "for_each",
			"event_index": 0, "field": "duration"},
			"%s Duration addresses the duration pseudo-field" % kind)


## Screen Blend gains palette's precise signed-Δ row (ADR-0087 dec. 12) — a `signed_rgb`
## editor over the SAME start_r/g/b bytes the picker back-solves, with the engine's doubling
## told in the label: the row shows the STORED byte, the fold applies it ×2. Gradient stops
## are absolute, so a Δ row is meaningless there — a mode-shaped absence, like palette's
## restores.
func _test_blend_has_a_signed_delta_row_gradient_does_not() -> void:
	var ctx := {"context": "for_each", "event_index": 0}
	var kf = _blend_kf()
	var d := _field(Projector.sections(kf, ctx)[0], "Tint Δ (applied ×2)")
	_assert_eq(d.get("shape", ""), "edit", "the Blend Δ cell is editable")
	_assert_eq(d.get("editor", ""), "signed_rgb", "…a signed_rgb editor (raw byte, signed view)")
	_assert_eq(d.get("seed", Vector3i.ZERO), Vector3i(26, 31, 36),
		"seeded with the raw stored bytes (widget shows signed)")
	var refs: Dictionary = d.get("field_refs", {})
	_assert_true(refs.get("r", {}) == {"channel": "screen", "context": "for_each",
		"event_index": 0, "field": "start_r"}, "Δ.r addresses start_r — the same byte the picker solves")
	_assert_true(refs.get("g", {}).get("field", "") == "start_g"
			and refs.get("b", {}).get("field", "") == "start_b",
		"Δ.g/b address start_g/start_b")

	for f in Projector.sections(_gradient_kf(), ctx)[0].get("fields", []):
		_assert_true(not String(f.get("name", "")).begins_with("Tint Δ"),
			"Gradient carries no Δ row (absolute stops — a mode-shaped absence)")


## The harmonized Enabled toggle (ADR-0087 dec. 11) on BOTH kinds — the same
## Disabled/Enabled choice palette shows, addressing the screen `enabled` pseudo-field
## (a byte-swap + stash on the channel, not a bit). Seeded from the DERIVED state.
func _test_both_kinds_expose_an_enabled_toggle() -> void:
	var ctx := {"context": "for_each", "event_index": 0}
	for kf in [_blend_kf(), _gradient_kf()]:
		var sec = Projector.sections(kf, ctx)[0]
		var kind: String = sec.get("title", "")
		var en := _field(sec, "Enabled")
		_assert_eq(en.get("shape", ""), "edit", "%s exposes an editable Enabled control" % kind)
		_assert_eq(en.get("editor", ""), "choice", "%s Enabled is a choice toggle" % kind)
		_assert_eq(int(en.get("value", -1)), 1, "%s (non-identity bytes) seeds ENABLED" % kind)
		_assert_true(en.get("choices", []) == ["Disabled", "Enabled"],
			"%s choices are Disabled/Enabled — palette's exact row" % kind)
		_assert_true(en.get("field_ref", {}) == {"channel": "screen", "context": "for_each",
			"event_index": 0, "field": "enabled"},
			"%s Enabled addresses the screen enabled pseudo-field" % kind)


## An identity no-op Blend (the insert-seed / disabled bytes) seeds the toggle DISABLED —
## the state is DERIVED from the bytes, so a cold no-op reads Disabled with no stash needed.
func _test_identity_noop_seeds_the_toggle_disabled() -> void:
	var kf = ScreenData.Keyframe.new()
	kf.mode = ScreenData.ScreenMode.BLEND
	kf.blend_mode = 0
	kf.ctrl = 0x80
	kf.duration_frames = 8
	var en := _field(Projector.sections(kf, {"context": "for_each", "event_index": 0})[0], "Enabled")
	_assert_eq(int(en.get("value", -1)), 0, "identity no-op bytes derive DISABLED")


# --- fixtures -------------------------------------------------------------

func _field(section: Dictionary, name: String) -> Dictionary:
	for f in section.get("fields", []):
		if f.get("name", "") == name:
			return f
	return {}


func _blend_kf():
	var kf = ScreenData.Keyframe.new()
	kf.mode = ScreenData.ScreenMode.BLEND
	kf.blend_mode = 5
	kf.duration_frames = 8
	kf.start_r_raw = 26; kf.start_g_raw = 31; kf.start_b_raw = 36
	kf.start_color = Color(26 / 255.0, 31 / 255.0, 36 / 255.0)
	return kf


func _gradient_kf():
	var kf = ScreenData.Keyframe.new()
	kf.mode = ScreenData.ScreenMode.GRADIENT
	kf.duration_frames = 12
	kf.start_color = Color(0.1, 0.2, 0.3)   # top stop
	kf.end_color = Color(0.4, 0.5, 0.6)     # bottom stop
	return kf


func _field_names(section: Dictionary) -> Array:
	var names: Array = []
	for f in section.get("fields", []):
		names.append(f.get("name", ""))
	return names


func _has_any(names: Array, candidates: Array) -> bool:
	for c in candidates:
		if c in names:
			return true
	return false


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
