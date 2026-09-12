extends RefCounted

## Database for FFT job prerequisites and JP requirements
##
## Loads job level data from jobs/job_levels.json and provides
## methods for checking job unlock requirements.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const JOB_LEVELS_PATH := "res://addons/exmateria_almanac/jobs/job_levels.json"

# Cached data
static var _prerequisites: Dictionary = {}  # {job_id: {required_job_id: required_level}}
static var _jp_requirements: Array = []     # JP needed for each level [0]=Lv1, [7]=Lv8
static var _job_name_to_id: Dictionary = {} # {name: job_id}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	"""Load job level data if not already loaded."""
	if _loaded:
		return
	var data := JsonAsset.load_dict(JOB_LEVELS_PATH)
	_prerequisites = data.get("prerequisites", {})
	_jp_requirements = data.get("jp_requirements", [])
	_job_name_to_id = data.get("job_name_to_id", {})
	_loaded = true


static func get_jp_for_level(level: int) -> int:
	"""Get the JP required to reach a specific job level.

	Args:
		level: Job level (1-8)

	Returns:
		JP required, or 0 if level is invalid
	"""
	_ensure_loaded()
	var index = level - 1
	if index < 0 or index >= _jp_requirements.size():
		return 0
	return _jp_requirements[index]


static func get_job_level_from_jp(jp: int) -> int:
	"""Calculate job level based on accumulated JP.

	Args:
		jp: Total JP earned in this job

	Returns:
		Job level (1-8)
	"""
	_ensure_loaded()
	var level = 1
	for i in range(_jp_requirements.size()):
		if jp >= _jp_requirements[i]:
			level = i + 1
		else:
			break
	return level


static func get_prerequisites(job_id: String) -> Dictionary:
	"""Get prerequisites for a job.

	Args:
		job_id: Job ID as hex string (e.g., '4c' for Knight)

	Returns:
		Dictionary of {required_job_id: required_level}, empty if no prereqs
	"""
	_ensure_loaded()
	return _prerequisites.get(job_id.to_lower(), {})


static func is_job_unlocked(job_id: String, job_levels: Dictionary) -> bool:
	"""Check if a job is unlocked based on current job levels.

	Args:
		job_id: Job ID to check (e.g., '4c' for Knight)
		job_levels: Dictionary of {job_id: current_level} for the unit

	Returns:
		True if all prerequisites are met
	"""
	_ensure_loaded()
	var prereqs = get_prerequisites(job_id)

	# No prerequisites means always unlocked (Squire, Chemist)
	if prereqs.is_empty():
		return true

	# Check each prerequisite
	for required_job_id in prereqs:
		var required_level = prereqs[required_job_id]
		var current_level = job_levels.get(required_job_id, 0)
		if current_level < required_level:
			return false

	return true


static func get_missing_prerequisites(job_id: String, job_levels: Dictionary) -> Array:
	"""Get list of prerequisites not yet met for a job.

	Args:
		job_id: Job ID to check
		job_levels: Dictionary of {job_id: current_level} for the unit

	Returns:
		Array of strings like ["Squire Lv2", "Knight Lv3"]
	"""
	_ensure_loaded()
	var missing: Array = []
	var prereqs = get_prerequisites(job_id)

	for required_job_id in prereqs:
		var required_level = prereqs[required_job_id]
		var current_level = job_levels.get(required_job_id, 0)
		if current_level < required_level:
			var job_name = get_job_name(required_job_id)
			missing.append("%s Lv%d (have Lv%d)" % [job_name, required_level, current_level])

	return missing


static func get_job_name(job_id: String) -> String:
	"""Get job name from ID.

	Args:
		job_id: Job ID as hex string

	Returns:
		Job name or "Unknown" if not found
	"""
	_ensure_loaded()
	for name in _job_name_to_id:
		if _job_name_to_id[name] == job_id.to_lower():
			return name
	return "Unknown"


static func get_all_generic_job_ids() -> Array:
	"""Get all generic job IDs in order.

	Returns:
		Array of job IDs from Squire (4a) to Mime (5d)
	"""
	_ensure_loaded()
	var ids: Array = []
	for offset in range(0x4A, 0x5E):
		ids.append("%02x" % offset)
	return ids


static func reload() -> void:
	"""Force reload of job level data (for debugging)."""
	_loaded = false
	_prerequisites = {}
	_jp_requirements = []
	_job_name_to_id = {}
	_ensure_loaded()
