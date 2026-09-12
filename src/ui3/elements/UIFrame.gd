@tool
class_name UIFrame
extends Node3D
## 9-slice resizable frame with top-left anchoring.
##
## Uses the existing nine_slice_3d shader for rendering.
## Origin is at TOP-LEFT of frame; frame extends RIGHT and DOWN.
##
## Vault: [[Dialogue Box Geometry]]

## ADR-0211 dec. 4 — the host autoload `PSXDisplay` is not nameable from inside an
## addon (every stranger rig declares an empty `[autoload]` block), so UI PAR is
## read and subscribed through the platform port. #1263 / ADR-0308.
const DisplayPort = ExMateriaPlatform.DisplayPort

const FRAME_TEXTURE_PATH = "res://assets/ui/frame.tga"
const SHADER_PATH = "res://assets/shaders/nine_slice_3d.gdshader"
## Opaque, depth-writing sibling for chrome that must occlude a folded prim
## (ADR-0077) — see the FORMATION info panel. Identical 9-slice sampling; the
## only difference is opaque render_mode + no ALPHA write.
const SHADER_PATH_OPAQUE = "res://assets/shaders/nine_slice_3d_opaque.gdshader"

# Source region in frame.tga (default = the flat menu-tile crop shared by 10+
# call sites). DialogueBox overrides this per-instance to the beveled dialog
# frame `(40,0,32,32)`.
#
# The ROM menu-frame's opaque content is x[2..31], y[2..28] with a 1px DARK
# outline column on every edge (frame.tga: `(48,40,32)` at x=2 / y=2, and
# `(32,24,16)` at the bottom/right). The old crop started at (3,3) — it
# INCLUDED the bottom+right dark rows but SCISSORED OFF the top+left ones, so
# every default-crop window rendered tan (not dark) at its top/left edge. The
# real machine draws the dark outline on ALL FOUR sides (oracle-verified 2026-08-10:
# the stats band, Eqp panel, portrait, and nameplate windows all show `(48,40,32)`
# at their frame edge; the port dropped it top+left). So the crop starts at
# (2,2) and MARGIN_LEFT/MARGIN_TOP each grow +1 to place that outline as the
# outermost border column — the right/bottom edges + the tiled centre are
# UNCHANGED (verified against nine_slice_3d's sampling), the mesh outer edge is
# unchanged (no content moves), only a dark outline column is ADDED top+left.
const SOURCE_X = 2
const SOURCE_Y = 2
const SOURCE_W = 29
const SOURCE_H = 26

# 9-slice margins in source pixels (left, right, top, bottom). left/top = 4/5
# (was 3/4): the extra +1 is the ROM dark outline column now inside the crop.
const MARGIN_LEFT = 4
const MARGIN_RIGHT = 4
const MARGIN_TOP = 5
const MARGIN_BOTTOM = 4

## The FFT detail-menu window 9-slice WITH the brown title stripe + footer bar — the "brown stripe"
## chrome the equip picker / stats band / Eqp-Ability panels show. It lives on the SAME FRAME.BIN
## sheet (frame.tga) at (218,3)-(247,24); the user pinned this rect 2026-08-09. DISTINCT from the
## DEFAULT flat menu-tile crop (3,3,28,25): the top margin IS the dark brown header stripe (drawn
## once, cursor/labels sit on it), the middle tiles the dithered tan body, the bottom margin is the
## footer bar. Set a UIFrame's `source_region`/`margins` to these to swap the flat backdrop for it.
const STRIPE_SOURCE := Vector4(218, 3, 30, 22)
# left,right,top(header stripe+cream separator),bottom(footer). top=9 keeps the cream separator line
# (source y11) in the FIXED top so it isn't tiled; the middle then tiles ONLY the clean dithered tan
# body, and the bottom margin keeps the dark line + footer bar fixed. bottom=8 (NOT 7): source row y17
# is a SOLID darker-tan line (the body→footer transition, uniform not dithered), so tiling it — as
# bottom=7 did (middle = source y12..17) — repeated that line every 6px = the visible horizontal
# banding. bottom=8 drops y17 into the fixed footer so the middle tiles ONLY the clean dither y12..16,
# giving the same fine 1px pixel scale as every other window's flat fill (oracle fb4-verified).
const STRIPE_MARGINS := Vector4(4, 5, 9, 8)

## Draw the frame OPAQUE (depth-writing, no ALPHA) instead of alpha-blended.
## Default false → every existing caller (battle HUD, dialogue, sort header) is
## byte-identical. The FORMATION info panel sets this true so its tan frame
## occludes the folded subtractive band it sits on (ADR-0077). Must be set before
## the node enters the tree (read once in `_setup_material`).
@export var opaque: bool = false

## Atlas source region (x, y, w, h) in frame.tga pixels. Per-instance override
## of the `SOURCE_*` consts; defaults to them so every existing caller is
## byte-identical. DialogueBox sets `Vector4(40, 0, 32, 32)` for the beveled
## dialog frame.
@export var source_region: Vector4 = Vector4(SOURCE_X, SOURCE_Y, SOURCE_W, SOURCE_H):
	set(value):
		if source_region == value:
			return
		source_region = value
		if _material:
			_material.set_shader_parameter("source_region", source_region)

## 9-slice margins (left, right, top, bottom) in source pixels. Per-instance
## override of the `MARGIN_*` consts; defaults to them. DialogueBox sets
## `Vector4(8, 8, 8, 8)` for the uniform 8px dialog bevel.
@export var margins: Vector4 = Vector4(MARGIN_LEFT, MARGIN_RIGHT, MARGIN_TOP, MARGIN_BOTTOM):
	set(value):
		if margins == value:
			return
		margins = value
		if _material:
			_material.set_shader_parameter("margins", margins)

## Optional atlas patch (x, y, w, h) the tiled 9-slice CENTER samples instead of the
## `source_region` interior. The border/corners/edges still come from `source_region`, so a
## frame can keep a specific chrome (e.g. the equip-picker's STRIPE crop, whose body is only a
## 5px block that tiles into a coarse mottle) while its interior tiles a clean fine-dither patch
## from elsewhere on the sheet. Default ZERO ⇒ OFF: the center tiles `source_region` as before,
## so every existing caller is byte-identical.
@export var center_region: Vector4 = Vector4.ZERO:
	set(value):
		if center_region == value:
			return
		center_region = value
		if _material:
			_material.set_shader_parameter("center_region", center_region)

## Size of the frame in virtual pixels
@export var frame_size: Vector2 = Vector2(100, 50):
	set(value):
		frame_size = value
		_update_mesh()

## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		pixels_per_unit = value
		_update_mesh()

## Pixel aspect ratio. Defaults to 1.25 per ADR-0036. (The citation used to read
## `= PSXDisplay.PAR`; that constant had zero readers and is deleted — ADR-0152.
## This 1.25 is an initial value: `PSXDisplay.live_ui_par` overwrites it on the
## first sync, and its own default is 1.0. Tracked as UI's, not Render's.)
## the frame is PSX-authored pixel art and needs the 1.25x horizontal stretch
## to sit at the same display-space width as its PAR'd UIChar/UIPortrait
## contents. Set to 1.0 for a non-PSX frame.
@export var pixel_aspect_ratio: float = 1.25:
	set(value):
		pixel_aspect_ratio = value
		_update_mesh()

## Render priority (higher renders in front)
@export var render_priority: int = 0:
	set(value):
		render_priority = value
		if _material:
			_material.render_priority = render_priority

## Absorb clicks landing on the frame body. The frame draws a solid background
## but is otherwise click-transparent (only buttons/rows carry an Area3D), so
## without this a click on the body/border/padding falls THROUGH to whatever
## collider sits behind the window. When true, a frame-sized Area3D consumes
## those clicks (it sits behind the window's own buttons, so a button still wins
## where they overlap). Disable for a purely decorative frame that should let
## clicks pass through. Picking is only live while the frame is visible.
@export var absorb_clicks: bool = true:
	set(value):
		absorb_clicks = value
		_update_absorber()

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _absorber: Area3D
var _absorber_shape: BoxShape3D


func _ready() -> void:
	_setup_mesh_instance()
	_setup_material()
	_setup_absorber()
	if not Engine.is_editor_hint():
		if not is_equal_approx(pixel_aspect_ratio, DisplayPort.live_ui_par()):
			pixel_aspect_ratio = DisplayPort.live_ui_par()
	_update_mesh()
	_update_absorber()
	if not visibility_changed.is_connected(_update_absorber):
		visibility_changed.connect(_update_absorber)
	if not Engine.is_editor_hint():
		# The is-connected guard lives on the port now — a re-added element runs
		# `_ready()` again and `Signal.connect` raises on a duplicate.
		DisplayPort.connect_live_ui_par_changed(_on_live_ui_par_changed)


func _on_live_ui_par_changed(value: float) -> void:
	pixel_aspect_ratio = value


func _setup_mesh_instance() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)


## Build the body click-absorber. It only ever picks (input_ray_pickable);
## it does not monitor overlaps. Its `input_event` swallows mouse-button
## presses so they cannot fall through to colliders behind the window.
func _setup_absorber() -> void:
	if _absorber:
		return
	_absorber = Area3D.new()
	_absorber.name = "ClickAbsorber"
	_absorber.monitoring = false
	_absorber.monitorable = false
	var collision := CollisionShape3D.new()
	_absorber_shape = BoxShape3D.new()
	collision.shape = _absorber_shape
	_absorber.add_child(collision)
	_absorber.input_event.connect(_on_absorber_input)
	add_child(_absorber)


func _on_absorber_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()


## Pickable only when absorbing is on AND the frame is actually visible — a
## hidden window must not eat clicks (physics picking ignores visibility, so we
## gate it explicitly).
func _update_absorber() -> void:
	if _absorber:
		_absorber.input_ray_pickable = absorb_clicks and is_visible_in_tree()


func _setup_material() -> void:
	var shader = load(SHADER_PATH_OPAQUE if opaque else SHADER_PATH)
	if shader == null:
		push_error("UIFrame: Could not load shader")
		return

	var frame_tex = load(FRAME_TEXTURE_PATH)
	if frame_tex == null:
		push_error("UIFrame: Could not load frame texture")
		return

	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("frame_texture", frame_tex)
	_material.set_shader_parameter("source_region", source_region)
	_material.set_shader_parameter("margins", margins)
	_material.set_shader_parameter("center_region", center_region)
	_material.render_priority = render_priority

	_mesh_instance.material_override = _material


func _update_mesh() -> void:
	if _material == null or _mesh_instance == null:
		return

	# Update shader with new frame size
	_material.set_shader_parameter("output_size", frame_size)

	# Calculate mesh size in world units. PAR (ADR-0036): the mesh is 1.25x
	# wider in display space so the frame matches the PAR'd UIChar/UIPortrait
	# content it surrounds; the shader's output_size stays in virtual pixels,
	# so 9-slice borders stay native and only the tiled center stretches.
	var mesh_width = frame_size.x * pixel_aspect_ratio * pixels_per_unit
	var mesh_height = frame_size.y * pixels_per_unit

	# Create/update quad mesh
	var quad = QuadMesh.new()
	quad.size = Vector2(mesh_width, mesh_height)
	_mesh_instance.mesh = quad

	# Offset mesh so origin is at TOP-LEFT:
	# - Move right by half width (+X)
	# - Move down by half height (-Y in 3D space)
	_mesh_instance.position = Vector3(mesh_width / 2.0, -mesh_height / 2.0, 0.0)

	# Match the body absorber to the frame footprint (same top-left anchoring).
	# Thin in Z so it rides the frame plane, behind the window's own buttons.
	if _absorber_shape and _absorber:
		_absorber_shape.size = Vector3(mesh_width, mesh_height, 0.05)
		_absorber.position = Vector3(mesh_width / 2.0, -mesh_height / 2.0, 0.0)


## The 9-slice ShaderMaterial (built in `_setup_material`). Exposed so a caller can push
## per-frame uniforms — e.g. DetailScene's box-open scissor (`clip_world`, §15.17) that
## reveals the frame chrome through the growing window aperture instead of scaling it.
func get_material() -> ShaderMaterial:
	return _material


## Set the frame size in virtual pixels
## Get the current frame size in virtual pixels
func get_size() -> Vector2:
	return frame_size


## Get the inner content area size (frame minus margins) in virtual pixels
## Get the frame size in world units
## Get left margin in virtual pixels
## Get right margin in virtual pixels
## Get top margin in virtual pixels
## Get bottom margin in virtual pixels
