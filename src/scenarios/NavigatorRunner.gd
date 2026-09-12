class_name NavigatorRunner
extends RefCounted

## The runtime navigator's orchestration state machine (HANDOFF T2/T4/T5, decision
## #179). It consumes a [GameNavigator] action plan and drives an injected EXECUTOR
## through the walk, advancing on the sub-scenes' finish signals — the ONLY new logic
## the persistent-world navigator adds on top of the reused ScenarioPathApplier /
## CombatLoop playback primitives.
##
## The executor is duck-typed (the live NavigatorMain implements it against the scene
## layer; tests inject a fake). It must provide:
##   play_scenario(root:int, beats:Array, terminal:bool)  # boot+play a scenario group
##   play_beat(beat:Dictionary)                           # play one woven cinematic beat
##   run_combat(root:int)                                 # start the ENTD battle
##   run_world_map(root:int)                              # mount the overworld screen
## The sub-scenes drive the walk forward by calling back:
##   on_scenario_finished()          # a scenario group's group_finished
##   on_beat_finished()              # an opener/victory cinematic ended
##   on_combat_finished(winner:int)  # CombatLoop.victory (0 = player wins)
##
## v1 defeat (winner != 0) = log + halt: no routing, no game-over (decision #179).
##
## The runner also keeps the Catalog correct as the walk moves (ADR-0201): each action
## carries `mutations` (create/join/leave/die deltas). On a SEEK (`begin_at(N)`) it
## resets the injected catalogue to new-game state and bulk-folds beats `0..N-1` before
## dispatching `N`; while walking, `_advance` applies each beat's delta as the beat is
## reached. One invariant governs both: **before beat `i` dispatches, `catalogue ==
## fold(0..i-1)`**. The catalogue is optional + duck-typed (a live [CharacterCatalog],
## or a test fake); with none injected the runner behaves exactly as before.

const Replay = ExMateriaCatalogue.CatalogueReplay
signal state_changed(state: int)   ## GameState.State the navigator just entered
signal walk_finished()             ## the terminal group completed — walk done
signal defeated()                  ## combat lost; the walk halts here (v1)

var current_state: int = -1
var current_action_index: int = -1

var _actions: Array
var _executor: Object
var _catalogue: Object
var _prologue: Array


## `prologue` (ADR-0201): the catalogue deltas of the groups that come BEFORE this walk's
## first action — non-empty only when a debug SEEK re-roots the plan past the story start
## (e.g. straight into the Orbonne battle). The re-rooted `actions` are just the tail of
## the story walk, so they no longer carry the earlier joins (Delita joins back in group
## 1); folding the prologue first restores the full new-game-to-here catalogue before the
## seeked beat, keeping the "before beat i, catalogue == fold(0..i-1)" invariant honest
## across the re-root. Empty for the canonical top-of-story walk (nothing precedes it).
func _init(actions: Array, executor: Object, catalogue: Object = null, prologue: Array = []) -> void:
	_actions = actions
	_executor = executor
	_catalogue = catalogue
	_prologue = prologue


## Start the walk at the first action.
func begin() -> void:
	begin_at(0)


## Start (SEEK) the walk at action `index` — the debug "seek here" entry point. The
## prior actions are skipped; the executor self-boots whatever world the seeked
## action needs (a scenario group boots its root; a battle beat / combat boots the
## battle world). `index` is clamped into range; <=0 starts from the top.
func begin_at(index: int) -> void:
	if _actions.is_empty():
		current_action_index = 0
		walk_finished.emit()
		return
	var target := clampi(index, 0, _actions.size() - 1)
	# Seek = reset the Catalog to new-game state, then silently fast-replay the skipped
	# beats' deltas (no world boot / render / battle sim). Before beat `target`
	# dispatches, `catalogue == fold(0..target-1)`. begin() = begin_at(0) folds nothing.
	_reset_and_fold(target)
	current_action_index = target
	_dispatch(_actions[target])


func _advance() -> void:
	# The beat we just finished contributes its canonical delta as we leave it, so the
	# invariant holds forward: after beat i completes, `catalogue == fold(0..i)`.
	_apply_current_mutations()
	current_action_index += 1
	if current_action_index >= _actions.size():
		walk_finished.emit()
		return
	_dispatch(_actions[current_action_index])


## --- Catalog fold (ADR-0201) ------------------------------------------------

## Reset the injected catalogue to new-game state and fold beats `0..target-1` into it.
## No-op when no catalogue is injected. `reset_to_new_game` is duck-typed and optional
## (a fake test catalogue implements it; the live one restores its new-game baseline).
func _reset_and_fold(target: int) -> void:
	if _catalogue == null:
		return
	if _catalogue.has_method("reset_to_new_game"):
		_catalogue.reset_to_new_game()
	# Fold the prior-history prologue FIRST (the groups before this re-rooted walk began),
	# then the skipped beats of the re-rooted plan. Together they reconstruct
	# fold(0..target-1) over the WHOLE story, not just this suffix.
	Replay.fold(_prologue, _prologue.size(), _catalogue)
	Replay.fold(_actions, target, _catalogue)


func _apply_current_mutations() -> void:
	# On a SEEK, `_reset_and_fold` already folded `0..target-1`; this then applies the
	# seeked beat's OWN delta once it completes — so it must NOT re-cover the folded
	# beats. That holds only because the current op kinds (create/join/leave/die) are
	# idempotent SET operations (proven by CatalogueReplayTest's refold-is-idempotent).
	# A future NON-idempotent op (e.g. a gil/JP counter delta the extensible op-list
	# anticipates) would double-count on the seek path and needs a different fold seam.
	if _catalogue == null or current_action_index < 0 or current_action_index >= _actions.size():
		return
	Replay.apply_action(_actions[current_action_index], _catalogue)


func _set_state(state: int) -> void:
	if state != current_state:
		current_state = state
		state_changed.emit(state)


func _dispatch(action: Dictionary) -> void:
	match String(action.get("kind", "")):
		"scenario":
			_set_state(GameState.State.SCENARIO)
			_executor.play_scenario(int(action.get("root", -1)),
				action.get("beats", []), bool(action.get("terminal", false)))
		"opener", "victory":
			_set_state(GameState.State.BATTLE)
			_executor.play_beat(action.get("beat", {}))
		"formation_view":
			# The debug-gated formation view (wayfinder #234 E): a view-only overlay bound to
			# the owned roster, shown between the opener and deployment. Non-gating — it yields
			# to on_formation_view_finished and never affects combat. Present in the plan only
			# when navigator.show_formation is set (the proof plan omits it entirely).
			_set_state(GameState.State.FORMATION)
			_executor.run_formation_view(int(action.get("root", -1)))
		"pre_battle":
			# The universal pre-combat setup breakpoint runs for EVERY battle: the executor
			# builds + presents the config and pauses before combat. Predetermined vs
			# roster-fed only changes what happens INSIDE it (fixed config vs placement).
			_set_state(GameState.State.PRE_BATTLE)
			_executor.run_pre_battle(int(action.get("root", -1)))
		"combat":
			_set_state(GameState.State.BATTLE)
			_executor.run_combat(int(action.get("root", -1)))
		"world_map":
			# The overworld the group's `world-map` successor lands on (port-list crossing
			# C2). Terminal for now: the map reports "the player entered node N" to
			# Campaign, and turning that into the next scenario is X1 — ADR-0117 dec. 8,
			# "Campaign picks a Scenario, which points at an event script, which Cutscene
			# plays". Until that lands the walk finishes here instead of one step short.
			_set_state(GameState.State.WORLD_MAP)
			_executor.run_world_map(int(action.get("root", -1)))


## --- Completion callbacks the sub-scenes fire -------------------------------

func on_scenario_finished() -> void:
	_advance()


## The executor calls this when the (view-only) formation overlay is dismissed — the walk
## advances from FORMATION into the pre-battle deployment. Never gates combat (#234 E).
func on_formation_view_finished() -> void:
	_advance()


## The executor calls this when the player confirms the pre-battle config breakpoint (or
## a debug resume fires) — the walk advances from PRE_BATTLE into combat.
func on_pre_battle_finished() -> void:
	_advance()


func on_beat_finished() -> void:
	_advance()


## The executor calls this when the world-map screen is dismissed. The action is
## terminal, so this advances past the end of the plan and emits `walk_finished`.
func on_world_map_finished() -> void:
	_advance()


## winner: 0 = player (advance to the victory beat), else defeat (v1: halt).
func on_combat_finished(winner: int) -> void:
	if winner == 0:
		_advance()
	else:
		push_warning("[NavigatorRunner] combat lost (winner=%d) — v1 halt" % winner)
		defeated.emit()
