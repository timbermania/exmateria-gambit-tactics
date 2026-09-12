extends Node
## TDD guard for Effect Studio TEXTURE replacement (#280, ADR-0199).
##
## The texture is the sheet every frame UVs into — 33,796 B, the file's largest
## gap and its LAST section. v1 replaces it from a same-dimensions RGBA .tga with
## the CLUT held FIXED.
##
## SPLIT OF WORK. The index-delta quantization needs the ORIGINAL indexed plane,
## which lives only in the BIN — the asset dir has colours (texture.tga) and the
## CLUT (texture_palette.json) but no plane. So quantization runs in Python
## (`write_effect_texture.py`, corpus-guarded), and GDScript owns what only it
## can: the scope verdict from the live framesets, the preview swap, and undo.
##
## SCOPE (ADR-0199 dec. 3): 8bpp single-sub-palette sheets only — 338 of the 401
## non-empty effects. 4bpp sheets render through per-frame 16-colour
## sub-palettes, so one flat export cannot show them truthfully; they are refused
## WITH A REASON rather than silently mis-imported.
##
## UNDO is a snapshot, not a scalar (ADR-0199 dec. 5): a 33 KB plane has no
## meaningful before/after scalar, so this mirrors the `"feds"` bank swap.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioTextureEditTest.tscn

const EffectData = ExMateriaEffects.EffectData

const Channel = preload("res://src/effects/studio/TextureChannel.gd")
const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const Saver = preload("res://src/effects/studio/EffectTextureSaver.gd")
const Tga = preload("res://src/effects/studio/TextureTga.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_a_plain_8bpp_sheet_is_authorable()
	_test_a_4bpp_sheet_is_refused_with_a_reason()
	_test_a_multi_sub_palette_sheet_is_refused_naming_them()
	_test_a_sheet_no_frame_references_is_refused_not_assumed_8bpp()
	_test_replace_swaps_the_preview_texture_and_keeps_the_authored_bytes()
	_test_replace_refuses_a_dimension_change()
	_test_session_undo_restores_the_previous_sheet()
	_test_export_writes_a_tga_that_reads_back_as_the_same_sheet()
	_test_saving_an_untouched_sheet_is_a_no_op()

	# A mid-test abort (a nonexistent method, say) stops that function and leaves
	# the rest unrun, which otherwise reports as a clean PASS. Pin the count so a
	# bare PASS cannot lie.
	const EXPECTED_ASSERTIONS := 27
	if _passed + _failed != EXPECTED_ASSERTIONS:
		print("[FAIL] EffectStudioTextureEditTest — ran %d assertions, expected %d (a test aborted)"
			% [_passed + _failed, EXPECTED_ASSERTIONS])
		get_tree().quit(1)
		return

	print("\n=== EffectStudioTextureEditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioTextureEditTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioTextureEditTest")
		get_tree().quit(0)


# --- scope verdict, read off the live framesets -------------------------------
# Mirrors `write_effect_texture.authorable` (which gates the byte writer); this
# copy exists so the inspector can explain a refusal without shelling to Python.

func _test_a_plain_8bpp_sheet_is_authorable() -> void:
	var verdict: Dictionary = Channel.authorable(_framesets(true, [0, 0, 0]))
	_assert_true(verdict.get("ok", false), "8bpp single-sub-palette sheet is authorable")
	_assert_eq(verdict.get("reason", "x"), "", "no reason when authorable")


func _test_a_4bpp_sheet_is_refused_with_a_reason() -> void:
	var verdict: Dictionary = Channel.authorable(_framesets(false, [0, 0]))
	_assert_true(not verdict.get("ok", true), "4bpp sheet is refused")
	_assert_true(String(verdict.get("reason", "")).contains("4bpp"),
		"the refusal names the depth")


func _test_a_multi_sub_palette_sheet_is_refused_naming_them() -> void:
	# E040: 8bpp but drawn through sub-palettes 0/4/5, so one flat RGBA export
	# would show most of it in the wrong colours.
	var verdict: Dictionary = Channel.authorable(_framesets(true, [0, 4, 5]))
	_assert_true(not verdict.get("ok", true), "multi-sub-palette sheet is refused")
	_assert_true(String(verdict.get("reason", "")).contains("sub-palette"),
		"the refusal names the sub-palettes")


func _test_a_sheet_no_frame_references_is_refused_not_assumed_8bpp() -> void:
	# E509/E510 have a texture but no frames, so no depth is established.
	var verdict: Dictionary = Channel.authorable([])
	_assert_true(not verdict.get("ok", true), "an unreferenced sheet is refused")
	_assert_true(String(verdict.get("reason", "")) != "", "and says why")


# --- the replace verb ---------------------------------------------------------

func _test_replace_swaps_the_preview_texture_and_keeps_the_authored_bytes() -> void:
	var data := _effect_data(4, 2)
	var before: Texture2D = data.texture

	var res: Dictionary = Channel.replace(data, _rgba(4, 2, 200), 4, 2)

	_assert_true(res.get("ok", false), "replace succeeds on matching dimensions")
	_assert_true(data.texture != before, "the preview texture is swapped")
	_assert_eq(data.texture.get_image().get_pixel(0, 0).r8, 200, "preview shows the new sheet")
	_assert_true(data.authored_texture_tga.size() > 0,
		"the authored TGA bytes are kept for the saver")
	_assert_true(res.has("texture_snapshot"), "a snapshot is returned for undo")


func _test_replace_refuses_a_dimension_change() -> void:
	# v1 forbids resize: a shape change cascades into every frame's UV fields.
	var data := _effect_data(4, 2)
	var res: Dictionary = Channel.replace(data, _rgba(8, 2, 200), 8, 2)

	_assert_true(not res.get("ok", true), "a resized import is refused")
	_assert_true(String(res.get("error", "")).contains("4x2"),
		"the refusal states the required dimensions")


func _test_session_undo_restores_the_previous_sheet() -> void:
	var data := _effect_data(4, 2)
	var session = Session.new(data)
	var before: Texture2D = data.texture

	var res: Dictionary = session.replace_texture(_rgba(4, 2, 200), 4, 2)
	_assert_true(res.get("ok", false), "session replace succeeds")
	_assert_true(res.get("invalidates_sim", false),
		"a new sheet must reach the preview through a re-fold")

	_assert_true(session.undo(), "undo pops the texture entry")
	_assert_true(data.texture == before, "the previous sheet is restored wholesale")
	_assert_eq(data.authored_texture_tga.size(), 0, "and the authored bytes are dropped")


func _test_export_writes_a_tga_that_reads_back_as_the_same_sheet() -> void:
	var data := _effect_data(4, 2)
	var dest := "user://texture_export_guard.tga"

	var res: Dictionary = Saver.export_tga(19, data.texture, dest)
	_assert_true(res.get("ok", false), "export succeeds")

	var f := FileAccess.open(dest, FileAccess.READ)
	_assert_true(f != null, "the file is on disk")
	var raw := f.get_buffer(f.get_length())
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dest))

	var img: Dictionary = Tga.decode(raw)
	_assert_eq(img.get("width", 0), 4, "exported width")
	_assert_eq(img.get("height", 0), 2, "exported height")
	_assert_eq(img.get("pixels", PackedByteArray())[0], 10, "exported texel survives the round trip")


func _test_saving_an_untouched_sheet_is_a_no_op() -> void:
	# Nothing was imported, so there is no authored .tga and the saver must not
	# shell out or claim an edit.
	var res: Dictionary = Saver.save(19, PackedByteArray())
	_assert_true(res.get("ok", false), "an untouched sheet saves cleanly")
	_assert_true(res.get("no_edit", false), "…as a declared no-op")


# --- fixtures -----------------------------------------------------------------

func _framesets(is_8bpp: bool, palette_ids: Array) -> Array:
	var frames := []
	for pid in palette_ids:
		frames.append({"is_8bpp": is_8bpp, "palette_id": int(pid)})
	return [{"frames": frames}]


func _effect_data(w: int, h: int) -> EffectData:
	var data := EffectData.new()
	data.framesets = _framesets(true, [0])
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color8(10, 20, 30, 255))
	data.texture = ImageTexture.create_from_image(img)
	return data


func _rgba(w: int, h: int, red: int) -> PackedByteArray:
	var px := PackedByteArray()
	px.resize(w * h * 4)
	for i in range(0, px.size(), 4):
		px[i] = red
		px[i + 1] = 0
		px[i + 2] = 0
		px[i + 3] = 255
	return px


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
