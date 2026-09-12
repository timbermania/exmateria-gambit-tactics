extends Node
## BY-EYE acceptance for the Move's manufactured pad (ADR-0101 decision 6, narrowed) — headful,
## real E043, driven through the REAL body-drag the author uses
## (`EffectStudioPage._on_span_body_drag_started/_dragged/_ended` → `EffectEditSession` →
## `PaletteChannel.move_span`), not through the planner.
##
## The mechanized guards (`ColourMovePadShapeTest`, `ColourMoveCorpusSweepTest`) pin that the
## minted pad folds inert and that `is_hidden_spacer` hides it. They cannot answer the question
## the author actually asks, which is whether the LANE looks right — decision 6's original
## objection was "disabled padding would draw as a row of hatched tiles", and the only honest
## check of a claim about hatched tiles is to look.
##
## Screenshots for the human review pass:
##   /tmp/e043_move_pad_before.png   the pristine lane
##   /tmp/e043_move_pad_after.png    after sliding span 0 right by 8 — the 8 frames it vacated
##                                   are now a minted pad, and must read as EMPTY SPACE
##
## Kept OUT of run_all_tests.sh (headful + gitignored extracts; acceptance precedent).
## Run: <GODOT> --path . --quit-after 400 res://tests/EffectColourMovePadAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const EFFECT := "E043"
const LANE := "palette:for_each:affected_units"
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_the_minted_pad_is_empty_space_on_the_real_lane()

	print("\n=== EffectColourMovePadAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectColourMovePadAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectColourMovePadAcceptanceTest")
		get_tree().quit(0)


func _test_the_minted_pad_is_empty_space_on_the_real_lane() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with(EFFECT):
			dir = d
	if dir == "":
		print("[SKIP] %s extract absent — Move pad acceptance skipped" % EFFECT)
		_passed += 1
		return
	page._load_effect(dir)
	await _frames(20)

	var lane := _lane(page._timeline._score)
	if lane.is_empty() or lane["spans"].size() < 2:
		print("[SKIP] %s has no %s lane to move on" % [EFFECT, LANE])
		_passed += 1
		return

	# Span 0's lead run is EMPTY (it starts the phase), so sliding it right is precisely the
	# case that has to manufacture padding out of nothing.
	var before_spans: Array = lane["spans"]
	var before_drawn: int = _drawn_count(before_spans, page)
	_assert_true(not Timeline.is_hidden_spacer(before_spans[0], ""),
		"span 0 is a DRAWN tint before the move")
	_shot(page, "/tmp/e043_move_pad_before.png")

	# The REAL gesture, through the page's own drag handlers.
	var span_id := String(before_spans[0]["id"])
	page._on_span_body_drag_started(span_id)
	page._on_span_body_dragged(span_id, 8)
	page._on_span_body_drag_ended(span_id)
	await _frames(10)

	var after := _lane(page._timeline._score)
	var after_spans: Array = after["spans"]
	# NOT "one more span": the pad costs a slot on the left and the right run's re-encoding
	# usually gives one back (48 frames as one 40 instead of 32+16 here), so a slide can be
	# span-count neutral. What must hold is the SHAPE — a pad, then the tint that used to start
	# the lane — and the lane's total played length.
	_assert_eq(_lane_frames(after_spans), _lane_frames(before_spans),
		"the lane's played length is unchanged by the slide")
	_assert_eq(after_spans[1]["fields"].get("rgb", Vector3i.ONE),
		before_spans[0]["fields"].get("rgb", Vector3i.ZERO),
		"the tint that started the lane is now span 1, its bytes untouched")

	# The pad is span 0 now; the moved tint follows it. Selection lands on the moved span after
	# a drag, and `is_hidden_spacer` never hides the SELECTED span, so ask about the pad with
	# nothing selected — which is the state the author looks at the lane in.
	var pad: Dictionary = after_spans[0]
	_assert_true(bool(pad["fields"].get("spacer", false)),
		"the REAL fold, on the live page, calls the manufactured pad empty space")
	_assert_true(bool(pad["fields"].get("enabled", false)),
		"…and it is an ENABLED Δ0 identity, not a disabled null (which is the Add stub's shape)")
	_assert_true(Timeline.is_hidden_spacer(pad, ""),
		"…so the painter HIDES it — no row of hatched tiles where the span used to be")
	_assert_eq(_drawn_count(after_spans, page), before_drawn,
		"the lane draws exactly the same number of tiles as before the move")

	_shot(page, "/tmp/e043_move_pad_after.png")
	print("[LOOK] compare /tmp/e043_move_pad_before.png and /tmp/e043_move_pad_after.png — the "
		+ "tint should have slid right by 8 frames with EMPTY SPACE behind it, not a hatch")


# --- helpers ----------------------------------------------------------------

func _lane(score: Dictionary) -> Dictionary:
	for lane in score.get("lanes", []):
		if String(lane.get("id", "")) == LANE:
			return lane
	return {}


## The lane's total played length, in frames.
func _lane_frames(spans: Array) -> int:
	var total := 0
	for sp in spans:
		total += int(sp["fields"].get("duration_frames", 0))
	return total


## How many of the lane's spans actually paint, with nothing selected.
func _drawn_count(spans: Array, _page) -> int:
	var n := 0
	for sp in spans:
		if not Timeline.is_hidden_spacer(sp, ""):
			n += 1
	return n


func _shot(ctrl: Control, path: String) -> void:
	var img := ctrl.get_window().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] %s" % path)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


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
