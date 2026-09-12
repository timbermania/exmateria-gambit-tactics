extends GPUCombatTestBase

## GPU Dash — No Hit Cloud Test (slice 2, the regression guard)
##
## Dash (ability 147) deals damage but its animation does NOT carry the
## PostGenericAttack (0xDE) opcode, so — like FFT — it must spawn NO hit cloud.
## This is the fix's whole point: the cloud is gated on the attacker's 0xDE
## opcode, not on the damage event, so a damaging-but-non-strike ability produces
## no spurious cloud.
##
## The dash is NON-LETHAL (a killing blow suppresses HP_CHANGED, which would make
## the test pass vacuously). The target survives; once its dash damage lands we
## wait a settle window and assert zero hit clouds were observed at the
## `hit_cloud_hook` seam. Any cloud fails immediately.
##
## See docs/VFX_TRIGGER_ARCHITECTURE.md and the companion GPUMeleeHitCloudTest
## (the strike case, which asserts exactly one).

const ABILITY_DASH := 147
const SETTLE_TICKS := 90  # generous window for a PGA to (wrongly) fire after damage

var _hit_cloud_count: int = 0
var _dash_damage_tick: int = -1
var _done: bool = false


func get_test_name() -> String:
	return "GPU Dash No Hit Cloud Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Dasher",
		"pos_x": 2, "pos_z": 1,
		"hp": 200, "max_hp": 200,
		"pa": 8, "ma": 5, "wp": 5,
		"brave": 70, "faith": 50,
		"mp": 20, "max_mp": 20,
		"speed": 100,
		"move": 3, "jump": 3,
		"weapon_range": 1,
		"weapon_flags": 1,
		"weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x60,  # Male Squire (has the Dash anim)
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Target",
		"pos_x": 2, "pos_z": 2,  # adjacent — Dash hits without pathing
		"hp": 500, "max_hp": 500,  # survives the ~48-damage dash
		"pa": 5, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"mp": 20, "max_mp": 20,
		"speed": 1,
		"move": 3, "jump": 3,
		"weapon_range": 1,
		"weapon_flags": 1,
		"weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x05,
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	# Dasher uses Dash on the nearest enemy; Target waits.
	if unit_idx == 0:
		return [{
			"enabled": true,
			"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
			"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
			"action_type": GPUConstants.ACTION_ABILITY,
			"action_id": ABILITY_DASH,
			"action_target_type": GPUConstants.TARGET_THEM,
		}]
	return [{
		"enabled": true,
		"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
		"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
		"action_type": GPUConstants.ACTION_WAIT,
		"action_id": 0,
		"action_target_type": GPUConstants.TARGET_SELF,
	}]


## Seam override (ADR-0018): ANY hit cloud from a dash is the bug — fail loud.
func _spawn_hit_cloud(position: Vector3, impact_dir: Vector3, target: Node, ability_id: int):
	_hit_cloud_count += 1
	super(position, impact_dir, target, ability_id)
	if not _done:
		_done = true
		print("\n[FAIL] Dash spawned a hit cloud (count=%d) — it carries no 0xDE opcode" % _hit_cloud_count)
		get_tree().quit()


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta < 0 and unit_idx == 1:
		if _dash_damage_tick < 0:
			_dash_damage_tick = current_tick
			print("  -> Dash landed: Target hit for %d (HP=%d)" % [abs(delta), new_hp])


func _process(delta):
	super._process(delta)
	if _done or _dash_damage_tick < 0:
		return
	# Dash damage has landed; give any (erroneous) PGA time to fire, then assert 0.
	if current_tick - _dash_damage_tick >= SETTLE_TICKS:
		_done = true
		print("\n[PASS] Dash dealt damage but spawned no hit cloud (count=0)")
		get_tree().quit()


func on_victory(_winning_team: int):
	if not _done:
		_done = true
		# Target died before we could settle, or nobody acted — inconclusive.
		print("\n[FAIL] Dash test ended without a settled non-lethal dash (clouds=%d)" % _hit_cloud_count)
