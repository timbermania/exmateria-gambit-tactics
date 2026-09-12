class_name ScenarioDialogueBoxDebugPanel
extends BaseDebugPanel

## Live-tuning panel for boxed dialogue placement + size.
##
## The box is placed on its speaker by `ScenarioVM._place_box_on_unit`, which re-runs
## EVERY FRAME while a box is open — so every knob here takes effect immediately on an
## already-open box (no reopen needed).
##
## Every knob is a shared TuneField bound to a `dialbox.*` slug (ADR-0068 move 2):
## ScenarioDialogueBoxPool OWNS these values (ScenarioVM calls box_pool.bind_tunables
## at boot), so this panel is just a VIEW (decision 12). A scrub writes the slug, the
## pool re-applies it, and the tuning survives a scenario reload for free. box_offset_px
## is a Vector2 (no TuneField control yet), so it is split into two float-slug rows.

const TuneField = preload("res://src/debug/TuneField.gd")


## `vm` is unused now that the box pool owns every value (ScenarioVM binds the slugs);
## the param stays for call-site compatibility (ScenarioPlayerScene passes it).
func setup(_vm) -> void:
	panel_title = "Scenario Dialogue Box"
	panel_category = Category.SCENARIO_LOOK
	_build_ui()


## Owned by DebugOverlay, outlives a scene reload. The knob values are owned by Tune
## now, so the freshly-booted box pool coalesces them on its own bind — nothing to push.
func rebind(_vm) -> void:
	pass


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(290, 0)
	add_child(vbox)

	# Pure VIEW (ADR-0068 decision 12): slug only — ScenarioDialogueBoxPool owns every default +
	# hint, read back from the registry. No defaults/hints, no owner symbols.
	add_section_title(vbox, "Anchor to billboarded sprite")
	TuneField.add(vbox, "Track billboard", "dialbox.anchor_to_billboard")
	TuneField.add(vbox, "Quad Y (0=origin, −=down)", "dialbox.anchor_quad_frac_y")

	add_separator(vbox)
	add_section_title(vbox, "Box size scale (1.0 = default)")
	TuneField.add(vbox, "Size scale", "dialbox.box_size_scale")

	add_separator(vbox)
	add_section_title(vbox, "Vertical gap: feet P → box near edge (native px)")
	TuneField.add(vbox, "Above (align 1)", "dialbox.box_gap_above_px")
	TuneField.add(vbox, "Below (align 2)", "dialbox.box_gap_below_px")

	add_separator(vbox)
	add_section_title(vbox, "Anchor fine-nudge (native 256x240 px)")
	TuneField.add(vbox, "X (right+)", "dialbox.box_offset_x")
	TuneField.add(vbox, "Y (down+)", "dialbox.box_offset_y")

	add_separator(vbox)
	add_section_title(vbox, "Speaker triangle (tail pointer) aim")
	TuneField.add(vbox, "Bias (px)", "dialbox.tri_aim_bias_px")
	TuneField.add(vbox, "Scale (gain)", "dialbox.tri_aim_scale")

	add_separator(vbox)
	TuneField.add(vbox, "Show anchor points (red/green/yellow)", "dialbox.debug_show_box_anchors")
	TuneField.add(vbox, "Show logical-position orb (cyan)", "dialbox.debug_show_tile_orb")

	add_separator(vbox)
	add_print_values_button(vbox)


func _on_print_values() -> void:
	print("[ScenarioDialogueBox] current knob values:")
	print("  box_size_scale       = %.3f" % Tune.get_value("dialbox.box_size_scale"))
	print("  box_gap_above_px      = %.1f" % Tune.get_value("dialbox.box_gap_above_px"))
	print("  box_gap_below_px      = %.1f" % Tune.get_value("dialbox.box_gap_below_px"))
	print("  box_offset_px         = (%.1f, %.1f)" % [Tune.get_value("dialbox.box_offset_x"),
		Tune.get_value("dialbox.box_offset_y")])
	print("  tri_aim_bias_px       = %.1f" % Tune.get_value("dialbox.tri_aim_bias_px"))
	print("  tri_aim_scale         = %.3f" % Tune.get_value("dialbox.tri_aim_scale"))
	print("  anchor_to_billboard   = %s" % str(Tune.get_value("dialbox.anchor_to_billboard")))
	print("  anchor_quad_frac_y    = %.3f" % Tune.get_value("dialbox.anchor_quad_frac_y"))
