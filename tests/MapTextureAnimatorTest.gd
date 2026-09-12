extends Node
## Tests for MapTextureAnimator — the real render of FFT map "Texture Animation
## Instructions" behind event-script {55} Use Field Object.
##
## Validates against MAP062 (Chapel of Orbonne), whose slot 1 is the live-verified
## oracle from `research/working_documents/scenario_1_captures/
## use_field_object_decode.md` (descriptor read out of PSX RAM for Field Object
## ID=1: 3 frames x 15 ticks, ForwardOnceOnTrigger). This test confirms the
## parser-emitted slot, the source->canvas blit math, the per-frame timing, and
## the restore-to-rest on completion — all deterministically, no emulator.
##
## Run: "$GODOT" --path . --quit-after 10 res://tests/MapTextureAnimatorTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const MapTextureAnimator = ExMateriaBattlefield.MapTextureAnimator


const MANIFEST_PATH := "res://assets/maps/MAP062/manifest.json"
const TEXTURE_PATH := "res://assets/maps/MAP062/texture_indexed.tga"
const PAGE_HEIGHT := 256

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var slots := _load_slots()
	var tex := load(TEXTURE_PATH) as Texture2D
	if slots.is_empty() or tex == null:
		print("[FAIL] MapTextureAnimatorTest: missing MAP062 assets (slots=%d tex=%s)"
			% [slots.size(), str(tex)])
		get_tree().quit(1)
		return

	_test_slot1_matches_oracle(slots)
	_test_setup_and_blit(slots, tex)
	_test_timing_and_hold(slots, tex)
	_test_reseed_preserves_running_animation(slots, tex)

	print("\n=== MapTextureAnimatorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 or _failed > 0:
		print("[FAIL] MapTextureAnimatorTest")
		get_tree().quit(1)
	else:
		print("[PASS] MapTextureAnimatorTest")
		get_tree().quit(0)


func _load_slots() -> Array:
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return []
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var anims: Dictionary = data.get("animations", {})
	return anims.get("texture_animations", [])


# Slot 1 == the live PSX descriptor for Field Object ID=1.
func _test_slot1_matches_oracle(slots: Array) -> void:
	_assert(slots.size() == 32, "32 slots present (got %d)" % slots.size())
	var s1: Dictionary = slots[1]
	_assert(s1.get("kind") == "uv", "slot1 is uv")
	_assert(int(s1.get("frame_count", 0)) == 3, "slot1 frame_count == 3")
	_assert(int(s1.get("frame_duration", 0)) == 15, "slot1 frame_duration == 15")
	_assert(int(s1.get("size_width", 0)) == 28, "slot1 size_width == 28")
	_assert(int(s1.get("size_height", 0)) == 70, "slot1 size_height == 70")


func _test_setup_and_blit(slots: Array, tex: Texture2D) -> void:
	var anim := MapTextureAnimator.new()
	var work_tex := anim.setup(slots, tex)
	_assert(work_tex != null, "setup returns a work texture")
	_assert(anim.is_ready(), "animator ready after setup")

	var slot: Dictionary = slots[1]
	var dst := _canvas_atlas_origin(slot)
	var src0 := _frame_atlas_origin(slot, 0)
	var w := int(slot.get("size_width", 0))
	var h := int(slot.get("size_height", 0))

	var source := anim.get_source_image()
	# Sanity: frame-0 source and canvas regions actually differ in the source
	# atlas (else the blit would be a no-op and the test would prove nothing).
	_assert(not _regions_equal(source, src0, source, dst, w, h),
		"frame0 source differs from canvas region (animation is meaningful)")

	anim.play(1)
	_assert(anim.is_active(1), "slot 1 active after play")

	# After the opening blit the canvas region must equal the frame-0 source.
	var work := anim.get_work_image()
	_assert(_regions_equal(work, dst, source, src0, w, h),
		"canvas == frame0 source after opening blit")


func _test_timing_and_hold(slots: Array, tex: Texture2D) -> void:
	# Slot 1 is a FORWARD once-on-trigger door-opening animation, so on
	# completion the canvas must HOLD the final frame (door stays open), NOT
	# restore to the closed rest texture.
	var anim := MapTextureAnimator.new()
	anim.setup(slots, tex)
	var slot: Dictionary = slots[1]
	var dst := _canvas_atlas_origin(slot)
	var w := int(slot.get("size_width", 0))
	var h := int(slot.get("size_height", 0))
	var source := anim.get_source_image()

	# Snapshot the rest (pre-play, closed-door) canvas pixels.
	var rest := source.get_region(Rect2i(dst.x, dst.y, w, h))
	# The final frame (frame_count-1) source region — the held "open" frame.
	var last_idx := int(slot.get("frame_count", 1)) - 1
	var last_src := _frame_atlas_origin(slot, last_idx)
	var last_frame := source.get_region(Rect2i(last_src.x, last_src.y, w, h))

	anim.play(1)
	# Total duration = 3 frames * 15 ticks = 45 ticks = 0.75s @ 60Hz.
	# Step ~0.5s: still mid-animation, must remain active.
	for i in range(30):
		anim.tick(1.0 / 60.0)
	_assert(anim.is_active(1), "still active at ~0.5s (< 0.75s duration)")

	# Step past the end: must finish and hold the final frame.
	for i in range(30):
		anim.tick(1.0 / 60.0)
	_assert(not anim.is_active(1), "inactive after full 0.75s duration")

	var work := anim.get_work_image()
	var after := work.get_region(Rect2i(dst.x, dst.y, w, h))
	_assert(_images_equal(last_frame, after), "canvas holds the final (open) frame after completion")
	_assert(not _images_equal(rest, after), "canvas does NOT snap back to the closed rest texture")


# A live `map.atlas_dilate_passes` scrub re-derives a new (dilated) atlas. While the
# animator owns the material's indexed_texture, the composer re-seeds the animator's
# base IN PLACE instead of swapping a static texture into the uniform — swapping would
# orphan the animator's work canvas and FREEZE the animation. This guards that
# reseed_indexed_source keeps the SAME material-facing work texture (so materials keep
# sampling it), folds in the new base, and preserves the running animation frame.
func _test_reseed_preserves_running_animation(slots: Array, tex: Texture2D) -> void:
	var anim := MapTextureAnimator.new()
	var work_tex := anim.setup(slots, tex)  # the object the materials sample
	var slot: Dictionary = slots[1]
	var dst := _canvas_atlas_origin(slot)
	var w := int(slot.get("size_width", 0))
	var h := int(slot.get("size_height", 0))

	# A sentinel pixel OUTSIDE the animated canvas region stands in for the
	# edge-padding a dilate pass writes — it must survive into the live work texture.
	var sentinel := Vector2i(0, 0)
	_assert(not Rect2i(dst.x, dst.y, w, h).has_point(sentinel),
		"reseed sentinel (0,0) is outside the animated canvas region")
	var dilated_img := anim.get_source_image().duplicate()
	if dilated_img.get_format() != Image.FORMAT_RGBA8:
		dilated_img.convert(Image.FORMAT_RGBA8)
	var marker := Color(1.0, 0.0, 1.0, 1.0)
	_assert(dilated_img.get_pixel(sentinel.x, sentinel.y) != marker,
		"sentinel starts != marker (the reseed actually changes something)")
	dilated_img.set_pixel(sentinel.x, sentinel.y, marker)
	var dilated_tex := ImageTexture.create_from_image(dilated_img)

	# Drive the animation to a mid, non-opening frame so "preserved" is meaningful.
	anim.play(1)
	for i in range(20):
		anim.tick(1.0 / 60.0)
	_assert(anim.is_active(1), "animation active before reseed")
	var frame_before := anim.get_work_image().get_region(Rect2i(dst.x, dst.y, w, h))

	var ok := anim.reseed_indexed_source(dilated_tex)
	_assert(ok, "reseed_indexed_source succeeds for a same-size atlas")
	# The base folded in: the animator's source now carries the dilate marker.
	_assert(anim.get_source_image().get_pixel(sentinel.x, sentinel.y) == marker,
		"reseed folds the new (dilated) base into the source atlas")
	# THE anti-freeze guard: the SAME work texture the materials sample was updated
	# in place (not replaced/orphaned), so the marker is now visible on-screen.
	_assert(work_tex.get_image().get_pixel(sentinel.x, sentinel.y) == marker,
		"reseed updates the SAME material-facing work texture (no orphaned canvas)")
	# The running animation frame is preserved (redrawn onto the fresh base), not
	# flashed back to frame 0.
	var frame_after := anim.get_work_image().get_region(Rect2i(dst.x, dst.y, w, h))
	_assert(_images_equal(frame_before, frame_after),
		"reseed preserves the current animation frame")
	# And the animation keeps advancing after the reseed.
	_assert(anim.is_active(1), "animation still active after reseed")
	for i in range(40):
		anim.tick(1.0 / 60.0)
	_assert(not anim.is_active(1), "animation still completes normally after reseed")

	# A size mismatch is refused (no in-place update of a texture the materials no
	# longer match), leaving state intact.
	var small := Image.create(w, h, false, Image.FORMAT_RGBA8)
	_assert(not anim.reseed_indexed_source(ImageTexture.create_from_image(small)),
		"reseed refuses a size-mismatched atlas")


# ---- helpers ----

func _canvas_atlas_origin(slot: Dictionary) -> Vector2i:
	return Vector2i(
		int(slot.get("canvas_x", 0)),
		int(slot.get("canvas_y", 0)) + int(slot.get("canvas_texture_page", 0)) * PAGE_HEIGHT)


func _frame_atlas_origin(slot: Dictionary, frame: int) -> Vector2i:
	return Vector2i(
		int(slot.get("first_frame_x", 0)) + frame * int(slot.get("size_width", 0)),
		int(slot.get("first_frame_y", 0)) + int(slot.get("first_frame_texture_page", 0)) * PAGE_HEIGHT)


func _regions_equal(img_a: Image, a: Vector2i, img_b: Image, b: Vector2i, w: int, h: int) -> bool:
	for y in range(h):
		for x in range(w):
			if img_a.get_pixel(a.x + x, a.y + y) != img_b.get_pixel(b.x + x, b.y + y):
				return false
	return true


func _images_equal(a: Image, b: Image) -> bool:
	return a.get_data() == b.get_data()


func _assert(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)
