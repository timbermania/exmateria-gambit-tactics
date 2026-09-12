extends Node
## TDD guard for the Effect Studio page-side playback SPEED (ADR-0090 dec. 4
## "speed is a continuous 0.1×–4× scrub field"). Speed is page state that multiplies
## the transport accumulator (`delta × TRANSPORT_HZ × speed`); the widget got finer
## (a continuous ScrubField replacing the 4-step cycle button), the transport did not.
## Two seams:
##   * PROPORTIONALITY — parked host, forward loop: N seconds at speed S advances the
##     playhead TRANSPORT_HZ · S · N frames (the accumulator carries fractional frames,
##     so a non-integer speed is frame-exact). This is the behaviour the field drives.
##   * WIDGET — the toolbar speed control is a ScrubField configured 0.1×–4× / step 0.05
##     / 0.01 per-px, seeded 1.0 with no signal, and its value_changed sets _speed_value
##     (so the range clamps the reachable speed).
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioSpeedFieldTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Transport = preload("res://src/effects/studio/LoopTransport.gd")
const ScrubField = preload("res://src/effects/studio/ScrubField.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_speed_scales_transport_advance()
	await _test_speed_field_is_a_scrubfield_configured_for_speed()
	await _test_field_value_change_drives_and_clamps_speed()
	await _test_seed_fires_no_signal()

	print("\n=== EffectStudioSpeedFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSpeedFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSpeedFieldTest")
		get_tree().quit(0)


# --- proportionality (the transport reads _speed()) -----------------------

## Park the host, run a FORWARD loop over a huge span (so the playhead never wraps),
## and count the forward host-seeks over a fixed tick sequence. At 30 Hz for 2.0 s the
## base advance is 60 frames (30 fps × 2 s, derived independently of the accumulator);
## the speed multiplies it. Assert both the absolute count and that doubling the speed
## doubles the advance.
func _test_speed_scales_transport_advance() -> void:
	# 2.0 s delivered as 100 ticks of 0.02 s. Per-tick advance 0.02·30·S stays under the
	# MAX_STEPS_PER_FRAME burst cap for every S in [0.1, 4], so no backlog is dropped.
	var at_half := await _advance_frames(0.5, 100, 0.02)
	var at_one := await _advance_frames(1.0, 100, 0.02)
	var at_two := await _advance_frames(2.0, 100, 0.02)

	# 30 fps × 2.0 s × speed, hand-derived (±1 for float accumulation at the boundary).
	_assert_near(at_one, 60, "speed 1.0× advances ~60 frames over 2 s")
	_assert_near(at_half, 30, "speed 0.5× advances ~30 frames over 2 s")
	_assert_near(at_two, 120, "speed 2.0× advances ~120 frames over 2 s")
	# Proportionality, independent of the absolute constant: 2× is twice 1×, ½× is half.
	_assert_near(at_two, at_one * 2, "doubling the speed doubles the advance")
	_assert_near(at_half, at_one / 2, "halving the speed halves the advance")


# --- widget config + wiring ----------------------------------------------

func _test_speed_field_is_a_scrubfield_configured_for_speed() -> void:
	var page = await _page()
	var f = page._speed_btn
	_assert_true(f is ScrubField, "the toolbar speed control is a ScrubField (not a cycle button)")
	_assert_true(is_equal_approx(f.min_value, 0.1), "min speed is 0.1×")
	_assert_true(is_equal_approx(f.max_value, 4.0), "max speed is 4.0×")
	_assert_true(is_equal_approx(f.step, 0.05), "step is 0.05 (2-decimal free-continuous grid)")
	_assert_true(is_equal_approx(f.scrub_sensitivity, 0.01), "scrub sensitivity is 0.01 value/px")
	_assert_eq(f.suffix, "×", "the field renders a × suffix")
	_assert_true(is_equal_approx(f.value, 1.0), "the field is seeded to 1.0×")
	_assert_true(is_equal_approx(page._speed(), 1.0), "_speed() reads the seeded 1.0×")
	page.queue_free()


func _test_field_value_change_drives_and_clamps_speed() -> void:
	var page = await _page()
	# A real value change (via the field's value setter) fans value_changed → _speed_value.
	page._speed_btn.value = 2.0
	_assert_true(is_equal_approx(page._speed(), 2.0), "changing the field sets the page speed")
	# The 0.1–4 range clamps the reachable speed: over/under-range values pin to the ends.
	page._speed_btn.value = 99.0
	_assert_true(is_equal_approx(page._speed(), 4.0), "an over-range value clamps to 4.0×")
	page._speed_btn.value = 0.0
	_assert_true(is_equal_approx(page._speed(), 0.1), "an under-range value clamps to 0.1×")
	page.queue_free()


func _test_seed_fires_no_signal() -> void:
	var page = await _page()
	var fires := [0]
	page._speed_btn.value_changed.connect(func(_v): fires[0] += 1)
	page._speed_btn.set_value_no_signal(3.0)
	_assert_eq(fires[0], 0, "set_value_no_signal seeds the field without firing value_changed")
	_assert_true(is_equal_approx(page._speed_btn.value, 3.0), "…but the seeded value took effect")
	# A subsequent real change still fires (proves the signal is live, not disconnected).
	page._speed_btn.value = 2.0
	_assert_eq(fires[0], 1, "a real value change still fires value_changed")
	page.queue_free()


# --- fixtures -------------------------------------------------------------

## Build a page, park a fake host, set a FORWARD loop over a huge span, seed the speed
## directly, and drive `count` process ticks of `dt`. Returns the number of forward
## host-seeks (== frames the playhead advanced).
func _advance_frames(speed: float, count: int, dt: float) -> int:
	var page = await _page()
	var host = _FakeHost.new()
	page.bind_host(host)
	page._end_frame = 100000          # huge span: forward loop never wraps
	page._loop_mode = Transport.MODE_FORWARD
	page._loop_dir = Transport.DIR_FWD
	page._speed_value = speed
	page._playing = true
	page._transport_accum = 0.0
	host.reset()
	for _i in range(count):
		page._process(dt)
	var n: int = host.seek_calls
	page.queue_free()
	return n


func _page():
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame   # let _ready build the UI (host still null → no seeks)
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

	func studio_seek_silent(frame: int) -> void:
		seek_calls += 1
		last_seek = frame

	func studio_set_playing(_playing: bool) -> void:
		pass

	func studio_current_frame() -> int:
		return last_seek


# --- asserts --------------------------------------------------------------

func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_near(actual: int, expected: int, label: String) -> void:
	if absi(actual - expected) <= 1:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected ~%d, got %d" % [label, expected, actual])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)
