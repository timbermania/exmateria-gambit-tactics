class_name ScenarioApply
extends RefCounted
## Pure apply layer for the event-script interpreter: `apply_X(intent, world)`
## performs an opcode's world mutation, but only through [ScenarioWorld] verbs —
## no node lookups, no VM state, no scene (ADR-0058).
##
## This is the third symmetric module in the decode/apply split. [ScenarioDecode]
## already holds the reverse-engineered "what an opcode means" (operands → typed
## intent); this holds "how it changes the rendered world", lifted out of the inline
## `_op_*` handler bodies on the god-Node [ScenarioVM]. A behavioral handler then
## collapses to `ScenarioApply.warp(ScenarioDecode.warp_unit(
## EventInstructionSet.args(inst)), _world)` — decode, then apply the
## intent to the world.
##
## These are free (`static`) functions: production passes a real [ScenarioWorld]
## wrapping the live scene, tests pass a [FakeScenarioWorld] that records the verb
## calls — the SAME code path, so an apply is testable without a scene boot and the
## apply bodies leave the VM (the god-Node shrinkage this refactor buys).
##
## Out of the seam: control flow / scheduler state (wait-barriers, block
## coroutines, event-variable math) stays on the VM — for a handler that both
## mutates and arms a barrier, apply does the world mutation and the VM arms the
## wait separately.

# ---------------------------------------------------------------------------
# {24} Warp Unit — position + spawn facing. The reference opcode for the seam:
# its decode is already pure/typed (ScenarioDecode.WarpIntent) and its apply
# exercises three distinct verb kinds (place, home-reset, facing).
# ---------------------------------------------------------------------------

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const PsxNum = ExMateriaPlatform.PsxNum

## Apply a decoded Warp Unit: place the unit on its tile, reset its move-home, and
## set its spawn facing. Skips (no mutation) when the unit was never spawned or the
## map can't resolve the tile — mirroring the inline handler's two guard-returns.
## Warp positions the unit; the later {45} Add Unit / {44} Draw Unit reveals it, so
## this does NOT touch visibility. Facing ground truth (female knight settles NORTH
## for Facing field 3): research/working_documents/scenario_1_captures/
## female_knight_facing_GROUND_TRUTH.md.
static func warp(intent: ScenarioDecode.WarpIntent, world: ScenarioWorld) -> void:
	if not world.has_unit(intent.uid):
		push_warning("[ScenarioApply] Warp Unit 0x%02X — no spawned unit; skipping (xy=(%d,%d))" %
			[intent.uid, intent.psx_x, intent.psx_y])
		return
	if not world.place_unit_on_tile(intent.uid, intent.psx_x, intent.psx_y):
		return
	# Warp zeroes the +0x60 offset on hardware: drop any in-flight Sprite-Move slide so
	# it doesn't keep lerping the unit back to its pre-warp target off the new base, THEN
	# re-base the move-home so the next Sprite-Move resolves against the warped tile.
	world.disarm_motion(intent.uid)
	world.clear_actor_home(intent.uid)
	world.set_unit_facing(intent.uid, intent.facing_12bit)


# ---------------------------------------------------------------------------
# Unit lifecycle — {45} Add Unit / {44} Draw Unit / {46} Erase Unit /
# {3D} Remove Unit. Add/Draw/Erase toggle graphic-commit + visibility; Remove
# tears the unit fully off the field and out of memory.
# ---------------------------------------------------------------------------

## {45} Add Unit — INTRODUCE the unit into the scene (BATTLE.BIN FUN_8008d05c):
## commit its graphic (marks it present in the sprite list / broadcast roster) AND
## set its +0xa render flag from the inverted Draw byte — Draw=0 draws it now, Draw=1
## holds it hidden. This IS the reveal for a unit whose only visibility op is a
## {45} Add (scn6 uid 1/4 at (0,4)/(0,3): a lone Add Draw=0 at pc434, never named by
## a {44} Draw) — such units spawn hidden (not yet present, _frame0_visible) and
## become visible only here, when their Add dispatches. `commit_unit_graphic` itself
## is still the seam point for future SHP/SEQ stat-commit work.
static func add_unit(uid: int, draw: int, world: ScenarioWorld) -> void:
	if not world.has_unit(uid):
		push_warning("[ScenarioApply] Add Unit 0x%02X — no spawned unit; skipping" % uid)
		return
	world.commit_unit_graphic(uid)
	world.set_unit_visible(uid, draw == 0)   # inverted: Draw=0 draw-now, Draw=1 held
	print("[ScenarioApply] Add Unit 0x%02X Draw=%d → %s" %
		[uid, draw, "visible (draw now)" if draw == 0 else "held (hidden)"])


## {44} Draw Unit — the on-screen reveal (sprite → visible).
static func draw_unit(uid: int, world: ScenarioWorld) -> void:
	if not world.has_unit(uid):
		push_warning("[ScenarioApply] Draw Unit 0x%02X — no spawned unit; skipping" % uid)
		return
	world.set_unit_visible(uid, true)
	print("[ScenarioApply] Draw Unit 0x%02X → visible" % uid)


## {46} Erase Unit — hide the sprite (registry intact; NOT a removal).
static func erase_unit(uid: int, world: ScenarioWorld) -> void:
	if not world.has_unit(uid):
		push_warning("[ScenarioApply] Erase Unit 0x%02X — no spawned unit; skipping" % uid)
		return
	world.set_unit_visible(uid, false)
	print("[ScenarioApply] Erase Unit 0x%02X → hidden" % uid)


## {3D} Remove Unit — tear the unit fully off the field AND out of memory (roster
## slot + registry + sprite), instantly (PSX FUN_80086f2c). The raw operand is a
## u16 chunk id resolved to the live registry key (u8 fallback); a miss is a no-op.
## Distinct from {46} Erase (hide-only) and {44} Blue Remove Unit (animated + War
## Trophy). The full teardown is one `world.remove_unit(key)` verb.
static func remove_unit(raw_uid: int, world: ScenarioWorld) -> void:
	var key := world.resolve_unit_key(raw_uid)
	if key < 0:
		print("[ScenarioApply] Remove Unit 0x%02X — no live unit; no-op" % raw_uid)
		return
	world.remove_unit(key)
	print("[ScenarioApply] Remove Unit 0x%02X → freed (roster slot + sprite)" % raw_uid)


## {47} Add Ghost Unit — spawn a sprite-only "ghost" actor (no ENTD roster record).
## The 8-byte body decodes to `xSP, x00, xID, X, Y, xEL, xFD, xDR` (§3.1); this
## computes the event-facing control-id (`xID + 0x64`, the id later ops address it
## by), decodes the facing wheel, inverts the draw flag (`xDR` 0=draw now, 1=held),
## and asks the world to instantiate the actor. Graphics resolve through the SAME
## unit-SPR pipeline as {45} Add Unit keyed by `sprite_set = xSP` (§5) — the only
## PSX difference is the ghost carries no ENTD unit-struct. Placement is the operand
## tile `X/Y` (§4.5a: no cinematic-anchor table; scn6 passes 0,0 = corner/off-frame).
## Re-adding a live ghost is a no-op (the world's idempotency gate, PSX
## `FUN_8007a6e4(slot)==0`). ADD_GHOST_UNIT_OPCODE_47.md §6.
##
## Facing note: `xFD` is decoded through the warp/spawn wheel (PsxNum.warp_facing_to_
## 12bit: 0=E,1=S,2=W,3=N), the SAME convention every other Godot-spawned unit uses.
## The community {47} reference lists a different table (0=S,1=W,2=N,3=E); scn6's
## ghosts all pass `xFD=0` and render off-frame, so the choice is not visually
## observable here — documented as an approximation in §6/§7 until dynamically ground-
## truthed.
static func add_ghost_unit(xsp: int, xid: int, x: int, y: int, xel: int, xfd: int,
		xdr: int, world: ScenarioWorld) -> void:
	var control_id := xid + 0x64
	var facing_12bit := PsxNum.warp_facing_to_12bit(xfd & 0x3)
	var visible := (xdr == 0)  # xDR inverted: 0 = draw now, 1 = held/hidden
	if not world.spawn_ghost_unit(control_id, xsp, x, y, xel, facing_12bit, visible):
		print("[ScenarioApply] Add Ghost Unit xID=%d (ctrl 0x%02X) — already spawned or no host; no-op" %
			[xid, control_id])
		return
	print("[ScenarioApply] Add Ghost Unit xID=%d → ctrl 0x%02X sprite_set=0x%02X tile=(%d,%d) elev=%d facing=0x%03X visible=%s" %
		[xid, control_id, xsp, x, y, xel, facing_12bit, str(visible)])


## {92} Inflict Status. PSX task body FUN_80148E88 branches on Status; the VM
## handler guarantees `status ∈ {0, 1, 2}` here (it fails loud on the 0x80+ range).
## The `_wait` operand (the cooperative task's yield count) has no analogue in our
## synchronous apply. A resolve miss is a no-op, matching remove_unit.
##   Status 0 = revive-if-dead(1 HP) + clean Standing (Critical if HP low) pose +
##             block later event HP-restore + SFX if it was dead. NOT a status bit.
##   Status 1 = Crystal: replace the body with the animated diamond billboard (§12.7).
##   Status 2 = Poison + Critical: add Poison status, force the Critical kneel pose,
##             and apply poison's static green sprite recolor (§11.2 / §12).
static func inflict_status(raw_uid: int, status: int, _wait: int, world: ScenarioWorld) -> void:
	var key := world.resolve_unit_key(raw_uid)
	if key < 0:
		print("[ScenarioApply] Inflict Status 0x%02X — no live unit; no-op" % raw_uid)
		return
	match status:
		0:
			world.revive_and_normalise(key)
			print("[ScenarioApply] Inflict Status 0x%02X (Status=0) → revive-if-dead + Standing" % raw_uid)
		1:
			world.inflict_crystal(key)
			print("[ScenarioApply] Inflict Status 0x%02X (Status=1) → Crystal (animated diamond)" % raw_uid)
		2:
			world.inflict_poison_critical(key)
			print("[ScenarioApply] Inflict Status 0x%02X (Status=2) → Poison + Critical (green tint + kneel)" % raw_uid)


# ---------------------------------------------------------------------------
# Unit motion — {3B} Sprite Move / {6E} Sprite Move Beta. Arm a per-unit
# straight-line [ScenarioMotion] targeting home + operand-offset. The Wait
# barrier ({6F}) stays on the VM (ADR-0055) — this only registers the motion.
# ---------------------------------------------------------------------------

## Arm a Sprite Move: resolve the unit, capture its home, and register a straight-
## line motion from its current position to `home + intent.offset`. Skips a unit that
## was never spawned or can't slide (no spatial transform). `divisor` converts the
## beta travel distance to opcode units; `tick_hz` is the motion clock; `max_dur_s`
## clamps the duration (INF = no clamp) so a play-through doesn't stall on a long
## slide. The endpoint is absolute-from-home, so repeated moves don't accumulate.
static func sprite_move(intent: ScenarioDecode.SpriteMoveIntent, world: ScenarioWorld,
		divisor: float, tick_hz: float, max_dur_s: float, label: String) -> void:
	var key := world.resolve_unit_key(intent.uid)
	if key < 0:
		print("[ScenarioApply] WARN %s 0x%04X — no spawned unit; skipping" % [label, intent.uid])
		return
	if not world.can_slide(key):
		return
	var home: Vector3 = world.capture_unit_home(key)
	var start: Vector3 = world.unit_position(key)
	var target: Vector3 = home + intent.offset
	var dur_s := _motion_duration_s(start, target, intent.time_frames, intent.speed,
		divisor, tick_hz)
	dur_s = minf(dur_s, max_dur_s)
	var m := ScenarioMotion.new()
	m.start = start
	m.target = target
	m.dur_s = maxf(dur_s, 1.0 / tick_hz)
	m.elapsed_s = 0.0
	m.easing = intent.easing
	m.weight = intent.weight
	world.arm_motion(key, m)
	print("[ScenarioApply] %s 0x%02X home=%s → target=%s dur=%.3fs type=%d w=%d" %
		[label, key, str(home), str(target), dur_s, intent.easing, intent.weight])


## Motion duration in seconds: {3B} fixed frame count, or {6E} Beta =
## `4·dist·divisor/speed` frames (dist in world tiles → opcode units via `divisor`).
static func _motion_duration_s(start: Vector3, target: Vector3, time_frames: int,
		speed: int, divisor: float, tick_hz: float) -> float:
	if time_frames > 0:
		return float(time_frames) / tick_hz
	var dist: float = start.distance_to(target) * divisor
	return ScenarioDecode.beta_duration_frames(dist, speed) / tick_hz


## {28} Walk To — grid relocation: walk the unit to tile (tx, tz) at `speed`,
## adopting the movement-walk anim + heading and advancing its home to the seat. The
## pathfinder route (`world.plan_walk`) is TERRAIN-only (units don't block — ROM a0=3
## map build; EventPathfinder header), and it either reaches the literal target tile or
## is REFUSED outright: `FUN_8017813C` has no nearest-reachable-tile fallback, so an
## unreachable target makes the whole opcode a no-op (ADR-0226). Walk To hands the ROM's
## own route BYTES to the ROM's own per-frame walk stepper — [ScenarioPathMotion] over
## `ExMateriaBattlefield.RomWalkStepper` — so a step may span more than one tile: a
## `{28}` walk LEAPS a one-tile gap rather than wading it. Both halves are
## transcriptions scored against live PSX captures: the planner on 18 (ADR-0226), the
## stepper on 43 510/43 510 field-frames over 13 (ADR-0225).
## ⚠️ The cadence is NOT `224/speed`: it is an integer recurrence, low by a frame a
## tile or more at every Speed, and nothing predicts it — the stepper runs the whole
## walk at `configure` time and `dur_s` is the frame count that came out. The {29}
## Wait Walk barrier stays on the VM (ADR-0055). Skips a missing/immovable unit or a
## no-map / no-tile plan.
##
## `level` is the opcode's `Z` operand carried through rather than dropped (ADR-0219
## dec. 7): the third argument of the ROM's own `tile_ptr(x, z, level)`, bounds-checked
## `< 2` at `0x8018400c`, and binary over all 634 unit-placement instructions in the
## exported corpus. A default of 0 keeps the ~30 callers that never had one honest —
## the ground is what they meant — without letting the value be inferred anywhere.
static func walk_to(uid: int, tx: int, tz: int, speed: float, world: ScenarioWorld,
		_divisor: float, tick_hz: float, max_dur_s: float, walk_anim_id: int,
		level: int = 0, flat_cost: bool = false) -> void:
	var key := world.resolve_unit_key(uid)
	if key < 0:
		print("[ScenarioApply] WARN Walk To 0x%04X — no spawned unit; skipping" % uid)
		return
	if not world.can_slide(key):
		return
	var plan := world.plan_walk(key, tx, tz, level, flat_cost)
	if plan.is_empty():
		return  # no map composer or no tile at the endpoint
	var start: Vector3 = plan["start"]
	var target: Vector3 = plan["target"]
	var endpoint: Vector3i = plan["endpoint"]
	# The ROM commits to the literal target or it does not walk at all, so this can no
	# longer differ — the "route ends short" branch it replaced was the shipped BFS's
	# invention. Kept as an assertion rather than deleted: if it ever fires, the planner
	# and its caller disagree about which cell was asked for.
	if endpoint != Vector3i(tx, tz, level):
		push_warning("[ScenarioApply] Walk To 0x%02X planned (%d,%d,L%d) but asked (%d,%d,L%d)" %
			[key, endpoint.x, endpoint.y, endpoint.z, tx, tz, level])
	# Full per-tile route polyline (each tile at its own terrain surface); fall back to
	# the endpoint-only straight line if the plan predates the waypoint field.
	var waypoints: Array = plan.get("waypoints", [start, target])
	# The ROM's route buffer is `[step_count] + step_bytes` (`EventPathfinder._route_bytes`),
	# and the stepper's own zero-length test is `route[0]`. Read here rather than derived
	# from the waypoints: a unit a Sprite Move has offset inside its own tile has a start
	# that differs from the target's tile centre while the ROUTE is still zero steps.
	var route_steps: int = int(plan["route"][0]) if not (plan["route"] as Array).is_empty() else 0
	# The cadence lives inside the stepper and is EMERGENT — `configure_rom` steps the
	# whole walk and `dur_s` is the frame count that came out. `divisor` is unused: Walk
	# To is tile-stepped, not the {6E} slide. `speed` is 8.8 fixed point and may be
	# fractional.
	#
	# 🔴 `configure_rom`, not `configure`. The plan now carries the ROM's own ROUTE
	# BYTES and the ROM's own tiles, so the stepper reads all five bytes per tile
	# instead of one approximated out of a polyline — which is what a leap, a gait and
	# a drape are made of. The polyline is still built, but as the ANSWER to "where
	# does this walk end", not as the motion's input.
	var m := ScenarioPathMotion.new()
	m.configure_rom(plan["terrain"], plan["psx_start"], plan["route"], speed, tick_hz,
		max_dur_s, plan["grid_origin"], plan["world_y_at_start"], plan["psx_rows"],
		waypoints)
	world.arm_motion(key, m)
	# Latch the seat's LEVEL onto the unit (ADR-0219 dec. 6). The route just answered
	# the one question a transform cannot — which of the endpoint column's up-to-two
	# tiles this walk lands on — and if nothing records it the answer is thrown away and
	# the NEXT Walk To re-plans from the column's ground. That is not hypothetical: it is
	# why scenario 29 pc 164 walked Algus 13 tiles up the Igros moat to reach the tile
	# beside him (`ScenarioWorld.seat_unit_cell`). Endpoint, not the requested `(tx, tz,
	# level)` — a terrain-sealed target stops short and the unit is on where it STOPPED.
	world.seat_unit_cell(key, endpoint)
	# Orient to the dominant travel axis + drive the movement-walk SEQ directly (the
	# combat WALKING activity would pick the wrong variant + freeze the frame clock;
	# HANDOFF_walk_to_animation.md). The walk writes the ORIENTATION source of truth
	# (`facing_angle`) straight from its world heading via the forward converter — NOT
	# by routing through the FacingDirection enum, the backward arrow ADR-0057 forbids;
	# the enum follows as a derived view. Without this the VM renderer draws the unit's
	# stale pre-walk facing for the whole walk (the scenario-6 chocobo walked NORTH
	# while facing WEST — CHOCOBO_WALK_OCTANT_28.md). The stepper re-faces per segment
	# on turns via poll_facing_change (VM-driven). The walk advances the tile, so the
	# next Sprite Move must re-capture home from the seat.
	#
	# 🔴 NONE OF THAT ON A ZERO-STEP ROUTE. A `{28}` to the tile the unit is already
	# standing on is planned, not refused — `EventPathfinder`'s `chain.is_empty() and
	# start != dest` returns `reached_target` with a bare `[0]` route buffer — and
	# `RomWalkStepper.step()` then reads `n = route[0] == 0` and returns BEFORE
	# `_arm_walk`. Hardware writes no facing and latches no anim; the unit stands as it
	# was. This block is a Godot-side addition with no degenerate case:
	# `heading_to_12bit(0, 0)` resolves to NORTH unconditionally, and that is scenario
	# 29 pc 388 (`ScenarioZeroLengthWalkTest`) — a second `{28}` to the tile pc 352
	# already walked Delita to spun him 0xC00-0x800 = 90° off Teta and played the walk
	# in place, and he kept the wrong facing through the `{3B}` hug slide.
	#
	# The home clear is gated with it, and for the same reason: `clear_home` exists for
	# a base RE-PLACEMENT, and a walk that advanced no tile re-placed no base. Clearing
	# it would let the next Sprite Move — pc 391/392, immediately after — re-capture
	# home off a unit a PREVIOUS Sprite Move had already offset, turning an
	# absolute-from-home endpoint into a relative slide that accumulates.
	if route_steps > 0:
		var facing_12bit := PsxNum.heading_to_12bit(target.x - start.x, target.z - start.z)
		world.set_walking(key, facing_12bit, walk_anim_id)
		world.clear_actor_home(key)
	print("[ScenarioApply] Walk To 0x%02X %s -> seat (%d,%d,L%d) waypts=%d dur=%.3fs speed=%.3f" %
		[key, str(start), endpoint.x, endpoint.y, endpoint.z, waypoints.size(), m.dur_s, speed])


# ---------------------------------------------------------------------------
# Facing & animation — {11} Unit Anim / {8C} Unit Anim Rotate / {2D} Rotate
# Unit / {53} Face Unit / {2C} Face Unit 2. The animation-playback machine and
# the rotate stepper stay Unit/VM-side (ADR-0055); apply resolves, decodes the
# target angle, and arms them through verbs.
# ---------------------------------------------------------------------------

## {11} Unit Anim — play `anim_id` on the selector's unit(s) (idle/SEQ/EVTCHR range
## dispatch is the play_unit_anim machine's job). `flag` is advisory in Godot. The
## Units/Multi selector broadcasts to a team-set when Multi≠0 (the scenario-1
## `Multi != 0` rows = "anim on all present units"); Multi=0 is one unit. Skips a
## unit whose sprite pipeline isn't ready; an empty set is a no-op.
static func unit_anim(intent: ScenarioDecode.UnitAnimIntent, world: ScenarioWorld) -> void:
	var keys := world.resolve_unit_set(intent.units, intent.multi)
	if keys.is_empty():
		print("[ScenarioApply] WARN Unit Anim Units=0x%02X Multi=0x%02X — no target unit(s); skipping" %
			[intent.units, intent.multi])
		return
	for key in keys:
		if not world.play_unit_anim(key, intent.anim_id):
			continue
		print("[ScenarioApply] Unit Anim 0x%02X anim=0x%X flag=%d" % [key, intent.anim_id, intent.flag])


## {80} March — RELEASE the selector's unit(s) back to their combat-idle "march in place"
## pose. NOT a walk and NOT a blanket flip: it mirrors the ROM handler FUN_80149490
## @0x80149490 — resolve the (Units,Multi) selector, then re-run the status-anim selector
## per addressed member (MARCH_OPCODE_80_SEMANTICS.md §2). Gariland is SINGLE (Units=0x80,
## Multi=0) → releases ONLY the dialogue speaker frozen by its {11} at PC8; every other unit
## was never frozen and has been march-idling since spawn (`scenario_spawn_facing`), so it is
## deliberately untouched. Broadcast selectors (Multi≠0, scenarios 17/18/31/34) release the
## whole team set through the same `resolve_unit_set`. `time` is the ROM per-unit stagger
## (Gariland=0 = lockstep); not staggered here (release-addressed-only, user-chosen
## 2026-08-01) but decoded for the log. An empty set is a no-op.
static func march(units: int, multi: int, time: int, world: ScenarioWorld) -> void:
	var keys := world.resolve_unit_set(units, multi)
	if keys.is_empty():
		print("[ScenarioApply] WARN March Units=0x%02X Multi=0x%02X — no target unit(s); skipping" %
			[units, multi])
		return
	for key in keys:
		world.release_to_combat_idle(key)
		print("[ScenarioApply] March release 0x%02X (Time=%d)" % [key, time])


## {8C} Unit Anim Rotate — INSTANT set-facing (absolute Direction nibble, no
## interpolation) + set-animation for one unit. Direction is an absolute wheel nibble
## (0=E,4=S,8=W,0xC=N) → target = Direction<<8, snapped (not stepped).
static func unit_anim_rotate(uid_raw: int, direction: int, anim_id: int, world: ScenarioWorld) -> void:
	var key := world.resolve_unit_key(uid_raw)
	if key < 0:
		print("[ScenarioApply] WARN Unit Anim Rotate 0x%04X — no spawned unit; skipping" % uid_raw)
		return
	if not world.has_valid_unit(key):
		return
	var target_12bit := PsxNum.direction_to_12bit(direction & 0xF)
	world.set_unit_facing(key, target_12bit)
	world.play_unit_anim(key, anim_id)
	print("[ScenarioApply] Unit Anim Rotate 0x%02X dir=%d (→0x%03X) anim=0x%X" %
		[key, direction & 0xF, target_12bit, anim_id])


## {2D} Rotate Unit — step the selector's unit(s) facing toward the mode-dispatched
## target (camera-relative / relative / face-target / absolute per the Facing byte)
## over a Direction/Speed/Delay-shaped duration. The stepper lives on the Unit
## (ADR-0055); this resolves the target and arms it PER unit (relative modes read
## each unit's own baseline). The Units/Multi selector broadcasts to a team-set when
## Multi≠0 — the scn6 `[Units=1,Multi=1]` player-team rotate that turns Ovelia
## (0xC00→0x800) and fixes her carry-pose H-flip. Camera yaw is a 0 stub (no
## scenario rotate uses camera-relative mode 0x10). An empty set is a no-op.
static func rotate_unit(intent: ScenarioDecode.RotateUnitIntent, world: ScenarioWorld) -> void:
	var keys := world.resolve_unit_set(intent.units, intent.multi)
	if keys.is_empty():
		print("[ScenarioApply] WARN Rotate Unit Units=0x%02X Multi=0x%02X — no target unit(s); skipping" %
			[intent.units, intent.multi])
		return
	for key in keys:
		var cur_12bit := world.rotate_baseline_12bit(key)
		var target_12bit := ScenarioDecode.resolve_rotate_target_12bit(intent.facing, cur_12bit, 0)
		world.arm_rotate(key, target_12bit, intent.direction, intent.speed, intent.delay)
		print("[ScenarioApply] Rotate Unit 0x%02X facing=0x%02X dir=%d spd=%d dly=%d → target_12bit=0x%03X" %
			[key, intent.facing, intent.direction, intent.speed, intent.delay, target_12bit])


## {53} Face Unit (mutual=false) / {2C} Face Unit 2 (mutual=true). The affected
## unit(s) rotate to look at the faced unit's tile (computed look-at, reusing the
## rotate stepper); {2C} also turns the faced unit 180° back so they face each other.
## The AFFECTED side is a Units/Multi selector — Multi≠0 broadcasts to a team-set,
## each member facing the same faced unit; the faced unit is a separate single ref.
## Skips missing/invalid units and the affected==faced degenerate (ROM LAB_80148128).
## Mutual face-back is single-unit in practice, so it only fires for a 1-unit set.
static func face_unit(aff_raw: int, faced_raw: int, multi: int, direction: int,
		speed: int, delay: int, mutual: bool, world: ScenarioWorld, label: String) -> void:
	var faced := world.resolve_unit_key(faced_raw)
	if faced < 0:
		print("[ScenarioApply] WARN %s faced=0x%04X — no spawned unit; skipping" % [label, faced_raw])
		return
	if not world.can_face(faced):
		print("[ScenarioApply] WARN %s faced=0x%04X — invalid node; skipping" % [label, faced_raw])
		return
	var affected := world.resolve_unit_set(aff_raw, multi)
	if affected.is_empty():
		print("[ScenarioApply] WARN %s affected Units=0x%02X Multi=0x%02X — no target unit(s); skipping" %
			[label, aff_raw, multi])
		return
	var rotated: Array = []
	for aff in affected:
		if aff == faced:
			continue  # ROM skips affected == faced
		if not world.can_face(aff):
			continue
		var target_12bit := world.face_look_at_12bit(aff, faced)
		world.arm_rotate(aff, target_12bit, direction, speed, delay)
		rotated.append(aff)
		print("[ScenarioApply] %s affected=0x%02X faced=0x%02X → aff_12bit=0x%03X dir=%d spd=%d dly=%d" %
			[label, aff, faced, target_12bit, direction, speed, delay])
	# {2C} mutual face-back: the faced unit turns to look at the affected. With a
	# broadcast set this is ambiguous (whom does it face?), and the mutual form is
	# single-unit in practice — so only face back for a single rotated affected.
	if mutual:
		if rotated.size() == 1:
			var faced_target := world.face_look_at_12bit(faced, rotated[0])
			world.arm_rotate(faced, faced_target, direction, speed, delay)
			print("[ScenarioApply] %s faced=0x%02X → faced_12bit=0x%03X (mutual back-face)" %
				[label, faced, faced_target])
		elif rotated.size() > 1:
			print("[ScenarioApply] WARN %s mutual back-face skipped for %d-unit broadcast set" %
				[label, rotated.size()])


## {69} Face Tile — affected unit(s) rotate to LOOK AT a map tile (X,Y) rather than
## a faced unit. Same look-at math + rotate stepper as {53} Face Unit, with the faced
## position taken from the tile centre in the shared raw-tile Godot frame (co-framed
## with every unit; see ScenarioVM._face_tile_look_at_12bit). The affected side is a
## Units/Multi selector — Multi≠0 broadcasts to a team-set, each member facing the
## same tile; Multi=0 is one unit. Skips invalid units; an empty set is a no-op.
static func face_tile(aff_raw: int, multi: int, tile_x: int, tile_y: int,
		direction: int, speed: int, delay: int, world: ScenarioWorld) -> void:
	var affected := world.resolve_unit_set(aff_raw, multi)
	if affected.is_empty():
		print("[ScenarioApply] WARN Face Tile affected Units=0x%02X Multi=0x%02X — no target unit(s); skipping" %
			[aff_raw, multi])
		return
	for aff in affected:
		if not world.can_face(aff):
			continue
		var target_12bit := world.face_tile_look_at_12bit(aff, tile_x, tile_y)
		world.arm_rotate(aff, target_12bit, direction, speed, delay)
		print("[ScenarioApply] Face Tile affected=0x%02X → tile=(%d,%d) 12bit=0x%03X dir=%d spd=%d dly=%d" %
			[aff, tile_x, tile_y, target_12bit, direction, speed, delay])


## {4E} Unit Shadow — enable/disable a unit's ground drop-shadow. ROM sets/clears
## the unit-struct show-flag at unit+0x298 (renderer @ 0x8007D5D0 gates on it);
## Godot toggles the per-unit UnitShadow. Operand `Disable`: 0=enable, 1=disable.
static func unit_shadow(unit_raw: int, disable: int, world: ScenarioWorld) -> void:
	var uid := world.resolve_unit_key(unit_raw)
	if uid < 0:
		print("[ScenarioApply] WARN Unit Shadow 0x%04X — no spawned unit; skipping" % unit_raw)
		return
	world.set_unit_shadow(uid, disable == 0)
	print("[ScenarioApply] Unit Shadow 0x%02X → %s" % [uid, "OFF" if disable != 0 else "ON"])


# ---------------------------------------------------------------------------
# Tint & palette — {32} Color Unit / {33} Color Field / Reset Palette / {1A}
# Map Darkness. The affine math is in ScenarioColorTint; the ramp state (ticked
# outside the halt gate) stays VM-side. Apply resolves + drives the tint object
# through verbs.
# ---------------------------------------------------------------------------

## {32} Color Unit — per-unit palette tint (a ramp, not a hide). Resolves the
## Units/Multi selector, then for each targeted unit folds the operand into its live
## [ScenarioColorTint] and pushes it to the shader (composed with any active {33}
## field tint); a pure-identity result is dropped so the tick loop skips it. Multi≠0
## broadcasts the tint to a team-set; Multi=0 is one unit. An empty set is a no-op.
static func color_unit(intent: ScenarioDecode.ColorUnitIntent, world: ScenarioWorld) -> void:
	var keys := world.resolve_unit_set(intent.units, intent.multi)
	if keys.is_empty():
		push_warning("[ScenarioApply] Color Unit Units=0x%02X Multi=0x%02X mode=%d — no target unit(s); skipping"
			% [intent.units, intent.multi, intent.mode])
		return
	for key in keys:
		var tint := world.get_or_create_unit_tint(key)
		# Modes 2/3/6/7 are luma (sepia); apply() latches the luma spec and the
		# shader takes its luma branch — no longer approximated as affine.
		tint.apply(intent.mode, intent.red, intent.green, intent.blue, intent.time)
		world.push_unit_tint(key, tint)
		if tint.is_identity():
			world.clear_unit_tint(key)
		print("[ScenarioApply] Color Unit 0x%02X mode=%d RGB=(%d,%d,%d) Time=%d"
			% [key, intent.mode, intent.red, intent.green, intent.blue, intent.time])


## Reset Palette — drop a unit's Color Unit tint and restore its shader to identity.
## No-op for an unspawned unit (PSX 0x7d0 sentinel).
static func reset_palette(uid_raw: int, world: ScenarioWorld) -> void:
	var key := world.resolve_unit_key(uid_raw)
	if key < 0:
		print("[ScenarioApply] Reset Palette Unit=0x%04X — no spawned unit; no-op" % uid_raw)
		return
	world.clear_unit_tint(key)
	world.push_unit_tint(key, ScenarioColorTint.new())
	print("[ScenarioApply] Reset Palette Unit=0x%04X (resolved 0x%02X) → tint cleared" % [uid_raw, key])


## {68} Mirror Sprite — latch the addressed unit's persistent whole-sprite
## horizontal-flip delta. `mirror` is the raw operand byte: the ROM handler tests
## `== 1` and every other value takes the clear path, so this is faithful rather
## than `!= 0` (no corpus site uses anything but 0 or 1). Single-unit by design —
## the ROM resolves through `unit_id_validate_resolve`, not the {2D}/{11}
## multi-selector, so there is no Units/Multi broadcast here.
##
## The flip COMPOSES BY XOR with the facing/camera-derived flip
## (`render_flags(+0x12) ^ flip_xor_mask(+0x13F)` @0x80086764), which is why the
## world verb latches a separate half rather than writing the final reversion —
## see research/working_documents/MIRROR_SPRITE_OPCODE_68.md.
static func mirror_sprite(uid_raw: int, mirror: int, world: ScenarioWorld) -> void:
	var key := world.resolve_unit_key(uid_raw)
	if key < 0:
		print("[ScenarioApply] WARN Mirror Sprite Unit=0x%04X Mirror=%d — no spawned unit; skipping" % [uid_raw, mirror])
		return
	var mirrored := mirror == 1
	world.set_unit_mirror(key, mirrored)
	print("[ScenarioApply] Mirror Sprite Unit=0x%04X (resolved 0x%02X) Mirror=%d → flip_xor=%s"
		% [uid_raw, key, mirror, str(mirrored)])


## {33} Color Field — the whole-scene palette fade: the same affine as {32}
## broadcast to every unit + the map palette (composed per unit with its own {32}
## tint). A pure-identity result is dropped.
static func color_field(intent: ScenarioDecode.ColorFieldIntent, world: ScenarioWorld) -> void:
	var tint := world.get_or_create_field_tint()
	# Modes 2/3/6/7 are luma (the whole-scene sepia wash); apply() latches the luma
	# spec and every surface's shader takes its luma branch — no longer approximated.
	tint.apply(intent.mode, intent.red, intent.green, intent.blue, intent.time)
	world.push_field_tint_to_all()
	if tint.is_identity():
		world.clear_field_tint()
	print("[ScenarioApply] Color Field mode=%d RGB=(%d,%d,%d) Time=%d"
		% [intent.mode, intent.red, intent.green, intent.blue, intent.time])


## {1A} Map Darkness — the prayer "oxide" screen tint: integrate a per-channel byte
## color toward `target` over `duration_ticks` (or snap when Time≤0). The ramp state
## is ticked VM-side; the verb owns the state mutation.
static func map_darkness(intent: ScenarioDecode.MapDarknessIntent, world: ScenarioWorld) -> void:
	if intent.blend != 4:
		push_warning("[ScenarioApply] Map Darkness Blend=%d not yet modeled; treating as byte-add (mode 4)"
			% intent.blend)
	world.set_map_darkness(intent)
	print("[ScenarioApply] Map Darkness Blend=%d target=%s snap=%s dur=%d"
		% [intent.blend, str(intent.target), str(intent.snap), intent.duration_ticks])


# ---------------------------------------------------------------------------
# Screen & overlay effects — {3C} Weather / {76}/{77}/{78} Dark Screen family /
# {7D} Show Graphic / Reveal. The overlays lazily create their scene nodes; the
# verb owns that so apply stays node-free. Wait barriers stay VM-side.
# ---------------------------------------------------------------------------

## {3C} Weather — drive the map-wide rain particle latch. `active=false` (or
## strength < 2) cancels; the verb lazily spawns the particle system on the first
## active latch and no-ops an inactive latch when none exists yet.
static func weather(intent: ScenarioDecode.WeatherIntent, world: ScenarioWorld) -> void:
	world.set_weather(intent.active, intent.strength)
	print("[ScenarioApply] Weather strength=%d active=%s" % [intent.strength, str(intent.active)])


## {76} Dark Screen — start the expanding diamond-mosaic overlay. The kind-54 {E5}
## barrier that holds while it settles is armed VM-side.
static func dark_screen(intent: ScenarioDecode.DarkScreenIntent, world: ScenarioWorld) -> void:
	world.show_dark_screen(intent)
	print("[ScenarioApply] Dark Screen shape=%d screenExp=%d sqExp=%d rot=%d" %
		[intent.shape, intent.screen_expansion_speed, intent.square_expansion_speed,
		intent.rotation_speed])


## {77} Remove Dark Screen — retract the mosaic (the barrier already released on
## grow-in). No-op when no overlay exists.
static func remove_dark_screen(world: ScenarioWorld) -> void:
	world.hide_dark_screen()
	print("[ScenarioApply] Remove Dark Screen")


## {3E} Color Screen — arm the full-screen colour ramp (start->end RGB over Time,
## ABR-blended per Mode). Lazily creates the overlay; the ramp ticks on the unified
## clock and the following {E5} Task=12 blocks until it lands on `end`.
static func color_screen(intent: ScenarioDecode.ColorScreenIntent, world: ScenarioWorld) -> void:
	world.show_color_screen(intent)
	print("[ScenarioApply] Color Screen mode=%d start=%s end=%s time=%d" %
		[intent.mode, str(intent.start), str(intent.end), intent.time])


## {2E} Background — set/ramp the full-screen gradient quad. Snap (Time≤0) applies
## the corners immediately; Time>0 arms a linear ramp over `Time*8` frames that the
## VM ticks and re-pushes to the background quad each frame. The Orbonne lightning
## flash is a sequence of these (snap the storm sky, ramp bright, ramp back).
static func background(intent: ScenarioDecode.BackgroundIntent, world: ScenarioWorld) -> void:
	world.get_or_create_background().apply(intent.top, intent.bottom, intent.time)
	world.push_screen_background()
	print("[ScenarioApply] Background top=%s bottom=%s Time=%d snap=%s"
		% [str(intent.top), str(intent.bottom), intent.time, str(intent.snap)])


## {78} Display Conditions — run one results/intro screen over the {76} dim. The
## first operand byte is a MODE, not a conditions id (BATTLE_RESULTS_SCREEN.md §13):
## 0 = READY!, 2 = the victory text, 3 = BONUS MONEY + the gil reel, 4/5/6 =
## WAR TROPHIES / WARNING / PARTING SHOT!!, 7 = the recruit flow, >= 8 = the
## victory-condition banner for BONUS.BIN page `mode - 8`. `Time` is the hold, and
## it reaches ONLY mode 0 and modes >= 8 — the dispatcher spawns 1..7 with all three
## params zero, so those bodies hard-code their own durations.
static func display_conditions(conditions: int, time: int, world: ScenarioWorld) -> void:
	world.show_conditions(conditions, time)
	print("[ScenarioApply] Display Conditions mode=%d time=%d" % [conditions, time])


## {7D} Show Graphic — fade a fullscreen graphic in/hold/out. The kind-61 {E5}
## barrier that holds while it's on screen is armed VM-side.
static func show_graphic(intent: ScenarioDecode.ShowGraphicIntent, world: ScenarioWorld) -> void:
	world.show_graphic(intent)
	print("[ScenarioApply] Show Graphic id=0x%02X" % intent.graphic_id)


## {91} Show Map Title — reveal a location-name strip (L->R wipe), hold, erase
## (L->R wipe). BLOCKS the VM until the strip erases (the handler arms a wait; the
## PSX built-in FUN_8014c9d0, NOT a following {E5}); the strip ticks VM-side
## outside the halt gate. The MAPTITLE slot is resolved from the current map
## inside the world verb.
static func show_map_title(intent: ScenarioDecode.MapTitleIntent, world: ScenarioWorld) -> void:
	world.show_map_title(intent)
	print("[ScenarioApply] Show Map Title X=%d Y=%d Speed=%d" % [intent.x, intent.y, intent.speed])


## Reveal — fade in from black over `time` frames (floored at 1). The fade ramp is
## ticked VM-side; this arms it.
static func reveal(time: int, world: ScenarioWorld) -> void:
	var t := time if time > 0 else 1
	world.arm_reveal(t)
	print("[ScenarioApply] Reveal T=%d (fade in from black)" % t)


# ---------------------------------------------------------------------------
# Dialogue — {10} Display Message / Change Dialog. Apply does the WORLD
# mutation (show/replace/close a box, or the free overlay) through
# ScenarioWorld verbs so the VM stops poking box-pool internals across call
# sites (the review's Card 2 seam). The advance-GATE stays VM scheduler state:
# display_message returns whether a boxed box was shown (VM arms the gate), and
# change_dialog returns the gate action for the VM to apply.
# ---------------------------------------------------------------------------

## {10} Display Message — the free overlay (Dialog 0x09, non-blocking prayer) or a
## boxed variant. `tokens` is the pre-decoded message text (from the instruction's
## dialogue payload). Returns true iff a boxed box was shown — the one case that arms
## the VM's advance gate. The overlay is deliberately non-blocking (the real barrier
## is the later {E5} Wait For Instruction Task=1); a missing overlay/box or empty
## tokens is skipped.
static func display_message(intent: ScenarioDecode.DisplayMessageIntent, tokens: Array,
		world: ScenarioWorld) -> bool:
	# A new message clears any previous overlay text (PSX single-slot dialog struct).
	world.clear_dialogue_overlay()
	if intent.is_overlay:
		if not world.has_dialogue_overlay():
			print("[ScenarioApply] overlay Display Message msg=#%d — no DialogueOverlay wired (VM-only context); skipping" % intent.msg_id)
			return false
		if tokens.is_empty():
			print("[ScenarioApply] overlay Display Message msg=#%d — empty tokens, skipping" % intent.msg_id)
			return false
		world.show_dialogue_overlay(tokens, intent.psx_x, intent.psx_y, intent.dialog)
		print("[ScenarioApply] overlay Display Message msg=#%d tokens=%d at psx=(%d,%d) Dialog=0x%02X (valign=%d)" %
			[intent.msg_id, tokens.size(), intent.psx_x, intent.psx_y, intent.dialog, intent.dialog & 0x3])
		return false
	if not world.is_boxed_dialog(intent.dialog):
		print("[ScenarioApply] skip unsupported Display Message Dialog=0x%02X msg=#%d" %
			[intent.dialog, intent.msg_id])
		return false
	if not world.has_dialogue_box():
		print("[ScenarioApply] boxed Display Message Dialog=0x%02X msg=#%d — no DialogueBox wired (VM-only context); skipping" %
			[intent.dialog, intent.msg_id])
		return false
	if tokens.is_empty():
		print("[ScenarioApply] boxed Display Message msg=#%d — empty tokens, skipping" % intent.msg_id)
		return false
	var slot := world.show_dialogue_box(tokens, intent.dialog, intent.speaker_uid,
		intent.portrait_row, intent.open_type, intent.psx_x, intent.psx_y, intent.fine_x60)
	print("[ScenarioApply] boxed Display Message msg=#%d Dialog=0x%02X speaker=0x%02X tokens=%d slot=%d" %
		[intent.msg_id, intent.dialog, intent.speaker_uid, tokens.size(), slot])
	return true  # arm the advance gate


## Change Dialog — close (Message 0xFFFF) or swap in place a dialog box. Routes all
## box access through verbs; returns a gate action for the VM to apply: `close_fg`
## (foreground box closed — tear down the gate), `close_bg` (a demoted box closed —
## gate untouched), `swap` (text swapped — arm the gate), or `noop`.
static func change_dialog(msg: int, target: int, portrait_byte: int, world: ScenarioWorld) -> Dictionary:
	var slot := world.resolve_dialog_slot(target)
	if msg == 0xFFFF:
		var was_foreground := world.close_dialog_slot(slot)
		print("[ScenarioApply] Change Dialog: close box (Target=%d slot=%d)" % [target, slot])
		return {"action": "close_fg" if was_foreground else "close_bg", "slot": slot}
	var toks := world.dialog_tokens_for(msg)
	if toks.is_empty():
		print("[ScenarioApply] Change Dialog: swap msg #%d has no baked tokens; keeping current box" % msg)
		return {"action": "noop", "slot": slot}
	if not world.swap_dialog_text(slot, toks, portrait_byte):
		return {"action": "noop", "slot": slot}  # no box at slot — silent no-op (as PSX)
	print("[ScenarioApply] Change Dialog: swap Target=%d slot=%d to msg #%d (%d tokens)" %
		[target, slot, msg, toks.size()])
	return {"action": "swap", "slot": slot}


# ---------------------------------------------------------------------------
# Field objects & EVTCHR — {58} Load EVTCHR / {55} Use Field Object / {54} Use
# 3D Object. The map texture-animation render + modeled-fallback state and the
# EVTCHR slot map are VM/scene machinery; apply resolves + drives the verb. The
# paired {57}/{56} Wait barriers stay VM-side.
# ---------------------------------------------------------------------------

## {58} Load EVTCHR — map an EVTCHR segment slot into a cinematic block (consumed by
## cinematic-range Unit Anim). Pure VM bookkeeping.
static func load_evtchr(block: int, slot: int, world: ScenarioWorld) -> void:
	world.load_evtchr(block, slot)
	print("[ScenarioApply] Load EVTCHR Block=%d Slot=0x%04X" % [block, slot])


## {55} Use Field Object — play a one-shot map texture-animation (or a modeled-timer
## fallback when the map can't render it). The verb owns the render attempt + the
## fallback state that the {57} Wait barrier polls; returns whether it really rendered.
static func use_field_object(id: int, arg2: int, world: ScenarioWorld) -> void:
	var rendered := world.play_field_object(id, arg2)
	print("[ScenarioApply] Use Field Object id=%d (unknown=%d) rendered=%s" % [id, arg2, rendered])


## {54} Use 3D Object — set 3D-object #ID to `state` (modeled-timer state the {56}
## Wait barrier polls; the real render is Stage 2).
static func use_3d_object(id: int, state: int, world: ScenarioWorld) -> void:
	world.play_3d_object(id, state)
	print("[ScenarioApply] Use 3D Object id=%d state=%d" % [id, state])


# ---------------------------------------------------------------------------
# Sound — {21} Sound Effect / {60} Fade Sound. The two *stateless* sound opcodes
# seam fully (decode → apply verb). The stateful {6B}/{6A} BG Sound (ramp
# registry) and {22} Switch Track (toggle) keep their VM handlers per ADR-0058
# ("scheduler state stays on the VM"); those call the same ScenarioWorld sound
# verbs directly for the SPU/music backend access.
# ---------------------------------------------------------------------------

## {21} Sound Effect — play a system SFX by catalog id.
static func sound_effect(sound_id: int, world: ScenarioWorld) -> void:
	world.play_system_sound(sound_id)
	print("[ScenarioApply] Sound Effect id=0x%02X" % sound_id)


## {60} Fade Sound — fade the active music to silence over `intent.ticks` sequencer
## ticks (a no-op if no music is playing).
static func fade_sound(intent: ScenarioDecode.FadeSoundIntent, world: ScenarioWorld) -> void:
	world.fade_music(intent.ticks)
	print("[ScenarioApply] Fade Sound ticks=%d" % intent.ticks)


## {7C} End Sound — stop the currently-playing event SFX/BGM (PSX SUB_800440cc:
## clear the active-sound handle + 8-voice teardown). No operands.
static func end_sound(world: ScenarioWorld) -> void:
	world.stop_all_event_sound()
	print("[ScenarioApply] End Sound")
