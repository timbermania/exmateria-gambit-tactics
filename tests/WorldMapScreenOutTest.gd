extends Node
## ADR-0174's OUT arm, as numbers and as a GATE — the half a filmstrip cannot check.
##
## The picture half is `-- --menu=screenout --shot=/tmp/x.png`, and it is not optional: a
## fade is a picture. This file checks the things a picture cannot state exactly — the
## endpoints, the direction, the landing frame — plus the one thing the ramp's arithmetic
## has nothing to say about: that `world_map.screen_out` actually turns it off.
##
## [b]Why the endpoints and not "it fades".[/b] The out-arm is NOT the in-arm reversed, and
## that is the whole reason `WorldMapScreenOut` restates the formula instead of running
## `WorldMapScreenIn` backwards (ADR-0174 §2):
##
##   out   `counter*256/len + 32`, ceil 0xFF   ->  starts 32, ends full black
##   in    `0xC0 - counter*256/len`, floor 0   ->  starts 192, ends clear
##
## A reversed in-arm would start at 0 (a cut, not a fade — the failure being fixed) and end
## at 192, which is level 24 of 31 and is NOT black. Both endpoints are load-bearing and
## neither survives a "reverse the other one" refactor, so both are pinned here.
##
## Run: <GODOT> --path . --quit-after 600 res://tests/WorldMapScreenOutTest.tscn

const SCENE_PATH := "res://assets/scenes/WorldMap.tscn"

var _passed := 0
var _failed := 0
## Set from a `dismissed` handler — a MEMBER because a lambda would capture a local by
## VALUE and never write it back (which made the 'not yet' arm vacuous before it was one).
var _dismissed := false


func _ready() -> void:
	_check_curve()
	await _check_gate()
	_finish()


func _check_curve() -> void:
	var first := WorldMapScreenOut.value_at(0)
	var last := WorldMapScreenOut.value_at(WorldMapScreenOut.RAMP_TICKS)

	# It OPENS already down. This is the arm that catches a reversed in-arm, whose first
	# frame is 0 — indistinguishable from no fade at all on the frame the player notices.
	_true("the ramp opens at 32, not 0 (the `+ 32` offset)", is_equal_approx(first, 32.0))

	# ...and it ENDS at full black. 255 bakes down to 248 = level 31 in the framebuffer's
	# own 5-bit channels, which is black; 192 (the in-arm's start) is level 24 and is not.
	_true("it lands on level 31 — 248, full black — not the in-arm's 192",
			is_equal_approx(last, 248.0))

	# Monotonic ASCENDING, which is the direction bit. The in-arm's test asserts the
	# opposite for the same reason: a ramp that ever brightens on the way out is the
	# subtractive quad being driven backwards.
	var rising := true
	var prev := -1.0
	for t in range(0, WorldMapScreenOut.RAMP_TICKS + 1):
		var v := WorldMapScreenOut.value_at(t)
		if v < prev:
			rising = false
		prev = v
	_true("it never brightens on the way out", rising)

	# Every pushed value is a framebuffer level, because the blend happens BEFORE the
	# 5-bit expansion — the ±1 error psx_expand_555 exists to close.
	var quantised := true
	for t in range(0, WorldMapScreenOut.RAMP_TICKS + 1):
		if fmod(WorldMapScreenOut.value_at(t), WorldMapScreenOut.LEVEL_STEP) != 0.0:
			quantised = false
	_true("every value is a whole 5-bit level (a multiple of 8)", quantised)

	# The picture is done BEFORE the latch is, same shape the in-arm has at 12 of 16.
	# Derived from the formula rather than hardcoded, so a length change moves it.
	_true("it lands at tick 14, two frames before the 16-tick latch",
			WorldMapScreenOut.land_tick() == 14)
	_true("and the ramp is 16 ticks", WorldMapScreenOut.RAMP_TICKS == 16)

	# The instance clock agrees with the static curve, and stops.
	var r := WorldMapScreenOut.new()
	_true("a fresh ramp is active", r.is_active())
	_true("and starts on the curve's first value", is_equal_approx(r.current_value(), 32.0))
	for _i in WorldMapScreenOut.RAMP_TICKS:
		r.tick()
	_true("after RAMP_TICKS ticks it is done", not r.is_active())
	_true("and rests on full black", is_equal_approx(r.current_value(), 248.0))


## The tunable is the point of the feature, so it gets an arm in BOTH directions. With the
## slug off, `_leave` must still emit `dismissed` — and emit it WITHOUT spending the ramp,
## because a host awaiting that signal is what actually tears the screen down.
##
## Both halves of that sentence are ARMED, and the OFF half is armed twice over: once on the
## signal (it fires) and once on the CLOCK (it fires inside the `leave()` call, with no frame
## in between). The negative arm it replaces — `not screen_out_active()` alone — was green on
## three different states of the world and could only distinguish one of them.
func _check_gate() -> void:
	# reset_overrides(), NOT reset(): this arm mounts a production node right after, and
	# `reset()` clears the REGISTRY, which only the owners can rebuild — `_static_init`
	# has already fired for this process and cannot fire again. That is what used to force
	# the `Tune.register_all()` replay this line called; the replay is deleted (ADR-0173)
	# and the over-broad clear it existed to undo is the thing that was wrong.
	Tune.reset_overrides()

	# --- OFF: the cut this replaces, one switch away ---
	Tune.set_value(WorldMapScreenOut.SCREEN_OUT_SLUG, false)
	var off := await _mount()
	if off == null:
		return
	# [b]Rule the OTHER TWO skips out FIRST.[/b] `_run_screen_out` returns early for three
	# different reasons — the tunable, a running capture, and a missing quad — and
	# `screen_out_active()` reads false after every one of them, because it is
	# `_screen_out != null and is_active()` and all three leave `_screen_out` null. So an arm
	# that reads only that flag is not testing the tunable at all: it passes just as green on
	# a scene that never built a screen-in quad. These two lines are what make the arm below
	# a statement about the SWITCH.
	_true("the OFF arm is judging the tunable, not the capture gate",
			off.capture_path.is_empty())
	_true("the OFF arm is judging the tunable, not a missing quad",
			off.has_screen_quad())

	_dismissed = false
	off.dismissed.connect(func() -> void: _dismissed = true)
	off.leave()
	# [b]No `await` between the call and this read — that IS the assertion.[/b] With the slug
	# off `_run_screen_out` returns synchronously, so `_leave` runs straight through to
	# `dismissed.emit()` inside the `leave()` call on the line above. Reading the flag here
	# rather than a frame later is what pins "WITHOUT spending the ramp": if this ever needs
	# a frame to pass, the OFF path has started costing the player time and the "one switch
	# away from the cut" promise is quietly gone. A `screen_out_active()` arm cannot say
	# this, because false is also what a fade that never started looks like.
	_true("with the tunable OFF `dismissed` fires inside `leave()` itself — no ramp spent",
			_dismissed)
	await get_tree().process_frame
	_true("with the tunable OFF the screen does not run a fade",
			not off.screen_out_active())
	off.queue_free()
	await get_tree().process_frame

	# --- ON: the ramp runs, and `dismissed` waits for it ---
	Tune.set_value(WorldMapScreenOut.SCREEN_OUT_SLUG, true)
	var on := await _mount()
	if on == null:
		return
	_dismissed = false
	on.dismissed.connect(func() -> void: _dismissed = true)
	on.leave()
	await get_tree().process_frame
	_true("with the tunable ON the screen is fading out", on.screen_out_active())
	_true("and `dismissed` has NOT fired yet — the host waits for the fade", not _dismissed)

	# Let it finish. Bounded so a stall fails loudly instead of hanging the runner — and
	# bounded in the SAME unit, with the same constant, as the loop inside `_run_screen_out`.
	# A flat `RAMP_TICKS * k` was the wrong unit on both sides: this loop resumes once per
	# RENDERED frame while the ramp advances once per VSYNC at 60 Hz, so the margin shrinks
	# as the display gets faster and inverts around 480 fps, where the bound would expire on
	# a fade that was running perfectly. Counting frames that made no PROGRESS never does.
	var stall := WorldMapScreenOut.STALL_FRAMES
	var last: int = on.screen_out_ticks()
	while on.screen_out_active() and stall > 0:
		await get_tree().process_frame
		var now: int = on.screen_out_ticks()
		if now == last:
			stall -= 1
		else:
			last = now
			stall = WorldMapScreenOut.STALL_FRAMES
	_true("the fade completes", not on.screen_out_active())
	# Bounded WAIT, not a single frame. `_leave` is awaiting `process_frame` in its own
	# loop, so on the frame this one observes `is_active()` go false, `_leave` has not yet
	# been resumed to re-test its condition and fall out — the emit lands a frame or two
	# later. Asserting on an exact frame here would be pinning coroutine resume ORDER,
	# which is not the promise; the promise is that `dismissed` follows the fade.
	var settle := 8
	while not _dismissed and settle > 0:
		settle -= 1
		await get_tree().process_frame
	_true("and `dismissed` fires once it has", _dismissed)
	on.queue_free()


func _mount() -> Node:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		_true("the world map scene loads", false)
		return null
	var layer := CanvasLayer.new()
	add_child(layer)
	var view = packed.instantiate()
	layer.add_child(view)
	for _i in 6:
		await get_tree().process_frame
	# The screen-in must be out of the way or it owns the shared quad.
	if view.has_method("settle_screen_in"):
		view.settle_screen_in()
	return view


func _true(msg: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL %s" % msg)


func _finish() -> void:
	if _failed > 0:
		print("[FAIL] WorldMapScreenOutTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
	else:
		print("[PASS] WorldMapScreenOutTest — %d/%d" % [_passed, _passed])
		get_tree().quit(0)
