extends Node
## Tests for ColorRecipe — the pure CPU core of ADR-0067's unified colour model.
## A recipe is the reduction of FFT's 11 PSX `Color` modes to two shapes: affine
## `{scale, bias}` (c·scale + bias) or luma `{div, delta5, source}` (the integer
## floor((2R+3G+B)/div)+delta sepia/grey mix). This suite drives the recipe value
## type, the mode→shape reduction, the fold's recipe(·) eval, the symbolic affine
## merge, and the linear DDA progress — extracted from ScenarioColorTint, kept
## byte-exact. See docs/adr/0067-color-modes-are-one-model.md and the "Color modes"
## cluster in CONTEXT.md.
##
## Run: bash tests/stranger/exmateria_schema/run.sh   (ADR-0194 — this test is
## addon-owned and runs in a STRANGER project, not in the host. Directly:
## "$GODOT" --path . --quit-after 5 res://addons/exmateria_schema/tests/ColorRecipeTest.tscn)

const Recipe = preload("res://addons/exmateria_schema/colour_model/ColorRecipe.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_mode0_is_additive_affine()
	_test_affine_mode_shapes()
	_test_luma_out5_reproduces_measured_pairs()
	_test_luma_mode_shapes()
	_test_luma_apply_uses_source()
	_test_affine_source_distinguishes_base_from_current()
	_test_affine_merge_composes_symbolically()
	_test_base_source_affine_merge_is_idempotent()
	_test_ramp_frames_for_time()
	_test_progress_at_is_linear()
	_test_param_max_8bit_screen_space()

	print("\n=== ColorRecipeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ColorRecipeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ColorRecipeTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColorRecipeTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)


func _assert_vec_approx(got: Vector3, want: Vector3, name: String) -> void:
	if got.is_equal_approx(want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# --- tests -------------------------------------------------------------------

## PSX Color mode 0 is "current + delta": in the layer model that is the absolute
## affine recipe {scale=1, bias=delta} applied to the fold's input colour — NOT the
## old accumulating `bias += delta`. delta is the signed 5-bit RGB param / 31.
## Red=8, Green=0, Blue=255(-1 signed) -> delta (8, 0, -1)/31.
func _test_mode0_is_additive_affine() -> void:
	var r := Recipe.from_mode(0, 8, 0, 255)
	_assert_eq(r.luma_div, 0, "mode 0 is affine (luma_div=0)")
	_assert_vec_approx(r.scale, Vector3.ONE, "mode 0 scale=1")
	_assert_vec_approx(r.bias, Vector3(8.0, 0.0, -1.0) / 31.0, "mode 0 bias=delta")
	# apply(base, current): affine ignores base and adds the delta to current.
	var got: Vector3 = r.apply(Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5))
	_assert_vec_approx(got, Vector3(0.5, 0.5, 0.5) + Vector3(8.0, 0.0, -1.0) / 31.0,
		"mode 0 apply adds delta to current")


## The remaining per-channel affine modes reduce to fixed {scale, bias} shapes
## applied to the fold input (the accumulation/reset semantics are the stack's job):
##   1     (c>>1) + delta      -> {0.5, delta}
##   4, 9  base + delta        -> {1,   delta}   (reset-to-base is a stack concern)
##   5     (base>>1) + delta   -> {0.5, delta}
##   8     base (absolute)     -> {1,   0}       (restore is a stack concern)
##   10    reset               -> {1,   0}
func _test_affine_mode_shapes() -> void:
	var d := Vector3(2.0, 4.0, 6.0) / 31.0  # delta for R=2,G=4,B=6

	var m1 := Recipe.from_mode(1, 2, 4, 6)
	_assert_eq(m1.luma_div, 0, "mode 1 affine")
	_assert_vec_approx(m1.scale, Vector3.ONE * 0.5, "mode 1 scale=0.5")
	_assert_vec_approx(m1.bias, d, "mode 1 bias=delta")

	for m in [4, 9]:
		var r := Recipe.from_mode(m, 2, 4, 6)
		_assert_vec_approx(r.scale, Vector3.ONE, "mode %d scale=1" % m)
		_assert_vec_approx(r.bias, d, "mode %d bias=delta" % m)

	var m5 := Recipe.from_mode(5, 2, 4, 6)
	_assert_vec_approx(m5.scale, Vector3.ONE * 0.5, "mode 5 scale=0.5")
	_assert_vec_approx(m5.bias, d, "mode 5 bias=delta")

	for m in [8, 10]:
		var r := Recipe.from_mode(m, 2, 4, 6)
		_assert_eq(r.luma_div, 0, "mode %d affine" % m)
		_assert_vec_approx(r.scale, Vector3.ONE, "mode %d scale=1 (identity shape)" % m)
		_assert_vec_approx(r.bias, Vector3.ZERO, "mode %d bias=0 (identity shape)" % m)


## luma_out5 is the byte-exact integer core of Color modes 2/3/6/7: mix each 5-bit
## CLUT entry to L = floor((2R+3G+B)/div), then out_ch = clamp(L + delta_ch, 0, 31).
## These 6 pairs are live scn8 field CLUT bytes (div=12, delta=(2,1,-1)) matched
## 227/227 in COLOR_TINT_LUMA_MODE_SEPIA.md §3.4 — the regression oracle preserved
## across the extraction from ScenarioColorTint.
func _test_luma_out5_reproduces_measured_pairs() -> void:
	var delta := Vector3i(2, 1, -1)
	var pairs := [
		[4, 4, 3, 3, 2, 0], [6, 5, 4, 4, 3, 1], [7, 6, 4, 5, 4, 2],
		[11, 12, 10, 7, 6, 4], [13, 14, 12, 8, 7, 5], [15, 16, 14, 9, 8, 6],
	]
	for p in pairs:
		var got: Vector3i = Recipe.luma_out5(Vector3i(p[0], p[1], p[2]), 12, delta)
		_assert_eq(got, Vector3i(p[3], p[4], p[5]), "luma_out5 base=(%d,%d,%d)" % [p[0], p[1], p[2]])


## Luma modes reduce to {div, delta5, from_base}: 7=base/12, 6=base/6, 3=current/12,
## 2=current/6. delta5 is the raw signed 5-bit RGB. Non-luma modes leave luma_div=0.
func _test_luma_mode_shapes() -> void:
	var m7 := Recipe.from_mode(7, 4, 3, 1)
	_assert_eq(m7.luma_div, 12, "mode 7 div=12")
	_assert_true(m7.luma_from_base, "mode 7 reads base")
	_assert_eq(m7.luma_delta5, Vector3i(4, 3, 1), "mode 7 delta5=(4,3,1)")

	var m6 := Recipe.from_mode(6, 255, 0, 2)  # Red=255 -> -1 signed
	_assert_eq(m6.luma_div, 6, "mode 6 div=6")
	_assert_true(m6.luma_from_base, "mode 6 reads base")
	_assert_eq(m6.luma_delta5, Vector3i(-1, 0, 2), "mode 6 delta5 sign-extends")

	var m3 := Recipe.from_mode(3, 0, 0, 0)
	_assert_eq(m3.luma_div, 12, "mode 3 div=12")
	_assert_true(not m3.luma_from_base, "mode 3 reads current")

	var m2 := Recipe.from_mode(2, 0, 0, 0)
	_assert_eq(m2.luma_div, 6, "mode 2 div=6")
	_assert_true(not m2.luma_from_base, "mode 2 reads current")


## A luma recipe's apply(base, current) picks its source: from_base reads `base`,
## from_current reads `current` (clamped) — mirroring the shader fold. Output is
## luma_out5 in 5-bit space, renormalized to [0,1].
func _test_luma_apply_uses_source() -> void:
	var base := Vector3(4.0, 4.0, 3.0) / 31.0      # 5-bit (4,4,3)
	var current := Vector3(11.0, 12.0, 10.0) / 31.0  # 5-bit (11,12,10)
	var delta := Vector3i(2, 1, -1)

	var from_base := Recipe.luma(12, delta, true)
	var want_b: Vector3i = Recipe.luma_out5(Vector3i(4, 4, 3), 12, delta)  # (3,2,0)
	_assert_vec_approx(from_base.apply(base, current), Vector3(want_b) / 31.0,
		"luma from_base reads base")

	var from_current := Recipe.luma(12, delta, false)
	var want_c: Vector3i = Recipe.luma_out5(Vector3i(11, 12, 10), 12, delta)  # (7,6,4)
	_assert_vec_approx(from_current.apply(base, current), Vector3(want_c) / 31.0,
		"luma from_current reads current")


## The affine source flag (the combat-Cure fix, issue #164): modes 0/1 read the
## colour-so-far; modes 4/5/9 read the ABSOLUTE base. from_mode sets the flag, and
## apply() honours it — a base-source affine ignores `current` entirely, so it is a
## function of `base` alone (idempotent under repetition).
func _test_affine_source_distinguishes_base_from_current() -> void:
	var base := Vector3(0.4, 0.5, 0.6)
	var current := Vector3(0.9, 0.1, 0.2)
	var d := Vector3(6.0, 0.0, 0.0) / 31.0

	for m in [0, 1]:
		var r := Recipe.from_mode(m, 6, 0, 0)
		_assert_true(not r.affine_from_base, "mode %d reads current (from_base=false)" % m)
		_assert_vec_approx(r.apply(base, current), current * r.scale + r.bias,
			"mode %d apply reads current" % m)

	for m in [4, 9]:
		var r := Recipe.from_mode(m, 6, 0, 0)
		_assert_true(r.affine_from_base, "mode %d reads base (from_base=true)" % m)
		_assert_vec_approx(r.apply(base, current), base + d, "mode %d apply reads base + delta" % m)

	var m5 := Recipe.from_mode(5, 6, 0, 0)
	_assert_true(m5.affine_from_base, "mode 5 reads base (from_base=true)")
	_assert_vec_approx(m5.apply(base, current), base * 0.5 + d, "mode 5 apply reads base*0.5 + delta")


## Contiguous settled affine layers merge into ONE affine so the live stack never
## grows: applying `below` then `above` is `above(below(c)) = c·(s0·s1) + (s1·b0+b1)`.
## The merge must be exact (the fold-equivalence below) and reversible (base untouched).
func _test_affine_merge_composes_symbolically() -> void:
	var below := Recipe.affine(Vector3(0.5, 0.5, 0.5), Vector3(0.1, 0.2, 0.3))
	var above := Recipe.affine(Vector3(2.0, 0.5, 1.0), Vector3(0.05, -0.1, 0.0))
	var merged := Recipe.merge(below, above)
	# {s0·s1, s1·b0 + b1}
	_assert_vec_approx(merged.scale, Vector3(1.0, 0.25, 0.5), "merged scale = s0·s1")
	_assert_vec_approx(merged.bias, Vector3(2.0 * 0.1 + 0.05, 0.5 * 0.2 - 0.1, 1.0 * 0.3 + 0.0),
		"merged bias = s1·b0 + b1")
	# Fold-equivalence: the merged single affine == applying both in order, any c.
	for c in [Vector3(0.3, 0.6, 0.9), Vector3(0.0, 1.0, 0.5), Vector3(1.0, 0.2, 0.7)]:
		var ignore := Vector3.ZERO  # current-source affine ignores base
		var stepwise: Vector3 = above.apply(ignore, below.apply(ignore, c))
		_assert_vec_approx(merged.apply(ignore, c), stepwise, "merge == stepwise fold at %s" % str(c))


## Source-aware merge (the Cure-blowout fix): merging must stay fold-equivalent when
## either operand reads the absolute base.
##   • above base-source  → above OVERWRITES below (idempotent run — the merge IS above)
##   • below base-source, above current → the composed recipe stays base-source
## Proven by fold-equivalence against `base` at several colours, so the merged single
## entry reproduces applying both in order.
func _test_base_source_affine_merge_is_idempotent() -> void:
	var below_cur := Recipe.affine(Vector3.ONE, Vector3(0.3, 0.0, 0.0))       # current + 0.3R
	var below_base := Recipe.affine_base(Vector3(0.5, 0.5, 0.5), Vector3.ZERO)  # base*0.5
	var above_base := Recipe.affine_base(Vector3.ONE, Vector3(0.0, 0.2, 0.0))   # base + 0.2G
	var above_cur := Recipe.affine(Vector3(2.0, 1.0, 1.0), Vector3.ZERO)        # current*2R

	# above base-source overwrites below (idempotency): merge == above, ignoring below.
	var over := Recipe.merge(below_cur, above_base)
	_assert_true(over.affine_from_base, "base-source above → merged reads base")
	# below base-source + above current: merged is base-source.
	var chain := Recipe.merge(below_base, above_cur)
	_assert_true(chain.affine_from_base, "base-source below → merged reads base")

	for c in [Vector3(0.3, 0.6, 0.9), Vector3(0.1, 1.0, 0.5), Vector3(0.8, 0.2, 0.7)]:
		var base := Vector3(0.4, 0.5, 0.6)
		var step_over: Vector3 = above_base.apply(base, below_cur.apply(base, c))
		_assert_vec_approx(over.apply(base, c), step_over, "overwrite merge == stepwise at %s" % str(c))
		var step_chain: Vector3 = above_cur.apply(base, below_base.apply(base, c))
		_assert_vec_approx(chain.apply(base, c), step_chain, "base-below merge == stepwise at %s" % str(c))


## A layer's progress runs over a frame count derived from the op's `Time` byte,
## mirroring FFT's two DDA tables: Time=0 snaps (0 frames), Time 1..3 = the fast
## table (fixed 8 frames), Time>=4 = the slow table (32 steps every Time>>2 frames
## = 32·(Time>>2)). Moved verbatim from ScenarioColorTint.ramp_frames_for_time.
func _test_ramp_frames_for_time() -> void:
	_assert_eq(Recipe.ramp_frames_for_time(0), 0, "Time=0 snaps (0 frames)")
	_assert_eq(Recipe.ramp_frames_for_time(1), 8, "Time=1 -> fast 8 frames")
	_assert_eq(Recipe.ramp_frames_for_time(3), 8, "Time=3 -> fast 8 frames")
	_assert_eq(Recipe.ramp_frames_for_time(4), 32, "Time=4 -> slow 32 frames")
	_assert_eq(Recipe.ramp_frames_for_time(8), 64, "Time=8 -> slow 64 frames")


## progress_at(elapsed, total) is the layer's [0,1] fade weight — linear DDA. It is
## a pure function of elapsed/total so any `now` is directly evaluable (seek/rewind).
## 0 at the start, 1 at (and past) the end; a zero-length ramp is instantly complete.
func _test_progress_at_is_linear() -> void:
	_assert_eq(Recipe.progress_at(0, 32), 0.0, "progress starts at 0")
	_assert_eq(Recipe.progress_at(8, 32), 0.25, "progress is linear (8/32)")
	_assert_eq(Recipe.progress_at(16, 32), 0.5, "progress is linear (16/32)")
	_assert_eq(Recipe.progress_at(32, 32), 1.0, "progress lands on 1 at the end")
	_assert_eq(Recipe.progress_at(40, 32), 1.0, "progress clamps at 1 past the end")
	_assert_eq(Recipe.progress_at(5, 0), 1.0, "a zero-length ramp is instantly complete")


## ADR-0067 slice 5b: param_max generalizes the mode engine to 8-bit screen space.
## The PSX combat gradient applier FUN_80090258 @0x80090258 uses the SAME 11-mode
## switch as the CLUT applier, reading baseline bytes @0x800a1b48 — mode 5 =
## base/2 + param (base * 0x8000 + param<<16 in 16.16). With param_max=255 the recipe
## must reproduce that byte-exactly (E005 for_each screen kf0: base=(32,64,124),
## param=(26,31,36) -> (16,32,62)+(26,31,36) = (42,63,98)). Default 31 is unchanged.
func _test_param_max_8bit_screen_space() -> void:
	# Default (5-bit): mode-5 bias is delta/31 — unchanged.
	var r5 := Recipe.from_mode(5, 4, 4, 4)
	_assert_vec_approx(r5.bias, Vector3(4, 4, 4) / 31.0, "8bit: default param_max=31 keeps /31 bias")
	_assert_true(r5.affine_from_base, "8bit: mode5 still base-source")

	# 8-bit screen: mode-5 = base/2 + param/255, byte-exact to FUN_80090258 case 5.
	var r8 := Recipe.from_mode(5, 26, 31, 36, 255)
	_assert_vec_approx(r8.scale, Vector3.ONE * 0.5, "8bit: mode5 scale = 0.5")
	_assert_vec_approx(r8.bias, Vector3(26, 31, 36) / 255.0, "8bit: mode5 bias = param/255")
	var base := Vector3(32, 64, 124) / 255.0
	var out := r8.apply(base, Vector3.ZERO)  # base-source ignores current
	_assert_vec_approx(out, Vector3(42, 63, 98) / 255.0, "8bit: mode5 base/2+param = (42,63,98)/255")

	# Signed-byte param at 8-bit: raw 254 = -2 -> delta -2/255 (darkening).
	var rn := Recipe.from_mode(0, 254, 254, 254, 255)
	_assert_vec_approx(rn.bias, Vector3(-2, -2, -2) / 255.0, "8bit: signed-byte param -2/255")

	# 8-bit luma (mode 2 reads CURRENT): L = floor((2R+3G+B)/6) in 255 space, /255.
	var rl := Recipe.from_mode(2, 0, 0, 0, 255)
	_assert_eq(rl.param_max, 255, "8bit: luma recipe carries param_max=255")
	var lout := rl.apply(Vector3.ZERO, Vector3(255, 0, 0) / 255.0)  # current=(255,0,0)
	_assert_vec_approx(lout, Vector3(85, 85, 85) / 255.0, "8bit: luma (2*255)/6=85 in 255 space")
