class_name ProgressionDebugPanel
extends BaseDebugPanel

## Debug panel for unit progression in GPUArena.
##
## Allows selecting units, granting XP/JP, leveling up, and resetting the cast.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase


const TuneField = preload("res://src/debug/TuneField.gd")

# The grant-amount spinboxes auto-persist (ADR-0068 AUTOSAVE) so a last-entered XP/JP/level
# count comes back next session. They sit inline against their action buttons, so we build
# the bound control alone (TuneField.build_control) and tint the adjacent label green rather
# than inject a full labeled row that would break the tight button layout.
const _LEVEL_HINT := {"min": 1, "max": 99, "step": 1}
const _AMOUNT_HINT := {"min": 1, "max": 9999, "step": 1}

var _player_units: Array = []
var _enemy_units: Array = []
var _selected_unit: Unit = null

# UI elements
var _selected_label: Label
var _status_label: Label
var _info_label: Label
var _player_list: VBoxContainer
var _enemy_list: VBoxContainer
var _unit_buttons: Dictionary = {}  # Unit -> Button
var _unit_labels: Dictionary = {}   # Unit -> Label
var _level_n_spinbox: SpinBox
var _xp_spinbox: SpinBox
var _jp_spinbox: SpinBox
var _bulk_xp_spinbox: SpinBox
var _bulk_jp_spinbox: SpinBox
var _selected_section: VBoxContainer


func setup(player_units: Array, enemy_units: Array) -> void:
	panel_title = "Progression"
	panel_category = Category.ROSTER
	_player_units = player_units
	_enemy_units = enemy_units
	_build_ui()


func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	add_child(main_vbox)

	# Selected unit + status
	_selected_label = Label.new()
	_selected_label.text = "Selected: None"
	_selected_label.add_theme_color_override("font_color", Color.YELLOW)
	main_vbox.add_child(_selected_label)

	_status_label = Label.new()
	_status_label.text = "Status: ---"
	main_vbox.add_child(_status_label)

	add_separator(main_vbox)

	# Player units section
	var player_section = create_collapsible_section(main_vbox, "Player Units", true)
	_player_list = VBoxContainer.new()
	player_section.add_child(_player_list)
	_populate_unit_list(_player_list, _player_units)

	add_separator(main_vbox)

	# Enemy units section
	var enemy_section = create_collapsible_section(main_vbox, "Enemy Units", true)
	_enemy_list = VBoxContainer.new()
	enemy_section.add_child(_enemy_list)
	_populate_unit_list(_enemy_list, _enemy_units)

	add_separator(main_vbox)

	# Selected unit actions
	_selected_section = create_collapsible_section(main_vbox, "Selected Unit", true)
	_build_selected_unit_section(_selected_section)

	add_separator(main_vbox)

	# Bulk actions
	var bulk_section = create_collapsible_section(main_vbox, "Bulk Actions", false)
	_build_bulk_section(bulk_section)

	add_separator(main_vbox)

	# Reset row. There is deliberately NO save button: ADR-0180 removed the roster save
	# path without adding one, because owned-overlay persistence is still ADR-0201 §8's
	# deferred work ("a save cannot exist before there is a game to save"). A button that
	# wrote user://roster.json would be writing to a store nothing reads.
	var reset_row = HBoxContainer.new()
	main_vbox.add_child(reset_row)

	var reset_btn = Button.new()
	reset_btn.text = "Reset Cast"
	reset_btn.pressed.connect(_on_reset_cast)
	reset_row.add_child(reset_btn)


func _populate_unit_list(container: VBoxContainer, units: Array) -> void:
	for unit in units:
		if not is_instance_valid(unit):
			continue
		var hbox = HBoxContainer.new()
		container.add_child(hbox)

		var btn = Button.new()
		btn.text = "Select"
		btn.custom_minimum_size.x = 60
		btn.pressed.connect(_on_unit_button_pressed.bind(unit))
		hbox.add_child(btn)
		_unit_buttons[unit] = btn

		var label = Label.new()
		label.text = _get_unit_label(unit)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)
		_unit_labels[unit] = label


func _build_selected_unit_section(container: VBoxContainer) -> void:
	_info_label = Label.new()
	_info_label.text = "(select a unit)"
	container.add_child(_info_label)

	# Level up row
	var level_row = HBoxContainer.new()
	container.add_child(level_row)

	var lvl1_btn = Button.new()
	lvl1_btn.text = "Level Up +1"
	lvl1_btn.pressed.connect(_on_level_up_one)
	level_row.add_child(lvl1_btn)

	var lvln_btn = Button.new()
	lvln_btn.text = "Level Up xN"
	lvln_btn.pressed.connect(_on_level_up_n)
	level_row.add_child(lvln_btn)

	_level_n_spinbox = TuneField.build_control("progression.level_up_count", 5,
		_LEVEL_HINT, Callable(), Tune.Persist.AUTOSAVE) as SpinBox
	_level_n_spinbox.custom_minimum_size.x = 70
	level_row.add_child(_level_n_spinbox)

	# XP row
	var xp_row = HBoxContainer.new()
	container.add_child(xp_row)

	var xp_label = Label.new()
	xp_label.text = "XP:"
	xp_label.add_theme_color_override("font_color", TuneField.AUTOSAVE_ACCENT)
	xp_row.add_child(xp_label)

	_xp_spinbox = TuneField.build_control("progression.grant_xp", 100,
		_AMOUNT_HINT, Callable(), Tune.Persist.AUTOSAVE) as SpinBox
	_xp_spinbox.custom_minimum_size.x = 80
	xp_row.add_child(_xp_spinbox)

	var xp_btn = Button.new()
	xp_btn.text = "Grant XP"
	xp_btn.pressed.connect(_on_grant_xp)
	xp_row.add_child(xp_btn)

	# JP row
	var jp_row = HBoxContainer.new()
	container.add_child(jp_row)

	var jp_label = Label.new()
	jp_label.text = "JP:"
	jp_label.add_theme_color_override("font_color", TuneField.AUTOSAVE_ACCENT)
	jp_row.add_child(jp_label)

	_jp_spinbox = TuneField.build_control("progression.grant_jp", 200,
		_AMOUNT_HINT, Callable(), Tune.Persist.AUTOSAVE) as SpinBox
	_jp_spinbox.custom_minimum_size.x = 80
	jp_row.add_child(_jp_spinbox)

	var jp_btn = Button.new()
	jp_btn.text = "Grant JP All Jobs"
	jp_btn.pressed.connect(_on_grant_jp_all)
	jp_row.add_child(jp_btn)


func _build_bulk_section(container: VBoxContainer) -> void:
	# Bulk XP row
	var bxp_row = HBoxContainer.new()
	container.add_child(bxp_row)

	var bxp_label = Label.new()
	bxp_label.text = "XP:"
	bxp_label.add_theme_color_override("font_color", TuneField.AUTOSAVE_ACCENT)
	bxp_row.add_child(bxp_label)

	_bulk_xp_spinbox = TuneField.build_control("progression.bulk_xp", 100,
		_AMOUNT_HINT, Callable(), Tune.Persist.AUTOSAVE) as SpinBox
	_bulk_xp_spinbox.custom_minimum_size.x = 80
	bxp_row.add_child(_bulk_xp_spinbox)

	var bxp_friendly = Button.new()
	bxp_friendly.text = "Friendly"
	bxp_friendly.pressed.connect(_on_bulk_xp.bind(true))
	bxp_row.add_child(bxp_friendly)

	var bxp_enemy = Button.new()
	bxp_enemy.text = "Enemy"
	bxp_enemy.pressed.connect(_on_bulk_xp.bind(false))
	bxp_row.add_child(bxp_enemy)

	# Bulk JP row
	var bjp_row = HBoxContainer.new()
	container.add_child(bjp_row)

	var bjp_label = Label.new()
	bjp_label.text = "JP:"
	bjp_label.add_theme_color_override("font_color", TuneField.AUTOSAVE_ACCENT)
	bjp_row.add_child(bjp_label)

	_bulk_jp_spinbox = TuneField.build_control("progression.bulk_jp", 200,
		_AMOUNT_HINT, Callable(), Tune.Persist.AUTOSAVE) as SpinBox
	_bulk_jp_spinbox.custom_minimum_size.x = 80
	bjp_row.add_child(_bulk_jp_spinbox)

	var bjp_friendly = Button.new()
	bjp_friendly.text = "Friendly"
	bjp_friendly.pressed.connect(_on_bulk_jp.bind(true))
	bjp_row.add_child(bjp_friendly)

	var bjp_enemy = Button.new()
	bjp_enemy.text = "Enemy"
	bjp_enemy.pressed.connect(_on_bulk_jp.bind(false))
	bjp_row.add_child(bjp_enemy)


#region Unit Selection

func _on_unit_button_pressed(unit: Unit) -> void:
	_select_unit(unit)


func _select_unit(unit: Unit) -> void:
	# Deselect previous
	if _selected_unit and _unit_buttons.has(_selected_unit):
		_unit_buttons[_selected_unit].text = "Select"

	_selected_unit = unit

	if unit:
		_selected_label.text = "Selected: %s" % unit.name
		if _unit_buttons.has(unit):
			_unit_buttons[unit].text = ">>>"
		_update_info_label()
	else:
		_selected_label.text = "Selected: None"
		_info_label.text = "(select a unit)"

#endregion


#region Actions

func _on_level_up_one() -> void:
	if not _selected_unit or not _selected_unit.unit_progression:
		_set_status("No unit selected")
		return
	_selected_unit.level_up()
	_heal_to_full(_selected_unit)
	_refresh_after_change(_selected_unit)
	_set_status("Leveled up %s to Lv%d" % [_selected_unit.name, _selected_unit.level])


func _on_level_up_n() -> void:
	if not _selected_unit or not _selected_unit.unit_progression:
		_set_status("No unit selected")
		return
	var count = int(_level_n_spinbox.value)
	for i in range(count):
		_selected_unit.level_up()
	_heal_to_full(_selected_unit)
	_refresh_after_change(_selected_unit)
	_set_status("Leveled up %s x%d to Lv%d" % [_selected_unit.name, count, _selected_unit.level])


func _on_grant_xp() -> void:
	if not _selected_unit or not _selected_unit.unit_progression:
		_set_status("No unit selected")
		return
	var amount = int(_xp_spinbox.value)
	var leveled = _selected_unit.unit_progression.add_experience(amount)
	_heal_to_full(_selected_unit)
	_refresh_after_change(_selected_unit)
	var msg = "Granted %d XP to %s" % [amount, _selected_unit.name]
	if leveled:
		msg += " (now Lv%d)" % _selected_unit.level
	_set_status(msg)


func _on_grant_jp_all() -> void:
	if not _selected_unit or not _selected_unit.unit_progression:
		_set_status("No unit selected")
		return
	var amount = int(_jp_spinbox.value)
	var all_jobs = JobDatabase.get_all_generic_jobs()
	_selected_unit.unit_progression.add_jp_to_all_jobs(all_jobs, amount)
	_refresh_after_change(_selected_unit)
	_set_status("Granted %d JP to all jobs for %s" % [amount, _selected_unit.name])


func _on_bulk_xp(friendly: bool) -> void:
	var units = _player_units if friendly else _enemy_units
	var amount = int(_bulk_xp_spinbox.value)
	var team_name = "friendly" if friendly else "enemy"
	for unit in units:
		if not is_instance_valid(unit) or unit.unit_stats.is_dead:
			continue
		if unit.unit_progression:
			unit.unit_progression.add_experience(amount)
			_heal_to_full(unit)
	_refresh_all_labels()
	_update_info_label()
	_set_status("Granted %d XP to all %s units" % [amount, team_name])


func _on_bulk_jp(friendly: bool) -> void:
	var units = _player_units if friendly else _enemy_units
	var amount = int(_bulk_jp_spinbox.value)
	var team_name = "friendly" if friendly else "enemy"
	var all_jobs = JobDatabase.get_all_generic_jobs()
	for unit in units:
		if not is_instance_valid(unit) or unit.unit_stats.is_dead:
			continue
		if unit.unit_progression:
			unit.unit_progression.add_jp_to_all_jobs(all_jobs, amount)
	_refresh_all_labels()
	_update_info_label()
	_set_status("Granted %d JP (all jobs) to all %s units" % [amount, team_name])


## Reset the player population to new-game and reload, so the host re-folds its seed.
##
## The overlay is per-run seed state — `reset_to_new_game()` clears it and drops every
## Character the run added since the baseline; the reload is what re-establishes it,
## because the host folds its MutationScript at boot (`ScenarioCast.seed_owned_roster`,
## `NavigatorRunner.begin_at`). Two steps, not one: clearing without reloading would
## leave the arena standing on units nothing owns.
##
## This is the successor to "Reset Rosters", which called `BaseRoster.reset_roster()` on
## both autoloads and then SAVED — see the note on the button for why no save survives.
func _on_reset_cast() -> void:
	CharacterCatalog.reset_to_new_game()
	_set_status("Cast reset - reloading scene...")
	get_tree().reload_current_scene()

#endregion


#region Helpers

func _heal_to_full(unit: Unit) -> void:
	if not is_instance_valid(unit):
		return
	unit.unit_stats.current_hp = unit.max_hp
	unit.unit_stats.current_mp = unit.max_mp


func _get_unit_label(unit: Unit) -> String:
	if not is_instance_valid(unit):
		return "(invalid)"
	var prog = unit.unit_progression
	if prog:
		return "%s (Lv%d %s)" % [unit.name, prog.level, prog.get_current_job_name()]
	return unit.name


func _update_info_label() -> void:
	if not _selected_unit or not is_instance_valid(_selected_unit):
		_info_label.text = "(select a unit)"
		return
	var prog = _selected_unit.unit_progression
	if prog:
		_info_label.text = "Lv%d %s  HP:%d/%d  MP:%d/%d  PA:%d MA:%d Spd:%d" % [
			prog.level, prog.get_current_job_name(),
			_selected_unit.unit_stats.current_hp, _selected_unit.max_hp,
			_selected_unit.unit_stats.current_mp, _selected_unit.max_mp,
			prog.get_effective_pa(), prog.get_effective_ma(),
			prog.get_effective_speed()
		]
	else:
		_info_label.text = "%s (no progression)" % _selected_unit.name


func _refresh_after_change(unit: Unit) -> void:
	_update_info_label()
	if _unit_labels.has(unit):
		_unit_labels[unit].text = _get_unit_label(unit)


func _refresh_all_labels() -> void:
	for unit in _unit_labels:
		if is_instance_valid(unit):
			_unit_labels[unit].text = _get_unit_label(unit)


func _set_status(text: String) -> void:
	_status_label.text = "Status: %s" % text
	print("[Progression] %s" % text)


func on_shown() -> void:
	_refresh_all_labels()
	_update_info_label()

#endregion
