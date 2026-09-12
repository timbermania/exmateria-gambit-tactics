class_name TurnQueue
extends RefCounted
## The TURN QUEUE — who acts next, and when (ADR-0236, design S6).
##
## Pure arithmetic over the GPU's TURN METER field: no RenderingDevice, no
## simulation, no nodes. Every unit gains `max(1, speed)` meter per tick and is
## READY at `TURN_METER_FULL`, so the whole queue is a closed-form projection of
## the current meters — which is exactly why the forecast can be shown one full
## round-robin deep without running the battle forward.
##
## It is wrong under Haste/Slow, deaths and reinforcements, the same caveat every
## turn-queue game carries: the projection assumes Speed and the living set hold.
##
## The tick arithmetic here MIRRORS `stage_compute.glsl`'s advance. If one moves,
## both move — `GPUTurnMeterTest` is the arm that fails when they disagree.


## A ready unit's meter has crossed this; the kernel stops accumulating there.
const FULL := GPUCombatPacker.TURN_METER_FULL


static func gain_per_tick(speed: int) -> int:
	"""Meter gained per tick. `max(1, ...)` mirrors the kernel: a Speed-0 unit
	would otherwise never act, which is not a slow unit but a non-terminating
	forecast."""
	return maxi(1, speed)


static func from_unit_states(states: Array) -> Array:
	"""Rows for this module, read off `GPUBatchSimulator.get_battle_unit_states`.

	One adapter, so the SNAPSHOT_FIELDS key names appear in exactly one place and
	the rest of the module is a pure function of plain ints."""
	var rows: Array = []
	for i in range(states.size()):
		var s: Dictionary = states[i]
		rows.append({
			"index": i,
			"team": int(s.get("team", 0)),
			"speed": int(s.get("speed", 0)),
			"turn_meter": int(s.get("turn_meter", 0)),
			"alive": (int(s.get("flags", 0)) & GPUConstants.FLAG_DEAD_BIT) == 0,
		})
	return rows


static func ticks_until_ready(row: Dictionary) -> int:
	"""Whole ticks before this row reaches FULL; 0 if it is already ready."""
	var meter: int = int(row["turn_meter"])
	if meter >= FULL:
		return 0
	var gain: int = gain_per_tick(int(row["speed"]))
	return int(ceil(float(FULL - meter) / float(gain)))


static func ready_now(rows: Array) -> Array:
	"""The living rows already at FULL, in the order they take their turns.

	Ordered by meter DESCENDING first — a unit with more overshoot crossed the
	line earlier and has been waiting longer — then by team, then by unit index.
	The design fixes only the tie-break (team, then index) and fixes it for a
	reason: nothing here may be random, because the enemy AI replays these
	positions inside its rollouts and a queue that reshuffled would make two runs
	of the same candidate disagree."""
	var ready: Array = []
	for row in rows:
		if bool(row["alive"]) and int(row["turn_meter"]) >= FULL:
			ready.append(row)
	ready.sort_custom(_before)
	return ready


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["turn_meter"]) != int(b["turn_meter"]):
		return int(a["turn_meter"]) > int(b["turn_meter"])
	if int(a["team"]) != int(b["team"]):
		return int(a["team"]) < int(b["team"])
	return int(a["index"]) < int(b["index"])


static func forecast(rows: Array, max_entries: int = 512) -> Array:
	"""The turn queue, ONE FULL ROUND-ROBIN DEEP (design S6).

	Extends until every living unit has appeared at least once, so the queue
	self-scales: a slow unit's long wait is visible as the pile of faster turns
	in front of it rather than implied by a bar. Entries are
	`{index, team, ticks_from_now, turn_meter}` in turn order, `ticks_from_now`
	counting from the caller's present.

	`max_entries` is a non-termination belt, not a display policy. If it bites,
	the shortfall is a `push_warning` naming the units that never appeared — a
	silently short queue would read as "that unit acts soon" when the truth is
	the opposite.

	The belt counts ITERATIONS, not emitted entries. A rule change that made some
	unit gain zero meter per tick would spin here forever while emitting nothing,
	so an entry-counted belt would never fire; a hang is a worse verdict than a
	short queue, because nothing names it."""
	var work: Array = []
	for row in rows:
		if bool(row["alive"]):
			work.append({
				"index": int(row["index"]),
				"team": int(row["team"]),
				"speed": int(row["speed"]),
				"turn_meter": int(row["turn_meter"]),
				"alive": true,
			})
	if work.is_empty():
		return []

	var out: Array = []
	var seen := {}
	var elapsed: int = 0
	# Two iterations per entry at worst: one to jump the clock, one to emit.
	var budget: int = max_entries * 2
	while seen.size() < work.size() and out.size() < max_entries and budget > 0:
		budget -= 1
		var ready: Array = ready_now(work)
		if ready.is_empty():
			# Nobody is ready: jump straight to the first tick on which somebody
			# is, rather than stepping one tick at a time. Closed form, so the
			# forecast costs the same whether the next turn is 1 tick or 90 away.
			var wait: int = ticks_until_ready(work[0])
			for row in work:
				wait = mini(wait, ticks_until_ready(row))
			for row in work:
				row["turn_meter"] = int(row["turn_meter"]) + wait * gain_per_tick(int(row["speed"]))
			elapsed += wait
			continue
		var taker: Dictionary = ready[0]
		out.append({
			"index": int(taker["index"]),
			"team": int(taker["team"]),
			"ticks_from_now": elapsed,
			"turn_meter": int(taker["turn_meter"]),
		})
		seen[int(taker["index"])] = true
		taker["turn_meter"] = int(taker["turn_meter"]) - FULL

	if seen.size() < work.size():
		var missing: Array = []
		for row in work:
			if not seen.has(int(row["index"])):
				missing.append(int(row["index"]))
		push_warning("TurnQueue.forecast stopped at %d entries before covering units %s — the queue shown is SHORT" % [
			out.size(), str(missing)])
	return out
