extends RefCounted
## Curve ⇄ colour-keyframe fitting (ADR-0089 colour-keyframe amendment, decisions 5/6/8).
##
## A colour keyframe is a JOINT CURVE colour at a frame (CONTEXT.md "Colour keyframe").
## The keyframes are the authoring layer; the dense 160-sample curves stay the compiled
## artifact. This module is the bridge between them:
##   • `import_from_curves(cr,cg,cb[,life_n])` — fit joint keyframes to the emitter's 160
##     curve samples via Douglas-Peucker breakpoint detection. Exact for the common piecewise-
##     linear ROM curves; for genuinely curvy segments it reports `exact=false` and a
##     bounded `max_error` (the honest-quantization tell) instead of silently approximating.
##     `life_n` splits the budget at the dead zone — see `import_from_curves`.
##   • `compile_to_curves(keyframes)` — lerp the curve colour LINEARLY between keyframes and
##     write it out per channel.
##
## THE SPRITE TEXEL `S` IS GONE FROM BOTH DIRECTIONS (2026-08-21, ADR-0089 decision 4 amended
## a second time). It used to mux on import and inverse-mux on compile, so a keyframe stored
## the OUTPUT colour `T = S ⊙ curve` and the author picked in that space. The author could not
## reach the colours they wanted there: censused over 3213 colour emitters, 97.5% have no
## channel whose byte slider can even hold 255, because the slider's ceiling is `S.k`, not 1.
## Fitting and compiling in CURVE space costs nothing in fidelity — the round trip through
## `S ⊘ S` was the identity anyway — and it is the space the samples are actually stored in,
## so `max_error` is now quoted in the units the packer writes.
##
## No `class_name` (ADR-0004) — preloaded by path.

const ColourMux = preload("res://src/effects/studio/ColourMux.gd")

const SAMPLE_COUNT := 160
## Below this per-channel deviation (≈half an 8-bit step in curve space) a fit is "exact".
const EXACT_EPSILON := 0.5 / 255.0
## Never emit more than this many keyframes — a curvy curve is quantized to a budget with an
## honest max_error rather than degenerating to one keyframe per sample.
const MAX_KEYFRAMES := 24


## Fit joint colour keyframes to the emitter's dense curves.
## Returns { "keyframes": Array[{frame:int, color:Color}], "exact": bool, "max_error": float }.
## The keyframe colours ARE the curve triples; max_error is the largest residual (in curve
## space) between the fitted piecewise-linear interpolation and the true samples.
##
## `life_n` IS THE PARTICLE'S LIFE, AND IT SPLITS THE BUDGET (2026-08-21). Passing it changes
## nothing about WHICH samples are fitted — all 160 still are — only how the `MAX_KEYFRAMES`
## budget is shared out. One global Douglas-Peucker over 160 samples spends that budget
## wherever the curve deviates most, and for a ROM curve that is very often the DEAD ZONE:
## the ages past `life_n`, which the particle renderer never samples and the colour column
## neither draws nor lets you click (CONTEXT.md *Colour dead zone*). Measured over 2995 corpus
## colour emitters, the dead zone STARVED the live window — 566 of them (18.9%) were left with
## one keyframe or none inside the life, which is the whole of what the author sees, and the
## worst-case residual INSIDE the life (the only error that renders) was **0.774**: a colour
## three quarters of full scale away from what the curve actually does, in the region the
## picture comes from. E001 emitter 0 is the shape of it — a 10-frame life, and 22 of the 24
## keyframes spent on ages 116-159.
##
## So each region gets its own budget, sharing the boundary sample. That is deliberately NOT
## the other repair, refitting to `[0, life_n)` — CONTEXT.md's *Avoid* list rules that out and
## is right to: `compile_to_curves` writes all 160 samples back from the keyframes, so
## dropping the tail's would flatten real bytes to fix what looked like a drawing bug. Nothing
## is dropped here. The live window measures exactly as well as the truncating fit
## (max residual 0.774 → 0.133, p90 0.0036 → 0.0019) and the dead zone exactly as well as
## before (max 0.9725, unchanged), for a median keyframe count of 10 against 9.
##
## `MAX_KEYFRAMES` stays a PER-REGION bound rather than becoming a global one, which is what
## it always effectively was: it exists so a curvy stretch cannot degenerate to one keyframe
## per sample, and each region is still bounded by it. A shared budget is what let one region
## starve the other. The cost is a longer worst-case list (47, not 24), and it is paid in the
## dead zone where nothing draws it.
##
## Omitted (or outside `(1, SAMPLE_COUNT)`) it is one global fit — the pre-2026-08-21
## behaviour, for callers that have no emitter to resolve a life from.
static func import_from_curves(cr, cg, cb, life_n: int = -1) -> Dictionary:
	var samples: Array = []
	samples.resize(SAMPLE_COUNT)
	for f in range(SAMPLE_COUNT):
		samples[f] = _sample(cr, cg, cb, f)

	var kept := _fit_frames(samples, life_n)
	var keyframes: Array = []
	for f in kept:
		keyframes.append({"frame": f, "color": samples[f]})

	var max_error := _residual(samples, keyframes)
	return {
		"keyframes": keyframes,
		"exact": max_error <= EXACT_EPSILON,
		"max_error": max_error,
	}


## Compile joint colour keyframes down to three dense per-channel curves.
## Linear RGB lerp of the curve colour between bracketing keyframes, held flat before the
## first / after the last, clamped into the unit cube. Returns
## { "r": PackedFloat32Array, "g": .., "b": .. } of length `n`.
static func compile_to_curves(keyframes: Array, n: int = SAMPLE_COUNT) -> Dictionary:
	var r := PackedFloat32Array()
	var g := PackedFloat32Array()
	var b := PackedFloat32Array()
	r.resize(n)
	g.resize(n)
	b.resize(n)
	for f in range(n):
		var curve: Color = ColourMux.clamp_unit(_curve_at(keyframes, f))
		r[f] = curve.r
		g[f] = curve.g
		b[f] = curve.b
	return {"r": r, "g": g, "b": b}


## The interpolated CURVE colour at frame `f` (public seam: the colour a new keyframe
## inherits, and what the picker seeds from) — same maths compile_to_curves uses. It was
## `muxed_at`, and the rename is the whole amendment in one word: a stale caller using the
## old name fails loudly rather than reading an output colour as a curve.
static func curve_at(keyframes: Array, f: int) -> Color:
	return _curve_at(keyframes, f)


## The interpolated curve colour at frame `f`: hold the first keyframe before it, the last
## after it, else linear-lerp between the bracketing pair.
static func _curve_at(keyframes: Array, f: int) -> Color:
	if keyframes.is_empty():
		return Color(0, 0, 0, 1)
	if f <= int(keyframes[0]["frame"]):
		return keyframes[0]["color"]
	var last: Dictionary = keyframes[keyframes.size() - 1]
	if f >= int(last["frame"]):
		return last["color"]
	for i in range(keyframes.size() - 1):
		var a: Dictionary = keyframes[i]
		var c: Dictionary = keyframes[i + 1]
		var fa: int = a["frame"]
		var fc: int = c["frame"]
		if f >= fa and f <= fc:
			var w := float(f - fa) / float(fc - fa)
			return (a["color"] as Color).lerp(c["color"], w)
	return last["color"]


## The kept frame indices for `samples`, with the budget split at the dead-zone boundary when
## `life_n` names one. Both regions are fitted; they SHARE the boundary sample `life_n - 1`,
## so the live window's last keyframe is also the tail's first and the polyline has no seam.
##
## The split is what stops the tail starving the live window, and the ORDER matters as much as
## the budget: `_douglas_peucker` pops its segment stack from the back, so it descends into the
## RIGHT half first and exhausts the tail before it ever returns to the head. Two calls make
## that bias unreachable rather than relying on it being small.
static func _fit_frames(samples: Array, life_n: int) -> Array:
	if life_n <= 1 or life_n >= samples.size():
		return _douglas_peucker(samples, EXACT_EPSILON, MAX_KEYFRAMES)
	var b: int = life_n - 1
	var keep := {}
	for f in _douglas_peucker(samples.slice(0, b + 1), EXACT_EPSILON, MAX_KEYFRAMES):
		keep[int(f)] = true
	for f in _douglas_peucker(samples.slice(b), EXACT_EPSILON, MAX_KEYFRAMES):
		keep[int(f) + b] = true
	var out := keep.keys()
	out.sort()
	return out


## Douglas-Peucker on the curve colour polyline (frame + RGB). Keeps the endpoints and,
## recursively, the point of largest per-channel deviation from its chord while that
## deviation exceeds `tol`; stops early once `budget` keyframes are kept. Returns kept frame
## indices in ascending order.
static func _douglas_peucker(samples: Array, tol: float, budget: int) -> Array:
	var n := samples.size()
	if n <= 2:
		return range(n)
	var keep := {0: true, n - 1: true}
	var stack := [[0, n - 1]]
	while not stack.is_empty():
		if keep.size() >= budget:
			break
		var seg = stack.pop_back()
		var lo: int = seg[0]
		var hi: int = seg[1]
		if hi - lo < 2:
			continue
		var worst := -1.0
		var worst_i := -1
		for i in range(lo + 1, hi):
			var d := _chord_deviation(samples, lo, hi, i)
			if d > worst:
				worst = d
				worst_i = i
		if worst > tol and worst_i >= 0:
			keep[worst_i] = true
			stack.push_back([lo, worst_i])
			stack.push_back([worst_i, hi])
	var out := keep.keys()
	out.sort()
	return out


## Per-channel max deviation of samples[i] from the straight chord samples[lo]→samples[hi].
static func _chord_deviation(samples: Array, lo: int, hi: int, i: int) -> float:
	var w := float(i - lo) / float(hi - lo)
	var interp: Color = (samples[lo] as Color).lerp(samples[hi], w)
	var c: Color = samples[i]
	return maxf(absf(c.r - interp.r), maxf(absf(c.g - interp.g), absf(c.b - interp.b)))


## The largest per-channel residual (curve space) of the kept keyframes' linear interpolation
## against the true samples — the honest max_error.
static func _residual(samples: Array, keyframes: Array) -> float:
	var worst := 0.0
	for f in range(samples.size()):
		var interp: Color = _curve_at(keyframes, f)
		var c: Color = samples[f]
		worst = maxf(worst, maxf(absf(c.r - interp.r), maxf(absf(c.g - interp.g), absf(c.b - interp.b))))
	return worst


static func _sample(cr, cg, cb, f: int) -> Color:
	return Color(cr.sample_by_frame(f), cg.sample_by_frame(f), cb.sample_by_frame(f), 1.0)
