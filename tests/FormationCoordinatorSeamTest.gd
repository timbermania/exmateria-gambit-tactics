extends Node3D
# test-kind: logic
# seeded-break: disabled enter()'s redundant-enter guard (if false and state == current_state()); re-entering a screen you are already on now pushes again + rebuilds, so the 'redundant enter is a no-op' asserts red (stack grew, overlay rebuilt, is_moving flipped); enter(IDLE) stays no-op via _can_enter

## Formation-transition COORDINATOR seam (ADR-0084) — the one owner of every Formation-screen
## enter/exit. Guards the public seam directly: `enter(state)` / `leave()` over the LIFO screen
## stack, the `settled(to)` signal, and the `current_state()` / `is_moving()` queries.
##
## The ADR verification, mechanized here:
##   - enter(state) drives an ANIMATION (is_moving() true) and `settled(state)` fires at the
##     resting screen; current_state() then reports it.
##   - leave() drives the REVERSE animation (is_moving() true) and `settled(...)` fires at the
##     screen it lands on; the stack pops. There is NO instant snap — invariant 1 (reversibility).
##   - a round-trip (enter→leave) BYTE-RESTORES the docked baseline: the selected unit returns to
##     the exact screen centre it had on the plain roster.
##   - gaps are OBSERVABLE (invariant 2): leave() at IDLE and enter(IDLE) are no-ops that neither
##     crash nor move the chrome — never a silent snap into a half-built screen.
##   - the stack is a GATE, not a ledger: re-entering the screen you are ALREADY on is a no-op —
##     no teardown, no rebuild, no second push. Guarded twice over, because the two doors differ:
##     at the seam (`enter(state)` twice) AND through the REAL viewport (two Enters on the settled
##     detail screen), since the roster's Enter reaches `open_detail` without passing `enter()`.
##
## Covers the two DISTINCT exit recipes: Equip's box-less chrome-slide reverse, and Change-Job's
## ASYMMETRIC spin-and-enlarge fling (§15.24 RE32 — the case that proves "reverse" is a first-class
## per-beat driver, not a naive frame-flip). The other two screens' reverses are covered elsewhere:
## DETAIL (○-press close) by FormationDetailTransitionTest + DetailTransitionTest, and ABILITY shares
## Equip's recipe (only `_sub_mode` differs).

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")

const TICK := 2.0 / 60.0
const State = FormationDetailTransition.State

var _failed := false


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	await _round_trip(State.EQUIP, "Equip")
	await _round_trip(State.CHANGE_JOB, "Change Job")
	await _gaps_observable()
	await _redundant_enter_is_noop(State.DETAIL, "Detail")
	await _redundant_enter_is_noop(State.EQUIP, "Equip")
	await _redundant_enter_is_noop(State.CHANGE_JOB, "Change Job")
	await _double_accept_through_viewport()

	if _failed:
		print("[FAIL] FormationCoordinatorSeam test")
	else:
		print("[PASS] FormationCoordinatorSeam: enter/leave over the stack, settled signal, is_moving, byte-restore round-trip (Equip + Change-Job), gaps observable, redundant enter is a no-op at the seam AND through the viewport (ADR-0084)")
	get_tree().quit()


## enter(state) → settled(state) → leave() → settled(IDLE), byte-restored to the docked baseline.
func _round_trip(state: int, label: String) -> void:
	var host: FormationDetailTransition = await _new_host()
	if host == null:
		return
	var seen: Array[int] = []
	host.settled.connect(func(to): seen.append(to))

	var docked_centre := host._formation.selected_unit_screen_center()

	# --- enter: an animation that settles on the target screen -----------------
	_expect(host.current_state() == State.IDLE, "%s: not IDLE before enter (got %d)" % [label, host.current_state()])
	host.enter(state)
	_expect(host.is_moving(), "%s: enter() did not start an animation (is_moving false)" % label)
	_pump_until(host, func(): return seen.has(state), 200)
	_expect(seen.has(state), "%s: settled(state) never fired after enter()" % label)
	_expect(host.current_state() == state,
		"%s: current_state() wrong after enter (got %d, want %d)" % [label, host.current_state(), state])

	# The selected unit has MOVED off its docked cell (the roster split / equip slide ran).
	_expect(not host._formation.selected_unit_screen_center().is_equal_approx(docked_centre),
		"%s: the roster never moved on enter (screen still docked)" % label)

	# --- leave: the REVERSE animation, settling back to IDLE -------------------
	seen.clear()
	host.leave()
	_expect(host.is_moving(), "%s: leave() did not start a reverse animation (is_moving false)" % label)
	_pump_until(host, func(): return seen.has(State.IDLE), 300)
	_expect(seen.has(State.IDLE), "%s: settled(IDLE) never fired after leave()" % label)
	_expect(host.current_state() == State.IDLE,
		"%s: coordinator not IDLE after leave (stack=%s)" % [label, host._stack])
	_expect(host.detail_overlay() == null, "%s: overlay not torn down after leave" % label)
	_expect(not host.is_moving(), "%s: still moving after the exit settled" % label)

	# --- byte-restore: the selected unit is back at its exact docked centre -----
	_expect(host._formation.selected_unit_screen_center().is_equal_approx(docked_centre),
		"%s: round-trip did NOT restore the docked baseline (centre %s, want %s)"
		% [label, host._formation.selected_unit_screen_center(), docked_centre])

	host.queue_free()
	await get_tree().process_frame


## Invariant 2 — a state with no recipe (IDLE / unwired) neither crashes nor moves the chrome.
func _gaps_observable() -> void:
	var host: FormationDetailTransition = await _new_host()
	if host == null:
		return
	var docked_centre := host._formation.selected_unit_screen_center()

	host.leave()   # nothing on the stack — a no-op, not a snap
	_expect(host.current_state() == State.IDLE, "leave() at IDLE changed the state")
	_expect(not host.is_moving(), "leave() at IDLE started an animation")

	host.enter(State.IDLE)   # IDLE has no entry recipe — a no-op
	_expect(host.current_state() == State.IDLE, "enter(IDLE) changed the state")
	_expect(host.detail_overlay() == null, "enter(IDLE) built an overlay")
	_expect(host._formation.selected_unit_screen_center().is_equal_approx(docked_centre),
		"enter(IDLE)/leave() at IDLE moved the roster")

	host.queue_free()
	await get_tree().process_frame


## The stack is a GATE — asking for the screen you are already ON changes nothing. Enter `state`,
## let it settle, then ask for it AGAIN: same overlay instance (no teardown + rebuild), same stack
## depth (no duplicate push), and no animation started. The bug this guards: the second request
## freed the live DetailScene, built a fresh one, and pushed a second DETAIL — after which one Esc
## left the overlay gone but current_state() still reporting DETAIL.
func _redundant_enter_is_noop(state: int, label: String) -> void:
	var host: FormationDetailTransition = await _new_host()
	if host == null:
		return
	var seen: Array[int] = []
	host.settled.connect(func(to): seen.append(to))

	host.enter(state)
	_pump_until(host, func(): return seen.has(state), 200)
	_expect(host.current_state() == state,
		"%s redundant-enter: never reached the screen (got %d)" % [label, host.current_state()])

	var before_stack: Array[int] = host._stack.duplicate()
	var before_overlay := host.detail_overlay()
	# Compared, not asserted true: Change-Job announces `settled` while its Player is still running,
	# so "no animation" is not a property of every resting screen. The no-op claim is that the second
	# request changes NOTHING — whatever was moving before is exactly what is moving after.
	var before_moving := host.is_moving()

	host.enter(state)   # <- the SAME screen, again

	_expect(host._stack == before_stack,
		"%s redundant-enter: stack changed (was %s, now %s)" % [label, before_stack, host._stack])
	_expect(host.detail_overlay() == before_overlay,
		"%s redundant-enter: the overlay was rebuilt (a teardown + fresh build)" % label)
	_expect(before_overlay == null or is_instance_valid(before_overlay)
			and not before_overlay.is_queued_for_deletion(),
		"%s redundant-enter: the live overlay was freed" % label)
	_expect(host.is_moving() == before_moving,
		"%s redundant-enter: changed is_moving (was %s, now %s) — it started or killed an animation"
		% [label, before_moving, host.is_moving()])

	host.queue_free()
	await get_tree().process_frame


## The SAME rule, through the door the user actually presses. The roster's Enter reaches
## `open_detail` via FormationScene.unit_activated, which does NOT pass through `enter()` — and the
## host's `_input` has no branch for the settled detail screen, so the press falls through to the
## covered grid. A test that calls `_unhandled_input` directly bypasses that entirely and would pass
## against the bug, so drive the REAL viewport (`push_input`) exactly as a player does.
func _double_accept_through_viewport() -> void:
	var host: FormationDetailTransition = await _new_live_host()
	if host == null:
		return

	await _tap(KEY_ENTER, 2)
	await _wait_until(func(): return host.current_state() == State.DETAIL and not host.is_moving(), 300)
	var first := host.detail_overlay()
	_expect(first != null, "viewport: the first Enter never opened the detail screen")
	_expect(host.current_state() == State.DETAIL,
		"viewport: not on DETAIL after one Enter (got %d)" % host.current_state())
	var depth := host._stack.size()

	await _tap(KEY_ENTER, 30)   # <- the second Enter on the SETTLED detail screen (settle, then re-check)
	_expect(host.detail_overlay() == first,
		"viewport: the second Enter rebuilt the detail screen (stack=%s)" % [host._stack])
	_expect(first == null or is_instance_valid(first) and not first.is_queued_for_deletion(),
		"viewport: the second Enter FREED the live DetailScene")
	_expect(host._stack.size() == depth,
		"viewport: the second Enter pushed again (stack=%s, want depth %d)" % [host._stack, depth])

	# …and the payoff: ONE Esc must land back on the roster with an EMPTY stack. With a duplicate
	# push, close_detail() pops one and the coordinator keeps reporting DETAIL with no overlay up.
	# ✕/BACKSPACE, not Escape. ADR-0137 Amendment 4 gave each intent ONE button and moved Esc to
	# SELECT/pause: `ui_cancel` is Backspace alone now, so an Escape tap here reached nothing and
	# this guard had been failing for the input map, not for the state machine.
	await _tap(KEY_BACKSPACE, 2)
	await _wait_until(func(): return host.detail_overlay() == null, 300)
	_expect(host.detail_overlay() == null, "viewport: Esc left the overlay up")
	_expect(host.current_state() == State.IDLE,
		"viewport: after one Esc the coordinator still reports %d (stack=%s) — the state machine is lying"
		% [host.current_state(), host._stack])

	host.queue_free()
	await get_tree().process_frame


## Let real frames run until `done` (or `max_frames`). Real-frame tests must WAIT ON A CONDITION,
## never on a frame count: a fixed budget that is ample when the scene runs alone starves when the
## suite runs back-to-back, and the guard fails for load rather than for the behavior it guards.
func _wait_until(done: Callable, max_frames: int) -> void:
	for _i in max_frames:
		if done.call():
			return
		await get_tree().process_frame


## Press and release `keycode` through the viewport, then let `frames` real frames run.
func _tap(keycode: int, frames: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		get_viewport().push_input(e)
	for _i in frames:
		await get_tree().process_frame


## A host left LIVE (its own _process running) so the real viewport → _input → _unhandled_input
## chain and the steppers behave exactly as they do in the game. The hand-pumped `_new_host` cannot
## be used here: viewport input arrives on real frames.
func _new_live_host() -> FormationDetailTransition:
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "LiveHost"
	add_child(host)
	for _i in 6:
		await get_tree().process_frame
	if host._formation == null or host._formation.selected_character() == null:
		_expect(false, "no formation/selection on the live host")
		host.queue_free()
		return null
	return host


func _new_host() -> FormationDetailTransition:
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	# Let _ready build the grid + seed the roster (it awaits one frame internally).
	for _i in 4:
		await get_tree().process_frame
	host.set_process(false)   # drive every stepper by hand for determinism
	if host._formation == null or host._formation.selected_character() == null:
		_expect(false, "no formation/selection")
		host.queue_free()
		return null
	return host


## Pump the host + detail overlay steppers by hand (menu-tick paced) until `done` or `max` ticks.
## The overlay's own _process is disabled so we're the SOLE driver (no double-stepping with real frames).
func _pump_until(host: FormationDetailTransition, done: Callable, max_ticks: int) -> void:
	for _i in max_ticks:
		if done.call():
			return
		var d = host.detail_overlay()
		if d != null and is_instance_valid(d):
			d.set_process(false)
			d._process(TICK)
		host._process(TICK)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
