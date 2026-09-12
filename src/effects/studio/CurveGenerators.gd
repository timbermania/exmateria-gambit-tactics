extends RefCounted
## The 16 parametric **curve-shape generators** (ADR-0089 curve-ownership amendment,
## decision 4) — a direct port of `effect-editor/ui/curve_generators.lua`, the working
## set the PCSX-Redux Lua editor already authored FFT curves with.
##
## They are the source of NEW shapes. A global shape LIBRARY was rejected on measurement:
## 2443 distinct shapes across the 401-effect corpus with weak reuse (only 421 appear in
## more than one effect), which is a browsing problem, not an authoring one. Eleven
## generators mint a shape from parameters (`linear`, `ease_in`/`out`, `s_curve`,
## `exponential_in`/`out`, `sine_wave`, `triangle_wave`, `sawtooth`, `pulse`, `constant`)
## and five reshape one you have (`invert`, `reverse`, `scale`, `shift`, `copy`).
##
## DOMAIN: a 160-element array of 0-255 ints — exactly `EffectCurve`'s length and
## `CurvePaintModel`'s grid range, so a generated shape drops straight into a
## [curve use site] through `CurvePaintModel.grid_to_curve` with no adapter.
##
## FIDELITY: the port is checked against a golden captured from the Lua module itself
## (`tests/goldens/curve_generators_golden.json`), element for element across 32
## parameter cases. Two idioms carry the semantics and are easy to get wrong:
## Lua's `math.floor` rounds toward -infinity (`floori`, never `int()` truncation), and
## Lua's `%` on floats is a FLOORED modulo (`fposmod`, never `fmod`).
##
## Pure static functions, no state. No `class_name` (ADR-0004) — preloaded by path.

## FFT curves are 160 dense samples. Not a tunable: it is the ROM's curve record length.
const CURVE_LENGTH := 160
const VMAX := 255


# --- shape generators ------------------------------------------------------

## Linear ramp from `start_val` to `end_val` over [start_frame, end_frame). Frames before
## the window hold `start_val`, frames at or after it hold `end_val` — the hold-outside
## rule every windowed generator below shares.
static func linear(start_frame: int, end_frame: int, start_val: float, end_val: float) -> Array:
	return _windowed(start_frame, end_frame, start_val, end_val, func(t): return t)


## Slow start, accelerating: `t^power`. power 1 = linear, 2 = quadratic, 3 = cubic.
static func ease_in(start_frame: int, end_frame: int, start_val: float, end_val: float,
		power: float = 2.0) -> Array:
	return _windowed(start_frame, end_frame, start_val, end_val,
		func(t): return pow(t, power))


## Fast start, decelerating: the mirror of ease_in.
static func ease_out(start_frame: int, end_frame: int, start_val: float, end_val: float,
		power: float = 2.0) -> Array:
	return _windowed(start_frame, end_frame, start_val, end_val,
		func(t): return 1.0 - pow(1.0 - t, power))


## Ease in AND out — slow at both ends, fast through the middle.
static func s_curve(start_frame: int, end_frame: int, start_val: float, end_val: float,
		power: float = 2.0) -> Array:
	return _windowed(start_frame, end_frame, start_val, end_val, func(t):
		if t < 0.5:
			return pow(2.0, power - 1.0) * pow(t, power)
		return 1.0 - pow(-2.0 * t + 2.0, power) / 2.0)


## Very slow start, explosive end. `strength` is the exponent's scale (10 = a 1/1024 floor).
## t = 0 is special-cased to a true 0 so the window starts exactly at `start_val`.
static func exponential_in(start_frame: int, end_frame: int, start_val: float, end_val: float,
		strength: float = 10.0) -> Array:
	return _windowed(start_frame, end_frame, start_val, end_val, func(t):
		return 0.0 if t == 0.0 else pow(2.0, strength * (t - 1.0)))


## Explosive start, very slow end — the mirror of exponential_in.
static func exponential_out(start_frame: int, end_frame: int, start_val: float, end_val: float,
		strength: float = 10.0) -> Array:
	return _windowed(start_frame, end_frame, start_val, end_val, func(t):
		return 1.0 if t == 1.0 else 1.0 - pow(2.0, -strength * t))


## Sine oscillation between `min_val` and `max_val`, `cycles` complete cycles across the
## window, `phase` in cycles (1 = a full cycle). Outside the window the curve holds the
## wave's value AT the boundary — not the endpoint values — so an oscillator that starts
## mid-swing does not step.
static func sine_wave(start_frame: int, end_frame: int, min_val: float, max_val: float,
		cycles: float = 1.0, phase: float = 0.0) -> Array:
	var lo := clampf(min_val, 0.0, float(VMAX))
	var hi := clampf(max_val, 0.0, float(VMAX))
	var amplitude := (hi - lo) / 2.0
	var offset := (hi + lo) / 2.0
	var wave := func(cycle_pos: float) -> float:
		return offset + amplitude * sin(cycle_pos * TAU)
	return _oscillator(start_frame, end_frame, cycles, phase, wave)


## Triangle oscillation — linear rise and fall instead of the sine's curve. Same window
## and hold rules as `sine_wave`.
static func triangle_wave(start_frame: int, end_frame: int, min_val: float, max_val: float,
		cycles: float = 1.0, phase: float = 0.0) -> Array:
	var lo := clampf(min_val, 0.0, float(VMAX))
	var hi := clampf(max_val, 0.0, float(VMAX))
	var amplitude := (hi - lo) / 2.0
	var offset := (hi + lo) / 2.0
	var wave := func(cycle_pos: float) -> float:
		# fposmod, not fmod: Lua's `%` is floored, so a negative phase wraps forward.
		var p := fposmod(cycle_pos, 1.0)
		var tri := 0.0
		if p < 0.25:
			tri = p * 4.0            # 0 → 1 over the first quarter
		elif p < 0.75:
			tri = 2.0 - p * 4.0      # 1 → -1 over the middle half
		else:
			tri = p * 4.0 - 4.0      # -1 → 0 over the last quarter
		return offset + amplitude * tri
	return _oscillator(start_frame, end_frame, cycles, phase, wave)


## Repeating ramps from `min_val` to `max_val`, `teeth` of them across the window. Unlike
## the two oscillators, it holds `min_val` before the window and `max_val` after — the
## sawtooth's own discontinuity, kept faithfully.
static func sawtooth(start_frame: int, end_frame: int, min_val: float, max_val: float,
		teeth: float = 1.0) -> Array:
	var lo := clampf(min_val, 0.0, float(VMAX))
	var hi := clampf(max_val, 0.0, float(VMAX))
	var out := _filled(floori(lo))
	for i in range(CURVE_LENGTH):
		if i < start_frame:
			out[i] = floori(lo)
		elif i >= end_frame:
			out[i] = floori(hi)
		else:
			var t := float(i - start_frame) / float(end_frame - start_frame)
			out[i] = floori(lo + (hi - lo) * fposmod(t * teeth, 1.0))
	return out


## Square wave: `high_val` for the first `duty_cycle` fraction of each pulse, `low_val`
## for the rest. Holds `low_val` on BOTH sides of the window (a pulse train that has not
## started, and one that has finished, are both low).
static func pulse(start_frame: int, end_frame: int, low_val: float, high_val: float,
		pulses: float = 1.0, duty_cycle: float = 0.5) -> Array:
	var lo: int = clampi(floori(low_val), 0, VMAX)
	var hi: int = clampi(floori(high_val), 0, VMAX)
	var duty := clampf(duty_cycle, 0.0, 1.0)
	var out := _filled(lo)
	for i in range(CURVE_LENGTH):
		if i < start_frame or i >= end_frame:
			out[i] = lo
		else:
			var t := float(i - start_frame) / float(end_frame - start_frame)
			out[i] = hi if fposmod(t * pulses, 1.0) < duty else lo
	return out


## One value at every frame. `constant(0)` is the IDENTITY curve (decision 5): a use site
## that gains it renders bit-identically to one with no curve at all, because no curve
## makes the sim hold the START values and an all-zero curve lerps to `min_start` at every
## frame. It is what a newly-added curve is minted as, so adding one changes nothing.
static func constant(value: float) -> Array:
	return _filled(clampi(floori(value), 0, VMAX))


# --- shape manipulators ----------------------------------------------------

## Flip vertically: 255 − v.
static func invert(curve: Array) -> Array:
	var out := _filled(0)
	for i in range(CURVE_LENGTH):
		out[i] = VMAX - (int(curve[i]) if i < curve.size() else 0)
	return out


## Flip horizontally — the curve played backwards.
static func reverse(curve: Array) -> Array:
	var out := _filled(0)
	for i in range(CURVE_LENGTH):
		var j: int = CURVE_LENGTH - 1 - i
		out[i] = int(curve[j]) if j >= 0 and j < curve.size() else 0
	return out


## Stretch or squash the curve's excursion around `midpoint` (contrast, not brightness).
static func scale(curve: Array, factor: float, midpoint: float = 128.0) -> Array:
	var out := _filled(0)
	for i in range(CURVE_LENGTH):
		var v: float = float(curve[i]) if i < curve.size() else 0.0
		out[i] = clampi(floori(midpoint + (v - midpoint) * factor), 0, VMAX)
	return out


## Move the whole curve up or down (brightness, not contrast), clamped at both rails.
static func shift(curve: Array, offset: float) -> Array:
	var out := _filled(0)
	for i in range(CURVE_LENGTH):
		var v: float = float(curve[i]) if i < curve.size() else 0.0
		out[i] = clampi(floori(v + offset), 0, VMAX)
	return out


## A detached copy, padded to CURVE_LENGTH. The verb the PICKER runs: a pick copies a
## shape into the use site's own curve, so nothing links afterward.
static func copy(curve: Array) -> Array:
	var out := _filled(0)
	for i in range(CURVE_LENGTH):
		out[i] = int(curve[i]) if i < curve.size() else 0
	return out


# --- internals -------------------------------------------------------------

## The shared windowed-generator body: hold `start_val` before the window, hold `end_val`
## at and after it, and inside map normalized position t through `easing` and lerp. The
## five ramp generators differ ONLY in that one function, so the window and hold rules
## cannot drift apart between them.
static func _windowed(start_frame: int, end_frame: int, start_val: float, end_val: float,
		easing: Callable) -> Array:
	var sv := clampf(start_val, 0.0, float(VMAX))
	var ev := clampf(end_val, 0.0, float(VMAX))
	var out := _filled(0)
	for i in range(CURVE_LENGTH):
		if i < start_frame:
			out[i] = floori(sv)
		elif i >= end_frame:
			out[i] = floori(ev)
		else:
			var t := float(i - start_frame) / float(end_frame - start_frame)
			out[i] = floori(sv + (ev - sv) * float(easing.call(t)))
	return out


## The shared oscillator body: inside the window the wave runs `cycles` cycles from
## `phase`; outside it HOLDS the wave's value at the nearer boundary. Values are clamped
## (an amplitude that overshoots a rail is clipped, not wrapped).
static func _oscillator(start_frame: int, end_frame: int, cycles: float, phase: float,
		wave: Callable) -> Array:
	var before: int = clampi(floori(float(wave.call(phase))), 0, VMAX)
	var after: int = clampi(floori(float(wave.call(cycles + phase))), 0, VMAX)
	var out := _filled(0)
	for i in range(CURVE_LENGTH):
		if i < start_frame:
			out[i] = before
		elif i >= end_frame:
			out[i] = after
		else:
			var t := float(i - start_frame) / float(end_frame - start_frame)
			out[i] = clampi(floori(float(wave.call(t * cycles + phase))), 0, VMAX)
	return out


static func _filled(value: int) -> Array:
	var out: Array = []
	out.resize(CURVE_LENGTH)
	out.fill(value)
	return out
