extends Node

## Headful integration probe (§11.5/§16.1): instantiate the real FormationScene, snap the
## logical cursor with set_selected_cell, then pump _process for a second and confirm the
## VISIBLE box glides (does NOT snap), leaves a multi-position trail, and settles on target.

const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")


func _ready() -> void:
	var scene = FormationScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var start_glide: Vector2 = scene._box_glide
	var target_cell := Vector2i(3, 1)   # far corner — long glide, full trail
	scene.set_selected_cell(target_cell)
	var want_target: Vector2 = scene.cell_box_centre(target_cell)

	# The logical cursor snapped immediately; the glide must NOT have jumped yet.
	if scene._box_glide != start_glide:
		print("[FAIL] box glide snapped on selection (should ease): %s" % scene._box_glide)

	# Pump one 60 Hz-ish step and sample the glide + how many trail slots are distinct.
	var saw_mid := false
	var max_distinct := 1
	for i in range(40):
		scene._advance_glide(1.0 / 60.0)
		var g: Vector2 = scene._box_glide
		if g != start_glide and g != want_target:
			saw_mid = true
		var distinct := {}
		for h in scene._box_history:
			distinct[h] = true
		max_distinct = max(max_distinct, distinct.size())

	var settled: Vector2 = scene._box_glide
	print("[probe] start=%s target=%s settled=%s saw_mid=%s max_trail=%d"
		% [start_glide, want_target, settled, saw_mid, max_distinct])

	var ok := true
	if not saw_mid:
		print("[FAIL] never observed a mid-glide position — box teleported"); ok = false
	if max_distinct < 4:
		print("[FAIL] trail never spread (max distinct history = %d, want >=4)" % max_distinct); ok = false
	# Settles EXACTLY on target (the glide snaps on convergence so the box lands centered
	# on the cell regardless of approach direction — not the raw ~3px floor()-stall).
	if settled != want_target:
		print("[FAIL] glide did not settle exactly on target: %s vs %s" % [settled, want_target]); ok = false
	# After settle the trail must collapse: only slot7 visible.
	var visible_slots := 0
	for s in range(FormationScene.TRAIL_LEN):
		if scene._trail_slot_visible(s):
			visible_slots += 1
	if visible_slots != 1:
		print("[FAIL] trail did not collapse at settle: %d slots visible" % visible_slots); ok = false

	if ok:
		print("[PASS] probe_formation_glide: box eases, trail spreads then collapses, settles on target")
	get_tree().quit()
