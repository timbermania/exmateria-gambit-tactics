extends Node
## CORPUS invariant sweep for CLOSING A CAMERA HOLD to zero width — the rule the boundary-drag
## clamp was relaxed to allow (EffectStudioPage._camera_edge_local_frame), and the one MOVE has
## always written when it slides the first event back to the phase origin.
##
## Why it exists: the fix removes a floor that fired on EVERY hold in EVERY camera lane, and
## the fixture guard (`EffectStudioEdgeDragWiringTest`) proves it over three hand-built lanes.
## This one asserts it over the SHIPPED distribution instead — every effect, every phase table,
## every sub-channel lane — because the last several bugs in this area had the same root: a rule
## was changed on reasoning about one fixture and it fired on thousands of spans.
##
## For every hidden hold in the corpus, closing it to its own start must hold:
##
##   1. every OTHER event in its lane keeps its end_frame (a closure is local)
##   2. the drawn event AFTER it starts where the hold began — the gap really closes
##   3. the two SIBLING sub-channel lanes are unchanged, event for event
##   4. the lane re-reads through parse∘lower as exactly what was written (no silent re-order)
##   5. the compiled keyframe count never grows by more than the one split a moved keyframe
##      can cost (leaving a coalesced group)
##
## And the MOVE ROUND TRIP, over every movable span the corpus has: slide it as far as it goes
## and slide it straight back, and the lane's whole event stream — ends, command words, values —
## must be exactly what it was. The author reported the failure of this one directly: "when we
## move, we are creating a left spacer, but when we go to move all the way back to the start it
## isn't deleting the spacer". A parked zero-width hold renders as nothing, so only the storage
## shows it (ADR-0101 decision 7).
##
## Plus the invariant that makes all five meaningful, checked on every table BEFORE any
## closure: `parse(lower(parse(t)))` reproduces `parse(t)` — `lower`'s own stated contract.
## Two shipped tables (E160/phase1, E256/for_each) already violated it, because both carry two
## events of ONE sub-channel at ONE end_frame and the tie-break was a global group-creation
## counter rather than each lane's own order. That is the same tie a zero-width hold creates,
## which is why relaxing the drag clamp is what surfaced it.
##
## It also prints the HOLD CENSUS — how many camera holds the corpus actually has, how many sit
## at a phase origin (the reported case's population), and how often a closure costs a slot.
## That is a fact about the shipped data, not about the code.
##
## Slow-ish (loads every effect's camera tables; no fold, so far cheaper than the colour
## sweeps). NOT in the fast net — run it directly:
##   <GODOT> --path . res://tests/CameraHoldClosureCorpusSweepTest.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const CameraLoweringClass = preload("res://src/effects/studio/CameraLowering.gd")
const CameraChannelClass = preload("res://src/effects/studio/CameraChannel.gd")
const EffectPhaseClass = ExMateriaEffects.EffectPhase
const SessionClass = preload("res://src/effects/studio/EffectEditSession.gd")

const EFFECTS_DIR := "res://assets/effects"
const LANES := ["angle", "position", "zoom"]

var _passed: int = 0
var _failed: int = 0
var _effects: int = 0
var _tables: int = 0
var _lanes: int = 0
var _events: int = 0
var _holds: int = 0
var _origin_holds: int = 0
var _closed: int = 0
var _already_zero: int = 0
var _cost_a_slot: int = 0
var _tied_tables: int = 0
var _round_trips: int = 0
var _emptied: int = 0
var _normalised: int = 0
var _trip_violations: Array = []
var _violations: Array = []
var _roundtrip_violations: Array = []


func _ready() -> void:
	for dir in _effect_dirs():
		var ed = EffectDataClass.load_from_directory(dir)
		if ed == null or ed.camera == null:
			continue
		_effects += 1
		for phase in EffectPhaseClass.ALL:
			if not ed.camera.has_table(phase):
				continue
			var table = ed.camera.get_table(phase)
			if table == null or table.keyframes.is_empty():
				continue
			_tables += 1
			_check_pristine_roundtrip(table, "%s/%s" % [dir.get_file(), phase])
			_check_move_round_trips(ed, phase, "%s/%s" % [dir.get_file(), phase])
			for lane_name in LANES:
				_sweep_lane(table, lane_name, "%s/%s/%s" % [dir.get_file(), phase, lane_name])

	print("[census] %d effects, %d camera phase tables, %d non-empty sub-channel lanes"
		% [_effects, _tables, _lanes])
	print("[census] %d events, of which %d are HIDDEN HOLDS (%.1f%%)"
		% [_events, _holds, 100.0 * float(_holds) / maxf(1.0, float(_events))])
	print("[census] %d of those holds sit at a PHASE ORIGIN — the reported case's population"
		% _origin_holds)
	print("[census] %d closures applied (%d holds were already zero-width)"
		% [_closed, _already_zero])
	print("[census] %d closures cost one extra compiled keyframe (left a coalesced group)"
		% _cost_a_slot)
	print("[census] %d shipped tables already carry a same-lane end_frame TIE" % _tied_tables)
	print("[census] %d Move round trips probed, %d of them emptied a hold on the way out"
		% [_round_trips, _emptied])
	print("[census] %d round trips NORMALISED a pre-existing zero-width hold out of the lane"
		% _normalised)

	_assert_true(_effects > 100, "the corpus actually loaded (%d effects)" % _effects)
	_assert_true(_closed > 100, "…and yielded real holds to close (%d)" % _closed)
	_assert_eq(_roundtrip_violations.size(), 0,
		"every shipped table round-trips through parse∘lower untouched (first 4: %s)"
			% str(_roundtrip_violations.slice(0, 4)))
	_assert_true(_round_trips > 500, "the sweep found real movable spans (%d)" % _round_trips)
	_assert_eq(_trip_violations.size(), 0,
		"every Move round trip restored the lane exactly (first 4: %s)"
			% str(_trip_violations.slice(0, 4)))
	_assert_eq(_violations.size(), 0,
		"every closure in the corpus held all five invariants (first 4: %s)"
			% str(_violations.slice(0, 4)))

	print("\n=== CameraHoldClosureCorpusSweepTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CameraHoldClosureCorpusSweepTest")
		get_tree().quit(1)
	else:
		print("[PASS] CameraHoldClosureCorpusSweepTest")
		get_tree().quit(0)


## `lower`'s contract on the table AS SHIPPED, before any edit: re-lowering what `parse` read
## must re-yield the same per-sub-channel event streams. Also counts the tables carrying a
## same-lane end_frame tie — the shape that puts the tie-break under strain, and the population
## a zero-width hold joins.
func _check_pristine_roundtrip(table, where: String) -> void:
	var before: Dictionary = CameraLoweringClass.parse(table)
	var after: Dictionary = CameraLoweringClass.parse(CameraLoweringClass.lower(before))
	var tied := false
	for lane_name in LANES:
		var ends := {}
		for ev in before[lane_name]:
			if ends.has(int(ev["end_frame"])):
				tied = true
			ends[int(ev["end_frame"])] = true
		if not _same_events(after[lane_name], before[lane_name]):
			_roundtrip_violations.append("%s/%s" % [where, lane_name])
	if tied:
		_tied_tables += 1


## Two Move invariants over every DRAWN span the corpus has (a hold is not grabbable — the
## timeline hides it — so Move is only ever aimed at drawn events):
##
##   A. NO ORPHANS. After any slide, no hold in the lane owns nothing. This is ADR-0101
##      decision 7 stated directly, and it is the author's report: the manufactured spacer used
##      to be left at zero width, invisible in the lane but still a keyframe.
##   B. A SUB-MAXIMAL round trip restores the lane byte for byte — ends, command words and
##      values, in every sub-channel. Sub-maximal because a slide that consumes a pre-existing
##      hold ENTIRELY deletes it, and deletion is lossy on purpose (decision 7 frees the slot);
##      undo restores that, a counter-move cannot. Inside the room, nothing is consumed, and the
##      spacer the move manufactured on the way out must be gone on the way back.
func _check_move_round_trips(ed, phase: String, where: String) -> void:
	var pristine = ed.camera.get_table(phase)
	for lane_name in LANES:
		var events: Array = CameraLoweringClass.parse(pristine).get(lane_name, [])
		for n in range(events.size()):
			if CameraChannelClass._event_is_hold(pristine, events[n], lane_name):
				continue      # a hold is hidden, so it is never the span an author grabs
			for reach in [9999, -9999]:
				_probe_move(ed, phase, lane_name, n, reach, where)
	ed.camera.tables[phase] = pristine


## One span, one direction: the MAXIMAL slide (invariant A) and the largest slide that consumes
## no whole hold (invariants A and B).
func _probe_move(ed, phase: String, lane_name: String, n: int, reach: int, where: String) -> void:
	var pristine = ed.camera.get_table(phase)
	var ref := {"channel": "camera", "context": phase, "camera_channel": lane_name, "ordinal": n}
	var room: int = int(CameraChannelClass.plan_move(ed, ref, reach).get("delta", 0))
	if room == 0:
		return
	var tag := "%s/%s#%d %+d" % [where, lane_name, n, room]

	# A — the maximal slide empties the hold it slides into, which must leave no orphan behind.
	# The verbs REPLACE tables[phase] and never mutate the stashed object, so putting the
	# pristine one back is an exact rewind between probes.
	ed.camera.tables[phase] = pristine
	SessionClass.new(ed).move_span(ref, room)
	_round_trips += 1
	var maxed: Dictionary = CameraLoweringClass.parse(ed.camera.get_table(phase))
	if maxed[lane_name].size() < CameraLoweringClass.parse(pristine)[lane_name].size():
		_emptied += 1
	# Only orphans this slide CREATED: 8 shipped holds already own nothing, and neither the
	# verbs nor this sweep may treat untouched ROM data as a defect.
	var was := _orphans(pristine, CameraLoweringClass.parse(pristine))
	for orphan in _orphans(ed.camera.get_table(phase), maxed):
		if not was.has(orphan):
			_trip_violations.append("%s (max): %s owns nothing" % [tag, orphan])
			break

	# B — one frame short of maximal consumes no whole hold, so out and back is an exact rewind.
	var inner: int = room - (1 if room > 0 else -1)
	if inner == 0:
		ed.camera.tables[phase] = pristine
		return
	ed.camera.tables[phase] = pristine
	var before: Dictionary = CameraLoweringClass.parse(pristine)
	var session = SessionClass.new(ed)
	var out: Dictionary = session.move_span(ref, inner)
	if int(out.get("delta", 0)) != inner:
		ed.camera.tables[phase] = pristine
		return
	# Slide back from where it LANDED — a structural move renumbers the lane.
	session.move_span({"channel": "camera", "context": phase, "camera_channel": lane_name,
		"ordinal": int(out.get("event_index", n))}, -inner)
	var after: Dictionary = CameraLoweringClass.parse(ed.camera.get_table(phase))
	for ln in LANES:
		if _same_events(after[ln], before[ln]):
			continue
		# A lane that arrived carrying an orphan comes back one event lighter: the slide grew
		# that empty hold, and sliding home emptied it AGAIN — this time from a hold that really
		# did own frames, so decision 7 deletes it. The verb normalised ROM cruft rather than
		# losing anything; the keyframe it dropped rendered nothing either way. Counted, not
		# failed — but only when the removed events are exactly the pre-existing orphans.
		if _same_events(after[ln], _without_orphans(pristine, before, ln)):
			_normalised += 1
			continue
		_trip_violations.append("%s (inner %+d): %s came back %s, not %s"
			% [tag, inner, ln, _ends_of(after[ln]), _ends_of(before[ln])])
		break
	ed.camera.tables[phase] = pristine


## `lanes[ln]` with every hold that already owned nothing dropped — what a round trip over a
## lane carrying ROM cruft is allowed to come back as.
func _without_orphans(table, lanes: Dictionary, ln: String) -> Array:
	var out: Array = []
	var evs: Array = lanes[ln]
	for i in range(evs.size()):
		var own_start: int = int(evs[i - 1]["end_frame"]) if i >= 1 else 0
		if CameraChannelClass._event_is_hold(table, evs[i], ln) \
				and int(evs[i]["end_frame"]) <= own_start:
			continue
		out.append(evs[i])
	return out


## Every hold that owns no frames, keyed by lane + the frame it sits on (an ordinal would shift
## under the very edit being judged). These are the orphans ADR-0101 decision 7 forbids a verb
## from LEAVING — the corpus's own 8 pre-existing ones are subtracted by the caller.
func _orphans(table, lanes: Dictionary) -> Dictionary:
	var out := {}
	for ln in LANES:
		var evs: Array = lanes[ln]
		for i in range(evs.size()):
			if not CameraChannelClass._event_is_hold(table, evs[i], ln):
				continue
			var own_start: int = int(evs[i - 1]["end_frame"]) if i >= 1 else 0
			if int(evs[i]["end_frame"]) <= own_start:
				out["%s@%d" % [ln, own_start]] = true
	return out


func _ends_of(events: Array) -> String:
	var out: Array = []
	for ev in events:
		out.append(int(ev["end_frame"]))
	return str(out)


func _sweep_lane(table, lane_name: String, where: String) -> void:
	var base: Dictionary = CameraLoweringClass.parse(table)
	var events: Array = base[lane_name]
	if events.is_empty():
		return
	_lanes += 1
	_events += events.size()
	var base_count: int = CameraLoweringClass.lower(base).keyframes.size()

	for n in range(events.size()):
		if not CameraChannelClass._event_is_hold(table, events[n], lane_name):
			continue
		_holds += 1
		var start_n: int = int(events[n - 1]["end_frame"]) if n >= 1 else 0
		if start_n == 0:
			_origin_holds += 1
		if int(events[n]["end_frame"]) == start_n:
			_already_zero += 1
			continue
		_closed += 1
		_close_one(table, base, lane_name, n, start_n, base_count, where)


## Close hold `n` to its own start on a FRESH parse (so each closure is measured against the
## pristine lane), lower it, read it back, and check the five invariants.
func _close_one(table, base: Dictionary, lane_name: String, n: int, start_n: int,
		base_count: int, where: String) -> void:
	var lanes: Dictionary = CameraLoweringClass.parse(table)
	lanes[lane_name][n]["end_frame"] = start_n
	var compiled = CameraLoweringClass.lower(lanes)
	var after: Dictionary = CameraLoweringClass.parse(compiled)
	var tag := "%s#%d" % [where, n]

	# 1. every OTHER event in the lane keeps its end_frame.
	var want_ends: Array = []
	for i in range(lanes[lane_name].size()):
		want_ends.append(int(lanes[lane_name][i]["end_frame"]))
	var got_ends: Array = []
	for ev in after[lane_name]:
		got_ends.append(int(ev["end_frame"]))
	if got_ends != want_ends:
		_violations.append("%s: lane ends %s != %s" % [tag, str(got_ends), str(want_ends)])
		return

	# 2. the hold now owns nothing, so the event after it starts where the hold began. (A hold
	#    at the lane TAIL has no successor to hand its span to — the score end marker does,
	#    ADR-0086 — so there is nothing to assert there.)
	if int(got_ends[n]) != start_n:
		_violations.append("%s: hold end %d != its own start %d" % [tag, int(got_ends[n]), start_n])
		return
	if n + 1 < got_ends.size():
		var next_start: int = 0
		for i in range(n + 1):
			next_start = maxi(next_start, int(got_ends[i]))
		if next_start != start_n:
			_violations.append("%s: the next event starts at %d, not %d"
				% [tag, next_start, start_n])
			return

	# 3. the two SIBLING lanes come back event for event.
	for other in LANES:
		if other == lane_name:
			continue
		if not _same_events(after[other], base[other]):
			_violations.append("%s: sibling lane %s changed" % [tag, other])
			return

	# 4. the lane re-reads as exactly what was written — command word and value too, not just
	#    the ends (a re-order that preserved the end vector would still be a different lane).
	if not _same_events(after[lane_name], lanes[lane_name]):
		_violations.append("%s: the lane did not round-trip through parse∘lower" % tag)
		return

	# 5. a moved keyframe can leave a group it was coalesced into, which costs at most ONE
	#    extra compiled keyframe. More than that means the closure re-shaped the table.
	var grew: int = compiled.keyframes.size() - base_count
	if grew > 1:
		_violations.append("%s: compiled count grew by %d" % [tag, grew])
		return
	if grew == 1:
		_cost_a_slot += 1


## Two parsed event streams are the same lane: same length, same end / command word / value.
## `origin_index` is provenance and goes stale on every re-lower (CameraLowering's own note),
## so it is deliberately excluded.
func _same_events(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		for key in ["end_frame", "source_bits", "interp_bits", "param", "flags", "value", "channel"]:
			if a[i][key] != b[i][key]:
				return false
	return true


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
