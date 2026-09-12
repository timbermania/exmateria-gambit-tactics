class_name ScenarioColorScreen
extends ScreenOverlayQuad
## Event-script {3E} "Color Screen" — the full-screen colour ramp that fades the
## whole framebuffer from a start RGB to an end RGB over Time frames, composited
## with a PSX semi-transparency (ABR) blend selected by Mode. Owned by ScenarioVM,
## ticked once per 60 Hz VM frame OUTSIDE the halt gate (like {76} Dark Screen /
## {1A} Map Darkness), so the ramp settles even while the VM parks on the {E5}
## Wait For Instruction(Task=0x0C) that immediately follows the {3E} dispatch.
##
## Faithful to the live-hardware RE (research/working_documents/
## COLOR_SCREEN_OPCODE_3E.md, static + live pcsx):
##   - The PSX worker FUN_801467dc lerps start->end in steps of 2 frames
##     (iVar6 = 0,2,4,6,8 then snaps to end): for start=0 end=255 Time=10 that is
##     the captured 0,51,102,153,204,255 sequence — a new step every 2 ticks,
##     landing exactly on `end` at tick == Time.
##   - Each push is drawn as a full-screen Gouraud quad by FUN_8008efb4; the quad
##     is SKIPPED when the colour is (0,0,0) (FUN_8008f208).
##   - Mode goes verbatim into the GP0 E1h draw-mode ABR field: 0=½B+½F (mix),
##     1=B+F (additive), 2=B-F (subtractive), 3=B+¼F. scn8 = Mode 2 white-ramp =>
##     subtractive fade to BLACK (live: framebuffer brightness 8181 -> 0).
##   - The following {E5} Wait For Instruction(Task=0x0C) blocks the VM on this
##     fiber (kind 0xC) until the ramp lands on `end` — is_active() drives that.

## Frames between ramp steps — the worker yields twice per step (2 frames).
const STEP_TICKS := 2

## Blend-shader family, one per PSX ABR mode (render_mode is compile-time static,
## so the mode picks a shader — same pattern as TileOverlayConfig.MODE_SHADERS).
## Consolidated blend math lives in assets/shaders/psx_screen_blend.gdshaderinc.
const MODE_SHADER_PATHS := [
	"res://assets/shaders/screen_color_mode0.gdshader",  # 0: ½B+½F  (mix)
	"res://assets/shaders/screen_color_mode1.gdshader",  # 1: B+F    (additive)
	"res://assets/shaders/screen_color_mode2.gdshader",  # 2: B-F    (subtractive)
	"res://assets/shaders/screen_color_mode3.gdshader",  # 3: B+¼F   (soft additive)
]

# --- Runtime ramp state ------------------------------------------------------

var _mode: int = 0
var _start: Vector3 = Vector3.ZERO   # (R,G,B) 0..255
var _end: Vector3 = Vector3.ZERO     # (R,G,B) 0..255
var _time: int = 0                   # ramp length in frames
var _ticks: int = 0                  # frames elapsed since start()
var _active: bool = false            # true while ramping (the {E5} barrier holds on this)
var _cur: Vector3 = Vector3.ZERO     # current pushed colour, 0..255

var _mmi: MeshInstance3D = null
var _mat: ShaderMaterial = null


func _ready() -> void:
	_build_render()


# --- Public API --------------------------------------------------------------

## Begin a {3E} ramp: seed the operands, reset to the start colour, select the
## Mode's blend shader.
func start(intent: ScenarioDecode.ColorScreenIntent) -> void:
	_mode = clampi(intent.mode, 0, MODE_SHADER_PATHS.size() - 1)
	_start = intent.start
	_end = intent.end
	_time = intent.time
	_ticks = 0
	_cur = _start
	if _time <= 0:
		# Time=0 => instant snap to end (PSX skips the ramp loop).
		_cur = _end
		_active = false
	else:
		_active = true
	_select_blend_shader(_mode)
	visible = true
	_push()


## Advance the ramp one 60 Hz VM frame. No-op once landed on `end`.
func tick() -> void:
	if not _active:
		return
	_ticks += 1
	# iVar6 = 2 * floor(ticks/2): a new step every STEP_TICKS frames.
	var iv := (_ticks / STEP_TICKS) * STEP_TICKS
	if iv >= _time:
		_cur = _end
		_active = false
	else:
		_cur = _start + (_end - _start) * (float(iv) / float(_time))
	_push()


## True while the ramp is still in-flight — the kind-0xC ({E5} Task=12) barrier
## holds on this. Releases once the colour lands on `end`.
func is_active() -> bool:
	return _active


## Snap the ramp straight to its end colour without spending frames — the fast-play
## settle guarantee (ScenarioVM.settle_screen_effects). No-op once landed. Mirrors
## letting `tick()` run to the frame it lands on `_end`.
func settle() -> void:
	if not _active:
		return
	_ticks = _time
	_cur = _end
	_active = false
	_push()


## Current pushed colour, 0..255, for the F3 panel / tests.
func current_color() -> Vector3:
	return _cur


## The PSX ABR blend mode in effect (0..3), for tests.
func blend_mode() -> int:
	return _mode


## True while the overlay quad is actually being drawn. Matches FUN_8008f208:
## the quad is skipped entirely at colour (0,0,0). For the F3 panel / tests.
func is_drawing() -> bool:
	return _mmi != null and _mmi.visible


# --- Internals ---------------------------------------------------------------

## Push the current colour to the shader. FUN_8008f208 skips the draw entirely
## when the colour is (0,0,0), so the quad is hidden at pure black.
func _push() -> void:
	var is_black := _cur.is_equal_approx(Vector3.ZERO)
	if _mmi != null:
		_mmi.visible = not is_black
	if _mat != null:
		_mat.set_shader_parameter("screen_color", _cur / 255.0)


func _select_blend_shader(mode: int) -> void:
	if _mat == null:
		return
	var shader := load(MODE_SHADER_PATHS[mode]) as Shader
	if shader != null and _mat.shader != shader:
		_mat.shader = shader


func _build_render() -> void:
	# Load the default (mode 0) shader up front; start() swaps to the real mode.
	var shader := load(MODE_SHADER_PATHS[0]) as Shader
	if shader == null:
		# Shaders not present yet (e.g. a pure ramp-logic unit test): the ramp
		# model still works; there's just no visible quad. Skip the material.
		return
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.render_priority = 100  # foreground overlay: sort over other transparents
	_mat.set_shader_parameter("screen_color", Vector3.ZERO)
	_mmi = _make_overlay_quad("ColorScreenQuad", _mat)
