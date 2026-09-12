extends Node
## current_anim_id read-only funnel test (ADR-0053, issue #152). The property is
## a getter only — the write half retired now that `play_body` is the single
## funnel. Asserts the getter defaults to 0 (idle), reflects `play_body` writes
## across the SEQ + EVTCHR ranges and back to idle, and that a same-value
## `play_body` is idempotent (the paint-time pose-resample contract).
## Clock-restart side effects are verified at integration time — the chapel
## cinematic Agrias rotate cascade is the oracle (handoff "Pass condition for
## Path D").
##
## Builds a bare Unit + AnimationStateController without going through
## Unit._ready — same pattern as UnitScenarioRotateTest, so `play_body` runs with
## `_initialized = false` and the type1_playback restart is guarded out (paint
## code already guards on `_initialized` everywhere).


func _ready() -> void:
	var failed := false

	var unit := Unit.new()

	# 1. Default value is 0 (idle).
	failed = _expect(unit.current_anim_id == 0, "default current_anim_id == 0 (idle)", failed)

	# 2. play_body drives a SEQ-range anim id; the getter reflects it.
	unit.play_body(42)
	failed = _expect(unit.current_anim_id == 42, "play_body drives SEQ-range value (42)", failed)

	# 3. Same-value play_body is idempotent (no-op contract for pose resampling).
	unit.play_body(42)
	failed = _expect(unit.current_anim_id == 42, "same-value play_body idempotent", failed)

	# 4. play_body drives an EVTCHR-range value (>= 0x1f5).
	unit.play_body(0x025d)
	failed = _expect(unit.current_anim_id == 0x025d, "play_body drives EVTCHR-range value (0x025d)", failed)

	# 5. play_body(0) resets to idle.
	unit.play_body(0)
	failed = _expect(unit.current_anim_id == 0, "play_body resets to 0 (idle)", failed)

	unit.free()

	if failed:
		print("[FAIL] UnitCurrentAnimIdTest")
	else:
		print("[PASS] UnitCurrentAnimIdTest: getter default + play_body funnel across SEQ + EVTCHR + idle reset")
	get_tree().quit()


func _expect(cond: bool, label: String, failed_so_far: bool) -> bool:
	if not cond:
		print("[FAIL] %s" % label)
		return true
	return failed_so_far
