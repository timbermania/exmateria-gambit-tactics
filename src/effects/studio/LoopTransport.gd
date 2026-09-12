extends RefCounted
## Pure bounce-transport state machine for the Effect Studio's region loop (ADR-0090).
##
## Given the loop `[start, end]` span (inclusive), the loop `mode`, the current
## direction `dir`, and the current frame `cur`, `step()` returns the NEXT
## `{frame, dir, done}` — one frame's worth of automatic transport. The page drives
## this once per 30 Hz × speed accumulator tick and `studio_seek`s the result.
##
## The machine is where the turnaround off-by-one lives, so it is pure and tested in
## isolation (LoopTransportTest). It owns NO clock, NO host, NO speed — those are the
## page's. Direction reset-on-Play, seek-to-start-if-outside, and the silent-reverse
## seek path are the page's concern; this only computes the next frame.
##
## Turnaround is **reflect-without-repeat**: each endpoint is shown exactly once per
## pass (… end-1, end, end-1 … / … start+1, start, start+1 …), never repeated — a
## repeated endpoint reads as a 1-frame stutter (CONTEXT "Loop mode").

const MODE_OFF: int = 0
const MODE_FORWARD: int = 1
const MODE_PINGPONG: int = 2

const DIR_FWD: int = 1
const DIR_BACK: int = -1


## Advance one frame of automatic transport. Returns
##   { "frame": int, "dir": int, "done": bool }
## `done` is true only in MODE_OFF once the playhead reaches `end` (the page then
## halts); Forward/Ping-pong loop forever, so they never report done.
static func step(start: int, end: int, mode: int, dir: int, cur: int) -> Dictionary:
	# Degenerate span (below the min length of 2): nothing to loop — hold in place.
	if end <= start:
		return {"frame": start, "dir": DIR_FWD, "done": mode == MODE_OFF}

	match mode:
		MODE_OFF:
			if cur >= end:
				return {"frame": end, "dir": DIR_FWD, "done": true}
			return {"frame": cur + 1, "dir": DIR_FWD, "done": false}

		MODE_FORWARD:
			# Wrap end -> start; end is reached as cur+1 and shown once before the wrap.
			if cur >= end:
				return {"frame": start, "dir": DIR_FWD, "done": false}
			return {"frame": cur + 1, "dir": DIR_FWD, "done": false}

		MODE_PINGPONG:
			if dir == DIR_FWD:
				if cur >= end:
					# Reflect off the far end WITHOUT repeating it.
					return {"frame": end - 1, "dir": DIR_BACK, "done": false}
				return {"frame": cur + 1, "dir": DIR_FWD, "done": false}
			else:
				if cur <= start:
					# Reflect off the near end without repeating it.
					return {"frame": start + 1, "dir": DIR_FWD, "done": false}
				return {"frame": cur - 1, "dir": DIR_BACK, "done": false}

	# Unknown mode: inert.
	return {"frame": cur, "dir": dir, "done": true}
