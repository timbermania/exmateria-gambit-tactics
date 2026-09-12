extends Node3D

## Formation START sub-menu guard (FORMATION_SCREEN.md §15.20) — headful (needs the
## RANGETILE atlas + shaders + FONT.BIN). Locks what a silent edit could regress:
##
##   1. Row model: the 5 action rows (Item…Order Unit), 16px pitch, up/down wrap.
##   2. Container {172,120,84,96} (PROVEN box-open aperture) + the box-open SCISSOR (§15.17):
##      frame 0 ⇒ empty point at centre, settle ⇒ full container, p=60 ⇒ the live {188,140,50,56}
##      (±1px of the ROM-integer center-out via BoxOpenAnimator). Body materials carry the
##      aperture; the "Menu" TITLE + the glove NEVER do (drawn full / on top, outside the clip).
##   2b. FRAME_RECT: the RENDERED frame is inset inside the aperture, right edge on the detail
##      panels' x244 (NOT the x256 struct-implied screen edge); FRAME_RECT ⊂ CONTAINER.
##   2c. "Menu" title = the texture-sampled window tab (§15.19): atlas cell (120,120,24,8) via
##      CLUT 0x7CBC, NOT FONT.BIN.
##   3. Glove cursor (§15.20): placed at (win_x−12+bob, win_y+row·16+10), bob axis = X
##      (the WORLD threshold-pair table, idle period 46). Two layers, shadow +2/+2. UNCLIPPED
##      (its own `cursor_materials` group, not `body_materials`) so it stays on top (issue 5).
##   4. The menu_glove_cursor atlas set: lit (168,0)/0x7d7c + shadow (184,0)/0x7dbc.
##   5. Outcome: confirm → chosen(row); cancel → cancelled.

const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")
const BoxOpenAnimator = preload("res://src/ui3/detail/BoxOpenAnimator.gd")
const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")

var _failed := false
var _last_chosen := -1
var _cancel_count := 0


func _ready() -> void:
	_test_rows_and_nav()
	_test_container_and_box_open()
	_test_frame_rect_inset()
	_test_title_tab()
	_test_title_not_clipped()
	_test_glove_unclipped()
	_test_glove_shadow_routes_to_fold()
	_test_glove_cursor_placement()
	_test_glove_bob_table()
	_test_atlas_glove_set()
	_test_outcome_signals()

	if _failed:
		print("[FAIL] FormationStartMenu test")
	else:
		print("[PASS] FormationStartMenu: rows/nav + box-open scissor + glove cursor + outcomes (§15.20)")
	get_tree().quit()


## 1. The 5 rows, 16px pitch, up/down wrap (mode-3 nav subset).
func _test_rows_and_nav() -> void:
	_expect(StartActionMenu.ROWS.size() == 5, "want 5 rows, got %d" % StartActionMenu.ROWS.size())
	_expect(StartActionMenu.ROWS[0] == "Item" and StartActionMenu.ROWS[4] == "Order Unit",
		"row strings drifted: %s" % str(StartActionMenu.ROWS))
	_expect(StartActionMenu.ROW_PITCH == 16, "row pitch != 16")

	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	add_child(m)
	_expect(m.selected_row() == 0, "initial row != 0")
	m.move_down(); _expect(m.selected_row() == 1, "down from 0 != 1")
	m.move_up(); _expect(m.selected_row() == 0, "up from 1 != 0")
	m.move_up(); _expect(m.selected_row() == 4, "up from 0 should wrap to 4, got %d" % m.selected_row())
	m.move_down(); _expect(m.selected_row() == 0, "down from 4 should wrap to 0, got %d" % m.selected_row())
	m.queue_free()


## 2. Container rect + the box-open scissor apertures.
func _test_container_and_box_open() -> void:
	_expect(StartActionMenu.CONTAINER == Rect2(172, 120, 84, 96),
		"CONTAINER = %s, want {172,120,84,96}" % StartActionMenu.CONTAINER)

	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	add_child(m)

	# frame < 0 (not started): an empty point at the centre — nothing revealed.
	var a_pre := m.aperture_at_frame(-1)
	_expect(a_pre.size == Vector2i.ZERO and a_pre.position == Rect2i(StartActionMenu.CONTAINER).get_center(),
		"pre-open aperture not an empty centre point: %s" % a_pre)

	# Settle ⇒ full container (no clip).
	var settle := BoxOpenAnimator.settle_frame(false)
	_expect(m.aperture_at_frame(settle) == Rect2i(StartActionMenu.CONTAINER),
		"settled aperture = %s, want the full container" % m.aperture_at_frame(settle))

	# p=60 (curve index 2) ⇒ the live-measured mid-open body {188,140,50,56} (±1px: the
	# ROM-integer center-out of {172,120,84,96} is {189,140,50,57}, within capture noise).
	var p60 := m.aperture_at_frame(2)
	_expect(absi(p60.position.x - 188) <= 1 and p60.position.y == 140,
		"p=60 origin = %s, want ~(188,140)" % p60.position)
	_expect(p60.size.x == 50 and absi(p60.size.y - 56) <= 1,
		"p=60 size = %s, want ~(50,56)" % p60.size)

	# Applying the box-open pushes the aperture onto the body materials as clip_world.
	m.set_open_frame(settle)
	_expect(m.aperture() == Rect2i(StartActionMenu.CONTAINER), "set_open_frame(settle) aperture wrong")
	_expect(m.body_materials().size() > 0, "no body materials collected (frame/rows/cursor)")
	m.queue_free()


## 2b. The RENDERED frame is inset inside the box-open aperture, right edge on the detail x244.
func _test_frame_rect_inset() -> void:
	var fr := StartActionMenu.FRAME_RECT
	var ap := Rect2i(StartActionMenu.CONTAINER)
	_expect(fr.position.x + fr.size.x == 244,
		"FRAME_RECT right = %d, want 244 (detail-panel inset)" % (fr.position.x + fr.size.x))
	# The drawn frame must sit fully inside the box-open aperture (so the scissor still reveals it).
	_expect(ap.encloses(fr), "FRAME_RECT %s not enclosed by the box-open aperture %s" % [fr, ap])
	# And it must be strictly narrower than the aperture (the fix: it stops short of the x256 edge).
	_expect(fr.size.x < ap.size.x and fr.position.x + fr.size.x < ap.position.x + ap.size.x,
		"FRAME_RECT should be inset from the struct rect's right edge")


## 2c. The "Menu" title = the texture-sampled window tab (§15.19), atlas cell (120,120,24,8).
func _test_title_tab() -> void:
	var atlas := RangeTileAtlas.new()
	_expect(atlas.has_window_tab(StartActionMenu.TITLE_TAB_NAME),
		"no window-tab cell for '%s' (regen RANGETILE.json)" % StartActionMenu.TITLE_TAB_NAME)
	_expect(atlas.window_tab_rect("Menu") == Rect2(120, 120, 24, 8),
		"Menu tab cell = %s, want (120,120,24,8)" % atlas.window_tab_rect("Menu"))
	# It is the SAME cream active-label CLUT as Eqp/Ability, not FONT.BIN.
	_expect(atlas.window_tab_colors().size() == 16, "window-tab CLUT != 16 colors")


## 2d. The "Menu" title is drawn FULL — it is NEVER given the box-open clip.
func _test_title_not_clipped() -> void:
	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	add_child(m)
	_expect(m.title_materials().size() > 0, "no title materials (Menu title missing)")

	# Close the body (empty aperture) — body materials get the inverted (never-passing) box.
	m.set_open_frame(-1)
	var body_clipped := false
	for bm in m.body_materials():
		var cw = bm.get_shader_parameter("clip_world")
		if cw != null and cw.x > 1e19:   # the inverted box _clip_world returns when closed
			body_clipped = true
			break
	_expect(body_clipped, "closed body materials not clipped (scissor not applied)")

	# The title materials must NOT carry that clip — they were never collected into the body set.
	for tm in m.title_materials():
		var cw = tm.get_shader_parameter("clip_world")
		_expect(cw == null or cw.x < 1e19, "title material was clipped by the box-open (should stay full)")
	_expect(StartActionMenu.RP_TITLE > StartActionMenu.RP_FRAME, "title rung not above the frame")
	m.queue_free()


## 3b. The glove is UNCLIPPED (issue 5): its own material group, never `body_materials`, so a
## closed box-open does NOT hide it — it pokes out the frame's left edge and stays on top.
func _test_glove_unclipped() -> void:
	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	add_child(m)
	_expect(m.cursor_materials().size() == 2, "want 2 glove mats (lit+shadow), got %d" % m.cursor_materials().size())
	# The glove mats must NOT be in the body set (which the box-open scissor clips).
	for cm in m.cursor_materials():
		_expect(not m.body_materials().has(cm), "glove material leaked into body_materials (would be clipped)")
	# Rungs: glove above the frame + rows so it draws on top.
	_expect(StartActionMenu.RP_CURSOR_SHADOW > StartActionMenu.RP_ROW_TEXT
			and StartActionMenu.RP_CURSOR_LIT > StartActionMenu.RP_CURSOR_SHADOW,
		"glove rungs must sit above frame/rows (shadow under lit)")
	# Close the body — the glove mats must NOT pick up the inverted clip box.
	m.set_open_frame(-1)
	for cm in m.cursor_materials():
		var cw = cm.get_shader_parameter("clip_world")
		_expect(cw == null or cw.x < 1e19, "glove material was clipped by the box-open (should stay on top)")
	m.queue_free()


## 3. Glove cursor placement + bob axis = X.
func _test_glove_cursor_placement() -> void:
	# row 0, no bob: x = 172 − 12 = 160, y = 120 + 0 + 10 = 130.
	_expect(StartActionMenu.cursor_display_pos(0, 0) == Vector2(160, 130),
		"cursor(row0,bob0) = %s, want (160,130)" % StartActionMenu.cursor_display_pos(0, 0))
	# row 2: y steps by 2·16 = 32 → 162. x unchanged.
	_expect(StartActionMenu.cursor_display_pos(2, 0) == Vector2(160, 162),
		"cursor(row2) = %s, want (160,162)" % StartActionMenu.cursor_display_pos(2, 0))
	# Bob is added to X only (axis = X): +3 bob → x 163, y unchanged.
	_expect(StartActionMenu.cursor_display_pos(0, 3) == Vector2(163, 130),
		"bob should move X only: %s" % StartActionMenu.cursor_display_pos(0, 3))


## 4. The glove bob threshold-pair table (idle period 46), consumed on X.
func _test_glove_bob_table() -> void:
	var idle := GloveCursorBob.load_glove_pairs("glove_idle")
	_expect(idle.size() == 6, "glove_idle pairs != 6 (got %d)" % idle.size())
	_expect(GloveCursorBob.glove_period(idle) == 46, "idle period != 46")
	# (16,0)(18,1)(22,2)(28,3)(36,2)(46,1): t<16→0, t=17→1, t=25→3, t=40→1.
	_expect(GloveCursorBob.glove_offset_for_frame(idle, 0) == 0, "idle@0 != 0")
	_expect(GloveCursorBob.glove_offset_for_frame(idle, 17) == 1, "idle@17 != 1")
	_expect(GloveCursorBob.glove_offset_for_frame(idle, 25) == 3, "idle@25 != 3")
	_expect(GloveCursorBob.glove_offset_for_frame(idle, 40) == 1, "idle@40 != 1")
	# Wraps by the period: frame 46 == frame 0.
	_expect(GloveCursorBob.glove_offset_for_frame(idle, 46) == GloveCursorBob.glove_offset_for_frame(idle, 0),
		"idle bob did not wrap at the period")


## 5. The menu_glove_cursor atlas set: lit (168,0)/0x7d7c + shadow (184,0)/0x7dbc.
func _test_atlas_glove_set() -> void:
	var atlas := RangeTileAtlas.new()
	_expect(atlas.menu_glove_lit_rect() == Rect2(168, 0, 16, 16),
		"glove lit rect = %s, want (168,0,16,16)" % atlas.menu_glove_lit_rect())
	_expect(atlas.menu_glove_shadow_rect() == Rect2(184, 0, 16, 16),
		"glove shadow rect = %s, want (184,0,16,16)" % atlas.menu_glove_shadow_rect())
	_expect(atlas.menu_glove_lit_colors().size() == 16, "glove lit CLUT != 16 colors")
	_expect(atlas.menu_glove_shadow_colors().size() == 16, "glove shadow CLUT != 16 colors")


## 6. Outcome signals.
func _test_outcome_signals() -> void:
	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	add_child(m)
	m.chosen.connect(func(r): _last_chosen = r)
	m.cancelled.connect(func(): _cancel_count += 1)
	m.move_down(); m.move_down()   # row 2
	m.confirm()
	_expect(_last_chosen == 2, "confirm emitted chosen(%d), want 2" % _last_chosen)
	m.cancel()
	_expect(_cancel_count == 1, "cancel did not emit cancelled once (%d)" % _cancel_count)
	m.queue_free()



## 3c. The glove's SUBTRACTIVE shadow must actually reach the fold on a folding build.
## PSX subtracts in the 8-bit framebuffer (DISPLAY space); Godot's main target is LINEAR, so an
## in-scene blend_sub applies a display-magnitude constant to linear light and over-darkens as the
## backdrop brightens (measured: max |err| vs the ROM's `bg - CLUT` 104 in-scene -> 4 folded, and 4
## is half an RGB555 step). The fold is the fix, so this asserts the ROUTE, not just the pixels.
##
## Worth a test rather than trusting the code: the fold's failure mode is SILENT — a shader that
## does not enrol simply blends in-scene and nothing raises. `Fold.add` is also a documented no-op
## off-fork, so the assertions below are gated on the same build predicate the producer uses.
func _test_glove_shadow_routes_to_fold() -> void:
	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	add_child(m)
	var shadow_mi: MeshInstance3D = m._shadow_holder.get_child(0) as MeshInstance3D
	_expect(shadow_mi != null, "glove shadow quad missing")
	if shadow_mi == null:
		m.queue_free(); return
	var mat := shadow_mi.material_override as ShaderMaterial
	var want := (StartActionMenu._SHADOW_FOLD_SHADER.resource_path if ExMateriaSchema.Fold.owns()
		else StartActionMenu._SHADOW_SHADER)
	_expect(mat != null and mat.shader != null and mat.shader.resource_path == want,
		"glove shadow shader = %s, want %s" % [
			("<null>" if mat == null or mat.shader == null else mat.shader.resource_path), want])
	if ExMateriaSchema.Fold.owns():
		# Enrolment is TWO per-instance properties, not just the material — without render_layer the
		# material folds in name only and never reaches Pass B.
		_expect(shadow_mi.render_layer != null,
			"glove shadow is not enrolled in the fold layer (render_layer unset)")
		# The LIT hand stays in-scene and OPAQUE: it is what depth-occludes the folded shadow, so
		# the shadow only peeks at +2/+2 instead of blooming through the hand.
		var lit_mi: MeshInstance3D = m._lit_holder.get_child(0) as MeshInstance3D
		_expect(lit_mi != null and lit_mi.render_layer == null,
			"the lit hand must NOT fold — it is the in-scene opaque depth writer")
	m.queue_free()

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("  [x] ", msg)
