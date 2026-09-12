extends Node
## TDD guard for the EMITTER SEQUENCE SUBJECT — the pure derivation that answers
## "which sequence, through which lens, does THIS target's emitter play?".
##
## It is what lets the inspector row's one right-hand column (ADR-0100 dec. 1) open on
## an `emitter` or a particle `span` target as well as on an `animation` one. Those two
## kinds address an emitter, and an emitter carries `anim_index` (the sequence) and
## `anim_param` (the frameset-group LENS its FRAME opcodes resolve against) — so the
## player's subject is derivable without the author navigating anywhere.
##
## Pure by construction, and that is the point: the thing worth guarding is the ADDRESS
## the player is bound to, not the picture. A wrong address draws a real sequence with
## real sprites and looks entirely plausible — the emitter-index-read-as-an-animation-index
## confusion this exists to make unrepresentable is invisible on screen.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/EffectStudioEmitterSequenceSubjectTest.tscn

const EffectData = ExMateriaEffects.EffectData
const EffectEmitter = ExMateriaEffects.EffectEmitter

const Subject = preload("res://src/effects/studio/EmitterSequenceSubject.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_an_emitter_target_names_its_own_sequence()
	_test_the_lens_is_the_emitters_anim_param_never_zero()
	_test_a_particle_span_names_the_emitter_it_fires()
	_test_a_disabled_span_still_names_its_remembered_emitter()
	_test_a_sound_span_names_nothing()
	_test_a_span_with_no_emitter_names_nothing()
	_test_an_animation_target_is_not_this_functions_business()
	_test_an_unpointed_anim_index_names_nothing()
	_test_a_missing_effect_or_score_names_nothing_rather_than_crashing()

	print("\n=== EffectStudioEmitterSequenceSubjectTest: %d passed, %d failed ==="
		% [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioEmitterSequenceSubjectTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioEmitterSequenceSubjectTest")
		get_tree().quit(0)


func _test_an_emitter_target_names_its_own_sequence() -> void:
	var ed := _effect([{"anim": 1, "group": 0}])
	var s: Dictionary = Subject.resolve(Target.emitter(0), ed, _score())
	_assert_eq(int(s.get("anim_index", -1)), 1, "the emitter's anim_index IS the subject")
	_assert_eq(int(s.get("emitter_index", -1)), 0, "and it names the emitter it came from")


func _test_the_lens_is_the_emitters_anim_param_never_zero() -> void:
	# The group is not decoration: `opcode.frameset + frameset_group_offset(group)` means
	# the SAME opcode reaches a different sprite per group (18 of 401 corpus effects have
	# more than one). Defaulting it to 0 would draw the wrong sprite, convincingly.
	var ed := _effect([{"anim": 0, "group": 1}])
	_assert_eq(int(Subject.resolve(Target.emitter(0), ed, _score()).get("group", -1)), 1,
		"the lens is the emitter's anim_param")


func _test_a_particle_span_names_the_emitter_it_fires() -> void:
	# THE PRIMARY CASE. "Click on an emitter event" is a click on a particle SPAN, and a
	# span's ref is a `span_id` — the emitter is only reachable through the score.
	var ed := _effect([{"anim": 0, "group": 0}, {"anim": 1, "group": 1}])
	var s: Dictionary = Subject.resolve(Target.span("particle:phase1:0#2"), ed, _score())
	_assert_eq(int(s.get("emitter_index", -1)), 1, "the span's emitter_index is followed")
	_assert_eq(int(s.get("anim_index", -1)), 1, "through to THAT emitter's sequence")
	_assert_eq(int(s.get("group", -1)), 1, "and THAT emitter's lens")


func _test_a_disabled_span_still_names_its_remembered_emitter() -> void:
	# A disabled span carries `emitter_id == 0` but a session-remembered identity, and the
	# score already resolves that into `emitter_index` (ADR-0089 particle_timeline). Seeing
	# what the event WOULD spawn is the reason to look at a disabled one at all.
	var ed := _effect([{"anim": 0, "group": 0}, {"anim": 1, "group": 1}])
	var s: Dictionary = Subject.resolve(Target.span("particle:phase1:0#9"), ed, _score())
	_assert_eq(int(s.get("emitter_index", -1)), 0, "a disabled span resolves like a live one")


func _test_a_sound_span_names_nothing() -> void:
	# Only a particle span carries `emitter_index`; a sound/camera/screen span has no
	# emitter and must claim no column, exactly as it does today.
	_assert_true(Subject.resolve(Target.span("sound:sfx#0"),
		_effect([{"anim": 0, "group": 0}]), _score()).is_empty(),
		"a sound span has no emitter, so no sequence")


func _test_a_span_with_no_emitter_names_nothing() -> void:
	_assert_true(Subject.resolve(Target.span("particle:phase1:0#7"),
		_effect([{"anim": 0, "group": 0}]), _score()).is_empty(),
		"a span whose emitter_index is -1 names nothing")
	_assert_true(Subject.resolve(Target.span("particle:nope#0"),
		_effect([{"anim": 0, "group": 0}]), _score()).is_empty(),
		"and a span_id in no lane names nothing rather than throwing")


func _test_an_animation_target_is_not_this_functions_business() -> void:
	# The animation path is the EXISTING one and reads its address off the ref. Answering
	# here too would give the column two sources of truth for the same screen.
	_assert_true(Subject.resolve(Target.animation(1, 0),
		_effect([{"anim": 1, "group": 0}]), _score()).is_empty(),
		"an animation target already knows its own sequence")
	for t in [Target.texture(), Target.effect_settings(), Target.frameset(0),
			Target.frame(0, 0), Target.container(0), Target.pair(0)]:
		_assert_true(Subject.resolve(t, _effect([{"anim": 0, "group": 0}]), _score()).is_empty(),
			"`%s` claims no column" % Target.kind(t))


func _test_an_unpointed_anim_index_names_nothing() -> void:
	# anim_index is a u8 with no referential guarantee (EffectKeyframeInspector says so at
	# :1391). Out of range must be "no column", not a decode of animations[200].
	var ed := _effect([{"anim": 200, "group": 0}])
	_assert_true(Subject.resolve(Target.emitter(0), ed, _score()).is_empty(),
		"an anim_index past the animations array names nothing")
	_assert_true(Subject.resolve(Target.emitter(9), ed, _score()).is_empty(),
		"and so does an emitter index past the emitters array")


func _test_a_missing_effect_or_score_names_nothing_rather_than_crashing() -> void:
	_assert_true(Subject.resolve(Target.emitter(0), null, _score()).is_empty(),
		"no effect loaded, no subject")
	_assert_true(Subject.resolve(Target.span("particle:phase1:0#2"),
		_effect([{"anim": 0, "group": 0}]), {}).is_empty(),
		"an empty score is walked, not indexed")
	_assert_true(Subject.resolve({}, _effect([{"anim": 0, "group": 0}]), _score()).is_empty(),
		"and an empty target names nothing")


# --- fixtures ---------------------------------------------------------------

## A score whose particle lane holds three spans: one firing emitter 1, one DISABLED but
## remembering emitter 0 (the score has already resolved that to an index), and one with
## no emitter at all. Plus a sound lane, whose spans carry no `emitter_index` key.
func _score() -> Dictionary:
	return {"lanes": [
		{"kind": "particle", "spans": [
			{"id": "particle:phase1:0#2", "emitter_index": 1, "emitter_id": 2},
			{"id": "particle:phase1:0#9", "emitter_index": 0, "emitter_id": 1},
			{"id": "particle:phase1:0#7", "emitter_index": -1, "emitter_id": 0},
		]},
		{"kind": "sound", "spans": [{"id": "sound:sfx#0"}]},
	]}


func _effect(specs: Array) -> EffectData:
	var ed := EffectData.new()
	ed.animations = [_anim(), _anim()]
	for i in range(specs.size()):
		var s: Dictionary = specs[i]
		var em := EffectEmitter.new()
		em.index = i
		em.anim_index = int(s.get("anim", 0))
		em.anim_param = int(s.get("group", 0))
		ed.emitters.append(em)
	return ed


func _anim() -> Dictionary:
	return {"index": 0, "opcodes": [{"type": "FRAME", "frameset": 0, "duration": 2}]}


# --- harness ----------------------------------------------------------------

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
