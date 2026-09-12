extends Node3D
## Acceptance guard (headful, end to end): ctrl-click a color on the ownership map in the GAME
## window and the debug page — which lives in a DIFFERENT OS-level Window — unfolds and scrolls
## to that element's row.
##
## This is the guard that pins the assumption the whole design rests on, and which the unit
## guard (UI3OwnerPickTest, pure color math) cannot reach: THE FINAL FRAMEBUFFER PIXEL REALLY
## DOES CARRY THE OWNER COLOR. The compositor engine-fold is active on every scene and sRGB
## conversion happens on readback, so "the shader writes owner_color" does not by itself mean
## "the pixel reads back as owner_color". Here it is measured against the real formation/detail
## scene, through the real camera, and the picked id must come back equal to the element whose
## color was sampled.
##
## Deliberately driven through the REAL scene tree (assets/scenes/FormationDetailTransition.tscn)
## rather than a bare Node3D: the camera lives in the .tscn, not the script, so a hand-built
## host renders nothing and every pixel reads back the same flat grey.
##
## The page is mounted in a genuine shown Window, because a HIDDEN Window does not lay out to
## full width — a page measured while hidden reads a fraction of its real size, and the scroll
## assertions below would be measuring the wrong geometry.
##
## Run: <GODOT> --path . --quit-after 400 res://tests/UI3OwnerPickAcceptanceTest.tscn

const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

var _passed := 0
var _failed := 0
var _view: UI3RegistryView = null
var _win: Window = null


func _action(n: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = n
	e.pressed = true
	return e


func _ready() -> void:
	# ADR-0181: the host reads `CharacterCatalog.owned_units()` and seeds nothing, so this rig
	# states its own fixture. It drives `FormationDetailTransition.tscn`, which is the bare
	# coordinator — the seeding boot lives in `FormationDev.tscn` and is not on this path.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	# --- the real screen, with its camera + compositor ---------------------------
	var host = preload("res://assets/scenes/FormationDetailTransition.tscn").instantiate()
	add_child(host)
	for _i in 6:
		await get_tree().process_frame
	var form = host._formation
	if form == null or form.selected_character() == null:
		_fail("no formation selection — the scene did not boot")
		_finish()
		return
	form._unhandled_input(_action("ui_accept"))
	host.open_action_menu()
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	for _i in 4:
		await get_tree().process_frame

	# --- the page, in its own shown Window (as production mounts it) --------------
	_win = Window.new()
	_win.size = Vector2i(1241, 900)
	add_child(_win)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win.add_child(scroll)
	_view = UI3RegistryView.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_view)
	_win.show()
	for _i in 4:
		await get_tree().process_frame
	_view.rebuild()
	await get_tree().process_frame

	await _test_picker_lifetime_follows_the_map()
	await _test_a_sampled_pixel_names_its_own_element()
	await _test_reveal_unfolds_ancestors_and_scrolls()
	await _test_a_miss_reveals_nothing()
	await _test_a_pick_isolates_what_you_clicked()
	_finish()


## The picker listens on the GAME window only while the map is on. Off-map it must not exist:
## the map is what makes the framebuffer a false-color ID buffer, and nothing should be eating
## ctrl-clicks on a normally-rendered game.
func _test_picker_lifetime_follows_the_map() -> void:
	_expect(_view.map_picker() == null, "no map, no picker — one existed before the map was on")
	_view._on_map_toggled(true)
	await get_tree().process_frame
	var picker := _view.map_picker()
	_expect(picker != null, "turning the map on must attach a picker")
	if picker == null:
		return
	_expect(picker.get_parent() == get_tree().root,
		"the picker must live in the MAIN window's tree (the page's Window never sees game clicks), parent was %s"
			% picker.get_parent())
	_view._on_map_toggled(false)
	await get_tree().process_frame
	_expect(_view.map_picker() == null, "turning the map off must remove the picker")


## The round trip: sample the framebuffer, find a pixel wearing a known element's owner color,
## and ctrl-pick that spot. The id that comes back must be that element.
func _test_a_sampled_pixel_names_its_own_element() -> void:
	_view._on_map_toggled(true)
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var picker := _view.map_picker()
	if picker == null:
		_fail("no picker to sample with")
		return

	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.get_width() == 0:
		_fail("could not read the framebuffer")
		return

	# Which owner colors are actually DRAWN? Elements the detail overlay occludes are legitimately
	# absent — you cannot click what is not on screen — so the test samples what is visible.
	var registry := get_node_or_null("/root/UI3Registry")
	var found: Dictionary = {}      # element id -> a framebuffer pixel wearing its color
	for e: UI3Element in registry.elements():
		found[e.id()] = Vector2i(-1, -1)
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var id: String = UI3OwnerColorMap.resolve_owner(
				_map_colors(), img.get_pixel(x, y))
			if id != "" and found.get(id, Vector2i(-1, -1)) == Vector2i(-1, -1):
				found[id] = Vector2i(x, y)

	var visible_ids: Array = []
	for id: String in found.keys():
		if found[id] != Vector2i(-1, -1):
			visible_ids.append(id)
	_expect(visible_ids.size() >= 3,
		("at least a few registered elements must be visibly wearing their owner color — "
		+ "found %d of %d. If this is 0 the framebuffer no longer carries the map, and the "
		+ "whole pick design is void.") % [visible_ids.size(), found.size()])

	# Every visible element must name ITSELF when picked at its own pixel.
	var rect := get_viewport().get_visible_rect().size
	var wrong: Array = []
	for id: String in visible_ids:
		var px: Vector2i = found[id]
		# framebuffer px -> window space (they need not be the same size)
		var wpos := Vector2(
			(float(px.x) + 0.5) * rect.x / float(img.get_width()),
			(float(px.y) + 0.5) * rect.y / float(img.get_height()))
		var got: String = picker.pick_at(wpos)
		if got != id:
			wrong.append("%s -> '%s'" % [id, got])
	_expect(wrong.is_empty(),
		"every visible element must resolve to ITSELF at its own pixel; mismatches: %s" % [wrong])
	# Say what was actually exercised — a guard whose coverage is invisible can rot into a
	# vacuous pass (0 visible elements would sail through every per-element loop below).
	print("[info] %d/%d registered elements were drawn and round-tripped pixel -> id: %s"
		% [visible_ids.size(), found.size(), visible_ids])


## Arriving at a row is only useful if you can see it: a nested element's box lives inside its
## parent's fold content, so a folded ancestor leaves nothing to scroll to.
func _test_reveal_unfolds_ancestors_and_scrolls() -> void:
	var registry := get_node_or_null("/root/UI3Registry")
	# Find a NESTED element (one with an ancestor) — the case folds can hide.
	var nested := ""
	var parent_id := ""
	for root: UI3Element in registry.roots():
		for child: UI3Element in registry.children_of(root):
			nested = child.id()
			parent_id = root.id()
			break
		if nested != "":
			break
	if nested == "":
		print("[skip] no nested element registered — ancestor unfolding not exercised")
		_passed += 1
		return

	# Fold everything shut first, so the reveal has real work to do.
	_view._on_fold_all()
	await get_tree().process_frame
	var parent_toggle: Button = _view.fold_toggle(parent_id)
	_expect(parent_toggle != null and not parent_toggle.button_pressed,
		"fold-all should have shut the parent (%s) before the reveal" % parent_id)

	var ok: bool = _view.reveal_element(nested)
	_expect(ok, "reveal_element(%s) must find a rendered row" % nested)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_view.last_revealed() == nested,
		"the page must report %s as last revealed, got '%s'" % [nested, _view.last_revealed()])

	var box: Control = _view.element_box(nested)
	_expect(box != null and box.is_visible_in_tree(),
		"the revealed row must actually be visible — a folded ancestor was left shut")
	_expect(box != null and box.size.y > 0.0,
		"the revealed row must have laid out (height 0 means an ancestor is still folded)")
	_expect(_view.reveal_flash() != null,
		"the revealed row must be flashed so the eye can find where the scroll landed")
	_expect(parent_toggle != null and parent_toggle.button_pressed,
		"the reveal must have UNFOLDED the ancestor (%s) that was hiding the row" % parent_id)


## A pick on nothing must navigate nowhere — the previous reveal must not be disturbed, and no
## row may be silently snapped to. This is the assertion that keeps this from being a
## nearest-color match.
func _test_a_miss_reveals_nothing() -> void:
	var picker := _view.map_picker()
	if picker == null:
		_fail("no picker for the miss check")
		return
	var before := _view.last_revealed()
	var got: String = picker.resolve(Color8(76, 76, 76))   # the empty-screen grey
	_expect(got == "", "a color no element wears must resolve to nothing, got '%s'" % got)
	_expect(picker.last_pick().get("reason", "") == "no_owner",
		"a miss on nothing must report 'no_owner', got '%s'" % picker.last_pick().get("reason", ""))
	_expect(_view.last_revealed() == before,
		"a missed pick must not move the page (was '%s', now '%s')" % [before, _view.last_revealed()])

	# ...and the reserved ALARM color is a DIFFERENT answer: real UI payload nobody owns.
	var alarm: String = picker.resolve(UI3OwnerColors.ALARM)
	_expect(alarm == "", "ALARM must never resolve to an owner, got '%s'" % alarm)
	_expect(picker.last_pick().get("reason", "") == "unowned",
		"an ALARM pick must report 'unowned' (an orphan finding), got '%s'"
			% picker.last_pick().get("reason", ""))


## A pick ISOLATES its target: everything folds shut first, then only the chain down to the
## clicked element re-opens. On a page of 18 elements the alternative is arriving at a row
## surrounded by every other element's expanded criteria, which is the state the click was
## meant to cut through — the point of clicking a colour is "show me THIS one".
func _test_a_pick_isolates_what_you_clicked() -> void:
	var registry := get_node_or_null("/root/UI3Registry")
	# Pick a NESTED target, so the chain that must stay open is more than just the target.
	var target := ""
	var chain: Array = []
	for root: UI3Element in registry.roots():
		for child: UI3Element in registry.children_of(root):
			target = child.id()
			chain = [root.id(), child.id()]
			break
		if target != "":
			break
	if target == "":
		print("[skip] no nested element registered — isolation not exercised")
		_passed += 1
		return

	# Start from the WORST case: everything expanded, so isolation has real work to do.
	_view._on_unfold_all()
	await get_tree().process_frame
	var open_before := _open_ids()
	_expect(open_before.size() > chain.size(),
		"precondition: more than the target's chain must be open before the pick (%d open)"
			% open_before.size())

	_view._on_map_element_picked(target)
	await get_tree().process_frame
	await get_tree().process_frame

	var open_after := _open_ids()
	for id: String in chain:
		_expect(open_after.has(id),
			"the clicked element's chain must be OPEN after the pick (%s is shut; open: %s)"
				% [id, open_after])
	var strays: Array = []
	for id: String in open_after:
		if not chain.has(id):
			strays.append(id)
	_expect(strays.is_empty(),
		("a pick must leave ONLY the clicked element's chain open — these stayed open: %s")
			% [strays])
	_expect(_view.element_box(target).is_visible_in_tree(),
		"the isolated target must still be visible")

	# Isolation is a VIEW state, not a data change: the page must still describe every element.
	var missing: Array = []
	for e: UI3Element in registry.elements():
		if _view.element_box(e.id()) == null:
			missing.append(e.id())
	_expect(missing.is_empty(),
		"folding for isolation must not DELETE rows — missing %s" % [missing])


## The ids of every element whose fold is currently open.
func _open_ids() -> Array:
	var out: Array = []
	var registry := get_node_or_null("/root/UI3Registry")
	for e: UI3Element in registry.elements():
		var t: Button = _view.fold_toggle(e.id())
		if t != null and t.button_pressed:
			out.append(e.id())
	out.sort()
	return out


func _map_colors() -> Dictionary:
	var picker := _view.map_picker()
	if picker == null:
		return {}
	var out: Dictionary = {}
	var registry := get_node_or_null("/root/UI3Registry")
	for e: UI3Element in registry.elements():
		out[e.id()] = _view.owner_color(e.id())
	return out


func _expect(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
	else:
		_fail(msg)


func _fail(msg: String) -> void:
	_failed += 1
	print("[FAIL] " + msg)


func _finish() -> void:
	if _view != null and is_instance_valid(_view):
		_view._on_map_toggled(false)
	print("\n=== UI3OwnerPickAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] UI3OwnerPickAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3OwnerPickAcceptanceTest")
		get_tree().quit(0)
