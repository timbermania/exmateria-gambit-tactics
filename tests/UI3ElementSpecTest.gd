extends Node3D

## Guard (ADR-0088 slice 1): the UI3Element construction surface + the UI3Registry index.
##   A. Spec validation is COLLECT-ALL: every missing/mistyped criterion is reported
##      individually (via the pure validate_spec seam — the _init path push_errors + asserts).
##      Includes the per-verb cadences (ADR-0097 §2), which are required only for an element
##      that DECLARES a beat — presence and int-ness only, since the curve vocabulary is the
##      beat's and this seam is static.
##   B. authored_home defaults to the authored rect literal's position; an explicit
##      spec override wins.
##   C. rel_world/z_for reproduce the EquipPickerMenu display→world math (worked-example
##      literals from FRAME_HOME (76,135), ppu 0.04, rung·0.19 — independent of the code).
##   D. Parent = nearest registered ancestor, resolved on _enter_tree (through non-element
##      nodes); the element places ITSELF from its rect against the parent's authored home;
##      the scene tree IS the registry (roots/children_of/unregister follow the tree).

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const Fold = ExMateriaSchema.Fold

var _failed := false


func _ready() -> void:
	_test_collect_all_validation()
	_test_type_and_range_validation()
	_test_authored_home()
	_test_rel_world_math()
	_test_z_for_math()
	_test_aperture_pad_auto_provided()
	await _test_parent_resolution_and_placement()

	if _failed:
		push_error("[FAIL] UI3ElementSpecTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3ElementSpecTest")
		get_tree().quit(0)


## A. An empty spec reports EVERY required criterion (id, rect, transition, frame, clip)
## individually — not just the first gap (collect-all-then-fail, ADR-0088 §2).
func _test_collect_all_validation() -> void:
	var errors := UI3Element.validate_spec({})
	_expect(errors.size() == 5,
		"empty spec must report all 5 required criteria, got %d: %s" % [errors.size(), errors])
	for field in ["id", "rect", "transition", "frame", "clip"]:
		var found := false
		for e in errors:
			if e.contains(field):
				found = true
				break
		_expect(found, "missing-criterion error for '%s' not reported" % field)

	# ADR-0097 §2: cadence is explicit-required PER VERB — but only for an element that
	# declares a beat. An element with a beat and no cadences reports BOTH verbs...
	var no_cadence := UI3Element.validate_spec({
		"id": "picker.window",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
	})
	_expect(no_cadence.size() == 2,
		"a declared beat must require a cadence per verb, got %d: %s"
		% [no_cadence.size(), no_cadence])
	for field in ["open_cadence", "close_cadence"]:
		var named := false
		for e in no_cadence:
			if e.contains(field):
				named = true
		_expect(named, "missing-cadence error for '%s' not reported" % field)

	# ...and an element that animates NOTHING answers nothing: NONE and RIDE_PARENT name no
	# playback, so they have no verb to cadence. This is what leaves the 22 NONE/RIDE_PARENT
	# elements untouched by ADR-0097.
	for kind: int in [UI3Element.Transition.NONE, UI3Element.Transition.RIDE_PARENT]:
		var inert := UI3Element.validate_spec({
			"id": "picker.rows",
			"rect": Rect2(76, 135, 174, 101),
			"transition": kind,
			"frame": UI3Element.Frame.NONE,
			"clip": UI3Element.Clip.PARENT_APERTURE,
		})
		_expect(inert.is_empty(),
			"an element naming no beat must require no cadence (kind %d), got %s" % [kind, inert])

	# The VALUE is not this audit's business (§1 — the vocabulary is per-beat, and this
	# function is static and beat-blind). Only a non-int is refused here; an int outside the
	# beat's curve names is UI3TransitionEngine.cadence_errors()' catch.
	var wrong_typed := UI3Element.validate_spec({
		"id": "picker.window",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"open_cadence": "fast",
		"close_cadence": 99,
	})
	_expect(wrong_typed.size() == 1 and String(wrong_typed[0]).contains("open_cadence"),
		"only the non-int cadence is refused statically, got: %s" % [wrong_typed])


## A. Wrong-typed / out-of-range fields each report individually; valid fields don't.
func _test_type_and_range_validation() -> void:
	var errors := UI3Element.validate_spec({
		"id": 7,                                   # wrong type (int, not String)
		"rect": Vector2(1, 2),                     # wrong type (Vector2, not Rect2)
		"transition": "box_open",                  # wrong type (String, not enum int)
		"frame": UI3Element.Frame.STRIPE,          # valid
		"clip": 99,                                # out of enum range
	})
	_expect(errors.size() == 4,
		"expected 4 problems (id/rect/transition/clip), got %d: %s" % [errors.size(), errors])

	var ok := UI3Element.validate_spec({
		"id": "picker.window",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.STRIPE,
		"clip": UI3Element.Clip.OWN_APERTURE,
	})
	_expect(ok.is_empty(), "valid spec must produce no errors, got: %s" % [ok])

	# Optional overrides are type-checked too (authored_home must be a Vector2).
	var bad_opt := UI3Element.validate_spec({
		"id": "picker.window",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
		"authored_home": "home",
	})
	_expect(bad_opt.size() == 1, "mistyped authored_home must report 1 problem, got: %s" % [bad_opt])

	# aperture_pad (ADR-0088 amendment §4) is optional but must be a Vector4 when present.
	var bad_pad := UI3Element.validate_spec({
		"id": "picker.window",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"aperture_pad": 4.0,
	})
	_expect(bad_pad.size() == 1 and String(bad_pad[0]).contains("aperture_pad"),
		"mistyped aperture_pad must report 1 problem naming it, got: %s" % [bad_pad])
	var ok_pad := UI3Element.validate_spec({
		"id": "picker.window",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"aperture_pad": Vector4(0, 4, 0, 0),
	})
	_expect(ok_pad.is_empty(), "a Vector4 aperture_pad must validate clean, got: %s" % [ok_pad])


## B. authored_home defaults to the authored rect position (the frozen content anchor,
## NOT the live rect — the EquipPickerMenu.FRAME_HOME idiom); an explicit override wins.
func _test_authored_home() -> void:
	var elem := _valid_element("t.home", Rect2(76, 135, 174, 101))
	_expect(elem.authored_home() == Vector2(76, 135),
		"authored_home must default to the rect literal position, got %s" % elem.authored_home())
	elem.free()

	var overridden: UI3Element = UI3Element.new({
		"id": "t.home2",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
		"authored_home": Vector2(10, 20),
	})
	_expect(overridden.authored_home() == Vector2(10, 20),
		"explicit authored_home must win, got %s" % overridden.authored_home())
	overridden.free()


## C. rel_world subtracts the authored home and converts at the resolved ppu — the
## EquipPickerMenu._rel_world math. Worked example at FRAME_HOME (76,135), ppu 0.04:
## the picker name column (120, 152) lands at ((120−76)·0.04, −(152−135)·0.04) = (1.76, −0.68).
func _test_rel_world_math() -> void:
	var elem := _valid_element("t.relworld", Rect2(76, 135, 174, 101))
	var got := elem.rel_world(120.0, 152.0)
	_expect(got.is_equal_approx(Vector3(1.76, -0.68, 0.0)),
		"rel_world(120,152) at home (76,135) must be (1.76, -0.68, 0), got %s" % got)
	elem.free()


## C. z_for converts a payload render_priority to the fold-rung Z through the resolved
## depth_rung, gated on fold ownership — the EquipPickerMenu._z_for math. Worked example:
## depth_rung 34 + rp 6 = rung 40 → Z 40·0.19 = 7.6.
func _test_z_for_math() -> void:
	var elem: UI3Element = UI3Element.new({
		"id": "t.zfor",
		"rect": Rect2(0, 0, 10, 10),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
		"depth_rung": 34,
	})
	# z_for guards `is_inside_tree()` as well as `Fold.owns()`: off-tree it returns ZERO regardless of
	# the build, because a rung Z is only meaningful once criteria resolve against a mounted parent.
	# So this add_child is load-bearing for the assert below, not scene-setup politeness.
	add_child(elem)   # payload mounts after add_child — z_for's own tree precondition
	var got := elem.z_for(6)
	if Fold.owns():
		_expect(got.is_equal_approx(Vector3(0.0, 0.0, 7.6)),
			"z_for(6) at depth_rung 34 must be (0,0,7.6) when the fold owns, got %s" % got)
	else:
		_expect(got == Vector3.ZERO, "z_for must be ZERO when the fold does not own, got %s" % got)
	elem.free()


## D. Parent resolution + self-placement + the registry index.
func _test_parent_resolution_and_placement() -> void:
	var registered: Array = []
	var unregistered: Array = []
	UI3Registry.element_registered.connect(func(e: UI3Element) -> void: registered.append(e))
	UI3Registry.element_unregistered.connect(func(e: UI3Element) -> void: unregistered.append(e))

	# Top-level element: places itself at screen_to_world(rect.position) against a zero home.
	var parent := _valid_element("t.parent", Rect2(76, 135, 174, 101))
	add_child(parent)
	_expect(parent.position.is_equal_approx(Vector3(3.04, -5.4, 0.0)),
		"top-level element must sit at screen_to_world(76,135) = (3.04, -5.4, 0), got %s" % parent.position)

	# A child element under a PLAIN Node3D still resolves the ELEMENT ancestor as its parent.
	var plain := Node3D.new()
	parent.add_child(plain)
	var child := _valid_element("t.parent.header", Rect2(120, 152, 40, 16))
	plain.add_child(child)

	_expect(child.parent_element() == parent,
		"child must resolve the nearest registered ancestor through non-element nodes")
	_expect(parent.parent_element() == null, "top-level element has no parent element")

	# The child places itself from its ABSOLUTE rect against the PARENT's authored home:
	# local = screen_to_world(120−76, 152−135) = (1.76, −0.68, 0).
	_expect(child.position.is_equal_approx(Vector3(1.76, -0.68, 0.0)),
		"child element local position must be (1.76, -0.68, 0), got %s" % child.position)

	# Registry index mirrors the tree: parent is a root, child is under it.
	var roots: Array = UI3Registry.roots()
	_expect(roots.has(parent) and not roots.has(child),
		"roots() must list the parent element only")
	var kids: Array = UI3Registry.children_of(parent)
	_expect(kids.size() == 1 and kids[0] == child,
		"children_of(parent) must list exactly the child element")
	_expect(registered.has(parent) and registered.has(child),
		"element_registered must have fired for both elements")

	# Moving the parent element carries the child (nested elements ride the tree).
	var before := child.global_position
	parent.position += Vector3(1.0, 2.0, 0.0)
	_expect(child.global_position.is_equal_approx(before + Vector3(1.0, 2.0, 0.0)),
		"nested element must ride its parent element's move")

	# Unregistration follows the tree.
	child.free()
	_expect(unregistered.size() == 1, "freeing the child must unregister it")
	_expect(UI3Registry.children_of(parent).is_empty(),
		"children_of must be empty after the child left the tree")
	parent.free()
	_expect(UI3Registry.roots().is_empty() or not UI3Registry.roots().has(parent),
		"roots must drop the freed parent")


## Convention (docs/ui3-guide.md §1): every OWN_APERTURE element auto-exposes an
## aperture_pad knob — the spec is injected with a Vector4.ZERO default when it omits
## the field, so <id>.aperture_pad always exists. PARENT_APERTURE/UNCLIPPED get none.
func _test_aperture_pad_auto_provided() -> void:
	var own: UI3Element = UI3Element.new({
		"id": "t.own_aperture",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
	})
	_expect(own.spec().has("aperture_pad"),
		"OWN_APERTURE must auto-provide aperture_pad, spec keys: %s" % [own.spec().keys()])
	_expect(own.spec().get("aperture_pad") == Vector4.ZERO,
		"auto aperture_pad must default to zero, got %s" % [own.spec().get("aperture_pad")])
	_expect(own.padded_rect() == Rect2i(own.rect()),
		"a zero auto-pad must leave the aperture box == rect, got %s" % [own.padded_rect()])
	own.free()

	# An explicit non-zero pad is preserved (not clobbered by the injection).
	var authored: UI3Element = UI3Element.new({
		"id": "t.own_aperture_authored",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"aperture_pad": Vector4(0, 4, 0, 0),
	})
	_expect(authored.spec().get("aperture_pad") == Vector4(0, 4, 0, 0),
		"explicit aperture_pad must be preserved, got %s" % [authored.spec().get("aperture_pad")])
	authored.free()

	# UNCLIPPED owns no aperture — no knob injected.
	var unclipped := _valid_element("t.unclipped", Rect2(0, 0, 10, 10))
	_expect(not unclipped.spec().has("aperture_pad"),
		"UNCLIPPED must NOT get an aperture_pad knob, spec keys: %s" % [unclipped.spec().keys()])
	unclipped.free()


func _valid_element(id: String, rect: Rect2) -> UI3Element:
	return UI3Element.new({
		"id": id,
		"rect": rect,
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[UI3ElementSpecTest] %s" % msg)
