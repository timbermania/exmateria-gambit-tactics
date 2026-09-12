class_name UI3ClipEngine
extends RefCounted

## The shared clip engine (ADR-0088 §4; interfaces §3) — reads each element's `clip`
## criterion, discovers payload materials from the subtree, and pushes `clip_world`.
## Hosted by UI3Registry; internal — callers and the dashboard talk to UI3Element only.
##
## The stale-clip kill, by construction (the f8442784d bug class is unrepresentable):
##   1. Push = FRESH pull-walk. push(element) walks the subtree NOW, collects every
##      ShaderMaterial on a MeshInstance3D, and sets clip_world from the element's
##      LIVE aperture. Neither the material list nor the rect is cached.
##   2. Mount-time coverage. The host forwards SceneTree.node_added; a MeshInstance3D
##      entering under a registered element schedules a DEFERRED, COALESCED
##      push(owning_element) — newly mounted payload receives the current aperture
##      the frame it appears, no notify hand call in any normal path.

## The infinite (unbounded) aperture — the clip shaders' own default for `clip_world`
## (see formation_text_opaque.gdshader: xy = world min, zw = world max, discard
## outside). Pushed EXPLICITLY for UNCLIPPED so the uniform is always set — the
## cursor's exemption is a declared answer, not an omitted array membership. NOT the
## inverted (1e20,1e20,-1e20,-1e20) box: that one discards EVERYTHING and is what a
## degenerate (shut) aperture maps to below.
const UNCLIPPED_SENTINEL := Vector4(-1e20, -1e20, 1e20, 1e20)

# The hosting UI3Registry node — supplies children_of() and the deferred flush hook.
var _host: Node
# Elements with a pending coalesced re-push (element -> true; one flag per element
# per frame). Flushed via the host's call_deferred.
var _pending: Dictionary = {}
var _flush_scheduled := false


func _init(host: Node) -> void:
	_host = host


## SceneTree.node_added hook (forwarded by the host). The filter is the type check
## BEFORE any ancestor walk, so non-UI churn costs one `is`.
func on_node_added(node: Node) -> void:
	if not (node is MeshInstance3D):
		return
	var e := _owning_element(node)
	if e != null:
		schedule_push(e)


## Schedule a deferred, coalesced push for `element` (at most one per element per frame).
func schedule_push(element: UI3Element) -> void:
	_pending[element] = true
	if not _flush_scheduled:
		_flush_scheduled = true
		_host.call_deferred("_flush_clip_pushes")


## Drop a pending push (element left the tree before its flush — a freed key must
## never reach the typed push path).
func forget(element: UI3Element) -> void:
	_pending.erase(element)


## Run the pending coalesced pushes (called deferred by the host).
func flush() -> void:
	_flush_scheduled = false
	var elems := _pending.keys()
	_pending.clear()
	for e in elems:   # untyped: a key freed since scheduling must not abort the flush
		if is_instance_valid(e) and (e as Node).is_inside_tree():
			push(e)


## Fresh pull-walk push: apply the element's RESOLVED clip_world to every payload
## material in its subtree NOW, then recurse into nested elements (a PARENT_APERTURE
## child follows this element's aperture change through its own resolution).
func push(element: UI3Element) -> void:
	var cw := resolved_clip_world(element)
	var basis_inv := clip_basis_inv_for(element)
	for m: ShaderMaterial in payload_materials(element):
		m.set_shader_parameter("clip_world", cw)
		m.set_shader_parameter("clip_basis_inv", basis_inv)
	for child: UI3Element in _host.children_of(element):
		push(child)


## The transform that maps a GLOBAL position back into the screen's own space — the second half of
## the aperture test, and the half that used to be assumed.
##
## `clip_world` is an axis-aligned rect in display px * ppu, i.e. the SCREEN's space. The shaders
## compare it against `MODEL_MATRIX * VERTEX`, which is GLOBAL. Those are the same space only while
## the screen root sits at the world origin, unrotated and unscaled — true of every UI3 screen that
## owns its own camera, and false the moment one mounts as a CHILD of the map camera (ADR-0137),
## where the UI plane is rotated and scaled in world space. There the two spaces disagree by the
## camera's whole transform and EVERY clipped fragment falls outside the box: the box-opening panels
## render nothing at all while the unclipped chrome around them looks fine.
##
## The screen is the nearest ancestor that DEFINES display space — i.e. that answers
## `screen_to_world`. That is a real criterion, not a heuristic: `clip_world`'s px*ppu numbers are
## exactly that function's image, so whoever provides it is by definition the space they are in.
## No such ancestor (an element mounted bare in a test) ⇒ identity, the previous behaviour.
##
## STALENESS, stated because it is load-bearing rather than lucky: this is a snapshot of a GLOBAL
## transform, so it goes stale if the screen root MOVES between pushes — which on the map host means
## while the camera pans. It cannot bite, because the two do not overlap in time: the entry pan runs
## BEFORE `open_detail` builds anything clipped, and the exit pan runs AFTER the overlay is freed;
## the only UI up while the camera moves (the hover pair and the band) is UNCLIPPED, and an unclipped
## element's unbounded `clip_world` makes the test false whatever the basis says. If a future gesture
## ever animates the camera with a box-opening panel on screen, that panel needs a re-push per frame
## and this is the note that says so.
static func clip_basis_inv_for(element: UI3Element) -> Transform3D:
	var n: Node = element.get_parent()
	while n != null:
		if n is Node3D and n.has_method("screen_to_world"):
			return (n as Node3D).global_transform.affine_inverse()
		n = n.get_parent()
	return Transform3D.IDENTITY


## Re-push ONLY `clip_basis_inv`, for every registered element — the per-frame answer to the
## staleness the note above describes, and the gesture it says did not exist yet now does
## (ADR-0137 Amendment 3: the entry pan ZOOMS, and it plays with the detail panels already up).
##
## Deliberately not a `push()` loop. `clip_world` is a function of each element's own aperture and
## nothing the camera does can change it; only the basis moves. So this skips `resolved_clip_world`
## and the nested-element recursion entirely and writes the one uniform that went stale — which is
## what makes it cheap enough to run every frame of a pan.
func refresh_basis() -> void:
	for e: UI3Element in _host.elements():
		if not is_instance_valid(e) or not (e as Node).is_inside_tree():
			continue
		var basis_inv := clip_basis_inv_for(e)
		for m: ShaderMaterial in payload_materials(e):
			m.set_shader_parameter("clip_basis_inv", basis_inv)


## The clip_world for an element's declared answer: OWN_APERTURE = its live aperture;
## PARENT_APERTURE = the nearest OWN_APERTURE ancestor's (none in the chain → the
## sentinel, effectively unclipped); UNCLIPPED = the sentinel, explicitly.
func resolved_clip_world(element: UI3Element) -> Vector4:
	match element.clip_mode():
		UI3Element.Clip.OWN_APERTURE:
			return clip_world(element.aperture(), element.ppu())
		UI3Element.Clip.PARENT_APERTURE:
			var anc := element.parent_element()
			while anc != null and anc.clip_mode() != UI3Element.Clip.OWN_APERTURE:
				anc = anc.parent_element()
			if anc == null:
				return UNCLIPPED_SENTINEL
			return clip_world(anc.aperture(), anc.ppu())
		_:
			return UNCLIPPED_SENTINEL


## Display px → world clip box (x_min, y_min, x_max, y_max) — the one home for the
## math the three per-class _clip_world copies carried. A degenerate rect is the SHUT
## aperture: the inverted box discards every fragment (the box-close end state).
static func clip_world(rect: Rect2i, ppu: float) -> Vector4:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Vector4(1e20, 1e20, -1e20, -1e20)
	var x0 := float(rect.position.x) * ppu
	var x1 := float(rect.position.x + rect.size.x) * ppu
	var y_top := -float(rect.position.y) * ppu
	var y_bot := -float(rect.position.y + rect.size.y) * ppu
	return Vector4(x0, y_bot, x1, y_top)


## Every ShaderMaterial on a MeshInstance3D in `element`'s OWN subtree — nested
## registered elements are skipped (their payload is theirs). Collected fresh on
## every call; never cached. Public: also the guard/host discovery surface
## (UI3Element.payload_materials forwards here).
func payload_materials(element: UI3Element) -> Array:
	var out: Array = []
	_collect_materials(element, element, out)
	return out


## Every MeshInstance3D carrying a ShaderMaterial in `element`'s OWN subtree (nested
## registered elements excluded) — the SAME ownership boundary as payload_materials,
## but returning the NODES the ownership map swaps/mutes rather than their materials.
## Collected fresh; never cached. Public: the map mechanism + guards discover through
## UI3Registry.payload_meshes / UI3Element.payload_meshes.
func payload_meshes(element: UI3Element) -> Array:
	var out: Array = []
	_collect_meshes(element, element, out)
	return out


func _collect_meshes(node: Node, element: UI3Element, out: Array) -> void:
	if node != element and node is UI3Element:
		return
	if node is MeshInstance3D and _mesh_has_shader(node as MeshInstance3D):
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, element, out)


## True when a MeshInstance3D carries a ShaderMaterial anywhere the material walk reads
## it (override / surface override / mesh surface) — i.e. it has UI payload to clip or
## swap. The exact membership test _collect_materials uses, on the node itself.
static func _mesh_has_shader(mi: MeshInstance3D) -> bool:
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


func _collect_materials(node: Node, element: UI3Element, out: Array) -> void:
	if node != element and node is UI3Element:
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is ShaderMaterial and not out.has(mi.material_override):
			out.append(mi.material_override)
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i)
			if m is ShaderMaterial and not out.has(m):
				out.append(m)
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(i)
				if sm is ShaderMaterial and not out.has(sm):
					out.append(sm)
	for c in node.get_children():
		_collect_materials(c, element, out)


func _owning_element(node: Node) -> UI3Element:
	var n := node.get_parent()
	while n != null:
		if n is UI3Element:
			return n
		n = n.get_parent()
	return null
