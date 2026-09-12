extends CombatHost

## GPU Combat Arena — production host (ADR-0018, C8).
##
## A production host that holds a [CombatLoop] (via the shared [CombatHost] base):
## it composes the scenario cast, places it on the scenario's own tiles, then hands the
## placed units to the loop via start_battle, wiring the loop's signals to its own
## concerns — death cues, the combat log, and the (non-quitting) end screen. It
## shares only the accessor MECHANICS with the test host (via CombatHost); the
## instrumentation vs production policy diverges sharply and stays per-host.
##
## Battle state (combat_loop / units / current_tick / _all_states / gpu_state_reader
## / managers / …), `_sync_loop_refs()`, `_is_unit_dead()`, `_process` (loop pump)
## live on [CombatHost]. A few GPUArena-subclass tests (GPUThrashTest /
## GPUTeleportTest / GPUItemFallthroughTest) read that state off this scene.
##
## Controls:
##   Enter - Open the unit under the tile cursor's Formation screen (ADR-0137)
##   Space - Toggle combat on/off (pause/resume)
##   Ctrl+R - Reset arena
##   F3 - Toggle debug overlay

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const CursorRig = ExMateriaBattlefield.CursorRig

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const TerrainCell = ExMateriaSchema.TerrainCell

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const DeploymentZoneDatabase = ExMateriaAlmanac.DeploymentZoneDatabase
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction
const Character = ExMateriaCatalogue.Character


## The scenario the arena boots into (ADR-0030). Its map is built once here —
## the ProceduralMap node has auto_build_on_ready = false in the .tscn, so the
## scenario (not a hardcoded MAP042) drives the first load. 9 = "Gariland Fight"
## on MAP022 — the FFT tutorial battle, flat 10x15 footprint matching the
## MapComposer MAP042 default the GPUCombatTestBase suite runs on, so
## GPUArena-derived tests (GPUThrashTest etc.) get a clean combat surface
## instead of the deep / cluttered Orbonne Monastery layout (MAP056).
@export var default_scenario_id: int = 9

## The Formation coordinator, by path — it carries no `class_name` (it is a scene script, not a
## global type), so both hosts that mount it reach it this way.
const FormationDetailTransitionScript = preload("res://src/ui3/formation/FormationDetailTransition.gd")

@onready var map: Node3D = $ProceduralMap
# The cursor NODE, by scene path — a scene-tree coupling, not a type reference
# (ADR-0196 dec. 2). Everything the scene READS off the cursor goes through
# `cursor_rig`, the published port (ADR-0206).
@onready var tile_cursor: Node3D = $TileCursor
var cursor_rig: CursorRig = null

# Host-owned config (the arena never times out and is not a regression test).
var max_ticks: int = 999999  # No timeout in the arena
var regression_logging: bool = false  # Not a test — disable regression logs

# --combat-auto-reset: how long the finished battle lingers (win/lose visible)
# before the arena reloads for the next run. Guard prevents double-scheduling.
const COMBAT_AUTO_RESET_DELAY_SEC: float = 3.0
var _auto_reset_armed: bool = false

var _debug_panels: Array = []
var _rng: RandomNumberGenerator


func _ready():
	max_ticks = 999999  # No timeout in the arena (a subclass test may set its own;
	#                     the arena overrides it back, matching the pre-C8 behavior).

	# The legacy `CombatUI` arrives inherited from the camera mount and is torn out
	# here, before anything else runs (ADR-0137's deferred demolition, this host's half).
	_demolish_legacy_combat_ui()

	# Debug logging defaults OFF (per CLAUDE.md). Toggle live via the F3 overlay's
	# Logging tab (Simulation / Iteration Debug). iteration_debug in particular is
	# very noisy here — it logs every UIChar glyph, animation opcode, and blocked
	# pathfinding tile. Re-enable here only for a focused session.
	#DebugConfig.simulation_debug_enabled = true
	#DebugConfig.iteration_debug_enabled = true

	# Handle "Run with Seed" button — auto-place and start, then reset flag
	if DebugConfig.run_with_seed:
		DebugConfig.run_with_seed = false
		DebugConfig.combat_autostart = true

	_rng = RandomNumberGenerator.new()
	if DebugConfig.combat_seed > 0:
		_rng.seed = DebugConfig.combat_seed
		DebugConfig.active_combat_seed = DebugConfig.combat_seed
		print("[GPUArena] Using fixed seed: %d" % DebugConfig.combat_seed)
	else:
		_rng.randomize()
		var generated_seed = _rng.seed
		DebugConfig.active_combat_seed = generated_seed
		print("[GPUArena] Generated seed: %d" % generated_seed)

	_rlog = RegressionLogger.new(get_test_name(), regression_logging)

	print("\n=== GPU COMBAT ARENA ===")
	print("Enter - Open the cursored unit's screen")
	print("Space - Toggle combat (pause/resume)")
	print("Ctrl+R - Reset arena")
	print("F3 - Toggle debug overlay")
	print("========================\n")

	await get_tree().process_frame
	await get_tree().process_frame

	# Load the boot scenario: builds its map (the ProceduralMap node has
	# auto_build_on_ready = false) and plays its battle music (ADR-0030). The
	# active scenario persists in DebugConfig so a picker choice survives a scene
	# reload (e.g. "Run with Seed"); -1 falls back to the scene default.
	if DebugConfig.active_scenario_id < 0:
		DebugConfig.active_scenario_id = default_scenario_id
	ScenarioLoader.apply_scenario(DebugConfig.active_scenario_id, map)

	# #589: hand the map's two outputs to the host systems that consume them.
	# Replay-then-connect, so a map the composer auto-built in ITS `_ready`
	# (children ready before parents) is covered by the replay and every later
	# `change_map` by the connect. See BattlefieldWiring.
	BattlefieldWiring.wire_map(map)
	# ADR-0192 dec. 3's clean fetch — one untyped step at the seam (`map` is
	# `$ProceduralMap`, which infers `Node`), `Lattice`-typed from here on.
	#
	# It lands in a LOCAL annotated HERE and is stored from there, rather than
	# straight into the host field. The field is declared on `CombatHost` and
	# receiver-type inference is per file, so a fetch landing directly in it reads as
	# "undeclared in this file" — the register's one stated blind spot (ADR-0192's
	# amendment, which measured exactly this line). One typed local is what makes the
	# claim checkable in the file that makes it.
	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		push_error("[GPUArena] Map has no lattice!")
		return

	# Seed the tile cursor now that the map exists (prefers (0,0), else first tile)
	# and hand the camera-follow + highlight wiring to the `CursorRig` port. GPU
	# regression tests inherit GPUArena.gd from bare scenes that omit the
	# TileCursor sibling — the null guard keeps combat starting without a cursor.
	if tile_cursor != null:
		cursor_rig = CursorRig.bind(self, tile_cursor, $PlayerCamera)
		# #589: the cursor's player-driven step is an `Audio` cue, and the cue name
		# is host vocabulary (`OpeningMenu` plays the same one). Wired by the root
		# that OWNS the node -- a cursor handed onward (FormationMapHost.bind_map)
		# is already wired by its owner.
		BattlefieldWiring.wire_cursor(cursor_rig)
		cursor_rig.seed_from_map(map, Vector2i(0, 0))
		_setup_formation_map_screen()

	_ensure_loop()

	# The CAST is built BEFORE the simulator, because it now SIZES the simulator.
	# `units_per_battle` splits the GPU battle at its midpoint and CombatLoop indexes
	# `team0 + team1` contiguously, so team0 must land exactly in [0, ups/2) — the same
	# arithmetic NavigatorMain does at its go-live. The retired roster cast was a fixed
	# 4v4, which is the only reason this ordering never mattered before (ADR-0180).
	await _create_units_for_strategy()
	combat_loop.units_per_battle = 2 * maxi(
		maxi(team0_units.size(), team1_units.size()), 1)
	if team1_units.size() > team0_units.size():
		push_warning("[GPUArena] team1(%d) > team0(%d) — GPU team split may mis-slot"
			% [team1_units.size(), team0_units.size()])

	combat_loop.setup_distance_field()
	combat_loop.setup_gpu_simulator()

	# ADR-0258 retired the deployment march, so there is no branch here any more:
	# the cast lands on the scenario's own tiles (the zone for the owned side, the
	# ENTD slot for everything else) and the battle boots on them.
	_place_units_at_defaults()
	_setup_debug_panels()
	_start_battle_from_roster()
	if DebugConfig.combat_autostart:
		combat_active = true
		_print_combat_state_dump()
		_ensure_heartbeat_timer()

	_setup_compass()

	# Scroll to the SIMULATION cell so the seed section is in view. The arena does
	# NOT force the dashboard open (#866): DebugOverlay._ready() already restores
	# UserSettings.debug_window.was_visible, so the window remembers — and the
	# unconditional show_overlay() that used to sit here overrode the preference
	# the user expressed by closing it last session. F3 opens it.
	DebugOverlay.switch_to_tab(DebugOverlay.Category.SIMULATION)

	DebugConfig.quit_requested.connect(_on_quit_requested)


# _process is inherited from CombatHost (it pumps the combat loop). The
# active-cursor highlight self-heal that used to live here moved into
# CursorController._process along with the rest of the cursor wiring.


func get_test_name() -> String:
	return "GPU Arena"


func _ensure_loop() -> void:
	if combat_loop:
		return
	combat_loop = CombatLoopClass.new()
	combat_loop.name = "CombatLoop"
	combat_loop.battle_name = get_test_name()
	combat_loop._rlog = _rlog
	combat_loop.max_ticks = max_ticks
	combat_loop.lattice = lattice
	# Phase 4.5: hand the loop the production PlayerCamera so cinematic spells
	# can take over the camera (mirrors EffectViewerScene's flow). Tests leave
	# this null and the cinematic still spawns, just without camera takeover.
	combat_loop.player_camera = $PlayerCamera
	combat_loop.map = map
	add_child(combat_loop)
	# Production connects only to the events it needs (death cue / combat log /
	# end-screen) — not a firehose. No quit on victory; no timeout (max_ticks huge).
	combat_loop.state_changed.connect(on_state_changed)
	combat_loop.hp_changed.connect(on_hp_changed)
	combat_loop.victory.connect(_on_loop_victory)

	# #211/#228 Phase 3: combat effect blend buckets fold in display space (not the scene's LINEAR
	# hardware-blend pass). The raw-RD GLSL driver was retired; the fold is now owned by the
	# CompositorAutopilot autoload (fork + Forward+), which auto-attaches EngineFoldCompositor to the
	# active camera for every scene — so no per-scene compositor wiring is needed here.


#region Cast composition (ADR-0180)

## Build the arena's cast from the battle it is ALREADY booting.
##
## The arena used to spawn four hand-invented blank Squires from `PartyRoster` and four
## from `EnemyRoster` beside a Gariland map it had already loaded — a second combat
## universe standing next to the real one. ADR-0180 deleted those two stores; the cast
## now comes from the same two places the story path's does:
##
##   player side — [CharacterCatalog]`.owned_units()`, established by folding the owned
##                 roster as it stands when Gariland boots (Ramza + the six Academy
##                 cadets ENTD 392 grants, derived, `own: true` — ADR-0216);
##   enemy side  — the scenario's ENTD record, partitioned by `team_color`.
##
## The composition itself is [ScenarioCast.compose] — this arena's own code, MOVED there
## when `GambitBattle` became the second host to boot from a `scenario_id` (ADR-0242).
## A host that copied it instead would be re-creating exactly the second combat universe
## ADR-0180 deleted. Units are spawned but NOT placed — placement is
## `_place_units_at_defaults`'s, unchanged.
func _create_units_for_strategy():
	var battle_cast: Dictionary = await ScenarioCast.compose(self, DebugConfig.active_scenario_id)
	team0_units = battle_cast["team0"]
	team1_units = battle_cast["team1"]
	# W7's stress fixture pads AFTER the compose, so `shipped_*` stays the size of the
	# cast ScenarioCast actually built and the padding is reported separately.
	var shipped_t0 := team0_units.size()
	var shipped_t1 := team1_units.size()
	await _pad_teams_for_stress()
	units = team0_units + team1_units
	var owned_count: int = (battle_cast["owned"] as Array).size()
	print("\n%d units created (awaiting placement): team0=%d (%d owned + %d ENTD-blue) team1=%d"
		% [units.size(), shipped_t0, owned_count,
			shipped_t0 - owned_count, shipped_t1])
	if team0_units.size() != shipped_t0 or team1_units.size() != shipped_t1:
		print("[GPUArena] STRESS cast: team0 %d->%d, team1 %d->%d (%d units total)"
			% [shipped_t0, team0_units.size(), shipped_t1, team1_units.size(),
				units.size()])


## Where a `--stress-units` clone stands, stashed at spawn. A SECOND meta rather than a
## reuse of [constant ENTD_TILE_META]: the owned-side filter in `_place_units_at_defaults`
## keys on "has no ENTD tile", so a clone carrying that meta would read as an ENTD unit
## to every future reader of it. Distinct name, same placement contract.
const STRESS_TILE_META := "stress_tile"


## Pad each team to `--stress-units=N` by cloning the cast the scenario already gave us.
##
## **This is a measurement lever, not a gameplay path** (W7). The shipped cast is 13 units
## and the heaviest frame it produces is 1.3 ms of a 6.94 ms budget — the fixture that
## found that cannot find where the budget BREAKS, because it never approaches it. This
## makes the one thing that scales, the unit count, the independent variable. It broke at
## 64: `docs/GPU-ARENA-PERF.md` → Round 26.
##
## Off unless asked: `N == 0` returns before touching anything, so every run without the
## flag is the same 13-unit cast the previous 25 rounds measured.
##
## Three things it has to get right, each of which silently produces a WRONG number:
##   • **The clone is deep.** `bind_for_combat` binds `character.progression` BY REFERENCE,
##     so two units sharing one Character share an HP pool — they would die together and
##     the fixture would decay at 2x the real rate. `Character.from_dict(to_dict())` mints
##     a fresh `UnitProgression`.
##   • **Every clone gets its own free ground tile.** Two units on one tile is not a state
##     the sim represents. The tiles come from `Battle`'s own placement policy
##     ([method PlacementPolicy.placement_cells]) minus what is already claimed.
##   • **Clones cluster on their team's centre.** A stress cast sprayed across the map
##     measures pathfinding to first contact, not combat. Nearest-free-to-the-anchor keeps
##     the engagement shape the shipped cast has.
##
## ⚠ Verify with the `[PERF]` line's `Units: n/m alive`, not this function's print — and
## read `m`, the SLOT count, which is what the sim allocated. The GPU sim clamps each side
## to `units_per_battle / 2` (`GPUBatchSimulator._upload_battle`), and `units_per_battle` is
## sized from these arrays one call later, so a unit spawned here is only SIMULATED if that
## sizing saw it. (The activity histogram beside `m` cannot answer this: it counts slots and
## has no `DEAD` bucket, so a corpse and an empty slot both read as an activity.)
func _pad_teams_for_stress() -> void:
	var target: int = DebugConfig.stress_units
	if target <= 0:
		return
	if lattice == null:
		push_warning("[GPUArena] --stress-units=%d ignored: no lattice" % target)
		return
	var claimed := _claimed_cells()
	var free_cells: Array = []
	for cell in PlacementPolicy.new(lattice).placement_cells():
		if not claimed.has(cell):
			free_cells.append(cell)
	# ONE clone at a time, alternating sides. Draining team0's whole request first
	# spends the shared tile pool on one side: at `--stress-units=64` the Gariland map
	# gave team0 all 64 and team1 only 47, which sizes `units_per_battle` to 128 and
	# leaves 17 slots permanently dead — a roster the sim carries but never fills.
	# Alternating makes a tile shortage degrade SYMMETRICALLY, so the two teams stay
	# equal and every slot the sim allocates holds a unit.
	while team0_units.size() < target or team1_units.size() < target:
		var before := team0_units.size() + team1_units.size()
		team0_units = await _pad_team(team0_units, mini(target, team0_units.size() + 1),
			UnitStats.Team.PLAYER, FacingDirection.NORTH, free_cells, "T0")
		team1_units = await _pad_team(team1_units, mini(target, team1_units.size() + 1),
			UnitStats.Team.ENEMY, FacingDirection.SOUTH, free_cells, "T1")
		if team0_units.size() + team1_units.size() == before:
			break  # the map is full on both sides; `_pad_team` has warned


## Clone `team` up to `target` units onto the nearest free cells. `free_cells` is consumed
## (both sides draw from one pool, so the two casts cannot collide).
func _pad_team(team: Array, target: int, side: UnitStats.Team, facing: int,
		free_cells: Array, label: String) -> Array:
	if team.is_empty() or team.size() >= target:
		return team
	var anchor := _team_anchor(team)
	free_cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return Vector2(a.x, a.y).distance_squared_to(anchor) \
			< Vector2(b.x, b.y).distance_squared_to(anchor))
	var made: Array = []
	while team.size() + made.size() < target:
		if free_cells.is_empty():
			push_warning("[GPUArena] stress %s: map ran out of free tiles at %d units"
				% [label, team.size() + made.size()])
			break
		var source = team[made.size() % team.size()].get_meta(UnitSpawn.CHARACTER_META)
		var clone := _clone_character(source, "stress-%s-%d" % [label, made.size()])
		# ScenarioCast owns the spawn seam since ADR-0242 — the same one the compose
		# above uses, so a stress clone is spawned exactly like a shipped unit.
		var spawned := await ScenarioCast.spawn_characters(self, [clone], side, facing,
			"  stress %s #%d" % [label, made.size()])
		if spawned.is_empty():
			push_warning("[GPUArena] stress %s: spawn failed at %d" % [label, made.size()])
			break
		spawned[0].set_meta(STRESS_TILE_META, free_cells.pop_front())
		made.append(spawned[0])
	return team + made


## A deep copy of `source` under a fresh slug.
##
## `to_dict()` carries progression, equipment and gambits but deliberately drops the
## identity keys (its own docstring says so), and `from_dict()` therefore also drops the
## two APPEARANCE-bearing ones. Carrying those across matters here: a clone of a unique
## that resolved as a generic would load a different sprite sheet and run different
## animation work than the unit it stands in for, which is the cost being measured.
## `special_name` is NOT carried — it is the story-NPC key `EntdBattle` filters
## non-combatants on, and a clone is not a story NPC.
func _clone_character(source, slug: String) -> Character:
	var clone := Character.from_dict(source.to_dict())
	clone.slug = slug
	clone.template_token = source.template_token
	clone.forms = source.forms.duplicate()
	clone.display_name = "%s+%s" % [source.display_name, slug.get_slice("-", 2)]
	return clone


## Every cell the shipped cast has already claimed: the ENTD units' own tiles, plus the
## deployment zone `_place_units_at_defaults` will drop the owned side onto.
func _claimed_cells() -> Dictionary:
	var out: Dictionary = {}
	for unit in team0_units + team1_units:
		if unit.has_meta(ENTD_TILE_META):
			out[unit.get_meta(ENTD_TILE_META)] = true
	for tile in DeploymentZoneDatabase.get_zone(
			_scenario_deployment_idx()).get("tiles", []):
		out[Vector3i(int(tile[0]), int(tile[1]), TerrainCell.GROUND_LEVEL)] = true
	return out


## Where a team stands, in grid `(x, z)` — the centroid its clones cluster on. ENTD units
## know their own tile; owned units do not yet have one, so their share of the deployment
## zone stands in for them (that is where `_place_units_at_defaults` is about to put them).
func _team_anchor(team: Array) -> Vector2:
	var cells: Array[Vector2] = []
	var unplaced := 0
	for unit in team:
		if unit.has_meta(ENTD_TILE_META):
			var c: Vector3i = unit.get_meta(ENTD_TILE_META)
			cells.append(Vector2(c.x, c.y))
		else:
			unplaced += 1
	var zone_tiles: Array = DeploymentZoneDatabase.get_zone(
		_scenario_deployment_idx()).get("tiles", [])
	for i in range(mini(unplaced, zone_tiles.size())):
		cells.append(Vector2(int(zone_tiles[i][0]), int(zone_tiles[i][1])))
	if cells.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for c in cells:
		sum += c
	return sum / cells.size()


## Where an ENTD-spawned unit stands per the ROM, stashed at spawn for the placement
## path below. One alias line keeps this file's spelling (ADR-0211 dec. 4); the
## stashing is [ScenarioCast]'s.
const ENTD_TILE_META := ScenarioCast.ENTD_TILE_META


func _place_units_at_defaults():
	"""Place the cast on the REAL tiles, not invented ones. Since ADR-0258 this is the
	arena's ONLY placement path.

	The owned side goes onto the scenario's first-squad deployment zone (the same
	[DeploymentPlan] assignment the navigator's deploy seam uses: list order, capped by
	the zone's `max_squad_size`); everything ENTD-spawned goes onto its own slot tile.
	Anything left over — an owned unit past the zone cap, a unit whose tile is missing —
	falls back to a spread beside the zone so it is at least on the map.
	"""
	var zone: Dictionary = DeploymentZoneDatabase.get_zone(_scenario_deployment_idx())
	var tiles: Array = zone.get("tiles", [])
	var cap := int(zone.get("max_squad_size", team0_units.size()))
	var owned_units_placed := 0
	if not tiles.is_empty():
		var owned: Array = team0_units.filter(
			func(u): return not u.has_meta(ENTD_TILE_META) \
				and not u.has_meta(STRESS_TILE_META))
		for p in DeploymentPlan.assign(owned, tiles, cap):
			var tile: Array = p["tile"]
			p["unit"].place_on_tile(int(tile[0]), int(tile[1]), map)
			p["unit"].visible = true
			owned_units_placed += 1
	else:
		push_warning("[GPUArena] deployment zone %d has no tiles — spreading the owned side"
			% _scenario_deployment_idx())

	var stragglers := 0
	var stress_placed := 0
	for team in [team0_units, team1_units]:
		for unit in team:
			if unit.visible:
				continue
			if unit.has_meta(ENTD_TILE_META):
				var t: Vector3i = unit.get_meta(ENTD_TILE_META)
				unit.place_on_tile(t.x, t.y, map, t.z)
			elif unit.has_meta(STRESS_TILE_META):
				# The `--stress-units` clones carry their own free ground cell, picked
				# at spawn from `Battle`'s placement policy — they never fall through to
				# the straggler spread below, which stacks everything on one row.
				var sc: Vector3i = unit.get_meta(STRESS_TILE_META)
				unit.place_on_tile(sc.x, sc.y, map, sc.z)
				stress_placed += 1
			else:
				unit.place_on_tile(3 + stragglers, 5, map)
				stragglers += 1
			unit.visible = true

	print("[GPUArena] Units placed: %d owned on deployment zone %d, %d on ENTD tiles, %d stress, %d spread"
		% [owned_units_placed, _scenario_deployment_idx(),
			units.size() - owned_units_placed - stress_placed - stragglers,
			stress_placed, stragglers])


## The deployment-zone index of the scenario the arena booted (Gariland: 256).
func _scenario_deployment_idx() -> int:
	return int(ScenarioDatabase.get_scenario(DebugConfig.active_scenario_id)
		.get("first_squad_deployment_idx", 0))


func _start_battle_from_roster():
	"""Compose the battle: hand the placed roster units to the loop. No GPU spec —
	the loop reads the live Unit nodes (set_battle_from_units)."""
	if not combat_loop:
		return

	var battle_seed = _rng.randi()
	combat_loop.start_battle(
		team0_units, team1_units, _build_encoded_gambits(),
		lattice, map, battle_seed)
	_sync_loop_refs()
	_setup_feedback_hud()

	if DebugConfig.gpu_debug_enabled:
		var states = gpu_state_reader.get_all_unit_states()
		print("[GPUArena] GPU battle configured with %d units" % units.size())
		for i in range(mini(states.size(), units.size())):
			var s = states[i]
			var us = units[i].unit_stats
			print("  %s: GPU hp=%d/%d mp=%d/%d | UnitStats hp=%d/%d mp=%d/%d speed=%d" % [
				units[i].name,
				s.get("hp", -1), s.get("max_hp", -1), s.get("mp", -1), s.get("max_mp", -1),
				us.current_hp, us.max_hp, us.current_mp, us.max_mp, us.atb_speed])


func _build_encoded_gambits() -> Array:
	"""Encode each unit's gambit list for the GPU (global index → encoded array).

	One line since ADR-0242: this loop was hand-mirrored on `NavigatorMain` and about to be
	mirrored a third time by `GambitBattle`, so it moved to [GambitEncoder.encode_for_units]
	where the safety-net rule it carries (ADR-0048) has one home."""
	return GambitEncoder.encode_for_units(units, "GPUArena")

#endregion


#region Input

func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		# A camera TAKEOVER means something else is driving the view — the map-hosted Formation
		# screen (ADR-0137), or a cinematic. Neither wants the battle resumed underneath it: Space
		# would unpause a sim the takeover paused, and the exit would then "unpause" one that is
		# already running. ADR-0137 calls this out as correct beyond its own feature — the cinematic
		# case is the same bug and was live before it. Every other map input that matters is already
		# gated on `camera_mode == CURSOR`; this closes the last one that was not.
		if _camera_is_taken_over():
			return
		if event.keycode == KEY_R and event.ctrl_pressed:
			_reset_arena()
			return
		# START and PAUSE are two keys now, not one (ADR-0137 Amendment 2). They were one because
		# `_toggle_combat` treated them as one flag, but they are not the same KIND of thing:
		# starting the battle is a ONE-WAY phase exit (NavigatorMain says it outright —
		# "'Starting the battle' is mechanically just leaving Deployment"), while pausing is a
		# repeatable toggle. One key carrying both is what forced Tab to mean three transitions
		# there and left nothing for the map cursor.
		#
		# Both stay INSIDE the takeover guard above. Amendment 1 §7 put that guard there for
		# exactly these two keys: a cinematic or the Formation screen has already paused the sim,
		# and resuming it underneath them is the bug that guard closed.
		if event.is_action_pressed("battle_start"):
			_start_combat()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("battle_pause"):
			_toggle_pause()
			get_viewport().set_input_as_handled()
			return
	# Enter and Tab are NOT handled here. They reach their meaning through TileCursor's
	# `cursor_confirmed` / `cursor_inspected`, so this scene decides what ACTING and
	# INSPECTING mean rather than what a keycode means.


## The Formation screen re-hosted over this battlefield (ADR-0137) — mounted under the map camera,
## the same coordinator the out-of-battle roster screen uses, in its MAP host mode.
var _formation_map_screen: Node3D = null


## Mount the map-hosted Formation screen. The cursor states the event; deciding what ACTING
## means is this scene's job, and since ADR-0258 it has exactly ONE answer: ○ on a unit opens
## that unit's screen with its action menu.
##
## `can_open` is unconditionally true. It used to be the exact negation of this scene's own
## gate, because the deployment march claimed ○ for itself while it ran — two listeners on one
## signal, kept a DISPATCH rather than a race by sharing one predicate (ADR-0137 Amendment 2).
## With the march retired there is no second claimant and no predicate to share, so the second
## listener is gone rather than left asserting false forever.
##
## INSPECT (△/Tab) is not routed here at all. The host listens to `cursor_inspected` itself and
## never gates it: looking at a unit has no host-specific reason to be refused, so there is nothing
## for this scene to decide.
func _setup_formation_map_screen() -> void:
	# ADR-0258: the march was the only reason this scene ever refused a confirm, so
	# `can_open` is now unconditionally true — ○ on the map always reaches the screen.
	_formation_map_screen = FormationDetailTransitionScript.mount_over_map(
		$PlayerCamera, cursor_rig, _unit_at_grid,
		_set_screen_pause,
		func() -> bool: return true)
	# HOST-side panel mount (#1267). `mount_over_map` returns null when the camera has no
	# `FocusPoint/Camera`, and this site never guarded that — the panel call is the first
	# thing here that would dereference it, so the guard comes in with it.
	if _formation_map_screen != null:
		FormationDebugPanels.register_formation_panels(_formation_map_screen.formation())


## Which unit is standing on `grid_pos` — this scene's own answer, handed to the map host so the
## screen never has to know how a battlefield stores its units.
## The cursor names a COLUMN (`Vector2i`), so this asks the column question: a unit on
## either cell of `grid_pos` answers. Cycling the cursor between a column's levels is
## deferred (#795); until it lands there is no way for the cursor to mean the upper one.
func _unit_at_grid(grid_pos: Vector2i):
	for unit in units:
		if unit == null or not is_instance_valid(unit) or unit.is_dead:
			continue
		var cell: Vector3i = unit.get_current_cell()
		if Vector2i(cell.x, cell.y) == grid_pos:
			return unit
	return null


## What the screen was interrupting, so closing it can put that back. Captured on open rather than
## assumed on close: see `_set_screen_pause`.
var _combat_active_before_screen := false


## The screen's pause hook. RESTORES the prior state instead of forcing `combat_active = true` on
## close — which is what it used to do, and which was harmless only because the screen could not be
## opened before the battle started. Amendment 2 made it openable before `start_battle`, and the
## old version would then have STARTED the battle the moment you closed the screen: a fight
## beginning because you looked at a unit. The same bug applies to opening it while already paused.
func _set_screen_pause(paused: bool) -> void:
	if paused:
		_combat_active_before_screen = combat_active
		combat_active = false
	else:
		combat_active = _combat_active_before_screen


## True while a driver other than the tile cursor owns the camera. Null-safe: GPU regression tests
## inherit this script from bare scenes with no PlayerCamera sibling.
func _camera_is_taken_over() -> bool:
	var cam := get_node_or_null("PlayerCamera")
	if cam == null or not ("camera_mode" in cam):
		return false
	return cam.camera_mode != cam.CameraMode.CURSOR


func _on_run_with_seed():
	DebugConfig.run_with_seed = true
	_reset_arena()


func _reset_arena():
	if DebugConfig.run_with_seed_requested.is_connected(_on_run_with_seed):
		DebugConfig.run_with_seed_requested.disconnect(_on_run_with_seed)
	for panel in _debug_panels:
		DebugOverlay.unregister_panel(panel)
	_debug_panels.clear()
	get_tree().reload_current_scene()


## Space — START the battle. One-way and idempotent: it arms the heartbeat and dumps the unit state,
## neither of which a resume should redo, so pressing it on a running battle is an accepted no-op
## rather than a pause. Pausing is `_toggle_pause`, on its own key.
func _start_combat():
	if combat_active:
		return
	combat_active = true
	print("\n[Combat] STARTED at tick %d" % current_tick)
	_print_combat_state_dump()
	_ensure_heartbeat_timer()


## Esc — PAUSE or resume. The bare flag flip, repeatable, with none of START's one-time arming. Does
## nothing before the battle has started: there is no sim to freeze, and reporting a pause the player
## cannot see is how the last round of this bug got written.
func _toggle_pause():
	if not combat_active and current_tick == 0:
		print("[Combat] not started yet — Space starts the battle")
		return
	combat_active = not combat_active
	print("\n[Combat] %s at tick %d" % ["RESUMED" if combat_active else "PAUSED", current_tick])


func _print_combat_state_dump():
	print("[Combat] === unit state ===")
	var states = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
	for i in range(units.size()):
		var u = units[i]
		var name = u.name if is_instance_valid(u) else "<dead>"
		var team = "T0" if i < team0_units.size() else "T1"
		var s: Dictionary = states[i] if i < states.size() else {}
		var gambit_count = 0
		if is_instance_valid(u) and u.gambit_list:
			for g in u.gambit_list.gambits:
				if not g.is_empty():
					gambit_count += 1
		print("  [%d] %s %s  HP=%d/%d  MP=%d/%d  pos=(%d,%d)  gambits=%d" % [
			i, team, name,
			s.get("hp", -1), s.get("max_hp", -1),
			s.get("mp", -1), s.get("max_mp", -1),
			s.get("pos_x", -1), s.get("pos_z", -1),
			gambit_count])
	print("[Combat] ==================")


var _heartbeat_timer: Timer = null

func _ensure_heartbeat_timer():
	if _heartbeat_timer and is_instance_valid(_heartbeat_timer):
		return
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = 1.0
	_heartbeat_timer.autostart = true
	_heartbeat_timer.timeout.connect(_print_combat_heartbeat)
	add_child(_heartbeat_timer)


func _print_combat_heartbeat():
	if not combat_active:
		return
	if not gpu_state_reader:
		print("[Heartbeat] tick=%d combat_active=true but gpu_state_reader=null" % current_tick)
		return
	var states = gpu_state_reader.get_all_unit_states()
	var t0_alive = 0
	var t1_alive = 0
	var hp_parts: Array = []
	for i in range(states.size()):
		var s: Dictionary = states[i]
		var alive: bool = s.get("hp", 0) > 0
		if i < team0_units.size():
			if alive: t0_alive += 1
		else:
			if alive: t1_alive += 1
		var name = units[i].name if i < units.size() and is_instance_valid(units[i]) else "?"
		hp_parts.append("%s=%d" % [name, s.get("hp", -1)])
	print("[Heartbeat T:%d] T0=%d/%d T1=%d/%d | %s" % [
		current_tick, t0_alive, team0_units.size(),
		t1_alive, team1_units.size(),
		" ".join(hp_parts)])

#endregion


#region Victory (don't quit)

func _on_loop_victory(winner: int, team0_alive: int, team1_alive: int) -> void:
	# The loop already set victory_achieved / combat_active=false and applied
	# deaths; the arena just reports and keeps the scene alive.
	if winner == 0:
		print("\n[Combat] VICTORY: Player team wins! (%d remaining)" % team0_alive)
	elif winner == 1:
		print("\n[Combat] DEFEAT: Enemy team wins! (%d remaining)" % team1_alive)
	else:
		print("\n[Combat] DRAW: Both teams eliminated!")

	# --combat-auto-reset: restart the battle after a brief pause so a continuous
	# run loops without manual Ctrl+R (DebugConfig.combat_auto_reset, set by the
	# CLI flag). _armed guards against a double schedule; the inside-tree recheck
	# guards against the scene being torn down during the wait.
	if DebugConfig.combat_auto_reset and not _auto_reset_armed:
		_auto_reset_armed = true
		print("[Combat] auto-reset in %.0fs..." % COMBAT_AUTO_RESET_DELAY_SEC)
		await get_tree().create_timer(COMBAT_AUTO_RESET_DELAY_SEC).timeout
		if is_inside_tree():
			_reset_arena()

#endregion


#region UI & Debug Panels

## The OLD combat UI is GONE from this battlefield — ADR-0137's deferred demolition, this host's half.
##
## ADR-0137 decided the map host REPLACES `UICombatManager` rather than joining it, and deferred the
## demolition because ripping the node out takes the roster bars and field-inspect with it.
## Amendment 2 then shipped `visible = false`, which is not the same thing: the whole subtree was
## still BUILT, readied, processed and carried on every frame of every arena run — a UI nobody could
## see and nobody could reach, whose only remaining effect was cost.
##
## Nothing here needs a replacement. Everything the node fed is answered by the map host
## ([FormationDetailTransition] in its [FormationMapHost] mode, mounted by
## `_setup_formation_map_screen`): hover gives the vitals/nameplate pair the roster bars gave and
## field-inspect duplicated, and ○/Enter and △/Tab give the whole Status screen the DetailLayer
## menus gave. (The legacy teleport placement path the portraits clicked for is gone outright —
## ADR-0258 retired it with the rest of the strategy phase.)
##
## 🔴 ONE THING GOES DARK WITH IT AND HAS NO NEW HOME: the gambit surface. `UIGambitDisplay` (the
## DetailLayer readout) and `UIGambitEditor` (the ModalLayer editor) were the only UI in the tree
## that could show or edit a unit's [GambitList], and the map host has no gambit section yet. They
## have been unreachable since Amendment 2 hid their host, so this deletes nothing a player could
## reach today — but it does close the last door, and re-opening it on the new screen is the
## follow-on job.
##
## 🔴 SCOPED TO THIS HOST. The node arrives INHERITED from `assets/scenes/CombatCamera.tscn`, which
## 108 scenes instance and `GPUCombatTestBase.gd` binds by literal path, so it cannot be deleted
## from the arena's own `.tscn` — a child of an instanced scene is not removable per-consumer. The
## global demolition (the node in the camera mount, `CombatUI.tscn`, `UICombatManager`, and
## `CombatUITest`'s harness) is still the separate job the ADR scoped. One item left that list
## rather than being demolished: `RosterViewDebugPanel` was deleted by #1070, having never been
## constructed anywhere.
## This frees the arena's copy and nothing else's.
func _demolish_legacy_combat_ui() -> void:
	var legacy := get_node_or_null("PlayerCamera/FocusPoint/Camera/CombatUI")
	if legacy == null:
		return
	legacy.get_parent().remove_child(legacy)
	legacy.queue_free()
	print("[UI] legacy CombatUI freed — the map host owns this battlefield's UI (ADR-0137)")


# Over-unit feedback billboards (ADR-0063, #89/#90): floating damage/heal numbers
# and status/charge bubbles. Observation-only — the manager consumes the loop's
# GPU signals (hp_changed / state_changed) and each unit's snapshot status; it
# writes no battle state. Parented under the loop so its map-anchored numbers
# ride the same Node3D space and the ADR-0037 combat_visuals freeze.
var _feedback_hud: FeedbackHudManager

func _setup_feedback_hud() -> void:
	# The body moved onto `FeedbackHudManager.mount` so the three hosts share one
	# implementation and the mounts grep as one census. The idempotence guard went with it,
	# and got better on the way: it asks the LOOP whether it already carries a hud, which is
	# the question a host that frees its loop per battle actually needs answered.
	_feedback_hud = FeedbackHudManager.mount(combat_loop)


func _setup_debug_panels():
	# The whole list moved to `CombatPanelCatalog` (one mount shared with `GambitBattle`).
	# It was twenty named blocks here and one over there, and nothing but hand-maintenance
	# kept the two in step — which it did not: the gambit host shipped with a boot banner
	# advertising F3 and no panels behind it.
	#
	# Note what did NOT move with it. The seed hookup below is this host's — `_on_run_with_seed`
	# reloads THIS arena — so it stays at the mount that needs it rather than becoming a
	# catalogue concern with a host callback threaded through it.
	#
	# NO `VitalsLayoutDebugPanel` and NO roster-view panel, then or now. Both were views
	# onto the legacy `CombatUI` this host frees (`_demolish_legacy_combat_ui`): the roster
	# panel tuned `UICombatManager`'s two roster bars, and the vitals panel tuned a
	# `_field_inspect_window` mounted by a `_setup_field_inspect()` NOTHING EVER CALLED — so
	# that arm has been dead, not merely hidden, since before ADR-0137 Amendment 2. The vitals
	# layout still has a live panel on the screen that owns it (`FormationScene`, DESIGNER).
	# The roster panel's file is GONE as of #1070 — `RosterViewDebugPanel` declared a
	# `class_name`, was registered by no catalogue and constructed by nothing, and its knobs
	# are unaffected because `UICombatManager` owns them (ADR-0068 decision 12).
	DebugConfig.run_with_seed_requested.connect(_on_run_with_seed)
	CombatPanelCatalog.mount(self, _debug_panels)

#endregion


## Screen-space compass in the top-right corner that tracks the live camera so
## world N/E/S/W stay legible while the isometric arena camera pans/rotates.
## Mirrors ScenarioPlayerScene._setup_compass — the same CompassOverlay the
## scenario player uses. See `CompassOverlay`.
func _setup_compass() -> void:
	var cam := get_node_or_null("PlayerCamera/FocusPoint/Camera") as Camera3D
	if cam == null:
		push_warning("[GPUArena] no Camera under PlayerCamera; compass unwired")
		return
	var layer := CanvasLayer.new()
	layer.name = "CompassLayer"
	layer.layer = 50
	add_child(layer)
	var compass := CompassOverlay.new()
	compass.name = "CompassOverlay"
	compass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(compass)
	compass.setup(cam)


func _on_quit_requested():
	if not victory_achieved:
		DebugConfig.record_error("[NO VICTORY] Combat did not conclude before timeout")


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING:
		if DebugConfig.iteration_debug_enabled:
			print("  -> %s moving toward target" % units[unit_idx].name)
	elif new_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
		if DebugConfig.iteration_debug_enabled:
			print("  -> %s charging ability" % units[unit_idx].name)


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	# Per-hit combat log — gated (default OFF; toggle Simulation in the F3 Logging
	# tab). Fires on every damage/heal tick and floods the console during combat.
	if not DebugConfig.simulation_debug_enabled:
		return
	if delta < 0:
		print("  -> %s hit for %d! HP=%d" % [units[unit_idx].name, abs(delta), new_hp])
	elif delta > 0:
		print("  -> %s healed for %d! HP=%d" % [units[unit_idx].name, delta, new_hp])
