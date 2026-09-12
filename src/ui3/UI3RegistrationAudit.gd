class_name UI3RegistrationAudit
extends RefCounted

## The registration audit (ADR-0088 §7.2; interfaces §8) — the enforcement ratchet's
## runtime detector, piggybacked on each screen's existing guard scene: boot the
## screen headful, tree-walk, and every RENDERING PAYLOAD (a MeshInstance3D carrying
## a ShaderMaterial, override or surface) under the audited UI root must sit under a
## registered UI3Element. Violations fail unless the owning class is on the tracked
## allowlist — which is SHRINK-ONLY and TWO-SIDED: growth of violations fails, and a
## listed class with zero current violations also fails ("remove <class>"), so an
## entry cannot linger after its migration lands. Growth of the file itself needs a
## code change reviewers see in the same diff as the new violating class.

const ALLOWLIST_PATH := "res://config/ui3_registration_allowlist.json"


## Every unowned payload mesh under `ui_root`: {node: NodePath, owner_class: String}.
## owner_class = the nearest ancestor with a script (its class_name, else the script
## path) — the class the allowlist names. Scoping the walk to the screen's UI root
## excludes world/battle meshes without heuristics.
static func violations(ui_root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_walk(ui_root, ui_root, false, out)
	return out


static func _walk(node: Node, ui_root: Node, under_element: bool, out: Array[Dictionary]) -> void:
	if node is UI3Element:
		under_element = true
	if not under_element and node is MeshInstance3D and _carries_shader_material(node):
		out.append({"node": ui_root.get_path_to(node), "owner_class": _owner_class(node, ui_root)})
	for c in node.get_children():
		_walk(c, ui_root, under_element, out)


static func _carries_shader_material(mi: MeshInstance3D) -> bool:
	if mi.material_override is ShaderMaterial:
		return true
	for i in mi.get_surface_override_material_count():
		if mi.get_surface_override_material(i) is ShaderMaterial:
			return true
	if mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_material(i) is ShaderMaterial:
				return true
	return false


static func _owner_class(node: Node, ui_root: Node) -> String:
	var n: Node = node
	while n != null:
		var script: Script = n.get_script()
		if script != null:
			var global_name := script.get_global_name()
			return String(global_name) if global_name != StringName("") else script.resource_path
		if n == ui_root:
			break
		n = n.get_parent()
	return "<unowned>"


## The two-sided verdict against an explicit class list (the pure seam guards drive):
## one error per violation whose owner is NOT listed, plus one "remove <class>" error
## per LISTED class with zero current violations (the forced shrink).
static func check(ui_root: Node, allowed_classes: Array) -> Array[String]:
	var errors: Array[String] = []
	var seen := {}
	for v: Dictionary in violations(ui_root):
		var owner := String(v["owner_class"])
		seen[owner] = true
		if not allowed_classes.has(owner):
			errors.append("unregistered payload at '%s' (owner %s) — register it as/under a UI3Element, or allowlist the class in %s"
				% [v["node"], owner, ALLOWLIST_PATH])
	for cls in allowed_classes:
		if not seen.has(cls):
			errors.append("remove %s from the allowlist — it has zero violations under this root (shrink-only ratchet)"
				% cls)
	return errors


## The no-empty-`DERIVED` audit (ADR-0088 Amendment 4 §3) — the second enforcement
## detector, same family as the payload audit above. Once `screen_anchored()` marks the
## intentionally-unplaced assemblies, any REMAINING rect that reports `Source.DERIVED`
## with `drivers == []` (a `derived([])` sentinel or a bare `Callable`) is a genuine
## "author forgot to declare this rect's drivers" gap — invisible today as a read-only
## page row. This tree-walks the registered elements under `ui_root` and returns the ids
## of the offenders; SCREEN_ANCHORED, AT_LOCATION, and AUTHORED are exempt by source.
static func empty_derived_violations(ui_root: Node) -> Array:
	var out: Array = []
	_walk_empty_derived(ui_root, out)
	return out


static func _walk_empty_derived(node: Node, out: Array) -> void:
	if node is UI3Element:
		for row: Dictionary in (node as UI3Element).criteria():
			if String(row.get("field", "")) != "rect":
				continue
			if row.get("source") == UI3Element.Source.DERIVED \
					and (row.get("drivers", []) as Array).is_empty():
				out.append((node as UI3Element).id())
			break
	for c in node.get_children():
		_walk_empty_derived(c, out)


## The per-screen verdict against a seed list of allowed ids (the pure seam guards drive):
## one error per empty-`DERIVED` element whose id is NOT listed. Deliberately ONE-SIDED —
## the ratchet is enforced by shrinking the seed as slices land (an id removed but not yet
## converted re-appears here, unlisted, and fails). A listed-but-absent id is NOT an error,
## so a partial screen boot (only some elements instantiated) never spuriously fails.
static func check_empty_derived(ui_root: Node, allowed_ids: Array) -> Array[String]:
	var errors: Array[String] = []
	for id in empty_derived_violations(ui_root):
		if not allowed_ids.has(id):
			errors.append("empty-DERIVED rect on element '%s' — declare its drivers (derived([...])), make it screen_anchored(), or seed it in the guard's allowlist"
				% id)
	return errors


## The guard-scene verb: fail the run on any unlisted empty-`DERIVED` element (each pushed
## individually so the log names every gap).
static func assert_no_empty_derived(ui_root: Node, allowed_ids: Array = []) -> void:
	var errors := check_empty_derived(ui_root, allowed_ids)
	for e in errors:
		push_error("[UI3RegistrationAudit] %s" % e)
	assert(errors.is_empty(), "no-empty-DERIVED audit failed (%d problems — see errors)" % errors.size())


## The tracked allowlist's class array ([] when the file is absent or malformed).
static func load_allowlist(path: String = ALLOWLIST_PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	if parsed is Dictionary and parsed.get("classes") is Array:
		return parsed["classes"]
	return []


## The guard-scene verb: check against the tracked allowlist and FAIL the run on any
## error (each pushed individually so the log names every gap).
static func assert_owned(ui_root: Node, path: String = ALLOWLIST_PATH) -> void:
	var errors := check(ui_root, load_allowlist(path))
	for e in errors:
		push_error("[UI3RegistrationAudit] %s" % e)
	assert(errors.is_empty(), "UI3 registration audit failed (%d problems — see errors)" % errors.size())
