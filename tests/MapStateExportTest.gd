extends Node
## The MAP056 half of what `MapStateSelectorTest` used to be — a claim about the
## shipped EXPORT, not about the selector.
##
## 🔴 WHY THIS FILE EXISTS AT ALL. `MapStateSelectorTest` moved into
## `addons/exmateria_battlefield/tests/` under ADR-0210 dec. 4 (applying ADR-0194 /
## #652) to pay `check_lattice_publish` arm 3's 8-site `MapStateSelector` row. Five
## of its six legs build their own synthetic `states[]` and moved cleanly. THE
## SIXTH READ REAL HOST CONTENT, and an addon-owned test is run only by
## `tests/stranger/exmateria_battlefield/run.sh`, in a project that has no content
## root — so moving it would have turned a real assertion into a permanent `[SKIP]`.
## A test that asserts nothing everywhere is ADR-0148's named failure and is the
## defect the stranger rig caught in ADR-0208's own move commit, so the leg stayed
## behind rather than travelling to a place it could not run.
##
## 🔴 AND IT IS RE-EXPRESSED, not copied, because copying it would have left the
## `MapStateSelector` row at 2 sites instead of 0 and paid nothing. The subject
## here is the EXPORT: `MapStateSelector.select` reads `arrangement_id`, `night`,
## `weather_raw` and `default` off each `states[]` row (ADR-0056, mirroring the ROM
## selector at 0x800f3f94), so this asserts that the shipped MAP056 rows still
## CARRY those keys with the values scenario 4 depends on. The selection RULE that
## consumes them is pinned by the five synthetic legs in the addon. Neither file
## can cover the other's half: the addon's legs would pass against a stale export,
## and this one would pass against a broken selector.
##
## Asset-gated: MAP056 is ROM-derived content (`SETUP.md`), absent in a fresh
## clone. Absence is a `[SKIP]`, and the skip is PRINTED and counted so a run that
## checked nothing does not read like a run that checked something.
##
## Run: "$GODOT" --path . res://tests/MapStateExportTest.tscn

const MAP056_MANIFEST := "res://assets/maps/MAP056/scene_manifest.json"

## Scenario 4 (MAP056, weather_raw=2, day, arrangement 0) renders the NORMAL
## overcast grey, not the default cyan. The two colours are the driving case
## ADR-0056 was written for.
const NORMAL_SKY_TOP := Vector3i(135, 138, 149)
const DEFAULT_SKY_TOP_R := 160

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0


func _ready() -> void:
	_test_map056_states_carry_the_raw_keys()

	print("\n=== MapStateExportTest: %d passed, %d failed, %d skipped ==="
		% [_passed, _failed, _skipped])
	if _failed > 0 or (_passed == 0 and _skipped == 0):
		print("[FAIL] MapStateExportTest")
		get_tree().quit(1)
	else:
		print("[PASS] MapStateExportTest")
		get_tree().quit(0)


func _test_map056_states_carry_the_raw_keys() -> void:
	var f := FileAccess.open(MAP056_MANIFEST, FileAccess.READ)
	if f == null:
		_skipped += 1
		print("  [SKIP] MAP056 scene_manifest not present — ROM-derived content, see SETUP.md")
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var states: Array = data.get("states", [])
	if states.is_empty():
		_assert(false, "MAP056 scene_manifest has states[] (stale export?)")
		return

	# Every row must carry the four authoritative raw keys the selector matches on.
	# A row missing one reads as `0` through `Dictionary.get(k, 0)` and would be
	# silently selected as the day/None/Primary row.
	var complete := true
	for s in states:
		for key in ["arrangement_id", "night", "weather_raw", "default"]:
			if not (s as Dictionary).has(key):
				complete = false
	_assert(complete, "every MAP056 states[] row carries arrangement_id/night/weather_raw/default")

	var normal := _row_for(states, 2, 0, 0)
	_assert(not normal.is_empty(), "MAP056 exports an arrangement-0 day row at weather_raw=2")
	if not normal.is_empty():
		var top: Dictionary = normal["lighting"]["gradient"]["top"]
		_assert(Vector3i(int(top["r"]), int(top["g"]), int(top["b"])) == NORMAL_SKY_TOP,
			"MAP056 weather_raw=2 day → NORMAL sky %s, got (%d,%d,%d)"
			% [NORMAL_SKY_TOP, int(top["r"]), int(top["g"]), int(top["b"])])

	# The INITIAL default row is the fallback the selector lands on for an
	# unexported weather — the cyan we were wrongly always rendering before ADR-0056.
	var fallback := _row_for(states, 0, 0, 0)
	_assert(not fallback.is_empty(), "MAP056 exports an arrangement-0 day row at weather_raw=0")
	if not fallback.is_empty():
		var dtop: Dictionary = fallback["lighting"]["gradient"]["top"]
		_assert(int(dtop["r"]) == DEFAULT_SKY_TOP_R,
			"MAP056 default (weather 0) sky is the (160,232,239) cyan, got r=%d" % int(dtop["r"]))


## The exact-match half of the selector's rule, spelled against the DATA. This is
## deliberately not the fallback ladder: a fallback here would let a MISSING wx=2
## row pass by resolving to the default, which is the export defect this file is
## for.
func _row_for(states: Array, weather_raw: int, night: int, arrangement: int) -> Dictionary:
	for s in states:
		var row: Dictionary = s
		if (int(row.get("arrangement_id", -1)) == arrangement
				and int(row.get("night", -1)) == night
				and int(row.get("weather_raw", -1)) == weather_raw):
			return row
	return {}


func _assert(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)
