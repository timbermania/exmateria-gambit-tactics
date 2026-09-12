extends Node3D
# test-kind: logic
# seeded-break: inverted FormationScene._unhandled_input's §15.5 branch so ui_accept with a selected unit emits `dismissed` instead of `unit_activated`; the ui_accept asserts red and the ui_cancel counter asserts cascade red (the seeded accept already bumped _dismissed_count to 1)

## FormationScene ○-press → detail activation guard (headful).
##
## The formation roster is a view-only overlay (#234 E) that yields on `dismissed`.
## Wiring the Status/detail screen (§15.5) splits confirm from cancel:
##   * Enter/○ on a roster unit → `unit_activated(character)` (host opens the detail
##     screen + plays the transition), and `selected_character()` names that unit;
##   * Backspace/✕ → `dismissed` (unchanged — the navigator still proceeds to deployment).
## Guards that split + the accessor so a regression can't collapse them back to one.

const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")
const AllTemplatesSeeder = ExMateriaCatalogue.AllTemplatesSeeder

var _activated = null
var _activated_count := 0
var _dismissed_count := 0
var _failed := false


func _ready() -> void:
	CharacterCatalog.reset_to_new_game()
	AllTemplatesSeeder.seed()
	var owned: Array = CharacterCatalog.owned_units()

	var form: FormationScene = FormationScene.new()
	form.name = "Formation"
	form.set_owned_characters(owned)
	add_child(form)
	await get_tree().process_frame
	await get_tree().process_frame

	form.unit_activated.connect(func(c): _activated = c; _activated_count += 1)
	form.dismissed.connect(func(): _dismissed_count += 1)

	# selected_character() names the unit under the cursor (cell 0,0 by default).
	var sel = form.selected_character()
	_expect(sel != null, "selected_character() is null on a seeded roster")

	# --- Enter/○ on a unit opens detail: unit_activated(selected), NOT dismissed ---
	form._unhandled_input(_action("ui_accept"))
	_expect(_activated_count == 1, "ui_accept did not emit unit_activated once (got %d)" % _activated_count)
	_expect(_activated == sel, "unit_activated carried the wrong unit (not selected_character())")
	_expect(_dismissed_count == 0, "ui_accept wrongly emitted dismissed (%d)" % _dismissed_count)

	# --- Backspace/✕ still dismisses (the #234 E contract is preserved) ----------
	form._unhandled_input(_action("ui_cancel"))
	_expect(_dismissed_count == 1, "ui_cancel did not emit dismissed once (got %d)" % _dismissed_count)
	_expect(_activated_count == 1, "ui_cancel wrongly emitted unit_activated (%d)" % _activated_count)

	if _failed:
		print("[FAIL] FormationDetailActivate test")
	else:
		print("[PASS] FormationDetailActivate: Enter→unit_activated(unit), Esc→dismissed (§15.5)")
	get_tree().quit()


## A pressed InputEventAction for `name` — drives _unhandled_input deterministically.
func _action(name: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
