extends RefCounted
## The pure search behind the WYSIWYG "target colour" screen-Blend authoring widget (#255).
##
## The mode-5 screen Blend param is a SIGNED byte applied DOUBLED (`start << 1`,
## ScreenSubsystem._push_phase_ops) — a bidirectional additive delta, not an absolute colour,
## so ±128 is not a colour chart. Rather than expose the raw param, the author picks the colour
## the backdrop TOP should BECOME at the parked frame; this solver back-solves the param by
## BRUTE-FORCING all 256 candidate raw bytes per channel through the REAL forward blend fold
## (supplied as an `eval` callback so the solver stays pure and the caller reuses the exact op
## the preview folds — no drift) and returns the raw bytes whose result lands closest to the
## target. Because it reuses the identical forward op, the chosen param is provably the best
## ACHIEVABLE and the parked preview always matches. Works for all 11 blend modes with no
## per-mode inversion.
##
## Not every target is reachable (mode + range + 0/255 clamping): additive can't darken past
## subtract's reach, etc. When unreachable, the NEAREST byte wins (min |result − target|) — the
## live preview then shows the true result, so the author sees the truth (the honest "nearest
## match" caveat). See the handoff and CONTEXT.md "Authoring model".


## Solve the screen-Blend param for a target top colour.
##
## `eval.call(r, g, b) -> Vector3` returns the resulting top colour (0-1 per channel) for the
## candidate raw bytes — the caller wires it to the live ScreenSubsystem fold at the parked
## frame (transiently overriding this tween's raw bytes), so it IS the forward blend the preview
## uses. `orig` = {r, g, b} the tween's current raw bytes; each channel is scanned independently
## while the OTHER two are held at `orig` (the doubled-additive/multiply Blend modes are
## channel-independent; the luma modes 6/7 that mix channels are never used by an in-window
## screen keyframe). `target` = the desired top colour as a Vector3 (0-1).
##
## Returns {r, g, b} raw bytes (0-255) minimizing per-channel |result − target|. Ties keep the
## LOWEST byte (the scan is ascending and only a STRICT improvement replaces the best), so the
## result is deterministic.
static func solve(eval: Callable, orig: Dictionary, target: Vector3) -> Dictionary:
	var best := {
		"r": int(orig.get("r", 0)),
		"g": int(orig.get("g", 0)),
		"b": int(orig.get("b", 0)),
	}
	# Channel key → the Vector3 axis its result is compared on.
	for entry in [["r", 0], ["g", 1], ["b", 2]]:
		var ch: String = entry[0]
		var axis: int = entry[1]
		var target_v: float = target[axis]
		var best_byte: int = int(orig.get(ch, 0))
		var best_err: float = INF
		for cand in range(256):
			# Hold the other two channels at their originals; vary only this one.
			var probe := Vector3.ZERO
			match ch:
				"r": probe = eval.call(cand, int(orig.get("g", 0)), int(orig.get("b", 0)))
				"g": probe = eval.call(int(orig.get("r", 0)), cand, int(orig.get("b", 0)))
				"b": probe = eval.call(int(orig.get("r", 0)), int(orig.get("g", 0)), cand)
			var err: float = absf(probe[axis] - target_v)
			if err < best_err:
				best_err = err
				best_byte = cand
		best[ch] = best_byte
	return best
