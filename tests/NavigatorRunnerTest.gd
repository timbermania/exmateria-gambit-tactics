extends Node
## Pure-logic guard (no live scene/VM/GPU) for [NavigatorRunner] — the runtime
## navigator's orchestration state machine (HANDOFF T2/T4/T5, decision #179). It
## consumes GameNavigator.plan_actions and drives an injected EXECUTOR (the live
## NavigatorMain implements it against ScenarioPathApplier / CombatLoop), advancing
## the walk on the real finish signals: a scenario group's group_finished, a woven
## cinematic beat's finish, and CombatLoop.victory. v1 defeat = log + halt.
##
## Tested against a FAKE executor that records the drive calls and lets the test fire
## the completion callbacks — so the SCENARIO -> BATTLE(opener->combat->victory) ->
## SCENARIO control flow is proven headlessly.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/NavigatorRunnerTest.tscn

const GS := preload("res://src/scenarios/GameState.gd")
const CatalogueReplay = ExMateriaCatalogue.CatalogueReplay
const Character = ExMateriaCatalogue.Character

var _passed: int = 0
var _failed: int = 0


# A fake executor: records each drive call so the test can assert the order. If a
# `catalogue` is attached, each call also snapshots the catalogue membership AT DISPATCH
# TIME — the seam the fold-before-dispatch invariant is asserted against.
class FakeExecutor:
	var calls: Array = []
	var catalogue = null
	func _snap() -> Array:
		return catalogue.slugs() if catalogue != null else []
	func play_scenario(root: int, beats: Array, terminal: bool) -> void:
		calls.append({"m": "scenario", "root": root, "beats": beats.size(), "terminal": terminal, "snap": _snap()})
	func play_beat(beat: Dictionary) -> void:
		calls.append({"m": "beat", "scn": int(beat.get("scenario_id", -1)), "snap": _snap()})
	func run_pre_battle(root: int) -> void:
		calls.append({"m": "pre_battle", "root": root, "snap": _snap()})
	func run_formation_view(root: int) -> void:
		calls.append({"m": "formation_view", "root": root, "snap": _snap()})
	func run_combat(root: int) -> void:
		calls.append({"m": "combat", "root": root, "snap": _snap()})


# A fake catalogue: the duck-typed surface the runner folds into (register/unregister/
# reset_to_new_game). new-game state here is EMPTY, so an expected snapshot is just the
# CatalogueReplay fold over a fresh instance.
class FakeCatalogue:
	var chars: Dictionary = {}
	func register(character) -> void:
		chars[character.slug] = character
	func unregister(slug: String) -> void:
		chars.erase(slug)
	func reset_to_new_game() -> void:
		chars.clear()
	func slugs() -> Array:
		var out: Array = chars.keys()
		out.sort()
		return out


func _ready() -> void:
	_test_happy_path_drive()
	_test_formation_view_dispatch()
	_test_defeat_halts()
	_test_begin_at_seeks_mid_walk()
	_test_begin_at_clamps_and_defaults()
	_test_fold_before_dispatch_invariant_walking()
	_test_fold_before_dispatch_invariant_seeking()
	_test_seek_folds_prologue_history()
	_test_begin_at_zero_equals_begin_catalogue()

	print("\n=== NavigatorRunnerTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorRunnerTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorRunnerTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorRunnerTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


# --- Slice 1: drive SCENARIO -> opener -> combat -> victory -> terminal SCENARIO ---
func _test_happy_path_drive() -> void:
	var actions := GameNavigator.new().plan_actions(1, 7)
	var exec := FakeExecutor.new()
	var runner := NavigatorRunner.new(actions, exec)

	var finished := [false]
	runner.walk_finished.connect(func(): finished[0] = true)

	runner.begin()
	# Action 0: play the grp1 scenario group; runner sits in SCENARIO.
	_eq(runner.current_state, GS.State.SCENARIO, "begin -> SCENARIO")
	_eq(exec.calls.size(), 1, "one drive call after begin")
	_eq(String(exec.calls[0]["m"]), "scenario", "first drive = play_scenario")
	_eq(int(exec.calls[0]["root"]), 1, "grp1 scenario driven")

	# grp1 finishes -> opener cinematic (scn4), state flips to BATTLE.
	runner.on_scenario_finished()
	_eq(runner.current_state, GS.State.BATTLE, "opener -> BATTLE")
	_eq(String(exec.calls[1]["m"]), "beat", "opener drive = play_beat")
	_eq(int(exec.calls[1]["scn"]), 4, "opener beat = scn4")

	# opener finishes -> PRE-BATTLE setup breakpoint (before combat). Runs for EVERY battle
	# and the runner enters the PRE_BATTLE state (universal config pause).
	runner.on_beat_finished()
	_eq(String(exec.calls[2]["m"]), "pre_battle", "pre_battle driven after opener")
	_eq(int(exec.calls[2]["root"]), 3, "pre_battle root=3")
	_eq(runner.current_state, GS.State.PRE_BATTLE, "pre_battle -> PRE_BATTLE state")

	# pre-battle confirmed -> run combat (ENTD 387, root 3).
	runner.on_pre_battle_finished()
	_eq(String(exec.calls[3]["m"]), "combat", "combat driven after pre_battle")
	_eq(int(exec.calls[3]["root"]), 3, "combat root=3")
	_eq(runner.current_state, GS.State.BATTLE, "combat stays BATTLE")

	# player victory -> victory cinematic (scn6).
	runner.on_combat_finished(0)  # winner 0 = player
	_eq(String(exec.calls[4]["m"]), "beat", "victory drive = play_beat")
	_eq(int(exec.calls[4]["scn"]), 6, "victory beat = scn6")

	# victory beat finishes -> terminal grp7 scenario; state back to SCENARIO.
	runner.on_beat_finished()
	_eq(runner.current_state, GS.State.SCENARIO, "terminal -> SCENARIO")
	_eq(String(exec.calls[5]["m"]), "scenario", "terminal drive = play_scenario")
	_eq(int(exec.calls[5]["root"]), 7, "terminal grp7")
	_true(bool(exec.calls[5]["terminal"]), "terminal flag set")

	# grp7 completes -> the walk is finished; no further drive calls.
	runner.on_scenario_finished()
	_true(finished[0], "walk_finished emitted")
	_eq(exec.calls.size(), 6, "no drive calls past the terminal group")


# --- Slice E2: the debug-gated formation_view dispatches to run_formation_view ---
# (FORMATION state, view-only, non-gating: on_formation_view_finished advances the walk.)
func _test_formation_view_dispatch() -> void:
	var actions := [
		{"kind": "opener", "beat": {"scenario_id": 10}},
		{"kind": "formation_view", "root": 9},
		{"kind": "pre_battle", "root": 9},
	]
	var exec := FakeExecutor.new()
	var runner := NavigatorRunner.new(actions, exec)

	runner.begin()  # dispatch opener
	_eq(String(exec.calls[0]["m"]), "beat", "begins on the opener beat")

	runner.on_beat_finished()  # opener done → formation_view
	_eq(String(exec.calls[1]["m"]), "formation_view", "opener → run_formation_view")
	_eq(int(exec.calls[1]["root"]), 9, "formation_view root=9")
	_eq(runner.current_state, GS.State.FORMATION, "formation_view → FORMATION state")

	runner.on_formation_view_finished()  # view dismissed → pre_battle
	_eq(String(exec.calls[2]["m"]), "pre_battle", "formation dismissed → pre_battle")
	_eq(runner.current_state, GS.State.PRE_BATTLE, "advances into PRE_BATTLE")


# --- Slice 3: begin_at seeks the walk to a mid-plan action (debug "seek here") ---
func _test_begin_at_seeks_mid_walk() -> void:
	# plan_actions(1,7) = [scenario1, opener4, pre_battle3, combat3, victory6, scenario7].
	# Seeking to index 3 must dispatch the COMBAT action first — the prior beats are skipped.
	var actions := GameNavigator.new().plan_actions(1, 7)
	var exec := FakeExecutor.new()
	var runner := NavigatorRunner.new(actions, exec)

	runner.begin_at(3)
	_eq(runner.current_action_index, 3, "begin_at(3) -> action index 3")
	_eq(exec.calls.size(), 1, "one drive call after begin_at")
	_eq(String(exec.calls[0]["m"]), "combat", "seek to index 3 drives combat")
	_eq(int(exec.calls[0]["root"]), 3, "combat root=3")
	_eq(runner.current_state, GS.State.BATTLE, "seek to combat -> BATTLE state")

	# From the seek point the walk continues forward normally.
	runner.on_combat_finished(0)
	_eq(String(exec.calls[1]["m"]), "beat", "continues to victory beat after the seek")
	_eq(int(exec.calls[1]["scn"]), 6, "victory beat = scn6")


# --- Slice 3b: begin_at clamps out-of-range and treats <=0 like begin() ---
func _test_begin_at_clamps_and_defaults() -> void:
	var actions := GameNavigator.new().plan_actions(1, 7)

	# Index past the end -> clamps to the last action (still dispatches one).
	var exec_hi := FakeExecutor.new()
	var runner_hi := NavigatorRunner.new(actions, exec_hi)
	runner_hi.begin_at(999)
	_eq(runner_hi.current_action_index, actions.size() - 1, "begin_at(too-big) clamps to last")
	_eq(String(exec_hi.calls[0]["m"]), "scenario", "clamped seek drives the terminal grp7")

	# Index 0 (or negative) behaves like begin() — start from the top.
	var exec_lo := FakeExecutor.new()
	var runner_lo := NavigatorRunner.new(actions, exec_lo)
	runner_lo.begin_at(-5)
	_eq(runner_lo.current_action_index, 0, "begin_at(negative) starts at 0")
	_eq(int(exec_lo.calls[0]["root"]), 1, "starts at grp1")


# --- ADR-0201: the fold-before-dispatch invariant (walking + seeking) ---------

# A hand-built mutation-carrying plan (independent of the Ch1 data). Membership at
# fold(N) = {}, {ramza}, {ramza,delita}, {ramza,delita}, {ramza}, {ramza,agrias}.
func _mutation_plan() -> Array:
	return [
		{"kind": "scenario", "root": 1, "beats": [], "terminal": false,
			"mutations": [{"op": "create", "slug": "ramza"}]},
		{"kind": "opener", "beat": {"scenario_id": 4},
			"mutations": [{"op": "join", "slug": "delita"}]},
		{"kind": "combat", "root": 3, "mutations": []},
		{"kind": "victory", "beat": {"scenario_id": 6},
			"mutations": [{"op": "die", "slug": "delita"}]},
		{"kind": "scenario", "root": 7, "beats": [], "terminal": true,
			"mutations": [{"op": "create", "slug": "agrias"}]},
	]


# The expected catalogue membership BEFORE beat `i` dispatches = fold(0..i-1).
func _expected_fold(actions: Array, i: int) -> Array:
	var cat := FakeCatalogue.new()
	# reference-fold via CatalogueReplay so the test measures the same engine.
	CatalogueReplay.fold(actions, i, cat)
	return cat.slugs()


func _test_fold_before_dispatch_invariant_walking() -> void:
	var actions := _mutation_plan()
	var cat := FakeCatalogue.new()
	var exec := FakeExecutor.new()
	exec.catalogue = cat
	var runner := NavigatorRunner.new(actions, exec, cat)

	# Walk the whole plan, driving each finish callback. The runner dispatches beats
	# 0..4; assert every dispatch snapshot equals fold(0..i-1).
	runner.begin()                    # dispatch beat 0
	runner.on_scenario_finished()     # beat 0 done -> dispatch beat 1
	runner.on_beat_finished()         # beat 1 done -> dispatch beat 2 (combat)
	runner.on_combat_finished(0)      # beat 2 done -> dispatch beat 3
	runner.on_beat_finished()         # beat 3 done -> dispatch beat 4

	_eq(exec.calls.size(), 5, "walked all 5 beats")
	for i in range(exec.calls.size()):
		_eq(exec.calls[i]["snap"], _expected_fold(actions, i),
			"walk: before beat %d, catalogue == fold(0..%d)" % [i, i - 1])
	# And after the terminal beat completes, the final fold is fold(0..4).
	runner.on_scenario_finished()
	_eq(cat.slugs(), _expected_fold(actions, actions.size()), "walk end == fold(all)")


func _test_fold_before_dispatch_invariant_seeking() -> void:
	var actions := _mutation_plan()
	var cat := FakeCatalogue.new()
	var exec := FakeExecutor.new()
	exec.catalogue = cat
	var runner := NavigatorRunner.new(actions, exec, cat)

	# Seed the catalogue with stale entries: the seek MUST reset before folding.
	cat.register(Character.new("stale", "Stale"))

	runner.begin_at(3)  # reset -> fold(0..2) -> dispatch beat 3
	_eq(exec.calls.size(), 1, "seek dispatches exactly one beat")
	_eq(exec.calls[0]["snap"], _expected_fold(actions, 3),
		"seek: before beat 3, catalogue == fold(0..2) (reset dropped 'stale')")

	# Continuing forward from the seek keeps the invariant.
	runner.on_beat_finished()  # beat 3 done -> dispatch beat 4
	_eq(exec.calls[1]["snap"], _expected_fold(actions, 4),
		"seek+continue: before beat 4, catalogue == fold(0..3)")


# --- ADR-0201: a re-rooted SEEK folds the prior-history PROLOGUE first ---------
# The debug seek can re-root the walk at a later group (e.g. straight to the Orbonne
# battle). The re-rooted plan omits the earlier groups' actions — and with them the
# cumulative joins authored there (Delita joins back in group 1). The runner takes a
# `prologue` (those prior actions) and folds it before the re-rooted plan, so a seeked
# battle inherits the full new-game-to-here catalogue, not just the suffix.
func _expected_with_prologue(prologue: Array, suffix: Array, i: int) -> Array:
	var cat := FakeCatalogue.new()
	CatalogueReplay.fold(prologue, prologue.size(), cat)
	CatalogueReplay.fold(suffix, i, cat)
	return cat.slugs()


func _test_seek_folds_prologue_history() -> void:
	var full := _mutation_plan()
	# Split the full walk: groups BEFORE the seek root (prologue) vs the re-rooted plan.
	# fold(prologue) = {ramza, delita}; the re-rooted plan starts at the combat beat.
	var prologue := [full[0], full[1]]           # scenario1 (create ramza) + opener4 (join delita)
	var suffix := [full[2], full[3], full[4]]    # combat3, victory6 (die delita), terminal (create agrias)
	var cat := FakeCatalogue.new()
	var exec := FakeExecutor.new(); exec.catalogue = cat
	var runner := NavigatorRunner.new(suffix, exec, cat, prologue)

	# Stale seed the reset must drop; the prologue then folds the real prior history.
	cat.register(Character.new("stale", "Stale"))

	runner.begin_at(0)  # reset -> fold(prologue) -> fold(suffix,0) -> dispatch suffix[0]
	_eq(exec.calls.size(), 1, "prologue seek dispatches exactly one beat")
	_eq(exec.calls[0]["snap"], _expected_with_prologue(prologue, suffix, 0),
		"re-rooted seek: prior-history prologue (ramza,delita) present before the seeked combat beat")

	# The walk continues forward, keeping prologue+suffix folded consistently.
	runner.on_combat_finished(0)  # combat done -> dispatch victory (die delita)
	_eq(exec.calls[1]["snap"], _expected_with_prologue(prologue, suffix, 1),
		"re-rooted seek+continue: before victory beat, catalogue still (ramza,delita)")
	runner.on_beat_finished()     # victory done (delita dies) -> dispatch terminal
	_eq(exec.calls[2]["snap"], _expected_with_prologue(prologue, suffix, 2),
		"re-rooted seek+continue: after delita dies, before terminal, catalogue == (ramza)")


func _test_begin_at_zero_equals_begin_catalogue() -> void:
	var actions := _mutation_plan()

	var cat_a := FakeCatalogue.new()
	var exec_a := FakeExecutor.new(); exec_a.catalogue = cat_a
	var runner_a := NavigatorRunner.new(actions, exec_a, cat_a)
	runner_a.begin()

	var cat_b := FakeCatalogue.new()
	var exec_b := FakeExecutor.new(); exec_b.catalogue = cat_b
	var runner_b := NavigatorRunner.new(actions, exec_b, cat_b)
	runner_b.begin_at(0)

	_eq(exec_a.calls[0]["snap"], exec_b.calls[0]["snap"], "begin() and begin_at(0) dispatch beat 0 with identical catalogue")
	_eq(exec_a.calls[0]["snap"], [], "begin() dispatches beat 0 at new-game state (empty)")


# --- Slice 2: v1 defeat halts — no victory beat, no walk_finished ---
func _test_defeat_halts() -> void:
	var actions := GameNavigator.new().plan_actions(1, 7)
	var exec := FakeExecutor.new()
	var runner := NavigatorRunner.new(actions, exec)

	var lost := [false]
	var finished := [false]
	runner.defeated.connect(func(): lost[0] = true)
	runner.walk_finished.connect(func(): finished[0] = true)

	# Drive through to combat.
	runner.begin()
	runner.on_scenario_finished()   # grp1 -> opener
	runner.on_beat_finished()       # opener -> pre_battle
	runner.on_pre_battle_finished() # pre_battle -> combat
	var calls_at_combat := exec.calls.size()

	# Enemy wins -> halt: defeated fires, no victory beat played, no walk_finished.
	runner.on_combat_finished(1)    # winner 1 = enemy
	_true(lost[0], "defeated emitted on enemy win")
	_true(not finished[0], "walk NOT finished on defeat")
	_eq(exec.calls.size(), calls_at_combat, "no victory beat driven after defeat")
	_eq(runner.current_state, GS.State.BATTLE, "stays in BATTLE after defeat")
