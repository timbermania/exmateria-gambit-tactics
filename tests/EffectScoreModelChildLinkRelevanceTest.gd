extends Node
## Guard for the child-emitter LINK rows carrying their field-relevance verdict (ADR-0089
## amendment bugfix). The oracle deads `child_emitter_on_death` / `child_emitter_mid_life` when
## the matching spawn mode is disabled, and the editable "Spawn on death" row (a real field_ref)
## already receives it. But the ADR-0073 navigation LINK rows ("Child on death" / "Child mid-life")
## carry a `target`, not a `field_ref.field`, so _attach_relevance could not match them — the
## Dead verdict was dropped and the link rendered Live (shown even under Hide inert). This pins
## that the link rows now inherit the same verdict via an explicit relevance key.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectScoreModelChildLinkRelevanceTest.tscn

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitter = ExMateriaEffects.EffectEmitter
const TimelineDataClass = ExMateriaEffects.TimelineData
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_disabled_child_mode_deads_the_link_row()
	_test_enabled_child_mode_keeps_the_link_live()

	print("\n=== EffectScoreModelChildLinkRelevanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectScoreModelChildLinkRelevanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectScoreModelChildLinkRelevanceTest")
		get_tree().quit(0)


## Both child modes disabled (flags_lo 0x00) but both children present (index 0): the oracle
## deads them, so BOTH the editable "Spawn on death" row AND the "Child on death" navigation
## link must read Dead — mirroring what the user sees on E317 emitter 6.
func _test_disabled_child_mode_deads_the_link_row() -> void:
	var rows := _config_rows(_emitter(0x00, 0, 0))
	_assert_state(rows, "Spawn on death", "dead", "editable spawn-index row is Dead (baseline)")
	_assert_state(rows, "Child on death", "dead", "the on-death navigation LINK inherits the Dead verdict")
	_assert_state(rows, "Child mid-life", "dead", "the mid-life navigation LINK inherits the Dead verdict")


## Death mode enabled (flags_lo bit 0 set): the on-death child is Live, so its link stays Live
## (not hidden) — guards that we don't over-hide an active spawn edge.
func _test_enabled_child_mode_keeps_the_link_live() -> void:
	var rows := _config_rows(_emitter(0x01, 0, 0))
	_assert_state(rows, "Child on death", "live", "an enabled on-death child keeps its link Live")


# --- helpers --------------------------------------------------------------

func _config_rows(ed) -> Array:
	var score := Model.build(ed)
	var out := Model.inspector_sections(Target.emitter(0), ed, score)
	var rows: Array = []
	for section in out:
		rows.append_array(section.get("fields", []))
	return rows


func _row(rows: Array, name: String) -> Dictionary:
	for r in rows:
		if str(r.get("name", "")) == name:
			return r
	return {}


func _assert_state(rows: Array, name: String, expected: String, label: String) -> void:
	var r := _row(rows, name)
	if r.is_empty():
		_failed += 1
		print("[FAIL] %s — row '%s' not found" % [label, name])
		return
	var got := str(r.get("relevance", {}).get("state", "<none>"))
	if got == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — '%s' relevance expected %s, got %s" % [label, name, expected, got])


## A one-emitter effect whose emitter 0 spawns emitter `on_death`/`mid_life` children, with the
## given `flags_lo` (child modes live in its low bits). All other groups at parser-shaped zeros.
func _emitter(flags_lo: int, on_death: int, mid_life: int):
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 0}]},
		],
	})
	var em = EffectEmitter.new()
	em.child_emitter_on_death = on_death
	em.child_emitter_mid_life = mid_life
	em.raw_data = {
		"position_start": [0, 0, 0], "position_end": [0, 0, 0],
		"spread_start": [0, 0, 0], "spread_end": [0, 0, 0],
		"angle_start": [0, 0, 0], "angle_end": [0, 0, 0],
		"vel_spread_start": [0, 0, 0], "vel_spread_end": [0, 0, 0],
		"radial_min_start": 0, "radial_max_start": 0, "radial_min_end": 0, "radial_max_end": 0,
		"accel_min_start": [0, 0, 0], "accel_max_start": [0, 0, 0],
		"accel_min_end": [0, 0, 0], "accel_max_end": [0, 0, 0],
		"drag_min_start": [0, 0, 0], "drag_max_start": [0, 0, 0],
		"drag_min_end": [0, 0, 0], "drag_max_end": [0, 0, 0],
		"target_start": [0, 0, 0], "target_end": [0, 0, 0],
		"homing_min_start": 0, "homing_max_start": 0, "homing_min_end": 0, "homing_max_end": 0,
		"curve_indices_raw": [0, 0, 0, 0, 0, 0, 0, 0],
		"motion_type_flag": 0x00, "animation_target_flag": 0x00,
		"emitter_flags_lo": flags_lo, "emitter_flags_hi": 0x00,
		"byte_00": 0, "byte_05": 0,
	}
	em.callback_params = {"param_4C": 0, "param_A8": 0}
	ed.emitters.append(em)
	return ed
