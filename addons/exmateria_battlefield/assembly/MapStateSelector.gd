extends RefCounted

## Selects which GNS "map state" renders for a given scenario environment.
##
## A FFT map ships multiple (arrangement, time, weather) rows; each carries its
## own sky gradient + ambient + directional lights + palette. A scenario picks
## one by its RAW weather index and night flag (ADR-0056). Selection is by raw
## int, NEVER by label: the scenario weather enum (0 None, 1 Normal, 2 Strong…)
## and the GNS weather enum (0 None, 1 NoneAlt, 2 Normal…) are offset by the
## NoneAlt slot, so a label match would load the wrong sky. The exporter writes
## the authoritative raw keys onto each `scene_manifest.json` `states[]` entry:
## `weather_raw` (0-4), `night` (0/1), `arrangement_id` (0/1).
##
## Fallback is asymmetric (mirrors the ROM selector at 0x800f3f94):
##   * missing weather/time → the INITIAL default row (a benign default sky);
##   * missing arrangement → empty (the caller must warn — never silently render
##     a wrong-arrangement geometry/sky).
## Vault: [[Map Darkness Opcode]]
## Vault: [[Map State Selection]]


## Returns the `states[]` entry matching `(weather_raw, is_night, arrangement)`,
## or the INITIAL default entry on a weather/time miss, or an empty Dictionary
## when `states` is empty / the requested arrangement has no rows at all.
static func select(states: Array, weather_raw: int, is_night: int, arrangement: int = 0) -> Dictionary:
	if states.is_empty():
		return {}

	var in_arrangement: Array = []
	for s in states:
		if int(s.get("arrangement_id", 0)) == arrangement:
			in_arrangement.append(s)
	if in_arrangement.is_empty():
		push_error("[MapStateSelector] no map state for arrangement %d — refusing to substitute a wrong-arrangement sky" % arrangement)
		return {}

	# Exact raw-int match on weather + night (the authoritative key).
	for s in in_arrangement:
		if int(s.get("weather_raw", 0)) == weather_raw and int(s.get("night", 0)) == is_night:
			return s

	# No weather/time match: leave the map-init default loaded, like the ROM.
	for s in in_arrangement:
		if bool(s.get("default", false)):
			return s
	return in_arrangement[0]
