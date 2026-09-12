extends Node
## Tests for ScenarioVM's {0x33} Color Field — the Orbonne prayer-scene
## WHOLE-SCENE palette-content fade (everything: all unit sprites AND the map
## palette darken during the prayer, then untint when the prayer text clears).
##
## FFT decode (research/working_documents/scenario_1_captures/
## prayer_screen_tint_quad_decode.md §8.5-8.7): the palette darkening is a
## per-view CLUT brightness curve armed by FUN_8008f710 and converged by a
## per-frame ticker; the untint is gated on the prayer Display Message advancing
## (§6.4). Color Field is the BROADCAST sibling of {0x32} Color Unit — the SAME
## Color(mode)/RGB/Time affine (tinted = base*scale + bias), applied to the whole
## field (every unit CLUT + the map palette) instead of one unit (no Units/Multi).
## Godot models it faithfully in PALETTE SPACE: the affine is pushed to each
## unit's unit_tint_scale/bias (composed with any active {32} tint) and to the
## map via MapComposer.set_field_tint (indexed_color.gdshader rewrites the sampled
## palette entry) — the same per-surface CLUT rewrite the PSX applier does, NOT a
## screen-space filter.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioColorFieldTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const Tint = preload("res://src/scenarios/ScenarioColorTint.gd")
const CHUNK_PATH := "res://assets/scenarios/scenario_1_chunk.json"

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_handler_registered_not_skip()
	_test_broadcast_darken_reaches_all_units_and_map()
	_test_ramp_ticks_outside_halt_gate()
	_test_untint_restores_identity()
	_test_time_zero_snaps()
	_test_field_composes_with_color_unit_tint()
	_test_real_chunk_field_ops_do_not_halt()
	_test_psx_parity_uniform_additive_clamp()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioColorFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioColorFieldTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioColorFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioColorFieldTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)


func _assert_vec_near(got, want: Vector3, name: String) -> void:
	if got is Vector3 and got.is_equal_approx(want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# --- fakes -------------------------------------------------------------------

class FakeMaterial extends RefCounted:
	var params: Dictionary = {}
	func set_shader_parameter(name: String, value) -> void:
		params[name] = value
	func get_shader_parameter(name: String):
		return params.get(name)

class FakeUnit extends RefCounted:
	var material := FakeMaterial.new()
	var visible: bool = true

## Stand-in for MapComposer: records the last {33} field color-stack broadcast so the
## test can assert the map palette received the same affine as the units (ADR-0067).
class FakeMapComposer extends Node:
	var last_scale: Vector3 = Vector3.ONE
	var last_bias: Vector3 = Vector3.ZERO
	var calls: int = 0
	func set_field_color_stack(tint_scale: Vector3, tint_bias: Vector3, _div: int,
			_delta5: Vector3i, _from_current: bool, _mix: float) -> void:
		last_scale = tint_scale
		last_bias = tint_bias
		calls += 1


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	return vm


func _add_unit(vm: ScenarioVMClass, uid: int) -> FakeUnit:
	var u := FakeUnit.new()
	vm.units_by_id[uid] = u
	return u


func _color_field_inst(mode: int, r: int, g: int, b: int, time: int) -> Dictionary:
	return {
		"name": "Color Field", "opcode": 0x33, "offset": 0,
		"params": [
			{"name": "Color", "value": mode},
			{"name": "Red", "value": r},
			{"name": "Green", "value": g},
			{"name": "Blue", "value": b},
			{"name": "Time", "value": time},
		],
	}


func _color_unit_inst(units: int, mode: int, r: int, g: int, b: int, time: int) -> Dictionary:
	return {
		"name": "Color Unit", "opcode": 0x32, "offset": 0,
		"params": [
			{"name": "Units", "value": units},
			{"name": "Multi", "value": 0},
			{"name": "Color", "value": mode},
			{"name": "Red", "value": r},
			{"name": "Green", "value": g},
			{"name": "Blue", "value": b},
			{"name": "Time", "value": time},
		],
	}


## ADR-0067: the VM pushes the field-composed unit tint as color_layer_* uniforms
## (unit.gdshader folds them). Read the affine layer's scale/bias back out (the affine
## layer is the one with div 0 in rgb1.w).
func _affine_layer(u: FakeUnit) -> int:
	var rgb1 = u.material.params.get("color_layer_rgb1")
	var count: int = u.material.params.get("color_layer_count", 0)
	for i in range(count):
		if rgb1[i].w == 0.0:
			return i
	return -1


func _uscale(u: FakeUnit) -> Vector3:
	var i := _affine_layer(u)
	if i < 0:
		return Vector3.ONE
	var v = u.material.params.get("color_layer_rgb0")[i]
	return Vector3(v.x, v.y, v.z)


func _ubias(u: FakeUnit) -> Vector3:
	var i := _affine_layer(u)
	if i < 0:
		return Vector3.ZERO
	var v = u.material.params.get("color_layer_rgb1")[i]
	return Vector3(v.x, v.y, v.z)


# --- tests -------------------------------------------------------------------

func _test_handler_registered_not_skip() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.COLOR_FIELD), "Color Field handler registered")
	# Prove it is the real handler, not _op_skip: a broadcast darken must arm the
	# global field tint (a no-op would leave it null).
	vm._op_color_field(_color_field_inst(1, 0, 0, 0, 0))  # mode 1 = >>1 halve
	_assert_true(vm._field_tint != null, "Color Field armed the global field tint (not a no-op)")


func _test_broadcast_darken_reaches_all_units_and_map() -> void:
	var vm := _make_vm()
	var map := FakeMapComposer.new()
	add_child(map)
	vm.map_composer = map
	var u1 := _add_unit(vm, 3)
	var u2 := _add_unit(vm, 7)
	# Mode 1 (per-channel >>1 halve), snap. scale=0.5, bias=0.
	vm._op_color_field(_color_field_inst(1, 0, 0, 0, 0))
	# Broadcast: EVERY spawned unit's palette-space affine is the field affine.
	_assert_vec_near(_uscale(u1), Vector3.ONE * 0.5, "unit 3 got field scale=0.5")
	_assert_vec_near(_uscale(u2), Vector3.ONE * 0.5, "unit 7 got field scale=0.5")
	_assert_vec_near(_ubias(u1), Vector3.ZERO, "unit 3 got field bias=0")
	# The map palette got the same affine (not a screen filter).
	_assert_true(map.calls > 0, "map_composer received the field broadcast")
	_assert_vec_near(map.last_scale, Vector3.ONE * 0.5, "map got field scale=0.5")
	_assert_vec_near(map.last_bias, Vector3.ZERO, "map got field bias=0")


func _test_ramp_ticks_outside_halt_gate() -> void:
	# The prayer darken/untint must complete even while the VM is halted on a
	# dialog wall — like the oxide/Color-Unit ramps, the field tick runs before
	# the `_running` gate in _tick_once.
	var vm := _make_vm()
	var map := FakeMapComposer.new()
	add_child(map)
	vm.map_composer = map
	var u := _add_unit(vm, 3)
	vm._running = false  # simulate halted-on-dialog
	# Mode 0 add, RGB=(225,225,225) Time=4 → signed(-31)/31 = -1, ramps bias 0→-1.
	vm._op_color_field(_color_field_inst(0, 225, 225, 225, 4))
	var start_bias := _ubias(u)
	for _t in range(32):
		vm._tick_once()
	var end_bias := _ubias(u)
	_assert_true(end_bias.x < start_bias.x - 0.5,
		"unit field bias ramped darker despite _running=false (%s -> %s)"
			% [str(start_bias), str(end_bias)])
	_assert_vec_near(end_bias, Vector3.ONE * -1.0, "mode0 add ramp lands unit bias=-1")
	_assert_vec_near(map.last_bias, Vector3.ONE * -1.0, "map ramped in lockstep to bias=-1")


func _test_untint_restores_identity() -> void:
	var vm := _make_vm()
	var map := FakeMapComposer.new()
	add_child(map)
	vm.map_composer = map
	var u := _add_unit(vm, 3)
	# Darken (snap), then untint via mode 4 RGB=0 (scale=1, bias=0 = identity).
	vm._op_color_field(_color_field_inst(0, 225, 225, 225, 0))  # snap dark
	_assert_vec_near(_ubias(u), Vector3.ONE * -1.0, "unit darkened after snap")
	vm._op_color_field(_color_field_inst(4, 0, 0, 0, 4))        # ramp to identity
	for _t in range(32):
		vm._tick_once()
	_assert_vec_near(_uscale(u), Vector3.ONE, "untint restores unit scale=1")
	_assert_vec_near(_ubias(u), Vector3.ZERO, "untint restores unit bias=0")
	_assert_vec_near(map.last_scale, Vector3.ONE, "untint restores map scale=1")
	_assert_vec_near(map.last_bias, Vector3.ZERO, "untint restores map bias=0")
	_assert_true(vm._field_tint == null or vm._field_tint.is_identity(),
		"field tint cleared/identity after untint")


func _test_time_zero_snaps() -> void:
	var vm := _make_vm()
	var u := _add_unit(vm, 3)
	vm._op_color_field(_color_field_inst(0, 225, 225, 225, 0))  # Time=0 snap
	var b0 := _ubias(u)
	vm._tick_once()  # no ramp pending — bias must not change
	_assert_vec_near(_ubias(u), b0, "Time=0 snaps, no ramp")
	_assert_vec_near(b0, Vector3.ONE * -1.0, "mode0 snap bias = signed(225)/31 = -1")


func _test_field_composes_with_color_unit_tint() -> void:
	# A unit under BOTH a per-unit {32} tint and a broadcast {33} field tint must
	# get the two COMPOSED (field ∘ unit), not clobbered. Unit halve (scale 0.5)
	# then field halve (scale 0.5) → combined scale 0.25.
	var vm := _make_vm()
	var u := _add_unit(vm, 3)
	vm._op_color_unit(_color_unit_inst(3, 1, 0, 0, 0, 0))  # unit scale=0.5
	_assert_vec_near(_uscale(u), Vector3.ONE * 0.5, "unit-only tint scale=0.5")
	vm._op_color_field(_color_field_inst(1, 0, 0, 0, 0))   # field scale=0.5
	_assert_vec_near(_uscale(u), Vector3.ONE * 0.25,
		"field composes with unit tint (0.5*0.5=0.25), not clobbered")


## PSX-parity ground truth (Q3, closed 2026-07-05): live pcsx CLUT-diff across
## the three orbonne_prayer_tint_* savestates proved the whole "view-engine" map
## darkening is a UNIFORM per-channel ADDITIVE offset with 5-bit clamp —
## `dark_entry = clamp(source_entry + offset, 0, 31)`, one offset triple per
## palette-view — NOT a multiplicative scale and NOT a per-entry curve (the earlier
## "brightness curve" read was constant-offset-over-varying-base mistaken for a
## multiplier). That is EXACTLY Godot's {33}/{32} mode-4 affine (scale=1, bias=delta)
## composed with the shader clamp. This test pins Godot's affine to the real
## measured CLUT: applying mode-4 bias=offset to each source entry must reproduce
## the captured dark entry. R/G reconstruct byte-exactly; B carries a +1 floor
## residue at the darkest entries (the 32-step DDA ramp's rounding — tolerated ±1).
## Golden pairs = live VRAM reads (src=02 untinted, dark=01 held).
## Rig: /tmp/clut_clamp_verify.py + extract_golden_pairs.py against port 8080.
func _test_psx_parity_uniform_additive_clamp() -> void:
	# (offset_r,g,b as SIGNED 5-bit) : [ [src_r,g,b, dark_r,g,b], ... ]
	# map palette (VRAM Y=480 x=64), offset (-4,-4,-4):
	var map_off := Vector3i(-4, -4, -4)
	var map_pairs := [
		[23, 24, 25, 19, 20, 21], [17, 16, 15, 13, 12, 11],
		[11, 10, 11, 7, 6, 7], [5, 6, 4, 1, 2, 0],
		[18, 11, 0, 14, 7, 0], [11, 4, 0, 7, 0, 0],
	]
	# sprite palette (VRAM Y=483 x=0), offset (-8,-8,-6):
	var spr_off := Vector3i(-8, -8, -6)
	var spr_pairs := [
		[28, 27, 27, 20, 19, 21], [12, 13, 14, 4, 5, 8],
		[17, 18, 19, 9, 10, 13], [11, 8, 4, 3, 0, 0],
		[22, 18, 6, 14, 10, 0], [28, 22, 16, 20, 14, 10],
	]
	_assert_parity_palette("map", map_off, map_pairs)
	_assert_parity_palette("sprite", spr_off, spr_pairs)


## Feed one palette's (source,dark) pairs through the real ScenarioColorTint mode-4
## affine + shader-equivalent clamp; assert it reproduces the PSX dark CLUT.
func _assert_parity_palette(label: String, off: Vector3i, pairs: Array) -> void:
	# mode-4 with signed bytes that sign-extend to the measured offset.
	var to_byte := func(v: int) -> int: return v & 0xFF
	var tint := Tint.new()
	var luma := tint.apply(4, to_byte.call(off.x), to_byte.call(off.y), to_byte.call(off.z), 0)
	_assert_true(not luma, "%s: mode-4 is uniform-affine (not luma)" % label)
	# mode-4 target: scale=1, bias=offset/31.
	_assert_vec_near(tint.scale, Vector3.ONE, "%s: mode-4 scale=1" % label)
	_assert_vec_near(tint.bias, Vector3(off.x, off.y, off.z) / 31.0, "%s: mode-4 bias=offset/31" % label)
	for p in pairs:
		var src := Vector3(p[0], p[1], p[2]) / 31.0
		var want := Vector3i(p[3], p[4], p[5])
		# Shader math (indexed_color.gdshader:215): clamp(base*scale + bias, 0, 1).
		var lit := (src * tint.scale + tint.bias).clamp(Vector3.ZERO, Vector3.ONE)
		var got := Vector3i(roundi(lit.x * 31.0), roundi(lit.y * 31.0), roundi(lit.z * 31.0))
		# R/G exact; allow +1 on any channel at the DDA floor residue.
		var dr: int = abs(got.x - want.x)
		var dg: int = abs(got.y - want.y)
		var db: int = abs(got.z - want.z)
		_assert_true(dr <= 1 and dg <= 1 and db <= 1,
			"%s parity src=%s got=%s want=%s (Δ%d,%d,%d ≤1)"
				% [label, str(Vector3i(p[0], p[1], p[2])), str(got), str(want), dr, dg, db])


func _test_real_chunk_field_ops_do_not_halt() -> void:
	# The real scenario-1 chunk carries the prayer Color Field ops (indices 22
	# snap, 53 untint ramp, plus others). Before this opcode was implemented the
	# VM halted on the unhandled 'Color Field'; now dispatching them keeps running.
	var vm := _make_vm()
	var ok := vm.load_chunk_json(CHUNK_PATH)
	_assert_true(ok, "loaded real scenario_1_chunk.json")
	if not ok:
		return
	var count := 0
	vm.start()
	for inst in vm._insts:
		if str(inst.get("name", "")) != "Color Field":
			continue
		vm._op_color_field(inst)
		count += 1
		_assert_true(vm._running, "VM still running after a Color Field op")
	_assert_true(count > 0, "chunk contains at least one Color Field op")
