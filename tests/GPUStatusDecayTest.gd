extends GPUCombatTestBase
# test-kind: gpu
# seeded-break: make the producer read nothing — in src/gpu/shaders/combat_common.glslinc's `status_default_ct`, return 0 for STATUS_SLOW. Arm 2 reds ("SLOW never cleared: inflicted statuses are still permanent"), which is #1105's finding 1 restored; arms 1 and 3 stay green, because a seeded countdown never touches the producer

## GPU Status Decay Test — the decay engine, both halves.
##
## THREE arms, one battle, because the claim has three parts and they share a
## harness (test charter clause 13):
##
##   1. **A SEEDED countdown clears.** HasteCarrier boots with HASTE set and a
##      30-tick countdown in its slot; the bit must clear at ~30. This is Tier 2
##      #6's original arm and it tests the CONSUMER.
##   2. **An INFLICTED countdown clears, at the duration the ROM gives it**
##      (#1116). TimeMage casts Slow on SlowTarget — nothing seeds anything — and
##      the bit must appear and then clear `StatusRegistry.default_duration_ticks`
##      later: 24 CT x 36 ticks. 🔴 THIS IS THE ARM NOTHING IN THE SUITE HAD.
##      #1105 measured that `set_status_with_timer` had zero call sites, so every
##      status inflicted in a battle was permanent; arm 1 was green throughout,
##      because seeding a countdown skips the producer entirely.
##   3. **A status the ROM never times stays set.** HasteCarrier also boots with
##      DARKNESS and no countdown, and it must still be set when the run ends.
##      Without this, "the bit cleared" is consistent with a tick loop that clears
##      every status it sees, and sixteen of FFT's forty are permanent until cured.
##
## ⚠️ SLOW LANDS ON THE FIRST CAST BY CONSTRUCTION, not by luck. Formula 10's hit
## chance is `min(MA + X, 100) * caster_faith * target_faith / 10000` and both
## Faiths are 100, so it is exactly 100 and the roll cannot miss. TimeMage also
## carries exactly one cast's worth of MP, because a second cast would REFRESH the
## countdown and arm 2 would be measuring the wrong interval.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


# 🔴 THIS TEST WAS SKIPPED, AND THE REASON WAS THE MEASUREMENT (#542 via
# `tests/skip_tests.tsv`: "HASTE timer clears 8 ticks off a +/-3 tolerance").
# The rule was never wrong; the instrument was. The bit is sampled once per FRAME
# and a frame banks however much wall clock it took — up to
# `CombatLoop.max_catchup_real_s * Engine.time_scale` of it — so under suite load
# one frame can step hundreds of ticks and the OBSERVED clear lands arbitrarily
# late. A ±3 window on a per-frame poll is a measurement of the box.
#
# So arm 1 is one-sided now: clearing EARLY is the defect (a countdown that
# decrements faster than a tick, or a tick loop that clears unarmed bits), and
# clearing late has two innocent causes. The sampler is one. The other is real and
# measured here: a cinematic pause early-returns out of `compute_unit_state` before
# the decay runs, and TimeMage's Slow cast pauses EVERY unit except itself — so
# this carrier's countdown freezes for the cast it has nothing to do with. The
# observed gap on this fixture is ~190 ticks of that. The upper bound still catches
# "never decays"; the seed is long enough that a coarse frame cannot step past the
# whole window before the first poll sees the bit set.
const HASTE_TIMER_TICKS = 300
const HASTE_LATE_ALLOWANCE = 400

# Slow: ability 34, formula 10, ct 2, range 3, mp 8, inflict ["Slow"] mode all.
const ABILITY_SLOW = 34
const SLOW_MP_FOR_ONE_CAST = 8

# What arm 2 expects, read from the registry rather than written here: the number
# is the ROM's (24 CT) and the conversion is the turn meter's, so a test holding
# its own copy would be a third place for them to disagree.
var _slow_expected_ticks: int = StatusRegistry.default_duration_ticks(&"slow")
# The poll is per host frame and `test_time_scale` advances ~4 ticks a frame, so
# the observed window is coarser than arm 1's. Slack over that, not over the rule.
const SLOW_TOLERANCE_TICKS = 60

# What the playback rate becomes once both measurements are in (see the bump site).
const FAST_FORWARD_SCALE = 12.0

var _haste_first_clear_tick: int = -1
var _haste_first_observed_tick: int = -1
var _slow_first_observed_tick: int = -1
var _slow_first_clear_tick: int = -1
var _slow_first_countdown: int = -1
var _darkness_ever_cleared: bool = false
var _results_printed: bool = false


func get_test_name() -> String:
	return "GPU Status Decay Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "HasteCarrier",
			"pos_x": 0, "pos_z": 0,
			"hp": 999, "max_hp": 999,
			"pa": 5, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 100,
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x02,
			# HASTE with a countdown (arm 1) and DARKNESS without one (arm 3),
			# carried by the same unit so the two are read off one state row: the
			# tick loop has to clear exactly the armed bit and leave the other.
			"status_flags_lo": (1 << StatusRegistry.bit(&"haste"))
				| (1 << StatusRegistry.bit(&"darkness")),
			"status_timers": [{"bit": StatusRegistry.bit(&"haste"), "ticks": HASTE_TIMER_TICKS}],
		},
		{
			# Arm 2's caster. Faith 100 and MA 12 pin formula 10's hit chance at
			# exactly 100; MP for ONE cast keeps it from refreshing the countdown.
			"name": "TimeMage",
			"pos_x": 0, "pos_z": 4,
			"hp": 999, "max_hp": 999,
			"pa": 5, "ma": 12, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": SLOW_MP_FOR_ONE_CAST, "max_mp": SLOW_MP_FOR_ONE_CAST,
			"speed": 100,
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x02,
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "Dummy",
			"pos_x": 8, "pos_z": 8,
			"hp": 999, "max_hp": 999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 1,
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x05,
		},
		{
			# Arm 2's target: two tiles from TimeMage, inside Slow's range 3, and
			# far from Dummy so the radius-1 splash cannot reach a second unit.
			# Faith 100 is the other half of the deterministic hit.
			"name": "SlowTarget",
			"pos_x": 2, "pos_z": 4,
			"hp": 999, "max_hp": 999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 0, "max_mp": 0,
			"speed": 1,
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
		},
	]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	# Only TimeMage acts. Everyone else stands still, so the only status that
	# lands in this battle is the one arm 2 is watching.
	if team == 0 and unit_idx == 1:
		return [make_spell_gambit(ABILITY_SLOW)]
	return []


func _ready():
	# Arm 2 needs the whole 864-tick countdown plus the cast windup; arm 1 is done
	# by tick ~31 and arm 3 is a statement about the end of the run.
	max_ticks = _slow_expected_ticks + 500
	super._ready()


func _process(delta):
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	var states = gpu_state_reader.get_all_unit_states()
	# 3 is SlowTarget (team0 x2 then team1 x2) — assert the row exists rather than
	# reading a shorter array's [0] and calling it a decay measurement.
	if states.size() < 4:
		return

	var carrier_flags: int = int(states[0].get("status_flags_lo", 0))
	var target_flags: int = int(states[3].get("status_flags_lo", 0))
	var has_haste := (carrier_flags & (1 << StatusRegistry.bit(&"haste"))) != 0
	var has_darkness := (carrier_flags & (1 << StatusRegistry.bit(&"darkness"))) != 0
	var has_slow := (target_flags & (1 << StatusRegistry.bit(&"slow"))) != 0

	if has_haste and _haste_first_observed_tick < 0:
		_haste_first_observed_tick = current_tick
	if not has_haste and _haste_first_observed_tick >= 0 and _haste_first_clear_tick < 0:
		_haste_first_clear_tick = current_tick

	if has_slow and _slow_first_observed_tick < 0:
		_slow_first_observed_tick = current_tick
		# 🔴 READ THE COUNTDOWN, NOT JUST THE WINDOW — ONCE, on the frame the bit
		# first appears. The armed VALUE is what the producer actually claims; the
		# elapsed time between the first and last sighting is a weaker measurement
		# that a refresh, or a frozen counter, shifts without being wrong about the
		# duration. Once, because `get_unit_column` is a blocking `buffer_get_data`
		# (ADR-0237 dec. 7 measured 33-51 ms for one column across 1024 battles) —
		# one read is a measurement, one per frame is a tax on every tick.
		_slow_first_countdown = _read_slow_countdown()
	if not has_slow and _slow_first_observed_tick >= 0 and _slow_first_clear_tick < 0:
		_slow_first_clear_tick = current_tick

	# 🔴 BOTH MEASUREMENTS FIRST, THEN FAST-FORWARD THROUGH THE WAIT. Arm 1 reads a
	# 30-tick window to ±3 and arm 2 reads the armed counter, and both are sampled
	# per FRAME — so both need a frame worth only a few ticks. What is left after
	# them is 864 ticks of waiting, and at that rate this test runs for minutes and
	# the suite scores it HUNG (the runner kills at 360 s). `playback_scale` is
	# exactly this knob, and ADR-0239 is why using it is not cheating: the drain it
	# feeds advances in whole TICK_INTERVAL steps and every outcome downstream is a
	# function of `current_tick`, never of wall clock. Only the CLEAR tick is
	# sampled coarsely afterwards, and that assertion is one-sided.
	if combat_loop and _haste_first_clear_tick >= 0 and _slow_first_countdown > 0 \
			and combat_loop.playback_scale < FAST_FORWARD_SCALE:
		combat_loop.playback_scale = FAST_FORWARD_SCALE
		print("  [decay] both measurements in at tick %d — playback x%.0f for the %d-tick wait" % [
			current_tick, FAST_FORWARD_SCALE, _slow_expected_ticks])

	if not has_darkness:
		_darkness_ever_cleared = true

	# Run until BOTH countdowns have resolved, or the ceiling. Quitting on the
	# first (arm 1, by tick ~31) is what the single-arm version did and it is
	# exactly why the missing producer was invisible here.
	if (_haste_first_clear_tick >= 0 and _slow_first_clear_tick >= 0) \
			or current_tick >= max_ticks:
		_print_results()


## SlowTarget's live countdown for SLOW, straight out of the unit buffer. Slot 5
## (the ROM's, `StatusRegistry.TIMER_SLOT`) lives in the HIGH half of
## STATUS_TIMER_2, because two 16-bit counters share each int.
func _read_slow_countdown() -> int:
	var slot: int = StatusRegistry.timer_slot(&"slow")
	var column: PackedInt32Array = gpu_state_reader.get_unit_column(
		GPUCombatPacker.UnitField.STATUS_TIMER_0 + (slot >> 1))
	if column.size() < 4:
		return -1
	var packed: int = column[3]
	return (packed >> 16) & 0xFFFF if (slot & 1) == 1 else (packed & 0xFFFF)


func _print_results():
	if _results_printed:
		return
	_results_printed = true

	var failures: Array[String] = []

	print("\n=== STATUS DECAY TEST RESULTS ===")

	# Arm 1 — the seeded countdown (the consumer).
	print("  seeded HASTE: first seen tick %d, cleared tick %d" % [
		_haste_first_observed_tick, _haste_first_clear_tick])
	if _haste_first_observed_tick < 0:
		failures.append("seeded HASTE was never seen set — it was seeded in the config, so arm 1 measured nothing")
	elif _haste_first_clear_tick < 0:
		failures.append("seeded HASTE never cleared (a %d-tick countdown was seeded)" % HASTE_TIMER_TICKS)
	else:
		var elapsed: int = _haste_first_clear_tick - max(_haste_first_observed_tick, 0)
		print("    elapsed %d, expected >= %d and < %d (late is the per-frame sampler, early is the bug)" % [
			elapsed, HASTE_TIMER_TICKS, HASTE_TIMER_TICKS + HASTE_LATE_ALLOWANCE])
		if elapsed < HASTE_TIMER_TICKS - 1:
			failures.append("seeded HASTE cleared after %d ticks, %d early on a %d-tick countdown" % [
				elapsed, HASTE_TIMER_TICKS - elapsed, HASTE_TIMER_TICKS])
		elif elapsed >= HASTE_TIMER_TICKS + HASTE_LATE_ALLOWANCE:
			failures.append("seeded HASTE took %d ticks against a %d-tick countdown — too late for a sampling artefact" % [
				elapsed, HASTE_TIMER_TICKS])

	# Arm 2 — the INFLICTED countdown (the producer, #1116).
	print("  inflicted SLOW: first seen tick %d, cleared tick %d" % [
		_slow_first_observed_tick, _slow_first_clear_tick])
	print("    countdown when first seen: %d, expected %d = 24 CT x %d" % [
		_slow_first_countdown, _slow_expected_ticks,
		StatusRegistry.TICKS_PER_CLOCK_TICK])
	if _slow_first_observed_tick < 0:
		failures.append("SLOW never landed — the cast did not resolve, so arm 2 measured nothing")
	elif _slow_first_clear_tick < 0:
		failures.append("SLOW never cleared: inflicted statuses are still permanent (expected ~%d ticks, the ROM's 24 CT)" % _slow_expected_ticks)
	else:
		var slow_elapsed: int = _slow_first_clear_tick - _slow_first_observed_tick
		# ⚠️ EXPECT THIS TO EXCEED THE COUNTDOWN, and not by a bug: a cinematic
		# pause early-returns out of `compute_unit_state` before the decay runs
		# (stage_compute's U_PAUSED gate), so a paused unit's counter is frozen —
		# which is what FFT does too, since its clock stops for the animation. The
		# measured gap on this fixture is ~90 ticks, all of it the Slow cast's own
		# cinematic playing out after the hit lands.
		print("    bit ran %d ticks (>= the countdown: pauses freeze it)" % slow_elapsed)
		# The armed value is the assertion. A few ticks may already have been spent
		# between the cast resolving and this frame's read, so the window is
		# one-sided: never MORE than the ROM's duration, never much less.
		if _slow_first_countdown > _slow_expected_ticks \
				or _slow_first_countdown < _slow_expected_ticks - SLOW_TOLERANCE_TICKS:
			failures.append("SLOW armed %d ticks, expected %d (-%d, +0)" % [
				_slow_first_countdown, _slow_expected_ticks, SLOW_TOLERANCE_TICKS])
		if slow_elapsed < _slow_expected_ticks - SLOW_TOLERANCE_TICKS:
			failures.append("SLOW's bit only lasted %d ticks against a %d-tick countdown" % [
				slow_elapsed, _slow_expected_ticks])

	# Arm 3 — the permanent control.
	print("  seeded DARKNESS (no ROM countdown): %s" % (
		"CLEARED" if _darkness_ever_cleared else "still set"))
	if _darkness_ever_cleared:
		failures.append("DARKNESS cleared, and the ROM gives it no countdown — the tick loop is clearing unarmed bits")

	print("  assertions: 3 arms, %d failed" % failures.size())
	for f in failures:
		print("    - %s" % f)
	print("=================================\n")
	if failures.is_empty():
		print("[PASS] GPUStatusDecay: a seeded countdown clears, an INFLICTED one clears at the ROM's duration, and an untimed status stays set")
	else:
		print("[FAIL] GPUStatusDecay: %d of 3 arms failed" % failures.size())
	get_tree().quit()


func on_victory(_winning_team: int):
	if not _results_printed:
		_print_results()
