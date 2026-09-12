extends Node
## Pure-logic guard (no GPU/scene): IndexedAtlasDilator bleeds the terrain atlas's opaque
## palette indices outward into the transparent (index-0) border texels — "edge padding /
## texture dilation". Fixes the map seam where a covered fragment at a patch EDGE samples a
## transparent index-0 texel INSIDE its own patch -> discard -> background sliver (proven
## cyan by the shader diagnostic: uv_rect arrives + clamp runs, but the texel is still
## transparent). Copies EXACT indices (nearest non-zero neighbor), never blends, so the
## crisp PSX nearest look is preserved.
##
## Atlas encoding: R channel carries the palette index (shader reads indexed.r * 15). Index
## 0 (R==0) is the transparent-black slot (models/palette.py). Dilation fills R==0 texels
## that touch an opaque neighbor with that neighbor's index.
##
## Run: bash tests/stranger/exmateria_battlefield/run.sh   (ADR-0194 — this test
## is addon-owned and runs in a STRANGER project, not in the host. Directly:
## "$GODOT" --path . --quit-after 5 res://addons/exmateria_battlefield/tests/MapAtlasDilateTest.tscn)


const IndexedAtlasDilator = preload("res://addons/exmateria_battlefield/texturing/IndexedAtlasDilator.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_transparent_texel_takes_opaque_neighbor_index()
	_test_one_pass_grows_exactly_one_texel()
	_test_two_passes_reach_distance_two()

	print("\n=== MapAtlasDilateTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] MapAtlasDilateTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] MapAtlasDilateTest")
		get_tree().quit(1)
	else:
		print("[PASS] MapAtlasDilateTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _assert_eq_int(got: int, want: int, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%d want=%d" % [name, got, want])


# --- helpers -----------------------------------------------------------------

## A texel carrying palette index `i` (R = i/15, matching the shader's indexed.r * 15).
func _index_color(i: int) -> Color:
	return Color(float(i) / 15.0, 0.0, 0.0, 1.0)

## Read the palette index back out of a texel (inverse of _index_color).
func _index_of(img: Image, x: int, y: int) -> int:
	return int(round(img.get_pixel(x, y).r * 15.0))


# --- tests -------------------------------------------------------------------

## Tracer bullet: [index0, index5, index0] row. After one dilation pass, the two transparent
## ends each take their opaque neighbor's index (5); the opaque center is unchanged.
func _test_transparent_texel_takes_opaque_neighbor_index() -> void:
	var img := Image.create(3, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, _index_color(0))
	img.set_pixel(1, 0, _index_color(5))
	img.set_pixel(2, 0, _index_color(0))

	var out := IndexedAtlasDilator.dilate(img, 1)

	_assert_eq_int(_index_of(out, 0, 0), 5, "left transparent takes neighbor index 5")
	_assert_eq_int(_index_of(out, 1, 0), 5, "opaque center unchanged")
	_assert_eq_int(_index_of(out, 2, 0), 5, "right transparent takes neighbor index 5")


## One pass grows the opaque region by exactly one texel — a transparent texel two away from
## any opaque one stays transparent (the fill reads a per-pass snapshot, so it can't cascade
## within a single pass). This is what makes `passes` a predictable "bleed distance" dial and
## keeps far index-0 gutters from flooding.
func _test_one_pass_grows_exactly_one_texel() -> void:
	var img := Image.create(5, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, _index_color(5))
	img.set_pixel(1, 0, _index_color(0))
	img.set_pixel(2, 0, _index_color(0))  # two texels from either opaque end
	img.set_pixel(3, 0, _index_color(0))
	img.set_pixel(4, 0, _index_color(5))

	var out := IndexedAtlasDilator.dilate(img, 1)

	_assert_eq_int(_index_of(out, 1, 0), 5, "1 texel out filled")
	_assert_eq_int(_index_of(out, 2, 0), 0, "2 texels out still transparent after 1 pass")
	_assert_eq_int(_index_of(out, 3, 0), 5, "1 texel out (other side) filled")


## Two passes reach two texels deep — the gap fully closes.
func _test_two_passes_reach_distance_two() -> void:
	var img := Image.create(5, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, _index_color(5))
	img.set_pixel(1, 0, _index_color(0))
	img.set_pixel(2, 0, _index_color(0))
	img.set_pixel(3, 0, _index_color(0))
	img.set_pixel(4, 0, _index_color(5))

	var out := IndexedAtlasDilator.dilate(img, 2)

	_assert_eq_int(_index_of(out, 2, 0), 5, "middle filled after 2 passes")
