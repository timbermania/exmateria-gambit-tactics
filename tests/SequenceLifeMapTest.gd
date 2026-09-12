extends Node
## TDD guard for the OPCODE -> LIFE-FRAME PROJECTION — the map that lets a film-strip cell
## be the second entry point for a colour keyframe (ADR-0089's colour-move amendment).
##
## The author's model is that the frame axis is a SUPERSET of the opcode axis, so picking a
## cell picks a frame. Measured over all 401 corpus effects that holds for 84% of the 2622
## colour-enabled emitters and breaks for a nameable 12.4%: 324 emitters whose particles
## DIE mid-animation, so their tail opcodes have no life frame at all (median 9 frames of
## animation never seen, p90 41, max 128). These tests pin the partial function — including
## that it answers -1 rather than clamping, because a clamped answer would pile every
## unreachable cell onto the last live frame and look like a working feature.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/SequenceLifeMapTest.tscn

const LifeMap = preload("res://src/effects/studio/SequenceLifeMap.gd")
const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")

var _passed: int = 0
var _failed: int = 0
var _completed: bool = false


func _ready() -> void:
	_test_a_cell_maps_to_the_tick_its_dwell_begins_at()
	_test_it_reads_the_traces_own_tick_start_not_a_second_halving()
	_test_a_cell_past_the_particles_death_answers_minus_one_not_a_clamp()
	_test_everything_after_a_terminal_frame_is_unreachable()
	_test_the_terminal_cell_ITSELF_is_still_reachable()
	_test_a_looped_opcode_resolves_to_its_FIRST_occurrence()
	_test_a_zero_dwell_cell_maps_to_the_boundary_it_sits_on()
	_test_an_unresolvable_window_maps_nothing()
	_test_life_frames_agrees_with_life_frame_of_cell_by_cell()
	_test_unreachable_count_states_what_the_greying_hides()
	_test_the_life_column_covers_every_age_exactly_once()
	_test_a_terminal_cell_owns_the_REST_of_the_life()
	_test_a_loop_gives_a_recurring_cell_ONE_ROW_PER_PASS()
	_test_a_zero_dwell_cell_gets_no_row_because_it_holds_no_age()
	_test_the_column_stops_at_death_mid_cell()
	_test_rows_of_cell_finds_every_pass()
	_test_no_column_is_longer_than_the_life_it_describes()

	_completed = true
	print("\n=== SequenceLifeMapTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0 or not _completed:
		print("[FAIL] SequenceLifeMapTest")
		get_tree().quit(1)
	else:
		print("[PASS] SequenceLifeMapTest")
		get_tree().quit(0)


## THE LIFE COLUMN'S CENTRAL INVARIANT: the rows partition `[0, life_n)` — every age is
## described by exactly one row, no gaps, no overlaps. The vertical colour ribbon draws one
## column per age INSIDE a row, so a gap would be a life frame with no colour anywhere and
## an overlap would be one with two.
func _test_the_life_column_covers_every_age_exactly_once() -> void:
	var rows := LifeMap.life_rows(_trace([4, 4, 4]), 6)
	_assert_eq(rows.size(), 3, "three 2-tick cells over a 6-frame life = 3 rows")
	_assert_true(_partitions(rows, 6), "and they partition [0, 6) exactly")


## A `duration = 0` frame PARKS (`ParticleAnimator.tick` sets `animation_held` and returns
## without advancing), so it owns every remaining life frame — 769 corpus emitters end this
## way, holding a median 9 frames and up to 110. `life_frames` cannot express that: it has
## one number per cell and no room for a span.
func _test_a_terminal_cell_owns_the_REST_of_the_life() -> void:
	var rows := LifeMap.life_rows(_trace([4, 0]), 20)
	_assert_eq(rows.size(), 2, "two cells, two rows")
	_assert_eq(int(rows[0]["ticks"]), 2, "the first dwells its own 2 ticks")
	_assert_eq(int(rows[1]["start"]), 2, "the terminal one starts where it left off")
	_assert_eq(int(rows[1]["ticks"]), 18, "…and holds the other 18 frames of a 20-frame life")
	_assert_true(_partitions(rows, 20), "still a clean partition")


## No terminal frame → `anim_time` wraps to 0, so a cell RECURS. 112 corpus emitters loop,
## a median 6 times and up to 26. `life_frames` resolves a repeat to its FIRST occurrence by
## decision (2026-08-20) and the later passes had no home at all; a life column gives each
## pass its own row, which is what makes every age addressable.
func _test_a_loop_gives_a_recurring_cell_ONE_ROW_PER_PASS() -> void:
	var rows := LifeMap.life_rows(_trace([2, 2]), 4)   # 1 tick each, life 4 = two passes
	_assert_eq(rows.size(), 4, "a 2-frame animation over a 4-frame life plays twice")
	_assert_eq(int(rows[0]["cell"]), 0, "pass 1 cell 0")
	_assert_eq(int(rows[2]["cell"]), 0, "pass 2 replays cell 0 as its OWN row")
	_assert_eq(int(rows[2]["start"]), 2, "…at age 2, not folded onto the first occurrence")
	_assert_true(_partitions(rows, 4), "and the two passes still partition the life")


## LOOP and SET_OFFSET dwell zero ticks, so they hold no age and get no row. They keep their
## trace cell and their picture — they are simply not part of any life frame.
func _test_a_zero_dwell_cell_gets_no_row_because_it_holds_no_age() -> void:
	var tr := SequenceTimeline.trace({"opcodes": [
		{"type": "SET_OFFSET", "offset": Vector2(1, 1)},
		{"type": "FRAME", "frameset": 0, "duration": 4, "depth_mode": 0},
		{"type": "LOOP"}]})
	var rows := LifeMap.life_rows(tr, 2)
	_assert_eq(rows.size(), 1, "only the FRAME cell holds an age")
	_assert_eq(int(rows[0]["cell"]), 1, "and it is the trace index, not a compacted one")


## Death mid-cell TRUNCATES the row rather than dropping it — the particle really does show
## that picture, just for fewer frames than the opcode asked for.
func _test_the_column_stops_at_death_mid_cell() -> void:
	var rows := LifeMap.life_rows(_trace([8, 8]), 3)   # 4 ticks each, life 3
	_assert_eq(rows.size(), 1, "the particle dies inside the first cell")
	_assert_eq(int(rows[0]["ticks"]), 3, "so its row is clipped to the 3 frames it lived")
	_assert_true(_partitions(rows, 3), "and still covers the whole life")


func _test_rows_of_cell_finds_every_pass() -> void:
	var rows := LifeMap.life_rows(_trace([2, 2]), 6)
	_assert_eq(LifeMap.rows_of_cell(rows, 0).size(), 3, "cell 0 plays three times in 6 frames")
	_assert_eq(LifeMap.rows_of_cell(rows, 9).size(), 0, "a cell that is not there has no rows")


## THE BOUND, over the real corpus: a row consumes at least one life frame, so the column is
## never longer than `life_n` however many times the animation loops. This is what keeps a
## 26-pass loop from instantiating 26 x 36 thumbnails.
func _test_no_column_is_longer_than_the_life_it_describes() -> void:
	var checked := 0
	var worst := 0
	for durations in [[4, 4, 4], [2, 2], [4, 0], [1, 1, 1, 1], [8, 8], [2, 2, 2, 2, 2, 2]]:
		for life in [1, 2, 3, 7, 16, 40, 160]:
			var rows := LifeMap.life_rows(_trace(durations), life)
			checked += 1
			worst = maxi(worst, rows.size())
			_assert_true(rows.size() <= life, "column <= life (%d rows for life %d)"
				% [rows.size(), life])
			_assert_true(_partitions(rows, life), "and partitions it (%s, life %d)"
				% [str(durations), life])
	print("  life column: %d (durations x life) combinations, longest column %d rows"
		% [checked, worst])


## Do the rows tile `[0, n)` exactly — contiguous, in order, ending on the last frame?
func _partitions(rows: Array, n: int) -> bool:
	var f := 0
	for r in rows:
		if int(r["start"]) != f or int(r["ticks"]) <= 0:
			return false
		f += int(r["ticks"])
	return f == n


func _test_a_cell_maps_to_the_tick_its_dwell_begins_at() -> void:
	# durations 4,4,4 -> 2 ticks each -> starts 0, 2, 4.
	var tr := _trace([4, 4, 4])
	_assert_eq(LifeMap.life_frame_of(tr, 0, 40), 0, "cell 0 begins at life frame 0")
	_assert_eq(LifeMap.life_frame_of(tr, 1, 40), 2, "cell 1 begins at life frame 2")
	_assert_eq(LifeMap.life_frame_of(tr, 2, 40), 4, "cell 2 begins at life frame 4")


func _test_it_reads_the_traces_own_tick_start_not_a_second_halving() -> void:
	# The halving ROUNDS UP (0x801AA1F8) and the corpus caught a floor-halving being wrong
	# on the 10 odd durations >= 3. An odd duration is the case that separates the two.
	var tr := _trace([3, 3])
	_assert_eq(int(tr[0]["ticks"]), 2, "duration 3 dwells ceil(3/2) = 2 ticks")
	_assert_eq(LifeMap.life_frame_of(tr, 1, 40), 2,
		"so the second cell starts at 2 — the trace's number, not a re-derived one")


func _test_a_cell_past_the_particles_death_answers_minus_one_not_a_clamp() -> void:
	# THE 12.4% CASE. A clamp would pile every unreachable cell onto the last live frame,
	# which draws a plausible-looking keyframe at an age this opcode never reaches.
	var tr := _trace([4, 4, 4, 4, 4])   # starts 0,2,4,6,8
	_assert_eq(LifeMap.life_frame_of(tr, 2, 5), 4, "the last cell inside a 5-frame life maps")
	_assert_eq(LifeMap.life_frame_of(tr, 3, 5), -1, "the first cell past it answers -1")
	_assert_eq(LifeMap.life_frame_of(tr, 4, 5), -1, "and so does every cell after that")


func _test_everything_after_a_terminal_frame_is_unreachable() -> void:
	# ParticleAnimator parks on a duration = 0 frame (authored lifetime) or dies on it
	# (animation-driven). Either way nothing after it ever shows — however long life is.
	var tr := _trace([4, 0, 4, 4])
	_assert_eq(LifeMap.life_frame_of(tr, 2, 200), -1,
		"a cell after the terminal is unreachable even in a very long life")
	_assert_eq(LifeMap.life_frame_of(tr, 3, 200), -1, "and so is the one after that")


func _test_the_terminal_cell_ITSELF_is_still_reachable() -> void:
	# The particle SHOWS the terminal frame — duration 0 displays once, then stops. Only
	# what follows it is dead. Off-by-one here would grey out the cell an author most
	# wants to colour: the one the particle spends its whole tail on.
	var tr := _trace([4, 0, 4])
	_assert_eq(LifeMap.life_frame_of(tr, 1, 200), 2, "the terminal cell maps to its own start")


func _test_a_looped_opcode_resolves_to_its_FIRST_occurrence() -> void:
	# Author's decision, 2026-08-20. A 6-frame animation over a 40-frame life plays ~6
	# times; one click gives one keyframe, at a position that does not depend on where the
	# player is parked. The other repeats are reachable by clicking the ribbon directly.
	var tr := _trace([4, 4, 4])   # 6 ticks total, life 40 -> ~6 loops
	_assert_eq(LifeMap.life_frame_of(tr, 1, 40), 2,
		"cell 1's first occurrence is frame 2, not 8 or 14 or 38")


func _test_a_zero_dwell_cell_maps_to_the_boundary_it_sits_on() -> void:
	# A leading SET_OFFSET occupies no time; it sits on the tick the next FRAME begins at.
	var anim := {"opcodes": [{"type": "SET_OFFSET", "x": 0, "y": 0},
		{"type": "FRAME", "frameset": 0, "duration": 4, "depth_mode": 0}]}
	var tr: Array = SequenceTimeline.trace(anim)
	_assert_eq(LifeMap.life_frame_of(tr, 0, 40), 0, "the leading SET_OFFSET is at frame 0")
	_assert_eq(LifeMap.life_frame_of(tr, 1, 40), 0, "and so is the FRAME it precedes")


func _test_an_unresolvable_window_maps_nothing() -> void:
	# life_n = -1 is EmitterLifeWindow's honest "cannot resolve". Treating it as 160 here
	# would make every cell clickable on exactly the emitters we know least about.
	var tr := _trace([4, 4])
	_assert_eq(LifeMap.life_frame_of(tr, 0, -1), -1, "an unresolved window maps nothing")
	_assert_eq(LifeMap.life_frame_of(tr, 0, 0), -1, "and neither does a zero one")
	_assert_eq(LifeMap.life_frame_of(tr, 9, 40), -1, "an out-of-range cell is -1, not a crash")


func _test_life_frames_agrees_with_life_frame_of_cell_by_cell() -> void:
	# The batch form exists so the strip does not re-scan the terminal prefix once per
	# cell. Two implementations of one rule is exactly what this module was made to stop,
	# so they are held to each other.
	for durations in [[4, 4, 4, 4], [4, 0, 4], [3, 3, 3], [0], [4, 4, 4, 4, 4, 4]]:
		for life in [-1, 1, 3, 5, 40]:
			var tr := _trace(durations)
			var batch: Array = LifeMap.life_frames(tr, life)
			_assert_eq(batch.size(), tr.size(), "one answer per cell (%s, life %d)"
				% [str(durations), life])
			for i in range(tr.size()):
				if int(batch[i]) != LifeMap.life_frame_of(tr, i, life):
					_failed += 1
					print("  [FAIL] batch and single disagree at cell %d (%s, life %d)"
						% [i, str(durations), life])
					return
	_passed += 1


func _test_unreachable_count_states_what_the_greying_hides() -> void:
	# Dropping cells silently is the other way to be wrong — the same lesson ADR-0089's
	# dead-zone amendment learned about keyframes past the life window.
	var tr := _trace([4, 4, 4, 4, 4])   # starts 0,2,4,6,8
	_assert_eq(LifeMap.unreachable_count(tr, 5), 2, "2 of 5 cells are past a 5-frame life")
	_assert_eq(LifeMap.unreachable_count(tr, 40), 0, "none of them are past a 40-frame one")


# --- fixtures ---

func _trace(durations: Array) -> Array:
	var ops: Array = []
	for d in durations:
		ops.append({"type": "FRAME", "frameset": 0, "duration": int(d), "depth_mode": 0})
	return SequenceTimeline.trace({"opcodes": ops})


# --- harness ---

func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)


func _assert_eq(a, b, msg: String) -> void:
	if a == b:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s (got %s, want %s)" % [msg, str(a), str(b)])
