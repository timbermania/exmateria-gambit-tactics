extends Node
## TDD guard for the SPACER clause of the boundary-drag grip (ADR-0086 decs. 18, 22 and 23; ADR-0087 shares the seam, so colour lanes
## are pinned here too).
##
## Motivating report: *"click a camera frame, drag the LEFT resize handle left — it creates a
## spacer and selects it; click off and it goes away. The right side is fine."* Nothing is
## created. There is no left handle either: what sits at a drawn span's visible left edge is
## the RIGHT grip of the hidden hold in front of it (ADR-0086 dec. 18 states this on
## purpose). Grabbing it selected that hold — and a selected span is never a hidden spacer
## (`is_hidden_spacer`), so the hold painted itself, hatched and labelled "Spacer".
##
## The rule this pins: a grip's WRITE owner (whose `end_frame` / `time_value` the drag stores)
## and its SELECT IDENTITY (who it selects, inspects and draws a handle for) are two different
## things, and they come apart exactly at a hidden hold.
##   * drawn span                     → identity is itself                      (unchanged)
##   * hidden hold, drawn successor   → identity is the SUCCESSOR — the author is dragging
##                                      that span's left edge; the hold never reveals
##   * hidden hold, hidden successor  → BLIND boundary: grip with NO identity
##   * hidden hold at the lane tail   → grip with NO identity (the end marker moves, no span)
## The last two are ONE case (ADR-0086 dec. 23): a hold with no drawn successor
## grips and speaks for nobody. Blind USED to be suppressed; that cost colour ~1945 keyframes
## with no compiled lane to reach them by, so reach wins and identity stays empty.
##
## Pure: `edge_grip_identity` / `edge_grip_drawn` are static, so the rule is guarded without a
## paint. The layout half is pinned too — the last bugs in this area exercised the DECISION
## and never the BEHAVIOUR, so both the predicate and the rects it produces are asserted.
##
## Run: <GODOT> --path . --quit-after 8 res://tests/EffectSpacerEdgeGripTest.tscn

const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const PaletteDataClass = ExMateriaEffects.PaletteData
const TimelineDataClass = ExMateriaEffects.TimelineData

# Every assertion below runs unconditionally, so a mid-test abort (which still prints [PASS]
# on the runner's assertion tally) shows up as a SHORT COUNT. Bump on purpose only.
const EXPECTED_ASSERTIONS := 27

const A0 := "camera:phase1:angle#0"
const A1 := "camera:phase1:angle#1"
const A2 := "camera:phase1:angle#2"
const A3 := "camera:phase1:angle#3"
const P0 := "palette:for_each:affected_units#0"
const P1 := "palette:for_each:affected_units#1"
const P2 := "palette:for_each:affected_units#2"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_verdict_drawn_span_owns_its_own_grip()
	_test_verdict_hold_hands_its_grip_to_the_next_drawn_span()
	_test_verdict_blind_boundary_grips_with_no_identity()
	_test_verdict_tail_hold_grips_with_no_identity()
	_test_verdict_selected_hold_is_drawn_so_it_owns_its_grip()
	_test_layout_hold_grip_sits_on_the_next_spans_visible_left_edge()
	_test_layout_blind_boundary_grips_but_selects_nothing()
	_test_layout_tail_hold_keeps_a_grip_with_no_identity()
	_test_grabbing_a_hold_grip_never_reveals_the_hold()
	_test_painter_shows_the_left_handle_of_the_selected_span()
	_test_colour_lanes_share_the_rule()

	var total := _passed + _failed
	if total != EXPECTED_ASSERTIONS:
		_failed += 1
		print("[FAIL] assertion count %d != EXPECTED_ASSERTIONS %d — a test aborted early"
			% [total, EXPECTED_ASSERTIONS])
	print("\n=== EffectSpacerEdgeGripTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSpacerEdgeGripTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSpacerEdgeGripTest")
		get_tree().quit(0)


# --- The pure verdict ------------------------------------------------------

func _test_verdict_drawn_span_owns_its_own_grip() -> void:
	# The classic right-edge grip: a drawn tile's boundary is its own, whatever follows it.
	_assert_eq(Timeline.edge_grip_identity(_span("a", false), _span("b", false), ""), "a",
		"a drawn span grips its right edge, and the grip is its own")
	# Even when EMPTY SPACE follows: dragging right extends the tile into the hold, and the
	# author is plainly resizing the thing they can see.
	_assert_eq(Timeline.edge_grip_identity(_span("a", false), _span("b", true), ""), "a",
		"a drawn span bordering a hold still owns its own right grip")


func _test_verdict_hold_hands_its_grip_to_the_next_drawn_span() -> void:
	# ADR-0086 dec. 18: "a spacer's right edge is the next drawn event's visible left edge".
	_assert_eq(Timeline.edge_grip_identity(_span("hold", true), _span("next", false), ""), "next",
		"a hold's grip BELONGS to the next drawn span — it is that span's left edge")


func _test_verdict_blind_boundary_grips_with_no_identity() -> void:
	# ADR-0086 dec. 23: empty space on both sides, so nothing may be selected and the hold
	# must never reveal — but the grip SURVIVES, because on a colour lane it is the only way
	# to reach that keyframe at all (no compiled lane, unpaintable, unselectable). Same
	# treatment as the lane tail; the two cases collapse into one.
	_assert_eq(Timeline.edge_grip_identity(_span("hold", true), _span("hold2", true), ""), "",
		"a boundary between two holds GRIPS, speaking for no span")


func _test_verdict_tail_hold_grips_with_no_identity() -> void:
	# ADR-0086: the last span's right grip "resizes the lane tail" — the moving party is the
	# score end marker, not a sibling. So the grip survives, speaking for no span.
	_assert_eq(Timeline.edge_grip_identity(_span("hold", true), {}, ""), "",
		"a lane-tail hold keeps its grip (the end marker) with no identity")


func _test_verdict_selected_hold_is_drawn_so_it_owns_its_grip() -> void:
	# Decision 5: the selected span always draws. A hold reached from the compiled lane is
	# therefore a normal visible tile, and its right edge is its own again.
	_assert_eq(Timeline.edge_grip_identity(_span("hold", true), _span("next", false), "hold"), "hold",
		"a SELECTED hold is drawn, so its right grip is its own")


# --- The layout it produces ------------------------------------------------

func _test_layout_hold_grip_sits_on_the_next_spans_visible_left_edge() -> void:
	var tl = _camera_timeline([8, 20, 32], [1])       # drawn, HOLD, drawn
	_assert_true(Timeline.is_hidden_spacer(_find(tl, A1), ""), "fixture: span #1 is a hidden hold")
	var grip: Rect2 = tl.edge_rect_for(A1)
	_assert_true(grip.size.x > 0.0, "the hold's boundary still has a grabbable grip")
	_assert_true(is_equal_approx(grip.get_center().x,
		tl.axis.frame_to_x(float(_find(tl, A2)["start"]))),
		"…centred exactly on the next drawn span's visible LEFT edge")
	_assert_eq(tl.edge_identity_for(A1), A2, "…and it belongs to that next drawn span")
	# The WRITE owner is untouched: the hold's own end_frame is the only stored number here.
	var hit = tl.hit_test(grip.get_center())
	_assert_eq(String(hit.get("kind", "")), "edge", "grabbing it arms a boundary drag")
	_assert_eq(String(hit.get("span_id", "")), A1,
		"…addressed to the HOLD — its end_frame is the boundary's one stored number")
	tl.free()


func _test_layout_blind_boundary_grips_but_selects_nothing() -> void:
	var tl = _camera_timeline([8, 16, 24, 32], [1, 2])   # drawn, HOLD, HOLD, drawn
	_assert_true(tl.edge_rect_for(A1).size.x > 0.0,
		"the hold→hold boundary registers a grip (reach preserved)")
	_assert_eq(tl.edge_identity_for(A1), "",
		"…speaking for no span, so dragging it reveals nothing and moves no selection")
	_assert_true(tl.edge_rect_for(A2).size.x > 0.0,
		"…while the second hold keeps its grip (a drawn span follows it)")
	_assert_eq(tl.edge_identity_for(A2), A3, "…belonging to that drawn span")
	tl.free()


func _test_layout_tail_hold_keeps_a_grip_with_no_identity() -> void:
	var tl = _camera_timeline([8, 20], [1])              # drawn, HOLD (lane tail)
	_assert_true(tl.edge_rect_for(A1).size.x > 0.0, "a tail hold keeps its lane-tail grip")
	_assert_eq(tl.edge_identity_for(A1), "", "…speaking for no span, so no selection moves")
	tl.free()


# --- The reported bug ------------------------------------------------------

func _test_grabbing_a_hold_grip_never_reveals_the_hold() -> void:
	# THE REGRESSION. The page selects the grip's IDENTITY, not its write owner. Selecting the
	# owner is what made the hold paint itself (a selected span is never a hidden spacer) and
	# read as "the drag created a spacer".
	var tl = _camera_timeline([8, 20, 32], [1])
	var identity: String = tl.edge_identity_for(A1)
	tl.select_span(identity)
	tl.rebuild_layout()
	_assert_true(Timeline.is_hidden_spacer(_find(tl, A1), tl.selected_span_id()),
		"selecting the grip's identity leaves the hold HIDDEN — no phantom spacer appears")
	# And the contrast that explains why the guard exists at all.
	_assert_true(not Timeline.is_hidden_spacer(_find(tl, A1), A1),
		"…whereas selecting the hold itself would reveal it (the old behaviour)")
	tl.free()


func _test_painter_shows_the_left_handle_of_the_selected_span() -> void:
	# The author's "left resize handle" is real on screen — without a second grip existing.
	# Selecting a drawn span lights BOTH grips whose identity it is: its own right edge, and
	# the left edge owned by the hold in front of it.
	var tl = _camera_timeline([8, 20, 32], [1])
	var left := {"span_id": A1, "select_id": tl.edge_identity_for(A1)}
	var right := {"span_id": A2, "select_id": tl.edge_identity_for(A2)}
	_assert_true(Timeline.edge_grip_drawn(left, A2, ""),
		"selecting a span draws the LEFT handle the hold in front of it owns")
	_assert_true(Timeline.edge_grip_drawn(right, A2, ""), "…and its own right handle")
	_assert_true(not Timeline.edge_grip_drawn(left, "", ""),
		"nothing selected, nothing hovered → no handle peppers the lane")
	# An identity-less tail grip must not light up merely because the selection is empty.
	_assert_true(not Timeline.edge_grip_drawn({"span_id": A3, "select_id": ""}, "", ""),
		"an identity-less (lane-tail) grip is hover-only, never matched by an empty selection")
	tl.free()


# --- Colour lanes share the seam (ADR-0087) --------------------------------

func _test_colour_lanes_share_the_rule() -> void:
	# ADR-0086 dec. 18 states the grip behaviour "on colour lanes too", and the report says
	# the same asymmetry shows on the colour channels. The registration is kind-agnostic, so
	# this pins that it stays that way.
	var tl = _palette_timeline([1])                      # drawn, HOLD, drawn
	_assert_eq(tl.edge_identity_for(P1), P2,
		"a palette hold hands its grip to the next drawn palette span")
	tl.free()
	var blind = _palette_timeline([0, 1])                # HOLD, HOLD, drawn
	_assert_true(blind.edge_rect_for(P0).size.x > 0.0,
		"…and a palette hold→hold boundary grips the same way")
	_assert_eq(blind.edge_identity_for(P0), "",
		"…speaking for no span — the colour lane is exactly where reach mattered")
	blind.free()


# --- Fixtures --------------------------------------------------------------

## A bare span dictionary shaped only as `is_hidden_spacer` reads it. `enabled` is left off:
## the camera default is "hidden unless EXPLICITLY disabled" (ADR-0086 dec. 17).
func _span(id: String, spacer: bool) -> Dictionary:
	return {"id": id, "fields": {"spacer": spacer}}


## A phase1 camera angle lane with one keyframe per entry in `ends`. Every index listed in
## `holds` is authored `MAP` + zero — the camera spacer predicate (CameraValueSemantics),
## so the projection stamps `fields.spacer` and the timeline hides it.
func _camera_timeline(ends: Array, holds: Array):
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": int(ends[ends.size() - 1]) + 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	var kfs: Array = []
	for i in range(ends.size()):
		var hold: bool = holds.has(i)
		kfs.append({
			"index": i, "end_frame": int(ends[i]),
			"angle": ([0, 0, 0] if hold else [10 * (i + 1), 20, 30]),
			"position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": ("MAP" if hold else "DIRECT"),
			"interpolation": "LINEAR", "param_index": 0, "flags": 0,
		})
	ed.camera = CameraData.from_json({"phase1": {"max_keyframe": ends.size() - 1, "keyframes": kfs}})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	return tl


## Three enabled tv-2 affected_units tweens under for_each, with `fields.spacer` STAMPED on
## the listed indices. Stamped rather than authored: the colour verdict is the expensive
## fold oracle (SpacerVerdicts) and this test is about the grip, not the fold — the timeline
## reads nothing but `fields.spacer` / `fields.enabled` either way.
func _palette_timeline(holds: Array):
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	var kfs: Array = []
	for i in range(3):
		kfs.append({"index": i, "time_value": 2, "duration_frames": 16,
			"rgb": [10, 20, 30], "ctrl": 0x85, "enabled": true, "blend_mode": 0})
	ed.palette = PaletteDataClass.from_json({"for_each": {"affected_units": {
		"context": "for_each", "channel_name": "affected_units", "max_keyframe": 4,
		"keyframes": kfs,
	}}})
	var score: Dictionary = Model.build(ed)
	for i in holds:
		var span: Dictionary = Model.find_span(score, "palette:for_each:affected_units#%d" % int(i))
		span["fields"]["spacer"] = true
		span["fields"]["enabled"] = true
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(score)
	tl.rebuild_layout()
	return tl


func _find(tl, span_id: String) -> Dictionary:
	return Model.find_span(tl._score, span_id)


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
