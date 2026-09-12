extends Node3D
## DetailScene ability slot-focus (slice 5b-1) — the ability mirror of the §15.25
## Eqp slot focus. In ability_only mode a glove cursor walks the ability slot rows,
## but the PRIMARY skillset slot (row 0) is job-fixed and unselectable (ABILITY_
## PICKER.md §1), so focus starts on the secondary row and navigation cycles only
## the 4 editable slots [1,2,3,4]. The equip slot-focus (row 0..4) is unchanged.
##
## Run: <GODOT> --path . --quit-after 8 res://tests/DetailAbilitySlotFocusTest.tscn

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

const _VIEW := {
	"move": 4, "jump": 3, "speed": 8, "r_power": 9, "r_wev": 5, "l_power": 0, "l_wev": 0,
	"r_at": 7, "c_ev": 12, "s_ev": 0, "a_ev": 0, "l_at": 0,
}

var _failed := false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


func _ready() -> void:
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	await get_tree().process_frame
	d.set_stats_view(_VIEW)
	d.enter_ability_mode()
	await get_tree().process_frame

	# Enter ability slot-focus: starts on the secondary row (1), NOT the fixed primary (0).
	d.enter_ability_slot_focus()
	_expect(d.is_slot_focused(), "enter_ability_slot_focus did not focus")
	_expect(d.slot_row() == 1, "ability focus starts on secondary(1), got %d (primary must be skipped)" % d.slot_row())
	_expect(d.slot_cursor_mounted(), "ability slot glove not mounted")

	# Down cycles the 4 editable slots only: 1 -> 2 -> 3 -> 4 -> 1 (primary 0 skipped).
	d.slot_cursor_down(); _expect(d.slot_row() == 2, "down 1->2, got %d" % d.slot_row())
	d.slot_cursor_down(); _expect(d.slot_row() == 3, "down 2->3, got %d" % d.slot_row())
	d.slot_cursor_down(); _expect(d.slot_row() == 4, "down 3->4, got %d" % d.slot_row())
	d.slot_cursor_down(); _expect(d.slot_row() == 1, "down 4->1 wrap (skip primary), got %d" % d.slot_row())
	# Up from the secondary row wraps to the last editable slot (movement), never primary.
	d.slot_cursor_up(); _expect(d.slot_row() == 4, "up 1->4 wrap (skip primary), got %d" % d.slot_row())

	d.exit_slot_focus()
	_expect(not d.is_slot_focused(), "exit_slot_focus did not clear focus")

	# Guard: enter_ability_slot_focus is a no-op unless the screen is in ability mode.
	var d2: DetailScene = DetailScene.new()
	d2.autoplay_open = false
	add_child(d2)
	await get_tree().process_frame
	d2.set_stats_view(_VIEW)
	d2.enter_ability_slot_focus()
	_expect(not d2.is_slot_focused(), "ability slot-focus must no-op when not in ability mode")

	_finish()


func _finish() -> void:
	if _failed:
		print("[FAIL] DetailAbilitySlotFocusTest")
	else:
		print("[PASS] DetailAbilitySlotFocusTest: ability slot-focus skips primary, cycles editable slots")
	get_tree().quit()
