extends RefCounted
## Pure frame-space math for the Effect Studio's loop region (ADR-0090).
##
## The loop region is an inclusive `[start, end]` span of frames, ephemeral studio
## state (never written to E###.BIN, cleared on effect load). It is created by an
## Alt+left-drag on the frames bar — two snapped frames handed to `from_frames`,
## which orders them and enforces the min length of 2 (a 2-frame `[f, f+1]` span, so
## a click without drag can't make a zero-length region). `effective` resolves what
## the transport actually loops: the region when one is set, else the whole score
## `0 .. stop_frame`. The empty dict `{}` is the "no region" sentinel.
##
## No axis, no host, no view — snapping (TimelineAxis.snap) and gesture plumbing are
## the frames bar's; this only reasons in frame integers, so it is tested in isolation.

## Order two frames into `{start, end}` and grow to the min length of 2.
static func from_frames(a: int, b: int) -> Dictionary:
	var start: int = mini(a, b)
	var end: int = maxi(a, b)
	if end - start < 1:
		end = start + 1  # min length 2 (inclusive [start, start+1])
	return {"start": start, "end": end}


## The span the transport actually loops: the region when set, else the whole score.
static func effective(region: Dictionary, stop_frame: int) -> Dictionary:
	if is_empty(region):
		return {"start": 0, "end": stop_frame}
	return {"start": int(region["start"]), "end": int(region["end"])}


## True when no region is set (the whole-score fallback applies).
static func is_empty(region: Dictionary) -> bool:
	return region == null or not region.has("start") or not region.has("end")
