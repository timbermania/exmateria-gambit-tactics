extends Node
## ADR-0161's SCREEN-IN ramp, as numbers — the half a filmstrip cannot check.
##
## The picture half is `-- --menu=screenin --shot=/tmp/x.png`, and it is not optional:
## a fade is a picture, and the specific risk this change carries is that it now
## STALLS. This file checks the things a picture cannot state exactly — the step
## size, the landing frame, and the two properties that make the ramp usable at all.
##
## [b]Why these assertions and not "it fades".[/b]
##
## [b]1. The step is 1 vsync, and the PICTURE lands four frames before the LATCH.[/b]
## MEASURED (ADR-0174): the tick at [code]0x800694A8[/code] increments the counter by one
## and divides by the length — no quantisation. ADR-0161 shipped a 2-frame step borrowed
## from [code]{3E}[/code]'s worker [code]FUN_801467dc[/code], which is a different function
## in a different overlay. And the two landmarks are genuinely different frames: the quad
## reaches 0 at tick 12, while the busy latch a console host blocks on clears at 16. A test
## that knew only one of those would pass while the other drifted.
##
## [b]2. The ramp is SEEKABLE.[/b] [method WorldMapScreenIn.value_at] must be a pure
## function of the tick — ticking N times and seeking to N have to agree, or the contact
## sheet (which seeks) shows a different ramp from the one that plays (which ticks). That
## is the failure mode where the picture you approve is not the picture that ships.
##
## [b]3. It starts at 192, and that is NOT fully black.[/b] MEASURED: the fade-IN arm
## begins at the [code]0xC0[/code] literal at [code]0x8006963C[/code] — level 24 of 31.
## The port asks this quad to do a job the console's never had (cover the mount frame,
## because ADR-0161 §1 established the navigator's `_fade_rect` cannot), and at 192 the top
## seven framebuffer levels survive tick 0. This arm asserts the MEASUREMENT and states the
## consequence as a number; whether those seven levels are present in the map's actual
## first frame is a question for `--menu=screenin`, not for arithmetic. Do not "fix" it to
## 255 without a picture that shows a leak — see ADR-0174.
##
## [b]4. Values are 5-bit baked.[/b] `psx_expand_555.gdshader` states the rule: the map
## composites in the GPU's own 5-bit channels, every quad is baked as `8 * v`, and the
## expansion runs ONCE at the end. An unquantised ramp computes `e(B) - e(F)` where the
## console computes `e(B - F)` — the ±1-on-25.9%-of-the-frame error that shader exists
## to close, reintroduced by the fade.
##
## [b]This file used to refuse to pin the length, and that refusal PAID.[/b] ADR-0161's 60
## was a mirror of scenario 12's scene-out, and because no assertion here depended on it,
## replacing it with the measured 16 (ADR-0174) cost three constants and two arms — no
## golden re-capture, no fixture churn. The length is now measured and IS pinned, at
## [constant WorldMapScreenIn.RAMP_TICKS]; what stays unpinned is the PICTURE, which only
## `--menu=screenin` can judge.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/WorldMapScreenInTest.tscn

## The brightest level the PSX framebuffer holds (5 bits). Tick 0 must be >= this or the
## subtraction does not reach black.
const MAX_LEVEL := 31

var _passed := 0
var _failed := 0


func _ready() -> void:
	_check_step_and_landing()
	_check_seek_matches_tick()
	_check_starts_black()
	_check_five_bit_baked()
	_check_is_drawing_gate()

	if _failed > 0:
		print("[FAIL] WorldMapScreenInTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapScreenInTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


## 1. A new value every STEP_TICKS vsyncs, and the landing is exact.
func _check_step_and_landing() -> void:
	var last := WorldMapScreenIn.RAMP_TICKS
	var land := WorldMapScreenIn.land_tick()
	_eq("RAMP_TICKS is the measured len argument", last, 16)

	# Every frame moves the value, right up to the landing — no quantisation.
	var moves := 0
	for t in range(0, land):
		if WorldMapScreenIn.value_at(t) != WorldMapScreenIn.value_at(t + 1):
			moves += 1
	_eq("every frame before the landing moves the value", moves, land)

	# The console's own arithmetic, frame by frame: 0xC0 - t*256/len, integer division.
	var off_curve := 0
	for t in range(0, last + 1):
		var want: float = float(maxi(0, WorldMapScreenIn.START_VALUE
				- (t * WorldMapScreenIn.RAMP_SCALE) / last))
		if not is_equal_approx(WorldMapScreenIn.value_at(t), want):
			off_curve += 1
	_eq("every frame matches 0xC0 - t*256/len", off_curve, 0)

	# The PICTURE lands at 12; the LATCH runs to 16. Both, separately.
	_eq("the picture lands on tick 12", land, 12)
	_ne("still tinting one frame before the landing",
			WorldMapScreenIn.value_at(land - 1), 0.0)
	_eq("clear exactly on the landing tick", WorldMapScreenIn.value_at(land), 0.0)
	_eq("the latch outruns the picture by four frames", last - land, 4)
	_eq("still clear at RAMP_TICKS", WorldMapScreenIn.value_at(last), 0.0)
	_eq("stays clear past it", WorldMapScreenIn.value_at(last + 30), 0.0)

	# And the instance agrees with the static function about when it is done.
	var ramp := WorldMapScreenIn.new()
	_eq("active at tick 0", ramp.is_active(), true)
	for _i in last - 1:
		ramp.tick()
	_eq("still active one tick short", ramp.is_active(), true)
	ramp.tick()
	_eq("inactive on the landing tick", ramp.is_active(), false)
	_eq("landed value is clear", ramp.current_value(), 0.0)
	_eq("ticks stop accumulating past the end", ramp.ticks(), last)


## 2. Seeking to N and ticking N times must be the same ramp — the contact sheet SEEKS,
## the screen TICKS, and they have to be showing the same thing.
func _check_seek_matches_tick() -> void:
	var ticked := WorldMapScreenIn.new()
	var sought := WorldMapScreenIn.new()
	var disagreements := 0
	for t in range(0, WorldMapScreenIn.RAMP_TICKS + 1):
		sought.seek(t)
		if not is_equal_approx(ticked.current_value(), sought.current_value()):
			disagreements += 1
		if not is_equal_approx(ticked.current_value(), WorldMapScreenIn.value_at(t)):
			disagreements += 1
		ticked.tick()
	_eq("seek, tick and value_at agree on every frame", disagreements, 0)

	# Seeking BACKWARDS re-arms — the sheet renders frames in order, but nothing should
	# depend on that.
	sought.seek(WorldMapScreenIn.RAMP_TICKS)
	_eq("seek to the end lands it", sought.is_active(), false)
	sought.seek(0)
	_eq("seek back to 0 re-arms it", sought.is_active(), true)
	_eq("...and restores the black", sought.current_value(),
			WorldMapScreenIn.value_at(0))


## 3. Tick 0 hides the mount frame, which is the job it inherited from the cover rect.
func _check_starts_black() -> void:
	var v0 := WorldMapScreenIn.value_at(0)
	var level := int(v0 / WorldMapScreenIn.LEVEL_STEP)
	_eq("tick 0 is the measured 0xC0", v0, 192.0)
	_eq("...which is level 24, not 31", level, 24)

	# Stated as the consequence rather than as a requirement: exactly which framebuffer
	# levels survive `B - F` at tick 0. Seven do. Whether the map HAS pixels that bright
	# in its first frame is what `--menu=screenin` answers; this pins the arithmetic so a
	# silent change to START_VALUE cannot pass unnoticed.
	var leaked := 0
	for b in range(0, MAX_LEVEL + 1):
		if float(b) * WorldMapScreenIn.LEVEL_STEP - v0 > 0.0:
			leaked += 1
	_eq("seven framebuffer levels survive tick 0", leaked, 7)


## 4. Every pushed value is a whole 5-bit level, so the blend happens where the console's
## does. See psx_expand_555.gdshader.
func _check_five_bit_baked() -> void:
	var off_grid := 0
	var out_of_range := 0
	for t in range(0, WorldMapScreenIn.RAMP_TICKS + 1):
		var v := WorldMapScreenIn.value_at(t)
		if fmod(v, WorldMapScreenIn.LEVEL_STEP) != 0.0:
			off_grid += 1
		if v < 0.0 or v > MAX_LEVEL * WorldMapScreenIn.LEVEL_STEP:
			out_of_range += 1
	_eq("every value is a whole 5-bit level", off_grid, 0)
	_eq("every value is in range", out_of_range, 0)

	# Monotonic: a screen-in that brightens then dims is not a fade.
	var reversals := 0
	for t in range(0, WorldMapScreenIn.RAMP_TICKS):
		if WorldMapScreenIn.value_at(t + 1) > WorldMapScreenIn.value_at(t):
			reversals += 1
	_eq("the ramp never brightens", reversals, 0)


## 5. The quad is hidden the moment it stops tinting — `FUN_8008f208`'s skip, and §24.1's
## enable gate, which tests the descriptor's own r/g/b.
func _check_is_drawing_gate() -> void:
	var ramp := WorldMapScreenIn.new()
	_eq("drawing at tick 0", ramp.is_drawing(), true)
	ramp.seek(WorldMapScreenIn.land_tick())
	_eq("not drawing from the landing tick", ramp.is_drawing(), false)
	_eq("...but the latch is still held there", ramp.is_active(), true)
	ramp.settle()
	_eq("not drawing once landed", ramp.is_drawing(), false)
	_eq("settle() lands it", ramp.is_active(), false)
	_eq("settle() agrees with value_at(RAMP_TICKS)", ramp.current_value(),
			WorldMapScreenIn.value_at(WorldMapScreenIn.RAMP_TICKS))


func _eq(what: String, got: Variant, want: Variant) -> void:
	if str(got) == str(want):
		_passed += 1
		return
	_failed += 1
	print("  MISMATCH  %s: got %s, want %s" % [what, got, want])


func _ne(what: String, got: Variant, unwanted: Variant) -> void:
	if str(got) != str(unwanted):
		_passed += 1
		return
	_failed += 1
	print("  MISMATCH  %s: got %s, wanted anything else" % [what, got])
