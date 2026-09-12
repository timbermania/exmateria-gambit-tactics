extends Node
## Tests for event opcode {0x66} "Commit Palette" — the map-palette-commit that
## folds the live {33} Color Field field-tint into the BASE map palette so the
## tint PERSISTS (PSX FUN_8008f63c copies the working CLUT strip → base). This is
## the entire scenario-3/4/5/6 "map has the wrong hue / missing blue" bug: Godot
## shipped the {33} field tint as a transient shader uniform but never committed
## it, so a later flash's mode-8 restore snapped the map back to the raw warm
## palette instead of the committed blue.
##
## RE (byte-exact, static + dynamic): research/working_documents/
## MAP_HUE_WEATHER_STATE_CLUT_BAKE.md §0. For scenario_004_chunk: PC12 {33}
## mode-4 (−3,−1,+3) tints the working CLUT blue; PC14 {0x66} commits it into the
## base. Godot analogue: fold the field-tint affine into MapComposer.palette_texture.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioCommitPaletteTest.tscn

## The host's declared mount for the addon's map composer (ADR-0207 dec. 1). A `.tscn`
## `ext_resource` names a path, never a `class_name`, so the mount is a SCENE — and
## `instantiate()` hands back the same unparented `Node3D` carrying `MapComposer.gd` that
## `MapComposerScript.new()` did, already named `ProceduralMap`, with `_ready` still unfired.
const ProceduralMapScene := preload("res://assets/scenes/ProceduralMap.tscn")
const ScenarioVMClass := preload("res://src/scenarios/ScenarioVM.gd")
const RecipeScript := ExMateriaSchema.ColorRecipe

# pal0, BGR555 (live PSX dumps — the assertion targets, handoff §"reference values").
# Warm base = current Godot palette_texture (the bug); Blue = committed base
# (PSX DAT_80099d76 == VRAM row Y=494) = warm + (−3,−1,+3) per opaque 5-bit entry.
const WARM := [0x7C00, 0x0864, 0x0CA6, 0x10C7, 0x14E8, 0x192A, 0x256C, 0x2DAF,
	0x3612, 0x3E76, 0x46D9, 0x00A4, 0x04E6, 0x0507, 0x0928, 0x0D6B]
const BLUE := [0x7C00, 0x1441, 0x1883, 0x1CA4, 0x20C5, 0x2507, 0x3149, 0x398C,
	0x41EF, 0x4A53, 0x52B6, 0x0C81, 0x10C3, 0x10E4, 0x1505, 0x1948]

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


## Stand-in for MapComposer: records commit_field_tint / set_field_tint broadcasts
## so the VM-level test can assert the commit fired with the live field affine and
## the field-tint was then reset to identity.
class FakeMapComposer extends Node:
	var commit_scale: Vector3 = Vector3.ZERO
	var commit_bias: Vector3 = Vector3.ZERO
	var commit_div: int = 0
	var commit_delta5: Vector3i = Vector3i.ZERO
	var commit_calls: int = 0
	var last_field_scale: Vector3 = Vector3.ONE
	var last_field_bias: Vector3 = Vector3.ZERO
	func commit_field_tint(scale: Vector3, bias: Vector3, div: int = 0,
			delta5: Vector3i = Vector3i.ZERO, _from_current: bool = false, _mix: float = 1.0) -> void:
		commit_scale = scale
		commit_bias = bias
		commit_div = div
		commit_delta5 = delta5
		commit_calls += 1
	func set_field_tint(scale: Vector3, bias: Vector3) -> void:
		last_field_scale = scale
		last_field_bias = bias


func _ready() -> void:
	_test_bake_folds_warm_into_committed_blue()
	_test_commit_field_tint_bakes_palette_texture()
	_test_op_commit_palette_commits_and_resets_field()
	_test_op_commit_palette_resolves_inflight_ramp()
	_test_flash_restore_lands_on_committed_blue_not_warm()
	_test_commit_field_tint_bakes_luma_wash()
	_test_op_commit_palette_commits_luma_field()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioCommitPaletteTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioCommitPaletteTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioCommitPaletteTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCommitPaletteTest")
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


func _color_field_inst(mode: int, r: int, g: int, b: int, time: int) -> Dictionary:
	return {
		"name": "Color Field", "opcode": 0x33, "offset": 0,
		"params": [
			{"name": "Color", "value": mode}, {"name": "Red", "value": r},
			{"name": "Green", "value": g}, {"name": "Blue", "value": b},
			{"name": "Time", "value": time},
		],
	}


# --- BGR555 <-> RGBA8 helpers (5-bit ch = round(8bit * 31/255)) ---------------

static func _bgr555_to_color(v: int) -> Color:
	var r5 := v & 0x1F
	var g5 := (v >> 5) & 0x1F
	var b5 := (v >> 10) & 0x1F
	return Color8(roundi(r5 * 255.0 / 31.0), roundi(g5 * 255.0 / 31.0),
		roundi(b5 * 255.0 / 31.0), 255)


static func _color_to_bgr555(c: Color) -> int:
	var r5 := roundi(c.r * 31.0)
	var g5 := roundi(c.g * 31.0)
	var b5 := roundi(c.b * 31.0)
	return (b5 << 10) | (g5 << 5) | r5


static func _row_to_image(row: Array) -> Image:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for x in range(16):
		img.set_pixel(x, 0, _bgr555_to_color(row[x]))
	return img


# --- tests -------------------------------------------------------------------

## The pure fold: folding the warm base row through the {33} mode-4 field affine
## (scale=1, bias=(−3,−1,+3)/31) with 5-bit clamp must reproduce the committed
## blue base row byte-exactly (per opaque entry). This is the whole fix, in one
## pure function — no scene, no VM.
func _test_bake_folds_warm_into_committed_blue() -> void:
	var src := _row_to_image(WARM)
	var scale := Vector3.ONE
	var bias := Vector3(-3, -1, 3) / 31.0
	# `bake_field_tint` is STATIC, and a `PackedScene` hands out a node rather than a
	# script — so the one static reach in this file goes through an instance. This is the
	# single place the scene mount fits worse than the script preload did (ADR-0207 dec. 3).
	var probe = ProceduralMapScene.instantiate()
	var baked: Image = probe.bake_field_tint(src, scale, bias)
	probe.free()
	_assert_true(baked != null, "bake_field_tint returned an image")
	if baked == null:
		return
	_assert_eq(baked.get_width(), 16, "baked width preserved")
	for x in range(16):
		var got := _color_to_bgr555(baked.get_pixel(x, 0))
		_assert_eq(got, BLUE[x], "entry %d folds warm 0x%04X -> blue 0x%04X" % [x, WARM[x], BLUE[x]])


## The commit behaviour on a MapComposer: given a warm palette_texture and the
## live field affine, commit_field_tint rewrites palette_texture IN PLACE to the
## blue committed base (so every geometry material referencing it samples blue).
func _test_commit_field_tint_bakes_palette_texture() -> void:
	var mc = ProceduralMapScene.instantiate()  # not add_child'd: _ready()/_build_map must not fire
	mc.palette_texture = ImageTexture.create_from_image(_row_to_image(WARM))
	mc.commit_field_tint(Vector3.ONE, Vector3(-3, -1, 3) / 31.0)
	var img: Image = mc.palette_texture.get_image()
	for x in range(16):
		var got := _color_to_bgr555(img.get_pixel(x, 0))
		_assert_eq(got, BLUE[x], "committed palette_texture entry %d == blue 0x%04X" % [x, BLUE[x]])
	mc.free()


## VM dispatch of {0x66}: with a live {33} field tint armed (scn4 PC12 mode-4
## (−3,−1,+3)), dispatching Commit Palette must (1) call map_composer.commit_field_tint
## with that live affine, and (2) reset the field tint to identity so a later
## flash restore lands on the committed base — the map's set_field_tint is left at
## identity and _field_tint is cleared.
func _test_op_commit_palette_commits_and_resets_field() -> void:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	var map := FakeMapComposer.new()
	add_child(map)
	vm.map_composer = map
	# Handler is bound to the real op, not skipped.
	_assert_true(vm._handlers.has(0x66), "0x66 handler registered")
	if vm._handlers.has(0x66):
		_assert_eq(vm._handlers[0x66].get_method(), "_op_commit_palette", "0x66 -> _op_commit_palette (not skip)")
	# Arm the scn4 PC12 field tint: mode-4 (−3,−1,+3) signed bytes, snap.
	vm._op_color_field(_color_field_inst(4, 0xFD, 0xFF, 0x03, 0))
	var want_bias := Vector3(-3, -1, 3) / 31.0
	_assert_vec_near(vm._field_tint.bias, want_bias, "field armed at bias (−3,−1,+3)/31")
	# Dispatch Commit Palette.
	vm._op_commit_palette({"name": "Commit Palette", "opcode": 0x66, "offset": 0, "params": []})
	_assert_eq(map.commit_calls, 1, "commit_field_tint called once")
	_assert_vec_near(map.commit_scale, Vector3.ONE, "committed with field scale=1")
	_assert_vec_near(map.commit_bias, want_bias, "committed with field bias (−3,−1,+3)/31")
	# Field tint reset to identity (now lives in the baked base).
	_assert_true(vm._field_tint == null or vm._field_tint.is_identity(), "field tint cleared after commit")
	_assert_vec_near(map.last_field_scale, Vector3.ONE, "map field-tint reset to scale=1")
	_assert_vec_near(map.last_field_bias, Vector3.ZERO, "map field-tint reset to bias=0")


## {66} committed MID-RAMP must bake the ramp's RESOLVED TARGET, not a half-faded
## frame. The scn10→11 "map is blue" bug: scn10 sets a blue {33} field (PC6), then
## ramps it → neutral (PC15-16, Time>0), then commits (PC18). A fast-forward path
## walk — or any ramp that outlasts its pre-commit {E5} wait — reaches {66} before
## the DDA finishes, so it baked a half-faded blue (live capture: bias≈(−0.53,−0.53,0)
## at ramp 34/64). On PSX the pre-commit wait guarantees the ramp settled, so the
## committed CLUT is always the target — the fix snaps the ramp on commit.
func _test_op_commit_palette_resolves_inflight_ramp() -> void:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	var map := FakeMapComposer.new()
	add_child(map)
	vm.map_composer = map
	# scn10 PC6: instant blue field — mode-4, (225,225,0) = signed (−31,−31,0) kills R,G.
	vm._op_color_field(_color_field_inst(4, 225, 225, 0, 0))
	# scn10 PC15-16: ramp back to neutral (mode-4 (0,0,0)) over Time>0 — DO NOT tick,
	# so the current tint is still ~blue while the ramp is in flight.
	vm._op_color_field(_color_field_inst(4, 0, 0, 0, 8))
	_assert_true(vm._field_tint.bias.x < -0.1,
		"pre-commit: ramp in flight, current bias still bluish (%.3f)" % vm._field_tint.bias.x)
	# scn10 PC18: commit MID-RAMP. Must bake the RESOLVED neutral target, not the
	# half-faded blue (the bug: without resolve() this commits bias≈(−0.53,−0.53,0)).
	vm._op_commit_palette({"name": "Commit Palette", "opcode": 0x66, "offset": 0, "params": []})
	_assert_vec_near(map.commit_scale, Vector3.ONE, "mid-ramp commit bakes resolved scale=1")
	_assert_vec_near(map.commit_bias, Vector3.ZERO,
		"mid-ramp commit bakes RESOLVED neutral bias, not the half-faded blue")


## The end-to-end regression the whole fix exists for, on a REAL MapComposer: the
## scenario_004 sequence is PC12 {33} tint → PC14 {0x66} commit → later a flash's
## mode-8 restore. BEFORE the fix, the blue lived only in the transient field-tint
## uniform, so the mode-8 restore snapped the map back to the raw WARM palette.
## AFTER the fix, {0x66} bakes blue into palette_texture, so the restore lands on
## the committed BLUE base. Asserts the palette at each beat.
func _test_flash_restore_lands_on_committed_blue_not_warm() -> void:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	var mc = ProceduralMapScene.instantiate()  # real composer, no geometry_mesh (set_field_tint no-ops)
	mc.palette_texture = ImageTexture.create_from_image(_row_to_image(WARM))
	vm.map_composer = mc
	# PC12 {33} mode-4 (−3,−1,+3): arms the transient field tint but does NOT bake —
	# the base palette is still warm at this point.
	vm._op_color_field(_color_field_inst(4, 0xFD, 0xFF, 0x03, 0))
	_assert_eq(_color_to_bgr555(mc.palette_texture.get_image().get_pixel(1, 0)), WARM[1],
		"{33} alone does not persist: palette still warm before commit")
	# PC14 {0x66} commit → palette baked blue.
	vm._op_commit_palette({"name": "Commit Palette", "opcode": 0x66, "offset": 0, "params": []})
	_assert_eq(_color_to_bgr555(mc.palette_texture.get_image().get_pixel(1, 0)), BLUE[1],
		"commit bakes palette blue")
	# Later flash mode-8 restore (scale=1, bias=0 identity) → the map must stay BLUE,
	# not snap back to warm (the bug).
	vm._op_color_field(_color_field_inst(8, 0, 0, 0, 0))
	var pal1 := _color_to_bgr555(mc.palette_texture.get_image().get_pixel(1, 0))
	_assert_eq(pal1, BLUE[1], "flash restore lands on committed blue, not warm")
	_assert_true(pal1 != WARM[1], "flash restore did NOT snap back to warm (the fix)")
	mc.free()


# --- luma commit (a sepia/grey {33} field committed via {66}) -----------------

## The committed BGR555 for one warm entry under a base-luma field: decode to 5-bit,
## apply luma_out5, re-encode. The oracle for a {66} commit over a mode-6/7 field.
static func _luma_want_bgr555(v: int, div: int, delta5: Vector3i) -> int:
	var base5 := Vector3i(v & 0x1F, (v >> 5) & 0x1F, (v >> 10) & 0x1F)
	var o: Vector3i = RecipeScript.luma_out5(base5, div, delta5)
	return (o.z << 10) | (o.y << 5) | o.x


## {66} over a LUMA {33} field (the sepia/brown flashback wash, scenarios 8/14/203/285)
## must bake the wash into the base palette, exactly as an affine field commits. Before
## the fix commit_field_tint carried only (scale,bias) so a luma field committed as
## identity — the palette stayed warm and a later mode-8 restore snapped off the sepia.
func _test_commit_field_tint_bakes_luma_wash() -> void:
	var div := 12
	var delta5 := Vector3i(4, 3, 1)  # mode-7 base luma /12
	var mc = ProceduralMapScene.instantiate()
	mc.palette_texture = ImageTexture.create_from_image(_row_to_image(WARM))
	# from_current = false -> luma reads the base colour (modes 6/7).
	mc.commit_field_tint(Vector3.ONE, Vector3.ZERO, div, delta5, false, 1.0)
	var img: Image = mc.palette_texture.get_image()
	var any_changed := false
	for x in range(16):
		var got := _color_to_bgr555(img.get_pixel(x, 0))
		var want := _luma_want_bgr555(WARM[x], div, delta5)
		_assert_eq(got, want, "luma commit entry %d bakes luma_out5 (0x%04X)" % [x, want])
		if want != WARM[x]:
			any_changed = true
	_assert_true(any_changed, "luma commit actually altered the palette (not identity)")
	mc.free()


## VM dispatch of {66} with a LUMA {33} field armed must forward the full luma spec to
## the commit — not just an affine shape. Arms mode-7 sepia, dispatches Commit Palette
## on a REAL MapComposer, and asserts the base palette holds the sepia wash after.
func _test_op_commit_palette_commits_luma_field() -> void:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	var mc = ProceduralMapScene.instantiate()
	mc.palette_texture = ImageTexture.create_from_image(_row_to_image(WARM))
	vm.map_composer = mc
	# Arm a mode-7 base-luma sepia field (div=12, delta5 = signed (4,3,1)).
	vm._op_color_field(_color_field_inst(7, 4, 3, 1, 0))
	_assert_eq(vm._field_tint.luma_div, 12, "mode-7 field armed as luma div=12")
	vm._op_commit_palette({"name": "Commit Palette", "opcode": 0x66, "offset": 0, "params": []})
	var img: Image = mc.palette_texture.get_image()
	for x in range(16):
		var got := _color_to_bgr555(img.get_pixel(x, 0))
		var want := _luma_want_bgr555(WARM[x], 12, Vector3i(4, 3, 1))
		_assert_eq(got, want, "{66} commits luma field entry %d (0x%04X)" % [x, want])
	mc.free()
