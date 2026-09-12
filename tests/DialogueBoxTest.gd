extends Node3D

## Unit tests for the boxed-portrait `DialogueBox` ui3 assembly.
##
## Covers the contract from boxed_dialog_decode.md / the build handoff:
##   * Typewriter reveal drives UIText.visible_chars from 0 → full, mapping
##     past newlines (which are not char nodes).
##   * Header ({Color 08}) vs body ({Color 00}) palette runs tint distinct
##     char ranges.
##   * Dialog-byte decode: align 1 → arrow DOWN (box above unit), align 2 →
##     arrow UP (box below unit); arrow-remove flag (0x8) hides the triangle.
##   * Unit-offset sign flips the PORTRAIT side; the triangle h-mirror is gated
##     on the authored arrow operand (msg[0x64] & 0xf0), not the offset (decode
##     §3 corr #2 / §1c).
##   * `typed_out` fires once the text finishes; `finish_typing` short-circuits.
##   * `{51}`-style in-place swap re-shows new content without teardown.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/DialogueBoxTest.tscn

const DialogueBoxClass = preload("res://src/ui3/assemblies/DialogueBox.gd")

# A real emitted unique folder (#201) with its OWNED portrait.tga. Run the
# transform + `godot --path . --import` first if templates/ is absent.
const RAMZA_FOLDER := "res://assets/characters/templates/ramza_3/"

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_typewriter_reveals_full_text()
	_test_palette_runs_split_header_body()
	_test_arrow_up_down_and_remove()
	_test_offset_flips_portrait_arrow_gates_triangle()
	_test_portrait_fronts_template_folder()
	_test_typed_out_and_finish_typing()
	_test_inplace_swap()
	_test_box_geometry()
	_test_text_and_portrait_insets()
	_test_portrait_size_dock_facing()
	_test_comma_renders()
	_test_curves_asset_present()
	_test_open_tween_walks_every_curve()
	_test_close_tween_shrinks_curve4()
	_test_dialog_70_is_the_remap_to_class_10()
	_test_pagination_splits_name_plus_three_lines()
	_test_pagination_single_page_no_icon()
	_test_pagination_no_name_three_per_page()
	_test_page_icon_left_of_right_portrait()
	_test_page_icon_shadow_is_subtractive()
	_test_page_flip_sfx_on_advance()

	print("\n=== DialogueBoxTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DialogueBoxTest")
		get_tree().quit(1)
	else:
		print("[PASS] DialogueBoxTest")
		get_tree().quit(0)


func _make_box() -> DialogueBox:
	var box: DialogueBox = DialogueBoxClass.new()
	add_child(box)
	# throttle=2 → factor (3−throttle)=1 → 1 frame/glyph so frame-count
	# assertions read cleanly (this is also the boxed production default).
	box.throttle = 2
	return box


# {Color 08}Speaker{Newline}{Color 00}body text — the canonical chapel shape.
func _header_body_tokens() -> Array:
	return [
		{"type": "color", "palette": 8},
		{"type": "text", "value": "Ovelia"},
		{"type": "newline"},
		{"type": "color", "palette": 0},
		{"type": "text", "value": "Hello."},
	]


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


# ---------- tests ----------

func _test_typewriter_reveals_full_text() -> void:
	var box := _make_box()
	box.show_dialog(_header_body_tokens(), 0x12, -1, 0.0)
	var body: UIText = box.get_node("Body")
	_assert_eq(box.is_typing(), true, "reveal: typing right after show")
	# "Ovelia" (6) + newline + "Hello." (6) = 12 char nodes, 13 full chars.
	box.advance_frames(6)
	_assert_eq(body.visible_chars, 6, "reveal: 6 frames → 'Ovelia' shown")
	# Newline drains free with the next glyph; 6 more frames complete the body.
	box.advance_frames(6)
	_assert_eq(body.visible_chars, 12, "reveal: +6 frames → all 12 glyphs")
	# One more frame ticks past end-of-tokens.
	box.advance_frames(1)
	_assert_eq(box.is_typing(), false, "reveal: typewriter done")
	box.queue_free()


func _test_palette_runs_split_header_body() -> void:
	var box := _make_box()
	box.show_dialog(_header_body_tokens(), 0x12, -1, 0.0)
	var body: UIText = box.get_node("Body")
	# Char node 0 ('O') is the {Color 08} speaker run → CUSTOM remap to the ROM
	# speaker ramp (CLUT slots 9-11). Node 6 ('H', first body char) is the
	# {Color 00} body run → MENU palette = atlas body ramp, no tint. (Newline is
	# not a char node, so body starts at index 6.)
	var speaker_char: UIChar = body.get_child(0)
	var body_char: UIChar = body.get_child(6)
	# Speaker: CUSTOM palette, white font_color (no tint), light slot = slot 9.
	_assert_eq(speaker_char.get_palette(), UIChar.FontPalette.CUSTOM,
		"palette: speaker char uses CUSTOM remap")
	_assert_true(speaker_char.font_color.is_equal_approx(Color.WHITE),
		"palette: speaker char not tinted (font_color white)")
	var slot9 := Color8(106, 41, 16)  # CLUT slot 9 (speaker stroke / px1) — FRAME pal 0 RED
	var light_vec: Vector4 = speaker_char._material.get_shader_parameter("palette_light")
	_assert_true(Color(light_vec.x, light_vec.y, light_vec.z).is_equal_approx(slot9),
		"palette: speaker stroke → CLUT slot 9 (%s)" % str(light_vec))
	# Body: CUSTOM remap to the dark body ramp (slots 1-3), white font_color.
	# (The shared atlas is off-white for menus/prayer; the box body is remapped,
	# NOT atlas-direct — atlas-direct off-white was the shipped bug.)
	_assert_eq(body_char.get_palette(), UIChar.FontPalette.CUSTOM,
		"palette: body char uses CUSTOM remap")
	_assert_true(body_char.font_color.is_equal_approx(Color.WHITE),
		"palette: body char not tinted (font_color white)")
	var body_slot1 := Color8(49, 41, 32)  # CLUT slot 1 (body stroke / px1) — dark
	var body_light_vec: Vector4 = body_char._material.get_shader_parameter("palette_light")
	_assert_true(Color(body_light_vec.x, body_light_vec.y, body_light_vec.z).is_equal_approx(body_slot1),
		"palette: body stroke → CLUT slot 1 (%s)" % str(body_light_vec))
	box.queue_free()


func _test_arrow_up_down_and_remove() -> void:
	var box := _make_box()
	var tri: MeshInstance3D = box.get_node("Triangle")

	# align 2 (Bottom) → box below unit → arrow UP.
	box.show_dialog(_header_body_tokens(), 0x12, -1, 0.0)
	box._do_layout_update()
	_assert_true(tri.visible, "arrow: visible for 0x12")
	_assert_eq(box._arrow_up, true, "arrow: 0x12 → arrow UP")

	# align 1 (Top) → box above unit → arrow DOWN.
	box.show_dialog(_header_body_tokens(), 0x11, -1, 0.0)
	box._do_layout_update()
	_assert_eq(box._arrow_up, false, "arrow: 0x11 → arrow DOWN")

	# arrow-remove flag 0x8.
	box.show_dialog(_header_body_tokens(), 0x12 | 0x8, -1, 0.0)
	box._do_layout_update()
	_assert_eq(tri.visible, false, "arrow: 0x8 flag removes triangle")
	box.queue_free()


func _test_offset_flips_portrait_arrow_gates_triangle() -> void:
	# Two SEPARATE axes (decode dialogue_box_triangle_aim_decode.md §7.1 + §3 corr
	# #2 / §1c, both dynamically verified): the PORTRAIT side keys on the unit-offset
	# sign (= sign(local_b8)); the TRIANGLE mirror keys on the authored arrow operand
	# `msg[0x64] & 0xf0` (open_type high nibble), NOT the offset. Every chapel line
	# has `&0xf0 == 0`, so those tails are ALWAYS base orientation — the prior rule
	# (mirror on offset sign) wrongly flipped the non-zero-offset lines.
	var box := _make_box()
	var tri: MeshInstance3D = box.get_node("Triangle")

	# open_type 0x03 (&0xf0 == 0, the chapel case): tail NEVER mirrors, either sign.
	# Unit RIGHT (offset > 0): portrait right, tail base.
	box.show_dialog(_header_body_tokens(), 0x12, 0x10, 40.0, 0x03)
	box._do_layout_update()
	_assert_true(tri.scale.x > 0.0, "arrow&0xf0==0: tail base, not mirrored (offset+)")
	_assert_eq(box._portrait_on_left, false, "offset+: portrait on right")

	# Unit LEFT (offset < 0): portrait flips LEFT, but the tail STAYS base (the old
	# model wrongly mirrored here — the msg3 "wrong way" tail).
	box.show_dialog(_header_body_tokens(), 0x12, 0x10, -40.0, 0x03)
	box._do_layout_update()
	_assert_true(tri.scale.x > 0.0, "arrow&0xf0==0: tail base, not mirrored (offset-)")
	_assert_eq(box._portrait_on_left, true, "offset-: portrait on left")

	# Authored arrow high-nibble set (open_type 0x10, &0xf0 != 0): the tail mirrors,
	# gated on the OPERAND — here with offset+ (which the old offset-sign rule left
	# un-mirrored), proving the gate is the operand, not the sign.
	box.show_dialog(_header_body_tokens(), 0x12, 0x10, 40.0, 0x10)
	box._do_layout_update()
	_assert_true(tri.scale.x < 0.0, "arrow&0xf0!=0: tail mirrors (gated on operand, not offset)")
	box.queue_free()


# ADR-0072 #223: an in-battle speaker with an owned template folder fronts the
# flat sprite sheet with its OWNED portrait.tga; the observable is the portrait
# leaving sheet-window mode (`_template_mode`) and its crop origin moving to (0,0)
# vs the flat sheet window (80,456). The flat fallback stays load-bearing (generic
# speakers, or a folder with no portrait.tga), and an EVTFACE face still supersedes.
func _test_portrait_fronts_template_folder() -> void:
	var box := _make_box()
	var portrait: UIPortrait = box.get_node("Portrait")

	# Unique speaker with an owned folder → OWNED 48x32 crop (origin 0,0).
	box.show_dialog(_header_body_tokens(), 0x12, 1, 40.0, 0x03, null, RAMZA_FOLDER)
	_assert_true(portrait._template_mode, "template: owned portrait.tga bound (template mode)")
	_assert_approx(portrait._portrait_x, 0.0, "template: crop origin x=0")
	_assert_approx(portrait._portrait_y, 0.0, "template: crop origin y=0")

	# Generic speaker (no folder) → flat sheet window (80,456), load-bearing.
	box.show_dialog(_header_body_tokens(), 0x12, 1, 40.0, 0x03, null, "")
	_assert_eq(portrait._template_mode, false, "flat: no folder → sheet-window mode")
	_assert_approx(portrait._portrait_x, 80.0, "flat: sheet window x=80")
	_assert_approx(portrait._portrait_y, 456.0, "flat: sheet window y=456")

	# EVTFACE scripted face supersedes the folder (cutscene portrait wins).
	var face := EvtFaceCatalog.face_texture(0, 0)
	box.show_dialog(_header_body_tokens(), 0x92, 1, 40.0, 3, face, RAMZA_FOLDER)
	_assert_eq(portrait._template_mode, false, "evtface: folder ignored when a face is set")
	_assert_true(portrait.get_evtface_texture() == face, "evtface: face bound over folder")
	box.queue_free()


func _test_typed_out_and_finish_typing() -> void:
	var box := _make_box()
	var fired := [0]
	box.typed_out.connect(func() -> void: fired[0] += 1)
	box.show_dialog(_header_body_tokens(), 0x12, -1, 0.0)
	# finish_typing short-circuits the reveal and fires typed_out.
	box.finish_typing()
	var body: UIText = box.get_node("Body")
	_assert_eq(body.visible_chars, 12, "finish: all glyphs shown")
	_assert_eq(box.is_typing(), false, "finish: not typing")
	_assert_true(fired[0] >= 1, "finish: typed_out emitted")
	box.queue_free()


func _assert_approx(got: float, want: float, name: String) -> void:
	if is_equal_approx(got, want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# Geometry: the 0x1X/0x9X box FORCES 3 lines + chrome = 3*16 + 16 = 64px,
# regardless of the arrow/tail flags. The ROM grows the box bitmap by an
# in-box tail term (cc==0 +8 / cc==4 +16); we draw the tail as an external quad,
# so OUR frame stays 64px and the tail doesn't inflate the bottom margin
# (refinement 2026-06-27; battle.bin 0x80130ae0/0x80130b24).
func _test_box_geometry() -> void:
	var box := _make_box()
	# 0x12 → align 2, cc==0 (arrow present) → 64px (no in-box tail allowance).
	box.show_dialog(_header_body_tokens(), 0x12, -1, 0.0)
	_assert_approx(box._box_h_px, 64.0, "geometry: 2-line box forced to 64px (3 lines + chrome)")
	# Thinking bubble (cc==4) → still 64 (external tail).
	box.show_dialog(_header_body_tokens(), 0x12 | 0x4, -1, 0.0)
	_assert_approx(box._box_h_px, 64.0, "geometry: cc==4 bubble → 64px (external tail)")
	# No tail (cc==8) → 64px.
	box.show_dialog(_header_body_tokens(), 0x12 | 0x8, -1, 0.0)
	_assert_approx(box._box_h_px, 64.0, "geometry: cc==8 no-tail → 64px")
	box.queue_free()


# Text top inset = box_top + 8 (both align cases). The ROM's +8 align==2 extra
# clears an in-box tail we instead render externally, so we drop it (2026-06-27).
# Portrait top inset = box_top + 7 (both align cases), same rationale.
func _test_text_and_portrait_insets() -> void:
	var box := _make_box()
	var ppu: float = box.pixels_per_unit
	var body: UIText = box.get_node("Body")

	# align==1 (0x11) → top inset 8.
	box.show_dialog(_header_body_tokens(), 0x11, -1, 0.0)
	box._do_layout_update()
	_assert_approx(body.position.y, -8.0 * ppu, "inset: text top 8 for align!=2")

	# align==2 (0x12) → top inset 8 (external-arrow: no +8 tail clearance).
	box.show_dialog(_header_body_tokens(), 0x12, -1, 0.0)
	box._do_layout_update()
	_assert_approx(body.position.y, -8.0 * ppu, "inset: text top 8 for align==2 (external arrow)")

	# Portrait top inset: align==1 → 7.
	box.show_dialog(_header_body_tokens(), 0x11, 0x10, 40.0)
	box._do_layout_update()
	var portrait: UIPortrait = box.get_node("Portrait")
	_assert_approx(portrait.position.y, -7.0 * ppu, "inset: portrait top 7 for align!=2")

	# Portrait top inset: align==2 → 7 (same external-arrow rationale).
	box.show_dialog(_header_body_tokens(), 0x12, 0x10, 40.0)
	box._do_layout_update()
	_assert_approx(portrait.position.y, -7.0 * ppu, "inset: portrait top 7 for align==2 (external arrow)")
	box.queue_free()


# Portrait sampled 31px wide, docked right at box_w − 0x2A, right-dock faces left.
func _test_portrait_size_dock_facing() -> void:
	var box := _make_box()
	var portrait: UIPortrait = box.get_node("Portrait")
	# Unit to the RIGHT → portrait docks right.
	box.show_dialog(_header_body_tokens(), 0x12, 0x10, 40.0)
	box._do_layout_update()
	_assert_approx(portrait._portrait_tex_height, 31.0, "portrait: sampled 31px wide (not 32)")
	_assert_approx(portrait.position.x, box._px_x(box._box_w_px - 0x2A),
		"portrait: dock-right X == box_w − 0x2A")
	# Right-dock un-mirrored faces left in the ROM; our inverted flip flag → true.
	_assert_eq(portrait.flipped, true, "portrait: right-dock faces left (flipped)")
	# Left dock (unit left) → not flipped.
	box.show_dialog(_header_body_tokens(), 0x12, 0x10, -40.0)
	box._do_layout_update()
	_assert_eq(portrait.flipped, false, "portrait: left-dock faces right (not flipped)")
	box.queue_free()


# G1: the dialogue comma ',' lives ONLY at multi-byte font index 2196 (byte-seq
# 0xDA74). The baked char_to_index must include it so the renderer doesn't fall
# back to '?'. (parse_fft_font.CHAR_TO_INDEX_RENDER; re-bake the font.)
func _test_comma_renders() -> void:
	var font := UIFont.new()
	font.load_font("res://assets/fonts")
	var comma_idx := font.get_char_index(",")
	var q_idx := font.get_char_index("?")
	_assert_true(comma_idx != q_idx, "comma: ',' resolves to its own glyph, not '?'")
	_assert_eq(comma_idx, 2196, "comma: ',' → atlas index 2196")


# --- Box OPEN (grow) / CLOSE (shrink) tween (Part B / §C.2) -------------------

# The ROM-parsed curves asset must exist, have all 5 curves, and each terminate
# at t==1.0 (the CI half of the anti-silent-failure contract; the box also
# push_errors at runtime if this is absent).
func _test_curves_asset_present() -> void:
	var path := "res://assets/ui/dialogue_box_curves.json"
	_assert_true(FileAccess.file_exists(path),
		"curves: dialogue_box_curves.json present (run parse_dialogue_box_curves.py)")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_assert_true(false, "curves: JSON unreadable")
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	_assert_true(data is Dictionary and (data.get("curves") is Array),
		"curves: has a 'curves' array")
	var curves: Array = data.get("curves", [])
	_assert_eq(curves.size(), 5, "curves: exactly 5 curves")
	for c in curves:
		var t: Array = c.get("t", [])
		_assert_true(t.size() > 0 and absf(float(t[-1]) - 1.0) < 0.0001,
			"curves: curve %d terminates at t==1.0" % int(c.get("index", -1)))


# Every OPEN curve, in ONE process (charter: carry every assertion that shares
# its setup). Open Type & 0xf selects the curve; all four are heavily used in the
# live corpus (c0=822, c1=1078, c2=1085, c3=760 over 3,745 Display Messages), and
# **c0 and c1 are the only OVERSHOOT curves** — their `t` climbs past 1.0 and
# settles back, which is the visible bounce. Asserted here entry-by-entry.
#
# TIMING (the ROM's inner-loop repeat, `0x80132cac..0x80132d88`): each entry is
# HELD for `3 − event_text_glyph_throttle` = 2 vsyncs. `advance_tween_frames`
# counts VSYNCS, so one entry costs `tween_frames_per_entry()` of them and the
# box takes 2× as many frames to settle as the curve has entries.
func _test_open_tween_walks_every_curve() -> void:
	var hold: int = DialogueBoxClass.tween_frames_per_entry()
	_assert_eq(hold, 2, "tween: 2 vsyncs per curve entry (3 − throttle, throttle=1)")
	var curves := {
		0: [0.203125, 0.390625, 0.5625, 0.71875, 0.859375, 0.984375,
			1.0234375, 1.015625, 1.0078125, 1.0],
		1: [0.271484375, 0.533203125, 0.78515625, 1.02734375, 1.125, 1.1015625,
			1.078125, 1.0546875, 1.03125, 1.0078125, 1.0],
		2: [0.09375, 0.1875, 0.28125, 0.375, 0.46875, 0.5625,
			0.65625, 0.75, 0.84375, 0.9375, 1.0],
		3: [0.203125, 0.390625, 0.5625, 0.71875, 0.859375, 0.984375, 1.0],
	}
	for idx: int in [0, 1, 2, 3]:
		var want: Array = curves[idx]
		var box := _make_box()
		box.show_dialog(_header_body_tokens(), 0x12, -1, 0.0, idx)
		_assert_true(box.is_tweening(), "open c%d: tweening right after show" % idx)
		_assert_true(box.is_opening(), "open c%d: is_opening during the grow" % idx)
		_assert_approx(box.get_tween_scale(), want[0], "open c%d: entry 0" % idx)
		for i in range(1, want.size()):
			# The entry does NOT change until its hold expires (Gap 1: we used to
			# step every vsync, so every box opened 2x too fast).
			box.advance_tween_frames(hold - 1)
			_assert_approx(box.get_tween_scale(), want[i - 1],
				"open c%d: entry %d still held at vsync %d" % [idx, i - 1, i * hold - 1])
			box.advance_tween_frames(1)
			_assert_approx(box.get_tween_scale(), want[i], "open c%d: entry %d" % [idx, i])
		# The final entry is held too; only then does the tween settle and end.
		box.advance_tween_frames(hold - 1)
		_assert_true(box.is_tweening(), "open c%d: still tweening on the last entry's hold" % idx)
		box.advance_tween_frames(1)
		_assert_approx(box.get_tween_scale(), 1.0, "open c%d: settled at full" % idx)
		_assert_true(not box.is_tweening(), "open c%d: tween done" % idx)
		_assert_true(not box.is_opening(), "open c%d: not opening once settled" % idx)
		box.queue_free()
	# The overshoot curves must actually overshoot — a curve table that silently
	# clamped to 1.0 would pass every assertion above only because the expected
	# values came from the same clamped source.
	for idx: int in [0, 1, 2, 3]:
		var arr: Array = curves[idx]
		var peak := 0.0
		for v in arr:
			peak = maxf(peak, float(v))
		if idx <= 1:
			_assert_true(peak > 1.0, "open c%d: overshoots past full size (bounce)" % idx)
		else:
			_assert_approx(peak, 1.0, "open c%d: no overshoot (peak == 1.0)" % idx)


# CLOSE always uses curve 4 (linear, 4 entries → 8 vsyncs). Size fraction = 1 − t,
# so the box shrinks .75 → .5 → .25 → 0, then tears down (hidden + inactive).
#
# Also the Gap-3 assertion: the ROM's open tween is fiber-BLOCKING, so the
# typewriter must not reveal a single glyph until the box has finished growing.
func _test_close_tween_shrinks_curve4() -> void:
	var hold: int = DialogueBoxClass.tween_frames_per_entry()
	var box := _make_box()
	box.show_dialog(_header_body_tokens(), 0x12, -1, 0.0, 3)
	# Gap 3: pumping the box's own clock while it is still opening types nothing.
	var body: UIText = box.get_node("Body")
	var shown_before := body.visible_chars
	box._process(1.5 / 60.0)
	_assert_true(box.is_opening(), "open+type: still opening after one vsync")
	_assert_eq(body.visible_chars, shown_before,
		"open+type: no glyph revealed while the box is still growing")
	box.finish_typing()
	# Settle the open tween so the close starts from full size. c3 = 7 entries.
	box.advance_tween_frames(7 * hold)
	_assert_approx(box.get_tween_scale(), 1.0, "close: at full size before close")
	_assert_true(not box.is_tweening(), "close: open tween finished in 7*hold vsyncs")
	box.close()
	_assert_true(box.is_tweening(), "close c4: tweening after close()")
	_assert_true(not box.is_opening(), "close c4: shrinking is not opening")
	var want := [0.75, 0.5, 0.25, 0.0]
	_assert_approx(box.get_tween_scale(), want[0], "close c4: entry 0 = .75")
	for i in range(1, want.size()):
		box.advance_tween_frames(hold - 1)
		_assert_approx(box.get_tween_scale(), want[i - 1],
			"close c4: entry %d still held" % (i - 1))
		box.advance_tween_frames(1)
		_assert_approx(box.get_tween_scale(), want[i], "close c4: entry %d" % i)
	# The last entry's hold runs out → teardown.
	box.advance_tween_frames(hold)
	_assert_true(not box.visible, "close c4: box hidden after shrink")
	_assert_true(not box.is_active(), "close c4: box inactive after shrink")
	box.queue_free()


# The `Dialog & 0x70 == 0x70` class is the ROM's REMAP-to-0x10 case, NOT a second
# box family. `0x80130930`: `(Dialog & 0x70) == 0x70` → `local_d2 = (Dialog & 0x1C) | 0x10`
# (plus an auto-derived align from `dialog_auto_align_from_facing`), and only THEN is
# `local_d0 = local_d2 & 0x70` taken at `0x80130980`. So the 814 live `Dialog = 0x70`
# messages reach the gate at `0x8013132c` as class 0x10 and get the SAME
# `dialog_box_open_close_tween` grow (and the curve-4 close at `0x80132774`) as every
# other portrait box — they do NOT take the `FUN_80132914` centre-out percent reveal.
#
# This is a REGRESSION GUARD: a 2026-09-10 handoff read `local_d0` off the raw Dialog
# byte, concluded those 814 messages were a separate family, and proposed routing them
# to a centre-out reveal with no close animation. That would have been a regression.
func _test_dialog_70_is_the_remap_to_class_10() -> void:
	var box := _make_box()
	# 0x70 must animate exactly like 0x12 (class 0x10) — same curve, same close.
	box.show_dialog(_header_body_tokens(), 0x70, -1, 0.0, 1)
	_assert_true(box.is_opening(), "0x70: opens with the family-A grow tween")
	_assert_approx(box.get_tween_scale(), 0.271484375, "0x70: on open curve 1, entry 0")
	box.advance_tween_frames(11 * DialogueBoxClass.tween_frames_per_entry())
	_assert_true(not box.is_tweening(), "0x70: open settles like class 0x10")
	box.finish_typing()
	box.close()
	_assert_true(box.is_tweening(), "0x70: SHRINKS on close (family A), not a plain vanish")
	_assert_approx(box.get_tween_scale(), 0.75, "0x70: close runs curve 4")
	box.queue_free()


# --- Pagination (fixed 3-line window; decode §1.1) ---------------------------

# The real Orbonne box: name + 3 dialogue lines → 2 pages. Page 1 = name + first
# 2 dialogue lines + "more" icon; page 2 = 3rd line, name dropped, NO icon. Box
# height stays the fixed 3-line window (64px) on both pages.
func _gafgarion_tokens() -> Array:
	return [
		{"type": "color", "palette": 8},
		{"type": "text", "value": "Gafgarion"},
		{"type": "newline"},
		{"type": "color", "palette": 0},
		{"type": "text", "value": "Is this going to be alright,"},
		{"type": "newline"},
		{"type": "text", "value": "Agrias?"},
		{"type": "newline"},
		{"type": "text", "value": "This is an urgent issue for us."},
	]


func _test_pagination_splits_name_plus_three_lines() -> void:
	var box := _make_box()
	box.show_dialog(_gafgarion_tokens(), 0x12, 0x10, 40.0)
	box._do_layout_update()
	var body: UIText = box.get_node("Body")

	# Two pages; page 1 on screen with the "more" icon.
	_assert_eq(box.page_count(), 2, "page: name + 3 lines → 2 pages")
	_assert_eq(box.current_page(), 0, "page: starts on page 1")
	_assert_true(box.has_more_pages(), "page: page 1 has a next page")
	_assert_approx(box._box_h_px, 64.0, "page: page 1 height = 3-line window")

	# Page 1 body = name + first 2 dialogue lines.
	box.finish_typing()
	_assert_eq(body.text, "Gafgarion\nIs this going to be alright,\nAgrias?",
		"page: page 1 = name + 2 dialogue lines")
	_assert_true(box.is_page_icon_visible(), "page: 'more' icon shown on page 1")

	# Advance to page 2 → name dropped, no icon, still 3-line window.
	var advanced: bool = box.advance_page()
	box._do_layout_update()
	_assert_true(advanced, "page: advance_page reports success")
	_assert_eq(box.current_page(), 1, "page: now on page 2")
	_assert_eq(box.has_more_pages(), false, "page: page 2 is the last page")
	box.finish_typing()
	_assert_eq(body.text, "This is an urgent issue for us.",
		"page: page 2 = 3rd line, name dropped")
	_assert_eq(box.is_page_icon_visible(), false, "page: no icon on last page")
	_assert_approx(box._box_h_px, 64.0, "page: page 2 height = 3-line window")

	# Advancing past the last page is a no-op.
	_assert_eq(box.advance_page(), false, "page: advance past last page is a no-op")
	box.queue_free()


# A name + 2 dialogue lines fits one page → no pagination, no icon.
func _test_pagination_single_page_no_icon() -> void:
	var box := _make_box()
	var toks := [
		{"type": "color", "palette": 8},
		{"type": "text", "value": "Ovelia"},
		{"type": "newline"},
		{"type": "color", "palette": 0},
		{"type": "text", "value": "Line one,"},
		{"type": "newline"},
		{"type": "text", "value": "line two."},
	]
	box.show_dialog(toks, 0x12, -1, 0.0)
	box._do_layout_update()
	_assert_eq(box.page_count(), 1, "single: name + 2 lines = 1 page")
	_assert_eq(box.has_more_pages(), false, "single: no next page")
	_assert_eq(box.is_page_icon_visible(), false, "single: no 'more' icon")
	box.queue_free()


# With NO speaker/name line, every page carries up to 3 dialogue lines.
func _test_pagination_no_name_three_per_page() -> void:
	var box := _make_box()
	var toks := [
		{"type": "color", "palette": 0},
		{"type": "text", "value": "a"},
		{"type": "newline"},
		{"type": "text", "value": "b"},
		{"type": "newline"},
		{"type": "text", "value": "c"},
		{"type": "newline"},
		{"type": "text", "value": "d"},
	]
	box.show_dialog(toks, 0x12, -1, 0.0)
	var body: UIText = box.get_node("Body")
	_assert_eq(box.page_count(), 2, "no-name: 4 lines → 2 pages (3 + 1)")
	box.finish_typing()
	_assert_eq(body.text, "a\nb\nc", "no-name: page 1 = first 3 lines")
	box.advance_page()
	box.finish_typing()
	_assert_eq(body.text, "d", "no-name: page 2 = 4th line")
	box.queue_free()


# Issue #1: with a portrait docked on the RIGHT, the page-turn "more" icon must
# sit to the LEFT of the portrait (right of the text), not overlap it in the box
# bottom-right corner. Anchored to the portrait's left edge
# (box_w − PORTRAIT_RIGHT_INSET_PX). No portrait → corner anchor unchanged.
func _test_page_icon_left_of_right_portrait() -> void:
	var box := _make_box()
	# Right-docked portrait (offset > 0) + a 2-page message (icon shown on page 1).
	box.show_dialog(_gafgarion_tokens(), 0x12, 0x10, 40.0)
	box._do_layout_update()
	var icon: MeshInstance3D = box.get_node("PageIcon")
	var portrait: UIPortrait = box.get_node("Portrait")
	_assert_eq(box._portrait_on_left, false, "icon: portrait docked right")
	_assert_true(box.is_page_icon_visible(), "icon: 'more' icon shown on page 1")

	# Icon right edge (centre + half-width) must be at/left of the portrait's left
	# edge, so the two don't overlap.
	var sz := box._page_icon_cell_size()
	var icon_half_w := sz.x * box._par() * box.pixels_per_unit * 0.5
	var icon_right_x := icon.position.x + icon_half_w
	var portrait_left_x := box._px_x(box._box_w_px - 0x2A)
	_assert_true(icon_right_x <= portrait_left_x + 0.0001,
		"icon: right edge (%.4f) left of portrait left edge (%.4f)" % [icon_right_x, portrait_left_x])

	# Without a portrait the icon keeps the box bottom-right corner anchor.
	box.show_dialog(_gafgarion_tokens(), 0x12, -1, 0.0)
	box._do_layout_update()
	var corner_left_px := box._box_w_px - box.PAGE_ICON_RIGHT_INSET_PX - sz.x
	var corner_center_x := box._px_x(corner_left_px) + icon_half_w
	_assert_approx(icon.position.x, corner_center_x, "icon: no-portrait → box-corner anchor")
	box.queue_free()


# The one unimplemented global dialogue sound: "Flip Page" (PSX system SFX
# 0x2d/45) fires on a multi-page boxed-dialogue advance — once per real page
# turn, NEVER on the final advance/close (the box has no more pages). Emitted
# from advance_page()'s success path as the `ui.dialogue_page_flip` cue; the box
# open/close chrome is intentionally silent.

# The page-turn icon's drop shadow is PSX ABR mode 2 (framebuffer − texel), NOT
# opaque ink. In the ROM's 0x7cbc active-label CLUT the two shadow entries carry
# STP=1 — idx 14 = 0x94a5 (41,41,41) and idx 15 = 0x8842 (16,16,16) — and every
# one of the four curl phases lays them in an L down the right 2 columns and
# across the bottom 2 rows. Drawn opaque they read as a black blob in the box's
# bottom-right corner (the reported bug); drawn subtractively they read as the
# faint darkening the PSX shows.
#
# Oracle: research/working_documents/scenario_1_captures/dialogue_pagination_images/
# page1_more_icon.png (native 256x240, icon at screen (164,65), phase 2). Against
# that cell 73/73 STP=0 texels are byte-exact to the CLUT and 30/30 STP=1 texels
# are byte-exact to `background − CLUT[i]` — e.g. tan (168,160,136) under idx 14
# reads (128,120,96), exactly −(40,40,40). Zero mismatches: ABR=2, not a 50% mix.
#
# TWO independent faults produced the blob, and either one alone keeps it, so
# this arm covers both.
func _test_page_icon_shadow_is_subtractive() -> void:
	var box := _make_box()
	box.show_dialog(_gafgarion_tokens(), 0x12, -1, 0.0)
	box._do_layout_update()
	var icon: MeshInstance3D = box.get_node("PageIcon")
	var omat := icon.material_override as ShaderMaterial

	# --- Fault 1: the CLUT must keep the STP bits ----------------------------
	# The icon's palette is the ROM's 0x7cbc, sourced from the extractor (which
	# already gets the alphas right) rather than re-typed in GDScript.
	var pal_img: Image = box._page_icon_palette().get_image()
	var rom: Array = RangeTileAtlas.new().window_tab_colors()
	_assert_eq(rom.size(), 16, "shadow: 0x7cbc CLUT has 16 entries")
	var drift := 0
	for i in 16:
		if not pal_img.get_pixel(i, 0).is_equal_approx(rom[i]):
			drift += 1
	_assert_eq(drift, 0, "shadow: icon CLUT == RangeTileAtlas.window_tab_colors() (0x7cbc)")
	# The two shadow entries: STP=1 ⇒ alpha 128, NOT the 255 the hardcode gave.
	_assert_true(pal_img.get_pixel(14, 0).is_equal_approx(Color8(41, 41, 41, 128)),
		"shadow: idx 14 keeps STP=1 (41,41,41,128)")
	_assert_true(pal_img.get_pixel(15, 0).is_equal_approx(Color8(16, 16, 16, 128)),
		"shadow: idx 15 keeps STP=1 (16,16,16,128)")
	# ...while the body ink (outline 5, cream 8, highlight 12) stays STP=0/opaque.
	for i in [5, 8, 12]:
		_assert_approx(pal_img.get_pixel(i, 0).a, 1.0,
			"shadow: idx %d body ink stays opaque (STP=0)" % i)

	# --- Fault 2: the two passes must key on COMPLEMENTARY halves ------------
	# `vitals_sprite` is opaque by contract (ADR-0077: never write ALPHA) and its
	# key WAS `c.a < 0.5`. Since 128/255 = 0.502 an STP=1 texel survives that
	# discard and still draws opaque — so fixing the palette alone changes
	# nothing on screen. Both keys must sit above 0.502 for the split to be a
	# partition rather than an overlap. No framebuffer readback exists in a unit
	# test, so this is read off the shader source (as DetailUnauthoredDepthTest
	# reads its render_modes).
	var op_src := FileAccess.get_file_as_string(box.PAGE_ICON_SHADER_PATH)
	_assert_true(op_src.contains("c.a < 0.9"),
		"shadow: vitals_sprite keys STP=0 only (c.a < 0.9, not the old < 0.5)")
	# BOTH sub twins take the complementary key — whichever the build routes to.
	for sp in [box.PAGE_ICON_SHADOW_SHADER_PATH, box.PAGE_ICON_SHADOW_FOLD_SHADER.resource_path]:
		var sub_src := FileAccess.get_file_as_string(sp)
		_assert_true(sub_src.contains("c.a > 0.9"),
			"shadow: %s keys STP=1 only (c.a > 0.9)" % sp.get_file())
	# The fold twin must NOT take a gamma knob: inside the fold scratch the values are already
	# display-space, so the raw CLUT colour IS the ROM subtract amount (that is the whole point
	# of folding it rather than approximating with pow()).
	var fold_src := _strip_line_comments(
		FileAccess.get_file_as_string(box.PAGE_ICON_SHADOW_FOLD_SHADER.resource_path))
	_assert_true(not fold_src.contains("pow("),
		"shadow: the fold twin applies NO pow (display-space subtrahend)")
	_assert_true(fold_src.contains("compositor_layer"),
		"shadow: the fold twin declares compositor_layer")

	# --- The subtractive pass ------------------------------------------------
	var shadow: MeshInstance3D = box.get_node_or_null("PageIconShadow")
	_assert_true(shadow != null, "shadow: a second, subtractive quad exists")
	if shadow == null:
		box.queue_free()
		return
	var smat := shadow.material_override as ShaderMaterial
	# PSX subtracts in the 8-bit framebuffer (DISPLAY space); Godot's main target is LINEAR, so
	# an in-scene blend_sub over-darkens. The engine fold seeds a display-space scratch from the
	# opaque scene and runs the hardware sub THERE, which is byte-for-byte the ROM's abr=2 — so
	# on a folding build the sub pass MUST route to the compositor_layer twin, not the in-scene one.
	var folds: bool = DialogueBoxClass.Fold.owns()
	var want_shader: String = box.PAGE_ICON_SHADOW_FOLD_SHADER.resource_path if folds \
		else box.PAGE_ICON_SHADOW_SHADER_PATH
	_assert_true(smat != null and smat.shader != null
			and smat.shader.resource_path == want_shader,
		"shadow: sub pass runs the %s subtractive shader" % ("FOLD" if folds else "in-scene"))
	# ...and on a folding build it is actually ENROLLED in the shared fold layer. Without the
	# render_layer membership the material would fold in name only and never reach Pass B.
	if folds:
		_assert_true(shadow.render_layer != null,
			"shadow: sub pass is enrolled in the fold layer (render_layer set)")
	# The box frame must be OPAQUE, or it is not in the fold's Pass A seed and the shadow would
	# subtract from whatever sits behind the box instead of from its tan body.
	_assert_true((box.get_node("Frame") as UIFrame).opaque,
		"shadow: the box frame draws OPAQUE so it lands in the fold seed")
	# Same quad, same rect: the discards are complementary, so the two passes
	# tile the cell instead of overlapping (no depth-occlusion trick needed).
	_assert_true(shadow.position.is_equal_approx(icon.position),
		"shadow: sub pass covers the same rect as the opaque pass")
	_assert_true((shadow.mesh as QuadMesh).size.is_equal_approx((icon.mesh as QuadMesh).size),
		"shadow: sub pass quad is the same size as the opaque pass")
	# It must ride the same 4-phase curl animation.
	box._page_icon_phase = 2
	box._update_page_icon_frame()
	_assert_true((smat.get_shader_parameter("cell") as Vector4).is_equal_approx(
			omat.get_shader_parameter("cell") as Vector4),
		"shadow: sub pass tracks the animation phase (same `cell`)")
	# ...and the same palette, so one CLUT feeds both halves of the split.
	_assert_true(smat.get_shader_parameter("palette_tex")
			== omat.get_shader_parameter("palette_tex"),
		"shadow: both passes sample ONE CLUT")
	# A subtractive pass reads what is already drawn, so it must land after the
	# box body/text AND after the opaque icon half.
	_assert_true(smat.render_priority > omat.render_priority,
		"shadow: sub pass draws after the opaque pass (rp %d > %d)"
			% [smat.render_priority, omat.render_priority])

	# Visibility rides the opaque pass: shown on page 1, gone on the last page.
	_assert_eq(shadow.visible, icon.visible, "shadow: visible with the icon on page 1")
	_assert_true(icon.visible, "shadow: (page 1 shows the icon)")
	box.advance_page()
	box._do_layout_update()
	_assert_eq(shadow.visible, icon.visible, "shadow: hidden with the icon on the last page")
	_assert_eq(icon.visible, false, "shadow: (last page hides the icon)")
	box.queue_free()


# Drop whole-line `//` comments from shader source before asserting on CODE. Only lines whose
# FIRST non-blank characters are `//` are dropped — a naive `//` strip would also eat every
# `res://` path, and the comments here legitimately discuss `pow()` while the code must not use it.
func _strip_line_comments(src: String) -> String:
	var out := PackedStringArray()
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("//"):
			out.append(line)
	return "\n".join(out)

func _test_page_flip_sfx_on_advance() -> void:
	# Name + 7 dialogue lines → 3 pages (name+2, 3, 2): two real page turns.
	var toks := [
		{"type": "color", "palette": 8},
		{"type": "text", "value": "Gafgarion"},
		{"type": "newline"},
		{"type": "color", "palette": 0},
		{"type": "text", "value": "line one"},
		{"type": "newline"}, {"type": "text", "value": "line two"},
		{"type": "newline"}, {"type": "text", "value": "line three"},
		{"type": "newline"}, {"type": "text", "value": "line four"},
		{"type": "newline"}, {"type": "text", "value": "line five"},
		{"type": "newline"}, {"type": "text", "value": "line six"},
		{"type": "newline"}, {"type": "text", "value": "line seven"},
	]
	# Capture only the page-flip cue (the typewriter also emits ui.text_typing).
	var flips := [0]
	var sub := func(n: String, _b: String, _s: int) -> void:
		if n == "ui.dialogue_page_flip":
			flips[0] += 1
	SfxRouter.cue_requested.connect(sub)

	var box := _make_box()
	# #1273 — the box now STATES `page_turned` and the host names the cue. Wiring it
	# here is not a test workaround: it is exactly what `ScenarioPlayerScene` does to
	# each of its three pooled boxes, so this arm still measures the cue end to end
	# rather than being downgraded to a signal-count.
	UIWiring.wire_dialogue_box(box)
	box.show_dialog(toks, 0x12, 0x10, 40.0)
	_assert_eq(box.page_count(), 3, "flip-sfx: name + 7 lines → 3 pages")
	# show_dialog itself must NOT blip (opening a box is silent).
	_assert_eq(flips[0], 0, "flip-sfx: no blip on box open")

	# Each real page turn blips exactly once.
	_assert_true(box.advance_page(), "flip-sfx: turn to page 2 succeeds")
	_assert_eq(flips[0], 1, "flip-sfx: one blip after first turn")
	_assert_true(box.advance_page(), "flip-sfx: turn to page 3 succeeds")
	_assert_eq(flips[0], 2, "flip-sfx: one blip per turn (two turns)")

	# Advancing past the last page is a no-op → NO blip (never on close).
	_assert_eq(box.advance_page(), false, "flip-sfx: past-last advance is a no-op")
	_assert_eq(flips[0], 2, "flip-sfx: no blip on the final (no-more-pages) advance")

	SfxRouter.cue_requested.disconnect(sub)
	box.queue_free()


func _test_inplace_swap() -> void:
	var box := _make_box()
	box.show_dialog(_header_body_tokens(), 0x12, -1, 0.0)
	box.finish_typing()
	# {51}-style swap: re-show new speaker/body on the SAME box (no teardown).
	var swap := [
		{"type": "color", "palette": 8},
		{"type": "text", "value": "Agrias"},
		{"type": "newline"},
		{"type": "color", "palette": 0},
		{"type": "text", "value": "Yes."},
	]
	box.show_dialog(swap, 0x92, -1, 0.0)
	var body: UIText = box.get_node("Body")
	_assert_eq(body.text, "Agrias\nYes.", "swap: text replaced in place")
	_assert_true(box.is_typing(), "swap: typewriter restarted")
	box.advance_frames(20)
	_assert_eq(body.visible_chars, 10, "swap: new text reveals fully")
	box.queue_free()
