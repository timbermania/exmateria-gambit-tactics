extends RefCounted

## Database for FFT base stats by unit type
##
## Loads base stat values from progression/base_stats.json.
## Base stats are starting raw values for HP/MP/Speed/PA/MA.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const BASE_STATS_PATH := "res://addons/exmateria_almanac/progression/base_stats.json"

# Cached data
static var _base_stats: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	"""Load base stats data if not already loaded."""
	if _loaded:
		return
	_base_stats = JsonAsset.load_dict(BASE_STATS_PATH, "base_stats")
	_loaded = true


static func get_base_stat(stat_type: String, stat_name: String) -> int:
	"""Get a specific base stat value.

	Args:
		stat_type: 'male', 'female', or 'monster'
		stat_name: 'hp', 'mp', 'speed', 'pa', or 'ma'

	Returns:
		Raw stat value (× 16384), or 0 if not found
	"""
	_ensure_loaded()
	var stats = _base_stats.get(stat_type.to_lower(), {})
	return stats.get(stat_name.to_lower(), 0)


static func reload() -> void:
	"""Force reload of base stats (for debugging)."""
	_loaded = false
	_base_stats = {}
	_ensure_loaded()
