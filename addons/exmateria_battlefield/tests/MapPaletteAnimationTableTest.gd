extends Node
## Pure-logic guard (no GPU/scene): PaletteAnimationTable.build lays a map manifest's
## `animations.palette_animations` out PER PALETTE ID, so heterogeneous entries keep their
## own frame range, rate and mode.
##
## THE RED FIXTURE IS MAP009 (Citadel of Igros), verbatim from its manifest:
##
##     palette 2  start 0  3 frames  duration 15  ForwardAndReverseLooping
##     palette 5  start 3  4 frames  duration  9  ForwardLooping
##     palette 7  start 7  4 frames  duration  9  ForwardLooping
##
## The predecessor, `DynamicGeometryBuilder._get_palette_animation_config()`, collapsed
## these to min..max as a contiguous RANGE with `palette_animations[0]`'s parameters, on
## the stated assumption that "all entries typically share same animation_start_index,
## frame_count, frame_duration". That is false for 16 of the 18 multi-entry maps in the
## corpus. For MAP009 it animated palettes 3, 4 and 6 (which have no animation at all) and
## made 5 and 7 sample palette 2's rows. Every assertion below fails under that collapse.
##
## Run: bash tests/stranger/exmateria_battlefield/run.sh   (ADR-0194 — addon-owned, runs
## in a STRANGER project. Directly: "$GODOT" --path . --quit-after 5
## res://addons/exmateria_battlefield/tests/MapPaletteAnimationTableTest.tscn)


const PaletteAnimationTable = preload("res://addons/exmateria_battlefield/texturing/PaletteAnimationTable.gd")

# MAP009's animations.palette_animations, verbatim.
const MAP009_ANIMS: Array = [
	{"overridden_palette_id": 2, "animation_start_index": 0, "frame_count": 3,
		"frame_duration": 15, "animation_mode": "ForwardAndReverseLooping"},
	{"overridden_palette_id": 5, "animation_start_index": 3, "frame_count": 4,
		"frame_duration": 9, "animation_mode": "ForwardLooping"},
	{"overridden_palette_id": 7, "animation_start_index": 7, "frame_count": 4,
		"frame_duration": 9, "animation_mode": "ForwardLooping"},
]

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_each_entry_keeps_its_own_schedule()
	_test_gaps_in_the_id_set_do_not_animate()
	_test_no_animations_is_an_inert_table()
	_test_trigger_modes_do_not_free_run()
	_test_duplicate_palette_id_last_wins()
	_test_out_of_range_and_empty_entries_are_ignored()

	print("\n=== MapPaletteAnimationTableTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] MapPaletteAnimationTableTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] MapPaletteAnimationTableTest")
		get_tree().quit(1)
	else:
		print("[PASS] MapPaletteAnimationTableTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _assert(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _assert_eq(got: Variant, want: Variant, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


## Assert palette `pid`'s whole schedule at once.
func _assert_schedule(table: Dictionary, pid: int, start: int, count: int,
		duration: float, mode: int, name: String) -> void:
	_assert_eq(table["start"][pid], start, "%s: start" % name)
	_assert_eq(table["count"][pid], count, "%s: frame count" % name)
	_assert_eq(table["duration"][pid], duration, "%s: frame duration" % name)
	_assert_eq(table["mode"][pid], mode, "%s: mode" % name)


# --- tests -------------------------------------------------------------------

## The heart of it: three entries, three DIFFERENT schedules, none borrowing another's.
## Under the old collapse palettes 5 and 7 read start=0/count=3/duration=15 — palette 2's.
func _test_each_entry_keeps_its_own_schedule() -> void:
	var t := PaletteAnimationTable.build(MAP009_ANIMS)

	_assert(t["any"], "MAP009 animates something")
	_assert_schedule(t, 2, 0, 3, 15.0,
		PaletteAnimationTable.MODE_FORWARD_AND_REVERSE_LOOPING, "palette 2")
	_assert_schedule(t, 5, 3, 4, 9.0,
		PaletteAnimationTable.MODE_FORWARD_LOOPING, "palette 5")
	_assert_schedule(t, 7, 7, 4, 9.0,
		PaletteAnimationTable.MODE_FORWARD_LOOPING, "palette 7")

	# And the rows they address are disjoint: 16-18, 19-22, 23-26 of the 16x32 palette
	# texture. Sharing a start index is exactly the bug.
	var rows := {}
	for pid in [2, 5, 7]:
		for f in range(t["count"][pid]):
			var row: int = PaletteAnimationTable.ANIM_ROW_BASE + t["start"][pid] + f
			_assert(not rows.has(row), "row %d claimed by one palette only" % row)
			rows[row] = pid
	_assert_eq(rows.size(), 11, "MAP009 claims 11 animation rows (3 + 4 + 4)")


## The ids are 2, 5 and 7 — NOT a contiguous range. 3, 4 and 6 have no animation, and the
## old min..max span animated all three of them with palette 2's frames.
func _test_gaps_in_the_id_set_do_not_animate() -> void:
	var t := PaletteAnimationTable.build(MAP009_ANIMS)
	for pid in [0, 1, 3, 4, 6, 8, 15]:
		_assert_eq(t["count"][pid], 0, "palette %d does not animate" % pid)


## A map with no palette animations produces a table that turns the shader gate OFF, so
## `enable_palette_animation` can be set on EVERY material without inventing motion.
func _test_no_animations_is_an_inert_table() -> void:
	var t := PaletteAnimationTable.build([])
	_assert(not t["any"], "empty manifest list does not animate")
	_assert_eq(t["count"].size(), PaletteAnimationTable.PALETTE_COUNT, "table is 16 wide")
	for pid in range(PaletteAnimationTable.PALETTE_COUNT):
		_assert_eq(t["count"][pid], 0, "palette %d inert" % pid)


## ForwardLoopingOnTrigger / ForwardOnceOnTrigger are played by an event script, not by
## the clock. They must not free-run — 8 entries across the map corpus are in that state.
func _test_trigger_modes_do_not_free_run() -> void:
	var t := PaletteAnimationTable.build([
		{"overridden_palette_id": 4, "animation_start_index": 0, "frame_count": 4,
			"frame_duration": 12, "animation_mode": "ForwardLoopingOnTrigger"},
		{"overridden_palette_id": 9, "animation_start_index": 4, "frame_count": 4,
			"frame_duration": 12, "animation_mode": "ForwardOnceOnTrigger"},
	])
	_assert(not t["any"], "trigger-only manifest does not free-run")
	_assert_eq(t["count"][4], 0, "ForwardLoopingOnTrigger inert")
	_assert_eq(t["count"][9], 0, "ForwardOnceOnTrigger inert")

	# An unknown/`Unknown` mode is treated the same way: one CLUT, no guessed schedule.
	var u := PaletteAnimationTable.build([
		{"overridden_palette_id": 4, "animation_start_index": 0, "frame_count": 4,
			"frame_duration": 12, "animation_mode": "Unknown"},
	])
	_assert_eq(u["count"][4], 0, "Unknown mode inert")


## Two entries CAN name one palette (MAP018 names 10 twice, MAP033 names 13 twice). One
## CLUT shows one schedule, so the later entry wins — pinned so the choice is not silent.
func _test_duplicate_palette_id_last_wins() -> void:
	var t := PaletteAnimationTable.build([
		{"overridden_palette_id": 10, "animation_start_index": 0, "frame_count": 3,
			"frame_duration": 12, "animation_mode": "ForwardLooping"},
		{"overridden_palette_id": 10, "animation_start_index": 6, "frame_count": 4,
			"frame_duration": 4, "animation_mode": "ForwardAndReverseLooping"},
	])
	_assert_schedule(t, 10, 6, 4, 4.0,
		PaletteAnimationTable.MODE_FORWARD_AND_REVERSE_LOOPING, "duplicate id")


## Malformed rows are skipped rather than written out of bounds — the arrays are exactly
## 16 wide and the shader indexes them with a clamped palette id.
func _test_out_of_range_and_empty_entries_are_ignored() -> void:
	var t := PaletteAnimationTable.build([
		{"overridden_palette_id": 16, "frame_count": 3, "animation_mode": "ForwardLooping"},
		{"overridden_palette_id": -1, "frame_count": 3, "animation_mode": "ForwardLooping"},
		{"overridden_palette_id": 3, "frame_count": 0, "animation_mode": "ForwardLooping"},
		{},
	])
	_assert(not t["any"], "no usable entry animates")
	_assert_eq(t["count"].size(), PaletteAnimationTable.PALETTE_COUNT, "still 16 wide")
	_assert_eq(t["count"][3], 0, "zero-frame entry inert")
