extends Node
## Guard for EmitterSpriteColor — the per-emitter representative sprite colour the Colour
## ribbon muxes in so its read-out matches the RENDERED particle (ALBEDO = sprite.rgb *
## modulate.rgb, effect_particle_opaque.gdshader). An effect particle multiplies its colour
## curve against the RGBA-baked texture.tga texel of the emitter's sprite — so a green-only
## sprite (E138 idx0: R=0/B=0) can never show red/blue no matter the curves. The representative
## is the peak-luma VISIBLE texel across the framesets the emitter's anim_index animation
## visits (animations[anim_index] FRAME opcodes + frameset_group_offset[anim_param]).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EmitterSpriteColorTest.tscn

const SpriteColor = preload("res://src/effects/studio/EmitterSpriteColor.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitterClass = ExMateriaEffects.EffectEmitter

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_peak_luma_texel_of_the_animations_framesets()
	_test_only_the_emitters_own_animation_framesets_count()
	_test_group_offset_shifts_the_frameset_window()
	_test_no_texture_is_white_identity()
	_test_out_of_range_emitter_is_white()

	print("\n=== EmitterSpriteColorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EmitterSpriteColorTest")
		get_tree().quit(1)
	else:
		print("[PASS] EmitterSpriteColorTest")
		get_tree().quit(0)


## A green-only sprite region resolves to its brightest green texel — the E138 idx0 case.
func _test_peak_luma_texel_of_the_animations_framesets() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	img.set_pixel(0, 0, Color(0, 0.25, 0, 1))
	img.set_pixel(1, 1, Color(0, 0.75, 0, 1))   # the brightest green in the region
	var ed := _effect(img, 0, 0, [_anim([0])], [_frameset(0, 0, 2, 2)], [0])
	var rep: Color = SpriteColor.representative(ed, 0)
	_assert_color(rep, Color(0, 0.75, 0), "green-only region → brightest green texel (no red/blue)")


## Two emitters with different anim_index see different frameset regions → different colours.
func _test_only_the_emitters_own_animation_framesets_count() -> void:
	var img := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	img.set_pixel(0, 0, Color(0, 0.5, 0, 1))     # frameset 0 region (left): green
	img.set_pixel(2, 0, Color(0.9, 0, 0, 1))     # frameset 1 region (right): red
	var framesets := [_frameset(0, 0, 2, 2), _frameset(2, 0, 2, 2)]
	var ed := _effect(img, 0, 0, [_anim([0]), _anim([1])], framesets, [0])
	var em1 := EffectEmitterClass.new()
	em1.anim_index = 1
	ed.emitters.append(em1)   # a second emitter using animation 1 (the red frameset)
	_assert_color(SpriteColor.representative(ed, 0), Color(0, 0.5, 0), "emitter 0 (anim 0) → green frameset")
	_assert_color(SpriteColor.representative(ed, 1), Color(0.9, 0, 0), "emitter 1 (anim 1) → red frameset")


## anim_param picks the frameset GROUP: its cumulative offset shifts which frameset the
## animation's relative index lands on.
func _test_group_offset_shifts_the_frameset_window() -> void:
	var img := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	img.set_pixel(0, 0, Color(0, 0, 0.5, 1))     # frameset 0: blue
	img.set_pixel(2, 0, Color(0.8, 0.8, 0, 1))   # frameset 1: yellow
	var framesets := [_frameset(0, 0, 2, 2), _frameset(2, 0, 2, 2)]
	# anim references relative frameset 0; group offset 1 → absolute frameset 1 (yellow).
	var ed := _effect(img, 0, 1, [_anim([0])], framesets, [0, 1])
	_assert_color(SpriteColor.representative(ed, 0), Color(0.8, 0.8, 0),
		"group offset 1 shifts relative frameset 0 → absolute frameset 1 (yellow)")


## No texture on the effect → white, the identity mux (the ribbon shows the pure curve).
func _test_no_texture_is_white_identity() -> void:
	var ed := _effect(null, 0, 0, [_anim([0])], [_frameset(0, 0, 2, 2)], [0])
	_assert_color(SpriteColor.representative(ed, 0), Color.WHITE, "no texture → white identity")


func _test_out_of_range_emitter_is_white() -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0.5, 0, 1))
	var ed := _effect(img, 0, 0, [_anim([0])], [_frameset(0, 0, 2, 2)], [0])
	_assert_color(SpriteColor.representative(ed, 5), Color.WHITE, "out-of-range emitter → white")


# --- builders ---------------------------------------------------------------

func _effect(img: Image, anim_index: int, anim_param: int, animations: Array,
		framesets: Array, group_offsets: Array) -> EffectDataClass:
	var ed := EffectDataClass.new()
	var em := EffectEmitterClass.new()
	em.anim_index = anim_index
	em.anim_param = anim_param
	ed.emitters.append(em)
	ed.animations = animations
	ed.framesets = framesets
	ed.frameset_group_offsets.assign(group_offsets)
	ed.texture = ImageTexture.create_from_image(img) if img != null else null
	return ed


func _anim(frameset_indices: Array) -> Dictionary:
	var ops: Array = []
	for fs in frameset_indices:
		ops.append({"type": "FRAME", "frameset": fs, "duration": 2})
	return {"opcodes": ops}


func _frameset(x: int, y: int, w: int, h: int) -> Dictionary:
	return {"frames": [{"uv": {"x": x, "y": y, "width": w, "height": h}}]}


func _assert_color(got: Color, want: Color, label: String) -> void:
	if absf(got.r - want.r) < 0.01 and absf(got.g - want.g) < 0.01 and absf(got.b - want.b) < 0.01:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — got %s want %s" % [label, str(got), str(want)])
