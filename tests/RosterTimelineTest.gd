extends Node
## Guard for [RosterTimeline] — the derived story timeline that replaces the four
## hand-authored mutation keys and gives a Seek its world-map state.
##
## The cases that matter are the ones the hand-authored version got WRONG and the one
## the user actually reported:
##   * the starting generics are granted at root 7 (Military Academy) and there are SIX;
##     root 9 (Gariland) grants nobody, though it deploys what the Academy granted
##   * Mustadio GUESTS at Zaland and only joins at Goug, so a Seek to Zaland must not
##     arrive with him
##   * seeking root 59 (Mandalia Plains) must install var[110]=10 so the map offers node
##     59 — it used to sit at story counter 1, offer Beoulve Residence, and chain forward
##     through the entire game
##
## Pure data + one live store write. No scene, no GPU.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/RosterTimelineTest.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_academy_grants_six_generics_gariland_grants_none()
	_test_gariland_arrives_with_the_academy_roster()
	_test_the_protagonist_is_present_from_the_first_battle()
	_test_mustadio_guests_at_zaland_and_joins_at_goug()
	_test_worker_8_is_recruited_at_the_activation_cinematic()
	_test_seek_state_for_the_reported_runaway()
	_test_chained_group_has_no_enter_state()
	_test_gating_vars_do_not_wipe_the_map_reveal_range()
	_test_installing_enter_vars_makes_the_map_offer_that_node()
	_test_every_battle_groups_opener_is_the_one_the_navigator_plans()
	_test_appearances_are_battle_scoped_and_never_owned()

	print("\n=== RosterTimelineTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] RosterTimelineTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] RosterTimelineTest")
		get_tree().quit(1)
	else:
		print("[PASS] RosterTimelineTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


func _test_academy_grants_six_generics_gariland_grants_none() -> void:
	var generics: Array = []
	for delta in RosterTimeline.joins_for(7):
		if not bool(delta.get("canonical", false)):
			generics.append(delta)
	_eq(generics.size(), 6, "the Academy grants six generics")
	_eq(RosterTimeline.joins_for(9).size(), 0, "Gariland grants nobody")


func _test_gariland_arrives_with_the_academy_roster() -> void:
	var before := RosterTimeline.roster_before(9)
	_true(before.has("delita"), "Delita is in the roster at Gariland")
	var minted := 0
	for slug in before:
		if String(slug).begins_with("entd392_"):
			minted += 1
	_eq(minted, 6, "the Academy's six generics are in the roster at Gariland")


func _test_the_protagonist_is_present_from_the_first_battle() -> void:
	# Ramza is never RECRUITED — he is the player. His only `join_after_event` is at root
	# 116 ("Chapter 2 Start"), which is the chapter-FORM re-bind, not a recruitment;
	# reading it as one left him out of the roster for the whole of Chapter 1.
	for root in [9, 59, 116, 373]:
		_true(RosterTimeline.roster_before(root).has("ramza"),
			"root %d arrives with the protagonist" % root)
	var seeded := 0
	for r in RosterTimeline.order():
		for delta in RosterTimeline.joins_for(r):
			if bool(delta.get("protagonist", false)):
				seeded += 1
	_eq(seeded, 1, "exactly one protagonist seed across the whole timeline")


func _test_mustadio_guests_at_zaland_and_joins_at_goug() -> void:
	_true(not RosterTimeline.roster_before(139).has("mustadio"),
		"Mustadio is a GUEST at Zaland, not a party member")
	_true(RosterTimeline.roster_before(169).has("mustadio"),
		"Mustadio is a party member after the Goug join")
	# Zaland flags him, but only Goug RECRUITS him.
	_eq(RosterTimeline.recruits_for(139).size(), 0, "Zaland recruits nobody")
	var goug := RosterTimeline.recruits_for(166)
	_eq(goug.size(), 1, "Goug recruits exactly one unit")
	_eq(String(goug[0].get("slug", "")), "mustadio", "and it is Mustadio")


func _test_worker_8_is_recruited_at_the_activation_cinematic() -> void:
	# ADR-0216 dec.14. The generator's own tests read the ENTD; this arm proves the fact
	# survives the COMMITTED asset and reaches a consumer, which is the half a generator
	# test cannot see. Root 212 is "Worker 8 Activated" at Besrodio's House (position 94);
	# 210 is "Steel Ball Found!" one group earlier, where the same slot carries no flag.
	_true(not RosterTimeline.roster_before(210).has("entd291_3"),
		"nobody is granted by Steel Ball Found!")
	var activated := RosterTimeline.recruits_for(212)
	_eq(activated.size(), 1, "Worker 8 Activated recruits exactly one unit")
	# Index only when there IS a row: an out-of-bounds read would abandon the rest of
	# this arm, so a regression would report one failure instead of five.
	var w8: Dictionary = activated[0] if activated.size() == 1 else {}
	_eq(String(w8.get("slug", "")), "entd291_3",
		"and it is ENTD 291 slot 3 - the Steel Giant, unnamed because special_name 117 is "
		+ "outside unit_names.json")
	_eq(int(w8.get("special_name", -1)), 117, "special_name 117")
	_eq(String(w8.get("team_color_name", "")), "Red",
		"flagged on the RED side of a cinematic record - the filter that hid him")
	_true(RosterTimeline.roster_before(214).has("entd291_3"),
		"and he is in the roster from the next group on")


func _test_seek_state_for_the_reported_runaway() -> void:
	_true(RosterTimeline.has_enter(59), "root 59 is entered from the world map")
	_eq(RosterTimeline.enter_vars(59), {110: 10}, "seeking root 59 installs var[110]=10")
	_true(RosterTimeline.enter_is_exclusive(59), "and that isolates node 59")


func _test_chained_group_has_no_enter_state() -> void:
	_true(not RosterTimeline.has_enter(373),
		"Bethla Garrison is reached by chaining, never offered by the map")
	_eq(RosterTimeline.enter_vars(373), {}, "so it has no enter vars")


func _test_gating_vars_do_not_wipe_the_map_reveal_range() -> void:
	# 528 IS in the reveal range and IS gated on, which is exactly why the reset is this
	# list rather than a blanket zero — a whole-store wipe would un-reveal map nodes.
	var gating := RosterTimeline.gating_vars()
	_true(gating.size() > 0, "there are gating vars")
	_true(gating.has(110), "the story counter is one of them")
	var reveal_hits := 0
	for idx in gating:
		if int(idx) >= WorldMapProgress.NODE_KNOWN_BASE \
				and int(idx) < WorldMapProgress.NODE_KNOWN_BASE + WorldMapProgress.NODE_COUNT:
			reveal_hits += 1
	_eq(reveal_hits, 1, "exactly one gating var (528) lands in the node-reveal range")


func _test_installing_enter_vars_makes_the_map_offer_that_node() -> void:
	# The end-to-end claim: write the derived state into the LIVE store and ask Campaign
	# what the map offers. This is the assertion the bug would have failed.
	var store := Campaign.vars()
	if store == null:
		_failed += 1
		print("  [FAIL] Campaign has no variable store")
		return
	var saved: Array = store.to_sparse()
	for idx in RosterTimeline.gating_vars():
		store.set_var(int(idx), 0)
	var wanted := RosterTimeline.enter_vars(59)
	for idx in wanted:
		store.set_var(int(idx), int(wanted[idx]))
	_eq(Campaign.story_counter(), 10, "the live store reads story counter 10")
	var live := Campaign.live_enter_nodes()
	_eq(live.size(), 1, "exactly one node offers an enter")
	if live.size() == 1:
		_eq(Campaign.enter_at(live[0]).get("scenario_id", -1), 59,
			"and it hands off scenario 59, not 13 (Beoulve Residence)")
	store.load_sparse(saved)


func _test_every_battle_groups_opener_is_the_one_the_navigator_plans() -> void:
	# TWO implementations of one query. `build_roster_timeline._opener_scenario_id` reads
	# the BC edge whose predicate mentions var 509 in Python; `GameNavigator._battle_beats`
	# reads the same edge in GDScript, and the appearance deltas are keyed on the Python
	# answer while the walk looks them up with the GDScript one. A drift between them does
	# not fail loudly — every appearance silently stops folding — so the agreement is
	# asserted here, over EVERY battle group rather than the one Orbonne spot-check.
	var nav := GameNavigator.new()
	var battles := 0
	var mismatches: Array = []
	for root in RosterTimeline.order():
		var derived := RosterTimeline.opener_scenario_id(root)
		var planned := -1
		for beat in nav.beats_for_group(root):
			if String(beat.get("role", "")) == "opener":
				planned = int(beat.get("scenario_id", -1))
				break
		if derived >= 0:
			battles += 1
		if derived != planned:
			mismatches.append("root %d: derived %d, navigator %d" % [root, derived, planned])
	_eq(mismatches, [], "every group's derived opener is the beat the navigator plans")
	_eq(battles, 72, "72 battle groups carry an opener — the key an appearance folds under")


func _test_appearances_are_battle_scoped_and_never_owned() -> void:
	# The generator asserts no deployability (ADR-0216 dec.8), so no appearance delta may
	# carry `own` — a linear group may carry none at all, and a slug binds ONCE.
	var seen: Array = []
	var total := 0
	for root in RosterTimeline.order():
		var appearances := RosterTimeline.appearances_for(root)
		if RosterTimeline.opener_scenario_id(root) < 0:
			_eq(appearances, [], "linear root %d derives no appearance" % root)
			continue
		for delta in appearances:
			total += 1
			var slug := String(delta.get("slug", ""))
			_true(not delta.has("own"), "%s's appearance asserts no `own`" % slug)
			_true(not seen.has(slug), "%s binds once, not again at root %d" % [slug, root])
			_true(not RosterTimeline.roster_before(root).has(slug),
				"%s is not re-bound after joining the roster" % slug)
			seen.append(slug)
	_eq(total, 28, "28 first binds across the story")
