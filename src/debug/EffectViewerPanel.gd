class_name EffectViewerPanel
extends BaseDebugPanel
## Debug panel for the Effect Viewer scene.
## Provides a dropdown to select effects (E001-E510), Play/Stop buttons,
## loop checkbox, and status label.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase


signal play_requested(effect_id: int)
signal stop_requested()
signal loop_toggled(enabled: bool)
signal react_toggled(enabled: bool)
signal camera_toggled(enabled: bool)
signal emitter_toggled(index: int, enabled: bool)

const TuneField = preload("res://src/debug/TuneField.gd")

var _effect_dropdown: OptionButton
var _play_button: Button
var _stop_button: Button
var _loop_checkbox: CheckBox
var _react_checkbox: CheckBox
var _camera_checkbox: CheckBox
var _status_label: Label
var _emitter_container: VBoxContainer
var _emitter_checkboxes: Array[CheckBox] = []

## Maps dropdown index -> effect_id (int)
var _index_to_effect_id: Array[int] = []

## Tracks which emitter indices are disabled (persists across replays of same effect)
var _disabled_emitters: Dictionary = {}
## The effect_id the disabled set applies to (-1 = none)
var _disabled_for_effect_id: int = -1


func setup() -> void:
	panel_title = "Effect Viewer"
	panel_category = Category.EFFECTS
	_build_ui()
	# Apply-on-boot (ADR-0068): the effect list is populated at runtime, so late-select the
	# persisted effect once it exists (default E065). Nothing auto-plays — restoring makes it
	# the active selection so the next Play resumes the effect you were working on.
	TuneField.resync_dropdown(_effect_dropdown, "effect_viewer.effect", "65")


func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	add_child(vbox)

	add_section_title(vbox, "Effect Viewer")
	add_separator(vbox)

	# Effect dropdown auto-persists (green, ADR-0068) so you come back to the effect you were
	# working on. Dynamic (scanned from assets/effects at runtime) → string-keyed dropdown
	# affordance, effect id as the stable key; setup() late-selects it after _populate_effects.
	_effect_dropdown = TuneField.add_dropdown(vbox, "Effect", "effect_viewer.effect", "65",
		Tune.Persist.AUTOSAVE)
	_effect_dropdown.custom_minimum_size.x = 300

	_populate_effects()

	add_separator(vbox)

	# Play / Stop buttons + Loop checkbox
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
	_loop_checkbox = TuneField.build_control("effect_viewer.loop", false, {},
		Callable(), Tune.Persist.EPHEMERAL) as CheckBox
	_loop_checkbox.text = "Loop"
	_loop_checkbox.add_theme_color_override("font_color", TuneField.EPHEMERAL_ACCENT)
	_loop_checkbox.toggled.connect(_on_loop_toggled)
	controls_row.add_child(_loop_checkbox)

	# Animate / Camera are view preferences → AUTOSAVE (green): they stick across launches.
	# The scene reads get_react_enabled()/get_camera_enabled() right after wiring so the
	# persisted pref drives the first boot too (apply-on-boot).
	_react_checkbox = TuneField.build_control("effect_viewer.animate", true, {},
		Callable(), Tune.Persist.AUTOSAVE) as CheckBox
	_react_checkbox.text = "Animate"
	_react_checkbox.add_theme_color_override("font_color", TuneField.AUTOSAVE_ACCENT)
	_react_checkbox.toggled.connect(func(e): react_toggled.emit(e))
	controls_row.add_child(_react_checkbox)

	_camera_checkbox = TuneField.build_control("effect_viewer.camera", true, {},
		Callable(), Tune.Persist.AUTOSAVE) as CheckBox
	_camera_checkbox.text = "Camera"
	_camera_checkbox.add_theme_color_override("font_color", TuneField.AUTOSAVE_ACCENT)
	_camera_checkbox.toggled.connect(func(e): camera_toggled.emit(e))
	controls_row.add_child(_camera_checkbox)

	add_separator(vbox)

	# Status label
	var status_row = HBoxContainer.new()
	vbox.add_child(status_row)

	add_label(status_row, "Status:", 50)

	_status_label = Label.new()
	_status_label.text = "Idle"
	status_row.add_child(_status_label)

	# Emitter toggles section (collapsible, starts open)
	_emitter_container = create_collapsible_section(vbox, "Emitters", true)


func _populate_effects() -> void:
	_index_to_effect_id.clear()
	_effect_dropdown.clear()

	# Build reverse map: effect_id -> first ability name that uses it
	var effect_to_name: Dictionary = {}
	for ability_id in range(512):
		var ability := AbilityDatabase.get_ability_view(ability_id)
		if ability.is_empty():
			continue
		var eid_val = ability.effect_id
		if eid_val == null:
			continue
		var eid: int = eid_val
		if eid >= 0 and not effect_to_name.has(eid):
			effect_to_name[eid] = ability.name

	# Scan effect directories
	var dir = DirAccess.open("res://assets/effects/")
	if not dir:
		return

	var effect_dirs: Array[String] = []
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and entry.begins_with("E") and entry.length() == 4:
			effect_dirs.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	effect_dirs.sort()

	for effect_dir in effect_dirs:
		var id_num = int(effect_dir.substr(1))
		var label = effect_dir
		if effect_to_name.has(id_num):
			label += " - %s" % effect_to_name[id_num]

		_effect_dropdown.add_item(label)
		# Stash the effect id as the dropdown's stable persistence key (the affordance stores
		# this, not the row index, so a selection survives a reload by id, not position).
		_effect_dropdown.set_item_metadata(_effect_dropdown.item_count - 1, id_num)
		_index_to_effect_id.append(id_num)


func select_effect(effect_id: int) -> void:
	"""Select an effect by ID in the dropdown."""
	var idx = _index_to_effect_id.find(effect_id)
	if idx >= 0:
		_effect_dropdown.selected = idx


func get_selected_effect_id() -> int:
	var idx = _effect_dropdown.selected
	if idx >= 0 and idx < _index_to_effect_id.size():
		return _index_to_effect_id[idx]
	return -1


func is_looping() -> bool:
	return _loop_checkbox.button_pressed


## The persisted Animate/Camera prefs (AUTOSAVE), read by EffectViewerScene right after it
## wires the toggle signals so a remembered choice drives the scene on boot (apply-on-boot).
func get_react_enabled() -> bool:
	return _react_checkbox.button_pressed


func get_camera_enabled() -> bool:
	return _camera_checkbox.button_pressed


func update_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func _on_play_pressed() -> void:
	var eid = get_selected_effect_id()
	if eid >= 0:
		# Clear disabled set when switching to a different effect
		if eid != _disabled_for_effect_id:
			_disabled_emitters.clear()
			_disabled_for_effect_id = eid
		play_requested.emit(eid)


func _on_stop_pressed() -> void:
	stop_requested.emit()


func _on_loop_toggled(enabled: bool) -> void:
	loop_toggled.emit(enabled)


func populate_emitters(effect: Node, effect_id: int) -> void:
	"""Populate emitter checkboxes from an EffectInstance.
	Called when an effect starts playing."""
	clear_emitters()

	if effect_id != _disabled_for_effect_id:
		_disabled_emitters.clear()
		_disabled_for_effect_id = effect_id

	var count: int = effect.get_emitter_count()
	if count == 0:
		return

	for i in range(count):
		var label_text = _build_emitter_label(effect, i)
		# tune-exempt: per-emitter enable/disable is data-driven per-effect — it only makes
		# sense against the current effect's emitter set, and its state is owned by the
		# in-memory _disabled_emitters dict (keyed by emitter index, cleared on effect change).
		var cb = CheckBox.new()  # tune-exempt: per-effect emitter toggle, owned by _disabled_emitters
		cb.text = label_text
		cb.button_pressed = not _disabled_emitters.has(i)
		var idx = i  # capture for closure
		cb.toggled.connect(func(enabled: bool):
			if enabled:
				_disabled_emitters.erase(idx)
			else:
				_disabled_emitters[idx] = true
			emitter_toggled.emit(idx, enabled)
		)
		_emitter_container.add_child(cb)
		_emitter_checkboxes.append(cb)


func clear_emitters() -> void:
	"""Remove all emitter checkboxes (keeps _disabled_emitters intact)."""
	for cb in _emitter_checkboxes:
		if is_instance_valid(cb):
			cb.queue_free()
	_emitter_checkboxes.clear()


func get_disabled_emitters() -> Dictionary:
	"""Return the current disabled emitter indices dictionary."""
	return _disabled_emitters


func _build_emitter_label(effect: Node, index: int) -> String:
	"""Build a compact label for an emitter checkbox."""
	var emitter = effect.manager.effect_data.get_emitter(index) if effect.manager else null
	if not emitter:
		return "[%d]" % index

	var parts: Array[String] = []
	parts.append("[%d] anim:%d" % [index, emitter.anim_index])

	# Compact flag summary
	var f = emitter.flags
	if f.get("color_curve_enabled", false):
		parts.append("col_curve")
	if f.get("rotation_enabled", false):
		parts.append("rot")
	if f.get("align_velocity", false):
		parts.append("align_vel")
	if f.get("face_camera", false):
		parts.append("face_cam")
	# Any non-zero strength homes; negative = repel (don't hide repulsion emitters).
	if emitter.homing_strength_max_start != 0 or emitter.homing_strength_min_start != 0:
		parts.append("homing")
	if emitter.child_emitter_on_death >= 0:
		parts.append("child_d:%d" % emitter.child_emitter_on_death)
	if emitter.child_emitter_mid_life >= 0:
		parts.append("child_m:%d" % emitter.child_emitter_mid_life)

	return " ".join(parts)
