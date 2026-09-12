extends Node3D

## TDD guard for the Character Catalog prefactor (ADR-0066, issue #158).
##
## The Catalog grows from a flat `{slug: name}` dict to `{slug: Character}`,
## where a `Character` is the identity record: canonical `slug` + optional
## aliases, a display name, and a `name provenance` flag (`Fixed` vs `Player`).
## `display_name`/`has_slug` resolve THROUGH the Character (slug or alias), and
## the two write seams honour provenance per ADR-0066 decision 11:
##   - `set_display_name` = the player-rename seam (naming UI) — only a `Player`
##     Character is renameable; a `Fixed` one is not player-editable.
##   - `import_name` = the re-import / seed seam — overwrites a `Fixed` name,
##     but NEVER clobbers a `Player` name (the player's choice wins).
##
## ScenarioNameMacroTest is the untouched slice-1 behavioural guard; this file
## covers the new identity surface only.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CharacterCatalogTest.tscn

const CharacterClass = ExMateriaCatalogue.Character
var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_seeded_ramza_is_a_character()
	_test_register_and_get_by_slug()
	_test_alias_resolves_to_same_character()
	_test_set_display_name_renames_player_only()
	_test_import_name_overwrites_fixed_never_player()
	_test_canonical_slug_wins_over_foreign_alias()
	_test_reregister_clears_stale_aliases()
	_test_unregister_drops_slug_and_aliases()
	print("\n=== CharacterCatalogTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CharacterCatalogTest")
		get_tree().quit(1)
	else:
		print("[PASS] CharacterCatalogTest")
		get_tree().quit(0)


## The seeded protagonist is now a Character (Player provenance), not a raw
## name string; display_name reads off it.
func _test_seeded_ramza_is_a_character() -> void:
	var c: CharacterClass = CharacterCatalog.get_character("ramza")
	_assert_true(c != null, "ramza resolves to a Character")
	if c == null:
		return
	_assert_eq(c.slug, "ramza", "ramza slug")
	_assert_eq(c.display_name, "Ramza", "ramza seeded name")
	_assert_eq(c.provenance, CharacterClass.Provenance.PLAYER,
		"protagonist is Player provenance (renamable, canonical default)")
	_assert_eq(CharacterCatalog.display_name("ramza"), "Ramza",
		"catalog.display_name reads off the Character")


## register() indexes a Character by slug; get_character/display_name/has_slug
## all resolve through it. Unknown key degrades to the key itself.
func _test_register_and_get_by_slug() -> void:
	var agrias := CharacterClass.new("agrias", "Agrias", CharacterClass.Provenance.FIXED)
	CharacterCatalog.register(agrias)
	_assert_true(CharacterCatalog.get_character("agrias") == agrias,
		"registered Character is returned by slug")
	_assert_eq(CharacterCatalog.display_name("agrias"), "Agrias", "display_name via Character")
	_assert_true(CharacterCatalog.has_slug("agrias"), "has_slug true for registered")
	_assert_true(not CharacterCatalog.has_slug("nobody"), "has_slug false for unknown")
	_assert_eq(CharacterCatalog.display_name("nobody"), "nobody",
		"unknown key degrades to the key (visible marker)")


## An alias resolves to the very same Character as its canonical slug.
func _test_alias_resolves_to_same_character() -> void:
	var delita := CharacterClass.new("delita", "Delita", CharacterClass.Provenance.FIXED,
		PackedStringArray(["delita_hero"]))
	CharacterCatalog.register(delita)
	_assert_true(CharacterCatalog.get_character("delita_hero") == delita,
		"alias resolves to the same Character")
	_assert_true(CharacterCatalog.has_slug("delita_hero"), "has_slug true for alias")
	_assert_eq(CharacterCatalog.display_name("delita_hero"), "Delita",
		"display_name via alias")


## set_display_name is the player-rename seam: it renames a Player Character
## (protagonist) but is a no-op on a Fixed one (not player-editable).
func _test_set_display_name_renames_player_only() -> void:
	CharacterCatalog.set_display_name("ramza", "Luso")
	_assert_eq(CharacterCatalog.display_name("ramza"), "Luso", "Player Character renamed")
	CharacterCatalog.set_display_name("ramza", "Ramza")  # restore shared autoload state

	CharacterCatalog.register(
		CharacterClass.new("mustadio", "Mustadio", CharacterClass.Provenance.FIXED))
	CharacterCatalog.set_display_name("mustadio", "Hacked")
	_assert_eq(CharacterCatalog.display_name("mustadio"), "Mustadio",
		"Fixed Character is not player-renamable (set_display_name is a no-op)")


## import_name is the re-import/seed seam (ADR-0066 dec.11): it overwrites a
## Fixed name but NEVER clobbers a Player name.
func _test_import_name_overwrites_fixed_never_player() -> void:
	CharacterCatalog.register(
		CharacterClass.new("orlandu", "T.G.Cid", CharacterClass.Provenance.FIXED))
	CharacterCatalog.import_name("orlandu", "Orlandu")
	_assert_eq(CharacterCatalog.display_name("orlandu"), "Orlandu",
		"re-import overwrites a Fixed name")

	# Player rename first, then a re-import must NOT clobber it.
	CharacterCatalog.set_display_name("ramza", "Ovelia")
	CharacterCatalog.import_name("ramza", "Ramza")
	_assert_eq(CharacterCatalog.display_name("ramza"), "Ovelia",
		"re-import never clobbers a Player name")
	CharacterCatalog.set_display_name("ramza", "Ramza")  # restore shared autoload state


## A Character's own canonical slug must win over a *foreign* Character's alias
## that happens to collide with it — the identity is not silently shadowed.
func _test_canonical_slug_wins_over_foreign_alias() -> void:
	var real := CharacterClass.new("beowulf", "Beowulf", CharacterClass.Provenance.FIXED)
	var other := CharacterClass.new("reis", "Reis", CharacterClass.Provenance.FIXED,
		PackedStringArray(["beowulf"]))  # alias collides with real's slug
	CharacterCatalog.register(real)
	CharacterCatalog.register(other)
	_assert_true(CharacterCatalog.get_character("beowulf") == real,
		"canonical slug wins over a foreign alias of the same string")


## Re-registering a slug with a different alias set drops the stale aliases —
## a removed alias no longer resolves.
func _test_reregister_clears_stale_aliases() -> void:
	CharacterCatalog.register(
		CharacterClass.new("rapha", "Rapha", CharacterClass.Provenance.FIXED,
			PackedStringArray(["rafa"])))
	_assert_true(CharacterCatalog.has_slug("rafa"), "old alias resolves before replace")
	CharacterCatalog.register(
		CharacterClass.new("rapha", "Rapha", CharacterClass.Provenance.FIXED))  # no aliases
	_assert_true(not CharacterCatalog.has_slug("rafa"),
		"stale alias no longer resolves after replace")
	_assert_true(CharacterCatalog.get_character("rapha") != null,
		"slug still resolves after replace")


## unregister() is the inverse of register: it removes a slug AND drops its
## aliases, so a slug that no longer names a live entry (e.g. a Roster pruning a
## freed <side>:N after remove_unit / a shorter reload) stops resolving to a
## detached Character. No-op for an unknown slug.
func _test_unregister_drops_slug_and_aliases() -> void:
	CharacterCatalog.register(
		CharacterClass.new("worker8", "Worker 8", CharacterClass.Provenance.FIXED,
			PackedStringArray(["construct_8"])))
	_assert_true(CharacterCatalog.has_slug("worker8"), "slug resolves before unregister")
	_assert_true(CharacterCatalog.has_slug("construct_8"), "alias resolves before unregister")
	CharacterCatalog.unregister("worker8")
	_assert_true(not CharacterCatalog.has_slug("worker8"),
		"slug no longer resolves after unregister")
	_assert_true(not CharacterCatalog.has_slug("construct_8"),
		"alias no longer resolves after unregister")
	# Unknown slug is a harmless no-op.
	CharacterCatalog.unregister("nobody_here")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
