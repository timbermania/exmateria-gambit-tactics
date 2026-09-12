extends Node3D

## DetailScene layout + box-open guard (headful — needs the RANGETILE atlas + shaders).
##
## Locks the composition a silent edit could regress:
##   1. The settled §15.14 window rects + the §15.17 box-open container centre.
##   2. That the lower panel actually builds: 3 window frames + 5 ability icons +
##      the two-layer Eqp slot icons (10 layers, 1-handed) + the two-layer Weap.Power
##      weapon-legend icon (2 layers), all under `_open_root`.
##   3. The box-open is a SCISSOR, not a scale (§15.17, live-confirmed 2026-08-05): it
##      NEVER scales `_open_root`; it reveals each window center-out through a growing
##      `clip_world` aperture, staggered (stats band first, then Eqp/Ability). The lower
##      aperture hits the live-confirmed {54,148,150,64} at p=60, and the content materials
##      carry that aperture as their clip.
##   4. The 2H-collapse variant hides the L.Hand row and swaps the combined icon.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression


const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")
const BoxOpenAnimator = preload("res://src/ui3/detail/BoxOpenAnimator.gd")
const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")
const Character = ExMateriaCatalogue.Character
var _failed := false


func _ready() -> void:
	# --- 1. layout constants -------------------------------------------------
	_expect(DetailScene.OPEN_CONTAINER == Rect2i(4, 126, 250, 108),
		"OPEN_CONTAINER = %s" % DetailScene.OPEN_CONTAINER)
	_expect(DetailScene.ABILITY_ROWS.size() == 5, "ability rows != 5")
	_expect(DetailScene.SLOT_ROWS.size() == 5, "slot rows != 5")
	# container centre = (129,180) display (the §15.17 pivot)
	var cx := DetailScene.OPEN_CONTAINER.position.x + DetailScene.OPEN_CONTAINER.size.x / 2.0
	var cy := DetailScene.OPEN_CONTAINER.position.y + DetailScene.OPEN_CONTAINER.size.y / 2.0
	_expect(cx == 129.0 and cy == 180.0, "container centre = (%s,%s), want (129,180)" % [cx, cy])

	# --- 2/3. build a 1-handed screen, settled ------------------------------
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)                            # _ready builds the panels

	# The vitals panel uses the SHARED corrected menu placement (not the battle
	# defaults): bars at x47, Lv./Exp. at (50,4)/(76,4) — same as the formation screen.
	var vw = d._vitals_window
	_expect(vw != null, "vitals panel not built")
	if vw != null:
		_expect(vw.bar_pos.size() >= 1 and is_equal_approx(vw.bar_pos[0].x, 47.0),
			"vitals bar x = %s, want 47 (apply_menu_layout)" % (vw.bar_pos[0] if vw.bar_pos.size() else "none"))
		_expect(vw.lv_pos == Vector2(50, 4) and vw.exp_pos == Vector2(76, 4),
			"vitals Lv/Exp = %s/%s, want (50,4)/(76,4)" % [vw.lv_pos, vw.exp_pos])

	# The nameplate (top-right) is the shared UIUnitNameplate widget; set a view and it
	# builds its glyph tree (frame + orb + name/job/zodiac/Brave·Faith).
	var np = d._nameplate
	_expect(np != null, "nameplate not built")
	if np != null:
		d.set_nameplate_view({"number": 1, "name": "Ramza", "job": "Squire",
			"brave": 70, "faith": 70, "zodiac": 0})
		_expect(np.get_child_count() >= 1, "nameplate has no content after set_view")

	var root: Node3D = d._open_root
	_expect(root != null, "_open_root not built")

	# The two dark column bands are the SHARED UIVitalsBand element (§15.19), REPARENTED under
	# _open_root (2026-08-05) and REVEALED center-out with the Eqp/Ability box-open aperture
	# (§15.17 scissor) instead of snapping to full size. The full-width vitals STRIPE is a
	# different element (rides the top vitals row, NOT the box-open) so it stays scene-level.
	_expect(_count_named(root, ["EqpBand", "AbilityBand"]) == 2,
		"column bands = %d, want 2 under the box-open group (§15.19)" % _count_named(root, ["EqpBand", "AbilityBand"]))
	_expect(_count_named(d, ["VitalsBand"]) == 1, "vitals stripe (UIVitalsBand) not built scene-level")

	if root != null:
		# Since the "frame = movable group" refactor the chrome + content hang off per-frame ORIGIN
		# nodes (StatsOrigin / LowerOrigin) under _open_root, not as flat siblings. The counts below
		# recurse / walk the origins; the totals are unchanged (a proven visual no-op — see
		# DetailFrameGroupTest), only the tree shape moved.
		var frames := _count_frames(root)
		# The Eqp + Ability panel is ONE monolithic frame now (§15.19), so only 2 lower
		# window frames remain: the stats band + the merged Eqp/Ability window.
		_expect(frames == 2, "lower frames = %d, want 2 (stats + monolithic Eqp/Ability)" % frames)
		# Icon/tab holders (plain Node3D from _mount_icon): 2 weapon-legend layers under StatsOrigin +
		# (5 ability + 10 slot + 2 tabs) under LowerOrigin = 19. Bands + rebuildable group nodes excluded.
		var holders := _count_icon_holders(d._stats_origin) + _count_icon_holders(d._lower_origin)
		_expect(holders == 19,
			"lower icon holders = %d, want 19 (5 ability + 10 slot + 2 weapon + 2 tabs)" % holders)

		# --- §15.21 (RE round 17): "send window to background" = a per-index CLUT SWAP, uniform
		# over the WHOLE lower Status subtree (frames + stats text + Eqp/Ability icons/tabs) — NOT
		# the retired display-space blue tint (which touched only the 2 frames). Menu-focus triggered
		# (set_backgrounded), default foreground.
		var win_mats := d.debug_window_materials()
		# The swap must cover MORE than the 2 frames — the key "uniform over subtree" property the
		# old frame-only tint could not assert (frames + text + icons).
		_expect(win_mats.size() > 2,
			"§15.21 subtree = %d window materials, want > 2 (frames + text + icons)" % win_mats.size())
		# Foreground by default: every window material's `backgrounded` == 0.0 (unset → null → 0.0).
		for wm in win_mats:
			var bg = wm.get_shader_parameter("backgrounded")
			_expect((bg == null) or float(bg) == 0.0,
				"§15.21 default should be foreground (backgrounded=%s)" % bg)
		# The FRAMES carry the RGB→index remap tables: fg[8] tan → bg[8] blue.
		for fr in _frames_of(root):
			var fm = fr.get_material()
			_expect(fm != null and int(fm.get_shader_parameter("palette_count")) == 16,
				"frame missing §15.21 palette_count 16 (got %s)"
					% [fm.get_shader_parameter("palette_count") if fm else "no-mat"])
			if fm != null:
				var fg = fm.get_shader_parameter("fg_palette")
				var bgp = fm.get_shader_parameter("bg_palette")
				_expect(fg != null and _v3_close(fg[8], Vector3(165.0/255.0, 156.0/255.0, 132.0/255.0), 0.02),
					"frame fg_palette[8] = %s, want tan (165,156,132)/255" % [fg[8] if fg else "null"])
				_expect(bgp != null and _v3_close(bgp[8], Vector3(107.0/255.0, 115.0/255.0, 123.0/255.0), 0.02),
					"frame bg_palette[8] = %s, want blue (107,115,123)/255" % [bgp[8] if bgp else "null"])
		# Flip to background: every window material now backgrounded == 1.0; every INDEXED material
		# (has a palette_tex param — icons/labels/values) carries a non-null palette_bg_tex.
		d.set_backgrounded(true)
		for wm in win_mats:
			_expect(float(wm.get_shader_parameter("backgrounded")) == 1.0,
				"after set_backgrounded(true), a window material is still foreground")
			if wm.get_shader_parameter("palette_tex") != null:
				_expect(wm.get_shader_parameter("palette_bg_tex") != null,
					"indexed window material has no §15.21 palette_bg_tex when backgrounded")
		# Flip back: every window material foreground again.
		d.set_backgrounded(false)
		for wm in win_mats:
			_expect(float(wm.get_shader_parameter("backgrounded")) == 0.0,
				"after set_backgrounded(false), a window material is still backgrounded")
		# The vitals+nameplate cluster is a SEPARATE group — NOT part of the swapped subtree. The
		# swapped-material count must equal exactly debug_window_materials() (cluster mats excluded);
		# and after backgrounding, the cluster's vitals/nameplate materials are untouched (null/0.0).
		d.set_backgrounded(true)
		for cm in _cluster_materials(d):
			var cbg = cm.get_shader_parameter("backgrounded")
			_expect((cbg == null) or float(cbg) == 0.0,
				"§15.21 must NOT background the vitals/nameplate cluster (got %s)" % cbg)
		d.set_backgrounded(false)

		# --- S3 (§15.22): the Status screen's OWN ◄L1/R1► corner unit-pager buttons are DetailScene
		# chrome (the roster sort-header is hidden). Each button = a 3-slice frame + 1 caption cell
		# (RANGETILE, button CLUT 0x7D7C). Because they're part of the lower-window material set they
		# background WITH the lower windows on menu-open — Oracle A (detail open) tan, Oracle B (menu
		# open) blue — NOT on detail-open.
		var pager_root := root.get_node_or_null("PagerButtons")
		_expect(pager_root != null, "PagerButtons container not built (§15.22)")
		if pager_root != null:
			_expect(pager_root.get_child_count() == 8,
				"pager pieces = %d, want 8 (2 buttons × [3 frame + 1 caption])" % pager_root.get_child_count())
		var pager_mats: Array = d.debug_pager_button_materials()
		_expect(pager_mats.size() == 8,
			"pager button materials = %d, want 8" % pager_mats.size())
		for pm in pager_mats:
			_expect(win_mats.has(pm),
				"a ◄L1/R1► material is not in the backgrounded window set — it would not blue on menu-open")

	# --- stats band: baked labels + number-font values build from a bound view ---
	# §15.18 (static-rooted): the band LABELS are baked RANGETILE cells (CLUT 0x7C3C),
	# NOT FONT.BIN; the VALUES + '/' + '%' are the small number font. Bind a view and the
	# middle band builds label sprites + number glyphs + the fixed 3-dot leaders.
	# Guard the atlas exposes every label token the builder draws (descriptor 0x80155D88).
	var atlas := RangeTileAtlas.new()
	for tok in ["Move", "Jump", "Speed", "Weap.Power", "AT", "C-", "S-", "A-", "EV", "R", "L"]:
		_expect(atlas.has_stat_label(tok), "atlas missing baked stat label '%s'" % tok)
	_expect(atlas.stat_label_colors().size() == 16, "stat label CLUT not 16 colors")
	d.set_stats_view({"move": 5, "jump": 3, "speed": 10,
		"r_power": 4, "l_power": 0, "r_wev": 5, "l_wev": 0,
		"r_at": 55, "l_at": 51, "c_ev": 10, "s_ev": 0, "a_ev": 0})
	var stats_root: Node3D = d._stats_text_root
	_expect(stats_root != null and stats_root.get_child_count() > 20,
		"stats band not built (label sprites + glyph holders = %d)" % (stats_root.get_child_count() if stats_root else -1))

	# The view builder maps a Character through progression (OUR data): AT per hand =
	# effective PA + that hand's weapon power (the oracle composition).
	var view := DetailScene.stats_view_from_character(_stub_character())
	_expect(view.has("move") and view.has("r_at") and view.has("a_ev"),
		"stats_view_from_character missing keys: %s" % [view.keys()])

	# --- worklist #4: per-slot EQUIPPED-item column (§15.13) — NAMES + the real ITEM.BIN ICONS.
	# RE round 49 (ITEM_EQUIPMENT_DATA.md §5) proved items.json `graphic` IS the ITEM.BIN menu-icon
	# cell (rec[1], live picker prims: Broad Sword g12, Leather Hat g90 pal 11) — the old worklist-#7
	# "graphic is a WEP1 sprite frame" deferral is refuted, so production entries carry the real cell
	# + palette and 4 icons mount alongside the 4 names. Expected literals below come from the round-49
	# live prim decode, not from items.json at test time.
	var eq_char = _stub_character()
	var ES = UnitProgression.EquipSlot
	eq_char.progression.equipment[ES.RIGHT_HAND] = 19   # Broad Sword
	eq_char.progression.equipment[ES.LEFT_HAND] = -1    # empty
	eq_char.progression.equipment[ES.HEAD] = 157        # Leather Hat
	eq_char.progression.equipment[ES.BODY] = 186        # Clothes
	eq_char.progression.equipment[ES.ACCESSORY] = 208   # Battle Boots
	var eq_view := DetailScene.stats_view_from_character(eq_char)
	var equipment: Array = eq_view.get("equipment", [])
	_expect(equipment.size() == 5, "stats view equipment array != 5 (%d)" % equipment.size())
	_expect((equipment[1] as Dictionary).is_empty(), "L.Hand (slot 1) should be empty")
	_expect(not (equipment[0] as Dictionary).is_empty()
			and String(equipment[0].get("name", "")).begins_with("Broad")
			and int(equipment[0].get("icon_graphic", -99)) == 12
			and int(equipment[0].get("palette", -99)) == 0,
		"R.Hand equipment view wrong (want name Broad*, icon_graphic 12, palette 0): %s" % [equipment[0] if equipment.size() else "none"])
	_expect(int((equipment[2] as Dictionary).get("icon_graphic", -99)) == 90
			and int((equipment[2] as Dictionary).get("palette", -99)) == 11,
		"Head equipment view wrong (want Leather Hat icon_graphic 90, palette 11): %s" % [equipment[2]])
	d.set_stats_view(eq_view)
	_expect(d.equip_item_name_count() == 4,
		"equipped-item NAMES mounted = %d, want 4" % d.equip_item_name_count())
	_expect(d.equip_item_icon_count() == 4,
		"equipped-item ICONS mounted = %d, want 4 (real ITEM.BIN cells, worklist #7 closed)" % d.equip_item_icon_count())
	# An unequipped unit mounts nothing (empty slots skipped).
	var bare = _stub_character()
	for s in [ES.RIGHT_HAND, ES.LEFT_HAND, ES.HEAD, ES.BODY, ES.ACCESSORY]:
		bare.progression.equipment[s] = -1
	d.set_stats_view(DetailScene.stats_view_from_character(bare))
	_expect(d.equip_item_icon_count() == 0 and d.equip_item_name_count() == 0,
		"unequipped unit should mount 0 icons/0 names (got %d/%d)" % [d.equip_item_icon_count(), d.equip_item_name_count()])
	# Restore the equipment-free stats view (no "equipment" key ⇒ 0 mounted) so the later
	# lower-panel icon-holder counts are unchanged by this block.
	d.set_stats_view({"move": 5, "jump": 3, "speed": 10,
		"r_power": 4, "l_power": 0, "r_wev": 5, "l_wev": 0,
		"r_at": 55, "l_at": 51, "c_ev": 10, "s_ev": 0, "a_ev": 0})

	# --- 3. box-open is a SCISSOR REVEAL, not a scale (§15.17, live-confirmed 2026-08-05) ---
	# _open_root must NEVER be scaled — the window is revealed through a growing clip aperture.
	_expect(root != null and root.scale.is_equal_approx(Vector3.ONE),
		"box-open must NOT scale _open_root (scissor reveal) — scale=%s" % (root.scale if root else Vector3.ZERO))

	# Settled (autoplay off → both windows fully open): apertures == the full window rects (no clip).
	d.set_open_frame(d._open_total_frames())
	_expect(d.lower_aperture() == DetailScene.OPEN_CONTAINER,
		"settled lower aperture = %s, want full OPEN_CONTAINER" % d.lower_aperture())
	# The settled stats aperture is a DERIVED rect (+ the R44 STATS_PANEL_NUDGE): its y/height come from
	# STATS_FRAME (the aperture rides the frame — move/resize the frame and its reveal window follows),
	# while its x/width are the INDEPENDENT full-width box-open sweep from STATS_CONTAINER (shared with
	# the lower panel, §15.18). Assert both halves so a regression can't re-couple width or de-couple y.
	var stats_nudge := Vector2i(DetailScene.STATS_PANEL_NUDGE)
	var settled_sa := d.stats_aperture()
	_expect(settled_sa.position.y == int(DetailScene.STATS_FRAME.position.y) + stats_nudge.y \
			and settled_sa.size.y == int(DetailScene.STATS_FRAME.size.y),
		"settled stats aperture y/h should derive from STATS_FRAME (+nudge.y=%d): got %s, frame %s"
			% [stats_nudge.y, settled_sa, DetailScene.STATS_FRAME])
	_expect(settled_sa.position.x == DetailScene.STATS_CONTAINER.position.x + stats_nudge.x \
			and settled_sa.size.x == DetailScene.STATS_CONTAINER.size.x,
		"settled stats aperture x/w should be the independent STATS_CONTAINER (+nudge.x=%d): got %s"
			% [stats_nudge.x, settled_sa])
	_expect(root.scale.is_equal_approx(Vector3.ONE), "settled still must not scale (scissor)")

	# Frame 0: BOTH windows open TOGETHER (user 2026-08-05: "same time, not in sequence") — each a
	# small center-out nub (p=10), neither closed, neither full.
	d.set_open_frame(0)
	_expect(d.stats_aperture().size != Vector2i.ZERO and d.stats_aperture() != DetailScene.STATS_CONTAINER,
		"frame0 stats aperture should be a partial nub, got %s" % d.stats_aperture())
	_expect(d.lower_aperture().size != Vector2i.ZERO and d.lower_aperture() != DetailScene.OPEN_CONTAINER,
		"frame0 lower aperture should be a partial nub (opens with the stats band), got %s" % d.lower_aperture())

	# The lower window reaches p=60 == the LIVE-CONFIRMED {54,148,150,64} prim (§15.17) at frame 2
	# (frames + the lower window's stagger, currently 0) — center-out, byte-exact.
	var lower_f2 := d._lower_open_delay() + 2
	d.set_open_frame(lower_f2)
	_expect(d.lower_aperture() == Rect2i(54, 148, 150, 64),
		"lower aperture at p=60 = %s, want the live {54,148,150,64}" % d.lower_aperture())

	# SAME WIDTH AT ALL TIMES (user 2026-08-05: "notice how they are the same width at all times
	# as they open"). The stats band and the Eqp/Ability panel share the ONE horizontal aperture:
	# at EVERY open frame their apertures must have the same WIDTH (they differ only vertically), and
	# the same x APART FROM the §15.26 R44 whole-stats-panel align nudge (STATS_PANEL_NUDGE.x). This is
	# what STATS_CONTAINER sharing OPEN_CONTAINER's x/w buys; guard it so a future edit can't re-diverge
	# the two widths (the bug that was fixed) while still allowing the deliberate R44 x-offset.
	var nudge_x := int(DetailScene.STATS_PANEL_NUDGE.x)
	for f in range(0, d._open_total_frames() + 2):
		d.set_open_frame(f)
		var sa := d.stats_aperture()
		var la := d.lower_aperture()
		_expect(sa.position.x == la.position.x + nudge_x and sa.size.x == la.size.x,
			"frame %d: stats/lower apertures diverged (stats x=%d w=%d, lower x=%d w=%d, R44 nudge.x=%d)"
				% [f, sa.position.x, sa.size.x, la.position.x, la.size.x, nudge_x])

	# The reveal is on the MATERIALS (a clip_world uniform), not a node transform: a lower-window
	# sprite material clips to exactly the lower aperture's world bounds.
	_expect(d._lower_mats.size() > 0, "no lower-window materials collected for the clip")
	if d._lower_mats.size() > 0:
		var cw = d._lower_mats[0].get_shader_parameter("clip_world")
		var want := d._clip_world(d.lower_aperture())
		_expect(cw != null and (cw as Vector4).is_equal_approx(want),
			"lower material clip_world = %s, want %s (the aperture's world bounds)" % [cw, want])

	# --- 4. two-handed variant hides L.Hand, keeps 5 ability + fewer slot layers ---
	var d2: DetailScene = DetailScene.new()
	d2.autoplay_open = false
	d2.two_handed = true
	add_child(d2)
	var root2: Node3D = d2._open_root
	if root2 != null:
		# 2H: R.Hand row = 1 layer (combined lit, no dark), L.Hand hidden,
		# head/body/accessory = 2 layers each → 1 + 0 + 3*2 = 7 slot holders + 5 ability
		# + 2 weapon-legend layers + 2 title tabs = 16 (bands + group nodes excluded). Counted under
		# the per-frame origins (the frame-group refactor re-rooted these off the flat _open_root).
		var holders2 := _count_icon_holders(d2._stats_origin) + _count_icon_holders(d2._lower_origin)
		_expect(holders2 == 16, "2H holders = %d, want 16" % holders2)

	if _failed:
		print("[FAIL] DetailScreen layout test")
	else:
		print("[PASS] DetailScreen: §15.14/§15.19 layout + §15.17 box-open SCISSOR reveal (2 frames, 2 bands, 19 holders, center-out aperture, no scale)")
	get_tree().quit()


## A default Ramza/Squire, same as the boot harness — drives the real progression path.
func _stub_character():
	return Character.create_default("Ramza", "4a", false)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


## Count the direct-child UIFrame nodes (the window chrome) under `node`.
func _count_frames(node: Node) -> int:
	return _frames_of(node).size()


## Every UIFrame node (window chrome) in the `node` subtree. Recurses: since the "frame = movable
## group" refactor the chrome lives under per-frame ORIGIN nodes (StatsOrigin/LowerOrigin), not as a
## direct child of _open_root, so a flat scan would miss them.
func _frames_of(node: Node) -> Array:
	var out := []
	for c in node.get_children():
		var sc = c.get_script()
		if sc != null and sc.get_global_name() == "UIFrame":
			out.append(c)
		out.append_array(_frames_of(c))
	return out


## Vector3 approximate-equality within `eps` per component (Vector3 has no epsilon variant).
func _v3_close(a, b: Vector3, eps: float) -> bool:
	if a == null:
		return false
	var v := a as Vector3
	return absf(v.x - b.x) <= eps and absf(v.y - b.y) <= eps and absf(v.z - b.z) <= eps


## Every ShaderMaterial under the vitals+nameplate cluster (a SEPARATE group from the box-open
## windows) — used to assert the §15.21 swap does NOT touch them. Empty is fine (light check).
func _cluster_materials(d) -> Array:
	var out := []
	var cluster = d._cluster
	if cluster == null or not is_instance_valid(cluster):
		return out
	_collect_shader_materials(cluster, out)
	return out


func _collect_shader_materials(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var m = (node as MeshInstance3D).material_override
		if m is ShaderMaterial and not out.has(m):
			out.append(m)
	for c in node.get_children():
		_collect_shader_materials(c, out)


## Count nodes in the `node` subtree whose name is in `names` (e.g. the column bands). Recurses:
## the bands are now reparented under LowerOrigin (the frame-group refactor), not directly under
## _open_root, so a flat scan would miss them.
func _count_named(node: Node, names: Array) -> int:
	var n := 0
	for c in node.get_children():
		if names.has(String(c.name)):
			n += 1
		n += _count_named(c, names)
	return n


## The per-frame icon/tab HOLDERS (plain Node3D from _mount_icon, each wrapping one MeshInstance3D
## quad) that are DIRECT children of a frame origin — the 5 ability + 10 slot + 2 weapon + 2 tab
## layers. Excludes the UIFrame chrome, the reparented bands, and the rebuildable group nodes
## (StatsText/EquipItems/AbilityItems/StatsDeltaPanel), matching the pre-refactor "direct children of _open_root,
## minus frames/bands/groups" arithmetic — just re-rooted under the origins.
const _GROUP_NAMES := ["StatsText", "EquipItems", "AbilityItems", "StatsDeltaPanel", "EqpBand", "AbilityBand", "PagerButtons"]

func _count_icon_holders(origin: Node) -> int:
	if origin == null or not is_instance_valid(origin):
		return 0
	var n := 0
	for c in origin.get_children():
		if c.get_script() != null:
			continue   # UIFrame chrome
		if String(c.name) == "StatsWeaponLegend":
			n += _count_icon_holders(c)   # the sword/rod legend group — its 2 layer holders nest here
			continue
		if _GROUP_NAMES.has(String(c.name)):
			continue   # named group / band node
		if _has_mesh_child(c):
			n += 1
	return n


func _has_mesh_child(node: Node) -> bool:
	for c in node.get_children():
		if c is MeshInstance3D:
			return true
	return false
