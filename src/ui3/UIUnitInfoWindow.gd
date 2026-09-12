@tool
class_name UIUnitInfoWindow
extends UIWindow
## Faithful FFT bottom-left VITALS READOUT (#91 / #88 assembly).
##
## A screen-space `ui3` panel (NOT a billboard) reproducing FFT PSX's always-on
## combat vitals gauge: portrait + `Lv.`/`Exp.` + `Hp`/`Mp`/`Ct` labels + three
## gradient bars + `cur/max` digits, laid out at the **ROM-exact** relative
## offsets recovered by live dynamic analysis (fork PCSX-Redux, sstate1 — see
## docs/battle-hud-faithful-spec.md §8 "LOCATED via dynamic analysis"). The draw
## fn is `0x801352BC`; the per-element screen XYs below were read straight out of
## the live display struct at `0x8017225C`.
##
## Faithfulness rule (project-wide): FFT's *visuals/layout*, OUR *data*. The
## panel never reads FFT's BattleUnitData — it takes our UnitStats view through
## [UnitInfoPresenter] (`set_unit_view`). Each bar is two layers in concert, just
## like the ROM (`draw_vitals_bars @0x801352BC`): a **38x6** RANGETILE swatch
## TRACK (textured SPRT, per-stat CLUT, dim — the bar's frame/empty casing,
## `vitals_sprite.gdshader`) with a **32x3** gouraud-gradient FILL inset inside
## it — fill width = `frac * 32` px, dark->bright ramp (the ROM's own POLY_G4;
## endpoint colours read live from the built primitives, NOT a static table),
## `vitals_bar.gdshader`. The fill shrinks as the stat drops, revealing the dim
## track behind. ALL TEXT (labels + cur/max digits) is
## white-on-dark — one uniform fill+outline look, exactly as the live PCSX
## framebuffer shows (the per-index menu CLUT is NOT what the panel uses), rendered
## by `vitals_sprite.gdshader`. Left panel = dark contrast band, NOT a tan frame
## (spec §8 "Live RE pass 2" dec-1).
##
## Vault: [[Learn Job Picker]]

## ADR-0211 dec. 4 — the host autoload `PSXDisplay` is not nameable from inside an
## addon (every stranger rig declares an empty `[autoload]` block), so UI PAR is
## read and subscribed through the platform port. #1263 / ADR-0308.
const DisplayPort = ExMateriaPlatform.DisplayPort

# `TunePort` is INHERITED from UI3Element (via UIWindow -> UIComponent) -- a const is a member, so redeclaring it
# here is a parse error, not a duplicate. #1268 / ADR-0306.

const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")
const NumberFont = preload("res://src/ui3/elements/NumberFont.gd")
const EquipDeltaPalette = preload("res://src/ui3/detail/EquipDeltaPalette.gd")
const UnitInfoPresenter = preload("res://src/ui3/UnitInfoPresenter.gd")
const UIPortrait = preload("res://src/ui3/elements/UIPortrait.gd")
const UIPortraitFrame = preload("res://src/ui3/assemblies/UIPortraitFrame.gd")
const SHADER_PATH := "res://src/ui3/shaders/vitals_sprite.gdshader"
const BAR_SHADER_PATH := "res://src/ui3/shaders/vitals_bar.gdshader"

# UI pixel-aspect ratio (ADR-0036). Sourced from the PROJECT-WIDE `PSXDisplay.live_ui_par`
# (default 1.0 = square) at build time, exactly like every other ui3 element (UIFrame / UIText /
# UIChar / UIPortrait). It is NOT a per-panel constant: hardcoding 1.25 here while the rest of ui3
# is square stretches only this panel's labels/bars/digits, so they drift out of alignment with the
# (square) portrait card — the source of the "labels graze the portrait / digits graze the bar tips"
# overlaps. PAR is a UNIFORM display-space stretch: at any PAR the *relative* layout (and thus whether
# elements overlap) is identical, so alignment is done at PAR=1 and PAR only scales the whole panel.
var _ui_par: float = 1.0

## World units per source texel (the ui3 "pixels_per_unit"). The on-screen
## height of one source pixel is `pixels_per_unit * viewport_h / camera.size`;
## glyphs are intra-mesh pixel-even ONLY when that product is an integer (see
## ADR-0051). Exposed (live-tunable in the F3 vitals panel) so the integer
## value can be dialled in by eye. 0.04 = the ui3 default (a NON-integer 2.74
## px/texel at the combat camera — the source of the uneven-serif look).
@export var pixels_per_unit: float = 0.04:
	set(v):
		if pixels_per_unit == v: return
		pixels_per_unit = v
		_mark_layout_dirty()

## Right-hand variant: move ONLY the portrait card to the band's RIGHT edge (and
## flip its art), then slide the text block (labels / bars / digits) sideways by
## [member mirror_text_shift] to fill the space the portrait left — the numbers
## and bars keep their normal left-to-right order and orientation, they just
## translate together. Used by the right-hand team in [UIVitalsRoster] so
## portraits hug the right border like the flipped enemy [UIRosterBar]. The
## un-mirrored (false) layout is the ROM-faithful bottom-left panel; this is OUR
## right-side variant (FFT has no native mirrored vitals panel — see class docs).
@export var mirrored: bool = false:
	set(v):
		if mirrored == v: return
		mirrored = v
		_mark_layout_dirty()

## How far to slide the text block (labels / bars / digits — NOT the band or
## portrait) when [member mirrored]. Negative = left, into the vacated portrait
## zone. Default -29 aligns the text's left edge with the portrait's old left
## edge; set 0 to leave the text exactly where the left-hand layout puts it.
@export var mirror_text_shift: float = -29.0:
	set(v):
		if mirror_text_shift == v: return
		mirror_text_shift = v
		_mark_layout_dirty()

# --- ROM-exact layout (FFT px, relative to panel origin = screen (140,170)) ----
# Captured from the live display struct (sstate1, acting-unit slot). The default
# per-element TOP-LEFT positions live in the @export tunables below so each piece
# can be nudged live via [VitalsLayoutDebugPanel]; sizes come from RANGETILE.
const ORIGIN_SCREEN := Vector2(140, 170)   # FFT screen XY of panel origin

# --- Intra-panel depth ladder (ADR-0077: order by real camera-Z, NOT render_priority) --------------
# The panel's sub-elements overlap (bar FILL over bar TRACK; portrait over the band), so they need a
# genuine near→far ordering. Per ADR-0077 that ordering is DEPTH, not a painter's `render_priority`
# ladder: each element carries a small local +Z (the ui3 convention is +Z = toward the viewer, exactly
# as UIPortraitFrame/UIMenuFrame/DialogueBox place their frame at -0.1 "behind" and content at +0.1
# "in front"). Because the sprites are opaque and depth-write, the fill lands in front of the track by
# real depth (no coincident-Z z-fight, no render_priority), and the whole panel — lifted onto the
# formation depth ladder — occludes the folded band beneath it through the shared depth buffer.
const Z_BAND := -0.15        # the panel's own contrast band (battle HUD only; behind everything)
const Z_PORTRAIT := 0.0      # UIPortraitFrame node origin (its frame sits at -0.1 internally, > Z_BAND)
const Z_BAR_TRACK := 0.0     # the dim swatch casing
const Z_BAR_FILL := 0.05     # the gouraud fill, in FRONT of its track
const Z_TEXT := 0.1          # labels / digits / Lv / Exp — frontmost, ui3 "content" plane

# Menu/text CLUT 0x7cbc (VRAM 960,498) — read live. The LABEL cells (168,32…) are
# authored body=index4(dark) + highlight=index1(cream); through this CLUT they
# render as cream-on-dark embossed letters (matches the live PCSX framebuffer).
const MENU_CLUT: PackedColorArray = [
	Color8(0, 0, 0, 0), Color8(239, 239, 231), Color8(156, 156, 148),
	Color8(82, 82, 74), Color8(33, 24, 16), Color8(90, 82, 74),
	Color8(123, 123, 115), Color8(140, 132, 115), Color8(165, 156, 132),
	Color8(156, 148, 123), Color8(115, 107, 90), Color8(140, 123, 107),
	Color8(173, 165, 140), Color8(33, 24, 16), Color8(41, 41, 41), Color8(16, 16, 16),
]

# cur/max DIGITS are FFT's HUD number font, extracted statically from EVENT/
# FRAME.BIN into FRAMEFONT.tga via tools/parse_frame_font.py and loaded through
# [NumberFont]. The HP/MP/CT readout draws cur, the bridging `/`, and max ALL in
# the SAME small size (NOT big cur + small max) — max just staggers a baseline
# lower-right; advance is overlap-1 (5px). Disasm: HUD builder FUN_801363dc
# @0x801363dc -> small digit routine FUN_8014aec0 @0x8014aec0 (U = digit*6+0x78).
# Stored as 4bpp index = grayscale, so the glyphs render through MENU_CLUT exactly
# like the labels. See docs/frame-bin-number-font.md.

# --- tunables (defaults dialed to the live PCSX left-panel capture) ------------
@export var band_color: Color = Color(0.0, 0.0, 0.0, 0.55):
	set(v):
		if band_color == v: return
		band_color = v
		_mark_layout_dirty()

## Draw this panel's own flat contrast band. The battle HUD keeps it (true); the
## FORMATION screen turns it OFF and draws the faithful full-width SUBTRACTIVE
## GOURAUD band at scene level instead (FormationScene._build_band_backdrop,
## FUN_80112c88 iter2 — §14.6.6), since that band is 256px-wide and screen-anchored
## (y169-236), not this panel-local 124px quad. See FORMATION_SCREEN.md §14.6.6.
@export var show_band: bool = true:
	set(v):
		if show_band == v: return
		show_band = v
		_mark_layout_dirty()

## Brightness multiplier for the bar gradient (fed to vitals_bar.gdshader). The
## gradient endpoint colours are now the ROM's true framebuffer colours, so the
## faithful default is 1.0 (was 2.2 when bars sampled an authored-dark swatch).
@export var bar_brightness: float = 1.0:
	set(v):
		if bar_brightness == v: return
		bar_brightness = v
		_mark_layout_dirty()

## Size multiplier for all numbers (cur, max, Lv, Exp). 1.0 = FRAMEFONT native
## HUD size (the faithful default); scales glyph size + advance together.
@export var num_scale: float = 1.0:
	set(v):
		if num_scale == v: return
		num_scale = v
		_mark_layout_dirty()

## cur (numerator) right-aligns here; the "/" begins here (panel-relative px).
## Measured from the composed block: cur right-edge ≈ rel x93.
@export var num_divider_x: float = 93.0:
	set(v):
		if num_divider_x == v: return
		num_divider_x = v
		_mark_layout_dirty()

## Top y of the cur (numerator) digit CELLS per stat row (panel-relative px),
## bar-aligned. Cur now uses the SMALL cell (glyph sits 1px below cell top, vs
## 4px for the old big cell), so these are +3 from the old big-cell values.
@export var num_row_y: PackedFloat32Array = PackedFloat32Array([19, 30, 40.5]):
	set(v):
		num_row_y = v
		_mark_layout_dirty()

## "/" offset from (divider_x, cur top): the slash bridges cur→max, set lower.
@export var slash_offset: Vector2 = Vector2(0, 2):
	set(v):
		if slash_offset == v: return
		slash_offset = v
		_mark_layout_dirty()

## max (denominator) offset from (divider_x, cur top): right of the slash, down a
## row — measured from the composed block (~+5x, +4y).
@export var max_offset: Vector2 = Vector2(5, 4):
	set(v):
		if max_offset == v: return
		max_offset = v
		_mark_layout_dirty()

## Portrait size multiplier (1.0 = [UIPortrait] native 40x48). The real unit
## portrait is rendered by [UIPortraitFrame] from the inspected unit's sprite id;
## when no sprite id is present the frame's background shows through.
@export var portrait_scale: float = 1.0:
	set(v):
		if portrait_scale == v: return
		portrait_scale = v
		_mark_layout_dirty()

## Draw the 9-slice [UIFrame] (border + background) around the portrait.
@export var show_portrait_frame: bool = true:
	set(v):
		if show_portrait_frame == v: return
		show_portrait_frame = v
		_mark_layout_dirty()

## Frame footprint (virtual px). Snug around the ~40x48 portrait — matches the
## proven [UIRosterBar] sizing for the same [UIPortraitFrame] + portrait.
@export var frame_size: Vector2 = Vector2(36, 52):
	set(v):
		if frame_size == v: return
		frame_size = v
		_mark_layout_dirty()

## Portrait top-left offset inside the frame (virtual px).
##
## Materialized from a pin (ADR-0068 dec. 8) and BY HAND, which is structural rather than an
## oversight: `_tb_vec2` forwards the slug as `"vitals.%s_x" % prop` and the default as
## `base.x`, so `tools/materialize_tunables.py` finds no literal slug at the bind line and
## skips with "call not found". Every `vitals.*` knob is baked here, at its `@export`
## initializer — the codemod cannot reach any of them.
@export var portrait_offset: Vector2 = Vector2(2, 2):
	set(v):
		if portrait_offset == v: return
		portrait_offset = v
		_mark_layout_dirty()

# --- per-piece TOP-LEFT positions (panel-relative px; defaults = ROM capture) --
# Exposed so each element can be nudged live in the debug panel. X is in pre-PAR px (the panel
# scales it by `_ui_par` = PSXDisplay.live_ui_par, 1.0 = square now, like every other ui3 piece).

## Portrait card (frame) top-left.
@export var portrait_pos: Vector2 = Vector2(2, 2):
	set(v):
		if portrait_pos == v: return
		portrait_pos = v
		_mark_layout_dirty()

## Dark contrast band size (virtual px).
@export var band_size: Vector2 = Vector2(124, 55.5):
	set(v):
		if band_size == v: return
		band_size = v
		_mark_layout_dirty()

## "Lv." label top-left.
@export var lv_pos: Vector2 = Vector2(63, 4):
	set(v):
		if lv_pos == v: return
		lv_pos = v
		_mark_layout_dirty()

## "Lv." number offset from [member lv_pos].
@export var lv_num_offset: Vector2 = Vector2(14.5, 0):
	set(v):
		if lv_num_offset == v: return
		lv_num_offset = v
		_mark_layout_dirty()

## "Exp." label top-left.
@export var exp_pos: Vector2 = Vector2(90, 4):
	set(v):
		if exp_pos == v: return
		exp_pos = v
		_mark_layout_dirty()

## "Exp." number offset from [member exp_pos].
@export var exp_num_offset: Vector2 = Vector2(18.5, 0):
	set(v):
		if exp_num_offset == v: return
		exp_num_offset = v
		_mark_layout_dirty()

## Hp / Mp / Ct label top-lefts (index 0/1/2).
@export var label_pos: Array[Vector2] = [
		Vector2(31, 19), Vector2(31, 30), Vector2(31, 41)]:
	set(v):
		label_pos = v
		_mark_layout_dirty()

## HP / MP / CT bar top-lefts (index 0/1/2).
@export var bar_pos: Array[Vector2] = [
		Vector2(43, 23), Vector2(43, 34), Vector2(43, 45)]:
	set(v):
		bar_pos = v
		_mark_layout_dirty()

## Full (100%) bar width and height in FFT px. ROM (FUN_801352bc): a bar is a
## gouraud quad of width `cur*32/max` and 3px tall — so a full bar is 32x3 and the
## fill width = frac * bar_full_width.
@export var bar_full_width: float = 32.0:
	set(v):
		if bar_full_width == v: return
		bar_full_width = v
		_mark_layout_dirty()

@export var bar_height: float = 3.0:
	set(v):
		if bar_height == v: return
		bar_height = v
		_mark_layout_dirty()

## The textured swatch TRACK size in FFT px. ROM (draw_vitals_bars @0x801352BC):
## the SPRT swatch is 38x6 — wider/taller than the 32x3 gouraud fill, so it shows
## as a casing/border around (and dim background behind) the fill.
@export var bar_track_size: Vector2 = Vector2(38, 6):
	set(v):
		if bar_track_size == v: return
		bar_track_size = v
		_mark_layout_dirty()

## The fill's inset from the swatch track's top-left, in FFT px. ROM: the 32x3
## fill sits at screen (187,194+) inside the 38x6 swatch at (183,193+) — ~4px
## left / 1px top. So track top-left = `bar_pos[stat] - bar_track_offset`.
@export var bar_track_offset: Vector2 = Vector2(4, 1):
	set(v):
		if bar_track_offset == v: return
		bar_track_offset = v
		_mark_layout_dirty()

## HP/MP/CT bar gradient endpoints — dark LEFT (x=0), bright RIGHT (x=1). These are
## the ROM's own POLY_G4 gouraud vertex colours, read live from the built draw
## primitives of draw_vitals_bars @0x801352BC (dynamic analysis, savestate9).
@export var bar_grad_left: Array[Color] = [
		Color8(72, 104, 120), Color8(128, 64, 56), Color8(80, 104, 64)]:
	set(v):
		bar_grad_left = v
		_mark_layout_dirty()

@export var bar_grad_right: Array[Color] = [
		Color8(168, 184, 112), Color8(224, 160, 80), Color8(176, 176, 64)]:
	set(v):
		bar_grad_right = v
		_mark_layout_dirty()

## Brightness of the empty-bar TRACK (the 38x6 RANGETILE swatch frame/background
## drawn behind + around the gradient fill). The swatch is authored dark, so this
## keeps the unfilled remainder a dim casing under the bright fill.
@export var bar_track_brightness: float = 1.0:
	set(v):
		if bar_track_brightness == v: return
		bar_track_brightness = v
		_mark_layout_dirty()

# --- internals -----------------------------------------------------------------
var _atlas: RangeTileAtlas
var _shader: Shader
var _bar_shader: Shader                      # vitals_bar.gdshader (gouraud gradient)
var _menu_pal: ImageTexture                 # labels + digits (0x7cbc)
var _bar_pal: Array[ImageTexture] = []     # per-stat CLUT for the swatch track
var _atlas_size := Vector2(256, 256)
var _font: NumberFont                        # FRAMEFONT.tga (big cur + small max)
var _digit_tex: Texture2D                    # _font.texture (FRAMEFONT.tga)
var _digit_size := Vector2(99, 22)           # FRAMEFONT atlas size

var _band: MeshInstance3D
var _portrait_frame: UIPortraitFrame
var _lv_label: MeshInstance3D
var _exp_label: MeshInstance3D
var _stat_labels: Array[MeshInstance3D] = []
var _bar_tracks: Array[MeshInstance3D] = []   # full-width swatch frame/background
var _bars: Array[MeshInstance3D] = []          # gouraud-gradient fill (on top)
var _num_pools: Array = []                 # per stat row: Array[MeshInstance3D]
var _hpmp_preview := false                 # §15.26: HP/MP numerator → "-" while the equip picker is up
# §15.26 numeric delta (EQUIP_STAT_PREVIEW.md §6): armor/accessory HP·MP deltas fill the numerators
# with a signed coloured value. {"hp": int, "mp": int}; a zero (or absent) field stays a dash.
var _hpmp_delta: Dictionary = {}
var _delta_pal_pos: ImageTexture           # blue numerator CLUT (positive; FRAME pal 15 +0xC)
var _delta_pal_neg: ImageTexture           # red numerator CLUT (negative; FRAME pal 15 +0x8)
var _lv_pool: Array = []
var _exp_pool: Array = []

var _current: Dictionary = {}


## The corrected OUT-OF-BATTLE menu layout (FORMATION_SCREEN.md §14.6): the Lv./Exp.
## label positions and the HP/MP/CT bar column, dialed so each bar sits snug BETWEEN
## its Hp/Mp/Ct label and its cur/max value (the faithful tiny overlap on each side).
## THIS is the placement every menu screen should use — call it right after `new()`.
##
## The `@export` DEFAULTS stay the BATTLE-oracle layout (bars x43, Lv x63/Exp x90),
## which the live battle HUD reads and whose intra-panel spacing genuinely differs;
## menu screens (formation roster, the unit-detail/Status screen, …) route through
## here so they share ONE corrected placement instead of each re-deriving it. Band
## handling stays per-screen (formation uses a scene-level subtractive band and sets
## `show_band=false`; the Status screen keeps the panel's own band).
static func apply_menu_layout(w: UIUnitInfoWindow) -> void:
	# Lv./Exp.: the battle defaults carry the ABSOLUTE oracle x (63/90) in the
	# panel-RELATIVE field, so the origin double-adds and they land ~13px too far
	# right. Correct panel x = oracle_x − origin_x (§14.6: Lv x63, Exp x89 → 50/76).
	w.lv_pos = Vector2(50.0, 4.0)
	w.exp_pos = Vector2(76.0, 4.0)
	# HP/MP/CT bars: panel x47 (was x43) so each bar hugs the gap between its label
	# and its cur/max value (§14.6), keeping the per-row y and the digit column.
	var bp: Array[Vector2] = w.bar_pos.duplicate()
	for i in bp.size():
		bp[i] = Vector2(47.0, bp[i].y)
	w.bar_pos = bp


func _build_children() -> void:
	_atlas = RangeTileAtlas.new()
	_shader = load(SHADER_PATH)
	_bar_shader = load(BAR_SHADER_PATH)
	if _atlas.texture:
		_atlas_size = Vector2(_atlas.texture.get_width(), _atlas.texture.get_height())

	_menu_pal = _make_palette(MENU_CLUT)
	# §15.26 equip stat-DELTA numerator CLUTs (EQUIP_STAT_PREVIEW.md §6): the armor/accessory
	# HP·MP delta must render as the SAME digit as the plain numerator next to it — same border,
	# same shading — with only the bright body recoloured by sign. So we copy the numerator's OWN
	# CLUT (MENU_CLUT) and recolour ink indices 1·2 → cyan (positive, sampled 0x774C) / bright red
	# (negative). See EquipDeltaPalette (this replaced the old FRAME-pal-15 index-bias path, which
	# produced foreign greys and dropped the border).
	_delta_pal_pos = EquipDeltaPalette.texture(EquipDeltaPalette.recolour(MENU_CLUT, EquipDeltaPalette.VITALS_CYAN))
	_delta_pal_neg = EquipDeltaPalette.texture(EquipDeltaPalette.recolour(MENU_CLUT, EquipDeltaPalette.VITALS_RED))
	_bar_pal.clear()
	for i in _atlas.bar_stat_count():
		_bar_pal.append(_make_palette(_clut_to_packed(_atlas.bar_stat_colors(i))))

	# HUD number font (FRAMEFONT.tga + two-size cells + measured kerning).
	_font = NumberFont.new()
	if _font.texture:
		_digit_tex = _font.texture
		_digit_size = Vector2(_digit_tex.get_width(), _digit_tex.get_height())

	# Dark contrast band (NOT a frame). Plain transparent quad behind the panel. Ordered by real
	# camera-Z (Z_BAND, the backmost plane) — NOT render_priority (ADR-0077). Depth test stays ON so
	# it sorts behind the opaque panel content and, on the formation depth ladder, behind the world.
	_band = MeshInstance3D.new()
	_band.mesh = QuadMesh.new()
	# Screen-space ortho UI contrast band, ordered by real camera-Z (ADR-0077) — same opt-out as the RP_* ladder.
	# psx-ot-depth-exempt: not a battle-OT CUSTOM0 mesh, so it opts out of ADR-0009's CUSTOM0-depth rule.
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = band_color
	_band.material_override = bmat
	_band.set_meta("layer_z", Z_BAND)
	add_child(_band)

	# Portrait card via the shared [UIPortraitFrame] assembly: a 9-slice [UIFrame]
	# (border + background) behind a paletted [UIPortrait], driven from the
	# inspected unit's sprite id. Ordering is by real camera-Z (ADR-0077), NOT
	# render_priority: the assembly places its own frame at -0.1 (behind) and
	# portrait at 0 (in front) internally, and the whole card mounts at Z_PORTRAIT
	# (see _update_layout), which sits in front of Z_BAND. The frame is decorative
	# here — it must NOT eat unit-picking clicks.
	_portrait_frame = UIPortraitFrame.new()
	_portrait_frame.pixels_per_unit = pixels_per_unit
	add_child(_portrait_frame)
	var frame := _portrait_frame.get_frame()
	if frame:
		frame.absorb_clicks = false

	# Text labels (RANGETILE cells, white fill + outline).
	_lv_label = _make_sprite(Z_TEXT)
	_exp_label = _make_sprite(Z_TEXT)
	_stat_labels.clear()
	_bar_tracks.clear()
	_bars.clear()
	for i in 3:
		_stat_labels.append(_make_sprite(Z_TEXT))
		# Empty-bar TRACK (full-width RANGETILE swatch, Z_BAR_TRACK) behind the
		# gouraud-gradient FILL (Z_BAR_FILL, nearer) — they work in concert: the dim
		# track is the bar's frame/background, the gradient is the current fill. The
		# fill sits in front of the track by real depth, not render_priority.
		_bar_tracks.append(_make_sprite(Z_BAR_TRACK))
		_bars.append(_make_bar_sprite(Z_BAR_FILL))

	_num_pools = [[], [], []]
	_lv_pool = []
	_exp_pool = []

	if _current.is_empty():
		# Editor-preview sample so the panel isn't blank in the inspector.
		_current = UnitInfoPresenter.build({
			"name": "Ramza", "job": "Squire", "level": 99, "exp": 60,
			"current_hp": 999, "max_hp": 999, "current_mp": 799, "max_mp": 799,
			"ct": 100, "brave": 70, "faith": 55, "sprite_id": 0x01})


func _update_layout() -> void:
	if _band == null:
		return
	(_band.material_override as StandardMaterial3D).albedo_color = band_color
	_layout_quad(_band, 0, 0, band_size.x, band_size.y)
	_band.visible = show_band

	# Portrait card: frame top-left at the portrait slot, portrait inset inside it.
	if _portrait_frame:
		_portrait_frame.pixels_per_unit = pixels_per_unit
		_portrait_frame.show_frame = show_portrait_frame
		_portrait_frame.frame_size = frame_size
		_portrait_frame.portrait_offset = portrait_offset
		_portrait_frame.portrait_scale = portrait_scale
		# Mirror: portrait card to the right edge of the band + flip the art.
		_portrait_frame.portrait_flipped = mirrored
		var pf_x := portrait_pos.x
		if mirrored:
			pf_x = band_size.x - portrait_pos.x - frame_size.x
		# Mount the portrait card on the intra-panel depth ladder at Z_PORTRAIT (in front of Z_BAND);
		# the assembly places its own frame/portrait/stats around that origin (-0.1 / 0 / +0.1).
		var pf_pos := _px_to_world(pf_x, portrait_pos.y)
		pf_pos.z = Z_PORTRAIT
		_portrait_frame.position = pf_pos

	# Labels (drawn at native cell size).
	_place_label(_lv_label, "Lv.", lv_pos)
	_place_label(_exp_label, "Exp.", exp_pos)
	var names := ["Hp", "Mp", "Ct"]
	for i in 3:
		_place_label(_stat_labels[i], names[i], label_pos[i] if i < label_pos.size() else Vector2.ZERO)

	_apply_view()


func _ready() -> void:
	# Take the project-wide UI PAR (like every other ui3 element) instead of a hardcoded 1.25, and
	# rebuild on live scrubs. @tool-guarded: the PSXDisplay autoload isn't present in the editor.
	if not Engine.is_editor_hint():
		if not is_equal_approx(_ui_par, DisplayPort.live_ui_par()):
			_ui_par = DisplayPort.live_ui_par()
			_mark_layout_dirty()
		DisplayPort.connect_live_ui_par_changed(_on_live_ui_par_changed)
	_bind_tunables()


func _on_live_ui_par_changed(value: float) -> void:
	if is_equal_approx(_ui_par, value):
		return
	_ui_par = value
	_mark_layout_dirty()


## Bind the vitals-window layout knobs to their `vitals.*` Tune slugs (ADR-0068). This
## window OWNS its layout, so a committed override coalesces into the property at boot AND
## a scrub re-drives the on-screen window (each @export setter re-applies), in any scene —
## the VitalsLayoutDebugPanel is just a view (decision 12). Vector2 props split into _x/_y
## slugs; the per-stat arrays (label_pos / bar_pos / num_row_y) split into per-index slugs.
## @tool-guarded: Tune.gd is not @tool, so it is a placeholder that can't be called in the
## editor — skip binding there (the .tscn @export values drive the editor preview).
func _bind_tunables() -> void:
	if Engine.is_editor_hint():
		return
	for p in ["pixels_per_unit", "portrait_scale", "bar_brightness", "bar_track_brightness",
			"num_scale", "num_divider_x"]:
		_tb_scalar(p)
	_tb_scalar("show_portrait_frame")
	for p in ["portrait_pos", "frame_size", "portrait_offset", "band_size", "lv_pos",
			"lv_num_offset", "exp_pos", "exp_num_offset", "bar_track_size", "bar_track_offset",
			"slash_offset", "max_offset"]:
		_tb_vec2(p)
	_tb_vec2_array("label_pos", 3)
	_tb_vec2_array("bar_pos", 3)
	_tb_float_array("num_row_y", 3)


## Bind a scalar (float/bool) @export prop to `vitals.<prop>`; the apply writes the
## property, whose setter re-applies the view.
func _tb_scalar(prop: String) -> void:
	TunePort.bind_update(self, "vitals." + prop, get(prop), func(v: Variant) -> void: set(prop, v))


## Bind a Vector2 @export prop to `vitals.<prop>_x` / `_y` float slugs.
func _tb_vec2(prop: String) -> void:
	var base: Vector2 = get(prop)
	TunePort.bind_update(self, "vitals.%s_x" % prop, base.x, func(v: float) -> void:
		set(prop, Vector2(v, (get(prop) as Vector2).y)))
	TunePort.bind_update(self, "vitals.%s_y" % prop, base.y, func(v: float) -> void:
		set(prop, Vector2((get(prop) as Vector2).x, v)))


## Bind an Array[Vector2] @export prop element-wise: `vitals.<prop>_<i>_x` / `_y`. The
## apply duplicates the typed array, rewrites the element, and reassigns so the property
## setter fires (assigning to an element in place would not).
func _tb_vec2_array(prop: String, n: int) -> void:
	for i in n:
		var idx := i
		var el: Vector2 = get(prop)[idx]
		TunePort.bind_update(self, "vitals.%s_%d_x" % [prop, idx], el.x, func(v: float) -> void:
			var arr: Array = get(prop).duplicate()
			arr[idx] = Vector2(v, (arr[idx] as Vector2).y)
			set(prop, arr))
		TunePort.bind_update(self, "vitals.%s_%d_y" % [prop, idx], el.y, func(v: float) -> void:
			var arr: Array = get(prop).duplicate()
			arr[idx] = Vector2((arr[idx] as Vector2).x, v)
			set(prop, arr))


## Bind a PackedFloat32Array @export prop element-wise: `vitals.<prop>_<i>`.
func _tb_float_array(prop: String, n: int) -> void:
	for i in n:
		var idx := i
		var el: float = get(prop)[idx]
		TunePort.bind_update(self, "vitals.%s_%d" % [prop, idx], el, func(v: float) -> void:
			var arr: PackedFloat32Array = get(prop).duplicate()
			arr[idx] = v
			set(prop, arr))


## Public — show the live view of a unit (a UnitInfoPresenter input dict).
func set_unit_view(view: Dictionary) -> void:
	_ensure_built()
	_current = UnitInfoPresenter.build(view)
	_apply_view()


## §15.26 equip-picker preview: blank the HP/MP numerators to "-" (bars/"/"/denominator stay). The
## default (false) leaves every roster/combat/detail vitals render byte-identical. Re-applies the view.
func set_hpmp_preview(on: bool) -> void:
	# Plain (dash) preview drops any NUMERIC delta — the delta path is exclusively set_hpmp_delta,
	# so a later dash-mode request never renders a stale +N/-N. Short-circuit only a true no-op.
	var had_delta := not _hpmp_delta.is_empty()
	if _hpmp_preview == on and not had_delta:
		return
	_hpmp_preview = on
	_hpmp_delta = {}
	if not _current.is_empty():
		_apply_view()


func hpmp_preview() -> bool:
	return _hpmp_preview


## Guard seam: the HP/MP numerators currently APPLIED to the gauges (from the last set_unit_view, i.e.
## `_current`). -1 when unbuilt. Render-readback for the equip/remove vitals-refresh guards: does the
## vitals cluster reflect the live unit after a commit, or revert to the stale build-time view?
func applied_hp_mp() -> Dictionary:
	return {
		"hp": int(_current.get("hp", {}).get("cur", -1)) if not _current.is_empty() else -1,
		"mp": int(_current.get("mp", {}).get("cur", -1)) if not _current.is_empty() else -1,
		# The DENOMINATORS travel with them, because on a battlefield the two halves have different
		# owners and can be wrong independently: current HP is the [UnitStats]' and a hit moves it,
		# max HP is the progression's and EQUIPMENT moves it. A guard that could only read `hp` had
		# to accept a frozen denominator as green (FormationMapHostTest's battlefield equip arm).
		"hp_max": int(_current.get("hp", {}).get("max", -1)) if not _current.is_empty() else -1,
		"mp_max": int(_current.get("mp", {}).get("max", -1)) if not _current.is_empty() else -1,
	}


## §15.26 numeric preview (EQUIP_STAT_PREVIEW.md §6): enter HP/MP preview AND fill each numerator
## with its signed delta — "+5"/"-5" coloured by sign, or a dash when the field is 0. `hp`/`mp` are
## the EquipStatDelta.compute hp/mp deltas (armor/accessory equip). Re-applies the view.
func set_hpmp_delta(hp: int, mp: int) -> void:
	_hpmp_delta = {"hp": hp, "mp": mp}
	_hpmp_preview = true
	if not _current.is_empty():
		_apply_view()


## §15.26 guard: how many numerator glyphs in vitals row `i` (0=hp,1=mp,2=ct) render through the
## blue (positive) vs red (negative) delta CLUT. Zero for a plain dash / real-value render.
func number_glyph_palette_counts(i: int) -> Dictionary:
	var pos := 0
	var neg := 0
	if i >= 0 and i < _num_pools.size():
		for mi in _num_pools[i]:
			if mi != null and is_instance_valid(mi) and mi.visible:
				var p = (mi.material_override as ShaderMaterial).get_shader_parameter("palette_tex")
				if p == _delta_pal_pos:
					pos += 1
				elif p == _delta_pal_neg:
					neg += 1
	return {"pos": pos, "neg": neg}


## Visible digit/slash glyph quads in vitals number row `i` (0=hp, 1=mp, 2=ct) — a render-state
## query for the §15.26 §D field-width guard. The HP/MP fraction is a fixed 3-wide field, so even
## the picker preview ("-/044") renders 5 cells (dash + slash + 3 denominator), never 4.
func number_glyph_count(i: int) -> int:
	if i < 0 or i >= _num_pools.size():
		return 0
	var n := 0
	for mi in _num_pools[i]:
		if mi != null and is_instance_valid(mi) and mi.visible:
			n += 1
	return n


## Display-px LEFT edges of the visible glyph quads in vitals number row `i` (0=hp, 1=mp,
## 2=ct), in draw order (cur digits, '/', max digits) — a render-state query for the §15.26
## dash-cell guard (the blanked numerator must land in the ROM's middle digit cell).
func number_glyph_xs(i: int) -> Array:
	if i < 0 or i >= _num_pools.size():
		return []
	var out: Array = []
	for mi in _num_pools[i]:
		if mi != null and is_instance_valid(mi) and mi.visible:
			var w: float = (mi.mesh as QuadMesh).size.x
			out.append((mi.position.x - w * 0.5) / (_ui_par * pixels_per_unit))
	return out


func _apply_view() -> void:
	if _band == null or _current.is_empty():
		return
	var m := _current

	# Real portrait: front the flat sprite sheet with the unit's OWNED template
	# portrait when it resolved to a folder (#205); else the flat sprite id
	# (-1 → frame bg only). The blank-folder fallback stays load-bearing.
	if _portrait_frame:
		_portrait_frame.display_from_template(
			String(m.get("template_folder", "")), int(m.get("sprite_id", -1)))

	var rows := ["hp", "mp", "ct"]
	for i in 3:
		var row: Dictionary = m[rows[i]]
		_layout_bar(i, float(row["frac"]))
		var y: float = num_row_y[i] if i < num_row_y.size() else 20.0
		# §15.26 equip-picker preview: the HP/MP NUMERATOR blanks to "-" (the "/" + max denominator
		# stay). CT (no numerator) is untouched. Off by default; the whole roster/combat path is unchanged.
		if _hpmp_preview and (rows[i] == "hp" or rows[i] == "mp"):
			# §15.26 §D / defect #9: the fraction is a fixed-width 3-digit right-aligned FIELD, so
			# the denominator zero-pads to 3 (`44` -> `044`) while the numerator stays right-aligned
			# to the divider — never a 2-digit denominator. NUMERIC delta (EQUIP_STAT_PREVIEW.md §6):
			# a nonzero hp/mp delta renders the SIGNED value ("+5"/"-5") coloured by sign; a zero (or
			# no-delta) field stays the single dash. Only the numerator is sign-coloured.
			var dv := int(_hpmp_delta.get(rows[i], 0))
			var num_text := "-"
			var num_pal: ImageTexture = null   # null → normal menu ink (the dash)
			if not _hpmp_delta.is_empty() and dv != 0:
				num_text = ("+" + str(dv)) if dv > 0 else str(dv)
				num_pal = _delta_pal_pos if dv > 0 else _delta_pal_neg
			var placements := _font.place_pair_text(num_text, str(int(row["max"])), num_divider_x, y,
					slash_offset, max_offset, num_scale, 3)
			# The numerator is the first `num_text.length()` placements (place_number emits one per
			# char); the '/' and denominator follow. Colour only the numerator run.
			_render_placements(_num_pools[i], placements, num_pal, num_text.length())
		else:
			_render_number_pair(_num_pools[i], row, num_divider_x, y)

	# Lv. / Exp. numbers (small `max`-size font, 2-digit zero-padded like the oracle
	# `Lv.99 Exp.05`; baseline-aligned with their labels).
	_render_number_solo(_lv_pool, str(int(m.get("level", 1))),
			lv_pos.x + lv_num_offset.x, lv_pos.y + lv_num_offset.y, 2)
	_render_number_solo(_exp_pool, str(int(m.get("exp", 0))),
			exp_pos.x + exp_num_offset.x, exp_pos.y + exp_num_offset.y, 2)


# --- rendering helpers ---------------------------------------------------------

func _make_palette(colors: PackedColorArray) -> ImageTexture:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		img.set_pixel(i, 0, colors[i] if i < colors.size() else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _clut_to_packed(cols: Array) -> PackedColorArray:
	var out := PackedColorArray()
	for c in cols:
		out.append(c)
	return out


## Make an index/CLUT sprite quad, ordered by real camera-Z: it carries `layer_z` (its local +Z on the
## intra-panel depth ladder), applied in [method _layout_quad]. NO render_priority (ADR-0077).
func _make_sprite(layer_z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("index_atlas", _atlas.texture)
	mat.set_shader_parameter("atlas_size", _atlas_size)
	mi.material_override = mat
	mi.set_meta("layer_z", layer_z)
	add_child(mi)
	return mi


## A bar sprite: a QuadMesh driven by the gouraud-gradient material
## ([constant BAR_SHADER_PATH]) instead of the index/CLUT sprite shader. Ordered by `layer_z`.
func _make_bar_sprite(layer_z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = _bar_shader
	mi.material_override = mat
	mi.set_meta("layer_z", layer_z)
	add_child(mi)
	return mi


## Draw a `cell` of an index atlas through a 16-colour CLUT, top-left at (x,y) px.
## `tex`/`tex_size` default to the RANGETILE atlas; digits pass FRAMEFONT.
func _config_clut(mi: MeshInstance3D, cell: Rect2, pal: ImageTexture,
		brightness: float, x: float, y: float, scale: float,
		tex: Texture2D = null, tex_size: Vector2 = Vector2.ZERO) -> void:
	var mat := mi.material_override as ShaderMaterial
	mat.set_shader_parameter("mode", 0)
	mat.set_shader_parameter("index_atlas", tex if tex else _atlas.texture)
	mat.set_shader_parameter("atlas_size", tex_size if tex_size != Vector2.ZERO else _atlas_size)
	mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y,
			cell.size.x, cell.size.y))
	mat.set_shader_parameter("palette_tex", pal)
	mat.set_shader_parameter("brightness", brightness)
	_layout_quad(mi, x, y, cell.size.x * scale, cell.size.y * scale)
	mi.visible = true


func _place_label(mi: MeshInstance3D, name: String, pos: Vector2) -> void:
	if not _atlas.has_label(name):
		mi.visible = false
		return
	_config_clut(mi, _atlas.label_rect(name), _menu_pal, 1.0, pos.x, pos.y, 1.0)


## Draw stat `stat` filled to `frac` as two layers that work in concert, exactly
## as `draw_vitals_bars @0x801352BC` does (textured SPRT swatch + inset POLY_G4):
##   1. TRACK — the 38x6 RANGETILE swatch (per-stat CLUT), dim: the bar's
##      frame/background/casing. Drawn at `bar_pos - bar_track_offset` so the
##      32x3 fill is INSET inside it (the ROM's ~4px L / 1px T border), and the
##      unfilled remainder reads as an empty bar with a real casing.
##   2. FILL — the gouraud-gradient quad, width = `frac * bar_full_width` (32px
##      full, 3px tall), dark->bright ramp, drawn on top inside the track.
## The fill SHRINKS as the stat drops (right edge slides left), revealing the dim
## track behind. At frac 0 only the empty track shows.
func _layout_bar(stat: int, frac: float) -> void:
	var bp: Vector2 = bar_pos[stat] if stat < bar_pos.size() else Vector2.ZERO

	# 1. Swatch track (38x6 casing/background), inset so the fill sits inside it.
	var track := _bar_tracks[stat]
	var sw := _atlas.bar_swatch_rect()
	var pal: ImageTexture = _bar_pal[stat] if stat < _bar_pal.size() else _menu_pal
	var tmat := track.material_override as ShaderMaterial
	tmat.set_shader_parameter("index_atlas", _atlas.texture)
	tmat.set_shader_parameter("atlas_size", _atlas_size)
	tmat.set_shader_parameter("cell", Vector4(sw.position.x, sw.position.y, sw.size.x, sw.size.y))
	tmat.set_shader_parameter("palette_tex", pal)
	tmat.set_shader_parameter("brightness", bar_track_brightness)
	_layout_quad(track, bp.x - bar_track_offset.x, bp.y - bar_track_offset.y,
			bar_track_size.x, bar_track_size.y)
	track.visible = true

	# 2. Gouraud fill, masked pixel-for-pixel to the swatch INTERIOR (index 3) so it
	#    fits the slanted parallelogram exactly — angled ends and all. Drawn over the
	#    same 38x6 rect as the track (so the shader samples the swatch per-pixel);
	#    `fill_frac` selects how much of the interior is painted, the rest revealing
	#    the dim track behind. At frac 0 the shader discards everything.
	var fill := _bars[stat]
	var fmat := fill.material_override as ShaderMaterial
	fmat.set_shader_parameter("index_atlas", _atlas.texture)
	fmat.set_shader_parameter("atlas_size", _atlas_size)
	fmat.set_shader_parameter("cell", Vector4(sw.position.x, sw.position.y, sw.size.x, sw.size.y))
	var cl: Color = bar_grad_left[stat] if stat < bar_grad_left.size() else Color.WHITE
	var cr: Color = bar_grad_right[stat] if stat < bar_grad_right.size() else Color.WHITE
	fmat.set_shader_parameter("color_left", Vector3(cl.r, cl.g, cl.b))
	fmat.set_shader_parameter("color_right", Vector3(cr.r, cr.g, cr.b))
	fmat.set_shader_parameter("brightness", bar_brightness)
	fmat.set_shader_parameter("fill_frac", clampf(frac, 0.0, 1.0))
	_layout_quad(fill, bp.x - bar_track_offset.x, bp.y - bar_track_offset.y,
			bar_track_size.x, bar_track_size.y)
	fill.visible = true


## Render the composed "cur/max" block exactly as FFT does it: `cur` right-aligned at
## divider_x, the bridging slash, then `max` staggered lower-right — via [NumberFont].
## Numeric rows zero-pad to 3 digits (`044/044` — the oracle field width); an out-of-battle
## CT row (`row.dashes`) draws the dash pair `---/---` instead.
func _render_number_pair(pool: Array, row: Dictionary, divider_x: float, y: float) -> void:
	var placements: Array
	if row.get("dashes", false):
		placements = _font.place_pair_text("---", "---", divider_x, y,
				slash_offset, max_offset, num_scale)
	else:
		placements = _font.place_pair(int(row["cur"]), int(row["max"]), divider_x, y,
				slash_offset, max_offset, num_scale, 3)
	_render_placements(pool, placements)


## Render a single left-aligned number (Lv./Exp.) in the small (`max`) size, zero-padded
## to `pad_width` digits (2 for the oracle `Lv.99`/`Exp.05`).
func _render_number_solo(pool: Array, text: String, x: float, y: float,
		pad_width: int = 0) -> void:
	_render_placements(pool, _font.place_number(
			text, x, y, NumberFont.SMALL, false, num_scale, pad_width))


## Draw each NumberFont glyph placement into a pool slot, then hide the leftovers.
## `head_pal` (optional): a CLUT to render the FIRST `head_len` glyphs through instead of the
## menu CLUT — the §15.26 numeric-delta path colours the numerator run (blue/red) while the
## '/' + denominator keep the normal menu ink. Default (null) = every glyph in the menu CLUT.
func _render_placements(pool: Array, placements: Array, head_pal: ImageTexture = null,
		head_len: int = 0) -> void:
	# Mirror is a rigid sideways slide applied in _layout_quad, so digit order and
	# kerning are preserved here with no special handling.
	var slot := 0
	for g in placements:
		var mi := _ensure_slot(pool, slot)
		var pal: ImageTexture = head_pal if (head_pal != null and slot < head_len) else _menu_pal
		_config_clut(mi, g["cell"], pal, 1.0, g["pos"].x, g["pos"].y,
				num_scale, _digit_tex, _digit_size)
		slot += 1
	_hide_slots_from(pool, slot)


func _ensure_slot(pool: Array, i: int) -> MeshInstance3D:
	while pool.size() <= i:
		pool.append(_make_sprite(Z_TEXT))
	return pool[i]


func _hide_slots_from(pool: Array, first: int) -> void:
	for i in range(first, pool.size()):
		pool[i].visible = false


# --- px -> ui3 world (top-left origin) -----------------------------------------

func _px_to_world(px_x: float, px_y: float) -> Vector3:
	return Vector3(px_x * _ui_par * pixels_per_unit, -px_y * pixels_per_unit, 0.0)


## Size a QuadMesh to `w_px x h_px` and anchor its TOP-LEFT at (ax, ay) px.
func _layout_quad(mi: MeshInstance3D, ax: float, ay: float, w_px: float, h_px: float) -> void:
	if mi == null:
		return
	var w := w_px * _ui_par * pixels_per_unit
	var h := h_px * pixels_per_unit
	# Mirror: slide the text block sideways (keeps reading order + orientation).
	# The band stays full-width; the portrait is placed separately in _update_layout.
	var lx := ax
	if mirrored and mi != _band:
		lx = ax + mirror_text_shift
	# Real camera-Z from the element's intra-panel ladder rung (ADR-0077): ordering is depth, not
	# render_priority. Coincident-Z overlaps (bar fill over track) are separated here, so opaque
	# depth-write composites them correctly with no z-fight.
	var lz: float = mi.get_meta("layer_z", 0.0)
	(mi.mesh as QuadMesh).size = Vector2(w, h)
	mi.position = Vector3(lx * _ui_par * pixels_per_unit + w / 2.0, -(ay * pixels_per_unit) - h / 2.0, lz)
