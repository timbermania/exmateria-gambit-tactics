extends Node
## Move-2 guard (ADR-0068): the roster-view placement knobs are OWNED by UICombatManager
## — it binds per-column `roster.friendly.*` / `roster.enemy.*` Tune slugs in _ready (the
## two columns are tuned independently), so an override coalesces onto the column AND a
## scrub re-drives it, with no debug-panel fan-out (decision 12) — the property that let #1070
## delete `RosterViewDebugPanel` without touching a knob or this guard. Exercises the
## duck-typed _bind_one_roster directly against a fake column (the real columns need the
## whole combat UI); the binding logic is what we're guarding.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/RosterViewTunablesTest.tscn

const UICombatManagerScript = preload("res://src/ui3/UICombatManager.gd")

class FakeRoster:
	var screen_pos := Vector2(0.02, 0.06)
	var spacing := 6.0
	var mirror_text_shift := -29.0
	var pixels_per_unit := 0.04
	var assembly_scale := 1.0
	var portrait_scale := 1.0
	var mirrored := false

var _passed := 0
var _failed := 0


func _ready() -> void:
	Tune.reset()
	# A pre-set override must coalesce onto the column when the manager binds it.
	Tune.set_value("roster.friendly.spacing", 12.0)
	Tune.set_value("roster.friendly.mirrored", true)

	# Manager NOT added to the tree, so its _ready doesn't run — we call the bind
	# helper directly (self is a valid Node bind-owner either way).
	var mgr = UICombatManagerScript.new()
	var fake := FakeRoster.new()
	mgr._bind_one_roster(fake, "roster.friendly")

	_assert_approx(fake.spacing, 12.0, "pre-set roster.friendly.spacing coalesces onto the column at bind")
	_assert_true(fake.mirrored, "pre-set roster.friendly.mirrored coalesces at bind")

	# Live scrub re-drives the bound column.
	Tune.set_value("roster.friendly.spacing", 30.0)
	Tune.set_value("roster.friendly.screen_pos_x", 0.5)
	Tune.set_value("roster.friendly.portrait_scale", 2.0)
	Tune.set_value("roster.friendly.mirrored", false)
	await get_tree().process_frame
	_assert_approx(fake.spacing, 30.0, "scrubbing roster.friendly.spacing live-updates")
	_assert_approx(fake.screen_pos.x, 0.5, "scrubbing roster.friendly.screen_pos_x live-updates the Vector2.x")
	_assert_approx(fake.portrait_scale, 2.0, "scrubbing roster.friendly.portrait_scale live-updates")
	_assert_true(not fake.mirrored, "scrubbing roster.friendly.mirrored live-updates")

	# A second column under its own namespace is independent.
	var fake2 := FakeRoster.new()
	mgr._bind_one_roster(fake2, "roster.enemy")
	Tune.set_value("roster.enemy.spacing", 99.0)
	await get_tree().process_frame
	_assert_approx(fake2.spacing, 99.0, "roster.enemy.spacing drives the enemy column")
	_assert_approx(fake.spacing, 30.0, "the friendly column is unaffected (independent namespace)")

	mgr.free()
	print("\n=== RosterViewTunablesTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] RosterViewTunablesTest")
		get_tree().quit(1)
	else:
		print("[PASS] RosterViewTunablesTest")
		get_tree().quit(0)


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
