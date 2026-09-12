class_name GambitScenarioBoot
extends RefCounted

## Boot one gambit SCENARIO DICT — spawn its units, encode its gambits, build its GPU
## battle spec. Extracted from [GambitScenarioRunner] so the live arm (ADR-0275 dec. 17)
## replays a fixture through THE SAME CODE the 84-fixture suite boots it with.
##
## === WHY THIS IS SHARED RATHER THAN COPIED =================================================
##
## ADR-0275 dec. 17 gives the lab read-only replay of the existing fixtures, and dec. 24
## makes the acceptance *"the lab EXPLAINS the existing XFAILs"*. A trace is only an
## explanation of an XFAIL if it is a trace of THAT battle: a second spawn path that
## defaults one stat differently, or seeds status a tick later, produces a run that looks
## like the fixture and is not it, and every conclusion drawn from it is unattributable.
## Duplicating ~120 lines here would have made that drift invisible and permanent.
##
## The rejected alternatives were a MODE on the runner (ADR-0275 dec. 14 — 84 fixtures read
## behaviour off it) and having the lab subclass the runner (it would inherit a `_ready`
## that runs all 84). Sharing the three pure-ish steps is the seam that costs neither.
##
## === THE THREE STEPS, AND WHAT EACH OWNS ===================================================
##
## [method spawn_unit] builds the scene-side [code]Unit[/code] — sprite, tile, facing,
## progression, the four HP/MP scalars, the COMBAT clock owner. [method encode_units] runs
## the authored [code]Gambit[/code] objects through [GambitEncoder] (real domain objects, no
## flat-dict shortcut — that is the editor->encoder path ADR-0275 dec. 20 keeps in the loop)
## and counts encoder SKIPS. [method build_battle_spec] builds the GPU-side config, which is
## a DIFFERENT shape from the scene-side unit and deliberately so.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias line per file
# keeps every use site's spelling, and makes a grep for the façade a complete census of
# host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice
const TerrainCell = ExMateriaSchema.TerrainCell
const FacingDirection = ExMateriaSchema.Facing.Direction
const ClockOwner = ExMateriaSchema.ClockOwner.Kind
const UnitProgression = ExMateriaAlmanac.UnitProgression

const UNIT_SCENE := "res://assets/scenes/Unit.tscn"

const SCENARIO_DIR := "res://tests/gambit_scenarios"


## Every scenario dict in [code]tests/gambit_scenarios/[/code], in directory order.
## Each `scenarios_*.gd` exposes a static `scenarios()` returning an Array of dicts.
##
## The 84 fixtures are the corpus BOTH arms read: the suite runs them for a verdict, the
## live arm replays one read-only (ADR-0275 dec. 17). One walk, so "the fixture set" cannot
## mean two different things depending on which arm you asked.
static func load_scenarios() -> Array:
	var out: Array = []
	var dir := DirAccess.open(SCENARIO_DIR)
	if not dir:
		push_error("[GambitScenarioBoot] cannot open %s" % SCENARIO_DIR)
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".gd") and name.begins_with("scenarios_"):
			var path := "%s/%s" % [SCENARIO_DIR, name]
			var script: Script = load(path)
			if script and script.has_method("scenarios"):
				for sc in script.scenarios():
					out.append(sc)
		name = dir.get_next()
	return out


## Spawn one scenario unit as a child of [param host], placed on [param map].
## [param fallback_index] only names the node when the cfg carries no `name`.
static func spawn_unit(host: Node, map: Node3D, cfg: Dictionary, fallback_index: int) -> Node:
	var unit_scene: PackedScene = load(UNIT_SCENE)
	var unit = unit_scene.instantiate()
	unit.name = cfg.get("name", "Unit%d" % fallback_index)
	host.add_child(unit)
	await host.get_tree().process_frame
	# 🔴 `body_sprite_id: 0` IS "UNSET", NOT A SPRITE, AND APPLYING IT MAKES THE UNIT INVISIBLE.
	# The texture set is 1-based — `assets/sprites/textures/` starts at `01.tga` and there is
	# no `00.tga` — so id 0 reaches `SpriteLayerManager` as a miss, which logs an ERROR and
	# binds the magenta-checker fallback. `Unit.body_sprite_id` already defaults to `0x01`, a
	# real texture, so the fix is to LEAVE THE DEFAULT ALONE rather than to invent one here.
	#
	# ⚠️ THIS IS 130 OF THE 184 UNIT DEFINITIONS in `tests/gambit_scenarios/` — 54 set 104 and
	# every other one sets 0 — so before this guard the majority of the corpus rendered as a
	# missing sprite in any scene that draws it. The gambit fixtures assert on GPU behaviour,
	# where the sprite id is inert, which is why nothing caught it: it is only visible to a
	# human watching the lab, and "one of the units doesn't render" is how it was reported.
	if cfg.has("body_sprite_id") and int(cfg["body_sprite_id"]) > 0:
		unit.body_sprite_id = cfg["body_sprite_id"]
	var tile_xz: Array = cfg.get("tile", [0, 0])
	unit.place_on_tile(int(tile_xz[0]), int(tile_xz[1]), map)
	unit.facing_direction = FacingDirection.NORTH if cfg.get("team", 0) == 0 else FacingDirection.SOUTH

	var team_enum: int = UnitStats.Team.PLAYER if cfg.get("team", 0) == 0 else UnitStats.Team.ENEMY
	var job_id: String = cfg.get("job", "")
	if job_id != "":
		var base_stat: int = UnitProgression.BaseStatType.MALE
		unit.initialize_with_progression(base_stat, job_id, team_enum)
	else:
		var progression = UnitProgression.new()
		progression.initialize(progression.base_stat_type, progression.current_job_id)
		unit.unit_progression = progression
		unit.unit_stats.team = team_enum

	unit.unit_stats.max_hp = cfg.get("max_hp", 100)
	unit.unit_stats.current_hp = cfg.get("hp", cfg.get("max_hp", 100))
	unit.unit_stats.max_mp = cfg.get("max_mp", 50)
	unit.unit_stats.current_mp = cfg.get("mp", cfg.get("max_mp", 50))
	if cfg.has("weapon_id") and unit.unit_progression:
		unit.unit_progression.equip_item(UnitProgression.EquipSlot.RIGHT_HAND, cfg["weapon_id"])

	# Match the GPU test base's tick-based playback: every playback advances on the GPU
	# tick so visuals can't drift between scenarios (COMBAT-owned, ADR-0083).
	unit.clock_owner = ClockOwner.COMBAT
	return unit


## Encode every unit's authored gambits. Returns `{gambits: Array, skips: int}`.
##
## A "skip" is an AUTHORED gambit that encoded to null (ADR-0023 faithful-or-explicit).
## Only the authored region is inspected: the encoder pads unused authored slots with null
## and appends the safety net (ADR-0048), and neither of those is an encoder skip.
static func encode_units(scenario: Dictionary) -> Dictionary:
	var gambits_array: Array = []
	var skips: int = 0
	for cfg in scenario.get("units", []):
		var raw: Array = cfg.get("gambits", [])
		var encoded := GambitEncoder.encode_gambits(raw)
		for i in range(mini(raw.size(), GPUConstants.MAX_USER_GAMBITS)):
			if encoded[i] == null:
				skips += 1
		gambits_array.append(encoded)
	return {"gambits": gambits_array, "skips": skips}


## Build the GPU-side `{team0, team1}` battle spec for a scenario, reading each unit's
## terrain height off [param lattice].
static func build_battle_spec(scenario: Dictionary, lattice) -> Dictionary:
	var gpu_team0: Array = []
	var gpu_team1: Array = []
	var lat: Lattice = lattice
	for cfg in scenario.get("units", []):
		var tile: Array = cfg.get("tile", [0, 0])
		var height := 0
		var t := lat.terrain_at(TerrainCell.ground(int(tile[0]), int(tile[1]))) if lat else null
		if t:
			height = t.height
		# hp defaults to max_hp when not given so a "max_hp: 999" knight isn't silently
		# flattened to 100/999 (10%) on the GPU buffer — that would flip every HP_BELOW(X)
		# condition's truth value (issue: B7 pass-2 retry never runs because pass-1
		# mistakenly succeeds on the "full HP" rank-0 unit). Matches the unit-stat fallback
		# used in `spawn_unit` above.
		var max_hp_value: int = int(cfg.get("max_hp", 100))
		var gpu_cfg := {
			"pos_x": int(tile[0]),
			"pos_z": int(tile[1]),
			"hp": int(cfg.get("hp", max_hp_value)),
			"max_hp": max_hp_value,
			"pa": cfg.get("pa", 10),
			"ma": cfg.get("ma", 10),
			"wp": cfg.get("wp", 5),
			"brave": cfg.get("brave", 50),
			"faith": cfg.get("faith", 50),
			"speed": cfg.get("speed", 100),
			"mp": cfg.get("mp", 50),
			"max_mp": cfg.get("max_mp", 50),
			"move": cfg.get("move", 4),
			"jump": cfg.get("jump", 3),
			"height": height,
			"weapon_range": cfg.get("weapon_range", 1),
			"weapon_flags": cfg.get("weapon_flags", 1),
			"weapon_type": cfg.get("weapon_type", 0),
			# Pre-combat status seed. lo covers bits 0–31 (DEAD, IMMOBILIZE, SILENCE, …),
			# hi covers 32–63. status_timers is an Array of `{bit, ticks}` dicts;
			# since #1116 the countdowns are slot-addressed and the old pre-packed
			# `(bit << 24) | ticks` int is REFUSED at the packer rather than seeding
			# somebody else's slot. Without a ticks entry the bit is set forever (no
			# countdown), which is what B4/B5 want.
			"status_flags_lo": cfg.get("status_flags_lo", 0),
			"status_flags_hi": cfg.get("status_flags_hi", 0),
			"status_timers": cfg.get("status_timers", []),
		}
		if cfg.get("team", 0) == 0:
			gpu_team0.append(gpu_cfg)
		else:
			gpu_team1.append(gpu_cfg)
	return {"team0": gpu_team0, "team1": gpu_team1}
