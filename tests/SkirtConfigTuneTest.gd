extends Node
## Move-2 guard (ADR-0068): SkirtConfig's parameters are Tune tunables — each property
## getter coalesces the `skirt.*` override over its PROPERTY_META default, the setter
## routes through Tune, and SkirtDebugPanel is a data-driven TuneField view. So an
## override persists + applies at boot in any scene; readers use SkirtConfig.<prop>
## unchanged. Owner assertions hit the real autoload; the panel is built in a bare tree.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/SkirtConfigTuneTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const SkirtConfig = ExMateriaBattlefield.SkirtConfig


const SkirtPanel = preload("res://src/debug/SkirtDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	Tune.reset()
	SkirtConfig.register_tunables()  # reset() wiped the class-load binds; re-establish

	# Getter coalesces the PROPERTY_META default when unset.
	_assert_approx(SkirtConfig.water_skirt_depth, 0.15, "water_skirt_depth reads its default")
	_assert_true(not SkirtConfig.water_skirt_enabled, "water_skirt_enabled reads its default (false)")
	_assert_true(not SkirtConfig.land_skirt_enabled, "land_skirt_enabled reads its default (false)")

	# The water lift is OFF by default, and this one is a value assertion on purpose.
	# `water_surface_offset` raises water-surface materials and nothing else, so any
	# non-zero default lifts one side of every water/non-water shared edge and opens a
	# see-through crack along the join — 1 px per 0.01, measured on MAP009. It is a
	# render artifact with no pure-logic seam of its own, so the default is the only
	# place it can be caught cheaply. If this fails, look at the map before changing it.
	_assert_approx(SkirtConfig.water_surface_offset, 0.0, "water_surface_offset defaults to 0.0 (no water lift)")

	# A Tune override drives the property (readers use SkirtConfig.<prop>).
	Tune.set_value("skirt.water_skirt_depth", 0.5)
	_assert_approx(SkirtConfig.water_skirt_depth, 0.5, "a skirt.water_skirt_depth override drives the property")
	Tune.set_value("skirt.water_skirt_enabled", false)
	_assert_true(not SkirtConfig.water_skirt_enabled, "a skirt.water_skirt_enabled override drives the property")

	# The setter routes through Tune.
	SkirtConfig.head_on_drop_depth = 0.4
	_assert_approx(float(Tune.get_value("skirt.head_on_drop_depth")), 0.4, "setting the property writes the slug")

	# Panel row is TuneField-built and writes the slug.
	Tune.reset()
	SkirtConfig.register_tunables()  # re-establish binds after the reset
	var panel := SkirtPanel.new()
	add_child(panel)
	panel.setup(null)
	var row := _find_row(panel, "Depth")
	_assert_true(row != null, "the Depth row exists")
	if row:
		var label := row.get_child(0) as Label
		_assert_true(label != null and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the Depth row carries the TuneField accent label")
		var sb := _first_spinbox(row)
		_assert_true(sb != null, "the Depth row has a SpinBox control")
		if sb:
			sb.value = 0.7
			sb.value_changed.emit(0.7)
			_assert_approx(float(Tune.get_value("skirt.water_skirt_depth")), 0.7,
				"scrubbing the Depth row writes through to skirt.water_skirt_depth")
	Tune.clear("skirt.water_skirt_depth")
	panel.queue_free()

	print("\n=== SkirtConfigTuneTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SkirtConfigTuneTest")
		get_tree().quit(1)
	else:
		print("[PASS] SkirtConfigTuneTest")
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


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
