class_name AbilityPickerMenu
extends Node3D

## The formation ability-slot picker (the "Set" flow) — the ability sibling of
## [EquipPickerMenu]. Opens on ○ from the ability sub-screen, lists the candidate
## secondary-skillsets / Reaction / Support / Movement abilities as PLAIN TEXT
## rows (ABILITY_PICKER.md §5: rows are name-text only — NO per-row type glyph or
## icon, unlike the equip picker), and emits the picked row on confirm.
##
## Candidate rows are set EXTERNALLY (`entries`) before add_child — the picker
## renders them; it does not build the catalog (see AbilityLoadout.candidates()).
## Each entry is `{id, name}`.
##
## Navigation mirrors the equip picker exactly (the shared ROM list-menu model):
## wrap top/bottom, and a 5-row scroll window (row stride 16px) — see §3.
##
## CHROME (this file's second build pass): the picker mounts the SAME two chrome
## pieces the equip picker does, through the SAME index→CLUT sprite mechanism —
##   (1) a cream "Ability" TITLE tab, and
##   (2) the bobbing glove CURSOR on the highlighted row.
## Title-cell provenance: the port reuses the LEFT ability panel's baked RANGETILE
## "Ability" tab cell (`window_tab_rect("Ability")` = (0,32,26,10)) through the cream
## active-label CLUT 0x7CBC — the "exact same cell/UV/sample as the panel tab" the
## user asked for. This is a DELIBERATE deviation from the ROM picker title, which
## RE'd as a DISTINCT baked cell (POLY_FT4 uv(0,200), tpage 0x0b, CLUT 0x7FFC, 80×16;
## ABILITY_PICKER.md §5): that v=200 cell is not extracted into RANGETILE.json, and
## reusing the panel tab guarantees byte-identical sampling with the panel on screen.

const _SPRITE_SHADER := "res://src/ui3/shaders/vitals_sprite.gdshader"
const _SHADOW_SHADER := "res://src/ui3/shaders/menu_cursor_shadow.gdshader"
## The FOLD twin of the glove's subtractive layer. PSX subtracts in the 8-bit framebuffer —
## DISPLAY space — while Godot's main target is LINEAR, so the in-scene twin subtracts a
## display-magnitude constant from linear light and over-darkens as the backdrop brightens.
## The engine fold seeds a DISPLAY-space scratch from the opaque scene, runs the hardware sub
## there and resolves back through RGB555, which is the ROM's abr=2 exactly (ADR-0074).
## PRELOADED as a Shader, never named as a String: a load() of a mistyped path returns null,
## a null shader does not raise, and the fold "just stops, with no error" (ADR-0191 dec. 2).
const _SHADOW_FOLD_SHADER := preload("res://src/ui3/shaders/menu_cursor_shadow_fold.gdshader")
## Fold handles (ADR-0074/0191): `owns()` is the BUILD predicate, `add` the enrolment decorator,
## `DepthMode.rung_z` the painter's-rung → fold-order key.
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

## The ROM list window shows at most 5 rows (16px pitch) and scrolls (§3).
const VISIBLE_ROWS := 5

## The title tab cell (the LEFT ability panel's tab — user-directed, see class doc).
const HEADER_ABILITY_CELL := "Ability"

## The cursor + row region — anchored on the picker WINDOW's LEFT edge (x155, the
## window authored_home.x) so the glove pokes off the left of the frame like the
## equip picker (ROWS_CONTAINER x76). y138 mirrors the equip relationship (rows text
## top y150 = container.y + CURSOR_Y_OFFSET(10) + 2), so the glove rests on the row.
## Placeholder/oracle-derived — F3-dialable (the pixel-dialing pass is a known deferral).
const ROWS_CONTAINER := Rect2i(155, 138, 90, 80)

const RP_BASE := 40
const RP_FRAME := 46
const RP_ROW_TEXT := 49
const RP_HEADER := 50
const RP_CURSOR_SHADOW := 51
const RP_CURSOR_LIT := 52

const _BOB_TICK := 1.0 / 60.0

## Emitted on ○ — the host validates + commits the picked candidate to the slot.
signal chosen(row: int)
## Emitted whenever the highlight moves (host may refresh a preview).
signal selection_changed(row: int)
## Emitted on × — the host closes the picker.
signal cancelled
## Re-emitted once the box-close animation finishes.
signal closed

## Candidate rows `{id, name}`, set by the host before add_child.
var entries: Array = []

## Play the box-open on _ready (host may disable to boot settled).
@export var autoplay_open: bool = true
@export var fast: bool = false

var _atlas: RangeTileAtlas
var _menu_text: UIMenuText
var _window: UI3Element
var _rows_elem: UI3Element
var _header_elem: UI3Element   # the cream "Ability" title tab (field: title_label_x)
var _cursor_elem: UI3Element   # the glove cursor element (UNCLIPPED, rides the window)

var _row_text_mats: Array[ShaderMaterial] = []   # per-glyph name materials (guard)
var _header_mats: Array[ShaderMaterial] = []     # the baked "Ability" cell material (guard)
var _cursor_mats: Array[ShaderMaterial] = []     # glove lit+shadow (guard)
var _visible_names: Array[String] = []           # the names rendered this build (guard)
var _content_built := false

# Palettes (built once in _ready from the atlas CLUTs).
var _tab_pal: ImageTexture           # header-cell CLUT 0x7CBC (cream)
var _glove_lit_pal: ImageTexture     # glove lit CLUT 0x7d7c
var _glove_shadow_pal: ImageTexture  # glove shadow CLUT 0x7dbc

# Glove cursor holders + bob (§15.20 / ADR-0046).
var _lit_holder: Node3D
var _shadow_holder: Node3D
var _bob_frame: int = 0
var _bob_accum: float = 0.0
var _moving_frames: int = 0
var _idle_pairs: Array = []
var _select_pairs: Array = []

var _row := 0
var _scroll := 0


func _ready() -> void:
	_atlas = RangeTileAtlas.new()
	_menu_text = UIMenuText.new()
	_tab_pal = _palette_from_colors(_atlas.window_tab_colors())
	_glove_lit_pal = _palette_from_colors(_atlas.menu_glove_lit_colors())
	_glove_shadow_pal = _palette_from_colors(_atlas.menu_glove_shadow_colors())
	_idle_pairs = GloveCursorBob.load_glove_pairs("glove_idle")
	_select_pairs = GloveCursorBob.load_glove_pairs("glove_select")
	_build_window()
	_build_content()
	if autoplay_open:
		play_open()
	_place_cursor()


# -----------------------------------------------------------------------------
# Window + rows/header/cursor elements (mirrors the equip picker; ADR-0088
# movable-origin model). Placement is oracle-derived (the RIGHT "Ability" panel,
# §5) but F3-dialable — the guard checks the mechanism (right cell / cursor
# present / text-only rows), not pixels.
# -----------------------------------------------------------------------------
func _build_window() -> void:
	_window = UI3Element.new({
		"id": "abilipicker.window",
		"rect": Rect2(155.0, 137.0, 95.0, 101.0),
		"authored_home": Vector2(155, 135),
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.STRIPE,
		"frame_center_patch": Vector4(6, 7, 21, 17),
		"frame_rp": RP_FRAME,
		"clip": UI3Element.Clip.OWN_APERTURE,
		# ADR-0088 amendment §4 (mirrors EquipPickerMenu): the header cell (y132) pokes 5px
		# above the window rect top (y137), so pad the box the box-open plays over by 5px on
		# top — the cream "Ability" title rides the reveal instead of being scissored. The
		# `aperture_pad` knob is otherwise auto-provided at zero (docs/ui3-guide.md "Aperture
		# padding"); a non-zero default is a deliberate port-side affordance.
		"aperture_pad": Vector4(0, 5, 0, 0),
		"depth_rung": -6,
		# ADR-0097 §2: one cadence per VERB — the `fast` export escalates the OPEN only.
		"open_cadence": UI3BoxOpenBeat.Cadence.FAST if fast else UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
	})
	add_child(_window)
	_window.closed.connect(func() -> void: closed.emit())

	# The list ASSEMBLY: ONE element; rows are payload placed from rect.y + `pitch`.
	# Text-only — a single `name_x` column, no glyph/icon/count columns.
	_rows_elem = UI3Element.new({
		"id": "abilipicker.rows",
		"rect": Rect2(145.0, 150.0, 90.0, 48.0), "authored_home": Vector2(158.0, 150.0),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
		"pitch": 16.0,
		"name_x": 178.0,
	})
	_window.add_child(_rows_elem)

	# The cream "Ability" title tab element — one baked RANGETILE word cell (the
	# panel tab, see class doc). Its rect.y anchors the cell; title_label_x is the knob.
	_header_elem = UI3Element.new({
		"id": "abilipicker.header",
		"rect": Rect2(162, 132, 30, 12),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
		"title_label_x": 162.0,
	})
	_window.add_child(_header_elem)

	# The glove cursor element: Clip.UNCLIPPED is a DECLARED answer (the glove pokes
	# off the frame's LEFT edge, outside the box-open scissor, drawn on top — mirrors
	# the equip picker §15.20). Its rect rides the window at the authored home.
	_cursor_elem = UI3Element.new({
		"id": "abilipicker.cursor",
		"rect": Rect2(155, 135, 95, 101),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_cursor_elem.name = "PickerGloveCursor"
	_window.add_child(_cursor_elem)


## Build (or rebuild) the visible payload — title cell, one name text per visible
## row, and the glove. Text-only rows: nothing but FONT glyphs is mounted in the
## row region (the RE correction). Called once from _ready and again on scroll.
func _build_content() -> void:
	for e: UI3Element in [_rows_elem, _header_elem, _cursor_elem]:
		for c in e.get_children():
			c.free()   # synchronous (mirrors the equip picker's scrub rebuild)
	_row_text_mats.clear()
	_header_mats.clear()
	_cursor_mats.clear()
	_visible_names.clear()
	_lit_holder = null
	_shadow_holder = null

	_build_header()
	_build_rows()
	_build_cursor()
	_content_built = true


## Mount the cream "Ability" title tab — the SAME baked RANGETILE cell + CLUT the
## left panel uses (`window_tab_rect("Ability")` through `window_tab_colors()` 0x7CBC),
## via the shared index→CLUT sprite material. NOT FONT glyphs (the user's ask).
func _build_header() -> void:
	if not _atlas.has_window_tab(HEADER_ABILITY_CELL):
		return
	var y := _header_elem.authored_home().y
	var x := float(_header_elem.spec().get("title_label_x", 162.0))
	_mount_header_cell(_atlas.window_tab_rect(HEADER_ABILITY_CELL), x, y)


func _mount_header_cell(cell: Rect2, x: float, y: float) -> void:
	if _atlas.texture == null or cell.size == Vector2.ZERO:
		return
	var mat := _sprite_mat(cell, _tab_pal, _SPRITE_SHADER, RP_HEADER)
	_header_mats.append(mat)
	var holder := Node3D.new()
	_header_elem.add_child(holder)
	holder.position = _header_elem.rel_world(x, y) + _header_elem.z_for(RP_HEADER)
	var mi := _quad(cell.size)
	mi.material_override = mat
	holder.add_child(mi)


## One name text per visible row — text-only (the §5 RE correction: no glyph/icon).
func _build_rows() -> void:
	var s := _rows_elem
	var row0_y := s.authored_home().y
	var pitch := float(s.spec().get("pitch", 16.0))
	var name_x := float(s.spec().get("name_x", 178.0))
	for i in range(_scroll, mini(entries.size(), _scroll + VISIBLE_ROWS)):
		var e: Dictionary = entries[i]
		var nm := String(e.get("name", ""))
		var y := row0_y + (i - _scroll) * pitch
		_menu_text.mount(s, nm, s.rel_world(name_x, y) + s.z_for(RP_ROW_TEXT),
			RP_ROW_TEXT, s.ppu(), _row_text_mats)
		_visible_names.append(nm)


## Mount the glove PAYLOAD under the persistent cursor element (shadow under, lit over).
func _build_cursor() -> void:
	_shadow_holder = _mount_glove(_atlas.menu_glove_shadow_rect(), _glove_shadow_pal, _SHADOW_SHADER, RP_CURSOR_SHADOW)
	_lit_holder = _mount_glove(_atlas.menu_glove_lit_rect(), _glove_lit_pal, _SPRITE_SHADER, RP_CURSOR_LIT)
	_place_cursor()


func _mount_glove(cell: Rect2, palette: ImageTexture, shader_path: String, rung: int) -> Node3D:
	var holder := Node3D.new()
	_cursor_elem.add_child(holder)
	if _atlas.texture == null or cell.size == Vector2.ZERO:
		return holder
	# The SUBTRACTIVE layer routes to its fold twin when this build folds (see _SHADOW_FOLD_SHADER).
	# Occlusion still comes from the OPAQUE lit hand above: the engine fold tests against the SHARED
	# opaque scene depth (LOADed, not cleared) with GREATER_OR_EQUAL, and the fold twin writes the
	# same reversed-Z NDC — so the hand hides the covered part exactly as in-scene.
	var folded := shader_path == _SHADOW_SHADER and Fold.owns()
	var mat := _sprite_mat(cell, palette, shader_path, rung)
	if folded:
		mat.shader = _SHADOW_FOLD_SHADER   # preloaded Shader (ADR-0191 dec. 2)
	_cursor_mats.append(mat)
	var mi := _quad(cell.size)
	mi.material_override = mat
	mi.position += _window.z_for(rung)
	holder.add_child(mi)
	if folded:
		Fold.add(mi, mat, DepthMode.rung_z(rung))
	return holder


# -----------------------------------------------------------------------------
# Row model + navigation.
# -----------------------------------------------------------------------------
func selected_row() -> int:
	return _row


func row_count() -> int:
	return entries.size()


## First visible entry index — the ROM scroll (DAT_801cd54c). Only entries
## [scroll, scroll+VISIBLE_ROWS) render; the cursor stays inside that window.
func scroll() -> int:
	return _scroll


func move_down() -> void:
	if entries.is_empty():
		return
	_row = (_row + 1) % entries.size()
	_on_selection_moved()


func move_up() -> void:
	if entries.is_empty():
		return
	_row = (_row - 1 + entries.size()) % entries.size()
	_on_selection_moved()


func _on_selection_moved() -> void:
	_moving_frames = GloveCursorBob.glove_period(_select_pairs)
	_bob_frame = 0
	var new_scroll := _scroll
	if _row < _scroll:
		new_scroll = _row
	elif _row >= _scroll + VISIBLE_ROWS:
		new_scroll = _row - VISIBLE_ROWS + 1
	if new_scroll != _scroll:
		_scroll = new_scroll
		if _content_built:
			_build_content()   # re-mount the visible window (synchronous frees)
	_place_cursor()
	selection_changed.emit(_row)


func confirm() -> void:
	chosen.emit(_row)


func cancel() -> void:
	cancelled.emit()


## `cadence` is the one-invocation override (ADR-0097 §4) — pass a UI3BoxOpenBeat.Cadence to
## make THIS play snap or slow without changing what the element is authored to do.
func play_open(cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	if _cursor_elem != null and is_instance_valid(_cursor_elem):
		_cursor_elem.visible = true   # a replay restores the glove
	if _window != null and is_instance_valid(_window):
		_window.open(cadence)


func play_close(cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	if _cursor_elem != null and is_instance_valid(_cursor_elem):
		_cursor_elem.visible = false  # focus has already left
	if _window != null and is_instance_valid(_window):
		_window.close(cadence)


func window() -> UI3Element:
	return _window


# -----------------------------------------------------------------------------
# Glove cursor placement + bob (§15.20). Bob axis = X. Anchored on the frame's LEFT edge.
# -----------------------------------------------------------------------------
## The glove display top-left for `row` at settled bob 0 — pure so the guard asserts it.
static func cursor_anchor_for(row: int) -> Vector2:
	return StartActionMenu.cursor_display_pos_in(ROWS_CONTAINER, row, 0)


func cursor_bob_x() -> int:
	var pairs := _select_pairs if _moving_frames > 0 else _idle_pairs
	return GloveCursorBob.glove_offset_for_frame(pairs, _bob_frame)


func cursor_display_pos() -> Vector2:
	# The cursor rides the VISIBLE row index — scrolling slides the list under it.
	return StartActionMenu.cursor_display_pos_in(ROWS_CONTAINER, _row - _scroll, cursor_bob_x())


func _place_cursor() -> void:
	if _lit_holder == null or not is_instance_valid(_lit_holder):
		return
	var lit := cursor_display_pos()
	var shadow := lit + StartActionMenu.CURSOR_SHADOW_DELTA
	# Home-relative under the cursor element (whose home == the window's), so the
	# glove rides the movable window.
	_lit_holder.position = _cursor_elem.rel_world(lit.x, lit.y)
	if _shadow_holder != null and is_instance_valid(_shadow_holder):
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


# -----------------------------------------------------------------------------
# Sprite helpers (mirror the equip picker — the shared index→CLUT sprite mechanism).
# -----------------------------------------------------------------------------
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


# -----------------------------------------------------------------------------
# Guard seams.
# -----------------------------------------------------------------------------
## The per-glyph name-text materials mounted for the visible rows.
func row_text_materials() -> Array:
	return _row_text_mats


## The baked "Ability" title cell material — proves the title renders through the
## RANGETILE index→CLUT cream MECHANISM (the panel tab), not FONT glyphs.
func header_cell_materials() -> Array:
	return _header_mats


## The glove cursor materials (lit + shadow) — UNCLIPPED, on top. For the guard.
func cursor_materials() -> Array:
	return _cursor_mats


## The candidate names rendered in the current visible window (top → bottom).
func visible_row_names() -> Array:
	return _visible_names


## Per-row DECORATION materials (type glyph / icon). Always empty: the ability
## picker rows are text-only (ABILITY_PICKER.md §5). Exposed so the guard can
## assert the RE correction (the equip picker mounts these; this one must not).
func row_decoration_materials() -> Array:
	return []
