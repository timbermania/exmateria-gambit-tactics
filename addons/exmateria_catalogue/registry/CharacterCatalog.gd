extends Node

## The active Character Catalog (autoload) — ADR-0066.
##
## The master runtime registry of who exists, keyed by a stable `slug`. Each
## entry is a `Character` (identity: slug + aliases + display name + name
## provenance, plus refs to the durable functional objects). Resolution goes
## `slug (or alias) → Character → display_name`; the call sites (dialogue name
## macros) are unchanged from the flat-dict first slice — they still call
## `display_name(slug)` and `name_macro_slug(macro)`.
##
## Why a runtime lookup at all (rather than baking the name into dialogue): a
## Character's name can be player-authored (that is the entire reason FFT's
## `0xE0`/`{Ramza}` control code exists instead of literal text). So names are
## resolved live, and the two write seams honour `name provenance`
## (ADR-0066 decision 11):
##   - `set_display_name` — the player-rename seam (naming UI): renames a
##     `Player` Character; a no-op on a `Fixed` one (not player-editable).
##   - `import_name` — the re-import / seed seam: overwrites a `Fixed` name,
##     but NEVER clobbers a `Player` name (the player's choice wins).

const Character = preload("res://addons/exmateria_catalogue/identity/Character.gd")


## The live catalogue node, resolved BY NODE PATH rather than by the bare
## `CharacterCatalog` identifier — the addon's own singleton, reached the way every
## extracted addon in this corpus reaches its own.
##
## 🔴 THE SPELLING IS THE DECISION, AND IT IS NOT STYLE. A bare `CharacterCatalog.` does
## not PARSE in a project that has not yet added the `[autoload]` line, and this corpus has
## the receipt twice: `addons/exmateria_platform/display_port/DisplayPort.gd:31` records it
## for `PSXDisplay`, and `addons/exmateria_sound/debug/spu_audio_debug_panel.gd:47-52`
## quotes the error it fixed — `Parse Error: Identifier "ExMateriaEffectSfx" not declared
## in the current scope. x5`. Both landed on `get_node_or_null(^"…")` and so does this.
##
## It is also the only spelling the guard can price. `check_addon_portability` arm 2 has no
## own-singleton exemption and books a bare `CharacterCatalog.` as standalone-parse debt;
## arm 2b DOES have one, decided on the `res://` path the `[autoload]` line carries, on the
## ground that the addon ships the script the line points at — which this addon does.
##
## Returns `null` where no autoload is installed. Callers take a catalogue by ARGUMENT and
## fall back here, so a test fake, a headless tool and the live game all reach the same
## code (ADR-0262 dec. 6 left the choice between a port and injection to pass 3; this is
## the injection, and `live()` is its default rather than a fourth verb over the port).
static func live() -> Node:
	var loop := Engine.get_main_loop()
	return loop.root.get_node_or_null(^"CharacterCatalog") if loop != null else null

## FFTPatcher macro names (as baked into dialogue tokens) that are Character
## **name inserts**, mapped to their Character slug. Only the protagonist name
## insert (`0xE0`/`{Ramza}`) exists in ROM content; authored content will target
## slugs directly. "Word" macros (`{Serpentarius}`, …) are deliberately absent —
## they are NOT names and must stay literal. This fixed set is what makes the
## name-vs-word decision deterministic (never "does it collide with a slug").
const NAME_MACRO_SLUG := {
	"Ramza": "ramza",
}

## slug → Character.
var _characters := {}
## alias → slug (so an alias resolves to the same Character as its slug).
var _alias_index := {}

## The OWNED overlay (wayfinder #234 B; ADR extending 0066/0073): the ordered slugs
## of the player's persistent, deployable subset — a catalogue-internal layer, NOT a
## field on Character (which would couple the player layer onto catalogue existence).
## Deploy order = list order. Owned membership is DIFFERENT from catalogue membership:
## the catalogue holds every unit at a state (incl. the Delita guest); owned is the
## player's roster. Surfaced as queries (add_owned/is_owned/owned_units/…). For the
## navigator proof it is SEEDED by the mutation fold each boot (see reset_to_new_game),
## so `reset` clears it and the fold re-applies it — the full player-authored save/load
## of this layer is deferred fog (ADR-0201 §8).
var _owned_order: Array[String] = []

## The new-game slug baseline for the navigator seek reset (ADR-0201). Captured lazily
## the first time `reset_to_new_game` runs — at that moment the Catalog holds exactly
## its new-game population (the seeded protagonist + promoted roster), before any
## replay has folded scripted guests in. A later seek removes everything NOT in this
## set, so replay is always applied onto a clean new-game Catalog.
var _new_game_baseline := {}
var _baseline_captured := false


func _ready() -> void:
	# Seed the protagonist: Player provenance with the canonical default name
	# (the name-entry flow may later override it via set_display_name).
	register(Character.new("ramza", "Ramza", Character.Provenance.PLAYER))


## Register (or replace) a Character, indexing it by slug and every alias. On
## replace, the previous registration's stale aliases are dropped first so a
## removed alias no longer resolves.
func register(character) -> void:
	var prev = _characters.get(character.slug, null)
	if prev != null:
		for stale in prev.aliases:
			if _alias_index.get(stale, "") == character.slug:
				_alias_index.erase(stale)
	_characters[character.slug] = character
	for alias in character.aliases:
		_alias_index[alias] = character.slug


## Remove a Character by slug, dropping its aliases too. The inverse of
## register: lets a Roster prune a slug that no longer names a live entry (a
## freed `<side>:N` after remove_unit, or a shorter reload) so it stops
## resolving to a detached Character. No-op for an unknown slug. Only the
## slug's OWN aliases are dropped (an alias re-pointed to another slug is left).
func unregister(slug: String) -> void:
	var character = _characters.get(slug, null)
	if character == null:
		return
	for alias in character.aliases:
		if _alias_index.get(alias, "") == slug:
			_alias_index.erase(alias)
	_characters.erase(slug)


## The Character for `key` (a slug OR an alias), or null if unknown. A canonical
## slug wins over a foreign Character's colliding alias — identity is never
## shadowed by an alias.
func get_character(key: String):
	if _characters.has(key):
		return _characters[key]
	var resolved_slug: String = _alias_index.get(key, "")
	return _characters.get(resolved_slug, null)


## The Character's current display name for `key`, or the key itself if unknown
## (so a missing entry degrades to a visible, non-crashing marker).
## (Named `display_name`, not `get_name`, to avoid shadowing `Node.get_name`.)
func display_name(key: String) -> String:
	var character = get_character(key)
	return character.display_name if character != null else key


## True if `key` (slug or alias) names a known Character.
func has_slug(key: String) -> bool:
	return get_character(key) != null


## Every registered Character (a copy of the values, so callers can't mutate the index).
## Read-only enumeration seam for inspection tools (the F3 ROSTER "Universe" panel).
func all_characters() -> Array:
	return _characters.values().duplicate()


## --- Owned overlay (wayfinder #234 B) ---------------------------------------

## Mark `slug` owned (append to the deploy-ordered player subset). Idempotent — a
## re-fold of the seeding mutation script must not duplicate an entry. Decoupled from
## registration: owning a slug the catalogue doesn't (yet) hold is allowed; it simply
## won't resolve in `owned_units` until registered.
func add_owned(slug: String) -> void:
	if slug != "" and not _owned_order.has(slug):
		_owned_order.append(slug)


## Drop `slug` from the owned overlay (the inverse of add_owned). No-op if not owned.
func remove_owned(slug: String) -> void:
	_owned_order.erase(slug)


## True if `slug` is in the owned overlay (exact slug, not alias).
func is_owned(slug: String) -> bool:
	return _owned_order.has(slug)


## The owned overlay as a raw ordered slug list (copy — callers can't mutate the index).
func owned_slugs() -> Array:
	return _owned_order.duplicate()


## The owned Characters in deploy order — the projection D deploys and E's formation
## view binds. Skips any owned slug with no registered Character (the overlay is
## decoupled from registration, so a not-yet-minted slug is silently absent).
func owned_units() -> Array:
	var out: Array = []
	for slug in _owned_order:
		var c = _characters.get(slug, null)
		if c != null:
			out.append(c)
	return out


## Replace the whole owned order (the reorder seam — roster assembly, deferred fog).
## Filters to non-empty slugs; de-dupes preserving first occurrence.
func set_owned_order(slugs: Array) -> void:
	var next: Array[String] = []
	for s in slugs:
		var slug := String(s)
		if slug != "" and not next.has(slug):
			next.append(slug)
	_owned_order = next


## Derive a unit's per-battle CLASS (never stored — wayfinder #234 B / ADR-0066 dec.5):
## owned → "player"; else Blue (team_color 0) → "guest" (Delita); else → "enemy". A
## view-layer label (E badges rows by it); the engine team split stays binary (A's
## team_of). The same identity can be a guest here and a party member elsewhere.
func classify(slug: String, team_color: int) -> String:
	if is_owned(slug):
		return "player"
	return "guest" if team_color == 0 else "enemy"


## The player-rename seam (naming UI). Renames a `Player` Character; a no-op on
## a `Fixed` one (Fixed names are not player-editable — ADR-0066 dec.11). No-op
## for an unknown key.
func set_display_name(key: String, name: String) -> void:
	var character = get_character(key)
	if character != null and character.is_renameable():
		character.display_name = name


## The re-import / seed seam. Overwrites a `Fixed` name (canonical, re-imported
## from ROM), but NEVER clobbers a `Player` name — the player's choice wins
## (ADR-0066 dec.11). No-op for an unknown key.
func import_name(key: String, name: String) -> void:
	var character = get_character(key)
	if character != null and character.provenance == Character.Provenance.FIXED:
		character.display_name = name


## The Character slug for a baked macro token's name if it is a name-insert
## macro, else "" (empty ⇒ not a name; render the macro literally).
func name_macro_slug(macro_name: String) -> String:
	return NAME_MACRO_SLUG.get(macro_name, "")


## Reset the Catalog to its new-game population — the seam a navigator SEEK calls
## before replaying a mutation script (ADR-0201 dec.4). The first call captures the
## current population as the new-game baseline (the Catalog is at new-game state then);
## every later call drops any slug NOT in that baseline, so a re-seek folds onto a
## clean Catalog rather than accumulating a prior seek's scripted guests. The
## player/roster baseline (protagonist + promoted units) is preserved.
func reset_to_new_game() -> void:
	# The owned overlay is per-run seed state (the mutation fold re-establishes it each
	# boot/seek), so clear it here regardless of baseline capture — a re-seek must land
	# the owned set from the re-folded script, not accumulate the prior run's.
	_owned_order.clear()
	if not _baseline_captured:
		_baseline_captured = true
		for slug in _characters.keys():
			_new_game_baseline[slug] = true
		return
	for slug in _characters.keys():
		if not _new_game_baseline.has(slug):
			unregister(slug)
