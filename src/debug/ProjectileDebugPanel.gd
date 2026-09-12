class_name ProjectileDebugPanel
extends BaseDebugPanel
## Debug panel for tuning projectile spin.
##
## ADR-0038: flight time is SEQ-derived, so per-family flight-speed tuning lives on the
## shader constants — not here. The only knob left is `spin_deg_per_tick`, the placeholder
## for thrown-weapon spin until the PSX-authentic rate is RE'd from BATTLE.BIN. It is a
## shared TuneField row bound to the `projectile.spin_deg_per_tick` slug (ADR-0068 move 2):
## Projectile3D OWNS it (reads Tune.of at its per-frame use-site), so this panel is just a
## VIEW (decision 12) — a scrub/pin drives every projectile live in any scene.

const TuneField = preload("res://src/debug/TuneField.gd")


func setup() -> void:
	panel_title = "Projectile"
	panel_category = Category.PROJECTILE
	_build_ui()


func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(250, 0)
	add_child(main_vbox)

	add_section_title(main_vbox, "Spin (deg/tick — thrown weapon / item)")
	# Pure VIEW (ADR-0068 decision 12): slug only — Projectile3D owns the default + hint,
	# read back from the registry. No default/hint here, no owner symbols.
	TuneField.add(main_vbox, "Spin", "projectile.spin_deg_per_tick")

	add_separator(main_vbox)
	var btn_row = add_button_row(main_vbox)
	var reset_btn = Button.new()
	reset_btn.text = "Reset Defaults"
	reset_btn.pressed.connect(func() -> void: Tune.clear("projectile.spin_deg_per_tick"))
	btn_row.add_child(reset_btn)
