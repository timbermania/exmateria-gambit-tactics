extends RefCounted
## The FEDS sound-lane DRAG plan (ADR-0085 amendment 2026-08-19b §2/§3) — the pure
## re-timing decision behind *a drag may re-time silence; it may never move an authored
## event's firing tick.*
##
## Given a track's CELLS (its spans and its bare zero-tick opcodes, in event order), the
## cell being dragged and the desired tick delta, it returns the tick counts the channel
## should write. No `EffectData`, no `FedsBank`, no scene, no fold oracle — `SoundDefChannel`
## only applies what this returns, which is what makes the clean-run cascade, the three walls
## and the insert-or-splice arithmetic guardable without a paint. The colour lanes' shape,
## transferred to a lane whose currency is a REST rather than an invisible spacer.
##
## THE MODEL (§2). Two of the three gestures touch no note bytes at all:
##
##   move          leading rest `a+k`, trailing rest `b-k`      no note byte
##   resize        one flanking rest `b∓Δ`                      the duration byte
##
## so the lane's editable number is **a rest's tick count** — ADR-0095's *"a boundary is one
## stored number"* landing here with nothing invented. Every gesture holds the track's clock
## still: whatever one side spends, the other side absorbs.
##
## THE THREE WALLS (§3). A **rest** is the currency: consumable, cascading to the far edge of
## a run of consecutive rests. A **note** is a wall — clamped against, never shortened by
## somebody else's drag, never deleted. A bare **zero-tick opcode is a wall too**, and that is
## the one ADR-0095's colour lanes do not have: rewriting a rest's `pp` ahead of an
## `Instrument` changes *when that instrument changes*, a silent re-timing of work the author
## never touched. So a run is only ever measured through rests with NO opcode between them
## (`_run` stops on the first non-rest cell), and a deposit is always written **byte-adjacent
## to the note**, ahead of any opcode on that side — `rest(a) Instrument note(d)` grown on the
## left becomes `rest(a) Instrument rest(k) note(d)`, and the Instrument still fires at `a`.
##
## One place this lane is strictly better off than ADR-0095's: a rest consumed to zero is
## SPLICED OUT (`rests[i] == 0`), so adjacency is expressible. `ColorLowering` cannot encode a
## zero-length span, which is why the colour lanes leave a 1-frame spacer no verb can remove.
##
## Clamped, never refused, on the way to a wall — the drag keeps following the cursor and
## drags back out again (ADR-0095 §4's pristine re-plan makes that self-inverse while held).
## Refused OUTRIGHT — with a reason, never silently reshaped — only where §8's parks bite: a
## move on a span carrying an interior opcode (the opcode would travel with the note, a claim
## about firing ticks the law does not license), and a resize of a MULTI-SEGMENT span (which
## segment absorbs the delta is undesigned, and 1279 of 1619 such spans carry an interior
## opcode, so guessing would re-time a fifth of the corpus).
##
## No `class_name` (ADR-0004) — preloaded by path.

## `80 pp` carries one param byte; a deposit larger than this is written as a RUN of rests
## (`_encode_rests` in the channel), which is more silence spelled differently, never a clamp.
const MAX_REST_TICKS := 255
## A note's explicit-duration form (`vv 00 tt`) carries one duration byte; the table form
## tops out at 192. Below 1 a note sounds nothing, which is the un-rest's refusal.
const MAX_NOTE_TICKS := 255
const MIN_NOTE_TICKS := 1

const MOVE := "move"
const RESIZE_RIGHT := "resize_right"
const RESIZE_LEFT := "resize_left"


## PURE: fold a track's spans + its bare opcodes into the CELL row the plan reasons over.
##
## A cell is one of three kinds, in event order:
##   note    a sounding span (possibly several segments, possibly with interior opcodes)
##   rest    silence — always exactly ONE segment (`fold_spans` gives a `0x80` no way to be
##           extended), which is why a rest is the atom the arithmetic spends
##   opcode  a bare zero-tick opcode OUTSIDE any span — a wall (§3)
##
## An opcode INSIDE a span (between its first and last segment) is not a cell: it belongs to
## the note, and it is what `interior_opcode` reports so a move can refuse the span (§8).
## `spans` is `FedsPairModel.fold_spans(events)`; `event_count` is `events.size()`.
static func build_cells(spans: Array, event_count: int) -> Array:
	var head: Dictionary = {}      # head event index -> span
	var owned: Dictionary = {}     # every event index a span's extent covers
	for sp in spans:
		var segs: Array = sp["segments"]
		head[int(sp["head_index"])] = sp
		for ei in range(int(segs[0]), int(segs[segs.size() - 1]) + 1):
			owned[ei] = true
	var cells: Array = []
	for ei in range(event_count):
		if head.has(ei):
			var sp: Dictionary = head[ei]
			var segs: Array = sp["segments"]
			var last: int = int(segs[segs.size() - 1])
			cells.append({
				"kind": str(sp["kind"]),
				"ticks": int(sp["total_ticks"]),
				"head_index": ei,
				"last_index": last,
				"segments": segs.duplicate(),
				# More events inside the span's extent than it has segments = an opcode
				# fires INSIDE the note. 1600 of 1619 fermata spans carry one.
				"interior_opcode": (last - ei + 1) > segs.size(),
			})
		elif not owned.has(ei):
			cells.append({
				"kind": "opcode", "ticks": 0, "head_index": ei, "last_index": ei,
				"segments": [ei], "interior_opcode": false,
			})
	return cells


## Which cell is headed by event `head_index`, or -1. The drag's address is the span head's
## byte boundary (§5), exactly as the un-rest's and the paint's is.
static func cell_of(cells: Array, head_index: int) -> int:
	for i in range(cells.size()):
		if int(cells[i].get("head_index", -1)) == head_index:
			return i
	return -1


## How many ticks of CURRENCY sit on one side of `cell_index` — the run of consecutive rests
## with no opcode between them (`dir` -1 = left, +1 = right). This is what a grip is drawn
## from: a note walled on both sides has none, which is honest (95.2% of the corpus) rather
## than a phantom handle over a drag that cannot move.
static func currency(cells: Array, cell_index: int, dir: int) -> int:
	var total: int = 0
	for c in _run(cells, cell_index, dir):
		total += int(c["ticks"])
	return total


## Plan one gesture. `delta` is in TICKS and signed the way the picture moves:
##   move           + later, - earlier      (the span translates; no note byte is written)
##   resize_right   + longer, - shorter     (the span's END moves; the start sits still)
##   resize_left    - longer, + shorter     (the span's START moves; the end sits still)
##
## Returns
##   {ok, reason, delta, rests, insert_before, insert_ticks, note_index, note_ticks}
##   ok             false = REFUSED (a §8 park); `reason` says which, and nothing is written
##   delta          the ACHIEVED delta after clamping — 0 means the drag had no currency
##   rests          {event index -> its new tick count}; 0 = the rest is spliced out
##   insert_before  event index a NEW rest goes immediately before (-1 = none); may be
##                  `event_count`, meaning "after the last event"
##   note_index     the note event whose duration changes (-1 for a move), `note_ticks` its
##                  new tick count
static func plan(cells: Array, cell_index: int, gesture: String, delta: int) -> Dictionary:
	var out: Dictionary = {
		"ok": false, "reason": "", "delta": 0, "rests": {},
		"insert_before": -1, "insert_ticks": 0, "note_index": -1, "note_ticks": -1,
	}
	if cell_index < 0 or cell_index >= cells.size():
		out["reason"] = "cell %d is not in this track" % cell_index
		return out
	var cell: Dictionary = cells[cell_index]
	if str(cell.get("kind", "")) != "note":
		out["reason"] = ("only a sounding span drags — a rest is the CURRENCY a drag spends, "
				+ "and the verb that puts a note inside one is the paint")
		return out
	var segments: Array = cell.get("segments", [])
	if gesture == MOVE:
		if bool(cell.get("interior_opcode", false)):
			out["reason"] = ("this span fires an opcode INSIDE it, which a move would carry "
					+ "along with the note — probably right, but a claim about firing ticks "
					+ "the law does not license, so it is parked (ADR-0085 19b §8)")
			return out
	elif gesture == RESIZE_RIGHT or gesture == RESIZE_LEFT:
		if segments.size() > 1:
			out["reason"] = ("this span is %d segments — which one absorbs a length delta is "
					+ "undesigned (ADR-0085 18c §7 / 19b §8), so a resize refuses it "
					+ "explicitly rather than guessing") % segments.size()
			return out
	else:
		out["reason"] = "unknown gesture '%s'" % gesture
		return out

	var left: Array = _run(cells, cell_index, -1)
	var right: Array = _run(cells, cell_index, 1)
	var ticks: int = int(cell["ticks"])
	var amount: int = absi(delta)
	var consume: Array = []
	var spends: bool = false     # does this direction have to BUY its ticks from a run?
	var deposit: int = 0         # -1 = into the left run, +1 = into the right, 0 = none
	var note_sign: int = 0       # what the note's own duration does
	match gesture:
		MOVE:
			# The whole span translates: one side pays, the other absorbs. No note byte.
			spends = true
			if delta > 0:
				consume = right
				deposit = -1
			elif delta < 0:
				consume = left
				deposit = 1
		RESIZE_RIGHT:
			if delta > 0:
				# Growing the end EATS the rest beside it — currency.
				spends = true
				consume = right
				note_sign = 1
			elif delta < 0:
				# Shrinking MAKES silence: free, and the flanking rest absorbs it.
				deposit = 1
				note_sign = -1
		RESIZE_LEFT:
			if delta < 0:
				spends = true
				consume = left
				note_sign = 1
			elif delta > 0:
				deposit = -1
				note_sign = -1

	if spends:
		var pool: int = 0
		for c in consume:
			pool += int(c["ticks"])
		amount = mini(amount, pool)
	if note_sign > 0:
		amount = mini(amount, MAX_NOTE_TICKS - ticks)
	elif note_sign < 0:
		amount = mini(amount, ticks - MIN_NOTE_TICKS)
	amount = maxi(amount, 0)

	out["ok"] = true
	out["delta"] = amount * signi(delta)
	if amount == 0:
		return out     # clamped flat against a wall — legal, and writes nothing

	# SPEND, nearest-first: the rest touching the note goes first, and the cascade only
	# reaches the next one once this one is gone. A rest taken to zero is spliced out, which
	# is how two notes are made adjacent.
	var owed: int = amount
	for c in consume:
		if owed <= 0:
			break
		var have: int = int(c["ticks"])
		var take: int = mini(have, owed)
		out["rests"][int(c["head_index"])] = have - take
		owed -= take

	# ABSORB. Grow the rest already touching the note on that side, or — when the thing
	# touching it is an opcode or the track edge — INSERT one byte-adjacent to the note, so
	# no opcode's firing tick moves (§3).
	if deposit != 0:
		var side: Array = left if deposit < 0 else right
		if side.is_empty():
			out["insert_before"] = int(cell["head_index"]) if deposit < 0 \
					else int(cell["last_index"]) + 1
			out["insert_ticks"] = amount
		else:
			var near: Dictionary = side[0]
			out["rests"][int(near["head_index"])] = int(near["ticks"]) + amount

	if note_sign != 0:
		out["note_index"] = int(cell["head_index"])
		out["note_ticks"] = ticks + note_sign * amount
	return out


## The run of consecutive REST cells starting immediately `dir`-ward of `cell_index`, nearest
## first. It stops on the first note AND on the first bare opcode — §3's third wall, the one
## the colour lanes do not have.
static func _run(cells: Array, cell_index: int, dir: int) -> Array:
	var out: Array = []
	var j: int = cell_index + dir
	while j >= 0 and j < cells.size() and str(cells[j].get("kind", "")) == "rest":
		out.append(cells[j])
		j += dir
	return out
