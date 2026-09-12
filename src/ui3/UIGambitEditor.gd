@tool
class_name UIGambitEditor3
extends UIModalWindow
## Gambit editor with full feature parity for editing gambit rules.
##
## Contains two menu sections:
## - Top menu: Action sentence builder (Do, Prefer, Team, To, When)
## - Bottom menu: Condition slots (4 rows)
##
## Auto-saves on every change. Uses ESC to close.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector
const UnitRole = ExMateriaSchema.UnitRole



## Emitted when gambit is saved
signal gambit_saved(gambit_index: int, gambit: Gambit)

## Emitted when any dropdown changes (for live preview)
signal gambit_changed(gambit: Gambit)

#region Configuration Exports


## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		if pixels_per_unit == value:
			return
		pixels_per_unit = value
		_mark_layout_dirty()

## Spacing between top and bottom menus
@export var menu_spacing: float = 2.0:
	set(value):
		if menu_spacing == value:
			return
		menu_spacing = value
		_mark_layout_dirty()

#endregion

#region Top Menu Configuration

@export_group("Top Menu")

@export var top_menu_size: Vector2 = Vector2(160, 100):
	set(value):
		if top_menu_size == value:
			return
		top_menu_size = value
		_mark_layout_dirty()

@export var top_menu_show_frame: bool = true:
	set(value):
		if top_menu_show_frame == value:
			return
		top_menu_show_frame = value
		_mark_layout_dirty()

@export var header_text: String = "Edit Gambit":
	set(value):
		if header_text == value:
			return
		header_text = value
		_mark_layout_dirty()

@export var header_offset: Vector2 = Vector2(4, -4):
	set(value):
		if header_offset == value:
			return
		header_offset = value
		_mark_layout_dirty()

@export var header_scale: float = 0.7:
	set(value):
		if header_scale == value:
			return
		header_scale = value
		_mark_layout_dirty()

@export var header_palette: int = 1:
	set(value):
		if header_palette == value:
			return
		header_palette = value
		_mark_layout_dirty()

@export var header_space_width: float = 1.0:
	set(value):
		if header_space_width == value:
			return
		header_space_width = value
		_mark_layout_dirty()

#endregion

#region Labels Configuration

@export_group("Labels")

## Text per top-menu label
@export var label_texts: Array[String] = ["Do", "Prefer", "To", "When", "Trigger"]:
	set(value):
		if label_texts == value:
			return
		label_texts = value
		_mark_layout_dirty()

## Shared text config for top-menu labels
@export var label_scale: float = 0.61:
	set(value):
		if label_scale == value:
			return
		label_scale = value
		_mark_layout_dirty()

@export var label_palette: int = 1:
	set(value):
		if label_palette == value:
			return
		label_palette = value
		_mark_layout_dirty()

@export var label_space_width: float = 1.0:
	set(value):
		if label_space_width == value:
			return
		label_space_width = value
		_mark_layout_dirty()

## Per-label offsets
@export var do_label_offset: Vector2 = Vector2(-2, 9):
	set(value):
		if do_label_offset == value:
			return
		do_label_offset = value
		_mark_layout_dirty()

@export var prefer_label_offset: Vector2 = Vector2(-16, 26):
	set(value):
		if prefer_label_offset == value:
			return
		prefer_label_offset = value
		_mark_layout_dirty()

@export var to_label_offset: Vector2 = Vector2(-3, 42):
	set(value):
		if to_label_offset == value:
			return
		to_label_offset = value
		_mark_layout_dirty()

@export var when_label_offset: Vector2 = Vector2(-12, 58):
	set(value):
		if when_label_offset == value:
			return
		when_label_offset = value
		_mark_layout_dirty()

@export var trigger_label_offset: Vector2 = Vector2(-23, 74):
	set(value):
		if trigger_label_offset == value:
			return
		trigger_label_offset = value
		_mark_layout_dirty()

#endregion

#region Bottom Menu Configuration

@export_group("Bottom Menu")

@export var bottom_menu_size: Vector2 = Vector2(195, 90):
	set(value):
		if bottom_menu_size == value:
			return
		bottom_menu_size = value
		_mark_layout_dirty()

@export var bottom_menu_show_frame: bool = true:
	set(value):
		if bottom_menu_show_frame == value:
			return
		bottom_menu_show_frame = value
		_mark_layout_dirty()

#endregion

#region Condition Labels Configuration

@export_group("Condition Labels")

## Text per condition row
@export var condition_label_texts: Array[String] = ["If", "and", "and", "and"]:
	set(value):
		if condition_label_texts == value:
			return
		condition_label_texts = value
		_mark_layout_dirty()

## Per-label offsets (absolute within bottom menu)
@export var condition_label_0_offset: Vector2 = Vector2(-4, 12):
	set(value):
		if condition_label_0_offset == value:
			return
		condition_label_0_offset = value
		_mark_layout_dirty()

@export var condition_label_1_offset: Vector2 = Vector2(-4, 32):
	set(value):
		if condition_label_1_offset == value:
			return
		condition_label_1_offset = value
		_mark_layout_dirty()

@export var condition_label_2_offset: Vector2 = Vector2(-4, 52):
	set(value):
		if condition_label_2_offset == value:
			return
		condition_label_2_offset = value
		_mark_layout_dirty()

@export var condition_label_3_offset: Vector2 = Vector2(-4, 72):
	set(value):
		if condition_label_3_offset == value:
			return
		condition_label_3_offset = value
		_mark_layout_dirty()

@export var condition_label_scale: float = 0.61:
	set(value):
		if condition_label_scale == value:
			return
		condition_label_scale = value
		_mark_layout_dirty()

@export var condition_label_palette: int = 1:
	set(value):
		if condition_label_palette == value:
			return
		condition_label_palette = value
		_mark_layout_dirty()

@export var condition_label_space_width: float = 1.0:
	set(value):
		if condition_label_space_width == value:
			return
		condition_label_space_width = value
		_mark_layout_dirty()

#endregion

#region Dropdown Configuration

@export_group("Dropdowns")

@export var dropdown_scale: float = 0.61:
	set(value):
		if dropdown_scale == value:
			return
		dropdown_scale = value
		_mark_layout_dirty()

@export var dropdown_palette: int = 0:
	set(value):
		if dropdown_palette == value:
			return
		dropdown_palette = value
		_mark_layout_dirty()

## Do dropdown (action selection)
@export var do_offset: Vector2 = Vector2(15, 7):
	set(value):
		if do_offset == value:
			return
		do_offset = value
		_mark_layout_dirty()

@export var do_width: float = 135.0:
	set(value):
		if do_width == value:
			return
		do_width = value
		_mark_layout_dirty()

## Prefer/Team dropdowns
@export var prefer_offset: Vector2 = Vector2(15, 23):
	set(value):
		if prefer_offset == value:
			return
		prefer_offset = value
		_mark_layout_dirty()

@export var prefer_width: float = 70.0:
	set(value):
		if prefer_width == value:
			return
		prefer_width = value
		_mark_layout_dirty()

@export var team_offset: Vector2 = Vector2(90, 23):
	set(value):
		if team_offset == value:
			return
		team_offset = value
		_mark_layout_dirty()

@export var team_width: float = 65.0:
	set(value):
		if team_width == value:
			return
		team_width = value
		_mark_layout_dirty()

## To dropdown (action target)
@export var to_offset: Vector2 = Vector2(15, 39):
	set(value):
		if to_offset == value:
			return
		to_offset = value
		_mark_layout_dirty()

@export var to_width: float = 135.0:
	set(value):
		if to_width == value:
			return
		to_width = value
		_mark_layout_dirty()

## When dropdown (condition target)
@export var when_offset: Vector2 = Vector2(15, 55):
	set(value):
		if when_offset == value:
			return
		when_offset = value
		_mark_layout_dirty()

@export var when_width: float = 135.0:
	set(value):
		if when_width == value:
			return
		when_width = value
		_mark_layout_dirty()

## Trigger Prefer/Team dropdowns
@export var trigger_prefer_offset: Vector2 = Vector2(15, 71):
	set(value):
		if trigger_prefer_offset == value:
			return
		trigger_prefer_offset = value
		_mark_layout_dirty()

@export var trigger_prefer_width: float = 70.0:
	set(value):
		if trigger_prefer_width == value:
			return
		trigger_prefer_width = value
		_mark_layout_dirty()

@export var trigger_team_offset: Vector2 = Vector2(90, 71):
	set(value):
		if trigger_team_offset == value:
			return
		trigger_team_offset = value
		_mark_layout_dirty()

@export var trigger_team_width: float = 60.0:
	set(value):
		if trigger_team_width == value:
			return
		trigger_team_width = value
		_mark_layout_dirty()

## Condition dropdowns base offset and spacing
@export var condition_base_offset: Vector2 = Vector2(8, 6):
	set(value):
		if condition_base_offset == value:
			return
		condition_base_offset = value
		_mark_layout_dirty()

@export var condition_row_height: float = 20.0:
	set(value):
		if condition_row_height == value:
			return
		condition_row_height = value
		_mark_layout_dirty()

@export var condition_type_width: float = 100.0:
	set(value):
		if condition_type_width == value:
			return
		condition_type_width = value
		_mark_layout_dirty()

@export var condition_param_offset_x: float = 115.0:
	set(value):
		if condition_param_offset_x == value:
			return
		condition_param_offset_x = value
		_mark_layout_dirty()

@export var condition_param_width: float = 65.0:
	set(value):
		if condition_param_width == value:
			return
		condition_param_width = value
		_mark_layout_dirty()

#endregion

#region Constants

# "Move" is the single movement verb (ADR-0062); it drives the To/Prefer/Team
# unit-target pickers (unit-anchored reposition). "Retreat"/"Approach" are not
# verbs — movement flavor is composed from the target. Tile-targeted moves are
# not authorable here yet (issue #38).
const STANDARD_ACTIONS: Array[String] = ["Attack", "Move", "Wait"]
const PREFER_OPTIONS: Array[String] = ["Nearest", "Most Critical", "Highest HP", "Lowest HP", "First"]
const TEAM_OPTIONS: Array[String] = ["Friendly", "Enemy"]
const CONDITION_TYPES: Array[String] = ["Always", "HP <", "HP >", "MP <", "In Range"]
const CONDITION_PARAM_HP: Array[String] = ["10%", "25%", "50%", "75%", "90%"]
const CONDITION_PARAM_RANGE: Array[String] = ["melee", "spell"]
const NOUNS_WITHOUT_FILTERS: Array[String] = ["Self", "Triggering"]

#endregion

#region Internal State

var _top_menu: UIMenuFrame
var _bottom_menu: UIMenuFrame
var _header_text_elem: UIText

var _dropdowns: Dictionary = {}  # key -> UIDropdown
var _labels: Dictionary = {}  # key -> UIText

var _unit: Node = null
var _gambit_index: int = -1
var _original_gambit: Gambit = null
var _working_conditions: Array[GambitCondition] = []
var _available_unit_names: Array[String] = []
var _ability_popup: UIActionAbilityPopup = null
var _selected_ability_name: String = ""  # Display name of selected ability, or "" for standard action
var _selected_ability_id: int = -1  # Ability id of selected ability, or -1 for a control verb

var _components_built: bool = false

#endregion


func _ready() -> void:
	_init_working_conditions()
	super._ready()
	visible = false


func _build_children() -> void:
	_build_ui()


func _init_working_conditions() -> void:
	_working_conditions.clear()
	for i in range(4):
		_working_conditions.append(GambitCondition.always())


#region UI Building

func _build_ui() -> void:
	_cleanup()

	# Top menu
	_top_menu = UIMenuFrame.new()
	_top_menu.name = "TopMenu"
	_top_menu.pixels_per_unit = pixels_per_unit
	_top_menu.frame_size = top_menu_size
	_top_menu.show_frame = top_menu_show_frame
	add_child(_top_menu)

	# Bottom menu
	_bottom_menu = UIMenuFrame.new()
	_bottom_menu.name = "BottomMenu"
	_bottom_menu.pixels_per_unit = pixels_per_unit
	_bottom_menu.frame_size = bottom_menu_size
	_bottom_menu.show_frame = bottom_menu_show_frame
	add_child(_bottom_menu)

	_build_top_menu()
	_build_bottom_menu()

	_components_built = true


func _cleanup() -> void:
	if _top_menu:
		_top_menu.queue_free()
		_top_menu = null

	if _bottom_menu:
		_bottom_menu.queue_free()
		_bottom_menu = null

	_dropdowns.clear()
	_labels.clear()
	_components_built = false


func _build_top_menu() -> void:
	# Header text
	_header_text_elem = _create_text(header_text, header_offset, header_scale, header_palette, header_space_width)
	_top_menu.add_child(_header_text_elem)

	# Labels and dropdowns
	var lt = label_texts
	_create_label_and_dropdown("do", lt[0] if lt.size() > 0 else "Do", do_label_offset, do_offset, do_width, _get_do_options())
	_create_label_and_dropdown("prefer", lt[1] if lt.size() > 1 else "Prefer", prefer_label_offset, prefer_offset, prefer_width, PREFER_OPTIONS.duplicate())
	_create_dropdown("team", team_offset, team_width, TEAM_OPTIONS.duplicate())
	_create_label_and_dropdown("to", lt[2] if lt.size() > 2 else "To", to_label_offset, to_offset, to_width, _get_noun_options(true))
	_create_label_and_dropdown("when", lt[3] if lt.size() > 3 else "When", when_label_offset, when_offset, when_width, _get_noun_options(false))
	_create_label_and_dropdown("trigger_prefer", lt[4] if lt.size() > 4 else "Trigger", trigger_label_offset, trigger_prefer_offset, trigger_prefer_width, PREFER_OPTIONS.duplicate())
	_create_dropdown("trigger_team", trigger_team_offset, trigger_team_width, TEAM_OPTIONS.duplicate())


func _build_bottom_menu() -> void:
	var cl_offsets = [condition_label_0_offset, condition_label_1_offset, condition_label_2_offset, condition_label_3_offset]
	for i in range(4):
		var row_y = condition_base_offset.y + i * condition_row_height

		# Condition label
		var label_text = condition_label_texts[i] if i < condition_label_texts.size() else ""
		var label = _create_text(label_text, cl_offsets[i], condition_label_scale, condition_label_palette, condition_label_space_width)
		_bottom_menu.add_child(label)
		_labels["condition_%d_label" % i] = label

		# Type dropdown
		var type_key = "condition_%d_type" % i
		var type_offset = Vector2(condition_base_offset.x, row_y)
		_create_condition_dropdown(type_key, type_offset, condition_type_width, CONDITION_TYPES.duplicate(), i)

		# Param dropdown
		var param_key = "condition_%d_param" % i
		var param_offset = Vector2(condition_param_offset_x, row_y)
		_create_condition_dropdown(param_key, param_offset, condition_param_width, _get_condition_param_options(0), i)


func _create_text(text: String, offset: Vector2, scale: float, palette: int, sw: float = 1.0) -> UIText:
	var elem = UIText.new()
	elem.text = text
	elem.pixels_per_unit = pixels_per_unit * scale
	elem.space_width = sw
	elem.set_palette(palette)
	elem.position = Vector3(offset.x * pixels_per_unit, -offset.y * pixels_per_unit, 0.02)
	return elem


func _create_label_and_dropdown(key: String, label_text: String, label_offset: Vector2, dd_offset: Vector2, dd_width: float, options: Array) -> void:
	# Label
	var label = _create_text(label_text, label_offset, label_scale, label_palette, label_space_width)
	_top_menu.add_child(label)
	_labels[key + "_label"] = label

	# Dropdown
	_create_dropdown(key, dd_offset, dd_width, options)


func _create_dropdown(key: String, offset: Vector2, width: float, options: Array) -> void:
	var dd = UIDropdown.new()
	dd.options = options as Array[String]
	dd.width = width
	dd.pixels_per_unit = pixels_per_unit * dropdown_scale
	dd.text_palette = dropdown_palette
	dd.space_width = 1.0
	dd.position = Vector3(offset.x * pixels_per_unit, -offset.y * pixels_per_unit, 0.03)
	dd.option_selected.connect(_on_dropdown_changed.bind(key))

	_top_menu.add_child(dd)
	_dropdowns[key] = dd


func _create_condition_dropdown(key: String, offset: Vector2, width: float, options: Array, row_index: int) -> void:
	var dd = UIDropdown.new()
	dd.options = options as Array[String]
	dd.width = width
	dd.pixels_per_unit = pixels_per_unit * dropdown_scale
	dd.text_palette = dropdown_palette
	dd.space_width = 1.0
	dd.position = Vector3(offset.x * pixels_per_unit, -offset.y * pixels_per_unit, 0.03)

	if key.ends_with("_type"):
		dd.option_selected.connect(_on_condition_type_changed.bind(row_index))
	else:
		dd.option_selected.connect(_on_condition_param_changed.bind(row_index))

	_bottom_menu.add_child(dd)
	_dropdowns[key] = dd

#endregion


#region Layout Update

func _update_layout() -> void:
	if not _components_built:
		return
	if not _top_menu or not _bottom_menu:
		return

	_top_menu.pixels_per_unit = pixels_per_unit
	_top_menu.frame_size = top_menu_size
	_top_menu.show_frame = top_menu_show_frame
	_top_menu.position = Vector3.ZERO

	_bottom_menu.pixels_per_unit = pixels_per_unit
	_bottom_menu.frame_size = bottom_menu_size
	_bottom_menu.show_frame = bottom_menu_show_frame
	_bottom_menu.position = Vector3(
		0,
		-(top_menu_size.y + menu_spacing) * pixels_per_unit,
		0
	)

	_update_all_child_positions()


func _update_all_child_positions() -> void:
	# Header text
	if _header_text_elem:
		_header_text_elem.text = header_text
		_header_text_elem.pixels_per_unit = pixels_per_unit * header_scale
		_header_text_elem.space_width = header_space_width
		_header_text_elem.set_palette(header_palette)
		_header_text_elem.position = Vector3(header_offset.x * pixels_per_unit, -header_offset.y * pixels_per_unit, 0.02)

	# Top menu dropdowns
	_update_dropdown("do", do_offset, do_width)
	_update_dropdown("prefer", prefer_offset, prefer_width)
	_update_dropdown("team", team_offset, team_width)
	_update_dropdown("to", to_offset, to_width)
	_update_dropdown("when", when_offset, when_width)
	_update_dropdown("trigger_prefer", trigger_prefer_offset, trigger_prefer_width)
	_update_dropdown("trigger_team", trigger_team_offset, trigger_team_width)

	# Top menu labels
	var lt = label_texts
	_update_label("do_label", do_label_offset, lt[0] if lt.size() > 0 else "Do")
	_update_label("prefer_label", prefer_label_offset, lt[1] if lt.size() > 1 else "Prefer")
	_update_label("to_label", to_label_offset, lt[2] if lt.size() > 2 else "To")
	_update_label("when_label", when_label_offset, lt[3] if lt.size() > 3 else "When")
	_update_label("trigger_prefer_label", trigger_label_offset, lt[4] if lt.size() > 4 else "Trigger")

	# Bottom menu condition dropdowns
	for i in range(4):
		var row_y = condition_base_offset.y + i * condition_row_height
		var type_offset = Vector2(condition_base_offset.x, row_y)
		var param_offset = Vector2(condition_param_offset_x, row_y)
		_update_condition_dropdown("condition_%d_type" % i, type_offset, condition_type_width)
		_update_condition_dropdown("condition_%d_param" % i, param_offset, condition_param_width)

	# Bottom menu condition labels
	_update_condition_labels()


func _update_dropdown(key: String, offset: Vector2, dd_width: float) -> void:
	var dd = _dropdowns.get(key) as UIDropdown
	if not dd:
		return
	dd.width = dd_width
	dd.pixels_per_unit = pixels_per_unit * dropdown_scale
	dd.text_palette = dropdown_palette
	dd.position = Vector3(offset.x * pixels_per_unit, -offset.y * pixels_per_unit, 0.03)


func _update_label(label_key: String, offset: Vector2, text: String = "") -> void:
	var label = _labels.get(label_key) as UIText
	if not label:
		return
	if not text.is_empty():
		label.text = text
	label.pixels_per_unit = pixels_per_unit * label_scale
	label.space_width = label_space_width
	label.set_palette(label_palette)
	label.position = Vector3(offset.x * pixels_per_unit, -offset.y * pixels_per_unit, 0.02)


func _update_condition_dropdown(key: String, offset: Vector2, dd_width: float) -> void:
	var dd = _dropdowns.get(key) as UIDropdown
	if not dd:
		return
	dd.width = dd_width
	dd.pixels_per_unit = pixels_per_unit * dropdown_scale
	dd.text_palette = dropdown_palette
	dd.position = Vector3(offset.x * pixels_per_unit, -offset.y * pixels_per_unit, 0.03)


func _update_condition_labels() -> void:
	var cl_offsets = [condition_label_0_offset, condition_label_1_offset, condition_label_2_offset, condition_label_3_offset]
	for i in range(4):
		var label = _labels.get("condition_%d_label" % i) as UIText
		if not label:
			continue
		var label_text = condition_label_texts[i] if i < condition_label_texts.size() else ""
		label.text = label_text
		label.pixels_per_unit = pixels_per_unit * condition_label_scale
		label.space_width = condition_label_space_width
		label.set_palette(condition_label_palette)
		var offset = cl_offsets[i]
		label.position = Vector3(offset.x * pixels_per_unit, -offset.y * pixels_per_unit, 0.02)

#endregion


#region Options Generation

func _get_do_options() -> Array[String]:
	var options: Array[String] = STANDARD_ACTIONS.duplicate()
	options.append("Ability...")
	return options


func _get_noun_options(include_triggering: bool) -> Array[String]:
	var options: Array[String] = ["Self"]
	if include_triggering:
		options.append("Triggering")
	options.append("Unit")

	# Add job roles
	if UnitRole:
		for role in UnitRole.get_all_roles():
			options.append(UnitRole.get_role_name(role))

	# Add available unit names
	for name in _available_unit_names:
		if not name.is_empty() and name not in options:
			options.append(name)

	return options


func _get_condition_param_options(type_index: int) -> Array[String]:
	if type_index == 4:  # In Range
		return CONDITION_PARAM_RANGE.duplicate()
	elif type_index == 0:  # Always
		return ["---"] as Array[String]
	else:
		return CONDITION_PARAM_HP.duplicate()

#endregion


#region Public API

## Open the editor for a specific gambit.
## If world_position is non-zero, moves editor to that position.
## If Vector3.ZERO (default), keeps current position (useful for scene-placed editors).
## Named `open_at` (not `open`) since the UIComponent base-swap (ADR-0088 Amendment 5) —
## `UI3Element.open()` is the transition verb the widget world now inherits.
func open_at(unit: Node, gambit_index: int, world_position: Vector3 = Vector3.ZERO) -> void:
	UIDropdown.close_any_open()
	if world_position != Vector3.ZERO:
		position = world_position
	_unit = unit
	_gambit_index = gambit_index

	if not unit or not "gambit_list" in unit or not unit.gambit_list:
		push_warning("[UIGambitEditor3] Invalid unit or gambit_list")
		return

	if gambit_index < 0 or gambit_index >= unit.gambit_list.size():
		push_warning("[UIGambitEditor3] Invalid gambit index: %d" % gambit_index)
		return

	_original_gambit = unit.gambit_list.get_at(gambit_index)
	_populate_conditions_from_gambit(_original_gambit)

	if not _components_built:
		_build_ui()
		_update_layout()
	else:
		_update_do_dropdown_options()

	_populate_from_gambit(_original_gambit)
	visible = true


## Close inherited from UIModalWindow (hide + emit closed); already saved on
## every change. Teardown only cascades to the private action sub-picker —
## this editor owns it (it is never a top-level modal), so closing the editor
## must dismiss it too. Also sweeps any open dropdown. See ADR-0010.
func _on_closing() -> void:
	UIDropdown.close_any_open()
	if _ability_popup and _ability_popup.is_open():
		_ability_popup.close()


## Set available unit names for noun dropdowns
## Set the ability popup used for "Ability..." selection
func set_ability_popup(popup: UIActionAbilityPopup) -> void:
	if _ability_popup and _ability_popup.action_selected.is_connected(_on_ability_selected):
		_ability_popup.action_selected.disconnect(_on_ability_selected)
	_ability_popup = popup
	if _ability_popup:
		_ability_popup.action_selected.connect(_on_ability_selected)

#endregion


#region Gambit Population

func _populate_conditions_from_gambit(gambit: Gambit) -> void:
	_init_working_conditions()
	if not gambit or gambit.conditions.is_empty():
		return

	for i in range(mini(gambit.conditions.size(), 4)):
		var cond = gambit.conditions[i]
		var new_cond = GambitCondition.new(cond.type, cond.comparator, cond.threshold)
		new_cond.range_type = cond.range_type
		new_cond.status_id = cond.status_id
		new_cond.ability_name = cond.ability_name
		new_cond.hp_amount = cond.hp_amount
		_working_conditions[i] = new_cond


func _populate_from_gambit(gambit: Gambit) -> void:
	if not gambit:
		return

	# Do dropdown
	var do_dd = _dropdowns.get("do") as UIDropdown
	if do_dd:
		if gambit.action_kind == Gambit.ActionKind.ABILITY:
			var ability_name := AbilityDatabase.get_ability_view(gambit.ability_id).name
			_selected_ability_id = gambit.ability_id
			_selected_ability_name = ability_name
			do_dd.set_display_override(ability_name)
		else:
			_selected_ability_id = -1
			_selected_ability_name = ""
			do_dd.clear_display_override()
			do_dd.select_by_value(Gambit.KIND_TO_VERB.get(gambit.action_kind, "Wait"))

	# Action target
	_populate_target_dropdowns(gambit.action_target, "to", "prefer", "team")

	# Condition target
	_populate_target_dropdowns(gambit.condition_target, "when", "trigger_prefer", "trigger_team")

	# Update enabled states
	_update_dropdown_enabled_states()

	# Conditions
	_populate_condition_dropdowns()

	_emit_gambit_changed()


func _populate_target_dropdowns(target: TargetSelector, noun_key: String, prefer_key: String, team_key: String) -> void:
	var noun_dd = _dropdowns.get(noun_key) as UIDropdown
	var prefer_dd = _dropdowns.get(prefer_key) as UIDropdown
	var team_dd = _dropdowns.get(team_key) as UIDropdown

	if noun_dd and target:
		match target.pool_type:
			TargetSelector.PoolType.SELF:
				noun_dd.select_by_value("Self")
			TargetSelector.PoolType.TRIGGERING:
				noun_dd.select_by_value("Triggering")
			TargetSelector.PoolType.TEAM_FILTER:
				if target.role_filter != UnitRole.Role.ANY:
					noun_dd.select_by_value(UnitRole.get_role_name(target.role_filter))
				else:
					noun_dd.select_by_value("Unit")
			TargetSelector.PoolType.SPECIFIC_UNITS:
				if target.unit_names.size() > 0:
					noun_dd.select_by_value(target.unit_names[0])

	if prefer_dd and target:
		prefer_dd.selected_index = mini(target.resolution, PREFER_OPTIONS.size() - 1)

	if team_dd and target:
		team_dd.selected_index = 0 if target.team_filter == TargetSelector.TeamFilter.FRIENDLY else 1


func _populate_condition_dropdowns() -> void:
	for i in range(4):
		var cond = _working_conditions[i]
		var type_key = "condition_%d_type" % i
		var param_key = "condition_%d_param" % i

		var type_dd = _dropdowns.get(type_key) as UIDropdown
		var param_dd = _dropdowns.get(param_key) as UIDropdown

		if type_dd:
			type_dd.selected_index = _condition_type_to_index(cond)

		if param_dd:
			var type_idx = _condition_type_to_index(cond)
			param_dd.options = _get_condition_param_options(type_idx)
			param_dd.selected_index = _condition_param_to_index(cond)


func _condition_type_to_index(cond: GambitCondition) -> int:
	match cond.type:
		GambitCondition.Type.ALWAYS:
			return 0
		GambitCondition.Type.TARGET_HP:
			return 1 if cond.comparator == GambitCondition.Comparator.LESS_THAN else 2
		GambitCondition.Type.TARGET_MP:
			return 3
		GambitCondition.Type.TARGET_IN_RANGE:
			return 4
		GambitCondition.Type.SELF_HP, GambitCondition.Type.ALLY_HP, GambitCondition.Type.ENEMY_HP:
			return 1 if cond.comparator == GambitCondition.Comparator.LESS_THAN else 2
		GambitCondition.Type.SELF_MP:
			return 3
		GambitCondition.Type.ENEMY_IN_RANGE, GambitCondition.Type.ALLY_IN_RANGE:
			return 4
	return 0


func _condition_param_to_index(cond: GambitCondition) -> int:
	match cond.type:
		GambitCondition.Type.ALWAYS:
			return 0
		GambitCondition.Type.ENEMY_IN_RANGE, GambitCondition.Type.ALLY_IN_RANGE, GambitCondition.Type.TARGET_IN_RANGE:
			return 0 if cond.range_type == GambitCondition.RangeType.MELEE else 1
		_:
			if cond.threshold <= 10:
				return 0
			elif cond.threshold <= 25:
				return 1
			elif cond.threshold <= 50:
				return 2
			elif cond.threshold <= 75:
				return 3
			else:
				return 4
	return 0

#endregion


#region Event Handlers

func _on_dropdown_changed(_index: int, _value: String, key: String) -> void:
	if key == "do" and _value == "Ability...":
		_open_ability_popup()
		# Restore display override if we had a previous ability selected,
		# so cancelling the popup doesn't lose the previous selection
		if not _selected_ability_name.is_empty():
			var do_dd = _dropdowns.get("do") as UIDropdown
			if do_dd:
				do_dd.set_display_override(_selected_ability_name)
		return
	if key == "do" and _value != "Ability...":
		_selected_ability_name = ""
		_selected_ability_id = -1
		var do_dd = _dropdowns.get("do") as UIDropdown
		if do_dd:
			do_dd.clear_display_override()
	if key in ["to", "when"]:
		_update_dropdown_enabled_states()
	_emit_gambit_changed()


func _on_condition_type_changed(type_index: int, _value: String, row_index: int) -> void:
	_working_conditions[row_index] = _index_to_condition(type_index, _working_conditions[row_index])

	var param_key = "condition_%d_param" % row_index
	var param_dd = _dropdowns.get(param_key) as UIDropdown
	if param_dd:
		param_dd.options = _get_condition_param_options(type_index)
		param_dd.selected_index = 0

	_emit_gambit_changed()


func _on_condition_param_changed(param_index: int, _value: String, row_index: int) -> void:
	var cond = _working_conditions[row_index]

	match cond.type:
		GambitCondition.Type.ENEMY_IN_RANGE, GambitCondition.Type.ALLY_IN_RANGE, GambitCondition.Type.TARGET_IN_RANGE:
			cond.range_type = GambitCondition.RangeType.MELEE if param_index == 0 else GambitCondition.RangeType.SPELL
		_:
			var thresholds = [10.0, 25.0, 50.0, 75.0, 90.0]
			cond.threshold = thresholds[param_index] if param_index < thresholds.size() else 50.0

	_emit_gambit_changed()


func _index_to_condition(index: int, existing: GambitCondition = null) -> GambitCondition:
	var threshold = existing.threshold if existing else 50.0
	match index:
		0:
			return GambitCondition.always()
		1:
			return GambitCondition.target_hp_below(threshold)
		2:
			return GambitCondition.target_hp_above(threshold)
		3:
			return GambitCondition.target_mp_below(threshold)
		4:
			return GambitCondition.target_in_range()
	return GambitCondition.always()


func _update_dropdown_enabled_states() -> void:
	var to_dd = _dropdowns.get("to") as UIDropdown
	var when_dd = _dropdowns.get("when") as UIDropdown

	if to_dd:
		var needs_filters = _noun_needs_filters(to_dd.get_selected_value())
		_set_dropdown_enabled("prefer", needs_filters)
		_set_dropdown_enabled("team", needs_filters)

	if when_dd:
		var needs_filters = _noun_needs_filters(when_dd.get_selected_value())
		_set_dropdown_enabled("trigger_prefer", needs_filters)
		_set_dropdown_enabled("trigger_team", needs_filters)


func _noun_needs_filters(noun: String) -> bool:
	if noun in NOUNS_WITHOUT_FILTERS:
		return false
	# Check if specific unit name
	if noun not in ["Self", "Triggering", "Unit"]:
		# 🔴 THIS GATE HAS BEEN FALSE SINCE THE ALMANAC EXTRACTION SHED THE
		# `class_name` — `UnitRole` is a `preload` const, not a registered class,
		# so `ClassDB` has never heard of it and this loop runs ZERO times. Every
		# role noun falls to `return false` and reports "needs no filters".
		# Found by #1159 and NOT fixed here: repairing it changes what the editor
		# enables, and ADR-0167 says a behavioural change does not ride inside a
		# move. Filed as #1167, which carries the measurement and the fix.
		#
		# The user-visible half: `_get_noun_options` at `:734` DOES offer every
		# role name (its own `if UnitRole:` is a preload const and always true),
		# so the editor lets you pick "Healer" and then disables the `prefer` and
		# `team` dropdowns that would say WHICH healer and WHOSE.
		for role in UnitRole.get_all_roles() if ClassDB.class_exists("UnitRole") else []:
			if UnitRole.get_role_name(role) == noun:
				return true
		return false
	return true


func _set_dropdown_enabled(key: String, enabled: bool) -> void:
	var dd = _dropdowns.get(key) as UIDropdown
	if dd:
		dd.disabled = not enabled


func _open_ability_popup() -> void:
	if not _ability_popup:
		push_warning("[UIGambitEditor3] No ability popup set")
		return
	if not _unit:
		push_warning("[UIGambitEditor3] No unit set")
		return
	_ability_popup.position.z = position.z + 0.1
	_ability_popup.show_for_unit(_unit)


func _on_ability_selected(ability_id: int) -> void:
	var ability_name = AbilityDatabase.get_ability_view(ability_id).name
	if ability_name.is_empty():
		return
	_selected_ability_name = ability_name
	_selected_ability_id = ability_id
	var do_dd = _dropdowns.get("do") as UIDropdown
	if do_dd:
		do_dd.set_display_override(ability_name)
	_emit_gambit_changed()


func _update_do_dropdown_options() -> void:
	var do_dd = _dropdowns.get("do") as UIDropdown
	if do_dd:
		var current = do_dd.get_selected_value()
		do_dd.options = _get_do_options()
		do_dd.select_by_value(current)


#endregion


#region Build Gambit

func _build_gambit_from_ui() -> Gambit:
	var gambit = Gambit.new()

	if _selected_ability_id >= 0:
		gambit.action_kind = Gambit.ActionKind.ABILITY
		gambit.ability_id = _selected_ability_id
	else:
		var action_value := "Wait"
		var do_dd = _dropdowns.get("do") as UIDropdown
		if do_dd:
			action_value = do_dd.get_selected_value()
			# "Ability..." is a UI trigger, not a real action — fall back to Attack
			if action_value == "Ability...":
				action_value = "Attack"
		gambit.action_kind = Gambit.VERB_TO_KIND.get(action_value, Gambit.ActionKind.WAIT)
		gambit.ability_id = -1

	gambit.action_target = _build_target_selector("to", "prefer", "team")
	gambit.condition_target = _build_target_selector("when", "trigger_prefer", "trigger_team")

	var active_conditions: Array[GambitCondition] = []
	for cond in _working_conditions:
		if cond.type != GambitCondition.Type.ALWAYS:
			active_conditions.append(cond)

	if active_conditions.is_empty():
		gambit.conditions = [GambitCondition.always()] as Array[GambitCondition]
	else:
		gambit.conditions = active_conditions

	return gambit


func _build_target_selector(noun_key: String, prefer_key: String, team_key: String) -> TargetSelector:
	var noun_dd = _dropdowns.get(noun_key) as UIDropdown
	var prefer_dd = _dropdowns.get(prefer_key) as UIDropdown
	var team_dd = _dropdowns.get(team_key) as UIDropdown

	var noun_value = noun_dd.get_selected_value() if noun_dd else "Unit"
	var prefer_idx = prefer_dd.selected_index if prefer_dd else 0
	var team_idx = team_dd.selected_index if team_dd else 1

	var target = TargetSelector.new()

	match noun_value:
		"Self":
			target = TargetSelector.self_()
		"Triggering":
			target = TargetSelector.triggering()
		"Unit":
			target.pool_type = TargetSelector.PoolType.TEAM_FILTER
			target.team_filter = TargetSelector.TeamFilter.FRIENDLY if team_idx == 0 else TargetSelector.TeamFilter.ENEMY
			target.role_filter = UnitRole.Role.ANY
			target.resolution = prefer_idx
		_:
			var role = _get_role_from_name(noun_value)
			if role != UnitRole.Role.ANY:
				target.pool_type = TargetSelector.PoolType.TEAM_FILTER
				target.team_filter = TargetSelector.TeamFilter.FRIENDLY if team_idx == 0 else TargetSelector.TeamFilter.ENEMY
				target.role_filter = role
				target.resolution = prefer_idx
			else:
				target.pool_type = TargetSelector.PoolType.SPECIFIC_UNITS
				target.unit_names = [noun_value]

	return target


func _get_role_from_name(name: String) -> int:
	if UnitRole:
		for role in UnitRole.get_all_roles():
			if UnitRole.get_role_name(role) == name:
				return role
	return UnitRole.Role.ANY


func _emit_gambit_changed() -> void:
	var gambit = _build_gambit_from_ui()
	# Auto-save to unit's gambit list on every change
	if _unit and _unit.gambit_list and _gambit_index >= 0:
		_unit.gambit_list.replace_at(_gambit_index, gambit)
	gambit_changed.emit(gambit)

#endregion


#region Input Handling

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()

#endregion
