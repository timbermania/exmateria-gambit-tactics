extends Node
## Perf regression guard for the SpacerVerdicts spacer fold (ADR-0087). The fold is the
## whole cost of EffectScoreModel.build, which runs SYNCHRONOUSLY on the UI thread on every
## colour edit — so an O(N^3) fold froze the studio for seconds on colour-dense effects
## (E015, 88 colour spans: measured 3.4 s before the evaluate-once + early-exit leave-one-out
## rewrite, 0.28 s after). This pins that the heaviest bundled effect stays well under a
## ceiling a return to the quadratic/cubic shape would blow straight past.
##
## The ceiling is deliberately loose (5x the post-fix time, ~5x under the pre-fix time) so it
## catches an algorithmic regression, not machine jitter. Correctness of the fold itself is
## SpacerVerdictsTest's job — this only guards the cost.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/SpacerVerdictsPerfTest.tscn

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData

const HEAVY_EFFECT := "E015"          # the colour-densest bundled effect (88 colour spans)
const CEILING_MS := 1500.0            # post-fix ~280 ms; pre-fix ~3400 ms — a wide, non-flaky band

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_heavy_effect_build_stays_fast()
	print("\n=== SpacerVerdictsPerfTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SpacerVerdictsPerfTest")
		get_tree().quit(1)
	else:
		print("[PASS] SpacerVerdictsPerfTest")
		get_tree().quit(0)


func _test_heavy_effect_build_stays_fast() -> void:
	var dir := "res://assets/effects/%s" % HEAVY_EFFECT
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		print("[SKIP] %s extract absent — perf guard skipped" % HEAVY_EFFECT)
		return
	var ed = EffectDataClass.load_from_directory(dir)
	# Warm once (parse-side lazies), then time three builds and take the best — a colour edit
	# pays exactly one Model.build, and we want the algorithm's cost, not a GC hiccup.
	Model.build(ed)
	var best := INF
	for _i in range(3):
		var t := Time.get_ticks_usec()
		Model.build(ed)
		best = minf(best, float(Time.get_ticks_usec() - t) / 1000.0)
	if best <= CEILING_MS:
		_passed += 1
		print("[ok] %s Model.build best-of-3 = %.0f ms (ceiling %.0f ms)" % [HEAVY_EFFECT, best, CEILING_MS])
	else:
		_failed += 1
		print("[FAIL] %s Model.build best-of-3 = %.0f ms EXCEEDS ceiling %.0f ms — the spacer fold likely regressed to O(N^2+)"
			% [HEAVY_EFFECT, best, CEILING_MS])
