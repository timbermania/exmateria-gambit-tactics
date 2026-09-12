extends Node
## TDD guard for the MANUFACTURED PAD's SHAPE (ADR-0101 decision 6, narrowed).
##
## Decision 6 originally read "padding is a COPY of the adjacent hold, NEVER
## `_new_disabled_keyframe`" — one rule for both cases. Its stated reason was a UI predicate,
## not a correctness one: a disabled keyframe is `spacer && not enabled`, `is_hidden_spacer`
## needed BOTH, so disabled padding would have drawn as a row of hatched tiles.
##
## The narrowing: where a run has a real adjacent hold, copying it stays right (it is the
## byte-shape shipped data uses, and it costs nothing). Where a run is EMPTY there is no
## adjacent hold, and the old fallback — a copy of the keyframe at the insertion point — is
## inert only ~92% of the time, which is why a whole trial-insert-and-ask-the-fold apparatus
## (`_manufactured_hold_is_inert`) grew around it, and why decisions 6 and 7 both carried an
## open fault: the planner was reading a fold its own edit invalidated.
##
## The pad Move mints is an ENABLED Δ0 IDENTITY (`_new_identity_keyframe`: rgb 0, blend mode 0,
## ctrl 0x80) — the same shape the screen arm's pad already used. It lowers to "current + 0", a
## per-frame no-op whatever it sits next to, so the fold calls it a spacer and `is_hidden_spacer`
## hides it with NO carve-out: decision 6's original objection simply does not arise.
##
## It is deliberately NOT the disabled null the first attempt at this reached for. That shape is
## already spoken for — `insert_event` and `_insert_spacer_stub` seed the author's born-disabled
## STUB with it, byte for byte — so teaching `is_hidden_spacer` to hide disabled zero keyframes
## made every freshly-Added colour event vanish the moment it was deselected. `_test_the_add_stub
## _is_not_what_a_pad_looks_like` is that regression, kept.
##
## What this file pins, in the order the argument runs:
##   1. the minted pad's inertness is structural, not statistical (the real fold agrees)
##   2. it is INVISIBLE through the painter's own predicate, unchanged
##   3. the author's born-disabled Add stub does NOT share its shape, and still draws
##   4. Move mints — never copies — into an empty run, and needs no licence to do it
##   5. the 8% population the old licence REFUSED now moves, and its pad is invisible
##
## Run: <GODOT> --path . res://tests/ColourMovePadShapeTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")
const MovePlan = preload("res://src/effects/studio/ColourMovePlan.gd")
const PaletteChannelClass = preload("res://src/effects/studio/PaletteChannel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_the_fixture_is_fold_derived_not_stamped()
	_test_a_minted_pad_folds_inert_by_construction()
	_test_the_minted_pad_is_hidden_and_the_add_stub_is_not()
	_test_an_empty_run_is_minted_never_copied()
	_test_the_population_the_licence_refused_now_moves_invisibly()
	_test_the_add_stub_is_not_what_a_pad_looks_like()
	_test_a_real_hold_is_still_copied()
	_test_the_minted_pad_survives_a_round_trip()

	print("\n=== ColourMovePadShapeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourMovePadShapeTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourMovePadShapeTest")
		get_tree().quit(0)


## The proof standard this branch runs on: nothing below is worth anything if the fixture
## stamps its own verdicts. `strict` is the 8% shape — a DRAWN tint hard in front of the span,
## so a copy of it would NOT fold inert and the old licence refused the slide outright.
func _test_the_fixture_is_fold_derived_not_stamped() -> void:
	_assert_eq(_verdicts(_strict()), [false, false, true],
		"the fold, unprompted, calls the leading tint DRAWN and only the trailing repeat a hold")
	_assert_eq(PaletteChannelClass.move_context(_strict(), _ref(1))["holds"],
		[false, false, true], "…and move_context's hold vector agrees with the score's")


## The whole reason the licence can go: a disabled null keyframe contributes NOTHING to the
## fold, wherever it is put and however many of them there are. Not 92% — always.
func _test_a_minted_pad_folds_inert_by_construction() -> void:
	# Insert minted pads by hand, in every shape `_seq_for` can emit: one 8-frame carrier and
	# a run of 1-frame residuals, ahead of a DRAWN tint (the shape a copy could never survive).
	for pad_lengths in [[8], [1, 1, 1], [8, 1, 1, 1]]:
		var data = _strict()
		var ch = _chan(data)
		var at: int = 1
		for L in pad_lengths:
			ch.keyframes.insert(at, _minted_pad(L))
			ch.max_keyframe += 1
			at += 1
		for i in range(ch.keyframes.size()):
			ch.keyframes[i].index = i
		var v: Array = _verdicts(data)
		var pads_inert := true
		for k in range(1, 1 + pad_lengths.size()):
			pads_inert = pads_inert and bool(v[k])
		_assert_true(pads_inert,
			"the REAL fold calls every minted pad empty space (%s)" % str(pad_lengths))


## The blocker decision 6 named, answered — and answered WITHOUT touching `is_hidden_spacer`,
## which is the point. An enabled Δ0 identity is `spacer && enabled`, so the painter's existing
## rule already calls it empty space.
##
## The second half is the regression that killed the first attempt: the author's born-disabled
## Add stub is a DISABLED zero keyframe, and so was the pad. Deriving pad-ness from the bytes
## therefore could not tell them apart, and hiding the pad hid every just-Added event as soon as
## it lost selection — the exact failure ADR-0087 dec. 27 exists to prevent.
## Caught by `EffectSpacerProjectionTest`, not by the shipped-corpus census that preceded it:
## only 15 of the corpus's 287 disabled palette keyframes are zero-tint, so the data barely
## noticed. The population that mattered was the one this Studio mints itself.
func _test_the_minted_pad_is_hidden_and_the_add_stub_is_not() -> void:
	var pad := {"id": "palette:x:0", "fields":
		{"spacer": true, "enabled": true, "rgb": Vector3i.ZERO, "blend_mode": 0}}
	var stub := {"id": "palette:x:1", "fields":
		{"spacer": true, "enabled": false, "rgb": Vector3i.ZERO, "blend_mode": 0}}
	var mute := {"id": "palette:x:2", "fields":
		{"spacer": true, "enabled": false, "rgb": Vector3i(40, 40, 200), "blend_mode": 5}}
	var drawn := {"id": "palette:x:3", "fields":
		{"spacer": false, "enabled": true, "rgb": Vector3i(40, 40, 200), "blend_mode": 5}}

	_assert_true(Timeline.is_hidden_spacer(pad, ""), "a minted PAD is empty space — hidden")
	_assert_true(not Timeline.is_hidden_spacer(stub, ""),
		"a born-disabled ADD STUB still draws, hatched — it is what the author is building")
	_assert_true(not Timeline.is_hidden_spacer(mute, ""),
		"an author's MUTE is still 'muted, not gone'")
	_assert_true(not Timeline.is_hidden_spacer(drawn, ""), "a drawn tween is unchanged")
	_assert_true(not Timeline.is_hidden_spacer(pad, "palette:x:0"),
		"…and the SELECTED span still always draws, pad or not (decision 5)")


## The regression witness, end to end through the real verbs: Add a stub into a spacer, then
## Move a span so it mints a pad, and assert the score tells them apart on the SAME lane.
func _test_the_add_stub_is_not_what_a_pad_looks_like() -> void:
	var data = _copy_fixture()
	var ch = _chan(data)
	var session = Session.new(data)
	var add := _ref(1)                      # index 1 is a HOLD — the spacer to build into
	add["frame"] = 20
	add["spacer_stub"] = true
	var added: Dictionary = session.insert_event(add)
	_assert_true(not added.is_empty(), "Add-into-a-spacer seeds a born-disabled stub")
	var stub_i: int = int(added["event_index"])
	_assert_true(not bool(ch.keyframes[stub_i].enabled), "…and the stub is DISABLED")

	var spans: Array = _spans(data)
	_assert_true(not Timeline.is_hidden_spacer(spans[stub_i], ""),
		"the stub DRAWS with nothing selected — it does not blink out on deselect")


## Decision 6 narrowed, at the planner. An empty run's padding is MINTED — the splice says so
## itself, so the two channels' copiers are never asked to invent bytes they do not have.
func _test_an_empty_run_is_minted_never_copied() -> void:
	var durations := [16, 24, 16]
	var holds := [false, false, true]      # nothing in front of span 1, a hold behind it

	var res: Dictionary = MovePlan.plan(durations, holds, 1, 8, 29)
	_assert_eq(int(res["delta"]), 8, "the empty lead run is grown — no licence to ask for")
	_assert_eq(int(res["cost"]), 1, "…for one slot: the pad itself")
	_assert_eq(res["left"]["seq"], [{"src": 1, "dur": 8, "pad": true}],
		"…and the splice entry is flagged PAD, so `apply` mints instead of copying")
	_assert_eq(int(res["left"]["from"]), 1, "…with `src` degraded to the insertion ADDRESS")

	# The other side, and the case decision 3's sharpening used to strand: played index 0. A
	# minted pad has no bytes to be wrong about, so a span AT the phase origin can grow a lead
	# too — the "copy of itself placed before it" the old fallback offered was the only reason
	# it could not.
	var at_origin: Dictionary = MovePlan.plan([24, 16], [false, true], 0, 8, 29)
	_assert_eq(int(at_origin["delta"]), 8, "a span at played index 0 is no longer stranded")
	_assert_true(bool(at_origin["left"]["seq"][0].get("pad", false)),
		"…because the lead it grows is minted, not a copy of itself")

	# A wedged span is still refused: minting invents PADDING, never room.
	var wedged: Dictionary = MovePlan.plan([16, 24, 16], [false, false, false], 1, 8, 29)
	_assert_true(not wedged.get("ok", false),
		"a span between two DRAWN tweens still has no frames to trade")


## The 8% the old licence refused — a slide `_manufactured_hold_is_inert` had to veto because
## the only candidate padding was a copy of a DRAWN tint. It now moves, and the fold still
## calls the whole lead run empty space, so the picture outside the moved span is untouched.
func _test_the_population_the_licence_refused_now_moves_invisibly() -> void:
	var data = _strict()
	var ch = _chan(data)
	var used_before: int = int(ch.max_keyframe)
	var lane_before: int = _lane_length(ch)
	var drawn_before: Vector3i = ch.keyframes[0].rgb

	var res: Dictionary = Session.new(data).move_span(_ref(1), 8)
	_assert_eq(int(res.get("delta", 0)), 8,
		"the span the fold-probe used to veto now slides")
	_assert_eq(int(ch.max_keyframe), used_before + 1, "…for exactly one slot")
	_assert_eq(_lane_length(ch), lane_before, "…and the lane's played length is unchanged")
	_assert_eq(ch.keyframes[0].rgb, drawn_before,
		"…and the DRAWN tint in front of it was not copied over")

	var pad = ch.keyframes[1]
	_assert_true(bool(pad.enabled) and pad.rgb == Vector3i.ZERO
			and int(pad.blend_mode) == 0 and int(pad.ctrl) == 0x80,
		"the manufactured lead is a MINTED enabled Δ0 identity, not a copy of anything")

	# The two questions that matter, asked of the real fold and the real painter.
	var spans: Array = _spans(data)
	_assert_true(bool(spans[1]["fields"]["spacer"]),
		"the REAL fold calls the minted pad empty space")
	_assert_true(Timeline.is_hidden_spacer(spans[1], ""),
		"…and the painter HIDES it — no row of hatched tiles")
	_assert_true(not Timeline.is_hidden_spacer(spans[0], ""),
		"…while the drawn tint in front of it still draws")


## The narrowing is a NARROWING: where a real adjacent hold exists, nothing changed. Copying
## it keeps the padding byte-shaped like shipped data, and it is what the corpus is full of.
func _test_a_real_hold_is_still_copied() -> void:
	var data = _copy_fixture()
	var ch = _chan(data)
	var hold_rgb: Vector3i = ch.keyframes[1].rgb
	var hold_ctrl: int = int(ch.keyframes[1].ctrl)
	Session.new(data).move_span(_ref(2), 3)

	var copied := true
	for i in range(1, 5):            # the re-encoded lead run: 16 + three 1-frame pads
		copied = copied and bool(ch.keyframes[i].enabled) \
			and ch.keyframes[i].rgb == hold_rgb and int(ch.keyframes[i].ctrl) == hold_ctrl
	_assert_true(copied,
		"every pad in a run that HAS a hold still carries that hold's own bytes, enabled")

	var seq: Array = MovePlan.plan([16, 16, 24, 16, 16],
		[false, true, false, true, false], 2, 3, 27)["left"]["seq"]
	var flagged := false
	for e in seq:
		flagged = flagged or bool(e.get("pad", false))
	_assert_true(not flagged, "…and no entry in a non-empty run is flagged PAD")


## The round trip through the minted pad, which is what decision 7's collapse has to survive:
## the pad run is emptied and DELETED, the slot comes back, and the picture is the one we
## started with. (This is the planner's half of "it won't go back" — the grip's half is a
## separate fault, ADR-0101 dec. 3's boundary clause.)
func _test_the_minted_pad_survives_a_round_trip() -> void:
	var data = _strict()
	var ch = _chan(data)
	var used_before: int = int(ch.max_keyframe)
	var before: Array = _durations(ch)
	var session = Session.new(data)

	var out: Dictionary = session.move_span(_ref(1), 8)
	_assert_eq(int(out.get("delta", 0)), 8, "out")
	var landed: int = int(out.get("event_index", -1))

	var back: Dictionary = session.move_span(_ref(landed), -8)
	_assert_eq(int(back.get("delta", 0)), -8, "the span slides straight back")
	_assert_eq(int(ch.max_keyframe), used_before,
		"…the emptied pad run was DELETED, so the slot came back (decision 7)")
	_assert_eq(_durations(ch), before, "…and the channel is keyframe-for-keyframe pristine")


# --- fixtures -------------------------------------------------------------

func _ref(index: int) -> Dictionary:
	return {"channel": "palette", "context": "for_each", "channel_name": "affected_units",
		"event_index": index}


func _chan(data):
	return data.palette.get_channel("for_each", "affected_units")


func _durations(ch) -> Array:
	return Lowering.durations(ch.keyframes)


func _lane_length(ch) -> int:
	var total: int = 0
	for d in _durations(ch).slice(0, Lowering.played_last(ch)):
		total += int(d)
	return total


func _spans(data) -> Array:
	var score: Dictionary = Model.build(data)
	for lane in score.get("lanes", []):
		if String(lane.get("id", "")) == "palette:for_each:affected_units":
			return lane.get("spans", [])
	return []


func _verdicts(data) -> Array:
	var out: Array = []
	for sp in _spans(data):
		out.append(bool(sp.get("fields", {}).get("spacer", false)))
	return out


## Exactly `ColourMoveTest`'s `strict` shape: a DRAWN tint, the span, then a repeat of the span.
## The lead run is EMPTY and a copy of keyframe 0 would NOT fold inert — the 8% population.
func _strict():
	return _build([
		{"tv": 2, "rgb": [0, 240, 241]},
		{"tv": 3, "rgb": [40, 40, 200]},
		{"tv": 2, "rgb": [40, 40, 200]},
	], 4)


## A hold run on BOTH sides of span 2 — the case that still copies.
func _copy_fixture():
	return _build([
		{"tv": 2, "rgb": [200, 40, 40]},
		{"tv": 2, "rgb": [200, 40, 40]},
		{"tv": 3, "rgb": [40, 40, 200]},
		{"tv": 2, "rgb": [40, 40, 200]},
		{"tv": 2, "rgb": [40, 200, 40]},
	], 6)


## What `PaletteChannel._new_identity_keyframe` mints, built here so the test does not have to
## reach into the channel's privates to state what shape it is asserting.
func _minted_pad(dur: int):
	var kf = PaletteDataClass.Keyframe.new()
	kf.rgb = Vector3i.ZERO
	kf.ctrl = 0x80
	kf.enabled = true
	kf.blend_mode = 0
	kf.time_value = Lowering.time_value_for_duration(dur)
	kf.duration_frames = dur
	return kf


func _build(spec: Array, used: int):
	var kfs: Array = []
	for i in range(spec.size()):
		kfs.append({"index": i, "time_value": int(spec[i]["tv"]),
			"duration_frames": Lowering.duration_for_time_value(int(spec[i]["tv"])),
			"rgb": spec[i]["rgb"], "ctrl": 0x85, "enabled": true, "blend_mode": 5})
	var pd = PaletteDataClass.from_json({
		"for_each": {"affected_units": {
			"context": "for_each", "channel_name": "affected_units",
			"max_keyframe": used, "keyframes": kfs,
		}},
	})
	var data := _FakeData.new()
	data.palette = pd
	return data


## Model.build reads across the whole effect, so the stub carries every field it touches.
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
