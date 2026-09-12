extends Node
## Unit encode schema round-trip test (ADR-0003). Pure GDScript — no GPU /
## RenderingDevice, no scene setup. Guards the single source of truth that maps
## a Unit into the combat buffer layout:
##
##   1. Schema invariants — no duplicate offsets, no live field missing an
##      extractor (the same pure check the boot validator runs). Knowingly-
##      unwired live fields (the equipped-reaction gap) surface as warnings.
##   1b. Buffer coverage — _write_unit_data touches every offset in
##      [0, UNIT_SIZE); an enum field with no writer is a boot error, not a
##      silent zero (ADR-0003 completeness net, gambit analogue).
##   2. Round-trip — a config with distinct per-key values, written via
##      _write_unit_data, reads back at the matching SNAPSHOT_FIELDS offset.
##      Also proves every encoded offset is observable in the snapshot.
##   3. Defaults — an empty config falls back to each row's declared default
##      (the load-bearing contract for the test path / dormant fields).
##   5. Reconfigure classification (ADR-0235) — no SHADER-WRITTEN field is
##      classified `recompute`, with the shader-write set scanned out of the
##      kernel source rather than hand-listed.
##   6. Overlay behaviour, saturated — `overlay_unit_config` over a block whose
##      every offset carries a distinct sentinel: `recompute` offsets take the
##      config value, `clamp` offsets keep the live value under the new ceiling,
##      and `carry` offsets plus all 57 non-schema offsets keep their sentinel.
##      Total over all 102 offsets, so it cannot pass vacuously the way a
##      real-battle no-op identity can (a battle that never breaks a weapon
##      never diverges `wp`, and would not notice it misclassified).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase



func _ready() -> void:
	var failed := false

	# 1. Schema invariants.
	var problems := GPUCombatPacker.unit_config_schema_problems()
	for w in problems["warnings"]:
		print("[WARN] %s" % w)
	if not problems["errors"].is_empty():
		for e in problems["errors"]:
			print("[FAIL] schema error: %s" % e)
		failed = true

	# 1b. Buffer coverage — _write_unit_data touches every offset in [0, UNIT_SIZE).
	var coverage := GPUCombatPacker.unit_buffer_coverage_problems()
	if not coverage["errors"].is_empty():
		for e in coverage["errors"]:
			print("[FAIL] coverage error: %s" % e)
		failed = true

	# Offset -> snapshot key, so we can confirm every encoded field is observable.
	var snapshot_offsets := {}
	for k in GPUCombatPacker.SNAPSHOT_FIELDS:
		snapshot_offsets[GPUCombatPacker.SNAPSHOT_FIELDS[k]] = k

	# 2. Round-trip with a distinct value per unique key.
	var cfg := {}
	var v := 1000
	for row in GPUCombatPacker.UNIT_CONFIG_SCHEMA:
		if not cfg.has(row["key"]):
			cfg[row["key"]] = v
			v += 1
	var data := PackedInt32Array()
	data.resize(GPUCombatPacker.UNIT_SIZE)
	GPUCombatPacker._write_unit_data(data, 0, cfg, 0)
	for row in GPUCombatPacker.UNIT_CONFIG_SCHEMA:
		var field: int = row["field"]
		if not snapshot_offsets.has(field):
			print("[FAIL] schema offset %d (key '%s') is not in SNAPSHOT_FIELDS" % [field, row["key"]])
			failed = true
			continue
		var expected: int = cfg[row["key"]]
		if data[field] != expected:
			print("[FAIL] round-trip key '%s' -> offset %d: wrote %d, read %d" % [row["key"], field, expected, data[field]])
			failed = true

	# 3. Absent keys fall back to declared defaults.
	var empty_data := PackedInt32Array()
	empty_data.resize(GPUCombatPacker.UNIT_SIZE)
	GPUCombatPacker._write_unit_data(empty_data, 0, {}, 0)
	for row in GPUCombatPacker.UNIT_CONFIG_SCHEMA:
		var field: int = row["field"]
		var expected_default: int = row["default"]
		if empty_data[field] != expected_default:
			print("[FAIL] default for '%s' -> offset %d: expected %d, got %d" % [row["key"], field, expected_default, empty_data[field]])
			failed = true

	# 4. Reaction mapping (ADR-0003 follow-up): the gap is closed (no warnings),
	#    and every mapped id is a real Reaction ability pointing at a valid
	#    REACT_* enum value (0..6).
	if not problems["warnings"].is_empty():
		print("[FAIL] expected no schema warnings after wiring reaction; got: %s" % str(problems["warnings"]))
		failed = true
	var rmap: Dictionary = GPUCombatPacker.REACTION_ABILITY_TO_REACT
	if rmap.size() != 7:
		print("[FAIL] reaction map should have 7 entries, has %d" % rmap.size())
		failed = true
	for id in rmap:
		var react: int = rmap[id]
		if react < 0 or react > 6:
			print("[FAIL] reaction map id %d -> %d is outside REACT_* range" % [id, react])
			failed = true
		if AbilityDatabase.get_ability_view(id).ability_type != "Reaction":
			print("[FAIL] reaction map id %d is not a Reaction-type ability" % id)
			failed = true

	# 5. Reconfigure classification (ADR-0235). A field the SHADER writes is live
	#    state, so it may not be `recompute`; the shader-write set is scanned out
	#    of the kernel source, not hand-listed, and an empty scan is an error.
	var written: Dictionary = GPUCombatPacker.shader_written_unit_fields()
	if written.is_empty():
		print("[FAIL] shader-write scan returned nothing — the ADR-0235 guard is inert")
		failed = true
	var behave_problems := GPUCombatPacker.overlay_behaviour_problems()
	for e in behave_problems["errors"]:
		print("[FAIL] behaviour error: %s" % e)
		failed = true

	# 6. Overlay behaviour, saturated over all UNIT_SIZE offsets.
	var live := PackedInt32Array()
	live.resize(GPUCombatPacker.UNIT_SIZE)
	for i in range(GPUCombatPacker.UNIT_SIZE):
		live[i] = 90000 + i  # distinct per offset, and far above any config value
	var before := live.duplicate()
	# A config whose max_hp / max_mp sit BELOW the live sentinel, so the clamp
	# rows have something to bite on; every other key gets its own value.
	var ocfg := {}
	var ov := 100
	for row in GPUCombatPacker.UNIT_CONFIG_SCHEMA:
		if not ocfg.has(row["key"]):
			ocfg[row["key"]] = ov
			ov += 1
	GPUCombatPacker.overlay_unit_config(live, 0, ocfg)
	var classified := {}
	for row in GPUCombatPacker.UNIT_CONFIG_SCHEMA:
		var field: int = row["field"]
		classified[field] = true
		var behave: String = row["behave"]
		if behave == GPUCombatPacker.BEHAVE_RECOMPUTE:
			if live[field] != ocfg[row["key"]]:
				print("[FAIL] overlay '%s' (offset %d) is recompute: expected %d, got %d" % [
					row["key"], field, ocfg[row["key"]], live[field]])
				failed = true
		elif behave == GPUCombatPacker.BEHAVE_CARRY:
			if live[field] != before[field]:
				print("[FAIL] overlay '%s' (offset %d) is carry but moved %d -> %d" % [
					row["key"], field, before[field], live[field]])
				failed = true
		elif behave == GPUCombatPacker.BEHAVE_CLAMP:
			var ceiling: int = live[row["clamp_to"]]
			var want: int = mini(before[field], ceiling)
			if live[field] != want:
				print("[FAIL] overlay '%s' (offset %d) is clamp: live %d, ceiling %d, expected %d, got %d" % [
					row["key"], field, before[field], ceiling, want, live[field]])
				failed = true
			if want >= before[field]:
				print("[FAIL] clamp arm is vacuous for '%s' — the ceiling did not bite" % row["key"])
				failed = true
	# Every offset with NO schema row is live state and must be untouched.
	for i in range(GPUCombatPacker.UNIT_SIZE):
		if not classified.has(i) and live[i] != before[i]:
			print("[FAIL] overlay touched non-schema offset %d: %d -> %d" % [i, before[i], live[i]])
			failed = true

	if failed:
		print("[FAIL] Unit encode schema test")
	else:
		print("[PASS] Unit encode schema: %d rows, round-trip + defaults + %d reactions OK; overlay classified against %d shader-written fields, saturated over %d offsets" % [
			GPUCombatPacker.UNIT_CONFIG_SCHEMA.size(), rmap.size(), written.size(), GPUCombatPacker.UNIT_SIZE])
	get_tree().quit()
