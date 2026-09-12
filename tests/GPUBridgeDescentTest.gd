extends GPUCombatTestBase

## ADR-0224's P4 and P5, END TO END ON THE GPU, on the map the ADR argues from.
##
## `GPUBridgeMoverAcceptanceTest` proves the two CPU-side inputs say the right
## thing over the whole corpus. This proves the SHADER READS THEM: a unit is
## deployed onto MAP083's bridge deck at `(4, 6, 1)` — record 405's cell — and
## the compute pipeline is run for real.
##
##   P4 — the unit's `U_HEIGHT` is 9, the deck's height, and the mover behaves as
##        if the tile under it is 9 rather than the 0 the column's ground holds.
##        Before ADR-0224's shader pass the packer wrote 9 and the shader read 0,
##        and nothing in the tree noticed.
##
##   P5 — the unit can path OFF the deck and reach the ground, and its route uses
##        no in-place level change: every step it takes moves to a different
##        `(x, z)`. Dec. 5 admits no "descend where you stand" move, so a step
##        that changed only the level would mean the mover invented one.
##
## ⚠️ THE MAP IS REAL AND THE BASE CLASS DOES NOT NORMALLY LOAD ONE. Every other
## `GPUCombatTestBase` scene runs on `ProceduralMap.tscn`, a flat arena with one
## level, which cannot express this defect at all. `_ready` swaps `map` for a
## `TerrainFixture` built from `assets/maps/MAP083/terrain.json` — the addon's own
## sanctioned lattice seam (ADR-0218), the same one `MapBufferCorpus` uses, so the
## tiles, the store, the port and the cliff rule are all production's.
##
## Run: <GODOT> --path . --quit-after 100000 res://tests/GPUBridgeDescentTest.tscn

const MapBufferCorpus = preload("res://tests/MapBufferCorpus.gd")
const TerrainFixture = ExMateriaBattlefield.TerrainFixture

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.

const MAP_NAME := "MAP083"
## Record 405's deployment cell (ADR-0224's opening table) and the ONLY reason
## this test names a map: `h0 = 0`, `h1 = 9`, the two numbers that differed by 9.
const DECK := Vector3i(4, 6, 1)
const DECK_HEIGHT := 9
const GROUND_HEIGHT_UNDER_DECK := 0
## A ground cell the deck can reach — the probe that picked it measured d = 1
## from `DECK` once the field grew its second plane.
const IDLER := Vector3i(4, 0, 0)

var _samples: Array[Vector3i] = []
var _done := false
var _start_height := -1
var _start_level := -1


func get_test_name() -> String:
	return "GPU Bridge Descent Test (ADR-0224 P4/P5)"


func _ready() -> void:
	var terrain: Dictionary = MapBufferCorpus.load_terrain(MAP_NAME)
	if terrain.is_empty():
		print("[FAIL] %s: terrain.json unreadable" % MAP_NAME)
		get_tree().quit(1)
		return
	var fixture := TerrainFixture.from_terrain(terrain)
	fixture.name = "RealMap"
	add_child(fixture)
	# Parented BEFORE `lattice` is read: the first read builds the tiles and the
	# cliff rule projects through their `global_position`.
	map = fixture
	if player_camera != null and "procedural_map_path" in player_camera:
		player_camera.procedural_map_path = player_camera.get_path_to(fixture)
	await super._ready()


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Deckhand",
		"pos_x": DECK.x, "pos_z": DECK.y, "pos_level": DECK.z,
		"hp": 200, "max_hp": 200,
		"pa": 10, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"move": 5, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x02,
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Idler",
		"pos_x": IDLER.x, "pos_z": IDLER.y, "pos_level": IDLER.z,
		"hp": 500, "max_hp": 500,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x05,
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		var g := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.MOVE, -1, TargetSelector.enemies())
		return GambitEncoder.encode_gambits([g])
	return [make_wait_gambit()]


## `place_on_tile` takes two grid axes and cannot say which of a column's cells
## it meant — the level is the one thing a transform cannot answer (ADR-0219
## dec. 6), so it is stated here after placement. `_build_battle_spec` reads
## `current_cell` straight afterwards, which is how the level reaches the packer.
func _create_units() -> void:
	await super._create_units()
	_seat(team0_units, get_team0_unit_configs())
	_seat(team1_units, get_team1_unit_configs())


func _seat(unit_list: Array, configs: Array) -> void:
	for i in range(unit_list.size()):
		var level: int = int(configs[i].get("pos_level", 0))
		var mc = unit_list[i].movement_component
		var cell: Vector3i = mc.current_cell
		mc.current_cell = Vector3i(cell.x, cell.y, level)
		var lat: Lattice = lattice
		var terrain = lat.terrain_at(mc.current_cell)
		if terrain == null:
			print("[FAIL] %s seated at %s, which the lattice does not mint" % [
				configs[i]["name"], mc.current_cell])


func _process(delta: float) -> void:
	# ⚠️ `CombatHost._process` IS THE TICK PUMP. Overriding it without calling
	# super leaves the battle configured, "started", and never stepped — the run
	# then burns its whole `--quit-after` budget and exits rc 0 with no verdict,
	# which is not a pass.
	# SAMPLED BEFORE THE PUMP, so the first sample is the SEAT rather than the
	# state after the first batch of ticks. `ticks_per_frame` is 4 here, so
	# sampling after `super._process` would have missed the deck entirely and
	# read the descent's second cell as the start.
	_sample()
	super._process(delta)
	_sample()


func _sample() -> void:
	if _done or not combat_active or gpu_state_reader == null:
		return
	var states = gpu_state_reader.get_all_unit_states()
	if states.is_empty():
		return
	var mover: Dictionary = states[0]
	var here := Vector3i(int(mover["pos_x"]), int(mover["pos_z"]), int(mover.get("level", 0)))
	if _start_level < 0:
		_start_level = here.z
		_start_height = int(mover.get("height", -1))
	if _samples.is_empty() or _samples[-1] != here:
		_samples.append(here)
	if here.z == 0 and _samples.size() > 1:
		_finish()


func on_victory(_winning_team: int) -> void:
	_finish()


func _on_loop_timed_out(tick: int) -> void:
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	var failed := 0

	print("\n=== BRIDGE DESCENT (%s, deck %s) ===" % [MAP_NAME, DECK])
	print("  route: %s" % str(_samples))

	# --- P4 -------------------------------------------------------------------
	# `U_HEIGHT` is packed from `lattice.terrain_at(cell)`, so a wrong LEVEL here
	# would show as the ground's 0. This is the packer's half of the two numbers
	# ADR-0224 opens with.
	if _start_level != DECK.z:
		print("  [x] P4: the unit started at level %d, not %d — it never reached the deck" % [
			_start_level, DECK.z])
		failed += 1
	if _start_height != DECK_HEIGHT:
		print("  [x] P4: U_HEIGHT is %d, expected the deck's %d (the column's ground is %d)" % [
			_start_height, DECK_HEIGHT, GROUND_HEIGHT_UNDER_DECK])
		failed += 1

	# --- P5 -------------------------------------------------------------------
	var descended := false
	for s in _samples:
		if s.z == 0:
			descended = true
			break
	if not descended:
		print("  [x] P5: the unit never left the deck — no sample reached level 0")
		failed += 1

	# No in-place level change: dec. 5 admits no fifth or sixth move, so a step
	# that held (x, z) and changed only the level would be a rule the mover
	# invented. Checked over the OBSERVED route rather than asserted of the
	# design, because the design is what is under test.
	var in_place := 0
	for i in range(1, _samples.size()):
		var a := _samples[i - 1]
		var b := _samples[i]
		if a.x == b.x and a.y == b.y and a.z != b.z:
			in_place += 1
			print("  [x] P5: step %d changed level in place: %s -> %s" % [i, a, b])
	failed += in_place

	if failed == 0:
		print("[PASS] the unit stood on the deck at h%d and walked down, %d steps, no in-place level change" % [
			DECK_HEIGHT, maxi(0, _samples.size() - 1)])
	else:
		print("[FAIL] GPUBridgeDescentTest: %d arm(s) failed" % failed)
	print("=== END RESULTS ===")
	get_tree().quit(1 if failed > 0 else 0)
