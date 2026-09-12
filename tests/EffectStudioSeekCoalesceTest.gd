extends Node
## TDD guard for EffectStudioPage's scrub-seek COALESCING. A drag emits
## seek_requested per mouse-motion (many per frame); each host seek can
## reset+repump the effect from 0 (ADR-0070, ~0.7 ms/frame → 100+ ms for a late
## backward target). The page must move the playhead per-event (cheap, responsive)
## but apply at most ONE host.studio_seek per _process tick, to the LATEST frame.
## Discrete transport (stop/step) must still seek immediately. See CONTEXT.md
## "Effect Studio" / "Playhead / scrub".
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioSeekCoalesceTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_scrub_coalesces_to_one_seek_per_frame()
	await _test_discrete_seek_is_immediate()

	print("\n=== EffectStudioSeekCoalesceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSeekCoalesceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSeekCoalesceTest")
		get_tree().quit(0)


func _test_scrub_coalesces_to_one_seek_per_frame() -> void:
	var page = await _page()
	var host = page._host
	host.reset()
	# A burst of scrub events (as a fast drag delivers within one frame).
	for f in [40, 33, 21, 8, 55]:
		page._on_seek_requested(f)
	_assert_eq(host.seek_calls, 0, "no host seek fires synchronously during a scrub burst")
	_assert_eq(page._timeline.get_playhead(), 55, "playhead tracks the LATEST scrub position immediately")
	# One process tick drains exactly one seek, to the latest position.
	page._process(0.016)
	_assert_eq(host.seek_calls, 1, "exactly one host seek per frame, not one per event")
	_assert_eq(host.last_seek, 55, "the coalesced seek targets the latest cursor frame")
	# A second tick with nothing pending does not re-seek.
	page._process(0.016)
	_assert_eq(host.seek_calls, 1, "an idle tick does not re-seek")
	page.queue_free()


func _test_discrete_seek_is_immediate() -> void:
	# Transport buttons route through _seek() and must NOT be deferred.
	var page = await _page()
	var host = page._host
	host.reset()
	page._seek(12)
	_assert_eq(host.seek_calls, 1, "a discrete _seek() applies immediately (one call)")
	_assert_eq(host.last_seek, 12, "discrete seek targets its frame")
	page.queue_free()


# --- fixtures -------------------------------------------------------------

func _page():
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame   # let _ready build the UI (host still null → no seeks)
	page.bind_host(_FakeHost.new())
	return page


class _FakeHost extends RefCounted:
	var seek_calls: int = 0
	var last_seek: int = -1

	func reset() -> void:
		seek_calls = 0
		last_seek = -1

	func studio_seek(frame: int) -> void:
		seek_calls += 1
		last_seek = frame

	func studio_set_playing(_playing: bool) -> void:
		pass

	func studio_current_frame() -> int:
		return last_seek


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
