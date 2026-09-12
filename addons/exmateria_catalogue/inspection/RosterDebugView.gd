extends RefCounted

## Read-only VIEW-MODEL for the two F3 ROSTER debug panels (ADR-0201 inspection):
##   • the "Universe" panel — the persistent [CharacterCatalog] as it stands at the
##     current beat (who exists: slug, name, provenance, roster group, job/level);
##   • the "Battle Binding" panel — how that universe maps onto the current battle's
##     ENTD slots via [SlugBinding] (each slot → catalogue Character, or FALLBACK).
##
## Pure functions over plain Character + SlugBinding inputs — NO scene/autoload coupling,
## so the panels stay dumb renderers and the row logic is unit-tested (RosterDebugViewTest).
## Resolution is READ-ONLY: it uses `resolve_slug` (side-effect free), never
## `resolve_character` (which would record a fallback on the live binding).

const Character = preload("res://addons/exmateria_catalogue/identity/Character.gd")

const ENTD_EMPTY := 0xFF


## One row per character in the persistent catalogue, sorted by slug for a stable view.
## `characters` is an Array of [Character] (e.g. `CharacterCatalog.all_characters()`).
## Row: { slug, name, provenance("FIXED"|"PLAYER"), group, job, level, female }.
static func build_universe_rows(characters: Array) -> Array:
	var rows: Array = []
	for c in characters:
		if c == null:
			continue
		rows.append({
			"slug": String(c.slug),
			"name": String(c.display_name),
			"provenance": _provenance_str(c.provenance),
			"group": _group_of_slug(String(c.slug)),
			"job": _job_of(c),
			"level": _level_of(c),
			"female": bool(c.is_female),
		})
	rows.sort_custom(func(a, b): return String(a["slug"]) < String(b["slug"]))
	return rows


## One row per DEPLOYED ENTD slot, in slot order, showing how it binds into the
## catalogue for battle `context`. Row: { uid, team, special_name, slug, bound, name,
## fallback }. HIT (slug resolves to a registered Character) → bound; else fallback.
##
## Only units actually on the field at battle start are rows: empty slots (uid 0xFF) and
## `always_present==false` slots are excluded. The latter are cutscene / alternate-version
## entries (e.g. the Orbonne Delita + control-dups) that never take the field — mirroring
## the combat-cast gate in NavigatorMain._build_frozen_combat_loop, so the panel shows exactly the
## deployed config rather than phantom units. (Non-combatant present NPCs like Ovelia stay:
## they ARE deployed, just not fighting.)
static func build_binding_rows(slots: Array, context: int, binding, catalogue) -> Array:
	var rows: Array = []
	for slot in slots:
		var uid := int(slot.get("unit_id", ENTD_EMPTY))
		if uid == ENTD_EMPTY:
			continue
		if not bool(slot.get("flags2_decoded", {}).get("always_present", false)):
			continue
		var slug := String(binding.resolve_slug(context, uid, slot))
		var character = catalogue.get_character(slug) if slug != "" else null
		var bound := character != null
		rows.append({
			"uid": uid,
			"team": String(slot.get("team_color_name", str(slot.get("team_color", 0)))),
			"special_name": int(slot.get("special_name", ENTD_EMPTY)),
			"slug": slug,
			"bound": bound,
			"name": String(character.display_name) if bound else "",
			"fallback": not bound,
			# The ENTD tile the unit is bound to (the "spot") — the config's placement.
			"x": int(slot.get("x", -1)),
			"y": int(slot.get("y", -1)),
		})
	return rows


## Coverage summary for the current battle: { total, bound, fallback }. Mirrors the
## live binding's coverage gap, computed read-only over the ENTD slots.
static func binding_summary(slots: Array, context: int, binding, catalogue) -> Dictionary:
	var total := 0
	var bound := 0
	for row in build_binding_rows(slots, context, binding, catalogue):
		total += 1
		if bool(row["bound"]):
			bound += 1
	return {"total": total, "bound": bound, "fallback": total - bound}


static func _provenance_str(provenance: int) -> String:
	return "PLAYER" if provenance == Character.Provenance.PLAYER else "FIXED"


## The roster namespace a slug belongs to (ADR-0066 `<side>:N`): party / enemy / story.
static func _group_of_slug(slug: String) -> String:
	if slug.begins_with("party:"):
		return "party"
	if slug.begins_with("enemy:"):
		return "enemy"
	return "story"


static func _job_of(c) -> String:
	return String(c.progression.current_job_id) if c.progression != null else ""


static func _level_of(c) -> int:
	return int(c.progression.level) if c.progression != null else 0
