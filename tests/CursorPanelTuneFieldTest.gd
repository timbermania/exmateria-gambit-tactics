extends Node
## Move-2 guard (ADR-0068): CursorDebugPanel's rows are built by the shared TuneField
## bound to `cursor.*` slugs, not hand-rolled SpinBoxes writing onto the TileCursor
## node — so each carries the accent (pinnable) label AND writes through to its slug
## (which TileCursor coalesces). Catches a revert of the in-place migration. Built in
## a bare tree; setup() takes an (unused) cursor arg, so null is fine here.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/CursorPanelTuneFieldTest.tscn

const CursorPanel = preload("res://src/debug/CursorDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# `reset_overrides()`, NOT `reset()` — ADR-0173 / #535. `_static_init` fires ONCE per class load
	# per process, so `reset()` would wipe the pose-slug declarations with no way back (the deleted
	# `register_tunables()` call below was that "way back", and replaying one owner's registration
	# by naming it is the deleted `register_all()` shape done by hand). Clearing only the
	# recoverable half leaves the DECLARATIONS standing, which is the whole isolation this test
	# needs. (palette_row / blend_mode stay panel-registrant rows, so the Mode OptionButton below
	# still self-registers.)
	Tune.reset_overrides()
	# 🔴 THE GUARD ON A DEPENDENCY THIS FILE NO LONGER SPELLS (ADR-0208 dec. 1 / dec. 2).
	# The four pose slugs are bound by `_static_init` at the cursor class's LOAD. This test used to
	# force that load itself, by preloading the addon script by path and then calling
	# `register_tunables()` explicitly — a criterion-4 site and, measured, redundant twice over:
	# `CursorDebugPanel` (the subject) annotates `setup(_rig: CursorRig)` and reads
	# `CursorRig.SEMI_MODE_LABELS`, and the rig preloads the cursor script, so loading the panel
	# already loads the owner. The reach is DELETED rather than re-spelled, and this assert is what
	# makes that safe: it tests the EFFECT, so it fires if the panel stops naming the rig, if the
	# rig stops preloading the cursor, or if `_static_init` regresses. Measured in both directions
	# — a bare scene that loads neither leaves `cursor.height` UNregistered, so this is a real
	# predicate and not a tautology. Without it the four pose-row assertions below would pass
	# vacuously against unregistered slugs.
	assert(Tune.is_registered("cursor.height"),
		"[CursorPanelTuneFieldTest] the cursor.* pose slugs are not registered — the mount "
		+ "const above is what loads the owner's class. ADR-0208 dec. 1.")
	var panel := CursorPanel.new()
	add_child(panel)
	panel.setup(null)

	# The "Height" row is a TuneField SpinBox: accent label + write-through.
	var row := _find_row(panel, "Height")
	_assert_true(row != null, "the 'Height' row exists")
	if row:
		var label := row.get_child(0) as Label
		_assert_true(label != null and label.has_theme_color_override("font_color")
			and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the Height row carries the TuneField accent label")
		var sb := _first_spinbox(row)
		_assert_true(sb != null, "the Height row has a SpinBox control")
		if sb:
			sb.value = 2.5
			sb.value_changed.emit(2.5)
			_assert_true(is_equal_approx(float(Tune.bind("cursor.height", 1.5)), 2.5),
				"scrubbing the row writes through to cursor.height")
	Tune.clear("cursor.height")

	# The blend-mode row is an enum OptionButton bound to cursor.blend_mode.
	var blend_row := _find_row(panel, "Mode")
	_assert_true(blend_row != null and _first_option(blend_row) != null,
		"the blend Mode row is an OptionButton (enum TuneField)")

	panel.queue_free()

	print("\n=== CursorPanelTuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CursorPanelTuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] CursorPanelTuneFieldTest")
		get_tree().quit(0)


## Find the TuneField row (HBoxContainer) whose first child Label has `text`.
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


func _first_option(row: Control) -> OptionButton:
	for child in row.get_children():
		if child is OptionButton:
			return child
	return null


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % label)
