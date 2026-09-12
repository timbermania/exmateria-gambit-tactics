extends Node
## Tests for ScenarioVM's {43} Call Function 4 — the battle->scenario-6 "dead unit
## fade": at the end of the Chapter-1 battle the losing side's on-field units fade
## out and are removed just before the abduction cutscene ("Princess Ovelia / Let
## go of me!").
##
## RE (research/working_documents/SCENARIO6_DEAD_UNIT_FADE.md, byte-grounded live on
## PSX): scenario-6 instr 7 = {43} Call Function Function=4 -> ROM FUN_80147cf0
## sweeps all 21 unit slots and fades every one with a live on-field sprite whose
## side index (`unit+0x1BA & 0x30`) is non-zero — a STABLE ENTD team byte, NOT
## hp==0 (§4.3). The VFX is TWO passes of the Color-Unit tint engine: pass 1
## mode-4 Δ=(-31,-31,0) kills R,G; pass 2 mode-4 Δ=(-31,-31,-31) collapses to
## black; then the sprite is hidden/despawned. The event VM then yields 120 frames.
##
## Scenario 6 uses ENTD record 387: the five enemy corpses are uids 134-138
## (team_color 1, always_present) — they fade; the abduction's staged actors (uids
## 5,139: team_color 1 but NOT yet on field) are spared and re-Added by the block
## after the sweep. This test models that partition with fake units and asserts the
## selection, the two-pass fade, the removal, and the 120-tick VM hold.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioDeadUnitFadeTest.tscn

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const OpaqueShader = preload("res://addons/exmateria_sprite_rig/render/unit.gdshader")
const AdditiveShader = preload("res://addons/exmateria_sprite_rig/render/unit_additive.gdshader")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_handler_bound()
	_test_selection_partition()
	_test_holds_vm_120_ticks()
	_test_two_pass_fade_to_black_then_hide()
	_test_persisting_side_and_staged_untouched()
	_test_additive_blend_swap()
	_test_fade_freezes_corpse_animation()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioDeadUnitFadeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioDeadUnitFadeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioDeadUnitFadeTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioDeadUnitFadeTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _assert_eq(got, want, name: String) -> void:
	_assert_true(got == want, "%s (got=%s want=%s)" % [name, str(got), str(want)])


func _assert_near(got: float, want: float, name: String, eps := 0.05) -> void:
	_assert_true(absf(got - want) <= eps, "%s (got=%.3f want=%.3f)" % [name, got, want])


# --- fakes -------------------------------------------------------------------

class FakeMaterial extends RefCounted:
	var params: Dictionary = {}
	func set_shader_parameter(name: String, value) -> void:
		params[name] = value

## Stand-in for the per-unit [UnitShadow]. `ScenarioWorld.set_unit_shadow` duck-types
## on `unit._shadow.set_enabled`, so this is the whole surface the {43} sweep's
## shadow-off (ROM `sb zero,0x298(s0)` in FUN_8008945c) touches.
class FakeShadow extends RefCounted:
	var enabled: bool = true
	var calls: int = 0
	func set_enabled(on: bool) -> void:
		enabled = on
		calls += 1

## Minimal stand-in for a spawned scenario Unit: carries the two ENTD-derived
## fields the sweep gate reads (`scenario_team_color`, `scenario_present`) plus the
## `visible`/`material` surface the tint push + removal touch.
class FakeUnit extends RefCounted:
	var _shadow := FakeShadow.new()
	var material := FakeMaterial.new()
	var visible: bool = true
	var scenario_team_color: int = 0
	var scenario_present: bool = true

## Fake unit carrying a REAL ShaderMaterial so the additive blend-mode swap can be
## asserted (the plain FakeUnit's FakeMaterial isn't a ShaderMaterial, so the swap
## no-ops there — by design, matching VM-only tint tests).
class FakeUnitReal extends RefCounted:
	var _shadow := FakeShadow.new()
	var material := ShaderMaterial.new()
	var visible: bool = true
	var scenario_team_color: int = 1
	var scenario_present: bool = true

## Fake unit exposing the `tick_based`/`advance_frame` anim surface that
## `_advance_scenario_anim` drives, so the freeze-on-fade behaviour can be
## asserted by counting `advance_frame` calls.
class FakeAnimUnit extends RefCounted:
	var _shadow := FakeShadow.new()
	var material := FakeMaterial.new()
	var visible: bool = true
	var scenario_team_color: int = 0
	var scenario_present: bool = true
	# Mirror the real Unit (ADR-0083): owner is settable, tick_based is derived.
	var clock_owner: ClockOwner = ClockOwner.SCENARIO
	var tick_based: bool:
		get: return clock_owner != ClockOwner.SELF
	var advance_count: int = 0
	func advance_frame(_normal_reps: int = 1, _react_reps: int = 1) -> void:
		advance_count += 1


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)  # triggers _ready -> handler registration + a valid _current_ctx
	_vms.append(vm)
	return vm


func _add_unit(vm: ScenarioVMClass, uid: int, team_color: int, present: bool) -> FakeUnit:
	var u := FakeUnit.new()
	u.scenario_team_color = team_color
	u.scenario_present = present
	vm.units_by_id[uid] = u
	return u


func _call_function_inst(fn: int) -> Dictionary:
	return {
		"name": "Call Function", "opcode": EventInstruction.CALL_FUNCTION, "offset": 0,
		"params": [{"name": "Function", "value": fn, "bytes": 1}],
	}


## Drive the effect ramps `n` frames the way `_tick_once` does: tick every actor's
## tint (advancing/pushing it), THEN advance the fade sequencer — same order as the
## live per-tick loop, without the full dispatch/round-robin machinery.
func _pump(vm: ScenarioVMClass, n: int) -> void:
	for _f in range(n):
		for uid in vm.actors:
			var t = (vm.actors[uid]).tint
			if t != null and t.tick():
				vm._apply_unit_tint(int(uid), t)
		vm._advance_dead_unit_fades()


# --- tests -------------------------------------------------------------------

func _test_handler_bound() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.CALL_FUNCTION),
		"Call Function (0x43) is bound")


# The sweep fades on-field non-persisting-side units only: the enemy corpse is
# selected; the player-side unit and the staged (not-yet-present) enemy are not.
func _test_selection_partition() -> void:
	var vm := _make_vm()
	var enemy := _add_unit(vm, 134, 1, true)      # team 1, on-field -> FADE
	var player := _add_unit(vm, 2, 0, true)       # team 0 (persists) -> KEEP
	var staged := _add_unit(vm, 5, 1, false)      # team 1 but not present -> SPARED

	vm._current_ctx.pc = 8
	vm._op_call_function(_call_function_inst(4))

	_assert_true(vm._dead_unit_fades.has(134), "enemy corpse is swept")
	_assert_true(not vm._dead_unit_fades.has(2), "player-side unit is NOT swept")
	_assert_true(not vm._dead_unit_fades.has(5), "staged (not-present) enemy is NOT swept")

	# The swept unit has an armed, in-flight fade tint; the others have none.
	var ea = vm.peek_actor(134)
	_assert_true(ea != null and ea.tint != null and ea.tint.is_ramping(),
		"swept enemy has an in-flight fade tint")
	_assert_true(vm.peek_actor(2) == null or vm.peek_actor(2).tint == null,
		"player-side unit got no tint")
	_assert_true(vm.peek_actor(5) == null or vm.peek_actor(5).tint == null,
		"staged enemy got no tint")
	# Shadow-off rides the SAME partition as the tint: the ROM clears the
	# drop-shadow show-flag `+0x298` inside FUN_8008945c, which only the swept
	# units are put through.
	_assert_true(not enemy._shadow.enabled, "swept enemy's shadow is off on the ARM frame")
	_assert_true(player._shadow.enabled, "player-side unit keeps its shadow")
	_assert_true(staged._shadow.enabled, "staged enemy keeps its shadow")
	# Silence "unused" — the nodes are what the assertions above reason about.
	_assert_true(enemy.visible and player.visible and staged.visible,
		"all units start visible")


# {43} Function 4 holds the calling context 120 ticks (event_fiber_yield_n(0x78))
# and does NOT halt the VM.
func _test_holds_vm_120_ticks() -> void:
	var vm := _make_vm()
	_add_unit(vm, 134, 1, true)
	vm._current_ctx.pc = 8
	vm._running = true
	vm._op_call_function(_call_function_inst(4))
	_assert_eq(vm._current_ctx.wait_ticks, 120, "Function 4 holds the VM 120 ticks")
	_assert_true(vm._running, "Function 4 does NOT halt the VM (_running stays true)")


# The two-pass fade: pass 1 kills R,G (keeps B) -> pass 2 collapses to black ->
# the unit is removed from the field (hidden), and the fade record clears.
func _test_two_pass_fade_to_black_then_hide() -> void:
	var vm := _make_vm()
	var enemy := _add_unit(vm, 134, 1, true)
	vm._current_ctx.pc = 8
	vm._op_call_function(_call_function_inst(4))
	var tint = vm.peek_actor(134).tint

	# Run pass 1 to completion (fast 8-frame ramp). It must land on Δ=(-31,-31,0):
	# bias R,G = -1 (kill), B = 0 (kept) — a dark silhouette, not yet black.
	_pump(vm, 8)
	_assert_near(tint.bias.x, -1.0, "after pass 1, bias.R killed (-1)")
	_assert_near(tint.bias.y, -1.0, "after pass 1, bias.G killed (-1)")
	_assert_near(tint.bias.z, 0.0, "after pass 1, bias.B kept (0)")
	_assert_eq(vm._dead_unit_fades.get(134), 2, "pass 1 landing advances to pass 2")
	_assert_true(enemy.visible, "unit still on field mid-fade (pass 2)")
	# The ground shadow is already GONE — killed on the arm frame, not at removal
	# (ROM `sb zero,0x298(s0)` @ 0x800894CC, two instructions before the tpage
	# write). A blob still drawing here is the "shadow outlives the corpse" bug.
	_assert_true(not enemy._shadow.enabled, "shadow still off through the dissolve")

	# Run pass 2 to completion (Time=4 slow ramp = 32 frames). It lands on
	# Δ=(-31,-31,-31): bias all -1 -> the CLUT collapses to black. Then the unit
	# is removed from the field and the fade record is cleared.
	_pump(vm, 40)
	_assert_near(tint.bias.z, -1.0, "after pass 2, bias.B killed -> black")
	_assert_true(not enemy.visible, "unit removed from field after fade (hidden)")
	_assert_true(not vm._dead_unit_fades.has(134), "fade record cleared once removed")
	# Restored with the opaque shader, for the same reason: the unit is off the
	# field, and a navigator/replay reuse must not inherit a shadowless unit.
	_assert_true(enemy._shadow.enabled, "shadow show-flag restored when the corpse is removed")


# A belt-and-braces guard on the two spared classes across the WHOLE fade: the
# persisting-side unit and the staged enemy stay visible and untinted even after
# the full sequence runs (they must never be caught by a later pass).
func _test_persisting_side_and_staged_untouched() -> void:
	var vm := _make_vm()
	_add_unit(vm, 134, 1, true)                    # will fade
	var player := _add_unit(vm, 2, 0, true)        # persists
	var staged := _add_unit(vm, 5, 1, false)       # spared (staged)
	vm._current_ctx.pc = 8
	vm._op_call_function(_call_function_inst(4))
	_pump(vm, 60)
	_assert_true(player.visible, "persisting-side unit still visible after full fade")
	_assert_true(staged.visible, "staged enemy still visible after full fade")
	_assert_true(vm.peek_actor(2) == null or vm.peek_actor(2).tint == null,
		"persisting-side unit never tinted")
	_assert_true(vm.peek_actor(5) == null or vm.peek_actor(5).tint == null,
		"staged enemy never tinted")
	_assert_true(player._shadow.calls == 0, "persisting-side unit's shadow never touched")
	_assert_true(staged._shadow.calls == 0, "staged enemy's shadow never touched")


# The fade renders the corpse ADDITIVELY so palette→black dissolves it into the
# background (ROM tpage ABR=1) instead of a black silhouette. Assert the unit's
# per-instance material is flipped to the additive shader on arm, and restored to
# the opaque shader when it's removed at the end of the fade.
func _test_additive_blend_swap() -> void:
	var vm := _make_vm()
	var enemy := FakeUnitReal.new()
	enemy.material.shader = OpaqueShader
	vm.units_by_id[134] = enemy
	vm._current_ctx.pc = 8
	vm._op_call_function(_call_function_inst(4))
	_assert_true(enemy.material.shader == AdditiveShader,
		"fade swaps the corpse to the additive (blend_add) shader")
	_pump(vm, 60)
	_assert_true(not enemy.visible, "faded corpse hidden at end")
	_assert_true(enemy.material.shader == OpaqueShader,
		"opaque shader restored when the corpse is removed")


# A swept corpse must FREEZE its body animation for the whole fade (ROM sets the
# static-sprite flag +0x298=0). Otherwise the freshly-spawned enemy keeps running
# its idle clock and visibly "stands up"/bobs while dissolving. Assert
# `_advance_scenario_anim` skips a swept unit but still drives an un-swept one.
func _test_fade_freezes_corpse_animation() -> void:
	var vm := _make_vm()
	var corpse := FakeAnimUnit.new()
	corpse.scenario_team_color = 1   # losing side -> swept
	vm.units_by_id[134] = corpse
	var survivor := FakeAnimUnit.new()
	survivor.scenario_team_color = 0  # persisting side -> keeps animating
	vm.units_by_id[2] = survivor

	vm._current_ctx.pc = 8
	vm._op_call_function(_call_function_inst(4))

	# Pump the body-anim clock several ticks the way `_advance_tick_visuals` does.
	for _f in range(10):
		vm._advance_scenario_anim()

	_assert_eq(corpse.advance_count, 0,
		"swept corpse's body anim is frozen during the fade")
	_assert_true(survivor.advance_count > 0,
		"un-swept survivor keeps animating")
