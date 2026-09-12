extends GPUCombatTestBase

## GPU Arena Test (4v4)
##
## Full 4v4 combat arena exercising all ability types:
## - Melee (Knight with Broad Sword)
## - Ranged (Archer with Long Bow)
## - Spells (Black Mage with Fire)
## - Throw Stone (Squire)
## - Items (Chemist with Potion on wounded allies)
##
## Roster loaded from arena_roster.json for easy editing.

var _roster_data: Dictionary = {}


func _ready():
	# 4v4 with charge_time > 0 abilities (Fire) now runs through the cinematic
	# orchestrator (issue #53), which freezes every other unit while the
	# cinematic plays (~600 ticks for Fire). At ~20 casts per battle that
	# roughly doubles the resolution budget. 60000 ticks gives margin.
	max_ticks = 60000
	_load_roster()
	super._ready()


func _load_roster():
	var file = FileAccess.open("res://tests/arena_roster.json", FileAccess.READ)
	if not file:
		push_error("[GPUArenaTest] Failed to open arena_roster.json")
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error != OK:
		push_error("[GPUArenaTest] JSON parse error: %s" % json.get_error_message())
		return

	_roster_data = json.data


func get_test_name() -> String:
	return "GPU Arena Test (4v4)"


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

	var unit_config = configs[local_idx]
	return unit_config.get("gambits", [make_attack_gambit()])


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING:
		print("  -> %s moving toward target" % units[unit_idx].name)
	elif old_state == GPUConstants.LOGICAL_ACTIVITY_WALKING and new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		print("  -> %s in range, attacking!" % units[unit_idx].name)
	elif new_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
		print("  -> %s charging ability" % units[unit_idx].name)
	elif old_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING and new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		print("  -> %s cast complete!" % units[unit_idx].name)


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta < 0:
		print("  -> %s hit for %d! HP=%d" % [units[unit_idx].name, abs(delta), new_hp])
	elif delta > 0:
		print("  -> %s healed for %d! HP=%d" % [units[unit_idx].name, delta, new_hp])


func on_victory(winning_team: int):
	if winning_team >= 0:
		print("\n[PASS] Arena combat resolved - Team %d won" % winning_team)
	else:
		print("\n[FAIL] Arena combat ended in a draw")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
