extends Node
## Golden tests for [DialogueBoxPlacement] — the pure native-px PSX dialogue-box
## placement solver. No VM, no nodes, no camera: the whole point of isolating the
## integer math is that it can be pinned directly against the live PSX captures.
##
## Golden data:
##   research/working_documents/scenario_1_captures/dialogue_box_triangle_aim_decode.md
##   §2  — the live authored-operand table (proj X/Y, Dialog, X58/Y5c/fineX60,
##         arrow byte, w68, and the resulting box-local tail tri_boxX).
##   §7.4 — the live arrow-X / portrait-side / portrait-X confirmation table.
##
## These lines are captured in the PSX CODE/DRAW frame, so the tests pass proj_x in
## that frame with the doc's literal clamp bounds [0x88, 0x180] / [0x16, 0xe4]. Box
## width `w = w68 + 0x40` — box-type 0x10 reserves the 0x40 portrait region even
## when it overrides the measured width (this +0x40 is exactly what makes tri_boxX
## land at 70/52/71/86/74 rather than 38/... — verified line-by-line).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/DialogueBoxPlacementTest.tscn

const Placement = preload("res://src/scenarios/DialogueBoxPlacement.gd")

# PSX code-frame clamp bounds (decode §1b): box_left/tri_scr clamp [0x88, 0x180].
const CODE_X_LO := 0x88
const CODE_X_HI := 0x180
const CODE_Y_LO := 0x16
const CODE_Y_HI := 0xe4
const PORTRAIT_PAD := 0x40   # box-type 0x10 reserves 0x40 for the portrait region

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_tri_box_x_golden_lines()
	_test_authored_offsets_move_tail_left()   # the Female-Knight smoking gun
	_test_arrow_x_inset_golden()              # §7.4
	_test_portrait_side_and_x_golden()        # §7.1 / §7.4
	_test_edge_clamp_shove_flips_portrait()
	_test_arrow_y_align_and_bubble()

	print("\n=== DialogueBoxPlacementTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] DialogueBoxPlacementTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] DialogueBoxPlacementTest")
		get_tree().quit(1)
	else:
		print("[PASS] DialogueBoxPlacementTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got %s, want %s" % [name, str(got), str(want)])


func _ok(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


# Solve a §2 line in the PSX code frame with w = w68 + 0x40.
func _solve_code(proj_x: int, proj_y: int, w68: int, dialog: int,
		arrow_byte: int, x58: int, y5c: int, fine_x60: int, box_h: int = 48) -> Dictionary:
	return Placement.solve(
		proj_x, proj_y, w68 + PORTRAIT_PAD, box_h,
		dialog, arrow_byte, x58, y5c, fine_x60, -1,
		CODE_X_LO, CODE_X_HI, CODE_Y_LO, CODE_Y_HI)


# §2 live table — the box-local tail tri_boxX (and the local_b8 behind it) must
# reproduce the captured values exactly. Each exercises a different combination of
# align tweak, edge-clamp shove, and authored fine-X.
func _test_tri_box_x_golden_lines() -> void:
	# prayer/3 Ovelia (still): align 2, all authored offsets 0 → centred tail.
	var r3 := _solve_code(235, 160, 92, 0x92, 0x03, 0, 0, 0)
	_eq(r3["tri_box_x"], 70, "p3 tri_box_x")
	_eq(r3["local_b8"], 0, "p3 local_b8")

	# prayer/4: align 2, Y5c=−8, fineX60=12, but the box clamps against the left
	# edge → shove −37, +fineX 12 → local_b8 = −25; tri_box_x = 85 − 25 − 8 = 52.
	var r4 := _solve_code(196, 142, 106, 0x92, 0x02, 0, -8, 12)
	_eq(r4["tri_box_x"], 52, "p4 tri_box_x")
	_eq(r4["local_b8"], -25, "p4 local_b8")

	# prayer/5: align 1 (box above), zero authored → tail centred BUT the +0xC
	# align tweak pushes box_left to 134 < 0x88, clamp shove −2 → tri_box_x = 71.
	var r5 := _solve_code(207, 121, 98, 0x91, 0x01, 0, 0, 0)
	_eq(r5["tri_box_x"], 71, "p5 tri_box_x")
	_eq(r5["local_b8"], -2, "p5 local_b8")

	# prayer/6: align 2, fineX60=1, no clamp → local_b8 = 1, tri_box_x = 93+1−8 = 86.
	var r6 := _solve_code(242, 144, 122, 0x92, 0x00, 0, 0, 1)
	_eq(r6["tri_box_x"], 86, "p6 tri_box_x")
	_eq(r6["local_b8"], 1, "p6 local_b8")

	# fknight/16: align 1, X58=20 shoves the whole box right but doesn't clamp, so
	# local_b8 stays 0 → tri_box_x = 82 − 8 = 74 (tail still centred under unit).
	var r16 := _solve_code(230, 134, 100, 0x91, 0x00, 20, 0, 0)
	_eq(r16["tri_box_x"], 74, "fk16 tri_box_x")
	_eq(r16["local_b8"], 0, "fk16 local_b8")


# The Female-Knight line (§2 fknight/15, JSON msgid 16): authored X58=−31 shoves
# the box 31px left of the unit column, AND fineX60=−32 shoves the tail a further
# 32px left (tail-only). Net: the tail lands well LEFT of the projected unit — the
# hand-placement the all-zero model could never reproduce. w68=0 here so we can't
# pin the exact tri_boxX (text width unknown), but the DIRECTION is the whole point.
func _test_authored_offsets_move_tail_left() -> void:
	var w := 120  # representative; exact text width not captured for this line
	var authored := Placement.solve(289, 142, w, 48, 0x12, 0x00, -31, -6, -32, -1,
		CODE_X_LO, CODE_X_HI, CODE_Y_LO, CODE_Y_HI)
	var zero := Placement.solve(289, 142, w, 48, 0x12, 0x00, 0, 0, 0, -1,
		CODE_X_LO, CODE_X_HI, CODE_Y_LO, CODE_Y_HI)
	# Authored tail sits left of both the unit column and the zero-operand tail.
	_ok(authored["tri_scr_x"] < 289, "fk15 tail left of unit")
	_ok(authored["tri_scr_x"] < zero["tri_scr_x"], "fk15 authored tail left of zero-operand tail")
	# fineX60 negative → local_b8 negative → portrait flips to the LEFT dock.
	_ok(not authored["portrait_side_right"], "fk15 portrait on LEFT (local_b8 < 0)")


# §7.4 live table — the ▼ arrow X inset (0x3e on the right side, 0x1e else; the
# local_ac ≥ 8 reset never fires here since local_ac = −1). Assert both the inset
# selector and the resulting arrow_x = box_right − inset.
func _test_arrow_x_inset_golden() -> void:
	# [box_right, local_b8, local_ac, expected arrow_x]
	var rows := [
		[301, 0, -1, 239],    # b8 ≥ 0 → RIGHT → 0x3e
		[306, -25, -1, 276],  # b8 < 0 → LEFT → 0x1e
		[298, -2, -1, 268],   # b8 < 0 → LEFT → 0x1e
		[323, 1, -1, 261],    # b8 ≥ 0 → RIGHT → 0x3e
	]
	for row in rows:
		var box_right: int = row[0]
		var b8: int = row[1]
		var ac: int = row[2]
		var want: int = row[3]
		var inset := Placement.arrow_x_inset(ac, b8 >= 0)
		_eq(box_right - inset, want, "arrow_x br=%d b8=%d" % [box_right, b8])


# §7.1 / §7.4 — portrait side = sign(local_b8): RIGHT dock = box_right − 0x30,
# LEFT dock = box_left + 8 (mirrored). Validate the exact captured portrait_x.
func _test_portrait_side_and_x_golden() -> void:
	# [box_right, box_w, local_b8, expected side_right, expected portrait_x]
	var rows := [
		[301, 156, 0, true, 253],    # RIGHT: 301 − 0x30
		[306, 170, -25, false, 144], # LEFT:  (306 − 170) + 8 = 144
		[298, 162, -2, false, 144],  # LEFT:  (298 − 162) + 8 = 144
		[323, 186, 1, true, 275],    # RIGHT: 323 − 0x30
	]
	for row in rows:
		var box_right: int = row[0]
		var box_w: int = row[1]
		var b8: int = row[2]
		var want_right: bool = row[3]
		var want_px: int = row[4]
		var box_left := box_right - box_w
		var side_right := b8 >= 0
		var px := (box_right + Placement.PORTRAIT_RIGHT_OFF) if side_right \
			else (box_left + Placement.PORTRAIT_LEFT_OFF)
		_eq(side_right, want_right, "portrait side br=%d b8=%d" % [box_right, b8])
		_eq(px, want_px, "portrait_x br=%d b8=%d" % [box_right, b8])


# An edge-clamp shove alone (no authored fine-X) can drive local_b8 negative and
# flip the portrait to the LEFT — the "portrait jumped sides" the user saw (§7.1).
func _test_edge_clamp_shove_flips_portrait() -> void:
	# Unit far to the screen LEFT: box_left clamps up against X_LO, shove < 0.
	var r := Placement.solve(150, 140, 170, 48, 0x92, 0x00, 0, 0, 0, -1,
		CODE_X_LO, CODE_X_HI, CODE_Y_LO, CODE_Y_HI)
	_ok(r["local_b8"] < 0, "edge shove drives local_b8 negative")
	_ok(not r["portrait_side_right"], "edge shove flips portrait LEFT")


# ▼ arrow Y = box_top + h − 0x18, minus 8 when a tail exists and align != 2,
# minus a further 8 for the thinking-bubble flag (decode §7.2).
func _test_arrow_y_align_and_bubble() -> void:
	# align 2 (box below, arrow up): no −8. box_top = proj_y = 100, h = 64.
	var a2 := Placement.solve(200, 100, 160, 64, 0x92, 0x00, 0, 0, 0, -1,
		CODE_X_LO, CODE_X_HI, CODE_Y_LO, CODE_Y_HI)
	_eq(a2["arrow_y"], a2["box_top"] + 64 - 0x18, "arrow_y align2 no −8")
	# align 1 (box above): tail present, ce != 2 → −8.
	var a1 := Placement.solve(200, 100, 160, 64, 0x91, 0x00, 0, 0, 0, -1,
		CODE_X_LO, CODE_X_HI, CODE_Y_LO, CODE_Y_HI)
	_eq(a1["arrow_y"], a1["box_top"] + 64 - 0x18 - 8, "arrow_y align1 −8")
