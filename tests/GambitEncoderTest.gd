extends Node
## Pure GambitEncoder test (ADR-0023). No GPU / RenderingDevice / scene setup.
## Verifies the Gambit-object -> GPU config projection:
##   1. Supported targets / conditions / actions encode to the right GPU enums.
##   2. Every UNSUPPORTED feature SKIPS the gambit (encodes to null) rather than
##      silently substituting NEAREST / ALWAYS / ATTACK.
## Complements GambitEncodeSchemaTest (the config-dict -> buffer side, ADR-0016).
##
## The unsupported cases intentionally emit push_error — those ERROR lines are
## expected and do not fail the run (the harness keys off [PASS]/[FAIL]).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector
const UnitRole = ExMateriaSchema.UnitRole
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const AbilityFamily = ExMateriaAlmanac.AbilityFamily


var _failed := false


func _ready() -> void:
	_test_supported()
	_test_status_conditions()
	_test_ko_alive_and_distance()
	_test_unsupported()
	_test_every_offered_choice_round_trips()
	_test_the_subject_column_reaches_the_rank_walk()
	_audit_every_aim_cell()
	_audit_ability_family()
	if _failed:
		print("[FAIL] GambitEncoder test")
	else:
		print("[PASS] GambitEncoder: supported mappings + UNSUPPORTED skip-on-encode"
			+ " + every choice the gambit surface OFFERS round-trips with no skip (ADR-0268 dec. 8)"
			+ " + every (verb x aim) cell graded and no offered aim or seed is broken (ADR-0276)"
			+ " + every reachable ability classifies into a family and seeds its pool (ADR-0278)"
			+ " + the Subject column reaches the kernel's rank walk (ADR-0283) + the POOL rows do and the DEPTH rows deliberately do not (ADR-0285)")
	get_tree().quit()


func _enc(g: Gambit):
	# Encode a single gambit; returns its config Dictionary, or null if skipped.
	return GambitEncoder.encode_gambits([g])[0]


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("[FAIL] %s" % msg)


func _expect_skipped(label: String, g: Gambit) -> void:
	var c = _enc(g)
	_expect(c == null, "%s should skip (encode to null), got %s" % [label, str(c)])


func _test_supported() -> void:
	var GP := GPUConstants

	# Attack the nearest enemy, always.
	var g1 := Gambit.create(
		TargetSelector.enemies(), [GambitCondition.always()],
		Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())
	var c1 = _enc(g1)
	_expect(c1 != null, "attack/nearest-enemy/always should encode")
	if c1 != null:
		_expect(c1["action_type"] == GP.ACTION_ATTACK, "action_type == ATTACK")
		_expect(c1["action_id"] == 0, "attack action_id == 0")
		_expect(c1["cond_target_type"] == GP.TARGET_NEAREST_ENEMY, "cond_target == NEAREST_ENEMY")
		_expect(c1["action_target_type"] == GP.TARGET_THEM, "action_target == THEM (triggering)")
		_expect(c1["conditions"].size() == 1 and c1["conditions"][0]["type"] == GP.COND_ALWAYS,
			"single ALWAYS condition")

	# Cast ability id 42 on the most-critical ally, when target HP < 50.
	var heal := TargetSelector.friendlies().with_resolution(TargetSelector.ResolutionStrategy.MOST_CRITICAL)
	var hp_lt := GambitCondition.new(GambitCondition.Type.TARGET_HP, GambitCondition.Comparator.LESS_THAN, 50.0)
	var g2 := Gambit.create(heal, [hp_lt], Gambit.ActionKind.ABILITY, 42, heal)
	var c2 = _enc(g2)
	_expect(c2 != null, "ability/most-critical-ally should encode")
	if c2 != null:
		_expect(c2["action_type"] == GP.ACTION_SPELL, "ability action_type == SPELL")
		_expect(c2["action_id"] == 42, "ability_id passthrough (42)")
		_expect(c2["cond_target_type"] == GP.TARGET_LOWEST_HP_ALLY, "cond_target == LOWEST_HP_ALLY")
		_expect(c2["action_target_type"] == GP.TARGET_LOWEST_HP_ALLY, "action_target == LOWEST_HP_ALLY")
		_expect(c2["conditions"][0]["type"] == GP.COND_HP_BELOW and c2["conditions"][0]["value"] == 50,
			"TARGET_HP < 50 -> COND_HP_BELOW 50")

	# In range of whatever this slot does -> COND_IN_RANGE with NO value (ADR-0268 dec. 11,
	# #32 drained). The value word must be 0 and not a range: the kernel resolves the reach from
	# the gambit's own action, and a number here would be a second, stale answer — throw range
	# is `speed / 2 + 1`, which moves with a Speed Break mid-battle.
	var near_foe := TargetSelector.enemies().with_resolution(TargetSelector.ResolutionStrategy.NEAREST_FIRST)
	var g_range := Gambit.create(near_foe, [GambitCondition.target_in_range()],
		Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())
	var c_range = _enc(g_range)
	_expect(c_range != null, "TARGET_IN_RANGE should ENCODE now — it left UNSUPPORTED_CONDITION_TYPES")
	if c_range != null:
		_expect(c_range["conditions"][0]["type"] == GP.COND_IN_RANGE,
			"TARGET_IN_RANGE -> COND_IN_RANGE")
		_expect(c_range["conditions"][0]["value"] == 0,
			"and carries NO value — the reach is the ACTION'S, not the condition's")

	# Wait on self; SELF_MP > 20.
	var mp_gt := GambitCondition.new(GambitCondition.Type.SELF_MP, GambitCondition.Comparator.GREATER_THAN, 20.0)
	var g3 := Gambit.create(TargetSelector.self_(), [mp_gt], Gambit.ActionKind.WAIT, -1, TargetSelector.self_())
	var c3 = _enc(g3)
	_expect(c3 != null, "wait/self should encode")
	if c3 != null:
		_expect(c3["action_type"] == GP.ACTION_WAIT, "action_type == WAIT")
		_expect(c3["cond_target_type"] == GP.TARGET_SELF, "cond_target == SELF")
		_expect(c3["conditions"][0]["type"] == GP.COND_MP_ABOVE and c3["conditions"][0]["value"] == 20,
			"SELF_MP > 20 -> COND_MP_ABOVE 20")

	# Move (unit-anchored) toward the nearest enemy, always (ADR-0062). The action
	# is ACTION_MOVE_TO_UNIT with action_id unused; the destination unit is encoded
	# via the action_target through the shared selector mapping.
	var g4 := Gambit.create(
		TargetSelector.self_(), [GambitCondition.always()],
		Gambit.ActionKind.MOVE, -1, TargetSelector.enemies())
	var c4 = _enc(g4)
	_expect(c4 != null, "move/nearest-enemy/always should encode")
	if c4 != null:
		_expect(c4["action_type"] == GP.ACTION_MOVE_TO_UNIT, "move action_type == MOVE_TO_UNIT")
		_expect(c4["action_id"] == 0, "move action_id == 0 (unused)")
		_expect(c4["action_target_type"] == GP.TARGET_NEAREST_ENEMY, "move action_target == NEAREST_ENEMY")

	# Move toward the most-critical ally (regroup-style composition).
	var rally := TargetSelector.friendlies().with_resolution(TargetSelector.ResolutionStrategy.MOST_CRITICAL)
	var g5 := Gambit.create(
		TargetSelector.self_(), [GambitCondition.always()],
		Gambit.ActionKind.MOVE, -1, rally)
	var c5 = _enc(g5)
	_expect(c5 != null, "move/most-critical-ally should encode")
	if c5 != null:
		_expect(c5["action_type"] == GP.ACTION_MOVE_TO_UNIT, "move action_type == MOVE_TO_UNIT (ally)")
		_expect(c5["action_target_type"] == GP.TARGET_LOWEST_HP_ALLY, "move action_target == LOWEST_HP_ALLY")


func _test_status_conditions() -> void:
	# HAS_STATUS / MISSING_STATUS route status_id (StringName) through
	# StatusRegistry to a bit index in [0,32). The shader at
	# stage_compute.glsl:100-104 reads condition_value as that bit index.
	# Unknown name skips the gambit (push_error is loud-fail, not silent COND_ALWAYS).
	var GP := GPUConstants
	var enemy := TargetSelector.enemies()
	var them := TargetSelector.triggering()

	# HAS_STATUS(&"silence") → COND_HAS_STATUS, value=25.
	var g_has := Gambit.create(enemy, [GambitCondition.has_status(&"silence")],
		Gambit.ActionKind.ATTACK, -1, them)
	var c_has = _enc(g_has)
	_expect(c_has != null, "HAS_STATUS(silence) should encode")
	if c_has != null:
		_expect(c_has["conditions"].size() == 1, "one condition emitted")
		var cond_h: Dictionary = c_has["conditions"][0]
		_expect(cond_h["type"] == GP.COND_HAS_STATUS, "HAS_STATUS → COND_HAS_STATUS")
		_expect(cond_h["value"] == 25, "HAS_STATUS(silence).value == 25 (got %d)" % cond_h["value"])

	# MISSING_STATUS(&"poison") → COND_NOT_STATUS, value=15.
	var g_miss := Gambit.create(enemy, [GambitCondition.missing_status(&"poison")],
		Gambit.ActionKind.ATTACK, -1, them)
	var c_miss = _enc(g_miss)
	_expect(c_miss != null, "MISSING_STATUS(poison) should encode")
	if c_miss != null:
		var cond_m: Dictionary = c_miss["conditions"][0]
		_expect(cond_m["type"] == GP.COND_NOT_STATUS, "MISSING_STATUS → COND_NOT_STATUS")
		_expect(cond_m["value"] == 15, "MISSING_STATUS(poison).value == 15 (got %d)" % cond_m["value"])

	# Unknown name → encoder-skip + push_error (ADR-0023). The ERROR line is
	# expected output, not a test failure.
	_expect_skipped("HAS_STATUS(unknown_name)",
		Gambit.create(enemy, [GambitCondition.has_status(&"definitely_not_a_status")],
			Gambit.ActionKind.ATTACK, -1, them))


## The four conditions the kernel always answered and nobody could ask (#1102), plus the one
## pool a corpse survives. Charter clause 13 — all of it shares `_enc`, so it is one process.
##
## 🔴 THE TRAP THIS EXISTS TO CLOSE. `has_status(&"dead")` is the obvious spelling of the revive
## gambit, it is a perfectly faithful ADR-0023 translation, it passes every encoder guard — and
## it encodes to `COND_HAS_STATUS` on status BIT 0, which nothing in the tree sets. The gambit
## never fires. So this asserts the two spellings produce DIFFERENT encodings, not just that
## `is_ko()` produces a right one: a guard that only checked `is_ko()` would stay green with the
## trap wide open beside it.
func _test_ko_alive_and_distance() -> void:
	var GP := GPUConstants
	var them := TargetSelector.triggering()
	var fallen := TargetSelector.friendlies_or_ko()

	# --- IS_KO reaches FLAG_DEAD, not status bit 0 -----------------------------------------
	var g_ko := Gambit.create(fallen, [GambitCondition.is_ko()],
		Gambit.ActionKind.ABILITY, 42, them)
	var c_ko = _enc(g_ko)
	_expect(c_ko != null, "is_ko() over a KO-inclusive ally pool should encode")
	if c_ko != null:
		var cond_k: Dictionary = c_ko["conditions"][0]
		_expect(cond_k["type"] == GP.COND_IS_DEAD, "IS_KO -> COND_IS_DEAD (got %d)" % cond_k["type"])
		_expect(cond_k["type"] != GP.COND_HAS_STATUS,
			"IS_KO must NOT route through COND_HAS_STATUS — bit 0 is hollow and never fires")
		_expect(cond_k["value"] == 0, "IS_KO carries no value")
		_expect(c_ko["cond_target_type"] == GP.TARGET_NEAREST_ALLY_OR_KO,
			"friendlies_or_ko() -> TARGET_NEAREST_ALLY_OR_KO, the only pool a corpse survives")

	# The trap, encoded side by side so the difference is asserted and not assumed. This one
	# still encodes — bit 0's FATE is the status audit's call, not this test's — but it must
	# not be what `is_ko()` produces.
	var g_trap := Gambit.create(fallen, [GambitCondition.has_status(&"dead")],
		Gambit.ActionKind.ABILITY, 42, them)
	var c_trap = _enc(g_trap)
	_expect(c_trap != null, 'has_status(&"dead") still encodes (bit 0 is a registered name)')
	if c_trap != null and c_ko != null:
		var cond_t: Dictionary = c_trap["conditions"][0]
		_expect(cond_t["type"] == GP.COND_HAS_STATUS and cond_t["value"] == 0,
			'has_status(&"dead") encodes to COND_HAS_STATUS on bit 0 — the silent-never-fires form')
		_expect(cond_t["type"] != c_ko["conditions"][0]["type"],
			'the two spellings of death must encode DIFFERENTLY: is_ko() reads FLAG_DEAD,'
			+ ' has_status(&"dead") reads a status bit nothing sets')

	# --- IS_ALIVE --------------------------------------------------------------------------
	var g_alive := Gambit.create(fallen, [GambitCondition.is_alive()],
		Gambit.ActionKind.ATTACK, -1, them)
	var c_alive = _enc(g_alive)
	_expect(c_alive != null, "is_alive() should encode")
	if c_alive != null:
		_expect(c_alive["conditions"][0]["type"] == GP.COND_IS_ALIVE, "IS_ALIVE -> COND_IS_ALIVE")

	# --- TARGET_DISTANCE, both directions --------------------------------------------------
	var enemy := TargetSelector.enemies()
	var g_near := Gambit.create(enemy, [GambitCondition.target_within(3.0)],
		Gambit.ActionKind.ATTACK, -1, them)
	var c_near = _enc(g_near)
	_expect(c_near != null, "target_within(3) should encode")
	if c_near != null:
		_expect(c_near["conditions"][0]["type"] == GP.COND_DISTANCE_LESS, "target_within -> COND_DISTANCE_LESS")
		_expect(c_near["conditions"][0]["value"] == 3, "and carries the TILE threshold (3)")

	var g_far := Gambit.create(enemy, [GambitCondition.target_beyond(3.0)],
		Gambit.ActionKind.ATTACK, -1, them)
	var c_far = _enc(g_far)
	_expect(c_far != null, "target_beyond(3) should encode")
	if c_far != null:
		_expect(c_far["conditions"][0]["type"] == GP.COND_DISTANCE_GREATER, "target_beyond -> COND_DISTANCE_GREATER")

	# EQUALS has no kernel arm. Skipping is the point: folding `== 3` into `> 3` would be the
	# silent substitution ADR-0023 bans, and the HP/MP arms above do exactly that fold today.
	var dist_eq := GambitCondition.new(GambitCondition.Type.TARGET_DISTANCE,
		GambitCondition.Comparator.EQUALS, 3.0)
	_expect_skipped("TARGET_DISTANCE with EQUALS",
		Gambit.create(enemy, [dist_eq], Gambit.ActionKind.ATTACK, -1, them))

	# --- include_ko is UNSUPPORTED everywhere it has no GPU spelling ------------------------
	# Not "ignored": dropping the flag would hand the author a KO-blind pool that reads back as
	# KO-inclusive — the readout agreeing while the unit does not (ADR-0268 dec. 8's failure).
	var ok_cond := [GambitCondition.always()]
	var ko_critical := TargetSelector.friendlies_or_ko().with_resolution(
		TargetSelector.ResolutionStrategy.MOST_CRITICAL)
	_expect_skipped("include_ko + MOST_CRITICAL (a corpse is 0% HP and would win every time)",
		Gambit.create(ko_critical, ok_cond, Gambit.ActionKind.ATTACK, -1, them))
	var ko_enemy := TargetSelector.enemies()
	ko_enemy.include_ko = true
	_expect_skipped("include_ko on an ENEMY pool", Gambit.create(ko_enemy, ok_cond, Gambit.ActionKind.ATTACK, -1, them))
	var ko_self := TargetSelector.self_()
	ko_self.include_ko = true
	_expect_skipped("include_ko on SELF", Gambit.create(ko_self, ok_cond, Gambit.ActionKind.ATTACK, -1, them))
	var ko_them := TargetSelector.triggering()
	ko_them.include_ko = true
	_expect_skipped("include_ko on TRIGGERING", Gambit.create(ko_them, ok_cond, Gambit.ActionKind.ATTACK, -1, them))

	# --- serialisation ---------------------------------------------------------------------
	# `to_dict` writes `type` as its ORDINAL, so a saved gambit list re-reads every member by
	# POSITION. Pinning one pre-existing ordinal is what makes "appended, never inserted" a
	# guarded rule instead of a comment: insert IS_KO anywhere above and this reds.
	_expect(int(GambitCondition.Type.TARGET_IN_RANGE) == 15,
		"TARGET_IN_RANGE must stay ordinal 15 — new Type members are APPENDED, never inserted,"
		+ " or every saved gambit list shifts meaning (got %d)" % int(GambitCondition.Type.TARGET_IN_RANGE))
	var round_tripped = GambitCondition.from_dict(GambitCondition.target_within(4.0).to_dict())
	_expect(round_tripped.type == GambitCondition.Type.TARGET_DISTANCE and int(round_tripped.threshold) == 4,
		"TARGET_DISTANCE survives to_dict/from_dict")
	var sel_rt = TargetSelector.from_dict(TargetSelector.friendlies_or_ko().to_dict())
	_expect(sel_rt.include_ko, "include_ko survives to_dict/from_dict — a dropped flag silently"
		+ " demotes a revive gambit to a KO-blind one")


func _test_unsupported() -> void:
	# Each gambit is valid except for one UNSUPPORTED feature -> must skip (null).
	var ok_cond := [GambitCondition.always()]
	var enemy := TargetSelector.enemies()
	var them := TargetSelector.triggering()

	# Action axis. (MOVE is now supported — ADR-0062 — and covered in _test_supported.)
	_expect_skipped("ABILITY without id",
		Gambit.create(enemy, ok_cond, Gambit.ActionKind.ABILITY, -1, them))
	# MOVE whose action_target is an UNSUPPORTED selector still skips (inherits the
	# selector's support set): move to a SPECIFIC unit has no GPU target.
	_expect_skipped("MOVE to SPECIFIC_UNITS target",
		Gambit.create(TargetSelector.self_(), ok_cond, Gambit.ActionKind.MOVE, -1,
			TargetSelector.specific(["Ramza"])))

	# Condition axis.
	for ct in [GambitCondition.Type.ENEMY_IN_RANGE, GambitCondition.Type.ENEMY_COUNT, GambitCondition.Type.HP_MISSING]:
		var bad := GambitCondition.new(ct, GambitCondition.Comparator.LESS_THAN, 1.0)
		_expect_skipped("condition %s" % GambitCondition.Type.keys()[ct],
			Gambit.create(enemy, [bad], Gambit.ActionKind.ATTACK, -1, them))

	# Target axis (placed as condition_target — checked first).
	_expect_skipped("SPECIFIC_UNITS target",
		Gambit.create(TargetSelector.specific(["Ramza"]), ok_cond, Gambit.ActionKind.ATTACK, -1, them))
	_expect_skipped("role_filter target",
		Gambit.create(TargetSelector.enemies(UnitRole.Role.MELEE), ok_cond, Gambit.ActionKind.ATTACK, -1, them))
	_expect_skipped("HIGHEST_STAT resolution",
		Gambit.create(
			TargetSelector.friendlies().with_resolution(TargetSelector.ResolutionStrategy.HIGHEST_STAT, &"HP"),
			ok_cond, Gambit.ActionKind.ATTACK, -1, them))
	var any_team := TargetSelector.new()
	any_team.pool_type = TargetSelector.PoolType.TEAM_FILTER
	any_team.team_filter = TargetSelector.TeamFilter.ANY
	_expect_skipped("TeamFilter.ANY target",
		Gambit.create(any_team, ok_cond, Gambit.ActionKind.ATTACK, -1, them))


## ADR-0268 dec. 8 — EVERY CHOICE THE GAMBIT SURFACE OFFERS ROUND-TRIPS, WITH NO SKIP.
##
## The other direction of `_test_unsupported`, and the one that costs the player something. E1
## makes an unsupported gambit a null slot: `push_error`, and evaluation falls through. So a
## screen that OFFERS an unsupported choice hands the player a rule that **reads back correctly
## in its own row and never fires** — the readout agrees and the unit does not, which is the one
## failure an authoring surface cannot let the player diagnose.
##
## Asserted over the whole CROSS-PRODUCT of the offered vocabularies, not a sample: the surface
## edits the parts INDEPENDENTLY (ADR-0268 dec. 1 — ←/→ walk them, each ○ lands one), so the
## reachable set IS every combination, and a per-list spot check would miss a pair that only
## fails together. This is not the "nonsense cross-product" ADR-0255 dec. 3 rejected — that was
## raw enum FIELDS; every cell here is a whole domain value built by a domain constructor.
##
## The product is `If` x `Subject` x `To` x `Do` — FOUR axes since ADR-0283 dec. 1, where
## ADR-0268 dec. 2 had three. The subject is a column again, so it is a thing the player can
## move on its own, and a cell is only covered if the guard moves it on its own too.
##
## `Subject` carries the BLANK row as well as `My` / `Their`, and blank is the axis value the
## fold could not produce: it writes a zero-length `conditions` array with `condition_target`
## MIRRORING the aim, which is the encoding every unconditional row now takes. Leaving it out
## would test four columns and ship three.
##
## THE RED ARM, MEASURED, not imagined: with `In Melee Range` / `In Spell Range` restored to
## `GambitOptions.conditions()` — where the shipped surface had them — this printed
## [b]216 failures[/b] and none without, against the pre-fold catalogue (2 conditions x 6 "To"
## x 6 "When" x 3 verbs). Re-measure rather than trusting that number if the catalogue moves;
## what matters is that it is the whole product those entries poison and not a sample.
##
## Scene-free on purpose: [GambitOptions] is static, so this needs no surface, no character and
## no battle. A guard that reached through the screen would need all three, for an assertion
## about two arrays.
func _test_every_offered_choice_round_trips() -> void:
	var targets := GambitOptions.targets()
	var conditions := GambitOptions.conditions()
	var subjects := GambitOptions.subjects()
	var verbs := GambitOptions.action_verbs()
	_expect(not targets.is_empty() and not conditions.is_empty() and not verbs.is_empty()
			and not subjects.is_empty(),
		"the offered catalogues must be non-empty — an EMPTY list round-trips vacuously,"
		+ " which is this guard's own way of going blind")

	# The `If` axis, with BLANK as a value rather than as a missing case. A `null` entry here
	# stands for the blank row, and the loop below builds it the way the surface does: no
	# condition, subject mirroring the aim.
	var if_axis: Array = [null]
	if_axis.append_array(conditions)
	# The `Subject` axis, likewise — `null` is the blank column, which only occurs with a blank
	# `If` and is therefore skipped against a real one.
	var subj_axis: Array = [null]
	subj_axis.append_array(subjects)

	var cells := 0
	for cond_entry in if_axis:
		for subj_entry in subj_axis:
			# Blank and set go TOGETHER on both columns: a subject is who a question is about,
			# so "no question with a subject" and "a question about nobody" are not states the
			# screen can produce, and asserting them would grade cells the player cannot reach.
			if (cond_entry == null) != (subj_entry == null):
				continue
			for to_entry in targets:
				for verb_entry in verbs:
					var picked: Dictionary = verb_entry["make"].call()
					var aim = to_entry["make"].call()
					var conds: Array = [] if cond_entry == null else [cond_entry["make"].call()]
					var subject = TargetSelector.from_dict(aim.to_dict()) if subj_entry == null \
						else subj_entry["make"].call(aim)
					var g := Gambit.create(subject, conds,
						picked["kind"], int(picked["ability_id"]), aim)
					var label := "Do '%s' / To '%s' / Subject '%s' / If '%s'" % [
						verb_entry["name"], to_entry["name"],
						"—" if subj_entry == null else subj_entry["name"],
						"—" if cond_entry == null else cond_entry["name"]]
					_expect(_enc(g) != null,
						"%s is OFFERED but E1-SKIPS — the player would author a row that reads"
						% label + " back correctly and never fires (ADR-0268 dec. 8)")
					cells += 1
	_expect(cells == (conditions.size() * subjects.size() + 1) * targets.size() * verbs.size(),
		"the product walked %d cells, which is not `(If x Subject + blank) x To x Do` — a"
			% cells
		+ " miscounted product is a product with a hole in it")

	# Each `If` AND `Subject` entry must READ BACK as itself. The row is the readout (ADR-0268
	# dec. 1), so a label that could not find its own catalogue row would print the domain's
	# fallback text and the player would see a string the list does not offer — the same class
	# of lie as an unencodable choice, caught in the same place because it has the same cause:
	# two descriptions of one value drifting apart.
	#
	# READ BACK AGAINST A FOE AIM, not against `triggering()`. `subject_label` answers `My` for
	# a SELF pool and `Their` for anything else, so a subject probed against an aim that
	# resolves to the actor would read `My` whichever row built it — the assertion would pass
	# for both rows and distinguish neither.
	for cond_entry in conditions:
		for subj_entry in subjects:
			# `Always` IS NOT IN THIS GRID, and skipping it is the assertion rather than a hole:
			# it is the one subject row that also writes the CONDITION, so pairing it with an
			# `If` entry builds a cell the screen cannot produce and grades a reading no player
			# can reach. Its own readback is directly below, driven from the same catalogue flag
			# the surface consults — so a build that dropped the flag reds there.
			if bool(subj_entry.get(GambitOptions.UNCONDITIONAL, false)):
				continue
			var aim = GambitOptions.foe_pool()
			var g2 := Gambit.create(subj_entry["make"].call(aim), [cond_entry["make"].call()],
				Gambit.ActionKind.ATTACK, -1, aim)
			_expect(GambitOptions.condition_label(g2) == String(cond_entry["name"]),
				"If '%s' must read back as itself, got '%s'"
				% [cond_entry["name"], GambitOptions.condition_label(g2)])
			_expect(GambitOptions.subject_label(g2) == String(subj_entry["name"]),
				"Subject '%s' must read back as itself, got '%s'"
				% [subj_entry["name"], GambitOptions.subject_label(g2)])

	# `Always` READS BACK AS ITSELF, off the row the CATALOGUE marks rather than off a literal —
	# and the row is built the way the surface builds it, mirrored selector plus the explicit
	# `ALWAYS` condition (`GambitSurface._write_unconditional`).
	var uncond: Dictionary = {}
	for subj_entry in subjects:
		if bool(subj_entry.get(GambitOptions.UNCONDITIONAL, false)):
			uncond = subj_entry
	_expect(not uncond.is_empty(),
		"the subject catalogue must carry exactly one row flagged `%s` — it is the row that"
			% GambitOptions.UNCONDITIONAL
		+ " answers 'no test', and without the FLAG the surface writes an ordinary subject and"
		+ " the row keeps its `If` column while claiming not to have one")
	if not uncond.is_empty():
		var aim3 = GambitOptions.foe_pool()
		var g3 := Gambit.create(uncond["make"].call(aim3), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, aim3)
		_expect(_enc(g3) != null,
			"an `Always` row must ENCODE — `Type.ALWAYS` maps to `COND_ALWAYS` and is not in"
			+ " UNSUPPORTED_CONDITION_TYPES, and a row the screen offers that E1-skips is"
			+ " ADR-0268 dec. 8's whole subject")
		_expect(GambitOptions.subject_label(g3) == GambitOptions.SUBJECT_ALWAYS,
			"…and read back as `%s` in the SUBJECT column, got '%s'"
			% [GambitOptions.SUBJECT_ALWAYS, GambitOptions.subject_label(g3)])
		# THE PARK NEVER REACHES THE GPU, and this is the arm that says so. `parked_condition` is
		# screen state on a domain object, so the one way it can do damage is by being encoded —
		# and `check_gambit_conditions` ANDs every entry it is given, so a park that leaked into
		# the buffer would make an `Always` row fire only when the predicate the player SET ASIDE
		# passed. Graded on the encoded cond_count, not on the field.
		var parked_g := Gambit.create(uncond["make"].call(aim3), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, aim3)
		parked_g.parked_condition = GambitCondition.target_hp_below(50.0)
		var c_parked = _enc(parked_g)
		_expect(c_parked != null and c_parked["conditions"].size() == 1
				and c_parked["conditions"][0]["type"] == GPUConstants.COND_ALWAYS,
			"an `Always` row with a PARKED predicate encodes ONE condition — the `ALWAYS` — and"
			+ " the park is not among them, or the row reads `Always` and fires below half HP")

		# AND IT SURVIVES A SAVE, because the flip the player wants undone outlives a reload. A
		# park that evaporated would restore a predicate today and a blank tomorrow from one
		# visible row state.
		var round_tripped = Gambit.from_dict(parked_g.to_dict())
		_expect(round_tripped.parked_condition != null
				and round_tripped.parked_condition.type == GambitCondition.Type.TARGET_HP
				and is_equal_approx(round_tripped.parked_condition.threshold, 50.0),
			"…and `parked_condition` round-trips through to_dict/from_dict")

		# AN OLD SAVE HAS NO SUCH KEY, and absent must already mean "nothing parked" — every
		# gambit ever written predates the field.
		var legacy := Gambit.create(TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())
		var legacy_dict := legacy.to_dict()
		_expect(not legacy_dict.has("parked_condition"),
			"a gambit with nothing parked OMITS the key rather than writing null — or every old"
			+ " save round-trips into a file that differs on a field nothing can see")
		_expect(Gambit.from_dict(legacy_dict).parked_condition == null,
			"…and a dict without the key loads as nothing parked")

		_expect(GambitOptions.is_unconditional(g3),
			"…and be the state the widget spans the `If` column on — the label and the predicate"
			+ " are two readings of one row and a build where they disagreed would draw a"
			+ " subject cell at the narrow cap with `Always` elided into it")

	# A BLANK CONDITION BLANKS THE `If` COLUMN AND ONLY THAT COLUMN, off the encoding the surface
	# actually writes — a zero-length `conditions` with the subject mirroring the aim. The
	# `ALWAYS` spelling reads back blank too: it is the same rule, and a save written before
	# ADR-0283 carries it (see `Gambit.is_empty`).
	#
	# 🔴 THE SUBJECT DOES NOT GO BLANK WITH IT, and this arm asserted that it did. ADR-0283
	# dec. 3 blanked it because "a subject with no question to be about is not a state the
	# screen can name" — but with no condition the subject is the row's GATE and nothing else:
	# `evaluate_gambits_up_to` runs `select_target` on the CONDITION target and writes
	# `VERDICT_NO_CANDIDATE` at `candidate < 0` BEFORE it consults `check_gambit_conditions`,
	# which returns true at zero conditions. So the column names a live switch on exactly these
	# rows, and blanking it made the player's `Subject` press invisible in left-to-right
	# authoring order (`GambitSurfaceTest`'s reading-order block).
	#
	# BOTH SUBJECTS ARE DRIVEN, not just the mirrored one — a build that hard-coded `Their`
	# would satisfy a `Their`-only arm, and `Their` is what the mirror invariant already puts
	# there.
	var aim2 = GambitOptions.foe_pool()
	var blank := Gambit.create(TargetSelector.from_dict(aim2.to_dict()), [],
		Gambit.ActionKind.ATTACK, -1, aim2)
	_expect(GambitOptions.condition_label(blank) == GambitOptions.BLANK,
		"a zero-condition row reads BLANK in the If column, got '%s'"
		% GambitOptions.condition_label(blank))
	_expect(GambitOptions.subject_label(blank) == GambitOptions.SUBJECT_THEIRS,
		"…and the Subject column still names the pool that row is GATED on, got '%s'"
		% GambitOptions.subject_label(blank))
	var blank_self := Gambit.create(TargetSelector.self_(), [],
		Gambit.ActionKind.ATTACK, -1, aim2)
	_expect(GambitOptions.subject_label(blank_self) == GambitOptions.SUBJECT_MINE,
		"…and the SAME row with the subject moved to the actor reads `My` — the column"
		+ " DISCRIMINATES on a conditionless row rather than printing the mirror's default,"
		+ " got '%s'" % GambitOptions.subject_label(blank_self))

	# =========================================================================================
	# 🔴 AND THE TWO SPELLINGS OF "NO CONDITION" READ DIFFERENTLY, WHICH THIS ARM USED TO FORBID.
	#
	# It looped `[[], [GambitCondition.always()]]` and required `Their` from both, on the
	# grounds that the kernel cannot tell them apart — `check_gambit_conditions` returns true at
	# zero conditions AND at one `ALWAYS`, so one behaviour ought to have one reading.
	#
	# That is true of the KERNEL and false of the SCREEN, and the counter-example is
	# `GambitSurfaceTest`'s reading-order arm. A row mid-authoring has a zero-length
	# `conditions`: the player has pressed `Do` and `To` and is about to press `Subject`. Read
	# zero as `Always` and that press changes nothing on screen — which is #1255's reported bug
	# (*"I can't select 'my' or 'their' until AFTER I have selected a condition"*) re-opened by
	# the fix that was supposed to finish it. So the two arrays are two ROW STATES:
	#
	#   []          no test CHOSEN YET     `My` / `Their`, and an `If` column reading `—`
	#   [ALWAYS]    no test, DECLARED      `Always`, and NO `If` column at all
	#
	# A pre-ADR-0283 save carrying a lone `ALWAYS` lands in the second line, which is what it
	# meant when it was written (ADR-0270 dec. 1) — so nothing a player authored reads wrong.
	var declared := Gambit.create(TargetSelector.from_dict(aim2.to_dict()),
		[GambitCondition.always()], Gambit.ActionKind.ATTACK, -1, aim2)
	_expect(GambitOptions.subject_label(declared) == GambitOptions.SUBJECT_ALWAYS,
		"an EXPLICIT `ALWAYS` condition reads `%s` in the Subject column, got '%s'"
		% [GambitOptions.SUBJECT_ALWAYS, GambitOptions.subject_label(declared)])
	_expect(GambitOptions.subject_label(blank) != GambitOptions.subject_label(declared),
		"…and the two spellings DIFFER — pinning either alone passes on a build that collapsed"
		+ " them, and collapsing them is what makes a `Subject` press invisible while the"
		+ " player is authoring left to right")
	_expect(GambitOptions.is_unconditional(declared)
			and not GambitOptions.is_unconditional(blank),
		"…and the predicate the widget spans on splits them the same way the label does, or the"
		+ " row would print `Always` into the 20-px cap the `If` column was still occupying")

	# The ability rows are not in the catalogue (they are the unit's job's, not the screen's),
	# so the one way THEY can fail the gate is asserted directly: a real id encodes, and the
	# -1 the verbs carry must never reach an ABILITY.
	var with_id := Gambit.create(TargetSelector.enemies(), [GambitCondition.always()],
		Gambit.ActionKind.ABILITY, 8, TargetSelector.triggering())
	_expect(_enc(with_id) != null, "an ABILITY carrying a real id must encode")


## ADR-0283 — WHAT THE FOURTH COLUMN IS FOR: `Their` REACHES THE KERNEL'S SECOND PASS.
##
## This is the only assertion that grades the CHANGE rather than the layout, and without it the
## whole ticket is a cosmetic one. `evaluate_gambits_up_to` is two-pass: Pass 1 tests the
## condition against rank 0, and Pass 2 walks `find_nth_nearest` at rank 1, 2, 3… RETESTING the
## condition at each rank. It does that for exactly three condition targets —
## `TARGET_NEAREST_ENEMY`, `TARGET_NEAREST_ALLY`, `TARGET_NEAREST_ALLY_OR_KO` — and writes
## `VERDICT_NOT_RETRYABLE` for every other one.
##
## THE FOLDED CATALOGUE COULD NOT PRODUCE ANY OF THE THREE FOR AN ALLY. Every `Ally HP<X%` row
## bound its subject to MOST_CRITICAL friendlies, which `_target_selector_to_gpu` maps to
## `TARGET_LOWEST_HP_ALLY` — so the screen offered the one ally subject that switches the rank
## walk OFF, and *"the nearest ally whose HP is below half"* was inexpressible from it. The
## kernel has always been able to run that sentence; the screen could not say it.
##
## ⚠️ **SINCE ADR-0285 THE `Their` ROW IS `Ally`, NOT `Nearest Ally`, AND THE SWAP IS THE
## POINT.** The three retryable types listed above are exactly the pool rows; `Nearest Ally` and
## `Nearest Foe` now encode `TARGET_NEAREST_ALLY_ONLY` / `TARGET_NEAREST_ENEMY_ONLY`, which
## Pass 2 does NOT list and therefore does not walk. So this function grades BOTH axes off one
## table — the pool rows retry, the depth rows do not — and either arm alone would be satisfied
## by a build that had collapsed the distinction in one direction.
##
## Asserted on the ENCODED field and against the kernel's own retryable set, not on a label: a
## readout can agree with the player while the buffer disagrees with both, which is the failure
## class this whole surface is built against.
func _test_the_subject_column_reaches_the_rank_walk() -> void:
	# The kernel's retryable set, restated from `stage_compute.glsl`'s Pass 2 guard. Restated
	# and not imported because GPUConstants carries the VALUES and the shader carries the
	# POLICY; if the policy moves, this list is the thing that should have to move with it.
	var retryable := [GPUConstants.TARGET_NEAREST_ALLY, GPUConstants.TARGET_NEAREST_ENEMY,
		GPUConstants.TARGET_NEAREST_ALLY_OR_KO]

	var subjects := GambitOptions.subjects()
	var theirs = null
	for s in subjects:
		if String(s["name"]) == GambitOptions.SUBJECT_THEIRS:
			theirs = s
	_expect(theirs != null,
		"the subject catalogue must carry `%s` — it is the row the rank walk hangs off"
			% GambitOptions.SUBJECT_THEIRS)
	if theirs == null:
		return

	# 🔴 ADR-0285 — THE DEPTH AXIS IS ASSERTED IN BOTH DIRECTIONS FROM ONE TABLE, because a
	# one-armed version of this is how the label started lying in the first place. `Ally` and
	# `Nearest Ally` encode the SAME search; the ONLY thing that distinguishes them anywhere in
	# the system is which side of Pass 2's retry guard their GPU type falls on. So an arm that
	# only checked the pool rows would pass identically before and after the split, and an arm
	# that only checked the strict rows would pass on a build that made EVERY ally row strict.
	#
	# `To = Ally` + `Subject = Their` + `HP<50%` is the sentence the fold could not say
	# (ADR-0283); `To = Nearest Ally` + the same is the one that could not exist (ADR-0285).
	for case in [
		["Ally", true], ["Foe", true],
		["Nearest Ally", false], ["Nearest Foe", false],
		["Weakest Ally", false], ["Weakest Foe", false],
	]:
		var aim_name: String = case[0]
		var want_retryable: bool = case[1]
		var aim = null
		for t in GambitOptions.targets():
			if String(t["name"]) == aim_name:
				aim = t["make"].call()
		_expect(aim != null, "the `To` catalogue must carry `%s`" % aim_name)
		if aim == null:
			continue
		var g := Gambit.create(theirs["make"].call(aim),
			[GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ABILITY, 1, aim)      # 1 = Cure
		var cfg = _enc(g)
		_expect(cfg != null, "`%s` + `Their` + HP<50%% must encode at all" % aim_name)
		if cfg == null:
			continue
		if want_retryable:
			_expect(retryable.has(int(cfg["cond_target_type"])),
				"`To = %s` + `Subject = Their` must encode a RETRYABLE cond_target_type so the"
					% aim_name
				+ " kernel's Pass 2 walks rank 1, 2, 3… — got %d, which Pass 2 answers"
					% int(cfg["cond_target_type"])
				+ " VERDICT_NOT_RETRYABLE for, and the row then only ever tests the closest one")
		else:
			_expect(not retryable.has(int(cfg["cond_target_type"])),
				"`To = %s` names ONE unit, so its cond_target_type must NOT be in the kernel's"
					% aim_name
				+ " retryable set — got %d, which Pass 2 walks past rank 0 for, and the row"
					% int(cfg["cond_target_type"])
				+ " then acts on somebody the player did not name (this is ADR-0285's whole"
				+ " defect: `Nearest Ally` used to encode `TARGET_NEAREST_ALLY`, which retries)")
		# And the two fields AGREE, which is what makes the retried rank the unit it acts on:
		# Pass 2 passes its own `candidate` through as the final target.
		_expect(int(cfg["cond_target_type"]) == int(cfg["action_target_type"]),
			"and `cond_target_type` must EQUAL `action_target_type` — `Their` is a copy of the"
			+ " aim, so a row that tested one pool and acted on another would not be the"
			+ " sentence the player read (got %d vs %d)"
				% [int(cfg["cond_target_type"]), int(cfg["action_target_type"])])

	# POSITIVE CONTROL ON THE STRICT PAIR: the two new types must actually be REACHED above, or
	# the `not retryable.has(...)` arm is satisfied by any encoder bug that maps them to some
	# third thing. Named explicitly against GPUConstants, which is generated from the shader.
	var strict_seen := {}
	for aim_name in ["Nearest Ally", "Nearest Foe"]:
		for t in GambitOptions.targets():
			if String(t["name"]) == aim_name:
				var cfg2 = _enc(Gambit.create(TargetSelector.self_(), [],
					Gambit.ActionKind.ABILITY, 1, t["make"].call()))
				if cfg2 != null:
					strict_seen[int(cfg2["action_target_type"])] = aim_name
	_expect(strict_seen.has(GPUConstants.TARGET_NEAREST_ALLY_ONLY),
		"`Nearest Ally` must encode TARGET_NEAREST_ALLY_ONLY (%d) and not merely something"
			% GPUConstants.TARGET_NEAREST_ALLY_ONLY
		+ " absent from the retryable list — saw %s" % str(strict_seen))
	_expect(strict_seen.has(GPUConstants.TARGET_NEAREST_ENEMY_ONLY),
		"`Nearest Foe` must encode TARGET_NEAREST_ENEMY_ONLY (%d) — saw %s"
			% [GPUConstants.TARGET_NEAREST_ENEMY_ONLY, str(strict_seen)])

	# 🔴 THE CIRCULAR PAIR IS UNREACHABLE FROM THE SCREEN, and it is the cell the fourth column
	# CREATED rather than one it inherited. `Their` is a copy of the aim, so a `Them` aim would
	# make the subject `TRIGGERING` too — and `select_target` answers
	# `case TARGET_THEM: return -1;`, so Pass 1 writes VERDICT_NO_CANDIDATE and skips the slot on
	# every tick forever. It ENCODES CLEANLY, which is why the round-trip above cannot see it:
	# rule E1 is a question about the mapping, and TRIGGERING maps.
	#
	# Two cuts, asserted separately, because either one alone leaves a route open.
	var them = null
	for t in GambitOptions.targets():
		if String(t["name"]) == "Them":
			them = t["make"].call()
	_expect(them != null, "the `To` catalogue must still NAME `Them` — the offer list withholds"
		+ " it, but a save that holds it has to read back as itself and not as the `Self`"
		+ " fallback")
	if them != null:
		# CUT 1 — `mirror_of` refuses to copy it, so no path can build the pair at all.
		var mirrored = GambitOptions.mirror_of(them)
		_expect(mirrored.pool_type == TargetSelector.PoolType.SELF,
			"`mirror_of(Them)` must fall back to the actor, not copy the cycle — got pool %d"
			% int(mirrored.pool_type))
		# CUT 2 — and if one ever did, the gate grades it and `targets_for` withholds the row.
		_expect(GambitOptions.aim_verdict(Gambit.ActionKind.ATTACK, -1, them, them)
				== GambitOptions.AIM_NEVER_RESOLVES,
			"and `Them` aimed at a `Them` subject must grade NEVER_RESOLVES, so `targets_for`"
			+ " withholds the row — got '%s'"
			% GambitOptions.aim_verdict(Gambit.ActionKind.ATTACK, -1, them, them))
		var offered := GambitOptions.targets_for(Gambit.ActionKind.ATTACK, -1, them)
		var names: Array = []
		for e in offered:
			names.append(String(e["name"]))
		_expect(not names.has("Them"),
			"which the offer list must actually honour — `Them` is still on it: %s" % str(names))
		# The mirror-image grade survives: `Them` under the ACTOR is merely redundant, and that
		# is the reading #1125 opens with. Asserted here so the two are not collapsed.
		_expect(GambitOptions.aim_verdict(Gambit.ActionKind.ATTACK, -1, them,
				TargetSelector.self_()) == GambitOptions.AIM_UNNAMED,
			"while `Them` under `My` stays UNNAMED — it resolves to the actor and only says so"
			+ " badly, which is a different failure from never resolving")

	# THE CONTROL, and it is the arm that says the assertion above is about the SUBJECT and not
	# about the encoder being permissive: the fold's own subject — MOST_CRITICAL friendlies, what
	# every `Ally HP<X%` row wrote — still encodes cleanly and is still NOT retryable. So the
	# defect was never a skip; it was a legal encoding of the wrong pool.
	var folded := Gambit.create(
		TargetSelector.friendlies().with_resolution(TargetSelector.ResolutionStrategy.MOST_CRITICAL),
		[GambitCondition.target_hp_below(50.0)],
		Gambit.ActionKind.ABILITY, 1,
		TargetSelector.friendlies().with_resolution(TargetSelector.ResolutionStrategy.NEAREST_FIRST))
	var folded_cfg = _enc(folded)
	_expect(folded_cfg != null,
		"the pre-ADR-0283 folded subject still ENCODES — it was never an E1 skip")
	if folded_cfg != null:
		_expect(not retryable.has(int(folded_cfg["cond_target_type"])),
			"and it is still NOT retryable (%d = TARGET_LOWEST_HP_ALLY), which is what made"
				% int(folded_cfg["cond_target_type"])
			+ " `nearest ally whose HP is below half` unsayable from the folded screen")


## ADR-0276 — THE (VERB x AIM) STATE SPACE, ENUMERATED AND GRADED.
##
## The player asked for "a rule/audit to make sure sensible defaults apply", and the two cells
## they hit — `Move / Self` and `ThrowStone / Self` — are instances, not the set. So this walks
## the whole space rather than pinning the two.
##
## === WHY THIS IS NOT `_test_every_offered_choice_round_trips` AGAIN ==========================
##
## That guard asks "does the cell ENCODE?", which is rule E1's question. Both reported cells
## encode. They pass every layer that has an opinion — encoder, packer, kernel entry — and then
## the unit does nothing (`Move / Self`: `execute_move_to_unit_gambit` reads its own tile,
## `manhattan_distance(my, my) <= 1`, REASON_ARRIVED, idle) or does something the ROM record
## forbids (`ThrowStone / Self`: `dont_hit_caster`). A round-trip cannot see either. This asks
## the question AFTER the encode: does the cell DO anything, and is the ability allowed to.
##
## === THE POSITIVE CONTROL, AND WHY IT IS AN ASSERTION AND NOT A COMMENT =====================
##
## "0 nonsense cells" printed by an audit that examined nothing looks exactly like a clean bill
## of health. So the subject is printed (how many abilities, how many cells) and the census is
## asserted NON-VACUOUS from both ends: the ability set must be non-empty, and the grader must
## return a non-zero count of BOTH broken classes. A classifier that went blind — an
## `AbilityView` accessor renamed, a `dont_hit_*` key dropped from the extractor — would grade
## every cell SENSIBLE, pass every "nothing is broken" assertion, and be caught only here.
func _audit_every_aim_cell() -> void:
	# The ability axis: every id any skillset row can open onto. The union over all skillsets
	# rather than one character's usable set — `_ability_choices` filters per unit, so any id in
	# the union is reachable by SOME unit, and a per-character subject would make this audit's
	# coverage depend on which character the test happened to build.
	var ability_ids: Array = []
	var seen: Dictionary = {}
	for sid in AbilityDatabase.SKILL_SETS.keys():
		for id in AbilityDatabase.get_skill_set_actions(int(sid)):
			var aid := int(id)
			if seen.has(aid):
				continue
			seen[aid] = true
			if AbilityDatabase.get_ability_view(aid).is_empty():
				continue
			ability_ids.append(aid)
	_expect(not ability_ids.is_empty(),
		"the audit's ability axis is EMPTY — every cell assertion below would pass vacuously")

	# The subject axis. `Them` has no class of its own; it forwards to whatever the `If` column
	# picked out, so the same aim is a different cell under a different subject. Deduped by the
	# CLASS the subject resolves to, because that is all `aim_class` reads and the ten condition
	# rows collapse onto three.
	var subjects: Array = []
	var subject_names: Array = []
	var seen_class: Dictionary = {}
	# Built from the SUBJECT catalogue crossed with the AIM catalogue, because since ADR-0283
	# `Their` has no pool of its own — it is a copy of the aim, so its class is the aim's. `My`
	# contributes the caster and the four team aims contribute ally and foe.
	for subj_entry in GambitOptions.subjects():
		for aim_entry in GambitOptions.targets():
			var subj = subj_entry["make"].call(aim_entry["make"].call())
			var cls := GambitOptions.aim_class(subj)
			if seen_class.has(cls):
				continue
			seen_class[cls] = true
			subjects.append(subj)
			subject_names.append("%s of %s" % [subj_entry["name"], aim_entry["name"]])
	# AND ONE SUBJECT THE SCREEN CANNOT PRODUCE, graded because a SAVE can hold it. A raw
	# `triggering()` subject is what a pre-ADR-0283 `Them` pair or #895's operators can leave
	# behind, and it is the only input that reaches `AIM_NEVER_RESOLVES` — `mirror_of` refuses to
	# build it, so the two loops above can never contribute it and the census would report that
	# grade as zero from an instrument that was not looking.
	subjects.append(TargetSelector.triggering())
	subject_names.append("a raw Them subject (not screen-reachable)")
	_expect(subjects.size() >= 3,
		"the Subject x To product collapsed to %d subject class(es) — `Them` would be one cell,"
			% subjects.size()
		+ " and the audit would stop distinguishing the aims that differ only by subject")

	# Verb axis: the three control verbs carried as {kind, ability_id}, then every ability.
	var cells: Array = []
	for verb_entry in GambitOptions.action_verbs():
		var picked: Dictionary = verb_entry["make"].call()
		cells.append([String(verb_entry["name"]), int(picked["kind"]), int(picked["ability_id"])])
	for aid in ability_ids:
		cells.append([AbilityDatabase.get_ability_view(aid).name,
			int(Gambit.ActionKind.ABILITY), aid])

	var census: Dictionary = {}
	var graded := 0
	for cell in cells:
		var verb_name: String = cell[0]
		var kind: int = cell[1]
		var ability_id: int = cell[2]
		for si in range(subjects.size()):
			var subject = subjects[si]
			var allowed: Array = GambitOptions.targets_for(kind, ability_id, subject)
			var allowed_names: Dictionary = {}
			for a in allowed:
				allowed_names[String(a["name"])] = true

			for to_entry in GambitOptions.targets():
				var aim = to_entry["make"].call()
				var verdict := GambitOptions.aim_verdict(kind, ability_id, aim, subject)
				census[verdict] = int(census.get(verdict, 0)) + 1
				graded += 1
				var label := "%s / %s (If subject '%s')" % [
					verb_name, String(to_entry["name"]), subject_names[si]]

				# THE GATE IS THE VERDICT. A row the screen offers must be one nothing can
				# fault, and a row it withholds must be one something can — an offer list that
				# drifted from the grader would let either half rot silently.
				var offered: bool = allowed_names.has(String(to_entry["name"]))
				_expect(offered == (verdict == GambitOptions.AIM_SENSIBLE),
					"%s grades '%s' but the `To` list %s it — the offer list and the grader"
						% [label, verdict, "OFFERS" if offered else "WITHHOLDS"]
					+ " must be one decision (ADR-0276)")

			# A gate that empties the list would leave the player a verb they cannot aim. No ROM
			# record carries all three `dont_hit_*` flags, so this holds — as a fact about the
			# data, asserted rather than assumed.
			_expect(not allowed.is_empty(),
				"%s / <every aim> is gated OUT — the verb would be unaimable" % verb_name)

			# THE SEED IS A CELL TOO, and it is the cell the player gets without asking. Both
			# reported bugs arrived this way: nobody chose `Self`, the constructor did.
			var seeded = GambitOptions.seed_aim_for(kind, ability_id, subject)
			_expect(seeded != null, "%s seeds NOTHING onto an empty slot" % verb_name)
			if seeded != null:
				_expect(GambitOptions.aim_verdict(kind, ability_id, seeded, subject)
						== GambitOptions.AIM_SENSIBLE,
					"%s seeds an aim graded '%s' — the screen would author the defect"
						% [verb_name, GambitOptions.aim_verdict(kind, ability_id, seeded, subject)])

	# === The subject, printed. ===============================================================
	print("[audit] (verb x aim) cells graded: %d — %d verbs+abilities x %d If-subjects x %d aims"
		% [graded, cells.size(), subjects.size(), GambitOptions.targets().size()])
	# EVERY grade, in a FIXED order, and then whatever the census saw that the list does not
	# name. A hardcoded list silently drops a grade the code grows — `AIM_NEVER_RESOLVES` was
	# counted and unprinted for exactly one run, and the only symptom was that the five rows no
	# longer summed to the total. The tail loop is what makes the census report its own subject.
	var known := [GambitOptions.AIM_SENSIBLE, GambitOptions.AIM_NO_OP,
		GambitOptions.AIM_FORBIDDEN, GambitOptions.AIM_IGNORED,
		GambitOptions.AIM_UNNAMED, GambitOptions.AIM_NEVER_RESOLVES,
		GambitOptions.AIM_UNTARGETABLE]
	var shown := 0
	for verdict in known:
		print("[audit]   %-15s %d" % [verdict, int(census.get(verdict, 0))])
		shown += int(census.get(verdict, 0))
	for verdict in census.keys():
		if known.has(verdict):
			continue
		print("[audit]   %-15s %d  <- GRADE NOT IN THE PRINT LIST" % [verdict, int(census[verdict])])
		shown += int(census[verdict])
	_expect(shown == graded,
		"the census rows must sum to the %d cells graded, got %d — a grade counted and not"
			% [graded, shown]
		+ " printed is a register nobody reads")

	# === The positive control. ===============================================================
	_expect(int(census.get(GambitOptions.AIM_FORBIDDEN, 0)) > 0,
		"the audit graded ZERO cells FORBIDDEN across %d — the ROM's `dont_hit_*` triple is on"
			% graded
		+ " 186 of 368 records, so a zero here means the classifier is READING NOTHING")
	_expect(int(census.get(GambitOptions.AIM_NO_OP, 0)) > 0,
		"the audit graded ZERO cells NO_OP — `Move / Self` is one, so a zero means the verb"
		+ " axis or the MOVE rule went blind")
	_expect(int(census.get(GambitOptions.AIM_UNTARGETABLE, 0)) > 0,
		"the audit graded ZERO cells UNTARGETABLE across %d — `dont_target_self` is on 156 of" % graded
		+ " 368 records and four of those are NOT covered by `dont_hit_caster`, so a zero means"
		+ " ADR-0291's aim-policy rule is not being consulted at all")

	# === The two cells the player reported, by name. =========================================
	# Named rather than left to the census, because a census counts and does not identify: these
	# two are the report, and a refactor that graded them SENSIBLE while keeping the totals
	# plausible is exactly what a count cannot catch.
	var self_aim = TargetSelector.self_()
	_expect(GambitOptions.aim_verdict(Gambit.ActionKind.MOVE, -1, self_aim) == GambitOptions.AIM_NO_OP,
		"`Move / Self` must grade NO_OP — it is the reported cell")
	var throw_stone := AbilityDatabase.get_view_by_name("ThrowStone")
	_expect(not throw_stone.is_empty() and throw_stone.dont_hit_caster,
		"ThrowStone must carry `dont_hit_caster` — the audit's other reported cell rests on it")
	if not throw_stone.is_empty():
		_expect(GambitOptions.aim_verdict(Gambit.ActionKind.ABILITY, throw_stone.ability_id,
				self_aim) == GambitOptions.AIM_FORBIDDEN,
			"`ThrowStone / Self` must grade FORBIDDEN — it is the reported cell")
	_expect(GambitOptions.aim_verdict(Gambit.ActionKind.WAIT, -1,
			GambitOptions.foe_pool()) == GambitOptions.AIM_IGNORED,
		"`Wait / Nearest Foe` must grade IGNORED — the kernel never reads the aim for WAIT")

	# === ADR-0291: the AIM axis, and it is asserted in BOTH directions on purpose. ===========
	#
	# 🔴 A ONE-SIDED ARM HERE PASSES ON THE DEFECT. "`Wish / Self` is not SENSIBLE" is satisfied
	# by a gate that refuses EVERY `Self` cell, which is the mistake this rule is one press away
	# from being. So the four arms below are a matrix, not a list: the new rule must FIRE on the
	# gap set, must NOT fire where the record permits self-targeting, must NOT swallow the cells
	# ADR-0049 already answers, and must NOT leak off the caster class onto the other pools.
	#
	# ⚠️ `Heal` (149) is here because it is the example the player OPENED with and then withdrew
	# themselves — its record permits self-targeting and the gate must keep saying so. An arm
	# that lost this row would re-introduce the withdrawn claim silently.
	var self_targeting_gap := {107: "Revive", 116: "Invitation", 152: "Wish", 200: "BloodSuck"}
	for aid in self_targeting_gap:
		var view = AbilityDatabase.get_ability_view(aid)
		_expect(not view.is_empty(), "ability %d (%s) must be in the catalogue" % [aid, self_targeting_gap[aid]])
		if view.is_empty():
			continue
		# The record half FIRST: a grade assertion alone cannot tell "the rule fired" from
		# "some OTHER rule fired". `dont_hit_caster` must be false or this proves nothing.
		_expect(view.dont_target_self and not view.dont_hit_caster,
			"%s (%d) must carry `dont_target_self` and NOT `dont_hit_caster` — it is the gap"
				% [self_targeting_gap[aid], aid]
			+ " set's defining shape, and without it the grade below could come from ADR-0049")
		_expect(GambitOptions.aim_verdict(Gambit.ActionKind.ABILITY, aid, self_aim)
				== GambitOptions.AIM_UNTARGETABLE,
			"`%s / Self` must grade UNTARGETABLE — the ROM zeroes the caster's own tile out of"
				% self_targeting_gap[aid]
			+ " the selectable table at 0x8017A450, and the screen offered the cell anyway")
		# …and the rule is about the CASTER class, not about the ability. Without this the
		# gate could be emptying the whole `To` list for these four and still read green.
		_expect(GambitOptions.aim_verdict(Gambit.ActionKind.ABILITY, aid,
				GambitOptions.foe_pool()) == GambitOptions.AIM_SENSIBLE,
			"`%s / Nearest Foe` must stay SENSIBLE — `dont_target_self` bars ONE tile, not the"
				% self_targeting_gap[aid] + " ability")

	# THE OTHER DIRECTION, and the one that fails if the rule became "no Self, ever".
	var heal := AbilityDatabase.get_view_by_name("Heal")
	_expect(not heal.is_empty() and not heal.dont_target_self and not heal.dont_hit_caster,
		"Heal (149) must carry NEITHER self-targeting flag — the withdrawn example rests on it")
	if not heal.is_empty():
		_expect(GambitOptions.aim_verdict(Gambit.ActionKind.ABILITY, heal.ability_id, self_aim)
				== GambitOptions.AIM_SENSIBLE,
			"`Heal / Self` must stay SENSIBLE — the record permits self-targeting, and the"
			+ " player withdrew this example themselves. A gate that reds it is over-firing")
	# THE THIRD ROW: an ability ADR-0049 already answers must keep ADR-0049's grade. The new
	# rule is ordered AFTER the hit-policy line precisely so this does not move.
	if not throw_stone.is_empty():
		_expect(GambitOptions.aim_verdict(Gambit.ActionKind.ABILITY, throw_stone.ability_id,
				self_aim) == GambitOptions.AIM_FORBIDDEN,
			"`ThrowStone / Self` must still grade FORBIDDEN, not UNTARGETABLE — the two axes are"
			+ " separate rules and the census can only report the gap if they stay separate")

	# === ADR-0296: the `To` list is ORDERED by the ability's family. ==========================
	#
	# 🔴 THE CONTROL IS THE POINT. "`Cure` puts an ally row first" is satisfied by a sorter that
	# puts an ally row first for EVERYTHING, so each arm below is paired with its opposite, and
	# an UNCLASSIFIED ability carries the third row: it must come back in `targets()` order,
	# untouched. Without that row a sorter that rearranged the whole catalogue reads identical.
	var _names := func(kind: int, aid: int) -> Array:
		var out: Array = []
		for e in GambitOptions.targets_for(kind, aid, null):
			out.append(e["name"])
		return out
	var _first_index := func(names: Array, wanted: Array) -> int:
		for i in names.size():
			if wanted.has(names[i]):
				return i
		return 9999
	var ally_rows := ["Ally", "Nearest Ally", "Weakest Ally"]
	var foe_rows := ["Foe", "Nearest Foe", "Weakest Foe"]

	var cure := AbilityDatabase.get_view_by_name("Cure")
	_expect(not cure.is_empty() and not cure.dont_target_self,
		"Cure must exist and be self-targetable — both arms below rest on it")
	if not cure.is_empty():
		var n: Array = _names.call(Gambit.ActionKind.ABILITY, cure.ability_id)
		_expect(n.size() > 0 and n[0] == "Self",
			"`Cure` is healing AND self-targetable, so `Self` must be the FIRST row — the"
			+ " player's rule verbatim. Got: %s" % str(n))
		_expect(_first_index.call(n, ally_rows) < _first_index.call(n, foe_rows),
			"`Cure` must list its ALLY rows above its FOE rows. Got: %s" % str(n))

	var fire := AbilityDatabase.get_view_by_name("Fire")
	_expect(not fire.is_empty(), "Fire must exist — it is the opposite arm")
	if not fire.is_empty():
		var n: Array = _names.call(Gambit.ActionKind.ABILITY, fire.ability_id)
		_expect(_first_index.call(n, foe_rows) < _first_index.call(n, ally_rows),
			"`Fire` is damage, so its FOE rows must come first — the OPPOSITE of Cure, which is"
			+ " what makes this a direction test and not a coincidence. Got: %s" % str(n))
		_expect(n.size() > 0 and n[0] != "Self",
			"`Fire / Self` must NOT head the list — `Self` sinks below `Ally` for a negative"
			+ " ability. Got: %s" % str(n))

	# 🔴 THE COMPOSITION ARM — ADR-0291 and ADR-0296 meeting on one ability.
	# `Wish` is `healing`, so it is POSITIVE and the rule would float `Self` to the top. It does
	# not, because `Self` is not in the list at all: the ROM forbids the cursor landing on the
	# caster and the gate already withheld the row. If this ever reports `Self` first, EITHER
	# the gate stopped withholding or the sorter started resurrecting.
	var wish := AbilityDatabase.get_ability_view(152)
	if not wish.is_empty():
		var n: Array = _names.call(Gambit.ActionKind.ABILITY, 152)
		_expect(not n.has("Self"),
			"`Wish` is positive AND `dont_target_self`, so `Self` must be ABSENT — ordering runs"
			+ " on what the gate left and can never resurrect a withheld row. Got: %s" % str(n))
		_expect(_first_index.call(n, ally_rows) < _first_index.call(n, foe_rows),
			"…and `Wish` must still lead with its ALLY rows. Got: %s" % str(n))

	# 🔴 ADR-0296 dec. 6: THE HEAD OF THE LIST IS THE SEEDED ROW, FOR EVERY CELL.
	#
	# dec. 1 claims the order and the default are ONE decision. That was a claim about the code
	# and not a guard on it, and `Attack` was already violating it: `seed_aim_for` hardcoded the
	# foe pool while the order asked `family_aim_name`, which answers `&""` for every non-ABILITY
	# verb — so `Attack` seeded `Foe` and opened on `Self`, on the most-used verb on the screen.
	#
	# Asserted as an INVARIANT over the whole space rather than as an `Attack` arm, because the
	# per-case version is what already existed and it did not catch this: the old assertion
	# pinned the SEED, wrote "its gated list head is `Self`" in its own message, and passed.
	# A test that documents the defect in its comment is not guarding against it.
	var head_mismatches: Array = []
	var self_promoted := 0
	for cell in cells:
		var cell_name: String = cell[0]
		var kind: int = cell[1]
		var aid: int = cell[2]
		var rows := GambitOptions.targets_for(kind, aid, null)
		if rows.is_empty():
			continue
		var seeded = GambitOptions.seed_aim_for(kind, aid, null)
		if seeded == null:
			continue
		if str(rows[0]["make"].call()) == str(seeded):
			continue
		# The ONE licensed disagreement: dec. 3 promotes `Self` above the family's row for a
		# positive, self-targetable ability. The DEFAULT stays the family's (ADR-0278 dec. 2,
		# "healing defaults to nearest friendly" — the player's own words), so head != seed is
		# intended there and nowhere else. Anything else is the `Attack` shape.
		if String(rows[0]["name"]) == "Self" \
				and GambitOptions.aim_polarity(kind, aid) == &"Ally":
			self_promoted += 1
			continue
		head_mismatches.append("%s head=%s seed=%s"
			% [cell_name, rows[0]["name"], str(seeded)])
	_expect(head_mismatches.is_empty(),
		"the FIRST row of the `To` list must BE the seeded aim, except where dec. 3 promotes"
		+ " `Self` for a positive self-targetable ability — %d cell(s) disagree for another"
			% head_mismatches.size()
		+ " reason, which is the `Attack` shape: %s" % str(head_mismatches.slice(0, 5)))
	# The carve-out must be NARROW: it is licensed only for `Ally` polarity, so a foe-side
	# ability heading on `Self` is still a failure. Asserted by construction above, and the
	# count is printed so a carve-out that quietly swallowed everything is visible.
	print("[audit] head==seed holds; `Self`-promoted cells (dec. 3 carve-out): %d of %d"
		% [self_promoted, cells.size()])
	_expect(self_promoted > 0 and self_promoted < cells.size(),
		"the `Self`-promotion carve-out covers %d of %d cells — 0 means dec. 3 never fires and"
			% [self_promoted, cells.size()]
		+ " the invariant is vacuous, ALL means it swallowed the whole walk and guards nothing")
	# …and the positive control, because an invariant over an empty walk is vacuous.
	_expect(cells.size() > 0, "the head-equals-seed invariant walked ZERO cells")
	var attack_rows := GambitOptions.targets_for(Gambit.ActionKind.ATTACK, -1, null)
	_expect(attack_rows.size() > 0 and String(attack_rows[0]["name"]) == "Foe",
		"`Attack` must OPEN on `Foe` — it is foe-side without having a family, and it is the"
		+ " cell that proved the seed and the order were two decisions")

	# THE CONTROL: no family => no claim => `targets()` order, byte for byte.
	var unclassified := -1
	for aid in AbilityDatabase.ABILITIES.keys():
		if GambitOptions.family_aim_name(Gambit.ActionKind.ABILITY, int(aid)) == &"" \
				and not AbilityDatabase.get_ability_view(int(aid)).is_empty():
			unclassified = int(aid)
			break
	_expect(unclassified >= 0,
		"no UNKNOWN-family ability found — the control arm needs one, and the classifier"
		+ " reports 42 such records, so a zero here means this loop is not looking")
	if unclassified >= 0:
		var got: Array = _names.call(Gambit.ActionKind.ABILITY, unclassified)
		var want: Array = []
		for e in GambitOptions.targets():
			if GambitOptions.aim_verdict(Gambit.ActionKind.ABILITY, unclassified,
					e["make"].call(), null) == GambitOptions.AIM_SENSIBLE:
				want.append(e["name"])
		_expect(got == want,
			"an UNKNOWN-family ability must keep `targets()` order untouched — ordering it would"
			+ " invent a claim the classifier declined to make. want %s got %s" % [str(want), str(got)])

	# 🔴 `Them` IS UNNAMED UNDER EVERY SUBJECT, AND THIS ARM USED TO ASSERT THE OPPOSITE.
	#
	# It read: *"`Them` is a cell that changes verdict with its SUBJECT, and both halves are
	# asserted"*, and it pinned `Them` + a FOE subject as SENSIBLE on the reasoning that
	# *"`Them` earns its place the moment the condition gives it something to forward to"*.
	# That is true of the STRUCT and false of the SCREEN, and the difference is one press.
	#
	# Grading `Them` against the subject as it stands asks at the wrong moment, because LANDING
	# the aim MOVES the subject. `GambitSurface`'s `To` apply re-mirrors whenever the subject
	# was a copy of the aim, and `GambitOptions.mirror_of` refuses to copy a `TRIGGERING` aim —
	# it falls back to the actor. The other branch is no different: with a two-row subject
	# catalogue, "not a copy of the aim" can only mean `My`, which is the actor already. So
	# both paths end with the subject on the caster, and the FOE-subject cell the old assertion
	# called sensible could not survive being chosen — pick it and you have `Self` under a word
	# that says otherwise.
	#
	# Asserted across BOTH subjects still, for the reason the old arm gave and got backwards: a
	# one-subject assertion cannot tell "graded independently of the subject" from "graded on a
	# subject that happens to agree".
	var them := TargetSelector.triggering()
	_expect(GambitOptions.aim_verdict(Gambit.ActionKind.ATTACK, -1, them, self_aim)
			== GambitOptions.AIM_UNNAMED,
		"`Attack / Them` under a SELF subject must grade UNNAMED — it IS the Self row, under"
		+ " the one name that does not say so (#1125's opening line)")
	_expect(GambitOptions.aim_verdict(Gambit.ActionKind.ATTACK, -1, them,
			GambitOptions.foe_pool()) == GambitOptions.AIM_UNNAMED,
		"…and the SAME cell under a FOE subject must ALSO grade UNNAMED — choosing it re-mirrors"
		+ " the subject onto a TRIGGERING aim, `mirror_of` refuses the cycle and falls back to"
		+ " the actor, so the FOE subject the grade was computed against no longer exists by the"
		+ " time the press finishes")

	# AND THE ROW IS THEREFORE WITHHELD — the grade and the offer list are ONE decision
	# (ADR-0276), so this is the assertion that says the player cannot author it at all.
	for subj in [self_aim, GambitOptions.foe_pool(), null]:
		var offered := false
		for e in GambitOptions.targets_for(Gambit.ActionKind.ATTACK, -1, subj):
			if String(e["name"]) == "Them":
				offered = true
		_expect(not offered,
			"the `To` list must NOT offer `Them` under any subject — it is `Self` wearing a"
			+ " name that hides it, and a row whose meaning collapses on being chosen is one"
			+ " the screen should never have shown")
	# STILL NAMEABLE, though, and that is a different claim: `targets()` is also the READBACK,
	# and `GambitSurface._target_text` prints the literal "Self" for any selector the catalogue
	# cannot name. The safety net, the imperative and #895's operators all build TRIGGERING
	# aims, so withholding the row from the OFFER list must not make those rows lie.
	var named := false
	for e in GambitOptions.targets():
		if String(e["name"]) == "Them":
			named = true
	_expect(named,
		"…while `targets()` must STILL carry `Them` — withholding a row says what can be"
		+ " AUTHORED, never that a row already holding it may read back as something else")


# =============================================================================
# ADR-0278 — THE FAMILY, AND WHERE THE SEED IT PICKS LANDS (#1125 (b))
# =============================================================================

## The ability ids any skillset row can open onto — the same axis
## `_audit_every_aim_cell` builds, for the same reason: a per-character subject would make the
## audit's coverage depend on which character the test happened to build.
func _reachable_ability_ids() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for sid in AbilityDatabase.SKILL_SETS.keys():
		for id in AbilityDatabase.get_skill_set_actions(int(sid)):
			var aid := int(id)
			if seen.has(aid):
				continue
			seen[aid] = true
			var v := AbilityDatabase.get_ability_view(aid)
			if v.is_empty() or v.name.is_empty():
				continue
			out.append(aid)
	return out


func _family_named(ability_name: String) -> StringName:
	var v := AbilityDatabase.get_view_by_name(ability_name)
	if v.is_empty():
		_expect(false, "`%s` is not in the catalogue — an assertion below has no subject"
			% ability_name)
		return AbilityFamily.UNKNOWN
	return AbilityFamily.of_view(v)


func _expect_ally_side(ability_name: String, why: String) -> void:
	var fam := _family_named(ability_name)
	_expect(fam != AbilityFamily.UNKNOWN and AbilityFamily.is_ally_side(fam),
		"`%s` must classify ALLY-SIDE and grades '%s' — %s" % [ability_name, fam, why])


func _expect_foe_side(ability_name: String, why: String) -> void:
	var fam := _family_named(ability_name)
	_expect(fam != AbilityFamily.UNKNOWN and not AbilityFamily.is_ally_side(fam),
		"`%s` must classify FOE-SIDE and grades '%s' — %s" % [ability_name, fam, why])


func _audit_ability_family() -> void:
	var reachable := _reachable_ability_ids()
	_expect(not reachable.is_empty(),
		"the family audit's ability axis is EMPTY — every assertion below would pass vacuously")

	# === THE POLARITY TABLE, BOTH DIRECTIONS. ================================================
	# #424's rule: a list that may only shrink needs both arms or it rots into a permanent
	# exemption. A status with no row makes the XOR fall through to the formula silently, and a
	# row naming a status nothing inflicts is a ruling nobody can check.
	for s in AbilityFamily.GOOD_STATUSES:
		_expect(not AbilityFamily.BAD_STATUSES.has(s),
			"status '%s' is in BOTH polarity lists — the XOR would read it by list order" % s)

	var catalogue_statuses: Dictionary = {}
	var mixed: Array = []
	for id in AbilityDatabase.ability_ids():
		var v := AbilityDatabase.get_ability_view(int(id))
		var good_seen := false
		var bad_seen := false
		for raw in v.inflict_statuses:
			var name_str := String(raw)
			catalogue_statuses[name_str] = true
			_expect(AbilityFamily.status_polarity(name_str) != 0,
				"status '%s' (on `%s`) has NO polarity row — the XOR falls through to the"
					% [name_str, v.name]
				+ " formula and nothing says it did")
			if AbilityFamily.status_polarity(name_str) > 0:
				good_seen = true
			elif AbilityFamily.status_polarity(name_str) < 0:
				bad_seen = true
		if good_seen and bad_seen:
			mixed.append(v.name)

	for s in AbilityFamily.GOOD_STATUSES + AbilityFamily.BAD_STATUSES:
		_expect(catalogue_statuses.has(s),
			"polarity row '%s' names a status NO record inflicts — a ruling nobody can" % s
			+ " falsify against the catalogue")

	# `AbilityFamily.of_view` reads the FIRST status as the set's polarity. That is only sound
	# because no set mixes, which is a fact about the data and is asserted rather than assumed:
	# a mixed set would make the family depend on array order, silently.
	_expect(mixed.is_empty(),
		"%d record(s) inflict BOTH good and bad statuses (%s) — the XOR reads statuses[0], so"
			% [mixed.size(), ", ".join(mixed)]
		+ " the family would be decided by array order (AbilityFamily.of_view)")

	# === COVERAGE, WITH NO SILENT DEFAULT. ===================================================
	var by_family: Dictionary = {}
	var unknown_reachable: Array = []
	for aid in reachable:
		var fam := AbilityFamily.of_id(aid)
		by_family[fam] = int(by_family.get(fam, 0)) + 1
		if fam == AbilityFamily.UNKNOWN:
			unknown_reachable.append(AbilityDatabase.get_ability_view(aid).name)

	var unknown_catalogue := 0
	for id in AbilityDatabase.ability_ids():
		var v := AbilityDatabase.get_ability_view(int(id))
		if v.has("formula") and AbilityFamily.of_view(v) == AbilityFamily.UNKNOWN:
			unknown_catalogue += 1

	# === THE SUBJECT, PRINTED. ===============================================================
	print("[audit] abilities classified: %d reachable of %d records carrying a formula"
		% [reachable.size(), _formula_carrying_count()])
	for fam in [AbilityFamily.DAMAGE, AbilityFamily.HEALING,
			AbilityFamily.BUFF, AbilityFamily.DEBUFF]:
		print("[audit]   %-10s %d" % [fam, int(by_family.get(fam, 0))])
	print("[audit]   %-10s %d reachable / %d over every record with a formula"
		% ["unknown", unknown_reachable.size(), unknown_catalogue])
	print("[audit]   polarity rows: %d good / %d bad over %d statuses in the catalogue"
		% [AbilityFamily.GOOD_STATUSES.size(), AbilityFamily.BAD_STATUSES.size(),
			catalogue_statuses.size()])

	# ONE reachable ability has no family, it is NAMED rather than counted, and the name is the
	# assertion: a bucket that only has to stay small is a bucket nobody reads. `Move-GetJp` is a
	# MOVEMENT support ability sitting in a skillset's `actions` list — it lands on nobody, so
	# there is no pool to prefer and ADR-0276 dec. 10's head-of-the-list is the right answer.
	const UNFAMILIED_BY_DESIGN: Array[String] = ["Move-GetJp"]
	var surprises: Array = []
	for n in unknown_reachable:
		if not UNFAMILIED_BY_DESIGN.has(n):
			surprises.append(n)
	_expect(surprises.is_empty(),
		"%d REACHABLE abilities classify into NO family (%s) — each one seeds the head of its"
			% [surprises.size(), ", ".join(surprises)]
		+ " gated list instead of a pool, which is ADR-0276 dec. 10 surviving where ADR-0278"
		+ " was supposed to replace it")
	# The other arm. An exemption list that may only shrink needs both (#424): a name here that
	# the classifier has since learned to rule is a permanent exemption nobody notices.
	for n in UNFAMILIED_BY_DESIGN:
		_expect(unknown_reachable.has(n),
			"`%s` is on the no-family exemption list and DOES classify now — drop the row" % n)

	# The residual is unreachable-only and it RATCHETS. Tolerating it silently is the defect
	# class this ticket exists to remove; the number is here so a record that stops being ruled
	# reds this line rather than joining a bucket nobody counts.
	const UNREACHABLE_UNRULED := 42
	_expect(unknown_catalogue <= UNREACHABLE_UNRULED,
		"%d records carry a formula AbilityFamily does not rule, up from %d — every one is"
			% [unknown_catalogue, UNREACHABLE_UNRULED]
		+ " supposed to be an UNREACHABLE monster formula or a `(Nothing)` placeholder, so"
		+ " growth means a rule was dropped or the extraction moved")

	# === THE POSITIVE CONTROL ON EACH FAMILY. ================================================
	# A classifier that booked all 249 as `damage` would satisfy "every seed matches its family"
	# perfectly, and a count of four families is the only thing that can see it.
	for fam in [AbilityFamily.DAMAGE, AbilityFamily.HEALING,
			AbilityFamily.BUFF, AbilityFamily.DEBUFF]:
		_expect(int(by_family.get(fam, 0)) > 0,
			"ZERO reachable abilities grade '%s' — a classifier collapsed onto the other three"
				% fam
			+ " passes every per-cell assertion in this file")

	# === THE ROM'S OWN ANSWER, CROSS-TABBED (issue #1227). ===================================
	# ADR-0278 dec. 9 argues this classifier is a `rule` because "nothing in the ROM stores a
	# family". That is still true — a family is 4-valued. But its ALLY/FOE PROJECTION *is*
	# stored, and BATTLE.BIN reads it as a two-bit field: `lbu 0x4(v1); andi 0x3` at
	# 0x8018b5f8-0x8018b604, with the other six bits of that byte DISCARDED at the same site.
	# So the rule is corroborated rather than unsourced, and this arm is what keeps it so: a
	# future family edit that disagrees with the ROM reds here instead of shipping.
	#
	# It is a GUARD, never the source. The ROM is SILENT on the set named below, so a family
	# derived from these flags alone would leave nine usable Faith/Brave/talk skills with no
	# pool at all. `AbilityFamily` stays the answer.
	var rom_ally := 0
	var rom_foe := 0
	var rom_silent: Array = []
	var rom_conflicts: Array = []
	for aid in reachable:
		var v := AbilityDatabase.get_ability_view(aid)
		var fam := AbilityFamily.of_id(aid)
		if fam == AbilityFamily.UNKNOWN:
			continue  # `Move-GetJp` — already NAMED by UNFAMILIED_BY_DESIGN above.
		if not v.ai_target_allies and not v.ai_target_enemies:
			rom_silent.append(v.name)
			continue
		var rom_ally_side: bool = v.ai_target_allies
		if rom_ally_side:
			rom_ally += 1
		else:
			rom_foe += 1
		if AbilityFamily.is_ally_side(fam) != rom_ally_side:
			rom_conflicts.append("%s (family '%s' says %s, ROM says %s)" % [
				v.name, fam,
				"ally" if AbilityFamily.is_ally_side(fam) else "foe",
				"ally" if rom_ally_side else "foe"])

	_expect(rom_conflicts.is_empty(),
		"%d reachable ability(ies) DISAGREE with the ROM's own polarity (%s) — the ROM answers"
			% [rom_conflicts.size(), ", ".join(rom_conflicts)]
		+ " *what the AI does* and this classifier answers *should it*, so a disagreement is a"
		+ " ruling somebody has to make and record, not an automatic defect (ADR-0291 dec. 5)")

	# BOUNDS, both ends. Zero comparable rows would make the assertion above vacuous; ALL of
	# them would mean the silent carve-out below had quietly swallowed the walk.
	var rom_comparable := rom_ally + rom_foe
	_expect(rom_comparable > 0 and rom_comparable < reachable.size(),
		"the ROM cross-tab compared %d of %d reachable abilities — 0 makes the agreement above"
			% [rom_comparable, reachable.size()]
		+ " vacuous, and all of them means the silent set stopped discriminating")
	# And both DIRECTIONS, so a ROM column collapsed onto one side cannot read as agreement.
	_expect(rom_ally > 0 and rom_foe > 0,
		"the ROM's polarity column is ONE-SIDED (%d ally / %d foe) — agreement with a constant"
			% [rom_ally, rom_foe]
		+ " is not agreement")

	# The silent set is NAMED rather than counted, for the reason UNFAMILIED_BY_DESIGN is: a
	# bucket that only has to stay small is a bucket nobody reads. Nine are `ai_usable`
	# Faith/Brave/talk skills the AI reaches some other way; `Golem`, `GilTaking` and
	# `Invitation` carry only the INERT `ai_only_*` bits (ADR-0291 dec. 5 — read by nothing,
	# and they contradict the proven pair on `Silf`, `Fairy` and `StealExp`).
	const ROM_SILENT_BY_DESIGN: Array[String] = [
		"Frog", "Preach", "Solution", "Negotiate", "PrayFaith", "DoubtFaith",
		"BlindRage", "Faith", "Innocent", "Golem", "GilTaking", "Invitation",
	]
	var rom_silent_surprises: Array = []
	for n in rom_silent:
		if not ROM_SILENT_BY_DESIGN.has(n):
			rom_silent_surprises.append(n)
	_expect(rom_silent_surprises.is_empty(),
		"%d reachable ability(ies) the ROM does not give a polarity are NOT on the named list"
			% rom_silent_surprises.size()
		+ " (%s) — either a skillset row changed or the extraction did"
			% ", ".join(rom_silent_surprises))
	# The other arm (#424): a name here the ROM has since answered is a dead exemption.
	for n in ROM_SILENT_BY_DESIGN:
		_expect(rom_silent.has(n),
			"`%s` is on the ROM-silent list and the ROM DOES give it a polarity now — drop the"
				% n
			+ " row, and check whether the extraction moved")

	print("[audit]   ROM polarity: %d ally / %d foe agree, %d conflict, %d silent of %d reachable"
		% [rom_ally, rom_foe, rom_conflicts.size(), rom_silent.size(), reachable.size()])

	_audit_family_witnesses()
	_audit_family_seeds(reachable)


func _formula_carrying_count() -> int:
	var n := 0
	for id in AbilityDatabase.ability_ids():
		if AbilityDatabase.get_ability_view(int(id)).has("formula"):
			n += 1
	return n


## The cells a census cannot identify, by name. Every one of these grades correctly under a rule
## that is wrong in a way the totals cannot show.
func _audit_family_witnesses() -> void:
	# --- THE FIVE THAT LOOK EXACTLY LIKE DAMAGE ------------------------------------------
	# All `target_reaction_type: "taking_damage"` with an EMPTY `inflict_statuses`. A rule that
	# read the reaction type books every one of them as damage and aims it at `Nearest Foe`.
	# Every one is a self- or ally-side restore; `Wish` spends the caster's own HP to heal.
	_expect_ally_side("Chakra", "f52 restores HP and MP to the caster and its neighbours")
	_expect_ally_side("Accumulate", "f54 raises the caster's own PA")
	_expect_ally_side("Yell", "f57 raises the target's Speed")
	_expect_ally_side("CheerUp", "f58 is a Squire support skill, not a strike")
	_expect_ally_side("Wish", "f60 spends the CASTER's HP to heal the target")
	_expect_ally_side("Scream", "f59 raises the caster's own stats")
	# …and the control: an ability that reads the same way and IS damage. Without it, an
	# `is_ally_side` that returned true unconditionally passes all six above.
	_expect_foe_side("ThrowStone", "f55 is the ability the player reported, and it is a strike")

	# --- BOTH DIRECTIONS OF THE XOR ------------------------------------------------------
	# Either alone is indistinguishable from a rule that ignores polarity entirely.
	_expect_ally_side("Esuna", "cancel + BAD statuses cleanses an ally")
	_expect_foe_side("DispelMagic", "cancel + GOOD statuses strips a FOE's buffs — the same"
		+ " `inflict_mode` as Esuna and the opposite pool")
	# …and the same pair one level down, on the formula that holds both sides at once.
	_expect_ally_side("Heal", "f56 + cancel + bad")
	_expect_foe_side("Seal", "f56 + inflict + bad — ADR-0276 names this pair as the reason"
		+ " `formula` alone cannot answer the question")

	# --- `inflict_mode` IS NOT TWO-VALUED, AND SPELLING IT `== \"all\"` INVERTS 17 RECORDS ---
	# `random` and `separate` inflict just as `all` does. Both directions witnessed, because a
	# rule testing `mode == "all"` is wrong on BOTH and a single case cannot say which half broke.
	_expect_foe_side("StasisSword", "`separate` + bad. THE ONE THAT REACHES THE PLAYER: its"
		+ " record carries no `dont_hit_allies`, so a family of `buff` would survive the gate"
		+ " and seed `Nearest Ally` — a Stop-sword aimed at a friend")
	_expect_ally_side("NamelessSong", "`random` + good — the other direction of the same"
		+ " mis-spelling")
	# Direction-tested: if the catalogue held no `random`/`separate` record the pair above would
	# be asserting a distinction the data does not draw, and would read as a clean pass.
	var modes: Dictionary = {}
	for id in AbilityDatabase.ability_ids():
		var v := AbilityDatabase.get_ability_view(int(id))
		if not v.inflict_statuses.is_empty() and v.inflict_mode != null:
			modes[String(v.inflict_mode)] = true
	_expect(modes.has("random") or modes.has("separate"),
		"the catalogue holds no `random`/`separate` inflict mode — the two assertions above"
		+ " distinguish nothing and `inflict_mode != \"cancel\"` is untested against"
		+ " `inflict_mode == \"all\"`")

	# --- THE TALK SKILL SPLIT ------------------------------------------------------------
	# One formula, no statuses, both directions, and the ROM records the magnitude without the
	# sign. These are the six rulings `ABILITY_FAMILY` exists for.
	_expect_ally_side("Praise", "f42 raises the target's Brave by 4")
	_expect_foe_side("Threaten", "f42 lowers it by 20 — same formula, same reaction type, same"
		+ " empty status list as Praise")


## Every seed the surface would author, checked against the family that picked it.
func _audit_family_seeds(reachable: Array) -> void:
	var fell_back: Array = []
	var mismatched := 0
	for aid in reachable:
		var fam := AbilityFamily.of_id(aid)
		# ADR-0285 dec. 4: the family seeds the POOL row, which is the behaviour ADR-0278
		# dec. 2's words described. `Nearest Ally` is now STRICT depth and seeding it would
		# have narrowed every healing and buff ability on the tick the rename landed.
		var want := "Ally" if AbilityFamily.is_ally_side(fam) else "Foe"
		for subject in [TargetSelector.self_(), GambitOptions.foe_pool()]:
			var seeded = GambitOptions.seed_aim_for(Gambit.ActionKind.ABILITY, aid, subject)
			_expect(seeded != null, "ability %d seeds NOTHING onto an empty slot" % aid)
			if seeded == null:
				continue
			# The seed is named out of the OFFER list, so the `To` column can print it — an aim
			# built from a second literal renders as the fallback (ADR-0276 dec. 12).
			var seeded_name := ""
			for entry in GambitOptions.targets_for(Gambit.ActionKind.ABILITY, aid, subject):
				var probe = entry["make"].call()
				if probe.pool_type == seeded.pool_type and probe.team_filter == seeded.team_filter \
						and probe.resolution == seeded.resolution:
					seeded_name = String(entry["name"])
					break
			_expect(not seeded_name.is_empty(),
				"ability %d seeds an aim the gated `To` list does not OFFER — the seed and the"
					% aid + " gate must be one decision")
			if fam == AbilityFamily.UNKNOWN:
				continue
			if seeded_name != want:
				fell_back.append("%s (%s wanted %s, got %s)"
					% [AbilityDatabase.get_ability_view(aid).name, fam, want, seeded_name])
				mismatched += 1

	# ZERO FALLBACKS, AND THE ZERO IS NOT A BLIND ONE. The gate is a HARD gate and the family
	# yields to it, so a fallback would be legal — this asserts that the ROM's hit policy and
	# these rulings never once disagree, which is the strongest control the classifier has. 59
	# of the reachable records carry `dont_hit_allies` or `dont_hit_enemies`, so the gate had 59
	# chances to contradict a ruling and took none.
	_expect(fell_back.is_empty(),
		"%d seed(s) fell back off their family's pool: %s — the family yields to the gate by"
			% [mismatched, ", ".join(fell_back.slice(0, 8))]
		+ " design, so this is not a crash, but every one is a ruling the ROM record disagrees"
		+ " with and should be re-read rather than tolerated (ADR-0278 dec. 4)")

	# --- THE THREE VERBS KEEP THEIR OWN RULES --------------------------------------------
	# ADR-0278 NARROWS ADR-0276 dec. 10, it does not delete it. `Move` and `Wait` have no family
	# — asking what a destination is FOR is the wrong axis — so both still take the head of the
	# gated list, and `Attack` still takes dec. 12's explicit foe pool (spelled `Nearest Foe`
	# until ADR-0285 split the column; the SELECTOR is unchanged, NEAREST_FIRST either way,
	# which is why this assertion reads the resolution and not the row's name).
	var attack_seed = GambitOptions.seed_aim_for(Gambit.ActionKind.ATTACK, -1, TargetSelector.self_())
	_expect(attack_seed != null and attack_seed.pool_type == TargetSelector.PoolType.TEAM_FILTER
			and attack_seed.team_filter == TargetSelector.TeamFilter.ENEMY
			and attack_seed.resolution == TargetSelector.ResolutionStrategy.NEAREST_FIRST,
		"`Attack` must still seed the FOE POOL explicitly (ADR-0268 dec. 12, kept by ADR-0278,"
		+ " renamed by ADR-0285, re-sourced by ADR-0296 dec. 6) — NEAREST_ONLY here would"
		+ " mean a basic attack stopped trying after the closest enemy failed the row")
	_expect(GambitOptions.family_aim_name(Gambit.ActionKind.MOVE, -1) == &"",
		"`Move` must have NO family — its aim is a DESTINATION, and a family that answered"
		+ " here would re-seed dec. 3's no-op through the preference instead of the head")
	_expect(GambitOptions.family_aim_name(Gambit.ActionKind.WAIT, -1) == &"",
		"`Wait` must have NO family — the kernel never reads its aim (ADR-0276 dec. 8)")
