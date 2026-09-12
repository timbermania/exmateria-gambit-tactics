class_name UnitSpawn
extends RefCounted

## The ONE seam that mints a live [Unit] from a catalogue [Character] (ADR-0180).
##
## Before ADR-0180 this lived on `BaseRoster` keyed by a **roster index**
## (`spawn_unit(i, team)` / `configure_spawned_unit(unit)`), and the story path —
## which has no roster to index — carried a second copy on the navigator
## (`NavigatorMain._spawn_owned_unit` / `_make_combat_ready_from_character` /
## `_seed_job_abilities`, all three of whose docstrings said they "mirror"
## BaseRoster). Retiring the rosters removed the index; what is left is what both
## copies always actually needed — a `Character` — so the seam re-roots on that
## and the mirror collapses instead of acquiring a third copy.
##
## Deliberately only the part that WAS identical. The per-host tails stay at their
## call sites and are not smuggled in here, because they disagree on purpose:
##   - the arena resets HP/MP to full after binding (a fresh fixture fight);
##   - the navigator stamps `special_name` from the active Form before resolving
##     (the ADR-0079 deploy seam), initializes the logical tile from where the
##     scenario placed the unit, and hands the clock to SCENARIO rather than
##     COMBAT until `_go_live`.
## A seam that swallowed those would have to grow a flag per host, which is the
## shape `BaseRoster`'s three abstract hooks already were.
##
## `class_name`, like every other leaf helper here (`EntdBattle`, `CatalogueReplay`,
## `DeploymentPlan`). ADR-0004's surviving decision — "subclasses extend by path,
## not by `class_name`" — is about a BASE script in an autoload's parse chain, and
## nothing extends this. Its underlying trap still applies for one run, though: a
## newly-added `class_name` is invisible until Godot rebuilds the global class
## cache, so every caller reports `Identifier "UnitSpawn" not declared` until one
## `godot --path . --import` has run. That is the pre-flight `run_all_tests.sh`
## already does before the suite.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityData = ExMateriaAlmanac.AbilityData
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const GambitList = ExMateriaAlmanac.GambitList
const JobDatabase = ExMateriaAlmanac.JobDatabase
const CharacterTemplateResolver = ExMateriaCatalogue.CharacterTemplateResolver

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const SpritePaletteResolver = ExMateriaSpriteRig.SpritePaletteResolver


const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"

## Starter abilities seeded per unit. Both retired copies used 3.
const STARTER_ABILITY_COUNT := 3

## AbilityDatabase's "Nothing" placeholder — never seeded.
const ABILITY_NOTHING := 256

## Meta key carrying the slug of the [Character] a Unit was built from — the ONE
## link from a live battlefield node back to its catalogue identity (ADR-0066
## dec. 4 names `slug` the cross-system identity key). It replaces the retired
## `roster_index`/`roster_team` pair, whose index only meant anything inside the
## roster that assigned it: only `BaseRoster.spawn_unit` ever set it, so every
## unit the story path deployed resolved to null.
const CHARACTER_SLUG_META := "character_slug"

## Meta key carrying the [Character] a Unit was built from, BY REFERENCE. The slug
## above is the DURABLE key — the one thing that survives a save — but it is only an
## address, and an address resolves through a population. Not every Character that
## fights is in one: an ENTD generic (`Character.from_entd_slot` on a slot with no
## `special_name`) has an EMPTY slug, because `create_default` leaves the slug for
## "Catalog promotion" and a nameless enemy is never promoted; and a NAMED ENTD unit
## (Delita, guesting on team0 at Gariland) has a slug the arena never registers,
## because `ScenarioCast.seed_owned_roster` folds only the `own: true` deltas and an
## appearance is not one.
##
## Minting positional slugs for those units to make them addressable is exactly the
## `enemy:N` identity ADR-0066 dec. 4 and ADR-0078 rule out. So the seam that KNOWS
## the identity carries it: `build()` was handed the Character, and it stamps it.
## ADR-0180 Amendment 2.
const CHARACTER_META := "character"

## Story-context STUB for the deploy-seam Form selection (ADR-0079). The active Form is
## chosen per story CHAPTER; while Chapter 1 (Gariland) is the only reachable one there is
## no live chapter state to read, so the seam selects with this constant. It SELECTS
## (`Character.active_special_name`) rather than hardcoding a `special_name`, so real
## chapter state drops in here and every unique's later Form follows with it.
const STORY_CHAPTER_STUB := 1


## Materialize `character`'s active Form as its `special_name` — the ADR-0079 deploy seam,
## and [method build]'s one precondition. Call it on a character a host DEPLOYS: a
## catalogue-resident unit has no ENTD slot to read the byte off, and without the stamp
## `build` job-routes a unique to a generic sheet instead of resolving its own template
## folder.
##
## A character with NO Form set is left untouched, and that guard is load-bearing: an
## ENTD-derived `Character` ([code]Character.from_entd_slot[/code]) carries its slot's
## `special_name` and an empty Form set, so a blanket stamp would overwrite Delita's byte
## with the job-route sentinel. Forms in, selection; no forms, no opinion — which is what
## makes this safe to call over a whole cast rather than only the units a host knows are
## unique.
##
## It lives HERE, beside the seam whose precondition it is, rather than as a line in each
## deploy path. A per-host copy is exactly how [ScenarioCast] came to have none: every
## scenario-booted battle job-routed Ramza to the generic Squire body and portrait while
## the navigator's own copy kept working.
static func materialize_active_form(character) -> void:
	if character == null or character.forms.is_empty():
		return
	character.special_name = character.active_special_name(STORY_CHAPTER_STUB)


static var _unit_scene: PackedScene = null


## Instance a Unit for `character` and resolve its visuals — body sprite id, BODY
## palette row and template folder — through the ONE template resolver seam
## (ADR-0072). NOT added to the tree and NOT bound: the caller owns parenting,
## because the two hosts parent to different nodes and wait different numbers of
## frames. Returns null if Unit.tscn will not load.
##
## The caller must stamp anything the resolver reads off the Character (the
## navigator's `special_name` Form selection) BEFORE calling — the resolver stays
## a pure function of what is on the Character when it runs.
static func build(character) -> Node:
	if character == null:
		push_error("[UnitSpawn] build(null)")
		return null
	if _unit_scene == null:
		_unit_scene = load(UNIT_SCENE_PATH)
	if _unit_scene == null:
		push_error("[UnitSpawn] failed to load %s" % UNIT_SCENE_PATH)
		return null
	var unit: Node = _unit_scene.instantiate()
	var visuals: Dictionary = CharacterTemplateResolver.resolve(character)
	# A generic routes through the job tables and gets the flat body ids; a unique
	# resolves to a template FOLDER (#202) and the loader reads its owned sheet
	# from there (#203), with the flat store as the load-bearing fallback. Guard
	# the flat pair so a folder-only resolve does not stamp a bogus 0.
	if visuals.has("body_sprite_id"):
		unit.body_sprite_id = visuals["body_sprite_id"]
		# THE ROW COMES FROM THE RIG, NOT THE RESOLVER (#1071, ADR-0272). It is a
		# render fact and its rule has one owner; the resolver used to pass it
		# through, which cost `exmateria_catalogue` its only cross-addon reach and
		# bought this call site nothing — it holds the `Character`, so it holds the
		# job. Same value, same owner, one fewer edge. `Unit.change_job` already
		# spells the re-stamp exactly this way (`Unit.gd:1481`).
		unit.body_palette_row = SpritePaletteResolver.job_body_palette_row(
			character.progression.current_job_id)
	unit.template_folder = visuals.get("template_folder", "")
	unit.name = character.display_name
	# Identity, not appearance: `name` is the DISPLAY name and Godot will silently
	# uniquify it among siblings, so it cannot be the key anything resolves by.
	unit.set_meta(CHARACTER_SLUG_META, character.slug)
	# The identity ITSELF, not only its address (ADR-0180 Amendment 2) — see
	# CHARACTER_META. The slug stays stamped: it is the durable key, and the one a
	# reader that outlives this object (a save, a log line) can still use.
	unit.set_meta(CHARACTER_META, character)
	return unit


## Bind a spawned Unit to its Character for combat: the Character's
## `UnitProgression` by REFERENCE (ADR-0005 — in-play equip/learn/level persist
## with no copy-back), the job's starter abilities, and the Character's gambit
## list (also by reference).
##
## Call after the unit is in the tree and one frame has passed — `Unit._ready`
## builds the animation set / playbacks, and `equipped_abilities` is not there
## before it.
##
## A Character with no progression cannot fight; that is a caller-visible
## condition (the navigator rebuilds one from the ENTD slot), so this warns and
## returns rather than inventing one.
##
## 🔴 IT ALSO STAMPS THE IDENTITY, ABOVE THAT GUARD — and the placement is the whole
## point of the third fix to [FormationMapHost.character_for_unit]. `build()` stamps
## both metas, and for two fixes running that was assumed to be every unit. It is not:
## `ScenarioPlayerScene._spawn_units` mints the ENTD cast itself — its own comment says
## it *"bypasses UnitSpawn.build"* — and the navigator makes those units combat-ready
## through THIS function alone. So the whole ENTD population reached the map host with
## no identity meta at all, `character_for_unit` answered null, and on that host a null
## is indistinguishable from an empty tile: no vitals or nameplate under the cursor, and
## Tab refusing to open the screen.
##
## ABOVE the progression guard, not below it, because a stamp below leaves exactly the
## BARE identity the host cannot resolve — the same shape as the two previous misses. A
## unit this function refuses to bind is still a unit that IS somebody.
##
## The bounded miss this leaves, stated rather than discovered later: a unit that never
## binds for combat at all. Those are the visual-only scenario actors, which have no
## `Character` to stamp (the scenario places a body, and identity is resolved later, by
## `_binding.resolve_character`) and never stand under a battle `FormationMapHost`.
static func bind_for_combat(unit: Node, character, team: int) -> void:
	if unit == null or character == null:
		return
	# Identity first. Both metas, so the DURABLE key (ADR-0066 dec. 4's slug) stops being
	# build-only: `character_for_unit` prefers the reference and falls back to the slug,
	# and a unit that outlives this object — a save, a log line — has only the slug.
	unit.set_meta(CHARACTER_SLUG_META, character.slug)
	unit.set_meta(CHARACTER_META, character)
	if character.progression == null:
		push_warning("[UnitSpawn] %s has no progression — not bound" % str(character.slug))
		return
	unit.bind_progression(character.progression, team)
	seed_job_abilities(unit, character)
	# The GPU encoder auto-appends the attack-nearest safety net (ADR-0048), so an
	# EMPTY list still fights — but a NULL one is not a list. Mint it on the
	# Character, not a throwaway, so gambits authored later persist like every
	# other by-reference edit.
	if character.gambits == null:
		character.gambits = GambitList.new()
	unit.set_gambit_list(character.gambits)


## Seed up to [constant STARTER_ABILITY_COUNT] castable actions from the
## Character's current job skill set, so casters can act (melee still attack via
## the safety net). Skips the "Nothing" placeholder and anything the unit cannot
## pay for.
static func seed_job_abilities(unit: Node, character) -> void:
	if unit == null or unit.equipped_abilities == null:
		return
	var job: Dictionary = JobDatabase.get_job(character.progression.current_job_id)
	if job.is_empty():
		return
	var actions: Array = AbilityDatabase.get_skill_set_actions(int(job.get("skill_set_id", 0)))
	var added := 0
	for ability_id in actions:
		if added >= STARTER_ABILITY_COUNT:
			break
		if ability_id == ABILITY_NOTHING:
			continue
		var ability = AbilityData.from_database(ability_id)
		if ability != null and ability.mp_cost <= unit.max_mp:
			unit.equipped_abilities.add_ability(ability)
			added += 1
