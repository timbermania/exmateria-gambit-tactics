@tool
class_name UIJobPopup
extends UIListModalWindow
## Job selection popup showing available jobs.
##
## Simple name-only list. The first option may be "---" to clear the sub-job.

## Emitted when a job is selected (id is "" when the clear option was picked)

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase

signal job_selected(job_id: String)


## Row type — note that JobRow.id is a String (job_id like "4a"), whereas
## ability pickers use int ids. The typed row keeps this distinction local.
class JobRow:
	extends RefCounted
	var id: String
	var name: String

	func _init(p_id: String = "", p_name: String = "") -> void:
		id = p_id
		name = p_name


const _COLUMNS = [
	{ "child": &"NameText", "field": &"name" },
]


#region Internal State

var _for_sub_job: bool = false

#endregion


## Show jobs for selection.
## If `for_sub_job` is true, includes a "---" option to clear the sub-job.
func show_jobs(for_sub_job: bool = false, world_position: Vector3 = Vector3.ZERO) -> void:
	_for_sub_job = for_sub_job
	var title := "Select Sub-Job" if for_sub_job else "Select Job"
	_open_with_rows(build_rows(for_sub_job), title, world_position)


## Build the typed row list. Public so the editor preview path and runtime path
## share one implementation.
func build_rows(for_sub_job: bool) -> Array:
	var rows: Array = []

	if for_sub_job:
		rows.append(JobRow.new("", "---"))

	if JobDatabase:
		var jobs = JobDatabase.get_all_generic_jobs()
		var temp: Array[JobRow] = []
		for job_id in jobs:
			var job = jobs[job_id]
			temp.append(JobRow.new(job_id, job.get("name", "Unknown")))
		temp.sort_custom(func(a, b): return a.name < b.name)
		for r in temp:
			rows.append(r)

	return rows


func _on_picked(row: Variant) -> void:
	var jr := row as JobRow
	if jr:
		job_selected.emit(jr.id)


func _columns() -> Array:
	return _COLUMNS


func _preview_rows() -> Array:
	return build_rows(false)
