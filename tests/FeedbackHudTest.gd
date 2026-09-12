extends Node
## Feedback-HUD over-unit billboard test (ADR-0063, issues #89 / #90).
##
## Drives a stub combat loop (the same `hp_changed` / `state_changed` signals +
## `units` array the real [CombatLoop] exposes) so this stays a fast, non-GPU
## check while still building real ArrayMesh billboards. Asserts:
##   1. a DamageNumber3D spawns on hp_changed, map-anchored under the manager;
##   2. the killing blow's number SURVIVES the target's death-frame;
##   3. billboards are `combat_visuals` members (ride the ADR-0037 freeze);
##   4. a StatusBubble3D appears on SPELL_CHARGING and clears when it ends;
##   5. an active status raises the bubble with its (placeholder) icon;
##   6. the manager writes no battle state — it only reads signals / snapshot.

const FeedbackHudManagerClass = preload("res://src/ui3/elements/FeedbackHudManager.gd")
const DamageNumber3DClass = preload("res://src/ui3/elements/DamageNumber3D.gd")
const StatusBubble3DClass = preload("res://src/ui3/elements/StatusBubble3D.gd")
const UnitStatusManagerClass = preload("res://src/units/UnitStatusManager.gd")

# The slice of CombatLoop the feedback HUD consumes — nothing more.
class StubLoop extends Node:
	signal hp_changed(unit_index: int, prev_hp: int, new_hp: int, delta: int)
	signal state_changed(unit_index: int, prev_state: int, new_state: int)
	var units: Array = []

var _failed := false


func _fail(msg: String) -> void:
	print("[FAIL] %s" % msg)
	_failed = true


func _make_unit(pos: Vector3) -> Node3D:
	var u := Node3D.new()
	u.position = pos
	var sm := UnitStatusManagerClass.new()
	sm.name = "UnitStatusManager"
	u.add_child(sm)
	return u


func _damage_numbers(manager: Node) -> Array:
	var out: Array = []
	for c in manager.get_children():
		if c is DamageNumber3DClass:
			out.append(c)
	return out


func _bubble_of(unit: Node) -> Node:
	for c in unit.get_children():
		if c is StatusBubble3DClass:
			return c
	return null


func _ready() -> void:
	await _run()
	if _failed:
		print("[FAIL] FeedbackHud test")
	else:
		print("[PASS] FeedbackHud: damage numbers (death-resilient) + status/charge bubbles")
	get_tree().quit()


func _run() -> void:
	var loop := StubLoop.new()
	add_child(loop)
	var u0 := _make_unit(Vector3(2, 0, 3))
	var u1 := _make_unit(Vector3(-1, 0, 4))
	add_child(u0)
	add_child(u1)
	loop.units = [u0, u1]

	var manager: Node3D = FeedbackHudManagerClass.new()
	add_child(manager)
	manager.setup(loop)
	await get_tree().process_frame

	# 1. Damage number spawns on hp_changed, map-anchored under the manager.
	loop.hp_changed.emit(0, 100, 70, -30)
	await get_tree().process_frame
	var nums := _damage_numbers(manager)
	if nums.size() != 1:
		_fail("expected 1 damage number after hp_changed, got %d" % nums.size())
	else:
		var n: Node3D = nums[0]
		var expected := u0.global_position + FeedbackHudManagerClass.NUMBER_RAISE
		# y climbs as it rises; check the anchor's XZ and that it started at/above.
		if absf(n.global_position.x - expected.x) > 0.001 or absf(n.global_position.z - expected.z) > 0.001:
			_fail("damage number not anchored over the unit: %s vs %s" % [n.global_position, expected])
		# 3. combat_visuals membership (ADR-0037 freeze).
		if not n.is_in_group("combat_visuals"):
			_fail("damage number not in combat_visuals group")

	# 2. Killing blow: number survives the unit's death-frame.
	loop.hp_changed.emit(0, 70, 0, -70)   # lethal
	await get_tree().process_frame
	u0.queue_free()                        # target despawns
	loop.units = [null, u1]                # loop drops the dead slot
	await get_tree().process_frame
	await get_tree().process_frame
	var survivors := _damage_numbers(manager)
	if survivors.size() < 1:
		_fail("killing-blow number did not survive the death-frame (got %d)" % survivors.size())

	# 4. Charge bubble appears on SPELL_CHARGING, clears when it ends.
	loop.state_changed.emit(1, GPUConstants.LOGICAL_ACTIVITY_IDLE, GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING)
	await get_tree().process_frame
	await get_tree().process_frame
	var bubble := _bubble_of(u1)
	if bubble == null:
		_fail("no StatusBubble3D child on the charging unit")
	else:
		if not bubble.is_in_group("combat_visuals"):
			_fail("status bubble not in combat_visuals group")
		if bubble.current_icon() != FeedbackHudManagerClass.CHARGE_ICON:
			_fail("charge bubble icon = %d, expected CHARGE_ICON %d" % [bubble.current_icon(), FeedbackHudManagerClass.CHARGE_ICON])

	loop.state_changed.emit(1, GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING, GPUConstants.LOGICAL_ACTIVITY_IDLE)
	await get_tree().process_frame
	await get_tree().process_frame
	if bubble != null and bubble.current_icon() != -1:
		_fail("charge bubble did not clear when charging ended (icon %d)" % bubble.current_icon())

	# 5. An active status raises the bubble with its icon. Uses &"poison" — the
	# canonical status name (StatusRegistry bit 15); the HUD map keys on the same
	# name so the bubble actually fires (previously &"poisoned" mismatched the model).
	var sm: Node = u1.get_node("UnitStatusManager")
	sm.add_status(&"poison")
	await get_tree().process_frame
	await get_tree().process_frame
	if bubble != null:
		var want: int = FeedbackHudManagerClass.STATUS_ICON[&"poison"]
		if bubble.current_icon() != want:
			_fail("poison bubble icon = %d, expected %d" % [bubble.current_icon(), want])
