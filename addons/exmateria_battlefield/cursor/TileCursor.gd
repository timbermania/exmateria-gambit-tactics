extends Node3D

## 🔴 THIS FILE HAS NO `class_name`, AND THAT IS THE DECISION (ADR-0206, applying
## ADR-0192 dec. 4 a second time). ADR-0164 dec. 4 criterion 1 scans `class_name`s, so a
## type without one cannot be in the published set. Thirteen host sites named `TileCursor`
## as a type; they now name `CursorRig`, the published port that owns one of these.
## `TileCursor.tscn` carries this script BY PATH and is unaffected; everything inside this
## addon `preload`s it (`CursorRig.gd`, `CursorController.gd`).

## The persistent on-grid camera-target device. Names which map tile the player
## is currently aimed at via `grid_pos: Vector2i`; the literal Tile node is derived on
## demand from the lattice and never published (`_tile_under_cursor()` is addon-internal since
## ADR-0194). The cursor never holds a Tile reference — Tile lifecycle is the map's
## concern; the cursor only names a logical position, and that is all four `cursor_*`
## signals carry.
##
## Sibling node, peer to PlayerCamera / ProceduralMap. Pushes signals only;
## holds no references to consumers (camera, audio router, future selection
## layers). See CONTEXT.md `Tile cursor` (Battlefield camera section) and
## godot-learning/docs/tile-cursor-handoff.md.
## Vault: [[Display Space Blend Fold]]
## Vault: [[Tile Overlay]]

## Emitted when the cursor's grid_pos changes (one step at a time).
##
## `Vector2i` ALONE (ADR-0164 dec. 3, closed at ADR-0194). The payload used to carry the
## `Tile` node beside the coordinate, which made this signal a door handing an addon-
## internal node to `UI` and to the assembler — criterion 3's last five rows. Nothing
## outside the addon ever read the node half: `FormationMapHost` bound it as `_tile` in
## three handlers and discarded it, `BattlefieldWiring` the same, and `GPUArena` narrowed
## it back to `Vector2i(tile.grid_x, tile.grid_z)` on the next line. It was never
## information either — the cursor DERIVES the tile from `grid_pos`, so a listener that
## wants the node can only be an addon file, and it asks `_tile_under_cursor()` for it.

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const DisplayPort = ExMateriaPlatform.DisplayPort
const TunePort = ExMateriaPlatform.TunePort

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const Fold = ExMateriaSchema.Fold

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const Lattice = preload("res://addons/exmateria_battlefield/lattice/Lattice.gd")
const PlayerCamera = preload("res://addons/exmateria_battlefield/camera/PlayerCamera.gd")
const Tile = preload("res://addons/exmateria_battlefield/lattice/Tile.gd")
const TileCursorBob = preload("res://addons/exmateria_battlefield/cursor/TileCursorBob.gd")
const TileCursorCompositor = preload("res://addons/exmateria_battlefield/cursor/TileCursorCompositor.gd")

signal cursor_moved(grid_pos: Vector2i)

## The PLAYER moved the cursor one step, by pressing a direction (#589). Not the
## same event as `cursor_moved`, and that difference is the whole reason this
## signal exists rather than reusing it: `cursor_moved` also fires from
## `move_to`, which host scenes call to place the cursor on a valid tile after a
## map builds, and which `FormationMapHost` and `CursorController` both consume.
## `SfxRouter.play_cue("ui.cursor_move")` used to sit on the line BELOW the
## `cursor_moved.emit` in `_try_step` — i.e. on exactly one of the two emit
## sites. Inverting the `Audio` reach onto `cursor_moved` would have added a
## cursor-move sound to every programmatic reposition, which is a behaviour
## change wearing a refactor's clothes.
##
## The cue itself is host vocabulary, not this system's: `OpeningMenu.gd:189`
## plays the same `"ui.cursor_move"` and has nothing to do with the battlefield.
## `BattlefieldWiring.wire_cursor` is what connects this to it.
signal cursor_stepped(grid_pos: Vector2i)

## Emitted when the player CONFIRMS on the tile the cursor currently names (○/Enter). The
## other half of the pair CONTEXT.md has always described: `cursor_moved` says where the
## cursor is, this says the player acted there. `grid_pos` may name a cell with no tile
## under it (confirm on an off-grid position); a listener that cares asks the lattice.
##
## The cursor states the EVENT and nothing more — it does not know whether that tile holds a
## unit, whether the unit is yours, or what confirming means. Every bit of that is the
## LISTENER's (ADR-0137: the deployment march reads it as "send this unit here", the formation
## map host reads it as "open this unit's screen"). Adding any of it here is the thing this
## signal exists to avoid.
signal cursor_confirmed(grid_pos: Vector2i)

## Emitted when the player asks to INSPECT the tile the cursor names (△/Tab). The passive
## twin of `cursor_confirmed`: confirming ACTS on what is there, inspecting only asks to LOOK
## at it. Split because those are two different intents and a single key could not carry both
## without its meaning changing by phase -- which is exactly the bug this pair replaces.
##
## Same silence as its twin: the cursor says the player asked, never what the answer is.
signal cursor_inspected(grid_pos: Vector2i)

## Emitted when the player asks to BACK OUT of whatever the cursor is in the middle of (✕/Backspace).
## The third member of the act/look/cancel triple, and it carries `grid_pos` for the same reason its
## twins do: the tile is the only thing the cursor knows, and every listener so far wants it (#941 —
## Backspace on a settled unit RECALLS the unit standing there, which is a question about a tile).
##
## 🔴 IT WAS A HOST-LOCAL KEYBIND, and that is the reason it moved here (#941). `GambitBattle`
## tested `ui_cancel` in its own `_unhandled_input` while ACT and LOOK arrived as signals — so two
## of the three cursor intents were the cursor's and the third was a keycode, and a host adding the
## fourth cursor host would have re-derived it a fourth time. `unit_inspect` is what that path leads
## to: three separate host actions bound to the same key because no port owned the intent.
##
## Same silence as its twins: it says the player asked to back out, never what backing out MEANS.
## Deploying reads it as "recall this unit"; the march would read it as "drop the pick".
signal cursor_cancelled(grid_pos: Vector2i)

@export_node_path("Node3D") var procedural_map_path: NodePath
@export_node_path("CharacterBody3D") var player_camera_path: NodePath

## Floating dagger position above the tile centroid, in world units.
# --- cursor.* pose tunables (ADR-0068) --------------------------------------
# The four POSE scalars have static-var literal homes (materializable, R1); the @export_range
# sliders below initialize from them (probe-confirmed the inspector default resolves), so the
# ONE code literal is the static var. HINTs live here too; register_tunables() binds them and
# CursorDebugPanel reads them back as pure views. (cursor.palette_row keeps bind_update — its default
# is read from the opaque body material's shader_parameter; cursor.blend_mode's default is the
# CURSOR_DEFAULT_BLEND_MODE const now that the outline routes instead of swapping a semi material.)
const CURSOR_HEIGHT_SLUG := "cursor.height"
static var CURSOR_HEIGHT_DEFAULT := 1.5
const CURSOR_HEIGHT_HINT := {"min": 0.0, "max": 5.0, "step": 0.01}
const CURSOR_SCALE_SLUG := "cursor.scale"
static var CURSOR_SCALE_DEFAULT := 0.75
const CURSOR_SCALE_HINT := {"min": 0.05, "max": 3.0, "step": 0.01}
const CURSOR_BOB_SCALE_SLUG := "cursor.bob_scale"
static var CURSOR_BOB_SCALE_DEFAULT := 1.0
const CURSOR_BOB_SCALE_HINT := {"min": 0.0, "max": 10.0, "step": 0.1}
const CURSOR_VBLANKS_PER_TICK_SLUG := "cursor.vblanks_per_tick"
static var CURSOR_VBLANKS_PER_TICK_DEFAULT := 1
const CURSOR_VBLANKS_PER_TICK_HINT := {"min": 1, "max": 8, "step": 1}

## Drives the HighlightMesh's local Y; bob is added on top.
@export_range(0.0, 5.0, 0.01) var cursor_height: float = CURSOR_HEIGHT_DEFAULT:
	set(value):
		cursor_height = value
		_apply_mesh_xform()

## Overall cursor size multiplier. The base mesh keeps the 13:24 dagger aspect.
@export_range(0.05, 3.0, 0.01) var cursor_scale: float = CURSOR_SCALE_DEFAULT:
	set(value):
		cursor_scale = value
		_apply_mesh_xform()

## Exaggeration multiplier for the ROM bob (1.0 = faithful). The amplitude IS the
## ROM offset table (ADR-0046) — this only scales it up for visual inspection.
@export_range(0.0, 10.0, 0.1) var bob_scale: float = CURSOR_BOB_SCALE_DEFAULT

## Frame-skip divider: effective bob rate = VBLANK_HZ / vblanks_per_tick. N=1 is
## the evidence-backed normal-play pace (60 Hz, +1 frame/tick); higher slows it.
@export_range(1, 8, 1) var vblanks_per_tick: int = CURSOR_VBLANKS_PER_TICK_DEFAULT

var grid_pos: Vector2i = Vector2i.ZERO

## The HOST's hand on the cursor's ear — false while the host is running a beat the player
## may not interrupt, true the rest of the time. Reached through `CursorRig.input_enabled`;
## nothing inside this addon writes it.
##
## It is a THIRD term in `_input_allowed()` and not a reuse of either existing one, because
## both of those say something else and saying it would be a lie. A camera TAKEOVER hides the
## dagger and hands the body to a driver; free-pan detaches the camera from the cursor
## entirely. A host beat does neither — the dagger stays on screen, the camera keeps easing on
## its own follow target — so a beat expressed as a takeover would BLANK the cursor for its
## duration and skip `_execute_cursor_follow`, which is the very travel it exists to show
## (`PlayerCamera._process` returns early in any non-CURSOR mode).
##
## It gates THIS node and only this node — its `_unhandled_input` and its `_process` repeat, so
## movement, ○, ✕ and unit-inspect all stop. Q/E never reach the cursor at all; they are
## `PlayerCamera._input`'s, and that file carries the matching flag for exactly that reason.
var input_enabled: bool = true

var _procedural_map: Node3D
var _player_camera  # PlayerCamera (untyped to dodge cyclic class-name preloads)
var _highlight_mesh: MeshInstance3D

# The SEMI-TRANS (STP=1 outline) pass is no longer an in-scene blend material — it routes through
# the combat display-space compositor (TileCursorCompositor), which folds it in 8-bit display space
# like the particles/trap (COMPOSITOR_INPUT_CONTRACT_GENERALIZATION.md §5). The OPAQUE body (STP=0)
# stays surface 0 (canvas + depth). The outline's blend mode + CLUT row are plain values here now (a
# push to the producer each frame) instead of a swapped material / material param.
var _cursor_producer: TileCursorCompositor = null
var _cursor_blend_mode: int = CURSOR_DEFAULT_BLEND_MODE   # compositor mode enum (0 mix/1 add/2 sub/3 add25)
var _cursor_palette_row: int = 4         # RANGETILE CLUT row (BATTLE.BIN slot 4)
var _cursor_uv_offset: Vector2 = Vector2(0.2578125, 0.5)     # sprite atlas origin (fallback = art)
var _cursor_uv_size: Vector2 = Vector2(0.05078125, 0.09375)  # sprite atlas size

# ROM-faithful bob (ADR-0046): the offset/hold step tables (cached from
# tile_knife.json), a monotonic tick counter, and a fixed-step accumulator
# (seconds) that advances the counter at VBLANK_HZ / vblanks_per_tick — never
# raw delta, matching AnimationPlayback.
const VBLANK_HZ := 60.0  # NTSC field clock — hardware truth, fixed
var _bob_offsets: Array[int] = []
var _bob_holds: Array[int] = []
var _bob_tile_unit: int = 28
var _bob_frame: int = 0
var _bob_accum: float = 0.0

const KEY_REPEAT_INITIAL_DELAY_MSEC: int = 250
const KEY_REPEAT_INTERVAL_MSEC: int = 100
const Y_OFFSET: float = 0.02  # Above HIGHLIGHT_Y_OFFSET (0.01) so cursor sits on top of range tiles
# Cursor sprite aspect from RANGETILE: 13 wide x 24 tall. Mesh is 1 tall by
# this ratio wide, then uniformly scaled by cursor_scale at draw time.
const CURSOR_ASPECT_W: float = 13.0 / 24.0

# PSX semi-transparency: the dagger sprite has both opaque (STP=0) body texels and
# semi-transparent (STP=1) outline texels. The body draws in-scene as surface 0
# (CURSOR_OPAQUE_MAT, canvas + depth). The outline routes through the display-space
# compositor (TileCursorCompositor) — its blend happens on the RD blend path, not an
# in-scene blend material, so the old per-mode semi shaders + tile_cursor_semi.tres are gone.
const CURSOR_OPAQUE_MAT: ShaderMaterial = preload("res://addons/exmateria_battlefield/cursor/tile_cursor_opaque.tres")

# Semi-trans (STP=1 outline) blend-mode labels — the cursor's PSX ABR rate; the `cursor.blend_mode`
# tunable indexes this and the INDEX is the compositor mode enum the producer folds with
# (0 mix/1 add/2 sub/3 add25). Owned here (not the debug panel) so the blend applies at the cursor in
# every scene — ADR-0068 decision 12. The default (index 2, Subtractive = drop-shadow look) is the
# mode the retired tile_cursor_semi.tres shipped with.
const CURSOR_DEFAULT_BLEND_MODE: int = 2
const SEMI_MODE_LABELS: Array[String] = [
	"0 Average (ABR00)", "1 Additive (ABR01)", "2 Subtractive (ABR10)", "3 Additive¼ (ABR11)",
]

const CURSOR_ACTIONS: Array[StringName] = [
	&"camera_up", &"camera_down", &"camera_left", &"camera_right",
]
## The CONFIRM action (○/Enter). Separate from CURSOR_ACTIONS because it is a one-shot edge, not a
## held+repeating step: confirming twice is two decisions, never an auto-repeat.
##
## A DEDICATED action rather than `ui_accept` — Godot's `ui_accept` default carries SPACE, and on
## the battlefield Space STARTS the battle (`battle_start`). Riding ui_accept here would have made
## starting a battle also a confirm. Bound to Enter / KP-Enter / pad ○.
const CURSOR_CONFIRM_ACTION: StringName = &"cursor_confirm"

## The INSPECT action (△/Tab). A one-shot edge like confirm, and gated identically.
##
## Tab is deliberately shared with `formation_start_menu`, and pad △ sits beside pad START the
## same way: the two never contend because they live in different input MODES -- the map cursor
## is frozen while the detail view is up, and the detail view does not exist while the map
## cursor is live. Read as one idea at two depths: "show me more".
const CURSOR_INSPECT_ACTION: StringName = &"unit_inspect"

## The CANCEL action (✕/Backspace). A one-shot edge like its twins, and gated identically.
##
## `ui_cancel` is Godot's own name and the project rebinds it to BACKSPACE (a bare Godot project
## binds Escape; here Escape is `battle_pause`, ADR-0137). Riding the built-in rather than minting a
## `cursor_cancel` is deliberate: every screen in this tree already backs out on `ui_cancel`, so a
## dedicated name would mean the battlefield alone cancelled on a different key.
const CURSOR_CANCEL_ACTION: StringName = &"ui_cancel"

# Latest-press-wins key tracking, [b]from EVENTS only[/b]. `_held` is every cursor direction
# currently down, in press order — the back of it is the one driving the repeat timer, which
# IS the rule. `_next_repeat_at_msec` is when the next auto-repeat step fires
# (Time.get_ticks_msec, wall-clock — survives pause).
#
# This was a single `_held_action` plus two polls of the `Input` singleton, and those polls
# are why `check_focus_anchor.py` listed this file: registering with Focus cannot discharge a
# poll, because the switch stops Godot CALLING a non-holder and cannot stop one ASKING. The
# list answers both questions the polls answered — "is the tracked action still down?" and
# "which one takes over when it is released?" — and answers the second one BETTER. The poll
# scanned `CURSOR_ACTIONS` and returned whichever came first in the TABLE, which is not press
# order, in a machine whose whole rule is latest-press-wins.
var _held: Array[StringName] = []
var _next_repeat_at_msec: int = 0


func _ready() -> void:
	_procedural_map = get_node_or_null(procedural_map_path)
	if not _procedural_map:
		_procedural_map = get_tree().get_first_node_in_group("procedural_map")

	_player_camera = get_node_or_null(player_camera_path)
	if not _player_camera:
		var found = get_tree().get_first_node_in_group("player_camera")
		if found:
			_player_camera = found

	# ROM bob step table (ADR-0046). Cached once; the per-frame path is pure.
	var bob := TileCursorBob.load_step_table("tile_knife")
	_bob_offsets = bob.get("offsets", [])
	_bob_holds = bob.get("holds", [])
	_bob_tile_unit = int(bob.get("tile_unit", 28))

	_highlight_mesh = $HighlightMesh
	_highlight_mesh.mesh = _build_highlight_mesh()
	# Surface 0 = opaque body (canvas + depth). The semi outline routes through the compositor.
	# PAR is handled entirely in the shader now (ADR-0044): the shared pixel_aspect
	# anchor + the psx_cursor_stretch global — no per-material seeding needed.
	_bind_range_textures()
	_highlight_mesh.set_surface_override_material(0, CURSOR_OPAQUE_MAT)
	_apply_mesh_xform()
	_setup_outline_producer()

	if _player_camera:
		_player_camera.camera_mode_changed.connect(_on_camera_mode_changed)

	_highlight_mesh.visible = false
	_bind_tunables()


## Build the direct outline-fold carrier and cache the sprite's atlas rect (read from the opaque body
## material — same RANGETILE sheet + CLUT). The outline routes only when the display-space fold owns
## compositing (fork + Forward+); on stock the cursor draws just its opaque body (no in-scene outline
## fallback — the pre-routing behavior), which also keeps the bare unit tests clean.
## Bind the ROM-derived atlas + palette onto the shared opaque material.
##
## ⚠️ These two are NOT `ext_resource`s in `tile_cursor_opaque.tres` any more, and cannot
## be: an `ext_resource` resolves at LOAD time, so no setting reaches it, and the pair was
## ADR-0202 Class B (content the addon can never ship). `Tile` owns the loading and the
## cache; this just hands the result to the material. `CURSOR_OPAQUE_MAT` is a `preload`,
## so one bind serves every cursor in the process — hence the early-out, which also keeps
## a null (unset content root, or a missing RANGETILE) from being cached as an answer.
func _bind_range_textures() -> void:
	if CURSOR_OPAQUE_MAT.get_shader_parameter("range_tex") != null:
		return
	var tex: Texture2D = Tile.range_texture()
	var palette: Texture2D = Tile.range_palette_texture()
	if tex == null or palette == null:
		return   # `Tile` / `BattlefieldContent` already reported the gap, once
	CURSOR_OPAQUE_MAT.set_shader_parameter("range_tex", tex)
	CURSOR_OPAQUE_MAT.set_shader_parameter("range_palette", palette)


func _setup_outline_producer() -> void:
	_cursor_uv_offset = CURSOR_OPAQUE_MAT.get_shader_parameter("cursor_uv_offset")
	_cursor_uv_size = CURSOR_OPAQUE_MAT.get_shader_parameter("cursor_uv_size")
	if not Fold.owns():
		return
	var range_tex: Texture2D = CURSOR_OPAQUE_MAT.get_shader_parameter("range_tex")
	var range_palette: Texture2D = CURSOR_OPAQUE_MAT.get_shader_parameter("range_palette")
	var palette_rows: int = int(CURSOR_OPAQUE_MAT.get_shader_parameter("palette_count"))
	_cursor_producer = TileCursorCompositor.new()
	_cursor_producer.setup(self, range_tex, range_palette, palette_rows)


## Return the borrowed compositor slot when the cursor leaves the tree.
func _exit_tree() -> void:
	if _cursor_producer != null:
		_cursor_producer.release()
		_cursor_producer = null


## Stage + publish the outline billboard each frame. When the cursor is hidden (TAKEOVER, off-grid),
## publish nothing so the compositor folds no stale outline. The pivot is the mesh's world origin
## (the dagger tip: tile + Y_OFFSET + cursor_height - bob), matching the in-scene billboard anchor;
## corners span the same footprint the dropped surface 1 did (CURSOR_ASPECT_W × cursor_scale).
func _publish_cursor_outline() -> void:
	if _cursor_producer == null:
		return
	if _highlight_mesh == null or not _highlight_mesh.visible:
		_cursor_producer.publish_empty()
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var view: Transform3D = cam.get_camera_transform().affine_inverse() if cam else Transform3D()
	var half_width: float = CURSOR_ASPECT_W * 0.5 * cursor_scale
	# Vector4, NOT Color: set_shader_parameter sRGB-linearizes a Color's RGB (sparing alpha) when it
	# feeds a plain `vec4` uniform, which crushes the sub-rect's U width (0.0508 -> ~0.003) and collapses
	# every column onto one texel — the "black dagger" bug. A Vector4 is delivered verbatim.
	var uv_rect := Vector4(_cursor_uv_offset.x, _cursor_uv_offset.y, _cursor_uv_size.x, _cursor_uv_size.y)
	# The fold re-applies psx_fx_stretch to the billboard offset (it was written for particles); divide
	# it out so the cursor keeps its own psx_cursor_stretch width. Both default 1.0 at rest.
	var fx: float = maxf(DisplayPort.live_fx_stretch(), 0.0001)
	var stretch: float = DisplayPort.live_cursor_stretch() / fx
	_cursor_producer.publish_cursor(view, _highlight_mesh.global_position, half_width, cursor_scale,
		uv_rect, _cursor_palette_row, _cursor_blend_mode, stretch)


## Hide the dagger ATOMICALLY: the opaque body (in-scene HighlightMesh) and the folded STP outline must
## disappear in the SAME frame. The body hides synchronously wherever this is called; the outline
## otherwise waits for the next _publish_cursor_outline() in _process, so on the frame a cinematic effect
## seizes the camera (TAKEOVER) the body is already gone while the folded outline keeps folding its
## last-published state — a one-frame "hollow dagger" flash (a regression from routing the STP outline
## out of HighlightMesh's coincident surface into a separate Fold carrier, which used to hide with it).
## publish_empty() drops the carrier from the fold NOW, closing the flash. No-op for the outline on stock
## (no producer); the body still hides.
func _hide_dagger() -> void:
	if _highlight_mesh != null:
		_highlight_mesh.visible = false
	if _cursor_producer != null:
		_cursor_producer.publish_empty()


## Bind the floating-dagger pose knobs to their `cursor.*` Tune slugs (ADR-0068).
## `bind` (not read-once `of`) because each value is written into a node/material
## that then just sits there, so a scrub has to re-drive it — this is what makes the
## knobs live in EVERY scene with no CursorDebugPanel fan-out (decision 12). The
## binding auto-drops when the cursor leaves the tree. Not @tool-guarded: TileCursor
## never runs in the editor (no @tool), so Tune is always the real autoload here.
##
## The four POSE scalars are bound in register_tunables() (static-var homes + hints) and just
## subscribe an on_update push here. palette_row / blend_mode stay bind_update per-instance:
## palette_row's default is read from the opaque body material's shader_parameter (its home, per ADR
## M5 — a legit non-materializable default), and blend_mode's default is CURSOR_DEFAULT_BLEND_MODE.
func _bind_tunables() -> void:
	TunePort.on_update(self, CURSOR_HEIGHT_SLUG, func(v: float) -> void: cursor_height = v)
	TunePort.on_update(self, CURSOR_SCALE_SLUG, func(v: float) -> void: cursor_scale = v)
	TunePort.on_update(self, CURSOR_BOB_SCALE_SLUG, func(v: float) -> void: bob_scale = v)
	TunePort.on_update(self, CURSOR_VBLANKS_PER_TICK_SLUG, func(v: int) -> void: vblanks_per_tick = v)
	var mats := cursor_materials()
	var pal_default: int = int(mats[0].get_shader_parameter("palette_row")) if not mats.is_empty() else 4
	TunePort.bind_update(self, "cursor.palette_row", pal_default,
		func(v: int) -> void: _set_palette_row(v))
	# The outline blend default is the mode the retired tile_cursor_semi.tres shipped with (2 = sub).
	TunePort.bind_update(self, "cursor.blend_mode", CURSOR_DEFAULT_BLEND_MODE,
		func(v: int) -> void: _set_blend_mode(v))


## Bind the four cursor pose scalars to their static-var homes + hints ONCE at class load (R2).
## Split from _bind_tunables (the per-instance on_update push) so it is this owner's named
## registration entry point — _static_init calls it at class load, and the ADR-0173 guards call
## it to read back which slugs this owner binds. palette_row / blend_mode are NOT here — they are per-instance
## (registered by their bind_update above when a cursor spawns).
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


static func register_tunables() -> void:
	TunePort.bind(CURSOR_HEIGHT_SLUG, CURSOR_HEIGHT_DEFAULT, CURSOR_HEIGHT_HINT)
	TunePort.bind(CURSOR_SCALE_SLUG, CURSOR_SCALE_DEFAULT, CURSOR_SCALE_HINT)
	TunePort.bind(CURSOR_BOB_SCALE_SLUG, CURSOR_BOB_SCALE_DEFAULT, CURSOR_BOB_SCALE_HINT)
	TunePort.bind(CURSOR_VBLANKS_PER_TICK_SLUG, CURSOR_VBLANKS_PER_TICK_DEFAULT, CURSOR_VBLANKS_PER_TICK_HINT)


## Write `palette_row` onto the opaque body material (surface 0) AND drive the routed outline. The
## body and outline share the CLUT row (both sample RANGETILE slot `row`).
func _set_palette_row(row: int) -> void:
	_cursor_palette_row = row
	for mat in cursor_materials():
		mat.set_shader_parameter("palette_row", row)


## Set the routed outline's blend mode (compositor enum 0 mix/1 add/2 sub/3 add25). Was a semi-
## material shader swap; the outline now folds in the compositor, so this is a plain value the
## producer reads each frame.
func _set_blend_mode(idx: int) -> void:
	if idx >= 0 and idx < SEMI_MODE_LABELS.size():
		_cursor_blend_mode = idx


## The routed outline's current blend mode (compositor mode enum). Debug/test read surface.
func cursor_blend_mode() -> int:
	return _cursor_blend_mode


## Build a vertical XY ArrayMesh with CUSTOM0 baked to the mesh centroid, so the
## cursor participates in the PSX ordering-table depth (CLAUDE.md `3D mesh
## without CUSTOM0 GTE depth`). The shader uses TILE_OVERLAY mode (7) so the
## quad sorts in front of tile + range-overlay geometry.
##
## The quad's local XY is oriented to the screen by the shader billboard
## (tile_cursor.gdshaderinc, same as every other sprite — the cursor is a single
## angle, so no camera-quadrant frame selection). UV V=0 maps to the dagger
## pommel (top of sprite), V=1 to the tip — so the tip points DOWN (toward the
## tile) when the quad is upright.
func _build_highlight_mesh() -> ArrayMesh:
	var hw: float = CURSOR_ASPECT_W * 0.5     # half-width  (X)
	var top: float = 1.0                       # top    (Y) — pommel
	var bot: float = 0.0                       # bottom (Y) — dagger tip
	var verts := PackedVector3Array([
		Vector3(-hw, top, 0.0),
		Vector3( hw, top, 0.0),
		Vector3( hw, bot, 0.0),
		Vector3(-hw, bot, 0.0),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	var centroid := Vector3.ZERO
	for v in verts:
		centroid += v
	centroid /= 4.0
	var custom0 := PackedFloat32Array()
	for _i in 4:
		custom0.append(centroid.x)
		custom0.append(centroid.y)
		custom0.append(centroid.z)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	var mesh := ArrayMesh.new()
	var custom_format: int = Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	# ONE surface now — the STP opaque body (surface 0, canvas + depth). The STP=1 semi outline that
	# used to be a second coincident surface routes through the display-space compositor
	# (TileCursorCompositor) instead of an in-scene blend material.
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, custom_format)
	return mesh


## The cursor's two STP-pass materials (opaque body + semi outline), so debug
## tooling can read/write shared shader params (palette_row, tint) across both.
func cursor_materials() -> Array[ShaderMaterial]:
	if _highlight_mesh == null:
		return []
	var mats: Array[ShaderMaterial] = []
	for i in _highlight_mesh.get_surface_override_material_count():
		var m := _highlight_mesh.get_surface_override_material(i) as ShaderMaterial
		if m != null:
			mats.append(m)
	return mats


## Apply scale + base position to the HighlightMesh. The ROM step-table bob is
## added by _process() (_update_mesh_anim); this only re-anchors the static parts
## after a knob twist.
func _apply_mesh_xform() -> void:
	if _highlight_mesh == null:
		return
	_highlight_mesh.scale = Vector3.ONE * cursor_scale
	_highlight_mesh.position.y = cursor_height


## Reposition the cursor to `target_pos`. Host scenes call this after the map
## has been built so the cursor starts on a valid tile (the default Vector2i.ZERO
## may not exist on the grid). Snaps; no lerp. Emits cursor_moved.
func move_to(target_pos: Vector2i) -> void:
	grid_pos = target_pos
	_refresh_mesh(_get_tile_at(grid_pos))
	cursor_moved.emit(grid_pos)


## ADDON-INTERNAL. The Tile node currently under the cursor, or null if grid_pos has no
## tile. Derived — callers should ask each frame, not cache the result.
##
## Private since ADR-0194: a public `-> Tile` is criterion 3's definition of a door, and
## the two host callers wanted a coordinate both times. `CursorController` is the one
## caller left and it is an addon file, which the criterion permits — it needs the NODE
## (`set_highlight_type`), not a cell.
func _tile_under_cursor() -> Tile:
	return _get_tile_at(grid_pos)


func _unhandled_input(event: InputEvent) -> void:
	if not _input_allowed():
		return
	# Confirm is the SAME gate as movement (`_input_allowed`): during a camera TAKEOVER the dagger
	# is hidden and the cursor is frozen, so there is no tile the player could mean. Swallowed, so
	# the one Enter press cannot ALSO reach a host handler behind us and mean a second thing.
	if event.is_action_pressed(CURSOR_CONFIRM_ACTION):
		cursor_confirmed.emit(grid_pos)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(CURSOR_INSPECT_ACTION):
		cursor_inspected.emit(grid_pos)
		get_viewport().set_input_as_handled()
		return
	# Swallowed like its twins, and safe for the same reason: `_input_allowed()` is false during a
	# camera TAKEOVER, which is exactly when a screen is up and wants ✕ for itself.
	if event.is_action_pressed(CURSOR_CANCEL_ACTION):
		cursor_cancelled.emit(grid_pos)
		get_viewport().set_input_as_handled()
		return
	for action in CURSOR_ACTIONS:
		if event.is_action_pressed(action):
			_begin_held(action)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released(action):
			# Only the DRIVING release restarts the timer. Letting go of a direction that was
			# already overridden changes nothing the player can feel, and re-arming the delay
			# there would stutter a roll.
			var was_driving := held_action() == action
			_held.erase(action)
			if was_driving and not _held.is_empty():
				_next_repeat_at_msec = Time.get_ticks_msec() + KEY_REPEAT_INITIAL_DELAY_MSEC


func _process(delta: float) -> void:
	_update_mesh_anim(delta)
	# Stage the routed outline AFTER the bob updates the mesh Y (its pivot is the mesh origin).
	_publish_cursor_outline()
	if not _input_allowed():
		_held.clear()
		return
	# The two `Input` re-derivations that stood here are gone. `_held` is maintained by the
	# release arm in `_unhandled_input`, so there is nothing left to re-check — and nothing
	# left for a frame on which this node does not hold input to ask.
	if _held.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now >= _next_repeat_at_msec:
		_next_repeat_at_msec = now + KEY_REPEAT_INTERVAL_MSEC
		_try_step(_held[-1])


## Per-frame: ROM step-table bob on Y (ADR-0046). Skipped while the mesh is
## hidden (TAKEOVER mode etc.) so we don't burn cycles or fight a takeover-driven
## orientation. Facing the camera is the shader's job (tile_cursor.gdshaderinc
## billboard, same as every other sprite) — no CPU rotation here.
##
## The bob is one-sided from the resting pose: the cursor sits at `cursor_height`
## (offset 0, the 16-frame dwell) and excursions DOWN toward the tile by up to
## `5/28` tile. The `−` is the provisional sign (capture-only unknown, ADR-0046);
## flip to `+` if a real-FFT capture shows the excursion rising.
func _update_mesh_anim(_delta: float) -> void:
	if _highlight_mesh == null or not _highlight_mesh.visible:
		return
	# Fixed-step accumulator (like AnimationPlayback) — advance the tick counter
	# at VBLANK_HZ / vblanks_per_tick, never raw delta. The phase machine is pure.
	var tick_duration: float = float(maxi(1, vblanks_per_tick)) / VBLANK_HZ
	_bob_accum += _delta
	while _bob_accum >= tick_duration:
		_bob_accum -= tick_duration
		_bob_frame += 1
	var offset: int = TileCursorBob.offset_for_frame(_bob_offsets, _bob_holds, _bob_frame)
	var bob_units: float = (float(offset) / float(_bob_tile_unit)) * bob_scale
	_highlight_mesh.position.y = cursor_height - bob_units


## [b]Alt-tab drops the held direction, and this is not optional.[/b]
##
## The poll covered it for free and never had to say so: the key comes up while the window is
## not focused, the release is never delivered to anyone, and the next frame's
## `is_action_pressed` simply saw it gone. An event-tracked list has to be told, or the cursor
## comes back auto-repeating on a key nobody is holding — a stuck input with nothing in the
## log, which is exactly the failure ADR-0119's Consequences describe.
##
## `_input_allowed()` already covers the in-game hand-offs (a camera TAKEOVER, free-pan); this
## covers the one that happens outside the game entirely.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_held.clear()


## The cursor direction currently driving the auto-repeat, or `&""` when none is down.
## Public because it is the only observable an input test has: the step itself is
## clamp-refused off-grid, so "the handler accepted the press" cannot be read off `grid_pos`.
func held_action() -> StringName:
	return _held[-1] if not _held.is_empty() else &""


func _input_allowed() -> bool:
	if not input_enabled:
		return false
	if _player_camera == null:
		return false
	if _player_camera.camera_mode != _player_camera.CameraMode.CURSOR:
		return false
	if PlayerCamera.free_camera():
		return false
	return true


func _begin_held(action: StringName) -> void:
	# Move-to-back rather than append: an OS key-repeat that slipped past `is_action_pressed`'s
	# echo filter must not put the same action in the list twice, or its release would leave a
	# copy behind and the cursor would walk on its own.
	_held.erase(action)
	_held.append(action)
	_next_repeat_at_msec = Time.get_ticks_msec() + KEY_REPEAT_INITIAL_DELAY_MSEC
	_try_step(action)


func _try_step(action: StringName) -> void:
	var delta := _action_to_grid_delta(action)
	if delta == Vector2i.ZERO:
		return
	var new_pos := grid_pos + delta
	var new_tile := _get_tile_at(new_pos)
	if new_tile == null:
		return  # off-grid; clamp by refusing the step
	grid_pos = new_pos
	_refresh_mesh(new_tile)
	cursor_moved.emit(grid_pos)
	cursor_stepped.emit(grid_pos)


## Quadrant-keyed action → grid delta. Every 90° increment of y_target_rot
## from the default -45° sits at a 45° camera-relative angle to the world,
## which makes a continuous "snap to nearest cardinal" degenerate (both axes
## have equal magnitude). The cardinal-correct answer is a fixed table per
## quadrant, derived from "press Q (CCW yaw +90°) → world-cardinal-formerly-
## at-screen-left rotates up": Q0 (default, screen-up = NORTH) → Q3 (screen-
## up = WEST) → Q2 (SOUTH) → Q1 (EAST). +X = NORTH, +Z = EAST (CLAUDE.md).
const _QUADRANT_DELTAS: Dictionary = {
	0: {  # yaw -45° / 315° — default; CRR's Q0
		&"camera_up":    Vector2i( 1,  0),  # NORTH
		&"camera_down":  Vector2i(-1,  0),  # SOUTH
		&"camera_left":  Vector2i( 0, -1),  # WEST
		&"camera_right": Vector2i( 0,  1),  # EAST
	},
	3: {  # yaw +45° — one Q press CCW from default
		&"camera_up":    Vector2i( 0, -1),  # WEST
		&"camera_down":  Vector2i( 0,  1),  # EAST
		&"camera_left":  Vector2i(-1,  0),  # SOUTH
		&"camera_right": Vector2i( 1,  0),  # NORTH
	},
	2: {  # yaw 135°
		&"camera_up":    Vector2i(-1,  0),  # SOUTH
		&"camera_down":  Vector2i( 1,  0),  # NORTH
		&"camera_left":  Vector2i( 0,  1),  # EAST
		&"camera_right": Vector2i( 0, -1),  # WEST
	},
	1: {  # yaw -135° / 225°
		&"camera_up":    Vector2i( 0,  1),  # EAST
		&"camera_down":  Vector2i( 0, -1),  # WEST
		&"camera_left":  Vector2i( 1,  0),  # NORTH
		&"camera_right": Vector2i(-1,  0),  # SOUTH
	},
}


func _action_to_grid_delta(action: StringName) -> Vector2i:
	if _player_camera == null:
		return Vector2i.ZERO
	return _QUADRANT_DELTAS[_quadrant_from_target_yaw()].get(action, Vector2i.ZERO)


## Quadrant index 0–3 matching CameraRelativeRenderer.get_camera_quadrant(),
## but resolved from the camera's TARGET yaw (snap-on-press) instead of the
## live focus_point rotation (which lerps).
func _quadrant_from_target_yaw() -> int:
	var deg: float = _player_camera.y_target_rot
	while deg < 0.0:
		deg += 360.0
	while deg >= 360.0:
		deg -= 360.0
	if deg >= 270.0:
		return 0
	if deg >= 180.0:
		return 1
	if deg >= 90.0:
		return 2
	return 3


## 🔴 THE CURSOR ADDRESSES A COLUMN AND RESOLVES ITS GROUND (ADR-0219). `grid_pos` is
## a `Vector2i` — the player steps it column to column — and since dec. 5 a column can
## hold two tiles. This picks the LOWEST, which is exactly what the cursor saw before
## the upper level was built, so no cursor behaviour moves on this change.
##
## It is a stated limitation, not a resolved question: FFT lets the player cycle the
## levels of a multi-level column, and nothing here can. Building that means the cursor
## publishes a cell rather than a column, which reaches ~90 sites across 17 files and
## answers a gameplay question ADR-0219 deliberately does not (#795).
func _get_tile_at(pos: Vector2i) -> Tile:
	var lat := _lattice()
	if lat == null:
		return null
	var ground := lat.ground_at(pos.x, pos.y)
	return lat._tile_at(ground.grid) if ground != null else null


## The map's lattice, or null before the map has built one.
##
## `_procedural_map` is resolved by NodePath and then by group, so it infers `Node3D`
## and this read is duck-typed BY CONSTRUCTION — the one untyped step at the seam
## ADR-0192 dec. 3 accepts permanently, because criterion 1 forbids publishing
## `MapComposer` so the map handle can never carry a type. The `in` probe replaces
## the `has_method("get_tile")` guard that stood here: it is the same "is this a real
## map yet" question one spelling out, and it is what a test's fake map answers by
## exposing a `Lattice` (ADR-0170 dec. 5 — `extends Lattice` and override, or a real
## `Lattice`; both satisfy it).
##
## 🔴 This file then reads `_tile_at`, which is ADDON-INTERNAL. It may, and since
## ADR-0194 that is the whole of the cursor's relationship with `Tile`: nothing it
## publishes carries one. A host file reaching `_tile_at` would be the defect; this is
## not one.
func _lattice() -> Lattice:
	if _procedural_map == null or not ("lattice" in _procedural_map):
		return null
	var lat: Lattice = _procedural_map.lattice
	return lat


func _refresh_mesh(tile: Tile) -> void:
	if tile == null:
		_hide_dagger()
		return
	# Anchor to the active tile's surface, FOLLOWING its elevation — the dagger
	# is always a fixed distance above the tile it names (cursor_height + bob,
	# applied via the mesh's local Y), whether that tile is ground or a rooftop.
	# (Previously Y was frozen at the first tile's ground level, which sank the
	# cursor into raised geometry like the house.)
	global_position = tile.global_position + Vector3(0.0, Y_OFFSET, 0.0)
	# Show only while we're in CURSOR mode (sprite hides during TAKEOVER).
	if _player_camera != null and _player_camera.camera_mode == _player_camera.CameraMode.CURSOR:
		_highlight_mesh.visible = true


func _on_camera_mode_changed(new_mode) -> void:
	if _player_camera == null:
		return
	if new_mode == _player_camera.CameraMode.TAKEOVER:
		_hide_dagger()
		_held.clear()
	else:  # CURSOR
		# Re-show only if we have a valid active tile to sit on.
		var tile := _tile_under_cursor()
		if tile != null:
			_refresh_mesh(tile)
