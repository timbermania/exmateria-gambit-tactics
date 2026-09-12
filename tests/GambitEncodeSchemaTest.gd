extends Node
## Gambit encode schema round-trip test (ADR-0016). Pure GDScript — no GPU /
## RenderingDevice, no scene setup. Guards the looped source of truth that packs
## an encoded gambit into the GambitField buffer layout:
##
##   1. Schema invariants — no doubly-written offset, and *completeness*: every
##      offset in [0, GAMBIT_SIZE) is written exactly once (schema, the
##      hand-packed condition block, or RESERVED). Same pure check the boot
##      validator runs. Catches an added-but-unpacked GambitField.
##   2. Round-trip — a config with a distinct value per flat key, packed via
##      _pack_gambits, reads back at the matching GambitField offset. The
##      hand-packed condition block round-trips too (count + per-slot type/value).
##   3. Defaults — an enabled slot that omits the flat keys falls back to each
##      row's declared default (the load-bearing contract for partial configs).


func _ready() -> void:
	var failed := false

	# 1. Schema invariants (duplicate offset + whole-buffer completeness).
	var problems := GPUCombatPacker.gambit_config_schema_problems()
	if not problems["errors"].is_empty():
		for e in problems["errors"]:
			print("[FAIL] schema error: %s" % e)
		failed = true

	# 2. Round-trip: one slot, distinct value per flat key + two conditions.
	var cfg := {}
	var v := 100
	for row in GPUCombatPacker.GAMBIT_CONFIG_SCHEMA:
		cfg[row["key"]] = v
		v += 1
	cfg["conditions"] = [
		{"type": 7, "value": 30},
		{"type": 9, "value": 50},
	]
	var data := GPUCombatPacker._pack_gambits([cfg])

	for row in GPUCombatPacker.GAMBIT_CONFIG_SCHEMA:
		var field: int = row["field"]
		var expected: int = int(cfg[row["key"]])
		if data[field] != expected:
			print("[FAIL] round-trip key '%s' -> offset %d: packed %d, read %d" % [row["key"], field, expected, data[field]])
			failed = true

	# Hand-packed condition block round-trips.
	var GF := GPUCombatPacker.GambitField
	if data[GF.COND_COUNT] != 2:
		print("[FAIL] COND_COUNT: expected 2, got %d" % data[GF.COND_COUNT])
		failed = true
	if data[GF.COND_TYPE_0] != 7 or data[GF.COND_VAL_0] != 30:
		print("[FAIL] condition slot 0: expected (7,30), got (%d,%d)" % [data[GF.COND_TYPE_0], data[GF.COND_VAL_0]])
		failed = true
	if data[GF.COND_TYPE_1] != 9 or data[GF.COND_VAL_1] != 50:
		print("[FAIL] condition slot 1: expected (9,50), got (%d,%d)" % [data[GF.COND_TYPE_1], data[GF.COND_VAL_1]])
		failed = true

	# 3. Defaults: an enabled slot omitting the flat keys falls back per row.
	var default_data := GPUCombatPacker._pack_gambits([{"enabled": true}])
	for row in GPUCombatPacker.GAMBIT_CONFIG_SCHEMA:
		var field: int = row["field"]
		var expected_default: int = int(row["default"])
		if default_data[field] != expected_default:
			print("[FAIL] default for '%s' -> offset %d: expected %d, got %d" % [row["key"], field, expected_default, default_data[field]])
			failed = true

	# A disabled/absent slot stays fully zero.
	var empty := GPUCombatPacker._pack_gambits([null])
	for i in range(GPUCombatPacker.GAMBIT_SIZE):
		if empty[i] != 0:
			print("[FAIL] disabled slot offset %d: expected 0, got %d" % [i, empty[i]])
			failed = true

	if failed:
		print("[FAIL] Gambit encode schema test")
	else:
		print("[PASS] Gambit encode schema: %d flat rows, round-trip + conditions + defaults OK" % GPUCombatPacker.GAMBIT_CONFIG_SCHEMA.size())
	get_tree().quit()
