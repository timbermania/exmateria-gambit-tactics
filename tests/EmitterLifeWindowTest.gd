extends Node
## TDD guard for the PARTICLE-LIFE WINDOW — the one derivation of how many game frames of
## an emitter's over-life curves the renderer can ever read.
##
## Worth its own guard because it is the AXIS of the colour editor. Since the ADR-0089
## colour-move amendment the editable colour track lives in the player column, beside a
## film strip tiled on the ANIMATION axis — and the two axes are not interchangeable:
## across all 401 corpus effects, of 2622 colour-enabled emitters they agree for 1412
## (53.9%), disagree for 1204 (45.9%), and 698 differ by more than 8 frames. Picking the
## wrong one does not nudge a keyframe, it relocates it.
##
## The split underneath that headline is what these tests pin: animation-driven emitters
## agree with the animation length BY CONSTRUCTION (they are defined as it), and
## authored-lifetime ones essentially never do.
##
## WHICH EMITTERS ARE IN WHICH CLASS was corrected on 2026-08-20, and these tests moved with
## it. The rule had been "is any of the four lifetime fields −1", which reads the END pair —
## and without a lifetime curve (3218 of 3227 corpus emitters) the spawner never samples the
## end pair at all. `EmitterLifeWindow.for_emitter` argues it in full with the primary
## source. Four assertions here changed sides; they were wrong, not the code.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/EmitterLifeWindowTest.tscn

const EffectCurve = ExMateriaEffects.EffectCurve
const ParticlePhysics = preload("res://addons/exmateria_effects/particles/ParticlePhysics.gd")

const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitterClass = ExMateriaEffects.EffectEmitter

var _passed: int = 0
var _failed: int = 0
var _completed: bool = false


func _ready() -> void:
	_test_an_authored_lifetime_is_the_max_of_the_start_pair()
	_test_the_max_not_the_min_is_the_bound()
	_test_without_a_lifetime_curve_the_end_pair_is_not_read()
	_test_with_a_lifetime_curve_the_end_pair_is_read()
	_test_a_lifetime_curve_index_that_resolves_to_nothing_is_no_curve()
	_test_animation_driven_falls_back_to_the_baked_display_length()
	_test_animation_driven_with_no_animation_keeps_minus_one()
	_test_a_negative_in_the_END_pair_does_not_mean_animation_driven()
	_test_a_negative_START_pair_is_animation_driven_however_real_the_end_pair_is()
	_test_the_kind_is_reported_not_inferred_from_the_note()
	_test_a_missing_emitter_answers_unresolved_rather_than_crashing()
	_test_no_lifetime_the_spawner_can_draw_escapes_the_window()
	_test_the_window_is_reachable_not_merely_an_upper_bound()

	_completed = true
	print("\n=== EmitterLifeWindowTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0 or not _completed:
		print("[FAIL] EmitterLifeWindowTest")
		get_tree().quit(1)
	else:
		print("[PASS] EmitterLifeWindowTest")
		get_tree().quit(0)


func _test_an_authored_lifetime_is_the_max_of_the_start_pair() -> void:
	var w: Dictionary = LifeWindow.for_emitter(_emitter([12, 20, 8, 16], 0), null)
	_assert_eq(int(w["n"]), 20, "an authored window is max(min_start, max_start)")
	_assert_eq(str(w["kind"]), "authored", "and it is the authored kind")


func _test_the_max_not_the_min_is_the_bound() -> void:
	# Lifetime is a RANDOM RANGE per particle, so the longest-lived particle is the one
	# that reads furthest into the curve. `min` would call live samples dead zone.
	var w: Dictionary = LifeWindow.for_emitter(_emitter([4, 40, 4, 4], 0), null)
	_assert_eq(int(w["n"]), 40, "the longest-lived particle sets the window, not the shortest")


## THE END PAIR IS INERT WITHOUT A LIFETIME CURVE, and this is the 2026-08-20 correction in
## one assertion. `ParticlePhysics.interpolate_range` opens with
## `if curve == null: return _srange(min_start, max_start)` — the last two fields are never
## sampled — and the ROM's `emitter_control_routine` (0x801A634C) branches identically on the
## packed curve nibble. The old rule took `max` over all four and drew up to 33 frames of
## phantom life on 309 corpus emitters (median 6, p90 12, max 32).
func _test_without_a_lifetime_curve_the_end_pair_is_not_read() -> void:
	var w: Dictionary = LifeWindow.for_emitter(_emitter([4, 8, 40, 40], 0), null)
	_assert_eq(int(w["n"]), 8, "no lifetime curve → a 40-frame END pair bounds nothing")


## …and WITH one it does: `min_val`/`max_val` are each a lerp from their start to their end,
## so over t ∈ [0,1] the largest reachable draw is the largest of the four corners. 9 of 3227
## corpus emitters are in this arm, and for them the old rule was right.
func _test_with_a_lifetime_curve_the_end_pair_is_read() -> void:
	var ed = _effect_with_animation([4, 3])
	ed.curves.clear()
	ed.curves.append(_flat_curve())
	var em = _emitter([4, 8, 40, 40], 0)
	em.curves = {"lifetime": 0}
	_assert_eq(int(LifeWindow.for_emitter(em, ed)["n"]), 40,
		"a lifetime curve ramps start→end, so the end pair bounds the window")
	_assert(LifeWindow.has_lifetime_curve(em, ed), "…and the curve is detected")


## An index that points nowhere is NOT a curve — `ActiveEmitter._get_curve` returns null for
## it, so `interpolate_range` takes the start pair. Mirrored exactly, because a looser test
## here quietly re-admits the end pair for every emitter with a stale index.
func _test_a_lifetime_curve_index_that_resolves_to_nothing_is_no_curve() -> void:
	var ed = _effect_with_animation([4, 3])
	ed.curves.clear()
	var em = _emitter([4, 8, 40, 40], 0)
	em.curves = {"lifetime": 3}
	_assert(not LifeWindow.has_lifetime_curve(em, ed), "an unpointed curve index is no curve")
	_assert_eq(int(LifeWindow.for_emitter(em, ed)["n"]), 8, "…so the end pair still bounds nothing")


func _test_animation_driven_falls_back_to_the_baked_display_length() -> void:
	# Two FRAME opcodes, durations 4 and 3 -> maxi(1,(4+1)>>1) + maxi(1,(3+1)>>1) = 2 + 2.
	var ed = _effect_with_animation([4, 3])
	var w: Dictionary = LifeWindow.for_emitter(_emitter([-1, -1, -1, -1], 0), ed)
	_assert_eq(int(w["n"]), 4, "Life = -1 means the window IS the baked display length")
	_assert_eq(str(w["kind"]), "animation_driven", "and it is the animation-driven kind")


func _test_animation_driven_with_no_animation_keeps_minus_one() -> void:
	# `anim_index` is a u8 with no referential guarantee and out-of-range values are in
	# the corpus. Inventing a length here would silently re-map every keyframe.
	var ed = _effect_with_animation([4, 3])
	var w: Dictionary = LifeWindow.for_emitter(_emitter([-1, -1, -1, -1], 7), ed)
	_assert_eq(int(w["n"]), -1, "an unpointed anim_index answers -1, it does not guess")


## THE −1 THAT MATTERS IS IN THE START PAIR. A sentinel in the end pair is inert data like
## every other end-pair value, so it cannot make an emitter animation-driven — the old rule's
## `min()` over all four said it could. 1348 of the 1361 corpus emitters with a mixed shape
## carry their −1 in the START pair, which is why the old rule mostly agreed anyway; this is
## the shape where it did not.
func _test_a_negative_in_the_END_pair_does_not_mean_animation_driven() -> void:
	var ed = _effect_with_animation([4, 3])
	var w: Dictionary = LifeWindow.for_emitter(_emitter([30, 30, -1, 30], 0), ed)
	_assert_eq(str(w["kind"]), "authored",
		"a -1 the spawner never reads cannot make the emitter animation-driven")
	_assert_eq(int(w["n"]), 30, "the start pair still bounds it at 30, not the animation's 4")


## …and the converse: the start pair at −1 IS animation-driven however real the end pair
## looks. This is E009 emitter 0's shape and the COMMON one — 1348 corpus emitters.
func _test_a_negative_START_pair_is_animation_driven_however_real_the_end_pair_is() -> void:
	var ed = _effect_with_animation([4, 3])
	var w: Dictionary = LifeWindow.for_emitter(_emitter([-1, -1, 16, 16], 0), ed)
	_assert_eq(str(w["kind"]), "animation_driven",
		"the START pair is the one read, so -1 there means animation-driven")
	_assert_eq(int(w["n"]), 4, "and the 16 beside it is inert, not an authored lifetime")


func _test_the_kind_is_reported_not_inferred_from_the_note() -> void:
	# The caller branches on the axis question; parsing prose to do it is how the two
	# surfaces would drift apart.
	var authored: Dictionary = LifeWindow.for_emitter(_emitter([16, 16, 16, 16], 0), null)
	_assert(authored.has("kind") and authored.has("n") and authored.has("note"),
		"every answer carries n + kind + note")


func _test_a_missing_emitter_answers_unresolved_rather_than_crashing() -> void:
	_assert_eq(int(LifeWindow.resolve(null, 0)["n"]), -1, "no effect data -> -1")
	var ed = _effect_with_animation([4, 3])
	_assert_eq(int(LifeWindow.resolve(ed, 99)["n"]), -1, "an out-of-range emitter -> -1")
	_assert_eq(str(LifeWindow.resolve(ed, 99)["kind"]), "unresolved", "and says so")


## THE PARITY TEST — and it is a DIFFERENT test than it was on 2026-08-19, for a reason
## worth stating. It used to compare this module against a hand transcription of the rule
## `EffectScoreModel` held inline. That copy is gone (the model calls this module now), so
## the transcription was guarding a duplicate of the thing under test against itself: it
## agreed with whatever this file said, including while this file was wrong for 360 corpus
## emitters. **A guard that agrees with both answers is not a guard.**
##
## What it compares against now is `ParticlePhysics.interpolate_range` — the actual function
## `ActiveEmitter._create_particle` draws the lifetime through. The window is a CLAIM about
## that function's range, so the honest test is to make it draw and check nothing escapes.
## Every colour-enabled emitter in every corpus effect on disk, sampled across the animation.
func _test_no_lifetime_the_spawner_can_draw_escapes_the_window() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260820
	var checked: int = 0
	var escaped: int = 0
	var worst: int = 0
	var worst_where: String = ""
	var dir := DirAccess.open("res://assets/effects")
	if dir == null:
		print("  [SKIP] renderer parity: no effects on disk (checked 0)")
		return
	var names: Array = []
	for n in dir.get_directories():
		names.append(n)
	names.sort()
	for name in names:
		var ed = _load_effect(name)
		if ed == null:
			continue
		for i in range(ed.emitters.size()):
			var em = ed.emitters[i]
			if em == null or not bool(em.flags.get("color_curve_enabled", false)):
				continue
			var w: Dictionary = LifeWindow.for_emitter(em, ed)
			if str(w["kind"]) != "authored":
				continue   # animation-driven: the bound is the animation, not a draw
			var n_win: int = int(w["n"])
			checked += 1
			var curve = ed.get_curve(int(em.curves.get("lifetime", -1))) \
				if em.curves is Dictionary else null
			# With a lifetime curve the drawn range MOVES with the frame, so sweep every
			# sample; without one `interpolate_range` ignores the frame entirely and one
			# is as good as 160 (this is what keeps a 1259-emitter sweep affordable).
			for f in (range(160) if curve != null else [0]):
				for _try in range(8):
					var draw: int = int(ParticlePhysics.interpolate_range(
						float(em.lifetime_min_start), float(em.lifetime_max_start),
						float(em.lifetime_min_end), float(em.lifetime_max_end),
						curve, f, rng))
					if draw > n_win:
						escaped += 1
						if draw - n_win > worst:
							worst = draw - n_win
							worst_where = "%s emitter %d (drew %d, window %d)" \
								% [name, i, draw, n_win]
	if checked == 0:
		print("  [SKIP] renderer parity: no authored colour emitters on disk")
		return
	print("  renderer parity: %d authored colour emitters swept" % checked)
	if escaped > 0:
		print("  worst: %s" % worst_where)
	_assert_eq(escaped, 0,
		"no lifetime the spawner can draw exceeds the window, over %d emitters" % checked)


## The other half of "the window is the upper bound": it must also be REACHABLE. A window
## the spawner can never draw up to is dead zone by another name, and the old rule's
## `max(all four)` produced exactly that — up to 32 phantom frames on 309 corpus emitters.
## Allowed to miss by one, because `_srange` is a float draw and `int()` truncates.
func _test_the_window_is_reachable_not_merely_an_upper_bound() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var checked: int = 0
	var unreachable: int = 0
	var dir := DirAccess.open("res://assets/effects")
	if dir == null:
		print("  [SKIP] reachability: no effects on disk")
		return
	var names: Array = []
	for n in dir.get_directories():
		names.append(n)
	names.sort()
	for name in names:
		var ed = _load_effect(name)
		if ed == null:
			continue
		for i in range(ed.emitters.size()):
			var em = ed.emitters[i]
			if em == null or not bool(em.flags.get("color_curve_enabled", false)):
				continue
			var w: Dictionary = LifeWindow.for_emitter(em, ed)
			if str(w["kind"]) != "authored":
				continue
			var n_win: int = int(w["n"])
			checked += 1
			var curve = ed.get_curve(int(em.curves.get("lifetime", -1))) \
				if em.curves is Dictionary else null
			var best: int = -99999
			for f in (range(160) if curve != null else [0]):
				for _try in range(40):
					best = maxi(best, int(ParticlePhysics.interpolate_range(
						float(em.lifetime_min_start), float(em.lifetime_max_start),
						float(em.lifetime_min_end), float(em.lifetime_max_end),
						curve, f, rng)))
			if best < n_win - 1:
				unreachable += 1
	if checked == 0:
		print("  [SKIP] reachability: no authored colour emitters on disk")
		return
	print("  reachability: %d authored colour emitters" % checked)
	_assert_eq(unreachable, 0,
		"every window is a lifetime the spawner actually draws, over %d emitters" % checked)


# --- fixtures ---

func _emitter(life: Array, anim_index: int):
	var em = EffectEmitterClass.new()
	em.lifetime_min_start = int(life[0])
	em.lifetime_max_start = int(life[1])
	em.lifetime_min_end = int(life[2])
	em.lifetime_max_end = int(life[3])
	em.anim_index = anim_index
	return em


func _effect_with_animation(durations: Array):
	var ed = EffectDataClass.new()
	var ops: Array = []
	for d in durations:
		ops.append({"type": "FRAME", "frameset": 0, "duration": int(d), "depth_mode": 0})
	ed.animations = [{"index": 0, "opcodes": ops}]
	return ed


## A curve `get_curve` will hand back — the CONTENT does not matter to the window rule,
## only that `_get_curve` resolves to something rather than null.
func _flat_curve() -> EffectCurve:
	var samples: Array = []
	for i in range(160):
		samples.append(float(i) / 159.0)
	return EffectCurve.from_array(samples, 0)


func _load_effect(name: String):
	var dir := "res://assets/effects/%s" % name
	if not DirAccess.dir_exists_absolute(dir):
		return null
	return EffectDataClass.load_from_directory(dir)


# --- harness ---

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)


func _assert_eq(a, b, msg: String) -> void:
	if a == b:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s (got %s, want %s)" % [msg, str(a), str(b)])
