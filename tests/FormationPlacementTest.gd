extends Node
# test-kind: logic
# seeded-break: FormationScene.rom_body_rect's two anchor constants swapped (X gets +BODY_ANCHOR_DY, Y gets +BODY_ANCHOR_DX — the +31/+24 ROM anchor transposed); all 16 body tl/centre arms and both live cell7 ground-truth assertions (body (211,100,24,40), shadow (211,130,20,10)) red; the size arms, the shadow offsets relative to the seeded body, the wide-shadow arm, the bbox/centre fallbacks, and the scale round-trip / feet-offset arms stay green; GREEN unbroken on the reverted tree

## FormationScene ROM placement test (bug #2, FORMATION_ELEMENT_PLACEMENT.md) —
## pure GDScript, no GPU. Guards the byte-exact body + drop-shadow rects against
## the decompiled formulas and the live-verified cell7 anchor.
##
##   Body  (FUN_80117db8 @0x80117db8): top-left = (cellX − Uw/2 + 31, cellY − Vh/2 + 24),
##         size = Uw×Vh, drawn native 1:1. cellX = col*62 + 6, cellY = 36 + row*60.
##   Shadow(FUN_8011814c 2nd prim): narrow (Uw<0x19) at (bodyLeft, bodyTop+30),
##         wide at (bodyLeft+12, bodyTop+35); size 20×10 (2:1 squash of a 20×20 texel).
##   Live (sstate0, pcsx :8080): cell7 (col3,row1) shadow template X=211, Y=130 —
##         body (211,100,24,40), shadow (211,130,20,10). See the living doc §5.

const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")
const SpriteLayerManager = ExMateriaSpriteRig.SpriteLayerManager
func _ready() -> void:
	var failed := false

	# --- Grid anchors (cellX = col*62+6, cellY = 36+row*60) ---------------------
	var expect_cellx := [6, 68, 130, 192]
	var expect_celly := [36, 96]
	for row in range(2):
		for col in range(4):
			var b: Rect2 = FormationScene.rom_body_rect(col, row, 24.0, 40.0)
			# body centre must be (cellX+31, cellY+24), size 24×40
			var cx: float = expect_cellx[col]
			var cy: float = expect_celly[row]
			var want_tl := Vector2(cx + 19.0, cy + 4.0)   # 31−12, 24−20
			if not b.position.is_equal_approx(want_tl):
				print("[FAIL] body[%d,%d] tl=%s want=%s" % [col, row, b.position, want_tl]); failed = true
			if not b.size.is_equal_approx(Vector2(24.0, 40.0)):
				print("[FAIL] body[%d,%d] size=%s want 24x40" % [col, row, b.size]); failed = true
			if not (b.position + b.size * 0.5).is_equal_approx(Vector2(cx + 31.0, cy + 24.0)):
				print("[FAIL] body[%d,%d] centre=%s want=%s" %
					[col, row, b.position + b.size * 0.5, Vector2(cx + 31.0, cy + 24.0)]); failed = true

	# --- Shadow: at (bodyLeft, bodyTop+30), 20×10, narrow (roster Uw=24<25) ------
	for row in range(2):
		for col in range(4):
			var b: Rect2 = FormationScene.rom_body_rect(col, row, 24.0, 40.0)
			var s: Rect2 = FormationScene.rom_shadow_rect(col, row, 24.0, 40.0)
			if not s.position.is_equal_approx(Vector2(b.position.x, b.position.y + 30.0)):
				print("[FAIL] shadow[%d,%d] pos=%s want=%s" %
					[col, row, s.position, Vector2(b.position.x, b.position.y + 30.0)]); failed = true
			if not s.size.is_equal_approx(Vector2(20.0, 10.0)):
				print("[FAIL] shadow[%d,%d] size=%s want 20x10" % [col, row, s.size]); failed = true

	# --- Live ground truth: cell7 (col3,row1) = the last-drawn shadow template ---
	var b7: Rect2 = FormationScene.rom_body_rect(3, 1, 24.0, 40.0)
	var s7: Rect2 = FormationScene.rom_shadow_rect(3, 1, 24.0, 40.0)
	if not b7.is_equal_approx(Rect2(211, 100, 24, 40)):
		print("[FAIL] cell7 body=%s want (211,100,24,40)" % b7); failed = true
	if not s7.is_equal_approx(Rect2(211, 130, 20, 10)):
		print("[FAIL] cell7 shadow=%s want (211,130,20,10) [live template X=211 Y=130]" % s7); failed = true

	# --- Wide (monster) branch: (bodyLeft+12, bodyTop+35) ------------------------
	var bw: Rect2 = FormationScene.rom_body_rect(0, 0, 40.0, 48.0)  # Uw=40 ≥ 0x19
	var sw: Rect2 = FormationScene.rom_shadow_rect(0, 0, 40.0, 48.0)
	if not sw.position.is_equal_approx(Vector2(bw.position.x + 12.0, bw.position.y + 35.0)):
		print("[FAIL] wide shadow pos=%s want=%s" %
			[sw.position, Vector2(bw.position.x + 12.0, bw.position.y + 35.0)]); failed = true

	# --- compute_body_bbox: piece-rect fallback when the atlas image is null -----
	# Two pieces at loc (10,20) 8×8 and (14,24) 8×8 → union bbox (10,20,12,12).
	var rects := [Vector2(0, 0), Vector2(8, 0)]
	var rect_sizes := [Vector2(8, 8), Vector2(8, 8)]
	var locs := [Vector2(10, 20), Vector2(14, 24)]
	var bbox: Rect2 = SpriteLayerManager.compute_body_bbox(null, rects, rect_sizes, locs)
	if not bbox.is_equal_approx(Rect2(10, 20, 12, 12)):
		print("[FAIL] compute_body_bbox fallback=%s want (10,20,12,12)" % bbox); failed = true
	# compute_body_center stays the bbox centre.
	var ctr: Vector2 = SpriteLayerManager.compute_body_center(null, rects, rect_sizes, locs)
	if not ctr.is_equal_approx(Vector2(16, 26)):
		print("[FAIL] compute_body_center=%s want (16,26)" % ctr); failed = true

	# --- Calibration: k∘body_scale_for_bbox round-trips a height to target_vh ----
	for h in [20.0, 34.0, 51.0]:
		var sc: float = FormationScene.body_scale_for_bbox(h, 40.0)
		var got: float = h * FormationScene.body_loc_to_screen_k(sc)
		if abs(got - 40.0) > 0.001:
			print("[FAIL] scale round-trip h=%s -> vis=%s want 40" % [h, got]); failed = true

	# --- derive_body_offset_px lands the visible FEET on the standing baseline -----
	# For any bbox+scale, cell_origin + offset + (foot+BIAS)*k must equal the feet
	# target (cellX+BODY_ANCHOR_DX, cellY+FEET_BASELINE_DY); foot = bbox bottom-centre.
	var tb := Rect2(30, 40, 16, 34)
	var tscale := 9.0
	var want_feet := Vector2(FormationScene.BODY_ANCHOR_DX, FormationScene.FEET_BASELINE_DY)
	var toff: Vector2 = FormationScene.derive_body_offset_px(tb, tscale, want_feet)
	var tk: float = FormationScene.body_loc_to_screen_k(tscale)
	var tfoot := Vector2(tb.position.x + tb.size.x * 0.5, tb.position.y + tb.size.y) + FormationScene.BODY_LOC_BIAS
	var landed := toff + tfoot * tk
	if not landed.is_equal_approx(want_feet):
		print("[FAIL] derive_body_offset feet land=%s want=%s" % [landed, want_feet]); failed = true

	if failed:
		print("[FAIL] FormationPlacement test")
	else:
		print("[PASS] FormationPlacement: body+shadow rects match ROM formulas + live cell7")
	get_tree().quit()
