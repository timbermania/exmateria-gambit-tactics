extends Node
## TDD guard for the Effect Studio "Save to E###.BIN" loop — the GAME→JSON half of the
## byte-perfect round-trip (Option B, slice 1). For the loop to reproduce a byte-identical
## BIN, the game must write back a `screen.json` that faithfully reproduces the one it
## loaded: `ScreenData.from_json(J).to_json()` must equal `J`. This requires ScreenData to
## RETAIN the full raw sub-block (the previous model dropped end_r/g/b, keeping only the
## Colors) and to expose a `to_json()` inverse of `from_json`.
##
## Independent source of truth: the real on-disk `assets/effects/E001/screen.json` (a
## faithful parse of E001.BIN) — NOT a value recomputed by the code under test.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ScreenDataRoundTripTest.tscn

const ScreenData = ExMateriaEffects.ScreenData

const SCREEN_JSON := "res://assets/effects/E001/screen.json"
const CONTEXTS := ["for_each", "phase1", "phase2"]
# Every field the on-disk screen.json carries per keyframe (the faithful write-back set).
const KF_FIELDS := ["index", "time_value", "duration_frames",
	"start_r", "start_g", "start_b", "end_r", "end_g", "end_b",
	"ctrl", "mode", "blend_mode"]

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_from_json_to_json_reproduces_the_on_disk_screen_json()

	print("\n=== ScreenDataRoundTripTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScreenDataRoundTripTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScreenDataRoundTripTest")
		get_tree().quit(0)


func _test_from_json_to_json_reproduces_the_on_disk_screen_json() -> void:
	var orig = _load_json(SCREEN_JSON)
	_assert_true(orig is Dictionary and not orig.is_empty(), "loaded E001 screen.json")
	if not (orig is Dictionary) or orig.is_empty():
		return

	var sd = ScreenData.from_json(orig)
	var out = sd.to_json()
	_assert_true(out is Dictionary, "to_json returns a Dictionary")

	for ctx in CONTEXTS:
		if not orig.has(ctx):
			continue
		_assert_true(out.has(ctx), "to_json emits the '%s' context" % ctx)
		if not out.has(ctx):
			continue
		var oc: Dictionary = orig[ctx]
		var wc: Dictionary = out[ctx]
		_assert_eq(int(wc.get("max_keyframe", -999)), int(oc.get("max_keyframe", -1)),
			"%s max_keyframe round-trips" % ctx)

		var okf: Array = oc.get("keyframes", [])
		var wkf: Array = wc.get("keyframes", [])
		_assert_eq(wkf.size(), okf.size(), "%s keyframe count round-trips (33)" % ctx)
		if wkf.size() != okf.size():
			continue

		for i in range(okf.size()):
			for f in KF_FIELDS:
				var ov = okf[i].get(f)
				var wv = wkf[i].get(f)
				# Type-tolerant compare: mode is a string, everything else numeric.
				var same := (str(ov) == str(wv)) if (f == "mode") else (int(ov) == int(wv))
				_assert_true(same, "%s kf[%d].%s round-trips (%s → %s)" % [ctx, i, f, str(ov), str(wv)])
				if not same:
					return   # one clear failure is enough; stop the flood


func _load_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text())


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
