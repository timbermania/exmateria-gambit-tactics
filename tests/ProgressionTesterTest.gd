extends GPUCombatTestBase

## Progression System Test
##
## Exercises all UnitProgression methods programmatically:
## leveling, job changes, JP/XP, ability learning, equipment,
## passive ability slots, weapon properties, equipment elements/statuses,
## and job unlock tree queries.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const LearnableAbility = ExMateriaAlmanac.LearnableAbility


var _roster_data: Dictionary = {}
var _step_count: int = 0
var _failed: bool = false
var _fail_reason: String = ""
var _test_started: bool = false


func _ready():
	max_ticks = 999999
	auto_start = false
	_load_roster()
	super._ready()


func _load_roster():
	var file = FileAccess.open("res://tests/arena_roster.json", FileAccess.READ)
	if not file:
		push_error("[ProgressionTesterTest] Failed to open arena_roster.json")
		return
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error != OK:
		push_error("[ProgressionTesterTest] JSON parse error: %s" % json.get_error_message())
		return
	_roster_data = json.data


func get_test_name() -> String:
	return "Progression Tester Test"


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
	var expected_team0 = _roster_data.get("team0", []).size()
	if not _test_started and combat_ui and team0_units.size() >= expected_team0 and expected_team0 > 0:
		_test_started = true
		call_deferred("_run_test_sequence")


func _step(description: String) -> void:
	_step_count += 1
	print("  [%d] %s" % [_step_count, description])


func _fail(reason: String) -> void:
	if not _failed:
		_failed = true
		_fail_reason = reason
		print("\n[FAIL] %s (at step %d)" % [reason, _step_count])


func _wait_frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _get_unit_progression(unit: Node):
	if not unit:
		return null
	if "unit_stats" in unit and unit.unit_stats:
		if unit.unit_stats.has_method("get_progression"):
			return unit.unit_stats.get_progression()
	return null


func _run_test_sequence() -> void:
	print("\n--- Starting Progression Tester Test ---")
	print("Friendly units: %d" % team0_units.size())

	if team0_units.is_empty():
		_fail("No friendly units available")
		get_tree().quit()
		return

	# Use first friendly unit for all progression tests
	var unit = team0_units[0]
	var progression = _get_unit_progression(unit)
	if not progression:
		_fail("Unit has no progression")
		get_tree().quit()
		return

	print("\n=== Testing: %s (Job: %s, Level: %d) ===" % [
		unit.name, progression.get_current_job_name(), progression.level])

	await _test_leveling(progression)
	await _test_experience(progression)
	await _test_job_management(progression)
	await _test_jp_management(progression)
	await _test_ability_learning(progression)
	await _test_ability_learning_from_job(progression)
	await _test_equipment(progression)
	await _test_weapon_properties(progression)
	await _test_equipment_elements_statuses(progression)
	await _test_passive_abilities(progression)
	await _test_sub_job(progression)
	await _test_job_unlock_tree(progression)
	await _test_stat_queries(progression)

	# Final summary
	print("\n--- Progression Tester Test Complete ---")
	print("Steps completed: %d" % _step_count)

	if _failed:
		print("\n[FAIL] %s" % _fail_reason)
	else:
		print("\n[PASS] All %d progression steps completed successfully" % _step_count)

	await _wait_frames(5)
	get_tree().quit()


func _test_leveling(progression) -> void:
	_step("level_up()")
	var old_level = progression.level
	progression.level_up()
	await _wait_frames(1)
	if progression.level != old_level + 1:
		_fail("level_up did not increment level: expected %d, got %d" % [old_level + 1, progression.level])
		return
	_step("level is now %d (was %d)" % [progression.level, old_level])


func _test_experience(progression) -> void:
	_step("add_experience(50) - should NOT level up")
	var old_level = progression.level
	var leveled = progression.add_experience(50)
	await _wait_frames(1)
	if leveled:
		_step("WARNING: add_experience(50) leveled up unexpectedly")
	else:
		_step("add_experience(50) returned false (no level up) - correct")

	_step("add_experience(100) - should level up")
	old_level = progression.level
	leveled = progression.add_experience(100)
	await _wait_frames(1)
	if leveled:
		_step("add_experience(100) leveled up to %d - correct" % progression.level)
	else:
		_step("WARNING: add_experience(100) did not level up (may depend on accumulated XP)")


func _test_job_management(progression) -> void:
	var original_job = progression.current_job_id
	_step("current job: %s (%s)" % [original_job, progression.get_current_job_name()])

	# Change to a different job
	var target_job = "4b"  # Chemist
	if original_job == "4b":
		target_job = "4c"  # Knight
	_step("change_job('%s')" % target_job)
	var success = progression.change_job(target_job)
	await _wait_frames(1)
	if not success:
		_step("WARNING: change_job returned false")
	_step("job is now: %s (%s)" % [progression.current_job_id, progression.get_current_job_name()])

	# Change back
	_step("change_job('%s') - restoring original" % original_job)
	progression.change_job(original_job)
	await _wait_frames(1)
	_step("job restored to: %s (%s)" % [progression.current_job_id, progression.get_current_job_name()])


func _test_jp_management(progression) -> void:
	_step("add_jp(500)")
	var old_jp = progression.get_job_jp()
	progression.add_jp(500)
	await _wait_frames(1)
	var new_jp = progression.get_job_jp()
	_step("JP: %d -> %d (added 500)" % [old_jp, new_jp])

	# Test add_jp_to_all_jobs
	_step("add_jp_to_all_jobs(['4a','4b','4c'], 200)")
	var jobs_to_add: Array = ["4a", "4b", "4c"]
	progression.add_jp_to_all_jobs(jobs_to_add, 200)
	await _wait_frames(1)
	_step("JP for 4a: %d, 4b: %d, 4c: %d" % [
		progression.get_job_jp("4a"),
		progression.get_job_jp("4b"),
		progression.get_job_jp("4c")])

	# Test get_job_level
	_step("get_job_level(): %d" % progression.get_job_level())
	_step("get_job_level('4a'): %d" % progression.get_job_level("4a"))


func _test_ability_learning(progression) -> void:
	# Grant enough JP to learn something
	_step("granting 9999 JP for ability learning")
	progression.add_jp(9999)
	await _wait_frames(1)

	# Get learnable abilities
	_step("get_learnable_abilities()")
	var learnable = progression.get_learnable_abilities()
	_step("found %d learnable abilities" % learnable.size())

	if learnable.is_empty():
		_step("WARNING: no learnable abilities for current job")
		return

	# Find first unlearned ability
	var to_learn = null
	for ability in learnable:
		if not ability.get("learned", false):
			to_learn = ability
			break

	if to_learn:
		var ability_id = to_learn.get("id", -1)
		var ability_name = to_learn.get("name", "???")
		_step("learn_ability(%d) - '%s' (cost: %d JP)" % [
			ability_id, ability_name, to_learn.get("jp_cost", 0)])
		var success = progression.learn_ability(ability_id)
		await _wait_frames(1)
		_step("learn_ability returned: %s" % str(success))

		_step("has_learned_ability(%d): %s" % [ability_id, str(progression.has_learned_ability(ability_id))])
	else:
		_step("all abilities already learned for current job")

	# Check learned abilities list
	var learned = progression.get_learned_abilities()
	_step("get_learned_abilities(): %d total" % learned.size())


func _test_ability_learning_from_job(progression) -> void:
	# Grant JP to chemist job and learn from it
	var job_id = "4b"  # Chemist
	_step("add_jp_to_all_jobs(['%s'], 9999) for cross-job learning" % job_id)
	progression.add_jp_to_all_jobs([job_id], 9999)
	await _wait_frames(1)

	# Get learnable abilities for chemist
	if not AbilityDatabase:
		_step("WARNING: AbilityDatabase not available")
		return

	var chemist_abilities := AbilityDatabase.get_learnable_abilities_for_job(job_id)
	if chemist_abilities.is_empty():
		_step("WARNING: no learnable abilities for job %s" % job_id)
		return

	# Find first unlearned one
	var to_learn: LearnableAbility = null
	for ability in chemist_abilities:
		if ability.id >= 0 and not progression.has_learned_ability(ability.id):
			to_learn = ability
			break

	if to_learn:
		_step("learn_ability_from_job(%d, '%s')" % [to_learn.id, job_id])
		var success = progression.learn_ability_from_job(to_learn.id, job_id)
		await _wait_frames(1)
		_step("learn_ability_from_job returned: %s" % str(success))
	else:
		_step("all chemist abilities already learned")


func _test_equipment(progression) -> void:
	if not ItemDatabase:
		_step("WARNING: ItemDatabase not available - skipping equipment tests")
		return

	# Test RIGHT_HAND (weapons)
	var weapons = ItemDatabase.get_weapons()
	if not weapons.is_empty():
		var item = weapons[0]
		var item_id = item.get("id", -1)
		var item_name = item.get("name", "???")
		_step("can_equip_item(RIGHT_HAND, %d/'%s'): %s" % [
			item_id, item_name, str(progression.can_equip_item(0, item_id))])
		_step("equip_item(RIGHT_HAND, %d/'%s')" % [item_id, item_name])
		progression.equip_item(0, item_id)
		await _wait_frames(1)
		_step("get_equipped_item(RIGHT_HAND): %d" % progression.get_equipped_item(0))
	else:
		_step("no weapons available - skipping RIGHT_HAND")

	# Test LEFT_HAND (shields)
	var shields = ItemDatabase.get_shields()
	if not shields.is_empty():
		var item = shields[0]
		var item_id = item.get("id", -1)
		var item_name = item.get("name", "???")
		_step("can_equip_item(LEFT_HAND, %d/'%s'): %s" % [
			item_id, item_name, str(progression.can_equip_item(1, item_id))])
		_step("equip_item(LEFT_HAND, %d/'%s')" % [item_id, item_name])
		progression.equip_item(1, item_id)
		await _wait_frames(1)
		_step("get_equipped_item(LEFT_HAND): %d" % progression.get_equipped_item(1))
	else:
		_step("no shields available - skipping LEFT_HAND")

	# Test ACCESSORY
	var accessories = ItemDatabase.get_accessories()
	if not accessories.is_empty():
		var item = accessories[0]
		var item_id = item.get("id", -1)
		var item_name = item.get("name", "???")
		_step("can_equip_item(ACCESSORY, %d/'%s'): %s" % [
			item_id, item_name, str(progression.can_equip_item(4, item_id))])
		_step("equip_item(ACCESSORY, %d/'%s')" % [item_id, item_name])
		progression.equip_item(4, item_id)
		await _wait_frames(1)
		_step("get_equipped_item(ACCESSORY): %d" % progression.get_equipped_item(4))
	else:
		_step("no accessories available - skipping ACCESSORY")

	# Test armor slots - need to filter head/body
	var all_armor = ItemDatabase.get_armor()

	# Find a head armor
	for armor in all_armor:
		var armor_id = armor.get("id", -1)
		if ItemDatabase.is_head_armor(armor_id):
			_step("equip_item(HEAD, %d/'%s')" % [armor_id, armor.get("name", "???")])
			progression.equip_item(2, armor_id)  # HEAD = 2
			await _wait_frames(1)
			break

	# Find a body armor
	for armor in all_armor:
		var armor_id = armor.get("id", -1)
		if ItemDatabase.is_body_armor(armor_id):
			_step("equip_item(BODY, %d/'%s')" % [armor_id, armor.get("name", "???")])
			progression.equip_item(3, armor_id)  # BODY = 3
			await _wait_frames(1)
			break

	# Test unequip
	_step("unequip_item(ACCESSORY)")
	var old_item = progression.unequip_item(4)  # ACCESSORY = 4
	await _wait_frames(1)
	_step("unequipped item_id: %d" % old_item)

	# Test equipment stat bonuses
	_step("get_equipment_stat_bonuses()")
	var bonuses = progression.get_equipment_stat_bonuses()
	_step("equipment bonuses: %s" % str(bonuses))


func _test_weapon_properties(progression) -> void:
	# Ensure we have a weapon equipped
	if not ItemDatabase:
		_step("WARNING: ItemDatabase not available - skipping weapon tests")
		return

	var weapons = ItemDatabase.get_weapons()
	if weapons.is_empty():
		_step("WARNING: no weapons available")
		return

	# Equip first weapon if not already equipped
	if progression.get_equipped_item(0) < 0:
		var first_weapon = weapons[0]
		progression.equip_item(0, first_weapon.get("id", -1))
		await _wait_frames(1)

	_step("get_weapon_power(): %d" % progression.get_weapon_power())
	_step("get_weapon_range(): %d" % progression.get_weapon_range())
	_step("get_weapon_evade(): %d" % progression.get_weapon_evade())
	_step("get_weapon_formula(): %d" % progression.get_weapon_formula())

	var flags = progression.get_weapon_flags()
	_step("get_weapon_flags(): %s" % str(flags))

	_step("get_physical_evade(): %d" % progression.get_physical_evade())
	_step("get_magic_evade(): %d" % progression.get_magic_evade())


func _test_equipment_elements_statuses(progression) -> void:
	_step("get_equipment_elements()")
	var elements = progression.get_equipment_elements()
	_step("equipment elements: %s" % str(elements))

	_step("get_equipment_statuses()")
	var statuses = progression.get_equipment_statuses()
	_step("equipment statuses: %s" % str(statuses))


func _test_passive_abilities(progression) -> void:
	if not AbilityDatabase:
		_step("WARNING: AbilityDatabase not available - skipping passive tests")
		return

	# Grant JP to current job for learning passives
	progression.add_jp(9999)
	await _wait_frames(1)

	# Try to learn and equip a Reaction ability
	var reactions := AbilityDatabase.get_views_by_type("Reaction")
	if not reactions.is_empty():
		var reaction := reactions[0]
		var rid := reaction.ability_id
		# Learn it first
		progression.learn_ability(rid)
		await _wait_frames(1)
		_step("set_equipped_reaction(%d/'%s')" % [rid, reaction.name])
		var success = progression.set_equipped_reaction(rid)
		_step("set_equipped_reaction returned: %s" % str(success))
		_step("get_equipped_reaction_name(): '%s'" % progression.get_equipped_reaction_name())

	# Try Support ability
	var supports := AbilityDatabase.get_views_by_type("Support")
	if not supports.is_empty():
		var support := supports[0]
		var sid := support.ability_id
		progression.learn_ability(sid)
		await _wait_frames(1)
		_step("set_equipped_support(%d/'%s')" % [sid, support.name])
		var success = progression.set_equipped_support(sid)
		_step("set_equipped_support returned: %s" % str(success))
		_step("get_equipped_support_name(): '%s'" % progression.get_equipped_support_name())

	# Try Movement ability
	var movements := AbilityDatabase.get_views_by_type("Movement")
	if not movements.is_empty():
		var movement := movements[0]
		var mid := movement.ability_id
		progression.learn_ability(mid)
		await _wait_frames(1)
		_step("set_equipped_movement(%d/'%s')" % [mid, movement.name])
		var success = progression.set_equipped_movement(mid)
		_step("set_equipped_movement returned: %s" % str(success))
		_step("get_equipped_movement_name(): '%s'" % progression.get_equipped_movement_name())

	# Unequip passives
	_step("set_equipped_reaction(-1) - unequip")
	progression.set_equipped_reaction(-1)
	_step("set_equipped_support(-1) - unequip")
	progression.set_equipped_support(-1)
	_step("set_equipped_movement(-1) - unequip")
	progression.set_equipped_movement(-1)
	await _wait_frames(1)


func _test_sub_job(progression) -> void:
	var target_sub = "4b"  # Chemist
	if progression.current_job_id == "4b":
		target_sub = "4c"  # Knight

	_step("set_sub_job('%s')" % target_sub)
	var success = progression.set_sub_job(target_sub)
	await _wait_frames(1)
	_step("set_sub_job returned: %s" % str(success))

	# Clear sub-job
	_step("set_sub_job('') - clear")
	progression.set_sub_job("")
	await _wait_frames(1)


func _test_job_unlock_tree(progression) -> void:
	_step("is_job_unlocked('4a'): %s" % str(progression.is_job_unlocked("4a")))  # Squire
	_step("is_job_unlocked('59'): %s" % str(progression.is_job_unlocked("59")))  # Ninja

	_step("get_unlocked_jobs()")
	var unlocked = progression.get_unlocked_jobs()
	_step("unlocked jobs: %d total" % unlocked.size())

	_step("get_locked_jobs()")
	var locked = progression.get_locked_jobs()
	_step("locked jobs: %d total" % locked.size())

	# Check prerequisites for a high-tier job
	_step("get_missing_prerequisites('59') - Ninja")
	var missing = progression.get_missing_prerequisites("59")
	if missing.is_empty():
		_step("Ninja is unlockable (no missing prerequisites)")
	else:
		_step("Ninja missing: %s" % str(missing))


func _test_stat_queries(progression) -> void:
	_step("get_effective_hp(): %d" % progression.get_effective_hp())
	_step("get_effective_mp(): %d" % progression.get_effective_mp())
	_step("get_effective_speed(): %d" % progression.get_effective_speed())
	_step("get_effective_pa(): %d" % progression.get_effective_pa())
	_step("get_effective_ma(): %d" % progression.get_effective_ma())
	_step("get_move(): %d" % progression.get_move())
	_step("get_jump(): %d" % progression.get_jump())
	_step("get_c_evade(): %d" % progression.get_c_evade())


# Override callbacks — we don't need GPU combat events
func on_state_changed(_unit_idx: int, _old_state: int, _new_state: int):
	pass

func on_hp_changed(_unit_idx: int, _old_hp: int, _new_hp: int, _delta: int):
	pass

func on_victory(_winning_team: int):
	pass
