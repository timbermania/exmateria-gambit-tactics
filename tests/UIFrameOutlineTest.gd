extends Node
## Guard: the default UIFrame 9-slice crop INCLUDES the ROM menu-frame's 1px dark
## outline column on every edge (frame.tga `(48,40,32)` at x=2 / y=2). Ties the
## SOURCE_*/MARGIN_* constants to the ACTUAL texture content (independent source of
## truth = the asset), so reverting the crop to the old (3,3) inset — which
## scissored the top+left outline and rendered tan there — fails here.
##
## Root cause it locks: nine_slice_3d maps the OUTERMOST output border column to
## `source_region.xy` (1:1). So the leftmost drawn column samples frame.tga at
## (SOURCE_X, *) and the topmost at (*, SOURCE_Y) — those must be the dark outline.
## Oracle-verified 2026-08-10: the real machine draws that dark outline on all four
## window edges; the port dropped it top+left (user: "one more pixel, darker,
## provides an outline"). See UIFrame.gd SOURCE_* comment.

const UIFrameCls = preload("res://src/ui3/elements/UIFrame.gd")

# The ROM dark outline colour in frame.tga (8-bit, matches the live oracle framebuffer).
const OUTLINE := Vector3(48, 40, 32)
# A body/bevel pixel is decidedly lighter — the old (3,3) crop landed here on top+left.
const MIN_BODY_LUMA := 120.0

var _failed := false


func _ready() -> void:
	var img: Image = load(UIFrameCls.FRAME_TEXTURE_PATH).get_image()

	# The 9-slice's leftmost drawn column samples (SOURCE_X, y); topmost samples (x, SOURCE_Y).
	var sx: int = UIFrameCls.SOURCE_X
	var sy: int = UIFrameCls.SOURCE_Y
	var body_x: int = sx + int(UIFrameCls.SOURCE_W) / 2   # a middle (tiled body) column
	var body_y: int = sy + int(UIFrameCls.SOURCE_H) / 2

	# LEFT edge: the outer border column IS the dark outline (not tan body).
	_expect_outline(img, sx, body_y, "LEFT outline column (SOURCE_X=%d)" % sx)
	# TOP edge: the outer border row IS the dark outline.
	_expect_outline(img, body_x, sy, "TOP outline row (SOURCE_Y=%d)" % sy)

	# And the crop's right/bottom edges still land on the (already-correct) dark border,
	# so the frame is a full dark ring (no regression on the edges the old crop kept).
	var rx: int = sx + int(UIFrameCls.SOURCE_W) - 1
	var by: int = sy + int(UIFrameCls.SOURCE_H) - 1
	_expect_dark(img, rx, body_y, "RIGHT edge (SOURCE_X+W-1=%d)" % rx)
	_expect_dark(img, body_x, by, "BOTTOM edge (SOURCE_Y+H-1=%d)" % by)

	if _failed:
		printerr("[FAIL] UIFrameOutlineTest")
	else:
		print("[PASS] UIFrameOutlineTest: default crop keeps the ROM dark outline on all 4 edges")
	get_tree().quit(1 if _failed else 0)


func _px(img: Image, x: int, y: int) -> Vector3:
	var c := img.get_pixel(x, y)
	return Vector3(round(c.r * 255.0), round(c.g * 255.0), round(c.b * 255.0))


func _expect_outline(img: Image, x: int, y: int, what: String) -> void:
	var p := _px(img, x, y)
	if (p - OUTLINE).length() > 8.0:
		_failed = true
		printerr("  %s: frame.tga(%d,%d) = %s, want dark outline %s" % [what, x, y, p, OUTLINE])


func _expect_dark(img: Image, x: int, y: int, what: String) -> void:
	var p := _px(img, x, y)
	# the bottom/right outline is a slightly different dark (32,24,16); just require "dark".
	if (p.x + p.y + p.z) / 3.0 > 80.0:
		_failed = true
		printerr("  %s: frame.tga(%d,%d) = %s, want a dark edge" % [what, x, y, p])
