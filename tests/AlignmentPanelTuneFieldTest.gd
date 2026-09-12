extends Node
## Guard for ADR-0068 R1–R8: the ScenarioUnitAlignmentDebugPanel is a VIEW (decision
## 12 / R5). Its rows pass NO default — they read each render.* slug's registered literal +
## hint from the registry (the OWNER's bind is the single source of truth) and write scrubs
## back through to Tune. We register the owners' slugs UP FRONT (as PSXDisplay / Unit._static_
## init do at boot) because a view row over an unregistered slug has nothing to render.
## Built in a bare tree (dummy scene root, empty units) so it dodges the GPUArena roster crash.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/AlignmentPanelTuneFieldTest.tscn

const AlignPanel = preload("res://src/debug/ScenarioUnitAlignmentDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_par_row_is_a_view_over_the_owner_slug()
	_test_alignment_rows_are_views_and_write_through()

	print("\n=== AlignmentPanelTuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] AlignmentPanelTuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] AlignmentPanelTuneFieldTest")
		get_tree().quit(0)


## Simulate the owners' boot-time registration (PSXDisplay._ready / Unit._static_init): a
## pure bind of each render.* slug to its literal + affordance hint. The panel is a view
## over these — it does not register them itself.
func _register_owner_slugs() -> void:
	Tune.bind("render.pixel_aspect", 1.25, {"min": 0.5, "max": 2.0, "step": 0.01})
	Tune.bind("render.unit_stretch", 1.0, {"min": 0.5, "max": 2.0, "step": 0.01})
	Tune.bind("render.unit_mesh_scale", 8.0, {"min": 1.0, "max": 20.0, "step": 0.1})
	Tune.bind("render.unit_y_lift", 0.05, {"min": -2.0, "max": 2.0, "step": 0.01})
	Tune.bind("render.loc_offset", Vector2(27.0, 26.0), {"min": -128.0, "max": 128.0, "step": 1.0})


func _test_par_row_is_a_view_over_the_owner_slug() -> void:
	Tune.reset()
	_register_owner_slugs()
	var panel := AlignPanel.new()
	add_child(panel)
	var dummy := Node.new()
	add_child(dummy)
	panel.setup(dummy, func() -> Array: return [])

	var par_sb: SpinBox = panel._par_sb
	_assert_true(par_sb != null, "the PAR knob is a SpinBox (built from the registered literal)")
	if par_sb:
		var label := par_sb.get_parent().get_child(0) as Label
		_assert_true(label != null and label.has_theme_color_override("font_color"),
			"the PAR row carries a TuneField accent label")
		if label:
			_assert_true(label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
				"the PAR label uses the tunable accent color")
		_assert_approx(par_sb.value, 1.25, "the view row shows the owner's registered literal")
		# Scrubbing writes through to the render.pixel_aspect slug (the whole point).
		par_sb.value = 1.6
		_assert_approx(float(Tune.bind("render.pixel_aspect", 0.0)), 1.6,
			"scrubbing the PAR view row writes through to Tune")

	panel.queue_free()
	dummy.queue_free()


## The mesh scale / Y-lift float rows and the collapsed loc_offset Vector2 row are all view
## rows: accent label, control inferred from the registered literal's type, write-through.
func _test_alignment_rows_are_views_and_write_through() -> void:
	Tune.reset()
	_register_owner_slugs()
	var panel := AlignPanel.new()
	add_child(panel)
	var dummy := Node.new()
	add_child(dummy)
	panel.setup(dummy, func() -> Array: return [])

	# Scalar float rows.
	for case in [[panel._scale_sb, "render.unit_mesh_scale", 6.5],
			[panel._ylift_sb, "render.unit_y_lift", 0.3]]:
		var sb: SpinBox = case[0]
		var slug: String = case[1]
		var val: float = case[2]
		_assert_true(sb != null, "%s knob is a SpinBox" % slug)
		if sb:
			var label := sb.get_parent().get_child(0) as Label
			_assert_true(label != null and label.has_theme_color_override("font_color")
				and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
				"%s row carries the TuneField accent label" % slug)
			sb.value = val
			_assert_approx(float(Tune.bind(slug, 0.0)), val,
				"scrubbing %s writes through to Tune" % slug)

	# The collapsed loc_offset row is a Vector2 (two per-component spinboxes).
	var loc: Control = panel._loc_control
	_assert_true(loc != null, "the loc_offset row built a control")
	var comps: Array = []
	if loc:
		for child in loc.get_children():
			if child is SpinBox:
				comps.append(child)
	_assert_true(comps.size() == 2, "loc_offset is one Vector2 row with two component spinboxes")
	if comps.size() == 2:
		comps[1].value = 22.0  # scrub the y component
		var got: Variant = Tune.bind("render.loc_offset", Vector2.ZERO)
		_assert_true(got is Vector2 and is_equal_approx(got.y, 22.0) and is_equal_approx(got.x, 27.0),
			"scrubbing the loc_offset y component writes the whole Vector2 through to Tune")

	panel.queue_free()
	dummy.queue_free()


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected ~%.4f, got %.4f" % [label, expected, actual])
