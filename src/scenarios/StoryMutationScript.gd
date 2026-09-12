class_name StoryMutationScript
extends RefCounted

## The DERIVED [MutationScript] (ADR-0216): the beat-keyed Catalog deltas the navigator
## folds, built from [RosterTimeline] instead of a hand-authored table. This is the "ROM
## generator" ADR-0201 dec.10 deferred — the ENTD half of it.
##
## It folds TWO derived tables, which answer different questions and land at different
## points in a group:
##
## [b]Recruits, at the group's END.[/b] A group grants its recruits when you LEAVE it —
## you do not have Orlandu when you ARRIVE at Bethla — which is exactly what
## `roster_before` encodes. [NavigatorRunner] applies an action's deltas as it leaves that
## action, so keying a group's joins on its own root-keyed action puts them at the group's
## end by construction. A group is either linear (one `scenario:<root>` action) or a battle
## (`combat:<root>` is its last root-keyed action) and never both, so both keys carry the
## same deltas and exactly one of them is ever looked up.
##
## [b]Appearances, at the group's START.[/b] Every named unit a battle's own ENTD spawns
## enters the Catalog, so its slot binds to a real identity (a [SlugBinding] HIT) instead
## of being rebuilt from the raw slot — ADR-0201 dec.6/7's whole point. Those deltas key on
## the battle's `opener:<scenario_id>`, the one action whose deltas land BEFORE the fight.
## Named ENEMIES included: the Catalog is the one population (ADR-0078), and an appearance
## grants nothing to the owned overlay.
##
## [b]Three decisions this consumer makes, which the generator deliberately does not[/b]
## (ADR-0216 dec.8 emits the raw flags and leaves them to the reader):
##
## 1. [b]`own` — owned membership.[/b] ADR-0078 rules that catalogue membership is not
##    owned membership: a unit can exist and never be the player's. The ROM cannot say
##    which is which — every join slot has `flags2 control` clear (and across all 72 battle
##    groups exactly ONE present slot sets it, Orbonne's baked-in Ramza), so the flag
##    discriminates nothing. A recruit is therefore marked `own: true` — it is the player's
##    roster, and nothing else mints the owned overlay — EXCEPT the units in
##    [constant NEVER_OWNED]. Without that split the Gariland deployment would field a
##    second Delita beside the one ENTD 388 spawns as the free blue guest.
## 2. [b]`repeat` joins are skipped, and an appearance binds ONCE.[/b] Either would
##    re-register a slug from a different ENTD slot, clobbering a Character the player has
##    been levelling. Only [method RosterTimeline.recruits_for] deltas fold, and the
##    generator already suppresses a re-bind at the source.
## 3. [b]The protagonist's new-game progression is authored, not sourced.[/b] Ramza's
##    position-0 seed points at ENTD 256, a cinematic slot whose `special_name` is 2 —
##    his CH2 form. Folding it would stamp a durable `special_name` on him, which ADR-0079
##    forbids (the active Form is materialized at the deploy seam, never at mint). So the
##    seed carries a pre-built lv1 Squire with his Ch1 Form set instead.
##
## Run guard: "$GODOT" --path . --quit-after 5 res://tests/StoryMutationScriptTest.tscn

const Character = ExMateriaCatalogue.Character
## Magic City Gariland — the first roster-fed battle, and the root the non-walking
## consumers ([GPUArena], [CombatUITestScene]) seed their player side at.
const GARILAND_ROOT := 9

## The protagonist's canonical slug (matches the CharacterCatalog new-game seed).
const RAMZA_SLUG := "ramza"

## Job ids (jobs.json): Squire 0x4a.
const JOB_SQUIRE := "4a"

## Ramza's Ch1 [Form] set — ROM-derived, seeded at mint (ADR-0079). His three chapter
## Forms are `special_name` 1/2/3; only the Ch1 incarnation is reachable now, so only it
## is authored. The deploy seam SELECTS the active Form and materializes its
## `special_name` — never a durable byte at mint.
const RAMZA_FORMS := [{"chapter": 1, "special_name": 1}]

## The recruits that never enter the OWNED overlay — catalogue-yes, owned-no, which is the
## split ADR-0078 already rules ("Delita is catalogue-yes / owned-no"). Named for what it
## decides, `own`, not for a rival concept: the per-battle role these units read as is
## [b]Class[/b] `guest`, which `CharacterCatalog.classify` derives from this plus the
## slot's `team_color` and never stores.
##
## Authored because the ROM cannot say it. `control` marks a slot the player commands, and
## across the 72 battle groups exactly one present slot sets it — Orbonne's baked-in Ramza,
## the sole predetermined cast. Everywhere else the player's units come from the roster and
## are not in the ENTD at all, so every Blue ENTD slot is a guest AT THAT BATTLE and the
## flag says nothing about whether the unit is ever owned (Agrias guests at Orbonne and is
## owned from Bariaus Valley on). Same footing as ADR-0216 dec.6's `RECRUIT_AT`.
const NEVER_OWNED := ["delita", "algus", "ovelia", "gafgarion", "alma"]


## Build the whole story's [MutationScript] from the derived timeline.
static func build() -> MutationScript:
	var table: Dictionary = {}
	for root in RosterTimeline.order():
		var appearances := appearance_deltas_for(root)
		if not appearances.is_empty():
			# Keyed on the battle's OPENER — the one action whose deltas land before the
			# fight, which is what a binding needs. `action_key` formats it, so the key
			# cannot drift from the one the navigator looks up.
			table[MutationScript.action_key({"kind": "opener",
				"beat": {"scenario_id": RosterTimeline.opener_scenario_id(root)}})] = appearances
		var deltas := deltas_for_group(root)
		if deltas.is_empty():
			continue
		# A group is linear OR a battle, never both, so exactly one of these keys is ever
		# looked up; carrying both keeps this builder free of the navigator's kind table.
		table["scenario:%d" % root] = deltas
		table["combat:%d" % root] = deltas.duplicate(true)
	return MutationScript.new(table)


## The deltas one group grants at its end: its permanent recruits, `own`-marked for
## everyone but the story guests, with the protagonist's seed swapped for an authored
## new-game Character (see the class doc).
static func deltas_for_group(root: int) -> Array:
	var out: Array = []
	for delta in RosterTimeline.recruits_for(root):
		out.append(_consumable(delta))
	return out


## The named units this battle SPAWNS, as never-owned catalogue joins — the derived
## replacement for the hand-typed Orbonne table (ADR-0216 dec.12). Empty for a linear
## group and for a battle whose whole named cast is already catalogued.
static func appearance_deltas_for(root: int) -> Array:
	var out: Array = []
	if RosterTimeline.opener_scenario_id(root) < 0:
		return out
	for delta in RosterTimeline.appearances_for(root):
		out.append({
			"op": String(delta.get("op", "join")),
			"slug": String(delta.get("slug", "")),
			"slot": (delta.get("slot", {}) as Dictionary).duplicate(true),
		})
	return out


## The fold of every group that comes BEFORE `root` in story order — the derived
## replacement for the navigator's replanned prologue. Defined for every group in the
## timeline, not only the ones reachable by chaining from the story root.
##
## RECRUITS ONLY: its fold is `RosterTimeline.roster_before(root)` by construction, and
## that equality is what keeps the script and the derived table from drifting.
static func seed_deltas_before(root: int) -> Array:
	var out: Array = []
	var stop := RosterTimeline.position(root)
	if stop < 0:
		return out
	for r in RosterTimeline.order():
		if RosterTimeline.position(r) >= stop:
			break
		out.append_array(deltas_for_group(r))
	return out


## What a SEEK to `root` must fold to arrive with the catalogue the walk would have
## built: every earlier group's appearances (at its start) and recruits (at its end), in
## that order. Wider than [method seed_deltas_before], which is the ROSTER alone — a
## re-rooted plan omits the earlier battles' opener actions too, so without this a unit
## first bound at an earlier fight would fall back to raw-ENTD construction if it turns
## up again later.
static func prologue_deltas_before(root: int) -> Array:
	var out: Array = []
	var stop := RosterTimeline.position(root)
	if stop < 0:
		return out
	for r in RosterTimeline.order():
		if RosterTimeline.position(r) >= stop:
			break
		out.append_array(appearance_deltas_for(r))
		out.append_array(deltas_for_group(r))
	return out


## The OWNED subset of the roster as it stands when Gariland boots — Ramza plus the six
## Academy cadets ENTD 392 grants, in fold order (the protagonist leads).
##
## PUBLIC because the seed has consumers that walk no plan: [GPUArena] and
## [CombatUITestScene] boot a battle directly and need the same player side the walk
## would have arrived with (ADR-0180). Both go through [CatalogueReplay]; they differ
## only in when.
static func owned_seed_deltas() -> Array:
	var out: Array = []
	for delta in seed_deltas_before(GARILAND_ROOT):
		if bool(delta.get("own", false)):
			out.append(delta)
	return out


## One derived join delta, made consumable: `own` decided here, and the protagonist's
## ENTD source replaced by his authored new-game Character.
static func _consumable(delta: Dictionary) -> Dictionary:
	var slug := String(delta.get("slug", ""))
	var out: Dictionary = {"op": String(delta.get("op", "join")), "slug": slug}
	if slug == RAMZA_SLUG:
		out["character"] = _ramza_character()
	else:
		out["slot"] = (delta.get("slot", {}) as Dictionary).duplicate(true)
	if not NEVER_OWNED.has(slug):
		out["own"] = true
	return out


## Ramza as a bare-catalogue protagonist made battle-ready: a lv1 Squire progression
## attached to his canonical identity (create_default seeds the durable progression + the
## job's default weapon). Keeps PLAYER provenance so he stays renameable. Carries his
## ROM-derived Form set (ADR-0079) — the active Form is materialized at the deploy seam,
## NOT stamped as a durable `special_name` here (identity stays context-free).
static func _ramza_character() -> Character:
	var c := Character.create_default("Ramza", JOB_SQUIRE, false, Character.Provenance.PLAYER)
	c.slug = RAMZA_SLUG
	c.forms = RAMZA_FORMS
	return c

