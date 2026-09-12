class_name ScenarioDarkScreen
extends ScreenOverlayQuad
## Event-script {76} "Dark Screen" — the overlay that dims the frame with an
## expanding, semi-transparent mosaic and then holds while {78} paints the
## victory-condition banner (intro) or the whole results sequence (outro) over it.
## Owned by ScenarioVM, ticked once per 60 Hz VM frame OUTSIDE the halt gate (like
## {3C} Weather / {1A} Map Darkness), so the mosaic settles even while the VM parks
## on the {E5} Wait For Instruction(0x36) barrier that follows.
##
## [b]The task body is `0x801CA664`, and it is read line by line[/b] in
## research/working_documents/DARKSCREEN_OPCODE_76_INVESTIGATION.md §13, then checked
## against the running emulator in §14 (all 288 slots dumped mid-retract: 0 lattice
## mismatches, delays exact across 113 independent values, sizes and angles exactly
## on their grids). BATTLE_RESULTS_SCREEN.md §17 is the live outro trace. The port
## follows that reading rather than §9/§11's earlier framebuffer-only model:
##
##   - [b]288 slots, 24 columns x 12 rows[/b], on the quincunx lattice below. Each is
##     ONE `POLY_F4` semi-transparent packet per frame — the "PSX draws each diamond
##     TWICE" reading was the slot's own A/B double buffer (§13), so a covered pixel
##     is a plain `½·bg + ½·F` and `dim` is 0.5. That is also why the mosaic and the
##     single full-screen quad the body swaps to at `0x801CADE4` look identical.
##   - [b]`Shape` is the sweep metric[/b], not decoration: it picks the distance `d`
##     each slot's spawn delay `d² / (256·ScreenExpansionSpeed)` is measured with.
##   - [b]The squares spin.[/b] They start axis-aligned (angle 0) and rotate to 512
##     = 45° as they grow, so they are the measured diamonds only at rest.
##   - [b]The retract is the same loop run backwards[/b] through the same per-slot
##     delays — same duration as the expansion, not a snappier one. A slot that has
##     not reached its turn is still submitted at FULL size, so the screen stays dark
##     ahead of the front and the corner farthest from the origin clears last.
##
## Rendered as ONE full-screen quad + assets/shaders/darkscreen_mosaic.gdshader. The
## shader owns no timing: this controller evaluates the per-slot law and uploads the
## 288 `(size, angle)` pairs as a 24x12 float texture, so `slot_size()`/`slot_angle()`
## are the single source of truth for what actually gets drawn.
##
## {77} Remove Dark Screen re-labels the task's kind (§13 — nothing re-enters the
## body) and the same loop runs backwards; once clear the controller parks.

## The display-space fold, through the schema addon's facade (ADR-0212 dec. 1).
const Fold = ExMateriaSchema.Fold
const DepthMode = ExMateriaSchema.DepthMode

## The dim's rung in the fold's order ladder. {78}'s banner sits on the rungs ABOVE
## it, which is the PSX's own order: the text is at OT bucket 0 and this tint at
## bucket 1, so the text draws over it (BATTLE_RESULTS_SCREEN.md §7).
const FOLD_RUNG_DIM := 0

const _MOSAIC_SHADER: Shader = preload("res://assets/shaders/darkscreen_mosaic.gdshader")
const _MOSAIC_FOLD_SHADER: Shader = preload("res://assets/shaders/darkscreen_mosaic_fold.gdshader")

# --- The lattice and the caps, out of 0x801CA724-0x801CA954 ------------------
## Columns x rows of the quincunx lattice — 288 slots, all 288 confirmed live (§14).
const LATTICE_COLS := 24
const LATTICE_ROWS := 12
## `size` cap (`0x801CAA3C`); the half-diagonal in pixels is `size / 4`, so a settled
## diamond is 12 px corner-to-centre and the field tessellates exactly.
const SIZE_MAX := 48
## `angle` cap — PSX angles are 4096 to the turn, so 512 is 45°: the quarter turn that
## takes an axis-aligned square to a diamond.
const ANGLE_MAX := 512
## PSX angle units in a full turn.
const ANGLE_TURN := 4096

# --- Timing -----------------------------------------------------------------
## Dead frames after dispatch before the mosaic starts expanding (~1.3 s @ 60 Hz) —
## §11.4's framebuffer time-series, which measured it from the opcode and so includes
## the `FUN_8013b590(0x27)` gate and the setup that precede the task body's own loop.
const DEAD_FRAMES := 78
## Vsyncs per `0x8014CA80` yield. The body advances every slot exactly once per yield,
## and a yield is NOT a frame (BATTLE_RESULTS_SCREEN.md §15 carries the warning) — this
## is a MEASUREMENT, taken twice and independently in §17: the slot counters themselves
## give `(160 - 129) / 15.5 = 2.0`, and the whole 53-yield Shape-1 retract took 112
## vsyncs = 2.11. It supersedes §11.4's ~73-frame expansion figure, which §14 flags as
## unreconciled with the same sweep's own yield count.
const VSYNCS_PER_YIELD := 2.1

# --- Render constants (§11.1/§13) -------------------------------------------
## Overlay colour F = RGB(48,40,16). NOT baked into the packet: `0x801CACCC` re-reads
## `0x801D0078..7A` into every diamond and into the settled quad every frame.
const FOG_COLOR := Color(48.0 / 255.0, 40.0 / 255.0, 16.0 / 255.0, 1.0)
## In-diamond alpha. One packet per diamond per frame at abr 0 = `½·bg + ½·F` (§13,
## retracting §11's double-blend reading).
const DIM_DEFAULT := 0.5

# --- Tunable look (live-adjustable via the F3 DarkScreen panel) ---------------

## In-diamond dim alpha — the PSX abr-0 half blend.
var dim: float = DIM_DEFAULT:
	set(v):
		dim = v
		_set_param("dim", v)

# --- Runtime state -----------------------------------------------------------

## +1 = growing in ({76}), -1 = retracting ({77}), 0 = idle/parked.
var _dir: int = 0
## Frames elapsed since {76} dispatch / since {77}.
var _frame: int = 0
## The decoded operands of the {76} in flight.
var _shape: int = 1
var _screen_expansion_speed: int = 12
var _square_expansion_speed: int = 4
var _rotation_speed: int = 0x40
## `max(delay) + SIZE_MAX/SquareExpansionSpeed` — how long one sweep runs, in yields.
var _sweep_yields: int = 1
## Per-slot spawn delay, row-major over LATTICE_ROWS x LATTICE_COLS.
var _delays: PackedInt32Array = PackedInt32Array()
## True while the mosaic is fully established (the body's single-quad hold phase).
var _settled: bool = false

var _mmi: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _state_img: Image = null
var _state_tex: ImageTexture = null


func _ready() -> void:
	_build_render()
	_rebuild_delays()
	_push_state(0)


# --- The per-slot law, straight out of 0x801CA664 ----------------------------

## Slot `(col, row)`'s centre in PSX framebuffer pixels (`0x801CA724`-`0x801CA954`).
## Odd columns are pushed a half-cell up — that offset is what makes the lattice a
## quincunx, and it puts the field one cell past every screen edge (x -12..264,
## y -24..252 over a 256x240 frame).
static func lattice_center(col: int, row: int) -> Vector2i:
	var cx := -12 + 12 * col
	var cy := (24 * row - 24) if (col & 1) else (-12 + 24 * row)
	return Vector2i(cx, cy)


## Yields slot `center` waits before it is first drawn: `d² / (256·speed)`, where
## `Shape` picks `d` (`0x801CA768`-`0x801CA7E8`, common tail `0x801CA898`).
## `SquareRoot0` truncates, so `d` is an integer before it is squared.
##   0 — a circle growing out of the screen centre (18 sites: every Deep Dungeon
##       battle, Yuguo Woods, Balk I, both Bethla walls, the tutorial, ...)
##   1 — a quarter-circle out of the top-left corner (134 sites, the shipped default)
##   2 — a vertical front wiping left to right (exactly ONE site: event 374,
##       *Rescue of Cid*)
##  >=3 — a diagonal band about the anti-diagonal. Unreachable in the shipped game:
##       the 500-event census only ever emits 0, 1 and 2.
static func slot_delay(center: Vector2i, shape: int, screen_expansion_speed: int) -> int:
	var speed := maxi(1, screen_expansion_speed)
	var d := 0
	match shape:
		0:
			d = int(sqrt(float((center.x - 128) * (center.x - 128)
				+ (center.y - 128) * (center.y - 128))))
		1:
			d = int(sqrt(float(center.x * center.x + center.y * center.y)))
		2:
			d = absi(center.x)
		_:
			# |ApplyMatrixLV(RotMatrix(0,0,512), (cx-128, cy-128, 0)).x| — the 45°-
			# rotated x, i.e. distance from the anti-diagonal through screen centre.
			var t := float(ANGLE_MAX) / float(ANGLE_TURN) * TAU
			d = absi(int(float(center.x - 128) * cos(t) - float(center.y - 128) * sin(t)))
	return (d * d) / (256 * speed)


## A slot's `size` `t` yields after its turn came. Growing: `size += SquareExpansionSpeed`
## capped at 48. Retracting: it starts full — a slot whose turn has NOT come is
## re-submitted at full size, which is why the dim stays solid ahead of the front —
## then `size -= SquareExpansionSpeed` floored at 0.
static func slot_size(yields_since_turn: int, square_expansion_speed: int, retracting: bool) -> int:
	var step := maxi(1, square_expansion_speed)
	if retracting:
		return clampi(SIZE_MAX - step * maxi(0, yields_since_turn), 0, SIZE_MAX)
	return clampi(step * maxi(0, yields_since_turn), 0, SIZE_MAX)


## A slot's `angle` `t` yields after its turn came — the spin that takes an
## axis-aligned square (0) to the settled diamond (512 = 45°). At the shipped
## `RotationSpeed = 0x40` it finishes in 8 yields against the size's 12.
static func slot_angle(yields_since_turn: int, rotation_speed: int, retracting: bool) -> int:
	var step := maxi(0, rotation_speed)
	if retracting:
		return clampi(ANGLE_MAX - step * maxi(0, yields_since_turn), 0, ANGLE_MAX)
	return clampi(step * maxi(0, yields_since_turn), 0, ANGLE_MAX)


# --- Public API --------------------------------------------------------------

## Begin {76}: seed the operands, rebuild the per-slot delays, reset to the dead delay.
func start(intent: ScenarioDecode.DarkScreenIntent) -> void:
	_shape = intent.shape
	_screen_expansion_speed = maxi(1, intent.screen_expansion_speed)
	_square_expansion_speed = maxi(1, intent.square_expansion_speed)
	_rotation_speed = maxi(0, intent.rotation_speed)
	_rebuild_delays()
	_dir = 1
	_frame = 0
	_settled = false
	_push_state(0)
	visible = true


## Begin {77}: run the same sweep backwards through the same per-slot delays.
func remove() -> void:
	_dir = -1
	_frame = 0
	_settled = false
	_push_state(0)


## How many yields one sweep takes: the last slot's delay plus the yields its square
## needs to finish growing. 53 for the shipped `Shape 1` / `0x0C` / `0x04` operands.
func sweep_yields() -> int:
	return _sweep_yields


## The same span in 60 Hz frames. 112 for the shipped operands — which is what §17
## measured off the live emulator for {76}'s teardown.
func sweep_frames() -> int:
	return ceili(float(_sweep_yields) * VSYNCS_PER_YIELD)


## Advance the animation one 60 Hz VM frame. No-op while idle.
func tick() -> void:
	if _dir == 0:
		return
	_frame += 1
	var active := (_frame - DEAD_FRAMES) if _dir == 1 else _frame
	var y := int(floor(float(maxi(0, active)) / VSYNCS_PER_YIELD))
	if y >= _sweep_yields:
		if _dir == 1:
			# The mosaic is established: the body swaps to ONE full-screen quad and
			# re-labels its kind 0x36 -> 0x37, which is what frees the {E5} barrier.
			_settled = true
		else:
			_settled = false
			visible = false
		_dir = 0
		_push_state(_sweep_yields)
		return
	_push_state(y)


## True while a sweep is in flight in EITHER direction — the kind-54 ({E5}) barrier
## holds on this. Releases only when the controller parks.
##
## 🔴 THIS USED TO BE `_dir == 1`, and that is the READY!-fadeout freeze (#1168). The
## barrier is on the task KIND, not on the direction: `{76}`'s body re-labels its slot
## `0x36` -> `0x37` once the mosaic is established (which is what frees the `{E5} 36 00`
## after the grow-in), and `{77}` re-labels it BACK to `0x36` and runs the same loop
## backwards — so the `{E5} 36 00` that follows `{77}` waits for the task to EXIT, i.e.
## for the whole 112-frame retract (BATTLE_RESULTS_SCREEN.md §13, DARKSCREEN §13).
## Reading only the grow-in made that second barrier release on the frame `{77}` ran,
## so the intro's last 1.87 s never played: the dim was still fully up when `{DB} Event
## End` fired and the navigator advanced into the battle build.
func is_sweeping() -> bool:
	return _dir != 0


## Force the animation to its terminal state without spending frames — the fast-play
## settle guarantee (a combat SEEK fast-forwards the opener at 30x and can park with
## the grow-in / retract still mid-flight; ScenarioVM.settle_screen_effects). A grow-in
## ({76}) lands fully established (still visible); a retract ({77}) lands cleared +
## hidden. No-op while idle. Mirrors letting `tick()` run to its last frame.
func settle() -> void:
	if _dir == 1:
		_settled = true
	elif _dir == -1:
		_settled = false
		visible = false
	_dir = 0
	_push_state(_sweep_yields)


## The current sweep 0..1, for the F3 panel / tests. 1.0 = fully established, 0.0 =
## nothing on screen.
func progress() -> float:
	if _settled:
		return 1.0
	if _dir == 0:
		return 0.0
	var active := (_frame - DEAD_FRAMES) if _dir == 1 else _frame
	var p := clampf(float(maxi(0, active)) / (float(_sweep_yields) * VSYNCS_PER_YIELD), 0.0, 1.0)
	return (1.0 - p) if _dir == -1 else p


## The decoded `Shape` in flight, for the F3 panel / tests.
func shape() -> int:
	return _shape


# --- Internals ---------------------------------------------------------------

## Recompute every slot's spawn delay (a pure function of Shape + ScreenExpansionSpeed)
## and the sweep length that falls out of it.
func _rebuild_delays() -> void:
	_delays.resize(LATTICE_ROWS * LATTICE_COLS)
	var worst := 0
	for row in LATTICE_ROWS:
		for col in LATTICE_COLS:
			var d := slot_delay(lattice_center(col, row), _shape, _screen_expansion_speed)
			_delays[row * LATTICE_COLS + col] = d
			worst = maxi(worst, d)
	_sweep_yields = maxi(1, worst + ceili(float(SIZE_MAX) / float(_square_expansion_speed)))


## Evaluate every slot at whole yield `y` and upload the 288 `(size, angle)` pairs.
## Nothing about the animation lives in the shader — it reads this texture and tests
## coverage, so `slot_size()`/`slot_angle()` are what actually ends up on screen.
func _push_state(y: int) -> void:
	if _state_img == null:
		return
	var retracting := _dir == -1
	for row in LATTICE_ROWS:
		for col in LATTICE_COLS:
			var t := y - _delays[row * LATTICE_COLS + col]
			_state_img.set_pixel(col, row, Color(
				float(slot_size(t, _square_expansion_speed, retracting)),
				float(slot_angle(t, _rotation_speed, retracting)), 0.0, 1.0))
	_state_tex.update(_state_img)
	_set_param("settled", _settled)


func _set_param(name: String, value) -> void:
	if _mat != null:
		_mat.set_shader_parameter(name, value)


func _build_render() -> void:
	# FORMAT_RGF (two 32-bit floats) so `size` and `angle` reach the shader as the
	# exact integers the law produced — an 8-bit texture would be resampled through
	# whatever colour space the renderer decided this image was in.
	_state_img = Image.create_empty(LATTICE_COLS, LATTICE_ROWS, false, Image.FORMAT_RGF)
	_state_tex = ImageTexture.create_from_image(_state_img)
	_mat = ShaderMaterial.new()
	# The dim folds whenever the build owns a fold, because {78}'s banner MUST fold and a
	# folded banner under an in-scene dim comes out with the fog painted over it — the fold
	# resolves at PRE_TRANSPARENT and in-scene transparents draw after it.
	_mat.shader = Fold.shader(_MOSAIC_FOLD_SHADER, _MOSAIC_SHADER)
	_mat.render_priority = 100  # off-fork: foreground overlay, over other transparents
	_mat.set_shader_parameter("fog_color", FOG_COLOR)
	_mat.set_shader_parameter("dim", dim)
	_mat.set_shader_parameter("slot_state", _state_tex)
	_mat.set_shader_parameter("settled", false)
	_mmi = _make_overlay_quad("DarkScreenQuad", _mat)
	Fold.add(_mmi, _mat, DepthMode.rung_z(FOLD_RUNG_DIM))
