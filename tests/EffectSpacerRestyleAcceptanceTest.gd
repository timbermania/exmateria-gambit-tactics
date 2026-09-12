extends Node
## HEADFUL acceptance for the fourth-amendment SPACER verdict (ADR-0087): end-to-end
## through the REAL EffectViewer → EffectStudioPage → studio_apply_edit →
## EffectEditSession → PaletteChannel, on real E317. Pins the two acceptance criteria:
##   (a) PRISTINE hatches: the E317 caster lane's played window projects
##       [lead, lead, flash, fade-out, hold, m8] → [T, T, F, F, T, T] in the live
##       page's timeline score (the ROM's own spacing events hatch, the amendment's
##       motivating fix — the third amendment showed zero here).
##   (b) CROSS-KEYFRAME RESTYLE: zeroing the flash's Δ (an edit to keyframe 2, never
##       touching keyframe 3) wakes the ex-fade-out's hatch on the SAME timeline
##       without re-selecting — the unconditional invalidates_layout → _rebuild_score
##       path recomputes verdicts lane-wide.
##
## Kept OUT of run_all_tests.sh (needs the gitignored E317 extract; acceptance precedent).
## Run: <GODOT> --path . --quit-after 200 res://tests/EffectSpacerRestyleAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_spacer_restyle_on_real_E317()

	print("\n=== EffectSpacerRestyleAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSpacerRestyleAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSpacerRestyleAcceptanceTest")
		get_tree().quit(0)


func _test_spacer_restyle_on_real_E317() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		print("[SKIP] E317 extract absent — spacer restyle acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	# (a) Pristine hatches on the live page's score — the caster lane's verdict shape.
	var lane := _lane(page._timeline._score, "palette:for_each:caster")
	if lane.is_empty():
		print("[SKIP] no caster lane on E317 — spacer restyle acceptance skipped")
		return
	var flags: Array = []
	for sp in lane["spans"]:
		flags.append(bool(sp["fields"].get("spacer", false)))
	_assert_eq(flags, [true, true, false, false, true, true],
		"pristine E317 caster: lead-ins + post-fade hold + trailing m8 hatch; flash + fade-out real")

	# (b) Cross-keyframe restyle: zero the FLASH (keyframe 2) through the real edit
	# path; keyframe 3 (the ex-fade-out, untouched) goes redundant and its span on the
	# rebuilt timeline hatches — no re-select, no manual rebuild.
	for f in ["r", "g", "b"]:
		page._apply_edit({"channel": "palette", "context": "for_each",
			"channel_name": "caster", "event_index": 2, "field": f}, 0)
	await _frames(4)
	var relane := _lane(page._timeline._score, "palette:for_each:caster")
	_assert_true(bool(relane["spans"][3]["fields"].get("spacer", false)),
		"zeroing the flash wakes the ex-fade-out's hatch (edit A restyles B, no re-select)")
	_assert_true(bool(relane["spans"][2]["fields"].get("spacer", false)),
		"…and the zeroed flash itself hatches (m4 Δ0 over a clean stack)")


# --- helpers ----------------------------------------------------------------

func _lane(score: Dictionary, lane_id: String) -> Dictionary:
	for lane in score.get("lanes", []):
		if lane.get("id", "") == lane_id:
			return lane
	return {}


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


# --- asserts ----------------------------------------------------------------

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
