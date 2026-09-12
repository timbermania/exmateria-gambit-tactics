extends RefCounted

## The 8-bit ADDITIVE map-illumination applier — a CPU model of FUN_80090dec
## @0x80090DEC, the THIRD colour sink of the FFT combat renderer (living doc
## research/working_documents/MAP_ILLUMINATION_APPLIER_HOLY_E015.md). This is the
## piece Godot was missing: the map "white light" (Holy/E015, Meteor, Ramuh summons)
## is NOT the 5-bit CLUT tint — it is a separate single global RGB, held in 16.16
## fixed-point clamped to 0-255 (8-bit), stamped as the flat Gouraud vertex colour of
## every terrain polygon and drawn ADDITIVELY over the lit-and-textured terrain.
##
## Because Godot folded the map only through the 5-bit CLUT ColorStack, the smooth
## 8-bit additive flood rendered as 32-level stair-steps ("clicking"). This applier
## reproduces the real curve: additive over a neutral base (0 ⇒ no illumination),
## params rescaled ×8 (the R<<3 at the affected-units track call site — a 5-bit δ of
## 31 → 248, the captured white-flood peak), ramped LINEARLY over [map_ramp] frames
## (Time×8 fast — distinct from the CLUT's fixed-8 — / 32·(Time»2) slow), no curve
## table. See the sibling 5-bit path in ColorStack.gd / ColorRecipe.gd.
##
## Like ColorStack it is declarative and re-derived from the op timeline every frame
## (never an accumulated buffer), so any `now` is directly evaluable — park / rewind /
## scrub come for free. Output is ONE flat vec3 delivered as a uniform (map_illum_add),
## not the per-index CLUT layer arrays.
## Vault: [[Combat Color Appliers]]
## Vault: [[Map Tint]]

## One armed op: a PSX Color keyframe as it reaches the map sink. `rgb5` is the raw
## SIGNED 5-bit param (sign-extended byte); the ×8 rescale to 8-bit happens in _target.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const ColorRecipe = ExMateriaSchema.ColorRecipe

class Op extends RefCounted:
	var mode: int
	var rgb5: Vector3i
	var start_frame: int
	var ramp_frames: int


var _ops: Array[Op] = []

## The additive illumination base (DAT_800a1b94, seeded by FUN_80090da8), normalized to
## [0,1]. = 0 for the Holy combat map (proven live), and 0 is the additive neutral, so
## an idle/no-op DDA is a true no-op. Exposed for the rare non-zero-base map.
var _base: Vector3 = Vector3.ZERO


## Frames a given `Time` byte ramps over on the MAP applier — DISTINCT from the CLUT's
## ColorRecipe.ramp_frames_for_time (which is a fixed 8 for Time<4). The map fast ramp
## is Time×8 (variable), filling the whole keyframe hold; slow (Time≥4) is 32 steps one
## every Time»2 frames = 32·(Time»2). Time=0 → 0 (an instant snap). Living doc §2.
static func map_ramp(time: int) -> int:
	if time <= 0:
		return 0
	if time < 4:
		return time * 8
	return 32 * (time >> 2)


## Sign-extend a param byte (Red/Green/Blue are signed bytes in the PSX applier), same
## convention as ColorRecipe — the map then rescales this 5-bit δ ×8 into 8-bit space.
static func _sb(b: int) -> int:
	b = b & 0xFF
	return b - 256 if b >= 128 else b


## Push one PSX Color op at its `start_frame`. `r/g/b` are the raw param bytes (as the
## CLUT keyframe carries them); `time` is the raw Time byte (ramp length = map_ramp).
func push_op(mode: int, r: int, g: int, b: int, time: int, start_frame: int) -> void:
	var op := Op.new()
	op.mode = mode
	op.rgb5 = Vector3i(_sb(r), _sb(g), _sb(b))
	op.start_frame = start_frame
	op.ramp_frames = map_ramp(time)
	_ops.append(op)


## Re-derive the single flat illumination RGB at `now` from the op timeline. Each op is
## a linear ramp from the value the DDA held when it armed (the previous op's settled
## target — ramps fill the hold, so the prior op is complete) toward its own target,
## over its ramp_frames. Ops that haven't started yet contribute nothing.
func evaluate(now: int) -> Vector3:
	var current := _base   # settled value carried between ops
	var result := _base    # displayed value at `now`
	for op in _ops:
		if now < op.start_frame:
			break  # this op and all later ones haven't started; hold `result`
		var target := _target(op, current)
		var elapsed := now - op.start_frame
		var p := 1.0 if op.ramp_frames <= 0 else clampf(float(elapsed) / float(op.ramp_frames), 0.0, 1.0)
		result = current.lerp(target, p)
		if p >= 1.0:
			current = target  # op settled; the next op ramps from here
		# else: still ramping — the next op's start_frame is start+hold >= start+ramp > now,
		# so the next iteration breaks and returns this ramping `result`.
	return result.clamp(Vector3.ZERO, Vector3.ONE)


## The absolute target this op ramps toward, in normalized [0,1] 8-bit space. Params are
## rescaled ×8 (5-bit δ → 8-bit) then normalized by 255. Mirrors FUN_80090dec's mode
## switch (living doc §2); clamped to [0,1] like the PSX clamp [0, 0xff0000].
func _target(op: Op, current: Vector3) -> Vector3:
	var param := Vector3(op.rgb5 * 8) / 255.0
	var t: Vector3
	match op.mode:
		0:
			t = current + param                 # current + param
		1:
			t = current * 0.5 + param           # (current>>1) + param
		4, 9:
			t = _base + param                   # base + param (idempotent absolute)
		5:
			t = _base * 0.5 + param             # (base>>1) + param
		8:
			t = _base                           # restore to base (timed release)
		10:
			t = current                         # stop: hold current
		6:
			t = _luma(_base, 6, op.rgb5 * 8)    # luma from base
		7:
			t = _luma(_base, 12, op.rgb5 * 8)
		2:
			t = _luma(current, 6, op.rgb5 * 8)  # luma from current
		3:
			t = _luma(current, 12, op.rgb5 * 8)
		_:
			t = current
	return t.clamp(Vector3.ZERO, Vector3.ONE)


## Luma transform in 8-bit space (param_max 255), reusing the bit-depth-agnostic core
## in ColorRecipe so the map and CLUT share one luma definition.
func _luma(src: Vector3, div: int, delta8: Vector3i) -> Vector3:
	var s := Vector3i((src.clamp(Vector3.ZERO, Vector3.ONE) * 255.0).round())
	return Vector3(ColorRecipe.luma_out(s, div, delta8, 255)) / 255.0
