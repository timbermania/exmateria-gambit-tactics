extends Node
## Regression test for SpriteLayerManager.compute_body_center — the OT depth
## sample-center derivation (ADR-0009).
##
## The center MUST be the midpoint of the smallest box containing all
## NON-TRANSPARENT body pixels, NOT the box of the raw piece rectangles. A
## sprite piece can carry large transparent margins (FFT monster frames — the
## scenario-6 chocobo's resting frame has pieces padded far below the body with
## no visible pixel down there). The piece-rectangle midpoint put the chocobo's
## depth sample ~1.44 world units below its feet, mis-sorting it against terrain.
##
## `compute_body_center` is a static, Image-in pure function, so we feed
## synthetic indexed-grayscale atlases directly. Index encoding matches
## add_tile_paletted: pixel.r*15 rounded = palette index; index 0 = transparent.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/DepthCenterBboxTest.tscn

const SLM := ExMateriaSpriteRig.SpriteLayerManager
var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_transparent_padding_below()
	_test_fully_opaque_matches_piece_bbox()
	_test_all_transparent_falls_back()
	_test_ignores_fully_transparent_padding_tile()

	print("\n=== DepthCenterBboxTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DepthCenterBboxTest")
		get_tree().quit(1)
	else:
		print("[PASS] DepthCenterBboxTest")
		get_tree().quit(0)


# The chocobo case in miniature: one tall piece (loc_y -36..132, so piece-rect
# center = 48) but visible pixels only in a band near the top -> the visible
# center must land at the pixels, not at the padded rectangle midpoint.
func _test_transparent_padding_below() -> void:
	var img := _blank(64, 200)
	# Visible band: atlas rows [2,42), cols [10,20). With the tile placed at
	# location (-32,-36): loc_y in [-34,6) -> center -14; loc_x in [-22,-12) ->
	# center -17. Piece-rect center would be y=48, x=0.
	_fill(img, 10, 2, 10, 40)
	var rects := [Vector2(0, 0)]
	var sizes := [Vector2(64, 168)]
	var locs := [Vector2(-32, -36)]
	var c := SLM.compute_body_center(img, rects, sizes, locs)
	_expect(c, Vector2(-17, -14), "tall piece, visible band near top")
	# Sanity: the piece-rect heuristic (no image) DOES give the bad y=48.
	var pc := SLM.compute_body_center(null, rects, sizes, locs)
	_expect(pc, Vector2(0, 48), "piece-rect fallback still equals padded midpoint")


func _test_fully_opaque_matches_piece_bbox() -> void:
	var img := _blank(32, 32)
	_fill(img, 0, 0, 20, 24)
	var rects := [Vector2(0, 0)]
	var sizes := [Vector2(20, 24)]
	var locs := [Vector2(-10, -30)]
	# Fully opaque -> visible bbox == piece bbox: y center (-30 + -6)/2 = -18.
	var c := SLM.compute_body_center(img, rects, sizes, locs)
	_expect(c, Vector2(0, -18), "fully-opaque piece == piece bbox")


func _test_all_transparent_falls_back() -> void:
	var img := _blank(16, 16)  # left fully transparent (index 0)
	var rects := [Vector2(0, 0)]
	var sizes := [Vector2(16, 16)]
	var locs := [Vector2(-8, -8)]
	# No visible pixels -> fall back to piece bbox: center (0, 0).
	var c := SLM.compute_body_center(img, rects, sizes, locs)
	_expect(c, Vector2(0, 0), "all-transparent frame falls back to piece bbox")


# Two tiles: a real body piece plus a fully-transparent padding piece placed far
# below. The transparent tile must not stretch the visible box.
func _test_ignores_fully_transparent_padding_tile() -> void:
	var img := _blank(64, 128)
	_fill(img, 0, 0, 16, 16)  # body piece pixels at atlas [0,16)x[0,16)
	# padding tile region [0,16)x[64,80) left transparent
	var rects := [Vector2(0, 0), Vector2(0, 64)]
	var sizes := [Vector2(16, 16), Vector2(16, 16)]
	var locs := [Vector2(-8, -20), Vector2(-8, 40)]
	# Only the body piece is visible: loc_y [-20,-4) -> center -12; x center 0.
	var c := SLM.compute_body_center(img, rects, sizes, locs)
	_expect(c, Vector2(0, -12), "fully-transparent padding tile ignored")


# --- helpers ---------------------------------------------------------------

func _blank(w: int, h: int) -> Image:
	# All index 0 (transparent). FORMAT_RGBA8 so get_pixel().r is exact.
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


func _fill(img: Image, x: int, y: int, w: int, h: int) -> void:
	# Paint palette index 1 (r = 1/15) so round(r*15) == 1 (opaque).
	var col := Color(1.0 / 15.0, 0, 0, 1.0)
	for py in range(h):
		for px in range(w):
			img.set_pixel(x + px, y + py, col)


func _expect(got: Vector2, want: Vector2, name: String) -> void:
	if got.is_equal_approx(want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])
