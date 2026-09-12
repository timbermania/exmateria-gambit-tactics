class_name ScenarioDebugPanel
extends BaseDebugPanel
## Scenario picker. One OptionButton listing every parsed scenario; picking
## one routes through ScenarioLoader.apply_scenario (sets map + battle music
## per ADR-0030). The pick AUTOSAVES: DebugConfig.active_scenario_id is backed by the
## `scenario.active_id` Tune slug, so a selection survives an app restart (not just a
## scene reload). See DebugConfig.set_active_scenario_id.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase


var _procedural_map: Node3D
var _scenario_selector: OptionButton


func setup(procedural_map: Node3D = null) -> void:
	_procedural_map = procedural_map
	panel_title = "Scenario"
	panel_category = Category.SCENARIO
	_build_ui()


func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(220, 0)
	add_child(main_vbox)

	# tune-exempt: a dynamic dropdown populated from ScenarioDatabase, so it can't be a static
	# TuneField default. Its VALUE is Tune-backed and AUTOSAVEd via DebugConfig.active_scenario_id
	# (slug scenario.active_id) — see _on_scenario_selected — so the pick sticks across restarts.
	_scenario_selector = OptionButton.new()  # tune-exempt: dynamic dropdown; value autosaves via DebugConfig
	_scenario_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scenario_selector.item_selected.connect(_on_scenario_selected)
	main_vbox.add_child(_scenario_selector)


func on_registered() -> void:
	_populate_scenario_selector.call_deferred()


func _populate_scenario_selector() -> void:
	_scenario_selector.clear()
	var rows = ScenarioDatabase.list_for_picker()
	if rows.is_empty():
		_scenario_selector.add_item("(No scenarios found)")
		return
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var id: int = row["id"]
		_scenario_selector.add_item("#%d %s" % [id, row["scenario_name"]])
		_scenario_selector.set_item_metadata(i, id)
		if id == DebugConfig.active_scenario_id:
			_scenario_selector.select(i)


func _on_scenario_selected(index: int) -> void:
	var id = _scenario_selector.get_item_metadata(index)
	if id == null:
		_scenario_selector.release_focus()
		return
	# Explicit pick — persist it (AUTOSAVE) so it sticks across an app restart, not
	# just a reload. (A bare `= id` would seed session-only; see DebugConfig.)
	DebugConfig.set_active_scenario_id(int(id))
	ScenarioLoader.apply_scenario(int(id), _procedural_map)
	_scenario_selector.release_focus()
