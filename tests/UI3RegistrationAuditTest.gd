extends Node3D

## Guard (ADR-0088 slice 6): the registration audit — every rendering payload
## (MeshInstance3D carrying a ShaderMaterial) under an audited UI root must sit
## under a registered UI3Element, unless its owning class is on the SHRINK-ONLY
## allowlist.
##   A. violations(): an unowned payload mesh is reported with its owner class
##      (nearest scripted ancestor); element-owned payload is not.
##   B. check() two-sided: a violation whose owner is listed passes; unlisted fails
##      (growth of violations fails); a LISTED class with ZERO violations fails with
##      "remove" (forced shrink — an entry cannot linger after its migration lands).
##   C. The tracked allowlist file loads.

var _failed := false


func _ready() -> void:
	# The audited UI root is the SCREEN's own scripted node (the per-screen guard
	# pattern: assert_owned(screen)); here the test node itself plays the screen.
	var ui_root: Node3D = self

	# An unowned payload mesh: under a plain holder, no UI3Element ancestor. The
	# nearest scripted ancestor is the screen root → owner_class falls back to the
	# script path (test scripts carry no class_name).
	var holder := Node3D.new()
	ui_root.add_child(holder)
	holder.add_child(_payload_quad())

	# Element-owned payload: same shape, under a registered element — never a violation.
	var elem: UI3Element = UI3Element.new({
		"id": "t.audit.win",
		"rect": Rect2(0, 0, 32, 32),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	ui_root.add_child(elem)
	elem.add_child(_payload_quad())

	# A mesh with NO ShaderMaterial (a plain StandardMaterial3D) is not payload.
	var plain := MeshInstance3D.new()
	plain.mesh = QuadMesh.new()
	plain.material_override = StandardMaterial3D.new()
	ui_root.add_child(plain)

	await get_tree().process_frame

	# --- A. violations ----------------------------------------------------------
	var v: Array = UI3RegistrationAudit.violations(ui_root)
	_expect(v.size() == 1, "exactly the unowned ShaderMaterial mesh must violate, got %d: %s"
		% [v.size(), v])
	var owner_class := ""
	if v.size() == 1:
		owner_class = String(v[0]["owner_class"])
		_expect(owner_class.ends_with("UI3RegistrationAuditTest.gd"),
			"owner_class must name the nearest scripted ancestor, got '%s'" % owner_class)

	# --- B. two-sided check -----------------------------------------------------
	var listed := UI3RegistrationAudit.check(ui_root, [owner_class])
	_expect(listed.is_empty(), "a listed owner must pass, got %s" % [listed])

	var unlisted := UI3RegistrationAudit.check(ui_root, [])
	_expect(unlisted.size() == 1 and String(unlisted[0]).contains(owner_class),
		"an UNLISTED violation must fail naming the owner, got %s" % [unlisted])

	var lingering := UI3RegistrationAudit.check(ui_root, [owner_class, "GhostClass"])
	_expect(lingering.size() == 1 and String(lingering[0]).contains("remove")
		and String(lingering[0]).contains("GhostClass"),
		"a listed class with zero violations must fail with 'remove', got %s" % [lingering])

	# --- C. the tracked allowlist file loads ------------------------------------
	var classes: Array = UI3RegistrationAudit.load_allowlist()
	_expect(classes is Array, "the tracked allowlist must load as a class array")

	if _failed:
		push_error("[FAIL] UI3RegistrationAuditTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3RegistrationAuditTest")
		get_tree().quit(0)


func _payload_quad() -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(1.0); }"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	mi.material_override = mat
	return mi


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[UI3RegistrationAuditTest] %s" % msg)
