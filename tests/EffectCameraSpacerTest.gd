extends Node
## TDD guard for the CAMERA SPACER — a `MAP` delta of zero renders as empty space
## (ADR-0086 dec. 15, widening ADR-0087's fifth-amendment treatment from a
## colour-lane role to a lane-event role).
##
## Author's hypothesis, confirmed on E317: *"setting source to MAP with angle/position/zoom
## fields is how [the ROM] made these events 'do nothing'"*. The runtime resolves `MAP` as
## `current + keyframe` on all three sub-channels, so a zero value holds the pose; every OTHER
## source mode resolves against an anchor / the saved slot / absolutely, where a zero is a real
## move (zoom `DIRECT` 0 = zoom TO zero).
##
## Five seams:
##   A) The predicate — CameraValueSemantics.is_spacer(channel, source_mode, value). MAP-only,
##      zoom on `.x` alone, and NOT the excluded inert classes (width-1, UNKNOWN, SHAKE-zero).
##   B) The stamp — EffectScoreModel._camera_spans puts `fields.spacer` on every sub-channel
##      span, PER SPAN: a coalesced keyframe can be a spacer on one mask bit, real on another.
##   C) The hide — EffectScoreTimeline.is_hidden_spacer, whose `enabled` clause now defaults
##      TRUE ("hidden unless EXPLICITLY disabled") so camera (no Enable bit) hides while
##      colour's deliberately-disabled carve-out is untouched.
##   D) The way back in — EffectStudioPage._camera_spacer_gap_actions (right-click → Add
##      waypoint here), the same insert_event a drawn span's verb uses.
##   E) The wake — CameraChannel._apply_vec flags `relayout` on a ZERO CROSSING only, so an
##      edit that gives a hold a real value reprojects instead of staying invisible.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCameraSpacerTest.tscn

const Semantics = preload("res://src/effects/studio/CameraValueSemantics.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const CameraChannelClass = preload("res://src/effects/studio/CameraChannel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# A — the predicate
	_test_map_with_zero_is_a_spacer_on_every_channel()
	_test_map_with_a_real_value_is_not()
	_test_every_other_source_mode_is_never_a_spacer()
	_test_zoom_reads_x_alone()
	_test_excluded_inert_classes_stay_visible()
	# B — the stamp
	_test_score_stamps_spacer_per_sub_channel_span()
	_test_coalesced_keyframe_is_judged_per_span()
	# C — the hide
	_test_camera_spacer_hides_without_an_enabled_field()
	_test_selected_camera_spacer_always_draws()
	_test_colour_disabled_carve_out_survives_the_default_flip()
	_test_span_without_a_spacer_field_is_never_hidden()
	_test_a_click_inside_a_hidden_spacer_seeks_it_does_not_select()
	# D — the way back in
	_test_gap_actions_offer_add_waypoint()
	# E — the wake
	_test_value_edit_reprojects_only_on_a_zero_crossing()
	# F — the motivating real data
	_test_real_E317_pins_the_three_cited_holds()

	print("\n=== EffectCameraSpacerTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraSpacerTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraSpacerTest")
		get_tree().quit(0)


# --- A: the predicate -----------------------------------------------------

## `MAP` is `current + keyframe` on all three sub-channels (CameraSubsystem :382 / :437 / :489),
## so a zero value gives `to == from` and the pose never moves — whatever the interpolation.
func _test_map_with_zero_is_a_spacer_on_every_channel() -> void:
	for ch in ["angle", "position", "zoom"]:
		_assert_true(Semantics.is_spacer(ch, "MAP", Vector3i.ZERO),
			"%s: MAP + zero is a spacer" % ch)


func _test_map_with_a_real_value_is_not() -> void:
	_assert_true(not Semantics.is_spacer("angle", "MAP", Vector3i(0, 64, 0)),
		"MAP + a real yaw delta is a live event")
	_assert_true(not Semantics.is_spacer("position", "MAP", Vector3i(0, -32, 0)),
		"MAP + a real position delta is a live event")


## The discriminator is the SOURCE MODE, not the value: every for-each camera keyframe in E317
## stores [0,0,0], and the CASTER pan / TARGET framing / SLOT_COPY return are all real moves.
## Under an absolute mode a zero is the OPPOSITE of inert — zoom DIRECT 0 means zoom TO zero.
func _test_every_other_source_mode_is_never_a_spacer() -> void:
	for mode in ["DIRECT", "TARGET", "CASTER", "CURSOR", "EFFECT_CTR",
			"ALL_TARGETS", "OFFSET", "SLOT_COPY", "ORIGIN"]:
		_assert_true(not Semantics.is_spacer("position", mode, Vector3i.ZERO),
			"%s + zero is NOT a spacer (it resolves against something external)" % mode)
	_assert_true(not Semantics.is_spacer("zoom", "DIRECT", Vector3i.ZERO),
		"zoom DIRECT 0 means zoom TO ZERO — a drastic change, never a spacer")


## _execute_zoom_command reads `float(kf.zoom.x)` and ignores y/z (storage padding), so the
## zoom verdict must too — else a padded [0, 5, 0] would read as a live zoom that never happens.
func _test_zoom_reads_x_alone() -> void:
	_assert_true(Semantics.is_spacer("zoom", "MAP", Vector3i(0, 5, 9)),
		"zoom judges .x alone (y/z are padding the runtime ignores)")
	_assert_true(not Semantics.is_spacer("zoom", "MAP", Vector3i(5, 0, 0)),
		"a non-zero zoom.x is a live zoom delta")


## Five OTHER classes provably move nothing and are deliberately OUT of scope this pass — the
## predicate is exactly the author's hypothesis. Widening later is additive, not a reversal.
## (Width-1 non-IMMEDIATE spans are authoring ACCIDENTS the runtime drops, worth seeing.)
func _test_excluded_inert_classes_stay_visible() -> void:
	_assert_true(not Semantics.is_spacer("angle", "TARGET", Vector3i.ZERO),
		"UNKNOWN-interp / width-1 classes are not judged here (source is not MAP)")
	_assert_true(not Semantics.is_spacer("position", "DIRECT", Vector3i.ZERO),
		"a zero-amplitude SHAKE under DIRECT stays visible (excluded class)")
	_assert_true(not Semantics.is_spacer("zoom", "OFFSET", Vector3i.ZERO),
		"zoom under OFFSET keeps its own `(inert)` LABEL, and is not hidden")
	_assert_true(Semantics.is_inert("zoom", "OFFSET"),
		"...that separate #281 inert LABEL still answers for it")


# --- B: the stamp ---------------------------------------------------------

## Every camera sub-channel span carries `fields.spacer`, computed from the value the runtime
## actually reads for that lane.
func _test_score_stamps_spacer_per_sub_channel_span() -> void:
	var score := Model.build(_effect({
		"phase1": {"max_keyframe": 2, "keyframes": [
			{"index": 0, "end_frame": 10, "channel_mask": 1, "source_mode": "CASTER",
				"interpolation": "COSINE_A", "angle": [0, 0, 0]},
			{"index": 1, "end_frame": 30, "channel_mask": 1, "source_mode": "MAP",
				"interpolation": "COSINE_A", "angle": [0, 0, 0]},
			{"index": 2, "end_frame": 50, "channel_mask": 1, "source_mode": "MAP",
				"interpolation": "COSINE_A", "angle": [0, 128, 0]}]},
	}))
	var spans: Array = _lane(score, "camera:phase1:angle").get("spans", [])
	_assert_true(spans.size() == 3, "three angle spans project")
	if spans.size() != 3:
		return
	_assert_true(not bool(spans[0]["fields"]["spacer"]),
		"the CASTER pan is a live event (zero value, external anchor)")
	_assert_true(bool(spans[1]["fields"]["spacer"]),
		"the MAP+zero hold is a spacer")
	_assert_true(not bool(spans[2]["fields"]["spacer"]),
		"the MAP delta with a real yaw is a live event")


## A coalesced keyframe shares ONE command word across its mask but keeps SEPARATE per-channel
## values — so it can be a spacer on one sub-channel and a real move on another. 6 such
## keyframes exist in the ROM, which is why the verdict is per SPAN, never per keyframe.
func _test_coalesced_keyframe_is_judged_per_span() -> void:
	var score := Model.build(_effect({
		"phase1": {"max_keyframe": 0, "keyframes": [
			{"index": 0, "end_frame": 20, "channel_mask": 3, "source_mode": "MAP",
				"interpolation": "COSINE_A", "angle": [0, 0, 0], "position": [0, 40, 0]}]},
	}))
	var ang: Array = _lane(score, "camera:phase1:angle").get("spans", [])
	var pos: Array = _lane(score, "camera:phase1:position").get("spans", [])
	_assert_true(ang.size() == 1 and bool(ang[0]["fields"]["spacer"]),
		"the shared keyframe is a SPACER on angle (its angle delta is zero)")
	_assert_true(pos.size() == 1 and not bool(pos[0]["fields"]["spacer"]),
		"...and a LIVE EVENT on position (its position delta is not) — same keyframe")


# --- C: the hide ----------------------------------------------------------

## Camera has no Enable bit and no Solo/Mute, so its spans carry no `enabled` field. The rule
## is "hidden unless EXPLICITLY disabled" — the clause defaults TRUE.
func _test_camera_spacer_hides_without_an_enabled_field() -> void:
	var span := {"id": "camera:phase1:angle#1", "kind": "camera", "fields": {"spacer": true}}
	_assert_true(Timeline.is_hidden_spacer(span, ""),
		"a camera spacer hides though it carries no `enabled` field")


func _test_selected_camera_spacer_always_draws() -> void:
	var span := {"id": "camera:phase1:angle#1", "kind": "camera", "fields": {"spacer": true}}
	_assert_true(not Timeline.is_hidden_spacer(span, "camera:phase1:angle#1"),
		"the selected camera spacer draws — the only way to edit a hold in place")


## The default flip must not touch colour: a deliberately-disabled colour event stamps
## `enabled: false` explicitly, so it stays "muted, not gone" (ADR-0087 fifth, decision 4).
func _test_colour_disabled_carve_out_survives_the_default_flip() -> void:
	var span := {"id": "palette:for_each:caster#3", "kind": "palette",
		"fields": {"spacer": true, "enabled": false}}
	_assert_true(not Timeline.is_hidden_spacer(span, ""),
		"a deliberately-disabled colour event still draws (hatched, selectable)")
	var live := {"id": "palette:for_each:caster#4", "kind": "palette",
		"fields": {"spacer": true, "enabled": true}}
	_assert_true(Timeline.is_hidden_spacer(live, ""),
		"...while an enabled colour spacer still hides")


func _test_span_without_a_spacer_field_is_never_hidden() -> void:
	var span := {"id": "particle:for_each:0#2", "kind": "particle", "fields": {"disabled": false}}
	_assert_true(not Timeline.is_hidden_spacer(span, ""),
		"a span carrying no `spacer` field is never hidden")


## The predicate is only half the contract — `hit_test` must actually honour it. It has TWO
## passes: an exact rect pass that skips hidden spacers, and a LOOSE pass (within
## LOOSE_SELECT_TOL of a lane row, for "difficult to select an event"). A hidden span's rect
## stays in `_span_rects` because the gap right-click needs it, and the loose pass measures
## distance to the nearest EDGE — so `d == 0` for any point INSIDE it. Without a skip there
## too, the loose pass hands back the span the exact pass just refused: the click selects an
## invisible event instead of seeking, and the right-click never reaches `lane_context`, so
## "Add waypoint here" is unreachable. Guarded end-to-end through the real control.
func _test_a_click_inside_a_hidden_spacer_seeks_it_does_not_select() -> void:
	var tl = Timeline.new()
	tl.size = Vector2(1200, 400)
	add_child(tl)
	tl.load_score(Model.build(_effect({
		"phase1": {"max_keyframe": 1, "keyframes": [
			{"index": 0, "end_frame": 60, "channel_mask": 1, "source_mode": "MAP",
				"interpolation": "COSINE_A", "angle": [0, 0, 0]},
			{"index": 1, "end_frame": 90, "channel_mask": 1, "source_mode": "TARGET",
				"interpolation": "COSINE_A", "angle": [0, 0, 0]}]},
	})))
	tl.rebuild_layout()
	var rects: Dictionary = _span_rects_by_id(tl)
	var hold: Rect2 = rects.get("camera:phase1:angle#0", Rect2())
	var move: Rect2 = rects.get("camera:phase1:angle#1", Rect2())
	_assert_true(hold.size.x > 2.0 * Timeline.LOOSE_SELECT_TOL,
		"the hold's rect is wide enough that its centre is outside loose range of the move")
	var deep: Vector2 = hold.get_center()
	var hit: Dictionary = tl.hit_test(deep)
	_assert_true(String(hit.get("kind", "")) == "seek",
		"a click deep inside a hidden hold SEEKS — it is empty space, in both passes")
	_assert_true(String(tl.hit_test(move.get_center()).get("kind", "")) == "select"
			and String(tl.hit_test(move.get_center()).get("span_id", "")) == "camera:phase1:angle#1",
		"...while the live TARGET move beside it still selects normally")
	# The selected-span carve-out reaches the hit-test too: once selected, the hold is grabbable
	# again, which is what makes editing a hold in place possible at all.
	tl.select_span("camera:phase1:angle#0")
	tl.rebuild_layout()
	_assert_true(String(tl.hit_test(deep).get("span_id", "")) == "camera:phase1:angle#0",
		"the SELECTED hold is selectable again (the in-place edit carve-out)")
	tl.queue_free()


func _span_rects_by_id(tl) -> Dictionary:
	var out: Dictionary = {}
	for hit in tl._span_rects:
		out[String(hit["span"]["id"])] = hit["rect"]
	return out


# --- D: the way back in ---------------------------------------------------

## A hidden hold is unselectable, so the right-click routes through lane_context. The only verb
## is the SAME insert-waypoint a drawn span offers — no Delete (nothing addressable in empty
## space) and no colour-style `spacer_stub` (camera has no born-disabled seed).
func _test_gap_actions_offer_add_waypoint() -> void:
	var lane := {"id": "camera:for_each:zoom", "kind": "camera",
		"phase": "for_each", "channel_index": 4}
	var acts := Page._camera_spacer_gap_actions(lane, 22)
	_assert_true(acts.size() == 1, "one verb: Add waypoint here")
	if acts.size() != 1:
		return
	var ref: Dictionary = acts[0]["field_ref"]
	_assert_true(String(acts[0]["verb"]) == "insert", "the verb lowers to insert_event")
	_assert_true(String(ref.get("channel", "")) == "camera"
			and String(ref.get("camera_channel", "")) == "zoom"
			and String(ref.get("context", "")) == "for_each"
			and int(ref.get("frame", -1)) == 22,
		"it addresses (camera, for_each, zoom) at the clicked phase-local frame")
	_assert_true(not ref.has("spacer_stub"),
		"no colour-style born-disabled stub flag — camera has no Enable bit")
	_assert_true(Page._camera_spacer_gap_actions(
			{"id": "camera_compiled:for_each", "kind": "camera_compiled",
				"phase": "for_each", "channel_index": 0}, 22).is_empty(),
		"the read-only compiled lane offers nothing")


# --- E: the wake ----------------------------------------------------------

## `_apply_vec` is the fast in-place path with no reproject, so a value edit that WAKES a hold
## would otherwise leave a real camera move invisible. It now flags `relayout` on a ZERO
## CROSSING only — not on every spinbox tick, which is the cost issue #298 is about.
func _test_value_edit_reprojects_only_on_a_zero_crossing() -> void:
	var data = _effect({
		"phase1": {"max_keyframe": 1, "keyframes": [
			{"index": 0, "end_frame": 20, "channel_mask": 1, "source_mode": "MAP",
				"interpolation": "COSINE_A", "angle": [0, 0, 0]},
			{"index": 1, "end_frame": 40, "channel_mask": 1, "source_mode": "MAP",
				"interpolation": "COSINE_A", "angle": [0, 128, 0]}]},
	})
	var ref0 := {"channel": "camera", "context": "phase1", "camera_channel": "angle",
		"ordinal": 0, "field": "angle_y"}
	var woke := CameraChannelClass.apply_raw(data, ref0, 128)
	_assert_true(bool(woke.get("relayout", false)),
		"zero → real WAKES the hold, so the edit reprojects")
	var moved := CameraChannelClass.apply_raw(data, ref0, 256)
	_assert_true(not bool(moved.get("relayout", false)),
		"real → real stays the cheap in-place fold (no rebuild per spinbox tick)")
	var slept := CameraChannelClass.apply_raw(data, ref0, 0)
	_assert_true(bool(slept.get("relayout", false)),
		"real → zero puts the event back to sleep, and reprojects too")


# --- F: real ROM data -----------------------------------------------------

## The three E317 for-each holds the author cited (quoted as RAW SLOTS, which is what
## `Model.keyframe_address` printed before the #286 build note fixed it to the ordinal),
## all `MAP` + `[0,0,0]` + COSINE_A, at for-each offset 8:
##   angle    raw3  f18-27   position raw4  f18-29   zoom raw7  f16-78
## Their neighbours — the CASTER pan in, the TARGET framing, the SLOT_COPY return — all store
## `[0,0,0]` too and must stay LIVE: on this data the source mode is the entire discriminator.
## Skipped (not failed) where the gitignored extract is absent, the acceptance precedent.
func _test_real_E317_pins_the_three_cited_holds() -> void:
	var dir := "res://assets/effects/E317"
	if not DirAccess.dir_exists_absolute(dir):
		print("  (skip) E317 extract absent")
		return
	var ed = ExMateriaEffects.EffectData.load_from_directory(dir)
	if ed == null or ed.camera == null:
		print("  (skip) E317 camera section absent")
		return
	var score := Model.build(ed)
	# (span index within the sub-channel lane, raw keyframe slot, expected spacer)
	var pins := {
		"camera:for_each:angle": [[0, 2, false], [1, 3, true], [2, 6, false],
			[3, 7, true], [4, 8, false]],
		"camera:for_each:position": [[0, 2, false], [1, 4, true], [2, 5, false],
			[3, 7, true], [4, 8, false]],
		"camera:for_each:zoom": [[0, 1, false], [1, 7, true], [2, 8, false]],
	}
	for lane_id in pins:
		var spans: Array = _lane(score, lane_id).get("spans", [])
		_assert_true(spans.size() == pins[lane_id].size(),
			"%s projects %d spans" % [lane_id, pins[lane_id].size()])
		if spans.size() != pins[lane_id].size():
			continue
		for pin in pins[lane_id]:
			var span: Dictionary = spans[pin[0]]
			_assert_true(int(span["keyframe_index"]) == pin[1],
				"%s span %d is raw slot %d" % [lane_id, pin[0], pin[1]])
			_assert_true(bool(span["fields"]["spacer"]) == pin[2],
				"%s raw%d (%s) is %s" % [lane_id, pin[1],
					span["fields"]["source_mode"],
					"a HOLD" if pin[2] else "a live move"])
	# The compiled storage lane hides nothing — it stays the faithful mirror of the packed
	# store, and is where a hidden hold remains legible (decision 8).
	for span in _lane(score, "camera_compiled:for_each").get("spans", []):
		_assert_true(not bool(span.get("fields", {}).get("spacer", false)),
			"compiled marker raw%d carries no spacer verdict" % int(span["keyframe_index"]))


# --- fixtures -------------------------------------------------------------

## A minimal EffectData carrying a phase1-offset-0 timeline and a camera table from the given
## camera.json-shaped dict.
func _effect(camera_json: Dictionary):
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = ExMateriaEffects.CameraData.from_json(camera_json)
	return ed


func _lane(score: Dictionary, lane_id: String) -> Dictionary:
	for lane in score.get("lanes", []):
		if String(lane.get("id", "")) == lane_id:
			return lane
	return {}


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
