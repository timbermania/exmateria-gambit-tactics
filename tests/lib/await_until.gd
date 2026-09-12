extends RefCounted
class_name AwaitUntil

## Wait for a STATE, on a FRAME budget — never for a duration.
##
## Charter clause 7 and clause 14 ([TEST-CHARTER.md](../../docs/TEST-CHARTER.md)).
## `await get_tree().create_timer(0.5).timeout` is a bet that half a second is
## enough on this box, at this load, today. It is the bug behind the ONE entry in
## `tools/run_tests_parallel.py`'s `SEQUENTIAL_LANE`:
##
##   EffectStudioDeselectScrollAcceptanceTest — 20/20 PASS idle, 5 FAIL in 30
##   starts under an N=8 mixed load. `window_bottom=0.0` — the deferred relayout
##   has not landed when the assertion reads it.
##
## A sleep long enough to be safe under load is wasted wall clock on every green
## run; a sleep short enough to be quick is a flake. There is no correct constant,
## which is why this helper takes none. It polls the predicate once per frame and
## returns as soon as the state is true — so it is BOTH faster than the sleep it
## replaces and immune to the load that made the sleep flaky.
##
## The budget is in FRAMES, not seconds, so a slow box takes longer in wall clock
## and stops at exactly the same place in the program. That is the whole point:
## the verdict must not be a function of how busy the machine was.
##
##     var ok := await AwaitUntil.frames(self, func(): return panel.window_bottom > 0.0, 120)
##     if not ok:
##         print("[FAIL] relayout never landed within 120 frames")
##
## Returns true if the predicate went true within the budget, false if it did not.
## It never asserts and never quits — the caller owns the verdict, because a
## helper that printed [FAIL] would put two rules in one register.


## Poll `predicate` once per rendered frame, up to `max_frames`.
##
## `host` is any Node in the tree (the test itself, normally) — the helper needs
## a tree to await frames on and does not assume it is one.
static func frames(host: Node, predicate: Callable, max_frames: int = 120) -> bool:
	var tree := host.get_tree()
	if tree == null:
		push_error("AwaitUntil.frames: host is not in a SceneTree")
		return false
	for _i in range(max_frames):
		if predicate.call():
			return true
		await tree.process_frame
	# One last read: the predicate may have gone true on the final frame we
	# awaited, and returning false there would be a fencepost flake — exactly
	# the class of bug this file exists to delete.
	return predicate.call()


## The physics-tick twin, for state that advances on the fixed step.
##
## Godot's physics step is FIXED (60 Hz of simulated time regardless of how long
## the frame took to render), so a physics-tick budget is deterministic in a way a
## process-frame budget is only approximately. Prefer this one for anything that
## moves.
static func ticks(host: Node, predicate: Callable, max_ticks: int = 120) -> bool:
	var tree := host.get_tree()
	if tree == null:
		push_error("AwaitUntil.ticks: host is not in a SceneTree")
		return false
	for _i in range(max_ticks):
		if predicate.call():
			return true
		await tree.physics_frame
	return predicate.call()


## Settle N frames — the honest replacement for `create_timer(0.0)`-style waits
## whose only job is "let the deferred call land".
##
## Named so the count is visible at the call site. Two frames is the usual answer
## for a `call_deferred` + a relayout; if you find yourself passing 60, you wanted
## `frames()` with a predicate and did not have one yet.
static func settle(host: Node, frame_count: int = 2) -> void:
	var tree := host.get_tree()
	if tree == null:
		return
	for _i in range(frame_count):
		await tree.process_frame
