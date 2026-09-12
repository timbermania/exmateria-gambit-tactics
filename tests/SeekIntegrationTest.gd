extends Node
## Integration guard for the ADR-0201 seek payoff (spec #191): the REAL
## [NavigatorRunner] driving the REAL [CharacterCatalog] autoload through the DERIVED
## [StoryMutationScript] (ADR-0216) — no scene boot, no render, no battle sim (a fake
## executor records dispatches). Proves that seeking to a later beat resets the Catalog
## to new-game and silently folds the SKIPPED beats' deltas, so the walk arrives with
## the cast the ROM says it should have; and that the reset preserves the player/roster
## baseline.
##
## The cast this asserts moved with the swap, and the move is the point: the authored
## table joined Delita at the Orbonne prologue, where he does not appear. He joins at
## the Military Academy (root 7), which is AFTER the Orbonne battle — so a seek to that
## battle must NOT have him.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/SeekIntegrationTest.tscn

const Character = ExMateriaCatalogue.Character

var _passed: int = 0
var _failed: int = 0


# Records dispatches only — the seek must be INSTANT (no world boot / render / sim).
class FakeExecutor:
	var calls: Array = []
	func play_scenario(root: int, beats: Array, terminal: bool) -> void:
		calls.append({"m": "scenario", "root": root})
	func play_beat(beat: Dictionary) -> void:
		calls.append({"m": "beat", "scn": int(beat.get("scenario_id", -1))})
	func run_combat(root: int) -> void:
		calls.append({"m": "combat", "root": root})
	# The universal pre-combat breakpoint (NavigatorRunner.gd:149). A stub standing in for
	# the executor must mirror its whole interface — without this the dispatch throws
	# `Nonexistent function 'run_pre_battle'` and records NO call at all.
	func run_pre_battle(root: int) -> void:
		calls.append({"m": "pre_battle", "root": root})
	func run_formation_view(root: int) -> void:
		calls.append({"m": "formation_view", "root": root})


func _ready() -> void:
	_test_seek_folds_scripted_cast_and_resets_baseline()
	_test_seek_is_pure_and_reproducible()

	print("\n=== SeekIntegrationTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] SeekIntegrationTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] SeekIntegrationTest")
		get_tree().quit(1)
	else:
		print("[PASS] SeekIntegrationTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


func _actions() -> Array:
	return GameNavigator.new().plan_actions(1, 7, StoryMutationScript.build())


func _test_seek_folds_scripted_cast_and_resets_baseline() -> void:
	# Capture the new-game baseline first (clean Catalog: seeded protagonist + roster),
	# THEN plant a stale scripted guest that a seek must scrub.
	CharacterCatalog.reset_to_new_game()
	_true(CharacterCatalog.has_slug("ramza"), "new-game baseline holds the protagonist")
	CharacterCatalog.register(Character.new("ghost", "Ghost"))
	_true(CharacterCatalog.has_slug("ghost"), "planted a stale non-baseline guest")

	var exec := FakeExecutor.new()
	var acts := _actions()
	# Locate the Orbonne combat by KIND, not by a hardcoded index. A battle group expands
	# to opener -> pre_battle -> combat -> victory (GameNavigator.gd:150), so inserting the
	# universal pre_battle breakpoint shifted combat from index 2 to 3 and this seek landed
	# on the wrong action. What the test is about is the seek's fold/reset behaviour, not
	# the plan's arity — so ask the plan where combat is.
	var combat_idx := -1
	for i in range(acts.size()):
		if String(acts[i].get("kind", "")) == "combat":
			combat_idx = i
			break
	_true(combat_idx >= 0, "the plan contains a combat action to seek to")
	var runner := NavigatorRunner.new(acts, exec, CharacterCatalog)
	runner.begin_at(combat_idx)  # seek to the Orbonne combat: reset + fold every earlier action

	# The skipped intro beat's `join ramza` folded in, and so did the Orbonne opener's
	# appearance cast — the walk arrives with the battle's own named units bound.
	_true(CharacterCatalog.has_slug("agrias"), "seek folded the Orbonne appearance cast (agrias)")
	# Delita joins at the ACADEMY (root 7), which the Orbonne battle precedes — so the
	# seek must not have run ahead of the ROM and handed him over early.
	_true(not CharacterCatalog.has_slug("delita"),
		"delita has NOT joined at the Orbonne battle (he joins at the Academy, root 7)")
	# The reset scrubbed the stale guest but kept the new-game baseline.
	_true(not CharacterCatalog.has_slug("ghost"), "seek reset dropped the stale guest")
	_true(CharacterCatalog.has_slug("ramza"), "seek reset kept the protagonist baseline")
	# Algus recruits at Mandalia Plains (root 15), far past this plan entirely.
	_true(not CharacterCatalog.has_slug("algus"), "algus is not folded — he recruits at root 15")
	# The seek dispatched the combat action and nothing else — instant, one drive call.
	_eq(exec.calls.size(), 1, "seek dispatches exactly one action")
	_eq(String(exec.calls[0]["m"]), "combat", "seek dispatched the combat action")


func _test_seek_is_pure_and_reproducible() -> void:
	# Two independent seeks to the same target leave the same scripted membership — the
	# seek is a pure function of (mutation_script, target).
	var runner_a := NavigatorRunner.new(_actions(), FakeExecutor.new(), CharacterCatalog)
	runner_a.begin_at(99)  # clamps to the last action (the academy) — folds everything before it
	var after_a := [CharacterCatalog.has_slug("ramza"), CharacterCatalog.has_slug("agrias"),
		CharacterCatalog.has_slug("delita")]

	var runner_b := NavigatorRunner.new(_actions(), FakeExecutor.new(), CharacterCatalog)
	runner_b.begin_at(99)
	var after_b := [CharacterCatalog.has_slug("ramza"), CharacterCatalog.has_slug("agrias"),
		CharacterCatalog.has_slug("delita")]

	_eq(after_a, after_b, "repeated seek to the same target is reproducible")
	# The academy IS the terminal action, and a group grants its recruits as the walk
	# LEAVES it — so seeking onto it folds everything before it and not Delita himself.
	_true(not CharacterCatalog.has_slug("delita"),
		"the seeked terminal group has not granted its own recruits yet")
