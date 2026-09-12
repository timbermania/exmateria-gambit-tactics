extends Node
## ACCEPTANCE (headful, real E019 = Fire 4, #270 / ADR-0093): the whole "Time scale band on the
## timeline → click → pop-up painter → paint → preview responds / enable greys the band" path,
## end to end through the live studio.
##   1. E019's two pacing curves project as a global "Time scale" lane; the timeline lays out its
##      two band hit-rects at the bottom.
##   2. Clicking the Phase-1 band (span id "time_scale#outer_phases") opens the pop-up painter
##      bound to that 600-int curve — it does NOT set a span inspection root.
##   3. Painting the played window to normal speed (all 2s) commits through the live
##      EffectEditSession onto data.time_scale.outer_phases AND re-renders the band; the REAL
##      EffectTimeline sim then runs at 1.0x through phase 1 (was slowed before) — the honest
##      "the paint reached the preview" proof.
##   4. Toggling the Phase-1 enable off clears flags bit5 + syncs time_scale.flags, and the
##      rebuilt band reports enabled=false (greyed, still drawn).
## Skips when E019 assets are absent (gitignored/ROM-derived). A screenshot is written.
## Run: godot --path . --quit-after 400 res://tests/EffectStudioTimeScaleAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectTimelineClass = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")
const SHOT := "user://effect_time_scale_e019.png"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioTimeScaleAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioTimeScaleAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioTimeScaleAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	_assert_true(dir != "", "E019 in the effect catalogue")
	page._load_effect(dir)
	await _frames(40)

	var data = page._effect_data
	_assert_true(data != null and not data.time_scale.is_empty(), "E019 has a parsed time_scale block")
	if data == null or data.time_scale.is_empty():
		return

	# --- (1) The pacing lane projects; the timeline lays out two band rects. ---
	var lane: Dictionary = page._timeline._score.get("pacing_lane", {})
	_assert_true(not lane.is_empty(), "the score carries a global Time scale lane")
	page._timeline.rebuild_layout()
	_assert_eq(page._timeline.pacing_band_rects().size(), 2, "the timeline lays out both pacing bands")

	# --- (2) Clicking the Phase-1 band opens the pop-up painter (not a span root). ---
	var nav_before: int = page._nav.size()
	page._on_span_selected("time_scale#outer_phases")
	await _frames(6)
	_assert_true(page._painter_panel.visible, "clicking the band opens the pop-up painter")
	_assert_eq(str(page._painter_pacing_field), "outer_phases", "the painter binds the Phase-1 curve")
	_assert_true(String(page._painter_title.text).findn("Phase 1 pacing") >= 0,
		"the pop-up is titled 'Phase 1 pacing' (not the arming-pattern name)")
	_assert_eq(page._nav.size(), nav_before, "opening the pacing painter does NOT push a span inspection root")

	# --- (3) Measure phase-1 sim speed BEFORE the paint (E019 slows below 1.0x). ---
	var p1: int = int(data.timeline.phase1_duration)
	var min_before := _min_phase1_factor(data.time_scale.duplicate(true), p1)
	_assert_true(min_before < 1.0,
		"E019's Phase-1 pacing slows the preview below 1.0x before editing (min %.3f)" % min_before)

	# Paint the whole curve to normal speed (2) and commit through the live session.
	var flat: Array = []
	for i in range(600):
		flat.append(2)
	page._commit_pacing_edit("outer_phases", flat)
	await _frames(20)
	_assert_eq(data.time_scale["outer_phases"], flat,
		"painting commits the whole 600-int curve onto the live data (byte-authentic)")
	# The band re-rendered off the rebuilt score.
	var band := _band(page, "time_scale#outer_phases")
	_assert_true(not band.is_empty() and int((band.get("pacing", []) as Array)[0]) == 2,
		"the on-timeline band re-renders from the edited curve")

	# --- (4) The preview no longer slows: factor stays 1.0x through phase 1. ---
	var min_after := _min_phase1_factor(data.time_scale, p1)
	_assert_eq(min_after, 1.0,
		"after painting normal speed the sim runs at 1.0x through phase 1 (preview changed): %.3f" % min_after)

	# --- (5) Toggling the enable off clears bit5 + greys the band. ---
	page._toggle_pacing_enable("outer_phases", false)
	await _frames(15)
	_assert_true(not bool(data.flags.get("time_scale_pattern1", true)),
		"toggling the enable clears flags bit5")
	_assert_true(not bool(data.time_scale.get("flags", {}).get("time_scale_pattern1", true)),
		"the time_scale.flags mirror is synced off")
	var band_off := _band(page, "time_scale#outer_phases")
	_assert_true(not bool(band_off.get("enabled", true)),
		"the rebuilt band reports enabled=false (greyed, still drawn)")

	# --- (6) Playback DWELLS on slow frames — the transport honors the pacing curve (#270). ---
	# Drive the REAL page transport over equal simulated time with a slow curve vs a normal one;
	# the slow curve must advance fewer frames. Before the fix the page transport ignored pacing
	# entirely (it advanced integer frames per tick regardless of the authored slowdown).
	page._toggle_pacing_enable("outer_phases", true)  # re-arm pattern1 (step 5 turned it off)
	await _frames(3)
	var slow_curve: Array = []
	for i in range(600):
		slow_curve.append(6)  # 2/6 ≈ 0.333x
	page._commit_pacing_edit("outer_phases", slow_curve)
	var adv_slow := _advance_over(page, 1.5)
	var normal_curve: Array = []
	for i in range(600):
		normal_curve.append(2)  # 1.0x
	page._commit_pacing_edit("outer_phases", normal_curve)
	var adv_norm := _advance_over(page, 1.5)
	_assert_true(adv_slow > 0 and adv_norm > 0,
		"the transport advances under both curves (slow=%d norm=%d)" % [adv_slow, adv_norm])
	_assert_true(adv_slow < adv_norm,
		"a slow pacing curve dwells: fewer frames advance over equal time than normal (%d < %d)"
		% [adv_slow, adv_norm])
	print("  transport advance over 1.5s: slow(6)=%d  normal(2)=%d frames" % [adv_slow, adv_norm])

	# Visual record for the eyeball.
	await _frames(5)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(SHOT)
	_assert_true(err == OK, "screenshot written to %s" % ProjectSettings.globalize_path(SHOT))
	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT))
	print("  phase-1 min factor: before=%.3f  after=%.3f" % [min_before, min_after])


## Drive the page's real transport for `seconds` of simulated time (deterministic 60 Hz ticks,
## the node's own _process disabled so only these ticks advance it) and return how many frames the
## playhead advanced from 0. Same code path a live Play uses — _process → _transport_step → _seek.
func _advance_over(page, seconds: float) -> int:
	page.set_process(false)
	page._seek(0)
	page._playing = true
	page._arm_transport()
	var start: int = page._timeline.get_playhead()
	var t := 0.0
	var dt := 1.0 / 60.0
	while t < seconds and page._playing:
		page._process(dt)
		t += dt
	page._playing = false
	return page._timeline.get_playhead() - start


func _band(page, id: String) -> Dictionary:
	for b in (page._timeline._score.get("pacing_lane", {}) as Dictionary).get("bands", []):
		if String(b.get("id", "")) == id:
			return b
	return {}


## Drive the REAL EffectTimeline sim over phase 1 and return the minimum time-scale factor
## observed — < 1.0 means the pacing curve slowed the preview. (Copied from the flags acceptance.)
func _min_phase1_factor(time_scale_data: Dictionary, phase1_duration: int) -> float:
	var tl = EffectTimelineClass.new()
	tl.setup(phase1_duration, phase1_duration + 10000, time_scale_data)
	tl.set_subsystems([])
	tl.start()
	var min_factor := 1.0
	for i in range(maxi(1, phase1_duration)):
		tl._advance_one_frame()
		min_factor = minf(min_factor, tl._time_scale_factor)
	return min_factor


# --- helpers ---------------------------------------------------------------
func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
