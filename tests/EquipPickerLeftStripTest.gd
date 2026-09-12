extends Node3D
## Guard: the equip-picker has a BROWN vertical strip running top-to-bottom on the LEFT of the
## window — the same subtractive UIVitalsBand column band the Eqp/Ability panels use (§15.19),
## NOT a header. Locks:
##   A. EXISTS — left_strip_material() returns a live ShaderMaterial.
##   B. REVEALED — the strip material is in body_materials(), so the box-open aperture reveals it
##      center-out with the rest of the window chrome (not popped in whole).
##   C. RIDES THE FRAME — the strip's holder is under the registered window ELEMENT (ADR-0088),
##      so grabbing/moving the window moves the strip with it (the movable-group model).
##   D. TUNEABLE + VERTICAL — its live rect (left_strip_rect(), the equipicker.strip.rect
##      composite) is a real, taller-than-wide strip sitting on the LEFT half of the frame.
##   E. STILL FOLD-ENROLLED after the carrier reparent — reparent() fires Fold's tree_exiting
##      un-enroll hook (b6400949d), which NULLS the strip mesh's render_layer and drops the
##      subtractive band from the fold layer (it stops compositing → the "looks off" report).
##      Re-enrolled after the move. Only meaningful when this scene owns compositing.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const Fold = ExMateriaSchema.Fold

const EquipPickerMenu = preload("res://src/ui3/detail/EquipPickerMenu.gd")

var _failed := false


func _ready() -> void:
	var m: EquipPickerMenu = EquipPickerMenu.new()
	m.autoplay_open = false
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame

	# A. exists
	var mat: ShaderMaterial = m.left_strip_material()
	_expect(mat != null and is_instance_valid(mat), "left_strip_material() must return a live material")

	# B. revealed by the box-open aperture
	if mat != null:
		_expect(m.body_materials().has(mat),
			"left strip must be in body_materials() so the box-open reveals it")

	# C. rides the movable origin (holder under the registered window element)
	var origin: Node3D = m.window()
	_expect(origin != null and is_instance_valid(origin), "window element missing")
	if origin != null:
		_expect(_strip_holder_under(origin),
			"left strip holder must be a descendant of the window element (rides the window move)")

	# D. tuneable, vertical, on the left
	var r: Rect2 = m.left_strip_rect()
	_expect(r.size.x > 0.0 and r.size.y > 0.0, "left_strip_rect must be a real rect, got %s" % [r])
	_expect(r.size.y > r.size.x, "left strip must be taller than wide (a vertical strip), got %s" % [r])
	var frame_rect: Rect2 = m.window().rect()
	_expect(r.position.x < frame_rect.position.x + frame_rect.size.x * 0.5,
		"left strip must sit on the LEFT half of the frame, got x=%s" % [r.position.x])

	# E. still fold-enrolled after the reparent (render_layer != null) — the bug this guards
	if mat != null and Fold.owns():
		var strip_mi := _mesh_with_mat(self, mat)
		_expect(strip_mi != null, "left strip mesh not found for fold-enrollment check")
		if strip_mi != null:
			_expect(strip_mi.render_layer != null,
				"left strip mesh lost its fold-layer membership (render_layer null) after the reparent")

	m.queue_free()
	if _failed:
		printerr("[FAIL] EquipPickerLeftStripTest")
		get_tree().quit(1)
	else:
		print("[PASS] EquipPickerLeftStripTest")
		get_tree().quit(0)


func _strip_holder_under(origin: Node) -> bool:
	# The strip's UIVitalsBand holder carries a MeshInstance3D whose material is the strip mat.
	var mat: ShaderMaterial = (origin.get_parent() as EquipPickerMenu).left_strip_material()
	return _find_mesh_with_mat(origin, mat)


func _find_mesh_with_mat(n: Node, mat: ShaderMaterial) -> bool:
	return _mesh_with_mat(n, mat) != null


func _mesh_with_mat(n: Node, mat: ShaderMaterial) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).material_override == mat:
		return n
	for c in n.get_children():
		var m := _mesh_with_mat(c, mat)
		if m != null:
			return m
	return null


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		printerr("  " + msg)
