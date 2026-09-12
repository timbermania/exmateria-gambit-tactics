extends Node3D

## TDD guard for the first slice of the Character-name pipeline (ADR-0066).
##
## The `{Ramza}` name-insert control code (`0xE0`) bakes into a dialogue token
## `{"type":"macro","name":"Ramza"}`. It must render the Character's CURRENT
## name via the `CharacterCatalog` — **no braces** — because the protagonist is
## player-renamable at runtime. Non-name "word" macros (`{Serpentarius}`) stay
## literal. One shared seam (`TypewriterController.macro_text`) covers all three
## render sites; this proves that seam plus the rename path.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ScenarioNameMacroTest.tscn

const TypewriterControllerClass = preload("res://src/scenarios/TypewriterController.gd")

var _failed: int = 0
var _passed: int = 0


## Minimal TypewriterController sink that accumulates revealed text.
class FakeSink:
	extends RefCounted
	var text: String = ""
	func typewriter_append(t: String) -> void:
		text += t
	func typewriter_set_palette(_p: int) -> void:
		pass


func _ready() -> void:
	_test_catalog_seed()
	_test_macro_text_name_vs_word()
	_test_macro_text_follows_rename()
	_test_flatten_substitutes_name()
	_test_drain_substitutes_name()

	print("\n=== ScenarioNameMacroTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioNameMacroTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioNameMacroTest")
		get_tree().quit(0)


func _test_catalog_seed() -> void:
	_assert_eq(CharacterCatalog.name_macro_slug("Ramza"), "ramza", "Ramza macro -> ramza slug")
	_assert_eq(CharacterCatalog.name_macro_slug("Serpentarius"), "", "word macro -> no slug")
	_assert_eq(CharacterCatalog.display_name("ramza"), "Ramza", "seeded ramza name")


func _test_macro_text_name_vs_word() -> void:
	var name_tok := {"type": "macro", "name": "Ramza"}
	var word_tok := {"type": "macro", "name": "Serpentarius"}
	_assert_eq(TypewriterControllerClass.macro_text(name_tok), "Ramza",
		"name macro renders name, no braces")
	_assert_eq(TypewriterControllerClass.macro_text(word_tok), "{Serpentarius}",
		"word macro stays literal")


func _test_macro_text_follows_rename() -> void:
	var name_tok := {"type": "macro", "name": "Ramza"}
	CharacterCatalog.set_display_name("ramza", "Delita")
	_assert_eq(TypewriterControllerClass.macro_text(name_tok), "Delita",
		"renamed protagonist renders new name")
	CharacterCatalog.set_display_name("ramza", "Ramza")  # restore shared autoload state
	_assert_eq(TypewriterControllerClass.macro_text(name_tok), "Ramza", "rename restored")


func _test_flatten_substitutes_name() -> void:
	var tokens := [
		{"type": "text", "value": "A"},
		{"type": "macro", "name": "Ramza"},
		{"type": "text", "value": "B"},
	]
	var flat: Dictionary = TypewriterControllerClass.flatten(tokens)
	_assert_eq(String(flat.get("text", "")), "ARamzaB",
		"flatten substitutes name inline, no braces")
	_assert_eq(flat.get("palettes", PackedInt32Array()).size(), 7,
		"palette entry per rendered char (1+5+1)")


func _test_drain_substitutes_name() -> void:
	var tc = TypewriterControllerClass.new()
	var sink := FakeSink.new()
	tc.start([{"type": "macro", "name": "Ramza"}], sink)
	tc.advance_frames(8)
	_assert_eq(sink.text, "Ramza", "drain path substitutes name into sink, no braces")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
