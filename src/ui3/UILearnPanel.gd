@tool
class_name UILearnPanel
extends UIModalWindow
## Ability learning panel showing available abilities to learn from a skill set.
##
## Displays:
## - Job dropdown to select which job's abilities to view
## - JP available for selected job
## - List of abilities with inline labels (JP:X  MP:X  CT:X  Rng:X  Learn/Learned)
##
## Vault: [[Learn Job Picker]]

## Emitted when an ability is learned

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const AbilityView = ExMateriaAlmanac.AbilityView
const JobDatabase = ExMateriaAlmanac.JobDatabase
const LearnableAbility = ExMateriaAlmanac.LearnableAbility

signal ability_learned(ability_id: int)


## Typed row payload for one learnable ability — pure display payload, no
## identity. Carries pre-formatted display strings and pre-resolved state
## palettes (same `schema-as-data` discipline as UIListModalWindow's [row
## column schema] / ADR-0016's gambit encode schema). State-derived overrides
## (`learned_palette` / `unaffordable_palette`) resolve once in
## `_add_ability_row`, not at render time. Identity (`ability_id`) is *not*
## on the row — it threads through the scroll list (`add_item`'s data arg
## feeds `_on_ability_selected`) and the click-area bind, both function-scope
## of `_add_ability_row`.
class AbilityLearnRow:
	extends RefCounted
	var name: String
	var jp_text: String      # pre-formatted: "JP:100"
	var mp_text: String      # pre-formatted: "MP:12" or "" when 0
	var ct_text: String      # pre-formatted: "CT:4"  or "" when 0
	var range_text: String   # pre-formatted: "Rng:3" or "" when 0
	var button_text: String  # "Learn" or "Learned"
	var name_palette: int    # pre-resolved with state override
	var stat_palette: int    # pre-resolved with state override (all stat cols share)

	func _init(p_name: String = "",
			p_jp_text: String = "", p_mp_text: String = "",
			p_ct_text: String = "", p_range_text: String = "",
			p_button_text: String = "",
			p_name_palette: int = 0, p_stat_palette: int = 0) -> void:
		name = p_name
		jp_text = p_jp_text
		mp_text = p_mp_text
		ct_text = p_ct_text
		range_text = p_range_text
		button_text = p_button_text
		name_palette = p_name_palette
		stat_palette = p_stat_palette


## Row column schema — six columns rendered per ability. Locally flavored
## (vs UIListModalWindow's): `offset_key` keys into the `column_offsets` Dict
## @export (which already exists), and `palette_field` reads from the row
## (since state-derived palette is per-row, not per-subclass). `space_prop`
## names a per-export space-width override (name vs stats have distinct
## widths). The painting primitive is shared with UIListModalWindow via
## `UIRowColumnRenderer.paint`; the schema-dict shape stays local because
## the knob sources differ.
const _COLUMNS = [
	{ "child": &"NameText",   "field": &"name",        "offset_key": "name",
	  "scale_prop": &"ability_name_scale",  "space_prop": &"ability_name_space_width",
	  "palette_field": &"name_palette" },
	{ "child": &"JPText",     "field": &"jp_text",     "offset_key": "jp",
	  "scale_prop": &"ability_stats_scale", "space_prop": &"ability_stats_space_width",
	  "palette_field": &"stat_palette" },
	{ "child": &"MPText",     "field": &"mp_text",     "offset_key": "mp",
	  "scale_prop": &"ability_stats_scale", "space_prop": &"ability_stats_space_width",
	  "palette_field": &"stat_palette" },
	{ "child": &"CTText",     "field": &"ct_text",     "offset_key": "ct",
	  "scale_prop": &"ability_stats_scale", "space_prop": &"ability_stats_space_width",
	  "palette_field": &"stat_palette" },
	{ "child": &"RangeText",  "field": &"range_text",  "offset_key": "range",
	  "scale_prop": &"ability_stats_scale", "space_prop": &"ability_stats_space_width",
	  "palette_field": &"stat_palette" },
	{ "child": &"ButtonText", "field": &"button_text", "offset_key": "button",
	  "scale_prop": &"ability_stats_scale", "space_prop": &"ability_stats_space_width",
	  "palette_field": &"stat_palette" },
]


## Default values for sync checking
const _CODE_DEFAULTS = {
	"pixels_per_unit": 0.04,
	"panel_width": 242.025,
	"panel_height": 180.0,
	"item_spacing": 0.0,
	"item_height": 9.0,
	"title_offset": Vector2(5, -5),
	"title_palette": 1,
	"jp_label_offset": Vector2(8, 13),
	"jp_value_offset": Vector2(22, 13),
	"jp_scale": 0.6,
	"jp_palette": 0,
	"dropdown_offset": Vector2(42, 7),
	"dropdown_width": 61.0,
	"dropdown_row_height": 7.0,
	"dropdown_text_offset_y": 3.0,
	"list_offset": Vector2(8, 25),
	"learned_palette": 2,
	"unaffordable_palette": 3,
	"ability_name_palette": 0,
	"ability_stats_palette": 0,
}

#region Configuration Exports


## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		if pixels_per_unit == value:
			return
		pixels_per_unit = value
		_mark_layout_dirty()

## Panel width in virtual pixels
@export var panel_width: float = 242.025:
	set(value):
		if panel_width == value:
			return
		panel_width = value
		_mark_layout_dirty()

## Panel height in virtual pixels
@export var panel_height: float = 180.0:
	set(value):
		if panel_height == value:
			return
		panel_height = value
		_mark_layout_dirty()

## Show frame background
@export var show_frame: bool = true:
	set(value):
		if show_frame == value:
			return
		show_frame = value
		_push(_frame, &"visible", value)

## Maximum visible abilities in list
@export var max_visible_items: int = 12:
	set(value):
		if max_visible_items == value:
			return
		max_visible_items = value
		_push(_scroll_list, &"visible_count", value)
		_mark_layout_dirty()

## Item spacing in virtual pixels
@export var item_spacing: float = 0.0:
	set(value):
		if item_spacing == value:
			return
		item_spacing = value
		_push(_scroll_list, &"item_spacing", value)
		_mark_layout_dirty()

## Item row height in virtual pixels
@export var item_height: float = 9.0:
	set(value):
		if item_height == value:
			return
		item_height = value
		_push(_scroll_list, &"virtual_item_height", value)
		_mark_layout_dirty()

## Space width for text elements (1.0 = consistent FFT style)
@export var text_space_width: float = 1.0:
	set(value):
		if text_space_width == value:
			return
		text_space_width = value
		_mark_layout_dirty()

#endregion

#region Title Configuration

@export_group("Title")

@export var title_offset: Vector2 = Vector2(5, -5):
	set(value):
		if title_offset == value:
			return
		title_offset = value
		_mark_layout_dirty()

@export var title_scale: float = 0.7:
	set(value):
		if title_scale == value:
			return
		title_scale = value
		_mark_layout_dirty()

@export var title_palette: int = 1:
	set(value):
		if title_palette == value:
			return
		title_palette = value
		_mark_layout_dirty()

#endregion

#region JP Display Configuration

@export_group("JP Display")

@export var jp_label_offset: Vector2 = Vector2(8, 13):
	set(value):
		if jp_label_offset == value:
			return
		jp_label_offset = value
		_mark_layout_dirty()

@export var jp_value_offset: Vector2 = Vector2(22, 13):
	set(value):
		if jp_value_offset == value:
			return
		jp_value_offset = value
		_mark_layout_dirty()

@export var jp_scale: float = 0.6:
	set(value):
		if jp_scale == value:
			return
		jp_scale = value
		_mark_layout_dirty()

@export var jp_palette: int = 0:
	set(value):
		if jp_palette == value:
			return
		jp_palette = value
		_mark_layout_dirty()

#endregion

#region Job Dropdown Configuration

@export_group("Job Dropdown")

@export var dropdown_offset: Vector2 = Vector2(42, 7):
	set(value):
		if dropdown_offset == value:
			return
		dropdown_offset = value
		_mark_layout_dirty()

@export var dropdown_width: float = 61.0:
	set(value):
		if dropdown_width == value:
			return
		dropdown_width = value
		_mark_layout_dirty()

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

@export var dropdown_space_width: float = 1.0:
	set(value):
		if dropdown_space_width == value:
			return
		dropdown_space_width = value
		_mark_layout_dirty()

@export var dropdown_render_priority: int = 1:
	set(value):
		if dropdown_render_priority == value:
			return
		dropdown_render_priority = value
		_mark_layout_dirty()

@export var dropdown_row_height: float = 7.0:
	set(value):
		if dropdown_row_height == value:
			return
		dropdown_row_height = value
		_mark_layout_dirty()

@export var dropdown_text_offset_x: float = 6.0:
	set(value):
		if dropdown_text_offset_x == value:
			return
		dropdown_text_offset_x = value
		_mark_layout_dirty()

@export var dropdown_text_offset_y: float = 3.0:
	set(value):
		if dropdown_text_offset_y == value:
			return
		dropdown_text_offset_y = value
		_mark_layout_dirty()

@export var dropdown_max_visible: int = 20:
	set(value):
		if dropdown_max_visible == value:
			return
		dropdown_max_visible = value
		_mark_layout_dirty()

#endregion

#region Column Configuration

@export_group("Columns")

## Column offsets (in virtual pixels from content left edge)
## Format: Name  JP:X  MP:X  CT:X  Rng:X  Learn/Learned
@export var column_offsets: Dictionary = {
	"name": 0.0,
	"jp": 70.0,
	"mp": 102.0,
	"ct": 134.0,
	"range": 162.0,
	"button": 192.0
}:
	set(value):
		if column_offsets == value:
			return
		column_offsets = value
		_mark_layout_dirty()

#endregion

#region List Configuration

@export_group("Ability List")

@export var list_offset: Vector2 = Vector2(8, 25):
	set(value):
		if list_offset == value:
			return
		list_offset = value
		_mark_layout_dirty()

@export var ability_name_scale: float = 0.6:
	set(value):
		if ability_name_scale == value:
			return
		ability_name_scale = value
		_mark_layout_dirty()

@export var ability_name_palette: int = 0:
	set(value):
		if ability_name_palette == value:
			return
		ability_name_palette = value
		_mark_layout_dirty()

@export var ability_name_space_width: float = 1.0:
	set(value):
		if ability_name_space_width == value:
			return
		ability_name_space_width = value
		_mark_layout_dirty()

@export var ability_stats_scale: float = 0.55:
	set(value):
		if ability_stats_scale == value:
			return
		ability_stats_scale = value
		_mark_layout_dirty()

@export var ability_stats_palette: int = 0:
	set(value):
		if ability_stats_palette == value:
			return
		ability_stats_palette = value
		_mark_layout_dirty()

@export var ability_stats_space_width: float = 1.0:
	set(value):
		if ability_stats_space_width == value:
			return
		ability_stats_space_width = value
		_mark_layout_dirty()

## Learned ability palette (grayed out)
@export var learned_palette: int = 2:
	set(value):
		if learned_palette == value:
			return
		learned_palette = value
		_mark_layout_dirty()

## Cannot afford palette
@export var unaffordable_palette: int = 3:
	set(value):
		if unaffordable_palette == value:
			return
		unaffordable_palette = value
		_mark_layout_dirty()

#endregion

#region Internal State

var _frame: UIFrame
var _title: UIText
var _jp_label: UIText
var _jp_value: UIText
var _job_dropdown: UIDropdown
var _job_ids: Array[String] = []  # Maps dropdown index to job_id
var _scroll_list: UIScrollableList
var _current_unit: Node = null
var _current_skill_set_id: int = -1
var _current_job_id: String = ""
var _ability_rows: Array[Dictionary] = []  # {ability_id, row_node, is_learned, can_afford, click_area?} — per-row UIText refs no longer tracked (the schema renders to anonymous children of row_node; reachable via NodePath if needed)

#endregion


func _ready() -> void:
	super._ready()
	visible = false


## Populate with real abilities for editor preview. UIComponent calls this at
## the end of every layout refresh in the editor; clear first so we rebuild
## rather than append.
func _populate_editor_preview() -> void:
	if _scroll_list:
		_clear_abilities()
	# Build dropdown
	_populate_job_dropdown()

	# Use Squire as default job for preview
	_current_job_id = "4a"

	# Load real abilities with all columns
	var abilities := AbilityDatabase.get_learnable_abilities_for_job(_current_job_id)
	var count = 0
	for ability_info in abilities:
		if count >= 8:  # Limit to 8 abilities for preview
			break
		var ability_id := ability_info.id
		var ability := AbilityDatabase.get_ability_view(ability_id)
		if ability.is_empty():
			continue

		var is_learned = count < 2  # First 2 shown as learned for preview
		var can_afford = count < 5  # First 5 can afford for preview

		_add_ability_row(
			ability_id,
			ability,
			is_learned,
			can_afford
		)
		count += 1


func _build_children() -> void:
	# Frame background
	_frame = UIFrame.new()
	_frame.pixels_per_unit = pixels_per_unit
	_frame.frame_size = Vector2(panel_width, panel_height)
	_frame.visible = show_frame
	_frame.position.z = -0.01
	add_child(_frame)

	# Title
	_title = UIText.new()
	_title.text = "Learn Abilities"
	_title.pixels_per_unit = pixels_per_unit * title_scale
	_title.space_width = text_space_width
	_title.set_palette(title_palette)
	add_child(_title)

	# JP Label
	_jp_label = UIText.new()
	_jp_label.text = "JP:"
	_jp_label.pixels_per_unit = pixels_per_unit * jp_scale
	_jp_label.space_width = text_space_width
	_jp_label.set_palette(jp_palette)
	add_child(_jp_label)

	# JP Value
	_jp_value = UIText.new()
	_jp_value.text = "0"
	_jp_value.pixels_per_unit = pixels_per_unit * jp_scale
	_jp_value.space_width = text_space_width
	_jp_value.set_palette(jp_palette)
	add_child(_jp_value)

	# Job Dropdown
	_job_dropdown = UIDropdown.new()
	_job_dropdown.pixels_per_unit = pixels_per_unit
	_job_dropdown.text_scale = dropdown_scale
	_job_dropdown.text_palette = dropdown_palette
	_job_dropdown.text_offset_x = dropdown_text_offset_x
	_job_dropdown.text_offset_y = dropdown_text_offset_y
	_job_dropdown.render_priority = dropdown_render_priority
	_job_dropdown.max_visible_options = dropdown_max_visible
	if dropdown_space_width >= 0:
		_job_dropdown.space_width = dropdown_space_width
	_job_dropdown.width = dropdown_width
	_job_dropdown.row_height = dropdown_row_height
	_job_dropdown.option_selected.connect(_on_job_selected)
	add_child(_job_dropdown)

	# Scrollable list (no headers - inline labels per row)
	_scroll_list = UIScrollableList.new()
	_scroll_list.pixels_per_unit = pixels_per_unit
	_scroll_list.visible_count = max_visible_items
	_scroll_list.item_spacing = item_spacing
	_scroll_list.virtual_item_height = item_height
	_scroll_list.show_scroll_indicators = false
	_scroll_list.item_selected.connect(_on_ability_selected)
	_scroll_list.cancelled.connect(close)
	add_child(_scroll_list)


func _update_layout() -> void:
	var ppu = pixels_per_unit

	if _frame:
		_frame.pixels_per_unit = ppu
		_frame.frame_size = Vector2(panel_width, panel_height)

	if _title:
		_title.pixels_per_unit = ppu * title_scale
		_title.space_width = text_space_width
		_title.set_palette(title_palette)
		_title.position = Vector3(
			title_offset.x * ppu,
			-title_offset.y * ppu,
			0.01
		)

	if _jp_label:
		_jp_label.pixels_per_unit = ppu * jp_scale
		_jp_label.space_width = text_space_width
		_jp_label.set_palette(jp_palette)
		_jp_label.position = Vector3(
			jp_label_offset.x * ppu,
			-jp_label_offset.y * ppu,
			0.01
		)

	if _jp_value:
		_jp_value.pixels_per_unit = ppu * jp_scale
		_jp_value.space_width = text_space_width
		_jp_value.set_palette(jp_palette)
		_jp_value.position = Vector3(
			jp_value_offset.x * ppu,
			-jp_value_offset.y * ppu,
			0.01
		)

	if _job_dropdown:
		_job_dropdown.pixels_per_unit = ppu
		_job_dropdown.text_scale = dropdown_scale
		_job_dropdown.text_palette = dropdown_palette
		_job_dropdown.text_offset_x = dropdown_text_offset_x
		_job_dropdown.text_offset_y = dropdown_text_offset_y
		_job_dropdown.render_priority = dropdown_render_priority
		_job_dropdown.max_visible_options = dropdown_max_visible
		if dropdown_space_width >= 0:
			_job_dropdown.space_width = dropdown_space_width
		_job_dropdown.width = dropdown_width
		_job_dropdown.row_height = dropdown_row_height
		# Position dropdown slightly forward (z=0.05) so open list is in front of ability rows
		_job_dropdown.position = Vector3(dropdown_offset.x * ppu, -dropdown_offset.y * ppu, 0.05)

	if _scroll_list:
		_scroll_list.pixels_per_unit = ppu
		_scroll_list.item_spacing = item_spacing
		_scroll_list.virtual_item_height = item_height
		_scroll_list.visible_count = max_visible_items
		_scroll_list.position = Vector3(
			list_offset.x * ppu,
			-list_offset.y * ppu,
			0.0
		)


#region Public API

## Open the panel for a specific skill set (legacy, prefer open_for_job)
## Open the panel for a specific job
func open_for_job(job_id: String, unit: Node, world_position: Vector3 = Vector3.ZERO) -> void:
	_current_job_id = job_id
	# Get skill_set_id from job for JP tracking
	if JobDatabase:
		var job = JobDatabase.get_job(job_id)
		_current_skill_set_id = int(job.get("skill_set_id", 0)) if not job.is_empty() else 0
	else:
		_current_skill_set_id = 0
	_current_unit = unit
	_open_internal(world_position)


func _open_internal(world_position: Vector3) -> void:
	# Only reposition if non-zero (allows scene-placed panels to keep their position)
	if world_position != Vector3.ZERO:
		position = world_position

	# Connect to unit's stats_changed to auto-refresh JP display
	if _current_unit and _current_unit.has_signal("stats_changed"):
		if not _current_unit.stats_changed.is_connected(_on_unit_stats_changed):
			_current_unit.stats_changed.connect(_on_unit_stats_changed)

	# Update title
	_title.text = "Learn Abilities"

	# Populate job dropdown
	_populate_job_dropdown()

	# Update JP display
	_update_jp_display()

	# Populate abilities
	_populate_abilities()

	visible = true
	_scroll_list.activate()


func _populate_job_dropdown() -> void:
	if not JobDatabase:
		return

	# Get all generic jobs
	var jobs = JobDatabase.get_all_generic_jobs()
	var job_list: Array = []

	for job_id in jobs:
		var job = jobs[job_id]
		job_list.append({
			"name": job.get("name", "Unknown"),
			"id": job_id
		})

	# Sort by name
	job_list.sort_custom(func(a, b): return a["name"] < b["name"])

	# Build parallel arrays: option names and job IDs
	var option_names: Array[String] = []
	_job_ids.clear()
	var selected_idx: int = 0

	for i in range(job_list.size()):
		var job_info = job_list[i]
		option_names.append(job_info["name"])
		_job_ids.append(job_info["id"])
		if job_info["id"] == _current_job_id:
			selected_idx = i

	# Set dropdown options and select current job
	if _job_dropdown:
		_job_dropdown.set_options(option_names, selected_idx)


func _on_job_selected(index: int, _value: String) -> void:
	if index >= 0 and index < _job_ids.size():
		_current_job_id = _job_ids[index]
		# Update skill_set_id for JP tracking
		if JobDatabase:
			var job = JobDatabase.get_job(_current_job_id)
			_current_skill_set_id = int(job.get("skill_set_id", 0)) if not job.is_empty() else 0
		_update_jp_display()
		_populate_abilities()


## Teardown before hiding (base UIModalWindow.close() hides + emits closed).
func _on_closing() -> void:
	# Disconnect from unit's stats_changed
	if _current_unit and _current_unit.has_signal("stats_changed"):
		if _current_unit.stats_changed.is_connected(_on_unit_stats_changed):
			_current_unit.stats_changed.disconnect(_on_unit_stats_changed)

	_scroll_list.deactivate()
	_clear_abilities()


## Refresh the display (after learning an ability)
func refresh() -> void:
	_update_jp_display()
	_populate_abilities()


func _on_unit_stats_changed() -> void:
	if visible:
		_update_jp_display()
		_populate_abilities()

#endregion


#region Internal Methods

func _update_jp_display() -> void:
	if not _current_unit:
		_jp_value.text = "0"
		return

	var jp: int = 0
	if _current_unit.has_method("get_unit_stats"):
		var stats = _current_unit.get_unit_stats()
		if stats and stats.has_method("get_progression"):
			var progression = stats.get_progression()
			if progression:
				# Get JP for the selected job
				jp = progression.job_jp.get(_current_job_id, 0)

	_jp_value.text = str(jp)


func _populate_abilities() -> void:
	_clear_abilities()

	# Get available JP for can_afford calculations
	var current_jp: int = 0
	if _current_unit and _current_unit.has_method("get_unit_stats"):
		var stats = _current_unit.get_unit_stats()
		if stats and stats.has_method("get_progression"):
			var progression = stats.get_progression()
			if progression:
				current_jp = progression.job_jp.get(_current_job_id, 0)

	# Get abilities from AbilityDatabase
	var abilities: Array[LearnableAbility] = []
	if not _current_job_id.is_empty():
		abilities = AbilityDatabase.get_learnable_abilities_for_job(_current_job_id)
	elif _current_skill_set_id > 0:
		# Fallback: get from skill set actions
		var actions = AbilityDatabase.get_skill_set_actions(_current_skill_set_id)
		for ability_id in actions:
			var view := AbilityDatabase.get_ability_view(ability_id)
			if not view.is_empty() and view.jp_cost > 0:
				abilities.append(LearnableAbility.from_view(view, "actions"))

	# Get learned abilities from unit
	var learned_ids: Array = []
	if _current_unit and _current_unit.has_method("get_unit_stats"):
		var stats = _current_unit.get_unit_stats()
		if stats and stats.has_method("get_progression"):
			var progression = stats.get_progression()
			if progression and progression.has_method("get_learned_abilities"):
				learned_ids = progression.get_learned_abilities()

	for ability_info in abilities:
		var ability_id: int = ability_info.id
		var ability := AbilityDatabase.get_ability_view(ability_id)
		if ability.is_empty():
			continue

		var jp_cost: int = ability.jp_cost
		var is_learned: bool = ability_id in learned_ids
		var can_afford: bool = current_jp >= jp_cost

		_add_ability_row(ability_id, ability, is_learned, can_afford)


func _add_ability_row(ability_id: int, ability: AbilityView, is_learned: bool, can_afford: bool) -> void:
	var ppu: float = pixels_per_unit
	var jp_cost: int = ability.jp_cost

	# Resolve state-derived palette ONCE; row carries the resolved values.
	var state_palette: int = -1
	if is_learned:
		state_palette = learned_palette
	elif not can_afford:
		state_palette = unaffordable_palette
	var name_pal: int = state_palette if state_palette >= 0 else ability_name_palette
	var stat_pal: int = state_palette if state_palette >= 0 else ability_stats_palette

	var arow := AbilityLearnRow.new(
		ability.name,
		"JP:%d"  % jp_cost,
		"MP:%d"  % ability.mp_cost,
		"CT:%d"  % ability.ct,
		"Rng:%d" % ability.range,
		"Learned" if is_learned else "Learn",
		name_pal,
		stat_pal,
	)

	var row_node := Node3D.new()
	for col in _COLUMNS:
		_render_column(arow, row_node, col, ppu)

	var row_data: Dictionary = {
		"ability_id": ability_id,
		"row_node": row_node,
		"is_learned": is_learned,
		"can_afford": can_afford,
	}

	# Click area for the Learn button — only when this row is actionable.
	if not is_learned and can_afford:
		var click_area := UIClickableField.new()
		var button_x: float = float(column_offsets.get("button", 192.0))
		var button_width: float = 50.0
		click_area.configure("learn", ability_id, Rect2(button_x, 0, button_width, item_height), ppu, false)
		click_area.clicked.connect(_on_ability_clicked.bind(ability_id, jp_cost))
		row_node.add_child(click_area)
		row_data["click_area"] = click_area

	_scroll_list.add_item(row_node, ability_id, item_height)
	_ability_rows.append(row_data)


## Resolve UILearnPanel's local schema-dict knobs and hand the painted values
## to the shared [UIRowColumnRenderer]. The schema-dict shape stays local
## (state-derived `palette_field`, `column_offsets` Dict via `offset_key`,
## split name/stats `space_prop`); only the rendering primitive is shared
## with UIListModalWindow.
func _render_column(row: AbilityLearnRow, row_node: Node3D, col: Dictionary, ppu: float) -> void:
	var field: StringName = col["field"]
	var value: String = str(row.get(field))
	var scale: float = float(get(col["scale_prop"]))
	var palette: int = int(row.get(col["palette_field"]))
	var space: float = float(get(col["space_prop"]))
	var offset_x_px: float = float(column_offsets.get(col["offset_key"], 0.0))
	UIRowColumnRenderer.paint(
		row_node, col["child"], value,
		ppu, scale, palette, space,
		offset_x_px, false,
	)


func _clear_abilities() -> void:
	_scroll_list.clear_items()
	_ability_rows.clear()


func _on_ability_selected(index: int, item_data: Variant) -> void:
	if index < 0 or index >= _ability_rows.size():
		return

	var row_data = _ability_rows[index]
	if row_data.get("is_learned", false):
		return  # Can't select already learned abilities

	var ability_id = item_data if item_data is int else -1
	if ability_id >= 0:
		_try_learn_ability(ability_id)


func _on_ability_clicked(_field_type: String, _field_index: int, ability_id: int, jp_cost: int) -> void:
	_try_learn_ability(ability_id, jp_cost)


func _try_learn_ability(ability_id: int, jp_cost: int = -1) -> void:
	if not _current_unit:
		return

	# Ignore clicks when dropdown is open (prevents click-through from dropdown options)
	if _job_dropdown and _job_dropdown.is_open:
		return

	# Get JP cost if not provided
	if jp_cost < 0:
		var ability := AbilityDatabase.get_ability_view(ability_id)
		jp_cost = ability.jp_cost

	# Check if unit has enough JP
	var available_jp: int = 0
	if _current_unit.has_method("get_unit_stats"):
		var stats = _current_unit.get_unit_stats()
		if stats and stats.has_method("get_progression"):
			var progression = stats.get_progression()
			if progression:
				available_jp = progression.job_jp.get(_current_job_id, 0)

	if available_jp < jp_cost:
		# Not enough JP - could show feedback here
		return

	# Learn the ability from the selected job (routed through Unit; see ADR-0007)
	if _current_unit.learn_ability_from_job(ability_id, _current_job_id):
		ability_learned.emit(ability_id)
		refresh()

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
