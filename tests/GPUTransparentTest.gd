extends GPUCombatTestBase

## GPU Transparent Test
##
## Tests TRANSPARENT target-filter — status_system.md §2 "Target filter" row,
## hooked in stage_compute (target selection + outgoing-action consume) and
## stage_damage Phase 3 (AOE-reveal consume).
##
## One battle, 3 team-0 actors + 4 team-1 targets (fits 4v4 default). Three
## load-bearing assertions, spaced along the z axis so each scenario's
## nearest-enemy search resolves within its own row.
##
##   Row z=0/1 — TARGET-SELECTION FILTER
##     Attacker (team 0) at (1, 0) has make_attack_gambit(). TransparentNearby
##     (team 1, TRANSPARENT) at (1, 1) is adjacent, dist 1. Bait (team 1, no
##     TRANSPARENT) at (3, 0) is dist 2 — same NORTH-axis geometry as the
##     known-good GPUReraiseTest Attacker/Defender pair (1,0)-(2,0)-(3,0).
##     Without the filter, find_unit_by_criteria picks TransparentNearby
##     (closer). With the filter wired, Attacker walks (1,0)→(2,0)→swing
##     Bait at (3,0). Witness: Bait HP drops; TransparentNearby HP stays
##     full. TransparentNearby's tile sits outside any Fire-AOE radius from
##     AOECaster's possible targets so the filter check isn't muddled by
##     incidental AOE bleed.
##
##   Row z=4 — OUTGOING-ACTION CONSUME
##     TransparentSwinger (team 0, TRANSPARENT) at (1, 4) has its own
##     make_attack_gambit(). PunchingBag (team 1, no TRANSPARENT, hp=999)
##     at (2, 4) is adjacent. Witness: after TransparentSwinger commits
##     its first attack, status_flags_lo bit 23 clears (TRANSPARENT
##     consumed on outgoing-action commit).
##
##   Row z=4 (bleed) — AOE REVEAL
##     AOECaster (team 0) at (1, 7) has a Fire spell gambit (ID 16,
##     effect_area=1, range=4). AOECaster's filtered nearest enemy is
##     PunchingBag at (2, 4), dist 4 (exactly Fire's range — no
##     WALKING_TO_CAST detour needed). Fire AOE radius 1 around (2, 4)
##     reaches (3, 4) — where TransparentInAOE (team 1, TRANSPARENT) sits.
##     Witness: after the AOE lands, TransparentInAOE took non-zero HP loss
##     AND its TRANSPARENT bit cleared. This pins that the Phase 3 hook
##     fires on AOE-pending and not on the named-target path (which
##     can't reach a transparent unit per Row z=0).
##
## Status timers seeded for 600 ticks so they outlive the test window — any
## bit clear has to come from a consume hook, not natural decay. Verdict
## prints at tick 300 (max 600) — enough for Fire's 40-tick charge plus
## travel time even under suite-load slowdown.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


const ABILITY_FIRE = 16
const TRANSPARENT_TIMER_TICKS = 600
const VERDICT_TICK = 300

var _results_printed: bool = false
var _initial_unit_hp: Dictionary = {}


func get_test_name() -> String:
	return "GPU Transparent Test"


func get_team0_unit_configs() -> Array:
	var melee_actor = {
		"hp": 400, "max_hp": 400, "pa": 20, "ma": 5, "wp": 10,
		"brave": 50, "faith": 50, "mp": 50, "max_mp": 50,
		"speed": 100, "move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19, "c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x02,
	}
	var t_mask = (1 << StatusRegistry.bit(&"transparent"))
	var t_timer = {"bit": StatusRegistry.bit(&"transparent"), "ticks": TRANSPARENT_TIMER_TICKS}
	return [
		# 0 — Row z=0: filter-test driver. Adjacent to TransparentNearby at (2,0)
		#       — known-good geometry from GPUReraiseTest. Walks around the
		#       transparent unit to reach Bait at (3,0) when the filter is wired.
		_merge(melee_actor, {"name": "Attacker", "pos_x": 1, "pos_z": 0}),
		# 1 — Row z=4: TRANSPARENT swinger that consumes its bit on first attack.
		_merge(melee_actor, {
			"name": "TransparentSwinger", "pos_x": 1, "pos_z": 4,
			"hp": 999, "max_hp": 999,
			"status_flags_lo": t_mask, "status_timers": [t_timer]}),
		# 2 — Row z=7 (within Fire range of PunchingBag at z=4): AOE caster.
		_merge(melee_actor, {"name": "AOECaster", "pos_x": 1, "pos_z": 7,
			"pa": 1, "ma": 20, "wp": 1, "max_mp": 200, "mp": 200}),
	]


func get_team1_unit_configs() -> Array:
	var dummy = {
		"hp": 200, "max_hp": 200, "pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 50, "mp": 50, "max_mp": 50,
		"speed": 100, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x05,
	}
	var t_mask = (1 << StatusRegistry.bit(&"transparent"))
	var t_timer = {"bit": StatusRegistry.bit(&"transparent"), "ticks": TRANSPARENT_TIMER_TICKS}
	return [
		# 3 — Row z=0/1: TRANSPARENT, adjacent SOUTH of Attacker (dist 1).
		#       Wins find_unit_by_criteria absent the filter. Position (1,1)
		#       is outside every Fire-AOE blast from AOECaster's plausible
		#       targets, so AOE bleed can't muddle the filter assertion.
		_merge(dummy, {
			"name": "TransparentNearby", "pos_x": 1, "pos_z": 1,
			"status_flags_lo": t_mask, "status_timers": [t_timer]}),
		# 4 — Row z=0: filter-test bait (visible). Wins target selection only
		#       because the filter skips TransparentNearby. Attacker reaches
		#       it via (1,0)→(2,0)→swing at (3,0).
		_merge(dummy, {"name": "Bait", "pos_x": 3, "pos_z": 0}),
		# 5 — Row z=4: punching bag for TransparentSwinger's outgoing-action
		#       consume. Also the named target of AOECaster's Fire.
		_merge(dummy, {"name": "PunchingBag", "pos_x": 2, "pos_z": 4,
			"hp": 999, "max_hp": 999}),
		# 6 — Row z=4 (bleed): TRANSPARENT carrier inside Fire's AOE radius
		#       around PunchingBag. Reveal hook clears the bit on AOE damage.
		_merge(dummy, {
			"name": "TransparentInAOE", "pos_x": 3, "pos_z": 4,
			"hp": 999, "max_hp": 999,
			"status_flags_lo": t_mask, "status_timers": [t_timer]}),
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	match unit_idx:
		0: return [make_attack_gambit()]                  # Attacker
		1: return [make_attack_gambit()]                  # TransparentSwinger
		2: return [make_spell_gambit(ABILITY_FIRE)]       # AOECaster (Fire on nearest enemy)
		_: return []                                      # team-1 dummies don't act


func _ready() -> void:
	max_ticks = 600
	super._ready()


func _capture_initials(states: Array) -> void:
	for i in range(states.size()):
		if not _initial_unit_hp.has(i):
			_initial_unit_hp[i] = int(states[i].get("hp", 0))


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed or not gpu_state_reader:
		return
	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 7:
		return
	_capture_initials(states)
	if current_tick >= VERDICT_TICK:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var transparent_bit = StatusRegistry.bit(&"transparent")
	var transparent_mask = 1 << transparent_bit

	# Indices: 0=Attacker, 1=TransparentSwinger, 2=AOECaster,
	#          3=TransparentNearby, 4=Bait, 5=PunchingBag, 6=TransparentInAOE.

	var transparent_nearby_hp   = int(states[3].get("hp", 0))
	var bait_hp_now             = int(states[4].get("hp", 0))
	var transparent_nearby_init = int(_initial_unit_hp.get(3, -1))
	var bait_hp_init            = int(_initial_unit_hp.get(4, -1))
	var filter_ok = (bait_hp_now < bait_hp_init) and (transparent_nearby_hp == transparent_nearby_init)

	var swinger_status_lo = int(states[1].get("status_flags_lo", 0))
	var consume_act_ok = (swinger_status_lo & transparent_mask) == 0

	var aoe_carrier_hp_init   = int(_initial_unit_hp.get(6, -1))
	var aoe_carrier_hp_now    = int(states[6].get("hp", 0))
	var aoe_carrier_status_lo = int(states[6].get("status_flags_lo", 0))
	var aoe_consume_ok = (aoe_carrier_status_lo & transparent_mask) == 0 \
			and aoe_carrier_hp_now < aoe_carrier_hp_init

	print("\n=== TRANSPARENT TEST RESULTS ===")
	print("  Row z=0 filter:        Bait HP %d→%d,  TransparentNearby HP %d→%d — %s" % [
		bait_hp_init, bait_hp_now,
		transparent_nearby_init, transparent_nearby_hp,
		"PASS" if filter_ok else "FAIL"])
	print("  Row z=4 act consume:   TransparentSwinger bit23=%s — %s" % [
		"clear" if (swinger_status_lo & transparent_mask) == 0 else "SET",
		"PASS" if consume_act_ok else "FAIL"])
	print("  Row z=4 AOE reveal:    TransparentInAOE HP %d→%d, bit23=%s — %s" % [
		aoe_carrier_hp_init, aoe_carrier_hp_now,
		"clear" if (aoe_carrier_status_lo & transparent_mask) == 0 else "SET",
		"PASS" if aoe_consume_ok else "FAIL"])

	if filter_ok and consume_act_ok and aoe_consume_ok:
		print("\n[PASS] TRANSPARENT filter + outgoing-action consume + AOE reveal all wired")
	else:
		var why := []
		if not filter_ok:       why.append("filter (attacker chose transparent or skipped bait)")
		if not consume_act_ok:  why.append("act consume (bit didn't clear after swing)")
		if not aoe_consume_ok:  why.append("aoe reveal (bit didn't clear or no AOE damage)")
		print("\n[FAIL] %s" % ", ".join(why))
	print("================================\n")
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
