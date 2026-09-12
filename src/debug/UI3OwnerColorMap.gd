class_name UI3OwnerColorMap
extends RefCounted

## The ownership-map MECHANISM (ADR-0088 Amendment 6 §1-§4): a debug-only object the
## pure-view page (UI3RegistryView) drives. It false-colors every registered element's
## OWN payload by a stable owner color, paints unowned payload the reserved ALARM color,
## and Mutes an element's payload — all on the LIVE game meshes (the map "draws" in the
## game viewport, §5, because we swap the material of the meshes already rendering there).
##
## Two INDEPENDENT, individually-LOSSLESS mutations (the load-bearing invariant §7):
##   • The color swap touches ONLY material_override. activate() captures each owned
##     mesh's prior material_override and swaps in a per-mesh debug material; deactivate()
##     restores the exact prior value (same object). Surface/mesh materials are never
##     touched. So a map on→off cycle leaves materials byte-identical.
##   • Mute touches ONLY `visible`. set_muted() captures each payload mesh's prior
##     `visible` and sets it false; clearing restores the exact prior value (never
##     force-true, §4 — a transition-hidden payload stays hidden). So a mute on→off
##     cycle leaves visibility byte-identical.
## Because the two mutations use disjoint fields they compose without interference: the
## map may be toggled while rows are muted and vice-versa, each restoring exactly.
##
## No production-shader edits (§2): faithful color comes from THIS debug shader sampling
## the mesh's own shape (glyph silhouette or full rect), not a tint uniform baked into
## the ~15 UI shaders.

const OwnerColors := preload("res://src/debug/UI3OwnerColors.gd")
const DEBUG_SHADER := "res://assets/shaders/ui3_owner_color.gdshader"
const ClipEngine := preload("res://src/ui3/UI3ClipEngine.gd")

var _active := false
# Captured swaps for a lossless restore: [{ "mesh": MeshInstance3D, "prev": Material }].
var _swap: Array = []
# element id -> the owner Color assigned this cycle (the legend the page mirrors).
var _colors: Dictionary = {}
# element id -> [{ "mesh": MeshInstance3D, "prev": bool }] captured on Mute.
var _mute: Dictionary = {}


## Assign each registered element its ROYGBIV owner color by its rank in the FLATTENED
## panel list (the depth-first display order the page renders — roots in order, each
## followed by its subtree), and return the id→Color map. Walking the display order (not
## registration order) is what makes the legend read top→bottom red→violet and a row's
## swatch the same color the mesh will wear. Reassigns each call (membership/shape may
## have changed — the ramp re-spreads to stay even; Amendment 6 revision).
func assign_colors(registry: Node) -> Dictionary:
	_colors = {}
	var flat: Array = _flatten(registry)
	var n: int = flat.size()
	for rank in n:
		_colors[(flat[rank] as UI3Element).id()] = OwnerColors.color_for_rank(rank, n)
	return _colors


## The flattened display order: each root, then its subtree depth-first (children_of),
## pre-order — the exact order UI3RegistryView._add_element renders rows in.
func _flatten(registry: Node) -> Array:
	var out: Array = []
	for root: UI3Element in registry.roots():
		_flatten_into(registry, root, out)
	return out


func _flatten_into(registry: Node, e: UI3Element, out: Array) -> void:
	out.append(e)
	for child: UI3Element in registry.children_of(e):
		_flatten_into(registry, child, out)


## The owner color for an element id (ALARM as a defensive fallback if unassigned).
func owner_color_for(id: String) -> Color:
	return _colors.get(id, OwnerColors.ALARM)


## The INVERSE of owner_color_for: which element is wearing this on-screen color? Lets a click
## on the map name the element under the cursor, since the map is already a false-color ID
## buffer. Returns "" when the color belongs to no owner. See [method resolve_owner].
func owner_for_color(c: Color) -> String:
	return resolve_owner(_colors, c)


## How close a framebuffer read may sit to an owner color and still count as that owner, per
## 8-bit channel. MEASURED, not chosen: reading the real compositor output back, an owner color
## returns byte-equal or off by exactly one on a single saturated channel (startmenu.frame
## 162,193,255 read back 161,193,255), deterministically. One is the whole observed error.
const PICK_CHANNEL_TOLERANCE := 1


## Resolve an on-screen color to the element id wearing it, over the given id->Color palette.
##
## EXACT 8-bit match first; failing that, a match within [constant PICK_CHANNEL_TOLERANCE] on
## every channel, which must land on exactly ONE owner. This is deliberately NOT a nearest-color
## match. The ramp is an equal-hue-step red->violet sweep whose spacing compresses as the
## element count grows — measured min pairwise L1 over color_for_rank is 44 at N=18 but 8 at
## N=80 and 3 at N=200 — so snapping to the closest owner gets less trustworthy exactly when the
## map is most crowded. Instead a color that is near nothing returns "" (the honest answer: you
## clicked something the map does not own, or something occluding it), and a color inside the
## tolerance box of TWO owners also returns "" rather than picking one of them.
##
## ALARM never resolves to an owner: it is reserved for unowned payload and sits L1 223 from
## every owner color at every N. Use [method is_alarm_color] to tell "unowned payload" apart
## from "nothing".
static func resolve_owner(colors: Dictionary, c: Color) -> String:
	var r := roundi(c.r * 255.0)
	var g := roundi(c.g * 255.0)
	var b := roundi(c.b * 255.0)
	var near := ""
	var near_count := 0
	for id: String in colors.keys():
		var o: Color = colors[id]
		var orr := roundi(o.r * 255.0)
		var og := roundi(o.g * 255.0)
		var ob := roundi(o.b * 255.0)
		if orr == r and og == g and ob == b:
			return id                      # exact — no tolerance needed, no ambiguity possible
		if absi(orr - r) <= PICK_CHANNEL_TOLERANCE and absi(og - g) <= PICK_CHANNEL_TOLERANCE \
				and absi(ob - b) <= PICK_CHANNEL_TOLERANCE:
			near = id
			near_count += 1
	if near_count == 1:
		return near
	return ""                              # nothing near, or too many near to be honest about


## The id->Color assignment from the last [method assign_colors] — the legend, as data.
## (The page mirrors it per row via [method owner_color_for]; a pick needs the whole map.)
func assigned_colors() -> Dictionary:
	return _colors


## Are these two colors within the pick tolerance on every 8-bit channel? The predicate
## [method resolve_owner] matches on, exposed so a caller can ask WHY a pick was ambiguous.
static func within_pick_tolerance(a: Color, b: Color) -> bool:
	return absi(roundi(a.r * 255.0) - roundi(b.r * 255.0)) <= PICK_CHANNEL_TOLERANCE \
		and absi(roundi(a.g * 255.0) - roundi(b.g * 255.0)) <= PICK_CHANNEL_TOLERANCE \
		and absi(roundi(a.b * 255.0) - roundi(b.b * 255.0)) <= PICK_CHANNEL_TOLERANCE


## Is this the reserved unowned-payload color? Pure magenta at full saturation, which
## color_for_rank can never emit — so "clicked unowned payload" stays a distinct answer from
## "clicked nothing the map knows".
static func is_alarm_color(c: Color) -> bool:
	return roundi(c.r * 255.0) == roundi(OwnerColors.ALARM.r * 255.0) \
		and roundi(c.g * 255.0) == roundi(OwnerColors.ALARM.g * 255.0) \
		and roundi(c.b * 255.0) == roundi(OwnerColors.ALARM.b * 255.0)


func is_active() -> bool:
	return _active


## Turn the map on: swap every owned mesh to its owner color, and (for each UI sweep
## root given, §3) paint every unowned UI-payload mesh the ALARM color. `ui_roots` are
## the screen mount subtrees to audit — scoped deliberately so the sweep never wanders
## into battle meshes (see UI3RegistryView._sweep_roots). Idempotent.
func activate(registry: Node, ui_roots: Array = []) -> void:
	if _active:
		return
	assign_colors(registry)
	var owned := {}          # mesh instance id -> true, so the unowned sweep can subtract it
	var owned_shaders := {}  # shader resource path -> true: the "this is UI payload" fingerprint
	for e: UI3Element in registry.elements():
		var color: Color = _colors.get(e.id(), OwnerColors.ALARM)
		for mesh in registry.payload_meshes(e):
			owned[(mesh as Object).get_instance_id()] = true
			var sp := _shader_path(mesh)
			if sp != "":
				owned_shaders[sp] = true
			_swap_mesh(mesh, color)
	# The unowned sweep alarms ONLY meshes whose shader a registered element also uses —
	# so a genuine UI-payload orphan lights up, but battle meshes sharing the sweep subtree
	# (terrain via indexed_color, unit sprites via unit.gdshader) are never false-alarmed.
	# Self-calibrating: no hardcoded UI-shader list to keep in sync. (A UI shader used ONLY
	# by an orphan — no registered rider — is missed; acceptable vs. magenta-bombing the map.)
	var alarmed := {}   # dedup: a mesh reachable from two roots is swapped once
	for root in ui_roots:
		if root == null:
			continue
		for mesh in _shader_meshes_under(root):
			var mid: int = (mesh as Object).get_instance_id()
			if owned.has(mid) or alarmed.has(mid):
				continue
			if not owned_shaders.has(_shader_path(mesh)):
				continue
			alarmed[mid] = true
			_swap_mesh(mesh, OwnerColors.ALARM)
	_active = true


## Turn the map off: restore every swapped mesh's material_override byte-identical.
## Leaves Mute untouched (the two are independent).
func deactivate() -> void:
	for entry in _swap:
		# Validate BEFORE the typed read, not after. Assigning a freed instance to a typed local
		# is itself an error that ABORTS this loop — so an `is_instance_valid(mesh)` guard placed
		# after the assignment is dead code, and payload freed between activate() and here (a
		# picker closing is enough) left every LATER mesh wearing its debug material with the map
		# stuck active. Guard: UI3OwnershipMapTest slice 7.
		var captured: Variant = entry["mesh"]
		if captured == null or not is_instance_valid(captured):
			continue
		(captured as MeshInstance3D).material_override = entry["prev"]
	_swap = []
	_active = false


## Mute (or unmute) one element's OWN payload — pure `visible`, independent of the swap.
## Capturing prior visibility means an already-hidden payload restores to hidden (§4).
func set_muted(element: UI3Element, on: bool) -> void:
	var id := element.id()
	if on:
		if _mute.has(id):
			return
		var captured: Array = []
		for mesh in element.payload_meshes():
			var mi := mesh as MeshInstance3D
			captured.append({"mesh": mi, "prev": mi.visible})
			mi.visible = false
		_mute[id] = captured
	else:
		_restore_mute(id)


## True while `id`'s own payload is muted.
func is_muted(id: String) -> bool:
	return _mute.has(id)


## The ids of every currently-muted element.
func muted_ids() -> Array:
	return _mute.keys()


## The page-level "Clear all": drop the map AND every Mute, restoring the live game to
## exactly its pre-map state (the auto-clear guarantee, §4).
func clear_all() -> void:
	for id in _mute.keys():
		_restore_mute(id)
	_mute = {}
	deactivate()


# --- internals ---------------------------------------------------------------
func _restore_mute(id: String) -> void:
	if not _mute.has(id):
		return
	for entry in _mute[id]:
		# Same order as deactivate(): validate before the typed read, or one freed mesh aborts
		# the loop and leaves every later element muted with no way back.
		var captured: Variant = entry["mesh"]
		if captured == null or not is_instance_valid(captured):
			continue
		(captured as MeshInstance3D).visible = entry["prev"]
	_mute.erase(id)


## Capture a mesh's prior material_override and swap in a per-mesh debug material tinted
## `color`, faithfully shaped from the mesh's own payload.
func _swap_mesh(mesh: MeshInstance3D, color: Color) -> void:
	_swap.append({"mesh": mesh, "prev": mesh.material_override})
	mesh.material_override = _debug_material(mesh, color)


## Build the per-mesh debug material: owner color + a shape faithful to the payload's
## own shader (glyph atlas → silhouette; anything else → its full rect).
func _debug_material(mesh: MeshInstance3D, color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(DEBUG_SHADER)
	mat.set_shader_parameter("owner_color", color)
	var src := _primary_shader_material(mesh)
	if src != null:
		# A glyph payload carries an index_atlas + cell — replicate its silhouette.
		var atlas: Variant = src.get_shader_parameter("index_atlas")
		if atlas is Texture2D:
			mat.set_shader_parameter("shape_mode", 1)
			mat.set_shader_parameter("index_atlas", atlas)
			var cell: Variant = src.get_shader_parameter("cell")
			if cell != null:
				mat.set_shader_parameter("cell", cell)
			var asz: Variant = src.get_shader_parameter("atlas_size")
			if asz != null:
				mat.set_shader_parameter("atlas_size", asz)
		# Carry the world aperture so apertured (box-open) content stays clipped.
		var clip: Variant = src.get_shader_parameter("clip_world")
		if clip != null:
			mat.set_shader_parameter("clip_world", clip)
		# ...and the BASIS the box is expressed in, which `ui3_owner_color.gdshader` declares
		# alongside it and defaults to IDENTITY. The two are one answer, not two: `clip_world`
		# is a rect in the SCREEN's space and the shader tests it against
		# `clip_basis_inv * MODEL_MATRIX * VERTEX`. Copying the rect and not the basis compares
		# a display-space box against a GLOBAL vertex, so on any screen whose root is not at the
		# world origin — every camera-child host, every map-hosted formation screen — the map
		# drew a correct color onto zero surviving fragments and read as "the ownership map is
		# broken on this panel".
		var basis: Variant = src.get_shader_parameter("clip_basis_inv")
		if basis != null:
			mat.set_shader_parameter("clip_basis_inv", basis)
	return mat


## The resource path of a mesh's primary shader ("" when none) — the UI-payload
## fingerprint the unowned sweep matches against the owned set.
static func _shader_path(mesh: MeshInstance3D) -> String:
	var sm := _primary_shader_material(mesh)
	if sm != null and sm.shader != null:
		return sm.shader.resource_path
	return ""


## The effective ShaderMaterial a mesh renders with (override wins, else the first
## surface override, else the first mesh-surface material) — the one whose shape/uniforms
## the debug material mirrors.
static func _primary_shader_material(mesh: MeshInstance3D) -> ShaderMaterial:
	if mesh.material_override is ShaderMaterial:
		return mesh.material_override
	for i in mesh.get_surface_override_material_count():
		if mesh.get_surface_override_material(i) is ShaderMaterial:
			return mesh.get_surface_override_material(i)
	if mesh.mesh != null:
		for i in mesh.mesh.get_surface_count():
			if mesh.mesh.surface_get_material(i) is ShaderMaterial:
				return mesh.mesh.surface_get_material(i)
	return null


## Every MeshInstance3D carrying a ShaderMaterial anywhere in `root`'s subtree — the
## candidate set for the unowned sweep (§3). Reuses the clip engine's membership test so
## "is this UI payload" is one definition.
static func _shader_meshes_under(root: Node) -> Array:
	var out: Array = []
	_gather_shader_meshes(root, out)
	return out


static func _gather_shader_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and ClipEngine._mesh_has_shader(node as MeshInstance3D):
		out.append(node)
	for c in node.get_children():
		_gather_shader_meshes(c, out)
