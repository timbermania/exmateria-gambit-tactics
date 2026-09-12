extends RefCounted

## Database for FFT ENTD enemy START positions.
##
## Loads encounters/entd_positions.json at first use and serves a record's
## enemy positions by entd_idx (a scenario's entd_idx points here). The JSON is
## a [committed extracted artifact](../../docs/context/12-strategy-phase.md) emitted by
## `tools/parse_placement.py` from BATTLE/ENTD{1..4}.ENT — the positions of the
## non-player-controlled units. Pure data, the same XDatabase shape as
## ScenarioDatabase.
##
## Each enemy carries `x`, `y`, `upper_level`, `facing`, and `team_color`. These
## are enemy SPAWN tiles: enemies auto-fill onto them, then march to a contested
## objective (ADR-0043 addendum). `team_color == 1` is red (true enemy); other
## colors among the non-player-controlled set are AI guests — prefer red when
## clamping to the enemy roster size.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const ENTD_PATH := "res://addons/exmateria_almanac/encounters/entd_positions.json"

const TEAM_COLOR_RED := 1  ## the "real enemy" color; others (e.g. blue) are guests

static var _entds: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_entds = JsonAsset.load_dict(ENTD_PATH, "entds")
	_loaded = true


## All non-player-controlled enemy positions for an entd_idx (in ENTD slot
## order). Returns [] if the index is missing or carries no enemies.
static func get_enemies(idx: int) -> Array:
	_ensure_loaded()
	var rec: Dictionary = _entds.get(str(idx), {})
	return rec.get("enemies", [])


## Enemy positions ordered so red (true enemies) come before guests, then by
## slot order. Use with a clamp (take the first N) to prefer real enemies over
## AI guests when the ENTD count exceeds the enemy roster size.
static func get_enemies_red_first(idx: int) -> Array:
	var enemies := get_enemies(idx)
	var red: Array = []
	var other: Array = []
	for e in enemies:
		if int(e.get("team_color", -1)) == TEAM_COLOR_RED:
			red.append(e)
		else:
			other.append(e)
	return red + other


## True if this entd_idx carries at least one enemy position.
static func has_enemies(idx: int) -> bool:
	return not get_enemies(idx).is_empty()


## Force reload (debugging / hot edits).
static func reload() -> void:
	_loaded = false
	_entds = {}
	_ensure_loaded()
