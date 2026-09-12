extends Node3D

## ADR-0088 Amendment 4 §2 guard: the §14.6.6 vitals stripe is the registered element
## `detail.vitals_band`, whose rect was a derived([]) empty-drivers dead-end. Its two REAL
## vertical knobs (VBAND_TOP_OUT / VBAND_BOT_OUT, promoted to static var + slug) now DRIVE
## it; the screen-wide X stays structural.
##   A. IDENTITY — the "VitalsBandElement" node is the registered element, UNCLIPPED.
##   B. DECLARED DRIVERS — the rect row is DERIVED and declares both vband slugs; default
##      rect is the un-migrated box (visual no-op: Rect2(0, 30, 256, 59)).
##   C. WRITE-THROUGH — scrubbing detail.vband_top_out re-places the element (the write-back
##      rebuilds the band; the fresh element reads the new static var).
##
## Run: <GODOT> --path . --quit-after 20 res://tests/DetailVitalsBandElementTest.tscn

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
}

var _passed := 0
var _failed := 0


func _ready() -> void:
	for slug in ["detail.vband_top_out", "detail.vband_bot_out"]:
		Tune.clear(slug)

	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	d.set_stats_view(_VIEW)
	await get_tree().process_frame
	await get_tree().process_frame

	var band := d.find_child("VitalsBandElement", true, false) as UI3Element
	_expect(band != null, "VitalsBandElement missing (vitals band not a registered element)")
	if band != null:
		# --- A. identity ---------------------------------------------------------
		_expect(band.id() == "detail.vitals_band", "element id %s != detail.vitals_band" % band.id())
		_expect(band.clip_mode() == UI3Element.Clip.UNCLIPPED, "vitals band clip must be UNCLIPPED")

		# --- A2. STILL FOLD-ENROLLED after the carrier reparent ------------------
		# reparent() fires Fold's tree_exiting un-enroll hook, nulling the band mesh's render_layer
		# and dropping the subtractive stripe from the fold layer (it stops compositing). Re-enrolled.
		var band_mesh := _first_mesh(band)
		if band_mesh != null and Fold.owns():
			_expect(band_mesh.render_layer != null,
				"band mesh lost its fold-layer membership (render_layer null) after the reparent")

		# --- B. declared drivers + default (no-op) rect --------------------------
		var row := _rect_row(band)
		_expect(row.get("source") == UI3Element.Source.DERIVED,
			"vitals band rect must be DERIVED, got %s" % [row])
		var drivers: Array = row.get("drivers", [])
		_expect(drivers.has("detail.vband_top_out") and drivers.has("detail.vband_bot_out"),
			"vitals band must declare both vband drivers, got %s" % [drivers])
		_expect(band.rect().is_equal_approx(Rect2(0, 30, 256, 59)),
			"default vitals band rect must be the un-migrated box Rect2(0,30,256,59), got %s" % band.rect())

		# --- C. write-through ----------------------------------------------------
		Tune.set_value("detail.vband_top_out", 34.0)
		await get_tree().process_frame
		# the write-back rebuilds the band, recreating the element — re-fetch it
		var band2 := d.find_child("VitalsBandElement", true, false) as UI3Element
		_expect(band2 != null, "vitals band element gone after scrub rebuild")
		if band2 != null:
			_expect(abs(band2.rect().position.y - 34.0) < 0.001,
				"scrubbing vband_top_out must move the element rect top, got %s" % band2.rect().position.y)
			_expect(abs(band2.rect().size.y - (89.0 - 34.0)) < 0.001,
				"the band height must follow (bot_out - top_out), got %s" % band2.rect().size.y)
		Tune.clear("detail.vband_top_out")

	d.queue_free()
	print("\n=== DetailVitalsBandElementTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DetailVitalsBandElementTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailVitalsBandElementTest: detail.vitals_band declared drivers + write-through")
		get_tree().quit(0)


func _first_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for c in root.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


func _rect_row(e: UI3Element) -> Dictionary:
	for r: Dictionary in e.criteria():
		if String(r["field"]) == "rect":
			return r
	return {}


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[DetailVitalsBandElementTest] " + msg)
		print("  [x] " + msg)
