class_name ScenarioWeather
extends Node3D
## Event-script {3C} "Weather" — the map-wide rain particle system. World-space
## 3D particles positioned in the battle scene, but drawn as SCREEN-SPACE
## constant-size vertical streaks to match the PSX ORTHOGRAPHIC draw (occlusion
## is still FREE from the depth buffer, mirroring the PSX shared ordering-table
## depth-sort). Owned by ScenarioVM, ticked once per 60 Hz VM frame.
##
## Faithful to the live-hardware RE (research/working_documents/
## WEATHER_OPCODE_3C_INVESTIGATION.md §10/§11/§12 + the §15 render re-derivation):
##   - RAIN = a FIXED 32 drops, template-free (§12 GAP 1).
##   - Each drop is a 2-endpoint WORLD-VERTICAL streak (shared X/Z, bottom + top Y)
##     that falls each frame by `vy = (fa6a4 + layer)·2` PSX sub-units, where `layer`
##     is the near bonus `fa6a8` for slots 0..15 and the far bonus `fa6ac` for 16..31.
##   - §15.1 (live-measured): the streak projects PERFECTLY SCREEN-VERTICAL under the
##     iso camera (`R12=0` → `dScreenX=0` for all 32 drops, at any FFT camera angle),
##     ORTHOGRAPHIC (constant screen size regardless of depth, `0.894 px/obj-unit`),
##     ~1 px wide. So we draw each drop as a screen-space billboard: long axis =
##     screen-Y, pixel length = `0.894·ΔY_obj·(viewport_h/240)`, constant width. This
##     is NOT a world-vertical ribbon (Godot's perspective camera would slant + scale
##     those into the "comets" the port previously showed).
##   - §15.2: additive-QUARTER blend (abr=3, dst+src/4), NO alpha. Per-drop brightness
##     = additive intensity over the (varying) background × the CLUT grey ramp
##     (bright head 224 → faint tail 24). Only the ~5-texel head shows → drops read as
##     small marks. Reproduced by an additive grey-ramp texture, alpha ignored.
##   - §15.3: splats are CONDITIONAL (~58% of landings). A drop only splats if its
##     streak STRADDLES the ground line in one frame (`bottom≥ground AND top<ground`);
##     a short/fast streak overshoots and skips. Not RNG, not unconditional.
##   - §15.4: real splats are thin, DIM, sparse diamond-ring OUTLINES (grey 40–120,
##     additive/4) that expand dot→small→wide→broken over 4 held-4-frame steps
##     (§12 GAP 2) — not clean bright filled ellipses.
##
## Modernization (user steer): the PSX baked per-map coarse ground-height grid
## (0x8018f8cc) is an optimization artifact and is NOT reproduced. Instead each
## drop's ground line is the height of the map tile it spawns over, sampled once
## at spawn. A flat default plane is the fallback when no tile is present.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice


# --- Faithful constants ------------------------------------------------------

## Rain always spawns exactly 32 drops (§12 GAP 1 — the rain path is template-free;
## the 64-particle template is snow-only).
const DROP_COUNT := 32
## PSX sub-units per tile (the scatter box uses `mapTiles · 28`).
const SUBUNITS_PER_TILE := 28.0
## Per-frame velocity scalar `DAT_80045980` (§12 GAP 3): `vy = (fa6a4 + layer)·2`.
const ANIM_SPEED_SCALAR := 2.0
## Slots 0..15 take the near layer bonus (fa6a8); 16..31 the far bonus (fa6ac).
const NEAR_LAYER_SLOTS := 16
## Splat `active` countdown length (§12 GAP 2 — spawns at 16, plays 16 frames).
const SPLAT_LIFE := 16
## Bottom-endpoint spawn depth in PSX sub-units (`Y = −0x180`, §12 GAP 1).
const SPAWN_BOTTOM_SUB := -384.0
## The nominal ground line `s2` in PSX sub-units (the uniform −48 drop-conversion
## threshold seen live for edge/default cells, §11.8/§12 GAP 4). We anchor each
## drop's world ground height at this abstract line, so the PSX fall math stays
## faithful while the *world* landing height comes from the map tile.
const GROUND_LINE_SUB := -48.0
## Orthographic vertical projection scale (§15.1): obj-Y projects at R22/4096 px
## per sub-unit. Streak screen length = `PX_PER_SUBUNIT_Y · ΔY_obj · viewport/240`.
const PX_PER_SUBUNIT_Y := 0.894
## The PSX native framebuffer height the pixel sizes are measured against (§15.1).
const REF_HEIGHT := 240.0

# --- Configuration (set by the host before the first set_weather) ------------

## Map footprint in tiles; the scatter box is `X∈[0,map_width)`, `Z∈[0,map_depth)`
## in Godot world units (1 tile = 1 world unit; tile (gx,gz) centre is gx+0.5).
var map_width: int = 10
var map_depth: int = 14
## The terrain PORT, used to sample each drop's ground-line world height once at
## spawn. Null → flat default.
##
## This field's docstring used to be a payload field-list written in ENGLISH —
## "MapComposer (or any node exposing get_tile(x,z) -> {global_position})" — which
## ADR-0164 dec. 2 cites as one of the two places the consumers asked for this port in
## prose because the type system was dodged. The prose is now a type.
var lattice: Lattice = null
## World Y used as the ground line when no tile is found (edge/off-map columns).
var default_ground_y: float = 0.0
## Optional test/host override for ground sampling: `Callable(tx:int, tz:int) -> float`.
## When set it replaces the lattice lookup (keeps the sim scene-free in tests).
var ground_sampler: Callable = Callable()
## Deterministic RNG — seedable so the sim is reproducible under test.
var rng := RandomNumberGenerator.new()

# --- Tunable look (live-adjustable via the F3 Weather panel) ------------------

# --- {3C} weather look tunables (ADR-0068) ----------------------------------
# Each slug's home lives HERE (not in ScenarioWeatherDebugPanel): a static-var DEFAULT
# (materializable, R1 — not a const, not a bind_update-forwarded property) plus a HINT const,
# bound in register_tunables(); the panel reads both back from the registry as a pure view.
const DROP_INTENSITY_SLUG := "weather.drop_intensity"
static var DROP_INTENSITY_DEFAULT := 0.25
const DROP_INTENSITY_HINT := {"min": 0.0, "max": 2.0, "step": 0.01}
const DROP_WIDTH_SLUG := "weather.drop_width_px"
static var DROP_WIDTH_DEFAULT := 1.4
const DROP_WIDTH_HINT := {"min": 0.1, "max": 8.0, "step": 0.1}
const DROP_LENGTH_SLUG := "weather.drop_length_scale"
static var DROP_LENGTH_DEFAULT := 1.0
const DROP_LENGTH_HINT := {"min": 0.0, "max": 4.0, "step": 0.05}
const SPLAT_INTENSITY_SLUG := "weather.splat_intensity"
static var SPLAT_INTENSITY_DEFAULT := 0.30
const SPLAT_INTENSITY_HINT := {"min": 0.0, "max": 2.0, "step": 0.01}
const SPLAT_SIZE_SLUG := "weather.splat_size"
static var SPLAT_SIZE_DEFAULT := 0.6
const SPLAT_SIZE_HINT := {"min": 0.05, "max": 4.0, "step": 0.05}
const SPLAT_STRADDLE_GATE_SLUG := "weather.splat_straddle_gate"
static var SPLAT_STRADDLE_GATE_DEFAULT := true  # bool → view renders a checkbox, no hint

## Additive-quarter brightness (§15.2: abr=3 → dst+src/4; the head grey 224/255 ×
## this ≈ +0.22 to the framebuffer). PSX drop vertex colour was 0x64 grey.
var drop_intensity: float = DROP_INTENSITY_DEFAULT:
	set(v):
		drop_intensity = v
		if _drop_mmi != null and _drop_mmi.material_override != null:
			_drop_mmi.material_override.set_shader_parameter("intensity", v)
## Drop streak width in PSX pixels (§15.1: ~1 px, constant screen width).
var drop_width_px: float = DROP_WIDTH_DEFAULT:
	set(v):
		drop_width_px = v
		if _drop_mmi != null and _drop_mmi.material_override != null:
			_drop_mmi.material_override.set_shader_parameter("width_px", v)
## Multiplier on the orthographic streak length (1.0 = faithful 0.894 px/sub-unit).
var drop_length_scale: float = DROP_LENGTH_DEFAULT
## Splat additive brightness (§15.4: dim — ring grey 40–120, additive/4).
var splat_intensity: float = SPLAT_INTENSITY_DEFAULT:
	set(v):
		splat_intensity = v
		if _splat_mmi != null and _splat_mmi.material_override != null:
			_splat_mmi.material_override.set_shader_parameter("intensity", v)
## Splat ground-ripple footprint, in world tiles.
var splat_size: float = SPLAT_SIZE_DEFAULT
## When false, EVERY landing splats (defeats the §15.3 straddle gate) — for live A/B.
var splat_straddle_gate: bool = SPLAT_STRADDLE_GATE_DEFAULT

# --- Runtime state -----------------------------------------------------------

var _active: bool = false
var _strength: int = 0
## (fa6a4, fa6a8, fa6ac) in PSX sub-units for the current strength.
var _triple := Vector3.ZERO

# Per-drop streak state. PSX-space Y (sub-units, Y-DOWN: more negative = higher);
# converted to world Y-up at render via each drop's own ground height.
var _psx_bottom := PackedFloat32Array()
var _psx_top := PackedFloat32Array()
var _drop_x := PackedFloat32Array()   # world X (tiles)
var _drop_z := PackedFloat32Array()   # world Z (tiles)
var _ground_y := PackedFloat32Array() # world Y of this drop's ground line

# Per-splat ripple state (one slot per drop; splat inherits the drop's landing X/Z).
var _splat_active := PackedInt32Array()  # 16..0 alive, <0 = free
var _splat_x := PackedFloat32Array()
var _splat_z := PackedFloat32Array()
var _splat_y := PackedFloat32Array()

# Render resources (built lazily in _ready; guarded so the sim runs head-less-safe).
var _drop_mm: MultiMesh = null
var _drop_mmi: MultiMeshInstance3D = null
var _splat_mm: MultiMesh = null
var _splat_mmi: MultiMeshInstance3D = null


func _ready() -> void:
	_alloc_state()
	_build_render()
	_bind_tunables()


## Bind the {3C} weather look knobs to their `weather.*` Tune slugs (ADR-0068). The
## weather node OWNS these values, so a committed override coalesces the moment the VM
## lazily spawns the node (Orbonne PC-6) AND a live scrub re-drives it — the weather
## debug panel is just a view (decision 12). Because the override lives in Tune, the
## dialled-in look now survives a click-to-rewind scenario reload for free (the fresh
## node's bind re-reads it), so the panel no longer hand-pushes values across respawns.
## the value is applied via its setter (shader push) or read per-frame. bind is SPLIT from
## on_update (ADR-0068): register_tunables() binds the static-var homes + hints ONCE at class
## load (below), and each node instance subscribes an on_update push here — so a scrub re-drives
## every node with no rival default. Not @tool-guarded: ScenarioWeather never runs in the editor.
func _bind_tunables() -> void:
	Tune.on_update(self, DROP_INTENSITY_SLUG, func(v: float) -> void: drop_intensity = v)
	Tune.on_update(self, DROP_WIDTH_SLUG, func(v: float) -> void: drop_width_px = v)
	Tune.on_update(self, DROP_LENGTH_SLUG, func(v: float) -> void: drop_length_scale = v)
	Tune.on_update(self, SPLAT_INTENSITY_SLUG, func(v: float) -> void: splat_intensity = v)
	Tune.on_update(self, SPLAT_SIZE_SLUG, func(v: float) -> void: splat_size = v)
	Tune.on_update(self, SPLAT_STRADDLE_GATE_SLUG, func(v: bool) -> void: splat_straddle_gate = v)


## Register `weather.*` slugs to their static-var homes + hints ONCE at class load (R2), so a
## committed override coalesces the instant the VM lazily spawns the node and the dashboard can
## enumerate the knobs before then. Split from _bind_tunables (the per-instance on_update push)
## as this owner's named registration entry point — _static_init calls it at class load, and
## the ADR-0173 guards call it to read back which slugs this owner binds.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


static func register_tunables() -> void:
	Tune.bind(DROP_INTENSITY_SLUG, DROP_INTENSITY_DEFAULT, DROP_INTENSITY_HINT)
	Tune.bind(DROP_WIDTH_SLUG, DROP_WIDTH_DEFAULT, DROP_WIDTH_HINT)
	Tune.bind(DROP_LENGTH_SLUG, DROP_LENGTH_DEFAULT, DROP_LENGTH_HINT)
	Tune.bind(SPLAT_INTENSITY_SLUG, SPLAT_INTENSITY_DEFAULT, SPLAT_INTENSITY_HINT)
	Tune.bind(SPLAT_SIZE_SLUG, SPLAT_SIZE_DEFAULT, SPLAT_SIZE_HINT)
	Tune.bind(SPLAT_STRADDLE_GATE_SLUG, SPLAT_STRADDLE_GATE_DEFAULT)


func _alloc_state() -> void:
	_psx_bottom.resize(DROP_COUNT)
	_psx_top.resize(DROP_COUNT)
	_drop_x.resize(DROP_COUNT)
	_drop_z.resize(DROP_COUNT)
	_ground_y.resize(DROP_COUNT)
	_splat_active.resize(DROP_COUNT)
	_splat_x.resize(DROP_COUNT)
	_splat_z.resize(DROP_COUNT)
	_splat_y.resize(DROP_COUNT)
	for i in DROP_COUNT:
		_splat_active[i] = -1


# --- Public API --------------------------------------------------------------

## Latch weather on/off. `active=false` (or strength < 2) cancels: all particles
## stop and the meshes hide. `active=true` (re)seeds the 32 drops scattered over
## the map footprint and across their fall so they don't all start at the top.
func set_weather(active: bool, strength: int) -> void:
	_strength = strength
	if not active:
		_active = false
		_hide_all()
		return
	_active = true
	_triple = ScenarioDecode.weather_velocity_triple(strength)
	if _psx_bottom.is_empty():
		_alloc_state()
	for i in DROP_COUNT:
		_respawn_drop(i, true)
		_splat_active[i] = -1
	_sync_render()


## Advance the particle sim one game frame (called at 60 Hz from ScenarioVM). No-op
## while inactive. Integrates the fall, converts STRADDLING drops to splats (§15.3)
## + respawns every crossing drop, and ages live splats, then syncs the MultiMesh.
func tick() -> void:
	if not _active:
		return
	var fa6a4 := _triple.x
	for i in DROP_COUNT:
		var layer := _triple.y if i < NEAR_LAYER_SLOTS else _triple.z
		var vy := (fa6a4 + layer) * ANIM_SPEED_SCALAR  # sub-units/frame (Y-down)
		_psx_bottom[i] += vy
		_psx_top[i] += vy
		# The bottom crossed the ground line. §15.3: splat ONLY if the streak still
		# straddles (top above the line) — a short/fast streak that overshot both
		# endpoints below the line skips its splat. Respawn on every crossing.
		if _psx_bottom[i] >= GROUND_LINE_SUB:
			if _psx_top[i] < GROUND_LINE_SUB or not splat_straddle_gate:
				_spawn_splat(i)
			_respawn_drop(i, false)
	for i in DROP_COUNT:
		if _splat_active[i] >= 0:
			_splat_active[i] -= 1
	_sync_render()


# --- Sim helpers -------------------------------------------------------------

## Reset drop `i` to the top with a fresh scatter position, ground line, and a
## randomized streak length + head-start. `initial=true` also randomizes the
## bottom's vertical progress so a fresh field is spread across the fall.
func _respawn_drop(i: int, initial: bool) -> void:
	var x := rng.randf() * float(map_width)
	var z := rng.randf() * float(map_depth)
	_drop_x[i] = x
	_drop_z[i] = z
	_ground_y[i] = _sample_ground(int(floor(x)), int(floor(z)))
	# Streak length + head-start: top = bottom − fa6a4 − rand()%(fa6a8·12) (§12 GAP 1).
	var scatter_span := maxi(1, int(_triple.y) * 12)
	var streak := _triple.x + float(rng.randi_range(0, scatter_span - 1))
	var bottom := SPAWN_BOTTOM_SUB
	if initial:
		# Spread the field vertically so drops don't all start at the ceiling.
		bottom = rng.randf_range(SPAWN_BOTTOM_SUB, GROUND_LINE_SUB)
	_psx_bottom[i] = bottom
	_psx_top[i] = bottom - streak


## Convert drop `i` to a splat pinned at its landing X/Z and ground height (§11.7).
func _spawn_splat(i: int) -> void:
	_splat_active[i] = SPLAT_LIFE
	_splat_x[i] = _drop_x[i]
	_splat_z[i] = _drop_z[i]
	_splat_y[i] = _ground_y[i]


## The ground-line world Y for the map tile at (tx,tz): the injected sampler wins,
## then the map tile height, else the flat default. This is the modernized stand-in
## for the PSX baked 0x8018f8cc grid (per-tile-at-spawn, user steer).
func _sample_ground(tx: int, tz: int) -> float:
	if ground_sampler.is_valid():
		return float(ground_sampler.call(tx, tz))
	# Rain lands on the ground of a column — the PSX grid this stands in for is
	# per-column too (ADR-0219 does not give weather a level).
	var cell := lattice.ground_at(tx, tz) if lattice != null else null
	if cell != null:
		return lattice.world_position_at(cell.grid).y
	return default_ground_y


## The ripple frame (0..3 = dot→ring→ellipse→dissipate) for a splat `active`
## countdown (§12 GAP 2). PSX updates the UV only when `active&3==0` (every 4th
## frame) so each ripple frame is HELD for 4 game-frames: active 16..9 = dot,
## 8..5 = ring, 4..1 = ellipse, 0 = dissipate.
static func splat_frame(active: int) -> int:
	return clampi(3 - ((active + 3) >> 2), 0, 3)


# World-space Y (up) of the drop midpoint given its PSX-space Y (down). Anchored so
# `psx == GROUND_LINE_SUB` maps to the drop's world ground height. Only the anchor
# position uses world units; the streak LENGTH is screen-space (§15.1).
func _midpoint_world_y(ground: float, psx_y: float) -> float:
	return ground + (GROUND_LINE_SUB - psx_y) / SUBUNITS_PER_TILE


# --- Rendering ---------------------------------------------------------------

func _build_render() -> void:
	# Drops: screen-space vertical streaks (a unit QuadMesh billboarded to constant
	# screen-pixel size in the vertex shader — orthographic, screen-vertical, §15.1).
	var drop_quad := QuadMesh.new()
	drop_quad.size = Vector2(1.0, 1.0)
	_drop_mm = MultiMesh.new()
	_drop_mm.transform_format = MultiMesh.TRANSFORM_3D
	_drop_mm.use_custom_data = true
	_drop_mm.mesh = drop_quad
	_drop_mm.instance_count = DROP_COUNT
	_drop_mm.visible_instance_count = 0
	_drop_mmi = MultiMeshInstance3D.new()
	_drop_mmi.name = "Drops"
	_drop_mmi.multimesh = _drop_mm
	_drop_mmi.material_override = _make_drop_material()
	# Vertices are repositioned in clip space; keep the whole box out of frustum cull.
	# Shares ScreenOverlayQuad's cull box (the same screen-space-mesh footgun).
	_drop_mmi.custom_aabb = ScreenOverlayQuad.CULL_AABB
	add_child(_drop_mmi)

	# Splats: flat ground ripples (a horizontal PlaneMesh, per-instance UV frame).
	var splat_plane := PlaneMesh.new()
	splat_plane.size = Vector2(1.0, 1.0)
	_splat_mm = MultiMesh.new()
	_splat_mm.transform_format = MultiMesh.TRANSFORM_3D
	_splat_mm.use_custom_data = true
	_splat_mm.mesh = splat_plane
	_splat_mm.instance_count = DROP_COUNT
	_splat_mm.visible_instance_count = 0
	_splat_mmi = MultiMeshInstance3D.new()
	_splat_mmi.name = "Splats"
	_splat_mmi.multimesh = _splat_mm
	_splat_mmi.material_override = _make_splat_material()
	_splat_mmi.custom_aabb = ScreenOverlayQuad.CULL_AABB
	add_child(_splat_mmi)


func _make_drop_material() -> ShaderMaterial:
	var sh := Shader.new()
	# Screen-space constant-pixel billboard: anchor the instance origin, then offset
	# each vertex in CLIP space by a constant pixel amount (÷ w cancels perspective).
	# INSTANCE_CUSTOM.x = streak length in PSX px; width_px + intensity are uniforms.
	# Additive-quarter, grey-ramp albedo, alpha ignored (§15.1/§15.2).
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear;
uniform float intensity = 0.25;
uniform float width_px = 1.4;
uniform float ref_height = 240.0;
void vertex() {
	vec4 view_anchor = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 clip = PROJECTION_MATRIX * view_anchor;
	float scale = VIEWPORT_SIZE.y / ref_height;      // PSX px -> viewport px
	float len_px = INSTANCE_CUSTOM.x * scale;
	float wid_px = width_px * scale;
	vec2 off_px = vec2(VERTEX.x * wid_px, VERTEX.y * len_px);
	clip.xy += off_px / (VIEWPORT_SIZE * 0.5) * clip.w;
	POSITION = clip;
}
void fragment() {
	// Grey ramp carries brightness; idx0 (black) adds nothing under additive blend.
	ALBEDO = texture(tex, UV).rgb * intensity;
	ALPHA = 1.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex", _make_drop_texture())
	mat.set_shader_parameter("intensity", drop_intensity)
	mat.set_shader_parameter("width_px", drop_width_px)
	mat.set_shader_parameter("ref_height", REF_HEIGHT)
	return mat


func _make_splat_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear;
uniform float intensity = 0.30;
void vertex() {
	// 4-frame ripple atlas laid out horizontally; INSTANCE_CUSTOM.x = frame 0..3.
	UV.x = (UV.x + INSTANCE_CUSTOM.x) * 0.25;
}
void fragment() {
	// Dim grey ring; additive, alpha ignored (black texels add nothing).
	ALBEDO = texture(tex, UV).rgb * intensity;
	ALPHA = 1.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex", _make_splat_texture())
	mat.set_shader_parameter("intensity", splat_intensity)
	return mat


## The live drop gradient strip (VRAM page(960,256) v=175, u=216→247; §15.2), baked
## as a vertical grey texture with the BRIGHT HEAD at the bottom (V=1) and the faint
## tail trailing up. Values are the CLUT greys; used as additive albedo (no alpha).
func _make_drop_texture() -> ImageTexture:
	# head-first order (u=216→247): quick ramp, 5-texel bright head, then linear fade.
	var grey := [72, 152, 184, 224, 224, 224, 224, 224, 200, 200, 184, 184, 168, 168,
		152, 152, 136, 136, 120, 120, 104, 104, 88, 88, 72, 72, 56, 56, 40, 40, 24, 24]
	var h := grey.size()
	var img := Image.create(2, h, false, Image.FORMAT_RGBA8)
	for row in h:
		# Bottom of the quad (V=1, the leading/falling head) = bright; top = tail.
		var g: float = float(grey[row]) / 255.0
		var v := h - 1 - row  # place head at the bottom texel
		var c := Color(g, g, g, 1.0)
		img.set_pixel(0, v, c)
		img.set_pixel(1, v, c)
	return ImageTexture.create_from_image(img)


## A 4-frame ripple atlas (64×16 = four 16×16 cells) matching the live splat cells
## (VRAM page(960,256) v=160–175, u∈{16,32,48,64}; §15.4): a thin DIM diamond-ring
## OUTLINE expanding dot→small→wide→broken. Grey (additive), NOT a filled ellipse.
func _make_splat_texture() -> ImageTexture:
	var cell := 16
	var img := Image.create(cell * 4, cell, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	# Per frame: ring radius (cell fractions), horizontal stretch, outline thickness,
	# and a dim base grey (matches live ring greys ~40–120 → 0.16–0.47). Frame 3 is a
	# broken/dissipating ring (drawn as sparse corner arcs via a lower coverage).
	var radii := [0.14, 0.34, 0.66, 0.82]
	var widths := [1.0, 1.15, 1.5, 1.7]
	var thick := [0.20, 0.16, 0.13, 0.13]
	var base := [0.28, 0.42, 0.34, 0.22]     # dim; frame1 brightest ring, frame3 faint
	var broken := [false, false, false, true]
	for f in 4:
		var r: float = radii[f]
		var xw: float = widths[f]
		var th: float = thick[f]
		var b: float = base[f]
		for y in cell:
			for x in cell:
				var nx := (float(x) + 0.5) / float(cell) * 2.0 - 1.0
				var ny := (float(y) + 0.5) / float(cell) * 2.0 - 1.0
				# Diamond/oval distance (L1-ish for the diamond look the live cells show).
				var d := absf(nx / xw) + absf(ny)
				var ring := 1.0 - clampf(absf(d - r) / th, 0.0, 1.0)
				var g := ring * b
				if broken[f]:
					# Knock out the ring's mid-edges → four corner arcs (dissipating).
					var ang := atan2(ny, nx)
					var gate := absf(sin(ang * 2.0))
					g *= smoothstep(0.25, 0.7, gate)
				if g > 0.002:
					img.set_pixel(f * cell + x, y, Color(g, g, g, 1.0))
	return ImageTexture.create_from_image(img)


func _hide_all() -> void:
	if _drop_mm != null:
		_drop_mm.visible_instance_count = 0
	if _splat_mm != null:
		_splat_mm.visible_instance_count = 0


## Push the current sim state into the MultiMesh instance transforms. Drops anchor
## at their world midpoint (the shader draws the screen-vertical streak around it);
## splats lie flat with a per-instance ripple frame.
func _sync_render() -> void:
	if _drop_mm == null:
		return
	for i in DROP_COUNT:
		var psx_mid := (_psx_bottom[i] + _psx_top[i]) * 0.5
		var anchor := Vector3(_drop_x[i], _midpoint_world_y(_ground_y[i], psx_mid), _drop_z[i])
		# Streak screen length in PSX px = 0.894 · ΔY_obj (orthographic, §15.1).
		var streak_sub := maxf(0.0, _psx_bottom[i] - _psx_top[i])
		var len_px := streak_sub * PX_PER_SUBUNIT_Y * drop_length_scale
		# Identity basis: the shader does the screen-space sizing, not the transform.
		_drop_mm.set_instance_transform(i, Transform3D(Basis(), anchor))
		_drop_mm.set_instance_custom_data(i, Color(len_px, 0.0, 0.0, 0.0))
	_drop_mm.visible_instance_count = DROP_COUNT

	if _splat_mm == null:
		return
	for i in DROP_COUNT:
		var active := _splat_active[i]
		if active < 0:
			# Collapse inactive splats to nothing (kept in the array for stable indices).
			_splat_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			_splat_mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
			continue
		var pos := Vector3(_splat_x[i], _splat_y[i] + 0.02, _splat_z[i])
		var basis := Basis().scaled(Vector3(splat_size, 1.0, splat_size))
		_splat_mm.set_instance_transform(i, Transform3D(basis, pos))
		_splat_mm.set_instance_custom_data(i, Color(float(splat_frame(active)), 0, 0, 0))
	_splat_mm.visible_instance_count = DROP_COUNT
