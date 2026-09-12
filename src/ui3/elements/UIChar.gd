@tool
class_name UIChar
extends Node3D
## A single character for the new UI system with top-left anchoring.
##
## Renders one character from a bitmap font atlas with simplified palette support.
## Origin is at TOP-LEFT of character; character renders RIGHT and BELOW.
##
## Palette modes:
## - MENU: Original atlas colors (no remapping)
## - STAT: Gray tones with black stroke (for stat displays)
## - CUSTOM: User-defined 3 colors
##
## Vault: [[Dialogue Font Palette]]

const TunePort = ExMateriaPlatform.TunePort

## ADR-0211 dec. 4 — the host autoload `PSXDisplay` is not nameable from inside an
## addon (every stranger rig declares an empty `[autoload]` block), so UI PAR is
## read and subscribed through the platform port. #1263 / ADR-0308.
const DisplayPort = ExMateriaPlatform.DisplayPort

## #1271 — `DebugConfig` is a host autoload, and an addon cannot ship
## `project.godot` entries (ADR-0262 dec. 6), so the identifier is undefined in a
## stranger project. The flags were already `Tune` slugs; `UIDebug` reads them
## through the platform port. ADR-0308.
const UIDebug = preload("res://src/ui3/UIDebug.gd")

const SHADER_PATH = "res://src/ui3/shaders/ui_font_char.gdshader"

## Font color palettes
enum FontPalette {
	MENU,    ## Original atlas colors (brown/tan)
	STAT,    ## Gray tones with stroke (for stat displays)
	CUSTOM,  ## User-defined palette colors
	DISABLED ## Washed-out version of MENU for disabled elements
}

## MENU palette colors (configurable via Font debug panel)
## Defaults match exact atlas RGB values so reset = no visual change
static var MENU_USE_PALETTE: bool = false
static var MENU_DARK: Color = Color8(48, 40, 32, 255)      # Atlas darkest
static var MENU_MID: Color = Color8(80, 80, 64, 255)       # Atlas mid
static var MENU_LIGHT: Color = Color8(128, 120, 104, 255)  # Atlas brightest
static var MENU_STROKE_ENABLED: bool = false
static var MENU_STROKE: Color = Color.BLACK

## STAT palette colors (tuned for Forward+ renderer, configurable via Font debug panel)
## Maps: dark atlas → STAT_DARK (brightest), mid atlas → STAT_MID, light atlas → STAT_LIGHT
static var STAT_DARK: Color = Color(0.9570, 0.8823, 0.8823, 1.0)    # Replaces darkest atlas color
static var STAT_MID: Color = Color(0.7813, 0.769, 0.769, 1.0)       # Replaces middle atlas color
static var STAT_LIGHT: Color = Color(0.6758, 0.6758, 0.6758, 1.0)   # Replaces brightest atlas color
static var STAT_STROKE: Color = Color(0.3555, 0.3555, 0.3555, 1.0)  # Stroke outline
static var STAT_STROKE_ENABLED: bool = true

## DISABLED palette colors — washed-out (lighter) versions of atlas colors
static var DISABLED_DARK: Color = Color8(86, 78, 70, 255)      # Atlas dark + 38
static var DISABLED_MID: Color = Color8(111, 111, 95, 255)     # Atlas mid + 31
static var DISABLED_LIGHT: Color = Color8(154, 146, 130, 255)  # Atlas light + 26
static var DISABLED_STROKE_ENABLED: bool = false
static var DISABLED_STROKE: Color = Color.BLACK

# Shared resources - loaded once, reused by all instances
static var _shared_font: UIFont
static var _shared_shader: Shader

## The character to display (single character)
@export var character: String = "":
	set(value):
		if value.length() > 0:
			character = value[0]
		else:
			character = ""
		_update_character()

## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		pixels_per_unit = value
		_update_mesh()

## Pixel aspect ratio. Defaults to 1.25 per ADR-0036. (The citation used to read
## `= PSXDisplay.PAR`; that constant had zero readers and is deleted — ADR-0152.
## This 1.25 is an initial value: `PSXDisplay.live_ui_par` overwrites it on the
## first sync, and its own default is 1.0. Tracked as UI's, not Render's.)
## PSX-authored sprite art needs the 1.25x horizontal stretch to display
## correctly on a square-pixel screen. Set to 1.0 for non-PSX UI (modern
## fonts, debug-only text). Authoring with PAR off and flipping it on later
## shifts every center- and right-aligned position; pick one and stick.
@export var pixel_aspect_ratio: float = 1.25:
	set(value):
		pixel_aspect_ratio = value
		_update_mesh()

## Font color/tint
@export var font_color: Color = Color.WHITE:
	set(value):
		font_color = value
		if _material:
			_material.set_shader_parameter("font_color", font_color)

## Material render priority (higher = renders on top)
@export var render_priority: int = 0:
	set(value):
		render_priority = value
		if _material:
			_material.render_priority = render_priority

var _font: UIFont
var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _current_palette: FontPalette = FontPalette.MENU
var _custom_colors: Dictionary = {}  # {dark, mid, light}
var _stroke_enabled: bool = false
var _stroke_color: Color = Color.BLACK
var _stroke_padding: float = 0.0


## Convert Color to Vector4 to bypass Godot's auto sRGB→linear conversion on Color params
static func _color_to_vec4(c: Color) -> Vector4:
	return Vector4(c.r, c.g, c.b, c.a)


func _ready() -> void:
	_ensure_shared_resources()
	_font = _shared_font
	_setup_mesh_instance()
	_setup_material()
	# In editor preview just use the @export default (PSXDisplay is non-@tool).
	# At runtime, sync to live_ui_par and rebuild on scrub (ADR-0036).
	if not Engine.is_editor_hint():
		if not is_equal_approx(pixel_aspect_ratio, DisplayPort.live_ui_par()):
			pixel_aspect_ratio = DisplayPort.live_ui_par()
	_update_mesh()
	_update_character()
	if not Engine.is_editor_hint():
		# The is-connected guard lives on the port now — a re-added element runs
		# `_ready()` again and `Signal.connect` raises on a duplicate.
		DisplayPort.connect_live_ui_par_changed(_on_live_ui_par_changed)


func _on_live_ui_par_changed(value: float) -> void:
	pixel_aspect_ratio = value


static func _ensure_shared_resources() -> void:
	if not _shared_font:
		_shared_font = UIFont.new()
	if not _shared_shader:
		_shared_shader = load(SHADER_PATH)


func _setup_mesh_instance() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)


func _setup_material() -> void:
	if not _shared_shader:
		push_error("UIChar: Shared shader not loaded")
		return

	_material = ShaderMaterial.new()
	_material.shader = _shared_shader
	_material.set_shader_parameter("font_atlas", _font.atlas_texture)
	_material.set_shader_parameter("atlas_size", Vector2(_font.atlas_width, _font.atlas_height))
	_material.set_shader_parameter("font_color", font_color)
	_material.render_priority = render_priority

	_mesh_instance.material_override = _material


func _update_mesh() -> void:
	if not _mesh_instance or not _font:
		return

	# Calculate mesh size with stroke padding
	var mesh_width = (_font.char_width + _stroke_padding * 2.0) * pixel_aspect_ratio * pixels_per_unit
	var mesh_height = (_font.char_height + _stroke_padding * 2.0) * pixels_per_unit

	# Create/update quad mesh
	var quad = QuadMesh.new()
	quad.size = Vector2(mesh_width, mesh_height)
	_mesh_instance.mesh = quad

	# Offset mesh so origin is at TOP-LEFT of character:
	# - Move right by half width (+X)
	# - Move down by half height (-Y in 3D space)
	_mesh_instance.position = Vector3(mesh_width / 2.0, -mesh_height / 2.0, 0.0)


func _update_character() -> void:
	if not _material or not _font:
		return

	if character.is_empty():
		visible = false
		return

	# Space characters are invisible (spacing handled by UIText)
	if character == " ":
		visible = false
		return

	visible = true
	var index = _font.get_char_index(character)
	var info = _font.get_char_info(index)

	if UIDebug.iteration():
		var row = index / _font.chars_per_row
		var col = index % _font.chars_per_row
		print("[UIChar] char='%s' -> index=%d (row %d, col %d) atlas=(%d,%d)" % [
			character, index, row, col, info.get("atlas_x", 0), info.get("atlas_y", 0)
		])

	var atlas_x = info.get("atlas_x", 0)
	var atlas_y = info.get("atlas_y", 0)

	_material.set_shader_parameter("char_region", Vector4(
		atlas_x,
		atlas_y,
		_font.char_width,
		_font.char_height
	))


## Get the display width of this character in world units (includes PAR)
func get_display_width() -> float:
	if not _font or character.is_empty():
		return 0.0
	var char_width = _font.get_char_width(character)
	return (char_width + _stroke_padding * 2.0) * pixel_aspect_ratio * pixels_per_unit


## Get the display height of this character in world units
func get_display_height() -> float:
	if not _font:
		return 0.0
	return (_font.char_height + _stroke_padding * 2.0) * pixels_per_unit


## Get character width in virtual pixels (without PAR)
## Get character height in virtual pixels
## Set the font color palette
func set_palette(palette: FontPalette) -> void:
	_current_palette = palette
	_custom_colors.clear()

	if not _material:
		return

	# Palette values are owned by Tune (`font.*` slugs, ADR-0068): the static above is
	# the code DEFAULT, `_pal` coalesces any committed override over it. Reading at this
	# use-site means every UIChar picks up an override on set_palette in ANY scene (and
	# after a reload), with no FontDebugPanel writing statics. FontDebugPanel drives a
	# live re-apply on scrub; new chars coalesce on their own set_palette.
	match palette:
		FontPalette.MENU:
			var menu_use: bool = _pal(MENU_USE_PALETTE, "font.menu_use_palette")
			_material.set_shader_parameter("use_palette", menu_use)
			if menu_use:
				_material.set_shader_parameter("palette_dark", _color_to_vec4(_pal(MENU_DARK, "font.menu_dark")))
				_material.set_shader_parameter("palette_mid", _color_to_vec4(_pal(MENU_MID, "font.menu_mid")))
				_material.set_shader_parameter("palette_light", _color_to_vec4(_pal(MENU_LIGHT, "font.menu_light")))
			_set_stroke_internal(_pal(MENU_STROKE_ENABLED, "font.menu_stroke_enabled"),
				_pal(MENU_STROKE, "font.menu_stroke"))

		FontPalette.STAT:
			_material.set_shader_parameter("use_palette", true)
			_material.set_shader_parameter("palette_dark", _color_to_vec4(_pal(STAT_DARK, "font.stat_dark")))
			_material.set_shader_parameter("palette_mid", _color_to_vec4(_pal(STAT_MID, "font.stat_mid")))
			_material.set_shader_parameter("palette_light", _color_to_vec4(_pal(STAT_LIGHT, "font.stat_light")))
			_set_stroke_internal(_pal(STAT_STROKE_ENABLED, "font.stat_stroke_enabled"),
				_pal(STAT_STROKE, "font.stat_stroke"))

		FontPalette.CUSTOM:
			_material.set_shader_parameter("use_palette", true)

		FontPalette.DISABLED:
			_material.set_shader_parameter("use_palette", true)
			_material.set_shader_parameter("palette_dark", _color_to_vec4(_pal(DISABLED_DARK, "font.disabled_dark")))
			_material.set_shader_parameter("palette_mid", _color_to_vec4(_pal(DISABLED_MID, "font.disabled_mid")))
			_material.set_shader_parameter("palette_light", _color_to_vec4(_pal(DISABLED_LIGHT, "font.disabled_light")))
			_set_stroke_internal(_pal(DISABLED_STROKE_ENABLED, "font.disabled_stroke_enabled"),
				_pal(DISABLED_STROKE, "font.disabled_stroke"))


## Register every `font.*` palette slug at class load (ADR-0068 R2) from its static-var home,
## so `_pal` pull-reads via Tune.get_value and the dashboard enumerates them before any UIChar
## exists. Editor-guarded: UIChar is @tool and Tune is a non-@tool placeholder in the editor.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## The font.* binds, split out so a test that clears the registry via Tune.reset() can
## re-establish them (the pilot's convention — _static_init won't re-run after a reset).
static func register_tunables() -> void:
	TunePort.bind("font.menu_use_palette", MENU_USE_PALETTE)
	TunePort.bind("font.menu_dark", MENU_DARK)
	TunePort.bind("font.menu_mid", MENU_MID)
	TunePort.bind("font.menu_light", MENU_LIGHT)
	TunePort.bind("font.menu_stroke_enabled", MENU_STROKE_ENABLED)
	TunePort.bind("font.menu_stroke", MENU_STROKE)
	TunePort.bind("font.stat_dark", STAT_DARK)
	TunePort.bind("font.stat_mid", STAT_MID)
	TunePort.bind("font.stat_light", STAT_LIGHT)
	TunePort.bind("font.stat_stroke_enabled", STAT_STROKE_ENABLED)
	TunePort.bind("font.stat_stroke", STAT_STROKE)
	TunePort.bind("font.disabled_dark", DISABLED_DARK)
	TunePort.bind("font.disabled_mid", DISABLED_MID)
	TunePort.bind("font.disabled_light", DISABLED_LIGHT)
	TunePort.bind("font.disabled_stroke_enabled", DISABLED_STROKE_ENABLED)
	TunePort.bind("font.disabled_stroke", DISABLED_STROKE)


## Pull-read a `font.*` palette override coalesced over its bound static-var default (ADR-0068
## R5). @tool-guarded: Tune.gd is not @tool, so in the editor it is a placeholder that cannot
## be called — fall back to the raw default there (mirrors the DebugConfig / SpriteLayerManager
## guards). `default` is the editor fallback + the type cue; the runtime read is by slug.
static func _pal(default: Variant, slug: String) -> Variant:
	if Engine.is_editor_hint():
		return default
	return TunePort.get_value(slug, default)


## Set custom palette colors (automatically switches to CUSTOM mode)
## dark/mid/light replace the corresponding atlas colors by nearest-match
func set_custom_colors(dark: Color, mid: Color, light: Color) -> void:
	_current_palette = FontPalette.CUSTOM
	_custom_colors = {"dark": dark, "mid": mid, "light": light}

	if not _material:
		return

	_material.set_shader_parameter("use_palette", true)
	_material.set_shader_parameter("palette_dark", _color_to_vec4(dark))
	_material.set_shader_parameter("palette_mid", _color_to_vec4(mid))
	_material.set_shader_parameter("palette_light", _color_to_vec4(light))


## Enable/disable stroke outline around the character
func set_stroke(enabled: bool, color: Color = Color.BLACK) -> void:
	_set_stroke_internal(enabled, color)


func _set_stroke_internal(enabled: bool, color: Color) -> void:
	_stroke_enabled = enabled
	_stroke_color = color

	if not _material:
		return

	_material.set_shader_parameter("stroke_enabled", enabled)
	_material.set_shader_parameter("stroke_color", color)

	var new_padding = 1.0 if enabled else 0.0
	if new_padding != _stroke_padding:
		_stroke_padding = new_padding
		_material.set_shader_parameter("stroke_padding", _stroke_padding)
		_update_mesh()


## Get current palette
func get_palette() -> FontPalette:
	return _current_palette


## Check if stroke is enabled
## Get stroke color
