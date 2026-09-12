@tool
class_name UIActionAbilityPopup
extends UIListModalWindow
## Action ability selection popup for combat/gambit ability selection.
##
## Shows abilities with MP, CT, and Range columns (no JP). Filters to abilities
## the unit has learned AND are available in their current job or sub-job.

## Emitted when an action ability is selected

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const AbilityView = ExMateriaAlmanac.AbilityView
const JobDatabase = ExMateriaAlmanac.JobDatabase

signal action_selected(ability_id: int)


## Row type — carries pre-formatted display strings for each stat column. Raw
## values are intentionally absent: `_on_picked` only reads `id`, and column
## rendering reads the already-formatted text (data, not code — same discipline
## as ADR-0016's gambit encode schema). Pre-formatting happens once in
## `build_rows`, not per virtual-scroll factory call.
class ActionRow:
	extends RefCounted
	var id: int
	var name: String
	var mp_text: String     # pre-formatted: "MP:5" or "" when 0
	var ct_text: String     # pre-formatted: "CT:5" or "" when 0
	var range_text: String  # pre-formatted: "Rng:3" or "" when 0

	func _init(p_id: int = -1, p_name: String = "",
			p_mp_text: String = "", p_ct_text: String = "",
			p_range_text: String = "") -> void:
		id = p_id
		name = p_name
		mp_text = p_mp_text
		ct_text = p_ct_text
		range_text = p_range_text


## Subclass-specific defaults
const _ACTION_DEFAULTS = {
	"mp_offset_x": 100.0,
	"ct_offset_x": 130.0,
	"range_offset_x": 160.0,
	"stat_scale": 0.7,
	"stat_palette": 0,
}


const _COLUMNS = [
	{ "child": &"NameText",  "field": &"name" },
	{ "child": &"MPText",    "field": &"mp_text",
	  "offset_x_prop": &"mp_offset_x",
	  "scale_prop":    &"stat_scale",
	  "palette_prop":  &"stat_palette",
	  "hide_when_empty": true },
	{ "child": &"CTText",    "field": &"ct_text",
	  "offset_x_prop": &"ct_offset_x",
	  "scale_prop":    &"stat_scale",
	  "palette_prop":  &"stat_palette",
	  "hide_when_empty": true },
	{ "child": &"RangeText", "field": &"range_text",
	  "offset_x_prop": &"range_offset_x",
	  "scale_prop":    &"stat_scale",
	  "palette_prop":  &"stat_palette",
	  "hide_when_empty": true },
]

#region Configuration Exports

@export_group("Action Display")

## MP text offset from ability name (X position in virtual pixels)
@export var mp_offset_x: float = 100.0:
	set(value):
		if mp_offset_x == value:
			return
		mp_offset_x = value
		_mark_layout_dirty()

## CT text offset
@export var ct_offset_x: float = 130.0:
	set(value):
		if ct_offset_x == value:
			return
		ct_offset_x = value
		_mark_layout_dirty()

## Range text offset
@export var range_offset_x: float = 160.0:
	set(value):
		if range_offset_x == value:
			return
		range_offset_x = value
		_mark_layout_dirty()

## Stats text scale
@export var stat_scale: float = 0.7:
	set(value):
		if stat_scale == value:
			return
		stat_scale = value
		_mark_layout_dirty()

## Stats text palette (0 = MENU to match equipment)
@export var stat_palette: int = 0:
	set(value):
		if stat_palette == value:
			return
		stat_palette = value
		_mark_layout_dirty()

#endregion

#region Internal State

var _current_unit: Node = null

#endregion


## Show action abilities for a unit, filtered by learned + job/subjob.
func show_for_unit(unit: Node, world_position: Vector3 = Vector3.ZERO) -> void:
	_current_unit = unit
	_open_with_rows(build_rows(unit), "Select Action", world_position)


func build_rows(unit: Node) -> Array:
	var rows: Array = []
	var abilities := _get_available_action_abilities(unit)
	for ability in abilities:
		var mp := ability.mp_cost
		var ct := ability.ct
		var rng := ability.range
		rows.append(ActionRow.new(
			ability.ability_id,
			ability.name if not ability.name.is_empty() else "???",
			"MP:%d" % mp if mp > 0 else "",
			"CT:%d" % ct if ct > 0 else "",
			"Rng:%d" % rng if rng > 0 else "",
		))
	return rows


func _get_available_action_abilities(unit: Node) -> Array[AbilityView]:
	var result: Array[AbilityView] = []

	if not unit:
		# No unit — return all Normal abilities for preview
		if AbilityDatabase:
			return AbilityDatabase.get_views_by_type("Normal")
		return result

	var progression = unit.get_node_or_null("UnitProgression")
	if not progression:
		return result

	var learned: Dictionary = progression.learned_abilities if "learned_abilities" in progression else {}

	var job_abilities = _get_action_abilities_from_job(progression.current_job_id)
	var subjob_abilities: Array = []
	if progression.sub_job_id != "":
		subjob_abilities = _get_action_abilities_from_job(progression.sub_job_id)

	# Current job abilities are always available (no learn check needed)
	for ability_id in job_abilities:
		if not AbilityDatabase:
			continue
		var view := AbilityDatabase.get_ability_view(ability_id)
		if not view.is_empty():
			result.append(view)

	# Sub-job abilities require learning first
	for ability_id in subjob_abilities:
		if learned.has(ability_id):
			if not AbilityDatabase:
				continue
			var view := AbilityDatabase.get_ability_view(ability_id)
			if not view.is_empty() and ability_id not in job_abilities:
				result.append(view)

	result.sort_custom(func(a: AbilityView, b: AbilityView): return a.name < b.name)
	return result


func _get_action_abilities_from_job(job_id: String) -> Array:
	if job_id.is_empty() or not JobDatabase:
		return []
	var job = JobDatabase.get_job(job_id)
	if not job:
		return []
	var skill_set_id = int(job.get("skill_set_id", 0))
	if not AbilityDatabase:
		return []
	var skill_set = AbilityDatabase.get_skill_set(skill_set_id)
	return skill_set.get("actions", [])


func _on_picked(row: Variant) -> void:
	var ar := row as ActionRow
	if ar:
		action_selected.emit(ar.id)


func _columns() -> Array:
	return _COLUMNS


func _preview_rows() -> Array:
	return build_rows(null)


## Override to include action-specific defaults in sync check
func _get_all_defaults() -> Dictionary:
	var defaults = super._get_all_defaults()
	defaults.merge(_ACTION_DEFAULTS)
	return defaults
