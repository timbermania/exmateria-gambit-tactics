extends GPUCombatTestBase

## GPU Status No-Damage Test
##
## Tests that status-only formulas deal 0 HP damage AT CAST.
## These formulas should route to the no-damage path in cast_instant_spell().
##
## Formulas tested:
##   10 (status, faith-scaled hit) -- Poison(28): should deal 0 HP damage
##   11 (status, faith-scaled hit) -- Haste2(33): should deal 0 HP damage
##   56 (status, 100% hit)         -- Seal(181): should deal 0 HP damage
##
## WHY THIS IS NOT "THE TARGET'S HP NEVER CHANGES" (#453). It was, and that assertion is
## false for Poison. A status-only formula deals no DIRECT damage, but the status it
## SUCCESSFULLY APPLIES may have a damage-over-time component of its own, and Poison's is
## the canonical FFT one: `stage_damage.glsl` queues `max(1, max_hp / POISON_HP_DIVISOR)`
## into every poisoned unit every `POISON_TICK_INTERVAL` ticks (status_system.md §2). On a
## 500 HP target that is exactly -62, repeating.
##
## So the old test scored the correct damage-over-time of the status it had just correctly
## inflicted as a bug, and could only pass when Poison's faith-scaled hit roll MISSED.
## Measured 2026-08-23: 13 FAIL / 7 PASS in 20 idle runs, 10 FAIL / 14 PASS in 24 under an
## 8-way mixed load — a hit rate, not a flake, and every failing run showed the identical
## -62 ladder (500 -> 438 -> 376 -> ...). Pinning the battle seed would only have frozen
## which side of the roll it lands on; a pin that lands on "miss" is a green test that
## asserts nothing whatever about poison.
##
## WHAT IT ASSERTS NOW, on both branches of the roll, so the outcome is deterministic even
## though the roll is not:
##   * every HP change on a target is a LEGAL poison tick — the poison bit is set on that
##     unit and the delta is exactly `-max(1, max_hp / POISON_HP_DIVISOR)`. Anything else
##     is a status-only formula dealing direct damage, which is the bug this test is for;
##   * the arithmetic closes: final HP == TARGET_HP - (ticks observed x tick size);
##   * poison MISSED  -> the target is untouched at TARGET_HP;
##   * poison LANDED  -> it actually ticked, once a full interval has had time to elapse.
##     That turns the old failure signal into coverage of the DoT path instead of a
##     result the test was hoping not to see.

# Ability IDs
const ABILITY_POISON = 28   # Formula 10: status-only (faith-scaled)
const ABILITY_HASTE2 = 33   # Formula 11: status-only buff (faith-scaled)
const ABILITY_SEAL = 181     # Formula 56: status-only (100% hit)

const TARGET_HP = 500

# Hand-mirrored from src/gpu/shaders/combat_common.glslinc:378-379, the same way
# StatusRegistry mirrors the STATUS_* bits. A poison tick is
# `max(1, max_hp / POISON_HP_DIVISOR)` every POISON_TICK_INTERVAL ticks.
const POISON_TICK_INTERVAL = 30
const POISON_HP_DIVISOR = 8
# StatusRegistry.NAMES_TO_BITS[&"poison"] — bits 0-31 live in `status_flags_lo`.
const POISON_BIT = 15

# Track whether each caster has acted (entered ACTING state)
var _caster_acted: Dictionary = {}  # caster_idx -> bool
var _check_timer: float = 0.0
var _all_passed_logged: bool = false

# Per-target damage-over-time bookkeeping, keyed by unit index (3-5).
var _poison_ticks: Dictionary = {}      # unit_idx -> count of LEGAL poison ticks seen
var _poison_loss: Dictionary = {}       # unit_idx -> HP those ticks actually removed
## Sealed verdict per target: {hp, ticks, loss} snapshotted the moment its DoT is PROVEN.
## SEAL_TICKS ticks establish both the size and the recurrence, which is everything this
## test claims about the damage-over-time path — and stopping there keeps the assertion out
## of the death spiral that follows. Left unsealed the poison target reaches 0 HP before the
## last caster has acted, and the killing change is never reported through `on_hp_changed`
## at all (measured: 8 ticks reported, 496 HP, and the final 4 -> 0 arrives through no
## signal), so the bookkeeping cannot close and a correct run scores red.
const SEAL_TICKS = 2
var _sealed: Dictionary = {}            # unit_idx -> {hp, ticks, loss}
var _poison_landed_tick: Dictionary = {}  # unit_idx -> tick the poison bit was first seen
var _illegal_change: Dictionary = {}    # unit_idx -> first HP change that was NOT a legal tick


## The exact HP a poison tick removes from this target. Integer division, and floored at 1
## the same way the shader floors it, so a low-max_hp unit still loses something.
func _poison_tick_size(max_hp: int) -> int:
	return maxi(1, max_hp / POISON_HP_DIVISOR)


## Is unit `idx` currently holding the poison bit? Read from the live GPU state rather than
## inferred from "we cast Poison at it" — the whole point is that the cast may have MISSED,
## and the two branches assert different things.
func _is_poisoned(idx: int) -> bool:
	if gpu_state_reader == null:
		return false
	var states = gpu_state_reader.get_all_unit_states()
	if idx >= states.size():
		return false
	return (int(states[idx].get("status_flags_lo", 0)) & (1 << POISON_BIT)) != 0

# Map caster index to test name
var _caster_test_names: Dictionary = {
	0: "f10_poison",
	1: "f11_haste2",
	2: "f56_seal",
}


func get_test_name() -> String:
	return "GPU Status No-Damage Test"


func get_team0_unit_configs() -> Array:
	var base = {
		"hp": 999, "max_hp": 999,
		"pa": 10, "ma": 10, "wp": 5,
		"brave": 50, "faith": 70,
		"mp": 200, "max_mp": 200,
		"speed": 100,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x02,
	}

	return [
		# 0: Formula 10 -- Poison (status, faith-scaled)
		_merge(base, {
			"name": "F10_Poison",
			"pos_x": 0, "pos_z": 0,
			"gambits": [make_spell_gambit(ABILITY_POISON)],
		}),
		# 1: Formula 11 -- Haste2 (status buff, faith-scaled)
		_merge(base, {
			"name": "F11_Haste2",
			"pos_x": 2, "pos_z": 0,
			"gambits": [make_spell_gambit(ABILITY_HASTE2)],
		}),
		# 2: Formula 56 -- Seal (status, 100% hit)
		_merge(base, {
			"name": "F56_Seal",
			"pos_x": 4, "pos_z": 0,
			"gambits": [make_ability_gambit(ABILITY_SEAL)],
		}),
	]


func get_team1_unit_configs() -> Array:
	var target_base = {
		"hp": TARGET_HP, "max_hp": TARGET_HP,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 70,
		"mp": 50, "max_mp": 50,
		"speed": 50,
		"move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x05,
	}

	return [
		# 3: Target for Poison
		_merge(target_base, {
			"name": "Tgt_F10",
			"pos_x": 0, "pos_z": 2,
			"gambits": [make_move_to_gambit(0, 2)],
		}),
		# 4: Target for Haste2
		_merge(target_base, {
			"name": "Tgt_F11",
			"pos_x": 2, "pos_z": 2,
			"gambits": [make_move_to_gambit(2, 2)],
		}),
		# 5: Target for Seal
		_merge(target_base, {
			"name": "Tgt_F56",
			"pos_x": 4, "pos_z": 2,
			"gambits": [make_move_to_gambit(4, 2)],
		}),
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	var all_configs = get_team0_unit_configs() + get_team1_unit_configs()
	if unit_idx < all_configs.size():
		return all_configs[unit_idx].get("gambits", [make_attack_gambit()])
	return [make_attack_gambit()]


func _ready():
	max_ticks = 2000  # ~33 seconds -- status abilities are fast
	super._ready()
	for i in range(3):
		_caster_acted[i] = false

	call_deferred("_print_test_debug")


func _print_test_debug():
	print("\n=== STATUS NO-DAMAGE TEST ===")
	print("  Formula 10 (Poison, ID %d): should deal 0 HP damage" % ABILITY_POISON)
	print("  Formula 11 (Haste2, ID %d): should deal 0 HP damage" % ABILITY_HASTE2)
	print("  Formula 56 (Seal, ID %d): should deal 0 HP damage" % ABILITY_SEAL)
	print("  All targets start at %d HP" % TARGET_HP)
	print("==============================\n")


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	var old_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[old_state] if old_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(old_state)
	var new_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[new_state] if new_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(new_state)
	print("  [STATE] %s: %s -> %s" % [unit_name, old_name, new_name])

	# Track when casters finish acting
	if unit_idx < 3 and new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		_caster_acted[unit_idx] = true
		var test_name = _caster_test_names.get(unit_idx, "?")
		print("  [INFO] %s is casting (test: %s)" % [unit_name, test_name])


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta: int):
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	# An HP change on a target 3-5 is a failure ONLY if it is not a legal poison tick.
	# A status-only formula deals no DIRECT damage, but the Poison it successfully applied
	# ticks for `max(1, max_hp / POISON_HP_DIVISOR)` on its own schedule and that is the
	# engine working. The two are told apart by the poison bit plus the exact magnitude —
	# anything else on a target is a status-only formula dealing damage, the real bug.
	if unit_idx >= 3 and unit_idx <= 5:
		# Past the seal this target's verdict is already decided and what follows is the
		# poison finishing it off — not evidence about the CAST, which is what is on trial.
		if _sealed.has(unit_idx):
			return
		var test_idx = unit_idx - 3
		var test_name = _caster_test_names.get(test_idx, "?")
		var tick_size = _poison_tick_size(TARGET_HP)
		# A tick removes `tick_size`, EXCEPT the one that kills: HP floors at 0, so the last
		# tick on a unit with less than a full tick left is short by exactly the shortfall.
		# Measured — an unmodified run reaches 4 HP after 8 ticks and the 9th lands as -4.
		# Counting only full-size ticks scored that legal, lethal tick as direct damage.
		var lethal_tick: bool = new_hp == 0 and delta == -old_hp and old_hp < tick_size
		# `_is_poisoned` OR "was seen poisoned earlier": the bit can be cleared by the very
		# change that kills the unit, and a lethal tick read after that would otherwise be
		# rejected for the state its own arrival caused.
		var poisoned_now_or_before: bool = _is_poisoned(unit_idx) \
				or _poison_landed_tick.has(unit_idx) or int(_poison_ticks.get(unit_idx, 0)) > 0
		if (delta == -tick_size or lethal_tick) and poisoned_now_or_before:
			_poison_ticks[unit_idx] = int(_poison_ticks.get(unit_idx, 0)) + 1
			_poison_loss[unit_idx] = int(_poison_loss.get(unit_idx, 0)) + (-delta)
			print("  [DOT] %s: poison tick %d on %s for %d%s  HP: %d -> %d" % [
				test_name, _poison_ticks[unit_idx], unit_name, -delta,
				" (lethal, clamped at 0)" if lethal_tick else "", old_hp, new_hp])
			if int(_poison_ticks[unit_idx]) >= SEAL_TICKS:
				_sealed[unit_idx] = {"hp": new_hp, "ticks": int(_poison_ticks[unit_idx]),
					"loss": int(_poison_loss[unit_idx])}
				print("  [DOT] %s: DoT proven over %d ticks — verdict sealed at %d HP" % [
					test_name, SEAL_TICKS, new_hp])
			_rlog.log_entry("POISON_TICK", {"test": test_name, "delta": delta, "new_hp": new_hp})
		else:
			if not _illegal_change.has(unit_idx):
				_illegal_change[unit_idx] = delta
			print("\n  [FAIL] %s: target %s took a %d HP change that is not a poison tick"
				% [test_name, unit_name, delta]
				+ " (HP: %d -> %d, poisoned=%s, tick_size=%d)" % [
					old_hp, new_hp, str(_is_poisoned(unit_idx)), tick_size])
			_rlog.log_entry("TEST_FAIL", {"test": test_name, "delta": delta, "old_hp": old_hp, "new_hp": new_hp})
	else:
		if delta < 0:
			print("  [DAMAGE] %s hit for %d  HP: %d -> %d" % [unit_name, abs(delta), old_hp, new_hp])
		elif delta > 0:
			print("  [HEAL] %s healed for %d  HP: %d -> %d" % [unit_name, delta, old_hp, new_hp])


func _process(delta):
	super._process(delta)
	if not combat_active or victory_achieved:
		return
	if not gpu_state_reader:
		return

	_check_timer += delta
	if _check_timer < 0.5:
		return
	_check_timer = 0.0

	# Wait until all casters have acted at least once
	var all_acted = true
	for i in range(3):
		if not _caster_acted.get(i, false):
			all_acted = false
			break

	if not all_acted:
		return

	if _all_passed_logged:
		return

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 6:
		return

	# Note the tick each target's poison bit first appears, so "it landed but never ticked"
	# is distinguishable from "it landed a moment ago and its first tick is still due".
	for _i in [3, 4, 5]:
		if not _poison_landed_tick.has(_i) \
				and (int(states[_i].get("status_flags_lo", 0)) & (1 << POISON_BIT)) != 0:
			_poison_landed_tick[_i] = current_tick

	# DON'T CONCLUDE WHILE A TICK IS STILL DUE. The old test read HP the moment the last
	# caster acted, which is why its verdict tracked nothing but whether it got there before
	# poison's first tick. If the bit is set and no tick has landed yet, give the schedule a
	# full interval to produce one — and if two intervals pass with nothing, that is a
	# genuine failure (the status applied and the DoT never ran), reported below.
	for _i in [3, 4, 5]:
		if _poison_landed_tick.has(_i) and int(_poison_ticks.get(_i, 0)) == 0 \
				and current_tick < int(_poison_landed_tick[_i]) + 2 * POISON_TICK_INTERVAL:
			return

	# Score each target: the cast dealt no direct damage, and whatever HP it did lose is
	# fully accounted for by legal poison ticks.
	_all_passed_logged = true
	var passed = 0
	var total = 3
	var target_indices = [3, 4, 5]
	var test_names = ["f10_poison", "f11_haste2", "f56_seal"]

	print("\n=== STATUS NO-DAMAGE TEST RESULTS ===")
	for i in range(3):
		var idx = target_indices[i]
		# A sealed target is scored on its snapshot, not on live state that has moved on.
		var target_hp = int(_sealed[idx]["hp"]) if _sealed.has(idx) \
			else int(states[idx].get("hp", 0))
		var ticks = int(_poison_ticks.get(idx, 0))
		var landed = _poison_landed_tick.has(idx)
		# Against the HP those ticks ACTUALLY removed, not ticks x tick_size — the lethal
		# tick is short, and an idealised product would read as an unaccounted gain.
		var expected_hp = TARGET_HP - int(_poison_loss.get(idx, 0))
		if _illegal_change.has(idx):
			# A status-only formula dealt DIRECT damage. The one thing this test is for.
			print("  [FAIL] %s: target took a %d HP change that was not a poison tick" % [
				test_names[i], int(_illegal_change[idx])])
			_rlog.log_entry("TEST_FAIL", {"test": test_names[i], "reason": "direct_damage",
				"delta": int(_illegal_change[idx])})
		elif target_hp != expected_hp:
			# Bookkeeping did not close: HP moved by something nobody reported.
			print("  [FAIL] %s: target HP %d != %d (start %d - %d HP over %d poison ticks)"
				% [test_names[i], target_hp, expected_hp, TARGET_HP,
					int(_poison_loss.get(idx, 0)), ticks]
				+ " — HP moved by something that was not reported")
			_rlog.log_entry("TEST_FAIL", {"test": test_names[i], "reason": "unaccounted",
				"hp": target_hp, "expected": expected_hp})
		elif not landed:
			# No poison on this target — either Poison's faith-scaled roll missed, or this is
			# haste2 / seal, whose statuses have no damage-over-time component at all. Either
			# way nothing may have touched its HP.
			print("  [PASS] %s: no poison on target; HP untouched at %d" % [
				test_names[i], target_hp])
			_rlog.log_entry("TEST_PASS", {"test": test_names[i], "hp": target_hp, "landed": false})
			passed += 1
		elif ticks == 0:
			# The bit is set and two full intervals went by without a tick. The status
			# applied and its damage-over-time never ran.
			print("  [FAIL] %s: poison landed at tick %d but never ticked by tick %d" % [
				test_names[i], int(_poison_landed_tick[idx]), current_tick])
			_rlog.log_entry("TEST_FAIL", {"test": test_names[i], "reason": "landed_never_ticked"})
		else:
			# The cast dealt no direct damage AND the status it applied ticks correctly.
			print("  [PASS] %s: cast dealt 0 direct damage; poison landed and ticked %d times for %d HP (now %d)" % [
				test_names[i], ticks, int(_poison_loss.get(idx, 0)), target_hp])
			_rlog.log_entry("TEST_PASS", {"test": test_names[i], "hp": target_hp,
				"landed": true, "ticks": ticks})
			passed += 1

	print("\n  %d/%d status no-damage tests passed" % [passed, total])
	if passed == total:
		print("[PASS] All status no-damage tests passed")
		_rlog.log_entry("TEST_PASS", {"reason": "all_status_no_damage", "passed": passed, "total": total})
	else:
		print("[FAIL] %d/%d status no-damage tests failed" % [total - passed, total])
		_rlog.log_entry("TEST_FAIL", {"reason": "status_dealt_damage", "passed": passed, "total": total})
	print("======================================\n")
	_rlog.output()
	victory_achieved = true
	combat_active = false
	get_tree().quit()


func on_victory(winning_team: int):
	if not _all_passed_logged:
		# Print results even if victory happens before all casters act
		print("\n[WARNING] Victory before all status abilities were cast")
	if winning_team >= 0:
		print("[%s] Team %d wins at tick %d" % [get_test_name(), winning_team, current_tick])


# Helper to merge two dictionaries
static func _merge(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var result = base.duplicate()
	for key in overrides:
		result[key] = overrides[key]
	return result
