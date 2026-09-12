extends Node
## HEADFUL acceptance for SPACER = INVISIBLE EMPTY SPACE (ADR-0087 FIFTH amendment): end-to-end
## through the REAL EffectViewer → EffectStudioPage → studio_insert_event → EffectEditSession →
## PaletteChannel, on real E317. Pins the amendment's user-facing behaviour:
##   (a) INVISIBLE: the E317 caster lane's ENABLED inert spacers report is_hidden_spacer=true
##       (the painter draws them as nothing), while the live flash/fade-out draw.
##   (b) ADD-INTO-THE-SPACER: driving the colour-lane gap verb (the right-click resolves through
##       _colour_spacer_gap_actions → _run_lane_verb, spacer_stub set) cuts a spacer into a
##       1-frame BORN-DISABLED stub bracketed by spacers, lands the selection on the stub, and
##       that stub is DRAWN (a deliberately-disabled event — not re-hidden). One undo restores.
##
## Kept OUT of run_all_tests.sh (needs the gitignored E317 extract; acceptance precedent).
## Run: <GODOT> --path . --quit-after 200 res://tests/EffectSpacerEmptySpaceAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const TimelineClass = preload("res://src/effects/studio/EffectScoreTimeline.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_spacer_empty_space_on_real_E317()

	print("\n=== EffectSpacerEmptySpaceAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSpacerEmptySpaceAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSpacerEmptySpaceAcceptanceTest")
		get_tree().quit(0)


func _test_spacer_empty_space_on_real_E317() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		print("[SKIP] E317 extract absent — spacer empty-space acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	var lane := _lane(page._timeline._score, "palette:for_each:caster")
	if lane.is_empty() or lane["spans"].size() < 6:
		print("[SKIP] no caster lane on E317 — spacer empty-space acceptance skipped")
		return

	# (a) The enabled inert lead-in spacers are INVISIBLE; the live flash draws.
	var sel: String = page._timeline.selected_span_id()
	_assert_true(TimelineClass.is_hidden_spacer(lane["spans"][0], sel),
		"E317 caster's enabled inert lead-in is invisible empty space")
	_assert_true(not TimelineClass.is_hidden_spacer(lane["spans"][2], sel),
		"…the live flash (span 2) draws")

	# (b) Add-into-the-spacer: right-click the first spacer region → Add event here.
	var before_n: int = lane["spans"].size()
	var offset: int = int(lane["spans"][0]["start"]) - int(lane["spans"][0]["authored_start"])
	var local_frame: int = int(lane["spans"][0]["authored_start"]) + 2   # inside the lead-in tile
	var actions: Array = page._colour_spacer_gap_actions(lane, local_frame)
	_assert_eq(actions.size(), 1, "the spacer region offers exactly one verb (Add)")
	_assert_eq(String(actions[0].get("label", "")), "Add event here", "…labelled Add event here")
	page._run_lane_verb(actions[0])
	await _frames(6)

	var relane := _lane(page._timeline._score, "palette:for_each:caster")
	_assert_eq(relane["spans"].size(), before_n + 2,
		"Add cuts the spacer into three (one keyframe → three)")
	var stub_id: String = page._timeline.selected_span_id()
	var stub := _span(relane, stub_id)
	_assert_true(not stub.is_empty(), "the selection lands on the new stub")
	_assert_true(not bool(stub.get("fields", {}).get("enabled", true)),
		"…which is BORN DISABLED (a deliberately-disabled placeholder)")
	_assert_true(not TimelineClass.is_hidden_spacer(stub, stub_id),
		"…so it is DRAWN, not instantly re-hidden (it stays visible to build over)")

	# One undo restores the original lane.
	page._undo()
	await _frames(6)
	var undone := _lane(page._timeline._score, "palette:for_each:caster")
	_assert_eq(undone["spans"].size(), before_n, "one undo restores the original spacer")


# --- helpers ----------------------------------------------------------------

func _lane(score: Dictionary, lane_id: String) -> Dictionary:
	for lane in score.get("lanes", []):
		if lane.get("id", "") == lane_id:
			return lane
	return {}


func _span(lane: Dictionary, span_id: String) -> Dictionary:
	for sp in lane.get("spans", []):
		if String(sp.get("id", "")) == span_id:
			return sp
	return {}


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
