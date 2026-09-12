extends Node
## Slice 5 — ACCEPTANCE (headful, real E312): the Colour ribbon the studio draws under
## emitter idx0's colour curves resolves to the SAME colour the particle renderer paints.
## The renderer paints in TWO steps — a per-particle modulate (_compute_color_modulate,
## the curve resolve) and the shader's `ALBEDO = col.rgb * COLOR.rgb`
## (effect_particle_opaque.gdshader), which muxes in the emitter's representative sprite
## colour. The ribbon mirrors BOTH (ColourRibbon.frame_colors takes `sprite_base`), so for
## every band f, ribbon.colors()[f] == modulate(particle age f) x ribbon.sprite_base() in
## RGB — proving the read-out and the render path share one resolve (EffectCurve.sample_rgb)
## and one mux, and can't drift. A screenshot is written for the eyeball check (the
## FedsPairStrip lesson: field dumps don't count).
##
## Skips when E312 assets are absent (gitignored/ROM-derived).
## Run: godot --path . --quit-after 400 res://tests/EffectStudioColourRibbonAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const ParticleClass = preload("res://addons/exmateria_effects/particles/Particle.gd")
const ColourRibbonClass = preload("res://src/effects/studio/ColourRibbon.gd")
const SHOT := "user://colour_ribbon_e312.png"

# Pin the count so a mid-test abort cannot report a clean [PASS] (the harness only counts
# assertions that RAN). It has to be BUMPED when an assertion is added: it was left at 12
# when `cbee913d7` took the ribbon vertical and added a 13th, so the suite has reported
# `[FAIL] ran 13 assertions, expected 12 — the test aborted early` on every run since, with
# 13 passed and 0 failed. A pin that cries wolf is worse than no pin — it is the guard that
# gets ignored right before it catches something.
const EXPECTED_ASSERTIONS := 13

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioColourRibbonAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0 or (_passed + _failed) != EXPECTED_ASSERTIONS:
		if (_passed + _failed) != EXPECTED_ASSERTIONS and _failed == 0:
			print("  [FAIL] ran %d assertions, expected %d — the test aborted early"
				% [_passed + _failed, EXPECTED_ASSERTIONS])
		print("[FAIL] EffectStudioColourRibbonAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioColourRibbonAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E312")):
		print("[SKIP] E312 assets not available — acceptance skipped")
		_passed = EXPECTED_ASSERTIONS
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

	var rend = scn._current_effect.sprite_renderer
	_assert_true(rend != null, "particle renderer present")

	page._set_root(Target.emitter(0))
	await _frames(30)

	# The colour surface is the PLAYER COLUMN's since the ADR-0089 colour-move amendment,
	# and since its 2026-08-20 vertical-column amendment the thing that DRAWS is
	# `ColourLifeColumn`, running down the side of the film strip. `_sequence_ribbon`
	# survives as a headless resolver — it still owns the sprite mux, the `Fit W` trim and
	# the `colors()` array every window assertion below reads — so it is asserted for what
	# it now is (bound and resolving) rather than for a picture it no longer paints.
	var ribbon = page._sequence_ribbon
	_assert_true(ribbon != null and not ribbon.visible,
		"the ribbon resolver is headless — the vertical column is what draws")
	_assert_true(page._sequence_life_column != null and page._sequence_life_column.visible,
		"emitter idx0 (colour ENABLED) shows a colour column beside the player")
	if ribbon == null:
		return
	_assert_true(ribbon.is_shown(), "the ribbon is shown")
	_assert_true(ribbon.has_frame_ruler(), "the ribbon carries a frame ruler")

	var cols: Array = ribbon.colors()
	_assert_true(cols.size() > 1, "the ribbon has bands (%d)" % cols.size())

	# The window is the particle's ACTUAL lifespan — E312 idx0 is animation-driven (Life=-1),
	# so it must be the animation's baked display length (12 frames), NOT 160. Validate against
	# BOTH the static resolver and the live animator's baked size (they can't drift), and
	# against a lone particle's measured age-at-death.
	var data = page._effect_data
	var em = data.get_emitter(0)
	var ai := int(em.anim_index)
	var static_len := int(data.get_animation_display_length(ai))
	_assert_true(cols.size() == static_len,
		"ribbon window (%d) == static animation display length (%d)" % [cols.size(), static_len])
	_assert_true(static_len == 12, "E312 idx0 animation is 12 baked frames (probed ground truth)")
	var death := _age_at_death(scn._current_effect.manager.animator, ai)
	_assert_true(static_len == death,
		"static length (%d) == a lone -1 particle's age-at-death (%d)" % [static_len, death])

	# The mux half of the paint path must actually BITE on E312 — a regression that dropped
	# sprite_base back to white would satisfy the parity loop below vacuously (white is the
	# identity), so pin that idx0's representative sprite colour is a real tint.
	var base: Color = ribbon.sprite_base()
	_assert_true(base != Color.WHITE,
		"E312 idx0's sprite base is a real tint, not white (%s) — the mux is load-bearing" % str(base))

	# Parity per band: the ribbon colour at frame f == the FULL paint the renderer applies at
	# that age — the per-particle modulate (the curve resolve) times the sprite base the
	# shader multiplies in. RGB only; the ribbon is opaque, the modulate carries the
	# semi_trans alpha.
	var mismatches := 0
	for f in range(cols.size()):
		var modulate: Color = rend._compute_color_modulate(_particle(0, f))
		var paint := Color(modulate.r * base.r, modulate.g * base.g, modulate.b * base.b, 1.0)
		if absf(cols[f].r - paint.r) > 0.004 or absf(cols[f].g - paint.g) > 0.004 \
				or absf(cols[f].b - paint.b) > 0.004:
			mismatches += 1
			if mismatches <= 3:
				print("  band %d ribbon=%s paint=%s (modulate=%s x base=%s)"
					% [f, str(cols[f]), str(paint), str(modulate), str(base)])
	_assert_true(mismatches == 0,
		"every band matches the renderer's painted colour (%d/%d mismatched)" % [mismatches, cols.size()])

	# Focused visual proof: the studio inspector lives under the F3 DebugOverlay (not the
	# captured main viewport), so render the SAME live ribbon into a SubViewport and grab
	# just the bar — a real pixel artifact of the resolved-colour bands.
	await _frames(5)
	var sv := SubViewport.new()
	sv.size = Vector2i(320, 24)
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var shot = ColourRibbonClass.new()
	shot.set_curves(data.get_curve(int(em.color_curves.get("r", -1))),
		data.get_curve(int(em.color_curves.get("g", -1))),
		data.get_curve(int(em.color_curves.get("b", -1))), true, cols.size(), true, base)
	shot.custom_minimum_size = Vector2(320, 24)
	shot.size = Vector2(320, 24)
	sv.add_child(shot)
	await _frames(3)
	var err := sv.get_texture().get_image().save_png(SHOT)
	_assert_true(err == OK, "ribbon screenshot written to %s" % ProjectSettings.globalize_path(SHOT))
	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT))


## Tick a lone animation-driven (-1) particle through the live animator until it signals
## complete — its age at death is the ground-truth lifespan the window must match.
func _age_at_death(animator, anim_index: int) -> int:
	var p = ParticleClass.new()
	p.anim_index = anim_index
	p.anim_time = 0
	p.lifetime = -1
	p.age = 0
	p.animation_complete = false
	p.active = true
	var guard := 0
	while not p.is_dead() and guard < 2000:
		animator.tick(p)
		p.age += 1
		guard += 1
	return p.age


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
