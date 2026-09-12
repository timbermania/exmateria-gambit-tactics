extends RefCounted

## Database for FFT job definitions
##
## Loads job data from jobs/jobs.json and provides lookup methods.
## Job data includes stat modifiers, equipment flags, and elemental properties.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
# ADR-0202 dec. 2 / ADR-0280 dec. 3 — `UnitRole` is the SHARED KERNEL's, not this
# addon's: ADR-0118 dec. 1's eleventh schema row, reached through the kernel's
# facade rather than by path because a `res://` literal leaving this addon root
# is arm 6 and this addon's arm-6 burn-down is EMPTY. Every reach INTO the
# kernel is free. `plugin.cfg`'s `deps=` declares it so the stranger rig stages
# it (#1159).
const UnitRole = ExMateriaSchema.UnitRole

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const JOBS_PATH := "res://addons/exmateria_almanac/jobs/jobs.json"

# Cached job data
static var _jobs: Dictionary = {}
static var _jp_requirements: Array = []
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	"""Load job data if not already loaded."""
	if _loaded:
		return
	var data := JsonAsset.load_dict(JOBS_PATH)
	_jobs = data.get("jobs", {})
	_jp_requirements = data.get("metadata", {}).get("jp_requirements", [])
	_loaded = true


static func all_job_ids() -> Array:
	"""Every job id in the database (hex strings), in load order.

	Data-derived — the keys of the parsed jobs.json, no hardcoded range. Lets
	callers enumerate jobs (e.g. the catalogue's monster-variant source) without
	guessing an id span or duplicating the load.
	"""
	_ensure_loaded()
	return _jobs.keys()


static func get_job(job_id: String) -> Dictionary:
	"""Get job data by ID (hex string, e.g., '4a' for Squire).

	Args:
		job_id: Job offset as lowercase hex string (e.g., '4a', '4c')

	Returns:
		Dictionary with job properties, or empty dict if not found
	"""
	_ensure_loaded()
	return _jobs.get(job_id.to_lower(), {})


static func is_monster(job_id: String) -> bool:
	"""True if the job is a monster (parser-derived; see ADR-0013).

	Args:
		job_id: Job ID as hex string (e.g., '4a', '5e')

	Returns:
		True if the job's parser-emitted `kind` is "monster".
	"""
	_ensure_loaded()
	return _jobs.get(job_id.to_lower(), {}).get("kind", "") == "monster"


static func is_generic_human(job_id: String) -> bool:
	"""True if the job is a generic HUMAN job (parser-derived `kind`; ADR-0013).

	The sibling of [is_monster] on the same parser-emitted axis. This is the test
	that decides whether a body sheet belongs to the **generic wardrobe** — the one
	population whose appearance is a function of `job` (ADR-0072 dec.1), and so the
	one population that must NOT carry an appearance-type `template_token`
	(ADR-0081 dec. 8).

	Args:
		job_id: Job ID as hex string (e.g., '4a', '4c')

	Returns:
		True if the job's parser-emitted `kind` is "generic_human".
	"""
	_ensure_loaded()
	return _jobs.get(job_id.to_lower(), {}).get("kind", "") == "generic_human"


static func generic_wardrobe_sprite_ids() -> Dictionary:
	"""The set of body sprite ids reachable by a **generic human job**, as a
	`{int sprite_id: true}` set — the mechanized form of ADR-0081
	dec. 8's appearance-type test (job-reachability).

	Data-derived from the job tables (both gender keys of every `generic_human`
	job), never a hardcoded sprite-id range — the same discipline as
	`CharacterTemplateResolver._has_gender_axis`. A sheet in this set is the
	wardrobe of a job; a sheet outside it that no other job reaches is an
	[appearance-type].
	"""
	_ensure_loaded()
	if not _wardrobe_sprites.is_empty():
		return _wardrobe_sprites
	for job_id in _jobs.keys():
		if not is_generic_human(job_id):
			continue
		_wardrobe_sprites[get_sprite_id(job_id, false)] = true
		_wardrobe_sprites[get_sprite_id(job_id, true)] = true
	return _wardrobe_sprites

## Cache for [generic_wardrobe_sprite_ids] — the job tables are immutable at runtime.
static var _wardrobe_sprites: Dictionary = {}


static func get_all_generic_jobs() -> Dictionary:
	"""Get all generic (player-usable) jobs.

	Returns:
		Dictionary mapping job_id to job data for jobs 0x4A-0x5D
	"""
	_ensure_loaded()
	var result = {}
	for offset in range(0x4A, 0x5E):
		var job_id = "%02x" % offset
		if _jobs.has(job_id):
			result[job_id] = _jobs[job_id]
	return result


static func reload() -> void:
	"""Force reload of job data (for debugging)."""
	_loaded = false
	_jobs = {}
	_jp_requirements = []
	_ensure_loaded()
	# The Learn picker's catalogue is memoized off this data — drop it or the picker keeps
	# listing the pre-reload jobs. (This is the only path that can change the answer.)
	#
	# ADR-0251 dec. 3 — `load()` here, NOT a class-level `const … = preload(…)`.
	# `JobCandidates.gd` preloads THIS file, so a const preload the other way is a
	# cyclic reference the parser rejects, and it is the only cycle in the addon's
	# 15-edge internal graph. This is the debug-only reload path; the cost is one
	# cached `ResourceLoader` hit on a call that already re-reads the whole table.
	var JobCandidatesCls := load("res://addons/exmateria_almanac/jobs/JobCandidates.gd")
	JobCandidatesCls.clear_cache()


## Job ID to combat role mapping
## Based on FFT generic jobs (0x4A-0x5D)
const JOB_ROLES := {
	# MELEE: Close combat fighters
	"4c": UnitRole.Role.MELEE,  # Knight
	"4e": UnitRole.Role.MELEE,  # Monk
	"55": UnitRole.Role.MELEE,  # Lancer
	"57": UnitRole.Role.MELEE,  # Samurai
	"59": UnitRole.Role.MELEE,  # Ninja

	# RANGED: Distance attackers
	"4d": UnitRole.Role.RANGED,  # Archer
	"52": UnitRole.Role.RANGED,  # Thief

	# MAGE: Offensive spellcasters
	"4f": UnitRole.Role.MAGE,    # Priest (also heals, but primary is white magic)
	"50": UnitRole.Role.MAGE,    # Wizard
	"51": UnitRole.Role.MAGE,    # Time Mage
	"56": UnitRole.Role.MAGE,    # Summoner

	# HEALER: Support/healing
	"4b": UnitRole.Role.HEALER,  # Chemist

	# HYBRID: Mixed roles
	"4a": UnitRole.Role.HYBRID,  # Squire
	"53": UnitRole.Role.HYBRID,  # Oracle
	"54": UnitRole.Role.HYBRID,  # Geomancer
	"58": UnitRole.Role.HYBRID,  # Mediator
	"5a": UnitRole.Role.HYBRID,  # Calculator
	"5b": UnitRole.Role.HYBRID,  # Bard
	"5c": UnitRole.Role.HYBRID,  # Dancer
	"5d": UnitRole.Role.HYBRID,  # Mime
}


static func get_job_role(job_id: String) -> UnitRole.Role:
	"""Get the combat role for a job.

	Args:
		job_id: Job ID as hex string (e.g., '4a', '4c')

	Returns:
		UnitRole.Role for the job, or HYBRID if unknown
	"""
	var lower_id = job_id.to_lower()
	if JOB_ROLES.has(lower_id):
		return JOB_ROLES[lower_id]

	# Default to HYBRID for unknown jobs (monsters, special units, etc.)
	return UnitRole.Role.HYBRID


static func get_sprite_id(job_id: String, is_female: bool = false) -> int:
	"""Look up the body sprite ID for a job (parser-derived; ADR-0013).

	The FFT sprite layout (0x4A/0x5A/0x5B special-case formula etc.) is
	resolved at extract time in `tools/extract_fft_data.py`; this is a
	flat dict read with no byte-boundary arithmetic.

	Args:
		job_id: Job ID as hex string (e.g., '4a')
		is_female: True for female variant. Only generic humans (and Mime)
			have distinct M/F sprites; for everything else both keys hold
			the same value.

	Returns:
		Sprite file ID (e.g., 0x60 for Male Squire, 0x34 for Agrias).
	"""
	_ensure_loaded()
	var job = _jobs.get(job_id.to_lower(), {})
	var key = "body_sprite_id_female" if is_female else "body_sprite_id_male"
	return job.get(key, 0)


static func get_sprite_name(sprite_id: int) -> String:
	"""Get the name of a sprite file by ID.

	Args:
		sprite_id: Sprite file ID (e.g., 0x60, 0x94)

	Returns:
		Sprite name or "Unknown" if not found
	"""
	return SPRITE_NAMES.get(sprite_id, "Unknown (0x%02X)" % sprite_id)


# Sprite file names from FFTPatcher SpriteFiles.xml
const SPRITE_NAMES := {
	0x00: "(None)",
	0x01: "Ramza Ch1", 0x02: "Ramza Ch2/3", 0x03: "Ramza Ch4",
	0x04: "Delita Ch1", 0x05: "Delita Ch2/3", 0x06: "Delita Ch4",
	0x07: "Algus", 0x08: "Zalbag", 0x09: "Dycedarg",
	0x0A: "Larg", 0x0B: "Goltana", 0x0C: "Ovelia",
	0x0D: "Orlandu", 0x0E: "High Priest", 0x0F: "Reis (Human)",
	0x10: "Zalmo", 0x11: "Gafgarion", 0x12: "Malak",
	0x13: "Simon", 0x14: "Alma", 0x15: "Olan",
	0x16: "Mustadio", 0x17: "Gafgarion (Guest)", 0x18: "Draclau",
	0x19: "Rafa", 0x1A: "Malak (Enemy)", 0x1B: "Elmdor",
	0x1C: "Teta", 0x1D: "Barinten", 0x1E: "Agrias",
	0x1F: "Beowulf", 0x20: "Wiegraf Ch1", 0x21: "Balmafula",
	0x22: "Mustadio (Guest)", 0x23: "Rudvich", 0x24: "Vormav",
	0x25: "Rofel", 0x26: "Izlude", 0x27: "Kletian",
	0x28: "Wiegraf Ch2/3", 0x29: "Rafa (Join)", 0x2A: "Meliadoul",
	0x2B: "Balk", 0x2C: "Alma (Dead)", 0x2D: "Celia",
	0x2E: "Lede", 0x2F: "Meliadoul (Enemy)", 0x30: "Alma (Events)",
	0x31: "Ajora", 0x32: "Cloud", 0x33: "Zalbag (Zombie)",
	0x34: "Agrias (Guest)",
	0x3C: "Velius", 0x3D: "Undead Knight", 0x3E: "Zalera",
	0x40: "Hashmalum", 0x41: "Altima", 0x43: "Queklain",
	0x45: "Adramelk", 0x48: "Holy Dragon", 0x49: "Altima (2nd)",
	# Generic human sprites
	0x60: "Male Squire", 0x61: "Female Squire",
	0x62: "Male Chemist", 0x63: "Female Chemist",
	0x64: "Male Knight", 0x65: "Female Knight",
	0x66: "Male Archer", 0x67: "Female Archer",
	0x68: "Male Monk", 0x69: "Female Monk",
	0x6A: "Male Priest", 0x6B: "Female Priest",
	0x6C: "Male Wizard", 0x6D: "Female Wizard",
	0x6E: "Male Time Mage", 0x6F: "Female Time Mage",
	0x70: "Male Summoner", 0x71: "Female Summoner",
	0x72: "Male Thief", 0x73: "Female Thief",
	0x74: "Male Mediator", 0x75: "Female Mediator",
	0x76: "Male Oracle", 0x77: "Female Oracle",
	0x78: "Male Geomancer", 0x79: "Female Geomancer",
	0x7A: "Male Lancer", 0x7B: "Female Lancer",
	0x7C: "Male Samurai", 0x7D: "Female Samurai",
	0x7E: "Male Ninja", 0x7F: "Female Ninja",
	0x80: "Male Calculator", 0x81: "Female Calculator",
	0x82: "Male Bard", 0x83: "Female Dancer",
	0x84: "Male Mime", 0x85: "Female Mime",
	# Monster sprites
	0x86: "Chocobo", 0x87: "Goblin", 0x88: "Bomb",
	0x89: "Coeurl", 0x8A: "Squid", 0x8B: "Skeleton",
	0x8C: "Ghost", 0x8D: "Ahriman", 0x8E: "Cockatrice",
	0x8F: "Uribo", 0x90: "Treant", 0x91: "Minotaur",
	0x92: "Malboro", 0x93: "Behemoth", 0x94: "Dragon",
	0x95: "Tiamat", 0x96: "Apanda/Byblos", 0x97: "Elidibs",
	0x98: "Dragon (Holy)", 0x99: "Demon", 0x9A: "Steel Giant"
}
