class_name ScenarioShowGraphic
extends ScreenOverlayQuad
## Event-script {7D} "Show Graphic" — the fullscreen event graphic (chapter title
## card, ending still, GAME OVER, or a WLDBK world background) that gradually
## fades in, holds, then fades out. Owned by ScenarioVM, ticked once per 60 Hz VM
## frame OUTSIDE the halt gate (like {76} Dark Screen / {3C} Weather), so the
## fade completes even while the VM parks on the {E5} Wait For Instruction(Task=61
## = 0x3D) barrier that immediately follows the {7D} dispatch.
##
## PSX provenance (research/working_documents/scenario_1_captures/
## show_graphic_op7d_decode.md, Parts II/III): {7D} spawns a cooperative task of
## kind 0x3D=61, and the ETC.OUT worker draws the card as TWO POLY_GT4 passes —
## an additive white-text pass + a subtractive drop-shadow — over the live scene.
## The fade-in is a LEFT->RIGHT gouraud wipe (reveal front, II.4); it then holds
## and the whole card's grey ramps 1->0 (II.6). {E5}(Task=61) blocks while any
## kind-61 task is live — i.e. until the graphic has fully faded away — so
## `is_live()` stays true across the whole reveal / hold / fade cycle, matching
## the chapter-intro beat (the card plays fully, THEN the scene proceeds).
##
## Rendered as two NDC-mapped fullscreen quads (show_graphic.gdshader additive +
## show_graphic_shadow.gdshader subtractive), sharing the reveal + PSX 4x4 dither
## logic in show_graphic_reveal.gdshaderinc. This controller drives the reveal
## front + grey level and places the card (centred band vs. fullscreen fill) via
## the `dst_half` uniform. All timing is ISO-sourced (configure_animation).

## Where the decoded ShowGraphic textures + manifest live (parse_show_graphics.py).
const GRAPHICS_DIR := "res://assets/scenarios/graphics/"
const MANIFEST_PATH := GRAPHICS_DIR + "show_graphics.json"
## PSX framebuffer the on-screen placement is measured against (256x240).
const REF_W := 256.0
const REF_H := 240.0

# --- Animation params (per-vblank frames). ISO-sourced from ETC.OUT and carried
# in the manifest's "animation" block (show_graphic_op7d_decode.md III.4/III.7),
# adopted via configure_animation(); these are the fmt-0 CHAPTER defaults so a
# missing manifest still animates faithfully.
## Reveal grows to the card content width (px) — template +0x1C.
var grow_limit: float = 248.0
## Reveal front advance per frame (px) — BATTLE global _DAT_80165f88 (init 1).
var grow_step: float = 1.0
## Frames held at full brightness after the reveal — 0x50.
var hold_frames: int = 80
## Frames over which the whole-card grey ramps 128->0 — 0x80.
var fade_frames: int = 128
## Soft-edge kernel width of the reveal front (px) — 0x20.
var edge: float = 32.0

# --- Runtime state -----------------------------------------------------------

## True from start() until the fade-out completes — the kind-61 {E5} barrier holds
## on this. Clears (graphic gone) once the whole cycle has played.
var _live: bool = false
## Frames elapsed since start() (drives reveal -> hold -> fade).
var _frame: int = 0
## Reveal front position (px, 0..grow_limit) — the L->R wipe (II.4).
var _reveal_front: float = 0.0
## Whole-card grey level 0..1 (the fade dim, II.6): 1 = full, 0 = gone.
var _grey: float = 0.0
## The last graphic id started (for the F3 panel / tests).
var _graphic_id: int = 0

var _tex: Texture2D = null
## Two draw passes (II.9): additive white text + subtractive drop-shadow.
var _mmi_text: MeshInstance3D = null
var _mmi_shadow: MeshInstance3D = null
var _mat_text: ShaderMaterial = null
var _mat_shadow: ShaderMaterial = null

## Parsed manifest cache (graphic-id-hex -> {file,w,h,fullscreen}); {} if absent.
static var _manifest: Dictionary = {}
static var _manifest_loaded: bool = false


func _ready() -> void:
	_build_render()
	_push_uniforms()
	visible = false


# --- Public API --------------------------------------------------------------

## Adopt the manifest's ISO-sourced animation block (grow_limit / grow_step /
## hold_frames / fade_frames / edge). Missing keys keep the current fmt-0 default,
## so the effect regenerates from ETC.OUT rather than a hardcoded placeholder.
func configure_animation(anim: Dictionary) -> void:
	# grow_limit floored at 1 so ceil(grow_limit/grow_step) can't collapse the
	# reveal phase to zero frames on a malformed manifest.
	grow_limit = maxf(1.0, float(anim.get("grow_limit", grow_limit)))
	grow_step = maxf(0.001, float(anim.get("grow_step", grow_step)))
	hold_frames = int(anim.get("hold_frames", hold_frames))
	fade_frames = int(anim.get("fade_frames", fade_frames))
	edge = float(anim.get("edge", edge))
	# edge_frac is constant for the whole card — push it once here, not per frame.
	_set_all("edge_frac", edge / grow_limit)


## Begin {7D}: resolve the graphic to a texture (which also adopts its animation
## params from the manifest), reset the reveal to its start.
func start(intent: ScenarioDecode.ShowGraphicIntent) -> void:
	_graphic_id = intent.graphic_id
	_resolve_graphic(intent.graphic_id)
	_frame = 0
	_reveal_front = 0.0
	_grey = 1.0
	_live = true
	_push_uniforms()
	# Only actually render if the texture resolved (in tests / a fresh clone the
	# generated assets may be absent — the barrier timing still runs so the VM
	# clears the halt, it just shows nothing).
	visible = _tex != null


## Advance the effect one per-vblank VM frame. No-op once the cycle has finished.
## Phases (II.4-II.6): reveal wipe -> hold -> global grey fade -> complete.
func tick() -> void:
	if not _live:
		return
	_frame += 1
	var grow_frames := int(ceil(grow_limit / grow_step))
	var hold_end := grow_frames + hold_frames
	var fade_end := hold_end + fade_frames
	if _frame <= grow_frames:
		# Reveal: front sweeps L->R at grow_step px/frame, full grey behind it.
		_reveal_front = minf(grow_limit, float(_frame) * grow_step)
		_grey = 1.0
	elif _frame <= hold_end:
		# Hold: fully revealed at full brightness.
		_reveal_front = grow_limit
		_grey = 1.0
	elif _frame < fade_end:
		# Fade-out: the WHOLE card's grey ramps 1 -> 0 uniformly.
		_reveal_front = grow_limit
		_grey = 1.0 - float(_frame - hold_end) / float(maxi(1, fade_frames))
	else:
		# Faded away — the graphic is gone; release the kind-61 barrier.
		_reveal_front = grow_limit
		_grey = 0.0
		_live = false
		visible = false
	_push_uniforms()


## True while the graphic is still on screen (revealing, held, or fading) — the
## kind-61 ({E5} Task=61) barrier polls this.
func is_live() -> bool:
	return _live


## Force the graphic to its faded-away terminal state without spending frames — the
## fast-play settle guarantee (ScenarioVM.settle_screen_effects). No-op once the cycle
## has finished. Mirrors letting `tick()` run past `fade_end`.
func settle() -> void:
	if not _live:
		return
	_reveal_front = grow_limit
	_grey = 0.0
	_live = false
	visible = false
	_push_uniforms()


## Reveal front position in px (0..grow_limit) — the L->R wipe, for tests / F3.
func reveal_front() -> float:
	return _reveal_front


## Whole-card grey level 0..1 (the fade dim), for tests / F3.
func grey_level() -> float:
	return _grey


## The graphic id currently being shown (0 if idle), for tests / debug.
func graphic_id() -> int:
	return _graphic_id


# --- Internals ---------------------------------------------------------------

## Look up the graphic id in the manifest, load its texture, adopt its ISO
## animation params, and set both passes' texture + placement. Leaves
## `_tex = null` (and render off) if unresolved.
func _resolve_graphic(gid: int) -> void:
	_tex = null
	var entry: Dictionary = _lookup(gid)
	if entry.is_empty():
		return
	# Adopt the per-id animation block so timing comes from ETC.OUT, not defaults.
	var anim = entry.get("animation", null)
	if anim is Dictionary:
		configure_animation(anim)
	var path: String = GRAPHICS_DIR + str(entry.get("file", ""))
	if not ResourceLoader.exists(path):
		return
	_tex = load(path) as Texture2D
	if _tex == null:
		return
	var fullscreen: bool = bool(entry.get("fullscreen", true))
	var w := float(entry.get("w", REF_W))
	var h := float(entry.get("h", REF_H))
	var dst_half := Vector2(0.5, 0.5)
	var dst_center := Vector2(0.5, 0.5)
	if not fullscreen:
		# Full-width, thin band. The card is NOT vertically centred on PSX: the
		# ISO `screen` block gives its top row (78 of a 240-tall framebuffer), so
		# place the band there instead of screen centre (upper third).
		dst_half = Vector2(minf(0.5, (w / REF_W) * 0.5), (h / REF_H) * 0.5)
		var screen = entry.get("screen", null)
		if screen is Dictionary:
			# Derive centre AND half-height from the same screen frame so they
			# never drift apart (the band spans [top, top+height] of ref_h).
			var ref_h := float(screen.get("ref_h", REF_H))
			var top := float(screen.get("top", 0.0))
			var sh := float(screen.get("height", h))
			dst_center = Vector2(0.5, (top + sh * 0.5) / ref_h)
			dst_half.y = (sh / ref_h) * 0.5
	_set_all("tex", _tex)
	_set_all("dst_half", dst_half)
	_set_all("dst_center", dst_center)


## Manifest entry for a graphic id, or {} if the manifest / id is absent.
func _lookup(gid: int) -> Dictionary:
	if not _manifest_loaded:
		_load_manifest()
	var key := "0x%02X" % gid
	return _manifest.get(key, {})


static func _load_manifest() -> void:
	_manifest_loaded = true
	if not ResourceLoader.exists(MANIFEST_PATH) and not FileAccess.file_exists(MANIFEST_PATH):
		return
	var txt := FileAccess.get_file_as_string(MANIFEST_PATH)
	if txt.is_empty():
		return
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		_manifest = parsed


## Push the current reveal/grey to both passes. Reveal + edge are normalised to
## the card content width so the shader stays placement-agnostic.
func _push_uniforms() -> void:
	# edge_frac is set once in configure_animation() — only reveal + grey change
	# per frame.
	_set_all("reveal", _reveal_front / maxf(1.0, grow_limit))
	_set_all("grey", _grey)


func _set_all(name: String, value) -> void:
	if _mat_text != null:
		_mat_text.set_shader_parameter(name, value)
	if _mat_shadow != null:
		_mat_shadow.set_shader_parameter(name, value)


func _build_render() -> void:
	# Two passes (II.9): additive white text, then a subtractive drop-shadow. Both
	# share the reveal/dither logic; only the blend mode + shadow offset differ.
	_mat_text = _make_pass_material(
		"res://assets/shaders/show_graphic.gdshader", 102)
	_mat_shadow = _make_pass_material(
		"res://assets/shaders/show_graphic_shadow.gdshader", 101)
	_mmi_shadow = _make_overlay_quad("ShowGraphicShadow", _mat_shadow)
	_mmi_text = _make_overlay_quad("ShowGraphicText", _mat_text)


func _make_pass_material(shader_path: String, priority: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.render_priority = priority  # over the map/units (above Dark Screen's 100)
	mat.set_shader_parameter("dst_half", Vector2(0.5, 0.5))
	mat.set_shader_parameter("dst_center", Vector2(0.5, 0.5))
	mat.set_shader_parameter("reveal", 0.0)
	mat.set_shader_parameter("edge_frac", edge / maxf(1.0, grow_limit))
	mat.set_shader_parameter("grey", 0.0)
	return mat
