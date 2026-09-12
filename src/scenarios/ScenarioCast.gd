class_name ScenarioCast
extends RefCounted

## The CAST of a scenario battle: every [Unit] that will fight, spawned and UNPLACED.
##
## One integer in, two teams out. A `scenario_id` names an ENTD record and an owned
## roster, and this composes them the way ADR-0180 settled: team0 = the player's owned
## units ∪ the ENTD's blue slots (Delita fights beside you at Gariland), team1 = the
## ENTD's non-blue slots. Placement is NOT here — the caller decides where the cast
## stands, which is the whole difference between the arena's strategy phase, its
## no-strategy default placement, and `GambitBattle`'s deployment assignment.
##
## Extracted from `GPUArena` when `GambitBattle` arrived (ADR-0242). It is the same
## code, moved: the arena had the only copy, and a second host copying it would rebuild
## what its own docstring calls "a second combat universe standing next to the real one"
## — the thing ADR-0180 retired the rosters to delete.
## [UnitSpawn] is the ONE seam that mints a `Unit` from a `Character`; this is the one
## seam that decides WHICH characters a scenario mints, and it sits directly above it.
##
## Deliberately NOT the navigator's spawn path. `NavigatorMain` composes the same two
## sides through the same [EntdBattle] calls but its per-unit tail genuinely disagrees
## (it stamps `special_name` from the active Form, carries HP across the walk, and
## hands the clock to SCENARIO until `_go_live`) — the tail [UnitSpawn]'s own docstring
## warns against swallowing. What is shared is already shared, in `EntdBattle`.

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's. One alias line per file keeps the use sites below spelled the way they
## were in the arena (ADR-0211 dec. 4).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase

const FacingDirection = ExMateriaSchema.Facing.Direction
const ClockOwner = ExMateriaSchema.ClockOwner.Kind
const CatalogueReplay = ExMateriaCatalogue.CatalogueReplay
const Character = ExMateriaCatalogue.Character

## Where an ENTD-spawned unit stands per the ROM, stashed at spawn.
##
## It is also the CAST's own answer to "is this unit the player's?": an owned unit
## carries no authored tile, because nothing in the ROM says where it stands — that
## is the question deployment exists to answer.
const ENTD_TILE_META := "entd_tile"


## Compose a scenario's two combat sides, spawned and unplaced.
##
## Returns `{"team0": [Unit], "team1": [Unit], "owned": [Unit]}`. `owned` is the
## player's own units — a SUBSET of team0, held out separately because it is the side
## a host may place freely; team0's remainder are the ENTD's blue slots, which stand
## where the ROM says they stand.
##
## `host` is the node the units are parented to and whose tree the spawn awaits on.
## Async: each `Unit` needs a frame between `add_child` and `bind_for_combat`.
static func compose(host: Node, scenario_id: int) -> Dictionary:
	seed_owned_roster()
	var owned_characters: Array = CharacterCatalog.owned_units()
	var slots: Array = EntdBattle.combatant_slots(
		EntdBattle.record(str(entd_idx_of(scenario_id))))

	var owned := await spawn_characters(host, owned_characters,
		UnitStats.Team.PLAYER, FacingDirection.NORTH, "OWNED")
	# Spawn every ENTD slot ONCE, keyed by its unit id, then let compose_teams own the
	# partition + ordering (a slot's side decides which team it binds to, so the spawn
	# has to know its team before the compose does — hence spawn-then-look-up rather
	# than spawning inside the transform).
	var by_uid := await _spawn_entd_slots(host, slots, scenario_id)
	var teams := EntdBattle.compose_teams(owned, slots,
		func(ss: Array) -> Array: return _units_for_slots(ss, by_uid),
		func(ss: Array) -> Array: return _units_for_slots(ss, by_uid))

	return {
		"team0": teams["team0"],
		"team1": teams["team1"],
		"owned": owned,
	}


## Fold the pre-Gariland owned roster into the catalogue so `owned_units()` is non-empty.
##
## `owned_units()` is established by folding a [MutationScript] through
## [CatalogueReplay], and only [NavigatorRunner] folds today — so without this a
## scenario-booted host's team0 would be empty. This is the one genuinely new piece of
## wiring ADR-0180 asks for, and it is what REPLACED `create_starter_roster()`: four
## hand-invented blank Squires give way to the roster the ROM's own ENTD join flags
## derive (ADR-0216).
##
## Idempotent, and it never overwrites: a host that already has an overlay (a re-entry,
## or a test that seeded its own cast) keeps it.
static func seed_owned_roster() -> void:
	if not CharacterCatalog.owned_units().is_empty():
		return
	CatalogueReplay.apply_action(
		{"mutations": GarilandMutationScript.owned_seed_deltas()}, CharacterCatalog)


## The ENTD record index of a scenario — the same record its map and music came from.
static func entd_idx_of(scenario_id: int) -> int:
	return int(ScenarioDatabase.get_scenario(scenario_id).get("entd_idx", 0))


## Spawn one combat-ready [Unit] per [Character], unplaced and hidden. Goes through
## [UnitSpawn], the ONE spawn seam — the same one the navigator's deploy path uses.
static func spawn_characters(host: Node, characters: Array, team: UnitStats.Team,
		facing: int, label: String) -> Array:
	var spawned: Array = []
	print("%s:" % label)
	for character in characters:
		var unit := UnitSpawn.build(character)
		if unit == null:
			continue
		# force_readable_name: the seeded generics are NAMED FOR THEIR JOB, so a squad of
		# 2 Squires + 2 Chemists collides on `name` and Godot's fast path renames the
		# duplicates `@Node3D@6243` — which is what the deployment prompt then prints.
		# The retired roster's four hand-invented names never collided, so this only
		# surfaced when the cast became the real one. Identity is the `character_slug`
		# meta either way; `name` is display, and display has to stay readable.
		host.add_child(unit, true)
		await host.get_tree().process_frame
		UnitSpawn.bind_for_combat(unit, character, team)
		# A scenario boot is a fresh fixture fight: everyone starts topped up. (The story
		# path deliberately does not — it carries HP across a walk.)
		unit.unit_stats.current_hp = unit.unit_stats.max_hp
		unit.unit_stats.current_mp = unit.unit_stats.max_mp

		unit.facing_direction = facing
		unit.visible = false  # Hidden until placed

		# Read the job off the unit's just-bound progression (bind_for_combat bound
		# character.progression by reference) rather than re-resolving the Character.
		var job_name = JobDatabase.get_job(unit.unit_progression.current_job_id).get("name", "Unknown")
		print("  %s [%s Lv%d]" % [unit.name, job_name, unit.level])

		# Enable tick-based animation (the loop wires the animation signals in
		# start_battle — it drives the units). All six playbacks ride the GPU
		# tick (ADR-0037) so Unit needs no per-_process pause check — pause
		# halts CombatLoop.tick, which halts every playback in lockstep.
		# COMBAT-owned from boot (ADR-0083): no VM here, so no double-pump risk.
		unit.clock_owner = ClockOwner.COMBAT
		spawned.append(unit)
	return spawned


## Spawn every ENTD slot as a combat-ready Unit, returning `{unit_id: Unit}`. The slot's
## `team_color` decides its side ([EntdBattle.team_of]) and therefore what it binds to;
## identity comes from [Character.from_entd_slot], which is the same construction the
## navigator falls back to for an unbound slot. Also stashes the slot's own tile in
## [constant ENTD_TILE_META] so a host can stand each unit where the ROM says it stands.
static func _spawn_entd_slots(host: Node, slots: Array, scenario_id: int) -> Dictionary:
	var by_uid: Dictionary = {}
	print("ENTD %d:" % entd_idx_of(scenario_id))
	# The ceiling an ENTD level sentinel scales to is a property of the RECORD, not of
	# one slot (godot-learning ADR-0289, #1179) — derive it once for the whole cast.
	var ceiling := Character.level_ceiling_for_slots(slots)
	for slot in slots:
		var character = Character.from_entd_slot(slot, null, ceiling)
		var team: UnitStats.Team = UnitStats.Team.PLAYER \
			if EntdBattle.team_of(int(slot.get("team_color", 0))) == 0 \
			else UnitStats.Team.ENEMY
		var facing: int = FacingDirection.SOUTH \
			if team == UnitStats.Team.ENEMY \
			else FacingDirection.NORTH
		var made := await spawn_characters(host, [character], team, facing,
			"  slot uid 0x%02X (%s)" % [int(slot.get("unit_id", 0xFF)),
				str(slot.get("team_color_name", "?"))])
		if made.is_empty():
			continue
		var unit = made[0]
		# `upper_level` is the ENTD's own terrain level and nothing read it before
		# ADR-0219 — a fourth loss site beside the three the ADR names. The meta is a
		# CELL now, so an enemy the ROM stands on a bridge is stood on the bridge.
		unit.set_meta(ENTD_TILE_META, Vector3i(int(slot.get("x", 0)),
			int(slot.get("y", 0)), int(slot.get("upper_level", 0))))
		by_uid[int(slot.get("unit_id", 0xFF))] = unit
	return by_uid


## The spawned Units for `slots`, in slot order — the lookup half of the spawn-then-compose
## split. A slot with no spawned unit drops (it cannot fight).
static func _units_for_slots(slots: Array, by_uid: Dictionary) -> Array:
	var out: Array = []
	for slot in slots:
		var unit = by_uid.get(int(slot.get("unit_id", 0xFF)))
		if unit != null and is_instance_valid(unit):
			out.append(unit)
	return out
