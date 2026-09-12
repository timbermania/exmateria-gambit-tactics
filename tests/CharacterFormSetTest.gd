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
const StoryScript = preload("res://src/scenarios/StoryMutationScript.gd")

## Ramza's three chapter Forms, ROM-derived (template_residue.json): Ch1 -> 1.
const RAMZA_CH1_SPECIAL_NAME := 1

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_unique_selects_active_form_special_name()
	_test_missing_form_for_context_is_none()
	_test_empty_form_set_is_none()
	_test_ramza_is_minted_with_his_ch1_form()

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



func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])
