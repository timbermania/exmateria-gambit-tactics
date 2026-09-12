extends Node3D

## Guard (ADR-0088 slice 2): the cacheless clip engine.
##   A. Push = fresh pull-walk: a settled OWN_APERTURE element's payload gets clip_world
##      from the LIVE aperture (worked-example literals at ppu 0.04).
##   B. Mount-time coverage: a MeshInstance3D added under a registered element receives
##      the CURRENT aperture via the deferred coalesced node_added push — no
##      notify_payload_changed() hand call.
##   C. An aperture change re-pushes immediately (the box-open drive path).
##   D. UNCLIPPED gets the infinite-aperture sentinel EXPLICITLY (a declared answer,
##      not an omitted array membership); PARENT_APERTURE resolves the nearest
##      OWN_APERTURE ancestor (none in the chain → sentinel).
##   E. The f8442784d stale-clip regression: a rect scrub re-derives the aperture from
##      the LIVE rect — the payload never keeps the OLD aperture.
##   F. The BASIS follows the camera. `clip_world` is a rect in the SCREEN's space and the
##      shaders test it against `clip_basis_inv * MODEL_MATRIX * VERTEX`, so a camera-CHILD
##      host that pans leaves every basis snapshotted against the old transform — and a stale
##      basis discards every clipped fragment rather than mis-clipping a few. The symptom is
##      untestable (no assertion can see an absent fragment); the mechanism is what is here.

## The infinite (unbounded) aperture — the clip shaders' own clip_world default
## (xy = world min, zw = world max, discard outside): everything VISIBLE. The inverted
## (1e20,1e20,-1e20,-1e20) box is the opposite — the shut discard-all aperture.
const SENTINEL := Vector4(-1e20, -1e20, 1e20, 1e20)

var _failed := false


func _ready() -> void:
	await _test_settled_push_and_mount_coverage()
	await _test_aperture_change_and_stale_scrub()
	await _test_unclipped_and_parent_aperture()
	await _test_camera_pan_refreshes_the_basis()

	if _failed:
		push_error("[FAIL] UI3ClipEngineTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3ClipEngineTest")
		get_tree().quit(0)


## A + B: settled element, payload mounted AFTER registration → current aperture lands
## the frame it appears. Worked example: rect (76,135,174,101) at ppu 0.04 →
## clip_world (x0, y_bot, x1, y_top) = (3.04, -9.44, 10.0, -5.4).
func _test_settled_push_and_mount_coverage() -> void:
	var elem := _element("t.clip.own", Rect2(76, 135, 174, 101), UI3Element.Clip.OWN_APERTURE)
	add_child(elem)
	var mat := _mount_quad(elem)
	await get_tree().process_frame
	var got: Variant = mat.get_shader_parameter("clip_world")
	_expect(got is Vector4 and (got as Vector4).is_equal_approx(Vector4(3.04, -9.44, 10.0, -5.4)),
		"mounted payload must receive the settled aperture (3.04, -9.44, 10.0, -5.4), got %s" % got)

	# B again mid-NON-settled: shrink the aperture, then mount NEW payload — it must get
	# the CURRENT (partial) aperture, not the settled rect and not nothing.
	elem._set_aperture(Rect2i(76, 135, 87, 50))
	var late := _mount_quad(elem)
	await get_tree().process_frame
	var got2: Variant = late.get_shader_parameter("clip_world")
	_expect(got2 is Vector4 and (got2 as Vector4).is_equal_approx(Vector4(3.04, -7.4, 6.52, -5.4)),
		"payload mounted mid-aperture must get the current aperture (3.04, -7.4, 6.52, -5.4), got %s" % got2)
	elem.free()


## C + E: an aperture change re-pushes synchronously; a rect scrub re-derives the
## aperture from the LIVE rect (the f8442784d stale-clip bug class).
func _test_aperture_change_and_stale_scrub() -> void:
	var elem := _element("t.clip.scrub", Rect2(76, 135, 174, 101), UI3Element.Clip.OWN_APERTURE)
	add_child(elem)
	var mat := _mount_quad(elem)
	elem.refresh_payload()   # explicit idempotent verb — covers the just-added mesh now

	# C. Drive the aperture directly (the transition-engine path) — synchronous re-push.
	elem._set_aperture(Rect2i(76, 135, 87, 50))
	var got: Variant = mat.get_shader_parameter("clip_world")
	_expect(got is Vector4 and (got as Vector4).is_equal_approx(Vector4(3.04, -7.4, 6.52, -5.4)),
		"aperture change must re-push synchronously, got %s" % got)

	# E. Scrub the rect while settled: the aperture must follow the LIVE rect — the old
	# (76,135)-anchored box re-applied would be the f8442784d regression.
	elem._set_aperture(Rect2i(76, 135, 174, 101))   # settle back to full
	elem._apply_rect(Rect2(100, 150, 174, 101))
	var scrubbed: Variant = mat.get_shader_parameter("clip_world")
	_expect(scrubbed is Vector4 and (scrubbed as Vector4).is_equal_approx(Vector4(4.0, -10.04, 10.96, -6.0)),
		"rect scrub must re-derive the aperture from the LIVE rect (4.0, -10.04, 10.96, -6.0), got %s"
		% scrubbed)
	_expect(elem.aperture() == Rect2i(100, 150, 174, 101),
		"aperture() must report the re-derived live rect, got %s" % elem.aperture())

	# refresh_payload is idempotent — the value holds.
	elem.refresh_payload()
	var again: Variant = mat.get_shader_parameter("clip_world")
	_expect(again is Vector4 and (again as Vector4).is_equal_approx(Vector4(4.0, -10.04, 10.96, -6.0)),
		"refresh_payload must be idempotent, got %s" % again)
	elem.free()


## D: the declared-answer exemption + aperture inheritance.
func _test_unclipped_and_parent_aperture() -> void:
	# UNCLIPPED (the glove cursor): the sentinel is EXPLICITLY pushed.
	var free_elem := _element("t.clip.free", Rect2(0, 0, 16, 16), UI3Element.Clip.UNCLIPPED)
	add_child(free_elem)
	var free_mat := _mount_quad(free_elem)
	await get_tree().process_frame
	var got: Variant = free_mat.get_shader_parameter("clip_world")
	_expect(got is Vector4 and got == SENTINEL,
		"UNCLIPPED payload must get the explicit infinite-aperture sentinel, got %s" % got)
	free_elem.free()

	# PARENT_APERTURE under an OWN_APERTURE ancestor: the child's payload is clipped by
	# the ANCESTOR's aperture — and follows its changes.
	var owner_elem := _element("t.clip.owner", Rect2(76, 135, 174, 101), UI3Element.Clip.OWN_APERTURE)
	add_child(owner_elem)
	var rider := _element("t.clip.owner.rider", Rect2(120, 152, 40, 16), UI3Element.Clip.PARENT_APERTURE)
	owner_elem.add_child(rider)
	var rider_mat := _mount_quad(rider)
	await get_tree().process_frame
	var inherited: Variant = rider_mat.get_shader_parameter("clip_world")
	_expect(inherited is Vector4 and (inherited as Vector4).is_equal_approx(Vector4(3.04, -9.44, 10.0, -5.4)),
		"PARENT_APERTURE payload must get the ancestor's aperture, got %s" % inherited)
	owner_elem._set_aperture(Rect2i(76, 135, 87, 50))
	var followed: Variant = rider_mat.get_shader_parameter("clip_world")
	_expect(followed is Vector4 and (followed as Vector4).is_equal_approx(Vector4(3.04, -7.4, 6.52, -5.4)),
		"an ancestor aperture change must re-push nested PARENT_APERTURE payload, got %s" % followed)
	owner_elem.free()

	# PARENT_APERTURE with NO OWN_APERTURE ancestor: effectively unclipped (sentinel).
	var orphan := _element("t.clip.orphan", Rect2(0, 0, 16, 16), UI3Element.Clip.PARENT_APERTURE)
	add_child(orphan)
	var orphan_mat := _mount_quad(orphan)
	await get_tree().process_frame
	var none: Variant = orphan_mat.get_shader_parameter("clip_world")
	_expect(none is Vector4 and none == SENTINEL,
		"PARENT_APERTURE with no aperture ancestor must get the sentinel, got %s" % none)
	orphan.free()


## F: a UIWindowHost is a CHILD of the camera, so a camera pan moves the whole screen root in
## world space. Nothing about the window's screen-local position changes — which is exactly why
## `UIWindowHost._process` used to skip it — but the clip basis is a snapshot of the root's
## GLOBAL transform, so the pan stales it and every clipped fragment is discarded. Measured on
## the turn-queue strip before the fix: pan the map cursor and the strip vanishes whole.
##
## Both directions, because either half alone is vacuous: the pan must MOVE the live basis (a
## pan that changed nothing would pass a "carried == live" assertion trivially), and the
## carried uniform must have FOLLOWED it.
func _test_camera_pan_refreshes_the_basis() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 12.6
	cam.position = Vector3(0.0, 0.0, 10.0)
	cam.current = true
	add_child(cam)
	var host := UIWindowHost.new()
	cam.add_child(host)
	var root := ScreenRoot.new()
	host.add_child(root)
	host.register_element("t.clip.pan.root", root, Vector2(0.1, 0.1))

	var elem := _element("t.clip.pan", Rect2(0, 0, 40, 20), UI3Element.Clip.OWN_APERTURE)
	root.add_child(elem)
	var mat := _mount_quad(elem)
	# Two frames, not one: the host places the root on its first `_process` and the engine's
	# mount-time push is coalesced to the frame after the mesh appeared.
	await get_tree().process_frame
	await get_tree().process_frame

	var live_before := UI3ClipEngine.clip_basis_inv_for(elem)
	var carried_before: Variant = mat.get_shader_parameter("clip_basis_inv")
	_expect(carried_before is Transform3D and (carried_before as Transform3D).is_equal_approx(live_before),
		"a settled camera-child host's payload must already carry the live basis, got %s vs %s"
		% [carried_before, live_before])

	# THE PAN. Translation only: no zoom, no viewport resize, no re-registration — the one
	# camera gesture that used to reach no code path at all.
	cam.position += Vector3(3.0, 1.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame

	var live_after := UI3ClipEngine.clip_basis_inv_for(elem)
	_expect(not live_after.is_equal_approx(live_before),
		"the pan did not move the screen root's basis at all — this arm asserts nothing (%s)"
		% live_after)
	var carried_after: Variant = mat.get_shader_parameter("clip_basis_inv")
	_expect(carried_after is Transform3D and (carried_after as Transform3D).is_equal_approx(live_after),
		"after a camera PAN the payload must carry the LIVE basis %s, not the pre-pan snapshot %s"
		% [live_after, carried_after])
	cam.free()


## The idiom [method UI3ClipEngine.clip_basis_inv_for] walks for: the nearest ancestor that
## DEFINES display space answers `screen_to_world`. DetailScene, FormationScene and
## TurnQueueHud.StripRoot all carry it; this is the smallest thing that does.
class ScreenRoot extends Node3D:
	func screen_to_world(px: float, py: float) -> Vector3:
		return Vector3(px * UI3Element.DEFAULT_PPU, -py * UI3Element.DEFAULT_PPU, 0.0)


func _element(id: String, rect: Rect2, clip: int) -> UI3Element:
	return UI3Element.new({
		"id": id,
		"rect": rect,
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": clip,
	})


## Mount one quad with a ShaderMaterial under `parent` and return the material — the
## payload shape the engine discovers (MeshInstance3D + material_override).
func _mount_quad(parent: Node3D) -> ShaderMaterial:
	var sh := Shader.new()
	# BOTH clip uniforms, because they are one answer: the box is in the screen's space and the
	# basis is what puts a global vertex into it (section F).
	sh.code = "shader_type spatial;\nuniform vec4 clip_world;\nuniform mat4 clip_basis_inv;\nvoid fragment() { ALBEDO = vec3(clip_world.x + clip_basis_inv[3][0]); }"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	mi.material_override = mat
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.add_child(mi)
	return mat


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[UI3ClipEngineTest] %s" % msg)
