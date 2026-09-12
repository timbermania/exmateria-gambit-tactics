extends Node
## UIComponent contract test. Pure GDScript — no real UI3 nodes.
##
## Pins the contract every layout-dirty subclass inherits:
##   1. _build_children + _update_layout fire once during _ensure_built.
##   2. N rapid mutations of a layout-dirty property coalesce into one
##      additional _update_layout call after the deferred frame.
##   3. _push() writes synchronously to the child (no defer).
##   4. _push() with a null child is a no-op.


class _TestComponent extends UIComponent:
	var build_count: int = 0
	var layout_count: int = 0
	var _label: Label

	var widget_color: Color = Color.WHITE:
		set(v):
			if widget_color == v:
				return
			widget_color = v
			_mark_layout_dirty()

	var label_text: String = "":
		set(v):
			if label_text == v:
				return
			label_text = v
			_push(_label, &"text", v)

	func _build_children() -> void:
		build_count += 1
		_label = Label.new()
		add_child(_label)

	func _update_layout() -> void:
		layout_count += 1


func _ready() -> void:
	var failed := false

	var c := _TestComponent.new()
	add_child(c)

	# 1. Build + initial layout fire once during _ensure_built.
	failed = _expect(c.build_count == 1, "_build_children fires once during _ready", failed)
	failed = _expect(c.layout_count == 1, "_update_layout fires once during _ensure_built", failed)

	# 2. Three rapid sets coalesce into a single deferred _update_layout.
	c.widget_color = Color.RED
	c.widget_color = Color.BLUE
	c.widget_color = Color.GREEN
	failed = _expect(c.layout_count == 1, "no _update_layout yet (deferred)", failed)
	await get_tree().process_frame
	failed = _expect(c.layout_count == 2, "3 rapid sets coalesce to 1 layout", failed)

	# 3. _push writes synchronously.
	c.label_text = "hello"
	failed = _expect(c._label.text == "hello", "_push writes synchronously", failed)

	# 4. _push with a null child is a no-op (doesn't crash).
	c._push(null, &"text", "ignored")
	failed = _expect(true, "_push(null) doesn't crash", failed)

	if failed:
		print("[FAIL] UIComponent contract test")
	else:
		print("[PASS] UIComponent contract test")

	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, label: String, prev_failed: bool) -> bool:
	if condition:
		print("[ok]   ", label)
		return prev_failed
	print("[FAIL] ", label)
	return true
