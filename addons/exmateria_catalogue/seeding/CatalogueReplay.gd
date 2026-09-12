extends RefCounted

## The replay engine that turns a beat-keyed **mutation script** into Catalog
## membership (ADR-0201). Pure, scene-free: it applies each beat's authored deltas
## into a duck-typed catalogue target and creates nothing else. This is the primary
## new seam — the [NavigatorRunner] seek path folds a plan through it before booting
## a battle, and the live walk applies one beat's delta as each beat is reached.
##
## A MUTATION is one delta on a beat's `mutations` list:
##   { "op": "create"|"join"|"leave"|"die", "slug": String, <source> }
## `create` mints an ephemeral via the character-builder factory; `join` promotes a
## unit into the persistent Catalog; both `register` a Character. `leave`/`die`
## remove the slug. Persistence is emergent: an entry is persistent iff the script
## never removes it (ADR-0201 dec.1). `leave` and `die` do not differ at the Catalog
## level in this slice (ADR-0201 open question).
##
## Character SOURCE for `create`/`join` (in priority order):
##   "character": a pre-built Character (tests, or an already-resolved identity)
##   "slot":      an ENTD slot dict -> [Character.from_entd_slot] (existing ENTD data)
##   else:        a bare identity — Character.new(slug, name) — no progression
## `create`/`join` never generate stats from scratch; they reference existing data
## (ADR-0201 dec.10, spec #190).
##
## The catalogue is duck-typed: it must provide `register(character)` and
## `unregister(slug)` (the live [CharacterCatalog] autoload, or a test fake).
##
## Run guard: "$GODOT" --path . --quit-after 5 res://tests/CatalogueReplayTest.tscn

const Character = preload("res://addons/exmateria_catalogue/identity/Character.gd")


## Apply the deltas of beats `0..up_to_index-1` into `catalogue`, in order. Folding
## to `up_to_index` yields exactly the union of those beats' deltas; the target is
## assumed to already be at new-game state (the runner resets before folding — the
## fold itself only applies). `up_to_index` is clamped into `[0, actions.size()]`.
static func fold(actions: Array, up_to_index: int, catalogue) -> void:
	var limit := clampi(up_to_index, 0, actions.size())
	for i in range(limit):
		apply_action(actions[i], catalogue)


## Apply ONE action's mutation deltas — the live-walk seam (the runner calls this as
## each beat is reached, so a walk never re-folds). An action with no `mutations` is
## a no-op.
static func apply_action(action: Dictionary, catalogue) -> void:
	for delta in action.get("mutations", []):
		_apply_delta(delta, catalogue)


static func _apply_delta(delta: Dictionary, catalogue) -> void:
	match String(delta.get("op", "")):
		"create", "join":
			catalogue.register(_build_character(delta))
			# `own: true` also marks the slug in the catalogue's OWNED overlay (#234 B/C —
			# the player's deployable subset; a story guest like Delita joins WITHOUT it).
			# Guarded by has_method so a minimal duck-typed fake (no overlay) is unaffected.
			if bool(delta.get("own", false)) and catalogue.has_method("add_owned"):
				catalogue.add_owned(String(delta.get("slug", "")))
		"leave", "die":
			catalogue.unregister(String(delta.get("slug", "")))
		_:
			push_warning("[CatalogueReplay] unknown mutation op %s — skipped" % str(delta.get("op", "")))


## Resolve a `create`/`join` delta to the Character to register. Never mints stats
## from scratch: a pre-built `character`, else an existing ENTD `slot`, else a bare
## identity carrying only slug + name. A `slug` on the delta always wins as the
## registered identity (the script names the global identity; the slot's own
## sourcing is only for the progression/stats it seeds).
static func _build_character(delta: Dictionary):
	var slug := String(delta.get("slug", ""))
	if delta.get("character", null) != null:
		var pre = delta["character"]
		if slug != "":
			pre.slug = slug
		return pre
	if delta.has("slot"):
		var c = Character.from_entd_slot(delta["slot"])
		if slug != "":
			c.slug = slug
		return c
	return Character.new(slug, String(delta.get("name", slug.capitalize())))
