extends RefCounted
## The PURE emitter-elapsed playhead → curve-index map (ADR-0089 amendment:
## "span-anchored playhead marker on emitter-elapsed curves"). An emitter-elapsed
## curve is sampled at `ActiveEmitter.elapsed_frames` (at spawn), so at playhead `P`
## a firing that started at `span.start` is at `elapsed = P − span.start` and the
## curve is read at index `elapsed % 160` — one frame, one point. This is the one
## non-negotiable: the marker sits EXACTLY where `EffectCurve.sample_by_frame(elapsed)`
## reads (its `frame % samples.size()`), so it can never lie about what the sim samples.
##
## This resolves geometry only (playhead + the firing's start/end); it enumerates no
## particles — unlike the particle-age clock, an emitter-elapsed read site depends only
## on the playhead and the firing's start. Out of the firing it clamps to the nearest
## curve edge and reports before/after (a marker that silently vanishes reads as a bug);
## a firing longer than 160 frames wraps the index and counts laps.
##
## Web/WASM-safe pure helper; no `class_name` (ADR-0004), preloaded by path.

const SAMPLE_COUNT: int = 160


## Resolve the marker for a firing spanning [span_start, span_end] at `playhead`.
## Returns `{present, index, lap, elapsed, raw_elapsed, frame, state}`:
##   index      — the curve sample the sim reads (`elapsed % count`), the marker's X.
##   lap        — completed wraps (`elapsed / count`); ≥ 1 on a firing over `count` frames.
##   elapsed    — frames since the firing started, CLAMPED to [0, duration].
##   raw_elapsed— the unclamped `playhead − span_start` (negative before the firing).
##   frame      — the absolute effect frame (`playhead`) — the tag's `fF` half.
##   state      — "before" | "in" | "after" (in is inclusive of both boundaries).
static func resolve(playhead: int, span_start: int, span_end: int,
		count: int = SAMPLE_COUNT) -> Dictionary:
	var raw_elapsed: int = playhead - span_start
	var duration: int = maxi(0, span_end - span_start)
	var state := "in"
	var elapsed := raw_elapsed
	if raw_elapsed < 0:
		state = "before"
		elapsed = 0
	elif raw_elapsed > duration:
		state = "after"
		elapsed = duration
	var index: int = (elapsed % count) if count > 0 else 0
	var lap: int = (elapsed / count) if count > 0 else 0
	return {"present": true, "index": index, "lap": lap, "elapsed": elapsed,
		"raw_elapsed": raw_elapsed, "frame": playhead, "state": state}


## The explicitly-absent marker: a browsed/drilled emitter with no governing firing
## (no concrete `span.start`) draws NO marker. `present` is false; the surfaces show a
## one-line "select this emitter's span" hint instead of a lying position.
static func absent() -> Dictionary:
	return {"present": false}
