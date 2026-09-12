class_name FormationScene
extends Node3D

## FORMATION / party-roster "sort list" screen — scene SKELETON (#171).
##
## Stands up the draw root, the tiled + vertical-gouraud stone background, and
## the empty 2x4 unit-cell grid at the FORMATION_SCREEN.md §12 coordinates. It
## draws no cell CONTENTS — later layer tickets (#173 body/orb/box, #174 sort
## value/chrome, #176 panels) mount into the per-cell anchors this scene exposes
## via get_cell(col, row).
##
## Coordinate model (§12.1): the overlay's packet `+0x80` X-centring is cancelled
## by the draw-env, so on-screen X = local X and Y = local + 126. §12.2 gives the
## grid directly: cell 56x48, anchor X = col*62 + 6, Y = 36 + row*60. We render in
## a virtual 256x240 screen mapped to world at PIXELS_PER_UNIT (the ui3 constant),
## origin top-left, +X right / -Y down. Painter's order via render_priority (ui3
## screen-space convention — no CUSTOM0 depth here).
##
## Vault: [[Display Space Blend Fold]]
## Vault: [[Formation Element Placement]]
## Vault: [[Formation Screen Compositing]]

const TunePort = ExMateriaPlatform.TunePort

## #1272 — `CharacterCatalog` is a host `[autoload]` line, and an addon cannot ship
## `project.godot` entries (ADR-0262 dec. 6). The catalogue SCRIPT already lives in
## `addons/exmateria_catalogue/`; `UIRoster` reaches the running node through its own
## `live()` and carries UI's empty-roster fallbacks. ADR-0308.
const UIRoster = preload("res://src/ui3/UIRoster.gd")

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const UnitMaterial = ExMateriaSpriteRig.UnitMaterial
const SpriteLayerManager = ExMateriaSpriteRig.SpriteLayerManager
const AnimationDatabase = ExMateriaSpriteRig.AnimationDatabase
const AnimationFrameCalculator = ExMateriaSpriteRig.AnimationFrameCalculator
const SpritePaletteResolver = ExMateriaSpriteRig.SpritePaletteResolver

## Emitted when the player CANCELS the view (Backspace/✕). The navigator hosts this as a
## view-only overlay and yields on it before proceeding to deployment (#234 E).

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
const JobDatabase = ExMateriaAlmanac.JobDatabase
const SpriteDatabase = ExMateriaAlmanac.SpriteDatabase
const UnitProgression = ExMateriaAlmanac.UnitProgression

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const SpriteLayer = ExMateriaSchema.SpriteLayer.Kind
const UnitMaterialVariant = ExMateriaSchema.UnitMaterialVariant.Kind
const Character = ExMateriaCatalogue.Character
const CharacterTemplateResolver = ExMateriaCatalogue.CharacterTemplateResolver

signal dismissed()

## Emitted when the player CONFIRMS (Enter/○) on a roster unit — the ○-press that opens
## that unit's Status/detail screen (§15.5). Carries the selected [Character]; a host
## overlays a DetailScene and plays the slide→box-open transition. (Enter on an empty
## roster still emits `dismissed`, preserving the pre-detail behavior.)
signal unit_activated(character)

const PIXELS_PER_UNIT := 0.04           # ui3 world-units per virtual pixel
const SCREEN := Vector2(256.0, 240.0)   # FFT virtual framebuffer

const CELL := Vector2(56.0, 48.0)       # §12.2 cell w=0x38, h=0x30
const COLS := 4
const ROWS := 2
const GRID_ORIGIN := Vector2(6.0, 36.0) # §12.2 col0/row0 anchor
const COL_PITCH := 62.0                 # §12.2 X = col*0x3e + 6
const ROW_PITCH := 60.0                 # §12.2 Y = 36 + row*0x3c


# -----------------------------------------------------------------------------
# Roster scroll windowing (ADR-0081 all-templates view). The fixed ROWS×COLS grid
# is a ROW-GRANULAR window onto a roster larger than 8: `scroll_offset` counts
# TOP ROWS scrolled off, so each step slides the window by COLS units. Pure index
# math — no animation, no pagination. The three helpers below are the seam.
# -----------------------------------------------------------------------------

## The ≤ ROWS*COLS units visible at `scroll_offset` rows down — `units` sliced from
## `scroll_offset*COLS` for one grid's worth. A short/over-run offset yields a
## partial or empty slice (Array.slice clamps), so callers stay crash-free.
static func scroll_window(units: Array, scroll_offset: int) -> Array:
	var start: int = scroll_offset * COLS
	return units.slice(start, start + ROWS * COLS)

## The last top-row offset that still fills the window — `total_rows - ROWS`, floored
## at 0 (a roster of ≤ one page never scrolls).
static func max_scroll_offset(count: int) -> int:
	var total_rows: int = int(ceil(float(count) / float(COLS)))
	return maxi(0, total_rows - ROWS)

## Pin an offset into `[0, max_scroll_offset(count)]` — advancing past the end (or a
## wild/negative value) clamps instead of scrolling into blank rows.
static func clamp_scroll(scroll_offset: int, count: int) -> int:
	return clampi(scroll_offset, 0, max_scroll_offset(count))


# -----------------------------------------------------------------------------
# Body render-input resolution (ADR-0072 / ADR-0081). The ONE place that turns a
# roster `Character` into the pieces `_build_cell_body` mounts — routed through the
# template resolver so a unit renders its OWN sheet, not a job sprite:
#   - folder-routed (unique / appearance-type): the body sheet is the resolved
#       template folder's `body.tga`; the animation seq/shp come from the template's
#       OWN `template.json` (a sheet reachable by no job still animates). This is
#       what fixes uniques rendering as their JOB sprite (Ramza-in-formation = Squire).
#   - job-routed generic: the legacy path — body sprite id + seq/shp via SpriteDatabase.
# `ok` is false only when neither a sheet nor a sprite could be found, so the caller
# warns once and skips exactly the un-renderable cells.
# -----------------------------------------------------------------------------

const _TEXTURE_DIR := "res://assets/sprites/textures/"

static func resolve_body_render(character) -> Dictionary:
	var visuals := CharacterTemplateResolver.resolve(character)
	var folder: String = visuals.get("template_folder", "")
	if not folder.is_empty():
		var meta := CharacterTemplateResolver.read_template_json(folder)
		var anim: Dictionary = meta.get("animation", {})
		var seq_type := String(anim.get("seq", ""))
		var shp_type := String(anim.get("shp", ""))
		# A flat fallback for the body sheet when the template names a sprite id (appearance-
		# types do; uniques don't) — load_body_sprite prefers the folder body.tga anyway.
		var flat := ""
		if meta.has("sprite_id") and meta.get("sprite_id") != null:
			var spr: String = SpriteDatabase.get_sprite(meta["sprite_id"]).get("spr_file", "")
			if not spr.is_empty():
				flat = _TEXTURE_DIR + spr.replace(".SPR", ".tga")
		return {
			"template_folder": folder,
			"flat_texture_path": flat,
			"seq_type": seq_type,
			"shp_type": shp_type,
			"palette_row": 0,
			"ok": seq_type != "" and shp_type != "",
		}
	# Job-routed generic (byte-identical to the prior inline lookup).
	var sprite_id: int = visuals.get("body_sprite_id", -1)
	var sprite_data := SpriteDatabase.get_sprite(sprite_id)
	var spr_file: String = sprite_data.get("spr_file", "")
	return {
		"template_folder": "",
		"flat_texture_path": _TEXTURE_DIR + spr_file.replace(".SPR", ".tga") if not spr_file.is_empty() else "",
		"seq_type": SpriteDatabase.get_seq_type(sprite_id),
		"shp_type": SpriteDatabase.get_shp_type(sprite_id),
		# THE ROW COMES FROM THE RIG, NOT THE RESOLVER (#1071, ADR-0272) — a render
		# fact with one owner, asked for with the job this branch already routed by.
		"palette_row": SpritePaletteResolver.job_body_palette_row(
			character.progression.current_job_id),
		"ok": not sprite_data.is_empty(),
	}


# --- ROM element placement — byte-exact (FORMATION_ELEMENT_PLACEMENT.md). ---
# Body: FUN_80117db8 @0x80117db8 centres the sprite at a FIXED cell offset and
# draws it NATIVE 1:1 (screen W×H = descriptor Uw×Vh). top-left =
# (cellX − Uw/2 + 31, cellY − Vh/2 + 24) ⇒ centre = (cellX+31, cellY+24),
# independent of sprite size. (§12.3's "cellX − 31 + ½Uw" had both signs flipped.)
const BODY_ANCHOR_DX := 31.0
const BODY_ANCHOR_DY := 24.0
# Roster descriptor cell = 24×40 (UNIT.BIN atlas; §13.3 Uw=0x18, Vh=0x28).
const ROSTER_DESC := Vector2(24.0, 40.0)
# Shadow: FUN_8011814c 2nd prim (tmpl 0x8018c704), placed RELATIVE TO THE BODY rect.
# Narrow (Uw<0x19, i.e. roster units): (bodyLeft, bodyTop+30). Wide (monsters):
# (bodyLeft+12, bodyTop+35). Drawn 20(W)×10(H) on screen from a 20×20 texel = a
# 2:1 VERTICAL SQUASH (the flat-on-floor look; NOT a POLY skew — the setter emits
# an axis-aligned POLY_FT4). Live-verified cell7 = (211,130,20,10).
const SHADOW_SCREEN_PX := Vector2(20.0, 10.0)
const SHADOW_FEET_DY_NARROW := 30.0   # bodyTop + 0x1e   (Uw <  0x19)
const SHADOW_FEET_DY_WIDE := 35.0     # bodyTop + 0x23   (Uw >= 0x19, monsters)
const SHADOW_WIDE_DX := 12.0          # bodyLeft + 0xc   (Uw >= 0x19)
const SHADOW_UW_GATE := 25            # 0x19
# Native-1:1 body scale: the unit compositor maps the FULL atlas height into the
# [0,1] quad, and the quad's on-screen size = body_scale / PIXELS_PER_UNIT px, so
# 1 native sprite-px == 1 virtual-px when body_scale = atlas_h * PIXELS_PER_UNIT
# (≈ 488 * 0.04 = 19.52). We derive per-unit scale from this so the composited
# Face-Front frame's VISIBLE height renders at the descriptor's Vh (40) px.

# --- Body compositor loc→screen calibration (formation_unit.gdshader) ----------
# The screen-space unit compositor maps a sprite loc-pixel ISOTROPICALLY: the
# aspect-ratio adjustment in pxl_pt_to_mesh (mesh_ar 1 / tex_ar 256/488) collapses
# BOTH axes to loc/atlas_w, so one loc-pixel spans body_scale/(BODY_ATLAS_W·PPU)
# virtual px on screen (= k below). So the composited sprite's loc-space visible
# bbox (SpriteLayerManager.current_body_bbox) drives the PLACEMENT (a FIXED uniform
# body_scale drives size — the ROM draws all minis at one scale, so job height
# differences are preserved, not normalized away):
#   • feet   : offset the holder so the bbox BOTTOM-centre (feet) lands on the
#              common standing baseline (cellX+31, cellY+FEET_BASELINE_DY) —
#              killing the per-job feet scatter and standing all units on one line.
# The map is analytic (no contradictory constant — the "≈19.5" and "loc/32" in the
# tree measure different things); k verified against the live framebuffer.
const BODY_ATLAS_W := 256.0                 # loc→UV divisor (atlas width; isotropic)
# A loc-coord's sub-pixel bias off the quad centre: shared_loc_offset(28,26 from
# unit.tres) + SPRITE_CENTER(100,100) − atlas_w/2(128,128). X cancels; Y = −2.
const BODY_LOC_BIAS := Vector2(0.0, -2.0)
# Units STAND on a common feet baseline (not centred — different-height jobs must
# share the ground line). The composited frame's visible-bbox BOTTOM (feet) is
# placed at cell-relative (BODY_ANCHOR_DX, FEET_BASELINE_DY); X stays the ROM body
# centre. Headful-tuned vs t04.png (oracle feet ≈ cellY+40, on the gold-box front).
const FEET_BASELINE_DY := 40.0

const _ASSET_DIR := "res://assets/ui/formation/"
const _BG_SHADER := "res://src/ui3/shaders/formation_background.gdshader"
const _OUTLINE_SHADER := "res://src/ui3/shaders/formation_cell_outline.gdshader"
const _ORB_SHADER := preload("res://src/ui3/shaders/formation_orb.gdshader")           # additive rim (STP=1)
const _ORB_OPAQUE_SHADER := preload("res://src/ui3/shaders/formation_orb_opaque.gdshader")  # opaque core (STP=0)
const _BOX_SHADER := preload("res://src/ui3/shaders/formation_box.gdshader")
const _BOX_SUB_SHADER := preload("res://src/ui3/shaders/formation_box_sub.gdshader")
const _SHADOW_SHADER := preload("res://src/ui3/shaders/formation_shadow.gdshader")  # subtractive feet decal
const _BAND_SHADER := preload("res://src/ui3/shaders/formation_band.gdshader")      # subtractive vitals-panel band
const _CYL_SHADER := preload("res://src/ui3/shaders/changejob_cylinder.gdshader")   # change-job commit cylinder (ABR 3)
const _SHADOW_TEX := "res://assets/materials/unit_shadow.png"              # ROM 20x20 radial blob
# Opaque, depth-writing proportional FONT.BIN glyphs for the info panel (#176):
# the ADR-0077 sibling of ui_font_char (discards, never writes ALPHA), so the
# name/job/Brave/Faith text occludes the folded band instead of being clobbered.
const _FONT_OPAQUE_SHADER := "res://src/ui3/shaders/formation_font_opaque.gdshader"
# FONT.BIN glyph top padding: the proportional glyph's ink starts ~2px below its
# cell top, so text cells drop by this to land on §14.6's oracle ink-top coords.
const FONT_INK_TOP_PAD := 2.0
# The HUD digit font has the SAME ~2px top pad — lift the digit rows by this so the
# number ink-tops land on §14.6 (so "01" top-aligns with the name, per the oracle).
const DIGIT_INK_TOP_PAD := 2.0

# The info panel's dark ink ramp (oracle-measured, dark-on-tan): every name/job/
# label/number glyph renders through this 3-tone. On the tan panel the glyph's
# bright atlas ink maps to INK_DARK (inverting the battle HUD's bright-on-dark).
const INFO_INK_LIGHT := Color(0.502, 0.471, 0.408)   # (128,120,104) glyph edge/AA
const INFO_INK_MID := Color(0.314, 0.314, 0.251)     # (80,80,64)
const INFO_INK_DARK := Color(0.188, 0.157, 0.125)    # (48,40,32) glyph body

# The zodiac glyph's faint dither browns (oracle-measured, §14.3) — slightly darker
# than the tan fill, NOT dark ink; the dominant two colours of the dithered outline.
const ZODIAC_BROWN_LIGHT := Color(0.502, 0.471, 0.408)  # (128,120,104)
const ZODIAC_BROWN_MID := Color(0.439, 0.408, 0.345)    # (112,104,88)

# --- Display-space FOLD variants (ADR-0077) ----------------------------------
# The five PSX add/sub prims join the engine-fold (ADR-0074): each wears a
# MONOMORPHIC `compositor_layer` shader and is handed to `Fold.add`, so the 4.8
# Forward+ engine Pass B blends it in the display-space scratch with the PSX
# per-step UNORM clamp — instead of the retired Mobile-era CompositorEffect.
# These are the twins of the five in-scene blend_add/blend_sub shaders below,
# adding only `compositor_layer`, a real-Z `DEPTH` write for occlusion, and
# (band) a direct display-space subtract now that the floor seeds the scratch.
# The in-scene shaders stay as the OFF-FORK fallback (Fold.owns() = false).
const _BOX_FOLD_SHADER := preload("res://src/ui3/shaders/formation_box_fold.gdshader")
const _BOX_SUB_FOLD_SHADER := preload("res://src/ui3/shaders/formation_box_sub_fold.gdshader")
const _ORB_RIM_FOLD_SHADER := preload("res://src/ui3/shaders/formation_orb_rim_fold.gdshader")
const _SHADOW_FOLD_SHADER := preload("res://src/ui3/shaders/formation_shadow_fold.gdshader")
const _BAND_FOLD_SHADER := preload("res://src/ui3/shaders/formation_band_fold.gdshader")
const _CYL_FOLD_SHADER := preload("res://src/ui3/shaders/changejob_cylinder_fold.gdshader")

## The six display-space add/sub prims and their (fold, in-scene fallback) shaders.
## `fold_shader_for(prim)` picks the compositor_layer variant when the engine
## fold owns compositing (fork + Forward+), else the Mobile in-scene blend twin —
## the same deliberate per-prim membership decision the callbacks/cursor use (ADR-0074).
## FormationFoldRoutingTest pins this map + the shaders' fold/exempt markers.
const FOLD_PRIMS := {
	"box_add": {"fold": _BOX_FOLD_SHADER, "scene": _BOX_SHADER},
	"box_sub": {"fold": _BOX_SUB_FOLD_SHADER, "scene": _BOX_SUB_SHADER},
	"orb_rim": {"fold": _ORB_RIM_FOLD_SHADER, "scene": _ORB_SHADER},
	"shadow": {"fold": _SHADOW_FOLD_SHADER, "scene": _SHADOW_SHADER},
	"band": {"fold": _BAND_FOLD_SHADER, "scene": _BAND_SHADER},
	# The Change-Job commit cylinder (§9) — the SIXTH prim, and the only one that exists for
	# just four seconds. Same routing decision as the other five: it is a PSX display-space
	# semi-transparent prim, so it belongs in the fold, not in the transparent colour layer.
	"changejob_cylinder": {"fold": _CYL_FOLD_SHADER, "scene": _CYL_SHADER},
}

## The shader for one add/sub prim: the `compositor_layer` variant when the build folds, else the
## in-scene Mobile blend fallback. The PICK is Fold.shader's (ADR-0191 dec. 2), tested on both
## branches in FoldTest; FOLD_PRIMS is what this producer hands it, per prim. Mirrors
## EffectCallback.blend_shader.
static func fold_shader_for(prim: String) -> Shader:
	var entry: Dictionary = FOLD_PRIMS[prim]
	return Fold.shader(entry["fold"], entry["scene"])

# The bottom-left vitals panel is the already-solved battle vitals readout
# (§14.4) — reused wholesale: portrait + Lv/Exp + HP/MP/CT gradient bars. It is a
# plain ui3 Node3D subtree (pixels_per_unit 0.04, same virtual scale as us).
const UIUnitInfoWindow = preload("res://src/ui3/UIUnitInfoWindow.gd")
const UnitInfoCluster = preload("res://src/ui3/UnitInfoCluster.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
## The BREAKOUT MARK (ADR-0137; CONTEXT.md "Formation screen hosting") — the fixed display-px
## point where a unit stands once it has been singled OUT of the roster. Body CENTRE, so it is
## the measured Equip/Ability settle (SETTLE_PX, a top-left ORIGIN) plus half the 24×40 roster
## descriptor: (166,173) + (12,20) = (178,193). DERIVED, not re-typed — the settle is a
## measurement and this must not silently desync from it.
##
## Both hosts land a unit on it by opposite means: the roster host slides the unit there while
## its rowmates exit the screen, the map host pans the CAMERA until the unit arrives on it. It is
## not Equip's — Ability uses the same mark, and Change-Job's oval centre derives from it.
const BREAKOUT_MARK_PX := SpriteSlideAnimator.SETTLE_PX + ROSTER_DESC * 0.5

# TYPE1 seq 2 = "Face Front" — the static, un-mirrored roster pose (§14.1).
const FACE_FRONT_SEQ := "2"

# Orb (§10): the 12x12 sprite sits at the cell's top-left. Selected cell pulses;
# others hold a per-cell spatial-falloff brightness.
const ORB_PX := Vector2(12.0, 12.0)
const ORB_BASE_LEVEL := 128.0   # PSX gouraud identity (128); selected base
const ORB_MIN_LEVEL := 80.0     # falloff clamp floor (§10.4)
const ORB_PULSE_MIN := -40.0    # triangle bounds (§10.3); base±pulse → [88,168]
const ORB_PULSE_MAX := 40.0
const ORB_PULSE_STEP := 4.0     # gouraud step per tick (measured off live OT)
const ORB_PULSE_HZ := 30.0      # ticks/sec = one step per 2 displayed frames.
								# DYNAMICALLY MEASURED (per-vsync sample of the OT
								# primitive 0x801F10D8): real period is 84 frames /
								# 1.40 s, held 2f per level + 4f per endpoint — NOT
								# the doc's 42 f (double-buffer alias). Time-driven,
								# so 1.40 s at any Godot framerate.

# --- Cursor GLIDE + fading TRAIL (§11.5 / §16.1) -----------------------------
# The logical cursor (selected_cell) SNAPS on a D-pad press; the VISIBLE gold box
# eases toward it via the integer law `slot = (3·old + target) >> 2` (per axis),
# leaving an 8-slot fading position trail, and the floor spotlight + swept orb/body
# brightness ride that same eased centre. DYNAMICALLY confirmed frame-for-frame vs
# the live OT (§16.1): centre_x RIGHT-press 48→…→93 (target 96), centre_y DOWN-press
# 75→…→118 (target 121) — both fit `(3·c+t)>>2` byte-exact, stalling ~3px short from
# integer truncation. Ticked at 60 Hz so the cadence is framerate-independent.
const GLIDE_HZ := 60.0
const TRAIL_LEN := 8
# Per-slot grey brightness MULTIPLY (§11.5.3, ROM const 0x8018C88C): slot0 = oldest /
# dimmest → slot7 = newest / full (128 = PSX gouraud identity). Multiplied into the box
# add/sub level so the trail fades behind the head. ROM-PARSED (ADR-0046) from WORLD.BIN
# into formation_tables.json by tools/parse_formation_tables.py — `_load_rom_tables` reads
# it into `_trail_ramp` at boot; this literal is only the FALLBACK for an isolated boot
# with no generated assets (the parser + its guard are the source of truth).
const _TABLES_PATH := "res://assets/ui/formation/formation_tables.json"
const TRAIL_RAMP_FALLBACK := [20.0, 35.0, 50.0, 65.0, 80.0, 90.0, 100.0, 128.0]

# Gold box (§11): 4 quadrant quads from one 32x16 ¼ texel, meeting at centre.
const BOX_QUAD_PX := Vector2(32.0, 16.0)
# Per-quadrant top-left (cell-relative px, from box centre) + UV mirror.
const _BOX_QUADRANTS := [
	{"off": Vector2(-32.0, -16.0), "flip": Vector2(0.0, 0.0)},  # top-left
	{"off": Vector2(0.0, -16.0),   "flip": Vector2(1.0, 0.0)},  # top-right (x)
	{"off": Vector2(-32.0, 0.0),   "flip": Vector2(0.0, 1.0)},  # bottom-left (y)
	{"off": Vector2(0.0, 0.0),     "flip": Vector2(1.0, 1.0)},  # bottom-right (xy)
]

# DEPTH LADDER (§12.1, ADR-0077). This screen WAS a flat overlay — every element
# coplanar at z=0 with depth OFF, draw order set entirely by render_priority. It now
# MATERIALIZES that painter's ladder into real distance-from-camera Z: each RP_* rung
# is a world-Z one OT bucket apart (rung_z), background farthest → header nearest.
# Because the Formation camera is orthographic that Z *is* the fold's order_z, so the
# add/sub prims fold in the right order (Fold.add) AND the opaque prims occlude the
# folded ones (box UNDER body, rim OVER body) — both fall out of the one Z. A direct
# port of the PSX ordering-table buckets (the box builder FUN_8011712c links sub=3 /
# add=4). Rungs MUST be distinct (≥ one bucket apart) or coincident prims z-fight /
# fold-tie. `rank` (Fold.add) is reserved for genuinely coincident prims (the 8
# glide-trail box slots). Bottom (far) → top (near):
const RP_BACKGROUND := 0
const RP_CELL_OUTLINE := 1     # placeholder scaffolding (off by default)
const RP_BOX_SUB := 2          # selection box, subtractive darken (under)
const RP_BOX_ADD := 3          # selection box, additive gold (over the sub shadow)
const RP_UNIT_SHADOW := 4      # per-unit subtractive feet decal (PSX bucket param_3-1=5):
							   #   above the gold box (buckets 3/4), below the body (6)
const RP_UNIT_BODY := 5        # unit sprite draws OVER the ground box + its own shadow
const RP_ORB := 6              # cell orb glow (topmost content)
const RP_CELL_BAR := 7         # per-cell HP/MP/CT fill swatch, over the orb, UNDER the digits
const RP_SORT_VALUE := 8       # per-cell sort readout ("Hp cur/max"), over the bar
const RP_HEADER_BAR := 9       # sort-tab header window bodies (tan bar, L2/R2 buttons)
const RP_HEADER_BOX := 10      # active-tab dark highlight box, over the tan bar
const RP_HEADER_LABEL := 11    # sort-tab label glyphs + L2/R2 captions, topmost
# RIGHT unit-info panel (#176), on the SAME depth ladder — its opaque, depth-writing
# frame/text/bullet occlude the folded subtractive band beneath it (ADR-0077), and
# stack over it near→far: frame (behind) < bullet/zodiac < text (front).
const RP_INFO_FRAME := 12      # tan 9-slice window, over the band
const RP_INFO_BULLET := 13     # blue orb bullet + zodiac glyph, on the frame
const RP_INFO_TEXT := 14       # unit-number / name / job / Brave·Faith glyphs, topmost
# The Change-Job commit cylinder (CHANGE_JOB_COMMIT.md §9) gets its OWN rung rather than
# borrowing one: `[dynamic]` the ROM's ordering table puts the 64 stripes in slot 0x38, in FRONT
# of the centre-unit quads at 0x33, and every roster-screen prim above is hidden while it plays,
# so nothing on this rung is coincident with anything. Still far below the job-title plate.
const RP_CHANGEJOB_CYLINDER := 15

## --- Pillarbox mask (gray letterbox bars, user 2026-08-08) ----------------------------------------
## The port presents the 256×240 square-pixel content in a 4:3 window, so the ortho camera's view is
## WIDER than the content: it spans virtual x≈[-32,288] (the cobble floor is only [0,256]), leaving a
## ~32px gray (0.3,0.3,0.3 ≈ sRGB 76) pillarbox margin on each side (the honest square-pixel framing,
## §15.24 item 5 revert e50032f38). Those margins are just the viewport CLEAR colour — nothing draws
## there — so anything that slides INTO the margin (a unit mid-Equip-slide, or the Change-Job ring as it
## enlarges off-screen on exit) renders OVER the gray, spilling past the framed content. The user's
## "make the gray bars on top of everything": draw an OPAQUE gray quad over each margin at a near-Z above
## all content so escaping sprites vanish behind it — the content is visually clipped to the 256×240 rect.
const PILLARBOX_GRAY := Color(0.3, 0.3, 0.3)   # matches the viewport clear colour (sRGB ≈ 76,76,76)
## Each mask covers from the content edge OUT past the camera frustum edge (frustum ≈ ±32px beyond the
## content; go to ±64 so the bar fully covers the visible margin regardless of the exact window aspect).
const PILLARBOX_MARGIN_PX := 64.0
## Near-Z the masks mount at (world units toward the ortho camera at z=10). ABOVE every content rung
## (the tallest — the detail overlay / menu — sits well under ~7 world Z = ~37 rungs × DepthMode.UNITS_PER_OT_BUCKET) yet
## still IN FRONT of the camera's near plane (~9.95), so it occludes everything without the Z-TRAP (a
## rung·0.19 large enough to top the overlay would land BEHIND the camera; a fixed near-Z sidesteps that).
const PILLARBOX_MASK_Z := 9.0

## Change-Job wheel front↔back painter's spread (§15.24 RE31, FUN_80119AA0 iVar6): the ring members all
## sit on the RP_UNIT_BODY rung, so their draw order is decided by a per-member SUB-RUNG Z bias monotonic
## in oval screen-Y (ChangeJobWheel.ring_depth_bias ∈ [-0.5,+0.5]). Kept UNDER one rung (0.9·bias → ±0.45
## rung around RP_UNIT_BODY=5) so a front body lifts toward the camera OVER a back body yet never crosses
## into the shadow rung (4) below or the orb rung (6) above — the OPAQUE body writes real DEPTH, so this
## reversed-Z lift IS the occlusion. Front-over-back exactly as the oracle ring (front-bottom draws last).
const CHANGEJOB_DEPTH_SPREAD := 0.9
# --- Bottom "band" backdrop (§14.6.6) ----------------------------------------
# The dark, top/bottom-faded band the vitals + info panels sit on. It is iter 2 of
# FUN_80112c88 (@0x80112c88 — the SISTER of the top sort-tab header backdrop): a
# full-width 256px UNTEXTURED gouraud region drawn ABR mode 2 (SUBTRACTIVE) over the
# cobble floor. NOT the panel-local flat 55%-black quad the reused UIUnitInfoWindow
# ships (that is disabled here via show_band=false and kept only for the battle HUD).
#
# ORACLE (byte-exact, no BP): the built POLY_G4 packet in the settled-roster RAM dump
# @0x801C02A8 — rect x=128(centre)/w=256/y=178/h=50, base_rgb (120,120,120); the top
# feather strips (y169..177) ramp the subtracted grey 12->108, the bottom feather
# (y228..236) ramp it 108->12. So the fg (grey subtracted from the floor) profiles
# 0 -> 120 -> hold 120 -> 0 down the band. Floor(grey-80) - 120 = clamp 0 = the pure-
# black core the oracle framebuffer shows. (The TOP band @0x801C0030 exists too but
# its fg is 0 everywhere -> invisible in this settled state, so only ONE band draws.)
const BAND_X0 := 0.0                    # full-width: screen x 0..256 (w=256, x=128 centre)
const BAND_X1 := 256.0
const BAND_TOP_OUT := 168.0             # fg 0 here; strip0 @y169 = 12/255 (fades IN)
const BAND_TOP_IN := 178.0             # body top: full fg 120
const BAND_BOT_IN := 228.0             # body bottom: full fg 120
const BAND_BOT_OUT := 237.0             # fg 0 here; strip8 @y236 = 12/255 (fades OUT)
const BAND_FULL_SUB := 120.0 / 255.0   # oracle base_rgb 120 = the subtracted grey
# NOTE: no floor-reference constant. The band re-samples the REAL per-pixel cobble (the same
# formation_background computation) and subtracts fg from THAT, so there is no guessed floor
# level to tune — the subtract is faithful clamp(cobble - fg, 0) per pixel (§14.6.6).

## The subtractive grey (fg/255) at screen `y` — the ROM's vertical gouraud profile
## (a trapezoid: 0 at the outer edges, full 120/255 across the body). This is the
## SINGLE SOURCE OF TRUTH: the band mesh bakes it into per-vertex COLOUR and the guard
## (FormationBandTest) checks it against the oracle strip values. Reproduces the packet
## law exactly: band_subtract_at(169)=12/255, (177)=108/255, (178..228)=120/255.
static func band_subtract_at(y: float) -> float:
	if y <= BAND_TOP_OUT or y >= BAND_BOT_OUT:
		return 0.0
	if y < BAND_TOP_IN:
		return BAND_FULL_SUB * (y - BAND_TOP_OUT) / (BAND_TOP_IN - BAND_TOP_OUT)
	if y <= BAND_BOT_IN:
		return BAND_FULL_SUB
	return BAND_FULL_SUB * (BAND_BOT_OUT - y) / (BAND_BOT_OUT - BAND_BOT_IN)

# --- Sort column + header chrome (#174, §12.3.1) -----------------------------
# The FIVE sort keys the top tabs page between — RE-DERIVED FROM THE LIVE ORACLE
# (§12.3.5, sstate R2-walk 2026-08-03): the header shows six label GLYPHS
# (Hp Mp Ct Lv. Exp. Br.Fa) but they page as FIVE keys, because Lv.+Exp. share ONE
# tab (each cell reads "Lv.99 Exp.05") exactly as Br.+Fa. share one ("Br.70 Fa.70").
# The active key drives which value every cell shows. Paging does NOT re-order the
# grid — it only swaps the displayed stat column (user-confirmed + oracle A/B).
const SORT_KEYS := ["hp", "mp", "ct", "lv_exp", "brave_faith"]
# Which header LABEL-GLYPH indices highlight for each key (the six glyphs Hp/Mp/Ct/
# Lv./Exp./Br.Fa map to five keys — the combined keys light TWO glyphs). Header order
# from RangeTileAtlas.header_labels(): 0 Hp, 1 Mp, 2 Ct, 3 Lv., 4 Exp., 5 Br(+Fa).
const SORT_KEY_LABEL_INDICES := {
	"hp": [0], "mp": [1], "ct": [2], "lv_exp": [3, 4], "brave_faith": [5],
}

# The sort-tab HEADER (§12.3.2, RE-DERIVED from the VRAM oracle): the labels +
# ◄L2/R2► buttons are TEXTURED RANGETILE atlas cells (VRAM 960,256) through the
# REAL VRAM CLUTs (0x7c3c inactive / 0x7cbc active / 0x7d7c button) — NOT flat
# quads or proportional font. Label cells + positions + button cells + CLUTs all
# come from the ROM-extracted RANGETILE manifest (parse_range_tiles sort_header);
# the scene just places them. See RangeTileAtlas.header_*().

# Header chrome. The tan sort-bar window is NOT a flat colour — it is the FFT
# menu-window 9-slice (FRAME.BIN → frame.tga, the SAME UIFrame the vitals/info
# panels use), PROVEN from the VRAM oracle: the live tan-bar prims sample tpage
# 0x0019 (VRAM 576,256 == frame.tga) through CLUT 0x7C3C — dark border, bright top
# bevel, dithered tan fill, dark drop-shadow (§12.3.3). There is no separate
# active-tab box either: the "dark box" behind the white "Hp" is the label cell's
# OWN index-4 fill field, painted tan by the inactive CLUT (0x7C3C, blends into the
# bar) and near-black by the active CLUT (0x7CBC, ink flips dark→white in the same
# swap). So both the tan-fill/bevel colours and the box are carried by the texture
# + CLUT, not hand-picked quads — and the "Br.Fa" period is a real atlas glyph too.

# The HUD digit font (FRAMEFONT) + RANGETILE labels render through this shared
# index/CLUT sprite shader — the SAME one the reused vitals window draws its
# HP/MP/CT digits with (headful-verified #175), so grid and panel read identically.
const _VITALS_SPRITE_SHADER := "res://src/ui3/shaders/vitals_sprite.gdshader"
# Opaque depth-writing glyph variant for BOTH the per-cell sort-value readout AND the sort-tab header
# labels/buttons, mounted at real Z (rung = its RP_* value) so a folded prim beneath (the gold box under
# a sort value) is occluded behind the text, and so coincident header caption pieces stack by camera-Z
# instead of render_priority (ADR-0077 — vitals_sprite is now plain opaque, so "always on top" is gone;
# header glyphs at z=0 would z-fight the floor, hence they use this real-Z path).
const _TEXT_OPAQUE_SHADER := "res://src/ui3/shaders/formation_text_opaque.gdshader"
# The per-cell HP/MP/CT fill swatch (§12.3) reuses the SAME gouraud fill shader the
# vitals panel bar draws — masked to the shared RANGETILE swatch interior (216,202,38,6),
# opaque + depth-writing (ADR-0077, no ALPHA). The grid draws the FILL ONLY: no dim
# casing/track behind it (ROM: the sort-value emitter @0x80118244 emits a single fixed
# 37×3 textured swatch keyed to the active sort column's CLUT — no separate frame prim,
# no HP-proportional length; the old doc's monster "f(HP%4)" was a misread CLUT selector).
const _VITALS_BAR_SHADER := "res://src/ui3/shaders/vitals_bar.gdshader"
# Shared HP/MP/CT bar gouraud endpoints (dark LEFT x=0 → bright RIGHT x=1), byte-identical
# to UIUnitInfoWindow.bar_grad_* (the ROM's own POLY_G4 vertex colours, draw_vitals_bars
# @0x801352BC). The grid swatch is CLUT-keyed to the active sort column, so the port colours
# it by the active key's stat gradient. Oracle-confirmed: a full-HP roster cell's HP swatch
# ramps (72,104,120)→(168,184,112), matching stat 0 here to the byte.
const BAR_GRAD_LEFT := [Color8(72, 104, 120), Color8(128, 64, 56), Color8(80, 104, 64)]
const BAR_GRAD_RIGHT := [Color8(168, 184, 112), Color8(224, 160, 80), Color8(176, 176, 64)]
# Which sort keys draw a fill swatch, and which stat gradient/CLUT colours it. ROM: the
# sort-value emitter reads a 0..2 sort-column selector (Hp/Mp/Ct); Lv/Exp/Br.Fa draw none.
const SORT_BAR_STAT := {"hp": 0, "mp": 1, "ct": 2}
# L2/R2 pressed-button flash (§12.3.5): px the tapped button drops, and how many
# displayed frames the pressed look holds before it clears (a brief tap, not a latch).
const HEADER_BTN_PRESSED_DY := 1.0
const HEADER_BTN_PRESSED_FRAMES := 6
# The shared 3x3 RANGETILE period glyph (§12.3.3 "Br.Fa" dot cell), appended after the
# "Br"/"Fa" duo labels so they read "Br."/"Fa." like the oracle (Lv./Exp. bake their own).
const CELL_PERIOD_GLYPH := Rect2(59, 21, 3, 3)
# The vitals_bar shader masks the gouraud fill to the swatch INTERIOR (index 3), which
# is inset (4,1) px from the 38×6 swatch cell's top-left (same as UIUnitInfoWindow's
# bar_track_offset). So a fill quad placed at `interior_top_left − this` lands its band
# exactly at `interior_top_left`.
const BAR_INTERIOR_INSET := Vector2(4.0, 1.0)

# Selected-unit floor SPOTLIGHT (§14.6.3): an oval light pool centred on the cursor
# unit's floor-contact point (spotlight_center_px), sliding as the selection moves —
# this REPLACES the port's first-shipped static vertical ramp (which was wrong on
# both axes). Same falloff as the orb: base − swing·sqrt(dx² + vfac·dy²), vfac = 4 ⇒
# a 2:1 horizontally-elongated pool. base/swing/min are ORACLE-GROUNDED against the
# live PSX floor (SOLVED 2026-07-18): §16 line 651 — the floor gouraud runs base
# `0xFF` (255) / floor `0x50` (80), applied as `texture × gouraud/128`, so the
# multiplier is [0x50/128, 0xFF/128] = [0.625, ~2.0]. The floor is a *brightening
# light pool* (up to ~2× near the selected unit), NOT the darken-only vignette the
# port first shipped (base 1.0 → the whole floor read ~2× too dark vs the oracle).
# base/swing/min below are a least-squares fit of `clamp(base − swing·dist, min,
# base)` to the PSX framebuffer's radial floor profile (peak ~1.46× at the pool
# edge, plateau 0.64 far; rmse 0.054) — min lands on 0x50/128 = 0.625 exactly.
# Live-tunable via F3. See FormationFloorSpotlightTest for the shape guard.
@export var floor_spot_base := 1.72       # centre multiplier — the pool BRIGHTENS (gouraud 0xFF/128 ≈ 2×)
@export var floor_spot_swing := 0.0068    # brightness units lost per px of oval distance (fit to oracle)
@export var floor_spot_min := 0.64        # far floor clamps here ≈ 0x50/128 = 0.625 (PSX gouraud floor)
@export var floor_spot_vfac := 4.0        # the oval's HORIZONTAL:VERTICAL shape (vertical falloff
										  # weight): 4 ⇒ 2:1 wide (light reaches 2× as far across
										  # the floor as up/down), 1 ⇒ a round pool, >4 ⇒ flatter/
										  # wider. `swing` sets the pool SIZE, `vfac` its aspect.
# Draw the placeholder cell outlines (skeleton scaffolding — off now cells fill).
@export var show_cell_outlines := false
# DEBUG (box emboss parity isolation): 0=composed emboss (ship this),
# 1=additive pass only, 2=subtractive pass only.
@export var box_pass_mode := 0

## The cursor cell — its orb pulses and it alone gets the gold box (§10/§11).
@export var selected_cell := Vector2i(0, 0)

## DEBUG (placement calibration): render ONLY the unit bodies — no orb / box /
## shadow / HP / vitals — so the sprite's visible extent can be measured against
## the oracle without confounding elements. Off for shipping.
@export var debug_bodies_only := false

# Headful-tuned placement/scale (the unit body shader's screen-space scale +
# the exact orb/box offsets are calibrated against t04.png, not byte-derived).
# The unit shader maps a sprite tile through the FULL atlas height (488 px) into
# the [0,1] quad. ~19.5 would be native 1:1, but the roster draws the bodies at
# roughly ⅗ that (matched to t04.png; each unit ≈ 24×40 straddling the cell top).
# Body: FIXED uniform `body_scale` (ROM draws every roster mini at one common
# scale — normalizing per-unit visible height would flatten real job height
# differences), with per-unit CENTERING derived from the composited frame's
# visible bbox so each unit's visible centre lands at the ROM body centre
# (cellX+31, cellY+24) — killing the per-job feet scatter (§7). body_scale is
# calibrated headful vs t04.png (~9 ⇒ visible height matches the oracle mini).
# body_offset_px is only the fallback when the frame's bbox can't be read.
@export var body_scale := 9.0                       # fixed holder scale (headful-tuned)
@export var body_offset_px := Vector2(28.0, 30.0)   # fallback cell-relative centre
# Cell-relative standing point the visible feet land on (X = ROM body centre,
# Y = common baseline). Defaults to the ROM/derived values; live-tunable via the
# F3 Formation panel. See BODY_ANCHOR_DX / FEET_BASELINE_DY for the derivation.
@export var feet_target_px := Vector2(BODY_ANCHOR_DX, FEET_BASELINE_DY)
@export var orb_offset_px := Vector2(0.0, 0.0)       # cell-relative orb top-left
@export var orb_falloff_scale := 0.20                # brightness units / px
@export var box_center_px := Vector2(28.0, 36.0)     # cell-relative box centre (feet; +2 vs t04 box)
# Gold-box GOURAUD debug scale (default 1.0 = FAITHFUL). RE of the box builder
# FUN_8011712c (WORLD.BIN; FORMATION_ORB_ADDITIVE_COLORSPACE.md) proved the box prim
# gouraud IS the per-slot trail-fade table {20,35,50,65,80,90,100,128} written verbatim
# to r0/g0/b0 — head slot = 0x80 = 128 = FULL, identical for the add and sub passes. So
# the faithful box level is just `trail_fade` (head = 128/128 = 1.0), no sub-full base
# constant. These knobs stay at 1.0 (a debug multiplier only); the on-screen "dim gold"
# is the PALETTE (dim idx7-8 texels) + the DARK floor under the box (unit shadow), NOT a
# gouraud < 1. Add/sub separate; box_emboss_dy = sub-pass Y drop.
@export var box_add_level := 1.0     # additive gouraud debug scale (1.0 = faithful full)
@export var box_sub_level := 1.0     # subtractive gouraud debug scale (1.0 = faithful full)
@export var box_emboss_dy := 1.0     # sub-pass Y offset below the add pass (px)
# Per-unit drop shadow (§12, FUN_8011814c feet decal). VRAM-VERIFIED: the roster shadow
# samples the SAME 20x20 round radial blob as the battle/map unit shadow (VRAM page
# (960,256), UV (144,64), tpage 0x5F subtractive) — see unit_shadow.png / §12.3. It is
# drawn into a 20×10 on-screen rect (a 2:1 vertical squash of the 20×20 texel) at the
# feet; the body sprite (bucket 6) occludes the blob's top so it reads as the bottom
# crescent. Placed RELATIVE TO THE FEET (like the ROM: shadow = body-rect-relative):
# shadow CENTRE = feet_target_px + shadow_feet_offset_px. Default offset is the ROM
# rom_shadow_rect centre relative to the feet baseline ((29,39) − (31,40) = (−2,−1));
# live-tunable via the F3 Formation panel.
@export var shadow_feet_offset_px := Vector2(-2.0, -4.0)  # shadow centre rel. to feet (headful-tuned up)
@export var shadow_size_px := Vector2(20.0, 10.0)         # ROM 20×10 (2:1 squash)
# Full raw-texel subtraction, IDENTICAL to the normal-scene shadow (Unit.tscn shadow_blob
# intensity=1.0). The oracle roster shadow is pure-black-on-dark-floor = full subtraction;
# it is the same PSX primitive, so it must not be weakened. Kept as a knob only because
# shadow_blob exposes the same one (per-unit tuning), NOT to fudge the roster look.
@export var shadow_intensity := 1.0
# Bottom-left vitals panel origin. ORACLE-NAILED against the live PSX formation VRAM
# 256×240 top buffer (formation_screen_load_from_worldmap.sstate, 2026-08-02): the panel
# elements land on FORMATION_SCREEN.md §14.6's coords — Hp label x45, HP-fill x57, cur
# digits x91; bar rows y200/211/222; Lv y181 — centred vertically in the subtractive band
# (y168–237). The earlier (12,140) was a port GUESS that floated the panel ~37px too high
# (portrait swallowed by the band's black core). Alignment is done at UI PAR = 1 (square,
# `PSXDisplay.live_ui_par`), so this is a single uniform anchor — no per-element fudge.
@export var vitals_origin_px := Vector2(13.0, 177.0)

# --- RIGHT unit-info panel (#176 / §14.6) ------------------------------------
# The tan 9-slice window to the RIGHT of the vitals panel: a blue orb bullet +
# unit number + name / job (proportional FONT.BIN) + a zodiac glyph (RANGETILE
# §14.3) + Brave/Faith label+value. ORACLE-MEASURED against the live PSX 256×240
# top buffer (formation_screen_load_from_worldmap.sstate, 2026-08-02): the frame
# outer rect is (134,176)→(248,230); text tops are §14.6's absolute coords. All
# placement is at UI PAR = 1 (square), like the vitals panel + header.
@export var info_origin_px := Vector2(134.0, 176.0)      # tan frame top-left
@export var info_frame_size_px := Vector2(114.0, 54.0)   # frame w×h (outer)
@export var info_bullet_px := Vector2(136.0, 179.0)      # orb bullet top-left (12×12) → glow x[137,146] y[180,189] = oracle
@export var info_number_px := Vector2(147.0, 183.0)      # unit-number ("01")
@export var info_name_px := Vector2(158.0, 183.0)        # name ("Ramza")
@export var info_job_px := Vector2(158.0, 199.0)         # job ("Squire")
@export var info_zodiac_px := Vector2(139.0, 205.0)      # zodiac glyph top-left (~20×20)
@export var info_brave_label_px := Vector2(162.0, 216.0)
@export var info_brave_value_px := Vector2(188.0, 216.0)
@export var info_faith_label_px := Vector2(205.0, 216.0)
@export var info_faith_value_px := Vector2(227.0, 216.0)

# --- Sort column + header chrome (#174) --------------------------------------
# Which sort key the whole screen reflects. t04.png is HP-sorted; changing this
# re-labels the highlighted tab and every cell's readout. The boot default; L2/R2 page
# it live (§12.3.5) via page_sort()/set_sort_key() — the capture probe drives it too.
@export var active_sort_key := "hp"
# Per-cell readout placement (cell-relative px). The value is the ROM HUD digit
# font "cur/max" pair (§12.3 value ≈ cellX+9, cellY+40) with a word label to its
# left; exact glyph placement is byte-approximate and headful-tuned vs t04.png.
@export var sort_label_offset_px := Vector2(2.0, 40.0)   # word-label top-left
@export var sort_value_divider_px := Vector2(35.0, 39.0) # cur right-aligned to x, at y (top row, aligned with the Hp label)
@export var sort_value_scale := 1.0                      # HUD-digit size multiplier
# The "duo" readout (Lv.Exp / Br.Fa, §12.3.5): two labelled 2-digit values side by
# side ("Lv.99 Exp.05"). Each group = word-label then its number `sort_duo_value_gap`
# px past the label's right edge; the right group starts at `sort_duo_split_px`. The
# right group is STAGGERED down by `sort_duo_stagger_dy` (the oracle drops the second
# value down-right, mirroring the pair cur/max stagger — §12.3.5). Headful-tuned vs
# the sstate oracle (formation_screen_load_from_worldmap: Br top y77 → Fa top y82 = +5).
@export var sort_duo_value_gap_px := 1.0                 # px from a label's right edge to its number
@export var sort_duo_split_px := 30.0                    # cell-x of the RIGHT (second) label
@export var sort_duo_stagger_dy := 5.0                   # px the RIGHT group drops (down-right stagger)
@export var sort_duo_dot_space_px := 2.0                 # extra space after the "Br."/"Fa." dot (oracle "Br. 70")
# The per-cell HP/MP/CT fill swatch (§12.3): a fill-only gouraud band (no casing),
# cell-relative INTERIOR top-left. ORACLE-measured (formation_screen_load_from_worldmap):
# the HP swatch's dark endpoint aligns L with the "Hp" label (x = label x) and its 3px
# band sits 8px below the label top — a full 32px-visible ramp under the readout.
@export var sort_bar_pos_px := Vector2(5.0, 49.0)        # fill interior top-left (cell-relative; aligns L with the Hp label, band 8px below its top)
# Sort-tab header window geometry (absolute virtual px, measured from the settled
# roster oracle — §12.3.1). The header is three menu windows on the stone floor:
# a central TAN bar holding the six sort labels, flanked by two blue-grey L2/R2
# buttons. Live-tunable via F3 for the headful A/B vs t04.png.
@export var header_bar_top_px := 15.0       # top y of the whole header band
@export var header_bar_height_px := 13.0    # band height (y ≈ 15–28)
@export var header_label_y_px := 18.0       # glyph-top of the sort labels (live-prim y)
@export var header_tan_rect_px := Vector4(64.0, 14.0, 128.0, 16.0)  # x,y,w,h tan-bar window (live-prim exact: x64→192, y14→30)
# ◄L2/R2► buttons are textured atlas cells placed from the manifest (origin_x
# 38/194) — no rect tunables (see _add_textured_button / RangeTileAtlas.header_buttons).

var _cells := {}                        # Vector2i(col,row) -> Node3D anchor
var _cell_content := []                 # kept refs (SpriteLayerManagers) so the
										# RefCounted/Node helpers aren't freed
var _bg_mat: ShaderMaterial             # background material (floor spotlight uniforms live here)
var _band_mat: ShaderMaterial           # band backdrop material (re-samples the same floor -> spot uniforms mirrored here)
var _cell_readouts_visible := true       # per-cell HP/MP/CT readout ("SortVal") visibility — hidden under the detail overlay
var _orb_phase := 0.0
var _orb_dir := 1.0
var _orb_accum := 0.0                    # fractional displayed-frames owed (time-driven pulse)
var _orb_hold := 0                        # extra frames to hold at an endpoint (§10.2: 2f each)
var _cluster: UnitInfoCluster            # the shared vitals+nameplate pair (docked; slides on ○-press)
var _vitals_window: UIUnitInfoWindow    # == _cluster.vitals_panel() (bottom-left; kept for debug panel + refs)
var _info_root: Node3D                   # == _cluster.nameplate() (RIGHT unit-info panel #176)
var _tunables_bound := false            # gate: suppress per-bind rebuild during boot

# --- Sort column + header text assets (#174), built once and shared per cell --
var _digit_font: NumberFont             # HUD cur/max digits (FRAMEFONT)
var _rt_atlas: RangeTileAtlas           # word labels ("Hp"/"Mp"/…) from RANGETILE
var _digit_pal: ImageTexture            # the shared 16-colour MENU CLUT (as a row)
var _header_ink_pal: ImageTexture       # header labels: real inactive_label CLUT (0x7c3c)
var _header_hilite_pal: ImageTexture    # header labels: real active_label CLUT (0x7cbc, active tab)
var _header_btn_pal: ImageTexture       # ◄L2/R2► textured button cells: real button CLUT (0x7d7c)
var _header_pressed_pal: ImageTexture   # ◄L2/R2► PRESSED cells: real button_pressed CLUT (0x7e7c, warm tan)
# §15.21 "send window to background": the per-CLUT BACKGROUND palettes the header samples when a menu
# (e.g. the detail overlay) takes focus. Same per-index swap as DetailScene — 0x7c3c→0x7d3c (labels),
# 0x7cbc→0x7c7c (active tab), 0x7d7c→0x7dfc (L2/R2 caption). `_header_mats` collects every header
# ShaderMaterial (glyphs + frame) so set_backgrounded flips them uniformly + a sort-rebuild re-applies.
var _header_ink_pal_bg: ImageTexture
var _header_hilite_pal_bg: ImageTexture
var _header_btn_pal_bg: ImageTexture
var _header_backgrounded := false
var _header_visible := true             # sort-header (bar + L2/R2) shown; hidden under the detail overlay (§15.22)
var _header_mats: Array[ShaderMaterial] = []
var _header_root: Node3D                # persistent header chrome (rebuilt on its own)
# Live L2/R2 sort paging (§12.3.5). `_pressed_side` = "left"/"right"/"" — the button
# flashing its pressed look; `_pressed_frames` counts it down (in _process) to a clear.
var _pressed_side := ""
var _pressed_frames := 0

# --- Cursor glide / trail / sweep state (§11.5 / §16.1) ----------------------
var _box_target := Vector2.ZERO         # box centre the glide eases toward (abs px)
var _box_glide := Vector2.ZERO          # eased box centre (abs px, integer-valued)
var _box_history: Array = []            # TRAIL_LEN past glide positions; slot7 = newest
var _glide_accum := 0.0                 # fractional 60 Hz glide ticks owed
var _trail_root: Node3D                 # persistent 8-box trail root (NOT rebuilt on move)
var _trail_slots: Array = []            # [{holder:Node3D, quads:[{mat,is_add}]}] per slot
var _orb_mats_by_cell := {}             # Vector2i -> [orb mats]  (brightness swept per frame)
var _orb_holders_by_cell := {}          # Vector2i -> orb holder Node3D (toggled by set_orbs_visible)
var _orbs_visible := true                # latched: the Equip screen hides the grid orbs (§15.23 RE24)
var _box_trail_visible := true           # latched: the Equip screen hides the gold box VISUAL (glide math stays live)
var _body_mats_by_cell := {}            # Vector2i -> body ShaderMaterial (ambient swept per frame)
var _body_bbox_by_cell := {}            # Vector2i -> the composited frame's visible bbox in LOC space
var _body_holders_by_cell := {}         # Vector2i -> body holder Node3D (a scene-ROOT sibling of the anchor,
                                        #   NOT a child — carries the sprite scale; the Equip slide moves it
                                        #   in lockstep with the anchor so the unit BODY tracks the slide)
var _populated := {}                    # Vector2i -> true for cells that hold a unit (nav bounds)
var _trail_ramp: Array = TRAIL_RAMP_FALLBACK.duplicate()   # ROM box-trail fade (§11.5.3), loaded at boot


## Load the ROM-parsed formation data tables (ADR-0046) — currently the box-trail fade
## ramp (§11.5.3). Mirrors GloveCursorBob.gd: FileAccess + a file_exists guard, and every field
## validated, so an isolated boot with no generated assets falls back to TRAIL_RAMP_FALLBACK
## instead of erroring. Regenerate the JSON with tools/parse_formation_tables.py.
func _load_rom_tables() -> void:
	if not FileAccess.file_exists(_TABLES_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_TABLES_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var fade: Variant = parsed.get("box_trail_fade")
	if typeof(fade) != TYPE_DICTIONARY:
		return
	var ramp: Variant = fade.get("ramp")
	if typeof(ramp) != TYPE_ARRAY or ramp.size() != TRAIL_LEN:
		return
	var out: Array = []
	for v in ramp:
		out.append(float(v))
	_trail_ramp = out


# -----------------------------------------------------------------------------
# The two HOSTS (ADR-0137). This scene is the ROSTER host — the Formation screen standing on
# its own, with its own orthographic camera, the stone floor behind it and the 4x2 grid
# answering "who is selected". The MAP host (FormationMapHost) is the SAME screen re-hosted
# over the live battlefield: mounted under the map's camera, the map itself behind it, and the
# tile cursor answering the selection question.
#
# The two predicates below are the whole seam. Everything else on this class — the band, the
# unit-info cluster, the body/shadow builders, screen_to_world, the Change-Job wheel — is
# screen-common and the map host inherits it unchanged. Deliberately predicates rather than a
# copied class: the failure mode ADR-0137 names is a SECOND copy of this screen.
# -----------------------------------------------------------------------------

## True when this host paints the formation screen's OWN backdrop — the cobble floor quad and the
## gray pillarbox bars. The roster host does. The map host does NOT: the battlefield IS its
## background (ADR-0137), so a cobble quad would hide the very thing it re-hosts over, and a
## pillarbox bar would mask the map rather than off-rect UI.
##
## The subtractive BAND is NOT part of this — it is screen-common and both hosts build it.
## `formation_band_fold.gdshader` is background-agnostic (`ALBEDO = vec3(sub)`), so over the map
## it subtracts from the map, verified headful.
func paints_own_backdrop() -> bool:
	return true


## True when this host owns the 4x2 roster GRID — the cells, their per-unit readouts, the blue
## orbs, the gold selection-box trail and the sort header. Everything that answers "who is
## selected" BY CELL hangs off this.
##
## The map host answers that question with the tile cursor instead, so every grid-shaped
## obligation degenerates to a no-op there: the chrome setters find nothing to hide, and the
## equip-slide cluster has no rows to split (the unit reaches the breakout mark by CAMERA PAN,
## not by sliding). Those degenerate naturally — they iterate empty collections — so this
## predicate gates only the BUILD.
func owns_roster_grid() -> bool:
	return true


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_load_rom_tables()            # box-trail fade ramp from WORLD.BIN (ADR-0046)
	# Seed the glide at the selected cell so the box/floor start settled (no boot glide).
	_box_glide = cell_box_centre(selected_cell)
	_box_target = _box_glide
	_box_history.clear()
	for _i in TRAIL_LEN:
		_box_history.append(_box_glide)
	_build_background()
	if owns_roster_grid():
		_build_grid()
		_populate_cells()
		_build_box_trail()        # persistent — glides/rebuilds independently of the cells
	if not debug_bodies_only:
		_build_unit_info_cluster()  # the shared vitals + RIGHT info (#176) pair, DOCKED —
		                            # screen-common: on the MAP host this same pair is what a
		                            # cursor HOVER slides in (ADR-0137).
		if owns_roster_grid():
			_build_sort_header()  # persistent — top-of-screen chrome, rebuilt on its own
	# ADR-0077: the add/sub prims join the ENGINE fold (compositor_layer + Fold.add), which the
	# CompositorAutopilot autoload attaches to the camera every scene. No cam.compositor here — the
	# retired FormationDisplaySpaceComposite used to clobber it, fighting the autopilot (the vanish bug).
	_bind_tunables()


## Bind the placement knobs to their `formation.*` Tune slugs (ADR-0068). This scene
## OWNS its placement, so a committed override coalesces into the @export at boot AND
## a scrub re-drives the cells (the apply writes the prop + rebuilds), and the slugs
## show in the generated Tunables dashboard — the FormationDebugPanel is just a view
## (decision 12). Vector2 knobs split into _x/_y float slugs. @tool-guarded: Tune.gd
## is not @tool (placeholder in-editor), so skip binding there.
func _bind_tunables() -> void:
	if Engine.is_editor_hint():
		return
	_tb_scalar("body_scale")
	_tb_scalar("shadow_intensity")
	_tb_vec2("feet_target_px")
	_tb_vec2("shadow_feet_offset_px")
	_tb_vec2("shadow_size_px")
	# Box knobs feed the persistent trail, NOT a cell rebuild: box_center_px shifts the
	# glide TARGET (read per-tick) and box_add/sub_level are re-applied per-tick, so they
	# need no rebuild; box_emboss_dy is baked into the quad geometry, so it rebuilds the
	# trail. (box_center_px stays a plain vec2 bind — its rebuild_cells is harmless; the
	# glide target is recomputed every tick, so the box still slides to the new offset.)
	_tb_vec2("box_center_px")
	_tb_scalar("box_add_level")
	_tb_scalar("box_sub_level")
	_tb_trail("box_emboss_dy")
	# Floor spotlight — apply is a bg-material uniform write, NOT a cell rebuild.
	_tb_floor_spot("floor_spot_base")
	_tb_floor_spot("floor_spot_swing")
	_tb_floor_spot("floor_spot_min")
	_tb_floor_spot("floor_spot_vfac")
	# Unit/orb dim: how fast a sprite darkens with distance from the selection (§16
	# body falloff). Rebuilds the cells (bodies/orbs bake their level at build time).
	_tb_scalar("orb_falloff_scale")
	# Sort-column readout: cell-relative placement of the per-cell "Hp cur/max"
	# block. These live inside the cells, so a scrub rebuilds the cells.
	_tb_vec2("sort_label_offset_px")
	_tb_vec2("sort_value_divider_px")
	_tb_scalar("sort_value_scale")
	_tb_scalar("sort_duo_stagger_dy")
	_tb_scalar("sort_duo_dot_space_px")
	# Sort-tab header chrome: a scrub rebuilds the header (not the cells).
	_tb_header("header_label_y_px")
	_tb_header("header_bar_top_px")
	_tb_header("header_bar_height_px")
	_tb_header_vec4("header_tan_rect_px")
	# Every bind's apply fired once during registration (setting the coalesced value
	# but skipping the rebuild via the guard); now do ONE rebuild that reflects any
	# committed overrides, and let subsequent scrubs rebuild per-edit.
	_tunables_bound = true
	rebuild_cells()


## Bind a scalar @export prop to `formation.<prop>`; apply writes it + rebuilds.
func _tb_scalar(prop: String) -> void:
	TunePort.bind_update(self, "formation." + prop, get(prop), func(v: Variant) -> void:
		set(prop, v); _rebuild_if_bound())


## Bind a box-geometry scalar @export to `formation.<prop>`; apply writes it + rebuilds
## the persistent box trail (the change alters the box quad geometry, not the cells).
func _tb_trail(prop: String) -> void:
	TunePort.bind_update(self, "formation." + prop, get(prop), func(v: Variant) -> void:
		set(prop, v)
		if _tunables_bound:
			_build_box_trail())


## Bind a floor-spotlight scalar @export to `formation.<prop>`; apply writes the prop
## and re-pushes the bg-material uniforms (a cheap uniform write, not a cell rebuild).
func _tb_floor_spot(prop: String) -> void:
	TunePort.bind_update(self, "formation." + prop, get(prop), func(v: Variant) -> void:
		set(prop, v); _apply_floor_spotlight())


## Bind a sort-tab-header scalar @export to `formation.<prop>`; apply writes it +
## rebuilds the header chrome (the header is persistent, not part of the cells).
func _tb_header(prop: String) -> void:
	TunePort.bind_update(self, "formation." + prop, get(prop), func(v: Variant) -> void:
		set(prop, v)
		if _tunables_bound:
			_build_sort_header())


## Vector4 (x,y,w,h rect) variant of [method _tb_header] — one float slug per
## component, each rebuilding the header chrome.
func _tb_header_vec4(prop: String) -> void:
	var base: Vector4 = get(prop)
	var names := ["x", "y", "z", "w"]
	for i in 4:
		var comp := i
		TunePort.bind_update(self, "formation.%s_%s" % [prop, names[comp]], base[comp],
			func(v: float) -> void:
				var r: Vector4 = get(prop)
				r[comp] = v
				set(prop, r)
				if _tunables_bound:
					_build_sort_header())


## Bind a Vector2 @export prop to `formation.<prop>_x` / `_y` float slugs.
func _tb_vec2(prop: String) -> void:
	var base: Vector2 = get(prop)
	TunePort.bind_update(self, "formation.%s_x" % prop, base.x, func(v: float) -> void:
		set(prop, Vector2(v, (get(prop) as Vector2).y)); _rebuild_if_bound())
	TunePort.bind_update(self, "formation.%s_y" % prop, base.y, func(v: float) -> void:
		set(prop, Vector2((get(prop) as Vector2).x, v)); _rebuild_if_bound())


## Rebuild the cells only once the initial bind sweep is done — during registration
## each bind's apply fires (with the coalesced value) before the cells should churn;
## _bind_tunables does the single post-bind rebuild.
func _rebuild_if_bound() -> void:
	if _tunables_bound:
		rebuild_cells()


## Move the LOGICAL cursor to `cell` (SNAP, §16.1): the cell index jumps instantly,
## but the VISIBLE gold box + floor spotlight + swept orb/body brightness only ease
## toward it — driven in _process off the eased glide, NOT a rebuild. So this just
## sets the glide TARGET, repoints the pulsing orb, and refreshes the vitals panel;
## the box glides + leaves its trail, the floor pool slides, all in _process. The
## selection→visual hook for D-pad nav (#171): callers route input here.
## The roster [Character] under the logical cursor, or null when the cell is empty
## (out-of-range / no roster). The ○-press (`unit_activated`) and any host threading
## the detail views read the selected unit through here.
## The docked vitals+nameplate pair, or null before it is built. Screen-common — both hosts own one.
func unit_info_cluster() -> UnitInfoCluster:
	return _cluster if _cluster != null and is_instance_valid(_cluster) else null


## The band material's current subtract factor knob is write-only via [method set_band_fade]; this
## reports whether the band exists at all, which a host needs before parking it faded out.
func has_band() -> bool:
	return _band_mat != null


## WHO is selected. The roster host answers by CELL (the grid position the box sits on); the map
## host (ADR-0137) answers with the unit under the tile cursor. One of the two genuinely-real
## obligations of the host seam (the other is `screen_to_world`).
func selected_character():
	var units := _roster_characters()
	var index := selected_cell.y * COLS + selected_cell.x
	if index < 0 or index >= units.size():
		return null
	return units[index]


## Hide/show the docked vitals+nameplate pair. A ○-press host hides it the instant the
## detail overlay's sliding cluster appears at the SAME docked spot (§15.5), so the pair
## hands off seamlessly (one pair visible, not two) and the formation grid + band stay
## as the background the transition plays over.
func set_unit_info_visible(shown: bool) -> void:
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.visible = shown


## Fade the bottom "black gradient stripe" (§14.6.6): `factor` scales its subtract strength
## (1 = the oracle 120/255, 0 = invisible). The ○-press host drives this DOWN as the Status
## screen's top stripe fades UP (§15.6 — the ROM slides one band with the pair; the port
## cross-fades the roster's bottom band out and the detail top band in). No-op pre-band-build.
func set_band_fade(factor: float) -> void:
	if _band_mat != null:
		_band_mat.set_shader_parameter("full_sub", BAND_FULL_SUB * factor)


## Hide/show the per-cell HP/MP/CT readouts — the "Hp 031/031" digits + the fill swatch (the
## "SortVal" child of each cell). The ○-press host hides them while the Status/detail overlay is
## up (matching the ROM: the unit sprites STAY on the grid but their vitals readouts blank),
## then shows them again on close. Body/shadow/orb are untouched. Latched so a sort-page rebuild
## (rebuild_sort_values → _build_cell_sort_value) keeps them hidden.
func set_cell_readouts_visible(shown: bool) -> void:
	_cell_readouts_visible = shown
	for anchor in _cells.values():
		if anchor == null or not is_instance_valid(anchor):
			continue
		var sv: Node = anchor.get_node_or_null("SortVal")
		if sv != null:
			sv.visible = shown


## Hide/show the per-cell blue selection ORBS (§10). The Equip screen (§15.23 RE24) tears the
## grid down to the single selected unit — no orb near it in the oracle (prim scan: 0 orb prims).
## The ○-press → Item → Equip host hides them for the duration; restored on close. Latched so a
## sort-page rebuild keeps them hidden. Body/shadow are untouched (the unit sprite stays + slides).
func set_orbs_visible(shown: bool) -> void:
	_orbs_visible = shown
	for holder in _orb_holders_by_cell.values():
		if holder != null and is_instance_valid(holder):
			holder.visible = shown


## Hide/show the gold selection-box VISUAL (the persistent trail, §11.5). The Equip screen has no
## box near the settled unit (oracle prim scan: 0 box prims). This hides the MESH only — the box
## GLIDE math (`_box_glide`) stays live because it SOURCES the floor spotlight centre (§16), which
## tracks the unit during the Equip slide. Latched so a rebuild keeps it hidden. Restored on close.
func set_box_trail_visible(shown: bool) -> void:
	_box_trail_visible = shown
	if _trail_root != null and is_instance_valid(_trail_root):
		_trail_root.visible = shown


func set_selected_cell(cell: Vector2i) -> void:
	if cell == selected_cell:
		return
	selected_cell = cell
	_box_target = cell_box_centre(selected_cell)   # box + floor glide toward the new cell
	_update_vitals_for_selection()                 # panel follows the logical cursor (snap)


## D-pad nav (#171): unhandled input steps the logical cursor one cell per press,
## clamped to the grid + to occupied cells, and routes through set_selected_cell so
## the box/floor glide. (Isolated-boot with no roster falls back to grid-bounds nav.)
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	# Cancel (Backspace/✕) dismisses the view (wayfinder #234 E — the navigator yields on
	# `dismissed`). Confirm (Enter/○) on a roster unit opens its Status/detail screen
	# (§15.5): emit `unit_activated` so a host plays the transition. Enter on an empty
	# roster falls back to `dismissed` (the pre-detail behavior).
	if event.is_action_pressed("ui_cancel"):
		dismissed.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		var character = selected_character()
		if character != null:
			unit_activated.emit(character)
		else:
			dismissed.emit()
		get_viewport().set_input_as_handled()
		return
	# L2/R2 page the sort key (§12.3.5): R2 = next column (rightward), L2 = previous,
	# wrapping. Rebuilds every cell's readout + the tab highlight + flashes the button.
	if event.is_action_pressed("formation_sort_next"):
		page_sort(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("formation_sort_prev"):
		page_sort(-1)
		get_viewport().set_input_as_handled()
		return
	var dir := Vector2i.ZERO
	if event.is_action_pressed("ui_right"):
		dir = Vector2i(1, 0)
	elif event.is_action_pressed("ui_left"):
		dir = Vector2i(-1, 0)
	elif event.is_action_pressed("ui_down"):
		dir = Vector2i(0, 1)
	elif event.is_action_pressed("ui_up"):
		dir = Vector2i(0, -1)
	else:
		return
	# At the grid's bottom/top edge, a further vertical step scrolls the ROW window over
	# the full injected roster instead of moving the cursor (ADR-0081 all-templates view).
	if dir.y != 0 and _injected_characters != null and _try_scroll(dir.y):
		get_viewport().set_input_as_handled()
		return
	var target := next_cell(selected_cell, dir)
	if _cell_has_unit(target):
		set_selected_cell(target)
	get_viewport().set_input_as_handled()


## Scroll the row window by one row when the cursor is at the edge it's pushing against and
## there is more roster that way. Returns true if it scrolled (and rebuilt). ↓ at the bottom
## row advances; ↑ at the top row retreats; clamped at the list ends.
func _try_scroll(dir_y: int) -> bool:
	var count: int = (_injected_characters as Array).size()
	var scrolled := false
	if dir_y > 0 and selected_cell.y == ROWS - 1 and scroll_offset < max_scroll_offset(count):
		scroll_offset += 1
		scrolled = true
	elif dir_y < 0 and selected_cell.y == 0 and scroll_offset > 0:
		scroll_offset -= 1
		scrolled = true
	if scrolled:
		rebuild_cells()
		# The cursor stays put but a NEW unit slid under it — the cell index is
		# unchanged, so set_selected_cell would early-return; refresh the panels
		# (vitals + RIGHT info + portrait) directly for units[selected_cell].
		_update_vitals_for_selection()
	return scrolled


## One grid step, clamped to the 4×2 grid bounds. Pure so it unit-tests. (ROM
## FUN_8012bb88 is a clamp/wrap selector — clamp chosen here; wrap is a live-confirm
## follow-up, #171.)
static func next_cell(cell: Vector2i, dir: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x + dir.x, 0, COLS - 1), clampi(cell.y + dir.y, 0, ROWS - 1))


## Does `cell` hold a roster unit? (nav stops at the last occupied cell). When the
## roster is empty — e.g. an isolated scene boot — allow grid-bounds nav instead.
func _cell_has_unit(cell: Vector2i) -> bool:
	if _populated.is_empty():
		return true
	return _populated.has(cell)


## Page the sort column one step (§12.3.5): `dir` = +1 (R2/next) or -1 (L2/prev),
## wrapping. Swaps every cell's readout + the tab highlight (the grid does NOT
## re-order — only the displayed column changes) and flashes the tapped button.
func page_sort(dir: int) -> void:
	set_sort_key(next_sort_key(active_sort_key, dir), "right" if dir > 0 else "left")


## Set the active sort key and rebuild the cells + header (§12.3.5). `pressed_side`
## (""/"left"/"right") flashes that L2/R2 button for HEADER_BTN_PRESSED_FRAMES. The
## public seam the navigator, a live page, and the capture probe all drive.
func set_sort_key(key: String, pressed_side: String = "") -> void:
	if SORT_KEYS.find(key) < 0:
		return
	active_sort_key = key
	_pressed_side = pressed_side
	_pressed_frames = HEADER_BTN_PRESSED_FRAMES if pressed_side != "" else 0
	if is_inside_tree() and not Engine.is_editor_hint():
		# Only the readout column + header change per page — rebuild JUST those, NOT the
		# unit bodies (rebuild_sort_values, not rebuild_cells) so paging stays snappy (§12.3.5).
		rebuild_sort_values()
		_build_sort_header()


## Absolute virtual-px centre of a cell's gold box (the point the glide targets). Uses the
## cell's DOCKED grid origin — the fixed target the box glides toward on a selection change.
func cell_box_centre(cell: Vector2i) -> Vector2:
	return cell_origin_px(cell.x, cell.y) + box_center_px


## The LIVE box centre of a cell's unit — its CURRENT rendered anchor position + box_center_px,
## NOT the docked grid origin. On the roster grid the anchor sits at its docked origin so this
## equals cell_box_centre; during the Equip slide the anchor MOVES, so this tracks the unit. The
## element-brightness sweep (§16.1) samples the spotlight falloff HERE so a unit moving WITH the
## pool stays lit — the ROM samples orb_spatial_falloff at each element's LIVE screen position,
## one field shared by floor + elements; measuring a moving unit at its stale docked cell is the
## bug that darkened it mid-slide (the floor pool and the unit brightness were sampled off
## different references — live centre for the floor, static cell for the unit).
func live_cell_box_centre(cell: Vector2i) -> Vector2:
	return cell_anchor_screen_px(cell) + box_center_px


## World position of a virtual-screen pixel (top-left origin, +X right/-Y down).
func screen_to_world(px: float, py: float) -> Vector3:
	return Vector3(px * PIXELS_PER_UNIT, -py * PIXELS_PER_UNIT, 0.0)


## Top-left virtual-pixel anchor of a grid cell (§12.2). Static (constants only) so
## the glide/falloff helpers and guards can compute cell geometry without a scene.
static func cell_origin_px(col: int, row: int) -> Vector2:
	return Vector2(GRID_ORIGIN.x + col * COL_PITCH, GRID_ORIGIN.y + row * ROW_PITCH)


## The mount anchor Node3D for a cell — later tickets add child sprites here,
## positioned in virtual pixels relative to the cell's top-left via screen_to_world.
func get_cell(col: int, row: int) -> Node3D:
	return _cells.get(Vector2i(col, row))


# --- Item → Equip unit sprite-slide (FORMATION_SCREEN.md §15.23, RE round 22) ---
# The Equip transition (from the Status overlay) reveals the formation's unit rows and
# slides them: the selected unit settles at the measured screen (166,173), every other
# unit slides off the right edge (ease-in). Only anchor POSITION is touched — no scale
# (the oracle quads are 24×40 in all 30 frames). Driven frame-by-frame by a host
# _process via SpriteSlideAnimator; begin_equip_slide() latches the docked starts.

## X past which a sliding unit is fully off the 256-px screen (origin left edge).
const EQUIP_EXIT_X := 300.0

var _equip_slide_active := false
var _equip_starts := {}     # Vector2i cell -> Vector2 docked anchor screen origin
var _equip_targets := {}    # Vector2i cell -> Vector2 slide-end anchor screen origin
var _equip_body_offsets := {}  # Vector2i cell -> Vector3 (holder.position - anchor.position), the
                               #   constant world offset of the detached body holder from its anchor;
                               #   captured at begin so play_equip_slide moves the body with the anchor

## The floor SPOTLIGHT centre on the SETTLED Equip screen — measured off the ROM sampler centre
## `0x8018BAD0/BAD2` in tmp/equip_re/ram_dest.bin = (164,177) (§15.23 / §16, RE round 24). i.e. the
## pool sits essentially ON the settled unit (sprite draws at SETTLE_PX=(166,173)), NOT at the unit's
## old grid cell. During the Equip slide the pool must EASE here along the SAME path the unit slides.
const EQUIP_SPOTLIGHT_SETTLE := Vector2(164.0, 177.0)

# Equip-slide spotlight retarget (§16 coupling kept: the pool is driven by the box-glide source, but
# the glide is retargeted to the sliding unit for the duration of the Equip slide, then held there).
var _equip_spotlight_active := false
var _equip_glide_start := Vector2.ZERO   # _box_glide at slide begin (the selected cell's box centre)
var _equip_glide_target := Vector2.ZERO  # the box-glide value that lands the pool at EQUIP_SPOTLIGHT_SETTLE


## Current screen-px origin (top-left) of a cell's anchor — inverse of screen_to_world.
func cell_anchor_screen_px(cell: Vector2i) -> Vector2:
	var a: Node3D = _cells.get(cell)
	if a == null or not is_instance_valid(a):
		return cell_origin_px(cell.x, cell.y)
	return Vector2(a.position.x / PIXELS_PER_UNIT, -a.position.y / PIXELS_PER_UNIT)


## Current screen-px origin (top-left) of a cell's rendered unit BODY holder — the
## actually-visible sprite, a detached scene-ROOT sibling of the anchor. Distinct from
## cell_anchor_screen_px: the anchor moving does NOT move the body (they are siblings),
## so a guard must read THIS to prove the Equip slide moves the unit sprite (§15.23).
## Returns the docked cell origin if the cell has no body holder.
func cell_body_screen_px(cell: Vector2i) -> Vector2:
	var h: Node3D = _body_holders_by_cell.get(cell)
	if h == null or not is_instance_valid(h):
		return cell_origin_px(cell.x, cell.y)
	return Vector2(h.position.x / PIXELS_PER_UNIT, -h.position.y / PIXELS_PER_UNIT)


## The grid cells that currently hold a roster unit (the "rows of units" the Equip
## slide drives). Filtered by _cell_has_unit so an empty-roster boot yields nothing.
func visible_unit_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _populated.is_empty():
		return out
	for cell in _cells:
		if _populated.has(cell):
			out.append(cell)
	return out


## Anchor top-left origin that lands the SELECTED unit's sprite draw-centre at the
## measured settle (SpriteSlideAnimator.SETTLE_PX = (166,173)); centre is cell-relative
## (BODY_ANCHOR_DX, BODY_ANCHOR_DY).
func equip_selected_settle_origin() -> Vector2:
	return SpriteSlideAnimator.SETTLE_PX - Vector2(BODY_ANCHOR_DX, BODY_ANCHOR_DY)


## Latch the docked start + slide target of every visible unit cell, so play_equip_slide
## can tween between them. Selected → settle at (166,173); others → off the right edge,
## keeping their row Y (the horizontal-exit class, §15.23 clut 14741).
func begin_equip_slide() -> void:
	_equip_starts.clear()
	_equip_targets.clear()
	_equip_body_offsets.clear()
	var sel := selected_cell
	var settle_origin := equip_selected_settle_origin()
	for cell in visible_unit_cells():
		var start := cell_anchor_screen_px(cell)
		_equip_starts[cell] = start
		if cell == sel:
			_equip_targets[cell] = settle_origin
		else:
			_equip_targets[cell] = Vector2(EQUIP_EXIT_X, start.y)
		# Latch the body holder's constant world offset from its anchor (anchor is still
		# docked here), so play_equip_slide can carry the body along with the anchor.
		var a: Node3D = _cells.get(cell)
		var h: Node3D = _body_holders_by_cell.get(cell)
		if a != null and is_instance_valid(a) and h != null and is_instance_valid(h):
			_equip_body_offsets[cell] = h.position - a.position
	_equip_slide_active = true
	# Retarget the floor spotlight (via its box-glide source, §16) to follow the sliding unit.
	# Solve `centre = _box_glide + (BODY_ANCHOR_DX,FEET_BASELINE_DY) - box_center_px` for the glide
	# that lands `centre` at the measured settle EQUIP_SPOTLIGHT_SETTLE=(164,177). play_equip_slide
	# eases _box_glide start→target with the SAME SpriteSlideAnimator profile as the unit sprite.
	_equip_glide_start = _box_glide
	_equip_glide_target = EQUIP_SPOTLIGHT_SETTLE - Vector2(BODY_ANCHOR_DX, FEET_BASELINE_DY) + box_center_px
	_equip_spotlight_active = true


## Reposition every latched cell anchor to its eased position at slide frame `frame`.
## No-op until begin_equip_slide() latches the starts/targets.
func play_equip_slide(frame: int) -> void:
	if not _equip_slide_active:
		return
	var dur := SpriteSlideAnimator.SLIDE_DURATION
	for cell in _equip_starts:
		var a: Node3D = _cells.get(cell)
		if a == null or not is_instance_valid(a):
			continue
		var p := SpriteSlideAnimator.position_at_frame(_equip_starts[cell], _equip_targets[cell], frame, dur)
		a.position = screen_to_world(p.x, p.y)
		# Carry the detached body holder along with the anchor (BUG: only the anchor's
		# children — orb/shadow — slid before; the unit BODY stayed docked). Keep its
		# latched offset so the sprite scale + rung Z are preserved.
		var h: Node3D = _body_holders_by_cell.get(cell)
		if h != null and is_instance_valid(h) and _equip_body_offsets.has(cell):
			h.position = a.position + _equip_body_offsets[cell]
	# Ease the floor-spotlight box-glide along the SAME profile so the pool tracks the unit to
	# its settle (§16 coupling: the pool is the box-glide source, retargeted for the Equip slide).
	if _equip_spotlight_active:
		_box_glide = SpriteSlideAnimator.position_at_frame(
			_equip_glide_start, _equip_glide_target, frame, SpriteSlideAnimator.SLIDE_DURATION)
		_apply_floor_spotlight()


## The current floor-spotlight centre (virtual px) — the value pushed to the shader, derived from
## the eased box glide (§16). Exposed for the guard: during/after the Equip slide it tracks the unit
## to EQUIP_SPOTLIGHT_SETTLE; on the grid it equals spotlight_center_px(selected).
func current_spotlight_center() -> Vector2:
	return _box_glide + Vector2(BODY_ANCHOR_DX, FEET_BASELINE_DY) - box_center_px


## End the Equip slide/spotlight retarget (the host calls this on close, before restoring the grid
## chrome). Clears the flags so _advance_glide resumes easing the pool back to the selected cell.
func end_equip_slide() -> void:
	_equip_slide_active = false
	_equip_spotlight_active = false


## Reverse the Equip slide: put every latched cell's anchor (and its detached body holder) back at
## its DOCKED grid origin (the starts captured by begin_equip_slide). Called when the Equip screen
## is torn down (esc → back to the roster) so the units return to the grid. No-op if no slide ran.
func redock_units() -> void:
	for cell in _equip_starts:
		var a: Node3D = _cells.get(cell)
		if a == null or not is_instance_valid(a):
			continue
		var start: Vector2 = _equip_starts[cell]
		a.position = screen_to_world(start.x, start.y)
		var h: Node3D = _body_holders_by_cell.get(cell)
		if h != null and is_instance_valid(h) and _equip_body_offsets.has(cell):
			h.position = a.position + _equip_body_offsets[cell]
	_equip_starts.clear()
	_equip_targets.clear()
	_equip_body_offsets.clear()


## Reverse the split slide, ANIMATED (§15.24, user 2026-08-08 — "undo the slide"): units travel from
## their exit target BACK to the docked grid start, so a TOP-row unit (which exited LEFT on entry) re-
## enters from the LEFT and a BOTTOM-row unit from the RIGHT — the exact mirror of begin_changejob_slide.
## frame 0 = fully exited, frame SLIDE_DURATION = docked. Implemented as a TIME-REVERSAL of the entry ease
## (position_at_frame at `dur-frame`), so the units DECELERATE into their cells (ease-out arrival) — the
## natural "undo" of the accelerating exit. Reuses the retained _equip_* latches; the host calls
## redock_units() at the end to snap to the exact origin + clear them. No-op if no slide latched.
func play_equip_unslide(frame: int) -> void:
	if _equip_starts.is_empty():
		return
	var dur := SpriteSlideAnimator.SLIDE_DURATION
	for cell in _equip_starts:
		var a: Node3D = _cells.get(cell)
		if a == null or not is_instance_valid(a):
			continue
		var p := SpriteSlideAnimator.position_at_frame(_equip_starts[cell], _equip_targets[cell], dur - frame, dur)
		a.position = screen_to_world(p.x, p.y)
		var h: Node3D = _body_holders_by_cell.get(cell)
		if h != null and is_instance_valid(h) and _equip_body_offsets.has(cell):
			h.position = a.position + _equip_body_offsets[cell]


# --- Deployment-picker slide-in (#941 follow-up, ADR-0249) ---------------------------------------
# The picker's units ENTER, they do not appear: the grid comes up over a live battlefield, and a
# roster that pops in place reads as a HUD element pasted over the map rather than a screen the map
# receded behind. The user asked for the two together — "it would look cleaner than fading to the
# formation screen — especially if the units slide in from the side" — so this is the dim's other
# half, driven off the SAME tick by FormationPickIn.
#
# It carries its OWN latch and does not touch the _equip_* dicts, unlike begin_changejob_slide which
# deliberately reuses them. Those are live property of the Item→Equip / Change-Job transition, and ○
# on a picker cell still opens a Status overlay through the roster's own path — a picker holding the
# Equip latches would have the two gestures writing one set of starts. The BODY-holder carry is
# copied verbatim, though: the bodies are detached scene-ROOT siblings of their anchors, so moving an
# anchor alone slides the orb and the shadow and leaves the unit standing where it was (the bug
# aa65e2952 fixed for the Equip slide).

## Where a picker unit starts, off the RIGHT edge — [constant EQUIP_EXIT_X], the one off-screen X this
## file has a measurement behind (§15.23: clut 14741 ramped 186→248 and exited past the right edge).
## Entering from the side the Equip slide EXITS to makes the arrival that measured run backwards,
## which is the same reuse play_equip_unslide already makes of the same numbers.
const PICK_ENTER_X := EQUIP_EXIT_X

var _pick_slide_homes := {}      # Vector2i cell -> Vector2 docked anchor screen origin (the DESTINATION)
var _pick_slide_body_offsets := {}   # Vector2i cell -> Vector3 holder.position - anchor.position
var _pick_slide_active := false


## Latch every populated cell's docked HOME and park the units off the right edge, ready to slide in.
## Call AFTER the grid is built and seeded (the bodies must exist for their offsets to be latched),
## and note that it MOVES the units immediately: a latch that only recorded homes would leave the
## grid docked for the one frame before the first play_pick_slide, which is the pop this exists to
## remove.
func begin_pick_slide() -> void:
	_pick_slide_homes.clear()
	_pick_slide_body_offsets.clear()
	for cell in visible_unit_cells():
		var a: Node3D = _cells.get(cell)
		if a == null or not is_instance_valid(a):
			continue
		_pick_slide_homes[cell] = cell_anchor_screen_px(cell)
		var h: Node3D = _body_holders_by_cell.get(cell)
		if h != null and is_instance_valid(h):
			_pick_slide_body_offsets[cell] = h.position - a.position
	_pick_slide_active = not _pick_slide_homes.is_empty()
	if _pick_slide_active:
		play_pick_slide(0)


## Place every latched cell at its position on gesture tick `tick`. Each row runs its own
## [method FormationPickIn.slide_frame_at], so the rows arrive as two waves.
##
## The ease is a TIME-REVERSAL of [SpriteSlideAnimator]'s accelerating exit — `position_at_frame`
## read at `dur - frame`, exactly as [method play_equip_unslide] does — so the units DECELERATE
## into their cells. An entry that accelerated would slam the grid into place; the natural undo of
## an accelerating exit is a decelerating arrival, and §15.24's own "undo the slide" settled that.
func play_pick_slide(tick: int) -> void:
	if not _pick_slide_active:
		return
	var dur := SpriteSlideAnimator.SLIDE_DURATION
	for cell in _pick_slide_homes:
		var a: Node3D = _cells.get(cell)
		if a == null or not is_instance_valid(a):
			continue
		var home: Vector2 = _pick_slide_homes[cell]
		var frame := FormationPickIn.slide_frame_at(tick, cell.y)
		var p := SpriteSlideAnimator.position_at_frame(
			home, Vector2(PICK_ENTER_X, home.y), dur - frame, dur)
		a.position = screen_to_world(p.x, p.y)
		var h: Node3D = _body_holders_by_cell.get(cell)
		if h != null and is_instance_valid(h) and _pick_slide_body_offsets.has(cell):
			h.position = a.position + _pick_slide_body_offsets[cell]


## Drop the latch. The counterpart of [method begin_pick_slide]; the host calls it on the frame the
## gesture lands, and again when the pick closes, so nothing stays keyed by a cell about to be freed.
##
## [b]It does NOT snap the units home, deliberately.[/b] The obvious counterpart would re-place every
## anchor on its latched home "so the final position is the authored origin rather than the last
## eased sample" — and that line is false here. The last eased sample IS the origin: at the landing
## tick [method FormationPickIn.slide_frame_at] returns [constant SpriteSlideAnimator.SLIDE_DURATION],
## [method play_pick_slide] reads `position_at_frame` at `dur - SLIDE_DURATION == 0`, and frame 0 is
## documented to return `start` EXACTLY. A snap here was written, and a seeded defect that deleted it
## reddened nothing — code with no observable consequence, which is the same rule #941 applied to
## assertions read from the other end. What DOES matter is the ORDER the host calls it in: the
## landing push must happen before the latch is dropped, and the rig asserts that.
func end_pick_slide() -> void:
	_pick_slide_homes.clear()
	_pick_slide_body_offsets.clear()
	_pick_slide_active = false


## Is a picker slide-in latched and running? Asked by the rig for [method has_pick_dim]'s reason:
## an animation that never runs and one that completes instantly end at the SAME rest state, so
## without a question about the gesture ITSELF the slide has no assertion — only its destination
## does, and the destination is where the units already were.
func pick_sliding() -> bool:
	return _pick_slide_active


## How far off its docked place cell `cell`'s unit currently sits, in screen px — 0 when docked. The
## rig's window onto the slide MID-FLIGHT: it reads the BODY holder, because the body is the sprite
## the player sees and an anchor moving without it is the exact bug §15.23 records. Measured against
## the BODY's own docked place (`home` + the latched holder offset), not the anchor's — the two
## differ by that offset, so comparing the body to the anchor home would report a standing lie.
##
## Meaningful only WHILE the latch is up: [method end_pick_slide] drops it, after which this answers
## 0 for every cell because there is no home on record — including a cell parked off-screen. A rig
## checking the LANDED state must ask [method cell_anchor_screen_px] against the authored
## [method cell_origin_px] instead, which is a question this object cannot answer in its own favour.
func pick_slide_offset_px(cell: Vector2i) -> float:
	if not _pick_slide_homes.has(cell):
		return 0.0
	var home: Vector2 = _pick_slide_homes[cell]
	var docked_body := home
	if _pick_slide_body_offsets.has(cell):
		var off: Vector3 = _pick_slide_body_offsets[cell]
		docked_body += Vector2(off.x / PIXELS_PER_UNIT, -off.y / PIXELS_PER_UNIT)
	return absf(cell_body_screen_px(cell).x - docked_body.x)

# --- Change Job screen (FORMATION_SCREEN.md §15.24, RE round 28) ----------------------------------
# The Change-Job entry is a TWO-ROW SPLIT variant of the Equip slide: the selected unit slides to the
# oval CENTRE (not the Equip settle), roster units ABOVE it exit LEFT and those below exit RIGHT (vs
# Equip's everyone-right). It reuses the SAME latch/tween/redock machinery (play_equip_slide, the
# _equip_* dicts) — only the per-cell targets + the spotlight settle differ. Then build_changejob_wheel
# rings the centred unit with one generic body per gender-appropriate job (ChangeJobWheel; the oval is
# a DYNAMIC-measured layout — the ROM has no trig ring, static RE round 28). The banner-slide reuse is
# ROM-grounded: the candidate builder FUN_80138a74 calls world_banner_reset 0x801161e8 (slide 0x8018ba30).

## The selected unit's settle centre on the Change-Job screen — the oval CENTRE (virtual body-centre px),
## measured from formation_changejob_dest.sstate (prim scan of the 24×40 unit quads).
const CHANGEJOB_CENTRE := Vector2(128.0, 123.0)
## Roster units above the selected exit LEFT (off the left edge); below exit RIGHT (EQUIP_EXIT_X).
const CHANGEJOB_EXIT_LEFT_X := -80.0

var _changejob_wheel_cells: Array[Vector2i] = []   # synthetic cell keys of the ring bodies (for cleanup)
var _changejob_wheel_root: Node3D = null
var _changejob_job_ids: Array = []                 # the gender-filtered job ids the wheel rendered
var _changejob_wheel_anchors: Array[Node3D] = []   # ring member anchors, parallel to _changejob_job_ids
var _changejob_body_offsets: Array[Vector3] = []   # each member body-holder's latched offset from its anchor
                                                   # (bodies are detached holders, moved with the anchor —
                                                   # same mechanism as play_equip_slide, RE aa65e2952)

# Entry contraction (§15.24 RE29): members slide in from off-oval (k=ENTRY_K_START) → settled (k=1).
var _changejob_entry_k := 1.0
# Rotation glide (§15.24 RE29): `_cj_front` is the member index currently at the front-bottom slot
# (float during a glide). ←/→ glides it by ±1 so the next job rotates to front. The unit's CURRENT
# job starts at the front (index_of_job); the highlighted job = job_ids[round(_cj_front) mod n].
var _changejob_front := 0.0
var _cj_rot_from := 0.0
var _cj_rot_to := 0.0
var _cj_rot_frame := 0
var _cj_rot_active := false
## Rotation glide length in menu-ticks (≈30 Hz) — a smooth one-step rotate (oracle: a smooth glide,
## §15.24 RE29 `tmp/cj_live/RIGHT/n_09` mid-rotation, not a snap).
const CHANGEJOB_ROTATE_DURATION := 8

## Member-slots the ring rotates over the EXIT fling (§15.24, user 2026-08-08): the ring keeps spinning
## as it enlarges off-screen (oracle × back-out — spin AND enlarge, one motion). ~a quarter-turn's worth
## of member steps, eased with the same accelerating k so the spin blows out with the radius.
const CHANGEJOB_EXIT_SPIN_MEMBERS := 5.0

# Exit fling state (§15.24, user 2026-08-08): begin_changejob_exit latches the front and drives k UP past
# the oval (ChangeJobWheel.exit_k) while _changejob_front keeps advancing, so the ring spins off-screen.
var _cj_exit_active := false
var _cj_exit_front0 := 0.0


## Begin the Change-Job entry slide (§15.24 beats 1–3): selected unit → oval centre, upper roster rows
## exit LEFT, lower rows exit RIGHT. Populates the SAME _equip_* latches begin_equip_slide uses, so the
## host drives it with play_equip_slide(frame) / end_equip_slide() / redock_units() unchanged.
func begin_changejob_slide() -> void:
	_equip_starts.clear()
	_equip_targets.clear()
	_equip_body_offsets.clear()
	var sel := selected_cell
	# The selected unit's anchor origin that lands its body centre at CHANGEJOB_CENTRE (mirror of the
	# Equip settle math: body centre = anchor + (BODY_ANCHOR_DX, BODY_ANCHOR_DY)).
	var centre_origin := CHANGEJOB_CENTRE - Vector2(BODY_ANCHOR_DX, BODY_ANCHOR_DY)
	for cell in visible_unit_cells():
		var start := cell_anchor_screen_px(cell)
		_equip_starts[cell] = start
		if cell == sel:
			_equip_targets[cell] = centre_origin
		elif cell.y * 2 < ROWS:
			# TOP half of the grid exits LEFT, BOTTOM half exits RIGHT — a FIXED row split, NOT relative
			# to the selected unit's row (§15.24 item 4, RE29). Oracle: Ramza selected TOP-LEFT still sends
			# the rest of the top row LEFT and the bottom row RIGHT (the old `cell.y < sel.y` sent same-row
			# units RIGHT — wrong whenever the selection sits in the top row).
			_equip_targets[cell] = Vector2(CHANGEJOB_EXIT_LEFT_X, start.y)   # top rows exit LEFT
		else:
			_equip_targets[cell] = Vector2(EQUIP_EXIT_X, start.y)            # bottom rows exit RIGHT
		var a: Node3D = _cells.get(cell)
		var h: Node3D = _body_holders_by_cell.get(cell)
		if a != null and is_instance_valid(a) and h != null and is_instance_valid(h):
			_equip_body_offsets[cell] = h.position - a.position
	_equip_slide_active = true
	# Ease the floor spotlight to the centred unit's feet (below the body centre by the feet-vs-centre gap).
	_equip_glide_start = _box_glide
	var centre_feet := CHANGEJOB_CENTRE + Vector2(0.0, FEET_BASELINE_DY - BODY_ANCHOR_DY)
	_equip_glide_target = centre_feet - Vector2(BODY_ANCHOR_DX, FEET_BASELINE_DY) + box_center_px
	_equip_spotlight_active = true


## Ring the centred selected unit with one generic body per gender-appropriate generic job (§15.24
## beat 8). Mints a job-template Character per ChangeJobWheel job id (same-sex as `selected_character`),
## renders it through the SAME _build_cell_body path the roster uses, positioned on the oval. Idempotent:
## clears any prior wheel first.
func build_changejob_wheel(selected_character) -> void:
	clear_changejob_wheel()
	if selected_character == null:
		return
	var female: bool = _character_is_female(selected_character)
	_changejob_job_ids = ChangeJobWheel.job_ids_for_sex(female)
	# The unit's CURRENT job starts at the front-bottom slot (§15.24: the current-job ring member sits
	# front-bottom on entry; the centre avatar is the unit itself, separate — RE29).
	var cur := "4a"
	if selected_character.progression != null:
		cur = selected_character.progression.current_job_id
	var fi := ChangeJobWheel.index_of_job(_changejob_job_ids, cur)
	_changejob_front = float(fi) if fi >= 0 else 0.0
	_cj_rot_active = false
	_changejob_entry_k = 1.0
	_changejob_wheel_root = Node3D.new()
	_changejob_wheel_root.name = "ChangeJobWheel"
	add_child(_changejob_wheel_root)
	var n: int = _changejob_job_ids.size()
	for i in n:
		var job_id: String = _changejob_job_ids[i]
		var anchor := Node3D.new()
		# Build the body at the member's SETTLED oval slot (so the detached body holder lands sensibly);
		# _place_changejob_wheel then carries both anchor + holder for the entry contraction / rotation.
		var settled := ChangeJobWheel.ring_position(i, n, _changejob_front)
		anchor.position = screen_to_world(settled.x - BODY_ANCHOR_DX, settled.y - BODY_ANCHOR_DY)
		_changejob_wheel_root.add_child(anchor)
		_changejob_wheel_anchors.append(anchor)
		var jobchar = Character.create_default(ChangeJobWheel.job_name(job_id), job_id, female)
		var key := Vector2i(-1000 - i, 0)   # synthetic cell key, outside the roster grid range
		_changejob_wheel_cells.append(key)
		# The ring member casts the SAME subtractive feet shadow the roster units do (§15.24 item 1) —
		# a child of the anchor, so _place_changejob_wheel carries it as the member glides/rotates.
		_build_cell_shadow(anchor)
		_build_cell_body(anchor, jobchar, key)
		# The floor spotlight belongs to the CENTRE avatar only; ring members are IMMUNE to the
		# spatial-falloff dim (§15.24 item 2). _build_cell_body seeded ambient_brightness from the
		# synthetic key's distance-to-selection (meaningless off-grid) — force full brightness. The
		# sweep (_apply_element_sweep) skips wheel keys so it stays 1.0 as the selection/pool moves.
		var wheel_mat: ShaderMaterial = _body_mats_by_cell.get(key)
		if wheel_mat != null:
			wheel_mat.set_shader_parameter("ambient_brightness", 1.0)
		# Latch the body holder's constant offset from its anchor (as begin_equip_slide does), so
		# _place can move the body WITH the anchor (bodies are detached holders, not anchor children).
		var h: Node3D = _body_holders_by_cell.get(key)
		if h != null and is_instance_valid(h):
			_changejob_body_offsets.append(h.position - anchor.position)
		else:
			_changejob_body_offsets.append(Vector3.ZERO)
	_place_changejob_wheel()


## Position every ring anchor (and its detached body holder) from the current front index
## (`_changejob_front`) + entry factor (`_changejob_entry_k`): settled oval position for the member,
## scaled out from CENTRE by k (k=1 ⇒ settled). Called on build, each entry-contraction step, and each
## rotation-glide step (§15.24 RE29).
func _place_changejob_wheel() -> void:
	var n: int = _changejob_wheel_anchors.size()
	for i in n:
		var a: Node3D = _changejob_wheel_anchors[i]
		if a == null or not is_instance_valid(a):
			continue
		var final_pos := ChangeJobWheel.ring_position(i, n, _changejob_front)
		var pos := ChangeJobWheel.entry_position(final_pos, _changejob_entry_k)
		a.position = screen_to_world(pos.x - BODY_ANCHOR_DX, pos.y - BODY_ANCHOR_DY)
		var key := _changejob_wheel_cells[i] if i < _changejob_wheel_cells.size() else Vector2i.ZERO
		var h: Node3D = _body_holders_by_cell.get(key)
		if h != null and is_instance_valid(h) and i < _changejob_body_offsets.size():
			# Per-member painter's DEPTH: lift the front (bottom-of-oval) bodies toward the camera and sink
			# the back (top) ones, within the RP_UNIT_BODY rung, so front bodies occlude back ones (§15.24
			# RE31, FUN_80119AA0 iVar6). Recomputed each place() so depth re-sorts as ←/→ rotates the ring.
			var zbias := ChangeJobWheel.ring_depth_bias(i, n, _changejob_front) * CHANGEJOB_DEPTH_SPREAD * DepthMode.UNITS_PER_OT_BUCKET
			h.position = a.position + _changejob_body_offsets[i] + Vector3(0.0, 0.0, zbias)


## Begin the ring ENTRY contraction (§15.24 RE29): members start off the oval (k=ENTRY_K_START) and
## the host steps `changejob_entry_step(frame)` 0..ENTRY_DURATION to settle them onto the oval.
func begin_changejob_entry() -> void:
	_changejob_entry_k = ChangeJobWheel.entry_k(0)
	_place_changejob_wheel()


## Advance the ring entry contraction to menu-tick `frame` (0..ENTRY_DURATION). k eases → 1.0 (settled).
func changejob_entry_step(frame: int) -> void:
	_changejob_entry_k = ChangeJobWheel.entry_k(frame)
	_place_changejob_wheel()


func changejob_entry_settled() -> bool:
	return _changejob_entry_k >= 1.0


## Begin a one-step ring ROTATION glide in `direction` (+1 = RIGHT/next job, −1 = LEFT/prev, §15.24 RE29):
## the front index glides by `direction` over CHANGEJOB_ROTATE_DURATION ticks so the next job rotates to
## the front-bottom slot. No-op while another rotation is mid-glide (matches the oracle's one-at-a-time step).
func changejob_begin_rotate(direction: int) -> void:
	if _cj_rot_active or _changejob_wheel_anchors.is_empty():
		return
	_cj_rot_from = _changejob_front
	_cj_rot_to = _changejob_front + float(direction)
	_cj_rot_frame = 0
	_cj_rot_active = true


## Advance the rotation glide one menu-tick; repositions the ring. Returns true once the glide SETTLES
## on the new front member (the host then reads changejob_highlighted_job_id to update the title plate).
func changejob_rotate_step() -> bool:
	if not _cj_rot_active:
		return false
	_cj_rot_frame += 1
	var t := float(_cj_rot_frame) / float(CHANGEJOB_ROTATE_DURATION)
	if t >= 1.0:
		_changejob_front = _cj_rot_to
		_cj_rot_active = false
		_place_changejob_wheel()
		return true
	var ease := t * t * (3.0 - 2.0 * t)   # smoothstep glide
	_changejob_front = lerp(_cj_rot_from, _cj_rot_to, ease)
	_place_changejob_wheel()
	return false


func changejob_is_rotating() -> bool:
	return _cj_rot_active


## Begin the ring EXIT fling (§15.24, user 2026-08-08): the ring spins while it enlarges off-screen. The
## host then steps `changejob_exit_step(frame)` 0..EXIT_DURATION; at the end every member has cleared the
## screen (k = EXIT_K_END) and the wheel can be cleared. Cancels any in-flight rotation. No-op if empty.
func begin_changejob_exit() -> void:
	if _changejob_wheel_anchors.is_empty():
		return
	_cj_rot_active = false
	_cj_exit_front0 = _changejob_front
	_changejob_entry_k = 1.0
	_cj_exit_active = true


## Advance the exit fling to menu-tick `frame` (0..EXIT_DURATION): k grows 1.0 → EXIT_K_END (members fly
## off the oval, ease-in) AND the front index keeps advancing (the ring spins) — one combined motion, both
## driven by the same accelerating t so the spin blows out with the radius. Reuses _place_changejob_wheel
## so the per-member front-over-back depth (§15.24 RE31) re-sorts every frame as the ring turns.
func changejob_exit_step(frame: int) -> void:
	if not _cj_exit_active:
		return
	_changejob_entry_k = ChangeJobWheel.exit_k(frame)
	var t := clampf(float(frame) / float(ChangeJobWheel.EXIT_DURATION), 0.0, 1.0)
	_changejob_front = _cj_exit_front0 + CHANGEJOB_EXIT_SPIN_MEMBERS * (t * t)
	_place_changejob_wheel()


## True once the exit fling has driven every member off-screen (k reached EXIT_K_END). For the host's
## teardown gate + the guard. False while it is still growing (or if no exit is running).
func changejob_exit_settled() -> bool:
	return _cj_exit_active and _changejob_entry_k >= ChangeJobWheel.EXIT_K_END - 0.001


## True while the exit fling is running (host drives changejob_exit_step until changejob_exit_settled).
func is_changejob_exiting() -> bool:
	return _cj_exit_active


## The current exit radius factor k (1.0 at fling start → EXIT_K_END off-screen). For the guard that the
## back-out is ANIMATED (k grows past 1) not an instant snap.
func changejob_exit_k() -> float:
	return _changejob_entry_k


## The current entry-contraction factor k (ENTRY_K_START off-oval → 1.0 settled). For the guard: right
## after build it is > 1 (members are NOT instantly at their final oval slots — §15.24 RE29, gap 2).
func changejob_entry_k() -> float:
	return _changejob_entry_k


## The current front member index (float; the member at the front-bottom slot). For the guard.
func changejob_front_index() -> float:
	return _changejob_front


## The job id currently highlighted (the member at the front-bottom slot) — job_ids[round(front) mod n].
func changejob_highlighted_job_id() -> String:
	var n: int = _changejob_job_ids.size()
	if n == 0:
		return ""
	var idx: int = int(round(_changejob_front)) % n
	if idx < 0:
		idx += n
	return _changejob_job_ids[idx]


# -----------------------------------------------------------------------------
# The Change-Job COMMIT cutscene's VISUALS (CHANGE_JOB_COMMIT.md §§7-9). The CLOCK and every
# per-frame quantity live in ChangeJobCommitCutscene; this is only the rendering the host drives
# from it. Three pieces, all torn down together:
#   - a SECOND centre body, the target job's, mounted exactly over the unit's own. The two
#     dissolve into each other on complementary halves of one random cell field (§8) — the ROM
#     keeps two 480-byte VRAM shadows and erases one while it fills the other.
#   - the four-hue gouraud tint, pushed onto BOTH bodies' materials (§7).
#   - the 64-stripe cylinder, an ArrayMesh rebuilt per frame from the ring formulas (§9).
# -----------------------------------------------------------------------------

## Synthetic cell key for the target-job body — outside the roster grid AND outside the wheel's
## own -1000.. range, so nothing else's cleanup claims it.
const CHANGEJOB_COMMIT_CELL := Vector2i(-2000, 0)

var _cj_commit_anchor: Node3D = null       # anchor for the target-job body (drives its feet placement)
var _cj_commit_cyl: MeshInstance3D = null  # the 64-stripe cylinder
var _cj_commit_mesh: ArrayMesh = null
var _cj_commit_active := false


## Mount the commit cutscene's visuals for a change into `new_job_id`. The target-job body is
## built through the SAME _build_cell_body path as every other body, anchored on the selected
## unit's anchor so the per-job feet alignment lands it exactly over the current one. It carries
## the selected character's template identity, so a UNIQUE keeps its own art across the change
## (the ROM re-resolves the sprite descriptor; for a unique that resolves to the same sheet).
func begin_changejob_commit(new_job_id: String) -> void:
	end_changejob_commit()
	var sel := selected_cell
	var anchor: Node3D = _cells.get(sel)
	var character = selected_character()
	if anchor == null or not is_instance_valid(anchor) or character == null:
		return
	_cj_commit_anchor = Node3D.new()
	_cj_commit_anchor.name = "ChangeJobCommitAnchor"
	_cj_commit_anchor.position = anchor.position
	add_child(_cj_commit_anchor)
	var target = Character.create_default(
		ChangeJobWheel.job_name(new_job_id), new_job_id, _character_is_female(character))
	target.template_token = character.template_token
	target.special_name = character.special_name
	_build_cell_body(_cj_commit_anchor, target, CHANGEJOB_COMMIT_CELL)
	# The centre avatar is immune to the spatial-falloff dim, like the ring members are.
	var mat: ShaderMaterial = _body_mats_by_cell.get(CHANGEJOB_COMMIT_CELL)
	if mat != null:
		mat.set_shader_parameter("ambient_brightness", 1.0)
	# The new body sits one hair in FRONT of the old one so their depth writes never fight; the
	# dissolve makes them disjoint per-pixel anyway, but equal Z would flicker on a tie.
	var h: Node3D = _body_holders_by_cell.get(CHANGEJOB_COMMIT_CELL)
	var old_h: Node3D = _body_holders_by_cell.get(sel)
	if h != null and is_instance_valid(h) and old_h != null and is_instance_valid(old_h):
		h.position = old_h.position + Vector3(0.0, 0.0, 0.0001)
	_build_changejob_cylinder()
	_cj_commit_active = true


## Push one cutscene frame onto the visuals: `revealed` is the dissolve's 0..1 fraction and
## `gouraud` the twelve corner bytes, both straight off the model. Cheap — uniform writes plus
## one ArrayMesh rebuild; nothing is re-composited.
func changejob_commit_step(f: int, revealed: float, gouraud: PackedByteArray) -> void:
	if not _cj_commit_active:
		return
	_push_commit_body(selected_cell, revealed, 0.0, gouraud)
	_push_commit_body(CHANGEJOB_COMMIT_CELL, revealed, 1.0, gouraud)
	_place_changejob_cylinder(f)


## Drive one body's cutscene uniforms. `sense` 0 = the OLD job (shows the cells the dissolve has
## NOT consumed), 1 = the NEW one (shows the consumed ones) — exact complements, so the pair is
## always exactly one sprite's worth of pixels.
func _push_commit_body(cell: Vector2i, revealed: float, sense: float, gouraud: PackedByteArray) -> void:
	var mat: ShaderMaterial = _body_mats_by_cell.get(cell)
	if mat == null:
		return
	mat.set_shader_parameter("cj_active", true)
	mat.set_shader_parameter("cj_dissolve", revealed)
	mat.set_shader_parameter("cj_dissolve_sense", sense)
	mat.set_shader_parameter("cj_bbox_loc", _commit_bbox_loc(cell))
	mat.set_shader_parameter("cj_loc_bias", BODY_LOC_BIAS)
	# PSX gouraud 0x80 is neutral 1.0x, so the byte IS the multiplier over 128.
	mat.set_shader_parameter("cj_tint_tl", _gouraud_corner(gouraud, 0))
	mat.set_shader_parameter("cj_tint_tr", _gouraud_corner(gouraud, 1))
	mat.set_shader_parameter("cj_tint_bl", _gouraud_corner(gouraud, 2))
	mat.set_shader_parameter("cj_tint_br", _gouraud_corner(gouraud, 3))


static func _gouraud_corner(g: PackedByteArray, corner: int) -> Vector3:
	var i := corner * 3
	if g.size() < i + 3:
		return Vector3.ONE
	return Vector3(float(g[i]), float(g[i + 1]), float(g[i + 2])) / 128.0


## The composited frame's visible bbox in LOC space — the tint gradient's domain, so the ramp
## spans the SPRITE the way the ROM's does (its quad is the 24x40 frame, ours is the 256-loc
## atlas window). Falls back to a nominal 24x40 centred on the quad if the frame is unreadable.
func _commit_bbox_loc(cell: Vector2i) -> Vector4:
	var bb: Rect2 = _body_bbox_by_cell.get(cell, Rect2())
	if bb.size.x > 0.0 and bb.size.y > 0.0:
		return Vector4(bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	# No readable frame: fall back to a nominal 24x40 centred on the quad (the ROM's own frame
	# size), so the ramp still spans a sprite-sized box rather than the whole 256-loc window.
	return Vector4(-12.0 - BODY_LOC_BIAS.x, -20.0 - BODY_LOC_BIAS.y, 24.0, 40.0)


## Build the cylinder mesh instance once (geometry is rewritten per frame). It rides the same
## fold routing as the other display-space prims (ADR-0077) at a rung in FRONT of the bodies —
## `[dynamic]` the ROM's OT walk puts the stripes in slot 0x38, ahead of the quads' 0x33.
func _build_changejob_cylinder() -> void:
	var folded := Fold.owns()
	_cj_commit_mesh = ArrayMesh.new()
	_cj_commit_cyl = MeshInstance3D.new()
	_cj_commit_cyl.name = "ChangeJobCylinder"
	_cj_commit_cyl.mesh = _cj_commit_mesh
	var mat := ShaderMaterial.new()
	mat.shader = fold_shader_for("changejob_cylinder")
	_cj_commit_cyl.material_override = mat
	add_child(_cj_commit_cyl)
	# MATERIALIZE the rung into real Z on BOTH paths (ADR-0077). `Fold.add`'s order_z only
	# orders prims WITHIN the fold layer; what decides whether a depth-writing opaque body
	# occludes this one is the geometry's own Z, because the fold shader emits `DEPTH` from
	# its clip position. Left at z = 0 the stripes sat five rungs BEHIND the unit bodies and
	# every ring member painted over them — the same shape of bug ADR-0077 exists for.
	# The stripe verts are built at local z = 0, so the node position carries the whole rung.
	_cj_commit_cyl.position = Vector3(0.0, 0.0, DepthMode.rung_z(RP_CHANGEJOB_CYLINDER))
	if folded:
		Fold.add(_cj_commit_cyl, mat, DepthMode.rung_z(RP_CHANGEJOB_CYLINDER))
	else:
		mat.render_priority = RP_CHANGEJOB_CYLINDER


## Rewrite the 64 stripes for cutscene frame `f`. Each stripe is two vertical GOURAUD spans —
## black at the screen top -> magenta at `y_top`, then magenta -> black at `y_bot` — drawn as
## 1px-wide quads because Godot has no gouraud LINE primitive. The ROM emits LINE_G2 packets;
## the visual result is identical and the ABR-3 quarter-add lives in the shader.
func _place_changejob_cylinder(f: int) -> void:
	if _cj_commit_mesh == null or not is_instance_valid(_cj_commit_cyl):
		return
	_cj_commit_mesh.clear_surfaces()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for k in ChangeJobCommitCutscene.STRIPES:
		var s: Dictionary = ChangeJobCommitCutscene.stripe_at(k, f)
		var x: int = s["x"]
		var y_top: int = s["y_top"]
		var y_bot: int = s["y_bot"]
		# Span 1: screen top (y 0) down to the magenta peak — nothing to draw once the peak
		# itself is above the screen (entry/exit, where S pushes the whole bar off the top).
		if y_top > 0:
			_push_stripe_span(verts, cols, x, 0, y_top,
				ChangeJobCommitCutscene.STRIPE_BLACK, ChangeJobCommitCutscene.STRIPE_MAGENTA)
		# Span 2: the magenta peak down to the bottom of the bar.
		if y_bot > 0:
			_push_stripe_span(verts, cols, x, y_top + 1, y_bot,
				ChangeJobCommitCutscene.STRIPE_MAGENTA, ChangeJobCommitCutscene.STRIPE_BLACK)
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	_cj_commit_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## One 1px-wide vertical gouraud span as two triangles, `top_col` at y0 fading to `bot_col` at y1.
##
## A span starting ABOVE the screen is clipped to y = 0 with its colour INTERPOLATED to the clip
## point, not clamped: during the entry the magenta peak sits ~150px off the top, so a clamped
## colour paints the screen's top edge full magenta when the ramp says it should be nearly black —
## the difference between "the cylinder fades in as it descends" and "a solid pink slab".
func _push_stripe_span(verts: PackedVector3Array, cols: PackedColorArray,
		x: int, y0: int, y1: int, top_col: Color, bot_col: Color) -> void:
	if y1 <= y0 or y1 <= 0:
		return
	if y0 < 0:
		top_col = top_col.lerp(bot_col, float(-y0) / float(y1 - y0))
		y0 = 0
	var tl := screen_to_world(float(x), float(y0))
	var br := screen_to_world(float(x + 1), float(y1))
	var tr := Vector3(br.x, tl.y, 0.0)
	var bl := Vector3(tl.x, br.y, 0.0)
	tl.z = 0.0
	br.z = 0.0
	for v in [tl, tr, br, tl, br, bl]:
		verts.append(v)
	for c in [top_col, top_col, bot_col, top_col, bot_col, bot_col]:
		cols.append(c)


## Drop the cutscene visuals and clear the cutscene uniforms off the unit's own body, so the
## settled screen renders exactly as it did before the commit. Idempotent.
func end_changejob_commit() -> void:
	_cj_commit_active = false
	var own: ShaderMaterial = _body_mats_by_cell.get(selected_cell)
	if own != null:
		own.set_shader_parameter("cj_active", false)
	var h: Node3D = _body_holders_by_cell.get(CHANGEJOB_COMMIT_CELL)
	if h != null and is_instance_valid(h):
		h.queue_free()
	_body_holders_by_cell.erase(CHANGEJOB_COMMIT_CELL)
	_body_mats_by_cell.erase(CHANGEJOB_COMMIT_CELL)
	_body_bbox_by_cell.erase(CHANGEJOB_COMMIT_CELL)
	if _cj_commit_anchor != null and is_instance_valid(_cj_commit_anchor):
		_cj_commit_anchor.queue_free()
	_cj_commit_anchor = null
	if _cj_commit_cyl != null and is_instance_valid(_cj_commit_cyl):
		_cj_commit_cyl.queue_free()
	_cj_commit_cyl = null
	_cj_commit_mesh = null


## True while the commit cutscene's visuals are mounted (for the guard + the host's teardown).
func is_changejob_committing() -> bool:
	return _cj_commit_active


## Re-composite the SELECTED unit's own body from its (now changed) job and drop it back at the
## Change-Job centre. The ROM's apply block re-resolves the sprite as part of rebuilding the unit
## (§11a `FUN_801212b8`); ours rebuilds the one cell rather than the whole grid.
func rebuild_selected_body() -> void:
	var sel := selected_cell
	var anchor: Node3D = _cells.get(sel)
	var character = selected_character()
	if anchor == null or not is_instance_valid(anchor) or character == null:
		return
	var old: Node3D = _body_holders_by_cell.get(sel)
	if old != null and is_instance_valid(old):
		# UNPARENT before the rebuild, not just queue_free: the free is deferred to end-of-frame,
		# so the old holder would still hold the "Body_<x>_<y>" name when _build_cell_body adds the
		# new one over the SAME anchor. Godot renames the newcomer, the rename hides it from
		# rebuild_cells()'s sweep, and the changed unit's body is orphaned on the next scroll —
		# a second, static sprite stacked on the grid. It also double-draws for one frame.
		remove_child(old)
		old.queue_free()
	_body_holders_by_cell.erase(sel)
	_body_mats_by_cell.erase(sel)
	_body_bbox_by_cell.erase(sel)
	_build_cell_body(anchor, character, sel)
	var mat: ShaderMaterial = _body_mats_by_cell.get(sel)
	if mat != null:
		mat.set_shader_parameter("ambient_brightness", 1.0)
	# Re-latch the Equip/Change-Job slide offset so a later un-slide carries the NEW holder.
	var h: Node3D = _body_holders_by_cell.get(sel)
	if h != null and is_instance_valid(h) and _equip_starts.has(sel):
		_equip_body_offsets[sel] = h.position - anchor.position


## Tear the Change-Job wheel down: free every ring body holder + its synthetic anchor and drop the
## synthetic cell keys. Called on close, before redock_units restores the roster.
func clear_changejob_wheel() -> void:
	for key in _changejob_wheel_cells:
		var h: Node3D = _body_holders_by_cell.get(key)
		if h != null and is_instance_valid(h):
			h.queue_free()
		_body_holders_by_cell.erase(key)
		_body_mats_by_cell.erase(key)   # drop the wheel material so the sweep stops touching it post-close
	_changejob_wheel_cells.clear()
	_changejob_job_ids.clear()
	_changejob_wheel_anchors.clear()
	_changejob_body_offsets.clear()
	_cj_rot_active = false
	_cj_exit_active = false
	_changejob_entry_k = 1.0
	if _changejob_wheel_root != null and is_instance_valid(_changejob_wheel_root):
		_changejob_wheel_root.queue_free()
	_changejob_wheel_root = null


## The gender-filtered job ids the wheel rendered (for the guard). Empty until build_changejob_wheel.
func changejob_wheel_job_ids() -> Array:
	return _changejob_job_ids


## Number of ring bodies currently mounted (the guard asserts one per gender-appropriate job).
func changejob_wheel_body_count() -> int:
	return _changejob_wheel_cells.size()


## How many ring anchors carry a feet-shadow decal (§15.24 item 1). _build_cell_shadow → _mount_quad
## mounts a holder node on the anchor (its mesh may be Fold-reparented on the fork, so count the holder,
## not a MeshInstance3D child). A wheel anchor gets ONLY the shadow, so a child == a shadow; the guard
## asserts one per member (parity with the roster, which always shadows its units).
func changejob_wheel_shadow_count() -> int:
	var n := 0
	for a in _changejob_wheel_anchors:
		if a != null and is_instance_valid(a) and a.get_child_count() > 0:
			n += 1
	return n


## The MINIMUM ambient_brightness across the ring member bodies (§15.24 item 2). The floor spotlight
## belongs to the centre avatar only, so every member must be full-bright — the guard asserts this is
## 1.0 even after a sweep (a far synthetic key would otherwise dim via spatial falloff). 1.0 if empty.
func changejob_wheel_min_brightness() -> float:
	var lo := 1.0
	for key in _changejob_wheel_cells:
		var mat: ShaderMaterial = _body_mats_by_cell.get(key)
		if mat == null:
			continue
		var b: float = mat.get_shader_parameter("ambient_brightness")
		lo = min(lo, b)
	return lo


func _character_is_female(character) -> bool:
	if character != null and character.progression != null:
		return character.progression.base_stat_type == UnitProgression.BaseStatType.FEMALE
	return false


## Screen-space centre (virtual px) of the selected-unit floor SPOTLIGHT: the unit's
## floor-CONTACT point — column-centre X (= the ROM body centre) and the feet-baseline
## Y. BOTH axes track the unit, so moving to another row slides the oval DOWN (the pool
## follows the selected unit, not a fixed vertical band — §14.6.3, live-corrected).
static func spotlight_center_px(col: int, row: int) -> Vector2:
	return Vector2(GRID_ORIGIN.x + col * COL_PITCH + BODY_ANCHOR_DX,
		GRID_ORIGIN.y + row * ROW_PITCH + FEET_BASELINE_DY)


## The selected unit's sprite-centre in screen px (its LIVE anchor + the body anchor offset). The
## main-formation START menu uses this to decide which screen half the menu opens on (opposite the
## unit, so it never overlaps — §15.20 RE26). On the docked roster this equals the cell centre.
## Is the selected unit one the player OWNS — i.e. may act on? On the roster host the answer is
## always yes: the roster is your own party by definition. The map host can be pointed at an enemy,
## and there the same screen opens read-only (ADR-0137 — the action rows are DISABLED, not hidden).
func selection_is_owned() -> bool:
	return true


## May the selected unit be edited right now (#894)? On the roster host, always: the standalone
## Formation screen is the out-of-battle path, where there is no turn for an edit to belong to.
## The map host is where the answer can be no.
func selection_is_steerable() -> bool:
	return selection_is_owned()


## WHERE the selected unit is, in display px. This is the query that INVERTS across the two hosts
## (ADR-0137): on the roster host the UI asks where the unit happens to be and places itself around
## it; on the map host the breakout mark is FIXED and the camera moves until the unit satisfies it.
func selected_unit_screen_center() -> Vector2:
	return cell_anchor_screen_px(selected_cell) + Vector2(BODY_ANCHOR_DX, BODY_ANCHOR_DY)


## Floor-spotlight brightness multiplier at virtual pixel (px,py) for the oval centred
## on `centre`. SAME falloff as the orb (§10): base − swing·sqrt(dx² + vfac·dy²), with
## vfac = 4 ⇒ a 2:1 HORIZONTALLY-elongated pool (light spreads twice as far across the
## floor as up/down). Clamped to [min_level, base]: the far floor darkens toward — but
## never past — a non-black minimum.
static func floor_brightness(px: float, py: float, centre: Vector2,
		base: float, swing: float, vfac: float, min_level: float) -> float:
	var dx := px - centre.x
	var dy := py - centre.y
	var dist := sqrt(dx * dx + vfac * dy * dy)
	return clampf(base - swing * dist, min_level, base)


## ROM on-screen body rect (virtual px) for a descriptor Uw×Vh at cell (col,row).
## FUN_80117db8 @0x80117db8: top-left = (cellX − Uw/2 + 31, cellY − Vh/2 + 24),
## size = Uw×Vh (drawn native 1:1). See FORMATION_ELEMENT_PLACEMENT.md §4.1.
static func rom_body_rect(col: int, row: int, uw: float, vh: float) -> Rect2:
	var cx := GRID_ORIGIN.x + col * COL_PITCH
	var cy := GRID_ORIGIN.y + row * ROW_PITCH
	return Rect2(cx - uw * 0.5 + BODY_ANCHOR_DX, cy - vh * 0.5 + BODY_ANCHOR_DY, uw, vh)


## ROM on-screen drop-shadow rect (virtual px). FUN_8011814c 2nd prim, placed
## relative to the BODY rect: (bodyLeft, bodyTop+30) for narrow (Uw<0x19) sprites,
## (bodyLeft+12, bodyTop+35) for wide ones; size 20×10 (2:1 squash of a 20×20 texel).
static func rom_shadow_rect(col: int, row: int, uw: float, vh: float) -> Rect2:
	var body := rom_body_rect(col, row, uw, vh)
	var narrow := uw < float(SHADOW_UW_GATE)
	var sx := body.position.x + (0.0 if narrow else SHADOW_WIDE_DX)
	var sy := body.position.y + (SHADOW_FEET_DY_NARROW if narrow else SHADOW_FEET_DY_WIDE)
	return Rect2(sx, sy, SHADOW_SCREEN_PX.x, SHADOW_SCREEN_PX.y)


## Loc-space → virtual-px scale of the compositor at a given holder body_scale.
## One sprite loc-pixel = body_scale/(BODY_ATLAS_W·PIXELS_PER_UNIT) virtual px
## (isotropic — see the calibration block above). Pure so it unit-tests.
static func body_loc_to_screen_k(body_scale: float) -> float:
	return body_scale / (BODY_ATLAS_W * PIXELS_PER_UNIT)


## The holder body_scale that renders a composited frame of visible loc-height
## `bbox_h` at `target_vh` virtual px. Inverse of body_loc_to_screen_k applied to
## the height: target_vh = bbox_h · k(body_scale).
static func body_scale_for_bbox(bbox_h: float, target_vh: float) -> float:
	if bbox_h <= 0.0:
		return 0.0
	return target_vh * BODY_ATLAS_W * PIXELS_PER_UNIT / bbox_h


## Cell-relative holder offset (the anchor screen point the holder mounts at) so
## the composited frame's visible-bbox FEET (bottom-centre) land on `feet_target_px`
## (cell-relative standing point). Derived per-unit from the frame's loc-space bbox
## + the fixed body_scale: this replaces the single guessed body_offset_px, removes
## the per-job feet scatter, AND stands all units (any height) on one line (§7).
static func derive_body_offset_px(bbox: Rect2, body_scale: float, feet_target_px: Vector2) -> Vector2:
	var k := body_loc_to_screen_k(body_scale)
	var foot := Vector2(bbox.position.x + bbox.size.x * 0.5, bbox.position.y + bbox.size.y)
	return feet_target_px - (foot + BODY_LOC_BIAS) * k


func _quad(size_px: Vector2) -> MeshInstance3D:
	# QuadMesh anchored TOP-LEFT: holder.position is the top-left corner, the mesh
	# is offset by half its size (+X/-Y) so it extends right-and-down (ui3 pattern).
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size_px * PIXELS_PER_UNIT
	mi.mesh = q
	mi.position = Vector3(q.size.x * 0.5, -q.size.y * 0.5, 0.0)
	return mi



func _build_background() -> void:
	# The backdrop group (cobble floor + band backdrop, one blend-ordered holder) is HOUSED
	# in the registered element `formation.background` (ADR-0088): a screen-anchored
	# assembly, UNCLIPPED, no beat (the band fades via the band factor). The element places
	# itself at screen origin; only the RP_BACKGROUND fold-Z lift stays hand-applied after
	# tree entry (pending a real depth criterion, like detail.compare).
	var holder := UI3Element.new({
		"id": "formation.background",
		"rect": UI3Element.screen_anchored(),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	holder.name = "Background"
	add_child(holder)
	holder.position.z += DepthMode.rung_z(RP_BACKGROUND)

	if not paints_own_backdrop():
		# MAP host (ADR-0137): the battlefield is the background. Build the BAND into the same
		# holder — it is screen-common, and subtracting it from the live map is the whole point —
		# but no cobble quad and no pillarbox bars.
		_build_band_backdrop(holder)
		return

	var mi := _quad(SCREEN)
	var mat := ShaderMaterial.new()
	mat.shader = load(_BG_SHADER)
	mat.set_shader_parameter("index_atlas", load(_ASSET_DIR + "BACKGROUND.tga"))
	mat.set_shader_parameter("palette_tex", load(_ASSET_DIR + "BACKGROUND.palette.tga"))
	mat.set_shader_parameter("tile_px", Vector2(128.0, 32.0))
	mat.set_shader_parameter("screen_px", SCREEN)
	# No render_priority: the holder above already carries this rung as real world Z
	# (DepthMode.rung_z(RP_BACKGROUND)), and ADR-0077 rules that ordering falls out of that
	# one Z. This prim is opaque and depth-writing on both the fork and the fallback, so the
	# priority was doing nothing the depth buffer wasn't already deciding (#634).
	mi.material_override = mat
	holder.add_child(mi)
	_bg_mat = mat

	# The subtractive "band" backdrop draws AFTER the floor (added second to the same
	# Background holder) so blend_sub subtracts from it; the vitals panel content
	# (render_priority >= 1) then paints over the band. §14.6.6.
	_build_band_backdrop(holder)
	_apply_floor_spotlight()
	_build_pillarbox_mask()


## Build the left + right gray pillarbox mask bars (user 2026-08-08): two OPAQUE gray quads over the 4:3
## letterbox margins outside the 256×240 content, mounted at a near-Z ABOVE all content so escaping
## sprites (the enlarging Change-Job exit ring, mid-slide roster units) vanish behind them instead of
## spilling over the gray. Over the (normally empty) margin the gray quad is identical to the viewport
## clear colour, so the framed roster is unchanged — the bars only ever HIDE content that leaves the rect.
func _build_pillarbox_mask() -> void:
	for spec in [
		{"name": "PillarboxLeft", "x": -PILLARBOX_MARGIN_PX, "w": PILLARBOX_MARGIN_PX},
		{"name": "PillarboxRight", "x": SCREEN.x, "w": PILLARBOX_MARGIN_PX},
	]:
		var holder := Node3D.new()
		holder.name = spec["name"]
		holder.position = screen_to_world(spec["x"], 0.0) + Vector3(0.0, 0.0, PILLARBOX_MASK_Z)
		add_child(holder)
		var mi := _quad(Vector2(spec["w"], SCREEN.y))
		# The mask is a flat unshaded bar pinned on top at PILLARBOX_MASK_Z that only ever
		# HIDES off-rect content — it never depth-sorts against OT geometry.
		# psx-ot-depth-exempt: screen-space pillarbox mask, not a battle mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = PILLARBOX_GRAY
		mi.material_override = mat
		holder.add_child(mi)


## Build the bottom "band" backdrop (§14.6.6): a full-width SUBTRACTIVE band reproducing
## FUN_80112c88 iter2. One QuadMesh over screen y168..237; the shader reads each fragment's
## screen y from FRAGCOORD (the ORTHOGRAPHIC camera makes this exact) and applies the oracle
## fg/255 trapezoid (band_subtract_at) in DISPLAY space against the re-sampled cobble. Above the floor
## (RP_BACKGROUND+1) so it reliably draws AFTER it and subtracts; vitals content (RP>=1,
## added later) paints over the band.
func _build_band_backdrop(holder: Node3D) -> void:
	var folded := Fold.owns()
	# The band is the SHARED UIVitalsBand element (extracted 2026-08-05 — the SAME stripe the
	# unit-detail / Status screen draws). On the fork it folds (display-space subtract of the fg
	# trapezoid from the Pass-A scratch cobble); off-fork it re-samples the floor here (principled
	# subtract, no guessed floor_ref — the spotlight uniforms are mirrored by _apply_floor_spotlight
	# so the two stay byte-identical). Only the y feather is set → the shared shader's x profile is 1.0.
	var spec := {
		"name": "BandBackdrop",
		"x0": BAND_X0, "x1": BAND_X1,
		"y_top_out": BAND_TOP_OUT, "y_top_in": BAND_TOP_IN,
		"y_bot_in": BAND_BOT_IN, "y_bot_out": BAND_BOT_OUT,
		"full_sub": BAND_FULL_SUB, "rung": RP_BACKGROUND + 1,
	}
	if not folded:
		spec["floor"] = {
			"index_atlas": load(_ASSET_DIR + "BACKGROUND.tga"),
			"palette_tex": load(_ASSET_DIR + "BACKGROUND.palette.tga"),
			"tile_px": Vector2(128.0, 32.0),
			"screen_px": SCREEN,
		}
	_band_mat = UIVitalsBand.build(holder, spec, PIXELS_PER_UNIT, SCREEN)
	# ADR-0088 Amendment 5 §4: house the stripe in the registered carrier element
	# `formation.vitals_band` (mirrors detail.vitals_band; UIVitalsBand is RefCounted, so a
	# carrier wrap — not a base-swap — is correct). The "BandBackdrop" holder reparents
	# keep-global (visual no-op: FormationBackdropElementTest's golden), so the stripe now
	# shows a UI3 row ON the formation roster, not only after ○-press mounts the Status screen.
	var band_elem := UI3Element.new({
		"id": "formation.vitals_band",
		"rect": Rect2(BAND_X0, BAND_TOP_OUT, BAND_X1 - BAND_X0, BAND_BOT_OUT - BAND_TOP_OUT),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	band_elem.name = "VitalsBandElement"
	holder.add_child(band_elem)
	var band_holder := holder.get_node_or_null("BandBackdrop") as Node3D
	if band_holder != null:
		band_holder.reparent(band_elem, true)   # keep-global: world transform unchanged
		# reparent() = remove_child + add_child, so the band mesh's tree_exiting fires Fold's
		# un-enroll hook (b6400949d) and NULLS its render_layer — silently dropping it from the
		# fold layer, so it stops compositing as a subtractive band (renders washed-out / "cut off
		# top and bottom"). Re-enroll into the fold layer after the move restores the subtract.
		if folded:
			for c: Node in band_holder.get_children():
				if c is MeshInstance3D:
					Fold.add(c, _band_mat, DepthMode.rung_z(RP_BACKGROUND + 1))


## Drive the floor spotlight from the current selection: centre the oval on the
## selected unit (both axes) and push the falloff knobs. A pure uniform write on the
## background material — no cell rebuild — so a selection move / knob scrub is cheap.
func _apply_floor_spotlight() -> void:
	if _bg_mat == null:
		return
	# The floor pool is SLAVED to the gold-box glide (§16.1): its centre = the eased box
	# centre offset to the unit's floor-contact point. At settle this equals
	# spotlight_center_px(selected); during a move it eases with the box (both axes) so the
	# floor slides WITH the box, never ahead of it (the §16.1 coherence rule).
	var centre := _box_glide + Vector2(BODY_ANCHOR_DX, FEET_BASELINE_DY) - box_center_px
	_bg_mat.set_shader_parameter("spot_center_px", centre)
	_bg_mat.set_shader_parameter("spot_base", floor_spot_base)
	_bg_mat.set_shader_parameter("spot_swing", floor_spot_swing)
	_bg_mat.set_shader_parameter("spot_vfac", floor_spot_vfac)
	_bg_mat.set_shader_parameter("spot_min", floor_spot_min)
	# Mirror the SAME spotlight into the band so its re-sampled cobble matches the floor per
	# pixel (the principled subtract only lands if both sample identical cobble). §14.6.6.
	if _band_mat != null:
		_band_mat.set_shader_parameter("spot_center_px", centre)
		_band_mat.set_shader_parameter("spot_base", floor_spot_base)
		_band_mat.set_shader_parameter("spot_swing", floor_spot_swing)
		_band_mat.set_shader_parameter("spot_vfac", floor_spot_vfac)
		_band_mat.set_shader_parameter("spot_min", floor_spot_min)


func _build_grid() -> void:
	var grid := Node3D.new()
	grid.name = "CellGrid"
	add_child(grid)
	_cells.clear()

	for row in range(ROWS):
		for col in range(COLS):
			var anchor := Node3D.new()
			anchor.name = "Cell_%d_%d" % [col, row]
			var o := cell_origin_px(col, row)
			anchor.position = screen_to_world(o.x, o.y)
			grid.add_child(anchor)
			_cells[Vector2i(col, row)] = anchor

			if show_cell_outlines:
				var mi := _quad(CELL)
				var mat := ShaderMaterial.new()
				mat.shader = load(_OUTLINE_SHADER)
				mat.set_shader_parameter("size_px", CELL)
				# THE ONE GENUINE render_priority EXCEPTION, and it is structural rather than
				# leftover: formation_cell_outline.gdshader declares `depth_draw_never,
				# depth_test_disabled`, so this prim has no depth to be sorted by and ADR-0077's
				# "ordering falls out of one Z" cannot reach it. A rung Z here would be inert —
				# the depth test that would read it is off — and dropping the priority would
				# leave the outline with no ordering at all. It stays, deliberately (#634).
				# It is debug scaffolding (#171, "not shipped chrome") and off by default; if it
				# is ever promoted, the fix is to make the SHADER depth-writing, then it joins
				# the ladder like everything else.
				mat.render_priority = RP_CELL_OUTLINE
				mi.material_override = mat
				anchor.add_child(mi)


# -----------------------------------------------------------------------------
# Cell contents (#173): per-unit Face-Front body sprite + per-cell orb, plus the
# gold selection box on the cursor cell. Ordered bg < outline < box sub < box add < unit
# < orb — by REAL Z, one OT bucket per RP_* rung (ADR-0077), NOT by paint order. "Screen-
# space, depth off" was true before ADR-0077 and has not been since (#634).
# -----------------------------------------------------------------------------

func _populate_cells() -> void:
	_cell_content.clear()
	_orb_mats_by_cell.clear()
	_orb_holders_by_cell.clear()
	_body_mats_by_cell.clear()
	_body_bbox_by_cell.clear()
	_body_holders_by_cell.clear()
	_populated.clear()
	var units := _roster_characters()
	for row in range(ROWS):
		for col in range(COLS):
			var cell := Vector2i(col, row)
			var anchor: Node3D = _cells.get(cell)
			if anchor == null:
				continue
			var index := row * COLS + col
			var character = units[index] if index < units.size() else null
			if character == null:
				continue  # roster shorter than the grid → this cell stays empty
			_populated[cell] = true
			if not debug_bodies_only:
				_build_cell_shadow(anchor)
			_build_cell_body(anchor, character, cell)
			if not debug_bodies_only:
				_build_cell_orb(anchor, cell)
				_build_cell_sort_value(anchor, character)
	# The gold box is NOT a per-cell child any more — it's the persistent glide/trail
	# (_build_box_trail), so a selection move eases it instead of rebuilding it here.


## Tear down and re-lay every cell's contents (body/shadow/orb/box) from the
## current placement knobs. For the F3 Formation calibration panel — lets a scrub
## take effect live without a scene reload. Grid anchors + background + vitals are
## untouched.
func rebuild_cells() -> void:
	var stale: Array = []
	var seen := {}
	# Sweep the TRACKED holders first, not just the `Body_`-named children. `_build_cell_body`
	# names a holder from its anchor's ROUNDED position, so two holders over the same rounded
	# spot collide and Godot renames the newcomer `@Node3D@<id>` — which `begins_with("Body_")`
	# then misses. A missed holder is not merely leaked: body holders are detached ROOT siblings
	# (see _build_cell_body), so `_populate_cells`'s dict `.clear()` orphans it in the tree at its
	# last position, where it never scrolls again and overlaps whatever body lands on that spot.
	for h in _body_holders_by_cell.values():
		if h != null and is_instance_valid(h) and h.get_parent() == self:
			seen[h.get_instance_id()] = true
			stale.append(h)
	for child in get_children():
		if child.name.begins_with("Body_") and not seen.has(child.get_instance_id()):
			seen[child.get_instance_id()] = true
			stale.append(child)
	for anchor in _cells.values():
		for c in anchor.get_children():
			stale.append(c)
	for n in stale:
		n.get_parent().remove_child(n)
		n.queue_free()
	_populate_cells()
	# The DOCKED pair reads the same population the cells do, so it is stale for exactly as
	# long as they were — rebind it here rather than leaving it to the next cursor press.
	#
	# The navigator mounts this scene and injects a frame LATER (`add_child` -> `await
	# process_frame` -> `set_owned_characters`), so `_build_unit_info_cluster` ran while
	# `_injected_characters` was still null. Before ADR-0180 the fallback was a DIFFERENT
	# store, so the screen showed the owned roster in the cells and a `PartyRoster` unit in
	# the vitals — measured on the Gariland route as a Squire at HP 031 under a panel reading
	# "Marcus" at 081. It self-healed on the first cursor move, which is why it survived.
	#
	# With ONE population the pair can now only be LATE, never wrong — and this line is what
	# makes it not even late. It is also what makes an UNBOUND cluster correct: the build no
	# longer refuses to exist when the roster has not arrived yet (see
	# `_build_unit_info_cluster`), and this is where it gets bound.
	_update_vitals_for_selection()


## Tear down + rebuild ONLY the per-cell sort-value readout (the "SortVal" child), leaving
## the unit body/shadow/orb/box intact. This is the sort-page hot path (§12.3.5): [ ]/L2/R2
## change only the displayed stat COLUMN, so recompositing the sprite bodies every keypress
## (what rebuild_cells does) was the paging lag the user hit. Cheap: a handful of textured
## quads per cell, no SEQ/SHP body composite.
func rebuild_sort_values() -> void:
	if debug_bodies_only:
		return
	var units := _roster_characters()
	for row in range(ROWS):
		for col in range(COLS):
			var cell := Vector2i(col, row)
			var anchor: Node3D = _cells.get(cell)
			if anchor == null or not _populated.get(cell, false):
				continue
			var old: Node = anchor.get_node_or_null("SortVal")
			if old != null:
				anchor.remove_child(old)
				old.queue_free()
			var index := row * COLS + col
			var character = units[index] if index < units.size() else null
			if character != null:
				_build_cell_sort_value(anchor, character)


## An injected ordered roster (wayfinder #234 E): when the navigator hosts this view it
## passes the owned units (`CharacterCatalog.owned_units()`) directly — so the view shows
## the player's OWNED subset (Delita, an ENTD guest, is correctly absent). Null = fall
## back to self-discovery, which since ADR-0180 reads the SAME overlay.
var _injected_characters = null

## Row-granular scroll into an injected roster larger than the 8-cell grid (ADR-0081
## all-templates view). Counts TOP ROWS scrolled off; the grid shows `scroll_window`
## of the owned list. Fixed cells, no animation — a page of 8 or fewer never scrolls.
var scroll_offset := 0


## Bind the view to an explicit ordered roster and rebuild (the navigator injection seam).
## Build the 4x2 roster grid AFTER `_ready` — for a host that does not own one at boot but needs
## one later (#941: the map host has no grid until the player asks who fights on a deployment
## tile). The same three calls `_ready` makes behind [method owns_roster_grid], in the same order.
##
## Idempotent, keyed on `_cells`: a second call while a grid is up would leave the first grid's
## nodes parented and unreachable, which is the orphan `rebuild_cells` exists to sweep.
func build_roster_grid() -> void:
	if not _cells.is_empty():
		return
	_build_grid()
	_populate_cells()
	_build_box_trail()


## Is the 4x2 grid BUILT — cells, bodies, box trail?
##
## Worth asking, and not answerable from the selection: `selected_character()` reads the injected
## roster by INDEX and `_cell_has_unit` falls through to grid-bounds nav when nothing is populated,
## so a host with no grid at all still selects, still navigates, and still reports a character. The
## grid is what the player SEES, and this is the only question that asks about it (#941 — a seeded
## "never build it" passed every other assertion in the picker's rig).
func has_roster_grid() -> bool:
	return not _cells.is_empty()


## How many grid cells actually hold a unit. The companion of [method has_roster_grid]: the grid can
## exist and be empty, which is what an injected roster that never landed looks like.
func populated_cell_count() -> int:
	return _populated.size()


## Tear the lazily-built grid back down, returning the host to its no-grid state. The counterpart
## of [method build_roster_grid] and NOT a general teardown: it drops the cells, the bodies and the
## box trail, and leaves everything the host built at `_ready` (the band, the docked pair) alone.
func free_roster_grid() -> void:
	if _cells.is_empty():
		return
	# The pick-in latch is keyed by cell and carries body holders about to be freed; a latch that
	# outlived its grid would leave `pick_sliding()` true over nothing (#941 follow-up).
	_pick_slide_homes.clear()
	_pick_slide_body_offsets.clear()
	_pick_slide_active = false
	for holder in _body_holders_by_cell.values():
		if holder != null and is_instance_valid(holder) and holder.get_parent() == self:
			holder.get_parent().remove_child(holder)
			holder.queue_free()
	for child in get_children():
		if child.name.begins_with("Body_") or child.name == "CellGrid":
			remove_child(child)
			child.queue_free()
	# The trail owns its own root and rebuilds by replacing it, so it is dropped through that
	# handle rather than by name — `_build_box_trail` is the only other reader of it.
	if _trail_root != null and is_instance_valid(_trail_root):
		remove_child(_trail_root)
		_trail_root.queue_free()
	_trail_root = null
	_trail_slots.clear()
	_cells.clear()
	_cell_content.clear()
	_orb_mats_by_cell.clear()
	_orb_holders_by_cell.clear()
	_body_mats_by_cell.clear()
	_body_bbox_by_cell.clear()
	_body_holders_by_cell.clear()
	_populated.clear()


func set_owned_characters(characters: Array) -> void:
	_injected_characters = characters
	if is_inside_tree() and not Engine.is_editor_hint():
		rebuild_cells()


## The characters this view renders (up to the 8 grid cells): the injected owned list when
## the navigator supplied one, else the catalogue's owned overlay (standalone / isolated
## boot). ONE population either way.
##
## The fallback used to be the `/root/PartyRoster` autoload, and that is what put a
## hand-invented blank Squire called "Marcus" on a world-map Formation screen while the
## grid beside it held a real unit: the two branches answered with DIFFERENT casts, so a
## one-frame binding race (`_build_unit_info_cluster` running while `_injected_characters`
## is still null) rendered `party:0` instead of a late unit. With one population the race
## can only yield a LATE unit, never a wrong one — which is why ADR-0180 could make this
## fall through at all. The standing objection ("falling through would silently render a
## DIFFERENT roster — worse than rendering none") inverted: rendering `party:0..3` WAS the
## different roster.
func _roster_characters() -> Array:
	var source: Array = _injected_characters as Array if _injected_characters != null \
		else UIRoster.owned_units()
	if _injected_characters != null:
		return scroll_window(source, scroll_offset)
	return source.slice(0, ROWS * COLS)


# -----------------------------------------------------------------------------
# Vitals panel (#175): the bottom-left readout is the already-solved battle
# vitals window (§14.4) — HP/MP/CT gradient bars + Lv/Exp + portrait — reused
# wholesale via UIUnitInfoWindow.set_unit_view(). We only wire the SELECTED cell's
# roster values into it; the bar/fill maths and layout are the reused window's.
# -----------------------------------------------------------------------------

## Build the shared vitals + RIGHT-info (#176) pair via [UnitInfoCluster], DOCKED at
## the roster bottom (§14.6/§14.7). The SAME two instances the Status/detail screen
## reuses at its top layout — owning them here (instead of two inline builds) is what
## lets the ○-press transition SLIDE this real pair up (§15.5) rather than crossfade.
## Byte-identical to the old inline build: same @export placement (vitals_origin_px /
## info_origin_px), same corrected menu layout, same formation vitals rung
## (RP_HEADER_LABEL). The info nameplate's sub-element offsets now live in the shared
## UIUnitNameplate.apply_menu_layout (== the info_*_px @export defaults).
## Build the docked pair, and bind it if there is already a unit to bind.
##
## The build used to REFUSE when `_roster_characters()` was empty or the selected index was
## out of range — "no character, no cluster". That held only because the old fallback was the
## `PartyRoster` autoload, which is seeded at app boot and is therefore never empty; the
## refusal was load-bearing on a store ADR-0180 deleted. With the catalogue's owned overlay as
## the fallback, a host that injects a frame AFTER `add_child` (the coordinator, the
## navigator) builds against an empty overlay and would get no docked pair at all, ever.
##
## A screen owns its docked pair whether or not a unit is bound yet — which is what
## [method build_unit_info_cluster_unbound] already existed for, because the MAP host has no
## roster array to index and the same guard would have left it with nothing. `rebuild_cells`
## binds it the moment a roster arrives.
func _build_unit_info_cluster() -> void:
	build_unit_info_cluster_unbound()
	_update_vitals_for_selection()


## Build the docked vitals+nameplate pair WITHOUT binding a unit to it. Split out of
## [method _build_unit_info_cluster] because the two hosts learn which unit to show at different
## times: the roster host knows at build (the selected cell), the map host not until the tile
## cursor hovers one — and the roster-shaped guard above ("no character, no cluster") would leave
## the map host with no pair at all, since a battlefield has no roster array to index.
func build_unit_info_cluster_unbound() -> void:
	# The cluster is the registered ELEMENT root `formation.unit_cluster` (ADR-0088 Amendment 5
	# §4): a screen-anchored assembly owning the group slide + an <id>.origin group-nudge. Its
	# vitals + nameplate sub-elements register under it; placement stays via place_layout (below).
	_cluster = UnitInfoCluster.new({
		"id": "formation.unit_cluster",
		"rect": UI3Element.screen_anchored(),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_cluster.name = "UnitInfoCluster"
	add_child(_cluster)
	# Formation vitals sit on RP_HEADER_LABEL (11), the roster's near content rung — pass
	# it so the depth ordering is unchanged from the pre-cluster build.
	_cluster.build(PIXELS_PER_UNIT, Fold.owns(), RP_HEADER_LABEL)
	_cluster.place_layout({"vitals": vitals_origin_px, "nameplate": info_origin_px})
	_vitals_window = _cluster.vitals_panel()
	_info_root = _cluster.nameplate()


## Map a roster [Character] to a [UIUnitInfoWindow] view dict. Roster units are
## OUT of battle, so HP/MP are FULL (current == max == the progression's effective
## stat) and there is no battle CT (0 → empty CT bar). Identity/level/exp/brave/
## faith come off the Character; sprite id + job name resolve through the shared
## JobDatabase (same path the grid cell body uses) so panel and grid agree.
static func vitals_view_from_character(character) -> Dictionary:
	var prog = character.progression
	var job_id: String = prog.current_job_id
	var max_hp: int = prog.get_effective_hp()
	var max_mp: int = prog.get_effective_mp()
	var job: Dictionary = JobDatabase.get_job(job_id)
	return {
		"name": character.display_name,
		"job": job.get("name", job_id),
		"level": prog.level,
		"exp": prog.experience,
		"sprite_id": JobDatabase.get_sprite_id(job_id, character.is_female),
		# Front the unit's OWN portrait when it resolves to a template folder (uniques
		# + appearance-types, #205); a generic job-routed unit has no folder → "" →
		# display_from_template falls back to the job sprite (Squire face is correct there).
		"template_folder": CharacterTemplateResolver.resolve(character).get("template_folder", ""),
		"current_hp": max_hp, "max_hp": max_hp,
		"current_mp": max_mp, "max_mp": max_mp,
		"ct": 0, "has_ct": false,   # out-of-battle roster: no CT -> "---/---" + full bar (UnitInfoPresenter)
		"brave": prog.brave,
		"faith": prog.faith,
		"statuses": [],
	}


# -----------------------------------------------------------------------------
# RIGHT unit-info panel (#176, §14.6): the tan 9-slice window to the right of the
# vitals panel — a blue orb bullet + unit number + name / job (proportional
# FONT.BIN) + a zodiac glyph (RANGETILE §14.3) + Brave/Faith label+value. Unlike
# the reused vitals window this panel is not built in the port at all, so it is
# assembled here from the shared UI primitives: an opaque `UIFrame` for the chrome,
# the opaque FONT.BIN glyph path for text, the HUD digit font for numbers, and the
# per-unit orb sprite (§10) for the bullet. Faithfulness rule: FFT visuals + layout,
# OUR data — name/job/brave/faith/zodiac come off the Character/JobDatabase. Every
# piece is opaque + depth-writing on the ADR-0077 ladder so it occludes the folded
# subtractive band it sits on. Rebuilt (glyph tree) when the selection changes.
# -----------------------------------------------------------------------------

## Rebind the RIGHT unit-info panel (#176) for the selected unit. The nameplate is the
## cluster's shared instance now, so a selection change re-binds its view (the widget
## rebuilds its own glyph tree) instead of freeing + reconstructing a panel here.
func _rebind_info_panel() -> void:
	if _cluster == null or not is_instance_valid(_cluster):
		return
	var units := _roster_characters()
	var index := selected_cell.y * COLS + selected_cell.x
	if index < 0 or index >= units.size():
		return
	var character = units[index]
	if character == null or character.progression == null:
		return
	_cluster.set_nameplate_view(info_view_from_character(character, index + 1))


## Map a roster [Character] + its 1-based roster slot to the info-panel view dict.
## Name / job / brave / faith / zodiac are OUR data (faithfulness rule); the job
## name resolves through the shared JobDatabase (same path the grid body uses).
static func info_view_from_character(character, number: int) -> Dictionary:
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


## Pure x-advance (px) for one character under §14.6's hand-rolled proportional
## layout: a glyph advances by its own FONT.BIN width, but a SPACE uses the ROM's
## narrow space advance (DialogueBox.SPACE_WIDTH_PX = 4px) — NOT the full FONT.BIN
## space cell, which is why the info-panel name/job used to over-gap. Mirrors
## UIText._get_space_width (the fix the dialogue box already carries). Pure → unit-tests.
static func glyph_advance(font: UIFont, ch: String) -> float:
	if ch == " ":
		return DialogueBox.SPACE_WIDTH_PX
	var info := font.get_char_info(font.get_char_index(ch))
	return float(info.get("width", font.char_width))


# -----------------------------------------------------------------------------
# Sort column + header chrome (#174, §12.3 / §14.6): the per-cell "Hp cur/max"
# readout for the active sort key, plus the top sort-tab header (labels + L2/R2).
# Text REUSES the HUD digit font (FRAMEFONT via NumberFont), the RANGETILE word
# labels, and the shared index/CLUT `vitals_sprite` shader — the SAME path the
# reused vitals window (#175) draws HP/MP/CT with, so grid + panel read alike.
# Header labels + L2/R2 use the menu proportional font via UIText. (Live L2/R2
# paging between sort keys is a separate interaction effort — #167 out-of-scope.)
# -----------------------------------------------------------------------------

## The per-cell sort readout for `key`, straight off the roster Character. Pure so
## it unit-tests without a scene. Roster units are OUT of battle, so HP/MP read
## full (cur == max == effective) and CT reads dashes — the vitals-view rule (#175).
## Three readout shapes (§12.3.5, oracle-derived):
##   * "pair" — Hp/Mp/Ct: one word label + a cur/max digit pair (CT shows "---").
##   * "duo"  — Lv.Exp / Br.Fa: TWO independently-labelled 2-digit values side by
##     side ("Lv.99 Exp.05", "Br.70 Fa.70"), each with its own atlas word label.
static func sort_value_from_character(character, key: String) -> Dictionary:
	var prog = character.progression
	if prog == null:
		return {}   # a progression-less appearance-type/unique (ADR-0081) has no stats to sort by
	match key:
		"hp":
			var hp: int = prog.get_effective_hp()
			return {"label": "Hp", "kind": "pair", "cur": hp, "max": hp}
		"mp":
			var mp: int = prog.get_effective_mp()
			return {"label": "Mp", "kind": "pair", "cur": mp, "max": mp}
		"ct":
			# Out of battle the roster has no CT: the oracle reads "Ct ---/---" (dash glyphs
			# in both the cur and max slots, same cur/max stagger as HP/MP). §12.3.5.
			return {"label": "Ct", "kind": "pair", "cur": 0, "max": 0, "dashes": true}
		"lv_exp":
			return {"kind": "duo",
				"left": {"label": "Lv.", "text": str(prog.level)},
				"right": {"label": "Exp.", "text": str(prog.experience)}}
		"brave_faith":
			# "Br."/"Fa." — the atlas "Br"/"Fa" cells carry NO period (unlike "Lv."/"Exp."),
			# so the oracle's trailing dot is the shared 3x3 RANGETILE period glyph, appended.
			return {"kind": "duo",
				"left": {"label": "Br", "text": str(prog.brave), "dot": true},
				"right": {"label": "Fa", "text": str(prog.faith), "dot": true}}
	return {}


## The per-cell fill-swatch stat index for a sort key (§12.3): 0/1/2 for Hp/Mp/Ct, or
## −1 for Lv/Exp/Br.Fa (which draw NO bar). ROM (sort-value emitter @0x80118244): the
## swatch is a FIXED-width textured prim CLUT-keyed to the active sort column's 0..2
## selector — not an HP-proportional gouraud fill. Roster units are out of battle (full
## vitals), so the swatch always draws full; the port colours it by this stat's gradient.
static func cell_sort_bar_stat(key: String) -> int:
	return int(SORT_BAR_STAT.get(key, -1))


## The sort key one page from `key` in direction `dir` (+1 = R2/next/rightward,
## -1 = L2/prev/leftward), WRAPPING at the ends (§12.3.5: R2 off Br.Fa → Hp). Pure so
## the paging state machine unit-tests without input. Unknown key falls back to the first.
static func next_sort_key(key: String, dir: int) -> String:
	var i := SORT_KEYS.find(key)
	if i < 0:
		return String(SORT_KEYS[0])
	return String(SORT_KEYS[(i + dir + SORT_KEYS.size()) % SORT_KEYS.size()])


## Which header LABEL-GLYPH indices highlight for `key` (§12.3.5): [n] for a plain
## tab, [n, m] for a combined tab (Lv.+Exp., Br.+Fa.). Empty if `key` isn't a sort key.
static func sort_tab_label_indices(key: String) -> Array:
	return SORT_KEY_LABEL_INDICES.get(key, [])


## Which sort key `key` pages to (index into SORT_KEYS), or -1 if `key` isn't a sort key.
static func sort_tab_active_index(key: String) -> int:
	return SORT_KEYS.find(key)


## Lazily build the shared text assets (HUD digit font, RANGETILE label atlas, and
## the MENU CLUT as a 16x1 palette row) — created once, reused by every cell + the
## header. The CLUT is the vitals window's MENU_CLUT (identical digit look).
func _ensure_text_assets() -> void:
	if _digit_font != null:
		return
	_digit_font = NumberFont.new()
	_rt_atlas = RangeTileAtlas.new()
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	var clut: PackedColorArray = UIUnitInfoWindow.MENU_CLUT
	for i in 16:
		img.set_pixel(i, 0, clut[i] if i < clut.size() else Color(0, 0, 0, 0))
	_digit_pal = ImageTexture.create_from_image(img)
	# Header CLUTs — the REAL 16-colour VRAM palettes the roster header samples
	# (§12.3.2), ROM-parsed from the LBA 0xE68 asset tail (0x7c3c/0x7cbc/0x7d7c).
	# The glyph's internal fill (atlas index 4) is a REAL colour — the bar's own
	# tan for inactive (so it blends in), dark for the active tab — giving the
	# genuine 2-tone emboss (the first pass's single-ink punch-out was the bug).
	_header_ink_pal = _palette_from_colors(_rt_atlas.header_clut_colors("inactive_label"))
	_header_hilite_pal = _palette_from_colors(_rt_atlas.header_clut_colors("active_label"))
	_header_btn_pal = _palette_from_colors(_rt_atlas.header_clut_colors("button"))
	_header_pressed_pal = _palette_from_colors(_rt_atlas.header_clut_colors("button_pressed"))
	# §15.21 background CLUTs (the per-index swap targets, shared with DetailScene).
	_header_ink_pal_bg = _palette_from_colors(UIWindowPalettes.BG_FOR_7C3C)     # 0x7c3c→0x7d3c
	_header_hilite_pal_bg = _palette_from_colors(UIWindowPalettes.BG_FOR_7CBC)  # 0x7cbc→0x7c7c
	_header_btn_pal_bg = _palette_from_colors(UIWindowPalettes.BG_FOR_7D7C)     # 0x7d7c→0x7dfc


## A 16x1 CLUT texture from a 16-Color array (the `vitals_sprite` shader samples
## it). Index 0 stays the atlas transparent key. Pure so the header CLUTs test
## without a scene.
static func _palette_from_colors(colors: Array) -> ImageTexture:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		img.set_pixel(i, 0, colors[i] if i < colors.size() else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


## Mount one index-atlas glyph cell (a FRAMEFONT digit or a RANGETILE word label)
## at cell-relative top-left `pos_px` under `anchor`, through the shared index/CLUT
## sprite shader at `priority`. `scale` sizes the quad (positions are pre-scaled).
## When `opaque` (ADR-0077), the glyph is drawn through the OPAQUE depth-writing text shader and mounted
## at real Z (rung = `priority`), so a folded prim beneath it (the gold box under the sort value) is
## occluded behind the text instead of clobbered by Pass C, and overlapping caption pieces stack by real
## camera-Z (distinct rung) rather than render_priority. The sort-value readout AND the sort-tab header
## glyphs both use `opaque` = true: with vitals_sprite now plain opaque (depth-tested), an `opaque` = false
## glyph at z=0 would z-fight the floor, so header text must ride its RP_* rung like everything else.
func _mount_glyph(anchor: Node3D, tex: Texture2D, cell: Rect2, pos_px: Vector2,
		scale: float, priority: int, palette: Texture2D = null, opaque: bool = false,
		palette_bg: Texture2D = null) -> ShaderMaterial:
	if tex == null or cell.size == Vector2.ZERO:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = load(_TEXT_OPAQUE_SHADER if opaque else _VITALS_SPRITE_SHADER)
	mat.set_shader_parameter("mode", 0)
	mat.set_shader_parameter("index_atlas", tex)
	mat.set_shader_parameter("atlas_size", Vector2(tex.get_width(), tex.get_height()))
	mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y))
	mat.set_shader_parameter("palette_tex", palette if palette != null else _digit_pal)
	mat.set_shader_parameter("brightness", 1.0)
	# §15.21 "send to background": arm the swap CLUT (null until a caller passes one). foreground default.
	if palette_bg != null:
		mat.set_shader_parameter("palette_bg_tex", palette_bg)
	mat.set_shader_parameter("backgrounded", 0.0)
	if not opaque:
		mat.render_priority = priority
	_mount_quad(anchor, pos_px, cell.size * scale, mat, priority if opaque else 0)
	return mat


## The per-cell readout for the active sort key (§12.3 / §12.3.5), placed relative to
## the cell. Two shapes: a "pair" (Hp/Mp/Ct → one word label + a cur/max digit pair,
## plus the coloured fill swatch), or a "duo" (Lv.Exp / Br.Fa → two labelled 2-digit
## values side by side, no bar). Byte-approximate + headful-tuned vs the oracle.
func _build_cell_sort_value(anchor: Node3D, character) -> void:
	_ensure_text_assets()
	var readout := sort_value_from_character(character, active_sort_key)
	if readout.is_empty():
		return
	# All readout glyphs (+ the fill swatch) go under ONE "SortVal" child of the cell, so a
	# sort-page can tear down and rebuild JUST the readout (rebuild_sort_values) without
	# recompositing the unit body/shadow/orb — the [ ]/L2/R2 hot path (§12.3.5 perf).
	var sv := Node3D.new()
	sv.name = "SortVal"
	sv.visible = _cell_readouts_visible   # hidden while the detail overlay is up (§15.5); rebuilds honour it
	anchor.add_child(sv)
	if readout.get("kind") == "duo":
		# Two labelled 2-digit values ("Lv.99 Exp.05"). No fill swatch for these keys.
		# The LEFT group sits on the label row; the RIGHT group staggers down-right
		# (`sort_duo_stagger_dy`), mirroring the pair cur/max drop (§12.3.5).
		_mount_duo_group(sv, readout["left"], sort_label_offset_px.x, 0.0)
		_mount_duo_group(sv, readout["right"], sort_duo_split_px, sort_duo_stagger_dy)
		return
	# Word label ("Hp"/"Mp"/"Ct") to the left of the number.
	var label_name: String = readout.get("label", "")
	if label_name != "" and _rt_atlas.has_label(label_name):
		_mount_glyph(sv, _rt_atlas.texture, _rt_atlas.label_rect(label_name),
			sort_label_offset_px, 1.0, RP_SORT_VALUE, null, true)
	# The number: a cur/max pair (HP/MP/CT). Zero-pad to 3 digits (`044/044`, `038/038`).
	# Out-of-battle CT has no value → the oracle reads "---/---" (dash glyphs, same slots).
	var placements: Array
	if readout.get("dashes", false):
		placements = _digit_font.place_pair_text("---", "---",
			sort_value_divider_px.x, sort_value_divider_px.y,
			Vector2(0, 2), Vector2(5, 5), sort_value_scale)
	else:
		placements = _digit_font.place_pair(int(readout["cur"]), int(readout["max"]),
			sort_value_divider_px.x, sort_value_divider_px.y,
			Vector2(0, 2), Vector2(5, 5), sort_value_scale, 3)
	for g in placements:
		_mount_glyph(sv, _digit_font.texture, g["cell"], g["pos"], sort_value_scale, RP_SORT_VALUE, null, true)
	# The fill swatch for the active sort key's stat (Hp/Mp/Ct only), fill-only, under the
	# digits (the top `cur` overlaps its upper edge, exactly as the oracle framebuffer shows).
	_mount_cell_bar(sv, cell_sort_bar_stat(active_sort_key))


## One "Lv.99"/"Exp.05"/"Br.70"/"Fa.70" group of a duo readout (§12.3.5): the atlas
## word label at cell-x `x`, then its 2-digit value `sort_duo_value_gap_px` past the
## label's right edge. `dy` drops the whole group (label + dot + value) below the label
## row — the LEFT group passes 0, the RIGHT group the stagger so the two values sit
## down-right of each other exactly as the oracle draws them. The label glyphs "Lv."/
## "Exp." bake their own period; "Br"/"Fa" don't, so `part.dot` appends the shared 3x3
## RANGETILE period.
func _mount_duo_group(anchor: Node3D, part: Dictionary, x: float, dy: float) -> void:
	var label_name: String = part.get("label", "")
	var value_x := x
	if label_name != "" and _rt_atlas.has_label(label_name):
		var lrect := _rt_atlas.label_rect(label_name)
		_mount_glyph(anchor, _rt_atlas.texture, lrect,
			Vector2(x, sort_label_offset_px.y + dy), 1.0, RP_SORT_VALUE, null, true)
		value_x = x + lrect.size.x
		if part.get("dot", false):
			# The trailing "." — the shared RANGETILE period glyph (§12.3.3), baseline-aligned
			# to the label's bottom, so "Br"/"Fa" read "Br."/"Fa." like the oracle.
			_mount_glyph(anchor, _rt_atlas.texture, CELL_PERIOD_GLYPH,
				Vector2(value_x, sort_label_offset_px.y + dy + lrect.size.y - CELL_PERIOD_GLYPH.size.y),
				1.0, RP_SORT_VALUE, null, true)
			# ASYMMETRIC spacing (§12.3.5): the "Lv."/"Exp." values HUG their baked-period label,
			# but "Br."/"Fa." sit a SPACE past the appended dot ("Br. 70", not "Br.70"). Only the
			# dot case gets this extra advance so Lv.Exp stays tight.
			value_x += CELL_PERIOD_GLYPH.size.x + sort_duo_dot_space_px
		value_x += sort_duo_value_gap_px
	for g in _digit_font.place_number(str(part.get("text", "")),
			value_x, sort_value_divider_px.y + dy, NumberFont.SMALL, false, sort_value_scale, 2):
		_mount_glyph(anchor, _digit_font.texture, g["cell"], g["pos"], sort_value_scale, RP_SORT_VALUE, null, true)


## The per-cell HP/MP/CT fill swatch (§12.3): the FILL-ONLY gouraud band for the active
## sort key's stat, drawn through the SAME shader + shared RANGETILE swatch as the vitals
## panel bar but WITHOUT the dim casing/track behind it. ROM (sort-value emitter
## @0x80118244): a single fixed-width textured swatch CLUT-keyed to the sort column — no
## separate frame prim, no HP-proportional length. Roster units are out of battle (full
## vitals), so it always draws full (`fill_frac` = 1). Opaque + depth-writing at
## RP_CELL_BAR (over the orb, under the digits) — ADR-0077, no ALPHA (the shader discards).
func _mount_cell_bar(anchor: Node3D, stat: int) -> void:
	if stat < 0 or _rt_atlas == null:
		return
	var sw := _rt_atlas.bar_swatch_rect()
	if sw.size == Vector2.ZERO:
		return
	var tex := _rt_atlas.texture
	var mat := ShaderMaterial.new()
	mat.shader = load(_VITALS_BAR_SHADER)
	mat.set_shader_parameter("index_atlas", tex)
	mat.set_shader_parameter("atlas_size", Vector2(tex.get_width(), tex.get_height()))
	mat.set_shader_parameter("cell", Vector4(sw.position.x, sw.position.y, sw.size.x, sw.size.y))
	var cl: Color = BAR_GRAD_LEFT[stat] if stat < BAR_GRAD_LEFT.size() else Color.WHITE
	var cr: Color = BAR_GRAD_RIGHT[stat] if stat < BAR_GRAD_RIGHT.size() else Color.WHITE
	mat.set_shader_parameter("color_left", Vector3(cl.r, cl.g, cl.b))
	mat.set_shader_parameter("color_right", Vector3(cr.r, cr.g, cr.b))
	mat.set_shader_parameter("fill_frac", 1.0)
	mat.set_shader_parameter("brightness", 1.0)
	# The shader masks to the swatch interior (inset BAR_INTERIOR_INSET), so place the whole
	# swatch quad shifted up-left by that inset → the band lands at sort_bar_pos_px.
	_mount_quad(anchor, sort_bar_pos_px - BAR_INTERIOR_INSET, sw.size, mat, RP_CELL_BAR)


## The sort-tab header (§12.3.1): three menu windows on the stone floor — a central
## TAN bar holding the six sort labels (textured menu-atlas glyphs, the active key
## highlighted white-on-dark), flanked by two blue-grey L2/R2 paging buttons.
## Persistent on its own root, rebuilt on a header-knob scrub — NOT part of the cell
## rebuild. This REPLACES the first pass's proportional-font-on-gradient model,
## which was wrong: the header is textured glyphs over menu windows (Ghidra-
## decompiled builder FUN_80112c88 + the settled roster oracle).
func _build_sort_header() -> void:
	if _header_root != null and is_instance_valid(_header_root):
		_header_root.queue_free()
	# The header is HOUSED in the registered element `formation.sort_header` (ADR-0088):
	# a screen-anchored ASSEMBLY (chrome + label glyphs + L2/R2 buttons all mount at
	# absolute display px under it — rect = the display screen box, so the element
	# origin sits at zero and _mount_glyph/_add_header_frame stay untouched). UNCLIPPED
	# declares the top-of-screen chrome's never-scissored answer. Rebuilt per sort page
	# (the element is re-created fresh — the detail.compare pattern).
	_header_root = UI3Element.new({
		"id": "formation.sort_header",
		"rect": UI3Element.screen_anchored(),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_header_root.name = "SortHeader"
	add_child(_header_root)
	_ensure_text_assets()

	# (D) Tan sort-bar window: the FFT menu-window 9-slice (FRAME.BIN → frame.tga),
	# the SAME textured UIFrame the vitals/info panels + dialogue draw — NOT flat
	# colour bands. PROVEN from the VRAM oracle (§12.3.3): the live tan-bar prims
	# sample tpage 0x0019 (VRAM 576,256, which renders byte-identical to frame.tga)
	# through CLUT 0x7C3C — a real 4-sided bordered window with a bright top bevel,
	# a dithered/textured tan fill, and a dark drop-shadow. This replaces the flat
	# horizontal bands (which had no left/right edges — the "no right side" bug).
	_add_header_frame(header_tan_rect_px)

	var labels := _rt_atlas.header_labels()
	# The active key lights ONE or TWO label glyphs (§12.3.5): the combined Lv.Exp /
	# Br.Fa tabs highlight both their cells at once. (Br.Fa is already one label entry
	# carrying its x2 "Fa" cell, so it's a single index; Lv.+Exp. are two entries.)
	var active_set: Array = sort_tab_label_indices(active_sort_key)

	# (C) No separate active-tab box. The "dark box" behind the active label is the
	# label cell's OWN index-4 fill field: the inactive CLUT (0x7C3C) paints idx4
	# tan (blending into the bar) and the active CLUT (0x7CBC) paints it near-black
	# while the ink (idx1) flips dark→white — one CLUT swap, no extra primitive
	# (PROVEN via the VRAM CLUT decode + HP_LABEL_FIXTURE, §12.3.3). Rendering the
	# active cell through the active CLUT (below) IS the highlight mechanism.

	# (B) Six sort labels: each drawn from its OWN header atlas cell (§12.3.3, from
	# the live prims — NOT the vitals WORD_LABELS, whose "Exp."/"Fa" cells differ) at
	# its live-exact screen x, through the REAL CLUTs — inactive_label (0x7c3c: dark
	# ink on the bar's tan) or, for the active tab, active_label (0x7cbc: white ink
	# on the cell's now-dark idx-4 field = the highlight). The "Br.Fa" tab adds a real
	# 3x3 PERIOD GLYPH (its own cell + position) + the "Fa" cell — the period is a
	# textured atlas glyph through the label CLUT, not a hand-placed solid quad.
	for i in labels.size():
		var l: Dictionary = labels[i]
		var pal: Texture2D = _header_hilite_pal if active_set.has(i) else _header_ink_pal
		# §15.21: the matching BACKGROUND CLUT (active tab → 0x7c7c, inactive label → 0x7d3c).
		var pal_bg: Texture2D = _header_hilite_pal_bg if active_set.has(i) else _header_ink_pal_bg
		var cell: Array = l.get("cell", [])
		if cell.size() == 4:
			_mount_glyph(_header_root, _rt_atlas.texture, _cell_rect(cell),
				Vector2(float(l.get("x", 0)), header_label_y_px), 1.0, RP_HEADER_LABEL, pal, true, pal_bg)
		if l.has("x2_name"):
			var dot: Dictionary = l.get("dot", {})
			var dcell: Array = dot.get("cell", [])
			if dcell.size() == 4:
				_mount_glyph(_header_root, _rt_atlas.texture, _cell_rect(dcell),
					Vector2(float(dot.get("x", 0)), float(dot.get("y", header_label_y_px))),
					1.0, RP_HEADER_LABEL, pal, true, pal_bg)
			var x2cell: Array = l.get("x2_cell", [])
			if x2cell.size() == 4:
				_mount_glyph(_header_root, _rt_atlas.texture, _cell_rect(x2cell),
					Vector2(float(l.get("x2", 0)), header_label_y_px), 1.0, RP_HEADER_LABEL, pal, true, pal_bg)

	# (A) L2/R2 buttons: textured RANGETILE atlas cells (3-slice window frame + the
	# baked "◄L2"/"R2►" caption) through the real button CLUT (0x7d7c) — REPLACES the
	# flat-quad + drawn-triangle + UIText caption path (that was the rejected build).
	# On a live L2/R2 page the tapped button flashes its PRESSED look (§12.3.5, oracle-
	# confirmed): the button CLUT swaps 0x7d7c blue-grey → 0x7e7c warm tan and it nudges
	# down `HEADER_BTN_PRESSED_DY` px. `_pressed_side` names it for `_pressed_frames`.
	var btns := _rt_atlas.header_buttons()
	if btns.has("left"):
		_add_textured_button(btns["left"], _pressed_side == "left")
	if btns.has("right"):
		_add_textured_button(btns["right"], _pressed_side == "right")

	# §15.21: collect every header ShaderMaterial (glyphs + the frame's material_override) and
	# (re)apply the current backgrounded state — so a sort-page rebuild preserves the swap while the
	# detail overlay is up (the header is torn down + rebuilt on every L2/R2 page / selection change).
	_header_mats.clear()
	_collect_header_mats(_header_root)
	var v := 1.0 if _header_backgrounded else 0.0
	for m in _header_mats:
		m.set_shader_parameter("backgrounded", v)

	# §15.22: honour the visibility latch — a rebuild while the detail overlay is up must stay hidden.
	_header_root.visible = _header_visible


## Walk `node`'s subtree collecting every ShaderMaterial the header draws through (the glyph quads
## mount via `_mount_quad` → `material_override`; the UIFrame sets its own material as its mesh's
## `material_override` too), so `set_backgrounded` can flip them all uniformly (§15.21).
func _collect_header_mats(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D and node.material_override is ShaderMaterial:
		_header_mats.append(node.material_override)
	for c in node.get_children():
		_collect_header_mats(c)


## §15.21 "send window to background": swap the sort-header (L2/R2 buttons + Hp/Mp… tab glyphs + the
## tan bar) to its BACKGROUND CLUTs when a menu/screen (the detail overlay) takes focus over the roster
## — the per-index swap mirroring DetailScene.set_backgrounded. Idempotent; preserved across rebuilds.
func set_backgrounded(on: bool) -> void:
	_header_backgrounded = on
	var v := 1.0 if on else 0.0
	for m in _header_mats:
		m.set_shader_parameter("backgrounded", v)


func is_backgrounded() -> bool:
	return _header_backgrounded


## §15.22: hide the WHOLE sort-header (tan bar + Hp/Mp… tab glyphs + the L2/R2 buttons) while the
## Status/detail overlay is up — the real Status screen shows only its own ◄L1/R1► corner buttons,
## never the roster header. Latched (mirrors `set_cell_readouts_visible`): a sort-page rebuild
## (`_build_sort_header`) re-reads `_header_visible` so a fresh `_header_root` stays hidden.
func set_header_visible(shown: bool) -> void:
	_header_visible = shown
	if _header_root != null and is_instance_valid(_header_root):
		_header_root.visible = shown


func is_header_visible() -> bool:
	return _header_visible


## One L2/R2 button as textured atlas cells (§12.3.2): a 3-slice window frame + a
## baked caption, all sampling RANGETILE through the button CLUT. `btn` =
## {origin_x, y, pieces:[[dx,dy,u,v,w,h]]} (frame pieces at v=128, captions at v<128).
## When `pressed` (§12.3.5) the whole button samples the PRESSED CLUT (0x7e7c warm tan)
## and drops `HEADER_BTN_PRESSED_DY` px — the momentary "pressed-in" flash on an L2/R2 tap.
func _add_textured_button(btn: Dictionary, pressed: bool = false) -> void:
	var ox: float = float(btn.get("origin_x", 0))
	var oy: float = float(btn.get("y", 0)) + (HEADER_BTN_PRESSED_DY if pressed else 0.0)
	var pal: Texture2D = _header_pressed_pal if pressed else _header_btn_pal
	# The caption pieces OVERLAP: the "◄L2"/"R2►" base cell and the digit/arrow cells
	# share screen columns (the ROM draws the digit ON TOP of the base — see §12.3.3).
	# The caption pieces OVERLAP, so they need a genuine near→far ORDER. Per ADR-0077 that is real
	# camera-Z, not render_priority: each piece mounts (opaque, depth-writing) at DepthMode.rung_z(RP_HEADER_BAR + i),
	# so a monotonically increasing rung draws frame first, then each caption piece in ROM order, later on
	# top — a faithful painter's stack that falls out of depth, with no coincident-Z tie for the sort to garble.
	# §15.21: the L2/R2 caption swaps 0x7d7c→0x7dfc when backgrounded. The PRESSED variant is a
	# transient flash on a live tap — no bg twin, so pass null (its own CLUT stays foreground).
	var pal_bg: Texture2D = null if pressed else _header_btn_pal_bg
	var i := 0
	for p in btn.get("pieces", []):
		_mount_glyph(_header_root, _rt_atlas.texture,
			Rect2(float(p[2]), float(p[3]), float(p[4]), float(p[5])),
			Vector2(ox + float(p[0]), oy + float(p[1])), 1.0, RP_HEADER_BAR + i, pal, true, pal_bg)
		i += 1


## Rect2 from a manifest cell array `[u, v, w, h]` (sort-tab labels / period glyph).
func _cell_rect(cell: Array) -> Rect2:
	return Rect2(float(cell[0]), float(cell[1]), float(cell[2]), float(cell[3]))


## The tan sort-bar window: the shared FFT menu-window 9-slice (`frame.tga` =
## FRAME.BIN, the graphic at VRAM 576,256 the oracle proved this bar samples),
## rendered through the SAME `UIFrame` the vitals/info panels + dialogue use.
## Mirror-the-sibling (effect-parity §B): a real 4-sided bordered window with the
## textured tan fill + top bevel, NOT flat bands. `rect` = x,y,w,h in virtual px.
func _add_header_frame(rect: Vector4) -> void:
	var frame := UIFrame.new()
	_header_root.add_child(frame)                       # _ready builds mesh + material
	frame.pixels_per_unit = PIXELS_PER_UNIT
	frame.pixel_aspect_ratio = 1.0                      # formation places chrome 1:1 (no PAR)
	frame.frame_size = Vector2(rect.z, rect.w)          # last: triggers _update_mesh with all set
	# Real camera-Z (ADR-0077): the tan bar sits on the header-bar rung, in front of the floor and
	# behind the labels — ordering by depth, not render_priority.
	frame.position = screen_to_world(rect.x, rect.y) + Vector3(0.0, 0.0, DepthMode.rung_z(RP_HEADER_BAR))
	# §15.21: arm the frame's RGB→index remap (pre-baked-RGB frame nearest-matches 0x7c3c → 0x7d3c
	# when backgrounded). Loaded INACTIVE (backgrounded 0); set_backgrounded flips it. UIFrame sets its
	# material as `_mesh_instance.material_override`, so the end-of-header `_collect_header_mats` walk
	# picks it up alongside the glyphs — no explicit append needed here.
	var m := frame.get_material()
	if m != null:
		m.set_shader_parameter("fg_palette", UIWindowPalettes.FRAME_FG_7C3C)
		m.set_shader_parameter("bg_palette", UIWindowPalettes.FRAME_BG_7D3C)
		m.set_shader_parameter("palette_count", 16)
		m.set_shader_parameter("backgrounded", 0.0)


## The per-unit drop shadow (§12): a subtractive feet decal, faithful to the roster
## body builder FUN_8011814c, which draws — after the sprite — a SECOND primitive at
## the feet (struct 0x8018c704) with tpage GetTPage(abr=2, 0x3c0,0x100) = 0x5F (ABR
## mode 2, subtractive) at OT bucket param_3-1 = 5: behind the body (bucket 6), above
## the gold box (buckets 3/4). It is the same subtractive blob as the battle unit
## shadow (the ROM 20x20 radial texel unit_shadow.png), here drawn FLAT in screen space
## (no terrain drape / OT depth / billboard — ordered by the RP_* ladder). We centre it
## at the feet and squash the round texel to an ellipse to match t04.png.
func _build_cell_shadow(anchor: Node3D) -> void:
	# Fold member on the fork (ADR-0077): the shadow overlaps the gold box at the feet, so it MUST fold
	# alongside it (else Pass C's coverage-discard clobbers the shadow wherever the box drew). Its real-Z
	# rung (RP_UNIT_SHADOW, behind the body) makes the body occlude the blob's top → the bottom crescent.
	var folded := Fold.owns()
	var mat := ShaderMaterial.new()
	mat.shader = fold_shader_for("shadow")
	mat.set_shader_parameter("shadow_tex", _cached_asset_tex(_SHADOW_TEX))
	mat.set_shader_parameter("intensity", shadow_intensity)  # uniform name mirrors shadow_blob
	if not folded:
		mat.render_priority = RP_UNIT_SHADOW
	# Fully DERIVED from the ROM shadow rect (§7): cell-relative top-left (19,34),
	# size 20×10 (the 2:1 squash of the 20×20 texel). It's a plain textured quad —
	# no compositor — so once the body is ROM-placed the shadow falls out. The
	# rect is relative to the body rect, hence to the cell, so subtract the cell
	# origin from the (col0,row0) ROM shadow rect to get the cell-relative anchor.
	# Feet-relative: shadow centre = the standing point + tunable offset. Back off
	# half-size for the top-left mount anchor.
	var centre := feet_target_px + shadow_feet_offset_px
	var top_left := centre - shadow_size_px * 0.5
	var mi := _mount_quad(anchor, top_left, shadow_size_px, mat, RP_UNIT_SHADOW)
	if folded:
		Fold.add(mi, mat, DepthMode.rung_z(RP_UNIT_SHADOW))


## Drive the shared SEQ/SHP pipeline (ADR-0019/0021/0022) to render one static,
## un-mirrored TYPE1 seq-2 "Face Front" frame (§14.1) for a roster unit — its own
## sprite + palette via the game's job→sprite resolution (NOT the per-class
## UNIT.BIN atlas). Mirrors Unit.gd's sprite setup / SequenceViewer's standalone
## use of SpriteLayerManager (no Unit node needed).
# A body-material TEMPLATE built once per view and DUPLICATED per cell (perf).
# `UnitMaterial.for_variant` pulls unit.tres AND its ext_resources (the shader +
# the 256×488 WEP1/EFF1 TGAs) off disk; nothing held the base alive between
# rebuilds, so every scroll re-read it ~24 ms × 8 cells ≈ 200 ms (the scroll
# hitch). Caching the fully-configured base (shader swapped, render_priority set)
# makes a scroll a cheap `.duplicate()` per cell (~0.3 ms) and keeps its shared
# textures resident. Per-cell params (type1_tex, ambient_brightness, …) still
# diverge on the duplicate exactly as before — render is byte-identical.
var _body_material_template: ShaderMaterial = null

## Per-folder body sheet + palette texture cache (immutable sheets) — a scroll
## re-shows the same sheets through the 8-cell window, so keep the Texture2D objects
## resident instead of forcing a disk re-decode each rebuild. See `_build_cell_body`.
var _body_tex_cache := {}

## Fixed per-cell chrome textures (ORB/shadow) keyed by path — const-path assets the
## cell builders re-`load()` on every rebuild; nothing holds them resident between
## rebuilds so each scroll re-decodes them. Cache keeps them alive (map hit on re-show).
var _asset_tex_cache := {}
func _cached_asset_tex(path: String) -> Texture2D:
	if not _asset_tex_cache.has(path):
		_asset_tex_cache[path] = load(path)
	return _asset_tex_cache[path]

## The lazily-built, cached body-material template (see `_body_material_template`).
func _body_mat_template() -> ShaderMaterial:
	if _body_material_template == null:
		# The FLAT variant (ADR-0189): the roster is a flat ortho scene, so the battle
		# compositor's OT depth and PAR anchor stretch are meaningless here. Which shader
		# that is, and that unit.tres's authored tile params carry onto it, are Sprite
		# Rig's business — this screen asks for a blend, not a file.
		var base := UnitMaterial.for_variant(
			UnitMaterialVariant.FLAT, UnitAssets.base_material())
		# No render_priority. It draws over the ground box and under the orb glow because its
		# holder sits at DepthMode.rung_z(RP_UNIT_BODY) and the variant writes depth — one Z,
		# per ADR-0077. The old comment here said "painter's order — RP_* ladder", which was
		# the pre-0077 framing on the very prim the ADR moved onto depth first (#634).
		_body_material_template = base
	return _body_material_template

func _build_cell_body(anchor: Node3D, character, cell: Vector2i) -> void:
	# Route through the ONE template resolver seam (ADR-0072/0081): a unique or
	# appearance-type renders its OWN sheet + seq from the template folder; a generic
	# job-routes as before. Drops the inline JobDatabase lookup that made every unit
	# (uniques included) render as its job sprite.
	var render := resolve_body_render(character)
	if not render.ok:
		push_warning("[Formation] no sprite for %s" % character.slug)
		return
	var seq_type: String = render.seq_type
	var shp_type: String = render.shp_type
	var animation_set := AnimationDatabase.get_set(seq_type, shp_type)
	if animation_set == null or animation_set.type1_seq.is_empty():
		push_warning("[Formation] no animation set for %s (%s/%s)" % [character.slug, seq_type, shp_type])
		return

	# Holder at the cell-relative feet anchor. billboard() preserves the model
	# basis scale, so scaling the holder sizes the sprite; a small +Z nudge lifts
	# the depth-writing unit shader clear of the background quad. Parented to the
	# scene root (not the anchor) so the scale doesn't compound the anchor xform.
	var holder := Node3D.new()
	holder.name = "Body_%d_%d" % [anchor.position.x, anchor.position.y]
	add_child(holder)
	# Track the holder per cell so the Equip slide (§15.23) can move it in lockstep with the
	# anchor — the anchor carries the orb/shadow (its children) but the body holder is a
	# detached ROOT sibling, so it needs its own reposition or the unit BODY stays docked
	# while only the orb slides. See begin_equip_slide()/play_equip_slide().
	_body_holders_by_cell[cell] = holder

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	# Duplicate the cached, fully-configured template (shader + render_priority already
	# set) instead of re-loading unit.tres per cell — the scroll-hitch fix. SpriteLayerManager
	# drives the per-cell params on the duplicate unchanged.
	var material: ShaderMaterial = _body_mat_template().duplicate()
	# §16: the unit body takes a FLAT spatial-falloff multiply (the SAME [80,128] pool
	# the orb samples, at the body centre) — a far unit renders uniformly dimmer. Drive
	# the compositor's ambient_brightness from the shared falloff (÷128 ⇒ [0.625,1.0]).
	# Evaluated off the SNAPPED selected_cell — coherent with the snapped orbs/box until
	# the box-glide-locked pool ease lands (§16.1 motion-fidelity, deferred).
	material.set_shader_parameter("ambient_brightness",
		spatial_falloff_level(cell, selected_cell, orb_falloff_scale) / ORB_BASE_LEVEL)
	# Keep the mat so _apply_element_sweep can re-drive ambient_brightness each frame off
	# the eased glide centre (§16.1) — a far unit sweeps through brightness as the pool
	# glides over it, instead of snapping when the selection changes.
	_body_mats_by_cell[cell] = material
	quad.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)

	var sprite_layers := SpriteLayerManager.new()
	sprite_layers.initialize(animation_set, material)
	# Prefer the resolved template folder's body.tga (unique / appearance-type); a
	# job-routed generic passes "" and the flat sprite loads (ADR-0072 #203).
	# Body sheets are immutable per folder, but load_body_sprite forces a full disk
	# re-decode (CACHE_MODE_IGNORE) every time — a scroll re-shows the same ~156 sheets
	# through an 8-cell window, so cache the resulting Texture2D objects by folder and
	# re-bind them on a re-show (byte-identical: same texture objects, no re-decode).
	var tex_key: String = render.template_folder if not render.template_folder.is_empty() else render.flat_texture_path
	if _body_tex_cache.has(tex_key):
		var pair: Array = _body_tex_cache[tex_key]
		sprite_layers.set_body_textures(pair[0], pair[1])
	else:
		sprite_layers.load_body_sprite(render.template_folder, render.flat_texture_path)
		_body_tex_cache[tex_key] = [
			material.get_shader_parameter("type1_tex"),
			material.get_shader_parameter("type1_palette"),
		]
	sprite_layers.set_body_palette_row(render.palette_row)
	sprite_layers.enable_layer(SpriteLayer.WEP1, false)
	sprite_layers.enable_layer(SpriteLayer.EFF1, false)
	var frame_id := AnimationFrameCalculator.get_frame_at(
		FACE_FRONT_SEQ, 0, animation_set.type1_seq)
	if frame_id >= 0:
		sprite_layers.load_frame_by_id(SpriteLayer.TYPE1, frame_id, true)
	else:
		push_warning("[Formation] no Face-Front frame for %s" % character.slug)
	_cell_content.append(sprite_layers)  # keep the manager alive (not tree-owned)

	# Size + place from the composited frame's visible bbox (loc space) so the
	# sprite renders at the ROM descriptor's Vh and its visible centre lands at the
	# ROM body centre (cellX+31, cellY+24) — per-unit, no feet scatter (§7). Falls
	# back to the guessed body_scale/body_offset_px when the bbox is unreadable.
	# FIXED uniform scale (the ROM draws every UNIT.BIN roster mini at one common
	# scale — a tall knight and a short mage keep their natural height difference,
	# so normalizing each unit's visible height to a constant is WRONG). The per-unit
	# visible bbox is used ONLY to CENTRE the sprite at the ROM body centre
	# (cellX+31, cellY+24) — that is what kills the per-job feet scatter (§7).
	var bbox := sprite_layers.current_body_bbox()
	# Keep the composited frame's visible bbox (LOC space): the Change-Job commit tint needs the
	# SPRITE's extent, not the quad's, because the ROM's gouraud quad IS the 24x40 frame while
	# ours is a 256-loc atlas window (§7). Nothing else reads it, and it costs one Rect2 per cell.
	_body_bbox_by_cell[cell] = bbox
	var offset_px: Vector2 = body_offset_px
	if bbox.size.y > 0.0:
		offset_px = derive_body_offset_px(bbox, body_scale, feet_target_px)
	var scale: float = body_scale
	holder.scale = Vector3(scale, scale, scale)
	# Materialize the body's ladder rung into real Z (ADR-0077): the opaque body writes DEPTH here, so
	# the folded gold box (a farther rung) is occluded BEHIND it and the orb rim (a nearer rung) over it.
	holder.position = anchor.position \
		+ screen_to_world(offset_px.x, offset_px.y) \
		+ Vector3(0.0, 0.0, DepthMode.rung_z(RP_UNIT_BODY))


## The per-cell glowing orb (§10): a 12x12 sprite drawn in TWO STP passes like the
## tile cursor — an OPAQUE core (STP=0) + an ADDITIVE rim halo (STP=1). Brightness
## is the PSX gouraud/128 (spatial falloff from the cursor); the selected cell's
## orb also pulses (_process). Both passes share one brightness value.
func _build_cell_orb(anchor: Node3D, cell: Vector2i) -> void:
	var idx_tex := _cached_asset_tex(_ASSET_DIR + "ORB.tga")
	var pal_tex := _cached_asset_tex(_ASSET_DIR + "ORB.palette.tga")
	var level := _orb_base_level(cell) / ORB_BASE_LEVEL
	var folded := Fold.owns()
	var holder := Node3D.new()
	# Materialize the orb rung into real Z (ADR-0077): the opaque core writes DEPTH here; the additive
	# rim HALO folds at the SAME rung, so it composites over the core (equal-Z GREATER_OR_EQUAL passes).
	holder.position = screen_to_world(orb_offset_px.x, orb_offset_px.y) + Vector3(0.0, 0.0, DepthMode.rung_z(RP_ORB))
	holder.visible = _orbs_visible   # honour the latch so a rebuild while the Equip screen is up stays hidden
	anchor.add_child(holder)
	_orb_holders_by_cell[cell] = holder
	var mats := []
	# Opaque CORE (STP=0) is ALWAYS in-scene (writes depth + seeds the fold scratch).
	var core_mi := _quad(ORB_PX)
	holder.add_child(core_mi)
	var core_mat := _orb_mat(_ORB_OPAQUE_SHADER, idx_tex, pal_tex, level)
	if not folded:
		core_mat.render_priority = RP_ORB
	core_mi.material_override = core_mat
	mats.append(core_mat)
	# Additive RIM halo (STP=1): a compositor_layer member on the fork (this is the HALO that vanished
	# when the Mobile composite was clobbered — ADR-0077), else an in-scene blend_add quad fallback.
	var rim_mi := _quad(ORB_PX)
	holder.add_child(rim_mi)
	var rim_mat := _orb_mat(fold_shader_for("orb_rim"), idx_tex, pal_tex, level)
	rim_mi.material_override = rim_mat
	if folded:
		Fold.add(rim_mi, rim_mat, DepthMode.rung_z(RP_ORB))
	else:
		rim_mat.render_priority = RP_ORB
	mats.append(rim_mat)
	# Keep every cell's orb mats so _apply_element_sweep re-drives brightness each frame
	# off the eased glide (§16.1); the selected cell's mats also carry the pulse.
	_orb_mats_by_cell[cell] = mats


## A formation-orb ShaderMaterial (core or rim variant): the shared index/CLUT + brightness params.
func _orb_mat(shader: Shader, idx_tex: Texture2D, pal_tex: Texture2D, level: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("index_tex", idx_tex)
	mat.set_shader_parameter("palette_tex", pal_tex)
	mat.set_shader_parameter("brightness", level)
	return mat


## The gold selection box (§11) on the cursor cell: one 32x16 ¼ texel mirrored
## x/y/xy into 4 quadrants, each drawn as TWO coincident passes offset 1px in Y —
## the ADDITIVE gold (tpage 0x3F) 1px higher OVER the SUBTRACTIVE darken (tpage
## 0x5F) 1px lower, embossing the edge with a drop shadow. FUN_8011712c builds the
## same two structs per quadrant (`structB.y = structA.y - 1`) and links them into
## OT buckets 3 (sub) / 4 (add) — an explicit paint order, which we mirror with the
## RP_BOX_SUB < RP_BOX_ADD ladder. Since ADR-0077 that ladder IS depth: each pass is
## lifted to `DepthMode.rung_z(rung)` below, one OT bucket apart. What stays authored is
## WHICH pass gets the nearer rung — a PSX fact, not a geometric one, since the two
## passes are otherwise coincident. That they must be distinct is load-bearing: when both
## shared a slot, Godot's transparent sort flipped them on the bottom-right quadrant
## (sub-on-top → blue). This used to read "(NOT depth — see the RP_* block)", which was
## true before ADR-0077 and has not been since (#634).
## DYNAMICALLY CONFIRMED on the live framebuffer (2026-07-17): add struct Y=135,
## sub struct Y=136 — bright gold with a dark line beneath. See §11.2.
##
## Builds ONE box under `holder` (which the trail positions at the box CENTRE, abs px):
## 4 quadrants × the enabled pass(es), each quad at its centre-relative offset. Returns
## [{mat, is_add}] so _update_box_trail can re-drive per-slot brightness (the trail fade).
## Brightness is seeded to 0 and set every frame by the trail update.
func _build_one_box(holder: Node3D) -> Array:
	var folded := Fold.owns()
	var idx_tex := load(_ASSET_DIR + "BOX.tga")
	var pal_tex := load(_ASSET_DIR + "BOX.palette.tga")
	# `dy` = per-pass screen-px Y offset (down); `rung` = depth-ladder rung (the sub darken folds one
	# rung BEHIND the additive gold, so add paints over it — the emboss); `is_add` picks box_add_level
	# vs box_sub_level when the trail sets brightness. On the fork each quad is a compositor_layer member
	# (Fold.add) — this is the gold selection box that VANISHED with the Mobile composite (ADR-0077).
	var sub_pass := {"prim": "box_sub", "rung": RP_BOX_SUB, "dy": box_emboss_dy, "is_add": false}
	var add_pass := {"prim": "box_add", "rung": RP_BOX_ADD, "dy": 0.0, "is_add": true}
	var passes: Array
	match box_pass_mode:
		1: passes = [add_pass]                     # additive pass only (parity debug)
		2: passes = [sub_pass]                     # subtractive pass only (parity debug)
		_: passes = [sub_pass, add_pass]           # 0 = composed emboss (sub under, add over)
	var quads := []
	for q in _BOX_QUADRANTS:
		for pass_info in passes:
			var mat := ShaderMaterial.new()
			mat.shader = fold_shader_for(pass_info["prim"])
			mat.set_shader_parameter("index_tex", idx_tex)
			mat.set_shader_parameter("palette_tex", pal_tex)
			mat.set_shader_parameter("uv_flip", q["flip"])
			mat.set_shader_parameter("brightness", 0.0)   # set per-frame by _update_box_trail
			var off: Vector2 = q["off"] + Vector2(0.0, pass_info["dy"])
			# holder sits AT the box centre (abs px, z=0); the quad is centre-relative + lifted to its rung.
			var sub_holder := Node3D.new()
			sub_holder.position = screen_to_world(off.x, off.y) + Vector3(0.0, 0.0, DepthMode.rung_z(pass_info["rung"]))
			holder.add_child(sub_holder)
			var mi := _quad(BOX_QUAD_PX)
			mi.material_override = mat
			sub_holder.add_child(mi)
			if folded:
				Fold.add(mi, mat, DepthMode.rung_z(pass_info["rung"]))
			else:
				mat.render_priority = pass_info["rung"]
			quads.append({"mat": mat, "is_add": pass_info["is_add"]})
	return quads


## Build (or rebuild) the persistent 8-box glide trail (§11.5): one full box per history
## slot, parented under a single root that is NOT torn down on a selection move. Positions
## / brightness / visibility are driven every frame by _update_box_trail off _box_history.
func _build_box_trail() -> void:
	if _trail_root != null and is_instance_valid(_trail_root):
		remove_child(_trail_root)
		_trail_root.queue_free()
	# The gold box trail is HOUSED in the registered element `formation.gold_box`
	# (ADR-0088): a screen-anchored assembly (slot holders position per-frame at
	# absolute display px off _box_history, so the element origin sits at zero),
	# UNCLIPPED as the cursor-class declared answer (the §15.20-glove precedent).
	_trail_root = UI3Element.new({
		"id": "formation.gold_box",
		"rect": UI3Element.screen_anchored(),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_trail_root.name = "BoxTrail"
	add_child(_trail_root)
	_trail_slots.clear()
	for s in TRAIL_LEN:
		var holder := Node3D.new()
		holder.name = "TrailSlot_%d" % s
		_trail_root.add_child(holder)
		var quads := _build_one_box(holder)
		_trail_slots.append({"holder": holder, "quads": quads})
	_trail_root.visible = _box_trail_visible   # honour the latch (Equip screen hides the box VISUAL, §15.23 RE24)
	_update_box_trail()


## Position / brighten / show-or-hide each trail slot from _box_history. Slot7 (newest =
## the head box) always draws at full ramp; older slots fade by TRAIL_RAMP and hide once
## they collapse onto the newer slot (the §11.5.3 settle gate) so the trail folds to a
## single box when the glide settles — critical, else 8 coincident ADDITIVE boxes blow out.
func _update_box_trail() -> void:
	for s in TRAIL_LEN:
		var slot: Dictionary = _trail_slots[s]
		var pos: Vector2 = _box_history[s]
		var holder: Node3D = slot["holder"]
		holder.position = screen_to_world(pos.x, pos.y)
		var vis := _trail_slot_visible(s)
		holder.visible = vis
		if not vis:
			continue
		var ramp: float = float(_trail_ramp[s]) / ORB_BASE_LEVEL
		for q in slot["quads"]:
			var level: float = (box_add_level if q["is_add"] else box_sub_level) * ramp
			q["mat"].set_shader_parameter("brightness", level)


## Settle gate (§11.5.3): the newest slot always draws; an older slot draws only while it
## is more than ~1px from the next-newer slot. When the glide settles, every slot coincides
## with the head, so all but slot7 hide → the trail collapses to one box.
func _trail_slot_visible(s: int) -> bool:
	if s == TRAIL_LEN - 1:
		return true
	var p: Vector2 = _box_history[s]
	var newer: Vector2 = _box_history[s + 1]
	return absf(p.x - newer.x) + absf(p.y - newer.y) > 0.5


## Mount a top-left-anchored textured quad of `size_px` at `offset_px` (cell-
## relative) under `anchor`, with `mat` as its material, lifted to depth-ladder `rung`
## (ADR-0077). Returns the MeshInstance3D so a folded prim can be handed to Fold.add.
func _mount_quad(anchor: Node3D, offset_px: Vector2, size_px: Vector2,
		mat: ShaderMaterial, rung: int = 0) -> MeshInstance3D:
	var holder := Node3D.new()
	holder.position = screen_to_world(offset_px.x, offset_px.y) + Vector3(0.0, 0.0, DepthMode.rung_z(rung))
	anchor.add_child(holder)
	var mi := _quad(size_px)
	mi.material_override = mat
	holder.add_child(mi)
	return mi


## The SHARED per-cell spatial-falloff gouraud level (§10 orb / §16 body): one
## `orb_spatial_falloff` sampled at a cell's centre — base 128 at the selected cell,
## dropping `falloff_scale`/px over the 2:1 oval distance (√(dx² + 4·dy²), BOTH axes),
## clamped to [80,128]. The ROM feeds the SAME falloff to the orb AND the unit body
## (base 200, clamp [0x50,0x80]); the port mirrors that by driving both from this pure
## function. Static so it unit-tests without a scene.
static func spatial_falloff_level(cell: Vector2i, selected: Vector2i,
		falloff_scale: float) -> float:
	if cell == selected:
		return ORB_BASE_LEVEL
	var dx := float(cell.x - selected.x) * COL_PITCH
	var dy := float(cell.y - selected.y) * ROW_PITCH
	var dist := sqrt(dx * dx + 4.0 * dy * dy)
	return clampf(ORB_BASE_LEVEL - falloff_scale * dist,
		ORB_MIN_LEVEL, ORB_BASE_LEVEL)


## The oval spatial falloff (§10/§16) evaluated in ABSOLUTE virtual px — the sweep
## form of spatial_falloff_level (which works in cell-index deltas). base − scale·
## sqrt(dx² + 4·dy²), clamped [80,128]. Feeding both element and centre their box-centre
## px makes this reduce EXACTLY to spatial_falloff_level at settle (the offset cancels),
## so nothing regresses when the glide has arrived; during a move it sweeps continuously.
static func falloff_px(sample: Vector2, centre: Vector2, scale: float) -> float:
	var d := sample - centre
	var dist := sqrt(d.x * d.x + 4.0 * d.y * d.y)
	return clampf(ORB_BASE_LEVEL - scale * dist, ORB_MIN_LEVEL, ORB_BASE_LEVEL)


## One glide step of the box centre toward `target` (§11.5.2 / §16.1): the integer law
## `next = (3·cur + target) >> 2` per axis, reproducing the live-OT ease cadence (RIGHT
## centre_x 48→…→93 for target 96; DOWN centre_y 75→…→118 for target 121). The last step
## SNAPS to the exact target: the raw floor()/truncation stalls ~3px SHORT in the travel
## direction (the oracle does too), but here that would leave the settled box ~3px off the
## unit — and off inconsistently by approach direction (right = −6px, left = −3px vs the
## feet). Converging exactly lands every cell centered like the first, regardless of which
## way you moved. The ease shape (and thus the trail) is unchanged; only the final resting
## pixel differs by ≤3px from the raw oracle.
static func box_glide_step(cur: Vector2, target: Vector2) -> Vector2:
	return Vector2(_glide_axis(cur.x, target.x), _glide_axis(cur.y, target.y))


static func _glide_axis(cur: float, target: float) -> float:
	var next: float = floor((3.0 * cur + target) / 4.0)
	if next == cur:
		return target   # converged (int-truncation stall) → land exactly on the cell
	return next


## Refresh the bottom-left vitals panel for the (snapped) selected unit. The panel
## follows the LOGICAL cursor instantly (it is not part of the glide).
## Re-read the SELECTED unit's numbers into the docked panel + every cell's readout. The host
## calls this when it returns to the roster from a sub-screen, because a sub-screen can MUTATE
## the unit: a Change-Job commit recomputes HP/MP and rewrites the job (CHANGE_JOB_COMMIT.md
## §11b — 044/044 → 038/038 on the oracle), and an Equip change moves stats too. Nothing on the
## roster refreshed itself on the way back, so the grid kept showing the pre-commit numbers (and
## the docked panel kept whatever unit it was last bound to) until an unrelated `rebuild_cells`
## — a scroll — happened to fix it. Cheap: the readouts are a handful of textured quads, and the
## sprite bodies are NOT re-composited (that is what made the scroll path expensive).
func refresh_selection_readouts() -> void:
	rebuild_sort_values()
	_update_vitals_for_selection()


func _update_vitals_for_selection() -> void:
	if _cluster == null or not is_instance_valid(_cluster):
		return
	var units := _roster_characters()
	var index := selected_cell.y * COLS + selected_cell.x
	if index < 0 or index >= units.size():
		return
	var character = units[index]
	if character == null or character.progression == null:
		return
	_cluster.set_unit_view(vitals_view_from_character(character))
	_rebind_info_panel()  # the RIGHT info panel shares the cluster's nameplate — rebind its view


## Per-cell static orb brightness level (§10.4 falloff, headful-tuned scale). The
## selected cell holds the base level; _process adds the pulse to it.
func _orb_base_level(cell: Vector2i) -> float:
	return spatial_falloff_level(cell, selected_cell, orb_falloff_scale)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _trail_root == null:
		return
	_advance_glide(delta)      # ease the box centre, shift the trail ring, reposition boxes
	_advance_orb_phase(delta)  # advance the selected-orb pulse phase (applied in the sweep)
	_apply_floor_spotlight()   # floor pool centre from the eased glide (§16.1)
	_apply_element_sweep()     # orb + body brightness swept off the eased glide (+pulse)
	_tick_button_flash()       # count down the L2/R2 pressed-button flash (§12.3.5)


## Count the L2/R2 pressed-button flash down to zero (§12.3.5); when it lapses, rebuild
## the header once to restore the button's normal (un-pressed) look.
func _tick_button_flash() -> void:
	if _pressed_frames <= 0:
		return
	_pressed_frames -= 1
	if _pressed_frames <= 0 and _pressed_side != "":
		_pressed_side = ""
		_build_sort_header()


## Ease the box centre toward the target at a fixed 60 Hz and keep the 8-slot history
## trail. Framerate-independent: accumulate ticks and step the integer glide law once per
## tick (capped so a frame hitch can't fast-forward the whole trail). §11.5 / §16.1.
func _advance_glide(delta: float) -> void:
	# While the Equip spotlight is retargeted, play_equip_slide OWNS _box_glide (easing it toward the
	# sliding unit); skip the grid-cell re-target so the two don't fight. The box VISUAL is hidden.
	if _equip_spotlight_active:
		return
	_box_target = cell_box_centre(selected_cell)   # picks up box_center_px scrubs live
	_glide_accum += delta * GLIDE_HZ
	var steps := int(_glide_accum)
	_glide_accum -= float(steps)
	steps = min(steps, TRAIL_LEN * 2)
	for _i in steps:
		_box_glide = box_glide_step(_box_glide, _box_target)
		for n in range(TRAIL_LEN - 1):        # FIFO shift: slot[n] <- slot[n+1]
			_box_history[n] = _box_history[n + 1]
		_box_history[TRAIL_LEN - 1] = _box_glide   # newest = the current glide
	_update_box_trail()


## Advance the selected-orb pulse PHASE only (the sweep applies it). A symmetric ±40
## triangle over the gouraud level (88..168, base 128). DYNAMICALLY MEASURED off the live
## OT primitive (0x801F10D8+4): ±4 every SECOND frame, endpoints held 4 frames → 84 f /
## 1.40 s. Ticked at ORB_PULSE_HZ = 30, one extra hold per endpoint, time-driven.
func _advance_orb_phase(delta: float) -> void:
	if not _orb_mats_by_cell.has(selected_cell):
		return
	_orb_accum += delta * ORB_PULSE_HZ
	while _orb_accum >= 1.0:
		_orb_accum -= 1.0
		if _orb_hold > 0:
			_orb_hold -= 1       # linger one extra tick → endpoint held 4 frames
			continue
		_orb_phase += _orb_dir * ORB_PULSE_STEP
		if _orb_phase >= ORB_PULSE_MAX:
			_orb_phase = ORB_PULSE_MAX
			_orb_dir = -1.0
			_orb_hold = 1
		elif _orb_phase <= ORB_PULSE_MIN:
			_orb_phase = ORB_PULSE_MIN
			_orb_dir = 1.0
			_orb_hold = 1


## Sweep every orb + body brightness off the SINGLE eased glide centre (§16.1): a far cell
## sweeps through brightness as the box-anchored pool glides over it, instead of snapping on
## a selection change. Distance is measured at each element's LIVE box centre → glide (so a unit
## that MOVES with the pool during the Equip slide stays lit — same falloff field as the floor
## spotlight, sampled at the element's real position, not its stale docked cell). On the static
## grid live == docked, so this is unchanged there. The selected cell's orb carries the pulse phase.
func _apply_element_sweep() -> void:
	for cell in _orb_mats_by_cell:
		var level: float = falloff_px(live_cell_box_centre(cell), _box_glide, orb_falloff_scale)
		if cell == selected_cell:
			level += _orb_phase
		var mult: float = level / ORB_BASE_LEVEL
		for mat in _orb_mats_by_cell[cell]:
			mat.set_shader_parameter("brightness", mult)
	for cell in _body_mats_by_cell:
		if cell in _changejob_wheel_cells:
			continue   # Change-Job ring members are spotlight-immune — stay at full brightness (§15.24 item 2)
		# …and so is the commit cutscene's target-job body. Its synthetic key sits 2000 columns off
		# the grid, so the falloff clamps it to ORB_MIN_LEVEL and the incoming job dissolves in at
		# 0.625x — then JUMPS to 1.0x when the teardown swaps in the rebuilt avatar. That step, not
		# the residual gouraud, is the "binary" pop. `begin_changejob_commit` pins it to 1.0 at
		# mount; this keeps the per-frame sweep from undoing that.
		if cell == CHANGEJOB_COMMIT_CELL:
			continue
		var blevel: float = falloff_px(live_cell_box_centre(cell), _box_glide, orb_falloff_scale)
		_body_mats_by_cell[cell].set_shader_parameter("ambient_brightness", blevel / ORB_BASE_LEVEL)
