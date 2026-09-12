class_name CombatUIDebugPanel
extends BaseDebugPanel
## Debug panel for UI3 Combat UI.
##
## Provides controls for:
## - Click area debug visibility
## - Roster bar properties
## - Menu visibility toggles
## - Popup testing

var _ui: UICombatManager
var _host: Node  # the CombatUITestScene, for the dialogue-box capture button


func setup(ui_manager, host: Node = null) -> void:
	panel_title = "UI3 Combat Debug"
	panel_category = Category.DESIGNER
	_ui = ui_manager as UICombatManager
	_host = host
	_build_ui()


func _build_ui() -> void:
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 400)
	add_child(scroll)

	var vbox = VBoxContainer.new()
	scroll.add_child(vbox)

	# Click Area Debug Section
	var click_section = create_collapsible_section(vbox, "Click Areas", true)
	_build_click_area_section(click_section)

	add_separator(vbox)

	# Roster Section
	var roster_section = create_collapsible_section(vbox, "Roster Bars", true)
	_build_roster_section(roster_section)

	add_separator(vbox)

	# Menu Section
	var menu_section = create_collapsible_section(vbox, "Menus", true)
	_build_menu_section(menu_section)

	add_separator(vbox)

	# Popup Section
	var popup_section = create_collapsible_section(vbox, "Popups", true)
	_build_popup_section(popup_section)

	add_separator(vbox)

	# Dialogue-box geometry capture (ADR-0051: a button the panel invokes,
	# replacing the former DLG_SHOT env var on the test scene).
	if _host and _host.has_method("capture_dialogue_box_to"):
		var cap_btn := Button.new()
		cap_btn.text = "Capture dialogue box → /tmp/dlg_box.png"
		cap_btn.pressed.connect(func(): _host.capture_dialogue_box_to())
		vbox.add_child(cap_btn)
		add_separator(vbox)

	# Print Values button
	add_print_values_button(vbox)


func _build_click_area_section(parent: Control) -> void:
	# Show click areas checkbox
	# tune-exempt: data-driven mirror of _ui.is_click_area_debug_visible() (owned by
	# UICombatManager, re-synced in on_shown). This panel is not registered in any scene.
	var click_cb = CheckBox.new()  # tune-exempt: mirror of UICombatManager click-area debug state
	click_cb.text = "Show Click Areas"
	click_cb.button_pressed = _ui.is_click_area_debug_visible() if _ui else false
	click_cb.toggled.connect(_on_show_click_areas_toggled)
	parent.add_child(click_cb)
	_controls["show_click_areas"] = click_cb


func _build_roster_section(parent: Control) -> void:
	# Friendly roster controls
	var friendly_label = Label.new()
	friendly_label.text = "Friendly Roster"
	parent.add_child(friendly_label)

	var friendly_row = HBoxContainer.new()
	parent.add_child(friendly_row)

	add_label(friendly_row, "Frames:", 60)

	# tune-exempt: data-driven — mirrors _ui.friendly_roster.frame_count, set by UICombatManager.
	var friendly_frames = SpinBox.new()  # tune-exempt: mirror of UICombatManager friendly_roster.frame_count
	friendly_frames.min_value = 0
	friendly_frames.max_value = 8
	friendly_frames.step = 1
	if _ui and _ui.friendly_roster:
		friendly_frames.value = _ui.friendly_roster.frame_count
	friendly_frames.value_changed.connect(_on_friendly_frame_count_changed)
	friendly_row.add_child(friendly_frames)
	_controls["friendly_frames"] = friendly_frames

	# Enemy roster controls
	var enemy_label = Label.new()
	enemy_label.text = "Enemy Roster"
	parent.add_child(enemy_label)

	var enemy_row = HBoxContainer.new()
	parent.add_child(enemy_row)

	add_label(enemy_row, "Frames:", 60)

	# tune-exempt: data-driven — mirrors _ui.enemy_roster.frame_count, set by UICombatManager.
	var enemy_frames = SpinBox.new()  # tune-exempt: mirror of UICombatManager enemy_roster.frame_count
	enemy_frames.min_value = 0
	enemy_frames.max_value = 8
	enemy_frames.step = 1
	if _ui and _ui.enemy_roster:
		enemy_frames.value = _ui.enemy_roster.frame_count
	enemy_frames.value_changed.connect(_on_enemy_frame_count_changed)
	enemy_row.add_child(enemy_frames)
	_controls["enemy_frames"] = enemy_frames

	# Show frame checkbox
	# tune-exempt: debug-viz mirror of roster.show_frame (owned by UICombatManager rosters).
	var show_frame_cb = CheckBox.new()  # tune-exempt: mirror of UICombatManager roster.show_frame
	show_frame_cb.text = "Show Roster Frames"
	show_frame_cb.button_pressed = true
	show_frame_cb.toggled.connect(_on_show_roster_frames_toggled)
	parent.add_child(show_frame_cb)
	_controls["show_roster_frames"] = show_frame_cb


func _build_menu_section(parent: Control) -> void:
	# Equipment menu
	# tune-exempt: mirrors live _ui._equipment_menu.visible (gameplay-driven), re-synced in on_shown.
	var equipment_cb = CheckBox.new()  # tune-exempt: mirror of live _ui._equipment_menu.visible
	equipment_cb.text = "Equipment Menu"
	equipment_cb.button_pressed = _ui._equipment_menu.visible if _ui and _ui._equipment_menu else false
	equipment_cb.toggled.connect(_on_equipment_menu_toggled)
	parent.add_child(equipment_cb)
	_controls["equipment_visible"] = equipment_cb

	# Ability menu
	# tune-exempt: mirrors live _ui._ability_menu.visible (gameplay-driven), re-synced in on_shown.
	var ability_cb = CheckBox.new()  # tune-exempt: mirror of live _ui._ability_menu.visible
	ability_cb.text = "Ability Menu"
	ability_cb.button_pressed = _ui._ability_menu.visible if _ui and _ui._ability_menu else false
	ability_cb.toggled.connect(_on_ability_menu_toggled)
	parent.add_child(ability_cb)
	_controls["ability_visible"] = ability_cb

	# Stats menu
	# tune-exempt: mirrors live _ui._stats_menu.visible (gameplay-driven), re-synced in on_shown.
	var stats_cb = CheckBox.new()  # tune-exempt: mirror of live _ui._stats_menu.visible
	stats_cb.text = "Stats Menu"
	stats_cb.button_pressed = _ui._stats_menu.visible if _ui and _ui._stats_menu else false
	stats_cb.toggled.connect(_on_stats_menu_toggled)
	parent.add_child(stats_cb)
	_controls["stats_visible"] = stats_cb

	# Gambit display
	# tune-exempt: mirrors live _ui._gambit_display.visible (gameplay-driven), re-synced in on_shown.
	var gambit_cb = CheckBox.new()  # tune-exempt: mirror of live _ui._gambit_display.visible
	gambit_cb.text = "Gambit Display"
	gambit_cb.button_pressed = _ui._gambit_display.visible if _ui and _ui._gambit_display else false
	gambit_cb.toggled.connect(_on_gambit_display_toggled)
	parent.add_child(gambit_cb)
	_controls["gambit_visible"] = gambit_cb


func _build_popup_section(parent: Control) -> void:
	# Test popup buttons
	var btn_row = HBoxContainer.new()
	parent.add_child(btn_row)

	var equip_btn = Button.new()
	equip_btn.text = "Equipment"
	equip_btn.pressed.connect(_on_test_equipment_popup)
	btn_row.add_child(equip_btn)

	var ability_btn = Button.new()
	ability_btn.text = "Ability"
	ability_btn.pressed.connect(_on_test_ability_popup)
	btn_row.add_child(ability_btn)

	var btn_row2 = HBoxContainer.new()
	parent.add_child(btn_row2)

	var learn_btn = Button.new()
	learn_btn.text = "Learn"
	learn_btn.pressed.connect(_on_test_learn_panel)
	btn_row2.add_child(learn_btn)

	var gambit_btn = Button.new()
	gambit_btn.text = "Gambit"
	gambit_btn.pressed.connect(_on_test_gambit_editor)
	btn_row2.add_child(gambit_btn)

	var close_btn = Button.new()
	close_btn.text = "Close All"
	close_btn.pressed.connect(_on_close_all_popups)
	parent.add_child(close_btn)


#region Event Handlers

func _on_show_click_areas_toggled(pressed: bool) -> void:
	if _ui:
		_ui.set_click_area_debug_visible(pressed)


func _on_friendly_frame_count_changed(value: float) -> void:
	if _ui and _ui.friendly_roster:
		_ui.friendly_roster.frame_count = int(value)


func _on_enemy_frame_count_changed(value: float) -> void:
	if _ui and _ui.enemy_roster:
		_ui.enemy_roster.frame_count = int(value)


func _on_show_roster_frames_toggled(pressed: bool) -> void:
	if _ui:
		if _ui.friendly_roster:
			_ui.friendly_roster.show_frame = pressed
		if _ui.enemy_roster:
			_ui.enemy_roster.show_frame = pressed


func _on_equipment_menu_toggled(pressed: bool) -> void:
	if _ui and _ui._equipment_menu:
		_ui._equipment_menu.visible = pressed


func _on_ability_menu_toggled(pressed: bool) -> void:
	if _ui and _ui._ability_menu:
		_ui._ability_menu.visible = pressed


func _on_stats_menu_toggled(pressed: bool) -> void:
	if _ui and _ui._stats_menu:
		_ui._stats_menu.visible = pressed


func _on_gambit_display_toggled(pressed: bool) -> void:
	if _ui and _ui._gambit_display:
		_ui._gambit_display.visible = pressed


func _on_test_equipment_popup() -> void:
	if _ui:
		_ensure_unit_selected()
		_ui._show_equipment_popup(0)


func _on_test_ability_popup() -> void:
	if _ui:
		_ensure_unit_selected()
		_ui._show_ability_popup(0)


func _on_test_learn_panel() -> void:
	if _ui:
		_ensure_unit_selected()
		_ui._show_learn_panel()


func _on_test_gambit_editor() -> void:
	if _ui:
		_ensure_unit_selected()
		_ui._show_gambit_editor(0)


func _ensure_unit_selected() -> void:
	# Auto-select first friendly unit if none selected
	if not _ui.get_selected_unit():
		if _ui._friendly_units.size() > 0:
			_ui.select_unit(_ui._friendly_units[0])


func _on_close_all_popups() -> void:
	if _ui:
		_ui._dismiss_open_ui()

#endregion


func _on_print_values() -> void:
	print("")
	print("=" .repeat(50))
	print("# UI3 Combat Debug Panel Values")
	print("=" .repeat(50))

	if _ui:
		print("Click Areas Debug: %s" % _ui.is_click_area_debug_visible())

		if _ui.friendly_roster:
			print("Friendly Roster Frames: %d" % _ui.friendly_roster.frame_count)
			print("Friendly Roster Show Frame: %s" % _ui.friendly_roster.show_frame)

		if _ui.enemy_roster:
			print("Enemy Roster Frames: %d" % _ui.enemy_roster.frame_count)
			print("Enemy Roster Show Frame: %s" % _ui.enemy_roster.show_frame)

		if _ui._equipment_menu:
			print("Equipment Menu Visible: %s" % _ui._equipment_menu.visible)

		if _ui._ability_menu:
			print("Ability Menu Visible: %s" % _ui._ability_menu.visible)

		if _ui._stats_menu:
			print("Stats Menu Visible: %s" % _ui._stats_menu.visible)

		if _ui._gambit_display:
			print("Gambit Display Visible: %s" % _ui._gambit_display.visible)

	print("=" .repeat(50))
	print("")


func on_shown() -> void:
	# Sync checkbox states when panel is shown
	if _ui:
		set_checkbox_value("show_click_areas", _ui.is_click_area_debug_visible())

		if _ui.friendly_roster:
			set_spinbox_value("friendly_frames", _ui.friendly_roster.frame_count)
			set_checkbox_value("show_roster_frames", _ui.friendly_roster.show_frame)

		if _ui.enemy_roster:
			set_spinbox_value("enemy_frames", _ui.enemy_roster.frame_count)

		set_checkbox_value("equipment_visible", _ui._equipment_menu.visible if _ui._equipment_menu else false)
		set_checkbox_value("ability_visible", _ui._ability_menu.visible if _ui._ability_menu else false)
		set_checkbox_value("stats_visible", _ui._stats_menu.visible if _ui._stats_menu else false)
		set_checkbox_value("gambit_visible", _ui._gambit_display.visible if _ui._gambit_display else false)
