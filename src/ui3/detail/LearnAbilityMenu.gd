class_name LearnAbilityMenu
extends Node3D

## The Learn **ability list** — phase 1 of the Learn flow, the screen the job picker
## ([JobPickerMenu]) hands off to on ○. ROM `FUN_8011F5F0` (`0x8011F5F0`), render template
## `0x8018D2F8`. `research/working_documents/LEARN_ABILITY_LIST.md` is the spec; every
## constant below cites the section it comes from.
##
## TWO panels, not one — that is the whole shape of the screen:
##   TOP    template `(33,41) 196x20`  — a one-row job summary: the job NAME plus
##          Lv. / Total / Next / Jp, and a `Master!` cell + star when the job is mastered (§3.2).
##   BOTTOM template `(33,86) 196x132` — `Ability / Mp / Speed / Jp` headers, the four
##          ability-TYPE tab icons, and eight 16-px rows of the current tab's abilities (§3.3/§5.2).
##
## Both panels open from ONE stage counter. The template carries exactly one `s22` record
## (`0x8018D4E3`), so the aperture advances once per frame for BOTH panels together — they do
## not stagger (§3.4, live-confirmed §13.2: at scale 90 both panels measure `floor(w·p)` on
## BOTH axes in the same frame). The port reproduces that by opening both windows on the same
## frame at the same cadence; `BoxOpenAnimator.scaled_rect` is already integer-floor
## (`(w*p)/100` on ints), which is `LEARN_PICKER.md` §21's one port-facing rule.
##
## ROWS carry TWO independent dim mechanisms driven by ONE flag (§7) — this is the most
## likely "looks right but isn't" failure on this screen, so both are reproduced:
##   (a) the NUMBERS swap CLUT outright — `0x7C3C` enabled → `0x7FA4` disabled;
##   (b) the NAME shifts to a different SHADE BAND inside one CLUT — `0x7FFC` indices
##       {1,2,3} enabled → {5,6,7} disabled (the glyph blitter's `bVar1 += shade * 4`).
## Read out of `learn_ability_ss3_settled.sstate` this session, those two land on the SAME
## three colours: `0x7FA4[1,2,3] == 0x7FFC[5,6,7] == (99,90,74)/(115,107,90)/(140,132,115)`.
## Two ROM mechanisms, one painted result — see [constant DIM_INKS].
##
## The rows are set EXTERNALLY ([member entries]) before add_child, like every sibling picker:
## this class renders and PARTITIONS them into the four tabs by the ROM's own ability-id
## ranges (§8), but computes no costs and reads no progression.
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

# -----------------------------------------------------------------------------
# Panels
# -----------------------------------------------------------------------------
## The TOP panel — the ROM template rect is `(33,41) 196x20` (`0x8018D2FC`, §3.1). The port
## rect carries the SAME chrome offset [JobPickerMenu] converged on over rounds 10–16: the
## STRIPE frame's fixed top chrome is 9 px, so the rect starts above the ROM's fill top, and
## the 9-slice art overhangs the template rect (§21) which is why the width is 203, not 196.
##
## The vertical span is MEASURED, not derived: the settled ROM framebuffer
## (`ss0_ss1_ss2_ss3_montage.png`, bottom-right quadrant) renders this panel's chrome over
## **y31..66**, because its own 9-slice art overhangs the template rect by 10 px top and 6 px
## bottom. Reading the template as the drawn rect puts the panel 4 px short at the bottom —
## which is exactly what the first build did. The height then carries a further +2 because
## the port's own STRIPE art stops 2 px inside the rect it is sized to; both numbers were
## dialled by scanning the rendered panel edge against the ROM's, not by arithmetic.
const TOP_PANEL := Rect2(29.0, 31.0, 203.0, 38.0)

## The BOTTOM panel — ROM template `(33,86) 196x132` (`0x8018D3B9`, §3.1), through the same
## offset. This one is the direct analogue of the job picker's single panel: a scrolling row
## list with its column headers STRADDLING the panel's top edge, 13 px above the ROM fill top
## in both screens (job picker: headers y26 over fill y39; here: headers y73 over fill y86).
## Vertical span measured off the same settled framebuffer: the ROM draws it over **y76..223**.
const BOTTOM_PANEL := Rect2(29.0, 76.0, 203.0, 150.0)

## Eight visible rows, 16 px pitch — `s16` header `0x8018D467` rec[6]=0x08, rec[5]=0x10 (§5.2),
## live-confirmed (`0x801C9E90 = 8`, `0x801C9E94 = 16`, §13.1). Longer lists scroll.
const VISIBLE_ROWS := 8
const ROW_PITCH := 16.0

## Row-0 text top (display px) — the ROM's row sub-block draws its cells at y=91 (§5.2's
## dash/`Learned` cells and all three `s13` records), one below the `s16` strip y=90 (rec[8]).
## The job picker resolves the same 1 px the same way (strip 43 → text 44).
const ROW0_TEXT_Y := 91.0

## The TOP frame's single row — the ROM's `s13` records and the separator glyph all sit at
## y=46 (§3.2). The job NAME blit is at y=45; the port mounts name and digits on ONE y, as
## the job picker does, because FONT.BIN ink and the digit strip pad differently.
const TOP_ROW_Y := 46.0

# -----------------------------------------------------------------------------
# Column headers — baked `assets/ui/frame.tga` word cells under the cream CLUT 0x7CBC,
# the same mechanism [JobPickerMenu] uses (round 9/10). Template uv bytes are RANGETILE
# coordinates and `frame.tga row = RANGETILE row + 32` (§4), which is already folded into
# every `cell` below. All eleven cells were cropped out of the sheet and LOOKED AT before
# they were baked here — the montage reads `Job Lv. Total Next Jp Ability Mp Speed Master!`,
# the squiggle, and `Learned`.
# -----------------------------------------------------------------------------
## TOP frame headers, screen y=28 (§3.2). The five cells are shared with [JobPickerMenu] —
## same words, same sheet rects, already visually verified there — so they are copied rather
## than re-derived from the ROM's 1-px-tighter template uv sizes.
const TOP_HEADER_CELLS := [
	{"name": "Job",   "cell": Rect2i(22, 32, 17, 8),   "x": 38.0},
	{"name": "Lv.",   "cell": Rect2i(49, 48, 14, 8),   "x": 119.0},
	{"name": "Total", "cell": Rect2i(0, 152, 22, 8),   "x": 143.0},
	{"name": "Next",  "cell": Rect2i(24, 152, 21, 8),  "x": 174.0},
	{"name": "Jp",    "cell": Rect2i(228, 64, 12, 10), "x": 208.0},
]
const TOP_HEADER_Y := 28.0

## BOTTOM frame headers, screen y=73 (§3.3). `Ability`/`Mp`/`Speed` are the three cells §4
## found already parsed in `RANGETILE.json` under `window_tabs`/`word_labels`/`stat_labels`
## — the user's open question "which sheet are Mp and Speed on?" answered: the same one.
const BOTTOM_HEADER_CELLS := [
	{"name": "Ability", "cell": Rect2i(0, 64, 26, 10),   "x": 37.0},
	{"name": "Mp",      "cell": Rect2i(184, 64, 16, 9),  "x": 135.0},
	{"name": "Speed",   "cell": Rect2i(176, 176, 26, 10), "x": 160.0},
	{"name": "Jp",      "cell": Rect2i(228, 64, 12, 10), "x": 205.0},
]
const BOTTOM_HEADER_Y := 73.0

## The four ability-TYPE tab icons, in template order — bolt / arrow / Ω / boot, read off
## RANGETILE at the template's own uv and size (§3.3/§4) and cropped-and-looked-at before
## baking. All four ALWAYS draw: each is preceded by a two-way PALETTE pick, not a visibility
## gate, so the current tab's icon is gold-lit and the other three are grey-blue (§13.3).
const TAB_ICONS := [
	{"cell": Rect2(136, 0, 10, 14),  "x": 67.0},
	{"cell": Rect2(148, 0, 10, 14),  "x": 82.0},
	{"cell": Rect2(136, 17, 14, 14), "x": 97.0},
	{"cell": Rect2(152, 17, 14, 14), "x": 116.0},
]
const TAB_ICON_Y := 70.0

## Which ability ids belong to which tab — the ROM's OWN partition, read out of
## `FUN_801228F0` (§8): the candidate builder zeroes every id outside the selected tab's
## range. Verified against the port's data this session: every one of the port's 32 Reaction
## records falls in `[0x1A6,0x1C5]`, all 32 Support in `[0x1C6,0x1E5]`, all 24 Movement in
## `[0x1E6,0x1FD]`, and everything else in the action range — zero exceptions. So the id range
## and [LearnableAbility]'s `category` are the same partition, and the id range is the ROM's.
const TAB_RANGES := [
	[0x001, 0x1A5],   # 0 Action
	[0x1A6, 0x1C5],   # 1 Reaction
	[0x1C6, 0x1E5],   # 2 Support
	[0x1E6, 0x1FD],   # 3 Movement
]
const TAB_COUNT := 4

# -----------------------------------------------------------------------------
# Row + top-frame columns. `x` is the ROM's `s13` BASE X, not a centre: `place_number`
# puts the first glyph CELL at the mount x, which is exactly what the record's base-x
# addresses. (The job picker reaches the same pixels the long way round, centring on the
# header and asserting the result equals the base-x — LEARN_PICKER.md §16.3.)
#
# `digits` is the record's `maxd`. Leading positions are NOT skipped: every `s13` here is
# type `0x0D`, which takes neither the blank (`0x19`) nor the dim-leading (`0x1A`) branch, so
# the ROM draws literal `0` glyphs in the SAME colour as the significant digits (§6.3) —
# `0300`, `0150`, `00`, exactly as the settled framebuffer reads.
# -----------------------------------------------------------------------------
## TOP frame columns (§3.2) — prov[0]=Lv, prov[1]=Total, prov[2]=Next, prov[3]=Jp.
const TOP_COLUMNS := [
	{"key": "lv",    "x": 123.0, "digits": 1},
	{"key": "total", "x": 143.0, "digits": 4},
	{"key": "next",  "x": 173.0, "digits": 4},
	{"key": "jp",    "x": 203.0, "digits": 4},
]

## The `/` between Lv. and Total — a STATIC quad in the template (`0x8018D34E`: x=137, y=46,
## 6x11, uv (180,16) = cell 10 of the digit strip `0123456789/-`). Chrome, not a divider.
const TOP_SEPARATOR_X := 137.0

## The job NAME's x — the ROM rasterises it to VRAM and blits one 80-px strip at x=38 (§5.1),
## sitting exactly under the `Job` header. The port draws FONT.BIN text at the same x.
const TOP_NAME_X := 38.0

## `Master!` — the top frame's `s2` gate on prov[5] (§3.2 @007F): uv (216,120) 34x9 drawn at
## (187,46), with a gold STAR sprite (RANGETILE (48,0) 10x10) at (177,44). Both were cropped
## and looked at. When the gate passes these REPLACE the Next and Jp columns (they are the
## gate's n1 branch; the two `s13` records are its n2 branch).
const MASTER_CELL := Rect2i(216, 152, 34, 9)
const MASTER_X := 187.0
const MASTER_STAR_CELL := Rect2(48, 0, 10, 10)
const MASTER_STAR_POS := Vector2(177.0, 44.0)

## The ability NAME column — `s16` rec[7]=0x26 (§5.2), an 80-px strip at x=38 under the
## left-aligned `Ability` header.
const NAME_X := 38.0

## The row's two number columns (§5.2's `s13` records at `0x8018D4A9` / `0x8018D4B3`):
## MP `maxd=2` at base x 136, Speed `maxd=2` at base x 167.
const ROW_MP_X := 136.0
const ROW_SPEED_X := 167.0

## The JP column, `maxd=4` at base x 199 (`0x8018D4D5`) — the FALSE branch of the row's
## prov[6] gate. TRUE draws the `Learned` cell instead, uv (216,208) 38x8 at (191,91).
const ROW_JP_X := 199.0
const LEARNED_CELL := Rect2i(216, 240, 38, 8)
const LEARNED_X := 191.0

## The dash cell — uv (216,132) 39x10 at (142,91), a decorative squiggle spanning the Mp AND
## Speed columns. Drawn INSTEAD of the two number columns whenever the ability is not an
## ACTION ability, which §14.3 shows is structural rather than incidental: `func_0x8005A72C`
## hands back a 14-byte extension record for action abilities and a 1–2 byte one for every
## other type, so a Reaction/Support/Movement ability has no MP or Speed FIELD to print.
## Driving it off the id range is therefore right, and "is mp_cost zero" would be wrong.
const DASH_CELL := Rect2i(216, 164, 39, 10)
const DASH_X := 142.0

## The cursor + row region. Derived exactly as [JobPickerMenu.ROWS_CONTAINER] is: the ROM's
## row arrow sits at strip x − rec[11] = 38 − 16 = 22 (§5.2), the lit glove at screen x20, and
## `StartActionMenu.cursor_display_pos_in` places it at `c.x − CURSOR_X_BIAS(12)` → c.x = 32.
## `c.y = strip y − CURSOR_Y_OFFSET(10)` = 90 − 10 = 80, which puts row-0 text at
## `c.y + 11 = 91` — [constant ROW0_TEXT_Y], as it must.
const ROWS_CONTAINER := Rect2i(32, 80, 199, 128)

const RP_BASE := 40
const RP_FRAME := 46
const RP_ROW_TEXT := 49
const RP_HEADER := 50
const RP_CURSOR_SHADOW := 51
const RP_CURSOR_LIT := 52

const _BOB_TICK := 1.0 / 60.0

# -----------------------------------------------------------------------------
# Palettes — the four CLUTs this screen samples, read straight out of
# `reference-assets/learn_ability_ss3_settled.sstate` with
# `learn_ability_captures/sstate_mine.py` (no emulator; the savestate carries all 1 MiB of
# VRAM). §13.1's live globals name them: `cd1bc=7C3C cd1f8=7CBC cd870=7FA4 cd5d8=7FFC`.
# -----------------------------------------------------------------------------
## The DISABLED ink triple — CLUT `0x7FA4` indices 1/2/3, which are byte-identical to CLUT
## `0x7FFC` indices 5/6/7. That identity is the finding: §7's two mechanisms (the numbers
## swap palette, the name shifts shade band) resolve to ONE painted colour ramp, so the
## whole disabled state is this one constant applied through two different code paths.
const DIM_INKS: Array[Color] = [
	Color8(99, 90, 74, 255),
	Color8(115, 107, 90, 255),
	Color8(140, 132, 115, 255),
]

## The ENABLED ink triple — CLUT `0x7C3C` indices 1/2/3. Identical (to 5-bit rounding) to
## `UIUnitNameplate.INFO_INK_*`, which is the port's existing menu-text ramp, and to
## `FrameCellAtlas.PALETTE0[1..3]`. Named here so the guard can pair it with [constant DIM_INKS].
const LIT_INKS: Array[Color] = [
	Color8(49, 41, 33, 255),
	Color8(82, 82, 66, 255),
	Color8(132, 123, 107, 255),
]

## CLUT `0x7FA4` in full — the DISABLED palette for the frame-cell quads (the dash squiggle).
## Note indices 4/8/12–15 are transparent here where `0x7C3C` has tan: a dimmed cell loses its
## baked tan background and reads as bare grey ink on the panel, which is what the tab-1
## capture shows.
const CLUT_7FA4: Array[Color] = [
	Color8(0, 0, 0, 0), Color8(99, 90, 74, 255), Color8(115, 107, 90, 255), Color8(140, 132, 115, 255),
	Color8(0, 0, 0, 0), Color8(107, 41, 16, 255), Color8(123, 74, 57, 255), Color8(140, 123, 107, 255),
	Color8(0, 0, 0, 0), Color8(33, 24, 16, 255), Color8(115, 107, 82, 255), Color8(214, 206, 173, 255),
	Color8(0, 0, 0, 0), Color8(0, 0, 0, 0), Color8(0, 0, 0, 0), Color8(0, 0, 0, 0),
]

## CLUT `0x7E7C` — the tab icon's LIT palette (`s2` TRUE branch, `01 3C F9`). Gold: index 2 is
## near-white and 12–15 walk up through amber. §13.3 saw the current tab gold and the other
## three grey, which is what picks this word as the TRUE branch (closing §3.3's open G3).
const CLUT_7E7C: Array[Color] = [
	Color8(0, 0, 0, 0), Color8(66, 66, 41, 255), Color8(255, 255, 239, 255), Color8(132, 132, 115, 255),
	Color8(173, 173, 132, 255), Color8(206, 206, 140, 255), Color8(247, 247, 181, 255), Color8(16, 8, 0, 255),
	Color8(33, 16, 0, 255), Color8(49, 24, 8, 255), Color8(66, 33, 16, 255), Color8(99, 57, 24, 255),
	Color8(165, 90, 33, 255), Color8(189, 123, 49, 255), Color8(214, 156, 66, 255), Color8(231, 206, 115, 255),
]

## CLUT `0x7EBC` — the tab icon's DIM palette (`s2` FALSE branch, `01 3C FA`). Blue-grey.
const CLUT_7EBC: Array[Color] = [
	Color8(0, 0, 0, 0), Color8(41, 41, 33, 255), Color8(140, 148, 165, 255), Color8(66, 74, 82, 255),
	Color8(74, 90, 99, 255), Color8(90, 107, 115, 255), Color8(107, 123, 140, 255), Color8(148, 49, 33, 255),
	Color8(148, 49, 33, 255), Color8(181, 66, 41, 255), Color8(231, 90, 41, 255), Color8(41, 41, 33, 255),
	Color8(57, 66, 57, 255), Color8(82, 90, 90, 255), Color8(107, 115, 115, 255), Color8(132, 140, 148, 255),
]

# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------
## Emitted on ○ over a LEARNABLE row — the host spends the JP and commits.
signal chosen(entry_index: int)
## Emitted on ○ over a row the ROM refuses: already learned (`bacc = 5`) or unaffordable
## (`FUN_801134E8(0xC009,0x30)`). §9's three-way confirm, minus the branch that commits.
signal refused(entry_index: int)
## Emitted whenever the highlight moves.
signal selection_changed(entry_index: int)
## Emitted on × — the host closes back to the job picker (§13.5: the ROM rebuilds the job
## picker and replays ITS aperture open from stage 1).
signal cancelled
## Re-emitted once both panels have finished closing.
signal closed
## Emitted when LEFT/RIGHT step the tab (§9).
signal tab_changed(tab: int)

# -----------------------------------------------------------------------------
# Host-set payload
# -----------------------------------------------------------------------------
## Every learnable ability of the picked job, in the database's own order — which this
## session verified reproduces the ROM's candidate array exactly for Squire: the port yields
## `092 093 094 095 | 1B4 | 1CC 1DE 1DF 1CF | 1E6`, and §13.3's live tabs read
## `4092 1093 1094 4095 | 41B4 | 41CC 41DE 41DF 41CF | 41E6`. Same ids, same order, per tab.
##
## Each entry: `{id:int, name:String, mp:int, speed:int, jp:int, learned:bool, affordable:bool}`.
## `speed` is already `ceil(100 / ct)` — see [method speed_from_ct]; the host applies it so
## this class stays a renderer.
var entries: Array = []

## The top frame's one row: `{name, lv, total, next, jp, mastered}`. `mastered` is the port's
## reading of prov[5] (`DAT_801C85D4`, §6) — every learnable of the job already learned.
var job_summary: Dictionary = {}

## Play the box-open on _ready (host may disable to boot settled).
@export var autoplay_open: bool = true
@export var fast: bool = false

var _atlas: RangeTileAtlas
var _menu_text: UIMenuText
var _top_window: UI3Element
var _bot_window: UI3Element
var _top_header_elem: UI3Element
var _top_row_elem: UI3Element
var _bot_header_elem: UI3Element
var _rows_elem: UI3Element
var _cursor_elem: UI3Element

var _lit_pal: ImageTexture       # 0x7C3C — enabled numbers + enabled frame cells
var _dim_pal: ImageTexture       # 0x7FA4 — disabled numbers + disabled frame cells
var _header_pal: ImageTexture    # 0x7CBC — the cream column headers
var _tab_lit_pal: ImageTexture   # 0x7E7C — the selected tab's icon
var _tab_dim_pal: ImageTexture   # 0x7EBC — the other three
var _star_pal: ImageTexture      # the Master! star (RANGETILE ability-icon CLUT)
var _glove_lit_pal: ImageTexture
var _glove_shadow_pal: ImageTexture

# Guard seams.
var _row_text_mats: Array[ShaderMaterial] = []
var _row_number_mats: Array[ShaderMaterial] = []
var _row_cell_mats: Array[ShaderMaterial] = []
var _top_mats: Array[ShaderMaterial] = []
var _header_cell_mats: Array[ShaderMaterial] = []
var _tab_icon_mats: Array[ShaderMaterial] = []
var _cursor_mats: Array[ShaderMaterial] = []
var _visible_names: Array[String] = []
var _visible_columns: Array = []
var _visible_dim: Array[bool] = []
var _content_built := false

# Glove cursor holders + bob (§15.20 / ADR-0046).
var _lit_holder: Node3D
var _shadow_holder: Node3D
var _bob_frame: int = 0
var _bob_accum: float = 0.0
var _moving_frames: int = 0
var _idle_pairs: Array = []
var _select_pairs: Array = []

## The four tabs' row lists — indices into [member entries], built once by [method _partition].
var _tab_rows: Array = [[], [], [], []]
var _tab := 0
## Per-tab cursor + scroll. The ROM saves and restores these across a tab change through the
## shared 6-byte picker records 10..13 (`FUN_80118BA4`/`FUN_80118BF0`, §9) — which is why its
## build block memsets exactly four of them, one per tab. §13.3 read all four back live.
var _tab_row: Array[int] = [0, 0, 0, 0]
var _tab_scroll: Array[int] = [0, 0, 0, 0]

var _open_windows := 0
var _closing := false


func _ready() -> void:
	_atlas = RangeTileAtlas.new()
	_menu_text = UIMenuText.new()
	_lit_pal = _palette_from_colors(FrameCellAtlas.PALETTE0)
	_dim_pal = _palette_from_colors(CLUT_7FA4)
	_header_pal = _palette_from_colors(_atlas.window_tab_colors())
	_tab_lit_pal = _palette_from_colors(CLUT_7E7C)
	_tab_dim_pal = _palette_from_colors(CLUT_7EBC)
	_star_pal = _palette_from_colors(_atlas.ability_icon_palette_colors())
	_glove_lit_pal = _palette_from_colors(_atlas.menu_glove_lit_colors())
	_glove_shadow_pal = _palette_from_colors(_atlas.menu_glove_shadow_colors())
	_idle_pairs = GloveCursorBob.load_glove_pairs("glove_idle")
	_select_pairs = GloveCursorBob.load_glove_pairs("glove_select")
	_partition()
	_build_windows()
	_build_content()
	if autoplay_open:
		play_open()
	_place_cursor()


## Re-derive everything from a freshly-written [member entries] / [member job_summary], in
## place. The ROM does this after every commit and every refused ○ (§9: "either way the
## candidate list is rebuilt and the cursor re-seated"), which is how the row the player just
## learned flips to `Learned` without the screen closing. The cursor is deliberately kept:
## a commit changes a row's FLAGS, never the row set, so re-seating it would be a jump the
## player did not ask for.
func rebuild() -> void:
	_partition()
	for t in TAB_COUNT:
		var n := (_tab_rows[t] as Array).size()
		_tab_row[t] = clampi(_tab_row[t], 0, maxi(0, n - 1))
		_tab_scroll[t] = clampi(_tab_scroll[t], 0, maxi(0, n - VISIBLE_ROWS))
	if _content_built:
		_build_content()
	_place_cursor()


## Split [member entries] across the four tabs by the ROM's ability-id ranges (§8). Order
## within a tab is the order the host handed them over, which is the skillset slot order the
## ROM's candidate builder walks.
func _partition() -> void:
	_tab_rows = [[], [], [], []]
	for i in entries.size():
		var t := tab_for_id(int((entries[i] as Dictionary).get("id", 0)))
		if t >= 0:
			(_tab_rows[t] as Array).append(i)


## Which tab an ability id belongs to, or −1 for an id outside all four ranges (the ROM's
## candidate builder zeroes those out of the array entirely).
static func tab_for_id(id: int) -> int:
	for t in TAB_COUNT:
		var r: Array = TAB_RANGES[t]
		if id >= int(r[0]) and id <= int(r[1]):
			return t
	return -1


## The Speed column's value: `ceil(100 / ct)`, the ROM's prov[8]
## (`0x8011F494`: `ori v1,zero,0x64; div v1,a0`, then +1 on a remainder). `ct == 0` returns
## 0 rather than dividing — the R3000A leaves `LO = −1, HI = rs` on a zero divisor, so
## `LO + (HI != 0)` is 0 and the ROM prints `00` with no special case (§13.4). Round 4's
## positive control pinned the formula: ability `0x0B` has `ct = 4` and rendered `25`.
static func speed_from_ct(ct: int) -> int:
	if ct <= 0:
		return 0
	return (100 + ct - 1) / ct


## True when the row draws the dash squiggle instead of MP/Speed digits — every ability
## outside the ACTION id range (§14.3: those records have no MP/Speed field at all).
static func is_dash_row(id: int) -> bool:
	return tab_for_id(id) != 0


# -----------------------------------------------------------------------------
# Windows
# -----------------------------------------------------------------------------
func _build_windows() -> void:
	_top_window = _make_panel("learnability.top", TOP_PANEL)
	_bot_window = _make_panel("learnability.bottom", BOTTOM_PANEL)

	# The top frame's five cream headers, straddling its top edge.
	_top_header_elem = _make_child(_top_window, "learnability.top.header",
		Rect2(TOP_HEADER_CELLS[0]["x"], TOP_HEADER_Y,
			_header_span(TOP_HEADER_CELLS), 10.0))
	# The top frame's one summary row.
	_top_row_elem = _make_child(_top_window, "learnability.top.row",
		Rect2(TOP_NAME_X, TOP_ROW_Y, 203.0 - TOP_NAME_X, ROW_PITCH))

	# The bottom frame's four headers + four tab icons — one element, since the icons sit on
	# the same straddling row and ride the same aperture.
	_bot_header_elem = _make_child(_bot_window, "learnability.bottom.header",
		Rect2(BOTTOM_HEADER_CELLS[0]["x"], TAB_ICON_Y,
			_header_span(BOTTOM_HEADER_CELLS), 14.0))
	# The list assembly: ONE element, rows placed from rect.y by `pitch`.
	_rows_elem = _make_child(_bot_window, "learnability.rows",
		Rect2(29.0, ROW0_TEXT_Y, 203.0, VISIBLE_ROWS * ROW_PITCH),
		{"pitch": ROW_PITCH, "name_x": NAME_X})

	# The glove pokes off the panel's LEFT edge, outside the box-open scissor — a DECLARED
	# Clip.UNCLIPPED, exactly as the sibling pickers answer it.
	_cursor_elem = UI3Element.new({
		"id": "learnability.cursor",
		"rect": BOTTOM_PANEL,
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_cursor_elem.name = "LearnAbilityGloveCursor"
	_bot_window.add_child(_cursor_elem)


## One aperture panel. Both are identical apart from their rect — that is the point: the ROM
## drives them from a single stage counter, so anything that could make them diverge (a
## different cadence, a different pad) is a bug waiting to happen (§3.4).
func _make_panel(id: String, rect: Rect2) -> UI3Element:
	var e := UI3Element.new({
		"id": id,
		"rect": rect,
		"authored_home": rect.position,
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.STRIPE,
		"frame_center_patch": Vector4(6, 7, 21, 17),
		"frame_rp": RP_FRAME,
		"clip": UI3Element.Clip.OWN_APERTURE,
		# The column headers straddle the panel's top edge, so the box the open plays over
		# must enclose them (ADR-0088 amendment §4) — same 9 px the job picker pads by.
		"aperture_pad": Vector4(0, 9, 0, 0),
		"depth_rung": -6,
		# ADR-0097 §2: one cadence per VERB. Both panels take the SAME pair, which is what
		# keeps them in lockstep.
		"open_cadence": UI3BoxOpenBeat.Cadence.FAST if fast else UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
	})
	add_child(e)
	e.opened.connect(_on_window_settled)
	e.closed.connect(_on_window_settled)
	return e


func _make_child(parent: UI3Element, id: String, rect: Rect2, extra: Dictionary = {}) -> UI3Element:
	var spec := {
		"id": id,
		"rect": rect,
		"authored_home": rect.position,
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	}
	spec.merge(extra)
	var e := UI3Element.new(spec)
	parent.add_child(e)
	return e


static func _header_span(cells: Array) -> float:
	var last: Dictionary = cells[cells.size() - 1]
	return float(last["x"]) + float((last["cell"] as Rect2i).size.x) - float((cells[0] as Dictionary)["x"])


# -----------------------------------------------------------------------------
# Content
# -----------------------------------------------------------------------------
func _build_content() -> void:
	for e: UI3Element in [_top_header_elem, _top_row_elem, _bot_header_elem, _rows_elem, _cursor_elem]:
		for c in e.get_children():
			c.free()   # synchronous, mirroring the sibling pickers' scrub rebuild
	_row_text_mats.clear()
	_row_number_mats.clear()
	_row_cell_mats.clear()
	_top_mats.clear()
	_header_cell_mats.clear()
	_tab_icon_mats.clear()
	_cursor_mats.clear()
	_visible_names.clear()
	_visible_columns.clear()
	_visible_dim.clear()
	_lit_holder = null
	_shadow_holder = null

	_build_headers()
	_build_top_row()
	_build_tab_icons()
	_build_rows()
	_build_cursor()
	_content_built = true


## The nine cream column headers across both frames — baked frame.tga word cells sampled as
## 4bpp INDEX bitmaps through CLUT 0x7CBC. The inversion is the point: the sheet bakes these
## words dark-on-tan and 0x7CBC maps ink index 1 to cream, which is the cream-on-dark header
## row the ROM draws straddling each panel's bevel.
func _build_headers() -> void:
	for h in TOP_HEADER_CELLS:
		_mount_cell(_top_header_elem, h["cell"], float(h["x"]), TOP_HEADER_Y, _header_pal,
			RP_HEADER, _header_cell_mats)
	for h in BOTTOM_HEADER_CELLS:
		_mount_cell(_bot_header_elem, h["cell"], float(h["x"]), BOTTOM_HEADER_Y, _header_pal,
			RP_HEADER, _header_cell_mats)


## The top frame's one row: the job NAME, then Lv. `/` Total / Next / Jp — or, when the job is
## mastered, the star + `Master!` in place of the Next and Jp columns (§3.2's `s2` gate).
func _build_top_row() -> void:
	var s := _top_row_elem
	var nm := String(job_summary.get("name", ""))
	_menu_text.mount(s, nm, s.rel_world(TOP_NAME_X, TOP_ROW_Y) + s.z_for(RP_ROW_TEXT),
		RP_ROW_TEXT, s.ppu(), _top_mats, LIT_INKS)
	_menu_text.mount_number(s, "/", s.rel_world(TOP_SEPARATOR_X, TOP_ROW_Y) + s.z_for(RP_ROW_TEXT),
		RP_ROW_TEXT, s.ppu(), _lit_pal, _top_mats)
	var mastered := bool(job_summary.get("mastered", false))
	for c in TOP_COLUMNS:
		var key := String(c["key"])
		if mastered and (key == "next" or key == "jp"):
			continue   # the gate's n1 branch replaces both columns with Master!
		_menu_text.mount_number(s, _padded(int(job_summary.get(key, 0)), int(c["digits"])),
			s.rel_world(float(c["x"]), TOP_ROW_Y) + s.z_for(RP_ROW_TEXT),
			RP_ROW_TEXT, s.ppu(), _lit_pal, _top_mats)
	if mastered:
		_mount_cell(s, MASTER_CELL, MASTER_X, TOP_ROW_Y, _lit_pal, RP_ROW_TEXT, _top_mats)
		_mount_sprite(s, MASTER_STAR_CELL, MASTER_STAR_POS.x, MASTER_STAR_POS.y, _star_pal,
			RP_ROW_TEXT, _top_mats)


## The four tab icons. All four ALWAYS draw — the template gates each on a PALETTE pick, not
## on visibility (§3.3) — so the current tab is gold and the other three grey-blue.
func _build_tab_icons() -> void:
	for t in TAB_COUNT:
		var ic: Dictionary = TAB_ICONS[t]
		var pal := _tab_lit_pal if t == _tab else _tab_dim_pal
		_mount_sprite(_bot_header_elem, ic["cell"], float(ic["x"]), TAB_ICON_Y, pal,
			RP_HEADER, _tab_icon_mats)


## One row per visible entry of the CURRENT tab. Three shapes, all driven off one flag and
## one id (§5.2/§7/§14.3):
##   name  — FONT.BIN text, [constant LIT_INKS] or [constant DIM_INKS] (the shade-band swap);
##   Mp/Speed — two 2-digit columns for an ACTION ability, else the dash squiggle;
##   Jp    — a 4-digit column, or the `Learned` cell when the unit already has it.
func _build_rows() -> void:
	var s := _rows_elem
	var rows: Array = _tab_rows[_tab]
	var scroll := _tab_scroll[_tab]
	var row0_y := s.authored_home().y
	for i in range(scroll, mini(rows.size(), scroll + VISIBLE_ROWS)):
		var e: Dictionary = entries[int(rows[i])]
		var y := row0_y + (i - scroll) * ROW_PITCH
		var id := int(e.get("id", 0))
		var learned := bool(e.get("learned", false))
		# The ROM's candidate bitfield: bit 12 = already learned (drawn ENABLED, with the
		# `Learned` cell), bits 14–15 = unaffordable → both dim mechanisms fire (§8).
		var dim := not learned and not bool(e.get("affordable", false))
		var pal := _dim_pal if dim else _lit_pal
		var inks := DIM_INKS if dim else LIT_INKS

		var nm := String(e.get("name", ""))
		_menu_text.mount(s, nm, s.rel_world(NAME_X, y) + s.z_for(RP_ROW_TEXT),
			RP_ROW_TEXT, s.ppu(), _row_text_mats, inks)

		var cols: Array = []
		if is_dash_row(id):
			_mount_cell(s, DASH_CELL, DASH_X, y, pal, RP_ROW_TEXT, _row_cell_mats)
			cols.append("-")
			cols.append("-")
		else:
			var mp := _padded(int(e.get("mp", 0)), 2)
			var sp := _padded(int(e.get("speed", 0)), 2)
			_menu_text.mount_number(s, mp, s.rel_world(ROW_MP_X, y) + s.z_for(RP_ROW_TEXT),
				RP_ROW_TEXT, s.ppu(), pal, _row_number_mats)
			_menu_text.mount_number(s, sp, s.rel_world(ROW_SPEED_X, y) + s.z_for(RP_ROW_TEXT),
				RP_ROW_TEXT, s.ppu(), pal, _row_number_mats)
			cols.append(mp)
			cols.append(sp)

		if learned:
			_mount_cell(s, LEARNED_CELL, LEARNED_X, y, pal, RP_ROW_TEXT, _row_cell_mats)
			cols.append("Learned")
		else:
			var jp := _padded(int(e.get("jp", 0)), 4)
			_menu_text.mount_number(s, jp, s.rel_world(ROW_JP_X, y) + s.z_for(RP_ROW_TEXT),
				RP_ROW_TEXT, s.ppu(), pal, _row_number_mats)
			cols.append(jp)

		_visible_names.append(nm)
		_visible_columns.append(cols)
		_visible_dim.append(dim)


## Zero-pad to the record's `maxd`. Over-wide values run long rather than losing a digit —
## the ROM's loop would draw only `maxd` cells, but every reachable figure is far under the
## field width and silently dropping a digit reads as a rendering bug (the job picker's
## `_column_text` carries the same reasoning).
static func _padded(value: int, digits: int) -> String:
	return str(maxi(0, value)).pad_zeros(digits)


func _build_cursor() -> void:
	_shadow_holder = _mount_glove(_atlas.menu_glove_shadow_rect(), _glove_shadow_pal,
		_SHADOW_SHADER, RP_CURSOR_SHADOW)
	_lit_holder = _mount_glove(_atlas.menu_glove_lit_rect(), _glove_lit_pal,
		_SPRITE_SHADER, RP_CURSOR_LIT)
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
	var mat := _cell_mat(_atlas.texture, cell, palette, shader_path, rung)
	if folded:
		mat.shader = _SHADOW_FOLD_SHADER   # preloaded Shader (ADR-0191 dec. 2)
	_cursor_mats.append(mat)
	var mi := _quad(cell.size)
	mi.material_override = mat
	mi.position += _bot_window.z_for(rung)
	holder.add_child(mi)
	if folded:
		Fold.add(mi, mat, DepthMode.rung_z(rung))
	return holder


# -----------------------------------------------------------------------------
# Row model + navigation
# -----------------------------------------------------------------------------
## The current tab (0..3).
func tab() -> int:
	return _tab


## The visible row index within the current tab.
func selected_row() -> int:
	return _tab_row[_tab]


## The index into [member entries] the cursor is on, or −1 when the tab is empty.
func selected_entry() -> int:
	var rows: Array = _tab_rows[_tab]
	if rows.is_empty():
		return -1
	return int(rows[_tab_row[_tab]])


func row_count() -> int:
	return (_tab_rows[_tab] as Array).size()


func scroll() -> int:
	return _tab_scroll[_tab]


func move_down() -> void:
	var n := row_count()
	if n == 0:
		return
	_tab_row[_tab] = (_tab_row[_tab] + 1) % n
	_on_selection_moved()


func move_up() -> void:
	var n := row_count()
	if n == 0:
		return
	_tab_row[_tab] = (_tab_row[_tab] - 1 + n) % n
	_on_selection_moved()


## LEFT — the previous tab, wrapping 0 → 3 (`FUN_8012BA7C` input bit `0x8000`, §9).
func tab_prev() -> void:
	_set_tab((_tab - 1 + TAB_COUNT) % TAB_COUNT)


## RIGHT — the next tab, wrapping 3 → 0 (input bit `0x2000`, §9).
func tab_next() -> void:
	_set_tab((_tab + 1) % TAB_COUNT)


## Switch tabs, keeping each tab's own cursor. The ROM writes the outgoing tab's 6-byte record
## and reads the incoming one (`FUN_80118BA4`/`FUN_80118BF0` on records tab+10, §9) — here the
## cursor simply lives per tab, which is the same observable behaviour §13.3 read back live.
func _set_tab(t: int) -> void:
	if t == _tab:
		return
	_tab = t
	_moving_frames = GloveCursorBob.glove_period(_select_pairs)
	_bob_frame = 0
	if _content_built:
		_build_content()
	_place_cursor()
	tab_changed.emit(_tab)
	selection_changed.emit(selected_entry())


func _on_selection_moved() -> void:
	_moving_frames = GloveCursorBob.glove_period(_select_pairs)
	_bob_frame = 0
	var row := _tab_row[_tab]
	var new_scroll := _tab_scroll[_tab]
	if row < new_scroll:
		new_scroll = row
	elif row >= new_scroll + VISIBLE_ROWS:
		new_scroll = row - VISIBLE_ROWS + 1
	if new_scroll != _tab_scroll[_tab]:
		_tab_scroll[_tab] = new_scroll
		if _content_built:
			_build_content()
	_place_cursor()
	selection_changed.emit(selected_entry())


## ○ — the ROM's three-way (§9): an unaffordable row (`entry >> 14 != 0`) buzzes
## `FUN_801134E8(0xC009,0x30)`, an already-learned row sets `bacc = 5` and does nothing, and
## anything else commits. The ROM's third branch opens a Yes/No confirmation (window 6,
## `FUN_8012AB78(6, &DAT_8018D280)`) BEFORE spending the JP; the port commits directly, as
## every other picker in this screen family does, and this is the seam that dialog would be
## added at. `0x8018D280` has never been walked — there is no measured geometry for it.
func confirm() -> void:
	var idx := selected_entry()
	if idx < 0:
		return
	var e: Dictionary = entries[idx]
	if bool(e.get("learned", false)) or not bool(e.get("affordable", false)):
		refused.emit(idx)
		return
	chosen.emit(idx)


func cancel() -> void:
	cancelled.emit()


# -----------------------------------------------------------------------------
# Aperture
# -----------------------------------------------------------------------------
## Open BOTH panels on the same frame at the same cadence — the template's single `s22`
## record means one stage counter drives both, and §13.2 measured them at the SAME scale in
## the same frame on both axes (G2 closed).
func play_open(cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	if _cursor_elem != null and is_instance_valid(_cursor_elem):
		_cursor_elem.visible = true
	_closing = false
	_open_windows = 0
	for w: UI3Element in [_top_window, _bot_window]:
		if w != null and is_instance_valid(w):
			_open_windows += 1
			w.open(cadence)


func play_close(cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	if _cursor_elem != null and is_instance_valid(_cursor_elem):
		_cursor_elem.visible = false   # focus has already left
	_closing = true
	_open_windows = 0
	for w: UI3Element in [_top_window, _bot_window]:
		if w != null and is_instance_valid(w):
			_open_windows += 1
			w.close(cadence)


## Both panels settle on the same frame, but each element emits its own `opened`/`closed`.
## Count them down so `closed` fires ONCE, after the second — a host that restored on the
## first would restore over a still-open panel.
func _on_window_settled() -> void:
	_open_windows -= 1
	if _open_windows > 0:
		return
	if _closing:
		_closing = false
		closed.emit()


func top_window() -> UI3Element:
	return _top_window


func bottom_window() -> UI3Element:
	return _bot_window


# -----------------------------------------------------------------------------
# Glove cursor placement + bob
# -----------------------------------------------------------------------------
static func cursor_anchor_for(row: int) -> Vector2:
	return StartActionMenu.cursor_display_pos_in(ROWS_CONTAINER, row, 0)


func cursor_bob_x() -> int:
	var pairs := _select_pairs if _moving_frames > 0 else _idle_pairs
	return GloveCursorBob.glove_offset_for_frame(pairs, _bob_frame)


func cursor_display_pos() -> Vector2:
	return StartActionMenu.cursor_display_pos_in(ROWS_CONTAINER,
		_tab_row[_tab] - _tab_scroll[_tab], cursor_bob_x())


func _place_cursor() -> void:
	if _lit_holder == null or not is_instance_valid(_lit_holder):
		return
	# An empty tab has no row to point at — the ROM's `cd824 == 0` guard. Hide the glove
	# rather than parking it on a row that is not drawn.
	var has_rows := row_count() > 0
	_lit_holder.visible = has_rows
	if _shadow_holder != null and is_instance_valid(_shadow_holder):
		_shadow_holder.visible = has_rows
	if not has_rows:
		return
	var lit := cursor_display_pos()
	var shadow := lit + StartActionMenu.CURSOR_SHADOW_DELTA
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
# Mount helpers
# -----------------------------------------------------------------------------
## A baked `frame.tga` word cell (header / Master! / dash / Learned) at display (x, y).
func _mount_cell(parent: UI3Element, cell: Rect2i, x: float, y: float, palette: ImageTexture,
		rung: int, mats_out: Array) -> void:
	if palette == null:
		return
	var tex := FrameCellAtlas.index_texture(cell)
	if tex == null:
		return
	var mat := _cell_mat(tex, Rect2(Vector2.ZERO, Vector2(cell.size)), palette, _SPRITE_SHADER, rung)
	mats_out.append(mat)
	var holder := Node3D.new()
	holder.position = parent.rel_world(x, y) + parent.z_for(rung)
	parent.add_child(holder)
	var mi := _quad(Vector2(cell.size))
	mi.material_override = mat
	holder.add_child(mi)


## A RANGETILE sprite cell (a tab icon, the Master! star) at display (x, y).
func _mount_sprite(parent: UI3Element, cell: Rect2, x: float, y: float, palette: ImageTexture,
		rung: int, mats_out: Array) -> void:
	if _atlas.texture == null or palette == null or cell.size == Vector2.ZERO:
		return
	var mat := _cell_mat(_atlas.texture, cell, palette, _SPRITE_SHADER, rung)
	mats_out.append(mat)
	var holder := Node3D.new()
	holder.position = parent.rel_world(x, y) + parent.z_for(rung)
	parent.add_child(holder)
	var mi := _quad(cell.size)
	mi.material_override = mat
	holder.add_child(mi)


func _cell_mat(atlas: Texture2D, cell: Rect2, palette: ImageTexture, shader_path: String,
		rung: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.set_shader_parameter("index_atlas", atlas)
	mat.set_shader_parameter("atlas_size", Vector2(atlas.get_width(), atlas.get_height()))
	mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y))
	mat.set_shader_parameter("palette_tex", palette)
	mat.set_shader_parameter("brightness", 1.0)
	mat.render_priority = rung
	return mat


func _quad(size_px: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size_px * _bot_window.ppu()
	mi.mesh = q
	mi.position = Vector3(q.size.x * 0.5, -q.size.y * 0.5, 0.0)
	return mi


static func _palette_from_colors(colors: Array) -> ImageTexture:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		img.set_pixel(i, 0, colors[i] if i < colors.size() else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


# -----------------------------------------------------------------------------
# Guard seams
# -----------------------------------------------------------------------------
## The per-glyph ability-NAME materials for the visible rows (FONT.BIN body text).
func row_text_materials() -> Array:
	return _row_text_mats


## The row NUMBER-column glyph materials (FRAMEFONT small digits) — separate from
## [method row_text_materials] so the guard can pin that the two render through DIFFERENT
## fonts, which is what the settled framebuffer shows.
func row_number_materials() -> Array:
	return _row_number_mats


## The row's baked frame.tga CELL materials — the dash squiggle and `Learned`.
func row_cell_materials() -> Array:
	return _row_cell_mats


## The top frame's summary-row materials (job name, `/`, the four columns, Master! + star).
func top_row_materials() -> Array:
	return _top_mats


## The nine cream column-header cell materials across both frames.
func header_cell_materials() -> Array:
	return _header_cell_mats


## The four tab-icon materials, in template order.
func tab_icon_materials() -> Array:
	return _tab_icon_mats


func cursor_materials() -> Array:
	return _cursor_mats


## The ability names rendered in the current tab's visible window, top → bottom.
func visible_row_names() -> Array:
	return _visible_names


## Per visible row, `[mp, speed, jp]` as PAINTED — `"-"` where the dash squiggle replaces the
## MP/Speed digits, `"Learned"` where the cell replaces the JP column.
func visible_row_columns() -> Array:
	return _visible_columns


## Per visible row, whether it painted through the DISABLED ramp (both mechanisms).
func visible_row_dim() -> Array:
	return _visible_dim


## The entry indices the current tab lists, in row order. For the guard's tab-partition check.
func tab_entry_indices(t: int) -> Array:
	return _tab_rows[t] if t >= 0 and t < TAB_COUNT else []
