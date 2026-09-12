@tool
class_name UIPortrait
extends Node3D
## Portrait mesh element with top-left anchoring (no frame).
##
## Displays a unit's portrait from their sprite texture.
## Origin is at TOP-LEFT of portrait; portrait extends RIGHT and DOWN.
##
## Portrait region in sprite textures:
## - Position: (80, 456)
## - Size: 48x32 pixels (landscape in texture)
## - Display: 32x48 after 90° rotation, then 40x48 with PAR
##
## Vault: [[Event Dialogue Portrait System]]

## ADR-0211 dec. 4 — the host autoload `PSXDisplay` is not nameable from inside an
## addon (every stranger rig declares an empty `[autoload]` block), so UI PAR is
## read and subscribed through the platform port. #1263 / ADR-0308.
const DisplayPort = ExMateriaPlatform.DisplayPort

const SHADER_PATH = "res://assets/shaders/unit_portrait_3d.gdshader"
## EVTFACE event-dialogue portraits ({50} Portrait Row) are fully-resolved RGBA
## (not indexed), drawn upright (not the SPR's 90°-rotated landscape), so they use
## a separate shader + un-rotated mesh. Display size stays identical to the
## unit-SPR path, so DialogueBox layout is unaffected. EvtFaceCatalog / §5.1.
const EVTFACE_SHADER_PATH = "res://assets/shaders/evtface_portrait_3d.gdshader"

# Sprite texture dimensions
const TEXTURE_WIDTH: int = 256
const TEXTURE_HEIGHT: int = 488

# Portrait region in sprite texture (stored rotated 90° CW from display)
const DEFAULT_PORTRAIT_X: int = 80
const DEFAULT_PORTRAIT_Y: int = 456
const DEFAULT_PORTRAIT_TEX_WIDTH: int = 48   # Width in texture
const DEFAULT_PORTRAIT_TEX_HEIGHT: int = 32  # Height in texture

## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		pixels_per_unit = value
		_update_mesh()

## Pixel aspect ratio. Defaults to 1.25 per ADR-0036. (The citation used to read
## `= PSXDisplay.PAR`; that constant had zero readers and is deleted — ADR-0152.
## This 1.25 is an initial value: `PSXDisplay.live_ui_par` overwrites it on the
## first sync, and its own default is 1.0. Tracked as UI's, not Render's.)
## PSX portrait sprites need the 1.25x horizontal stretch. Set to 1.0 for
## non-PSX portraits. Authoring with PAR off and flipping later shifts every
## center- and right-aligned position; pick one and stick.
@export var pixel_aspect_ratio: float = 1.25:
	set(value):
		pixel_aspect_ratio = value
		_update_mesh()

## Horizontal flip for portrait reversal
@export var flipped: bool = false:
	set(value):
		flipped = value
		_update_flip()

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _current_sprite_id: int = -1
var _pending_sprite_id: int = -1  # For calls before _ready()

# EVTFACE mode: display a resolved RGBA face (upright, no palette) instead of the
# unit-SPR indexed path. Set via display_evtface(); switches the material + mesh
# orientation. `_pending_evtface` holds a face requested before _ready().
var _evtface_mode: bool = false
var _evtface_material: ShaderMaterial
var _pending_evtface: Texture2D = null
static var _shared_evtface_shader: Shader

# Template-folder mode (ADR-0072 #203): the portrait is drawn from a unit's
# OWNED `portrait.tga` — a pre-cropped 48x32 slice with its own palette — instead
# of a window into the shared 256x488 sprite sheet. Reuses the paletted `_material`
# (same indexed shader), but rebinds `portrait_region`/`atlas_size` to the crop.
# `_pending_template_folder` holds a folder requested before _ready().
var _template_mode: bool = false
var _pending_template_folder: String = ""

# Portrait region (can be customized if needed)
var _portrait_x: float = DEFAULT_PORTRAIT_X
var _portrait_y: float = DEFAULT_PORTRAIT_Y
var _portrait_tex_width: float = DEFAULT_PORTRAIT_TEX_WIDTH
var _portrait_tex_height: float = DEFAULT_PORTRAIT_TEX_HEIGHT

static var _shared_shader: Shader


func _ready() -> void:
	_ensure_shared_resources()
	_setup_mesh_instance()
	_setup_material()
	if not Engine.is_editor_hint():
		if not is_equal_approx(pixel_aspect_ratio, DisplayPort.live_ui_par()):
			pixel_aspect_ratio = DisplayPort.live_ui_par()
	_update_mesh()
	_apply_overlay()

	# Apply any sprite ID that was set before _ready()
	if _pending_sprite_id >= 0:
		_apply_sprite_id(_pending_sprite_id)
		_pending_sprite_id = -1

	# Apply any EVTFACE texture that was set before _ready().
	if _pending_evtface != null:
		_apply_evtface(_pending_evtface)
		_pending_evtface = null

	# Apply any template-folder portrait requested before _ready().
	if not _pending_template_folder.is_empty():
		_apply_template_portrait(_pending_template_folder)
		_pending_template_folder = ""

	if not Engine.is_editor_hint():
		# The is-connected guard lives on the port now — a re-added element runs
		# `_ready()` again and `Signal.connect` raises on a duplicate.
		DisplayPort.connect_live_ui_par_changed(_on_live_ui_par_changed)


func _on_live_ui_par_changed(value: float) -> void:
	pixel_aspect_ratio = value


static func _ensure_shared_resources() -> void:
	if not _shared_shader:
		_shared_shader = load(SHADER_PATH)


func _setup_mesh_instance() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)


func _setup_material() -> void:
	if not _shared_shader:
		push_error("UIPortrait: Shared shader not loaded")
		return

	_material = ShaderMaterial.new()
	_material.shader = _shared_shader
	_material.set_shader_parameter("atlas_size", Vector2(TEXTURE_WIDTH, TEXTURE_HEIGHT))
	_update_shader_region()
	_material.render_priority = 0

	_mesh_instance.material_override = _material


func _update_shader_region() -> void:
	if _material:
		_material.set_shader_parameter("portrait_region", Vector4(
			_portrait_x, _portrait_y, _portrait_tex_width, _portrait_tex_height
		))


func _update_mesh() -> void:
	if not _mesh_instance:
		return

	# Display dimensions (after 90° rotation and PAR):
	# - texture is 48x32 landscape
	# - display as 32x48 after rotation
	# - then 40x48 with PAR applied to width
	var display_width = _portrait_tex_height * pixel_aspect_ratio * pixels_per_unit
	var display_height = _portrait_tex_width * pixels_per_unit

	# Create quad mesh
	var quad = QuadMesh.new()
	if _evtface_mode:
		# EVTFACE face is already upright (32x48 RGBA) — size the quad to the SAME
		# on-screen dims as the rotated SPR path (so layout matches) and DON'T
		# rotate. Local +X = right, +Y = up.
		quad.size = Vector2(display_width, display_height)
		_mesh_instance.mesh = quad
		_mesh_instance.rotation_degrees.z = 0.0
	else:
		# Mesh needs to be sized for the rotated orientation
		# The portrait shader expects the mesh to be rotated 90° CCW
		quad.size = Vector2(_portrait_tex_width, _portrait_tex_height * pixel_aspect_ratio) * pixels_per_unit
		_mesh_instance.mesh = quad
		# Rotate 90° CCW around Z to display portrait upright
		_mesh_instance.rotation_degrees.z = 90.0

	# Offset mesh so origin is at TOP-LEFT of displayed portrait:
	# After 90° CCW rotation, the mesh's local X becomes world Y and local Y becomes world -X
	# We need to position so the top-left of the visible portrait is at origin
	_mesh_instance.position = Vector3(display_width / 2.0, -display_height / 2.0, 0.0)


func _update_flip() -> void:
	if not _mesh_instance:
		return
	if _evtface_mode:
		# Un-rotated: horizontal axis is local X.
		_mesh_instance.scale.x = -1.0 if flipped else 1.0
		_mesh_instance.scale.y = 1.0
	else:
		# After the SPR path's 90° rotation, Y is the horizontal axis.
		_mesh_instance.scale.x = 1.0
		_mesh_instance.scale.y = -1.0 if flipped else 1.0


## Render this portrait as a painter's-ordered 2D overlay: force it into the
## transparent draw queue at `priority` and disable depth testing, so it
## composites by render_priority (above lower-priority quads, below higher)
## rather than by z-depth. For screen-space UI panels (e.g. [UIUnitInfoWindow])
## whose sibling elements all use `no_depth_test` + render_priority. No effect on
## the default depth-layered use ([UIPortraitFrame]/[UIMenuFrame]).
var _overlay_priority: int = -1
func set_overlay_priority(priority: int) -> void:
	_overlay_priority = priority
	_apply_overlay()


func _apply_overlay() -> void:
	if _overlay_priority < 0:
		return
	if _material != null:
		_material.render_priority = _overlay_priority
	if _evtface_material != null:
		_evtface_material.render_priority = _overlay_priority


## Override the sampled portrait width for THIS instance only (post-rotation
## display width, in source px). The default 32 → a 40px column with PAR; FFT's
## boxed dialog samples 31 so the 31×48 quad clears the 8px frame border (see
## dialogue_box_geometry_and_fidelity_decode.md Part 3). Does NOT touch the
## shared DEFAULT_PORTRAIT_TEX_HEIGHT global, so other portrait users are
## unaffected. Safe to call before _ready (the field is read in _ready).
func set_sampled_width(width_px: float) -> void:
	_portrait_tex_height = width_px
	_update_shader_region()
	_update_mesh()


## Display portrait for a sprite ID
func display_sprite_id(sprite_id: int) -> void:
	if sprite_id < 0:
		visible = false
		_pending_sprite_id = -1
		return

	# Store as pending if material not ready yet (called before _ready)
	if not _material:
		_pending_sprite_id = sprite_id
		_pending_evtface = null  # last source requested wins
		return

	_apply_sprite_id(sprite_id)


## Display a portrait straight from a unit's template folder's OWNED `portrait.tga`
## (ADR-0072 #203), the moddable read surface — preferred over the shared
## sprite-sheet path. The folder portrait is a pre-cropped 48x32 slice with its
## own palette, so this rebinds the shader to sample the whole crop (region
## (0,0,48,32), atlas 48x32) rather than the flat path's (80,456,…) window into
## the 256x488 sheet. Falls back to `display_sprite_id(fallback_sprite_id)` when
## the folder is blank or holds no `portrait.tga` — **load-bearing**, since
## template folders are generated + gitignored (#200) and may be absent.
func display_from_template(template_folder: String, fallback_sprite_id: int) -> void:
	if not template_folder.is_empty() \
			and ResourceLoader.exists(template_folder + "portrait.tga"):
		# Store as pending if the material isn't ready yet (called before _ready).
		if not _material:
			_pending_template_folder = template_folder
			_pending_sprite_id = -1   # last source requested wins
			_pending_evtface = null
			return
		_apply_template_portrait(template_folder)
		return
	display_sprite_id(fallback_sprite_id)


## Internal: bind the OWNED template-folder portrait crop + rebind the sampling
## region to the whole slice. Leaves EVTFACE mode if we were in it.
func _apply_template_portrait(template_folder: String) -> void:
	if _evtface_mode:
		_evtface_mode = false
		_mesh_instance.material_override = _material
		_update_mesh()
		_update_flip()

	var tex_path := template_folder + "portrait.tga"
	var pal_path := template_folder + "portrait.palette.tga"
	var texture := load(tex_path) as Texture2D
	if not texture:
		push_warning("UIPortrait: Could not load template portrait: %s" % tex_path)
		visible = false
		return

	_template_mode = true
	_current_sprite_id = -1  # left the shared-sheet sprite-id path

	# The crop is 48x32 with the portrait already at its origin — sample the whole
	# image. `_portrait_tex_height` (the post-rotation sampled width) is preserved
	# so a caller's set_sampled_width() still applies to the crop.
	_portrait_x = 0.0
	_portrait_y = 0.0
	_portrait_tex_width = DEFAULT_PORTRAIT_TEX_WIDTH
	_material.set_shader_parameter("atlas_size", texture.get_size())
	_update_shader_region()

	_material.set_shader_parameter("sprite_texture", texture)
	var palette := load(pal_path) as Texture2D
	if palette:
		_material.set_shader_parameter("sprite_palette", palette)
	else:
		push_warning("UIPortrait: Could not load template palette: %s" % pal_path)
	visible = true


## Display an EVTFACE event-dialogue portrait ({50} Portrait Row). `texture` is a
## resolved 32x48 RGBA face from [EvtFaceCatalog]; null hides the portrait. This
## is a genuinely different source from the unit-SPR path (`display_sprite_id`) —
## used for scripted cutscene boxes, not in-battle dialogue.
func display_evtface(texture: Texture2D) -> void:
	if texture == null:
		visible = false
		_pending_evtface = null
		return
	if not _material and not _evtface_material:
		_pending_evtface = texture
		_pending_sprite_id = -1  # last source requested wins
		return
	_apply_evtface(texture)


## Internal: switch to EVTFACE mode + bind the RGBA face texture.
func _apply_evtface(texture: Texture2D) -> void:
	_ensure_evtface_material()
	if _evtface_material == null:
		# Shader failed to load (already push_error'd) — stay hidden rather than
		# compositing a blank untextured quad into the box.
		visible = false
		return
	if not _evtface_mode:
		_evtface_mode = true
		_current_sprite_id = -1  # leaving the SPR path
		_mesh_instance.material_override = _evtface_material
		_update_mesh()  # rebuild un-rotated
		_update_flip()
	_evtface_material.set_shader_parameter("face_texture", texture)
	visible = true


func _ensure_evtface_material() -> void:
	if _evtface_material:
		return
	if not _shared_evtface_shader:
		_shared_evtface_shader = load(EVTFACE_SHADER_PATH)
	if not _shared_evtface_shader:
		# Surface a missing/corrupt shader loudly, mirroring the SPR path's
		# _setup_material push_error — otherwise the box silently renders a blank
		# untextured quad and "shader missing" looks identical to "face missing".
		push_error("UIPortrait: EVTFACE shader not loaded: %s" % EVTFACE_SHADER_PATH)
		return
	_evtface_material = ShaderMaterial.new()
	_evtface_material.shader = _shared_evtface_shader
	if _overlay_priority >= 0:
		_evtface_material.render_priority = _overlay_priority


## Internal: apply sprite ID to material
func _apply_sprite_id(sprite_id: int) -> void:
	# Returning to the indexed unit-SPR path from EVTFACE mode: restore the
	# paletted material + rotated mesh.
	if _evtface_mode:
		_evtface_mode = false
		_mesh_instance.material_override = _material
		_update_mesh()
		_update_flip()
	if _template_mode:
		# Returning to the shared-sheet path from a template-folder crop: restore
		# the sheet-window region + full-sheet atlas the sprite-id path expects.
		_template_mode = false
		_portrait_x = DEFAULT_PORTRAIT_X
		_portrait_y = DEFAULT_PORTRAIT_Y
		_portrait_tex_width = DEFAULT_PORTRAIT_TEX_WIDTH
		_material.set_shader_parameter("atlas_size", Vector2(TEXTURE_WIDTH, TEXTURE_HEIGHT))
		_update_shader_region()
	if sprite_id == _current_sprite_id:
		return  # No change needed

	_current_sprite_id = sprite_id
	var texture_path = "res://assets/sprites/textures/%02X.tga" % sprite_id
	var palette_path = "res://assets/sprites/textures/%02X.palette.tga" % sprite_id
	var texture = load(texture_path) as Texture2D
	var palette = load(palette_path) as Texture2D

	if texture:
		_material.set_shader_parameter("sprite_texture", texture)
		# ADR-0022: portrait shader is paletted. Load the companion palette
		# texture written by extract_spr_indexed. Missing palette is non-fatal:
		# the shader samples a default (transparent) palette, so the portrait
		# renders as transparent rather than with wrong colors.
		if palette:
			_material.set_shader_parameter("sprite_palette", palette)
		else:
			push_warning("UIPortrait: Could not load palette: %s" % palette_path)
		visible = true
	else:
		push_warning("UIPortrait: Could not load texture: %s" % texture_path)
		visible = false


## Clear the portrait display
func clear() -> void:
	_current_sprite_id = -1
	_pending_evtface = null
	visible = false


## Set horizontal flip
## Get the display width in world units
func get_display_width() -> float:
	return _portrait_tex_height * pixel_aspect_ratio * pixels_per_unit


## Get the display height in world units
func get_display_height() -> float:
	return _portrait_tex_width * pixels_per_unit


## Get the display width in virtual pixels
## Get the display height in virtual pixels
## Get current sprite ID (-1 if none)
func get_sprite_id() -> int:
	return _current_sprite_id


## The EVTFACE face texture actually bound and on the EVTFACE path (null when on the
## SPR path, cleared, or the face never applied — e.g. a missing shader hid it).
## Derived from live state so it can't report a phantom face the box isn't showing.
func get_evtface_texture() -> Texture2D:
	if not _evtface_mode or _evtface_material == null:
		return null
	return _evtface_material.get_shader_parameter("face_texture")
