extends Node3D

## Guard (ADR-0088 Amendment 5 §2/§5 — the base-swap boot audit): `UIComponent extends
## UI3Element`, so every window/button/roster widget is now natively element-capable. The
## base-swap must be INERT for the un-migrated widget world: each subclass boots untouched,
## answers the default role PAYLOAD, and never enters the UI3Registry index (no missing-id
## boot assert, no stray page row). ELEMENT migration is a per-instance opt-in (§4), not a
## consequence of the base change.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/UIComponentBootAuditTest.tscn

var _failed := false


func _ready() -> void:
	# A representative spread of the un-migrated widget classes (UIWindow + subtypes, button,
	# rosters, frame, vitals panel). Each must boot bare, answer PAYLOAD, and stay unregistered.
	var factories := {
		"UIButton": func() -> Node: return UIButton.new(),
		"UIWindow": func() -> Node: return UIWindow.new(),
		"UIMenuFrame": func() -> Node: return UIMenuFrame.new(),
		"UIRosterBar": func() -> Node: return UIRosterBar.new(),
		"UIVitalsRoster": func() -> Node: return UIVitalsRoster.new(),
		"UIGambitDisplay": func() -> Node: return UIGambitDisplay.new(),
		"UIModalWindow": func() -> Node: return UIModalWindow.new(),
		"UIUnitInfoWindow": func() -> Node: return UIUnitInfoWindow.new(),
	}

	var before: int = UI3Registry.elements().size()
	for cls_name: String in factories:
		var w: Node = (factories[cls_name] as Callable).call()
		_expect(w is UIComponent, "%s must be a UIComponent" % cls_name)
		_expect(w is UI3Element, "%s must be a UI3Element after the base-swap" % cls_name)
		w.name = cls_name + "Instance"
		add_child(w)
		await get_tree().process_frame

		# The un-migrated widget answers PAYLOAD by default...
		_expect((w as UI3Element).role() == UI3Element.Role.PAYLOAD,
			"%s must default to Role.PAYLOAD" % cls_name)
		# ...and therefore never enters the registry index (no page row, no slug).
		_expect(not UI3Registry.elements().has(w),
			"%s (PAYLOAD) must NOT register in UI3Registry" % cls_name)
		w.free()
		await get_tree().process_frame

	# The index is exactly where it started — the base-swap added nobody.
	_expect(UI3Registry.elements().size() == before,
		"the base-swap must not change the registry index size (%d -> %d)"
			% [before, UI3Registry.elements().size()])

	if _failed:
		push_error("[FAIL] UIComponentBootAuditTest")
		get_tree().quit(1)
	else:
		print("[PASS] UIComponentBootAuditTest")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[UIComponentBootAuditTest] %s" % msg)
