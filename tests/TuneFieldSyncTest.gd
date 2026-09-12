extends Node
## Proves "repeat controllers" (ADR-0068): two TuneField rows bound to the SAME slug
## — as if the same knob were placed in two different panels, or a panel AND the
## registry — stay in lockstep. Scrubbing either drives the other, and a code-side
## Tune write drives both, because each row binds to the slug through Tune. This is
## the cross-board sync the framework gives for free — no panel-to-panel wiring.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/TuneFieldSyncTest.tscn

const TuneField = preload("res://src/debug/TuneField.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	Tune.reset()
	var hint := {"min": 0.0, "max": 10.0, "step": 1.0}
	var panel_a := VBoxContainer.new()
	add_child(panel_a)
	var panel_b := VBoxContainer.new()
	add_child(panel_b)

	# The SAME slug, built independently in two "panels".
	var a := TuneField.add(panel_a, "Thing", "demo.thing", 1.0, hint) as SpinBox
	var b := TuneField.add(panel_b, "Thing (elsewhere)", "demo.thing", 1.0, hint) as SpinBox

	# Scrub A -> B follows (setting .value emits value_changed, which writes Tune).
	a.value = 7.0
	_check("B follows a scrub of A", b.value, 7.0)

	# Scrub B -> A follows.
	b.value = 3.0
	_check("A follows a scrub of B", a.value, 3.0)

	# A code-side Tune write drives BOTH rows.
	Tune.set_value("demo.thing", 9.0)
	_check("A follows a code-side Tune write", a.value, 9.0)
	_check("B follows a code-side Tune write", b.value, 9.0)

	# Reset (clear) drives both back to the coalesced default.
	Tune.clear("demo.thing")
	_check("A resets to the default on clear", a.value, 1.0)
	_check("B resets to the default on clear", b.value, 1.0)

	print("\n=== TuneFieldSyncTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TuneFieldSyncTest")
		get_tree().quit(1)
	else:
		print("[PASS] TuneFieldSyncTest")
		get_tree().quit(0)


func _check(label: String, actual: float, expected: float) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %.2f, got %.2f" % [label, expected, actual])
