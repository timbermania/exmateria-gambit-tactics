extends RefCounted
## The pure "pick the tint" back-solver for the PALETTE lane (ADR-0087) — the palette
## analogue of the screen BlendTargetSolver.
##
## The palette tint byte is a SIGNED Δ through one of the 11 shared blend modes, never an
## absolute colour (the #266 mislabel that produced the "seek-color renders the wrong hue"
## bug). So instead of exposing the raw byte, the author picks the colour a fixed reference
## should BECOME, and this module back-solves the Δ by reusing the screen BlendTargetSolver
## against the REAL forward PALETTE fold (ColorStack, param_max 31, quantize) — the exact op
## PaletteSubsystem plays. Because the reference is fixed, the fold is a single op whose base
## AND colour-so-far are that reference, so every mode's per-channel result is a pure function
## of one delta byte (ADR-0087 decision 3): the per-channel brute force is valid across all 11
## modes, including the luma ones (2/3/6/7), with no 3-D search or per-mode inversion.
##
## Reference base is mid-grey (15/31) for v1 — for the affine modes "grey becomes X" makes
## Δ = X − grey, so the control reads as "pick the tint" directly (sampling a real surface
## pixel is a deferred refinement). Unreachable targets snap to the NEAREST achievable byte,
## and the reported `achieved` colour is the honest forward fold of that byte. No class_name
## (ADR-0004). Restores (modes 8/10) carry no tint — never call solve() for them.

const ColorStackClass = ExMateriaSchema.ColorStack
const BlendTargetSolver = preload("res://src/effects/studio/BlendTargetSolver.gd")

## The fixed reference the author tints against: mid-grey at 5-bit CLUT step 15/31.
const REFERENCE_RAW := 15
const REFERENCE := Vector3(REFERENCE_RAW / 31.0, REFERENCE_RAW / 31.0, REFERENCE_RAW / 31.0)


## Back-solve the signed Δ bytes so the reference becomes `target` under blend `mode`. `orig`
## = {r, g, b} the keyframe's current raw bytes (the scan holds the other two channels here
## while varying one). Returns {r, g, b} raw bytes (0-255) plus `achieved` — the forward fold
## of those bytes, the honest "actual" colour (equals `target` when reachable, the nearest
## otherwise).
static func solve(mode: int, orig: Dictionary, target: Vector3) -> Dictionary:
	var eval := func(r: int, g: int, b: int) -> Vector3:
		return _fold(mode, r, g, b)
	var best: Dictionary = BlendTargetSolver.solve(eval, orig, target)
	best["achieved"] = result(mode, int(best.get("r", 0)), int(best.get("g", 0)), int(best.get("b", 0)))
	return best


## The forward palette fold of one tween's raw bytes over the reference — the colour the
## surface reaches (WYSIWYG). Used both as the picker's seed (fold of the STORED bytes) and
## to report a solve's `achieved` result. Returns a Color for the inspector's swatches.
static func result(mode: int, r: int, g: int, b: int) -> Color:
	var v := _fold(mode, r, g, b)
	return Color(v.x, v.y, v.z, 1.0)


## Fold a single palette op (mode + raw bytes) over the fixed reference at full progress —
## a fresh ColorStack so base AND colour-so-far are the reference (the decision-3 invariant).
## quantize + param_max 31 mirror the 5-bit CLUT applier PaletteSubsystem drives.
static func _fold(mode: int, r: int, g: int, b: int) -> Vector3:
	var stack := ColorStackClass.new()
	stack.set_param_max(31)
	stack.set_quantize(true)
	# time 0 → a snap layer (duration 0), folded at the same frame → full progress.
	stack.push_op(mode, r, g, b, 0, 0)
	return stack.fold(REFERENCE, 0, 0)
