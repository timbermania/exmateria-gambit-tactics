extends Node3D
# test-kind: logic
# seeded-break: no-op'd the body-holder carry line in FormationScene.play_equip_slide (pass instead of h.position = a.position + latched offset) so the detached unit BODY stays docked while anchors slide; every 'BODY did not track the anchor' + 'non-selected BODY off the right edge' assert reds, the frame-0/ease-in/settle/exits/scale asserts stay green

## FormationScene Item→Equip slide guard (headful) — FORMATION_SCREEN.md §15.23,
## RE round 22. Drives the REAL populated formation grid (the "rows of units" the
## user confirmed the formation screen always shows) through the Equip slide and pins
## the visible contract:
##   - begin_equip_slide() captures each visible unit cell's docked origin + target;
##   - play_equip_slide(0) leaves every anchor at its docked grid origin;
##   - play_equip_slide(SLIDE_DURATION) lands the SELECTED unit's sprite CENTER at the
##     measured (166,173) and slides every NON-selected unit off the right edge;
##   - the motion is ease-in (accelerating), and NOTHING scales (24×40 constant).
## Built via the FormationDetailTransition host so the roster + selection match the
## real wire (same recipe as FormationDetailTransitionTest).

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")

var _failed := false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	for _i in 4:
		await get_tree().process_frame

	var form = host._formation
	_expect(form != null and form.selected_character() != null,
		"host has no formation / no selected unit after ready")
	if form == null:
		_finish()
		return

	var sel: Vector2i = form.selected_cell
	var dur: int = SpriteSlideAnimator.SLIDE_DURATION

	# The selected unit's settle: sprite CENTER at (166,173). The body draw-center sits
	# at cell-relative (BODY_ANCHOR_DX, BODY_ANCHOR_DY) = (31,24) above the anchor origin.
	var body_center_off := Vector2(form.BODY_ANCHOR_DX, form.BODY_ANCHOR_DY)
	var expect_settle_origin := SpriteSlideAnimator.SETTLE_PX - body_center_off

	# Record docked origins of visible unit cells BEFORE the slide begins. The BODY holder
	# is a detached scene-root sibling of the anchor, so track BOTH: the bug was that only
	# the anchor (orb/shadow) slid while the unit sprite stayed docked.
	var docked := {}
	var docked_body := {}
	var scale_before := {}
	for cell in form.visible_unit_cells():
		var a: Node3D = form.get_cell(cell.x, cell.y)
		if a != null:
			docked[cell] = form.cell_anchor_screen_px(cell)
			docked_body[cell] = form.cell_body_screen_px(cell)
			scale_before[cell] = a.scale
	_expect(docked.size() >= 2, "need >=2 visible units to test selected vs non-selected (got %d)" % docked.size())

	# --- begin + play(0): every anchor AND body holder still at its docked grid origin ---
	form.begin_equip_slide()
	form.play_equip_slide(0)
	for cell in docked:
		_expect(form.cell_anchor_screen_px(cell).is_equal_approx(docked[cell]),
			"cell %s moved at frame 0 (%s != docked %s)" % [cell, form.cell_anchor_screen_px(cell), docked[cell]])
		_expect(form.cell_body_screen_px(cell).is_equal_approx(docked_body[cell]),
			"cell %s BODY moved at frame 0 (%s != docked %s)" % [cell, form.cell_body_screen_px(cell), docked_body[cell]])

	# --- ease-in: at the midpoint the selected unit has covered < half the distance ---
	form.play_equip_slide(dur / 2)
	var sel_mid := form.cell_anchor_screen_px(sel)
	var sel_dock: Vector2 = docked[sel]
	var covered := (sel_mid - sel_dock).length()
	var total := (expect_settle_origin - sel_dock).length()
	_expect(total > 1.0, "selected settle equals its dock — no motion to measure")
	if total > 1.0:
		_expect(covered < total * 0.5, "selected not ease-in: midpoint covered %.1f of %.1f" % [covered, total])

	# --- play(DURATION): selected settles at (166,173) center; non-selected off right edge ---
	form.play_equip_slide(dur)
	var sel_origin := form.cell_anchor_screen_px(sel)
	_expect(sel_origin.distance_to(expect_settle_origin) <= 0.5,
		"selected anchor %s did not settle at %s" % [sel_origin, expect_settle_origin])
	var sel_center := sel_origin + body_center_off
	_expect(sel_center.distance_to(SpriteSlideAnimator.SETTLE_PX) <= 0.5,
		"selected sprite center %s != SETTLE_PX %s" % [sel_center, SpriteSlideAnimator.SETTLE_PX])

	for cell in docked:
		if cell == sel:
			continue
		_expect(form.cell_anchor_screen_px(cell).x >= 256.0,
			"non-selected cell %s not off the right edge (x=%.1f)" % [cell, form.cell_anchor_screen_px(cell).x])

	# --- THE BUG GUARD: the rendered unit BODY must track the anchor, not stay docked.
	# The body holder is a detached sibling; before the fix, moving the anchor left the
	# sprite behind (user's "only the blue bullets slide"). Assert the body's screen
	# displacement equals the anchor's for every cell, and that non-selected bodies exit. ---
	for cell in docked:
		var body_delta: Vector2 = form.cell_body_screen_px(cell) - docked_body[cell]
		var anchor_delta: Vector2 = form.cell_anchor_screen_px(cell) - docked[cell]
		_expect(body_delta.distance_to(anchor_delta) <= 0.5,
			"cell %s BODY did not track the anchor (body moved %s, anchor moved %s)" % [cell, body_delta, anchor_delta])
		if cell != sel:
			_expect(form.cell_body_screen_px(cell).x >= 256.0,
				"non-selected cell %s BODY not off the right edge (x=%.1f)" % [cell, form.cell_body_screen_px(cell).x])

	# --- no scale: anchor scale is untouched by the slide ---
	for cell in docked:
		var a: Node3D = form.get_cell(cell.x, cell.y)
		if a != null:
			_expect(a.scale.is_equal_approx(scale_before[cell]),
				"cell %s scale changed during the slide (%s != %s)" % [cell, a.scale, scale_before[cell]])

	_finish()


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationEquipSlide test")
	else:
		print("[PASS] FormationEquipSlide: §15.23 selected→(166,173), non-selected exit right, ease-in, no scale")
	get_tree().quit()
