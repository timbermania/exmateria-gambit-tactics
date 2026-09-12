extends Node
## Wiring ACCEPTANCE (headful, real E312): a colour-curve edit made through the Effect
## Studio choke point (page._apply_edit -> host studio_apply_edit) must take effect in the
## LIVE particle renderer, not just the model. Guards the E312 emitter-idx0 report where
## toggling colour on/off and reassigning curves did nothing because the renderer's
## per-emitter colour-curve cache was built once at initialize() and never rebuilt.
##
## Asserts on the renderer's _compute_color_modulate (the exact function that feeds the
## per-particle colour): colour ON reads the curves; toggling OFF via the host goes white;
## reassigning a curve index changes what the modulate samples.
##
## Skips when E312 assets are absent (they are gitignored/ROM-derived).
## Run: godot --path . --quit-after 400 res://tests/EffectStudioColorCurveLiveEditTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const EmitterChannel = preload("res://src/effects/studio/EmitterChannel.gd")
const ParticleClass = preload("res://addons/exmateria_effects/particles/Particle.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioColorCurveLiveEditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioColorCurveLiveEditTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioColorCurveLiveEditTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E312")):
		print("[SKIP] E312 assets not available — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E312"):
			dir = d
	_assert_true(dir != "", "E312 in the effect catalogue")
	page._load_effect(dir)
	await _frames(40)

	var data = page._effect_data
	var em = data.get_emitter(0)
	_assert_true(em != null, "E312 emitter 0 present")
	_assert_true(int(EmitterChannel.read_raw(em, "color_curve_enable")) == 1,
		"E312 idx0 colour curves are ENABLED at load (the report's premise 'flags 0x00 = off' "
		+ "referred to the KEYFRAME flags, not emitter_flags_lo)")

	var rend = scn._current_effect.sprite_renderer
	_assert_true(rend != null, "particle renderer present")

	page._set_root(Target.emitter(0))
	await _frames(10)

	# Baseline: colour ON -> modulate is not white (the curves are assigned + non-flat).
	var base = rend._compute_color_modulate(_particle(0, 15))
	_assert_true(not _is_white(base), "colour ON: modulate reads the curves (not white)")

	# Toggle OFF through the host choke point -> modulate must go white.
	page._apply_edit({"channel": "emitter", "emitter_index": 0, "field": "color_curve_enable"}, 0)
	await _frames(20)
	var off = rend._compute_color_modulate(_particle(0, 15))
	_assert_true(_is_white(off), "toggle OFF via host: modulate goes white (renderer cache refreshed)")

	# Toggle back ON -> coloured again.
	page._apply_edit({"channel": "emitter", "emitter_index": 0, "field": "color_curve_enable"}, 1)
	await _frames(20)
	var on = rend._compute_color_modulate(_particle(0, 15))
	_assert_true(not _is_white(on), "toggle back ON via host: modulate coloured again")

	# Reassign the G curve to a different index -> the renderer must cache the NEW curve object
	# (identity check is deterministic; sampled values could coincide across curves).
	var new_g := 0 if int(em.color_curves.get("g", 0)) != 0 else 3
	page._apply_edit({"channel": "emitter", "emitter_index": 0, "field": "color_curve_g"}, new_g)
	await _frames(20)
	_assert_true(rend._emitter_color_curve_g[0] == data.get_curve(new_g),
		"reassign G curve via host: renderer caches the reassigned curve object (idx %d)" % new_g)


func _is_white(c: Color) -> bool:
	return c.r == 1.0 and c.g == 1.0 and c.b == 1.0


func _particle(emitter_index: int, age: int):
	var p = ParticleClass.new()
	p.emitter_index = emitter_index
	p.age = age
	return p


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
