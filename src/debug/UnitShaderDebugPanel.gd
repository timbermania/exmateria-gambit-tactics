class_name UnitShaderDebugPanel
extends BaseDebugPanel
## Debug panel for unit shader depth settings (unified OT model, ADR-0009).
##
## Tunes the UNIT-mode forward nudge (ot_unit_forward, world units) that keeps a
## unit sprite just in front of its own tile, plus the depth-center up/down bias. Both
## rows are shared TuneField controls bound to `render.*` slugs (ADR-0068 move 2): Unit
## OWNS ot_unit_forward (it binds it on the unit material) and SpriteLayerManager
## re-reads render.center_bias at its depth-update use-site, so this panel is just a
## VIEW (decision 12) — a scrub writes the slug and every unit re-drives in any scene,
## no per-panel fan-out over a units accessor. The sprite's vertical depth-sample
## center (depth_center_height) itself is derived per frame from the body pieces.

const TuneField = preload("res://src/debug/TuneField.gd")


## The scene_root / get_units args are no longer needed for the knobs (Unit binds
## the forward slug itself, SpriteLayerManager re-reads the bias slug), but the
## signature stays for call-site compatibility (ScenarioPlayerScene passes them).
func setup(_scene_root: Node, _get_units_func: Callable) -> void:
	panel_title = "Unit Shader"
	panel_category = Category.GENERAL
	_build_ui()


## Owned by DebugOverlay, outlives a scene reload. Nothing to re-push now — the slug
## values are owned by Tune, so the freshly-booted units coalesce them on spawn.
func rebind(_scene_root: Node, _get_units_func: Callable) -> void:
	pass


func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(300, 0)
	add_child(main_vbox)

	add_section_title(main_vbox, "Unit Forward Nudge (ADR-0009)")

	var info_label = Label.new()
	info_label.text = "World units toward camera. Higher = sprite further in front of its own tile. (Vertical center is auto-derived per sprite.)"
	info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	main_vbox.add_child(info_label)

	# Pure VIEW (ADR-0068 decision 12): slug only — Unit owns the default + hint (bound from
	# DepthMode.UNIT_FORWARD), read back from the registry. No default/hint, no owner symbols.
	TuneField.add(main_vbox, "unit_forward:", "render.ot_unit_forward")

	# Depth-center diagnostics: show a marker at the derived center and nudge it
	# up/down live (world units) to find the right value, then bake it into the
	# DEPTH_CENTER_* formula in SpriteLayerManager.
	add_separator(main_vbox)
	add_section_title(main_vbox, "Depth Center (tuning)")

	# TuneField row bound to debug.show_depth_center (ADR-0068): blue, pinnable, synced.
	TuneField.add(main_vbox, "Show center marker", "debug.show_depth_center", false)
	# Pure VIEW (ADR-0068 decision 12): slug only — SpriteLayerManager owns the default + hint,
	# read back from the registry. No default/hint here, no owner symbols.
	TuneField.add(main_vbox, "center_bias (up/down):", "render.center_bias")

	add_separator(main_vbox)
	add_button_row(main_vbox)
	add_print_values_button(main_vbox)


func _on_print_values() -> void:
	print("")
	print("=".repeat(50))
	print("# Unit Shader Values")
	print("=".repeat(50))
	print("ot_unit_forward = %.4f" % Tune.get_value("render.ot_unit_forward"))
	print("center_bias         = %.4f" % Tune.get_value("render.center_bias"))
	print("=".repeat(50))
	print("")
