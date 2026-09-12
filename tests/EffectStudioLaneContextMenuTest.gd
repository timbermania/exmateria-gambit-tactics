extends Node
## TDD guard for the LANE CONTEXT-MENU resolver (ADR-0086 dec. 7, #287-adjacent).
##
## Right-clicking a timeline lane row offers the add/delete verbs. The pure decision — given
## the right-clicked span + the frame under the cursor, WHICH verbs with WHICH field_refs —
## is `EffectStudioPage._lane_context_actions(span, frame)`. Fast + ROM-free (no scene): the
## PopupMenu display + dispatch to the host's EffectEditSession is the headful acceptance.
##
## Camera (ADR-0086): a sub-channel span offers Add (insert at the cursor frame — a
## span-cut) and Delete (the span's own event, by ordinal) — a camera span COVERS an
## interval, so clicking it is clicking in its time. Sound is different: an event is
## an INSTANT and "add here" targets a GAP, which on the timeline is EMPTY lane space
## — so Add lives on the lane-level GAP right-click (`_gap_context_actions`, fed by
## lane_context_requested) while an EVENT span offers Delete only and the inert
## TERMINATOR end-cap offers nothing (select-to-inspect; its bytes are the last
## event's gap). Particle spans (ADR-0089) offer Add (Split) + Delete, and their gaps
## offer Add. Screen / palette spans (ADR-0087) carry the same Add + Delete verbs,
## addressed by RAW keyframe index (palette adds its tint channel_name); their INERT
## SPACER regions (fifth amendment) render as empty space and offer only "Add event
## here" (the spacer tests below). The read-only compiled storage lane is INERT
## (no field_ref → authors nothing).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioLaneContextMenuTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_camera_subchannel_span_offers_add_and_delete()
	_test_add_frame_is_converted_to_phase_local()
	_test_compiled_storage_lane_is_inert()
	_test_unmapped_camera_mask_offers_nothing()
	_test_sound_event_span_offers_delete_only()
	_test_sound_terminator_offers_nothing()
	_test_sound_gap_offers_add_here()
	_test_gap_on_other_or_empty_lanes_offers_nothing()
	_test_verb_landing_span_id_per_channel()
	_test_particle_span_offers_add_and_delete()
	_test_particle_drawn_span_add_is_labelled_split()
	_test_particle_gap_offers_add_only()
	_test_palette_spacer_region_offers_add_event_only()
	_test_screen_spacer_region_offers_add_event_only()

	print("\n=== EffectStudioLaneContextMenuTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioLaneContextMenuTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioLaneContextMenuTest")
		get_tree().quit(0)


## A camera angle span, right-clicked at frame 14, yields exactly two actions: Add (insert
## at the cursor frame — the insert-waypoint verb, addressed by frame) and Delete (this
## event, addressed by its (camera_channel, ordinal) §#286 address).
func _test_camera_subchannel_span_offers_add_and_delete() -> void:
	var span := _camera_span("angle", 1)   # channel_index mask 1, ordinal 1
	var actions: Array = Page._lane_context_actions(span, 14)

	_assert_eq(actions.size(), 2, "a camera sub-channel span offers Add + Delete")
	if actions.size() < 2:
		return

	var add: Dictionary = _action_by_verb(actions, "insert")
	var add_ref: Dictionary = add.get("field_ref", {})
	_assert_eq(add_ref.get("channel", ""), "camera", "Add targets the camera channel")
	_assert_eq(add_ref.get("context", ""), "for_each", "Add carries the phase")
	_assert_eq(add_ref.get("camera_channel", ""), "angle", "Add carries the sub-channel lane")
	_assert_eq(add_ref.get("frame", -1), 14, "Add is addressed by the cursor frame (a span-cut)")
	_assert_eq(add_ref.has("ordinal"), false, "Add has no ordinal — the event does not exist yet")

	var del: Dictionary = _action_by_verb(actions, "delete")
	var del_ref: Dictionary = del.get("field_ref", {})
	_assert_eq(del_ref.get("channel", ""), "camera", "Delete targets the camera channel")
	_assert_eq(del_ref.get("context", ""), "for_each", "Delete carries the phase")
	_assert_eq(del_ref.get("camera_channel", ""), "angle", "Delete carries the sub-channel lane")
	_assert_eq(del_ref.get("ordinal", -1), 1, "Delete is addressed by the span's ordinal (§#286)")
	_assert_eq(del_ref.has("frame"), false, "Delete has no frame — it removes an existing event")


## The cursor frame is SCORE-ABSOLUTE (the timeline axis includes the phase offset), but
## CameraChannel.insert_event wants a PHASE-LOCAL end_frame. The span carries both `start`
## (absolute) and `authored_start` (phase-local); their difference IS the offset. A span at
## phase offset 100 (start 108, authored_start 8), right-clicked at absolute frame 109, must
## Add at phase-local frame 9 — else the keyframe lands 100 frames off.
func _test_add_frame_is_converted_to_phase_local() -> void:
	var span := _camera_span("angle", 0)
	span["authored_start"] = 8
	span["start"] = 108        # offset = start - authored_start = 100

	var actions: Array = Page._lane_context_actions(span, 109)
	var add_ref: Dictionary = _action_by_verb(actions, "insert").get("field_ref", {})
	_assert_eq(add_ref.get("frame", -1), 9,
		"the absolute cursor frame is converted to the phase-local end_frame")


## The read-only compiled storage lane (kind camera_compiled) authors nothing — no verbs.
func _test_compiled_storage_lane_is_inert() -> void:
	var span := {"kind": "camera_compiled", "phase": "for_each",
		"channel_index": 0, "keyframe_index": 2, "lane_id": "camera_compiled:for_each"}
	_assert_eq(Page._lane_context_actions(span, 14).size(), 0,
		"the compiled storage lane is inert")


## A camera span whose mask maps to no sub-channel lane offers nothing — the mask-name
## lookup is the guard, so an unmapped mask (0, or a future bit the lane table doesn't
## know) is inert rather than a menu whose field_ref would address an empty lane name.
func _test_unmapped_camera_mask_offers_nothing() -> void:
	var span := {"kind": "camera", "phase": "for_each",
		"channel_index": 0, "keyframe_index": 1, "lane_id": "camera:for_each"}
	_assert_eq(Page._lane_context_actions(span, 14).size(), 0,
		"an unmapped camera mask offers no lane verbs")


## A sound EVENT span offers Delete only: an event is an instant, so "add here" is a
## GAP gesture (the lane-level right-click below), not something you do ON a marker.
func _test_sound_event_span_offers_delete_only() -> void:
	var span := _sound_span("event", 1)
	var actions: Array = Page._lane_context_actions(span, 20)

	_assert_eq(actions.size(), 1, "a sound event span offers exactly one verb")
	var del_ref: Dictionary = _action_by_verb(actions, "delete").get("field_ref", {})
	_assert_eq(del_ref.get("channel", ""), "sound", "Delete targets the sound channel")
	_assert_eq(del_ref.get("phase", ""), "for_each", "Delete carries the phase")
	_assert_eq(del_ref.get("channel_index", -1), 0, "Delete carries the channel index")
	_assert_eq(del_ref.get("event_index", -1), 1, "Delete is addressed by the event index")
	_assert_eq(del_ref.has("frame"), false, "Delete has no frame — it removes an existing event")


## The terminator end-cap is select-to-inspect only — no verbs. Its slot's bytes are
## the last event's gap (delete would be two-verbs-one-byte), and adding lives on the
## gap itself now.
func _test_sound_terminator_offers_nothing() -> void:
	var span := _sound_span("terminator", 3)
	_assert_eq(Page._lane_context_actions(span, 40).size(), 0,
		"the terminator offers no verbs (select-to-inspect only)")


## The GAP gesture: right-clicking empty space on a sound lane offers "Add sound event
## here" at the cursor frame, converted to phase-local via the lane's projected spans
## (their start − authored_start is the phase offset).
func _test_sound_gap_offers_add_here() -> void:
	var lane := _sound_lane()
	var actions: Array = Page._gap_context_actions(lane, 20)

	_assert_eq(actions.size(), 1, "a sound lane gap offers exactly one verb")
	var add_ref: Dictionary = _action_by_verb(actions, "insert").get("field_ref", {})
	_assert_eq(add_ref.get("channel", ""), "sound", "Add targets the sound channel")
	_assert_eq(add_ref.get("phase", ""), "for_each", "Add carries the phase")
	_assert_eq(add_ref.get("channel_index", -1), 0, "Add carries the channel index")
	_assert_eq(add_ref.get("frame", -1), 12,
		"Add converts the absolute cursor frame to phase-local (20 − offset 8)")
	_assert_eq(add_ref.has("event_index"), false, "Add has no event_index — it does not exist yet")


## Gap right-clicks on other lane kinds (camera tiles its spans; screen/palette are
## follow-ups) and on an EMPTY sound lane (no spans → no offset, and the verb cannot
## seed an empty channel) offer nothing.
func _test_gap_on_other_or_empty_lanes_offers_nothing() -> void:
	var cam_lane := {"id": "camera:for_each:angle", "kind": "camera",
		"phase": "for_each", "channel_index": 1, "spans": [_camera_span("angle", 0)]}
	_assert_eq(Page._gap_context_actions(cam_lane, 20).size(), 0,
		"a camera lane gap offers nothing (its spans tile the row)")
	var empty_lane := {"id": "sound:for_each:1", "kind": "sound",
		"phase": "for_each", "channel_index": 1, "spans": []}
	_assert_eq(Page._gap_context_actions(empty_lane, 20).size(), 0,
		"an empty sound lane offers nothing (no gap to split yet)")


## After a structural verb the page lands the selection on the result's ordinal — the
## span id it selects is a pure function of (field_ref, ordinal), per channel.
func _test_verb_landing_span_id_per_channel() -> void:
	_assert_eq(Page._verb_landing_span_id(
		{"channel": "camera", "context": "for_each", "camera_channel": "angle"}, 1),
		"camera:for_each:angle#1", "camera lands on its (lane, ordinal) span id")
	_assert_eq(Page._verb_landing_span_id(
		{"channel": "sound", "phase": "phase1", "channel_index": 2}, 3),
		"sound:phase1:2#3", "sound lands on its (lane, event index) span id")


## A particle span (ADR-0089 particle_timeline) offers Add (split at the cursor, phase-local)
## + Delete (this span by its raw keyframe index), addressed by the flat (phase, channel_index).
func _test_particle_span_offers_add_and_delete() -> void:
	var span := {
		"id": "particle:for_each:0#2", "lane_id": "particle:for_each:0",
		"kind": "particle", "phase": "for_each",
		"channel_index": 0, "keyframe_index": 2,
		"authored_start": 10, "start": 18,   # offset = 8
	}
	var actions: Array = Page._lane_context_actions(span, 25)
	_assert_eq(actions.size(), 2, "a particle span offers Add + Delete")
	if actions.size() < 2:
		return

	var add_ref: Dictionary = _action_by_verb(actions, "insert").get("field_ref", {})
	_assert_eq(add_ref.get("channel", ""), "particle", "Add targets the particle channel")
	_assert_eq(add_ref.get("context", ""), "for_each", "…the phase")
	_assert_eq(add_ref.get("channel_index", -1), 0, "…the lane index")
	_assert_eq(add_ref.get("frame", -1), 17, "…the cursor frame converted to phase-local (25 − 8)")
	_assert_eq(add_ref.has("event_index"), false, "Add has no keyframe yet")

	var del_ref: Dictionary = _action_by_verb(actions, "delete").get("field_ref", {})
	_assert_eq(del_ref.get("channel", ""), "particle", "Delete targets the particle channel")
	_assert_eq(del_ref.get("event_index", -1), 2, "Delete is addressed by the raw keyframe index")
	_assert_eq(del_ref.has("frame"), false, "Delete has no frame")


## ADR-0089 particle_timeline (Add/Split honesty): right-clicking a DRAWN burst offers to
## Split it at the cursor — the verb genuinely cuts a drawn span's extent, so it is named
## "Split span here", NOT "Add span here" (which reads as a no-op insert). Same insert
## lowering; only the label changes so the drawn-span action is honest.
func _test_particle_drawn_span_add_is_labelled_split() -> void:
	var span := {
		"id": "particle:for_each:0#2", "lane_id": "particle:for_each:0",
		"kind": "particle", "phase": "for_each",
		"channel_index": 0, "keyframe_index": 2,
		"authored_start": 10, "start": 18,
	}
	var add: Dictionary = _action_by_verb(Page._lane_context_actions(span, 25), "insert")
	_assert_eq(String(add.get("label", "")), "Split span here",
		"a drawn particle burst's insert verb is honestly labelled Split, not Add")


## Add-in-a-gap (ADR-0089): the gap right-click has NO span — it resolves to (phase,
## channel_index, phase-local frame). The pure gap resolver offers ONLY "Add span here"
## (born-disabled insert at the cursor; no Delete — a gap has no drawn span to remove).
func _test_particle_gap_offers_add_only() -> void:
	var actions: Array = Page._lane_gap_context_actions("for_each", 0, 17)
	_assert_eq(actions.size(), 1, "a particle gap offers exactly one verb")
	if actions.is_empty():
		return
	var add: Dictionary = actions[0]
	_assert_eq(String(add.get("label", "")), "Add span here", "…labelled Add span here")
	_assert_eq(String(add.get("verb", "")), "insert", "…the insert verb")
	var ref: Dictionary = add.get("field_ref", {})
	_assert_eq(ref.get("channel", ""), "particle", "Add targets the particle channel")
	_assert_eq(ref.get("context", ""), "for_each", "…the phase")
	_assert_eq(ref.get("channel_index", -1), 0, "…the lane index")
	_assert_eq(ref.get("frame", -1), 17, "…the phase-local cursor frame (the page already offset-corrected)")
	_assert_eq(ref.has("event_index"), false, "Add has no keyframe yet")


## Add-into-a-spacer (ADR-0087 decs. 23-28): right-clicking an INVISIBLE spacer region of a
## colour lane behaves like an emitter gap — the timeline emits lane_context (the hidden spacer
## is unselectable), and the pure resolver offers ONLY "Add event here": a `spacer_stub` insert
## that cuts the spacer into a 1-frame born-disabled stub bracketed by spacers. No Delete (you
## build over empty space, you don't remove it). Palette carries its channel_name; the frame is
## already phase-local (the page offset-corrected it).
func _test_palette_spacer_region_offers_add_event_only() -> void:
	var lane := {"id": "palette:for_each:caster", "kind": "palette", "phase": "for_each"}
	var actions: Array = Page._colour_spacer_gap_actions(lane, 22)
	_assert_eq(actions.size(), 1, "a palette spacer region offers exactly one verb")
	if actions.is_empty():
		return
	var add: Dictionary = actions[0]
	_assert_eq(String(add.get("label", "")), "Add event here", "…labelled Add event here")
	_assert_eq(String(add.get("verb", "")), "insert", "…the insert verb")
	var ref: Dictionary = add.get("field_ref", {})
	_assert_eq(ref.get("channel", ""), "palette", "Add targets the palette channel")
	_assert_eq(ref.get("context", ""), "for_each", "…the phase")
	_assert_eq(ref.get("channel_name", ""), "caster", "…the tint channel (parsed from the lane id)")
	_assert_eq(ref.get("frame", -1), 22, "…the phase-local cursor frame")
	_assert_eq(bool(ref.get("spacer_stub", false)), true, "…flagged spacer_stub (the 3-way split)")


func _test_screen_spacer_region_offers_add_event_only() -> void:
	var lane := {"id": "screen:phase2", "kind": "screen", "phase": "phase2"}
	var actions: Array = Page._colour_spacer_gap_actions(lane, 5)
	_assert_eq(actions.size(), 1, "a screen spacer region offers exactly one verb")
	if actions.is_empty():
		return
	var ref: Dictionary = actions[0].get("field_ref", {})
	_assert_eq(ref.get("channel", ""), "screen", "Add targets the screen channel")
	_assert_eq(ref.get("context", ""), "phase2", "…the phase")
	_assert_eq(ref.has("channel_name"), false, "screen is 1-D — no channel_name")
	_assert_eq(ref.get("frame", -1), 5, "…the phase-local cursor frame")
	_assert_eq(bool(ref.get("spacer_stub", false)), true, "…flagged spacer_stub")


# --- helpers ----------------------------------------------------------------

## A sound-lane span as EffectScoreModel._sound_spans emits it: kind "sound", the
## channel identity, the keyframe index, and the absolute/local start pair (phase
## offset 8 — the standard phase1_duration in the timeline fixtures).
func _sound_span(role: String, keyframe_index: int) -> Dictionary:
	return {
		"id": "sound:for_each:0#%d" % keyframe_index,
		"lane_id": "sound:for_each:0",
		"kind": "sound", "role": role, "phase": "for_each",
		"channel_index": 0, "keyframe_index": keyframe_index,
		"authored_start": 10, "start": 18,   # offset = 8
	}


## A sound lane as EffectScoreModel._sound_lanes emits it, with one projected span
## carrying the phase offset (start − authored_start = 8).
func _sound_lane() -> Dictionary:
	return {
		"id": "sound:for_each:0", "kind": "sound", "label": "Sound 0",
		"phase": "for_each", "channel_index": 0,
		"spans": [_sound_span("event", 0)],
	}

## A camera sub-channel span as EffectScoreModel._camera_spans emits it: kind "camera",
## channel_index = the sub-channel mask bit, and the stable ordinal (§#286).
func _camera_span(channel_name: String, ordinal: int) -> Dictionary:
	var mask: int = {"angle": 1, "position": 2, "zoom": 4}[channel_name]
	return {
		"id": "camera:for_each:%s#%d" % [channel_name, ordinal],
		"lane_id": "camera:for_each:%s" % channel_name,
		"kind": "camera", "phase": "for_each",
		"channel_index": mask, "keyframe_index": 99, "ordinal": ordinal,
	}


func _action_by_verb(actions: Array, verb: String) -> Dictionary:
	for a in actions:
		if String(a.get("verb", "")) == verb:
			return a
	return {}


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
