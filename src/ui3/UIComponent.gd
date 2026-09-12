@tool
class_name UIComponent
extends UI3Element
## Base for any UI3 node that participates in the deferred-layout contract.
## UIWindow is the modal/non-modal subtype; non-window UI3 nodes (UIButton,
## UIFrame, UIText, UIClickableField, the popups) extend this directly.
##
## Subclass contract:
##   _build_children()         create children once (called once on _ready)
##   _update_layout()          apply current property values to children
##   _populate_editor_preview() optional — defaults to no-op
##
## Setter shapes (descriptive — see CONTEXT.md "UI3 components"):
##   shape (a) layout-affecting -> `_mark_layout_dirty()`   (deferred, batched)
##   shape (b) sync propagation -> `_push(child, &"field", v)`, repeated
##                                 `_push` calls, or a helper that does the
##                                 same kind of work (sync)
## Setters often compose (a) and (b) — push the value immediately, then
## mark dirty so the surrounding layout recomputes.

var _built: bool = false
var _layout_dirty: bool = false


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_build_children()
	_update_layout()
	if Engine.is_editor_hint():
		_populate_editor_preview()


# Subclass hooks — override these.
func _build_children() -> void:
	pass


func _update_layout() -> void:
	pass


func _populate_editor_preview() -> void:
	pass


# Shape (a): deferred batched layout. No-ops before `_ensure_built` runs —
# property setters that fire during scene deserialization don't need to
# schedule, because `_ensure_built` applies the current property values
# once children exist.
func _mark_layout_dirty() -> void:
	if _layout_dirty or not _built:
		return
	_layout_dirty = true
	call_deferred("_do_layout_update")


func _do_layout_update() -> void:
	if not _layout_dirty:
		return
	_layout_dirty = false
	_update_layout()
	if Engine.is_editor_hint():
		_populate_editor_preview()


# Shape (b): sync push to a child's field. No-ops if the child isn't built yet
# — `_update_layout` re-applies the property value once children exist.
func _push(child: Node, field: StringName, value) -> void:
	if child:
		child.set(field, value)
