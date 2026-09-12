@tool
extends Node3D
## Contract test for the deepened UIListModalWindow.
##
## Drives each picker subclass through the new typed-row contract without
## needing UI input: builds rows, opens via _open_with_rows, dispatches a pick
## by emitting the scroll list's item_selected signal, and asserts the picker's
## typed signal fires with the expected typed row.


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	await get_tree().process_frame
	await get_tree().process_frame

	var ok := 0
	var fail := 0

	for r in [
		await _test_job_popup(),
		await _test_passive_popup(),
		await _test_action_popup(),
		await _test_equipment_popup(),
	]:
		if r:
			ok += 1
		else:
			fail += 1

	print("\n=== PickerContractTest: %d passed, %d failed ===" % [ok, fail])
	get_tree().quit(0 if fail == 0 else 1)


func _test_job_popup() -> bool:
	var p := UIJobPopup.new()
	add_child(p)
	await get_tree().process_frame

	var rows := p.build_rows(false)
	if rows.is_empty():
		print("[FAIL] UIJobPopup.build_rows returned empty")
		p.queue_free()
		return false
	if not (rows[0] is UIJobPopup.JobRow):
		print("[FAIL] UIJobPopup rows are not JobRow")
		p.queue_free()
		return false

	var got_id := [""]
	p.job_selected.connect(func(id: String): got_id[0] = id)
	p.show_jobs(false)
	# Simulate keyboard-Enter on row 0 — same path mouse-click takes (both
	# funnel through _dispatch_pick).
	p._scroll_list.item_selected.emit(0, rows[0])

	var expected_id: String = (rows[0] as UIJobPopup.JobRow).id
	var ok_: bool = got_id[0] == expected_id
	print("[%s] UIJobPopup: expected id=%s got=%s" % ["PASS" if ok_ else "FAIL", expected_id, got_id[0]])
	p.queue_free()
	return ok_


func _test_passive_popup() -> bool:
	var p := UIPassiveAbilityPopup.new()
	add_child(p)
	await get_tree().process_frame

	var rows := p.build_rows("Reaction")
	if rows.is_empty():
		print("[FAIL] UIPassiveAbilityPopup.build_rows returned empty")
		p.queue_free()
		return false
	# Row 0 should be the "---" clear option (id=-1)
	var clear_row := rows[0] as UIPassiveAbilityPopup.PassiveRow
	if clear_row == null or clear_row.id != -1:
		print("[FAIL] UIPassiveAbilityPopup row 0 should be clear option id=-1, got id=%s" % (clear_row.id if clear_row else "null"))
		p.queue_free()
		return false

	var got := {"slot": "", "id": 0}
	p.passive_selected.connect(func(slot: String, id: int):
		got["slot"] = slot
		got["id"] = id)
	p.show_for_type("Reaction")
	p._scroll_list.item_selected.emit(0, rows[0])

	var ok_: bool = got["slot"] == "Reaction" and got["id"] == -1
	print("[%s] UIPassiveAbilityPopup: slot=%s id=%s" % ["PASS" if ok_ else "FAIL", got["slot"], got["id"]])
	p.queue_free()
	return ok_


func _test_action_popup() -> bool:
	var p := UIActionAbilityPopup.new()
	add_child(p)
	await get_tree().process_frame

	# build_rows(null) returns all Normal abilities for preview
	var rows := p.build_rows(null)
	if rows.is_empty():
		print("[FAIL] UIActionAbilityPopup.build_rows(null) returned empty")
		p.queue_free()
		return false
	if not (rows[0] is UIActionAbilityPopup.ActionRow):
		print("[FAIL] UIActionAbilityPopup rows are not ActionRow")
		p.queue_free()
		return false

	var got_id := [-999]
	p.action_selected.connect(func(id: int): got_id[0] = id)
	p.show_for_unit(null)
	p._scroll_list.item_selected.emit(0, rows[0])

	var expected_id: int = (rows[0] as UIActionAbilityPopup.ActionRow).id
	var ok_: bool = got_id[0] == expected_id
	print("[%s] UIActionAbilityPopup: expected id=%d got=%d" % ["PASS" if ok_ else "FAIL", expected_id, got_id[0]])
	p.queue_free()
	return ok_


func _test_equipment_popup() -> bool:
	var p := UIEquipmentPopup.new()
	add_child(p)
	await get_tree().process_frame

	var rows := p.build_rows(0, null)  # slot 0 = R.Hand (weapons)
	if rows.is_empty():
		print("[FAIL] UIEquipmentPopup.build_rows(0, null) returned empty")
		p.queue_free()
		return false
	var first := rows[0] as UIEquipmentPopup.EquipRow
	if first == null:
		print("[FAIL] UIEquipmentPopup rows are not EquipRow")
		p.queue_free()
		return false
	# stats should be pre-rendered as a non-empty string for weapons
	if first.stats.is_empty():
		print("[FAIL] UIEquipmentPopup weapon row stats unexpectedly empty (name=%s)" % first.name)
		p.queue_free()
		return false

	var got := {"slot": -1, "id": -1}
	p.item_equipped.connect(func(slot: int, id: int):
		got["slot"] = slot
		got["id"] = id)
	p.show_for_slot(0, null)
	p._scroll_list.item_selected.emit(0, rows[0])

	var ok_: bool = got["slot"] == 0 and got["id"] == first.id
	print("[%s] UIEquipmentPopup: slot=%d id=%d (expected slot=0 id=%d)" % [
		"PASS" if ok_ else "FAIL", got["slot"], got["id"], first.id
	])
	p.queue_free()
	return ok_
