extends Node3D

## Guard (ADR-0088 Amendment 6): the UI3 ownership map — false-color each element's
## OWN payload by a stable, sibling-distinct owner color; a lossless debug material
## swap (no production-shader edits); unowned payload → a reserved alarm color; and a
## per-element Mute (pure visibility, captured + restored exactly). The MECHANISM
## lives in UI3OwnerColors (palette) + UI3OwnerColorMap (swap/mute/alarm), driven by
## the pure-view page (UI3RegistryView, guarded in UI3RegistryPageTest).
##
## Slices:
##   1. Owner-color palette: a flattened-list ROYGBIV ramp — perceptually spaced
##      (equal OKLab steps), hue MONOTONIC by rank, ALARM reserved.
##   1b. Distinctness: min pairwise OKLab distance across owners exceeds a threshold.
##   2. payload_meshes: an element's own MeshInstance3Ds, nested elements excluded.
##   3. Lossless swap: activate→deactivate leaves material_override byte-identical, and the
##      debug material MIRRORS the payload's clip pair — `clip_world` AND `clip_basis_inv`.
##   4. Unowned payload resolves to the alarm color.
##   5. Mute: hides own payload, restores prior visibility exactly, multi-mute stacks,
##      orthogonal to the swap.
##   6. assign_colors walks the registry tree in FLATTENED depth-first pre-order (the
##      UI3RegistryView render order), so a row's swatch == its on-screen swap color and
##      the legend reads top→bottom red→violet.

const OwnerColors := preload("res://src/debug/UI3OwnerColors.gd")

var _failed := false


func _ready() -> void:
	_test_palette()
	_test_distinctness()
	_test_adjacent_distinctness()
	await _test_payload_meshes()
	await _test_lossless_swap()
	await _test_unowned_alarm()
	await _test_mute()
	await _test_flattened_order()
	await _test_payload_freed_while_the_map_is_on()
	_finish()


# --- Slice 1: the ROYGBIV owner-color palette --------------------------------
func _test_palette() -> void:
	var n := 8
	var prev_hue := -1.0
	for rank in n:
		var c: Color = OwnerColors.color_for_rank(rank, n)
		_expect(OwnerColors.color_for_rank(rank, n).is_equal_approx(c),
			"color_for_rank(%d, %d) must be deterministic across calls" % [rank, n])
		# Hue runs red→violet down the list: strictly increasing, and inside the ROYGBIV
		# arc (short of magenta at ~328°) so no owner color drifts toward ALARM's magenta.
		var hue: float = OwnerColors.oklab_hue_deg(c)
		_expect(hue > prev_hue,
			"owner hue must increase with rank (ROYGBIV top→bottom) — rank %d hue %.1f <= %.1f" \
				% [rank, hue, prev_hue])
		_expect(hue >= 20.0 and hue <= 310.0,
			"owner hue %.1f (rank %d) must sit inside the red→violet arc, short of magenta" \
				% [hue, rank])
		prev_hue = hue
		_expect(not c.is_equal_approx(OwnerColors.ALARM),
			"owner color rank %d must not equal the reserved ALARM color" % rank)
	# First is red-ish, last is violet-ish (endpoints of the arc).
	_expect(OwnerColors.oklab_hue_deg(OwnerColors.color_for_rank(0, n)) < 40.0,
		"rank 0 must be red (arc start)")
	_expect(OwnerColors.oklab_hue_deg(OwnerColors.color_for_rank(n - 1, n)) > 270.0,
		"the last rank must be violet (arc end, short of magenta)")
	# Degenerate n: a single owner is well-defined and still not ALARM.
	_expect(not OwnerColors.color_for_rank(0, 1).is_equal_approx(OwnerColors.ALARM),
		"a lone owner (n=1) must resolve to a real color, never ALARM")


# --- Slice 1b: "distinct enough" — min pairwise OKLab distance ----------------
func _test_distinctness() -> void:
	# The concrete answer to "not distinct enough": every pair of owner colors must sit
	# at least THRESHOLD apart in OKLab (≈ perceived difference), for a realistic N. The
	# lightness zigzag (Am6 §8) buys margin over the old hue-only ramp, so the threshold is
	# raised from 0.05 to 0.10.
	const THRESHOLD := 0.10
	var n := 10
	var cols: Array = []
	for rank in n:
		cols.append(OwnerColors.oklab(OwnerColors.color_for_rank(rank, n)))
	var worst := 1e9
	for i in n:
		for j in range(i + 1, n):
			var d: float = (cols[i] - cols[j]).length()
			worst = min(worst, d)
	_expect(worst >= THRESHOLD,
		"owners must be perceptually distinct — min pairwise OKLab distance %.4f < %.2f" \
			% [worst, THRESHOLD])


# --- Slice 1c: ADJACENT distinctness — the "colors too similar" fix (Am6 §8) --
func _test_adjacent_distinctness() -> void:
	# The user's complaint was that NEIGHBOURING rows read alike: as N grows the hue-only
	# ramp compressed adjacent OKLab distance (0.083 @N=8 → 0.039 @N=16). The lightness
	# zigzag alternates brightness by rank, so *adjacent* rows always differ in L even when
	# their hues are close. Assert the min adjacent distance at a large N clears a threshold
	# far above the old hue-only 0.039 — this is the slice that proves the fix.
	const ADJ_THRESHOLD := 0.15
	var n := 16
	var worst := 1e9
	for rank in n - 1:
		var a: Vector3 = OwnerColors.oklab(OwnerColors.color_for_rank(rank, n))
		var b: Vector3 = OwnerColors.oklab(OwnerColors.color_for_rank(rank + 1, n))
		worst = min(worst, (a - b).length())
	_expect(worst >= ADJ_THRESHOLD,
		"adjacent owner rows must be brightness-distinct (zigzag) — min adjacent OKLab distance %.4f < %.2f" \
			% [worst, ADJ_THRESHOLD])


# --- Slice 2: own-payload MESH walk (nested elements excluded) ---------------
func _test_payload_meshes() -> void:
	var parent := UI3Element.new({
		"id": "t.map.win",
		"rect": Rect2(10, 10, 100, 60),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(parent)
	# Own payload: a direct mesh, and one nested under a plain Node3D (still the
	# parent's own — a plain node is not an ownership boundary).
	var own_direct := _payload_mesh("own_direct")
	parent.add_child(own_direct)
	var holder := Node3D.new()
	parent.add_child(holder)
	var own_deep := _payload_mesh("own_deep")
	holder.add_child(own_deep)
	# A mesh with NO ShaderMaterial is not payload (nothing to swap/clip).
	var bare := MeshInstance3D.new()
	bare.mesh = QuadMesh.new()
	parent.add_child(bare)
	# A NESTED registered element with its own mesh — the ownership boundary: its
	# payload is ITS own, excluded from the parent's set.
	var child := UI3Element.new({
		"id": "t.map.win.row",
		"rect": Rect2(20, 20, 40, 16),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	parent.add_child(child)
	var child_mesh := _payload_mesh("child_mesh")
	child.add_child(child_mesh)
	await get_tree().process_frame

	var registry := get_node_or_null("/root/UI3Registry")
	var parent_meshes: Array = registry.payload_meshes(parent)
	_expect(parent_meshes.has(own_direct) and parent_meshes.has(own_deep),
		"payload_meshes must include the element's own payload meshes (direct + nested-under-plain-node)")
	_expect(not parent_meshes.has(child_mesh),
		"payload_meshes must STOP at a nested UI3Element (its mesh is the child's own payload)")
	_expect(not parent_meshes.has(bare),
		"payload_meshes must skip a mesh with no ShaderMaterial (no payload to swap)")
	# The element convenience forwarder returns the same set.
	_expect(parent.payload_meshes().size() == parent_meshes.size(),
		"UI3Element.payload_meshes() must forward to the registry set")
	# The child owns exactly its own mesh.
	var child_meshes: Array = registry.payload_meshes(child)
	_expect(child_meshes == [child_mesh],
		"a nested element owns exactly its own mesh, got %s" % [child_meshes])

	parent.free()


# --- Slice 3: the LOSSLESS owner-color swap ----------------------------------
func _test_lossless_swap() -> void:
	var registry := get_node_or_null("/root/UI3Registry")
	var root := UI3Element.new({
		"id": "t.map.s1.win",
		"rect": Rect2(0, 0, 100, 60),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(root)
	var m_a := _payload_mesh("m_a")
	root.add_child(m_a)
	var child := UI3Element.new({
		"id": "t.map.s1.row",
		"rect": Rect2(0, 0, 40, 16),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	root.add_child(child)
	var m_b := _payload_mesh("m_b")
	child.add_child(m_b)
	await get_tree().process_frame

	# Snapshot the exact pre-map state (the losslessness invariant compares against this).
	var before_a: Material = m_a.material_override
	var before_b: Material = m_b.material_override
	var vis_a := m_a.visible
	var vis_b := m_b.visible

	# The CLIP PAIR the swapped material has to carry through. Written onto the source here,
	# AFTER the engine's mount-time push has run, so the copy is read off two known values
	# rather than off whatever this element's UNCLIPPED answer happened to be.
	#
	# They are ONE answer, not two: `clip_world` is a rect in the SCREEN's space and
	# `ui3_owner_color.gdshader` tests it against `clip_basis_inv * MODEL_MATRIX * VERTEX`,
	# defaulting the basis to IDENTITY. Copying the rect alone compares a display-space box
	# against a GLOBAL vertex, so on every screen whose root is not at the world origin — each
	# camera-child host, each map-hosted formation screen — the map painted a correct colour
	# onto zero surviving fragments, and it read as "the ownership map is broken on this panel".
	var src_a := m_a.material_override as ShaderMaterial
	src_a.shader = _clip_shader()
	var clip_box := Vector4(3.04, -9.44, 10.0, -5.4)
	var clip_basis := Transform3D(Basis.IDENTITY, Vector3(6.87, -6.58, 0.0)).affine_inverse()
	src_a.set_shader_parameter("clip_world", clip_box)
	src_a.set_shader_parameter("clip_basis_inv", clip_basis)

	var map := UI3OwnerColorMap.new()
	map.activate(registry)
	_expect(map.is_active(), "the map must report active after activate()")
	_expect(m_a.material_override != before_a and m_a.material_override is ShaderMaterial,
		"activate must swap an owned mesh's material_override to the debug material")
	var dbg: ShaderMaterial = m_a.material_override
	_expect(dbg.shader == load(UI3OwnerColorMap.DEBUG_SHADER),
		"the swapped material must use the ui3_owner_color debug shader")
	var c_a: Variant = dbg.get_shader_parameter("owner_color")
	var c_b: Variant = (m_b.material_override as ShaderMaterial).get_shader_parameter("owner_color")
	_expect(c_a is Color and (c_a as Color).is_equal_approx(map.owner_color_for("t.map.s1.win")),
		"the mesh's owner color must equal the element's assigned legend color")
	_expect(not (c_a as Color).is_equal_approx(c_b as Color),
		"different owners must wear different colors (sibling-distinct on screen)")
	var swapped_box: Variant = dbg.get_shader_parameter("clip_world")
	_expect(swapped_box is Vector4 and (swapped_box as Vector4).is_equal_approx(clip_box),
		"the debug material must carry the payload's clip_world %s, got %s" % [clip_box, swapped_box])
	var swapped_basis: Variant = dbg.get_shader_parameter("clip_basis_inv")
	_expect(swapped_basis is Transform3D and (swapped_basis as Transform3D).is_equal_approx(clip_basis),
		"the debug material must carry the payload's clip_basis_inv %s, got %s — a copied box with an IDENTITY basis discards every fragment"
		% [clip_basis, swapped_basis])

	map.deactivate()
	_expect(not map.is_active(), "the map must report inactive after deactivate()")
	_expect(m_a.material_override == before_a and m_b.material_override == before_b,
		"deactivate must restore material_override byte-identical (the SAME object)")
	_expect(m_a.visible == vis_a and m_b.visible == vis_b,
		"the color swap must never touch per-mesh visibility (that is Mute's field)")

	# Idempotent + repeatable: a second on→off cycle is equally lossless.
	map.activate(registry)
	map.deactivate()
	_expect(m_a.material_override == before_a and m_b.material_override == before_b,
		"a second map cycle must also restore byte-identical")

	root.free()


# --- Slice 4: unowned payload resolves to the ALARM color --------------------
func _test_unowned_alarm() -> void:
	var registry := get_node_or_null("/root/UI3Registry")
	var ui_root := Node3D.new()
	ui_root.name = "s4_ui_root"
	add_child(ui_root)
	var win := UI3Element.new({
		"id": "t.map.s4.win",
		"rect": Rect2(0, 0, 100, 60),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	ui_root.add_child(win)
	# The owned mesh + the stray both wear a UI-payload shader (the element uses it), so the
	# stray reads as an unclaimed UI widget. The "battle" mesh wears a DIFFERENT shader no
	# element uses (terrain/units) — it shares the sweep subtree but must NOT be alarmed.
	var ui_shader := "res://src/ui3/shaders/formation_solid.gdshader"
	var battle_shader := "res://assets/shaders/solid_ot.gdshader"
	var owned := _shader_mesh("s4_owned", ui_shader)
	win.add_child(owned)
	var stray := _shader_mesh("s4_stray", ui_shader)
	ui_root.add_child(stray)
	var battle := _shader_mesh("s4_battle", battle_shader)
	ui_root.add_child(battle)
	await get_tree().process_frame

	var before_stray: Material = stray.material_override
	var before_battle: Material = battle.material_override
	var map := UI3OwnerColorMap.new()
	map.activate(registry, [ui_root])
	var owned_c: Variant = (owned.material_override as ShaderMaterial).get_shader_parameter("owner_color")
	var stray_c: Variant = (stray.material_override as ShaderMaterial).get_shader_parameter("owner_color")
	_expect(stray_c is Color and (stray_c as Color).is_equal_approx(UI3OwnerColors.ALARM),
		"unclaimed UI payload must be painted the reserved ALARM color, got %s" % [stray_c])
	_expect(owned_c is Color and not (owned_c as Color).is_equal_approx(UI3OwnerColors.ALARM),
		"owned payload must keep its owner color, never the alarm color, got %s" % [owned_c])
	# The battle mesh (a non-UI shader no element uses) must be left ALONE — the audit
	# never false-alarms terrain/unit sprites that merely share the sweep subtree.
	_expect(battle.material_override == before_battle,
		"a non-UI mesh (shader no element uses) must NOT be alarmed, got swapped")
	map.deactivate()
	_expect(stray.material_override == before_stray and battle.material_override == before_battle,
		"the alarm swap must restore every touched mesh byte-identical too")
	ui_root.free()


# --- Slice 5: Mute (pure visibility, captured + restored EXACTLY) -------------
func _test_mute() -> void:
	var a := UI3Element.new({
		"id": "t.map.s5.a", "rect": Rect2(0, 0, 40, 16),
		"transition": UI3Element.Transition.NONE, "frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(a)
	var m_a := _payload_mesh("s5_a")
	a.add_child(m_a)
	var b := UI3Element.new({
		"id": "t.map.s5.b", "rect": Rect2(0, 0, 40, 16),
		"transition": UI3Element.Transition.NONE, "frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(b)
	var m_b := _payload_mesh("s5_b")
	b.add_child(m_b)
	# B's payload starts HIDDEN (a transition-hidden strip) — Mute must restore it to
	# hidden, never force it visible (§4).
	m_b.visible = false
	await get_tree().process_frame

	var registry := get_node_or_null("/root/UI3Registry")
	var map := UI3OwnerColorMap.new()

	# Mute hides the element's own payload; multi-mute stacks.
	map.set_muted(a, true)
	_expect(m_a.visible == false and map.is_muted("t.map.s5.a"),
		"muting an element must hide its own payload")
	map.set_muted(b, true)
	var mids: Array = map.muted_ids()
	_expect(mids.has("t.map.s5.a") and mids.has("t.map.s5.b"),
		"multi-mute must stack, got %s" % [mids])

	# Orthogonal to the swap: activating the map over a muted element swaps its material
	# (not its visibility); deactivating restores the material, leaving it still muted.
	map.activate(registry)
	_expect(m_a.material_override is ShaderMaterial and m_a.visible == false,
		"the swap must not un-hide a muted mesh (visibility and material are disjoint)")
	map.deactivate()
	_expect(m_a.visible == false, "deactivating the map must leave an independently-muted mesh hidden")

	# Unmute restores prior visibility EXACTLY: A back to visible, B back to HIDDEN.
	map.set_muted(a, false)
	_expect(m_a.visible == true and not map.is_muted("t.map.s5.a"),
		"unmuting must restore a normally-visible payload to visible")
	map.set_muted(b, false)
	_expect(m_b.visible == false,
		"unmuting must restore a transition-hidden payload to HIDDEN (never force-true)")

	# clear_all drops map + every mute, restoring the live state exactly.
	map.set_muted(a, true)
	map.activate(registry)
	map.clear_all()
	_expect(not map.is_active() and map.muted_ids().is_empty() and m_a.visible == true,
		"clear_all must drop the map and every mute, restoring visibility")

	a.free()
	b.free()


# --- Slice 6: FLATTENED depth-first assignment (the display order) -----------
func _test_flattened_order() -> void:
	var registry := get_node_or_null("/root/UI3Registry")
	# Two roots, then a child of the FIRST root — so registration order (A, B, childA)
	# differs from the flattened display order (A, childA, B). Assignment must follow the
	# display order, or the legend rainbow would not read top→bottom.
	var a := UI3Element.new({
		"id": "t.map.s6.a", "rect": Rect2(0, 0, 40, 16),
		"transition": UI3Element.Transition.NONE, "frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(a)
	var b := UI3Element.new({
		"id": "t.map.s6.b", "rect": Rect2(0, 0, 40, 16),
		"transition": UI3Element.Transition.NONE, "frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(b)
	var child_a := UI3Element.new({
		"id": "t.map.s6.a.row", "rect": Rect2(0, 0, 30, 12),
		"transition": UI3Element.Transition.RIDE_PARENT, "frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	a.add_child(child_a)
	await get_tree().process_frame

	var map := UI3OwnerColorMap.new()
	var colors: Dictionary = map.assign_colors(registry)
	# Independently derive the display order from the SAME public traversal the page uses
	# (roots + children_of, depth-first pre-order) — the spec of "flattened list order".
	var flat: Array = _flatten(registry)
	var total := flat.size()
	# childA must sit immediately after A (its parent), and BEFORE B — the DFS property.
	var ia: int = flat.find("t.map.s6.a")
	var ic: int = flat.find("t.map.s6.a.row")
	var ib: int = flat.find("t.map.s6.b")
	_expect(ia >= 0 and ic == ia + 1 and ib > ic,
		"child must follow its parent and precede the next root (DFS pre-order): a=%d child=%d b=%d" \
			% [ia, ic, ib])
	# Every element wears the ramp color for its FLATTENED rank — so swatch (owner_color_for)
	# == on-screen swap color == color_for_rank(rank, total). Hue is monotonic down the list.
	var prev_hue := -1.0
	for rank in total:
		var id: String = flat[rank]
		var want: Color = OwnerColors.color_for_rank(rank, total)
		_expect((colors[id] as Color).is_equal_approx(want),
			"element %s (rank %d) must wear color_for_rank(%d, %d)" % [id, rank, rank, total])
		_expect(map.owner_color_for(id).is_equal_approx(want),
			"owner_color_for(%s) (the swatch color) must equal the on-screen ramp color" % id)
		var hue: float = OwnerColors.oklab_hue_deg(want)
		_expect(hue >= prev_hue,
			"the legend must read top→bottom red→violet — rank %d hue %.1f < %.1f" \
				% [rank, hue, prev_hue])
		prev_hue = hue

	a.free()
	b.free()


## The flattened display order the UI3 page renders: roots in order, each followed by its
## subtree depth-first (children_of), pre-order. Mirrors UI3RegistryView._add_element.
func _flatten(registry: Node) -> Array:
	var out: Array = []
	for root: UI3Element in registry.roots():
		_flatten_into(registry, root, out)
	return out


func _flatten_into(registry: Node, e: UI3Element, out: Array) -> void:
	out.append(e.id())
	for child: UI3Element in registry.children_of(e):
		_flatten_into(registry, child, out)


func _payload_mesh(name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = QuadMesh.new()
	mi.material_override = ShaderMaterial.new()
	return mi


## The smallest shader that declares the clip PAIR — slice 3 writes both onto a source material
## and asserts the swap carried both through.
func _clip_shader() -> Shader:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nuniform vec4 clip_world;\nuniform mat4 clip_basis_inv;\nvoid fragment() { ALBEDO = vec3(clip_world.x + clip_basis_inv[3][0]); }"
	return sh


func _shader_mesh(name: String, shader_path: String) -> MeshInstance3D:
	var mi := _payload_mesh(name)
	(mi.material_override as ShaderMaterial).shader = load(shader_path)
	return mi


# --- Slice 7: payload FREED while the map is on -------------------------------
## The lossless-restore invariant (slice 3) has to survive the ordinary case of UI payload
## disappearing between activate() and deactivate() — closing a picker frees its meshes, and the
## captured swap list still points at them.
##
## This was a REAL bug, not a hypothetical: the restore loops read the captured mesh into a
## TYPED local before checking is_instance_valid, so the check was dead code — the typed
## assignment itself raised "Trying to assign invalid previously freed instance" and ABORTED the
## whole loop. Measured: with one freed mesh, 0 of 3 survivors were restored and is_active()
## stayed true, i.e. toggling the map off left the game permanently false-colored with the map
## stuck on. Reported from a real session (UI3OwnerColorMap.deactivate via _on_map_toggled).
func _test_payload_freed_while_the_map_is_on() -> void:
	var reg := get_node("/root/UI3Registry")
	var owners: Array = []
	for i in range(4):
		var e: UI3Element = UI3Element.new({
			"id": "t.gone.e%d" % i,
			"rect": Rect2(10, 10, 20, 20),
			"transition": UI3Element.Transition.NONE,
			"frame": UI3Element.Frame.NONE,
			"clip": UI3Element.Clip.UNCLIPPED,
		})
		add_child(e)
		var mi := _shader_mesh("m%d" % i, "res://src/ui3/shaders/formation_text_opaque.gdshader")
		e.add_child(mi)
		owners.append({"e": e, "mi": mi, "prev": mi.material_override})
	await get_tree().process_frame

	# --- the SWAP half ---
	var map := UI3OwnerColorMap.new()
	map.activate(reg, [self])
	await get_tree().process_frame
	(owners[0]["mi"] as MeshInstance3D).free()      # as closing a picker frees its payload
	await get_tree().process_frame
	map.deactivate()

	var unrestored: Array = []
	for i in range(1, owners.size()):
		var mi = owners[i]["mi"]
		if is_instance_valid(mi) and mi.material_override != owners[i]["prev"]:
			unrestored.append("t.gone.e%d" % i)
	_expect(unrestored.is_empty(),
		("a mesh freed while the map was on must not stop deactivate() restoring the others — "
		+ "these kept their debug material: %s") % [unrestored])
	_expect(not map.is_active(),
		"deactivate() must leave the map inactive even when a captured mesh was freed")

	# --- the MUTE half (the same dead check, in _restore_mute) ---
	var map2 := UI3OwnerColorMap.new()
	map2.assign_colors(reg)
	var survivor: UI3Element = owners[1]["e"]
	var doomed: UI3Element = owners[2]["e"]
	map2.set_muted(survivor, true)
	map2.set_muted(doomed, true)
	_expect(map2.muted_ids().size() == 2, "precondition: two elements muted")
	(owners[2]["mi"] as MeshInstance3D).free()
	await get_tree().process_frame
	map2.clear_all()

	_expect((owners[1]["mi"] as MeshInstance3D).visible,
		"a mesh freed under one mute must not stop another element's payload being un-muted")
	_expect(map2.muted_ids().is_empty(),
		"clear_all() must drop every mute even when a muted mesh was freed, left %s"
			% [map2.muted_ids()])

	for r in owners:
		if is_instance_valid(r["e"]):
			(r["e"] as UI3Element).free()
	await get_tree().process_frame


# --- harness -----------------------------------------------------------------
func _finish() -> void:
	if _failed:
		push_error("[FAIL] UI3OwnershipMapTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3OwnershipMapTest")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[UI3OwnershipMapTest] %s" % msg)
