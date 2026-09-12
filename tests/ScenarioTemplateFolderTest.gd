extends Node
# test-kind: logic
# seeded-break: ResidueManifest.folder_of drops the trailing slash (returns TEMPLATE_ROOT + token instead of TEMPLATE_ROOT + token + "/") — the folder-path shape the #203 loaders and the DialogueBox portrait path read from; 'special_name 3 -> ramza_3 folder' and 'special_name 30 -> agrias_30 folder' red (missing the '/'); the special_name 0 (generic) and absent-special_name no-folder cases stay green
## Regression test for ScenarioPlayerScene._resolve_template_folder (ADR-0072 #223).
##
## Scenario units are spawned bypassing UnitSpawn.build — the one place
## `Unit.template_folder` is otherwise populated (#203) — so the spawn seam must
## resolve the folder itself for the DialogueBox portrait path (#223) to front the
## flat sheet with a unique speaker's OWNED portrait.tga. The rule is the resolver's
## unique branch: the ENTD slot's `special_name` through the [ResidueManifest] — a
## folder for a unique, "" for a generic/monster (which keeps the flat store).
##
## `_resolve_template_folder` is a static pure function, called directly on the
## script with no scene instance — the same shape as `_resolve_sprite_set`.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ScenarioTemplateFolderTest.tscn

const ScenarioPlayerScript := preload("res://src/scenarios/ScenarioPlayerScene.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	# A residue unique resolves to its owned template folder (identity + Form baked
	# into special_name — each Form owns a distinct folder).
	_check({"special_name": 3},
		"res://assets/characters/templates/ramza_3/", "special_name 3 -> ramza_3 folder")
	_check({"special_name": 30},
		"res://assets/characters/templates/agrias_30/", "special_name 30 -> agrias_30 folder")
	# A generic (special_name not in the residue) -> "" -> flat sprite-sheet portrait.
	_check({"special_name": 0}, "", "special_name 0 (generic) -> no folder")
	# A slot with no special_name at all defaults to generic (no folder), never a crash.
	_check({}, "", "absent special_name -> no folder")

	print("\n=== ScenarioTemplateFolderTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioTemplateFolderTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioTemplateFolderTest")
		get_tree().quit(0)


func _check(slot: Dictionary, want: String, name: String) -> void:
	var got: String = ScenarioPlayerScript._resolve_template_folder(slot)
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])
