extends Node
## The PSX blend path, over its WHOLE domain — every (background, foreground) pair of
## 5-bit levels in every semi-transparency mode, 3 x 32 x 32 = 3072 cases, on the GPU.
##
## [b]What it is guarding.[/b] The world map composites in the console's own 5-bit
## channels: a texel is baked as `8 * v` and [code]psx_expand_555.gdshader[/code] widens
## the finished frame with `(v << 3) | (v >> 2)` once. That is what makes fixed-function
## blending exact — `4(B+F)` floors to `(B+F) >> 1`, ADD clamps at byte 255 = level 31,
## SUB clamps at byte 0. Expanding per quad instead computes `e(B) op e(F)` where the
## console computes `e(B op F)`, and the two differ by one 8-bit level on a quarter of
## the frame.
##
## [b]Why synthetic and not a screenshot.[/b] A frame exercises whatever pairs it happens
## to contain; this exercises all of them, needs no ROM-derived asset, and fails with the
## exact (mode, B, F) rather than a percentage. The frame-level check is
## `tools/wm_compare.py` against `tools/wm_console_frame.py`, and it is a different
## question — it also answers geometry, uv and CLUT.
##
## The reference is `render_scene.py`'s `blend()`, reimplemented in [method _psx] as
## integers.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/WorldMapBlendTest.tscn

const LEVELS := 32
const MODES := [0, 1, 2, 3]

var _passed := 0
var _failed := 0


func _ready() -> void:
	var renderer := WorldMapRenderer.new()
	for abr in MODES:
		await _check_mode(renderer, abr)
	if _failed > 0:
		print("[FAIL] WorldMapBlendTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapBlendTest — %d/%d" % [_passed, _passed + _failed])
	get_tree().quit(0)


## Paint a 32x32 board: column x is foreground level x, row y is background level y.
## Read it back through the expansion pass and compare every cell to the integer model.
func _check_mode(renderer: WorldMapRenderer, abr: int) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(LEVELS, LEVELS)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The default is 2D-HDR off; say so, because a float target would quantise elsewhere.
	vp.use_hdr_2d = false
	add_child(vp)

	var root := Node2D.new()
	vp.add_child(root)
	for b in LEVELS:
		root.add_child(_bar(Rect2(0, b, LEVELS, 1), b, null, 1.0))
	for f in LEVELS:
		# The same shift the renderer bakes with -- abr 3's quarter is taken here, not
		# by the blender.
		root.add_child(_bar(Rect2(f, 0, 1, LEVELS),
				f >> WorldMapRenderer.level_shift(abr, true),
				renderer.material_for(abr, true), _alpha_for(abr)))

	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	vp.add_child(copy)
	var expand := ColorRect.new()
	expand.material = ShaderMaterial.new()
	(expand.material as ShaderMaterial).shader = \
			load("res://src/world_map/psx_expand_555.gdshader")
	expand.position = Vector2.ZERO
	expand.size = Vector2(LEVELS, LEVELS)
	vp.add_child(expand)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()

	var bad := 0
	var first := ""
	for b in LEVELS:
		for f in LEVELS:
			var want := WorldMapAssets.expand5(_psx(b, f, abr))
			var got := int(img.get_pixel(f, b).r8)
			if got != want:
				bad += 1
				if first.is_empty():
					first = "B=%d F=%d want %d got %d" % [b, f, want, got]
	vp.queue_free()
	if bad > 0:
		_fail("abr %d: %d of %d pairs wrong (first: %s)" % [abr, bad, LEVELS * LEVELS, first])
	else:
		_pass("abr %d: all %d level pairs blend exactly" % [abr, LEVELS * LEVELS])


## A flat quad of one 5-bit level, through the SAME bake the renderer uses: a texture
## carrying `8 * v`, drawn at modulate 1.0. Colouring the polygon instead would test a
## path the map never takes.
func _bar(rect: Rect2, level: int, mat: Material, alpha: float) -> Polygon2D:
	var img := Image.create_from_data(1, 1, false, Image.FORMAT_RGBA8,
			PackedByteArray([level * WorldMapRenderer.LEVEL_SCALE,
					level * WorldMapRenderer.LEVEL_SCALE,
					level * WorldMapRenderer.LEVEL_SCALE, 255]))
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		rect.position, rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size, rect.position + Vector2(0, rect.size.y)])
	poly.uv = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	poly.texture = ImageTexture.create_from_image(img)
	poly.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	poly.color = Color(1, 1, 1, alpha)
	poly.material = mat
	return poly


func _alpha_for(abr: int) -> float:
	return 0.5 if abr == 0 else 1.0


## `render_scene.py`'s blend(), one channel, integers throughout.
static func _psx(b: int, f: int, abr: int) -> int:
	match abr:
		0: return (b + f) / 2
		1: return mini(31, b + f)
		2: return maxi(0, b - f)
		_: return mini(31, b + f / 4)


func _pass(msg: String) -> void:
	_passed += 1
	print("  ok   %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	print("  FAIL %s" % msg)
