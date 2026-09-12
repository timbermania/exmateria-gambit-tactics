class_name GambitAssertions
extends RefCounted

## Predicate library for the gambit scenario suite. Pure functions over
## (trace, final_state, team_of_unit) — no side effects, no Godot scene
## dependencies, no shader-side reads. Each predicate returns
## [code]{ok: bool, name: String, detail: String}[/code]. The [code]name[/code]
## is the canonical string used by [code]xfail[/code] entries to mark this
## specific expectation as expected-to-fail.
##
## See [code]docs/gambit-rules.md[/code] for the rule list each predicate
## encodes. Tracer-bullet vocabulary (issue #57):
## - outcome.winner
## - by_tick(T): unit('X').committed(ACTION_Y)
## - no_stuck(unit='X', max_idle_ticks=N, given='any_enemy_alive')
## - gambit_fired_at_slot(unit='X', slot=N)
## - no_safety_net_hit(unit='X') — ADR-0048: the unit reaches an AUTHORED
##   gambit and never commits from the injected safety-net slot. "Always hits
##   the safety net" = its authored gambits are all dead (an authoring bug).
##   Scenarios that intentionally route to the safety net omit this / xfail it.
## - damage_dealt_to(target='X', by_tick=N) — B7 pass-2 rank-pivot witness.
## - aoe_hits(expected_targets=[...], not_targets=[...], by_tick=N) — I1/I2
##   witness for "AoE ability with effect_area > 0 hits every unit in radius."
##   Walks hp_events: every expected_target must have at least one negative
##   delta (or DIED event) by by_tick; every not_target must NOT.
## - healing_applied_to(target='X', by_tick=N) — I2's positive-half witness
##   for "Healing AoE filters to allies only" — at least one positive hp_event
##   on the target. Damage events use damage_dealt_to; healing is the
##   inverse, so a separate predicate keeps the sign-direction explicit.
##   With [code]expect_no_heal: true[/code] the predicate inverts to "no
##   positive-delta hp_event on the target by [code]by_tick[/code]" — the
##   heal-the-foe diagnostic that pairs with damage_dealt_to expect_no_damage
##   for an "in-radius wrong-team unit" not_target check.
## - revived(target='X', by_tick=N) — F7 witness for "a cancel-Dead ability
##   lands on a KO'd unit." Walks per_tick_snapshots for the FLAG_DEAD bit:
##   the target must be observed DEAD and then, later, NOT dead with hp > 0.
##   Deliberately not an hp_event check — a heal delta says an HP write
##   happened, which is exactly what a Cure at a corpse would also say if the
##   guards ever let one through. The flag is the thing under test.
##   With [code]expect_no_revive: true[/code] it inverts. Either way the
##   predicate FAILS LOUD when the target never died at all, because a
##   never-killed unit makes the negative arm pass for the wrong reason.
## - aoe_stamps_differ(targets=[...]) — I3 witness for the per-target
##   cinematic AoE stamp. cast_cinematic_spell (stage_spell.glsl :545-548)
##   writes U_AOE_PENDING_FIRE_FRAME = first_hit_frame + N * for_each_delay
##   per target, so the orchestrator fires damage at distinct cinematic-
##   timer values. Walks per_tick_snapshots, finds a snapshot where every
##   listed target has aoe_pending_fire_frame >= 0 (mid-cinematic, pre-
##   fire), and asserts the stamps differ across targets — the load-bearing
##   half of the rule. The "fires at the right tick" half is structurally
##   invisible to the host-frame sampler because for_each_delay is 1 PSX
##   frame across all 401 effect timelines and the runner samples at
##   host-frame rate (4 IRQ ticks/frame at test_time_scale = 4.0), so 3
##   consecutive-tick fires fold to one observed tick.
## - cinematic_lifecycle(caster='X', non_caster='Y', by_tick=N) — J1+J3
##   witness. Walks per_tick_snapshots: finds at least one snapshot where
##   cinematic_caster_idx == caster_idx AND non_caster.paused >= 1 (J1
##   "non-caster paused during cinematic"; ref-count >= 1 covers multi-
##   cinematic scenarios where this non-caster is paused by 2+ casters at
##   once); then finds a LATER snapshot where non_caster.paused == 0 (J3
##   "teardown clears U_PAUSED"). J2 (caster's
##   stage continues so the cinematic ends at all) is implicit: if the
##   cinematic never teared down, the J3 half would never fire.
## - position.reached_within(unit='X', target='Y', max_dist=N, by_tick=N) — F4 MOVE_TO_UNIT witness.
## - position.stayed_at(unit='X', tile=[x,z], by_tick=N) — F6 WAIT witness.
## - passes_through(unit='X', ally_tile=[x,z], by_tick=N) — G4/G5 pass-through
##   witness. Detects the per-tick Manhattan-≥2 position jump that
##   `find_passthrough_destination` emits when it skips over an allied
##   occupant. `expect_no_pass: true` inverts the check (G5 fails-closed).
## - no_thrash(unit='X', by_tick=N) — G7/H6 retry-without-thrash witness.
##   Reads the shader's `decision_meta` thrash_flag bit (set by
##   `check_decision_thrash` when the 6-entry ring buffer shows a stuck-target
##   or repeat-decision pattern) and asserts the bit never flipped on for the
##   named unit within the window.
## - state_inhibited(unit='X', during_state='SPELL_CHARGING') — H1-H5 witness
##   for "unit in <state> does not re-evaluate gambits." Walks `state_events`
##   for the unit, finds the first entry into during_state, and verifies the
##   NEXT state_event is a natural exit (prev == during_state) WITHOUT a new
##   `current_gambit` slot being written during the window. A re-eval that
##   committed a new action would either inject an intermediate state event
##   with prev != during_state OR carry a different current_gambit at exit;
##   both modes are caught.
## - returns_to_idle(unit='X', after_state='ACTING', within_ticks=N) — H7
##   witness for post-action IDLE return. After the unit first enters
##   after_state, the unit must reach IDLE within `within_ticks` (counted
##   from after_state ENTRY tick to IDLE entry tick, inclusive of any
##   AWAITING_IMPACT tail).
## - cooldown_respected(unit='X', ability=N, min_spacing=M, min_casts=K) —
##   B8 witness for "Action is on cooldown -> fall through." Walks
##   `cast_events` for (unit, ability); asserts (1) at least min_casts events
##   fired (need >=2 to witness a gap), (2) every consecutive pair's tick
##   gap is >= min_spacing. Without the cooldown veto, a CT=0 0-MP ability
##   re-fires as fast as its cast animation + TICKS_GAMBIT_REEVAL allow,
##   blowing the spacing check on the very first pair.

const ACTING_STATES := [
	GPUConstants.LOGICAL_ACTIVITY_ACTING,
	GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING,
]

const ACTIVE_STATES := [
	GPUConstants.LOGICAL_ACTIVITY_ACTING,
	GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING,
	GPUConstants.LOGICAL_ACTIVITY_WALKING,
	GPUConstants.LOGICAL_ACTIVITY_WALKING_TO_CAST,
	GPUConstants.LOGICAL_ACTIVITY_APPROACHING,
	GPUConstants.LOGICAL_ACTIVITY_AWAITING_IMPACT,
]


## Evaluate every expectation in [code]expect[/code]; return an array of
## per-expectation result dicts.
static func evaluate(expect: Dictionary, trace: GambitTraceLogger, team_of: Dictionary) -> Array:
	var results: Array = []
	if expect.has("outcome"):
		results.append(_check_outcome(expect["outcome"], trace))
	for ex in expect.get("trace", []):
		results.append(_check_trace(ex, trace))
	for ex in expect.get("liveness", []):
		results.append(_check_liveness(ex, trace, team_of))
	for ex in expect.get("gambit_slot", []):
		results.append(_check_gambit_slot(ex, trace))
	for ex in expect.get("no_safety_net_hit", []):
		results.append(_check_no_safety_net_hit(ex, trace))
	for ex in expect.get("no_commit_at_slot", []):
		results.append(_check_no_commit_at_slot(ex, trace))
	for ex in expect.get("damage", []):
		results.append(_check_damage_dealt_to(ex, trace))
	for ex in expect.get("aoe_hits", []):
		results.append(_check_aoe_hits(ex, trace))
	for ex in expect.get("healing", []):
		results.append(_check_healing_applied_to(ex, trace))
	for ex in expect.get("revived", []):
		results.append(_check_revived(ex, trace))
	for ex in expect.get("aoe_stamps_differ", []):
		results.append(_check_aoe_stamps_differ(ex, trace))
	for ex in expect.get("cinematic_lifecycle", []):
		results.append(_check_cinematic_lifecycle(ex, trace))
	for ex in expect.get("position", []):
		results.append(_check_position(ex, trace))
	for ex in expect.get("passes_through", []):
		results.append(_check_passes_through(ex, trace))
	for ex in expect.get("no_thrash", []):
		results.append(_check_no_thrash(ex, trace))
	for ex in expect.get("state_inhibited", []):
		results.append(_check_state_inhibited(ex, trace))
	for ex in expect.get("returns_to_idle", []):
		results.append(_check_returns_to_idle(ex, trace))
	for ex in expect.get("cooldown", []):
		results.append(_check_cooldown_respected(ex, trace))
	for ex in expect.get("alternates_with", []):
		results.append(_check_alternates_with(ex, trace))
	return results


# ---- outcome -----------------------------------------------------------------

static func _check_outcome(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var expected: int = spec.get("winner", -2)
	var ok: bool = trace.winner == expected
	var detail := "winner=%d (expected %d)" % [trace.winner, expected]
	return {"ok": ok, "name": "outcome.winner", "detail": detail}


# ---- trace.by_tick(T): unit('X').committed(...) -----------------------------

static func _check_trace(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	# Tracer-bullet form for #57: by_tick committed.
	# spec = {kind: "by_tick", tick: T, unit: "Monk", committed: "ATTACK"}
	var unit_name: String = spec.get("unit", "")
	var tick_limit: int = spec.get("tick", 0)
	var committed: String = spec.get("committed", "")
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "by_tick(%d): unit('%s').committed(%s)" % [tick_limit, unit_name, committed]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}

	# Walk events in order; pick the FIRST commit that matches the kind.
	var first_match_tick: int = -1
	for ev in trace.cast_events:
		if ev["unit"] == unit_idx and ev["tick"] <= tick_limit:
			if committed == "SPELL" or committed == "ABILITY" or committed == "ACTION_SPELL":
				first_match_tick = ev["tick"]
				break
	if first_match_tick < 0:
		for ev in trace.state_events:
			if ev["unit"] != unit_idx:
				continue
			if ev["tick"] > tick_limit:
				break
			if ev["new"] == GPUConstants.LOGICAL_ACTIVITY_ACTING:
				if committed == "ATTACK" or committed == "ACTION_ATTACK" or committed == "ACTION_ANY":
					first_match_tick = ev["tick"]
					break
	var ok := first_match_tick >= 0
	var detail := "first commit at tick %d" % first_match_tick if ok else "no commit by tick %d (final_tick=%d)" % [tick_limit, trace.final_tick]
	return {"ok": ok, "name": name_str, "detail": detail}


# ---- liveness.no_stuck(unit='X', max_idle_ticks=N, given='...') ------------

static func _check_liveness(spec: Dictionary, trace: GambitTraceLogger, team_of: Dictionary) -> Dictionary:
	# spec = {kind: "no_stuck", unit: "Monk", max_idle_ticks: 10, given: "any_enemy_alive"}
	var unit_name: String = spec.get("unit", "")
	var max_idle: int = spec.get("max_idle_ticks", 10)
	var given: String = spec.get("given", "any_enemy_alive")
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "no_stuck(unit='%s', max_idle_ticks=%d, given='%s')" % [unit_name, max_idle, given]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}

	# Find the longest run of idle ticks while `given` holds.
	var longest_run: int = 0
	var current_run: int = 0
	var run_start_tick: int = -1
	var worst_start: int = -1
	for snap in trace.per_tick_snapshots:
		var units_snap: Array = snap["units"]
		if unit_idx >= units_snap.size():
			continue
		var u: Dictionary = units_snap[unit_idx]
		var dead: bool = (int(u["flags"]) & CombatHost.GPU_FLAGS_DEAD_BIT) != 0
		if dead:
			current_run = 0
			run_start_tick = -1
			continue
		# `given` evaluation
		var given_holds: bool = true
		if given == "any_enemy_alive":
			given_holds = trace.count_alive_enemies(unit_idx, team_of, snap) > 0
		if not given_holds:
			current_run = 0
			run_start_tick = -1
			continue
		# idle = state == IDLE
		if int(u["state"]) == GPUConstants.LOGICAL_ACTIVITY_IDLE:
			if current_run == 0:
				run_start_tick = snap["tick"]
			current_run += 1
			if current_run > longest_run:
				longest_run = current_run
				worst_start = run_start_tick
		else:
			current_run = 0
			run_start_tick = -1
	var ok := longest_run <= max_idle
	var detail := "longest_idle_run=%d (max %d); worst run started tick %d" % [longest_run, max_idle, worst_start]
	return {"ok": ok, "name": name_str, "detail": detail}


# ---- damage.damage_dealt_to(target='X', by_tick=N) --------------------------

static func _check_damage_dealt_to(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	# Asserts that [code]target[/code] took at least one damaging hp_event
	# (delta < 0) at or before [code]by_tick[/code]. Used by B7 to witness the
	# pass-2 rank pivot — when slot 0's condition fails on the rank-0 nearest
	# enemy, pass 2 retries with rank 1 and the action lands on that unit,
	# so the rank-1 unit (not rank-0) is the first to take damage.
	#
	# With [code]expect_no_damage: true[/code] the predicate inverts to "the
	# named unit must NOT take damage by [code]by_tick[/code]" — useful as a
	# diagnostic counter-assertion (B7's pass-2 retry: rank-0 enemy must NOT
	# be the one that takes the hit).
	var target_name: String = spec.get("target", "")
	var tick_limit: int = spec.get("by_tick", 0)
	var expect_none: bool = bool(spec.get("expect_no_damage", false))
	var target_idx: int = trace.unit_index(target_name)
	var name_str := "%s(target='%s', by_tick=%d)" % [
			"no_damage_dealt_to" if expect_none else "damage_dealt_to",
			target_name, tick_limit]
	if target_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % target_name}
	var first_hit_tick: int = -1
	var first_hit_delta: int = 0
	for ev in trace.hp_events:
		if ev["unit"] != target_idx:
			continue
		if ev["tick"] > tick_limit:
			break
		if int(ev["delta"]) < 0:
			first_hit_tick = ev["tick"]
			first_hit_delta = int(ev["delta"])
			break
	# One-shot kills are emitted as a single DIED event by the combat
	# interpreter (see [code]GPUCombatInterpreter.interpret[/code] death
	# precedence: a newly-dead unit emits only DIED; HP_CHANGED is
	# suppressed). For "did damage land?" purposes, a death IS evidence of
	# damage having landed — fold death_events into the check so a B7-style
	# pivot to a low-HP target that one-shots it still counts as "damage
	# dealt." Heals can't trigger death so there's no risk of a false
	# positive.
	if first_hit_tick < 0:
		for dev in trace.death_events:
			if dev["unit"] != target_idx:
				continue
			if dev["tick"] > tick_limit:
				break
			first_hit_tick = dev["tick"]
			first_hit_delta = 0  # death event carries no delta
			break
	if expect_none:
		if first_hit_tick < 0:
			return {"ok": true, "name": name_str,
					"detail": "no damaging hp_event for '%s' by tick %d (as expected)" % [target_name, tick_limit]}
		return {"ok": false, "name": name_str,
				"detail": "expected no damage but '%s' took delta=%d at tick %d" % [
						target_name, first_hit_delta, first_hit_tick]}
	if first_hit_tick >= 0:
		return {"ok": true, "name": name_str,
				"detail": "first damaging hit at tick %d (delta=%d)" % [first_hit_tick, first_hit_delta]}
	# Dump observed hp_events so a failure shows whether damage went to a
	# different unit (e.g. pass-2 not firing → rank-0 took the hit instead).
	var observed: Array = []
	for ev in trace.hp_events:
		observed.append("tick=%d unit=%d(%s) delta=%d" % [
				ev["tick"], ev["unit"], trace.unit_name(ev["unit"]), ev["delta"]])
	return {"ok": false, "name": name_str,
			"detail": "no damaging hp_event for '%s' by tick %d (observed: %s)" % [
					target_name, tick_limit, ", ".join(observed) if observed.size() > 0 else "none"]}


# ---- gambit_fired_at_slot(unit='X', slot=N) ---------------------------------

static func _check_gambit_slot(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	# Asserts that when this unit first committed an action, the GPU's
	# current_gambit was the expected slot. Slot ordering rule A1.
	var unit_name: String = spec.get("unit", "")
	var expected_slot: int = spec.get("slot", 0)
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "gambit_fired_at_slot(unit='%s', slot=%d)" % [unit_name, expected_slot]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}
	var commit = trace.first_commit.get(unit_idx, null)
	if commit == null:
		return {"ok": false, "name": name_str, "detail": "unit never committed"}
	var actual_slot: int = commit["slot"]
	var ok: bool = actual_slot == expected_slot
	var detail := "first commit at tick %d slot %d (expected %d)" % [commit["tick"], actual_slot, expected_slot]
	# WHAT it aimed at, not just WHEN it fired. A slot-only report cannot tell a cast at
	# the corpse the slot was authored for from a cast at some other candidate entirely —
	# and #1113 spent a diagnosis round on exactly that ambiguity.
	for ev in trace.cast_events:
		if int(ev["unit"]) != unit_idx:
			continue
		if int(ev["tick"]) < int(commit["tick"]):
			continue
		detail += "; first cast ability=%d target=%s at tick %d" % [
				int(ev["ability_id"]), trace.unit_name(int(ev["target"])), int(ev["tick"])]
		break
	return {"ok": ok, "name": name_str, "detail": detail}


# ---- no_safety_net_hit(unit='X') --------------------------------------------

static func _check_no_safety_net_hit(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	# ADR-0048 regression guard: over the whole trace, the unit never COMMITS an
	# action from the injected safety-net slot (GPUConstants.MAX_USER_GAMBITS).
	# If every-authored-slot-dead is the only reason a unit acts, that is an
	# authoring bug the safety net would otherwise mask. Walks the discrete
	# action-commit witness so host-frame sampling can't hide a fallback commit.
	var unit_name: String = spec.get("unit", "")
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "no_safety_net_hit(unit='%s')" % unit_name
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}
	var safety_slot: int = GPUConstants.MAX_USER_GAMBITS
	for ev in trace.action_committed_events:
		if ev["unit"] == unit_idx and ev["current_gambit"] == safety_slot:
			return {
				"ok": false, "name": name_str,
				"detail": "committed from safety-net slot %d at tick %d (authored gambits never fired)" % [safety_slot, ev["tick"]],
			}
	return {"ok": true, "name": name_str, "detail": "no safety-net-slot commit across trace"}


# ---- no_commit_at_slot(unit='X', slot=N) ------------------------------------
#
# The negative twin of `gambit_fired_at_slot`: over the WHOLE trace this unit
# never commits from slot N. `gambit_fired_at_slot` can only say which slot won
# — it has no way to say a slot must LOSE, which is what a scenario proving a
# condition does not pass needs.
#
# 🔴 IT CARRIES ITS OWN POSITIVE CONTROL. A unit that committed nothing at all
# — spawned unreachable, gambit list empty, the sim never advanced — satisfies
# "never committed from slot N" vacuously, and reads identically to the real
# result. So a unit with NO commits is a FAIL, not a pass, unless the scenario
# says `allow_no_commit: true` and means it.
#
# Spec keys:
#   unit:            name of the unit
#   slot:            the slot that must never win
#   allow_no_commit: opt out of the positive control (default false)
static func _check_no_commit_at_slot(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var unit_name: String = spec.get("unit", "")
	var slot: int = spec.get("slot", 0)
	var allow_no_commit: bool = spec.get("allow_no_commit", false)
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "no_commit_at_slot(unit='%s', slot=%d)" % [unit_name, slot]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}
	var commits: int = 0
	for ev in trace.action_committed_events:
		if ev["unit"] != unit_idx:
			continue
		commits += 1
		if ev["current_gambit"] == slot:
			return {
				"ok": false, "name": name_str,
				"detail": "committed from slot %d at tick %d" % [slot, ev["tick"]],
			}
	if commits == 0 and not allow_no_commit:
		return {
			"ok": false, "name": name_str,
			"detail": "'%s' committed NOTHING across the trace — this assertion would pass"
					% unit_name
					+ " vacuously, so it is scored blind rather than green",
		}
	return {"ok": true, "name": name_str,
			"detail": "%d commits, none from slot %d" % [commits, slot]}


# ---- aoe_hits(expected_targets=[...], not_targets=[...], by_tick=N) ---------
#
# I1/I2 witness for "AoE ability with effect_area > 0 hits every unit in
# radius (and only those units)." Both halves walk the same hp_event /
# death_event streams that `damage_dealt_to` uses, but evaluated as a SET so
# a single spec covers an N-target hit pattern.
#
# A negative delta on an expected target counts as a hit; so does a DIED
# event (the combat interpreter folds the killing blow into DIED, suppressing
# HP_CHANGED — same precedence rule the single-target predicate handles).
# A positive delta is NOT a hit (healing); the not_targets check rejects only
# negative deltas / deaths, so a healed unit in not_targets still passes.
#
# Spec keys:
#   expected_targets: array of unit names; each must take damage by by_tick.
#   not_targets:      array of unit names; none may take damage by by_tick.
#   by_tick:          tick limit; events strictly after this are ignored.
static func _check_aoe_hits(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var expected: Array = spec.get("expected_targets", [])
	var not_expected: Array = spec.get("not_targets", [])
	var by_tick: int = spec.get("by_tick", 0)
	var name_str := "aoe_hits(expected=%s, not_targets=%s, by_tick=%d)" % [
			str(expected), str(not_expected), by_tick]

	# Fail-closed on a spec error rather than vacuous-pass: an aoe_hits with
	# no expected targets is structurally a typo, not a meaningful witness.
	# The collateral (not_targets) check on its own is what damage_dealt_to
	# expect_no_damage already covers — aoe_hits is specifically the
	# "set-shaped positive witness."
	if expected.is_empty():
		return {"ok": false, "name": name_str,
				"detail": "aoe_hits needs at least 1 expected target, got 0"}

	var missing: Array = []
	for unit_name in expected:
		var idx: int = trace.unit_index(unit_name)
		if idx < 0:
			missing.append("'%s' (unknown unit)" % unit_name)
			continue
		if not _unit_was_damaged_by(trace, idx, by_tick):
			missing.append("'%s'" % unit_name)
	var collateral: Array = []
	for unit_name in not_expected:
		var idx: int = trace.unit_index(unit_name)
		if idx < 0:
			collateral.append("'%s' (unknown unit)" % unit_name)
			continue
		if _unit_was_damaged_by(trace, idx, by_tick):
			collateral.append("'%s'" % unit_name)
	if missing.is_empty() and collateral.is_empty():
		return {"ok": true, "name": name_str,
				"detail": "all %d expected targets damaged by tick %d; %d not_targets untouched" % [
						expected.size(), by_tick, not_expected.size()]}
	var bits: Array = []
	if not missing.is_empty():
		bits.append("missing damage on: %s" % ", ".join(missing))
	if not collateral.is_empty():
		bits.append("unexpected damage on: %s" % ", ".join(collateral))
	return {"ok": false, "name": name_str, "detail": "; ".join(bits)}


# True iff [code]unit_idx[/code] had a negative-delta hp_event or a death_event
# at or before [code]by_tick[/code]. Same fold-DIED-into-damaged precedence
# rule [code]_check_damage_dealt_to[/code] uses.
static func _unit_was_damaged_by(trace: GambitTraceLogger, unit_idx: int, by_tick: int) -> bool:
	for ev in trace.hp_events:
		if ev["unit"] != unit_idx:
			continue
		if ev["tick"] > by_tick:
			break
		if int(ev["delta"]) < 0:
			return true
	for dev in trace.death_events:
		if dev["unit"] != unit_idx:
			continue
		if dev["tick"] > by_tick:
			break
		return true
	return false


# ---- healing_applied_to(target='X', by_tick=N) ------------------------------
#
# I2 positive-half witness for "healing AoE filters to allies." A heal lands
# as a positive-delta hp_event on the target (instant path) — or, on the
# cinematic path, as a positive hp_event when the orchestrator fires at
# first_hit_frame + N * for_each_delay. Either way the surface is the same.
#
# With [code]expect_no_heal: true[/code] the predicate inverts to "the named
# unit must NOT receive a positive-delta hp_event by [code]by_tick[/code]" —
# the heal-the-foe diagnostic counter-assertion. Note: a heal that clamps to
# max_hp produces no HP_CHANGED event at all (delta=0), so the no-heal
# witness is fully observable only against a target at less-than-max HP.
# Use against the matching expect_no_damage check on the same unit so the
# pair (no_damage, no_heal) decisively pins "this unit was not affected by
# the AoE."
#
# Spec keys:
#   target:         name of the unit that should be healed
#   by_tick:        tick limit; events strictly after this are ignored
#   expect_no_heal: optional bool, default false. When true, predicate
#                   passes iff no positive-delta hp_event was observed.
static func _check_healing_applied_to(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var target_name: String = spec.get("target", "")
	var tick_limit: int = spec.get("by_tick", 0)
	var expect_none: bool = bool(spec.get("expect_no_heal", false))
	var target_idx: int = trace.unit_index(target_name)
	var name_str := "%s(target='%s', by_tick=%d)" % [
			"no_healing_applied_to" if expect_none else "healing_applied_to",
			target_name, tick_limit]
	if target_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % target_name}
	var first_heal_tick: int = -1
	var first_heal_delta: int = 0
	for ev in trace.hp_events:
		if ev["unit"] != target_idx:
			continue
		if ev["tick"] > tick_limit:
			break
		if int(ev["delta"]) > 0:
			first_heal_tick = ev["tick"]
			first_heal_delta = int(ev["delta"])
			break
	if expect_none:
		if first_heal_tick < 0:
			return {"ok": true, "name": name_str,
					"detail": "no positive-delta hp_event for '%s' by tick %d (as expected)" % [
							target_name, tick_limit]}
		return {"ok": false, "name": name_str,
				"detail": "expected no heal but '%s' took delta=+%d at tick %d" % [
						target_name, first_heal_delta, first_heal_tick]}
	if first_heal_tick >= 0:
		return {"ok": true, "name": name_str,
				"detail": "first heal at tick %d (delta=+%d)" % [first_heal_tick, first_heal_delta]}
	return {"ok": false, "name": name_str,
			"detail": "no positive-delta hp_event for '%s' by tick %d" % [target_name, tick_limit]}


# ---- revived(target='X', by_tick=N) -----------------------------------------
#
# F7 witness (#1113): an ability whose ROM inflict list names `Dead` under mode
# `cancel` lands on a KO'd unit and brings it back.
#
# 🔴 THE ASSERTION IS THE FLAG, NOT THE HP DELTA. Every other half-fix in this
# area writes HP — `apply_heal_to_target` writes HP at a corpse today and the
# unit stays dead, because `is_unit_dead` reads FLAG_DEAD in the unit flag word
# and nothing else. A predicate keyed on a positive hp_event would go green on
# that half-fix. So this one reads `flags` out of the per-tick snapshot and
# demands the transition DEAD -> NOT DEAD, with hp > 0 on the far side.
#
# The scenario must KILL the unit in sim — GPUCombatPacker hard-zeroes the unit
# flag word at pack time, so a corpse cannot be seeded from a unit cfg, and
# seeding the state the assertion looks for is how a fixture fakes its own
# success. That is enforced here: if the target is never observed dead, BOTH
# arms fail, because "it never died" is indistinguishable from "it was never
# revived" to any predicate that only looks at the end state.
#
# Spec keys:
#   target:           name of the unit that must come back
#   by_tick:          tick limit; snapshots strictly after this are ignored
#   expect_no_revive: optional bool, default false. When true, the predicate
#                     passes iff the target died and STAYED dead through the
#                     window — the control arm for "a plain heal is not a
#                     revive."
static func _check_revived(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var target_name: String = spec.get("target", "")
	var tick_limit: int = spec.get("by_tick", 0)
	var expect_none: bool = bool(spec.get("expect_no_revive", false))
	var target_idx: int = trace.unit_index(target_name)
	var name_str := "%s(target='%s', by_tick=%d)" % [
			"no_revive" if expect_none else "revived", target_name, tick_limit]
	if target_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % target_name}

	var died_tick: int = -1
	var revived_tick: int = -1
	var revived_hp: int = 0
	for snap in trace.per_tick_snapshots:
		if int(snap["tick"]) > tick_limit:
			break
		var units_snap: Array = snap["units"]
		if target_idx >= units_snap.size():
			continue
		var u: Dictionary = units_snap[target_idx]
		var dead: bool = (int(u.get("flags", 0)) & CombatHost.GPU_FLAGS_DEAD_BIT) != 0
		if dead:
			if died_tick < 0:
				died_tick = int(snap["tick"])
			continue
		if died_tick >= 0 and revived_tick < 0 and int(u.get("hp", 0)) > 0:
			revived_tick = int(snap["tick"])
			revived_hp = int(u.get("hp", 0))
			break

	if died_tick < 0:
		return {"ok": false, "name": name_str,
				"detail": "'%s' was never observed DEAD by tick %d — the scenario did not kill it, so neither arm of this predicate means anything" % [
						target_name, tick_limit]}
	if expect_none:
		if revived_tick < 0:
			return {"ok": true, "name": name_str,
					"detail": "died at tick %d and stayed dead through tick %d (as expected)" % [
							died_tick, tick_limit]}
		return {"ok": false, "name": name_str,
				"detail": "expected no revive but '%s' cleared FLAG_DEAD at tick %d with hp=%d" % [
						target_name, revived_tick, revived_hp]}
	if revived_tick >= 0:
		return {"ok": true, "name": name_str,
				"detail": "died at tick %d, FLAG_DEAD cleared at tick %d with hp=%d" % [
						died_tick, revived_tick, revived_hp]}
	return {"ok": false, "name": name_str,
			"detail": "'%s' died at tick %d and never came back by tick %d" % [
					target_name, died_tick, tick_limit]}


# ---- aoe_stamps_differ(targets=[...]) ---------------------------------------
#
# I3 witness for "cinematic AoE stamps U_AOE_PENDING_FIRE_FRAME per target,
# fires damage at first_hit_frame + N * for_each_delay" — the per-target
# stamp half. cast_cinematic_spell (stage_spell.glsl :545-548) writes a
# different fire_frame for each target in stamp order:
#
#   fire_frame = first_hit_frame + target_count * for_each_delay
#
# so during the cinematic window (after stamp, before fire) every listed
# target carries a DIFFERENT aoe_pending_fire_frame value. The predicate
# walks per_tick_snapshots to find the snapshot where every listed target
# has pending_fire_frame ≥ 0 (mid-cinematic, all stamps written, none fired
# yet) and asserts the stamps form a strictly-distinct set.
#
# The "fires at the right tick" half of the rule is structurally invisible
# from a host-frame sampler: every effect timeline ships for_each_delay = 1
# PSX frame, and the runner samples once per host frame which runs ~4 IRQ
# ticks at test_time_scale = 4.0. Three consecutive-IRQ-tick fires
# therefore fold to one observed tick (hp_events all carry the same
# current_tick). Witnessing the stamps catches the same regression — if the
# per-target stride collapsed, the stamps would equal — without needing the
# sub-frame timing.
#
# Spec keys:
#   targets: array of unit names; each must carry a non-negative stamp in
#            at least one snapshot, and the stamps must be pairwise distinct.
static func _check_aoe_stamps_differ(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var targets: Array = spec.get("targets", [])
	var name_str := "aoe_stamps_differ(targets=%s)" % [str(targets)]
	if targets.size() < 2:
		return {"ok": false, "name": name_str,
				"detail": "aoe_stamps_differ needs at least 2 targets, got %d" % targets.size()}
	var target_idxs: Array = []
	var missing: Array = []
	for unit_name in targets:
		var idx: int = trace.unit_index(unit_name)
		if idx < 0:
			missing.append("'%s' (unknown unit)" % unit_name)
			continue
		target_idxs.append({"name": unit_name, "idx": idx})
	if not missing.is_empty():
		return {"ok": false, "name": name_str,
				"detail": "unknown units: %s" % ", ".join(missing)}

	# Scan for the first snapshot where every target carries a non-negative
	# stamp. The orchestrator clears the stamp to -1 on fire, so a snapshot
	# with all targets ≥ 0 is by definition "mid-cinematic, pre-fire."
	for snap in trace.per_tick_snapshots:
		var units_snap: Array = snap["units"]
		var stamps: Array = []
		var all_stamped: bool = true
		for entry in target_idxs:
			var idx: int = int(entry["idx"])
			if idx >= units_snap.size():
				all_stamped = false
				break
			var v: int = int(units_snap[idx].get("aoe_pending_fire_frame", -1))
			if v < 0:
				all_stamped = false
				break
			stamps.append({"name": entry["name"], "stamp": v})
		if not all_stamped:
			continue
		# All ≥ 0; check pairwise distinctness.
		var seen: Dictionary = {}
		var dup: bool = false
		for s in stamps:
			if seen.has(s["stamp"]):
				dup = true
				break
			seen[s["stamp"]] = true
		var detail_bits: Array = []
		for s in stamps:
			detail_bits.append("%s=%d" % [s["name"], int(s["stamp"])])
		if dup:
			return {"ok": false, "name": name_str,
					"detail": "stamps not pairwise distinct at tick %d: %s" % [
							int(snap["tick"]), ", ".join(detail_bits)]}
		return {"ok": true, "name": name_str,
				"detail": "distinct stamps observed at tick %d: %s" % [
						int(snap["tick"]), ", ".join(detail_bits)]}
	return {"ok": false, "name": name_str,
			"detail": "no snapshot observed with every target carrying a non-negative aoe_pending_fire_frame (cinematic stamp never landed, or fired before being sampled)"}


# ---- cinematic_lifecycle(caster='X', non_caster='Y', by_tick=N) -------------
#
# J1+J3 witness. The cinematic-spell shader path (cast_cinematic_spell in
# stage_spell.glsl) does three observable things simultaneously when a
# charge_time > 0 spell completes its charge: sets the caster's per-unit
# U_CINEMATIC_TIMER = 0, increments U_PAUSED on every non-caster, and stamps
# AoE targets. cinematic_teardown inverts the first two when the cinematic
# ends. The trace logger samples per-unit U_PAUSED + U_CINEMATIC_TIMER each
# tick, and derives the "spotlight" cinematic_caster_idx (lowest unit_id
# with cinematic_timer >= 0) from that — issue #118 retired the battle-
# header pair. The predicate walks per_tick_snapshots and asserts:
#
#   1. Some snapshot exists where cinematic_caster_idx == caster_idx AND
#      non_caster.paused >= 1 — the J1 "non-caster paused during cinematic"
#      half. This snapshot must occur at or before by_tick. >= 1 (rather
#      than == 1) accommodates the #118 ref-count semantic: multiple
#      concurrent cinematics each increment U_PAUSED on this non-caster.
#   2. A LATER snapshot exists where non_caster.paused == 0 AND
#      cinematic_caster_idx == -1 — the J3 "teardown clears U_PAUSED" half.
#      Either before or after by_tick is fine; the predicate accepts the
#      full trace tail. The cinematic_caster_idx == -1 sub-clause pins the
#      "teardown fired" signature: cinematic_teardown decrements every
#      other unit's U_PAUSED and resets the caster's U_CINEMATIC_TIMER in
#      the same pass, so a paused=0 snapshot caused by anything else
#      (e.g., the non_caster died and death-handling zeroed U_PAUSED)
#      cannot fool the predicate.
#
# J2 ("the caster's stage_compute / stage_spell continue") is implicit: if
# the orchestrator stopped, the cinematic never ends, U_PAUSED never clears,
# and step 2 fails. A regression that paused the caster too would manifest
# as a stuck cinematic and a J3-half failure.
#
# Spec keys:
#   caster:     name of the unit that casts the cinematic spell
#   non_caster: name of a unit that should be paused during the cinematic
#   by_tick:    cinematic must START by this tick (the snapshot from step 1
#               must have tick ≤ by_tick); the unpause from step 2 may land
#               later.
static func _check_cinematic_lifecycle(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var caster_name: String = spec.get("caster", "")
	var non_caster_name: String = spec.get("non_caster", "")
	var by_tick: int = spec.get("by_tick", 1 << 30)
	var caster_idx: int = trace.unit_index(caster_name)
	var non_caster_idx: int = trace.unit_index(non_caster_name)
	var name_str := "cinematic_lifecycle(caster='%s', non_caster='%s', by_tick=%d)" % [
			caster_name, non_caster_name, by_tick]
	if caster_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown caster '%s'" % caster_name}
	if non_caster_idx < 0:
		return {"ok": false, "name": name_str,
				"detail": "unknown non_caster '%s'" % non_caster_name}

	var paused_during_tick: int = -1
	var unpaused_after_tick: int = -1
	for i in range(trace.per_tick_snapshots.size()):
		var snap: Dictionary = trace.per_tick_snapshots[i]
		var snap_tick: int = int(snap["tick"])
		var units_snap: Array = snap["units"]
		if non_caster_idx >= units_snap.size():
			continue
		var paused: int = int(units_snap[non_caster_idx].get("paused", 0))
		var cinematic_caster: int = int(snap.get("cinematic_caster_idx", -1))
		if paused_during_tick < 0:
			if snap_tick > by_tick:
				continue
			# paused is a ref-count under #118 (every cast_cinematic_spell /
			# start_reraise_cinematic increment is paired with a teardown
			# decrement). A single-cinematic J scenario lands at 1; concurrent
			# cinematics on multiple non-caster units would land at 2+. Match
			# >= 1 so future multi-cinematic J scenarios stay covered without
			# tripping a false negative.
			if cinematic_caster == caster_idx and paused >= 1:
				paused_during_tick = snap_tick
		elif unpaused_after_tick < 0:
			# Require cinematic_caster_idx == -1 alongside paused == 0 so
			# the witness is "teardown fired" specifically, not any
			# unrelated cause of paused→0 (e.g., a future scenario where
			# non_caster dies mid-cinematic and death-handling zeros
			# U_PAUSED). cinematic_teardown writes both fields in one pass
			# (stage_spell.glsl :711, :715), so the conjunction is the
			# exact teardown signature.
			if paused == 0 and cinematic_caster == -1:
				unpaused_after_tick = snap_tick
				break
	if paused_during_tick < 0:
		return {"ok": false, "name": name_str,
				"detail": "no snapshot at or before tick %d showed '%s' paused while '%s' was the cinematic caster" % [
						by_tick, non_caster_name, caster_name]}
	if unpaused_after_tick < 0:
		return {"ok": false, "name": name_str,
				"detail": "'%s' was paused at tick %d during '%s's cinematic but never returned to paused=0 (teardown never fired or U_PAUSED never cleared)" % [
						non_caster_name, paused_during_tick, caster_name]}
	return {"ok": true, "name": name_str,
			"detail": "'%s' paused at tick %d (cinematic_caster=%s); unpaused at tick %d (delta %d)" % [
					non_caster_name, paused_during_tick, caster_name,
					unpaused_after_tick, unpaused_after_tick - paused_during_tick]}


# ---- position dispatch -------------------------------------------------------
#
# Position witnesses read the per-tick snapshot ring (pos_x / pos_z), the same
# source [code]_check_liveness[/code] uses. Sub-kinds:
#   - reached_within: did [code]unit[/code] get within Manhattan [code]max_dist[/code]
#     of [code]target[/code] by tick T? (F4 MOVE_TO_UNIT witness.)
#   - stayed_at: did [code]unit[/code]'s tile stay at [code]tile=[x,z][/code]
#     through tick T? (F6 WAIT witness — "no movement" half of the rule.)

static func _check_position(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var kind: String = spec.get("kind", "")
	match kind:
		"reached_within":
			return _check_reached_within(spec, trace)
		"stayed_at":
			return _check_stayed_at(spec, trace)
		_:
			return {"ok": false, "name": "position.unknown",
					"detail": "unknown position kind '%s'" % kind}


static func _check_reached_within(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	# spec = {kind: "reached_within", unit: "Monk", target: "Knight",
	#         max_dist: 1, by_tick: 400}
	var unit_name: String = spec.get("unit", "")
	var target_name: String = spec.get("target", "")
	var max_dist: int = spec.get("max_dist", 1)
	var by_tick: int = spec.get("by_tick", 0)
	var unit_idx: int = trace.unit_index(unit_name)
	var target_idx: int = trace.unit_index(target_name)
	var name_str := "reached_within(unit='%s', target='%s', max_dist=%d, by_tick=%d)" % [
			unit_name, target_name, max_dist, by_tick]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}
	if target_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown target '%s'" % target_name}

	var closest_dist: int = 1 << 30
	var closest_tick: int = -1
	for snap in trace.per_tick_snapshots:
		if int(snap["tick"]) > by_tick:
			break
		var units_snap: Array = snap["units"]
		if unit_idx >= units_snap.size() or target_idx >= units_snap.size():
			continue
		var u: Dictionary = units_snap[unit_idx]
		var t: Dictionary = units_snap[target_idx]
		var d: int = abs(int(u["pos_x"]) - int(t["pos_x"])) + abs(int(u["pos_z"]) - int(t["pos_z"]))
		if d < closest_dist:
			closest_dist = d
			closest_tick = int(snap["tick"])
		if d <= max_dist:
			return {"ok": true, "name": name_str,
					"detail": "reached dist %d at tick %d (limit %d)" % [d, int(snap["tick"]), max_dist]}
	var detail := "closest dist %d at tick %d (needed <= %d by tick %d)" % [
			closest_dist, closest_tick, max_dist, by_tick]
	return {"ok": false, "name": name_str, "detail": detail}


static func _check_stayed_at(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	# spec = {kind: "stayed_at", unit: "Monk", tile: [4, 7], by_tick: 200}
	var unit_name: String = spec.get("unit", "")
	var tile: Array = spec.get("tile", [0, 0])
	var expected_x: int = int(tile[0]) if tile.size() >= 1 else 0
	var expected_z: int = int(tile[1]) if tile.size() >= 2 else 0
	var by_tick: int = spec.get("by_tick", 0)
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "stayed_at(unit='%s', tile=[%d,%d], by_tick=%d)" % [
			unit_name, expected_x, expected_z, by_tick]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}

	for snap in trace.per_tick_snapshots:
		if int(snap["tick"]) > by_tick:
			break
		var units_snap: Array = snap["units"]
		if unit_idx >= units_snap.size():
			continue
		var u: Dictionary = units_snap[unit_idx]
		var ux: int = int(u["pos_x"])
		var uz: int = int(u["pos_z"])
		if ux != expected_x or uz != expected_z:
			return {"ok": false, "name": name_str,
					"detail": "moved to (%d,%d) at tick %d" % [ux, uz, int(snap["tick"])]}
	return {"ok": true, "name": name_str,
			"detail": "position held at (%d,%d) through tick %d" % [expected_x, expected_z, by_tick]}


# ---- passes_through(unit='X', ally_tile=[x,z], by_tick=N) -------------------
#
# G4/G5 witness. `find_passthrough_destination` emits a multi-tile move-step
# whose destination is the first empty tile BEYOND the allied occupant —
# `write_movement_step` then sets `U_PROPOSED_X/Z` to that tile, so the unit's
# per-tick snapshot `pos_x/pos_z` jumps from the pre-ally tile to the
# post-ally tile in a single transition with the allied tile strictly on the
# axis-aligned line between them. Normal single-step moves are Manhattan=1
# transitions, so a Manhattan-≥2 transition that crosses the ally tile is the
# signature of pass-through having fired.
#
# Spec keys:
#   unit:          name of the unit whose path should pass through
#   ally_tile:     [x, z] of the allied tile to test against
#   by_tick:       only consider snapshots ≤ this tick
#   expect_no_pass (optional, default false): invert — assert no such
#                  transition occurred (G5 fails-closed half of the pair)
static func _check_passes_through(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var unit_name: String = spec.get("unit", "")
	var tile: Array = spec.get("ally_tile", [0, 0])
	var ally_x: int = int(tile[0]) if tile.size() >= 1 else 0
	var ally_z: int = int(tile[1]) if tile.size() >= 2 else 0
	var by_tick: int = spec.get("by_tick", 0)
	var expect_no: bool = bool(spec.get("expect_no_pass", false))
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "%s(unit='%s', ally_tile=[%d,%d], by_tick=%d)" % [
			"no_passes_through" if expect_no else "passes_through",
			unit_name, ally_x, ally_z, by_tick]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}

	var have_prev: bool = false
	var prev_x: int = 0
	var prev_z: int = 0
	var first_pass_tick: int = -1
	var first_pass_from: Array = []
	var first_pass_to: Array = []
	for snap in trace.per_tick_snapshots:
		if int(snap["tick"]) > by_tick:
			break
		var units_snap: Array = snap["units"]
		if unit_idx >= units_snap.size():
			# Skip without carrying stale prev_x/prev_z; the next valid
			# snapshot must start a fresh single-step delta or we'd
			# compute a multi-tile jump that falsely matches the
			# axis-segment check.
			have_prev = false
			continue
		var u: Dictionary = units_snap[unit_idx]
		var ux: int = int(u["pos_x"])
		var uz: int = int(u["pos_z"])
		if have_prev:
			var dx: int = ux - prev_x
			var dz: int = uz - prev_z
			if abs(dx) + abs(dz) >= 2 and _tile_on_axis_segment(prev_x, prev_z, ux, uz, ally_x, ally_z):
				first_pass_tick = int(snap["tick"])
				first_pass_from = [prev_x, prev_z]
				first_pass_to = [ux, uz]
				break
		prev_x = ux
		prev_z = uz
		have_prev = true

	if expect_no:
		if first_pass_tick < 0:
			return {"ok": true, "name": name_str,
					"detail": "no pass-through over (%d,%d) by tick %d (as expected)" % [
							ally_x, ally_z, by_tick]}
		return {"ok": false, "name": name_str,
				"detail": "unexpected pass-through over (%d,%d) at tick %d (%s → %s)" % [
						ally_x, ally_z, first_pass_tick, str(first_pass_from), str(first_pass_to)]}
	if first_pass_tick >= 0:
		return {"ok": true, "name": name_str,
				"detail": "pass-through over (%d,%d) at tick %d (%s → %s)" % [
						ally_x, ally_z, first_pass_tick, str(first_pass_from), str(first_pass_to)]}
	return {"ok": false, "name": name_str,
			"detail": "no Manhattan-≥2 transition over (%d,%d) by tick %d" % [
					ally_x, ally_z, by_tick]}


# True iff (tx,tz) lies strictly between (x0,z0) and (x1,z1) on a shared
# axis (same row or same column, exclusive of the endpoints).
static func _tile_on_axis_segment(x0: int, z0: int, x1: int, z1: int, tx: int, tz: int) -> bool:
	if x0 == x1:
		if tx != x0:
			return false
		return (tz - z0) * (tz - z1) < 0
	if z0 == z1:
		if tz != z0:
			return false
		return (tx - x0) * (tx - x1) < 0
	return false


# ---- no_thrash(unit='X', by_tick=N) ----------------------------------------
#
# G7/H6 witness for the "retry without thrash" rule. `check_decision_thrash`
# (stage_compute.glsl :348) walks the 6-entry decision history ring buffer
# and sets bit 3 of `decision_meta` (`thrash_flag`) when either:
#   - the same target appears 3+ times across the 6 entries, OR
#   - the LAST 3 entries cycle stuck reasons (NO_PATH / GAMBIT_FAILED /
#     NO_GAMBIT) without any forward-progress entry between them.
# That's the only way the bit ever flips on, so this predicate is a strict
# read of `thrash_flag` across the snapshot window: ok=true iff bit 3 stayed
# 0 for the named unit on every snapshot at or before `by_tick`. The
# diagnostic ring buffer accumulates thrash_count in bits [7:4] across the
# run; the predicate cares about the flag, not the cumulative count, so a
# unit that recovered from an earlier thrash doesn't pass — the rule is "no
# thrash within the window," not "not currently thrashing at by_tick."
#
# Geometry for the G7/H6 scenarios — see scenarios_G_pathfinding.gd. G2a's
# jump=3 dead-end column gives a unit a path the shader plans but cannot
# fully execute, so `check_decision_thrash`'s repeat-reason path is the
# natural failure mode to witness if the no-thrash rule regresses.
static func _check_no_thrash(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var unit_name: String = spec.get("unit", "")
	var by_tick: int = spec.get("by_tick", 0)
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "no_thrash(unit='%s', by_tick=%d)" % [unit_name, by_tick]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}
	var first_thrash_tick: int = -1
	for snap in trace.per_tick_snapshots:
		if int(snap["tick"]) > by_tick:
			break
		var units_snap: Array = snap["units"]
		if unit_idx >= units_snap.size():
			continue
		var u: Dictionary = units_snap[unit_idx]
		if int(u.get("thrash_flag", 0)) == 1:
			first_thrash_tick = int(snap["tick"])
			break
	if first_thrash_tick < 0:
		return {"ok": true, "name": name_str,
				"detail": "thrash_flag never set for '%s' by tick %d" % [unit_name, by_tick]}
	return {"ok": false, "name": name_str,
			"detail": "thrash_flag set on '%s' at tick %d (decision_meta=0x%02x)" % [
					unit_name, first_thrash_tick,
					int(trace.per_tick_snapshots[_snap_index_at_tick(trace, first_thrash_tick)]["units"][unit_idx].get("decision_meta", 0))]}


# Linear scan helper for failure diagnostic — snapshots are appended in tick
# order, so this is a single pass and only runs on the failure branch.
static func _snap_index_at_tick(trace: GambitTraceLogger, tick: int) -> int:
	for i in range(trace.per_tick_snapshots.size()):
		if int(trace.per_tick_snapshots[i]["tick"]) == tick:
			return i
	return 0


# ---- state_inhibited(unit='X', during_state='SPELL_CHARGING') --------------
#
# H1–H5 witness. Each of those rules says "a unit in <state> does not re-
# evaluate gambits." Structurally the GPU implements this by `compute_unit_state`
# (stage_compute.glsl) only calling `evaluate_gambits` from the IDLE fall-
# through and from the higher-priority WALKING re-eval — the SPELL_CHARGING /
# ACTING / AWAITING_IMPACT / U_PAUSED branches each return without touching
# the gambit eval path. The trace doesn't directly capture "evaluate_gambits
# was called," but it captures the OBSERVABLE consequences via state_events
# and `current_gambit`:
#
#   - A successful re-eval committing a NEW gambit slot writes
#     U_CURRENT_GAMBIT (stage_compute.glsl :544 inside execute_gambit_action).
#     The next state_event for the unit will carry that new slot AND a
#     prev_state that is the locked state (so the unit transitioned out).
#   - A re-eval that committed the SAME action body (same slot, same state)
#     is invisible to current_gambit but no real shader regression would
#     produce that pattern — evaluate_gambits's only call site outside the
#     legal IDLE/WALKING gates is the bug we're hunting, and it always
#     re-resolves a fresh slot.
#
# Algorithm:
#   1. Find the first state_event for the unit where new == during_state.
#      That's the entry into the locked window; capture (entry_tick,
#      entry_gambit).
#   2. Find the NEXT state_event for the same unit (any state). That's the
#      first exit.
#   3. ok=true iff exit.prev == during_state (the unit stayed in
#      during_state until that exit transition, no intermediate transitions)
#      AND exit.current_gambit == entry.current_gambit (the slot wasn't
#      overwritten by a fresh commit).
#
# Spec keys:
#   unit:          name of the unit
#   during_state:  string from GPUConstants.LOGICAL_ACTIVITY_NAMES
#   by_tick (optional, default huge): cap entry-search to this tick
static func _check_state_inhibited(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var unit_name: String = spec.get("unit", "")
	var state_name: String = spec.get("during_state", "")
	var by_tick: int = spec.get("by_tick", 1 << 30)
	var state_id: int = GPUConstants.LOGICAL_ACTIVITY_NAMES.find(state_name)
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "state_inhibited(unit='%s', during_state='%s')" % [unit_name, state_name]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}
	if state_id < 0:
		return {"ok": false, "name": name_str,
				"detail": "unknown state '%s' (expected one of %s)" % [
						state_name, str(GPUConstants.LOGICAL_ACTIVITY_NAMES)]}
	var entry_idx: int = -1
	for i in range(trace.state_events.size()):
		var ev: Dictionary = trace.state_events[i]
		if int(ev["unit"]) != unit_idx:
			continue
		if int(ev["tick"]) > by_tick:
			break
		if int(ev["new"]) == state_id:
			entry_idx = i
			break
	if entry_idx < 0:
		return {"ok": false, "name": name_str,
				"detail": "unit '%s' never entered %s by tick %d" % [
						unit_name, state_name, by_tick]}
	var entry_ev: Dictionary = trace.state_events[entry_idx]
	var entry_tick: int = int(entry_ev["tick"])
	var entry_gambit: int = int(entry_ev["current_gambit"])
	var exit_ev: Dictionary = {}
	for j in range(entry_idx + 1, trace.state_events.size()):
		if int(trace.state_events[j]["unit"]) == unit_idx:
			exit_ev = trace.state_events[j]
			break
	if exit_ev.is_empty():
		# Unit entered the locked state and stayed there until the trace
		# ended (e.g. cinematic still running at max_ticks). That's vacuously
		# OK — no re-eval was observed within the window.
		return {"ok": true, "name": name_str,
				"detail": "unit '%s' entered %s at tick %d (slot %d) and stayed through trace end (no re-eval observed)" % [
						unit_name, state_name, entry_tick, entry_gambit]}
	var exit_tick: int = int(exit_ev["tick"])
	var exit_prev: int = int(exit_ev["prev"])
	var exit_new: int = int(exit_ev["new"])
	var exit_gambit: int = int(exit_ev["current_gambit"])
	if exit_prev != state_id:
		return {"ok": false, "name": name_str,
				"detail": "unit '%s' next state_event at tick %d has prev=%s (expected %s); re-eval likely fired during %s window" % [
						unit_name, exit_tick,
						GPUConstants.LOGICAL_ACTIVITY_NAMES[exit_prev],
						state_name, state_name]}
	if exit_gambit != entry_gambit:
		return {"ok": false, "name": name_str,
				"detail": "current_gambit changed during %s window for '%s': entry slot=%d → exit slot=%d at tick %d (re-eval committed a new gambit)" % [
						state_name, unit_name, entry_gambit, exit_gambit, exit_tick]}
	return {"ok": true, "name": name_str,
			"detail": "'%s' held %s (slot %d) tick %d → %d (%d ticks); natural exit to %s" % [
					unit_name, state_name, entry_gambit, entry_tick, exit_tick,
					exit_tick - entry_tick,
					GPUConstants.LOGICAL_ACTIVITY_NAMES[exit_new]]}


# ---- returns_to_idle(unit='X', after_state='ACTING', within_ticks=N) -------
#
# H7 witness for "post-action: unit returns to IDLE and re-evaluates gambits."
# After a unit's first commit (entry into after_state), the state machine must
# advance back to IDLE within `within_ticks` of the entry. The natural path
# for an ATTACK is ACTING → IDLE (or ACTING → AWAITING_IMPACT → IDLE for
# ranged); both are accepted because the predicate only asserts that IDLE is
# reached, not the intermediate path.
#
# Spec keys:
#   unit:         name of the unit
#   after_state:  string from GPUConstants.LOGICAL_ACTIVITY_NAMES (default
#                 "ACTING")
#   within_ticks: max ticks from after_state entry to IDLE entry
static func _check_returns_to_idle(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var unit_name: String = spec.get("unit", "")
	var after_state_name: String = spec.get("after_state", "ACTING")
	var within: int = spec.get("within_ticks", 60)
	var after_state_id: int = GPUConstants.LOGICAL_ACTIVITY_NAMES.find(after_state_name)
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "returns_to_idle(unit='%s', after_state='%s', within_ticks=%d)" % [
			unit_name, after_state_name, within]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}
	if after_state_id < 0:
		return {"ok": false, "name": name_str,
				"detail": "unknown state '%s' (expected one of %s)" % [
						after_state_name, str(GPUConstants.LOGICAL_ACTIVITY_NAMES)]}
	var entry_tick: int = -1
	var entry_idx: int = -1
	for i in range(trace.state_events.size()):
		var ev: Dictionary = trace.state_events[i]
		if int(ev["unit"]) != unit_idx:
			continue
		if int(ev["new"]) == after_state_id:
			entry_tick = int(ev["tick"])
			entry_idx = i
			break
	if entry_idx < 0:
		return {"ok": false, "name": name_str,
				"detail": "unit '%s' never entered %s" % [unit_name, after_state_name]}
	for j in range(entry_idx + 1, trace.state_events.size()):
		var ev: Dictionary = trace.state_events[j]
		if int(ev["unit"]) != unit_idx:
			continue
		if int(ev["new"]) == GPUConstants.LOGICAL_ACTIVITY_IDLE:
			var delta: int = int(ev["tick"]) - entry_tick
			if delta <= within:
				return {"ok": true, "name": name_str,
						"detail": "'%s' entered %s at tick %d, reached IDLE at tick %d (delta %d ≤ %d)" % [
								unit_name, after_state_name, entry_tick,
								int(ev["tick"]), delta, within]}
			return {"ok": false, "name": name_str,
					"detail": "'%s' reached IDLE at tick %d, %d ticks after %s entry (exceeds %d)" % [
							unit_name, int(ev["tick"]), delta, after_state_name, within]}
	return {"ok": false, "name": name_str,
			"detail": "'%s' entered %s at tick %d but never returned to IDLE within trace" % [
					unit_name, after_state_name, entry_tick]}


# ---- cooldown_respected(unit='X', ability=N, min_spacing=M, min_casts=K) ---
#
# B8 witness for "Action is on cooldown -> fall through." Walks
# `cast_events` for (unit, ability) and asserts (1) at least `min_casts`
# events fired for that pair (need >=2 to witness a gap), (2) every
# consecutive pair's tick gap is >= `min_spacing`. Without the cooldown veto,
# a CT=0 0-MP ability re-fires as fast as its cast animation +
# TICKS_GAMBIT_REEVAL allow, so the very first gap blows the spacing check.
static func _check_cooldown_respected(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var unit_name: String = spec.get("unit", "")
	var ability: int = int(spec.get("ability", -1))
	var min_spacing: int = int(spec.get("min_spacing", 60))
	var min_casts: int = int(spec.get("min_casts", 2))
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "cooldown_respected(unit='%s', ability=%d, min_spacing=%d)" % [
			unit_name, ability, min_spacing]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}
	var cast_ticks: Array = []
	# Parallel array of GPU commit ticks recovered from cooldown_ready_at SSBO
	# samples (= ready_at - min_spacing). The predicate asserts spacing against
	# THIS axis when available — `tick` is a host-frame snapshot that can lag
	# the actual GPU commit by up to (frame_size - 1) ticks at
	# Engine.time_scale > 1, leaking sub-floor gaps in the trace-tick view
	# while the GPU enforced the floor correctly.
	var gpu_ticks: Array = []
	for ev in trace.cast_events:
		if int(ev["unit"]) != unit_idx:
			continue
		if int(ev["ability_id"]) != ability:
			continue
		cast_ticks.append(int(ev["tick"]))
		var ready_at: int = int(ev.get("cooldown_ready_at", -1))
		gpu_ticks.append(ready_at - min_spacing if ready_at >= 0 else -1)
	if cast_ticks.size() < min_casts:
		return {"ok": false, "name": name_str,
				"detail": "only %d cast(s) of ability %d observed for '%s' (need >=%d to witness spacing); ticks=%s" % [
						cast_ticks.size(), ability, unit_name, min_casts, str(cast_ticks)]}
	# Spacing axis: prefer GPU commit ticks (truth) when sampled. The
	# trace-tick view is the loud reading the predicate has historically used
	# and is reported in parallel for transparency.
	var use_gpu: bool = gpu_ticks.size() == cast_ticks.size() and int(gpu_ticks[0]) >= 0
	var axis_ticks: Array = gpu_ticks if use_gpu else cast_ticks
	var worst_gap: int = 0x7FFFFFFF
	var worst_pair: String = ""
	for i in range(1, axis_ticks.size()):
		var gap: int = int(axis_ticks[i]) - int(axis_ticks[i - 1])
		if gap < worst_gap:
			worst_gap = gap
			worst_pair = "tick %d -> tick %d (gap %d)" % [
					int(axis_ticks[i - 1]), int(axis_ticks[i]), gap]
	var ok: bool = worst_gap >= min_spacing
	var axis_label := "GPU commit ticks (from cooldown_ready_at)" if use_gpu else "trace ticks"
	var detail := "observed %d casts (axis=%s) at %s; min gap %d at %s (need >=%d)" % [
			cast_ticks.size(), axis_label, str(axis_ticks), worst_gap, worst_pair, min_spacing]
	if use_gpu:
		detail += "; trace_ticks=%s" % str(cast_ticks)
	return {"ok": ok, "name": name_str, "detail": detail}


# ---- alternates_with(unit='X', ability=N, ability_slot=A, fallback_slot=F,
#                     min_fallback_per_cycle=K) ------------------------------
#
# Issue #92 witness: cooldown on the ability slot must open a *real* fall-through
# window — enough ticks past the cast animation to admit at least K fallback
# commits before the ability re-fires. Asserts that across every consecutive
# pair of REAL ability commits, the fallback slot commits at least K times.
#
# "Real" ability commit = `cast_events` filtered to `current_gambit == ability_slot`.
# This rejects the spurious CAST_BEGAN that GPUCombatInterpreter:178-184 emits
# when a fallback ATTACK inherits the prior `casting_ability_id` — those have
# `current_gambit == fallback_slot`. The dual-filter avoids the noise B8 had to
# avoid with WAIT.
#
# Fallback commits = `action_committed_events` with `current_gambit ==
# fallback_slot`. This stream is the discrete-commit witness #93 added — it
# fires on every cast_step_id bump and is immune to the host-frame coalescing
# that drops short IDLE windows from `state_events` (where ACTING → IDLE →
# ACTING blinks of ≤1 GPU tick can sample as uninterrupted ACTING at >1 ticks
# per host frame).
static func _check_alternates_with(spec: Dictionary, trace: GambitTraceLogger) -> Dictionary:
	var unit_name: String = spec.get("unit", "")
	var ability: int = int(spec.get("ability", -1))
	var ability_slot: int = int(spec.get("ability_slot", 0))
	var fallback_slot: int = int(spec.get("fallback_slot", 1))
	var min_fb: int = int(spec.get("min_fallback_per_cycle", 1))
	var unit_idx: int = trace.unit_index(unit_name)
	var name_str := "alternates_with(unit='%s', ability=%d, fallback_slot=%d, min_per_cycle=%d)" % [
			unit_name, ability, fallback_slot, min_fb]
	if unit_idx < 0:
		return {"ok": false, "name": name_str, "detail": "unknown unit '%s'" % unit_name}
	var ability_ticks: Array = []
	for ev in trace.cast_events:
		if int(ev["unit"]) != unit_idx:
			continue
		if int(ev["ability_id"]) != ability:
			continue
		if int(ev.get("current_gambit", -1)) != ability_slot:
			continue
		ability_ticks.append(int(ev["tick"]))
	if ability_ticks.size() < 2:
		return {"ok": false, "name": name_str,
				"detail": "only %d real ability commit(s) observed for '%s' on slot %d (need >=2 to witness a cycle); cast_event_ticks=%s" % [
						ability_ticks.size(), unit_name, ability_slot, str(ability_ticks)]}
	var fallback_ticks: Array = []
	for ev in trace.action_committed_events:
		if int(ev["unit"]) != unit_idx:
			continue
		if int(ev.get("current_gambit", -1)) != fallback_slot:
			continue
		fallback_ticks.append(int(ev["tick"]))
	# Per-cycle audit. Strict (Ti, Ti+1) open window.
	var per_cycle_counts: Array = []
	var worst_count: int = 0x7FFFFFFF
	var worst_cycle: String = ""
	for i in range(1, ability_ticks.size()):
		var lo: int = int(ability_ticks[i - 1])
		var hi: int = int(ability_ticks[i])
		var n: int = 0
		for t in fallback_ticks:
			if int(t) > lo and int(t) < hi:
				n += 1
		per_cycle_counts.append(n)
		if n < worst_count:
			worst_count = n
			worst_cycle = "cycle (tick %d -> tick %d): %d fallback(s)" % [lo, hi, n]
	var ok: bool = worst_count >= min_fb
	var detail := "ability_commits=%s; fallback_commits=%s; per_cycle_counts=%s; worst=%s (need >=%d per cycle)" % [
			str(ability_ticks), str(fallback_ticks), str(per_cycle_counts), worst_cycle, min_fb]
	return {"ok": ok, "name": name_str, "detail": detail}
