extends RefCounted
## The PURE planner for the colour Move (ADR-0101 decisions 3-7) — palette and screen share it,
## exactly as they share `ColorLowering`, because both store the identical length encoding and a
## forked rule is how the last three bugs in this area happened.
##
## THE SHAPE. A colour lane is FULLY TILED: every played keyframe owns a tile, and "empty space"
## is a HOLD — a keyframe the fold declares disable-equivalent (`SpacerVerdicts`), which the
## painter hides. So a Move has no gaps to slide through; it trades frames between the two
## maximal HOLD RUNS on either side of the span. One clamped delta shifts both of the span's
## boundaries, its width is preserved, the run in front gives up `d` frames and the run behind
## takes them — and because the two runs' combined length is conserved, everything outside them
## stays pinned at its absolute frame. A span wedged between two drawn tweens is refused, in
## `plan_move`'s existing vocabulary: a move must never change what another span renders.
##
## THE CURRENCY. Storable lengths are `1` and the multiples of 8 — nothing between. A region of
## length `L = 8a + b` therefore needs exactly `b` one-frame keyframes plus one carrying the
## `8a`, and a channel has only `33 − max_keyframe` free slots. So a sub-8 slide COSTS SLOTS
## (8 of them for any non-multiple-of-8 delta over two multiple-of-8 runs), a channel that
## cannot pay degrades to 8-frame granularity rather than refusing (decision 4), and a run
## dragged to zero length is DELETED, recovering its slots (decision 7).
##
## Everything here is arithmetic over two plain arrays — `durations` and `holds` — so the rule
## is guarded without an EffectData, a fold, or a paint. The channels supply the two arrays
## (the fold-derived hold verdicts differ per kind: palette reads `kf.enabled`, screen reads
## `is_author_disabled`) and execute the returned splice with their own keyframe copier.
##
## No `class_name` (ADR-0004) — preloaded by path.

const _Lowering = preload("res://src/effects/studio/ColorLowering.gd")

## Free slots at or above which the drag is FRAME-granular (ADR-0101 decision 4). Below it the
## drag falls back to multiple-of-8 deltas, which cost nothing. 8 is the worst-case price of a
## non-multiple-of-8 slide, so the gate is the guarantee, not a guess — and it is a property of
## the CHANNEL, not of the current delta, so the granularity cannot flicker mid-gesture
## (decision 5: the tell is the handle's own motion).
const FINE_SLOT_BUDGET := 8


## Plan the slide of played span `n` by `delta` frames.
##
##   `durations`  per-keyframe played lengths, in index order (at least `holds.size()` long)
##   `holds`      per-keyframe "this tile is hidden empty space", over the PLAYED window only
##   `free_slots` `33 − max_keyframe`
##
## An EMPTY run on either side is grown from nothing, unconditionally — there is no licence to
## ask for. Decision 6, narrowed: where a run HAS an adjacent hold the padding copies it, and
## where it has none the padding is MINTED — an ENABLED Δ0 IDENTITY, which lowers to "current +
## 0" and is therefore a per-frame no-op whatever it sits next to. The old fallback copied the
## keyframe at the insertion point, which folds inert only ~92% of the time — hence the licence,
## hence `_manufactured_hold_is_inert`'s trial insert, hence a planner that read a fold its own
## edit invalidated. A minted pad has no bytes to be wrong about, so all of it goes.
##
## Returns `{ok, reason, delta, granularity, cost, left, right}`. `left` / `right` are splices:
## `{from, to, seq}` replaces the half-open index range `[from, to)` of the PRE-EDIT array with
## `seq`, each entry `{src, dur}` = "a copy of pre-edit keyframe `src`, `dur` frames long" —
## unless it carries `pad: true`, which means "a freshly MINTED `dur`-frame pad" and `src` is
## only the insertion address. Apply `right` FIRST so `left`'s indices stay valid.
## Pure — nothing is mutated.
static func plan(durations: Array, holds: Array, n: int, delta: int,
		free_slots: int) -> Dictionary:
	var last: int = holds.size()
	if n < 0 or n >= last:
		return _refused("no played span at index %d" % n)
	if bool(holds[n]):
		return _refused("a hold is empty space, not a movable span")

	var bounds := hold_run_bounds(holds, n)
	var p: int = int(bounds["p"])
	var q: int = int(bounds["q"])
	var left_count: int = n - p
	var right_count: int = q - n - 1
	var lead: int = _span(durations, p, n)          # frames of hold IN FRONT of the span
	var trail: int = _span(durations, n + 1, q)     # frames of hold BEHIND it

	# Every side can GROW: it either has an adjacent hold to copy or it mints a pad. So the only
	# thing that can refuse a Move is having no FRAMES to trade — a span with a drawn tween hard
	# against it on both sides. (This used to be gated on a per-side manufacture licence, which
	# is what stranded a span slid onto played index 0: its only candidate padding was a copy of
	# ITSELF placed before it, and the fold refused that. Minting has no such problem.)
	var right_room: int = trail
	var left_room: int = lead
	if left_room == 0 and right_room == 0:
		return _refused("wedged: neither neighbour is a hold")

	var wanted: int = clampi(delta, -left_room, right_room)
	var fine: bool = free_slots >= FINE_SLOT_BUDGET
	var coarse: int = _snap_toward_zero(wanted, _Lowering.STEP)
	# Decision 4's two-tier degrade, in preference order, with every rung PRICED. `fine` is a
	# WORST-CASE bound (8 slots is the most a sub-8 slide can cost), never a price — so using
	# it to decide whether the exact delta is even encoded made Move ONE-WAY:
	#
	#   A fine slide SPENDS the slots that licensed it. The author releases, grabs again, and
	#   `EffectEditSession.begin_move` re-reads the budget — now under 8 — so the return trip
	#   plans coarse, and the frame the span came from is not a multiple of 8 away. The span
	#   sits still until the cursor nears the next eighth and then jumps PAST where it started.
	#   Measured on shipped data: E003 for_each/target #1 and E023 phase1/affected_units #2
	#   slide −3 for +7/+8 slots, dropping 14/15 free to 7 — and the return's own cost is
	#   −7/−8, because it re-merges the very padding the out trip inserted. Trivially
	#   affordable, and never offered.
	#
	# So the exact delta is priced first, and a broke channel takes it when it costs NOTHING —
	# which is exactly the reversal of a slide the author just made. A slide that would SPEND
	# still degrades to eights on a broke channel, so decision 4's guarantee ("the author
	# always gets a move — sometimes a coarser one") and decision 5's tell both stand for the
	# whole population they were written about.
	for d in [wanted, coarse, 0]:
		var built := _encode(durations, p, n, q, int(d), lead, trail,
			left_count, right_count)
		var cost: int = int(built["cost"])
		if cost > free_slots:
			continue                       # unaffordable outright — try the next rung
		if int(d) != coarse and not fine and cost > 0:
			continue                       # broke: 8-grained unless the slide is free
		built["ok"] = true
		built["reason"] = ""
		built["delta"] = int(d)
		built["granularity"] = 1 if int(d) == wanted else _Lowering.STEP
		return built
	return _refused("no affordable slide (%d free slots)" % free_slots)


## The PLAN half of a Move without the splice — "how far would this slide actually go, and at
## what granularity", answered from the gesture's own context and touching no keyframe.
##
## This is what a STRUCTURE-FREE drag asks every motion (ADR-0089 Drag preview, generalised from
## particle to the colour kinds). The drag draws the span at `start + delta` and the channel is
## not written until release, so the only thing a motion needs from the model is the number —
## and the number has to be the PLANNER'S, never the cursor's, or the preview would promise a
## landing release does not honour. `EffectEditSession` reports it to the page and commits the
## same delta once, on release, through the ordinary `plan` + `apply` pair.
##
## Takes the whole `move_context` because the two colour kinds' contexts are already identical
## in shape — which is why this lives here and not forked into PaletteChannel and ScreenChannel
## beside their two verbatim `move_span`s. Returns `{}` for a refused or clamped-to-zero slide
## (a wedged span, an empty context): "no slide", which a caller draws as "at home".
static func preview(ctx: Dictionary, n: int, delta: int) -> Dictionary:
	if ctx.is_empty():
		return {}
	var p: Dictionary = plan(ctx["durations"], ctx["holds"], n, delta, int(ctx["free_slots"]))
	if not p.get("ok", false) or int(p["delta"]) == 0:
		return {}
	return {
		"delta": int(p["delta"]),
		"granularity": int(p["granularity"]),
		"cost": int(p["cost"]),
	}


## The maximal HOLD RUNS bracketing played span `n`: `p` is the first index of the run in front
## (== n when the previous tile is drawn), `q` the index just past the run behind (== n+1 when
## the next tile is drawn). The unit decision 7 collapses is the RUN, not the keyframe — a run
## of k holds may shrink to k frames and then vanish entirely.
static func hold_run_bounds(holds: Array, n: int) -> Dictionary:
	var p: int = n
	while p > 0 and bool(holds[p - 1]):
		p -= 1
	var q: int = n + 1
	while q < holds.size() and bool(holds[q]):
		q += 1
	return {"p": p, "q": q}


## Execute a plan's two splices against a live channel. `dup` copies one keyframe, `set_dur`
## writes a length onto a copy, `mint_pad` builds a fresh INERT pad of a given length — all
## three per-kind, so they arrive as Callables and this stays the one place the ORDER is right:
## every copy is taken from the PRE-EDIT array, and the RIGHT splice runs first so the left
## one's indices are still the ones the plan was made against.
##
## `mint_pad` is a SECOND factory rather than a flag on `dup` because the two shapes answer
## different questions: `dup` keeps a run byte-identical to the hold it extends (what shipped
## data looks like), `mint_pad` invents empty space where there is no hold to extend at all.
static func apply(ch, plan_result: Dictionary, dup: Callable, set_dur: Callable,
		mint_pad: Callable) -> void:
	_splice(ch, plan_result["right"], dup, set_dur, mint_pad)
	_splice(ch, plan_result["left"], dup, set_dur, mint_pad)


## Net slot cost of a plan (positive = slots spent, negative = slots recovered by a collapse).
static func cost_of(plan_result: Dictionary) -> int:
	return int(plan_result.get("cost", 0))


# --- internals ---------------------------------------------------------------


## Build both splices for one delta and price them. `lead + trail` is invariant, so the two new
## region lengths always sum to the old pair — which is precisely why everything downstream
## stays pinned.
static func _encode(durations: Array, p: int, n: int, q: int, d: int,
		lead: int, trail: int, left_count: int, right_count: int) -> Dictionary:
	var left_seq := _seq_for(lead + d, p, n, p)
	var right_seq := _seq_for(trail - d, n + 1, q, n + 1)
	return {
		"left": {"from": p, "to": n, "seq": left_seq},
		"right": {"from": n + 1, "to": q, "seq": right_seq},
		"cost": left_seq.size() + right_seq.size() - left_count - right_count,
	}


## The MINIMAL keyframe sequence encoding a hold region of `length` frames, taken from the run's
## own keyframes `[from_i, to_i)` — decision 6: padding is a COPY of the adjacent hold, so the
## run stays byte-shaped like the shipped data it extends and the fold's verdict on it cannot
## change (a hold repeated is the same hold).
##
## An EMPTY run has no adjacent hold, so its padding is MINTED instead — every entry flagged
## `pad: true`, `src` degraded to the mere insertion address. That is decision 6's narrowing:
## the old fallback copied the keyframe at the insertion point, which is inert only ~92% of the
## time, so it needed a fold-measured licence and could still be refused. A minted pad is an
## ENABLED Δ0 identity — inert whatever it sits next to and however many of them there are, so
## there is nothing left to measure. The two channels supply the shape (`mint_pad` in `apply`);
## it is deliberately NOT a disabled null, which is the author's Add-stub shape — see
## `PaletteChannel._new_identity_keyframe`.
##
## `L = 8a + b` needs one keyframe carrying the `8a` (when a > 0) plus exactly `b` one-frame
## keyframes: any sum of multiples of 8 is a multiple of 8, so the `b` residual has no cheaper
## encoding. A length of 0 returns nothing — the run collapses and its slots come back.
static func _seq_for(length: int, from_i: int, to_i: int, insert_at: int) -> Array:
	if length <= 0:
		return []
	var sources: Array = []
	for i in range(from_i, to_i):
		sources.append(i)
	var mint: bool = sources.is_empty()
	if mint:
		sources.append(maxi(0, insert_at))
	var out: Array = []
	var whole: int = (length / _Lowering.STEP) * _Lowering.STEP
	var residual: int = length % _Lowering.STEP
	if whole > 0:
		out.append(_entry(sources[0], whole, mint))
	for k in range(residual):
		out.append(_entry(sources[mini(out.size(), sources.size() - 1)], 1, mint))
	return out


static func _entry(src: int, dur: int, mint: bool) -> Dictionary:
	var e := {"src": src, "dur": dur}
	if mint:
		e["pad"] = true
	return e


static func _splice(ch, region: Dictionary, dup: Callable, set_dur: Callable,
		mint_pad: Callable) -> void:
	var from_i: int = int(region["from"])
	var to_i: int = int(region["to"])
	var seq: Array = region["seq"]
	if from_i == to_i and seq.is_empty():
		return
	# Copy FIRST: `src` indexes the pre-edit array, which the removal below invalidates.
	var built: Array = []
	for e in seq:
		if bool(e.get("pad", false)):
			built.append(mint_pad.call(int(e["dur"])))    # nothing to copy — invent empty space
			continue
		var kf = dup.call(ch.keyframes[int(e["src"])])
		set_dur.call(kf, int(e["dur"]))
		built.append(kf)
	for k in range(to_i - 1, from_i - 1, -1):
		ch.keyframes.remove_at(k)
	for j in range(built.size()):
		ch.keyframes.insert(from_i + j, built[j])
	ch.max_keyframe = int(ch.max_keyframe) + built.size() - (to_i - from_i)


## Total played length of the half-open keyframe range [from_i, to_i).
static func _span(durations: Array, from_i: int, to_i: int) -> int:
	var total: int = 0
	for i in range(from_i, to_i):
		total += int(durations[i])
	return total


## `d` reduced to the nearest multiple of `step` no further from zero than itself.
static func _snap_toward_zero(d: int, step: int) -> int:
	return signi(d) * ((absi(d) / step) * step)


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "delta": 0, "granularity": _Lowering.STEP,
		"cost": 0, "left": {"from": 0, "to": 0, "seq": []},
		"right": {"from": 0, "to": 0, "seq": []}}
