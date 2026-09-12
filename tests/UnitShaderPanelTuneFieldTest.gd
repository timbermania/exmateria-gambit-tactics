extends Node
# test-kind: logic
# seeded-break: UnitShaderDebugPanel's forward-nudge row re-bound from `render.ot_unit_forward` to `render.center_bias` — 'scrubbing unit_forward: writes through to render.ot_unit_forward' RED (the row still builds, accent + SpinBox + the center_bias arm stay green); GREEN unbroken on the reverted tree

## Move-2 guard (ADR-0068): UnitShaderDebugPanel's forward-nudge and center-bias rows
## are built by the shared TuneField bound to `render.*` slugs, not SpinBoxes writing
## onto unit materials / a static — so each carries the accent (pinnable) label AND
## writes through to its slug (Unit / SpriteLayerManager coalesce it). Built in a bare
## tree; setup() takes (unused) scene_root + units-accessor args.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/UnitShaderPanelTuneFieldTest.tscn

const ShaderPanel = preload("res://src/debug/UnitShaderDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")
const SpriteLayerManagerScript = ExMateriaSpriteRig.SpriteLayerManager
const UnitScript = preload("res://src/units/Unit.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	Tune.reset()
	# Both rows are now pure-VIEW rows — each owner must re-establish its bind after reset
	# (ADR-0068: register_tunables() is the static replay _static_init also calls at class load),
	# or the row renders as an unsupported read-only field with no SpinBox. Unit owns
	# render.ot_unit_forward, SpriteLayerManager owns render.center_bias.
	UnitScript.register_tunables()
	SpriteLayerManagerScript.register_tunables()
	var panel := ShaderPanel.new()
	add_child(panel)
	panel.setup(null, Callable())

	_check_row(panel, "unit_forward:", "render.ot_unit_forward", 0.5)
	_check_row(panel, "center_bias (up/down):", "render.center_bias", -1.5)

	panel.queue_free()

	print("\n=== UnitShaderPanelTuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] UnitShaderPanelTuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] UnitShaderPanelTuneFieldTest")
		get_tree().quit(0)


func _check_row(panel: Node, label_text: String, slug: String, scrub: float) -> void:
	var row := _find_row(panel, label_text)
	_assert_true(row != null, "the '%s' row exists" % label_text)
	if row == null:
		return
	var label := row.get_child(0) as Label
	_assert_true(label != null and label.has_theme_color_override("font_color")
		and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
		"the '%s' row carries the TuneField accent label" % label_text)
	var sb := _first_spinbox(row)
	_assert_true(sb != null, "the '%s' row has a SpinBox control" % label_text)
	if sb:
		sb.value = scrub
		sb.value_changed.emit(scrub)
		_assert_true(is_equal_approx(float(Tune.bind(slug, 0.0)), scrub),
			"scrubbing '%s' writes through to %s" % [label_text, slug])
	Tune.clear(slug)


func _find_row(node: Node, label_text: String) -> Control:
	for child in node.get_children():
		if child is HBoxContainer and child.get_child_count() > 0:
			var lbl := child.get_child(0) as Label
			if lbl and lbl.text == label_text:
				return child
		var found := _find_row(child, label_text)
		if found:
			return found
	return null


func _first_spinbox(row: Control) -> SpinBox:
	for child in row.get_children():
		if child is SpinBox:
			return child
	return null


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % label)
