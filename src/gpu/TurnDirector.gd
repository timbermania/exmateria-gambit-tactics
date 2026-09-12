class_name TurnDirector
extends Node
## The TURN DIRECTOR — freeze / hand off / commit / cancel (ADR-0239, design S1/S3).
##
## A component node mounted onto a [CombatLoop]. NOT on the host scene and NOT on
## [CombatHost]: `CombatHost` has exactly one subclass (`GPUArena`) and
## `NavigatorMain` deliberately does not extend it — it builds a bare `CombatLoop`
## and mirrors the host pump by hand. There are already two CombatLoop hosts
## duplicating that; put this on a host and there would be three. The consequence
## that proves the placement is that `TurnDirectorTest` mounts it on a bare loop
## with **no host scene at all**.
##
## What it does: the world runs, and the instant a living unit's TURN METER
## crosses `TURN_METER_FULL` the world FREEZES on that exact tick and the turn is
## handed off. Somebody — the adjustment UI, the enemy's rollout driver, or a test
## — then calls [method commit] or [method cancel]. The clock only ever advances
## from one turn to the next.
##
## It directs turns, not gambits: `NavigatorMain` mounts the same director, where
## "gambit" is not the word for what is happening. The gambit-specific parts (the
## adjustment UI, the AI) are what mount ON it.
##
## === What this is NOT ========================================================
##
## **It does not pump.** [CombatLoop.tick] is the one pump and the one freeze
## authority (ADR-0037 dec. 2: "one authority, no mirror"); ADR-0083 dec. 1 makes
## the double-pump structurally impossible by giving every unit clock exactly one
## owner, and its Considered options weighed a single clock authority and set it
## aside. A director that pumped would be the third thing able to advance
## COMBAT-owned bodies — the very condition ADR-0083 expressed away. So this
## GATES (`combat_active`) and SCALES (`playback_scale`); both hosts are untouched.
##
## **It does not decide who the player is.** It announces which unit is up and
## makes no judgement about sides — `NavigatorMain` puts guests on team 0, and a
## guest is a unit the player may not command. Team rides along in
## [signal turn_opened] only because [TurnQueue] already carries it.
##
## **It does not decide whether a turn is worth stopping for.** That is
## [member stops_the_world], and it is the host's to set: `GambitBattle` is played
## and stops, `NavigatorMain`'s walk is watched and does not. The stop living behind
## [member CombatLoop.turn_gate] as a predicate — rather than welded into the tick
## loop — is what makes that one flag instead of a second class.

const FULL := GPUCombatPacker.TURN_METER_FULL

## A living unit crossed the meter and the world has frozen on that tick. `taker`
## is the unit index whose turn it is; `team` is its team, passed through from
## [TurnQueue] and never branched on here. DEPLOYMENT opens with `taker == -1`:
## deployment is a turn with the clock stopped and the meter gate removed (design
## S9), so it is the same signal in a different mode, not a second freeze path.
signal turn_opened(taker: int, team: int)
## The turn was spent. Emitted AFTER `consume_turn`, before the next turn opens.
signal turn_committed(taker: int)
## The turn's edits were thrown away and the same turn is about to re-open.
signal turn_cancelled(taker: int)
## The last ready unit committed and the between-turn stretch has begun.
signal resumed()

enum State {
	## The between-turn stretch: the world is advancing and the gate is armed.
	RUNNING,
	## Frozen, and a taker holds the turn.
	TURN_OPEN,
	## Frozen, no taker, meter gate removed — the deployment assignment (design S9).
	DEPLOYMENT,
}

# --- Tunables (ADR-0068) -----------------------------------------------------

const PLAYBACK_RATE_SLUG := "gambit.playback_rate"

## The between-turn playback rate: how fast the world plays from one turn to the
## next. A `static var` home and not a `const`, because a `const` is frozen at
## parse time and a scrub could never reach its readers (ADR-0068 dec. 13).
##
## It is a VIEWING rate, not a simulation rate. The stretch's length in TICKS is
## fixed — it ends when the next unit crosses — so this changes only how long you
## spend watching it and can never change an outcome. Deliberately not
## instantaneous: the between-turn stretch is where the consequences of the
## player's gambits become visible, and skipping it severs the feedback loop.
static var playback_rate: float = 1.0


static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## This owner's named registration entry point (ADR-0173): `_static_init` calls it
## at class load — the only thing that does — and the guards call it to read back
## which slugs this owner binds.
static func register_tunables() -> void:
	Tune.bind(PLAYBACK_RATE_SLUG, playback_rate,
		{"min": 0.25, "max": 8.0, "step": 0.25})


# --- Wiring ------------------------------------------------------------------

## The loop this director gates. Untyped for the same reason [CombatHost] leaves
## its own reference untyped: the `class_name` may be absent from a stale global
## cache.
var combat_loop = null
## Which battle in the batch this director directs. The rollout fleet's candidate
## battles are directed by nobody — only the real battle has turns.
var battle_id: int = 0

var _state: int = State.RUNNING
var _taker: int = -1
## The pre-turn image, taken per TAKER and not per freeze. Two units can be ready
## at the same stop and take their turns back to back; a snapshot scoped to the
## freeze would let a cancel of the second silently revert the first's committed
## decision — the invisible divergence ADR-0235 rejects a lossy round trip to
## avoid. DEPLOYMENT holds {} : nothing is ticking and the units are not in the
## GPU buffer yet (`boot_battle` is what puts them there), so its placements are
## CPU-side and land in one write at commit. There is nothing to undo.
var _snapshot: Dictionary = {}

## Whether an open turn STOPS the world (WAIT mode, the default), or is spent where
## it opens.
##
## A turn only means something if somebody is there to take it — the adjustment UI
## (#894), the rollout driver (#897), or a test. `NavigatorMain` mounts this
## director on a battle NOBODY plays: the walk's combat is a spectacle that runs
## itself to annihilation, and a director that froze there would hand the first
## crossing to nobody and hang the walk on it.
##
## False is not a lesser director. It still ORDERS the turns and still SPENDS them,
## which is what keeps the meters moving and the forecast meaningful: with nothing
## consuming turns the kernel stops advancing a meter that has crossed and leaves
## it at its crossing value, so every living unit sits permanently ready and the
## queue degenerates to "everyone, now". What it drops is the freeze — and with the
## freeze, the snapshot, because nothing can cancel a turn nobody holds, which is
## also what keeps the policy affordable at the walk's fast-forward rate.
##
## This is design S3's "Active mode is the same machine that simply does not stop at
## the next turn" in its first and smallest form: the stop is gone and nothing else
## is claimed — no shot clock, and no player who may interject.
##
## It also arms THE TURN BRAKE. A host that stops for turns needs its kernel to
## stop the taker FIRST — see [method _apply_brake].
var stops_the_world: bool = true:
	set(value):
		if stops_the_world == value:
			return
		stops_the_world = value
		_apply_brake()


## Mount a director on a loop. The one-line form design S11 requires of
## `NavigatorMain`, and the shape `CursorRig.mount` already established.
static func mount(loop: Node, p_battle_id: int = 0) -> TurnDirector:
	var director := TurnDirector.new()
	director.name = "TurnDirector"
	director.combat_loop = loop
	director.battle_id = p_battle_id
	loop.add_child(director)
	# Also installed here, not only in `_ready`. A node added to a parent that is
	# not yet inside the tree has its `_ready` DEFERRED until the parent enters,
	# and a caller that mounts before `add_child(loop)` would otherwise get a
	# director whose gate is not armed yet. Idempotent with `_ready`'s install.
	director._install_gate()
	return director


func _ready() -> void:
	# The write-back that lands a scrub on the static var's direct readers
	# (ADR-0068 dec. 15). A registration alone is inert to scrubbing.
	Tune.on_update(self, PLAYBACK_RATE_SLUG, func(v: float) -> void: playback_rate = v)
	_install_gate()


func _install_gate() -> void:
	if combat_loop != null:
		combat_loop.turn_gate = Callable(self, "_turn_gate")
		combat_loop.playback_scale = playback_rate
		_apply_brake()


## Arm (or disarm) the kernel's turn brake for this battle.
##
## THE BRAKE AND THE SETTLED TEST IN [method _turn_gate] ARE ONE MECHANISM AND
## SHIP TOGETHER. The gate refuses to freeze a world in which a ready unit is
## mid-movement-step, because logical position is the DESTINATION for the whole
## duration of a step, so freezing mid-step lands the camera on a cell whose
## sprite has not arrived. On its own that gate would HANG: a continuously walking
## unit is never settled, and on the tick its timer drains the kernel can write the
## next step in the same tick, so the columns the gate reads need never show a
## settled walker. The brake is what makes settled REACHABLE — a ready unit
## finishes the step it is on and starts nothing new.
##
## Gated on [member stops_the_world] and nothing else, so `NavigatorMain`'s walk —
## which announces and spends turns where they open and never freezes — has no
## brake and is untouched by construction. No second flag.
##
## Idempotent and safe before the simulator exists: `mount` runs before
## `boot_battle` in at least one host, and `TurnDirectorTest` mounts on a bare loop
## with no simulator at all.
func _apply_brake() -> void:
	if combat_loop == null or not is_instance_valid(combat_loop):
		return
	if combat_loop.gpu_simulator == null:
		return
	combat_loop.gpu_simulator.turn_brake_battle = battle_id if stops_the_world else -1


func _exit_tree() -> void:
	# The loop outlives the director in every teardown order that matters; a gate
	# left pointing at a freed node is a per-tick call into nothing.
	if combat_loop != null and is_instance_valid(combat_loop) \
			and combat_loop.turn_gate.is_valid() \
			and combat_loop.turn_gate.get_object() == self:
		combat_loop.turn_gate = Callable()
		# The brake is this director's too, and a loop that outlives it must not
		# keep braking for a turn nothing will ever open.
		if combat_loop.gpu_simulator != null:
			combat_loop.gpu_simulator.turn_brake_battle = -1


func _process(_delta: float) -> void:
	# Forwarded every frame rather than on the Tune edge, because the 1x/2x/4x
	# control and hold-to-skip write `playback_rate` directly and never go through
	# a slug. One float assignment.
	if combat_loop != null:
		combat_loop.playback_scale = playback_rate
		# The simulator is built by the host's `boot_battle`, which can land AFTER
		# the mount — so the arm in `_install_gate` may have had nothing to write
		# to. Re-applied here for the same reason the rate is: one int compare
		# against a setter that early-returns when it has not moved.
		_apply_brake()


# --- The cycle ---------------------------------------------------------------

func state() -> int:
	return _state


## The unit whose turn is open, or -1 when none is (RUNNING, or DEPLOYMENT).
func taker() -> int:
	return _taker


## The per-tick stop predicate installed on [member CombatLoop.turn_gate].
##
## Allocation-free by construction: it scans the three lean columns the loop
## already read this tick and builds nothing. The full [TurnQueue] ordering is paid ONCE,
## in `_open_turn`, on the tick it actually stops — not 60 times a second.
##
## THE SETTLED TEST — trip when someone is ready AND NO ready unit is mid-step.
## Logical position is the DESTINATION for the whole duration of a movement step
## (`stage_resolve.glsl`: "CPU updates position at START of movement, not END"), so
## a gate that froze the instant a meter crossed would routinely stop the world
## with the taker's sprite a tile short of the cell the camera, `get_current_cell`
## and `_unit_at_grid` all place it on — the turn opening on a tile that looks
## empty. `combat_active = false` then stops the ticks that would have carried the
## sprite in, so it sits there for the whole turn.
##
## It only terminates because the kernel BRAKES (see [method _apply_brake]): a
## ready unit finishes its step and starts no other. Without the brake a walker is
## never settled and this waits forever. Ordering is untouched — `_open_turn` still
## takes `TurnQueue.ready_now()[0]` — so this shifts turn TIMING by at most one
## step, never who is up.
##
## The dead-bit test is load-bearing, not defensive: the kernel stops advancing a
## dead unit's meter, so a unit that dies at or above FULL keeps that meter
## forever. Without the filter the gate would trip every tick while `ready_now`
## (which does filter) returned nothing, and the director would freeze and resume
## in a loop with no turn to open.
##
## Freezing happens INSIDE this call, synchronously, before the loop can run
## another tick. Reacting in `_process` instead would depend on node order —
## the host pumps the parent loop before a child director processes — which is a
## correctness argument that a scene rearrangement could silently break.
func _turn_gate(meters: PackedInt32Array, flags: PackedInt32Array,
		states: PackedInt32Array) -> bool:
	if _state != State.RUNNING:
		return false
	var n: int = mini(mini(meters.size(), flags.size()), states.size())
	var anyone_ready := false
	for i in range(n):
		if meters[i] < FULL or (flags[i] & GPUConstants.FLAG_DEAD_BIT) != 0:
			continue
		# TERM 1 — no ready unit is mid-step. A ready unit still crossing a tile
		# must not be frozen there: the freeze stops EVERY clock, so it would sit
		# between tiles for the whole turn. Quantified over ALL ready units and not
		# just the taker, because that is who it is FOR — the taker is covered by
		# term 2 in `_open_turn`, and a braked bystander was about to settle anyway.
		#
		# 🔴 GATED ON `stops_the_world`, WHICH IS NOT DEFENSIVE. The brake is armed
		# by the same flag, so under the walk's policy a ready unit walks forever and
		# this would block every announcement the walk ever makes — the turns would
		# not be late, they would never happen. A host that does not freeze has
		# nothing to land well.
		if stops_the_world and GPUConstants.is_movement_state(states[i]):
			return false
		anyone_ready = true
	if not anyone_ready:
		return false
	return _open_turn()


## The turn queue as the player reads it: one full round-robin deep, every living
## unit appearing at least once (design S6, ADR-0236). Pure arithmetic over the
## meters as they stand — no simulation, and correct only under the caveat
## [TurnQueue] states (Haste/Slow, deaths, reinforcements).
##
## It lives here rather than on the HUD because the REACH is this class's own:
## loop -> simulator -> this battle's slice -> [TurnQueue] rows is exactly what
## `_open_turn` already walks, and #895's rollout driver wants the same rows. A
## view that walked it itself would be a second copy of the director's plumbing,
## living in `ui3`.
##
## Empty while the battle does not exist yet. DEPLOYMENT has no GPU buffer to
## read (ADR-0242 dec. 2) — a real state, not an error, and the reason this
## returns `[]` rather than pushing a warning.
func forecast(max_entries: int = 512) -> Array:
	if combat_loop == null or combat_loop.gpu_simulator == null:
		return []
	return TurnQueue.forecast(
		TurnQueue.from_unit_states(
			combat_loop.gpu_simulator.get_battle_unit_states(battle_id)),
		max_entries)


## Freeze and hand off to the first unit in turn order. Returns false (leaving the
## world running) when nobody is actually ready.
func _open_turn() -> bool:
	if combat_loop == null or combat_loop.gpu_simulator == null:
		return false
	var unit_states: Array = combat_loop.gpu_simulator.get_battle_unit_states(battle_id)
	var rows: Array = TurnQueue.from_unit_states(unit_states)
	var ready: Array = TurnQueue.ready_now(rows)
	if ready.is_empty():
		return false
	var row: Dictionary = ready[0]
	if not stops_the_world:
		return _spend_where_it_opens(row)
	var taker_index: int = int(row["index"])
	# TERM 2 — THE TAKER HAS NOT COMMITTED TO ANYTHING. This is what a turn is FOR:
	# the adjustment window and `GambitBattle._think_for` both rewrite the taker's
	# gambits while the turn is open, and a unit caught mid-ACTING or mid-charge
	# finishes the action it had already committed to — so the edit is accepted,
	# acknowledged, and silently not what the unit does next. IDLE is the only state
	# in which nothing is in flight, and it is exactly the state the kernel's brake
	# writes, so the gate tests the state the brake establishes rather than a second
	# idea of "settled".
	#
	# Alignment rides along for free: IDLE is not a movement state, so
	# `GPUVisualBridge` takes its NO_MOVE branch and snaps the sprite to
	# `world_position_at(cell)` — the reported bug, fixed as a consequence rather
	# than as its own rule.
	#
	# Refusing here rather than in the gate keeps the turn ORDER in one place. The
	# head is still `TurnQueue.ready_now()[0]` (meter desc, then team, then index);
	# this only makes its turn open LATER, never somebody else's open first. The
	# gate cannot make this test itself — it has the meter, flag and state columns
	# but not `team`, so it cannot break a meter tie the way `_before` does, and a
	# second copy of that ordering is the one thing `TurnQueue` says must not exist.
	#
	# Terminates because every state drains to IDLE: the movement states via the
	# brake, ACTING / AWAITING_IMPACT within a tick of their timer, SPELL_CHARGING
	# through ACTING, and DYING carries FLAG_DEAD so it never reaches here.
	if taker_index < 0 or taker_index >= unit_states.size():
		return false
	if int(unit_states[taker_index].get("state", -1)) != GPUConstants.LOGICAL_ACTIVITY_IDLE:
		return false
	_taker = taker_index
	# BEFORE the freeze and before any edit: this is the image `cancel` returns to,
	# and it is taken while the meter is still UNSPENT, which is what makes cancel
	# re-open the same turn rather than eat it.
	_snapshot = combat_loop.gpu_simulator.snapshot_battle(battle_id)
	_state = State.TURN_OPEN
	# The one freeze authority (ADR-0037 dec. 2). Set before the signal so a
	# subscriber that commits synchronously sees a coherent director.
	combat_loop.combat_active = false
	turn_opened.emit(_taker, int(row["team"]))
	return true


## Spend a turn without freezing anything — the [member stops_the_world] `false`
## policy. Always returns `false`: the gate's contract is that `true` BREAKS the
## frame's tick loop, and nothing here is holding the world, so the drain carries on
## through the same tick it was announced on and the turn costs zero ticks.
##
## Announces FIRST and consumes after, so a subscriber that reads [method forecast]
## on `turn_opened` — the HUD does — sees the picture WAIT mode shows it: the taker
## at the head of the queue, with its meter still unspent. Consuming first would put
## the announced unit LAST in its own announcement.
##
## No snapshot and no state change: `state()` stays RUNNING, which is the invariant
## `commit` spells out (RUNNING iff the world is live) and is true here throughout —
## the world never stopped. `_taker` is set across the two emits only, because for
## the length of the announcement the answer to "whose turn is this" is his.
func _spend_where_it_opens(row: Dictionary) -> bool:
	var spent: int = int(row["index"])
	_taker = spent
	turn_opened.emit(spent, int(row["team"]))
	combat_loop.gpu_simulator.consume_turn(battle_id, spent)
	turn_committed.emit(spent)
	_taker = -1
	return false


## Spend the open turn and carry on. In DEPLOYMENT this starts the battle instead.
##
## Committing with no edits IS "wait" — there is no separate pass verb, because
## spending a turn having changed nothing is exactly what waiting is.
func commit() -> bool:
	if _state == State.DEPLOYMENT:
		_state = State.RUNNING
		_resume()
		return true

	if _state != State.TURN_OPEN:
		return false
	var spent: int = _taker
	combat_loop.gpu_simulator.consume_turn(battle_id, spent)
	_snapshot = {}
	_taker = -1
	# `_state` deliberately stays TURN_OPEN across the emit and the drain below.
	# THE INVARIANT IS `state() == RUNNING` IFF THE WORLD IS LIVE, and the world is
	# still frozen here — flipping to RUNNING first would hand every
	# `turn_committed` subscriber one frame of "running, but combat_active is
	# false", which is the kind of undocumented transient #894 and #897 would
	# each discover the hard way. What a subscriber sees instead is coherent:
	# frozen, with no taker yet.
	turn_committed.emit(spent)
	# Drain: two units can be ready at the same stop, and resuming the world for
	# zero ticks between them would be a distinction with no consequence in the sim
	# that every subscriber would still have to handle as a resume/refreeze pair.
	# RECOMPUTED, never cached — a cached ready list is a claim about a world a
	# `reconfigure_unit` just edited.
	if _open_turn():
		return true
	_state = State.RUNNING
	_resume()
	return true


## Throw the open turn's edits away and re-open the same turn.
##
## Cancel undoes the EDITS, not the turn. The snapshot predates `consume_turn`, so
## restoring puts the unspent meter back and the same unit is still ready — which
## is why this re-opens rather than resumes. A cancel that spent the turn would
## make Escape cost you a turn.
##
## Unavailable in DEPLOYMENT, which holds no snapshot: resetting placements is the
## deployment screen's business, over CPU-side units that are not in the GPU buffer
## yet.
func cancel() -> bool:
	if _state != State.TURN_OPEN:
		return false
	var undone: int = _taker
	combat_loop.gpu_simulator.restore_battle(battle_id, _snapshot)
	_snapshot = {}
	_taker = -1
	# Still TURN_OPEN across the emit, for the reason spelled out in `commit`.
	turn_cancelled.emit(undone)
	# Re-open rather than resume: the restore put the meter back, so this finds the
	# same taker and takes a fresh (identical) snapshot.
	if _open_turn():
		return true
	_state = State.RUNNING
	_resume()
	return true


## Open the deployment assignment: frozen, no taker, no meter gate (design S9).
## Mechanically a turn in a different mode — same signal, same commit — which is
## the whole point: the deployment screen is not new UI.
func open_deployment() -> void:
	_taker = -1
	_snapshot = {}
	_state = State.DEPLOYMENT
	if combat_loop != null:
		combat_loop.combat_active = false
	turn_opened.emit(-1, -1)


func _resume() -> void:
	if combat_loop != null:
		# Land the rate HERE and not only in `_process`: the rate you pick during a
		# turn is the rate the stretch that follows should play at, and a harness
		# that drives `tick()` by hand never renders a frame for `_process` to run
		# on. `_process` still forwards it so a mid-stretch scrub or hold-to-skip
		# takes effect without waiting for the next turn.
		combat_loop.playback_scale = playback_rate
		combat_loop.combat_active = true
	resumed.emit()
