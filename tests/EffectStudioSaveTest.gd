extends Node
## TDD guard for the Effect Studio one-click "Save to E###.BIN" loop (Option B, slice 3).
## Two seams:
##   (1) EffectStudioPage has a Save affordance on the transport bar whose action forwards
##       to the host's studio_save() — the page owns the button; the host owns the data +
##       the disk repack.
##   (2) ACCEPTANCE (headful): loading a real effect and saving it with NO edits reproduces
##       the source E###.BIN byte-for-byte — the game→json→bin byte-perfect round-trip end
##       to end (skipped if the ROM extract isn't present).
##
## Run: <GODOT> --path . --quit-after 30 res://tests/EffectStudioSaveTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const CameraChannel = preload("res://src/effects/studio/CameraChannel.gd")
const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"

# for_each camera SoA offsets (mirror parse_effect.CAMERA_TRACK_TABLES), for reading the
# written BIN back in the composition guard.
const CAM_FE := {"end_frame": 0x06B2, "command": 0x0806, "max_keyframe": 0x0828, "count": 17}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_page_save_button_forwards_to_host()
	await _test_unedited_save_reproduces_source_bin_byte_for_byte()
	await _test_studio_save_layers_camera_onto_screen_edits()
	await _test_studio_save_layers_sound_onto_the_chain()
	await _test_camera_edit_saves_without_a_screen_section()

	print("\n=== EffectStudioSaveTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSaveTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSaveTest")
		get_tree().quit(0)


# --- Seam 1: page Save button → host.studio_save --------------------------

func _test_page_save_button_forwards_to_host() -> void:
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame
	var host = _FakeHost.new()
	page.bind_host(host)

	# A Save affordance exists on the transport bar.
	var save_btn := _find_button(page, "Save")
	_assert_true(save_btn != null, "the transport bar has a Save button")

	# Its action forwards to the host's studio_save exactly once.
	page._save()
	_assert_eq(host.save_calls, 1, "the Save action forwards to host.studio_save()")


# --- Seam 2: acceptance — byte-perfect round-trip through the game ---------

func _test_unedited_save_reproduces_source_bin_byte_for_byte() -> void:
	var base_bin := ProjectSettings.globalize_path("res://").path_join(
		"../project-assets/fft-extract/EFFECT/E001.BIN").simplify_path()
	if not FileAccess.file_exists(base_bin):
		print("[SKIP] E001.BIN not available (ROM extract absent) — acceptance round-trip skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	scn.studio_select_effect(1)   # E001, parked
	await _frames(20)

	var res: Dictionary = scn.studio_save()
	_assert_true(res.get("ok", false), "studio_save() succeeds (%s)" % str(res.get("error", "")))
	if not res.get("ok", false):
		return

	var out_path: String = res.get("out_path", "")
	_assert_true(FileAccess.file_exists(out_path), "the output BIN was written")
	if not FileAccess.file_exists(out_path):
		return

	var src := FileAccess.get_file_as_bytes(base_bin)
	var out := FileAccess.get_file_as_bytes(out_path)
	_assert_eq(out.size(), src.size(), "output BIN size matches the source")
	_assert_true(out == src, "unedited Save reproduces E001.BIN byte-for-byte")

	# EDIT PATH: change one screen byte through the live choke point, Save again, and
	# require the output to differ from the source in EXACTLY that byte. The offset is
	# derived from the on-disk header.json (independent source) + the ROM field offsets.
	var header = JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/E001/header.json"))
	var tptr: int = int(header["header"]["timeline_section_ptr"])
	var off: int = (tptr + 8) + 0x057E + 0x42   # for_each base + kf0 start-R (u8)
	var new_val: int = (int(src[off]) + 33) % 256

	scn.studio_apply_edit(
		{"channel": "screen", "context": "for_each", "event_index": 0, "field": "start_r"}, new_val)
	await _frames(6)
	var res2: Dictionary = scn.studio_save()
	_assert_true(res2.get("ok", false), "edited studio_save() succeeds")
	if not res2.get("ok", false):
		return
	var out2 := FileAccess.get_file_as_bytes(res2.get("out_path", ""))
	var diffs: Array = []
	for i in range(src.size()):
		if src[i] != out2[i]:
			diffs.append(i)
	_assert_true(diffs == [off], "an edited start_r changes exactly the for_each kf0 start-R byte (got %s)" % str(diffs))
	_assert_eq(int(out2[off]), new_val, "the changed byte holds the edited value")


# --- Seam 3: composition — camera edits land ALONGSIDE screen edits -------

## studio_save must persist BOTH channels into ONE BIN: the camera patch layers on top
## of the screen writer's output, so a screen edit AND a camera edit made in the same
## session both reach the saved file. Before the camera Save bridge, the camera edit was
## silently dropped (studio_save saved only the screen). E317 is camera-rich (9 active
## for_each keyframes).
func _test_studio_save_layers_camera_onto_screen_edits() -> void:
	var base_bin := ProjectSettings.globalize_path("res://").path_join(
		"../project-assets/fft-extract/EFFECT/E317.BIN").simplify_path()
	if not FileAccess.file_exists(base_bin):
		print("[SKIP] E317.BIN not available (ROM extract absent) — composition guard skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	scn.studio_select_effect(317)
	await _frames(20)

	# (a) camera edit through the choke point: insert a zoom lane event at frame 50.
	CameraChannel.insert_event(scn._current_effect.effect_data, {
		"channel": "camera", "context": "for_each", "camera_channel": "zoom", "frame": 50})

	# (b) screen edit through the live choke point: bump for_each kf0 start_r.
	var header = JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/E317/header.json"))
	var tptr: int = int(header["header"]["timeline_section_ptr"])
	var screen_off: int = (tptr + 8) + 0x057E + 0x42   # screen for_each kf0 start-R (u8)
	var src := FileAccess.get_file_as_bytes(base_bin)
	var new_val: int = (int(src[screen_off]) + 33) % 256
	scn.studio_apply_edit(
		{"channel": "screen", "context": "for_each", "event_index": 0, "field": "start_r"}, new_val)
	await _frames(6)

	var res: Dictionary = scn.studio_save()
	_assert_true(res.get("ok", false), "composed studio_save() succeeds (%s)" % str(res.get("error", "")))
	if not res.get("ok", false):
		return
	var out := FileAccess.get_file_as_bytes(res.get("out_path", ""))

	# The screen edit survived the camera layer (not clobbered).
	_assert_eq(int(out[screen_off]), new_val, "the screen start_r edit is present in the saved BIN")

	# The camera edit reached the SAME BIN: the inserted zoom event appears in the written
	# for_each SoA (a semantic check — the re-lower renumbers slots, so we look for the
	# event by frame+mask, not a count delta).
	_assert_true(_has_zoom_at_frame(out, tptr, 50),
		"a zoom keyframe at frame 50 reached the saved camera section")
	# And it was ABSENT before — proving the save (not the base) put it there.
	_assert_true(not _has_zoom_at_frame(FileAccess.get_file_as_bytes(base_bin), tptr, 50),
		"the base E317 had no zoom keyframe at frame 50 (the edit, not the base, wrote it)")


## ADR-0085 slice 4: the three sound seams (triggers / containers / FEDS bytes) are
## BRIDGED — a FEDS byte edit made through the live choke point survives studio_save,
## layered on the screen+camera chain (one output file, all channels).
func _test_studio_save_layers_sound_onto_the_chain() -> void:
	var base_bin := ProjectSettings.globalize_path("res://").path_join(
		"../project-assets/fft-extract/EFFECT/E317.BIN").simplify_path()
	if not FileAccess.file_exists(base_bin):
		print("[SKIP] E317.BIN not available (ROM extract absent) — sound layering guard skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	scn.studio_select_effect(317)
	await _frames(20)

	var ed = scn._current_effect.effect_data
	_assert_true(ed.feds_bank != null, "E317 carries a FEDS bank")
	if ed.feds_bank == null:
		scn.queue_free()
		return
	# The first parameterized opcode of track 0 — a real, byte-addressed edit target.
	var patch_off := -1
	var before := -1
	for e in ed.feds_bank.get_track_events(0):
		if e is ExMateriaSound.SoundOpcodes.OpcodeEvent and e.params.size() > 0:
			patch_off = ed.feds_bank.track_offsets[0] + e.offset + 1
			before = ed.feds_bank.raw[patch_off]
			break
	if patch_off < 0:
		print("[SKIP] E317 track 0 has no parameterized opcode")
		_passed += 1
		scn.queue_free()
		return
	var new_val := (before + 1) % 128
	scn.studio_apply_edit(
		{"channel": "sound_def", "kind": "byte", "offset": patch_off, "pair_idx": 0}, new_val)
	await _frames(6)

	var res: Dictionary = scn.studio_save()
	_assert_true(res.get("ok", false), "sound-layered studio_save() succeeds (%s)" % str(res.get("error", "")))
	if res.get("ok", false):
		var out := FileAccess.get_file_as_bytes(res.get("out_path", ""))
		var header = JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/E317/header.json"))
		var sd_ptr: int = int(header["header"]["sound_def_ptr"])
		_assert_eq(int(out[sd_ptr + patch_off]), new_val,
			"the FEDS byte edit reached the saved BIN through the unified chain")

	# Restore the cached EffectData (load_from_directory caches per dir).
	ed.feds_bank.raw[patch_off] = before
	scn.queue_free()
	await _frames(2)


## Seam 3b: a camera edit must persist even when the effect has NO screen section. ADR-0086
## says a camera edit recompiles the whole camera section and patches that region — it does not
## depend on a successful screen write. The old studio_save early-returned "no live effect to
## save" whenever effect_data.screen == null and only layered camera THROUGH the screen result,
## so an effect with camera data but no screen silently dropped its camera edits. Here we drop
## the screen model on a camera-rich effect (E317) and require the camera edit to still reach the
## saved BIN by patching the pristine extract directly.
func _test_camera_edit_saves_without_a_screen_section() -> void:
	var base_bin := ProjectSettings.globalize_path("res://").path_join(
		"../project-assets/fft-extract/EFFECT/E317.BIN").simplify_path()
	if not FileAccess.file_exists(base_bin):
		print("[SKIP] E317.BIN not available (ROM extract absent) — screen-absent guard skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	scn.studio_select_effect(317)
	await _frames(20)

	# Simulate an effect with camera data but NO screen section.
	scn._current_effect.effect_data.screen = null

	# A camera edit through the choke point: insert a zoom lane event at frame 50.
	CameraChannel.insert_event(scn._current_effect.effect_data, {
		"channel": "camera", "context": "for_each", "camera_channel": "zoom", "frame": 50})

	var res: Dictionary = scn.studio_save()
	_assert_true(res.get("ok", false),
		"studio_save() succeeds with camera data and no screen section (%s)" % str(res.get("error", "")))
	if not res.get("ok", false):
		return
	var out_path: String = res.get("out_path", "")
	_assert_true(FileAccess.file_exists(out_path), "the output BIN was written (screen-absent path)")
	if not FileAccess.file_exists(out_path):
		return

	var header = JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/E317/header.json"))
	var tptr: int = int(header["header"]["timeline_section_ptr"])
	var out := FileAccess.get_file_as_bytes(out_path)
	_assert_true(_has_zoom_at_frame(out, tptr, 50),
		"the camera edit reached the saved BIN even with no screen section")
	# And it was ABSENT before — proving the save (patching the pristine extract), not the base,
	# put it there.
	_assert_true(not _has_zoom_at_frame(FileAccess.get_file_as_bytes(base_bin), tptr, 50),
		"the base E317 had no zoom keyframe at frame 50 (the camera-only save wrote it)")


## True if the written for_each SoA has an active keyframe at `frame` whose command word
## sets the zoom mask (bit 2).
func _has_zoom_at_frame(bytes: PackedByteArray, tptr: int, frame: int) -> bool:
	var mk: int = int(bytes.decode_s16(tptr + CAM_FE["max_keyframe"]))
	for i in range(mk + 1):
		var ef: int = bytes.decode_s16(tptr + CAM_FE["end_frame"] + i * 2)
		var cmd: int = bytes.decode_u16(tptr + CAM_FE["command"] + i * 2)
		if ef == frame and (cmd & 0x04) != 0:
			return true
	return false


# --- helpers --------------------------------------------------------------

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _find_button(node: Node, text_contains: String) -> Button:
	if node is Button and String(node.text).findn(text_contains) != -1:
		return node
	for c in node.get_children():
		var r := _find_button(c, text_contains)
		if r != null:
			return r
	return null


class _FakeHost extends RefCounted:
	var save_calls: int = 0

	func studio_save() -> Dictionary:
		save_calls += 1
		return {"ok": true, "out_path": ""}

	func studio_select_effect(_id: int) -> void: pass
	func studio_seek(_f: int) -> void: pass
	func studio_set_playing(_p: bool) -> void: pass
	func studio_current_frame() -> int: return 0
	func studio_set_audibility(_a: Dictionary) -> void: pass
	func studio_apply_edit(_r: Dictionary, _v, _defer = false) -> void: pass


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
