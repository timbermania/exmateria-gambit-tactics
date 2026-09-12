extends RefCounted

## The identity binding that lifts a battle-local `(context, uid)` handle to a global
## `slug`, with a safe escape hatch (ADR-0201 dec.6/7). `uid` is a per-ENTD slot byte —
## NOT globally unique — so the mapping is always context-scoped: two battles' `uid 3`s
## resolve to different slugs. The `slug` is the single join key (ADR-0066 dec.4).
##
## `resolve_character` is the battle read-seam:
##   HIT  (slug resolves to a registered Catalog Character) -> return that Character,
##        so its replayed identity/progression flows into the fight.
##   MISS (no slug, or the slug is not registered) -> fall back to constructing the
##        Character from the raw ENTD slot exactly as today ([Character.from_entd_slot]),
##        and RECORD the `(context, uid)` as a coverage gap. Binding coverage is then a
##        visible, shrinking set — divergence is explicit, not silent.
##
## A slug comes from (in priority order): an explicit `bind(context, uid, slug)` entry,
## else the slot's `special_name` via [UnitNames] (named/special units bind first). The
## catalogue is duck-typed: it must provide `get_character(slug)` (the live
## [CharacterCatalog] autoload, or a test fake).
##
## Run guard: "$GODOT" --path . --quit-after 5 res://tests/SlugBindingTest.tscn

# SIBLING MEMBERS of this addon, by path. A member declares no `class_name` — the
# folder-named facade holds the addon's ONE global (ADR-0212 dec. 1) — so an
# intra-addon reference preloads its sibling, which is `exmateria_almanac`'s own
# idiom (`items/EquipStatDelta.gd:33`). Outside the addon the same names come
# off `ExMateriaCatalogue`; inside it there is no facade to go through.
const Character = preload("res://addons/exmateria_catalogue/identity/Character.gd")
const UnitNames = preload("res://addons/exmateria_catalogue/identity/UnitNames.gd")

const ENTD_EMPTY := 0xFF

## context (int) -> { uid (int) -> slug (String) }. Context-scoped so a `uid` that
## collides across battles still resolves to the right identity.
var _table: Dictionary = {}

## Ordered record of the `(context, uid)` slots that fell back to ENTD-slot
## construction — the shrinking binding-coverage gap. Deduped via `_fallback_seen`.
var _fallbacks: Array = []
var _fallback_seen: Dictionary = {}


## Author an explicit `(context, uid) -> slug` binding (the highest-priority source).
func bind(context: int, uid: int, slug: String) -> void:
	if not _table.has(context):
		_table[context] = {}
	_table[context][uid] = slug


## The slug for `(context, uid)` from the authored table only (no slot fallback), or
## "" if unbound. Context-scoped: same `uid` in two contexts can differ.
func slug_for(context: int, uid: int) -> String:
	return String(_table.get(context, {}).get(uid, ""))


## The slug for this cast slot: an explicit binding wins; else the slot's canonical
## `special_name` via [UnitNames] (named/special units bind first); else "".
func resolve_slug(context: int, uid: int, slot: Dictionary) -> String:
	var explicit := slug_for(context, uid)
	if explicit != "":
		return explicit
	var special := int(slot.get("special_name", ENTD_EMPTY))
	if UnitNames.has(special):
		return UnitNames.slug_of(special)
	return ""


## The Character for this cast slot. HIT -> the registered Catalog Character; MISS ->
## `Character.from_entd_slot(slot)`, recorded as a coverage gap. `catalogue` is
## duck-typed on `get_character(slug)`.
##
## `level_ceiling` rides through to the miss branch only — it is the record-wide level
## an ENTD sentinel scales to (godot-learning ADR-0289, #1179); a registered Catalog
## Character already carries its own level and is not rebuilt from the slot. `-1`
## (the default) leaves [member Character.entd_level_ceiling] to answer.
func resolve_character(context: int, uid: int, slot: Dictionary, catalogue,
		level_ceiling: int = -1):
	var slug := resolve_slug(context, uid, slot)
	if slug != "":
		var bound = catalogue.get_character(slug)
		if bound != null:
			return bound
	_record_fallback(context, uid)
	return Character.from_entd_slot(slot, null, level_ceiling)


## The dedup key for a `(context, uid)` slot in `_fallback_seen`. One encoding, shared
## by the writer (`_record_fallback`) and reader (`has_fallback`) so they can't drift.
func _fallback_key(context: int, uid: int) -> String:
	return "%d:%d" % [context, uid]


func _record_fallback(context: int, uid: int) -> void:
	var key := _fallback_key(context, uid)
	if _fallback_seen.has(key):
		return
	_fallback_seen[key] = true
	_fallbacks.append({"context": context, "uid": uid})


## The recorded coverage gap: the `(context, uid)` slots that fell back to ENTD-slot
## construction. Queryable so coverage shrinks deliberately rather than hiding.
func fallbacks() -> Array:
	return _fallbacks.duplicate()


func fallback_count() -> int:
	return _fallbacks.size()


func has_fallback(context: int, uid: int) -> bool:
	return _fallback_seen.has(_fallback_key(context, uid))
