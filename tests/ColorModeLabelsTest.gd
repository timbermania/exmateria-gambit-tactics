extends Node
## TDD guard for ColorModeLabels (ADR-0087) — the ONE shared human-label map for the
## 11 PSX Color modes (codes 0-10, ColorRecipe.from_mode). Both the screen Blend-mode
## row and the palette tint's blend-mode selector read it, so they cannot drift to
## different words for the same op. The source axis (current vs base) is IN the label:
## the idempotent base-source variants (4/5/6/7/9) carry an "over base" suffix; the two
## restores (8/10) are "Reset to base" / "Reset". See CONTEXT "Palette tint" / "Color modes".
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ColorModeLabelsTest.tscn

const Labels = preload("res://src/effects/studio/ColorModeLabels.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_labels_match_the_recipe_semantics()
	_test_base_source_variants_say_over_base()
	_test_restores_are_reset_labels()
	_test_choices_cover_all_eleven_in_code_order()

	print("\n=== ColorModeLabelsTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColorModeLabelsTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColorModeLabelsTest")
		get_tree().quit(0)


## The 11 codes carry the human names ADR-0087 fixed — matched to the ColorRecipe.from_mode
## shapes: 0=additive over current, 1=dim-then-add over current, 2/3=luma desaturate (div 6
## strong / div 12 subtle) over current, and the 4/5/6/7/9 base-source idempotent variants.
func _test_labels_match_the_recipe_semantics() -> void:
	_assert_eq(Labels.label(0), "Add", "mode 0 = additive over current")
	_assert_eq(Labels.label(1), "Dim ½ + Add", "mode 1 = dim-then-add over current")
	_assert_eq(Labels.label(2), "Desaturate (strong)", "mode 2 = luma div 6 over current")
	_assert_eq(Labels.label(3), "Desaturate (subtle)", "mode 3 = luma div 12 over current")


## The base-source modes (4/5/6/7/9) are the IDEMPOTENT variants that read the committed
## base, so their label carries the "over base" source distinction (the #164 fix that
## makes repetition land on base+delta, not base+N·delta). 9 is a real byte ≡ 4 (Add).
func _test_base_source_variants_say_over_base() -> void:
	_assert_eq(Labels.label(4), "Add over base", "mode 4 = additive over base")
	_assert_eq(Labels.label(5), "Dim ½ + Add over base", "mode 5 = dim-then-add over base")
	_assert_eq(Labels.label(6), "Desaturate (strong) over base", "mode 6 = luma div 6 over base")
	_assert_eq(Labels.label(7), "Desaturate (subtle) over base", "mode 7 = luma div 12 over base")
	_assert_eq(Labels.label(9), "Add over base", "mode 9 is a real byte ≡ 4 (Add over base)")


## The two restores carry no colour (the Δ is ignored); their labels name the reset.
func _test_restores_are_reset_labels() -> void:
	_assert_eq(Labels.label(8), "Reset to base", "mode 8 = absolute-base restore")
	_assert_eq(Labels.label(10), "Reset", "mode 10 = reset")


## The choices() convenience yields all 11 in code order as {value, label} — the shape
## the value-carrying enum editor consumes (item id == code).
func _test_choices_cover_all_eleven_in_code_order() -> void:
	var choices := Labels.choices()
	_assert_eq(choices.size(), 11, "choices cover all 11 modes")
	for code in range(11):
		_assert_eq(int(choices[code].get("value", -1)), code, "choice %d carries its code as value" % code)
		_assert_eq(str(choices[code].get("label", "")), Labels.label(code), "choice %d label matches label(code)" % code)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
