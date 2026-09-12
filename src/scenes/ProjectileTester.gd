extends Node3D
## Projectile Model Tester Scene
##
## Loads PSX 3D polygon projectile models from JSON and displays them
## side-by-side for visual inspection. Supports rotation to view from all angles.
##
## Controls:
## - Mouse drag: Rotate camera around models
## - Scroll: Zoom in/out
## - Model buttons: Toggle individual model visibility

const JSON_PATH := "res://assets/projectiles/projectile_models.json"
const MATERIAL_PATH := "res://assets/materials/projectile_vertex_color.tres"
const MODEL_SPACING := 5.0  # Units between models

var models: Dictionary = {}  # model_name -> MeshInstance3D
var model_material: Material
var rotation_speed := 0.005
var zoom_speed := 0.5
var camera_distance := 15.0
var camera_angle := Vector2(0.3, 0.0)  # x = pitch, y = yaw

@onready var camera: Camera3D = $Camera3D
@onready var model_container: Node3D = $ModelContainer


func _ready() -> void:
	print("\n=== PROJECTILE TESTER ===")

	# Load material
	model_material = load(MATERIAL_PATH) as Material
	if not model_material:
		push_error("[ProjectileTester] Failed to load material: %s" % MATERIAL_PATH)
		return

	# Load and build models
	var json_data := _load_json(JSON_PATH)
	if json_data.is_empty():
		push_error("[ProjectileTester] Failed to load JSON: %s" % JSON_PATH)
		return

	_create_models(json_data)
	_create_ui()
	_update_camera()

	print("[ProjectileTester] Loaded %d models" % models.size())


func _load_json(path: String) -> Dictionary:
	"""Load and parse JSON file."""
	if not FileAccess.file_exists(path):
		push_error("[ProjectileTester] JSON file not found: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[ProjectileTester] Failed to open JSON: %s" % path)
		return {}

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("[ProjectileTester] JSON parse error: %s" % json.get_error_message())
		return {}

	return json.data


func _create_models(json_data: Dictionary) -> void:
	"""Create mesh instances for all projectile models."""
	var model_data: Dictionary = json_data.get("models", {})
	var model_names := model_data.keys()
	model_names.sort()

	var x_offset := -MODEL_SPACING * (model_names.size() - 1) / 2.0

	for model_name in model_names:
		var mesh := ProjectileMeshBuilder.build_mesh(model_data[model_name])

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.material_override = model_material
		mesh_instance.position = Vector3(x_offset, 0, 0)
		mesh_instance.name = model_name

		model_container.add_child(mesh_instance)
		models[model_name] = mesh_instance

		# Create label
		var label := _create_label(model_name, Vector3(x_offset, -4.0, 0))
		model_container.add_child(label)

		x_offset += MODEL_SPACING


func _create_label(text: String, position: Vector3) -> Label3D:
	"""Create a 3D label for a model."""
	var label := Label3D.new()
	label.text = text.capitalize()
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.01
	label.modulate = Color.WHITE
	label.outline_size = 8
	label.outline_modulate = Color.BLACK
	return label


func _create_ui() -> void:
	"""Create UI panel with model toggles and info."""
	var panel := PanelContainer.new()
	panel.name = "UIPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.offset_right = 200
	panel.offset_bottom = 200

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Projectile Models"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	# Instructions
	var instructions := Label.new()
	instructions.text = "Drag to rotate\nScroll to zoom"
	instructions.add_theme_font_size_override("font_size", 12)
	vbox.add_child(instructions)

	# Model toggles
	var separator := HSeparator.new()
	vbox.add_child(separator)

	for model_name in models:
		var checkbox := CheckBox.new()
		checkbox.text = model_name.capitalize()
		checkbox.button_pressed = true
		checkbox.toggled.connect(_on_model_toggled.bind(model_name))
		vbox.add_child(checkbox)

	# Add to CanvasLayer for UI
	var canvas := CanvasLayer.new()
	canvas.name = "UILayer"
	canvas.add_child(panel)
	add_child(canvas)


func _on_model_toggled(visible: bool, model_name: String) -> void:
	"""Handle model visibility toggle."""
	if models.has(model_name):
		models[model_name].visible = visible


func _input(event: InputEvent) -> void:
	# Mouse drag for rotation. [b]The mask comes off the EVENT, not the [Input] singleton.[/b]
	# `Input.is_mouse_button_pressed` was a poll, which is the one thing Focus structurally
	# cannot gate — the switch stops Godot CALLING a non-holder, it cannot stop one ASKING —
	# and `check_focus_anchor.py` listed this file for it. Nothing had to be TRACKED to remove
	# it: an `InputEventMouseMotion` already carries the button state at the moment it was
	# generated, which is strictly better than asking the singleton one frame later.
	if event is InputEventMouseMotion \
			and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		camera_angle.y += event.relative.x * rotation_speed
		camera_angle.x = clamp(camera_angle.x - event.relative.y * rotation_speed, -1.5, 1.5)
		_update_camera()

	# Scroll for zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = max(5.0, camera_distance - zoom_speed)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = min(50.0, camera_distance + zoom_speed)
			_update_camera()


func _update_camera() -> void:
	"""Update camera position based on angle and distance."""
	var offset := Vector3(
		sin(camera_angle.y) * cos(camera_angle.x),
		sin(camera_angle.x),
		cos(camera_angle.y) * cos(camera_angle.x)
	) * camera_distance

	camera.position = offset
	camera.look_at(Vector3.ZERO, Vector3.UP)
