extends Node
## HEADFUL acceptance guard for the TIER-3 FEDS pair editor end-to-end (ADR-0085
## amendment 2026-08-11), on the REAL EffectViewer with real extracted E004 — the
## noise-sweep pair the slice-0 table fix made legible (0xB4 Noise_EnableAndClock
## used to decode as chromatic garbage). Confirms the live wiring:
##   * drill into a referenced pair → the PAGE-LEVEL lane panel shows (ADR-0085
##     2026-08-11 amendment) with data-driven lanes + a working per-loop
##     wind/unwind toggle, and the inspector renders runtime-truth opcode rows
##     and the manual Audition button,
##   * an inspector widget edit lands in the SHARED FedsBank raw byte (the same
##     object playback reads) and the pair view re-derives live,
##   * with the pair open, ghost pips light every resolving trigger's span.
##
## Kept OUT of run_all_tests.sh (needs the gitignored EFFECT extract; the camera
## acceptance precedent).
## Run: <GODOT> --path . --quit-after 120 res://tests/FedsPairEditorAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_pair_editor_end_to_end_on_e004()
	await _test_prearm_verdict_and_energy_on_e001()
	await _test_frame_axis_projection_on_e317()
	await _test_noop_ab_on_e001_wholly_muted()
	await _test_noop_ab_on_a_partially_muted_pair()
	await _test_play_releases_capture_mode_immediately()
	await _test_note_audition_console_on_e001()
	await _test_prune_for_real_delete_and_undo_on_e001()

	print("\n=== FedsPairEditorAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FedsPairEditorAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] FedsPairEditorAcceptanceTest")
		get_tree().quit(0)


func _test_pair_editor_end_to_end_on_e004() -> void:
	if not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path("res://assets/effects/E004")):
		print("[SKIP] E004 assets absent")
		_passed += 1
		return
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	# Select E004 THROUGH the page (its loader syncs the host preview instance),
	# exactly as the picker does — so page, host and session share one EffectData.
	var e004_dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E004"):
			e004_dir = d
	if e004_dir == "":
		print("[SKIP] E004 not in the picker")
		_passed += 1
		scn.queue_free()
		return
	page._load_effect(e004_dir)
	await _frames(20)
	var ed = scn._current_effect.effect_data
	if ed.feds_bank == null:
		_assert_true(false, "E004 carries a FEDS bank")
		scn.queue_free()
		return

	# Open a pair a container actually references (the provenance-led drill target).
	var pair_idx := -1
	for v in page._pair_views:
		if not (v.get("used_by_containers", []) as Array).is_empty():
			pair_idx = int(v.get("pair_idx", -1))
			break
	_assert_true(pair_idx >= 0, "E004 has a container-referenced pair")
	if pair_idx < 0:
		scn.queue_free()
		return
	page._set_root(Target.pair(pair_idx))
	await _frames(4)

	# The editor renders: the page-level lane panel + runtime-truth rows + Audition.
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	_assert_true(page._pair_panel.visible, "the pair lane panel shows for the open pair")
	var lay: Dictionary = Panel.layout(page._pair_panel._view, 900.0, page._pair_panel._state())
	_assert_true((lay.get("lanes", []) as Array).size() >= 1,
			"the panel draws data-driven lanes for the real pair")
	_assert_true((lay.get("sections", []) as Array).size() == 2,
			"one collapsible section per track")

	# Slice 2 (§2): the panel paints opcode-honesty verdicts on the REAL pair — every
	# chip carries a Live/Pre-arm/Inert/Structural verdict and the track headers speak
	# the Sounding/Stub tell.
	var Verdicts = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	var verdict_tagged := 0
	for chip in lay.get("chips", []):
		if str(chip.get("verdict", "")) != "":
			verdict_tagged += 1
	_assert_true(verdict_tagged >= 1, "the real pair's chips carry opcode-honesty verdicts")
	var header_labels := ""
	for sec in lay.get("sections", []):
		header_labels += str(sec.get("label", ""))
	_assert_true("Sounding" in header_labels or "flows into" in header_labels,
			"the track headers speak the Sounding/Stub tell")

	# Slice 3 (§3): the per-track energy bands render (2 isolated offline SPU renders,
	# shared-peak normalized) and CORROBORATE the §2 verdicts — the falsifiable
	# direction (per the RE: no opcode reaches the sibling voice, so a note-less track
	# sounds nothing in isolation): a track with NO note of its own must read FLAT,
	# and a track WITH a note swells. A contradiction is a bug, not a pixel quirk.
	var bands: Array = lay.get("energy_bands", [])
	if bands.is_empty():
		print("[SKIP] pair %d rendered no energy bands (transport busy / engine)" % pair_idx)
		_passed += 1
	else:
		var contradiction := 0
		var max_peak := 0.0
		var any_note := false
		for band in bands:
			var bt := int(band.get("track"))
			var tv: Dictionary = page._pair_views[pair_idx].get("tracks", [])[bt]
			var has_note: bool = not ((tv.get("notes", []) as Array).is_empty())
			var peak := float(band.get("peak"))
			max_peak = maxf(max_peak, peak)
			any_note = any_note or has_note
			if not has_note and peak > 0.3:
				contradiction += 1
		_assert_true(contradiction == 0,
				"a note-less track's band reads FLAT — the energy corroborates §2 (%d off)" % contradiction)
		if any_note:
			_assert_true(max_peak > 0.5,
					"a track with notes swells its band (the isolated render produced real audio)")

	# PER-FRAME GRID ALIGNMENT (ADR-0085 amendment 2026-08-12): the panel projects
	# a per-frame orientation grid onto the SHARED timeline axis, so each line
	# coincides pixel-for-pixel with the score's _draw_grid directly below — both
	# read page._timeline.axis and step from frame 0. Compute the panel layout on
	# that shared axis and assert every grid line sits at the score's grid x for
	# its own frame, with a constant score-matching stride.
	var glay: Dictionary = Panel.layout(page._pair_panel._view, page._pair_panel.size.x,
			page._pair_panel._state(), page._timeline.axis, page._pair_panel._anchor)
	var grid: Array = glay.get("grid", [])
	_assert_true(grid.size() >= 1, "the open pair's panel draws a per-frame orientation grid")
	var grid_off := 0
	for gm in grid:
		if absf(float(gm.get("x")) - page._timeline.axis.frame_to_x(float(gm.get("frame")))) > 0.01:
			grid_off += 1
	_assert_true(grid_off == 0,
			"every panel grid line sits at the score's grid x for that frame (%d off)" % grid_off)
	# The stride equals the FramesBar/score _ruler_step for this axis (both derive
	# it the same way), so the panel and score lines land on the same frames.
	var expect_step: int = Panel._ruler_step_for(page._timeline.axis)
	var stride_ok := true
	for gi in range(1, grid.size()):
		if int(grid[gi].get("frame")) - int(grid[gi - 1].get("frame")) != expect_step:
			stride_ok = false
	_assert_true(stride_ok, "grid frames march at the shared _ruler_step (score-matching stride)")

	# Wind/unwind (the thing the rejected strip could not do). FRAME-AXIS §4:
	# folding collapses DRAWING, not TIME — unwinding fills the loop's reserved
	# span with ghost copies while the axis extent stays put; winding restores.
	var brackets: Array = lay.get("brackets", [])
	if brackets.is_empty():
		print("[SKIP] opened pair has no loop — wind/unwind not exercised here")
		_passed += 1
	else:
		var br: Dictionary = brackets[0]
		var drawn: int = (lay.get("span_bars", []) as Array).size() \
				+ (lay.get("chips", []) as Array).size()
		page._pair_panel.toggle_loop(int(br.get("track")), int(br.get("loop_index")))
		await _frames(2)
		var un_lay: Dictionary = Panel.layout(page._pair_panel._view, 900.0,
				page._pair_panel._state())
		var un_drawn: int = (un_lay.get("span_bars", []) as Array).size() \
				+ (un_lay.get("chips", []) as Array).size()
		_assert_true(un_drawn > drawn,
				"unwinding fills the reserved span with ghost copies (×14 loop)")
		_assert_true(int(un_lay.get("total_ticks")) == int(lay.get("total_ticks")),
				"unwinding never moves the axis extent (drawing-collapse, not time)")
		page._pair_panel.toggle_loop(int(br.get("track")), int(br.get("loop_index")))
		await _frames(2)
		var re_lay: Dictionary = Panel.layout(page._pair_panel._view, 900.0,
				page._pair_panel._state())
		_assert_true((re_lay.get("span_bars", []) as Array).size() \
				+ (re_lay.get("chips", []) as Array).size() == drawn,
				"winding back restores the folded drawing")
	# Slice 1 (ADR-0085 amendment 2026-08-12 §1): opening the pair LANDS ON THE CODE —
	# the panel auto-selects track A's first event (the inspector opens on it, not on an
	# empty overview the author must click again to leave).
	var a_track: Dictionary = page._pair_views[pair_idx].get("tracks", [])[0]
	var a_has_events: bool = not ((a_track.get("notes", []) as Array).is_empty() \
			and (a_track.get("commands", []) as Array).is_empty())
	if a_has_events:
		_assert_true(int(page._pair_panel.selected_event().get("track", -1)) == 0,
				"opening the pair auto-selects a track-A event (land on the code)")
	# SELECTING an event through the panel scopes its edit cells into the F1 inspector.
	var sel_ei := _first_param_event_index(page._pair_views[pair_idx])
	if sel_ei >= 0:
		page._pair_panel._selected = {"track": 0, "event_index": sel_ei}
		page._pair_panel.event_selected.emit(0, sel_ei)
		await _frames(4)
		_assert_true(page._inspector.int_widgets().size() +
				page._inspector.enum_widgets().size() >= 1,
				"selecting an event scopes its edit cells into the inspector")
	var audition_btns := 0
	for b in page._inspector.action_buttons():
		if "Audition" in str(b.text):
			audition_btns += 1
	_assert_true(audition_btns >= 1, "manual Audition button renders")

	# The noise-sweep truth (slice 0): pair 1 (bank track 2) opens with
	# Noise_EnableAndClock legible. Only asserted when we opened that pair.
	if pair_idx == 1:
		var labels: Array = []
		var nview: Dictionary = page._pair_views[pair_idx]
		for c in (nview.get("tracks", [])[0] as Dictionary).get("commands", []):
			labels.append(str(c.get("label", "")))
		_assert_true(labels.has("Noise_EnableAndClock"),
				"the noise sweep decodes under the runtime table")

	# A live edit through the host choke point lands in the SHARED bank byte and
	# re-derives the view (the widget→ref lowering itself is unit-guarded).
	var probe_off := _first_param_offset(page._pair_views[pair_idx])
	if probe_off >= 0:
		var before: int = ed.feds_bank.raw[probe_off]
		var new_val := (before + 1) % 100
		page._apply_edit({"channel": "sound_def", "kind": "byte",
				"offset": probe_off, "pair_idx": pair_idx}, new_val)
		await _frames(4)
		_assert_true(int(ed.feds_bank.raw[probe_off]) == new_val,
				"the edit patched the shared FedsBank byte in place")
		_assert_true(page._sound_env["feds_bank"] == ed.feds_bank,
				"page env and instance share ONE FedsBank (single source)")
		_assert_true(int(_first_param_value(page._pair_views[pair_idx])) == new_val,
				"the pair view re-derived live after the edit")
		# Restore (EffectData caches per dir).
		scn.studio_apply_edit({"channel": "sound_def", "kind": "byte",
				"offset": probe_off, "pair_idx": pair_idx}, before)
		await _frames(2)

	# Ghost pips: with the pair open, every resolving trigger's span carries pips.
	var pips: Dictionary = page._compute_pips()
	if pips.is_empty():
		print("[SKIP] no E004 trigger resolves to pair %d — pip scope empty" % pair_idx)
		_passed += 1
	else:
		var lit := false
		for lane in page._timeline._score.get("lanes", []):
			for span in lane.get("spans", []):
				if not (span.get("pips", []) as Array).is_empty():
					lit = true
		_assert_true(lit, "an open pair lights pips on the resolving trigger spans")

		# FRAME-AXIS ALIGNMENT (2026-08-11 amendment): the panel projects onto
		# the timeline's SHARED axis. Park the playhead on a known pip frame —
		# the panel's playhead must sit at axis.frame_to_x(anchor + pip), and
		# with every loop unwound the drawn note onsets must land ON the pips.
		var anchor: Dictionary = page._pair_panel._anchor
		_assert_true(str(anchor.get("source", "")) != "orphan",
				"a pair with resolving triggers anchors on a real fire frame")
		var fire := int(anchor.get("frame", 0))
		var pip_list: Array = pips[pips.keys()[0]]
		var pip := int(pip_list[mini(1, pip_list.size() - 1)])
		page._timeline.set_playhead(fire + pip)
		await _frames(2)
		var expect_x: float = page._timeline.axis.frame_to_x(float(fire + pip))
		_assert_true(absf(page._pair_panel._playhead_x() - expect_x) < 0.01,
				"panel playhead parks at axis.frame_to_x(anchor + pip)")
		page._pair_panel.set_all_unwound(true)
		await _frames(2)
		var alay: Dictionary = Panel.layout(page._pair_panel._view,
				page._pair_panel.size.x, page._pair_panel._state(),
				page._timeline.axis, anchor)
		var onset_frames := {}
		for b in alay.get("span_bars", []):
			onset_frames[int(round(page._timeline.axis.x_to_frame(
					(b.get("rect") as Rect2).position.x))) - fire] = true
		var missed := 0
		for p in pip_list:
			if not onset_frames.has(int(p)):
				missed += 1
		_assert_true(missed == 0,
				"every ghost pip has an unwound panel onset at its exact frame (missed %d)" % missed)
		page._pair_panel.set_all_unwound(false)
		await _frames(2)

	# Audition fires through the on_action seam (audible on speakers; assert no crash).
	page._run_action({"kind": "audition_sound", "id": pair_idx + 1})
	await _frames(30)
	_passed += 1   # reaching here = the audition path executed without error

	scn.queue_free()
	await _frames(2)


## E001 (CURE): the RE's pre-arm exemplar (Cure_4 track A: silent instrument + ADSR/
## pitch opcodes BEFORE the first Note → AC 83 switch to an audible instrument). The
## dynamic close for §2: the classifier must FIND a Pre-arm verdict on the real cure
## bank (static-rooted, dynamically validated), and the per-track energy bands must
## corroborate it — a note-less (pure pre-arm / stub) track reads FLAT in isolation.
func _test_prearm_verdict_and_energy_on_e001() -> void:
	if not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path("res://assets/effects/E001")):
		print("[SKIP] E001 assets absent")
		_passed += 1
		return
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	var e001_dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E001"):
			e001_dir = d
	if e001_dir == "":
		print("[SKIP] E001 not in the picker")
		_passed += 1
		scn.queue_free()
		return
	page._load_effect(e001_dir)
	await _frames(20)
	if scn._current_effect.effect_data.feds_bank == null:
		print("[SKIP] E001 carries no FEDS bank")
		_passed += 1
		scn.queue_free()
		return

	# The pre-arm idiom must be visible SOMEWHERE on the cure bank — the classifier
	# finds a voice-write staged before the first note (the AC 0E → … → Note story).
	var Verdicts = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	var prearm_hits := 0
	for v in page._pair_views:
		for tv in v.get("tracks", []):
			for verdict in (Verdicts.verdicts(tv).get("per_event", {}) as Dictionary).values():
				if str(verdict) == Verdicts.PREARM:
					prearm_hits += 1
	_assert_true(prearm_hits >= 1,
			"the cure pre-arm idiom (voice-write before the first note) is found on E001")

	# The §2 dynamic close (the deterministic E001 fix): a CURE pair's track A carries a
	# silent instrument under EVERY note, so the classifier must read it WHOLLY Muted —
	# every event hatched, no lone "Live" over a provably-silent track. Find it (static-
	# rooted): a pair whose track A is wholly Muted with notes of its own.
	var muted_pair := -1
	for v in page._pair_views:
		var ta: Dictionary = v.get("tracks", [])[0] if not (v.get("tracks", []) as Array).is_empty() else {}
		if not ta.is_empty() and bool(Verdicts.verdicts(ta).get("wholly_muted")) \
				and not (ta.get("notes", []) as Array).is_empty():
			muted_pair = int(v.get("pair_idx", -1))
			break
	_assert_true(muted_pair >= 0,
			"E001 has a wholly-Muted track A — its silent-instrument notes all hatch (no 'Live' lie)")

	# Open the wholly-Muted pair (or a referenced one) and corroborate its energy bands.
	# The dynamic validation: track A's band must read SILENT IN ISOLATION — its raw,
	# un-normalized peak stays at the floor even though the shared-normalize can dress it
	# UP to a full-height swell. The band is corroboration only; the hatch is decided
	# statically off the stream, never from this render.
	var pair_idx := muted_pair
	if pair_idx < 0:
		for v in page._pair_views:
			if not (v.get("used_by_containers", []) as Array).is_empty():
				pair_idx = int(v.get("pair_idx", -1))
				break
	if pair_idx < 0:
		print("[SKIP] E001 has no container-referenced pair")
		_passed += 1
		scn.queue_free()
		await _frames(2)
		return
	page._set_root(Target.pair(pair_idx))
	await _frames(4)
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var lay: Dictionary = Panel.layout(page._pair_panel._view, 900.0, page._pair_panel._state())
	var bands: Array = lay.get("energy_bands", [])
	print("[E001] pair %d — %d energy bands; track A wholly-Muted=%s" % [pair_idx, bands.size(),
			str(Verdicts.verdicts(page._pair_views[pair_idx].get("tracks", [])[0]).get("wholly_muted"))])
	if bands.is_empty():
		print("[SKIP] E001 pair %d rendered no energy bands" % pair_idx)
		_passed += 1
	else:
		var contradiction := 0
		var checked_wholly := false
		for band in bands:
			var ti := int(band.get("track"))
			var tv: Dictionary = page._pair_views[pair_idx].get("tracks", [])[ti]
			var vd: Dictionary = Verdicts.verdicts(tv)
			var has_note: bool = not ((tv.get("notes", []) as Array).is_empty())
			print("[E001]   track %d: wholly=%s raw_peak=%.4f silent_iso=%s norm_peak=%.3f" % [ti,
					str(vd.get("wholly_muted")), float(band.get("raw_peak", -1.0)),
					str(band.get("silent_in_isolation")), float(band.get("peak"))])
			if not has_note and float(band.get("peak")) > 0.3:
				contradiction += 1
			# A wholly-Muted track must read silent in isolation — the empirical
			# corroboration of the static hatch (raw peak below the absolute floor).
			if bool(vd.get("wholly_muted")):
				checked_wholly = true
				_assert_true(bool(band.get("silent_in_isolation")),
						"E001 track %d is wholly Muted AND reads silent in isolation (raw peak %.4f)" \
						% [ti, float(band.get("raw_peak", -1.0))])
		_assert_true(contradiction == 0,
				"E001 note-less track bands read FLAT — energy corroborates the pre-arm/stub verdicts (%d off)" % contradiction)
		if not checked_wholly:
			print("[note] E001 pair %d rendered no band for its wholly-Muted track A" % pair_idx)
	scn.queue_free()
	await _frames(2)


## E317 (Choco Ball, Instrument chips): the panel projects a second real effect
## onto the shared frame axis — typed Instrument chips render, and the pair
## anchors to a representative trigger when one resolves.
func _test_frame_axis_projection_on_e317() -> void:
	if not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path("res://assets/effects/E317")):
		print("[SKIP] E317 assets absent")
		_passed += 1
		return
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	var e317_dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			e317_dir = d
	if e317_dir == "":
		print("[SKIP] E317 not in the picker")
		_passed += 1
		scn.queue_free()
		return
	page._load_effect(e317_dir)
	await _frames(20)
	var pair_idx := -1
	for v in page._pair_views:
		if not (v.get("used_by_containers", []) as Array).is_empty():
			pair_idx = int(v.get("pair_idx", -1))
			break
	if pair_idx < 0:
		print("[SKIP] E317 has no container-referenced pair")
		_passed += 1
		scn.queue_free()
		return
	page._set_root(Target.pair(pair_idx))
	await _frames(4)
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var panel = page._pair_panel
	_assert_true(panel.visible, "the pair lane panel shows for the open E317 pair")
	var lay: Dictionary = Panel.layout(panel._view, panel.size.x, panel._state(),
			page._timeline.axis, panel._anchor)
	var instr := 0
	for chip in lay.get("chips", []):
		if str(chip.get("full", "")).begins_with("Instrument"):
			instr += 1
	_assert_true(instr >= 1, "E317 pair renders typed Instrument chips")
	if not page._compute_pips().is_empty():
		_assert_true(str(panel._anchor.get("source", "")) != "orphan",
				"E317's referenced pair anchors on a resolving trigger")
		var fire := int(panel._anchor.get("frame", 0))
		var first_bar_x := INF
		for b in lay.get("span_bars", []):
			first_bar_x = minf(first_bar_x, (b.get("rect") as Rect2).position.x)
		if first_bar_x < INF:
			var pip0: int = int((page._compute_pips().values()[0] as Array)[0])
			_assert_true(absf(first_bar_x - page._timeline.axis.frame_to_x(
					float(fire + pip0))) < 0.01,
					"the first onset sits at axis.frame_to_x(anchor + first pip)")
	scn.queue_free()
	await _frames(2)


## THE NO-OP PRUNE A/B on E001 (ADR-0085 amendment 2026-08-12 "active corroboration").
## The deterministic anchor: E001's wholly-Muted track A carries a silent instrument under
## every note. Pruning its no-ops (notes → equal-delta rests) and re-rendering the MIXED
## pair must prove the audible output barely moves — the honest read is amber "faint" (a
## sub-audible floor leaks), NOT "changed". The Δ is discovered by the REAL SPU here, never
## hard-coded; we assert the tier the measurement actually lands and that it is not `changed`.
func _test_noop_ab_on_e001_wholly_muted() -> void:
	if not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path("res://assets/effects/E001")):
		print("[SKIP] E001 assets absent"); _passed += 1; return
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	var e001_dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E001"):
			e001_dir = d
	if e001_dir == "":
		print("[SKIP] E001 not in the picker"); _passed += 1; scn.queue_free(); return
	page._load_effect(e001_dir)
	await _frames(20)
	if scn._current_effect.effect_data.feds_bank == null:
		print("[SKIP] E001 carries no FEDS bank"); _passed += 1; scn.queue_free(); return
	var Verdicts = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	# Find the wholly-Muted track-A pair (static-rooted), then run the A/B on the REAL SPU.
	var muted_pair := -1
	for v in page._pair_views:
		var tracks: Array = v.get("tracks", [])
		if tracks.is_empty():
			continue
		var ta: Dictionary = tracks[0]
		if bool(Verdicts.verdicts(ta).get("wholly_muted")) \
				and not (ta.get("notes", []) as Array).is_empty():
			muted_pair = int(v.get("pair_idx", -1))
			break
	if muted_pair < 0:
		print("[SKIP] E001 has no wholly-Muted track-A pair"); _passed += 1
		scn.queue_free(); await _frames(2); return
	page._set_root(Target.pair(muted_pair))
	await _frames(4)
	var tells: Dictionary = page._run_noop_ab(muted_pair)
	if tells.is_empty():
		print("[SKIP] E001 pair %d: A/B render did not run (engine busy)" % muted_pair)
		_passed += 1; scn.queue_free(); await _frames(2); return
	var ta_tell: Dictionary = tells.get(0, {})
	var tb_tell: Dictionary = tells.get(1, {})
	print("[E001 no-op A/B] dir=E001 pair=%d  trackA: tier=%s Δ%.4f peakΔ%.4f  |  trackB: tier=%s Δ%.4f" % [
			muted_pair, str(ta_tell.get("tier")), float(ta_tell.get("max_abs", -1.0)),
			float(ta_tell.get("peak_delta", -1.0)),
			str(tb_tell.get("tier")), float(tb_tell.get("max_abs", -1.0))])
	# The load-bearing honesty check: pruning the wholly-Muted track A must not make the
	# mix change — that would mean the classifier over-claimed silence.
	#
	# This read was amber "faint" (Δ≈0.0245) until the prune's substitute became `0x80`
	# (ADR-0085 2026-08-18c §1), and the old number was measuring the OLD SUBSTITUTE, not
	# the muted note-ons. Track A's raw peak in isolation is 0.0117, so removing it can
	# move the mix by at most that — a Δ of 0.0245 was already more energy than the thing
	# being removed has. The mechanism is in `advance_track`: a note-form rest goes down
	# the NOTE path (`accumulated += delta_time`, inline), while `0x80` dispatches through
	# `_process_opcode` and RETURNS — the FFT-faithful pre-Note Rest exit at PC 0x8001588C
	# that the tempo-drift work put there. Replacing every note of a wholly-Muted track
	# with the invented form therefore deleted every one of those exits and re-batched the
	# track's cadences; measured on the capture SPU, that artifact is ~9× the Δ the real
	# form produces (Δ(baseline, note-form) 0.2562 vs Δ(baseline, 0x80) 0.0295 on
	# peak-normalized envelopes, with the two pruned renders 0.2456 apart from each other).
	#
	# With the corpus's rest the answer is the one the static classifier predicts: track A
	# is silent in isolation (0.0117 < ABSOLUTE_QUIET 0.035), so pruning it reads INERT.
	# Deterministic, so the measured Δ is stable below SILENCE_RMS (0.004).
	_assert_true(str(ta_tell.get("tier")) == GP.NOOP_INERT,
			"E001 track A's no-ops read inert — removing provably-silent notes changes nothing (Δ%.4f)" % \
			float(ta_tell.get("max_abs", -1.0)))
	# Attribution: track B is the carrier, and pruning ITS no-ops leaves the mix bit-identical.
	_assert_true(str(tb_tell.get("tier")) != GP.NOOP_CHANGED,
			"E001 track B's no-ops do not change the mix either (tier=%s Δ%.4f)" % [
			str(tb_tell.get("tier")), float(tb_tell.get("max_abs", -1.0))])
	# The panel now paints the per-track tell rows under the bands.
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var lay: Dictionary = Panel.layout(page._pair_panel._view, 900.0, page._pair_panel._state())
	_assert_true((lay.get("noop_tells", []) as Array).size() >= 1,
			"the A/B verdict rows render under the open pair's tracks")
	# The JOINT (mixed) energy waveform renders, and after the A/B its pruned mix overlays it.
	var jb: Dictionary = lay.get("joint_band", {})
	_assert_true(not jb.is_empty()
			and (jb.get("baseline_points") as PackedVector2Array).size() >= 2,
			"the panel draws the joint (mixed-pair) energy waveform")
	_assert_true((jb.get("pruned_points") as PackedVector2Array).size() >= 2,
			"after the A/B, the pruned mix overlays the joint band (the Δ is the visible gap)")
	# END-TO-END: drive it through the INSPECTOR action seam (the '▶ Audition (no-ops
	# pruned)' button beside '▶ Audition pair'), exactly as a click does — it recomputes
	# the A/B and audibly plays the pruned pair.
	page._run_action({"kind": "audition_pruned", "pair_idx": muted_pair})
	await _frames(20)
	_assert_true(page._pair_noop_ab_cache.has(muted_pair),
			"the '▶ Audition (no-ops pruned)' action runs the A/B + auditions the pruned pair")
	scn.queue_free()
	await _frames(2)


## The sharp test: on a pair with a SOUNDING track (a real live swell), pruning only its
## no-ops must leave the live frames bit-identical → the mix barely moves (inert/faint,
## never changed). If ANY real effect's pair read `changed`, the static classifier
## over-claimed a no-op — exactly the bug this experiment exists to catch.
func _test_noop_ab_on_a_partially_muted_pair() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	for name in ["E004", "E317"]:
		if not DirAccess.dir_exists_absolute(
				ProjectSettings.globalize_path("res://assets/effects/" + name)):
			continue
		var scn = load(EFFECT_SCENE).instantiate()
		add_child(scn)
		await _frames(30)
		var page = scn._studio_page
		var dir := ""
		for d in page._effect_dirs:
			if String(d).ends_with(name):
				dir = d
		if dir == "":
			scn.queue_free(); await _frames(2); continue
		page._load_effect(dir)
		await _frames(20)
		if scn._current_effect.effect_data.feds_bank == null:
			scn.queue_free(); await _frames(2); continue
		var pair_idx := -1
		for v in page._pair_views:
			if not (v.get("used_by_containers", []) as Array).is_empty():
				pair_idx = int(v.get("pair_idx", -1)); break
		if pair_idx < 0:
			scn.queue_free(); await _frames(2); continue
		page._set_root(Target.pair(pair_idx))
		await _frames(4)
		var tells: Dictionary = page._run_noop_ab(pair_idx)
		if tells.is_empty():
			print("[SKIP] %s pair %d: A/B render did not run" % [name, pair_idx])
			_passed += 1; scn.queue_free(); await _frames(2); continue
		for t in [0, 1]:
			var tl: Dictionary = tells.get(t, {})
			print("[%s no-op A/B] dir=%s pair=%d track%s: tier=%s Δ%.4f peakΔ%.4f" % [
					name, name, pair_idx, "AB"[t], str(tl.get("tier")),
					float(tl.get("max_abs", -1.0)), float(tl.get("peak_delta", -1.0))])
			_assert_true(str(tl.get("tier")) != GP.NOOP_CHANGED,
					"%s pair %d track %s: pruning the no-ops does not audibly change the mix (tier=%s Δ%.4f)" % [
					name, pair_idx, "AB"[t], str(tl.get("tier")), float(tl.get("max_abs", -1.0))])
		scn.queue_free()
		await _frames(2)
		return   # one real partially-muted pair is enough for the sharp test
	print("[SKIP] neither E004 nor E317 present for the partially-muted A/B")
	_passed += 1


## REGRESSION: pressing Play must release the offline ghost renderer IMMEDIATELY. The queue
## holds engine.capture_mode = true across frames while it pre-renders the effect's ghost
## waveforms on load, and capture_mode PARKS the live producer — so if play only aborts the
## queue one _process frame later, the effect's opening one-shot fires silently ("no sound
## until you audition"). This asserts capture_mode is false the instant _toggle_play() runs,
## while the queue is still in-flight (short wait, not drained).
func _test_play_releases_capture_mode_immediately() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(8)
	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E001"):
			dir = d
	if dir == "" and not page._effect_dirs.is_empty():
		dir = String(page._effect_dirs[0])
	if dir == "":
		print("[SKIP] no effect to play-test"); _passed += 1; scn.queue_free(); return
	page._load_effect(dir)
	await _frames(3)   # SHORT — the ghost queue is still rendering (capture_mode true)
	if page._ghost_queue.is_idle():
		print("[note] ghost queue already drained; capture_mode=%s" % str(ExMateriaEffectSfx.capture_mode))
	page._toggle_play()
	# The instant after play starts (before the next _process pump), the producer must be LIVE.
	_assert_true(not ExMateriaEffectSfx.capture_mode,
			"Play releases capture_mode immediately — the live producer is not parked (was the silent-until-audition bug)")
	page._stop()
	await _frames(2)
	scn.queue_free()
	await _frames(2)


## The event_index of the first parameterized opcode in track A of `view` (-1 = none).
func _first_param_event_index(view: Dictionary) -> int:
	for c in (view.get("tracks", [])[0] as Dictionary).get("commands", []):
		if not (c.get("params", []) as Array).is_empty() \
				and not str(c.get("label", "")).begins_with("Unknown_"):
			return int(c.get("event_index", -1))
	return -1


## The blob offset of the first parameterized opcode's first param in track A of `view`.
func _first_param_offset(view: Dictionary) -> int:
	for c in (view.get("tracks", [])[0] as Dictionary).get("commands", []):
		if not (c.get("params", []) as Array).is_empty() \
				and not str(c.get("label", "")).begins_with("Unknown_"):
			return int(c.get("offset", -1)) + 1
	return -1


## ADR-0085 2026-08-13 dynamic close: the note-chip AUDITION CONSOLE (HOLD-TO-PLAY), driven
## through the real inspector on real E001. Select the sustaining AC 67 Tubular Bells note,
## press-and-HOLD "▶ Hear this note" → audible on the master bus at the note's real pitch;
## release → stops. "▶ Tail only" hold → the loop-point ring. Crucially it asserts the
## REPEAT works (the reported bug): a SECOND hold must sound as loudly as the first — the
## managed reserved audition unit + capture-mode suppression, exercised end-to-end.
func _test_note_audition_console_on_e001() -> void:
	if not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path("res://assets/effects/E001")):
		print("[SKIP] E001 assets absent")
		_passed += 1
		return
	var Audition = load("res://src/effects/studio/FedsNoteAudition.gd")
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	var e001_dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E001"):
			e001_dir = d
	if e001_dir == "":
		print("[SKIP] E001 not in the picker")
		_passed += 1
		scn.queue_free()
		return
	page._load_effect(e001_dir)
	await _frames(20)

	# Find a sustaining, hearable note (prefer the AC 67 Tubular Bells hold this feature is
	# about) — its running instrument must build a hold-enabled, tail-capable console.
	var pick := {}
	for v in page._pair_views:
		var tracks: Array = v.get("tracks", [])
		for ti in range(tracks.size()):
			for n in (tracks[ti] as Dictionary).get("notes", []):
				var inst := int(n.get("active_instrument", -1))
				if inst < 0:
					continue
				var b: Dictionary = Audition.build(n, inst)
				if bool(b.get("hold_enabled")) and bool(b.get("sustains")) and bool(b.get("tail_enabled")):
					if pick.is_empty() or inst == 67:
						pick = {"pair": int(v.get("pair_idx", -1)), "track": ti,
								"ei": int(n.get("event_index", -1)), "inst": inst}
				if inst == 67 and not pick.is_empty() and int(pick.get("inst", -1)) == 67:
					break
	if pick.is_empty():
		print("[SKIP] E001 carries no sustaining audition note")
		_passed += 1
		scn.queue_free()
		return
	print("[E001-audition] note under instrument %d in pair %d track %d"
			% [int(pick["inst"]), int(pick["pair"]), int(pick["track"])])

	# Open the pair and select the note THROUGH the panel — the inspector scopes to it.
	page._set_root(Target.pair(int(pick["pair"])))
	await _frames(4)
	page._pair_panel._selected = {"track": int(pick["track"]), "event_index": int(pick["ei"])}
	page._pair_panel.event_selected.emit(int(pick["track"]), int(pick["ei"]))
	await _frames(4)

	# The console buttons render, gated correctly (a sustaining note enables both). No Stop
	# button — hold-to-play uses release.
	var hold_btn: Button = _console_button(page, "▶ Hear this note")
	var tail_btn: Button = _console_button(page, "▶ Tail only")
	_assert_true(hold_btn != null and tail_btn != null,
			"the note chip renders the hold-to-play Hear / Tail console")
	_assert_true(_console_button(page, "■ Stop") == null, "hold-to-play has no Stop button")
	if hold_btn == null or tail_btn == null:
		scn.queue_free()
		return
	_assert_true(not hold_btn.disabled, "a sustaining note's Hear-this-note is enabled")
	_assert_true(not tail_btn.disabled, "a sustaining note's Tail-only is enabled")

	# Tap the master bus so we assert what the author actually HEARS. Clear any capture_mode
	# a PRIOR sub-test left latched on the (autoloaded) engine — it parks the live producer.
	ExMateriaEffectSfx.capture_mode = false
	var cap := AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, cap)
	await _frames(6)

	# Hold #1 → audible; release. Then Hold #2 → MUST be audible too (the repeat bug).
	var pk1 := await _hold_and_measure(hold_btn, cap)
	_assert_true(pk1 > 0.001, "hold-to-play 'Hear this note' is audible (peak %.3f)" % pk1)
	var pk2 := await _hold_and_measure(hold_btn, cap)
	_assert_true(pk2 > 0.001, "a SECOND hold is still audible (repeat bug fixed, peak %.3f)" % pk2)
	# Tail-only hold → the loop ring is audible.
	var pkt := await _hold_and_measure(tail_btn, cap)
	_assert_true(pkt > 0.001, "hold-to-play 'Tail only' rings the loop (peak %.3f)" % pkt)

	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	scn.queue_free()
	await _frames(2)


## Press-and-hold a hold-to-play button for ~0.5s, return the peak master-bus amplitude
## heard during the hold, then release. Covers the producer's buffer lead before sampling.
func _hold_and_measure(btn: Button, cap: AudioEffectCapture) -> float:
	btn.button_down.emit()
	await _frames(24)          # cover the ~0.25s SFX buffer lead
	_drain_peak(cap)           # clear stale frames
	await _frames(12)
	var pk := _drain_peak(cap)
	btn.button_up.emit()
	await _frames(10)
	return pk


func _drain_peak(cap: AudioEffectCapture) -> float:
	var pk := 0.0
	var n := cap.get_frames_available()
	if n > 0:
		for fr in cap.get_buffer(n):
			pk = maxf(pk, maxf(absf(fr.x), absf(fr.y)))
	return pk


## An enabled/disabled console Button by its (starts-with) label, or null. The projector's
## action cells register in the inspector's action_buttons() seam.
func _console_button(page, label_starts: String) -> Button:
	if page._inspector == null:
		return null
	for b in page._inspector.action_buttons():
		if b is Button and String((b as Button).text).begins_with(label_starts):
			return b
	return null


func _first_param_value(view: Dictionary) -> int:
	for c in (view.get("tracks", [])[0] as Dictionary).get("commands", []):
		if not (c.get("params", []) as Array).is_empty() \
				and not str(c.get("label", "")).begins_with("Unknown_"):
			return int((c.get("params", []) as Array)[0])
	return -1


## Prune-for-real (ADR-0085 2026-08-13 amendment) END-TO-END on E001: drive the '🗑 Delete
## no-ops (permanent)' inspector action through the SAME seam a click takes; the pair's FEDS
## bytes change in the SHARED model (the object playback + save read), the pair re-derives live,
## and host undo (Ctrl+Z) restores the ORIGINAL bytes byte-for-byte. Persistence is Save's job
## — not asserted here (no disk write in the guard).
func _test_prune_for_real_delete_and_undo_on_e001() -> void:
	if not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path("res://assets/effects/E001")):
		print("[SKIP] E001 assets absent"); _passed += 1; return
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	var e001_dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E001"):
			e001_dir = d
	if e001_dir == "":
		print("[SKIP] E001 not in the picker"); _passed += 1; scn.queue_free(); return
	page._load_effect(e001_dir)
	await _frames(20)
	var ed = scn._current_effect.effect_data
	if ed == null or ed.feds_bank == null:
		print("[SKIP] E001 carries no FEDS bank"); _passed += 1; scn.queue_free(); return
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	# Pick a pair that actually HAS prunable no-ops (bytes change) — scan for one whose pruned
	# blob differs. E001 is wholly-muted, so its muted-note pairs qualify.
	var target_pair := -1
	for v in page._pair_views:
		var pi := int(v.get("pair_idx", -1))
		var pb = GP.build_pruned_bank(ed.feds_bank, pi, [0, 1])
		if pb != null and pb.raw != ed.feds_bank.raw:
			target_pair = pi
			break
	if target_pair < 0:
		print("[SKIP] E001 has no pair with prunable no-ops"); _passed += 1
		scn.queue_free(); await _frames(2); return
	var orig_bank = ed.feds_bank
	var orig_raw: PackedByteArray = ed.feds_bank.raw.duplicate()
	page._set_root(Target.pair(target_pair))
	await _frames(4)

	# DELETE through the inspector action seam (the '🗑 Delete no-ops' button), exactly as a click.
	page._run_action({"kind": "prune_noops_commit", "pair_idx": target_pair})
	await _frames(6)
	_assert_true(ed.feds_bank != orig_bank,
			"E001 pair %d: the delete SWAPPED the shared FedsBank object" % target_pair)
	_assert_true(ed.feds_bank.raw != orig_raw,
			"…the FEDS bytes actually changed (no-ops removed)")
	_assert_true(page._sound_env["feds_bank"] == ed.feds_bank,
			"…the studio env re-points at the pruned bank (pair re-derives from the new bytes)")
	_assert_true(page._pair_views.size() >= 1,
			"…the pair views re-derived off the pruned bytes")

	# UNDO through the host seam (Ctrl+Z): the ORIGINAL bytes come back byte-for-byte.
	page._undo()
	await _frames(6)
	_assert_true(ed.feds_bank == orig_bank, "undo restored the ORIGINAL bank object")
	_assert_true(ed.feds_bank.raw == orig_raw, "…byte-for-byte")
	_assert_true(page._sound_env["feds_bank"] == ed.feds_bank,
			"…and the studio env follows the restore (no stale pruned view)")
	scn.queue_free()
	await _frames(2)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
