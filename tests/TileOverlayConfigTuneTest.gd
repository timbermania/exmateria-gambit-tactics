extends Node
# test-kind: logic
# seeded-break: in `Tune._ready`, change `if _is_test_process():` to
# `if false and _is_test_process():` — the seam stops firing, the panel scrub commits to
# `res://config/tune_overrides.json`, and both ADR-0281 assertions red together (measured:
# 11 passed / 2 failed, and the file appears).
## Move-2 guard (ADR-0068): TileOverlayConfig's per-type params + UV crop are Tune
## tunables — get_param / the uv_* getters coalesce `tile.*` overrides over the seeded
## defaults, set_param routes through Tune, and a Tune.value_changed→`changed` bridge
## re-applies live tiles. TilesDebugPanel is a TuneField view whose per-type rows rebind
## to the selected type's slugs. Owner assertions hit the real autoload.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/TileOverlayConfigTuneTest.tscn
##
## 🔴 THIS TEST IS ALSO THE DIRECTION TEST FOR ADR-0281's staging seam, because it is the one
## test that drives a real AUTOSAVE panel row. `_test_panel` builds a REAL TilesDebugPanel and
## selects a type; `tile.selected_type` is an AUTOSAVE TuneField, so the same gesture calls
## `Tune.commit_slug(slug, path)` — and the panel constructs its own TuneFields with the
## production default, so the test never gets to pass a temp path. Before ADR-0281 that default
## WAS `res://config/tune_overrides.json`, and this test wrote the developer's machine state
## mid-run: #1149 measured nine later tests going red for it, attributed to the branch under test.
##
## It used to defend itself with snapshot + RESTORE, and that defence had the defect in it — the
## restore early-returned when the file had not existed before, which is the only case that
## matters now that the file is untracked (90e593900). So the repair is gone and a VERDICT stands
## in its place: `_assert_machine_state_untouched` proves the repo file is byte-identical across
## the run, and `staging_path()` is asserted EMPTY first, because "no file appeared" from a test
## whose seam never fired is a zero from a blind instrument.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const TileOverlayConfig = ExMateriaBattlefield.TileOverlayConfig


const TilesPanel = preload("res://src/debug/TilesDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")

var _passed := 0
var _failed := 0
var _changed_count := 0
## Bytes-or-absence of config/tune_overrides.json before this test ran (see the header).
var _overrides_before: PackedByteArray = PackedByteArray()
var _overrides_existed := false


func _ready() -> void:
	_snapshot_machine_state()
	Tune.reset()
	TileOverlayConfig.register_tunables()  # reset() wiped the construction-time binds; re-establish
	var t0: int = TileOverlayConfig.tunable_types()[0]  # PLACEMENT_PLAYER
	var t1: int = TileOverlayConfig.tunable_types()[1]  # PLACEMENT_ENEMY

	# get_param coalesces the seeded default when unset.
	_assert_eq(int(TileOverlayConfig.get_param(t0, "palette_row")), 0, "get_param reads the seeded default")

	# A Tune override on the type's slug drives get_param + apply.
	TileOverlayConfig.of().changed.connect(func(): _changed_count += 1)
	_changed_count = 0
	Tune.set_value(TileOverlayConfig.param_slug(t0, "palette_row"), 5)
	_assert_eq(int(TileOverlayConfig.get_param(t0, "palette_row")), 5, "a tile.<type>.palette_row override drives get_param")
	_assert_true(_changed_count >= 1, "the Tune write bridges to the `changed` signal (tiles re-apply)")

	# set_param routes through Tune; the two types are independent slugs.
	TileOverlayConfig.set_param(t1, "phase_rate", 42.0)
	_assert_approx(float(TileOverlayConfig.get_param(t1, "phase_rate")), 42.0, "set_param writes the type's slug")
	_assert_approx(float(TileOverlayConfig.get_param(t0, "phase_rate")), 10.0, "the other type is unaffected (independent slug)")

	# Color param round-trips (Color TuneField support).
	Tune.set_value(TileOverlayConfig.param_slug(t0, "tint"), Color(0.1, 0.2, 0.3, 1.0))
	var tint = TileOverlayConfig.get_param(t0, "tint")
	_assert_true(tint is Color and tint.is_equal_approx(Color(0.1, 0.2, 0.3, 1.0)), "a per-type tint Color override coalesces")

	# UV crop global is Tune-backed.
	Tune.set_value("tile.uv_offset_x", 33.0)
	_assert_approx(TileOverlayConfig.uv_offset_x, 33.0, "a tile.uv_offset_x override drives the global getter")

	_test_panel(t0, t1)

	_assert_machine_state_untouched()

	print("\n=== TileOverlayConfigTuneTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TileOverlayConfigTuneTest")
		get_tree().quit(1)
	else:
		print("[PASS] TileOverlayConfigTuneTest")
		get_tree().quit(0)


func _test_panel(t0: int, t1: int) -> void:
	Tune.reset()
	TileOverlayConfig.register_tunables()  # re-establish binds after the reset
	var panel := TilesPanel.new()
	add_child(panel)
	panel.setup()

	# The per-type Speed row (selected type 0) is a TuneField writing the type-0 slug.
	var row := _find_row(panel, "Speed (Hz)")
	_assert_true(row != null, "the per-type Speed row exists")
	if row:
		var label := row.get_child(0) as Label
		_assert_true(label != null and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the Speed row carries the TuneField accent label")
		var sb := _first_spinbox(row)
		if sb:
			sb.value = 55.0
			sb.value_changed.emit(55.0)
			_assert_approx(float(Tune.get_value(TileOverlayConfig.param_slug(t0, "phase_rate"))), 55.0,
				"scrubbing the Speed row writes the selected type's slug")

	# Switching the type selector rebinds the per-type rows to the other type's slugs.
	panel._type_opt.select(1)
	panel._type_opt.item_selected.emit(1)
	var row2 := _find_row(panel, "Speed (Hz)")
	var sb2 := _first_spinbox(row2) if row2 else null
	if sb2:
		sb2.value = 77.0
		sb2.value_changed.emit(77.0)
		_assert_approx(float(Tune.get_value(TileOverlayConfig.param_slug(t1, "phase_rate"))), 77.0,
			"after switching type, the row writes the NEW type's slug")
	panel.queue_free()


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


func _assert_eq(actual: int, expected: int, label: String) -> void:
	if actual == expected: _passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected): _passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])


func _assert_true(cond: bool, label: String) -> void:
	if cond: _passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


## --- ADR-0281: the machine-state seam (see the header) -------------------------------------------

func _snapshot_machine_state() -> void:
	_overrides_existed = FileAccess.file_exists(Tune.OVERRIDE_PATH)
	if _overrides_existed:
		_overrides_before = FileAccess.get_file_as_bytes(Tune.OVERRIDE_PATH)


## Four states, not one, and the old restore only handled the last two: the file may have been
## ABSENT or PRESENT before, and is ABSENT or PRESENT now. Comparing bytes-or-absence covers the
## grid in one assertion and — unlike "assert the file is absent" — stays true for a developer
## who legitimately has pins dialed in. That is also why the runner sentinel
## (`tools/machine_state_sentinel.py`) compares rather than asserts absence.
func _assert_machine_state_untouched() -> void:
	_assert_true(Tune.staging_path().is_empty(),
		"the seam fired: a test process has no staging file (ADR-0281)")
	var exists_now := FileAccess.file_exists(Tune.OVERRIDE_PATH)
	_assert_true(exists_now == _overrides_existed,
		"config/tune_overrides.json is %s, exactly as it was before the panel scrub"
			% ("present" if _overrides_existed else "absent"))
	if _overrides_existed and exists_now:
		_assert_true(FileAccess.get_file_as_bytes(Tune.OVERRIDE_PATH) == _overrides_before,
			"config/tune_overrides.json is byte-identical (the panel scrub reached no disk)")
