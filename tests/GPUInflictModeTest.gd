extends GPUCombatTestBase
# test-kind: gpu
# seeded-break: make RANDOM behave like ALL — in src/gpu/shaders/combat_common.glslinc's `resolve_inflict_mask`, add INFLICT_MODE_RANDOM to the first line's early `return mask`. Arm 1 reds ("LookofDevil set 5 of its 5 listed statuses in one cast"); arms 2-4 stay green, because they watch a SEPARATE-mode ability. VERIFIED, both arms: the mirror seed (INFLICT_MODE_SEPARATE there instead) reds arm 3 ("all three GrandCross targets came out with the same status set") and leaves arm 1 green

## GPU Inflict Mode Test — the two modes the shader used to drop (#1117).
##
## `apply_inflict_all` implemented ALL and CANCEL and fell off the end for
## RANDOM and SEPARATE, so 27 of the 155 status-bearing abilities inflicted
## nothing, with no warning at encode time and no branch at apply time. This is
## the end-to-end witness that both now land, and that each lands the SHAPE the
## ROM gives it rather than collapsing into ALL.
##
## FOUR arms, one battle, because they share the harness (test charter clause
## 13) and two of them are each other's control:
##
##   1. **RANDOM lands EXACTLY ONE.** DevilEye casts LookofDevil (301, formula
##      80, `random`, five statuses) once at RandomTarget. The ROM collects the
##      listed statuses and indexes them with a single draw
##      (`FUN_80187F24` -> `FUN_8018EEA0`), so the count is one — not five (which
##      is what ALL would give) and not zero (which is what the missing branch
##      gave). ⚠️ EXACTLY ONE IS DETERMINISTIC HERE: formula 80 applies with no
##      hit roll, and the count is read off a snapshot taken on the frame the
##      FIRST listed bit appeared, which is one cast's worth by construction.
##   2. **SEPARATE lands a SUBSET.** CrossBearer casts GrandCross (350, formula
##      56, `separate`, nine statuses, radius 2) once across three clustered
##      targets. Every target's status set must be a subset of those nine — an
##      inflict must not invent a bit.
##   3. **SEPARATE ROLLS PER (TARGET, STATUS), which is the claim that
##      distinguishes it from every other mode.** One cast, three targets, nine
##      statuses = 27 independent rolls at `INFLICT_SEPARATE_KEEP_PCT`, so the
##      three targets must NOT all come out with the same status set. Under ALL
##      they would (all nine); under the old fall-through they would (none); and
##      under one-roll-per-cast they would too. 🔴 THIS IS THE ARM THAT CANNOT BE
##      SATISFIED BY ANY OTHER MODE.
##   4. **Something landed.** The union across the three targets is non-empty —
##      the anti-vacuity check, so arms 2 and 3 cannot both be satisfied by a
##      shader that inflicts nothing at all.
##
## FALSE-RED BUDGET, because arms 3 and 4 are probabilistic and the battle seed
## is `randi()`. At 24% per roll, P(all 27 rolls fail) = 0.76^27 = 8.2e-4, and
## that is the ONLY outcome that reds arms 3 and 4 on a correct shader. The
## accepted precedent in this suite is GPUStatusHitRateTest, which documents
## 1.3e-3 for the same kind of window. Arms 1 and 2 carry no such budget.
##
## 🔴 THAT NUMBER ASSUMES ALL THREE TARGETS ARE IN THE BLAST, and this fixture's
## positions are not pinned by the engine — units settle onto valid cells and
## `MapComposer` builds the terrain per run. So the membership is CONTROLLED
## rather than assumed: under the ALL seed a hit target is unmistakable (9 of 9),
## and three control runs put all three at (0,8) / (1,8) / (0,7) with 9 of 9
## each. If a future change to placement drops one out of the radius the budget
## becomes 0.76^18 = 8.6e-3, which is why the per-target position and first
## sighting are printed on every run rather than only on a failure.
##
## WHY NOT A RATE BAND. The obvious test of a 24% chance is to measure the rate,
## and this suite already has six skipped tests that do exactly that
## (`tests/skip_tests.tsv`, the GPUEvasion* family, #539). A band over a handful
## of GPU casts measures the box; a shape invariant over one cast does not.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


# LookofDevil: formula 80 (apply with no hit roll), ct 0, mp 0, range 3,
# effect_area 0, inflict `random` over five statuses. Death Sentence is NOT among
# them, so nothing in this fixture depends on #1119's missing bits.
const ABILITY_LOOK_OF_DEVIL = 301
# GrandCross: formula 56 (apply with no hit roll), ct 5, mp 0, range 4,
# effect_area 2, inflict `separate` over nine statuses.
const ABILITY_GRAND_CROSS = 350

# The two ability records' own status lists, as StatusRegistry names. Written out
# rather than read from AbilityDatabase on purpose: the arms below are assertions
# about WHICH bits may appear, and deriving the expectation from the same table
# the encoder reads would make a re-extraction that changes a list green by
# construction. The encode-side parity is StatusEncoderTest's job.
const RANDOM_STATUSES: Array[StringName] = [
	&"silence", &"darkness", &"petrify", &"disable", &"immobilize",
]
const SEPARATE_STATUSES: Array[StringName] = [
	&"silence", &"confusion", &"darkness", &"petrify", &"frog",
	&"berserk", &"slow", &"poison", &"sleep",
]

# 🔴 EVERY ARM READS A SNAPSHOT TAKEN ON THE FRAME ITS CAST LANDED, NOT THE END
# OF THE RUN, because all four are claims about ONE cast. Both abilities would
# cast again — LookofDevil's cooldown is 300 ticks and GrandCross re-arms after
# 150 charge + 150 cooldown — and every one of their statuses outlasts this run
# (the shortest countdown among the fourteen is Slow's 24 CT = 864 ticks), so
# bits ACCUMULATE. Read at the end, "exactly one of five" and "not all nine"
# would both be measuring however many casts fitted.
#
# Measured on this fixture over three runs, 2026-09-11: LookofDevil lands tick
# 3-4 (ct 0, so the first gambit eval resolves it) and GrandCross lands tick
# 526-528 (ct 5 charge plus its cinematic), each on a frame that banked 4 ticks.
# The ceiling is that second number with room for the charge to run long under
# load; the run quits as soon as both snapshots are in, so reaching the ceiling
# is a failure path and not the normal one.
const TEST_MAX_TICKS = 1000
# The shortest gap to a SECOND cast of either ability: LookofDevil's 300-tick
# cooldown, and GrandCross's 150 cooldown + 150 charge. A snapshot frame that
# banked this many ticks could hold two casts, and then no arm here is a verdict
# — so the span is recorded and checked rather than assumed. It is not a
# tolerance on the rule: `test_time_scale` steps ~4 ticks a frame, two orders
# under this, and a frame that banks 300 is a box measurement (see the same
# hazard priced in GPUStatusDecayTest's arm 1).
const SECOND_CAST_FLOOR = 300
# How long after the first GrandCross bit appears before the three targets are
# read. `cast_cinematic_spell` stamps each in-radius target its OWN fire frame
# (`first_hit_frame + target_count * for_each_delay`), so one cast lands on them
# one after another and a snapshot taken at the first bit reads the later targets
# as empty sets. 🔴 THAT IS NOT A HYPOTHETICAL: the first version of this test
# snapshotted at the first bit and the ALL seed still PASSED it, because the
# third target had not been hit yet and so differed from the other two.
# MEASURED with the ALL seed, where a hit target is unmistakable (9 of 9): the
# three fire on ticks 528, 528 and 532, so the spread is 4 ticks. 120 is 30x that
# and still well inside SECOND_CAST_FLOOR.
const SEPARATE_SETTLE_TICKS = 120


var _random_landed_at: int = -1
var _random_bits_at_landing: int = 0
var _random_landing_span: int = 0
var _separate_landed_at: int = -1
var _separate_sets: Array[int] = []
var _separate_first_seen: Array[int] = [-1, -1, -1]
var _separate_strays: Array[int] = []
var _separate_names: Array[String] = []
var _separate_landing_span: int = 0
var _prev_tick: int = 0
var _results_printed: bool = false


func get_test_name() -> String:
	return "GPU Inflict Mode Test (RANDOM + SEPARATE #1117)"


## Bit mask for a name list, so an arm can talk about "the listed set".
static func _mask_of(names: Array[StringName]) -> int:
	var mask := 0
	for n in names:
		mask |= 1 << StatusRegistry.bit(n)
	return mask


func get_team0_unit_configs() -> Array:
	# Two casters, 12 tiles apart, so neither ability can reach the other's
	# slice: LookofDevil is range 3 / radius 0 and GrandCross is range 4 /
	# radius 2, and every cross distance below is >= 6.
	return [
		{
			"name": "DevilEye",
			"pos_x": 0, "pos_z": 0,
			"hp": 999, "max_hp": 999,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 99, "max_mp": 99,
			"speed": 100, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x02,
		},
		{
			"name": "CrossBearer",
			"pos_x": 0, "pos_z": 12,
			"hp": 999, "max_hp": 999,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 99, "max_mp": 99,
			"speed": 100, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x02,
		},
	]


func get_team1_unit_configs() -> Array:
	# All inert: move 0 and no gambits, so the only statuses in this battle are
	# the ones the two casts put there and the geometry cannot drift.
	var base := {
		"pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x05,
		"hp": 999, "max_hp": 999,
	}
	return [
		# Arm 1's target: 2 tiles from DevilEye (range 3), and 6 from the nearest
		# GrandCross target, which is 4 outside GrandCross's radius 2.
		_merge(base, {"name": "RandomTarget", "pos_x": 0, "pos_z": 2}),
		# Arms 2-4: CrossBearer's nearest enemy is CrossA at distance 4, so the
		# aim lands there; CrossB and CrossC are 1 tile from it, inside radius 2.
		# CrossBearer itself is 4 from the aim point and so outside its own blast.
		_merge(base, {"name": "CrossA", "pos_x": 0, "pos_z": 8}),
		_merge(base, {"name": "CrossB", "pos_x": 1, "pos_z": 8}),
		_merge(base, {"name": "CrossC", "pos_x": 0, "pos_z": 7}),
	]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	if team != 0:
		return []
	if unit_idx == 0:
		return [make_spell_gambit(ABILITY_LOOK_OF_DEVIL)]
	return [make_spell_gambit(ABILITY_GRAND_CROSS)]


func _ready() -> void:
	max_ticks = TEST_MAX_TICKS
	super._ready()


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	var states: Array = gpu_state_reader.get_all_unit_states()
	# 6 rows: two casters then four targets. Assert the array rather than reading
	# a shorter one's [0] and calling the zero an inflict measurement.
	if states.size() < 6:
		return

	# How many ticks THIS frame banked. Both snapshots carry it, because a frame
	# wide enough to span two casts makes its own reading unscoreable.
	var span: int = current_tick - _prev_tick
	_prev_tick = current_tick

	var random_flags: int = int(states[2].get("status_flags_lo", 0)) & _mask_of(RANDOM_STATUSES)
	if _random_landed_at < 0 and random_flags != 0:
		_random_landed_at = current_tick
		_random_bits_at_landing = random_flags
		_random_landing_span = span

	var separate_mask := _mask_of(SEPARATE_STATUSES)
	# Per-target first sighting, which is what MEASURES the stagger the settle
	# window below has to cover. A target whose nine rolls all failed never gets
	# one, so this is a lower bound on the spread and not a census of the blast.
	for i in range(3, 6):
		if _separate_first_seen[i - 3] < 0 \
				and (int(states[i].get("status_flags_lo", 0)) & separate_mask) != 0:
			_separate_first_seen[i - 3] = current_tick
	if _separate_landed_at < 0:
		var union := 0
		for i in range(3, 6):
			union |= int(states[i].get("status_flags_lo", 0))
		if (union & separate_mask) != 0:
			_separate_landed_at = current_tick
			_separate_landing_span = span
	# 🔴 THE SNAPSHOT WAITS OUT THE STAGGER. `cast_cinematic_spell` gives each
	# in-radius target its OWN fire frame (`first_hit_frame + target_count *
	# for_each_delay`), so one AOE cast resolves its targets on DIFFERENT ticks —
	# a snapshot taken when the first bit appears has only the first target's
	# rolls in it, and reads every later target as an empty set. Measured with
	# the ALL seed below.
	if _separate_landed_at >= 0 and _separate_sets.is_empty() \
			and current_tick >= _separate_landed_at + SEPARATE_SETTLE_TICKS:
		for i in range(3, 6):
			var flags: int = int(states[i].get("status_flags_lo", 0))
			_separate_sets.append(flags & separate_mask)
			# The STRAY read is against the full flag word, not the masked one,
			# so an inflict that lit a tenth unrelated status is visible rather
			# than masked away by the very set under test.
			_separate_strays.append(flags & ~separate_mask)
			# The POSITION goes in the label, because "0 of 9" has two causes —
			# the rolls came up empty, or the unit was never in the blast — and
			# only the geometry tells them apart.
			_separate_names.append("%s @(%d,%d) first seen %d" % [
				states[i].get("name", "unit%d" % i),
				int(states[i].get("pos_x", -1)), int(states[i].get("pos_z", -1)),
				_separate_first_seen[i - 3]])

	# Quit the moment both casts have been snapshotted — the SEPARATE one only
	# counts once the settle window above has actually read the three targets.
	# The ceiling is the failure path: reaching it means a cast never resolved.
	if (_random_landed_at >= 0 and not _separate_sets.is_empty()) \
			or current_tick >= max_ticks - 1:
		_print_results()


func _print_results() -> void:
	if _results_printed:
		return
	_results_printed = true

	var failures: Array[String] = []

	print("\n=== INFLICT MODE TEST RESULTS ===")

	# --- Arm 1: RANDOM lands exactly one -----------------------------------
	var random_count: int = _popcount(_random_bits_at_landing)
	print("  RANDOM  LookofDevil -> RandomTarget: landed tick %d (frame span %d), %d of %d listed statuses set (%s)" % [
		_random_landed_at, _random_landing_span, random_count, RANDOM_STATUSES.size(),
		_names_in(_random_bits_at_landing, RANDOM_STATUSES)])
	if _random_landed_at < 0:
		failures.append("LookofDevil set none of its %d listed statuses in %d ticks — formula 80 applies with no hit roll, so the cast either never resolved or RANDOM is still the fall-through" % [
			RANDOM_STATUSES.size(), max_ticks])
	elif _random_landing_span >= SECOND_CAST_FLOOR:
		# The instrument's own control: a frame this wide could hold two casts,
		# and then "exactly one" is unbounded. A measurement failure, not a
		# verdict — so it reds rather than passing on a number it cannot defend.
		failures.append("the frame that first saw a LookofDevil status banked %d ticks, at or past the %d-tick two-cast floor — arm 1 cannot tell one cast from two, so this run measured the box" % [
			_random_landing_span, SECOND_CAST_FLOOR])
	elif random_count != 1:
		failures.append("LookofDevil set %d of its %d listed statuses in one cast; RANDOM picks exactly one (%d is what ALL would give)" % [
			random_count, RANDOM_STATUSES.size(), RANDOM_STATUSES.size()])

	# --- Arms 2-4: SEPARATE over three targets ------------------------------
	print("  SEPARATE GrandCross: landed tick %d (frame span %d)" % [
		_separate_landed_at, _separate_landing_span])
	if _separate_landed_at < 0:
		failures.append("GrandCross landed nothing on any of its three targets in %d ticks; formula 56 applies with no hit roll, so either all 27 per-status rolls came up empty (P = 8.2e-4), the cast never resolved, or SEPARATE is still the fall-through" % max_ticks)
	elif _separate_landing_span >= SECOND_CAST_FLOOR:
		failures.append("the frame that first saw a GrandCross status banked %d ticks, at or past the %d-tick two-cast floor — arms 2-4 cannot tell one cast from two" % [
			_separate_landing_span, SECOND_CAST_FLOOR])
	else:
		var union := 0
		for i in range(_separate_sets.size()):
			union |= _separate_sets[i]
			print("    %-34s: %d of %d set (%s)" % [
				_separate_names[i], _popcount(_separate_sets[i]),
				SEPARATE_STATUSES.size(),
				_names_in(_separate_sets[i], SEPARATE_STATUSES)])
			# Arm 2 — no bit outside the listed nine.
			if _separate_strays[i] != 0:
				failures.append("%s carries status bits outside GrandCross's listed nine (stray mask 0x%X)" % [
					_separate_names[i], _separate_strays[i]])

		# Arm 3 — the three outcomes are not all the same.
		var all_same: bool = _separate_sets[0] == _separate_sets[1] \
			and _separate_sets[1] == _separate_sets[2]
		print("    per-target sets identical? %s" % all_same)
		if all_same:
			failures.append("all three GrandCross targets came out with the same status set (0x%X) — one cast is 27 independent rolls, so this is ALL, CANCEL-shaped, or no-op, not SEPARATE" % _separate_sets[0])

		# Arm 4 — anti-vacuity. Redundant with arm 3's all-empty case on purpose:
		# "nothing landed" and "everything landed the same" are different findings
		# and a reader should not have to work out which one reddened.
		if union == 0:
			failures.append("GrandCross's three targets all came out empty at the landing frame")

	print("  assertions: 4 arms, %d failed" % failures.size())
	for f in failures:
		print("    - %s" % f)
	print("=================================\n")
	if failures.is_empty():
		print("[PASS] GPUInflictMode: RANDOM landed exactly one of five, SEPARATE rolled each of nine per target")
	else:
		print("[FAIL] GPUInflictMode: %d of 4 arms failed" % failures.size())
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	# Nothing in this fixture deals damage, so a victory here means something
	# other than the two casts ended the battle — score whatever was snapshotted
	# rather than letting the runner kill the process with no verdict.
	if not _results_printed:
		_print_results()


static func _popcount(v: int) -> int:
	var n := 0
	while v != 0:
		n += v & 1
		v >>= 1
	return n


## The set's member names, for a log line a reader can act on. An empty set
## prints "none" rather than an empty string, so a zero is legible.
static func _names_in(mask: int, names: Array[StringName]) -> String:
	var hit: Array[String] = []
	for n in names:
		if (mask & (1 << StatusRegistry.bit(n))) != 0:
			hit.append(String(n))
	return "none" if hit.is_empty() else ", ".join(hit)


static func _merge(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate()
	for key in overrides:
		result[key] = overrides[key]
	return result
