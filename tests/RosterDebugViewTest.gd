extends Node
## Pure-logic guard for [RosterDebugView] — the read-only view-model behind the two F3
## ROSTER debug panels (the "Universe" catalogue view + the "Battle Binding" view). No
## scene / autoload coupling: it builds display rows from plain Character + SlugBinding
## inputs, so both panels can render live state without embedding lookup logic.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/RosterDebugViewTest.tscn

const RosterDebugView = ExMateriaCatalogue.RosterDebugView
const CharacterClass = ExMateriaCatalogue.Character
const SlugBinding = ExMateriaCatalogue.SlugBinding
var _passed: int = 0
var _failed: int = 0


# A minimal duck-typed catalogue: get_character(slug) -> Character or null.
class FakeCatalogue:
	var by_slug: Dictionary = {}
	func add(c) -> void: by_slug[c.slug] = c
	func get_character(slug: String): return by_slug.get(slug, null)


func _ready() -> void:
	_test_universe_rows()
	_test_binding_rows_hit_and_fallback()
	_test_binding_rows_excludes_absent_units()
	_test_binding_summary()

	print("\n=== RosterDebugViewTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] RosterDebugViewTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] RosterDebugViewTest"); get_tree().quit(1)
	else:
		print("[PASS] RosterDebugViewTest"); get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want: _passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])

func _true(c: bool, name: String) -> void: _eq(c, true, name)


func _test_universe_rows() -> void:
	# The persistent catalogue "universe": mixed provenance + roster-prefixed slugs.
	var ramza := CharacterClass.new("ramza", "Ramza", CharacterClass.Provenance.PLAYER)
	var delita := CharacterClass.new("delita", "Delita", CharacterClass.Provenance.FIXED)
	var party0 := CharacterClass.new("party:0", "Ainsley", CharacterClass.Provenance.PLAYER)
	# Unsorted input; the view must sort by slug for a stable display.
	var rows: Array = RosterDebugView.build_universe_rows([delita, party0, ramza])

	_eq(rows.size(), 3, "universe: one row per character")
	if rows.size() != 3: return
	_eq(String(rows[0].get("slug")), "delita", "universe: sorted by slug (row0)")
	_eq(String(rows[1].get("slug")), "party:0", "universe: sorted by slug (row1)")
	_eq(String(rows[2].get("slug")), "ramza", "universe: sorted by slug (row2)")
	_eq(String(rows[0].get("provenance")), "FIXED", "universe: FIXED provenance string")
	_eq(String(rows[2].get("provenance")), "PLAYER", "universe: PLAYER provenance string")
	# Roster membership is derived from the slug namespace (ADR-0066 party:N/enemy:N).
	_eq(String(rows[1].get("group")), "party", "universe: party:N slug → party group")
	_eq(String(rows[0].get("group")), "story", "universe: bare slug → story group")


func _test_binding_rows_hit_and_fallback() -> void:
	var ctx := 388  # Gariland ENTD index (the context key)
	var cat := FakeCatalogue.new()
	cat.add(CharacterClass.new("ramza", "Ramza", CharacterClass.Provenance.PLAYER))
	var binding := SlugBinding.new()
	binding.bind(ctx, 2, "ramza")   # slot uid 2 explicitly bound to a catalogued slug → HIT

	var present := {"always_present": true}
	var slots := [
		{"unit_id": 2, "special_name": 0xFF, "team_color": 0, "team_color_name": "Blue", "x": 5, "y": 7, "flags2_decoded": present},
		{"unit_id": 9, "special_name": 0xFF, "team_color": 3, "team_color_name": "Red", "flags2_decoded": present},  # unbound → FALLBACK
		{"unit_id": 0xFF, "special_name": 0xFF, "team_color": 0, "flags2_decoded": present},                          # EMPTY → skipped
	]
	var rows: Array = RosterDebugView.build_binding_rows(slots, ctx, binding, cat)

	_eq(rows.size(), 2, "binding: empty slots skipped")
	if rows.size() != 2: return
	_eq(int(rows[0].get("uid")), 2, "binding: row0 uid")
	# "units bound to certain spots" — the row carries the ENTD tile position.
	_eq(int(rows[0].get("x")), 5, "binding: row carries slot x")
	_eq(int(rows[0].get("y")), 7, "binding: row carries slot y")
	_true(bool(rows[0].get("bound")), "binding: uid2 resolves to a catalogue Character (HIT)")
	_eq(String(rows[0].get("name")), "Ramza", "binding: HIT shows the catalogue display name")
	_eq(String(rows[0].get("slug")), "ramza", "binding: HIT shows the resolved slug")
	_true(not bool(rows[1].get("bound")), "binding: uid9 has no slug → FALLBACK")
	_true(bool(rows[1].get("fallback")), "binding: uid9 flagged as coverage gap")

	# The view must NOT mutate the live binding's coverage log (read-only inspection).
	_eq(binding.fallback_count(), 0, "binding: view does not record fallbacks on the live binding")


# always_present==false ENTD slots (cutscene / alternate-version entries — e.g. the Orbonne
# Delita dups + control-dups) are NOT deployed at battle start, so the binding view must
# exclude them, mirroring the combat-cast gate in NavigatorMain._build_frozen_combat_loop. Without
# this the panel lists phantom units that never take the field.
func _test_binding_rows_excludes_absent_units() -> void:
	var ctx := 387  # Orbonne
	var cat := FakeCatalogue.new()
	var binding := SlugBinding.new()
	var slots := [
		{"unit_id": 2, "special_name": 0x02, "team_color": 0, "team_color_name": "Blue",
			"flags2_decoded": {"always_present": true}},   # deployed → kept
		{"unit_id": 5, "special_name": 0x05, "team_color": 3, "team_color_name": "Red",
			"flags2_decoded": {"always_present": false}},  # cutscene Delita → excluded
		{"unit_id": 4, "special_name": 0x04, "team_color": 0,
			"flags2_decoded": {}},                          # missing flag → treated absent, excluded
	]
	var rows: Array = RosterDebugView.build_binding_rows(slots, ctx, binding, cat)
	_eq(rows.size(), 1, "binding: only always_present slots kept")
	if rows.size() == 1:
		_eq(int(rows[0].get("uid")), 2, "binding: the kept row is the deployed unit")
	var s: Dictionary = RosterDebugView.binding_summary(slots, ctx, binding, cat)
	_eq(int(s.get("total")), 1, "summary: absent units excluded from totals")


func _test_binding_summary() -> void:
	var ctx := 388
	var cat := FakeCatalogue.new()
	cat.add(CharacterClass.new("ramza", "Ramza", CharacterClass.Provenance.PLAYER))
	var binding := SlugBinding.new()
	binding.bind(ctx, 2, "ramza")
	var present := {"always_present": true}
	var slots := [
		{"unit_id": 2, "special_name": 0xFF, "team_color": 0, "flags2_decoded": present},
		{"unit_id": 9, "special_name": 0xFF, "team_color": 3, "flags2_decoded": present},
		{"unit_id": 4, "special_name": 0xFF, "team_color": 3, "flags2_decoded": present},
	]
	var s: Dictionary = RosterDebugView.binding_summary(slots, ctx, binding, cat)
	_eq(int(s.get("total")), 3, "summary: total non-empty slots")
	_eq(int(s.get("bound")), 1, "summary: bound count")
	_eq(int(s.get("fallback")), 2, "summary: fallback count")
