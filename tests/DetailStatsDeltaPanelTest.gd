extends Node3D
## DEFECT #8 guard (FORMATION_SCREEN.md §15.26 C, RE round 35): the equip-picker compare band is
## TWO overlapping stats panels, not one. `world_equip_compare_panel_builder 0x80111EC4` is registered
## at BOTH slot 0xb (BASE, nudge +2,+2) and slot 0xc (DELTA, nudge 0,0) — so the delta panel sits ~2px
## UP-LEFT of the base ("the slightly-offset second panel" the user saw). Both render, both show dashes
## in the oracle (cursor on the equipped item → zero delta). Round-34 drew ONE panel — the bug.
##
## Seam: DetailScene, which owns the stats band. Normal Status detail = ONE panel; flipping into the
## picker's stats-preview mode brings up the SECOND (delta) panel offset up-left, in dash mode; leaving
## preview drops it back to one.
##
## Run: <GODOT> --path . --quit-after 10 res://tests/DetailStatsDeltaPanelTest.tscn

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	var d = DetailScene.new()
	d.autoplay_open = false           # settle immediately (no box-open transition)
	add_child(d)
	await get_tree().process_frame
	d.set_stats_view({
		"move": 3, "jump": 3, "speed": 8, "r_power": 4, "r_wev": 5, "l_power": 0, "l_wev": 0,
		"r_at": 4, "c_ev": 5, "s_ev": 0, "a_ev": 0, "l_at": 0})
	await get_tree().process_frame

	# Normal Status detail: ONE stats panel.
	_expect(d.stats_panel_count() == 1,
		"normal detail should have 1 stats panel, got %d" % d.stats_panel_count())
	_expect(not d.stats_delta_active(), "delta panel should be absent outside the picker preview")

	# Picker preview: the SECOND (delta) panel appears, ~2px up-left, both in dash mode.
	d.set_stats_preview(true)
	await get_tree().process_frame
	_expect(d.stats_panel_count() == 2,
		"equip-picker preview should show 2 overlapping stats panels (DEFECT #8), got %d" % d.stats_panel_count())
	_expect(d.stats_delta_active(), "delta (compare) panel not built in preview mode")
	# The §15.26 slot offset is 2px PER AXIS; the DIRECTION is the tuneable
	# detail.stats_delta_nudge_* dial (ROM parity note: the ROM's ADDED panel is the
	# (2,2) down-right one — see FORMATION_SCREEN.md §15.26 C2), so the guard locks
	# the magnitude, not the sign.
	var off: Vector2 = d.stats_delta_offset()
	_expect(absf(off.x) == 2.0 and absf(off.y) == 2.0,
		"delta panel should sit 2px diagonal of base, got offset %s" % off)

	# ADR-0088 amendment §5: the compare panel is a REGISTERED ELEMENT (BOX_OPEN /
	# OWN_APERTURE) whose reveal the ORCHESTRATOR plays via the verbs. Standalone
	# preview (this seam) boots it SETTLED-open — self-play demoted; no pop-in beat.
	var comp: UI3Element = d.stats_compare_element()
	_expect(comp != null and is_instance_valid(comp),
		"stats_compare_element() must return the registered compare element in preview")
	if comp != null:
		_expect(comp.transition_mode() == UI3Element.Transition.BOX_OPEN,
			"compare element must declare the BOX_OPEN beat, got %d" % comp.transition_mode())
		_expect(comp.clip_mode() == UI3Element.Clip.OWN_APERTURE,
			"compare element must clip OWN_APERTURE, got %d" % comp.clip_mode())
		_expect(comp.is_settled(), "standalone preview must boot the compare element SETTLED (no self-play)")
		_expect(comp.aperture().size.x > 0 and comp.aperture().size.y > 0,
			"settled compare aperture must be open, got %s" % comp.aperture())
		_expect(not Tune.is_registered("detail.compare.rect"),
			"compare rect is DERIVED from the stats-frame drivers — it must mint no slug")
		# The dup'd panel text must NOT share materials with the base panel: the compare
		# element's own aperture cannot be expressed on a shared material.
		var own: Array = comp.payload_materials()
		_expect(own.size() > 0, "compare element has no discovered payload materials")
		var shared := 0
		for m in d._stats_text_mats:
			if own.has(m):
				shared += 1
		_expect(shared == 0,
			"compare payload shares %d material(s) with the base stats text — base would clip too" % shared)
		# §15.26 occlusion (user bug 2026-08-11, "double sword/rod"): the ROM's compare panel is
		# FULLY OPAQUE — the base panel's Weap.Power sword/rod legend must fold BEHIND the delta
		# chrome (larger world-Z = nearer = drawn on top, ADR-0077), so only the delta's OWN
		# legend pair is visible. The bug: base legend at fold rungs 5/6 sat NEARER than the
		# whole delta panel (z_rung −1 + a 0.01 hair) and drew through it — two swords/rods.
		var chrome_z := _delta_chrome_z(comp)
		_expect(not is_nan(chrome_z), "compare element has no UIFrame chrome to test against")
		if not is_nan(chrome_z):
			for bz in _mesh_zs(d._stats_legend_root):
				_expect(bz < chrome_z,
					"base legend mesh (z=%.3f) must fold BEHIND the delta chrome (z=%.3f)" % [bz, chrome_z])
			var dup_legend := comp.find_child("StatsWeaponLegend", true, false) as Node3D
			_expect(dup_legend != null, "compare element carries no duplicated legend")
			if dup_legend != null:
				for dz in _mesh_zs(dup_legend):
					_expect(dz > chrome_z,
						"delta's own legend mesh (z=%.3f) must sit ON its chrome (z=%.3f)" % [dz, chrome_z])
		# The close VERB walks the reversed beat to fully shut (the engine owns the walk).
		comp.close()
		_expect(not comp.is_settled(), "close() must enter the reversed beat")
		for i in 12:
			UI3Registry.transition_engine_step()
		_expect(comp.aperture().size == Vector2i.ZERO,
			"a finished compare close must end fully shut, got %s" % comp.aperture())
		comp.open()   # restore for the teardown leg below
		for i in 12:
			UI3Registry.transition_engine_step()

	# Leaving preview drops back to a single panel (no orphan delta).
	d.set_stats_preview(false)
	await get_tree().process_frame
	_expect(d.stats_panel_count() == 1,
		"leaving preview should return to 1 stats panel, got %d" % d.stats_panel_count())
	_expect(not d.stats_delta_active(), "delta panel not torn down on leaving preview")

	d.queue_free()
	print("\n=== DetailStatsDeltaPanelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DetailStatsDeltaPanelTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailStatsDeltaPanelTest: two overlapping stats panels in picker preview")
		get_tree().quit(0)


## Global-Z of the compare element's UIFrame chrome (its direct 9-slice child), or NAN if absent.
func _delta_chrome_z(comp: Node) -> float:
	for c in comp.get_children():
		if c is UIFrame:
			return (c as Node3D).global_position.z
	return NAN


## Global-Z of every MeshInstance3D under `root` (the drawn legend quads ride their holders' rung lifts).
func _mesh_zs(root: Node) -> Array:
	var out: Array = []
	if root == null or not is_instance_valid(root):
		return out
	if root is MeshInstance3D:
		out.append((root as Node3D).global_position.z)
	for c in root.get_children():
		out += _mesh_zs(c)
	return out


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
