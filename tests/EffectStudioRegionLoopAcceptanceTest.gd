extends Node
## Slice 5 — ACCEPTANCE (headful, real E317): the page-driven region-loop transport
## (ADR-0090) drives the REAL host. Boots the Effect Viewer + Studio page, loads E317,
## then pumps `page._process(dt)` (the real accumulator) so the REAL EffectInstance frame
## follows. Asserts:
##   - Forward mode bounces the playhead WITHIN the loop region and wraps end→start,
##   - the REAL host's effect frame follows the page (studio_seek wiring),
##   - Ping-pong reflects (direction flips to backward mid-play, endpoints once per pass),
##   - the real host's SILENT seek path (studio_seek_silent) moves the frame (reverse leg),
##   - play never auto-stops in a loop mode (a mid-play edit can't be interrupted by the
##     transport halting).
## Writes a screenshot of the timeline band (the studio lives under F3 — render into a
## SubViewport, per the FedsPairStrip lesson: field dumps don't count).
##
## Skips when E317 assets are absent (gitignored/ROM-derived).
## Run: godot --path . --quit-after 400 res://tests/EffectStudioRegionLoopAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Transport = preload("res://src/effects/studio/LoopTransport.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const SHOT := "user://region_loop_e317.png"

const R_START := 4
const R_END := 10

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioRegionLoopAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioRegionLoopAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioRegionLoopAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E317")):
		print("[SKIP] E317 assets not available — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	_assert_true(dir != "", "E317 in the effect catalogue")
	page._load_effect(dir)
	await _frames(40)

	_assert_true(page._stop_frame() > R_END,
		"effect is long enough for region [%d,%d] (stop=%d)" % [R_START, R_END, page._stop_frame()])
	_assert_true(page._host.has_method("studio_seek_silent"), "real host wired studio_seek_silent")

	# --- Forward region bounce ------------------------------------------------
	page._set_region({"start": R_START, "end": R_END})
	page._loop_mode = Transport.MODE_FORWARD
	page._seek(R_START)
	page._playing = false
	page._toggle_play()      # arm + play (host stays parked; page seeks it)
	_assert_true(page._playing, "Play engaged")

	var fwd := _pump_and_sample(page, 180)
	_assert_true(fwd.min() >= R_START and fwd.max() <= R_END,
		"forward: playhead stays within [%d,%d] (saw %d..%d)" % [R_START, R_END, fwd.min(), fwd.max()])
	_assert_true(fwd.has(R_END), "forward: reaches the region end %d" % R_END)
	_assert_true(_wrapped(fwd), "forward: wraps back to start after the end")
	# The REAL host followed the page's seeks (studio_seek wiring), not the page alone.
	var host_f: int = page._host.studio_current_frame()
	_assert_true(host_f >= R_START and host_f <= R_END,
		"real host frame %d tracks the region" % host_f)
	_assert_true(page._playing, "forward loop never auto-stops (mid-play edits stay uninterrupted)")

	# --- Ping-pong reflect ----------------------------------------------------
	page._loop_mode = Transport.MODE_PINGPONG
	page._seek(R_START)
	page._playing = false
	page._toggle_play()
	var saw_back := false
	var pong: Array = []
	for _i in range(180):
		page._process(1.0 / 60.0)
		pong.append(page._timeline.get_playhead())
		if page._loop_dir == Transport.DIR_BACK:
			saw_back = true
	_assert_true(pong.min() >= R_START and pong.max() <= R_END,
		"ping-pong: playhead stays within [%d,%d]" % [R_START, R_END])
	_assert_true(saw_back, "ping-pong: direction flips to backward (reverse leg runs)")
	_assert_true(pong.has(R_START) and pong.has(R_END), "ping-pong: reflects off both ends")

	# --- Real silent-seek path moves the frame (reverse leg mechanism) --------
	page._playing = false
	page._host.studio_seek_silent(R_START + 2)
	await _frames(3)
	_assert_true(page._host.studio_current_frame() == R_START + 2,
		"real silent seek moves the effect frame to %d" % (R_START + 2))

	# --- Screenshot of the loop band ------------------------------------------
	await _screenshot(page)


## Pump the real page transport `n` sim-frames at 60 fps and collect the playhead each frame.
func _pump_and_sample(page, n: int) -> Array:
	var samples: Array = []
	for _i in range(n):
		page._process(1.0 / 60.0)
		samples.append(page._timeline.get_playhead())
	return samples


## True if the sample stream ever steps DOWN by more than one frame (an end→start wrap).
func _wrapped(samples: Array) -> bool:
	for i in range(1, samples.size()):
		if samples[i] < samples[i - 1] - 1:
			return true
	return false


## Render the studio timeline (with the region band) into a SubViewport and grab it — the
## studio lives under the F3 overlay, not the captured main viewport.
func _screenshot(page) -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(900, 220)
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var tl = Timeline.new()
	tl.size = Vector2(900, 220)
	tl.custom_minimum_size = Vector2(900, 220)
	tl.load_score(page._timeline._score)
	tl.set_end_frame(page._stop_frame())
	tl.set_loop_region({"start": R_START, "end": R_END})
	tl.set_playhead(R_START + 3)
	tl.rebuild_layout()
	sv.add_child(tl)
	await _frames(4)
	var err := sv.get_texture().get_image().save_png(SHOT)
	_assert_true(err == OK, "timeline band screenshot written")
	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT))


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
