extends Node
## Guard for ScenarioVM.settle_screen_effects() — the "all pre-battle scenario effects
## are RESOLVED before the battle starts" rule (NavigatorMain.run_combat).
##
## The bug: a direct combat SEEK fast-forwards the group's opener at 30× and parks the
## instant the opcode stream hits end-of-script. The VM's time-driven ramps (the {33}
## Color Field sepia wash, {1A} Map Darkness, {2E} Background gradient, the {Reveal}
## fade, the {76}/{3E}/{7D}/{91} overlays, {6B} BG-sound fades) advance one frame per
## tick INDEPENDENTLY of dispatch — so a ramp armed by one of the last opcodes has no
## following Wait to tick against and is left mid-flight, lingering into combat. The 1×
## linear walk ticks them to completion; the seek does not.
##
## settle_screen_effects() snaps every in-flight ramp to its COMMITTED TARGET (never
## neutral — combat inherits the committed palette, WITHIN_GROUP_MEMBER_TRANSITION.md),
## mirroring a tick-to-final-frame, so the seek lands exactly where the walk does. This
## test arms each effect mid-ramp and asserts one settle_screen_effects() call resolves
## them all to target, and that the per-effect snap()s land on their terminal state.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioSettleScreenEffectsTest.tscn

const ScenarioVMClass := preload("res://src/scenarios/ScenarioVM.gd")
## The host's declared mount for the addon's map composer (ADR-0207 dec. 1). A `.tscn`
## `ext_resource` names a path, never a `class_name`, so the mount is a SCENE — and
## `instantiate()` hands back the same unparented `Node3D` carrying `MapComposer.gd` that
## `MapComposerScript.new()` did, already named `ProceduralMap`, with `_ready` still unfired.
const ProceduralMapScene := preload("res://assets/scenes/ProceduralMap.tscn")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_settle_resolves_field_tint_to_committed_target()
	_test_settle_snaps_oxide_reveal_and_background()
	_test_settle_is_noop_when_nothing_ramping()
	_test_background_settle_lands_on_target()
	_test_bgsound_settle_lands_on_target()
	_test_darkscreen_settle_grow_and_retract()
	_test_colorscreen_settle_lands_on_end()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioSettleScreenEffectsTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioSettleScreenEffectsTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioSettleScreenEffectsTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioSettleScreenEffectsTest")
		get_tree().quit(0)


# --- The {33} Color Field sepia wash: the actual lingering effect --------------
## Arm a {33} Color Field ramp (Time=8) toward the blue target (−3,−1,+3)/31, tick it
## partway so it's mid-ramp, then assert one settle_screen_effects() call snaps it to
## the committed TARGET (not neutral identity). This is the sepia/hue wash the seek was
## leaving mid-flight.
func _test_settle_resolves_field_tint_to_committed_target() -> void:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	# Real composer, NOT add_child'd → set_field_tint no-ops (no geometry_mesh), so the
	# test exercises the ramp model without needing a built map (mirrors the commit test).
	vm.map_composer = ProceduralMapScene.instantiate()

	vm._op_color_field(_color_field_inst(4, 0xFD, 0xFF, 0x03, 8))  # Time=8 → in-flight
	for _i in 3:
		vm._field_tint.tick()
	_assert_true(vm._field_tint != null and vm._field_tint.is_ramping(),
		"precondition: field tint is mid-ramp before settle")
	var mid := vm._field_tint.bias

	vm.settle_screen_effects()

	_assert_true(not vm._field_tint.is_ramping(),
		"settle: field tint no longer ramping")
	# Committed target = (−3,−1,+3)/31 (same target the commit test asserts), NOT the
	# mid-ramp value and NOT neutral (0,0,0) — combat inherits the committed hue.
	_assert_vec_near(vm._field_tint.bias, Vector3(-3, -1, 3) / 31.0,
		"settle: field tint snapped to committed target, not neutral")
	_assert_true(not vm._field_tint.bias.is_equal_approx(mid),
		"settle: field tint moved off its mid-ramp value")


# --- Oxide + Reveal + Background, all resolved by one settle call ---------------
func _test_settle_snaps_oxide_reveal_and_background() -> void:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)

	# {1A} Map Darkness oxide, mid-ramp toward the sepia target (50,34,30).
	vm._oxide_start_byte = Vector3(20, 4, 0)
	vm._oxide_target_byte = Vector3(50, 34, 30)
	vm._oxide_current_byte = Vector3(35, 19, 15)
	vm._oxide_duration_ticks = 32
	vm._oxide_remaining_ticks = 16

	# {Reveal} fade, mid-reveal (half-black rect).
	vm.fade_rect = ColorRect.new()
	vm.fade_rect.color = Color(0, 0, 0, 0.5)
	vm._reveal_duration_ticks = 96
	vm._reveal_remaining_ticks = 48

	# {2E} Background gradient, mid-ramp.
	vm._background = load("res://src/scenarios/ScenarioBackground.gd").new()
	vm._background.apply(Vector3(184, 188, 119), Vector3(16, 29, 61), 8)
	vm._background.tick()

	vm.settle_screen_effects()

	_assert_true(vm._oxide_remaining_ticks == 0, "settle: oxide ramp done")
	_assert_vec_near(vm._oxide_current_byte, Vector3(50, 34, 30),
		"settle: oxide snapped to target")
	_assert_true(vm._reveal_remaining_ticks == 0, "settle: reveal ramp done")
	_assert_true(vm.fade_rect.color.a <= 0.001,
		"settle: reveal snapped the fade fully clear (alpha 0)")
	_assert_true(not vm._background.is_ramping(), "settle: background ramp done")
	_assert_vec_near(vm._background.top, Vector3(184, 188, 119) / 255.0,
		"settle: background top corner snapped to target")

	vm.fade_rect.free()


# --- No-op / null-safe when nothing is armed (the linear-walk path) -------------
func _test_settle_is_noop_when_nothing_ramping() -> void:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	# Fresh VM: every effect is null / idle. settle must not throw and must leave the
	# idle reveal fade untouched.
	vm.fade_rect = ColorRect.new()
	vm.fade_rect.color = Color(0.2, 0.3, 0.4, 0.7)  # arbitrary, no reveal armed
	vm.settle_screen_effects()  # must not throw
	# Color channels are 32-bit floats, so compare with a tolerance (0.7 != 0.7f exactly).
	_assert_true(abs(vm.fade_rect.color.a - 0.7) < 0.001,
		"settle: no reveal armed → fade rect untouched")
	vm.fade_rect.free()


# --- Per-effect settle() snaps (class-level, pure model) ------------------------
func _test_background_settle_lands_on_target() -> void:
	var bg = load("res://src/scenarios/ScenarioBackground.gd").new()
	bg.apply(Vector3(200, 100, 50), Vector3(10, 20, 30), 8)  # Time=8 → ramps
	bg.tick()
	_assert_true(bg.is_ramping(), "precondition: background mid-ramp")
	_assert_true(bg.settle(), "background settle() returns true (snapped)")
	_assert_true(not bg.is_ramping(), "background settled: not ramping")
	_assert_vec_near(bg.top, Vector3(200, 100, 50) / 255.0, "background top on target")
	_assert_vec_near(bg.bottom, Vector3(10, 20, 30) / 255.0, "background bottom on target")
	_assert_true(not bg.settle(), "background settle() returns false when idle")


func _test_bgsound_settle_lands_on_target() -> void:
	var s = load("res://src/scenarios/ScenarioBgSound.gd").new()
	s.start_ramp(10, 100, 20)  # fade 10 → 100 over 20 frames
	s.tick()
	_assert_true(not s.is_idle(), "precondition: bg-sound mid-ramp")
	_assert_true(s.settle(), "bg-sound settle() returns true (snapped)")
	_assert_true(s.is_idle(), "bg-sound settled: idle")
	_assert_true(s.vol == 100, "bg-sound vol on target (100)")
	_assert_true(not s.settle(), "bg-sound settle() returns false when idle")


func _test_darkscreen_settle_grow_and_retract() -> void:
	# Grow-in ({76}) settles fully established (progress 1, still visible).
	var grow = load("res://src/scenarios/ScenarioDarkScreen.gd").new()
	add_child(grow)
	grow.start(_dark_intent())
	grow.settle()
	_assert_true(abs(grow.progress() - 1.0) < 0.001,
		"dark-screen grow settles to progress 1 (established)")
	grow.queue_free()

	# Retract ({77}) settles cleared + hidden (progress 0).
	var retract = load("res://src/scenarios/ScenarioDarkScreen.gd").new()
	add_child(retract)
	retract.start(_dark_intent())
	retract.remove()
	retract.settle()
	_assert_true(abs(retract.progress()) < 0.001,
		"dark-screen retract settles to progress 0 (cleared)")
	_assert_true(not retract.visible, "dark-screen retract settles hidden")
	retract.queue_free()


func _test_colorscreen_settle_lands_on_end() -> void:
	var cs = load("res://src/scenarios/ScenarioColorScreen.gd").new()
	add_child(cs)
	cs.start(_color_screen_intent(Vector3.ZERO, Vector3(255, 255, 255), 10))
	cs.tick()
	cs.tick()
	_assert_true(cs.is_active(), "precondition: color-screen mid-ramp")
	cs.settle()
	_assert_true(not cs.is_active(), "color-screen settled: not active")
	_assert_vec_near(cs.current_color(), Vector3(255, 255, 255),
		"color-screen snapped to end colour")
	cs.queue_free()


# --- Helpers -------------------------------------------------------------------
func _dark_intent():
	var intent = ScenarioDecode.DarkScreenIntent.new()
	intent.screen_expansion_speed = 12
	intent.square_expansion_speed = 4
	return intent


func _color_screen_intent(start: Vector3, end: Vector3, time: int):
	var intent = ScenarioDecode.ColorScreenIntent.new()
	intent.mode = 0
	intent.start = start
	intent.end = end
	intent.time = time
	return intent


func _color_field_inst(mode: int, r: int, g: int, b: int, time: int) -> Dictionary:
	return {
		"name": "Color Field", "opcode": 0x33, "offset": 0,
		"params": [
			{"name": "Color", "value": mode}, {"name": "Red", "value": r},
			{"name": "Green", "value": g}, {"name": "Blue", "value": b},
			{"name": "Time", "value": time},
		],
	}


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _assert_vec_near(got, want: Vector3, name: String) -> void:
	if got is Vector3 and (got as Vector3).distance_to(want) < 0.01:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s (got %s, want %s)" % [name, str(got), str(want)])
