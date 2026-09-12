extends Node
# test-kind: logic
# seeded-break: EffectViewerScene.studio_apply_edit's dispatch swapped the two preview-update calls (a FOLDED-channel edit now calls redeliver_colors() instead of refold(), a read-live edit now calls refold()) — the camera-edit refold/no-seek, palette read-live repaint/no-refold, and the read-live-defer arm's three assertions red; the deferred-drag commit arms stay green (the defer-flag machinery is untouched); GREEN unbroken on the reverted tree
## TDD guard: the host's authoring choke point re-folds the preview for FOLDED-channel
## edits (#267 follow-on — the camera-edit "no rescrub" bug).
##
## EffectViewerScene.studio_apply_edit lowers a raw edit through EffectEditSession and
## then reconciles the preview per `invalidates_sim`:
##   * invalidates_sim TRUE  (camera framing — folded during the sim) → refold() the
##     instance (reset → re-pump the current frame). It must NOT use seek(current_frame),
##     which is a same-frame no-op that folds nothing (see EffectSeekTest).
##   * invalidates_sim FALSE (screen/palette colour — read-live) → redeliver_colors()
##     in place, NO re-fold.
##
## Seam: studio_apply_edit(field_ref, new_raw) on a real EffectViewerScene with a fake
## instance that records refold/seek/redeliver — the exact host method the page calls.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectViewerRefoldTest.tscn

const EffectViewerScene = preload("res://src/scenes/EffectViewerScene.gd")
const EffectData = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const PaletteData = ExMateriaEffects.PaletteData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_camera_edit_refolds_not_seeks()
	_test_readlive_edit_redelivers_without_refold()
	_test_deferred_sim_edit_holds_refold_until_commit()
	_test_commit_refold_is_noop_without_deferred_edit()
	_test_readlive_edit_ignores_defer_and_never_arms_commit()

	print("\n=== EffectViewerRefoldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectViewerRefoldTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectViewerRefoldTest")
		get_tree().quit(0)


## A camera edit (invalidates_sim=true) must refold() — NOT a same-frame seek (no-op).
func _test_camera_edit_refolds_not_seeks() -> void:
	var host = EffectViewerScene.new()
	var fake := _FakeEffect.new()
	fake.effect_data = _data_with_camera_and_palette()
	host._current_effect = fake

	var res: Dictionary = host.studio_apply_edit(
		{"channel": "camera", "context": "phase1", "camera_channel": "angle", "ordinal": 0,
			"field": "source_mode"}, 0x140)

	_assert_true(res.get("invalidates_sim", false), "camera edit reports invalidates_sim")
	_assert_eq(fake.refolds, 1, "a folded (camera) edit re-folds the preview once")
	_assert_true(fake.seeks.is_empty(), "it does NOT use a same-frame seek (that would no-op)")
	_assert_eq(fake.redelivers, 0, "a folded edit does not use the read-live redeliver path")
	host.free()


## A read-live edit (invalidates_sim=false, e.g. palette tint) repaints via
## redeliver_colors() with NO re-fold.
func _test_readlive_edit_redelivers_without_refold() -> void:
	var host = EffectViewerScene.new()
	var fake := _FakeEffect.new()
	fake.effect_data = _data_with_camera_and_palette()
	host._current_effect = fake

	var res: Dictionary = host.studio_apply_edit(
		{"channel": "palette", "context": "for_each", "channel_name": "target",
			"event_index": 0, "field": "blend_mode"}, 5)

	_assert_eq(res.get("invalidates_sim", true), false, "palette edit is read-live (invalidates_sim=false)")
	_assert_eq(fake.redelivers, 1, "a read-live edit repaints in place via redeliver_colors")
	_assert_eq(fake.refolds, 0, "a read-live edit does NOT re-fold")
	host.free()


## ADR-0089 Drag preview (host side): a sim-invalidating edit made with defer_refold=true does
## NOT refold in place — the page reprojects the sim-free geometry per motion and the drag's
## terminal studio_commit_refold folds ONCE. So a whole drag costs one refold, not one per frame.
func _test_deferred_sim_edit_holds_refold_until_commit() -> void:
	var host = EffectViewerScene.new()
	var fake := _FakeEffect.new()
	fake.effect_data = _data_with_camera_and_palette()
	host._current_effect = fake

	# Two mid-drag motions on a folded (camera) channel, each asking to defer.
	host.studio_apply_edit({"channel": "camera", "context": "phase1", "camera_channel": "angle",
		"ordinal": 0, "field": "source_mode"}, 0x140, true)
	host.studio_apply_edit({"channel": "camera", "context": "phase1", "camera_channel": "angle",
		"ordinal": 0, "field": "source_mode"}, 0x040, true)
	_assert_eq(fake.refolds, 0, "a deferred sim edit does not refold mid-drag")

	host.studio_commit_refold()
	_assert_eq(fake.refolds, 1, "release folds ONCE for the whole drag")
	host.studio_commit_refold()
	_assert_eq(fake.refolds, 1, "a second commit is a no-op (the pending flag was cleared)")
	host.free()


## studio_commit_refold with nothing deferred (e.g. after a read-live-only drag) must NOT
## refold — read-live lanes stay untouched by the drag-preview machinery.
func _test_commit_refold_is_noop_without_deferred_edit() -> void:
	var host = EffectViewerScene.new()
	var fake := _FakeEffect.new()
	fake.effect_data = _data_with_camera_and_palette()
	host._current_effect = fake

	host.studio_commit_refold()
	_assert_eq(fake.refolds, 0, "commit with nothing deferred does not refold")
	host.free()


## A read-live (palette) edit ignores the defer flag entirely — it repaints in place via
## redeliver_colors and never arms the deferred refold, so a following commit stays a no-op.
func _test_readlive_edit_ignores_defer_and_never_arms_commit() -> void:
	var host = EffectViewerScene.new()
	var fake := _FakeEffect.new()
	fake.effect_data = _data_with_camera_and_palette()
	host._current_effect = fake

	host.studio_apply_edit({"channel": "palette", "context": "for_each", "channel_name": "target",
		"event_index": 0, "field": "blend_mode"}, 5, true)
	_assert_eq(fake.redelivers, 1, "a read-live edit still repaints in place, defer flag or not")
	_assert_eq(fake.refolds, 0, "…and never refolds")

	host.studio_commit_refold()
	_assert_eq(fake.refolds, 0, "…so the drag-release commit finds nothing to fold")
	host.free()


# --- fixtures --------------------------------------------------------------

func _data_with_camera_and_palette():
	var data = EffectData.new()
	data.camera = CameraData.from_json({
		"phase1": {"max_keyframe": 1, "keyframes": [{
			"index": 0, "end_frame": 8,
			"angle": [10, 20, 30], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR",
			"param_index": 0, "flags": 0,
		}]},
	})
	data.palette = PaletteData.from_json({
		"for_each": {"target": {"context": "for_each", "channel_name": "target",
			"max_keyframe": 2, "keyframes": [
				{"index": 0, "duration_frames": 10, "enabled": true, "blend_mode": 2,
					"rgb": [255, 128, 0]}]}},
	})
	return data


class _FakeEffect extends Node:
	var effect_data
	var _frame: int = 5
	var refolds: int = 0
	var redelivers: int = 0
	var seeks: Array = []
	func get_effect_frame() -> int:
		return _frame
	func refold() -> void:
		refolds += 1
	func redeliver_colors() -> void:
		redelivers += 1
	func seek(f: int) -> void:
		seeks.append(f)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
