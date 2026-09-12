extends Node
## Integration guard for [NavigatorMain.run_pre_battle] — the UNIVERSAL pre-battle config
## breakpoint. Bare-constructs a NavigatorMain (no scene boot; mirrors NavigatorCombatRevealTest),
## points it at a real ENTD, injects a fake runner, and asserts the breakpoint is universal:
## run_pre_battle PAUSES (does not advance) for BOTH a predetermined battle (Orbonne 387)
## and a roster-fed one (Gariland 388); `resume_pre_battle` then advances to combat. The
## control flag only changes what the setup HOSTS — the pause itself is always present
## (there is always a battle to set up).
##
## Also guards [code]_unit_at_grid[/code], the "which unit stands here?" callable this host hands
## the map-hosted Formation screen at Deployment. It lives here because this is the bare-construct
## navigator harness: the live path reaches it only if the map host wins a one-frame race against
## the proof test's own quit, so a live arm would guard it only sometimes.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/NavigatorPreBattleTest.tscn

var _passed: int = 0
var _failed: int = 0


class FakeRunner:
	extends NavigatorRunner
	var finished: int = 0
	func _init() -> void: super([], null)
	func on_pre_battle_finished() -> void: finished += 1


## ADR-0212 dec. 1 / ADR-0211 dec. 4 — `addons/exmateria_schema` declares only
## `ExMateriaSchema`, so this line is what keeps the use sites below spelled the way they were.
const TerrainCell = ExMateriaSchema.TerrainCell


## Minimal stand-in for a placed Unit: `_unit_at_grid` asks exactly one question of each
## registry entry, so answering it is the whole contract.
## Counts `settle_screen_effects()` — the ONE question the arm below asks of the VM.
class SettleCountingVM extends Node:
	var calls: int = 0
	func settle_screen_effects() -> void: calls += 1


class CellStub extends Node:
	var cell: Vector3i
	func _init(c: Vector3i) -> void: cell = c
	func get_current_cell() -> Vector3i: return cell


const SKIP_SLUG := "navigator.skip_pre_battle"


func _ready() -> void:
	_test_pauses_then_resumes("387", 3, "Orbonne (predetermined)")
	_test_pauses_then_resumes("388", 9, "Gariland (roster-fed)")
	_test_resume_is_noop_when_not_parked()
	_test_skip_tunable_bypasses_pause()
	_test_unit_at_grid_answers_the_column()
	_test_walk_path_does_not_settle_screen_effects()

	print("\n=== NavigatorPreBattleTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorPreBattleTest: ran zero assertions"); get_tree().quit(1); return
	if _failed > 0:
		print("[FAIL] NavigatorPreBattleTest"); get_tree().quit(1)
	else:
		print("[PASS] NavigatorPreBattleTest"); get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want: _passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])

func _true(c: bool, name: String) -> void: _eq(c, true, name)


func _new_nav() -> Node:
	return load("res://src/scenarios/NavigatorMain.gd").new()


func _test_pauses_then_resumes(entd_key: String, root: int, label: String) -> void:
	var nav := _new_nav()
	var runner := FakeRunner.new()
	nav._nav_runner = runner
	nav._entd_record = entd_key

	nav.run_pre_battle(root)
	# The breakpoint is UNIVERSAL: it parks and does NOT advance until confirmed.
	_true(nav._pre_battle_active, "%s: parks at the pre-battle config breakpoint" % label)
	_eq(runner.finished, 0, "%s: does NOT advance to combat until confirmed" % label)

	nav.resume_pre_battle()
	_true(not nav._pre_battle_active, "%s: resume clears the pause" % label)
	_eq(runner.finished, 1, "%s: resume advances to combat" % label)
	nav.free()


## The AUTOSAVE "skip pre-battle breakpoints" toggle bypasses the pause entirely (the
## pre-battle analogue of dialogue auto-advance): the walk goes straight to combat.
func _test_skip_tunable_bypasses_pause() -> void:
	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(SKIP_SLUG, true)   # in-memory only (no file write from set_value)

	var nav := _new_nav()
	var runner := FakeRunner.new()
	nav._nav_runner = runner
	nav._entd_record = "387"
	nav.run_pre_battle(3)
	_true(not nav._pre_battle_active, "skip toggle: does NOT park at the breakpoint")
	_eq(runner.finished, 1, "skip toggle: advances straight to combat")
	nav.free()

	Tune.clear(SKIP_SLUG)   # drop the override so the default (pause) is restored


## `_ensure_battle_world` MUST NOT settle the VM's screen effects on the ordinary linear
## walk — #1168, and the second half of the READY!-fadeout freeze.
##
## `settle_screen_effects()` is the SEEK's fast-forward guarantee: a direct seek replays the
## opener at 30x and can park with a ramp mid-flight, so every ramp is snapped to its
## committed end-state. On the walk nothing was fast-forwarded and those ramps are real
## authored animations playing at 1x — and the call used to sit one line further out, where
## the walk reached it too. What it snapped was `{77}`'s 112-frame dark-screen retract: the
## last 1.87 s of the battle intro vanished in a single frame.
##
## ONE ARM, deliberately. `_battle_world_root != root` is the seek predicate, and that branch
## `await`s `_boot_world_for` -> `_boot_scenario_world`, which a bare-construct host has no
## world to do. The arm that is reachable here is the one that REGRESSED; the positive
## control below is on the instrument, so a zero cannot come from a stub nobody called.
func _test_walk_path_does_not_settle_screen_effects() -> void:
	var nav := _new_nav()
	var vm := SettleCountingVM.new()
	nav._vm = vm

	# THE INSTRUMENT'S POSITIVE CONTROL. A counter that never counts and a walk that never
	# settles read identically; this is what tells them apart — and it also pins the method
	# NAME, which is the whole of what `has_method` gates on at the call site.
	vm.settle_screen_effects()
	_eq(vm.calls, 1, "settle guard: the counting stub does count (positive control)")
	vm.calls = 0

	# The linear walk: `play_beat` already booted this group's world and stamped the root,
	# so `_ensure_battle_world` has nothing to boot and nothing to fast-forward.
	nav._battle_world_root = 9
	nav._ensure_battle_world(9)
	_eq(vm.calls, 0,
		"settle guard: the walk path does NOT snap the VM's in-flight screen effects")

	vm.free()
	nav.free()


func _test_resume_is_noop_when_not_parked() -> void:
	var nav := _new_nav()
	var runner := FakeRunner.new()
	nav._nav_runner = runner
	nav.resume_pre_battle()  # not parked
	_eq(runner.finished, 0, "resume is a no-op when not parked")
	nav.free()


## A unit whose logical cell is on any LEVEL of the cursor's column answers for that column, and a
## unit with no logical tile answers for nothing.
##
## The regression: `get_current_cell()` returns the level-aware `Vector3i` (ADR-0219 / #795) and
## `grid_pos` is the cursor's `Vector2i` column, so comparing them directly is not a false result —
## it is `Invalid operands 'Vector3i' and 'Vector2i' in operator '=='`, which aborts the enclosing
## function on its FIRST unit. Every tile then answered `null`, which reads as "empty tile" and
## fails nothing; the only trace was a `SCRIPT ERROR:` line. So the arm below is written to fail on
## the ANSWER (`want`, not `null`), not on the error text — the same defect must be caught by a
## test that never reads stdout.
func _test_unit_at_grid_answers_the_column() -> void:
	var nav := _new_nav()
	var ground := CellStub.new(Vector3i(4, 7, 0))
	var upper := CellStub.new(Vector3i(2, 3, 2))     # same question, a level off the ground
	var nowhere := CellStub.new(TerrainCell.NONE)    # spawned, never placed
	nav._units_by_id = {0x80: nowhere, 0x01: ground, 0x78: upper}

	_eq(nav._unit_at_grid(Vector2i(4, 7)), ground, "_unit_at_grid finds the unit on the column")
	_eq(nav._unit_at_grid(Vector2i(2, 3)), upper,
		"_unit_at_grid answers for a unit standing above the ground level of the column")
	_eq(nav._unit_at_grid(Vector2i(9, 9)), null, "_unit_at_grid answers null for an empty column")
	# The un-placed unit must not answer for the sentinel's own column.
	_eq(nav._unit_at_grid(Vector2i(TerrainCell.NONE.x, TerrainCell.NONE.y)), null,
		"a unit with no logical tile stands nowhere")

	ground.free(); upper.free(); nowhere.free(); nav.free()
