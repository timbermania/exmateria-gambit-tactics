extends Node
## TDD guard for ADR-0099 dec. 5 — the region SCOPE control.
##
## "Move and resize both act on the region, under one visible scope control", with the
## member count stated BEFORE the drag and the scope resetting whenever a different region
## is opened.
##
## THE VOCABULARY IS AMENDED (author, 2026-08-21): `effect wide / frameset wide / a manual
## subset of framesets, in thumbnail order`, keyed on the FRAMESET rather than the frame.
## dec. 5's `this frame only` and its facet filters are superseded — see the enum's
## docstring in `FramesetRegionScope.gd` for the corpus numbers behind that and why the
## facets were never a task anyone had.
##
## The selection logic lives here as PURE statics — the same test seam
## `FramesetCanvas`'s coordinate math uses — so the rule is assertable without a
## live node, a window, or a screenshot. The panel is deliberately a separate
## file from `EffectStudioPage.gd`: the page only has to build it and connect one
## signal.
##
## Run: <GODOT> --path . --quit-after 400 res://tests/EffectStudioRegionScopeTest.tscn

const Scope = preload("res://src/effects/studio/FramesetRegionScope.gd")
const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_the_default_scope_is_every_member_of_the_region()
	_test_frameset_wide_takes_only_the_frameset_on_screen()
	_test_the_subset_ticks_framesets_and_an_empty_tick_set_takes_nothing()
	_test_the_rail_lists_framesets_in_thumbnail_order_and_keeps_the_unplayed()
	_test_the_toggle_seeds_the_ticks_and_refuses_an_empty_selection()
	_test_a_one_frameset_region_refuses_the_tick_without_changing_mode()
	await _test_the_toggle_buttons_are_actually_wide_enough_to_press()
	_test_the_blast_radius_is_stated_before_the_drag()
	_test_opening_a_different_region_keeps_the_mode_and_drops_the_list()
	_test_a_rebind_on_the_same_members_changes_nothing()
	_test_a_bind_with_no_region_leaves_the_scope_alone()
	_test_the_regions_identity_is_its_members_not_its_block()
	_test_the_panel_reports_the_members_the_edit_will_touch()
	_test_the_label_names_the_gesture_and_the_framesets_it_reaches()
	_test_the_resting_state_says_how_many_regions_are_pointable()
	_test_the_rows_print_only_the_facets_the_members_disagree_on()
	_test_a_list_of_one_or_none_is_not_shown_and_costs_no_height()
	_test_the_scale_verb_asks_before_it_writes_and_keeps_the_ramp()

	print("\n=== EffectStudioRegionScopeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioRegionScopeTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioRegionScopeTest")
		get_tree().quit(0)


func _test_the_default_scope_is_every_member_of_the_region() -> void:
	# dec. 5: "all N frames (default)". The sharing is the whole point — E019 is 30
	# identical drags without it — so the safe-feeling default (this frame only) is
	# the wrong one; the count is made VISIBLE instead.
	var members := _members()
	var picked: Array = Scope.select_members(members, Scope.SCOPE_EFFECT, 0, {})
	_assert_eq(picked.size(), 4, "the default scope is the whole region")


## THE SCOPE KEYS ON THE FRAMESET, NOT THE FRAME (author, 2026-08-21: "effect wide,
## frameset wide, subset of framesets"). Censused: 91.5% of multi-member corpus regions
## span more than one frameset, median 3 (p90 11, max 71), against a median of 4 members
## (max 107). The frameset is the smaller list AND the one the author can see — the strip
## draws framesets and "frame 2 of frameset 17" is an address with no picture.
func _test_frameset_wide_takes_only_the_frameset_on_screen() -> void:
	var members := _members()
	# The fixture's four members sit in framesets 0, 1, 2, 2.
	_assert_eq(Scope.select_members(members, Scope.SCOPE_FRAMESET, 2, {}).size(), 2,
		"frameset 2 holds two of the four members, and frameset-wide takes both")
	_assert_eq(Scope.select_members(members, Scope.SCOPE_FRAMESET, 0, {}).size(), 1,
		"frameset 0 holds one")
	_assert_eq(Scope.select_members(members, Scope.SCOPE_FRAMESET, 9, {}).size(), 0,
		"a frameset with no member in this region selects nothing — never a fallback to all")

	# AND IT CANNOT HALF-SELECT A FRAMESET. Frameset 2's two members share the region, so
	# a frame-keyed scope could take one and leave the other — with nothing on screen
	# saying which, because both draw inside the same sprite.
	var picked: Array = Scope.select_members(members, Scope.SCOPE_FRAMESET, 2, {})
	for m in picked:
		_assert_eq(int(m["frameset_index"]), 2, "every picked member is in the named frameset")


func _test_the_subset_ticks_framesets_and_an_empty_tick_set_takes_nothing() -> void:
	var members := _members()
	_assert_eq(Scope.select_members(members, Scope.SCOPE_SUBSET, 2, {0: true}).size(), 1,
		"one ticked frameset takes its member")
	_assert_eq(Scope.select_members(members, Scope.SCOPE_SUBSET, 2, {0: true, 2: true}).size(), 3,
		"two ticked framesets take all three of their members")
	# A selection that silently means "all" is how an author moves thirty frames intending
	# to move two. The live control cannot reach this state; the static must still be honest.
	_assert_eq(Scope.select_members(members, Scope.SCOPE_SUBSET, 2, {}).size(), 0,
		"no ticks selects nothing rather than falling back to the whole region")


## THE RAIL'S ROW, AND ITS ORDER. `order_framesets` puts the framesets the sequence on
## screen actually reaches first, in the order it reaches them, and KEEPS the rest.
func _test_the_rail_lists_framesets_in_thumbnail_order_and_keeps_the_unplayed() -> void:
	var members := _members()
	_assert_eq(str(Scope.distinct_framesets(members)), str([0, 1, 2]),
		"the rail's row is the distinct framesets, ascending")

	# A strip that plays 2 then 0 (and 2 again, and a frameset this region never touches).
	_assert_eq(str(Scope.order_framesets([0, 1, 2], [2, 0, 2, 7])), str([2, 0, 1]),
		"played framesets come first in strip order; 1 is never played and follows")
	# REPEATS RESOLVE TO THE FIRST OCCURRENCE, so a looping sequence does not reorder the
	# rail every time it comes round.
	_assert_eq(str(Scope.order_framesets([0, 2], [2, 0, 2])), str([2, 0]),
		"a frameset's rank is where it FIRST appears")
	# THE E317 SHAPE, which is the case the author hit: a region spanning six framesets
	# where the sequence on screen plays exactly one of them.
	_assert_eq(str(Scope.order_framesets([15, 17, 18, 19, 20, 21], [15, 16, 22])),
		str([15, 17, 18, 19, 20, 21]),
		"the five the strip cannot show are kept, in index order, after the one it can")
	_assert_eq(str(Scope.order_framesets([0, 1, 2], [])), str([0, 1, 2]),
		"no strip at all leaves the row in index order")


## THE BLAST RADIUS IS STATED BEFORE THE DRAG (dec. 5) — and a narrowed scope says SPLIT.
func _test_the_blast_radius_is_stated_before_the_drag() -> void:
	var members := _members()
	var all: Array = Scope.select_members(members, Scope.SCOPE_EFFECT, 0, {})
	_assert_true(Scope.scope_label(members, all).contains("4"),
		"the label names how many frames the edit will move: %s" % Scope.scope_label(members, all))

	# `region_edits` writes each member's OWN uv bytes and a region is recomputed from those
	# bytes on every read, so leaving members out does not make a smaller edit — it gives
	# the moved frames a new rect and leaves the rest behind as their own region. "1 of 4
	# frames will move" is true and hides that the group stops being one group.
	var one: Array = Scope.select_members(members, Scope.SCOPE_FRAMESET, 0, {})
	var label: String = Scope.scope_label(members, one, 0)
	_assert_true(label.contains("SPLIT"),
		"narrowing announces the SPLIT, not a smaller edit: %s" % label)
	_assert_true(label.contains("1") and label.contains("3"),
		"…naming what moves and what stays behind: %s" % label)
	_assert_true(not Scope.scope_label(members, all, 0).contains("SPLIT"),
		"the unnarrowed case is not a split — nothing is left behind")


## dec. 5: "It resets to all whenever a different region is opened." A sticky narrow scope
## carried into an unrelated region is how an author edits one frame believing they edited
## thirty — and on the texture tab a rebind is a MOUSE-MOVE away, not a navigation away.
## ADR-0099 dec. 5e — THE MODE PERSISTS, A HAND-BUILT SUBSET DOES NOT.
##
## dec. 5's original letter reset the scope to `all` on every `bind`, and `bind` has four
## callers of which only one is "a different region was opened". Reported by the author:
## *"whenever you change the selection scope … if you then change the thumbnail, it flips
## back to effect. the scope should persist."*
##
## This test used to assert the reset, and it never tested what its name claimed: the
## "DIFFERENT region on the same sheet" it re-bound to was frameset 0 frame 1, whose uv is
## `(8,40,32,32)` — the SAME block frameset 2 frame 1 stores mirrored. It passed because
## `bind` reset unconditionally, so no bind could tell them apart. The genuinely different
## region on this sheet is frameset 0 frame **0**, the lone 8x8.
func _test_opening_a_different_region_keeps_the_mode_and_drops_the_list() -> void:
	var panel = Scope.new()
	add_child(panel)
	panel.bind(_framesets(), 2, 1)
	panel.set_scope(Scope.SCOPE_FRAMESET)
	_assert_eq(panel.scope(), Scope.SCOPE_FRAMESET, "the author narrowed the scope")

	panel.bind(_framesets(), 0, 0)   # the lone 8x8 — a genuinely different region
	_assert_eq(panel.scope(), Scope.SCOPE_FRAMESET,
		"a RULE survives the region change: the author asked for frameset-wide and still has it")
	_assert_eq(panel.selected_members().size(), 1,
		"…re-evaluated against the new region's own members, not the old ones")

	# A LIST cannot be carried. Its ticks name the old region's framesets, so in the new one
	# they either select nothing (dec. 5c refuses that outright) or happen to select
	# everything — a subset that silently means `all`, which is what dec. 5 exists to stop.
	panel.bind(_framesets(), 2, 1)
	panel.set_scope(Scope.SCOPE_SUBSET)
	panel.toggle_frameset(0)          # un-tick one, so the subset is a real choice
	_assert_eq(panel.scope(), Scope.SCOPE_SUBSET, "the author built a subset")
	_assert_eq(panel.selected_members().size(), 3, "of 3 of the 4 members")

	panel.bind(_framesets(), 0, 0)
	_assert_eq(panel.scope(), Scope.SCOPE_FRAMESET,
		"a subset degrades to frameset-wide — narrow, expressible, and on the radio")
	_assert_eq(panel.selected_members().size(), 1, "and selects the new region's members")
	panel.free()


## THE COMMONEST BIND IS NOT A REGION CHANGE AT ALL. Three of `bind`'s four callers re-bind
## without changing the region — the panel refreshing, a pin landing on the box already
## hovered, and (the one that matters most) the author's own drag committing at
## `EffectStudioPage:2778`. A scope that could not survive those is a scope that cannot be
## used for two drags in a row.
func _test_a_rebind_on_the_same_members_changes_nothing() -> void:
	var panel = Scope.new()
	add_child(panel)
	panel.bind(_framesets(), 2, 1)
	panel.set_scope(Scope.SCOPE_SUBSET)
	panel.toggle_frameset(0)
	var picked: int = panel.selected_members().size()

	# The same region reached from a DIFFERENT member — frameset 0's frame 1 stores the
	# identical block upright where frameset 2's frame 1 stores it mirrored.
	panel.bind(_framesets(), 0, 1)
	_assert_eq(panel.scope(), Scope.SCOPE_SUBSET,
		"the same members re-bound from another frame is the same region, and keeps the subset")
	_assert_eq(panel.selected_members().size(), picked, "…ticks and all")
	panel.free()


## THE RESTING BIND IS THE ABSENCE OF A SUBJECT, not a region change. `TextureTabPanel:673`
## binds `frame_index = -1` on any multi-region frameset, and `_on_group_region_hovered`
## does the same the moment the pointer leaves every box — both on a mouse-move path. A
## reset here would put dec. 5's old behaviour back on exactly the path ADR-0130 dec. 12f
## had to pin a region to escape.
func _test_a_bind_with_no_region_leaves_the_scope_alone() -> void:
	var panel = Scope.new()
	add_child(panel)
	panel.bind(_framesets(), 2, 1)
	panel.set_scope(Scope.SCOPE_SUBSET)
	panel.toggle_frameset(0)

	panel.bind(_framesets(), 2, -1, 3)   # the pointer is between boxes
	_assert_eq(panel.members().size(), 0, "no region resolves, so the panel is about nothing")
	_assert_eq(panel.scope(), Scope.SCOPE_SUBSET, "and the scope is untouched by that")

	panel.bind(_framesets(), 2, 1)       # back into the same box
	_assert_eq(panel.scope(), Scope.SCOPE_SUBSET, "so re-entering it finds the subset intact")
	_assert_eq(panel.selected_members().size(), 3, "with the same three members ticked")
	panel.free()


## A REGION'S IDENTITY IS ITS MEMBERSHIP, NOT ITS BLOCK — and that choice is load-bearing
## rather than stylistic. The region's `Rect2i` moves on every commit, so identity read off
## the block would say "different region" on the one bind whose whole meaning is *the
## author's edit landed*.
func _test_the_regions_identity_is_its_members_not_its_block() -> void:
	var before: Array = Canvas.region_members(_framesets(), Rect2i(8, 40, 32, 32))
	# The same region after a move: every member's uv shifted, the block is somewhere else,
	# the frames are the same frames.
	var moved: Array = _framesets()
	for m in before:
		var uv: Dictionary = moved[int(m["frameset_index"])]["frames"][int(m["frame_index"])]["uv"]
		uv["x"] = int(uv["x"]) + 16
		uv["y"] = int(uv["y"]) + 16
	var after: Array = Canvas.region_members(moved, Rect2i(24, 56, 32, 32))

	_assert_eq(Scope.member_key(before), Scope.member_key(after),
		"a region that MOVED is the same region — same frames, different block")
	_assert_true(Scope.member_key(before) != Scope.member_key(
			Canvas.region_members(_framesets(), Rect2i(0, 0, 8, 8))),
		"and a different set of frames is a different region")
	_assert_eq(Scope.member_key([]), [],
		"no members is no key, which is how `bind` tells 'nothing here' from 'somewhere else'")


## THE TOGGLE IS A BULK-SET OF THE RAIL, not a separate state that starts empty.
##
## Pressing `Pick` seeds the ticks from whatever was showing, so the author un-ticks from a
## full selection rather than building one from nothing — dec. 5's "the count is made
## visible instead of the default made timid", applied to the one mode whose whole job is
## partial selection. And the last tick cannot be removed: an empty selection is a drag
## that moves nothing, and a gesture that silently does nothing is worse than a refused
## click.
func _test_the_toggle_seeds_the_ticks_and_refuses_an_empty_selection() -> void:
	var panel = Scope.new()
	add_child(panel)
	panel.bind(_framesets(), 2, 1)          # 4 members over framesets 0, 1, 2

	panel.set_scope(Scope.SCOPE_SUBSET)
	_assert_eq(panel.selected_members().size(), 4,
		"Pick seeds from Effect — everything ticked, nothing silently dropped")

	panel.set_scope(Scope.SCOPE_EFFECT)
	panel.set_scope(Scope.SCOPE_FRAMESET)
	panel.set_scope(Scope.SCOPE_SUBSET)
	_assert_eq(panel.selected_members().size(), 2,
		"…and from Frameset it seeds the frameset's two members, not all four")

	panel.toggle_frameset(0)
	_assert_eq(panel.selected_members().size(), 3, "ticking another frameset adds its member")
	panel.toggle_frameset(0)
	_assert_eq(panel.selected_members().size(), 2, "and un-ticking removes it again")

	# A rail tick from ANY mode switches to Pick — the tile is the chooser, so touching one
	# never needs a mode press first.
	panel.set_scope(Scope.SCOPE_EFFECT)
	panel.toggle_frameset(1)
	_assert_eq(panel.scope(), Scope.SCOPE_SUBSET, "a tile tick IS choosing to pick")

	# Strip it down to one and refuse to go further.
	panel.set_scope(Scope.SCOPE_EFFECT)
	panel.set_scope(Scope.SCOPE_SUBSET)
	for f in panel.region_framesets():
		panel.toggle_frameset(f)
	_assert_true(panel.selected_members().size() >= 1,
		"the last frameset cannot be un-ticked (%d left)" % panel.selected_members().size())
	panel.free()


## A ONE-FRAMESET REGION REFUSES THE WHOLE GESTURE, MODE SWITCH INCLUDED (2026-08-21).
##
## The two rules above used to collide. "A tile tick IS choosing to pick" switched the mode
## first; "the last frameset cannot be un-ticked" then refused the tick. On a region living
## in ONE frameset those are the same click, so its entire effect was to move the scope
## control into `Pick` — a mode with nothing in it to pick — and change nothing else.
##
## It was unreachable while the rail collapsed a row of one to nothing. The rail shows a tile
## for every region now, and 3636 of 6632 corpus regions (54.8%) live in one frameset, so the
## sole tile is clickable on more than half of them.
func _test_a_one_frameset_region_refuses_the_tick_without_changing_mode() -> void:
	var panel = Scope.new()
	add_child(panel)
	# The fixture's frameset 0 frame 0 — the `(0,0,8,8)` rect labelled "other region" — is
	# the single-frameset case: no other frame in the fixture normalises to that block.
	panel.bind(_framesets(), 0, 0)
	_assert_eq(panel.region_framesets().size(), 1,
		"the fixture really does give a ONE-frameset region here (%s) — a skip would make "
		% str(panel.region_framesets()) + "this whole guard unable to fail")
	var before: int = panel.scope()
	var picked: int = panel.selected_members().size()
	panel.toggle_frameset(int(panel.region_framesets()[0]))
	_assert_eq(panel.scope(), before,
		"the sole tile does not drag the mode into Pick behind a refused tick")
	_assert_eq(panel.selected_members().size(), picked,
		"…and takes nothing out of the selection either")
	panel.free()


func _test_the_panel_reports_the_members_the_edit_will_touch() -> void:
	# The panel's whole contract to the page: hand back the member list that
	# `FramesetCanvas.region_edits` lowers into one compound edit (dec. 9).
	var panel = Scope.new()
	var framesets := _framesets()
	panel.bind(framesets, 2, 1)
	var picked: Array = panel.selected_members()
	var edits: Array = Canvas.region_edits(framesets, picked, Rect2i(16, 48, 32, 32))
	_assert_eq(picked.size(), 4, "the default scope hands back the whole region")
	_assert_eq(edits.size(), 8, "four members x the two fields a move changes")
	# And the region it resolved is the one the opened frame belongs to.
	_assert_eq(panel.region(), Rect2i(8, 40, 32, 32), "the panel names the region it is scoped to")
	panel.free()


## THE LABEL IS A CONSEQUENCE, NOT A ROSTER — and it names the split.
##
## The author, reading the shipped control: *"in the texture collapsible section why does
## it list frames? what's the thinking"*, and earlier, mid-edit, *"I thought the change was
## effect wide?"*. Both are the same gap: 81.4% of corpus regions have members in more than
## one frameset, so the list is normally naming frames the view cannot show, and the label
## said only "6 frames in this region" — a count with no gesture attached and no hint that
## most of it is off screen.
func _test_the_label_names_the_gesture_and_the_framesets_it_reaches() -> void:
	var members := _members()
	var all: Array = Scope.select_members(members, Scope.SCOPE_EFFECT, 0, {})

	# The fixture's four members sit in framesets 0, 1, 2, 2. Opened from frameset 2, one
	# of them is on screen and three are not, and the label has to say so.
	var split: String = Scope.scope_label(members, all, 2)
	_assert_true(split.contains("4") and split.contains("2 in this frameset"),
		"the label splits the region by what the view can show: %s" % split)
	_assert_true(split.contains("2 in framesets not shown"),
		"…and names the half that is invisible, which is the whole reason the list exists: %s"
			% split)
	_assert_true(split.contains("⚠"),
		"a multi-frame edit is warned about, not merely counted: %s" % split)

	# NO SPLIT WITHOUT A FRAMESET TO SPLIT ON. `-1` is the honest input from a host with no
	# frameset on screen; the label omits the clause rather than guessing at it.
	_assert_true(not Scope.scope_label(members, all, -1).contains("not shown"),
		"with no frameset in context the split is omitted, not invented")

	# ONE MEMBER IS NOT A BLAST RADIUS. dec. 5 wants the count stated; "this frame only"
	# states it, and the row that would repeat it is dropped (see the list test below).
	var lone := [members[0]]
	_assert_true(Scope.scope_label(lone, lone, 0).contains("this frame only"),
		"a singleton region says so in words: %s" % Scope.scope_label(lone, lone, 0))
	_assert_true(not Scope.scope_label(lone, lone, 0).contains("⚠"),
		"…and carries no warning, because nothing else moves")


## THE RESTING STATE IS A STATE, NOT AN ERROR (ADR-0130 dec. 12).
##
## With N live boxes on the sheet and the pointer on none of them there is no region to
## resolve, and the control printed "No region" — which is what a broken control says, next
## to five boxes that were all draggable. It now says what is true and what to do about it.
func _test_the_resting_state_says_how_many_regions_are_pointable() -> void:
	var none: Array = []
	var resting: String = Scope.scope_label(none, none, 59, 5)
	_assert_true(resting.contains("5 regions"),
		"the resting label counts the boxes on the sheet: %s" % resting)
	_assert_true(resting.contains("point at"),
		"…and says what the author has to do to resolve one: %s" % resting)
	_assert_true(not resting.contains("No region"),
		"it never claims there is nothing here while boxes are live")
	_assert_eq(Scope.scope_label(none, none, 59, 0), "No region",
		"and with no live boxes either, 'No region' is the truth again")


## THE ROWS PRINT DIFFERENCES, because that is the stated reason the facets are on them at
## all. A facet every member shares is the same word repeated down a 248px column, and it
## is what pushed the informative tail off the end of the row ("· p…").
func _test_the_rows_print_only_the_facets_the_members_disagree_on() -> void:
	var members := _members()
	var varying: Dictionary = Scope.varying_facets(members)
	_assert_true(varying.has("mirrored"),
		"the fixture's members disagree about mirroring, so the rows say which are")
	_assert_true(varying.has("palette_id"),
		"…and about palette")

	# A region whose members agree on everything: two upright frames, same palette, same
	# drawn size. There is nothing to consent to beyond the count, so the row is the address.
	var uniform := Canvas.region_members(_uniform_framesets(), Rect2i(8, 40, 32, 32))
	_assert_eq(uniform.size(), 2, "the uniform fixture shares one block")
	_assert_eq(Scope.varying_facets(uniform).size(), 0,
		"members that agree on every facet vary on none")
	var row: String = Scope.member_label(uniform[0], Scope.varying_facets(uniform))
	_assert_eq(row, "frameset 0 / frame 1",
		"so the row is the address alone (was '%s')" % row)
	# And the whole truth is still available to a caller with room for it.
	_assert_true(Scope.member_label(uniform[0], null).contains("pal 0"),
		"passing null prints every facet, for a host that is not 248px wide")

	# A region of ONE varies on nothing by construction — there is no neighbour to differ
	# from, and a comparison against itself would print every facet as a difference.
	_assert_eq(Scope.varying_facets([members[0]]).size(), 0,
		"a single member disagrees with nobody")


## THE LIST EARNS ITS HEIGHT OR IT IS NOT THERE.
##
## Measured before this: E066 frameset 59 on a `frame` target listed ONE row and reserved
## 124px for it — ~200px of empty rectangle inside the overlay that exists to answer "a
## bunch of dead space". The host states a CEILING now and the list asks for its rows.
func _test_a_list_of_one_or_none_is_not_shown_and_costs_no_height() -> void:
	var panel = Scope.new()
	panel.list_max_height = 124.0
	add_child(panel)

	panel.bind(_framesets(), 2, 1)          # the 4-member region
	var many: Control = panel._member_list
	_assert_true(many.visible, "a region worth enumerating shows its members")
	_assert_true(many.custom_minimum_size.y > 0.0,
		"and asks for height for them (%.0f)" % many.custom_minimum_size.y)
	_assert_true(many.custom_minimum_size.y <= 124.0,
		"never above the host's ceiling (%.0f)" % many.custom_minimum_size.y)

	panel.bind(_uniform_framesets(), 0, 0)  # frame 0 is the OTHER region — one member
	_assert_eq(panel.members().size(), 1, "a singleton region")
	_assert_true(not many.visible,
		"a list of one repeats the line above it, so it is not drawn")
	_assert_eq(many.custom_minimum_size.y, 0.0,
		"and reserves nothing (%.0f)" % many.custom_minimum_size.y)

	panel.bind(_framesets(), 0, -1)         # the resting state: no region at all
	_assert_eq(panel.members().size(), 0, "no region resolved")
	_assert_true(not many.visible, "an empty list is a labelled void; it is not drawn")

	# THE ROWS ARE NOT A PICKER. Selecting happens on the rail's frameset tiles and on the
	# toggle row; these rows are the enumeration behind that choice. A row highlight that
	# answers with nothing is a worse lie than no affordance at all.
	panel.bind(_framesets(), 2, 1)
	_assert_true(not many.is_item_selectable(0),
		"the rows do not offer a selection the control cannot consume")

	panel.queue_free()


## A CONTROL THAT IS ZERO PIXELS WIDE PASSES EVERY PREDICATE ABOUT ITS EXISTENCE.
##
## The toggle row shipped invisible and this suite was green. `clip_text` drops a Button's
## minimum width to ~zero — which is deliberate, it is what stops "Frameset 12" from
## setting the 248px overlay's width — and an `HBoxContainer` hands a child with no expand
## flag exactly its minimum. All three collapsed to nothing and the row drew as a bare
## label. Caught by screenshot, which is the fourth time on this surface
## ([[render-atlas-crops-and-look-at-them]]).
##
## So the assertion is the RECT, not the node: laid out at the width the overlay actually
## gives, each button must be wide enough to read a count on and to aim at.
func _test_the_toggle_buttons_are_actually_wide_enough_to_press() -> void:
	var host := Control.new()
	# The real number: `TextureTabPanel.OVERLAY_W` (248) less the panel stylebox's 6px
	# content margins. Asserting at some generous test width would pass while the shipping
	# one failed, which is exactly how this defect got out.
	host.size = Vector2(236.0, 400.0)
	add_child(host)
	var panel = Scope.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(panel)
	panel.size = Vector2(236.0, 400.0)
	panel.bind(_framesets(), 2, 1)
	await get_tree().process_frame
	await get_tree().process_frame

	var buttons: Array = []
	for child in panel.get_children():
		if child is HBoxContainer:
			for b in child.get_children():
				if b is Button and b.toggle_mode:
					buttons.append(b)
	_assert_eq(buttons.size(), 3, "three modes: Effect, Frameset, Pick")
	for b in buttons:
		_assert_true(b.size.x >= 40.0,
			"'%s' is wide enough to press and to read (%.0fpx)" % [b.text, b.size.x])
		_assert_true(b.text.strip_edges() != "", "…and says which mode it is")
	# AND THE ROW STILL DOES NOT BID INTO THE OVERLAY'S WIDTH, which is what `clip_text` was
	# for. If this reddens, the fix above traded one defect for the one it replaced.
	_assert_true(panel.get_combined_minimum_size().x <= 236.0,
		"the row's minimum stays inside the overlay (%.0f)" % panel.get_combined_minimum_size().x)
	host.queue_free()


## Two frames sharing one 32x32 block and agreeing on every facet — the case where the
## per-row facets are pure noise. Frame 0 is a second, single-member region so the
## singleton path has a fixture too.
func _uniform_framesets() -> Array:
	return [
		{"frames": [
			{"uv": {"x": 0, "y": 0, "width": 8, "height": 8}, "palette_id": 0,
				"vertices": _quad(0)},
			{"uv": {"x": 8, "y": 40, "width": 32, "height": 32}, "palette_id": 0,
				"vertices": _quad(0)},
		]},
		{"frames": [
			{"uv": {"x": 8, "y": 40, "width": 32, "height": 32}, "palette_id": 0,
				"vertices": _quad(0)},
		]},
	]


## Four frames sharing one 32x32 block, deliberately disagreeing on every facet:
## two upright / two mirrored, one of them rotated, spread over three framesets and
## two palettes. E005 stores exactly this shape (one block, upright in frameset 17
## and mirrored in frameset 26).
func _framesets() -> Array:
	return [
		{"frames": [
			{"uv": {"x": 0, "y": 0, "width": 8, "height": 8}, "palette_id": 0},          # other region
			{"uv": {"x": 8, "y": 40, "width": 32, "height": 32}, "palette_id": 0,
				"vertices": _quad(0)},
		]},
		{"frames": [
			{"uv": {"x": 39, "y": 40, "width": -32, "height": 32}, "palette_id": 5,
				"vertices": _quad(0)},
		]},
		{"frames": [
			{"uv": {"x": 8, "y": 40, "width": 32, "height": 32}, "palette_id": 0,
				"vertices": _quad(1)},
			{"uv": {"x": 39, "y": 40, "width": -32, "height": 32}, "palette_id": 0,
				"vertices": _quad(0)},
		]},
	]


func _members() -> Array:
	return Canvas.region_members(_framesets(), Rect2i(8, 40, 32, 32))


## `kind` 0 = an ordinary upright quad; 1 = one rotated off the axes.
func _quad(kind: int) -> Dictionary:
	if kind == 1:
		return {"top_left": [-10, -10], "top_right": [10, -6],
			"bottom_left": [-14, 10], "bottom_right": [6, 14]}
	return {"top_left": [-10, -10], "top_right": [10, -10],
		"bottom_left": [-10, 10], "bottom_right": [10, 10]}



## THE REGION SCALE (ADR-0099 dec. 3 amendment) — the verb the author asked for: *"all
## frames at this UV get a scaled adjustment"*.
##
## It sits on THIS control rather than on the frame screen's Width/Height rows, and that is
## dec. 5 rather than taste: the blast radius must be stated BEFORE the gesture, and a row
## that looks per-frame silently moving 30 frames is the exact failure this control exists
## to prevent. Asserted here: the verb emits the factor with the members the count was read
## off, it commits on the BUTTON and not on a keystroke, and it never fans a no-op.
func _test_the_scale_verb_asks_before_it_writes_and_keeps_the_ramp() -> void:
	var scope = Scope.new()
	add_child(scope)          # `_build` runs on _ready, and the verb is a real widget
	scope.bind(_framesets(), 0, 1)
	var seen: Array = []
	scope.scale_requested.connect(func(f, m): seen.append({"factor": f, "members": m}))

	# A factor typed but not applied fans NOTHING. "1.25" passes through "1.2" a digit at a
	# time, and a live-fanning factor would make that a 30-frame edit nobody asked for.
	scope._scale_field.set_value_no_signal(1.5)
	_assert_eq(seen.size(), 0, "typing a factor fans no edit — the button is the commit")

	scope._scale_apply.emit_signal("pressed")
	_assert_eq(seen.size(), 1, "pressing Apply asks once")
	if seen.size() == 1:
		_assert_true(is_equal_approx(float(seen[0]["factor"]), 1.5), "…carrying the factor")
		_assert_eq(int(seen[0]["members"].size()), scope.selected_members().size(),
			"…and the SAME members the count was read off, not a re-derived list")
	_assert_true(is_equal_approx(float(scope._scale_field.value), 1.0),
		"and the factor resets to 1.00, so a second Apply is not an accidental compounding")

	# 1.00x is the resting value, so it must never be a gesture.
	scope._scale_apply.emit_signal("pressed")
	_assert_eq(seen.size(), 1, "applying 1.00x fans nothing — it is the identity, not an edit")

	remove_child(scope)
	scope.queue_free()

func _assert_eq(actual, expected, label: String) -> void:
	if str(actual) == str(expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
