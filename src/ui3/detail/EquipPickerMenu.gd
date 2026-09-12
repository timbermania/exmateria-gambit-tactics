class_name EquipPickerMenu
extends Node3D
## The equipment PICKER item-list window (FORMATION_SCREEN.md §15.26, RE round 35) — the item-select
## list (Broad Sword / Mythril Knife / Dagger rows) opened by pressing ○ on a slot row of the
## Item→Equip screen (§15.25). Per round 35 this is WORLD window slot 0xf (builder
## `world_equip_picker_window 0x8011241C`, per-row column renderer `world_equip_row_renderer
## 0x80128CE0`) — a SEPARATE window from the stats/compare band (`0x80111EC4`, two panels; that is
## DetailScene's stats band, §15.26 C / DEFECT #8). The ○-open + commit dispatch is
## `world_equip_picker_statemachine 0x8011AF4C` (row Y = idx·16 + 144); commit = `world_equip_commit
## 0x80124428` (out of scope). It COMPOSES the RE'd primitives (§15.20 glove cursor + GloveCursorBob,
## BoxOpenAnimator center-out scissor, FONT text, the NumberFont digit strip) so nothing is re-derived.
##
## Per-row 5 columns (§15.26 table B), each a specific mechanism — NOT a look-alike:
##   (a) type/class glyph — a PER-TYPE 12×12 RANGETILE cell (WORLD.BIN LUT 0x8018D7FC via
##       atlas type_glyph_rect, keyed by the item class byte) through the idle dark CLUT
##       TYPE_GLYPH_CLUT (0x7c3c) — §15.28; NOT one fixed sword;
##   (b) item icon — ITEM.BIN via the `graphic` byte, `icon_uv_for(graphic)` (WORLD literal
##       0x800EA990), CLUT ITEM_ICON_CLUT (0x3fa8) by item type;
##   (c) name — FONT page;
##   (d,e) counts "NN/NN" — the FRAME.BIN BIG number strip for the digits (§15.27, U=0x78+8·d,
##       CLUT 0x7C3C) with the SMALL-set slash — NOT the generic font, NOT all-SMALL (round-35 misread);
##   (f) frame + "Eqp."/"ALL" header — CLUT-swap CREAM cells (0x7c7c family), NOT dark FONT.BIN text.
##
## Faithfulness: FFT layout, OUR data. The item ICON (b) RENDERS the real ITEM.BIN sprite (extracted by
## tools/extract_item_sprites.py → item_icons_index.tga + item_icons.json; index→CLUT at icon_uv_for).
## The header's "Eqp."/"ALL" are now BAKED RANGETILE word cells (window_tabs "Eqp" 28,32 + "ALL"
## 45,120) through the cream active-label CLUT 0x7CBC — the SAME sheet + mechanism as the §15.19
## window tabs. STILL DEFERRED behind the CORRECT mechanism (never faked): the class-glyph CELL (a,
## UV in SCUS, not in RANGETILE.json); the count VALUES (`+0x54` equip tables + `0x801208B8` owned +
## `0x80123764` team) + item NAME string (inventory not threaded). See §15.26 "Port status".
##
## Vault: [[Equip Sub Screen]]

const TunePort = ExMateriaPlatform.TunePort

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")
const UIMenuText = preload("res://src/ui3/UIMenuText.gd")
const BoxOpenAnimator = preload("res://src/ui3/detail/BoxOpenAnimator.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")
## Preloaded, not load()ed (was `load()` in _build_left_strip until ADR-0191 dec. 11): an
## untyped `load()` of a script defeats the parser, so a wrong-arity call on the shared band
## producer would be a RUNTIME error at one seldom-walked call site instead of a parse error —
## the same silent-failure shape dec. 2 refuses for shader paths, one level up.
const UIVitalsBandCls = preload("res://src/ui3/UIVitalsBand.gd")

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
# Item icons render through the SAME clip-aware index→CLUT shader as the rest of the body text, so the
# box-open aperture reveals them and index 0 keys transparent (§15.26 b).
const _ICON_SHADER := "res://src/ui3/shaders/formation_text_opaque.gdshader"
const _ITEM_ICON_INDEX_TEX := "res://assets/items/item_icons_index.tga"
const _ITEM_ICON_JSON := "res://assets/items/item_icons.json"

# --- geometry (§15.26, GREEN framebuffer sstate4) -----------------------------
## The 9-slice frame outer rect (display px). Framebuffer-authoritative (oracle fb4): the window TOP
## edge is at ~y135 (the cream/dark bevel above the brown header stripe) — the earlier y128 was a
## prim-scan over-read into the stats band above. The brown header stripe (top margin) then lands at
## y135..144 so the cream "Eqp."/"ALL" cells (y137) sit ON it, matching the oracle. Bottom kept ~232.
## Round 39 (oracle_diff measured, port_aligned vs fb4): the right dark bevel read x244 vs oracle x248
## and the bottom dark bevel y230 vs oracle y234 — both 4px short. Width 170→174 (right edge x246→250,
## bevel→x248) + height 97→101 (bottom y232→236, bevel→y234); left x76 + top y135 already match, so
## this is a pure grow of the right + bottom margins. ROWS_CONTAINER follows the window rect.
##
## Two-model split — now the WINDOW ELEMENT's own model (ADR-0088; docs/ui3-element-interfaces.md):
## the spec's `authored_home` is the FIXED anchor all content offsets are taken against (every
## column/row/header const below is an oracle-measured absolute display coord AT this home); the
## spec's `rect` is the LIVE window rect (auto-bound composite slug `equipicker.window.rect`).
## The element origin sits at the live position while `rel_world` subtracts the home — so a rect
## scrub translates the origin and the WHOLE window (chrome + strip + header + rows + cursor)
## rides it. A size scrub grows the chrome + box-open aperture; content does not reflow (dial the
## column knobs if the interior layout should follow). The glove cursor's fixed home is an
## AUTHORED literal on its own element spec (ADR-0088 Amendment 4 §2) — the ex-FRAME_HOME
## const, retired there so its one repeatedly-pixel-tuned home is a live-editable row.
## The cursor + row region — BELOW the header stripe, so the §15.20 formula
## cursor_display_pos_in(ROWS_CONTAINER, 0, 0) = (76−12, 138+10) = (64, 148). y 136→138
## re-measured 2026-08-11 vs the live picker quicksave (glove lit-body bright rows,
## stripe-anchored): the fb4-era 136 sat the glove 2px high in the window.
const ROWS_CONTAINER := Rect2i(76, 138, 170, 88)
## Type/class GLYPH (§15.26 a, corrected §15.28 round 47) — a PER-TYPE dark weapon-class marker, one
## per row, LEFT of the item icon. The ROM picks a 12×12 cell per item CLASS byte from the WORLD.BIN
## type→UV LUT at 0x8018D7FC (provider chain 0x80128CE0 → FUN_8011AA34 → FUN_80124FF4; W=H=0xC is the
## WORLD literal at 0x80125018); live prims: Broad Sword (type 3) uv(104,128), Mythril Knife/Dagger
## (type 1) uv(80,128), 12×12, screen x=80. Cells come from the atlas (`type_glyph_rect(wtype)`,
## parsed out of WORLD.BIN per ADR-0001) — the old fixed (64,0,16,13) sword-on-every-row is DEAD.
## The glyph COLUMN placement is a rows-element spec field (equipicker.rows.glyph_x/glyph_dy).
## §15.26 (f): the header is BAKED RANGETILE word cells through the cream active-label CLUT 0x7CBC —
## the SAME sheet + mechanism as the §15.19 Eqp/Ability/Menu window tabs — NOT FONT.BIN glyphs.
## "Eqp" reuses the precedent equipment-menu tab cell (window_tabs 28,32); "ALL" is the word-row
## cell the parser now exposes (window_tabs 45,120; the "Total Next ALL Check…" row, y120).
const HEADER_EQP_CELL := "Eqp"
const HEADER_ALL_CELL := "ALL"

## The ROM picker window's row capacity (round 49, ITEM_EQUIPMENT_DATA.md §7): 5 rows at
## 16px pitch, live-proven with 6 candidates (icon prims y147..211, the 6th reached by
## scrolling; scroll var DAT_801cd54c, total count DAT_801cd824).
const VISIBLE_ROWS := 5

# --- depth ladder (this menu stacks ABOVE the detail overlay AND the backgrounded list-menu) ---
# Mirrors StartActionMenu's two-channel model (render_priority for draw-order tiebreak; a small fold
# real-Z rung the fork turns into world-Z). The list-menu tops out at overlay 32 + rp 45 → rung 37;
# the picker uses a higher overlay so its whole band clears it, staying under the camera-clip (~52).
const RP_BASE := 40
const RP_FRAME := 46
# The subtractive LEFT column band sits BETWEEN the frame (it darkens the frame's tan interior) and
# the icons/text/cursor (which draw OVER it, undarkened) — §15.19, the same order the Eqp/Ability
# panels stack their column band.
const RP_LEFT_BAND := 47
const RP_ICON := 48
const RP_ROW_TEXT := 49
const RP_HEADER := 50
const RP_CURSOR_SHADOW := 51
const RP_CURSOR_LIT := 52
const DEFAULT_MENU_RUNG := 34

## Virtual PSX screen (display px) — for the UIVitalsBand display-space subtract.
const SCREEN := Vector2(256.0, 240.0)

## Auto-play the box-open on _ready (headful check). A test/host drives it by hand.
@export var autoplay_open: bool = true
## Per-instance fast box-open override (ORed over the `equipicker.window.fast`
## spec literal the window element auto-binds — the F3 checkbox's home now).
@export var fast: bool = false
@export var overlay_rung_offset: int = DEFAULT_MENU_RUNG

## Emitted on confirm (○/Enter) with the highlighted row. The equip COMMIT is the outer layer (§15.26).
signal chosen(row: int)
## Emitted when the highlighted row changes (every ↑/↓ move, and once when the picker's content is
## first built). The host recomputes the numeric stat-DELTA preview for the item now under the cursor
## (EQUIP_STAT_PREVIEW.md) — so the compare panel tracks the cursor live.
signal selection_changed(row: int)
## Emitted on cancel (×) — the host closes the picker back to the §15.25 slot focus.
signal cancelled
## Emitted when the box-CLOSE animation (play_close) finishes shrinking to a point — the host
## frees the picker on this, so the window folds shut instead of vanishing.
signal closed

## §15.26 (b) — the ITEM.BIN item-icon CLUT (chosen by item TYPE) and (a, §15.28) the type/class-glyph
## idle CLUT. The icon CLUT-swap-to-green causal test proved 0x3fa8 keys exactly the picker icons +
## equipped mini-icons. The glyph CLUT is STATIC-ROOTED (round 47): the provider FUN_8011AA34 writes
## descriptor+8 from DAT_801CD1BC, loaded by the palette swapper FUN_801298C0 from the WORLD constant
## bank — idle 0x7C3C (@0x8018DF8C, == FRAME.BIN tail +0x9000), highlight 0x7D3C (@0x8018DF8E). The
## live prim scan shows every picker row idle (0x7C3C); round-35's 0x7dfc claim is REFUTED (that id
## is a different bank slot, DAT_801CD5E4's highlight value).
const ITEM_ICON_CLUT := 0x3fa8
const TYPE_GLYPH_CLUT := 0x7c3c

## §15.26 (b) — the ITEM.BIN item-icon source rect for an item's `graphic` byte, the WORLD literal
## from `world_item_icon_place 0x800EA990`: U=(graphic%15)*16, V=(graphic/15)*16+0x20, 16x16 (the
## ITEM.BIN page at VRAM(896,256)). PURE + static so the guard asserts the formula without the
## (unextracted) ITEM sheet — the icon TEXTURE is the documented §15.26 deferral, the geometry is here.
## §15.26 dyn proofs: graphic 12 -> u192,v32; 1 -> u16,v32; 90 -> u0,v128; 0 -> u0,v32.
static func icon_uv_for(graphic: int) -> Rect2:
	return Rect2((graphic % 15) * 16, (graphic / 15) * 16 + 0x20, 16, 16)


## §15.26 (b) — the ITEM.BIN icon CLUT chosen by item `type` (= itemRecord[0], a 0..15 bank selector).
## WORLD path `world_item_icon_place 0x800EA990`: CLUT = GetClut(DAT_80153198 + (type%8)*16,
## DAT_8015319a + type/8). Round-36 read those two DAT bases from the live oracle RAM:
## DAT_80153198 = 640, DAT_8015319a = 254 → CLUT(type) = 0x3fa8 + (type & 7) + (type >> 3) * 0x40
## (16 banks at VRAM(640,254) row 0..7 and VRAM(640,255) row 8..15). Causally validated: the picker's
## weapons render type 0 = 0x3fa8; the Eqp-panel armour showed 0x3fae (type 6) and 0x3feb (type 11).
## `item_icons.json.palettes[type]` matches each VRAM CLUT byte-for-byte, so palette index == type.
static func type_clut(item_type: int) -> int:
	var t := item_type & 0xf
	return 0x3fa8 + (t & 7) + (t >> 3) * 0x40


## The candidate item rows. Each = {id, name, equipped, owned, graphic, palette, wtype} — the ROM
## 12-byte item record bytes items.json mirrors 1:1 (ITEM_EQUIPMENT_DATA.md §1, RE round 49; built
## for a slot by EquipCandidates). The host sets this BEFORE add_child()/_ready (like
## StartActionMenu.rows). `graphic` = rec[1], keys the ITEM.BIN icon (col b via icon_uv_for);
## `palette` = rec[0], keys the icon CLUT bank (type_clut → 0x3FA8+pal; round 49 corrected the
## §15.26-b "by item type" reading — the selector IS the palette byte, and every row now samples
## its own bank, closing the palette-0 stopgap). `wtype` = rec[5] item_type_id, the CLASS byte
## keying the per-type glyph cell (col a; round-49 live-proven for Sword/Knife/Shield/Rod/Hat/
## Clothing/Shoes). Counts "NN/NN" = equipped-across-roster / party-total.
## Defaults = the sstate0 R.Hand candidates with the ROM-true bytes (round 49 fixed the round-35
## mispairing graphic 2/1/12): Broad Sword id 19 g12, Mythril Knife id 2 g2, Dagger id 1 g1 —
## live prims u192/u32/u16 @ v32, all palette 0 (CLUT 0x3FA8).
var entries: Array = [
	{"id": 19, "name": "Broad Sword", "equipped": 4, "owned": 4, "graphic": 12, "palette": 0, "wtype": 3},
	{"id": 2, "name": "Mythril Knife", "equipped": 0, "owned": 1, "graphic": 2, "palette": 0, "wtype": 1},
	{"id": 1, "name": "Dagger", "equipped": 4, "owned": 4, "graphic": 1, "palette": 0, "wtype": 1},
]

var _atlas: RangeTileAtlas
var _menu_text: UIMenuText
var _tab_pal: ImageTexture                # header-cell CLUT 0x7CBC (cream ink on dark; §15.26 f)
var _header_mats: Array[ShaderMaterial] = []  # baked "Eqp."/"ALL" header cell mats (for the guard)
var _value_pal: ImageTexture              # count-digit CLUT (0x7C3C-family, so '/' renders)
var _item_icon_tex: Texture2D            # ITEM.BIN indexed sheet (item_icons_index.tga)
var _item_palettes: Array = []           # the 16 ITEM.BIN palettes (index == item type; §15.26 b)
var _type_pal_cache: Dictionary = {}     # item type -> its 16-colour CLUT texture (built on demand)
var _icon_mats: Array[ShaderMaterial] = []  # per-row ITEM.BIN icon materials (for the guard)
var _glyph_mats: Array[ShaderMaterial] = [] # per-row weapon type-glyph materials (§15.26 a; for the guard)
var _count_digit_mats: Array = []           # per-row count DIGIT glyph mats (§15.27 BIG set; for the guard)
var _count_slash_mats: Array = []           # per-row count '/' glyph mats (§15.27 SMALL set; for the guard)
var _glyph_pal: ImageTexture                # dark type-glyph CLUT 0x7c3c (weapon_icon_dark_colors)
var _glove_lit_pal: ImageTexture
var _glove_shadow_pal: ImageTexture

var _row: int = 0
var _scroll: int = 0   # first visible entry index (the ROM DAT_801cd54c analogue)
# The registered WINDOW ELEMENT (ADR-0088): the movable origin, the STRIPE chrome, the
# box-open beat, and the clip aperture all live on it. Content mounts under it via
# _window.rel_world (relative to the frozen authored home), so moving the element moves
# the whole coherent window. Replaces the hand-rolled _frame_origin + accumulators.
var _window: UI3Element
# The registered CHILD elements (ADR-0088 amendment §1 — no second registration tier):
# each remaining content part is an element whose composite rect is its placement knob
# and whose interior scalars are spec FIELDS on it (equipicker.<part>.<field> auto-binds).
# The elements persist; only their PAYLOAD is freed + rebuilt on a content-knob scrub.
var _strip_elem: UI3Element    # the §15.19 brown left column band (fields: sub, feather)
var _header_elem: UI3Element   # the "Eqp."/"ALL" stripe cells (fields: eqp_label_x, all_label_x)
var _rows_elem: UI3Element     # the item-list ASSEMBLY — ONE element; rows are payload
                               # placed from its rect.y + `pitch` driver (amendment §3)
# The glove cursor's own element: clip = UNCLIPPED as a DECLARED answer (the engine
# pushes the explicit sentinel), riding the window at the authored home.
var _cursor_elem: UI3Element
var _lit_holder: Node3D
var _shadow_holder: Node3D
var _cursor_mats: Array[ShaderMaterial] = [] # glove lit+shadow (for the guard)
var _left_strip_mat: ShaderMaterial          # the §15.19 subtractive brown left column band

const _BOB_TICK := 1.0 / 60.0

# Glove bob (§15.20 / ADR-0046).
var _bob_frame: int = 0
var _bob_accum: float = 0.0
var _moving_frames: int = 0
var _idle_pairs: Array = []
var _select_pairs: Array = []

# True once the first _build_content ran — the rebuild-on-scrub guard (each on_update's
# subscribe-time apply fires during _subscribe_content_rebuilds, before the first build).
var _content_built: bool = false
var _rebuild_pending: bool = false   # coalesce a frame's content-knob scrubs into one DEFERRED rebuild (see _rebuild_if_bound)


func _ready() -> void:
	_atlas = RangeTileAtlas.new()
	_menu_text = UIMenuText.new()
	_idle_pairs = GloveCursorBob.load_glove_pairs("glove_idle")
	_select_pairs = GloveCursorBob.load_glove_pairs("glove_select")
	_value_pal = _palette_from_colors(_atlas.stat_label_colors())
	_tab_pal = _palette_from_colors(_atlas.window_tab_colors())
	_glove_lit_pal = _palette_from_colors(_atlas.menu_glove_lit_colors())
	_glove_shadow_pal = _palette_from_colors(_atlas.menu_glove_shadow_colors())
	_glyph_pal = _palette_from_colors(_atlas.type_glyph_colors())   # §15.28 a: idle dark CLUT 0x7c3c
	_load_item_icons()
	add_to_group("box_open_panels")      # the F3 "Box-open animation" replay buttons find us here

	_build_window()
	_build_elements()             # the child elements mint their own equipicker.<part>.* binds
	_subscribe_content_rebuilds() # a content-knob scrub frees + rebuilds the payload
	_build_content()

	if autoplay_open:
		play_open()
	# else: the element boots settled (aperture = full live rect) — nothing to drive.
	_place_cursor()


## Build the registered WINDOW ELEMENT once (ADR-0088). Its spec dict is the single
## authored home: the live rect (composite `equipicker.window.rect`), the frozen
## authored_home content anchor, the STRIPE chrome + fine-dither interior patch, the
## box-open beat, and the OWN_APERTURE clip answer. The element builds the chrome,
## the clip engine discovers the payload, and the transition engine plays open/close.
func _build_window() -> void:
	_window = UI3Element.new({
		"id": "equipicker.window",
		# §15.26 window rect (framebuffer-authoritative, F3-pinned 2026-08-11: chrome
		# +1y/−5w vs the unchanged authored home below).
		"rect": Rect2(76.0, 137.0, 169.0, 101.0),
		# The FIXED authored content home — frozen so content authored against it never
		# rides a live rect pin (§1). (76,135) is the ex-FRAME_HOME position.
		"authored_home": Vector2(76, 135),
		"transition": UI3Element.Transition.BOX_OPEN,
		# §15.26 (f): the FFT brown-stripe chrome (STRIPE crop), its interior tiling
		# the FINE-dither patch the Eqp/Ability/stats panels tile — the STRIPE crop's
		# own 5px body repeats into a coarse mottle (see UIFrame.center_region).
		"frame": UI3Element.Frame.STRIPE,
		"frame_center_patch": Vector4(6, 7, 21, 17),
		"frame_rp": RP_FRAME,
		"clip": UI3Element.Clip.OWN_APERTURE,
		# ADR-0088 amendment §4 (first consumer): the header cells (y132) poke 4px
		# above the window rect top (y136) — pad the box the box-open plays over so
		# they ride the reveal instead of being clipped. Port-side affordance: the
		# ROM scissor is the container rect.
		"aperture_pad": Vector4(0, 4, 0, 0),
		# DEFAULT_MENU_RUNG(34) − RP_BASE(40): the fold-rung offset z_for adds to a
		# payload render_priority (the picker band clears the backgrounded list-menu).
		"depth_rung": -6,
		# ADR-0097 §2: one cadence per VERB. DEFAULT is the AUTHORED "use the house rule"
		# answer (opens normal, closes fast) — not silence.
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
	})
	add_child(_window)
	_window.closed.connect(func() -> void: closed.emit())
	if fast:
		# per-instance export override of the class literal — the OPEN only (ADR-0097 §2)
		_window.spec()["open_cadence"] = UI3BoxOpenBeat.Cadence.FAST
	if overlay_rung_offset != DEFAULT_MENU_RUNG:
		_window.spec()["depth_rung"] = overlay_rung_offset - RP_BASE


## Build the persistent CHILD elements once (ADR-0088 amendment §1/§3). Each spec dict
## is the single authored home for that part's placement (composite `<id>.rect`) and its
## content knobs (spec fields — auto-minted `<id>.<field>` binds). Placements are
## authored ABSOLUTE display px (amendment §2 — the oracle's coordinate space); riding
## the movable window is mechanical (the element origin chain), never authored.
func _build_elements() -> void:
	# The BROWN vertical strip on the LEFT (§15.19) — the same subtractive UIVitalsBand
	# column band the Eqp/Ability panels draw: fg/255 grey subtracted in display space so
	# the tan interior reads brown under it. Oracle-rooted (fb4, §15.26; round-45 measured
	# x94..112/y144..232) then F3-dialed + materialised (x95/w17/y142/h87/feather2.5).
	# The icon column — one weapon icon centred in it per row. Box-open reveals it.
	_strip_elem = UI3Element.new({
		"id": "equipicker.strip",
		"rect": Rect2(95, 142, 17, 87),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
		"sub": 48.0 / 255.0,   # oracle column-band subtract (tan −48 → brown) = DetailScene.BAND_SUB
		"feather": 2.5,        # x-edge fade into the tan body (px), each side (F3-dialed pin)
	})
	_window.add_child(_strip_elem)
	# The header stripe cells (§15.26 f, right-justified): "Eqp." ≈x200, "ALL" ≈x222. Cell
	# top y132 (F3-pinned; was 134) lands the ink on the brown header stripe (frame top
	# y135, dark fill y137..142; the cell art carries a row of tan padding above its glyph).
	_header_elem = UI3Element.new({
		"id": "equipicker.header",
		"rect": Rect2(200, 132, 45, 12),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
		"eqp_label_x": 200.0,
		"all_label_x": 222.0,
	})
	_window.add_child(_header_elem)
	# The item-list ASSEMBLY (amendment §3): ONE element — rows are payload placed from
	# rect.y (row-0 text top) + the `pitch` driver; columns are FIELDS, not elements (a
	# column has no origin). Row y + all dy fields re-measured 2026-08-11 against the
	# LIVE picker quicksave (stripe-underline-anchored ink rows, oracle fb + prim scan
	# + VRAM texels, issue #290 follow-up): name ink row_y+2 = oracle 150 → rows y150
	# (round-42's 152 carried the window's own +2); glyph quad top row_y+0 x80 (§15.28
	# live prims: 12×12 at (80,150), template rec (0x50,0x96)); icon quad
	# top row_y−2 (16×16 straddles); BIG count digits right-aligned ending x217 (eq) /
	# x238 (owned), digit INK fb rows 152..160 = quad row_y−1+PAD2 with the strip's
	# blank v0..3 ('0' ink starts v4); SMALL "/" x217, ink spans EXACTLY the digit ink
	# rows (VRAM: '/' stroke v16..24 vs digit v4..11+prim-v1 → both fb 152..160), so
	# slash_dy 2 bottom-aligns it with the digits — NOT a superscript slash.
	# NAME_X F3-pinned 120 (was 116).
	_rows_elem = UI3Element.new({
		"id": "equipicker.rows",
		"rect": Rect2(79, 150, 156, 48),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
		"pitch": 16.0,
		"name_x": 120.0,
		"glyph_x": 80.0,
		"glyph_dy": 0.0,
		"icon_x": 96.0,
		"icon_dy": -2.0,
		"eq_right_x": 217.0,
		"slash_x": 217.0,
		"owned_right_x": 238.0,
		"count_dy": -1.0,
		"slash_dy": 2.0,
	})
	_window.add_child(_rows_elem)
	# The glove cursor element: Clip.UNCLIPPED is a DECLARED answer (the engine pushes
	# the explicit infinite-aperture sentinel), not an omitted array membership (§15.20
	# issue 5 — the glove pokes off the frame's LEFT edge, outside the box-open scissor,
	# drawn on top). Its rect is DERIVED (the authored-home mirror), so it mints no slug
	# and rides the window element for free.
	_cursor_elem = UI3Element.new({
		"id": "equipicker.cursor",
		# The glove's single FIXED home (ADR-0088 Amendment 4 §2): an AUTHORED literal — the
		# repeatedly-pixel-tuned home earns an editable equipicker.cursor.rect row (was a
		# derived([]) dead-end mirroring the retired FRAME_HOME const).
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_cursor_elem.name = "PickerGloveCursor"
	_window.add_child(_cursor_elem)


## Build (or rebuild) the PAYLOAD under the persistent elements — the band quad, header
## cells, row glyph/icon/text/count meshes, and the glove. Called once from _ready and
## again from _rebuild_if_bound on every content-knob scrub; the elements (and the
## window chrome) persist. Newly mounted payload receives the current aperture via the
## clip engine's node_added coverage — mid-open rebuilds work by construction.
func _build_content() -> void:
	for e: UI3Element in [_strip_elem, _header_elem, _rows_elem, _cursor_elem]:
		for c in e.get_children():
			c.free()   # synchronous: called from a Tune callback
	_cursor_mats.clear()
	_header_mats.clear()
	_icon_mats.clear()
	_glyph_mats.clear()
	_count_digit_mats.clear()
	_count_slash_mats.clear()
	_left_strip_mat = null
	_lit_holder = null
	_shadow_holder = null

	_build_left_strip()
	_build_header()
	_build_rows()
	_build_cursor()
	_content_built = true


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


## Move the highlight down/up one row (wraps, like the FFT list menus); ride the select bob table.
## Past the window edge the LIST scrolls (round 49: ROM capacity 5) and the row payload rebuilds.
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
			_build_content()   # re-mount the visible row window (synchronous frees, like a scrub)
	_place_cursor()
	# The cursor now rests on a new item — let the host recompute the numeric stat-DELTA preview
	# for it (EQUIP_STAT_PREVIEW.md). The FIRST selection is pushed by the host on open (it connects
	# after add_child, so it can't catch an emit fired during the build).
	selection_changed.emit(_row)


func confirm() -> void:
	chosen.emit(_row)


func cancel() -> void:
	cancelled.emit()


# -----------------------------------------------------------------------------
# Box-open (§15.17 center-out scissor) — played by the shared TransitionEngine's
# BOX_OPEN beat on the window element (ADR-0088; the per-class accumulator died).
# -----------------------------------------------------------------------------
## `cadence` is the one-invocation override (ADR-0097 §4) — pass a UI3BoxOpenBeat.Cadence to
## make THIS play snap or slow without changing what the element is authored to do.
func play_open(cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	if _cursor_elem != null and is_instance_valid(_cursor_elem):
		_cursor_elem.visible = true   # a replay after play_close restores the glove
	_window.open(cadence)


## Play the box-CLOSE: the same beat reversed — the center-out scissor shrinking the
## fully-rendered window back to a point — then `closed` re-emits from the element.
## The glove cursor (unclipped, on top) hides immediately: focus has already left.
func play_close(cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	if _cursor_elem != null and is_instance_valid(_cursor_elem):
		_cursor_elem.visible = false
	_window.close(cadence)


## The §15.17 aperture at open-frame `n` against the LIVE window rect (pure preview).
func aperture_at_frame(n: int) -> Rect2i:
	var full := Rect2i(_window.rect())
	if n < 0:
		return Rect2i(full.get_center(), Vector2i.ZERO)
	return UI3BoxOpenBeat.rect_for(full, n,
		UI3BoxOpenBeat.resolve(_window.cadence_for(UI3Element.OPEN_CADENCE), true))


func aperture() -> Rect2i:
	return _window.aperture()


## The registered window element — the movable origin + chrome + aperture carrier.
func window() -> UI3Element:
	return _window


## The body materials (chrome + strip + header + rows) the box-open scissor reveals —
## the clip engine's fresh discovery over the window element AND its PARENT_APERTURE
## child elements (the UNCLIPPED cursor excluded by its declared answer).
func body_materials() -> Array:
	var out := _window.payload_materials()
	for e: UI3Element in [_strip_elem, _header_elem, _rows_elem]:
		if e != null and is_instance_valid(e):
			out.append_array(e.payload_materials())
	return out


## The glove cursor materials (lit + shadow) — UNCLIPPED, on top. Exposed for the guard.
func cursor_materials() -> Array:
	return _cursor_mats


# -----------------------------------------------------------------------------
# Glove cursor placement + bob (§15.20). Bob axis = X. Anchored on the frame's LEFT edge.
# -----------------------------------------------------------------------------
## The glove display top-left for `row` at settled bob 0 — the RE'd anchor (64, 146+row·16). Pure so
## the guard asserts it without a built scene.
static func cursor_anchor_for(row: int) -> Vector2:
	return StartActionMenu.cursor_display_pos_in(ROWS_CONTAINER, row, 0)


func cursor_bob_x() -> int:
	var pairs := _select_pairs if _moving_frames > 0 else _idle_pairs
	return GloveCursorBob.glove_offset_for_frame(pairs, _bob_frame)


func cursor_display_pos() -> Vector2:
	# The cursor rides the VISIBLE row index — scrolling slides the list under it (round 49).
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


# -----------------------------------------------------------------------------
# Scene build. The window CHROME (STRIPE 9-slice + dither interior + window CLUTs)
# is built by the ELEMENT from its frame criterion — see _build_window.
# -----------------------------------------------------------------------------


## The BROWN vertical strip on the LEFT (§15.19) — the SAME UIVitalsBand column band the
## Eqp/Ability panels use, feathered LEFT/RIGHT (an x trapezoid) so it fades into the tan interior.
## It subtracts fg/255 grey in display space (tan → brown). Reparented under the STRIP ELEMENT so
## it rides the movable window; the clip engine discovers its material there (PARENT_APERTURE →
## the window's box-open reveals it center-out). Rung RP_LEFT_BAND sits between the frame
## (darkened by it) and the icons/text (drawn over it, undarkened). Geometry = the strip element's
## LIVE rect (equipicker.strip.rect); sub/feather = its spec fields.
func _build_left_strip() -> void:
	# The strip rect is authored ABSOLUTE display px; shift by the window's live-rect
	# delta so the band lands on the MOVED window — the band builds in absolute display
	# space (below), so the element origin chain's mechanical ride doesn't apply to the
	# build coordinates. A strip.rect scrub is covered too: the rebuild subscription
	# re-derives the band from the live rect.
	var off := _window.rect().position - _window.authored_home()
	var r := _strip_elem.rect()
	var x0 := r.position.x + off.x
	var x1 := r.position.x + r.size.x + off.x
	var sy := r.position.y + off.y
	var f := _fld(_strip_elem, "feather", 2.5)
	var rung := overlay_rung_offset + (RP_LEFT_BAND - RP_BASE)   # match z_for's fold-rung convention
	# Build under the picker ROOT (world origin) so the band's ABSOLUTE display-px placement is
	# world-correct, then reparent it keep-global under the strip element (below).
	_left_strip_mat = UIVitalsBandCls.build(self, {
		"name": "PickerLeftStrip",
		# quad spans the body ± feather columns each side; the full subtract covers [x0, x1].
		"x0": x0 - f, "x1": x1 + f,
		# y: no feather — a full-height vertical strip over the rect's y span.
		"y_top_out": sy, "y_top_in": sy,
		"y_bot_in": sy + r.size.y, "y_bot_out": sy + r.size.y,
		# x: tight fade OUTSIDE the body, into the tan interior (mirrors DetailScene._build_column_band).
		"x_left_out": x0 - f, "x_left_in": x0,
		"x_right_in": x1, "x_right_out": x1 + f,
		"full_sub": _fld(_strip_elem, "sub", 48.0 / 255.0), "rung": rung,
	}, _window.ppu(), SCREEN)
	# Reparent the holder keep-global under the strip element (its settled world transform
	# — screen pos + fold depth — is unchanged) so it rides the movable window element;
	# the clip engine discovers its material there (box-open reveals it center-out).
	var holder := get_node_or_null("PickerLeftStrip") as Node3D
	if holder != null:
		holder.reparent(_strip_elem, true)
		# reparent() = remove_child + add_child, so the strip mesh's tree_exiting fires Fold's un-enroll
		# hook (b6400949d) and NULLS its render_layer — dropping the subtractive brown column from the
		# fold layer so it stops compositing (the dither interior shows through instead of the darken).
		# Re-enroll it (idempotent) with the SAME rung it was built with. (f0e56a591 fixed the detail
		# vitals stripe + formation roster this way but missed this picker strip site.)
		if Fold.owns() and _left_strip_mat != null:
			var strip_mi: MeshInstance3D = null
			for c: Node in holder.get_children():
				if c is MeshInstance3D:
					strip_mi = c
					break
			if strip_mi != null:
				Fold.add(strip_mi, _left_strip_mat, DepthMode.rung_z(rung))


## The left brown-strip material — for the guard / a host to tint. Null until _build_left_strip.
func left_strip_material() -> ShaderMaterial:
	return _left_strip_mat


## The strip element's LIVE rect (display px) — the equipicker.strip.rect composite knob.
func left_strip_rect() -> Rect2:
	return _strip_elem.rect()


## Read a scalar spec FIELD off a child element (the amendment-§1 content-knob home).
func _fld(e: UI3Element, field: String, fallback: float) -> float:
	return float(e.spec().get(field, fallback))


# -----------------------------------------------------------------------------
# Content-rebuild subscriptions (ADR-0088 amendment §1). The knobs themselves are the
# child elements' auto-binds now (composite rects + spec fields — the elements apply
# a scrub to their own spec/transform); the picker only subscribes the REBUILD, since
# the payload meshes are built FROM those values. The F3 "Equip picker" panel and the
# UI3 page are pure views over the same slugs.
# -----------------------------------------------------------------------------
func _subscribe_content_rebuilds() -> void:
	for slug: String in [
		# The strip band derives its quad from the live rect + sub/feather fields.
		"equipicker.strip.rect", "equipicker.strip.sub", "equipicker.strip.feather",
		# Header cells re-mount at their label x fields (rect pos rides mechanically).
		"equipicker.header.eqp_label_x", "equipicker.header.all_label_x",
		# The rows assembly re-lays its payload from pitch + the column fields
		# (rect pos rides mechanically; row y derives from the frozen authored home).
		"equipicker.rows.pitch", "equipicker.rows.name_x",
		"equipicker.rows.glyph_x", "equipicker.rows.glyph_dy",
		"equipicker.rows.icon_x", "equipicker.rows.icon_dy",
		"equipicker.rows.eq_right_x", "equipicker.rows.slash_x",
		"equipicker.rows.owned_right_x",
		"equipicker.rows.count_dy", "equipicker.rows.slash_dy",
	]:
		TunePort.on_update(self, slug, func(_v: Variant) -> void: _rebuild_if_bound())


## Rebuild the element payload after a content-knob scrub — but only once the first
## build ran (each on_update's subscribe-time apply fires before it). The aperture
## needs no hand re-derive: the window element owns it, and freshly mounted payload
## receives the current clip via the engine. Runs AFTER the owning element applied the
## scrub to its spec/rect (its own bind subscribed first), so the build reads fresh.
##
## DEFERRED on purpose (same fix as DetailScene._rebuild_if_bound). A content-knob scrub
## arrives INSIDE the F3 SpinBox's value_changed → C++ SpinBox::gui_input; _build_content
## free()s the payload (fold-carrier band/glyphs) synchronously, which — while gui_input is
## still on the stack, about to touch its range_click_timer — SIGSEGVs the 4.8 fork with
## wandering heap corruption. Hand the rebuild to the next idle frame (never nested in input
## dispatch) and coalesce a frame's scrubs into one. _build_content stays synchronous when
## called directly from _ready (not an input callstack).
func _rebuild_if_bound() -> void:
	if _content_built and not _rebuild_pending:
		_rebuild_pending = true
		_flush_pending_rebuild.call_deferred()


## Deferred flush for _rebuild_if_bound: rebuilds the payload at idle, out of the scrub's
## input/signal callstack. Re-checks that content is still built (the picker may have closed
## between the scrub and this flush).
func _flush_pending_rebuild() -> void:
	if not _rebuild_pending:
		return
	_rebuild_pending = false
	if _content_built:
		_build_content()
		_place_cursor()


func _build_header() -> void:
	# §15.26 (f), defect #5: the "Eqp."/"ALL" header is BAKED RANGETILE word cells drawn through the
	# cream active-label CLUT 0x7CBC — the SAME sheet + mechanism as the §15.19 Eqp/Ability/Menu window
	# tabs — NOT dark FONT.BIN text and NOT cream-tinted FONT glyphs (round 34/36 stand-ins). "Eqp"
	# reuses the precedent equipment-menu tab cell (window_tabs 28,32; the user: "the EXACT SAME Eqp");
	# "ALL" is the "Total Next ALL Check…" word-row cell the parser now exposes (window_tabs 45,120).
	# Both are right-justified in the header stripe; the box-open aperture reveals them via the
	# engine's payload discovery (the header sits inside the frame top, unlike the START menu's
	# outside-clip title tab).
	# The cells mount at the header ELEMENT's frozen authored y (its rect.y knob moves
	# the origin, and the cells ride); the label x's are its spec fields.
	var y := _header_elem.authored_home().y
	if _atlas.has_window_tab(HEADER_EQP_CELL):
		_mount_header_cell(_atlas.window_tab_rect(HEADER_EQP_CELL),
			_fld(_header_elem, "eqp_label_x", 200.0), y)
	if _atlas.has_window_tab(HEADER_ALL_CELL):
		_mount_header_cell(_atlas.window_tab_rect(HEADER_ALL_CELL),
			_fld(_header_elem, "all_label_x", 222.0), y)


## Mount one baked header word cell (top-left at display x,y) through the cream window-tab CLUT, via
## the shared index→CLUT sprite material — collected into `_header_mats` (for the guard). §15.26 (f):
## the cream MECHANISM + the real baked art, not FONT.
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


## The baked header cell materials ("Eqp." + "ALL") — for the guard. Proves the header renders
## through the RANGETILE index→CLUT cream MECHANISM, not FONT.BIN glyphs (defect #5).
func header_cell_materials() -> Array:
	return _header_mats


## The item-list window frame's 9-slice source region — for the guard (§15.26 f / GAP 3): proves the
## picker uses the FFT brown-stripe chrome (UIFrame.STRIPE_SOURCE), not the flat menu-tile default.
func frame_source_region() -> Vector4:
	var mat := _window.chrome_material()
	if mat != null:
		return mat.get_shader_parameter("source_region")
	return Vector4.ZERO


## The fine-dither atlas patch the frame's 9-slice CENTER tiles for the interior (the
## element's `frame_center_patch` spec literal, auto-bound as
## equipicker.window.frame_center_patch). The interior matches the Eqp/Ability/stats
## panels instead of the STRIPE crop's coarse 5px body.
func body_dither_patch() -> Vector4:
	return _window.spec().get("frame_center_patch", Vector4.ZERO)


## The frame material's live `center_region` uniform — for the guard: proves the interior tiles
## the fine patch (not the STRIPE interior).
func frame_center_region() -> Vector4:
	var mat := _window.chrome_material()
	if mat != null:
		return mat.get_shader_parameter("center_region")
	return Vector4.ZERO


func _build_rows() -> void:
	# The assembly's rows are payload placed from its frozen authored row-0 top (rect.y
	# knob moves the origin, rows ride) + the `pitch` driver; columns are its fields.
	var s := _rows_elem
	var row0_y := s.authored_home().y
	var pitch := _fld(s, "pitch", 16.0)
	# Only the visible window renders (round 49: ROM capacity VISIBLE_ROWS, scroll slides it).
	for i in range(_scroll, mini(entries.size(), _scroll + VISIBLE_ROWS)):
		var e: Dictionary = entries[i]
		var y := row0_y + (i - _scroll) * pitch
		# (c) NAME — FONT.BIN (msgid item_id+0x6800 in the ROM; OUR name string here).
		# No mats_out: the clip engine discovers the glyph materials (ADR-0088 §3).
		_menu_text.mount(s, String(e.get("name", "")),
			s.rel_world(_fld(s, "name_x", 120.0), y) + s.z_for(RP_ROW_TEXT), RP_ROW_TEXT, s.ppu())
		# (d)/(e) COUNTS "NN/NN" — BIG-set digits + SMALL slash through the value CLUT
		# (§15.27: ROM digit prims sample the FRAME.BIN BIG strip U=0x78+8·d, v=1, CLUT
		# 0x7C3C; the slash alone stays the SMALL set). Values are STUBS (§15.26).
		var eq := str(int(e.get("equipped", 0))).pad_zeros(2)
		var ow := str(int(e.get("owned", 0))).pad_zeros(2)
		var count_y := y + _fld(s, "count_dy", -1.0)
		_mount_number_right(eq, _fld(s, "eq_right_x", 217.0), count_y)
		_menu_text.mount_number(s, "/",
			s.rel_world(_fld(s, "slash_x", 217.0), y + _fld(s, "slash_dy", 2.0)) + s.z_for(RP_ROW_TEXT),
			RP_ROW_TEXT, s.ppu(), _value_pal, _count_slash_mats)
		_mount_number_right(ow, _fld(s, "owned_right_x", 238.0), count_y)
		# (b) item-icon column: the source rect IS computed here via the WORLD-literal formula
		# `icon_uv_for(e.graphic)` (0x800EA990) through CLUT ITEM_ICON_CLUT (by e.type). The icon
		# TEXTURE is the §15.26 deferral — the indexed ITEM.BIN sheet (VRAM 896,256) + per-type CLUT
		# LUT are NOT extracted into the project yet — so nothing is mounted (kept behind the correct
		# mechanism, never a look-alike sprite). When the sheet lands, mount cell icon_uv_for(graphic).
		# (b) item ICON — the REAL ITEM.BIN sprite at icon_uv_for(graphic), through the index→CLUT shader
		# (extracted by tools/extract_item_sprites.py). Skipped for graphic 0 (= "no item").
		if _item_icon_tex != null and int(e.get("graphic", 0)) > 0:
			_mount_item_icon(int(e.get("graphic", 0)), int(e.get("palette", 0)),
				_fld(s, "icon_x", 96.0), y + _fld(s, "icon_dy", -2.0))
		# (a) type/class GLYPH — the PER-TYPE dark weapon-class marker LEFT of the icon (§15.28:
		# atlas type_glyph_rect(wtype) through the idle dark CLUT 0x7c3c). ROM prim: 12×12 at
		# screen x=80, top == the row text top (glyph_x 80 / glyph_dy 0, template rec (0x50,0x96)).
		_mount_type_glyph(int(e.get("wtype", 0)),
			_fld(s, "glyph_x", 80.0), y + _fld(s, "glyph_dy", 0.0))


## Load the extracted ITEM.BIN icon sheet (index_atlas) + keep its 16 palettes. Each row picks its bank
## by item `type` (§15.26 b, round-36): palette index == type. No-op (empty icon column) if absent.
func _load_item_icons() -> void:
	if not ResourceLoader.exists(_ITEM_ICON_INDEX_TEX) or not FileAccess.file_exists(_ITEM_ICON_JSON):
		return
	_item_icon_tex = load(_ITEM_ICON_INDEX_TEX)
	var data = JSON.parse_string(FileAccess.open(_ITEM_ICON_JSON, FileAccess.READ).get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	_item_palettes = data.get("palettes", [])


## The 16-colour CLUT texture for an item `palette` byte (rec[0]; round 49 — the ROM CLUT
## selector). Clamped 0..15, built once per palette and cached. `type_clut(pal)` documents the
## WORLD CLUT id this palette encodes (0x3FA8+pal / 0x3FE8+(pal−8)).
func _palette_for_type(item_type: int) -> ImageTexture:
	var t := clampi(item_type, 0, 15)
	if not _type_pal_cache.has(t):
		_type_pal_cache[t] = _item_palette_texture(_item_palettes, t)
	return _type_pal_cache[t]


## A 16×1 CLUT texture from ITEM.BIN palette `pal_idx` (each entry [r,g,b,a] 0-255). Index 0 stays
## transparent (the shader also keys idx==0 → discard).
func _item_palette_texture(palettes: Array, pal_idx: int) -> ImageTexture:
	var pal: Array = palettes[pal_idx] if pal_idx < palettes.size() else []
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		var c := Color(0, 0, 0, 0)
		if i < pal.size():
			var e = pal[i]
			c = Color8(int(e[0]), int(e[1]), int(e[2]), int(e[3]))
		img.set_pixel(i, 0, c)
	return ImageTexture.create_from_image(img)


## Mount one 16×16 ITEM.BIN icon (top-left at display x,y) via the index→CLUT shader —
## collected into `_icon_mats` for the guard; the box-open aperture reveals it via the
## engine's payload discovery.
func _mount_item_icon(graphic: int, item_type: int, x: float, y: float) -> void:
	var cell := icon_uv_for(graphic)
	var mat := ShaderMaterial.new()
	mat.shader = load(_ICON_SHADER)
	mat.set_shader_parameter("mode", 0)
	mat.set_shader_parameter("index_atlas", _item_icon_tex)
	mat.set_shader_parameter("atlas_size", Vector2(_item_icon_tex.get_width(), _item_icon_tex.get_height()))
	mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y))
	mat.set_shader_parameter("palette_tex", _palette_for_type(item_type))
	mat.set_shader_parameter("brightness", 1.0)
	mat.render_priority = RP_ICON
	_icon_mats.append(mat)
	var holder := Node3D.new()
	_rows_elem.add_child(holder)
	holder.position = _rows_elem.rel_world(x, y)
	var mi := _quad(cell.size)
	mi.material_override = mat
	mi.position += _rows_elem.z_for(RP_ICON)
	holder.add_child(mi)


## The per-row ITEM.BIN icon materials (§15.26 b) — for the guard. One per row with graphic>0.
func icon_materials() -> Array:
	return _icon_mats


## Mount the PER-TYPE weapon-class glyph (§15.28) for one row (top-left display x,y), through the
## shared index→CLUT sprite material against the RANGETILE atlas — the SAME mechanism as the
## header/glove, the idle dark CLUT 0x7c3c. The 12×12 cell comes from the WORLD.BIN type→UV LUT
## (atlas `type_glyph_rect(wtype)`); types without a glyph (0 / unused) mount nothing, like the ROM's
## null-provider skip. Joins `_glyph_mats` (guard); the box-open reveal is engine-discovered.
func _mount_type_glyph(wtype: int, x: float, y: float) -> void:
	if _atlas.texture == null or _glyph_pal == null:
		return
	var cell := _atlas.type_glyph_rect(wtype)
	if cell.size == Vector2.ZERO:
		return
	var mat := _sprite_mat(cell, _glyph_pal, _SPRITE_SHADER, RP_ICON)
	_glyph_mats.append(mat)
	var holder := Node3D.new()
	_rows_elem.add_child(holder)
	holder.position = _rows_elem.rel_world(x, y) + _rows_elem.z_for(RP_ICON)
	var mi := _quad(cell.size)
	mi.material_override = mat
	holder.add_child(mi)


## The per-row weapon type-glyph materials (§15.26 a) — for the guard. One per row.
func type_glyph_materials() -> Array:
	return _glyph_mats


## The loaded ITEM.BIN indexed icon sheet (null if the extracted asset is absent).
func icon_texture() -> Texture2D:
	return _item_icon_tex


func _mount_number_right(s: String, right_x: float, y: float) -> void:
	var x := right_x - _menu_text.number_width(s, NumberFont.BIG)
	_menu_text.mount_number(_rows_elem, s,
		_rows_elem.rel_world(x, y) + _rows_elem.z_for(RP_ROW_TEXT),
		RP_ROW_TEXT, _rows_elem.ppu(), _value_pal, _count_digit_mats, NumberFont.BIG)


## The count-column DIGIT glyph materials (§15.27 — BIG FRAME.BIN strip; for the guard).
func count_digit_materials() -> Array:
	return _count_digit_mats


## The count-column '/' glyph materials (§15.27 — stays the SMALL set; for the guard).
func count_slash_materials() -> Array:
	return _count_slash_mats


## Mount the glove PAYLOAD under the persistent cursor element (see _build_elements).
func _build_cursor() -> void:
	# Shadow (subtractive) FIRST/under, then the OPAQUE lit hand — the same glove as §15.20/§15.25.
	_shadow_holder = _mount_glove(_atlas.menu_glove_shadow_rect(), _glove_shadow_pal, _SHADOW_SHADER, RP_CURSOR_SHADOW)
	_lit_holder = _mount_glove(_atlas.menu_glove_lit_rect(), _glove_lit_pal, _SPRITE_SHADER, RP_CURSOR_LIT)


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


# -----------------------------------------------------------------------------
# Per-frame drive — the GLOVE BOB only (§15.20): the box-open/close accumulators
# retired into the shared TransitionEngine (ADR-0088 §4). The display↔world math
# (_rel_world/_z_for/_clip_world/_screen_to_world) retired into UI3Element and the
# clip engine.
# -----------------------------------------------------------------------------
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
