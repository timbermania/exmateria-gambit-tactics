extends Node
## CORPUS invariant sweep for the colour MOVE (ADR-0101 decisions 3-7). The fixture guard
## (`ColourMoveTest`) proves the rule over a hand-built space; this one proves it over the
## SHIPPED distribution — real palette and screen channels, real fold-derived holds.
##
## Why both, and why this one exists at all: the last three bugs in this area had the same
## root — a rule was changed on reasoning about one fixture, and it fired on thousands of
## spans. The invariants Move must never break are stated here directly rather than
## re-derived from a fixture someone thought to write down:
##
##   1. the moved span's WIDTH is preserved
##   2. everything OUTSIDE the two hold runs keeps its length (so its absolute frame is pinned)
##   3. the two runs' combined length is conserved, so the lane's total length never changes
##   4. every written length is STORABLE (1 or a multiple of 8) — nothing silently re-snaps
##   5. the 33-slot budget is never exceeded
##   6. the ROUND TRIP: a slide can be slid straight back, onto the frame it came from, with
##      the budget no worse than it started (see `_check_round_trip` for the one open exclusion)
##
## It also prints the MOVABILITY CENSUS — how many drawn colour spans a Move can actually
## reach, and in which direction. That number is a fact about the shipped data, not about the
## code, and it is the one the author should see when judging whether the hold-run model earns
## its keep on real effects.
##
## Slow by design (loads and FOLDS a sample of the corpus). NOT part of the fast net — run it
## directly:  <GODOT> --path . res://tests/ColourMoveCorpusSweepTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")
const MovePlan = preload("res://src/effects/studio/ColourMovePlan.gd")
const SpacerVerdictsClass = preload("res://src/effects/studio/SpacerVerdicts.gd")
const PaletteChannelClass = preload("res://src/effects/studio/PaletteChannel.gd")
const ScreenChannelClass = preload("res://src/effects/studio/ScreenChannel.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const EffectPhaseClass = ExMateriaEffects.EffectPhase

const EFFECTS_DIR := "res://assets/effects"
## The fold is the studio's most expensive computation, so the sweep samples. A twentieth of
## 401 effects still yields hundreds of real spans across both kinds — enough for a
## distribution, and it keeps the run inside a couple of minutes.
const SAMPLE_EVERY := 20
## Deltas probed per movable span: the two extremes (which is where a run collapses), a
## sub-8 fine slide, and a coarse one.
const PROBE_DELTAS := [-9999, -3, 3, 8, 9999]

var _passed: int = 0
var _failed: int = 0
var _effects: int = 0
var _channels: int = 0
var _drawn: int = 0
var _movable_left: int = 0
var _movable_right: int = 0
var _movable_both: int = 0
var _manufactured: int = 0
var _moves: int = 0
var _round_trips: int = 0
var _landed_at_origin: int = 0
var _slot_gains: int = 0
var _played_before: int = 0
var _one_way: int = 0
var _one_way_samples: Array = []
var _violations: Array = []


func _ready() -> void:
	var dirs := _effect_dirs()
	for k in range(dirs.size()):
		if k % SAMPLE_EVERY != 0:
			continue
		var ed = EffectDataClass.load_from_directory(dirs[k])
		if ed == null:
			continue
		_effects += 1
		var offsets: Dictionary = Lowering.stream_offsets(ed)
		if ed.palette != null:
			for cn in PaletteDataClass.ALL_CHANNELS:
				var pv: Dictionary = SpacerVerdictsClass.palette_verdicts(ed.palette, cn, offsets)
				for phase in EffectPhaseClass.ALL:
					_sweep(ed, ed.palette.get_channel(phase, cn), pv.get(phase, {}),
						{"channel": "palette", "context": phase, "channel_name": cn},
						PaletteChannelClass, dirs[k])
		if ed.screen != null:
			var sv: Dictionary = SpacerVerdictsClass.screen_verdicts(ed.screen, offsets)
			for phase in EffectPhaseClass.ALL:
				_sweep(ed, ed.screen.get_channel(phase), sv.get(phase, {}),
					{"channel": "screen", "context": phase},
					ScreenChannelClass, dirs[k])

	print("[census] %d effects sampled, %d colour channels, %d drawn spans"
		% [_effects, _channels, _drawn])
	print("[census] movable: %d left-only+both, %d right-only+both, %d BOTH directions"
		% [_movable_left, _movable_right, _movable_both])
	print("[census] %d of those needed a MANUFACTURED hold (the fold granted the licence)"
		% _manufactured)
	print("[census] %d real moves applied" % _moves)
	print("[census] %d fine slides slid straight BACK (%d left the channel with MORE free slots)"
		% [_round_trips, _slot_gains])
	print("[census] %d round trips landed the span on played index 0 (was an exclusion; now held to the invariant)"
		% _landed_at_origin)
	print("[census] ONE-WAY (OPEN — the edit changes the fold the planner read; see _check_round_trip): %d could not be slid back"
		% _one_way)
	for smp in _one_way_samples:
		print("           %s" % smp)

	_assert_true(_effects > 15, "the corpus actually loaded (%d effects)" % _effects)
	_assert_true(_drawn > 200, "the sweep found real drawn spans (%d)" % _drawn)
	_assert_true(_moves > 50, "…and real moves to apply (%d)" % _moves)
	_assert_true(_round_trips > 20, "…and real round trips to check (%d)" % _round_trips)
	_assert_eq(_violations.size(), 0,
		"every move in the corpus held all six invariants (first 4: %s)"
			% str(_violations.slice(0, 4)))

	print("\n=== ColourMoveCorpusSweepTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourMoveCorpusSweepTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourMoveCorpusSweepTest")
		get_tree().quit(0)


func _sweep(ed, ch, verdicts: Dictionary, base_ref: Dictionary, channel_class, dir: String) -> void:
	if ch == null or ch.keyframes.is_empty():
		return
	_channels += 1
	var last: int = Lowering.played_last(ch)
	var holds: Array = []
	for i in range(last):
		holds.append(bool(verdicts.get(i, false)) and _enabled(ch.keyframes[i], base_ref))
	var session = Session.new(ed)
	for n in range(last):
		if bool(holds[n]):
			continue
		_drawn += 1
		var ref: Dictionary = base_ref.duplicate()
		ref["event_index"] = n
		var ctx: Dictionary = channel_class.move_context(ed, ref)
		if ctx.is_empty():
			continue
		var bounds := MovePlan.hold_run_bounds(holds, n)
		var p: int = int(bounds["p"])
		var q: int = int(bounds["q"])
		var can_left: bool = int(MovePlan.plan(ctx["durations"], holds, n, -9999,
			int(ctx["free_slots"]))["delta"]) < 0
		var can_right: bool = int(MovePlan.plan(ctx["durations"], holds, n, 9999,
			int(ctx["free_slots"]))["delta"]) > 0
		if can_left:
			_movable_left += 1
		if can_right:
			_movable_right += 1
		if can_left and can_right:
			_movable_both += 1
		if (p == n and can_right) or (q == n + 1 and can_left):
			_manufactured += 1
		if not (can_left or can_right):
			continue
		for d in PROBE_DELTAS:
			var snap: Dictionary = channel_class.snapshot(ed, ref)
			var before: Array = Lowering.durations(ch.keyframes)
			var before_used: int = int(ch.max_keyframe)
			var played_before: int = Lowering.played_last(ch)
			var res: Dictionary = channel_class.move_span(ed, ref, int(d), ctx)
			if not res.is_empty():
				_moves += 1
				_check(ch, before, before_used, p, q, n, int(res["delta"]),
					int(res.get("event_index", -1)), ref, dir)
				# The fine deltas are where the budget flip lives; round-tripping all five
				# would quintuple the fold cost for no extra coverage.
				if absi(int(d)) == 3:
					_played_before = played_before
					_check_round_trip(ed, ch, channel_class, ref, int(res["delta"]),
						int(res.get("event_index", -1)), before, before_used, dir, n)
			channel_class.restore(ed, snap)   # leave the shared EffectData cache pristine


## The five invariants, against the pre-edit duration array. `moved` is the plan's own report
## of where the span landed — derived by the code under test, then checked, rather than
## re-derived here by a second implementation of the same arithmetic.
func _check(ch, before: Array, before_used: int, p: int, q: int, n: int, delta: int,
		moved: int, ref: Dictionary, dir: String) -> void:
	var after: Array = Lowering.durations(ch.keyframes)
	var grew: int = after.size() - before.size()
	var label := "%s %s/%s[%d] d=%d" % [dir.get_file(), str(ref.get("channel", "")),
		str(ref.get("context", "")), n, delta]

	# 1 — the moved span's WIDTH.
	if moved < 0 or moved >= after.size() or int(after[moved]) != int(before[n]):
		_violate("%s: the span's %d-frame width did not survive (landed at %d)"
			% [label, int(before[n]), moved])
	# 2 — everything OUTSIDE the two hold runs keeps its length, so its absolute frame is pinned.
	if before.slice(0, p) != after.slice(0, p):
		_violate("%s: a keyframe before the lead run changed" % label)
	if before.slice(q) != after.slice(q + grew):
		_violate("%s: a keyframe after the trailing run changed" % label)
	# 3 — the block the two runs and the span occupy conserves its length.
	var before_block: int = _sum(before.slice(p, q))
	var after_block: int = _sum(after.slice(p, q + grew))
	if before_block != after_block:
		_violate("%s: the run block changed length %d → %d" % [label, before_block, after_block])
	# 4 — every written length is STORABLE (1 or a multiple of 8); nothing re-snapped silently.
	for i in range(p, mini(q + grew, after.size())):
		if not Lowering.is_faithful(int(after[i])):
			_violate("%s: wrote an unstorable length %d" % [label, int(after[i])])
	# 5 — the 33-slot budget.
	if int(ch.max_keyframe) > Lowering.NATIVE_KEYFRAME_SLOTS:
		_violate("%s: max_keyframe %d over the 33-slot budget (was %d)"
			% [label, int(ch.max_keyframe), before_used])


## INVARIANT 6 — the ROUND TRIP, which is the fault the author reported: *"once you move it, it
## doesn't let you move back to the position you started."* Slide the span back by exactly what
## it moved, from a **fresh context**, because that is what a second grab does — and the fresh
## context is the whole point. The first slide SPENT slots, and `EffectEditSession.begin_move`
## re-reads the budget every grab, so the return used to be planned in eights past the frame it
## came from (decision 4's degrade firing on the trip that RECOVERS the slots, not one that
## spends them). Measured witnesses before the fix: E003 for_each/target #1, E023
## phase1/affected_units #2.
##
## The index-0 EXCLUSION IS RETIRED (ADR-0101 decision 6's narrowing). It read: a slide that
## lands the span on played index 0 is stuck there, because a colour span at the phase origin
## cannot grow a lead — its only candidate padding would be a copy of ITSELF placed before it,
## which changes when the tint arrives, and the fold refused it. That was true of the COPY, not
## of padding: a minted Δ0 identity has no bytes to be wrong about, so index 0 grows a lead like
## anywhere else and the return is now ATTEMPTED rather than skipped. `_landed_at_origin` still
## counts the population so the retirement is visible, but those trips are held to the same
## invariant as every other.
func _check_round_trip(ed, ch, channel_class, ref: Dictionary, delta: int, moved: int,
		before: Array, before_used: int, dir: String, n: int) -> void:
	if delta == 0 or moved < 0:
		return
	if moved == 0:
		_landed_at_origin += 1        # counted, no longer excused — the check below runs
	var back_ref: Dictionary = ref.duplicate()
	back_ref["event_index"] = moved
	var back_ctx: Dictionary = channel_class.move_context(ed, back_ref)
	if back_ctx.is_empty():
		_violate("%s %s[%d] d=%d: the landed span has no move context at all"
			% [dir.get_file(), str(ref.get("channel", "")), n, delta])
		return
	var back: Dictionary = channel_class.move_span(ed, back_ref, -delta, back_ctx)
	_round_trips += 1
	var label := "%s %s/%s/%s[%d] out %+d -> %d" % [dir.get_file(),
		str(ref.get("channel", "")), str(ref.get("context", "")),
		str(ref.get("channel_name", "-")), n, delta, moved]
	var lead_back: int = _run_frames(back_ctx, moved, true)
	var trail_back: int = _run_frames(back_ctx, moved, false)
	var landed_is_hold: bool = moved < back_ctx["holds"].size() and bool(back_ctx["holds"][moved])
	if back.is_empty() or int(back.get("delta", 0)) == 0:
		# OPEN, ADR-level, so COUNTED rather than asserted — never silently passed. The root is
		# `ColourMovePlan` reasoning over a hold vector taken BEFORE the edit, where the edit
		# CHANGES what the fold says, so the out trip leaves a lane the return's planner does not
		# recognise. THREE shipped shapes were recorded here; decision 6's narrowing (padding is
		# MINTED where a run is empty, not copied) retired two of them:
		#
		#   • RETIRED — the manufactured padding did not read back as a hold. The old licence
		#     (`PaletteChannel._manufactured_hold_is_inert`, now deleted) probed ONE copy of
		#     `STEP` frames while `_seq_for` wrote as many ONE-frame copies as the residual
		#     needed. Witnesses E158 / E311 `for_each/target` #1 and E065 / E372 `phase1/target`
		#     #2 all came back with `lead == 0`; none of them appears any more. A minted Δ0
		#     identity is inert whatever it sits next to and however many of them there are.
		#   • RETIRED — decision 7's collapse was one-way wherever that side's manufacture
		#     licence was not granted, and at played index 0 it never could be, so a span slid
		#     onto the phase origin was stuck in BOTH directions (E012, E016, E066). Those trips
		#     are no longer excused at all: `_landed_at_origin` counts them and they run the full
		#     invariant below.
		#   • STILL OPEN — the MOVED SPAN itself reads back as a hold, so the planner refuses to
		#     address it ("a hold is empty space, not a movable span"). E510 `for_each` #0/#4 on
		#     both the palette and the screen arm: after the slide the whole played window folds
		#     inert but index 0. This one is not about padding — the span's own bytes go
		#     redundant in the position it lands on — so the narrowing does not touch it.
		#
		# It also means the Move CHANGED WHAT IS RENDERED, which decision 3 forbids outright, so
		# it stays the serious one — "it won't go back" is how the author meets it, not what it is.
		if landed_is_hold or lead_back == 0 or trail_back == 0:
			_one_way += 1
			if _one_way_samples.size() < 8:
				_one_way_samples.append("%s (%s, lead %d, trail %d, %d free)" % [label,
					"the landed span now folds INERT" if landed_is_hold else "an emptied run",
					lead_back, trail_back, int(back_ctx["free_slots"])])
			return
		_violate("%s: the return was REFUSED with room on both sides (lead %d, trail %d, %d free)"
			% [label, lead_back, trail_back, int(back_ctx["free_slots"])])
		return
	var got: int = int(back.get("delta", 0))
	if got != -delta:
		_violate("%s: the return moved %+d, not %+d (%d free slots)"
			% [label, got, -delta, int(back_ctx["free_slots"])])
		return
	# The PICTURE must be exactly what it was — the span back on its own start frame, and the
	# lane the same total length. NOT the hold runs' internal keyframe split: a run is the unit
	# decision 7 reasons about, so a 48-frame lead stored as `32 + 16` coming back as one `48`
	# keyframe is the same picture and one slot cheaper (E043 for_each/affected_units #3 does
	# exactly that). Asserting byte-equality there would flag a lossless compaction as a fault.
	var after: Array = Lowering.durations(ch.keyframes)
	var landed: int = int(back.get("event_index", -1))
	if landed < 0 or _sum(after.slice(0, landed)) != _sum(before.slice(0, n)):
		_violate("%s: the span is back but not on its own start frame (%d, was %d)"
			% [label, _sum(after.slice(0, maxi(0, landed))), _sum(before.slice(0, n))])
		return
	if _sum(after.slice(0, Lowering.played_last(ch))) != _sum(before.slice(0, _played_before)):
		_violate("%s: the lane's played length changed across the round trip" % label)
		return
	# The BUDGET may end up BETTER than it started (the compaction above recovers a slot) but
	# never worse — a round trip that leaks a keyframe every time is what decision 7 exists to
	# stop, and it is how the camera arm of this same bug was found (commit cc629e25e).
	if int(ch.max_keyframe) > before_used:
		_violate("%s: the round trip LEAKED slots (max_keyframe %d, was %d)"
			% [label, int(ch.max_keyframe), before_used])
		return
	if int(ch.max_keyframe) < before_used:
		_slot_gains += 1


## Frames of hold on one side of played span `n`, from a move context — for the refusal report.
func _run_frames(ctx: Dictionary, n: int, lead: bool) -> int:
	var holds: Array = ctx["holds"]
	var durs: Array = ctx["durations"]
	if n < 0 or n >= holds.size():
		return -1
	var b := MovePlan.hold_run_bounds(holds, n)
	var total := 0
	if lead:
		for i in range(int(b["p"]), n):
			total += int(durs[i])
	else:
		for i in range(n + 1, int(b["q"])):
			total += int(durs[i])
	return total


func _sum(a: Array) -> int:
	var t: int = 0
	for v in a:
		t += int(v)
	return t


func _enabled(kf, base_ref: Dictionary) -> bool:
	if String(base_ref.get("channel", "")) == "screen":
		return not ScreenChannelClass.is_author_disabled(kf)
	return bool(kf.enabled)


func _violate(msg: String) -> void:
	if _violations.size() < 30:
		_violations.append(msg)


func _effect_dirs() -> Array:
	var out: Array = []
	var da := DirAccess.open(EFFECTS_DIR)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if da.current_is_dir() and name.begins_with("E"):
			out.append("%s/%s" % [EFFECTS_DIR, name])
		name = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
