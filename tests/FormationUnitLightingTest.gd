extends Node
# test-kind: logic
# seeded-break: spatial_falloff_level's 2:1 oval distance drops its row term (sqrt(dx² + 4·dy²) -> sqrt(dx²)); 'row-below body not dimmer than selected (both axes must track)' RED (row level = 128 = selected); every column-dim/monotone, clamp-floor, multiplier-range, and purity arm stays green; GREEN unbroken on the reverted tree

## Unit-body spatial-falloff lighting guard (formation screen) — pure GDScript, no GPU.
##
## §16 (DYNAMIC-confirmed): the roster floor/orb/body "spotlight" is ONE spatial
## falloff (`orb_spatial_falloff`) written per-element. Unit BODIES sample it once at
## the body centre (base 200, clamped [0x50,0x80] = [80,128]) → a FLAT per-unit
## multiply: a unit farther from the selection renders uniformly dimmer. The port
## drives the body shader's `ambient_brightness` from `spatial_falloff_level(cell)`
## (the SAME [80,128] falloff the orb uses — one function, §10/§16), so this guards:
## selected == full (128), farther == dimmer, monotone, clamped to the [80,128] floor.

const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")

const BASE := 128.0   # ORB_BASE_LEVEL (PSX gouraud identity)
const MIN := 80.0     # ORB_MIN_LEVEL (falloff clamp floor)
const SCALE := 0.20   # orb_falloff_scale default (headful-tuned)


func _ready() -> void:
	var failed := false
	var sel := Vector2i(0, 0)

	# --- Selected cell renders at full identity (128 ⇒ ×1.0) -------------------
	var b_sel: float = FormationScene.spatial_falloff_level(sel, sel, SCALE)
	if abs(b_sel - BASE) > 1e-6:
		print("[FAIL] selected body level=%f want base=%f" % [b_sel, BASE]); failed = true

	# --- A farther unit is dimmer; monotone with distance ----------------------
	var b_near: float = FormationScene.spatial_falloff_level(Vector2i(1, 0), sel, SCALE)
	var b_mid: float = FormationScene.spatial_falloff_level(Vector2i(2, 0), sel, SCALE)
	var b_far: float = FormationScene.spatial_falloff_level(Vector2i(3, 1), sel, SCALE)
	if not (b_near < b_sel):
		print("[FAIL] near body %f not dimmer than selected %f" % [b_near, b_sel]); failed = true
	if not (b_mid < b_near):
		print("[FAIL] body falloff not monotone in column: near=%f mid=%f" % [b_near, b_mid]); failed = true
	if not (b_far < b_near):
		print("[FAIL] diagonal-far body %f not dimmer than near %f" % [b_far, b_near]); failed = true

	# --- Row change dims too (BOTH axes track — §16, oval vfac=4) --------------
	var b_row: float = FormationScene.spatial_falloff_level(Vector2i(0, 1), sel, SCALE)
	if not (b_row < b_sel):
		print("[FAIL] row-below body %f not dimmer than selected %f (both axes must track)" % [b_row, b_sel]); failed = true

	# --- Never darker than the [80,128] clamp floor ----------------------------
	var b_corner: float = FormationScene.spatial_falloff_level(Vector2i(3, 1), sel, SCALE)
	if b_corner < MIN - 1e-6:
		print("[FAIL] far body level=%f below clamp floor %f" % [b_corner, MIN]); failed = true

	# --- The shader multiplier is the level / 128 ⇒ [0.625, 1.0] ---------------
	var mult_sel := b_sel / BASE
	var mult_far := b_far / BASE
	if abs(mult_sel - 1.0) > 1e-6:
		print("[FAIL] selected ambient multiplier=%f want 1.0" % mult_sel); failed = true
	if not (mult_far >= MIN / BASE - 1e-6 and mult_far < 1.0):
		print("[FAIL] far ambient multiplier=%f out of [%f,1.0)" % [mult_far, MIN / BASE]); failed = true

	# --- Pure function: same inputs → same output (reversible) -----------------
	var again: float = FormationScene.spatial_falloff_level(Vector2i(1, 0), sel, SCALE)
	if abs(again - b_near) > 1e-9:
		print("[FAIL] spatial_falloff_level not pure: %f != %f" % [again, b_near]); failed = true

	if failed:
		print("[FAIL] FormationUnitLighting test")
	else:
		print("[PASS] FormationUnitLighting: bodies take the shared [80,128] falloff (both axes), far units dimmer")
	get_tree().quit()
