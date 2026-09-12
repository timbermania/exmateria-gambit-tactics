extends Node
## TDD guard for the FRAMESET RAIL — the `Pick` half of the ADR-0099 dec. 5 scope toggle
## (author, 2026-08-21: *"subset of framesets (manual toggle, thumbnail order)"* … *"actual
## thumbnails along the bottom of the texture viewfinder - I guess? we will need to scale
## them dynamically"*).
##
## The geometry is PURE statics on purpose. The rail is drawn rather than assembled from
## container nodes (see the file's own header on why), so there are no child rects to read
## back — which would make every layout question a screenshot question. This way the
## scaling rule, the hit rule and the backdrop's extent are all assertable without a window,
## and the screenshot is spent on the one thing only a screenshot can answer: whether the
## picture is right.
##
## Run: <GODOT> --path . --quit-after 60 res://tests/EffectStudioFramesetRailTest.tscn

const Rail = preload("res://src/effects/studio/RegionFramesetRail.gd")
const Scope = preload("res://src/effects/studio/FramesetRegionScope.gd")
const Painter = preload("res://src/effects/studio/SequenceSpritePainter.gd")
const Bounds = preload("res://src/effects/studio/SequenceTimeline.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_tiles_grow_to_a_ceiling_and_shrink_to_a_floor()
	_test_past_the_floor_the_rail_scrolls_instead_of_shrinking()
	_test_an_empty_row_asks_for_no_height()
	_test_the_backdrop_covers_the_tiles_and_not_the_sheet()
	_test_the_label_is_part_of_its_tile()
	_test_a_tick_switches_the_mode_and_the_rail_follows()
	_test_each_tile_is_fit_to_its_own_sprite()

	print("\n=== EffectStudioFramesetRailTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioFramesetRailTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioFramesetRailTest")
		get_tree().quit(0)


## "Scale them dynamically", stated as a rule with two stops.
##
## THE FLOOR IS THE LOAD-BEARING HALF. Censused, a region spans a median of 3 framesets but
## p99 is 31 and the max is 71 — and 71 tiles across a measured 798px port is an 11px tile,
## which is a smear rather than a picture and cannot be aimed at. Without a floor the rule
## "fit them all" silently produces exactly that at the tail of the corpus.
func _test_tiles_grow_to_a_ceiling_and_shrink_to_a_floor() -> void:
	# Three tiles in a wide port: they would each get ~260px, so the CEILING binds.
	_assert_eq(Rail.tile_size(800.0, 3), Rail.TILE_MAX,
		"a short row does not blow three sprites up across the sheet")
	# Twenty in the same port: (800 - 8 - 57) / 20 = 36.75 — between the stops, so it is
	# the fit that binds and the whole row is visible without scrolling.
	var mid: float = Rail.tile_size(800.0, 20)
	_assert_true(mid > Rail.TILE_MIN and mid < Rail.TILE_MAX,
		"a middling row scales to fit (%.1f)" % mid)
	# The corpus maximum in a narrow port: the FLOOR binds.
	_assert_eq(Rail.tile_size(400.0, 71), Rail.TILE_MIN,
		"71 framesets never shrink into a smear")
	_assert_eq(Rail.tile_size(800.0, 0), 0.0, "no row, no tile")


## Past the floor the row overflows, and overflow that cannot be scrolled to is a set of
## framesets that do not exist as far as the author knows.
func _test_past_the_floor_the_rail_scrolls_instead_of_shrinking() -> void:
	var narrow := Vector2(400.0, 60.0)
	_assert_true(Rail.max_scroll(narrow, 71) > 0.0,
		"a row past the floor can be scrolled (%.0f)" % Rail.max_scroll(narrow, 71))
	# AND A ROW THAT FITS CANNOT BE. Otherwise the author scrolls a full row off its own
	# left edge and the tiles simply vanish, with nothing saying they came back.
	_assert_eq(Rail.max_scroll(Vector2(800.0, 60.0), 3), 0.0,
		"a row that fits has nowhere to scroll to")
	# The last tile is reachable at full scroll — the predicate that actually matters.
	var n := 71
	var last: Rect2 = Rail.tile_rect(n - 1, n, narrow, Rail.max_scroll(narrow, n))
	_assert_true(last.position.x + last.size.x <= narrow.x + 0.01,
		"scrolled to the end, the last tile is on the rail (right edge %.1f of %.0f)"
			% [last.position.x + last.size.x, narrow.x])


## An empty row asks for ZERO height, so the host hides it rather than reserving a strip of
## the sheet to say nothing — the lesson the scope's member list learned the hard way when
## a one-row list cost 124px of reserved void.
func _test_an_empty_row_asks_for_no_height() -> void:
	_assert_eq(Rail.rail_height(800.0, 0), 0.0, "no framesets, no rail")
	_assert_eq(Rail.used_width(Vector2(800.0, 60.0), 0), 0.0, "and no backdrop")
	_assert_true(Rail.rail_height(800.0, 3) > 0.0, "a real row asks for real height")
	_assert_eq(Rail.hit_tile(Vector2(10, 10), 0, Vector2(800, 60), 0.0), -1,
		"an empty rail is not a crash and takes no clicks")


## THE BACKDROP IS THE TILES' WIDTH, NOT THE RAIL'S.
##
## Found by SCREENSHOT with this suite's geometry green. On E066 frameset 59 a 13-tile row
## at TILE_MAX spans 772 of a 1562-unit port, and a full-width backdrop laid a translucent
## scrim over the whole bottom of the sheet — including the live yellow box the author is
## dragging, which is the one thing on the surface that must not be dimmed.
func _test_the_backdrop_covers_the_tiles_and_not_the_sheet() -> void:
	var port := Vector2(1562.0, 75.0)
	var used: float = Rail.used_width(port, 13)
	_assert_true(used < port.x * 0.6,
		"a 13-tile row leaves most of the sheet's bottom uncovered (%.0f of %.0f)"
			% [used, port.x])
	# It ends just past the last tile, not somewhere arbitrary.
	var last: Rect2 = Rail.tile_rect(12, 13, port, 0.0)
	_assert_true(used >= last.position.x + last.size.x,
		"the backdrop reaches the last tile (%.0f vs %.0f)" % [used, last.position.x + last.size.x])
	_assert_true(used <= last.position.x + last.size.x + 2.0 * Rail.PAD + 0.01,
		"…and stops there")
	# A row that DOES fill the port is capped at it rather than drawing off the edge.
	_assert_true(Rail.used_width(Vector2(400.0, 60.0), 71) <= 400.0,
		"an overflowing row's backdrop is clipped to the rail")


## The frameset NUMBER is part of its tile's target. A 24px picture with an 11px number
## under it is one thing to the eye, and a band of dead pixels between rows of targets is
## how a click lands on nothing — the "present, visible, and not hittable" family again.
func _test_the_label_is_part_of_its_tile() -> void:
	var port := Vector2(800.0, 80.0)
	var r: Rect2 = Rail.tile_rect(1, 5, port, 0.0)
	var on_picture := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5)
	var on_label := Vector2(r.position.x + 2.0, r.position.y + r.size.y + Rail.LABEL_H * 0.5)
	_assert_eq(Rail.hit_tile(on_picture, 5, port, 0.0), 1, "the picture is the target")
	_assert_eq(Rail.hit_tile(on_label, 5, port, 0.0), 1, "and so is the number under it")
	# The gap BETWEEN tiles is not any tile.
	var between := Vector2(r.position.x + r.size.x + Rail.TILE_GAP * 0.5,
		r.position.y + r.size.y * 0.5)
	_assert_eq(Rail.hit_tile(between, 5, port, 0.0), -1, "the gap belongs to nobody")
	# A SCROLLED RAIL HITS WHAT IT DRAWS. Both read the same `tile_rect`, which is the point
	# of it being one static: a hit rule derived separately from the draw is how a control
	# ends up highlighting one tile and toggling another.
	var narrow := Vector2(300.0, 60.0)
	var scrolled: Rect2 = Rail.tile_rect(9, 40, narrow, 200.0)
	_assert_eq(Rail.hit_tile(scrolled.get_center(), 40, narrow, 200.0), 9,
		"a scrolled tile is picked where it is drawn")


## END TO END, without a window: a tick on the rail's row reaches the scope and narrows the
## selection, and the scope's own toggle row moves the ticks back.
func _test_a_tick_switches_the_mode_and_the_rail_follows() -> void:
	var scope = Scope.new()
	add_child(scope)
	scope.bind(_framesets(), 2, 0)
	var row: Array = scope.region_framesets()
	_assert_eq(str(row), str([0, 1, 2]), "the rail's row is the region's framesets")
	_assert_eq(scope.selected_members().size(), 3, "and Effect takes all three")

	scope.toggle_frameset(1)
	_assert_eq(scope.scope(), Scope.SCOPE_SUBSET, "a tile tick switches the mode to Pick")
	_assert_eq(scope.selected_members().size(), 2, "…by un-ticking the one that was clicked")
	_assert_true(not scope.is_frameset_selected(1), "and the rail draws it un-ticked")
	_assert_true(scope.is_frameset_selected(0), "while the others stay ticked")

	scope.set_scope(Scope.SCOPE_EFFECT)
	_assert_true(scope.is_frameset_selected(1), "Effect puts every tile back")
	scope.free()


## Three framesets, one member each, all sampling the SAME 32x32 block — the rail's ordinary
## case (median 3) and the one where every tile is a different sprite drawn from one rect.
func _framesets() -> Array:
	var uv := {"x": 8, "y": 40, "width": 32, "height": 32}
	var quad := {"top_left": [-10, -10], "top_right": [10, -10],
		"bottom_left": [-10, 10], "bottom_right": [10, 10]}
	return [
		{"frames": [{"uv": uv.duplicate(), "palette_id": 0, "vertices": quad}]},
		{"frames": [{"uv": uv.duplicate(), "palette_id": 0, "vertices": quad}]},
		{"frames": [{"uv": uv.duplicate(), "palette_id": 0, "vertices": quad}]},
	]


func _assert_eq(actual, expected, label: String) -> void:
	if str(actual) == str(expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


## EACH TILE IS FIT TO ITS OWN SPRITE, not to one box shared across the row (2026-08-21).
##
## The rail copied the sequence strip's shared-box rule at first. It does not carry over:
## a strip's row is one animation over TIME, where the shared box is what makes "same
## picture, moved" visible; this row is one REGION's framesets, every member of which is the
## SAME sheet rect by definition. What differs is the frame QUAD, a transform — so members
## are routinely the same texels at wildly different scales, and under a shared box the
## small ones became slivers. Author: *"why don't I see the thumbnails on the texture
## anymore for what is selected for multi select?"*
##
## E317 frameset 15's region is the reported case, and these are its real numbers: bounds of
## 33x33 beside 33x5, 27x5, 21x5, 14x5, 10x5. Corpus-wide 19.2% of tiles drew under a
## quarter of the shared box; fit to their own, 2.8% still draw under 2px and that residual
## is extreme ASPECT RATIO (244x4 beams), which no choice of box can fix — stated because
## this change is an improvement and not a cure, and the census says which is which.
##
## Asserted through `fit`, which is what `_draw` actually calls, rather than by reading
## `_boxes` — the private is the mechanism and this is the behaviour.
func _test_each_tile_is_fit_to_its_own_sprite() -> void:
	var inner := Rect2(0.0, 0.0, 36.0, 36.0)
	var big := Rect2i(-16, -16, 33, 33)     # E317 frameset 15
	var flat := Rect2i(-1, -1, 33, 5)       # E317 frameset 17
	var shared := Rect2i(-16, -16, 48, 33)  # what the two shared before

	# THE STARVATION ITSELF, so this test fails if someone restores the shared box. What
	# makes a tile unreadable is that its LONG axis stops short of the tile: the sprite is
	# then centred small in both directions, and its short axis — already only 5px — is
	# scaled by the same shortfall.
	var was: Dictionary = Painter.fit(shared, inner)
	var was_w: float = 33.0 * float(was["scale"])
	var was_h: float = 5.0 * float(was["scale"])
	_assert_true(was_w < 0.75 * inner.size.x,
		"a shared box leaves the long axis short (%.1f of %.0f) — the sprite is centred "
		% [was_w, inner.size.x] + "small and the 5px axis goes with it (%.1fpx)" % was_h)

	var now: Dictionary = Painter.fit(flat, inner)
	var now_w: float = 33.0 * float(now["scale"])
	var now_h: float = 5.0 * float(now["scale"])
	_assert_true(absf(now_w - inner.size.x) < 0.01,
		"its own box fills the long axis (%.1f of %.0f)" % [now_w, inner.size.x])
	_assert_true(now_h > was_h,
		"…so the short axis grows with it, %.1fpx to %.1fpx" % [was_h, now_h])

	# E317 IS THE MILD CASE and its ratio is bounded by the two boxes' widths (48 vs 33,
	# so 1.45x). The corpus's bad rows are bad because the shared box is tall: E450
	# frameset 0's row shares a 48x312 box, where an ordinary 40x40 member is scaled by
	# 36/312 and lands under 5px. Asserted separately so the mild case cannot stand in for
	# the severe one — they differ by a factor of five and one number would hide it.
	var tall := Rect2i(-24, -156, 48, 312)
	var ordinary := Rect2i(0, 0, 40, 40)
	var t_was: float = 40.0 * float(Painter.fit(tall, inner)["scale"])
	var t_now: float = 40.0 * float(Painter.fit(ordinary, inner)["scale"])
	_assert_true(t_was < 6.0, "a 48x312 shared box draws a 40x40 member %.1fpx" % t_was)
	_assert_true(t_now > 6.0 * t_was,
		"…and its own box draws it %.1fpx — %.0fx" % [t_now, t_now / maxf(0.01, t_was)])

	# A TILE THAT ALREADY FILLED ITS SHARE IS UNCHANGED — the change must not rescale the
	# members that were never the problem, or every rail in the corpus moves to fix 19.2%.
	var b_now: Dictionary = Painter.fit(big, inner)
	_assert_true(absf(33.0 * float(b_now["scale"]) - 36.0) < 0.01,
		"the 33x33 member still fills its tile")

	# A DEGENERATE BOX IS SCALE ZERO, NOT A DIVIDE. Fitting per tile means `fit` now sees
	# one frameset's extent instead of a row's union, so a collapsed quad reaches it alone.
	_assert_eq(float(Painter.fit(Rect2i(0, 0, 0, 0), inner)["scale"]), 0.0,
		"a collapsed quad paints nothing rather than dividing by zero")
	_assert_eq(float(Painter.fit(big, Rect2()) ["scale"]), 0.0, "and so does a zero tile")


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
