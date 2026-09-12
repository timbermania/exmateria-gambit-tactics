extends Node
## Pure-logic guard (no scene/VM/GPU) for [CatalogueReplay] — the ADR-0201 replay
## engine that folds a beat-keyed mutation script into Catalog membership. Tested
## against a FAKE catalogue (a bare slug->Character dict with register/unregister),
## so `create`/`join` add and `leave`/`die` remove with no live Catalog or scene.
##
## Covers: create/join add a slug; leave/die remove it; folding to N is exactly the
## union of deltas 0..N-1; an empty script is a no-op; re-folding to the same target
## is idempotent; folding to N then continuing to M>N equals folding straight to M.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/CatalogueReplayTest.tscn

const CharacterClass = ExMateriaCatalogue.Character
const CatalogueReplay = ExMateriaCatalogue.CatalogueReplay
var _passed: int = 0
var _failed: int = 0


# A fake catalogue: the minimal duck-typed surface CatalogueReplay writes
# (register/unregister), plus a sorted `slugs()` view for the assertions.
class FakeCatalogue:
	var chars: Dictionary = {}
	func register(character) -> void:
		chars[character.slug] = character
	func unregister(slug: String) -> void:
		chars.erase(slug)
	func has(slug: String) -> bool:
		return chars.has(slug)
	func slugs() -> Array:
		var out: Array = chars.keys()
		out.sort()
		return out


func _ready() -> void:
	_test_create_join_add_leave_die_remove()
	_test_fold_to_n_is_union_of_prior_beats()
	_test_empty_script_is_noop()
	_test_refold_same_target_is_idempotent()
	_test_fold_then_continue_equals_fold_straight()
	_test_delta_slug_overrides_source_identity()

	print("\n=== CatalogueReplayTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] CatalogueReplayTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] CatalogueReplayTest")
		get_tree().quit(1)
	else:
		print("[PASS] CatalogueReplayTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


# A 5-beat script exercising every op. Membership after fold(N):
#   fold(0) = {}
#   fold(1) = {ramza, delita}
#   fold(2) = {ramza, delita, agrias}
#   fold(3) = {ramza, agrias}          (delita died)
#   fold(4) = {ramza}                  (agrias left)
#   fold(5) = {ramza}
func _script() -> Array:
	return [
		{"kind": "scenario", "mutations": [
			{"op": "create", "slug": "ramza"}, {"op": "create", "slug": "delita"}]},
		{"kind": "opener", "mutations": [{"op": "join", "slug": "agrias"}]},
		{"kind": "combat", "mutations": [{"op": "die", "slug": "delita"}]},
		{"kind": "victory", "mutations": [{"op": "leave", "slug": "agrias"}]},
		{"kind": "scenario", "mutations": []},
	]


func _test_create_join_add_leave_die_remove() -> void:
	var cat := FakeCatalogue.new()
	CatalogueReplay.apply_action({"mutations": [{"op": "create", "slug": "gafgarion"}]}, cat)
	_true(cat.has("gafgarion"), "create adds slug")
	CatalogueReplay.apply_action({"mutations": [{"op": "join", "slug": "agrias"}]}, cat)
	_true(cat.has("agrias"), "join adds slug")
	CatalogueReplay.apply_action({"mutations": [{"op": "leave", "slug": "gafgarion"}]}, cat)
	_true(not cat.has("gafgarion"), "leave removes slug")
	CatalogueReplay.apply_action({"mutations": [{"op": "die", "slug": "agrias"}]}, cat)
	_true(not cat.has("agrias"), "die removes slug")


func _test_fold_to_n_is_union_of_prior_beats() -> void:
	var script := _script()
	var expected := [
		[],
		["delita", "ramza"],
		["agrias", "delita", "ramza"],
		["agrias", "ramza"],
		["ramza"],
		["ramza"],
	]
	for n in range(expected.size()):
		var cat := FakeCatalogue.new()
		CatalogueReplay.fold(script, n, cat)
		_eq(cat.slugs(), expected[n], "fold(%d) membership" % n)


func _test_empty_script_is_noop() -> void:
	var cat := FakeCatalogue.new()
	CatalogueReplay.fold([], 0, cat)
	CatalogueReplay.fold([], 5, cat)  # out-of-range clamps; still a no-op
	_eq(cat.slugs(), [], "empty script folds to empty catalogue")


func _test_refold_same_target_is_idempotent() -> void:
	var script := _script()
	var cat := FakeCatalogue.new()
	CatalogueReplay.fold(script, 3, cat)
	var once := cat.slugs()
	# Re-fold onto the SAME catalogue (register/unregister are set-ops) — membership
	# is unchanged (the seek path always resets first; this proves the fold is safe).
	CatalogueReplay.fold(script, 3, cat)
	_eq(cat.slugs(), once, "re-folding to the same target is idempotent")
	_eq(once, ["agrias", "ramza"], "fold(3) membership as expected")


func _test_fold_then_continue_equals_fold_straight() -> void:
	var script := _script()
	var stepped := FakeCatalogue.new()
	CatalogueReplay.fold(script, 2, stepped)
	CatalogueReplay.fold(script, 5, stepped)  # continue on to the end
	var direct := FakeCatalogue.new()
	CatalogueReplay.fold(script, 5, direct)
	_eq(stepped.slugs(), direct.slugs(), "fold(2)->fold(5) == fold(5)")


func _test_delta_slug_overrides_source_identity() -> void:
	# A pre-built Character is registered under the delta's slug (the script names the
	# global identity), not whatever the source object carried.
	var cat := FakeCatalogue.new()
	var pre := CharacterClass.new("stale", "Guest")
	CatalogueReplay.apply_action({"mutations": [
		{"op": "create", "slug": "delita", "character": pre}]}, cat)
	_true(cat.has("delita"), "delta slug is the registered identity")
	_true(not cat.has("stale"), "source object's own slug does not leak in")
