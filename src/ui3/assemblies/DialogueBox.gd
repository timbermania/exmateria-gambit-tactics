@tool
class_name DialogueBox
extends Node3D
## FFT 3-line portrait dialogue box (event opcode `0x10`, Dialog=`0x1X`/`0x9X`,
## and `0x7X`→`0x1X`). The boxed counterpart to the 2D `DialogueOverlay`
## (Dialog=`0x09` prayer); both share the renderer-agnostic
## `TypewriterController`. Built on the ui3 substrate: `UIFrame` (9-slice box)
## + `UIPortrait` (speaker face) + `UIText` (body) + a speaker triangle quad.
##
## Origin is TOP-LEFT (matches every ui3 element); the box lays out from (0,0)
## rightward/downward. The caller positions THIS node in screen-space to follow
## the speaking unit (the box auto-sizes to its text).
##
## RE source of truth: research/working_documents/scenario_1_captures/
## boxed_dialog_decode.md + dialogue_box_geometry_and_fidelity_decode.md (geometry
## constants, with battle.bin addresses). Sizing/triangle/portrait/advance grounded:
##   - height = FORCED 3 lines*16 + 16 chrome = 64px (the ROM's arrow/tail term
##     extends the box bitmap for its IN-box tail; we draw the tail externally so
##     the frame stays 64); width = text + 0x18, or +0x38 with a portrait. Text
##     top inset 8.
##   - frame chrome = FRAME.BIN (40,0,32,32), 9-slice uniform 8px, tiled center.
##   - triangle: 16x16, FRAME (88,0)=up (box below unit) / (88,16)=down (box
##     above unit); h-flip by unit side; dst-X tracks the unit, clamped
##     [0x10, width-0x10].
##   - portrait: speaker SPR portrait sampled 31px wide, top inset 7 (15 when
##     align==2); right-dock faces left; side follows the unit sign.
##   - advance = CROSS/confirm; the VM halts until pressed.
##   - header/body = a mid-string {Color 08}/{Color 00} swap (one text object).
##
## Vault: [[Dialogue Box Geometry]]
## Vault: [[Dialogue Font Palette]]
## Vault: [[Dialogue Pagination]]
## Vault: [[Display Message Opcode]]
## Vault: [[Event Dialogue Portrait System]]
## Vault: [[Typewriter Text Cadence]]

## ADR-0211 dec. 4 — the host autoload `PSXDisplay` is not nameable from inside an
## addon (every stranger rig declares an empty `[autoload]` block), so UI PAR is
## read and subscribed through the platform port. #1263 / ADR-0308.
const DisplayPort = ExMateriaPlatform.DisplayPort

## Display-space fold handles (ADR-0074/0191): `Fold.owns()` is the BUILD predicate and
## `Fold.add` the enrolment decorator; `DepthMode.rung_z` turns a painter's rung into the
## fold-order key. Reached through the addon's one global façade (ADR-0212 dec. 1).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

const TRIANGLE_UP_PATH := "res://assets/ui/dialog_triangle_up.tga"
const TRIANGLE_DOWN_PATH := "res://assets/ui/dialog_triangle_down.tga"

# --- RE constants (boxed_dialog_decode.md / dialogue_box_geometry_decode.md) --
const LINE_HEIGHT_PX := 16
const BOX_CHROME_PX := 16          # height = lines*16 + 16 (+ arrow term)
## The 0x1X/0x9X box FORCES 3 lines regardless of the actual {Newline} count
## (battle.bin 0x80130ae0). Height always assumes 3 lines.
const FORCED_LINES := 3
## ROM arrow/tail height term (battle.bin 0x80130b24..b54): Dialog & 0xC == 0
## (arrow) → +8; == 4 (thinking bubble) → +16; == 8 (no tail) → +0. The ROM grows
## the box bitmap by this to hold an IN-box tail. We draw the tail as a separate
## external quad, so these are documented-but-unused for OUR frame height (the
## frame is a flat 64px; see `_recompute_size`). Kept for RE reference.
const ARROW_EXTRA_DEFAULT_PX := 8     # cc==0
const ARROW_EXTRA_BUBBLE_PX := 16     # cc==4
const WIDTH_PAD_PX := 0x18         # text + 24 (no portrait)
## Text + 56 when a portrait is docked. The ROM reserves 0x40 (64); we trim to
## 0x38 (56) so the docked portrait sits ~3px off the right border instead of
## ~9px — the extra ROM slack read as too much right margin (refinement
## 2026-06-27). Right region = 6px text-gap + 31px portrait + 3px gap + 8px border.
const WIDTH_PAD_PORTRAIT_PX := 0x38  # text + 56 (portrait present)
const TEXT_INSET_PX := 8           # inner text X = box_left + 8 …
const TEXT_INSET_PORTRAIT_PX := 0x30  # … or box_left + 48 when portrait on left
## Text top inset = box_top + 8 (battle.bin 0x80131370). The ROM adds +8 more
## (→16) for the upward-tail/bottom-anchored case (align local_ce==2, 0x801313e4)
## to clear the tail region that the ROM draws INSIDE the box top. We render the
## speaker triangle as a SEPARATE quad ABOVE the frame (not eating into the
## interior), so that +8 double-counts and reads as too much top margin — we
## drop it back to 8 (refinement 2026-06-27).
const TEXT_TOP_INSET_PX := 8
const TEXT_TOP_INSET_CE2_PX := 8
const PORTRAIT_INSET_PX := 8       # portrait left  = box_left + 8
## Portrait right-dock left edge = box_left + width − 0x2A (42). The ROM docks at
## width − 0x30 (48), leaving a ~9px gap to the right border; trimmed to 0x2A so
## the portrait sits ~3px off the inner border (refinement 2026-06-27).
const PORTRAIT_RIGHT_INSET_PX := 0x2A  # portrait right = box_left + width - 42
## Portrait top inset = box_top + 7 (battle.bin 0x801311ac). The ROM's +8 (→15)
## for local_ce==2 (0x801311c8) compensates for the same in-box upward tail the
## text inset does; since we draw the triangle externally we drop it back to 7 so
## the portrait tracks the text top (refinement 2026-06-27).
const PORTRAIT_TOP_INSET_PX := 7
const PORTRAIT_TOP_INSET_CE2_PX := 7
## ROM samples the portrait 31px wide (0x1F at 0x80131218), one column trimmed
## from the 32-wide rotated SPR, so the 31×48 quad clears the 8px right border.
const PORTRAIT_SAMPLE_WIDTH_PX := 31
## Beveled dialog frame chrome: FRAME.BIN sprite (40,0,32,32), 9-slice uniform
## 8px margins, 16×16 tiled center (battle.bin FUN_8014c18c/FUN_8014c758). The
## shared UIFrame default is the flat menu-tile crop; this is the dialog override.
const DIALOG_FRAME_REGION := Vector4(40, 0, 32, 32)
const DIALOG_FRAME_MARGINS := Vector4(8, 8, 8, 8)
const TRIANGLE_PX := 16
const TRIANGLE_CLAMP_MARGIN_PX := 0x10  # dst-X clamp [0x10, width-0x10]
## Seat the triangle's base bar onto the frame border. The arrow textures carry
## 2-3px of transparent padding on the box-facing side, so the bar floated ~4px
## off the 72px frame's edge at overlap=4; bumped to 9 so it sits flush on (and
## slightly into) the border (refinement 2026-06-27, R4).
const TRIANGLE_EDGE_OVERLAP_PX := 8     # seat the triangle bar on the frame border
## FFT's dialog renderer special-cases the space glyph to a 4px advance
## (`0x80132578..0x80132588`), ignoring the per-char width table's 0x0A=10.
## Mirror of DialogueOverlay._SPACE_PSX_WIDTH so box spaces match the overlay.
const SPACE_WIDTH_PX := 4.0

## Dialog-byte arrow flag: 0x8 = remove arrow entirely.
const DIALOG_ARROW_REMOVE := 0x8

## Box OPEN (grow) / CLOSE (shrink) tween (living doc Part B / §C.2). On open the
## ROM grows the box+portrait quads from the speaker-triangle point to the full
## rect; on close it shrinks them back with curve 4. Each curve entry is HELD for
## `tween_frames_per_entry()` vsyncs — the earlier "one entry per 60 Hz frame"
## reading is REFUTED. The 5 curves are STATIC data in BATTLE.BIN — parsed
## deterministically into `assets/ui/dialogue_box_curves.json` (do NOT hardcode).
## OPEN curve = OpenType (payload +0xE) & 0xf; CLOSE = curve 4. Overshoot curves
## (0/1) exceed 1.0 mid-anim → the box bounces past full, which the scale
## reproduces directly. See parse_dialogue_box_curves.py.
const CURVES_PATH := "res://assets/ui/dialogue_box_curves.json"
const CLOSE_CURVE_INDEX := 4

## The ROM's global text-speed throttle `event_text_glyph_throttle @0x80165F88`,
## whose stored default is **1** (the disassembly annotates the two loads at
## `0x80132c90` / `0x80132d78` `= 00000001h`). The tween driver re-reads it on
## every curve entry and holds that entry for `3 − throttle` vsyncs.
##
## ⚠ This is deliberately NOT the `throttle` export above. That field is the
## TYPEWRITER's, and the boxed consumer sets it to **2** as a documented net-cadence
## FUDGE (our 1-glyph-per-sleep walker vs the PSX's paired 2-glyph reveal — see the
## `throttle` doc and TYPEWRITER_TEXT_CADENCE.md §7.1). The tween has no such pairing
## to compensate for, so feeding it the fudged 2 would give factor 1 and reproduce the
## very "2× too fast" bug this const exists to fix. `{75}/{76}` Set Text Speed is not
## wired in our port, so the ROM value is pinned here rather than read from the VM.
##
## At `throttle >= 3` the `blez` @ `0x80132c9c` skips the inner loop entirely — no
## `event_fiber_yield`, no corner-lerp — so the whole curve is consumed inside one
## frame and the box SNAPS open with no animation. Unreachable while this is 1;
## recorded so a future Set Text Speed wiring knows the edge exists.
const ROM_TEXT_GLYPH_THROTTLE := 1

const _TWEEN_IDLE := 0
const _TWEEN_OPEN := 1
const _TWEEN_CLOSE := 2

# --- Pagination + animated page-turn "more" icon -----------------------------
## The kind-0x10 box is a FIXED 3-line window (decode §1.1). A message longer
## than the window pages: **page 1 = name line + first 2 dialogue lines; page ≥2
## = up to 3 dialogue lines, name row dropped (portrait persists)**. Line breaks
## come from `{Newline}`. O/Circle advances a page in place; the box closes only
## after the last page's advance. RE:
## research/working_documents/scenario_1_captures/dialogue_pagination_and_page_icon_decode.md
const PAGE_WINDOW_LINES := 3
## Dialogue-line budget on page ≥2 (whole window) and on page 1 (window minus the
## name row).
const PAGE_LINES_WITH_NAME := PAGE_WINDOW_LINES - 1   # page 1: 2 dialogue lines
const PAGE_LINES_NO_NAME := PAGE_WINDOW_LINES          # page ≥2: 3 dialogue lines

## Animated page-turn "more" icon (decode §3.4). A 4-phase page-corner-curl loop
## sampled from the shared RANGETILE index atlas, drawn as a SEPARATE quad over
## the (static) box at its bottom-right while a NEXT page is pending — matching
## PSX, where the icon is a per-frame OT primitive over an un-re-uploaded box.
## Cells + atlas path are the ISO-verified metadata in assets/ui/page_turn_icon.json.
const PAGE_ICON_META_PATH := "res://assets/ui/page_turn_icon.json"
## Reuse the RANGETILE index/CLUT sprite shader (index-as-gray → 16-colour CLUT).
## This is the OPAQUE half of the icon — it keys on STP=0 texels only.
const PAGE_ICON_SHADER_PATH := "res://src/ui3/shaders/vitals_sprite.gdshader"
## ...and the SUBTRACTIVE half. On PSX the whole icon is ONE primitive at tpage
## 0x5F (abr=2) with ABE on, so its STP=0 texels land opaque while its STP=1
## texels subtract from the framebuffer. Godot has no per-texel blend mode, so
## the one ROM prim splits into two quads over the same rect with COMPLEMENTARY
## alpha keys — the established mixed-STP pattern (`formation_orb_opaque` +
## `formation_orb`; the glove's lit pass + `menu_cursor_shadow`). Unlike the
## glove the two halves never overlap, so no depth-occlusion trick is needed.
const PAGE_ICON_SHADOW_SHADER_PATH := "res://src/ui3/shaders/menu_cursor_shadow.gdshader"
## ...and its FOLD twin, which is the one that is actually CORRECT. PSX subtracts in the
## 8-bit framebuffer — DISPLAY (gamma-encoded) space. Godot's main target is LINEAR, so the
## in-scene `blend_sub` above subtracts a display-magnitude constant from a linear value and
## over-darkens by up to 34/255 on a tan background. The engine fold exists to solve exactly
## this (ADR-0074): it seeds a DISPLAY-space scratch from the opaque scene, runs the hardware
## sub THERE, then resolves back to linear + RGB555. Folded, this pass IS the ROM's abr=2.
## `Fold.shader()` picks the twin on the build predicate; off-fork we fall back in-scene.
## PRELOADED as a Shader, never named as a String: a load() of a mistyped path returns null, a
## null shader does not raise, and the fold "just stops, with no error" (ADR-0191 dec. 2).
const PAGE_ICON_SHADOW_FOLD_SHADER := preload("res://src/ui3/shaders/menu_cursor_shadow_fold.gdshader")
## Icon inset from the box's inner bottom-right corner (px from the border to the
## icon's right / bottom edge).
const PAGE_ICON_RIGHT_INSET_PX := 5
const PAGE_ICON_BOTTOM_INSET_PX := 5
## Gap (px) between a right-docked portrait's left edge and the page-turn icon
## when both share the box — the icon sits left of the portrait, right of text.
## (No PSX reference has a portrait + more-icon together; the user's verbal spec
## governs — handoff Issue #1.)
const PAGE_ICON_PORTRAIT_GAP_PX := 2
## The icon's 16-colour CLUT. The exact ROM CLUT is unpinned (selector
## DAT_8016dafc is write-only in the Ghidra export, decode §3.4); the curl sits in
## the RANGETILE HUD-label region just above Hp/Mp/Ct, so it shares the shared
## menu/label CLUT (0x7cbc — the same one UIUnitInfoWindow renders those labels
## through). idx 5 = outline, 8/9/12 = cream body/dither, 14/15 = dark drop-shadow.
##
## Read from the extractor (RANGETILE.json `window_tabs.colors`, via
## RangeTileAtlas.window_tab_colors()) rather than re-typed here. That is not
## just DRY: the extractor keeps each entry's PSX **STP bit** in the alpha byte,
## and the only two words of 0x7cbc carrying bit 15 are exactly the drop-shadow
## pair — idx 14 = 0x94a5 (41,41,41) and idx 15 = 0x8842 (16,16,16), both a=128.
## A hardcoded array wrote them a=255, which dropped the STP bits and rendered
## the shadow as an opaque black blob down the icon's right/bottom edges.
static var _page_icon_clut_cache: Array = []

# Parsed curve cache: int index → PackedFloat32Array of `t` fractions. Loaded
# once (shared across every box instance); fails LOUD if the asset is absent.
static var _curves_by_index: Dictionary = {}
static var _curves_loaded: bool = false


# Load the ROM-parsed open/close curves. Anti-silent-failure contract (§C.2b):
# push_error + refuse to fake a fallback curve if the JSON is missing/empty —
# mirrors ScenarioVM.gd's cinematic_seq.json guard. A missing asset degrades to
# "box appears at full size instantly" (no fake linear tween) with a loud error.
static func _load_curves() -> Dictionary:
	if _curves_loaded:
		return _curves_by_index
	_curves_loaded = true
	if not FileAccess.file_exists(CURVES_PATH):
		push_error("[DialogueBox] dialogue_box_curves.json MISSING — box open/close " +
			"has no curve data. Run: uv run python tools/parse_dialogue_box_curves.py " +
			"(or bash tools/bootstrap_assets.sh)")
		return _curves_by_index
	var f := FileAccess.open(CURVES_PATH, FileAccess.READ)
	if f == null:
		push_error("[DialogueBox] dialogue_box_curves.json unreadable — box open/close disabled.")
		return _curves_by_index
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary) or not (data.get("curves") is Array):
		push_error("[DialogueBox] dialogue_box_curves.json malformed (no 'curves' array). " +
			"Re-run: uv run python tools/parse_dialogue_box_curves.py")
		return _curves_by_index
	for c in data["curves"]:
		if c is Dictionary and c.has("index") and (c.get("t") is Array):
			var arr := PackedFloat32Array()
			for v in c["t"]:
				arr.append(float(v))
			if not arr.is_empty():
				_curves_by_index[int(c["index"])] = arr
	if _curves_by_index.is_empty():
		push_error("[DialogueBox] dialogue_box_curves.json has no usable curves — box open/close disabled.")
	return _curves_by_index

signal typed_out   ## emitted when the typewriter finishes revealing the text
signal advanced    ## emitted when the player/caller advances past the box

## A REAL page turn happened (#1273). Emitted from `advance_page` AFTER its
## `has_more_pages` guard, which is the whole point of a separate signal.
##
## 🔴 DO NOT FOLD THIS INTO `advanced`. `advanced` is emitted by `advance()` — the
## player leaving the box — and this is emitted by `advance_page()`, the text rolling
## to the next page with the box still up. The two verbs are one word apart and mean
## opposite things, which is the best argument available for two signals. `SfxRouter`'s own cue row says the blip fires
## "on a real page turn (O/Circle)" and never on the final advance or box close, so
## reusing `advanced` would play a page-flip on every dismissal. That is exactly the
## trap `TileCursor.cursor_stepped` documents: inverting onto the broader signal
## would be "a behaviour change wearing a refactor's clothes".
signal page_turned

## One glyph was revealed by the typewriter (#1273). The host turns this into the
## "Text Typing" blip; `DialogueOverlay` already wires the SAME cue onto its OWN
## `TypewriterController.glyph_typed`, which is the evidence that the cue is host
## vocabulary and never belonged in here.
signal glyph_revealed

## World units per virtual pixel (ui3 screen-space convention: 0.04).
@export var pixels_per_unit: float = 0.04:
	set(value):
		if pixels_per_unit == value:
			return
		pixels_per_unit = value
		_request_layout_update()

## ROM-faithful palette = FRAME.BIN palette 0 (CONFIRMED DYNAMICALLY 2026-06-27,
## handoff_dialog_box_palette_RESOLVED.md). The boxed dialog font is ONE 16-color
## CLUT; the `{Color 00}` body run uses slots 1-3 (DARK ramp, stroke (49,41,32))
## and the `{Color 08}` speaker name uses slots 9-11 (a RED ramp, stroke
## (106,41,16)). The body renders the baked atlas directly; the speaker run is
## recolored to slots 9-11 via the shader's 3-level CUSTOM remap
## (UIText.set_char_clut_run). NO font_color tint: the speaker ramp is not a
## scalar multiple of the body ramp, so a tint can't reproduce it. Colors are
## sourced from the font's dialog_clut (the dump); these constants are the
## committed fallback if the meta predates it.
## Mapping: px1(stroke)=slot, px2(highlight)=slot+1, px3(AA)=slot+2.
const SPEAKER_STROKE := Color8(106, 41, 16)     # CLUT slot 9  (px1) — RED
const SPEAKER_HILITE := Color8(123, 74, 57)     # CLUT slot 10 (px2)
const SPEAKER_AA := Color8(139, 123, 106)       # CLUT slot 11 (px3)
const BODY_STROKE := Color8(49, 41, 32)         # CLUT slot 1  (px1) — DARK
const BODY_HILITE := Color8(82, 82, 65)         # CLUT slot 2  (px2)
const BODY_AA := Color8(131, 123, 106)          # CLUT slot 3  (px3)

## ROM text-speed throttle for the shared `TypewriterController`'s sticky-budget
## cadence (cost = `budget · (3 − throttle)`). Default **2** → factor 1, i.e. one
## glyph per VBlank for a budget-1 (no-leading-{Delay}) boxed message. This
## reproduces the ROM's *net* boxed cadence: the PSX reveal is PAIRED (2 glyphs
## then a ~2-VBlank pause ≈ 1.12 VBlanks/glyph net), and factor 1 on our
## 1-glyph-per-sleep walker matches that net rate — closer than the faithful
## factor-2 raw cost would be. See `TYPEWRITER_TEXT_CADENCE.md` §5/§7.1. Live
## clock drives reveal in _process; tests pin this explicitly.
@export var throttle: int = 2:
	set(value):
		throttle = clampi(value, 0, 3)
## Frames (60 Hz) per page-turn-icon animation phase. The PSX phase-counter
## increment rate isn't pinned (decode §3.4); ~7.5 Hz reads cleanly. Tunable.
@export var page_icon_frames_per_phase: int = 8:
	set(value):
		page_icon_frames_per_phase = maxi(1, value)

var _frame: UIFrame = null
var _portrait: UIPortrait = null
var _text: UIText = null
var _triangle: MeshInstance3D = null
var _triangle_material: StandardMaterial3D = null
var _triangle_up_tex: Texture2D = null
var _triangle_down_tex: Texture2D = null

var _typewriter: TypewriterController = null

# Active-show state
var _full_text: String = ""
var _char_palettes: PackedInt32Array = PackedInt32Array()  # per full_text char
var _revealed_full_len: int = 0
var _box_w_px: float = 0.0
var _box_h_px: float = 0.0
var _portrait_on_left: bool = false
var _has_portrait: bool = false
var _dialog_byte: int = 0         # the full Dialog byte (mode 0x70 nibble + flags)
var _align: int = 2               # Dialog & 0x3 (low-nibble local_ce); 2 = bottom-anchored
var _arrow_flags: int = 0         # Dialog & 0xC (local_cc); 0=arrow, 4=bubble, 8=none
var _show_arrow: bool = true
var _arrow_up: bool = true        # true = arrow UP (box below unit)
var _unit_offset_px: float = 0.0  # unit screen-X − box centre-X (signed)
# Tail horizontal MIRROR gate. PSX mirrors the speaker-triangle sprite ONLY when
# the authored arrow operand `msg[0x64] & 0xf0` is non-zero (decode §3 correction
# #2 / §1c: `sign(local_b8)` flips the PORTRAIT, NOT the tail). Every chapel line
# has `&0xf0 == 0`, so the tail there is ALWAYS base orientation — verified vs
# psx_box_zoom.png (Ovelia msg3 down-tail leans down-LEFT, unmirrored). Set once
# per show_dialog from `open_type`; consumed in `_layout_triangle`.
var _arrow_mirror: bool = false
var _active: bool = false

# --- Pagination (fixed 3-line window; decode §1.1) ---------------------------
# `_pages` is the per-page token arrays for the current message; `_page_idx` is
# the page on screen. Built once per show_dialog/swap_text; O/Circle advances it.
var _pages: Array = []
var _page_idx: int = 0

# --- Animated page-turn "more" icon (decode §3.4) ----------------------------
var _page_icon: MeshInstance3D = null
var _page_icon_material: ShaderMaterial = null
var _page_icon_shadow: MeshInstance3D = null          # the STP=1 subtractive half
var _page_icon_shadow_material: ShaderMaterial = null
var _page_icon_cells: Array = []          # Array[Vector4] atlas rects, one per phase
var _page_icon_atlas_path: String = ""
var _page_icon_phase: int = 0
var _page_icon_phase_accum: int = 0

var _layout_dirty: bool = false

# --- Open/close grow-shrink tween (Part B) -----------------------------------
# `_tween_scale` is the current fraction of full box size (1.0 = full, >1.0 =
# overshoot); OPEN drives it up the selected curve, CLOSE drives it down curve 4.
var _tween_mode: int = _TWEEN_IDLE
var _tween_curve: PackedFloat32Array = PackedFloat32Array()
var _tween_idx: int = 0
var _tween_scale: float = 1.0
# Vsyncs still owed to the CURRENT curve entry (the ROM's inner-loop repeat).
var _tween_hold: int = 0

# Base (untweened) transform — the placement the caller wants (zoom compensation
# + screen position). The tween scales about the speaker-triangle pivot ON TOP
# of this, so the caller's transform and the grow/shrink compose cleanly. Set
# via `set_zoom_scale` / `set_base_position` (ScenarioVM) or captured at `_ready`
# (scene-authored placement); standalone defaults to identity at the origin.
var _base_scale: Vector3 = Vector3.ONE
var _base_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_ensure_children()
	_ensure_typewriter()
	# Capture whatever placement the scene/parent gave us as the untweened base
	# so the open/close tween composes on top of it (setters override this later).
	_base_scale = scale
	_base_position = position
	if not Engine.is_editor_hint():
		set_process(true)


func _ensure_typewriter() -> void:
	if _typewriter != null:
		return
	_typewriter = TypewriterController.new()
	_typewriter.completed.connect(_on_typewriter_completed)
	_typewriter.glyph_typed.connect(_on_typewriter_glyph)


func _ensure_children() -> void:
	if _frame == null:
		_frame = UIFrame.new()
		_frame.name = "Frame"
		_frame.absorb_clicks = false
		# Per-instance dialog chrome: the beveled FRAME.BIN (40,0,32,32) 9-slice
		# with uniform 8px margins (NOT UIFrame's flat menu-tile default).
		_frame.source_region = DIALOG_FRAME_REGION
		_frame.margins = DIALOG_FRAME_MARGINS
		# OPAQUE (alpha-tested, depth-writing), not alpha-blended. The page-turn icon's
		# subtractive drop shadow folds, and the fold's Pass A seeds its display-space scratch
		# from the OPAQUE scene colour — a transparent frame is simply not in that seed, so the
		# shadow would subtract from whatever is behind the box instead of from its tan body.
		# The formation info panel sets this for the same reason (its folded subtractive band).
		# Safe here: the body text, portrait and speaker triangle all sit IN FRONT of the frame
		# in Z (0.1 / 0.1 / 0.05 vs the frame's -0.1), so a depth-writing frame occludes none.
		_frame.opaque = true
		add_child(_frame)
	if _portrait == null:
		_portrait = UIPortrait.new()
		_portrait.name = "Portrait"
		# ROM samples the dialog portrait 31px wide so it clears the 8px border.
		_portrait.set_sampled_width(PORTRAIT_SAMPLE_WIDTH_PX)
		add_child(_portrait)
	if _text == null:
		_text = UIText.new()
		_text.name = "Body"
		_text.render_priority = 1
		_text.space_width = SPACE_WIDTH_PX  # ROM 4px space advance (mirror overlay)
		add_child(_text)
	if _triangle == null:
		_setup_triangle()
	if _page_icon == null:
		_setup_page_icon()


func _setup_triangle() -> void:
	_triangle = MeshInstance3D.new()
	_triangle.name = "Triangle"
	var quad := QuadMesh.new()
	quad.size = Vector2(TRIANGLE_PX * _par() * pixels_per_unit, TRIANGLE_PX * pixels_per_unit)
	_triangle.mesh = quad
	# psx-ot-depth-exempt: screen-space ui3 dialog-box speaker arrow, not a battle-OT mesh.
	_triangle_material = StandardMaterial3D.new()
	_triangle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_triangle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_triangle_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_triangle_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_triangle_material.no_depth_test = true
	_triangle_material.render_priority = 2
	if ResourceLoader.exists(TRIANGLE_UP_PATH):
		_triangle_up_tex = load(TRIANGLE_UP_PATH) as Texture2D
	if ResourceLoader.exists(TRIANGLE_DOWN_PATH):
		_triangle_down_tex = load(TRIANGLE_DOWN_PATH) as Texture2D
	_triangle_material.albedo_texture = _triangle_up_tex
	_triangle.material_override = _triangle_material
	add_child(_triangle)


# --- Animated page-turn "more" icon (decode §3.4) ----------------------------

# The icon is TWO quads over one rect, not one (see PAGE_ICON_SHADOW_SHADER_PATH):
# the opaque pass draws the STP=0 body, the subtractive pass draws the STP=1 drop
# shadow. They share the atlas, the CLUT and the `cell` phase; only the shader and
# the alpha key differ, and those keys partition the palette, so the two never
# cover the same texel.
func _setup_page_icon() -> void:
	_load_page_icon_meta()
	var atlas := _load_page_icon_atlas()
	var pal := _page_icon_palette()
	# Above the body text (1) and speaker triangle (2) in painter's order.
	_page_icon = _build_page_icon_pass("PageIcon", PAGE_ICON_SHADER_PATH, 3, atlas, pal)
	_page_icon_material = _page_icon.material_override as ShaderMaterial
	# One rung ABOVE the opaque pass: `blend_sub` reads the framebuffer it darkens,
	# so it has to land after the box body, the text AND the icon's own opaque half.
	# (The halves never overlap, so this is about what is UNDER the shadow, not about
	# occluding the body ink.)
	_page_icon_shadow = _build_page_icon_pass(
		"PageIconShadow", PAGE_ICON_SHADOW_SHADER_PATH, 4, atlas, pal)
	_page_icon_shadow_material = _page_icon_shadow.material_override as ShaderMaterial
	# On a folding build swap to the PRELOADED fold Shader (display-space blend; see the const).
	if Fold.owns():
		_page_icon_shadow_material.shader = PAGE_ICON_SHADOW_FOLD_SHADER
	# Enrol the sub pass in the shared fold layer when this build folds; off-fork `Fold.add` is a
	# no-op by contract (ADR-0191 dec. 12) and the in-scene twin's render_priority above is what
	# orders it. Lone quad ⇒ rank 0; the rung is the same painter's rung as the in-scene path.
	if Fold.owns():
		Fold.add(_page_icon_shadow, _page_icon_shadow_material, DepthMode.rung_z(4))
	_update_page_icon_frame()


# One of the icon's two passes: a cell-sized quad on `shader_path` at `rung`,
# wired to the shared atlas + CLUT. Loud (not silent) if the shader is absent.
func _build_page_icon_pass(node_name: String, shader_path: String, rung: int,
		atlas: Texture2D, pal: ImageTexture) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var quad := QuadMesh.new()
	var sz := _page_icon_cell_size()
	quad.size = Vector2(sz.x * _par() * pixels_per_unit, sz.y * pixels_per_unit)
	mi.mesh = quad
	# psx-ot-depth-exempt: screen-space ui3 page-turn "more" indicator, not a battle-OT mesh.
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(shader_path):
		mat.shader = load(shader_path)
	else:
		push_error("[DialogueBox] %s MISSING — page-turn icon disabled." % shader_path)
	if atlas != null:
		mat.set_shader_parameter("index_atlas", atlas)
		mat.set_shader_parameter("atlas_size", Vector2(atlas.get_width(), atlas.get_height()))
	mat.set_shader_parameter("palette_tex", pal)
	mat.set_shader_parameter("brightness", 1.0)
	mat.render_priority = rung
	mi.material_override = mat
	mi.visible = false
	add_child(mi)
	return mi


# Parse assets/ui/page_turn_icon.json → per-phase atlas rects + atlas path. Loud
# on absence (like the curves asset) but degrades to "no icon", not a fake one.
func _load_page_icon_meta() -> void:
	_page_icon_cells.clear()
	if not FileAccess.file_exists(PAGE_ICON_META_PATH):
		push_error("[DialogueBox] page_turn_icon.json MISSING — page-turn icon disabled. " +
			"Run: uv run python tools/parse_range_tiles.py")
		return
	var f := FileAccess.open(PAGE_ICON_META_PATH, FileAccess.READ)
	if f == null:
		push_error("[DialogueBox] page_turn_icon.json unreadable — page-turn icon disabled.")
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		push_error("[DialogueBox] page_turn_icon.json malformed — page-turn icon disabled.")
		return
	var dir := str(data.get("texture_dir", "res://assets/sprites/textures"))
	var tex := str(data.get("texture", "RANGETILE.tga"))
	_page_icon_atlas_path = dir.path_join(tex)
	for fr in data.get("frames", []):
		if not (fr is Dictionary):
			continue
		var a: Array = fr.get("atlas", [])
		if a.size() >= 4:
			_page_icon_cells.append(Vector4(float(a[0]), float(a[1]), float(a[2]), float(a[3])))


func _load_page_icon_atlas() -> Texture2D:
	if _page_icon_atlas_path != "" and ResourceLoader.exists(_page_icon_atlas_path):
		return load(_page_icon_atlas_path) as Texture2D
	if _page_icon_atlas_path != "":
		push_error("[DialogueBox] page-turn icon atlas missing at %s — icon disabled. " % _page_icon_atlas_path +
			"Run: uv run python tools/parse_range_tiles.py")
	return null


func _page_icon_cell_size() -> Vector2:
	if not _page_icon_cells.is_empty():
		var c: Vector4 = _page_icon_cells[0]
		return Vector2(c.z, c.w)
	return Vector2(10, 12)


# The ROM's 0x7cbc active-label CLUT (16 Color entries, STP bit in .a), cached
# across every box instance. Anti-silent-failure contract (§C.2b) like the curves
# and metadata loads above: push_error + return empty rather than fake a palette.
static func _page_icon_clut() -> Array:
	if not _page_icon_clut_cache.is_empty():
		return _page_icon_clut_cache
	var cols: Array = RangeTileAtlas.new().window_tab_colors()
	if cols.size() < 16:
		push_error("[DialogueBox] RANGETILE.json window_tabs CLUT missing/short (%d of 16) — " % cols.size() +
			"page-turn icon has no palette. Run: uv run python tools/parse_range_tiles.py")
		return []
	_page_icon_clut_cache = cols
	return _page_icon_clut_cache


# The 16-colour CLUT the index atlas is sampled through (built as a 16x1 texture,
# matching vitals_sprite.gdshader's palette_tex convention). ONE texture feeds
# BOTH passes — they split it by the alpha/STP key, they do not each own a half.
func _page_icon_palette() -> ImageTexture:
	var clut := _page_icon_clut()
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in range(16):
		img.set_pixel(i, 0, clut[i] if i < clut.size() else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


# Point the icon quad's cell uniform at the current animation phase's atlas rect.
func _update_page_icon_frame() -> void:
	if _page_icon_material == null or _page_icon_cells.is_empty():
		return
	var i := _page_icon_phase % _page_icon_cells.size()
	_page_icon_material.set_shader_parameter("cell", _page_icon_cells[i])
	if _page_icon_shadow_material != null:
		_page_icon_shadow_material.set_shader_parameter("cell", _page_icon_cells[i])


# Dock the icon at the box's inner bottom-right corner (top-left-anchored quad,
# offset by half-extent since QuadMesh is centred). When a portrait is docked on
# the RIGHT it would overlap the corner icon, so anchor the icon to the LEFT of
# the portrait instead (portrait left edge = box_w − PORTRAIT_RIGHT_INSET_PX).
func _layout_page_icon() -> void:
	if _page_icon == null:
		return
	var sz := _page_icon_cell_size()
	var quad := _page_icon.mesh as QuadMesh
	if quad != null:
		quad.size = Vector2(sz.x * _par() * pixels_per_unit, sz.y * pixels_per_unit)
	var x_left_px: float
	var y_top_px: float
	if _has_portrait and not _portrait_on_left:
		# Right-docked portrait present: seat the icon to the LEFT of the portrait
		# (x) AND align its BOTTOM edge to the portrait's bottom (y) so the two
		# share a baseline, instead of dropping to the box's inner bottom border.
		x_left_px = _box_w_px - PORTRAIT_RIGHT_INSET_PX - PAGE_ICON_PORTRAIT_GAP_PX - sz.x
		var portrait_top_px := float(PORTRAIT_TOP_INSET_CE2_PX if _align == 2 else PORTRAIT_TOP_INSET_PX)
		# Portrait rendered height in virtual px (PAR affects width only, not height).
		var portrait_h_px := (_portrait.get_display_height() / pixels_per_unit) if _portrait != null else 0.0
		y_top_px = portrait_top_px + portrait_h_px - sz.y
	else:
		x_left_px = _box_w_px - PAGE_ICON_RIGHT_INSET_PX - sz.x
		y_top_px = _box_h_px - PAGE_ICON_BOTTOM_INSET_PX - sz.y
	var half_w := sz.x * _par() * pixels_per_unit * 0.5
	var half_h := sz.y * pixels_per_unit * 0.5
	_page_icon.position = Vector3(_px_x(x_left_px) + half_w, _px_y(-y_top_px) - half_h, 0.06)
	# The subtractive half sits on the SAME rect at the SAME Z — complementary
	# discards, so the quads tile the cell rather than fight over it. Same Z is
	# safe for `menu_cursor_shadow`'s depth TEST too: the opaque half writes depth
	# only where it draws, and it never draws a texel this pass keeps, so what the
	# shadow tests against is the box frame behind it (z = −0.1), which is farther.
	if _page_icon_shadow != null:
		var sq := _page_icon_shadow.mesh as QuadMesh
		if sq != null:
			sq.size = Vector2(sz.x * _par() * pixels_per_unit, sz.y * pixels_per_unit)
		_page_icon_shadow.position = _page_icon.position


# Show the icon only while a later page is pending and the box is live.
func _update_page_icon_visibility() -> void:
	if _page_icon == null:
		return
	_page_icon.visible = _active and has_more_pages()
	if _page_icon_shadow != null:
		_page_icon_shadow.visible = _page_icon.visible


# PAR for x-offsets / widths. Runtime tracks PSXDisplay.live_ui_par like the
# other ui3 elements; editor preview uses the 1.25 default.
func _par() -> float:
	if not Engine.is_editor_hint():
		return DisplayPort.live_ui_par()
	# Editor preview only: the autoload is non-`@tool` so it is genuinely absent
	# here. A project with no `[autoload]` line is a different question and the
	# port answers it with 1.0, the value the game actually runs at (#1263).
	return 1.25


func _px_x(px: float) -> float:
	return px * _par() * pixels_per_unit


func _px_y(px: float) -> float:
	return px * pixels_per_unit


## Show a boxed dialogue. `tokens` is the baked token list; `dialog_byte` is
## the opcode Dialog byte (selects align + arrow flags); `sprite_id` is the
## speaker's body sprite for the portrait (-1 = no portrait). `unit_offset_px`
## is the unit's screen-X minus the box centre-X (signed; <0 = unit left of the
## box → flip portrait/triangle). Re-calling on the SAME box performs the `{51}`
## in-place swap (no teardown).
## `evtface` (optional) is a resolved EVTFACE event-portrait texture ({50} Portrait
## Row, EvtFaceCatalog); when set it supersedes `sprite_id` as the portrait source
## (scripted cutscene faces vs the in-battle unit SPR). Both null/-1 = no portrait.
## `template_folder` (optional, ADR-0072 #223) is a unique speaker's resolved template
## folder; when set (and no `evtface`) the unit-SPR portrait is fronted by the folder's
## OWNED `portrait.tga` instead of the flat sprite sheet — flat fallback load-bearing.
func show_dialog(tokens: Array, dialog_byte: int, sprite_id: int = -1, unit_offset_px: float = 0.0, open_type: int = 3, evtface: Texture2D = null, template_folder: String = "") -> void:
	_ensure_children()
	_ensure_typewriter()

	# Decode the Dialog byte (boxed_dialog_decode.md A1).
	_dialog_byte = dialog_byte
	_align = dialog_byte & 0x3                 # 1=Top(box above→arrow down), 2=Bottom(box below→arrow up)
	_arrow_flags = dialog_byte & 0xC
	_show_arrow = (_arrow_flags != DIALOG_ARROW_REMOVE)
	# align==1 → box above unit → arrow DOWN; else (2/0) → box below unit → arrow UP.
	_arrow_up = (_align != 1)
	_unit_offset_px = unit_offset_px
	# Tail mirror fires only on a non-zero arrow high-nibble (decode §1c). Chapel
	# lines are all zero here → base orientation; msgid15 (open_type 0x12) is the
	# one scenario-1 line that mirrors.
	_arrow_mirror = (open_type & 0xf0) != 0
	_has_portrait = evtface != null or sprite_id >= 0 or template_folder != ""
	_portrait_on_left = unit_offset_px < 0.0

	if _has_portrait:
		if evtface != null:
			_bind_evtface(evtface)
		else:
			# SPR path shares the same G4 flip rule as _bind_evtface (see there).
			_portrait.flipped = not _portrait_on_left
			if template_folder != "":
				# Front the flat sheet with the unique's OWNED portrait.tga (#223);
				# display_from_template falls back to display_sprite_id if the folder
				# is blank or holds no portrait.tga (generated + gitignored, #200).
				_portrait.display_from_template(template_folder, sprite_id)
			else:
				_portrait.display_sprite_id(sprite_id)
			_portrait.visible = true
	else:
		_portrait.clear()
		_portrait.visible = false

	# Split the message into fixed-3-line-window pages (decode §1.1) and render
	# page 1. Page ≥2 is reached via `advance_page` (O/Circle) in place — portrait,
	# frame, side, and arrow persist across pages.
	_pages = _paginate(tokens)
	_page_idx = 0
	_active = true
	_render_current_page()
	visible = true

	# Grow the box open from the speaker-triangle point (Part B). A NEW box opens;
	# the {51} in-place swap (swap_text) does NOT re-open.
	_begin_open_tween(open_type)


## `{51}` Change Dialog swap: replace the body text in place (keeping the
## frame, side, and arrow) and restart the typewriter. No teardown.
## `evtface` (optional) re-resolves the portrait in place — a {51} that carries a
## valid Portrait Column re-picks the EVTFACE face (row stays put, §2.5). null
## leaves the current portrait untouched (the col-0 / no-{50}-row swap case).
func swap_text(tokens: Array, evtface: Texture2D = null) -> void:
	_ensure_children()
	_ensure_typewriter()
	if evtface != null:
		_bind_evtface(evtface)
	_pages = _paginate(tokens)
	_page_idx = 0
	_active = true
	_render_current_page()
	visible = true


## Dock a resolved EVTFACE face onto the portrait. Shared by show_dialog's initial
## draw and swap_text's {51} in-place re-pick so the facing rule has ONE home.
## Portrait facing (G4): the ROM mirrors only on the LEFT dock; the raw SPR natively
## faces LEFT, so right-dock-unmirrored faces into the box. Our extracted texture is
## the OPPOSITE handedness, so we invert: right-dock (portrait_on_left == false) →
## flip → faces left like the ground truth; left-dock → no flip → faces right into
## the body. Net = !portrait_on_left.
func _bind_evtface(tex: Texture2D) -> void:
	_has_portrait = true
	_portrait.flipped = not _portrait_on_left
	_portrait.display_evtface(tex)
	_portrait.visible = true


## The full Dialog byte this box was opened with (mode nibble + flags) — the {51}
## swap re-resolves its portrait against the box's own stored mode.
func dialog_byte() -> int:
	return _dialog_byte


# --- Pagination (fixed 3-line window; decode §1.1) ---------------------------

## Render the current page's tokens into the body: flatten → text + palette runs,
## reset the reveal, re-measure, and (re)start the typewriter. Portrait / frame /
## side / arrow are OWNED by show_dialog and untouched here, so a page advance
## keeps the speaker face while dropping the name row (page ≥2 carries no name).
func _render_current_page() -> void:
	var page_tokens: Array = _pages[_page_idx] if _page_idx < _pages.size() else []
	var flat := TypewriterController.flatten(page_tokens)
	_full_text = str(flat["text"])
	_char_palettes = flat["palettes"]
	_revealed_full_len = 0
	_text.pixels_per_unit = pixels_per_unit
	_text.visible_chars = 0
	_text.text = _full_text
	_apply_palette_runs()
	# Width tracks the page's widest line; height is the fixed 3-line window.
	_recompute_size()
	_request_layout_update()
	# Reset the reveal clock so the fractional VBlank carry from the prior page/box
	# doesn't leak into this one.
	_reset_reveal_clock()
	_typewriter.throttle = throttle
	_typewriter.start(page_tokens, self)
	# The "more" icon shows only while a later page is pending.
	_page_icon_phase = 0
	_page_icon_phase_accum = 0
	_update_page_icon_frame()
	_update_page_icon_visibility()


## Advance to the next page in place (O/Circle). No re-open tween — the box is
## already open. Returns false when already on the last page.
func advance_page() -> bool:
	if not has_more_pages():
		return false
	_page_idx += 1
	_active = true
	_render_current_page()
	# "Flip Page" blip (PSX system SFX 0x2d/45) fires on a real page turn only —
	# never on the final advance (guarded above) or box close. The CUE is host
	# vocabulary (#1273); this states the event and `UIWiring` names the sound.
	page_turned.emit()
	return true


## True while a later page is pending (drives the "more" icon + the VM's
## advance-vs-close decision).
func has_more_pages() -> bool:
	return _page_idx < _pages.size() - 1


## Total pages the current message split into (test hook).
func page_count() -> int:
	return _pages.size()


## Zero-based index of the page on screen (test hook).
func current_page() -> int:
	return _page_idx


## Is the animated "more" icon currently shown (test hook).
func is_page_icon_visible() -> bool:
	return _page_icon != null and _page_icon.visible


## Split a flattened message-token list into per-page token arrays for the fixed
## 3-line window: **page 1 = name line + first 2 dialogue lines; page ≥2 = up to
## 3 dialogue lines, name dropped**. When the message has no speaker/name line,
## every page carries up to 3 dialogue lines.
func _paginate(tokens: Array) -> Array:
	var lines := _split_lines(tokens)
	if lines.is_empty():
		return [tokens]
	var has_name := _line_has_speaker_text(lines[0])
	var pages: Array = []
	var i := 0
	var first := true
	var n := lines.size()
	while i < n:
		var page_lines: Array = []
		var budget := PAGE_LINES_NO_NAME
		if first and has_name:
			page_lines.append(lines[0])
			i = 1
			budget = PAGE_LINES_WITH_NAME
		while i < n and budget > 0:
			page_lines.append(lines[i])
			i += 1
			budget -= 1
		if page_lines.is_empty():
			break
		pages.append(_page_tokens_for_lines(page_lines))
		first = false
	if pages.is_empty():
		return [tokens]
	return pages


## Walk a token list into per-line records `{tokens, start_palette}`, split on
## `{Newline}`. `start_palette` is the {Color} run active when the line BEGINS
## (inherited from earlier lines) so a page boundary can restore it. Trailing
## empty lines (a message ending in a newline) are dropped so they don't spawn a
## phantom blank page.
func _split_lines(tokens: Array) -> Array:
	var lines: Array = []
	var pal := 0
	var cur := {"tokens": [], "start_palette": pal}
	for tok in tokens:
		if not (tok is Dictionary):
			continue
		var kind: String = str(tok.get("type", ""))
		if kind == "newline":
			lines.append(cur)
			cur = {"tokens": [], "start_palette": pal}
			continue
		if kind == "color":
			pal = int(tok.get("palette", 0))
		cur["tokens"].append(tok)
	lines.append(cur)
	# Drop trailing content-free lines.
	while lines.size() > 1 and _line_is_empty(lines[lines.size() - 1]):
		lines.remove_at(lines.size() - 1)
	return lines


## A line has no rendered content when it holds no text/macro tokens (only
## color/delay control tokens, or nothing).
func _line_is_empty(line: Dictionary) -> bool:
	for tok in line.get("tokens", []):
		var kind: String = str(tok.get("type", ""))
		if kind == "text" and str(tok.get("value", "")) != "":
			return false
		if kind == "macro":
			return false
	return true


## True when a line renders any text under a NON-zero (speaker `{Color 08}`)
## palette — i.e. it is the red name row that consumes one window slot on page 1.
func _line_has_speaker_text(line: Dictionary) -> bool:
	var pal := int(line.get("start_palette", 0))
	for tok in line.get("tokens", []):
		var kind: String = str(tok.get("type", ""))
		if kind == "color":
			pal = int(tok.get("palette", 0))
		elif kind == "text" and str(tok.get("value", "")) != "" and pal != 0:
			return true
	return false


## Rebuild a self-contained token array for one page's lines. The first line is
## prefixed with a `{Color}` restoring its inherited palette (so a body-only page
## renders in the body ramp, not leftover speaker state); subsequent lines are
## joined with `{Newline}`.
func _page_tokens_for_lines(page_lines: Array) -> Array:
	var out: Array = []
	for li in range(page_lines.size()):
		var line: Dictionary = page_lines[li]
		if li == 0:
			out.append({"type": "color", "palette": int(line.get("start_palette", 0))})
		else:
			out.append({"type": "newline"})
		for tok in line.get("tokens", []):
			out.append(tok)
	return out


# --- TypewriterController sink ------------------------------------------------

func typewriter_append(text: String) -> void:
	_revealed_full_len += text.length()
	_update_visible()


func typewriter_set_palette(_palette: int) -> void:
	# Palette runs are pre-computed from flatten() and applied once in
	# _apply_palette_runs(); the live reveal only needs the visible count.
	pass


func _update_visible() -> void:
	if _text == null:
		return
	# full_text indices include newlines; UIText char nodes exclude them.
	var revealed := mini(_revealed_full_len, _full_text.length())
	var newlines := _full_text.substr(0, revealed).count("\n")
	_text.visible_chars = revealed - newlines


func _on_typewriter_completed() -> void:
	# Ensure everything is shown, then notify the gate.
	_revealed_full_len = _full_text.length()
	_update_visible()
	emit_signal("typed_out")


func _on_typewriter_glyph() -> void:
	# One "Text Typing" blip per revealed glyph (PSX system SFX 0x73) — named by
	# `UIWiring`, not here (#1273).
	glyph_revealed.emit()


# --- Layout ------------------------------------------------------------------

func _recompute_size() -> void:
	# Logical-px text width (strip PAR + ppu back out of the world measure).
	var par := _par()
	var denom := par * pixels_per_unit
	var text_w_px := 0.0
	if _text != null and denom > 0.0:
		text_w_px = _text.get_text_size().x / denom
	# Width tracks the measured text (+ portrait reserve). Height is FIXED: the
	# 0x1X/0x9X box forces 3 lines + chrome = 64px. The ROM ALSO grows the box by
	# an arrow/tail term (cc==0 +8 / cc==4 +16) because it draws the tail INSIDE
	# the box bitmap; we draw the speaker triangle as a SEPARATE quad ABOVE the
	# frame, so adding that term here just inflated the bottom margin past the
	# ground truth (refinement 2026-06-27, R6). The ARROW_EXTRA_* consts are kept
	# as the documented ROM values but no longer extend OUR frame.
	_box_w_px = text_w_px + (WIDTH_PAD_PORTRAIT_PX if _has_portrait else WIDTH_PAD_PX)
	_box_h_px = FORCED_LINES * LINE_HEIGHT_PX + BOX_CHROME_PX


func _request_layout_update() -> void:
	if _layout_dirty:
		return
	_layout_dirty = true
	call_deferred("_do_layout_update")


func _do_layout_update() -> void:
	if not _layout_dirty:
		return
	_layout_dirty = false
	_update_layout()


func _update_layout() -> void:
	_ensure_children()
	# Frame (behind everything).
	_frame.pixels_per_unit = pixels_per_unit
	_frame.frame_size = Vector2(_box_w_px, _box_h_px)
	_frame.position = Vector3(0, 0, -0.1)

	# Body text inset: X pushes right when the portrait is on the LEFT; Y is
	# box_top + 8 normally, +16 when bottom-anchored/upward-tail (align==2).
	var text_inset_px := TEXT_INSET_PORTRAIT_PX if (_has_portrait and _portrait_on_left) else TEXT_INSET_PX
	var text_top_px := TEXT_TOP_INSET_CE2_PX if _align == 2 else TEXT_TOP_INSET_PX
	_text.pixels_per_unit = pixels_per_unit
	_text.position = Vector3(_px_x(text_inset_px), _px_y(-text_top_px), 0.1)

	# Portrait side follows the unit (left when unit is left of the box). Top
	# inset = box_top + 7, or +15 when align==2.
	if _has_portrait and _portrait != null:
		var px_x: float
		if _portrait_on_left:
			px_x = _px_x(PORTRAIT_INSET_PX)
		else:
			px_x = _px_x(_box_w_px - PORTRAIT_RIGHT_INSET_PX)
		var portrait_top_px := PORTRAIT_TOP_INSET_CE2_PX if _align == 2 else PORTRAIT_TOP_INSET_PX
		_portrait.pixels_per_unit = pixels_per_unit
		_portrait.position = Vector3(px_x, _px_y(-portrait_top_px), 0.1)

	# Setting _text.pixels_per_unit above rebuilds the char nodes (resetting them
	# to the global font_color/MENU palette), so re-apply the speaker/body runs.
	_apply_palette_runs()
	_layout_triangle()
	_layout_page_icon()


func _layout_triangle() -> void:
	if _triangle == null:
		return
	if not _show_arrow:
		_triangle.visible = false
		return
	_triangle.visible = true

	# Pick the cell (up = box below unit; down = box above unit).
	_triangle_material.albedo_texture = _triangle_up_tex if _arrow_up else _triangle_down_tex

	# dst-X tracks the unit, clamped inside the box span (RE: (w/2)+offset-8).
	var tri_x := _box_w_px * 0.5 + _unit_offset_px - (TRIANGLE_PX * 0.5)
	tri_x = clampf(tri_x, TRIANGLE_CLAMP_MARGIN_PX, _box_w_px - TRIANGLE_CLAMP_MARGIN_PX)

	# dst-Y: arrow UP rides the TOP edge poking up; DOWN rides the BOTTOM edge
	# poking down. The cells have ~3px of transparent padding on the box-facing
	# side, so overlap the edge by TRIANGLE_EDGE_OVERLAP_PX to seat the bar on
	# the frame border (no floating gap).
	var tri_y_px: float
	if _arrow_up:
		tri_y_px = TRIANGLE_PX - TRIANGLE_EDGE_OVERLAP_PX  # quad bottom dips into box top
	else:
		tri_y_px = -(_box_h_px) + TRIANGLE_EDGE_OVERLAP_PX  # quad top dips into box bottom

	# Refresh the quad to the current ppu/PAR.
	var quad := _triangle.mesh as QuadMesh
	if quad != null:
		quad.size = Vector2(TRIANGLE_PX * _par() * pixels_per_unit, TRIANGLE_PX * pixels_per_unit)
	# Top-left anchoring: mesh quad is centred, so offset by half-extent.
	var half_w := TRIANGLE_PX * _par() * pixels_per_unit * 0.5
	var half_h := TRIANGLE_PX * pixels_per_unit * 0.5
	_triangle.position = Vector3(_px_x(tri_x) + half_w, _px_y(tri_y_px) - half_h, 0.05)
	# Horizontal mirror gate. The cells are extracted in their PSX BASE lean
	# (down.tga tips down-LEFT, up.tga tips up-RIGHT); PSX only mirrors the tail
	# sprite when the authored arrow operand `msg[0x64] & 0xf0` is non-zero
	# (decode §3 correction #2 / §1c — `sign(local_b8)` flips the PORTRAIT, not the
	# tail). Chapel lines are all `&0xf0 == 0` → base orientation, matching PSX
	# (psx_box_zoom.png: Ovelia msg3 down-tail leans down-LEFT unmirrored, though
	# `local_b8 = +8`). The prior rule keyed the flip on `sign(_unit_offset_px)`,
	# which spuriously mirrored every non-zero-offset line — exactly the tails the
	# user reported pointing "the wrong way".
	_triangle.scale = Vector3(-1.0 if _arrow_mirror else 1.0, 1.0, 1.0)


# Recolor the speaker ({Color 08}) vs body ({Color 00}) runs over the current
# char nodes. Body renders the atlas directly (CLUT slots 1-3); the speaker run
# is remapped to the ROM speaker ramp (slots 9-11). Maps full_text palette
# entries → char-node indices (newlines are not char nodes).
func _apply_palette_runs() -> void:
	if _text == null or _char_palettes.is_empty():
		return
	var sp := _speaker_ramp()  # [dark(px3), mid(px2), light(px1)] = slots 11,10,9
	var bd := _body_ramp()     # [dark(px3), mid(px2), light(px1)] = slots 3,2,1
	var node_idx := 0
	for i in range(_full_text.length()):
		if _full_text[i] == "\n":
			continue
		var pal := _char_palettes[i] if i < _char_palettes.size() else 0
		if pal != 0:
			# {Color 08} (and any non-zero) → speaker ramp (CLUT 9-11, red).
			_text.set_char_clut_run(node_idx, node_idx + 1, sp[0], sp[1], sp[2])
		else:
			# {Color 00} → body ramp (CLUT 1-3, dark). The shared atlas is
			# off-white (for menus/prayer), so the box body is a CUSTOM remap,
			# NOT atlas-direct — that off-white-body render was the shipped bug.
			_text.set_char_clut_run(node_idx, node_idx + 1, bd[0], bd[1], bd[2])
		node_idx += 1


# Resolve the speaker ramp from the ROM dialog_clut dump (slots 9/10/11 mapped
# to px1/px2/px3), falling back to the committed constants. Returned as
# [dark(=px3/slot11), mid(=px2/slot10), light(=px1/slot9)] to match the
# set_char_clut_run(dark, mid, light) signature.
func _speaker_ramp() -> Array:
	var clut: Array[Color] = []
	UIChar._ensure_shared_resources()
	if UIChar._shared_font != null:
		clut = UIChar._shared_font.dialog_clut
	if clut.size() >= 12:
		return [clut[11], clut[10], clut[9]]
	return [SPEAKER_AA, SPEAKER_HILITE, SPEAKER_STROKE]


# Resolve the body ramp from the ROM dialog_clut dump (slots 1/2/3 = px1/px2/px3),
# falling back to the committed constants. Returned as [dark(=px3/slot3),
# mid(=px2/slot2), light(=px1/slot1)] to match set_char_clut_run(dark, mid, light).
func _body_ramp() -> Array:
	var clut: Array[Color] = []
	UIChar._ensure_shared_resources()
	if UIChar._shared_font != null:
		clut = UIChar._shared_font.dialog_clut
	if clut.size() >= 4:
		return [clut[3], clut[2], clut[1]]
	return [BODY_AA, BODY_HILITE, BODY_STROKE]


# --- Reveal clock + advance gate ---------------------------------------------

## The PSX typewriter clocks off the 60 Hz frame-sync interrupt, not the render
## rate. `DialogueBox` is used standalone in ui3 (CombatUITest) as well as under
## ScenarioVM, so it can't borrow the VM's `_tick_once` pump the overlay uses —
## instead it accumulates its own wall-clock `delta * 60` here and spends whole
## VBlanks on the walker. This keeps the type-out host-refresh-independent (the
## old `Engine.get_frames_drawn()` cursor made a 144 Hz monitor type 2.4x too
## fast).
const _TICK_HZ := 60.0

func _process(dt: float) -> void:
	if _typewriter == null:
		return
	# Nothing to pump once the box is idle AND the tween has settled.
	if not _active and _tween_mode == _TWEEN_IDLE:
		return
	var frames := _advance_delta(dt)
	if frames <= 0:
		return
	# The grow/shrink tween ticks even after typing finishes (open bounce-in) and
	# after `_active` clears (close shrink runs until _finish_close hides the box).
	var was_tweening := _tween_mode != _TWEEN_IDLE
	if was_tweening:
		advance_tween_frames(frames)
	# The ROM's tween is fiber-BLOCKING: the `jal dialog_box_open_close_tween` at
	# `0x80131344` returns only once the outer loop @0x80132d98 has consumed the whole
	# curve, and the first `event_dialogue_tick` is downstream of it — so the box is
	# fully open BEFORE the first glyph appears. A frame spent growing is a frame the
	# typewriter does not get (we used to grow and type in the same frame).
	if _active and _typewriter.is_active() and not was_tweening:
		_typewriter.advance_frames(frames)
	# Animate the page-turn "more" icon (4-phase loop) while a later page pends.
	if _page_icon != null and _page_icon.visible and not _page_icon_cells.is_empty():
		_page_icon_phase_accum += frames
		var per := maxi(1, page_icon_frames_per_phase)
		while _page_icon_phase_accum >= per:
			_page_icon_phase_accum -= per
			_page_icon_phase = (_page_icon_phase + 1) & 0x3
		_update_page_icon_frame()


## Wall-clock reveal cursor: accumulate elapsed time as 60 Hz VBlanks and return
## the whole VBlanks to spend this frame, carrying the fraction forward. RESET
## to 0 on every show_dialog/swap_text via `_reset_reveal_clock()` — otherwise
## the fractional carry from the previous box would leak into the next one.
var _reveal_accum: float = 0.0
func _advance_delta(dt: float) -> int:
	_reveal_accum += dt * _TICK_HZ
	var whole := int(_reveal_accum)
	_reveal_accum -= float(whole)
	return whole


func _reset_reveal_clock() -> void:
	_reveal_accum = 0.0


## Drive the typewriter directly (unit tests without a real clock).
func advance_frames(n: int) -> void:
	if _typewriter != null:
		_typewriter.advance_frames(n)


## True while the typewriter is still revealing.
func is_typing() -> bool:
	return _typewriter != null and _typewriter.is_active()


func is_active() -> bool:
	return _active


## Current box footprint in WORLD units (width includes PAR). Valid after a
## show_dialog/swap_text (size is computed synchronously). Lets a caller place
## the top-left-anchored box relative to a speaker.
func get_box_size_world() -> Vector2:
	return Vector2(_box_w_px * _par() * pixels_per_unit, _box_h_px * pixels_per_unit)


## Re-aim the mouth triangle after the box has been (re)positioned — e.g. when
## the caller edge-clamps the box away from the speaker. `offset_px` is the tail's
## offset from box centre in native px (PSX `local_b8`); sign flips facing.
func set_triangle_aim(offset_px: float) -> void:
	_unit_offset_px = offset_px
	_layout_triangle()


## Dock the speaker portrait on the LEFT (mirrored to face inward) or RIGHT of the
## box. In PSX this keys on `sign(local_b8)` (decode §7.1) and can flip live as the
## box edge-clamps or an authored fine-X shoves the tail — the caller drives it from
## the same local_b8 it feeds `set_triangle_aim`. Re-lays only when the side changes.
func set_portrait_side(on_left: bool) -> void:
	if _portrait_on_left == on_left:
		return
	_portrait_on_left = on_left
	if _has_portrait and _portrait != null:
		# Match show_dialog's facing rule: extracted SPR handedness → flip = !on_left.
		_portrait.flipped = not _portrait_on_left
	_update_layout()


## Reveal the full text immediately (advance press during typing).
func finish_typing() -> void:
	if _typewriter != null:
		_typewriter.reset()
	_revealed_full_len = _full_text.length()
	_update_visible()
	emit_signal("typed_out")


## Player/caller advanced past this box.
func advance() -> void:
	emit_signal("advanced")


## Close the box. Faithful to the ROM (Part B): the box SHRINKS closed (curve 4)
## into the speaker-triangle point, then disappears. Drive the shrink tween; the
## teardown (`_finish_close`) runs when it bottoms out. A box that is already
## hidden tears down immediately.
func close() -> void:
	if not _active and _tween_mode == _TWEEN_IDLE and not visible:
		_finish_close()
		return
	_begin_close_tween()


# Actual teardown — reset the walker, drop the text/portrait, restore the base
# transform, and hide. Called when the close tween finishes (or immediately when
# there was nothing to shrink).
func _finish_close() -> void:
	if _typewriter != null:
		_typewriter.reset()
	_active = false
	_revealed_full_len = 0
	_full_text = ""
	if _text != null:
		_text.text = ""
	if _portrait != null:
		_portrait.clear()
	if _page_icon != null:
		_page_icon.visible = false
	if _page_icon_shadow != null:
		_page_icon_shadow.visible = false
	_pages = []
	_page_idx = 0
	_tween_mode = _TWEEN_IDLE
	_tween_hold = 0
	_tween_scale = 1.0
	scale = _base_scale
	position = _base_position
	visible = false


# --- Open/close grow-shrink tween (Part B) -----------------------------------

## The caller's zoom compensation (constant on-screen box size under a zoomed
## camera). Stored as the tween's base X/Y scale; Z is preserved. Re-applies the
## current tween fraction on top so a mid-tween re-placement stays correct.
func set_zoom_scale(s: Vector3) -> void:
	_base_scale = s
	_apply_tween_transform()


## The caller's screen placement. Stored as the tween's base position; the
## grow/shrink offsets from the triangle pivot compose on top.
func set_base_position(p: Vector3) -> void:
	_base_position = p
	_apply_tween_transform()


func get_base_position() -> Vector3:
	return _base_position


## Current fraction of full box size (1.0 = full, >1.0 = overshoot). Test hook.
func get_tween_scale() -> float:
	return _tween_scale


func is_tweening() -> bool:
	return _tween_mode != _TWEEN_IDLE


## True only while the box is GROWING open (not while it shrinks closed). The ROM's
## open tween blocks the event fiber, so nothing — typewriter or advance press —
## happens during it; the close tween runs after the fiber has already moved on.
func is_opening() -> bool:
	return _tween_mode == _TWEEN_OPEN


## True while the box is meaningfully on screen — typing, idle-open, or mid
## open/close tween. Lets the VM re-place the box live each frame while it's up.
func is_open() -> bool:
	return visible or _active or _tween_mode != _TWEEN_IDLE


## Vsyncs each curve entry is HELD for, mirroring the ROM tween driver's INNER
## loop (`0x80132cac..0x80132d88`): every iteration begins `jal event_fiber_yield`
## and then re-applies the SAME entry `s4`, with `s0` counting to `3 − throttle`;
## the OUTER loop (`0x80132c88..0x80132d98`, `s3 += 2`) is what advances to the next
## entry. At the ROM's pinned throttle of 1 that is **2 vsyncs per entry**, so c3
## settles in 14 frames (not 7), c1 in 22 (not 11) and the close in 8 (not 4).
##
## The arithmetic is `TypewriterController`'s — the two are the same ROM global.
static func tween_frames_per_entry() -> int:
	return TypewriterController.frame_factor(ROM_TEXT_GLYPH_THROTTLE)


## Drive the tween forward N **vsync frames** directly (unit tests without a real
## clock). N frames advance N / `tween_frames_per_entry()` curve entries — this is
## the same path `_process` pumps, so a test driving it exercises the real cadence.
func advance_tween_frames(n: int) -> void:
	for _i in range(n):
		if _tween_mode == _TWEEN_IDLE:
			return
		_tween_hold -= 1
		if _tween_hold <= 0:
			_step_tween()


func _begin_open_tween(open_type: int) -> void:
	var curves := _load_curves()
	var idx := open_type & 0xf
	if not curves.has(idx):
		# Asset missing/curve absent — _load_curves already emitted a loud error.
		# Show the box at full size rather than fake a curve.
		_tween_mode = _TWEEN_IDLE
		_tween_scale = 1.0
		_apply_tween_transform()
		return
	_tween_curve = curves[idx]
	_tween_idx = 0
	_tween_mode = _TWEEN_OPEN
	_tween_hold = tween_frames_per_entry()
	_tween_scale = _tween_curve[0]
	_apply_tween_transform()


func _begin_close_tween() -> void:
	var curves := _load_curves()
	if not curves.has(CLOSE_CURVE_INDEX):
		_finish_close()
		return
	_tween_curve = curves[CLOSE_CURVE_INDEX]
	_tween_idx = 0
	_tween_mode = _TWEEN_CLOSE
	_tween_hold = tween_frames_per_entry()
	# CLOSE curve `t` marches 0→1 as PROGRESS; size fraction = 1 − t (full→0).
	_tween_scale = 1.0 - _tween_curve[0]
	_apply_tween_transform()


func _step_tween() -> void:
	if _tween_mode == _TWEEN_IDLE:
		return
	_tween_idx += 1
	if _tween_idx >= _tween_curve.size():
		if _tween_mode == _TWEEN_CLOSE:
			_tween_mode = _TWEEN_IDLE
			_tween_scale = 0.0
			_finish_close()
			return
		# OPEN done → settle at full size.
		_tween_mode = _TWEEN_IDLE
		_tween_scale = 1.0
		_apply_tween_transform()
		return
	var ct := _tween_curve[_tween_idx]
	_tween_hold = tween_frames_per_entry()
	_tween_scale = (1.0 - ct) if _tween_mode == _TWEEN_CLOSE else ct
	_apply_tween_transform()


# Compose the base placement with the current tween fraction, scaling about the
# speaker-triangle pivot so the box grows out of / shrinks into the mouth point
# (matching the ROM's corner-lerp collapse point). With `_tween_scale == 1.0`
# this is exactly the base transform.
func _apply_tween_transform() -> void:
	var t := _tween_scale
	scale = Vector3(_base_scale.x * t, _base_scale.y * t, _base_scale.z)
	var pivot := _tween_pivot()
	position = _base_position + Vector3(
		_base_scale.x * pivot.x * (1.0 - t),
		_base_scale.y * pivot.y * (1.0 - t),
		0.0)


# The collapse/grow point in box-local world units: the speaker-triangle (mouth)
# location when the arrow is shown, else the box bottom-centre.
func _tween_pivot() -> Vector3:
	if _show_arrow and _triangle != null:
		return Vector3(_triangle.position.x, _triangle.position.y, 0.0)
	return Vector3(_px_x(_box_w_px * 0.5), _px_y(-_box_h_px), 0.0)
