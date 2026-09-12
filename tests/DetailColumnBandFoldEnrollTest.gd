extends Node3D

## Guard: the §15.19 Eqp/Ability lower-panel dark column bands (the "ability/equipment joint
## panel" brown strips) stay FOLD-ENROLLED after `_build_column_band` reparents their holder
## keep-global into the box-open group.
##
## reparent() = remove_child + add_child, so the band mesh's tree_exiting fires Fold's un-enroll
## hook (b6400949d), which NULLS its render_layer and drops the subtractive band from the fold
## layer — it stops compositing and the tan frame shows through (the "looks a little off now"
## report). f0e56a591 re-enrolled the vitals stripe + formation roster this way but MISSED this
## joint-panel site; DetailScene._build_column_band now re-adds each band after the reparent.
##
## Locks (only meaningful when this build owns compositing — Forward+ fork; gated on
## Fold.owns()):
##   A. Both EqpBand and AbilityBand holders carry a MeshInstance3D.
##   B. Each band mesh's render_layer != null (still in the fold layer after the reparent).
##
## Run: <GODOT> --path . --quit-after 20 res://tests/DetailColumnBandFoldEnrollTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const Fold = ExMateriaSchema.Fold

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

const _VIEW := {
	"move": 4, "jump": 3, "speed": 8, "r_power": 9, "r_wev": 5, "l_power": 0, "l_wev": 0,
	"r_at": 7, "c_ev": 12, "s_ev": 0, "a_ev": 0, "l_at": 0,
	"equipment": [{"name": "Broad Sword", "palette": 0, "icon_graphic": -1}, {},
		{"name": "Leather Hat", "palette": 4, "icon_graphic": -1}, {}, {}],
}

var _passed := 0
var _failed := 0


func _ready() -> void:
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	d.set_stats_view(_VIEW)
	await get_tree().process_frame
	await get_tree().process_frame

	if not Fold.owns():
		# The bands build via the off-fork non-fold path (no Fold.add) — render_layer is
		# legitimately null and there is nothing to guard. Skip cleanly.
		print("[SKIP] DetailColumnBandFoldEnrollTest — build does not own compositing")
		d.queue_free()
		get_tree().quit(0)
		return

	for band_name in ["EqpBand", "AbilityBand"]:
		var holder := d.find_child(band_name, true, false) as Node3D
		_expect(holder != null, "%s holder missing (column band not built)" % band_name)
		if holder != null:
			var mi := _first_mesh(holder)
			_expect(mi != null, "%s holder carries no MeshInstance3D" % band_name)
			if mi != null:
				_expect(mi.render_layer != null,
					"%s mesh lost its fold-layer membership (render_layer null) after the reparent" % band_name)

	d.queue_free()
	print("\n=== DetailColumnBandFoldEnrollTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		printerr("[FAIL] DetailColumnBandFoldEnrollTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailColumnBandFoldEnrollTest: Eqp/Ability column bands stay fold-enrolled")
		get_tree().quit(0)


func _first_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for c in root.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("[DetailColumnBandFoldEnrollTest] " + msg)
		print("  [x] " + msg)
