extends Node3D

## PROTOTYPE — THROWAWAY. Not production, not tested, not referenced by src/.
##
## Answers ONE question that ADR-0268 could not settle on paper (handoff §2.1): what does
## walking ←/→ across `Enable · Do · To · If` on one row FEEL like, versus drilling
## SLOT -> PART -> CHOICE the way the shipped [GambitSurface] does?
##
## It renders the row layout dec. 1 chose, in the real 256x240 frame, in the real FONT.BIN,
## inside the real UI3 window — because the question is about pixels and presses, and an
## arithmetic budget cannot answer it. Everything here is copied from [GambitSurfaceMenu]
## rather than shared with it: a prototype that refactors its subject has changed the thing
## it was measuring.
##
## Run it: see `tools/proto_gambit_row.gd`.

const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")
const UIMenuText = preload("res://src/ui3/UIMenuText.gd")
const GloveCursorBob = preload("res://src/ui3/GloveCursorBob.gd")

const _SPRITE_SHADER := "res://src/ui3/shaders/vitals_sprite.gdshader"
const _SHADOW_SHADER := "res://src/ui3/shaders/menu_cursor_shadow.gdshader"
const _SHADOW_FOLD_SHADER := preload("res://src/ui3/shaders/menu_cursor_shadow_fold.gdshader")
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

## The shade-band swap the Learn list already uses for live-vs-dim rows (LearnAbilityMenu
## §8). Reused here as the PART cursor: the focused part is LIT, its siblings DIM. It costs
## ZERO px, which is the whole reason to try it before spending 24 px on chevrons.
const LIT_INKS: Array[Color] = [
	Color8(49, 41, 33, 255), Color8(82, 82, 66, 255), Color8(132, 123, 107, 255),
]
const DIM_INKS: Array[Color] = [
	Color8(99, 90, 74, 255), Color8(115, 107, 90, 255), Color8(140, 132, 115, 255),
]

## The window. Same home as the shipped surface's (`GambitSurfaceMenu.GAMBIT_CONTAINER`), so
## the two are photographed in the same box and the comparison is about the ROW, not the frame.
const CONTAINER := Rect2(12, 134, 232, 104)

const RP_FRAME := 46
const RP_ROW_TEXT := 49
const RP_HEADER := 50
const RP_CURSOR_SHADOW := 51
const RP_CURSOR_LIT := 52

const _BOB_TICK := 1.0 / 60.0

## The parts, left to right — the sentence's reading order (ADR-0268 dec. 1), with the enable
## flag as the LEFTMOST part rather than a button (dec. 4).
enum Part { ENABLE, DO, TO, IF }
const PART_COUNT := 4

## Column x, display px, measured off the widest real option string in each column (see
## `tools/proto_gambit_row.gd --measure`). The row runs x=28..236 inside a window at x=16
## 224 px wide: 12 px of left inset (the shipped menu's `name_x`) and 4 px of right pad.
const COL_X := {
	Part.ENABLE: 26.0,
	Part.DO: 50.0,
	Part.TO: 124.0,
	Part.IF: 186.0,
}


const ROW0_Y := CONTAINER.position.y + 18.0
const ROW_PITCH := 16.0

## The rows: `{enabled: bool, do: String, to: String, iff: String, extra: int}`. Set before
## add_child, like every sibling picker's `entries`.
var rows: Array = []
var title: String = "Gambit"
## `true` renders the focused part with a `→` chevron in front of it INSTEAD of the shade
## swap — the 10-px-per-row variant, so the look can price it against the free one.
var chevron_cursor: bool = false
## `true` moves the GLOVE itself to the focused part's column instead of parking it at the
## row's left edge — one cursor for both axes, and it is the ROM's own cursor rather than a
## glyph invented for this screen. The row still goes LIT, so "which row" survives.
var part_glove: bool = false

signal chosen(row: int, part: int)
signal cancelled

var _atlas: RangeTileAtlas
var _menu_text: UIMenuText
var _window: UI3Element
var _rows_elem: UI3Element
var _header_elem: UI3Element
var _cursor_elem: UI3Element

var _glove_lit_pal: ImageTexture
var _glove_shadow_pal: ImageTexture
var _lit_holder: Node3D
var _shadow_holder: Node3D
var _bob_frame: int = 0
var _bob_accum: float = 0.0
var _moving_frames: int = 0
var _idle_pairs: Array = []
var _select_pairs: Array = []

var _row: int = 0
var _part: int = Part.DO
## Widest px any row actually painted, per column — the honest budget, collected while
## mounting. ADR-0268 dec. 2's numbers were computed against a 10-px space; the renderer
## advances a space 4 px (`DialogueBox.SPACE_WIDTH_PX`), so this reports what is really there.
var measured_right_edge: float = 0.0
var _if_right: float = 0.0


func _ready() -> void:
	_atlas = RangeTileAtlas.new()
	_menu_text = UIMenuText.new()
	_glove_lit_pal = _palette_from_colors(_atlas.menu_glove_lit_colors())
	_glove_shadow_pal = _palette_from_colors(_atlas.menu_glove_shadow_colors())
	_idle_pairs = GloveCursorBob.load_glove_pairs("glove_idle")
	_select_pairs = GloveCursorBob.load_glove_pairs("glove_select")
	_build_window()
	_build_content()
	_window.open()
	_place_cursor()


func _build_window() -> void:
	var c := CONTAINER
	_window = UI3Element.new({
		"id": "protogambitrow.window",
		"rect": c,
		"authored_home": Vector2(c.position),
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.STRIPE,
		"frame_center_patch": Vector4(6, 7, 21, 17),
		"frame_rp": RP_FRAME,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"aperture_pad": Vector4(0, 0, 0, 0),
		"depth_rung": -6,
		# BOTH cadences, or the window builds NOTHING and does it silently (ADR-0097 §2).
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
	})
	add_child(_window)

	_rows_elem = UI3Element.new({
		"id": "protogambitrow.rows",
		"rect": Rect2(c.position.x, c.position.y + 14.0, c.size.x, c.size.y - 14.0),
		"authored_home": Vector2(c.position.x, ROW0_Y),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	_window.add_child(_rows_elem)

	_header_elem = UI3Element.new({
		"id": "protogambitrow.header",
		"rect": Rect2(c.position.x + 8.0, c.position.y + 3.0, 96.0, 12.0),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	_window.add_child(_header_elem)

	_cursor_elem = UI3Element.new({
		"id": "protogambitrow.cursor",
		"rect": c,
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_cursor_elem.name = "ProtoGloveCursor"
	_window.add_child(_cursor_elem)


func _build_content() -> void:
	for e: UI3Element in [_rows_elem, _header_elem, _cursor_elem]:
		for ch in e.get_children():
			ch.free()
	_lit_holder = null
	_shadow_holder = null
	measured_right_edge = 0.0

	var h := _header_elem
	_menu_text.mount(h, title, h.rel_world(CONTAINER.position.x + 8.0, CONTAINER.position.y + 3.0)
		+ h.z_for(RP_HEADER), RP_HEADER, h.ppu(), null)

	var s := _rows_elem
	for i in range(rows.size()):
		_mount_row(s, i, ROW0_Y + i * ROW_PITCH)

	_shadow_holder = _mount_glove(_atlas.menu_glove_shadow_rect(), _glove_shadow_pal,
		_SHADOW_SHADER, RP_CURSOR_SHADOW)
	_lit_holder = _mount_glove(_atlas.menu_glove_lit_rect(), _glove_lit_pal,
		_SPRITE_SHADER, RP_CURSOR_LIT)
	_place_cursor()


## One gambit, read across: `○ Attack   Nearest Foe   HP < 50% +1`.
##
## The enable flag is the ROM's own `○` / `·` pair (both in FONT.BIN), not a checkbox cell —
## there is no baked checkbox and the surface is game-original, so a glyph is what it can
## honestly wear. `·` rather than blank, because an EMPTY leftmost part reads as a rendering
## failure and an off flag has to read as a state. `·` was tried first and is INVISIBLE at
## 4 px on tan — it reads as dirt on the window, not as "this rule is off".
func _mount_row(s: UI3Element, i: int, y: float) -> void:
	var r: Dictionary = rows[i]
	var focused_row := i == _row
	for pv in [Part.ENABLE, Part.DO, Part.TO, Part.IF]:
		var p: int = pv
		var text := _part_text(r, p)
		var lit: bool = focused_row and p == _part
		var x: float = COL_X[p]
		if chevron_cursor:
			if lit:
				_mount_at(s, "→", x - 10.0, y, LIT_INKS)
			lit = focused_row
		elif part_glove:
			lit = focused_row
		_mount_at(s, text, x, y, LIT_INKS if lit else DIM_INKS)
		var right := x + _menu_text.measure(text)
		measured_right_edge = maxf(measured_right_edge, right)
		if p == Part.IF:
			_if_right = right
	# dec. 3's `+N`: a slot carrying conditions the row cannot show says so, because a screen
	# that silently drops what the player cannot see is worse than one that cannot author it.
	# `+N` rides the END of the If value, not a fixed column. At a fixed x it either collides
	# with a long condition or floats free of a short one, and both readings are wrong: the
	# mark belongs TO that value.
	var extra := int(r.get("extra", 0))
	if extra > 0:
		_mount_at(s, "+%d" % extra, _if_right + 4.0, y, DIM_INKS)
		measured_right_edge = maxf(measured_right_edge, _if_right + 4.0 + 12.0)


func _mount_at(s: UI3Element, text: String, x: float, y: float, inks: Array) -> void:
	_menu_text.mount(s, text, s.rel_world(x, y) + s.z_for(RP_ROW_TEXT),
		RP_ROW_TEXT, s.ppu(), null, inks)


func _part_text(r: Dictionary, p: int) -> String:
	match p:
		Part.ENABLE:
			return "○" if bool(r.get("enabled", true)) else "×"
		Part.DO:
			return String(r.get("do", "Wait"))
		Part.TO:
			return String(r.get("to", "Self"))
		_:
			return String(r.get("iff", "Always"))


# -----------------------------------------------------------------------------
# Navigation — the whole point of the prototype.
# -----------------------------------------------------------------------------
## ←/→ CLAMP rather than wrap. A sentence has a first word and a last word; wrapping from
## `If` back to the enable flag would teleport the cursor across the row, and the row is the
## thing this layout asks the player to read left to right.
func move_part(step: int) -> void:
	var next := clampi(_part + step, 0, PART_COUNT - 1)
	if next == _part:
		return
	_part = next
	_bump()


func move_row(step: int) -> void:
	if rows.is_empty():
		return
	_row = (_row + step + rows.size()) % rows.size()
	_bump()


## L1/R1 raise/lower the focused slot (dec. 6) — a real verb, because slot order IS priority.
func reorder(step: int) -> void:
	var to := _row + step
	if to < 0 or to >= rows.size():
		return
	var moved: Dictionary = rows[_row]
	rows.remove_at(_row)
	rows.insert(to, moved)
	_row = to
	_bump()


func toggle_enable() -> void:
	if rows.is_empty():
		return
	var r: Dictionary = rows[_row]
	r["enabled"] = not bool(r.get("enabled", true))
	_bump()


func confirm() -> void:
	if _part == Part.ENABLE:
		toggle_enable()   # dec. 4: ○ on the flag TOGGLES; it opens no list
		return
	chosen.emit(_row, _part)


func cancel() -> void:
	cancelled.emit()


func set_value(row: int, part: int, text: String) -> void:
	if row < 0 or row >= rows.size():
		return
	var key: String = {Part.DO: "do", Part.TO: "to", Part.IF: "iff"}.get(part, "")
	if key == "":
		return
	(rows[row] as Dictionary)[key] = text
	_bump()


func _bump() -> void:
	_moving_frames = GloveCursorBob.glove_period(_select_pairs)
	_bob_frame = 0
	_build_content()


func row() -> int:
	return _row


func part() -> int:
	return _part


## What the row READS as one string — for the transcript the driver prints, and the thing a
## real guard would assert on.
func row_text(i: int) -> String:
	var r: Dictionary = rows[i]
	var out := "%s %s / %s / %s" % [_part_text(r, Part.ENABLE), _part_text(r, Part.DO),
		_part_text(r, Part.TO), _part_text(r, Part.IF)]
	var extra := int(r.get("extra", 0))
	return out + (" +%d" % extra if extra > 0 else "")


# -----------------------------------------------------------------------------
# Glove (copied from GambitSurfaceMenu — a prototype does not refactor its subject).
# -----------------------------------------------------------------------------
func _mount_glove(cell: Rect2, palette: ImageTexture, shader_path: String, rung: int) -> Node3D:
	var holder := Node3D.new()
	_cursor_elem.add_child(holder)
	if _atlas.texture == null or cell.size == Vector2.ZERO:
		return holder
	var folded := shader_path == _SHADOW_SHADER and Fold.owns()
	var mat := _sprite_mat(cell, palette, shader_path, rung)
	if folded:
		mat.shader = _SHADOW_FOLD_SHADER
	var mi := _quad(cell.size)
	mi.material_override = mat
	mi.position += _window.z_for(rung)
	holder.add_child(mi)
	if folded:
		Fold.add(mi, mat, DepthMode.rung_z(rung))
	return holder


func cursor_display_pos() -> Vector2:
	var bob := GloveCursorBob.glove_offset_for_frame(
		_select_pairs if _moving_frames > 0 else _idle_pairs, _bob_frame)
	var origin_x: float = float(COL_X[_part]) - 12.0 if part_glove else CONTAINER.position.x
	var c := Rect2i(origin_x, CONTAINER.position.y + 8, CONTAINER.size.x, CONTAINER.size.y - 8)
	return StartActionMenu.cursor_display_pos_in(c, _row, bob)


func _place_cursor() -> void:
	if _lit_holder == null or not is_instance_valid(_lit_holder):
		return
	var lit := cursor_display_pos()
	_lit_holder.position = _cursor_elem.rel_world(lit.x, lit.y)
	if _shadow_holder != null and is_instance_valid(_shadow_holder):
		var shadow := lit + StartActionMenu.CURSOR_SHADOW_DELTA
		_shadow_holder.position = _cursor_elem.rel_world(shadow.x, shadow.y)


func _process(delta: float) -> void:
	_bob_accum += delta
	while _bob_accum >= _BOB_TICK:
		_bob_accum -= _BOB_TICK
		_bob_frame += 1
		if _moving_frames > 0:
			_moving_frames -= 1
			if _moving_frames == 0:
				_bob_frame = 0
	_place_cursor()


func _sprite_mat(cell: Rect2, palette: ImageTexture, shader_path: String, rung: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.set_shader_parameter("index_atlas", _atlas.texture)
	mat.set_shader_parameter("atlas_size", Vector2(_atlas.texture.get_width(), _atlas.texture.get_height()))
	mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y))
	mat.set_shader_parameter("palette_tex", palette)
	mat.set_shader_parameter("brightness", 1.0)
	mat.render_priority = rung
	return mat


func _quad(size_px: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size_px * _window.ppu()
	mi.mesh = q
	mi.position = Vector3(q.size.x * 0.5, -q.size.y * 0.5, 0.0)
	return mi


static func _palette_from_colors(colors: Array) -> ImageTexture:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		img.set_pixel(i, 0, colors[i] if i < colors.size() else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
