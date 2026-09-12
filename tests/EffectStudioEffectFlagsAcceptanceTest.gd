extends Node
## ACCEPTANCE (headful, real E019 = Fire 4, #272 / ADR-0092): the whole "Effect Settings →
## toggle an engine flag → the preview responds" path, end to end through the live studio.
##   1. The "Effect ⚙" button opens the effect_settings target, and the inspector renders a
##      Flags section whose one bitflags row is seeded with E019's RAW byte 0x23 (bits 0,1
##      ignored + bit5 time-scale 3-phase).
##   2. Clearing bit5 through the page choke point writes the flags byte (0x23 → 0x03, ignored
##      bits 0,1 preserved) AND syncs data.time_scale.flags.time_scale_pattern1 → false.
##   3. That sync makes the PREVIEW SPEED change: E019's outer_phases curve peaks at pacing
##      9-10, so with pattern1 ON the real EffectTimeline sim slows below 1.0× during phase 1;
##      with it OFF (after the edit) the factor stays 1.0× the whole phase. Driven on the real
##      sim class with the actual edited data — the honest "the flag does something" proof.
## Skips when E019 assets are absent (gitignored/ROM-derived). A screenshot is written.
## Run: godot --path . --quit-after 400 res://tests/EffectStudioEffectFlagsAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectTimelineClass = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")
const SHOT := "user://effect_flags_e019.png"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioEffectFlagsAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioEffectFlagsAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioEffectFlagsAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	_assert_true(dir != "", "E019 in the effect catalogue")
	page._load_effect(dir)
	await _frames(40)

	var data = page._effect_data
	_assert_true(data != null and not data.flags.is_empty(), "E019 has a parsed flags block")
	_assert_true(not data.time_scale.is_empty(), "E019 has time-scale data (bit5 has something to drive)")
	if data == null or data.flags.is_empty():
		return

	_assert_eq(int(data.flags.get("flags_byte", -1)), 0x23, "E019's raw flags byte is 0x23")

	# --- (1) The Effect ⚙ button opens the settings surface with the Flags row. ---
	page._open_effect_settings()
	await _frames(10)
	_assert_true(Target.kind(page._nav.back()) == "effect_settings",
		"the button navigated to the effect_settings target")
	var sections = Model.inspector_sections(Target.effect_settings(), data, page._timeline._score)
	var flags_sec := _find_section(sections, "Flags")
	_assert_true(not flags_sec.is_empty(), "the inspector shows a Flags section")
	var row = flags_sec.get("fields", [])[0] if not flags_sec.get("fields", []).is_empty() else {}
	_assert_eq(str(row.get("editor", "")), "bitflags", "the Flags row is a bitflags group")
	_assert_eq(int(row.get("value", -1)), 0x23,
		"the row seeds the RAW byte 0x23 (ignored bits 0,1 ride along, not just the four bools)")

	# --- (2) Measure the preview speed with bit5 ON (before the edit). ---
	var p1: int = int(data.timeline.phase1_duration)
	var min_factor_on := _min_phase1_factor(data.time_scale.duplicate(true), p1)
	_assert_true(min_factor_on < 1.0,
		"with time-scale 3-phase ON, the sim slows below 1.0x in phase 1 (min factor %.3f)" % min_factor_on)

	# --- (3) Clear bit5 through the page choke point → byte written + time-scale synced. ---
	page._apply_edit({"channel": "effect_flags", "field": "flags_byte"}, 0x03)
	await _frames(20)
	_assert_eq(int(data.flags.get("flags_byte", -1)), 0x03, "the flags byte is written to 0x03")
	_assert_eq(int(data.flags.get("flags_byte", -1)) & 0x03, 0x03, "engine-ignored bits 0,1 preserved")
	_assert_true(not bool(data.time_scale.get("flags", {}).get("time_scale_pattern1", true)),
		"clearing bit5 synced time_scale.flags.time_scale_pattern1 → false")

	# --- (4) The preview no longer slows: factor stays 1.0x the whole phase. ---
	var min_factor_off := _min_phase1_factor(data.time_scale, p1)
	_assert_eq(min_factor_off, 1.0,
		"with 3-phase OFF the sim runs at 1.0x through phase 1 (preview speed changed): %.3f" % min_factor_off)

	# Visual record for the eyeball.
	await _frames(5)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(SHOT)
	_assert_true(err == OK, "screenshot written to %s" % ProjectSettings.globalize_path(SHOT))
	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT))
	print("  phase-1 min factor: ON=%.3f  OFF=%.3f" % [min_factor_on, min_factor_off])


## Drive the REAL EffectTimeline sim over phase 1 with the given time-scale data and return the
## minimum time-scale factor observed — < 1.0 means the pacing curve slowed the preview. No
## subsystems (we only read the factor the timeline computes from the pacing curve).
func _min_phase1_factor(time_scale_data: Dictionary, phase1_duration: int) -> float:
	var tl = EffectTimelineClass.new()
	# Keep phase 2 well beyond the window so the whole measurement stays in phase 1.
	tl.setup(phase1_duration, phase1_duration + 10000, time_scale_data)
	tl.set_subsystems([])
	tl.start()
	var min_factor := 1.0
	for i in range(maxi(1, phase1_duration)):
		tl._advance_one_frame()
		min_factor = minf(min_factor, tl._time_scale_factor)
	return min_factor


# --- helpers ---------------------------------------------------------------
func _find_section(sections: Array, title: String) -> Dictionary:
	for sec in sections:
		if str(sec.get("title", "")) == title:
			return sec
	return {}


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


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
