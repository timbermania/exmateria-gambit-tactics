extends Node
## ACCEPTANCE (headful, real E019 = Fire 4, #280): the LIVE texture-import path, end to end
## through the running studio — the coverage every earlier #280 guard lacked.
##
## Three defects have now shipped past ~120 green #280 assertions because every guard tested
## a seam in isolation: the Texture surface was unreachable, the projector header crashed the
## inspector, and the import never reached the preview. This test drives the real chain the
## user's clicks drive — page._load_effect -> the page's Export handler -> repaint the file on
## disk -> the page's Import handler -> assert the NEW PIXELS reach BOTH surfaces that show the
## sheet (the frameset canvas AND the particle material), that a REFUSED import says so out
## loud, and that Ctrl+Z takes both surfaces back.
##
## Skips when E019 assets are absent (gitignored/ROM-derived).
## Run: godot --path . --quit-after 800 res://tests/EffectStudioTextureImportAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const TGA_PATH := "user://e019_texture_import_probe.tga"
const SHOT_MAIN := "user://effect_texture_import_particles.png"
const Tga = preload("res://src/effects/studio/TextureTga.gd")

# Pin the count so a mid-test abort cannot report a clean [PASS] (the harness only counts
# assertions that RAN).
const EXPECTED_ASSERTIONS := 26

const SENTINEL := Color8(255, 0, 255, 255)   # magenta — nowhere in a real FFT sheet
const SENTINEL_RLE := Color8(0, 255, 255, 255)   # cyan — the RLE leg, distinct from the above

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioTextureImportAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0 or (_passed + _failed) != EXPECTED_ASSERTIONS:
		if (_passed + _failed) != EXPECTED_ASSERTIONS and _failed == 0:
			print("  [FAIL] ran %d assertions, expected %d — the test aborted early"
				% [_passed + _failed, EXPECTED_ASSERTIONS])
		print("[FAIL] EffectStudioTextureImportAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioTextureImportAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — acceptance skipped")
		_passed = EXPECTED_ASSERTIONS
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	_assert_true(dir != "", "E019 in the effect catalogue")
	page._load_effect(dir)
	await _frames(40)

	# --- (1) The page projects the HOST's live model, not a copy. --------------------
	# If these are different objects the import can never reach the canvas, whatever
	# else is true.
	var host_data = scn.studio_effect_data()
	_assert_true(host_data != null, "the host has a live effect model")
	_assert_true(page._effect_data != null and host_data != null
		and page._effect_data.get_instance_id() == host_data.get_instance_id(),
		"the studio page and the host share ONE EffectData object")
	if host_data == null or host_data.texture == null:
		_fail_rest("no live texture to import into")
		return

	var w: int = host_data.texture.get_width()
	var h: int = host_data.texture.get_height()

	# --- (2) Export writes a decodable RGBA .tga of the live sheet. -------------------
	page._on_texture_file_selected(TGA_PATH, true)
	var raw := _read(TGA_PATH)
	_assert_true(raw.size() > 0, "export wrote %s" % TGA_PATH)
	var decoded: Dictionary = Tga.decode(raw)
	_assert_true(decoded.get("ok", false),
		"the exported .tga decodes: %s" % decoded.get("error", ""))
	if not decoded.get("ok", false):
		_fail_rest("export produced an undecodable file")
		return
	_assert_eq(Vector2i(int(decoded["width"]), int(decoded["height"])), Vector2i(w, h),
		"the export's dimensions match the live sheet")

	# --- (3) Repaint the file: every pixel magenta. -----------------------------------
	var painted := PackedByteArray()
	painted.resize(w * h * 4)
	for i in range(w * h):
		painted[i * 4 + 0] = 255
		painted[i * 4 + 1] = 0
		painted[i * 4 + 2] = 255
		painted[i * 4 + 3] = 255
	_write(TGA_PATH, Tga.encode(w, h, painted))

	# --- (4) Open a frame FIRST, so the canvas is live when the import lands. -------
	# This is the user's actual situation: a frame is on screen, then they import. The
	# canvas must follow the swap on its own — re-picking a frame to force a rebind is
	# not a fix, and re-picking the SAME dropdown entry fires nothing at all.
	_assert_true(page._frameset_picker != null and page._frameset_picker.item_count > 1,
		"the frame browser lists real (frameset, frame) pairs")
	page._on_frameset_browsed(1)
	# THE TEXTURE TAB is the surface that draws the sheet on a frame target now
	# (ADR-0130 dec. 10) — the right column plays the sequence instead. So the
	# "who cached this object" staleness this file exists to catch has to be
	# proved on the tab's canvas: it is the one an author is actually looking at.
	page._set_active_tab("texture")
	await _frames(8)
	_assert_true(page._texture_panel.visible, "the texture tab is showing")
	_assert_true(page._texture_panel.canvas()._texture != null
		and page._texture_panel.canvas()._texture.get_instance_id() == host_data.texture.get_instance_id(),
		"the canvas starts bound to the pre-import sheet")

	# --- (5) Import through the REAL host verb the dialog calls. ---------------------
	var before_id: int = host_data.texture.get_instance_id()
	page._on_texture_file_selected(TGA_PATH, false)
	await _frames(8)

	_assert_true(not host_data.authored_texture_tga.is_empty(),
		"the import was ACCEPTED (authored bytes are staged for the saver)")
	_assert_true(host_data.texture != null
		and host_data.texture.get_instance_id() != before_id,
		"the live model's texture object was swapped")
	_assert_eq(_pixel(host_data.texture, w / 2, h / 2), SENTINEL,
		"the live model's sheet now reads back the repainted pixels")

	# --- (6a) Surface 1: the frameset canvas follows the swap with NO further click. ------
	_assert_true(page._texture_panel.canvas()._texture != null
		and page._texture_panel.canvas()._texture.get_instance_id() == host_data.texture.get_instance_id(),
		"the canvas re-bound to the IMPORTED sheet without re-picking the frame")

	# --- (6b) Surface 2: the particle material samples the new sheet. ------------------
	# This is the one refold() cannot reach — the sheet is bound into the pool slot's
	# shader material ONCE at renderer initialize().
	var renderer = scn._current_effect.sprite_renderer
	_assert_true(renderer != null, "the live effect has a particle renderer")
	if renderer == null:
		_fail_rest("no renderer to check")
		return
	var pool = Engine.get_main_loop().root.get_node_or_null("EffectMultiMeshPool")
	var slot: int = renderer._pool_slot
	var mat: ShaderMaterial = pool.get_material(slot)
	var bound: Texture2D = mat.get_shader_parameter("effect_texture")
	_assert_true(bound != null
		and bound.get_instance_id() == host_data.texture.get_instance_id(),
		"the particle shader material samples the IMPORTED sheet")
	var slot_tex: Texture2D = pool._all_slots[slot]["_effect_tex"]
	_assert_true(slot_tex != null
		and slot_tex.get_instance_id() == host_data.texture.get_instance_id(),
		"the compositor's slot sheet (_effect_tex) is the IMPORTED sheet")

	# --- (6c) Evidence: scrub to a frame with live particles and capture the game window. --
	# Magenta sprites here are the user's exact symptom inverted — the repainted sheet
	# actually reaching the particles. Only the MAIN viewport is captured: the studio page
	# lives in the DebugDashboard's own OS Window, which lays out at a fraction of its real
	# width under a test harness, so a shot of it shows a cropped transport bar rather than
	# the canvas. The canvas is covered by the binding assertion above instead.
	scn.studio_seek(24)
	await _frames(12)
	var main_img: Image = get_viewport().get_texture().get_image()
	_assert_true(main_img.save_png(SHOT_MAIN) == OK, "particle screenshot written")
	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT_MAIN))

	# --- (7) A REFUSED import says so on screen. -------------------------------------
	# Every refusal used to be a bare push_warning, so a rejected file and a working one
	# looked identical to the author — the reason this bug survived to a user report.
	_assert_true(String(page._save_label.text).begins_with("Imported:"),
		"an accepted import reports itself on the status strip")
	_write(TGA_PATH, Tga.encode(w / 2, h, painted.slice(0, (w / 2) * h * 4)))
	page._on_texture_file_selected(TGA_PATH, false)
	await _frames(4)
	_assert_true(String(page._save_label.text).begins_with("Import refused:"),
		"a wrong-dimensions import is REFUSED OUT LOUD, not silently dropped")
	_assert_eq(_pixel(host_data.texture, w / 2, h / 2), SENTINEL,
		"…and the refused import left the live sheet untouched")

	# --- (8) Ctrl+Z reverts BOTH surfaces, not just the model. -----------------------
	# The inverse of the same bug: undo restores the pre-import ImageTexture object, and
	# the renderer had cached the imported one.
	page._undo()
	await _frames(8)
	_assert_true(_pixel(host_data.texture, w / 2, h / 2) != SENTINEL,
		"undo put the pre-import sheet back on the model")
	var after_undo: Texture2D = pool.get_material(slot).get_shader_parameter("effect_texture")
	_assert_true(after_undo != null
		and after_undo.get_instance_id() == host_data.texture.get_instance_id(),
		"the particle material followed the undo back to the pre-import sheet")
	_assert_true(page._texture_panel.canvas()._texture != null
		and page._texture_panel.canvas()._texture.get_instance_id() == host_data.texture.get_instance_id(),
		"the canvas followed the undo back to the pre-import sheet")

	# --- (9) An RLE-COMPRESSED .tga imports through the same path. -------------------
	# Image type 10 is the DEFAULT in several editors' TGA export, so an artist's re-save of
	# a sheet the studio itself exported routinely arrives compressed — the real report was a
	# 128x128 file that came back 14,338 B instead of 65,554. Covered here and not only at
	# the codec seam, because "the decoder handles it" is exactly the kind of isolated green
	# that let three earlier defects through.
	var cyan := PackedByteArray()
	cyan.resize(w * h * 4)
	for i in range(w * h):
		cyan[i * 4 + 1] = 255
		cyan[i * 4 + 2] = 255
		cyan[i * 4 + 3] = 255
	_write(TGA_PATH, _rle_encode(w, h, cyan))
	_assert_true(_read(TGA_PATH).size() < 18 + w * h * 4,
		"the fixture really is compressed — smaller than its uncompressed form")
	page._on_texture_file_selected(TGA_PATH, false)
	await _frames(8)
	_assert_eq(_pixel(host_data.texture, w / 2, h / 2), SENTINEL_RLE,
		"an RLE .tga imports and reaches the live sheet")
	var rle_bound: Texture2D = pool.get_material(slot).get_shader_parameter("effect_texture")
	_assert_true(rle_bound != null
		and rle_bound.get_instance_id() == host_data.texture.get_instance_id(),
		"…and the particle material follows it too")


# --- helpers ---------------------------------------------------------------
## Encode RGBA as an image-type-10 (RLE true-colour) .tga — what an editor with compression
## left on writes. Emits RUN packets only, which is both the natural encoding for a flat
## sheet and the case that exercises runs spanning scanlines (packets are not row-aligned).
func _rle_encode(width: int, height: int, rgba: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(18)
	for i in range(18):
		out[i] = 0
	out[2] = 10                                  # RLE true-colour
	out[12] = width & 0xFF
	out[13] = (width >> 8) & 0xFF
	out[14] = height & 0xFF
	out[15] = (height >> 8) & 0xFF
	out[16] = 32
	out[17] = 0x28                               # top-left origin, 8 alpha bits
	var total: int = width * height
	var done: int = 0
	while done < total:
		var run: int = min(128, total - done)    # 128 = the largest a packet can carry
		var at: int = done * 4
		out.append(0x80 | (run - 1))
		out.append_array(PackedByteArray([rgba[at + 2], rgba[at + 1], rgba[at], rgba[at + 3]]))
		done += run
	return out


func _pixel(tex: Texture2D, x: int, y: int) -> Color:
	var img: Image = tex.get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	return img.get_pixel(x, y)


func _read(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var b := f.get_buffer(f.get_length())
	f.close()
	return b


func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _fail_rest(why: String) -> void:
	while (_passed + _failed) < EXPECTED_ASSERTIONS:
		_failed += 1
		print("  [FAIL] not reached — %s" % why)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
