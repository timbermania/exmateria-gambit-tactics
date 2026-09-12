extends Node
## TDD guard for EffectScoreModel — the PURE projection that turns a parsed
## EffectData into the Effect Studio score (phase sections + lanes + spans on one
## absolute frame axis). No scene, no widgets: the model is the testable core, the
## timeline view is thin glue. See CONTEXT.md "Effect Studio" / "Score" cluster.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectScoreModelTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData
const TimelineClass = preload("res://src/effects/studio/EffectScoreTimeline.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_particle_span_absolute_placement()
	_test_phase_offsets_and_sections()
	_test_gaps_skipped_empty_channel_kept()
	_test_screen_color_lane()
	_test_palette_color_lanes()
	_test_camera_sub_channel_lanes()
	_test_sound_trigger_lanes()
	_test_a_reproject_keeps_the_builds_frame_axis()
	_test_sound_ghost_bar_and_section_extent()
	_test_sound_anchor_offset_surfaces_on_span()
	_test_sound_energy_envelope_surfaces_on_span()
	_test_container_views_thread_into_score()
	_test_identity_is_stable_across_authored_edit()
	_test_real_effect_projects_cleanly()
	_test_inspector_header_and_particle_event_section()
	_test_inspector_sections_palette()
	_test_emitter_view_groups_ordered()
	_test_emitter_view_out_of_range()
	_test_emitter_view_vec3_range_and_config()
	_test_emitter_view_child_edge_toggle()
	_test_emitter_view_real_effect()
	_test_keyframe_address_particle()
	_test_keyframe_address_palette()
	_test_keyframe_address_sound()
	_test_keyframe_address_camera()
	_test_keyframe_address_empty_span()
	_test_palette_window_drops_padding_keyframes()
	_test_sound_window_drops_terminal_keyframe()
	_test_rebuild_kind_lanes_refreshes_one_kind_reuses_others()
	_test_rebuild_kind_lanes_preserves_order_and_recomputes_extent()
	_test_rebuild_kind_lanes_drops_every_group_its_builder_re_emits()
	_test_pacing_lane_two_bands()
	_test_pacing_lane_absent_without_time_scale()
	_test_pacing_lane_enabled_flags()
	_test_pacing_norm_height_map()
	_test_pacing_factor_at()

	print("\n=== EffectScoreModelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectScoreModelTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectScoreModelTest")
		get_tree().quit(0)


## A for-each channel keyframe is placed on the absolute axis at
## `phase1_duration + authored_time` (the for-each offset), while its authored
## (phase-local) frames are preserved for round-trip editing. The span a keyframe
## owns is `[kf[N-1].time, kf[N].time)`, and it carries a stable id.
func _test_particle_span_absolute_placement() -> void:
	var ed = _effect_with_timeline(8, 64, [
		{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
			{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 2}]},
	])
	var score := Model.build(ed)
	var lane := _lane(score, "particle:for_each:0")
	_assert_true(not lane.is_empty(), "for-each channel 0 becomes a lane")
	_assert_eq(lane["spans"].size(), 1, "one emitting span")
	var span: Dictionary = lane["spans"][0]
	_assert_eq(span["authored_start"], 0, "authored start is the phase-local frame")
	_assert_eq(span["authored_end"], 10, "authored end is the phase-local frame")
	_assert_eq(span["start"], 8, "absolute start = phase1_duration + authored start")
	_assert_eq(span["end"], 18, "absolute end = phase1_duration + authored end")
	_assert_eq(span["emitter_index"], 1, "emitter_id 2 spawns emitter index 1")
	_assert_eq(span["id"], "particle:for_each:0#1", "span id is lane_id#keyframe_index")


## Each phase's keyframes land at its own axis offset (phase1→0, for_each→p1d,
## phase2→p1d+phase2_delay), the phase overlap is preserved (phase2 X-band starts
## inside for-each), and the ruler section per phase spans its own lanes' extent.
func _test_phase_offsets_and_sections() -> void:
	var ed = _effect_with_timeline(8, 64, [
		{"context": "phase1", "channel_index": 0, "max_keyframe": 1, "keyframes": [
			{"time": 0, "emitter_id": 0}, {"time": 5, "emitter_id": 1}]},
		{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
			{"time": 0, "emitter_id": 0}, {"time": 20, "emitter_id": 1}]},
		{"context": "phase2", "channel_index": 0, "max_keyframe": 1, "keyframes": [
			{"time": 0, "emitter_id": 0}, {"time": 30, "emitter_id": 1}]},
	])
	var score := Model.build(ed)
	_assert_eq(_lane(score, "particle:phase1:0")["spans"][0]["start"], 0, "phase1 offset is 0")
	_assert_eq(_lane(score, "particle:for_each:0")["spans"][0]["start"], 8, "for_each offset is p1d")
	_assert_eq(_lane(score, "particle:phase2:0")["spans"][0]["start"], 72, "phase2 offset is p1d+delay")
	# phase2 span [72,102) is the far end → max_frame 102
	_assert_eq(score["max_frame"], 102, "max_frame is the far end of all spans")
	var p2 := _phase(score, "phase2")
	_assert_eq(p2["start"], 72, "phase2 section starts at its offset (overlapping for-each)")
	_assert_eq(p2["end"], 102, "phase2 section ends at its lanes' far edge")
	_assert_eq(p2["label"], "Phase 2", "phase carries a plain-words label")


## An emitter_id-0 keyframe is a gap (not drawn), but a channel that only skips is
## now KEPT as an empty lane — you can't author a channel you can't see, so every
## defined channel shows even with zero spans.
func _test_gaps_skipped_empty_channel_kept() -> void:
	var ed = _effect_with_timeline(8, 64, [
		{"context": "for_each", "channel_index": 0, "max_keyframe": 3, "keyframes": [
			{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1},
			{"time": 20, "emitter_id": 0}, {"time": 30, "emitter_id": 2}]},
		{"context": "for_each", "channel_index": 1, "max_keyframe": 2, "keyframes": [
			{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 0},
			{"time": 20, "emitter_id": 0}]},
	])
	var score := Model.build(ed)
	var ch0 := _lane(score, "particle:for_each:0")
	_assert_eq(ch0["spans"].size(), 2, "the two emitting keyframes become spans; the gap is skipped")
	_assert_eq(ch0["spans"][0]["authored_end"], 10, "first span is kf1 [0,10)")
	_assert_eq(ch0["spans"][1]["authored_start"], 20, "second span is kf3 [20,30) — the gap between is dropped")
	var ch1 := _lane(score, "particle:for_each:1")
	_assert_true(not ch1.is_empty(), "an all-skip channel is kept as a lane (authorable)")
	_assert_eq(ch1["spans"].size(), 0, "the kept empty channel has zero spans")


## Camera splits into three independent sub-channels (angle/position/zoom) per phase.
## A keyframe's channel_mask selects which sub-channel(s) it drives; each sub-channel
## span runs from the previous mask-selected keyframe's end_frame to this one's.
func _test_camera_sub_channel_lanes() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.camera = ExMateriaEffects.CameraData.from_json({
		"phase1": {"max_keyframe": 3, "keyframes": [
			{"index": 0, "end_frame": 0, "channel_mask": 2, "interpolation": "UNKNOWN_0x0000"},
			{"index": 1, "end_frame": 8, "channel_mask": 2, "interpolation": "COSINE_A",
				"source_mode": "TARGET", "position": [1, 2, 3]},
			{"index": 2, "end_frame": 8, "channel_mask": 1, "interpolation": "COSINE_A",
				"source_mode": "DIRECT", "angle": [10, 20, 30]},
			{"index": 3, "end_frame": 58, "channel_mask": 3, "interpolation": "COSINE_A",
				"source_mode": "MAP"}]},
	})
	var score := Model.build(ed)
	# Position (mask&2): kf1 [0,8) then kf3 (mask 3 includes 2) [8,58). kf0 end 0 → no span.
	var pos := _lane(score, "camera:phase1:position")
	_assert_eq(pos["label"], "Cam position", "position sub-channel lane is labelled")
	_assert_eq(pos["spans"].size(), 2, "position driven by kf1 and kf3")
	_assert_eq(pos["spans"][0]["start"], 0, "kf1 owns [0,8) — phase1 offset is 0")
	_assert_eq(pos["spans"][0]["end"], 8, "kf1 absolute end")
	_assert_eq(pos["spans"][1]["authored_start"], 8, "kf3 position span starts at prev selected end (8)")
	_assert_eq(pos["spans"][1]["authored_end"], 58, "kf3 position span ends at its end_frame")
	# Angle (mask&1): kf2 [0,8), kf3 [8,58).
	var ang := _lane(score, "camera:phase1:angle")
	_assert_eq(ang["spans"].size(), 2, "angle driven by kf2 and kf3")
	# Zoom (mask&4): none of these keyframes select it → empty lane, still present.
	var zoom := _lane(score, "camera:phase1:zoom")
	_assert_true(not zoom.is_empty(), "the zoom sub-channel lane is present even with no keyframes")
	_assert_eq(zoom["spans"].size(), 0, "zoom has no spans here")


## Sound lanes are one per (phase, channel_index). A keyframe fires when sound_id>=2;
## it fires at the cumulative duration of the keyframes before it, and its own
## duration is the gap to the next. The walker window is strict `<`: BOTH phase and
## for_each fire indices 0..max_keyframe-1, and index==max_keyframe is a terminator
## the runtime never fires (FFT sound guard `kf < max`; disasm 0x801A478C phase /
## 0x801A3408 for-each — NOT the wider palette/screen `< max-1`, NOT array-end).
## The live-drag reproject's frame axis must be the BUILD's axis.
##
## `rebuild_kind_lanes` recomputes `max_frame`, and it did so with its own copy of build's loop
## — a copy that omitted the sound-TERMINATOR skip (ADR-0085 Amendment 2026-08-10). The terminator sits at
## its true frame, often a long silent tail past the last real event, so on a real effect the
## first motion of any drag stretched the ruler by a factor of six and crushed every lane in the
## score into a corner (measured on E317: 112 → 691). Both builders now share
## `_content_max_frame`; this pins that they agree, on a fixture whose terminator is deliberately
## far past its content — the whole shape of the fault in twelve keyframes.
func _test_a_reproject_keeps_the_builds_frame_axis() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"duration_frames": 600, "sound_id": 5},   # kf0 fires at local 0
				{"duration_frames": 0, "sound_id": 7}]},   # kf1 == max → terminator, 600 frames out
		],
	}
	var score := Model.build(ed)
	var term: Dictionary = Model.find_span(score, "sound:for_each:0#1")
	_assert_eq(int(term.get("start", -1)), 608,
		"fixture: the terminator really is far past the content (abs 608)")
	_assert_eq(int(score["max_frame"]), 8,
		"build's axis is CONTENT — the distant terminator does not drive it")
	for kind in ["sound", "palette"]:
		# "sound" rebuilds the very lane the terminator lives on; "palette" rebuilds nothing here
		# and only recomputes the axis. Both went wrong the same way, so both are pinned.
		_assert_eq(int(Model.rebuild_kind_lanes(score, ed, kind).get("max_frame", -1)),
			int(score["max_frame"]),
			"a %s reproject keeps the build's axis, terminator and all" % kind)


func _test_sound_trigger_lanes() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 2, "keyframes": [
				{"duration_frames": 6, "sound_id": 0},   # kf0 skip (sid<2)
				{"duration_frames": 4, "sound_id": 5},   # kf1 fires (index 1 < max 2)
				{"duration_frames": 0, "sound_id": 7}]},  # kf2 == max_keyframe → terminator, dropped
		],
	}
	var score := Model.build(ed)
	var lane := _lane(score, "sound:for_each:0")
	_assert_true(not lane.is_empty(), "sound builds a per-channel lane")
	_assert_eq(lane["kind"], "sound", "lane kind is sound")
	_assert_eq(lane["label"], "Sound 0", "sound lane names its channel")
	# ADR-0085 "every event is accessible via a timeline handle": both live-window events
	# project a handle (kf0 a SILENT event, kf1 an audible fire), plus the terminator end-cap.
	_assert_eq(lane["spans"].size(), 3, "two event handles (kf0 silent, kf1 fire) + one terminator")
	var kf0: Dictionary = lane["spans"][0]
	_assert_eq(str(kf0["role"]), "event", "kf0 is a live event handle even though it's silent")
	_assert_eq(kf0["start"], 8, "kf0 fires at the for_each offset (8) + local (0)")
	_assert_eq(kf0["ghost_frames"], 0, "a silent event carries no tail — the tell of no sound")
	_assert_eq(kf0["fields"]["sound_id"], 0, "kf0 is the skip sentinel (sound_id 0)")
	var kf1: Dictionary = lane["spans"][1]
	_assert_eq(str(kf1["role"]), "event", "kf1 is a live event handle")
	_assert_eq(kf1["authored_start"], 6, "kf1 fires after kf0's 6-frame duration")
	_assert_eq(kf1["start"], 14, "absolute = for_each offset (8) + local (6)")
	# A trigger is an INSTANT (ADR-0085): its span has zero on-timeline length — the
	# old duration-as-width was the misleading gap-to-next, not the sound's length.
	_assert_eq(kf1["authored_end"], 6, "trigger is an instant: authored_end == authored_start")
	_assert_eq(kf1["end"], 14, "trigger is an instant: end == start")
	_assert_eq(kf1["ghost_frames"], 0, "no ghost map → no projected length")
	_assert_eq(kf1["fields"]["sound_id"], 5, "inspector field carries the sound id")
	var term: Dictionary = Model.find_span(score, "sound:for_each:0#2")
	_assert_true(not term.is_empty(), "the index==max_keyframe terminator IS drawn (inert end-cap)")
	_assert_eq(str(term["role"]), "terminator", "index==max_keyframe is the terminator, not a fire")
	_assert_eq(term["start"], 18, "terminator at true frame = offset 8 + last-event fire local (10)")
	_assert_eq(term["ghost_frames"], 0, "terminator carries no tail")

	# phase1/phase2 use the same strict `<` window: indices 0..max_keyframe-1 are events;
	# index==max_keyframe is the terminator end-cap, and anything past it is padding (dropped).
	ed.sound = {
		"phase1": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"duration_frames": 5, "sound_id": 3},   # kf0 event (index 0 < max 1)
				{"duration_frames": 5, "sound_id": 4},   # kf1 == max_keyframe → terminator
				{"duration_frames": 5, "sound_id": 9}]},  # kf2 past max → padding, dropped
		],
	}
	var p1 := _lane(Model.build(ed), "sound:phase1:0")
	_assert_eq(p1["spans"].size(), 2, "phase1: one event (index 0) + the terminator (index 1); padding dropped")
	_assert_eq(p1["spans"][0]["keyframe_index"], 0, "the lone event is index 0 (= max_keyframe-1)")
	_assert_eq(str(p1["spans"][0]["role"]), "event", "index 0 is the event handle")
	_assert_eq(p1["spans"][1]["keyframe_index"], 1, "the terminator is index 1 (= max_keyframe)")
	_assert_eq(str(p1["spans"][1]["role"]), "terminator", "index 1 is the terminator end-cap")


## When the studio supplies a {sound_id → ghost frames} map (from the FEDS bank),
## a trigger span carries that read-only projected length as `ghost_frames`. The
## span itself stays an instant; the phase SECTION must stretch to cover the ghost
## bar's extent so it isn't drawn outside its band (ADR-0085 ghost bar).
func _test_sound_ghost_bar_and_section_extent() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"duration_frames": 4, "sound_id": 5},   # fires at for_each offset 8
				{"duration_frames": 0, "sound_id": 7}]},  # terminator, dropped
		],
	}
	var score := Model.build(ed, {5: 40})   # sound_id 5 projects to a 40-frame ghost
	var lane := _lane(score, "sound:for_each:0")
	var span: Dictionary = lane["spans"][0]
	_assert_eq(span["start"], 8, "trigger fires at the for_each offset")
	_assert_eq(span["end"], 8, "trigger is still an instant even with a ghost")
	_assert_eq(span["ghost_frames"], 40, "ghost length comes from the supplied map")
	var section := _phase(score, "for_each")
	_assert_eq(section["end"], 48, "section covers the ghost extent (start 8 + 40 frames)")


## ADR-0085 TIER-2: the studio pre-projects the effect's SoundContainers (mode / emitted
## ids / pairs / used-by, via SoundContainerModel) and threads that list into the score
## under "sound_containers", so the container-kind projector reads it without touching the
## resolver/FEDS bank — the same seam ghost/energy use. Omitted → an empty list, not absent.
func _test_container_views_thread_into_score() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	var views := [{"index": 0, "mode_name": "TRIPLE_CYCLE"}, {"index": 1, "mode_name": "DIRECT_A"}]
	var score := Model.build(ed, {}, {}, views)
	_assert_eq(score.get("sound_containers", null), views,
		"the supplied container views thread verbatim into the score")
	var bare := Model.build(ed)
	_assert_eq(bare.get("sound_containers", null), [],
		"no views supplied → an empty list under sound_containers")


## ADR-0085 anchor: the authoring-only `anchor_offset` on a sound keyframe surfaces on
## the span (for the timeline's hit marker) and in the inspector `fields` (default 0
## when the authored JSON omits it). It is metadata only — `start` (the fire frame)
## must NOT move, so the on-disk trigger stays a plain early fire (byte-faithful).
func _test_sound_anchor_offset_surfaces_on_span() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"duration_frames": 4, "sound_id": 5, "anchor_offset": 7},
				{"duration_frames": 0, "sound_id": 7}]},   # terminator, dropped
		],
	}
	var span: Dictionary = _lane(Model.build(ed, {5: 40}), "sound:for_each:0")["spans"][0]
	_assert_eq(span["anchor_offset"], 7, "authored anchor_offset surfaces on the span")
	_assert_eq(span["fields"]["anchor_offset"], 7, "anchor_offset surfaces as an inspector field")
	_assert_eq(span["start"], 8, "anchor_offset does NOT move the fire frame")
	# Default 0 when the authored JSON omits the key (the common case).
	ed.sound["for_each"][0]["keyframes"][0] = {"duration_frames": 4, "sound_id": 5}
	var span0: Dictionary = _lane(Model.build(ed, {5: 40}), "sound:for_each:0")["spans"][0]
	_assert_eq(span0["anchor_offset"], 0, "a keyframe without anchor_offset defaults to 0")
	_assert_eq(span0["fields"]["anchor_offset"], 0, "the inspector field defaults to 0")
## ADR-0085 climax cue: the studio hands build() an {sound_id → energy envelope} map
## (the audio sibling of the ghost map). A firing trigger carries its sound's 0..1
## envelope on the span as `energy`, for the timeline to paint inside the ghost bar.
## Absent from the map (or no map at all) → an empty envelope, never a crash.
func _test_sound_energy_envelope_surfaces_on_span() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"duration_frames": 4, "sound_id": 5},
				{"duration_frames": 0, "sound_id": 7}]},   # terminator, dropped
		],
	}
	var env := PackedFloat32Array([0.0, 0.5, 1.0, 0.5])
	var span: Dictionary = _lane(Model.build(ed, {5: 40}, {5: env}), "sound:for_each:0")["spans"][0]
	_assert_true(span["energy"] is PackedFloat32Array, "energy surfaces as a float sample array")
	_assert_eq(span["energy"].size(), 4, "the supplied envelope reaches the span intact")
	_assert_true(absf(span["energy"][2] - 1.0) < 1e-6, "the envelope's peak sample survives")
	# No energy map supplied → an empty envelope (ghost bar draws no curve).
	var span_bare: Dictionary = _lane(Model.build(ed, {5: 40}), "sound:for_each:0")["spans"][0]
	_assert_eq(span_bare["energy"].size(), 0, "no energy map → an empty envelope, no crash")


## `duration_frames` width that accumulates within the phase (unlike particle
## keyframes, whose `time` is already cumulative); only enabled (TINT) keyframes
## are drawn, FADE keyframes advance the cursor but stay invisible.
func _test_screen_color_lane() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.screen = ExMateriaEffects.ScreenData.from_json({
		"for_each": {"context": "for_each", "max_keyframe": 3, "keyframes": [
			# kf0 Gradient (bit-7 clear), kf1 Blend (bit-7 set) — both in the runtime's
			# played window (0..max_keyframe-2 = 0,1). kf2/kf3 are trailing terminators.
			{"index": 0, "duration_frames": 12, "mode": "FADE",
				"start_r": 10, "start_g": 20, "start_b": 30,
				"end_r": 40, "end_g": 50, "end_b": 60},
			{"index": 1, "duration_frames": 20, "mode": "TINT", "blend_mode": 1,
				"start_r": 255, "start_g": 0, "start_b": 0},
			{"index": 2, "duration_frames": 8, "mode": "FADE"},
			{"index": 3, "duration_frames": 8, "mode": "FADE"},
		]},
	})
	var score := Model.build(ed)
	var lane := _lane(score, "screen:for_each")
	_assert_true(not lane.is_empty(), "screen builds a lane")
	_assert_eq(lane["kind"], "screen", "lane kind is screen")
	_assert_eq(lane["label"], "Screen", "screen lane is labelled 'Screen'")
	# Faithful window = what ScreenSubsystem actually plays (0..max_keyframe-2). The
	# fully-tiled lane draws BOTH the Gradient and the Blend; the trailing terminators
	# do NOT draw (no phantom Gradient tweens — ADR-0071).
	_assert_eq(lane["spans"].size(), 2, "both the Gradient and Blend tweens draw; terminators don't")
	var grad: Dictionary = lane["spans"][0]
	var blend: Dictionary = lane["spans"][1]
	_assert_eq(grad["fields"].get("screen_kind", ""), "Grad", "kf0 is drawn as a Gradient tween")
	_assert_eq(grad["authored_start"], 0, "Gradient starts the phase")
	_assert_eq(grad["authored_end"], 12, "Gradient owns its duration")
	# kf1 (Blend, dur 20) → [12,32) local, absolute for_each offset (8) + 12 = 20
	_assert_eq(blend["fields"].get("screen_kind", ""), "Blend", "kf1 is drawn as a Blend tween")
	_assert_eq(blend["authored_start"], 12, "Blend starts after the Gradient's duration")
	_assert_eq(blend["authored_end"], 32, "Blend ends a duration_frames later")
	_assert_eq(blend["start"], 20, "absolute = for_each offset (8) + local (12)")
	_assert_eq(blend["color"], Color(1, 0, 0, 1), "Blend drawn in its produced color")
	_assert_eq(blend["fields"]["blend_mode"], 1, "inspector fields carry the blend mode")


## Palette lanes: one per (phase, channel_name) that animates. Like screen, widths accumulate
## over duration_frames. EVERY played keyframe gets a span — including DISABLED ones (ADR-0087
## fully-tiled lane): a disabled null tween still occupies its tile. Fifth amendment: it is
## verdict-inert (`fields.spacer`) but `enabled` false, so it stays DRAWN (dimmed + hatched) and
## selectable to re-enable — "muted, not gone" (an enabled inert spacer, by contrast, is hidden).
## The enabled span is hued by its rgb; the gutter label names the channel.
func _test_palette_color_lanes() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.palette = ExMateriaEffects.PaletteData.from_json({
		"for_each": {
			"caster": {"context": "for_each", "channel_name": "caster", "max_keyframe": 3,
				"keyframes": [
					{"index": 0, "duration_frames": 6, "enabled": false, "rgb": [0, 0, 0]},
					{"index": 1, "duration_frames": 10, "enabled": true, "blend_mode": 3,
						"rgb": [0, 255, 0]},
				]},
		},
	})
	var score := Model.build(ed)
	var lane := _lane(score, "palette:for_each:caster")
	_assert_true(not lane.is_empty(), "palette builds a per-channel lane")
	_assert_eq(lane["kind"], "palette", "lane kind is palette")
	_assert_eq(lane["label"], "Caster", "palette channel name becomes a plain-words label")
	_assert_eq(lane["spans"].size(), 2, "BOTH the disabled and enabled keyframes draw (fully-tiled)")

	var disabled: Dictionary = lane["spans"][0]
	_assert_eq(disabled["authored_start"], 0, "the disabled tween occupies its own tile [0,6)")
	_assert_eq(disabled["authored_end"], 6, "…its tile ends at its duration")
	_assert_eq(bool(disabled["fields"]["enabled"]), false, "…and is marked disabled")
	_assert_true(bool(disabled["fields"].get("spacer", false)), "…verdict-inert (a disabled null tween)")
	_assert_true(not TimelineClass.is_hidden_spacer(disabled, ""), "…but DRAWN, not hidden (deliberately disabled — ADR-0087 decs. 23-28)")
	_assert_eq(str(disabled["fields"].get("border", "solid")), "solid", "…border SOLID: dashed = Gradient only")

	var enabled: Dictionary = lane["spans"][1]
	_assert_eq(enabled["authored_start"], 6, "the enabled span starts after the disabled kf's duration")
	_assert_eq(enabled["start"], 14, "absolute = for_each offset (8) + local (6)")
	_assert_eq(bool(enabled["fields"]["enabled"]), true, "…and is marked enabled")
	_assert_eq(enabled["color"], Color(0, 1, 0, 1), "the enabled span is hued by the keyframe rgb")
	_assert_eq(enabled["fields"]["blend_mode"], 3, "inspector fields carry blend mode")


## A span's identity is its lane_id#keyframe_index — independent of position — so
## editing a keyframe's authored time moves the span on the axis WITHOUT changing
## its id (an editor can track selection across an edit). find_span looks it up.
func _test_identity_is_stable_across_authored_edit() -> void:
	var specs := [{"context": "for_each", "channel_index": 0, "max_keyframe": 1,
		"keyframes": [{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1}]}]
	var before := Model.build(_effect_with_timeline(8, 64, specs))
	specs[0]["keyframes"][1]["time"] = 25  # author drags the keyframe later
	var after := Model.build(_effect_with_timeline(8, 64, specs))
	var s_before := Model.find_span(before, "particle:for_each:0#1")
	var s_after := Model.find_span(after, "particle:for_each:0#1")
	_assert_true(not s_before.is_empty(), "find_span resolves a span by id")
	_assert_eq(s_before["authored_end"], 10, "before-edit end")
	_assert_eq(s_after["authored_end"], 25, "same id now owns the moved interval")
	_assert_eq(s_after["id"], s_before["id"], "identity survives the authored-time edit")


## Grounding: the projection holds on a real parsed effect (E000), not just
## synthetic fixtures — every span is well-formed (start < end ≤ max_frame) and
## carries the invariants the view relies on.
func _test_real_effect_projects_cleanly() -> void:
	var dir := "res://assets/effects/E000"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		print("[SKIP] E000 assets absent — regen with tools/bootstrap_assets.sh")
		return
	var ed = ExMateriaEffects.EffectData.load_from_directory(dir)
	var score := Model.build(ed)
	_assert_true(score["lanes"].size() > 0, "a real effect yields at least one lane")
	var well_formed := true
	for lane in score["lanes"]:
		for span in lane["spans"]:
			# Instants are zero-width by design (start == end at the frame): a camera_compiled
			# point marker, AND every sound span (a trigger fires at an instant, ADR-0085).
			# Every other span is a real interval. The sound TERMINATOR legitimately sits past
			# max_frame (decision 7 excludes its silent tail from the axis), so it's exempt from
			# the ≤max_frame bound; events and intervals must still fit.
			var is_instant: bool = span.get("marker", false) or span.get("kind", "") == "sound"
			var is_terminator: bool = str(span.get("role", "")) == "terminator"
			if is_instant:
				if span["start"] != span["end"]:
					well_formed = false
				elif not is_terminator and span["end"] > score["max_frame"]:
					well_formed = false
			elif span["start"] >= span["end"] or span["end"] > score["max_frame"]:
				well_formed = false
			if span["lane_id"] != lane["id"]:
				well_formed = false
	_assert_true(well_formed, "every span is well-formed (interval start<end, marker start==end) ≤max_frame and back-references its lane")


## The inspector renders `inspector_header(span)` (the archetype-independent context
## rows) above the projector's `inspector_sections`. For a particle span the detail
## leads with the Event section — what the span OWNS (emitter id + action flags) —
## with the emitter's grouped sections a level deeper (ADR-0071).
func _test_inspector_header_and_particle_event_section() -> void:
	var ed = _effect_with_timeline(8, 64, [
		{"context": "for_each", "channel_index": 2, "max_keyframe": 1, "keyframes": [
			{"time": 0, "emitter_id": 0},
			{"time": 10, "emitter_id": 3, "action_flags": 16}]},
	])
	var span: Dictionary = _lane(Model.build(ed), "particle:for_each:2")["spans"][0]
	var header := _rows_by_label(Model.span_header_rows(span))
	_assert_eq(header["Kind"], "Particle", "header names the lane kind")
	_assert_eq(header["Phase"], "For-each", "header names the phase in plain words")
	_assert_eq(header["Frames"], "8–18", "header shows the absolute frame range")
	var secs := Model.span_sections(span, ed)
	_assert_eq(secs[0].get("title", ""), "Event", "particle detail leads with the Event section")
	_assert_eq(_section_value(secs, "Event", "Emitter"), "index 2 (id 3)", "Event names the referenced emitter")
	_assert_eq(_section_value(secs, "Event", "Action flags"), "0x10", "Event carries the action flags as hex")


## Palette spans project one titled section with their inline fields (channel, rgb,
## enabled, blend, duration) — no shared entity, so it's the single-section case.
func _test_inspector_sections_palette() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.palette = ExMateriaEffects.PaletteData.from_json({
		"for_each": {"target": {"context": "for_each", "channel_name": "target",
			"max_keyframe": 2, "keyframes": [
				{"index": 0, "duration_frames": 10, "enabled": true, "blend_mode": 2,
					"rgb": [255, 128, 0]}]}},
	})
	var span: Dictionary = _lane(Model.build(ed), "palette:for_each:target")["spans"][0]
	_assert_eq(_rows_by_label(Model.span_header_rows(span))["Kind"], "Map/unit tint", "palette kind label")
	var secs := Model.span_sections(span, ed)
	_assert_eq(secs[0].get("title", ""), "Palette tint", "palette projects one titled section")
	_assert_eq(_section_value(secs, "Palette tint", "Channel"), "target", "palette channel")
	# Palette is now EDITABLE (#266): the tint projects as an absolute-colour picker cell
	# (gradient_color) rather than a read-only "(r, g, b)" string; Blend mode is a value enum.
	_assert_eq(_section_editor(secs, "Palette tint", "Tint"), "target_color", "palette tint editable result-picker (ADR-0087)")
	_assert_eq(_section_value(secs, "Palette tint", "Blend mode"), "2", "palette blend mode")
	_assert_eq(_section_value(secs, "Palette tint", "Duration"), "10", "palette duration")


## Find a projected field's display value by (section title, field name).
func _section_value(sections: Array, title: String, field_name: String) -> String:
	for s in sections:
		if s.get("title", "") == title:
			for fld in s.get("fields", []):
				if fld.get("name", "") == field_name:
					# A `link` field (ADR-0073) shows its `label` in the value cell.
					return str(fld.get("value", fld.get("label", "")))
	return "<missing:%s/%s>" % [title, field_name]


## Find a projected field's `editor` kind by (section title, field name) — for the
## editable cells (#266 palette, #255 screen) that carry no display `value` string.
func _section_editor(sections: Array, title: String, field_name: String) -> String:
	for s in sections:
		if s.get("title", "") == title:
			for fld in s.get("fields", []):
				if fld.get("name", "") == field_name:
					return str(fld.get("editor", ""))
	return "<missing:%s/%s>" % [title, field_name]


## The inspector navigates keyframe(span) → emitter record → params grouped by
## WHAT THEY CHARACTERIZE. emitter_view projects one emitter into the four ordered
## characterizing accordion groups — the seam that replaces the old flat "jump
## straight to curves" shortcut (curve now hangs off a specific param, never the
## keyframe) — plus the trailing "Advanced (raw)" section (ADR-0089 slice 3:
## real-but-opaque callback params + reserved const bytes).
func _test_emitter_view_groups_ordered() -> void:
	var ed = ExMateriaEffects.EffectData.new()
	ed.emitters.append(EffectEmitter.new())
	var titles := []
	for g in Model.emitter_view(ed, 0):
		titles.append(g["title"])
	_assert_eq(titles,
		["Emitter", "Particle · born-with", "Particle · over-life", "Config", "Advanced (raw)"],
		"emitter view has the four characterizing groups + Advanced (raw), in tree order")


func _test_emitter_view_out_of_range() -> void:
	var ed = ExMateriaEffects.EffectData.new()
	_assert_eq(Model.emitter_view(ed, 0), [], "no emitter at index → empty view")
	_assert_eq(Model.emitter_view(ed, -1), [], "negative index → empty view")


## `_test_emitter_view_param_shapes_and_gating` lived here and is DELETED (#465).
##
## It asserted a projection `emitter_view` no longer produces. Every scalar param used to
## be ONE row carrying `{shape: "vec3"|"range"|"int"|"curve_only", from, to, curve_index,
## enabled}`. Today a param group projects THREE editable rows — `Position · at start`,
## `· at end`, `· curve` — each `shape: "edit"` with typed `cells` and a `group` stamp
## carrying the summary, inertness and relevance verdict. Not a rename: the row model
## changed, and this fixture's `em.position_start` Vector3 no longer even reaches the
## projection, which reads the raw record fields.
##
## The `Position` lookup therefore threw, and a GDScript runtime error aborts the enclosing
## function — so the 14 assertions after it never ran, under a green verdict.
##
## The modern guard is `EmitterProjectorTest`, 24 functions over exactly this surface:
## `_test_vec3_group_projects_two_axis_edit_rows`, `_test_range_group_never_collapses_min_max`,
## `_test_color_curves_and_homing_blend_editable`, `_test_group_stamp_carries_summary_and_inert`
## and `_test_group_stamps_carry_relevance_verdicts` cover what this claimed, against the
## shape production actually has.


## Acceleration/drag carry vec3 min & max (a vec3_range); Config entries are bare
## constants (no from/to/curve); the opaque callback_params bag is NOT surfaced.
func _test_emitter_view_vec3_range_and_config() -> void:
	var ed = ExMateriaEffects.EffectData.new()
	var em = EffectEmitter.new()
	em.acceleration_min_start = Vector3(0, 1, 2)
	em.acceleration_max_start = Vector3(0, 0, 0)
	em.acceleration_min_end = Vector3(0, 3, 4)
	em.acceleration_max_end = Vector3(0, 0, 0)
	em.curves = {"acceleration": 2}
	em.anim_index = 7
	em.child_emitter_on_death = 5
	em.child_emitter_mid_life = -1
	# OUTWARD_UNIT_ORIENTED velocity mode (both flags) + align_to_velocity sprite rotation.
	em.flags = {"velocity_inward": true, "align_to_facing": true, "align_to_velocity": true}
	ed.emitters.append(em)
	var by_name := _params_by_name(Model.emitter_view(ed, 0))

	# Velocity mode is derived from the flag pair and shown as a const so the mode is
	# visible while diagnosing mis-oriented particles.
	var vmode: Dictionary = by_name["Velocity mode"]
	_assert_eq(vmode["shape"], "const", "velocity mode is a const row")
	_assert_eq(vmode["value"], "OUTWARD_UNIT_ORIENTED", "both flags → OUTWARD_UNIT_ORIENTED")
	# The old `Align to velocity` lookup threw here and aborted the rest of this function.
	# The flag row is now an EDITABLE enum named `Sprite faces its velocity` — and it is
	# decoded from the raw `motion_type_flag` bits, not from the `em.flags` dictionary this
	# fixture sets, so the old "surfaced as yes" claim has no fixture to stand on. The enum
	# decomposition is guarded by EmitterProjectorTest, against a record that actually
	# carries the bits. What survives here is that the row EXISTS under its current name.
	_assert_true(by_name.has("Sprite faces its velocity"),
		"the align-to-velocity flag is projected, under its current semantic name")
	_assert_true(not by_name.has("Align to velocity"),
		"…and not under the retired one")

	# Acceleration is no longer one `vec3_range` row: a vec3-range group projects four
	# value rows plus a curve row. Guarded in detail by
	# EmitterProjectorTest._test_range_group_never_collapses_min_max.
	for suffix in [" · at start (min)", " · at start (max)", " · at end (min)",
			" · at end (max)", " · curve"]:
		_assert_true(by_name.has("Acceleration" + suffix),
			"acceleration projects a row for%s" % suffix)

	# Config entries are editable rows now, not read-only constants; `Anim index` is
	# `Animation set`. The value still reaches the row.
	var anim: Dictionary = by_name["Animation set"]
	_assert_eq(anim["shape"], "edit", "config entries are editable rows")
	_assert_eq(anim["value"], 7, "animation set value")
	# A spawned child is a LINK to that emitter's bare view (ADR-0073), not a dead-end int.
	var child_death: Dictionary = by_name["Child on death"]
	_assert_eq(child_death["shape"], "link", "child-on-death is a link, not a const")
	_assert_eq(child_death["label"], "emitter 5", "child-on-death link labels the child emitter")
	_assert_eq(int(child_death["target"]["ref"]["index"]), 5, "child-on-death link targets emitter 5")
	_assert_eq(by_name["Child mid-life"]["shape"], "const", "a 'none' child stays a const")
	_assert_eq(by_name["Child mid-life"]["value"], "none", "child ref -1 → none")

	_assert_true(not by_name.has("Callback params"), "opaque callback bytes are omitted (door #2)")


## ADR-0075: a LIVE child edge (a real child index AND the authored spawn flag on) marks
## its link toggleable with a `{parent_index, edge}` payload — the inspector renders the
## suppression checkbox only there. An authored-OFF edge (index set, flag off) is a plain
## link with NO toggle (off-only, live-edges-only / D1). The model stays stateless: it
## marks toggleability, it never carries the suppressed state.
func _test_emitter_view_child_edge_toggle() -> void:
	var ed = ExMateriaEffects.EffectData.new()
	var em = EffectEmitter.new()
	em.child_emitter_on_death = 5
	em.child_emitter_mid_life = 6
	# Death edge authored ON (live), mid-life edge authored OFF.
	em.flags = {"child_death_enabled": true, "child_midlife_enabled": false}
	ed.emitters.append(em)
	var by_name := _params_by_name(Model.emitter_view(ed, 0))

	var death: Dictionary = by_name["Child on death"]
	_assert_eq(death["shape"], "link", "a live child edge is still a link")
	_assert_true(death.has("toggle"), "a live child edge carries a toggle payload")
	_assert_eq(int(death["toggle"]["parent_index"]), 0, "toggle keys on the PARENT emitter index")
	_assert_eq(str(death["toggle"]["edge"]), "death", "on-death edge tagged 'death'")

	var mid: Dictionary = by_name["Child mid-life"]
	_assert_eq(mid["shape"], "link", "an authored-off edge is still a plain link")
	_assert_true(not mid.has("toggle"), "an authored-off edge carries NO toggle (D1: live edges only)")

	# A 'none' child (index -1) never toggles regardless of flag.
	var em2 = EffectEmitter.new()
	em2.child_emitter_on_death = -1
	em2.flags = {"child_death_enabled": true}
	ed.emitters.append(em2)
	var by_name2 := _params_by_name(Model.emitter_view(ed, 1))
	_assert_eq(by_name2["Child on death"]["shape"], "const", "a 'none' child stays a const")
	_assert_true(not by_name2["Child on death"].has("toggle"), "a 'none' child carries no toggle")


## Grounding: emitter_view holds on a real parsed effect (E004, rich curve data),
## not just synthetic fixtures — the four characterizing groups + Advanced (raw),
## every CHARACTERIZING row well-formed (Advanced rows are int/const with tooltips —
## their shape is pinned by EmitterProjectorTest).
func _test_emitter_view_real_effect() -> void:
	var dir := "res://assets/effects/E004"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		print("[SKIP] E004 assets absent — regen with tools/bootstrap_assets.sh")
		return
	var ed = ExMateriaEffects.EffectData.load_from_directory(dir)
	var view := Model.emitter_view(ed, 0)
	_assert_eq(view.size(), 5, "four characterizing groups + Advanced (raw) on a real emitter")
	var ok := true
	for g in view:
		if str(g["title"]) == "Advanced (raw)":
			continue
		for p in g["params"]:
			if not (p.has("name") and p.has("shape")):
				ok = false
			# ADR-0089 #291 row model: an "edit" row must carry an editing surface —
			# a cells list (grouped or ungrouped multi-cell rows), a single field_ref
			# (int/enum Config rows), or per-component field_refs. Const rows need none.
			if str(p.get("shape", "")) == "edit" \
					and not (p.has("cells") or p.has("field_ref") or p.has("field_refs")):
				ok = false
	_assert_true(ok, "every characterizing row is well-formed (name+shape; edit rows carry an editing surface)")


func _params_by_name(view: Array) -> Dictionary:
	var out := {}
	for g in view:
		for p in g["params"]:
			out[p["name"]] = p
	return out


## keyframe_address builds the copy-to-clipboard string a user pastes to reference
## one keyframe unambiguously: effect · lane_id · kf#index · absolute frames, then
## a kind-specific payload. Every token maps back to code (lane_id → phase+kind+
## channel; kf# → index into the channel's keyframes).
func _test_keyframe_address_particle() -> void:
	var ed = _effect_with_timeline(8, 64, [
		{"context": "for_each", "channel_index": 2, "max_keyframe": 1, "keyframes": [
			{"time": 0, "emitter_id": 0},
			{"time": 10, "emitter_id": 3, "action_flags": 16}]},
	])
	var span: Dictionary = _lane(Model.build(ed), "particle:for_each:2")["spans"][0]
	_assert_eq(Model.keyframe_address("E317", span),
		"E317 · particle:for_each:2 · kf#1 · f8–18 · emitter idx2 (id3) · flags 0x10",
		"particle address is effect·lane·kf·frames·emitter·flags")


func _test_keyframe_address_palette() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.palette = ExMateriaEffects.PaletteData.from_json({
		"for_each": {"target": {"context": "for_each", "channel_name": "target",
			"max_keyframe": 2, "keyframes": [
				{"index": 0, "duration_frames": 10, "enabled": true, "blend_mode": 2,
					"rgb": [255, 128, 0]}]}},
	})
	var span: Dictionary = _lane(Model.build(ed), "palette:for_each:target")["spans"][0]
	_assert_eq(Model.keyframe_address("E042", span),
		"E042 · palette:for_each:target · kf#0 · f8–18 · rgb(255,128,0) · blend 2",
		"palette address carries the tint channel, rgb, and blend")


## A sound trigger's address carries `sid` and — per ADR-0085 conformance — the `gap`
## token (the space to the NEXT trigger), NOT `dur`: a trigger is an instant with no
## on-timeline length, so its `duration_frames` is the gap, not a duration.
func _test_keyframe_address_sound() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"duration_frames": 12, "sound_id": 4},
				{"duration_frames": 0, "sound_id": 0}]},
		],
	}
	var span: Dictionary = _lane(Model.build(ed), "sound:for_each:0")["spans"][0]
	_assert_eq(Model.keyframe_address("E317", span),
		"E317 · sound:for_each:0 · kf#0 · f8–8 · sid 4 · gap 12",
		"sound address carries sid and the GAP to the next trigger (not dur)")


## CAMERA addresses by ORDINAL, not the raw storage slot (ADR-0086 dec. 5, #286): `lower` re-packs
## the flat array on every split/merge, so the raw index goes stale — which is the whole point
## of the ordinal. The address string must print the SAME token the span id carries, or
## reconstructing `<lane_id>#<N>` from a pasted address silently resolves to a DIFFERENT event.
## The raw slot stays visible in the payload as provenance (it is what the compiled lane and a
## hex dump show), just never as the address.
##
## Fixture mirrors real E317 for_each angle: raw slots 2/3/6 are the 1st/2nd/3rd angle events,
## so ordinal 1 lives at raw slot 3 — the exact off-by-two that made "kf#3" ambiguous.
func _test_keyframe_address_camera() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.camera = ExMateriaEffects.CameraData.from_json({
		"for_each": {"max_keyframe": 6, "keyframes": [
			{"index": 0, "end_frame": 0, "channel_mask": 0, "interpolation": "UNKNOWN_0x0000"},
			{"index": 1, "end_frame": 0, "channel_mask": 0, "interpolation": "UNKNOWN_0x0000"},
			{"index": 2, "end_frame": 10, "channel_mask": 1, "source_mode": "CASTER",
				"interpolation": "COSINE_A", "angle": [0, 0, 0]},
			{"index": 3, "end_frame": 19, "channel_mask": 1, "source_mode": "MAP",
				"interpolation": "COSINE_A", "angle": [0, 0, 0]},
			{"index": 4, "end_frame": 0, "channel_mask": 0, "interpolation": "UNKNOWN_0x0000"},
			{"index": 5, "end_frame": 0, "channel_mask": 0, "interpolation": "UNKNOWN_0x0000"},
			{"index": 6, "end_frame": 41, "channel_mask": 1, "source_mode": "TARGET",
				"interpolation": "COSINE_A", "angle": [0, 0, 0]}]},
	})
	var spans: Array = _lane(Model.build(ed), "camera:for_each:angle")["spans"]
	_assert_eq(Model.keyframe_address("E317", spans[1]),
		"E317 · camera:for_each:angle · kf#1 · f18–27 · angle · MAP · COSINE_A · slot 3",
		"camera address prints the ORDINAL (kf#1), with the raw slot as payload provenance")
	# The address token and the span id must agree — the id IS how a pasted address resolves.
	for span in spans:
		_assert_eq("%s#%d" % [span["lane_id"], _address_index(Model.keyframe_address("E", span))],
			String(span["id"]),
			"the address's kf# reconstructs the span id exactly (%s)" % span["id"])


## The integer in the `kf#N` token of an address string.
func _address_index(addr: String) -> int:
	for tok in addr.split(" · "):
		if tok.begins_with("kf#"):
			return int(tok.substr(3))
	return -1


func _test_keyframe_address_empty_span() -> void:
	_assert_eq(Model.keyframe_address("E317", {}), "", "an empty span yields no address")


## Palette lanes must use the RUNTIME's keyframe window — PaletteSubsystem applies
## only indices 0..max_keyframe-2; the rest are terminators/padding it never plays.
## An enabled keyframe past that window (E077's [600,5400] tint) must NOT become a
## span, or the Studio shows phantom keyframes. (Screen lanes keep their own wider
## 0..max_keyframe window — see _screen_lanes.)
func _test_palette_window_drops_padding_keyframes() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.palette = ExMateriaEffects.PaletteData.from_json({
		"for_each": {"target": {"context": "for_each", "channel_name": "target",
			"max_keyframe": 2, "keyframes": [
				{"index": 0, "duration_frames": 8, "enabled": true, "blend_mode": 4,
					"rgb": [10, 20, 30]},
				{"index": 1, "duration_frames": 592, "enabled": false, "rgb": [0, 0, 0]},
				{"index": 2, "duration_frames": 4800, "enabled": true, "blend_mode": 5,
					"rgb": [128, 128, 128]}]}},
	})
	var lane := _lane(Model.build(ed), "palette:for_each:target")
	_assert_eq(lane["spans"].size(), 1, "only the in-window enabled keyframe draws (padding dropped)")
	_assert_eq(lane["spans"][0]["keyframe_index"], 0, "the drawn span is index 0, not the [600,5400] padding kf")


## Grounding: sound lanes use the RUNTIME's strict-`<` window for BOTH phase and
## for_each (FFT sound guard `kf < max`, disasm 0x801A478C / 0x801A3408) — fire
## 0..max_keyframe-1, and index==max_keyframe is a TERMINATOR. Under ADR-0085 "every
## event is accessible via a timeline handle" the terminator is now an INERT end-cap
## span (role "terminator"), NOT a fire: no EVENT handle sits at/after max_keyframe, the
## terminator carries no ghost tail, and it is EXCLUDED from max_frame so E006's f608 slot
## never balloons the axis to 1208. E006's for_each sound channels each author a sid>=2
## keyframe exactly AT index==max_keyframe (ch0/ch1 kf#3, ch2 kf#1) — that audible-looking
## slot is still just the end-cap (particle-freed ~f130 long before f608). Sister to
## _test_palette_window_drops_padding_keyframes.
func _test_sound_window_drops_terminal_keyframe() -> void:
	var dir := "res://assets/effects/E006"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		print("[SKIP] E006 assets absent — regen with tools/bootstrap_assets.sh")
		return
	var ed = ExMateriaEffects.EffectData.load_from_directory(dir)
	var score := Model.build(ed)
	# Invariant: every sound EVENT handle is strictly inside its channel's window; the
	# ONLY span at index==max_keyframe is the terminator end-cap.
	var events_in_window := true
	for lane in score["lanes"]:
		if lane["kind"] != "sound":
			continue
		var mk := _sound_channel_max(ed, lane["phase"], lane["channel_index"])
		for span in lane["spans"]:
			var is_term: bool = str(span.get("role", "event")) == "terminator"
			if is_term:
				if span["keyframe_index"] != mk:
					events_in_window = false
			elif span["keyframe_index"] >= mk:
				events_in_window = false
	_assert_true(events_in_window, "no sound EVENT at/after index==max_keyframe; the terminator sits AT it")
	# The three terminal slots are now INERT end-caps (role terminator), never fires, and
	# carry no tail; the real cast trigger stays an event.
	for tid in ["sound:for_each:0#3", "sound:for_each:1#3", "sound:for_each:2#1"]:
		var term := Model.find_span(score, tid)
		_assert_true(not term.is_empty(), "%s projects the terminator end-cap" % tid)
		_assert_eq(str(term.get("role", "")), "terminator", "%s is the inert terminator, not a fire" % tid)
		_assert_eq(int(term.get("ghost_frames", 0)), 0, "%s carries no tail" % tid)
	var cast := Model.find_span(score, "sound:for_each:0#1")
	_assert_true(not cast.is_empty(), "the real cast trigger (kf#1) survives")
	_assert_eq(str(cast.get("role", "")), "event", "the cast trigger is a live event handle")
	# The terminator is excluded from max_frame (ADR-0085 Amendment 2026-08-10): the axis collapses
	# off the f608/f1208 tail to the particle-bounded content (~154).
	_assert_true(score["max_frame"] < 200, "max_frame excludes the terminator tail → real content (~154)")


func _sound_channel_max(ed, phase: String, channel_index: int) -> int:
	var channels = ed.sound.get(phase, [])
	if channels is Array:
		for ch in channels:
			if ch is Dictionary and int(ch.get("channel_index", 0)) == channel_index:
				return int(ch.get("max_keyframe", 0))
	return 0


func _rows_by_label(rows: Array) -> Dictionary:
	var out := {}
	for r in rows:
		out[r["label"]] = r["value"]
	return out


# --- fixtures -------------------------------------------------------------

## A minimal EffectData carrying only a timeline built from channel specs. Each
## keyframe spec is a partial dict (time/emitter_id/action_flags); TimelineData
## fills the rest.
## The two PACING curves project as a single GLOBAL (non-phase) "Time scale" lane carrying two
## bands (#270, ADR-0093): Phase-1 pacing over [0, phase1_duration) and For-each pacing over the
## for-each region. Each band carries its played-window samples (the frames its phase samples)
## and the enable flag; the byte-preserved tail past the window is not carried. Fixture: p1d=8, a
## for-each particle lane spanning [8,28) so the for-each region is 20 frames wide.
func _test_pacing_lane_two_bands() -> void:
	var ed = _effect_with_timeline(8, 64, [
		{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
			{"time": 0, "emitter_id": 0}, {"time": 20, "emitter_id": 1}]},
	])
	ed.time_scale = _time_scale_block(true, false)
	var score := Model.build(ed)
	var lane: Dictionary = score.get("pacing_lane", {})
	_assert_true(not lane.is_empty(), "build carries a global pacing lane when time_scale is present")
	_assert_eq(lane.get("kind", ""), "time_scale", "the pacing lane is a time_scale-kind lane")
	_assert_true(bool(lane.get("global", false)), "the pacing lane is global (no phase)")
	var bands: Array = lane.get("bands", [])
	_assert_eq(bands.size(), 2, "one lane carries two tiled bands")
	var b1: Dictionary = bands[0]
	_assert_eq(b1.get("field", ""), "outer_phases", "first band is the Phase-1 curve")
	_assert_eq(b1.get("start", -1), 0, "Phase-1 band starts at frame 0")
	_assert_eq(b1.get("end", -1), 8, "Phase-1 band ends at phase1_duration")
	_assert_eq((b1.get("pacing", []) as Array).size(), 8, "Phase-1 band carries its played window (p1d frames)")
	_assert_eq((b1.get("pacing", []) as Array)[0], 2, "the played window is the head of outer_phases")
	var b2: Dictionary = bands[1]
	_assert_eq(b2.get("field", ""), "for_each", "second band is the For-each curve")
	_assert_eq(b2.get("start", -1), 8, "For-each band starts at the for-each offset")
	_assert_eq(b2.get("end", -1), 28, "For-each band ends at the for-each region far edge")
	_assert_eq((b2.get("pacing", []) as Array).size(), 20, "For-each band carries its 20-frame region window")


func _test_pacing_lane_absent_without_time_scale() -> void:
	var ed = _effect_with_timeline(8, 64, [
		{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
			{"time": 0, "emitter_id": 0}, {"time": 20, "emitter_id": 1}]},
	])
	# no ed.time_scale set → an effect with no Time-Scale section
	var score := Model.build(ed)
	_assert_true((score.get("pacing_lane", {}) as Dictionary).is_empty(),
		"an effect with no time_scale carries no pacing lane")


func _test_pacing_lane_enabled_flags() -> void:
	var ed = _effect_with_timeline(8, 64, [
		{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
			{"time": 0, "emitter_id": 0}, {"time": 20, "emitter_id": 1}]},
	])
	ed.time_scale = _time_scale_block(true, false)
	var bands: Array = (Model.build(ed).get("pacing_lane", {}) as Dictionary).get("bands", [])
	_assert_true(bool(bands[0].get("enabled", false)), "Phase-1 band reports its enable bit (pattern1 on)")
	_assert_true(not bool(bands[1].get("enabled", true)), "For-each band reports its enable bit (pattern2 off)")


## The band HEIGHT is slowness above normal: (value-2)/8 clamped 0..1, so a normal-speed 2 reads
## flat and the maximum-slow 10 fills the lane. Expected literals are the spec, not recomputed.
func _test_pacing_norm_height_map() -> void:
	_assert_true(abs(Model.pacing_norm(2) - 0.0) < 0.0001, "value 2 (normal) maps to a flat 0.0")
	_assert_true(abs(Model.pacing_norm(10) - 1.0) < 0.0001, "value 10 (max slow) fills the lane")
	_assert_true(abs(Model.pacing_norm(6) - 0.5) < 0.0001, "value 6 is half height")
	_assert_true(abs(Model.pacing_norm(1) - 0.0) < 0.0001, "below-normal clamps to 0.0")
	_assert_true(abs(Model.pacing_norm(14) - 1.0) < 0.0001, "above-max clamps to 1.0")


## The pacing PLAYBACK factor at an absolute frame — BASE_PACING(2)/value, gated by the enable
## flags — mirrors EffectTimeline._update_time_scale so the studio transport slows exactly like the
## game clock. Phase-1 frames key outer_phases; for-each frames (>= phase1_duration) key for_each.
## A disabled pattern, an empty block, or value 2 all yield 1.0 (normal speed).
func _test_pacing_factor_at() -> void:
	var p1d := 8
	var ts := {
		"flags": {"time_scale_pattern1": true, "time_scale_pattern2": false},
		"outer_phases": [2, 4, 8, 2, 2, 2, 2, 2],   # phase-1 window
		"for_each": [10, 10, 10],                    # for-each window (after p1d)
	}
	_assert_true(abs(Model.pacing_factor_at(ts, p1d, 0) - 1.0) < 0.0001, "value 2 at frame 0 -> 1.0x")
	_assert_true(abs(Model.pacing_factor_at(ts, p1d, 1) - 0.5) < 0.0001, "value 4 -> 0.5x (2/4)")
	_assert_true(abs(Model.pacing_factor_at(ts, p1d, 2) - 0.25) < 0.0001, "value 8 -> 0.25x (2/8)")
	# For-each pattern is OFF, so a for-each frame stays 1.0x even though for_each=10.
	_assert_true(abs(Model.pacing_factor_at(ts, p1d, 9) - 1.0) < 0.0001,
		"for-each frame with pattern2 OFF stays 1.0x (gated)")
	# Turn pattern2 on: the for-each frame now slows.
	ts["flags"]["time_scale_pattern2"] = true
	_assert_true(abs(Model.pacing_factor_at(ts, p1d, 9) - 0.2) < 0.0001, "value 10 for-each -> 0.2x (2/10)")
	# An empty block, or pattern1 off, is always normal speed.
	_assert_true(abs(Model.pacing_factor_at({}, p1d, 2) - 1.0) < 0.0001, "empty time_scale -> 1.0x")
	ts["flags"]["time_scale_pattern1"] = false
	_assert_true(abs(Model.pacing_factor_at(ts, p1d, 2) - 1.0) < 0.0001, "pattern1 off -> 1.0x at a phase-1 frame")


## A 600-int time_scale block with the two enables set as asked; curves are a deterministic
## 2..10 ramp head so the played-window slice is checkable.
func _time_scale_block(pattern1: bool, pattern2: bool) -> Dictionary:
	var outer: Array = []
	var foreach: Array = []
	for i in range(600):
		outer.append(2 + (i % 9))
		foreach.append(2 + ((i + 3) % 9))
	return {
		"flags": {"time_scale_pattern1": pattern1, "time_scale_pattern2": pattern2},
		"outer_phases": outer, "for_each": foreach,
	}


func _effect_with_timeline(phase1_duration: int, phase2_delay: int, channels: Array):
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": phase1_duration, "phase2_delay": phase2_delay},
		"particle_channels": channels,
	})
	return ed


func _lane(score: Dictionary, lane_id: String) -> Dictionary:
	for lane in score["lanes"]:
		if lane["id"] == lane_id:
			return lane
	return {}


func _phase(score: Dictionary, name: String) -> Dictionary:
	for p in score["phases"]:
		if p["name"] == name:
			return p
	return {}


## ADR-0089 Drag preview: rebuild_kind_lanes refreshes ONLY the named kind's lanes from the
## live effect_data and REUSES every other kind's lanes by reference — the sim-free geometry
## reproject a live drag needs, so a particle drag never re-runs the ~400ms palette/screen
## spacer oracle. A moved particle keyframe shows in the refreshed particle lane while the
## palette lane stays the SAME object (untouched, not rebuilt).
func _test_rebuild_kind_lanes_refreshes_one_kind_reuses_others() -> void:
	var specs := [{"context": "for_each", "channel_index": 0, "max_keyframe": 1,
		"keyframes": [{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1}]}]
	var ed = _effect_with_timeline(8, 64, specs)
	ed.palette = ExMateriaEffects.PaletteData.from_json({
		"for_each": {"caster": {"context": "for_each", "channel_name": "caster", "max_keyframe": 2,
			"keyframes": [{"index": 0, "duration_frames": 10, "enabled": true, "blend_mode": 3,
				"rgb": [0, 255, 0]}]}},
	})
	var old_score := Model.build(ed)
	var palette_lane_before := _lane(old_score, "palette:for_each:caster")
	var particle_end_before: int = Model.find_span(old_score, "particle:for_each:0#1")["authored_end"]
	_assert_eq(particle_end_before, 10, "the particle span ends at 10 before the move")

	# The drag mutated ONLY the particle keyframe's time — palette bytes are untouched.
	ed.timeline.get_channels("for_each")[0].keyframes[1].time = 25
	var new_score := Model.rebuild_kind_lanes(old_score, ed, "particle")

	_assert_eq(Model.find_span(new_score, "particle:for_each:0#1")["authored_end"], 25,
		"the particle lane was rebuilt — the moved keyframe shows")
	var palette_lane_after := _lane(new_score, "palette:for_each:caster")
	_assert_true(palette_lane_after == palette_lane_before,
		"the palette lane is the SAME object — reused, not rebuilt (the 400ms cost skipped)")


## rebuild_kind_lanes preserves lane ORDER (kinds are contiguous groups the timeline draws
## top-to-bottom) and recomputes the cheap max_frame + phase sections so a grow extends the ruler.
func _test_rebuild_kind_lanes_preserves_order_and_recomputes_extent() -> void:
	var specs := [{"context": "for_each", "channel_index": 0, "max_keyframe": 1,
		"keyframes": [{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1}]}]
	var ed = _effect_with_timeline(8, 64, specs)
	ed.palette = ExMateriaEffects.PaletteData.from_json({
		"for_each": {"caster": {"context": "for_each", "channel_name": "caster", "max_keyframe": 2,
			"keyframes": [{"index": 0, "duration_frames": 10, "enabled": true, "blend_mode": 3,
				"rgb": [0, 255, 0]}]}},
	})
	var old_score := Model.build(ed)
	var order_before: Array = []
	for lane in old_score["lanes"]:
		order_before.append(String(lane["id"]))
	var max_before: int = old_score["max_frame"]

	# Grow the particle span past the old extent.
	ed.timeline.get_channels("for_each")[0].keyframes[1].time = 200
	var new_score := Model.rebuild_kind_lanes(old_score, ed, "particle")

	var order_after: Array = []
	for lane in new_score["lanes"]:
		order_after.append(String(lane["id"]))
	_assert_eq(order_after, order_before, "lane order is preserved (kinds stay in their rows)")
	_assert_true(new_score["max_frame"] > max_before, "max_frame grew with the extended particle span")
	_assert_true(new_score["max_frame"] >= 208, "…covering abs 208 (offset 8 + local 200)")


## CAMERA is the one builder that emits TWO lane kinds — the three authoring sub-channel lanes
## AND the read-only `camera_compiled` storage view. A kind-scoped reproject that drops only the
## lanes matching the REQUESTED kind therefore keeps the stale compiled lanes AND appends fresh
## ones: the lane list grows by one compiled row per phase on every call. On a live camera Move
## that is once per mouse motion, which is how it was reported — "it creates a second, third etc
## camera compiled lane, each frame changes". The splice must drop every group the builder is
## about to re-emit, not just the one that was asked for.
func _test_rebuild_kind_lanes_drops_every_group_its_builder_re_emits() -> void:
	var ed = _effect_with_timeline(8, 64, [])
	ed.camera = ExMateriaEffects.CameraData.from_json({
		"phase1": {"max_keyframe": 1, "keyframes": [
			{"index": 0, "end_frame": 10, "channel_mask": 1, "source_mode": "CASTER",
				"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 64, 0]},
			{"index": 1, "end_frame": 30, "channel_mask": 1, "source_mode": "MAP",
				"interpolation": "LINEAR", "command_raw": 0x8C1, "angle": [0, 0, 0]}]},
	})
	var score := Model.build(ed)
	var order_before: Array = []
	for lane in score["lanes"]:
		order_before.append(String(lane["id"]))
	_assert_true(order_before.has("camera_compiled:phase1"),
		"the fixture really does project a compiled lane")

	# Three reprojects — a live drag does one per motion.
	for i in range(3):
		score = Model.rebuild_kind_lanes(score, ed, "camera")
	var order_after: Array = []
	for lane in score["lanes"]:
		order_after.append(String(lane["id"]))
	_assert_eq(order_after, order_before,
		"repeated camera reprojects leave the lane list identical — no compiled lane accumulates")
	_assert_eq(_count(order_after, "camera_compiled:phase1"), 1,
		"…exactly ONE compiled lane per phase, however many motions the drag emitted")


func _count(items: Array, needle: String) -> int:
	var n: int = 0
	for it in items:
		if String(it) == needle:
			n += 1
	return n


# --- asserts --------------------------------------------------------------

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
