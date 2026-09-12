extends Node3D

## Guard (ADR-0088 Amendment 5 §5 — role audit): the decisive proof that role is PER-INSTANCE.
## UIVitalsRoster grows/shrinks a dynamic list of UIUnitInfoWindow panels (one template applied
## to all). The SAME UIUnitInfoWindow class is ELEMENT inside the unit cluster (slice 4) — but a
## roster panel is repeated, data-driven PAYLOAD: it must answer PAYLOAD, mint no slug, and stay
## OUT of the UI3Registry index across resize churn (else N identical rows + register/unregister
## thrash every frame_count change).
##   A. PAYLOAD — every grown roster panel answers Role.PAYLOAD and is unregistered.
##   B. NO CHURN — growing then shrinking the roster leaves the registry index exactly as it
##      started (no roster panel ever entered it).
##
## Run: <GODOT> --path . --quit-after 20 res://tests/UIVitalsRosterRoleAuditTest.tscn

var _failed := false


func _ready() -> void:
	var before: int = UI3Registry.elements().size()

	var roster := UIVitalsRoster.new()
	roster.name = "VitalsRoster"
	add_child(roster)
	roster.frame_count = 5
	await get_tree().process_frame
	await get_tree().process_frame

	_audit_panels(roster, "grow to 5")
	_expect(UI3Registry.elements().size() == before,
		"growing the roster must not register any panel (index %d -> %d)"
			% [before, UI3Registry.elements().size()])

	# Resize churn: shrink then grow. No panel should ever register.
	roster.frame_count = 2
	await get_tree().process_frame
	roster.frame_count = 4
	await get_tree().process_frame
	await get_tree().process_frame

	_audit_panels(roster, "resize churn")
	_expect(UI3Registry.elements().size() == before,
		"resize churn must leave the registry index unchanged (index %d -> %d)"
			% [before, UI3Registry.elements().size()])

	roster.free()
	await get_tree().process_frame
	_expect(UI3Registry.elements().size() == before, "freeing the roster must leave the index unchanged")

	if _failed:
		push_error("[FAIL] UIVitalsRosterRoleAuditTest")
		get_tree().quit(1)
	else:
		print("[PASS] UIVitalsRosterRoleAuditTest")
		get_tree().quit(0)


func _audit_panels(roster: Node, phase: String) -> void:
	var panels: Array = []
	_collect_panels(roster, panels)
	_expect(panels.size() > 0, "%s: no UIUnitInfoWindow panels found" % phase)
	for p: UIUnitInfoWindow in panels:
		_expect((p as UI3Element).role() == UI3Element.Role.PAYLOAD,
			"%s: a roster panel answered %d, expected PAYLOAD" % [phase, (p as UI3Element).role()])
		_expect(not UI3Registry.elements().has(p),
			"%s: a roster panel is registered (must be unregistered PAYLOAD)" % phase)


func _collect_panels(n: Node, out: Array) -> void:
	if n is UIUnitInfoWindow:
		out.append(n)
	for c in n.get_children():
		_collect_panels(c, out)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[UIVitalsRosterRoleAuditTest] %s" % msg)
