extends Node3D

## Guard (ADR-0088 slice 4a): auto-bind threading — registration feeds ADR-0068.
##   A. Literal-authored spec fields mint slugs named by element id: one COMPOSITE
##      Rect2 slug for rect, enum-hinted int binds for transition/frame/clip, plain
##      binds for beat params (the per-verb cadences). `id` and `authored_home` mint NOTHING
##      (identity + the frozen anchor are not live knobs).
##   B. The generalized R8 write-through: a rect scrub through Tune moves the origin
##      (and the aperture rides); an enum scrub lands on the criterion.
##   C. Derived placements mint NO slug: the element re-places itself when a DRIVER
##      slug is scrubbed (E3 "derive, don't duplicate").
##   D. The answer() widget path binds CLASS-scoped slugs once; instances subscribe.
##   E. criteria() reports field/value/source/slug — AUTHORED vs INHERITED vs DERIVED.

var _failed := false


func _ready() -> void:
	await _test_minted_slugs()
	await _test_write_through()
	await _test_derived_placement()
	await _test_answer_path()
	_test_criteria_read_surface()

	if _failed:
		push_error("[FAIL] UI3AutoBindTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3AutoBindTest")
		get_tree().quit(0)


func _win_spec() -> Dictionary:
	return {
		"id": "t.ab.win",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.STRIPE,
		"clip": UI3Element.Clip.OWN_APERTURE,
	}


## A. Slugs minted for literal fields only, named by element id.
func _test_minted_slugs() -> void:
	var elem: UI3Element = UI3Element.new(_win_spec())
	add_child(elem)
	await get_tree().process_frame

	_expect(Tune.is_registered("t.ab.win.rect"), "rect must mint one composite slug")
	_expect(Tune.default_of("t.ab.win.rect") == Rect2(76, 135, 174, 101),
		"the rect slug's default must be the authored literal, got %s" % [Tune.default_of("t.ab.win.rect")])
	for f in ["transition", "frame", "clip"]:
		_expect(Tune.is_registered("t.ab.win." + f), "criterion '%s' must mint a slug" % f)
		_expect(Tune.meta_of("t.ab.win." + f).has("enum"),
			"criterion '%s' must carry an enum hint (live dropdown)" % f)
	_expect(int(Tune.meta_of("t.ab.win.frame")["enum"]["STRIPE"]) == UI3Element.Frame.STRIPE,
		"the frame enum hint must map tokens to enum values")
	_expect(String(Tune.meta_of("t.ab.win.frame").get("enum_tokens", "")) == "UI3Element.Frame",
		"the enum hint must record the token prefix (materialise's enum-token reversal)")
	_expect(Tune.is_registered("t.ab.win.open_cadence"),
		"a beat-param spec field must mint an ordinary slug")
	_expect(not Tune.is_registered("t.ab.win.id"), "id must mint nothing")
	_expect(not Tune.is_registered("t.ab.win.authored_home"),
		"authored_home (the frozen anchor) must mint nothing")
	elem.free()


## B. Write-through: scrubbing the minted slugs reaches the screen.
func _test_write_through() -> void:
	var elem: UI3Element = UI3Element.new(_win_spec())
	add_child(elem)
	await get_tree().process_frame

	# A rect scrub moves ONLY the origin transform — and the settled aperture rides.
	Tune.set_value("t.ab.win.rect", Rect2(100, 150, 174, 101))
	_expect(elem.position.is_equal_approx(Vector3(4.0, -6.0, 0.0)),
		"a rect scrub must move the origin to screen_to_world(100,150) = (4.0,-6.0,0), got %s"
		% elem.position)
	_expect(elem.aperture() == Rect2i(100, 150, 174, 101),
		"the settled aperture must ride the rect scrub, got %s" % elem.aperture())
	_expect(elem.authored_home() == Vector2(76, 135),
		"the authored home must NOT ride a live scrub (frozen anchor), got %s" % elem.authored_home())

	# An enum scrub lands on the criterion.
	Tune.set_value("t.ab.win.clip", UI3Element.Clip.UNCLIPPED)
	_expect(elem.clip_mode() == UI3Element.Clip.UNCLIPPED,
		"a clip scrub must land on the criterion, got %d" % elem.clip_mode())

	Tune.clear("t.ab.win.rect")
	Tune.clear("t.ab.win.clip")
	_expect(elem.position.is_equal_approx(Vector3(3.04, -5.4, 0.0)),
		"clearing the rect override must restore the authored placement, got %s" % elem.position)
	elem.free()


## C. A derived placement mints no slug and re-places on driver scrubs.
func _test_derived_placement() -> void:
	Tune.bind("t.ab.rows.row0_y", 152.0)
	Tune.bind("t.ab.rows.pitch", 16.0)
	var row: UI3Element = UI3Element.new({
		"id": "t.ab.row1",
		"rect": UI3Element.derived(["t.ab.rows.row0_y", "t.ab.rows.pitch"],
			func() -> Rect2: return Rect2(120.0,
				float(Tune.get_value("t.ab.rows.row0_y")) + 1.0 * float(Tune.get_value("t.ab.rows.pitch")),
				40.0, 16.0)),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	add_child(row)
	await get_tree().process_frame

	_expect(not Tune.is_registered("t.ab.row1.rect"), "a derived rect must mint NO slug")
	_expect(row.rect() == Rect2(120, 168, 40, 16),
		"the derived rect must evaluate at construction (row0 + 1*pitch = 168), got %s" % row.rect())
	_expect(row.position.is_equal_approx(Vector3(4.8, -6.72, 0.0)),
		"the derived element must place itself, got %s" % row.position)

	Tune.set_value("t.ab.rows.pitch", 20.0)
	_expect(row.rect() == Rect2(120, 172, 40, 16),
		"a DRIVER scrub must re-evaluate the derived rect (row0 + 20 = 172), got %s" % row.rect())
	_expect(row.position.is_equal_approx(Vector3(4.8, -6.88, 0.0)),
		"a driver scrub must re-place the derived element, got %s" % row.position)
	Tune.clear("t.ab.rows.pitch")
	row.free()


## D. The answer() widget path: class-scoped slugs, minted once, derived rect free.
func _test_answer_path() -> void:
	var a := ProbeWidget.new()
	var b := ProbeWidget.new()
	add_child(a)
	add_child(b)
	await get_tree().process_frame

	_expect(Tune.is_registered("t.ab.probewidget.frame"),
		"answer() must bind the class-scoped slug")
	_expect(int(Tune.default_of("t.ab.probewidget.frame")) == UI3Element.Frame.MENU_TILE,
		"the class answer literal is the slug default")
	_expect(not Tune.is_registered("t.ab.probewidget.rect"),
		"a widget's derived rect must mint nothing")

	# Every instance subscribes: one scrub lands on both.
	Tune.set_value("t.ab.probewidget.frame", UI3Element.Frame.NONE)
	_expect(int(a.resolve_criterion("frame", -1)) == UI3Element.Frame.NONE
		and int(b.resolve_criterion("frame", -1)) == UI3Element.Frame.NONE,
		"a class-slug scrub must land on every instance")
	Tune.clear("t.ab.probewidget.frame")
	a.free()
	b.free()


## E. criteria(): the page's whole per-row model.
func _test_criteria_read_surface() -> void:
	var elem: UI3Element = UI3Element.new(_win_spec())
	add_child(elem)
	var rows: Array = elem.criteria()
	var by_field := {}
	for r: Dictionary in rows:
		by_field[r["field"]] = r

	_expect(by_field.has("rect") and by_field["rect"]["source"] == UI3Element.Source.AUTHORED
		and by_field["rect"]["slug"] == "t.ab.win.rect",
		"rect must report AUTHORED with its slug, got %s" % [by_field.get("rect")])
	_expect(by_field.has("ppu") and by_field["ppu"]["source"] == UI3Element.Source.INHERITED
		and is_equal_approx(float(by_field["ppu"]["value"]), 0.04)
		and by_field["ppu"]["slug"] == "",
		"non-overridden ppu must report INHERITED, resolved, no slug, got %s" % [by_field.get("ppu")])
	_expect(by_field.has("clip") and by_field["clip"]["source"] == UI3Element.Source.AUTHORED,
		"clip must report AUTHORED, got %s" % [by_field.get("clip")])
	elem.free()

	var row: UI3Element = UI3Element.new({
		"id": "t.ab.row2",
		"rect": UI3Element.derived([], func() -> Rect2: return Rect2(0, 0, 8, 8)),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	add_child(row)
	var drows: Array = row.criteria()
	for r: Dictionary in drows:
		if r["field"] == "rect":
			_expect(r["source"] == UI3Element.Source.DERIVED and r["slug"] == "",
				"a derived rect must report DERIVED with no slug, got %s" % [r])
	row.free()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[UI3AutoBindTest] %s" % msg)


## A widget-path probe: no spec at new(); criteria answered per field at class level.
class ProbeWidget:
	extends UI3Element

	func _register_criteria() -> void:
		answer("id", "t.ab.probewidget")
		answer("rect", UI3Element.derived([], func() -> Rect2: return Rect2(0, 0, 10, 10)))
		answer("transition", UI3Element.Transition.NONE)
		answer("frame", UI3Element.Frame.MENU_TILE)
		answer("clip", UI3Element.Clip.UNCLIPPED)
