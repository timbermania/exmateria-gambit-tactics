extends Node
## TDD guard for `FrameQuadTransform` — the frame quad read as translate / rotate / scale /
## shear over the sheet region, instead of as eight signed integers.
##
## The whole file is PURE: no window, no node, no screenshot. That is deliberate for this
## family (see the memory `studio-layout-measure-band-render-subviewport`), and it is what
## lets the round trip run against the REAL corpus rather than a fixture — the claim being
## guarded is "this decomposition is lossless for the game's own data", which a hand-made
## quad cannot support.
##
## Run: <GODOT> --path . --quit-after 1200 res://tests/EffectStudioFrameQuadTransformTest.tscn

const Q = preload("res://src/effects/studio/FrameQuadTransform.gd")
const Channel = preload("res://src/effects/studio/FramesetChannel.gd")
const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")

## Did every test reach its end? A GDScript runtime error inside a test unwinds SILENTLY,
## so a green summary with a short count is a FAILING run that looks like a passing one.
const _EXPECTED_TESTS := [
	"the_identity_is_the_sheet_region_on_the_origin",
	"the_reported_frame_reads_as_five_facts",
	"recompose_is_exact_over_the_real_corpus",
	"the_corpus_is_parallelograms_and_the_rest_is_within_a_pixel",
	"one_term_moves_and_the_others_keep_their_precision",
	"a_knob_lowers_to_only_the_components_it_moved",
	"a_scale_is_the_same_edit_either_way",
	"a_scale_preserves_every_ratio_in_the_group",
	"a_scale_does_not_shear_a_rotated_quad",
	"a_scale_is_refused_before_a_partial_write",
	"the_field_table_is_the_channels_inverse",
]

var _passed: int = 0
var _failed: int = 0
var _completed: Dictionary = {}


func _ready() -> void:
	_test_the_identity_is_the_sheet_region_on_the_origin()
	_test_the_reported_frame_reads_as_five_facts()
	_test_recompose_is_exact_over_the_real_corpus()
	_test_the_corpus_is_parallelograms_and_the_rest_is_within_a_pixel()
	_test_one_term_moves_and_the_others_keep_their_precision()
	_test_a_knob_lowers_to_only_the_components_it_moved()
	_test_a_scale_is_the_same_edit_either_way()
	_test_a_scale_preserves_every_ratio_in_the_group()
	_test_a_scale_does_not_shear_a_rotated_quad()
	_test_a_scale_is_refused_before_a_partial_write()
	_test_the_field_table_is_the_channels_inverse()

	for name in _EXPECTED_TESTS:
		if not _completed.has(name):
			_failed += 1
			print("[FAIL] %s never reached its end — a runtime error unwound it silently" % name)

	print("\n=== EffectStudioFrameQuadTransformTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioFrameQuadTransformTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioFrameQuadTransformTest")
		get_tree().quit(0)


## The base is the SHEET REGION's own size, centred on the origin — the author's framing.
## Sign folded out: a negative uv width is a mirror flag, not a smaller box.
func _test_the_identity_is_the_sheet_region_on_the_origin() -> void:
	_assert_eq(Q.base_size(_frame({"x": 8, "y": 40, "width": 40, "height": 40}, 0, 0, 40, 40)),
		Vector2i(40, 40), "the base is the sheet region's dimensions")
	_assert_eq(Q.base_size(_frame({"x": 127, "y": 87, "width": -40, "height": -40}, 0, 0, 40, 40)),
		Vector2i(40, 40), "a mirrored region has the same base — the sign is a flip, not a size")

	# A quad that IS the base reads as the identity: native size, no angle, no lean, on the
	# origin. 41.8% of the corpus is at scale 1.00x, so this is the common case, not a
	# contrived one.
	var t: Dictionary = Q.decompose(_frame({"x": 0, "y": 0, "width": 40, "height": 40},
		-20, -20, 40, 40))
	_assert_true(bool(t.get("ok", false)), "the identity quad decomposes")
	_assert_true(_near(t["scale"].x, 1.0) and _near(t["scale"].y, 1.0), "…at scale 1.00x")
	_assert_true(_near(t["rotation"], 0.0), "…at 0 degrees")
	_assert_true(_near(t["shear"], 0.0), "…with no shear")
	_assert_true(t["position"].is_equal_approx(Vector2.ZERO), "…centred on the origin")
	_assert_true(bool(t["affine"]), "…and needs no residual")
	_done("the_identity_is_the_sheet_region_on_the_origin")


## E317 frameset 16 frame 0 is the frame in the author's report — the eight numbers they
## called esoteric. Read as a transform it is four terms at rest and a two-pixel nudge,
## which is the whole argument for this file existing.
func _test_the_reported_frame_reads_as_five_facts() -> void:
	var frame := _frame({"x": 8, "y": 40, "width": 40, "height": 40}, -20, -18, 40, 40)
	var t: Dictionary = Q.decompose(frame)
	_assert_eq(t["base"], Vector2i(40, 40), "E317 fs16 fr0 samples a 40x40 sheet region")
	_assert_true(_near(t["scale"].x, 1.0) and _near(t["scale"].y, 1.0),
		"…drawn at 1.00x, native texel size")
	_assert_true(_near(t["rotation"], 0.0), "…at 0 degrees")
	_assert_true(_near(t["shear"], 0.0), "…with no shear")
	_assert_true(t["position"].is_equal_approx(Vector2(0, 2)),
		"…nudged 2 down from the origin, which is the only number in the frame that is not at rest")
	_done("the_reported_frame_reads_as_five_facts")


## THE CLAIM THIS FILE RESTS ON: the six terms are a LOSSLESS view of the eight numbers.
## Asserted against every frame of every `E###.BIN` in the project, not a fixture — if
## decomposing and recomposing an UNTOUCHED quad moved a single corner, the editor would
## silently rewrite seven components every time the author touched the eighth.
func _test_recompose_is_exact_over_the_real_corpus() -> void:
	var frames := _corpus()
	if frames.is_empty():
		print("[SKIP] no E### assets — corpus round trip skipped")
		_done("recompose_is_exact_over_the_real_corpus")
		return
	var checked := 0
	var moved := 0
	var first := ""
	for entry in frames:
		var frame: Dictionary = entry["frame"]
		var t: Dictionary = Q.decompose(frame)
		if not bool(t.get("ok", false)):
			continue
		checked += 1
		var back: Dictionary = Q.compose(t)
		for corner in Q.CORNERS:
			var a: Array = back.get(corner, [])
			var b: Array = frame.get("vertices", {}).get(corner, [])
			if a.size() < 2 or b.size() < 2:
				continue
			if int(a[0]) == int(b[0]) and int(a[1]) == int(b[1]):
				continue
			moved += 1
			if first == "":
				first = "%s fs%d fr%d %s: %s -> %s" % [entry["effect"], entry["fs"],
					entry["fr"], corner, str(b), str(a)]
			break
	_assert_true(checked > 20000, "the corpus round trip ran over the whole corpus (%d frames)" % checked)
	_assert_eq(moved, 0, "decompose -> compose moves NO corner of any corpus frame (first: %s)" % first)
	_done("recompose_is_exact_over_the_real_corpus")


## WHY SIX TERMS AND NOT EIGHT. Affine reaches every parallelogram; the two degrees of
## freedom it gives up are the projective ones that make a trapezoid. This is the
## measurement that says the corpus does not want them — and that the handful of exceptions
## are rounding on a rotated quad rather than a deliberate shape, so `residual` never has
## to carry more than a pixel.
func _test_the_corpus_is_parallelograms_and_the_rest_is_within_a_pixel() -> void:
	var frames := _corpus()
	if frames.is_empty():
		print("[SKIP] no E### assets — parallelogram census skipped")
		_done("the_corpus_is_parallelograms_and_the_rest_is_within_a_pixel")
		return
	var total := 0
	var affine := 0
	var worst := 0
	for entry in frames:
		var t: Dictionary = Q.decompose(entry["frame"])
		if not bool(t.get("ok", false)):
			continue
		total += 1
		if bool(t["affine"]):
			affine += 1
		else:
			var r: Vector2 = t["residual"]
			worst = maxi(worst, int(maxf(absf(r.x), absf(r.y))))
	var pct := 100.0 * float(affine) / float(maxi(1, total))
	_assert_true(pct > 99.0, "over 99%% of corpus quads are exact parallelograms (got %.2f%%)" % pct)
	_assert_eq(worst, 1, "and no non-parallelogram is off by more than ONE unit — "
		+ "the residual is rounding on a rotated quad, not a trapezoid")
	_done("the_corpus_is_parallelograms_and_the_rest_is_within_a_pixel")


## The author reads a rounded rotation; the transform keeps the exact one. If a scale edit
## recomposed from what the ROW displays, every untouched corner of the 8.89% of quads at a
## genuinely arbitrary angle would drift by the display rounding.
func _test_one_term_moves_and_the_others_keep_their_precision() -> void:
	# atan2(1,2) = 26.5651…°, which no row will show in full. The quad is deliberately LARGE
	# (179-unit edges, inside the 198x198 the corpus reaches): the corner displacement from
	# a rounding error is the error times the radius, so on a small quad rounding the angle
	# is harmless and on a big one it is not. The editor cannot know which it has.
	var frame := _rotated_frame(160, 160, 2, 1, 80)
	var t: Dictionary = Q.decompose(frame)
	_assert_true(absf(float(t["rotation"]) - 26.5651) < 0.01, "the stored angle is the exact one")
	_assert_true(absf(float(t["rotation"]) - round(float(t["rotation"]))) > 0.001,
		"…and it is NOT a whole number of degrees, so rounding it would move corners")

	var scaled: Dictionary = Q.with_term(t, "scale_x", 2.0)
	_assert_true(is_equal_approx(float(scaled["rotation"]), float(t["rotation"])),
		"changing scale leaves the rotation bit-for-bit alone")
	_assert_true(is_equal_approx(float(scaled["shear"]), float(t["shear"])),
		"…and the shear")
	_assert_true(scaled["position"].is_equal_approx(t["position"]),
		"…and the position")

	# On a quad this size the rounded angle IS enough to move a corner — which is why the
	# precision is kept in the transform rather than read back off the row.
	var coarse: Dictionary = Q.with_term(t, "rotation", round(float(t["rotation"])))
	var a: Dictionary = Q.compose(t)
	var b: Dictionary = Q.compose(coarse)
	_assert_true(a != b, "recomposing from the ROUNDED angle would move a corner")
	_done("one_term_moves_and_the_others_keep_their_precision")


## One knob is ONE undo entry, and a knob nudged back to where it started is not an entry
## at all. `vertex_edits` emits only the components that actually moved.
func _test_a_knob_lowers_to_only_the_components_it_moved() -> void:
	var frame := _frame({"x": 8, "y": 40, "width": 40, "height": 40}, -20, -18, 40, 40)
	var t: Dictionary = Q.decompose(frame)

	_assert_eq(Q.vertex_edits(3, 1, frame, t).size(), 0,
		"an untouched transform lowers to NO edits — not an undo entry to press through")

	# Slide the quad one to the right: all four corners' X move, no Y does.
	var moved: Dictionary = Q.with_term(t, "position_x", 1.0)
	var edits: Array = Q.vertex_edits(3, 1, frame, moved)
	_assert_eq(edits.size(), 4, "a translate in X lowers to exactly the four X components")
	var fields: Array = []
	for e in edits:
		fields.append(str(e["field_ref"]["field"]))
		_assert_eq(int(e["field_ref"]["frameset_index"]), 3, "each edit carries the frameset address")
		_assert_eq(int(e["field_ref"]["frame_index"]), 1, "…and the frame address")
		_assert_eq(str(e["field_ref"]["channel"]), "frameset", "…on the frameset channel")
	fields.sort()
	_assert_eq(fields, ["vertex_bl_x", "vertex_br_x", "vertex_tl_x", "vertex_tr_x"],
		"…and names the four raw fields FramesetChannel writes")

	# Typing a WIDTH is the same knob as a scale, in PSX units instead of as a ratio.
	var by_width: Dictionary = Q.with_term(t, "width", 80.0)
	var by_scale: Dictionary = Q.with_term(t, "scale_x", 2.0)
	_assert_eq(Q.compose(by_width), Q.compose(by_scale),
		"typing width 80 on a 40-wide base is the same edit as typing scale 2.00x")
	_done("a_knob_lowers_to_only_the_components_it_moved")


## The docstring claims multiplying the eight raw components IS multiplying scale, position
## and residual while leaving rotation and shear — a similarity scales lengths, not angles.
## `scale_edits` takes the short route, so the equivalence is asserted rather than trusted.
func _test_a_scale_is_the_same_edit_either_way() -> void:
	var framesets := _region_framesets()
	var members := Canvas.region_members(framesets, Canvas.region_of(framesets, 0, 0))
	_assert_true(members.size() >= 3, "the fixture region has several members")

	var ratio := 1.5
	var short_route: Array = Q.scale_edits(framesets, members, ratio)

	var long_route: Array = []
	for m in members:
		var fi := int(m["frameset_index"])
		var fj := int(m["frame_index"])
		var frame: Dictionary = framesets[fi]["frames"][fj]
		var t: Dictionary = Q.decompose(frame)
		var s: Dictionary = t.duplicate(true)
		s["scale"] = t["scale"] * ratio
		s["position"] = t["position"] * ratio
		s["residual"] = t["residual"] * ratio
		long_route.append_array(Q.vertex_edits(fi, fj, frame, s))

	_assert_eq(short_route.size(), long_route.size(),
		"both routes write the same number of components")
	_assert_eq(_edit_map(short_route), _edit_map(long_route),
		"multiplying the raw components IS multiplying scale+position and leaving the angles")
	_done("a_scale_is_the_same_edit_either_way")


## THE ADR-0099 dec. 3 AMENDMENT, asserted. Dec. 3 refuses a region vertex write because an
## ADDITIVE delta "would flatten a 6x growth ramp into a constant offset". The
## multiplicative form does not: every member's size ratio to every other member survives.
func _test_a_scale_preserves_every_ratio_in_the_group() -> void:
	var framesets := _region_framesets()
	var members := Canvas.region_members(framesets, Canvas.region_of(framesets, 0, 0))
	var before: Array = []
	for m in members:
		before.append(Canvas.quad_size(framesets[int(m["frameset_index"])]["frames"][int(m["frame_index"])]))
	# The fixture IS a ramp, like the corpus groups this is for (E019's biggest draws one
	# 23x23 block at ten sizes, 7x7 through 56x56).
	_assert_true(before[0] != before[before.size() - 1], "the fixture group is a growth ramp")

	_apply(framesets, Q.scale_edits(framesets, members, 2.0))

	var after: Array = []
	for m in members:
		after.append(Canvas.quad_size(framesets[int(m["frameset_index"])]["frames"][int(m["frame_index"])]))
	for i in range(members.size()):
		_assert_true(_near(float(after[i].x - 1) / float(maxi(1, before[i].x - 1)), 2.0, 0.05),
			"member %d doubled in width (%s -> %s)" % [i, str(before[i]), str(after[i])])
	# The ramp is the thing dec. 3 was protecting, so state it as a ramp and not only
	# per-member: the largest-to-smallest ratio is what an ADDITIVE delta would destroy.
	var span_before := float(before[before.size() - 1].x - 1) / float(maxi(1, before[0].x - 1))
	var span_after := float(after[after.size() - 1].x - 1) / float(maxi(1, after[0].x - 1))
	_assert_true(_near(span_before, span_after, 0.05),
		"and the group's largest-to-smallest ratio is unchanged (%.2f -> %.2f) — the ramp is still a ramp"
			% [span_before, span_after])
	_done("a_scale_preserves_every_ratio_in_the_group")


## 2,064 corpus frames have no edge axis-aligned. Scaling those per-axis in SCREEN space
## shears them; scaling about the origin is a similarity and cannot. `quad_orientation` is
## the instrument — it is what would report the damage.
func _test_a_scale_does_not_shear_a_rotated_quad() -> void:
	var frame := _rotated_frame(40, 40, 4, 3)
	_assert_eq(Canvas.quad_orientation(frame), "rotated", "the fixture quad is genuinely angled")
	var framesets: Array = [{"index": 0, "frames": [frame]}]
	var members: Array = [{"frameset_index": 0, "frame_index": 0}]
	var before: Dictionary = Q.decompose(frame)

	_apply(framesets, Q.scale_edits(framesets, members, 3.0))

	var after: Dictionary = Q.decompose(framesets[0]["frames"][0])
	_assert_eq(Canvas.quad_orientation(framesets[0]["frames"][0]), "rotated",
		"it is still a rotated quad, not a sheared one")
	_assert_true(absf(float(after["rotation"]) - float(before["rotation"])) < 0.01,
		"its angle is unchanged")
	_assert_true(absf(float(after["shear"]) - float(before["shear"])) < 0.01,
		"and no shear was introduced")
	_assert_true(_near(float(after["scale"].x) / float(before["scale"].x), 3.0, 0.02),
		"while it did in fact grow 3x")
	_done("a_scale_does_not_shear_a_rotated_quad")


## ADR-0099 dec. 4a: every member is asked BEFORE any of them is written. A clamp
## discovered halfway through 30 members is a partial edit with no diagnostic.
func _test_a_scale_is_refused_before_a_partial_write() -> void:
	var framesets := _region_framesets()
	var members := Canvas.region_members(framesets, Canvas.region_of(framesets, 0, 0))
	_assert_true(bool(Q.scale_verdict(framesets, members, 2.0).get("ok", false)),
		"a reasonable factor is allowed")

	var over: Dictionary = Q.scale_verdict(framesets, members, 100000.0)
	_assert_true(not bool(over.get("ok", true)), "a factor that leaves signed 16-bit is REFUSED")
	_assert_true(String(over.get("message", "")).contains("16-bit"),
		"…and the refusal says why (got '%s')" % String(over.get("message", "")))

	var collapse: Dictionary = Q.scale_verdict(framesets, members, 0.001)
	_assert_true(not bool(collapse.get("ok", true)),
		"a factor that collapses a member to no area is REFUSED — invisible and not "
		+ "recoverable by scaling back up")
	_assert_true(String(collapse.get("message", "")).contains("collapse"),
		"…and says so (got '%s')" % String(collapse.get("message", "")))
	_done("a_scale_is_refused_before_a_partial_write")


## This file's corner->field table and `FramesetChannel._VERTEX_FIELD` are inverses of each
## other. Kept honest by the guard rather than by hand: a name that drifted would address a
## component that silently never gets written.
func _test_the_field_table_is_the_channels_inverse() -> void:
	var seen: Dictionary = {}
	for corner in Q.CORNERS:
		for comp in range(2):
			var field: String = Q._FIELD[corner][comp]
			_assert_true(Channel._VERTEX_FIELD.has(field),
				"FramesetChannel writes the field '%s'" % field)
			var addr: Array = Channel._VERTEX_FIELD.get(field, [])
			_assert_eq(str(addr[0]) if addr.size() > 0 else "", corner,
				"'%s' addresses the %s corner" % [field, corner])
			_assert_eq(int(addr[1]) if addr.size() > 1 else -1, comp,
				"'%s' addresses component %d" % [field, comp])
			seen[field] = true
	_assert_eq(seen.size(), Channel._VERTEX_FIELD.size(),
		"and the two tables name the same eight components")
	_done("the_field_table_is_the_channels_inverse")


# ── fixtures ─────────────────────────────────────────────────────────────────────────

## An upright frame: a `w`x`h` quad with its top-left at (tlx, tly).
func _frame(uv: Dictionary, tlx: int, tly: int, w: int, h: int) -> Dictionary:
	return {
		"index": 0, "palette_id": 0, "semi_trans_mode": 1, "semi_trans_on": true,
		"is_8bpp": false, "uv": uv,
		"vertices": {
			"top_left": [tlx, tly], "top_right": [tlx + w, tly],
			"bottom_left": [tlx, tly + h], "bottom_right": [tlx + w, tly + h],
		},
	}


## A quad rotated by atan2(dy, dx) — a 3-4-5 triangle gives an angle no row can display in
## full, which is the point.
func _rotated_frame(uw: int, uh: int, dx: int, dy: int, mult: int = 8) -> Dictionary:
	var u := Vector2i(dx * mult, dy * mult)          # top edge
	var v := Vector2i(-dy * mult, dx * mult)         # perpendicular side edge
	return {
		"index": 0, "palette_id": 0, "semi_trans_mode": 1, "semi_trans_on": true,
		"is_8bpp": false, "uv": {"x": 0, "y": 0, "width": uw, "height": uh},
		"vertices": {
			"top_left": [0, 0], "top_right": [u.x, u.y],
			"bottom_left": [v.x, v.y], "bottom_right": [u.x + v.x, u.y + v.y],
		},
	}


## A growth ramp on ONE shared sheet region, across several framesets — the shape 81.4% of
## corpus regions actually have, and the case ADR-0099 dec. 3 was reasoning about.
func _region_framesets() -> Array:
	var uv := {"x": 8, "y": 40, "width": 40, "height": 40}
	var out: Array = []
	for i in range(5):
		var side: int = 8 + i * 12          # 8, 20, 32, 44, 56
		out.append({"index": i, "header_flags": 0,
			"frames": [_frame(uv.duplicate(), -side / 2, -side / 2, side, side)]})
	return out


## Every frame of every extracted effect in the project, or [] when the (gitignored,
## ROM-derived) assets are absent — the skip pattern the frameset acceptance test uses.
func _corpus() -> Array:
	var root := "res://assets/effects"
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for name in dir.get_directories():
		if not name.begins_with("E"):
			continue
		var path := "%s/%s/frames.json" % [root, name]
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text)
		if not (parsed is Array):
			continue
		for fs in parsed:
			if not (fs is Dictionary):
				continue
			for fr in fs.get("frames", []):
				if fr is Dictionary:
					out.append({"effect": name, "fs": int(fs.get("index", -1)),
						"fr": int(fr.get("index", -1)), "frame": fr})
	return out


## Play a compound onto plain framesets — the pure stand-in for `apply_compound`, so the
## assertions are about the EDITS and not about the session.
func _apply(framesets: Array, edits: Array) -> void:
	for e in edits:
		var ref: Dictionary = e["field_ref"]
		var addr: Array = Channel._VERTEX_FIELD[str(ref["field"])]
		var frame: Dictionary = framesets[int(ref["frameset_index"])]["frames"][int(ref["frame_index"])]
		var pair: Array = frame["vertices"][str(addr[0])]
		pair[int(addr[1])] = int(e["new_raw"])


func _edit_map(edits: Array) -> Dictionary:
	var out: Dictionary = {}
	for e in edits:
		var r: Dictionary = e["field_ref"]
		out["%d/%d/%s" % [int(r["frameset_index"]), int(r["frame_index"]), str(r["field"])]] = int(e["new_raw"])
	return out


func _near(a: float, b: float, eps: float = 1e-6) -> bool:
	return absf(a - b) <= eps


func _done(name: String) -> void:
	_completed[name] = true


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
