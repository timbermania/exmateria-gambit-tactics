extends Node
## Tests for PaletteSubsystem's combat-colour path — ADR-0067's deferred combat
## unification (issue #164). The subsystem is being routed OFF the additive
## `unit_tint`/`map_tint` delta uniform and ONTO the unified ColorStack seam
## (`color_apply`), so combat effects fold over the real ALBEDO base at 5-bit
## fidelity, byte-exact to the PSX palette applier `color_tint_blend_apply
## @0x8008f710`. The engine (ColorRecipe/ColorStack) is already proven byte-exact
## (227/227, ColorStackTest); these tests pin that PaletteSubsystem DRIVES it
## faithfully from parsed keyframes.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/PaletteSubsystemTest.tscn

const PaletteSubsystem = ExMateriaEffects.PaletteSubsystem
const PaletteData = ExMateriaEffects.PaletteData
const Recipe = ExMateriaSchema.ColorRecipe
const EffectPhase = ExMateriaEffects.EffectPhase
const ColorStack = ExMateriaSchema.ColorStack


## Records what the overlay concatenated + pushed to a unit material, so we can fold
## the DELIVERED caster/target tint back on the CPU (via ColorStack.fold_packed).
class FakeMaterial extends RefCounted:
	var params: Dictionary = {}
	func set_shader_parameter(name: String, value) -> void:
		params[name] = value

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_additive_mode0_folds_base_plus_delta()
	_test_mode1_halve_then_add()
	_test_luma_mode2_folds_over_real_base()
	_test_luma_mode6_reads_base_not_current()
	_test_mode4_reads_absolute_base_not_bare_param()
	_test_consecutive_mode4_is_idempotent()
	_test_consecutive_mode5_is_idempotent()
	_test_mode4_run_then_mode8_restores_to_base()
	_test_disabled_keyframe_contributes_nothing()
	_test_respects_max_keyframe_window()
	_test_time_value_drives_the_ramp()
	_test_mode8_restore_fades_back_to_base()
	_test_mode10_clear_snaps_to_base()
	_test_future_snap_keyframe_inactive_before_its_start()
	_test_snap_keyframe_activates_at_its_start()
	_test_future_snap_inactive_before_start_even_when_later_restored()
	_test_map_stream_is_continuous_across_phase_seam()
	_test_map_stream_phase2_restore_fades_earlier_phase_layers()
	_test_map_stream_single_phase_matches_build_stack()
	_test_map_advance_records_phase_starts_and_delivers_continuous_tint()
	_test_caster_unit_tint_continuous_across_phase_seam()
	_test_advance_does_not_deliver_map_illumination_to_textured_map()

	print("\n=== PaletteSubsystemTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] PaletteSubsystemTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] PaletteSubsystemTest")
		get_tree().quit(1)
	else:
		print("[PASS] PaletteSubsystemTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_vec_approx(got: Vector3, want: Vector3, name: String) -> void:
	if got.is_equal_approx(want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


## Assert `got` is no brighter than `ref` in any channel (got <= ref per channel,
## within an epsilon) — the "no pop" invariant for a monotonic dim.
func _assert_not_brighter(got: Vector3, ref: Vector3, name: String) -> void:
	var eps := 0.0005
	if got.x <= ref.x + eps and got.y <= ref.y + eps and got.z <= ref.z + eps:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s is brighter than ref=%s" % [name, str(got), str(ref)])


# --- fixture -----------------------------------------------------------------

## Build a PaletteData with one channel (default caster) carrying the given
## keyframes in the for_each phase. Each keyframe dict is
## {mode, r, g, b, time?, dur?, enabled?}.
func _palette_with(keyframes: Array, channel: String = PaletteData.CASTER,
		max_keyframe: int = -1) -> PaletteData:
	var kf_json := []
	for i in range(keyframes.size()):
		var k: Dictionary = keyframes[i]
		var mode: int = k.get("mode", 0)
		var enabled: bool = k.get("enabled", true)
		# ctrl = bit7 enable | blend_mode in low bits (matches the parser's split).
		var ctrl: int = (0x80 if enabled else 0x00) | mode
		kf_json.append({
			"index": i,
			"time_value": k.get("time", 0),
			"duration_frames": k.get("dur", 1),
			"rgb": [k.get("r", 0), k.get("g", 0), k.get("b", 0)],
			"ctrl": ctrl,
			"enabled": enabled,
			"blend_mode": mode,
		})
	# max_keyframe bounds the processing window: the PSX applies indices
	# 0..max_keyframe-2. Default gives room to process every keyframe we authored.
	var mk: int = max_keyframe if max_keyframe >= 0 else keyframes.size() + 1
	var data := {
		"for_each": {
			channel: {
				"context": "for_each",
				"channel_name": channel,
				"max_keyframe": mk,
				"keyframes": kf_json,
			}
		}
	}
	return PaletteData.from_json(data)


## Build a PaletteData spanning MULTIPLE phase contexts for one channel — the
## cross-phase continuity fixture. `phase_kfs` maps a phase name (phase1 / for_each
## / phase2) to its keyframe list (same dict shape as _palette_with). Each phase's
## max_keyframe defaults to size+1 (apply every authored kf).
func _palette_multiphase(phase_kfs: Dictionary, channel: String = PaletteData.AFFECTED_UNITS) -> PaletteData:
	var data := {}
	for phase in phase_kfs.keys():
		var keyframes: Array = phase_kfs[phase]
		var kf_json := []
		for i in range(keyframes.size()):
			var k: Dictionary = keyframes[i]
			var mode: int = k.get("mode", 0)
			var enabled: bool = k.get("enabled", true)
			var ctrl: int = (0x80 if enabled else 0x00) | mode
			kf_json.append({
				"index": i,
				"time_value": k.get("time", 0),
				"duration_frames": k.get("dur", 1),
				"rgb": [k.get("r", 0), k.get("g", 0), k.get("b", 0)],
				"ctrl": ctrl,
				"enabled": enabled,
				"blend_mode": mode,
			})
		data[phase] = {
			channel: {
				"context": phase,
				"channel_name": channel,
				"max_keyframe": keyframes.size() + 1,
				"keyframes": kf_json,
			}
		}
	return PaletteData.from_json(data)


# --- tests -------------------------------------------------------------------

## Tracer bullet: a single enabled additive (mode 0) keyframe drives a ColorStack
## whose fold over a 5-bit base albedo == base + delta, on the 5-bit grid. This is
## the additive-stays-faithful anchor: palette params are 5-bit deltas over 5-bit
## CLUT entries, so base + delta stays exactly on-grid (quantize is a no-op here).
func _test_additive_mode0_folds_base_plus_delta() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([{"mode": 0, "r": 4, "g": 0, "b": 0}]))
	var stack = pal.build_stack(PaletteData.CASTER)
	# 5-bit base albedo: (10, 12, 20)/31.
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	var want := Vector3(14.0, 12.0, 20.0) / 31.0  # +4/31 R, on grid
	_assert_vec_approx(stack.fold(base, 0, 0), want, "mode0 additive folds base+delta (5-bit)")


## Mode 1 halves the surface then adds the param — dim-then-tint. Folds to
## base*0.5 + delta (5-bit). Even base entries halve exactly, so the value is
## unambiguous on the grid.
func _test_mode1_halve_then_add() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([{"mode": 1, "r": 4, "g": 0, "b": 0}]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	var want := Vector3(9.0, 6.0, 10.0) / 31.0  # (5,6,10) + (4,0,0)
	_assert_vec_approx(stack.fold(base, 0, 0), want, "mode1 folds base*0.5 + delta")


## Luma mode 2 mixes the colour-so-far to a single luminance in 5-bit space then
## adds the per-channel delta — the sepia/grey wash. For a lone keyframe the
## colour-so-far IS the base, so it folds over the REAL base albedo (the fix: the
## old delta-domain path lumad a base of 0). Byte-exact to ColorRecipe.luma_out5.
func _test_luma_mode2_folds_over_real_base() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([{"mode": 2, "r": 2, "g": 1, "b": 0}]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base5 := Vector3i(10, 12, 20)
	var base := Vector3(base5) / 31.0
	var want: Vector3i = Recipe.luma_out5(base5, 6, Vector3i(2, 1, 0))  # L=76/6=12 -> (14,13,12)
	_assert_vec_approx(stack.fold(base, 0, 0), Vector3(want) / 31.0, "mode2 luma folds over real base")


## Mode 6 luma reads the BASE colour, not the colour-so-far — so a preceding
## additive layer must NOT change its luminance source. Push additive +8R then a
## mode-6 luma: the luma must come out from base (L=12), not from base+8R (L=15).
## This is the base-source distinction the old flat float-luma path couldn't make.
func _test_luma_mode6_reads_base_not_current() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([
		{"mode": 0, "r": 8, "g": 0, "b": 0},   # current becomes base + 8R
		{"mode": 6, "r": 0, "g": 0, "b": 0},   # luma from BASE, no delta
	]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base5 := Vector3i(10, 12, 20)
	var base := Vector3(base5) / 31.0
	var want: Vector3i = Recipe.luma_out5(base5, 6, Vector3i.ZERO)  # (12,12,12) from base
	_assert_vec_approx(stack.fold(base, 0, 1), Vector3(want) / 31.0, "mode6 luma reads base not current")


## Modes 4-7 read the ABSOLUTE base (the committed palette), not delta-on-0. Mode
## 4 folds to base + param. The old subsystem short-circuited 4/5/6/7 to the bare
## param (base=0) — this proves the route reads the real base instead.
func _test_mode4_reads_absolute_base_not_bare_param() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([{"mode": 4, "r": 4, "g": 0, "b": 0}]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	var want := Vector3(14.0, 12.0, 20.0) / 31.0  # base + param, NOT bare param
	_assert_vec_approx(stack.fold(base, 0, 0), want, "mode4 folds absolute base + param")


## The regression guard (issue #164 / Cure blowout): modes 4/5/9 read the ABSOLUTE
## committed base, so N consecutive same-param keyframes of an absolute-base mode are
## IDEMPOTENT — all fold to `base + delta`, never `base + N·delta`. Real combat
## timelines (E001 Cure) push ~10 consecutive mode-4 keyframes; if each read the
## running colour they'd accumulate to white and hold. Two enabled mode-4 keyframes
## must fold to base + delta once, not twice. now=2 so both layers are settled.
func _test_consecutive_mode4_is_idempotent() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([
		{"mode": 4, "r": 6, "g": 0, "b": 0},   # base + 6R
		{"mode": 4, "r": 6, "g": 0, "b": 0},   # base + 6R again — NOT base + 12R
	]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	var want := Vector3(16.0, 12.0, 20.0) / 31.0  # base + 6R (idempotent), NOT +12R
	_assert_vec_approx(stack.fold(base, 0, 2), want, "two mode-4 keyframes are idempotent (base+delta, not base+2·delta)")


## Mode 5 is the halve-then-add absolute-base mode (`(base>>1) + delta`), so it is
## idempotent for the same reason as mode 4 — the `affected_units` channel of E001 is
## dominated by ~15 consecutive mode-5 keyframes. Two must fold to base*0.5 + delta
## once, not base*0.25 + 1.5·delta (what current-source accumulation would give).
func _test_consecutive_mode5_is_idempotent() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([
		{"mode": 5, "r": 4, "g": 0, "b": 0},
		{"mode": 5, "r": 4, "g": 0, "b": 0},
	]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	var want := Vector3(9.0, 6.0, 10.0) / 31.0  # (5,6,10) + (4,0,0) once
	_assert_vec_approx(stack.fold(base, 0, 2), want, "two mode-5 keyframes are idempotent (base*0.5+delta)")


## A run of absolute-base tints followed by a mode-8 restore releases cleanly back to
## base — the real Cure shape (tint ramp, hold, restore). Even accumulated-then-fixed,
## the mode-8 restore fades every active layer to base, so once it completes the
## surface is bare base again (no residual white).
func _test_mode4_run_then_mode8_restores_to_base() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([
		{"mode": 4, "r": 6, "g": 0, "b": 0},               # base + 6R (frame 0, dur 1)
		{"mode": 4, "r": 6, "g": 0, "b": 0},               # base + 6R again (frame 1, dur 1)
		{"mode": 8, "r": 0, "g": 0, "b": 0, "time": 4},    # restore over 32 frames from frame 2
	]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	var want_tint := Vector3(16.0, 12.0, 20.0) / 31.0  # idempotent base + 6R at restore start
	_assert_vec_approx(stack.fold(base, 0, 2), want_tint, "mode-4 run is base+delta at restore start")
	_assert_vec_approx(stack.fold(base, 0, 34), base, "mode-8 restore releases the run back to base")


## A disabled keyframe (ctrl bit 7 clear) makes NO apply call on the PSX — the
## builder must skip it, not push a phantom layer. A lone disabled mode-0 keyframe
## leaves the base untouched.
func _test_disabled_keyframe_contributes_nothing() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([{"mode": 0, "r": 4, "g": 0, "b": 0, "enabled": false}]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	_assert_vec_approx(stack.fold(base, 0, 0), base, "disabled keyframe leaves base untouched")
	_assert_eq(stack.count(), 0, "disabled keyframe pushes no layer")  # fold() evaluated the stack


## The PSX applies only keyframe indices 0..max_keyframe-2; indices at or past
## max_keyframe-1 are terminators/padding and never applied. With two authored
## keyframes but max_keyframe=2, only index 0 is applied.
func _test_respects_max_keyframe_window() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([
		{"mode": 0, "r": 4, "g": 0, "b": 0},   # index 0 — applied
		{"mode": 0, "r": 8, "g": 0, "b": 0},   # index 1 — past window, ignored
	], PaletteData.CASTER, 2))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	var want := Vector3(14.0, 12.0, 20.0) / 31.0  # base + 4R only (not +12R)
	_assert_vec_approx(stack.fold(base, 0, 1), want, "only index 0 applied within max_keyframe window")


## The keyframe's time_value drives the DDA ramp (Time>=4 → 32-frame slow fade).
## A mode-0 +8R over 32 frames folds to base at the start, base + delta/2 halfway,
## and base + delta at the end — re-derived at any `now` (seek/rewind for free).
func _test_time_value_drives_the_ramp() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([{"mode": 0, "r": 8, "g": 0, "b": 0, "time": 4, "dur": 32}]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	_assert_vec_approx(stack.fold(base, 0, 0), base, "ramp: base at start (progress 0)")
	_assert_vec_approx(stack.fold(base, 0, 16), Vector3(14.0, 12.0, 20.0) / 31.0, "ramp: base+delta/2 halfway")
	_assert_vec_approx(stack.fold(base, 0, 32), Vector3(18.0, 12.0, 20.0) / 31.0, "ramp: base+delta at end")


## Mode 8 (palette-absolute restore) fades the active layers back to base over its
## Time, then expires them — the tint releases. Evaluated forward from the restore
## frame: full tint at the restore start, half-way back mid-fade, bare base at the end.
func _test_mode8_restore_fades_back_to_base() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([
		{"mode": 0, "r": 8, "g": 0, "b": 0},               # settled additive at frame 0 (dur 1)
		{"mode": 8, "r": 0, "g": 0, "b": 0, "time": 4},    # restore over 32 frames from frame 1
	]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	_assert_vec_approx(stack.fold(base, 0, 1), Vector3(18.0, 12.0, 20.0) / 31.0, "full tint at restore start")
	_assert_vec_approx(stack.fold(base, 0, 17), Vector3(14.0, 12.0, 20.0) / 31.0, "restore half-way back to base")
	_assert_vec_approx(stack.fold(base, 0, 33), base, "restore fully released -> bare base")


## Mode 10 (reset/clear) snaps the stack clear immediately — no cross-fade.
func _test_mode10_clear_snaps_to_base() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([
		{"mode": 0, "r": 8, "g": 0, "b": 0},   # settled additive at frame 0
		{"mode": 10, "r": 0, "g": 0, "b": 0},  # clear at frame 1
	]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	_assert_vec_approx(stack.fold(base, 0, 1), base, "mode10 clear snaps stack to base")
	_assert_eq(stack.count(), 0, "mode10 clear leaves no active layer")


## The Ramuh whiteout (issue #164 follow-up), in miniature: a keyframe scheduled
## for a LATER frame must not affect the fold before its start_frame. A snap
## keyframe (Time=0 → 0-frame ramp) was wrongly active at every `now`, even before
## its start_frame, because the DDA reads "0-length ramp == fully applied" without
## checking it has STARTED. So a white keyframe authored at frame 10 painted the map
## white from frame 0 — and being the last absolute-base op, it won the merge and held.
## Here: a mild +4R tint at frame 0 then a white snap at frame 10; folded at now=0 the
## surface must be base+4R, NOT the not-yet-reached white.
func _test_future_snap_keyframe_inactive_before_its_start() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([
		{"mode": 0, "r": 4, "g": 0, "b": 0, "dur": 10},        # frame 0, spans [0,10)
		{"mode": 4, "r": 31, "g": 31, "b": 31, "time": 0},     # white snap at frame 10
	]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	var want := Vector3(14.0, 12.0, 20.0) / 31.0  # base + 4R only — the white hasn't started
	_assert_vec_approx(stack.fold(base, 0, 0), want, "future snap keyframe is inactive before its start_frame")


## The complement / boundary of the fix: a snap keyframe activates EXACTLY at its
## start_frame — inactive at start-1, applied from start onward (so the transient
## flash still lands on schedule, we didn't just disable future layers wholesale).
func _test_snap_keyframe_activates_at_its_start() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([
		{"mode": 0, "r": 4, "g": 0, "b": 0, "dur": 10},        # frame 0, spans [0,10)
		{"mode": 4, "r": 31, "g": 31, "b": 31, "time": 0},     # white snap at frame 10
	]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	var tint := Vector3(14.0, 12.0, 20.0) / 31.0  # base + 4R, white not yet reached
	var white := Vector3.ONE
	_assert_vec_approx(stack.fold(base, 0, 9), tint, "snap inactive the frame before its start")
	_assert_vec_approx(stack.fold(base, 0, 10), white, "snap active exactly at its start_frame")
	_assert_vec_approx(stack.fold(base, 0, 40), white, "snap holds after its start (until superseded/restored)")


## The Meteor (E047) whiteout: same "active before its start_frame" bug reached via a
## SECOND path. E047's phase carries a mode-8 restore AFTER a late white snap; when
## build_stack pushes the mode-8 op, `_restore` flips EVERY prior layer `restoring`
## (restore_start = the restore op's start_frame). The restoring branch of progress_at
## sits above the round-1 start-frame guard, so folded at now=0 the white layer returns
## restore_from(1.0) — fully white before frame 0 — and, being the last absolute-base op,
## wins the merge and holds the map white almost the whole effect. The fix hoists the
## start-frame guard above the restoring branch: a layer that hasn't started is 0,
## restoring or not. Folded at now=0 the surface must be base+4R, NOT white.
func _test_future_snap_inactive_before_start_even_when_later_restored() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_with([
		{"mode": 0, "r": 4, "g": 0, "b": 0, "dur": 10},        # frame 0, spans [0,10)
		{"mode": 4, "r": 31, "g": 31, "b": 31, "time": 0},     # white snap at frame 10
		{"mode": 8, "r": 0, "g": 0, "b": 0, "time": 4},        # restore (32-frame FADE) at frame 11 -> flips all layers restoring
	]))
	var stack = pal.build_stack(PaletteData.CASTER)
	var base := Vector3(10.0, 12.0, 20.0) / 31.0
	var want := Vector3(14.0, 12.0, 20.0) / 31.0  # base + 4R only — the white hasn't started
	# Before the fix this folds to WHITE at now=0: the restoring branch returns
	# restore_from(1.0) because the fade hasn't begun (now - restore_start is negative),
	# so the not-yet-started white snap is fully active and wins the absolute-base merge.
	_assert_vec_approx(stack.fold(base, 0, 0), want, "future snap stays inactive at now=0 even when a later mode-8 restores it")


## The phase-boundary POP (map color parity, Raise/E005): the PSX color engine has
## NO phase concept — it's one stateful CLUT DDA. Godot chops color into phase blocks
## (phase1/for_each/phase2) and, evaluating each per-phase at a phase-relative clock
## that RESETS at every boundary, a freshly-rebuilt stack's first layer at progress 0
## folds as identity ⇒ the map POPS back to full-bright base for a frame at the seam,
## then re-dims. `build_stream` fixes this: it concatenates the phase blocks into ONE
## continuous stack at their ABSOLUTE frame offsets, so phase1's settled dim is STILL
## present when for_each's identical dim fades in on top — no gap, no pop. E005 map:
## phase1 dims to (base>>1)+(-4,-4,-4); for_each idx0 re-dims to the same target.
## Base (14,10,5) -> dim target (3,1,0). Across the seam @ frame 8 the fold must stay
## dimmed, NOT return to (14,10,5).
func _test_map_stream_is_continuous_across_phase_seam() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_multiphase({
		"phase1": [{"mode": 5, "r": 252, "g": 252, "b": 252, "time": 1, "dur": 8}],   # (base>>1)-4
		"for_each": [{"mode": 5, "r": 252, "g": 252, "b": 252, "time": 1, "dur": 8}], # same dim, re-issued
	}, PaletteData.AFFECTED_UNITS))
	# Phase starts as the subsystem observes them: phase1 @0, for_each @8 (phase1_duration).
	var phase_starts := {"phase1": 0, "for_each": 8}
	var stack = pal.build_stream(PaletteData.AFFECTED_UNITS, phase_starts)
	var base := Vector3(14.0, 10.0, 5.0) / 31.0
	# The dim is monotonic RIGHT THROUGH the seam: no frame is brighter than the one
	# before it across frames 6->7->8->9. A per-phase rebuild pops frame 8 back to base
	# (14,10,5) — brighter than frame 7 — which this catches.
	var f6 := stack.fold(base, 0, 6)
	var f7 := stack.fold(base, 0, 7)
	var f8 := stack.fold(base, 0, 8)   # the phase1->for_each seam
	var f9 := stack.fold(base, 0, 9)
	_assert_not_brighter(f7, f6, "frame 7 not brighter than 6")
	_assert_not_brighter(f8, f7, "no pop AT the seam: frame 8 not brighter than 7")
	_assert_not_brighter(f9, f8, "frame 9 (into for_each) not brighter than 8")
	# And the seam frame sits at the dim target (3,1,0), NOT the popped-back base (14,10,5).
	_assert_vec_approx(f8, Vector3(3.0, 1.0, 0.0) / 31.0, "seam frame holds the dim target (3,1,0), no pop to base")


## The for_each->phase2 seam: phase2 idx0 is a mode-8 restore (E005 snaps the map
## back to base at the end). Because build_stream puts phase2's op in the SAME stack
## as the earlier dim layers, the mode-8 restore FADES those real layers back to base
## over its Time — the faithful "continue then release". A per-phase rebuild can't:
## phase2's fresh stack has no layers to restore, so the map would already have popped
## to base and the restore is a no-op. Here: phase1 dims to (3,1,0) and holds; phase2's
## mode-8 (32-frame fade) at frame 20 releases it back to base by frame 52.
func _test_map_stream_phase2_restore_fades_earlier_phase_layers() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_multiphase({
		"phase1": [{"mode": 5, "r": 252, "g": 252, "b": 252, "time": 1, "dur": 8}],  # dim, holds settled
		"phase2": [{"mode": 8, "r": 0, "g": 0, "b": 0, "time": 4}],                  # restore over 32 frames
	}, PaletteData.AFFECTED_UNITS))
	var stack = pal.build_stream(PaletteData.AFFECTED_UNITS, {"phase1": 0, "phase2": 20})
	var base := Vector3(14.0, 10.0, 5.0) / 31.0
	var dim := Vector3(3.0, 1.0, 0.0) / 31.0
	# At the restore start the earlier dim layer is STILL dimmed (not instantly popped to base).
	_assert_vec_approx(stack.fold(base, 0, 20), dim, "phase2 restore starts from the held dim, not base")
	# After the 32-frame restore the map is fully released back to base.
	_assert_vec_approx(stack.fold(base, 0, 52), base, "phase2 mode-8 fades the earlier dim layer back to base")


## No regression for single-phase combat effects (the common case, e.g. Cure): a
## build_stream over just the for_each phase (started @0) folds identically to the
## per-phase build_stack. The fix is inert when there is only one phase.
func _test_map_stream_single_phase_matches_build_stack() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_multiphase({
		"for_each": [
			{"mode": 5, "r": 252, "g": 252, "b": 252, "time": 1, "dur": 8},
			{"mode": 5, "r": 0, "g": 0, "b": 0, "time": 4, "dur": 32},
		],
	}, PaletteData.AFFECTED_UNITS))
	var base := Vector3(14.0, 10.0, 5.0) / 31.0
	var per_phase = pal.build_stack(PaletteData.AFFECTED_UNITS, "for_each")
	var stream = pal.build_stream(PaletteData.AFFECTED_UNITS, {"for_each": 0})
	for now in [0, 4, 8, 20, 40]:
		_assert_vec_approx(stream.fold(base, 0, now), per_phase.fold(base, 0, now),
			"single-phase stream == build_stack at now=%d" % now)


## Runtime wiring: driving the REAL timeline pump (advance(frame, open_phases(...)))
## records each phase's absolute start frame, and the map tint it self-delivers is the
## continuous stream — so the fold stays monotonic right across the phase1->for_each
## seam. This is the end-to-end guard that the per-phase reset (and its pop) is gone.
func _test_map_advance_records_phase_starts_and_delivers_continuous_tint() -> void:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_multiphase({
		"phase1": [{"mode": 5, "r": 252, "g": 252, "b": 252, "time": 1, "dur": 8}],
		"for_each": [{"mode": 5, "r": 252, "g": 252, "b": 252, "time": 1, "dur": 8}],
	}, PaletteData.AFFECTED_UNITS))
	var base := Vector3(14.0, 10.0, 5.0) / 31.0
	var prev := base
	# open_phases(frame, phase1_duration=8, phase2_start=124): phase1 for frame<8, then for_each.
	for frame in range(0, 10):
		pal.advance(frame, EffectPhase.open_phases(frame, 8, 124))
		# The tint the subsystem just self-delivered == build_stream over the recorded
		# starts, folded at the absolute frame (mirrors _deliver_output exactly).
		var folded := pal.build_stream(PaletteData.AFFECTED_UNITS, pal._phase_first_frame).fold(base, 0, frame)
		if frame > 0:
			_assert_not_brighter(folded, prev, "advance-driven map not brighter at frame %d (no seam pop)" % frame)
		prev = folded
	# Phases were recorded at their true absolute starts as the single-pass clock crossed them.
	_assert_eq(pal._phase_first_frame.get("phase1", -1), 0, "advance recorded phase1 start @ 0")
	_assert_eq(pal._phase_first_frame.get("for_each", -1), 8, "advance recorded for_each start @ 8")


## The CASTER unit tint has the SAME multi-phase structure as the map (E005 caster
## carries enabled keyframes in phase1 + for_each + phase2), so it popped at the seam
## too — a DIFFERENT surface (TintedSurfaces), same per-phase-rebuild root cause.
## Driving the real advance() with a registered caster unit and folding what the overlay
## DELIVERED (ColorStack.fold_packed over the pushed layers), the tint must stay
## monotonic across the phase1->for_each seam — no pop.
func _test_caster_unit_tint_continuous_across_phase_seam() -> void:
	var caster := Node.new()
	var uid := caster.get_instance_id()
	var mat := FakeMaterial.new()
	# Register the caster on the AUTOLOAD overlay so _deliver_output's push lands here.
	# #1224: a surface's slot is an ARRAY of materials, not one material.
	TintedSurfaces._surface_materials[uid] = [mat]
	TintedSurfaces._active_layers[uid] = {}

	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_multiphase({
		"phase1": [{"mode": 5, "r": 252, "g": 252, "b": 252, "time": 1, "dur": 8}],
		"for_each": [{"mode": 5, "r": 252, "g": 252, "b": 252, "time": 1, "dur": 8}],
	}, PaletteData.CASTER))
	pal.set_units(caster, null)

	var base := Vector3(14.0, 10.0, 5.0) / 31.0
	var prev := base
	for frame in range(0, 10):
		pal.advance(frame, EffectPhase.open_phases(frame, 8, 124))
		var folded := ColorStack.fold_packed(
			mat.params.get("color_layer_rgb0", []),
			mat.params.get("color_layer_rgb1", []),
			mat.params.get("color_layer_meta", []),
			mat.params.get("color_layer_count", 0),
			base, 0, true)
		if frame > 0:
			_assert_not_brighter(folded, prev, "caster tint not brighter at frame %d (no seam pop)" % frame)
		prev = folded

	TintedSurfaces._surface_materials.erase(uid)
	TintedSurfaces._active_layers.erase(uid)
	caster.free()


## Faithful-port (Holy/E015 rev 5): the 8-bit additive map illumination applier only ever
## tinted the PSX's UNTEXTURED flat-colour terrain primitive class (d2b4/d568), which Godot
## does not render — all Godot map tiles are textured. Delivering the flood globally over the
## textured map over-brightened terrain the PSX never additive-tinted (the reported map wash).
## So _deliver_output must NOT push a map illumination: firing even the E015 near-white flood
## channel leaves the map material's `map_illum_add` at the additive neutral 0 across every
## frame. (The DDA builder stays for a future untextured-terrain scope; it is not delivered.)
func _test_advance_does_not_deliver_map_illumination_to_textured_map() -> void:
	# We drive the real advance()->_deliver_output and read what it delivered to the map
	# material. Register a lone material + clear the CLUT concatenation state (the pattern
	# the caster-tint test uses). \U0001f7e2 #1192 DELETED the producer and the sink, so this
	# guard is now stronger than when it was written: there is no longer any code path that
	# COULD deliver the additive. The assertion is still the map material's own
	# `map_illum_add` getter — `Battlefield`'s uniform, which #1192 leaves in place — so the
	# test keeps working against the shader rather than against a private field.
	var mat := ShaderMaterial.new()
	TintedSurfaces.reserve_map_surface()
	TintedSurfaces._surface_materials[TintedSurfaces.SURFACE_MAP] = [mat]
	TintedSurfaces._active_layers[TintedSurfaces.SURFACE_MAP] = {}

	var pal = PaletteSubsystem.new()
	# The E015 flood on the map (affected_units) channel: idx1's mode-4 31/31/31 drives the
	# illumination DDA to the near-white 248 plateau the old delivery pushed as map_illum_add.
	pal.initialize(_palette_with([
		{"mode": 5, "r": 0, "g": 1, "b": 1, "time": 4, "dur": 32},        # idx0 -> 0,8,8
		{"mode": 4, "r": 31, "g": 31, "b": 31, "time": 4, "dur": 32},     # idx1 -> 248 flood
	], PaletteData.AFFECTED_UNITS))

	var worst := Vector3.ZERO
	for frame in range(0, 120):
		pal.advance(frame, EffectPhase.open_phases(frame, 8, 124))
		var got = mat.get_shader_parameter("map_illum_add")
		if got is Vector3:
			worst = worst.max(got.abs())
	_assert_vec_approx(worst, Vector3.ZERO,
		"E015 flood is never delivered to the textured map (map_illum_add stays neutral 0 all frames)")

	TintedSurfaces._surface_materials[TintedSurfaces.SURFACE_MAP] = []
	TintedSurfaces._active_layers[TintedSurfaces.SURFACE_MAP] = {}
