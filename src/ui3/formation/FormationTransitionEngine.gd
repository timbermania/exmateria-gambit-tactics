extends RefCounted
## ADR-0084 — the beat/recipe ENGINE the Formation coordinator plays its screen transitions on.
##
## One orthogonal axis (ADR-0084 "Decision"), mechanized:
##   - a [Beat] is ONE reversible move of role-selected targets: a forward frame-driver, a distinct
##     reverse frame-driver, a forward duration, and (for asymmetric exits — Change-Job's spin-fling)
##     an optional distinct reverse_duration. Position is a pure function of `frame` (explicit
##     stepping, never `await`) so the same beat drives forward AND backward and can be hand-stepped.
##   - a [Recipe] is ONE screen transition expressed as a SEQUENCE OF GROUPS; the beats in a group
##     run CONCURRENTLY, and groups run in order with a BARRIER between them (the next group waits for
##     the longest beat in the current one). Composition is FLAT — recipes never contain recipes.
##   - a [Player] plays a recipe forward, or the SAME groups REVERSED (reverse order, each beat's
##     reverse driver) on exit — so there is no separately-authored exit (invariant 1). It owns the
##     ONE menu-tick accumulator and the `_MAX_CATCHUP` clamp, so a stall / render_unfocused throttle
##     can never collapse a whole transition into one visual frame (the teleport).
##   - [method audit] is the boot-time reversibility check (invariant 1): a beat lacking a reverse
##     driver is reported so a forgotten exit fails in CI, not at the user's first Esc.
##
## The Formation coordinator (FormationDetailTransition) owns the roster/detail nodes; the beats'
## forward/reverse Callables wrap that scene's existing frame-stepped methods (play_equip_slide, …).
## This engine is scene-free and unit-tested on its own (FormationTransitionEngineTest).

## Menu-tick cadence (≈30 Hz), shared with the §15 animators (SpriteSlideAnimator et al.).
##
## 2/60 because the §15.1 slide keyframes `[144,139,67,31,13,4,0]` are NOT pre-repeated, so
## they legitimately hold ~2 vsyncs each. This is why UI3Beat.tick() is 1/60 and this is
## 2/60 — the same ~30 Hz cadence encoded two ways (there, the hold lives in the curve data;
## here, in the clock). Collapsing them to one number in either direction is a REGRESSION —
## see the note on UI3Beat.tick(). ADR-0097 folds the difference into the curve so the two
## constants can finally become one.
const TICK := 2.0 / 60.0
## Per-frame catch-up ceiling: a single oversized delta (a stall, or the Hyprland render_unfocused
## throttle dropping the window to ~1 fps) is clamped to this so the accumulator can't run a whole
## recipe's worth of steps in one frame. Normal 30–60 fps deltas are well under it.
const MAX_CATCHUP := 2.0 * TICK


## One reversible move of its (role-selected) targets between two keyframes. The targets are chosen
## INSIDE the forward/reverse drivers by role ("the selected unit" vs "the rest") — a beat never
## carries a frozen node list, so element-flow is gap-proof (ADR-0084 invariant 3).
class Beat:
	extends RefCounted
	## A short id for the boot audit / diagnostics.
	var id: String
	## `func(frame: int) -> void` — drives the forward motion at `frame` in 1..duration.
	var forward: Callable
	## `func(frame: int) -> void` — drives the REVERSE motion at `frame` in 1..reverse_duration.
	## A distinct driver, NOT a naive forward-flip: Change-Job's exit fling ≠ its entry contraction
	## reversed. For a genuinely symmetric beat, callers pass a reverse that computes forward(dur−n).
	var reverse: Callable
	## Forward length in menu-ticks.
	var duration: int
	## Reverse length in menu-ticks — defaults to `duration` (symmetric); set distinct for the
	## asymmetric exits (the fling is a different length than the contraction it undoes).
	var reverse_duration: int
	## The element-ROLES this beat drives ("roster", "ring", …) — used ONLY to mechanize invariant 4
	## (no element driven by two positional beats at once): concurrent beats in a group must declare
	## DISJOINT role sets. A single-beat group needs no tags; a multi-beat group MUST tag every beat.
	var targets: Array

	func _init(p_id: String, p_forward: Callable, p_reverse: Callable, p_duration: int, p_reverse_duration: int = -1, p_targets: Array = []) -> void:
		id = p_id
		forward = p_forward
		reverse = p_reverse
		duration = p_duration
		reverse_duration = p_duration if p_reverse_duration < 0 else p_reverse_duration
		targets = p_targets

	## Invariant-1 predicate: a beat is reversible iff it carries a callable reverse driver.
	func has_reverse() -> bool:
		return reverse.is_valid()


## A group with a BARRIER HOOK: a non-beat side-effect that fires when the group becomes active
## (before its first beat frame). Change-Job builds the job ring at the boundary between the
## roster-split group and the ring-entry group, and undoes it (clears the ring) at the reverse
## boundary. A plain `Array[Beat]` group has no hook; use Group only where a seam needs instant work.
class Group:
	extends RefCounted
	var beats: Array
	## Fires when this group becomes active during a FORWARD play (e.g. build the ring).
	var on_enter_forward: Callable
	## Fires when this group becomes active during a REVERSE play (e.g. clear the ring / reset a slide).
	var on_enter_reverse: Callable

	func _init(p_beats: Array, p_on_enter_forward: Callable = Callable(), p_on_enter_reverse: Callable = Callable()) -> void:
		beats = p_beats
		on_enter_forward = p_on_enter_forward
		on_enter_reverse = p_on_enter_reverse


## One screen transition — a FLAT sequence of [Group]s (beats that run concurrently + an optional
## barrier hook); groups run in order with a barrier between. For terse authoring a hookless group may
## be written as a bare `Array[Beat]`; `_init` normalizes it to a hookless [Group] so the Player and
## the audits only ever see ONE type (no `group is Array` branching downstream).
class Recipe:
	extends RefCounted
	var id: String
	var groups: Array   # always [Group] after _init normalization

	func _init(p_id: String, p_groups: Array) -> void:
		id = p_id
		groups = []
		for g in p_groups:
			groups.append(g if g is Group else Group.new(g))


## Plays a recipe forward or reversed, one menu-tick accumulator + `_MAX_CATCHUP` clamp. Not a Node —
## the coordinator owns it and ticks it from its single `_process` (or a guard hand-steps it).
class Player:
	extends RefCounted
	var _groups: Array = []       # play order (already reversed on a reverse play)
	var _reversed := false
	var _gi := 0                  # index of the currently-stepping group
	var _frame := 0               # ticks into the current group (0 = not yet stepped)
	var _accum := 0.0
	var _playing := false
	var _on_settled: Callable = Callable()

	## Begin playing `recipe` — forward, or (reversed=true) the same groups in REVERSE ORDER via each
	## beat's reverse driver. `on_settled` fires exactly once when the last group finishes (immediately
	## if the recipe is empty). Drivers are called from frame 1; frame 0 is the untouched initial state.
	func play(recipe: Recipe, reversed: bool, on_settled: Callable) -> void:
		_groups = recipe.groups.duplicate()
		if reversed:
			_groups.reverse()
		_reversed = reversed
		_gi = 0
		_frame = 0
		_accum = 0.0
		_on_settled = on_settled
		_playing = _has_any_beat()
		if _playing:
			_fire_enter_hook()          # the first group's barrier hook fires before its first frame
		elif _on_settled.is_valid():
			_on_settled.call()

	func is_playing() -> bool:
		return _playing

	## Abort the current play WITHOUT firing on_settled — for a teardown that has already snapped the
	## world to its resting state (e.g. a chrome descent finishing before the roster un-slide it drove).
	func stop() -> void:
		_playing = false

	## Ticks into the current group (for guards/observation). 0 when not playing.
	func current_frame() -> int:
		return _frame if _playing else 0

	## Index of the currently-stepping group in play order (for guards/observation).
	func current_group_index() -> int:
		return _gi

	## Advance exactly one menu-tick: step every beat in the current group whose duration still covers
	## this frame, then cross the barrier to the next group when the longest beat is done. Firing
	## on_settled after the last group. Idempotent once settled.
	func step() -> void:
		if not _playing:
			return
		_frame += 1
		var group: Group = _groups[_gi]
		var beats: Array = group.beats
		var gdur := _group_duration(group)
		for beat in beats:
			var bdur: int = beat.reverse_duration if _reversed else beat.duration
			if _frame <= bdur:
				var driver: Callable = beat.reverse if _reversed else beat.forward
				if driver.is_valid():
					driver.call(_frame)
		if _frame >= gdur:
			_gi += 1
			_frame = 0
			if _gi >= _groups.size():
				_playing = false
				if _on_settled.is_valid():
					_on_settled.call()
			else:
				_fire_enter_hook()      # next group's barrier hook, before its first frame

	## Accumulate `delta` at the menu-tick cadence and step whole ticks, clamping the per-frame
	## catch-up so one oversized frame can't teleport through the recipe.
	func advance(delta: float) -> void:
		if not _playing:
			return
		_accum += minf(delta, MAX_CATCHUP)
		while _accum >= TICK and _playing:
			_accum -= TICK
			step()

	## Fire the currently-active group's barrier hook (the direction-appropriate one). No-op for a
	## group with no hook set.
	func _fire_enter_hook() -> void:
		var group: Group = _groups[_gi]
		var hook: Callable = group.on_enter_reverse if _reversed else group.on_enter_forward
		if hook.is_valid():
			hook.call()

	func _group_duration(group: Group) -> int:
		var d := 0
		for beat in group.beats:
			d = maxi(d, beat.reverse_duration if _reversed else beat.duration)
		return d

	func _has_any_beat() -> bool:
		for group in _groups:
			if not group.beats.is_empty():
				return true
		return false


## Boot-time reversibility audit (ADR-0084 invariant 1). Returns one error string per beat lacking a
## reverse driver — empty means every recipe is fully exitable by replaying its groups reversed.
static func audit(recipes: Array) -> Array:
	var errors: Array = []
	for recipe in recipes:
		for gi in recipe.groups.size():
			var beats: Array = recipe.groups[gi].beats
			for beat in beats:
				if not beat.has_reverse():
					errors.append("recipe '%s' group %d beat '%s' has no reverse driver" % [recipe.id, gi, beat.id])
	return errors


## Boot-time concurrency audit (ADR-0084 invariant 4: no element driven by two positional beats at
## once). Within a group, concurrent beats must drive DISJOINT element roles. A single-beat group is
## always clean; a group with two+ beats must tag every beat's `targets`, and no role may repeat.
## Returns one error string per conflict (untagged concurrent beat, or overlapping roles) — empty is OK.
static func concurrency_conflicts(recipes: Array) -> Array:
	var errors: Array = []
	for recipe in recipes:
		for gi in recipe.groups.size():
			var beats: Array = recipe.groups[gi].beats
			if beats.size() < 2:
				continue   # a lone beat can't conflict with a concurrent one
			var seen := {}
			for beat in beats:
				if beat.targets.is_empty():
					errors.append("recipe '%s' group %d beat '%s' is concurrent but declares no targets" % [recipe.id, gi, beat.id])
					continue
				for role in beat.targets:
					if seen.has(role):
						errors.append("recipe '%s' group %d: beats '%s' and '%s' both drive role '%s'" % [recipe.id, gi, seen[role], beat.id, role])
					else:
						seen[role] = beat.id
	return errors
