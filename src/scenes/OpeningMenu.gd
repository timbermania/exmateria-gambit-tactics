@tool
class_name OpeningMenu
extends Node3D
## Title-menu overlay for OpeningScene.
##
## Layers the four menu items (NEW GAME / CONTINUE / TUTORIAL / SOUND) plus
## the © 1997/1998 SQUARE copyright onto the OPNBK1 parchment.
##
## Each line is a single 3D quad sampling OPNTEX1 through a 16-entry CLUT
## (the same indexed-bitmap-through-CLUT pattern the vitals panel uses for
## RANGETILE — `vitals_sprite.gdshader` / [UIUnitInfoWindow]). The acting
## item samples CLUT 8 (cream-white body); the others sample CLUT 7 (dim
## navy/slate). Both feed the same opaque draw via `opntex_glyph.gdshader`.
##
## CLUT 7 vs CLUT 8 were confirmed by live RAM extraction on 2026-06-19,
## from OPEN.BIN's menu draw at PC 0x800690E8..0x80069128:
##   if (item.field_20 == 0 || (cell_ctrl & (1<<27)))
##       clut = (cell_ctrl >> 12) & 0xF;   // → 7 for every title item
##   else
##       clut = item.field_20 - 1;          // → 8 when field_20 = 0x09
## See `tools/parse_opntex.py` docstring for the full derivation.
##
## Up/Down cycles the selection and fires SfxRouter "ui.cursor_move" (FFT
## system bank slot 0x03 — confirmed by PCSX-Redux dynamic analysis: a BP
## on `play_sound` @ 0x80012520 captures `a1=0x03` every press; caller is
## the SCUS wrapper `FUN_80043FF8` @ 0x80043FF8 which jumps into the menu
## state machine living in OPEN.BIN, which fans out to OPNTEX1's two
## AddPrim calls per item via GetClut).
##
## Sizing matches OpeningScene: pixels_per_unit=0.04, no PAR (this scene's
## bg is 320-mode native — see OpeningScene.gd docstring for the why).

const ATLAS_PATH := "res://assets/ui/opntex/opntex1_index.png"
const CLUT_SELECTED_PATH := "res://assets/ui/opntex/opntex1_clut_p08.png"
const CLUT_UNSELECTED_PATH := "res://assets/ui/opntex/opntex1_clut_p09.png"
const CELLS_PATH := "res://assets/ui/opntex/opntex1_cells.json"
const SHADER_PATH := "res://src/ui3/shaders/opntex_glyph.gdshader"
const ATLAS_SIZE := Vector2(256.0, 256.0)

const PIXELS_PER_UNIT := 0.04

const MENU_ITEMS := [
	{"id": "new_game", "cell_name": "new_game"},
	{"id": "continue", "cell_name": "continue"},
	{"id": "tutorial", "cell_name": "tutorial"},
	{"id": "sound",    "cell_name": "sound"},
]

# Layout in virtual pixels relative to scene origin (origin = screen
# center, +Y up). Slot-9 PSX framebuffer puts NEW GAME at y=151..159 in a
# 320x240 frame (origin y=120), so the top of NEW GAME sits 31 px BELOW
# center. Subsequent items step by 12 px. Copyright is at y=210..219 →
# 90..99 px below center. The X anchor (137 px in 320-mode) is 23 px LEFT
# of center.
const FIRST_ITEM_TOP_PX := 31.0
const ITEM_STRIDE_PX := 12.0
const ITEM_X_PX := -23.0
const COPYRIGHT_X_PX := -60.0
const COPYRIGHT_TOP_PX := 90.0

signal selection_changed(index: int)
signal item_confirmed(item_id: String)

var _selected_index: int = 0
var _sprites: Array[MeshInstance3D] = []     # one MeshInstance3D per menu item
var _copyright_sprite: MeshInstance3D

# Shared resources (loaded once)
var _shader: Shader
var _atlas: Texture2D
var _clut_selected: Texture2D
var _clut_unselected: Texture2D
var _cells: Dictionary = {}


func _ready() -> void:
	_load_resources()
	_build_sprites()
	_apply_selection()


func _load_resources() -> void:
	_shader = load(SHADER_PATH)
	_atlas = load(ATLAS_PATH)
	_clut_selected = load(CLUT_SELECTED_PATH)
	_clut_unselected = load(CLUT_UNSELECTED_PATH)
	var f := FileAccess.open(CELLS_PATH, FileAccess.READ)
	if f:
		var json := JSON.new()
		if json.parse(f.get_as_text()) == OK:
			_cells = json.data
		f.close()


func _build_sprites() -> void:
	for c in get_children():
		c.queue_free()
	_sprites.clear()

	for i in range(MENU_ITEMS.size()):
		var item: Dictionary = MENU_ITEMS[i]
		var cell_name: String = item.cell_name
		var sprite := _make_glyph_sprite(cell_name)
		var cell: Dictionary = _cells.get(cell_name, {})
		var w_px := float(cell.get("w", 54))
		var h_px := float(cell.get("h", 10))
		var top_px := FIRST_ITEM_TOP_PX + i * ITEM_STRIDE_PX
		# Center of the glyph quad (Sprite3D.centered semantics): top-left
		# anchor at (ITEM_X_PX, -top_px) → centre at (ITEM_X_PX + w/2, -top_px - h/2).
		var cx := (ITEM_X_PX + w_px * 0.5) * PIXELS_PER_UNIT
		var cy := -(top_px + h_px * 0.5) * PIXELS_PER_UNIT
		sprite.position = Vector3(cx, cy, 0.1)
		add_child(sprite)
		_sprites.append(sprite)

	_copyright_sprite = _make_glyph_sprite("copyright")
	var cc: Dictionary = _cells.get("copyright", {})
	var cw := float(cc.get("w", 118))
	var ch := float(cc.get("h", 10))
	var ccx := (COPYRIGHT_X_PX + cw * 0.5) * PIXELS_PER_UNIT
	var ccy := -(COPYRIGHT_TOP_PX + ch * 0.5) * PIXELS_PER_UNIT
	_copyright_sprite.position = Vector3(ccx, ccy, 0.1)
	add_child(_copyright_sprite)


func _make_glyph_sprite(cell_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Glyph_%s" % cell_name
	var cell: Dictionary = _cells.get(cell_name, {})
	var w_px := float(cell.get("w", 54))
	var h_px := float(cell.get("h", 10))
	var quad := QuadMesh.new()
	quad.size = Vector2(w_px * PIXELS_PER_UNIT, h_px * PIXELS_PER_UNIT)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("index_atlas", _atlas)
	mat.set_shader_parameter("atlas_size", ATLAS_SIZE)
	mat.set_shader_parameter("cell", Vector4(
		float(cell.get("x", 0)),
		float(cell.get("y", 0)),
		w_px,
		h_px,
	))
	# Default to unselected — _apply_selection switches the acting item to CLUT 8.
	mat.set_shader_parameter("palette_tex", _clut_unselected)
	mi.material_override = mat
	return mi


func _apply_selection() -> void:
	for i in range(_sprites.size()):
		var mi := _sprites[i]
		var mat := mi.material_override as ShaderMaterial
		if mat == null:
			continue
		var pal: Texture2D = _clut_selected if i == _selected_index else _clut_unselected
		mat.set_shader_parameter("palette_tex", pal)
	# Copyright always uses the unselected (semi-trans navy) CLUT.
	if _copyright_sprite:
		var cmat := _copyright_sprite.material_override as ShaderMaterial
		if cmat:
			cmat.set_shader_parameter("palette_tex", _clut_unselected)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var dir := 0
	if event.keycode == KEY_DOWN or event.keycode == KEY_S:
		dir = 1
	elif event.keycode == KEY_UP or event.keycode == KEY_W:
		dir = -1
	elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
		var item: Dictionary = MENU_ITEMS[_selected_index]
		item_confirmed.emit(item.id)
		return
	else:
		return

	var prev := _selected_index
	_selected_index = (_selected_index + dir) % MENU_ITEMS.size()
	if _selected_index < 0:
		_selected_index += MENU_ITEMS.size()
	if _selected_index != prev:
		_apply_selection()
		SfxRouter.play_cue("ui.cursor_move")
		selection_changed.emit(_selected_index)
