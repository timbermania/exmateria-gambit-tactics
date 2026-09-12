extends Node
## Pure-logic guard (no scene/VM/GPU) for [SlugBinding] — the ADR-0201 identity
## resolver that lifts a battle-local `(context, uid)` to a global `slug`, with an
## ENTD-slot fallback. Tested against a FAKE catalogue (a bare slug->Character dict
## with `get_character`); the miss path builds a real Character via
## [Character.from_entd_slot] against the shared X-databases (still no scene/render).
##
## Covers: `(context, uid) -> slug` is context-local (same `uid`, two contexts,
## different slugs); a hit returns the catalogue Character; a miss falls back to
## ENTD-slot construction and is recorded; a registered special resolves to its
## canonical slug; the coverage set is deduped and queryable.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/SlugBindingTest.tscn

const CharacterClass = ExMateriaCatalogue.Character
const SlugBinding = ExMateriaCatalogue.SlugBinding
# Canonical special_name ids from unit_names.json (see EntdBattleInitTest): 4 = Delita,
# 30 = Agrias, 0xFF = empty/no-special (a factory generic).
const SPECIAL_DELITA := 4
const SPECIAL_AGRIAS := 30

var _passed: int = 0
var _failed: int = 0


# A fake catalogue: the minimal surface SlugBinding reads (get_character), plus a
# helper to seed it.
class FakeCatalogue:
	var chars: Dictionary = {}
	func add(character) -> void:
		chars[character.slug] = character
	func get_character(slug: String):
		return chars.get(slug, null)


func _ready() -> void:
	_test_slug_is_context_local()
	_test_special_resolves_without_explicit_binding()
	_test_hit_returns_catalogue_character()
	_test_miss_falls_back_and_records()
	_test_registered_special_resolves_to_canonical()
	_test_fallback_set_is_deduped()

	print("\n=== SlugBindingTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] SlugBindingTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] SlugBindingTest")
		get_tree().quit(1)
	else:
		print("[PASS] SlugBindingTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


# A generic (no special) ENTD slot — from_entd_slot builds a Player-provenance unit.
func _generic_slot(uid: int) -> Dictionary:
	return {"unit_id": uid, "special_name": 0xFF, "job": 0x4a, "sprite_set": 0x80}


func _test_slug_is_context_local() -> void:
	var b := SlugBinding.new()
	b.bind(387, 3, "delita")
	b.bind(390, 3, "agrias")
	_eq(b.slug_for(387, 3), "delita", "context 387 uid 3 -> delita")
	_eq(b.slug_for(390, 3), "agrias", "same uid 3, context 390 -> agrias")
	_eq(b.slug_for(999, 3), "", "unbound context -> empty slug")


func _test_special_resolves_without_explicit_binding() -> void:
	var b := SlugBinding.new()
	# No explicit bind: a canonical special_name resolves through UnitNames.
	var slot := {"unit_id": 5, "special_name": SPECIAL_AGRIAS}
	_eq(b.resolve_slug(400, 5, slot), "agrias", "special_name 30 -> agrias slug")
	# An explicit binding still wins over the special.
	b.bind(400, 5, "override")
	_eq(b.resolve_slug(400, 5, slot), "override", "explicit binding overrides special")


func _test_hit_returns_catalogue_character() -> void:
	var cat := FakeCatalogue.new()
	var delita := CharacterClass.new("delita", "Delita", CharacterClass.Provenance.FIXED)
	cat.add(delita)
	var b := SlugBinding.new()
	b.bind(387, 3, "delita")
	var got = b.resolve_character(387, 3, {"unit_id": 3, "special_name": SPECIAL_DELITA}, cat)
	_true(got == delita, "hit returns the exact catalogue Character")
	_eq(b.fallback_count(), 0, "a hit records no coverage gap")


func _test_miss_falls_back_and_records() -> void:
	var cat := FakeCatalogue.new()  # empty — every slug misses
	var b := SlugBinding.new()
	var got = b.resolve_character(999, 7, _generic_slot(7), cat)
	_true(got != null, "miss still yields a Character")
	_eq(got.provenance, CharacterClass.Provenance.PLAYER, "miss built a generic via from_entd_slot")
	_eq(b.fallback_count(), 1, "the miss is recorded as a coverage gap")
	_true(b.has_fallback(999, 7), "the fallen-back (context, uid) is queryable")


func _test_registered_special_resolves_to_canonical() -> void:
	# A special with NO explicit binding still binds to the catalogue via its canonical
	# slug — named/special units bind first (ADR-0201 dec.7).
	var cat := FakeCatalogue.new()
	var agrias := CharacterClass.new("agrias", "Agrias", CharacterClass.Provenance.FIXED)
	cat.add(agrias)
	var b := SlugBinding.new()
	var got = b.resolve_character(400, 5, {"unit_id": 5, "special_name": SPECIAL_AGRIAS}, cat)
	_true(got == agrias, "registered special resolves to its canonical Character")
	_eq(b.fallback_count(), 0, "no coverage gap for a bound special")


func _test_fallback_set_is_deduped() -> void:
	var cat := FakeCatalogue.new()
	var b := SlugBinding.new()
	b.resolve_character(999, 7, _generic_slot(7), cat)
	b.resolve_character(999, 7, _generic_slot(7), cat)  # same slot again
	_eq(b.fallback_count(), 1, "the same (context, uid) is recorded once")
	b.resolve_character(999, 8, _generic_slot(8), cat)
	_eq(b.fallback_count(), 2, "a different uid is a distinct gap")


