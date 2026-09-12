extends GPUCombatTestBase

## GPU Weapon Element No-Status Test (issue #116) -- LOAD-BEARING
##
## Locks in the ROM-faithful divergence between [code]FUN_80186FD0[/code] at
## [code]0x80186FD0[/code] (weapon-element path, NO status overlay) and
## [code]FUN_80186FF8[/code] at [code]0x80186FF8[/code] (spell-side, WITH
## Oil x2 / Float x Earth status overlay).
##
## Setup: a Flame-Rod Fighter and a Fire-spell Mage each attack their own
## Oiled target. Pair each with a non-Oiled control. The spell path doubles
## Oiled damage (PR #112 witness); the weapon path does NOT.
##
## Layout, on MAP042's natural terrain (heights in brackets), separated so each
## attacker's gambit resolves to its intended target via TARGET_NEAREST_ENEMY:
##   FighterOiled (team 0, Flame Rod, basic attack) at (0, 0) h13
##   FighterCtrl  (team 0, Flame Rod, basic attack) at (0, 3) h14
##   Mage         (team 0, Fire spell)              at (4, 6) h9
##   OiledWeapon  (team 1, Oil bit, weapon target)  at (1, 0) h13
##   ControlWeapon(team 1, no Oil, weapon control)  at (1, 3) h14
##   OiledSpell   (team 1, Oil bit, spell target)   at (5, 8) h7  -- Fire range 4
##   ControlSpell (team 1, no Oil, spell control)   at (6, 8) h7
##
## The Fire spell is an AOE radius 1 so it lands on both OiledSpell and
## ControlSpell in one cast (re-using the GPUOilFireDoubleTest pattern).
##
## WHY THE SPELL TRIO MOVED (2026-08-22). It was Mage (0,10) / OiledSpell (3,10) /
## ControlSpell (3,11), and the header called the layout "Manhattan". It is not:
## TARGET_NEAREST_ENEMY ranks by `get_distance`, a precomputed WALKABLE path field, and
## skips anything it cannot reach (`if (val < 0) continue`). On MAP042 the x=0..1 column is
## a high ridge (h12-16) and row z=10 falls off a cliff at x=3 (h9 -> h3, a 6-drop against
## Jump 3). So the mage's own targets, 3 tiles away by Manhattan, were UNREACHABLE, and the
## nearest reachable enemy was ControlWeapon — 8 tiles away along the ridge. The mage spent
## the whole run walking to the wrong half of the test and the spell path recorded zero
## hits. `assets/maps/` is gitignored, so the terrain this layout stands on is a local ROM
## export that can drift again; `_check_layout_premise` asserts it now.
##
## The three spell units now sit in the flat low pocket at z=8 (h7): the mage casts from 3
## tiles away without moving, and the weapon half is on the far side of the cliff where it
## cannot be mistaken for a nearer target.
##
## PASS: spell oiled_delta == 2 * spell control_delta AND weapon oiled_delta
## approximately equals weapon control_delta (ratio ~1.0, NOT 2.0).
## FAIL: any ratio violates expectation.


const ABILITY_FIRE = 16
const FLAME_ROD_ID = 53
const STATUS_OIL_BIT = 30
const TARGET_START_HP = 800  # large enough to survive 2 hits without dying
const FIRE_RANGE = 4         # ability_attributes.json: Fire range = 4, effect_area = 1
const FIRE_AOE = 1

# Tile placements, as [x, z]. See the layout note in the header — these are chosen against
# MAP042's terrain, not on a flat grid.
const FIGHTER_A    := [0, 0]
const FIGHTER_B    := [0, 3]
const MAGE         := [4, 6]
const WEAPON_OILED := [1, 0]
const WEAPON_CTRL  := [1, 3]
const SPELL_OILED  := [5, 8]
const SPELL_CTRL   := [6, 8]


func get_test_name() -> String:
	return "GPU Weapon Element No-Status Test (Oil x2 fires on spells, NOT on weapons)"


func _fighter(name: String, pos_x: int, pos_z: int) -> Dictionary:
	return {
		"name": name,
		"pos_x": pos_x, "pos_z": pos_z,
		"hp": 500, "max_hp": 500,
		"pa": 10, "ma": 5, "wp": 3,
		"brave": 50, "faith": 50,
		"mp": 0, "max_mp": 0,
		"speed": 100, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x04,
		"weapon_id": FLAME_ROD_ID,
	}


func get_team0_unit_configs() -> Array:
	return [
		_fighter("FighterOiledTarget",   FIGHTER_A[0], FIGHTER_A[1]),
		_fighter("FighterControlTarget", FIGHTER_B[0], FIGHTER_B[1]),
		{
			"name": "FireMage",
			"pos_x": MAGE[0], "pos_z": MAGE[1],
			"hp": 500, "max_hp": 500,
			"pa": 5, "ma": 12, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 99, "max_mp": 99,
			"speed": 100, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x04,
		},
	]


func _target(name: String, pos_x: int, pos_z: int, oiled: bool) -> Dictionary:
	var cfg := {
		"name": name,
		"pos_x": pos_x, "pos_z": pos_z,
		"hp": TARGET_START_HP, "max_hp": TARGET_START_HP,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 100,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x05,
	}
	if oiled:
		cfg["status_flags_lo"] = 1 << STATUS_OIL_BIT
	return cfg


func get_team1_unit_configs() -> Array:
	return [
		_target("OiledWeapon",   WEAPON_OILED[0],  WEAPON_OILED[1],  true),
		_target("ControlWeapon", WEAPON_CTRL[0],   WEAPON_CTRL[1],   false),
		_target("OiledSpell",    SPELL_OILED[0],   SPELL_OILED[1],   true),
		_target("ControlSpell",  SPELL_CTRL[0],    SPELL_CTRL[1],    false),
	]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	if team != 0:
		return []
	# 0=FighterOiledTarget, 1=FighterControlTarget, 2=FireMage
	if unit_idx == 0 or unit_idx == 1:
		return [make_attack_gambit()]
	if unit_idx == 2:
		return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]
	return []


func _ready() -> void:
	max_ticks = 1500
	super._ready()


var _weapon_hits_seen: bool = false
var _spell_hits_seen: bool = false
var _weapon_oiled_delta: int = 0
var _weapon_control_delta: int = 0
var _spell_oiled_delta: int = 0
var _spell_control_delta: int = 0
var _results_printed: bool = false


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 7:
		return

	# Indices: 0=FighterOiled, 1=FighterCtrl, 2=FireMage,
	#          3=OiledWeapon, 4=ControlWeapon, 5=OiledSpell, 6=ControlSpell.
	var ow_hp := int(states[3].get("hp", TARGET_START_HP))
	var cw_hp := int(states[4].get("hp", TARGET_START_HP))
	var os_hp := int(states[5].get("hp", TARGET_START_HP))
	var cs_hp := int(states[6].get("hp", TARGET_START_HP))

	# Capture the FIRST nonzero delta for each target individually -- subsequent
	# hits compound, so we lock in the cleanest measurement of one strike's
	# scale. AOE fan-out may not land both spell deltas in the same snapshot,
	# hence the per-target capture.
	if _weapon_oiled_delta == 0 and ow_hp < TARGET_START_HP:
		_weapon_oiled_delta = TARGET_START_HP - ow_hp
	if _weapon_control_delta == 0 and cw_hp < TARGET_START_HP:
		_weapon_control_delta = TARGET_START_HP - cw_hp
	if _spell_oiled_delta == 0 and os_hp < TARGET_START_HP:
		_spell_oiled_delta = TARGET_START_HP - os_hp
	if _spell_control_delta == 0 and cs_hp < TARGET_START_HP:
		_spell_control_delta = TARGET_START_HP - cs_hp
	_weapon_hits_seen = _weapon_oiled_delta > 0 and _weapon_control_delta > 0
	_spell_hits_seen = _spell_oiled_delta > 0 and _spell_control_delta > 0

	if _weapon_hits_seen and _spell_hits_seen:
		_print_results(states)
		return

	if current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var ow_hp := int(states[3].get("hp", TARGET_START_HP))
	var cw_hp := int(states[4].get("hp", TARGET_START_HP))
	var os_hp := int(states[5].get("hp", TARGET_START_HP))
	var cs_hp := int(states[6].get("hp", TARGET_START_HP))
	if _weapon_oiled_delta == 0:    _weapon_oiled_delta = TARGET_START_HP - ow_hp
	if _weapon_control_delta == 0:  _weapon_control_delta = TARGET_START_HP - cw_hp
	if _spell_oiled_delta == 0:     _spell_oiled_delta = TARGET_START_HP - os_hp
	if _spell_control_delta == 0:   _spell_control_delta = TARGET_START_HP - cs_hp

	var premise_ok := _check_layout_premise()
	print("\n=== WEAPON ELEMENT NO-STATUS TEST RESULTS ===")
	print("  WEAPON path (Flame Rod basic attack):")
	print("    OiledWeapon   delta=%+d, ControlWeapon delta=%+d" % [
		-_weapon_oiled_delta, -_weapon_control_delta])
	print("  SPELL path (Fire AOE):")
	print("    OiledSpell    delta=%+d, ControlSpell  delta=%+d" % [
		-_spell_oiled_delta, -_spell_control_delta])

	var weapon_hit := _weapon_oiled_delta > 0 and _weapon_control_delta > 0
	var spell_hit := _spell_oiled_delta > 0 and _spell_control_delta > 0
	# Weapon path: Oil should NOT apply -- ratio ~1.0 (allow integer-floor +-1).
	var diff: int = absi(_weapon_oiled_delta - _weapon_control_delta)
	var weapon_no_overlay: bool = weapon_hit and diff <= 1
	# Spell path: Oil x2 -- exact ratio from PR #112's witness pattern.
	var spell_doubled := spell_hit and _spell_oiled_delta == _spell_control_delta * 2

	if premise_ok and weapon_hit and spell_hit and weapon_no_overlay and spell_doubled:
		print("\n[PASS] Oil applies on spells (x2) but NOT on weapon attacks (ratio ~1.0)")
	else:
		var why: Array = []
		if not premise_ok: why.append("the MAP no longer supports this layout (see [LAYOUT] above)")
		if not weapon_hit: why.append("weapon path did not register both hits")
		if not spell_hit:  why.append("spell path did not register both hits")
		if weapon_hit and not weapon_no_overlay:
			why.append("weapon-oiled differs from weapon-control by >1 (overlay leaked into weapon)")
		if spell_hit and not spell_doubled:
			why.append("spell-oiled != 2 * spell-control (overlay broken on spell side; #112 regression?)")
		print("\n[FAIL] %s" % ", ".join(why))
	print("=============================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)


## Assert the two facts the layout rests on, and print every tile height either way.
##
## This test measures a DAMAGE RATIO, so it is only meaningful if each attacker actually
## reached its own pair. Both halves depend on terrain the repo does not track:
##   1. the mage must be able to cast on OiledSpell from where it stands — within Fire's
##      range, with ControlSpell inside the AOE around it;
##   2. the two halves must not be confusable — the weapon pair must not out-rank the spell
##      pair for the mage by Manhattan distance either.
## When a regenerated export breaks one, say which, instead of reporting a phantom
## "spell path did not register both hits".
func _check_layout_premise() -> bool:
	# Typed local for the inherited `CombatHost.lattice` — receiver inference is per file.
	var lat: Lattice = lattice
	if lat == null:
		print("[LAYOUT] no lattice — the layout premise could not be checked")
		return false
	var named := {
		"FighterOiled": FIGHTER_A, "FighterCtrl": FIGHTER_B, "Mage": MAGE,
		"OiledWeapon": WEAPON_OILED, "ControlWeapon": WEAPON_CTRL,
		"OiledSpell": SPELL_OILED, "ControlSpell": SPELL_CTRL,
	}
	var parts: Array = []
	for n in named:
		var t := lat.terrain_at(TerrainCell.ground(named[n][0], named[n][1]))
		parts.append("%s(%d,%d)h=%s" % [n, named[n][0], named[n][1],
			str(int(t.height)) if t != null else "OFF-MAP"])
	print("[LAYOUT] %s" % " ".join(parts))

	var ok := true
	var cast_dist: int = absi(MAGE[0] - SPELL_OILED[0]) + absi(MAGE[1] - SPELL_OILED[1])
	if cast_dist > FIRE_RANGE:
		print("[LAYOUT] FAIL: mage is %d tiles from OiledSpell, past Fire's range %d" % [
			cast_dist, FIRE_RANGE])
		ok = false
	var aoe_dist: int = absi(SPELL_CTRL[0] - SPELL_OILED[0]) + absi(SPELL_CTRL[1] - SPELL_OILED[1])
	if aoe_dist > FIRE_AOE:
		print("[LAYOUT] FAIL: ControlSpell is %d from OiledSpell, outside the AOE radius %d — "
			% [aoe_dist, FIRE_AOE] + "one cast cannot hit both")
		ok = false
	# The mage must not sit inside its own blast (Fire has dont_hit_caster = false).
	var self_dist: int = absi(MAGE[0] - SPELL_OILED[0]) + absi(MAGE[1] - SPELL_OILED[1])
	if self_dist <= FIRE_AOE:
		print("[LAYOUT] FAIL: the mage is inside its own AOE (%d <= %d)" % [self_dist, FIRE_AOE])
		ok = false
	# The weapon pair must be unambiguously farther from the mage than the spell pair.
	for wn in [WEAPON_OILED, WEAPON_CTRL]:
		var d: int = absi(MAGE[0] - wn[0]) + absi(MAGE[1] - wn[1])
		if d <= cast_dist:
			print("[LAYOUT] FAIL: weapon target (%d,%d) is %d from the mage, "
				% [wn[0], wn[1], d] + "no farther than its own target (%d)" % cast_dist)
			ok = false
	return ok
