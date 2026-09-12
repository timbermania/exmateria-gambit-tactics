extends Node3D

## Guard (ADR-0088 Amendment 2): key locations — named alternative placements.
##   A. `UI3Element.at(location_slug)` is the third rect answer form: a DerivedRect
##      whose single driver is the location slug and whose eval reads the location's
##      LIVE value through Tune. Mints NO `<id>.rect` slug; scrubbing the location
##      re-places the element (origin move + settled aperture rides); the authored
##      home stays frozen (content-anchor semantics — "move the frame, content rides").
##   B. `place_at(location_slug)` re-homes a live element to another location's live
##      value (the WHERE verb, sibling of open()/close()): rect follows the NEW
##      location, the aperture re-derives, scrubbing the NEW location moves the
##      element, and scrubbing the OLD location no longer displaces it (the stale
##      driver-subscription hazard) — repeated re-homing must not fight itself.

var _failed := false


func _ready() -> void:
	await _test_at_answers_with_live_location()
	await _test_place_at_rehomes()

	if _failed:
		push_error("[FAIL] UI3KeyLocationTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3KeyLocationTest")
		get_tree().quit(0)


## A. at(): rect answered by reference to a location, live through the driver machinery.
func _test_at_answers_with_live_location() -> void:
	Tune.bind("t.kl.loc.a", Rect2(40, 60, 80, 32), {"step": 1.0})
	var elem: UI3Element = UI3Element.new({
		"id": "t.kl.win",
		"rect": UI3Element.at("t.kl.loc.a"),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
	})
	add_child(elem)
	await get_tree().process_frame

	_expect(elem.rect() == Rect2(40, 60, 80, 32),
		"at() must answer with the location's live value, got %s" % elem.rect())
	_expect(not Tune.is_registered("t.kl.win.rect"),
		"an at-location rect is a derived placement — it must mint NO <id>.rect slug")
	_expect(elem.position.is_equal_approx(Vector3(1.6, -2.4, 0.0)),
		"the element must place itself at the location, got %s" % elem.position)

	# Scrubbing the LOCATION re-places every element that answers with it.
	Tune.set_value("t.kl.loc.a", Rect2(50, 70, 80, 32))
	_expect(elem.rect() == Rect2(50, 70, 80, 32),
		"a location scrub must re-evaluate the at() rect, got %s" % elem.rect())
	_expect(elem.position.is_equal_approx(Vector3(2.0, -2.8, 0.0)),
		"a location scrub must move the origin, got %s" % elem.position)
	_expect(elem.aperture() == Rect2i(50, 70, 80, 32),
		"the settled aperture must ride the location scrub, got %s" % elem.aperture())
	_expect(elem.authored_home() == Vector2(40, 60),
		"the authored home must stay frozen across a location scrub (content anchor), got %s"
		% elem.authored_home())

	Tune.clear("t.kl.loc.a")
	_expect(elem.rect() == Rect2(40, 60, 80, 32),
		"clearing the location override must restore the authored placement, got %s" % elem.rect())
	elem.free()


## B. place_at(): the orchestrator-invoked WHERE verb.
func _test_place_at_rehomes() -> void:
	Tune.bind("t.kl.loc.b", Rect2(120, 60, 80, 32), {"step": 1.0})
	var elem: UI3Element = UI3Element.new({
		"id": "t.kl.win2",
		"rect": UI3Element.at("t.kl.loc.a"),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
	})
	add_child(elem)
	await get_tree().process_frame

	elem.place_at("t.kl.loc.b")
	_expect(elem.rect() == Rect2(120, 60, 80, 32),
		"place_at(B) must re-drive the rect to location B's live value, got %s" % elem.rect())
	_expect(elem.position.is_equal_approx(Vector3(4.8, -2.4, 0.0)),
		"place_at(B) must move the origin, got %s" % elem.position)
	_expect(elem.aperture() == Rect2i(120, 60, 80, 32),
		"place_at(B) must re-derive the settled aperture, got %s" % elem.aperture())
	_expect(elem.authored_home() == Vector2(40, 60),
		"place_at must NOT touch the authored home (content rides the re-home), got %s"
		% elem.authored_home())

	# The NEW location is live: scrubbing B moves the element.
	Tune.set_value("t.kl.loc.b", Rect2(130, 65, 80, 32))
	_expect(elem.rect() == Rect2(130, 65, 80, 32),
		"after place_at(B), scrubbing B must re-place the element, got %s" % elem.rect())

	# The OLD location is inert: scrubbing A must not displace the element off B.
	Tune.set_value("t.kl.loc.a", Rect2(10, 10, 80, 32))
	_expect(elem.rect() == Rect2(130, 65, 80, 32),
		"after place_at(B), scrubbing the OLD location A must not displace the element, got %s"
		% elem.rect())

	# Re-homing back and forth must not fight itself (subscriptions dedup, answers swap).
	elem.place_at("t.kl.loc.a")
	_expect(elem.rect() == Rect2(10, 10, 80, 32),
		"place_at back to A must follow A's LIVE (scrubbed) value, got %s" % elem.rect())
	elem.place_at("t.kl.loc.b")
	_expect(elem.rect() == Rect2(130, 65, 80, 32),
		"a second place_at(B) must land back on B's live value, got %s" % elem.rect())

	Tune.clear("t.kl.loc.a")
	_expect(elem.rect() == Rect2(130, 65, 80, 32),
		"clearing the INACTIVE location A must not move an element homed at B, got %s" % elem.rect())
	Tune.clear("t.kl.loc.b")
	_expect(elem.rect() == Rect2(120, 60, 80, 32),
		"clearing B must restore B's authored home value, got %s" % elem.rect())
	elem.free()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[UI3KeyLocationTest] %s" % msg)
