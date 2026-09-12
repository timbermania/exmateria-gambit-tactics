extends Node
## Integration guard (real Control, bare tree): EffectCurvePainter turns a mouse
## drag into a dense stroke over the bound EffectCurve's grid, with preview-vs-commit
## semantics — the drag mutates a LOCAL grid and only mouse-UP reports the finished
## stroke as `curve_changed(values)`. Stroke correctness itself is locked in
## CurvePaintModelTest.
##
## The painter does NOT write the bound curve (it did, until the ADR-0089
## curve-ownership amendment made a commit a real session edit — the choke point has to
## see the PRE-edit samples to snapshot them for undo, which it cannot if the painter
## has already overwritten them). So the assertions below read the EMITTED array, and
## the bound curve staying untouched is now a property in its own right.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCurvePainterTest.tscn

const EffectCurve = ExMateriaEffects.EffectCurve

const Painter = preload("res://src/effects/studio/EffectCurvePainter.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_drag_paints_and_commits_on_release()
	_test_no_commit_until_release()
	_test_bind_curve_carries_used_window()
	_test_active_region_veils_tail_and_marks_boundary()
	_test_active_region_no_veil_when_wrapping_or_animation_driven()

	print("\n=== EffectCurvePainterTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCurvePainterTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCurvePainterTest")
		get_tree().quit(0)


## A drag from bottom-left to top-right paints an ascending curve and, on release,
## REPORTS it as the whole 160-sample 0-255 array. The bound curve is left alone — the
## channel writes it, so the choke point still sees the pre-edit samples for undo.
func _test_drag_paints_and_commits_on_release() -> void:
	var curve = EffectCurve.from_array(_flat(160, 0.0), 0)
	var p = _painter(curve)
	var changed := {"n": 0, "values": []}
	p.curve_changed.connect(func(v): changed["n"] += 1; changed["values"] = v)
	var r: Rect2 = p._grid_rect()
	_press(p, Vector2(r.position.x, r.position.y + r.size.y))          # col 0, min
	_drag(p, Vector2(r.position.x + r.size.x, r.position.y))            # col last, max
	_release(p, Vector2(r.position.x + r.size.x, r.position.y))
	_assert_eq(changed["n"], 1, "release emits curve_changed exactly once")
	var vals: Array = changed["values"]
	_assert_eq(vals.size(), 160, "the whole curve is reported, not a delta")
	_assert_true(int(vals[0]) < 26, "left column stayed near the min after paint")
	_assert_true(int(vals[159]) > 229, "right column painted near the max")
	for v in vals:
		_assert_in_grid(v)
	_assert_eq(curve.samples[159], 0.0, "the painter leaves the bound curve to the channel")


## Nothing is reported mid-drag — only mouse-up commits.
func _test_no_commit_until_release() -> void:
	var curve = EffectCurve.from_array(_flat(160, 0.0), 0)
	var p = _painter(curve)
	var changed := {"n": 0}
	p.curve_changed.connect(func(_v): changed["n"] += 1)
	var r: Rect2 = p._grid_rect()
	_press(p, Vector2(r.position.x, r.position.y + r.size.y))
	_drag(p, Vector2(r.position.x + r.size.x * 0.5, r.position.y))
	_assert_eq(changed["n"], 0, "no commit while dragging")
	_assert_eq(curve.samples[80], 0.0, "the bound curve is untouched until release")
	_release(p, Vector2(r.position.x + r.size.x * 0.5, r.position.y))
	_assert_eq(changed["n"], 1, "release commits")


## ADR-0089 curve-UX amendment — the painter is the INVERSE of the sparkline: it
## keeps all 160 frames editable but marks what the sim consumes. bind_curve threads
## the used window `used_n` in (fourth arg) and it rides on the widget.
func _test_bind_curve_carries_used_window() -> void:
	var curve = EffectCurve.from_array(_flat(160, 0.0), 0)
	var p = _painter(curve)
	_assert_eq(p.used_window(), -1, "no window by default (whole curve editable, no veil)")
	p.bind_curve(curve, 0, 255, 40)
	_assert_eq(p.used_window(), 40, "bind_curve carries the used window")


## A real sub-window (0 < N < count) veils the INACTIVE tail (N..count] and marks a
## boundary at frame N. The veil starts at the boundary and runs to the grid's right
## edge; the boundary sits strictly inside the grid.
func _test_active_region_veils_tail_and_marks_boundary() -> void:
	var r := Rect2(10, 10, 300, 100)
	var reg: Dictionary = Painter.active_region(40, 160, r)
	_assert_true(reg["show_veil"], "0<N<count veils the inactive tail")
	var bx: float = reg["boundary_x"]
	_assert_true(bx > r.position.x and bx < r.position.x + r.size.x, "boundary is inside the grid")
	var veil: Rect2 = reg["veil_rect"]
	_assert_true(abs(veil.position.x - bx) < 0.001, "the veil starts at the boundary")
	_assert_true(abs((veil.position.x + veil.size.x) - (r.position.x + r.size.x)) < 0.001,
		"the veil runs to the grid's right edge")


## Fallbacks: a wrapping window (>= count) has NO veil and no note; an
## animation-driven window (-1) has no veil but an honest corner note.
func _test_active_region_no_veil_when_wrapping_or_animation_driven() -> void:
	var r := Rect2(10, 10, 300, 100)
	var wrap: Dictionary = Painter.active_region(200, 160, r)
	_assert_true(not wrap["show_veil"], "a wrapping window (>=count) has no veil")
	_assert_eq(str(wrap["note"]), "", "…and no note (the whole curve genuinely plays)")
	var anim: Dictionary = Painter.active_region(-1, 160, r)
	_assert_true(not anim["show_veil"], "an animation-driven window (-1) has no veil")
	_assert_true(str(anim["note"]) != "", "…but carries an honest note")


# --- helpers --------------------------------------------------------------

func _painter(curve):
	var p = Painter.new()
	add_child(p)               # _ready
	p.size = Vector2(320, 120)
	p.bind_curve(curve, 0, 255)
	return p


func _press(p, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	p._gui_input(e)


func _release(p, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = pos
	p._gui_input(e)


func _drag(p, pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	p._gui_input(e)


func _flat(n: int, v: float) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(v)
	return a


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


## The painter reports in its GRID alphabet (0-`vmax` ints); the 0-1 normalization is
## CurveChannel's side of the bridge, not the painter's.
func _assert_in_grid(v) -> void:
	if int(v) >= 0 and int(v) <= 255:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] sample out of [0,255]: %s" % str(v))
