class_name ScenarioCameraDirector
extends RefCounted
## The scenario-camera *director* — the stateful cinematic-camera slice lifted out
## of [ScenarioVM] into a subsystem the interpreter orchestrates.
##
## The Camera opcode ({19}), the Camera Fusion bracket ({1d}/{1e}), the ~11 hand-
## calibrated `camera_*` knobs, the screen-space→world pose transform, the per-frame
## lerp, and the fusion-chain spline all used to sit inline in the god-VM, poking
## `PlayerCamera`'s child nodes directly. That is the most-debugged, most-fragile
## behaviour in the file, and it shared a class (and a 138-member table) with the
## dialogue pool, the walker, and the tint state. This module owns that state and
## its apply, so the interpreter's Camera handlers shrink to one-line delegations
## and the RE calibration (the point of the tedious framing work) lives in one place.
##
## Behaviour is byte-identical to the pre-extraction VM — this is a refactor, not a
## re-decode. It is the stateful-director sibling of the pure [ScenarioDecode] layer:
## the VM-wide context it needs ([member ScenarioVM.player_camera],
## [member ScenarioVM.map_composer], [member ScenarioVM.map_size_z], the
## play-through knobs) is read live through a back-reference so there is a single
## source of truth; everything camera-specific is owned here. Operands are decoded
## through [EventInstructionSet] `args` (ADR-0059 Phase 2), same as the VM handlers.

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude
const CameraCalibration = ExMateriaPlatform.CameraCalibration


# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice
## And the same for `addons/exmateria_platform`, which shed `DisplayPort` — the
## name of a hardware standard — under ADR-0212 dec. 1.
const PsxNum = ExMateriaPlatform.PsxNum
## And the framing datum, which is NOT this file's to own any more: the gameplay rig
## (`addons/exmateria_battlefield/camera/PlayerCamera.gd`) frames the same tile and
## must land it on the same screen row, so the two constants moved to the one file
## both sides of the host/addon line may name.
const DisplayPort = ExMateriaPlatform.DisplayPort


const PsxChirality = ExMateriaPlatform.PsxChirality
const _CameraChainSpline = preload("res://src/scenarios/CameraChainSpline.gd")

## Back-reference to the owning interpreter. The director reads VM-wide context
## (the camera node, the map, the play-through gate, the operand decoder) through
## it live so those stay single-sourced on the VM.
var _vm: ScenarioVM = null

## Debug gate: when true the Camera opcode ({19}) is a no-op, so the scenario
## plays with the camera left wherever it is. Formerly the `SCENARIO_NO_CAMERA`
## boot env; now the "Disable camera takeover" checkbox on the Scenario Camera
## debug panel (ADR-0051 — scene config lives in panels, not env vars). The
## framing A/B knobs (backrotate / aim_floor / vertical_datum) are likewise on
## that panel; their former `SCENARIO_*` boot envs were retired with this one.
var camera_disabled: bool = false


func _init(vm: ScenarioVM) -> void:
	_vm = vm


# --- Calibration knobs -------------------------------------------------------

## Ortho size in Godot Display-space units that corresponds to ROM
## sprite_scale = 4096 (= 1.0x). At zoom=4096 → ortho = this value;
## at zoom=8192 → ortho = this / 2 (zoomed in); at zoom=2048 → ortho = ×2.
## Calibrated by visual comparison against the PCSX first-dialog savestate
## on MAP062 — 8.0 frames the chapel altar + Ovelia + flanking figures
## at roughly the same composition.
var camera_ortho_at_1x_zoom: float = 8.3

## Live rotation offset added to the opcode-derived camera rotation
## (degrees, per-axis). Useful to compensate for a misaligned forward
## ray when the ortho centering doesn't match PCSX perspective framing.
var camera_rotation_offset_deg: Vector3 = Vector3.ZERO

## H1 framing fix (`handoff_camera_framing_pivot.md`): PSX is fixed-camera-
## at-origin — `screen = R·world + T`, `T = −work_position` (`FUN_800ee95c`).
## So the world point that lands at SCREEN CENTRE is `R⁻¹·work_position`, the
## opcode position back-rotated by the inverse view rotation. Godot historically
## planted the ortho body at the *raw* axis-remapped opcode position, so the
## framing was only correct at the single yaw where the former constant camera offset (removed #139, ADR-0057)
## absorbed the fixed `R⁻¹`; any yaw change (the PC≈100 swoop) drifted the
## centre laterally ("scoot the camera over"). When this flag is ON,
## `_compute_camera_godot_pose` rotates the remapped opcode vector by the
## focus_point basis (the view→world, i.e. `R⁻¹`, analog) before planting the
## body, so the framed point holds across the whole swoop and
## the former constant camera offset (removed #139, ADR-0057) collapses toward a small residual. For an ortho
## camera only the in-plane components matter, so the PSX view-depth sign is a
## don't-care here. A/B live via the Scenario Camera debug panel.
##
## RESOLVED 2026-06-29 (living doc F6): the bug was the camera ORIENTATION, not
## the position. The GTE sets translation T = −R·work_position (FUN_800ee95c runs
## ApplyMatrix on −work_position with R loaded), so the PSX camera sits AT
## work_position — the raw position was always right. The empirical Euler
## orientation only approximated R, so the view direction drifted with yaw ("scoot
## the door back"). With this flag ON we orient from the EXACT captured GTE
## rotation R = Rx(pitch)·Ry(yaw)·Rz(roll) (Godot basis B = D·R⁻¹·D,
## D = diag(1,−1,−1), a pure rotation), and the door holds framed through the
## whole swoop with the former constant camera offset (removed #139, ADR-0057) ≈ 0.
##
## 2026-06-29 REVERTED TO DEFAULT OFF: A/B proved this is visually NEGLIGIBLE for
## the chapel (empirical orientation ≈ exact R → pixel-identical frames), so it
## does not fix the framing. Kept as an experimental knob; the real bug is still
## open — see `handoff_camera_framing_v2.md` (strongest lead: H2 chirality).
var camera_backrotate_pivot: bool = false

## Safety A/B knob for the back-rotation above: when ON, use `Basis.inverse()`
## instead of the forward basis. The derivation says the FORWARD basis is
## correct (focus_point basis = view→world = `R⁻¹`); this exists only so the
## opposite handedness can be ruled out headful without a relaunch. Leave OFF.
var camera_backrotate_invert: bool = false

## VERTICAL framing fix (living doc F8/F9 + `handoff_scenario_camera_vertical_impl`).
## The scenario ortho camera body IS the screen-centre (body → FocusPoint →
## Camera3D), so `godot_pos.y` is literally the world-Y the frame centres on.
## The raw opcode aim `−opcode_z/112` lands ~1 tile BELOW the chapel floor the
## units stand on (settled: aim 1.96 vs Agrias' feet at 3.04) — that 1.08-unit
## gap is the live-probed −29px vertical drop (subject framed too low).
##
## When this flag is ON, `_compute_camera_godot_pose` replaces `godot_pos.y`
## with the floor_y of the map tile the body hovers over (`_framed_floor_y`),
## a TERRAIN-AWARE aim (the chapel floor is NOT flat — MAP062 altar h7 vs nave
## h0-1). Because it is a true WORLD-space correction it projects correctly at
## every pitch, so it survives the PC≈100 swoop rotation (unlike the former
## constant camera offset (removed #139, ADR-0057), whose world offset projected
## to a yaw-DEPENDENT screen shift). Empirically (F8) Agrias native-Y 156.5 vs PSX 158.
##
## SETTLED-ONLY (F12): floor-aim is applied to at-rest / target poses, NOT to the
## in-motion swoop. STATIC + DYNAMIC proof (living doc F12): the PSX scenario camera
## Y is a pure interpolated opcode value with NO terrain read — event Camera writer
## `FUN_801474a4`, ticker `camera_per_vsync_ticker` @ 0x801439c0; the camera is
## married to a tile ONLY in the effect-camera tile-source path `FUN_801aab90` @
## 0x801aab90 (`Y=−height·12`), which the scenario never uses. So the per-tick floor
## pin (F11: ±5–8 tile jerks during the descent) was provably wrong. `aim_floor`
## (param on `_compute_camera_godot_pose`) gates it: `_apply_chain_spline_pose`
## passes `false` (raw opcode descent during motion); snap/lerp paths floor their
## settled TARGET (computed once → no jitter); the floored settle is re-applied once
## when the chain drains (`_settle_camera_onto_floor`). The swoop is smooth and the
## settled dialogue shot stays floored (F10: Agrias native-Y 162 vs PSX 158).
## NB the settled floor is a Godot ortho-vs-PSX-projection band-aid (F9 lateral bug),
## not PSX tile-marriage — PSX holds raw at the swoop end.
##
## A/B live via the Scenario Camera debug panel.
##
## 2026-06-29 — DEFAULT FLIPPED TO OFF (user decision): this is NOT authentic.
## F12 proved the PSX scenario camera Y is a pure interpolated opcode value with NO
## terrain read (writer `FUN_801474a4`, ticker `0x801439c0`); tile-marriage exists
## only in the effect-camera path the scenario never uses. The floor-aim was a
## band-aid for the lateral chirality bug, which F19 has now fixed at the source
## (`camera_flip_body_depth`). Keep it as an A/B knob, but ship OFF.
##
## ⚠️ Turning it off exposes a SEPARATE, still-open VERTICAL bug the band-aid was
## masking: the raw aim (`godot_pos.y = −opcode_Z/112`) frames Agrias at native-Y
## ≈120 vs PSX's ≈160 (~40px too HIGH) — even though F12 says raw opcode Y is what
## PSX uses. So the opcode-Z→Godot-Y datum/mapping has its own discrepancy (the
## vertical analog of the F19 horizontal story), to be root-caused, not re-band-aided.
var camera_aim_floor_y: bool = false

## LATERAL chirality fix (living doc F19) — the real "scoot the door back" bug.
## ADR-0052 depth-flips every UNIT (`godot_z = PsxNum.flip_depth_row(psx_z) =
## map_size_z−1 − psx_z`, now baked in the parser per #141), but the camera BODY
## depth was consumed RAW (`godot_pos.z = opcode_Y/112`), so the ortho camera
## filmed a depth-flipped world
## from an un-flipped position — a constant ~+21px lateral framing error (the
## long-deferred "LATERAL chirality bug" flagged in `_framed_floor_y`). This was
## masked, NOT fixed, by the former constant camera offset (removed #139, ADR-0057) (a constant world-X fudge that
## drifts with yaw) and partly by the floor-aim band-aid (`camera_aim_floor_y`).
##
## When ON, `_compute_camera_godot_pose` mirrors the body's depth the SAME way units
## are flipped (`godot_pos.z = (map_size_z−1) − opcode_Y/112`). VERIFIED to the pixel
## (F19): Agrias/Ovelia/priest land at native_par 107.6/148.4/66.7 vs the live PSX
## screen store 107/147/68 (≤1.4px). Falls back to the raw z when `map_size_z` is
## unset (VM-only tests / non-map scenes) so those paths are byte-for-byte untouched.
## NB this also re-points `_framed_floor_y` at the CORRECT tile, so the vertical
## (floor-aim) axis shifts — re-check it after enabling. A/B via the Scenario Camera
## debug panel.
var camera_flip_body_depth: bool = true

## VERTICAL DATUM fix (living doc F20) — the vertical analog of the F19 lateral fix,
## the bug `camera_aim_floor_y=OFF` exposed (units framed ~40px too HIGH).
##
## ROOT CAUSE (pinned authentically against the live GTE, not curve-fit). FFT's
## sprite projection is PURE AFFINE ORTHO: `screen = R·SV/4096 + TR` (read at the
## sprite-projection BP `0x80086ba0` → `0x80086ba8`: the feet SVECTOR (154,−84,98)
## maps via the captured R + TR=(196,315,452) to (235.7, 160.4) == the live store
## +0x120/+0x122 = 235/160, to the px; OFX=OFY=0, H unused for X/Y). Decomposing
## `TR = −R·work_position + (256, 160, …)` shows **work_position projects to screen
## (128, 160)** — horizontally CENTRED but VERTICALLY at 160, not the frame midpoint
## 120. So FFT frames the optical centre LOW; Godot's ortho rig centres it at native
## 120 → every unit lands ~40px too high (diag measured −40.3/−41.9/−40.6 across
## Agrias/Ovelia/priest — a CONSTANT datum, depth/yaw-independent, NOT perspective:
## the vertical slope already matches, F15).
##
## This is NOT the floor-aim band-aid: it reads no terrain (F12), it's a single
## constant, and it is yaw/pitch/depth-stable because it is applied POST-rotation
## (like the GTE's TR, added after R) — a SCREEN-SPACE vertical shift. When ON,
## `_compute_camera_godot_pose` shifts `godot_pos` along the camera's LOCAL-UP axis
## (from `godot_rot`) by the world distance that lands the subject
## `DisplayPort.VERTICAL_DATUM_PX` (= 160−120 = 40) native-px lower — the shared home,
## so this rig and `PlayerCamera` cannot frame the same tile two different ways —
## scaled by the ortho size so the PIXEL offset
## stays constant across the swoop's zoom. Falls back to no-op when `map_size_z` is
## unset (VM-only / non-map paths untouched). A/B via the Scenario Camera debug panel.
## Gate: `tests/ScenarioCameraVerticalDatumTest`.
var camera_vertical_datum: bool = true

## Screen-edge crop fractions (left, top, right, bottom — each 0.0..0.5).
## Renders black bars over the viewport edges so the user can "stop down"
## the image to match PCSX's tighter framing without changing the camera
## itself. Driven into the scene's CropOverlay node by ScenarioPlayerScene.
var camera_crop_padding: Vector4 = Vector4.ZERO
signal crop_padding_changed(value: Vector4)
func set_camera_crop_padding(v: Vector4) -> void:
	camera_crop_padding = v
	crop_padding_changed.emit(v)

## Interpolation curve applied per Camera opcode.
##
## **PSX uses LINEAR — verified by dynamic capture 2026-06-24.** Loaded
## `orbonne_prayer_cinematic.sstate`, dropped a Write BP at the live pitch
## register (`0x800A7784`, writer PC `0x8008BA68`, called from
## `FUN_801439C0` at ra `0x80143A04`), sampled 441 writes across ~10s of
## chapel cinematic. Findings:
##   * Camera writes fire every ~1,128,800 CPU cycles = 33.3 ms = **30 Hz**
##     (every other vsync), but the script's `Time` field is 60 Hz ticks —
##     `time_ticks / 60.0` for lerp duration stays correct.
##   * Per-frame pitch Δ is overwhelmingly ±1 with occasional ±2 — the
##     signature of linear interpolation with a fractional-rate fixed-point
##     accumulator. Never sees zero mid-segment.
##   * Velocity does drift across consecutive Camera opcodes (e.g.
##     -0.93/frame → -1.47/frame across our window) but each individual
##     opcode is constant-velocity; cinematic authors hand-tuned waypoint
##     spacing so consecutive opcodes hand off with similar speeds.
##   * Cosine ease-in-out per-opcode (the prior Godot default) drops
##     velocity to zero at every boundary — the "go-stop-go" the user
##     reported. PSX does not do this.
##
## COSINE_A / COSINE_B kept available behind the F3 dropdown for A/B
## verification on any specific shot that looks off — they are the curves
## FFT's *effect*-camera system exposes (CAMERA_SYSTEM.md), but the
## *scenario*-camera handler bakes in linear.
enum EaseMode { LINEAR, COSINE_A, COSINE_B }
var camera_ease_mode: int = EaseMode.LINEAR


# --- Interpolation / fusion-chain state --------------------------------------

# Last Camera opcode params — kept so the debug panel can re-apply with new
# calibration values without restarting the scenario.
var _last_camera_params: Dictionary = {}
var _has_last_camera: bool = false

# Whether the director currently holds the PlayerCamera. Latched on the first
# Camera opcode / chain arm so takeover is requested exactly once.
var _camera_taken_over: bool = false

# Camera-pose interpolation state. The Camera opcode's `Time` param is the
# number of 60 Hz ticks to lerp from the current pose to the new target — this
# is what produces the "swooping fly-through" sequences. The VM blocks on
# _wait_ticks for the same duration so subsequent opcodes don't pre-empt.
#
# Lerp progress is tracked in CONTINUOUS SECONDS (not VM ticks) so the visual
# update runs per host frame regardless of refresh rate — otherwise at >60 Hz
# refresh the camera holds its pose between ticks and the motion stutters.
var _cam_lerp_active: bool = false
var _cam_lerp_elapsed_s: float = 0.0
var _cam_lerp_duration_s: float = 0.0
var _cam_start_pos: Vector3
var _cam_start_rot: Vector3
var _cam_start_ortho: float
var _cam_target_pos: Vector3
var _cam_target_rot: Vector3
var _cam_target_ortho: float

## Camera Fusion (0x1d/0x1e) queued-lerp state. PSX dispatcher consumes
## the 0x1d..0x1e bracket atomically (probe_camera_vs_dialog_timing.py
## 2026-06-26: PSX dispatcher jumped from PC 121 op=0x1d directly to PC 225
## op=0x49 in 719 cycles, same vsync — all 6 Cameras + 0x1e skipped). The
## actual lerp drains through a background fiber while the VM races past.
##
## We mirror this in Godot by queueing Camera opcodes encountered while
## `_in_camera_fusion` is true and chaining them through `_advance_camera_lerp`
## (which already runs in `_process`, independent of `_wait_ticks`).
## `_op_camera_fusion_end` doesn't block — the chain continues in the
## background while the VM advances to subsequent opcodes (Wait, Display
## Message, etc.) — exactly the parallelism seen on PSX.
var _in_camera_fusion: bool = false
var _camera_queue: Array = []  # Array of param dicts {x,y,z,angle,map_rot,cam_rot,zoom,time}

## When true, fusion chains play through `CameraChainSpline` (FFT-faithful
## cross-segment Bezier blend, no velocity cliffs) instead of strict
## per-segment linear lerp. Default ON — verified bit-exact against PSX
## by `ScenarioChapelChainSplineTest` (±0.03 opcode units across 514
## ticks). Flip via F3 debug panel for A/B comparison against the
## strict-linear baseline.  See `CameraChainSpline.gd` and
## `research/working_documents/scenario_1_captures/cinematic_camera_motion_decode.md`.
var use_camera_chain_spline: bool = true
var _chain_spline: RefCounted = null
var _chain_spline_tick_acc: float = 0.0

## Final-waypoint params of the active fusion chain (last queued Camera op).
## Saved at `_start_chain_spline` so that when the spline DRAINS we can re-apply
## that pose WITH floor-aim and ease the camera onto the framed floor — the swoop
## itself runs floor-aim OFF (raw opcode descent, see `_apply_chain_spline_pose`
## + living doc F12: the PSX scenario camera Y is a pure interpolated opcode
## value, NEVER a per-tile terrain pin).
var _chain_final_params: Dictionary = {}
var _chain_final_valid: bool = false
## Ease (60 Hz ticks) for the settle-onto-floor nudge after the swoop drains.
## ~0.2s hides the raw→floored Y correction (≈29px at the chapel settled shot).
const _SWOOP_SETTLE_TICKS := 12

## Snapshot of `_last_camera_params` at the moment Camera Fusion Start fired,
## i.e. the pre-bracket pose (immediate Camera at PC=56 for chapel). Used as
## the spline's seg-0 target. Without this we'd grab the LAST queued Camera
## (chapel's PC=207) as the seed, which would run the chain backwards.
var _fusion_seed_camera_params: Dictionary = {}
var _fusion_seed_valid: bool = false

## True only during a chain handoff inside `_process` — tells
## `_apply_camera_pose_no_block` to use the just-completed segment's TARGET as
## the next segment's START instead of reading the live camera transform back.
## Two reasons:
##   1. Eliminates a one-frame stall at every chain boundary. The previous
##      implementation rendered `done=1.0` on the completing segment, then
##      started the new lerp at `elapsed=0` on the next frame — the camera
##      held at prev_target for one host frame at every boundary, visible as
##      a hitch in the chapel swoop. We carry the lerp overshoot
##      (`elapsed - duration`) into the new segment so the boundary frame
##      renders a true partial step of the new segment.
##   2. Removes the dependence on Godot synchronously flushing the global
##      transform between `apply_takeover` and the next-frame readback. With
##      the target-as-start handoff, the new segment is mathematically on-rails
##      from waypoint N-1's target to waypoint N's target — no race against the
##      Node3D transform tree.
## The first queued segment (started by `_op_camera_fusion_end`, not from
## `_process`) still uses live readback so the chain seeds from wherever the
## camera actually is when fusion opens.
var _chain_handoff: bool = false

## {1F} Focus / {38} Focus Speed pending state. On PSX, Focus is a bytecode patcher
## that rewrites the position operands of the *following* `{19}` Camera opcode with
## the target unit(s)' midpoint (and Focus Speed its `Time`). The Godot VM is linear
## — Focus/Focus Speed arrive as their own opcodes — so we mirror the effect by
## STASHING the intent here; the next `_op_camera` consumes it (overrides the
## authored X/Y/Z with the unit midpoint, and `Time` with the focus speed). Cleared
## on consumption / VM reset. See FOCUS_OPCODE_1F_INVESTIGATION.md §9.
var _pending_focus: ScenarioDecode.FocusIntent = null
var _pending_focus_time: int = -1

## Read-seam recording the LAST `{1F}` Focus consumption outcome (for the roster-fed
## navigator's end-to-end proof, which verifies scn-12's victory Focus re-aimed the
## camera onto the deployed Ramza rather than falling back to the authored pose).
## `last_focus_resolved` is true iff the most recent Camera-consumed Focus found its
## target unit(s); `last_focus_target_godot` is that resolved Godot-world midpoint.
## Untouched by a Camera op with no pending Focus.
var last_focus_resolved: bool = false
var last_focus_target_godot: Vector3 = Vector3.ZERO

## {73} Camera Move (relative) pending deltas. On PSX, {73} (FUN_801474a4) is a
## bytecode patcher — the sibling of {1F} Focus — that rewrites the FOLLOWING
## {19} Camera's first 7 operands with `live_camera_pose[f] + delta[f]` (Time
## left alone; a delta of 0x2710 = 10000 = "keep this field"). The Godot VM is
## linear, so we STASH the 7 signed deltas here; the next `_op_camera` consumes
## them (base = `_last_camera_params`, the live pose in opcode units). This is
## the scenario-6 PC 386 fix: it turns the authored `Zoom=0` filler into
## `live(4096)+0` = 4096, so the ortho no longer blows up to a wide teleport.
## Empty = none. Cleared on consumption / VM reset. See §4.4/§5.1 of
## CAMERA_ROTATION_OPCODES_63_73_19_INVESTIGATION.md.
var _pending_camera_delta: Array = []

## {73} "keep this field unchanged" sentinel (10000 = 0x2710) — a delta equal to
## this leaves the corresponding operand at its live value.
const CAMERA_DELTA_KEEP := 10000

## {63} Camera Speed Curve. `_pending_speed_curve` is the byte armed by a {63}
## opcode, consumed by the FOLLOWING {19} Camera (0 = none). `_active_curve_byte`
## is the curve driving the CURRENT lerp — latched at Camera-execution time so
## `_curve` shapes the swoop with the §4.7 closed form instead of the global
## `camera_ease_mode`. 0 on both means "fall back to `camera_ease_mode`" (LINEAR).
## Only the plain non-fusion lerp consumes it — the fusion spline has its own math
## (a documented gap; scenario 6's {63}/{73}/{19} orbit is non-fusion). See §5.2.
var _pending_speed_curve: int = 0
var _active_curve_byte: int = 0


# --- Per-frame drive + halt predicate ----------------------------------------

## Advance the camera one host frame — the fusion-chain spline step and the
## per-frame lerp. Called from `ScenarioVM._advance_frame` with the (possibly
## scaled) host delta so fast-play drives the SAME pipeline.
func tick(delta: float) -> void:
	# Spline-driven camera chain ticks at _TICK_HZ (matches the PSX 60 Hz
	# tick the spline math was derived from). Pose is held between ticks —
	# the chapel motion is smooth enough at 60 Hz that no per-frame
	# interpolation is needed; if anything wobbles, we can lerp between
	# adjacent ticks here.
	if _chain_spline != null:
		_chain_spline_tick_acc += delta * ScenarioVM._TICK_HZ
		while _chain_spline_tick_acc >= 1.0:
			_chain_spline_tick_acc -= 1.0
			var scratch: PackedInt32Array = _chain_spline.step()
			_apply_chain_spline_pose(scratch)
			if _chain_spline.done:
				print("[ScenarioVM] Camera-chain spline drained")
				_chain_spline = null
				_settle_camera_onto_floor()
				break

	# Per-frame camera-lerp advance — runs at the host frame rate so motion stays
	# smooth at any refresh, independent of the 60 Hz VM tick.
	if _cam_lerp_active:
		_cam_lerp_elapsed_s += delta
		if _cam_lerp_elapsed_s >= _cam_lerp_duration_s:
			var overshoot := _cam_lerp_elapsed_s - _cam_lerp_duration_s
			_cam_lerp_elapsed_s = _cam_lerp_duration_s
			_cam_lerp_active = false
			_advance_camera_lerp()  # final tick at done=1.0
			# Chain into the next queued Camera if any are pending (drains the
			# fusion-bracket queue; no-op when not in a fusion-driven chain).
			# `_chain_handoff` flips `_apply_camera_pose_no_block` to use the
			# just-completed segment's TARGET as the new START — see the flag's
			# docstring for the timing/jitter rationale.
			if not _camera_queue.is_empty():
				_chain_handoff = true
				_start_next_queued_camera()
				_chain_handoff = false
				# Carry the overshoot into the new segment so the boundary frame
				# renders a partial step instead of holding at prev_target for
				# one frame. Clamp to `_cam_lerp_duration_s` so a very-short
				# next segment (overshoot ≥ its duration) doesn't go negative —
				# in that pathological case the new segment renders at done=1.0
				# and completes on the next `_process` tick.
				if _cam_lerp_active and overshoot > 0.0:
					_cam_lerp_elapsed_s = minf(overshoot, _cam_lerp_duration_s)
					_advance_camera_lerp()
		else:
			_advance_camera_lerp()


## kind-4 predicate: true when no scenario camera motion is in flight — no
## per-frame lerp, no fusion-chain spline, and no queued camera waypoints.
func is_idle() -> bool:
	return not _cam_lerp_active and _chain_spline == null and _camera_queue.is_empty()


## Normalised lerp progress in [0,1] for the debug panel readout.
func get_lerp_progress() -> float:
	if not _cam_lerp_active or _cam_lerp_duration_s <= 0.0:
		return 0.0
	return clampf(_cam_lerp_elapsed_s / _cam_lerp_duration_s, 0.0, 1.0)


# --- Opcode handlers + apply -------------------------------------------------

## {1F} Focus — stash the pending focus so the FOLLOWING `{19}` Camera opcode
## re-aims onto the target unit(s)' midpoint (PSX patches that Camera op's operands
## in place; we mirror the effect at Camera-execution time). No immediate camera
## move — matches PSX, where Focus only rewrites the future Camera op.
func _op_focus(inst: Dictionary) -> void:
	_pending_focus = ScenarioDecode.focus(EventInstructionSet.args(inst))
	print("[ScenarioVM] Focus units=(0x%X,0x%X) auto_map_rotation=%s (pending; next Camera re-aims)" %
		[_pending_focus.unit1, _pending_focus.unit2, str(_pending_focus.auto_map_rotation)])


## {38} Focus Speed — stash the interpolation duration for the following Camera op
## (PSX Focus Speed rides the Camera writer's `Time`). Optional; absent → the
## Camera's authored `Time` stands.
func _op_focus_speed(inst: Dictionary) -> void:
	_pending_focus_time = EventInstructionSet.args(inst).raw("Speed", -1)
	print("[ScenarioVM] Focus Speed=%d (pending Camera Time override)" % _pending_focus_time)


## Resolve the pending Focus target to a Godot-world point (midpoint of the two
## named units). Returns null if neither unit is present — matching PSX's `0x7d0`
## absent-unit abort (the authored Camera pose then stands). A single-unit focus
## (unit1==unit2, the common case) returns that unit's position.
func _focus_midpoint_godot(intent: ScenarioDecode.FocusIntent):
	var positions: Array = []
	for uid in [intent.unit1, intent.unit2]:
		var key: int = _vm._resolve_unit_key(uid)
		if key < 0 or not _vm.units_by_id.has(key):
			continue
		var u = _vm.units_by_id[key]
		if not is_instance_valid(u) or not ("global_position" in u):
			continue
		positions.append(u.global_position)
	if positions.is_empty():
		return null
	var sum := Vector3.ZERO
	for pos in positions:
		sum += pos
	return sum / float(positions.size())


## The four 90° camera quadrants a Focus may re-aim onto — PSX table
## `0x80169718`, read in order by `FUN_80147318`. Every authored Map Rotation in
## the corpus is one of these, which is why the picker below is usually a no-op
## on an already-settled camera.
const FOCUS_MAP_ROTATIONS: Array[int] = [0xE00, 0xA00, 0x600, 0x200]


## The map rotation a `Unknown==0` Focus patches into the FOLLOWING `{19}` Camera's
## operand slot 4 — `FUN_80147318`, transcribed.
##
## PSX: `s3 = BATTLE_wrap_camera_yaw_angle() & 0xFFF` (the live yaw, wrapped), then
## for each of the four quadrants it takes the SHORTEST signed turn from `s3` and
## keeps the smallest; the return is `live_yaw + signed_turn`, read from the RAW
## (unwrapped) scratch yaw at `+0x78` so an accumulated turn count survives. The
## authored operand is never consulted — it is overwritten before the Camera task
## reads it.
##
## ⚠️ GAP, deliberately: PSX first builds a 4-bit EXCLUSION mask by projecting each
## focused unit's screen anchor (`unit_screen_anchor_project`) through
## `FUN_8018401c(0xB, …)` and skips any quadrant whose bit is set — the "don't frame
## them behind a wall" test. Without it every quadrant is allowed, so the nearest is
## always the live one and this returns `live` unchanged. That is the correct
## degenerate case (the ROM returns the same thing whenever the current quadrant is
## unblocked); what we cannot yet do is MOVE off a blocked quadrant.
func _focus_map_rotation(live_map_rot: int) -> int:
	var wrapped: int = ((live_map_rot % 0x1000) + 0x1000) % 0x1000
	var best_mag: int = 0x8000
	var best_turn: int = 0
	for quadrant in FOCUS_MAP_ROTATIONS:
		var direct: int = quadrant - wrapped
		var other: int = (direct - 0x1000) if direct > 0 else (direct + 0x1000)
		var mag: int = mini(absi(direct), absi(other))
		if mag >= best_mag:
			continue
		best_mag = mag
		# The sign follows whichever route was shorter (0x80147420..48): the direct
		# diff carries `direct`'s sign, the wrapped one the opposite.
		var direct_shorter := absi(direct) < absi(other)
		if direct > 0:
			best_turn = mag if direct_shorter else -mag
		else:
			best_turn = -mag if direct_shorter else mag
	return live_map_rot + best_turn


## {73} Camera Move (relative) — stash the 7 signed deltas so the FOLLOWING {19}
## Camera is pre-patched to `live_pose + delta` (PSX FUN_801474a4 patches that
## Camera's operands in place; we mirror the effect at Camera-execution time). No
## immediate camera move — matches PSX, where {73} only rewrites the future Camera.
func _op_camera_move_relative(inst: Dictionary) -> void:
	_pending_camera_delta = ScenarioDecode.camera_move_relative(EventInstructionSet.args(inst))
	print("[ScenarioVM] Camera Move Relative deltas=%s (pending; next Camera → live+delta)" %
		str(_pending_camera_delta))


## {63} Camera Speed Curve — arm the per-op ease for the FOLLOWING {19} Camera
## (PSX writes the byte to the persistent global 0x80166054; we stash it and latch
## it onto the next lerp). Read positionally so the catalog operand name is not
## relied upon. No immediate move — matches PSX.
func _op_camera_speed_curve(inst: Dictionary) -> void:
	_pending_speed_curve = EventInstructionSet.args(inst).nth(0) & 0xFF
	var sc := ScenarioDecode.camera_speed_curve(_pending_speed_curve)
	print("[ScenarioVM] Camera Speed Curve 0x%02X (intensity=%d A=%d B=%d; pending next Camera)" %
		[_pending_speed_curve, sc.intensity, sc.accel_shape, sc.field_gate])


## The exact {63} ease curve, measured live per-vblank and bit-exact to hardware
## (±1/1024) for 0xAA — a linear blend between pure-linear motion and symmetric
## quadratic ease-in-out, weighted by the intensity nibble (NOT a cosine). `byte`
## is the {63} value; `done` = frame/Time in [0,1]. `A = byte & 0x3` selects the
## shape (0 = linear, ≥1 = eased); the intensity nibble `I` is the ease weight.
## Matches the task-body math at 0x80146454/0x801464b0. See §4.7/§5.2.
func _curve63(done: float, byte: int) -> float:
	var A := byte & 0x3
	if A == 0:
		return done  # linear — no curve
	var I := (byte & 0xF0) >> 4
	var eq := (2.0 * done * done) if done < 0.5 else (1.0 - 2.0 * (1.0 - done) * (1.0 - done))
	return (float(16 - I) / 16.0) * done + (float(I) / 16.0) * eq


## One {73} field: `live + delta`, or the live value untouched when the delta is
## the `CAMERA_DELTA_KEEP` (0x2710) sentinel. Mirrors the task-body branch at
## `0x80147514` (delta == 0x2710 → target = live).
func _apply_delta(live: int, delta: int) -> int:
	return live if delta == CAMERA_DELTA_KEEP else live + delta


## Drop any stashed {1F}/{38} Focus and {73} camera delta (called from
## ScenarioVM.start so a replay re-derives them from PC 0).
func clear_pending_focus() -> void:
	_pending_focus = null
	_pending_focus_time = -1
	_pending_camera_delta = []


func _op_camera(inst: Dictionary) -> void:
	if _vm.player_camera == null:
		push_warning("[ScenarioVM] Camera opcode but no player_camera ref")
		return
	if camera_disabled:
		return
	var a := EventInstructionSet.args(inst)
	# Camera's spatial operands are 16-bit signed; keep the explicit s16 here
	# (byte-identical to the pre-seam director) rather than delegating width to
	# a.signed(), which would depend on the catalog width being plumbed through.
	var x := PsxNum.s16(a.raw("X"))
	var z := PsxNum.s16(a.raw("Z"))
	var y := PsxNum.s16(a.raw("Y"))
	var angle := PsxNum.s16(a.raw("Angle"))
	var map_rot := PsxNum.s16(a.raw("Map Rotation"))
	var cam_rot := PsxNum.s16(a.raw("Camera Rotation"))
	var zoom := a.raw("Zoom")
	var time_ticks := a.raw("Time", 1)

	# {73} Camera Move (relative) consumption: a preceding {73} pre-patches THIS
	# Camera's first 7 operands to `live_pose + delta` (PSX FUN_801474a4). The live
	# pose in opcode units is `_last_camera_params` — the scenario camera doesn't
	# move between ops, so it equals the live scratch PSX reads (byte-exact vs the
	# PC 218 seed, §4.6). A delta of `CAMERA_DELTA_KEEP` (0x2710) leaves that field
	# unchanged; Time is never patched. This is why the authored `Zoom=0` filler
	# becomes `live(4096)+0` = 4096 — the structural fix for the "teleport to a
	# nonsense wide shot" (no zoom clamp needed, §4.4/§5.1). With no prior Camera
	# this run (no live pose to key off) the authored operands stand, mirroring the
	# Focus absent-unit abort — scenario 6 always seeds first, so this is defensive.
	if not _pending_camera_delta.is_empty():
		if _has_last_camera:
			var b := _last_camera_params
			var d := _pending_camera_delta
			x = _apply_delta(int(b.get("x", 0)), int(d[0]))
			z = _apply_delta(int(b.get("z", 0)), int(d[1]))
			y = _apply_delta(int(b.get("y", 0)), int(d[2]))
			angle = _apply_delta(int(b.get("angle", 0)), int(d[3]))
			map_rot = _apply_delta(int(b.get("map_rot", 0)), int(d[4]))
			cam_rot = _apply_delta(int(b.get("cam_rot", 0)), int(d[5]))
			zoom = _apply_delta(int(b.get("zoom", int(CameraCalibration.ZOOM_UNITY))), int(d[6]))
			print("[ScenarioVM] Camera pre-patched by {73}: live+delta → psx=(%d,%d,%d) ang=(%d,%d,%d) zoom=%d" %
				[x, z, y, angle, map_rot, cam_rot, zoom])
		else:
			print("[ScenarioVM] {73} Camera Move but no prior Camera — authored pose stands")
		_pending_camera_delta = []

	# {1F} Focus consumption: a preceding Focus re-aims THIS Camera onto the target
	# unit(s). Overwrite the authored opcode position with the units' Godot-world
	# midpoint, reverse-converted to opcode units (the inverse of
	# `_compute_camera_godot_pose`: X=lateral·112, Z(vertical)=−up·112,
	# Y(depth)=(map_size_z−depth)·112 for the ADR-0052 flip). Authored angle/zoom are
	# kept; `Time` uses the pending Focus Speed if any.
	# Units absent → skip the override (authored pose stands, mirroring PSX abort).
	#
	# 🔴 A `Unknown==0` Focus ALSO overwrites the authored Map Rotation (slot 4) with
	# `FUN_80147318`'s quadrant pick — see [method _focus_map_rotation]. That is 464 of
	# the 475 Focus ops in the corpus, so on nearly every focused shot the authored Map
	# Rotation is dead bytes. Keeping it was measured wrong at Gariland's victory beat:
	# the ROM holds yaw 0x0A00 across scenario 12's Camera (camera scratch +0x78, the
	# GTE mirror and every unit's render-flip bit all agree) while the authored operand
	# says 0x0E00, so the port whipped the camera 180° off the battle's own rotation and
	# put three of five survivors behind the houses. The rotation is picked off the LIVE
	# pose, so it needs a prior Camera this run; with none, the authored value stands
	# (same fallback as {73}).
	if _pending_focus != null:
		if _pending_focus.auto_map_rotation and _has_last_camera:
			var live_rot := int(_last_camera_params.get("map_rot", map_rot))
			var picked := _focus_map_rotation(live_rot)
			if picked != map_rot:
				print("[ScenarioVM] Focus auto map rotation: authored %d → %d (live %d)" %
					[map_rot, picked, live_rot])
			map_rot = picked
		var mid = _focus_midpoint_godot(_pending_focus)
		if mid != null:
			var div: float = ScenarioVM.SCENARIO_POSITION_DIVISOR
			x = int(round(mid.x * div))
			z = int(round(-mid.y * div))
			if _vm.map_size_z > 0:
				# Godot midpoint depth → opcode Y: the same continuous depth-flip
				# chokepoint (ADR-0057); it is its own inverse (size−(size−z)=z).
				y = int(round(PsxNum.flip_depth_continuous(mid.z, _vm.map_size_z) * div))
			else:
				y = int(round(mid.z * div))
			last_focus_resolved = true
			last_focus_target_godot = mid
			print("[ScenarioVM] Camera re-aimed by Focus onto godot=%s → opcode(x=%d,z=%d,y=%d)" %
				[str(mid), x, z, y])
		else:
			last_focus_resolved = false
			print("[ScenarioVM] Focus target unit(s) not present — Camera uses authored pose")
		if _pending_focus_time >= 0:
			time_ticks = _pending_focus_time
		_pending_focus = null
		_pending_focus_time = -1

	if not _camera_taken_over:
		_vm.player_camera.request_takeover(self)
		_camera_taken_over = true

	_last_camera_params = {"x": x, "y": y, "z": z,
		"angle": angle, "map_rot": map_rot, "cam_rot": cam_rot, "zoom": zoom,
		"time": time_ticks}
	_has_last_camera = true

	# Inside a Camera Fusion bracket: queue, don't apply. The VM races past.
	# The queue plays back as a chain in `_advance_camera_lerp` — once the
	# current waypoint's lerp completes, the next one starts. The VM never
	# blocks on Camera ops in fusion mode, so subsequent opcodes (Wait,
	# Display Message, etc.) fire in parallel with the lerp chain.
	if _in_camera_fusion:
		# The fusion spline has its own velocity math — {63} doesn't shape it (a
		# documented gap; scenario 6's orbit is non-fusion). Drop any armed curve so
		# it can't leak onto a later non-fusion Camera.
		_pending_speed_curve = 0
		_camera_queue.append(_last_camera_params.duplicate())
		print("[ScenarioVM] Camera (queued in fusion) psx=(%d,%d,%d) t=%d (queue depth=%d)" %
			[x, y, z, time_ticks, _camera_queue.size()])
		return

	# Non-fusion Camera firing while the FFT-faithful spline owns the camera:
	# skip the lerp. The chapel cleanup at PC=48 (`Camera psx=(840,504,-220)
	# t=4`) fires ~7s into the 9s 6-segment fusion chain — the scenario
	# author counted on the chain finishing first (PC=48 is a no-op landing
	# on the same pose seg 6 ends at). Running a 4-tick lerp in parallel
	# with the still-active spline produces a ~93 opcode/tick race-to-target
	# (20× the spline's natural peak velocity) — the "skip then catch
	# itself" jerk reproduced by `ScenarioChapelJerkProbeTest`. PSX hides
	# the override because its per-vsync ticker reads the chain fiber's
	# output last, so the chain wins mid-bracket; we mirror that by
	# no-op'ing the override here.
	if _chain_spline != null:
		_pending_speed_curve = 0
		print("[ScenarioVM] Camera (non-fusion) skipped — chain spline still owns the camera (final target reached when spline drains)")
		return

	# Legacy queue-cancel path: only meaningful when the strict-linear chain
	# is in use (spline OFF in the F3 panel for A/B comparison). With the
	# linear path, items still sit in `_camera_queue`; same author-intent
	# logic applies — cancel the stale queue so the cleanup pose lands without
	# the queue revival jerking the camera back through the swoop tail.
	if not _camera_queue.is_empty():
		print("[ScenarioVM] Camera (non-fusion) overrides in-flight linear chain; dropping %d queued items" %
			_camera_queue.size())
		_camera_queue.clear()

	# {63} Camera Speed Curve consumption: latch the armed curve onto this lerp so
	# `_curve` shapes the swoop with the §4.7 closed form (0 = global ease mode).
	_active_curve_byte = _pending_speed_curve
	_pending_speed_curve = 0
	_apply_camera_pose(x, y, z, angle, map_rot, cam_rot, zoom, time_ticks)


## The exact GTE view-rotation matrix R that FUN_800ee95c builds for the given
## opcode angles, R = Rx(pitch)·Ry(yaw)·Rz(roll). Captured live and fit to the
## 4096-quantization floor — see `camera_framing_pivot_decode.md` F4. Operates
## on PSX world axes packed as (x=lateral, y=vertical-down, z=depth); the Basis
## is used as a raw 3×3, NOT as a Godot Y-up orientation. Angle units 4096=360°,
## positive signs, standard right-handed elementary rotations (which
## `Basis(axis, angle)` produces).
func _psx_view_rotation(pitch_u: float, yaw_u: float, roll_u: float) -> Basis:
	# Magnitude (raw angle → rad) routes through the single PsxMagnitude seam (ADR-0091);
	# CameraData stores the angle raw for RE byte-fidelity, so the seam is here, the
	# GDScript consume-boundary (ADR-0091 §3), not the parser.
	var p := PsxMagnitude.angle_to_rad(pitch_u)
	var y := PsxMagnitude.angle_to_rad(yaw_u)
	var r := PsxMagnitude.angle_to_rad(roll_u)
	return Basis(Vector3(1, 0, 0), p) * Basis(Vector3(0, 1, 0), y) * Basis(Vector3(0, 0, 1), r)


## Terrain-aware vertical aim for the framed shot (living doc F8/F9). Returns the
## `floor_y` of the map tile the ortho camera body hovers over — the world-Y the
## frame should centre on so the subject's feet land correctly instead of ~29px
## low (the raw `−opcode_z/112` aim sits ~1 tile below the chapel floor).
##
## Chirality (ADR-0052, vertical-handoff decision #1): `godot_pos` is already the
## camera body's GODOT-WORLD position, and `map_composer.get_tile` is indexed in
## the SAME Godot-world grid — `cinematic_place` places units at
## `get_tile(flipped_row)` and Godot world `grid+0.5`, so a tile's get_tile index
## equals its Godot-world (x,z). Therefore the floor directly beneath the body is
## `get_tile(floor(godot_pos.x), floor(godot_pos.z))` with NO extra depth flip —
## the body's z is consumed raw but it is consumed raw INTO
## Godot world, which is the frame get_tile uses. (Whether the raw body even sits
## over the PSX-intended tile is the separate, out-of-scope LATERAL chirality
## bug; the `delta_y` diagnostic in `_describe_focal_tile_for_log` logs the
## flipped alternative so the no-flip choice can be re-checked at any keyframe.)
##
## Falls back to `godot_pos.y` UNCHANGED when there is no map (non-chapel scenes,
## the VM-only test path with no `map_composer`) or the tile is off-grid, so those
## paths are byte-for-byte untouched.
func _framed_floor_y(godot_pos: Vector3) -> float:
	var lattice: Lattice = _vm._lattice()
	if lattice == null:
		return godot_pos.y
	var gx := int(floor(godot_pos.x))
	var gz := int(floor(godot_pos.z))
	# A world position floors to a COLUMN, and the floor under the camera is that
	# column's ground (ADR-0219). Camera framing has never known about levels and this
	# keeps it answering exactly what it answered before.
	var cell := lattice.ground_at(gx, gz)
	if cell == null:
		return godot_pos.y
	return lattice.world_position_at(cell.grid).y


## Convert an opcode Camera pose (PSX units + angles + zoom) into the Godot
## body position, focus rotation, and ortho size, applying the current
## calibration knobs. Single source of truth for the three apply paths
## (`_apply_camera_pose`, `_apply_camera_pose_no_block`,
## `_apply_chain_spline_pose`) so the H1 back-rotation stays consistent.
##
## `x`/`y`/`z` are opcode position units (the spline path passes floats; the
## opcode paths pass ints, both auto-convert). Returns `{pos, rot, ortho}`.
func _compute_camera_godot_pose(x: float, y: float, z: float,
		angle: float, map_rot: float, cam_rot: float, zoom: float,
		aim_floor: bool = true) -> Dictionary:
	var rot_off := Vector3(
		deg_to_rad(camera_rotation_offset_deg.x),
		deg_to_rad(camera_rotation_offset_deg.y),
		deg_to_rad(camera_rotation_offset_deg.z))
	# Position is consumed RAW for BOTH paths (living doc F5/F6): the GTE sets
	# translation T = −R·work_position (FUN_800ee95c calls ApplyMatrix on
	# −work_position with R already loaded), so the PSX camera sits AT
	# work_position in world space — the raw opcode position is already correct.
	# X=lateral, Y=depth, Z=vertical(Y-down) → Godot (x, −z=up, y=depth)/112.
	var godot_pos := Vector3(
		 x / ScenarioVM.SCENARIO_POSITION_DIVISOR,
		-z / ScenarioVM.SCENARIO_POSITION_DIVISOR,
		 y / ScenarioVM.SCENARIO_POSITION_DIVISOR)
	# LATERAL chirality fix (living doc F19): mirror the body's DEPTH the same way
	# ADR-0052 flips every unit, so the ortho camera films the depth-flipped world
	# from the matching frame. Consuming the raw body z (opcode_Y/112) left it in an
	# UN-flipped frame → a constant ~+21px lateral offset (verified to the pixel,F19).
	# The camera body is a transitional Placement (ADR-0057): route its flip
	# through the ONE scenario depth-flip chokepoint. It is a continuous depth
	# (opcode_Y/112, not an integer tile row), so it takes the continuous sibling
	# `PsxNum.flip_depth_continuous` (size−z), not `flip_depth_row` (size−1−z) —
	# the +0.5 tile-centring absorbs the −1 (see PsxNum). Done BEFORE the floor-aim
	# below so the tile lookup uses the corrected (PSX-intended) tile.
	# Skipped when `map_size_z` is unset (VM-only tests / non-map scenes) → raw z.
	if camera_flip_body_depth and _vm.map_size_z > 0:
		godot_pos.z = PsxNum.flip_depth_continuous(
			y / ScenarioVM.SCENARIO_POSITION_DIVISOR, _vm.map_size_z)
	# VERTICAL fix (F8/F9): re-aim the ortho centre at the framed tile's floor.
	# Done on the body's final Godot-world (x,z); replaces Y outright.
	#
	# `aim_floor` gates this PER CALLER (living doc F12). STATIC + DYNAMIC proof:
	# the PSX scenario/event camera Y is a pure interpolated opcode value — the
	# event Camera writer (FUN_801474a4) and the per-vsync ticker
	# (camera_per_vsync_ticker 0x801439c0) read NO terrain/tile height; the swoop
	# work_position.y descends smoothly opcode_Z −572→−220 (probe
	# `probe_camera_swoop_terrain.py`). The camera is married to a tile ONLY in the
	# effect-camera tile-source modes (FUN_801aab90 Y=−height·12 @ 0x801ab2dc),
	# which the scenario never uses. So the per-tick floor pin is WRONG during the
	# swoop: `_apply_chain_spline_pose` passes `aim_floor=false` (raw descent),
	# while the snap/lerp/settle paths floor their (settled) targets. The settled
	# nudge is re-applied once when the chain drains (`_advance_frame`).
	if camera_aim_floor_y and aim_floor:
		godot_pos.y = _framed_floor_y(godot_pos)
	var godot_rot: Vector3
	if camera_backrotate_pivot:
		# ORIENTATION fix (F6): use the EXACT captured GTE rotation instead of the
		# empirical Euler, so the view direction tracks yaw faithfully and the
		# door stops drifting laterally. R = Rx(pitch)·Ry(yaw)·Rz(roll). The Godot
		# camera basis (view→world, reflected-map frame per ADR-0052) is
		# B = D·R⁻¹·D with D = diag(1,−1,−1) — a PURE rotation (det +1).
		var R := _psx_view_rotation(angle, map_rot, cam_rot)
		var D := Basis.from_scale(Vector3(1.0, -1.0, -1.0))
		var B: Basis = D * R.inverse() * D
		if camera_backrotate_invert:
			B = B.inverse()  # A/B safety for a residual handedness flip
		godot_rot = B.get_euler() + rot_off
	else:
		# Empirical orientation (the shipped baseline — "roughly right" start).
		godot_rot = PsxChirality.psx_angles_to_godot_rotation(
			angle, map_rot, cam_rot) + rot_off
	# Zoom: opcode value matches effect-camera convention (4096 = 1.0x base).
	# `camera_ortho_at_1x_zoom` is the Display-space ortho size at 1.0x; the zoom
	# unity (raw 4096 = 1.0x) is the CameraCalibration base (ADR-0091), not a bare literal.
	var ortho: float = camera_ortho_at_1x_zoom * CameraCalibration.ZOOM_UNITY / max(1.0, zoom)
	# VERTICAL DATUM fix (F20): FFT frames the optical centre at native-Y 160, not the
	# midpoint 120 (work_position projects to (128,160) per the GTE TR decomposition).
	# Replicate that as a SCREEN-SPACE vertical shift — applied here, AFTER `godot_rot`,
	# along the camera's LOCAL-UP axis, so it is yaw/pitch-independent exactly like the
	# GTE's post-rotation TR. Moving the body up view-space drops the subject on screen.
	# World shift = (VERTICAL_DATUM_PX / native-240) · ortho, both from `DisplayPort`
	# (KEEP_HEIGHT: ortho size IS
	# the vertical world extent) — px-constant across the swoop's zoom. Gated on
	# `map_size_z > 0` so VM-only / non-map paths stay byte-for-byte unchanged.
	# MUTUALLY EXCLUSIVE with the deprecated floor-aim band-aid (they are two solutions
	# to the same vertical gap — F8's terrain-pin ≈158 vs this authentic datum ≈160):
	# when floor-aim actively replaces pos.y, skip the datum so they never stack.
	var floor_aim_active := camera_aim_floor_y and aim_floor and _vm.map_composer != null
	if camera_vertical_datum and _vm.map_size_z > 0 and not floor_aim_active:
		var up: Vector3 = Basis.from_euler(godot_rot).y
		godot_pos += up * (DisplayPort.VERTICAL_DATUM_PX
			/ DisplayPort.NATIVE_VIEWPORT_HEIGHT) * ortho
	return {"pos": godot_pos, "rot": godot_rot, "ortho": ortho}


## Apply a scenario Camera opcode pose using the current calibration knobs.
## Split out so the calibration debug panel can re-apply the last-seen opcode
## with new knob values, no restart required.
##
## When `time_ticks > 1` the pose lerps from the current pose to the target
## over that many 60 Hz ticks (cosine ease) and the VM blocks for the same
## duration so the next opcode doesn't pre-empt the swoop. `time_ticks <= 1`
## snaps instantly (used by the initial pose-setting opcodes).
func _apply_camera_pose(x: int, y: int, z: int,
		angle: int, map_rot: int, cam_rot: int, zoom: int,
		time_ticks: int = 1) -> void:
	if _vm.play_through_skip_unknown and time_ticks > _vm.play_through_max_ticks:
		time_ticks = _vm.play_through_max_ticks

	var _pose := _compute_camera_godot_pose(
		float(x), float(y), float(z),
		float(angle), float(map_rot), float(cam_rot), float(zoom))
	var godot_pos: Vector3 = _pose["pos"]
	var godot_rot: Vector3 = _pose["rot"]
	var ortho: float = _pose["ortho"]

	if time_ticks <= 1:
		_vm.player_camera.apply_takeover(godot_pos, godot_rot, ortho)
		_cam_lerp_active = false
	else:
		# Capture the current pose as the lerp start — PlayerCamera in takeover
		# mode keeps body position + focus rotation + camera.size live, so we
		# just read them back.
		_cam_start_pos = _vm.player_camera.global_position
		_cam_start_rot = _vm.player_camera.focus_point.global_rotation
		_cam_start_ortho = _vm.player_camera.camera.size
		_cam_target_pos = godot_pos
		_cam_target_rot = godot_rot
		_cam_target_ortho = ortho
		_cam_lerp_duration_s = float(time_ticks) / ScenarioVM._TICK_HZ
		_cam_lerp_elapsed_s = 0.0
		_cam_lerp_active = true
		# PSX is non-blocking: opcode 0x19 handler FUN_801474a4 writes the lerp
		# targets and returns without calling FUN_8014ca80, so main races past
		# Camera and reaches the Block Starts at PC 100/114/127 the same vsync.
		# The lerp ticks asynchronously via _advance_camera_lerp in _process,
		# independent of any context's wait_ticks. Explicit Wait opcodes (PC 141
		# Wait 20 in chapel) handle whatever synchronization the script wants.
	print("[ScenarioVM] Camera psx=(%d,%d,%d) ang=(%d,%d,%d) zoom=%d t=%d godot_pos=%s ortho=%.2f%s" %
		[x, y, z, angle, map_rot, cam_rot, zoom, time_ticks, str(godot_pos), ortho,
			_describe_focal_tile_for_log(godot_pos)])


func _advance_camera_lerp() -> void:
	if _cam_lerp_duration_s <= 0.0 or _vm.player_camera == null:
		return
	var done := clampf(_cam_lerp_elapsed_s / _cam_lerp_duration_s, 0.0, 1.0)
	var ct := _curve(done)
	var pos := _cam_start_pos.lerp(_cam_target_pos, ct)
	var rot := Vector3(
		lerp_angle(_cam_start_rot.x, _cam_target_rot.x, ct),
		lerp_angle(_cam_start_rot.y, _cam_target_rot.y, ct),
		lerp_angle(_cam_start_rot.z, _cam_target_rot.z, ct))
	var ortho := lerpf(_cam_start_ortho, _cam_target_ortho, ct)
	_vm.player_camera.apply_takeover(pos, rot, ortho)


## Camera Fusion Start (0x1d). PSX dispatcher's 0x1d handler eats the entire
## bracket atomically (see `_in_camera_fusion` docstring). In Godot we set a
## flag so subsequent Camera ops are queued instead of applied.
func _op_camera_fusion_start(_inst: Dictionary) -> void:
	_in_camera_fusion = true
	_camera_queue.clear()
	# Snapshot the pre-bracket pose for the spline seed. `_last_camera_params`
	# is set by the immediate Camera before fusion opens; we save it here so
	# subsequent queued Cameras don't overwrite what the spline uses for seg 0.
	if _has_last_camera:
		_fusion_seed_camera_params = _last_camera_params.duplicate()
		_fusion_seed_valid = true
	# Don't snap any in-flight lerp — let it continue to its target. The
	# queued chain will pick up from wherever the camera lands.


## Camera Fusion End (0x1e). Closes the queue and kicks off the chain — the
## first queued Camera starts lerping; subsequent items advance automatically
## in `_process` as each lerp completes. The VM does NOT wait — it continues
## past this opcode while the chain plays in the background. This is the key
## parallelism that lets Display Message (PC 42) fire during the camera swoop.
func _op_camera_fusion_end(_inst: Dictionary) -> void:
	_in_camera_fusion = false
	if use_camera_chain_spline and _camera_queue.size() >= 2:
		_start_chain_spline()
	else:
		_start_next_queued_camera()


## Build the spline buffer from the queued Camera ops and seed it with the
## live camera pose as seg 0.  Drains `_camera_queue` (the spline owns the
## chain from here).  Per-tick stepping happens in `_process`.
func _start_chain_spline() -> void:
	if _vm.player_camera == null:
		_start_next_queued_camera()
		return
	if not _camera_taken_over:
		_vm.player_camera.request_takeover(self)
		_camera_taken_over = true
	# Seg 0 target = the live PSX-units pose. The chain queue holds the
	# subsequent waypoints (each {x,y,z,angle,map_rot,cam_rot,zoom,time}).
	# We don't have a clean way to read back PSX-units from the live
	# Godot transform (the conversion is lossy through SCENARIO_POSITION_DIVISOR
	# + the rotation matrix), so use the LAST applied Camera params as the
	# seed if available; otherwise fall back to the first queue entry.
	var seed_pose := PackedInt32Array()
	seed_pose.resize(_CameraChainSpline.AXIS_COUNT)
	# Prefer the pre-bracket snapshot (immediate Camera before fusion_start).
	# Fall back to the live _last_camera_params if the snapshot's missing
	# (shouldn't happen in chapel; defensive for non-canonical chunks).
	var seed_src: Dictionary
	if _fusion_seed_valid:
		seed_src = _fusion_seed_camera_params
	elif _has_last_camera:
		seed_src = _last_camera_params
	else:
		seed_src = _camera_queue[0]
	seed_pose[0] = int(seed_src.get("x", 0))
	seed_pose[1] = int(seed_src.get("y", 0))
	seed_pose[2] = int(seed_src.get("z", 0))
	seed_pose[3] = int(seed_src.get("angle", 0))
	seed_pose[4] = int(seed_src.get("map_rot", 0))
	seed_pose[5] = int(seed_src.get("cam_rot", 0))
	seed_pose[6] = int(seed_src.get("zoom", int(CameraCalibration.ZOOM_UNITY)))
	# Save the final waypoint (last queued Camera op) so the drain can ease the
	# camera onto the framed floor for the settled shot (F12 — the swoop runs
	# floor-aim OFF). The last queue entry is the spline's terminal target.
	_chain_final_params = (_camera_queue.back() as Dictionary).duplicate()
	_chain_final_valid = true
	_chain_spline = _CameraChainSpline.new()
	_chain_spline.init_from_queue(_camera_queue, seed_pose)
	_camera_queue.clear()
	_chain_spline_tick_acc = 0.0
	_cam_lerp_active = false  # spline owns the camera from here
	print("[ScenarioVM] Camera-chain spline armed: 7 axes, %d waypoints (seed=%s)" %
		[_chain_spline.axes[0].total_segs - 1, str(seed_pose)])


## Convert spline-scratch output (7 ints: positions in opcode*1024, rotations
## in opcode units) to a Godot world pose and push it to the camera.
func _apply_chain_spline_pose(scratch: PackedInt32Array) -> void:
	if _vm.player_camera == null:
		return
	# Position: scratch is opcode*1024, opcode-units feed into the existing
	# Godot conversion (the same one `_apply_camera_pose` does, just with
	# a divide-by-1024 to get back to opcode units).
	var x := float(scratch[0]) / 1024.0
	var y := float(scratch[1]) / 1024.0
	var z := float(scratch[2]) / 1024.0
	var angle := float(scratch[3])
	var map_rot := float(scratch[4])
	var cam_rot := float(scratch[5])
	var zoom := maxi(1, int(scratch[6]))

	# Floor-aim OFF for the in-motion swoop: the PSX camera Y here is the raw
	# interpolated opcode descent, NOT a per-tile terrain pin (living doc F12 —
	# disassembly + `probe_camera_swoop_terrain.py`). Pinning Y to terrain every
	# tick is what produced the ±5–8 tile vertical jerks (F11). The floored
	# settled framing is restored once the chain drains (see `_advance_frame`).
	var _pose := _compute_camera_godot_pose(
		x, y, z, angle, map_rot, cam_rot, float(zoom), false)
	_vm.player_camera.apply_takeover(_pose["pos"], _pose["rot"], _pose["ortho"])


## Called once when the fusion chain spline DRAINS. The swoop ran floor-aim OFF
## (raw opcode descent — F12), so the camera now sits at the raw final pose. If
## floor-aim is ON, re-apply the chain's final waypoint through the normal
## (floored) path with a short ease, gently settling the ortho centre onto the
## framed tile's floor for the dialogue shot. No-op when floor-aim is OFF (the
## raw end IS the intended settle) or there is no map (`_framed_floor_y` falls
## back to the raw Y, so the ease would be a no-op anyway). PSX itself does not
## nudge here — this ease compensates for Godot's ortho-vs-PSX-projection vertical
## datum (the still-open lateral/projection bug, F9), not for any PSX motion.
func _settle_camera_onto_floor() -> void:
	if not camera_aim_floor_y or not _chain_final_valid or _vm.player_camera == null:
		return
	if _vm.map_composer == null:
		return  # no terrain → floor-aim is a no-op; nothing to settle onto
	var p := _chain_final_params
	_apply_camera_pose(
		int(p.get("x", 0)), int(p.get("y", 0)), int(p.get("z", 0)),
		int(p.get("angle", 0)), int(p.get("map_rot", 0)), int(p.get("cam_rot", 0)),
		int(p.get("zoom", int(CameraCalibration.ZOOM_UNITY))), _SWOOP_SETTLE_TICKS)


## Pop and apply the next queued Camera. Called by `_op_camera_fusion_end` to
## start the chain, and by `_process` each time the current lerp completes.
## Sets `_cam_lerp_active` via `_apply_camera_pose` but never `_wait_ticks`.
func _start_next_queued_camera() -> void:
	if _camera_queue.is_empty():
		return
	var p: Dictionary = _camera_queue.pop_front()
	# Apply with a sentinel that's >1 so we lerp (not snap). The PSX queue's
	# camera writes happen every other vsync (~30 Hz) — see the
	# `camera_ease_mode` docstring's calibration notes. The `time_ticks`
	# field on each queued op is the lerp duration. We pass it through
	# `_apply_camera_pose_no_block` to avoid setting `_wait_ticks`.
	_apply_camera_pose_no_block(p)


## Apply a queued Camera pose without arming `_wait_ticks`. Mirrors
## `_apply_camera_pose` but skips the VM-block step and uses the per-op
## `time` field directly. Identical math to `_apply_camera_pose`'s lerp branch
## so a queued op produces the same trajectory as a sequential one.
func _apply_camera_pose_no_block(p: Dictionary) -> void:
	if _vm.player_camera == null:
		return
	if not _camera_taken_over:
		_vm.player_camera.request_takeover(self)
		_camera_taken_over = true

	var x: int = p.x; var y: int = p.y; var z: int = p.z
	var angle: int = p.angle; var map_rot: int = p.map_rot
	var cam_rot: int = p.cam_rot; var zoom: int = p.zoom
	var time_ticks: int = p.time
	if _vm.play_through_skip_unknown and time_ticks > _vm.play_through_max_ticks:
		time_ticks = _vm.play_through_max_ticks

	var _pose := _compute_camera_godot_pose(
		float(x), float(y), float(z),
		float(angle), float(map_rot), float(cam_rot), float(zoom))
	var godot_pos: Vector3 = _pose["pos"]
	var godot_rot: Vector3 = _pose["rot"]
	var ortho: float = _pose["ortho"]

	if time_ticks <= 1:
		_vm.player_camera.apply_takeover(godot_pos, godot_rot, ortho)
		_cam_lerp_active = false
		# Snap-complete — immediately try the next queued op.
		call_deferred("_start_next_queued_camera")
		return

	# Chain handoff: start from the prev segment's TARGET (kept in
	# `_cam_target_*` until we overwrite them below). First-in-chain (called
	# from `_op_camera_fusion_end`, _chain_handoff=false) still seeds from
	# live camera so the chain picks up wherever the camera actually is when
	# fusion opens. See `_chain_handoff` docstring for the full rationale.
	if _chain_handoff:
		_cam_start_pos = _cam_target_pos
		_cam_start_rot = _cam_target_rot
		_cam_start_ortho = _cam_target_ortho
	else:
		_cam_start_pos = _vm.player_camera.global_position
		_cam_start_rot = _vm.player_camera.focus_point.global_rotation
		_cam_start_ortho = _vm.player_camera.camera.size
	_cam_target_pos = godot_pos
	_cam_target_rot = godot_rot
	_cam_target_ortho = ortho
	_cam_lerp_duration_s = float(time_ticks) / ScenarioVM._TICK_HZ
	_cam_lerp_elapsed_s = 0.0
	_cam_lerp_active = true
	print("[ScenarioVM] Camera (queued-chain start) psx=(%d,%d,%d) t=%d godot_pos=%s ortho=%.2f chain=%s" %
		[x, y, z, time_ticks, str(godot_pos), ortho, str(_chain_handoff)])


## Map normalised progress `done` in [0,1] through `camera_ease_mode`.
## LINEAR is the verified PSX curve (see `camera_ease_mode` docstring).
## COSINE_A / COSINE_B are retained for the F3 A/B toggle.
func _curve(done: float) -> float:
	# A {63} Camera Speed Curve armed on this lerp overrides the global ease mode
	# with the bit-exact §4.7 closed form. 0 = no curve → the global mode below.
	if _active_curve_byte != 0:
		return _curve63(done, _active_curve_byte)
	match camera_ease_mode:
		EaseMode.LINEAR:
			return done
		EaseMode.COSINE_A:
			return 0.5 - 0.5 * cos(PI * done)
		EaseMode.COSINE_B:
			# Asymmetric ease: faster ramp-in than ramp-out, mirroring the
			# effect-camera COSINE_B variant. Kept here for A/B comparison
			# only; PSX scenarios never select this curve.
			return 1.0 - cos(0.5 * PI * done)
		_:
			return done


## Per-Camera-opcode diagnostic appended to the existing log line so the
## "+2 Y offset" investigation has a paper trail. Reports the tile at the
## focal point's (grid_x, grid_z) — that's the strongest candidate for the
## "the +2 is the tile-height of the framed tile" hypothesis. Empty string
## when no map_composer is wired (silent so the log stays parseable).
func _describe_focal_tile_for_log(focal: Vector3) -> String:
	var lattice: Lattice = _vm._lattice()
	if lattice == null:
		return ""
	var gx := int(floor(focal.x))
	var gz := int(floor(focal.z))
	var cell := lattice.ground_at(gx, gz)
	if cell == null:
		return "  focal_tile=(%d,%d):none" % [gx, gz]
	# focal.y minus the cell's world floor is the height the camera focal sits
	# above the tile under it — the candidate "what +2 means" number.
	var floor_y: float = lattice.world_position_at(cell.grid).y
	# Vertical-handoff decision #1 paper trail: log the FLIPPED-row alternative
	# floor_y too, so the no-flip choice in `_framed_floor_y` can be re-checked at
	# any swoop keyframe (they coincide only at the midline / settled frame).
	var flip := "  flip_tile=(off-grid)"
	if _vm.map_size_z > 0:
		# Integer tile-row flip: the one chokepoint (ADR-0057 transitional Placement).
		var fz := PsxNum.flip_depth_row(gz, _vm.map_size_z)
		var flip_cell := lattice.ground_at(gx, fz)
		if flip_cell != null:
			flip = "  flip_tile=(%d,%d) floor_y=%.3f" % [
				gx, fz, lattice.world_position_at(flip_cell.grid).y]
	return "  focal_tile=(%d,%d) h=%d floor_y=%.3f delta_y=%.3f%s" % [
		gx, gz, cell.height, floor_y, focal.y - floor_y, flip]


## Public version of the focal-tile log line for the screenshot button.
## Always pre-fixed with the camera's body position so the line is self-
## describing in the log even without the original opcode print.
func describe_last_camera_for_log() -> String:
	if not _has_last_camera or _vm.player_camera == null:
		return "(no Camera opcode applied yet)"
	var p := _last_camera_params
	var focal: Vector3 = _vm.player_camera.global_position
	return "psx=(%d,%d,%d) zoom=%d godot_pos=%s%s" % [
		int(p.x), int(p.y), int(p.z), int(p.zoom),
		str(focal), _describe_focal_tile_for_log(focal)]


## Re-apply the most recent Camera opcode with the current calibration knobs.
## Returns false if no Camera opcode has fired yet this run.
func reapply_last_camera() -> bool:
	if not _has_last_camera or _vm.player_camera == null:
		return false
	if not _camera_taken_over:
		_vm.player_camera.request_takeover(self)
		_camera_taken_over = true
	var p := _last_camera_params
	# Re-apply snaps (time=1) — the debug-panel use-case is to A/B knobs on a
	# specific pose, not to replay the original interpolation.
	_apply_camera_pose(p.x, p.y, p.z, p.angle, p.map_rot, p.cam_rot, p.zoom, 1)
	return true
