extends Node3D
# test-kind: logic
# seeded-break: value_at now returns 0.0 one step early (iv >= RAMP_TICKS - STEP_TICKS instead of iv >= RAMP_TICKS) — the ramp reaches fully-clear two ticks before RAMP_TICKS; the 'A: the ramp landed EARLY — one step short is the off-by-one this pins' assert reds, the start-covering / 2-tick quantisation / lands-ON-30 / monotone, seek==tick, vsync-counted (144 Hz delta), input-gate swallow-then-accept, quad-freed-on-landing, and MAP-host-exempt asserts stay green

## The Formation screen's SCREEN-IN (ADR-0172): the ramp, the input gate, the quad's lifetime,
## and the two hosts that must differ.
##
## [b]The curve is pinned as a SHAPE, never as truth.[/b] `RAMP_TICKS` = 30 is
## `WorldMapTownPage`'s measured `world_menu_open_curve` span applied to a different mechanism,
## and nothing has observed `WORLD.BIN`'s Formation entry at all. So this asserts what the code
## CLAIMS about itself — starts covering, steps every 2 vsyncs, lands exactly ON `RAMP_TICKS`,
## and `seek`/`advance`/`value_at` agree on every frame — and deliberately does NOT assert that
## 30 is right. `WorldMapScreenInTest` declines the same way, for the same reason: a test that
## pinned the number as truth would entrench the guess.
##
## Arms:
##   A. `value_at` is a pure 2-frame-stepped ramp that lands ON 30, not one step short.
##   B. `seek` and `advance` agree frame for frame — a contact sheet seeks, the game ticks, and
##      the picture you approve has to be the picture that ships.
##   C. The ramp is counted in VSYNCS: 144 Hz deltas take the same 30 ticks, not a third of them.
##   D. Input is refused while it ramps and accepted after (`CONTEXT.md`: a screen-in runs
##      "before it accepts input").
##   E. The quad is FREED on landing, not left at zero — ADR-0162's hazard: an NDC overlay quad
##      fills the screen of ANY camera in the World3D, which is the bug that rendered Formation
##      black on this very route.
##   F. The MAP host builds NO screen-in. It is a persistent overlay on a live battlefield.
##
## Run: <GODOT> --path . --quit-after 200 res://tests/FormationScreenInTest.tscn

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()

	_a_curve()
	_b_seek_matches_tick()
	_c_counted_in_vsyncs()
	await _d_input_gate_and_e_quad_lifetime()
	await _f_map_host_has_none()

	print("\n=== FormationScreenInTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationScreenInTest")
	else:
		print("[PASS] FormationScreenInTest: 2-frame ramp lands on RAMP_TICKS, seek==tick, vsync-counted, input gated, quad freed, MAP host exempt (ADR-0172)")
	get_tree().quit()


func _a_curve() -> void:
	_expect(FormationScreenIn.value_at(0) == FormationScreenIn.START_VALUE,
			"A: the ramp does not start fully covering")
	_expect(FormationScreenIn.value_at(0) == FormationScreenIn.value_at(1),
			"A: tick 1 stepped — the quantisation is %d frames" % FormationScreenIn.STEP_TICKS)
	_expect(FormationScreenIn.value_at(2) < FormationScreenIn.value_at(0),
			"A: tick 2 did not step")
	_expect(FormationScreenIn.value_at(FormationScreenIn.RAMP_TICKS) == 0.0,
			"A: the ramp does not land ON RAMP_TICKS")
	_expect(FormationScreenIn.value_at(FormationScreenIn.RAMP_TICKS - 2) > 0.0,
			"A: the ramp landed EARLY — one step short is the off-by-one this pins")
	var prev := FormationScreenIn.value_at(0)
	var monotone := true
	for t in range(1, FormationScreenIn.RAMP_TICKS + 1):
		var v := FormationScreenIn.value_at(t)
		if v > prev:
			monotone = false
		prev = v
	_expect(monotone, "A: the ramp is not monotonically falling")


func _b_seek_matches_tick() -> void:
	var seeker := FormationScreenIn.new()
	var agree := true
	for t in range(0, FormationScreenIn.RAMP_TICKS + 3):
		seeker.seek(t)
		if seeker.ticks() != t or seeker.is_active() != (t < FormationScreenIn.RAMP_TICKS):
			agree = false
	_expect(agree, "B: seek and value_at disagree — a seeked contact sheet would not be the shipped frame")
	seeker.free()


func _c_counted_in_vsyncs() -> void:
	var fast := FormationScreenIn.new()
	# 144 Hz deltas. A delta-driven tween would land in ~12 of these; a vsync counter takes 30/60 s.
	var frames := 0
	while fast.is_active() and frames < 500:
		fast.advance(1.0 / 144.0)
		frames += 1
	var want := int(ceil(FormationScreenIn.RAMP_TICKS * 144.0 / 60.0))
	_expect(absi(frames - want) <= 1,
			"C: ramp took %d frames at 144 Hz, want ~%d — it is running on the DISPLAY's clock" % [frames, want])
	if is_instance_valid(fast):
		fast.free()


func _d_input_gate_and_e_quad_lifetime() -> void:
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.host_mode = FormationDetailTransition.Host.ROSTER
	host.name = "Host"
	add_child(host)
	for _i in 6:
		await get_tree().process_frame
	_expect(not host.screen_in_active(),
			"D: the screen-in ran WITHOUT being asked — it must start settled (ADR-0172)")
	host.begin_screen_in()
	await get_tree().process_frame

	_expect(host.screen_in_active(), "D: begin_screen_in() raised no ramp on the ROSTER host")
	var quad = host.find_child("FormationScreenInQuad", true, false)
	_expect(quad != null, "E: the screen-in built no overlay quad")

	# D: ○ during the ramp must not open a Status screen behind the cover.
	#
	# Pushed through the VIEWPORT, not into `host._input`. Driving the callback directly is what
	# made the first version of this arm vacuous: the coordinator's `_input` returned early, the
	# press was never consumed, and on the real path it fell through to the roster grid's
	# `_unhandled_input` — which is where ○ on the plain roster opens Status. The arm only bites
	# when the event travels the route a key actually travels.
	var accept := InputEventKey.new()
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	get_viewport().push_input(accept)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(host.current_state() == FormationDetailTransition.State.IDLE,
			"D: ○ was acted on WHILE the screen was still raising itself")

	# Land it.
	for _i in 200:
		await get_tree().process_frame
		if not host.screen_in_active():
			break
	_expect(not host.screen_in_active(), "D: the ramp never landed")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(host.find_child("FormationScreenInQuad", true, false) == null,
			"E: the quad is still in the tree after landing — it fills ANY camera in this World3D (ADR-0162)")

	# ...and now the same press works, by the same route.
	get_viewport().push_input(accept)
	for _i in 30:
		await get_tree().process_frame
		if host.current_state() != FormationDetailTransition.State.IDLE:
			break
	_expect(host.current_state() != FormationDetailTransition.State.IDLE,
			"D: ○ was still refused AFTER the ramp landed")
	host.queue_free()
	await get_tree().process_frame


func _f_map_host_has_none() -> void:
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.host_mode = FormationDetailTransition.Host.MAP
	host.name = "MapHost"
	add_child(host)
	for _i in 8:
		await get_tree().process_frame
	host.begin_screen_in()   # asked explicitly — the MAP host must still refuse
	await get_tree().process_frame
	_expect(not host.screen_in_active(),
			"F: the persistent MAP host raised a screen-in over the battlefield it is mounted on")
	_expect(host.find_child("FormationScreenInQuad", true, false) == null,
			"F: the MAP host built a full-screen subtractive quad")
	host.queue_free()
	await get_tree().process_frame


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
