extends Node
## Headful capture harness for the dialogue-box triangle-aim investigation.
## Instances ScenarioPlayer, fast-plays to PC 60 (Ovelia "Just a moment,
## Agrias..."), then dumps the projection math the box/triangle use and saves a
## screenshot, so we can compare against the PSX ground truth. Throwaway.

const SCENARIO := preload("res://assets/scenes/ScenarioPlayer.tscn")
# Sweep several boxed Display Messages across screen positions. Godot chunk PC is
# offset ~5 from the decode-doc PC; these were found to open a box.
# align-1 (box above) PCs reliably open a foreground box under the rewind rig;
# align-2 (below) PCs often get superseded by a persisting align-1 box, so the
# bottom-arrow flip is best eyeballed live in-game rather than here.
const TARGET_PCS := [60, 149, 282]

func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a headful capture harness for the dialogue-box triangle-aim investigation — it dumps projection math and a screenshot")
	ScenarioDebugSession.rewind_target_pc = TARGET_PCS[0]
	var player := SCENARIO.instantiate()
	add_child(player)
	_run(player)

func _run(player: Node) -> void:
	var vm: Node = null
	for i in range(1200):
		await get_tree().process_frame
		vm = player.get("_vm")
		if vm != null and not vm.units_by_id.is_empty():
			break
	if vm == null:
		print("[cap] NO VM"); _quit(); return
	vm.box_pool.debug_show_box_anchors = true  # draw P + attach-point gizmos in the shots
	vm.box_pool.debug_show_tile_orb = true     # draw the cyan logical-tile ground orb too

	print("[cap] === speaker feet_screenX vs triangle_screenX (px, 1280-wide vp) ===")
	for pc in TARGET_PCS:
		vm.set_rewind_target(pc)
		for i in range(1800):
			await get_tree().process_frame
			if bool(vm.paused) and not bool(vm._ff_active):
				break
		var box: Node = vm.box_pool.dialogue_box
		var steps := 0
		while (box == null or not box.is_open()) and steps < 6:
			vm.step(1)
			for j in range(40):
				await get_tree().process_frame
				if not bool(vm._ff_active):
					break
			box = vm.box_pool.dialogue_box
			steps += 1
		await get_tree().process_frame
		await get_tree().process_frame
		var open: bool = box != null and box.is_open()
		var speaker: Node3D = vm.box_pool._box_speaker as Node3D
		var cam: Camera3D = vm._active_camera()
		if not open or speaker == null or cam == null:
			print("[cap] pc=%d  no box (open=%s speaker=%s)" % [pc, str(open), str(speaker)])
			continue
		var world: Vector3 = speaker.global_position
		var scr_feet: Vector2 = cam.unproject_position(world)
		var vp: Vector2 = cam.get_viewport().get_visible_rect().size
		var feet256 := scr_feet.x * 256.0 / vp.x if vp.x > 0 else 0.0
		var tri: Node3D = box.get_node_or_null("Triangle")
		var tri_dx := 0.0
		var tri_flip := 1.0
		var align := int(vm.box_pool._box_dialog) & 0x3
		if tri != null:
			tri_dx = cam.unproject_position(tri.global_position).x - scr_feet.x
			tri_flip = tri.scale.x
		var arrow_up: bool = bool(box._arrow_up) if "_arrow_up" in box else (align != 1)
		var uoff: float = float(box._unit_offset_px) if "_unit_offset_px" in box else 0.0
		# Orb = logical tile centre at ground-0. Its projected screen-X vs the
		# origin's (red) screen-X tells us if the camera moves X with Y (non-iso).
		var orb_x := cam.unproject_position(Vector3(world.x, 0.0, world.z)).x
		print("[cap] pc=%3d %-14s align=%d arrow_up=%s unit_off=%.2f flip.x=%.0f originX=%6.1f orbX(y0)=%6.1f  origin.x-orb.x=%6.2f"
			% [pc, str(speaker.name), align, str(arrow_up), uoff, tri_flip, scr_feet.x, orb_x, scr_feet.x - orb_x])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/godot_box_pc%d.png" % pc)
		print("[cap] shot /tmp/godot_box_pc%d.png" % pc)
	_quit()

func _quit() -> void:
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
