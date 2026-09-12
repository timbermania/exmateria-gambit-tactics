class_name UI3OwnerMapPicker
extends Node

## Click a color on the ownership map, get told which element owns it (ADR-0088 Amendment 6
## follow-on). The page ([UI3RegistryView]) listens and jumps to that element's row.
##
## WHY A SEPARATE NODE. The debug dashboard is its own OS-level [Window] ([DebugDashboard]
## extends Window; the page is instantiated inside it), so a click on the game has no route to
## the page's input. This node lives in the MAIN window's tree for exactly as long as the map
## is active, catches the click there, and reports across the window boundary by signal.
##
## WHY A PIXEL READ AND NOT A COLLIDER. The map is already a false-color ID buffer —
## `ui3_owner_color.gdshader` is unshaded, normal blend, alpha-tested, and its header states
## the intent outright: "the on-screen color matches the page's swatch even for add/sub fold
## members". So the framebuffer already answers "who owns this pixel". Going the other way
## would mean giving UI3 payload physics: it is bare [MeshInstance3D] with no [Area3D], and the
## only physics picking in the codebase ([code]UIWindowHost._apply_modal_grab[/code]) works on
## Area3D — so a collider approach means editing production for a debug feature. This edits
## nothing.
##
## The lookup itself, its measured +/-1 tolerance, and why it is not a nearest-color match are
## documented on [method UI3OwnerColorMap.resolve_owner]. Guard: UI3OwnerPickTest.
##
## MODIFIER, NOT PLAIN CLICK. The game is still live under the map, so a bare left-click has to
## keep reaching it. Ctrl (or Alt) + left-click is the pick, and only that combination is
## consumed.

## The picked element's id — the page's cue to reveal that row.
signal element_picked(element_id: String)

## A pick that resolved to nothing, with why. `reason` is one of:
##   "unowned"   — the reserved ALARM color: real UI payload no registered element claims
##                 (that IS the finding — the map is telling you about an orphan)
##   "no_owner"  — the pixel belongs to no owner color (background, the game underneath,
##                 or an element occluding the one you aimed at)
##   "ambiguous" — inside the tolerance box of more than one owner; see resolve_owner
##   "no_pixel"  — the framebuffer could not be read this frame
signal pick_missed(color: Color, reason: String)

const OwnerColorMap = preload("res://src/debug/UI3OwnerColorMap.gd")

## The map this picker resolves against — the same instance the page drives, so the colors
## looked up are the ones actually on screen.
var _map: UI3OwnerColorMap = null

## The last resolution, for guards + diagnostics: {"color": Color, "id": String,
## "reason": String}. Empty until the first pick.
var _last: Dictionary = {}


func _init(map: UI3OwnerColorMap = null) -> void:
	_map = map


## Resolve a pick at a window-space position, exactly as a click would. Split out from the
## input handler so a guard can drive it without synthesising mouse events, and so the
## framebuffer read has one home.
##
## Returns the element id, or "" on any miss (the `pick_missed` signal carries the reason).
func pick_at(window_pos: Vector2) -> String:
	var color: Variant = read_pixel(window_pos)
	if color == null:
		_last = {"color": Color(), "id": "", "reason": "no_pixel"}
		pick_missed.emit(Color(), "no_pixel")
		return ""
	return resolve(color as Color)


## Resolve an already-read color. Emits either `element_picked` or `pick_missed`.
func resolve(color: Color) -> String:
	if _map == null:
		_last = {"color": color, "id": "", "reason": "no_owner"}
		pick_missed.emit(color, "no_owner")
		return ""
	var id := _map.owner_for_color(color)
	if id != "":
		_last = {"color": color, "id": id, "reason": ""}
		element_picked.emit(id)
		return id
	# ALARM is reserved and can never be an owner color, so an alarm pixel is a DIFFERENT
	# answer from "nothing here" — it means unowned UI payload, which is the map's whole point.
	var reason := "unowned" if OwnerColorMap.is_alarm_color(color) else _miss_reason(color)
	_last = {"color": color, "id": "", "reason": reason}
	pick_missed.emit(color, reason)
	return ""


## Tell "near more than one owner" apart from "near none" — resolve_owner collapses both to "",
## but they mean different things to whoever clicked.
func _miss_reason(color: Color) -> String:
	var near := 0
	for id: String in _map.assigned_colors().keys():
		if OwnerColorMap.within_pick_tolerance(_map.owner_color_for(id), color):
			near += 1
	return "ambiguous" if near > 1 else "no_owner"


## Read one pixel of the FINAL framebuffer at a window-space position, or null if unavailable.
##
## The framebuffer and the window are not necessarily the same size (the game renders at its
## own resolution and is scaled to the window), so the position is mapped through the ratio
## rather than used raw. Reading the whole image for one pixel is a full GPU->CPU readback; that
## is fine at click rate for a debug tool, and it is the only way to see the composited result —
## the compositor engine-fold means the mesh's own color is not the final color.
func read_pixel(window_pos: Vector2) -> Variant:
	var vp := get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null or img.get_width() == 0 or img.get_height() == 0:
		return null
	var rect := vp.get_visible_rect().size
	var sx: float = float(img.get_width()) / maxf(rect.x, 1.0)
	var sy: float = float(img.get_height()) / maxf(rect.y, 1.0)
	var px := clampi(int(window_pos.x * sx), 0, img.get_width() - 1)
	var py := clampi(int(window_pos.y * sy), 0, img.get_height() - 1)
	return img.get_pixel(px, py)


## Ctrl/Alt + left-click picks; everything else falls through to the game, which is still live
## under the map. Only the picking combination is consumed.
func _unhandled_input(event: InputEvent) -> void:
	if _map == null or not _map.is_active():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if not (mb.ctrl_pressed or mb.alt_pressed):
		return
	pick_at(mb.position)
	get_viewport().set_input_as_handled()


## The last pick's outcome (guard + diagnostic surface): {"color", "id", "reason"}.
func last_pick() -> Dictionary:
	return _last
