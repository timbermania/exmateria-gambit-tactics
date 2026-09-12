extends Node3D

## TDD guard for the folder-fronting runtime asset loaders (ADR-0072, issue #203).
##
## The template/resolver system's payoff slice: the loaders read a unit's visuals
## from its **template folder** (`res://assets/characters/templates/<token>/`, the
## moddable read surface) instead of the flat `textures/NN.tga` store — while the
## flat path stays **load-bearing** (folders are generated + gitignored, #200, so
## they may be absent on a fresh checkout; the loader must degrade, never error).
##
## Two loaders shift, each fronting both paths:
##   - `SpriteLayerManager.load_body_sprite(template_folder, flat_path)` — the BODY
##     sheet. The folder's `body.tga` is a byte-identical copy of the flat sheet,
##     so its `body.palette.tga` companion resolves by basename exactly like flat.
##   - `UIPortrait.display_from_template(template_folder, fallback_sprite_id)` — the
##     menu portrait. The folder's `portrait.tga` is a PRE-CROPPED 48x32 slice with
##     its own palette, so the shader region rebinds to (0,0,48,32) / atlas 48x32
##     vs the flat path's (80,456,48,32) window into the 256x488 sheet.
##
## Uses a real emitted unique folder (ramza_3) — run the #201 transform +
## `godot --path . --import` first if `assets/characters/templates/` is absent.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/TemplateFolderLoaderTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const SpriteLayerManager = ExMateriaSpriteRig.SpriteLayerManager

const TEMPLATE_FOLDER := "res://assets/characters/templates/ramza_3/"
const ABSENT_FOLDER := "res://assets/characters/templates/does_not_exist_zz/"
const FLAT_BODY_PATH := "res://assets/sprites/textures/01.tga"
const FLAT_PORTRAIT_ID := 1  # -> 01.tga in the flat store

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_body_loads_from_template_folder()
	_test_body_falls_back_to_flat_when_folder_blank()
	_test_body_falls_back_to_flat_when_folder_missing_body()
	await _test_portrait_loads_from_template_folder()
	await _test_portrait_falls_back_to_flat_when_folder_blank()
	await _test_portrait_mode_resets_when_returning_to_sprite_id()

	print("\n=== TemplateFolderLoaderTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TemplateFolderLoaderTest")
		get_tree().quit(1)
	else:
		print("[PASS] TemplateFolderLoaderTest")
		get_tree().quit(0)


func _make_layers() -> SpriteLayerManager:
	var layers := SpriteLayerManager.new()
	layers.material = UnitAssets.base_material().duplicate()
	return layers


func _make_portrait() -> UIPortrait:
	var p := UIPortrait.new()
	add_child(p)
	return p


# --- BODY (SpriteLayerManager) -------------------------------------------------

func _test_body_loads_from_template_folder() -> void:
	var layers := _make_layers()
	var ok := layers.load_body_sprite(TEMPLATE_FOLDER, FLAT_BODY_PATH)
	_assert(ok, "load_body_sprite returns true for a real template folder")
	var tex := layers.material.get_shader_parameter("type1_tex") as Texture2D
	_assert_eq(tex.resource_path, TEMPLATE_FOLDER + "body.tga",
		"BODY sheet bound from the template folder, not the flat store")
	var pal := layers.material.get_shader_parameter("type1_palette") as Texture2D
	_assert_eq(pal.resource_path, TEMPLATE_FOLDER + "body.palette.tga",
		"BODY palette companion resolves inside the template folder")


func _test_body_falls_back_to_flat_when_folder_blank() -> void:
	var layers := _make_layers()
	var ok := layers.load_body_sprite("", FLAT_BODY_PATH)
	_assert(ok, "load_body_sprite returns true on the flat fallback")
	var tex := layers.material.get_shader_parameter("type1_tex") as Texture2D
	_assert_eq(tex.resource_path, FLAT_BODY_PATH,
		"blank template folder degrades to the flat body path")


func _test_body_falls_back_to_flat_when_folder_missing_body() -> void:
	var layers := _make_layers()
	# The folder path is non-blank but holds no body.tga — the fallback is
	# load-bearing (folders are regenerable; a unit may resolve to a folder that
	# hasn't been emitted yet).
	var ok := layers.load_body_sprite(ABSENT_FOLDER, FLAT_BODY_PATH)
	_assert(ok, "load_body_sprite returns true when the folder lacks body.tga")
	var tex := layers.material.get_shader_parameter("type1_tex") as Texture2D
	_assert_eq(tex.resource_path, FLAT_BODY_PATH,
		"absent folder body degrades to the flat body path")


# --- PORTRAIT (UIPortrait) -----------------------------------------------------

func _test_portrait_loads_from_template_folder() -> void:
	var p := _make_portrait()
	await get_tree().process_frame
	p.display_from_template(TEMPLATE_FOLDER, FLAT_PORTRAIT_ID)
	var mat := p._material
	var tex := mat.get_shader_parameter("sprite_texture") as Texture2D
	_assert_eq(tex.resource_path, TEMPLATE_FOLDER + "portrait.tga",
		"portrait sliced from the template folder's portrait.tga")
	var pal := mat.get_shader_parameter("sprite_palette") as Texture2D
	_assert_eq(pal.resource_path, TEMPLATE_FOLDER + "portrait.palette.tga",
		"portrait palette resolves inside the template folder")
	_assert_eq(mat.get_shader_parameter("portrait_region"), Vector4(0, 0, 48, 32),
		"region samples the whole 48x32 crop, not a window into the sheet")
	_assert_eq(mat.get_shader_parameter("atlas_size"), Vector2(48, 32),
		"atlas size is the crop's own dimensions")
	p.queue_free()


func _test_portrait_falls_back_to_flat_when_folder_blank() -> void:
	var p := _make_portrait()
	await get_tree().process_frame
	p.display_from_template("", FLAT_PORTRAIT_ID)
	var mat := p._material
	var tex := mat.get_shader_parameter("sprite_texture") as Texture2D
	_assert_eq(tex.resource_path, "res://assets/sprites/textures/01.tga",
		"blank folder degrades to the flat sprite-sheet portrait")
	_assert_eq(mat.get_shader_parameter("portrait_region"), Vector4(80, 456, 48, 32),
		"flat path keeps the sheet-window region")
	_assert_eq(mat.get_shader_parameter("atlas_size"), Vector2(256, 488),
		"flat path keeps the full-sheet atlas size")
	p.queue_free()


func _test_portrait_mode_resets_when_returning_to_sprite_id() -> void:
	var p := _make_portrait()
	await get_tree().process_frame
	p.display_from_template(TEMPLATE_FOLDER, FLAT_PORTRAIT_ID)  # into template mode
	p.display_sprite_id(FLAT_PORTRAIT_ID)                       # back to the sheet path
	var mat := p._material
	_assert_eq(mat.get_shader_parameter("portrait_region"), Vector4(80, 456, 48, 32),
		"returning to display_sprite_id restores the sheet-window region")
	_assert_eq(mat.get_shader_parameter("atlas_size"), Vector2(256, 488),
		"returning to display_sprite_id restores the full-sheet atlas size")
	p.queue_free()


# --- helpers -------------------------------------------------------------------

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)


func _assert_eq(a, b, msg: String) -> void:
	if a == b:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s (got %s, expected %s)" % [msg, str(a), str(b)])
