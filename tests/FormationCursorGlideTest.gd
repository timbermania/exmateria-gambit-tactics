extends Node
# test-kind: logic
# seeded-break: box_glide_step's converged snap disabled (_glide_axis's `next == cur` stall returns the stalled value instead of the target) — 'RIGHT/DOWN glide cadence mismatch' RED at the final step (eases to 93/118 and stalls there instead of snapping to 96/121) and 'glide did not converge to target' RED; the next_cell clamps, the fixed-point-at-target, the decreasing-axis, and every falloff_px arm stay green; GREEN unbroken on the reverted tree

## Cursor GLIDE + nav guard (formation screen) — pure GDScript, no GPU.
##
## The logical cursor (selected_cell) SNAPS; the visible gold box + floor pool EASE
## toward it via the integer law `next = (3·cur + target) >> 2` per axis (§11.5.2 /
## §16.1), leaving a fading trail. This guards the three pure pieces the scene builds on:
##   1. next_cell — one grid step, clamped to the 4×2 grid;
##   2. box_glide_step — the eased cadence, DYNAMICALLY captured off the live OT
##      (RIGHT centre_x 48→…→93 for target 96; DOWN centre_y 75→…→118 for target 121);
##   3. falloff_px — the abs-px sweep form reduces EXACTLY to spatial_falloff_level at
##      settle (so the swept orbs/bodies match the built index-based levels).

const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")


func _ready() -> void:
	var failed := false

	# --- 1. next_cell: steps within the grid, clamps at every edge ---------------
	if FormationScene.next_cell(Vector2i(0, 0), Vector2i(1, 0)) != Vector2i(1, 0):
		print("[FAIL] next_cell right from (0,0)"); failed = true
	if FormationScene.next_cell(Vector2i(0, 0), Vector2i(0, 1)) != Vector2i(0, 1):
		print("[FAIL] next_cell down from (0,0)"); failed = true
	# Clamps: left/up at the top-left, right/down at the bottom-right.
	if FormationScene.next_cell(Vector2i(0, 0), Vector2i(-1, 0)) != Vector2i(0, 0):
		print("[FAIL] next_cell left clamp at (0,0)"); failed = true
	if FormationScene.next_cell(Vector2i(0, 0), Vector2i(0, -1)) != Vector2i(0, 0):
		print("[FAIL] next_cell up clamp at (0,0)"); failed = true
	if FormationScene.next_cell(Vector2i(3, 0), Vector2i(1, 0)) != Vector2i(3, 0):
		print("[FAIL] next_cell right clamp at col 3"); failed = true
	if FormationScene.next_cell(Vector2i(3, 1), Vector2i(0, 1)) != Vector2i(3, 1):
		print("[FAIL] next_cell down clamp at row 1"); failed = true

	# --- 2. box_glide_step: oracle ease cadence, then SNAP exactly onto the cell ---
	# The gliding steps match the live-OT captures byte-for-byte; the FINAL step converges
	# to the exact target instead of the raw floor()-stall (~3px short) so the settled box
	# sits on the unit consistently regardless of approach direction (see box_glide_step).
	# RIGHT press: centre_x eases 48 → 93 (oracle) then snaps to target 96.
	var right_want := [60.0, 69.0, 75.0, 80.0, 84.0, 87.0, 89.0, 90.0, 91.0, 92.0, 93.0, 96.0]
	if not _glide_axis_matches(48.0, 96.0, right_want):
		print("[FAIL] RIGHT glide cadence mismatch"); failed = true
	# DOWN press: centre_y eases 75 → 118 (oracle) then snaps to target 121.
	var down_want := [86.0, 94.0, 100.0, 105.0, 109.0, 112.0, 114.0, 115.0, 116.0, 117.0, 118.0, 121.0]
	if not _glide_axis_matches(75.0, 121.0, down_want):
		print("[FAIL] DOWN glide cadence mismatch"); failed = true

	# At convergence the glide SNAPS to the exact target (lands centered on the cell)…
	var converge: Vector2 = FormationScene.box_glide_step(Vector2(93.0, 118.0), Vector2(96.0, 121.0))
	if converge != Vector2(96.0, 121.0):
		print("[FAIL] glide did not converge to target: %s" % converge); failed = true
	# …and once AT the target it holds (a true fixed point, so the trail settles).
	var held: Vector2 = FormationScene.box_glide_step(Vector2(96.0, 121.0), Vector2(96.0, 121.0))
	if held != Vector2(96.0, 121.0):
		print("[FAIL] glide not a fixed point at target: %s" % held); failed = true

	# Decreasing axes reach the target EXACTLY too.
	var down_left: Vector2 = FormationScene.box_glide_step(Vector2(35.0, 35.0), Vector2(34.0, 34.0))
	if down_left != Vector2(34.0, 34.0):
		print("[FAIL] decreasing glide did not reach target: %s" % down_left); failed = true

	# --- 3. falloff_px reduces to the index-based falloff at settle --------------
	# Feeding both element and centre their cell-origin px (offset cancels) must equal
	# spatial_falloff_level for the same cell pair, so the swept levels == the built ones.
	var sel := Vector2i(0, 0)
	var scale := 0.20
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 0), Vector2i(0, 1), Vector2i(3, 1)]:
		var idx: float = FormationScene.spatial_falloff_level(cell, sel, scale)
		var px: float = FormationScene.falloff_px(
			FormationScene.cell_origin_px(cell.x, cell.y),
			FormationScene.cell_origin_px(sel.x, sel.y), scale)
		if abs(idx - px) > 1e-4:
			print("[FAIL] falloff_px %s: index=%f px=%f (must agree at settle)" % [cell, idx, px]); failed = true

	# The eased centre is BRIGHTEST at the glide point (== base, then adds the pulse).
	var at_centre: float = FormationScene.falloff_px(Vector2(50.0, 50.0), Vector2(50.0, 50.0), scale)
	if abs(at_centre - 128.0) > 1e-6:
		print("[FAIL] falloff_px centre=%f want 128" % at_centre); failed = true
	# 2:1 oval: a horizontal step D and a vertical step D/2 give equal falloff.
	var h: float = FormationScene.falloff_px(Vector2(90.0, 50.0), Vector2(50.0, 50.0), scale)
	var v: float = FormationScene.falloff_px(Vector2(50.0, 70.0), Vector2(50.0, 50.0), scale)
	if abs(h - v) > 1e-4:
		print("[FAIL] falloff_px not 2:1 oval: h(+40)=%f v(+20)=%f" % [h, v]); failed = true

	if failed:
		print("[FAIL] FormationCursorGlide test")
	else:
		print("[PASS] FormationCursorGlide: nav clamps, glide cadence byte-exact, sweep==settle falloff")
	get_tree().quit()


## Run the integer glide law on one axis from `start` toward `target` and compare the
## produced sequence against the captured oracle `want`.
func _glide_axis_matches(start: float, target: float, want: Array) -> bool:
	var cur := start
	var ok := true
	for i in want.size():
		cur = FormationScene.box_glide_step(Vector2(cur, 0.0), Vector2(target, 0.0)).x
		if abs(cur - want[i]) > 1e-6:
			print("  [glide] step %d: got %f want %f (start=%f target=%f)" % [i, cur, want[i], start, target])
			ok = false
	return ok
