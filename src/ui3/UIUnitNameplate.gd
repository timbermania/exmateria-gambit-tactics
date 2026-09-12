class_name UIUnitNameplate
extends UI3Element
## The unit-info "nameplate" panel (#176, FORMATION_SCREEN.md §14.6): the tan 9-slice
## window carrying a blue orb bullet + unit number + name / job (proportional
## FONT.BIN) + a zodiac glyph (RANGETILE §14.3) + Brave/Faith label+value. It is the
## SAME panel on the formation roster (bottom-right) and the unit-detail/Status screen
## (top-right, beside the vitals panel) — so it lives here as ONE reusable widget
## instead of inline in a screen. Faithfulness rule: FFT visuals + layout, OUR data
## (name/job/brave/faith/zodiac off the Character).
##
## Every piece is OPAQUE + depth-writing on the ADR-0077 ladder (frame behind < bullet
## < text in front) so it occludes a folded subtractive band it sits over. The screen
## supplies the layout (origin + per-element positions, absolute 256×240 px); the
## widget owns the rendering (assets, shaders, the orb fold). Call `set_view()` after
## setting the layout vars — it (re)builds the glyph tree.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase


# 🔴 NO `DepthMode` / `Fold` ALIAS HERE, AND THAT IS DELIBERATE. This script
# EXTENDS `UI3Element.gd`, which declares both, and GDScript refuses a
# member that already exists in the parent — a parse error that takes this
# whole file out. An alias is a per-CLASS declaration, not a per-file one;
# the inherited constants are what the use sites below read (ADR-0212 dec. 1).

const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")
const UIUnitInfoWindow = preload("res://src/ui3/UIUnitInfoWindow.gd")

const PIXELS_PER_UNIT := 0.04
const _ASSET_DIR := "res://assets/ui/formation/"
const ORB_PX := Vector2(12.0, 12.0)

const _FONT_OPAQUE_SHADER := "res://src/ui3/shaders/formation_font_opaque.gdshader"
const _TEXT_OPAQUE_SHADER := "res://src/ui3/shaders/formation_text_opaque.gdshader"
const _VITALS_SPRITE_SHADER := "res://src/ui3/shaders/vitals_sprite.gdshader"
const _ORB_OPAQUE_SHADER := preload("res://src/ui3/shaders/formation_orb_opaque.gdshader")
const _ORB_SHADER := preload("res://src/ui3/shaders/formation_orb.gdshader")                 # additive rim (in-scene)
const _ORB_RIM_FOLD_SHADER := preload("res://src/ui3/shaders/formation_orb_rim_fold.gdshader")

# Ink ramps (§14.6): the info-panel number/letter ink is the DARK ramp (dark-on-tan),
# NOT the cream battle-HUD MENU CLUT — the glyph's bright index maps to the darkest ink.
const INFO_INK_LIGHT := Color(0.502, 0.471, 0.408)   # (128,120,104) glyph edge/AA
const INFO_INK_MID := Color(0.314, 0.314, 0.251)     # (80,80,64)
const INFO_INK_DARK := Color(0.188, 0.157, 0.125)    # (48,40,32) glyph body
const ZODIAC_BROWN_LIGHT := Color(0.502, 0.471, 0.408)  # (128,120,104) zodiac highlight
const ZODIAC_BROWN_MID := Color(0.439, 0.408, 0.345)    # (112,104,88) zodiac glyph

const FONT_INK_TOP_PAD := 2.0    # FONT.BIN ink starts ~2px below its cell top
const DIGIT_INK_TOP_PAD := 2.0   # HUD digit font same pad

# Depth-ladder rungs (ADR-0077): frame behind < bullet/zodiac < text in front.
const RP_FRAME := 12
const RP_BULLET := 13
const RP_TEXT := 14

# --- layout (absolute 256x240 px; the SCREEN sets these before set_view) ------
# Defaults = the formation roster's oracle-measured §14.6 placement (bottom-right).
# `rung_offset` lifts every piece (frame/bullet/text + the folded orb rim) on the ADR-0077
# ladder — 0 docked on the roster; a positive lift when the Status screen overlays the roster
# so the nameplate sorts nearer than the formation grid. Set BEFORE set_view (baked at build).
var rung_offset := 0
var pixels_per_unit := PIXELS_PER_UNIT
var origin_px := Vector2(134.0, 176.0)       # tan frame top-left
var frame_size_px := Vector2(114.0, 54.0)    # frame w×h (outer)
var bullet_px := Vector2(136.0, 179.0)       # orb bullet top-left (12×12)
var number_px := Vector2(147.0, 183.0)       # unit-number ("01")
var name_px := Vector2(158.0, 183.0)         # name ("Ramza")
var job_px := Vector2(158.0, 199.0)          # job ("Squire")
var zodiac_px := Vector2(139.0, 205.0)       # zodiac glyph top-left (~20×20)
var brave_label_px := Vector2(162.0, 216.0)
var brave_value_px := Vector2(188.0, 216.0)
var faith_label_px := Vector2(205.0, 216.0)
var faith_value_px := Vector2(227.0, 216.0)

var _root: Node3D
var _rt_atlas: RangeTileAtlas
var _info_font: UIFont
var _digit_font: NumberFont
var _digit_pal: ImageTexture        # shared MENU CLUT (the _mount_glyph fallback)
var _info_digit_pal: ImageTexture   # dark digit CLUT (dark-on-tan)
var _info_zodiac_pal: ImageTexture  # zodiac-glyph CLUT (dark ink on tan)


## The ONE menu nameplate layout — the oracle-measured §14.6 element arrangement,
## expressed as fixed offsets from the frame's top-left `origin`. Both the formation
## roster (docked, origin (134,176)) and the Status/detail screen (top, origin
## (130,32)) place the SAME panel, so the offsets live here once instead of being
## re-typed per screen. Call before `set_view()`. (Verified byte-identical to the
## formation `info_*` @exports and the detail `_build_nameplate` offsets, 2026-08-05.)
static func apply_menu_layout(np: UIUnitNameplate, origin: Vector2) -> void:
	np.origin_px = origin
	np.frame_size_px = Vector2(114.0, 54.0)
	np.bullet_px = origin + Vector2(2.0, 3.0)
	np.number_px = origin + Vector2(13.0, 7.0)
	np.name_px = origin + Vector2(24.0, 7.0)
	np.job_px = origin + Vector2(24.0, 23.0)
	np.zodiac_px = origin + Vector2(5.0, 29.0)
	np.brave_label_px = origin + Vector2(28.0, 40.0)
	np.brave_value_px = origin + Vector2(54.0, 40.0)
	np.faith_label_px = origin + Vector2(71.0, 40.0)
	np.faith_value_px = origin + Vector2(93.0, 40.0)


## Map a roster [Character] + its 1-based slot to the nameplate view dict. OUR data
## (faithfulness rule); the job name resolves through the shared JobDatabase.
static func view_from_character(character, number: int) -> Dictionary:
	var prog = character.progression
	var job: Dictionary = JobDatabase.get_job(prog.current_job_id)
	return {
		"number": number,
		"name": character.display_name,
		"job": job.get("name", prog.current_job_id),
		"brave": prog.brave,
		"faith": prog.faith,
		"zodiac": prog.zodiac,
	}


## (Re)build the panel for `view` ({number,name,job,brave,faith,zodiac}). Safe to
## call repeatedly (e.g. on selection change) — the previous glyph tree is freed.
func set_view(view: Dictionary) -> void:
	if _root != null and is_instance_valid(_root):
		# DETACH before freeing. `queue_free` is DEFERRED — the old root stays a child for
		# the rest of the frame — so binding twice in one frame renders BOTH nameplates,
		# and anything walking this subtree sees a doubled mesh tree. `remove_child` is
		# immediate, so a re-bind is idempotent WITHIN the frame. Measured against
		# FormationUnitClusterElementTest's golden: 63 meshes with one bind, 69 with three,
		# 63 again with this line. The vitals half of the same cluster never had the bug —
		# `UIUnitInfoWindow.set_unit_view` REUSES its tree (`_ensure_built` + `_apply_view`)
		# instead of tearing it down.
		remove_child(_root)
		_root.queue_free()
	_ensure_assets()
	_root = Node3D.new()
	_root.name = "Nameplate"
	add_child(_root)

	# (A) Tan 9-slice window — opaque (ADR-0077) so it occludes a folded band. PAR=1.
	var frame := UIFrame.new()
	frame.opaque = true
	_root.add_child(frame)                       # _ready builds mesh + material
	frame.pixels_per_unit = pixels_per_unit
	frame.pixel_aspect_ratio = 1.0
	frame.frame_size = frame_size_px             # set LAST → _update_mesh with all params
	frame.position = _at(origin_px, RP_FRAME)

	# (B) blue orb bullet, (C) unit number, (D) name+job, (E) zodiac, (F) Brave/Faith.
	#
	# The number is SKIPPED at 0, and the bullet above is why that is a whole feature rather
	# than a hole: 0 means "this unit has no owned slot" (an ENTD enemy, an ENTD-blue guest),
	# the bullet is its own mount, so the plate keeps its bullet and simply prints no digits.
	# The alternative is what shipped — [FormationMapHost.slot_number_for] answered a literal
	# 1 for every unresolvable unit, putting Ramza's number on the plate over every enemy.
	# A pad-2 zero would render `00`, which is the same wrong answer in a different font.
	_mount_bullet(bullet_px)
	var number := int(view.get("number", 0))
	if number > 0:
		_mount_number(str(number), 2, number_px)
	_mount_word(str(view.get("name", "")), name_px)
	_mount_word(str(view.get("job", "")), job_px)
	_mount_zodiac(int(view.get("zodiac", 0)), zodiac_px)
	# Brave/Faith are WHOLE-WORD baked RANGETILE textures (smaller than FONT.BIN), value
	# = the HUD digit font — mounted exactly like the Hp/Mp/Ct word labels.
	_mount_label_texture("Brave", brave_label_px)
	_mount_number(str(int(view.get("brave", 0))), 0, brave_value_px)
	_mount_label_texture("Faith", faith_label_px)
	_mount_number(str(int(view.get("faith", 0))), 0, faith_value_px)


# -----------------------------------------------------------------------------
# Rendering (owned by the widget; identical to the formation info-panel path).
# -----------------------------------------------------------------------------
func _ensure_assets() -> void:
	if _info_font != null:
		return
	_rt_atlas = RangeTileAtlas.new()
	_info_font = UIFont.new()
	_digit_font = NumberFont.new()
	# Shared MENU CLUT as a 16x1 row (the _mount_glyph fallback palette).
	var mimg := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	var clut: PackedColorArray = UIUnitInfoWindow.MENU_CLUT
	for i in 16:
		mimg.set_pixel(i, 0, clut[i] if i < clut.size() else Color(0, 0, 0, 0))
	_digit_pal = ImageTexture.create_from_image(mimg)
	# Dark digit CLUT (dark-on-tan): glyph strokes 1/2/3 → dark ink ramp; the near-black
	# cell fill (index 4) and everything else → TRANSPARENT so the tan shows through.
	var dimg := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		dimg.set_pixel(i, 0, Color(0, 0, 0, 0))
	dimg.set_pixel(1, 0, INFO_INK_DARK)
	dimg.set_pixel(2, 0, INFO_INK_MID)
	dimg.set_pixel(3, 0, INFO_INK_LIGHT)
	_info_digit_pal = ImageTexture.create_from_image(dimg)
	# Zodiac CLUT (§14.3): the cell has no transparent key — background dither (8/4/12)
	# → transparent, glyph strokes (3/6/7) → the faint mid-brown the oracle shows.
	var zimg := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		zimg.set_pixel(i, 0, Color(0, 0, 0, 0))
	zimg.set_pixel(3, 0, ZODIAC_BROWN_MID)
	zimg.set_pixel(6, 0, ZODIAC_BROWN_MID)
	zimg.set_pixel(7, 0, ZODIAC_BROWN_LIGHT)
	_info_zodiac_pal = ImageTexture.create_from_image(zimg)


## The blue orb bullet (§10): an opaque CORE (writes depth + seeds the fold scratch)
## plus an additive RIM halo that folds on the fork (the blue glow), static at full
## brightness (no pulse).
func _mount_bullet(pos_px: Vector2) -> void:
	var idx_tex := load(_ASSET_DIR + "ORB.tga")
	var pal_tex := load(_ASSET_DIR + "ORB.palette.tga")
	var folded := Fold.owns()
	var holder := Node3D.new()
	holder.position = _at(pos_px, RP_BULLET)
	_root.add_child(holder)
	var core_mi := _quad(ORB_PX)
	holder.add_child(core_mi)
	var core_mat := _orb_mat(_ORB_OPAQUE_SHADER, idx_tex, pal_tex, 1.0)
	if not folded:
		core_mat.render_priority = RP_BULLET
	core_mi.material_override = core_mat
	var rim_mi := _quad(ORB_PX)
	holder.add_child(rim_mi)
	var rim_mat := _orb_mat(Fold.shader(_ORB_RIM_FOLD_SHADER, _ORB_SHADER), idx_tex, pal_tex, 1.0)
	rim_mi.material_override = rim_mat
	if folded:
		Fold.add(rim_mi, rim_mat, DepthMode.rung_z(RP_BULLET + rung_offset))
	else:
		rim_mat.render_priority = RP_BULLET


## A HUD-digit number (FRAMEFONT), dark-on-tan, top-left at `pos_px`; `pad` zero-pads.
func _mount_number(text: String, pad: int, pos_px: Vector2) -> void:
	var placements := _digit_font.place_number(text, pos_px.x, pos_px.y - DIGIT_INK_TOP_PAD,
		NumberFont.SMALL, false, 1.0, pad)
	for g in placements:
		_mount_glyph(_digit_font.texture, g["cell"], g["pos"], RP_TEXT, _info_digit_pal)


## One word of proportional FONT.BIN text (name/job), opaque dark-on-tan; spaces use
## the ROM narrow advance so the layout doesn't over-gap.
func _mount_word(text: String, pos_px: Vector2) -> void:
	var font := _info_font
	var x := pos_px.x
	var y := pos_px.y - FONT_INK_TOP_PAD
	for ch in text:
		var idx := font.get_char_index(ch)
		var info := font.get_char_info(idx)
		var w := glyph_advance(font, ch)
		if ch != " ":
			var mat := ShaderMaterial.new()
			mat.shader = load(_FONT_OPAQUE_SHADER)
			mat.set_shader_parameter("font_atlas", font.atlas_texture)
			mat.set_shader_parameter("atlas_size", Vector2(font.atlas_width, font.atlas_height))
			mat.set_shader_parameter("char_region", Vector4(
				float(info.get("atlas_x", 0)), float(info.get("atlas_y", 0)),
				font.char_width, font.char_height))
			mat.set_shader_parameter("use_palette", true)
			mat.set_shader_parameter("palette_light", _ink_vec4(INFO_INK_DARK))
			mat.set_shader_parameter("palette_mid", _ink_vec4(INFO_INK_MID))
			mat.set_shader_parameter("palette_dark", _ink_vec4(INFO_INK_LIGHT))
			_mount_quad(Vector2(x, y), Vector2(font.char_width, font.char_height), mat, RP_TEXT)
		x += w


## A WHOLE-WORD baked RANGETILE label ("Brave"/"Faith"), dark-on-tan. No-op if absent.
func _mount_label_texture(label: String, pos_px: Vector2) -> void:
	if _rt_atlas == null or not _rt_atlas.has_label(label):
		return
	_mount_glyph(_rt_atlas.texture, _rt_atlas.label_rect(label), pos_px, RP_TEXT, _info_digit_pal)


## The zodiac sign glyph (RANGETILE §14.3, 0..12), dark ink on tan. No-op if absent.
func _mount_zodiac(sign: int, pos_px: Vector2) -> void:
	if _rt_atlas == null or not _rt_atlas.has_method("zodiac_rect"):
		return
	var cell: Rect2 = _rt_atlas.zodiac_rect(sign)
	if cell.size == Vector2.ZERO:
		return
	_mount_glyph(_rt_atlas.texture, cell, pos_px, RP_BULLET, _info_zodiac_pal)


# --- low-level helpers (mirrored from FormationScene) ------------------------

## Mount one index-atlas glyph cell (HUD digit / RANGETILE label / zodiac) opaque +
## depth-writing (ADR-0077) through the text shader, at `pos_px` on rung `rung`.
func _mount_glyph(tex: Texture2D, cell: Rect2, pos_px: Vector2, rung: int, palette: Texture2D) -> void:
	if tex == null or cell.size == Vector2.ZERO:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(_TEXT_OPAQUE_SHADER)
	mat.set_shader_parameter("mode", 0)
	mat.set_shader_parameter("index_atlas", tex)
	mat.set_shader_parameter("atlas_size", Vector2(tex.get_width(), tex.get_height()))
	mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y))
	mat.set_shader_parameter("palette_tex", palette if palette != null else _digit_pal)
	mat.set_shader_parameter("brightness", 1.0)
	_mount_quad(pos_px, cell.size, mat, rung)


func _mount_quad(offset_px: Vector2, size_px: Vector2, mat: ShaderMaterial, rung: int) -> MeshInstance3D:
	var holder := Node3D.new()
	holder.position = _at(offset_px, rung)
	_root.add_child(holder)
	var mi := _quad(size_px)
	mi.material_override = mat
	holder.add_child(mi)
	return mi


func _orb_mat(shader: Shader, idx_tex: Texture2D, pal_tex: Texture2D, level: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("index_tex", idx_tex)
	mat.set_shader_parameter("palette_tex", pal_tex)
	mat.set_shader_parameter("brightness", level)
	return mat


## A TOP-LEFT-anchored quad of `size_px` (holder position = the top-left corner).
func _quad(size_px: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size_px * pixels_per_unit
	mi.mesh = q
	mi.position = Vector3(q.size.x * 0.5, -q.size.y * 0.5, 0.0)
	return mi


## World position of a virtual-screen pixel + a depth-ladder rung Z (lifted by rung_offset
## when this nameplate is overlaid over another screen — ADR-0077 real-Z).
func _at(px: Vector2, rung: int) -> Vector3:
	return Vector3(px.x * pixels_per_unit, -px.y * pixels_per_unit, 0.0) + Vector3(0.0, 0.0, DepthMode.rung_z(rung + rung_offset))


## Pure x-advance (px) for one character under §14.6's proportional layout: a glyph
## advances by its FONT.BIN width; a SPACE uses the ROM narrow advance (4px).
static func glyph_advance(font: UIFont, ch: String) -> float:
	if ch == " ":
		return DialogueBox.SPACE_WIDTH_PX
	var info := font.get_char_info(font.get_char_index(ch))
	return float(info.get("width", font.char_width))


## Color → Vector4 (bypass Godot's auto sRGB→linear; the opaque font shader does the
## pow(2.2) itself, mirroring UIChar).
static func _ink_vec4(c: Color) -> Vector4:
	return Vector4(c.r, c.g, c.b, c.a)
