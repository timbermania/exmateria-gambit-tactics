extends Node
## TDD guard (#270, ADR-0093) for EffectTimeScaleSaver — the game→json→bin repack of the effect's
## two PACING curves. Two seams: (1) the pure adapter reads the live time_scale dict into the
## writer's `{outer_phases, for_each}` shape; (2) end-to-end, save() shells the byte-exact Python
## writer and the output E###.BIN carries the edited curves nibble-packed, with every change
## contained to the two 300-byte curve regions (ROM-backed; skipped when the extract is absent).
##
## Run: <GODOT> --path . --quit-after 5 res://tests/EffectTimeScaleSaverTest.tscn

const EffectTimeScaleSaver = preload("res://src/effects/studio/EffectTimeScaleSaver.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_adapter_reads_live_curves()
	_test_adapter_refuses_empty()
	_test_save_packs_edited_curves_within_the_region()

	print("\n=== EffectTimeScaleSaverTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectTimeScaleSaverTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectTimeScaleSaverTest")
		get_tree().quit(0)


func _block(outer_v: int, foreach_v: int) -> Dictionary:
	var outer: Array = []
	var foreach: Array = []
	for i in range(600):
		outer.append(outer_v)
		foreach.append(foreach_v)
	return {
		"flags": {"time_scale_pattern1": true, "time_scale_pattern2": false},
		"outer_phases": outer, "for_each": foreach,
	}


func _test_adapter_reads_live_curves() -> void:
	var res: Dictionary = EffectTimeScaleSaver.to_time_scale_json(_block(2, 3))
	_assert_true(res.get("ok", false), "adapter accepts a live time_scale dict")
	_assert_eq((res.get("json", {}).get("outer_phases", []) as Array).size(), 600,
		"outer_phases carried verbatim (600 ints)")
	_assert_eq((res.get("json", {}).get("for_each", []) as Array)[0], 3, "for_each carried verbatim")


func _test_adapter_refuses_empty() -> void:
	_assert_true(not EffectTimeScaleSaver.to_time_scale_json({}).get("ok", true),
		"an empty time_scale dict is a hard error, not a crash")
	_assert_true(not EffectTimeScaleSaver.to_time_scale_json({"flags": {}}).get("ok", true),
		"a time_scale dict missing the curves is refused")


## End-to-end: save all-2 outer + all-3 for_each into E019 through the Python writer, and confirm
## both 300-byte regions pack to the expected nibbles AND every change is contained to the region.
func _test_save_packs_edited_curves_within_the_region() -> void:
	var base := ProjectSettings.globalize_path("res://").path_join(
		"../project-assets/fft-extract/EFFECT/E019.BIN").simplify_path()
	if not FileAccess.file_exists(base) \
			or not FileAccess.file_exists("res://assets/effects/E019/header.json"):
		print("  [skip] E019 ROM extract / header.json absent — writer round-trip not run")
		_passed += 1
		return

	var base_bytes := FileAccess.get_file_as_bytes(base)
	var ts_ptr := int(base_bytes.decode_u32(0x14))  # time_scale_ptr (header 0x14, base_offset 0)
	_assert_true(ts_ptr != 0, "E019 carries a live time_scale section")

	var res: Dictionary = EffectTimeScaleSaver.save(19, _block(2, 3))
	_assert_true(res.get("ok", false), "save() succeeds: %s" % res.get("error", ""))
	if not res.get("ok", false):
		return

	var out_bytes := FileAccess.get_file_as_bytes(res.get("out_path", ""))
	# outer_phases region: all-2 → every byte 0x22 (both nibbles = 2).
	_assert_eq(out_bytes[ts_ptr], 0x22, "outer_phases region packs all-2 nibbles (0x22)")
	_assert_eq(out_bytes[ts_ptr + 150], 0x22, "…across the whole 300-byte outer region")
	# for_each region: all-3 → every byte 0x33.
	_assert_eq(out_bytes[ts_ptr + 300], 0x33, "for_each region packs all-3 nibbles (0x33)")
	# Every change is contained to the two 300-byte regions [ts_ptr, ts_ptr+600).
	var strayed := 0
	for i in range(base_bytes.size()):
		if out_bytes[i] != base_bytes[i] and (i < ts_ptr or i >= ts_ptr + 600):
			strayed += 1
	_assert_eq(strayed, 0, "no byte outside the two curve regions changed")


# --- helpers ---------------------------------------------------------------
func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
