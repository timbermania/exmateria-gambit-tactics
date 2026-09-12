extends Node2D

var _process_count: int = 0


func _process(_dt: float) -> void:
	_process_count += 1
	if _process_count == 1 or _process_count % 60 == 0:
		print("[Preview] _process tick #%d" % _process_count)


## Visual preview for `DialogueOverlay` — drives the chapel-prayer tokens
## directly (PC=42 of scenario_1_chunk.json) so the rendered output can be
## inspected without ticking through ~14s of upstream camera/wait ops.
##
## Run via: `<GODOT> --path . res://tests/DialogueOverlayPreview.tscn`
## (omit `--quit-after` so the prayer types out fully).

const DialogueOverlayClass = preload("res://src/scenarios/DialogueOverlay.gd")
const CHUNK_JSON_PATH := "res://assets/scenarios/scenario_1_chunk.json"

var _overlay: DialogueOverlayClass = null


func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a visual preview of DialogueOverlay — its own docstring says to run it WITHOUT --quit-after so the prayer types out")
	# Solid dark backdrop so light text reads.
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.04, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_overlay = DialogueOverlayClass.new()
	_overlay.name = "DialogueOverlay"
	add_child(_overlay)

	# Load the baked chunk to pull the chapel prayer's token list (instruction 42).
	var f := FileAccess.open(CHUNK_JSON_PATH, FileAccess.READ)
	if f == null:
		push_error("missing chunk JSON")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_error("chunk JSON not a dict")
		return
	var insts: Array = parsed.get("instructions", [])
	if insts.size() <= 42:
		push_error("chunk JSON has %d instructions, no PC=42" % insts.size())
		return
	var prayer: Dictionary = insts[42]
	var dialogue: Dictionary = prayer.get("dialogue", {})
	var tokens: Array = dialogue.get("tokens", [])
	var psx_x := 0
	var psx_y := 60
	for p in prayer.get("params", []):
		if p is Dictionary:
			match p.get("name", ""):
				"X": psx_x = int(p.get("value", 0))
				"Y": psx_y = int(p.get("value", 60))

	print("[Preview] prayer tokens=%d X=%d Y=%d" % [tokens.size(), psx_x, psx_y])
	_overlay.show_overlay(tokens, psx_x, psx_y)
	# Save a screenshot after the prayer finishes typing (or 10s, whichever
	# comes first). Two-step await ensures the final glyph is on screen
	# before the screenshot fires.
	_capture_when_done()


func _capture_when_done() -> void:
	print("[Preview] capture coroutine started")
	await _wait_frames(180)
	print("[Preview] reached mid (180 frames)")
	_screenshot("mid")
	await _wait_frames(420)
	print("[Preview] reached end (600 frames)")
	_screenshot("end")
	# Self-quit so the runner returns control.
	get_tree().quit(0)


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
		if i % 60 == 0:
			print("[Preview]   frame %d / %d" % [i, n])


func _screenshot(label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("[Preview] screenshot %s failed (no viewport image)" % label)
		return
	var out_path := "user://dialogue_overlay_preview_%s.png" % label
	img.save_png(out_path)
	var abs_path := ProjectSettings.globalize_path(out_path)
	print("[Preview] screenshot %s saved → %s (current_text=%s)" %
		[label, abs_path, _overlay.current_text.replace("\n", "\\n")])
