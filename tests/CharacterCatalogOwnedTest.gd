extends Node
## Pure-logic guard for the CharacterCatalog OWNED overlay + derived class
## (wayfinder #234 B / ADR extending 0066+0073). The catalogue is the one population;
## "owned" is a catalogue-internal `_owned_order` overlay (the persisted player layer)
## surfaced as queries, and a unit's per-battle CLASS is derived (never stored) from
## owned-membership × team_color.
##
## Tests a FRESH CharacterCatalog instance (not the autoload) so there is no seeded
## protagonist / arena-roster pollution — the overlay methods don't need _ready.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/CharacterCatalogOwnedTest.tscn

const CatalogScript = ExMateriaCatalogue.CharacterCatalog
const CharacterClass = ExMateriaCatalogue.Character
var _passed: int = 0
var _failed: int = 0
# Fresh catalogues are unparented Nodes; keep refs so they're freed before quit (an
# unparented Node left leaking trips the engine's shutdown unref-safety check).
var _cats: Array = []


func _ready() -> void:
	_test_empty_overlay()
	_test_add_owned_orders_and_resolves()
	_test_add_owned_idempotent()
	_test_remove_owned()
	_test_owned_units_skips_unregistered()
	_test_classify_derives_from_owned_and_team()
	_test_reset_clears_owned_overlay()

	for c in _cats:
		if is_instance_valid(c):
			c.free()
	_cats.clear()

	print("\n=== CharacterCatalogOwnedTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] CharacterCatalogOwnedTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] CharacterCatalogOwnedTest")
		get_tree().quit(1)
	else:
		print("[PASS] CharacterCatalogOwnedTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


# A fresh catalogue with no _ready seed (never entered the tree). Register a few
# bare identities so the overlay has something to resolve.
func _fresh() -> Object:
	var cat = CatalogScript.new()
	_cats.append(cat)
	return cat


func _register(cat: Object, slug: String) -> void:
	cat.register(CharacterClass.new(slug, slug.capitalize()))


func _owned_slugs_of(cat: Object) -> Array:
	var out: Array = []
	for c in cat.owned_units():
		out.append(c.slug)
	return out


# --- Slice B1: an empty catalogue owns nothing ---
func _test_empty_overlay() -> void:
	var cat := _fresh()
	_eq(cat.owned_units().size(), 0, "fresh: owned_units empty")
	_true(not cat.is_owned("ramza"), "fresh: nothing is owned")


# --- Slice B2: add_owned records ownership AND deploy order (Ramza first) ---
func _test_add_owned_orders_and_resolves() -> void:
	var cat := _fresh()
	_register(cat, "ramza")
	_register(cat, "g1")
	cat.add_owned("ramza")
	cat.add_owned("g1")
	_true(cat.is_owned("ramza"), "ramza owned after add_owned")
	_true(cat.is_owned("g1"), "g1 owned after add_owned")
	_eq(cat.owned_slugs(), ["ramza", "g1"], "owned_slugs preserves insertion order")
	_eq(_owned_slugs_of(cat), ["ramza", "g1"], "owned_units resolve in order")


# --- Slice B3: add_owned is idempotent (a re-fold must not duplicate) ---
func _test_add_owned_idempotent() -> void:
	var cat := _fresh()
	_register(cat, "ramza")
	cat.add_owned("ramza")
	cat.add_owned("ramza")
	_eq(cat.owned_slugs(), ["ramza"], "add_owned twice = one entry")


# --- Slice B4: remove_owned drops the slug from the overlay ---
func _test_remove_owned() -> void:
	var cat := _fresh()
	_register(cat, "ramza")
	_register(cat, "g1")
	cat.add_owned("ramza")
	cat.add_owned("g1")
	cat.remove_owned("g1")
	_eq(cat.owned_slugs(), ["ramza"], "remove_owned drops g1")
	_true(not cat.is_owned("g1"), "g1 no longer owned")


# --- Slice B5: owned_units resolves only registered identities (overlay is decoupled) ---
func _test_owned_units_skips_unregistered() -> void:
	var cat := _fresh()
	_register(cat, "ramza")
	cat.add_owned("ramza")
	cat.add_owned("ghost")  # never registered
	_eq(cat.owned_slugs(), ["ramza", "ghost"], "owned_slugs keeps the raw overlay")
	_eq(_owned_slugs_of(cat), ["ramza"], "owned_units skips the unresolvable slug")


# --- Slice B6: class is DERIVED from owned × team_color, never stored ---
func _test_classify_derives_from_owned_and_team() -> void:
	var cat := _fresh()
	_register(cat, "ramza")
	cat.add_owned("ramza")
	# owned → player regardless of team color.
	_eq(cat.classify("ramza", 0), "player", "owned Blue → player")
	# not-owned Blue (team_color 0) → guest (Delita).
	_eq(cat.classify("delita", 0), "guest", "not-owned Blue → guest")
	# not-owned non-Blue → enemy.
	_eq(cat.classify("thief", 1), "enemy", "not-owned Red → enemy")


# --- Slice B7: reset_to_new_game clears the overlay (the fold re-seeds it each boot) ---
func _test_reset_clears_owned_overlay() -> void:
	var cat := _fresh()
	_register(cat, "ramza")
	cat.add_owned("ramza")
	cat.reset_to_new_game()
	_eq(cat.owned_slugs(), [], "reset clears owned overlay")
