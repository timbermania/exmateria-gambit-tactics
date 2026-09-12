extends Node
# test-kind: logic
# seeded-break: ResidueManifest.folder_of's return drops its trailing slash (TEMPLATE_ROOT + token + "/" -> TEMPLATE_ROOT + token); 'folder path ends with a slash' RED (got=false); the has()/distinct-folder, res://-rooted, template-root, and generic-empty-folder arms stay green; GREEN unbroken on the reverted tree
## Pure-logic guard (no scene/GPU) for the unique↔asset residue manifest
## (ADR-0072, issue #202). The residue is the small hand-authored bridge that
## maps a *unique* `Character`'s ROM `special_name` (the whole unique [template
## key] — #199) to its owned [template] folder. It is the single authority for
## "which special_names are unique"; a special_name absent here is job-routed.
##
## Folders are *derived and regenerable* — emitted by the character-alignment
## transform (#201), read by the runtime loaders (#203) — so these assertions
## check the mapping (the address), NOT that any folder exists on disk yet.
##
## Run: "$GODOT" --path . --quit-after 4 res://tests/ResidueManifestTest.tscn

const ResidueManifest = ExMateriaCatalogue.ResidueManifest

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_known_uniques_resolve_to_a_folder()
	_test_multi_form_special_names_get_distinct_folders()
	_test_generic_and_empty_ids_are_not_unique()
	_test_folder_of_is_rooted_under_the_template_store()

	print("\n=== ResidueManifestTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ResidueManifestTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ResidueManifestTest")
		get_tree().quit(1)
	else:
		print("[PASS] ResidueManifestTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


## A canonical story unit's special_name is in the residue and carries a folder.
func _test_known_uniques_resolve_to_a_folder() -> void:
	_true(ResidueManifest.has(1), "Ramza (special_name 1) is a unique")
	_true(ResidueManifest.has(52), "Agrias (special_name 52) is a unique")
	_true(ResidueManifest.folder_of(1) != "", "Ramza resolves to a non-empty folder")
	_true(ResidueManifest.folder_of(52) != "", "Agrias resolves to a non-empty folder")


## Each special_name is a distinct [Form] (#199): Ramza's Ch1/Ch2/Ch4 forms
## (1/2/3) each own a *distinct* template folder — the token packs identity+Form,
## so the folders must differ.
func _test_multi_form_special_names_get_distinct_folders() -> void:
	var ch1 := ResidueManifest.folder_of(1)
	var ch2 := ResidueManifest.folder_of(2)
	var ch4 := ResidueManifest.folder_of(3)
	_true(ch1 != ch2 and ch2 != ch4 and ch1 != ch4,
		"Ramza's three forms get three distinct folders")


## A generic (special_name 0 / no special name) and the empty-slot sentinel
## (0xFF) are NOT unique — they fall through to the job-routed branch.
func _test_generic_and_empty_ids_are_not_unique() -> void:
	_true(not ResidueManifest.has(0), "special_name 0 (generic) is not unique")
	_true(not ResidueManifest.has(255), "special_name 0xFF (empty) is not unique")
	_true(not ResidueManifest.has(126), "an unmapped id is not unique")
	_eq(ResidueManifest.folder_of(0), "", "generic resolves to an empty folder")


## folder_of returns a res:// path under the derived template store, so the
## #203 loaders can read straight from it.
func _test_folder_of_is_rooted_under_the_template_store() -> void:
	var f := ResidueManifest.folder_of(1)
	_true(f.begins_with("res://"), "folder is a res:// path")
	_true(f.contains(ResidueManifest.TEMPLATE_ROOT), "folder sits under the template root")
	_true(f.ends_with("/"), "folder path ends with a slash")
