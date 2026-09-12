extends Node
## Differential guard: the Effect Studio score must show ONLY the palette keyframes
## the runtime actually plays. The runtime (PaletteSubsystem._each_keyframe) is the
## single definition of the keyframe window — it applies indices 0..max_keyframe-2
## and treats the rest as terminators/padding. EffectScoreModel must mirror that
## window exactly, or the Studio draws phantom spans (E077 affected_units showed a
## bogus [600,5400] tint from a padding keyframe past max_keyframe). Compares the
## model's per-lane authored starts against the frames the runtime emits, over a
## real effect with heavy padding.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectScoreWindowParityTest.tscn

const PaletteData = ExMateriaEffects.PaletteData

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const PaletteSubsystem = ExMateriaEffects.PaletteSubsystem
const EffectPhase = ExMateriaEffects.EffectPhase
const EffectDataClass = ExMateriaEffects.EffectData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_palette_window_matches_runtime("E077")

	print("\n=== EffectScoreWindowParityTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectScoreWindowParityTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectScoreWindowParityTest")
		get_tree().quit(0)


func _test_palette_window_matches_runtime(effect_name: String) -> void:
	var dir := "res://assets/effects/%s" % effect_name
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		print("[SKIP] %s assets absent" % effect_name)
		return
	var ed = EffectDataClass.load_from_directory(dir)
	var score := Model.build(ed)

	var sub = PaletteSubsystem.new()
	sub.initialize(ed.palette)

	for phase in EffectPhase.ALL:
		for channel in PaletteData.ALL_CHANNELS:
			var ch = ed.palette.get_channel(phase, channel)
			if ch == null or ch.keyframes.is_empty():
				continue
			# Runtime: the ENABLED keyframe local starts it actually emits.
			var runtime_starts: Array = []
			sub._each_keyframe(channel, phase, 0, func(_kf, at: int) -> void:
				runtime_starts.append(at))
			runtime_starts.sort()
			# Model: the authored (local) starts of the spans it draws.
			var lane := _lane(score, "palette:%s:%s" % [phase, channel])
			var model_starts: Array = []
			for span in lane.get("spans", []):
				model_starts.append(span["authored_start"])
			model_starts.sort()

			var label := "%s palette:%s:%s (max_keyframe=%d)" % [
				effect_name, phase, channel, ch.max_keyframe]
			if model_starts == runtime_starts:
				_passed += 1
			else:
				_failed += 1
				print("[FAIL] %s — model draws starts %s but runtime plays %s" % [
					label, str(model_starts), str(runtime_starts)])


func _lane(score: Dictionary, lane_id: String) -> Dictionary:
	for lane in score["lanes"]:
		if lane["id"] == lane_id:
			return lane
	return {}
