extends Node3D
# test-kind: logic
# seeded-break: _build_band_backdrop drops the post-reparent Fold re-enroll (the Fold.add block) — the b6400949d defect state: reparent's tree_exiting un-enrolls the band mesh and NULLs its render_layer, so 'band mesh lost its fold-layer membership (render_layer null) after the reparent' reds; the id/role/UNCLIPPED/no-beat asserts + the UI3Registry row + the BandBackdrop-housed + carrier-ride asserts stay green

## Guard (ADR-0088 Amendment 5 §4): the §14.6.6 subtractive stripe on the FORMATION roster
## is now housed in the registered carrier element `formation.vitals_band` (mirroring
## detail.vitals_band; UIVitalsBand is RefCounted so a carrier wrap is correct). Before this
## slice the roster drew the SAME stripe on a bare node — so it never showed a UI3 row until
## ○-press mounted the Status screen. Now the band shows a row ON the formation roster.
##   A. REGISTERED — an element with id "formation.vitals_band" is in the UI3Registry index
##      (i.e. it gets a UI3-page row), UNCLIPPED, no beat.
##   B. HOUSED — the "BandBackdrop" mesh holder is a descendant of that carrier.
##   C. RIDES — moving the carrier moves the band mesh with it (movable origin).
##
## (Visual no-op is covered by FormationBackdropElementTest's position-multiset golden.)
##
## Run: <GODOT> --path . --quit-after 30 res://tests/FormationVitalsBandElementTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const Fold = ExMateriaSchema.Fold

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	for _i in 4:
		await get_tree().process_frame

	var form = host._formation
	_expect(form != null, "no formation scene (host boot failed)")

	var band := form.find_child("VitalsBandElement", true, false) as UI3Element if form != null else null
	_expect(band != null, "VitalsBandElement missing (formation band not a registered element)")
	if band != null:
		# --- A. registered (gets a UI3 row) --------------------------------------
		_expect(band.id() == "formation.vitals_band", "element id %s != formation.vitals_band" % band.id())
		_expect(band.role() == UI3Element.Role.ELEMENT, "formation band carrier must be Role.ELEMENT")
		_expect(band.clip_mode() == UI3Element.Clip.UNCLIPPED, "formation band clip must be UNCLIPPED")
		_expect(band.transition_mode() == UI3Element.Transition.NONE, "formation band has no beat")
		var listed := false
		for e: UI3Element in UI3Registry.elements():
			if e == band:
				listed = true
				break
		_expect(listed, "formation.vitals_band must be in the UI3Registry index (a UI3 page row)")

		# --- B. housed -----------------------------------------------------------
		var mesh := _first_mesh(band)
		_expect(mesh != null, "the band mesh (BandBackdrop) is not housed under the carrier")

		# --- B2. STILL FOLD-ENROLLED after the carrier reparent ------------------
		# reparent() = remove_child + add_child, so the band mesh's tree_exiting fires Fold's
		# un-enroll hook and NULLS its render_layer — dropping it from the fold layer so the
		# subtractive band stops compositing ("cut off top and bottom"). It must be re-enrolled.
		if mesh != null and Fold.owns():
			_expect(mesh.render_layer != null,
				"band mesh lost its fold-layer membership (render_layer null) after the reparent")

		# --- C. rides the movable origin -----------------------------------------
		if mesh != null:
			var before := mesh.global_position
			var delta := Vector3(0.7, -0.3, 0.0)
			band.position += delta
			var after := mesh.global_position
			_expect(((after - before) - delta).length() < 0.001,
				"the band mesh must ride the carrier move (movable origin)")
			band.position -= delta

	print("\n=== FormationVitalsBandElementTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationVitalsBandElementTest")
		get_tree().quit(1)
	else:
		print("[PASS] FormationVitalsBandElementTest: formation.vitals_band carrier registered + houses the band")
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
		push_error("[FormationVitalsBandElementTest] %s" % msg)
		print("  [x] " + msg)
