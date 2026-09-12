extends Node
## Tests for ScenarioColorTint's LUMA modes (Color = 2/3/6/7) — the sepia/brown
## "drawn on brown paper" flashback wash ({33} Color Field / {32} Color Unit in
## scenarios 8/14/203/285). Unlike the per-channel affine modes, a luma mode
## converts each palette entry to ONE luminance scalar (a channel mix) and adds a
## per-channel brown delta: `out_ch = (2R + 3G + B)/div + delta_ch`, clamped 5-bit.
## The current per-channel `base*scale + bias` affine cannot express a channel mix,
## so these were stubbed to mode-0 additive; this suite drives the real transform.
##
## Byte-exact ground truth: research/working_documents/COLOR_TINT_LUMA_MODE_SEPIA.md
## §3.4 — the live scenario-8 resident field palette (view 0), matched base->out at
## 227/227 (100%) with div=12, delta=(2,-1)/... The six pairs below are measured
## CLUT bytes read straight off the running game.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioLumaTintTest.tscn

const Tint = preload("res://src/scenarios/ScenarioColorTint.gd")
const Recipe = ExMateriaSchema.ColorRecipe
const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_luma_out5_reproduces_measured_base_to_out()
	_test_apply_sets_luma_spec_per_mode()
	_test_vm_pushes_unit_luma_uniforms()
	_test_field_luma_broadcasts_to_map_and_units()
	_test_unit_luma_wins_over_field_luma()
	_test_luma_ramp_lerps_delta()
	_test_luma_fade_out_cross_fades_to_base()
	_test_vm_pushes_unit_luma_mix_uniform()
	_test_field_luma_fade_broadcasts_mix_to_map()
	_test_vm_also_pushes_unified_color_stack()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioLumaTintTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioLumaTintTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioLumaTintTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioLumaTintTest")
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


## ADR-0067: the VM now pushes the effective {32}∘{33} spec as color_layer_* uniforms
## (unit.gdshader folds them via color_apply) instead of the old unit_luma_*/
## unit_tint_* uniforms. These helpers read the effective luma / affine spec back out
## of the pushed layer arrays so the behavioural assertions below stay meaningful.
func _unit_luma(mat) -> Dictionary:
	var rgb0 = mat.params.get("color_layer_rgb0")
	var rgb1 = mat.params.get("color_layer_rgb1")
	var meta = mat.params.get("color_layer_meta")
	var count: int = mat.params.get("color_layer_count", 0)
	for i in range(count):
		if rgb1[i].w > 0.0:  # luma layer (div in rgb1.w)
			return {
				"div": int(rgb1[i].w),
				"delta5": Vector3i(roundi(rgb0[i].x), roundi(rgb0[i].y), roundi(rgb0[i].z)),
				"from_current": (meta[i] & (1 << 3)) == 0,
				"mix": rgb0[i].w,
			}
	return {"div": 0, "delta5": Vector3i.ZERO, "from_current": false, "mix": 1.0}


func _unit_affine_scale(mat) -> Vector3:
	var rgb0 = mat.params.get("color_layer_rgb0")
	var rgb1 = mat.params.get("color_layer_rgb1")
	var count: int = mat.params.get("color_layer_count", 0)
	for i in range(count):
		if rgb1[i].w == 0.0:  # affine layer (div 0)
			return Vector3(rgb0[i].x, rgb0[i].y, rgb0[i].z)
	return Vector3.ONE


# --- tests -------------------------------------------------------------------

## §3.4 measured pairs: the live scn8 field CLUT (view 0), delta (2,1,-1), div 12.
## `luma_out5` is the byte-exact integer core: L = floor((2R+3G+B)/div), then each
## channel = clamp(L + delta_ch, 0, 31). Must reproduce every measured out byte.
## Oracle = the PRODUCTION core ColorRecipe.luma_out5 (the copy the shipped color
## stack folds), NOT the legacy ScenarioColorTint copy — else a drift in the production
## core passes green against a stale duplicate (review finding #7).
func _test_luma_out5_reproduces_measured_base_to_out() -> void:
	var delta := Vector3i(2, 1, -1)
	# [base_r,g,b, out_r,g,b] — live CLUT bytes (COLOR_TINT_LUMA_MODE_SEPIA.md §3.4).
	var pairs := [
		[4, 4, 3, 3, 2, 0],
		[6, 5, 4, 4, 3, 1],
		[7, 6, 4, 5, 4, 2],
		[11, 12, 10, 7, 6, 4],
		[13, 14, 12, 8, 7, 5],
		[15, 16, 14, 9, 8, 6],
	]
	for p in pairs:
		var base := Vector3i(p[0], p[1], p[2])
		var want := Vector3i(p[3], p[4], p[5])
		var got: Vector3i = Recipe.luma_out5(base, 12, delta)
		_assert_eq(got, want, "luma_out5 base=%s -> out" % str(base))


## apply() must carry a luma SPEC for modes 2/3/6/7 instead of collapsing to
## affine, so the VM can push the real transform to the shader:
##   mode 7 = base luma /12   (the primary sepia; 16 uses)
##   mode 6 = base luma /6
##   mode 3 = current luma /12   (grayscale; reads current, not base)
##   mode 2 = current luma /6
## delta5 is the signed 5-bit RGB delta; non-luma modes leave luma_div == 0.
func _test_apply_sets_luma_spec_per_mode() -> void:
	# mode 7 field op from scn8 PC28: delta (4,3,1), Time=0 snap.
	var t7 = Tint.new()
	var is7 := t7.apply(7, 4, 3, 1, 0)
	_assert_true(is7, "mode 7 reports luma")
	_assert_eq(t7.luma_div, 12, "mode 7 div=12")
	_assert_true(t7.luma_from_base, "mode 7 reads base")
	_assert_eq(t7.luma_delta5, Vector3i(4, 3, 1), "mode 7 delta5=(4,3,1)")

	# mode 6 = base luma /6.
	var t6 = Tint.new()
	t6.apply(6, 255, 0, 2, 0)  # Blue=255 -> -1 signed
	_assert_eq(t6.luma_div, 6, "mode 6 div=6")
	_assert_true(t6.luma_from_base, "mode 6 reads base")
	_assert_eq(t6.luma_delta5, Vector3i(-1, 0, 2), "mode 6 delta5 sign-extends")

	# mode 3 = current luma /12 (reads current, not base).
	var t3 = Tint.new()
	t3.apply(3, 0, 0, 0, 0)
	_assert_eq(t3.luma_div, 12, "mode 3 div=12")
	_assert_true(not t3.luma_from_base, "mode 3 reads current")

	# A non-luma mode leaves luma off (affine path).
	var t1 = Tint.new()
	var is1 := t1.apply(1, 0, 0, 0, 0)
	_assert_true(not is1, "mode 1 is not luma")
	_assert_eq(t1.luma_div, 0, "mode 1 luma_div=0 (affine)")


# --- VM integration ----------------------------------------------------------

class FakeMaterial extends RefCounted:
	var params: Dictionary = {}
	func set_shader_parameter(name: String, value) -> void:
		params[name] = value
	func get_shader_parameter(name: String):
		return params.get(name)

class FakeUnit extends RefCounted:
	var material := FakeMaterial.new()
	var visible: bool = true


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	return vm


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


## A luma {32} Color Unit op must push the luma spec to the sprite shader (so the
## shader takes its luma branch) — NOT collapse to affine — and the tint must
## survive: its affine IS identity, so is_identity() must also honour luma_div.
func _test_vm_pushes_unit_luma_uniforms() -> void:
	var vm := _make_vm()
	var unit := FakeUnit.new()
	vm.units_by_id[29] = unit
	# scn8 PC29-style unit luma: mode 7, delta (4,2,-1), snap.
	vm._op_color_unit(_color_unit_inst(29, 7, 4, 2, 255, 0))
	var lu := _unit_luma(unit.material)
	_assert_eq(lu["div"], 12, "shader got unit luma div=12")
	_assert_eq(lu["delta5"], Vector3i(4, 2, -1), "shader got unit luma delta5")
	_assert_eq(lu["from_current"], false, "mode 7 reads base (from_current=false)")
	# The luma tint must NOT be dropped as identity.
	var actor := vm.peek_actor(29)
	_assert_true(actor != null and actor.tint != null, "luma tint retained (not cleared as identity)")


## Stand-in map composer that records the {33} field color-stack broadcast (ADR-0067).
class FakeMapComposer extends Node:
	var luma_calls: int = 0
	var last_div: int = 0
	var last_delta5: Vector3i = Vector3i.ZERO
	var last_from_current: bool = false
	var last_mix: float = 1.0
	func set_field_color_stack(_s: Vector3, _b: Vector3, div: int, delta5: Vector3i,
			from_current: bool, mix: float) -> void:
		if div > 0:
			luma_calls += 1
		last_div = div
		last_delta5 = delta5
		last_from_current = from_current
		last_mix = mix


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


## A luma {33} Color Field is the whole-scene sepia: it must broadcast the luma
## spec to BOTH the map palette (MapComposer.set_field_luma) and every unit sprite
## (the field luma dominates each unit — scn8 PC28). Delta (4,3,1), mode 7, snap.
func _test_field_luma_broadcasts_to_map_and_units() -> void:
	var vm := _make_vm()
	var map := FakeMapComposer.new()
	add_child(map)
	vm.map_composer = map
	var unit := FakeUnit.new()
	vm.units_by_id[3] = unit
	vm._op_color_field(_color_field_inst(7, 4, 3, 1, 0))
	# Map got the luma broadcast.
	_assert_true(map.luma_calls > 0, "map_composer.set_field_luma was called")
	_assert_eq(map.last_div, 12, "map got field luma div=12")
	_assert_eq(map.last_delta5, Vector3i(4, 3, 1), "map got field luma delta5=(4,3,1)")
	_assert_eq(map.last_from_current, false, "mode 7 field reads base (from_current=false)")
	# Every unit sprite got the field luma too (field dominates the unit).
	var lu := _unit_luma(unit.material)
	_assert_eq(lu["div"], 12, "unit got field luma div=12")
	_assert_eq(lu["delta5"], Vector3i(4, 3, 1), "unit got field luma delta5")


## scn8 ground truth (COLOR_TINT_LUMA_MODE_SEPIA.md §3.1/3.2): the {33} field and
## {32} unit op write DIFFERENT palette views — view 0 (map) = field (4,3,1), view 3
## (unit sprites) = unit-op (4,2,-1). The {32} op fires AFTER the {33} field (PC29 >
## PC28), so per-view last-write-wins: a unit's OWN luma tint must WIN over the field
## luma (else sprites render the field's grayer (4,3,1) instead of the browner
## (4,2,-1)). A unit with NO own tint still falls back to the broadcast field luma.
func _test_unit_luma_wins_over_field_luma() -> void:
	var vm := _make_vm()
	var tinted := FakeUnit.new()     # gets its own {32} luma
	var bare := FakeUnit.new()       # no own tint — falls back to the field
	vm.units_by_id[29] = tinted
	vm.units_by_id[7] = bare
	# PC28: {33} field luma (4,3,1) broadcast to all.
	vm._op_color_field(_color_field_inst(7, 4, 3, 1, 0))
	# PC29: {32} unit luma (4,2,-1) on unit 29 (fires after the field).
	vm._op_color_unit(_color_unit_inst(29, 7, 4, 2, 255, 0))
	# The tinted unit shows ITS OWN delta, not the field's.
	_assert_eq(_unit_luma(tinted.material)["delta5"], Vector3i(4, 2, -1),
		"unit's own {32} luma (4,2,-1) wins over field (4,3,1)")
	_assert_eq(_unit_luma(tinted.material)["div"], 12, "tinted unit div=12")
	# The bare unit still gets the broadcast field luma.
	_assert_eq(_unit_luma(bare.material)["delta5"], Vector3i(4, 3, 1),
		"untinted unit falls back to field luma (4,3,1)")


## scn8: PC28 snaps luma delta (4,3,1); PC38 ramps to (2,1,-1) over Time=4 (32
## frames). The div/mode snap immediately (still luma 7); only the delta lerps —
## the PSX DDA walks each entry linearly to its new luma target, which for a
## fixed-div luma reduces to lerping the delta (COLOR_TINT_LUMA_MODE_SEPIA.md §2.3).
func _test_luma_ramp_lerps_delta() -> void:
	var t = Tint.new()
	t.apply(7, 4, 3, 1, 0)               # snap to (4,3,1)
	_assert_eq(t.luma_delta5, Vector3i(4, 3, 1), "ramp start delta = (4,3,1)")
	t.apply(7, 2, 1, 255, 4)             # ramp to (2,1,-1) over 32 frames
	_assert_eq(t.luma_div, 12, "div stays 12 during luma ramp")
	# Delta must not have snapped to target yet (still near the start).
	_assert_eq(t.luma_delta5, Vector3i(4, 3, 1), "delta held at start on arm (not snapped)")
	var frames := 0
	var reached_mid := false
	while t.tick():
		frames += 1
		# Somewhere mid-ramp the delta is strictly between start and target.
		if t.luma_delta5.x < 4 and t.luma_delta5.x > 2:
			reached_mid = true
		if frames > 64:
			break
	_assert_eq(frames, 32, "luma ramp runs 32 frames (Time=4)")
	_assert_true(reached_mid, "delta lerps through intermediate values")
	_assert_eq(t.luma_delta5, Vector3i(2, 1, -1), "luma ramp lands exactly on (2,1,-1)")


## scn8 PC47/48: after the sepia flashback, {33}/{32} Color=8 Time=8 RESTORE the
## base palette. On PSX this is a per-CLUT-entry DDA that walks each entry from its
## current (sepia-luma) value back to base over 64 frames — a genuine cross-fade,
## NOT a snap. The Godot model keeps the luma branch alive during the ramp and lerps
## a `luma_mix` scalar 1.0 (full sepia) -> 0.0 (base); when it lands the tint collapses
## to the affine base (luma_div == 0) and reads as identity (COLOR_TINT_LUMA_MODE_SEPIA.md
## §2.3, ramp_frames_for_time(8) = 32*(8>>2) = 64).
func _test_luma_fade_out_cross_fades_to_base() -> void:
	var t = Tint.new()
	t.apply(7, 4, 3, 1, 0)               # snap into the sepia flashback wash
	_assert_eq(t.luma_div, 12, "sepia active: div=12")
	_assert_eq(t.luma_mix, 1.0, "sepia active: full luma output (mix=1)")
	# PC47/48 restore: mode 8, Time=8 -> a 64-frame cross-fade back to base.
	t.apply(8, 0, 0, 0, 8)
	# Must NOT snap: the luma branch stays alive so the shader keeps drawing the
	# sepia to fade FROM; only the mix scalar starts walking down.
	_assert_eq(t.luma_div, 12, "fade-out keeps the luma spec alive during the ramp")
	_assert_eq(t.luma_mix, 1.0, "fade-out starts at full sepia (mix=1)")
	var frames := 0
	var reached_mid := false
	while t.tick():
		frames += 1
		if t.luma_mix < 1.0 and t.luma_mix > 0.0:
			reached_mid = true
		if frames > 128:
			break
	_assert_eq(frames, 64, "fade-out runs 64 frames (Time=8)")
	_assert_true(reached_mid, "luma_mix lerps through intermediate values (a real cross-fade)")
	# Landed on base: mix hit 0, the luma branch collapsed, tint reads as identity.
	_assert_eq(t.luma_mix, 0.0, "fade-out lands exactly on base (mix=0)")
	_assert_eq(t.luma_div, 0, "fade-out collapses to the affine path (luma_div=0)")
	_assert_true(t.is_identity(), "restored tint is neutral/identity (safe to drop)")


## The VM must push the cross-fade weight to the sprite shader as `unit_luma_mix`
## (the shader lerps base<->sepia by it). A luma snap pushes 1.0 (full sepia); a
## mode-8 fade-out that's been ticked pushes a value strictly between 1 and 0 — so
## the sprite dissolves back to colour instead of snapping (scn8 PC48).
func _test_vm_pushes_unit_luma_mix_uniform() -> void:
	var vm := _make_vm()
	var unit := FakeUnit.new()
	vm.units_by_id[29] = unit
	# PC29-style sepia snap: mode 7, full luma output.
	vm._op_color_unit(_color_unit_inst(29, 7, 4, 2, 255, 0))
	_assert_eq(_unit_luma(unit.material)["mix"], 1.0, "sepia pushes full luma mix (1.0)")
	# PC48-style restore: mode 8, Time=8 — arms the cross-fade, luma stays alive.
	vm._op_color_unit(_color_unit_inst(29, 8, 0, 0, 0, 8))
	_assert_eq(_unit_luma(unit.material)["div"], 12, "fade keeps unit luma div=12 alive")
	_assert_eq(_unit_luma(unit.material)["mix"], 1.0, "fade arms at full sepia (mix=1.0)")
	# Advance the fade one tick and re-push: the mix must be decreasing, not snapped.
	var actor := vm.peek_actor(29)
	actor.tint.tick()
	vm._apply_unit_tint(29, actor.tint)
	var mixed = _unit_luma(unit.material)["mix"]
	_assert_true(mixed < 1.0 and mixed > 0.0, "ticking the fade pushes a decreasing mix (%s)" % str(mixed))


## The {33} field restore (scn8 PC47) must broadcast the same cross-fade to the MAP
## palette: MapComposer.set_field_luma gets the mix weight so the map's sepia CLUT
## dissolves back to base in step with the sprites — not a snap.
func _test_field_luma_fade_broadcasts_mix_to_map() -> void:
	var vm := _make_vm()
	var map := FakeMapComposer.new()
	add_child(map)
	vm.map_composer = map
	# PC28: field sepia snap (mode 7).
	vm._op_color_field(_color_field_inst(7, 4, 3, 1, 0))
	_assert_eq(map.last_mix, 1.0, "sepia field broadcasts full luma mix (1.0)")
	# PC47: field restore mode 8, Time=8 — arms the cross-fade, luma stays alive.
	vm._op_color_field(_color_field_inst(8, 0, 0, 0, 8))
	_assert_eq(map.last_div, 12, "field fade keeps map luma div=12 alive")
	_assert_eq(map.last_mix, 1.0, "field fade arms at full sepia (mix=1.0)")
	# Advance the field fade one tick and re-broadcast: mix decreasing, not snapped.
	vm._field_tint.tick()
	vm._apply_field_tint_to_all()
	_assert_true(map.last_mix < 1.0 and map.last_mix > 0.0,
		"ticking the field fade broadcasts a decreasing map mix (%s)" % str(map.last_mix))


## ADR-0067: the VM pushes the effective {32}∘{33} spec as unified color-stack uniforms
## (color_layer_*), which unit.gdshader folds via color_apply (byte-exact per
## ColorStack's parity oracle). A sepia unit -> 2 layers (affine below + luma), luma
## div in rgb1[1].w.
func _test_vm_also_pushes_unified_color_stack() -> void:
	var vm := _make_vm()
	var unit := FakeUnit.new()
	vm.units_by_id[29] = unit
	vm._op_color_unit(_color_unit_inst(29, 7, 4, 2, 255, 0))  # mode 7 sepia snap
	var p := unit.material.params
	_assert_eq(p.get("color_layer_count"), 2, "sepia -> affine + luma = 2 color layers")
	var rgb1 = p.get("color_layer_rgb1")
	_assert_true(rgb1 is PackedVector4Array, "color_layer_rgb1 pushed as PackedVector4Array")
	_assert_eq(rgb1[1].w, 12.0, "luma layer div=12 in rgb1[1].w")
	var rgb0 = p.get("color_layer_rgb0")
	_assert_eq(Vector3(rgb0[1].x, rgb0[1].y, rgb0[1].z), Vector3(4, 2, -1), "luma delta5 in rgb0[1].xyz")
