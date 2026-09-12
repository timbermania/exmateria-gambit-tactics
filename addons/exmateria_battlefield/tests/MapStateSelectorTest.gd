extends Node
## Tests for MapStateSelector — the ADR-0056 raw-int map-state selection.
##
## A scenario picks which GNS environment row (sky gradient + ambient + lights +
## palette) renders by matching its RAW weather index + night flag against the
## scene_manifest `states[]` — never by label (the scenario/GNS weather enums are
## offset by NoneAlt, so a label match would pick the wrong sky). This pins the
## selection: exact raw-int match, night-flag discrimination, INITIAL-default
## fallback on a weather/time miss, and the two empty cases.
##
## 🔴 THIS FILE IS ADDON-OWNED AND EVERY LEG IS SYNTHETIC. It moved here from
## `tests/` under ADR-0210 dec. 4, applying ADR-0194 / #652: it reaches nothing but
## `addons/exmateria_battlefield/assembly/MapStateSelector.gd`, so the host was
## naming an addon `class_name` it does not publish — `check_lattice_publish`
## arm 3, 8 sites, the largest row on the board after `Tile`. Inside the addon the
## same call is not a reach and the row is paid.
##
## The move was only available because the legs below build their own `states[]`
## with `_state()`. The SIXTH leg did not: it read a real scenario manifest, which
## is HOST content a stranger project does not have, and moving it here would have
## made it a permanent skip — a test that asserts nothing everywhere, which is
## ADR-0148's named failure and the exact defect the stranger rig caught in
## ADR-0208's own move commit. So that leg did NOT move: it stayed in the host as
## `tests/MapStateExportTest.gd`, re-expressed as a claim about the EXPORT rather
## than about the selector. The selection RULE is pinned here; that the shipped
## rows still carry the keys the rule reads is pinned there. Neither file can
## cover the other's half.
##
## Run: this file is run by `bash tests/stranger/exmateria_battlefield/run.sh`,
## which globs its addon's `tests/*.tscn`. ADR-0194 dec. 4 forbids running it as
## `res://tests/X.tscn` in the host project.

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const MapStateSelector = preload("res://addons/exmateria_battlefield/assembly/MapStateSelector.gd")


var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_exact_match()
	_test_night_flag_distinguishes()
	_test_weather_miss_falls_back_to_default()
	_test_empty_states()
	_test_missing_arrangement_returns_empty()

	print("\n=== MapStateSelectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 or _failed > 0:
		print("[FAIL] MapStateSelectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] MapStateSelectorTest")
		get_tree().quit(0)


func _state(arrangement: int, night: int, weather_raw: int, is_default: bool, top: int) -> Dictionary:
	# A synthetic states[] entry keyed by a distinguishable gradient top.
	return {
		"arrangement_id": arrangement,
		"night": night,
		"weather_raw": weather_raw,
		"default": is_default,
		"dir": ".",
		"palette_file": null,
		"lighting": {"gradient": {"top": {"r": top, "g": 0, "b": 0}}},
	}


func _top(state: Dictionary) -> int:
	return int(state["lighting"]["gradient"]["top"]["r"])


func _test_exact_match() -> void:
	var states := [
		_state(0, 0, 0, true, 10),
		_state(0, 0, 2, false, 20),
		_state(0, 0, 3, false, 30),
	]
	var got := MapStateSelector.select(states, 2, 0, 0)
	_assert(_top(got) == 20, "weather_raw=2 selects the wx2 row")


func _test_night_flag_distinguishes() -> void:
	# Same weather, different night flag → distinct rows.
	var states := [
		_state(0, 0, 2, true, 11),
		_state(0, 1, 2, false, 99),
	]
	_assert(_top(MapStateSelector.select(states, 2, 0, 0)) == 11, "day wx2 picks day row")
	_assert(_top(MapStateSelector.select(states, 2, 1, 0)) == 99, "night wx2 picks night row")


func _test_weather_miss_falls_back_to_default() -> void:
	# No wx=4 row → the ROM leaves the map-init default loaded (benign default sky).
	var states := [
		_state(0, 0, 0, true, 10),
		_state(0, 0, 2, false, 20),
	]
	var got := MapStateSelector.select(states, 4, 0, 0)
	_assert(_top(got) == 10, "unknown weather falls back to the INITIAL default row")


func _test_empty_states() -> void:
	_assert(MapStateSelector.select([], 2, 0, 0).is_empty(), "empty states → empty (use default lighting)")


func _test_missing_arrangement_returns_empty() -> void:
	# Requesting Secondary (1) when the map has only Primary rows must not
	# silently substitute a Primary sky — return empty and let the caller warn.
	var states := [_state(0, 0, 0, true, 10)]
	_assert(MapStateSelector.select(states, 0, 0, 1).is_empty(),
		"missing arrangement → empty (never a wrong-arrangement substitute)")


func _assert(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)
