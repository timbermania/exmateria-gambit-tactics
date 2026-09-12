extends Node
## ACCEPTANCE (headful, real E317 — the staggered-spawn baseline) for the span-anchored
## emitter-elapsed playhead marker (ADR-0089 amendment). The correctness anchor is NOT an
## eyeball (repo rule: static-rooted, dynamic-validated): fold to a scrubbed playhead P and
## assert the marker's curve index == the index the SIM actually samples the emitter-elapsed
## curve at for a particle spawned this frame — pinning the marker to the real read site and
## resolving the authored-vs-compiled start offset EMPIRICALLY rather than by guessing.
##
## THE READ SITE. An emitter-elapsed curve is looked up at the timeline's per-channel
## `spawn_counter` (ActiveEmitter.spawn_particles_for_timeline sets `elapsed_frames =
## spawn_counter` for the lookup, then RESTORES it — so the persistent elapsed_frames stays
## 0 and is NOT the clock; spawn_counter is). `PhaseBlock._process_channel` spawns with
## spawn_counter THEN post-increments it, so after folding to frame P the channel state holds
## `spawn_counter = (P − span.start) + 1` — i.e. the particle spawned at P used index
## `spawn_counter − 1`. That is exactly what the marker must point at: marker.elapsed ==
## spawn_counter − 1, marker.index == (spawn_counter − 1) % 160. (Probed 2026-08-12: at
## P=span.start the state reads spawn_counter=1 → the spawn used 0, and the marker reads 0.)
##
## Unit guards prove the pure mapper / views / threading in isolation; this proves the WIRING
## end-to-end on a real, emitter-dense effect through the REAL page → host → EffectInstance.
##
## Run: <GODOT> --path . --quit-after 400 res://tests/EffectStudioCurvePlayheadMarkerAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 317
const BASE_BIN := "res://../project-assets/fft-extract/EFFECT/E317.BIN"
const PhaseClass = ExMateriaEffects.EffectPhase

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_marker_index_matches_the_sim_read_site()

	print("\n=== EffectStudioCurvePlayheadMarkerAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioCurvePlayheadMarkerAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioCurvePlayheadMarkerAcceptanceTest")
		get_tree().quit(0)


func _test_marker_index_matches_the_sim_read_site() -> void:
	var base_abs := ProjectSettings.globalize_path(BASE_BIN).simplify_path()
	if not FileAccess.file_exists(base_abs):
		print("[SKIP] E317.BIN not available (ROM extract absent) — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	scn.studio_select_effect(EFFECT_ID)
	await _frames(20)

	var page = scn._studio_page
	_assert_true(page != null, "the Studio page is mounted")
	if page == null:
		return

	# Find a live case: a particle span, a playhead P comfortably inside its firing, where the
	# span's keyframe is the one currently spawning on its channel (so spawn_counter is THIS
	# firing's clock).
	var found := await _find_live_case(page, scn)
	_assert_true(not found.is_empty(), "a particle span with a live spawning firing exists")
	if found.is_empty():
		return

	var spawn_counter: int = int(found["spawn_counter"])
	var sim_index: int = (spawn_counter - 1) % 160   # the index the particle spawned at P used
	var marker: Dictionary = page._marker_for_target()
	_assert_true(bool(marker.get("present", false)), "the selected span resolves a present marker")
	_assert_eq(str(marker.get("state", "")), "in", "the marker is inside the firing")
	# THE INVARIANT: the marker sits exactly where the sim samples the emitter-elapsed curve.
	_assert_eq(int(marker.get("index", -1)), sim_index,
		"marker index == sim curve read-site (P=%d, span_start=%d, spawn_counter=%d)"
			% [int(found["playhead"]), int(found["span_start"]), spawn_counter])
	# The elapsed coordinate itself is pinned to the sim's clock (the strong form; the start
	# offset is resolved empirically, not guessed).
	_assert_eq(int(marker.get("elapsed", -1)), spawn_counter - 1,
		"marker elapsed == sim spawn_counter − 1 (start offset resolved empirically)")


# --- helpers ---------------------------------------------------------------

## Scan particle spans for one whose keyframe is actively spawning at a scrubbed inside-frame.
## Returns {span_id, playhead, span_start, spawn_counter} or {} if none found.
func _find_live_case(page, scn) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if String(lane.get("kind", "")) != "particle":
			continue
		var channel_index: int = int(lane.get("channel_index", -1))
		for span in lane.get("spans", []):
			if bool(span.get("disabled", false)):
				continue
			var start: int = int(span.get("start", 0))
			var end: int = int(span.get("end", 0))
			var keyframe_index: int = int(span.get("keyframe_index", -1))
			var phase: String = String(span.get("phase", ""))
			if end - start < 5:
				continue
			var span_id := String(span.get("id", ""))
			page._on_span_selected(span_id)
			# A frame comfortably inside (avoid the last 2 frames — the keyframe period ends one
			# frame before `end` because of the post-decremented duration).
			for k in [3, 4, 2, 5, 6]:
				var p: int = start + k
				if p >= end - 1:
					continue
				page._seek(p)
				await _frames(2)
				var sc := _spawn_counter(scn, phase, channel_index, keyframe_index)
				if sc >= 1:
					return {"span_id": span_id, "playhead": p, "span_start": start, "spawn_counter": sc}
	return {}


## The live spawn_counter for `channel_index` on `phase`, but only when the actively-spawning
## keyframe is `keyframe_index` (the selected span's firing). -1 when not matching.
func _spawn_counter(scn, phase: String, channel_index: int, keyframe_index: int) -> int:
	var block = _block(scn, phase)
	if block == null:
		return -1
	for st in block.channel_states:
		if int(st.channel.channel_index) == channel_index and int(st.current_keyframe) == keyframe_index:
			return int(st.spawn_counter)
	return -1


func _block(scn, phase: String):
	var m = scn._current_effect.manager
	match phase:
		PhaseClass.PHASE1: return m.phase1_block
		PhaseClass.PHASE2: return m.phase2_block
		_: return m.for_each_block


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
