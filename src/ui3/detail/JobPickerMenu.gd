class_name JobPickerMenu
extends Node3D

## The formation "Learn" job picker — the job sibling of [AbilityPickerMenu] (the "Set"
## flow). Opens on ○ from the ability sub-screen's "Learn" row and lists the unit's UNLOCKED
## generic jobs over the ROM's own panel: `Rect2(29,30,203,193)` (x29..231 / y30..222 — the
## CHROME top, §9.2), eleven 16-px rows from y44, and five cream column headers that STRADDLE
## the panel's top edge rather than sitting above it.
## LEARN_PICKER.md **round 10** is the spec; it supersedes §12 wherever they disagree.
##
## ONE SCROLLING LIST of all candidates (round 10 #6): the ROM's candidate array carries a
## `0xFFFF` break implying two columns, but no input crosses it and the rows render in order,
## so on screen it is indistinguishable from one list (§14.5's nav probe). LEFT/RIGHT move no
## cursor in the ROM either.
##
## Candidate rows are set EXTERNALLY (`entries`) before add_child — the picker renders them;
## it computes neither the unlock set (see `UnitProgression.get_unlocked_jobs()`) nor the
## column numbers. See [member entries] for the shape.
##
## Navigation mirrors the sibling picker exactly (the shared ROM list-menu model): wrap
## top/bottom, and an 11-row scroll window (row stride 16px) — §3.
##
## CHROME, all through the shared index→CLUT sprite mechanism:
##   (1) the five cream COLUMN HEADERS — Job / Lv. / Total / Next / Jp — as baked
##       `assets/ui/frame.tga` word cells under CLUT 0x7CBC ([FrameCellAtlas]; round 9 read
##       all five off the sheet, killing both the round-7 "FONT glyphs" and round-8
##       "RANGETILE quads" readings), and
##   (2) the bobbing glove CURSOR on the highlighted row, whose ROM screen position
##       (20,43) at row 0 is what pins [constant ROWS_CONTAINER].
##
## The picker also owns the DETAIL VITALS BAND's fade for the duration of its OPEN aperture
## walk (round 10 #3) — it publishes a factor per frame through [signal band_factor_changed]
## and lets the host apply it, because the picker owns the box-open clock but not the band.
## The CLOSE publishes nothing per-frame: the band comes back in one step with the rest of
## the screen once the box has shut (see [method _on_window_aperture]).
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

## The ROM panel (x29..231 / y30..222) fits ELEVEN 16-px rows in its
## y39..222 interior — first row top y44, the framebuffer's row bands y44..55 / y60..71
## (LEARN_PICKER.md round 10 #1, §9.2). The list scrolls past that (§3; the ROM's real
## case is 18 candidates against these 11 slots).
const VISIBLE_ROWS := 11

## The five COLUMN HEADERS — Job / Lv. / Total / Next / Jp (§9.3). Each is a BAKED WORD CELL
## on `assets/ui/frame.tga` (FRAME.BIN), drawn through the cream CLUT 0x7CBC — round 9 read
## all five off the sheet directly and killed the round-7 reading twice over: they are not
## FONT glyphs (§9.2's "no baked cell exists" is superseded) and not RANGETILE quads (round
## 8's attribution — RANGETILE at these rects is chrome; its "Next" is a down-triangle).
##
## `cell` = the frame.tga source rect (round 9's quad rects, which carry ~1px of bleed around
## the ink bbox). `x` = the ROM's live screen x (§9.2's framebuffer bboxes: JOB 38..54,
## LV 119..132, TOTAL 143..164, NEXT 174..194, JP 208..219). All five share screen y26 — the
## `p` descender is why Jp's cell is 10 rows, not 8.
const HEADER_CELLS := [
	{"name": "Job",   "cell": Rect2i(22, 32, 17, 8),   "x": 38.0},
	{"name": "Lv.",   "cell": Rect2i(49, 48, 14, 8),   "x": 119.0},
	{"name": "Total", "cell": Rect2i(0, 152, 22, 8),   "x": 143.0},
	{"name": "Next",  "cell": Rect2i(24, 152, 21, 8),  "x": 174.0},
	{"name": "Jp",    "cell": Rect2i(228, 64, 12, 10), "x": 208.0},
]

## The header row's screen top (§9.2: all five quads span y26..34/35) — 4px above the panel
## CHROME top (y30), which is what `aperture_pad` grows the box-open over. The headers OVERLAP
## that chrome by four rows: the ROM's cream header row y27..33 and the panel's first chrome
## rows y30..33 are the same framebuffer pixels, which is the straddle the port reproduces.
const HEADER_Y := 26.0

## The four NUMBER columns, in render order: the entry key each reads, the display-px x its
## ink CENTRES on (the matching header cell's own centre), and its DIGIT COUNT. The job NAME
## is the fifth column and is left-aligned at NAME_X instead, so it is not in this table.
##
## `digits` is the ROM's `maxd` byte, read straight off the template `0x8018D1A4`
## (LEARN_PICKER.md §3.1): Lv. is `maxd = 1` @0x77, the other three are `maxd = 4`
## @0x81/@0xBF/@0xC9. The ROM pads the unused leading positions with literal `0` glyphs in
## the same CLUT — s13 record type `0x0D` takes neither the blank (`0x19`) nor the
## dim-leading (`0x1A`) branch (`0x80127FD4`..`0x801280A4`) — so the settled screen reads
## `I │ /0175 │ 0200 │ 0005`, never `1 │ 175 │ 200 │ 5`.
const COLUMNS := [
	{"key": "lv", "center_x": LV_CENTER_X, "digits": 1},
	{"key": "total", "center_x": TOTAL_CENTER_X, "digits": 4},
	{"key": "next", "center_x": NEXT_CENTER_X, "digits": 4},
	{"key": "jp", "center_x": JP_CENTER_X, "digits": 4},
]

## The `/` between the Lv. and Total columns — a STATIC quad in the ROM template
## (`0x8018D1A4` @0x6E: x=137, y=44, 6x11, `uv (180,16)` = cell 10 of the digit strip
## `0123456789/`), drawn once per row at the row text's own y. Not a separator between a
## pair — nothing is being divided; it is chrome that happens to be the slash glyph, which is
## why it is mounted as a one-character number rather than through `place_pair`.
const SEPARATOR_X := 137.0

## The cursor + row region. NOT a guess: §9.2's live framebuffer puts the ROM's row-0
## glove lit layer at screen (20,43)–(36,59) and its shadow at (22,45) (+2/+2, §15.20).
## `StartActionMenu.cursor_display_pos_in` places the lit glove at
## `(c.x − CURSOR_X_BIAS(12) + bob, c.y + row·16 + CURSOR_Y_OFFSET(10))`, so the container
## that reproduces (20,43) is x = 20 + 12 = 32, y = 43 − 10 = 33. Row text then tops out at
## y44 = c.y + 11 — the framebuffer's first row band (y44..55). Width/height span the panel
## interior to x231 / y209 (11 rows × 16).
const ROWS_CONTAINER := Rect2i(32, 33, 199, 176)

## Row-0 text top (display px) + the column pitch — the framebuffer row bands y44..55,
## y60..71 (§9.2). The rows element's authored home carries these.
const ROW0_TEXT_Y := 44.0
const ROW_PITCH := 16.0

## The five COLUMN x-anchors (display px), read off the ROM's own header quads (§9.2's
## live screen bboxes: JOB 38..54, LV 119..132, TOTAL 143..164, NEXT 174..194, JP
## 208..219). The job NAME is left-aligned under the JOB header; the four number columns
## are CENTRED on their header cell's centre — `(left + right + 1) / 2`.
##
## Centred, NOT right-aligned: §9.2's row-glyph run is screen **x123..224**, and centring
## reproduces both ends exactly — a 1-digit Lv. on 125.5 starts at 122.5 → x123, and a 4-digit
## Jp on 213.5 ends at x224 (see UIMenuText.number_ink_width, which carries the derivation).
## Round 10 #5 right-aligned them on each header's right edge + 1, which predicts x128..220 —
## refuted at BOTH ends of the same run it cited. F3-dialable like every other placement.
##
## Round 16 pinned the centres against the template's own base-x bytes rather than the
## framebuffer run: with the columns now FIXED-WIDTH (see COLUMNS.digits) the ink starts at
## `round(center - width/2)`, which must equal the record's base-x — `0x7B/0x8F/0xAD/0xCB` =
## 123/143/173/203. Three already did; NEXT was 184.0 and landed on 174, one pixel right of
## the ROM, so it is 183.5.
const NAME_X := 38.0
const LV_CENTER_X := 125.5
const TOTAL_CENTER_X := 153.5
const NEXT_CENTER_X := 183.5
const JP_CENTER_X := 213.5

const RP_BASE := 40
const RP_FRAME := 46
const RP_ROW_TEXT := 49
const RP_HEADER := 50
const RP_CURSOR_SHADOW := 51
const RP_CURSOR_LIT := 52

const _BOB_TICK := 1.0 / 60.0

## Emitted on ○ — the host JP-gates + commits the picked job.
signal chosen(row: int)
## Emitted whenever the highlight moves (host may refresh a preview).
signal selection_changed(row: int)
## Emitted on × — the host closes the picker.
signal cancelled
## Re-emitted once the box-close animation finishes.
signal closed
## The detail vitals band's `full_sub` multiplier for the current aperture frame (round 10
## #3). The host pipes it straight into DetailScene.set_vitals_band_factor — the picker owns
## the aperture, so it owns the band's clock; it does not reach for the DetailScene itself.
signal band_factor_changed(factor: float)

## Candidate rows, set by the host before add_child. Each entry is
## `{id, name, lv, total, next, jp}` — `id` the generic job id ("4a"-style hex), `name` the
## JobDatabase display name, and the four INTEGER column values the host reads off the unit's
## progression (round 10 #5). The picker renders them; it computes neither the unlock set nor
## the numbers.
var entries: Array = []

## Play the box-open on _ready (host may disable to boot settled).
@export var autoplay_open: bool = true
@export var fast: bool = false

## Which row the picker boots on. Zero for a fresh open; the host sets it when the picker is
## being REBUILT behind a screen the player just backed out of — × on the Learn ability list
## puts the ROM back here with its own 6-byte record intact (LEARN_ABILITY_LIST.md §13.5),
## and a picker that reopened on row 0 would silently lose the player's place.
@export var initial_row: int = 0

## Whether the OPEN ramps the vitals band (round 10 #3). True for the press that reaches this
## picker from the detail screen — the band is up and must fade with the aperture. FALSE when
## the picker is re-opened from a screen ONE LEVEL DEEPER (× off the Learn ability list): the
## band is already cleared, and re-running the ramp from frame 0 would flash it back to full
## and fade it out a second time. The `closed` handler still publishes its single 1.0, so the
## band comes back with the rest of the screen either way.
@export var band_ramp_on_open: bool = true

var _atlas: RangeTileAtlas
var _menu_text: UIMenuText
var _window: UI3Element
var _rows_elem: UI3Element
var _header_elem: UI3Element   # the five cream column-header cells (Job/Lv./Total/Next/Jp)
var _cursor_elem: UI3Element   # the glove cursor element (UNCLIPPED, rides the window)

var _row_text_mats: Array[ShaderMaterial] = []   # per-glyph job-NAME materials, FONT.BIN (guard)
var _row_number_mats: Array[ShaderMaterial] = []  # the four number columns, FRAMEFONT digits (guard)
var _header_mats: Array[ShaderMaterial] = []     # FONT header glyphs — dead since round 10 (guard)
var _header_cell_mats: Array[ShaderMaterial] = []  # the five frame.tga header cell materials (guard)
var _cursor_mats: Array[ShaderMaterial] = []     # glove lit+shadow (guard)
var _visible_names: Array[String] = []           # the names rendered this build (guard)
var _visible_columns: Array = []                 # the [lv, total, next, jp] strings per visible row (guard)
var _content_built := false

# Palettes (built once in _ready from the atlas CLUTs).
var _glove_lit_pal: ImageTexture     # glove lit CLUT 0x7d7c
var _glove_shadow_pal: ImageTexture  # glove shadow CLUT 0x7dbc
var _header_pal: ImageTexture        # the cream header CLUT 0x7cbc (§9.2)

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

# The aperture walk's own frame counter, for the band fade. The BOX_OPEN beat owns the
# clock (ADR-0088: the per-class accumulators died); we only COUNT its per-frame aperture
# pushes, which the engine emits exactly once per driven frame starting at frame 0.
var _ap_frame := 0
var _ap_closing := false
var _ap_active := false


func _ready() -> void:
	_atlas = RangeTileAtlas.new()
	_menu_text = UIMenuText.new()
	_header_pal = _palette_from_colors(_atlas.window_tab_colors())
	_glove_lit_pal = _palette_from_colors(_atlas.menu_glove_lit_colors())
	_glove_shadow_pal = _palette_from_colors(_atlas.menu_glove_shadow_colors())
	_idle_pairs = GloveCursorBob.load_glove_pairs("glove_idle")
	_select_pairs = GloveCursorBob.load_glove_pairs("glove_select")
	# Seat the restored row (and its scroll window) BEFORE the first build, so the rebuild
	# mounts the right slice of the list rather than mounting row 0's and re-mounting.
	_row = clampi(initial_row, 0, maxi(0, entries.size() - 1))
	_scroll = clampi(_row - VISIBLE_ROWS + 1, 0, maxi(0, entries.size() - VISIBLE_ROWS))
	_build_window()
	_build_content()
	if autoplay_open:
		play_open()
	_place_cursor()


# -----------------------------------------------------------------------------
# Window + rows/header/cursor elements (mirrors the sibling picker; ADR-0088 movable-origin
# model). Placement is ROM-derived — the panel bbox from §11, the row grid and glove anchor
# from §9.2's live framebuffer, the header x's from §9.2's prim table — and still F3-dialable.
# -----------------------------------------------------------------------------
func _build_window() -> void:
	_window = UI3Element.new({
		"id": "jobpicker.window",
		# The ROM panel bbox: x29..231 / y30..222. The TOP is y30, not §11's y35 — §11's bbox
		# is the BEVEL/FILL top, while §9.2's framebuffer row profile shows the panel's own
		# chrome starting four rows higher, INSIDE the cream header row y27..33 (y30 0x10A6
		# ×130 and y31 0x573A ×124 are full-width chrome rows). Round 10 #1 took §11's bbox
		# for the whole window rect, which is why the headers rendered 100% ABOVE the frame
		# instead of straddling its top edge the way the ROM draws them.
		#
		# The bottom is unchanged (30 + 193 = 223 ⇒ y222). With STRIPE's 9px top margin the
		# fixed chrome now covers y30..38 and the tiled body starts at y39 — exactly where
		# §9.2 puts the panel fill, and 5px of top margin above row 0's text at y44. Rows,
		# headers and cursor are authored in ABSOLUTE display px, so raising the rect moves
		# the frame alone.
		"rect": Rect2(29.0, 30.0, 203.0, 193.0),
		"authored_home": Vector2(29, 30),
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.STRIPE,
		"frame_center_patch": Vector4(6, 7, 21, 17),
		"frame_rp": RP_FRAME,
		"clip": UI3Element.Clip.OWN_APERTURE,
		# ADR-0088 amendment §4 (mirrors AbilityPickerMenu): the five header cells sit at
		# screen y26..35 (§9.2), 4px above the window rect top (y30), so pad the box the
		# box-open plays over by 4px on top — the cream headers ride the reveal instead of
		# being scissored. The `aperture_pad` knob is otherwise auto-provided at zero
		# (docs/ui3-guide.md "Aperture padding"); a non-zero default is a deliberate
		# port-side affordance.
		"aperture_pad": Vector4(0, 9, 0, 0),
		"depth_rung": -6,
		# ADR-0097 §2: one cadence per VERB. The `fast` export escalates the OPEN only; the
		# close takes the house rule (DEFAULT -> fast) like every other picker.
		"open_cadence": UI3BoxOpenBeat.Cadence.FAST if fast else UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
	})
	add_child(_window)
	_window.aperture_changed.connect(_on_window_aperture)
	_window.opened.connect(func() -> void:
		_ap_active = false
		band_factor_changed.emit(0.0))
	_window.closed.connect(func() -> void:
		_ap_active = false
		band_factor_changed.emit(1.0)
		closed.emit())

	# The list ASSEMBLY: ONE element; rows are payload placed from rect.y + `pitch`.
	# Text-only — a single `name_x` column, no glyph/icon/count columns.
	_rows_elem = UI3Element.new({
		"id": "jobpicker.rows",
		"rect": Rect2(29.0, ROW0_TEXT_Y, 203.0, VISIBLE_ROWS * ROW_PITCH),
		"authored_home": Vector2(29.0, ROW0_TEXT_Y),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
		"pitch": ROW_PITCH,
		"name_x": NAME_X,
	})
	_window.add_child(_rows_elem)

	# The cream column-header element — the five baked frame.tga word cells (§9.3). It spans
	# the header row (screen x38..220, y26..36); each cell places itself absolutely inside it.
	_header_elem = UI3Element.new({
		"id": "jobpicker.header",
		"rect": Rect2(NAME_X, HEADER_Y, _header_right_x() - NAME_X, 10.0),
		"authored_home": Vector2(NAME_X, HEADER_Y),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	_window.add_child(_header_elem)

	# The glove cursor element: Clip.UNCLIPPED is a DECLARED answer (the glove pokes
	# off the frame's LEFT edge, outside the box-open scissor, drawn on top — mirrors
	# the sibling picker §15.20). Its rect rides the window at the authored home.
	_cursor_elem = UI3Element.new({
		"id": "jobpicker.cursor",
		"rect": Rect2(29, 30, 203, 193),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_cursor_elem.name = "PickerGloveCursor"
	_window.add_child(_cursor_elem)


## Build (or rebuild) the visible payload — title header, one name text per
## visible row, and the glove. Text-only rows: nothing but FONT glyphs is
## mounted in the row region. Called once from _ready and again on scroll.
func _build_content() -> void:
	for e: UI3Element in [_rows_elem, _header_elem, _cursor_elem]:
		for c in e.get_children():
			c.free()   # synchronous (mirrors the sibling picker's scrub rebuild)
	_row_text_mats.clear()
	_row_number_mats.clear()
	_header_mats.clear()
	_header_cell_mats.clear()
	_cursor_mats.clear()
	_visible_names.clear()
	_visible_columns.clear()
	_lit_holder = null
	_shadow_holder = null

	_build_header()
	_build_rows()
	_build_cursor()
	_content_built = true


## Mount the five cream column headers — one baked `frame.tga` word cell each, sampled as a
## 4bpp INDEX bitmap ([FrameCellAtlas]) through the cream CLUT 0x7CBC. That inversion is the
## whole point: the sheet bakes these words DARK-on-tan, and 0x7CBC maps the ink index 1 to
## cream 0xE7E7E7 and the cell's tan background indices to the dark shades — which is exactly
## the cream-on-dark header the ROM framebuffer shows above the panel bevel (§9.2).
func _build_header() -> void:
	if _header_pal == null:
		return
	for h in HEADER_CELLS:
		var cell: Rect2i = h["cell"]
		var tex := FrameCellAtlas.index_texture(cell)
		if tex == null:
			continue
		var mat := _cell_mat(tex, Rect2(Vector2.ZERO, Vector2(cell.size)), _header_pal,
			_SPRITE_SHADER, RP_HEADER)
		_header_cell_mats.append(mat)
		var holder := Node3D.new()
		holder.position = _header_elem.rel_world(float(h["x"]), HEADER_Y) \
			+ _header_elem.z_for(RP_HEADER)
		_header_elem.add_child(holder)
		var mi := _quad(Vector2(cell.size))
		mi.material_override = mat
		holder.add_child(mi)


## One row per visible entry: the job NAME in FONT.BIN text left-aligned under the Job header,
## then the four number columns in the SMALL HUD DIGIT font, centred under Lv. / Total / Next /
## Jp. Two different fonts by design (§9.2): the name is menu body text, while the ROM's row
## numbers are "small 6-px-wide quads" — the FRAMEFONT `small` set (6×10 cells, advance 5) the
## nameplate draws Brave/Faith with, on its dark 3-ink CLUT. Text-only throughout: no glyph or
## icon column, which is what [method row_decoration_materials] pins.
func _build_rows() -> void:
	var s := _rows_elem
	var row0_y := s.authored_home().y
	var pitch := float(s.spec().get("pitch", ROW_PITCH))
	var name_x := float(s.spec().get("name_x", NAME_X))
	for i in range(_scroll, mini(entries.size(), _scroll + VISIBLE_ROWS)):
		var e: Dictionary = entries[i]
		var nm := String(e.get("name", ""))
		var y := row0_y + (i - _scroll) * pitch
		_menu_text.mount(s, nm, s.rel_world(name_x, y) + s.z_for(RP_ROW_TEXT),
			RP_ROW_TEXT, s.ppu(), _row_text_mats)
		_visible_names.append(nm)
		var cols: Array = []
		for c in COLUMNS:
			var text := _column_text(int(e.get(c["key"], 0)), int(c["digits"]))
			cols.append(text)
			_mount_centered_number(s, text, float(c["center_x"]), y)
		_visible_columns.append(cols)
		# The `/` chrome between Lv. and Total — left-aligned on its own template x, not
		# centred on anything (SEPARATOR_X carries the derivation).
		_menu_text.mount_number(s, "/", s.rel_world(SEPARATOR_X, y) + s.z_for(RP_ROW_TEXT),
			RP_ROW_TEXT, s.ppu(), null, _row_number_mats)


## One column's painted string: `value` zero-padded to the ROM's `maxd` for that column
## (LEARN_PICKER.md §3.1). A value too wide for the field is NOT truncated — the ROM's own
## digit loop would draw only `maxd` cells, but every reachable JP figure is well under 9999
## and silently dropping a digit reads as a rendering bug, so an over-wide value simply runs
## long and stays legible.
static func _column_text(value: int, digits: int) -> String:
	return str(maxi(0, value)).pad_zeros(digits)


## Mount `text` as HUD digits with its INK centred on `center_x` (display px) — the number
## columns hang off their header's centre, so they stay centred as the digit count changes.
## Centring uses the ink width (advance × (n−1) + the last cell), not the advance-only width:
## on the SMALL set those differ by the 1px cell overhang, and it is that measure which lands
## §9.2's run on x123..224 exactly. Snapped to whole display px so the 6px cells stay crisp.
func _mount_centered_number(s: UI3Element, text: String, center_x: float, y: float) -> void:
	var x := number_ink_x(text, center_x)
	_menu_text.mount_number(s, text, s.rel_world(x, y) + s.z_for(RP_ROW_TEXT),
		RP_ROW_TEXT, s.ppu(), null, _row_number_mats)


## Where `text`'s ink STARTS (display px) when centred on `center_x`. The one place the
## centring rule lives, so the guard asserts it against §9.2's run instead of re-deriving it.
func number_ink_x(text: String, center_x: float) -> float:
	return roundf(center_x - _menu_text.number_ink_width(text) * 0.5)


## The px width of `text`'s ink in the row number font — the guard pairs it with
## [method number_ink_x] to check both ends of §9.2's x123..224 run.
func number_ink_width(text: String) -> float:
	return _menu_text.number_ink_width(text)


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
		_ap_frame = 0
		_ap_closing = false
		_ap_active = true
		_window.open(cadence)


func play_close(cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	if _cursor_elem != null and is_instance_valid(_cursor_elem):
		_cursor_elem.visible = false  # focus has already left
	if _window != null and is_instance_valid(_window):
		_ap_frame = 0
		_ap_closing = true
		_ap_active = true
		# `_ap_closing` is what MUTES the per-frame band publish for this walk
		# ([method _on_window_aperture]); the band returns on the `closed` handler's 1.0.
		_window.close(cadence)


## The vitals band's `full_sub` multiplier at aperture frame `n` — DetailScene's OWN
## `band_crossfade` out-ramp `clamp(1 − s/0.6)` sampled on the box-open clock, with
## `s = n / settle_frame`. Pure so the guard asserts it without a built scene.
##
## KNOWN, USER-ACCEPTED DIVERGENCE (round 10 #3): this curve clears the band at 60% of the
## aperture walk, while the measured ROM band samples (§9.5: 120→96→72→48→0, exactly
## −24/frame over 5 frames) put it at 0 on the settle frame. The user was shown both and
## chose the existing crossfade. Stretching it later is a one-line change here.
##
## Sampled on the OPEN clock only — the close holds the band cleared and snaps it back with the
## rest of the screen ([method _on_window_aperture]), so `frame` never counts a close here.
static func band_factor_at_frame(frame: int, cadence: int) -> float:
	var settle := float(UI3BoxOpenBeat.settle_for(cadence))
	if settle <= 0.0:
		return DetailScene.band_crossfade(1.0).x   # IMMEDIATE: no walk to sample, land the end
	return DetailScene.band_crossfade(clampf(float(frame) / settle, 0.0, 1.0)).x


## One aperture push = one driven beat frame (UI3TransitionEngine drives frame 0 on play,
## then one per step). Count them and publish the band factor for that frame.
##
## OPEN ONLY. The band ∥ aperture pairing is a MEASURED ROM fact for the open — LEARN_PICKER.md
## §4 beat 2 starts the band-fade counter on the same vsync the aperture first renders, and the
## two progress together through ss4. There is no measured CLOSE to mirror: the ROM animates
## opens only (ADR-0182), so both the port's close animation and anything riding it are port
## inventions.
##
## The close therefore publishes NOTHING per frame — the band is held cleared for the whole
## walk and returns on the `closed` handler's single `1.0`, the same step
## FormationDetailTransition._restore_after_job_picker brings the list-menu and the DetailScene
## panels back. User-directed 2026-08-19: "the closing of the panel should happen 100%, then
## the other stuff all happens at once."
##
## Reversing the open put the band at full by ~60% of a 5-frame FAST close (measured: 0, 0,
## 0.17, 0.58, 1.0, shut) — so the band arrived BEFORE the box was shut and the panels after
## it, splitting one return into two events. Not an ADR-0084 invariant-1 question: that
## invariant governs COORDINATOR RECIPES and positional beats, and this picker is self-clocked
## through play_open/play_close with the band published as a crossfade, not a beat.
func _on_window_aperture(_rect: Rect2i) -> void:
	if not _ap_active or _ap_closing or not band_ramp_on_open:
		return
	var cadence := _ap_cadence()
	band_factor_changed.emit(band_factor_at_frame(_ap_frame, cadence))
	_ap_frame += 1


## The RESOLVED cadence of the OPEN currently playing (ADR-0097 §1) — the authored per-verb
## answer, through the house rule. Asked of the live window element, so a call-site override
## (§4) is included: the band must ramp over the frames actually being played, not the ones the
## spec would have played. Open-only because the close no longer ramps anything
## ([method _on_window_aperture]); a `_ap_closing` branch here would be unreachable.
func _ap_cadence() -> int:
	return UI3BoxOpenBeat.resolve(_window.cadence_for(UI3Element.OPEN_CADENCE), true)


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
# Sprite helpers (mirror the sibling picker — the shared index→CLUT sprite mechanism).
# -----------------------------------------------------------------------------
func _sprite_mat(cell: Rect2, palette: ImageTexture, shader_path: String, rung: int) -> ShaderMaterial:
	return _cell_mat(_atlas.texture, cell, palette, shader_path, rung)


## The shared index→CLUT sprite material, over ANY index atlas — the RANGETILE sheet for the
## glove, a [FrameCellAtlas] cell bitmap for the headers.
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
## The per-glyph JOB-NAME materials mounted for the visible rows (FONT.BIN body text).
func row_text_materials() -> Array:
	return _row_text_mats


## The four NUMBER columns' glyph materials for the visible rows — the SMALL HUD digit font
## (FRAMEFONT), not FONT.BIN. Separate from [method row_text_materials] so the guard can pin
## that the two columns render through DIFFERENT fonts, which is what §9.2 shows.
func row_number_materials() -> Array:
	return _row_number_mats


## FONT-composed header glyph materials. ALWAYS EMPTY since round 10 — the headers are baked
## `frame.tga` cells now. Kept as a seam so the guard asserts the round-7 FONT mechanism is
## GONE rather than merely untested; see [method header_cell_materials].
func header_materials() -> Array:
	return _header_mats


## The five cream column-header CELL materials (Job/Lv./Total/Next/Jp) — proves the headers
## render through the frame.tga index→CLUT 0x7CBC mechanism (round 9 / round 10 #4).
func header_cell_materials() -> Array:
	return _header_cell_mats


## The frame.tga source rects the five headers sample, in column order. For the guard.
func header_cells() -> Array:
	var out: Array = []
	for h in HEADER_CELLS:
		out.append(h["cell"])
	return out


## The right edge of the LAST header cell (Jp: x208 + a 12px cell = 220) — the header
## element's own right edge, derived from the table so it cannot drift from it.
static func _header_right_x() -> float:
	var last: Dictionary = HEADER_CELLS[HEADER_CELLS.size() - 1]
	return float(last["x"]) + float((last["cell"] as Rect2i).size.x)


## The header element's own rect (display px) — the cream header row's box. For the guard's
## aperture check: it straddles the window top, so the box-open's `aperture_pad` must enclose it.
func header_element_rect() -> Rect2:
	return _header_elem.rect() if _header_elem != null else Rect2()


## The five headers' screen x anchors, in column order. For the guard.
func header_screen_x() -> Array:
	var out: Array = []
	for h in HEADER_CELLS:
		out.append(float(h["x"]))
	return out


## The glove cursor materials (lit + shadow) — UNCLIPPED, on top. For the guard.
func cursor_materials() -> Array:
	return _cursor_mats


## The candidate names rendered in the current visible window (top → bottom).
func visible_row_names() -> Array:
	return _visible_names


## The four number-column strings `[lv, total, next, jp]` per visible row (top → bottom) —
## what is actually painted, for the guard.
func visible_row_columns() -> Array:
	return _visible_columns


## Per-row DECORATION materials (type glyph / icon). Always empty: the job picker rows are
## text-only — a job name plus four number columns (LEARN_PICKER.md round 10 #5).
## Exposed so the guard can assert the shape (the equip picker mounts these;
## this one must not).
func row_decoration_materials() -> Array:
	return []
