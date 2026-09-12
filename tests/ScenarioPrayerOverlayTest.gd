extends Node

## Integration test for the scenario-1 chapel prayer (PC=42) — drives
## `ScenarioVM._op_display_message` against the actual baked chunk JSON
## (`assets/scenarios/scenario_1_chunk.json`), feeds the resolved tokens
## into a real `DialogueOverlay`, and verifies the typewriter produces
## the prayer prefix at known frame milestones.
##
## Bypasses the full `ScenarioPlayer.tscn` (which spins up MapComposer +
## unit spawning + PlayerCamera) so the assertion can target the overlay
## without the cost. Phase 4 of `display_message_overlay_decode.md`.
##
## Run via: <GODOT> --path . --quit-after 5 res://tests/ScenarioPrayerOverlayTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const DialogueOverlayClass = preload("res://src/scenarios/DialogueOverlay.gd")
const CHUNK_JSON_PATH := "res://assets/scenarios/scenario_1_chunk.json"

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_prayer_handler_show_overlay_with_baked_tokens()
	_test_overlay_renders_prayer_prefix_at_milestones()
	_test_subsequent_display_message_clears_overlay()
	_test_overlay_does_not_gate_dispatch()
	_test_prayer_overlay_fades_out_on_dismiss()

	print("\n=== ScenarioPrayerOverlayTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioPrayerOverlayTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioPrayerOverlayTest")
		get_tree().quit(0)


func _make_vm_and_overlay() -> Array:
	var vm: ScenarioVMClass = ScenarioVMClass.new()
	add_child(vm)
	var overlay: DialogueOverlayClass = DialogueOverlayClass.new()
	add_child(overlay)
	# throttle=2 → factor (3−throttle)=1, so the sticky budget maps 1:1 to frames
	# (plain glyph=1, {Delay N}=N and the following glyphs=N). The frame-by-frame
	# assertions then read against the token semantics. (Production is throttle=1
	# → factor 2; see DialogueOverlayTest's golden.)
	overlay.throttle = 2
	vm.dialogue_overlay = overlay
	var ok := vm.load_chunk_json(CHUNK_JSON_PATH)
	_assert_true(ok, "load_chunk_json")
	return [vm, overlay]


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


# ---------- tests ----------

# Calls _op_display_message directly with the prayer instruction; verifies
# the overlay flips active and starts typing.
func _test_prayer_handler_show_overlay_with_baked_tokens() -> void:
	var pair := _make_vm_and_overlay()
	var vm = pair[0]
	var overlay = pair[1]
	var prayer_inst: Dictionary = vm._insts[42]
	_assert_eq(prayer_inst.get("name"), "Display Message", "PC=42 is Display Message")
	_assert_true(prayer_inst.has("dialogue"), "PC=42 has dialogue field")

	vm._op_display_message(prayer_inst)
	_assert_true(overlay.is_active(), "after handler: overlay is active")
	# Pre-tick: no glyphs typed yet.
	_assert_eq(overlay.current_text, "", "pre-tick: overlay text empty")
	vm.queue_free()
	overlay.queue_free()


# Drive the typewriter through the prayer string and pin down the same
# milestones the DialogueOverlayTest pins down, but starting from the
# real baked chunk JSON (not a hand-rolled token list).
func _test_overlay_renders_prayer_prefix_at_milestones() -> void:
	var pair := _make_vm_and_overlay()
	var vm = pair[0]
	var overlay = pair[1]
	vm._op_display_message(vm._insts[42])

	# Token sequence: {Delay 05}"God,{Delay 0F} {Delay 05}please help us{Newline}…
	# Sticky model at factor 1 (throttle=2): the leading {Delay 05}=5 sets the
	# budget, so "God," types at 5 frames/glyph. Absolute-frame seeks.
	var at := [0]
	var seek := func(target: int) -> void:
		overlay.advance_frames(target - at[0])
		at[0] = target
	seek.call(5)
	_assert_eq(overlay.current_text, "", "5 frames: still in opening delay")
	seek.call(6)
	_assert_eq(overlay.current_text, "\"", "f=6: first glyph typed")
	seek.call(26)
	_assert_eq(overlay.current_text, "\"God,", "f=26: '\"God,' typed at 5 frames/glyph")
	# {Delay 0F}=15 → space (budget-15 glyph) → {Delay 05} restores 5;
	# "please help us" (14 glyphs @5) ends at f=131.
	seek.call(131)
	_assert_eq(overlay.current_text, "\"God, please help us",
		"f=131: first line complete (space + delays + 14 glyphs)")
	# Newline drains free; 'sinful children of Ivalice' (26 glyphs @5) ends f=261.
	seek.call(261)
	_assert_eq(
		overlay.current_text,
		"\"God, please help us\nsinful children of Ivalice",
		"f=261: second line complete",
	)
	vm.queue_free()
	overlay.queue_free()


# A subsequent Display Message of any kind (boxed OR overlay) should clear
# the previous overlay — captures the default clear-trigger rule per the
# living doc's Phase 3 (pending A.3/B.3 confirmation).
func _test_subsequent_display_message_clears_overlay() -> void:
	var pair := _make_vm_and_overlay()
	var vm = pair[0]
	var overlay = pair[1]
	vm._op_display_message(vm._insts[42])
	overlay.advance_frames(20)
	_assert_true(not overlay.current_text.is_empty(),
		"after 20 frames: overlay has some text")

	# Find the next Display Message in the chunk (a boxed variant).
	var next_dm_inst: Dictionary = {}
	for i in range(43, vm._insts.size()):
		var inst: Dictionary = vm._insts[i]
		if str(inst.get("name", "")) == "Display Message":
			next_dm_inst = inst
			break
	_assert_true(not next_dm_inst.is_empty(),
		"chunk has another Display Message after PC=42")

	# A subsequent Display Message dismisses the prayer via the ROM fade-out
	# ramp (Part A), NOT an instant pop — so right after the handler the overlay
	# is still active (fading). Drive the ramp to completion, then assert cleared.
	vm._op_display_message(next_dm_inst)
	_assert_true(overlay.is_active(),
		"subsequent Display Message begins the overlay fade (not an instant clear)")
	overlay.advance_frames(20)
	_assert_eq(overlay.current_text, "",
		"after fade completes: overlay cleared")
	_assert_true(not overlay.is_active(),
		"after fade completes: overlay deactivated")
	vm.queue_free()
	overlay.queue_free()


# REGRESSION (Fix 2, 2026-07-01): the overlay is NON-BLOCKING. On PSX the
# typewriter runs off the frame-sync interrupt, not the event dispatcher — the
# {1A} Map Darkness fires at prayer+1.4 s and Ovelia's Unit Anim at +3.9 s while
# the last glyph doesn't land until +8.2 s (TYPEWRITER_TEXT_CADENCE.md §4.4). So
# `_op_display_message` must NOT arm a wait-gate on the calling context: after
# the handler runs, the overlay is typing yet the context is free to dispatch
# the following Wait / Map Darkness / Unit Anim.
func _test_overlay_does_not_gate_dispatch() -> void:
	var pair := _make_vm_and_overlay()
	var vm = pair[0]
	var overlay = pair[1]
	vm._op_display_message(vm._insts[42])
	_assert_true(overlay.is_active(),
		"non-blocking: overlay is typing after handler")
	# The calling context must NOT be parked on a wait_until predicate — that
	# would halt opcode dispatch until the typewriter finished (the old gated
	# behaviour this regression guards against).
	_assert_true(vm._current_ctx != null, "non-blocking: main context exists")
	_assert_true(not vm._current_ctx.wait_until.is_valid(),
		"non-blocking: handler armed no wait-gate on the calling context")
	vm.queue_free()
	overlay.queue_free()


# Part A / §C.1: on dismiss the prayer text FADES OUT — a brightness ramp
# 1.0 → 0x38/0x80 (≈0.4375) in steps of 8/128 per 60 Hz tick, THEN a handle-free
# removal. It is NOT an instant pop, NOT alpha, NOT a box shrink. Drives
# `_container.modulate` (the ROM Gouraud-RGB brightness) through the ramp.
func _test_prayer_overlay_fades_out_on_dismiss() -> void:
	var pair := _make_vm_and_overlay()
	var vm = pair[0]
	var overlay = pair[1]
	vm._op_display_message(vm._insts[42])
	# Box-type-0 (Dialog 0x09) SELF-DISMISSES on completion — no clear() call, no
	# next Display Message (§Z.9). Type it out one frame at a time until the fade
	# begins, capturing the pre-fade state. (Per-frame advance is how ScenarioVM
	# pumps it; a single batched call also works now — see DialogueOverlay
	# advance_frames, which hands leftover frames to the fade after completion.)
	var fade_began := false
	for _i in range(1500):
		if overlay._fading:
			fade_began = true
			break
		overlay.advance_frames(1)
	_assert_true(fade_began, "self-dismiss: prayer auto-fades on completion (no external clear)")
	_assert_true(not overlay.current_text.is_empty(), "self-dismiss: text present as the fade starts")
	_assert_true(overlay.visible, "self-dismiss: still visible at fade start")
	_assert_true(overlay.is_active(), "self-dismiss: active while fading")
	_assert_true(overlay._container.modulate.r > 0.99, "self-dismiss: ramp starts at full brightness")

	# One tick drops brightness (−8/128 = 0.9375), still above the 0.4375 floor.
	overlay.advance_frames(1)
	var mid: float = overlay._container.modulate.r
	_assert_true(mid < 1.0 and mid > 0.4375, "self-dismiss: brightness dropping (%s)" % str(mid))

	# Ramp to the 0x38 floor then handle-free removal → hidden + inactive.
	overlay.advance_frames(20)
	_assert_true(not overlay.visible, "self-dismiss: hidden after ramp completes")
	_assert_true(not overlay.is_active(), "self-dismiss: inactive after ramp completes")
	_assert_eq(overlay.current_text, "", "self-dismiss: text cleared after ramp")
	vm.queue_free()
	overlay.queue_free()
