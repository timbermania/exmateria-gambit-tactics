extends Node3D

## ADR-0084 beat/recipe ENGINE seam (the module the coordinator plays its transitions on).
## Pure + fast — RefCounted Beats/Recipe/Player, no formation/roster seeding. Verifies the four
## load-bearing properties the coordinator relies on:
##   - a recipe plays FORWARD: each group's beats step frames 1..duration in order, groups run in
##     authoring order with a BARRIER between them (no interleave).
##   - a recipe plays REVERSED: groups run in REVERSE order, each beat driven by its own REVERSE driver
##     (a distinct Callable, NOT the forward flipped — the Change-Job exit-fling case).
##   - the delta accumulator honors the MAX_CATCHUP clamp: one oversized delta advances a bounded number
##     of ticks, never collapsing a slide to its end (the teleport guard).
##   - the boot-time reversibility AUDIT (invariant 1) flags any beat missing a reverse driver.

const TransitionEngine = preload("res://src/ui3/formation/FormationTransitionEngine.gd")

var _failed := false


func _ready() -> void:
	_forward_single_group()
	_reverse_uses_distinct_driver()
	_multi_group_barrier()
	_max_catchup_clamp()
	_audit_flags_missing_reverse()
	_group_barrier_hooks_fire()
	_concurrency_audit_flags_overlap()

	if _failed:
		print("[FAIL] FormationTransitionEngine test")
	else:
		print("[PASS] FormationTransitionEngine: forward play, reverse (distinct driver), group barrier, MAX_CATCHUP clamp, reversibility + concurrency audits, group barrier hooks (ADR-0084)")
	get_tree().quit()


## Invariant 4 — no element driven by two positional beats at once. concurrency_conflicts flags a
## group whose concurrent beats share a target role (or leave targets untagged); disjoint roles pass;
## a lone beat per group (our real recipes) is always clean.
func _concurrency_audit_flags_overlap() -> void:
	var a := func(f): pass
	# Two concurrent beats sharing the "roster" role → conflict.
	var clash := TransitionEngine.Recipe.new("CLASH", [[
		TransitionEngine.Beat.new("b1", a, a, 2, -1, ["roster"]),
		TransitionEngine.Beat.new("b2", a, a, 2, -1, ["roster", "ring"]),
	]])
	_expect(not TransitionEngine.concurrency_conflicts([clash]).is_empty(),
		"concurrency: overlapping concurrent targets not flagged")

	# Two concurrent beats on DISJOINT roles → clean (the ADR's [roster_split, ring_build] case).
	var ok := TransitionEngine.Recipe.new("OK", [[
		TransitionEngine.Beat.new("b1", a, a, 2, -1, ["roster"]),
		TransitionEngine.Beat.new("b2", a, a, 2, -1, ["ring"]),
	]])
	_expect(TransitionEngine.concurrency_conflicts([ok]).is_empty(),
		"concurrency: disjoint concurrent targets wrongly flagged")

	# A concurrent beat with NO targets can't be proven disjoint → flagged (fires loudly, per ADR).
	var untagged := TransitionEngine.Recipe.new("UNTAGGED", [[
		TransitionEngine.Beat.new("b1", a, a, 2),
		TransitionEngine.Beat.new("b2", a, a, 2),
	]])
	_expect(not TransitionEngine.concurrency_conflicts([untagged]).is_empty(),
		"concurrency: untagged concurrent beats not flagged")

	# A lone-beat group (every real recipe today) is always clean.
	var lone := TransitionEngine.Recipe.new("LONE", [[TransitionEngine.Beat.new("solo", a, a, 2)]])
	_expect(TransitionEngine.concurrency_conflicts([lone]).is_empty(),
		"concurrency: a single-beat group was flagged")


## A Group carries a barrier HOOK — a non-beat side-effect (Change-Job builds the job ring at the
## boundary between the roster-split group and the ring-entry group) that fires when the group becomes
## active, BEFORE its first beat frame. Forward play fires the forward hooks in order (including the
## first group's, at play start); reverse play fires the REVERSE hooks in reversed group order. This
## is how the ADR's `CHANGE_JOB = [[…],[roster_split, ring_build],[…]]` places instant work at seams.
func _group_barrier_hooks_fire() -> void:
	var log: Array[String] = []
	var b0 := TransitionEngine.Beat.new("b0", func(f): log.append("b0.%d" % f), func(f): log.append("B0.%d" % f), 1)
	var b1 := TransitionEngine.Beat.new("b1", func(f): log.append("b1.%d" % f), func(f): log.append("B1.%d" % f), 1)
	var g0 := TransitionEngine.Group.new([b0], func(): log.append("F0"), func(): log.append("R0"))
	var g1 := TransitionEngine.Group.new([b1], func(): log.append("F1"), func(): log.append("R1"))
	var recipe := TransitionEngine.Recipe.new("H", [g0, g1])

	var fwd := TransitionEngine.Player.new()
	fwd.play(recipe, false, func(): log.append("settled"))
	for _i in 6:
		if not fwd.is_playing():
			break
		fwd.step()
	_expect(log == ["F0", "b0.1", "F1", "b1.1", "settled"],
		"hooks: forward order wrong (got %s)" % [log])

	log.clear()
	var rev := TransitionEngine.Player.new()
	rev.play(recipe, true, func(): log.append("settled"))
	for _i in 6:
		if not rev.is_playing():
			break
		rev.step()
	_expect(log == ["R1", "B1.1", "R0", "B0.1", "settled"],
		"hooks: reverse did not fire reverse hooks in reversed order (got %s)" % [log])

	# The audit sees through Group wrappers to the beats (a Group's beat with no reverse still fails).
	var bad := TransitionEngine.Recipe.new("BADG", [TransitionEngine.Group.new(
		[TransitionEngine.Beat.new("nofix", func(_f): pass, Callable(), 1)])])
	_expect(not TransitionEngine.audit([bad]).is_empty(), "audit: did not see a bad beat inside a Group")


## A single-group single-beat recipe steps frames 1..duration forward, then settles once.
func _forward_single_group() -> void:
	var seen: Array[int] = []
	var beat := TransitionEngine.Beat.new("slide", func(f): seen.append(f), func(_f): pass, 3)
	var settled := [0]
	var player := TransitionEngine.Player.new()
	player.play(TransitionEngine.Recipe.new("R", [[beat]]), false, func(): settled[0] += 1)

	_expect(player.is_playing(), "forward: player not playing after play()")
	for _i in 3:
		player.step()
	_expect(seen == [1, 2, 3], "forward: frames stepped wrong (got %s, want [1,2,3])" % [seen])
	_expect(settled[0] == 1, "forward: on_settled fired %d times (want 1)" % settled[0])
	_expect(not player.is_playing(), "forward: still playing after the last group settled")
	# Idempotent once settled — an extra step must not re-run or re-settle.
	player.step()
	_expect(settled[0] == 1, "forward: stepping past settle re-fired on_settled")


## Reversed play drives each beat's REVERSE callable (a distinct driver), not the forward flipped.
func _reverse_uses_distinct_driver() -> void:
	var fwd: Array[int] = []
	var rev: Array[int] = []
	var beat := TransitionEngine.Beat.new("slide", func(f): fwd.append(f), func(f): rev.append(f), 3)
	var player := TransitionEngine.Player.new()
	player.play(TransitionEngine.Recipe.new("R", [[beat]]), true, func(): pass)
	for _i in 3:
		player.step()
	_expect(rev == [1, 2, 3], "reverse: reverse driver not stepped (got %s)" % [rev])
	_expect(fwd.is_empty(), "reverse: forward driver was called during a reverse play (got %s)" % [fwd])


## Two groups run in order with a barrier forward; reversed, the GROUP ORDER flips (g2 then g1).
func _multi_group_barrier() -> void:
	var order: Array[String] = []
	var g1 := TransitionEngine.Beat.new("a", func(f): order.append("a%d" % f), func(f): order.append("A%d" % f), 2)
	var g2 := TransitionEngine.Beat.new("b", func(f): order.append("b%d" % f), func(f): order.append("B%d" % f), 2)
	var recipe := TransitionEngine.Recipe.new("R2", [[g1], [g2]])

	var fwd_player := TransitionEngine.Player.new()
	fwd_player.play(recipe, false, func(): pass)
	for _i in 4:
		fwd_player.step()
	_expect(order == ["a1", "a2", "b1", "b2"],
		"barrier: forward interleaved groups (got %s, want a1 a2 b1 b2)" % [order])

	order.clear()
	var rev_player := TransitionEngine.Player.new()
	rev_player.play(recipe, true, func(): pass)
	for _i in 4:
		rev_player.step()
	_expect(order == ["B1", "B2", "A1", "A2"],
		"barrier: reverse did not flip group order (got %s, want B1 B2 A1 A2)" % [order])


## One oversized delta advances only a bounded number of ticks — never straight to the end.
func _max_catchup_clamp() -> void:
	var beat := TransitionEngine.Beat.new("long", func(_f): pass, func(_f): pass, 100)
	var player := TransitionEngine.Player.new()
	player.play(TransitionEngine.Recipe.new("LONG", [[beat]]), false, func(): pass)
	player.advance(1.0)   # a 1-second stall / render_unfocused throttle spike
	var expected := int(TransitionEngine.MAX_CATCHUP / TransitionEngine.TICK)   # floor(clamp / tick) = 2 steps
	_expect(player.current_frame() < 100,
		"clamp: one oversized delta ran the beat to its end (frame=%d/100 — teleport)" % player.current_frame())
	_expect(player.is_playing(), "clamp: one oversized delta finished a 100-frame beat in one step")
	_expect(player.current_frame() == expected,
		"clamp: expected floor(MAX_CATCHUP/TICK)=%d steps, got %d" % [expected, player.current_frame()])


## Invariant 1 — the audit flags a beat with no reverse driver (and passes a fully-reversible recipe).
func _audit_flags_missing_reverse() -> void:
	var good := TransitionEngine.Recipe.new("GOOD", [[TransitionEngine.Beat.new("ok", func(_f): pass, func(_f): pass, 2)]])
	_expect(TransitionEngine.audit([good]).is_empty(), "audit: flagged a fully reversible recipe")

	var bad := TransitionEngine.Recipe.new("BAD", [[TransitionEngine.Beat.new("noexit", func(_f): pass, Callable(), 2)]])
	_expect(not TransitionEngine.audit([bad]).is_empty(), "audit: did NOT flag a beat with no reverse driver")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
