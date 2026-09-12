extends Node
## Tests for TintedSurfaces' ADR-0067 combat route (issue #164). The registry no
## longer writes the additive `unit_tint` uniform — it concatenates each effect
## owner's ColorStack snapshot into the unified `color_layer_*` uniforms so combat
## palette effects fold through color_apply over the real ALBEDO at 5-bit
## fidelity. update_layer(delta) stays as an additive bridge (TrapPaletteController).
##
## 🔴 THE FILE IS STILL CALLED `UnitTintOverlayTest` AND THAT IS A DECIDED
## SCOPE BOUNDARY, NOT AN OVERSIGHT (#1223). `docs/TEST-BASELINE-E2.tsv` is a FROZEN
## measurement whose header ledgers are `# deleted` and `# moved` — there is no
## `# renamed` kind, and `tools/check_test_baseline.py`'s own docstring says a frozen
## measurement cannot be re-frozen. Renaming this file would therefore need a new
## ledger kind in a register #1223 does not own, and the rename is not in #1223's
## acceptance criteria. #1224 adds the erased-key test for the merged registry and is
## where the naming settles. Everything INSIDE this file names `TintedSurfaces`, so
## there is no stale citation in code — only a filename that describes the subject's
## previous name.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/UnitTintOverlayTest.tscn

const TintedSurfacesScript = preload("res://addons/exmateria_effects/overlay/TintedSurfaces.gd")
const PaletteSubsystem = ExMateriaEffects.PaletteSubsystem
const PaletteData = ExMateriaEffects.PaletteData
const ColorStack = ExMateriaSchema.ColorStack

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_single_owner_stack_pushes_color_layers()
	_test_two_owners_concatenate()
	_test_additive_bridge_pushes_one_affine()
	_test_removing_last_owner_clears_the_stack()

	print("\n=== UnitTintOverlayTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] UnitTintOverlayTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] UnitTintOverlayTest")
		get_tree().quit(1)
	else:
		print("[PASS] UnitTintOverlayTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_vec4_approx(got: Vector4, want: Vector4, name: String) -> void:
	if got.is_equal_approx(want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


## Records shader-parameter sets so we can assert what the overlay pushed. Injected
## directly into the registry's material map to sidestep the typed register_surface().
class FakeMaterial extends RefCounted:
	var params: Dictionary = {}
	func set_shader_parameter(name: String, value) -> void:
		params[name] = value


func _make_overlay_with_unit(surface_id: int) -> Array:
	var overlay = TintedSurfacesScript.new()
	var mat := FakeMaterial.new()
	# #1224: a surface's slot is an ARRAY of materials, not one material.
	overlay._surface_materials[surface_id] = [mat]
	overlay._active_layers[surface_id] = {}
	return [overlay, mat]


func _stack_mode0(r: int) -> ColorStack:
	var pal = PaletteSubsystem.new()
	pal.initialize(_palette_one(0, r, 0, 0))
	return pal.build_stack(PaletteData.CASTER)


func _palette_one(mode: int, r: int, g: int, b: int) -> PaletteData:
	return PaletteData.from_json({
		"for_each": {"caster": {
			"context": "for_each", "channel_name": "caster", "max_keyframe": 2,
			"keyframes": [{
				"index": 0, "time_value": 0, "duration_frames": 1,
				"rgb": [r, g, b], "ctrl": 0x80 | mode, "enabled": true, "blend_mode": mode,
			}],
		}}
	})


# --- tests -------------------------------------------------------------------

## A single owner's ColorStack snapshot is pushed as color_layer_* with quantize
## true (palette applier is 5-bit) — NOT the retired additive unit_tint uniform.
func _test_single_owner_stack_pushes_color_layers() -> void:
	var pair := _make_overlay_with_unit(101)
	var overlay = pair[0]
	var mat = pair[1]
	overlay.update_stack(101, 7, _stack_mode0(4), 0)
	_assert_eq(mat.params.get("color_layer_count"), 1, "one owner -> one layer")
	_assert_eq(mat.params.get("quantize"), true, "palette route quantizes (5-bit)")
	_assert_vec4_approx(mat.params.get("color_layer_rgb1")[0], Vector4(4.0 / 31.0, 0.0, 0.0, 0.0),
		"additive bias = +4/31 R")
	_assert_eq(mat.params.has("unit_tint"), false, "does NOT write the retired unit_tint uniform")


## Two owners' snapshots concatenate into two layers.
func _test_two_owners_concatenate() -> void:
	var pair := _make_overlay_with_unit(102)
	var overlay = pair[0]
	var mat = pair[1]
	overlay.update_stack(102, 1, _stack_mode0(4), 0)
	overlay.update_stack(102, 2, _stack_mode0(8), 0)
	_assert_eq(mat.params.get("color_layer_count"), 2, "two owners -> two concatenated layers")


## update_layer(delta) is the additive bridge (TrapPaletteController): one scale=1
## affine layer whose bias is the delta — folds to base + delta through the stack.
func _test_additive_bridge_pushes_one_affine() -> void:
	var pair := _make_overlay_with_unit(103)
	var overlay = pair[0]
	var mat = pair[1]
	overlay.update_layer(103, 9, Color(0.2, -0.1, 0.0))
	_assert_eq(mat.params.get("color_layer_count"), 1, "additive bridge -> one layer")
	_assert_vec4_approx(mat.params.get("color_layer_rgb0")[0], Vector4(1.0, 1.0, 1.0, 1.0),
		"additive bridge scale = 1, progress = 1")
	_assert_vec4_approx(mat.params.get("color_layer_rgb1")[0], Vector4(0.2, -0.1, 0.0, 0.0),
		"additive bridge bias = the delta")


## Removing the last owner clears the stack to a true no-op: count 0 AND quantize
## false, so the idle unit doesn't 5-bit-quantize its base.
func _test_removing_last_owner_clears_the_stack() -> void:
	var pair := _make_overlay_with_unit(104)
	var overlay = pair[0]
	var mat = pair[1]
	overlay.update_stack(104, 5, _stack_mode0(4), 0)
	overlay.remove_layer(104, 5)
	_assert_eq(mat.params.get("color_layer_count"), 0, "no owners -> count 0")
	_assert_eq(mat.params.get("quantize"), false, "no owners -> quantize false (no-op)")
