extends GPUCombatTestBase

## GPU SEQ Movement Opcode Test
##
## Verifies that SEQ movement opcodes (MoveForward2/MoveBackward2) fire
## the move_offset_changed signal during melee attack animations.
## The standard ATTACKING animation (130/131 for TYPE1) contains these opcodes
## for the wind-up/lunge pattern.
##
## PASS: move_offset_changed fires at least once AND target takes damage.

var _move_offset_fired: bool = false
var _move_offset_connected: bool = false
var _damage_dealt: bool = false
var _done: bool = false


func get_test_name() -> String:
	return "GPU SEQ Movement Opcode Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Swordsman",
		"pos_x": 0, "pos_z": 0,
		"hp": 150, "max_hp": 150,
		"pa": 8, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19,  # Broad Sword
		"body_sprite_id": 0x02,
		"speed": 100
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Target",
		"pos_x": 1, "pos_z": 0,  # Adjacent
		"hp": 999, "max_hp": 999,
		"pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 0, "max_mp": 0,
		"move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x05,
		"speed": 1
	}]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_attack_gambit()]


func _ready():
	max_ticks = 2000
	super._ready()


func _process(delta):
	# Connect move_offset_changed once units are spawned (base _ready has awaits)
	if not _move_offset_connected and units.size() > 0:
		var attacker = units[0]
		if attacker.display.type1_playback:
			attacker.display.type1_playback.move_offset_changed.connect(_on_test_move_offset)
			print("  [SEQ] Connected move_offset_changed on %s" % attacker.name)
			_move_offset_connected = true
	super._process(delta)


func _on_test_move_offset(offset: Vector2):
	if not _move_offset_fired:
		print("  [SEQ] First move_offset_changed: offset=(%d, %d)" % [offset.x, offset.y])
	_move_offset_fired = true
	_check_test_pass()


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta: int):
	if _done:
		return
	if unit_idx == 1 and delta < 0:
		print("  [SEQ] Target hit for %d (HP: %d -> %d)" % [abs(delta), old_hp, new_hp])
		_damage_dealt = true
		_check_test_pass()
	elif delta < 0:
		var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
		print("  [SEQ] %s hit for %d (HP: %d -> %d)" % [unit_name, abs(delta), old_hp, new_hp])


func _check_test_pass():
	if _done:
		return
	if _move_offset_fired and _damage_dealt:
		_done = true
		print("\n[PASS] SEQ movement opcodes: move_offset_changed fired AND damage dealt")
		_rlog.log_entry("TEST_PASS", {"move_offset_fired": true, "damage_dealt": true})
		_rlog.output()
		victory_achieved = true
		combat_active = false
		get_tree().quit()


func on_victory(winning_team: int):
	if _done:
		return
	var reasons: Array = []
	if not _move_offset_fired:
		reasons.append("move_offset_changed never fired")
	if not _damage_dealt:
		reasons.append("no damage dealt to target")
	print("\n[FAIL] SEQ movement opcodes: %s (team %d won)" % [", ".join(reasons), winning_team])
	_rlog.log_entry("TEST_FAIL", {"move_offset_fired": _move_offset_fired, "damage_dealt": _damage_dealt})
	_rlog.output()
	get_tree().quit()
