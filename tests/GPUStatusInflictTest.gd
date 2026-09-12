extends GPUCombatTestBase

## GPU Status Inflict Tracer (#98)
##
## End-to-end witness for the [code]inflict_mode == "all"[/code] path: parser
## emits [code]inflict_statuses[/code] -> StatusEncoder translates at the
## encode boundary -> GPU buffer carries the mask -> compute shader ORs the
## bits onto the target's [code]STATUS_FLAGS_LO[/code] on a confirmed hit.
##
## Two slices in one battle, both team-0-attacker -> team-1-target. Each
## verifies THREE waypoints to lock in the contract end-to-end:
##   1. bit gets set on the target after the cast/swing lands,
##   2. HP starts ticking down after the bit is set,
##   3. (spell slice) the unit eventually dies from poison damage.
##
##   Spell: Priest casts Poison (ability 28, formula 10, AOE radius 1). On
##          landing the target should gain STATUS_POISON, then take 25 HP
##          (max_hp/POISON_HP_DIVISOR) every 30 ticks via stage_damage
##          Phase 1.5, and die. Routes through stage_damage Phase 1 AOE ->
##          apply_break_effect (formula 10).
##
##   Weapon: Attacker equips Blind Knife (item 3, inflict Darkness mode=all).
##          A basic attack should inflict STATUS_DARKNESS on the target.
##          Routes through stage_compute.apply_attack_damage -> the new
##          U_WEAPON_INFLICT_MASK/MODE writer. (Darkness reduces hit% on
##          attacks the target makes; no per-tick damage component, so we
##          only verify the bit lands -- no death witness for this slice.)
##
## Both witnesses are load-bearing for the integration contract -- ability
## inflict goes through the ability buffer; weapon inflict goes through the
## per-unit weapon fields. Once green, every other "all"-mode single-status
## ability lights up on the same code path.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


const ABILITY_POISON = 28
const ITEM_BLIND_KNIFE = 3
# Must mirror combat_common.glslinc; the GPUPoisonTest pins the same values.
const POISON_TICK_INTERVAL = 30
const POISON_HP_DIVISOR = 8

var _spell_target_poisoned: bool = false
var _weapon_target_darkened: bool = false
var _spell_target_dead: bool = false
var _spell_target_max_hp: int = 0
var _spell_target_hp_at_first_poison: int = -1
var _spell_target_min_hp_seen: int = -1
var _results_printed: bool = false


func get_test_name() -> String:
	return "GPU Status Inflict Test (Poison + Blind Knife)"


func get_team0_unit_configs() -> Array:
	# Priest: high MA / Faith, casts Poison repeatedly on nearest enemy.
	# AttackerBK: equips Blind Knife (id 3); basic-attack inflicts Darkness.
	return [
		{
			"name": "Priest",
			"pos_x": 0, "pos_z": 0,
			"hp": 200, "max_hp": 200,
			"pa": 5, "ma": 12, "wp": 1,
			"brave": 50, "faith": 90,
			"mp": 99, "max_mp": 99,
			"speed": 100, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x02,
		},
		{
			"name": "AttackerBK",
			"pos_x": 0, "pos_z": 4,
			"hp": 200, "max_hp": 200,
			"pa": 10, "ma": 5, "wp": 4,
			"brave": 50, "faith": 50,
			"mp": 0, "max_mp": 0,
			"speed": 100, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": ITEM_BLIND_KNIFE,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x02,
		},
	]


func get_team1_unit_configs() -> Array:
	# Inert targets. Faith 70 so Poison's Faith-scaled hit% lands reliably
	# (per #103: hit = (MA+X) * Faith_c/100 * Faith_t/100). Priest has Faith
	# 90, formula_x 160 — Faith_t 70 gives ~63% hit per cast, plenty for the
	# test's 1500-tick window with cooldown 300. WeaponTarget keeps high HP
	# since we don't need a kill on it.
	var base := {
		"pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 70,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x05,
	}
	return [
		# 200 HP / 25-per-tick poison -> 8 poison ticks * 30 = 240 damage
		# ticks once the bit is set; the test budget below allows for cast
		# windup + 8 ticks + slack.
		_merge(base, {"name": "SpellTarget",  "pos_x": 2, "pos_z": 0,
			"hp": 200, "max_hp": 200}),
		_merge(base, {"name": "WeaponTarget", "pos_x": 1, "pos_z": 4,
			"hp": 999, "max_hp": 999}),
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	# Priest -> casts Poison on nearest enemy (SpellTarget).
	# AttackerBK -> basic attack the nearest enemy (WeaponTarget).
	# Team-1 units have no gambits -- they stand still.
	if unit_idx == 0:
		return [make_spell_gambit(ABILITY_POISON)]
	if unit_idx == 1:
		return [make_attack_gambit()]
	return []


func _ready() -> void:
	# Cast windup (ct=3 -> ~90 ticks plus spell anim) + 8 poison ticks at
	# 30 ticks each + slack. ~600 ticks is the floor; use 1500 to absorb
	# variable cast animation timing.
	max_ticks = 1500
	super._ready()


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 4:
		return

	if _spell_target_max_hp == 0:
		_spell_target_max_hp = int(states[2].get("max_hp", 0))

	var poison_bit := 1 << StatusRegistry.bit(&"poison")
	var dark_bit := 1 << StatusRegistry.bit(&"darkness")
	var spell_flags_lo = int(states[2].get("status_flags_lo", 0))
	var weapon_flags_lo = int(states[3].get("status_flags_lo", 0))
	var spell_hp = int(states[2].get("hp", 0))

	if (spell_flags_lo & poison_bit) != 0:
		if not _spell_target_poisoned:
			_spell_target_poisoned = true
			_spell_target_hp_at_first_poison = spell_hp
		if _spell_target_min_hp_seen < 0 or spell_hp < _spell_target_min_hp_seen:
			_spell_target_min_hp_seen = spell_hp
		if spell_hp <= 0:
			_spell_target_dead = true
	if (weapon_flags_lo & dark_bit) != 0:
		_weapon_target_darkened = true

	# Quit only after the spell slice has played out (bit set + ticks ran +
	# target died), the weapon slice has its bit, or we hit the test ceiling.
	var spell_done = _spell_target_poisoned and _spell_target_dead
	if (spell_done and _weapon_target_darkened) or current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var poison_bit := 1 << StatusRegistry.bit(&"poison")
	var dark_bit := 1 << StatusRegistry.bit(&"darkness")
	var spell_flags_lo = int(states[2].get("status_flags_lo", 0))
	var weapon_flags_lo = int(states[3].get("status_flags_lo", 0))
	var spell_hp_now = int(states[2].get("hp", 0))
	var damage_taken = _spell_target_max_hp - spell_hp_now if _spell_target_max_hp > 0 else 0
	var expected_tick_dmg = _spell_target_max_hp / POISON_HP_DIVISOR

	print("\n=== STATUS INFLICT TEST RESULTS ===")
	print("  SpellTarget  status_flags_lo = 0x%08X (poison bit %s)" % [
		spell_flags_lo,
		"SET" if (spell_flags_lo & poison_bit) != 0 else "missing"])
	print("  SpellTarget  HP %d/%d (took %d damage, expected %d per poison tick)" % [
		spell_hp_now, _spell_target_max_hp, damage_taken, expected_tick_dmg])
	print("  SpellTarget  death: %s" % ("YES" if _spell_target_dead else "no"))
	print("  WeaponTarget status_flags_lo = 0x%08X (darkness bit %s)" % [
		weapon_flags_lo,
		"SET" if (weapon_flags_lo & dark_bit) != 0 else "missing"])

	# Poison ticks happen only AFTER the bit is set, so the damage we count
	# is HP-at-first-poison minus current-HP (or initial max if the unit is
	# already dead).
	var ticked_damage = 0
	if _spell_target_hp_at_first_poison >= 0:
		ticked_damage = _spell_target_hp_at_first_poison - max(spell_hp_now, 0)

	var spell_bit_ok = _spell_target_poisoned
	var spell_dmg_ok = ticked_damage >= expected_tick_dmg
	var spell_death_ok = _spell_target_dead
	var weapon_ok = _weapon_target_darkened

	if spell_bit_ok and spell_dmg_ok and spell_death_ok and weapon_ok:
		print("\n[PASS] Poison spell inflict + tick damage + death; Blind Knife inflict OK")
	else:
		var why: Array = []
		if not spell_bit_ok:   why.append("SpellTarget never gained POISON bit")
		if not spell_dmg_ok:   why.append("post-poison damage %d < expected per-tick %d" % [ticked_damage, expected_tick_dmg])
		if not spell_death_ok: why.append("SpellTarget did not die from poison")
		if not weapon_ok:      why.append("WeaponTarget never gained DARKNESS bit")
		print("\n[FAIL] %s" % ", ".join(why))
	print("====================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)


static func _merge(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var result = base.duplicate()
	for key in overrides:
		result[key] = overrides[key]
	return result
