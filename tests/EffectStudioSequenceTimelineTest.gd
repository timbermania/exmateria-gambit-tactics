extends Node
## TDD guard for the SEQUENCE film-strip's pure decode (`SequenceTimeline.gd`).
##
## THE MODEL (revised with the user 2026-08-20 — the ADR-0102 fencepost amendment).
## The strip is a ROW OF TIME POSITIONS: ONE CELL PER OPCODE — every opcode, not just
## FRAME — and a cell renders the animation at the position it stands for, `pos_tick`.
## The first cell is the animation at t=0, the last is the animation at its end, and
## an interior cell is the END of that opcode's duration.
##
## Consequences that are asserted here because they are the whole point:
##   * offsets ACCUMULATE into the cell — E190 anim 2 shows frameset 1 three times
##     differing ONLY by offset, so a strip that ignored the offset would draw three
##     identical cells and hide the motion the sequence exists to encode.
##   * every animation opens with a SET_OFFSET before any FRAME (2,428 of 2,428 in
##     the corpus, and the first FRAME is opcode 1 in every one of them), so cell 0 is
##     the spare slot the animation's START goes in. It used to draw an empty box on
##     the grounds that "inventing a sprite there would make it lie"; a position is not
##     an invention, so it now shows the frame that is on screen at t=0.
##   * the positions are MONOTONE and span exactly `[0, total_ticks - 1]`. That is the
##     fencepost: N stretches of time have N+1 boundaries, and both ends are now
##     reachable. It also means a park can never seek off the end of the sequence.
##   * `tick_start`/`ticks` did NOT move. They are still the dwell — the per-opcode view
##     of `ParticleAnimator._bake_animations` — and `total_ticks` still equals that
##     bake's array length, which is what the corpus parity sweep checks.
##
## The expectations were produced by an INDEPENDENT Python oracle that decodes
## `animations.json` without reading this codebase (scratchpad/seq_trace_oracle.py),
## so it can genuinely disagree — the method that caught four wrong numbers last
## session. Corpus figures quoted below are that oracle's, over 2,428 animations.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioSequenceTimelineTest.tscn

const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_a_cell_per_opcode_not_per_frame_opcode()
	_test_cell_zero_is_the_animations_first_frame()
	_test_the_last_cell_is_the_animations_last_frame()
	_test_every_row_is_a_time_position()
	_test_an_interior_cell_stands_for_the_end_of_its_duration()
	_test_the_cut_window_ends_at_the_position()
	_test_an_animation_with_no_trailing_loop_needs_no_special_case()
	_test_an_animation_with_no_frame_at_all_keeps_the_crosshair()
	_test_offsets_accumulate_so_a_repeated_frameset_still_moves()
	_test_a_frame_dwells_duration_halved_ticks()
	_test_zero_duration_is_terminal_and_still_shows_once()
	_test_an_odd_duration_rounds_UP_the_way_the_rom_does()
	_test_loop_holds_the_final_state()
	_test_tick_spans_are_contiguous_and_address_the_frame_cell()
	_test_bounds_is_the_union_over_every_step_at_its_offset()
	_test_bounds_survives_a_sequence_whose_framesets_do_not_exist()
	_test_cell_aspect_is_square_for_the_median_and_clamped_for_a_beam()
	_test_sprite_quads_composite_every_frame_of_the_frameset()
	_test_sprite_quads_map_a_mirrored_frame_through_signed_uvs()
	_test_a_frame_opcode_index_is_relative_to_the_frameset_group()

	print("\n=== EffectStudioSequenceTimelineTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSequenceTimelineTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSequenceTimelineTest")
		get_tree().quit(0)


## E190 anim 2 — a falling sprite, and the corpus's ideal fixture: SET_OFFSET, four
## mid-stream ADD_OFFSETs, frameset 1 three times at three offsets, a duration=24
## hold, a duration=0 terminal, and a LOOP. 12 opcodes.
func _e190_anim2() -> Dictionary:
	return {"index": 2, "opcodes": [
		{"type": "SET_OFFSET", "x": 0, "y": -48},
		{"type": "FRAME", "frameset": 0, "duration": 2, "depth_mode": 1},
		{"type": "ADD_OFFSET", "dx": 0, "dy": 8},
		{"type": "FRAME", "frameset": 1, "duration": 2, "depth_mode": 1},
		{"type": "ADD_OFFSET", "dx": 0, "dy": 16},
		{"type": "FRAME", "frameset": 1, "duration": 2, "depth_mode": 1},
		{"type": "ADD_OFFSET", "dx": 0, "dy": 16},
		{"type": "FRAME", "frameset": 1, "duration": 2, "depth_mode": 1},
		{"type": "ADD_OFFSET", "dx": 0, "dy": 8},
		{"type": "FRAME", "frameset": 2, "duration": 24, "depth_mode": 1},
		{"type": "FRAME", "frameset": 2, "duration": 0, "depth_mode": 1},
		{"type": "LOOP"},
	]}


func _test_a_cell_per_opcode_not_per_frame_opcode() -> void:
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	_assert_eq(tr.size(), 12, "one cell per OPCODE — 12 opcodes, 12 cells (not 6 FRAMEs, not 17 ticks)")
	_assert_eq(tr[0].get("type"), "SET_OFFSET", "the non-FRAME opcodes get cells too")
	_assert_eq(tr[11].get("type"), "LOOP", "including the trailing LOOP")
	_assert_eq(tr[4].get("op_index"), 4, "each cell carries the opcode index it selects")


func _test_cell_zero_is_the_animations_first_frame() -> void:
	# THE REVERSAL. Cell 0's opcode is a SET_OFFSET and runs before any FRAME, so under
	# the old model it drew an empty box with a crosshair. Under the new one it stands
	# for t=0, and what the game puts on screen at t=0 is the first FRAME's state.
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	_assert_eq(tr[0].get("pos_tick"), 0, "cell 0 stands for the animation's first tick")
	_assert_eq(tr[0].get("has_sprite"), true, "so it draws a sprite rather than a crosshair")
	_assert_eq(tr[0].get("frameset"), 0, "the frameset that is up at t=0 — the first FRAME's")
	_assert_eq(tr[0].get("depth_mode"), 1, "with that frame's depth mode, not the -1 it held")
	_assert_eq(tr[0].get("offset"), Vector2i(0, -48),
		"at the offset the first FRAME renders at, which here is the one it just set")
	_assert_eq(tr[0].get("type"), "SET_OFFSET",
		"the ROW still names its own opcode — only the picture is of a time position")
	_assert_eq(tr[0].get("ticks"), 0, "and it still owns no dwell: the bake is untouched")


func _test_the_last_cell_is_the_animations_last_frame() -> void:
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	var total: int = SequenceTimeline.total_ticks(tr)
	_assert_eq(tr[11].get("type"), "LOOP", "the trailing LOOP is the spare slot at the end")
	_assert_eq(tr[11].get("pos_tick"), total - 1,
		"and it stands for the animation's LAST tick, the fencepost the strip could not reach")
	_assert_eq(tr[11].get("has_sprite"), true, "drawing the last frame")
	_assert_eq(tr[11].get("frameset"), 2, "which is the frameset still up when the clock ends")
	# The author's call on the collision: it stays a distinct, selectable slot even though
	# its picture duplicates the row above. The last FRAME's end IS the animation's end, so
	# the two agreeing is the model working, not a bug to hide.
	_assert_eq(tr[10].get("pos_tick"), tr[11].get("pos_tick"),
		"the last FRAME's end and the animation's end are the same tick, and both are shown")


func _test_every_row_is_a_time_position() -> void:
	# THE FENCEPOST, asserted as a whole. Every row carries a position; the positions run
	# in order and cover exactly [0, total-1] end to end, with the two ends AT the ends.
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	var total: int = SequenceTimeline.total_ticks(tr)
	var pos: Array = []
	for e in tr:
		pos.append(int(e.get("pos_tick", -1)))
	_assert_eq(pos, [0, 0, 0, 1, 1, 2, 2, 3, 3, 15, 16, 16],
		"one position per row, from the animation's first tick to its last")
	_assert_eq(pos[0], 0, "the strip STARTS at the animation's start")
	_assert_eq(pos[pos.size() - 1], total - 1, "and ENDS at its end")
	for i in range(pos.size()):
		_assert_true(pos[i] >= 0 and pos[i] <= total - 1,
			"row %d's position is inside the sequence, so a park can never seek off it" % i)
		if i > 0:
			_assert_true(pos[i] >= pos[i - 1], "row %d does not go backwards in time" % i)


func _test_an_interior_cell_stands_for_the_end_of_its_duration() -> void:
	# The author's words: "in between it's the END of that opcode's duration". The
	# 12-tick hold is the case that can show it — 83.6% of corpus cells dwell one tick,
	# where the end and the start are the same number and nothing moves.
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	_assert_eq(tr[9].get("tick_start"), 4, "the long hold's dwell still BEGINS at tick 4")
	_assert_eq(tr[9].get("ticks"), 12, "and still runs 12 ticks — the bake is untouched")
	_assert_eq(tr[9].get("pos_tick"), 15, "but the ROW stands for its last tick, 4 + 12 - 1")
	_assert_eq(tr[1].get("tick_start"), tr[1].get("pos_tick"),
		"a one-tick dwell's start and end are one tick, so those rows do not move at all")


func _test_the_cut_window_ends_at_the_position() -> void:
	# The whole model in one invariant: a row's position is the LAST tick of its colour
	# window. That pins `cut_start`/`cut_ticks` to `pos_tick` so the two cannot drift.
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	for i in range(tr.size()):
		var e: Dictionary = tr[i]
		_assert_eq(int(e.get("cut_start", -1)) + int(e.get("cut_ticks", 0)) - 1,
			int(e.get("pos_tick", -1)),
			"row %d's window ends exactly at the position it stands for" % i)
		_assert_eq(int(e.get("cut_ticks", 0)), maxi(1, int(e.get("ticks", 0))),
			"row %d spans its dwell, or one tick when it has none" % i)
	_assert_eq(tr[9].get("cut_start"), 4,
		"a FRAME's window still OPENS at its dwell — the ADR-0103 cut is unchanged for it")
	_assert_eq(tr[0].get("cut_ticks"), 1,
		"and a row owning no dwell is a still, so `cell_color` needs no branch for it")


func _test_an_animation_with_no_trailing_loop_needs_no_special_case() -> void:
	# 51 of the 2,428 corpus animations end on a FRAME rather than a LOOP (50 end
	# FRAME,FRAME; one ends ADD_OFFSET,FRAME). There is no spare slot at the end — and
	# none is needed, because that FRAME's end-of-duration already IS the animation's end.
	var tr: Array = SequenceTimeline.trace({"opcodes": [
		{"type": "SET_OFFSET", "x": 0, "y": 0},
		{"type": "FRAME", "frameset": 3, "duration": 8, "depth_mode": 1},
		{"type": "FRAME", "frameset": 4, "duration": 0, "depth_mode": 1},
	]})
	var total: int = SequenceTimeline.total_ticks(tr)
	_assert_eq(total, 5, "4 ticks of hold and one terminal frame")
	_assert_eq(tr[2].get("type"), "FRAME", "the last row is a real FRAME, not a spare slot")
	_assert_eq(tr[2].get("pos_tick"), total - 1, "and it lands on the end by the same rule")
	_assert_eq(tr[0].get("pos_tick"), 0, "while the start still lands on the leading SET_OFFSET")
	_assert_eq(tr[0].get("frameset"), 3, "which shows the first frame")


func _test_an_animation_with_no_frame_at_all_keeps_the_crosshair() -> void:
	# Nothing to adopt, so nothing is invented. No corpus animation is shaped this way,
	# but E509/E510 prove the strip has to stay navigable with nothing to draw.
	var tr: Array = SequenceTimeline.trace({"opcodes": [
		{"type": "SET_OFFSET", "x": 4, "y": 4},
		{"type": "LOOP"},
	]})
	_assert_eq(SequenceTimeline.total_ticks(tr), 0, "a sequence with no FRAME runs no ticks")
	_assert_eq(tr[0].get("has_sprite"), false, "and there is no first frame to show")
	_assert_eq(tr[1].get("has_sprite"), false, "nor any last one")
	_assert_eq(tr[0].get("pos_tick"), 0, "the positions collapse to 0 rather than going negative")
	_assert_eq(tr[1].get("pos_tick"), 0, "so a click still parks somewhere legal")


func _test_offsets_accumulate_so_a_repeated_frameset_still_moves() -> void:
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	# Cells 3, 5, 7 are all frameset 1. If the offset were dropped they would be
	# pixel-identical and the fall would be invisible.
	_assert_eq(tr[3].get("frameset"), 1, "cell 3 holds frameset 1")
	_assert_eq(tr[5].get("frameset"), 1, "cell 5 holds the SAME frameset")
	_assert_eq(tr[7].get("frameset"), 1, "so does cell 7")
	_assert_eq(tr[3].get("offset"), Vector2i(0, -40), "-48 + 8")
	_assert_eq(tr[5].get("offset"), Vector2i(0, -24), "-40 + 16")
	_assert_eq(tr[7].get("offset"), Vector2i(0, -8), "-24 + 16")
	# An ADD_OFFSET cell keeps the sprite it inherited and only moves it.
	_assert_eq(tr[2].get("frameset"), 0, "an ADD_OFFSET cell still shows the frameset it inherited")
	_assert_eq(tr[2].get("offset"), Vector2i(0, -40), "moved to the new offset")


func _test_a_frame_dwells_duration_halved_ticks() -> void:
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	# FFT decrements frame_timer by 2 per game frame, so a FRAME shows for duration>>1.
	_assert_eq(tr[1].get("ticks"), 1, "duration 2 shows for 1 tick")
	_assert_eq(tr[9].get("ticks"), 12, "duration 24 shows for 12")
	_assert_eq(tr[2].get("ticks"), 0, "an ADD_OFFSET takes no time at all")
	_assert_eq(tr[11].get("ticks"), 0, "nor does LOOP")
	_assert_eq(SequenceTimeline.total_ticks(tr), 17, "the whole sequence runs 17 ticks")


func _test_zero_duration_is_terminal_and_still_shows_once() -> void:
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	_assert_eq(tr[10].get("duration"), 0, "the last FRAME stores duration 0")
	_assert_eq(tr[10].get("ticks"), 1, "which still displays ONCE — max(1, 0>>1), not zero")
	_assert_eq(tr[10].get("is_terminal"), true, "and then terminates the animation")
	_assert_eq(tr[9].get("is_terminal"), false, "an ordinary hold is not terminal")


func _test_an_odd_duration_rounds_UP_the_way_the_rom_does() -> void:
	# The ROM's interpreter (`render_particle_sprite` @0x801AA1F8) sets
	# frame_timer = duration, then each render call does `timer -= 2` and advances
	# only once the SIGN-EXTENDED result is < 1. So the entry is on screen for
	# ceil(duration/2) calls, not floor: duration 255 survives 255,253,...,1 and
	# advances on the call that would make it -1 — 128 ticks, not 127.
	# Even durations are unaffected (ceil == floor), which is 21,032 of the 21,043
	# FRAME opcodes in the corpus; only 10 opcodes are odd and >= 3 (nine D=255,
	# one D=75), all verified against `animations.json` directly.
	var tr255: Array = SequenceTimeline.trace(_e088_anim0())
	_assert_eq(tr255[1].get("ticks"), 128, "duration 255 shows for ceil(255/2) = 128 ticks")
	var tr75: Array = SequenceTimeline.trace(_e141_anim5())
	_assert_eq(tr75[1].get("ticks"), 38, "duration 75 shows for ceil(75/2) = 38 ticks")
	# The even case must not move, or the fix has cost more than it bought.
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	_assert_eq(tr[1].get("ticks"), 1, "duration 2 still shows for 1 tick")
	_assert_eq(tr[9].get("ticks"), 12, "duration 24 still shows for 12")
	_assert_eq(tr[10].get("ticks"), 1, "and duration 0 still shows ONCE")


## E088 animation 0, verbatim — the corpus's duration-255 case (shared by E089/E090
## and six more). A single long-held frameset, then the terminal frame.
func _e088_anim0() -> Dictionary:
	return {
		"opcodes": [
			{"type": "SET_OFFSET", "x": 0, "y": 0},
			{"type": "FRAME", "frameset": 2, "duration": 255, "depth_mode": 1},
			{"type": "FRAME", "frameset": 0, "duration": 0, "depth_mode": 1},
			{"type": "LOOP"},
		]
	}


## E141 animation 5, verbatim — the corpus's only other odd duration >= 3.
func _e141_anim5() -> Dictionary:
	return {
		"opcodes": [
			{"type": "SET_OFFSET", "x": 0, "y": 0},
			{"type": "FRAME", "frameset": 20, "duration": 75, "depth_mode": 1},
			{"type": "FRAME", "frameset": 0, "duration": 0, "depth_mode": 1},
			{"type": "LOOP"},
		]
	}


func _test_loop_holds_the_final_state() -> void:
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	_assert_eq(tr[11].get("frameset"), 2, "LOOP changes nothing, so it shows what was already up")
	_assert_eq(tr[11].get("offset"), Vector2i(0, 0), "at the offset already reached")
	_assert_eq(tr[11].get("has_sprite"), true, "it is a real picture, not an empty cell")


func _test_tick_spans_are_contiguous_and_address_the_frame_cell() -> void:
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	_assert_eq(tr[1].get("tick_start"), 0, "the first FRAME starts the clock")
	_assert_eq(tr[9].get("tick_start"), 4, "four single-tick FRAMEs precede the long hold")
	_assert_eq(tr[10].get("tick_start"), 16, "which ends at 4 + 12")
	# The playhead maps a playing tick back to the cell to highlight.
	_assert_eq(SequenceTimeline.op_at_tick(tr, 0), 1, "tick 0 is the first FRAME opcode")
	_assert_eq(SequenceTimeline.op_at_tick(tr, 3), 7, "tick 3 is the third repeat of frameset 1")
	_assert_eq(SequenceTimeline.op_at_tick(tr, 4), 9, "tick 4 enters the 12-tick hold")
	_assert_eq(SequenceTimeline.op_at_tick(tr, 15), 9, "and stays there to its last tick")
	_assert_eq(SequenceTimeline.op_at_tick(tr, 16), 10, "tick 16 is the terminal frame")
	_assert_eq(SequenceTimeline.op_at_tick(tr, 17), -1, "past the end addresses nothing")


func _test_bounds_is_the_union_over_every_step_at_its_offset() -> void:
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	# Two 1-frame framesets, a 4x4 quad each, at offsets y=-48 and y=0.
	var framesets: Array = [
		_frameset([_frame(Rect2i(0, 0, 4, 4), Rect2i(0, 0, 4, 4))]),
		_frameset([_frame(Rect2i(0, 0, 4, 4), Rect2i(0, 0, 4, 4))]),
		_frameset([_frame(Rect2i(0, 0, 4, 4), Rect2i(0, 0, 4, 4))]),
	]
	var box: Rect2i = SequenceTimeline.bounds(tr, framesets)
	# y spans from the first step's top (0 + -48) to the last step's bottom (3 + 0).
	_assert_eq(box, Rect2i(0, -48, 4, 52),
		"ONE box over the whole sequence — a per-cell fit would re-centre each sprite and cancel the fall")


func _test_bounds_survives_a_sequence_whose_framesets_do_not_exist() -> void:
	# E509/E510 really are like this: 14 framesets referenced, frames.json EMPTY.
	var tr: Array = SequenceTimeline.trace(_e190_anim2())
	var box: Rect2i = SequenceTimeline.bounds(tr, [])
	_assert_eq(box, Rect2i(), "no drawable geometry yields an empty box, not a crash or a garbage union")
	_assert_eq(SequenceTimeline.trace(_e190_anim2()).size(), 12,
		"and the cells still exist — the strip stays navigable with nothing to draw in it")


func _test_cell_aspect_is_square_for_the_median_and_clamped_for_a_beam() -> void:
	# Measured over 2,420 animations with drawable bounds: median aspect is EXACTLY
	# 1.0 (p25 through p75 all 1.0); 7.1% fall outside [0.2, 5.0], max 167:1.
	_assert_eq(SequenceTimeline.cell_aspect(Rect2i(0, 0, 36, 36)), 1.0, "the median animation is square")
	_assert_eq(SequenceTimeline.cell_aspect(Rect2i(0, 0, 80, 40)), 2.0, "an ordinary wide box is used as-is")
	_assert_eq(SequenceTimeline.cell_aspect(Rect2i(0, -185, 4, 188)), 0.2,
		"E190's 4x188 beam clamps to the measured floor rather than drawing a 1px-wide sprite")
	_assert_eq(SequenceTimeline.cell_aspect(Rect2i(0, 0, 167, 1)), 5.0, "and the 167:1 extreme clamps to the ceiling")
	_assert_eq(SequenceTimeline.cell_aspect(Rect2i()), 1.0, "an empty box falls back to square")


func _test_sprite_quads_composite_every_frame_of_the_frameset() -> void:
	# THE fact that decides the strip: a FRAME opcode selects a FRAMESET, and the
	# renderer draws EVERY frame of it together. One cell = one composited sprite,
	# never one sprite layer.
	var fs: Dictionary = _frameset([
		_frame(Rect2i(0, 0, 8, 8), Rect2i(-8, -8, 8, 8)),
		_frame(Rect2i(8, 0, 8, 8), Rect2i(0, -8, 8, 8)),
	])
	var quads: Array = SequenceTimeline.sprite_quads(fs, Vector2i(0, 10))
	_assert_eq(quads.size(), 2, "both frames of the frameset are drawn, composited")
	var pts: PackedVector2Array = quads[0].get("points")
	_assert_eq(pts.size(), 4, "each frame is one quad of four corners")
	_assert_eq(pts[0], Vector2(-8, 2), "top-left vertex carries the animation offset (-8, -8 + 10)")
	_assert_eq(pts[1], Vector2(-1, 2), "then top-right — an 8-wide quad ends at x+7, vertices being texel indices")
	_assert_eq(pts[2], Vector2(-1, 9), "then bottom-right — winding is tl, tr, br, bl")
	_assert_eq(pts[3], Vector2(-8, 9), "then bottom-left")
	var uvs: PackedVector2Array = quads[1].get("uvs")
	_assert_eq(uvs[0], Vector2(8.5, 0.5),
		"UVs are texel CENTRES (x + 0.5) — the mapping EffectParticleRenderer uses to avoid seams")


func _test_sprite_quads_map_a_mirrored_frame_through_signed_uvs() -> void:
	# A negative uv width is how the corpus stores a mirrored frame: the stored x is
	# the block's LAST column and the sampling walks left. The flip lives in the UVs,
	# so the vertex quad is unchanged and only the UV corners swap ends.
	var fs: Dictionary = _frameset([_frame(Rect2i(39, 40, -32, 32), Rect2i(-16, -16, 32, 32))])
	var quads: Array = SequenceTimeline.sprite_quads(fs, Vector2i.ZERO)
	var uvs: PackedVector2Array = quads[0].get("uvs")
	_assert_eq(uvs[0], Vector2(39.5, 40.5), "the stored x is the RIGHT edge for a mirrored frame")
	_assert_eq(uvs[1], Vector2(8.5, 40.5),
		"and the top-right UV walks LEFT by width-1 (39 - 31), landing on the block's true left column")
	var pts: PackedVector2Array = quads[0].get("points")
	_assert_eq(pts[0], Vector2(-16, -16), "the vertex quad itself is NOT mirrored — the flip is in the UVs alone")


func _test_a_frame_opcode_index_is_relative_to_the_frameset_group() -> void:
	# A FRAME opcode's `frameset` is RELATIVE to the frameset GROUP the playing
	# emitter selects (its `anim_param`): the absolute index is
	# `opcode.frameset + frameset_group_offset(group)` — ParticleAnimator.gd:120. So
	# the SAME sequence resolves to different sprites depending on who plays it, and
	# a viewport that assumed the index was absolute would draw the wrong sprite for
	# the 18 of 401 corpus effects that have more than one group (17 have two, E040
	# has three).
	#
	# The offset arrives as a plain int so this module stays pure — resolving it from
	# an emitter is EffectData.frameset_group_offset's job, the ONE derivation, and
	# this must not become a copy of it.
	var tr: Array = SequenceTimeline.trace(_e190_anim2(), 63)
	_assert_eq(tr[1].get("frameset"), 63, "frameset 0 of group 1 is absolute frameset 63")
	_assert_eq(tr[3].get("frameset"), 64, "and its frameset 1 is 64")
	# Cell 0 adopts the first FRAME's state, so it adopts it ALREADY RESOLVED — the
	# lens is applied once, on the way in, and never a second time on the way out. A
	# pre-FRAME cell that shifted its own -1 by the group would land on 62.
	_assert_eq(tr[0].get("frameset"), 63,
		"the first cell shows what is on screen at t=0, which is the ABSOLUTE frameset")
	_assert_eq(tr[0].get("has_sprite"), true, "and it is a real picture through this lens too")
	# The default is the identity, which is what group 0 means and what 383 of 401
	# effects use.
	var plain: Array = SequenceTimeline.trace(_e190_anim2())
	_assert_eq(plain[1].get("frameset"), 0, "no group offset leaves the stored index alone")


# --- fixtures ---------------------------------------------------------------

## A frame whose quad is `quad` in PSX units. Vertex coordinates are TEXEL INDICES,
## not continuous edges, so a 4-wide quad stores corners at x and x+3 — E190's real
## frame spans vertices 0..3 against a uv width of 4, which is what settles it. That
## makes an extent inclusive (`max - min + 1`), the same convention
## `FramesetCanvas.quad_size` uses.
func _frame(uv: Rect2i, quad: Rect2i) -> Dictionary:
	var rx: int = quad.position.x + quad.size.x - 1
	var by: int = quad.position.y + quad.size.y - 1
	return {
		"uv": {"x": uv.position.x, "y": uv.position.y, "width": uv.size.x, "height": uv.size.y},
		"vertices": {
			"top_left": [quad.position.x, quad.position.y],
			"top_right": [rx, quad.position.y],
			"bottom_left": [quad.position.x, by],
			"bottom_right": [rx, by],
		},
	}


func _frameset(frames: Array) -> Dictionary:
	return {"frames": frames}


# --- harness ----------------------------------------------------------------

func _assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s\n         expected: %s\n         actual:   %s" % [msg, expected, actual])


func _assert_true(cond: bool, msg: String) -> void:
	_assert_eq(cond, true, msg)
