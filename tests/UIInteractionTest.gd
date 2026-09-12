extends GPUCombatTestBase

## UI Interaction Test
##
## Exercises all UI popups, menus, and interactions programmatically.
## Uses roster-based units and drives UICombatManager's internal methods
## directly rather than simulating input events.
##
## Covers: unit selection, equipment popups (with item selection),
## ability popups (with job/passive selection), learn panel,
## gambit editor, and deselection for all friendly units.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase


var _roster_data: Dictionary = {}
var _step_count: int = 0
var _step_total: int = 0
var _failed: bool = false
var _fail_reason: String = ""
var _test_started: bool = false


func _ready():
	max_ticks = 999999  # No GPU timeout — this is a UI test
	auto_start = false  # Don't start combat
	_load_roster()
	super._ready()


func _load_roster():
	var file = FileAccess.open("res://tests/arena_roster.json", FileAccess.READ)
	if not file:
		push_error("[UIInteractionTest] Failed to open arena_roster.json")
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error != OK:
		push_error("[UIInteractionTest] JSON parse error: %s" % json.get_error_message())
		return

	_roster_data = json.data


func get_test_name() -> String:
	return "UI Interaction Test"


func get_team0_unit_configs() -> Array:
	return _roster_data.get("team0", [])


func get_team1_unit_configs() -> Array:
	return _roster_data.get("team1", [])


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	var team_key = "team0" if team == 0 else "team1"
	var configs = _roster_data.get(team_key, [])
	var team0_size = _roster_data.get("team0", []).size()
	var local_idx = unit_idx if team == 0 else unit_idx - team0_size
	if local_idx < 0 or local_idx >= configs.size():
		return [make_attack_gambit()]
	return configs[local_idx].get("gambits", [make_attack_gambit()])


func _process(delta):
	# Wait until all units are created (async _create_units adds them one at a time)
	var expected_team0 = _roster_data.get("team0", []).size()
	if not _test_started and combat_ui and team0_units.size() >= expected_team0 and expected_team0 > 0:
		_test_started = true
		call_deferred("_run_test_sequence")


func _step(description: String) -> void:
	_step_count += 1
	print("  [%d] %s" % [_step_count, description])


## Pick row `idx` out of a UIListModalWindow popup through PRODUCTION's own
## selection funnel — `_dispatch_pick` is what both a mouse click and a
## keyboard-Enter call, and it looks the typed row up out of the scroll list,
## hands it to the popup's `_on_picked`, and closes.
##
## This used to read a `_items_data` array of Dictionaries off the popup and
## re-emit its signal by hand. That property was retired when the popups moved
## to typed RefCounted rows (EquipRow / JobRow / PassiveRow) held by the scroll
## list, so the read threw — and a GDScript runtime error ABORTS THE ENCLOSING
## FUNCTION, so every step after the first popup silently never ran while the
## test still printed [PASS]. #465.
func _pick_row(popup: Node, idx: int, label: String) -> bool:
	var n: int = popup.get_row_count()
	if idx < 0 or idx >= n:
		_step("%s popup has no row %d (%d row(s)) - closing" % [label, idx, n])
		combat_ui.close_current_modal()
		return false
	var row: Variant = popup._scroll_list.get_item_data(idx)
	_step("selecting %s: %s (id=%s)" % [label, row.name, str(row.id)])
	popup._dispatch_pick(idx)   # emits the popup's own signal, then closes
	return true


func _fail(reason: String) -> void:
	if not _failed:
		_failed = true
		_fail_reason = reason
		print("\n[FAIL] %s (at step %d)" % [reason, _step_count])


func _wait_frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _run_test_sequence() -> void:
	print("\n--- Starting UI Interaction Test ---")
	print("Friendly units: %d" % team0_units.size())

	if team0_units.is_empty():
		_fail("No friendly units available")
		get_tree().quit()
		return

	# Exercise each friendly unit
	for unit_idx in range(team0_units.size()):
		if _failed:
			break
		var unit = team0_units[unit_idx]
		print("\n=== Unit %d: %s ===" % [unit_idx, unit.name])
		await _test_unit_interactions(unit)
		await _wait_frames(2)

	# Final summary
	print("\n--- UI Interaction Test Complete ---")
	print("Steps completed: %d" % _step_count)

	if _failed:
		print("\n[FAIL] %s" % _fail_reason)
	else:
		print("\n[PASS] All %d UI interaction steps completed successfully" % _step_count)

	await _wait_frames(5)
	get_tree().quit()


func _test_unit_interactions(unit: Node) -> void:
	# 1. Select unit
	_step("select_unit(%s)" % unit.name)
	combat_ui.select_unit(unit)
	await _wait_frames(2)

	if combat_ui.get_selected_unit() != unit:
		_fail("Unit selection failed for %s" % unit.name)
		return

	# 2. Equipment popups (slots 0-4)
	await _test_equipment_popups(unit)

	# 3. Ability popups (slots 0-4)
	await _test_ability_popups(unit)

	# 4. Learn panel
	await _test_learn_panel(unit)

	# 5. Gambit editor
	await _test_gambit_editor(unit)

	# 6. Clear selection
	_step("clear_selection()")
	combat_ui.clear_selection()
	await _wait_frames(2)

	if combat_ui.has_selection():
		_fail("Selection not cleared for %s" % unit.name)


func _test_equipment_popups(unit: Node) -> void:
	for slot in range(5):
		var slot_names = ["R.Hand", "L.Hand", "Head", "Body", "Accessory"]
		var slot_name = slot_names[slot] if slot < slot_names.size() else "Slot%d" % slot

		_step("show_equipment_popup(slot=%d/%s)" % [slot, slot_name])
		combat_ui._show_equipment_popup(slot)
		await _wait_frames(3)

		# Select first available item from popup
		if combat_ui._equipment_popup and combat_ui._equipment_popup.visible:
			_pick_row(combat_ui._equipment_popup, 0, "item for slot %s" % slot_name)
		else:
			_step("equipment_popup not visible (no items?) - skipping")

		await _wait_frames(2)


func _test_ability_popups(unit: Node) -> void:
	# Grant JP so the unit can learn passives for equipping
	var progression = _get_unit_progression(unit)
	if progression:
		progression.add_jp(9999)
		# Also grant JP to chemist for sub-job variety
		progression.add_jp_to_all_jobs(["4a", "4b", "4c", "4d", "4e"], 9999)
		await _wait_frames(1)

		# Learn some passive abilities so they can be equipped
		if AbilityDatabase:
			for type_name in ["Reaction", "Support", "Movement"]:
				var abilities := AbilityDatabase.get_views_by_type(type_name)
				if not abilities.is_empty():
					var aid := abilities[0].ability_id
					if aid >= 0:
						progression.learn_ability(aid)

	# Slot 0: Job - select a different job
	_step("show_ability_popup(slot=0/Job)")
	combat_ui._show_ability_popup(0)
	await _wait_frames(3)

	if combat_ui._job_popup and combat_ui._job_popup.visible:
		# Pick the second job (the first might be the current one).
		_pick_row(combat_ui._job_popup, 1, "job")
	else:
		_step("job_popup not visible - skipping")
	await _wait_frames(2)

	# Slot 1: Sub-Job - select a sub-job
	_step("show_ability_popup(slot=1/SubJob)")
	combat_ui._show_ability_popup(1)
	await _wait_frames(3)

	if combat_ui._job_popup and combat_ui._job_popup.visible:
		# Skip the first row ("---" clear option) and pick the second.
		_pick_row(combat_ui._job_popup, 1, "sub-job")
	else:
		_step("sub_job_popup not visible - skipping")
	await _wait_frames(2)

	# Slots 2-4: Reaction, Support, Movement (passive popups) - select an ability
	var passive_names = ["Reaction", "Support", "Movement"]
	for i in range(3):
		var slot = i + 2
		_step("show_ability_popup(slot=%d/%s)" % [slot, passive_names[i]])
		combat_ui._show_ability_popup(slot)
		await _wait_frames(3)

		if combat_ui._passive_popup and combat_ui._passive_popup.visible:
			# Skip "---" (index 0) and pick the first real ability.
			_pick_row(combat_ui._passive_popup, 1, passive_names[i])
		else:
			_step("passive_popup(%s) not visible - skipping" % passive_names[i])
		await _wait_frames(2)


func _test_learn_panel(unit: Node) -> void:
	_step("show_learn_panel()")
	combat_ui._show_learn_panel()
	await _wait_frames(3)

	if combat_ui._learn_panel and combat_ui._learn_panel.visible:
		_step("learn_panel visible")

		# Grant JP so learning is possible
		var progression = _get_unit_progression(unit)
		if progression:
			_step("granting JP for job %s" % progression.current_job_id)
			progression.add_jp(9999)
			await _wait_frames(2)

		_step("closing learn_panel")
		combat_ui.close_current_modal()
	else:
		_step("learn_panel not visible - skipping")

	await _wait_frames(2)


func _test_gambit_editor(unit: Node) -> void:
	# Ensure unit has a gambit list
	if not "gambit_list" in unit or not unit.gambit_list:
		_step("unit has no gambit_list - skipping gambit editor")
		return

	var gambit_count = mini(4, unit.gambit_list.size())
	for gambit_idx in range(gambit_count):
		_step("show_gambit_editor(index=%d)" % gambit_idx)
		combat_ui._show_gambit_editor(gambit_idx)
		await _wait_frames(3)

		if combat_ui._gambit_editor and combat_ui._gambit_editor.visible:
			_step("gambit_editor visible for index %d - closing" % gambit_idx)
			combat_ui.close_current_modal()
		else:
			_step("gambit_editor not visible for index %d - skipping" % gambit_idx)

		await _wait_frames(2)


func _get_unit_progression(unit: Node):
	if not unit:
		return null
	if "unit_stats" in unit and unit.unit_stats:
		if unit.unit_stats.has_method("get_progression"):
			return unit.unit_stats.get_progression()
	return null


# Override callbacks — we don't need GPU combat events
func on_state_changed(_unit_idx: int, _old_state: int, _new_state: int):
	pass


func on_hp_changed(_unit_idx: int, _old_hp: int, _new_hp: int, _delta: int):
	pass


func on_victory(_winning_team: int):
	pass
