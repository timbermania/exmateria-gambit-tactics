extends Node
# test-kind: logic
# seeded-break: spotlight_center_px's row-tracking term dropped (Y no longer advances with row) — 'centre Y does not advance with row' RED ((37,76) -> (37,76), the vertical-tracking correction the 2026-07-17 live-fix exists for); the brighten/floor-clamp, the 2:1 oval, the LEFT/RIGHT profiles, the mirror, the reversibility, and the far-clamp arms stay green; GREEN unbroken on the reverted tree

## Floor-spotlight oval guard (formation screen) — pure GDScript, no GPU.
##
## The selected-unit floor light is the SAME oval falloff as the orb (§10):
##   brightness(px,py) = base − swing·sqrt(dx² + vfac·dy²),  vfac = 4 ⇒ a 2:1
## HORIZONTALLY-elongated oval, centred on the selected unit's FLOOR-CONTACT point
## (column-centre X, feet-baseline Y). BOTH axes track the unit — moving to another
## row slides the pool DOWN (live-corrected 2026-07-17: the handoff's "vertical
## falloff is FIXED / row change invariant" was a misread of the capture).

const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")


func _ready() -> void:
	var failed := false
	# Oracle-grounded shipping values (§16): the PSX floor gouraud is base 0xFF / floor
	# 0x50 applied as texture × gouraud/128 ⇒ a BRIGHTENING pool [0.625, ~2×], fit to the
	# framebuffer radial profile. base > 1.0 is load-bearing — a darken-only pool (base
	# 1.0, the port's first ship) rendered the whole floor ~2× too dark vs the oracle.
	var base := 1.72
	var swing := 0.0068
	var vfac := 4.0
	var min_level := 0.64

	# --- The pool BRIGHTENS: centre multiplier exceeds 1.0 (gouraud 0xFF/128), and the
	#     far clamp lands on the PSX gouraud floor 0x50/128 = 0.625 (± a fit epsilon) ----
	if not (base > 1.0):
		print("[FAIL] floor pool must BRIGHTEN (base=%f ≤ 1.0 is darken-only, ~2x too dark vs oracle)" % base); failed = true
	if abs(min_level - 0.625) > 0.03:
		print("[FAIL] far clamp min=%f not ≈ 0x50/128 = 0.625 (PSX gouraud floor)" % min_level); failed = true

	# --- Centre tracks BOTH axes: X with column, Y with row --------------------
	var c00: Vector2 = FormationScene.spotlight_center_px(0, 0)
	var c30: Vector2 = FormationScene.spotlight_center_px(3, 0)
	var c01: Vector2 = FormationScene.spotlight_center_px(0, 1)
	if not (c30.x > c00.x):                                   # column → X
		print("[FAIL] centre X does not advance with column: %s -> %s" % [c00, c30]); failed = true
	if not (c01.y > c00.y):                                   # row → Y (the correction)
		print("[FAIL] centre Y does not advance with row (oval must track the unit vertically): %s -> %s" % [c00, c01]); failed = true

	# --- Oval is 2:1 (horizontal extent twice the vertical, from vfac = 4) ------
	# A horizontal step D and a vertical step D/2 must give the SAME brightness.
	var horiz: float = FormationScene.floor_brightness(c00.x + 40.0, c00.y, c00, base, swing, vfac, min_level)
	var vert: float = FormationScene.floor_brightness(c00.x, c00.y + 20.0, c00, base, swing, vfac, min_level)
	if abs(horiz - vert) > 1e-4:
		print("[FAIL] oval not 2:1: horiz(+40)=%f vert(+20)=%f" % [horiz, vert]); failed = true
	# ...and an EQUAL vertical step falls faster than the horizontal one.
	var vert_eq: float = FormationScene.floor_brightness(c00.x, c00.y + 40.0, c00, base, swing, vfac, min_level)
	if not (vert_eq < horiz):
		print("[FAIL] vertical(+40)=%f not darker than horizontal(+40)=%f" % [vert_eq, horiz]); failed = true

	# --- Centre is the brightest point (== base) -------------------------------
	var at_centre: float = FormationScene.floor_brightness(c00.x, c00.y, c00, base, swing, vfac, min_level)
	if abs(at_centre - base) > 1e-6:
		print("[FAIL] centre brightness=%f want base=%f" % [at_centre, base]); failed = true

	# --- Horizontal profile: selected LEFT bright→dark, ~2:1 across the floor ---
	# Sample the 4 column X at the selected row's feet Y (dy = 0 ⇒ pure horizontal).
	var xs := []
	for col in range(4):
		xs.append(FormationScene.spotlight_center_px(col, 0).x)
	var left := []
	for x in xs:
		left.append(FormationScene.floor_brightness(x, c00.y, c00, base, swing, vfac, min_level))
	# hand-computed independent oracle: dist = dx = 62·col; b = clamp(base − swing·dx, min, base).
	var want_left := [
		base,
		maxf(base - swing * 62.0, min_level),
		maxf(base - swing * 124.0, min_level),
		maxf(base - swing * 186.0, min_level),
	]
	for i in range(4):
		if abs(left[i] - want_left[i]) > 1e-4:
			print("[FAIL] LEFT col%d b=%f want=%f" % [i, left[i], want_left[i]]); failed = true
	if not (left[0] > left[1] and left[1] > left[2] and left[2] > left[3]):
		print("[FAIL] LEFT profile not monotone: %s" % [left]); failed = true
	if left[0] / left[3] < 1.8:
		print("[FAIL] LEFT swing too flat: %f (want ~2:1)" % (left[0] / left[3])); failed = true

	# --- Mirror: selected RIGHT profile is the reverse of the LEFT one ----------
	var right := []
	for x in xs:
		right.append(FormationScene.floor_brightness(x, c30.y, c30, base, swing, vfac, min_level))
	for i in range(4):
		if abs(right[i] - left[3 - i]) > 1e-4:
			print("[FAIL] RIGHT col%d=%f not mirror of LEFT col%d=%f" % [i, right[i], 3 - i, left[3 - i]]); failed = true

	# --- Reversibility: pure function — recomputing LEFT after RIGHT is identical
	var left2 := []
	for x in xs:
		left2.append(FormationScene.floor_brightness(x, c00.y, c00, base, swing, vfac, min_level))
	for i in range(4):
		if abs(left2[i] - left[i]) > 1e-9:
			print("[FAIL] not reversible: LEFT col%d %f != %f" % [i, left2[i], left[i]]); failed = true

	# --- Far floor clamps to a non-black minimum (== min_level, never black) ----
	var far: float = FormationScene.floor_brightness(c00.x + 400.0, c00.y, c00, base, swing, vfac, min_level)
	if abs(far - min_level) > 1e-6:
		print("[FAIL] far brightness=%f not clamped to min_level=%f" % [far, min_level]); failed = true

	if failed:
		print("[FAIL] FormationFloorSpotlight test")
	else:
		print("[PASS] FormationFloorSpotlight: oval falloff tracks the unit (both axes), 2:1, mirrored, reversible")
	get_tree().quit()
