extends Node
## Slice A — EffectData.get_animation_display_length(anim_index): the BAKED play length in
## game frames, i.e. the actual lifespan of an animation-driven (Life=-1) particle and the
## honest window for its over-life colour curves. It must MIRROR ParticleAnimator's baking
## (each FRAME opcode → maxi(1, duration >> 1) game frames; duration=0 terminal = 1 frame;
## LOOP is a no-op marker, not a stop) so the authoring view can't drift from the sim. This
## guards resolver ≡ live animator baked size, asset-free.
##
## Run: godot --path . --quit-after 6 res://tests/EffectAnimationDisplayLengthTest.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const ParticleAnimatorClass = preload("res://addons/exmateria_effects/particles/ParticleAnimator.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_mirrors_baking_and_known_lengths()
	_test_unresolvable_returns_minus_one()

	print("\n=== EffectAnimationDisplayLengthTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectAnimationDisplayLengthTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectAnimationDisplayLengthTest")
		get_tree().quit(0)


func _test_mirrors_baking_and_known_lengths() -> void:
	var ed = EffectDataClass.new()
	# anim0: 20→10, 2→1, 0(terminal)→1  = 12  (the E312 idx0 shape)
	# anim1: 1→maxi(1,0)=1, 1→1          = 2   (the sub-2 duration floor)
	# anim2: 6→3, LOOP(no-op), 4→2        = 5   (baking does NOT stop at LOOP)
	ed.animations = [
		{"opcodes": [_frame(20), _frame(2), _frame(0)]},
		{"opcodes": [_frame(1), _frame(1)]},
		{"opcodes": [_frame(6), {"type": "LOOP"}, _frame(4)]},
	]
	var expected := [12, 2, 5]

	var animator = ParticleAnimatorClass.new()
	animator.initialize(ed)

	for i in range(3):
		var got: int = ed.get_animation_display_length(i)
		_assert_eq(got, expected[i], "anim %d display length" % i)
		_assert_eq(got, int(animator.get_animation_duration(i)),
			"anim %d ≡ live animator baked size" % i)


## An out-of-range or opcode-less animation can't be resolved → -1 (the caller falls back
## to the whole curve rather than inventing a length).
func _test_unresolvable_returns_minus_one() -> void:
	var ed = EffectDataClass.new()
	ed.animations = [{"opcodes": [{"type": "LOOP"}]}]  # no FRAME opcodes
	_assert_eq(ed.get_animation_display_length(0), -1, "no FRAME opcodes → -1")
	_assert_eq(ed.get_animation_display_length(5), -1, "out-of-range index → -1")
	_assert_eq(ed.get_animation_display_length(-1), -1, "negative index → -1")


func _frame(duration: int) -> Dictionary:
	return {"type": "FRAME", "duration": duration, "frameset": 0, "depth_mode": 0}


func _assert_eq(got: int, expected: int, label: String) -> void:
	if got == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %d, expected %d)" % [label, got, expected])
