@tool
class_name UIModalWindow
extends UIWindow

## Base for a **modal window** — a window opened by drilling deeper into a
## non-modal window, drawn above the non-modal windows, and dismissed before
## the player does anything else. Owns the lifecycle contract every modal
## shares (closed / close / is_open); content population and the bespoke
## `open()` / `show_*` entry points stay on each subclass, and the host
## ([UIWindowHost]) drives presentation. At most one top-level modal is open
## at a time. See CONTEXT.md "Combat UI windows" and ADR-0010.

# Emitted once the window has closed — whether cancelled or committed. Since the
# UIComponent base-swap (ADR-0088 Amendment 5), this reuses the inherited UI3Element
# `closed` signal rather than redeclaring it (the modal close IS a "closed").
const OPEN_DURATION: float = 0.12


## True while the window is showing.
func is_open() -> bool:
	return visible


## Animate this window in (scale-up from its top-left toward its dialed-in
## position). Convenience over the static helper; the host calls this on open.
func animate_in() -> void:
	animate_open(self)


## Scale-up open animation for any window node (modal or non-modal menu).
## Static so non-modal menus — which don't yet share this base — can reuse it
## until they move onto a common UIWindow base. Origin = top-left; content
## extends +X / -Y, so the window grows from that corner toward center.
static func animate_open(node: Node3D) -> void:
	var half := _half_size_world(node)
	var target_pos: Vector3 = node.position
	# tween_method so position tracks scale exactly (no drift)
	node.scale = Vector3(0.01, 0.01, 1)
	node.position = Vector3(target_pos.x + half.x, target_pos.y + half.y, target_pos.z)
	var tween := node.create_tween()
	tween.tween_method(func(t: float):
		node.scale = Vector3(t, t, 1)
		node.position = Vector3(
			target_pos.x + half.x * (1.0 - t),
			target_pos.y + half.y * (1.0 - t),
			target_pos.z)
	, 0.01, 1.0, OPEN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## Center offset in world units, probed from whatever frame the window owns.
static func _half_size_world(node: Node3D) -> Vector2:
	var ppu := 0.04
	if "pixels_per_unit" in node:
		ppu = node.pixels_per_unit
	var w := 100.0
	var h := 60.0
	if "_frame" in node and node._frame and "frame_size" in node._frame:
		w = node._frame.frame_size.x
		h = node._frame.frame_size.y
	elif "_top_menu" in node and node._top_menu and "frame_size" in node._top_menu:
		w = node._top_menu.frame_size.x
		var top_h = node._top_menu.frame_size.y
		var bot_h = node._bottom_menu.frame_size.y if ("_bottom_menu" in node and node._bottom_menu) else 0.0
		h = top_h + bot_h
	elif "frame_size" in node:
		w = node.frame_size.x
		h = node.frame_size.y
	# +X = rightward, -Y = downward → center offset is (+half_w, -half_h)
	return Vector2(w * 0.5 * ppu, -h * 0.5 * ppu)


## Dismiss the window: run subclass teardown, hide, then notify. Idempotent —
## calling it on an already-hidden window does nothing.
##
## This OVERRIDES UI3Element.close (UIModalWindow is a UIWindow is a UIComponent is a
## UI3Element): a modal owns its own leave animation rather than playing a transition beat, so
## it drives the hide itself and emits the inherited `closed`. It therefore takes — and
## ignores — the ADR-0097 §4 cadence override, because the signature must match the base and
## because a modal that is already instant has no curve for a cadence to select. Not an
## oversight: if a modal ever grows a beat, this is where the override starts being honoured.
func close(_cadence: int = NO_CADENCE_OVERRIDE) -> void:
	if not visible:
		return
	_on_closing()
	visible = false
	closed.emit()


## Subclass hook: teardown run just before the window hides (disconnecting
## signals, clearing list contents, cascading to a private sub-window).
## Override this, not close().
func _on_closing() -> void:
	pass
