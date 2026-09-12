extends RefCounted

## UI's four reads of the player's roster, reached WITHOUT the `CharacterCatalog`
## autoload identifier (#1272, extraction #8 pass 6 step 2).
##
## WHAT THIS SEVERS. Six lines in three formation members named the autoload. An addon
## cannot ship `project.godot` entries (ADR-0262 dec. 6) and every stranger rig declares
## an EMPTY `[autoload]` block, so the identifier does not PARSE once `src/ui3/` becomes
## `addons/exmateria_ui/` — a compile break, not a degraded screen (ADR-0308).
##
## 🔴 THIS IS NOT "EXTRACT THE CATALOGUE". `registry/CharacterCatalog.gd` ALREADY lives in
## `addons/exmateria_catalogue/`; it is the host's `[autoload]` LINE that does not travel.
## The script travels with the addon, the registration does not — so the whole job is to
## reach the running node by some spelling other than the bare identifier.
##
## 🔴 THE CATALOGUE ALREADY DECIDED THE SPELLING, AND IT IS NOT A PORT. `CharacterCatalog`
## publishes `static func live()` — `get_node_or_null(^"CharacterCatalog")` — and its own
## docstring rules on why: *"Callers take a catalogue by ARGUMENT and fall back here … 
## ADR-0262 dec. 6 left the choice between a port and injection to pass 3; this is the
## injection, and `live()` is its default rather than a fourth verb over the port."*
## `addons/exmateria_catalogue/seeding/AllTemplatesSeeder.gd:205` is the shipped example.
## So this file adds NO new door — it reaches the existing one and carries UI's fallbacks.
##
## 🔴 WHY NOT `ExMateriaSpriteRig.ContentPort`, the ticket's other option: that port answers
## seven SCALAR ROM-content queries (weapon v-offsets, palette rows, ability anim ids). The
## owned-roster overlay is not sprite content and the port has no verb that could carry it.
## Rejected on its surface, not on taste.
##
## THE FALLBACKS, AND WHY EACH IS THE ONE IT IS. With no catalogue there is no owned
## overlay at all, so each verb answers the EMPTY truth rather than a guess:
##   owned_units()  -> []     the roster is empty, so the formation grid draws no cells
##   owned_slugs()  -> []     `.find()` then gives -1, which the one caller already maps
##                            to slot 0 — the same answer it gives an unknown character
##   is_owned()     -> false  there is no overlay to be in. NOTE this is NOT the same
##                            question as `FormationMapHost.unit_is_owned`'s own
##                            `character == null -> true`: that one means "an
##                            unidentified unit standing on the player's map", which is
##                            a can't-tell. "No catalogue" is not a can't-tell, it is a
##                            known-empty, and claiming ownership the addon cannot
##                            verify would be the guess.
##   get_character() -> null  the caller's other early return on a missing slug
##
## Nothing here is instantiated; the class is a namespace of statics.

## The SCRIPT, aliased off the catalogue addon's published surface (ADR-0211 dec. 4 — a
## host may alias a published constant, and may not `preload` an addon path). `live()` is
## a static on it, so this const never mints a catalogue: `.new()` on this script would be
## a second, empty universe, which `exmateria_catalogue.gd:95-101` warns about by name.
const CatalogueRegistry = ExMateriaCatalogue.CharacterCatalog


## The running catalogue, or null where no autoload is installed.
static func _live() -> Node:
	return CatalogueRegistry.live()


## The player's persistent, deployable characters, in owned order.
static func owned_units() -> Array:
	var c := _live()
	return c.owned_units() if c != null else []


## The same set as slugs, in the same order.
static func owned_slugs() -> Array:
	var c := _live()
	return c.owned_slugs() if c != null else []


## Is `slug` in the owned overlay? False with no catalogue — see the fallback note above.
static func is_owned(slug: String) -> bool:
	var c := _live()
	return c.is_owned(slug) if c != null else false


## The [Character] for a slug or alias, or null.
static func get_character(key: String):
	var c := _live()
	return c.get_character(key) if c != null else null
