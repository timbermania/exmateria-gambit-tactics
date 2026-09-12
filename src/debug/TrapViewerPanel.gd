class_name TrapViewerPanel
extends BaseDebugPanel
## Debug panel for the Trap Viewer scene.
## Provides handler dropdown, element selector, direction slider,
## Play/Stop buttons, loop checkbox, and status label.

const TrapEffect = ExMateriaEffects.TrapEffect

const TuneField = preload("res://src/debug/TuneField.gd")

signal play_requested(handler_id: int, element_id: int, direction_deg: float)
signal stop_requested()
signal loop_toggled(enabled: bool)

var _handler_dropdown: OptionButton
var _element_dropdown: OptionButton
var _direction_slider: HSlider
var _direction_label: Label
var _play_button: Button
var _stop_button: Button
var _loop_checkbox: CheckBox
var _status_label: Label

# Ordered list of handler IDs matching dropdown indices
var _handler_ids: Array[int] = []


func setup() -> void:
	panel_title = "Trap Viewer"
	panel_category = Category.EFFECTS
	_build_ui()
	# Late-select the persisted handler once the runtime list is populated (the element
	# enum already coalesced its value at build). Nothing loads until Play, so restoring is
	# just re-selection — the next Play uses the remembered handler.
	TuneField.resync_dropdown(_handler_dropdown, "trap_viewer.handler", "")


func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	add_child(vbox)

	add_section_title(vbox, "Trap Viewer")
	add_separator(vbox)

	_build_handler_dropdown(vbox)
	_build_element_dropdown(vbox)
	_build_direction_slider(vbox)
	add_separator(vbox)
	_build_controls(vbox)
	add_separator(vbox)
	_build_status(vbox)


func _build_handler_dropdown(vbox: VBoxContainer) -> void:
	# The chosen handler auto-persists (green, ADR-0068) so you resume on it next launch.
	# Dynamic (TrapEffect handler set built at runtime) → string-keyed dropdown affordance,
	# handler id as the stable key; setup() late-selects it after _populate_handlers.
	_handler_dropdown = TuneField.add_dropdown(vbox, "Handler", "trap_viewer.handler", "",
		Tune.Persist.AUTOSAVE)
	_handler_dropdown.custom_minimum_size.x = 250
	_populate_handlers()


func _build_element_dropdown(vbox: VBoxContainer) -> void:
	# Element is a STATIC 0-8 list, so the enum path of the shared TuneField builder fits:
	# the map is label→id and OptionButton.selected == id (insertion order), which is what
	# get_selected_element_id already reads. Auto-persists the picked element.
	var element_names: Array[String] = [
		"0 - None", "1 - Fire", "2 - Lightning", "3 - Ice",
		"4 - Wind", "5 - Earth", "6 - Water", "7 - Holy", "8 - Dark"
	]
	var element_enum := {}
	for i in element_names.size():
		element_enum[element_names[i]] = i
	_element_dropdown = TuneField.add(vbox, "Element", "trap_viewer.element", 0,
		{"enum": element_enum}, Tune.Persist.AUTOSAVE) as OptionButton


func _build_direction_slider(vbox: VBoxContainer) -> void:
	var dir_row = HBoxContainer.new()
	vbox.add_child(dir_row)
	add_label(dir_row, "Direction:", 60)
	_direction_slider = HSlider.new()
	_direction_slider.min_value = 0
	_direction_slider.max_value = 360
	_direction_slider.value = 0
	_direction_slider.step = 15
	_direction_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_direction_slider.custom_minimum_size.x = 150
	_direction_slider.value_changed.connect(_on_direction_changed)
	dir_row.add_child(_direction_slider)
	_direction_label = Label.new()
	_direction_label.text = "0°"
	_direction_label.custom_minimum_size.x = 35
	dir_row.add_child(_direction_label)


func _build_controls(vbox: VBoxContainer) -> void:
	var controls_row = HBoxContainer.new()
	controls_row.add_theme_constant_override("separation", 8)
	vbox.add_child(controls_row)

	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.custom_minimum_size.x = 60
	_play_button.pressed.connect(_on_play_pressed)
	controls_row.add_child(_play_button)

	_stop_button = Button.new()
	_stop_button.text = "Stop"
	_stop_button.custom_minimum_size.x = 60
	_stop_button.pressed.connect(_on_stop_pressed)
	controls_row.add_child(_stop_button)

	# Loop is a momentary playback convenience → EPHEMERAL (grey): a session that loops on
	# next launch would surprise. Built control-only to keep it inline with Play/Stop.
	_loop_checkbox = TuneField.build_control("trap_viewer.loop", false, {},
		Callable(), Tune.Persist.EPHEMERAL) as CheckBox
	_loop_checkbox.text = "Loop"
	_loop_checkbox.add_theme_color_override("font_color", TuneField.EPHEMERAL_ACCENT)
	_loop_checkbox.toggled.connect(_on_loop_toggled)
	controls_row.add_child(_loop_checkbox)


func _build_status(vbox: VBoxContainer) -> void:
	var status_row = HBoxContainer.new()
	vbox.add_child(status_row)
	add_label(status_row, "Status:", 50)
	_status_label = Label.new()
	_status_label.text = "Idle"
	status_row.add_child(_status_label)


func _populate_handlers() -> void:
	_handler_ids.clear()
	_handler_dropdown.clear()
	# Sorted handler IDs — includes standard TrapEffect handlers + special handlers (4, 22)
	var ids: Array = TrapEffect.HANDLER_CONFIGS.keys()
	# Add special handlers not in HANDLER_CONFIGS
	if 4 not in ids:
		ids.append(4)
	if 22 not in ids:
		ids.append(22)
	ids.sort()
	# Extended names for special handlers
	var special_names: Dictionary = {
		4: "Spell Charge Lines",
		22: "Orbital Summon Orbs",
	}
	for hid in ids:
		var name_str: String = special_names.get(hid, TrapEffect.HANDLER_GROUP_NAMES.get(hid, "Unknown"))
		_handler_dropdown.add_item("%d - %s" % [hid, name_str])
		_handler_ids.append(hid)


func get_selected_handler_id() -> int:
	var idx = _handler_dropdown.selected
	if idx >= 0 and idx < _handler_ids.size():
		return _handler_ids[idx]
	return -1


func get_selected_element_id() -> int:
	return _element_dropdown.selected


func get_direction_deg() -> float:
	return _direction_slider.value


func update_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func _on_play_pressed() -> void:
	var hid = get_selected_handler_id()
	if hid >= 0:
		play_requested.emit(hid, get_selected_element_id(), get_direction_deg())


func _on_stop_pressed() -> void:
	stop_requested.emit()


func _on_loop_toggled(enabled: bool) -> void:
	loop_toggled.emit(enabled)


func _on_direction_changed(value: float) -> void:
	_direction_label.text = "%d°" % int(value)
