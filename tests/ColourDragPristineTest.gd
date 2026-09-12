extends Node
## TDD guard for RESTORE-THEN-REAPPLY on the colour boundary drag (ADR-0086 dec. 23,
## decision 3) — and for the pristine-snapshot property it depends on.
##
## The coverage gap this closes: `EffectSpacerEdgeGripTest`'s colour fixture STAMPS
## `fields.spacer` rather than deriving it, because SpacerVerdicts is the studio's most
## expensive computation. So nothing exercised the one mechanism colour has and camera does
## not — a spacer verdict that is a LIVE FOLD over the whole stream, re-run on every drag
## frame. This fixture is FOLD-DERIVED: it stamps nothing and asserts what the real fold says.
##
## Run: <GODOT> --path . res://tests/ColourDragPristineTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")
const PaletteChannelClass = preload("res://src/effects/studio/PaletteChannel.gd")

const EXPECTED_ASSERTIONS := 13

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_the_fixture_is_fold_derived_not_stamped()
	_test_a_snapshot_survives_repeated_restores()
	_test_a_coalesced_drag_is_idempotent()
	_test_the_bracket_leaves_no_residue()

	var total: int = _passed + _failed
	if total != EXPECTED_ASSERTIONS:
		_failed += 1
		print("[FAIL] assertion count drifted — expected %d, ran %d" % [EXPECTED_ASSERTIONS, total])
	print("\n=== ColourDragPristineTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourDragPristineTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourDragPristineTest")
		get_tree().quit(0)


## The fixture stamps NOTHING. An idempotent repeat of an already-settled tint is
## disable-equivalent (ADR-0087 decs. 17-22), so the real fold must call span 1 a spacer
## while spans 0 and 2 stay drawn. If this assertion ever fails the fixture has stopped
## exercising the fold and every test below it is worthless.
func _test_the_fixture_is_fold_derived_not_stamped() -> void:
	var data = _fold_fixture()
	var verdicts := _verdicts(data)
	_assert_true(verdicts.size() >= 3, "the fold produced verdicts for the fixture's spans")
	_assert_true(not verdicts[0], "span 0 (the settling tint) is NOT a spacer by the fold")
	_assert_true(verdicts[1], "span 1 (the idempotent repeat) IS a spacer BY THE FOLD, unstamped")


## THE regression this commit actually fixes. Restore-then-reapply replays ONE snapshot MANY
## times, and `PaletteChannel.restore` handed the live channel the snapshot's OWN array — so it
## survived exactly one restore and silently corrupted on the next (A/B: this fails pre-fix at
## restore #3 with [24, 8, 24] where [16, 16, 24] was expected).
func _test_a_snapshot_survives_repeated_restores() -> void:
	var data = _fold_fixture()
	var ch = _chan(data)
	var ref := _boundary_ref(0)
	var snap: Dictionary = PaletteChannelClass.snapshot(data, ref)
	var pristine := _durations(ch)

	for pass_i in range(3):
		var session = Session.new(data)
		session.apply_edit(ref, 8 * (pass_i + 1))
		PaletteChannelClass.restore(data, snap)
		_assert_eq(_durations(ch), pristine,
			"restore #%d returns the channel to the pristine durations" % (pass_i + 1))


## Inside one drag bracket, replaying an earlier cursor position must land exactly where going
## there directly lands — the drag re-plans from the ORIGINAL data, never from its own previous
## output.
##
## HONEST NOTE: this assertion passes with AND without the restore-then-reapply bracket, because
## ADR-0101 decision 1 already made `total` invariant and therefore the trade idempotent. It is
## kept as a REGRESSION guard, not as proof the bracket works: it pins idempotence as a property
## of the gesture, so a future change to the trade's arithmetic cannot quietly reintroduce drag
## history. The assertion that genuinely goes red without this commit is the repeated-restore
## one above.
func _test_a_coalesced_drag_is_idempotent() -> void:
	var ref := _boundary_ref(0)

	# Reference: a single motion straight to the target.
	var direct = _fold_fixture()
	var ds = Session.new(direct)
	ds.begin_coalesce(ref)
	ds.apply_edit(ref, 24)
	ds.end_coalesce()
	var expected := _durations(_chan(direct))

	# The same target reached after wandering — every intermediate position the mouse crossed.
	var wandered = _fold_fixture()
	var ws = Session.new(wandered)
	ws.begin_coalesce(ref)
	for v in [8, 40, 1, 56, 16, 24]:
		ws.apply_edit(ref, v)
	ws.end_coalesce()
	_assert_eq(_durations(_chan(wandered)), expected,
		"a wandering drag lands exactly where a direct one does")

	# And the whole gesture is still ONE undo that returns the pristine state.
	var pristine := _durations(_chan(_fold_fixture()))
	_assert_true(ws.undo(), "the wandering drag is one undo")
	_assert_eq(_durations(_chan(wandered)), pristine, "…restoring the pristine durations")
	_assert_true(not ws.undo(), "…and there is nothing more to undo")


## The bracket must not leak: once closed, an ordinary edit applies to the CURRENT state rather
## than being rewound to a stale grab.
func _test_the_bracket_leaves_no_residue() -> void:
	var data = _fold_fixture()
	var session = Session.new(data)
	var ref := _boundary_ref(0)
	session.begin_coalesce(ref)
	session.apply_edit(ref, 24)
	session.end_coalesce()
	var after_drag := _durations(_chan(data))
	session.apply_edit(ref, 8)
	_assert_true(_durations(_chan(data)) != after_drag,
		"an edit after the bracket closes still changes the channel")
	_assert_true(session.undo(), "…and records its own undo entry")
	_assert_eq(_durations(_chan(data)), after_drag,
		"…which unwinds to the post-drag state, not to the grab")


# --- fixtures -------------------------------------------------------------

func _boundary_ref(index: int) -> Dictionary:
	return {"channel": "palette", "context": "for_each", "channel_name": "affected_units",
		"event_index": index, "field": "boundary_end"}


func _chan(data):
	return data.palette.get_channel("for_each", "affected_units")


func _durations(ch) -> Array:
	var out: Array = []
	for kf in ch.keyframes:
		out.append(Lowering.duration_for_time_value(int(kf.time_value)))
	return out


## The spacer verdicts the REAL fold produces for the fixture's palette lane, read back off the
## projected score (which is what the timeline paints from).
func _verdicts(data) -> Array:
	var score: Dictionary = Model.build(data)
	for lane in score.get("lanes", []):
		if String(lane.get("id", "")) == "palette:for_each:affected_units":
			var out: Array = []
			for sp in lane.get("spans", []):
				out.append(bool(sp.get("fields", {}).get("spacer", false)))
			return out
	return []


## A palette channel whose middle keyframe is an IDEMPOTENT REPEAT of the one before it — the
## fold's own reason to call something empty space. Nothing here stamps `spacer`.
func _fold_fixture():
	var kfs: Array = []
	var spec := [
		{"tv": 2, "rgb": [200, 40, 40]},   # settle on a tint
		{"tv": 2, "rgb": [200, 40, 40]},   # …say it again: disable-equivalent
		{"tv": 3, "rgb": [40, 40, 200]},   # a genuinely different tint
	]
	for i in range(spec.size()):
		kfs.append({"index": i, "time_value": int(spec[i]["tv"]),
			"duration_frames": Lowering.duration_for_time_value(int(spec[i]["tv"])),
			"rgb": spec[i]["rgb"], "ctrl": 0x85, "enabled": true, "blend_mode": 5})
	var pd = PaletteDataClass.from_json({
		"for_each": {"affected_units": {
			"context": "for_each", "channel_name": "affected_units",
			"max_keyframe": spec.size() + 1, "keyframes": kfs,
		}},
	})
	var data := _FakeData.new()
	data.palette = pd
	return data


## Model.build reads across the whole effect, so the stub carries every field it touches —
## all empty but the palette lane under test.
class _FakeData extends RefCounted:
	var screen = null
	var palette = null
	var camera = null
	var timeline = null
	var sound = {}
	var script_ops: Array = []
	var emitters: Array = []
	var curves: Array = []
	var frames: Array = []
	var framesets: Array = []
	var animations: Array = []
	var effect_flags = null
	var time_scale = null
	var name: String = "fixture" 


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
