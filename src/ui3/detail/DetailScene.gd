class_name DetailScene
extends Node3D
## The unit-detail / Status screen (FORMATION_SCREEN.md §15) — the screen the
## Formation ○-press opens on a roster unit. Composes the shipped UI widgets at the
## settled §15.14 layout and plays the §15.17 box-open animation on the lower panel.
##
## Faithfulness rule (as elsewhere): FFT visuals + layout, OUR data. Sources:
##   - windows        : `UIFrame` 9-slice (FRAME.BIN, CLUT 0x7CBC) — rows 1-5 §15.14.
##   - vitals panel   : reuse `UIUnitInfoWindow` (portrait + HP/MP/CT bars + Lv/Exp).
##   - ability icons  : the five FIXED RANGETILE cells (§15.15), new `ability_icons`
##                      atlas set, CLUT 0x7D7C.
##   - slot icons     : the five two-layer Eqp slot markers (§15.16), new `slot_icons`
##                      atlas set (dark 0x7C3C under lit 0x7D7C).
##   - weapon legend  : the ONE two-layer Weap.Power dagger/rod legend (§15.18), new
##                      `weapon_icons` atlas set (dark 0x7C3C under colourful lit 0x7D7C).
##   - box-open       : `BoxOpenAnimator` — center-out scissor reveal via the WORLD
##                      curve (§15.17 RE11/12: a clip aperture, not a geometry scale).
##
## Positions here are the settled OT/live coords from §15.14-15.16; the ones marked
## OT-approximate want a pixel-exact live pass (Item B.4) — dial them against the
## oracle as `effect-parity` does. What is still RE-open (Item B.1) is STUBBED with a
## TODO: the stat-band labels/values, the per-item ITEM.BIN icons + item names, the
## ability NAME text, and the right nameplate text. The icon MECHANISMS + the
## animation — the parts this build exists to prove — are wired for real.
##
## Vault: [[Unit Pager Buttons]]

const TunePort = ExMateriaPlatform.TunePort

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const AbilityLoadout = ExMateriaAlmanac.AbilityLoadout
const ItemDatabase = ExMateriaAlmanac.ItemDatabase
const JobDatabase = ExMateriaAlmanac.JobDatabase
const UnitProgression = ExMateriaAlmanac.UnitProgression

const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")
const UIUnitInfoWindow = preload("res://src/ui3/UIUnitInfoWindow.gd")
const UIUnitNameplate = preload("res://src/ui3/UIUnitNameplate.gd")
const UIMenuText = preload("res://src/ui3/UIMenuText.gd")
const BoxOpenAnimator = preload("res://src/ui3/detail/BoxOpenAnimator.gd")
const UIVitalsBand = preload("res://src/ui3/UIVitalsBand.gd")
const UnitInfoCluster = preload("res://src/ui3/UnitInfoCluster.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")
const EquipDeltaPalette = preload("res://src/ui3/detail/EquipDeltaPalette.gd")

const PIXELS_PER_UNIT := 0.04
const SCREEN := Vector2(256.0, 240.0)
const _SPRITE_SHADER := "res://src/ui3/shaders/vitals_sprite.gdshader"
const _SHADOW_SHADER := "res://src/ui3/shaders/menu_cursor_shadow.gdshader"   # subtractive glove drop-shadow
## The FOLD twin of the glove's subtractive layer. PSX subtracts in the 8-bit framebuffer —
## DISPLAY space — while Godot's main target is LINEAR, so the in-scene twin subtracts a
## display-magnitude constant from linear light and over-darkens as the backdrop brightens.
## The engine fold seeds a DISPLAY-space scratch from the opaque scene, runs the hardware sub
## there and resolves back through RGB555, which is the ROM's abr=2 exactly (ADR-0074).
## PRELOADED as a Shader, never named as a String: a load() of a mistyped path returns null,
## a null shader does not raise, and the fold "just stops, with no error" (ADR-0191 dec. 2).
const _SHADOW_FOLD_SHADER := preload("res://src/ui3/shaders/menu_cursor_shadow_fold.gdshader")
# The vitals-readout "black gradient stripe" — the SAME subtractive band the formation
# screen draws (§14.6.6) — is built by UIVitalsBand, which owns BOTH shaders: the fold
# variant on the fork (ALBEDO=vec3(sub), subtracting the oracle fg/255 trapezoid from the
# Pass-A scratch) and the in-scene twin as the off-fork fallback. This file used to keep
# its own dead copy of the two paths as consts; they were never read and are gone.

# --- depth ladder (within-panel ordering) -----------------------------------
# The lower panel is revealed by a growing aperture (box-open scissor, §15.17) — its content
# holds full size, so ordering is by render_priority on the sprite materials. It is ALSO a
# real-Z fold ladder (ADR-0077): the two dark
# column bands are subtractive fold prims (§15.19) that must subtract from the frame
# behind them yet be occluded by the icons that sit on them — so the lower FRAME, the
# BANDS, and the icons get a real depth rung (via _mount_icon/_add_frame `z_rung`) so
# the engine fold's Pass-B depth test orders them: frame FAR (in the Pass-A scratch) <
# band MID (folds, subtracts the scratch tan) < icons NEAR (opaque, write depth, so the
# band folds behind them). The stats-band frame + text ALSO ride the ladder now (ADR-0077
# amendment: no unauthored depth) — frame at RP_WINDOW_FRAME, glyphs/labels at RP_TEXT (strictly
# nearer than the frame). They were the last Z=0 floor holdout, which let the F3-draggable vitals
# band composite over the stats rows when dragged down; naming a rung puts the panel in front of it.
const RP_WINDOW_FRAME := 3     # FRAME.BIN 9-slice chrome (lower window: far rung)
const RP_BAND := 4             # the two dark column bands (subtractive fold; §15.19)
const RP_SLOT_DARK := 5        # Eqp slot dark backing layer
const RP_SLOT_LIT := 6         # Eqp slot lit icon (over the dark)
const RP_ITEM_ICON := 7        # per-item ITEM.BIN icon (TODO)
const RP_ABILITY_ICON := 7     # Ability-window row icon
const RP_TABS := 8             # "Eqp"/"Ability" title tabs (over the frame; §15.19)
const RP_TEXT := 9             # labels / names (TODO)
const RP_PAGER_FRAME := 10     # ◄L1/R1► corner unit-pager button frame (§15.22)
const RP_PAGER_CAP := 11       # its baked "◄L1"/"R1►" caption, over the frame body
const RP_SLOT_CURSOR_SHADOW := 13  # §15.25 Eqp slot-list glove cursor: subtractive drop-shadow (under lit)
const RP_SLOT_CURSOR_LIT := 14     # §15.25 its lit hand — ON TOP of the whole panel, pokes off the frame edge
const RP_COMPARE_BASE := 15    # §15.26 delta/compare panel: the whole group folds ABOVE the base band's
							   # ladder (max 14) — the ROM's top panel is fully opaque, so its chrome must
							   # occlude the base legend/text; only the 2px offset corner shows the pair.
							   # Its duplicated payload keeps the base's relative rungs on top of this lift.

# --- top-row depth rungs (real Z, ADR-0077) ---------------------------------
# The vitals band folds (subtractive) and must sit BEHIND the vitals panel, which
# writes depth (opaque vitals_sprite/vitals_bar) and occludes it — so the band shows
# in the gaps but never clobbers the readout. Same global-unify wiring as formation.
const RP_VITALS_BAND := 1      # the subtractive "black gradient stripe" (far)
const RP_VITALS_PANEL := 12    # the vitals panel content (near, occludes the band)

# --- "send window to background" palette swap (§15.21 — RE round 17) ---------
# CORRECTION of the earlier display-space blue-tint (RETIRED). RE'd the real mechanism: when a
# menu takes focus over the Status screen (e.g. the START action sub-menu opens), the backgrounded
# windows do NOT get an average blend toward an ambient — every window recolours via a per-index
# CLUT SWAP, uniform over the whole subtree. Each foreground CLUT maps to a fixed background CLUT:
# labels/values/dark-icons/FRAME 0x7C3C→0x7D3C, ability/lit-slot/lit-weapon icons 0x7D7C→0x7DFC,
# window tabs 0x7CBC→0x7C7C. Everything but the pre-baked-RGB FRAME is indexed+CLUT, so the swap
# is exact: the indexed shaders sample palette_bg_tex when `backgrounded`; the RGB FRAME shader
# nearest-matches its texel against the foreground CLUT and remaps to the background one. The swap
# is uniform over the lower Status subtree (frames + text + icons); the vitals/nameplate cluster is
# a SEPARATE group and is NOT swapped (it stays tan/foreground while a menu is up).
#
# Palette tables now live in the ONE shared source (UIWindowPalettes) so DetailScene + FormationScene
# read the same bg CLUTs (§15.21 "send to background"). These aliases keep the local names + values
# byte-identical (the guard's frame fg[8]/bg[8] checks still pass). Keyed by the FOREGROUND clut each
# is the bg twin of: 0x7C3C→0x7D3C (body/labels/dark icons/frame), 0x7D7C→0x7DFC (lit icons),
# 0x7CBC→0x7C7C (active tab).
const _BG_7D3C := UIWindowPalettes.BG_FOR_7C3C
const _BG_7DFC := UIWindowPalettes.BG_FOR_7D7C
const _BG_7C7C := UIWindowPalettes.BG_FOR_7CBC
# The FRAME (0x7C3C) is pre-baked RGB, not indexed — so it can't sample a CLUT. The frame shader
# instead nearest-matches its DISPLAY-space texel to _FRAME_FG (the 0x7C3C entries) and remaps to
# the same-index _FRAME_BG (the 0x7D3C entries). Vector3, /255, alpha dropped.
const _FRAME_FG := UIWindowPalettes.FRAME_FG_7C3C
const _FRAME_BG := UIWindowPalettes.FRAME_BG_7D3C

# The vitals "black gradient stripe" (§14.6.6) — the SAME shared UIVitalsBand element the
# formation roster draws (extracted 2026-08-05), here at the Status screen's TOP vitals row.
# FULL-WIDTH across the screen (x0..256), fg 0 at the top/bottom feathers, full body subtract in
# the middle; the vitals panel + nameplate (opaque, near rung) occlude it so it shows only in the
# readout gap. SAME subtract as the formation band (120/255) — the band appearance is entirely
# BACKGROUND-driven: clamp(formation_cobble − 120, 0). Where the selected unit's spotlight does NOT
# light the top-left vitals area (the typical case — oracle fb_ss9, our real use case), the cobble
# there is dark → the band crushes to pure black. Where a unit sits under the spotlight (fb_ss4),
# the same subtract leaves darkened cobble texture. Do NOT tune the subtract to one state's look —
# it's spotlight-relative; the integrated ○-press path renders over the real spotlit formation.
const VBAND_X0 := 0.0
const VBAND_X1 := 256.0
# Feather widths match the AUTHORITATIVE formation stripe (FormationScene.BAND_TOP_OUT..IN:
# 10px top / 9px bottom = clean 12/255 steps) — the detail stripe is the SAME shared element and
# never had its own oracle; its old 8px feather read too steep. The shader floor-snaps to virtual
# pixels, so these span the ROM's discrete transparency levels (12,24,…,108,120) top and bottom.
# TOP_OUT / BOT_OUT are static var (ADR-0088 Amendment 4 §2): the band's two REAL vertical
# knobs (bound to detail.vband_top_out / detail.vband_bot_out with write-back), driving the
# detail.vitals_band element rect. The screen-wide X (VBAND_X0/X1) stays structural.
static var VBAND_TOP_OUT := 30.0    # fg 0 (top feather start; 10px ramp to body)
const VBAND_TOP_IN := 40.0     # body top (full fg)
const VBAND_BOT_IN := 80.0     # body bottom (full fg)
static var VBAND_BOT_OUT := 89.0    # fg 0 (bottom feather end; 9px ramp from body)
const VBAND_FULL_SUB := 120.0 / 255.0   # same subtract as the formation band (see VBAND_X0 note)

# --- settled window rects (display 256x240, §15.14) --------------------------
# The frame BLOCK is inset ~13px from each screen edge in the oracle (sstate4 fb): every
# frame's tan fill spans x13..244 (not x2..252 — the earlier OT-approximate guess left the
# frames ~11px too wide on the left, so the content sat with a fat left margin). The column
# split stays at ~x127. Right column keeps its x130 left edge (its content is anchored
# there); only the outer edges move in to the measured 13 / 244.
const VITALS_FRAME := Rect2(13, 32, 113, 54)     # row 1  (x13..126)
const NAMEPLATE_FRAME := Rect2(130, 32, 114, 54) # row 2  (x130..244)
static var STATS_FRAME := Rect2(10.0, 92.0, 230.0, 47.0)  # row 3 — F3-pinned 2026-08-11,
													  # materialised (was 13,88,231,46; x10..240, y92..139)
# Height 42→46 (round 38, static-rooted + dynamically-verified). Data root — the picker compare-band
# frame struct `0x8018b3c4`={132,80,250,58} (via world_menu_window_open_scale 0x800ec954, bias-strip)
# → aperture y80..138, and Status-band `0x80155d68`={4,74,250,58} → y74..132; both put the band's
# visible bottom well below the old h42 (bottom y130). Dynamically PINNED via the ortho-capture oracle
# diff: h42 rendered the dark bottom border at ~y130, leaving a ~4px cobblestone gap above the equip
# picker (top y135) — the real game (fb4) shows a 1px seam. h46 lands the dark border at y133 with a
# single cobblestone row at y134, and the picker top/cream/brown at y135/136/137 match fb4 exactly.
# (FFT stacks these panels with OVERLAPPING 9-slice borders, so the seam is band-bottom→picker-top,
# not a full gap.)
# The Eqp + Ability panel is ONE monolithic window in the oracle (§15.19), not two —
# a single FRAME.BIN 9-slice spanning the full inset width. The settled OT arena shows
# a single backdrop sprite at display (12,134) 234×92; matched to the stacked STATS_FRAME
# left/right (x13..244) so the three windows read as one continuous panel. The Eqp/Ability
# split is created by the two dark column bands + the title tabs, NOT by a frame seam.
static var LOWER_FRAME := Rect2(14.0, 137.0, 230.0, 94.0)  # rows 4-5 merged — F3-pinned
													  # 2026-08-11, materialised (was 13,132,231,94)
## §15.23 Equip sub-screen: the SAME origin/height, width 231→125 (right edge x244→x138).
## Measured off the settled destination framebuffer — frame's dark right border is a clean
## full-height column at x137-138 (RE round 23; world_equip_mode_panel_builder FUN_80110480).
static var LOWER_FRAME_EQUIP := Rect2(14.0, 136.0, 125, 94)  # F3-pinned 2026-08-11, materialised
															 # (was 13,132; w/h unpinned)
## §15.23 Ability sub-screen (RE round 27, START-"Ability"): the SAME origin/height as Equip but
## NARROWER — width 117 (right edge x244→x130). Framebuffer-MEASURED off oracle savestate7 (fb.png):
## the tan interior ends at x127 and the frame's dark full-height right border is x128..130 (RE23
## method). Slightly narrower than the Eqp panel (125 → x138). Builder is slot 9 FUN_80111070
## (Ability), the parallel of slot 10 FUN_80110480 (Eqp) — refs @0x80115838 / @0x80115564.
static var LOWER_FRAME_ABILITY := Rect2(13, 132, 117, 94)  # x13..130, y132..226

# --- Ability-only sub-screen: the Ability window RELOCATED to the LEFT (§15.23 RE27) ----------
# In the JOINT Eqp+Ability Status screen the Ability column sits on the RIGHT (ABILITY_ROWS x136-138,
# ABL_TAB (131,131), band x136..152). In the ability-ONLY sub-screen the Eqp half is dropped and the
# lone Ability window slides to the LEFT (where the Eqp column normally is) — framebuffer-measured on
# oracle savestate7: the whole window shifts left by ~115px. (The RAM OT in ss7 holds a stale
# joint-layout frame — its tab prims read Eqp-left/Ability-right — so the panel is FRAMEBUFFER-rooted;
# the Set/Remove/Learn menu on the right is the current, prim-confirmed element.)
static var ABL_TAB_LEFT_POS := Vector2(16, 131)   # "Ability" tab top-left (joint (131,131) − 115; glyphs land x19..40)
static var ABL_BAND_LEFT_X0 := 21.0               # Ability-icon column band, LEFT (joint 136..152 − 115)
static var ABL_BAND_LEFT_X1 := 37.0               # framebuffer-confirmed subtract (G 104 vs empty 151 = −47 ≈ BAND_SUB)
# Ability-window row icon anchors, LEFT column (joint ABILITY_ROWS − 115; framebuffer icons x23-33,
# rows y142/158/174/190/206 pitch 16). Rows 3-4 are the 16px cells (x21); rows 0-2 the 12px (x23).
const ABILITY_ROWS_LEFT: Array[Vector2] = [
	Vector2(23, 142), Vector2(23, 158), Vector2(23, 174),
	Vector2(21, 190), Vector2(21, 206),
]

# The box-open container — the lower (Eqp/Ability) panel bounding rect (§15.17, live-measured):
# the growing aperture that reveals this window. Its centre (129,180) is the §15.17 pivot.
static var OPEN_CONTAINER := Rect2i(4, 126, 250, 108)
# The stats-band window aperture (§15.18/§15.20). The stats band is a SEPARATE box-opening
# window (builder `world_status_stats_band_builder` @0x800EABCC, its OWN
# `world_menu_window_open_scale` call) — but it SHARES the lower panel's frame counter, curve,
# AND HORIZONTAL EXTENT. User 2026-08-05, watching PCSX next to the port: "notice how they are
# the same width at all times as they open." So this aperture uses OPEN_CONTAINER's x/w
# (x4..254, w250, centre-x 129) — differing ONLY vertically (y88..130, frame-derived). The two
# windows therefore grow horizontally in LOCKSTEP and reach full width on the SAME vsync (they
# share the frame counter through the same curve). The stats band only LOOKS done first because
# it is vertically shorter (h42 vs h108) — a size illusion, NOT a stagger.
#
# Why two vertical apertures and not ONE merged reveal: the same oracle frame shows BOTH
# windows' vertical extremes at once (the stats band's TOP "Weap.Power" header AND the Eqp
# panel's BOTTOM "Clothes/Equip Chang" row) with a cobblestone GAP between them — which a single
# center-out aperture (which would clip both extremes symmetrically) cannot produce. So it is two
# vertical scissors sharing the ONE horizontal one, NOT a single box spanning stats+lower.
# (Was Rect2i(13,88,231,42) = the frame rect, w231 — narrower than the lower's w250, so the two
# widths diverged during the open; that width divergence is the bug the user spotted.)
static var STATS_CONTAINER := Rect2i(4, 88, 250, 46)   # ONLY x/w are live (the full-width box-open sweep,
# shared with the lower panel, §15.18); y/h are DERIVED from STATS_FRAME in _stats_container() so the
# aperture rides the frame (no hand-kept lockstep, no clip when the frame moves). The 88/46 y/h here are
# vestigial defaults — kept equal to STATS_FRAME's for clarity, but the derivation, not these, is used.

# Ability-window row icon anchors — settled live-OT display coords (§15.15):
# screen (266,142)/(266,158)/(266,174)/(264,190)/(264,206), −0x80 x-bias applied.
const ABILITY_ROWS: Array[Vector2] = [
	Vector2(138, 142), Vector2(138, 158), Vector2(138, 174),
	Vector2(136, 190), Vector2(136, 206),
]
# Eqp slot-category row anchors — settled live-OT display (§15.16), dialed to the
# sstate4 OT arena per row: screen x 146/146/145/144/143 (−0x80 → display 18/18/17/16/15,
# a slight left drift top→bottom), y stepping 16. Both layers (dark, lit) share the anchor.
const SLOT_ROWS: Array[Vector2] = [
	Vector2(18, 145), Vector2(18, 161), Vector2(17, 177),
	Vector2(16, 193), Vector2(15, 209),
]
# The per-item ITEM.BIN icon sits just right of the slot marker (display x30, §15.13). It straddles
# the slot row a hair high (oracle icon-core y141..158 for the y145 anchor → top ≈ anchor−4, matching
# the picker's ICON_DY). The equipped-item NAME (Broad/Leather/Clothes/Battle) begins at ~x50 (oracle
# name-ink x50..72), the tail running UNDER the equip-picker window that slides over it (the picker's
# opaque frame occludes the overflow, so we render the full name and let it be clipped — no truncation).
const ITEM_COL_X := 30.0
const EQUIP_ITEM_ICON_DY := -4.0
const EQUIP_NAME_X := 50.0
# The per-slot ability NAME begins right of the category-icon column, mirroring the Eqp
# name column (EQUIP_NAME_X). First-cut offsets — pixel-dialing against the oracle is a
# deferred F3 pass (same deferral the Eqp names got). The joint (right) column sits +115
# from the ability_only (left) column, matching the icon rows' ABILITY_ROWS/_LEFT shift.
const ABILITY_NAME_X := 155.0        # joint FULL Status screen (right column)
const ABILITY_NAME_LEFT_X := 40.0    # ability_only sub-screen (left column; oracle ink ~x40)
# The extracted ITEM.BIN icon sheet + per-type CLUT LUT — the SAME mechanism EquipPickerMenu uses for
# the picker rows (§15.26 b). Loaded once; empty (icons skipped) if the sheet is absent.
const _EQUIP_ICON_SHADER := "res://src/ui3/shaders/formation_text_opaque.gdshader"
const _EQUIP_ICON_INDEX_TEX := "res://assets/items/item_icons_index.tga"
const _EQUIP_ICON_JSON := "res://assets/items/item_icons.json"

# --- Eqp/Ability panel: dark column bands + title tabs (§15.19) --------------
# TWO vertical dark bands sit behind the icon columns — one behind the Eqp item-icon
# column, one behind the Ability icon column. Each is a subtractive rect (§15.14 row 20;
# oracle TILEt rgb(48,48,48) abr=2): the settled OT arena has them at display (30,135) and
# (136,135), both 16×90, subtracting 48/255 from the tan frame (measured: tan (160,152,128)
# → (112,104,80) = −48/channel). The SAME shared UIVitalsBand element as the vitals stripe,
# folded so the subtract is display-space — but feathered LEFT/RIGHT (per user 2026-08-05)
# so it fades into the frame the way the wide stripe fades top/bottom.
const BAND_SUB := 48.0 / 255.0           # oracle subtract amount (tan −48 → band)
static var BAND_TOP := 135.0                  # band top (display y)
static var BAND_BOT := 224.0                  # band bottom (display y; ends just above the frame bevel)
static var EQP_BAND_X0 := 30.0                # Eqp item-icon column band (display x30..46)
static var EQP_BAND_X1 := 46.0
static var ABL_BAND_X0 := 136.0               # Ability-icon column band (display x136..152)
static var ABL_BAND_X1 := 152.0
# The column bands fade LEFT/RIGHT into the tan frame (an x trapezoid, §15.19). Oracle-measured
# (fb_ss4, median-G per column): the full-subtract body is the **16px** OT rect (G 152→104) with
# a **TIGHT 2px feather OUTSIDE** each side (152→136→120→104). So the feather extends beyond the
# body (body ± feather), keeping the full 16px band and a crisp gradient — NOT a wide fade eating
# into the body (the earlier 4px-inside feather left only an 8px body, too narrow + too gradual).
const BAND_X_FEATHER := 2.0

# The two title tabs — "Eqp" / "Ability" — cream word cells (§15.19) at the top of each
# band. Live-OT display top-left: Eqp (29,131), Ability (131,131). Baked RANGETILE cells
# through the active-label CLUT 0x7CBC (cell carries its own tan fill + dark outline).
static var EQP_TAB_POS := Vector2(29, 130)   # F3-pinned 2026-08-11 (was y131)
static var ABL_TAB_POS := Vector2(131, 131)

# --- live frame tunables (ADR-0068) ------------------------------------------
# Every window/aperture/tab/band above is a `static var` (not a const) so the F3
# "Detail Screen" panel can scrub it live without a scene reload — the pain point
# was hand-dialing these by editing constants + relaunching (§15.x rounds). Each is
# bound to a `detail.*` Tune slug in `_bind_detail_tunables`; a scrub writes the var
# and rebuilds the settled lower panel (_rebuild_lower_settled). This class OWNS the
# slugs (ADR-0068 decision 12); DetailScreenDebugPanel is just a VIEW over them.
const _DT_POS := {"min": -64.0, "max": 320.0, "step": 1.0}   # top-left corner (display px)
const _DT_SIZE := {"min": 0.0, "max": 320.0, "step": 1.0}    # frame width/height (display px)
const _DT_NUDGE := {"min": -32.0, "max": 32.0, "step": 0.5}  # whole-panel align nudge
const _DT_EDGE := {"min": 0.0, "max": 256.0, "step": 1.0}    # column-band / band-y edge (display px)
var _detail_tunables_bound := false   # gate: suppress per-bind rebuild during the boot sweep
var _rebuild_pending := false         # coalesce a frame's knob scrubs into one DEFERRED rebuild (see _rebuild_if_bound)

# --- stats band layout (§15.14 row 14 + the RE-round-9 static root) ----------
# RE-ROUNDED 2026-08-04 (see FORMATION_SCREEN.md §15.18): the stats-band TEXT is NOT
# FONT.BIN. The builder is `world_status_stats_band_builder` (WORLD `FUN_800eabcc`,
# screen 0x23) and it draws:
#   * LABELS (Move/Jump/Speed/Weap.Power/AT/C-/S-/A-/EV/R/L) as baked RANGETILE sprite
#     cells from the descriptor table `0x80155D88` (18 recs {u,v,w,h,x,y}), through the
#     dark-ink-on-tan menu label CLUT 0x7C3C — the SAME mechanism as the ability/slot
#     icons. The '-' in C-/S-/A- is baked INSIDE the cell (there is no FONT dash), and a
#     shared "EV" cell draws after each, so "C-EV" == cell "C-" then cell "EV".
#   * VALUES (digits, '/', '%') from FFT's small number font (FRAME.BIN, the port's
#     NumberFont / UIMenuText.mount_number) — `%` is that font's U=192 dots+slash glyph,
#     NOT FONT.BIN's circles+slash. The "…" leader before Move/Jump/Speed and R/L values
#     is ONE number-font cell (FRAME.BIN (120,26) 6×4, FRAMEFONT glyph "…") drawn by
#     world_render_number_small (FUN_800fe37c fmt flag 0x100) at the value row +3, adv 7.
# Positions below are the byte-exact ROM descriptors (display = 12 + x_off, 88 + y_off;
# rectB = {140,88} − 0x80 X-bias via the buffer's DR_OFFSET prim). §15.29 round 48
# re-derived the equip-screen sibling table DAT_8018B3FC — SAME 18 dx/dy as 0x80155D88,
# only the value-strip blit UVs differ — and validated every record on the sstate1 live
# prim scan + framebuffer, pixel-exact. Label anchors are the cell TOP-LEFT.
const STAT_ROW_Y: Array[float] = [94.0, 106.0, 117.0]   # header / R / L row cell-tops

# VALUE rows (§15.29 round 48, ROM-exact): the values render into three scratch
# strips blitted at display y93 (Move/Jump/Speed strip, rows +0/+12/+24) and y105
# (Weap.Power + AT strips, rows +0/+12) — table DAT_8018B3FC recs 14-16, row pitch
# 12 via the job tables 0x8018B4D4/0x8018B588. Digit ink sits 1px below the strip
# row top (glyph V=0x10, ink v17); mount_number's convention lands ink at mount_y−1,
# so mount rows = strip row + 2. One shared const for MJS rows 1-3; WP/AT use [1]/[2].
const VAL_ROW_Y: Array[float] = [95.0, 107.0, 119.0]

# Labels (name → cell top-left, display px). C-/S-/A- bake the dash; EV is shared.
const LBL_MOVE := Vector2(22, 94)
const LBL_JUMP := Vector2(22, 106)
const LBL_SPEED := Vector2(17, 117)
const LBL_WEAP := Vector2(72, 94)
const LBL_R := Vector2(68, 106)
const LBL_L := Vector2(68, 118)
const LBL_AT := Vector2(147, 94)
const LBL_CDASH := Vector2(164, 94)   # "C-"
const LBL_SDASH := Vector2(190, 94)   # "S-"
const LBL_ADASH := Vector2(215, 94)   # "A-"
const AT_EV_X: Array[float] = [173.0, 198.0, 224.0]   # the shared "EV" after C-/S-/A-

# The "…" leader (§15.29 round 48, ROM-exact): NOT composed dots — ONE number-font
# cell (FRAME.BIN (120,26) 6×4, three baked 2px dots) that `world_render_number_small`
# (FUN_800fe37c, fmt flag 0x100 @0x800fe554) draws at the value row +3px, advancing 7
# so the value's first digit lands at leader_x + 7. Parsed as FRAMEFONT glyph "…".
const ELLIPSIS_ADVANCE := 7.0   # leader cell left edge = value_x − 7 (ROM strip x0)
const ELLIPSIS_DROP := 3.0      # leader cell sits 3px BELOW the value row (U=0x78,V=0x1A)

# Value columns (number-font, left edge of the value run). The "…" ends at value_x.
# Value columns (number-font, left edge of the value run) — dialed to the sstate4
# oracle (§15.18 positioning pass): each value's first-glyph left edge matches the
# oracle framebuffer (Move x51, "004" x83, AT "55" x148; measured, not OT-guessed).
# ADR-0068 static vars (detail.mjs_value_x / wp_value_x / at_val_x) so the F3 panel
# positions the stats-band numbers.
static var MJS_VALUE_X := 51.0  # Move/Jump/Speed single value (ROM strip x44 + leader 7)
static var WP_VALUE_X := 83.0   # "004 / 05%" run (Weap.Power R/L rows; ROM strip x76 + 7)
# The AT/C-EV/S-EV/A-EV value row is a FIXED 4-column table under its headers — §15.29
# round 48 ROM-exact: the value job table (0x8018B4D4/0x8018B588 group 2) composes the
# strip as AT at dst x6 (fmt 0x0002 = ALWAYS 2 digits, zero-padded — never 1-digit, so
# the column can't flow), then per EV column a kerned '/' (fmt 0x8000: cell at dst−2),
# 2 digits at dst+7, '%' after (fmt 0x2000). Strip origin display x142 ⇒ AT digits at
# 148, '/' cells at 160/185/211, EV digits at 167/192/218 ('%' rides the run at +10).
static var AT_VAL_X := 148.0                         # AT 2-digit field left edge (detail.at_val_x)
const AT_SLASH_X: Array[float] = [160.0, 185.0, 211.0]  # the 3 '/' separators (kerned cell left)
const AT_EV_COL_X: Array[float] = [167.0, 192.0, 218.0] # C-/S-/A-EV "NN%" left edges

# Extra px added around the '/' separator in the Weap.Power "PPP / EE%" run. Was 3.0 (read
# a hair wide vs the oracle — the run grew ~1px per gap); 2.0 matches the sstate4 spacing.
const TOKEN_GAP := 2.0

# The Weap.Power weapon-type legend icon (§15.18) — one FIXED two-layer emboss cell
# (silver dagger over red-tipped rod), NOT ITEM.BIN and NOT per-equipped-weapon. Its
# TOP-LEFT sits at display (130,103) (raw (258,103), −0x80 X-bias), left of the R/L rows.
# ADR-0068 static var (detail.weapon_icon_pos_x/_y) so the F3 panel positions the sword/rod.
static var WEAPON_ICON_POS := Vector2(130, 103)

## The two-handed-weapon collapse variant (§15.16): R/L.Hand merge into one icon and
## the L.Hand row hides. Off by default (1-handed, like the sstate4 oracle unit).
@export var two_handed: bool = false

## The Item→Equip sub-screen variant (§15.23, RE round 23): the lower panel is the
## Eqp-only column in a NARROWER frame (LOWER_FRAME_EQUIP) — the Ability band/tab/icons
## (slot 9 FUN_80111070) are dropped, and the selected unit stands in the revealed terrain
## gap on the right. Off by default (the full joint Eqp+Ability Status screen). Toggle it on
## an already-built screen with enter_equip_mode() (rebuilds the lower panel in place).
@export var equip_only: bool = false

## The START→Ability sub-screen variant (§15.23, RE round 27): the MIRROR of equip_only — the
## Eqp half (slot icons / item icons / Eqp band+tab) is dropped and the lone Ability window (slot 9
## FUN_80111070: its 5 fixed icons + ability names) slides to the LEFT in the NARROWER
## LOWER_FRAME_ABILITY, with the selected unit standing in the revealed terrain gap on the right.
## Mutually exclusive with equip_only. Off by default; toggle on a built screen with enter_ability_mode().
@export var ability_only: bool = false

## Auto-play the box-open on _ready (headful visual check). A test drives it by hand.
@export var autoplay_open: bool = true
## Use the fast open (5-frame, curve step ×2) vs normal (~9-frame).
@export var fast: bool = false
## Fast box-open default for NEW detail screens (ADR-0068, detail.fast) — the F3 checkbox's
## home; _ready ORs it into the per-instance export, a live scrub also flips the current instance.
static var FAST := false

## Lift every element on the ADR-0077 real-Z ladder by this many rungs. 0 = standalone
## (the DetailScreen boot, this screen IS the whole view). When the ○-press host overlays
## this DetailScene OVER the formation roster, it sets DEFAULT_OVERLAY_RUNG_OFFSET so the
## WHOLE Status screen sorts NEARER than every formation element (grid units top out at
## RP_UNIT_BODY=5, the roster's info panel at 14): the menus then occlude the units and the
## subtractive strip DARKENS them (was: units drew in front of the menu, un-darkened —
## detail's low rungs 1-9 sat BEHIND formation's 5-14). Set BEFORE add_child (read in _ready).
const DEFAULT_OVERLAY_RUNG_OFFSET := 15
@export var overlay_rung_offset: int = 0

var _atlas: RangeTileAtlas
var _ability_pal: ImageTexture
var _slot_lit_pal: ImageTexture
var _slot_dark_pal: ImageTexture
var _weapon_lit_pal: ImageTexture  # Weap.Power legend lit CLUT 0x7D7C (colourful dagger/rod)
var _weapon_dark_pal: ImageTexture # its dark backing CLUT 0x7C3C
var _label_pal: ImageTexture       # stats-band label CLUT 0x7C3C (dark ink on tan)
var _tab_pal: ImageTexture         # Eqp/Ability title-tab CLUT 0x7CBC (cream ink on dark)

# §15.21 "send to background": the per-CLUT BACKGROUND palettes, sampled by the indexed
# shaders when `backgrounded`. Same layout as the fg palettes above (0x7D7C→0x7DFC etc).
var _backgrounded := false
var _ability_pal_bg: ImageTexture
var _slot_lit_pal_bg: ImageTexture
var _slot_dark_pal_bg: ImageTexture
var _weapon_lit_pal_bg: ImageTexture
var _weapon_dark_pal_bg: ImageTexture
var _label_pal_bg: ImageTexture
var _tab_pal_bg: ImageTexture

# §15.25 Eqp slot-list FOCUS sub-state: a bobbing glove cursor over the 5 slot rows, mounted
# when ○ hands focus from the Equip list-menu into this panel. Anchored on the FRAME's left edge
# (LOWER_FRAME_EQUIP (13,132)) via StartActionMenu.cursor_display_pos_in — the SAME §15.20 formula
# the list-menu glove uses. Always FOREGROUND (the panel holds focus; only the list-menu backgrounds).
var _slot_focused := false
var _slot_row := 0
## True while the slot focus is over the ABILITY panel (not the Eqp panel): the
## cursor rides LOWER_FRAME_ABILITY and navigation cycles only the editable slots
## (the primary skillset slot 0 is job-fixed / unselectable — ABILITY_PICKER.md §1).
var _slot_ability := false
var _slot_cursor_root: Node3D
var _slot_lit_holder: Node3D
var _slot_shadow_holder: Node3D
var _slot_glove_lit_pal: ImageTexture
var _slot_glove_shadow_pal: ImageTexture
var _slot_bob_frame := 0
var _slot_bob_accum := 0.0
var _slot_moving_frames := 0
var _slot_idle_pairs: Array = []
var _slot_select_pairs: Array = []

var _open_root: Node3D             # the lower-panel group (box-open reveals its content via a clip)
# Per-frame ORIGIN nodes (the "frame = movable group" model): a frame's chrome AND its content are
# children of ONE origin node placed at the frame's top-left, positioned RELATIVE to that origin (via
# the `*_FRAME0` authored-home anchors below). Move the origin → the whole coherent frame moves. This
# replaces the old flat-sibling layout where scrubbing a frame slid the chrome off its own content
# (the ~15 absolute display consts the STATS_PANEL_NUDGE comment laments having "no shared origin").
var _stats_origin: UI3Element      # stats band = the REGISTERED ELEMENT `detail.stats` (ADR-0088):
								   # chrome + text + weapon legend ride it; the clip engine
								   # discovers its payload (the hand clip pushes retired)
var _lower_origin: UI3Element      # Eqp/Ability panel = the REGISTERED ELEMENT `detail.lower`
								   # (ADR-0088): chrome + tabs + bands + icons + equip items ride
								   # it; the clip engine discovers its payload
# The frames' AUTHORED-HOME top-left (settled §15.14 default). Content offsets are taken relative to this
# FIXED anchor (not the live tunable), so a frame-position scrub translates the origin and the content
# rides it — while a full rebuild still lands content frame-relative (rebuild-safe, no snap-back).
const STATS_FRAME0 := Vector2(13, 88)
const LOWER_FRAME0 := Vector2(13, 132)
var _stats_text_root: Node3D       # stats-band text (child of _stats_origin; rebuildable)
var _stats_legend_root: Node3D     # the sword/rod weapon legend (child of _stats_origin; delta clones it)
var _stats_frame_node: UIFrame     # the base stats-band frame chrome (kept so the delta panel mirrors it)
# §15.26 DEFECT #8: the equip-picker compare band is TWO overlapping stats panels — builder 0x80111EC4
# registered at slot 0xb (BASE, RAM nudge +2,+2) AND slot 0xc (DELTA, nudge 0,0) → the delta panel sits
# 2px UP-LEFT of the base. It exists ONLY in the picker's stats-preview state (both panels show dashes
# = zero delta on the equipped item). Built by mirroring the settled base panel, so nothing on the
# working normal-Status path changes.
static var STATS_DELTA_NUDGE := Vector2(2.0, 2.0)   # F3-tunable (detail.stats_delta_nudge_*); live only
													# in-picker. Materialised 2026-08-11: dialed DOWN-RIGHT
													# to the ROM (§15.26 C2 — the ROM's ADDED panel is the
													# (2,2) one; was (-2,-2) up-left)
# §15.26 Round 44 (locality-diff): the WHOLE stats-compare panel (base frame + text + the delta panel)
# sat ~4px DOWN and ~4px LEFT of the oracle. MEASURED off the frame BEVEL — the one feature that is
# content-free, so it survives the different-subject (Ramza vs test-Squire) noise that made label
# cross-correlation lie (it "showed" +4 RIGHT; the bevel refuted it: port frame-left x11 vs oracle x15
# = 4 left; port frame-top y+4 = 4 down). Display px, +x=right / +y=DOWN (screen); so (4, -4) shifts it
# RIGHT+UP onto the oracle. Applied as ONE runtime offset (`_stats_panel_nudge_world`) to every stats-panel
# node + the clip aperture, so frame and content move together — the base/delta 2px relationship
# (STATS_DELTA_NUDGE) rides along untouched. Not a const-by-const move (the band is ~15 absolute display
# consts with no shared origin).
static var STATS_PANEL_NUDGE := Vector2(3, -4)   # §15.29 round 48: ROM-exact zero-net —
	# origin(STATS_FRAME 10,92) + nudge − STATS_FRAME0(13,88) = (0,0), so every LBL_*/value
	# const IS the on-screen display px (oracle-measured: outside-panel landmarks align at
	# (0,0); the old (4,−4.5) left the whole band at +1,−0.5 with half-pixel AA smear)
var _stats_delta_root: UI3Element                      # the offset delta/compare panel — a REGISTERED
													   # element (ADR-0088 amendment §5): BOX_OPEN beat +
													   # OWN_APERTURE; the picker orchestration plays the verbs
var _stats_delta_mats: Array[ShaderMaterial] = []      # its frame chrome mats (for the box-open clip)
# The box-open is a growing rectangular APERTURE (a per-material `clip_world` scissor, §15.17),
# NOT a scale — the fully-rendered window is REVEALED center-out. Each box-opening window keeps
# a list of its content materials so set_open_frame can push the aperture bounds onto them:
var _stats_frame_mats: Array[ShaderMaterial] = []   # stats window chrome (built once)
var _stats_text_mats: Array[ShaderMaterial] = []    # stats band label/value glyphs (rebuilt per view)
var _lower_mats: Array[ShaderMaterial] = []         # Eqp/Ability window: frame + bands + tabs + icons
# §15.13 / worklist #4: the per-slot EQUIPPED-item ITEM.BIN icon + FONT name (Broad/Leather/Clothes/
# Battle on the oracle). Their OWN rebuildable group (child of _open_root, like _stats_text_root) so a
# selection change re-derives them from the fresh stats view. Own clip list, applied with _lower_clip
# alongside _lower_mats so the box-open aperture reveals them center-out with the rest of the panel.
var _equip_items_root: Node3D
var _equip_item_mats: Array[ShaderMaterial] = []
var _item_icon_tex: Texture2D                       # extracted ITEM.BIN icon index sheet (item_icons_index.tga)
var _item_palettes: Array = []                      # per-type 16-colour CLUTs from item_icons.json
var _type_pal_cache: Dictionary = {}                # item_type → ImageTexture, built on demand
var _equip_icon_count := 0                          # how many equipped-item icons the last build mounted (guard)
var _equip_name_count := 0                          # how many equipped-item names the last build mounted (guard)
var _ability_items_root: Node3D                     # rebuildable child holding the per-slot ability NAME column
var _ability_item_mats: Array[ShaderMaterial] = []  # the ability name glyph mats (own clip list, like _equip_item_mats)
var _ability_name_count := 0                         # how many ability-slot names the last build mounted (guard)
var _pager_mats: Array[ShaderMaterial] = []         # ◄L1/R1► corner pager buttons (§15.22; subset of the swap set)
var _button_pal: ImageTexture                       # ◄L1/R1► button CLUT 0x7D7C (shared with the sort-header)
var _button_pal_bg: ImageTexture                    # its §15.21 background twin 0x7DFC (blues on menu-open)
var _stats_preview := false                         # §15.26: stats values → "-" while the equip picker is up
# §15.26 numeric delta (EQUIP_STAT_PREVIEW.md): the signed per-field delta of the item under the
# picker/remove cursor, and which equip slot it is for (so the Weap.Power R vs L row fills). Empty
# ⇒ plain dash preview (the pre-numeric behaviour). Weapon fields (wp/wev) fill the focused hand's
# Weap.Power row; hp/mp route to the vitals numerators (set_vitals_preview_delta).
var _stats_delta_values: Dictionary = {}
var _stats_delta_slot: int = -1
## Guard seam: the exact signed strings the LAST preview build painted per band field
## ({move,jump,speed,r_at,l_at,c_ev,s_ev,a_ev} → "+N"/"-N"/"-"). Populated only on a preview build.
var _stats_delta_preview_strings: Dictionary = {}
var _delta_pal_pos: ImageTexture                    # blue number CLUT (positive delta; FRAME pal 15 +0xC)
var _delta_pal_neg: ImageTexture                    # red number CLUT (negative delta; FRAME pal 15 +0x8)
var _stats_clip: Rect2i = STATS_CONTAINER           # current stats aperture (full until the open runs)
var _lower_clip: Rect2i = OPEN_CONTAINER            # current Eqp/Ability aperture
var _cluster: UnitInfoCluster      # the shared vitals+nameplate group (slides on ○-press)
var _vitals_window: UIUnitInfoWindow  # == _cluster.vitals_panel() (kept for internal refs)
var _nameplate: UIUnitNameplate       # == _cluster.nameplate()
var _menu_text: UIMenuText         # shared FONT.BIN dark-on-tan text renderer
var _open_frame: int = 0
var _open_playing: bool = false
var _open_accum: float = 0.0
var _vitals_band_mat: ShaderMaterial   # the top "black gradient stripe" — kept so the ○-press cross-fade
									   # can ramp its `full_sub` in (§15.6: the top strip fades IN as the pair
									   # settles, while the formation bottom strip fades OUT — see band_crossfade)
var _vitals_band_mi: MeshInstance3D    # the band's compositor-render-layer carrier — a knob scrub UPDATES
									   # it in place (never frees it; freeing a FOLD_LAYER member mid-composite
									   # corrupts the 4.8-fork engine heap → SpinBox-input SIGSEGV)
var _formation_band_factor: float = 1.0  # 1 = the roster's bottom band at full; the host reads this each
									   # frame to fade it out in lockstep with this screen's top band fading in

# --- ○-press transition state (§15.5: slide → dead gap → box-open) ------------
# OPEN plays SLIDE → GAP → OPEN (box unfurls). CLOSE (Esc) plays the reverse: the box
# folds shut (CLOSE_BOX), a dead gap, then the pair slides back DOWN with the cross-fade
# run backwards (top stripe out / bottom stripe in) — "the opposite of opening". CLOSED is
# terminal; the host listens for `closed` to free the overlay + restore the roster pair.
enum _TPhase { NONE, SLIDE, ENTRY_SLIDE, GAP, OPEN, CLOSE_BOX, CLOSE_GAP, CLOSE_SLIDE, LOWER_CLOSE, CLOSED }
signal closed
## Fired when a `play_lower_close()` box-close reaches fully shut (apertures zero). The sub-screen
## (Equip/Ability) back-out GATES the rest of the exit on this: the menu/panel folds shut first, then
## the coordinator plays the reversed recipe (chrome descent + roster un-slide together). A host/test
## also reads it to observe the fold completing.
signal lower_closed
## Fired when a `play_entry_slide()` reaches the settled TOP layout (the chrome is up, the
## box-open was NOT run). The host runs the sub-screen's own transition (Change-Job / Equip /
## Ability) off this, so those main-menu entries SLIDE the top chrome instead of snapping.
signal entry_slide_done
## Fired when the box-open finishes (the ○-press Status arc has fully settled: chrome at TOP + the
## lower panel open). The coordinator (ADR-0084) emits `settled(DETAIL)` off this, so the DETAIL
## screen reports a resting state through the same seam the sub-screens do.
signal opened
const _MENU_TICK := 2.0 / 60.0   # one menu tick (keyframes held ~2 vsyncs ≈ 30 Hz)
## Per-frame catch-up ceiling for the delta-paced steppers (slide + box-open). A single
## oversized frame — a stall, a hitch, or the Hyprland `render_unfocused` throttle dropping
## the window to ~1 fps — otherwise runs the accumulator loop enough times to reach the settle
## in ONE visual frame (the "teleport"). Clamping the delta bounds each visual frame's advance
## so intermediate keyframes stay visible; normal 30-60 fps deltas are well under it, unaffected.
const _MAX_CATCHUP := 2.0 * _MENU_TICK
# The box-open advances ONE curve index PER VSYNC (§15.17) — distinct from _MENU_TICK. The ROM
# driver indexes `world_menu_open_curve` once per builder-loop iteration (once per vsync), and
# the curve ALREADY bakes the ~2-vsync holds as repeated entries ([10,10,60,60,90,90,…]). So the
# open is walked at 1/60, NOT the 2/60 menu tick — walking it at 2/60 double-counted the baked
# holds and ran the open 2× too slow (~18 vsync vs the ROM's ~9; user 2026-08-05: "the port's
# open is a little slower than PCSX"). The SLIDE phase keeps _MENU_TICK — its §15.1 keyframes are
# NOT pre-repeated, so they legitimately hold ~2 vsyncs each.
const _BOX_OPEN_TICK := 1.0 / 60.0
const _GAP_TICKS := 2            # §15.5 ~3-4 vsync dead gap between the slide and the open
var _tphase: int = _TPhase.NONE
var _tframe: int = 0
var _taccum: float = 0.0
# When the Player-driven chrome beat (begin_chrome_raise) is armed with the chrome ALREADY at TOP
# (path 2 — entered from the open detail screen), the forward steps HOLD instead of re-raising.
var _chrome_hold: bool = false
var _unit_view: Dictionary = {}
var _nameplate_view: Dictionary = {}
var _stats_view: Dictionary = {}


func _ready() -> void:
	_atlas = RangeTileAtlas.new()
	_menu_text = UIMenuText.new()
	_ability_pal = _palette_from_colors(_atlas.ability_icon_palette_colors())
	_slot_lit_pal = _palette_from_colors(_atlas.slot_icon_lit_colors())
	_slot_dark_pal = _palette_from_colors(_atlas.slot_icon_dark_colors())
	_weapon_lit_pal = _palette_from_colors(_atlas.weapon_icon_lit_colors())
	_weapon_dark_pal = _palette_from_colors(_atlas.weapon_icon_dark_colors())
	_label_pal = _palette_from_colors(_atlas.stat_label_colors())
	_tab_pal = _palette_from_colors(_atlas.window_tab_colors())
	# §15.26 equip stat-DELTA number CLUTs: a delta digit must render as the SAME digit as the
	# plain stat value beside it — same tan fill and border — with only the ink body recoloured by
	# sign. So we copy the stat-label CLUT (0x7C3C, the plain value's own palette) and recolour ink
	# indices 1·2 → blue (positive) / red (negative), the oracle FRAME-pal-15 primaries. The
	# plain/zero-dash stays _label_pal (tan). See EquipDeltaPalette.
	_delta_pal_pos = EquipDeltaPalette.texture(EquipDeltaPalette.recolour(_atlas.stat_label_colors(), EquipDeltaPalette.STATS_BLUE))
	_delta_pal_neg = EquipDeltaPalette.texture(EquipDeltaPalette.recolour(_atlas.stat_label_colors(), EquipDeltaPalette.STATS_RED))
	# §15.25 Eqp slot-list glove cursor art (same RANGETILE glove cells + bob tables as the list-menu).
	_slot_glove_lit_pal = _palette_from_colors(_atlas.menu_glove_lit_colors())
	_slot_glove_shadow_pal = _palette_from_colors(_atlas.menu_glove_shadow_colors())
	_slot_idle_pairs = GloveCursorBob.load_glove_pairs("glove_idle")
	_slot_select_pairs = GloveCursorBob.load_glove_pairs("glove_select")

	# §15.21 background CLUTs (per-index swap targets — see the palette tables above).
	_ability_pal_bg = _palette_from_colors(_BG_7DFC)
	_slot_lit_pal_bg = _palette_from_colors(_BG_7DFC)
	_weapon_lit_pal_bg = _palette_from_colors(_BG_7DFC)
	_slot_dark_pal_bg = _palette_from_colors(_BG_7D3C)
	_weapon_dark_pal_bg = _palette_from_colors(_BG_7D3C)
	_label_pal_bg = _palette_from_colors(_BG_7D3C)
	_tab_pal_bg = _palette_from_colors(_BG_7C7C)

	_load_item_icons()   # extracted ITEM.BIN icon sheet for the per-slot equipped-item icons (§15.13)
	# Register the frame tunables BEFORE the first build so any committed `detail.*` override
	# coalesces into the static vars the builders read (the bind sweep's applies fire now, but
	# _rebuild_if_bound no-ops until _detail_tunables_bound flips below).
	_bind_detail_tunables()
	fast = fast or FAST   # F3 default (the checkbox wins over the export default)
	add_to_group("box_open_panels")      # the F3 "Box-open animation" replay buttons find us here
	_build_top_panels()
	_build_lower_panel()
	_build_pager_buttons()
	_detail_tunables_bound = true   # from here, a scrub rebuilds the settled lower panel live

	if autoplay_open:
		play_open()
	else:
		set_open_frame(_open_total_frames())  # both windows settled by default (apertures = full)


## Bind the unit whose Status this screen shows. FFT visuals, OUR data: the vitals
## panel (portrait + bars + Lv/Exp) is driven from this view dict (built the same way
## FormationScene maps a roster Character, `vitals_view_from_character`). Per-slot item and
## ability NAMES are supplied separately via `set_stats_view` (equipment/ability_slots).
func set_unit_view(view: Dictionary) -> void:
	_unit_view = view
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.set_unit_view(view)


## Bind the top-right nameplate view ({number,name,job,brave,faith,zodiac}) — built
## the same way the formation roster maps a Character (`UIUnitNameplate.view_from_character`).
func set_nameplate_view(view: Dictionary) -> void:
	_nameplate_view = view
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.set_nameplate_view(view)


## Bind the middle stats-band view — the Move/Jump/Speed · Weap.Power · AT/EV numbers
## (`stats_view_from_character`). Rebuilds the band text if the panel already exists.
func set_stats_view(view: Dictionary) -> void:
	_stats_view = view
	if _open_root != null and is_instance_valid(_open_root):
		_build_stats_text()
		_build_equip_items()     # re-derive the per-slot equipped icon+name column from the fresh view
		_build_ability_items()   # re-derive the per-slot ability NAME column (Task 1) — same repaint trigger


## Map a roster [Character] to the stats-band view. OUR data (faithfulness rule),
## pulled from the same progression the vitals/nameplate read. AT (attack) per hand =
## effective PA + that hand's weapon power — the composition the oracle shows (Ramza's
## R dagger AT 55 / L 51 back-solves to PA 51, +4 WP on the R hand). The evade trio
## (C/S/A-EV) is a unit-wide readout shown on the R "main hand" row; the L row shows
## zeros (matching the oracle) since a second weapon adds no evasion of its own.
static func stats_view_from_character(character) -> Dictionary:
	var prog = character.progression
	var r_id: int = prog.equipment.get(UnitProgression.EquipSlot.RIGHT_HAND, -1)
	var l_id: int = prog.equipment.get(UnitProgression.EquipSlot.LEFT_HAND, -1)
	var pa: int = prog.get_effective_pa()
	var r_power: int = _weapon_power(r_id)
	var l_power: int = _weapon_power(l_id)
	return {
		"move": prog.get_move(),
		"jump": prog.get_jump(),
		"speed": prog.get_effective_speed(),
		"r_power": r_power, "l_power": l_power,
		"r_wev": _weapon_evade(r_id), "l_wev": _weapon_evade(l_id),
		"r_at": pa + r_power, "l_at": pa + l_power,
		"c_ev": prog.get_c_evade(),
		"s_ev": prog.get_physical_evade(),
		"a_ev": prog.get_accessory_evade(),
		# §15.13 / worklist #4: the 5 equipped items, in SLOT_ROWS order (R.Hand, L.Hand, Head, Body,
		# Accessory), for the per-slot ITEM.BIN icon + name column. Each entry is {} (empty slot) or
		# {icon_graphic, palette, name} — icon_graphic keys icon_uv_for, palette keys the ITEM.BIN CLUT
		# (ITEM_EQUIPMENT_DATA.md §5), name is the label.
		"equipment": _equipment_view(prog),
		# The 5 ability-slot NAMES, in AbilityLoadout.Slot order (Primary, Secondary, Reaction, Support,
		# Movement) matching the ABILITY_ROWS icons, for the ability panel's per-slot name column. Each
		# entry is {name} ("" = empty). The mirror of `equipment` for the Ability half (Task 1).
		"ability_slots": _ability_view(prog),
	}


## The 5-slot ability-NAME view (AbilityLoadout.Slot order) for the Ability panel's per-slot name
## column — the mirror of _equipment_view. OUR data via the loadout model, so the "what does each
## slot hold" knowledge stays in AbilityLoadout, not duplicated here. Empty "" for an unset slot.
static func _ability_view(prog) -> Array:
	var lo := AbilityLoadout.from_progression(prog)
	var out: Array = []
	for slot in [AbilityLoadout.Slot.PRIMARY, AbilityLoadout.Slot.SECONDARY,
			AbilityLoadout.Slot.REACTION, AbilityLoadout.Slot.SUPPORT, AbilityLoadout.Slot.MOVEMENT]:
		out.append({"name": _ability_slot_name(slot, lo.get_slot(slot))})
	return out


## Resolve one ability slot's DISPLAY name from its stored value. PRIMARY holds a skillset id ->
## skillset name; SECONDARY holds a JOB id -> that job's action-skillset name (job->skillset 1:1);
## R/S/M hold an ability id -> ability name. 0/empty -> "" (blank, like an unequipped item slot).
static func _ability_slot_name(slot: int, value: int) -> String:
	if value <= 0:
		return ""
	match slot:
		AbilityLoadout.Slot.PRIMARY:
			return str(AbilityDatabase.get_skill_set(value).get("name", ""))
		AbilityLoadout.Slot.SECONDARY:
			var sid := int(JobDatabase.get_job("%02x" % value).get("skill_set_id", 0))
			return str(AbilityDatabase.get_skill_set(sid).get("name", ""))
		_:
			return str(AbilityDatabase.get_ability_view(value).name)


## The 5-slot equipped-item view (SLOT_ROWS order) for the Eqp panel's per-item icon+name column.
## OUR data (ItemDatabase), the FFT layout. Empty {} for an unequipped slot (skipped at mount time).
static func _equipment_view(prog) -> Array:
	var slots := [UnitProgression.EquipSlot.RIGHT_HAND, UnitProgression.EquipSlot.LEFT_HAND,
		UnitProgression.EquipSlot.HEAD, UnitProgression.EquipSlot.BODY, UnitProgression.EquipSlot.ACCESSORY]
	var out: Array = []
	for s in slots:
		var item_id: int = prog.equipment.get(s, -1)
		if item_id < 0:
			out.append({})
		else:
			# All three fields are ItemDatabase truth: items.json `graphic` IS the ITEM.BIN menu-icon
			# cell (rec[1]) and `palette` keys its CLUT (rec[0]) — RE round 49, ITEM_EQUIPMENT_DATA.md
			# §5/§8 (the old worklist-#7 "graphic is a WEP1 sprite frame" claim was a mispaired A/B and
			# is refuted by live picker prims: Broad Sword id 19 → cell 12).
			out.append({
				"name": ItemDatabase.get_item_name(item_id),
				"palette": int(ItemDatabase.get_item(item_id).get("palette", 0)),
				"icon_graphic": ItemDatabase.get_item_graphic(item_id),
			})
	return out


static func _weapon_power(item_id: int) -> int:
	if item_id >= 0 and ItemDatabase.is_weapon(item_id):
		return ItemDatabase.get_weapon_power(item_id)
	return 0


static func _weapon_evade(item_id: int) -> int:
	if item_id >= 0 and ItemDatabase.is_weapon(item_id):
		return ItemDatabase.get_weapon_evade(item_id)
	return 0


# -----------------------------------------------------------------------------
# TOP panels (vitals + nameplate). These SLIDE in via the banner coroutine
# (§15.11), a DIFFERENT mechanism from the box-open; here they are placed settled.
# -----------------------------------------------------------------------------
func _build_top_panels() -> void:
	# The vitals readout sits on the faithful subtractive "black gradient stripe"
	# (§14.6.6), NOT the widget's flat 55%-black quad — same as the formation screen.
	_build_vitals_band()

	# The vitals panel + nameplate are the SHARED composable pair (UnitInfoCluster) —
	# the SAME two instances the formation roster docks at the bottom, here settled at
	# the Status-screen TOP layout. Owning them via the cluster is what lets the ○-press
	# transition SLIDE the real pair up (§15.5) instead of crossfading two copies. The
	# cluster applies the corrected menu placement (bars/Lv/Exp) and the ADR-0077 near
	# rung, so this composition is byte-identical to the old inline build.
	# The cluster is the registered ELEMENT root `detail.unit_cluster` (ADR-0088 Amendment 5 §4):
	# a screen-anchored assembly owning the group slide + an <id>.origin group-nudge; its vitals
	# + nameplate sub-elements register under it. Placement stays via place_layout / the slide.
	_cluster = UnitInfoCluster.new({
		"id": "detail.unit_cluster",
		"rect": UI3Element.screen_anchored(),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_cluster.name = "UnitInfoCluster"
	add_child(_cluster)
	# Lift the shared pair by the same overlay offset so it stays NEARER than the formation
	# grid AND nearer than this screen's own vitals stripe (which the panel must occlude).
	_cluster.build(PIXELS_PER_UNIT, Fold.owns(), UnitInfoCluster.RP_VITALS_PANEL, overlay_rung_offset)
	_cluster.place_layout(UnitInfoCluster.LAYOUT_TOP)
	_vitals_window = _cluster.vitals_panel()
	_nameplate = _cluster.nameplate()
	if not _unit_view.is_empty():
		_cluster.set_unit_view(_unit_view)
	if not _nameplate_view.is_empty():
		_cluster.set_nameplate_view(_nameplate_view)


# -----------------------------------------------------------------------------
# LOWER panel (stats band + Eqp + Abl) — the box-open group. Everything here is a child of
# `_open_root` and drawn at its SETTLED size; the box-open reveals it via a growing aperture
# (per-material `clip_world` scissor, §15.17), collected into the per-window material lists.
# -----------------------------------------------------------------------------
func _build_lower_panel() -> void:
	_open_root = Node3D.new()
	_open_root.name = "LowerPanel"
	# SCREEN-AT-ORIGIN anchor (ADR-0088): local coordinates under this root ARE absolute display
	# px through screen_to_world — the frame UI3Element._place_self assumes, so registered
	# elements (detail.compare today; detail.stats/lower as they migrate) parent here without a
	# hand anchor. The old container-centre anchor cancelled against _local_under_container and
	# is retired. LIFT the whole group by the overlay offset (ADR-0077 real-Z): every child
	# (frame, icons, tabs, stats text — every one now authoring its own rung) rides it up uniformly, so
	# the lower panel occludes the formation grid units behind it. The box-open no longer SCALES
	# this group — it reveals the content via the per-material `clip_world` aperture (§15.17),
	# so this Z is untouched by the open.
	_open_root.position = Vector3(0.0, 0.0, _overlay_z())
	add_child(_open_root)

	# Per-frame ORIGIN nodes (the "frame = movable group" model). Each sits at its frame's LIVE
	# top-left (the tunable position); its chrome + content mount RELATIVE to it (offsets taken from
	# the fixed `*_FRAME0` authored home). Move the origin → the whole coherent frame moves as one.
	# The stats band group = the REGISTERED ELEMENT `detail.stats` (ADR-0088). Its rect is
	# DERIVED from the live STATS_FRAME static var (the detail.stats_frame_* slugs stay the
	# tunable home this slice — a scrub rebuilds everything via _rebuild_lower_settled, so the
	# fresh element reads fresh; no composite slug mints). It places ITSELF (_open_root is
	# screen-at-origin) exactly where the old hand origin sat; chrome stays legacy _add_frame
	# payload (Frame.NONE) because the R44 panel nudge offsets it from the element origin.
	_stats_origin = UI3Element.new({
		"id": "detail.stats",
		# DERIVED with DECLARED drivers (ADR-0088 Amendment 4 §2): the detail.stats_frame_*
		# knobs already rebuild this whole panel on scrub via _rebuild_lower_settled — declaring
		# them (was a bare Callable dead-end) surfaces them inline on the UI3 page. Same eval.
		"rect": UI3Element.derived(["detail.stats_frame_x", "detail.stats_frame_y",
			"detail.stats_frame_w", "detail.stats_frame_h"],
			func() -> Rect2: return Rect2(STATS_FRAME)),
		"transition": UI3Element.Transition.BOX_OPEN,
		# ADR-0097 §2: the §15.17 sweep opens on the normal curve and closes on the fast
		# one — the house rule, named rather than assumed.
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
	})
	_stats_origin.name = "StatsOrigin"
	# The §15.17 SWEEP aperture is WIDER than the chrome (the full-width box, x/w from the
	# live STATS_CONTAINER, y/h riding the frame, all R44-nudged) — expressed as aperture_pad
	# over the rect. COMPUTED from live tunables, so written post-construction via spec()
	# (a dict literal would mint a bind whose first-registered default outlives scrubs); the
	# panel rebuilds on every one of those scrubs, so the pad is always fresh.
	var nc := _nudged_stats_container()
	var sf := STATS_FRAME
	_stats_origin.spec()["aperture_pad"] = Vector4(
		sf.position.x - nc.position.x, sf.position.y - nc.position.y,
		(nc.position.x + nc.size.x) - (sf.position.x + sf.size.x),
		(nc.position.y + nc.size.y) - (sf.position.y + sf.size.y))
	_stats_origin._set_aperture(_stats_origin.padded_rect())
	_open_root.add_child(_stats_origin)
	# The Eqp/Ability panel group = the REGISTERED ELEMENT `detail.lower` (ADR-0088), the
	# mirror of detail.stats above: rect DERIVED from the mode-dependent live frame rect
	# (LOWER_FRAME / _EQUIP / _ABILITY — a mode switch or frame scrub rebuilds everything,
	# so the fresh element reads fresh), placement via _place_self, the §15.17 full-width
	# sweep aperture as computed aperture_pad (OPEN_CONTAINER vs the frame rect).
	_lower_origin = UI3Element.new({
		"id": "detail.lower",
		# DERIVED with the UNION of all three mode frames' drivers (ADR-0088 Amendment 4 §2):
		# _lower_frame_rect() picks LOWER_FRAME / _EQUIP / _ABILITY by mode, so ALL three
		# frames' slugs drive it — a STABLE row set beats a live-changing one. Same eval.
		"rect": UI3Element.derived([
			"detail.lower_frame_x", "detail.lower_frame_y", "detail.lower_frame_w", "detail.lower_frame_h",
			"detail.lower_frame_equip_x", "detail.lower_frame_equip_y", "detail.lower_frame_equip_w", "detail.lower_frame_equip_h",
			"detail.lower_frame_ability_x", "detail.lower_frame_ability_y", "detail.lower_frame_ability_w", "detail.lower_frame_ability_h"],
			func() -> Rect2: return _lower_frame_rect()),
		"transition": UI3Element.Transition.BOX_OPEN,
		# ADR-0097 §2: the §15.17 sweep opens on the normal curve and closes on the fast
		# one — the house rule, named rather than assumed.
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
	})
	_lower_origin.name = "LowerOrigin"
	var lc := OPEN_CONTAINER
	var lf := _lower_frame_rect()
	_lower_origin.spec()["aperture_pad"] = Vector4(
		lf.position.x - lc.position.x, lf.position.y - lc.position.y,
		(lc.position.x + lc.size.x) - (lf.position.x + lf.size.x),
		(lc.position.y + lc.size.y) - (lf.position.y + lf.size.y))
	_lower_origin._set_aperture(_lower_origin.padded_rect())
	_open_root.add_child(_lower_origin)

	# The stats-band window (chrome) — on the near ladder at RP_WINDOW_FRAME (ADR-0077 dec. 7: no
	# unauthored depth). It was the last Z=0 floor holdout (z_rung=-1), one rung BEHIND the F3-draggable
	# vitals band, so dragging the band down over the stats rows composited over the opaque frame and
	# darkened it (opacity does not save a floor-parked prim — a fold band is occluded only by depth
	# that is NEARER). Now it matches its sibling lower frame; its text lifts to RP_TEXT (strictly
	# nearer than this frame, so the tan center never occludes its own glyphs). Its left/right
	# (x13..244) match the lower window's. It reveals through the STATS aperture (its own box-open), so
	# its material joins _stats_frame_mats. Under _stats_origin at the frame top-left (local 0) + the
	# R44 whole-panel align nudge.
	_stats_frame_node = _background_frame(_add_frame(_stats_origin, Rect2(Vector2.ZERO, STATS_FRAME.size), RP_WINDOW_FRAME, RP_WINDOW_FRAME, false, _stats_frame_mats))
	_stats_frame_node.position += _stats_panel_nudge_world()   # §15.26 R44: whole-panel align onto oracle

	# The Eqp + Ability panel — ONE monolithic FRAME.BIN 9-slice (§15.19), not two. Given
	# a real depth rung (RP_WINDOW_FRAME) so it lands in the fold's Pass-A scratch BEHIND
	# the subtractive column bands, which subtract its tan. Reveals through the LOWER aperture.
	# §15.23 Equip sub-screen: the frame NARROWS (231→125, right edge x244→x138) — the Ability
	# half is dropped and the selected unit stands in the revealed terrain gap (RE round 23).
	# Under _lower_origin at the frame top-left (local 0); only the WIDTH varies by mode.
	_background_frame(_add_frame(_lower_origin, Rect2(Vector2.ZERO, _lower_frame_rect().size), RP_WINDOW_FRAME, RP_WINDOW_FRAME, false, _lower_mats))

	# Which columns show, and where the Ability column sits (§15.23 RE27). THREE modes:
	#   FULL  (joint)  : Eqp column (left) + Ability column (RIGHT, ABL_*_POS)
	#   EQUIP (equip_only): Eqp column only (left); Ability half dropped
	#   ABILITY (ability_only): Ability column only, RELOCATED to the LEFT (ABL_*_LEFT_*); Eqp dropped
	# So the Eqp half shows unless ability_only; the Ability half shows unless equip_only; and the
	# Ability half's X anchors move LEFT in ability_only. One symmetric switch, not two near-copies.
	var show_eqp := not ability_only
	var show_ability := not equip_only
	var abl_tab_pos := ABL_TAB_LEFT_POS if ability_only else ABL_TAB_POS
	var abl_band0 := ABL_BAND_LEFT_X0 if ability_only else ABL_BAND_X0
	var abl_band1 := ABL_BAND_LEFT_X1 if ability_only else ABL_BAND_X1
	var abl_rows: Array = ABILITY_ROWS_LEFT if ability_only else ABILITY_ROWS

	# The dark column band(s) (§15.19) — flat subtractive rects behind each icon column,
	# folded so the subtract is display-space. Rung RP_BAND sits between the frame (far)
	# and the icons (near): it subtracts the frame's tan yet is occluded where an icon
	# (opaque, nearer) sits on it. Eqp band drops in ability_only; Ability band drops in equip_only.
	if show_eqp:
		_build_column_band("EqpBand", EQP_BAND_X0, EQP_BAND_X1)
	if show_ability:
		_build_column_band("AbilityBand", abl_band0, abl_band1)

	# The title tab(s) (§15.19) — "Eqp"/"Ability" cream word cells at the top of each band,
	# drawn like the other RANGETILE menu sprites through the active-label CLUT. Only the tab of
	# the surviving column shows in a sub-screen; the Ability tab moves LEFT in ability_only.
	if show_eqp and _atlas.has_window_tab("Eqp"):
		_mount_icon(_lower_origin, _atlas.window_tab_rect("Eqp"), EQP_TAB_POS - LOWER_FRAME0,
			_tab_pal, RP_TABS, _tab_pal_bg, RP_TABS, false, _lower_mats)
	if show_ability and _atlas.has_window_tab("Ability"):
		_mount_icon(_lower_origin, _atlas.window_tab_rect("Ability"), abl_tab_pos - LOWER_FRAME0,
			_tab_pal, RP_TABS, _tab_pal_bg, RP_TABS, false, _lower_mats)

	# Ability-window row icons (§15.15) — five FIXED cells, CLUT 0x7D7C. Near rung so they sit ON
	# the Ability band (occlude it in the fold). Dropped in equip_only; relocated LEFT in ability_only
	# (the ability-ONLY sub-screen, slot 9 FUN_80111070's window as the lone LEFT panel — RE27).
	if show_ability:
		for row in abl_rows.size():
			var cell := _atlas.ability_icon_rect(row)
			_mount_icon(_lower_origin, cell, abl_rows[row] - LOWER_FRAME0, _ability_pal, RP_ABILITY_ICON, _ability_pal_bg, RP_ABILITY_ICON, false, _lower_mats)

	# The per-slot ability NAME column (Task 1) — the mirror of the Eqp item-name column. Its own
	# rebuildable child so a commit re-derives it from the fresh stats view; empty until set_stats_view
	# supplies the loadout. Only when the Ability column shows (dropped in equip_only, like its icons).
	if show_ability:
		_ability_items_root = Node3D.new()
		_ability_items_root.name = "AbilityItems"
		# Child of _lower_origin; its glyph builders keep using _local_under_container(disp), so cancel
		# the origin's frame-anchor offset here — nets to today's world position, and rides frame moves.
		_ability_items_root.position = -_local_under_container(LOWER_FRAME0.x, LOWER_FRAME0.y)
		_lower_origin.add_child(_ability_items_root)
		_build_ability_items()

	# Eqp slot-category icons (§15.16) — two layers per row (dark backing, lit icon). These sit LEFT
	# of the Eqp band (on the tan), not on it — but share the near rungs. Dropped in ability_only.
	for slot in (_atlas.slot_icon_count() if show_eqp else 0):
		if two_handed and slot == 1:
			continue  # L.Hand row hides in the 2H-collapse variant
		var anchor := SLOT_ROWS[slot]
		var lit_cell := _atlas.slot_icon_lit_rect(slot)
		if two_handed and slot == 0:
			lit_cell = _atlas.slot_icon_2h_lit_rect()  # R/L.Hand merge into one icon
		else:
			var dark_cell := _atlas.slot_icon_dark_rect(slot)
			_mount_icon(_lower_origin, dark_cell, anchor - LOWER_FRAME0, _slot_dark_pal, RP_SLOT_DARK, _slot_dark_pal_bg, RP_SLOT_DARK, false, _lower_mats)
		_mount_icon(_lower_origin, lit_cell, anchor - LOWER_FRAME0, _slot_lit_pal, RP_SLOT_LIT, _slot_lit_pal_bg, RP_SLOT_LIT, false, _lower_mats)

	# §15.13 / worklist #4: the per-slot EQUIPPED-item ITEM.BIN icon + FONT name column (Broad/Leather/
	# Clothes/Battle on the oracle). Its own rebuildable child so a selection change re-derives it from
	# the fresh stats view; empty until set_stats_view supplies the equipment (mirrors _stats_text_root).
	if show_eqp:
		_equip_items_root = Node3D.new()
		_equip_items_root.name = "EquipItems"
		# Child of _lower_origin; its glyph/icon builders keep using _local_under_container(disp), so
		# cancel the origin's frame-anchor offset here — nets to today's world position, and rides moves.
		_equip_items_root.position = -_local_under_container(LOWER_FRAME0.x, LOWER_FRAME0.y)
		_lower_origin.add_child(_equip_items_root)
		_build_equip_items()

	# Weap.Power weapon-type legend icon (§15.18) — ONE fixed two-layer emboss (dark
	# backing under a colourful dagger/rod), left of the R/L weapon-AT rows. NOT ITEM.BIN
	# and NOT per-equipped-weapon: a decorative physical-/magic-weapon legend that never
	# varies. Same mechanism as the Eqp slot icons; shares their dark/lit depth rungs.
	# It sits INSIDE the stats band (y103), so it reveals through the STATS aperture — collect
	# it into the stats window's built-once list, not the lower panel's (§15.18).
	# Mounted under its OWN child root (local 0 under _stats_origin — net position unchanged) so the
	# §15.26 delta/compare panel can duplicate() the legend and the sword/rod rides the delta nudge
	# with the text, like the ROM's full second stats-band draw (slot 0xc).
	_stats_legend_root = Node3D.new()
	_stats_legend_root.name = "StatsWeaponLegend"
	# §15.29 round 48: the legend rides the SAME whole-panel nudge as the frame + text —
	# it was the one stats piece missing it, sitting (nudge) off the rest of the band
	# (oracle-measured sword/rod at (127,107.5) instead of the ROM's (130,103)).
	_stats_legend_root.position = _stats_panel_nudge_world()
	_stats_origin.add_child(_stats_legend_root)
	_mount_icon(_stats_legend_root, _atlas.weapon_icon_dark_rect(), WEAPON_ICON_POS - STATS_FRAME0,
		_weapon_dark_pal, RP_SLOT_DARK, _weapon_dark_pal_bg, RP_SLOT_DARK, false, _stats_frame_mats)
	_mount_icon(_stats_legend_root, _atlas.weapon_icon_lit_rect(), WEAPON_ICON_POS - STATS_FRAME0,
		_weapon_lit_pal, RP_SLOT_LIT, _weapon_lit_pal_bg, RP_SLOT_LIT, false, _stats_frame_mats)

	# Stats band (§15.14 rows 14-15) — Move/Jump/Speed · Weap.Power · AT/EV, all FONT.BIN
	# dark-on-tan text. Lives in its own child so set_stats_view() can rebuild just the
	# numbers on a selection change without disturbing the frames/icons.
	_stats_text_root = Node3D.new()
	_stats_text_root.name = "StatsText"
	# Child of _stats_origin. Its glyph builders keep using _local_under_container(disp); cancel the
	# origin's frame-anchor offset and fold in the R44 whole-panel align nudge — nets to today's world
	# position (glyphs unchanged), and the whole group rides an origin move.
	_stats_text_root.position = _stats_panel_nudge_world() - _local_under_container(STATS_FRAME0.x, STATS_FRAME0.y)
	_stats_origin.add_child(_stats_text_root)
	_build_stats_text()   # arms each glyph's bg palette itself (see its tail), so per-selection rebuilds re-arm

	# TODO(Item B.1): the per-item Eqp NAME text (rows 19) — FONT.BIN, once item IDs
	#   are threaded into a stats/eqp view (mechanism is UIMenuText, same as this band).


## The lower-panel frame rect for the current mode: the narrow Ability-only frame (§15.23 RE27,
## x13..130), the narrow Eqp-only frame (§15.23, x13..138), or the full joint Eqp+Ability frame
## (§15.19, x13..244). Origin/height are identical across all three; only the width differs.
func _lower_frame_rect() -> Rect2:
	if ability_only:
		return LOWER_FRAME_ABILITY
	return LOWER_FRAME_EQUIP if equip_only else LOWER_FRAME


## Switch an already-built Status screen into the Item→Equip sub-screen (§15.23): drop the
## Ability half, narrow the frame, keep the stats band + Eqp column + vitals/nameplate. The
## top panels (_cluster) and the pager buttons are rebuilt-cheap; the lower panel (_open_root)
## is torn down and rebuilt in equip_only geometry, then settled open. Idempotent.
func enter_equip_mode() -> void:
	if equip_only:
		return
	equip_only = true
	ability_only = false   # mutually exclusive lower modes
	_rebuild_lower_settled()


## Switch an already-built Status screen into the START→Ability sub-screen (§15.23 RE27): the MIRROR
## of enter_equip_mode — drop the Eqp half, keep the (LEFT-relocated) Ability window + stats band +
## vitals/nameplate, narrow the frame to LOWER_FRAME_ABILITY, then settle open. Idempotent.
func enter_ability_mode() -> void:
	if ability_only:
		return
	ability_only = true
	equip_only = false     # mutually exclusive lower modes
	_rebuild_lower_settled()


## Return an Equip/Ability sub-screen to the JOINT Eqp+Ability Status panel (§15.19) — the inverse of
## enter_equip_mode / enter_ability_mode, and new with ADR-0137 Amendment 7 (before it, no back-out
## ever landed BACK on the Status screen, so there was nothing to widen the frame for).
##
## It BOX-OPENS rather than snapping, unlike its two inverses. They snap because they run at the end
## of the entry recipe, which has already opened the screen; this one runs after `play_lower_close`
## has folded the narrow panel shut, and an aperture that closed has to be opened again for the
## screen to come back at all. Idempotent — a no-op on an already-joint screen.
##
## `_tphase` is armed to OPEN so the box-open's own tail fires `opened` when it rests, which is what
## lets the host report `settled(DETAIL)` at the resting screen rather than the moment it asked for
## one (ADR-0084: `settled` means arrived). OPEN is a RESTING phase for `is_transitioning`, so this
## does not lie about motion — `_open_playing` is what holds that true while the apertures grow.
func exit_sub_mode() -> void:
	if not equip_only and not ability_only:
		return
	equip_only = false
	ability_only = false
	_rebuild_lower_settled()
	_tphase = _TPhase.OPEN
	play_open()


# -----------------------------------------------------------------------------
# §15.25 The Eqp slot-list FOCUS sub-state — a bobbing glove cursor over the 5 slot rows.
# -----------------------------------------------------------------------------

## Hand INPUT FOCUS from the Equip list-menu into this panel (§15.25): mount the glove cursor on
## slot row 0 (R.Hand), anchored on the FRAME's left edge (LOWER_FRAME_EQUIP). Only meaningful on the
## settled Eqp-ONLY panel (§15.23); a no-op otherwise. The host backgrounds the list-menu in step.
func enter_slot_focus() -> void:
	if not equip_only:
		return
	_slot_focused = true
	_slot_ability = false
	_slot_row = 0
	_slot_moving_frames = 0
	_slot_bob_frame = 0
	_build_slot_cursor()
	_place_slot_cursor()


## The 4 editable ability slots (secondary/reaction/support/movement) the cursor
## cycles — the primary skillset (0) is job-fixed and never focusable (§1).
const _ABILITY_EDITABLE_ROWS := [1, 2, 3, 4]


## Hand focus into the ABILITY panel (the mirror of enter_slot_focus). Only
## meaningful on the settled ability-only sub-screen; a no-op otherwise. The
## cursor starts on the secondary row (the first editable slot).
func enter_ability_slot_focus() -> void:
	if not ability_only:
		return
	_slot_focused = true
	_slot_ability = true
	_slot_row = _ABILITY_EDITABLE_ROWS[0]
	_slot_moving_frames = 0
	_slot_bob_frame = 0
	_build_slot_cursor()
	_place_slot_cursor()


## Return focus to the list-menu (×): tear the panel cursor down. The host un-backgrounds the menu.
func exit_slot_focus() -> void:
	_slot_focused = false
	_slot_ability = false
	if _slot_cursor_root != null and is_instance_valid(_slot_cursor_root):
		_slot_cursor_root.queue_free()
	_slot_cursor_root = null
	_slot_lit_holder = null
	_slot_shadow_holder = null


func is_slot_focused() -> bool:
	return _slot_focused


func slot_row() -> int:
	return _slot_row


## True while the glove cursor is mounted over the panel (for the guard).
func slot_cursor_mounted() -> bool:
	return _slot_lit_holder != null and is_instance_valid(_slot_lit_holder)


## The settled (bob=0) display-space top-left of the glove on the current slot row — the RE'd anchor
## cursor_display_pos_in(frame,row,0) = (1, 142 + row·16), the frame's left edge (§15.25). For the guard.
func slot_cursor_anchor() -> Vector2:
	return StartActionMenu.cursor_display_pos_in(_slot_frame_container(), _slot_row, 0)


## Move the slot cursor DOWN one row (wraps 4→0, like the FFT list menus); ride the select bob table.
func slot_cursor_down() -> void:
	_slot_row = _ability_step(_slot_row, 1) if _slot_ability else (_slot_row + 1) % SLOT_ROWS.size()
	_on_slot_cursor_moved()


func slot_cursor_up() -> void:
	_slot_row = _ability_step(_slot_row, -1) if _slot_ability \
		else (_slot_row - 1 + SLOT_ROWS.size()) % SLOT_ROWS.size()
	_on_slot_cursor_moved()


## Step the ability-slot cursor by `dir` (+1/-1) over the editable slots only,
## wrapping — so the job-fixed primary (0) is skipped in both directions.
func _ability_step(row: int, dir: int) -> int:
	var i := _ABILITY_EDITABLE_ROWS.find(row)
	if i < 0:
		i = 0
	i = (i + dir + _ABILITY_EDITABLE_ROWS.size()) % _ABILITY_EDITABLE_ROWS.size()
	return _ABILITY_EDITABLE_ROWS[i]


func _on_slot_cursor_moved() -> void:
	_slot_moving_frames = GloveCursorBob.glove_period(_slot_select_pairs)
	_slot_bob_frame = 0
	_place_slot_cursor()


## The glove anchors on the Eqp panel FRAME's left edge (§15.25) — the same window-relative model as
## the list-menu, but the "window" is LOWER_FRAME_EQUIP. Rect2i so cursor_display_pos_in accepts it.
func _slot_frame_container() -> Rect2i:
	var r := LOWER_FRAME_ABILITY if _slot_ability else LOWER_FRAME_EQUIP
	return Rect2i(int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y))


func _slot_bob_x() -> int:
	var pairs := _slot_select_pairs if _slot_moving_frames > 0 else _slot_idle_pairs
	return GloveCursorBob.glove_offset_for_frame(pairs, _slot_bob_frame)


func _build_slot_cursor() -> void:
	if _slot_cursor_root != null and is_instance_valid(_slot_cursor_root):
		return
	if _open_root == null or not is_instance_valid(_open_root):
		return
	# The slot glove is HOUSED in the registered element `detail.slot_cursor` (ADR-0088
	# audit): screen-anchored (holders place per-row in absolute display px), UNCLIPPED as
	# the DECLARED §15.25 answer — the glove pokes off the frame edge, on top, never in the
	# box-open scissor (previously encoded by _lower_mats omission).
	_slot_cursor_root = UI3Element.new({
		"id": "detail.slot_cursor",
		"rect": UI3Element.screen_anchored(),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_slot_cursor_root.name = "SlotGloveCursor"
	_open_root.add_child(_slot_cursor_root)
	# Shadow (subtractive) under the OPAQUE lit hand — both UNCLIPPED (not in _lower_mats), ON TOP of
	# the settled panel, poking off the frame's left edge (§15.25 / §15.20 issue 5).
	_slot_shadow_holder = _mount_slot_glove(_atlas.menu_glove_shadow_rect(), _slot_glove_shadow_pal, _SHADOW_SHADER, RP_SLOT_CURSOR_SHADOW)
	_slot_lit_holder = _mount_slot_glove(_atlas.menu_glove_lit_rect(), _slot_glove_lit_pal, _SPRITE_SHADER, RP_SLOT_CURSOR_LIT)


func _mount_slot_glove(cell: Rect2, palette: ImageTexture, shader_path: String, rung: int) -> Node3D:
	var holder := Node3D.new()
	_slot_cursor_root.add_child(holder)
	if _atlas.texture == null or cell.size == Vector2.ZERO:
		return holder
	# The SUBTRACTIVE layer routes to its fold twin when this build folds (see _SHADOW_FOLD_SHADER).
	# Occlusion still comes from the OPAQUE lit hand above: the engine fold tests against the SHARED
	# opaque scene depth (LOADed, not cleared) with GREATER_OR_EQUAL, and the fold twin writes the
	# same reversed-Z NDC — so the hand hides the covered part exactly as in-scene.
	var folded := shader_path == _SHADOW_SHADER and Fold.owns()
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.set_shader_parameter("index_atlas", _atlas.texture)
	mat.set_shader_parameter("atlas_size", Vector2(_atlas.texture.get_width(), _atlas.texture.get_height()))
	mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y))
	mat.set_shader_parameter("palette_tex", palette)
	mat.set_shader_parameter("brightness", 1.0)
	mat.render_priority = rung
	if folded:
		mat.shader = _SHADOW_FOLD_SHADER   # preloaded Shader (ADR-0191 dec. 2)
	var mi := _quad(cell.size)
	mi.material_override = mat
	if Fold.owns():
		mi.position += Vector3(0.0, 0.0, DepthMode.rung_z(rung))   # per-layer real-Z lift, above the settled panel
	holder.add_child(mi)
	if folded:
		Fold.add(mi, mat, DepthMode.rung_z(rung))
	return holder


## Position the glove holders on the current row (+ bob). Holders are children of _open_root, so we
## place them container-relative (via _local_under_container) — the SAME frame as the slot icons.
func _place_slot_cursor() -> void:
	if _slot_lit_holder == null or not is_instance_valid(_slot_lit_holder):
		return
	var lit := StartActionMenu.cursor_display_pos_in(_slot_frame_container(), _slot_row, _slot_bob_x())
	var shadow := lit + StartActionMenu.CURSOR_SHADOW_DELTA
	_slot_lit_holder.position = _local_under_container(lit.x, lit.y)
	if _slot_shadow_holder != null and is_instance_valid(_slot_shadow_holder):
		_slot_shadow_holder.position = _local_under_container(shadow.x, shadow.y)


## Tear the whole lower-panel group down (frames, bands, tabs, icons, stats text, pager buttons are
## all children of _open_root) + clear its material collections, then rebuild it in the CURRENT mode
## (equip_only / ability_only / joint) and settle it open. Shared by enter_equip_mode/enter_ability_mode.
func _rebuild_lower_settled() -> void:
	if _open_root != null and is_instance_valid(_open_root):
		_open_root.free()   # synchronous: called from a menu callback, not _open_root's own signal
	_open_root = null
	_stats_origin = null
	_lower_origin = null
	_stats_text_root = null
	_stats_legend_root = null
	_equip_items_root = null
	_ability_items_root = null
	_lower_mats.clear()
	_equip_item_mats.clear()
	_ability_item_mats.clear()
	_stats_frame_mats.clear()
	_stats_text_mats.clear()
	_pager_mats.clear()
	_build_lower_panel()      # respects equip_only/ability_only (narrow frame, dropped column)
	_build_pager_buttons()    # ◄L1/R1► corner buttons live under _open_root, so rebuild them too
	set_open_frame(_open_total_frames())   # settle the panel open (no whole-screen box-open, §15.23)


# -----------------------------------------------------------------------------
# Live frame tunables (ADR-0068) — bind each window/aperture/tab/band `static var`
# above to a `detail.*` Tune slug. The apply writes the var + rebuilds the settled
# lower panel, so a scrub in the F3 "Detail Screen" panel dials the layout live. All
# the tuned frames live under `_open_root`, so ONE rebuild path (_rebuild_lower_settled)
# covers every knob. Mirrors FormationScene._bind_tunables (the proven roster pattern).
# -----------------------------------------------------------------------------
func _bind_detail_tunables() -> void:
	if Engine.is_editor_hint():
		return
	# Window frames + box-open apertures — top-left corner (x,y) + size (w,h).
	_dt_rect("STATS_FRAME")            # stats band (Move/Jump/… row)
	_dt_rect("LOWER_FRAME")            # Eqp+Ability joint panel
	_dt_rect("LOWER_FRAME_EQUIP")      # Equip-only sub-screen frame
	_dt_rect("LOWER_FRAME_ABILITY")    # Ability-only sub-screen frame
	_dt_rect("OPEN_CONTAINER")         # lower box-open aperture (clip rect)
	_dt_rect_xw("STATS_CONTAINER")     # stats aperture: only x/w are live (y/h derived from STATS_FRAME)
	# Tab positions + the whole-stats-panel align nudge — top-left corner only.
	_dt_vec2("EQP_TAB_POS")
	_dt_vec2("ABL_TAB_POS")
	_dt_vec2("ABL_TAB_LEFT_POS")
	_dt_vec2("STATS_PANEL_NUDGE", _DT_NUDGE)
	_dt_vec2("STATS_DELTA_NUDGE", _DT_NUDGE)   # compare/delta (fg) panel offset — visibly moves only in-picker preview
	_dt_vec2("WEAPON_ICON_POS")                # the sword/rod Weap.Power legend (§15.18) top-left
	# Stats-band value columns (§15.18 — the number runs; labels stay ROM-descriptor consts).
	_dt_scalar("MJS_VALUE_X")
	_dt_scalar("WP_VALUE_X")
	_dt_scalar("AT_VAL_X")
	# Box-open speed (§15.17) — consumed on the next play; also flips the live instance.
	TunePort.bind_update(self, "detail.fast", FAST,
		func(v: bool) -> void:
			set("FAST", v)
			fast = bool(v))
	# Dark column-band edges (x) + shared band top/bottom (y).
	_dt_scalar("EQP_BAND_X0"); _dt_scalar("EQP_BAND_X1")
	_dt_scalar("ABL_BAND_X0"); _dt_scalar("ABL_BAND_X1")
	_dt_scalar("ABL_BAND_LEFT_X0"); _dt_scalar("ABL_BAND_LEFT_X1")
	_dt_scalar("BAND_TOP"); _dt_scalar("BAND_BOT")
	# The vitals stripe's two real vertical knobs (Amendment 4 §2): the write-back sets the static
	# var, then reshapes the band MESH in place. The detail.vitals_band element re-places its own
	# transform live off these same slugs (its derived-rect driver subscription), so we only touch
	# the mesh height + feather here — NEVER free/rebuild (ADR-0068 W1–W3, write-back shape #1).
	# A tunable write-back runs inside the F3 SpinBox's gui_input callstack; any synchronous free()
	# there SIGSEGVs the 4.8 fork (not a fold problem — see CONTEXT "Fold member lifetime"). In-place
	# mutation frees nothing, so it is safe to run synchronously on the input frame. No-op pre-build.
	for band_prop in ["VBAND_TOP_OUT", "VBAND_BOT_OUT"]:
		var p: String = band_prop
		TunePort.bind_update(self, "detail." + p.to_lower(), float(get(p)),
			func(v: float) -> void:
				set(p, v)
				_update_vitals_band(), _DT_EDGE)


## Bind a Rect2/Rect2i frame `static var` to four `detail.<prop>_x/_y/_w/_h` float slugs
## (top-left corner + size). The apply recomposes the whole rect (value-type structs don't
## write back through a Variant) — Rect2i frames round the scrub to int.
func _dt_rect(prop: String) -> void:
	var base: Variant = get(prop)
	var is_i: bool = base is Rect2i
	var slug := "detail." + prop.to_lower()
	var comps := ["x", "y", "w", "h"]
	var vals := [base.position.x, base.position.y, base.size.x, base.size.y]
	for i in 4:
		var idx := i
		TunePort.bind_update(self, "%s_%s" % [slug, comps[idx]], float(vals[idx]),
			func(v: float) -> void:
				var r: Variant = get(prop)
				var c := [r.position.x, r.position.y, r.size.x, r.size.y]
				c[idx] = v
				if is_i:
					set(prop, Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
				else:
					set(prop, Rect2(c[0], c[1], c[2], c[3]))
				_rebuild_if_bound(),
			(_DT_POS if idx < 2 else _DT_SIZE))


## Bind ONLY the x + width of a Rect2/Rect2i frame (for STATS_CONTAINER, whose y/h are DERIVED from
## STATS_FRAME in _stats_container()). Mirrors _dt_rect but skips the y/h knobs so the panel has no
## dead controls — the aperture's vertical extent belongs to the frame, its horizontal extent is its own.
func _dt_rect_xw(prop: String) -> void:
	var base: Variant = get(prop)
	var is_i: bool = base is Rect2i
	var slug := "detail." + prop.to_lower()
	for pair in [["x", 0], ["w", 2]]:
		var comp: String = pair[0]
		var idx: int = pair[1]
		var vals := [base.position.x, base.position.y, base.size.x, base.size.y]
		TunePort.bind_update(self, "%s_%s" % [slug, comp], float(vals[idx]),
			func(v: float) -> void:
				var r: Variant = get(prop)
				var c := [r.position.x, r.position.y, r.size.x, r.size.y]
				c[idx] = v
				if is_i:
					set(prop, Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
				else:
					set(prop, Rect2(c[0], c[1], c[2], c[3]))
				_rebuild_if_bound(),
			(_DT_POS if idx < 2 else _DT_SIZE))


## Bind a Vector2 `static var` (tab pos / align nudge) to `detail.<prop>_x` / `_y` slugs.
func _dt_vec2(prop: String, hint: Dictionary = _DT_POS) -> void:
	var base: Vector2 = get(prop)
	var slug := "detail." + prop.to_lower()
	TunePort.bind_update(self, "%s_x" % slug, base.x, func(v: float) -> void:
		set(prop, Vector2(v, (get(prop) as Vector2).y)); _rebuild_if_bound(), hint)
	TunePort.bind_update(self, "%s_y" % slug, base.y, func(v: float) -> void:
		set(prop, Vector2((get(prop) as Vector2).x, v)); _rebuild_if_bound(), hint)


## Bind a float `static var` (band edge / y) to a single `detail.<prop>` slug.
func _dt_scalar(prop: String, hint: Dictionary = _DT_EDGE) -> void:
	TunePort.bind_update(self, "detail." + prop.to_lower(), float(get(prop)),
		func(v: float) -> void:
			set(prop, v); _rebuild_if_bound(), hint)


## Rebuild the settled lower panel after a knob scrub — but ONLY once the boot bind sweep
## is done (each bind's apply fires during registration; the single first build follows) and
## only when the panel is actually built + resting (not mid box-open / slide transition).
##
## DEFERRED on purpose. A tunable scrub arrives INSIDE the F3 SpinBox's value_changed → C++
## SpinBox::gui_input. Rebuilding synchronously there frees _open_root (window frames, the
## fold-carrier column bands, their materials, Tune subscribers) while gui_input is still on the
## stack and about to touch its own range_click_timer — which SIGSEGVs the 4.8 fork with wandering
## heap corruption (Timer::set_wait_time / the accessibility HashSet). Freeing a node from within
## the input/signal callstack is the hazard, NOT the fold enrollment per se (the compositor keeps no
## persistent per-member list, and EngineFoldCompositor frees enrolled carriers every frame from
## _process without issue). So we hand the rebuild to the next idle frame via call_deferred — the
## same safe point EngineFold frees at, never nested in input dispatch — and coalesce a whole frame's
## worth of knob scrubs into ONE rebuild. This generalizes the per-knob vitals-band in-place fix
## (782ca3444) to every frame/rect knob. Gated identically to before.
func _rebuild_if_bound() -> void:
	if _detail_tunables_bound and _tphase == _TPhase.NONE \
			and _open_root != null and is_instance_valid(_open_root):
		if not _rebuild_pending:
			_rebuild_pending = true
			_flush_pending_rebuild.call_deferred()


## Deferred flush for _rebuild_if_bound: runs the settled-panel rebuild at idle, out of the scrub's
## input/signal callstack. Re-checks the guards — the scene may have started a transition or torn the
## panel down between the scrub and this flush.
func _flush_pending_rebuild() -> void:
	if not _rebuild_pending:
		return
	_rebuild_pending = false
	if _tphase == _TPhase.NONE and _open_root != null and is_instance_valid(_open_root):
		_rebuild_lower_settled()


## (Re)build the stats-band text under `_stats_text_root` from `_stats_view`. Three
## blocks of FONT.BIN dark text (see the STAT_*/WP_*/AT_* layout constants). No-op-safe
## before the root exists; frees the previous glyph tree so it can rerun per selection.
func _build_stats_text() -> void:
	if _stats_text_root == null or not is_instance_valid(_stats_text_root):
		return
	# Free the prior glyphs IMMEDIATELY, not via queue_free: this rebuild is synchronous and its tail
	# (_rebuild_stats_delta → _stats_text_root.duplicate()) runs in THIS call. A deferred free would leave
	# the old glyphs still parented, so the delta panel's duplicate() would clone them alongside the fresh
	# ones (≈2× glyphs, "garbage/kanji" '-' until a full rebuild) — §15.26 DEFECT #8. free() mirrors the
	# _rebuild_lower_settled `_open_root.free()` idiom (menu-callback rebuild, no self-signal).
	for c in _stats_text_root.get_children():
		_stats_text_root.remove_child(c)
		c.free()
	_stats_text_mats.clear()   # these glyph mats are rebuilt below; drop the freed ones' clip refs
	if _stats_view.is_empty():
		return
	var v := _stats_view
	_stats_delta_preview_strings = {}   # repopulated below on a preview build (guard readback)

	# Text mechanism (§15.18, static-rooted): LABELS are baked RANGETILE cells (CLUT
	# 0x7C3C) via `_label`; NUMBERS ('/' and '%' included) are FFT's small number font
	# (NumberFont, `_num`/`_run`) — '%' is that font's dots+slash glyph, NOT FONT.BIN.
	# Move/Jump/Speed and R/L rows get a fixed 3-dot "…" leader (`_ellipsis`).

	# --- Block 1: Move/Jump/Speed — baked label · "…" · number value -----------
	_label("Move", LBL_MOVE)
	_label("Jump", LBL_JUMP)
	_label("Speed", LBL_SPEED)
	for i in 3:
		var y := VAL_ROW_Y[i]
		var key: String = ["move", "jump", "speed"][i]
		_ellipsis(MJS_VALUE_X, y)
		# §15.26 preview: full band coverage — the equip picker shows this field's SIGNED delta
		# (blue +N / red -N / tan dash when unchanged), not a flat "-". Plain dash preview (empty delta)
		# still dashes every field. Settled (non-preview) shows the live value.
		if _stats_preview:
			_paint_delta_value(key, MJS_VALUE_X, y)
		else:
			_num(str(int(v.get(key, 0))), MJS_VALUE_X, y)

	# --- Block 2: Weap.Power (baked header) + R/L rows ("NNN / NN%") -----------
	_label("Weap.Power", LBL_WEAP)
	var wp_rows: Array = [
		["R", LBL_R, int(v.get("r_power", 0)), int(v.get("r_wev", 0))],
		["L", LBL_L, int(v.get("l_power", 0)), int(v.get("l_wev", 0))],
	]
	var wp_val_y: Array[float] = [VAL_ROW_Y[1], VAL_ROW_Y[2]]
	for ri in wp_rows.size():
		var row: Array = wp_rows[ri]
		var y: float = wp_val_y[ri]
		_label(row[0], row[1])
		_ellipsis(WP_VALUE_X, y)
		if _stats_preview:
			# §15.26 preview. With a numeric delta for THIS hand's slot (ri 0=R.Hand, 1=L.Hand),
			# fill the two Weap.Power numbers with the SIGNED wp/wev delta (blue +N / red -N / tan
			# dash); otherwise (no delta, or the delta is for the other hand) show the "- / -" dashes.
			if not _stats_delta_values.is_empty() and _stats_delta_slot == ri:
				_run_delta([_delta_token(int(_stats_delta_values.get("wp", 0)), TOKEN_GAP),
					_delta_dash("/", TOKEN_GAP),
					_delta_token(int(_stats_delta_values.get("wev", 0)))], WP_VALUE_X, y)
			else:
				# "R 004 / 05%" → "R - / -" (oracle sstate4).
				_run([_n("-", TOKEN_GAP), _n("/", TOKEN_GAP), _n("-")], WP_VALUE_X, y)
		else:
			# "004 / 05%": zero-padded power, '/', 2-digit evade, '%' — ALL number-font.
			_run([_n(_pad3(int(row[2])), TOKEN_GAP), _n("/", TOKEN_GAP),
				_n(str(int(row[3])).pad_zeros(2)), _n("%")], WP_VALUE_X, y)

	# --- Block 3: AT C-EV S-EV A-EV (baked headers) + R/L value rows ----------
	# "C-EV" == baked cell "C-" (dash inside) then shared cell "EV"; same for S-/A-.
	_label("AT", LBL_AT)
	_label("C-", LBL_CDASH); _label("EV", Vector2(AT_EV_X[0], STAT_ROW_Y[0]))
	_label("S-", LBL_SDASH); _label("EV", Vector2(AT_EV_X[1], STAT_ROW_Y[0]))
	_label("A-", LBL_ADASH); _label("EV", Vector2(AT_EV_X[2], STAT_ROW_Y[0]))
	# Value rows = a fixed table "AT / CC% / SS% / AA%" (R = main hand + evade trio; L = off
	# hand, zeros). Fixed columns (not a flow) so the EV values stay under their headers.
	if _stats_preview:
		# §15.26 preview: full band coverage — AT shows the PA delta, S-EV/A-EV the shield/accessory
		# evade deltas (R row); C-EV always dashes (job-only). Plain dash preview (empty delta)
		# collapses every column to "-", matching the old oracle-sstate4 behaviour.
		_at_value_row_delta(true, VAL_ROW_Y[1])
		_at_value_row_delta(false, VAL_ROW_Y[2])
	else:
		_at_value_row(int(v.get("r_at", 0)), int(v.get("c_ev", 0)),
			int(v.get("s_ev", 0)), int(v.get("a_ev", 0)), VAL_ROW_Y[1])
		_at_value_row(int(v.get("l_at", 0)), 0, 0, 0, VAL_ROW_Y[2])

	# A rebuild can happen mid-open (set_stats_view on a selection change) — the clip engine's
	# node_added coverage would land the current aperture next frame; re-push through the
	# element NOW so the fresh glyphs are clipped synchronously, like the old hand re-apply.
	if _stats_origin != null and is_instance_valid(_stats_origin):
		_stats_origin._set_aperture(_stats_clip)

	# §15.21: arm each glyph's BACKGROUND palette + preserve the current backgrounded state on
	# EVERY (re)build. The number-value glyphs come from UIMenuText.mount_number (which doesn't
	# thread a bg palette), so without this a per-selection rebuild leaves palette_bg_tex UNSET —
	# and `formation_text_opaque` then samples the default (white) texture when backgrounded, so
	# the digits render pure white. All stats-band text uses _label_pal (0x7C3C) → _label_pal_bg
	# (0x7D3C). Harmless on the "…" dot-leader mats (formation_font_opaque ignores both params).
	var _bgv := 1.0 if _backgrounded else 0.0
	for m in _stats_text_mats:
		m.set_shader_parameter("palette_bg_tex", _label_pal_bg)
		m.set_shader_parameter("backgrounded", _bgv)

	# §15.26 DEFECT #8: keep the second (delta) stats panel in sync with every base rebuild. No-op
	# unless we're in the picker's stats-preview state (the compare band only exists then).
	_rebuild_stats_delta()


## §15.26 DEFECT #8 — (re)build the offset delta/compare stats panel. It exists ONLY in the picker's
## stats-preview state; there it MIRRORS the just-built base panel (same dash content, same frame) 2px
## UP-LEFT, so the "slightly-offset second panel" edge shows exactly as on the oracle. The base panel's
## normal-Status path is untouched — the delta is a separate offset group, torn down when preview ends.
##
## The panel is a REGISTERED ELEMENT (ADR-0088 amendment §5): BOX_OPEN + OWN_APERTURE, its rect DERIVED
## from the stats-frame drivers (mints no slug). It boots SETTLED-open (self-play demoted to standalone
## preview); the PICKER ORCHESTRATION (FormationDetailTransition) invokes open()/close() and tears down
## on `closed`. Oracle honesty (2026-08-11 static+dyn): the ROM does NOT box-open this panel — the
## compare builder `0x80111EC4` never calls either §15.17 curve walker (its chrome is the gradient-line
## frame `0x800E3358`, not a 9-slice window). Pre-picker (formation_equip_dest_live RAM read) only slot
## 0xc is installed; picker open freshly installs slot 0xb (`0x8011AF4C` → `FUN_801156b4`) as a POP —
## and the ROM's ADDED panel is the (2,2) down-right one, the port adds its delta up-left of the
## standing base. The animated reveal here is a deliberate port-side product decision (the ADR's §5).
func _rebuild_stats_delta() -> void:
	if not _stats_preview or _open_root == null or not is_instance_valid(_open_root) \
			or _stats_origin == null or not is_instance_valid(_stats_origin):
		if _stats_delta_root != null and is_instance_valid(_stats_delta_root):
			_stats_delta_root.free()   # synchronous: the registry must not see two compare elements
		_stats_delta_root = null
		_stats_delta_mats.clear()
		return
	# Cursor-move UPDATE (EQUIP_STAT_PREVIEW.md live delta): if the compare ELEMENT already exists,
	# KEEP it — freeing/recreating it each cursor move would invalidate the picker's live open()/close()
	# reference and re-register a fresh element mid-animation. Only refresh the cloned payload (the
	# StatsText + weapon-legend duplicates) with the just-rebuilt base numbers.
	if _stats_delta_root != null and is_instance_valid(_stats_delta_root):
		_populate_stats_delta_payload()
		return
	# The delta/compare band is its OWN movable frame group — a SIBLING of the base stats group under
	# _open_root, NOT grafted onto _stats_origin. Its origin sits at the base origin + the 2px slot-0xc
	# offset, both RE-DERIVED from the live STATS_FRAME on every rebuild — so the delta rides a
	# frame-position scrub (which rebuilds via _rebuild_lower_settled) exactly as the base does. The old
	# code placed this frame-INDEPENDENTLY (nudges only, no frame term) then reparent(keep-global) pinned
	# that world pos, so a rebuild snapped it back and it lagged the base (user-reported "second band
	# doesn't move"); it was even mis-offset at boot whenever STATS_FRAME ≠ STATS_FRAME0 (a dialed override).
	_stats_delta_root = UI3Element.new({
		"id": "detail.compare",
		# DERIVED (bare-Callable form): the TRUE panel box = the live STATS_FRAME + the 2px
		# delta nudge — placement AND settled-aperture base, per standard element semantics.
		# Drivers (detail.stats_frame_* + the compare offset detail.stats_delta_nudge_*) already
		# rebuild this whole panel on scrub via _rebuild_lower_settled — DECLARING them (Amendment
		# 4 §2, was a bare Callable dead-end) surfaces them inline on the UI3 page. Same eval; mints
		# no slug (derived elements render read-only through their drivers).
		"rect": UI3Element.derived(["detail.stats_frame_x", "detail.stats_frame_y",
			"detail.stats_frame_w", "detail.stats_frame_h",
			"detail.stats_delta_nudge_x", "detail.stats_delta_nudge_y"], _compare_panel_rect),
		"transition": UI3Element.Transition.BOX_OPEN,
		# ADR-0097 §2: the §15.17 sweep opens on the normal curve and closes on the fast
		# one — the house rule, named rather than assumed.
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.NONE,   # chrome is legacy _add_frame payload (DetailScene not yet migrated)
		"clip": UI3Element.Clip.OWN_APERTURE,
	})
	_stats_delta_root.name = "StatsDeltaPanel"
	# The R44 panel-nudge reveal = aperture_pad (ADR-0088 amendment §4): the nudged chrome must
	# ride the box the beat opens over, without leaking into the rect. Written POST-construction
	# (spec()[...], like the picker's fast override) because the pad is COMPUTED from the
	# live STATS_PANEL_NUDGE: a dict literal would mint a bind whose first-registered default
	# outlives nudge scrubs (Tune on_update captures it) — the stale-clip class this avoids.
	# The panel rebuilds on every nudge scrub, so the pad is always fresh.
	var n := STATS_PANEL_NUDGE
	_stats_delta_root.spec()["aperture_pad"] = Vector4(
		maxf(0.0, -n.x), maxf(0.0, -n.y), maxf(0.0, n.x), maxf(0.0, n.y))
	_stats_delta_root._set_aperture(_stats_delta_root.padded_rect())   # re-derive the settled box with the pad
	_open_root.add_child(_stats_delta_root)
	# The element PLACES ITSELF (_place_self on tree entry: _open_root is screen-at-origin, so
	# its rect corner lands at the exact old hand-anchored position). Only the fold DEPTH lift
	# stays hand-applied, pending a real depth criterion (§15.26): on the fold the WHOLE group
	# lifts to the RP_COMPARE_BASE bucket — the ROM's compare panel is fully opaque, so its
	# chrome must occlude the base band's legend (rungs 5/6) while the duplicated payload keeps
	# its relative rungs — plus a hair toward the camera (z+0.01) against coplanar z-fighting.
	# (Nothing re-places the element after this: bare-Callable rect, no drivers.)
	_stats_delta_root.position.z += 0.01 + (DepthMode.rung_z(RP_COMPARE_BASE) if Fold.owns() else 0.0)
	# The delta frame chrome — its own UIFrame (same rect/CLUTs as the base), mounted RELATIVE to this
	# origin (local 0 + the R44 panel nudge), mirroring the base `_stats_frame_node` exactly. The
	# element's clip engine discovers + apertures it (no hand _apply_clip).
	var delta_frame := _background_frame(_add_frame(_stats_delta_root, Rect2(Vector2.ZERO, STATS_FRAME.size), RP_WINDOW_FRAME, RP_WINDOW_FRAME, false, _stats_delta_mats))
	delta_frame.position += _stats_panel_nudge_world()   # §15.26 R44: same whole-panel align as the base chrome
	_populate_stats_delta_payload()


## Clone the base stats text + weapon legend into the compare element (its visible payload). Split out
## of _rebuild_stats_delta so a cursor-move UPDATE can REFRESH the numbers without recreating the
## element: it drops the previous clones (keeping the frame chrome) and re-clones the just-built base.
func _populate_stats_delta_payload() -> void:
	if _stats_delta_root == null or not is_instance_valid(_stats_delta_root):
		return
	# Drop the previous cloned text/legend (a synchronous free, like _build_stats_text — a deferred
	# queue_free would let the next duplicate() capture stale glyphs, §15.26 DEFECT #8). The frame
	# chrome (a UIFrame child) stays; only the two named payload clones are replaced.
	for nm in ["StatsText", "StatsWeaponLegend"]:
		var old := _stats_delta_root.find_child(nm, true, false)
		if old != null and is_instance_valid(old):
			old.get_parent().remove_child(old)
			old.free()
	# The delta text/legend = clones of the just-built base, with their materials made UNIQUE: the
	# compare element's own aperture cannot be expressed on materials shared with the base panel (a
	# shared clip_world would scissor both). The clip engine covers the fresh clones (node_added).
	if _stats_text_root != null and is_instance_valid(_stats_text_root):
		var dup := _stats_text_root.duplicate()
		dup.position = _stats_text_root.position
		_make_materials_unique(dup)
		_stats_delta_root.add_child(dup)
	# The sword/rod weapon legend rides the delta too (#6 — user: "the sword/rod doesn't move with
	# the text"): the ROM's compare panel is a full second stats-band draw, legend included.
	if _stats_legend_root != null and is_instance_valid(_stats_legend_root):
		var legend_dup := _stats_legend_root.duplicate()
		legend_dup.position = _stats_legend_root.position
		_make_materials_unique(legend_dup)
		_stats_delta_root.add_child(legend_dup)


## The compare element's derived box (display px): the TRUE panel box — live STATS_FRAME + the
## 2px delta nudge. The R44 whole-panel nudge does NOT widen this rect; the nudged chrome rides
## the reveal via the element's `aperture_pad` instead (see _rebuild_stats_delta).
func _compare_panel_rect() -> Rect2:
	return Rect2(STATS_FRAME.position + STATS_DELTA_NUDGE, STATS_FRAME.size)


## Deep-copy every ShaderMaterial override in `root`'s subtree (a duplicate() clone shares them with
## the original — see _rebuild_stats_delta). Copies keep all current uniform values.
func _make_materials_unique(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.material_override is ShaderMaterial:
			mi.material_override = mi.material_override.duplicate()
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i)
			if m is ShaderMaterial:
				mi.set_surface_override_material(i, m.duplicate())
	for c in root.get_children():
		_make_materials_unique(c)


## The registered stats-band element `detail.stats` (ADR-0088) — the movable origin whose
## subtree (chrome + weapon legend + stats text) the clip engine apertures. Null before the
## lower panel builds.
func stats_element() -> UI3Element:
	return _stats_origin if _stats_origin != null and is_instance_valid(_stats_origin) else null


## The registered Eqp/Ability panel element `detail.lower` (ADR-0088) — the movable origin
## whose subtree (chrome + bands + tabs + icons + equip items) the clip engine apertures.
func lower_element() -> UI3Element:
	return _lower_origin if _lower_origin != null and is_instance_valid(_lower_origin) else null


## The registered compare-panel element (ADR-0088 amendment §5) — null unless the picker's
## stats-preview built it. The ORCHESTRATOR invokes its open()/close() verbs; standalone
## preview leaves it settled-open.
func stats_compare_element() -> UI3Element:
	return _stats_delta_root if _stats_delta_root != null and is_instance_valid(_stats_delta_root) else null


## §15.13 / worklist #4 — (re)build the per-slot EQUIPPED-item column: for each equipped slot, the
## ITEM.BIN icon (the SAME extracted sheet + per-type CLUT mechanism as the equip picker) at
## (ITEM_COL_X, row−ICON_DY) and the item NAME (dark-ink FONT) at (EQUIP_NAME_X, row). Empty slots are
## skipped. Rebuilds on every set_stats_view; its mats carry the lower aperture so the box-open reveals
## them center-out with the panel. The name overflow runs UNDER the equip-picker window (occluded), so
## we render the full string — the oracle's "Broad"/"Leathe"/"Clothes"/"Battle" are clips, not truncation.
func _build_equip_items() -> void:
	if _equip_items_root == null or not is_instance_valid(_equip_items_root):
		return
	for c in _equip_items_root.get_children():
		c.queue_free()
	_equip_item_mats.clear()
	_equip_icon_count = 0
	_equip_name_count = 0
	var equip: Array = _stats_view.get("equipment", [])
	for slot in mini(equip.size(), SLOT_ROWS.size()):
		var e = equip[slot]
		if typeof(e) != TYPE_DICTIONARY or e.is_empty():
			continue
		var anchor := SLOT_ROWS[slot]
		# Mount only a VALID ITEM.BIN icon cell (icon_graphic >= 0). Production entries carry the real
		# items.json `graphic` cell (RE round 49 — see _equipment_view); -1 means "no cell", icon skipped.
		var icon_g := int(e.get("icon_graphic", -1))
		if _item_icon_tex != null and icon_g >= 0:
			_mount_equip_item_icon(icon_g, int(e.get("palette", 0)),
				ITEM_COL_X, anchor.y + EQUIP_ITEM_ICON_DY)
			_equip_icon_count += 1
		var nm := String(e.get("name", ""))
		if nm != "":
			# Lift the name onto the RP_ITEM_ICON fold rung (like the icon) so the engine-fold Pass-B
			# depth test draws it OVER the subtractive Eqp band (rung RP_BAND), matching the slot icons.
			var name_base := _local_under_container(EQUIP_NAME_X, anchor.y)
			if Fold.owns():
				name_base += Vector3(0.0, 0.0, DepthMode.rung_z(RP_ITEM_ICON))
			_menu_text.mount(_equip_items_root, nm,
				name_base, RP_ITEM_ICON, PIXELS_PER_UNIT, _equip_item_mats, null, RP_ITEM_ICON)
			_equip_name_count += 1
	# Reveal exactly like the rest of the lower panel — re-push the current aperture through the
	# ELEMENT so the fresh icon/name mats are clipped synchronously (the clip engine's node_added
	# coverage would land it next frame anyway; ADR-0088).
	if _lower_origin != null and is_instance_valid(_lower_origin):
		_lower_origin._set_aperture(_lower_clip)
	# §15.21: a repaint (selection/commit) mounts fresh FG glyphs — re-apply the panel's current bg
	# state so a rebuild while the panel is blue keeps the names blue (mirror StartActionMenu rows).
	_apply_item_name_bg(_equip_item_mats, lower_panel_backgrounded())


## The per-slot ability NAME column (Task 1) — the mirror of _build_equip_items for the Ability panel.
## Draws the current name right of each category icon (primary skillset, secondary sub-job skillset,
## R/S/M ability names), reading the resolved `ability_slots` view. Rebuilt from the fresh stats view
## on every selection/commit (set_stats_view), so a committed pick repaints the slot immediately.
func _build_ability_items() -> void:
	if _ability_items_root == null or not is_instance_valid(_ability_items_root):
		return
	for c in _ability_items_root.get_children():
		c.queue_free()
	_ability_item_mats.clear()
	_ability_name_count = 0
	var slots: Array = _stats_view.get("ability_slots", [])
	# Same left/right column switch the ability ICONS use — names ride the surviving column.
	var abl_rows: Array = ABILITY_ROWS_LEFT if ability_only else ABILITY_ROWS
	var name_x := ABILITY_NAME_LEFT_X if ability_only else ABILITY_NAME_X
	for row in mini(slots.size(), abl_rows.size()):
		var e = slots[row]
		var nm := String(e.get("name", "")) if typeof(e) == TYPE_DICTIONARY else ""
		if nm == "":
			continue
		var anchor: Vector2 = abl_rows[row]
		# Lift the name onto the RP_ITEM_ICON fold rung (like the Eqp names) so the engine-fold Pass-B
		# depth test draws it OVER the subtractive Ability band (rung RP_BAND), matching the row icons.
		var name_base := _local_under_container(name_x, anchor.y)
		if Fold.owns():
			name_base += Vector3(0.0, 0.0, DepthMode.rung_z(RP_ITEM_ICON))
		_menu_text.mount(_ability_items_root, nm, name_base, RP_ITEM_ICON, PIXELS_PER_UNIT, _ability_item_mats, null, RP_ITEM_ICON)
		_ability_name_count += 1
	# Reveal exactly like the Eqp names — re-push the current aperture so the fresh name mats clip now.
	if _lower_origin != null and is_instance_valid(_lower_origin):
		_lower_origin._set_aperture(_lower_clip)
	# §15.21: re-apply the panel's current bg state to the freshly-mounted names (see _build_equip_items).
	_apply_item_name_bg(_ability_item_mats, lower_panel_backgrounded())


## Mount one 16×16 equipped ITEM.BIN icon (top-left at display x,y) via the index→CLUT sprite shader —
## the SAME path as EquipPickerMenu._mount_item_icon, but in the detail's container space + own clip list.
func _mount_equip_item_icon(graphic: int, palette: int, x: float, y: float) -> void:
	var cell: Rect2 = EquipPickerMenu.icon_uv_for(graphic)
	var mat := ShaderMaterial.new()
	mat.shader = load(_EQUIP_ICON_SHADER)
	mat.set_shader_parameter("mode", 0)
	mat.set_shader_parameter("index_atlas", _item_icon_tex)
	mat.set_shader_parameter("atlas_size", Vector2(_item_icon_tex.get_width(), _item_icon_tex.get_height()))
	mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y))
	mat.set_shader_parameter("palette_tex", _equip_type_palette(palette))
	mat.set_shader_parameter("brightness", 1.0)
	mat.render_priority = RP_ITEM_ICON
	_equip_item_mats.append(mat)
	var holder := Node3D.new()
	_equip_items_root.add_child(holder)
	holder.position = _local_under_container(x, y)
	# Lift onto the RP_ITEM_ICON fold rung so the engine-fold depth test draws the icon OVER the
	# subtractive Eqp band (rung RP_BAND) — the same real-Z lift the slot icons get via _mount_icon.
	if Fold.owns():
		holder.position += Vector3(0.0, 0.0, DepthMode.rung_z(RP_ITEM_ICON))
	var mi := _quad(cell.size)
	mi.material_override = mat
	mi.set_meta("z_rung", RP_ITEM_ICON)   # authored rung (ADR-0077 dec. 7) — mirrors _mount_icon
	holder.add_child(mi)


## Load the extracted ITEM.BIN icon sheet + its per-type CLUTs (§15.26 b). No-op (icons skipped) if
## the sheet is absent — the names still render, matching the "content behind the mechanism" rule.
func _load_item_icons() -> void:
	if not ResourceLoader.exists(_EQUIP_ICON_INDEX_TEX) or not FileAccess.file_exists(_EQUIP_ICON_JSON):
		return
	_item_icon_tex = load(_EQUIP_ICON_INDEX_TEX)
	var data = JSON.parse_string(FileAccess.open(_EQUIP_ICON_JSON, FileAccess.READ).get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		_item_palettes = data.get("palettes", [])


## The 16×1 ITEM.BIN CLUT texture for an item's `palette` byte (rec[0], 0..15 — ITEM_EQUIPMENT_DATA.md
## §5; NOT the class byte), built once + cached.
func _equip_type_palette(palette: int) -> ImageTexture:
	var t := clampi(palette, 0, 15)
	if not _type_pal_cache.has(t):
		var pal: Array = _item_palettes[t] if t < _item_palettes.size() else []
		var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
		for i in 16:
			if i < pal.size():
				var c = pal[i]
				img.set_pixel(i, 0, Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
		_type_pal_cache[t] = ImageTexture.create_from_image(img)
	return _type_pal_cache[t]


## Guard accessors (worklist #4): how many equipped-item icons / names the last build mounted.
func equip_item_icon_count() -> int:
	return _equip_icon_count


func equip_item_name_count() -> int:
	return _equip_name_count


## How many ability-slot NAMES the last _build_ability_items mounted (Task 1 display guard).
func ability_item_name_count() -> int:
	return _ability_name_count


## The resolved ability-slot names the name column last built from, in AbilityLoadout.Slot order
## (Task 1 display guard). Reads the live stats view — pair with ability_item_name_count() to prove
## a committed pick both resolved AND mounted.
func ability_slot_names() -> Array:
	var out: Array = []
	for e in _stats_view.get("ability_slots", []):
		out.append(String(e.get("name", "")) if typeof(e) == TYPE_DICTIONARY else "")
	return out


## One AT/C-EV/S-EV/A-EV value row as a FIXED 4-column table (§15.18): the AT value
## right-aligned before the first '/', then each evade "NN%" left-aligned in its own
## oracle-measured column with a light '/' between. Every value sits under its header.
func _at_value_row(at: int, c_ev: int, s_ev: int, a_ev: int, y: float) -> void:
	# §15.29: AT is a FIXED 2-digit zero-padded field (ROM fmt 0x0002 draws count digits
	# including leading zeros — "05", never "5"), left edge at AT_VAL_X. No right-align.
	_num(str(at).pad_zeros(2), AT_VAL_X, y)
	var evs := [c_ev, s_ev, a_ev]
	for i in evs.size():
		_num("/", AT_SLASH_X[i], y)
		_num(str(int(evs[i])).pad_zeros(2) + "%", AT_EV_COL_X[i], y)


## §15.26 preview variant of _at_value_row: "- / - / - / -" — every value a lone "-", the "/"
## separators kept, no "%" (oracle sstate4 equip-picker preview).
func _at_value_row_preview(y: float) -> void:
	_num_right("-", AT_VAL_X + 10.0, y)   # right edge of the fixed 2-digit AT field
	for i in 3:
		_num("/", AT_SLASH_X[i], y)
		_num("-", AT_EV_COL_X[i], y)


## Full-coverage preview: one band VALUE column painted as its signed delta (blue +N / red -N / tan
## dash for 0-or-N/A), reading _stats_delta_values[field]. Records the string for the guard readback.
## When _stats_delta_values is empty (plain dash preview) every field is 0 → a dash, matching the old
## _at_value_row_preview / _num("-") behaviour.
func _paint_delta_value(field: String, x: float, y: float) -> void:
	var tok := _delta_token(int(_stats_delta_values.get(field, 0)))
	_run_delta([tok], x, y)
	_stats_delta_preview_strings[field] = tok["s"]


## Full-coverage preview of the AT row ("AT / C-EV / S-EV / A-EV"). AT delta = the item's PA
## contribution ONLY — a weapon swap leaves AT dashed (the Weap.Power row already shows its +N, and the
## ROM dashes AT here too — doc §6), so PA-boosting gear is what moves this column. C-EV is job-only →
## always a dash. The evade pair (S-EV/A-EV) shows on the R "main hand" row only; the L row dashes them
## (mirrors the settled _at_value_row(l_at, 0, 0, 0)).
func _at_value_row_delta(is_r_row: bool, y: float) -> void:
	var at_tok := _delta_token(int(_stats_delta_values.get("pa", 0)))
	_run_delta([at_tok], AT_VAL_X, y)
	# C-EV always dashes; S-EV/A-EV are the shield/accessory evade deltas on the R row, dashes on L.
	var col_toks := [
		_delta_dash("-"),
		_delta_token(int(_stats_delta_values.get("s_ev", 0))) if is_r_row else _delta_dash("-"),
		_delta_token(int(_stats_delta_values.get("a_ev", 0))) if is_r_row else _delta_dash("-"),
	]
	for i in 3:
		_num("/", AT_SLASH_X[i], y)
		_run_delta([col_toks[i]], AT_EV_COL_X[i], y)
	if is_r_row:
		_stats_delta_preview_strings["r_at"] = at_tok["s"]
		_stats_delta_preview_strings["c_ev"] = col_toks[0]["s"]
		_stats_delta_preview_strings["s_ev"] = col_toks[1]["s"]
		_stats_delta_preview_strings["a_ev"] = col_toks[2]["s"]
	else:
		_stats_delta_preview_strings["l_at"] = at_tok["s"]


# --- token composer ----------------------------------------------------------
# A row is a list of {s, gap} number-font tokens (digits/'/'/'%'); `gap` px is added
# AFTER the token's own advance. (Labels are baked cells via `_label`, not tokens.)
func _n(s: String, gap: float = 0.0) -> Dictionary: return {"s": s, "gap": gap}


# --- delta token composer (§15.26 numeric preview) ---------------------------
# A delta token adds a per-token `pal` (the blue/red/tan number CLUT) to the {s, gap} shape —
# the SIGN chooses the palette, mirroring the ROM's sign→sub-ramp classifier (doc §5).
func _delta_token(v: int, gap: float = 0.0) -> Dictionary:
	# positive → "+N" blue; negative → "-N" red (str() already carries the '-'); zero → a tan dash.
	if v > 0:
		return {"s": "+" + str(v), "pal": _delta_pal_pos, "gap": gap}
	elif v < 0:
		return {"s": str(v), "pal": _delta_pal_neg, "gap": gap}
	return {"s": "-", "pal": _label_pal, "gap": gap}


## A non-signed separator/token in the delta run (the '/' between WP and W-EV) — drawn in the
## plain tan CLUT, never coloured (the ROM strips the colour bias around the slash, doc §5).
func _delta_dash(s: String, gap: float = 0.0) -> Dictionary:
	return {"s": s, "pal": _label_pal, "gap": gap}


## Mount a delta token run at display (x0,py): each token draws through ITS OWN number CLUT
## (blue/red for a signed value, tan for the separator/dash). Same layout as [method _run].
func _run_delta(tokens: Array, x0: float, py: float) -> void:
	var x := x0
	for t in tokens:
		var w := _menu_text.mount_number(_stats_text_root, t["s"], _stats_text_base(x, py),
			RP_TEXT, PIXELS_PER_UNIT, t["pal"], _stats_text_mats, NumberFont.SMALL, RP_TEXT)
		x += w + t.get("gap", 0.0)


## Mount a number-font token run starting at display (x0,py); returns the end x (px).
func _run(tokens: Array, x0: float, py: float) -> float:
	var x := x0
	for t in tokens:
		var w := _menu_text.mount_number(_stats_text_root, t["s"], _stats_text_base(x, py), RP_TEXT, PIXELS_PER_UNIT, _label_pal, _stats_text_mats, NumberFont.SMALL, RP_TEXT)
		x += w + t.get("gap", 0.0)
	return x


## One baked stats-band LABEL cell (RANGETILE sprite through CLUT 0x7C3C) at display
## top-left `disp` — the faithful source (§15.18), rendered exactly like the ability/
## slot icons (one index→CLUT sprite). Unknown names are skipped (no-op-safe).
func _label(name: String, disp: Vector2) -> void:
	if _atlas == null or not _atlas.has_stat_label(name):
		return
	# RP_TEXT fold rung (ADR-0077 dec. 7: no unauthored depth) — strictly NEARER than the stats
	# frame (RP_WINDOW_FRAME), so the opaque frame's tan center never occludes the label glyphs, and
	# NEARER than the draggable vitals band. Matches the number glyphs' rung (see _run/_num/_ellipsis).
	_mount_icon(_stats_text_root, _atlas.stat_label_rect(name), disp, _label_pal, RP_TEXT, _label_pal_bg, RP_TEXT, true, _stats_text_mats)


## One small-number-font value at display (px,py) (digits / '/' / '%', dark-on-tan).
func _num(s: String, px: float, py: float) -> void:
	_menu_text.mount_number(_stats_text_root, s, _stats_text_base(px, py), RP_TEXT, PIXELS_PER_UNIT, _label_pal, _stats_text_mats, NumberFont.SMALL, RP_TEXT)


## A number RIGHT-aligned so its field ends at display `right_x` (for a numeric column).
func _num_right(s: String, right_x: float, py: float) -> void:
	_num(s, right_x - _menu_text.number_width(s), py)


## The "…" leader before a value on row `py` — §15.29 round 48 ROM-exact: ONE
## number-font cell (FRAMEFONT "…", the 6×4 three-dot cell at FRAME.BIN (120,26)),
## drawn `ELLIPSIS_DROP` below the value row and `ELLIPSIS_ADVANCE` left of the value
## (world_render_number_small fmt flag 0x100: leader at dst, first digit at dst+7).
func _ellipsis(value_x: float, py: float) -> void:
	_menu_text.mount_number(_stats_text_root, "…",
		_stats_text_base(value_x - ELLIPSIS_ADVANCE, py + ELLIPSIS_DROP),
		RP_TEXT, PIXELS_PER_UNIT, _label_pal, _stats_text_mats, NumberFont.SMALL, RP_TEXT)


static func _pad3(n: int) -> String:
	return str(n).pad_zeros(3)


# -----------------------------------------------------------------------------
# The ○-press transition (§15.5) — the whole arc, on this ONE screen: the shared
# vitals+nameplate cluster slides bottom→top (phase 1) with the lower Eqp/Ability
# panel held CLOSED, a short dead gap (phase 2/gap), then the box-open unfurls the
# lower panel (phase 3). Runs OVER the (kept) formation screen: the cluster starts
# exactly where the formation's docked pair sat, so the hand-off is seamless and the
# band "cut" is the formation band staying behind while this screen's vitals stripe
# takes over (§15.6). Drive it from a host after binding the unit's views.
# -----------------------------------------------------------------------------
func play_transition() -> void:
	if _cluster == null or not is_instance_valid(_cluster):
		play_open()   # no cluster (shouldn't happen) — fall back to the box-open alone
		return
	_begin_chrome_slide()
	_tphase = _TPhase.SLIDE   # …→ GAP → box-open (the full ○-press Status arc)


## Play ONLY the chrome entry slide (§15.1 pair DOCKED→TOP + §15.6 band cross-fade), WITHOUT the
## dead-gap / box-open — the FIRST-CLASS motion every roster→top-chrome entry shares. The ○-press
## Status transition (play_transition) is this slide THEN the box-open; the main-menu sub-screens
## (Change-Job / Equip / Ability) want the slide but open their OWN lower panel afterward, so they
## play this and run their begin_*_transition on `entry_slide_done`. Emits `entry_slide_done` when
## the pair settles at LAYOUT_TOP. With no cluster it settles instantly and still fires the signal,
## so the host's followup always runs.
func play_entry_slide() -> void:
	if _cluster == null or not is_instance_valid(_cluster):
		settle_open()             # nothing to slide — put the screen in its settled state…
		entry_slide_done.emit()   # …and fire so the host's sub-transition still runs
		return
	_begin_chrome_slide()
	_tphase = _TPhase.ENTRY_SLIDE   # …→ done (no box-open — the sub-screen opens its own panel)


## Shared setup for both top-chrome-raising motions (play_transition, play_entry_slide): park the
## lower panel CLOSED, reset the band cross-fade to its docked start (roster band full / detail
## stripe hidden), and arm the §15.1 DOCKED→TOP slide at frame 0. The caller sets `_tphase` to pick
## what follows the slide.
func _begin_chrome_slide() -> void:
	_open_playing = false
	_close_lower_panel()                    # windows stay shut through the slide
	# Cross-fade start (§15.6): the roster's bottom band is full, this screen's top stripe hidden;
	# both ramp as the slide progresses (the bottom fades out, the top fades in).
	_formation_band_factor = 1.0
	_set_detail_band_factor(0.0)
	_cluster.begin_slide(UnitInfoCluster.LAYOUT_DOCKED, UnitInfoCluster.LAYOUT_TOP)
	_tframe = 0
	_taccum = 0.0


## Play the transition in REVERSE (Esc): fold the lower panel shut, dead gap, then slide the
## vitals+nameplate pair back DOWN to the docked layout with the band cross-fade run backwards
## (top stripe out / bottom stripe in) — "the opposite of opening". Emits `closed` when the pair
## is docked again, so the host can free this overlay and restore the roster's own docked pair.
## Put the screen straight into its fully-open SETTLED state WITHOUT animating — the transition's
## end state (box-open apertures full, cluster at LAYOUT_TOP, band cross-fade complete). Used when a
## host opens the Status/Equip screen non-transitionally (e.g. Item chosen from the main-formation
## START menu → the Equip slide runs, not the ○-press vitals slide). _ready already settled the box
## + cluster when autoplay_open=false; this also completes the band cross-fade (roster band OUT,
## detail top stripe IN) so `formation_band_factor()` reads the settled 0.0.
func settle_open() -> void:
	set_open_frame(_open_total_frames())
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.place_layout(UnitInfoCluster.LAYOUT_TOP)
	_formation_band_factor = 0.0
	_set_detail_band_factor(1.0)


## True while a chrome transition (entry slide, ○-press arc, box-open, or the reverse close /
## exit slide) is mid-flight — i.e. NOT at a resting state (settled-open or docked). The
## coordinator (ADR-0084) folds this into its `is_moving()` for input routing + guards.
func is_transitioning() -> bool:
	if _open_playing:
		return true
	return _tphase != _TPhase.NONE and _tphase != _TPhase.CLOSED and _tphase != _TPhase.OPEN


func play_close() -> void:
	if _cluster == null or not is_instance_valid(_cluster):
		closed.emit()   # nothing to animate — let the host tear down immediately
		return
	_open_playing = false                   # the CLOSE_BOX driver folds the panel now
	_tphase = _TPhase.CLOSE_BOX
	_tframe = 0
	_taccum = 0.0


## Animate ONLY the lower Eqp/Ability + stats panel box-CLOSE (§15.17 reverse) — the apertures
## shrink center-out to nothing — WITHOUT touching the chrome/cluster or sliding the pair. The
## sub-screen (Equip/Ability) back-out plays this FIRST and gates the rest of the exit on `lower_closed`
## (user 2026-08-08: the menu folds shut, THEN the chrome descent + roster un-slide happen at once),
## so the panels don't blink out LAST when the overlay is freed. Distinct from `play_close` (the
## ○-press Status close), which couples the box-close to its OWN chrome slide — here the chrome descent
## is the recipe's job, so this drives the apertures only. Emits `lower_closed` when fully shut;
## no-op-safe (emits at once) if the panel was never opened.
func play_lower_close() -> void:
	_open_playing = false
	if _open_total_frames() <= 0:
		lower_closed.emit()
		return
	_tphase = _TPhase.LOWER_CLOSE
	_tframe = 0
	_taccum = 0.0


## Play ONLY the chrome EXIT slide (LAYOUT_TOP→DOCKED + the §15.6 band cross-fade run
## BACKWARD), WITHOUT folding a lower panel — the box-less mirror of `play_entry_slide`
## (ADR-0084). The main-menu sub-screens (Equip/Ability/Change-Job) opened via
## `play_entry_slide` and own their own lower panel; on exit the pair simply descends and the
## host frees the whole overlay on `closed`, so there is no box-close to run. Reuses the
## existing CLOSE_SLIDE phase — the reverse cluster slide + reversed `band_crossfade` already
## live there. Emits `closed` when the pair reaches LAYOUT_DOCKED; with no cluster, at once.
func play_exit_slide() -> void:
	if _cluster == null or not is_instance_valid(_cluster):
		closed.emit()
		return
	_open_playing = false
	_cluster.begin_slide(UnitInfoCluster.LAYOUT_TOP, UnitInfoCluster.LAYOUT_DOCKED)
	# Start from the settled-open band state (this screen's top stripe full, roster band gone);
	# CLOSE_SLIDE fades the top stripe OUT and the roster band back IN as the pair drops.
	_formation_band_factor = 0.0
	_set_detail_band_factor(1.0)
	_tphase = _TPhase.CLOSE_SLIDE
	_tframe = 0
	_taccum = 0.0


# -----------------------------------------------------------------------------
# Chrome slide as a Player-DRIVEN recipe beat (ADR-0084). The main-menu sub-screen recipes
# (Change-Job / Equip / Ability) own the chrome raise/descend as their FIRST group so it FALLS OUT
# of playing the recipe reversed — no separately-authored exit (invariant 1). These expose the
# pure-function-of-frame core the self-clocked `_drive_transition` already used (the ○-press
# play_transition / play_close arc keeps that self-clock; it is not yet ported to a recipe), so the
# coordinator's ONE Player drives BOTH directions with its single accumulator + MAX_CATCHUP clamp.
# -----------------------------------------------------------------------------

## Forward-chrome beat length in menu-ticks (the §15.1 DOCKED→TOP slide).
func chrome_settle_frame() -> int:
	return VitalsSlideAnimator.settle_frame()


## Park the freshly-built overlay ready for a Player-driven chrome RAISE (Entry.DOCKED): pair at
## LAYOUT_DOCKED, lower panel closed, band at the roster start (roster band full / detail stripe
## hidden). The recipe's chrome beat (begin_chrome_raise → chrome_step_forward) raises it from here.
func prepare_chrome_docked() -> void:
	if _cluster == null or not is_instance_valid(_cluster):
		return
	_open_playing = false
	_close_lower_panel()
	_cluster.place_layout(UnitInfoCluster.LAYOUT_DOCKED)
	_formation_band_factor = 1.0
	_set_detail_band_factor(0.0)


## Arm the FORWARD chrome beat (recipe chrome-group on_enter_forward): the §15.1 pair raise +
## §15.6 band cross-fade, driven frame-by-frame by chrome_step_forward. Entered from the MAIN menu
## (path 1) the pair starts DOCKED and rises; entered from the already-open detail screen (path 2)
## the chrome is ALREADY at TOP, so arm a no-op TOP→TOP HOLD (and leave the band settled) — replaying
## the beat must not drop-then-raise it. Frame 0 is snapped to the start so nothing flashes at TOP.
func begin_chrome_raise() -> void:
	if _cluster == null or not is_instance_valid(_cluster):
		return
	_open_playing = false
	_close_lower_panel()                     # windows stay shut through the slide
	_chrome_hold = _cluster.vitals_origin_px().distance_to(UnitInfoCluster.LAYOUT_TOP["vitals"]) < 1.0
	if _chrome_hold:
		# Already up (path 2): hold at TOP, band already at the settled open state — don't disturb it.
		_cluster.begin_slide(UnitInfoCluster.LAYOUT_TOP, UnitInfoCluster.LAYOUT_TOP)
		_formation_band_factor = 0.0
		_set_detail_band_factor(1.0)
	else:
		_formation_band_factor = 1.0
		_set_detail_band_factor(0.0)
		_cluster.begin_slide(UnitInfoCluster.LAYOUT_DOCKED, UnitInfoCluster.LAYOUT_TOP)
	_cluster.set_slide_frame(0)


## Arm the REVERSE chrome beat (recipe chrome-group on_enter_reverse): the box-less mirror of
## begin_chrome_raise — the pair descends TOP→DOCKED with the band cross-fade run BACKWARD, driven by
## chrome_step_reverse. The sub-screen's own lower panel was already torn down earlier in the reverse
## play, so there is no box to fold.
##
## `hold` is the MIRROR of begin_chrome_raise's path-2 HOLD, and it exists because the descent is no
## longer unconditional. This used to say "always a real descent (the full-unwind exit returns to the
## roster, RE25)" — true while every sub-screen back-out unwound off the Status screen. ADR-0137
## Amendment 7 makes the MAP host's back-out RETURN to it, and a chrome that was HELD on the way in
## must be held on the way out too: descending it would dock the vitals pair onto a roster that this
## host does not have, and then have to raise it again for a screen that never left.
func begin_chrome_descend(hold := false) -> void:
	if _cluster == null or not is_instance_valid(_cluster):
		return
	_open_playing = false
	_chrome_hold = hold
	_formation_band_factor = 0.0
	_set_detail_band_factor(1.0)
	if hold:
		# Held at TOP with the band already at the settled detail state — the exact mirror of the
		# path-2 forward hold, and `chrome_step_reverse` skips the cross-fade for the same reason.
		_cluster.begin_slide(UnitInfoCluster.LAYOUT_TOP, UnitInfoCluster.LAYOUT_TOP)
	else:
		_cluster.begin_slide(UnitInfoCluster.LAYOUT_TOP, UnitInfoCluster.LAYOUT_DOCKED)
	_cluster.set_slide_frame(0)


## Step the FORWARD chrome slide to menu-tick `frame` (1..chrome_settle_frame): the pair rises and the
## band cross-fades in (roster band out / detail stripe in). A path-2 HOLD leaves both untouched.
func chrome_step_forward(frame: int) -> void:
	if _cluster == null or not is_instance_valid(_cluster) or _chrome_hold:
		return
	_cluster.set_slide_frame(frame)
	var cf := band_crossfade(_slide_fraction(frame))
	_formation_band_factor = cf.x
	_set_detail_band_factor(cf.y)


## Step the REVERSE chrome slide to menu-tick `frame`: the pair descends and the band cross-fades
## BACKWARD (detail stripe out / roster band in) — the mirror of chrome_step_forward, HOLD and all: a
## `begin_chrome_descend(true)` leaves both the pair and the band untouched, exactly as a path-2 hold
## does on the way forward.
func chrome_step_reverse(frame: int) -> void:
	if _cluster == null or not is_instance_valid(_cluster) or _chrome_hold:
		return
	_cluster.set_slide_frame(frame)
	var cf := band_crossfade(1.0 - _slide_fraction(frame))
	_formation_band_factor = cf.x
	_set_detail_band_factor(cf.y)


## Collapse the box-opening windows to nothing (apertures fully closed) — the pre-box-open
## state during the slide + dead gap. Nothing scales: both apertures are set EMPTY, so the
## `clip_world` scissor discards every fragment of both windows. The scene-level top vitals
## stripe (not a box-open member) holds full-size.
func _close_lower_panel() -> void:
	_stats_clip = Rect2i(_nudged_stats_container().get_center(), Vector2i.ZERO)
	_lower_clip = Rect2i(OPEN_CONTAINER.get_center(), Vector2i.ZERO)
	if _stats_origin != null and is_instance_valid(_stats_origin):
		_stats_origin._set_aperture(_stats_clip)   # element push (ADR-0088)
	if _lower_origin != null and is_instance_valid(_lower_origin):
		_lower_origin._set_aperture(_lower_clip)


## Advance the ○-press transition state machine by `delta` (menu-tick paced). Slides
## the cluster through the §15.1 keyframes, waits the dead gap, then hands to the
## box-open (play_open) — which the existing box-open driver in _process finishes.
func _drive_transition(delta: float) -> void:
	if _tphase == _TPhase.NONE or _tphase == _TPhase.OPEN or _tphase == _TPhase.CLOSED:
		return
	_taccum += delta
	while _taccum >= _MENU_TICK:
		_taccum -= _MENU_TICK
		_tframe += 1
		if _tphase == _TPhase.SLIDE or _tphase == _TPhase.ENTRY_SLIDE:
			_cluster.set_slide_frame(_tframe)
			# Cross-fade the two bands with the slide (§15.6): bottom out, top in.
			var cf := band_crossfade(_slide_fraction(_tframe))
			_formation_band_factor = cf.x
			_set_detail_band_factor(cf.y)
			if _tframe >= VitalsSlideAnimator.settle_frame():
				_cluster.set_slide_frame(VitalsSlideAnimator.settle_frame())
				# Settled: bottom band fully gone, top stripe at full strength.
				_formation_band_factor = 0.0
				_set_detail_band_factor(1.0)
				if _tphase == _TPhase.ENTRY_SLIDE:
					# First-class entry slide: STOP here (no box-open) and hand off to the host,
					# which runs the sub-screen's own transition (Change-Job / Equip / Ability).
					_tphase = _TPhase.NONE
					_tframe = 0
					entry_slide_done.emit()
					return
				_tphase = _TPhase.GAP
				_tframe = 0
		elif _tphase == _TPhase.GAP:
			if _tframe >= _GAP_TICKS:
				_tphase = _TPhase.OPEN
				play_open()   # phase 3 — the box-open driver takes over
				return
		elif _tphase == _TPhase.CLOSE_BOX:
			# Reverse of the box-open: the apertures shrink shut (open frame counts DOWN from the
			# settled total). Because the lower window lags the stats band on OPEN, on CLOSE it
			# collapses FIRST (n−delay hits 0 while the stats band is still shrinking) — the mirror.
			var total := _open_total_frames()
			set_open_frame(maxi(total - _tframe, 0))
			if _tframe >= total:
				_close_lower_panel()      # snap the last step to fully closed
				_tphase = _TPhase.CLOSE_GAP
				_tframe = 0
		elif _tphase == _TPhase.LOWER_CLOSE:
			# Lower-panel-ONLY box-close (sub-screen exit): the SAME aperture shrink as CLOSE_BOX,
			# but it does NOT proceed to a chrome slide — the chrome descent is the recipe's job,
			# running concurrently. Ends by emitting `lower_closed` and returning to NONE.
			var ltotal := _open_total_frames()
			set_open_frame(maxi(ltotal - _tframe, 0))
			if _tframe >= ltotal:
				_close_lower_panel()      # snap the last step to fully closed
				_tphase = _TPhase.NONE
				_tframe = 0
				lower_closed.emit()
				return
		elif _tphase == _TPhase.CLOSE_GAP:
			if _tframe >= _GAP_TICKS:
				_cluster.begin_slide(UnitInfoCluster.LAYOUT_TOP, UnitInfoCluster.LAYOUT_DOCKED)
				_tphase = _TPhase.CLOSE_SLIDE
				_tframe = 0
		elif _tphase == _TPhase.CLOSE_SLIDE:
			_cluster.set_slide_frame(_tframe)
			# Cross-fade RUN BACKWARDS: open_amount falls 1→0 as the pair drops top→docked,
			# so band_crossfade fades the top stripe OUT and the bottom stripe back IN.
			var cf := band_crossfade(1.0 - _slide_fraction(_tframe))
			_formation_band_factor = cf.x
			_set_detail_band_factor(cf.y)
			if _tframe >= VitalsSlideAnimator.settle_frame():
				_cluster.set_slide_frame(VitalsSlideAnimator.settle_frame())
				# Docked again: bottom band back at full, top stripe gone.
				_formation_band_factor = 1.0
				_set_detail_band_factor(0.0)
				_tphase = _TPhase.CLOSED
				closed.emit()             # the host frees the overlay + restores the roster pair
				return


# -----------------------------------------------------------------------------
# Box-open animation (§15.17) — a growing rectangular APERTURE (GPU scissor) that reveals
# each fully-rendered window center-out. NOT a scale: nothing changes size; the window
# content (frame chrome, bands, icons, text) is drawn at its settled position and CLIPPED
# to the aperture (live-confirmed 2026-08-05 — a paused mid-open frame shows the content
# hard-clipped mid-glyph with NO frame, the frame appearing only once the aperture reaches
# the panel edges). The two box-opening windows (stats band + Eqp/Ability) each reveal through
# their own aperture, opening TOGETHER — the same center-out progress, each about its own centre
# (user 2026-08-05: "same time, not in sequence"; the per-window stagger is a kept hook, now 0).
# -----------------------------------------------------------------------------
func play_open() -> void:
	_open_frame = 0
	_open_playing = true
	_open_accum = 0.0
	set_open_frame(0)


## Apply the box-open at animation frame `n`: set each window's aperture (`clip_world` scissor)
## to its §15.17 center-out rect. Both windows open on frame `n` (the Eqp/Ability panel may lag
## by `_lower_open_delay()`, currently 0 ⇒ they open together). n past the settle holds each
## aperture at its full window rect (= no visible clip → the settled composition).
func set_open_frame(n: int) -> void:
	_stats_clip = _aperture(_nudged_stats_container(), n)
	_lower_clip = _aperture(OPEN_CONTAINER, n - _lower_open_delay())
	# Both apertures land through their ELEMENTS (ADR-0088): _set_aperture pushes each
	# subtree via the clip engine's fresh discovery (stats: chrome + legend + glyphs;
	# lower: chrome + bands + tabs + icons + equip items). The hand mats arrays keep only
	# their §15.21 backgrounding / debug-swap role.
	if _stats_origin != null and is_instance_valid(_stats_origin):
		_stats_origin._set_aperture(_stats_clip)
	if _lower_origin != null and is_instance_valid(_lower_origin):
		_lower_origin._set_aperture(_lower_clip)


## The current Eqp/Ability window aperture (display px) — the growing scissor rect. Exposed
## for the guards: `size == 0` ⇒ closed, `== OPEN_CONTAINER` ⇒ fully open (no clip).
func lower_aperture() -> Rect2i:
	return _lower_clip


## The current stats-band window aperture (display px).
func stats_aperture() -> Rect2i:
	return _stats_clip


## The center-out aperture rect for a window at open-frame `frame`. frame < 0 (the window has
## not started opening) ⇒ an EMPTY rect at the centre (nothing revealed). Uses the §15.17
## curve + ROM-integer center-out math (BoxOpenAnimator), so p=60 ⇒ {54,148,150,64} for the
## lower container — the live-confirmed mid-open prim.
func _aperture(container: Rect2i, frame: int) -> Rect2i:
	if frame < 0:
		return Rect2i(container.get_center(), Vector2i.ZERO)
	return BoxOpenAnimator.rect_at_frame(container, frame, fast)


## (The hand `_apply_clip(mats, rect)` push retired — both box-open windows aperture
## through their registered elements + the shared clip engine now, ADR-0088. `_clip_world`
## below remains as the display→world clip math home the layout guard asserts against.)


## World-space bounds (xmin, ymin, xmax, ymax) of a display-space aperture rect, matching
## screen_to_world (wx = px·ppu, wy = −py·ppu — so display-y flips to world-y). An empty rect
## ⇒ an inverted (never-passing) box, so the whole window is discarded (fully closed).
func _clip_world(rect: Rect2i) -> Vector4:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Vector4(1e20, 1e20, -1e20, -1e20)
	var x0 := float(rect.position.x) * PIXELS_PER_UNIT
	var x1 := float(rect.position.x + rect.size.x) * PIXELS_PER_UNIT
	var y_top := -float(rect.position.y) * PIXELS_PER_UNIT               # world ymax (display top)
	var y_bot := -float(rect.position.y + rect.size.y) * PIXELS_PER_UNIT # world ymin (display bottom)
	return Vector4(x0, y_bot, x1, y_top)


## Open-frames the lower Eqp/Ability window lags the stats band. 0 ⇒ the two box-opening
## windows open TOGETHER — the same center-out progress, each about its own centre (user
## 2026-08-05: "the top and bottom panels should open at the same time, not in sequence").
## (Kept as a hook: a positive value would stagger stats-then-lower.)
func _lower_open_delay() -> int:
	return 0


## Total open-frames until BOTH windows have settled (stats settle + the lower window's lag).
func _open_total_frames() -> int:
	return _lower_open_delay() + BoxOpenAnimator.settle_frame(fast)


func _process(delta: float) -> void:
	# Clamp the per-frame catch-up so a delta spike / render_unfocused throttle can't collapse the
	# slide or box-open into ONE visual frame (the teleport). Bounds both delta-paced steppers below.
	delta = minf(delta, _MAX_CATCHUP)
	_drive_transition(delta)   # §15.5 slide → gap → (hands off to the box-open below)
	# §15.25 slot-cursor glove bob: one table step per vsync; the select table rides one cycle after
	# a nav. Runs whenever the panel holds focus, independent of the box-open below.
	if _slot_focused:
		_slot_bob_accum += delta
		while _slot_bob_accum >= _BOX_OPEN_TICK:
			_slot_bob_accum -= _BOX_OPEN_TICK
			_slot_bob_frame += 1
			if _slot_moving_frames > 0:
				_slot_moving_frames -= 1
				if _slot_moving_frames == 0:
					_slot_bob_frame = 0   # hand back to the idle table at phase 0
		_place_slot_cursor()
	if not _open_playing:
		return
	# Advance one curve index PER VSYNC (_BOX_OPEN_TICK, §15.17: the ROM box-open indexes its
	# curve once per builder-loop iteration = once per vsync; the curve already bakes the holds
	# as repeated entries). Wall-clock so it plays the same on any refresh rate.
	_open_accum += delta
	while _open_accum >= _BOX_OPEN_TICK:
		_open_accum -= _BOX_OPEN_TICK
		_open_frame += 1
		set_open_frame(_open_frame)
		if _open_frame >= _open_total_frames():
			_open_playing = false
			set_open_frame(_open_total_frames())
			if _tphase == _TPhase.OPEN:
				_tphase = _TPhase.NONE   # the ○-press arc is fully settled (chrome up + panel open)
				opened.emit()
			break


# --- placement helpers (ui3 idiom, mirrored from FormationScene) -------------

## World position of a virtual-screen pixel (top-left origin, +X right / -Y down).
func screen_to_world(px: float, py: float) -> Vector3:
	return Vector3(px * PIXELS_PER_UNIT, -py * PIXELS_PER_UNIT, 0.0)


## World-Z the overlay offset adds (0 off the fork / standalone). The lower-panel group is
## lifted by this; the scene-level bands + the cluster fold it into their own rung instead.
func _overlay_z() -> float:
	return DepthMode.rung_z(overlay_rung_offset) if Fold.owns() else 0.0


## The band cross-fade (§15.6 / user 2026-08-05): as the vitals pair slides bottom→top the
## roster's BOTTOM band fades OUT and this screen's TOP stripe fades IN (the ROM slides one
## band with the pair; the port models it as two static bands cross-faded). `s` is the slide
## fraction (0 docked → 1 settled). Returns (formation_factor, detail_factor), each a `full_sub`
## multiplier: bottom gone by s=0.6, top ramping in from s=0.4 to full at settle — so the bottom
## "fades away and THEN the top fades in" with a short overlap, not a binary swap.
static func band_crossfade(s: float) -> Vector2:
	var formation_out := clampf(1.0 - s / 0.6, 0.0, 1.0)
	var detail_in := clampf((s - 0.4) / 0.6, 0.0, 1.0)
	return Vector2(formation_out, detail_in)


## The slide fraction (0 docked → 1 settled) at transition frame `n` — the §15.1 keyframe
## offset walked toward 0, normalized by the docked start (144). Mirrors UnitInfoCluster.
func _slide_fraction(n: int) -> float:
	var span := float(VitalsSlideAnimator.SLIDE_CURVE[0])
	return 1.0 - float(VitalsSlideAnimator.offset_at_frame(n)) / span


## Set this screen's top vitals-stripe subtract strength to `factor` × its full value
## (0 = invisible, 1 = the oracle 120/255). Drives the ○-press fade-in. No-op pre-build.
func _set_detail_band_factor(factor: float) -> void:
	if _vitals_band_mat != null:
		_vitals_band_mat.set_shader_parameter("full_sub", VBAND_FULL_SUB * factor)


## Hide (or restore) every DetailScene PANEL — the unit-info cluster (portrait + vitals +
## nameplate) and the whole lower group `_open_root` (stats band, Eqp/Ability panel, the
## compare panel, the ◄L1/R1► pager, the slot glove). The top `detail.vitals_band` stripe and
## the 3D formation scene behind it are deliberately LEFT ALONE — they are the ROM's window 0,
## which survives the Learn press (LEARN_PICKER.md §4 / round 10 #2: the ROM tears the detail
## panels down and builds the job list over the still-lit formation, restoring them on cancel).
func set_panels_visible(on: bool) -> void:
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.visible = on
	if _open_root != null and is_instance_valid(_open_root):
		_open_root.visible = on


## True while the panels above are shown (the settled state). For the guard.
func panels_visible() -> bool:
	if _open_root != null and is_instance_valid(_open_root):
		return _open_root.visible
	return _cluster != null and is_instance_valid(_cluster) and _cluster.visible


## Drive this screen's top vitals stripe from OUTSIDE the entry slide — the Learn job picker
## fades it out with its aperture walk and back in on cancel (round 10 #3). Same knob the
## ○-press cross-fade uses; 1 = the oracle 120/255, 0 = gone.
func set_vitals_band_factor(factor: float) -> void:
	_set_detail_band_factor(factor)


## The stripe's current `full_sub` as a fraction of its full value (1 = full, 0 = gone).
## Reads the live material so the guard sees what is actually on screen.
func vitals_band_factor() -> float:
	if _vitals_band_mat == null:
		return 0.0
	return float(_vitals_band_mat.get_shader_parameter("full_sub")) / VBAND_FULL_SUB


## The roster's BOTTOM band fade factor for the current transition frame (1 = full, 0 = gone).
## The host (FormationDetailTransition) reads this each frame and fades the formation band with
## it, so the two bands cross-fade in lockstep (this screen owns only its own top stripe).
func formation_band_factor() -> float:
	return _formation_band_factor


## The vitals-readout "black gradient stripe" (§14.6.6) — the SHARED UIVitalsBand element
## (the same one the formation roster draws), FULL-WIDTH across the screen at the Status
## screen's TOP vitals row. On the fork it folds (Fold.add → display-space subtract of the
## fg/255 y-trapezoid from the scene behind it); the opaque vitals panel + nameplate occlude
## it (near rung), so it shows only in the readout gap — the oracle black-behind-the-bars look.
func _build_vitals_band() -> void:
	# The stripe is HOUSED in the registered element `detail.vitals_band` (ADR-0088 audit):
	# a top-level scene element, UNCLIPPED (not a box-open member) with no transition (its
	# reveal is the band-factor cross-fade, not a beat). The band quad builds in absolute
	# display space under `self` then reparents keep-global (the column-band idiom).
	var band_elem := UI3Element.new({
		"id": "detail.vitals_band",
		# The §14.6.6 stripe box (screen-wide, feather-to-feather). Case-3 drivers (Amendment
		# 4 §2): the two REAL vertical knobs drive it; X stays screen-wide structural.
		"rect": UI3Element.derived(["detail.vband_top_out", "detail.vband_bot_out"], func() -> Rect2:
			return Rect2(VBAND_X0, VBAND_TOP_OUT, VBAND_X1 - VBAND_X0, VBAND_BOT_OUT - VBAND_TOP_OUT)),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	band_elem.name = "VitalsBandElement"
	add_child(band_elem)
	# `rung` is LIFTED by overlay_rung_offset (both the holder Z and the Fold.add order key,
	# in lockstep) so an overlaid Status screen's stripe subtracts the formation grid units
	# behind it — yet stays BEHIND the vitals panel (also lifted) which occludes it.
	_vitals_band_mat = UIVitalsBand.build(self, {
		"name": "VitalsBand",
		"x0": VBAND_X0, "x1": VBAND_X1,
		"y_top_out": VBAND_TOP_OUT, "y_top_in": VBAND_TOP_IN,
		"y_bot_in": VBAND_BOT_IN, "y_bot_out": VBAND_BOT_OUT,
		"full_sub": VBAND_FULL_SUB, "rung": RP_VITALS_BAND + overlay_rung_offset,
	}, PIXELS_PER_UNIT, SCREEN)
	var band_holder := get_node_or_null("VitalsBand") as Node3D
	if band_holder != null:
		band_holder.reparent(band_elem, true)   # keep-global: world transform unchanged
		# Remember the mesh carrier so a knob scrub reshapes it IN PLACE (never frees it).
		_vitals_band_mi = null
		for c: Node in band_holder.get_children():
			if c is MeshInstance3D:
				_vitals_band_mi = c
				break
		# reparent() = remove_child + add_child, so the band mesh's tree_exiting fires Fold's
		# un-enroll hook (b6400949d) and NULLS its render_layer — dropping it from the fold layer
		# so the subtractive stripe stops compositing. Re-enroll it after the move.
		if Fold.owns() and _vitals_band_mi != null:
			Fold.add(_vitals_band_mi, _vitals_band_mat, DepthMode.rung_z(RP_VITALS_BAND + overlay_rung_offset))


## Update the vitals band IN PLACE on a vband knob scrub (ADR-0088 Amendment 4 §2 write-back).
## The registered `detail.vitals_band` element re-derives its OWN rect from the two slugs and
## re-places its transform live (UI3Element._subscribe_rect_driver), and the band holder rides
## it — so POSITION is already handled. Here we only reshape the MESH to the new height and push
## the new feather params onto the SAME material.
##
## Crucially this does NOT free/rebuild — it is write-back shape #1 (mutate in place, ADR-0068
## Addendum W). Not because freeing a fold member is unsafe (it isn't — see CONTEXT "Fold member
## lifetime"), but because a tunable write-back runs inside the F3 SpinBox's gui_input callstack, and
## any synchronous free() there SIGSEGVs the 4.8 fork (wandering heap corruption via
## Timer::set_wait_time / the accessibility HashSet). In-place mutation frees nothing, so it is safe to
## run synchronously on the input frame. No-op before the first build.
func _update_vitals_band() -> void:
	if _vitals_band_mi == null or not is_instance_valid(_vitals_band_mi):
		return
	UIVitalsBand.update_extent(_vitals_band_mi, _vitals_band_mat, {
		"x0": VBAND_X0, "x1": VBAND_X1,
		"y_top_out": VBAND_TOP_OUT, "y_top_in": VBAND_TOP_IN,
		"y_bot_in": VBAND_BOT_IN, "y_bot_out": VBAND_BOT_OUT,
	}, PIXELS_PER_UNIT)


## One of the two Eqp/Ability dark column bands (§15.19) — the SAME UIVitalsBand element as
## the vitals stripe, but feathered LEFT/RIGHT (an x trapezoid) so it fades into the tan frame
## the way the wide stripe fades top/bottom. It belongs to the Eqp/Ability panel, so its material
## joins `_lower_mats` and is REVEALED center-out through the box-open aperture (§15.17 scissor,
## user 2026-08-05: "a window into the fully-rendered panel that reveals its contents") — the band
## is clipped by the growing aperture like the frame/icons, NOT scaled. It is reparented under the
## box-open group (keep-global) so it rides the overlay Z-lift with the rest; the fold rung
## RP_BAND(+overlay) still orders it behind the frame (subtracts the Pass-A scratch) yet occluded
## by the icons on it. The fold clip discard leaves depth/order untouched (it already discards its
## own out-of-band texels).
func _build_column_band(band_name: String, body_x0: float, body_x1: float) -> void:
	# body_x0..body_x1 is the OT rect (16px full subtract); the 2px feather sits OUTSIDE it, so the
	# quad spans body ± feather and the full body is preserved (oracle: 16px body + tight 2px edges).
	var f := BAND_X_FEATHER
	var band_mat := UIVitalsBand.build(self, {
		"name": band_name,
		"x0": body_x0 - f, "x1": body_x1 + f,   # quad covers the 2 feather columns each side
		# y: no feather — full subtract over [BAND_TOP, BAND_BOT] (top_out==top_in, bot_in==bot_out).
		"y_top_out": BAND_TOP, "y_top_in": BAND_TOP,
		"y_bot_in": BAND_BOT, "y_bot_out": BAND_BOT,
		# x: tight fade OUTSIDE the 16px body, into the frame. The shader floor-snaps the sample to
		# its virtual-pixel column, so these endpoints are chosen so integer eval yields the oracle's
		# clean 16→32→48 (152→136→120→104): a 3px ramp on the LEFT (out0=body-3 ⇒ cols body-2,body-1 =
		# 16,32) and, correcting floor's left-edge bias, in1=body-1/out1=body+2 on the RIGHT (cols
		# body,body+1 = 32,16). Two lit feather columns per side + a 16px body.
		"x_left_out": body_x0 - 3.0, "x_left_in": body_x0,
		"x_right_in": body_x1 - 1.0, "x_right_out": body_x1 + 2.0,
		"full_sub": BAND_SUB, "rung": RP_BAND + overlay_rung_offset,
	}, PIXELS_PER_UNIT, SCREEN)
	if band_mat != null:
		_lower_mats.append(band_mat)   # revealed center-out with the Eqp/Ability panel (§15.17)
	# Move the freshly-built band into the box-open group (keep-global: its settled world transform
	# — screen pos + fold depth/order — is unchanged) so it rides the overlay Z-lift with the panel.
	var holder := get_node_or_null(NodePath(band_name)) as Node3D
	var band_parent: Node3D = _lower_origin if (_lower_origin != null and is_instance_valid(_lower_origin)) else _open_root
	if holder != null and band_parent != null:
		holder.reparent(band_parent, true)   # keep-global: its settled world transform is unchanged; rides the frame origin
		# reparent() = remove_child + add_child, so the band mesh's tree_exiting fires Fold's un-enroll
		# hook (b6400949d) and NULLS its render_layer — dropping the subtractive column band from the
		# fold layer so it stops compositing (the tan frame shows through instead of the darken). Re-enroll
		# it (idempotent) with the SAME rung it was built with so it keeps subtracting. (f0e56a591 fixed the
		# vitals stripe + formation roster the same way but missed this box-open joint-panel site.)
		if Fold.owns() and band_mat != null:
			var band_mi: MeshInstance3D = null
			for c: Node in holder.get_children():
				if c is MeshInstance3D:
					band_mi = c
					break
			if band_mi != null:
				Fold.add(band_mi, band_mat, DepthMode.rung_z(RP_BAND + overlay_rung_offset))


## World-space centre of the box-open container (§15.17): display (129,180).
## Local offset (under `_open_root`) that lands an element at absolute display px.
## _open_root is SCREEN-AT-ORIGIN (ADR-0088) — local IS the plain screen_to_world image;
## the old container-centre anchor (and its subtraction here) is retired.
func _local_under_container(px: float, py: float) -> Vector3:
	return screen_to_world(px, py)


## Local base for a stats-band glyph (number/label) at display (px,py), LIFTED onto the RP_TEXT fold
## rung on the fork (ADR-0077 dec. 7: no unauthored depth). The stats numbers were the Z=0 floor
## holdout — rung-less, so the F3-draggable vitals band composited over them. RP_TEXT is strictly
## NEARER than the stats frame (RP_WINDOW_FRAME), so the opaque frame never occludes its own glyphs,
## and nearer than the band. Off-fork the lift is skipped (ordering falls back to render_priority).
func _stats_text_base(px: float, py: float) -> Vector3:
	var base := _local_under_container(px, py)
	if Fold.owns():
		base += Vector3(0.0, 0.0, DepthMode.rung_z(RP_TEXT))
	return base


## §15.26 Round 44 — the one knob that shifts the whole stats-compare panel onto the oracle.
## World-space offset of STATS_PANEL_NUDGE (display px, +y down → world -y).
func _stats_panel_nudge_world() -> Vector3:
	return Vector3(STATS_PANEL_NUDGE.x * PIXELS_PER_UNIT, -STATS_PANEL_NUDGE.y * PIXELS_PER_UNIT, 0.0)


## The stats box-open APERTURE rect (display px), BEFORE the R44 nudge. Its x/width are INDEPENDENT
## (the full-width box-open sweep, shared with the lower panel — deliberately WIDER than the inset
## frame chrome, §15.18), taken from STATS_CONTAINER. But its y/height are DERIVED from STATS_FRAME so
## the reveal window RIDES the frame: move or resize the stats frame and its aperture follows. This
## replaces the old hand-kept "y/h in lockstep" convention (round 38) that silently broke when the
## frame-group refactor let the frame move — content slid past the parked aperture and clipped.
func _stats_container() -> Rect2i:
	return Rect2i(STATS_CONTAINER.position.x, int(STATS_FRAME.position.y),
		STATS_CONTAINER.size.x, int(STATS_FRAME.size.y))


## The stats aperture shifted by the R44 whole-panel nudge so it reveals the moved content (not the
## original rect — else the top of the up-nudged frame would be clipped).
func _nudged_stats_container() -> Rect2i:
	var c := _stats_container()
	return Rect2i(c.position + Vector2i(STATS_PANEL_NUDGE), c.size)


# `z_rung`: the fold depth rung (rung_z) so the engine fold's Pass-B depth test orders this frame vs
# the subtractive column bands — the lower window (far), the icons on the bands (near). REQUIRED (no
# default) so "unauthored depth" is unspeakable (ADR-0077 dec. 7): every caller must NAME a rung,
# even rung 0 (RP_BACKGROUND, the authored back). Recorded as `z_rung` meta for the guard; the Z-lift
# itself is only applied on the fork (off-fork ordering falls back to render_priority).
func _add_frame(parent: Node3D, rect: Rect2, rung: int, z_rung: int, in_container: bool = false,
		mats_out = null) -> UIFrame:
	var frame := UIFrame.new()
	frame.opaque = true
	parent.add_child(frame)                 # _ready builds mesh + material
	frame.pixels_per_unit = PIXELS_PER_UNIT
	frame.pixel_aspect_ratio = 1.0          # detail chrome is square-pixel (matches formation)
	frame.render_priority = rung
	frame.frame_size = rect.size            # set LAST → triggers _update_mesh with all params
	var base := _local_under_container(rect.position.x, rect.position.y) if in_container \
		else screen_to_world(rect.position.x, rect.position.y)
	if z_rung >= 0 and Fold.owns():
		base += Vector3(0.0, 0.0, DepthMode.rung_z(z_rung))
	frame.position = base
	# Record the AUTHORED rung so the no-unauthored-depth guard can key on it (ADR-0077 dec. 7):
	# on OR off the fold (off-fork the Z-lift above is skipped, but the authored intent is unchanged).
	frame.set_meta("z_rung", z_rung)
	if mats_out != null and frame.get_material() != null:
		mats_out.append(frame.get_material())   # so the box-open clip can reveal the frame chrome
	return frame


## Arm the §15.21 "send to background" CLUT remap on a lower Status window FRAME. The frame is
## pre-baked RGB, so the shader nearest-matches each texel to _FRAME_FG (0x7C3C) and remaps to the
## same-index _FRAME_BG (0x7D3C) whenever `backgrounded` is set. Loaded here but INACTIVE
## (backgrounded 0) — set_backgrounded(true) flips it. No-op if the frame has no material yet. Only
## the stats/Eqp/Ability frames get this; the nameplate/vitals cluster stays tan (separate group).
func _background_frame(frame: UIFrame) -> UIFrame:
	if frame == null:
		return frame
	var m := frame.get_material()
	if m != null:
		m.set_shader_parameter("fg_palette", _FRAME_FG)
		m.set_shader_parameter("bg_palette", _FRAME_BG)
		m.set_shader_parameter("palette_count", 16)
		m.set_shader_parameter("backgrounded", 0.0)
	return frame


## §15.21 "send window to background": flip the whole lower Status subtree (frames + stats text +
## Eqp/Ability icons/tabs) to its background CLUTs — the per-index swap that recolours the windows
## when a menu (e.g. the START action sub-menu) takes focus over them. Uniform over the subtree; the
## vitals+nameplate cluster is a separate group and is left untouched (stays foreground/tan). Default
## is foreground — nothing calls this in _ready.
func set_backgrounded(on: bool) -> void:
	_backgrounded = on
	var v := 1.0 if on else 0.0
	for m in _stats_frame_mats:
		m.set_shader_parameter("backgrounded", v)
	for m in _stats_text_mats:
		m.set_shader_parameter("backgrounded", v)
	for m in _lower_mats:
		m.set_shader_parameter("backgrounded", v)
	for m in _pager_mats:   # §15.22: ◄L1/R1► blue WITH the lower windows on menu-open (Oracle B)
		m.set_shader_parameter("backgrounded", v)
	# The per-slot Eqp/Ability NAME columns swap by ink twins (formation_font_opaque), not palette_bg_tex.
	_apply_item_name_bg(_equip_item_mats, on)
	_apply_item_name_bg(_ability_item_mats, on)


## §15.21: the per-slot Eqp item + Ability NAME columns use the 3-ink formation_font_opaque shader (the
## SAME mechanism as the list-menu rows), so their deactivation swap is an ink-twin re-set — NOT the
## palette_bg_tex swap the frames/icons/stats use. Without this the names stayed tan while the panel
## around them went blue. Re-ink a name-column mat list to the §15.21 bg twins (or back to fg); shared
## by both backgrounding entry points and re-applied on every name rebuild so a repaint-while-blue stays
## blue. The fg inks are UIMenuText's mount defaults (INFO_INK_*); the bg twins are the row-text twins.
func _apply_item_name_bg(mats: Array, on: bool) -> void:
	for m in mats:
		if m == null or not is_instance_valid(m):
			continue
		m.set_shader_parameter("palette_light",
			UIMenuText._ink(StartActionMenu._ROW_INK_BG_LIGHT if on else UIUnitNameplate.INFO_INK_DARK))
		m.set_shader_parameter("palette_mid",
			UIMenuText._ink(StartActionMenu._ROW_INK_BG_MID if on else UIUnitNameplate.INFO_INK_MID))
		m.set_shader_parameter("palette_dark",
			UIMenuText._ink(StartActionMenu._ROW_INK_BG_DARK if on else UIUnitNameplate.INFO_INK_LIGHT))


func is_backgrounded() -> bool:
	return _backgrounded


## §15.26 equip-picker preview: blank every stats-band VALUE to "-" (labels + "…" leader stay tan).
## SELECTIVE — unlike set_backgrounded this does NOT blue the band; it stays foreground, just dashed.
## Idempotent; rebuilds the stats text in the current mode.
func set_stats_preview(on: bool) -> void:
	# Plain (dash) preview drops any NUMERIC delta — the delta path is exclusively
	# set_stats_preview_delta, so a later dash-mode request (e.g. remove on an empty slot)
	# never renders a stale +N/-N. Keep the no-op short-circuit only when nothing changes.
	var had_delta := not _stats_delta_values.is_empty()
	if _stats_preview == on and not had_delta:
		return
	_stats_preview = on
	_stats_delta_values = {}
	_stats_delta_slot = -1
	_build_stats_text()


func is_stats_preview() -> bool:
	return _stats_preview


## §15.26 numeric preview (EQUIP_STAT_PREVIEW.md): enter stats-preview AND fill the compare panel
## with the SIGNED per-field delta of the item under the cursor. `delta` = {wp, wev, hp, mp} (the
## EquipStatDelta.compute output); `slot` = the focused UnitProgression.EquipSlot, so the Weap.Power
## R (slot 0) vs L (slot 1) row fills. wp/wev colour the Weap.Power numbers here; hp/mp are routed to
## the vitals numerators by the caller (set_vitals_preview_delta). An EMPTY `delta` = plain dashes
## (== set_stats_preview(true)). Idempotent-rebuild on every cursor move.
func set_stats_preview_delta(delta: Dictionary, slot: int) -> void:
	_stats_delta_values = delta.duplicate()
	_stats_delta_slot = slot
	_stats_preview = true
	_build_stats_text()


## §15.26 guard/wiring: the signed per-field delta the panel is currently previewing (empty in dash
## mode). {wp, wev, hp, mp}; lets the orchestrator + guards read back what the cursor pushed.
func stats_preview_delta() -> Dictionary:
	return _stats_delta_values.duplicate()


## Guard seam (full band coverage): the exact strings the last preview build painted per band field
## ({move,jump,speed,r_at,l_at,c_ev,s_ev,a_ev} → "+N"/"-N"/"-"). Empty outside preview.
func stat_delta_preview_strings() -> Dictionary:
	return _stats_delta_preview_strings.duplicate()


## §15.26 guard: how many stats-text glyphs render through the blue (positive) vs red (negative)
## delta CLUT — i.e. how many delta digits are coloured by sign. Zero for plain dash-mode preview.
func stats_delta_glyph_palette_counts() -> Dictionary:
	var pos := 0
	var neg := 0
	for m in _stats_text_mats:
		if m == null or not is_instance_valid(m):
			continue
		var p = m.get_shader_parameter("palette_tex")
		if p == _delta_pal_pos:
			pos += 1
		elif p == _delta_pal_neg:
			neg += 1
	return {"pos": pos, "neg": neg}


## §15.26 DEFECT #8 guard: how many stats panels are drawn — 1 normally, 2 in the picker preview (the
## base + the offset delta/compare panel).
func stats_panel_count() -> int:
	return 2 if stats_delta_active() else 1


## Is the second (delta/compare) stats panel currently built? True only in the picker's preview state.
func stats_delta_active() -> bool:
	return _stats_delta_root != null and is_instance_valid(_stats_delta_root)


## The delta panel's offset from the base (display px) — 2px up-left (slot-0xc vs slot-0xb, §15.26 C).
func stats_delta_offset() -> Vector2:
	return STATS_DELTA_NUDGE


## §15.26 DEFECT #8 guard: glyph-mesh count in the BASE stats-text group. The delta (compare) panel is a
## `duplicate()` of this group, so on a healthy build the two counts MATCH. They diverge (delta ≈ 2×) if
## the duplicate captures glyphs still queued-for-free from the prior view = the "garbage glyphs" bug.
func stats_glyph_count() -> int:
	return _count_meshes(_stats_text_root)


## §15.26 DEFECT #8 guard: glyph-mesh count in the DELTA panel's duplicated stats-text subtree (name
## "StatsText", cloned in _rebuild_stats_delta). Must equal stats_glyph_count(); doubling = the bug.
func stats_delta_glyph_count() -> int:
	if _stats_delta_root == null or not is_instance_valid(_stats_delta_root):
		return -1
	var txt := _stats_delta_root.find_child("StatsText", true, false)
	return _count_meshes(txt)


func _count_meshes(root) -> int:
	if root == null or not is_instance_valid(root):
		return -1
	var n := 0
	for c in root.get_children():
		if c is MeshInstance3D and not c.is_queued_for_deletion():
			n += 1
		n += maxi(0, _count_meshes(c))
	return n


## §15.26 guard: is the vitals window in HP/MP preview ("-" numerator) mode?
func is_vitals_preview() -> bool:
	if _cluster != null and is_instance_valid(_cluster) and _cluster.vitals_panel() != null:
		return _cluster.vitals_panel().hpmp_preview()
	return false


## Guard seam: the HP/MP numerators currently applied to the vitals gauges (from the last
## set_unit_view). Render-readback for the equip/remove vitals-refresh guards. {} if not built.
func rendered_vitals_hp_mp() -> Dictionary:
	if _cluster != null and is_instance_valid(_cluster) and _cluster.vitals_panel() != null:
		return _cluster.vitals_panel().applied_hp_mp()
	return {}


## §15.26 guard: is the lower Eqp slot panel backgrounded (blue)? Reads the swap param off _lower_mats.
func lower_panel_backgrounded() -> bool:
	for m in _lower_mats:
		if m != null and is_instance_valid(m):
			return float(m.get_shader_parameter("backgrounded")) >= 0.5
	return false


## §15.26 guard: is the stats band backgrounded (blue)? It must STAY tan (preview, not blue) — this
## proves the picker's backgrounding is SELECTIVE (lower panel only), not the whole detail subtree.
func stats_band_backgrounded() -> bool:
	for m in _stats_frame_mats:
		if m != null and is_instance_valid(m):
			return float(m.get_shader_parameter("backgrounded")) >= 0.5
	return false


## §15.26 equip-picker preview: the vitals HP/MP NUMERATORS → "-" (bars, "/", and the 999 denominator
## stay). Delegated to the shared vitals window via the cluster. No-op-safe before the cluster is built.
func set_vitals_preview(on: bool) -> void:
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.set_vitals_preview(on)


## §15.26 numeric preview (EQUIP_STAT_PREVIEW.md §6): fill the vitals HP/MP numerators with the
## signed armor/accessory delta ("+5"/"-5" coloured; 0 → dash). Delegated to the shared vitals window.
func set_vitals_preview_delta(hp: int, mp: int) -> void:
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.set_vitals_preview_delta(hp, mp)


## §15.26: send ONLY the lower Eqp slot panel (+ the ◄L1/R1► pager) to background — the §15.21 CLUT
## swap over `_lower_mats` + `_pager_mats`, LEAVING the stats band tan (it goes to preview, not blue).
## This is the picker-open backgrounding; distinct from set_backgrounded (which blues the whole subtree
## when the START menu is up). Idempotent.
func set_slot_panel_backgrounded(on: bool) -> void:
	var v := 1.0 if on else 0.0
	for m in _lower_mats:
		m.set_shader_parameter("backgrounded", v)
	for m in _pager_mats:
		m.set_shader_parameter("backgrounded", v)
	# The per-slot Eqp/Ability NAME columns ride the lower panel — blue them WITH it (ink-twin swap).
	_apply_item_name_bg(_equip_item_mats, on)
	_apply_item_name_bg(_ability_item_mats, on)


## §15.26: hide/show the §15.25 slot-list glove WITHOUT dropping slot focus — the picker takes the
## active cursor while it is up (one active cursor on screen), and the slot glove returns on close.
func set_slot_cursor_visible(on: bool) -> void:
	if _slot_cursor_root != null and is_instance_valid(_slot_cursor_root):
		_slot_cursor_root.visible = on


## The full set of window materials the §15.21 swap covers (frames + stats text + lower icons/tabs).
## For the guard: the swap must be uniform over the whole subtree, not just the two frames.
func debug_window_materials() -> Array:
	var a := []
	a.append_array(_stats_frame_mats)
	a.append_array(_stats_text_mats)
	a.append_array(_lower_mats)
	a.append_array(_pager_mats)   # §15.22 corner pager buttons swap with the lower windows
	return a


## §15.22: the Status screen's own ◄L1 (top-left) / R1► (top-right) unit-pager buttons. While the
## Status overlay is up the roster sort-header is hidden (FormationScene.set_header_visible(false));
## the real screen shows only these two corner buttons. Each = a 3-slice RANGETILE frame + one baked
## caption cell through the shared menu button CLUT 0x7D7C — the SAME art/CLUT as the formation L2/R2
## buttons, live-captured from the OT at screen origins (12,14)/(224,14). They join `_lower_mats` so
## `set_backgrounded` blues them WITH the lower windows on start-menu open (Oracle B), NOT on
## detail-open (Oracle A = all tan). Also held in `_pager_mats` for the guard.
func _build_pager_buttons() -> void:
	var pager: Dictionary = _atlas.detail_pager()
	if pager.is_empty() or _open_root == null:
		return
	_button_pal = _palette_from_colors(_atlas.header_clut_colors("button"))   # 0x7D7C foreground
	_button_pal_bg = _palette_from_colors(_BG_7DFC)                           # 0x7DFC background twin
	# The pager pair is HOUSED in the registered element `detail.pager` (ADR-0088 audit): a
	# screen-anchored ASSEMBLY (two corner buttons placed absolute from the atlas consts) —
	# rect = the display screen box, so rel_world/_local_under_container coincide and the
	# element origin sits at zero. UNCLIPPED declares the §15.22 exemption (never box-open
	# clipped) that was previously encoded by array omission.
	var pager_root := UI3Element.new({
		"id": "detail.pager",
		"rect": UI3Element.screen_anchored(),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	pager_root.name = "PagerButtons"
	_open_root.add_child(pager_root)
	for side in ["left", "right"]:
		var btn: Dictionary = pager.get(side, {})
		if btn.is_empty():
			continue
		var ox := float(btn.get("origin_x", 0))
		var oy := float(btn.get("y", 0))
		for piece in btn.get("pieces", []):
			# piece = [dx, dy, u, v, w, h]; v=128 → the 3-slice frame, else the caption (over the body).
			var cell := Rect2(float(piece[2]), float(piece[3]), float(piece[4]), float(piece[5]))
			var pos := Vector2(ox + float(piece[0]), oy + float(piece[1]))
			var is_cap: bool = int(piece[3]) != 128
			var rp: int = RP_PAGER_CAP if is_cap else RP_PAGER_FRAME
			# in_container=true → `_local_under_container` lands them at absolute screen px + the overlay
			# Z-lift (same math the lower panel uses), so they sit in the true corners and occlude the
			# grid. Collected into `_pager_mats` — NOT `_lower_mats` — so the box-open aperture clip does
			# NOT erase them (they sit ABOVE OPEN_CONTAINER). They still background via set_backgrounded.
			_mount_icon(pager_root, cell, pos, _button_pal, rp, _button_pal_bg,
				rp, true, _pager_mats)


## The ◄L1/R1► pager button materials (§15.22) — a subset of debug_window_materials(); for the guard
## to assert they exist AND background with the lower windows on menu-open.
func debug_pager_button_materials() -> Array:
	return _pager_mats


# `z_rung` is REQUIRED (no default) so unauthored depth is unspeakable (ADR-0077 dec. 7): every icon
# names a fold rung, recorded as `z_rung` meta for the guard. In practice `rung` (render_priority) ==
# `z_rung` at every call site; both are passed so off-fork ordering and on-fork depth agree.
func _mount_icon(parent: Node3D, cell: Rect2, anchor_px: Vector2, palette: ImageTexture, z_rung: int,
		palette_bg: ImageTexture = null,
		rung: int = 0, in_container: bool = false, mats_out = null) -> MeshInstance3D:
	if _atlas.texture == null or cell.size == Vector2.ZERO:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = load(_SPRITE_SHADER)
	mat.set_shader_parameter("index_atlas", _atlas.texture)
	mat.set_shader_parameter("atlas_size", Vector2(_atlas.texture.get_width(), _atlas.texture.get_height()))
	mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y))
	mat.set_shader_parameter("palette_tex", palette)
	mat.set_shader_parameter("palette_bg_tex", palette_bg)   # §15.21 background CLUT (null until built)
	mat.set_shader_parameter("backgrounded", 0.0)            # foreground by default
	mat.set_shader_parameter("brightness", 1.0)
	mat.render_priority = rung
	if mats_out != null:
		mats_out.append(mat)   # box-open clip reveals this icon through the window aperture
	var holder := Node3D.new()
	var base := _local_under_container(anchor_px.x, anchor_px.y) if in_container \
		else screen_to_world(anchor_px.x, anchor_px.y)
	if z_rung >= 0 and Fold.owns():
		base += Vector3(0.0, 0.0, DepthMode.rung_z(z_rung))
	holder.position = base
	parent.add_child(holder)
	var mi := _quad(cell.size)
	mi.material_override = mat
	# Record the AUTHORED rung for the no-unauthored-depth guard (ADR-0077 dec. 7) — on OR off the
	# fold, mirroring _add_frame (off-fork the Z-lift is skipped but the authored intent is unchanged).
	mi.set_meta("z_rung", z_rung)
	holder.add_child(mi)
	return mi


## A TOP-LEFT-anchored quad of `size_px` (holder position = the top-left corner).
func _quad(size_px: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size_px * PIXELS_PER_UNIT
	mi.mesh = q
	mi.position = Vector3(q.size.x * 0.5, -q.size.y * 0.5, 0.0)
	return mi


static func _palette_from_colors(colors: Array) -> ImageTexture:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		img.set_pixel(i, 0, colors[i] if i < colors.size() else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
