class_name UIClickableField
extends Area3D
## Reusable click area component for UI elements.
##
## Creates an Area3D with collision shape that can be positioned over any UI element.
## Emits clicked signal with field type and index when clicked.

## Emitted when the click area is clicked
signal clicked(field_type: String, field_index: int)

## The type of field this click area represents (e.g., "equipment", "ability", "gambit")
var field_type: String = ""

## The index within the field type (e.g., slot index for equipment)
var field_index: int = -1

## Optional item data associated with this click area
var item_data: Variant = null

var _debug_mesh: MeshInstance3D
var _collision: CollisionShape3D


func _ready() -> void:
	input_ray_pickable = true
	input_event.connect(_on_input_event)


## Configure the click area with type, index, size, and position.
## rect: Position and size in virtual pixels (x, y, width, height)
## pixels_per_unit: World units per virtual pixel
## show_debug: Whether to show debug mesh
func configure(type: String, index: int, rect: Rect2, pixels_per_unit: float, show_debug: bool = false) -> void:
	field_type = type
	field_index = index

	# Create collision shape if not exists
	if not _collision:
		_collision = CollisionShape3D.new()
		var box = BoxShape3D.new()
		_collision.shape = box
		add_child(_collision)

	# Calculate world size
	var world_width = rect.size.x * pixels_per_unit
	var world_height = rect.size.y * pixels_per_unit

	# Update collision shape size
	var box: BoxShape3D = _collision.shape
	box.size = Vector3(world_width, world_height, 0.1)

	# Position at center of rect (origin is top-left in UI, +X right, -Y down).
	# Z: a small forward nudge so this button's collider sits just in front of
	# its OWN window's body click-absorber (the UIFrame absorber rides the frame
	# plane), letting the button win where they overlap. Deliberately tiny —
	# modal isolation is the host's input-grab (ADR-0061), NOT this offset, so it
	# must stay below the gambit->action nested bump (0.1) and the layer gap
	# (1.0): button 0.05 < nest 0.1 < layer 1.0. The old +0.5 (claiming to "fix
	# visibility") protruded a back-layer button across layers and caused the
	# modal through-click; the debug mesh handles visibility via no_depth_test.
	position = Vector3(
		(rect.position.x + rect.size.x / 2.0) * pixels_per_unit,
		-(rect.position.y + rect.size.y / 2.0) * pixels_per_unit,
		0.05
	)

	# Update or create debug mesh
	_update_debug_mesh(box.size, show_debug)


## Set visibility of the debug mesh
func set_debug_visible(debug_visible: bool) -> void:
	if _debug_mesh:
		_debug_mesh.visible = debug_visible


## Get the current debug visibility state
func is_debug_visible() -> bool:
	return _debug_mesh and _debug_mesh.visible


func _update_debug_mesh(size: Vector3, show: bool) -> void:
	if not _debug_mesh:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "DebugMesh"

		# psx-ot-depth-exempt: screen-space UI debug box (no_depth_test), not battle geometry
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.8, 0.2, 0.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true  # Render on top of UI elements
		mat.render_priority = 10  # Renders above UIText (priority 2)
		_debug_mesh.material_override = mat

		add_child(_debug_mesh)

	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	_debug_mesh.mesh = box_mesh
	_debug_mesh.visible = show


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			clicked.emit(field_type, field_index)
			get_viewport().set_input_as_handled()
