extends Node
## ADR-0090 dec. 4 "speed is a continuous 0.1×–4× scrub field" ACCEPTANCE (headful,
## real E019). Boots the real EffectViewer, parks E019 in the Studio, and drives the LIVE
## toolbar speed ScrubField end-to-end to prove the refined control changes the playback
## rate on a real effect:
##   * the toolbar speed control is a ScrubField that renders its own value ("1.00×");
##   * landing it on 0.25× / 2.0× re-labels it AND changes _speed(), the transport
##     multiplier the page-driven clock reads;
##   * driving a fixed synthetic tick sequence from frame 0 advances the real playhead
##     proportionally to speed — 2.0× travels ~8× as far as 0.25× (both well short of the
##     E019 end, so neither clamps).
## Ticks are fed synchronously (no await between them) so ONLY these ticks move the
## transport — the engine's own _process can't interleave. This is the wired-end-to-end
## proof; drag feel is eyeballed in /verify.
##
## Saves a real-window screenshot for the human review pass (field dumps don't count):
##   /tmp/e019_speed_scrubfield.png
##
## Run: <GODOT> --path . --quit-after 200 res://tests/EffectStudioSpeedFieldAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const ScrubField = preload("res://src/effects/studio/ScrubField.gd")
const Transport = preload("res://src/effects/studio/LoopTransport.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_speed_field_changes_real_playback_rate()

	print("\n=== EffectStudioSpeedFieldAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSpeedFieldAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSpeedFieldAcceptanceTest")
		get_tree().quit(0)


func _test_speed_field_changes_real_playback_rate() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(40)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	_assert_true(dir != "", "E019 is in the effect catalogue")
	if dir == "":
		return
	page._load_effect(dir)
	await _frames(20)

	# The toolbar control is the continuous ScrubField (not the old cycle button), and it
	# renders its own value seeded at 1.00×.
	var f = page._speed_btn
	_assert_true(f is ScrubField, "the toolbar speed control is a ScrubField")
	_assert_eq(_field_text(f), "1.00×", "the field renders its seeded value as 1.00×")

	var budget: int = page._stop_frame()
	_assert_true(budget > 40, "E019 has room to advance without clamping (stop=%d)" % budget)

	# 0.4 s of transport delivered as 8 ticks of 0.05 s. At 30 Hz that's 12 base frames;
	# speed multiplies it (3 frames at 0.25×, 24 at 2.0×) — both far under the E019 end.
	var slow := _drive(page, 0.25, 8, 0.05)
	_assert_eq(_field_text(f), "0.25×", "landing the field on 0.25 re-labels it 0.25×")
	_assert_near(slow, 3, "0.25× advances ~3 frames over 0.4 s")

	var fast := _drive(page, 2.0, 8, 0.05)
	_assert_eq(_field_text(f), "2.00×", "landing the field on 2.0 re-labels it 2.00×")
	_assert_near(fast, 24, "2.0× advances ~24 frames over 0.4 s")

	_assert_true(fast > slow, "the faster speed advances the real playhead further (%d > %d)" % [fast, slow])
	_assert_near(fast, slow * 8, "2.0× travels ~8× as far as 0.25× (proportional to speed)")
	_assert_true(fast < budget, "even the fast run stays short of the E019 end (no clamp)")

	# Park on a readable value and shoot the real Studio window for the human pass.
	page._speed_btn.value = 1.5
	await _frames(4)
	_shot(page, "/tmp/e019_speed_scrubfield.png")


# --- drive ----------------------------------------------------------------

## Park at frame 0 with a NON-looping transport, land the LIVE speed field on `speed`
## (fanning its value_changed into the page), then feed `ticks` synthetic `dt` steps
## synchronously (so only these advance the transport). Returns the real playhead.
func _drive(page, speed: float, ticks: int, dt: float) -> int:
	page._seek(0)
	page._loop_mode = Transport.MODE_OFF
	page._loop_dir = Transport.DIR_FWD
	page._speed_btn.value = speed          # the real widget → value_changed → _speed_value
	page._playing = true
	page._transport_accum = 0.0
	for _i in range(ticks):
		page._process(dt)
	var p: int = page._timeline.get_playhead()
	page._playing = false
	return p


func _field_text(f) -> String:
	return f._display.text if f._display != null else ""


## Capture the WINDOW that hosts the page — the Studio lives in the DebugDashboard, a
## separate OS Window (its own viewport), not the main game viewport.
func _shot(ctrl: Control, path: String) -> void:
	var img := ctrl.get_window().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] %s" % path)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


# --- asserts --------------------------------------------------------------

func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_near(actual: int, expected: int, label: String) -> void:
	if absi(actual - expected) <= 2:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected ~%d, got %d" % [label, expected, actual])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)
