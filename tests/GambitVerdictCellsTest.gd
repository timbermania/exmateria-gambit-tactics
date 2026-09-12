extends GPUCombatTestBase

# test-kind: gpu
# seeded-break: in `src/gpu/shaders/stage_compute.glsl`'s `execute_gambit_action`,
#   delete the `verdict = VERDICT_SILENCED;` line (leave its `return false`) — the
#   SILENCED cell then decodes FIRED and the aggregate goes red. Every cell below was
#   proved red the same way, by breaking the thing it names, before being trusted green.

## Gambit Verdict Cells — the ADR-0275 dec. 18 guard (#1127).
##
## The kernel stamps a per-slot VERDICT into the two reserved ints of each gambit row
## (dec. 4, landed by #1126). This test is the answer to "why do you believe it".
##
## 🔴 THE TRAP THIS TEST EXISTS FOR. A verdict write that never fires — wrong branch,
## wrong slot index, gated off — leaves a ZEROED field, and `VERDICT_NONE == 0` is a
## REAL ANSWER ("this call did not reach this slot"), not absence. So nothing here
## asserts nonzero-ness: every assertion names the DECODED field and the exact code,
## and the payload beside it. A zero from a blind instrument is not absence.
##
## TWELVE CODES, NINE BATTLES, ONE PROCESS. Each cell is a battle in one batch, rigged
## so exactly one failure point is reachable, and every cell that can share a roster
## carries several assertions — the charter's clause 13 (a test here is a process with
## a ~2.3 s floor, so splitting one costs 2.3 s forever). The batch steps once for all
## nine, so the ninth cell is free.
##
##   b0  FIRED + NONE       slot 0 commits; slot 1 is never walked and must read NONE
##   b1  DISABLED           GM_ENABLED == 0, payload 0, and pass 2 skips the slot
##   b2  CONDITION_FALSE    x2 (first and second condition), + the pass-2 pair:
##                          CONDITION_FALSE at rank 1 and NOT_RETRYABLE on TARGET_SELF
##   b3  RANKS_EXHAUSTED    one enemy, so `find_nth_nearest(1)` ends the rank walk
##   b4  NO_CANDIDATE       + NO_FINAL_TARGET — a lone unit: no ally to condition on,
##                          and no ally for the ACTION's own target type to resolve
##   b5  SILENCED           STATUS_SILENCE on the ACTOR, vetoing a SPELL
##   b6  IMMOBILIZED        x2 — STATUS_IMMOBILIZE vetoes MOVE_TO *and* MOVE_TO_UNIT
##   b7  MP_SHORT           spell_pre_validate: 1 MP against a costed spell
##   b8  ON_COOLDOWN        ADR-0047 B8, seeded through the cooldown SSBO
##
## THE LAYOUT IS PARSED, NOT TRANSCRIBED, and the parse lives in [GambitVerdictReader]
## under `src/`, not here. `combat_common.glslinc` is the authority for the code numbers
## and the bit shifts and the reader reads them out of it at run time — a mirrored enum
## would be a second source of truth that goes stale silently, and the decode would then
## report the wrong NAME for the right bits. The reader is in `src/gpu/` because the live
## arm's readout panel is its SECOND consumer (ADR-0275 dec. 13/20) and two copies of that
## table is the same staleness one layer out.
##
## What stays here is the SCORING: every check the reader makes about its own load — twelve
## codes declared, each of the eight fields the documented width (derived from the gaps
## between successive shifts) — is fed through `_check`, so a layout that changes shape reds
## this test instead of decoding garbage. The last assertion is a COVERAGE one: every
## `VERDICT_*` code the kernel declares must be named by some cell, so a thirteenth verdict
## cannot land uncelled.
##
## Run headful (never --headless), from `godot-learning/`:
##   godot --path . tests/GambitVerdictCellsTest.tscn

const UNITS_PER_BATTLE := 4        # set_battle_units caps each team at half of this
const TICK_BUDGET := 300           # ticks, never seconds (charter clause 6)
const TICK_CHUNK := 5

## Fire — a costed, cooldown-carrying spell in `AbilityDatabase`. Both quantities are
## ASSERTED below rather than assumed: the lever layer bakes them at load (ADR-0277
## dec. 2), and a lever that zeroed either one would make the MP_SHORT / ON_COOLDOWN
## cells pass vacuously by reaching FIRED through a veto that no longer exists.
const SPELL_ABILITY := 16

## The shared decoder (ADR-0275 dec. 4). Parses the verdict vocabulary and the bit shifts
## out of `combat_common.glslinc` at run time; this test SCORES its self-checks.
var _reader := GambitVerdictReader.new()

var _k: Dictionary = {}            # every `const int NAME = v;` in the kernel header
var _code_of: Dictionary = {}      # "FIRED" -> 1
var _name_of: Dictionary = {}      # 1 -> "FIRED"
var _fields: Array = []            # [{key, shift, width}, ...]
var _cells_grid: Array = []        # walkable level-0 cells, sorted
var _ability: Dictionary = {}      # GPUAbilityLoader cache, post-lever
var _pass := 0
var _fail := 0


func get_test_name() -> String:
	return "Gambit Verdict Cells Test"


func _ready():
	max_ticks = 999999
	auto_start = false
	regression_logging = false
	_rlog = RegressionLogger.new(get_test_name(), false)

	print("\n=== %s ===" % get_test_name())

	await get_tree().process_frame
	await get_tree().process_frame

	if not _load_kernel_layout():
		await _report()
		return

	# ADR-0192 dec. 3's clean fetch — one untyped step at the seam, into a LOCAL
	# annotated here (the field is inherited from `CombatHost`).
	var lat: Lattice = map.lattice
	lattice = lat
	if lat == null:
		_check(false, "map has a lattice")
		await _report()
		return

	_collect_cells()
	if _cells_grid.size() < UNITS_PER_BATTLE:
		_check(false, "map has at least %d walkable level-0 cells (has %d)" % [
			UNITS_PER_BATTLE, _cells_grid.size()])
		await _report()
		return

	_setup_distance_field()
	var df: DistanceFieldGenerator = combat_loop.distance_field
	if df == null:
		_check(false, "the combat loop built a distance field")
		await _report()
		return

	_ability = GPUAbilityLoader.build()["cache"]
	_check_ability_preconditions()

	var cells: Array = _build_cells()
	var sim := GPUBatchSimulator.new()
	if not sim.initialize(lattice, df, cells.size(), UNITS_PER_BATTLE):
		sim.cleanup()
		_check(false, "GPUBatchSimulator initialized for %d battles (VRAM?)" % cells.size())
		await _report()
		return

	_seat(sim, cells)
	var walked_at: int = _step_until_walked(sim, cells)
	print("[cells] %d battles x %d units, every cell walked by tick %d of %d" % [
		cells.size(), UNITS_PER_BATTLE, walked_at, TICK_BUDGET])

	var snaps: Dictionary = {}
	for cell in cells:
		snaps[cell["battle"]] = sim.snapshot_battle(int(cell["battle"]))
	sim.cleanup()

	_report_cells(cells, snaps)
	_check_cells(cells, snaps)
	_check_coverage(cells)
	await _report()


func _process(_delta):
	pass


# === The kernel's own layout ==================================================

## The decode lives in [GambitVerdictReader] (`src/gpu/`), not here — the live arm's
## readout panel is its second consumer (ADR-0275 dec. 13/20) and a second copy of the
## table would go stale silently. What stays in the TEST is the SCORING of the reader's
## own checks: that it found twelve codes and that every field is the documented width.
## That is the guard on the decoder, and a guard belongs in the thing that can fail.
func _load_kernel_layout() -> bool:
	var loaded := _reader.load_layout()
	for c in _reader.checks:
		_check(bool(c["ok"]), String(c["what"]))
	_k = _reader.consts
	_code_of = _reader.code_of
	_name_of = _reader.name_of
	_fields = _reader.fields
	return loaded and _fail == 0


func _decode(word_a: int, word_b: int) -> Dictionary:
	return _reader.decode(word_a, word_b)


func _fmt(d: Dictionary) -> String:
	return _reader.format(d)


# === The cells ===============================================================

func _collect_cells() -> void:
	var cells: Array = []
	# `lattice` is declared on `CombatHost` and annotation inference is PER FILE, so
	# the port guard reads the inherited field as an undeclared receiver.
	var lat: Lattice = lattice
	for c in lat.all_cells():
		if c.grid.z != 0 or c.impassable or c.pass_through_only:
			continue
		cells.append(c.grid)
	cells.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	_cells_grid = cells


## Every unit is unkillable and full of MP unless its cell says otherwise: an HP or MP
## number that drifts mid-run would move the PAYLOAD a condition cell asserts on.
func _cfg(overrides: Dictionary) -> Dictionary:
	var base := {"hp": 9999, "max_hp": 9999, "pa": 12, "ma": 10, "wp": 6,
		"brave": 60, "faith": 60, "mp": 200, "max_mp": 200, "speed": 8,
		"move": 4, "jump": 3, "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1}
	for k in overrides:
		base[k] = overrides[k]
	return base


func _attack() -> Dictionary:
	return GPUCombatTestBase.make_attack_gambit()


## An attack row whose CONDITION target pool and condition list are the rig.
func _attack_when(cond_target: int, conditions: Array) -> Dictionary:
	var g := GPUCombatTestBase.make_attack_gambit()
	g["cond_target_type"] = cond_target
	g["conditions"] = conditions
	return g


func _cond(type: int, value: int) -> Dictionary:
	return {"type": type, "value": value}


func _build_cells() -> Array:
	var g := _cells_grid
	var out: Array = []

	# --- b0: the slot that FIRED, and the slot the walk never reached -------------
	out.append({
		"battle": 0, "label": "FIRED + NONE",
		"team0": [_cfg({})], "team1": [_cfg({})],
		"ladders": {0: [_attack(), _attack()]},
		"ready": [0, 0],
		"expect": [
			# `candidate` is the payload of a FIRED slot: unit 1 is the only enemy.
			{"unit": 0, "slot": 0, "p1": "FIRED", "ci": 0, "op": 0, "mask": 0b0001,
				"payload": 1, "p2": "NONE",
				"why": "slot 0 committed the attack, and pass 2 never ran because it did"},
			# NOT asserted: the payload. `clear_verdict` writes int A only — a
			# VERDICT_NONE in the pass-1 nibble makes int B meaningless, so a second
			# store would be bought for nothing (kernel comment, dec. 4).
			{"unit": 0, "slot": 1, "p1": "NONE", "p2": "NONE",
				"why": "slot 1 was cleared and never walked — NONE is that answer, not absence"},
		],
	})

	# --- b1: GM_ENABLED == 0 ------------------------------------------------------
	var disabled := _attack()
	disabled["enabled"] = false
	out.append({
		"battle": 1, "label": "DISABLED",
		"team0": [_cfg({})], "team1": [_cfg({})],
		"ladders": {0: [disabled, _attack()]},
		"ready": [0, 1],
		"expect": [
			{"unit": 0, "slot": 0, "p1": "DISABLED", "ci": 0, "op": 0, "mask": 0,
				"payload": 0, "p2": "NONE",
				"why": "a disabled slot stamps zeroes for every detail field, and pass 2 skips it"},
			{"unit": 0, "slot": 1, "p1": "FIRED", "payload": 1,
				"why": "the ladder fell through to slot 1"},
		],
	})

	# --- b2: a condition said no — twice, and both passes -------------------------
	# 2v2, everyone at full HP and full MP, and NOTHING in this ladder can fire, which
	# is what lets pass 2 run at all.
	out.append({
		"battle": 2, "label": "CONDITION_FALSE (x2) + pass-2 pair",
		"team0": [_cfg({}), _cfg({})], "team1": [_cfg({}), _cfg({})],
		"ladders": {
			0: [
				_attack_when(GPUConstants.TARGET_NEAREST_ENEMY,
					[_cond(GPUConstants.COND_HP_BELOW, 5)]),
				_attack_when(GPUConstants.TARGET_SELF,
					[_cond(GPUConstants.COND_ALWAYS, 0), _cond(GPUConstants.COND_MP_BELOW, 1)]),
			],
			1: [],
		},
		"ready": [0, 0],
		"expect": [
			{"unit": 0, "slot": 0, "p1": "CONDITION_FALSE", "ci": 0,
				"op": GPUConstants.COND_HP_BELOW, "mask": 0b0001, "payload": 100,
				"p2": "CONDITION_FALSE", "p2ci": 0, "p2op": GPUConstants.COND_HP_BELOW, "rank": 1,
				"why": "HP_BELOW 5 against a target at 100% — the number that lost is the payload; "
					+ "the rank-1 enemy said no too, and pass 2 records it WITHOUT clobbering pass 1"},
			{"unit": 0, "slot": 1, "p1": "CONDITION_FALSE", "ci": 1,
				"op": GPUConstants.COND_MP_BELOW, "mask": 0b0011, "payload": 100,
				"p2": "NOT_RETRYABLE", "p2ci": 0, "p2op": 0, "rank": 0,
				"why": "condition 1 failed with condition 0 already RUN — the evaluated mask is "
					+ "what stops `condition 1 failed` reading as `1 was the only one checked`"},
		],
	})

	# --- b3: pass 2 walked the ranks to the end ----------------------------------
	# ONE enemy, so `find_nth_nearest(rank 1)` returns -1 immediately and the rank walk
	# ends on its initial verdict with the last reached rank still 0.
	out.append({
		"battle": 3, "label": "RANKS_EXHAUSTED",
		"team0": [_cfg({})], "team1": [_cfg({})],
		"ladders": {0: [_attack_when(GPUConstants.TARGET_NEAREST_ENEMY,
			[_cond(GPUConstants.COND_HP_BELOW, 5)])]},
		"ready": [0, 0],
		"expect": [
			{"unit": 0, "slot": 0, "p1": "CONDITION_FALSE", "op": GPUConstants.COND_HP_BELOW,
				"payload": 100, "p2": "RANKS_EXHAUSTED", "p2ci": 0, "p2op": 0, "rank": 0,
				"why": "the only enemy IS rank 0, so there is no rank 1 to try"},
		],
	})

	# --- b4: nobody to condition on, and nobody for the ACTION to hit -------------
	# A lone team-0 unit: `TARGET_NEAREST_ALLY` excludes self, so the pool is empty.
	var no_final := _attack_when(GPUConstants.TARGET_NEAREST_ENEMY,
		[_cond(GPUConstants.COND_ALWAYS, 0)])
	no_final["action_target_type"] = GPUConstants.TARGET_NEAREST_ALLY
	out.append({
		"battle": 4, "label": "NO_CANDIDATE + NO_FINAL_TARGET",
		"team0": [_cfg({})], "team1": [_cfg({})],
		"ladders": {0: [
			_attack_when(GPUConstants.TARGET_NEAREST_ALLY, [_cond(GPUConstants.COND_ALWAYS, 0)]),
			no_final,
		]},
		"ready": [0, 0],
		"expect": [
			{"unit": 0, "slot": 0, "p1": "NO_CANDIDATE", "ci": 0, "op": 0, "mask": 0,
				"payload": GPUConstants.TARGET_NEAREST_ALLY,
				"why": "NO_CANDIDATE's payload is the TARGET_* pool that came back empty, "
					+ "not a measured quantity"},
			{"unit": 0, "slot": 1, "p1": "NO_FINAL_TARGET", "mask": 0b0001, "payload": 1,
				"why": "the conditions passed against enemy 1 and the ACTION's own target type "
					+ "resolved to -1; the payload is the candidate that got that far"},
		],
	})

	# --- b5: SPELL vetoed by STATUS_SILENCE on the ACTOR --------------------------
	out.append({
		"battle": 5, "label": "SILENCED",
		"team0": [_cfg({"status_flags_lo": 1 << int(_k["STATUS_SILENCE"])})],
		"team1": [_cfg({})],
		"ladders": {0: [GPUCombatTestBase.make_spell_gambit(
			SPELL_ABILITY, GPUConstants.TARGET_NEAREST_ENEMY)]},
		"ready": [0, 0],
		"status": {"unit": 0, "bit": int(_k["STATUS_SILENCE"])},
		"expect": [
			{"unit": 0, "slot": 0, "p1": "SILENCED", "mask": 0b0001, "payload": 1,
				"why": "the silence gate is read on the ACTOR and fires before MP is even looked at"},
		],
	})

	# --- b6: both movement actions vetoed by STATUS_IMMOBILIZE --------------------
	var move_to_unit := {
		"enabled": true,
		"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
		"conditions": [_cond(GPUConstants.COND_ALWAYS, 0)],
		"action_type": GPUConstants.ACTION_MOVE_TO_UNIT,
		"action_id": 0,
		"action_target_type": GPUConstants.TARGET_THEM,
	}
	out.append({
		"battle": 6, "label": "IMMOBILIZED (MOVE_TO and MOVE_TO_UNIT)",
		"team0": [_cfg({"status_flags_lo": 1 << int(_k["STATUS_IMMOBILIZE"])})],
		"team1": [_cfg({})],
		"ladders": {0: [
			GPUCombatTestBase.make_move_to_gambit(g[1].x, g[1].y),
			move_to_unit,
		]},
		"ready": [0, 0],
		"status": {"unit": 0, "bit": int(_k["STATUS_IMMOBILIZE"])},
		"expect": [
			# The p2 here is a SECOND witness for NOT_RETRYABLE, and it is asserted because
			# the seeded-break run found it: breaking the pass-2 no-alternates branch moved
			# this field and reddened nothing, which is a produced verdict nobody watched.
			{"unit": 0, "slot": 0, "p1": "IMMOBILIZED", "mask": 0b0001, "payload": 0,
				"p2": "NOT_RETRYABLE",
				"why": "MOVE_TO resolves TARGET_SELF, so the payload is the actor's own id — "
					+ "0 here is a decoded SUBJECT, which is why the code is asserted beside it, "
					+ "and TARGET_SELF has no alternates for pass 2 to try"},
			{"unit": 0, "slot": 1, "p1": "IMMOBILIZED", "mask": 0b0001, "payload": 1,
				"why": "the same veto covers MOVE_TO_UNIT; a rig that only tried MOVE_TO would "
					+ "leave half the branch unwitnessed"},
		],
	})

	# --- b7: spell_pre_validate said no ------------------------------------------
	out.append({
		"battle": 7, "label": "MP_SHORT",
		"team0": [_cfg({"mp": 1})], "team1": [_cfg({})],
		"ladders": {0: [GPUCombatTestBase.make_spell_gambit(
			SPELL_ABILITY, GPUConstants.TARGET_NEAREST_ENEMY)]},
		"ready": [0, 0],
		"expect": [
			{"unit": 0, "slot": 0, "p1": "MP_SHORT", "mask": 0b0001, "payload": 1,
				"why": "1 MP against a costed spell, with a live final target — so this is the "
					+ "MP arm of spell_pre_validate and not its target arm"},
		],
	})

	# --- b8: the ADR-0047 B8 cooldown floor --------------------------------------
	# Seeded through the cooldown SSBO rather than by letting the spell fire once: the
	# fire-then-retry route works, but it dates the assertion to whichever tick the
	# second evaluation lands on. A seeded `ready_at` is the same veto, on tick 1.
	out.append({
		"battle": 8, "label": "ON_COOLDOWN",
		"team0": [_cfg({})], "team1": [_cfg({})],
		"ladders": {0: [GPUCombatTestBase.make_spell_gambit(
			SPELL_ABILITY, GPUConstants.TARGET_NEAREST_ENEMY)]},
		"cooldown": {"unit": 0, "ability": SPELL_ABILITY, "ready_at": 1000000},
		"ready": [0, 0],
		"expect": [
			{"unit": 0, "slot": 0, "p1": "ON_COOLDOWN", "mask": 0b0001, "payload": 1,
				"why": "MP is full, so the slot got past spell_pre_validate and died on the "
					+ "cooldown floor — the two vetoes are independent and this proves which one"},
		],
	})

	# --- b9: a retreat with nowhere to go ----------------------------------------
	# ADR-0301. The only verdict in the vocabulary that reports a failure found by
	# reading the MAP, and the only one whose pre-validation is there so the slot can
	# FALL THROUGH: a cornered unit has to be able to reach its Attack row.
	#
	# Seeded by aiming the retreat at the ACTOR rather than by boxing a unit in with
	# terrain. `retreat_step_cell` refuses `flee_from == unit_id` outright, so this is
	# the one "there is no cell" case that does not depend on what MapComposer built
	# this run — the same reason GPURetreatStepTest's arm 4 uses it.
	var retreat_self := {
		"enabled": true,
		"cond_target_type": GPUConstants.TARGET_SELF,
		"conditions": [_cond(GPUConstants.COND_ALWAYS, 0)],
		"action_type": GPUConstants.ACTION_RETREAT_STEP,
		"action_id": 0,
		"action_target_type": GPUConstants.TARGET_SELF,
	}
	out.append({
		"battle": 9, "label": "NO_RETREAT",
		"team0": [_cfg({})], "team1": [_cfg({})],
		"ladders": {0: [retreat_self]},
		"ready": [0, 0],
		"expect": [
			{"unit": 0, "slot": 0, "p1": "NO_RETREAT", "mask": 0b0001, "payload": 0,
				"p2": "NOT_RETRYABLE",
				"why": "the condition passed and the ACTION died on the map, not on a status "
					+ "bit or a pool — the payload is the actor's own id, which is exactly what "
					+ "made the retreat impossible; TARGET_SELF has no alternates for pass 2"},
		],
	})

	return out


# === Running them ============================================================

func _seat(sim: GPUBatchSimulator, cells: Array) -> void:
	var g := _cells_grid
	for cell in cells:
		var b: int = int(cell["battle"])
		var t0: Array = []
		var t1: Array = []
		for i in range((cell["team0"] as Array).size()):
			t0.append(_build_gpu_config(g[i], cell["team0"][i]))
		for i in range((cell["team1"] as Array).size()):
			t1.append(_build_gpu_config(g[2 + i], cell["team1"][i]))
		sim.set_battle_units(b, t0, t1, 1234)
		# EVERY unit gets an explicit ladder, including the inert ones: a support unit
		# left to whatever the buffer holds is a unit that might act, and an actor that
		# gets attacked is an actor whose HP payload moves.
		for u in range(UNITS_PER_BATTLE):
			var ladder: Array = (cell["ladders"] as Dictionary).get(u, [])
			sim.set_unit_gambits(b, u, ladder)
		if cell.has("cooldown"):
			var cd: Dictionary = cell["cooldown"]
			var snap: Dictionary = sim.snapshot_battle(b)
			var words: PackedInt32Array = snap["cooldowns"]
			words[int(cd["unit"]) * GPUBatchSimulator.MAX_COOLDOWN_ABILITIES
				+ int(cd["ability"])] = int(cd["ready_at"])
			snap["cooldowns"] = words
			_check(sim.restore_battle(b, snap),
				"b%d: seeded the cooldown SSBO through restore_battle" % b)


## Step until every cell's actor has actually been WALKED, or the tick budget runs out.
## Readiness is deliberately "this slot's pass-1 nibble left NONE" and not "the expected
## code appeared": the loop must not be able to wait for the answer it wants.
func _step_until_walked(sim: GPUBatchSimulator, cells: Array) -> int:
	var ticks := 0
	while ticks < TICK_BUDGET:
		sim.step_tick(TICK_CHUNK)
		ticks += TICK_CHUNK
		var all_walked := true
		for cell in cells:
			var ready: Array = cell["ready"]
			var words: PackedInt32Array = sim.snapshot_battle(int(cell["battle"]))["gambits"]
			var d := _decode_slot(words, int(ready[0]), int(ready[1]))
			if int(d["p1"]) == int(_code_of["NONE"]):
				all_walked = false
				break
		if all_walked:
			return ticks
	return ticks


func _decode_slot(words: PackedInt32Array, unit: int, slot: int) -> Dictionary:
	return _reader.read_slot(words, unit, slot)


# === The assertions ==========================================================

func _check(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAILED: %s" % what)


func _check_ability_preconditions() -> void:
	var ab: Dictionary = _ability.get(SPELL_ABILITY, {})
	_check(int(ab.get("mp_cost", 0)) > 1,
		"ability %d costs more than the 1 MP the MP_SHORT cell's actor holds (post-lever cost %s)" % [
			SPELL_ABILITY, str(ab.get("mp_cost", "missing"))])
	_check(int(ab.get("cooldown_ticks", 0)) > 0,
		"ability %d carries a cooldown at all, or cooldown_pre_validate returns true before "
		% SPELL_ABILITY + "reading the SSBO (post-lever ticks %s)" % str(ab.get("cooldown_ticks", "missing")))


func _report_cells(cells: Array, snaps: Dictionary) -> void:
	for cell in cells:
		var b: int = int(cell["battle"])
		var words: PackedInt32Array = snaps[b]["gambits"]
		print("[cells] b%d %s" % [b, cell["label"]])
		for e in cell["expect"]:
			var d := _decode_slot(words, int(e["unit"]), int(e["slot"]))
			print("    u%d slot %d  %s" % [int(e["unit"]), int(e["slot"]), _fmt(d)])


func _check_cells(cells: Array, snaps: Dictionary) -> void:
	for cell in cells:
		var b: int = int(cell["battle"])
		var snap: Dictionary = snaps[b]
		var words: PackedInt32Array = snap["gambits"]
		if cell.has("status"):
			# A status that failed to seat would show up as the WRONG verdict below, but
			# it would show up as a mystery. Read the bit back off the unit block.
			var st: Dictionary = cell["status"]
			var flags: int = _unit_field(snap["battle"], int(st["unit"]),
				GPUCombatPacker.UnitField.STATUS_FLAGS_LO)
			_check((flags & (1 << int(st["bit"]))) != 0,
				"b%d: status bit %d is set on the actor (flags_lo=%d)" % [b, int(st["bit"]), flags])
		for e in cell["expect"]:
			var d := _decode_slot(words, int(e["unit"]), int(e["slot"]))
			for key in e.keys():
				if key in ["unit", "slot", "why"]:
					continue
				# `-1` for an unknown name rather than an invalid-index runtime error: a
				# GDScript error inside this coroutine would abort the walk SILENTLY and
				# leave the process with no verdict at all.
				var want: int = int(_code_of.get(e[key], -1)) if typeof(e[key]) == TYPE_STRING else int(e[key])
				var got: int = int(d[key])
				var shown_got: String = _name_of.get(got, str(got)) if key in ["p1", "p2"] else str(got)
				# The key leads the line — `b2/u0/s0 op` — so a seeded-break run can be
				# scored mechanically against the set of assertions it was PREDICTED to
				# red. An arm that reds a different set is a break nobody attributed.
				_check(got == want, "b%d/u%d/s%d %s: expected %s, got %s — %s [%s]" % [
					b, int(e["unit"]), int(e["slot"]), key, str(e[key]), shown_got,
					e.get("why", ""), cell["label"]])


func _unit_field(battle_slice: PackedInt32Array, unit: int, field: int) -> int:
	return battle_slice[GPUCombatPacker.BATTLE_HEADER_SIZE + unit * GPUCombatPacker.UNIT_SIZE + field]


## The clause that keeps this test from going stale: a verdict code the kernel declares
## and no cell names is a failure point nobody is watching, which is the exact state
## ADR-0275 dec. 18 exists to end.
func _check_coverage(cells: Array) -> void:
	var named: Dictionary = {}
	for cell in cells:
		for e in cell["expect"]:
			for key in ["p1", "p2"]:
				if e.has(key) and typeof(e[key]) == TYPE_STRING:
					named[e[key]] = true
	var missing: Array = []
	for code in _code_of.keys():
		if not named.has(code):
			missing.append(code)
	_check(missing.is_empty(),
		"every verdict code the kernel declares is asserted by a cell (uncelled: %s)" % str(missing))
	print("[cells] codes asserted: %d of %d declared" % [named.size(), _code_of.size()])


func _report() -> void:
	print("\n--- %s: %d passed, %d failed ---" % [get_test_name(), _pass, _fail])
	# Clause 9: a green summary is not a run. Zero assertions is a FAIL, not a pass.
	if _pass == 0:
		print("[VERDICT] FAIL — no assertion ran; this test did not exercise the verdict")
	elif _fail > 0:
		print("[VERDICT] FAIL — %d of %d verdict assertions disagree with the kernel" % [
			_fail, _pass + _fail])
	else:
		print("[VERDICT] PASS — %d assertions: all %d verdict codes decode from the kernel's own write, with their payloads" % [
			_pass, _code_of.size()])
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if _fail > 0 or _pass == 0 else 0)
