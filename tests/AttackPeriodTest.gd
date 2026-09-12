# test-kind: gpu
# seeded-break: in combat_common.glslinc make `consume_attack_recovery` return
# unconditionally (or delete its two write_unit lines) — the DOUBLED arm reds
# because the levered unit's realised period collapses back onto the control's.
extends GPUCombatTestBase

## The LEVERED ATTACK PERIOD, measured in a live battle (#1107, ADR-0279).
##
## 🔴 EVERY CONTROL AND EVERY SUBJECT IS IN THE SAME BATTLE, ON THE SAME TICK
## CLOCK. An attack period is a duration, and a duration compared across two runs
## measures the box as much as the change. Every arm differs from its own control
## in exactly one field — `attack_period_factor_q8` — so no amount of load on
## this machine can move one arm without moving the others.
##
## 🔴 A BATTLE IS 4v4. `units_per_battle` is 8 and it is split per TEAM, so a
## fifth team-0 unit is dropped with no error and its slot index belongs to
## somebody else. This test was first written with five attackers and read the
## DUMMY's 40-tick melee gaps as if they were a bow's — an arm that examined the
## wrong unit and reported a confident number for it. That is why
## `_check_subject` asserts each slot's `weapon_type` and
## `attack_period_factor_q8` BEFORE any timing assertion runs: an instrument that
## cannot name its own subject cannot be trusted about it.
##
## Five measured arms across both teams, one process (charter clause 13):
##
##   CONTROL     sword, q8 = 256 (1.0x) — the reference, and the instrument's own
##               positive control: if it never swings, every other arm is
##               measuring nothing and the report says so.
##   DOUBLED     sword, q8 = 512 (2.0x) — must owe exactly one more base period
##               as recovery, so its gap is the control's PLUS that period.
##   BOW CONTROL / BOW DOUBLED — the same pair on a RANGED weapon, and the pair
##               that earns its slots. A bow's period is NOT its animation: the
##               firer waits out `projectile_frame + max(dist * 10, 15)` in
##               AWAITING_IMPACT, so at distance 3 it is a 56-tick period over a
##               52-frame SEQ. A kernel that scaled the ANIMATION passes every
##               melee arm and still turns `x2.0` into `x1.68` on exactly the
##               three weapon types this ticket was about — which is the defect
##               these two arms caught.
##   HALVED      sword, q8 = 128 (0.5x), on TEAM 1 because team 0 is full — must
##               be IDENTICAL to the control. The unlevered period is the floor,
##               so a factor below 1.0 buys nothing. This arm fails if the clamp
##               ever becomes a negative timer.
##
## Every assertion is on the DIFFERENCE between an arm and its OWN control, never
## on a gap's absolute value. Between an action ending and the next beginning
## there is a fixed dispatch overhead (the IDLE edge, then `evaluate_gambits` on
## the next tick); pinning an absolute number would pin that overhead, which is
## not what this ticket changed. A difference cancels it.

const Q8_ONE := 256
const Q8_DOUBLE := 512
const Q8_HALF := 128

## The melee arms share one `TYPE1_MELEE_SWING` base. DIRECT (`weapon_flags` 4)
## removes the vertical attack limit: the procedural map varies in height, and an
## arm that silently stopped being able to reach its target would look exactly
## like an arm whose period changed.
const WEAPON_FLAGS_DIRECT := 4
const MELEE_WEAPON_TYPE := 1
const BROAD_SWORD := 19

## `weapon_type` 12 is Bow. `weapon_range` 5 is the Long Bow's own reach; the
## archers stand at distance 3 inside it, because the flight tail is a function
## of the DISTANCE STOOD AT, not of the weapon's maximum.
const BOW_WEAPON_TYPE := 12
const LONG_BOW := 83
const BOW_RANGE := 5

## SLOT INDICES, NOT ARRAY POSITIONS. Team 0 occupies 0..3 and team 1 starts at
## `units_per_battle / 2` = 4, so the dummy is slot 4 and the team-1 floor arm is
## slot 5. Measured off the running battle, not assumed — see `_check_subject`.
const TEAM1_SLOT_BASE := 4
const IDX_CONTROL := 0
const IDX_DOUBLED := 1
const IDX_BOW_CONTROL := 2
const IDX_BOW_DOUBLED := 3
const IDX_HALVED := TEAM1_SLOT_BASE + 1

var _acting_ticks := {
	IDX_CONTROL: [], IDX_DOUBLED: [],
	IDX_BOW_CONTROL: [], IDX_BOW_DOUBLED: [], IDX_HALVED: [],
}

## The arms, in report order: `[slot, name]`.
const _ARMS := [
	[IDX_CONTROL, "Control"], [IDX_DOUBLED, "Doubled"],
	[IDX_BOW_CONTROL, "BowControl"], [IDX_BOW_DOUBLED, "BowDoubled"],
	[IDX_HALVED, "Halved"],
]

## How far below its control gap a doubled arm's added recovery may fall before
## the arm reds, and IT HAS A MEASURED WINDOW OF [3, 6] rather than a comfortable
## margin — so it is written down instead of tuned by feel.
##
## `added` is the arm's own unlevered period; its control gap is that period plus
## a fixed dispatch overhead, measured here at **2** ticks for a sword (38-frame
## SEQ, 40-tick gap) and **3** for a bow (56-tick period, 59-tick gap). So the
## floor of the window is 3: any less and the honest bow arm reds.
##
## The ceiling is 6, and that is what the constant is really for. The failure it
## must catch is scaling a bow's 52-frame ANIMATION instead of its 56-tick
## PERIOD, which lands `added` at 52 against a 59 control — a 7-tick shortfall.
## At 7 or more this assertion stops discriminating and the ranged arms become
## decoration.
##
## 5 sits in the middle. ⚠️ MOVING THE ARCHERS MOVES THIS: the discrimination gap
## IS `period - animation`, which is `max(0, 26 + dist * 10 - 52)`, so at distance
## 2 it collapses to zero and no slack works at all.
const _OVERHEAD_SLACK := 5
var _asserts := 0
var _failed := false


func _ready() -> void:
	# Long enough for several swings on the SLOWEST arm (a doubled 38-tick base
	# is 76 plus overhead), short enough to stay a bounded test. The dummy cannot
	# die, so TIMEOUT is the expected and only exit.
	max_ticks = 900
	super()


func get_test_name() -> String:
	return "Attack Period Test"


func _attacker(nm: String, x: int, z: int, q8: int) -> Dictionary:
	return {
		"name": nm,
		"pos_x": x, "pos_z": z,
		"hp": 9999, "max_hp": 9999,
		"pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1,
		"weapon_flags": WEAPON_FLAGS_DIRECT,
		"weapon_type": MELEE_WEAPON_TYPE,
		"weapon_id": BROAD_SWORD,
		"attack_period_factor_q8": q8,
		"body_sprite_id": 0x02,
	}


func _archer(nm: String, x: int, z: int, q8: int) -> Dictionary:
	var cfg := _attacker(nm, x, z, q8)
	cfg["weapon_type"] = BOW_WEAPON_TYPE
	cfg["weapon_id"] = LONG_BOW
	cfg["weapon_range"] = BOW_RANGE
	return cfg


func get_team0_unit_configs() -> Array:
	# The melee arms take orthogonal neighbours of the dummy at (2, 2) so both are
	# in range on tick one and neither has to path anywhere — a unit that walks is
	# a unit whose gaps include travel.
	# ⚠️ FOUR, AND FOUR IS THE CAP. A fifth is dropped silently.
	# The archers stand at the SAME distance 3 and beside each other, because a
	# ranged period carries `max(dist * 10, 15)` flight ticks — two archers at
	# different ranges would differ in two variables instead of one. Distance 3
	# and not 5 for a measured reason: at 4 one archer failed
	# `has_line_of_sight_direct` on this procedural map and walked a tile, which
	# put travel inside its gaps while the other's stayed clean.
	return [
		_attacker("Control", 1, 2, Q8_ONE),
		_attacker("Doubled", 3, 2, Q8_DOUBLE),
		_archer("BowControl", 1, 4, Q8_ONE),
		_archer("BowDoubled", 3, 4, Q8_DOUBLE),
	]


func get_team1_unit_configs() -> Array:
	# The dummy must survive the whole budget: a death would end the battle and
	# truncate the arms at different swing counts. `pa`/`wp` 1 against 9999 HP
	# attackers keeps it from killing anyone either.
	#
	# `Halved` rides on TEAM 1 because team 0 is full at four. It stands adjacent
	# to `Control` and swings at it — a different target from the other arms, but
	# the same weapon, the same distance and the same tick clock, and the claim it
	# tests ("x0.5 changes nothing") needs only its own control.
	return [
		{
			"name": "Dummy",
			"pos_x": 2, "pos_z": 2,
			"hp": 999999, "max_hp": 999999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50,
			"move": 0, "jump": 3,
			"weapon_range": 1,
			"weapon_flags": WEAPON_FLAGS_DIRECT,
			"weapon_type": MELEE_WEAPON_TYPE,
			"weapon_id": BROAD_SWORD,
			"body_sprite_id": 0x05,
		},
		_attacker("Halved", 0, 2, Q8_HALF),
	]


func on_state_changed(unit_idx: int, old_state: int, new_state: int) -> void:
	if new_state != GPUConstants.LOGICAL_ACTIVITY_ACTING:
		return
	if old_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		return
	if not _acting_ticks.has(unit_idx):
		return
	_acting_ticks[unit_idx].append(combat_loop.current_tick)


func _ok(condition: bool, message: String) -> void:
	_asserts += 1
	if not condition:
		_failed = true
		print("[FAIL] %s" % message)


## Gaps between consecutive swing starts. The FIRST gap is dropped: the opening
## swing begins from a standing start whose lead-in is not the period.
func _gaps(idx: int) -> Array:
	var ticks: Array = _acting_ticks[idx]
	var out := []
	for i in range(1, ticks.size()):
		out.append(ticks[i] - ticks[i - 1])
	if not out.is_empty():
		out.pop_front()
	return out


## The modal gap, not the mean: a single interrupted swing (a reaction, a
## re-target) would drag a mean and leave a mode alone.
func _modal_gap(idx: int) -> int:
	var counts := {}
	var best := -1
	var best_n := 0
	for g in _gaps(idx):
		counts[g] = int(counts.get(g, 0)) + 1
		if counts[g] > best_n:
			best_n = counts[g]
			best = g
	return best


## 🔴 BOTH EXITS REPORT, AND THIS TEST QUITS ITSELF.
##
## The first version reported only from `_on_loop_timed_out` and let the base
## class quit. `check_test_charter` refused it on clause 4 — *"never calls
## .quit()"* — and it was right for a reason beyond the letter: the dummy is not
## SUPPOSED to die, but "not supposed to" is an assumption about the very
## mechanism under test. If a levered arm ever ran fast enough to kill it, the
## battle would end through `victory` instead, `_report` would never run, and the
## scene would exit with NO VERDICT — the outcome that looks least like a bug and
## is worst to have.
var _reported := false


func _report_once() -> void:
	if _reported:
		return
	_reported = true
	_report()
	get_tree().quit()


func _on_loop_timed_out(_tick: int) -> void:
	_report_once()


func on_victory(_winning_team: int) -> void:
	# Reaching here at all means the dummy died, which the arms' assertions will
	# already have caught as a truncated swing count. Report anyway rather than
	# exiting silently.
	_report_once()



func _report() -> void:
	var states: Array = combat_loop.gpu_state_reader.get_all_unit_states() \
		if combat_loop != null and combat_loop.gpu_state_reader != null else []

	# 🔴 NAME THE SUBJECT BEFORE TIMING IT. The first version of this test read
	# the dummy's gaps as a bow's, because a fifth team-0 unit is dropped without
	# an error and its slot index silently belongs to somebody else. Every arm now
	# proves which unit it measured.
	_check_subject(states, IDX_CONTROL, "Control", MELEE_WEAPON_TYPE, Q8_ONE)
	_check_subject(states, IDX_DOUBLED, "Doubled", MELEE_WEAPON_TYPE, Q8_DOUBLE)
	_check_subject(states, IDX_BOW_CONTROL, "BowControl", BOW_WEAPON_TYPE, Q8_ONE)
	_check_subject(states, IDX_BOW_DOUBLED, "BowDoubled", BOW_WEAPON_TYPE, Q8_DOUBLE)
	_check_subject(states, IDX_HALVED, "Halved", MELEE_WEAPON_TYPE, Q8_HALF)

	for arm in _ARMS:
		var idx: int = arm[0]
		var st: Dictionary = states[idx] if idx < states.size() else {}
		print("[AttackPeriod] %-11s slot=%d wt=%s q8=%s swings=%d gaps=%s" % [
			arm[1], idx, str(st.get("weapon_type")), str(st.get("attack_period_factor_q8")),
			_acting_ticks[idx].size(), str(_gaps(idx))])

	# 🔴 THE INSTRUMENT'S OWN POSITIVE CONTROL. Every assertion below is about
	# gaps, and a unit that never acted has none — which would read as a clean
	# pass on an empty register. Three entries is the minimum that leaves one
	# usable gap after the opener is dropped.
	for arm in _ARMS:
		_ok(_acting_ticks[arm[0]].size() >= 3,
			"%s entered ACTING %d times in %d ticks — fewer than 3 leaves no gap, so this arm examined nothing" % [
				arm[1], _acting_ticks[arm[0]].size(), max_ticks])

	var control := _modal_gap(IDX_CONTROL)
	var doubled := _modal_gap(IDX_DOUBLED)
	var halved := _modal_gap(IDX_HALVED)
	var bow_control := _modal_gap(IDX_BOW_CONTROL)
	var bow_doubled := _modal_gap(IDX_BOW_DOUBLED)

	if control <= 0 or doubled <= 0 or halved <= 0 or bow_control <= 0 or bow_doubled <= 0:
		_ok(false, "an arm produced no usable gap (%d/%d/%d/%d/%d) — nothing below is measurable" % [
			control, doubled, halved, bow_control, bow_doubled])
		_verdict(control, doubled, halved, bow_control, bow_doubled)
		return

	# THE FLOOR. x0.5 must be indistinguishable from x1.0 — there is no shorter
	# SEQ to play, and `max(0, levered - rom)` is what says so.
	_ok(halved == control,
		"a x0.5 factor changed the realised period: halved=%d control=%d — the unlevered period is supposed to be the floor" % [
			halved, control])

	# THE LEVER, on melee and then on ranged. Each is asserted against its OWN
	# control, and on the DIFFERENCE, which cancels the fixed dispatch overhead
	# both members of a pair pay.
	_assert_doubling("sword", control, doubled)
	# A bow's period must be strictly longer than a sword's; if it is not, the
	# archers are not firing from range and the arm below is noise.
	_ok(bow_control > control,
		"the un-levered BOW gap (%d) is not longer than the un-levered SWORD gap (%d) — the archers are not firing from range" % [
			bow_control, control])
	_assert_doubling("bow", bow_control, bow_doubled)

	_verdict(control, doubled, halved, bow_control, bow_doubled)


## x2.0 owes one more base period. `added` is therefore the arm's own unlevered
## period, which is its control's gap less the fixed dispatch overhead — so it
## must be close to the control gap from below, and never above it.
func _assert_doubling(what: String, control: int, doubled: int) -> void:
	var added := doubled - control
	_ok(added > 0,
		"x2.0 on a %s added %d ticks — the lever did not reach the kernel at all" % [what, added])
	_ok(added <= control,
		"x2.0 on a %s added %d ticks against a control gap of %d — recovery is one period, never more" % [
			what, added, control])
	_ok(added >= control - _OVERHEAD_SLACK,
		"x2.0 on a %s added only %d ticks against a control gap of %d — short of one whole period (for a bow that is the ANIMATION being scaled instead of the PERIOD)" % [
			what, added, control])


func _check_subject(states: Array, idx: int, nm: String, want_wt: int, want_q8: int) -> void:
	var st: Dictionary = states[idx] if idx < states.size() else {}
	_ok(int(st.get("weapon_type", -1)) == want_wt,
		"slot %d (%s) holds weapon_type %s, expected %d — this arm is measuring the wrong unit" % [
			idx, nm, str(st.get("weapon_type")), want_wt])
	_ok(int(st.get("attack_period_factor_q8", -1)) == want_q8,
		"slot %d (%s) holds attack_period_factor_q8 %s, expected %d — the lever did not reach the buffer" % [
			idx, nm, str(st.get("attack_period_factor_q8")), want_q8])


func _verdict(control: int, doubled: int, halved: int, bow_control: int, bow_doubled: int) -> void:
	if _asserts == 0 or _failed:
		print("[FAIL] Attack Period: %d assertions, at least one red" % _asserts)
	else:
		print("[PASS] Attack Period: %d assertions — sword %d -> %d (+%d), halved %d; bow %d -> %d (+%d)" % [
			_asserts, control, doubled, doubled - control, halved,
			bow_control, bow_doubled, bow_doubled - bow_control])
