extends Node

## Pure-ish tests for `DialogueOverlay.advance_frames` semantics.
##
## Validates the typewriter contract that backs the scenario-1 chapel
## prayer (PC=42) and that the rest of the overlay layer will consume:
##
##   * `{Delay N}` consumes exactly N display frames (no off-by-one at
##     either end).
##   * Text tokens type one glyph per frame.
##   * Control tokens (color/newline) drain freely between frames.
##   * Reaching end-of-tokens deactivates the overlay + emits `completed`.
##   * `show_overlay` + `clear` round-trip without leaking state.
##
## Run via: <GODOT> --path . --quit-after 5 res://tests/DialogueOverlayTest.tscn

const DialogueOverlayClass = preload("res://src/scenarios/DialogueOverlay.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_pure_text_types_one_glyph_per_frame()
	_test_delay_spends_exact_frames()
	_test_color_and_newline_drain_free()
	_test_completion_emits_signal_and_deactivates()
	_test_clear_resets_state()
	_test_chapel_prayer_full_advance()
	_test_production_cadence_golden()
	_test_sticky_budget_little_money()
	_test_default_budget_types_at_factor()
	_test_delay_token_cost_is_budget_times_factor()
	_test_split_pages_and_content_lines()
	_test_valign_center_placement()
	_test_multipage_advance_holds_active()
	_test_boxtype0_self_dismisses_without_external_clear()

	print("\n=== DialogueOverlayTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DialogueOverlayTest")
		get_tree().quit(1)
	else:
		print("[PASS] DialogueOverlayTest")
		get_tree().quit(0)


func _make_overlay() -> DialogueOverlayClass:
	var ov: DialogueOverlayClass = DialogueOverlayClass.new()
	add_child(ov)
	# throttle=2 → factor (3−throttle)=1, so the sticky budget maps 1:1 to frames:
	# a plain glyph (budget 1) costs 1 frame and a {Delay N} costs N frames. The
	# "N frames in, K glyphs typed" assertions then read the walker mechanics
	# directly. (Production is throttle=1 → factor 2 — see the golden test.)
	ov.throttle = 2
	return ov


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


# ---------- tests ----------

func _test_pure_text_types_one_glyph_per_frame() -> void:
	var ov := _make_overlay()
	ov.show_overlay([
		{"type": "text", "value": "abc"},
	], 0, 60)
	ov.advance_frames(1)
	_assert_eq(ov.current_text, "a", "pure text: 1 frame → 'a'")
	ov.advance_frames(2)
	_assert_eq(ov.current_text, "abc", "pure text: 3 frames → 'abc'")
	ov.queue_free()


func _test_delay_spends_exact_frames() -> void:
	var ov := _make_overlay()
	# {Delay 5} should consume exactly 5 frames with no glyph typed, then
	# the next frame types the first glyph of "x".
	ov.show_overlay([
		{"type": "delay", "frames": 5},
		{"type": "text",  "value": "x"},
	], 0, 60)
	ov.advance_frames(4)
	_assert_eq(ov.current_text, "", "delay 5: after 4 frames no glyph")
	_assert_true(ov.is_active(), "delay 5: still active mid-delay")
	ov.advance_frames(1)
	_assert_eq(ov.current_text, "", "delay 5: 5 frames in, still no glyph (delay drains)")
	ov.advance_frames(1)
	_assert_eq(ov.current_text, "x", "delay 5: 6th frame types first glyph")
	ov.queue_free()


func _test_color_and_newline_drain_free() -> void:
	var ov := _make_overlay()
	ov.show_overlay([
		{"type": "color",   "palette": 8},
		{"type": "text",    "value": "A"},
		{"type": "newline"},
		{"type": "color",   "palette": 0},
		{"type": "text",    "value": "b"},
	], 0, 60)
	# Frame 1: drains color → types 'A'.
	ov.advance_frames(1)
	_assert_eq(ov.current_text, "A", "control drain: frame 1 → 'A'")
	_assert_eq(ov.palette, 8, "control drain: palette set by free color")
	# Frame 2: drains newline + color → types 'b'.
	ov.advance_frames(1)
	_assert_eq(ov.current_text, "A\nb", "control drain: frame 2 → 'A\\nb'")
	_assert_eq(ov.palette, 0, "control drain: palette flipped by second color")
	ov.queue_free()


func _test_completion_emits_signal_and_deactivates() -> void:
	var ov := _make_overlay()
	var emitted := [false]
	ov.completed.connect(func() -> void: emitted[0] = true)
	ov.show_overlay([{"type": "text", "value": "ab"}], 0, 60)
	ov.advance_frames(2)
	_assert_eq(ov.current_text, "ab", "completion: full text typed")
	# One more frame ticks past end-of-tokens; the completed signal fires and the
	# box-type-0 overlay begins its SELF-DISMISS fade (still active while fading).
	ov.advance_frames(1)
	_assert_true(emitted[0], "completion: signal emitted")
	_assert_true(ov.is_active(), "completion: overlay auto-dismiss fade in flight (still active)")
	# Drive the fade ramp to the floor → the overlay hides and deactivates.
	ov.advance_frames(20)
	_assert_true(not ov.is_active(), "completion: overlay inactive after auto-dismiss fade")
	_assert_eq(ov.current_text, "", "completion: text gone after auto-dismiss")
	ov.queue_free()


func _test_clear_resets_state() -> void:
	var ov := _make_overlay()
	ov.show_overlay([{"type": "text", "value": "abc"}], 0, 60)
	ov.advance_frames(2)
	# clear() with visible text begins the ROM dismiss FADE (Part A), not an
	# instant hide; the overlay stays active until the ramp completes.
	ov.clear()
	_assert_true(ov.is_active(), "clear: overlay fading after dismiss")
	ov.advance_frames(20)
	_assert_eq(ov.current_text, "", "clear: text cleared after fade")
	_assert_true(not ov.is_active(), "clear: overlay inactive after fade")
	# A fresh show_overlay cancels any fade and must not resume from the old state.
	ov.show_overlay([{"type": "text", "value": "xy"}], 0, 60)
	ov.advance_frames(1)
	_assert_eq(ov.current_text, "x", "clear: fresh show_overlay types from start")
	ov.queue_free()


# Lock down the chapel-prayer (PC=42) token list against the typewriter.
# Cumulative frame budget should land on visible milestones — picks up on
# any future Delay-unit semantic change.
func _test_chapel_prayer_full_advance() -> void:
	var ov := _make_overlay()
	# Source: scenario_1_chunk.json PC=42 dialogue.tokens, locked down by
	# tools/test_chunk_text_bake.py.
	var prayer: Array = [
		{"type": "delay",   "frames": 0x05},
		{"type": "text",    "value": "\"God,"},
		{"type": "delay",   "frames": 0x0F},
		{"type": "text",    "value": " "},
		{"type": "delay",   "frames": 0x05},
		{"type": "text",    "value": "please help us"},
		{"type": "newline"},
		{"type": "text",    "value": "sinful children of Ivalice"},
		{"type": "delay",   "frames": 0x3C},
		{"type": "text",    "value": "."},
		{"type": "delay",   "frames": 0x01},
	]
	ov.show_overlay(prayer, 0, 0x3C)
	# Sticky model at factor 1 (throttle=2): budget starts at the leading
	# {Delay 05}=5, so "God," types at 5 frames/glyph; the space inherits
	# {Delay 0F}=15 (one 15-frame glyph); {Delay 05} restores 5 for the rest.
	# Absolute-frame seeks (running total via `_at`).
	var _at := [0]
	var seek := func(target: int) -> void:
		ov.advance_frames(target - _at[0])
		_at[0] = target
	# Opening {Delay 05} = 5 frames; first glyph '"' at f=6.
	seek.call(5)
	_assert_eq(ov.current_text, "", "prayer: 5 delay frames → no text")
	seek.call(6)
	_assert_eq(ov.current_text, "\"", "prayer: f=6 first glyph")
	# "God," at 5 frames/glyph (budget 5): ',' (glyph 5) at f=6+4*5=26.
	seek.call(26)
	_assert_eq(ov.current_text, "\"God,", "prayer: f=26 through '\"God,'")
	# {Delay 0F}=15 frames, then the space (itself a 15-frame glyph) at f=46.
	seek.call(45)
	_assert_eq(ov.current_text, "\"God,", "prayer: f=45 still in {Delay 0F}")
	seek.call(46)
	_assert_eq(ov.current_text, "\"God, ", "prayer: f=46 space typed (budget 15)")
	# {Delay 05} restores budget 5; "please help us" (14 glyphs) ends at f=131.
	seek.call(131)
	_assert_eq(ov.current_text, "\"God, please help us",
		"prayer: f=131 first line complete")
	# Newline drains free; "sinful children of Ivalice" (26 glyphs @5) ends f=261.
	seek.call(261)
	_assert_eq(
		ov.current_text,
		"\"God, please help us\nsinful children of Ivalice",
		"prayer: f=261 second line complete",
	)
	# {Delay 3C}=60 frames, then '.' (a 60-frame glyph) at f=326.
	seek.call(325)
	_assert_true(ov.is_active(), "prayer: still active during 0x3C delay")
	seek.call(326)
	_assert_eq(
		ov.current_text,
		"\"God, please help us\nsinful children of Ivalice.",
		"prayer: f=326 '.' typed after long delay",
	)
	# Trailing {Delay 01} then end-of-tokens completes → box-type-0 self-dismiss
	# fade runs; a large batch types the rest AND drives the fade to the floor.
	ov.advance_frames(200)
	_assert_true(not ov.is_active(), "prayer: self-dismissed (typed + auto-faded) after trailing delay")
	ov.queue_free()


# GOLDEN CADENCE — the same prayer, but at the PRODUCTION throttle (default 1 →
# factor 3−throttle = 2), resolved from the live PSX capture
# (TYPEWRITER_TEXT_CADENCE.md §7.1). The prior test pins throttle=2 (factor 1) to
# read the walker's discrete mechanics; THIS one guards the real on-screen speed.
#
# Sticky-budget schedule: budget starts at the leading {Delay 05}=5, so "God, "
# types at 5·2=10 VBlanks/glyph; the space inherits {Delay 0F}=15 (a single
# 15·2=30 VBlank glyph — this is what shifts everything after it +20 vs the old
# additive model, which mis-charged the space at a flat 10); {Delay 05} restores
# budget 5 for the rest, and {Delay 3C}=60 makes the final '.' a 60·2=120 VBlank
# glyph. Reveal ORDER is unchanged from the old golden; only the frame indices
# after the space shift by +20 (the corrected sticky space cost).
func _test_production_cadence_golden() -> void:
	var ov: DialogueOverlayClass = DialogueOverlayClass.new()
	add_child(ov)
	# Do NOT override the tunable — assert the shipped default.
	_assert_eq(ov.throttle, 1, "golden: production throttle default = 1 (factor 2)")

	# Same token list as _test_chapel_prayer_full_advance (scenario_1 PC=42).
	var prayer: Array = [
		{"type": "delay",   "frames": 0x05},
		{"type": "text",    "value": "\"God,"},
		{"type": "delay",   "frames": 0x0F},
		{"type": "text",    "value": " "},
		{"type": "delay",   "frames": 0x05},
		{"type": "text",    "value": "please help us"},
		{"type": "newline"},
		{"type": "text",    "value": "sinful children of Ivalice"},
		{"type": "delay",   "frames": 0x3C},
		{"type": "text",    "value": "."},
		{"type": "delay",   "frames": 0x01},
	]
	ov.show_overlay(prayer, 0, 0x3C)

	# Absolute-frame milestones (each computed from f(k) above). We advance the
	# cursor to each absolute frame and assert the revealed text. `_seek` tracks
	# the running frame total so each step is the delta from the previous.
	var _at := [0]  # boxed running frame total for the closure
	var seek := func(target: int) -> void:
		ov.advance_frames(target - _at[0])
		_at[0] = target

	# Opening {Delay 05} = 5·2=10 frames; glyph 1 ('"') at f=11.
	seek.call(10)
	_assert_eq(ov.current_text, "", "golden: f=10 still in opening delay")
	seek.call(11)
	_assert_eq(ov.current_text, "\"", "golden: f=11 first glyph")
	# "God," at budget 5 → 10 frames/glyph; ',' (glyph 5) at f=11+4*10=51.
	seek.call(51)
	_assert_eq(ov.current_text, "\"God,", "golden: f=51 through '\"God,'")
	# ',' cools 10, then {Delay 0F}=15 adds 30 → the space at f=91 (unchanged).
	seek.call(90)
	_assert_eq(ov.current_text, "\"God,", "golden: f=90 still in {Delay 0F}")
	seek.call(91)
	_assert_eq(ov.current_text, "\"God, ", "golden: f=91 space typed")
	# The space is a budget-15 glyph → costs 30 (not the old flat 10); {Delay 05}
	# then restores budget 5. "please help us" (14 glyphs @10) ends at f=261
	# (= 91 + 30 space + 10 delay05 + 13*10) — +20 vs the old additive f=241.
	seek.call(261)
	_assert_eq(ov.current_text, "\"God, please help us",
		"golden: f=261 first line complete (newline not yet drained)")
	# "sinful children of Ivalice" (26 glyphs @10) ends at f=261+26*10=521.
	seek.call(521)
	_assert_eq(ov.current_text, "\"God, please help us\nsinful children of Ivalice",
		"golden: f=521 second line complete")
	# The '.' waits out {Delay 3C}=60 → 120 frames: f=521+10 cool+120 = 651.
	seek.call(650)
	_assert_eq(ov.current_text, "\"God, please help us\nsinful children of Ivalice",
		"golden: f=650 still in {Delay 3C} before '.'")
	seek.call(651)
	_assert_eq(ov.current_text, "\"God, please help us\nsinful children of Ivalice.",
		"golden: f=651 final '.' typed")
	ov.queue_free()


# STICKY BUDGET — the ROM's per-glyph cost is a sticky `budget` (init 1) that
# each {Delay NN} sets to NN and that persists across subsequent glyphs until
# the next {Delay}. Every glyph AND every delay costs `budget·(3−throttle)`
# VBlanks (throttle default 1 → factor 2). See TYPEWRITER_TEXT_CADENCE.md §7.1.
#
# This is the scenario-8 "…little money…" case: after a {Delay 19}=25, the run
# of glyphs types SLOWLY at 25·2=50 VBlanks/glyph — NOT a single pause then
# fast typing (the old additive model's bug).
func _test_sticky_budget_little_money() -> void:
	var ov: DialogueOverlayClass = DialogueOverlayClass.new()
	add_child(ov)
	# Production defaults (throttle=1 → factor 2). Do NOT override.
	ov.show_overlay([
		{"type": "delay", "frames": 0x05},   # budget=5, cost 10
		{"type": "text",  "value": "ab"},    # a@f11, b@f21 (5·2=10 each)
		{"type": "delay", "frames": 0x19},   # budget=25, cost 50
		{"type": "text",  "value": "cd"},    # c@f81, d@f131 (25·2=50 each)
	], 0, 60)
	# a and b type at budget 5 (10 frames each).
	ov.advance_frames(21)
	_assert_eq(ov.current_text, "ab", "sticky: f=21 'ab' typed at budget 5")
	# After {Delay 19}: 50-frame delay, then 'c' at f=81.
	ov.advance_frames(59)  # → f=80
	_assert_eq(ov.current_text, "ab", "sticky: f=80 still in {Delay 19} before 'c'")
	ov.advance_frames(1)   # → f=81
	_assert_eq(ov.current_text, "abc", "sticky: f=81 'c' typed after {Delay 19}")
	# 'd' costs budget 25 → 50 frames (the "slows down" behavior). It is NOT at
	# f=91 (which is where the old additive fixed-glyph-cost model put it).
	ov.advance_frames(10)  # → f=91
	_assert_eq(ov.current_text, "abc", "sticky: f=91 'd' NOT yet typed (budget 25, not fixed 10)")
	ov.advance_frames(40)  # → f=131
	_assert_eq(ov.current_text, "abcd", "sticky: f=131 'd' typed 50 frames after 'c'")
	ov.queue_free()


# DEFAULT BUDGET = 1 — a message with no leading {Delay} types at budget 1, i.e.
# 1·(3−throttle) frames/glyph. At production throttle=1 that is 2 frames/glyph.
func _test_default_budget_types_at_factor() -> void:
	var ov: DialogueOverlayClass = DialogueOverlayClass.new()
	add_child(ov)  # production default throttle=1 → factor 2
	ov.show_overlay([{"type": "text", "value": "abc"}], 0, 60)
	ov.advance_frames(1)
	_assert_eq(ov.current_text, "a", "default budget: f=1 'a' (typed on first frame)")
	ov.advance_frames(1)
	_assert_eq(ov.current_text, "a", "default budget: f=2 still 'a' (2 frames/glyph)")
	ov.advance_frames(1)
	_assert_eq(ov.current_text, "ab", "default budget: f=3 'b' at 2 frames/glyph")
	ov.advance_frames(2)
	_assert_eq(ov.current_text, "abc", "default budget: f=5 'abc'")
	ov.queue_free()


# DELAY COST = budget·(3−throttle) — the {Delay NN} token itself sleeps its
# just-set budget, and that budget persists to the following glyphs. At factor 2
# a {Delay 03} costs 3·2=6 frames and the next glyph also costs 6.
func _test_delay_token_cost_is_budget_times_factor() -> void:
	var ov: DialogueOverlayClass = DialogueOverlayClass.new()
	add_child(ov)  # factor 2
	ov.show_overlay([
		{"type": "delay", "frames": 0x03},   # budget=3, cost 6
		{"type": "text",  "value": "xy"},    # x@f7, y@f13 (3·2=6 each)
	], 0, 60)
	ov.advance_frames(6)
	_assert_eq(ov.current_text, "", "delay cost: f=6 {Delay 03} still draining (3*2=6)")
	ov.advance_frames(1)
	_assert_eq(ov.current_text, "x", "delay cost: f=7 'x' after 6-frame delay")
	ov.advance_frames(5)
	_assert_eq(ov.current_text, "x", "delay cost: f=12 'y' not yet (budget 3 persists → 6 frames)")
	ov.advance_frames(1)
	_assert_eq(ov.current_text, "xy", "delay cost: f=13 'y' typed 6 frames after 'x'")
	ov.queue_free()


# ---------- pagination + valign (scenario-8 narration, §Z.3/§Z.6) ----------

func _make_lines(n: int) -> Array:
	# n content lines, each a single-glyph text token, newline-separated.
	var t: Array = []
	for i in range(n):
		if i > 0:
			t.append({"type": "newline"})
		t.append({"type": "text", "value": "x"})
	return t


func _narration_two_pages() -> Array:
	# A {Delay 3C}-followed-by-newline+text is a page break; leading blank lines
	# are stripped. Yields 2 pages of 2 content lines each.
	return [
		{"type": "text", "value": " "}, {"type": "newline"},              # blank lead (stripped)
		{"type": "delay", "frames": 2}, {"type": "text", "value": "AB"}, {"type": "newline"},
		{"type": "text", "value": "CD"}, {"type": "delay", "frames": 0x3C}, {"type": "text", "value": "."},
		{"type": "newline"},                                              # PAGE BREAK
		{"type": "text", "value": " "}, {"type": "newline"},              # blank lead p2 (stripped)
		{"type": "delay", "frames": 2}, {"type": "text", "value": "EF"}, {"type": "newline"},
		{"type": "text", "value": "GH"},
	]


func _test_split_pages_and_content_lines() -> void:
	var ov := _make_overlay()
	var pages := ov._split_pages(_narration_two_pages())
	_assert_eq(pages.size(), 2, "split: 2 pages at {Delay 3C}+newline")
	_assert_eq(ov._count_content_lines(pages[0]), 2, "split: page 0 = 2 content lines")
	_assert_eq(ov._count_content_lines(pages[1]), 2, "split: page 1 = 2 content lines")
	# The prayer shape — {Delay 3C} with only "." + end after it — stays ONE page.
	var single := [
		{"type": "text", "value": "a"}, {"type": "newline"}, {"type": "text", "value": "b"},
		{"type": "delay", "frames": 0x3C}, {"type": "text", "value": "."},
	]
	_assert_eq(ov._split_pages(single).size(), 1, "split: trailing {Delay 3C} stays single page (prayer)")
	ov.queue_free()


func _test_valign_center_placement() -> void:
	var ov := _make_overlay()
	ov.dialog_byte = 0x0B  # Center (narration)
	ov._page_idx = 0
	ov._pages = [_make_lines(3)]
	_assert_eq(int(round(ov._first_line_psx_y(0))), 92, "center 3 lines → top 92 (116−24)")
	ov._pages = [_make_lines(5)]
	_assert_eq(int(round(ov._first_line_psx_y(0))), 76, "center 5 lines → top 76 (116−40)")
	ov._pages = [_make_lines(6)]
	_assert_eq(int(round(ov._first_line_psx_y(0))), 76, "center 6 lines → CLAMPED to top margin 76")
	# valign=Top (prayer, Dialog 0x09) passes the authored Y through unchanged.
	ov.dialog_byte = 0x09
	ov._pages = [_make_lines(2)]
	_assert_eq(int(round(ov._first_line_psx_y(60))), 60, "top valign → authored Y=60")
	ov.queue_free()


# The load-bearing scenario-8 fix: a box-type-0 overlay dismisses ITSELF after the
# message ends — no clear() call, no next Display Message, no input. (Before this,
# the narration lingered until the far-downstream PC54 box, so it "never went
# away".) Same mechanism as the chapel prayer; §Z.9 / TYPEWRITER_TEXT_CADENCE §7.1.
func _test_boxtype0_self_dismisses_without_external_clear() -> void:
	var ov := _make_overlay()
	ov.show_overlay([{"type": "text", "value": "hi"}], 0, 0, 0, 0x0B)
	# Catch the fade the moment it arms (single-frame stepping, as ScenarioVM pumps).
	var saw_fade := false
	for _i in range(60):
		if ov._fading:
			saw_fade = true
			break
		ov.advance_frames(1)
	_assert_true(saw_fade, "self-dismiss: fade arms on completion (no clear() called)")
	# Drive it to the floor — the overlay hides itself with NO external clear().
	ov.advance_frames(40)
	_assert_true(not ov.is_active(), "self-dismiss: overlay gone with NO external clear()")
	_assert_eq(ov.current_text, "", "self-dismiss: text cleared by itself")
	ov.queue_free()


func _test_multipage_advance_holds_active() -> void:
	var ov := _make_overlay()
	ov.show_overlay(_narration_two_pages(), 0, 0, 0, 0x0B)
	_assert_eq(ov._pages.size(), 2, "multipage: show_overlay split into 2 pages")
	var saw_page1 := false
	var saw_gh := false
	var prog := ov.overlay_progress()
	var monotonic := true
	for _f in range(400):
		if ov._page_idx == 1:
			saw_page1 = true
		if ov.current_text.find("GH") >= 0:
			saw_gh = true       # page-2 fully typed (before the self-dismiss fade clears it)
		if not ov.is_active():
			break
		var np: int = ov.overlay_progress()
		if np < prog:
			monotonic = false
		prog = np
		ov.advance_frames(1)
	# The barrier (is_active) must stay true until BOTH pages are fully typed AND
	# the last page's self-dismiss fade has run — this is what keeps {33} Color
	# Field from firing before the narration is gone.
	_assert_true(saw_page1, "multipage: advanced to page 1 while still active (barrier held across pages)")
	_assert_true(monotonic, "multipage: overlay_progress monotonic across the page clear")
	_assert_true(saw_gh, "multipage: last page fully typed before self-dismiss")
	_assert_true(not ov.is_active(), "multipage: inactive only after the last page auto-dismisses")
	_assert_eq(ov.current_text, "", "multipage: text gone after self-dismiss fade")
	ov.queue_free()
