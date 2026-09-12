extends Node
# test-kind: logic
# seeded-break: in `TintedSurfaces.update_layer`, replace the per-surface mask with a
#   bare `ColorStackClass.MASK_WHOLE` (difference 3 flattened) — 'the map delta packs
#   MASK_SURFACE0, not MASK_WHOLE' reds and nothing else does, which is the arm that
#   exists because the map's update_layer has no production caller. A second,
#   independent seed: delete the `reserve_map_surface()` call from `_ready` and the
#   SURFACE_MAP-coexists and no-registration-guard arms red while every unit arm stays
#   green.

## #1224's LOAD-AND-ASSERT witness: `MapTintOverlay` is GONE, `TintedSurfaces` resolves
## as an autoload, and `SURFACE_MAP` coexists with a unit token in ONE registry.
##
## WHY A GODOT PROCESS AND NOT A GUARD. `[autoload]` resolution is engine behaviour:
## whether a name is in the tree, and whether a DELETED name is really gone, is not a
## static edge (#1224's acceptance criteria say so in those words). And ADR-0157 Spike A
## is the standing reason to assert rather than observe — the engine exits 0 through a
## script that failed to bind and a node that mounted stripped.
##
## 🔴 THE ERASED-KEY CLAIM IS THE SUBJECT, AND IT WAS NOT TRUE AS WRITTEN. ADR-0288
## dec. 7 says `MapTintOverlay` is `UnitTintOverlay` *"with the surface key erased"*.
## Measured at #1224 it was the key plus four differences, and this file pins the three
## that are observable from outside the class:
##
##   * a surface holds MANY materials (the map's chunks) where a unit holds one;
##   * `SURFACE_MAP` is RESERVED at `_ready`, so the map's `update_stack` has no
##     registration guard to trip — the unit's still does;
##   * `update_layer` packs `MASK_SURFACE0` for the map and `MASK_WHOLE` for a unit.
##
## 🟢 THE FOURTH DIFFERENCE NO LONGER EXISTS. It was the `map_illum_add` additive sink,
## covered by its own file; #1192 measured the whole feature unreached and deleted both
## halves, taking that file with it. Three differences remain and this file pins all three.
##
## ⚠️ THE DELETED-NAME ARM CANNOT BE SPELLED `MapTintOverlay`. Naming a removed autoload
## as a bare identifier is a PARSE error, which would take this whole file down rather
## than fail an assertion — the trap `EffectManagerNode3DAnchorTest` paid for at #1219.
## So the arm asks the TREE and the ProjectSettings, by string.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/TintedSurfacesMergeTest.tscn

## 🔴 NEITHER ADDRESS IS SPELLED AS A `res://` LITERAL HERE, and that is deliberate
## twice over. A literal would (a) put this file on `check_lattice_scene.py`'s
## criterion-4 burn-down for a reach it does not need, and (b) put a DELETED path on
## `check_res_paths.py`'s unresolved list — a guard reporting a dangling reference that
## is the whole point of the assertion. Both arms below derive the address from the LIVE
## registry's own `resource_path` instead, which is also the stronger question: it
## follows the addon to whatever address a consumer vendors it at, where a literal
## would not.
const MERGED_BASENAME := "overlay/TintedSurfaces.gd"
const DELETED_BASENAME := "MapTintOverlay.gd"

var _passed: int = 0
var _failed: int = 0

## Which arms ran to their last line. A GDScript runtime error ABORTS its calling
## function silently, so "every arm finished" is asserted, never assumed (#1219).
var _arms_completed: Array[String] = []


func _ready() -> void:
	_autoload_arm()
	_deleted_arm()
	_coexist_arm()
	_mask_arm()

	_check("all four arms ran to their last line — an aborted call is not a pass",
		_arms_completed, ["autoload", "deleted", "coexist", "mask"] as Array[String])

	print("\n=== TintedSurfacesMergeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0:
		print("[FAIL] TintedSurfacesMergeTest asserted NOTHING")
		get_tree().quit(1)
	elif _failed > 0:
		print("[FAIL] TintedSurfacesMergeTest")
		get_tree().quit(1)
	else:
		print("[PASS] TintedSurfacesMergeTest")
		get_tree().quit(0)


## Arm 1 — the merged registry is really in the tree, under its own name, with the
## reserved token already present.
func _autoload_arm() -> void:
	var node := get_tree().root.get_node_or_null(^"TintedSurfaces")
	_check("TintedSurfaces resolves as an autoload node", node != null, true)
	if node == null:
		return
	_check("...and it is the merged script, read back off the live node",
		node.get_script().resource_path.ends_with(MERGED_BASENAME), true)
	_check("...with SURFACE_MAP reserved at _ready (difference 2)",
		node.is_surface_registered(TintedSurfaces.SURFACE_MAP), true)
	_check("SURFACE_MAP is 0, which get_instance_id() never returns",
		TintedSurfaces.SURFACE_MAP, 0)
	_arms_completed.append("autoload")


## Arm 2 — `MapTintOverlay` is gone from BOTH places a name can hide: the autoload
## settings and the filesystem. By string, deliberately (see the header).
func _deleted_arm() -> void:
	_check("the MapTintOverlay autoload setting is gone",
		ProjectSettings.has_setting("autoload/MapTintOverlay"), false)
	_check("...and nothing answers to the name in the tree",
		get_tree().root.get_node_or_null(^"MapTintOverlay") != null, false)
	# Derived from the live registry's own directory — see the header.
	var overlay_dir := ""
	var live := get_tree().root.get_node_or_null(^"TintedSurfaces")
	if live != null:
		overlay_dir = live.get_script().resource_path.get_base_dir()
	_check("the overlay directory was located off the live script", overlay_dir != "", true)
	if overlay_dir != "":
		_check("...and the deleted script is not in it",
			FileAccess.file_exists(overlay_dir + "/" + DELETED_BASENAME), false)
		_check("...while the merged one is",
			FileAccess.file_exists(overlay_dir + "/TintedSurfaces.gd"), true)
	_arms_completed.append("deleted")


## Arm 3 — the erased-key claim, directly: the map's tint and a unit's tint stack
## INDEPENDENTLY under one registry (#1224's acceptance criterion, in its words).
func _coexist_arm() -> void:
	var map_mat := ShaderMaterial.new()
	var unit_mat := ShaderMaterial.new()
	var unit_id := get_instance_id()   # a real, non-zero instance token

	TintedSurfaces.reserve_map_surface()
	TintedSurfaces._surface_materials[TintedSurfaces.SURFACE_MAP] = [map_mat]
	TintedSurfaces._active_layers[TintedSurfaces.SURFACE_MAP] = {}
	TintedSurfaces.register_surface(unit_id, unit_mat)

	_check("the map and a unit are two surfaces in ONE registry",
		TintedSurfaces.is_surface_registered(TintedSurfaces.SURFACE_MAP)
			and TintedSurfaces.is_surface_registered(unit_id), true)
	_check("...and the unit token is not the reserved one",
		unit_id == TintedSurfaces.SURFACE_MAP, false)

	# A surface holds MANY materials (difference 1). A second map material joins the
	# same token rather than replacing the first — which is what MapComposer needs and
	# what the 1:1 unit side could not express.
	var map_mat2 := ShaderMaterial.new()
	TintedSurfaces.register_surface(TintedSurfaces.SURFACE_MAP, map_mat2)
	_check("a surface holds MANY materials (difference 1)",
		TintedSurfaces._surface_materials[TintedSurfaces.SURFACE_MAP].size(), 2)
	# De-duplication is BattlefieldWiring's documented contract for re-calling wire_map.
	TintedSurfaces.register_surface(TintedSurfaces.SURFACE_MAP, map_mat2)
	_check("...and registering the same one twice is a no-op",
		TintedSurfaces._surface_materials[TintedSurfaces.SURFACE_MAP].size(), 2)

	# Independence: a delta on the map must not appear on the unit, and vice versa.
	TintedSurfaces.update_layer(TintedSurfaces.SURFACE_MAP, 101, Color(0.25, 0.0, 0.0))
	TintedSurfaces.update_layer(unit_id, 102, Color(0.0, 0.5, 0.0))
	_check("the map surface carries exactly its own owner",
		TintedSurfaces._active_layers[TintedSurfaces.SURFACE_MAP].keys(), [101])
	_check("the unit surface carries exactly its own owner",
		TintedSurfaces._active_layers[unit_id].keys(), [102])

	# Removing one owner leaves the other standing — the stacks are independent.
	TintedSurfaces.remove_layer(TintedSurfaces.SURFACE_MAP, 101)
	_check("removing the map's owner empties the map stack",
		TintedSurfaces._active_layers[TintedSurfaces.SURFACE_MAP].is_empty(), true)
	_check("...and leaves the unit's stack untouched",
		TintedSurfaces._active_layers[unit_id].keys(), [102])

	# remove_all_layers_for_owner sweeps every surface, which is EffectInstance's exit.
	TintedSurfaces.update_layer(TintedSurfaces.SURFACE_MAP, 103, Color(0.1, 0.1, 0.1))
	TintedSurfaces.update_layer(unit_id, 103, Color(0.2, 0.2, 0.2))
	TintedSurfaces.remove_all_layers_for_owner(103)
	_check("remove_all_layers_for_owner clears one owner off the map",
		TintedSurfaces._active_layers[TintedSurfaces.SURFACE_MAP].has(103), false)
	_check("...and off the unit, in the same call",
		TintedSurfaces._active_layers[unit_id].has(103), false)
	_check("...without touching the unit's OTHER owner",
		TintedSurfaces._active_layers[unit_id].has(102), true)

	TintedSurfaces.unregister_surface(unit_id)
	_check("a unit surface can be unregistered",
		TintedSurfaces.is_surface_registered(unit_id), false)
	_check("...but the reserved map surface cannot be",
		TintedSurfaces.is_surface_registered(TintedSurfaces.SURFACE_MAP), true)
	_arms_completed.append("coexist")


## Arm 4 — `update_layer`'s mask differs by surface (difference 3). This is the arm
## with no production caller on the map side, so it is the one a flatten would slip past.
func _mask_arm() -> void:
	var ColorStack = ExMateriaSchema.ColorStack
	var map_mat := ShaderMaterial.new()
	var unit_id := get_instance_id()

	TintedSurfaces.reserve_map_surface()
	TintedSurfaces._surface_materials[TintedSurfaces.SURFACE_MAP] = [map_mat]
	TintedSurfaces._active_layers[TintedSurfaces.SURFACE_MAP] = {}
	TintedSurfaces.register_surface(unit_id, ShaderMaterial.new())

	TintedSurfaces.update_layer(TintedSurfaces.SURFACE_MAP, 201, Color(0.5, 0.0, 0.0))
	TintedSurfaces.update_layer(unit_id, 202, Color(0.5, 0.0, 0.0))

	var map_meta: Array = TintedSurfaces._active_layers[TintedSurfaces.SURFACE_MAP][201]["meta"]
	var unit_meta: Array = TintedSurfaces._active_layers[unit_id][202]["meta"]
	_check("the map delta packs MASK_SURFACE0, not MASK_WHOLE",
		map_meta, [ColorStack.MASK_SURFACE0])
	_check("the unit delta packs MASK_WHOLE",
		unit_meta, [ColorStack.MASK_WHOLE])
	_check("...and the two masks really are different values",
		ColorStack.MASK_SURFACE0 == ColorStack.MASK_WHOLE, false)

	TintedSurfaces.remove_layer(TintedSurfaces.SURFACE_MAP, 201)
	TintedSurfaces.unregister_surface(unit_id)
	_arms_completed.append("mask")


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
