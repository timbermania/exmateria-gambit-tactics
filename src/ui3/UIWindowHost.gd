@tool
class_name UIWindowHost
extends Node3D
## The combat-UI **host**: places every registered [UIWindow] at its dialed-in
## `screen_pos` and owns the single-current modal lifecycle. Per ADR-0010,
## "host" is the role; this is not a UI component (its `_placement_dirty` is a
## per-frame poll watching camera/viewport, distinct from `UIComponent`'s
## one-shot deferred batch — see CONTEXT.md "UIComponent").
##
## Screen coordinates: (0,0) is top-left, (1,1) is bottom-right.
##
## Supports @tool for editor preview.
##
## Usage:
##   var host = UIWindowHost.new()
##   camera.add_child(host)
##   host.register_element("my_panel", panel_node, Vector2(0.1, 0.1))

## Reference camera size for base pixels_per_unit calculations
const REFERENCE_CAMERA_SIZE: float = 14.0

## Distance from camera for screen-space rendering
@export var screen_space_depth: float = 10.0

## World units per virtual pixel - cascades to children that support it
@export var pixels_per_unit: float = 0.04:
	set(value):
		pixels_per_unit = value
		_update_children_pixels_per_unit()

## Registered elements: {name: {node, screen_pos, visible_check}}
var _elements: Dictionary = {}

## Track camera size + viewport size to relayout only when they change.
var _last_camera_size: float = 0.0
var _last_viewport_size: Vector2 = Vector2.ZERO
## The camera transform the clip bases were last snapshotted against. Separate from the two
## above because it drives a DIFFERENT answer: size/viewport move where windows sit, this
## moves what space they sit in. See `_process`.
var _last_camera_transform: Transform3D = Transform3D()

## Set when something invalidates placement (a new registration, a manual
## request). Forces one relayout on the next frame regardless of camera state.
## Named apart from UIComponent's `_layout_dirty` on purpose: same idea, very
## different mechanics — UIComponent batches one deferred call per dirty cycle,
## the host polls `_process` watching camera/viewport changes. See CONTEXT.md
## "UIComponent" and "Combat UI windows".
var _placement_dirty: bool = true


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		# Editor: relayout every frame so inspector screen_pos tweaks preview live.
		_relayout()
		return
	# Runtime: relayout only when placement could actually have changed — on a
	# dirty flag (registration) or a camera-zoom / viewport-resize. Camera
	# *translation* needs none: the container rides the camera, so each window's
	# screen-local position is invariant. This keeps the per-frame loop off the
	# open animation, which also writes position.x/y. See ADR-0010.
	var camera = get_viewport().get_camera_3d() if get_viewport() else null
	if not camera:
		return
	var vp := _get_effective_viewport_size()
	if _placement_dirty or camera.size != _last_camera_size or vp != _last_viewport_size:
		_relayout()
	# ...and the SECOND half of that sentence, which the comment above got wrong for as long
	# as it existed. A window's screen-local POSITION is invariant under a camera pan; its
	# GLOBAL TRANSFORM is not, because this host is a CHILD of the camera. Every UI3 clip
	# basis is a snapshot of a screen root's global transform ([method
	# UI3ClipEngine.clip_basis_inv_for]), so a pan leaves every one of them stale — and a
	# stale basis is not a small error, it compares a display-space box against a global
	# vertex and DISCARDS EVERY CLIPPED FRAGMENT. Measured on the turn-queue strip: pan the
	# map cursor and the whole strip vanishes; close and re-open it and it comes back full,
	# because re-opening re-drives `_set_aperture` -> `_push_clip` -> a fresh basis.
	if camera.global_transform != _last_camera_transform:
		_last_camera_transform = camera.global_transform
		_refresh_clip_basis()


## Request a relayout on the next frame (e.g. after changing a screen_pos at
## runtime). Idempotent.
func mark_placement_dirty() -> void:
	_placement_dirty = true


## Apply container scale (camera zoom) + reposition every registered window.
func _relayout() -> void:
	var camera = get_viewport().get_camera_3d() if get_viewport() else null
	if not camera:
		return
	_last_camera_size = camera.size
	_last_viewport_size = _get_effective_viewport_size()
	_placement_dirty = false
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		# Scale container to compensate for camera zoom (cheap transform).
		var scale_factor = camera.size / REFERENCE_CAMERA_SIZE
		scale = Vector3(scale_factor, scale_factor, scale_factor)
	_update_element_positions()
	# A zoom rewrites this host's SCALE and a relayout rewrites each window's local x/y —
	# both move a registered screen root in world space, so both stale the same snapshot the
	# pan does. Same call, second door.
	_refresh_clip_basis()


## Re-push every registered UI3 element's clip BASIS, because this host (or the camera it
## rides) just moved. [method UI3Registry.refresh_clip_basis] writes ONE uniform per payload
## material and skips the aperture walk entirely — its docstring calls that out as being
## deliberately cheap enough to run on every frame of a pan, which is what the caller above
## does. Looked up rather than referenced: a host mounted in a rig with no autoloads (every
## UI3 unit test) must still place its windows.
func _refresh_clip_basis() -> void:
	var registry := get_node_or_null("/root/UI3Registry")
	if registry != null:
		registry.refresh_clip_basis()


func _update_element_positions() -> void:
	for element_name in _elements:
		var data = _elements[element_name]
		var node: Node3D = data["node"]

		if not is_instance_valid(node):
			continue

		# Skip if visibility check returns false
		if data.has("visible_check") and data["visible_check"].is_valid():
			if not data["visible_check"].call():
				continue

		# Use node's screen_pos property if it has one (allows inspector changes to work)
		# Otherwise fall back to the registered screen_pos
		var screen_pos: Vector2
		if "screen_pos" in node:
			screen_pos = node.screen_pos
		else:
			screen_pos = data["screen_pos"]
		var world_pos = _screen_to_world(screen_pos)
		var local_pos = to_local(world_pos)
		node.position.x = local_pos.x
		node.position.y = local_pos.y


func _screen_to_world(screen_pos: Vector2) -> Vector3:
	return _calculate_world_position(screen_pos)


func _calculate_world_position(screen_pos: Vector2) -> Vector3:
	var camera = get_viewport().get_camera_3d() if get_viewport() else null
	if not camera:
		return Vector3.ZERO

	var viewport_size = _get_effective_viewport_size()
	var aspect = viewport_size.x / viewport_size.y

	var half_height: float
	var half_width: float

	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		half_height = camera.size / 2.0
		half_width = half_height * aspect
	else:
		var fov_rad = deg_to_rad(camera.fov)
		half_height = screen_space_depth * tan(fov_rad / 2.0)
		half_width = half_height * aspect

	var x = lerp(-half_width, half_width, screen_pos.x)
	var y = lerp(half_height, -half_height, screen_pos.y)

	return camera.global_position + camera.global_transform.basis * Vector3(x, y, -screen_space_depth)


## Get the effective viewport size for aspect ratio calculations.
## In editor mode, uses project settings to match runtime behavior.
func _get_effective_viewport_size() -> Vector2:
	if Engine.is_editor_hint():
		# Use PSX internal dimensions (16:15) to match runtime SubViewport aspect
		return Vector2(1024, 960)
	return get_viewport().get_visible_rect().size


func _update_children_pixels_per_unit() -> void:
	for element_name in _elements:
		var data = _elements[element_name]
		var node = data["node"]
		if is_instance_valid(node) and "pixels_per_unit" in node:
			node.pixels_per_unit = pixels_per_unit


## Convert screen coordinates to world position.
## Public wrapper for _calculate_world_position.
## Register a UI element with a screen-normalized position.
## Does NOT reparent the node - just tracks its position.
func register_element(element_name: String, node: Node3D, screen_pos: Vector2,
				 visible_check: Callable = Callable()) -> void:
	_elements[element_name] = {
		"node": node,
		"screen_pos": screen_pos,
		"visible_check": visible_check
	}

	if "pixels_per_unit" in node:
		node.pixels_per_unit = pixels_per_unit

	_placement_dirty = true


## Auto-register every descendant window for placement. A "window" is any node
## exposing a `screen_pos` property; it is keyed by its node name and is treated
## as a leaf (the scan does not descend into a window's own internals). Replaces
## hand-written register_element() calls per window. See ADR-0010.
func register_window_tree(root: Node = self) -> void:
	for child in root.get_children():
		if "screen_pos" in child:
			register_element(child.name, child, child.screen_pos)
		else:
			register_window_tree(child)


#region Modal lifecycle
## At most one top-level modal window is open at a time (mutual exclusion).
## Opening one dismisses the current; the host clears its slot when a modal
## reports `closed`. A modal's private sub-window (e.g. the gambit editor's
## action picker) is the owner's concern, not tracked here. Modals draw in
## front by living on a layer in front (render-order); input isolation is the
## grab below, not Z. See CONTEXT.md "Combat UI windows" and ADR-0010/0020.

## **Input isolation is structural, not Z-based (ADR-0061).** While a modal is
## open the host *grabs input*: every clickable that is NOT on the modal's own
## layer stops physics-picking, so a click behind the modal cannot fall through
## regardless of any Z value. Render-order (structural layer + render_priority)
## and click-order (closest-collider physics pick) are decoupled; the grab stops
## relying on their Z agreeing.

var _current_modal: UIModalWindow = null

## Clickables this host disabled for the current grab, to restore on release.
## Only colliders that were pickable when the grab fired are recorded, so a
## frame whose absorber was already off (hidden) is never wrongly re-enabled.
var _grabbed_areas: Array[Area3D] = []
var _modal_grab_active: bool = false


## Present a modal: dismiss the current one (if any), track this as current,
## grab input behind it, animate it in. The caller populates content (bespoke
## args) beforehand. `_current_modal` is assigned BEFORE closing the previous
## modal so the swap's `closed` signal does not release the grab mid-swap.
func open_modal(window: UIModalWindow) -> void:
	var previous := _current_modal
	_current_modal = window
	if previous and previous != window and previous.is_open():
		previous.close()
	if not window.closed.is_connected(_on_modal_closed):
		window.closed.connect(_on_modal_closed.bind(window))
	_apply_modal_grab(window.get_parent())
	window.animate_in()


## Disable physics picking on every clickable under the host that is NOT a
## descendant of `modal_layer` (the layer the open modal lives on). Idempotent:
## a no-op while a grab is already active, so a modal->modal swap keeps the lower
## layers disabled without churn. `modal_layer` is the modal's parent, so the
## whole modal layer (the modal plus any privately-nested sub-picker) stays
## live; only the layers behind it are grabbed.
func _apply_modal_grab(modal_layer: Node) -> void:
	if _modal_grab_active or modal_layer == null:
		return
	_modal_grab_active = true
	_grabbed_areas.clear()
	_collect_grab_targets(self, modal_layer)


func _collect_grab_targets(node: Node, modal_layer: Node) -> void:
	for child in node.get_children():
		if child == modal_layer:
			continue  # the modal's own layer (and its subtree) stays interactive
		if child is Area3D and child.input_ray_pickable:
			child.input_ray_pickable = false
			_grabbed_areas.append(child)
		_collect_grab_targets(child, modal_layer)


## Restore picking on exactly the colliders the grab disabled.
func _release_modal_grab() -> void:
	if not _modal_grab_active:
		return
	_modal_grab_active = false
	for area in _grabbed_areas:
		if is_instance_valid(area):
			area.input_ray_pickable = true
	_grabbed_areas.clear()


## Dismiss the current modal, if one is open. Returns true if it closed one
## (so callers like an ESC handler can consume the input).
func close_current_modal() -> bool:
	if _current_modal and _current_modal.is_open():
		_current_modal.close()
		return true
	return false


## True while a top-level modal is open.
func is_modal_open() -> bool:
	return _current_modal != null and _current_modal.is_open()


func _on_modal_closed(window: UIModalWindow) -> void:
	if _current_modal == window:
		_current_modal = null
		_release_modal_grab()

#endregion


## Update screen position for an existing element.
## Get screen position of an element.
## Get a registered element node by name.
## Unregister an element (does not free the node).
## Check if an element is registered.
