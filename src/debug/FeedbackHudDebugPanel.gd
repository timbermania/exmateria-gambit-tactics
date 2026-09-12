class_name FeedbackHudDebugPanel
extends BaseDebugPanel
## F3 toggles for the over-unit feedback HUD (ADR-0063, #89/#90).
##
## Two feature gates, both defaulting ON (current behavior). DebugConfig OWNS the values
## (Tune-backed slugs debug.feedback_numbers_enabled / debug.feedback_charge_bubble_enabled);
## this panel is a pure VIEW (ADR-0068 decision 12) — a shared TuneField bool row renders each as
## a checkbox, two-way bound to the slug, so FeedbackHudManager reads them live.
##
## Diagnostic intent: turn both OFF to confirm whether the over-unit billboards are involved in the
## Fire-on-a-charging-caster compositing artifact. If the artifact persists with these off, the
## numbers / charge bubble are NOT the cause and we've misdiagnosed.

const TuneField = preload("res://src/debug/TuneField.gd")


func setup() -> void:
	panel_title = "Feedback HUD"
	panel_category = Category.UNIT
	_build_ui()


func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(250, 0)
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	add_section_title(vbox, "Over-unit feedback (ADR-0063)")
	# Pure VIEW: slug + code default (true), matching the DebugConfig property. TuneField owns the
	# coalescing read, two-way bind, and Pin/Reset menu.
	TuneField.add(vbox, "Damage / heal numbers", "debug.feedback_numbers_enabled", true)
	TuneField.add(vbox, "Charge 'speech' bubble", "debug.feedback_charge_bubble_enabled", true)

	add_separator(vbox)
	var btn_row = add_button_row(vbox)
	var reset_btn = Button.new()
	reset_btn.text = "Reset Defaults"
	reset_btn.pressed.connect(func() -> void:
		Tune.clear("debug.feedback_numbers_enabled")
		Tune.clear("debug.feedback_charge_bubble_enabled"))
	btn_row.add_child(reset_btn)
