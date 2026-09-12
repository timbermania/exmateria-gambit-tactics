extends Node
# test-kind: logic
# seeded-break: size the band back to the card row (`_bar_rect` -> `Rect2(0, 0, p.x + n * _pitch() ...)`) in src/ui3/TurnQueueHud.gd — arm 2's two band-origin arms red, because the band then starts at the strip anchor instead of at the screen's left edge. Seven more independent seeds, each verified to redden ONLY its own arm: `if not _leaving.is_empty(): return` -> `if false:` in `_advance_step` reds 'arm 8: the shuffle began on step N and the head's close only finished on step M' (the close barrier is the user's whole ask and nothing else can see it); `if _moving > 0: return` -> `if false:` reds 'arm 8: the entrant's aperture opened on step N and the shuffle landed on step M'; the card spec's "clip" -> `Clip.PARENT_APERTURE` reds arm 9's two clip_world arms (NOT the aperture-percentage arm — the beat still drives the element's own aperture, only the CLIP resolution moves, which is why the instrument reads the material and not the element); delete `_shown = []` from the tail of `_clear_cards` reds 'arm 11: the strip did not come back'; neutralise the redraw gate (`if key == _shown:` -> `if false:`) reds arm 4's unchanged-queue arms AND its REORDERED arm; drop `_sync_open`'s `and not _covered` term reds 'arm 11: the strip stayed up under a full-screen unit screen'; and swapping `Cadence.BACK` for `Cadence.NORMAL` in `_spawn_card`'s spec reds 'arm 8: the survivor never went past slot 0' (NOT arm 10, which is the curve's arithmetic and is blind to what the card declares). Two more for the card/face split, each verified to redden ONLY arm 2b: `_card_size` back on `_portrait_size()` reds 'a portrait_scale scrub moved the card box' (32 -> 44) — note it stays GREEN without arm 2b's forced re-derive, because `portrait_scale` drives no rect and `rect()` would hand back a cached box; and emptying `_build_bar`'s `[SCALE_SLUG, PORTRAIT_OFFSET_SLUG]` subscription list reds 'the payload subscription is missing' and 'the offset is not wired', which is the knobs-look-dead-in-F3 defect.
## Turn queue forecast HUD test (#893 design S6, redesigned under ADR-0269). No GPU,
## no director, no battle — the strip is driven through `show_entries`, its pure-view
## seam, and every animation is HAND-STEPPED through the UI3 transition engine's
## guard seam, so nothing here waits on a clock (charter clause 14).
##
## The arithmetic itself is TurnQueueTest's (closed form vs brute force, round-robin
## depth); what is guarded here is everything BETWEEN that answer and the screen,
## which is where a queue view goes wrong:
##
##   1. One card per TURN, not per unit — a fast unit appears twice in one
##      round-robin and both entries must draw. A view that keyed cards by unit
##      would silently collapse them, and the collapse reads as "that unit acts
##      once", which is the opposite of what the queue says.
##   2. Order, chrome and the BAND — the strip's left-to-right order IS the forecast's
##      order, the leftmost entry is the unit acting now, every CARD wears its own frame
##      while the bar wears none, and the band spans the whole screen rather than stopping
##      at the last portrait. The band arm is relational (against the viewport this process
##      got), never against the ~373 px one camera happens to give.
##   3. Teams are marked twice — mirrored (kept from ADR-0244 dec. 7) and coloured
##      (ADR-0269 dec. 2). The colour is the one that survives a card having no
##      neighbour to be compared against.
##   4. The redraw gate — an unchanged queue is not repainted, so a refresh on
##      every turn edge is not a rebuild of every portrait. Read through `draws()`
##      and NOT through node identity: a queue of the same LENGTH reuses its card
##      objects whether the gate fires or not, so identity alone is vacuous here.
##   5. Truncation is reported and never silent.
##   6. An empty forecast CLOSES the strip — and `visible` may only drop once that
##      close has actually finished, or the box-open animation is never seen.
##   7. Fed the REAL forecast, over rows TurnQueue itself ordered.
##   8. The DIFF (ADR-0269 dec. 6) and its ORDER — a shuffled queue must MOVE the cards it
##      already has, not rebuild them; and the head's close, the survivors' shuffle and the
##      new tail's open must happen one after another, which is read as three step indices
##      off one hand-cranked walk because "one after another" is a claim about WHEN.
##   9. The card's OWN aperture reached the real payload — both the portrait and the team
##      underlay carry the card's live `clip_world`, and both shaders DECLARE it, which are
##      two different questions and need two different instruments.
##  10. The BACK cadence overshoots, lands exactly, and did not disturb NORMAL.
##  11. The COVER gate — the strip leaves when a full-screen unit screen stands over the
##      battlefield, AND comes back when that screen does. It is NOT gated on the open turn
##      any more: the strip is up for the whole battle.

const FULL := GPUCombatPacker.TURN_METER_FULL
## Step budget for settling every live beat. The longest play here is the fade's 16
## frames; 64 is margin, and it is a COUNT, never a duration (charter clause 14).
const SETTLE_STEPS := 64

var _hud: TurnQueueHud = null
var _camera: Node3D = null
var _asserts: int = 0
var _failed: bool = false


## A stand-in for a `Unit`, carrying only what the HUD reads off one. Deliberately
## not a real Unit: the HUD's whole claim is that it needs a portrait id and
## nothing else, and a real Unit would hide a dependency this asserts is absent.
class StubUnit extends Node:
	var body_sprite_id: int = 0x80
	var template_folder: String = ""


func _ready() -> void:
	_camera = Node3D.new()
	_camera.name = "Camera"
	add_child(_camera)

	var units: Array = []
	for i in range(6):
		var unit := StubUnit.new()
		unit.name = "Stub%d" % i
		unit.body_sprite_id = 0x80 + (i % 4)
		_camera.add_child(unit)
		units.append(unit)

	_hud = TurnQueueHud.mount(_camera, null)
	_hud.bind_units(units)

	_arm_1_one_card_per_turn()
	_arm_2_order()
	_arm_3_teams_marked_twice()
	_arm_4_redraw_gate()
	_arm_5_truncation()
	_arm_6_empty_closes()
	_arm_7_real_forecast()
	_arm_8_the_diff_moves_cards()
	_arm_9_aperture_reaches_the_payload()
	_arm_10_back_cadence()
	_arm_11_cover_gate()

	# Charter clause 9: a green must be a RUN. A GDScript error aborts only its
	# enclosing function, so an arm that died halfway would otherwise print [PASS]
	# for the arms that ran and nothing at all for the ones it never reached.
	if _asserts == 0:
		print("[FAIL] Turn queue HUD: ZERO assertions ran — the test did not execute")
	elif _failed:
		print("[FAIL] Turn queue HUD test (%d assertions)" % _asserts)
	else:
		print("[PASS] Turn queue HUD: %d assertions — one card per turn, order, band span, team mark, redraw gate, truncation, close, real forecast, diff + sequencing, aperture, BACK cadence, cover gate" % _asserts)
	get_tree().quit()


# --- harness ------------------------------------------------------------------

func _check(ok: bool, msg: String) -> bool:
	_asserts += 1
	if not ok:
		print("[FAIL] %s" % msg)
		_failed = true
	return ok


## Hand-step every live transition and move play to settlement. A COUNT of engine
## frames, never a wall-clock wait — the engine's own guard seam exists for this.
func _settle() -> void:
	for _i in range(SETTLE_STEPS):
		UI3Registry.transition_engine_step()


func _entry(index: int, team: int, ticks: int) -> Dictionary:
	return {"index": index, "team": team, "ticks_from_now": ticks, "turn_meter": FULL}


## Every ShaderMaterial under one card that the clip engine has actually written `clip_world`
## on. `get_shader_parameter` returns null for a uniform nobody has set, so this counts
## materials the engine REACHED rather than materials that merely declare the uniform.
func _clipped_materials(card: UI3Element) -> Array:
	var out: Array = []
	for m: ShaderMaterial in card.payload_materials():
		if m.get_shader_parameter("clip_world") != null:
			out.append(m)
	return out


## Does `m`'s shader DECLARE `name`? Separate question from the one above, and the pair is the
## point: `set_shader_parameter` on a uniform a shader does not declare is a silent no-op that
## `get_shader_parameter` reads straight back, so "the engine wrote it" and "the shader can see
## it" have to be asked with two different instruments.
func _declares_uniform(m: ShaderMaterial, name: String) -> bool:
	if m == null or m.shader == null:
		return false
	for u: Dictionary in m.shader.get_shader_uniform_list():
		if String(u.get("name", "")) == name:
			return true
	return false


func _tint_of(card: UI3Element) -> Variant:
	var underlay := card.get_node_or_null("TeamUnderlay")
	if underlay == null or not (underlay is MeshInstance3D):
		return null
	var mat := (underlay as MeshInstance3D).material_override as ShaderMaterial
	return null if mat == null else mat.get_shader_parameter("tint")


func _portrait_of(card: UI3Element) -> UIPortrait:
	return card.get_node_or_null("Portrait") as UIPortrait


# --- 1. One card per TURN -----------------------------------------------------

func _arm_1_one_card_per_turn() -> void:
	# Unit 0 is fast enough to act three times before unit 5 acts once. The
	# forecast says so with three separate entries; the strip must draw three.
	_hud.show_entries([
		_entry(0, 0, 0), _entry(1, 1, 4), _entry(0, 0, 9),
		_entry(2, 0, 12), _entry(0, 0, 18), _entry(5, 1, 40),
	])
	_settle()
	_check(_hud.cards().size() == 6,
		"arm 1: %d cards for 6 queued turns — a repeat entry was collapsed" % _hud.cards().size())
	_check(_hud.shown_indices() == [0, 1, 0, 2, 0, 5],
		"arm 1: shown_indices = %s, expected [0, 1, 0, 2, 0, 5]" % str(_hud.shown_indices()))


# --- 2. Order -----------------------------------------------------------------

func _arm_2_order() -> void:
	_hud.show_entries([_entry(3, 0, 0), _entry(1, 1, 7), _entry(4, 0, 11)])
	_settle()
	_check(_hud.shown_indices() == [3, 1, 4],
		"arm 2: shown_indices = %s, expected [3, 1, 4]" % str(_hud.shown_indices()))
	# Left to right, strictly: the strip's x order IS the turn order, and a layout
	# that laid them out backwards would still pass the index assertion above.
	var xs: Array = []
	for card in _hud.cards():
		xs.append(card.rect().position.x)
	var ascending := true
	for i in range(1, xs.size()):
		if xs[i] <= xs[i - 1]:
			ascending = false
	_check(ascending, "arm 2: cards are not laid out left to right — x = %s" % str(xs))
	# The head sits at the strip anchor's content inset, and NOT at the band's left edge: the
	# band now starts off the left of the anchor (it spans the screen) while the row still
	# starts where the user placed it. A card measured from the band would jump a screen margin
	# left the moment the band widened, which is the one thing the widening had to not do.
	var pad_l := TurnQueueHud.pad().x
	_check(not xs.is_empty() and is_equal_approx(float(xs[0]), pad_l),
		"arm 2: the head of the strip sits at x=%s, not at the content inset %s"
			% [str(xs[0]) if not xs.is_empty() else "<none>", str(pad_l)])

	# THE BAND SPANS THE SCREEN (the user's first ask). Read off the bar element, because the
	# band is its payload and its rect IS the band's extent — and read RELATIONALLY, never
	# against 373: the width is a function of the viewport this process happens to have, and a
	# literal here would be a capture-rig constant nailed into a test.
	var band := _hud.bar().rect()
	var span := band.size.x
	var row := float(xs[xs.size() - 1]) + _hud.cards()[0].rect().size.x + TurnQueueHud.pad().z
	_check(span > row + 1.0,
		"arm 2: the band is %f px wide and the card row ends at %f — the band still stops at the last portrait"
			% [span, row])
	# It reaches the screen's LEFT edge, which is to the left of the strip's anchor, so its x0
	# is negative and proportional to where the anchor sits. This is the half that a band merely
	# made "very wide" would fail.
	var anchor_x := TurnQueueHud.screen_pos().x
	_check(band.position.x < 0.0,
		"arm 2: the band starts at x=%f — it begins at the strip anchor, not at the screen's left edge"
			% band.position.x)
	_check(is_equal_approx(band.position.x, -anchor_x * span),
		"arm 2: the band starts at x=%f; the screen's left edge is %f px left of an anchor at %f"
			% [band.position.x, anchor_x * span, anchor_x])
	# ...and it is a BAND and not a dim: still one card row tall.
	_check(is_equal_approx(band.size.y,
			TurnQueueHud.pad().y + _hud.cards()[0].rect().size.y + TurnQueueHud.pad().w),
		"arm 2: the band is %f px tall, not the card row plus its pad" % band.size.y)

	# The CHROME, which items 4 + 7 of the review inverted: each card carries its own
	# MENU_TILE frame and the bar carries none. Read off the live element rather than off the
	# spec dictionary — `_ensure_chrome` is what actually builds (or fails to build) a UIFrame,
	# and a spec naming a frame that never meshed looks identical from outside.
	for i in range(_hud.cards().size()):
		_check(_hud.cards()[i].chrome() != null,
			"arm 2: card %d wears no frame — per-card chrome never meshed" % i)
	_check(_hud.bar() != null and _hud.bar().chrome() == null,
		"arm 2: the BAR still wears a frame — the strip is framed twice over")
	# ...and the frame draws AROUND the face, not on it: the card box is the portrait grown by
	# the 9-slice's own margins. Sub-assertion of the same setup, so it rides here rather than
	# costing a second ~2.3 s process (charter clause 13).
	var m := TurnQueueHud.card_margins()
	var card_w := _hud.cards()[0].rect().size.x if not _hud.cards().is_empty() else 0.0
	# `card_scale` and NOT `portrait_scale`: the card box stopped being derived from the face.
	# Reading the face's knob here would pass today only because the two defaults are EQUAL, and
	# would go red for a false reason the first time either is dialed on its own.
	var box_w := TurnQueueHud.portrait_base().x * TurnQueueHud.card_scale()
	_check(is_equal_approx(card_w, ceilf(box_w + m.x + m.z)),
		"arm 2: a card box is %f wide, expected %f at card_scale plus the 9-slice's %f — the border draws over the portrait"
			% [card_w, box_w, m.x + m.z])
	# ...and the box is a WHOLE display pixel, so the card pitch does not drift a fraction per
	# slot and leave a stray dark column in every third gap.
	_check(is_equal_approx(card_w, floorf(card_w)),
		"arm 2: the card box is %f wide — a fractional pitch drifts the gaps" % card_w)
	_arm_2b_card_is_decoupled_from_face(card_w)


## The SPLIT itself: `portrait_scale` sizes the face, `card_scale` sizes the box, and neither
## reaches the other. Carried on arm 2's setup rather than costing its own ~2.3 s process
## (charter clause 13), and it is the one assertion that can tell the decoupled build from the
## old derived one — at rest the two produce identical geometry, so a shot cannot.
func _arm_2b_card_is_decoupled_from_face(card_w: float) -> void:
	var portrait := _hud.cards()[0].get_node_or_null("Portrait") as UIPortrait
	if not _check(portrait != null, "arm 2b: card 0 carries no Portrait to measure"):
		return
	var ppu_before := portrait.pixels_per_unit
	var pos_before := portrait.position

	# Scrub the FACE. The box must not move.
	Tune.set_value(TurnQueueHud.SCALE_SLUG, TurnQueueHud.PORTRAIT_SCALE_DEFAULT * 1.5)
	_settle()
	# ...and FORCE a re-derive before reading the box, by scrubbing a slug that really does drive
	# the card rect. Without this the read is VACUOUS: `portrait_scale` is not a driver any more,
	# so a card's rect answer is simply not re-evaluated and `rect()` hands back the cached value
	# — which passes whether or not `_card_size` still reads the face. Verified by seeding the
	# revert: `_card_size` back on `_portrait_size()` stayed GREEN until this scrub existed.
	# `spacing` moves the PITCH and never the size, so it cannot itself change what is asserted.
	Tune.set_value(TurnQueueHud.SPACING_SLUG, TurnQueueHud.SPACING_DEFAULT + 1.0)
	_settle()
	_check(is_equal_approx(_hud.cards()[0].rect().size.x, card_w),
		"arm 2b: a portrait_scale scrub moved the card box to %f from %f — the card is still derived from the face"
			% [_hud.cards()[0].rect().size.x, card_w])
	Tune.set_value(TurnQueueHud.SPACING_SLUG, TurnQueueHud.SPACING_DEFAULT)
	_settle()
	# ...and it must not be INERT either: the knob drives no rect now, so `_resize_card` is the
	# only thing that answers it. Without that subscription this knob reads as dead in F3.
	_check(portrait.pixels_per_unit > ppu_before,
		"arm 2b: portrait_scale scrubbed and the face's ppu stayed %f — the payload subscription is missing"
			% ppu_before)
	Tune.set_value(TurnQueueHud.SCALE_SLUG, TurnQueueHud.PORTRAIT_SCALE_DEFAULT)
	_settle()

	# Scrub the OFFSET. The face moves inside a box that does not.
	Tune.set_value(TurnQueueHud.PORTRAIT_OFFSET_SLUG,
		TurnQueueHud.PORTRAIT_OFFSET_DEFAULT + Vector2(3.0, 2.0))
	_settle()
	_check(not portrait.position.is_equal_approx(pos_before),
		"arm 2b: portrait_offset scrubbed and the face stayed at %v — the offset is not wired"
			% pos_before)
	_check(is_equal_approx(_hud.cards()[0].rect().size.x, card_w),
		"arm 2b: a portrait_offset scrub resized the card box — the offset must move the face, not the card")
	Tune.set_value(TurnQueueHud.PORTRAIT_OFFSET_SLUG, TurnQueueHud.PORTRAIT_OFFSET_DEFAULT)
	_settle()
	_check(portrait.position.is_equal_approx(pos_before),
		"arm 2b: the face did not return to %v when both knobs went back to their defaults" % pos_before)


# --- 3. Teams are marked twice ------------------------------------------------

func _arm_3_teams_marked_twice() -> void:
	_hud.show_entries([_entry(0, 0, 0), _entry(1, 1, 5), _entry(2, 0, 9)])
	_settle()
	var cards := _hud.cards()
	if not _check(cards.size() == 3, "arm 3: %d cards, expected 3" % cards.size()):
		return
	var want_flip := [false, true, false]
	for i in range(3):
		var portrait := _portrait_of(cards[i])
		_check(portrait != null and portrait.flipped == want_flip[i],
			"arm 3: entry %d flipped = %s, expected %s" % [
				i, "<no portrait>" if portrait == null else str(portrait.flipped),
				str(want_flip[i])])
	# The colour, which is the marking that does not need a neighbour to compare
	# against. Read off the live material, so a card built without an underlay — or
	# one whose tint was never pushed — reds here rather than looking merely dull.
	var ally: Variant = _tint_of(cards[0])
	var foe: Variant = _tint_of(cards[1])
	_check(ally != null and foe != null,
		"arm 3: a card carries no team underlay tint (ally=%s foe=%s)" % [str(ally), str(foe)])
	_check(ally != null and foe != null and ally != foe,
		"arm 3: both teams are tinted the SAME colour %s — the underlay marks nothing" % str(ally))
	_check(_tint_of(cards[2]) == ally,
		"arm 3: two team-0 cards carry different tints")


# --- 4. The redraw gate -------------------------------------------------------

func _arm_4_redraw_gate() -> void:
	_hud.show_entries([_entry(0, 0, 0), _entry(1, 1, 6)])
	_settle()
	var before := _hud.cards()
	var draws_before: int = _hud.draws()
	# The SAME queue, re-read a tick later: `ticks_from_now` moves and the order
	# does not, which is what every refresh during the between-turn stretch looks
	# like. Nothing may be rebuilt.
	_hud.show_entries([_entry(0, 0, 0), _entry(1, 1, 3)])
	var after := _hud.cards()
	if not _check(before.size() == after.size(),
			"arm 4: card count moved %d -> %d on an unchanged queue" % [before.size(), after.size()]):
		return
	var same := true
	for i in range(before.size()):
		if before[i] != after[i]:
			same = false
	_check(same, "arm 4: a card was rebuilt on an unchanged queue")
	_check(_hud.draws() == draws_before,
		"arm 4: draws %d -> %d on an unchanged queue — the gate did not fire" % [
			draws_before, _hud.draws()])
	# And a real change still redraws — the gate must not be a freeze.
	_hud.show_entries([_entry(1, 1, 0), _entry(0, 0, 6)])
	_settle()
	_check(_hud.draws() == draws_before + 1,
		"arm 4: draws %d -> %d on a REORDERED queue — the gate is a freeze" % [
			draws_before, _hud.draws()])
	_check(_hud.shown_indices() == [1, 0],
		"arm 4: the gate swallowed a REAL reorder — shown_indices = %s" % str(_hud.shown_indices()))


# --- 5. Truncation ------------------------------------------------------------

func _arm_5_truncation() -> void:
	# The cap is `turnqueue.max_cards` now, not an @export — a display policy the player scrubs
	# (ADR-0269 dec. 9). Driven through Tune rather than through a property, because that is the
	# only door the running game has and a test that used a second one would not exercise it.
	Tune.set_value(TurnQueueHud.MAX_CARDS_SLUG, 4)
	var entries: Array = []
	for i in range(9):
		entries.append(_entry(i % 6, i % 2, i * 3))
	_hud.show_entries(entries)
	_settle()
	_check(_hud.cards().size() == 4,
		"arm 5: %d cards drawn for a 9-deep queue capped at 4" % _hud.cards().size())
	_check(_hud.shown_indices().size() == 4,
		"arm 5: shown_indices reports %d entries, expected 4" % _hud.shown_indices().size())
	# ...and the cap is LIVE: raising it re-runs the last forecast through the new number rather
	# than waiting for the next turn edge, which is what makes it a knob and not a boot setting.
	Tune.set_value(TurnQueueHud.MAX_CARDS_SLUG, 7)
	_settle()
	_check(_hud.cards().size() == 7,
		"arm 5: %d cards after raising max_cards to 7 — the scrub did not reach the strip"
			% _hud.cards().size())
	Tune.set_value(TurnQueueHud.MAX_CARDS_SLUG, TurnQueueHud.MAX_CARDS_DEFAULT)


# --- 6. An empty forecast closes the strip ------------------------------------

func _arm_6_empty_closes() -> void:
	_hud.show_entries([_entry(0, 0, 0)])
	_settle()
	_check(_hud.visible, "arm 6: the strip is hidden with a turn queued")
	_check(_hud.is_showing(), "arm 6: the strip does not consider itself shown with a turn queued")

	_hud.show_entries([])
	# The INTENT drops immediately; the pixels do not. `visible` staying true through
	# the close is the whole point — dropping it here would mean the box-open close is
	# animating something nobody can see, which is how the animation silently dies.
	_check(not _hud.is_showing(), "arm 6: the strip still wants to be shown with no turn queued")
	_check(_hud.cards().is_empty(),
		"arm 6: %d cards left over from the previous queue" % _hud.cards().size())
	_settle()
	_check(not _hud.visible,
		"arm 6: the strip is still visible after its close settled (deployment draws an empty strip)")


# --- 7. The real forecast -----------------------------------------------------
#
# The seam this widget rests on is `TurnQueue.forecast` -> strip. Fabricated entries
# in the arms above cannot catch a HUD that reads the wrong key off a real row, so
# this one hands it the module's own output.

func _arm_7_real_forecast() -> void:
	var rows := [
		{"index": 0, "team": 0, "speed": 10, "turn_meter": FULL, "alive": true},
		{"index": 1, "team": 1, "speed": 5, "turn_meter": 0, "alive": true},
		{"index": 2, "team": 0, "speed": 5, "turn_meter": 0, "alive": true},
		{"index": 3, "team": 1, "speed": 5, "turn_meter": 0, "alive": false},
	]
	var forecast: Array = TurnQueue.forecast(rows)
	_hud.show_entries(forecast)
	_settle()

	if not _check(not forecast.is_empty(), "arm 7: the forecast is empty over three living units"):
		return
	var want: Array = []
	for entry in forecast:
		want.append(int(entry["index"]))
	_check(_hud.shown_indices() == want,
		"arm 7: strip = %s, forecast = %s" % [str(_hud.shown_indices()), str(want)])
	_check(int(forecast[0]["index"]) == 0,
		"arm 7: the unit already at FULL is not at the head of the queue")
	_check(not _hud.shown_indices().has(3), "arm 7: a dead unit is drawn in the queue")


# --- 8. The diff MOVES cards, and the three verbs are SERIALISED --------------
#
# The head takes its turn and drops off the back; everyone shuffles one slot left and
# one new turn appears at the tail. That is the ONLY thing this widget ever does
# between two turns, and before ADR-0269 it was a wholesale rebuild — which is why
# nothing could animate. A destroyed-and-recreated card has no identity to carry a
# motion, so this arm is the load-bearing one for steps 4, 5 and 6 together.
#
# It is also where the ORDER is guarded. The user asked for the three verbs to happen one
# after another — close, then shuffle, then open — and the whole of that claim is about
# WHEN, so it is read as three step INDICES off one hand-cranked walk rather than as three
# separate settled states. A build that plays all three at once passes every identity
# assertion above and every endpoint assertion below; only the indices can see it.

func _arm_8_the_diff_moves_cards() -> void:
	_hud.show_entries([_entry(0, 0, 0), _entry(1, 1, 5), _entry(2, 0, 9), _entry(3, 1, 14)])
	_settle()
	var before := _hud.cards()
	if not _check(before.size() == 4, "arm 8: %d cards, expected 4" % before.size()):
		return
	var head := before[0]
	var slot0 := TurnQueueHud.pad().x
	var slot1 := before[1].rect().position.x

	_hud.show_entries([_entry(1, 1, 0), _entry(2, 0, 4), _entry(3, 1, 9), _entry(4, 0, 15)])
	var after := _hud.cards()
	if not _check(after.size() == 4, "arm 8: %d cards after the shuffle, expected 4" % after.size()):
		return
	# The three survivors are the SAME OBJECTS, one slot left.
	for i in range(3):
		_check(after[i] == before[i + 1],
			"arm 8: slot %d holds a NEW card — the queue was rebuilt, not diffed" % i)
	_check(after[3] != head, "arm 8: the retired head card was recycled into the tail slot")
	_check(not after.has(head), "arm 8: the head card is still in the queue after its turn")

	# The DIFF is immediate and the PLAYS are not. Before a single engine step: the survivor
	# is still standing on its old slot, and the entrant already exists at its real slot with
	# a SHUT aperture. Deferring the diff instead of the plays would fail here.
	_check(is_equal_approx(after[0].rect().position.x, slot1),
		"arm 8: the survivor left slot 1 (x=%f) in the same pass as the head's close — the shuffle did not wait"
			% after[0].rect().position.x)
	_check(after[3].aperture().size.x < int(after[3].rect().size.x),
		"arm 8: the entrant is already apertured open (%d of %d px) before the head has closed"
			% [after[3].aperture().size.x, int(after[3].rect().size.x)])

	# One hand-cranked walk, three first-times recorded off it. A COUNT of engine frames and
	# never a duration (charter clause 14).
	var closed_at := -1
	var moved_at := -1
	var landed_at := -1
	var opened_at := -1
	var lowest := after[0].rect().position.x
	for f in range(SETTLE_STEPS * 3):
		if closed_at < 0 and is_instance_valid(head) and head.is_settled():
			closed_at = f
		if moved_at < 0 and absf(after[0].rect().position.x - slot1) > 0.001:
			moved_at = f
		if landed_at < 0 and moved_at >= 0 and after[0].is_move_settled():
			landed_at = f
		if opened_at < 0 and after[3].aperture().size.x > 0:
			opened_at = f
		lowest = minf(lowest, after[0].rect().position.x)
		UI3Registry.transition_engine_step()

	_check(closed_at >= 0, "arm 8: the head card never finished its close")
	_check(moved_at >= closed_at,
		"arm 8: the shuffle began on step %d and the head's close only finished on step %d — the two overlap"
			% [moved_at, closed_at])
	_check(landed_at >= 0 and opened_at >= landed_at,
		"arm 8: the entrant's aperture opened on step %d and the shuffle landed on step %d — the tail did not wait"
			% [opened_at, landed_at])

	# The CARD's declared cadence, rather than the curve's arithmetic (arm 10 does that, and a
	# card authored `NORMAL` would sail straight past it): the survivor travels LEFT, so a BACK
	# cadence must carry it PAST slot 0 and pull it back. A monotone cadence never crosses its
	# destination at all.
	_check(lowest < slot0 - 0.001,
		"arm 8: the survivor never went past slot 0 (lowest x=%f, slot %f) — the card's move cadence is monotone, not BACK"
			% [lowest, slot0])
	_check(after[0].is_move_settled(), "arm 8: the slide never settled")
	_check(is_equal_approx(after[0].rect().position.x, slot0),
		"arm 8: the survivor landed at x=%f, not on slot 0 (%f) — an overshoot that does not land" % [
			after[0].rect().position.x, slot0])
	# ...and the entrance actually finished: a box that opens to less than the card is a
	# permanently cropped portrait, which reads as a rendering bug rather than as an animation.
	_check(after[3].aperture().size.x == int(after[3].rect().size.x),
		"arm 8: the entrant settled at %d of its %d px — its aperture never opened fully"
			% [after[3].aperture().size.x, int(after[3].rect().size.x)])


# --- 9. The card's OWN aperture reached the real payload ----------------------
#
# A card enters and leaves by scissoring itself, so `BOX_OPEN` drives the CARD's aperture and
# the clip engine pushes that aperture to every material under it. Both of them have to get it:
# the portrait carries the face and the underlay carries the team colour, and a card that
# apertured only one of them would leave a coloured block standing where its head used to be.
#
# This replaces the FADE arm that stood here until the entrance became an aperture. It is the
# same claim about the same seam — "the beat reached the real payload, not just the element" —
# asked of the uniform that now carries it. The `_declares_uniform` half is the part the fade
# arm could only claim: a `set_shader_parameter` for a uniform the shader dropped is silent, and
# reading the value back cannot tell you, because Godot hands you what you wrote.

func _arm_9_aperture_reaches_the_payload() -> void:
	# A torn-down strip and a fresh one, so BOTH cards are entrants with a play of their own —
	# a diff against whatever the previous arm left would make one of them a survivor, and a
	# survivor is already open.
	_hud.show_entries([])
	_settle()
	_hud.show_entries([_entry(0, 0, 0), _entry(1, 1, 5)])
	var cards := _hud.cards()
	if not _check(cards.size() == 2, "arm 9: %d cards, expected 2" % cards.size()):
		return
	var clipped := _clipped_materials(cards[0])
	_check(clipped.size() >= 2,
		"arm 9: the clip engine reached %d of the card's materials, expected the portrait AND the underlay"
			% clipped.size())
	for m: ShaderMaterial in clipped:
		_check(_declares_uniform(m, "clip_world") and _declares_uniform(m, "clip_basis_inv"),
			"arm 9: a card material's shader does not declare clip_world/clip_basis_inv — the push is a silent no-op")

	# THE BAND OPENS FIRST, and every card is still SHUT while its scissor sweeps the screen.
	# Played together they would not line up: the band's box is the screen and a card's is 32 px,
	# so the outermost cards finish opening long before the band reaches them and stand on the
	# bare battlefield in the meantime. Looked at, and it reads as a glitch rather than a reveal.
	var band := _hud.bar()
	_check(band.aperture().size.x > 0 and not band.is_settled(),
		"arm 9: the band is not part-way through its own box-open (%d px, settled=%s)"
			% [band.aperture().size.x, str(band.is_settled())])
	_check(cards[0].aperture().size.x == 0,
		"arm 9: a card is %d px open while the band is still sweeping — the two plays overlap"
			% cards[0].aperture().size.x)
	var band_settled_at := -1
	for f in range(SETTLE_STEPS):
		if band.is_settled():
			band_settled_at = f
			break
		UI3Registry.transition_engine_step()
	if not _check(band_settled_at >= 0, "arm 9: the band never finished opening"):
		return

	# The step that settled the band emitted `opened`, which is what releases the cards — and
	# `play()` drives frame 0 SYNCHRONOUSLY, so by now a card is 10% of the way through its own
	# scissor (UI3BoxOpenBeat's NORMAL curve) rather than either shut or whole.
	var full := int(cards[0].rect().size.x)
	var mid := cards[0].aperture().size.x
	_check(mid > 0 and mid < full,
		"arm 9: a freshly-opened card's aperture is %d of %d px — it is not part-way through its box-open"
			% [mid, full])
	# ...and the engine pushed THAT aperture, not a stale or default one. This is the assertion
	# the fade arm's `0 < fade < 1` was: proof the payload is riding the live beat.
	var want := UI3ClipEngine.clip_world(cards[0].aperture(), cards[0].ppu())
	var mid_ok := true
	for m: ShaderMaterial in clipped:
		if not Vector4(m.get_shader_parameter("clip_world")).is_equal_approx(want):
			mid_ok = false
	_check(mid_ok, "arm 9: a card material carries a clip_world that is not its element's live aperture")

	_settle()
	_check(cards[0].aperture().size == Vector2i(cards[0].rect().size.ceil()),
		"arm 9: a settled card's aperture is %s, not its whole rect %s — the box never finished opening"
			% [str(cards[0].aperture().size), str(cards[0].rect().size)])
	var settled := UI3ClipEngine.clip_world(cards[0].aperture(), cards[0].ppu())
	var settled_ok := true
	for m: ShaderMaterial in _clipped_materials(cards[0]):
		if not Vector4(m.get_shader_parameter("clip_world")).is_equal_approx(settled):
			settled_ok = false
	_check(settled_ok, "arm 9: a settled card's payload kept a mid-open clip box")

	# The FADE beat's own endpoints. `Transition.FADE` has no consumer left in this package —
	# ADR-0269 keeps the enum member (its int is persisted in Tune overrides and authored in
	# specs, so it may only ever be APPENDED) and keeps `UI3FadeBeat` registered against it,
	# because an enum answer that resolves to no beat would silently SNAP instead of erroring.
	# These two lines are what is left guarding that beat, and they ride here because they are
	# arithmetic and cost this process nothing (charter clause 13).
	_check(is_equal_approx(UI3FadeBeat.fade_at_frame(-1), 0.0),
		"arm 9: the fade beat's shut state is not fully transparent")
	_check(is_equal_approx(
		UI3FadeBeat.fade_at_frame(UI3FadeBeat.settle_for(UI3FadeBeat.Cadence.NORMAL)), 1.0),
		"arm 9: the fade beat's settle frame is not fully opaque")


# --- 10. The BACK cadence -----------------------------------------------------

func _arm_10_back_cadence() -> void:
	var total := UI3MoveSlideBeat.back_frames()
	_check(UI3MoveSlideBeat.settle_for(UI3MoveSlideBeat.Cadence.BACK) == total,
		"arm 10: BACK's settle frame is not its curve length")
	# Both endpoints pixel-exact — an overshoot curve that does not LAND is a card
	# that comes to rest a fraction of a pixel off its slot, forever.
	_check(is_equal_approx(UI3MoveSlideBeat.back_fraction_at_frame(0), 0.0),
		"arm 10: BACK does not start at the journey's origin")
	_check(is_equal_approx(UI3MoveSlideBeat.back_fraction_at_frame(total), 1.0),
		"arm 10: BACK does not land exactly on its destination")
	var peak := 0.0
	for f in range(1, total):
		peak = maxf(peak, UI3MoveSlideBeat.back_fraction_at_frame(f))
	_check(peak > 1.0, "arm 10: BACK never goes past its mark — peak %f, it is not an overshoot" % peak)
	# And it overshoots ENOUGH. The formation hover's s = 0.7 peaks at +1.76%, which on
	# this widget's ~25 px card pitch is 0.45 px — sub-pixel, i.e. indistinguishable
	# from NORMAL at the one place the cadence was added for.
	_check(peak > 1.05,
		"arm 10: BACK peaks at only +%.2f%% — sub-pixel on a card pitch, inherit-the-hover territory"
			% ((peak - 1.0) * 100.0))
	# NORMAL is untouched: still the monotone §15.1 table, still never past its mark.
	var monotone := true
	var prev := -1.0
	for f in range(0, VitalsSlideAnimator.settle_frame() + 1):
		var v := UI3MoveSlideBeat.fraction_at_frame(f)
		if v < prev or v > 1.0:
			monotone = false
		prev = v
	_check(monotone, "arm 10: adding BACK disturbed the NORMAL cadence's ROM curve")
	_check(is_equal_approx(
		UI3MoveSlideBeat.fraction_at_frame(VitalsSlideAnimator.settle_frame()), 1.0),
		"arm 10: NORMAL no longer lands on its destination")


# --- 11. The cover gate -------------------------------------------------------
#
# ADR-0269's first build gated the strip on the open TURN, on ADR-0260's measurement that a
# Gariland battle stops 8 times. Seen on screen, the reading inverted: what the player wants
# between the stops is who is coming. The strip is now up for the whole battle, and the only
# thing that takes it away is a screen standing over the battlefield it annotates.
#
# Run LAST: it is the only arm that moves the gates.

func _arm_11_cover_gate() -> void:
	_hud.show_entries([_entry(0, 0, 0), _entry(1, 1, 5)])
	_settle()
	_check(_hud.is_showing(), "arm 11: the strip is not shown during a live battle")

	# The turn EDGES no longer gate it — this is the assertion that pins the reversal, because
	# a strip that still hid on `resumed` would pass every other arm here.
	_hud.show_entries([_entry(0, 0, 0), _entry(1, 1, 4)])
	_settle()
	_check(_hud.is_showing(),
		"arm 11: the strip left between turns — it is gated on the open turn, not on the battle")

	_hud.set_covered(true)
	_check(not _hud.is_showing(),
		"arm 11: the strip stayed up under a full-screen unit screen")
	_settle()
	_check(not _hud.visible, "arm 11: the strip is still drawn under a full-screen unit screen")
	_check(_hud.cards().is_empty(), "arm 11: the strip kept its cards while off screen")

	# ...and it COMES BACK, over the very same queue. The redraw gate compares the
	# QUEUE, but what it has to answer is "is what I drew still on screen" — after a
	# teardown the answer is no, and a gate that forgets this opens an empty band.
	_hud.set_covered(false)
	_hud.show_entries([_entry(0, 0, 0), _entry(1, 1, 5)])
	_settle()
	_check(_hud.cards().size() == 2,
		"arm 11: the strip did not come back — %d cards over an unchanged queue" % _hud.cards().size())
	_check(_hud.is_showing(), "arm 11: the strip did not re-open when the screen closed")
	_check(_hud.visible, "arm 11: the strip re-opened but was never made visible")

	# The BATTLE gate, the other half of the lifecycle: the battle ending takes the strip with
	# it, whatever the queue still says.
	_hud.set_battle_live(false)
	_check(not _hud.is_showing(), "arm 11: the strip stayed up after the battle ended")
	_settle()
	_check(not _hud.visible, "arm 11: the strip is still drawn after the battle ended")
	_hud.set_battle_live(true)
