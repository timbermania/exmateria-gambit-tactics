extends Node
## TDD guard for ADR-0130 — THE TEXTURE HAS TWO SURFACES: A PAGE AND A TAB.
##
## The complaint: "there are random links to the texture everywhere. But nowhere can you
## actually view the texture." The audit found FOUR surfaces and none of them drawing the
## sheet, because the only renderer was gated to the `frame` target kind alone.
##
## THE LOAD-BEARING ASSERTION IS THE LAYOUT ONE (dec. 3). The author's stated requirement
## for choosing a tab over the band they first proposed was "then it wouldn't push the
## player stuff down". That is a claim about the RIGHT column's rect being invariant under
## a left-column tab switch, and it is the thing most likely to break silently: Godot skips
## invisible children in container minimums, so any width or height read live off the
## showing tab would swing on every switch and resize the player.
##
## Run: godot --path . --quit-after 900 res://tests/EffectStudioTextureTabTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const FramesetProjector = preload("res://src/effects/studio/FramesetProjector.gd")
const TextureTab = preload("res://src/effects/studio/TextureTabPanel.gd")
const Canvas_ = preload("res://src/effects/studio/FramesetCanvas.gd")
const RegionScope = preload("res://src/effects/studio/FramesetRegionScope.gd")

var _passed: int = 0
var _failed: int = 0
var _completed: Dictionary = {}
const _EXPECTED_TESTS := [
	"pure_coverage_scope", "surfaces_died", "link_survives",
	"tab_switch_moves_nothing", "declared_width_holds", "content_height_survives_hiding",
	"gate_admits_texture", "binds_frame_in_context", "scope_rides_the_handles",
	"scope_survives_a_thumbnail", "rail_always_shows",
	"picture_on_screen", "overlay_costs_the_row_nothing", "actions_are_reachable",
	"the_overlay_folds", "opens_at_a_useful_size", "frame_screen_plays",
]


func _done(name: String) -> void:
	_completed[name] = true


func _ready() -> void:
	await _run()
	for name in _EXPECTED_TESTS:
		if not _completed.has(name):
			_failed += 1
			print("  FAIL: test '%s' never reached its end — it aborted mid-run" % name)
	print("\n=== EffectStudioTextureTabTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioTextureTabTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioTextureTabTest")
		get_tree().quit(0)


func _run() -> void:
	# The pure half runs with no window and no assets at all.
	_test_coverage_scope_is_the_frameset_in_context()

	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — the live half is skipped")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	_assert_true(page != null, "the studio page exists")
	if page == null:
		return
	DebugOverlay.show_overlay()
	await _frames(30)
	await _settle(page._body, "the dashboard body")

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	if dir == "":
		print("[SKIP] E019 not in the catalogue")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return
	page._load_effect(dir)
	await _frames(40)
	await _settle(page._body, "the dashboard body after loading E019")
	if page._effect_data == null or page._effect_data.texture == null:
		print("[SKIP] E019 has no texture")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return

	_test_the_duplicate_round_trip_surfaces_are_gone(page)
	_test_the_link_that_mints_the_page_survives(page)
	await _test_a_tab_switch_moves_nothing_in_the_right_column(page)
	await _test_the_declared_width_does_not_swing(page)
	await _test_content_height_survives_the_inspector_being_hidden(page)
	await _test_the_gate_admits_the_texture_kind(page)
	await _test_the_tab_binds_the_frame_in_context(page)
	await _test_the_scope_control_rides_the_handles(page)
	await _test_the_scope_survives_a_thumbnail_change(page)
	await _test_the_rail_shows_for_every_region(page)
	await _test_the_picture_is_actually_on_screen(page)
	await _test_the_overlay_costs_the_row_nothing(page)
	await _test_the_actions_are_reachable_on_a_short_port(page)
	await _test_the_overlay_folds_to_the_caption(page)
	await _test_the_sheet_opens_at_a_useful_size(page)
	await _test_a_frame_screen_plays_instead_of_drawing_the_sheet_twice(page)


## dec. 4a, PURE. A frameset in context narrows the coverage mask to that frameset alone,
## so the lit texels are the regions the sprite on screen draws from. Nothing in context
## falls back to the whole effect. Assertable with no window and no decode.
func _test_coverage_scope_is_the_frameset_in_context() -> void:
	var fake := _FakeData.new()
	fake.framesets = [{"frames": [{"uv": {"x": 0, "y": 0, "width": 8, "height": 8}}]},
		{"frames": [{"uv": {"x": 8, "y": 0, "width": 8, "height": 8}}]},
		{"frames": []}]

	var whole: Array = TextureTab._coverage_framesets(fake, -1)
	_assert_eq(whole.size(), 3, "no frameset in context — the mask is the WHOLE effect")

	var one: Array = TextureTab._coverage_framesets(fake, 1)
	_assert_eq(one.size(), 1, "a frameset in context narrows the mask to one")
	_assert_true(one[0] == fake.framesets[1], "…and it is THAT frameset, not the first")

	# Out of range must not narrow to nothing — an unbindable index is not an empty sheet.
	var oob: Array = TextureTab._coverage_framesets(fake, 99)
	_assert_eq(oob.size(), 3, "an out-of-range frameset falls back to the whole effect")
	_done("pure_coverage_scope")


## dec. 6. `_sheet_actions` rendered on TWO target kinds, not the one the audit counted.
## Both are gone; the Texture tab carries the pair on every screen instead.
func _test_the_duplicate_round_trip_surfaces_are_gone(page) -> void:
	for target in [Target.frameset(0), Target.frame(0, 0)]:
		var names: Array = _field_names(target, page._effect_data)
		_assert_true(not ("Export" in names),
			"%s no longer offers a duplicate Export" % Target.kind(target))
		_assert_true(not ("Import" in names),
			"%s no longer offers a duplicate Import" % Target.kind(target))
	_done("surfaces_died")


## dec. 7. The link is NOT a place to work — it is the only thing that MINTS the `texture`
## target. Registering a kind does not make it reachable, so deleting this would strand
## the page, and the whole ADR is about the page being reachable AND useful.
func _test_the_link_that_mints_the_page_survives(page) -> void:
	for target in [Target.frameset(0), Target.frame(0, 0)]:
		var names: Array = _field_names(target, page._effect_data)
		_assert_true("Sheet" in names,
			"%s still links to the texture page" % Target.kind(target))
	_done("link_survives")


## dec. 3, AND THE REASON THE TAB BEAT THE BAND. "then it wouldn't push the player stuff
## down": the right column's rect must be byte-identical across a left-column tab switch.
func _test_a_tab_switch_moves_nothing_in_the_right_column(page) -> void:
	page._set_root(Target.frame(0, 0))
	await _frames(20)
	# STOP THE PLAYER FIRST. The column's width tracks the focus block's declared content
	# width (ADR-0100's leftover term), and the block re-renders as the animation advances
	# to an opcode whose rows differ — so a RUNNING player makes the column breathe by a
	# few px, independently of anything a tab switch does. Measuring through that tested
	# the animation, not the invariant, and flaked about one run in eight. The breathing
	# is real and worth knowing about; it is simply not what this assertion is about.
	if page._sequence_canvas != null:
		page._sequence_canvas.set_playing(false)
	await _frames(20)
	var before_panel: Rect2 = _column_rect(page)
	var before_bar: float = page._frames_bar.position.y

	page._set_active_tab("texture")
	await _frames(20)
	var during_panel: Rect2 = _column_rect(page)
	var during_bar: float = page._frames_bar.position.y

	page._set_active_tab("values")
	await _frames(20)
	var after_panel: Rect2 = _column_rect(page)

	# A TOLERANCE, not exact Rect2 equality. The invariant is "the column does not move or
	# resize", and 1px still catches every failure this guards against — the tab strip's
	# 31px shift, a squeeze from a live-read content width. Exact equality also asserts
	# that nothing in a LIVE, PLAYING column settles by a sub-pixel between two reads,
	# which is not the claim and which flaked roughly one run in eight once a colour
	# surface moved into that column beside the player.
	_assert_rect(during_panel, before_panel,
		"the right column does not move or resize when the Texture tab opens")
	_assert_rect(after_panel, before_panel,
		"…nor when it closes again")
	_assert_true(absf(during_bar - before_bar) <= 1.0,
		"the frames bar (and every lane below it) does not move either (%.1f vs %.1f)"
			% [during_bar, before_bar])
	_done("tab_switch_moves_nothing")


## dec. 3's mechanism. The column is claimed from `_inspector.content_width()`, and that
## number must not depend on which tab is showing. This is the assertion that would catch
## someone "simplifying" it to a live `get_combined_minimum_size().x`.
func _test_the_declared_width_does_not_swing(page) -> void:
	page._set_root(Target.frame(0, 0))
	await _frames(20)
	var w_values: float = page._inspector.content_width()
	page._set_active_tab("texture")
	await _frames(20)
	var w_texture: float = page._inspector.content_width()
	page._set_active_tab("values")
	await _frames(20)
	_assert_eq(w_texture, w_values,
		"declared content width is the same whichever tab shows (%.0f)" % w_values)

	# WHAT IS ACTUALLY AT STAKE, and why the live assertion above cannot show it.
	#
	# `column_width`'s leftover clamp is `row_w - content_w - gutter`, and at the bodies
	# this harness gets (measured 1187 and 1241) that leftover is ~650px against a column
	# that only ever wants 276 — so the clamp DOES NOT BIND, and swapping the declared
	# width for the live one changes nothing on screen. Reverting the discipline here and
	# re-running this test is green, which is exactly the trap
	# [[ab-revert-of-a-shared-helper-proves-nothing]] warns about: a guard that passes on
	# pre-fix code proves nothing at all.
	#
	# So the stake is asserted where it is expressible — on the pure function, at a row
	# narrow enough for the clamp to bind, using the two REAL measured inputs. The window
	# is compositor-chosen and this family has measured bodies from 153px up; a narrow one
	# is not hypothetical.
	var live_min: float = page._texture_panel.get_combined_minimum_size().x
	print("[MEASURE] body_w=%.0f  declared=%.0f  texture_panel_live_min=%.0f  column_w=%.0f" % [
		page._body.size.x, w_values, live_min, _column_rect(page).size.x])
	_assert_true(absf(live_min - w_values) > 1.0,
		"the two candidate widths genuinely differ (declared %.0f vs live %.0f) — otherwise this proves nothing"
			% [w_values, live_min])
	const NARROW_ROW := 700.0
	var from_declared: float = page.column_width(NARROW_ROW, page._CANVAS_SIDE, w_values)
	var from_live: float = page.column_width(NARROW_ROW, page._CANVAS_SIDE, live_min)
	_assert_true(absf(from_declared - from_live) > 1.0,
		"at a %.0fpx row the clamp binds and the choice of input MOVES the column (%.0f vs %.0f)"
			% [NARROW_ROW, from_declared, from_live])
	_done("declared_width_holds")


## The Godot behaviour this design BETS ON, measured rather than assumed.
##
## `content_height()` reads `_content.get_combined_minimum_size().y` LIVE, and the Texture
## tab hides `_inspector` outright. Godot's container minimums skip invisible CHILDREN —
## the question is whether hiding an ANCESTOR zeroes a descendant's combined minimum. If
## it did, the row would collapse the moment the Texture tab opened. Asserted, because a
## design resting on an engine detail that nothing checks is the same trap as a comment
## asserting a round-trip property.
func _test_content_height_survives_the_inspector_being_hidden(page) -> void:
	page._set_root(Target.frame(0, 0))
	await _frames(20)
	var h_shown: float = page._inspector.content_height()
	page._set_active_tab("texture")
	await _frames(20)
	var h_hidden: float = page._inspector.content_height()
	page._set_active_tab("values")
	await _frames(20)
	_assert_true(h_shown > 0.0, "the inspector has a natural height to begin with (%.0f)" % h_shown)
	_assert_eq(h_hidden, h_shown,
		"hiding the inspector does NOT zero its content height — the row cannot collapse")
	_done("content_height_survives_hiding")


## dec. 8. The `frame`-only gate was the single reason the Texture PAGE could not show the
## texture. A `texture` target now binds the whole sheet with no frame — which is a real
## view, not an empty one, because `_draw` paints sheet + coverage unconditionally.
func _test_the_gate_admits_the_texture_kind(page) -> void:
	page._set_root(Target.texture())
	await _frames(20)
	_assert_true(page._frameset_panel.visible,
		"a `texture` target shows the sheet — the page finally has a picture")
	_assert_true(page._frameset_canvas._frame.is_empty(),
		"…bound to NO frame, so no UV box is invented for it")
	_assert_true(page._frameset_canvas._texture != null,
		"…and the sheet itself is bound")
	# The scope control has no region to speak for here and must not offer one.
	_assert_true(not page._region_scope.visible,
		"the region scope is hidden when there is no frame in context")
	_done("gate_admits_texture")


## dec. 4. The tab binds what the target can HONESTLY say. A `frame` names one frame; an
## `emitter` names none, and none is invented — binding frame 0 of the shown frameset
## would decode a real rect and draw a real box with nothing saying it is the wrong one.
func _test_the_tab_binds_the_frame_in_context(page) -> void:
	page._set_root(Target.frame(0, 0))
	await _frames(20)
	_assert_eq(page._texture_panel.bound_frameset(), 0, "a frame target binds its frameset")
	_assert_eq(page._texture_panel.bound_frame(), 0, "…and its frame")
	_assert_true(not page._texture_panel.canvas()._frame.is_empty(),
		"…so the tab draws that frame's UV box")

	page._set_root(Target.frameset(1))
	await _frames(20)
	_assert_eq(page._texture_panel.bound_frameset(), 1, "a frameset target binds the frameset")
	_assert_eq(page._texture_panel.bound_frame(), -1, "…and NO frame — a frameset is a group")
	_assert_true(page._texture_panel.canvas()._frame.is_empty(),
		"…so no UV box is minted for a group of them")
	_done("binds_frame_in_context")


## dec. 5. The handles and the scope control ship together or not at all: a drag that can
## move thirty frames without saying so is the ADR-0099 failure by construction.
func _test_the_scope_control_rides_the_handles(page) -> void:
	page._set_root(Target.frame(0, 0))
	await _frames(20)
	var scope = page._texture_panel.region_scope()
	_assert_true(scope != null and scope.visible,
		"a frame in context: the scope control is beside the live handles")

	# AMENDED BY dec. 12. This used to assert the scope was HIDDEN here, on the reasoning
	# that no frame in context meant no handles. There are handles now: every distinct
	# region of the frameset is its own live box, so the control that states a drag's blast
	# radius has to be present — dec. 5 pairs them, and dec. 12d holds its height rather
	# than letting it appear when the pointer enters a box (which would resize the overlay
	# on a mouse-move path and make the facts jump).
	page._set_root(Target.frameset(1))
	await _frames(20)
	_assert_true(page._texture_panel.canvas().group_live,
		"a frameset in context: its regions are live boxes (dec. 12)")
	_assert_true(scope.visible,
		"…so the scope control rides them, exactly as it rides a frame's (dec. 12d)")
	_done("scope_rides_the_handles")


## ADR-0099 dec. 5e, THROUGH THE WIRING. The unit guard lives in
## `EffectStudioRegionScopeTest`; this one is here because the author's report was about a
## GESTURE — *"if you then change the thumbnail, it flips back to effect"* — and what a
## thumbnail change reaches is `TextureTabPanel.bind_sheet`, three calls above the `bind`
## the rule lives in. The predicate was tested and the behaviour was not is this family's
## own recorded failure ([[effect-studio-predicate-tested-not-behaviour]]).
func _test_the_scope_survives_a_thumbnail_change(page) -> void:
	page._set_root(Target.frame(0, 0))
	await _frames(20)
	var scope = page._texture_panel.region_scope()
	if scope == null:
		print("[SKIP] no scope control on this build")
		_passed += 1
		_done("scope_survives_a_thumbnail")
		return

	scope.set_scope(RegionScope.SCOPE_FRAMESET)
	_assert_eq(scope.scope(), RegionScope.SCOPE_FRAMESET, "the author narrows the scope")

	# THE THUMBNAIL CHANGE, as the strip makes it: a re-bind onto another frameset with no
	# single frame in context. This is `_resync_texture_tab_to_playhead`'s own call shape.
	page._texture_panel.bind_sheet(page._effect_data, 1, -1)
	await _frames(6)
	_assert_eq(scope.scope(), RegionScope.SCOPE_FRAMESET,
		"changing the thumbnail keeps it — it no longer flips back to effect-wide")

	# AND THE RADIO SAYS SO. A persisted mode is only safe because it is announced; a scope
	# the control disagrees with would be worse than the reset it replaced.
	var pressed := -1
	for b in scope._scope_buttons:
		if b.button_pressed:
			pressed = int(b.get_meta("scope_mode", -1))
	_assert_eq(pressed, RegionScope.SCOPE_FRAMESET,
		"…and the toggle row shows which mode is live, so nothing about it is silent")
	_done("scope_survives_a_thumbnail")


## THE RAIL SHOWS FOR EVERY REGION, not only for the ones spanning two framesets or more
## (2026-08-21). Author: *"I think it only shows the thumbnails on the bottom if there are
## more than 1 frames referencing the rect - can we just always have it show? it makes it
## less confusing."*
##
## `_rebind_rail` used to collapse a row of one to an empty row, on the reasoning that a row
## of one is not a choice. True about TICKING and wrong about the rail: measured over the
## corpus, 3636 of 6632 regions (54.8%) live in a single frameset, so the rail was absent on
## more than half of them and its presence read as arbitrary. Worse, 3361 of those (50.7% of
## ALL regions) have a single member, and the member list is gated on `_members.size() > 1` —
## so the author saw neither, and nothing named the sprite the edit was about to rewrite.
##
## THE LIST IS THE OTHER HALF, and it is what keeps this from being a trade. The rail
## SUPPRESSES the list, so always showing it would have hidden the list on the 275 regions
## (4.1%) whose several members share one frameset — 68 of which disagree about a facet, so
## their rows are not even repetition. A one-tile rail enumerates none of the choice, so it
## does not earn the suppression; a 13-tile row for 15 members always has and still does.
func _test_the_rail_shows_for_every_region(page) -> void:
	var tp = page._texture_panel
	var rail = tp.rail()
	var scope = tp.region_scope()
	if rail == null or scope == null:
		print("[SKIP] no rail on this build")
		_passed += 1
		_done("rail_always_shows")
		return
	# BOTH ARMS ARE BOUND EXPLICITLY, on regions chosen because they are each kind. A single
	# `Target.frame(0, 0)` looked like it covered this and did not: E019 frame 0/0's region
	# spans 15 framesets, so restoring the old row-of-one collapse left the suite GREEN. A
	# guard for "a row of one still shows" has to bind a row of one.
	#
	# E019 frameset 42 frame 0 is the awkward case on purpose: ONE frameset, TWO members. It
	# is where the rail gains a tile AND the list must not lose one.
	page._set_root(Target.frame(42, 0))
	await _frames(20)
	var row: int = rail.row().size()
	var members: int = scope.members().size()
	_assert_eq(row, 1, "E019 frameset 42's region is the ONE-tile case (%d members)" % members)
	_assert_true(rail.visible,
		"a row of one SHOWS — it used to collapse to an empty row and vanish, which is "
		+ "54.8% of corpus regions and 50.7% where the list is empty too, so the author "
		+ "saw nothing at all naming the sprite the edit would rewrite")
	_assert_true(members > 1 and not scope.list_suppressed,
		"…and the member list survives beside it (%d members), because a one-tile rail "
		% members + "enumerates none of them — this is the 4.1% of regions where always "
		+ "showing the rail would otherwise have LOST something")

	# THE OTHER ARM, unchanged behaviour: E019 frame 0/0's region spans 15 framesets.
	page._set_root(Target.frame(0, 0))
	await _frames(20)
	_assert_true(rail.row().size() > 1,
		"E019 frameset 0's region is the multi-tile case (%d tiles)" % rail.row().size())
	_assert_true(scope.list_suppressed,
		"a real row still REPLACES the member list, as it always has — the change adds a "
		+ "tile where there was none, it does not put two enumerations side by side")
	_done("rail_always_shows")


## THE ASSERTION THAT WAS MISSING, and the reason it is here.
##
## Every other guard in this file was GREEN while the tab showed no picture at all. The
## region scope lists its members — thirty of them on E019's biggest region — and those
## rows landed in the PanelContainer's combined minimum, which a Container may not shrink
## below. So the panel overflowed the rect `_relayout` assigns it (measured 2469px against
## a ~950px row), the canvas grew with it, and the sheet was centred at y=1079: below the
## visible row. Perfect metadata, no picture, 31 passing assertions.
##
## Caught by SCREENSHOT ([[render-atlas-crops-and-look-at-them]]). This is that finding
## turned into a predicate: the panel may not exceed the height it was given, and the
## sheet's draw rect must land inside the part of the body a person can actually see.
func _test_the_picture_is_actually_on_screen(page) -> void:
	page._set_root(Target.frame(0, 0))
	page._set_active_tab("texture")
	await _frames(30)

	var panel: Rect2 = page._texture_panel.get_global_rect()
	var lanes: Rect2 = page._scroll.get_global_rect()
	# SKIP WITH THE NUMBERS when the window cannot express the invariant, rather than
	# asserting through it. The dashboard's height is compositor-chosen and this harness has
	# been handed bodies of 163 and 514 on CONSECUTIVE runs; at 163 the inspector row is
	# shorter than this panel's own irreducible minimum (54px — two Labels and the
	# PanelContainer's padding, with the canvas at zero), so no layout satisfies "the panel
	# fits the row" and the assertion is testing the window manager. Same pattern as
	# EffectStudioFramesetLayoutTest; see [[studio-page-lives-in-separate-window]].
	var min_h: float = page._texture_panel.get_combined_minimum_size().y
	var row_h: float = lanes.position.y - panel.position.y
	if row_h < min_h:
		print("[SKIP] the row is %.0fpx and the tab's irreducible minimum is %.0f — this body (%s) cannot express the invariant"
			% [row_h, min_h, page._body.size])
		_passed += 1
		_done("picture_on_screen")
		return
	_assert_true(panel.position.y + panel.size.y <= lanes.position.y + 1.0,
		"the tab does not overflow its row into the timeline (panel bottom %.0f, lanes top %.0f)"
			% [panel.position.y + panel.size.y, lanes.position.y])

	# The sheet itself, in global coordinates, inside the panel that is supposed to show it.
	var canvas = page._texture_panel.canvas()
	var draw: Rect2 = canvas.current_draw_rect()
	var sheet := Rect2(canvas.get_global_rect().position + draw.position, draw.size)
	_assert_true(sheet.size.x > 0.0 and sheet.size.y > 0.0,
		"the sheet is drawn at a non-zero size (%s)" % sheet.size)

	# NOT `panel.encloses(sheet)` — that was the first form of this assertion and it is
	# WRONG, because a 256-tall sheet in a 237px row overflows on purpose: the viewport
	# opens at 100% and the author pans (ADR-0098, the author's own ruling), and the canvas
	# clips. Demanding containment would fail the layout working correctly.
	#
	# The defect this exists to catch is the sheet drawn ENTIRELY off the panel — centred at
	# y=1079 in a row that ends at 950. So: the sheet must overlap the panel, and its CENTRE
	# must be inside it. Both hold when it merely overflows, neither holds when it is gone.
	_assert_true(panel.intersects(sheet),
		"the sheet overlaps the panel that shows it (sheet %s, panel %s)" % [sheet, panel])
	_assert_true(panel.has_point(sheet.get_center()),
		"the sheet's centre is inside the visible panel (centre %s, panel %s)"
			% [sheet.get_center(), panel])

	# ── AND THE FACTS DO NOT COVER IT (ADR-0130 dec. 11) ──
	#
	# THE THIRD REPORT ON THIS SURFACE was "this box was supposed to just be some tiny box
	# which minimally and/or doesn't cover the texture page." The facts moved from a column
	# beside the picture onto the picture, which answers the width complaint and creates a
	# NEW way to fail the same sentence: an overlay that grows with its content — thirty
	# scope members, say — covers the sheet outright.
	#
	# So this predicate, which already carries the two layout defects this tab has shipped,
	# grows the third: the overlay is INSIDE the port, it is a CORNER of it, and the sheet's
	# centre is not under it.
	var overlay: Control = page._texture_panel.overlay()
	_assert_true(overlay != null and overlay.visible, "the facts overlay is on the port")
	var port: Rect2 = canvas.get_global_rect()
	var ov: Rect2 = overlay.get_global_rect()
	print("[MEASURE] port %s  overlay %s  sheet %s" % [port, ov, sheet])
	_assert_true(port.grow(1.0).encloses(ov),
		"the overlay is inside the port it annotates (overlay %s, port %s)" % [ov, port])
	_assert_true(ov.size.x <= TextureTab.OVERLAY_W + 1.0,
		"…and no wider than its declared ceiling (%.0f vs %.0f)" % [ov.size.x, TextureTab.OVERLAY_W])
	# THE FRACTION IS THE ASK, STATED AS A NUMBER. "Tiny box" is not assertable; "a third of
	# the port at most" is, and it is what reddens if the overlay ever regains a size flag
	# or loses the scope cap — a thirty-row member list alone is 480px of height.
	var frac: float = (ov.size.x * ov.size.y) / maxf(1.0, port.size.x * port.size.y)
	_assert_true(frac <= 0.35,
		"the overlay is corner furniture, not a second column (%.0f%% of the port)" % (frac * 100.0))
	# SAY SO WHEN THE PORT CANNOT EXPRESS IT. The overlay hugs the right edge and the sheet
	# is centred, so a port narrower than ~2*(OVERLAY_W + PAD) puts the centre under the
	# overlay no matter how well the overlay behaves — asserting through that would be
	# testing the window manager.
	var expressible: float = 2.0 * (TextureTab.OVERLAY_W + 2.0 * TextureTab.OVERLAY_PAD)
	if port.size.x < expressible:
		print("[SKIP] the port is %.0fpx and the centre clause needs %.0f — this body cannot express it"
			% [port.size.x, expressible])
	else:
		_assert_true(not ov.has_point(sheet.get_center()),
			"the sheet's centre is not under the facts (centre %s, overlay %s)"
				% [sheet.get_center(), ov])
	_done("picture_on_screen")


## THE SAME BUG ROTATED NINETY DEGREES — AND THEN DISSOLVED (ADR-0130 dec. 11).
##
## THE HISTORY, because the assertions below are what is LEFT of it and read as trivial
## without it. `_test_the_picture_is_actually_on_screen` asserted the panel's BOTTOM edge
## against the timeline. Nothing asserted its RIGHT edge against the column beside it, so
## the tab shipped with its facts column sliced off mid-word ("Dimensions 12…", "⭳ Export
## .tga ⭱…") under the sequence player, and forty green assertions said nothing about it.
##
## The mechanism was arithmetic: `CANVAS_W` (560) plus `DECLARED_SIDE_W` (300) put the
## PanelContainer's combined minimum at 864, `_relayout` assigned it the row's leftover
## (measured 727 / 776 / 812 at a 1187px body), and A CONTAINER CANNOT SHRINK BELOW ITS
## MINIMUM. `768575272` fixed it by making the width a SPLIT the page pre-states.
##
## THE FACTS ARE NOT IN THE ROW ANY MORE. They are anchored inside `FramesetCanvas`, which
## `extends Control` and NOT Container — so they contribute ZERO to this panel's combined
## minimum, and the row and the column have no width left to disagree about. The split is
## not wrong, it is UNREACHABLE, and `set_slot_width` / `canvas_width` / `chrome_width` /
## `DECLARED_SIDE_W` are deleted with it.
##
## So this predicate no longer guards the arithmetic — it guards THE FACT THAT MADE THE
## ARITHMETIC UNNECESSARY, which is the thing a future edit could take away without
## noticing. A `Container` in place of that `Control`, or a `custom_minimum_size` on the
## overlay's ancestor chain, and 864 is back.
func _test_the_overlay_costs_the_row_nothing(page) -> void:
	page._set_active_tab("texture")
	page._set_root(Target.frame(0, 0))
	await _frames(30)
	var panel = page._texture_panel
	var canvas = panel.canvas()
	var overlay = panel.overlay()

	# THE LOAD-BEARING ENGINE FACT, MEASURED RATHER THAN ASSUMED. The entire history of
	# this file is minimums propagating somewhere nobody expected, so the one this design
	# rests on is asserted rather than trusted: a `Control` parent does not fold a child's
	# minimum into its own.
	_assert_true(overlay.get_parent() == canvas,
		"the facts hang off the CANVAS, not off a sibling of it")
	_assert_true(not (canvas is Container),
		"…and that canvas is a plain Control, which is what makes the next assertion true")
	# THE SIZE, not the minimum, and the distinction is the point. The overlay's own
	# minimum is deliberately ~zero (its body scrolls, so nothing inside it can bid for
	# width — see `SCROLL_MODE_SHOW_NEVER` in the panel); what it HAS is a real 248px rect
	# assigned by `_place_overlay`. A 248px laid-out child contributing zero to its parent's
	# minimum is exactly the engine fact this design rests on, and asserting the minimum
	# here would have asserted nothing at all.
	_assert_true(overlay.size.x > 100.0,
		"the overlay really is a sized control (%.0f wide) — otherwise this proves nothing"
			% overlay.size.x)
	_assert_true(canvas.get_combined_minimum_size().x < 1.0,
		"…and NONE of that width reaches the canvas (%.1f)"
			% canvas.get_combined_minimum_size().x)

	# THE PANEL'S MINIMUM IS CHROME ALONE, at every target kind and whatever is bound. The
	# pre-move number was 864 (measured, and printed by the shot rig at this same body), so
	# this reddens by a factor of ten on the old shape rather than by a hair.
	const CHROME_CEILING := 96.0
	for target in [Target.frame(0, 0), Target.frameset(10), Target.emitter(0)]:
		# Navigate AWAY first: `_set_root` on the target already open is a NO-OP and does
		# not re-run the update chain, so without this the assertions read whatever the
		# previous case left behind.
		page._set_root(Target.texture())
		await _frames(10)
		page._set_root(target)
		page._set_active_tab("texture")
		await _frames(30)
		# STOP THE PLAYER — the column's width tracks the focus block's declared content
		# width and breathes a few px as the animation advances (the same flake as
		# `_test_a_tab_switch_moves_nothing_in_the_right_column`).
		if page._sequence_canvas != null:
			page._sequence_canvas.set_playing(false)
		await _frames(20)
		var live_min: float = panel.get_combined_minimum_size().x
		print("[MEASURE] %s: tab min=%.0f  assigned=%.0f  canvas=%.0f"
			% [Target.kind(target), live_min, panel.size.x, canvas.size.x])
		_assert_true(live_min < CHROME_CEILING,
			"%s: the tab's whole width claim is chrome (%.0f, was 864 before dec. 11)"
				% [Target.kind(target), live_min])
		# AND THE PICTURE GOT THE ROW. The ask, stated as a number: the canvas is the slot,
		# not a 560px cap with a thousand pixels of leftover going to a column of text.
		_assert_true(canvas.size.x >= panel.size.x - CHROME_CEILING,
			"%s: the port IS the slot (%.0f of %.0f) — no column beside it"
				% [Target.kind(target), canvas.size.x, panel.size.x])
		# The original complaint's own edge, kept: the tab still stops before the column.
		var column: Rect2 = _column_rect(page)
		if column.size.x <= 0.0:
			print("[NOTE] %s carries no right column here" % Target.kind(target))
			_passed += 1
			continue
		var rect := Rect2(panel.position, panel.size)
		_assert_true(rect.position.x + rect.size.x <= column.position.x + 1.0,
			"%s: the tab stops before the column starts (panel right %.0f, column left %.0f)"
				% [Target.kind(target), rect.position.x + rect.size.x, column.position.x])

	# THE PURE PLACEMENT, at ports no window here will hand us.
	#
	# `overlay_rect` is where the two remaining ways to fail live, and both are about SMALL
	# ports: an overlay taller than the port hangs off one edge (the reachability defect
	# `cbe359478` fixed, arriving on the other axis), and one wider than the port eats the
	# picture whole. This family has measured ports from 153px up, so neither is invented.
	var want := Vector2(TextureTab.OVERLAY_W, 360.0)
	for port in [Vector2(1564, 701), Vector2(560, 263), Vector2(300, 200), Vector2(120, 90),
			Vector2(40, 20), Vector2(0, 0)]:
		var r: Rect2 = TextureTab.overlay_rect(port, want)
		_assert_true(r.size.x >= 0.0 and r.size.y >= 0.0,
			"a %s port yields a non-negative overlay (%s)" % [port, r])
		_assert_true(Rect2(Vector2.ZERO, port).grow(0.5).encloses(r),
			"a %s port CONTAINS its overlay (%s) — nothing hangs off an edge" % [port, r])
		_assert_true(r.size.x <= want.x + 0.5 and r.size.y <= want.y + 0.5,
			"…and the overlay never grows past what it asked for (%s vs %s)" % [r.size, want])
	# BOTTOM-RIGHT, one pad in, whenever the port can afford it — the corner the author
	# named. Asserted at a port with room, because at a port without room the clamp above
	# is the whole story and this would be a tautology.
	var roomy: Rect2 = TextureTab.overlay_rect(Vector2(1564, 701), want)
	_assert_eq(roomy.position.x + roomy.size.x, 1564.0 - TextureTab.OVERLAY_PAD,
		"the overlay's right edge is one pad off the port's")
	_assert_eq(roomy.position.y + roomy.size.y, 701.0 - TextureTab.OVERLAY_PAD,
		"…and its bottom edge likewise — bottom RIGHT, as asked")
	_assert_eq(roomy.size, want, "…at the size it wanted, since this port can afford it")
	_done("overlay_costs_the_row_nothing")


## THE ⬥ DEFECT, PRE-EMPTED ON THE AXIS THIS SHAPE EXPOSES IT ON.
##
## `cbe359478` moved the ⬥ button above the colour grid because a control pinned below a
## growing list goes off the bottom edge: TECHNICALLY VISIBLE, ACTUALLY UNREACHABLE, and
## nothing in that suite could see it because every assertion asked whether the button
## existed and was enabled. An overlay pinned to the port's BOTTOM edge has exactly that
## failure available to it, so Export/Import sit at the TOP of the overlay and this asks
## WHERE they are, not whether they are there.
##
## ON A PROBE, NOT THE LIVE TAB, and deliberately. The live port here is 700px tall and the
## overlay wants ~360 — the case cannot redden. A probe with an explicitly short port can,
## at any body, on a tiling WM that refuses `Window.size`.
func _test_the_actions_are_reachable_on_a_short_port(page) -> void:
	var probe = TextureTab.new()
	add_child(probe)
	probe.size = Vector2(520, 150)     # shorter than the overlay's content wants
	await _frames(4)
	probe.bind_sheet(page._effect_data, 0, 0)
	await _frames(6)

	var port: Rect2 = probe.canvas().get_global_rect()
	var ov: Rect2 = probe.overlay().get_global_rect()
	_assert_true(port.size.y > 0.0, "the probe has a port at all (%s)" % port)
	_assert_true(port.grow(1.0).encloses(ov),
		"a %s port still CONTAINS the overlay (%s) — it does not hang off the bottom"
			% [port.size, ov])
	_assert_true(ov.size.y < 360.0,
		"…because the overlay was clamped to it (%.0f tall) rather than overflowing" % ov.size.y)

	# THE ACTIONS THEMSELVES, by rect. The refusal path hides them, so assert the state
	# first — E019 is 8bpp and authorable, and a silent skip here would be the ⬥ bug again.
	var ex: Button = probe.export_button()
	var im: Button = probe.import_button()
	_assert_true(ex.get_parent().visible,
		"E019 is authorable, so the actions are offered (not the ADR-0199 refusal)")
	for b in [ex, im]:
		var r: Rect2 = b.get_global_rect()
		_assert_true(r.size.x > 0.0 and r.size.y > 0.0, "%s has a real rect (%s)" % [b.text, r])
		_assert_true(port.grow(1.0).encloses(r),
			"%s is inside the port on a %s canvas (%s)" % [b.text, port.size, r])

	# AND THE ORDERING THAT MAKES THAT TRUE, stated so a future edit that drops the actions
	# back below the facts reddens here rather than on the author's screen. The clamp eats
	# the BOTTOM of the overlay's content; whatever is last is what goes.
	_assert_true(ex.get_global_rect().position.y < probe._facts_grid.get_global_rect().position.y,
		"the actions sit ABOVE the facts, so a clamp takes a fact and never a button")
	probe.queue_free()
	_done("actions_are_reachable")


## "IT JUST NEEDS TO BE MADE MORE DISCREET" — the fold is the floor of that, and the floor
## has to actually be a floor.
##
## Folded, the overlay is the caption row and nothing else. Asserted as a RATIO against its
## own unfolded height rather than a pixel count, because the theme's font metrics are not
## this test's business and a hardcoded number would go stale on the next theme change.
##
## AND IT SURVIVES A REBIND: an author who folded the facts away to look at the sheet did
## not ask for them back because they clicked a different frame. `bind_sheet` rebuilds the
## grid and re-places the overlay, so this is a live way for the state to be lost.
func _test_the_overlay_folds_to_the_caption(page) -> void:
	page._set_root(Target.frame(0, 0))
	page._set_active_tab("texture")
	await _frames(30)
	var panel = page._texture_panel
	var overlay = panel.overlay()

	panel.set_folded(false)
	await _frames(4)
	var open_h: float = overlay.size.y
	panel.set_folded(true)
	await _frames(4)
	var shut_h: float = overlay.size.y
	var port_h: float = panel.canvas().size.y
	var header_h: float = panel.fold_toggle().size.y
	print("[MEASURE] port=%.0f  overlay open=%.0f folded=%.0f  header=%.0f"
		% [port_h, open_h, shut_h, header_h])

	# THE PORT-INDEPENDENT CLAIM FIRST, because the ratio below is not one. Folding hides
	# the body, so what is left is the header row plus the panel's own margins — true at
	# every port this harness can be handed.
	if port_h < 96.0:
		print("[SKIP] a %.0fpx port cannot express a fold at all" % port_h)
		_passed += 1
	else:
		_assert_true(shut_h < open_h - 1.0,
			"folding makes the overlay shorter (%.0f -> %.0f)" % [open_h, shut_h])
		_assert_true(shut_h <= header_h + 16.0,
			"…and what is left is the header row alone (%.0f, header %.0f)" % [shut_h, header_h])
		_assert_true(shut_h > 0.0, "…but it is still THERE, so the author can unfold it")

	# THE RATIO IS ONLY EXPRESSIBLE ON A PORT TALL ENOUGH TO SHOW THE OPEN OVERLAY WHOLE,
	# and this is the second time this file has learned that lesson on a compositor-chosen
	# body. Measured on consecutive unchanged runs: a 701px port (open 319, folded 39) and a
	# ~150px one, where `OVERLAY_MAX_H_FRACTION` clamps the OPEN overlay to 90 — at which
	# point "folded is under 40% of open" is measuring the CLAMP, not the fold, and it
	# reddened on code that was working perfectly. Skip with the numbers, the pattern this
	# file already uses twice.
	var cap: float = port_h * TextureTab.OVERLAY_MAX_H_FRACTION
	if open_h >= cap - 1.0:
		print("[SKIP] the %.0fpx port clamps the open overlay to %.0f — the fold RATIO would measure the clamp"
			% [port_h, open_h])
		_passed += 1
	else:
		_assert_true(open_h > 100.0,
			"the unfolded overlay has real content to hide (%.0f)" % open_h)
		_assert_true(shut_h <= open_h * 0.4,
			"folded, it is the caption alone (%.0f vs %.0f open)" % [shut_h, open_h])

	panel.bind_sheet(page._effect_data, 0, 1)
	await _frames(6)
	_assert_true(panel.is_folded(), "a rebind does not silently unfold the facts")
	_assert_true(overlay.size.y <= shut_h + 1.0,
		"…and the folded overlay does not grow on the rebind (%.0f)" % overlay.size.y)

	panel.set_folded(false)
	await _frames(4)
	_assert_true(overlay.size.y >= minf(open_h, cap) - 1.0,
		"unfolding brings the facts back (%.0f)" % overlay.size.y)

	# ── THE TOGGLE HAS TO BE HITTABLE IN BOTH DIRECTIONS ──
	#
	# The author, on the first build: *"it seems like I can close the but can't reopen it."*
	# The fold shipped as a 17px flat chevron beside a plain caption Label — a Button with
	# no border, no background and one glyph, sitting next to the text that looks like the
	# obvious thing to click and was inert. Every assertion above was green: the state
	# round-tripped perfectly when driven through `set_folded`, which is exactly the gap
	# `cbe359478` opened on ⬥ and dec. 11c closed for Export/Import. A control can be
	# present, visible, correctly wired AND unusable.
	#
	# So this asks WHERE the toggle is and HOW BIG, in both states, and then drives the fold
	# through the CONTROL rather than through the setter — because the setter was never the
	# broken half.
	var toggle: Button = panel.fold_toggle()
	_assert_true(toggle != null, "the overlay has a fold toggle")
	for want_folded in [false, true]:
		panel.set_folded(want_folded)
		await _frames(4)
		var tr: Rect2 = toggle.get_global_rect()
		var ovr: Rect2 = overlay.get_global_rect()
		print("[MEASURE] folded=%s  toggle %s  overlay %s" % [want_folded, tr, ovr])
		_assert_true(ovr.grow(1.0).encloses(tr),
			"folded=%s: the toggle is inside the overlay (%s in %s)" % [want_folded, tr, ovr])
		# THE WHOLE HEADER, not a glyph. 0.8 of the overlay's width leaves room for the
		# panel's content margins and nothing else — a 17px chevron in a 248px box is 0.07
		# and reddens by an order of magnitude.
		_assert_true(tr.size.x >= ovr.size.x * 0.8,
			"folded=%s: the toggle spans the header row, not a glyph (%.0f of %.0f)"
				% [want_folded, tr.size.x, ovr.size.x])
		_assert_true(tr.size.y >= 12.0,
			"folded=%s: …and is tall enough to hit (%.0f)" % [want_folded, tr.size.y])
	# AND THE CONTROL ITSELF DRIVES IT, both ways. `set_folded` was always correct; the
	# button was not wired to anything an author could reach.
	panel.set_folded(false)
	await _frames(4)
	toggle.button_pressed = false
	await _frames(4)
	_assert_true(panel.is_folded(), "pressing the header FOLDS it")
	toggle.button_pressed = true
	await _frames(4)
	_assert_true(not panel.is_folded(), "…and pressing it again UNFOLDS it — both directions")

	# AND A REAL MOUSE PRESS GETS THERE, which is the only clause above that tests the thing
	# the author actually did. `button_pressed` drives the Button directly and proves nothing
	# about the input path: the overlay sits INSIDE `FramesetCanvas`, which is
	# `MOUSE_FILTER_STOP` and owns hover, zoom, pan and (since dec. 12) N draggable region
	# boxes. If the canvas swallowed the press the toggle would be perfectly wired and
	# perfectly unreachable — which is the shape of the defect this whole test exists for.
	# A SYNTHETIC MOUSE CLICK IS DELIBERATELY *NOT* ASSERTED HERE, and this note exists so
	# the next reader does not spend the hour again.
	#
	# `Viewport.push_input` transforms the event by `get_final_transform().affine_inverse()`,
	# the studio dashboard is a SEPARATE WINDOW with its own `content_scale_factor`
	# ([[studio-page-lives-in-separate-window]]), and a point read off `get_global_rect()`
	# does not land where it looks like it should — pushed both raw and pre-transformed, the
	# viewport found NO control at all, not even the 1564px canvas. `gui_get_hovered_control`
	# cannot arbitrate either: it returns null for synthetic input regardless, because
	# `_gui_update_mouse_over` early-returns unless `gui.mouse_in_viewport` is set, and that
	# comes from a real OS mouse-enter. A guard built on that would be testing itself.
	#
	# It is also not the open question. The author COULD fold the overlay — they hit the
	# 17px chevron — and could not unfold it, which proves the press reaches a Button
	# inside this overlay through the canvas's `MOUSE_FILTER_STOP`. What failed was the
	# TARGET, and the target is what the rect assertions above measure.
	panel.set_folded(false)
	await _frames(4)
	_done("the_overlay_folds")


## ADR-0098 dec. 2, AMENDED PER SURFACE — the author's second complaint, and their second
## ruling on the same question.
##
## "can we get the texture defaulted to a reasonable size when we open the texture page? it
## starts kind of small." Measured: a 128x256 sheet drew 128x256 in a 560x701 port on a
## `frame` target — 23% of the width, 37% of the height — because dec. 2 says the view opens
## at a flat 100%, always.
##
## Dec. 2 is not overturned, it becomes A FLOOR: the tab opens at `max(1, fit)`. That
## distinction is the whole assertion, and it is not pedantry — `fit_scale` snaps DOWN the
## ladder, so on the SHORT `frameset` row a 256-tall sheet in a 263-tall port fits at 0.96
## and snaps to 0.5. A bare fit would HALVE the picture to save nine pixels, which is the
## exact measurement that made dec. 2 a flat 100% in the first place. Both cases are
## asserted, because only having the tall one would let a bare fit pass.
func _test_the_sheet_opens_at_a_useful_size(page) -> void:
	var canvas = page._texture_panel.canvas()
	var frame_canvas = page._frameset_canvas

	# THE POLICY IS PER SURFACE, and the frame screen keeps dec. 2 verbatim: a fit that
	# snaps down renders a 23x23 UV box at 12px, smaller than its own 8px corner handles,
	# which is the drag failure ADR-0098 recorded when fitting was tried there.
	_assert_true(canvas.open_at_fit, "the Texture TAB opts into fit-floored-at-100%")
	_assert_true(not frame_canvas.open_at_fit,
		"the FRAME screen's canvas does not — ADR-0098 dec. 2 still holds where it was ruled")

	# PURE, over the two port shapes this surface really gets, using E019's real sheet.
	# `fit_scale` is what the floor is applied to, so both halves are visible here.
	var sheet := Vector2(128, 128)
	sheet = Vector2(page._effect_data.texture.get_width(), page._effect_data.texture.get_height())
	# The two port SHAPES this surface gets, kept as the numbers the split used to produce
	# (dec. 11 gave the port the whole slot, so the live ones are wider now — but width was
	# never the binding term here and making these wider would only weaken the case).
	var tall := Vector2(423, 701)    # a `frame` target's row
	var short := Vector2(472, 263)   # a `frameset` target's — the row is the binding term
	var fit_tall: float = Canvas_.fit_scale(tall, sheet)
	var fit_short: float = Canvas_.fit_scale(short, sheet)
	print("[MEASURE] sheet %s  fit(tall %s)=%.3f  fit(short %s)=%.3f"
		% [sheet, tall, fit_tall, short, fit_short])
	_assert_true(fit_tall >= 2.0,
		"a tall port fits this sheet at %.0fx — the room dec. 2 was leaving unused" % fit_tall)
	_assert_true(fit_short < 1.0,
		"a short port does NOT (fit %.3f) — so the floor has something to do" % fit_short)

	# THE POLICY ITSELF, at both ports, on a real canvas the compositor cannot reach.
	# Asserting `maxf(1.0, fit_short) == 1.0` instead would have been a claim about `maxf`
	# — a tautology that stays green with the floor stripped out of the code, which is
	# precisely the guard-that-cannot-redden trap this file already fell into once.
	var probe = Canvas_.new()
	probe.open_at_fit = true
	probe.visible = false
	add_child(probe)
	probe.bind_frame(page._effect_data.texture, {})
	probe.size = tall
	await _frames(2)
	_assert_eq(probe.opening_scale(), 2.0,
		"a %s port opens the sheet at 2x — the room dec. 2 was leaving unused" % tall)
	probe.size = short
	await _frames(2)
	_assert_eq(probe.opening_scale(), 1.0,
		"a %s port opens it at 100%%, NOT at the 0.5 a bare fit would snap to" % short)
	# And the opt-out really is dec. 2 verbatim, at the same two ports.
	probe.open_at_fit = false
	_assert_eq(probe.opening_scale(), 1.0, "opted out, a short port is still 100%")
	probe.size = tall
	await _frames(2)
	_assert_eq(probe.opening_scale(), 1.0, "opted out, a TALL port is 100% too — dec. 2 verbatim")
	probe.queue_free()

	# LIVE, on the real canvas at whatever port the window gives it. The claim is the
	# INVARIANT, not a number: the opening rung is never below 100%, and never above what
	# the port can show whole.
	for target in [Target.frame(0, 0), Target.frameset(10)]:
		page._set_root(Target.texture())
		await _frames(10)
		page._set_root(target)
		page._set_active_tab("texture")
		await _frames(30)
		var opening: float = canvas.opening_scale()
		var port: Vector2 = canvas.size
		var live_fit: float = Canvas_.fit_scale(port, sheet)
		_assert_true(opening >= 1.0,
			"%s: never smaller than 100%% (port %s, opening %.3f)"
				% [Target.kind(target), port, opening])
		_assert_eq(opening, maxf(1.0, live_fit),
			"%s: opens at max(1, fit) — port %s, fit %.3f" % [Target.kind(target), port, live_fit])
		# The rung ladder is not decorative: a non-rung scale draws a texel as a fractional
		# number of screen pixels, which is what ADR-0098 dec. 1 exists to prevent.
		_assert_eq(opening, Canvas_.ladder_snap(opening),
			"%s: the opening scale is a ladder RUNG (%.3f)" % [Target.kind(target), opening])
		# And a fresh bind really is AT the opening rung — `_zoom_steps` is a count from it.
		_assert_eq(canvas.current_scale(), opening,
			"%s: a freshly-bound sheet draws at the opening rung" % Target.kind(target))
	_done("opens_at_a_useful_size")


## dec. 10 — THE SWAP. A frame screen is "the sheet on the left, the animation on the
## right": the Texture tab draws the sheet, and the right column that used to draw it
## again now plays the sequence that shows this frameset.
##
## Measured over all 401 effects / 17,423 framesets: 76.4% are named by exactly ONE
## animation, 10.8% by none, 12.8% by several. All three cases are asserted, because the
## none case is the one where inventing an address would be the ADR-0100 defect — a real
## sequence, real sprites, nothing on screen saying it is the wrong one.
func _test_a_frame_screen_plays_instead_of_drawing_the_sheet_twice(page) -> void:
	# Navigate AWAY and back. `_set_root` on the target that is already open is a no-op —
	# it does not re-run the update chain — so re-selecting `frame(0,0)` after the previous
	# test left it open asserts the state that test happened to leave behind, not this
	# one's. Cost an hour of chasing a "failure" that was the harness, not the page.
	page._set_root(Target.frameset(0))
	await _frames(20)
	page._set_root(Target.frame(0, 0))
	await _frames(30)
	_assert_true(not page._frameset_panel.visible,
		"a frame target no longer parks the sheet in the right column")
	_assert_true(page._sequence_panel.visible,
		"…the sequence player takes that slot instead")
	_assert_true(not page._sequence_bound.is_empty(),
		"…bound to a real address (%s)" % page._sequence_bound)

	# The address is the animation that actually names this frameset, not `index 0` by luck.
	var fs_idx: int = 0
	var bound: int = int(page._sequence_bound.get("anim_index", -1))
	var names_it := false
	for op in page._effect_data.animations[bound].get("opcodes", []):
		if op is Dictionary and str(op.get("type", "")) == "FRAME" \
				and int(op.get("frameset", -1)) == fs_idx:
			names_it = true
	_assert_true(names_it,
		"…and animation %d really does name frameset %d" % [bound, fs_idx])

	# An ORPHAN frameset claims nothing rather than inventing a sequence.
	var orphan: int = _orphan_frameset(page._effect_data)
	if orphan < 0:
		print("[NOTE] E019 has no orphan frameset — the no-address case is inexpressible here")
		_passed += 1
	else:
		page._set_root(Target.frameset(orphan))
		await _frames(30)
		_assert_true(not page._sequence_panel.visible,
			"frameset %d is named by NO animation, so the column claims nothing" % orphan)
	_done("frame_screen_plays")


## A frameset no FRAME opcode names — 10.8% of the corpus. Derived from the effect in hand
## rather than hardcoded, so this cannot silently stop testing anything.
static func _orphan_frameset(effect_data) -> int:
	var named := {}
	for anim in effect_data.animations:
		if not (anim is Dictionary):
			continue
		for op in anim.get("opcodes", []):
			if op is Dictionary and str(op.get("type", "")) == "FRAME":
				named[int(op.get("frameset", -1))] = true
	for i in range(effect_data.framesets.size()):
		if not named.has(i):
			return i
	return -1


func _column_rect(page) -> Rect2:
	for p in [page._frameset_panel, page._sequence_panel]:
		if p != null and p.visible:
			return Rect2(p.position, p.size)
	return Rect2()


func _field_names(target: Dictionary, effect_data) -> Array:
	var out: Array = []
	for sec in FramesetProjector.sections(target, effect_data, {}):
		for f in sec.get("fields", []):
			out.append(str(f.get("name", "")))
	return out


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _settle(node: Control, what: String, max_frames: int = 240) -> void:
	var last := Vector2.ZERO
	var stable := 0
	for i in range(max_frames):
		await get_tree().process_frame
		if node == null:
			return
		if node.size == last:
			stable += 1
			if stable >= 8:
				return
		else:
			stable = 0
			last = node.size
	print("[NOTE] %s never settled in %d frames (last %s)" % [what, max_frames, last])


class _FakeData extends RefCounted:
	var framesets: Array = []


func _assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s\n         expected: %s\n         actual:   %s" % [msg, expected, actual])


## Rect equality to within a pixel on every edge — see the call sites for why a tolerance.
func _assert_rect(a: Rect2, b: Rect2, msg: String) -> void:
	var ok: bool = absf(a.position.x - b.position.x) <= 1.0 \
		and absf(a.position.y - b.position.y) <= 1.0 \
		and absf(a.size.x - b.size.x) <= 1.0 \
		and absf(a.size.y - b.size.y) <= 1.0
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s\n         expected: %s\n         actual:   %s" % [msg, b, a])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % msg)
