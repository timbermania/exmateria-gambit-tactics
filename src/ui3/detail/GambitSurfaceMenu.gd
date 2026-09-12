class_name GambitSurfaceMenu
extends Node3D

## ONE titled, glove-cursored list of plain-text rows — the gambit surface's only widget, used
## at all three of its levels (#1007).
##
## The surface drills SLOT -> PART -> CHOICE, and all three levels are the same thing: a titled
## list of strings you walk with ↑/↓, take with ○ and leave with ✕. Building three classes for
## that would have been three copies of the glove, the box-open and the scroll window, so this
## is ONE class mounted three times with a different `title` and `entries`. What differs between
## the levels is the STRINGS, and strings are data.
##
## Modelled on [AbilityPickerMenu] — the same UI3Element window / rows / cursor triple, the same
## ROM list-menu navigation (wrap top-bottom, a scrolling window of [constant VISIBLE_ROWS] at a
## 16px pitch), the same index->CLUT glove and its subtractive fold twin.
##
## MOST OF THESE WINDOWS WEAR NO TITLE AT ALL. The two choice lists never did (ADR-0268 dec. 10
## — the column they hang off is already the part's name), and the ROW level stopped (ADR-0255
## Amendment 1 — the adjustment-menu row that opens it already said "Gambit", and the title was
## spending an 8-px band and inking into the frame's own top border to repeat it). The IMPERATIVE
## level is the one that still wears one, and [method title_band] collapses the band for the rest.
##
## WHERE A TITLE IS WORN IT IS FONT.BIN TEXT, NOT A BAKED CELL, and that is a decision rather
## than a shortcut. The two title tabs the atlas carries are "Eqp" and "Ability"
## (`window_tab_rect`), baked cells RE'd off the ROM's own lower windows. FFT has no gambit
## screen, so there is no cell to sample and never will be — and reusing the "Ability" cell (the
## ability picker's deliberate deviation) would title this window with a word that names a
## DIFFERENT screen one press away. A FONT.BIN title is what a game-original window can honestly
## wear.
##
## Rows are WIDE. A gambit reads as a sentence ("Attack Nearest Foe"), not as an item name, so
## this window spans most of the display rather than sitting in the 84-96px column the ROM's own
## list menus use. Placement is authored, not oracle-derived — there is no oracle — and stays
## F3-dialable through the [Tune] bind below.

const TunePort = ExMateriaPlatform.TunePort

const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")
const UIMenuText = preload("res://src/ui3/UIMenuText.gd")
const GloveCursorBob = preload("res://src/ui3/GloveCursorBob.gd")

const _SPRITE_SHADER := "res://src/ui3/shaders/vitals_sprite.gdshader"
const _SHADOW_SHADER := "res://src/ui3/shaders/menu_cursor_shadow.gdshader"
## The FOLD twin of the glove's subtractive layer — preloaded as a Shader, never named as a
## String, because a load() of a mistyped path returns null and a null shader does not raise
## (ADR-0191 dec. 2). Same reasoning as every other glove consumer.
const _SHADOW_FOLD_SHADER := preload("res://src/ui3/shaders/menu_cursor_shadow_fold.gdshader")
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

## The ROM list-menu window shows at most 5 rows at a 16px pitch and scrolls. Four gambit slots
## fit without scrolling; the CHOICE level (every ability a job can cast) does not, which is why
## the scroll window is inherited rather than dropped.
const VISIBLE_ROWS := 5

## The window's one key location (ADR-0088 Amendment 2) — a composite Rect2 bind, so the whole
## menu (frame, rows, title, glove, box-open aperture) moves when it is scrubbed.
const LOC_GAMBIT := "gambitsurface.loc.window"
## Authored home, display px — the ROM-pinned lower panel's own margins (ADR-0255 Amendment 1).
##
## It is pinned to the slot [member DetailScene.LOWER_FRAME] occupies — the ROM-pinned lower
## panel this window REPLACES when the surface opens — so that nothing shifts under the player
## between two screens that share one slot. Before this they disagreed by 2 left / 3 up / 2
## wide, which reads on a capture as the panel jumping when the surface opens.
##
## MATCHED ON INK, NOT ON RECT, and the difference is one pixel that only a capture can see.
## The detail screen's panels are FRAME.BIN 9-slice mounts and ink AT their rect; a UI3
## [constant UI3Element.Frame.STRIPE] inks one px INSIDE it. So `x = 13` and not LOWER_FRAME's
## 14 — measured on the capture, the stats panel directly above inks its left column at x=14 and
## its right at x=240, and this rect reproduces both (13+1, 13+230-3).
##
## WIDE (230 of the 256-px display) because a row is a whole SENTENCE across (ADR-0268 dec. 1),
## not an item name.
##
## HEIGHT is `VISIBLE_ROWS*16 + 16` — the container rule ADR-0247 derived, and the whole of it,
## because THERE IS NO TITLE BAND at the row level any more (ADR-0255 Amendment 1 dropped the
## "Gambit" title). That is 96 and not LOWER_FRAME's 94: the last 2 px are the container rule's,
## and at 92 the fifth row's glyphs sat ON the bottom frame border — which a capture showed and
## no layout assertion could have.
##
## The old x=12 argued that 12 was as far LEFT as the window could go, because the glove hangs
## at `container.x - CURSOR_X_BIAS` and the mask clips to [0, 256]. That objection does not
## survive the ROM: the Eqp window's own glove sits at `13 - 12 + bob ≈ 1`, half off the left
## edge, BY DESIGN (`vault/Equip Sub Screen.md`). x=14 is safe, and the glove at 2 is the
## ROM's own look.
static var GAMBIT_CONTAINER := Rect2(13, 137, 230, 96)

# -----------------------------------------------------------------------------
# THE ROW (ADR-0268 dec. 1, unfolded by ADR-0283 dec. 1) — `Slot · Do · To · Subject · If`,
# read across.
#
# Every number below is a MEASUREMENT against `assets/fonts/font_meta.json` through the
# renderer's own advance (`UIUnitNameplate.glyph_advance`, which gives a SPACE 4 px via
# `DialogueBox.SPACE_WIDTH_PX` — not the 10 px the raw glyph table records, which is what
# ADR-0268 dec. 2's arithmetic used and why its numbers do not reproduce).
#
# The row runs 22..240 = 218 px and spends every one of them:
#
#   22  SLOT      6   the slot NUMBER, 1-4 — a readout, not a part (dec. 13)
#    +  (3)           …then 3 px, because SLOT and DO'S CHEVRON SHARE A LANE — see below
#   31  DO       50   capped; 21 of the 228 action-ability names are wider and elide
#   94  TO       48   the target presets, widest "Weakest Ally" / "Nearest Foe" = 48
#                     (ADR-0285 took the list from 6 rows to 8 and cost NOTHING here: the two
#                      new rows are the bare pools, "Ally" and "Foe", at 14 px each — the cap
#                      was already set by the narrowed spellings. The list now SCROLLS past
#                      VISIBLE_ROWS, which is a height question and not a width one.)
#  155  SUBJECT  20   the two-way switch, widest "Their" = 20
#  188  IF       40   the BARE predicate, widest "HP<25%" / "MP<50%" = 40
#  240  +N       12   right-aligned; dec. 3's affordance for `conditions[1..]`
#
# with a 13-px gap in front of TO, SUBJECT and IF for the focus chevron.
#
# === THE GAP IS 13 BECAUSE 11 WAS PHOTOGRAPHED AND IS WRONG ================================
#
# The chevron is mounted at `column_x - CHEVRON_W`, so what matters is the BLANK PIXELS between
# the preceding value's last ink and the arrow's first — `gap - 9`, because FONT.BIN's `→`
# carries one empty column on its own left (ink pattern `.#########`, read off
# `font_atlas.tga`). Every other glyph in this row inks its FULL advance: `A`, `H`, `S`, `M`,
# `-` all ink 6 of 6 and `y` inks 4 of 4, so two letters inside a word already touch.
#
# 13 px gives 4 blank px, which is a word space (`DialogueBox.SPACE_WIDTH_PX`). 11 px gives 2,
# and 2 was CAPTURED (ADR-0244, `tools/capture_gambit_surface.gd --worst`): a full-cap
# `Weakest Ally` followed by the subject's chevron renders `Weakest Ally➡Their`, which reads as
# an arrow BETWEEN two values rather than as a cursor on one. That is a wrong meaning, not a
# tight fit, and no layout assertion could have seen it.
#
# === AND WHY THE SLOT NUMBER SHARES A LANE WITH `DO`'S CHEVRON =============================
#
# At 13-px gaps the four columns, the number and the `+N` want 6 + 4x13 + 50 + 48 + 20 + 40 + 12
# = 228 px against 218. The 10 px is not available anywhere else:
#
#   - `Do` cannot give it. The elision count is not linear in the cap — it has a CLIFF between
#     48 px and 46, where 25 of 228 names become 102 (`VerticalJump5` and every `* Magic` land
#     in those 2 px). 50 is already 4 below dec. 13's 54.
#   - The window cannot widen. ADR-0255 Amendment 1 pinned it to the ROM lower panel's own
#     margins, matched ON INK against the stats panel above it; the 256-px mask is the ROM's.
#   - `+N` cannot shrink: `+1` measures 12 px, and dec. 3 says the one-condition cap is only
#     defensible with the affordance attached.
#
# So the number and the chevron take the same 10 px, and they can: the number is a PER-ROW
# readout and the chevron appears on exactly one part of exactly one row, so the two are never
# wanted at the same x at the same time. The cost is the focused row's number while its `Do` is
# the focused part — the one row the glove is already resting on. `_build_gambit_rows` is where
# that swap happens.
#
# The glove bounds the left end: its ink stops at x=18 (measured on a capture, not from
# `CURSOR_X_BIAS`), so 22 is the leftmost x the row can start at without the glove's fingers
# reaching the slot number. x=18 was tried and photographed doing exactly that.
const COL_ENABLE_X := 22.0
const COL_DO_X := 31.0
const COL_TO_X := 94.0
const COL_SUBJ_X := 155.0
const COL_IF_X := 188.0
const COL_DO_CAP := 50.0
const COL_TO_CAP := 48.0
const COL_SUBJ_CAP := 20.0
const COL_IF_CAP := 40.0
## What SUBJECT may spend on a row whose `If` column is DISABLED — 155 runs all the way to 188
## instead of stopping at 175, because the 13 px it stops short of are the CHEVRON'S GAP and a
## disabled column is one the chevron can never land in.
##
## 🔴 `Always` DOES NOT FIT [constant COL_SUBJ_CAP]. Measured through `UIMenuText.measure`
## against `font_meta.json`, `Always` is **26 px** (6+2+6+4+4+4) against the 20 px `Their` set
## the switch at, and every glyph inks its full advance — nothing in this row has slack to lend
## (see the budget above; the row is already 10 px over and pays for it by sharing a lane).
##
## The 13 px is where the 6 px comes from, and it is free ONLY because the column is disabled
## rather than merely empty: `_move_part` cannot rest on `PART_IF` here
## (`GambitSurface._last_part`), so no arrow is ever mounted at `COL_IF_X - CHEVRON_W`. That
## leaves `Always` ending at 181 with 7 px of blank before the dim cell at 188 — narrower than
## dec. 4's 13 px chevron clearance, but this is VALUE-to-VALUE spacing and not arrow-to-value,
## and 7 px is nearly two word spaces (`DialogueBox.SPACE_WIDTH_PX` is 4). Photographed, because
## dec. 4's whole lesson is that this clearance is a reading and not a threshold.
const COL_SUBJ_DISABLED_CAP := 33.0
## The chevron's own advance — it is mounted at `column_x - CHEVRON_W`, so its ink lands in the
## gap in front of the column it names. NOT the same number as the GAP between columns (13),
## and conflating the two costs the clearance: mounted at `x - gap` the arrow sits 1 px from the
## PRECEDING value and 4 from the one it points at, which is the wrong way round.
const CHEVRON_W := 10.0
## `+N` is RIGHT-aligned to this x rather than trailing the `If` value. Trailing it, the mark
## either collides with a long condition or floats free of a short one; right-aligned it always
## reads as "this row has more", and it cannot overlap because 188+40 = 228 is where it starts.
##
## 240 and not 238: the window's right ink column is 240 (`13 + 230 - 3`), so a mark ending
## there inks its last pixel at 239 and leaves the frame's border its own column. Captured — the
## `+1` sits 2 px clear of the border.
const PLUS_RIGHT_X := 240.0
## The part cursor. A `→` and not the glove, and a shade swap alone confounds a DISABLED row
## with an unfocused one — the two states then render identically.
##
## THE GLOVE WAS RE-TRIED ON THE CURRENT LAYOUT and photographed again (2026-09-10, ADR-0268
## dec. 1's "considered and reversed"). It does not merely cover the column to its LEFT, which is
## how the prototype recorded it — it covers the column it NAMES. The glove hangs at
## `anchor - CURSOR_X_BIAS(12)` and is 13 px wide, so anchored on `Do` at x=38 it inks 26..39 and
## eats that row's own first glyph: `1 ⟨glove⟩--` where the chevron gives `1 → ---`. Making it fit
## costs 4 px off `COL_DO_CAP` and 4 off `COL_TO_CAP` — paid by the one column that already
## elides 21 of 228 ability names — to buy a marker that is worse than the 10-px one sitting in a
## gap that is otherwise empty. The chevron stays.
const PART_CHEVRON := "→"
## Elision mark for an over-wide `Do`. FONT.BIN carries `⋯` as one 10-px glyph.
const ELIDE := "⋯"

## The four PART indices this widget aims the chevron by, and the sentinel for a column that is
## not a part at all. Mirrors `GambitSurface.Part` — mirrored and not imported, because this
## widget renders what it is handed and knows nothing about gambits (see the class doc); what it
## needs is "which of the columns I draw does `focused_part` name", which is a rendering question.
const PART_DO := 0
const PART_TO := 1
const PART_SUBJ := 2
const PART_IF := 3
const NOT_A_PART := -1

## The shade band, shared with [LearnAbilityMenu]'s live-vs-dim rows: the FOCUSED row is LIT and
## every other row DIM, which is the ROM's own convention and what the glove is already saying.
const LIT_INKS: Array[Color] = [
	Color8(49, 41, 33, 255), Color8(82, 82, 66, 255), Color8(132, 123, 107, 255),
]
const DIM_INKS: Array[Color] = [
	Color8(99, 90, 74, 255), Color8(115, 107, 90, 255), Color8(140, 132, 115, 255),
]

## §15.21 BACKGROUNDED twins of the two bands above. A window another surface has focus over
## swaps its whole CLUT foreground→background — a DISCRETE per-index swap, not an alpha tint —
## and the row glyphs are the half of that a palette texture cannot do for us, because FONT.BIN
## text is drawn through three output inks rather than through a CLUT.
##
## They are not eyeballed. [constant LIT_INKS] is CLUT `0x7C3C` indices **1/2/3** and
## [constant DIM_INKS] is the SAME clut's **5/6/7** — the glyph blitter's own `bVar1 += shade * 4`
## shade-band shift, which is why the dim band is a shifted read of the lit one rather than a
## second palette. So each twin is `UIWindowPalettes.BG_FOR_7C3C` at the very same index.
## `GambitSurfaceTest` asserts that equality rather than trusting these literals.
const LIT_INKS_BG: Array[Color] = [
	Color8(41, 49, 57, 255), Color8(57, 66, 74, 255), Color8(82, 90, 99, 255),
]
const DIM_INKS_BG: Array[Color] = [
	Color8(66, 74, 90, 255), Color8(74, 82, 90, 255), Color8(90, 99, 107, 255),
]
## The CLUT indices the four bands above are read from — the guard's subject, so it can prove the
## literals against `UIWindowPalettes` instead of restating them.
const LIT_CLUT_INDICES := [1, 2, 3]
const DIM_CLUT_INDICES := [5, 6, 7]

## Row 0's TEXT top, as an inset from the rows rect — and expressed as the glove's own offset
## plus one, because the ROM relationship this reproduces is "the glove sits 1 px ABOVE the text
## cell's top" ([StartActionMenu], oracle-matched: text = `c.y + 11 + i*16`, glove =
## `c.y + i*16 + 10`). Written as the RELATION so the two cannot drift; a bare 11.0 here would
## be a second, silent copy of a number that is only meaningful against the glove's.
const ROW0_TEXT_INSET_Y := StartActionMenu.CURSOR_Y_OFFSET + 1.0

## The top band a TITLED window spends on its title. Untitled windows collapse it — see
## [method title_band].
const TITLE_BAND := 8.0

const RP_BASE := 40
const RP_FRAME := 46
const RP_ROW_TEXT := 49
const RP_HEADER := 50
const RP_CURSOR_SHADOW := 51
const RP_CURSOR_LIT := 52

const _BOB_TICK := 1.0 / 60.0

## Emitted on ○ with the picked row index. The surface decides what the row MEANS — this widget
## does not know whether it is showing slots, parts or choices.
signal chosen(row: int)
## Emitted whenever the highlight moves.
signal selection_changed(row: int)
## Emitted on ✕.
signal cancelled
## Re-emitted once the box-close animation finishes.
signal closed

## The row strings, top to bottom. Set by the surface BEFORE add_child.
var entries: Array[String] = []
## The window title, rendered in FONT.BIN. Set before add_child. EMPTY by default, because
## that is what every level but the imperative wears — and because the default is what an
## un-set instance renders, a titled default would put a word on a window nobody asked to name.
var title: String = ""

## THE ROW MODE. When non-empty this menu renders COLUMNS instead of [member entries]' single
## strings — one dict per gambit slot, `{enable: String, do: String, to: String, iff: String,
## extra: int}`, already stringified by the surface. An `inert: true` row is drawn DIM even
## under the glove and takes no chevron (ADR-0270's safety net); the widget still knows nothing
## about gambits — "inert" is a rendering answer, and which rows deserve it is the surface's
## question (see the class doc).
var row_entries: Array = []
## Which part of the focused row carries the chevron. Ignored outside row mode.
var focused_part: int = -1

## Build HERE instead of at the key location. The CHOICE list sets it, because its x is DERIVED
## from the column whose part it is serving (ADR-0268 dec. 1 — "the list opens under its own
## column") and a derived position cannot BE a key location: `gambitsurface.loc.*` names
## authored homes an F3 scrub moves, and a window that lands wherever the cursor is has no
## single home to scrub. Zero size = unset.
var container_override: Rect2 = Rect2()

## Namespace for this instance's four [UI3Element] ids. TWO of these menus are alive at once
## once a choice list is open — dec. 1 wants the row still legible BEHIND it — and a UI3Element
## id is a registry key, so two windows answering to `gambitsurface.window` is one element
## reading the other's stored rect. It renders as a perfectly drawn frame with NO TEXT IN IT,
## which is exactly what the first capture showed and what no layout assertion could have.
var id_prefix: String = "gambitsurface"

## Play the box-open on _ready (a host may disable it to boot settled, as the guards do).
@export var autoplay_open: bool = true

var _atlas: RangeTileAtlas
var _menu_text: UIMenuText
var _window: UI3Element
var _rows_elem: UI3Element
var _header_elem: UI3Element
var _cursor_elem: UI3Element

var _row_text_mats: Array[ShaderMaterial] = []
var _header_mats: Array[ShaderMaterial] = []
var _cursor_mats: Array[ShaderMaterial] = []
var _visible_names: Array[String] = []
var _content_built := false

var _glove_lit_pal: ImageTexture
var _glove_lit_pal_bg: ImageTexture      # §15.21 bg twin (0x7D7C → 0x7DFC) for the backgrounded glove
var _glove_shadow_pal: ImageTexture

var _lit_holder: Node3D
var _shadow_holder: Node3D
var _bob_frame: int = 0
var _bob_accum: float = 0.0
var _moving_frames: int = 0
var _idle_pairs: Array = []
var _select_pairs: Array = []

var _row := 0
var _scroll := 0
## §15.21 — true while another surface holds focus OVER this window.
var _backgrounded := false


static func _bind_location() -> void:
	TunePort.bind(LOC_GAMBIT, GAMBIT_CONTAINER, {"step": 1.0})


## The live container rect. Read through Tune so an F3 scrub moves the whole menu.
static func container() -> Rect2i:
	_bind_location()
	return Rect2i(TunePort.get_value(LOC_GAMBIT, GAMBIT_CONTAINER))


## The rect THIS instance builds at: [member container_override] when one was set, the key
## location otherwise. Every placement below goes through here rather than through
## [method container], so one window class serves both the row list at its authored home and
## the choice list under whichever column opened it.
func container_now() -> Rect2i:
	if container_override.size != Vector2.ZERO:
		return Rect2i(container_override)
	return container()


func _ready() -> void:
	_bind_location()
	_atlas = RangeTileAtlas.new()
	_menu_text = UIMenuText.new()
	_glove_lit_pal = _palette_from_colors(_atlas.menu_glove_lit_colors())
	_glove_lit_pal_bg = _palette_from_colors(UIWindowPalettes.BG_FOR_7D7C)
	_glove_shadow_pal = _palette_from_colors(_atlas.menu_glove_shadow_colors())
	_idle_pairs = GloveCursorBob.load_glove_pairs("glove_idle")
	_select_pairs = GloveCursorBob.load_glove_pairs("glove_select")
	_build_window()
	_build_content()
	if autoplay_open:
		play_open()
	_place_cursor()


# -----------------------------------------------------------------------------
# Window + rows/header/cursor elements (the ADR-0088 movable-origin triple).
# -----------------------------------------------------------------------------
## The rect answer for one of this menu's four elements. At the authored home it is the plain
## literal, which mints `<id>.rect` and the rest of the `<id>.*` knobs. Under a
## [member container_override] it is a HOST-DERIVED answer, which mints NOTHING.
##
## That difference is the whole of #1081. This menu is torn down and rebuilt on every press,
## always under the SAME four ids, and `Tune` is first-write-wins — so a literal rect made the
## SECOND list inherit the FIRST list's geometry (and its `name_x`, and its `pitch`) while its
## `authored_home` stayed its own. The two disagreed, `rel_world` compounded the delta, and the
## glyphs landed outside the window's own `OWN_APERTURE` scissor: a perfectly drawn EMPTY box
## at the previous list's position. See [method UI3Element.host_derived].
func _rect_answer(r: Rect2) -> Variant:
	if container_override.size == Vector2.ZERO:
		return r
	return UI3Element.host_derived(func() -> Rect2: return r)


func _build_window() -> void:
	var c := container_now()
	# The window answers WHERE by reference to its key location (ADR-0088 Amendment 2 §3):
	# scrubbing `gambitsurface.loc.window` re-places the whole menu. A menu carrying an
	# override answers HOST-DERIVED instead — see [member container_override] for why a
	# per-column list cannot ride the slug, and `_rect_answer` for why it cannot be a literal.
	var where: Variant = UI3Element.at(LOC_GAMBIT)
	if container_override.size != Vector2.ZERO:
		where = _rect_answer(Rect2(c))
	_window = UI3Element.new({
		"id": "%s.window" % id_prefix,
		"rect": where,
		"authored_home": Vector2(c.position),
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.STRIPE,
		"frame_center_patch": Vector4(6, 7, 21, 17),
		"frame_rp": RP_FRAME,
		"clip": UI3Element.Clip.OWN_APERTURE,
		# No aperture pad: unlike the two ROM pickers, whose baked tabs POKE ABOVE the window
		# and need the box-open reveal padded to carry them, this window's title sits INSIDE
		# its own top band. A poking title is what the ROM does because it has a window above
		# to tab against; this one opens under the Status stats panel, and a title above the
		# frame lands on that panel's bottom border. Measured on a capture, not reasoned.
		"aperture_pad": Vector4(0, 0, 0, 0),
		"depth_rung": -6,
		# ADR-0097 §2 — one cadence per VERB, and both are REQUIRED criteria: an element that
		# declares a beat must name a cadence for each verb it serves, or the spec assert fires
		# and the window builds NOTHING (which renders as a surface that opened onto an empty
		# screen, not as an error the player could report).
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
	})
	add_child(_window)
	_window.closed.connect(func() -> void: closed.emit())

	# rect and authored_home AGREE, and that is the whole of the 4-px cursor misalignment
	# (ADR-0255 Amendment 1). [method UI3Element.rel_world] subtracts `authored_home` while the
	# node itself sits at `rect`, so a rect of `c.y + 14` under a home of `c.y + 18` drew every
	# row glyph 4 px ABOVE the display coordinate it was handed — while the glove, whose element
	# has rect == home, landed where the formula said. Measured on `gambit_row.png`: the row-0
	# `○` inked at y 147-155 under a glove inked at 153-163.
	var rows_top := float(_rows_rect_in(c).position.y) + ROW0_TEXT_INSET_Y
	_rows_elem = UI3Element.new({
		"id": "%s.rows" % id_prefix,
		"rect": _rect_answer(Rect2(c.position.x, rows_top, c.size.x,
			float(c.position.y + c.size.y) - rows_top)),
		"authored_home": Vector2(float(c.position.x), rows_top),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
		"pitch": float(StartActionMenu.ROW_PITCH),
		"name_x": c.position.x + 12.0,
	})
	_window.add_child(_rows_elem)

	_header_elem = UI3Element.new({
		"id": "%s.header" % id_prefix,
		# y + 4 and not the + 3 it shipped at: the STRIPE frame's own top border inks at
		# `c.y + 2`, so a title at + 3 had its first glyph row eaten by the frame (photographed
		# on `ctrl_gambit.png`, before ADR-0255 Amendment 1 removed the row level's title
		# altogether — the IMPERATIVE level still wears one, and still has to clear the border).
		"rect": _rect_answer(Rect2(c.position.x + 8.0, c.position.y + 4.0, 96.0, 12.0)),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
		"title_label_x": c.position.x + 8.0,
		"authored_home": Vector2(float(c.position.x) + 8.0, float(c.position.y) + 4.0),
	})
	_window.add_child(_header_elem)

	# UNCLIPPED is a DECLARED answer: the glove pokes off the frame's LEFT edge, outside the
	# box-open scissor, and is drawn on top (the shared §15.20 model).
	_cursor_elem = UI3Element.new({
		"id": "%s.cursor" % id_prefix,
		# Shares the WINDOW's slug (ADR-0088 Amendment 4 §2) so a re-home moves the glove too.
		"rect": where,
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_cursor_elem.name = "GambitGloveCursor"
	_window.add_child(_cursor_elem)


func _build_content() -> void:
	for e: UI3Element in [_rows_elem, _header_elem, _cursor_elem]:
		for c in e.get_children():
			c.free()   # synchronous, mirroring the two ROM pickers' scrub rebuild
	_row_text_mats.clear()
	_header_mats.clear()
	_cursor_mats.clear()
	_visible_names.clear()
	_lit_holder = null
	_shadow_holder = null

	_build_header()
	_build_rows()
	_build_cursor()
	# A rebuild mints FRESH materials, which come up foreground by construction. Every path into
	# this function has to end backgrounded if the window is — including ↑/↓, which rebuilds on
	# every press in row mode — so the re-push belongs here and not at the one call site that
	# happens to change the flag.
	_apply_backgrounded_uniforms()
	_content_built = true


## The FONT.BIN title (see the class doc for why it is not a baked cell).
func _build_header() -> void:
	if title.is_empty():
		return
	var s := _header_elem
	var x := float(s.spec().get("title_label_x", s.authored_home().x))
	var y := s.authored_home().y
	# INKS and not the `backgrounded` uniform, because this title is FONT.BIN text
	# (`formation_font_opaque`), whose three output inks ARE its palette — unlike
	# [StartActionMenu]'s baked "Menu" tab, which is a sprite through a CLUT and swaps by uniform.
	# A `backgrounded` push here would be a silently ignored write to a uniform that does not
	# exist, which looks exactly like a working swap in the source and does nothing on screen.
	if _backgrounded:
		_menu_text.mount(s, title, s.rel_world(x, y) + s.z_for(RP_HEADER),
			RP_HEADER, s.ppu(), _header_mats, LIT_INKS_BG)
	else:
		_menu_text.mount(s, title, s.rel_world(x, y) + s.z_for(RP_HEADER),
			RP_HEADER, s.ppu(), _header_mats)


func _build_rows() -> void:
	if not row_entries.is_empty():
		_build_gambit_rows()
		return
	var s := _rows_elem
	var row0_y := s.authored_home().y
	var pitch := float(s.spec().get("pitch", 16.0))
	var name_x := float(s.spec().get("name_x", s.authored_home().x))
	for i in range(_scroll, mini(entries.size(), _scroll + VISIBLE_ROWS)):
		var nm := entries[i]
		var y := row0_y + (i - _scroll) * pitch
		# The plain list carries no shade band, so it asks for inks ONLY when backgrounded —
		# passing them unconditionally would replace [UIMenuText]'s own foreground default with a
		# restatement of it, which is a second place for the list's colour to be wrong.
		if _backgrounded:
			_menu_text.mount(s, nm, s.rel_world(name_x, y) + s.z_for(RP_ROW_TEXT),
				RP_ROW_TEXT, s.ppu(), _row_text_mats, DIM_INKS_BG)
		else:
			_menu_text.mount(s, nm, s.rel_world(name_x, y) + s.z_for(RP_ROW_TEXT),
				RP_ROW_TEXT, s.ppu(), _row_text_mats)
		_visible_names.append(nm)


## One gambit per line, read across: `2 Cure   Weakest Ally   Their   HP<50% +1`.
##
## Three signals in three CHANNELS, which is the whole reason this is not five strings in one
## mount. The `○`/`×` mark says ENABLED; the shade band says WHICH ROW (LIT vs DIM, with the
## glove agreeing at the left edge); the chevron says WHICH PART. Collapse any two of them onto
## one channel and a disabled row becomes indistinguishable from an unfocused one — which is
## exactly what the shade-only draft did, photographed before this one was written.
func _build_gambit_rows() -> void:
	var s := _rows_elem
	var row0_y := s.authored_home().y
	var pitch := float(s.spec().get("pitch", 16.0))
	for i in range(_scroll, mini(row_entries.size(), _scroll + VISIBLE_ROWS)):
		var r: Dictionary = row_entries[i]
		var y := row0_y + (i - _scroll) * pitch
		var focused := i == _row
		# `inert` beats focus. The LIT band says "this is the row the glove is on"; an inert row
		# is one the glove can rest on and do nothing to, so lighting it would promise a press
		# that is refused. DIM under the glove is the only shade that says both things at once.
		var inert := bool(r.get("inert", false))
		var inks := _inks_for(focused, inert)
		# A row the surface hands over as a PLAIN string (the imperative's, which is an order and
		# not a sentence) is rendered as one — the level's fifth row is not a fifth slot, and
		# forcing it into four columns would say it was.
		if r.has("text"):
			_mount_part(s, String(r["text"]), COL_ENABLE_X, y, inks, 0.0)
			_visible_names.append(String(r["text"]))
			continue
		# `[x, text, cap, part]`, and `part` is CARRIED rather than being the loop index. The
		# leftmost column is the slot NUMBER, which the cursor does not stop on (ADR-0268
		# dec. 13), so column position and part index stopped agreeing the moment ENABLE stopped
		# being a part — a loop index here would aim the chevron one column left of the part it
		# names, on every row, and still render perfectly.
		# `if_disabled` — the row declared `Always`, so its `If` column is still DRAWN and still
		# in its own lane, but dim and unreachable. The cell shows the predicate `Always` parked
		# (`GambitSurface._write_if_cell`), so what goes dim is a real value the player can get
		# back, not a placeholder.
		var if_disabled := bool(r.get("if_disabled", false))
		var cols := [
			[COL_ENABLE_X, String(r.get("enable", "")), 0.0, NOT_A_PART],
			[COL_DO_X, String(r.get("do", "")), COL_DO_CAP, PART_DO],
			[COL_TO_X, String(r.get("to", "")), COL_TO_CAP, PART_TO],
			[COL_SUBJ_X, String(r.get("subj", "")),
				COL_SUBJ_DISABLED_CAP if if_disabled else COL_SUBJ_CAP, PART_SUBJ],
			[COL_IF_X, String(r.get("iff", "")), COL_IF_CAP, PART_IF],
		]
		# THE SLOT NUMBER AND `Do`'S CHEVRON SHARE ONE LANE, and that sharing is what pays for
		# the fourth column. Both want the 10 px at x=22: the number is a per-row readout and
		# the chevron appears on exactly one part of exactly one row, so the two are never
		# wanted at the same x at the same time. Giving them a lane each costs 10 px the row
		# does not have (see the budget above); sharing costs the focused row's number, on the
		# one row the glove is already resting on.
		var do_focused := focused and not inert and focused_part == PART_DO
		for col: Array in cols:
			var x: float = col[0]
			var part: int = col[3]
			if part == NOT_A_PART and do_focused:
				continue   # the chevron below is standing in this column's lane
			# The chevron only on the focused row's focused part, and never on the number
			# column — it names no part, and the glove is already resting at the frame's left
			# edge immediately to its left.
			if focused and not inert and part != NOT_A_PART and part == focused_part:
				_mount_part(s, PART_CHEVRON, x - CHEVRON_W, y, inks, 0.0)
			# THE DISABLED CELL PAINTS IN THE DIM BAND WHATEVER THE ROW IS DOING. `inks` is the
			# ROW's band, so on the focused row every cell is LIT — and an `Always` row's `If`
			# cell must not be, because it holds a predicate that is set aside rather than
			# applied. `_inks_for(false, ...)` and not the `DIM_INKS` literal, so the
			# backgrounded twin (§15.21) comes along for free.
			#
			# ⚠️ On an UNFOCUSED row this distinction is invisible — the whole row is already
			# dim, and the ROM's shade band gives this window two shades, not three. The
			# SUBJECT column carries the reading there: `Always` is the word that says the
			# fourth column does not apply, and it is the leftmost of the two.
			var cell_inks := _inks_for(false, inert) if (if_disabled and part == PART_IF) \
				else inks
			_mount_part(s, String(col[1]), x, y, cell_inks, float(col[2]))
		var extra := int(r.get("extra", 0))
		if extra > 0:
			var mark := "+%d" % extra
			_mount_part(s, mark, PLUS_RIGHT_X - _menu_text.measure(mark), y, inks, 0.0)
		_visible_names.append(row_text(i))


## The ink band a row paints in — TWO independent questions, asked in order, and neither can be
## folded into the other.
##
## `inert` beats focus (ADR-0270), and BACKGROUNDED is orthogonal to both: it says "another
## surface has focus over this window", which is true of every row at once, while lit-vs-dim says
## WHICH ROW inside this window. Collapsing them — backgrounding by dimming — would make the
## focused row of a backgrounded window indistinguishable from an unfocused row of a foreground
## one, which is the same failure the shade-only chevron draft had (see [method
## _build_gambit_rows]). The band is picked in the foreground vocabulary first and then swapped
## to its §15.21 twin, so the two answers survive as two.
func _inks_for(focused: bool, inert: bool) -> Array[Color]:
	var lit := focused and not inert
	if _backgrounded:
		return LIT_INKS_BG if lit else DIM_INKS_BG
	return LIT_INKS if lit else DIM_INKS


## §15.21 "send window to background": swap the WHOLE menu — frame, row glyphs, title and glove —
## to its deactivated blue-grey CLUTs, or back. Ported from [method
## StartActionMenu.set_backgrounded], which is the RE-grounded original; this window was the only
## menu in the family that skipped it, so a choice list opened over the row left the row window
## looking exactly as focused as the list.
##
## A DISCRETE per-index CLUT swap, not an alpha tint. Idempotent. The row glyphs cannot be swapped
## by a uniform here because their inks are baked at mount time, so the rows REBUILD — which is
## what this widget already does on every ↑/↓ (see [method _on_selection_moved]), so it is the
## idiom rather than a new cost.
func set_backgrounded(on: bool) -> void:
	if _backgrounded == on and _content_built:
		return
	_backgrounded = on
	var v := 1.0 if on else 0.0
	if _window != null and is_instance_valid(_window):
		var frame_mat := _window.chrome_material()
		if frame_mat != null:
			frame_mat.set_shader_parameter("backgrounded", v)   # nine-slice fg→bg remap
	if _content_built:
		# Rebuilds the rows AND the title in the other ink vocabulary, and re-pushes the glove's
		# uniform through `_apply_backgrounded_uniforms` at its tail.
		_build_content()


func is_backgrounded() -> bool:
	return _backgrounded


## Re-push the §15.21 uniform onto the materials a rebuild just replaced. Called from the tail of
## [method _build_content], so no rebuild path can drop the state.
func _apply_backgrounded_uniforms() -> void:
	var v := 1.0 if _backgrounded else 0.0
	for m in _cursor_mats:
		m.set_shader_parameter("backgrounded", v)   # glove lit swaps; subtractive shadow no-ops


## Show or hide the glove. A backgrounded window's cursor is REMOVED, not frozen: the ROM's answer
## to "two live cursors on screen" is that only the focused surface has one at all, which is a
## stronger statement than a glove that has merely stopped bobbing. [method
## StartActionMenu.set_cursor_visible] is the original.
func set_cursor_visible(on: bool) -> void:
	if _cursor_elem != null and is_instance_valid(_cursor_elem):
		_cursor_elem.visible = on


func cursor_visible() -> bool:
	return _cursor_elem != null and is_instance_valid(_cursor_elem) and _cursor_elem.visible


## Mount one column's text, elided to `cap` px if it overruns (cap 0 = no cap). The elision is
## the `Do` column's alone in practice: 21 of the 228 action-ability names measure wider than
## [constant COL_DO_CAP], and the full name is one ○ away in that part's own list.
func _mount_part(s: UI3Element, text: String, x: float, y: float, inks: Array[Color],
		cap: float) -> void:
	if text.is_empty():
		return
	var shown := _elide(text, cap) if cap > 0.0 else text
	_menu_text.mount(s, shown, s.rel_world(x, y) + s.z_for(RP_ROW_TEXT),
		RP_ROW_TEXT, s.ppu(), _row_text_mats, inks)


## `text` trimmed until it plus the elision mark fits `cap` px. Character-wise and not by a
## ratio, because the font is PROPORTIONAL — "VerticalJump8" and "DiamondSword" are the same
## character count and 4 px apart.
func _elide(text: String, cap: float) -> String:
	if _menu_text.measure(text) <= cap:
		return text
	var mark_w := _menu_text.measure(ELIDE)
	var out := text
	while out.length() > 1 and _menu_text.measure(out) + mark_w > cap:
		out = out.substr(0, out.length() - 1)
	return out + ELIDE


## What row `i` READS as one string — the guard seam, and what `visible_row_names()` reports in
## row mode. Uncapped on purpose: a guard asserting the row's CONTENT must not be reading the
## elision, and a guard asserting the elision asks [method _elide] directly.
func row_text(i: int) -> String:
	if i < 0 or i >= row_entries.size():
		return ""
	var r: Dictionary = row_entries[i]
	if r.has("text"):
		return String(r["text"])
	# FIVE fields always — the `If` column is drawn on every row, disabled or not. A DISABLED
	# cell is bracketed, because `row_text` is what guards and `visible_row_names()` score and
	# the dim PALETTE is the one thing a string cannot carry: without the brackets an `Always`
	# row and a live one read identically here, and a guard asserting the disable would have
	# nothing to assert against.
	var iff := String(r.get("iff", ""))
	if bool(r.get("if_disabled", false)):
		iff = "(%s)" % iff
	var out := "%s %s / %s / %s / %s" % [r.get("enable", ""), r.get("do", ""),
		r.get("to", ""), r.get("subj", ""), iff]
	var extra := int(r.get("extra", 0))
	return out + (" +%d" % extra if extra > 0 else "")


func _build_cursor() -> void:
	_shadow_holder = _mount_glove(_atlas.menu_glove_shadow_rect(), _glove_shadow_pal, _SHADOW_SHADER, RP_CURSOR_SHADOW)
	_lit_holder = _mount_glove(_atlas.menu_glove_lit_rect(), _glove_lit_pal, _SPRITE_SHADER, RP_CURSOR_LIT)
	_place_cursor()


func _mount_glove(cell: Rect2, palette: ImageTexture, shader_path: String, rung: int) -> Node3D:
	var holder := Node3D.new()
	_cursor_elem.add_child(holder)
	if _atlas.texture == null or cell.size == Vector2.ZERO:
		return holder
	var folded := shader_path == _SHADOW_SHADER and Fold.owns()
	# The LIT glove carries its §15.21 bg twin; the subtractive shadow ignores the uniform (its
	# shader never samples a palette), which is why only one of the two is armed.
	var pal_bg := _glove_lit_pal_bg if shader_path == _SPRITE_SHADER else null
	var mat := _sprite_mat(cell, palette, shader_path, rung, pal_bg)
	if folded:
		mat.shader = _SHADOW_FOLD_SHADER
	_cursor_mats.append(mat)
	var mi := _quad(cell.size)
	mi.material_override = mat
	mi.position += _window.z_for(rung)
	holder.add_child(mi)
	if folded:
		Fold.add(mi, mat, DepthMode.rung_z(rung))
	return holder


# -----------------------------------------------------------------------------
# Row model + navigation (the shared ROM list-menu model).
# -----------------------------------------------------------------------------
func selected_row() -> int:
	return _row


func row_count() -> int:
	return row_entries.size() if not row_entries.is_empty() else entries.size()


func scroll() -> int:
	return _scroll


## Re-render the rows in place — the surface calls this after an edit so the slot list shows
## the sentence the player just changed without tearing the window down and re-opening it.
func set_entries(next: Array[String]) -> void:
	entries = next
	_reflow()


## The row-mode sibling of [method set_entries]: re-render the gambit rows in place after an
## edit, so the row the player just changed reads it back without the window tearing down and
## re-opening. `part` re-aims the chevron in the same repaint, because ←/→ and ○ both land here.
func set_row_entries(next: Array, part: int) -> void:
	row_entries = next
	focused_part = part
	_reflow()


func _reflow() -> void:
	var count := row_count()
	if _row >= count:
		_row = maxi(0, count - 1)
	_scroll = clampi(_scroll, 0, maxi(0, count - VISIBLE_ROWS))
	if _content_built:
		_build_content()
	_place_cursor()


func move_down() -> void:
	if row_count() == 0:
		return
	_row = (_row + 1) % row_count()
	_on_selection_moved()


func move_up() -> void:
	if row_count() == 0:
		return
	_row = (_row - 1 + row_count()) % row_count()
	_on_selection_moved()


func _on_selection_moved() -> void:
	_moving_frames = GloveCursorBob.glove_period(_select_pairs)
	_bob_frame = 0
	var new_scroll := _scroll
	if _row < _scroll:
		new_scroll = _row
	elif _row >= _scroll + VISIBLE_ROWS:
		new_scroll = _row - VISIBLE_ROWS + 1
	var scrolled := new_scroll != _scroll
	_scroll = new_scroll
	# REBUILT ON EVERY MOVE IN ROW MODE, not only when the window scrolled. ADR-0268 dec. 1 gives
	# the LIT/DIM band the job of saying WHICH ROW, "with the glove agreeing at its left edge" —
	# and the shade is baked into the row meshes at build time, so a move that only re-placed the
	# glove left the band on the row the player had LEFT. Photographed: the glove on the last row
	# with the first row still lit and still carrying the chevron. ←/→ never showed it, because
	# `set_row_entries` rebuilds anyway.
	#
	# The plain-entries mode has no shade band and no chevron, so it keeps the old
	# rebuild-on-scroll-only cost.
	if _content_built and (scrolled or not row_entries.is_empty()):
		_build_content()
	_place_cursor()
	selection_changed.emit(_row)


func confirm() -> void:
	chosen.emit(_row)


func cancel() -> void:
	cancelled.emit()


func play_open(cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	if _cursor_elem != null and is_instance_valid(_cursor_elem):
		_cursor_elem.visible = true
	if _window != null and is_instance_valid(_window):
		_window.open(cadence)


func play_close(cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	if _cursor_elem != null and is_instance_valid(_cursor_elem):
		_cursor_elem.visible = false
	if _window != null and is_instance_valid(_window):
		_window.close(cadence)


func window() -> UI3Element:
	return _window


# -----------------------------------------------------------------------------
# Glove cursor placement + bob (§15.20). Bob axis = X, anchored on the frame's LEFT edge.
# -----------------------------------------------------------------------------
## The glove display top-left for `row` at settled bob 0 — pure, so a guard can assert it.
##
## Answers about the ROW level, which is the one at the authored home and the one that wears no
## title: its rows start at the container's own top, so the drop is zero.
static func cursor_anchor_for(row: int) -> Vector2:
	return StartActionMenu.cursor_display_pos_in(container(), row, 0)


## The rect the glove/rows are laid out in: the window container dropped by the title band, so
## row 0's glove rests on row 0's text rather than on the title. At the ROW level the band is
## ZERO — that level wears no title (ADR-0255 Amendment 1) — and so is it for the two choice
## lists, which never wore one. Only the IMPERATIVE level still pays the 8 px.
func _rows_rect_in(c: Rect2i) -> Rect2i:
	var band := int(title_band())
	return Rect2i(c.position.x, c.position.y + band, c.size.x, c.size.y - band)


## The top band this instance's title occupies, display px. A titled window pays it; an
## untitled one does not, and collapsing it is what recovers the row budget the "Gambit" title
## was spending on a word the player did not need (ADR-0255 Amendment 1).
func title_band() -> float:
	return 0.0 if title.is_empty() else TITLE_BAND


func cursor_bob_x() -> int:
	var pairs := _select_pairs if _moving_frames > 0 else _idle_pairs
	return GloveCursorBob.glove_offset_for_frame(pairs, _bob_frame)


func cursor_display_pos() -> Vector2:
	return StartActionMenu.cursor_display_pos_in(
		_rows_rect_in(container_now()), _row - _scroll, cursor_bob_x())


func _place_cursor() -> void:
	if _lit_holder == null or not is_instance_valid(_lit_holder):
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
# Sprite helpers (the shared index->CLUT sprite mechanism).
# -----------------------------------------------------------------------------
func _sprite_mat(cell: Rect2, palette: ImageTexture, shader_path: String, rung: int,
		palette_bg: ImageTexture = null) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.set_shader_parameter("index_atlas", _atlas.texture)
	mat.set_shader_parameter("atlas_size", Vector2(_atlas.texture.get_width(), _atlas.texture.get_height()))
	mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y))
	mat.set_shader_parameter("palette_tex", palette)
	if palette_bg != null:
		mat.set_shader_parameter("palette_bg_tex", palette_bg)
		mat.set_shader_parameter("backgrounded", 0.0)   # armed, foreground until told otherwise
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
## The per-glyph row-text materials mounted for the visible rows.
func row_text_materials() -> Array:
	return _row_text_mats


## The per-glyph TITLE materials. Non-empty and FONT-shaped is the assertion — this window's
## title is glyphs, not a baked atlas cell (class doc).
func header_text_materials() -> Array:
	return _header_mats


## The glove cursor materials (lit + shadow) — UNCLIPPED, on top.
func cursor_materials() -> Array:
	return _cursor_mats


## The row strings rendered in the current visible window (top -> bottom).
func visible_row_names() -> Array:
	return _visible_names
