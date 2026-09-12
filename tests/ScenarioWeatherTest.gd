extends Node
## Tests for ScenarioVM's {0x3C} Weather — the map-wide rain particle latch.
##
## FFT decode (research/working_documents/WEATHER_OPCODE_3C_INVESTIGATION.md
## §0/§10/§12): the two operand bytes pack into one PSX global (Strength |
## Unknown<<8); the per-frame consumer reads Unknown as the ACTIVE gate and
## Strength as the intensity index into a velocity triple. Rain = a fixed 32
## drops; each is a 2-endpoint vertical streak that falls `(fa6a4+layer)·2`
## sub-units/frame and, on crossing its ground line, converts to a 4-frame ripple
## splat pinned to the ground height and respawns at the top. Snow is a per-map
## flag, out of scope here.
##
## The pure decode (ScenarioDecode.weather / weather_velocity_triple) and the sim
## state machine (ScenarioWeather) are tested WITHOUT a scene camera — the ground
## line is injected as a constant and the RNG is seeded for reproducibility.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioWeatherTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const WeatherClass = preload("res://src/scenarios/ScenarioWeather.gd")

var _passed: int = 0
var _failed: int = 0
var _nodes: Array = []


func _ready() -> void:
	_test_decode_active_gate()
	_test_decode_velocity_triple()
	_test_handler_registered_not_skip()
	_test_splat_frame_cadence()
	_test_sim_falls_lands_splats_and_respawns()
	_test_straddle_gate_skips_overshoot_but_hits_straddle()
	_test_cancel_hides_and_stops()

	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()

	print("\n=== ScenarioWeatherTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioWeatherTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioWeatherTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioWeatherTest")
		get_tree().quit(0)


# --- decode -----------------------------------------------------------------

# Mint an EventInstructionArgs reader from a name->value dict (the decoder takes
# the typed reader now, not a bare dict). Weather operands are unsigned, so the
# default byte width is fine.
func _reader(vals: Dictionary) -> EventInstructionArgs:
	var arr: Array = []
	for k in vals:
		arr.append({"name": String(k), "value": int(vals[k]), "bytes": 1})
	return EventInstructionArgs.from_instruction({"params": arr}, {})


func _test_decode_active_gate() -> void:
	# Unknown!=0 AND strength>=2 → active; Unknown=0 cancels; strength 0/1 = clear.
	var a := ScenarioDecode.weather(_reader({"Strength": 2, "Unknown": 1}))
	_assert_true(a.active, "Strength=2 Unknown=1 → active")
	_assert_eq(a.strength, 2, "strength decoded")

	var cancel := ScenarioDecode.weather(_reader({"Strength": 2, "Unknown": 0}))
	_assert_true(not cancel.active, "Unknown=0 → cancel (inactive)")

	var clear := ScenarioDecode.weather(_reader({"Strength": 1, "Unknown": 1}))
	_assert_true(not clear.active, "Strength=1 (clear) → inactive even with Unknown=1")

	var storm := ScenarioDecode.weather(_reader({"Strength": 4, "Unknown": 1}))
	_assert_true(storm.active and storm.strength == 4, "Strength=4 Unknown=1 → active storm")


func _test_decode_velocity_triple() -> void:
	_assert_vec_eq(ScenarioDecode.weather_velocity_triple(2), Vector3(3, 5, 8), "triple s2")
	_assert_vec_eq(ScenarioDecode.weather_velocity_triple(3), Vector3(5, 6, 9), "triple s3")
	_assert_vec_eq(ScenarioDecode.weather_velocity_triple(4), Vector3(5, 9, 18), "triple s4")


func _test_handler_registered_not_skip() -> void:
	var vm := _make_vm()
	var h = vm._handlers.get(EventInstruction.WEATHER, null)
	_assert_true(h != null, "Weather handler registered")
	if h != null:
		_assert_eq((h as Callable).get_method(), "_op_weather", "Weather → _op_weather (not skip)")


# --- sim --------------------------------------------------------------------

func _test_splat_frame_cadence() -> void:
	# Each ripple frame held 4 game-frames: 16..9 dot, 8..5 ring, 4..1 ellipse, 0 dissipate.
	_assert_eq(WeatherClass.splat_frame(16), 0, "active16 → dot")
	_assert_eq(WeatherClass.splat_frame(12), 0, "active12 → dot")
	_assert_eq(WeatherClass.splat_frame(9), 0, "active9 → dot")
	_assert_eq(WeatherClass.splat_frame(8), 1, "active8 → ring")
	_assert_eq(WeatherClass.splat_frame(5), 1, "active5 → ring")
	_assert_eq(WeatherClass.splat_frame(4), 2, "active4 → ellipse")
	_assert_eq(WeatherClass.splat_frame(1), 2, "active1 → ellipse")
	_assert_eq(WeatherClass.splat_frame(0), 3, "active0 → dissipate")


func _test_sim_falls_lands_splats_and_respawns() -> void:
	var w := _make_weather()
	# Deterministic + scene-free: inject a flat ground line and seed the RNG.
	w.ground_sampler = func(_tx: int, _tz: int) -> float: return 0.0
	w.rng.seed = 1234
	w.set_weather(true, 3)

	# All 32 drops seeded within the map footprint.
	var in_box := true
	for i in ScenarioWeather.DROP_COUNT:
		if w._drop_x[i] < 0.0 or w._drop_x[i] >= float(w.map_width):
			in_box = false
		if w._drop_z[i] < 0.0 or w._drop_z[i] >= float(w.map_depth):
			in_box = false
	_assert_true(in_box, "all drops seeded within the map footprint")

	# Run enough frames that every drop has crossed the ground line at least once
	# (strength-3 near falls 22 sub/frame; the full fall span < 384 sub → <18 frames,
	# but head-start scatter means we run generously).
	var splats_seen := 0
	for _f in 120:
		w.tick()
		for i in ScenarioWeather.DROP_COUNT:
			if w._splat_active[i] >= 0:
				splats_seen += 1
				break
	_assert_true(splats_seen > 0, "at least one splat became active during the fall")

	# Drops never sit below their ground line (they respawn on crossing).
	var all_above := true
	for i in ScenarioWeather.DROP_COUNT:
		# psx_bottom Y-down: after a tick it must not be far past the ground line.
		if w._psx_bottom[i] > ScenarioWeather.GROUND_LINE_SUB + 40.0:
			all_above = false
	_assert_true(all_above, "drops respawn near the top after crossing (not sinking)")


func _test_straddle_gate_skips_overshoot_but_hits_straddle() -> void:
	# §15.3: the splat gate is a geometric STRADDLE, not "every landing". A streak
	# SHORTER than the per-frame fall step jumps clean over the ground line between
	# frames (bottom AND top both end up past it) and must NOT splat; a long streak
	# that still straddles (top above the line) MUST splat. Drive both in one tick
	# by hand-placing two drops so the outcome is deterministic (no RNG).
	var w := _make_weather()
	w.ground_sampler = func(_tx: int, _tz: int) -> float: return 0.0
	w.rng.seed = 99
	w.set_weather(true, 3)  # near-slot vy = (fa6a4 5 + fa6a8 6)·2 = 22 sub/frame

	# Ground line is GROUND_LINE_SUB = -48 (Y-down: larger = lower/past the ground).
	# Drop 0 — SHORT streak (5), bottom just above the line: one 22-sub step lands
	# bottom at -28 and top at -33, BOTH below the line → overshoot, no straddle.
	w._psx_bottom[0] = -50.0
	w._psx_top[0] = -55.0
	# Drop 1 — LONG streak (50), same bottom: bottom → -28, top → -78 (still above
	# the line) → straddles → splats.
	w._psx_bottom[1] = -50.0
	w._psx_top[1] = -100.0

	w.tick()

	_assert_true(w._splat_active[0] < 0, "short streak overshoots the ground line → NO splat")
	_assert_true(w._splat_active[1] >= 0, "long streak straddling the ground line → splat")

	# And with the gate defeated (live A/B mode), the overshooting drop DOES splat.
	var w2 := _make_weather()
	w2.ground_sampler = func(_tx: int, _tz: int) -> float: return 0.0
	w2.rng.seed = 99
	w2.splat_straddle_gate = false
	w2.set_weather(true, 3)
	w2._psx_bottom[0] = -50.0
	w2._psx_top[0] = -55.0
	w2.tick()
	_assert_true(w2._splat_active[0] >= 0, "gate off → even an overshoot splats (A/B mode)")


func _test_cancel_hides_and_stops() -> void:
	var w := _make_weather()
	w.ground_sampler = func(_tx: int, _tz: int) -> float: return 0.0
	w.rng.seed = 7
	w.set_weather(true, 2)
	_assert_true(w._active, "active after set_weather(true)")
	w.set_weather(false, 0)
	_assert_true(not w._active, "inactive after cancel")
	# tick() is a no-op while inactive — bottoms must not move.
	var before := w._psx_bottom[0]
	w.tick()
	_assert_eq(w._psx_bottom[0], before, "tick is a no-op while cancelled")


# --- fixtures ---------------------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	vm.set_process(false)
	_nodes.append(vm)
	return vm


func _make_weather() -> ScenarioWeather:
	var w := WeatherClass.new()
	w.map_width = 10
	w.map_depth = 14
	add_child(w)  # _ready() allocates state + builds render resources
	_nodes.append(w)
	return w


# --- assert helpers ---------------------------------------------------------

func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)


func _assert_vec_eq(got, want: Vector3, name: String) -> void:
	if got is Vector3 and got.is_equal_approx(want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])
