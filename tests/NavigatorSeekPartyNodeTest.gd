extends Node
## A SEEK must re-root the party MARKER, not just the story variables.
##
## The reported defect, in the player's words: *seek to root 28, let it play out onto the
## world map — Ramza is standing in Magic City Gariland instead of Igros Castle, and the
## next root's location is never revealed. Walking back to Igros by hand reveals it.*
##
## Both halves are ONE stale value. [member WorldMapProgress._party_node] is written only
## by the map's own arrival path, so a walk that never travelled kept
## [method WorldMapProgress.new_campaign]'s seed — node 7, Gariland. The map draws its
## marker there, AND [method WorldMapScene._start_reveal_pass] is handed
## `progress.party_node()` (ADR-0230 dec. 8), so the opening pass ran at Gariland, which
## owes nothing at story counter 4. The four reveal steps that light Sweegy Woods sit on
## Igros — exactly where ADR-0230's Prediction 1 says "the marker is standing".
##
## [b]Nothing here seeds the party node.[/b] [CampaignRevealPassTest]'s map-open arm calls
## `p.set_party_node(3)` by hand and is green against this defect unchanged, because it
## hands the map the very value production never computed. This test asks the production
## function for it instead.
##
## Run: <GODOT> --path . --quit-after 10 res://tests/NavigatorSeekPartyNodeTest.tscn

var _passed := 0
var _failed := 0

const NAVIGATOR_MAIN := preload("res://src/scenarios/NavigatorMain.gd")

## Place 3 == node index 2 == Igros Castle. The screen counts from 1, the store from 0.
const IGROS_PLACE := 3
const IGROS_INDEX := 2
## `new_campaign()`'s seed, and the wrong answer this test exists for.
const GARILAND_PLACE := 7
## What group 28's own scenarios write as they play — scenario 29 runs `Zero(110)` then
## `Add(110, 4)`, so the map opens at story counter 4.
const COUNTER_AFTER_ROOT_28 := 4
const SWEEGY_INDEX := 26

## `seek root → the group whose enter state places the party`. The chain-reached roots are
## the point: 28 (Citadel of Igros Castle) chains off 26 (Office of Igros Castle), which
## the map offers at Igros; 24 chains off 15 at Mandalia; 37 chains off 33 at Dorter.
const ANCHORS := [
	[26, 26], [30, 30], [33, 33],     # entered from the map — its own anchor
	[28, 26], [24, 15], [37, 33],     # chain-reached — the nearest entered group before it
	[1, -1], [3, -1],                 # the prologue: nothing at or before it is entered
]


func _ready() -> void:
	_test_the_enter_anchor()
	_test_the_seek_installs_the_marker()
	_test_the_marker_is_what_makes_the_reveal_land()
	_test_the_seed_is_the_defect()

	if _failed > 0:
		print("[FAIL] NavigatorSeekPartyNodeTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] NavigatorSeekPartyNodeTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


# ---------------------------------------------------------------- the arms

func _test_the_enter_anchor() -> void:
	for row in ANCHORS:
		var root: int = row[0]
		_eq("enter anchor of root %d" % root, NAVIGATOR_MAIN._enter_anchor(root), int(row[1]))


## The production function, driven directly. `_install_world_state` touches only Campaign
## and RosterTimeline, so the scene never has to boot.
func _test_the_seek_installs_the_marker() -> void:
	var keep := Campaign.progress
	var p := WorldMapProgress.new_campaign()
	Campaign.progress = p
	_eq("before the seek the marker is on the seed", p.party_node(), GARILAND_PLACE)

	var nav := NAVIGATOR_MAIN.new()
	nav._install_world_state(28)
	nav.free()

	_eq("seek 28 stands the party at Igros Castle", p.party_node(), IGROS_PLACE)
	Campaign.progress = keep


## The payoff: with the marker where the seek put it, the map's opening pass drains the
## four steps that light Sweegy Woods. This is the reported symptom, end to end.
func _test_the_marker_is_what_makes_the_reveal_land() -> void:
	var keep := Campaign.progress
	var p := WorldMapProgress.new_campaign()
	Campaign.progress = p
	var nav := NAVIGATOR_MAIN.new()
	nav._install_world_state(28)
	nav.free()
	# The group then plays, and its own scenarios advance the counter.
	p.set_story_counter(COUNTER_AFTER_ROOT_28)
	_eq("counter 4: the one live enter is Sweegy Woods",
			str(Campaign.live_enter_nodes()), "[%d]" % SWEEGY_INDEX)
	_true("...and it is unknown before the map opens", not p.is_node_known(SWEEGY_INDEX))

	# Exactly what `WorldMapScene._start_reveal_pass(progress.party_node())` hands the
	# animation. Drained rather than paced here: ADR-0231 moved WHEN the steps land, and
	# this arm is about WHICH NODE the pass is asked for.
	_eq("the opening pass at the marker owes four steps",
			_drain(Campaign.place_to_index(p.party_node()), p), 4)
	_true("...and Sweegy Woods is revealed", p.is_node_known(SWEEGY_INDEX))
	Campaign.progress = keep


## The control, so the arm above cannot pass for the wrong reason: run the SAME pass from
## the seed the defect left in place and watch it owe nothing. Without this the assertion
## "four steps landed" is compatible with the party node being irrelevant.
func _test_the_seed_is_the_defect() -> void:
	var keep := Campaign.progress
	var p := WorldMapProgress.new_campaign()
	Campaign.progress = p
	p.set_story_counter(COUNTER_AFTER_ROOT_28)
	_eq("from the Gariland seed the same pass owes nothing",
			_drain(Campaign.place_to_index(GARILAND_PLACE), p), 0)
	_true("...so Sweegy Woods stays hidden", not p.is_node_known(SWEEGY_INDEX))
	_eq("...while Igros owes the four", _drain(IGROS_INDEX, p), 4)
	Campaign.progress = keep


# ---------------------------------------------------------------- helpers

## Drain a whole reveal pass — what [method WorldMapScene._start_reveal_pass] hands to
## [WorldMapRevealAnimation], which paces it (ADR-0231) — and
## return the step count.
func _drain(node_index: int, store: WorldMapProgress) -> int:
	var pass_ := Campaign.reveal_pass(node_index, store)
	var steps := 0
	while true:
		if pass_.step().is_empty():
			break
		steps += 1
	return steps


func _eq(what: String, got: Variant, want: Variant) -> void:
	if got == want:
		_passed += 1
		return
	_failed += 1
	printerr("  [x] %s — got %s, want %s" % [what, str(got), str(want)])


func _true(what: String, cond: bool) -> void:
	_eq(what, cond, true)
