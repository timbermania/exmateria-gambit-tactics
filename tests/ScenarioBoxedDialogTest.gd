extends Node3D

## Integration test for the BOXED Display Message path in ScenarioVM, driving
## the real baked chunk (scenario_1_chunk.json) through a real DialogueBox.
##
## Covers Phase 4 of the boxed-dialog build:
##   * Dialog-byte routing: 0x1X/0x9X/0x7X → boxed; 0x09 → overlay; others skip.
##   * Boxed Display Message → DialogueBox.show_dialog + arms the advance gate.
##   * Wait For Instruction consumes the gate (interactive halt; auto-advance
##     dwell in play-through).
##   * `_advance_dialog`: 1st press finishes typing, 2nd releases the gate.
##   * Change Dialog 0xFFFF closes the box; a baked-message swap re-shows text.
##   * message_id → tokens index built from Display Message records.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/ScenarioBoxedDialogTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const DialogueBoxClass = preload("res://src/ui3/assemblies/DialogueBox.gd")
const CHUNK_JSON_PATH := "res://assets/scenarios/scenario_1_chunk.json"

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_routing_predicate()
	_test_boxed_show_and_gate()
	_test_advance_two_press()
	_test_advance_is_delivered_not_polled()
	_test_change_dialog_close()
	_test_auto_advance_dwell()
	_test_message_index_and_swap()
	_test_change_dialog_swap_updates_portrait()
	_test_change_dialog_swap_col0_keeps_portrait()
	_test_boxed_portrait_fronts_speaker_template_folder()
	_test_pagination_advance_press_ladder()
	_test_pagination_auto_advance_pages()
	_test_concurrent_boxes_147_154()
	_test_first_event_non_persist_closes_on_advance()

	print("\n=== ScenarioBoxedDialogTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioBoxedDialogTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioBoxedDialogTest")
		get_tree().quit(0)


func _make_vm_and_box() -> Array:
	var vm = ScenarioVMClass.new()
	add_child(vm)
	var box = DialogueBoxClass.new()
	add_child(box)
	box.throttle = 2  # factor 1 → 1 frame/glyph for clean frame-count assertions
	vm.box_pool.dialogue_box = box
	var ok: bool = vm.load_chunk_json(CHUNK_JSON_PATH)
	_assert_true(ok, "load_chunk_json")
	return [vm, box]


func _first_boxed_pc(vm) -> int:
	for i in range(vm._insts.size()):
		var inst = vm._insts[i]
		if str(inst.get("name", "")) != "Display Message":
			continue
		var dlg := 0
		for p in inst.get("params", []):
			if str(p["name"]) == "Dialog":
				dlg = int(p["value"])
		if vm.box_pool._is_boxed_dialog(dlg & 0xFF):
			return i
	return -1


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

func _test_routing_predicate() -> void:
	var vm = ScenarioVMClass.new()
	add_child(vm)
	_assert_true(vm.box_pool._is_boxed_dialog(0x12), "route: 0x12 boxed")
	_assert_true(vm.box_pool._is_boxed_dialog(0x11), "route: 0x11 boxed")
	_assert_true(vm.box_pool._is_boxed_dialog(0x91), "route: 0x91 boxed")
	_assert_true(vm.box_pool._is_boxed_dialog(0x92), "route: 0x92 boxed")
	_assert_true(vm.box_pool._is_boxed_dialog(0x70), "route: 0x70 boxed (remap)")
	_assert_eq(vm.box_pool._is_boxed_dialog(0x09), false, "route: 0x09 overlay, not boxed")
	_assert_eq(vm.box_pool._is_boxed_dialog(0x21), false, "route: 0x21 Check, not boxed")
	vm.queue_free()


func _test_boxed_show_and_gate() -> void:
	var pair := _make_vm_and_box()
	var vm = pair[0]
	var box = pair[1]
	var pc := _first_boxed_pc(vm)
	_assert_true(pc >= 0, "boxed: found a boxed Display Message in chunk")

	vm._op_display_message(vm._insts[pc])
	_assert_true(box.is_active(), "boxed: box active after Display Message")
	_assert_true(box.is_typing(), "boxed: box typing after show")
	_assert_true(vm._pending_dialog_gate, "boxed: advance gate armed")

	# The very next opcode is Wait For Instruction (the gate).
	vm._op_wait_for_instruction(vm._insts[pc + 1])
	_assert_eq(vm._pending_dialog_gate, false, "gate: WFI consumed the pending flag")
	_assert_true(vm._dialog_gate_active, "gate: dispatch halted on advance")
	vm.queue_free()
	box.queue_free()


func _test_advance_two_press() -> void:
	var pair := _make_vm_and_box()
	var vm = pair[0]
	var box = pair[1]
	var pc := _first_boxed_pc(vm)
	vm._op_display_message(vm._insts[pc])
	vm._op_wait_for_instruction(vm._insts[pc + 1])
	_assert_true(box.is_typing(), "advance: typing before first press")
	# A press while the box is still GROWING is ignored — the ROM's open tween
	# blocks the event fiber, so there is nobody to read the press.
	_assert_true(box.is_opening(), "advance: box still opening right after show")
	vm._advance_dialog()
	_assert_true(box.is_typing(), "advance: a press during the open is IGNORED")
	_assert_true(vm._dialog_gate_active, "advance: gate still held after the ignored press")
	_settle_open(vm)
	# First press finishes the typewriter.
	vm._advance_dialog()
	_assert_eq(box.is_typing(), false, "advance: 1st press finishes typing")
	_assert_true(vm._dialog_gate_active, "advance: gate still held after 1st press")
	# Second press releases the gate.
	vm._advance_dialog()
	_assert_eq(vm._dialog_gate_active, false, "advance: 2nd press releases gate")
	vm.queue_free()
	box.queue_free()


## The advance key as an EVENT — the wiring nothing else in this file touches.
##
## Every other arm here calls `vm._advance_dialog()` directly, one level BELOW even the input
## callback, so the whole path from a press to a released gate was unasserted. It used to be a
## poll: `_process` asked `Input.is_action_just_pressed` once a frame, which is the last entry
## on `check_focus_anchor.py`'s POLL list and the one thing Focus structurally cannot gate —
## the switch stops Godot CALLING a non-holder, it cannot stop one ASKING.
##
## Driven with `get_viewport().push_input` and deliberately NOT `Input.parse_input_event`:
## `parse_input_event` writes the `Input` singleton on its way through, so a poll would satisfy
## this arm too and it would assert nothing about delivery. `push_input` goes straight to the
## viewport and leaves the singleton alone. Measured, not assumed.
func _test_advance_is_delivered_not_polled() -> void:
	var pair := _make_vm_and_box()
	var vm = pair[0]
	var box = pair[1]
	var pc := _first_boxed_pc(vm)
	vm._op_display_message(vm._insts[pc])
	vm._op_wait_for_instruction(vm._insts[pc + 1])
	_assert_true(box.is_typing(), "delivered: typing before the first press")
	_settle_open(vm)  # the open tween blocks the press (see _settle_open)
	_push_action(&"ui_accept")
	_assert_eq(box.is_typing(), false, "delivered: a pushed press finishes the typewriter")
	_assert_true(vm._dialog_gate_active, "delivered: ...and the gate is still held")
	_push_action(&"ui_accept")
	_assert_eq(vm._dialog_gate_active, false, "delivered: a second press releases the gate")
	vm.queue_free()
	box.queue_free()


## Synchronous: `push_input` runs the whole chain before it returns, so the assertion on the
## next line already sees the result. Never by calling `_unhandled_input` directly — a test
## that calls the callback cannot tell "ignored" from "never delivered".
func _push_action(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	get_viewport().push_input(ev)


func _test_change_dialog_close() -> void:
	var pair := _make_vm_and_box()
	var vm = pair[0]
	var box = pair[1]
	# Find a 0x9X box (closable) and its following Change Dialog 0xFFFF.
	var pc := -1
	for i in range(vm._insts.size() - 3):
		if str(vm._insts[i].get("name", "")) != "Display Message":
			continue
		var dlg := 0
		for p in vm._insts[i].get("params", []):
			if str(p["name"]) == "Dialog":
				dlg = int(p["value"])
		if (dlg & 0x80) != 0 and vm.box_pool._is_boxed_dialog(dlg):
			pc = i
			break
	_assert_true(pc >= 0, "close: found a 0x9X closable box")
	vm._op_display_message(vm._insts[pc])
	# Walk forward to the Change Dialog.
	var cd := -1
	for i in range(pc + 1, mini(pc + 6, vm._insts.size())):
		if str(vm._insts[i].get("name", "")) == "Change Dialog":
			cd = i
			break
	_assert_true(cd >= 0, "close: Change Dialog follows the box")
	vm._op_change_dialog(vm._insts[cd])
	# Change Dialog 0xFFFF closes the box via the ROM SHRINK tween (Part B), not
	# an instant hide — it stays active until the shrink (curve 4, 4 entries held
	# 2 vsyncs each = 8 frames) completes. The gate, however, clears immediately.
	_assert_eq(vm._pending_dialog_gate, false, "close: gate cleared immediately")
	_assert_true(box.is_tweening(), "close: box shrinking after Change Dialog 0xFFFF")
	box.advance_tween_frames(8)
	_assert_eq(box.is_active(), false, "close: box closed after shrink completes")
	vm.queue_free()
	box.queue_free()


func _test_auto_advance_dwell() -> void:
	var pair := _make_vm_and_box()
	var vm = pair[0]
	var box = pair[1]
	vm.dialog_auto_advance = true
	vm.dialog_auto_advance_ticks = 5
	var pc := _first_boxed_pc(vm)
	vm._op_display_message(vm._insts[pc])
	vm._op_wait_for_instruction(vm._insts[pc + 1])
	_assert_true(vm._dialog_gate_active, "auto: gate active")
	_assert_eq(box.is_typing(), false, "auto: text revealed immediately")
	# Dwell counts down; gate releases on the 5th tick.
	for i in range(4):
		vm._tick_dialog_gate()
	_assert_true(vm._dialog_gate_active, "auto: still held at 4 ticks")
	vm._tick_dialog_gate()
	_assert_eq(vm._dialog_gate_active, false, "auto: released after dwell")
	vm.queue_free()
	box.queue_free()


# A name + 3 dialogue lines → 2 pages (decode §1.2). The Orbonne box.
func _gafgarion_tokens() -> Array:
	return [
		{"type": "color", "palette": 8},
		{"type": "text", "value": "Gafgarion"},
		{"type": "newline"},
		{"type": "color", "palette": 0},
		{"type": "text", "value": "Is this going to be alright,"},
		{"type": "newline"},
		{"type": "text", "value": "Agrias?"},
		{"type": "newline"},
		{"type": "text", "value": "This is an urgent issue for us."},
	]


# The interactive O/Circle ladder over a 2-page box: press finishes typing →
# press turns the page → press finishes typing → press releases the gate.
func _test_pagination_advance_press_ladder() -> void:
	var pair := _make_vm_and_box()
	var vm = pair[0]
	var box = pair[1]
	box.show_dialog(_gafgarion_tokens(), 0x12, -1, 0.0)
	vm.box_pool._foreground_slot = 1  # box is pool slot 1 (the wired box)
	vm._dialog_gate_active = true

	_assert_true(box.is_typing(), "ladder: page 1 typing")
	box.advance_tween_frames(64)  # the open tween blocks the press (see _settle_open)
	vm._advance_dialog()  # press 1: finish page 1
	_assert_eq(box.is_typing(), false, "ladder: press 1 finishes page 1")
	_assert_eq(box.current_page(), 0, "ladder: still page 1 after finish")
	_assert_true(vm._dialog_gate_active, "ladder: gate held after finishing page 1")

	vm._advance_dialog()  # press 2: turn to page 2
	_assert_eq(box.current_page(), 1, "ladder: press 2 turns to page 2")
	_assert_true(vm._dialog_gate_active, "ladder: gate still held on page 2")

	box.finish_typing()   # reveal page 2 (skip its type-out)
	vm._advance_dialog()  # press 3: last page → release
	_assert_eq(vm._dialog_gate_active, false, "ladder: final press releases gate")
	vm.queue_free()
	box.queue_free()


# Auto-advance dwell turns each page on its own dwell and releases only after the
# last page (mirrors the interactive ladder for headless play-through).
func _test_pagination_auto_advance_pages() -> void:
	var pair := _make_vm_and_box()
	var vm = pair[0]
	var box = pair[1]
	vm.dialog_auto_advance = true
	vm.dialog_auto_advance_ticks = 3
	box.show_dialog(_gafgarion_tokens(), 0x12, -1, 0.0)
	vm.box_pool._foreground_slot = 1  # box is pool slot 1 (the wired box)
	vm._pending_dialog_gate = true
	vm._consume_dialog_gate()
	_assert_true(vm._dialog_gate_active, "auto-page: gate active")
	_assert_eq(box.current_page(), 0, "auto-page: on page 1")

	for i in range(3):
		vm._tick_dialog_gate()
	_assert_eq(box.current_page(), 1, "auto-page: dwell turned to page 2")
	_assert_true(vm._dialog_gate_active, "auto-page: gate held for page 2")

	for i in range(3):
		vm._tick_dialog_gate()
	_assert_eq(vm._dialog_gate_active, false, "auto-page: released after last page")
	vm.queue_free()
	box.queue_free()


func _test_message_index_and_swap() -> void:
	var pair := _make_vm_and_box()
	var vm = pair[0]
	var box = pair[1]
	# Index built from the 18 baked Display Message records (ids 1..19, no 11).
	_assert_true(vm.box_pool._message_tokens.size() >= 18, "index: message tokens indexed")
	_assert_true(vm.box_pool._message_tokens.has(3), "index: msg #3 present")

	# Show a box, then a synthetic Change Dialog swapping to msg #3.
	var pc := _first_boxed_pc(vm)
	vm._op_display_message(vm._insts[pc])
	box.finish_typing()
	var swap_inst := {
		"name": "Change Dialog", "opcode": 0x51,
		"params": [
			{"name": "Target", "value": 1},
			{"name": "Message", "value": 3},
			{"name": "Portrait Column", "value": 0},
			{"name": "Portrait Palette", "value": 0},
		],
	}
	vm._op_change_dialog(swap_inst)
	_assert_true(box.is_active(), "swap: box still active after swap")
	_assert_true(box.is_typing(), "swap: typewriter restarted for swap")
	_assert_true(vm._pending_dialog_gate, "swap: gate re-armed")
	vm.queue_free()
	box.queue_free()


# {51} Change Dialog carries a Portrait Column. When a {50} row is active and the
# swap's column is valid (byte in [1,8]), the in-place swap must re-resolve the
# LIVE box's EVTFACE portrait to (row, col = byte-1) — not just the body text. 63
# vanilla {51} swaps (scn14 msg18 col1, scn158, scn384…) carry a non-zero column
# the old text-only swap silently dropped, leaving a stale face.
# PORTRAIT_ROW_OPCODE_50_EVTFACE.md §2.5; issue #165.
func _test_change_dialog_swap_updates_portrait() -> void:
	var pair := _make_vm_and_box()
	var vm = pair[0]
	var box = pair[1]
	# Latch a {50} row (Row 0) exactly as the VM would at scn14 instr 34.
	vm._portrait_row = 0
	var face0 := EvtFaceCatalog.face_texture(0, 0)  # Balbanes (col 0)
	var face1 := EvtFaceCatalog.face_texture(0, 1)  # Teta (col 1)
	_assert_true(face0 != null and face1 != null and face0 != face1,
		"swap-portrait: EVTFACE (0,0) and (0,1) are distinct faces")
	# Open a mode-0x10 box showing Balbanes (col 0) — the {10} that precedes the swap.
	box.show_dialog(_gafgarion_tokens(), 0x92, -1, 0.0, 3, face0)
	vm.box_pool._foreground_slot = 1
	_assert_true(box._portrait.get_evtface_texture() == face0,
		"swap-portrait: box opens showing EVTFACE(0,0) Balbanes")
	# {51} swaps to baked msg #3 with Portrait Column = 2 → col 1 (Teta).
	var swap_inst := {
		"name": "Change Dialog", "opcode": 0x51,
		"params": [
			{"name": "Target", "value": 1},
			{"name": "Message", "value": 3},
			{"name": "Portrait Column", "value": 2},
			{"name": "Portrait Palette", "value": 0},
		],
	}
	vm._op_change_dialog(swap_inst)
	_assert_true(box.is_active(), "swap-portrait: box still active after swap")
	_assert_true(box._portrait.get_evtface_texture() == face1,
		"swap-portrait: {51} Portrait Column 2 re-resolves the face to EVTFACE(0,1) Teta")
	vm.queue_free()
	box.queue_free()


# A {51} swap carrying Portrait Column 0 (298 of 361 vanilla real-swaps, e.g.
# scn8 msgs 6-12) must LEAVE the current face untouched — not clear it. col-0 means
# "no EVTFACE override on this swap", so the box keeps the portrait the opening
# {10} gave it (the same speaker keeps talking). Confirmed scope decision: strict
# "col-0 => clear" is deferred pending an on-screen A/B. Issue #165.
func _test_change_dialog_swap_col0_keeps_portrait() -> void:
	var pair := _make_vm_and_box()
	var vm = pair[0]
	var box = pair[1]
	vm._portrait_row = 0
	var face0 := EvtFaceCatalog.face_texture(0, 0)  # Balbanes (col 0)
	box.show_dialog(_gafgarion_tokens(), 0x92, -1, 0.0, 3, face0)
	vm.box_pool._foreground_slot = 1
	# {51} swaps text to msg #3 but carries Portrait Column 0 (no override).
	var swap_inst := {
		"name": "Change Dialog", "opcode": 0x51,
		"params": [
			{"name": "Target", "value": 1},
			{"name": "Message", "value": 3},
			{"name": "Portrait Column", "value": 0},
			{"name": "Portrait Palette", "value": 0},
		],
	}
	vm._op_change_dialog(swap_inst)
	_assert_true(box.is_active(), "swap-col0: box still active after swap")
	_assert_true(box._portrait.get_evtface_texture() == face0,
		"swap-col0: Portrait Column 0 leaves the current face (Balbanes) untouched")
	vm.queue_free()
	box.queue_free()


# A minimal stand-in for a spawned scenario Unit: the box pool reads `body_sprite_id`
# (portrait fallback) and `template_folder` (the resolved unique folder the spawn seam
# put there, #223) off the speaker registered in `units_by_id`.
class FakeSpeaker extends Node:
	var body_sprite_id: int = 1
	var template_folder: String = ""


# ADR-0072 #223: a unique speaking in-battle renders from its OWNED portrait.tga.
# The box pool reads `template_folder` off the speaker (the scenario spawn seam
# resolved it, mirroring #205's roster/info-window seam — no resolver call here) and
# threads it into show_dialog. A generic speaker (no folder) stays on the flat sheet.
func _test_boxed_portrait_fronts_speaker_template_folder() -> void:
	var pair := _make_vm_and_box()
	var vm = pair[0]
	var box = pair[1]
	var uid := 0x40

	# Unique speaker carrying its resolved folder → box fronts the sheet with it.
	var unique := FakeSpeaker.new()
	unique.template_folder = "res://assets/characters/templates/ramza_3/"
	add_child(unique)
	vm.units_by_id = {uid: unique}
	# portrait_row 0 → no EVTFACE override → the speaker unit-SPR/template path.
	vm.box_pool._show_dialog_box(_gafgarion_tokens(), 0x12, uid, 0)
	_assert_true(box._portrait._template_mode,
		"pool: unique speaker's OWNED portrait fronts the flat sheet")

	# Generic speaker (no folder) keeps the flat sprite-sheet portrait (load-bearing).
	var generic := FakeSpeaker.new()
	add_child(generic)
	vm.units_by_id = {uid: generic}
	vm.box_pool._show_dialog_box(_gafgarion_tokens(), 0x12, uid, 0)
	_assert_eq(box._portrait._template_mode, false,
		"pool: generic speaker stays on the flat sprite sheet")

	unique.queue_free()
	generic.queue_free()
	vm.queue_free()
	box.queue_free()


# Wire the VM with a 3-box pool (slot 1 = dialogue_box, slots 2-3 = extras) so a
# scene that stacks concurrent boxes has slots to open into.
func _make_vm_and_pool() -> Array:
	var vm = ScenarioVMClass.new()
	add_child(vm)
	var boxes: Array = []
	for i in range(3):
		var box = DialogueBoxClass.new()
		add_child(box)
		box.throttle = 2  # factor 1 → 1 frame/glyph
		boxes.append(box)
	vm.box_pool.dialogue_box = boxes[0]
	vm.box_pool.extra_dialogue_boxes = [boxes[1], boxes[2]]
	var ok: bool = vm.load_chunk_json(CHUNK_JSON_PATH)
	_assert_true(ok, "pool: load_chunk_json")
	return [vm, boxes]


# Locate the 147-154 concurrent-box window: Display Message, WFI(1), Display
# Message, WFI(1), Change Dialog(0xFFFF), Wait, Change Dialog(0xFFFF). Returns the
# pc of the first Display Message, or -1.
func _find_concurrent_window(vm) -> int:
	for i in range(vm._insts.size() - 6):
		if str(vm._insts[i].get("name", "")) != "Display Message":
			continue
		if str(vm._insts[i + 1].get("name", "")) != "Wait For Instruction":
			continue
		if str(vm._insts[i + 2].get("name", "")) != "Display Message":
			continue
		if str(vm._insts[i + 3].get("name", "")) != "Wait For Instruction":
			continue
		if str(vm._insts[i + 4].get("name", "")) != "Change Dialog":
			continue
		# Confirm the two closers target box 1 then box 2 (open order).
		if _param(vm._insts[i + 4], "Message") != 65535:
			continue
		return i
	return -1


func _param(inst: Dictionary, key: String):
	for p in inst.get("params", []):
		if str(p["name"]) == key:
			return int(p["value"])
	return null


# Release the foreground box's advance gate by pressing through its pages.
## Settle the foreground box's OPEN tween. The ROM's open tween is fiber-BLOCKING
## (`jal dialog_box_open_close_tween` @0x80131344 returns only after the whole
## curve), so a player press cannot reach a box that is still growing — and
## `ScenarioVM._advance_dialog` now models that. These arms drive the VM
## synchronously, with no vsyncs passing, so they have to spend the open frames
## themselves before a press means anything.
func _settle_open(vm) -> void:
	var box = vm.box_pool._foreground_box()
	if box == null or not box.has_method("is_opening"):
		return
	# Longest open curve is 11 entries; a generous bound beats a magic number.
	box.advance_tween_frames(64)


func _drain_advance(vm) -> void:
	for _i in range(8):
		if not vm._dialog_gate_active:
			return
		_settle_open(vm)
		vm._advance_dialog()


# The Orbonne opening (chunk idx 147-154): two boxes coexist (top Gafgarion /
# bottom Agrias), Task=1 holds each until advanced, then `Change Dialog Target=1`
# closes box 1 only and `Target=2` closes box 2. Model pinned in
# concurrent_dialogue_boxes_decode.md (static bytecode + live PCSX capture).
func _test_concurrent_boxes_147_154() -> void:
	var pair := _make_vm_and_pool()
	var vm = pair[0]
	var boxes: Array = pair[1]
	var base := _find_concurrent_window(vm)
	_assert_true(base >= 0, "concurrent: found the two-box window in chunk")
	if base < 0:
		vm.queue_free()
		for b in boxes:
			b.queue_free()
		return

	# --- Box 1 opens (idx 147) and gates on WFI Task=1 (idx 148). ---
	vm._op_display_message(vm._insts[base])
	var box1 = vm.box_pool._box_at(1)
	_assert_true(box1 != null and box1.is_active(), "concurrent: box 1 open after msg")
	_assert_eq(vm.box_pool._foreground_slot, 1, "concurrent: box 1 is foreground")
	vm._op_wait_for_instruction(vm._insts[base + 1])
	# (b) Task=1 holds until the player advances the foreground box.
	_assert_true(vm._dialog_gate_active, "concurrent: Task=1 holds box 1")
	_drain_advance(vm)
	_assert_eq(vm._dialog_gate_active, false, "concurrent: box 1 advanced releases gate")

	# --- Box 2 opens (idx 149) on TOP; box 1 stays visible (kind-0x33). ---
	vm._op_display_message(vm._insts[base + 2])
	var box2 = vm.box_pool._box_at(2)
	# (a) Both boxes visible concurrently.
	_assert_true(box1.is_active(), "concurrent: box 1 STILL visible after box 2 opens")
	_assert_true(box2 != null and box2.is_active(), "concurrent: box 2 open")
	_assert_true(box1 != box2, "concurrent: boxes are distinct pool slots")
	_assert_eq(vm.box_pool._foreground_slot, 2, "concurrent: box 2 is now foreground")
	vm._op_wait_for_instruction(vm._insts[base + 3])
	_assert_true(vm._dialog_gate_active, "concurrent: Task=1 holds box 2")
	_drain_advance(vm)

	# --- Change Dialog Target=1 closes box 1 ONLY (idx 151). ---
	_assert_eq(_param(vm._insts[base + 4], "Target"), 1, "concurrent: 1st closer Target=1")
	vm._op_change_dialog(vm._insts[base + 4])
	box1.advance_tween_frames(8)
	_assert_eq(box1.is_active(), false, "concurrent: Target=1 closed box 1")
	_assert_true(box2.is_active(), "concurrent: box 2 still up after box 1 closes")

	# --- Change Dialog Target=2 closes box 2 (idx 153). ---
	var closer2 := base + 6  # base+5 is the Wait Time=4 between the two closers
	_assert_eq(str(vm._insts[closer2].get("name", "")), "Change Dialog", "concurrent: 2nd closer present")
	_assert_eq(_param(vm._insts[closer2], "Target"), 2, "concurrent: 2nd closer Target=2")
	vm._op_change_dialog(vm._insts[closer2])
	box2.advance_tween_frames(8)
	_assert_eq(box2.is_active(), false, "concurrent: Target=2 closed box 2")

	vm.queue_free()
	for b in boxes:
		b.queue_free()


# The FIRST Orbonne event (chunk idx 55-83) is ONE box at a time, UNLIKE the
# 147-154 two-box beat. msg2 (Dialog=0x12 — bit 0x80 CLEAR) closes the instant
# it is advanced; msg3 (Dialog=0x91 — bit 0x80 SET, top) then opens ALONE, with
# NO bottom box. The Dialog bit 0x80 is the persist flag: PSX's Display Message
# handler stashes (Dialog & 0x80) per box (0x80130998) and the dialog fiber tears
# the slot down (LAB_80131a80) when it is clear. Ground truth (side-by-side PSX
# capture): research/.../dialogue_box_visual_parity_investigation.md (crux STOP 2).
func _test_first_event_non_persist_closes_on_advance() -> void:
	var pair := _make_vm_and_pool()
	var vm = pair[0]
	var boxes: Array = pair[1]
	# msg2 = first boxed Display Message with Dialog bit 0x80 CLEAR (non-persist).
	var pc := -1
	for i in range(vm._insts.size()):
		if str(vm._insts[i].get("name", "")) != "Display Message":
			continue
		var dlg := int(_param(vm._insts[i], "Dialog"))
		if vm.box_pool._is_boxed_dialog(dlg & 0xFF) and (dlg & 0x80) == 0:
			pc = i
			break
	_assert_true(pc >= 0, "first-event: found a non-persist (bit7=0) boxed message")
	if pc < 0:
		vm.queue_free()
		for b in boxes:
			b.queue_free()
		return
	var dlg2 := int(_param(vm._insts[pc], "Dialog"))
	var slot2 = vm.box_pool._slot_for_dialog(dlg2 & 0xFF)
	vm._op_display_message(vm._insts[pc])
	var msg2box = vm.box_pool._box_at(slot2)
	_assert_true(msg2box != null and msg2box.is_active(), "first-event: msg2 open (bottom)")
	# Next op is WFI Task=1; the player advances past it.
	vm._op_wait_for_instruction(vm._insts[pc + 1])
	_drain_advance(vm)
	msg2box.advance_tween_frames(16)
	_assert_eq(msg2box.is_active(), false, "first-event: msg2 (bit7=0) CLOSES on advance")
	_assert_eq(vm.box_pool._foreground_slot, 0, "first-event: no foreground box after msg2 closes")
	# msg3 = next boxed Display Message (top, bit7=1).
	var pc3 := -1
	for i in range(pc + 2, vm._insts.size()):
		if str(vm._insts[i].get("name", "")) != "Display Message":
			continue
		if vm.box_pool._is_boxed_dialog(int(_param(vm._insts[i], "Dialog")) & 0xFF):
			pc3 = i
			break
	_assert_true(pc3 >= 0, "first-event: found msg3 (top)")
	vm._op_display_message(vm._insts[pc3])
	var active := 0
	for s in [1, 2, 3]:
		var b = vm.box_pool._box_at(s)
		if b != null and b.is_active():
			active += 1
	_assert_eq(active, 1, "first-event CRUX: exactly 1 box up when msg3 (top) opens")
	_assert_eq(msg2box.is_active(), false, "first-event CRUX: msg2 (bottom) stays closed")
	vm.queue_free()
	for b in boxes:
		b.queue_free()
