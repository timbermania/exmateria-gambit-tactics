extends Node
## TDD guard for the TEXTURE round-trip surface's host wiring (#280, ADR-0199 dec. 6).
##
## The projector declares two actions; the page turns each into a file dialog and
## hands the chosen path to the host. Both directions live in the studio so the
## artist loop never depends on the Lua/PCSX extractor.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioTextureWiringTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const EffectDataClass = ExMateriaEffects.EffectData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_export_opens_a_save_dialog_filtered_to_tga()
	await _test_import_opens_an_open_dialog_filtered_to_tga()
	await _test_choosing_a_file_hands_the_path_to_the_host()

	const EXPECTED_ASSERTIONS := 9
	if _passed + _failed != EXPECTED_ASSERTIONS:
		print("[FAIL] EffectStudioTextureWiringTest — ran %d assertions, expected %d (a test aborted)"
			% [_passed + _failed, EXPECTED_ASSERTIONS])
		get_tree().quit(1)
		return

	print("\n=== EffectStudioTextureWiringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioTextureWiringTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioTextureWiringTest")
		get_tree().quit(0)


func _test_export_opens_a_save_dialog_filtered_to_tga() -> void:
	var page = await _page()
	page._run_action({"kind": "texture_export"})

	var dlg: FileDialog = page._texture_dialog
	_assert_true(dlg != null, "export opens a file dialog")
	_assert_eq(dlg.file_mode, FileDialog.FILE_MODE_SAVE_FILE, "export SAVES a file")
	_assert_true(String(",".join(dlg.filters)).contains("tga"), "filtered to .tga")
	page.queue_free()


func _test_import_opens_an_open_dialog_filtered_to_tga() -> void:
	var page = await _page()
	page._run_action({"kind": "texture_import"})

	var dlg: FileDialog = page._texture_dialog
	_assert_true(dlg != null, "import opens a file dialog")
	_assert_eq(dlg.file_mode, FileDialog.FILE_MODE_OPEN_FILE, "import OPENS a file")
	_assert_true(String(",".join(dlg.filters)).contains("tga"), "filtered to .tga")
	page.queue_free()


func _test_choosing_a_file_hands_the_path_to_the_host() -> void:
	var page = await _page()
	var host := _FakeHost.new()
	page.bind_host(host)

	page._on_texture_file_selected("/tmp/sheet.tga", true)
	_assert_eq(host.exported, "/tmp/sheet.tga", "export path reaches the host")

	page._on_texture_file_selected("/tmp/painted.tga", false)
	_assert_eq(host.imported, "/tmp/painted.tga", "import path reaches the host")

	# A host that predates the feature must not crash the page.
	page.bind_host(_BareHost.new())
	page._on_texture_file_selected("/tmp/x.tga", false)
	_passed += 1
	page.queue_free()


func _page():
	var page = Page.new()
	page._effect_data = EffectDataClass.new()
	add_child(page)
	await get_tree().process_frame
	return page


class _FakeHost extends RefCounted:
	var exported: String = ""
	var imported: String = ""
	func studio_export_texture(path: String) -> void: exported = path
	func studio_import_texture(path: String) -> void: imported = path
	func studio_seek(_f: int) -> void: pass
	func studio_set_playing(_p: bool) -> void: pass
	func studio_current_frame() -> int: return 0
	func studio_select_effect(_id: int) -> void: pass


class _BareHost extends RefCounted:
	func studio_seek(_f: int) -> void: pass
	func studio_current_frame() -> int: return 0


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
