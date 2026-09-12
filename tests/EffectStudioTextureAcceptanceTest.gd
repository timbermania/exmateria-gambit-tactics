extends Node
## End-to-end acceptance for TEXTURE replacement (#280, ADR-0096/0097) on the REAL
## shipped E019 data — the proof the pure seams compose against ROM-derived bytes
## rather than fixtures.
##
## E019 (Fire 4) is 128×256 @ 8bpp drawn through sub-palette 0 — one of the 338
## in-scope effects. Its `texture.tga` on disk was produced by the Lua extractor,
## so it doubles as the oracle: the studio's own export must reproduce it byte
## for byte, and importing it back must be a visual no-op.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioTextureAcceptanceTest.tscn

const EffectData = ExMateriaEffects.EffectData

const Channel = preload("res://src/effects/studio/TextureChannel.gd")
const Saver = preload("res://src/effects/studio/EffectTextureSaver.gd")
const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const Registry = preload("res://src/effects/studio/InspectorProjectorRegistry.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Tga = preload("res://src/effects/studio/TextureTga.gd")

const E019_DIR := "res://assets/effects/E019"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var data = EffectData.load_from_directory(E019_DIR)
	if data == null or data.texture == null:
		print("[FAIL] EffectStudioTextureAcceptanceTest — E019 assets not available")
		get_tree().quit(1)
		return

	_test_the_real_sheet_is_in_scope(data)
	_test_the_projector_reads_the_real_geometry(data)
	_test_export_reproduces_the_shipped_tga_byte_for_byte(data)
	_test_importing_the_shipped_tga_is_a_visual_no_op_and_undoes(data)

	const EXPECTED_ASSERTIONS := 14
	if _passed + _failed != EXPECTED_ASSERTIONS:
		print("[FAIL] EffectStudioTextureAcceptanceTest — ran %d assertions, expected %d (a test aborted)"
			% [_passed + _failed, EXPECTED_ASSERTIONS])
		get_tree().quit(1)
		return

	print("\n=== EffectStudioTextureAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioTextureAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioTextureAcceptanceTest")
		get_tree().quit(0)


func _test_the_real_sheet_is_in_scope(data) -> void:
	var verdict: Dictionary = Channel.authorable(data.framesets)
	_assert_true(verdict.get("ok", false),
		"E019 is authorable (8bpp, sub-palette 0) — got: %s" % verdict.get("reason", ""))
	_assert_eq(data.texture.get_width(), 128, "real sheet width")
	_assert_eq(data.texture.get_height(), 256, "real sheet height")


func _test_the_projector_reads_the_real_geometry(data) -> void:
	var sections: Array = Registry.sections(Target.texture(), data, {})
	var text := JSON.stringify(sections)
	_assert_true(text.contains("128×256"), "the inspector states the real dimensions")
	_assert_true(text.contains("8bpp"), "…and the real depth")
	_assert_true(text.contains("texture_import"), "…and offers the Import action")


func _test_export_reproduces_the_shipped_tga_byte_for_byte(data) -> void:
	var dest := "user://e019_acceptance_export.tga"
	var res: Dictionary = Saver.export_tga(19, data.texture, dest)
	_assert_true(res.get("ok", false), "export succeeds on the real sheet")

	var ours := _read(dest)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dest))
	var shipped := _read("%s/texture.tga" % E019_DIR)

	_assert_eq(ours.size(), shipped.size(), "exported size matches the Lua extractor's file")
	var differing := 0
	for i in range(min(ours.size(), shipped.size())):
		if ours[i] != shipped[i]:
			differing += 1
	_assert_eq(differing, 0, "the studio's export IS the Lua extractor's bytes")


func _test_importing_the_shipped_tga_is_a_visual_no_op_and_undoes(data) -> void:
	var session = Session.new(data)
	var before: Texture2D = data.texture
	var before_pixels: PackedByteArray = before.get_image().get_data()

	var img: Dictionary = Tga.decode(_read("%s/texture.tga" % E019_DIR))
	_assert_true(img.get("ok", false), "the shipped sheet decodes")

	var res: Dictionary = session.replace_texture(
		img["pixels"], int(img["width"]), int(img["height"]))
	_assert_true(res.get("ok", false), "the real sheet re-imports")

	# Re-importing an unmodified export must not change a single texel.
	var after_pixels: PackedByteArray = data.texture.get_image().get_data()
	_assert_eq(after_pixels, before_pixels, "an unmodified re-import is a visual no-op")

	_assert_true(session.undo(), "undo pops the texture snapshot")
	_assert_true(data.texture == before, "…and restores the original sheet object")


func _read(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var b := f.get_buffer(f.get_length())
	f.close()
	return b


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
