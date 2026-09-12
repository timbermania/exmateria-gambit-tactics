class_name StartActionMenu
extends Node3D
## The Formation/Status START sub-menu (FORMATION_SCREEN.md §15.20) — the vertical
## action list (Item / Ability / Change Job / Remove Unit / Order Unit) with a "Menu"
## title box and a bobbing glove cursor, opened by pressing START on the detail/Status
## screen. It box-opens ON TOP of the already-built detail screen (§15.14–15.19) and
## returns only a chosen row (0..4) + an outcome — the per-item target screens (Item
## menu, Change Job screen, …) are a SEPARATE outer layer, out of scope here (§15.20).
##
## Faithfulness rule (as elsewhere): FFT visuals + layout, OUR data. Sources:
##   - window frame : `UIFrame` 9-slice, CLUT 0x7cfc (the 4-quad menu frame, §15.20).
##   - box-open     : `BoxOpenAnimator` center-out SCISSOR (§15.17), same curve/cadence
##                    as the detail screen — the body is REVEALED through a `clip_world`
##                    aperture, nothing scales.
##   - "Menu" title : a SEPARATE full-size element — the same TEXTURE-SAMPLED word-tab as the
##                    Eqp/Ability window tabs (§15.19): a baked RANGETILE cell (uv 120,120 24×8)
##                    drawn through the cream active-label CLUT 0x7CBC, NOT FONT.BIN. It does NOT
##                    box-open (sits outside the body scissor, poking above the frame top-left).
##   - rows         : 5 FONT.BIN dark-on-tan strings (`UIMenuText`), 16px pitch.
##   - glove cursor : two-layer 16×16 emboss on RANGETILE — lit uv(168,0)/CLUT 0x7d7c (opaque) +
##                    shadow uv(184,0)/CLUT 0x7dbc (SUBTRACTIVE, PSX ABR2 = bg−texel, the gold-box
##                    drop-shadow mechanism), offset +2/+2; bobs on X (`GloveCursorBob` glove tables,
##                    ADR-0046). It is UNCLIPPED and on top — it pokes out the frame's LEFT edge.
##                    The FIRST glove consumer (gh #73).
##
## The RENDER/OPEN/nav are the RE'd ground truth (§15.20 decomp + the committed save
## states formation_startmenu_ss{0,1,2,3}); the row STRINGS are the screenshot text.
##
## ADR-0088 migration (registered elements; guard StartMenuFrameGroupTest): the menu is a
## registered WINDOW element (OWN_APERTURE + the shared BOX_OPEN beat — the third copy of
## the per-class box-open accumulator died here) with an INSET chrome child element
## (FRAME_RECT ⊂ CONTAINER, so the chrome is NOT the window element's own frame criterion),
## an UNCLIPPED title element (drawn full, outside the body scissor) and an UNCLIPPED glove
## cursor element. The WINDOW answers its rect `at(location)` — a KEY LOCATION picked by
## the host among the 5 proven homes (ADR-0088 Amendment 2); the child elements are
## DERIVED placements anchored on the build-time container and ride the window origin.
##
## Vault: [[Start Action Menu]]

const TunePort = ExMateriaPlatform.TunePort

const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")
const UIMenuText = preload("res://src/ui3/UIMenuText.gd")
const BoxOpenAnimator = preload("res://src/ui3/detail/BoxOpenAnimator.gd")
const UIUnitNameplate = preload("res://src/ui3/UIUnitNameplate.gd")
const LearnAbilityMenu = preload("res://src/ui3/detail/LearnAbilityMenu.gd")

const _SPRITE_SHADER := "res://src/ui3/shaders/vitals_sprite.gdshader"
## The glove SHADOW layer is SUBTRACTIVE (PSX ABR2: bg − texel, full strength) — PROVEN from the ss1
## OT: the shadow SPRTt (uv 184,0 / clut 0x7DBC) is drawn under `DR_TPAGE 0x005F` (abr=2), gouraud
## 0x80 (neutral → texel×128/128 = full). The opaque lit hand (SPRT 0x64) is drawn AFTER it in OT
## order and OCCLUDES it, so only the +2,+2 offset peeks out (§15.20 / issue 6). This is an IN-SCENE
## blend_sub prim (NOT compositor_layer): it must share the main depth buffer with the in-scene
## opaque lit hand so the hand's depth hides the overlap — a folded shadow uses a separate scratch
## depth buffer the hand can't write, so the full 16×16 subtract blooms (the "shadow too strong" bug).
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

## The five action rows, in menu order (0=Item … 4=Order Unit). Ground-truth strings
## from the ss1 screenshot; the ROW enum indexes match the list-window `+0x38` sel row.
const ROWS: Array[String] = ["Item", "Ability", "Change Job", "Remove Unit", "Order Unit"]

## The Item→Equip sub-screen re-renders THIS SAME slot-6 window (§15.23, PROVEN: same
## container (172,120) 84×96 CLUT 0x7C3C, an "Order Unit" ghost of the old 5-item content
## faintly under "List") with a 4-item set. The port need not reproduce the ghost.
const ROWS_EQUIP: Array[String] = ["Equip", "Best", "Remove", "List"]

## The START-"Ability" sub-screen (§15.23 RE round 27) re-renders the SAME slot-6 window with a
## 3-item Set/Remove/Learn set — the exact mirror of the Item→Equip menu but for the Ability panel.
## Prim-scanned authoritative from oracle savestate7 (tmp/ss7_re/ram.bin, offline scan). 3 rows just
## works — the row/box-open/glove loops all key off rows.size(), so no other change is needed.
const ROWS_ABILITY: Array[String] = ["Set", "Remove", "Learn"]

## The DEPLOYMENT row set (#941) — GAME-ORIGINAL, and the first row set in this file that is not
## RE'd from the ROM. FFT's deployment screen has no action menu at all: you pick a unit off a list
## and it lands. This port keeps the ROM-faithful `ROWS` byte-untouched AND rolls its own menu,
## which was the explicit ask — the two are not a tradeoff, because `rows` has been a host-swapped
## `var` since §15.23 and the row/box-open/glove loops all key off `rows.size()`.
##
## ONE row, deliberately. The screen it opens over is already showing exactly one benched unit and
## the tile was chosen before the screen came up, so "Deploy Unit" is the whole verb — a second row
## would be a question the player has already answered. It sits in [constant LOC_DEPLOY], the one
## home sized for a single row.
const ROWS_DEPLOY: Array[String] = ["Deploy Unit"]

## The ADJUSTMENT-TURN row set (#1007) — GAME-ORIGINAL, the second row set here with no oracle
## behind it, and the one that gives the gambit surface its door.
##
## It is the ROM's five with the two roster verbs dropped and "Gambit" added. Both halves of that
## are deliberate. "Remove Unit" and "Order Unit" edit the ROSTER — mid-battle they name nothing a
## turn can do, and they were already inert on the map host (the coordinator's dispatch falls
## through to a close). "Gambit" is the fourth adjustment type design §4 calls legal, and the only
## one with no screen: equipment, job and ability slots have been editable through this menu since
## #894 landed the adjustment turn.
##
## Index 3 is "Gambit" here and "Remove Unit" in [constant ROWS]. That collision is exactly the
## hazard ADR-0247 named — "an index means nothing across two row sets" — and it is why the
## coordinator dispatches this menu BY ROW LABEL. A name means the same thing in both sets.
const ROWS_ADJUST: Array[String] = ["Item", "Ability", "Change Job", "Gambit"]

## The active row set — defaults to the 5-item START actions. A host swaps it (e.g. to
## ROWS_EQUIP) BEFORE add_child()/_ready so the menu builds with that content in the SAME
## window. Everything else (container, frame, glove, box-open) is identical (§15.23).
var rows: Array[String] = ROWS

## The window's KEY LOCATION (ADR-0088 Amendment 2) — one of the `startmenu.loc.*` slugs
## below. A host picks it BEFORE add_child()/_ready (this replaced the retired
## set-`container`-before-add_child handshake); every derived rect below is recomputed
## from the location's LIVE value in _ready, and the window element answers
## `at(location)`, so the whole menu (frame, rows, title, glove, box-open aperture)
## moves with the location — scrubbed or re-homed. A typo'd slug fails loudly at
## resolve (Tune.get_value's bind assert).
var location: String = LOC_START

# --- geometry derived from `location`'s live value in _ready (default == the START home) ----
var _container: Rect2i = Rect2i(172, 120, 84, 96)  # the active container (the location's value at build)
var _frame_rect: Rect2i = FRAME_RECT          # 9-slice frame rect (container inset by FRAME_INSET)
var _row_text_x: float = ROW_TEXT_X           # row text left x (container.x + ROW_TEXT_INSET_X)
var _row0_text_top_y: float = ROW0_TEXT_TOP_Y # row0 text top y (container.y + ROW0_TEXT_INSET_Y)
var _title_tab_pos: Vector2 = TITLE_TAB_POS   # "Menu" tab top-left (container.origin + TITLE_TAB_OFFSET)

# --- key locations (ADR-0088 Amendment 2): the window's ≥2 legal homes -----------------------
# One composite Rect2 bind per location, `startmenu.loc.*` — the Tune bind table IS the
# location registry (minted on first instance in _ready, before any element constructs;
# class statics exist before any element boots, so there is no ordering hazard). This
# static-var block documents the legal set an orchestrator selects among; each literal
# keeps its oracle citation. Authored ABSOLUTE display px — no base+delta even for the
# mirrored main_left/main_right pair (each variant is independently prim-scan-proven).
const LOC_START := "startmenu.loc.start"
const LOC_EQUIP := "startmenu.loc.equip"
const LOC_ABILITY := "startmenu.loc.ability"
const LOC_MAIN_LEFT := "startmenu.loc.main_left"
const LOC_MAIN_RIGHT := "startmenu.loc.main_right"
## The deployment menu's home (#941) — see [constant DEPLOY_CONTAINER]. The sixth legal home and
## the first with no oracle behind it.
const LOC_DEPLOY := "startmenu.loc.deploy"

## The adjustment menu's two homes (#1007) — the main-menu mirror pair, one row shorter. See
## [constant ADJUST_CONTAINER].
const LOC_ADJUST_LEFT := "startmenu.loc.adjust_left"
const LOC_ADJUST_RIGHT := "startmenu.loc.adjust_right"
## The adjustment menu's DETAIL-screen home — the ○-on-a-unit route, where the menu opens over
## the Status overlay rather than beside the roster.
const LOC_ADJUST_DETAIL := "startmenu.loc.adjust_detail"

## Container display rect {172,120,84,96} — the window STRUCT rect, PROVEN from the slot-6
## draw struct (§15.20: origin win+0x08/0x0a raw (300,120) → display (172,120) after the
## −0x80 x-bias; size win+0x14/0x16 = 84×96). This is what the box-open aperture grows
## center-out to (p=60 → {188,140,50,56}, live-confirmed), and what the glove/row placement
## formulae anchor on (`win_x`/`win_y`). It is NOT the drawn frame — see FRAME_RECT.
static var CONTAINER := Rect2(172, 120, 84, 96)  # startmenu.loc.start

## The Item→Equip sub-screen re-renders the SAME slot-6 list-menu, but at a DIFFERENT,
## smaller window container (§15.23, RE round 24 — prim scan of ram_dest.bin + framebuffer
## measure of current.png). The (172,120,84,96) rect that a naive scan also finds is the
## FADING START-menu GHOST (the "Order Unit ghost"), NOT the live Equip menu. The live
## Equip window body SPRTt is at display (196,132) 60×80; its "Menu" tab, rows, frame and
## glove all follow the SAME container-relative offsets below, so ONE container swap moves
## the whole menu. Picked by the host BEFORE add_child (`location = LOC_EQUIP`).
static var EQUIP_CONTAINER := Rect2(196, 132, 60, 80)  # startmenu.loc.equip

## The START-"Ability" (Set/Remove/Learn) list-menu container (§15.23 RE round 27 — prim scan of
## oracle savestate7 ram.bin). NARROWER AND SHORTER than the Equip menu: the window body SPRTt is
## at display (200,132) 56×64 (raw xy0=(328,132) uv=(0,0), −0x80 x-bias), its "Menu" tab at
## (203,131) = container+(3,−1), frame tan art x203..244 (right edge x244, SAME as Equip). 3 rows
## not 4 (Set/Remove/Learn), so it is shorter (64 vs 80). Everything else derives from the container
## exactly like Equip/Main. Picked by the host BEFORE add_child (`location = LOC_ABILITY`).
static var ABILITY_CONTAINER := Rect2(200, 132, 56, 64)  # startmenu.loc.ability

## The MAIN-formation (roster grid) START menu container — the SAME 5-item widget, opened by
## pressing START on the plain roster, at the TOP-LEFT (RE round 25, oracle savestate4 prim scan:
## window body SPRTt display (10,32) 84×96, "Menu" tab (13,31), frame art x13..82). Only the origin
## differs from the detail-screen CONTAINER (172,120) — everything else is derived. This is the
## LEFT variant, used when the selected unit sits on the RIGHT half of the screen.
static var MAIN_CONTAINER := Rect2(10, 32, 84, 96)  # startmenu.loc.main_left

## The RIGHT variant of the main-formation menu (RE round 26, oracle savestate6 prim scan: body
## SPRTt display (172,32) 84×96, "Menu" tab (175,31)). The menu opens OPPOSITE the selected unit's
## screen half so it never overlaps the unit: unit on the LEFT half → menu opens here (RIGHT); unit
## on the RIGHT half → menu opens at MAIN_CONTAINER (LEFT). Same y/size — only the X toggles 10↔172.
static var MAIN_CONTAINER_RIGHT := Rect2(172, 32, 84, 96)  # startmenu.loc.main_right

## The DEPLOYMENT menu container (#941) — DERIVED, not prim-scanned, and the only rect in this
## block with no oracle citation, because the ROM has no such menu to cite.
##
## Derived from the three proven variants rather than invented: each one is `rows*16 + 16` tall
## (5→96, 4→80, 3→64), so one row is 32; and each one's frame art ends at display x244 (the detail
## panels' inset), which for `FRAME_INSET`'s `x+2 … x+w-12` is `x + w = 256`. Width 96 is the
## widest that keeps that right edge while leaving room for the 11-glyph "Deploy Unit" — the
## 84-wide START home only ever had to fit "Change Job". `y` matches the Equip/Ability homes.
static var DEPLOY_CONTAINER := Rect2(160, 132, 96, 32)  # startmenu.loc.deploy

## The ADJUSTMENT menu containers (#1007) — the main-formation mirror pair at [constant
## ROWS_ADJUST]'s four rows instead of five. DERIVED by the rule the deployment home established
## and the three oracle variants prove: a container is `rows*16 + 16` tall (5→96, 4→80, 3→64), so
## dropping one row drops 16px and nothing else. Same x/y/width as the five-row pair, so the menu
## opens in the same corner opposite the unit and only its bottom edge moves up.
static var ADJUST_CONTAINER := Rect2(10, 32, 84, 80)         # startmenu.loc.adjust_left
static var ADJUST_CONTAINER_RIGHT := Rect2(172, 32, 84, 80)  # startmenu.loc.adjust_right
static var ADJUST_CONTAINER_DETAIL := Rect2(172, 120, 84, 80)  # startmenu.loc.adjust_detail

## Screen-half threshold (px) for the main-menu side flip — the 256-wide screen's centre.
const SCREEN_CENTER_X := 128.0


## The main-formation menu LOCATION for a selected unit whose sprite-centre is at screen x
## `unit_center_x` — OPPOSITE the unit's half so the menu never overlaps it (oracle ss4/ss6):
## unit LEFT half → menu RIGHT; unit RIGHT half → menu LEFT. Selection POLICY stays a pure
## static in the owner class, returning a key-location slug (Amendment 2 §4): the
## orchestrator asks policy, then sets `location` / invokes `place_at`. Guard-asserted.
static func main_container_for(unit_center_x: float) -> String:
	return LOC_MAIN_RIGHT if unit_center_x < SCREEN_CENTER_X else LOC_MAIN_LEFT


## Each five-row home paired with its four-row twin (#1007). The pairing is the whole of what a
## row set needs to know about geometry here: same corner, one row shorter.
const ADJUST_HOME_FOR := {
	LOC_START: LOC_ADJUST_DETAIL,
	LOC_MAIN_LEFT: LOC_ADJUST_LEFT,
	LOC_MAIN_RIGHT: LOC_ADJUST_RIGHT,
}


## The home `rows` wants, given the home the ROM's five would have used.
##
## Asked by the orchestrator AFTER its own side-flip policy has run, so the adjustment menu
## inherits the "open opposite the unit" rule for free instead of re-deriving it — and a row set
## with no twin (a host's own, e.g. [constant ROWS_DEPLOY]) passes straight through, which is what
## keeps this from being a rule every future row set has to opt out of.
static func home_for(rows: Array[String], default_slug: String) -> String:
	if rows == ROWS_ADJUST and ADJUST_HOME_FOR.has(default_slug):
		return String(ADJUST_HOME_FOR[default_slug])
	return default_slug


## Mint the key-location binds (Amendment 2 §2): one composite Rect2 slug per legal home,
## bound to its static-var literal above. Idempotent (Tune.bind is first-write-wins);
## called at the top of _ready so `at(location)` never evals an unregistered slug — and
## callable by guards that scrub `startmenu.loc.*` without booting a menu first.
static func _bind_locations() -> void:
	TunePort.bind(LOC_START, CONTAINER, {"step": 1.0})
	TunePort.bind(LOC_EQUIP, EQUIP_CONTAINER, {"step": 1.0})
	TunePort.bind(LOC_ABILITY, ABILITY_CONTAINER, {"step": 1.0})
	TunePort.bind(LOC_MAIN_LEFT, MAIN_CONTAINER, {"step": 1.0})
	TunePort.bind(LOC_MAIN_RIGHT, MAIN_CONTAINER_RIGHT, {"step": 1.0})
	TunePort.bind(LOC_DEPLOY, DEPLOY_CONTAINER, {"step": 1.0})
	TunePort.bind(LOC_ADJUST_LEFT, ADJUST_CONTAINER, {"step": 1.0})
	TunePort.bind(LOC_ADJUST_RIGHT, ADJUST_CONTAINER_RIGHT, {"step": 1.0})
	TunePort.bind(LOC_ADJUST_DETAIL, ADJUST_CONTAINER_DETAIL, {"step": 1.0})


## Bind the shared container-relative offsets (Amendment 2 §5) with a write-back so the
## static var — the drivers' single home — tracks a live scrub. Registered at the top of
## _ready, BEFORE the elements construct, so on a scrub the write-back lands before the
## child elements' driver subscriptions re-evaluate from it. The row insets have no
## element of their own: their consumer is the row-block rebuild (a no-op until built).
func _bind_offsets() -> void:
	TunePort.bind_update(self, SLUG_FRAME_INSET, FRAME_INSET,
		func(v: Variant) -> void: StartActionMenu.FRAME_INSET = v,
		{"step": 1.0})
	TunePort.bind_update(self, SLUG_TITLE_TAB_OFFSET, TITLE_TAB_OFFSET,
		func(v: Variant) -> void: StartActionMenu.TITLE_TAB_OFFSET = v,
		{"step": 1.0})
	TunePort.bind_update(self, SLUG_ROW_TEXT_INSET_X, ROW_TEXT_INSET_X,
		func(v: Variant) -> void: _apply_row_inset_x(float(v)),
		{"step": 1.0})
	TunePort.bind_update(self, SLUG_ROW0_TEXT_INSET_Y, ROW0_TEXT_INSET_Y,
		func(v: Variant) -> void: _apply_row0_inset_y(float(v)),
		{"step": 1.0})


## Land a row-inset scrub: write the static-var home, then re-mount the row block
## (R4 — recompute end-to-end from the tuned base; a no-op until the rows exist).
func _apply_row_inset_x(v: float) -> void:
	StartActionMenu.ROW_TEXT_INSET_X = v
	_rebuild_rows()


func _apply_row0_inset_y(v: float) -> void:
	StartActionMenu.ROW0_TEXT_INSET_Y = v
	_rebuild_rows()

## Container-relative offsets shared by ALL the window's homes (RE round 24: the START
## consts equal these applied to CONTAINER; the Equip window equals them applied to
## EQUIP_CONTAINER, matched to the framebuffer; §15.23 proves them identical per variant).
## Static-var binds (ADR-0088 Amendment 2 §5): DRIVERS, not locations — each is listed in
## the owning child element's DerivedRect drivers (frame inset → chrome element, tab
## offset → title element) or consumed by the row-block rebuild, so ONE offset knob tunes
## that part across every variant at once.
static var TITLE_TAB_OFFSET := Vector2(3, -1)   # "Menu" tab top-left = container.origin + this
static var ROW_TEXT_INSET_X := 9.0              # row text left x = container.x + this
static var ROW0_TEXT_INSET_Y := 11.0            # row0 text top y = container.y + this
static var FRAME_INSET := Rect2(2, 2, -14, -9)  # frame rect = container inset by (x,y,+w,+h)

const SLUG_TITLE_TAB_OFFSET := "startmenu.title_tab_offset"
const SLUG_ROW_TEXT_INSET_X := "startmenu.row_text_inset_x"
const SLUG_ROW0_TEXT_INSET_Y := "startmenu.row0_text_inset_y"
const SLUG_FRAME_INSET := "startmenu.frame_inset"

## The RENDERED 9-slice frame rect (display px, ss1-measured). The frame ART is inset well
## inside the struct rect: its tan spans x175..244 / y122..209, so its RIGHT edge lands on
## the detail panels' x244 inset (NOT the x256 screen edge the struct width implies), and it
## reads narrower than the aperture. The box-open aperture (CONTAINER) fully contains this,
## so the center-out scissor still reveals it; the glove/rows still anchor on CONTAINER.
const FRAME_RECT := Rect2i(174, 122, 70, 87)

## Row geometry (display px, framebuffer-measured on ss1, §15.20). Text is dark-on-tan
## FONT.BIN, left edge x≈181 (Item ink); the first row (Item) text-top ≈131; 16px row pitch.
const ROW_TEXT_X := 181.0
const ROW0_TEXT_TOP_Y := 131.0
const ROW_PITCH := 16

## The "Menu" title tab — a baked RANGETILE word cell (uv 120,120 24×8) drawn through the
## cream active-label CLUT 0x7CBC, the SAME mechanism as the Eqp/Ability window tabs (§15.19).
## Live prim `SPRTt xy0=(303,119)` → display (175,119); it pokes above the frame top-left and
## is drawn FULL (never under the body scissor).
const TITLE_TAB_NAME := "Menu"
const TITLE_TAB_POS := Vector2(175, 119)

## Glove cursor placement (`world_menu_cursor_place` FUN_800ec5b8, §15.20):
##   x = win_x + bob − 0xC ,  y = win_y + row·0x10 + 10
## anchoring the glove on the LEFT edge of the selected row, pointing in. `win_x/win_y`
## are the container display origin (172,120). Bob is added to X (axis=X, left↔right).
const CURSOR_X_BIAS := 12          # the −0xC left offset in the placement formula
const CURSOR_Y_OFFSET := 10        # the +10 in win_y + row·16 + 10
const CURSOR_SHADOW_DELTA := Vector2(2, 2)   # shadow layer offset +2/+2

# --- depth ladder (this menu stacks ABOVE the whole detail overlay) ----------
# TWO ordering channels, kept SEPARATE (they conflate in the detail screen, which caused a
# trap here). `render_priority` (RP_*, a high 40-45 band) is the DRAW-ORDER tiebreak — used
# off-fork and for same-Z opaque layering. The FOLD real-Z rung (ZR_*, a small 0-5 band) is
# what ADR-0077 turns into world-Z on the fork: Z = (overlay_rung_offset + ZR) · 0.19. The
# detail overlay tops out at real-rung 13 + its overlay 15 = 28 → Z≈5.3; the ortho camera
# sits at Z=10, so a rung must stay UNDER ~52 or it lands BEHIND the camera and vanishes.
# The menu therefore uses a small ZR band + a MENU-specific overlay (DEFAULT_MENU_RUNG=32,
# above the detail's 28, well under the camera) — NOT the detail's 40+render_priority as a
# Z-rung, which computed Z≈10.45 and clipped the whole menu out.
const RP_BASE := 40
const RP_FRAME := 40               # the 9-slice menu frame (far, in the body scissor)
const RP_ROW_TEXT := 42            # the five action-row strings
const RP_CURSOR_SHADOW := 43       # glove shadow layer (under the lit)
const RP_CURSOR_LIT := 44          # glove lit layer
const RP_TITLE := 45               # "Menu" title (drawn full, above the body)

## The default fold real-Z base rung for the menu when it opens over the detail overlay:
## above the detail's top total (13+15=28), well under the camera-clip rung (~52).
const DEFAULT_MENU_RUNG := 32

## Auto-play the box-open on _ready (headful visual check). A test drives it by hand.
@export var autoplay_open: bool = true
## Fast open (5-frame, curve step ×2) vs normal (~9-frame) — mirrors the detail screen.
@export var fast: bool = false
## The fold real-Z base rung (ADR-0077, fork only). Each element rides this + its small ZR
## delta; the host sets it so the menu's whole Z band clears the detail overlay behind it.
@export var overlay_rung_offset: int = DEFAULT_MENU_RUNG

## Emitted on confirm (○/Enter) with the chosen row 0..4. The per-item target screen is
## the outer layer's job (§15.20) — this menu only reports the choice.
signal chosen(row: int)
## Emitted on cancel (×/Backspace) — the host closes the menu back to the detail screen.
signal cancelled
## Emitted when ○ lands on a DISABLED row (ADR-0137). Named apart from `chosen` so a host can
## never mistake a refusal for a choice, and so the ROM's buzz has somewhere to hang.
signal refused(row: int)

var _atlas: RangeTileAtlas
var _menu_text: UIMenuText
var _glove_lit_pal: ImageTexture
var _glove_lit_pal_bg: ImageTexture          # §15.21 bg twin (0x7D7C→0x7DFC) for the backgrounded glove
var _glove_shadow_pal: ImageTexture
var _tab_pal: ImageTexture                   # "Menu" title-tab CLUT 0x7CBC (cream ink on dark)
var _tab_pal_bg: ImageTexture                # §15.21 bg twin of 0x7CBC

var _row: int = 0
# The registered WINDOW element (ADR-0088): movable origin, the shared BOX_OPEN beat,
# and the OWN_APERTURE clip live on it; content mounts under it via rel_world so the
# whole menu rides a window move. Replaces the hand accumulator + _body_mats clip set.
var _window: UI3Element
# The INSET drawn chrome (FRAME_RECT ⊂ CONTAINER): a child element carrying the
# MENU_TILE frame criterion, PARENT_APERTURE so the window's box-open reveals it.
var _frame_elem: UI3Element
# The "Menu" title tab element — UNCLIPPED as a DECLARED answer (§15.20: drawn full,
# outside the body scissor, poking above the frame top-left).
var _title_elem: UI3Element
# The glove cursor element — UNCLIPPED, on top, pokes out the frame's left edge.
var _cursor_elem: UI3Element
var _title_mats: Array[ShaderMaterial] = []  # the "Menu" title tab (drawn full — NOT clipped)
var _cursor_mats: Array[ShaderMaterial] = [] # glove lit+shadow (UNCLIPPED, on top — NOT in the scissor)
var _row_text_mats: Array[ShaderMaterial] = [] # the FONT.BIN row glyphs (ink-triplet swap on background)
## Per-ROW glyph materials, parallel to `rows`. `_row_text_mats` is the flat union of these and
## stays as-is (the engine-discovered clip walk reads it); this index exists because the DISABLED
## ink is per row, so re-lighting the window after a background swap must not re-light a row that
## was never lit.
var _row_mats_by_row: Array = []
## Row indices that are present but not choosable (ADR-0137). Set before add_child, or live via
## [method set_disabled_rows].
var _disabled_rows := {}
var _lit_holder: Node3D
var _shadow_holder: Node3D
var _rows_holder: Node3D                     # the row-string block (freed + re-mounted on an inset scrub)
var _backgrounded: bool = false              # §15.21: true while another surface has focus over this menu

# §15.21 "send to background" row-text ink swap. UIMenuText.mount maps body→palette_light,
# mid→palette_mid, edge→palette_dark; the bg twins are the 0x7C3C→0x7D3C remap of those inks
# (UIWindowPalettes.BG_FOR_7C3C: dark idx1, mid idx6, light idx4).
const _ROW_INK_FG_LIGHT := UIUnitNameplate.INFO_INK_DARK    # (48,40,32) glyph body
const _ROW_INK_FG_MID := UIUnitNameplate.INFO_INK_MID       # (80,80,64)
const _ROW_INK_FG_DARK := UIUnitNameplate.INFO_INK_LIGHT    # (128,120,104) glyph edge/AA
const _ROW_INK_BG_LIGHT := Color(41.0/255, 49.0/255, 57.0/255)   # bg twin of (48,40,32)
const _ROW_INK_BG_MID := Color(74.0/255, 82.0/255, 90.0/255)     # bg twin of (80,80,64)
const _ROW_INK_BG_DARK := Color(99.0/255, 107.0/255, 115.0/255)  # bg twin of (128,120,104)

## DISABLED rows (ADR-0137) — a row that is present and cursorable but cannot be chosen, which is
## how an enemy's action rows read on the map-hosted Formation screen: shown, not hidden, so the
## screen stays the same screen and only the permission differs.
##
## The ink triple is the ROM's OWN disabled ramp, already ported and RE-grounded — CLUT `0x7FA4`
## indices 1/2/3, byte-identical to `0x7FFC` indices 5/6/7, which is the glyph blitter's
## `bVar1 += shade * 4` shade-band shift. Reused from [LearnAbilityMenu] rather than restated, so
## the two screens cannot drift; nothing here is a new palette.
##
## Distinct from `_ROW_INK_BG_*` above, and the distinction matters: BACKGROUNDED is "another
## surface has focus" (the whole window goes blue-grey and comes back), DISABLED is "this row is
## not available" (per-row, and it does not come back). They compose — a backgrounded menu with a
## disabled row still shows both — which is why the ink choice below is per-row rather than a
## second global flag.
const _ROW_INK_OFF_LIGHT := LearnAbilityMenu.DIM_INKS[0]
const _ROW_INK_OFF_MID := LearnAbilityMenu.DIM_INKS[1]
const _ROW_INK_OFF_DARK := LearnAbilityMenu.DIM_INKS[2]

const _BOB_TICK := 1.0 / 60.0

# Glove bob state — a per-vsync counter; `_moving` picks the select table for a short
# window after a nav keypress, else the idle table (§15.20 / ADR-0046).
var _bob_frame: int = 0
var _bob_accum: float = 0.0
var _moving_frames: int = 0
var _idle_pairs: Array = []
var _select_pairs: Array = []


func _ready() -> void:
	_bind_locations()
	_bind_offsets()
	_atlas = RangeTileAtlas.new()
	_menu_text = UIMenuText.new()
	_idle_pairs = GloveCursorBob.load_glove_pairs("glove_idle")
	_select_pairs = GloveCursorBob.load_glove_pairs("glove_select")
	_glove_lit_pal = _palette_from_colors(_atlas.menu_glove_lit_colors())
	_glove_lit_pal_bg = _palette_from_colors(UIWindowPalettes.BG_FOR_7D7C)   # §15.21 backgrounded glove
	_glove_shadow_pal = _palette_from_colors(_atlas.menu_glove_shadow_colors())
	_tab_pal = _palette_from_colors(_atlas.window_tab_colors())
	_tab_pal_bg = _palette_from_colors(UIWindowPalettes.BG_FOR_7CBC)         # §15.21 backgrounded "Menu" tab

	# Recompute every derived rect from the active location's LIVE value (default LOC_START ==
	# the START home, so an unconfigured menu is byte-identical to before; the Equip host picks
	# location = LOC_EQUIP). The values below anchor the FROZEN content frame (rel_world):
	# a live location scrub afterwards moves only the window ORIGIN and everything rides.
	_container = Rect2i(TunePort.get_value(location, EQUIP_CONTAINER if location == LOC_EQUIP else CONTAINER))
	_frame_rect = frame_rect_for(_container)
	_row_text_x = _container.position.x + ROW_TEXT_INSET_X
	_row0_text_top_y = _container.position.y + ROW0_TEXT_INSET_Y
	_title_tab_pos = Vector2(_container.position) + TITLE_TAB_OFFSET

	_build_elements()
	_build_rows()
	_build_title()
	_build_cursor()

	if autoplay_open:
		play_open()
	# else: the window element boots settled (aperture = the full container).
	_place_cursor()


## Build the registered elements once (ADR-0088). The WINDOW answers `at(location)` —
## the host-picked key location (Amendment 2), live through the driver machinery. The
## child elements are DERIVED placements anchored on the FROZEN build container: a live
## location scrub (or place_at) moves only the window origin and they ride it (the
## movable-origin model — a live-location-reading child eval would double-move). The
## window carries the shared BOX_OPEN beat + the OWN_APERTURE clip; the inset chrome /
## title / glove are child elements answering their own clip criteria
## (PARENT_APERTURE / UNCLIPPED / UNCLIPPED).
func _build_elements() -> void:
	var c := _container
	_window = UI3Element.new({
		"id": "startmenu.window",
		# The window answers WHERE by reference to its key location (Amendment 2 §3):
		# scrubbing the location re-places the whole menu; place_at re-homes it live.
		"rect": UI3Element.at(location),
		"transition": UI3Element.Transition.BOX_OPEN,
		# The drawn chrome is INSET (FRAME_RECT ⊂ CONTAINER, §15.20 2b) — NOT the
		# window element's own frame criterion, which would size chrome to the rect.
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
		# DEFAULT_MENU_RUNG(32) − RP_BASE(40): the fold-rung offset z_for adds to each
		# payload render_priority (the menu band clears the detail overlay behind it).
		"depth_rung": DEFAULT_MENU_RUNG - RP_BASE,
		# ADR-0097 §2: one cadence per VERB. DEFAULT is the AUTHORED "use the house rule"
		# answer (opens normal, closes fast) — not silence.
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
	})
	add_child(_window)
	if fast:
		# per-instance export override of the class literal — the OPEN only (ADR-0097 §2)
		_window.spec()["open_cadence"] = UI3BoxOpenBeat.Cadence.FAST
	if overlay_rung_offset != DEFAULT_MENU_RUNG:
		_window.spec()["depth_rung"] = overlay_rung_offset - RP_BASE
	_frame_elem = UI3Element.new({
		"id": "startmenu.frame",
		# POSITION anchors on the FROZEN build container + the LIVE shared inset
		# (Amendment 2 §5): an inset scrub re-places/re-sizes the chrome across every
		# variant at once, and a location move arrives by riding the window origin (a
		# live-location-reading POSITION eval would double-move). SIZE reads the LIVE
		# window rect: origin-riding cannot resize, so a cross-container re-home
		# (place_at, START 84×96 → EQUIP 60×80) re-derives the chrome dimensions.
		"rect": UI3Element.derived([SLUG_FRAME_INSET],
			func() -> Rect2:
				var live_size := Vector2(_window.rect().size) \
					if _window != null and is_instance_valid(_window) else Vector2(c.size)
				return Rect2(Vector2(c.position) + FRAME_INSET.position,
					live_size + FRAME_INSET.size)),
		"transition": UI3Element.Transition.RIDE_PARENT,
		# The 4-quad menu frame (CLUT 0x7cfc, §15.20) = UIFrame's default flat
		# menu-tile crop; the element builds it and arms the §15.21 fg/bg CLUT swap.
		"frame": UI3Element.Frame.MENU_TILE,
		"frame_rp": RP_FRAME,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	_window.add_child(_frame_elem)
	_title_elem = UI3Element.new({
		"id": "startmenu.title",
		# Frozen build container + live tab offset — same driver model as the chrome.
		"rect": UI3Element.derived([SLUG_TITLE_TAB_OFFSET],
			func() -> Rect2: return Rect2(Vector2(c.position) + TITLE_TAB_OFFSET, Vector2(24, 8))),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_window.add_child(_title_elem)
	_cursor_elem = UI3Element.new({
		"id": "startmenu.cursor",
		# The glove anchors on the window's SELECTED key location (ADR-0088 Amendment 4 §2):
		# at(location) sharing the WINDOW's slug (not a new location) — reads as AT_LOCATION
		# named after the same home and kills the frozen-`c` capture a place_at re-home would
		# not have moved. Rides the existing startmenu.loc.* namespace (ownership guard untouched).
		# The zero-offset that makes a SHARED slug compose correctly lives in `_place_self`.
		"rect": UI3Element.at(location),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_cursor_elem.name = "GloveCursor"
	_window.add_child(_cursor_elem)


# -----------------------------------------------------------------------------
# Row model + navigation (state machine mode 3 subset, §15.20).
# -----------------------------------------------------------------------------
func selected_row() -> int:
	return _row


func row_count() -> int:
	return rows.size()


## §15.23 content swap: re-render the SAME window with a new row set — the ROM's
## in-place slot-6 re-render (the "Order Unit ghost" proof; the port skips the ghost).
## The selection resets to row 0 (oracle: the sub-menu glove opens on its first row).
## Live, the row block re-mounts anchored on the FROZEN build container, so on a
## re-homed window the rebuilt rows still land frame-relative (they ride the origin).
## Before _ready this is just the `rows` preset (the fresh-build handshake).
func set_rows(new_rows: Array[String]) -> void:
	rows = new_rows
	_row = 0
	_rebuild_rows()
	_place_cursor()


## Re-home the LIVE menu onto another key location (ADR-0088 Amendment 2 §4) — the
## whole-widget WHERE verb over the window element's place_at: the window origin
## carries the move and every child element/payload rides it; the frame chrome
## re-derives its SIZE from the new home (its rect eval reads the live window rect).
## §15.23: the ROM switches sub-menus by re-rendering this same window in place, so
## the orchestrator re-homes the live instance instead of teardown+rebuild.
## `cadence` is the one-invocation move override (ADR-0097 §4/§5), passed through to the
## window element — inert while the window declares no move beat (absent = snap).
func place_at(location_slug: String, cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	location = location_slug
	_window.place_at(location_slug, cadence)
	if _frame_elem != null and is_instance_valid(_frame_elem):
		_frame_elem.refresh_payload()   # SIZE re-derives from the live window rect


## §15.21 "send window to background": swap the WHOLE menu (frame + row glyphs + "Menu" tab + glove)
## to its deactivated blue-grey CLUTs, or back to foreground. Used when focus hands off to a surface
## OVER this menu — e.g. the Eqp slot-list focus sub-state (§15.25): the panel takes the cursor and
## THIS list-menu backgrounds (the inverse of §15.23, where the Status windows background under the
## menu). A discrete per-index CLUT swap, NOT an alpha tint. Idempotent.
func set_backgrounded(on: bool) -> void:
	_backgrounded = on
	var v := 1.0 if on else 0.0
	var frame_mat := _frame_elem.chrome_material() if _frame_elem != null else null
	if frame_mat != null:
		frame_mat.set_shader_parameter("backgrounded", v)   # nine-slice fg→bg remap
	for m in _title_mats:
		m.set_shader_parameter("backgrounded", v)            # "Menu" tab (vitals_sprite bg CLUT)
	for m in _cursor_mats:
		m.set_shader_parameter("backgrounded", v)            # glove lit swaps; subtractive shadow no-ops
	# FONT.BIN row glyphs recolour by re-setting the 3 output inks. Per ROW, not over the flat mat
	# list: a DISABLED row must keep its dim ramp when the window comes back to the foreground.
	_apply_row_inks()


func is_backgrounded() -> bool:
	return _backgrounded


## Which of the three ink states row `i` paints in. DISABLED wins over BACKGROUNDED: an unavailable
## row reads as unavailable whether or not this window currently has focus, and the disabled ramp is
## already the dimmer of the two.
func _inks_for_row(i: int) -> Array:
	if _disabled_rows.has(i):
		return [_ROW_INK_OFF_LIGHT, _ROW_INK_OFF_MID, _ROW_INK_OFF_DARK]
	if _backgrounded:
		return [_ROW_INK_BG_LIGHT, _ROW_INK_BG_MID, _ROW_INK_BG_DARK]
	return [_ROW_INK_FG_LIGHT, _ROW_INK_FG_MID, _ROW_INK_FG_DARK]


## Re-push every row's ink triple from its current state. Cheap — a uniform write per glyph, no
## rebuild — so both the background swap and a live disabled-set change route through it.
func _apply_row_inks() -> void:
	for i in _row_mats_by_row.size():
		var inks: Array = _inks_for_row(i)
		for m in _row_mats_by_row[i]:
			m.set_shader_parameter("palette_light", _ink(inks[0]))
			m.set_shader_parameter("palette_mid", _ink(inks[1]))
			m.set_shader_parameter("palette_dark", _ink(inks[2]))


## Mark rows as present-but-unchoosable (ADR-0137 — an enemy's screen is the SAME screen, read
## only). Disabled rows stay in the list and stay cursorable: the glove still walks onto them, and
## ○ REFUSES instead of choosing, which is exactly how the ROM's Learn list treats an unaffordable
## ability. Hiding them would renumber the list and make two screens out of one.
##
## Safe before `_ready` (it is just the preset the build reads) and live after.
func set_disabled_rows(indices: Array) -> void:
	_disabled_rows.clear()
	for i in indices:
		_disabled_rows[int(i)] = true
	_apply_row_inks()


## All rows disabled — the whole menu is a read-only view. The shorthand for an enemy unit.
func set_all_rows_disabled(on: bool) -> void:
	set_disabled_rows(range(rows.size()) if on else [])


func is_row_disabled(i: int) -> bool:
	return _disabled_rows.has(i)


func disabled_rows() -> Array:
	return _disabled_rows.keys()


## Show/hide the glove cursor. When focus hands off to another surface (the §15.25 Eqp slot list),
## this menu's cursor is REMOVED so there is a single active cursor on screen (the panel's) — the
## rest of the window still backgrounds (blue) via set_backgrounded.
func set_cursor_visible(on: bool) -> void:
	if _cursor_elem != null and is_instance_valid(_cursor_elem):
		_cursor_elem.visible = on


func cursor_visible() -> bool:
	return _cursor_elem != null and is_instance_valid(_cursor_elem) and _cursor_elem.visible


static func _ink(c: Color) -> Vector4:
	return Vector4(c.r, c.g, c.b, c.a)


## Move the selection down one row (wraps 4→0, as FFT list menus do). Marks the cursor
## "moving" so the glove bobs off its select table + re-places on the new row.
func move_down() -> void:
	_row = (_row + 1) % rows.size()
	_on_selection_moved()


## Move the selection up one row (wraps 0→4).
func move_up() -> void:
	_row = (_row - 1 + rows.size()) % rows.size()
	_on_selection_moved()


func _on_selection_moved() -> void:
	_moving_frames = GloveCursorBob.glove_period(_select_pairs)   # ride the select table one cycle
	_bob_frame = 0
	_place_cursor()


## Confirm the current row (○/Enter) → emit `chosen`, or `refused` when the row is DISABLED. The
## refusal is a first-class signal rather than a silent return so a host can play the ROM's buzz;
## mirrors `LearnAbilityMenu.confirm`, which is where this whole disabled mechanism comes from.
func confirm() -> void:
	if _disabled_rows.has(_row):
		refused.emit(_row)
		return
	chosen.emit(_row)


## Cancel the menu (×/Backspace) → emit `cancelled`.
func cancel() -> void:
	cancelled.emit()


# -----------------------------------------------------------------------------
# Box-open (§15.17 center-out scissor) — played by the shared TransitionEngine's
# BOX_OPEN beat on the window element (ADR-0088; the third per-class accumulator died).
# -----------------------------------------------------------------------------
## `cadence` is the one-invocation override (ADR-0097 §4) — pass a UI3BoxOpenBeat.Cadence to
## make THIS play snap or slow without changing what the element is authored to do.
func play_open(cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	_window.open(cadence)


## The center-out aperture rect (display px) at animation frame `n`. n<0 ⇒ an empty
## point at the centre (nothing revealed); n≥settle ⇒ the full container (no clip).
## Anchored on the window element's LIVE rect (== the build container until the
## location is scrubbed or the window re-homed), so a hand-driven open tracks a move.
func aperture_at_frame(n: int) -> Rect2i:
	var c := Rect2i(_window.rect()) if _window != null and is_instance_valid(_window) else _container
	if n < 0:
		return Rect2i(c.get_center(), Vector2i.ZERO)
	return UI3BoxOpenBeat.rect_for(c, n,
		UI3BoxOpenBeat.resolve(_window.cadence_for(UI3Element.OPEN_CADENCE), true))


## Park the box-open at frame `n`: drive the window element's aperture directly (the
## guard/host hand-drive; the clip engine pushes it onto the body materials).
func set_open_frame(n: int) -> void:
	_window._set_aperture(aperture_at_frame(n))


## The current body aperture (display px). size 0 ⇒ closed; == CONTAINER ⇒ fully open.
func aperture() -> Rect2i:
	return _window.aperture()


## The registered window element — the movable origin + aperture + beat carrier.
func window() -> UI3Element:
	return _window


## The inset chrome child element (the MENU_TILE frame carrier, driven by
## startmenu.frame_inset) — a guard/host handle.
func frame_element() -> UI3Element:
	return _frame_elem


## The "Menu" title tab element (driven by startmenu.title_tab_offset) — a guard/host handle.
func title_element() -> UI3Element:
	return _title_elem


## The body materials (frame + rows) the box-open scissor reveals — the clip engine's
## fresh discovery over the window element and its PARENT_APERTURE chrome child (the
## UNCLIPPED title/cursor elements excluded by their declared answers). Exposed for
## the guard: after a close, these carry the inverted `clip_world` box.
func body_materials() -> Array:
	var out := _window.payload_materials()
	if _frame_elem != null and is_instance_valid(_frame_elem):
		out.append_array(_frame_elem.payload_materials())
	return out


## The "Menu" title materials — drawn full, NEVER given the box-open clip (§15.20). Exposed
## for the guard: these must stay unclipped even when the body aperture is closed.
func title_materials() -> Array:
	return _title_mats


## The glove cursor materials (lit + shadow). Exposed for the guard: these live under the
## UNCLIPPED cursor element, so they stay visible when the box-open aperture is closed
## (§15.20 / issue 5).
func cursor_materials() -> Array:
	return _cursor_mats


# -----------------------------------------------------------------------------
# Glove cursor placement + bob (§15.20). Bob axis = X.
# -----------------------------------------------------------------------------
## The glove cursor display position (top-left of the lit layer) for `row` with bob
## offset `bob_x` — the RE'd `world_menu_cursor_place` formula. Static + pure so the
## guard can assert it without a built scene.
static func cursor_display_pos(row: int, bob_x: int) -> Vector2:
	return cursor_display_pos_in(Rect2i(CONTAINER), row, bob_x)


## The glove display position for a given container `c` — the container-relative form the
## Equip menu uses (its container differs from the START default). Pure so the guard asserts it.
static func cursor_display_pos_in(c: Rect2i, row: int, bob_x: int) -> Vector2:
	return Vector2(
		c.position.x - CURSOR_X_BIAS + bob_x,
		c.position.y + row * ROW_PITCH + CURSOR_Y_OFFSET)


## The rendered 9-slice frame rect for a container `c` (container inset by FRAME_INSET). Pure.
static func frame_rect_for(c: Rect2i) -> Rect2i:
	return Rect2i(c.position.x + int(FRAME_INSET.position.x), c.position.y + int(FRAME_INSET.position.y),
		c.size.x + int(FRAME_INSET.size.x), c.size.y + int(FRAME_INSET.size.y))


## The active window container rect — the LIVE home (== the build container until the
## location is scrubbed or the menu re-homed; the transition guards pin the settled
## sub-menu containers through this). The FROZEN build container `_container` stays the
## content anchor (rows/glove formulae) — frame-relative, it rides the window origin.
func container_rect() -> Rect2i:
	if _window != null and is_instance_valid(_window):
		return Rect2i(_window.rect())
	return _container


## The current bob offset (X px) — the select table for a short window after a nav, else
## the idle table (period 46). Exposed for the guard (bob axis = X).
func cursor_bob_x() -> int:
	var pairs := _select_pairs if _moving_frames > 0 else _idle_pairs
	return GloveCursorBob.glove_offset_for_frame(pairs, _bob_frame)


func _place_cursor() -> void:
	if _cursor_elem == null or not is_instance_valid(_cursor_elem):
		return
	var lit := cursor_display_pos_in(_container, _row, cursor_bob_x())
	var shadow := lit + CURSOR_SHADOW_DELTA
	# Home-relative under the cursor element (whose home == the container origin), so
	# the glove rides the movable window element.
	if _lit_holder != null:
		_lit_holder.position = _cursor_elem.rel_world(lit.x, lit.y)
	if _shadow_holder != null:
		_shadow_holder.position = _cursor_elem.rel_world(shadow.x, shadow.y)


# -----------------------------------------------------------------------------
# Scene build. The window CHROME (menu-tile 9-slice + §15.21 CLUT arming) is built
# by the FRAME ELEMENT from its frame criterion — see _build_elements.
# -----------------------------------------------------------------------------
func _build_rows() -> void:
	_rows_holder = Node3D.new()
	_rows_holder.name = "Rows"
	_window.add_child(_rows_holder)
	_mount_rows()


## Mount the row strings into the rows holder from the FROZEN build container + the
## LIVE row insets. rel_world subtracts the frozen home, so a rebuild on a moved or
## re-homed window still lands the rows frame-relative (they ride the origin).
func _mount_rows() -> void:
	_row_text_x = _container.position.x + ROW_TEXT_INSET_X
	_row0_text_top_y = _container.position.y + ROW0_TEXT_INSET_Y
	for i in rows.size():
		var y := _row0_text_top_y + i * ROW_PITCH
		# Row glyph mats are engine-discovered for the box-open clip (ADR-0088 §3);
		# _row_text_mats keeps them for the §15.21 ink swap only.
		var row_mats: Array[ShaderMaterial] = []
		_menu_text.mount(_rows_holder, rows[i],
			_window.rel_world(_row_text_x, y) + _window.z_for(RP_ROW_TEXT),
			RP_ROW_TEXT, _window.ppu(), row_mats, _inks_for_row(i))
		_row_text_mats.append_array(row_mats)
		_row_mats_by_row.append(row_mats)


## Live row-inset scrub consumer: tear down and re-mount the row block. Synchronous
## free (a queued free would leave doomed glyphs for the clip walk / a duplicate) and
## a fresh ink-state re-apply; the clip engine re-covers the new payload on node_added.
func _rebuild_rows() -> void:
	if _rows_holder == null or not is_instance_valid(_rows_holder):
		return
	for child in _rows_holder.get_children():
		child.free()
	_row_text_mats.clear()
	_row_mats_by_row.clear()
	_mount_rows()
	if _backgrounded:
		set_backgrounded(true)


func _build_title() -> void:
	# The "Menu" title tab is drawn FULL immediately — a baked RANGETILE word cell through the
	# cream active-label CLUT (§15.19 mechanism), NOT FONT.BIN. It mounts under the UNCLIPPED
	# title ELEMENT, so the box-open scissor never touches it (§15.20: title outside the body clip).
	if not _atlas.has_window_tab(TITLE_TAB_NAME):
		return
	_mount_static_cell(_atlas.window_tab_rect(TITLE_TAB_NAME), _title_tab_pos, _tab_pal,
		_SPRITE_SHADER, RP_TITLE, _title_mats, _tab_pal_bg)


func _build_cursor() -> void:
	# Shadow (STP, blend_mix, PSX ABR00 average) FIRST/under, then the OPAQUE lit hand. Both mount
	# under the UNCLIPPED cursor ELEMENT (its declared clip answer) so the box-open scissor never
	# clips them: the glove is on top, poking out the frame's left edge (§15.20 / issue 5). The
	# opaque lit layer writes depth so the shadow's +2,+2 overlap is hidden behind the hand and only
	# peeks out (fork). The lit hand gets the §15.21 bg glove CLUT (swapped in when the menu
	# backgrounds); the shadow is subtractive (palette-independent) so it needs no bg twin.
	_shadow_holder = _mount_glove(_atlas.menu_glove_shadow_rect(), _glove_shadow_pal, _SHADOW_SHADER, RP_CURSOR_SHADOW)
	_lit_holder = _mount_glove(_atlas.menu_glove_lit_rect(), _glove_lit_pal, _SPRITE_SHADER, RP_CURSOR_LIT, _glove_lit_pal_bg)


func _mount_glove(cell: Rect2, palette: ImageTexture, shader_path: String, rung: int,
		palette_bg: ImageTexture = null) -> Node3D:
	# A glove cursor layer under the cursor element — positioned each frame by `_place_cursor`, so
	# we set no holder position here (only the per-layer z-lift on the quad).
	var holder := Node3D.new()
	_cursor_elem.add_child(holder)
	if _atlas.texture == null or cell.size == Vector2.ZERO:
		return holder
	# The SUBTRACTIVE layer routes to its fold twin when this build folds (see _SHADOW_FOLD_SHADER).
	# Occlusion still comes from the OPAQUE lit hand above: the engine fold tests against the SHARED
	# opaque scene depth (LOADed, not cleared) with GREATER_OR_EQUAL, and the fold twin writes the
	# same reversed-Z NDC — so the hand hides the covered part exactly as in-scene and the shadow
	# still only peeks at +2/+2. (The in-scene twin's header predates that; it was written when the
	# fold owned a private scratch depth the hand could not write.)
	var folded := shader_path == _SHADOW_SHADER and Fold.owns()
	var mat := _sprite_mat(cell, palette, shader_path, rung, palette_bg)
	if folded:
		mat.shader = _SHADOW_FOLD_SHADER   # preloaded Shader (ADR-0191 dec. 2)
	_cursor_mats.append(mat)
	var mi := _quad(cell.size)
	mi.material_override = mat
	# The z-lift lives on the quad; the holder carries the dynamic display position.
	mi.position += _cursor_elem.z_for(rung)
	holder.add_child(mi)
	if folded:
		Fold.add(mi, mat, DepthMode.rung_z(rung))
	return holder


## Mount a static (fixed-position) RANGETILE cell sprite at display `disp` (top-left) — the "Menu"
## title tab, under the title ELEMENT. Collected into `mats_out` for the §15.21 CLUT swap.
func _mount_static_cell(cell: Rect2, disp: Vector2, palette: ImageTexture, shader_path: String,
		rung: int, mats_out: Array, palette_bg: ImageTexture = null) -> Node3D:
	var holder := Node3D.new()
	_title_elem.add_child(holder)
	if _atlas.texture == null or cell.size == Vector2.ZERO:
		return holder
	var mat := _sprite_mat(cell, palette, shader_path, rung, palette_bg)
	if mats_out != null:
		mats_out.append(mat)
	holder.position = _title_elem.rel_world(disp.x, disp.y) + _title_elem.z_for(rung)
	var mi := _quad(cell.size)
	mi.material_override = mat
	holder.add_child(mi)
	return holder


## Build a RANGETILE index->CLUT sprite material (shared by the title tab + both glove layers).
## `palette_bg` (optional): the §15.21 background CLUT the vitals_sprite shader swaps to when
## `backgrounded` flips on. Only the vitals_sprite path reads it; the subtractive shadow ignores it.
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
		mat.set_shader_parameter("backgrounded", 0.0)   # §15.21: armed but foreground until set_backgrounded
	mat.set_shader_parameter("brightness", 1.0)
	mat.render_priority = rung
	return mat


# -----------------------------------------------------------------------------
# Per-frame drive — the GLOVE BOB only (§15.20): the box-open accumulator retired
# into the shared TransitionEngine (ADR-0088 §4); the display↔world / clip math
# retired into UI3Element and the clip engine.
# -----------------------------------------------------------------------------
func _process(delta: float) -> void:
	# Glove bob: one table step per vsync; the select table rides one cycle after a nav.
	_bob_accum += delta
	while _bob_accum >= _BOB_TICK:
		_bob_accum -= _BOB_TICK
		_bob_frame += 1
		if _moving_frames > 0:
			_moving_frames -= 1
			if _moving_frames == 0:
				_bob_frame = 0   # hand back to the idle table at its phase 0
	_place_cursor()


# --- helpers -----------------------------------------------------------------
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
