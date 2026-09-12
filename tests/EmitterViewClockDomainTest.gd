extends Node
## TDD guard for the clock-domain tag on emitter_view sections (ADR-0089 amendment:
## span-anchored playhead marker). Curves are read on THREE clocks and the surface never
## said which — the felt "hard to map the curve to the playhead" ambiguity. The projector
## must tag each section's clock so the inspector knows which sparklines carry the
## emitter-elapsed playhead marker:
##   • Emitter group + Particle · born-with → "emitter" (sampled at ActiveEmitter.elapsed_frames)
##   • Particle · over-life                 → "age"     (sampled per-particle at particle.age)
## Only the "emitter"-clocked sections get the span-anchored marker; the age-clocked
## over-life sparklines must opt OUT (they get their own mechanism later).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EmitterViewClockDomainTest.tscn

const EffectCurve = ExMateriaEffects.EffectCurve

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectEmitter = ExMateriaEffects.EffectEmitter
const EffectData = ExMateriaEffects.EffectData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_emitter_and_born_sections_are_emitter_clocked()
	_test_over_life_section_is_age_clocked()

	print("\n=== EmitterViewClockDomainTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EmitterViewClockDomainTest")
		get_tree().quit(1)
	else:
		print("[PASS] EmitterViewClockDomainTest")
		get_tree().quit(0)


## The two emitter-elapsed families carry clock == "emitter" — they sample by the
## firing's elapsed frame, so the span-anchored playhead marker maps single-valued.
func _test_emitter_and_born_sections_are_emitter_clocked() -> void:
	var view := Model.emitter_view(_effect(), 0)
	_assert_eq(_clock(view, "Emitter"), "emitter", "the Emitter section is emitter-clocked")
	_assert_eq(_clock(view, "Particle · born-with"), "emitter",
		"the born-with section is emitter-clocked")


## The over-life colour/homing family carries clock == "age" — it samples per-particle by
## age, so it opts OUT of the span-anchored marker (its own mechanism lands later).
func _test_over_life_section_is_age_clocked() -> void:
	var view := Model.emitter_view(_effect(), 0)
	_assert_eq(_clock(view, "Particle · over-life"), "age",
		"the over-life section is age-clocked (no emitter marker)")


# --- helpers --------------------------------------------------------------

func _clock(view: Array, title: String) -> String:
	for section in view:
		if section.get("title", "") == title:
			return str(section.get("clock", ""))
	return "<section missing>"


func _effect():
	var ed = EffectData.new()
	var em = EffectEmitter.new()
	em.curves = {"position": 0}
	em.color_curves = {"r": 0}
	ed.emitters.append(em)
	ed.curves.append(EffectCurve.from_array([0.0, 0.5, 1.0], 0))
	return ed


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
