extends BaseDebugPanel
## F3 panel for the deterministic "cast Fire" reproduction scene (FireCastReproScene).
##
## Two one-shot buttons that ARM a unit's gambit so it performs a specific action on
## its next turn (ADR-0051: interactions live in F3 panels, never env vars):
##   - "Wizard casts Fire" — the Black-Mage caster casts Fire (E016, charge_time 4)
##     on the adjacent Target, which auto-enters cinematic mode (GPU cinematic edge).
##   - "Squire Dash → Wizard" — the Male Squire approaches and Dashes the Wizard (a
##     second, non-cinematic cast to compare the caster×effect interaction against).
##
## Pure VIEW: the host (FireCastReproScene) owns the combat state and the arm/disarm
## logic; this panel only fires host callbacks and renders the status line the host
## pushes back via set_status().

var _host = null
var _status_label: Label = null


func setup(host) -> void:
	_host = host
	panel_title = "Fire-Cast Repro"
	panel_category = Category.SIMULATION
	_build_ui()


func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(280, 0)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	add_section_title(vbox, "Deterministic cast repro")

	var fire_row = add_button_row(vbox)
	var fire_btn = Button.new()
	fire_btn.text = "Wizard casts Fire (auto-cinematic)"
	fire_btn.pressed.connect(func() -> void:
		if _host:
			_host.arm_wizard_fire())
	fire_row.add_child(fire_btn)

	var dash_row = add_button_row(vbox)
	var dash_btn = Button.new()
	dash_btn.text = "Squire Dash → Wizard"
	dash_btn.pressed.connect(func() -> void:
		if _host:
			_host.arm_squire_dash())
	dash_row.add_child(dash_btn)

	add_separator(vbox)

	var disarm_row = add_button_row(vbox)
	var disarm_btn = Button.new()
	disarm_btn.text = "Disarm all (idle)"
	disarm_btn.pressed.connect(func() -> void:
		if _host:
			_host.disarm_all())
	disarm_row.add_child(disarm_btn)

	add_separator(vbox)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(280, 0)
	_status_label.text = "Idle — all units waiting."
	vbox.add_child(_status_label)


func set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text
