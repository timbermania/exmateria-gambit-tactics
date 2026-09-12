class_name UI3TransitionEngine
extends RefCounted

## The shared transition engine (ADR-0088 §4; interfaces §4) — the generalizable
## mechanical core of the ADR-0084 coordinator, extracted: one advance loop, one
## delta accumulator per play, the MAX_CATCHUP clamp, per-beat tick cadence, forward
## and reverse drive, settle detection. Hosted by UI3Registry (which advances it from
## _process); internal — elements author only the `transition` criterion plus
## open()/close() and the settle signals. The recipe/stack coordinator
## (FormationTransitionEngine) remains a Formation-world CLIENT, not a rival.

## Per-frame catch-up ceiling, in ticks: one oversized delta (a stall, the Hyprland
## render_unfocused throttle) can never collapse a whole beat into one visual frame.
const MAX_CATCHUP_TICKS := 2.0

# Beats registered at class level: UI3Element.Transition kind -> UI3Beat.
var _beats: Dictionary = {}
# MOVE beats (ADR-0097 §5), keyed by UI3Element.Move kind. A separate map because it is a
# separate vocabulary: the move slot's beats have no reverse and take a destination.
var _move_beats: Dictionary = {}
# Active playbacks: element -> {beat, reversed, frame, accum}. One play per element —
# a new open()/close() replaces the current one mid-flight.
var _plays: Dictionary = {}
# Active MOVE playbacks, same shape plus {"move": true}. A SECOND map, not a second entry in
# the first: a move is a different motion running on a different clock, and an element may
# legitimately be moving WHILE it opens — one slot per element would make the two evict each
# other (ADR-0097 §5).
var _moves: Dictionary = {}


## Register (or, with null, unregister) the beat implementing a Transition kind.
func register_beat(kind: int, beat: UI3Beat) -> void:
	if beat == null:
		_beats.erase(kind)
	else:
		_beats[kind] = beat


## Start playing `element`'s declared beat (reversed = the close direction), optionally at a
## one-invocation `cadence` overriding the element's authored answer (ADR-0097 §4). Returns
## false when the kind has no playback (NONE / RIDE_PARENT / nothing registered) —
## the element then settles instantly. Frame 0 is driven immediately (the play_open
## "seed box" behavior); a reverse play starts from the settled state.
##
## A beat already FINISHED at frame 0 — an IMMEDIATE cadence, whose curve is the identity —
## settles SYNCHRONOUSLY here (ADR-0097 §3). Deferring it to the first `_step` would cost one
## rendered frame at full size and leave the system with two instant behaviours differing by a
## frame. The settle signal is load-bearing, not cosmetic: `p.closed.connect(p.queue_free)` is
## the standard teardown in _close_equip_picker / _close_job_picker, so a close that skipped
## `closed` would leak the node permanently.
func play(element: UI3Element, reversed: bool,
		cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> bool:
	var beat: UI3Beat = _beats.get(element.transition_mode())
	if beat == null:
		return false
	# Armed BEFORE frame 0 is driven: the override has to be in force for the very first
	# drive() and for the settle test that can end an IMMEDIATE play right here.
	element._cadence_override = cadence
	var p := {"beat": beat, "reversed": reversed, "frame": 0, "accum": 0.0, "move": false}
	_plays[element] = p
	_drive(element, p)
	if _finished(element, p):
		_settle(element, p)
	return true


## Start playing `element`'s declared MOVE beat: the walk from its current rect to the one
## place_at() re-homed it onto (ADR-0097 §5). Returns false when the element declares no move
## beat — Move.NONE, an absent `move` field, or nothing registered — and place_at then SNAPS,
## which is what it has always done, so every existing caller is unchanged.
##
## No `reversed` parameter, on purpose: a move's inverse is another move to the other place.
func play_move(element: UI3Element,
		cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> bool:
	var beat: UI3Beat = _move_beats.get(element.move_mode())
	if beat == null:
		return false
	element._move_cadence_override = cadence
	var p := {"beat": beat, "reversed": false, "frame": 0, "accum": 0.0, "move": true}
	_moves[element] = p
	_drive(element, p)
	if _finished(element, p):
		_settle(element, p)
	return true


## Accumulate `delta` against each active play's own tick cadence and step whole
## frames, clamped so a spike can't teleport a beat to settled.
func advance(delta: float) -> void:
	_advance_map(_plays, delta, false)
	_advance_map(_moves, delta, true)


func _advance_map(map: Dictionary, delta: float, move: bool) -> void:
	for element in map.keys():
		if not (is_instance_valid(element) and (element as Node).is_inside_tree()):
			map.erase(element)
			_release(element, move)
			continue
		var p: Dictionary = map[element]
		var tick: float = p["beat"].tick()
		p["accum"] = minf(float(p["accum"]) + delta, MAX_CATCHUP_TICKS * tick)
		while p["accum"] >= tick and map.has(element):
			p["accum"] = float(p["accum"]) - tick
			_step(element, p)


## Guard seam: step every active play — transition AND move — exactly one beat frame.
func step() -> void:
	_step_map(_plays, false)
	_step_map(_moves, true)


func _step_map(map: Dictionary, move: bool) -> void:
	for element in map.keys():
		if is_instance_valid(element):
			_step(element, map[element])
		else:
			map.erase(element)
			_release(element, move)


## Register (or, with null, unregister) the beat implementing a Move kind.
func register_move_beat(kind: int, beat: UI3Beat) -> void:
	if beat == null:
		_move_beats.erase(kind)
	else:
		_move_beats[kind] = beat


## The beat registered for a Transition kind (null for NONE/RIDE_PARENT, or an unbuilt
## kind like SLIDE) — the UI3 page reads it to ask a declared beat its precondition
## (ADR-0088 Amendment 3 §5).
func beat_for(kind: int) -> UI3Beat:
	return _beats.get(kind)


## The beat registered for a Move kind (null for NONE — the snap that place_at has always
## done — or an unregistered kind).
func move_beat_for(kind: int) -> UI3Beat:
	return _move_beats.get(kind)


func is_playing(element: UI3Element) -> bool:
	return _plays.has(element)


func is_moving(element: UI3Element) -> bool:
	return _moves.has(element)


## Drop both plays without settling (element left the tree).
func forget(element: UI3Element) -> void:
	_plays.erase(element)
	_moves.erase(element)
	_release(element, false)
	_release(element, true)


func _step(element: UI3Element, p: Dictionary) -> void:
	p["frame"] = int(p["frame"]) + 1
	_drive(element, p)
	if _finished(element, p):
		_settle(element, p)


## Has this play reached its length? Asked at frame 0 too (see `play`), which is the only
## frame at which an IMMEDIATE cadence's answer is yes.
func _finished(element: UI3Element, p: Dictionary) -> bool:
	var beat: UI3Beat = p["beat"]
	var settle := beat.settle_frame(element)
	return int(p["frame"]) >= (beat.reverse_frames(settle, element) if p["reversed"] else settle)


## End a play: drop it, release the call-site cadence override, THEN tell the element (which
## raises its settled flag and emits). The release comes first so a `closed` handler that
## immediately re-opens the element does not inherit the finished play's override.
func _settle(element: UI3Element, p: Dictionary) -> void:
	var move: bool = bool(p.get("move", false))
	(_moves if move else _plays).erase(element)
	_release(element, move)
	if move:
		element._move_finished()
	else:
		element._transition_finished(not p["reversed"])


## Clear a one-invocation cadence override (ADR-0097 §4). Every path that ends a play goes
## through here — settle, forget, and the dead-element sweep in advance() — because an
## override that outlived its play would silently re-cadence the element's NEXT play.
func _release(element: UI3Element, move: bool) -> void:
	if not is_instance_valid(element):
		return
	if move:
		element._move_cadence_override = UI3Element.NO_CADENCE_OVERRIDE
	else:
		element._cadence_override = UI3Element.NO_CADENCE_OVERRIDE


func _drive(element: UI3Element, p: Dictionary) -> void:
	var beat: UI3Beat = p["beat"]
	if p["reversed"]:
		beat.reverse_drive(element, int(p["frame"]), beat.settle_frame(element))
	else:
		beat.drive(element, int(p["frame"]))


## Boot-time reversibility audit (ADR-0084 invariant 1 over all of UI3): for every
## registered element whose transition names a playback, the beat must exist and be
## reversible. NONE and RIDE_PARENT register no playback BY declaration — auditable
## answers, not gaps.
func reversibility_errors(elements: Array) -> Array:
	var errors: Array = []
	for e: UI3Element in elements:
		# A declared MOVE beat must exist — but reversibility is NOT asked of it, and that is
		# the point of the separate slot (ADR-0097 §5): a move's inverse is another move to the
		# other place, so "has a reverse path" is not a question a move beat can fail. Checked
		# before the transition branch below because `move` is independent of `transition`: an
		# element can sit still on open and still slide between homes.
		var move_kind := e.move_mode()
		if move_kind != UI3Element.Move.NONE and _move_beats.get(move_kind) == null:
			errors.append("element '%s' names move beat '%s' but no beat is registered"
				% [e.id(), UI3Element.Move.keys()[move_kind].to_lower()])
		var kind := e.transition_mode()
		if kind == UI3Element.Transition.NONE or kind == UI3Element.Transition.RIDE_PARENT:
			continue
		var kind_name: String = UI3Element.Transition.keys()[kind].to_lower()
		var beat: UI3Beat = _beats.get(kind)
		if beat == null:
			errors.append("element '%s' names beat '%s' but no beat is registered" % [e.id(), kind_name])
		elif not beat.reversible:
			errors.append("beat '%s' (element '%s') has no reverse path" % [kind_name, e.id()])
	return errors


## Boot-time CADENCE audit (ADR-0097 §1, the new audit surface its Consequences call out):
## for every registered element, ask its DECLARED beat to range-check the element's authored
## cadences against that beat's own vocabulary. `UI3Element.validate_spec` is static and
## beat-blind, so it can only demand a cadence be present and be an int — this is where an
## int that is not one of the beat's curve names is caught. An element naming no beat has no
## cadence to check.
func cadence_errors(elements: Array) -> Array:
	var errors: Array = []
	for e: UI3Element in elements:
		for beat: UI3Beat in [_beats.get(e.transition_mode()), _move_beats.get(e.move_mode())]:
			if beat == null:
				continue
			for problem in beat.cadence_errors(e):
				errors.append("element '%s': %s" % [e.id(), problem])
	return errors
