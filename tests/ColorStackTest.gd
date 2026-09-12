extends Node
## Tests for ColorStack — the CPU source of truth for ADR-0067's unified colour
## model (the DepthMode.gd analog). It holds one consumer's ordered list of colour
## layers (recipe + timeline + surface mask), evaluates each layer's progress at a
## given `now` via the byte-exact DDA, merges settled affines, expires restored
## layers, and packs the bounded uniform arrays the shared include folds:
##   color_layer_rgb0[i] = (affine scale | luma delta5).xyz , .w = progress
##   color_layer_rgb1[i] = affine bias.xyz                  , .w = luma div (0 ⇒ affine)
##   color_layer_meta[i] = surface mask[2:0] | luma source[3]
## See docs/adr/0067-color-modes-are-one-model.md and the "Color modes" cluster.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ColorStackTest.tscn

const Recipe = ExMateriaSchema.ColorRecipe
const Stack = ExMateriaSchema.ColorStack

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const ColorRecipe = ExMateriaSchema.ColorRecipe

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_settled_affine_layer_packs()
	_test_progress_evaluated_at_now()
	_test_layers_preserve_push_order()
	_test_luma_layer_packs()
	_test_settled_affines_merge()
	_test_luma_breaks_the_affine_run()
	_test_midramp_affine_stays_separate()
	_test_apply_pushes_uniforms_to_material()
	_test_apply_packed_concatenates_and_pads()
	_test_apply_packed_empty_is_noop()
	_test_push_op_reduces_and_ramps_in()
	_test_push_op_luma()
	_test_mode8_restore_fades_out_then_expires()
	_test_restore_midfade_fades_from_current_not_snap()
	_test_restore_does_not_resurrect_layer_before_restore_start()
	_test_restore_captured_midfade_shows_ramp_before_restore_start()
	_test_restore_holds_base_when_shadowed_by_settled_base_layer()
	_test_mode10_reset_snaps_clear()
	_test_fold_affine_and_luma()
	_test_fold_respects_surface_mask()
	_test_fold_matches_legacy_unit_shader_math()
	_test_fold_matches_legacy_field_shader_math()
	_test_fold_matches_legacy_additive_combat_tint()
	_test_fold_packed_reproduces_fold()
	_test_commit_bake_affine_byte_exact()
	_test_commit_bake_snaps_source_to_5bit_before_affine()
	_test_commit_bake_generalizes_to_luma()

	print("\n=== ColorStackTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ColorStackTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ColorStackTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColorStackTest")
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


func _assert_vec4_approx(got: Vector4, want: Vector4, name: String) -> void:
	if got.is_equal_approx(want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# --- tests -------------------------------------------------------------------

## A single settled (snap, duration 0) additive affine layer packs into the uniform
## arrays: count=1, rgb0 = (scale.xyz, progress=1), rgb1 = (bias.xyz, div=0),
## meta = whole-surface mask (0x7). A snap is instantly at full progress.
func _test_settled_affine_layer_packs() -> void:
	var stack := Stack.new()
	var recipe := Recipe.affine(Vector3.ONE, Vector3(0.1, 0.2, 0.3))
	stack.push_layer(recipe, 0, 0)  # start=0, duration=0 (snap), default whole-surface mask
	stack.evaluate(0)
	_assert_eq(stack.count(), 1, "one layer active")
	_assert_vec4_approx(stack.rgb0()[0], Vector4(1.0, 1.0, 1.0, 1.0), "rgb0 = (scale, progress=1)")
	_assert_vec4_approx(stack.rgb1()[0], Vector4(0.1, 0.2, 0.3, 0.0), "rgb1 = (bias, div=0)")
	_assert_eq(stack.meta()[0], 0x7, "meta = whole-surface mask (all bits)")


## A layer ramping over [start, start+dur] has its progress re-derived at `now`:
## 0 at start, linear through, 1 at the end. Re-evaluating at a different `now`
## re-derives it (never accumulates) — the seek/rewind property.
func _test_progress_evaluated_at_now() -> void:
	var stack := Stack.new()
	stack.push_layer(Recipe.affine(Vector3.ONE, Vector3(0.2, 0.0, 0.0)), 10, 32)
	stack.evaluate(10)
	_assert_eq(stack.rgb0()[0].w, 0.0, "progress 0 at start")
	stack.evaluate(18)  # 8/32 in
	_assert_eq(stack.rgb0()[0].w, 0.25, "progress 0.25 at 8/32")
	stack.evaluate(42)  # end
	_assert_eq(stack.rgb0()[0].w, 1.0, "progress 1 at end")
	# Seek backward: re-derived, not stuck at 1.
	stack.evaluate(18)
	_assert_eq(stack.rgb0()[0].w, 0.25, "seek back re-derives progress (0.25)")


## Layers fold in push order (ordered array — the ADR keeps interlacing free), so
## the packed arrays preserve insertion order. Distinct masks keep them from merging,
## isolating the ordering property.
func _test_layers_preserve_push_order() -> void:
	var stack := Stack.new()
	stack.push_layer(Recipe.affine(Vector3.ONE, Vector3(0.1, 0.0, 0.0)), 0, 0, 0x1)
	stack.push_layer(Recipe.affine(Vector3.ONE * 0.5, Vector3.ZERO), 0, 0, 0x2)
	stack.evaluate(0)
	_assert_eq(stack.count(), 2, "two distinct-mask layers stay separate")
	_assert_vec4_approx(stack.rgb1()[0], Vector4(0.1, 0.0, 0.0, 0.0), "layer 0 first")
	_assert_vec4_approx(stack.rgb0()[1], Vector4(0.5, 0.5, 0.5, 1.0), "layer 1 second (scale 0.5)")


## A luma layer packs delta5 into rgb0.xyz, div into rgb1.w (nonzero ⇒ luma), and
## the source into meta bit 3 (set ⇒ base, modes 6/7; clear ⇒ current, modes 2/3).
func _test_luma_layer_packs() -> void:
	var stack := Stack.new()
	stack.push_layer(Recipe.luma(12, Vector3i(4, 3, 1), true), 0, 0)   # from_base -> bit 3 set
	stack.push_layer(Recipe.luma(6, Vector3i(2, 1, 0), false), 0, 0)   # from_current -> bit 3 clear
	stack.evaluate(0)
	_assert_vec4_approx(stack.rgb0()[0], Vector4(4, 3, 1, 1.0), "luma rgb0 = (delta5, progress)")
	_assert_eq(stack.rgb1()[0].w, 12.0, "luma div in rgb1.w")
	_assert_eq(stack.meta()[0] & (1 << 3), (1 << 3), "from_base sets source bit 3")
	_assert_eq(stack.meta()[1] & (1 << 3), 0, "from_current clears source bit 3")


## Contiguous SETTLED (progress=1) affine layers of the same mask collapse to ONE
## packed entry via the symbolic merge — so repeated additive ops never overflow the
## 8-layer uniform budget. The merged affine == composing all three in order.
func _test_settled_affines_merge() -> void:
	var stack := Stack.new()
	# Three settled additive-ish affines: ×0.5, +0.1 R, ×2 all. Snap at frame 0.
	var a := Recipe.affine(Vector3(0.5, 0.5, 0.5), Vector3.ZERO)
	var b := Recipe.affine(Vector3.ONE, Vector3(0.1, 0.0, 0.0))
	var c := Recipe.affine(Vector3(2.0, 2.0, 2.0), Vector3.ZERO)
	stack.push_layer(a, 0, 0)
	stack.push_layer(b, 0, 0)
	stack.push_layer(c, 0, 0)
	stack.evaluate(0)
	_assert_eq(stack.count(), 1, "three settled affines merge to one entry")
	# Expected: merge(merge(a,b),c). scale = 0.5·1·2 = 1; bias = ((0·1+0.1)·2) = 0.2 R.
	var m: ColorRecipe = Recipe.merge(Recipe.merge(a, b), c)
	_assert_vec4_approx(stack.rgb0()[0], Vector4(m.scale.x, m.scale.y, m.scale.z, 1.0),
		"merged scale packed")
	_assert_vec4_approx(stack.rgb1()[0], Vector4(m.bias.x, m.bias.y, m.bias.z, 0.0),
		"merged bias packed")


## A luma layer is non-commutative and cannot fold into an affine, so it BREAKS the
## affine run: [affine, luma, affine] packs as three ordered entries (not merged
## across the luma), preserving interlacing.
func _test_luma_breaks_the_affine_run() -> void:
	var stack := Stack.new()
	stack.push_layer(Recipe.affine(Vector3.ONE, Vector3(0.1, 0.0, 0.0)), 0, 0)
	stack.push_layer(Recipe.luma(12, Vector3i(4, 3, 1), true), 0, 0)
	stack.push_layer(Recipe.affine(Vector3.ONE, Vector3(0.0, 0.2, 0.0)), 0, 0)
	stack.evaluate(0)
	_assert_eq(stack.count(), 3, "luma breaks the affine run -> 3 entries")
	_assert_eq(stack.rgb1()[1].w, 12.0, "middle entry is the luma")


## Only SETTLED affines merge; a still-ramping affine keeps its own entry so its
## live progress folds correctly. Two settled below + one mid-ramp on top -> 2 entries.
func _test_midramp_affine_stays_separate() -> void:
	var stack := Stack.new()
	stack.push_layer(Recipe.affine(Vector3(0.5, 0.5, 0.5), Vector3.ZERO), 0, 0)  # settled
	stack.push_layer(Recipe.affine(Vector3.ONE, Vector3(0.1, 0.0, 0.0)), 0, 0)   # settled
	stack.push_layer(Recipe.affine(Vector3.ONE, Vector3(0.0, 0.3, 0.0)), 0, 32)  # ramps
	stack.evaluate(8)  # top layer is 8/32 = 0.25 in
	_assert_eq(stack.count(), 2, "two settled merge, mid-ramp affine stays separate")
	_assert_eq(stack.rgb0()[1].w, 0.25, "mid-ramp entry keeps its progress")


## Records shader-parameter sets so we can assert what apply() pushes.
class FakeMaterial extends RefCounted:
	var params: Dictionary = {}
	func set_shader_parameter(name: String, value) -> void:
		params[name] = value


## apply(material, now) evaluates at `now` and pushes the full uniform contract:
## the four arrays (padded to the fixed uniform size), the live count, and the
## per-consumer quantization flag. The arrays are packed types the shader accepts.
func _test_apply_pushes_uniforms_to_material() -> void:
	var stack := Stack.new()
	stack.set_quantize(true)
	stack.push_layer(Recipe.affine(Vector3.ONE, Vector3(0.1, 0.2, 0.3)), 0, 0)
	var mat := FakeMaterial.new()
	stack.apply(mat, 0)
	_assert_eq(mat.params.get("color_layer_count"), 1, "pushed count")
	_assert_eq(mat.params.get("quantize"), true, "pushed quantize flag")
	var rgb0 = mat.params.get("color_layer_rgb0")
	_assert_true(rgb0 is PackedVector4Array, "rgb0 is a PackedVector4Array")
	_assert_eq(rgb0.size(), Stack.MAX_COLOR_LAYERS, "rgb0 padded to the fixed uniform size")
	_assert_vec4_approx(rgb0[0], Vector4(1.0, 1.0, 1.0, 1.0), "rgb0[0] = (scale, progress)")
	var meta = mat.params.get("color_layer_meta")
	_assert_true(meta is PackedInt32Array, "meta is a PackedInt32Array")
	_assert_eq(meta[0], 0x7, "meta[0] = whole-surface mask")


## apply_packed pushes PRE-EVALUATED concatenated layer arrays (the multi-owner
## overlay path): count = the concatenated length, arrays padded to the fixed size,
## quantize honored when non-empty.
func _test_apply_packed_concatenates_and_pads() -> void:
	var rgb0 := [Vector4(1, 1, 1, 1.0), Vector4(0.5, 0.5, 0.5, 1.0)]
	var rgb1 := [Vector4(0.1, 0.0, 0.0, 0.0), Vector4(0.0, 0.0, 0.0, 0.0)]
	var meta := [0x7, 0x1]
	var mat := FakeMaterial.new()
	Stack.apply_packed(mat, rgb0, rgb1, meta, true)
	_assert_eq(mat.params.get("color_layer_count"), 2, "apply_packed count = concatenated length")
	_assert_eq(mat.params.get("quantize"), true, "apply_packed honors quantize")
	var p0 = mat.params.get("color_layer_rgb0")
	_assert_eq(p0.size(), Stack.MAX_COLOR_LAYERS, "apply_packed pads rgb0 to fixed size")
	_assert_vec4_approx(p0[1], Vector4(0.5, 0.5, 0.5, 1.0), "apply_packed keeps entry 1")
	_assert_eq(mat.params.get("color_layer_meta")[0], 0x7, "apply_packed keeps meta 0")


## An empty layer list is a true no-op: count 0 AND quantize false, so an idle
## consumer doesn't 5-bit-quantize its base (the include quantizes even at count 0).
func _test_apply_packed_empty_is_noop() -> void:
	var mat := FakeMaterial.new()
	Stack.apply_packed(mat, [], [], [], true)
	_assert_eq(mat.params.get("color_layer_count"), 0, "apply_packed empty -> count 0")
	_assert_eq(mat.params.get("quantize"), false, "apply_packed empty -> quantize forced false")


## push_op is the driver entry: it reduces (mode, r, g, b) to a recipe and pushes a
## layer that ramps in over `time` from `now`. mode 0 R=8 -> additive {1, (8/31,0,0)}.
func _test_push_op_reduces_and_ramps_in() -> void:
	var stack := Stack.new()
	stack.push_op(0, 8, 0, 0, 4, 10)  # mode, r, g, b, time=4 (32 frames), now=10
	stack.evaluate(10)
	_assert_eq(stack.count(), 1, "push_op added a layer")
	_assert_eq(stack.rgb0()[0].w, 0.0, "ramps in from progress 0 at start")
	_assert_vec4_approx(stack.rgb1()[0], Vector4(8.0 / 31.0, 0.0, 0.0, 0.0), "reduced to affine bias=delta")
	stack.evaluate(26)  # 16/32 in
	_assert_eq(stack.rgb0()[0].w, 0.5, "progress 0.5 mid-ramp")
	stack.evaluate(42)
	_assert_eq(stack.rgb0()[0].w, 1.0, "progress 1 at end")


## fold_packed folds PRE-PACKED layer arrays over a base — the CPU readback oracle
## for a multi-owner snapshot (the unit-tint analog of fold(), which folds a live
## stack). It must reproduce fold() exactly for the same evaluated snapshot, so a
## concatenated unit stack can be checked byte-exact on the CPU without the GPU.
func _test_fold_packed_reproduces_fold() -> void:
	var stack := Stack.new()
	stack.set_quantize(true)
	stack.push_op(5, 252, 252, 252, 1, 0)   # mode-5 (base>>1)-4 dim
	stack.push_op(0, 4, 0, 0, 0, 0)         # +4R additive on top
	var base := Vector3(14.0, 10.0, 5.0) / 31.0
	stack.evaluate(8)
	var packed := Stack.fold_packed(stack.rgb0(), stack.rgb1(), stack.meta(), stack.count(), base, 0, true)
	_assert_vec_approx(packed, stack.fold(base, 0, 8), "fold_packed reproduces fold for the same snapshot")


## push_op routes luma modes to a luma layer (delta5/div/source), not affine.
func _test_push_op_luma() -> void:
	var stack := Stack.new()
	stack.push_op(7, 4, 3, 1, 0, 0)  # mode 7 = base luma /12, snap
	stack.evaluate(0)
	_assert_eq(stack.rgb1()[0].w, 12.0, "luma div=12 packed")
	_assert_vec4_approx(stack.rgb0()[0], Vector4(4, 3, 1, 1.0), "luma delta5 packed")
	_assert_eq(stack.meta()[0] & (1 << 3), (1 << 3), "mode 7 sets base source bit")


## A mode-8 "palette absolute" op is a RESTORE: it runs the active layers' progress
## back down to 0 over `time` (a cross-fade to base, not a new layer), and once it
## lands the layer is expired — it contributes nothing and drops from the packing.
func _test_mode8_restore_fades_out_then_expires() -> void:
	var stack := Stack.new()
	stack.push_op(7, 4, 3, 1, 0, 0)   # settled sepia luma at frame 0
	stack.evaluate(0)
	_assert_eq(stack.rgb0()[0].w, 1.0, "sepia settled at full progress")
	stack.push_op(8, 0, 0, 0, 4, 0)   # restore over 32 frames, from now=0
	stack.evaluate(0)
	_assert_eq(stack.rgb0()[0].w, 1.0, "restore starts at full sepia (progress 1)")
	stack.evaluate(16)
	_assert_eq(stack.rgb0()[0].w, 0.5, "restore fades progress downward (0.5)")
	stack.evaluate(32)
	_assert_eq(stack.count(), 0, "fully restored layer is expired (dropped)")
	# Seek back mid-fade re-derives the cross-fade (never accumulated).
	stack.evaluate(16)
	_assert_eq(stack.rgb0()[0].w, 0.5, "seek back re-derives the restore (0.5)")


## A restore (mode 8/10) that INTERRUPTS a still-fading-in layer must ease out from
## the layer's CURRENT progress, not snap it to full first. push a 32-frame fade-in,
## restore it at frame 8 (progress 0.25): the restore must start at 0.25 and run down
## to 0, never popping up to 1.0.
func _test_restore_midfade_fades_from_current_not_snap() -> void:
	var stack := Stack.new()
	stack.push_op(0, 8, 0, 0, 4, 0)   # additive affine, 32-frame ramp starting at now=0
	stack.evaluate(8)
	_assert_eq(stack.rgb0()[0].w, 0.25, "fade-in is 25% at frame 8")
	stack.push_op(8, 0, 0, 0, 4, 8)   # restore over 32 frames, from now=8, mid-fade
	stack.evaluate(8)
	_assert_eq(stack.rgb0()[0].w, 0.25, "restore starts at CURRENT progress (0.25), no snap to 1.0")
	stack.evaluate(24)
	_assert_eq(stack.rgb0()[0].w, 0.125, "restore eases down from 0.25 (half-way -> 0.125)")
	stack.evaluate(40)
	_assert_eq(stack.count(), 0, "restore fully run down -> layer expired")


## A restore captured LATER in a layer's life must not reach BACK and resurrect the
## frames between the layer's start and the restore. A mode-8 restore flips every prior
## layer `restoring` with restore_start = the restore op's frame; evaluating at a frame
## between the layer's start and restore_start must read the layer's NORMAL ramp
## progress, and the restore must only take effect at now >= restore_start. Without the
## `now >= restore_start` guard the restoring branch returns restore_from(=1.0) for those
## earlier frames — resurrecting the layer to full (the Holy/E015 map "clicking": the
## flood layer paints white for every frame between its start and the restore).
func _test_restore_does_not_resurrect_layer_before_restore_start() -> void:
	var stack := Stack.new()
	stack.push_op(4, 31, 31, 31, 4, 0)   # high-δ base affine, 32-frame ramp from now=0
	stack.evaluate(8)
	_assert_eq(stack.rgb0()[0].w, 0.25, "layer ramps normally pre-restore (0.25 at frame 8)")
	# A LATER mode-8 restore at frame 100, long after the layer settled.
	stack.push_op(8, 0, 0, 0, 4, 100)
	# The frame between start(0) and restore_start(100) must NOT snap to full.
	stack.evaluate(8)
	_assert_eq(stack.rgb0()[0].w, 0.25, "frame between start and restore is NOT resurrected to full")
	# The restore takes effect only from restore_start: 1.0 at the top of the ramp-down.
	stack.evaluate(100)
	_assert_eq(stack.rgb0()[0].w, 1.0, "restore begins at restore_start (progress 1.0)")
	stack.evaluate(116)
	_assert_eq(stack.rgb0()[0].w, 0.5, "restore fades down after restore_start (0.5)")


## The companion case where the restore is captured MID-FADE, so restore_from < 1.0 (the
## sibling of _test_restore_does_not_resurrect...: that one captures a SETTLED layer,
## restore_from=1.0). A layer at 0.5 progress restored at frame 16 must still show its
## NORMAL ramp for the pre-restore window [start, restore_start] on a backward seek — NOT
## be held at restore_from — and be continuous with restore_from at the restore boundary.
## Pre-fix the restoring branch returned restore_from (0.5) for the earlier frames instead
## of the ramp (0.25), so this pins the restore_from<1.0 corner the settled test can't.
func _test_restore_captured_midfade_shows_ramp_before_restore_start() -> void:
	var stack := Stack.new()
	stack.push_op(0, 8, 0, 0, 4, 0)   # 32-frame ramp from now=0
	stack.evaluate(16)
	_assert_eq(stack.rgb0()[0].w, 0.5, "layer is 50% at frame 16")
	stack.push_op(8, 0, 0, 0, 4, 16)  # restore captured mid-fade -> restore_from = 0.5
	# Seek BACK to a frame between start(0) and restore_start(16): natural ramp, not the hold.
	stack.evaluate(8)
	_assert_eq(stack.rgb0()[0].w, 0.25, "pre-restore frame shows the natural ramp (0.25), not restore_from (0.5)")
	# Continuous with restore_from at the boundary, then eases down from 0.5.
	stack.evaluate(16)
	_assert_eq(stack.rgb0()[0].w, 0.5, "restore begins at restore_from (0.5), continuous with the ramp")
	stack.evaluate(24)
	_assert_eq(stack.rgb0()[0].w, 0.375, "restore eases down from 0.5 (8/32 in -> 0.5*(1-0.25) = 0.375)")


## The E173 "red dip": a settled base-reading layer (mode 4/9) MASKS every layer below
## it — at full progress it reads `base` and ignores the colour-so-far, so a red tint
## underneath contributes nothing to the settled composite. PSX keeps ONE CLUT, so at
## the restore instant it already holds base and a mode-8 restore (base->base) is
## invisible. The stack model must match: when a restore ramps the mask's progress down,
## the shadowed red MUST NOT re-surface — the composite has to HOLD base across the whole
## restore window (no dark-red dip) and land expired at the end. Pre-fix the mask un-masks
## mid-ramp and the red idx below leaks back through (E173 Night Sword f110-118 on the map).
func _test_restore_holds_base_when_shadowed_by_settled_base_layer() -> void:
	var stack := Stack.new()
	stack.set_quantize(true)
	var base := Vector3(19, 19, 19) / 31.0  # exact 5-bit so the quantized fold is stable
	stack.push_op(5, 3, 229, 232, 0, 0)   # mode-5 red (base>>1 + delta), snap at f0 -> masked
	stack.push_op(4, 0, 0, 0, 0, 0)       # mode-4 base identity on top, snap -> masks the red
	# The settled composite is base: the top base-identity layer shadows the red beneath it.
	_assert_vec_approx(stack.fold(base, 0, 5), base, "settled composite is base (red is masked)")
	stack.push_op(8, 0, 0, 0, 1, 10)      # mode-8 restore over 8 frames from f10 (base->base)
	# Across the whole restore window the composite HOLDS base — the shadowed red never leaks.
	for f in [10, 11, 13, 15, 17]:
		_assert_vec_approx(stack.fold(base, 0, f), base, "restore holds base (no red dip) at f%d" % f)
	# Fully restored: every layer expired, composite is base.
	_assert_vec_approx(stack.fold(base, 0, 18), base, "composite is base after the restore")
	_assert_eq(stack.count(), 0, "both layers expired after the restore")


## A mode-10 reset with Time=0 snaps the stack clear immediately (no cross-fade).
func _test_mode10_reset_snaps_clear() -> void:
	var stack := Stack.new()
	stack.push_op(0, 8, 0, 0, 0, 0)   # settled additive
	stack.evaluate(0)
	_assert_eq(stack.count(), 1, "one layer before reset")
	stack.push_op(10, 0, 0, 0, 0, 0)  # reset snap
	stack.evaluate(0)
	_assert_eq(stack.count(), 0, "mode-10 reset snaps the stack clear")


## fold(base, surface_id, now) is the CPU mirror of the shader's color_apply —
## it folds the packed stack over a base colour the same way (used for {66} commit
## and as the byte-exact test oracle). A settled affine folds to base·scale+bias; a
## settled luma folds to luma_out5/31.
func _test_fold_affine_and_luma() -> void:
	var stack := Stack.new()
	stack.push_layer(Recipe.affine(Vector3(0.5, 0.5, 0.5), Vector3(0.1, 0.0, 0.0)), 0, 0)
	var base := Vector3(0.6, 0.4, 0.2)
	_assert_vec_approx(stack.fold(base, 0, 0), base * 0.5 + Vector3(0.1, 0.0, 0.0), "fold affine")

	var lstack := Stack.new()
	lstack.push_layer(Recipe.luma(12, Vector3i(4, 3, 1), true), 0, 0)
	var b5 := Vector3(11.0, 12.0, 10.0) / 31.0
	var want: Vector3i = Recipe.luma_out5(Vector3i(11, 12, 10), 12, Vector3i(4, 3, 1))
	_assert_vec_approx(lstack.fold(b5, 0, 0), Vector3(want) / 31.0, "fold luma from base")


## fold only applies layers whose surface mask includes surface_id (the same gate the
## shader uses). A weapon-only layer (mask 0x2) leaves surface 0 (body) untouched.
func _test_fold_respects_surface_mask() -> void:
	var stack := Stack.new()
	stack.push_layer(Recipe.affine(Vector3.ONE, Vector3(0.3, 0.0, 0.0)), 0, 0, 0x2)  # weapon only
	var base := Vector3(0.5, 0.5, 0.5)
	_assert_vec_approx(stack.fold(base, 0, 0), base, "body surface untouched by weapon-only layer")
	_assert_vec_approx(stack.fold(base, 1, 0), base + Vector3(0.3, 0.0, 0.0), "weapon surface tinted")


## Legacy reference: the exact fragment math unit.gdshader uses today for the
## composed {32}∘{33} effective tint (base_affine = ALBEDO·scale+bias; luma reads
## base_affine or ALBEDO; ALBEDO = mix(base_affine, luma_out, luma_mix)). The
## effective spec maps to ≤2 ColorStack layers (affine below + luma at progress=mix),
## and fold() must reproduce the reference across sample bases — the byte-exact guard
## that makes the slice-3 shader port a no-op. Specs are the scn8 sepia (mode7) values.
func _legacy_unit_albedo(albedo: Vector3, scale: Vector3, bias: Vector3, luma_div: int,
		delta5: Vector3i, from_current: bool, luma_mix: float) -> Vector3:
	var base_affine := albedo * scale + bias
	if luma_div == 0:
		return base_affine
	var luma_src := base_affine.clamp(Vector3.ZERO, Vector3.ONE) if from_current else albedo
	var s5 := Vector3i((luma_src.clamp(Vector3.ZERO, Vector3.ONE) * 31.0).round())
	var luma_out := Vector3(Recipe.luma_out5(s5, luma_div, delta5)) / 31.0
	return base_affine.lerp(luma_out, luma_mix)


## Build the ≤2-layer stack that reproduces a unit's effective spec, matching the old
## shader path. Mirrors the slice-3 translation ScenarioVM will do.
func _stack_from_eff(scale: Vector3, bias: Vector3, luma_div: int, delta5: Vector3i,
		from_current: bool, luma_mix: float) -> Stack:
	var stack := Stack.new()
	stack.push_fixed_layer(Recipe.affine(scale, bias), 1.0)  # base_affine (fully applied)
	if luma_div > 0:
		var luma := Recipe.luma(luma_div, delta5, not from_current)  # from_base = not from_current
		stack.push_fixed_layer(luma, luma_mix)  # progress = the cross-fade weight
	return stack


func _test_fold_matches_legacy_unit_shader_math() -> void:
	var bases := [Vector3(0.6, 0.4, 0.2), Vector3(0.0, 1.0, 0.5), Vector3(0.13, 0.35, 0.9),
		Vector3(1.0, 1.0, 1.0), Vector3(0.03, 0.03, 0.03)]
	# [scale, bias, div, delta5, from_current, mix] — affine door-fade, sepia snap, sepia mid-fade.
	var specs := [
		[Vector3(0.5, 0.5, 0.5), Vector3.ZERO, 0, Vector3i.ZERO, false, 1.0],       # {32} mode1 dim
		[Vector3.ONE, Vector3.ZERO, 12, Vector3i(4, 2, -1), false, 1.0],            # mode7 sepia (base)
		[Vector3.ONE, Vector3.ZERO, 12, Vector3i(4, 3, 1), false, 0.5],             # sepia mid-restore
		[Vector3.ONE, Vector3(0.1, 0.0, -0.1), 6, Vector3i(2, 1, 0), true, 1.0],    # mode2 current-luma over affine
	]
	for spec in specs:
		var stack := _stack_from_eff(spec[0], spec[1], spec[2], spec[3], spec[4], spec[5])
		for base in bases:
			var got: Vector3 = stack.fold(base, 0, 0)
			var want: Vector3 = _legacy_unit_albedo(base, spec[0], spec[1], spec[2], spec[3], spec[4], spec[5])
			_assert_vec_approx(got, want, "fold == legacy shader (div=%d mix=%s base=%s)" % [spec[2], str(spec[5]), str(base)])


## Legacy reference: the exact field-tint math indexed_color.gdshader uses (the map's
## {33} broadcast is a SINGLE affine-or-luma layer). Affine CLAMPS the result (the map
## can take an additive field, scn8 idx270 mode-0); luma is mix(base, luma_out, mix).
func _legacy_field_rgb(rgb: Vector3, scale: Vector3, bias: Vector3, luma_div: int,
		delta5: Vector3i, luma_mix: float) -> Vector3:
	if luma_div == 0:
		return (rgb * scale + bias).clamp(Vector3.ZERO, Vector3.ONE)
	var s5 := Vector3i((rgb.clamp(Vector3.ZERO, Vector3.ONE) * 31.0).round())
	var luma_out := Vector3(Recipe.luma_out5(s5, luma_div, delta5)) / 31.0
	return rgb.lerp(luma_out, luma_mix)


## The map field is ONE ColorStack layer: affine {scale,bias} at progress 1, or a
## base-source luma at progress = the cross-fade weight. clamp(fold(...)) must match
## the legacy field shader across bases (the map path clamps the affine to [0,1]).
func _test_fold_matches_legacy_field_shader_math() -> void:
	var bases := [Vector3(0.6, 0.4, 0.2), Vector3(0.9, 0.9, 0.9), Vector3(0.13, 0.35, 0.9), Vector3(0.0, 0.5, 0.32)]
	var specs := [
		[Vector3(0.5, 0.5, 0.5), Vector3.ZERO, 0, Vector3i.ZERO, 1.0],          # door-dim affine
		[Vector3.ONE, Vector3(0.3, 0.3, 0.3), 0, Vector3i.ZERO, 1.0],           # additive field (overflows -> clamp)
		[Vector3.ONE, Vector3.ZERO, 12, Vector3i(4, 3, 1), 1.0],               # mode7 sepia field (base luma)
		[Vector3.ONE, Vector3.ZERO, 12, Vector3i(4, 3, 1), 0.5],               # sepia field mid-restore
	]
	for spec in specs:
		var stack := Stack.new()
		if spec[2] == 0:
			stack.push_fixed_layer(Recipe.affine(spec[0], spec[1]), 1.0)
		else:
			stack.push_fixed_layer(Recipe.luma(spec[2], spec[3], true), spec[4])  # field luma reads base
		for base in bases:
			var got: Vector3 = stack.fold(base, 0, 0).clamp(Vector3.ZERO, Vector3.ONE)
			var want: Vector3 = _legacy_field_rgb(base, spec[0], spec[1], spec[2], spec[3], spec[4])
			_assert_vec_approx(got, want, "field fold == legacy (div=%d mix=%s base=%s)" % [spec[2], str(spec[4]), str(base)])


## Combat tints (screen_background, unit_tint, map_tint) are additive DELTAS applied
## `color + delta` — the ADR-0067 "additive = scale=1 affine" special case. A single
## affine {scale=1, bias=delta} layer folds to exactly base + delta (UNCLAMPED, matching
## screen_background.gdshader which only clamps negatives at the dither stage). This is
## the whole combat model: ScreenEffectOverlay/overlays already sum per-owner deltas to
## ONE delta, so ONE layer suffices.
func _test_fold_matches_legacy_additive_combat_tint() -> void:
	var bases := [Vector3(0.6, 0.4, 0.2), Vector3(0.9, 0.1, 0.5), Vector3(0.0, 0.0, 0.0)]
	var deltas := [Vector3(0.2, 0.0, -0.1), Vector3(0.5, 0.5, 0.5), Vector3(-0.3, 0.1, 0.0)]
	for delta in deltas:
		var stack := Stack.new()
		stack.push_fixed_layer(Recipe.affine(Vector3.ONE, delta), 1.0)
		for base in bases:
			_assert_vec_approx(stack.fold(base, 0, 0), base + delta,
				"additive combat fold == base + delta (delta=%s base=%s)" % [str(delta), str(base)])


## The {66} Commit Palette bake — fold the stack over every palette entry and quantize
## to 5-bit in place, redefining base. commit_bake must reproduce the legacy affine bake
## `entry5 -> clamp(round(entry5*scale + bias*31), 0, 31)` byte-exact (the map-hue commit).
func _test_commit_bake_affine_byte_exact() -> void:
	var scale := Vector3(0.5, 1.0, 1.0)
	var bias := Vector3(0.0, 4.0 / 31.0, 8.0 / 31.0)
	# 3 entries at known 5-bit values.
	var src := Image.create(3, 1, false, Image.FORMAT_RGBA8)
	var entries := [Vector3i(20, 10, 6), Vector3i(31, 0, 15), Vector3i(4, 16, 30)]
	for i in range(3):
		var e: Vector3i = entries[i]
		src.set_pixel(i, 0, Color(e.x / 31.0, e.y / 31.0, e.z / 31.0, 1.0))
	var stack := Stack.new()
	stack.push_fixed_layer(Recipe.affine(scale, bias), 1.0)
	var baked := stack.commit_bake(src, 0)
	for i in range(3):
		var e: Vector3i = entries[i]
		var want := Vector3i(
			clampi(roundi(e.x * scale.x + bias.x * 31.0), 0, 31),
			clampi(roundi(e.y * scale.y + bias.y * 31.0), 0, 31),
			clampi(roundi(e.z * scale.z + bias.z * 31.0), 0, 31))
		var p := baked.get_pixel(i, 0)
		var got := Vector3i(roundi(p.r * 31.0), roundi(p.g * 31.0), roundi(p.b * 31.0))
		_assert_eq(got, want, "commit_bake affine entry %d byte-exact" % i)
		_assert_eq(p.a, 1.0, "commit_bake preserves alpha entry %d" % i)


## Because commit routes through fold, it generalizes to a luma field for free (the old
## affine-only bake couldn't): committing a base-luma recipe bakes luma_out5 per entry.
func _test_commit_bake_generalizes_to_luma() -> void:
	var src := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	src.set_pixel(0, 0, Color(11.0 / 31.0, 12.0 / 31.0, 10.0 / 31.0, 1.0))
	var stack := Stack.new()
	stack.push_fixed_layer(Recipe.luma(12, Vector3i(4, 3, 1), true), 1.0)
	var baked := stack.commit_bake(src, 0)
	var want: Vector3i = Recipe.luma_out5(Vector3i(11, 12, 10), 12, Vector3i(4, 3, 1))
	var p := baked.get_pixel(0, 0)
	var got := Vector3i(roundi(p.r * 31.0), roundi(p.g * 31.0), roundi(p.b * 31.0))
	_assert_eq(got, want, "commit_bake luma entry bakes luma_out5")


## The commit source is a real BGR555 CLUT stored in an RGBA8 texture, so get_pixel()
## returns byte/255, NOT exactly n/31. The PSX committer (and the deleted inline
## bake_field_tint) quantize each entry to its true 5-bit value BEFORE the affine —
## `entry5 -> clamp(round(entry5*scale + bias*31), 0, 31)`. commit_bake must do the
## same: fold the SNAPPED 5-bit source, not the raw 8-bit sample. Swept over all 32
## source levels at scale=0.5, where the raw-8-bit path drifts off-by-1 on ~12 of 32.
func _test_commit_bake_snaps_source_to_5bit_before_affine() -> void:
	var scale := Vector3(0.5, 0.5, 0.5)
	var src := Image.create(32, 1, false, Image.FORMAT_RGBA8)
	for n in range(32):
		src.set_pixel(n, 0, Color(n / 31.0, n / 31.0, n / 31.0, 1.0))  # stored as round(n/31*255)/255
	var stack := Stack.new()
	stack.push_fixed_layer(Recipe.affine(scale, Vector3.ZERO), 1.0)
	var baked := stack.commit_bake(src, 0)
	for n in range(32):
		var want := clampi(roundi(n * 0.5), 0, 31)  # 5-bit source first, then affine
		var p := baked.get_pixel(n, 0)
		var got := roundi(p.r * 31.0)
		_assert_eq(got, want, "commit_bake snaps source %d to 5-bit before x0.5 (want %d)" % [n, want])
