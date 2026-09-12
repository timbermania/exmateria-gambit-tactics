extends Node3D
# test-kind: logic
# seeded-break: Character.create_default's provenance default parameter flips from Provenance.PLAYER to Provenance.FIXED - the roster-seeding factory mints Fixed (non-renamable) Characters; 'roster entries are Player-owned' + 'Player Character is renamable' RED (expected 1 got 0 / expected true); the 62 other asserts stay green (the owned overlay folds in via GarilandMutationScript's explicit deltas, not this default; serialization/join-delta/reset/resolver cases are provenance-agnostic); GREEN unbroken on the reverted tree

## TDD guard for the Character-backed player population (ADR-0066, ADR-0180).
##
## A `Character` IS the durable unit record: it owns its identity (slug/display
## name/authored gender + name provenance) and references the durable
## `UnitProgression`/`GambitList` the live `Unit` binds by reference (no copy-back —
## ADR-0005). It lives in the `CharacterCatalog`, and the player's deployable subset
## is the catalogue's OWNED OVERLAY, established by folding a `MutationScript`
## through `CatalogueReplay`.
##
## WHAT MOVED. This file used to test the same claims against the `PartyRoster`
## autoload — `get_character(index)` as the read seam, `<side>:<index>` promotion,
## `add_unit`/`remove_unit`/`reset_roster`. ADR-0180 deleted that store, so each
## roster-shaped case is re-pointed at the mechanism that replaced it, and ONE is
## simply gone: `remove_unit` re-slugging its survivors guarded a failure mode
## (index-derived slugs going stale when the list shifts) that cannot exist once
## identity is a slug rather than a position. ADR-0066 dec. 4 had already ruled
## against positional slugs; deleting the store is what finally made it true.
##
## The flat `to_dict`/`from_dict` schema is untouched and is still pinned here — it
## is the Character's own serialization, not the retired save file's.
##
## (Zodiac is listed in #163 but is not modelled by UnitProgression/roster today,
## so "roster parity" excludes it — see the ADR note.)
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CharacterRosterParityTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase

const CharacterClass = ExMateriaCatalogue.Character
const CatalogueReplay = ExMateriaCatalogue.CatalogueReplay
const CharacterTemplateResolver = ExMateriaCatalogue.CharacterTemplateResolver
var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_seed_owned_overlay()
	_test_create_default_builds_owned_identity_and_progression()
	_test_provenance_gates_renaming()
	_test_overlay_entries_are_catalog_entries()
	_test_rename_reflects_through_shared_character()
	_test_serialization_roundtrip_and_rename_persist()
	_test_serialization_covers_representative_dicts()
	_test_legacy_dict_loads_unpromoted()
	_test_from_dict_tolerates_present_null_fields()
	_test_to_dict_tolerates_null_progression()
	_test_a_join_delta_registers_and_owns()
	_test_spawn_visuals_route_through_resolver()
	_test_reset_clears_the_overlay()  # destructive to the live catalogue — keep last

	print("\n=== CharacterRosterParityTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CharacterRosterParityTest")
		get_tree().quit(1)
	else:
		print("[PASS] CharacterRosterParityTest")
		get_tree().quit(0)


## create_default is the roster-seeding factory: it builds a Character that OWNS
## a fresh progression (job/gender/starting weapon) + gambit list, with an empty
## slug (assigned at promotion). Its progression is a real, editable object — the
## same one the live Unit will bind by reference.
func _test_create_default_builds_owned_identity_and_progression() -> void:
	var c: CharacterClass = CharacterClass.create_default("Marcus", "4c", false)  # Male Knight
	_assert_eq(c.display_name, "Marcus", "create_default sets the display name")
	_assert_eq(c.slug, "", "slug is empty until Catalog promotion")
	_assert_eq(c.provenance, CharacterClass.Provenance.PLAYER, "roster entries are Player-owned")
	_assert_true(c.progression != null, "seeds a progression")
	_assert_true(c.gambits != null, "seeds a gambit list")
	_assert_eq(c.progression.current_job_id, "4c", "progression carries the job")
	_assert_true(not c.is_female, "male authored gender")
	# The progression is owned + mutable (edits are seen on the same object later).
	c.progression.brave = 71
	_assert_eq(c.progression.brave, 71, "progression is a live, editable object")

	# Female flips the authored gender bit (and the female base stats).
	var f: CharacterClass = CharacterClass.create_default("Elena", "4a", true)
	_assert_true(f.is_female, "female authored gender")


## Name provenance decides editability (ADR-0066 dec.11): a Player Character is
## renamable, a Fixed one is not. Roster entries are Player-owned.
func _test_provenance_gates_renaming() -> void:
	var player: CharacterClass = CharacterClass.create_default("Generic", "4a", false)
	_assert_true(player.is_renameable(), "Player Character is renamable")
	var fixed := CharacterClass.new("agrias", "Agrias", CharacterClass.Provenance.FIXED)
	_assert_true(not fixed.is_renameable(), "Fixed Character is not renamable")


## Establish the player population the way production does: fold the Gariland owned
## seed through [CatalogueReplay]. Nothing else mints it — there is no store that
## seeds itself at boot any more, which is the whole of ADR-0180.
func _seed_owned_overlay() -> void:
	if CharacterCatalog.owned_units().is_empty():
		CatalogueReplay.apply_action(
			{"mutations": GarilandMutationScript.owned_seed_deltas()}, CharacterCatalog)


## An owned-overlay entry IS the Catalog entry — one object, one identity. The
## overlay is an ORDER OF SLUGS over the catalogue, not a second store holding second
## copies; that inversion (a store that promoted ITSELF into the catalogue under
## positional `party:N` slugs) is what ADR-0180 deleted.
func _test_overlay_entries_are_catalog_entries() -> void:
	var owned: Array = CharacterCatalog.owned_units()
	_assert_true(owned.size() > 0, "the owned overlay has units")
	if owned.is_empty():
		return
	var c: CharacterClass = owned[0]
	_assert_eq(c.slug, GarilandMutationScript.RAMZA_SLUG,
		"the overlay is ORDERED — the protagonist leads it (deploy order)")
	_assert_true(c == CharacterCatalog.get_character(c.slug),
		"the overlay entry IS the Catalog entry (same object)")
	_assert_true(c.progression != null, "the overlay entry carries a progression")
	_assert_true(CharacterCatalog.is_owned(c.slug), "and is marked owned")
	# The slug is an identity, not a position. Nothing named `party:0` exists.
	_assert_true(CharacterCatalog.get_character("party:0") == null,
		"no positional `party:N` slug survives (ADR-0066 dec. 4, ADR-0180)")


## A rename through the canonical seam (CharacterCatalog.set_display_name) is
## seen on the roster Character directly — the name is single-owned, so
## roster/menus/dialogue all read one value.
func _test_rename_reflects_through_shared_character() -> void:
	var owned: Array = CharacterCatalog.owned_units()
	if owned.is_empty():
		return
	var c: CharacterClass = owned[0]
	var slug: String = c.slug
	var original: String = c.display_name
	CharacterCatalog.set_display_name(slug, "Renamed")
	_assert_eq(c.display_name, "Renamed", "the owned Character reflects a catalog rename")
	_assert_eq(CharacterCatalog.display_name(slug), "Renamed", "catalog reflects the rename")
	CharacterCatalog.set_display_name(slug, original)  # restore shared autoload state
	_assert_eq(c.display_name, original, "rename restored")


## The flat JSON schema is unchanged (no slug key); a round-trip preserves the
## fields, and a renamed Character serializes its CURRENT name so a rename
## survives save/load.
func _test_serialization_roundtrip_and_rename_persist() -> void:
	var c: CharacterClass = CharacterClass.create_default("Wiegraf", "4c", false)
	c.progression.level = 7
	var d := c.to_dict()
	_assert_eq(d.get("unit_name"), "Wiegraf", "to_dict serializes the name")
	_assert_true(not d.has("slug"), "flat schema unchanged (no slug key)")
	var back: CharacterClass = CharacterClass.from_dict(d)
	_assert_eq(back.display_name, "Wiegraf", "from_dict restores the name")
	_assert_eq(back.progression.level, 7, "from_dict restores level")

	c.display_name = "Velius"
	_assert_eq(c.to_dict().get("unit_name"), "Velius", "to_dict serializes the renamed name")


## from_dict → to_dict is an idempotent, field-preserving round-trip across a
## male human, a female human, and a female-flagged monster (whose base_stat_type
## is MONSTER yet whose raw is_female must survive byte-for-byte).
func _test_serialization_covers_representative_dicts() -> void:
	var dicts := [
		{"unit_name": "Wiegraf", "is_female": false, "current_job_id": "4c",
			"level": 7, "brave": 71, "faith": 42, "weapon_id": 19,
			"learned_abilities": [10, 22]},
		{"unit_name": "Sera", "is_female": true, "current_job_id": "4b", "level": 3},
		{"unit_name": "Cuar", "is_female": true, "current_job_id": "60", "level": 5},
	]
	for d in dicts:
		var rt: Dictionary = CharacterClass.from_dict(d).to_dict()
		var rt2: Dictionary = CharacterClass.from_dict(rt).to_dict()
		_assert_eq(rt.hash(), rt2.hash(), "round-trip is idempotent for %s" % d["unit_name"])
		_assert_eq(rt.get("unit_name"), d["unit_name"], "name preserved for %s" % d["unit_name"])
		_assert_eq(rt.get("is_female"), d["is_female"], "raw is_female preserved for %s" % d["unit_name"])
		_assert_eq(rt.get("current_job_id"), d["current_job_id"], "job preserved for %s" % d["unit_name"])


## A legacy save (flat keys, no slug) still loads into a Character; it is
## unpromoted (empty slug) until the roster registers it.
func _test_legacy_dict_loads_unpromoted() -> void:
	var legacy := {"unit_name": "Legacy", "is_female": true, "current_job_id": "4f", "level": 3}
	var e: CharacterClass = CharacterClass.from_dict(legacy)
	_assert_eq(e.display_name, "Legacy", "legacy dict name loads")
	_assert_eq(e.progression.current_job_id, "4f", "legacy job loads")
	_assert_eq(e.slug, "", "loaded Character is unpromoted until the roster slugs it")


## A corrupted / hand-edited save can carry a key present with an explicit null
## value. Dictionary.get's default only fires on an ABSENT key, so from_dict must
## coalesce null -> default rather than assign Nil to a typed field — otherwise
## from_dict crashes mid-build and the whole side's roster silently reverts to
## the blank starter, discarding the loaded party.
func _test_from_dict_tolerates_present_null_fields() -> void:
	var corrupt := {
		"unit_name": null, "is_female": null, "current_job_id": null,
		"level": null, "brave": null, "job_levels": null, "job_jp": null,
		"learned_abilities": null, "equipped_action_set": null,
		"weapon_id": null, "gambits_data": null,
	}
	var c: CharacterClass = CharacterClass.from_dict(corrupt)
	_assert_true(c != null, "from_dict survives present-null fields (no Nil-assign crash)")
	if c == null:
		return
	_assert_eq(c.display_name, "Unnamed", "null unit_name falls back to default")
	_assert_true(not c.is_female, "null is_female falls back to false")
	_assert_true(c.progression != null, "progression built despite null fields")
	if c.progression == null:
		return
	_assert_eq(c.progression.current_job_id, "4a", "null current_job_id falls back to 4a")
	_assert_eq(c.progression.level, 1, "null level falls back to 1")
	_assert_true(c.gambits != null, "null gambits_data yields an empty gambit list")


## The bare `Character.new(...)` constructor leaves `progression == null` (only
## create_default / from_dict seed one). If such a Character reaches units[] and
## the roster is saved, to_dict() must not nil-deref its progression — it should
## still emit a valid identity dict rather than crash the whole save.
func _test_to_dict_tolerates_null_progression() -> void:
	var bare := CharacterClass.new("", "Nameless")  # no progression seeded
	_assert_true(bare.progression == null, "bare constructor leaves progression null")
	var d: Dictionary = bare.to_dict()
	_assert_true(d != null and d.has("unit_name"), "to_dict returns a dict, no crash")
	_assert_eq(d.get("unit_name"), "Nameless", "identity still serialized without a progression")


## A unit recruited after boot arrives as a `join`/`create` delta with `own: true` —
## the ONE mutation seam that grows the player population now that `add_unit` is gone.
## It must both REGISTER the identity and mark it owned; a delta that registers
## without owning is a story guest (Delita), and the two are not the same thing.
func _test_a_join_delta_registers_and_owns() -> void:
	var before: int = CharacterCatalog.owned_slugs().size()
	var recruit: CharacterClass = CharacterClass.create_default("Recruit", "4a", false)
	CatalogueReplay.apply_action({"mutations": [
		{"op": "join", "slug": _RECRUIT_SLUG, "character": recruit, "own": true},
	]}, CharacterCatalog)
	var c = CharacterCatalog.get_character(_RECRUIT_SLUG)
	_assert_true(c != null, "a join delta registers the recruit in the Catalog")
	if c == null:
		return
	_assert_true(c == recruit, "the recruited Character IS the Catalog entry")
	_assert_true(CharacterCatalog.is_owned(_RECRUIT_SLUG), "`own: true` marks it owned")
	_assert_eq(CharacterCatalog.owned_slugs().size(), before + 1, "the overlay grew by one")
	_assert_eq(recruit.display_name, "Recruit", "recruit name resolves through its Character")

	# A guest joins WITHOUT owning — registered, deployable by nobody.
	CatalogueReplay.apply_action({"mutations": [
		{"op": "join", "slug": _GUEST_SLUG, "character":
			CharacterClass.create_default("Guest", "4a", false)},
	]}, CharacterCatalog)
	_assert_true(CharacterCatalog.get_character(_GUEST_SLUG) != null, "the guest registers")
	_assert_true(not CharacterCatalog.is_owned(_GUEST_SLUG),
		"a join without `own` is a GUEST — registered, not owned")

	CharacterCatalog.remove_owned(_RECRUIT_SLUG)
	CharacterCatalog.unregister(_RECRUIT_SLUG)
	CharacterCatalog.unregister(_GUEST_SLUG)


## Probe slugs that cannot collide with the real cast.
const _RECRUIT_SLUG := "__parity_probe_recruit"
const _GUEST_SLUG := "__parity_probe_guest"


## `reset_to_new_game()` is the reset seam the F3 debug action drives. The overlay is
## PER-RUN seed state — the mutation fold re-establishes it each boot/seek — so a reset
## must CLEAR it rather than rebuild it in place, or a re-seek accumulates the prior
## run's owned set on top of the new one. Destructive to the live catalogue: last.
##
## The old case here asserted the opposite shape (that a reset must RE-PROMOTE the
## rebuilt entries under `party:N`, or renames would read a stale detached object).
## That whole failure mode was a property of a store that owned its own copies.
func _test_reset_clears_the_overlay() -> void:
	_assert_true(CharacterCatalog.owned_units().size() > 0, "the overlay is populated first")
	CharacterCatalog.reset_to_new_game()
	_assert_eq(CharacterCatalog.owned_slugs().size(), 0,
		"reset_to_new_game clears the owned overlay — it is per-run seed state")

	# ...and a re-fold re-establishes it, which is what a boot or a seek does.
	CatalogueReplay.apply_action(
		{"mutations": GarilandMutationScript.owned_seed_deltas()}, CharacterCatalog)
	_assert_true(CharacterCatalog.owned_units().size() > 0,
		"re-folding the seed re-establishes the overlay")
	_assert_true(CharacterCatalog.is_owned(GarilandMutationScript.RAMZA_SLUG),
		"and the protagonist is owned again")


## ADR-0072 seam: the spawn path does not compute the body sprite inline — it goes
## through CharacterTemplateResolver ([UnitSpawn.build] is its one caller). A live owned
## Character must resolve to exactly the value the job table gives today (JobDatabase),
## so the seam is a pure refactor with no visual change.
##
## THE PALETTE ROW IS NOT ON THIS SEAM ANY MORE (#1071, ADR-0272) — it left the dict,
## so asserting it here would compare `null` to an int. Its parity for the same jobs is
## taken in [CharacterTemplateResolverTest] and [CombatBodyPaletteRowTest], which
## exercise the route the spawn path now uses.
func _test_spawn_visuals_route_through_resolver() -> void:
	var owned: Array = CharacterCatalog.owned_units()
	_assert_true(owned.size() > 1, "the overlay has a generic to resolve")
	if owned.size() < 2:
		return
	var c: CharacterClass = owned[1]   # a job-routed generic, not the unique protagonist
	var job: String = c.progression.current_job_id
	var r := CharacterTemplateResolver.resolve(c)
	_assert_eq(r.get("body_sprite_id"), JobDatabase.get_sprite_id(job, c.is_female),
		"resolver sprite id == today's job-table lookup")
	_assert_true(not r.has("body_palette_row"),
		"and the resolver answers no palette row — it is the rig's, not this seam's")


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
