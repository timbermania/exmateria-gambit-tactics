extends Node
## Move-2 guard for ADR-0068: the font palette colors/flags are OWNED by UIChar — it
## reads each via Tune.of (`font.*` slugs) at its set_palette use-site — so a committed
## override coalesces onto every char in EVERY scene (and after a reload), with no
## FontDebugPanel writing UIChar statics (decision 12). Uses a real UIChar and reads the
## palette back off its material.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/FontPaletteTunableTest.tscn

const UICharScript = preload("res://src/ui3/elements/UIChar.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	Tune.reset()
	# reset() wiped the boot binds; re-establish the ones this test reads — UIChar's font.*
	# palette slugs and PSXDisplay's render.ui_pixel_aspect (read via UIChar mesh sizing).
	UICharScript.register_tunables()
	PSXDisplay.register_tunables()
	Tune.set_value("font.stat_dark", Color(1.0, 0.0, 0.0, 1.0))

	var ch = UICharScript.new()
	add_child(ch)
	await get_tree().process_frame
	ch.set_palette(UICharScript.FontPalette.STAT)

	var pd: Vector4 = ch._material.get_shader_parameter("palette_dark")
	_assert_approx(pd.x, 1.0, "font.stat_dark override coalesces into the material (R)")
	_assert_approx(pd.y, 0.0, "font.stat_dark override coalesces into the material (G)")

	# A scrub is live at the use-site: re-applying reads the new coalesced value.
	Tune.set_value("font.stat_dark", Color(0.0, 1.0, 0.0, 1.0))
	ch.set_palette(UICharScript.FontPalette.STAT)
	var pd2: Vector4 = ch._material.get_shader_parameter("palette_dark")
	_assert_approx(pd2.y, 1.0, "scrubbing font.stat_dark is read live on the next set_palette")

	# The MENU palette gates on font.menu_use_palette (default false → atlas colors).
	Tune.set_value("font.menu_use_palette", true)
	Tune.set_value("font.menu_light", Color(0.0, 0.0, 1.0, 1.0))
	ch.set_palette(UICharScript.FontPalette.MENU)
	_assert_true(bool(ch._material.get_shader_parameter("use_palette")),
		"font.menu_use_palette override enables the menu palette")
	var ml: Vector4 = ch._material.get_shader_parameter("palette_light")
	_assert_approx(ml.z, 1.0, "font.menu_light coalesces when the menu palette is enabled")

	print("\n=== FontPaletteTunableTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FontPaletteTunableTest")
		get_tree().quit(1)
	else:
		print("[PASS] FontPaletteTunableTest")
		get_tree().quit(0)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
