extends Node
## Pure-logic guard for a unique Character's Form set and the deploy-seam Form
## SELECTION (ADR-0079). A roster-deployed unique carries its ROM-derived Form set
## (its chapter incarnations, seeded at mint); the deploy seam SELECTS the active
## Form for the current story context and materializes its `special_name`. A miss
## (no Form for that context, or no Form set at all) yields `SPECIAL_NAME_NONE`,
## which job-routes — that is how a generic stays generic.
##
## Independent source of truth: `assets/scenarios/template_residue.json` records
## Ramza's three Forms as `special_name` 1/2/3 (Ch1 `ramza_1`, Ch2-3 `ramza_2`,
## Ch4 `ramza_3`). This test hand-authors a Form set in that shape and asserts the
## selection materializes the right byte — it does NOT recompute it from the code.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/CharacterFormSetTest.tscn

const CharacterClass = ExMateriaCatalogue.Character
const CharacterTemplateResolver = ExMateriaCatalogue.CharacterTemplateResolver
const StoryScript = preload("res://src/scenarios/StoryMutationScript.gd")

## Ramza's three chapter Forms, ROM-derived (template_residue.json): Ch1 -> 1.
const RAMZA_CH1_SPECIAL_NAME := 1

## The folder that `special_name` 1 addresses — the independent half of the assertion, read
## off the same hand-authored residue (`{"1": "ramza_1"}`) rather than recomputed.
const RAMZA_CH1_TEMPLATE_FOLDER := "res://assets/characters/templates/ramza_1/"

## Delita's Ch1 `special_name` (residue `{"4": "delita_4"}`) — any real unique byte works
## for the no-Form-set guard; a ROM-true one keeps the case readable.
const DELITA_CH1_SPECIAL_NAME := 4

## The slug the Gariland seed mints the protagonist under.
const RAMZA_SLUG := "ramza"

## The scenario the composed case boots. Any scenario composes the same owned side (it is
## the catalogue's, not the ENTD's); 4 is the one the defect was reported on.
const SCENARIO_WITH_AN_OWNED_UNIQUE := 4

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_unique_selects_active_form_special_name()
	_test_missing_form_for_context_is_none()
	_test_empty_form_set_is_none()
	_test_ramza_is_minted_with_his_ch1_form()
	_test_deploy_stamp_routes_ramza_to_his_ch1_template()
	_test_deploy_stamp_leaves_an_entd_derived_character_alone()
	await _test_scenario_cast_stamps_its_owned_side()

	print("\n=== CharacterFormSetTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] CharacterFormSetTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] CharacterFormSetTest")
		get_tree().quit(1)
	else:
		print("[PASS] CharacterFormSetTest")
		get_tree().quit(0)


## A unique carrying its Ch1 Form materializes that Form's special_name when the
## story context selects Chapter 1.
func _test_unique_selects_active_form_special_name() -> void:
	var c := CharacterClass.new("ramza", "Ramza", CharacterClass.Provenance.PLAYER)
	c.forms = [{"chapter": 1, "special_name": RAMZA_CH1_SPECIAL_NAME}]
	_eq(c.active_special_name(1), RAMZA_CH1_SPECIAL_NAME,
		"Ch1 context selects Ramza's Ch1 Form (special_name 1)")


## A context with no matching Form on file misses -> job-route sentinel. (Only the
## Ch1 Form is seeded now, so a Ch2 selection must fall through, not the wrong byte.)
func _test_missing_form_for_context_is_none() -> void:
	var c := CharacterClass.new("ramza", "Ramza", CharacterClass.Provenance.PLAYER)
	c.forms = [{"chapter": 1, "special_name": RAMZA_CH1_SPECIAL_NAME}]
	_eq(c.active_special_name(2), CharacterClass.SPECIAL_NAME_NONE,
		"a context with no Form on file misses -> SPECIAL_NAME_NONE (job-route)")


## A generic (no Form set) always misses -> job-route. This is the mechanism that
## keeps the squadmates generic.
func _test_empty_form_set_is_none() -> void:
	var c := CharacterClass.new("gariland_generic_1", "Squire", CharacterClass.Provenance.PLAYER)
	_eq(c.active_special_name(1), CharacterClass.SPECIAL_NAME_NONE,
		"an empty Form set selects SPECIAL_NAME_NONE (generic job-routes)")


## The Gariland roster seed mints Ramza WITH his Ch1 Form set (seeded at mint,
## ADR-0079) — so the deploy seam materializes special_name 1 and he resolves
## unique. His durable identity still carries NO active special_name (that is the
## whole point — it is per-context, materialized at deploy, not stored at mint).
func _test_ramza_is_minted_with_his_ch1_form() -> void:
	var ramza = StoryScript._ramza_character()
	_eq(ramza.active_special_name(1), RAMZA_CH1_SPECIAL_NAME,
		"minted Ramza selects his Ch1 Form (special_name 1)")
	_eq(ramza.special_name, CharacterClass.SPECIAL_NAME_NONE,
		"minted Ramza carries NO durable special_name (materialized at deploy, not mint)")


## The stamp is not the whole seam — what the stamp BUYS is the resolver's unique branch.
## Selection alone was already green above while the scenario cast still job-routed Ramza,
## so this carries the assertion one step further, to the template folder his portrait and
## body are actually read from.
func _test_deploy_stamp_routes_ramza_to_his_ch1_template() -> void:
	var ramza = StoryScript._ramza_character()
	UnitSpawn.materialize_active_form(ramza)
	_eq(ramza.special_name, RAMZA_CH1_SPECIAL_NAME,
		"the deploy stamp materializes Ramza's Ch1 Form (special_name 1)")
	var resolved: Dictionary = CharacterTemplateResolver.resolve(ramza)
	_eq(resolved.get("template_folder", ""), RAMZA_CH1_TEMPLATE_FOLDER,
		"a stamped Ramza resolves to his OWN template folder, not a job-routed sheet")
	_eq(resolved.has("body_sprite_id"), false,
		"a stamped Ramza does not job-route (no generic body_sprite_id)")


## The guard that lets the stamp be applied over a WHOLE cast: a Character built from an
## ENTD slot carries its slot's `special_name` and no Form set, so the stamp must not
## overwrite it with the job-route sentinel. Delita's byte survives.
func _test_deploy_stamp_leaves_an_entd_derived_character_alone() -> void:
	var delita = CharacterClass.new("delita", "Delita", CharacterClass.Provenance.FIXED)
	delita.special_name = DELITA_CH1_SPECIAL_NAME
	UnitSpawn.materialize_active_form(delita)
	_eq(delita.special_name, DELITA_CH1_SPECIAL_NAME,
		"a Form-less (ENTD-derived) Character keeps its slot's special_name")


## THE DEFECT THIS SEAM EXISTED TO PREVENT, at the host that had no copy of it, and driven
## through that host's own entry point. Every scenario-booted battle (GambitBattle /
## GPUArena) composes its player side through [ScenarioCast.compose], and until this fix
## that path never materialized a Form — so Ramza fought scenario 4 with the generic Squire
## body and portrait while the navigator's identical cast was correct.
##
## It calls `compose` rather than the stamp: a case that stamps for itself stays green when
## the host drops the call, which is precisely the bug. The assertion is read off the spawned
## [Unit]'s `template_folder` — the field the portrait and body loaders actually consult —
## and the generics in the same cast are the control that the stamp routed only the unique.
func _test_scenario_cast_stamps_its_owned_side() -> void:
	var host := Node.new()
	add_child(host)
	var battle_cast: Dictionary = await ScenarioCast.compose(host, SCENARIO_WITH_AN_OWNED_UNIQUE)
	var ramza: Node = null
	var a_generic: Node = null
	var generics_job_routed := true
	for unit in battle_cast["owned"]:
		if String(unit.get_meta(UnitSpawn.CHARACTER_SLUG_META, "")) == RAMZA_SLUG:
			ramza = unit
		else:
			a_generic = unit
			if String(unit.template_folder) != "":
				generics_job_routed = false
	if ramza == null:
		_failed += 1
		print("  [FAIL] the composed owned side has no '%s'" % RAMZA_SLUG)
	else:
		_eq(String(ramza.template_folder), RAMZA_CH1_TEMPLATE_FOLDER,
			"the composed owned Ramza carries his Ch1 template folder, not a Squire sheet")
	_eq(generics_job_routed, true,
		"the stamp leaves the generic squadmates job-routed (only a unique gains a folder)")
	_assert_the_battle_panel_reads_the_unit(ramza, a_generic)
	host.queue_free()


## THE SECOND READER OF THE SAME FACT. The spawned [Unit] above is one consumer of the
## materialized Form; the docked unit-info panel is the other, and until this fix they
## disagreed on the same screen: at the Orbonne pre-battle (root 3, ENTD 387) the turn-queue
## card drew `templates/ramza_2/` while the panel beside it drew the generic Squire face.
##
## The panel lost because the predetermined-cast path (`NavigatorMain._make_combat_ready`)
## binds the CATALOGUE Character, which carries no `special_name` — ADR-0079 forbids the
## identity from holding one durably — and the panel resolved the folder from that identity.
## So the assertion here is the disagreement itself: an UNSTAMPED identity (`special_name`
## 0, exactly what the bind hands over) paired with a live unit must still yield the UNIT's
## folder.
##
## Carried into this test rather than given its own scene: the cast above already spawned the
## two units this needs, and a scene costs a whole Godot boot (TEST-CHARTER).
func _assert_the_battle_panel_reads_the_unit(unique_unit: Node, generic_unit: Node) -> void:
	if unique_unit == null or generic_unit == null:
		_failed += 1
		print("  [FAIL] the composed cast did not yield both a unique and a generic unit")
		return
	# The identity the predetermined bind hands the panel: minted, never deploy-stamped.
	var unstamped = StoryScript._ramza_character()
	_eq(unstamped.special_name, CharacterClass.SPECIAL_NAME_NONE,
		"the bound catalogue identity carries no special_name (the precondition of the defect)")

	var on_field: Dictionary = FormationMapHost.vitals_view_for(unstamped, unique_unit)
	_eq(String(on_field.get("template_folder", "")), String(unique_unit.template_folder),
		"the battle vitals panel fronts the LIVE unit's template folder, not the identity's job route")

	# `sprite_id` is the OTHER half of `display_from_template` and it has the OTHER owner:
	# it is job-routed, a Change-Job moves it, and that lands on the identity. The overlay
	# must not take it.
	var identity_only: Dictionary = FormationScene.vitals_view_from_character(unstamped)
	_eq(on_field.get("sprite_id"), identity_only.get("sprite_id"),
		"the overlay leaves the job-routed fallback sprite id with the identity")

	# The other direction, which a one-way overlay would get wrong: a STAMPED identity
	# standing as a generic unit must show the generic's (empty) folder. The unit is the
	# materialized Form on a battlefield, so it wins whichever way the two differ.
	var stamped = StoryScript._ramza_character()
	UnitSpawn.materialize_active_form(stamped)
	var as_generic: Dictionary = FormationMapHost.vitals_view_for(stamped, generic_unit)
	_eq(String(as_generic.get("template_folder", "")), "",
		"a unit that job-routes shows the job route even when the identity is stamped")

	# OFF the field there is no unit to ask, and the identity is the only answer left.
	var off_field: Dictionary = FormationMapHost.vitals_view_for(stamped, null)
	_eq(String(off_field.get("template_folder", "")), RAMZA_CH1_TEMPLATE_FOLDER,
		"with no unit on the field the identity still answers (the null-safe leg is unchanged)")


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])
