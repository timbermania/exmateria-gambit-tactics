extends Node
## Move-2 guard (bare tree, ADR-0068): ProjectileDebugPanel's spin row is TuneField-built
## and bound to the `projectile.spin_deg_per_tick` slug — Projectile3D OWNS the value
## (reads Tune.of at its per-frame use-site, default = Projectile3D.SPIN_DEG_PER_TICK_DEFAULT),
## so the panel no longer writes a static the projectile reads.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ProjectilePanelTuneFieldTest.tscn

const ProjPanel = preload("res://src/debug/ProjectileDebugPanel.gd")
const Projectile3DScript = preload("res://src/projectiles/Projectile3D.gd")
const TuneField = preload("res://src/debug/TuneField.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	Tune.reset()
	# The owner re-establishes its bind after reset (ADR-0068: register_tunables() is the
	# static replay _static_init also calls at class load). The panel is now a pure VIEW —
	# it reads the default + hint back from the registry, so the slug MUST be registered
	# before the panel builds or the row renders as an unsupported read-only field.
	Projectile3DScript.register_tunables()
	# The default home is the Projectile3D static var, read back by the pure-view panel row.
	_assert_true(is_equal_approx(Projectile3DScript.SPIN_DEG_PER_TICK_DEFAULT, 24.0),
		"Projectile3D owns the spin default (24.0)")

	var panel := ProjPanel.new()
	add_child(panel)
	panel.setup()

	var row := _find_row(panel, "Spin")
	_assert_true(row != null, "the Spin row exists")
	if row:
		var label := row.get_child(0) as Label
		_assert_true(label != null and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the Spin row carries the TuneField accent label")
		var sb := _first_spinbox(row)
		_assert_true(sb != null, "the Spin row has a SpinBox control")
		if sb:
			sb.value = 40.0
			sb.value_changed.emit(40.0)
			_assert_true(is_equal_approx(float(Tune.bind("projectile.spin_deg_per_tick", 24.0)), 40.0),
				"scrubbing the row writes through to projectile.spin_deg_per_tick")
	Tune.clear("projectile.spin_deg_per_tick")

	panel.queue_free()

	print("\n=== ProjectilePanelTuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ProjectilePanelTuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] ProjectilePanelTuneFieldTest")
		get_tree().quit(0)


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
