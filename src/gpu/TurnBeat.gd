class_name TurnBeat
extends RefCounted
## The TURN-OPEN BEAT — the 0.3 s "it is this unit's turn" presentation
## (`docs/TURN-OPEN-BEAT-DESIGN.md`), extracted from `GambitBattle` so the two
## CombatLoop hosts can both show it (ADR-0265).
##
## [TurnDirector] answers *when* a turn opens. This answers *what the player sees
## when it does*: the AT marker lands on the taker, the ROM's informational-plate
## cue plays, and the camera travels to them while the input surfaces of the
## battlefield are held shut for the length of the travel.
##
## === Why a component and not a base class ====================================
##
## The two hosts are two lineages — `GambitBattle extends CombatHost`,
## `NavigatorMain extends ScenarioPlayerScene` — and GDScript has no multiple
## inheritance, so the only shape that can serve both is composition. It is the
## shape [method TurnDirector.mount], `CursorRig.mount` and `TurnQueueHud.mount`
## already established on this seam, and the reason ADR-0239 put the director on
## the LOOP rather than on the host applies verbatim here: a presentation feature
## that lived on `CombatHost` would be unreachable from the host that deliberately
## does not extend it.
##
## ⚠️ ADR-0264 rejected "extract a shared component" for BATTLE ENTRY only. That
## rejection is about which host owns the seek; it says nothing about the
## turn-presentation features, so do not cite it here.
##
## === What this is NOT ========================================================
##
## **It does not pump.** The travel is a FRAME COUNTER the host advances from its
## own `_process` ([method advance]) — not a `Tween` and not an `await`. Two
## reasons, both from the design: the travel has to advance through the director's
## FREEZE (where nothing else is ticking), and a counter is a state a test can read
## and drive instead of a duration it has to sleep through (TEST-CHARTER clause 14).
##
## **It does not decide whose turn is worth a beat.** The host's steerability set
## does. An enemy turn is opened and passed inside one freeze, and a marker that
## flashed on and off eleven times a round-robin would be noise.
##
## **It owns no lifetime but the marker's.** The cursor rig, the camera and the
## lattice are the HOST's, re-bound on every use ([method bind]) rather than
## latched at construction — `GambitBattle` builds its rig after `_ready` and
## `NavigatorMain` builds one per battle, so a reference taken once is a reference
## that goes stale on the second battle.

# ADR-0211 dec. 4 — one alias line per file is what keeps a grep for the façade a
# complete census of the coupling.
const TerrainCell = ExMateriaSchema.TerrainCell
const Lattice = ExMateriaBattlefield.Lattice

## The cue: the ROM's own "an informational plate just came up" (system bank slot 18).
## Rejected alternatives are in the design's §6 — `confirm_selection` is transactional and
## you hear it again two seconds later at the actual confirm; `power_up` reads as a buff
## landing.
const CUE_TURN_OPEN := "help_message_popup"

# --- What the host lends us (re-bound per use; see the class doc) -------------
var cursor_rig = null      # CursorRig
var camera = null          # PlayerCamera
var lattice: Lattice = null
var units: Array = []

## Frames left in the camera travel, or 0 when no beat is running.
##
## The length is `PlayerCamera.follow_ease_frames` READ AT ARM TIME and not a second knob:
## the travel is the camera's own cosine ease, so a private constant here would be a
## duplicate that drifts the moment somebody turns `camera.follow_ease_frames` (ADR-0068).
var frames_left: int = 0

## The unit the running beat is travelling to, or -1. Kept separately from
## `TurnDirector.taker()` because the beat has to be able to LAND on the unit it started
## for even if the turn moved underneath it, and because [method recenter] needs a subject
## after the beat is over.
var beat_taker: int = -1

## The unit index the AT marker is on, or -1 for "no marker". A plain int and not a bool,
## because the sprite is parented to a unit and "shown" is meaningless without saying whose.
var marker_unit: int = -1

## The mounted marker node, or null. Held so a re-show can free the previous one — the node
## is a child of the UNIT, so a taker that died mid-turn takes it with them and this
## reference goes invalid rather than dangling.
var marker: TurnMarker3D = null


## Build a beat. Nothing is bound yet: every caller binds at use (see the class doc), and a
## constructor that took the four handles would read as if they were latched.
static func mount() -> TurnBeat:
	return TurnBeat.new()


## Re-point at the host's current cursor / camera / terrain / cast. Called immediately
## before every [method open] and [method recenter]; cheap, and the one thing that keeps a
## per-battle rig from going stale under a beat that outlived it.
func bind(p_cursor_rig, p_camera, p_lattice: Lattice, p_units: Array) -> void:
	cursor_rig = p_cursor_rig
	camera = p_camera
	lattice = p_lattice
	units = p_units


## Arm the beat for a steerable taker.
##
## The order — camera first, cursor last — is load-bearing and is NOT `seed_from_map`'s.
## That helper moves the cursor and THEN snaps the camera; here the camera is driven to the
## taker first and the cursor arrives at the end, so the cursor's own `cursor_moved` →
## `CursorController._on_cursor_moved` → `camera.track_cursor` finds the camera already at
## the position it would ask for and the deadzone leaves it alone. Reversed, the player sees
## two moves: a snap and then an ease.
func open(taker: int) -> void:
	beat_taker = taker
	# Shown at the FREEZE, not on arrival, so the marker is already on the unit when the
	# camera gets there rather than popping in at the end of its own travel.
	show_marker(taker)
	SfxRouter.play_system(CUE_TURN_OPEN)

	var cell := taker_cell(taker)
	if cursor_rig == null or camera == null or not is_instance_valid(camera) \
			or cell == TerrainCell.NONE:
		# Nothing to travel with. The turn is still open and still steerable — a missing
		# camera must not leave the cursor deaf, which is the one failure mode of this whole
		# feature that the player cannot recover from.
		end()
		return

	# The degenerate case is a decision, not an optimisation (design §1): with the cursor
	# already on the taker there is nothing to show, so travelling zero distance while
	# refusing input for 18 frames would be a toll with no beat behind it.
	if cursor_rig.grid_pos == Vector2i(cell.x, cell.y):
		end()
		return

	camera.follow_cursor(world_of(cell))
	# There is no skip (design §1), and a swallow is THREE gates because the battlefield
	# accepts device input on three surfaces: the cursor (movement, ○, ✕, △), the camera
	# (Q/E and F — and Q/E is the one that matters, because `_rotate_yaw` re-aims a running
	# travel at the cursor's pre-beat tile), and the HOST's own `_unhandled_input`. Gating
	# one of the three is not a swallow; it just tells the player which key still works.
	# The third gate is the host's, and [method running] is the predicate it asks.
	cursor_rig.input_enabled = false
	camera.input_enabled = false
	frames_left = maxi(1, camera.follow_ease_frames)


## One frame of the travel. Driven from the host's `_process`, which keeps running through
## the freeze — the director gates `CombatLoop.tick` and nothing else (ADR-0037 dec. 2),
## which is the whole reason a travel-while-frozen needs no new machinery.
func advance() -> void:
	if frames_left <= 0:
		return
	frames_left -= 1
	if frames_left > 0:
		return
	# The landing. `move_to` and not `seed_from_map`: this is a placement onto a cell the
	# camera has already arrived at, and `seed_from_map` would snap the camera a second time.
	var cell := taker_cell(beat_taker)
	if cursor_rig != null and cell != TerrainCell.NONE:
		cursor_rig.move_to(Vector2i(cell.x, cell.y))
	end()


## Beat over: the cursor is free again. Called on landing, on the degenerate case, on a
## failed arm, and on commit — every exit, because a cursor left deaf is a game that stopped
## responding with nothing in the log.
func end() -> void:
	frames_left = 0
	if cursor_rig != null:
		cursor_rig.input_enabled = true
	if camera != null and is_instance_valid(camera):
		camera.input_enabled = true


## Is the travel running right now? The one predicate the host's input gate asks.
func running() -> bool:
	return frames_left > 0


## `Home` — snap BOTH cursor and camera back to the turn taker (design §4).
##
## 🔴 THE DESIGN'S STATED REASON IS NOT THE MEASURED ONE, and the key is right anyway.
## §4 says `camera_up/down/left/right` "can pan the camera off the taker independently of
## the cursor". Measured: those four ARE `TileCursor.CURSOR_ACTIONS`, they walk the CURSOR,
## and `PlayerCamera._execute_translation` returns immediately unless the
## `camera.free_camera` debug override is on — so in normal play they never pan anything on
## their own.
##
## What actually strands the taker is the cursor, which this design deliberately leaves FREE
## (§3): walk it across the map and the camera follows it there, and now the unit whose turn
## it is — and the AT sprite with it — is off screen with no cheap way back. Q/E is the
## second route: `PlayerCamera._rotate_yaw` recentres on the CURSOR's tile, not on the
## taker's. Both make §4's conclusion right, so the action stays; only its rationale moves.
##
## A snap and not a travel: this is a correction the player asked for, not a beat being
## shown to them.
func recenter() -> void:
	if beat_taker < 0 or cursor_rig == null:
		return
	var cell := taker_cell(beat_taker)
	if cell == TerrainCell.NONE:
		return
	cursor_rig.move_to(Vector2i(cell.x, cell.y))
	if camera != null and is_instance_valid(camera) and lattice != null:
		camera.follow_cursor(world_of(cell), true)


## The AT marker seam — SHOW. Mounts the ROM's "AT" sprite ([TurnMarker3D]) as a child of
## the taker. Player turns only — an enemy turn is an open-and-pass, and a marker that
## flashes on and off eleven times a round-robin is noise.
##
## This is a DELIBERATE divergence from the ROM, whose predicate is `unit[+4] == the acting
## unit` whoever that is (AT_MARKER_RENDERING.md §4.1). The gate is the HOST's steerability
## set, per TURN-OPEN-BEAT-DESIGN.md §5; changing it back is a design decision, not a
## fidelity bug to quietly fix.
##
## Idempotent, because a cancel re-opens the SAME turn and the marker must survive it.
func show_marker(unit_index: int) -> void:
	if marker_unit == unit_index and marker != null and is_instance_valid(marker):
		return
	hide_marker()
	marker_unit = unit_index
	var unit = units[unit_index] if unit_index >= 0 and unit_index < units.size() else null
	if unit == null or not is_instance_valid(unit):
		# The index is still recorded: the beat's observable is "whose turn is marked", and a
		# unit that cannot host a sprite must not silently read as "no turn open".
		return
	marker = TurnMarker3D.new()
	unit.add_child(marker)


## The AT marker seam — HIDE. On `turn_committed` and nowhere else: never absent while a
## turn is open, never present when one is not.
func hide_marker() -> void:
	marker_unit = -1
	if marker != null and is_instance_valid(marker):
		marker.queue_free()
	marker = null


## Where the taker is standing, as a CELL. `Unit.get_current_cell()` and not a grid→unit
## helper's inverse: re-deriving unit→grid by scanning one would make two units on one
## column ambiguous in the one place the answer has to be exact.
func taker_cell(taker: int) -> Vector3i:
	if taker < 0 or taker >= units.size():
		return TerrainCell.NONE
	var unit = units[taker]
	if unit == null or not is_instance_valid(unit):
		return TerrainCell.NONE
	return unit.get_current_cell()


## Where a cell IS, in world space. Through the port: the answer derives from a live node
## transform and is the one terrain fact that can go stale, which is why ADR-0192 dec. 6
## made it a query rather than a payload field.
func world_of(cell: Vector3i) -> Vector3:
	return lattice.world_position_at(cell) if lattice != null else Vector3.ZERO
