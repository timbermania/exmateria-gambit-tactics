extends Node3D

## PARITY PROBE (not a pass/fail test): drive the FIRST boxed-dialogue event
## (chunk idx 55-83) through the real ScenarioVM + a 3-box pool, exactly the way
## a player would — Display Message opens a box, Wait For Instruction Task=1 halts
## (a STOP), the player advances, Change Dialog closes a box — and print the
## box-pool state at each Task=1 stop. Compared side-by-side against the PSX
## capture in research/.../dialogue_box_visual_parity_investigation.md.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/ScenarioFirstEventParityProbe.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const DialogueBoxClass = preload("res://src/ui3/assemblies/DialogueBox.gd")
const CHUNK_JSON_PATH := "res://assets/scenarios/scenario_1_chunk.json"

const EVENT_START := 55
const EVENT_END := 84  # exclusive-ish; stop when we hit the next event's Task!=1

var _slot_msg := {}      # slot -> last message id shown there
var _stop := 0


func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a parity PROBE — its own header says not a pass/fail test; it prints a trace to compare against the PSX")
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
	if not ok:
		print("[PROBE] FAILED to load chunk")
		get_tree().quit(1)
		return

	print("\n===== GODOT first-event parity probe (idx %d-%d) =====" % [EVENT_START, EVENT_END])
	var i := EVENT_START
	while i < EVENT_END and i < vm._insts.size():
		var inst = vm._insts[i]
		var name := str(inst.get("name", ""))
		match name:
			"Display Message":
				var dlg := int(_param(vm, inst, "Dialog"))
				var msg := int(_param(vm, inst, "Message"))
				var unit := int(_param(vm, inst, "Unit"))
				if vm.box_pool._is_boxed_dialog(dlg & 0xFF):
					vm._op_display_message(inst)
					# `: int`, not `:=`. `vm` is untyped here, so the parser cannot see
					# `_slot_for_dialog`'s `-> int` through `vm.box_pool` and refuses to
					# infer. Annotating is the fix; the inference form is a PARSE error,
					# and it does NOT present as one — trunk recorded it as a HUNG scene,
					# this line measured it as rc=0 printing nothing, i.e. "no verdict".
					# Two symptoms, one cause, and neither says "parse error" out loud.
					var slot: int = vm.box_pool._slot_for_dialog(dlg & 0xFF)
					_slot_msg[slot] = {"msg": msg, "unit": unit, "dlg": dlg}
					print("  idx%d OPEN msg%d unit0x%02X dlg0x%02X -> slot%d (%s)" % [
						i, msg, unit, dlg, slot, _pos(slot)])
			"Wait For Instruction":
				var task := int(_param(vm, inst, "Task"))
				vm._op_wait_for_instruction(inst)
				if task == 1:
					if vm._dialog_gate_active:
						_report_stop(vm, i)
						_drain_advance(vm)
						# Frames elapse during the following Wait ops; let any
						# close/shrink tween (a non-persist box closing on advance)
						# complete so the next stop reflects the settled screen.
						for b in boxes:
							if b.has_method("advance_tween_frames"):
								b.advance_tween_frames(16)
					# else: Task=1 that passes (nothing awaiting) — no stop
				elif task != 1 and i > EVENT_START + 3:
					# reached the next-event barrier (Task=8/4/...) — event over
					print("  idx%d WFI Task=%d (event tail/next-event barrier) — stop stepping" % [i, task])
					break
			"Change Dialog":
				var target := int(_param(vm, inst, "Target"))
				var m := int(_param(vm, inst, "Message"))
				vm._op_change_dialog(inst)
				# advance tweens so the close/shrink completes deterministically
				for b in boxes:
					if b.has_method("advance_tween_frames"):
						b.advance_tween_frames(16)
				var live := _active_slots(vm)
				print("  idx%d CHANGE DIALOG Target=%d msg=%d -> active slots now %s" % [
					i, target, m, str(live)])
			_:
				pass
		i += 1

	print("===== end probe =====\n")
	get_tree().quit(0)


func _report_stop(vm, idx: int) -> void:
	_stop += 1
	var live := _active_slots(vm)
	var desc := []
	for slot in live:
		var m = _slot_msg.get(slot, {})
		desc.append("slot%d=%s msg%d(unit0x%02X)%s" % [
			slot, _pos(slot), int(m.get("msg", -1)), int(m.get("unit", 0)),
			" [FG]" if slot == vm.box_pool._foreground_slot else ""])
	print("  >> STOP %d @ idx%d: %d box(es): %s" % [_stop, idx, live.size(), "; ".join(desc)])


func _active_slots(vm) -> Array:
	var out := []
	for slot in [1, 2, 3]:
		var b = vm.box_pool._box_at(slot)
		if b != null and b.is_active():
			out.append(slot)
	return out


func _pos(slot: int) -> String:
	return "top" if slot == 1 else ("bottom" if slot == 2 else "slot%d" % slot)


func _drain_advance(vm) -> void:
	for _i in range(8):
		if not vm._dialog_gate_active:
			return
		# The ROM's open tween blocks the event fiber, so a press cannot reach a
		# box that is still growing (ScenarioVM._advance_dialog models it). This
		# probe steps the VM synchronously, so spend the open frames here.
		var box = vm.box_pool._foreground_box()
		if box != null and box.has_method("is_opening"):
			box.advance_tween_frames(64)
		vm._advance_dialog()


func _param(vm, inst: Dictionary, key: String):
	for p in inst.get("params", []):
		if str(p["name"]) == key:
			return int(p["value"])
	return 0
