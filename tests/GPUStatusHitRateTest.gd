extends GPUCombatTestBase

## GPU Status Hit Rate Test (#103)
##
## Witnesses the Faith-scaled hit% for formula 10 status spells. Two slices
## in one battle, same Priest casting Poison on different targets:
##
##   InnocentTarget (Faith = 0)  -- Poison must NEVER inflict. The roll is
##                                  (MA+X) * (Faith_c/100) * (0/100) = 0%.
##   FaithfulTarget (Faith = 90) -- Poison must inflict at least once across
##                                  the test window. With Priest Faith 90 and
##                                  formula_x 160 the per-cast hit is
##                                  min(100, 12+160) * 0.90 * 0.90 = 81%, so
##                                  zero hits across N casts is astronomically
##                                  rare (P(0 hits, N=4) = 0.19^4 ~ 0.13%).
##
## Pairs with GPUStatusInflictTest (#98 -- the ALL-mode SET path) and
## GPUStatusCancelTest (#100 -- the CANCEL path). Once green every other
## formula-10/11 status spell inherits the same hit roll.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


const ABILITY_POISON = 28
const TEST_MAX_TICKS = 1500


func get_test_name() -> String:
	return "GPU Status Hit Rate Test (Faith-scaled #103)"


func get_team0_unit_configs() -> Array:
	# Priest casts Poison on the NEAREST_ENEMY each gambit eval. Both targets
	# stand still; the Innocent target is closer so the FIRST cast goes there,
	# but the Priest also gets ample reach for the faithful one once the
	# innocent's miss exhausts its slice.
	return [
		{
			"name": "Priest",
			"pos_x": 0, "pos_z": 0,
			"hp": 999, "max_hp": 999,
			"pa": 5, "ma": 12, "wp": 1,
			"brave": 50, "faith": 90,
			"mp": 99, "max_mp": 99,
			"speed": 100, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x02,
		},
	]


func get_team1_unit_configs() -> Array:
	# Faith=0 stand-in for Innocent (status bit lands in #99). Faith=90 is the
	# "easy hit" target. Both inert (move=0, no gambits) so the Priest's
	# nearest-enemy targeting is geometry-stable. Same max_hp so log
	# inspection is symmetrical.
	var base := {
		"pa": 1, "ma": 1, "wp": 1,
		"brave": 50,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x05,
		"hp": 999, "max_hp": 999,
	}
	return [
		_merge(base, {"name": "InnocentTarget", "pos_x": 2, "pos_z": 0, "faith": 0}),
		_merge(base, {"name": "FaithfulTarget", "pos_x": 3, "pos_z": 0, "faith": 90}),
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		return [make_spell_gambit(ABILITY_POISON, GPUConstants.TARGET_NEAREST_ENEMY)]
	return []


func _ready() -> void:
	# ct=3 -> ~90 ticks charge + ~60 anim + 300 cooldown = ~450 ticks per
	# cast. 1500 budget gives ~3 casts per target before the deadline.
	max_ticks = TEST_MAX_TICKS
	super._ready()


var _innocent_poisoned_at: int = -1
var _faithful_poisoned_at: int = -1
var _results_printed: bool = false


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 3:
		return

	var poison_bit_mask := 1 << StatusRegistry.bit(&"poison")
	var innocent_flags := int(states[1].get("status_flags_lo", 0))
	var faithful_flags := int(states[2].get("status_flags_lo", 0))

	if _innocent_poisoned_at < 0 and (innocent_flags & poison_bit_mask) != 0:
		_innocent_poisoned_at = current_tick
	if _faithful_poisoned_at < 0 and (faithful_flags & poison_bit_mask) != 0:
		_faithful_poisoned_at = current_tick

	if _faithful_poisoned_at >= 0 or current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	print("\n=== STATUS HIT RATE TEST RESULTS ===")
	print("  InnocentTarget (Faith=0):  poisoned_at = %s" % (
		"%d (FAILED -- 0%% hit should never land)" % _innocent_poisoned_at
		if _innocent_poisoned_at >= 0 else "never (OK)"))
	print("  FaithfulTarget (Faith=90): poisoned_at = %s" % (
		"%d (OK)" % _faithful_poisoned_at
		if _faithful_poisoned_at >= 0 else "never (FAIL -- expected ~81%% hit)"))

	var innocent_ok := _innocent_poisoned_at < 0
	var faithful_ok := _faithful_poisoned_at >= 0

	if innocent_ok and faithful_ok:
		print("\n[PASS] Faith=0 immune to Faith-scaled status; Faith=90 inflicted reliably")
	else:
		var why: Array = []
		if not innocent_ok: why.append("Innocent (Faith=0) was poisoned at tick %d" % _innocent_poisoned_at)
		if not faithful_ok: why.append("Faithful (Faith=90) never poisoned within %d ticks" % max_ticks)
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
