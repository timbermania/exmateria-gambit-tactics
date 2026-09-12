class_name ScenarioMapTitle
extends ScreenOverlayQuad
## Event-script {91} "Show Map Title" — the pre-battle location-name text strip
## (e.g. "Military Academy's Auditorium") that reveals with a LEFT->RIGHT wipe,
## holds, then ERASES with a second LEFT->RIGHT wipe (the left end vanishes
## first). Owned by ScenarioVM, ticked once per 60 Hz VM frame OUTSIDE the halt
## gate (like {7D} Show Graphic / {76} Dark Screen), so it plays to completion
## while the scene proceeds.
##
## PSX provenance (research/working_documents/scenario_1_captures/
## show_map_title_op91_decode.md): {91} spawns an ATTACK.OUT task (worker
## SUB_801c9ec0) that uploads a 256x16 4bpp strip from EVENT/MAPTITLE.BIN, drawn
## over the live scene as an ADDITIVE gouraud pass (transparent CLUT idx0 lets
## the scene show through). Unlike {7D}, the fade-out is NOT a global brightness
## ramp — it is a second L->R wipe (§6.5).
##
## {91} BLOCKS the event VM until the whole reveal→hold→erase completes: the ROM
## interpreter case ends with FUN_8014c9d0 (yield-until-the-spawned-task-inactive),
## an implicit wait built into the opcode itself — NOT a following {E5} barrier.
## Dynamically confirmed (op91 decode §6): the scene holds on the sepia tint
## through the entire title, then advances (sepia restore, dialogue) only once it
## has erased away. So `is_live()` IS the barrier the VM waits on (~591 frames at
## Speed 1). The effect self-ticks OUTSIDE the halt gate, so it keeps advancing
## while the main context is parked on it.
##
## The image is selected by MAP CONTEXT (not the opcode operand, which is
## X/Y/Speed). The selection is ARITHMETIC, not an opaque table (was op91 §3
## GAP-3.1): the ATTACK.OUT worker (0x801C9EC0) reads event var 0x33 (= the
## battle map_id) and uploads MAPTITLE strip (map_id - 1). MAPTITLE.BIN is a flat
## array in map_id-1 order — strip i is the title for map_id i+1. The manifest's
## map_id_to_slot table is that relation, derived over the inked strips (map 24 ->
## 23 "Military Academy's Auditorium" byte-proven; map 104 -> 103 "Beoulve
## Residence"). Rendered as one NDC-mapped quad (show_map_title.gdshader), driving
## `reveal`/`erase` fronts + PSX dither.

## Where the decoded map-title textures + manifest live (parse_map_titles.py).
const TITLES_DIR := "res://assets/scenarios/map_titles/"
const MANIFEST_PATH := TITLES_DIR + "map_titles.json"
## PSX framebuffer the on-screen placement is measured against (256x240).
const REF_W := 256.0
const REF_H := 240.0
const STRIP_W := 256.0
const STRIP_H := 20.0          # ATTACK.OUT upload rect height (256×20 strip)
## Horizontal screen centre — the strip is authored centred; the battle draw-env
## centres it. (The prim→screen X offset is a global draw-env constant, not in
## ATTACK.OUT — op91 decode §II GAP; X is therefore fixed at centre here.)
const SCREEN_CENTER_X := 0.5

# --- Render params — ROM-sourced from EVENT/ATTACK.OUT (manifest "render" block,
# every value cited to an ATTACK.OUT file offset in op91 decode §II). These are
# the defaults if the manifest is absent; configure_render() overrides from ROM.
## Reveal/erase front grows to this many px — ATTACK.OUT 0xADD8 (slti 248).
var grow_limit: float = 248.0
## Front advance per frame (px) at Speed=1 — the task steps by Speed/vblank.
var grow_step: float = 1.0
## Frames held fully revealed before the erase wipe — ATTACK.OUT 0xAE24 (110).
var hold_frames: int = 110
## Soft-edge kernel width of a wipe front (px) — ATTACK.OUT 0xABD4 (0x20).
var edge: float = 32.0
## Primitive-space top Y (px) — ATTACK.OUT 0xAA68 (addiu +96); mapped to screen.
var prim_y_base: float = 96.0
## Speed multiplier from the opcode operand (scales grow_step for both wipes).
var speed: float = 1.0

# --- Runtime state -----------------------------------------------------------

## True from start() until the erase wipe completes (for tests / F3 only — {91}
## is fire-and-forget, nothing gates on it).
var _live: bool = false
## Frames elapsed since start() (drives reveal -> hold -> erase).
var _frame: int = 0
## Reveal front position (px, 0..grow_limit) — the fade-in L->R wipe (§6.4).
var _reveal_front: float = 0.0
## Erase front position (px, 0..grow_limit) — the fade-out L->R wipe (§6.5).
var _erase_front: float = 0.0
## The MAPTITLE slot currently shown (-1 if none/unresolved), for tests / F3.
var _slot: int = -1

var _tex: Texture2D = null
## Two draw passes (VRAM-confirmed, §6.3): additive text + subtractive drop-shadow
## offset ~(+1,+1) px — the same dual-pass as {7D} Show Graphic.
var _mmi_text: MeshInstance3D = null
var _mmi_shadow: MeshInstance3D = null
var _mat_text: ShaderMaterial = null
var _mat_shadow: ShaderMaterial = null

## Parsed manifest cache; {} if absent.
static var _manifest: Dictionary = {}
static var _manifest_loaded: bool = false


func _ready() -> void:
	_build_render()
	_push_uniforms()
	visible = false


# --- Public API --------------------------------------------------------------

## The MAPTITLE slot for a BATTLE map_id, or -1 if the map has no title. The ROM
## rule is arithmetic: strip = map_id - 1 (ATTACK.OUT worker 0x801C9EC0 reads event
## var 0x33 = map_id, subtracts 1). We read it from the manifest's map_id_to_slot
## table (derived over the 115 inked strips), so an out-of-range / titleless map
## returns -1. Static so callers (ScenarioWorld) can resolve without a live node.
static func slot_for_map(map_id: int) -> int:
	if not _manifest_loaded:
		_load_manifest()
	var tbl = _manifest.get("map_id_to_slot", {})
	if tbl is Dictionary and tbl.has(str(map_id)):
		return int(tbl[str(map_id)])
	return -1


## Adopt the manifest's ROM-sourced "render" block (grow_limit / hold_frames /
## edge / prim_y_base, all cited to ATTACK.OUT offsets). Missing keys keep the
## current default, so a missing manifest still animates faithfully.
func configure_render(r: Dictionary) -> void:
	grow_limit = maxf(1.0, float(r.get("grow_limit", grow_limit)))
	hold_frames = int(r.get("hold_frames", hold_frames))
	edge = float(r.get("edge", edge))
	prim_y_base = float(r.get("prim_y_base", prim_y_base))
	_set_param("edge_frac", edge / maxf(1.0, grow_limit))


## Begin {91}: resolve `slot` to a texture (adopting the manifest animation), set
## `speed`, and reset both wipe fronts. `x`/`y` are the opcode placement offsets
## (px in a 256x240 frame; 0 = the default anchored position).
func start(slot: int, speed_operand: int = 1, x: int = 0, y: int = 0) -> void:
	_slot = slot
	speed = maxf(1.0, float(speed_operand))
	_resolve_slot(slot, x, y)
	_frame = 0
	_reveal_front = 0.0
	_erase_front = 0.0
	# Live (→ the VM blocks on it) only when the map HAS a title, i.e. the slot
	# resolved (>= 0). An UNMAPPED map (slot -1) must NOT arm the ~606-frame block
	# on a strip that renders nothing — that would freeze the scene ~10 s looking
	# like a hang. A valid slot whose PNG is merely absent (fresh clone / CI before
	# bootstrap) still sequences so is_live() timing holds; `visible` gates the draw.
	_live = slot >= 0
	_push_uniforms()
	visible = _tex != null


## Advance one per-vblank VM frame. Phases (§6.4-§6.5): reveal wipe -> hold ->
## erase wipe -> complete. No-op once finished.
func tick() -> void:
	if not _live:
		return
	_frame += 1
	var step := grow_step * speed
	var grow_frames := int(ceil(grow_limit / step))
	var hold_end := grow_frames + hold_frames
	var erase_end := hold_end + grow_frames
	if _frame <= grow_frames:
		# Reveal: front sweeps L->R; nothing erased yet.
		_reveal_front = minf(grow_limit, float(_frame) * step)
		_erase_front = 0.0
	elif _frame <= hold_end:
		# Hold: fully revealed, no erase.
		_reveal_front = grow_limit
		_erase_front = 0.0
	elif _frame < erase_end:
		# Erase: a SECOND L->R front sweeps across, turning the strip back off
		# from the left (§6.5) — NOT a global brightness fade.
		_reveal_front = grow_limit
		_erase_front = minf(grow_limit, float(_frame - hold_end) * step)
	else:
		# Erased away — the strip is gone.
		_reveal_front = grow_limit
		_erase_front = grow_limit
		_live = false
		visible = false
	_push_uniforms()


## True while the strip is still on screen (revealing, held, or erasing) — the
## {91} handler parks the main VM context until this clears (the FUN_8014c9d0 wait).
func is_live() -> bool:
	return _live


## Force the strip to its fully-erased terminal state without spending frames — the
## fast-play settle guarantee (ScenarioVM.settle_screen_effects). No-op once erased.
## Mirrors letting `tick()` run past `erase_end`.
func settle() -> void:
	if not _live:
		return
	_reveal_front = grow_limit
	_erase_front = grow_limit
	_live = false
	visible = false
	_push_uniforms()


## Monotonic frame counter since start() — the progress probe the VM's wait-until
## watchdog polls, so the ~591-frame block never spuriously times out.
func progress() -> int:
	return _frame


## Reveal front position in px (0..grow_limit), for tests / F3.
func reveal_front() -> float:
	return _reveal_front


## Erase front position in px (0..grow_limit), for tests / F3.
func erase_front() -> float:
	return _erase_front


## The MAPTITLE slot currently shown (-1 if idle/unresolved), for tests / debug.
func slot() -> int:
	return _slot


# --- Internals ---------------------------------------------------------------

## Look up the slot in the manifest, load its texture, adopt animation params,
## and place the strip. Leaves `_tex = null` (render off) if unresolved.
func _resolve_slot(slot_idx: int, x: int, y: int) -> void:
	_tex = null
	if slot_idx < 0:
		return
	var entry: Dictionary = _lookup(slot_idx)
	if entry.is_empty():
		return
	var render = _manifest.get("render", null)
	if render is Dictionary:
		configure_render(render)
	var path: String = TITLES_DIR + str(entry.get("file", ""))
	if not ResourceLoader.exists(path):
		return
	_tex = load(path) as Texture2D
	if _tex == null:
		return
	var w := float(entry.get("w", STRIP_W))
	var h := float(entry.get("h", STRIP_H))
	# Vertical placement is ROM-sourced: the strip's primitive-space top is
	# prim_y_base (ATTACK.OUT +96); band centre = (prim_y_base + h/2)/240. X is
	# centred (authored-centred strip + battle draw-env). The opcode X/Y operands
	# nudge the anchored centre (px→UV).
	var center := Vector2(
		SCREEN_CENTER_X + float(x) / REF_W,
		(prim_y_base + h * 0.5) / REF_H + float(y) / REF_H)
	var half := Vector2((w / REF_W) * 0.5, (h / REF_H) * 0.5)
	_set_param("tex", _tex)
	_set_param("dst_center", center)
	_set_param("dst_half", half)


## Manifest entry for a slot, or {} if the manifest / slot is absent.
func _lookup(slot_idx: int) -> Dictionary:
	if not _manifest_loaded:
		_load_manifest()
	var titles = _manifest.get("titles", {})
	if titles is Dictionary:
		return titles.get(str(slot_idx), {})
	return {}


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


func _push_uniforms() -> void:
	_set_param("reveal", _reveal_front / maxf(1.0, grow_limit))
	_set_param("erase", _erase_front / maxf(1.0, grow_limit))


func _set_param(name: String, value) -> void:
	if _mat_text != null:
		_mat_text.set_shader_parameter(name, value)
	if _mat_shadow != null:
		_mat_shadow.set_shader_parameter(name, value)


func _build_render() -> void:
	# Two passes (§6.3): additive white text, then a subtractive drop-shadow. Both
	# share the reveal/erase/dither logic; only the blend mode + shadow offset differ.
	# Shadow drawn under the text (lower priority) so the text wins on the body.
	_mat_shadow = _make_pass("res://assets/shaders/show_map_title_shadow.gdshader", 101)
	_mat_text = _make_pass("res://assets/shaders/show_map_title.gdshader", 102)
	_mmi_shadow = _make_overlay_quad("ShowMapTitleShadow", _mat_shadow)
	_mmi_text = _make_overlay_quad("ShowMapTitleText", _mat_text)


func _make_pass(shader_path: String, priority: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.render_priority = priority  # over the map/units (matches Show Graphic)
	mat.set_shader_parameter("dst_half", Vector2(0.5, STRIP_H / REF_H * 0.5))
	mat.set_shader_parameter("dst_center",
		Vector2(SCREEN_CENTER_X, (prim_y_base + STRIP_H * 0.5) / REF_H))
	mat.set_shader_parameter("reveal", 0.0)
	mat.set_shader_parameter("erase", 0.0)
	mat.set_shader_parameter("edge_frac", edge / maxf(1.0, grow_limit))
	return mat
