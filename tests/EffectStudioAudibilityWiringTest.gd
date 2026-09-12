extends Node
## TDD guard for EffectStudioPage's Solo/Mute → host wiring. When a lane's solo/mute
## toggles on the timeline, the page resolves the whole preview audibility
## (EffectScoreModel.resolve_audibility) and forwards it to the host via
## studio_set_audibility(audibility) — the resolve_audibility result; the host then routes
## it to the particle renderer + subsystems. Loading an effect re-applies (a fresh
## instance starts fully audible). Uses a real page + fake host. See CONTEXT.md
## "Effect Studio".
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioAudibilityWiringTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_toggle_forwards_audibility_to_host()
	await _test_load_reapplies_audibility()

	print("\n=== EffectStudioAudibilityWiringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioAudibilityWiringTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioAudibilityWiringTest")
		get_tree().quit(0)


## Muting a particle lane on the timeline forwards the resolved audibility to the
## host: its emitters in disabled_emitters (a particle lane gates no folded subsystem).
func _test_toggle_forwards_audibility_to_host() -> void:
	var page = await _page()
	var host = page._host
	host.reset()
	var lane_id := _first_particle_lane_with_spans(page)
	_assert_true(lane_id != "", "the loaded effect has a particle lane with emitters")
	page._timeline.toggle_mute(lane_id)
	_assert_eq(host.audibility_calls, 1, "toggling mute forwards audibility to the host once")
	_assert_true(not host.last_audibility.get("disabled_emitters", {}).is_empty(),
		"the muted particle lane's emitters are disabled")


## Loading an effect re-applies audibility (so a freshly-spawned instance, which
## starts fully audible, matches the current selection — here empty → all audible).
func _test_load_reapplies_audibility() -> void:
	var page = await _page()
	var host = page._host
	host.reset()
	page._load_effect(page._effect_dirs[0])
	_assert_true(host.audibility_calls >= 1, "loading an effect re-applies audibility to the host")
	_assert_true(host.last_audibility.get("disabled_emitters", {}).is_empty(), "a fresh load with nothing muted disables no emitters")
	_assert_true(host.last_audibility.get("muted_screen", {}).is_empty(), "a fresh load mutes no screen lanes")
	_assert_true(host.last_audibility.get("muted_palette", {}).is_empty(), "a fresh load mutes no palette lanes")


# --- fixtures -------------------------------------------------------------

func _page():
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame   # let _ready build the UI + load the default effect
	page.bind_host(_FakeHost.new())
	return page


func _first_particle_lane_with_spans(page) -> String:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") == "particle" and not lane["spans"].is_empty():
			return lane["id"]
	return ""


class _FakeHost extends RefCounted:
	var audibility_calls: int = 0
	var last_audibility: Dictionary = {}

	func reset() -> void:
		audibility_calls = 0
		last_audibility = {}

	func studio_set_audibility(audibility: Dictionary) -> void:
		audibility_calls += 1
		last_audibility = audibility

	func studio_select_effect(_effect_id: int) -> void:
		pass

	func studio_seek(_frame: int) -> void:
		pass

	func studio_set_playing(_playing: bool) -> void:
		pass

	func studio_current_frame() -> int:
		return 0


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
