extends RefCounted
## WHERE AN OPCODE LANDS ON THE PARTICLE'S LIFE — the projection that makes the film strip
## an entry point for colour authoring (ADR-0089's colour-move amendment).
##
## The author's model, verbatim: *"every entry on the opcode level axis has a map on the
## frame level axis — so the frame level one is a superset. So maybe you can pick a colour
## keyframe in the frameset panel and that will add a keyframe onto the frame level axis.
## But then you could also do a non-frameset-level one directly on the frame level axis.
## Either way it's 1 ribbon at the frame level with 2 entry points."*
##
## That is right for 84% of colour emitters and breaks in one nameable way for the rest.
## Measured over all 401 corpus effects, 2622 colour-enabled emitters:
##
## | | emitters | share | does every opcode land on a life frame? |
## |---|---|---|---|
## | animation-driven (`Life = −1`) | 1370 | 52.3% | yes, exact 1:1 — life IS the animation |
## | authored, exactly one pass | 41 | 1.6% | yes, exact 1:1 |
## | parks on a terminal frame for the tail | 769 | 29.3% | yes, once — the last opcode owns a long tail (median 9 frames held, max 110) |
## | the animation LOOPS over life | 112 | 4.3% | yes, but many times (median 6 repeats, max 26) |
## | **the particle DIES mid-animation** | **324** | **12.4%** | **NO** — the tail opcodes never play (median 9 frames of animation never seen, p90 41, max 128) |
## | no animation | 6 | 0.2% | — |
##
## So the map is a partial function, and the 324 are not an edge case to swallow silently:
## those strip cells are real opcodes that this emitter's particles never live to reach.
## They answer -1 here and the strip greys them, which turns the hole into information.
##
## LOOPED OPCODES RESOLVE TO THEIR FIRST OCCURRENCE (author's decision, 2026-08-20). The
## other repeats are still reachable — by clicking the ribbon directly, which is what the
## second entry point is for. One click, one keyframe, at a position that does not depend
## on where the player happens to be parked.
##
## IT PROJECTS THE TRACE, NOT THE OPCODES. `SequenceTimeline.trace` has already walked the
## opcodes and carries `tick_start` and `is_terminal` per cell — so this cannot disagree
## with the strip about where a cell begins, because it is reading the strip's own answer.
## A second walk of `anim.opcodes` here would be a fourth copy of the `maxi(1, (d + 1) >> 1)`
## halving rule, which the corpus has already caught being wrong once.
##
## No `class_name` (ADR-0004); preloaded by path like the other effect-studio scripts.


## The life frame trace cell `i` maps to, or -1 when the particle never reaches it.
##
## The frame is the cell's `tick_start` — the tick its dwell BEGINS at, which for a
## zero-dwell cell (SET_OFFSET, LOOP) is the boundary it sits on. Deliberately not
## `pos_tick`: that is the LAST tick of the cell's colour window (ADR-0103's "piece"), and
## a keyframe placed there would recolour the cell's own final frame rather than the cell.
##
## Two ways to answer -1, and they are different facts:
##   * a STRICTLY EARLIER cell is terminal — `ParticleAnimator` parks on a `duration = 0`
##     frame (authored lifetime) or dies on it (animation-driven), so nothing after it ever
##     shows. Only 13 of 2428 corpus animations (0.5%) put their terminal anywhere but last,
##     so this arm is rare — but where it fires it is total, not partial.
##   * `tick_start >= life_n` — the particle is already dead. Looping cannot rescue it: a
##     loop restarts at tick 0, so the cell's next appearance is LATER, never earlier.
static func life_frame_of(trace: Array, cell_index: int, life_n: int) -> int:
	if cell_index < 0 or cell_index >= trace.size() or life_n <= 0:
		return -1
	for j in range(cell_index):
		var prev = trace[j]
		if prev is Dictionary and bool(prev.get("is_terminal", false)):
			return -1
	var cell = trace[cell_index]
	if not (cell is Dictionary):
		return -1
	var start: int = int(cell.get("tick_start", -1))
	if start < 0 or start >= life_n:
		return -1
	return start


## The whole projection in one pass — one entry per trace cell, -1 where unreachable.
## The strip wants all of them at once (every cell decides its own greying), and doing it
## per cell would re-scan the terminal prefix once per cell.
static func life_frames(trace: Array, life_n: int) -> Array:
	var out: Array = []
	var parked: bool = false
	for i in range(trace.size()):
		var cell = trace[i]
		if not (cell is Dictionary):
			out.append(-1)
			continue
		var start: int = int(cell.get("tick_start", -1))
		if parked or life_n <= 0 or start < 0 or start >= life_n:
			out.append(-1)
		else:
			out.append(start)
		if bool(cell.get("is_terminal", false)):
			parked = true
	return out


## How many of the trace's cells the particle never reaches — the count the strip states
## rather than leaving the author to notice greyed cells and guess why.
static func unreachable_count(trace: Array, life_n: int) -> int:
	var n: int = 0
	for f in life_frames(trace, life_n):
		if int(f) < 0:
			n += 1
	return n


## THE LIFE COLUMN — the particle's whole life told as the run of pictures it shows, one
## entry per RUN of consecutive life frames that hold the same trace cell:
## `{cell, start, ticks}`, covering `[0, life_n)` with no gaps and no overlaps.
##
## `life_frames` above answers "where does this OPCODE land", which is the right question
## for a strip laid out by opcode. The vertical colour column asks the opposite one —
## "which picture is showing at this AGE" — and the two are not inverses, because the
## animation is not a bijection onto the life:
##
##   * a TERMINAL frame (`duration = 0`) PARKS: `ParticleAnimator.tick` sets
##     `animation_held` and returns without advancing, so that one cell owns every
##     remaining life frame. 769 corpus emitters (29.3%) end this way, holding a median 9
##     frames and up to 110. `life_frames` cannot say that — it has one number per cell.
##   * an animation with no terminal frame LOOPS (`anim_time = 0` at the end), so a cell
##     RECURS. 112 emitters (4.3%) loop, a median 6 times and up to 26. `life_frames`
##     resolves those to the first occurrence by decision and the later passes had no
##     home at all; here each pass is its own row.
##   * a cell whose dwell is zero (LOOP, SET_OFFSET) holds no life frame, so it gets no
##     row. It is still in the trace and still has a picture; it just is not part of any
##     age.
##
## Row count is bounded by `life_n`, not by the opcode count times the repeats — every row
## consumes at least one life frame. Median 16 across the corpus, p95 40.
##
## KNOWN INACCURACY, inherited: for an ANIMATION-DRIVEN emitter whose terminal frame is not
## last, `EmitterLifeWindow` over-counts the window (it sums every FRAME opcode) and this
## will park on the terminal rather than end there. 13 of 2428 corpus animations (0.5%) put
## a terminal anywhere but last. The window is the thing to fix, not this walk.
static func life_rows(trace: Array, life_n: int) -> Array:
	var out: Array = []
	if life_n <= 0 or trace.is_empty():
		return out
	var f: int = 0
	var i: int = 0
	# Every iteration either emits a row (consuming >= 1 life frame), steps past a
	# zero-dwell cell, or wraps — so the walk terminates on its own; `_occupied_cells`
	# covers the one trace that could wrap forever. This is belt-and-braces, and it is
	# sized for the WORST case rather than the typical one: a short animation over a long
	# life replays, and each pass costs one iteration per cell plus a wrap. `life_n + 2n`
	# was too tight and cut a 20-pass loop off at 13.
	var guard: int = life_n * (trace.size() + 2) + 8
	while f < life_n and guard > 0:
		guard -= 1
		if i >= trace.size():
			if _occupied_cells(trace) == 0:
				break
			i = 0            # LOOP — only reached when no terminal frame stopped us
			continue
		var cell = trace[i]
		if not (cell is Dictionary) or int(cell.get("ticks", 0)) <= 0:
			i += 1
			continue
		var terminal: bool = bool(cell.get("is_terminal", false))
		# A terminal cell owns the REST of the life, not just its own dwell.
		var take: int = (life_n - f) if terminal else mini(int(cell["ticks"]), life_n - f)
		out.append({"cell": i, "start": f, "ticks": take})
		f += take
		if terminal:
			break
		i += 1
	return out


## How many trace cells occupy any time at all. Guards the loop-back above: an all-zero-dwell
## trace would otherwise wrap forever finding nothing to emit.
static func _occupied_cells(trace: Array) -> int:
	var n: int = 0
	for cell in trace:
		if cell is Dictionary and int(cell.get("ticks", 0)) > 0:
			n += 1
	return n


## The life column's rows for trace cell `i`, in order — every age at which that opcode's
## picture is on screen. One entry for 95%+ of cells; several for a looped animation.
## The strip's cell-to-row link, and the thing `life_frames` flattened to a single answer.
static func rows_of_cell(rows: Array, cell_index: int) -> Array:
	var out: Array = []
	for r in rows:
		if r is Dictionary and int(r.get("cell", -1)) == cell_index:
			out.append(r)
	return out
