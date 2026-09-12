extends Node3D
# test-kind: logic
# seeded-break: move the two `set_meta` lines in `UnitSpawn.bind_for_combat` BELOW its `character.progression == null` guard and the STAMP arm's bare-identity leg reds (`bind_for_combat` stamps a Character with no progression too — that is what makes the identity resolvable for a unit the bind refused). Delete the two lines outright and the whole stamp arm reds, taking `character_for_unit` on a bind-only unit with it — which is the pre-fix tree, and reports 3 and 5 exactly. A second, independent seed: in `FormationMapHost.slot_number_for` return `1` instead of `0` for a unit outside the owned overlay and the two no-slot arms red while every owned-position arm stays green. A third seed, for the STATUS-SCREEN arm: revert either vitals push in `FormationDetailTransition` to the bare `FormationScene.vitals_view_from_character` and the arm reds on the site you reverted — the BUILD site (`open_detail`) reds the entry assert ('must show the LIVE HP 15, got 31'), the EQUIP-COMMIT site reds the post-commit assert ('must still read the live 15, got 151') plus the funnel census, and each leaves the other GREEN, so the two are proven independent. A fifth seed, for the funnel census specifically — and the one that matters, because it is the evasion the census's FIRST cut could not see: split any site into `var v := FormationScene.vitals_view_from_character(character)` + `set_unit_view(v)` and the census reds with `Found 2`, where a census matching the single-line push spelling stays GREEN. A fourth seed, for the clamp leg: replace the body of `UnitStats._on_progression_stats_changed` with `pass` and ONLY the clamp assert reds ('must clamp DOWN to 31 ... got 151') — the denominator assert beside it stays green, so that pair is independent too.

## ADR-0137 guard — the Formation screen re-hosted over the live battlefield.
##
## Pins the parts of that decision that are CHECKABLE without a map: the host seam (which layers
## each host builds, which queries invert), the mount arithmetic that reconciles the screen's
## authored ortho with the map camera's, the reversibility of the new camera-pan beat, and the
## hover cadence's two curves. The parts that need a real battlefield — that the pan actually lands
## the unit on the breakout mark, that the band subtracts from the map — are verified headful over
## a live GPUArena; a unit test cannot see a picture.

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const TransitionEngine = preload("res://src/ui3/formation/FormationTransitionEngine.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")
const Character = ExMateriaCatalogue.Character
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
# ADR-0211 dec. 4 — a host MAY alias a published constant off the addon façade, and may NOT
# `preload` an addon path. One alias per SYMBOL (this file also aliases `Character` above), which is
# what keeps a grep for `ExMateriaAlmanac` a complete census of host->addon coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression

## Crystal Helmet: `hp_bonus` +120 in the HEAD slot — an HP swing far too large for a rounding or an
## off-by-one to imitate, which is what makes "did the DENOMINATOR move" a readable question.
const HP_HELMET := 154

var _failed := false
var _checks := 0


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	_test_breakout_mark()
	_test_mount_transform()
	_test_mount_z_keeps_the_rung_ladder_in_front()
	_test_one_intent_per_button()
	_test_hover_curves()
	_test_off_layout()
	await _test_panel_widths_are_measured()
	await _test_host_seam()
	await _test_map_recipe()
	await _test_sub_exit_pops_one_level()
	await _test_disabled_rows()
	await _test_character_resolution()
	await _test_uncatalogued_units_resolve()
	await _test_bind_stamps_identity()
	await _test_vitals_repaint_follows_the_cursor()
	await _test_vitals_read_the_live_unit()
	await _test_status_screen_reads_the_live_unit()

	if _failed:
		print("[FAIL] FormationMapHost test")
	else:
		print("[PASS] FormationMapHost (%d assertions): seam + mount + breakout mark + pan reversibility"
			% _checks
			+ " + hold/pan split + one-intent-per-button + hover cadence + pad handoff"
			+ " + ✕ pops one level on MAP / unwinds on ROSTER + disabled rows (ADR-0137)"
			+ " + unit→Character resolves by slug (ADR-0180)"
			+ " + an UNCATALOGUED ENTD unit resolves + is not owned (ADR-0180 Am.2)"
			+ " + bind_for_combat STAMPS the identity, above its own progression guard"
			+ " + the pair repaints from the CURSOR, not cell 0 (ADR-0137 Am.9)"
			+ " + the vitals gauges read the LIVE unit's HP/MP, not the identity's max"
			+ " + the battlefield STATUS screen reads the live unit too, at build AND after an equip"
			+ " commit (a helmet raises the denominator and does not heal the numerator, and"
			+ " stripping it clamps the numerator back DOWN). The funnel CENSUS is no longer"
			+ " claimed here — it is tools/check_vitals_funnel.py, repo-wide, in the pre-flight")
	get_tree().quit()


## TWO marks now, one per host — and the guard has to say which number serves which.
##
## ROSTER: [constant FormationScene.BREAKOUT_MARK_PX] is the Equip/Ability settle plus half a roster
## descriptor — DERIVED, so a re-measured settle carries it. The literal (178,193) is the ADR's
## number; if that pair fails, the settle moved and the ADR needs re-reading, not the constant
## patching. The map host no longer consumes either.
##
## MAP: [constant FormationMapHost.FEET_MARK_PX] is its OWN measurement (2026-08-21), and what makes
## it RIGHT is not the literal — it is that the unit stands centred in the gap the sub-screen opens
## between the narrowed lower panel and the list menu. So the expectation is computed from the two
## constants that SPAN that gap, which this mark does not own: `LOWER_FRAME_EQUIP`'s right edge and
## `EQUIP_CONTAINER`'s left edge. Move either panel, or move the mark, and this goes red — which is
## the whole point (a guard that derives its expectation from the constant under test cannot fail).
## Confirmed RED by hand against the pre-fix x=178 before being trusted.
func _test_breakout_mark() -> void:
	# --- the ROSTER host's mark, unchanged ---
	_expect(FormationScene.BREAKOUT_MARK_PX == Vector2(178, 193),
		"ROSTER breakout mark should be (178,193), got %s" % str(FormationScene.BREAKOUT_MARK_PX))
	_expect(FormationScene.BREAKOUT_MARK_PX
			== SpriteSlideAnimator.SETTLE_PX + FormationScene.ROSTER_DESC * 0.5,
		"ROSTER breakout mark must stay DERIVED from SETTLE_PX + half the descriptor")

	# --- the MAP host's mark: its own literal, then the reason for it ---
	_expect(FormationMapHost.FEET_MARK_PX == Vector2(167, 213),
		"MAP feet mark should be (167,213), got %s" % str(FormationMapHost.FEET_MARK_PX))
	_expect(FormationMapHost.FEET_MARK_PX.x != FormationScene.BREAKOUT_MARK_PX.x,
		"the MAP mark must be its own — sharing the roster's x is what put the unit on the menu")

	var mark_x: float = FormationMapHost.FEET_MARK_PX.x
	var half_w: float = FormationMapHost.MAP_BODY_PX.x * 0.5
	# Equip: the TIGHTER of the two gaps, so the mark is centred on this one.
	var eq_left: float = DetailScene.LOWER_FRAME_EQUIP.position.x + DetailScene.LOWER_FRAME_EQUIP.size.x
	var eq_right: float = StartActionMenu.EQUIP_CONTAINER.position.x
	_expect(absf(mark_x - (eq_left + eq_right) * 0.5) <= 1.0,
		"MAP mark x=%.1f must be centred in the EQUIP gap x%.0f..%.0f (centre %.1f)"
			% [mark_x, eq_left, eq_right, (eq_left + eq_right) * 0.5])
	_expect(mark_x - half_w > eq_left and mark_x + half_w < eq_right,
		"the unit (%.0fpx wide) must stand clear of BOTH EQUIP panels, not against one"
			% FormationMapHost.MAP_BODY_PX.x)
	# Ability: a wider gap, shifted LEFT. The one mark has to clear it too.
	var ab_left: float = DetailScene.LOWER_FRAME_ABILITY.position.x + DetailScene.LOWER_FRAME_ABILITY.size.x
	var ab_right: float = StartActionMenu.ABILITY_CONTAINER.position.x
	_expect(mark_x - half_w > ab_left and mark_x + half_w < ab_right,
		"MAP mark x=%.1f must also clear the ABILITY gap x%.0f..%.0f" % [mark_x, ab_left, ab_right])

	# Vertically the unit has to sit BELOW the stats band and ABOVE the screen floor — the gap the
	# panels leave runs from the lower frame's top to y240.
	var head_y: float = FormationMapHost.FEET_MARK_PX.y - FormationMapHost.MAP_BODY_PX.y
	_expect(head_y > DetailScene.LOWER_FRAME_EQUIP.position.y,
		"the unit's head (y=%.0f) must clear the stats band above the lower frame" % head_y)
	_expect(FormationMapHost.FEET_MARK_PX.y < FormationScene.SCREEN.y,
		"the unit's feet must land on-screen")


## The one genuine unknown the design left open: the screen is authored for a keep-height ortho of
## 240px * 0.04 = 9.6 world units, the map camera runs 12.6, and the root scales to reconcile them.
##
## ADR-0137 Amendment 3 turned the correction from a fixed mount into a FUNCTION the gesture walks:
## the entry pan zooms the camera from 12.6 to the authored 9.6, so the map arrives at the Formation
## scene's own scale and the root correction rides from 1.3125 down to 1.0. Both ends are pinned
## below — the 1.0 end is the one that says the zoom TARGET is right, because a target anywhere else
## leaves the root correcting for a mismatch that is supposed to be gone.
func _test_mount_transform() -> void:
	var m: Dictionary = FormationMapHost.mount_transform_for(12.6)
	_expect(is_equal_approx(float(m["scale"]), 1.3125),
		"mount scale should be 12.6/9.6 = 1.3125, got %f" % float(m["scale"]))
	var pos: Vector3 = m["position"]
	# The authored screen's origin is display (0,0) — its top-LEFT — so its centre has to be pushed
	# back onto the camera's local origin, at the scaled size.
	_expect(pos.is_equal_approx(Vector3(-6.72, 6.3, -10.0)),
		"mount position should be (-6.72, 6.3, -10), got %s" % str(pos))
	# An UNCORRECTED mount would occupy 9.6/12.6 = 76% of screen height — the bug this guards.
	_expect(not is_equal_approx(float(m["scale"]), 1.0), "identity scale would under-fill by 24%")
	# The FAR end of the zoom. 9.6 is written as a literal on purpose: deriving it from
	# AUTHORED_ORTHO_SIZE would make this assertion a restatement of the constant it is checking,
	# and it would stay green if that constant drifted.
	_expect(is_equal_approx(FormationMapHost.AUTHORED_ORTHO_SIZE, 9.6),
		"authored ortho should be 240*0.04 = 9.6, got %f" % FormationMapHost.AUTHORED_ORTHO_SIZE)
	var arrived: Dictionary = FormationMapHost.mount_transform_for(9.6)
	_expect(is_equal_approx(float(arrived["scale"]), 1.0),
		"at the zoom target the root must need NO correction, got %f" % float(arrived["scale"]))


## THE MOUNT'S Z SCALE IS 1.0, AND THE ORDERING-TABLE LADDER STAYS IN FRONT OF THE CAMERA.
##
## The arm that would have caught "the gambit modal opens and no UI elements show up". That defect
## satisfied every structural check there is — the surface existed, held the pad, was
## `visible_in_tree`, was not culled, had real AABBs and a settled box-open — and drew nothing,
## because `apply_mount_transform` scaled Z along with X/Y. `GambitSurfaceTest` passed 123/0
## through it, and no assertion in the tree could see it, because the thing that was wrong was a
## COORDINATE, not a state.
##
## So this asserts the geometry that MEANS "drawn": the tallest rung this screen mounts must land
## in front of the near plane at the widest correction the map host ever applies. It needs no
## frame, no GPU and no scene — the mount is a pure function and the ladder is two constants — so
## it rides in this process rather than costing a 2.3 s boot of its own (charter clause 13).
func _test_mount_z_keeps_the_rung_ladder_in_front() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 12.6                       # the map camera's own ortho, pre-pan
	var node := Node3D.new()
	FormationMapHost.apply_mount_transform(node, cam)

	# X and Y still carry the 12.6/9.6 reconciliation — the screen is authored for 9.6 and this
	# camera is not it, so dropping the correction outright would under-fill by 24%.
	_expect(is_equal_approx(node.scale.x, 1.3125) and is_equal_approx(node.scale.y, 1.3125),
		"X/Y must still be corrected by cam.size/9.6, got %s" % str(node.scale))
	# Z must NOT. It is not a screen quantity: under this node Z is the ADR-0009 ordering-table
	# ladder, `rung * UNITS_PER_OT_BUCKET`, an absolute depth. Scaling a depth bucket by a
	# screen-size ratio is the category error this pins.
	_expect(is_equal_approx(node.scale.z, 1.0),
		"the mount's Z scale must be 1.0, got %f — a scaled Z splays the OT ladder toward the"
			% node.scale.z + " camera and the top of it crosses the near plane")

	# The ladder itself, at the tallest rung the tree actually mounts: GambitSurfaceMenu's glove is
	# `depth_rung -6 + RP_CURSOR_LIT 52` = 46. Derived from the constants rather than written as a
	# literal, so a re-rung of that menu re-prices this assertion instead of silently escaping it.
	var top_rung: int = -6 + GambitSurfaceMenu.RP_CURSOR_LIT
	var ladder_z: float = float(top_rung) * ExMateriaSchema.DepthMode.UNITS_PER_OT_BUCKET
	var world_z: float = node.position.z + ladder_z * node.scale.z
	_expect(world_z < -cam.near,
		"the tallest mounted rung (%d) lands at z=%+.3f, which is not in front of near=%.3f —"
			% [top_rung, world_z, cam.near]
			+ " every quad above it is near-plane clipped and the screen renders EMPTY")

	# DIRECTION. The pre-fix arithmetic, computed rather than remembered: with Z scaled like X/Y
	# the same rung lands BEHIND the camera. Asserting the broken value is positive is what makes
	# the assertion above a measurement and not a tautology that any Z scale would satisfy.
	var broken_z: float = node.position.z + ladder_z * 1.3125
	_expect(broken_z > 0.0,
		"the control is dead: a UNIFORM mount scale must put rung %d behind the camera (got"
			% top_rung + " %+.3f); if it does not, this arm can no longer fail" % broken_z)

	cam.free()
	node.free()


## Two curves, not one (ADR-0097): their units are not interchangeable, and their SHAPES differ for
## a reason — the pair overshoots, the band must not.
func _test_hover_curves() -> void:
	var settle := FormationHoverAnimator.settle_frame()
	_expect(is_equal_approx(FormationHoverAnimator.pair_fraction_at(0), 0.0), "pair starts off-screen")
	_expect(is_equal_approx(FormationHoverAnimator.pair_fraction_at(settle), 1.0), "pair settles docked")
	var peak := 0.0
	for f in range(0, settle + 1):
		peak = maxf(peak, FormationHoverAnimator.pair_fraction_at(f))
	_expect(peak > 1.0, "the pair cadence must OVERSHOOT (peak %f); ADR-0137 asks for"
		% peak + " 'opens a little too much, then settles'")

	_expect(is_equal_approx(FormationHoverAnimator.band_fraction_at(0), 0.0), "band starts invisible")
	var band_peak := 0.0
	var prev := -1.0
	var monotone := true
	for f in range(0, settle + 1):
		var v := FormationHoverAnimator.band_fraction_at(f)
		band_peak = maxf(band_peak, v)
		if v < prev - 0.0001:
			monotone = false
		prev = v
	_expect(band_peak <= 1.0 + 0.0001,
		"the band cadence must NOT overshoot (peak %f) — its fraction scales the oracle's" % band_peak
		+ " 120/255 subtract, so past 1.0 is darker than the ROM's black, not livelier")
	_expect(monotone, "the band fade must be monotone")

	# Authored, therefore `static var` + a Tune slug — never a `const` beside the parsed SLIDE_CURVE.
	for slug in [FormationHoverAnimator.PAIR_TICKS_SLUG, FormationHoverAnimator.PAIR_OVERSHOOT_SLUG,
			FormationHoverAnimator.BAND_TICKS_SLUG, FormationMapHost.PAN_DURATION_SLUG]:
		_expect(Tune.registered_slugs().has(slug), "authored cadence '%s' has no Tune home" % slug)


## The third layout parks BOTH pieces fully outside the 256-px display, each past the edge it
## enters from — otherwise a "hidden" panel is a sliver of chrome stuck to the screen edge at rest.
func _test_off_layout() -> void:
	var v: Vector2 = UnitInfoCluster.LAYOUT_OFF["vitals"]
	var n: Vector2 = UnitInfoCluster.LAYOUT_OFF["nameplate"]
	_expect(v.x + UnitInfoCluster.VITALS_W <= 0.0,
		"vitals OFF must be fully left of x=0 (right edge at %f)" % (v.x + UnitInfoCluster.VITALS_W))
	_expect(n.x >= FormationScene.SCREEN.x,
		"nameplate OFF must be fully right of x=256 (left edge at %f)" % n.x)
	# The two assertions above are arithmetic on the constants LAYOUT_OFF is DERIVED from, so they
	# can never fail — they were green the whole time the vitals panel sat 14 px on screen at rest.
	# The only thing that can catch that is measuring what the panel actually DRAWS; see
	# `_test_panel_widths_are_measured`.
	# The hover is a horizontal entrance, not the DOCKED→TOP rise: Y is unchanged.
	_expect(is_equal_approx(v.y, (UnitInfoCluster.LAYOUT_DOCKED["vitals"] as Vector2).y),
		"vitals OFF must keep the DOCKED Y")
	_expect(is_equal_approx(n.y, (UnitInfoCluster.LAYOUT_DOCKED["nameplate"] as Vector2).y),
		"nameplate OFF must keep the DOCKED Y")


## The width constants are a MEASUREMENT of the built panels, and this is the only assertion that
## can tell. Build a real cluster, take the union AABB of everything each panel draws, and compare.
## An under-measured width does not park the panel off screen — it parks it ALMOST off screen, and
## the residue reads to the player as a panel that never left.
func _test_panel_widths_are_measured() -> void:
	var cluster := UnitInfoCluster.new()
	add_child(cluster)
	cluster.build(FormationScene.PIXELS_PER_UNIT, false)
	# Synthetic WIDEST-CASE content: the panels draw nothing until a view is pushed, and the extent
	# we care about is the one the widest readout produces. Three-digit HP/MP and a full CT are the
	# widest the vitals panel ever gets; the nameplate's is a long name + job.
	cluster.set_unit_view({
		"name": "Wwwwwwwww", "job": "Wwwwwwwwww", "level": 99, "exp": 99,
		"sprite_id": "", "template_folder": "",
		"current_hp": 999, "max_hp": 999, "current_mp": 999, "max_mp": 999,
		"ct": 100, "has_ct": true, "brave": 99, "faith": 99, "statuses": [],
	})
	cluster.set_nameplate_view({
		"number": 99, "name": "Wwwwwwwww", "job": "Wwwwwwwwww",
		"brave": 99, "faith": 99, "zodiac": 0,
	})
	for _i in 8:
		await get_tree().process_frame
	for pair in [["vitals", cluster._vitals, UnitInfoCluster.VITALS_W],
			["nameplate", cluster._nameplate, UnitInfoCluster.NAMEPLATE_W]]:
		var node = pair[1]
		if node == null or not is_instance_valid(node):
			_expect(false, "the cluster should build a %s panel" % pair[0])
			continue
		var drawn_px: float = _union_aabb(node).size.x / FormationScene.PIXELS_PER_UNIT
		if drawn_px <= 0.0:
			_expect(false, "%s drew nothing to measure" % pair[0])
			continue
		_expect(drawn_px <= float(pair[2]) + 1.0,
			("%s draws %.1f px but its constant says %.1f — the OFF layout parks it %.1f px"
				+ " ON screen, which is the panel that 'never quite leaves'")
				% [pair[0], drawn_px, float(pair[2]), drawn_px - float(pair[2])])
	cluster.queue_free()


## Union of every VisualInstance3D AABB under `root`, in ROOT-LOCAL space. The panels are bare
## Node3Ds — their real extent is the union of what they draw, never their own (empty) AABB.
func _union_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is VisualInstance3D:
			var a: AABB = (root.global_transform.affine_inverse()
				* (n as Node3D).global_transform) * (n as VisualInstance3D).get_aabb()
			out = a if first else out.merge(a)
			first = false
	return out


## The seam itself: the map host turns off exactly two things and inverts exactly one query.
func _test_host_seam() -> void:
	var host := FormationMapHost.new()
	add_child(host)
	for _i in 4:
		await get_tree().process_frame

	_expect(not host.paints_own_backdrop(), "the map host must not paint its own backdrop")
	_expect(not host.owns_roster_grid(), "the map host has no roster grid")
	# The query INVERTS to a FIXED mark — and to this host's OWN mark, not the roster's. Pinned as a
	# literal on purpose: deriving it from FEET_MARK_PX/MAP_BODY_PX would just restate the method.
	_expect(host.selected_unit_screen_center() == Vector2(167.0, 199.5),
		"the map host's selected-unit query INVERTS to its own breakout mark (167,199.5), got %s"
			% str(host.selected_unit_screen_center()))
	_expect(host.selected_unit_screen_center() != FormationScene.BREAKOUT_MARK_PX,
		"the map host must NOT report the roster host's mark")

	# No grid was built — and the grid-shaped coordinator obligations therefore degenerate rather
	# than erroring. Calling every one of them proves the no-ops are total, not merely unused.
	_expect(host.get_node_or_null("Background") != null, "the BAND holder must still build")
	_expect(host.has_band(), "the map host must build the subtractive band — it is screen-common")
	_expect(host.unit_info_cluster() != null,
		"the map host must build the docked pair even with no roster to index")
	for call_name in ["set_orbs_visible", "set_box_trail_visible", "set_cell_readouts_visible",
			"set_header_visible"]:
		host.call(call_name, false)
		host.call(call_name, true)
	host.begin_equip_slide()
	host.play_equip_slide(0)
	host.play_equip_unslide(0)
	host.end_equip_slide()
	host.redock_units()
	_expect(true, "unreachable")   # reaching here at all is the assertion

	# The pair starts parked off-screen with no band: at rest this screen shows NOTHING over the map.
	var c := host.unit_info_cluster()
	_expect(c.vitals_origin_px().x <= 0.0,
		"at rest the vitals must be parked off-screen, found x=%f" % c.vitals_origin_px().x)
	host.queue_free()


## The camera beats are first-class REVERSIBLE beats, so the boot audit covers them and the exit
## comes for free. Amendment 5 SPLIT them across two recipes, and the split is the thing to pin:
## MAP_DETAIL now only HOLDS the camera (the takeover, which is what freezes the cursor and the pad),
## while the pan+zoom MOTION rides in the EQUIP group — because it is the sub-screen that narrows the
## frames and actually reveals the unit. Pinning both halves is what stops the motion drifting back
## to DETAIL entry, where the user watched it pan to a unit the panels then covered.
func _test_map_recipe() -> void:
	var host: Node3D = FormationDetailTransition.new()
	host.host_mode = FormationDetailTransition.Host.MAP
	add_child(host)
	for _i in 4:
		await get_tree().process_frame

	var recipes: Array = host.recipe_table()
	var ids: Array = []
	for r in recipes:
		ids.append(r.id)
	_expect(ids.has("MAP_DETAIL"), "MAP host must register a MAP_DETAIL recipe (ids=%s)" % str(ids))
	_expect(TransitionEngine.audit(recipes).is_empty(),
		"MAP recipes are NOT fully reversible: %s" % str(TransitionEngine.audit(recipes)))
	for r in recipes:
		if r.id != "MAP_DETAIL":
			continue
		_expect(r.groups.size() == 1, "MAP_DETAIL is one group (the hold), got %d" % r.groups.size())
		var beat = r.groups[0].beats[0]
		_expect(beat.id == "map_hold", "MAP_DETAIL group 0 should be the HOLD, got '%s'" % beat.id)
		# A takeover with no motion has nothing to animate on the way in...
		_expect(beat.duration == FormationMapHost.HOLD_TICKS,
			"the hold occupies one tick forward (%d), got %d"
			% [FormationMapHost.HOLD_TICKS, beat.duration])
		# ...but its REVERSE is the real return, and it is ASYMMETRIC by design:
		# release_takeover's cosine ease is not the entry run backward.
		_expect(beat.reverse_duration == FormationMapHost.PAN_RELEASE_TICKS,
			"the hold's reverse declares its OWN length (%d), got %d"
			% [FormationMapHost.PAN_RELEASE_TICKS, beat.reverse_duration])

	# The MOTION lives in EQUIP, and ONLY on this host — the roster host's EQUIP has no camera at
	# all. Both halves are asserted: present here, and (below) absent on the roster host.
	for r in recipes:
		if r.id != "EQUIP":
			continue
		var ids2: Array = []
		var targets: Array = []
		for b in r.groups[0].beats:
			ids2.append(b.id)
			targets.append_array(b.targets)
		_expect(ids2.has("map_pan"),
			"the MAP host's EQUIP group must carry the pan+zoom, got %s" % str(ids2))
		# Invariant 4 is what LETS it ride in the same group as the chrome and the roster slide:
		# three beats, three disjoint targets, so they may play concurrently.
		_expect(targets.size() == 3 and targets.has("chrome") and targets.has("roster")
				and targets.has("camera"),
			"the three concurrent beats must declare DISJOINT targets, got %s" % str(targets))
	_expect(TransitionEngine.concurrency_conflicts(recipes).is_empty(),
		"the MAP EQUIP group must be invariant-4 clean: %s"
		% str(TransitionEngine.concurrency_conflicts(recipes)))

	# The wholesale pad claim's TWO exceptions (ADR-0137). Everything else is swallowed: the map's
	# own handlers test RAW KEYCODES, so no named-action swallow could reach them, and Space and Tab
	# both mutate `combat_active` — left leaking they resume the battle underneath an open screen
	# and make the exit unpause an already-running sim.
	_expect(FormationDetailTransition.map_pad_exempt(_key(KEY_F3)), "F3 must stay live over the screen")
	_expect(FormationDetailTransition.map_pad_exempt(InputEventMouseMotion.new()),
		"mouse events must stay live over the screen")
	for kc in [KEY_SPACE, KEY_ENTER, KEY_TAB, KEY_R, KEY_ESCAPE, KEY_UP]:
		_expect(not FormationDetailTransition.map_pad_exempt(_key(kc)),
			"keycode %d must be SWALLOWED while the map host owns the pad" % kc)
	_expect(not host.map_input_owned(), "the pad is not owned before a screen is entered")

	# The ROSTER host must NOT grow the map recipe — the two hosts coexist, neither leaks.
	var roster_host: Node3D = FormationDetailTransition.new()
	add_child(roster_host)
	for _i in 4:
		await get_tree().process_frame
	var rids: Array = []
	for r in roster_host.recipe_table():
		rids.append(r.id)
		# ...and its EQUIP must not have grown a camera beat either (Amendment 5). The map beat is
		# added by a `host_mode == MAP` branch inside the SHARED recipe builder, so this is the
		# assertion that says the branch is real rather than decorative.
		if r.id == "EQUIP":
			var beat_ids: Array = []
			for b in r.groups[0].beats:
				beat_ids.append(b.id)
			_expect(not beat_ids.has("map_pan"),
				"the ROSTER host's EQUIP must have no camera beat, got %s" % str(beat_ids))
	_expect(not rids.has("MAP_DETAIL"), "the ROSTER host must not carry MAP_DETAIL (ids=%s)" % str(rids))
	host.queue_free()
	roster_host.queue_free()


## Amendment 7 — where ✕ out of a sub-screen LANDS, which is now a per-host question.
##
## ADR-0084 RE25 ("a sub-screen back-out is a FULL unwind to the roster") still governs the roster
## host and no longer governs the map one, so the guard has to pin the SPLIT rather than either half:
## the same press on the same state does two different things depending on who is hosting, and a
## regression that collapses them back into one rule is exactly what this catches.
##
## `_exit_settled` is driven directly rather than through a real back-out because the unwind is the
## only thing under test here — the ANIMATED round trip needs a live battlefield and is verified
## headful (tmp/proto/deployed_mark_probe.tscn). What a unit test can prove is that the sites which
## must agree actually do; as of ADR-0261 there is only ONE site, the `_UNWIND_*` table, and this is
## its guard. The three that preceded it (the predicate, `_exit_settled`'s match arms, and
## `_teardown_sub_screen`) each stated a depth in prose, which is how Change Job came to disagree
## with the rows either side of it on the same menu.
func _test_sub_exit_pops_one_level() -> void:
	var map_host: Node3D = FormationDetailTransition.new()
	map_host.host_mode = FormationDetailTransition.Host.MAP
	var roster_host: Node3D = FormationDetailTransition.new()
	add_child(map_host)
	add_child(roster_host)
	for _i in 4:
		await get_tree().process_frame

	var S = FormationDetailTransition.State
	# EQUIP and ABILITY reached FROM the Status screen — the only route the map host has.
	for sub in [S.EQUIP, S.ABILITY]:
		_seed_stack(map_host, [S.DETAIL, sub])
		_expect(map_host._sub_exit_returns_to_detail(),
			"MAP: ✕ out of state %d must return to the Status screen" % sub)
		map_host._exit_settled()
		_expect(map_host._stack == [S.DETAIL],
			"MAP: ✕ out of state %d must pop ONE level to DETAIL, got stack=%s" % [sub, map_host._stack])

		_seed_stack(roster_host, [S.DETAIL, sub])
		_expect(not roster_host._sub_exit_returns_to_detail(),
			"ROSTER: RE25 is unamended — ✕ out of state %d still unwinds" % sub)
		roster_host._exit_settled()
		_expect(roster_host._stack.is_empty(),
			"ROSTER: ✕ out of state %d must FULL-unwind (RE25), got stack=%s" % [sub, roster_host._stack])

	# CHANGE_JOB joined the split in ADR-0261 and is no longer exempt on the MAP host. Amendment 7
	# excluded it because "committing a job change is a destination, not a detour" — an argument
	# about the COMMIT, on a press where you did not commit. Left exempt, ✕ off Change Job landed on
	# the battlefield while ✕ off Item, one row up the same menu, landed on Status.
	_seed_stack(map_host, [S.DETAIL, S.CHANGE_JOB])
	_expect(map_host._sub_exit_returns_to_detail(),
		"MAP: ✕ out of CHANGE_JOB must return to the Status screen, like its sibling rows")
	map_host._exit_settled()
	_expect(map_host._stack == [S.DETAIL],
		"MAP: ✕ out of CHANGE_JOB must pop ONE level to DETAIL, got stack=%s" % [map_host._stack])

	_seed_stack(roster_host, [S.DETAIL, S.CHANGE_JOB])
	_expect(not roster_host._sub_exit_returns_to_detail(),
		"ROSTER: RE25 is unamended — the wheel is a takeover of the roster, and ✕ unwinds to it")
	roster_host._exit_settled()
	_expect(roster_host._stack.is_empty(),
		"ROSTER: ✕ out of CHANGE_JOB must FULL-unwind (RE25), got stack=%s" % [roster_host._stack])

	# The PICK level (ADR-0261) is the map host's floor — popping it empties the stack, which is what
	# makes it the level that releases the claims. Asserted here because the back grammar is now ONE
	# table and this is the table's guard: a PICK that unwound wholesale, or one that refused to pop,
	# would both leave the camera takeover held with no screen to justify it.
	_seed_stack(map_host, [S.PICK])
	map_host._exit_settled()
	_expect(map_host._stack.is_empty(),
		"MAP: ✕ out of PICK must empty the stack, got stack=%s" % [map_host._stack])

	# Status opened OVER a pick pops to the PICK — one level, like everything else on this host, but
	# NOT via the Amendment 7 return: that predicate asks "do I stay on a Status screen", and here
	# the Status screen is the thing leaving. The distinction is load-bearing, because it is what
	# `_on_detail_closed` reads to decide whether to reverse the camera pan — and reversing it here
	# would release the takeover that the pick underneath is still using to hold the tile cursor.
	_seed_stack(map_host, [S.PICK, S.DETAIL])
	_expect(not map_host._sub_exit_returns_to_detail(),
		"MAP: leaving a Status screen is not the Am.7 sub-screen RETURN to one")
	map_host._exit_settled()
	_expect(map_host._stack == [S.PICK],
		"MAP: ✕ out of Status-over-a-pick must pop ONE level to PICK, got stack=%s" % [map_host._stack])

	# The ○-press Status close is untouched: it always popped exactly one, on either host.
	for h in [map_host, roster_host]:
		_seed_stack(h, [S.DETAIL])
		h._exit_settled()
		_expect(h._stack.is_empty(), "DETAIL close must pop exactly the DETAIL screen")

	# The chrome beat's reverse must READ that predicate, not re-decide it — the descent is what
	# would dock the vitals pair onto a roster the map host has none of.
	_seed_stack(map_host, [S.DETAIL, S.EQUIP])
	var d := DetailScene.new()
	add_child(d)
	for _i in 4:
		await get_tree().process_frame
	map_host._detail = d
	map_host._chrome_enter_reverse()
	_expect(d._chrome_hold,
		"MAP: the EQUIP reverse must HOLD the chrome when it returns to the Status screen")
	_seed_stack(roster_host, [S.DETAIL, S.EQUIP])
	roster_host._detail = d
	roster_host._chrome_enter_reverse()
	_expect(not d._chrome_hold, "ROSTER: the EQUIP reverse must still DESCEND the chrome")

	map_host._detail = null
	roster_host._detail = null

	# The return must still LAND when there is nothing to widen. `exit_sub_mode` is idempotent, so on
	# a screen that never narrowed (the instant-teardown fallback, reached while the sub-screen is
	# still sliding in) its `opened` never fires — and a return that waits on it strands the player
	# on a menu-less screen with `settled` never sent.
	var landed := [false]
	map_host.settled.connect(func(_to): landed[0] = true, CONNECT_ONE_SHOT)
	_seed_stack(map_host, [S.DETAIL, S.EQUIP])
	map_host._return_sub_screen_to_detail()          # _detail is null — the degenerate case
	_expect(map_host._stack == [S.DETAIL],
		"a return with no overlay must still pop to DETAIL, got stack=%s" % [map_host._stack])
	_expect(landed[0], "a return with no overlay must still report settled — else nothing lands")

	d.queue_free()
	map_host.queue_free()
	roster_host.queue_free()


## An enemy's screen is the SAME screen, read-only: rows present, cursorable, painted through the
## ROM's own disabled shade band, and ○ refuses instead of choosing.
func _test_disabled_rows() -> void:
	var m := StartActionMenu.new()
	add_child(m)
	for _i in 3:
		await get_tree().process_frame

	var n := m.row_count()
	m.set_all_rows_disabled(true)
	_expect(m.row_count() == n, "disabled rows stay PRESENT — hiding them renumbers the list")
	_expect(m.disabled_rows().size() == n, "every row should be disabled, got %d" % m.disabled_rows().size())

	var refused := [-1]
	var chose := [-1]
	m.refused.connect(func(r: int): refused[0] = r)
	m.chosen.connect(func(r: int): chose[0] = r)
	m.move_down()
	_expect(m.selected_row() == 1, "a disabled row is still CURSORABLE (the glove walks onto it)")
	m.confirm()
	_expect(refused[0] == 1 and chose[0] == -1, "○ on a disabled row must REFUSE, not choose")

	m.set_disabled_rows([])
	m.confirm()
	_expect(chose[0] == 1, "re-enabling must restore the choice")

	# No new palette: the disabled ramp IS the one already ported from the ROM's Learn list.
	_expect(StartActionMenu._ROW_INK_OFF_LIGHT == LearnAbilityMenu.DIM_INKS[0]
			and StartActionMenu._ROW_INK_OFF_MID == LearnAbilityMenu.DIM_INKS[1]
			and StartActionMenu._ROW_INK_OFF_DARK == LearnAbilityMenu.DIM_INKS[2],
		"the disabled ink must be LearnAbilityMenu.DIM_INKS — ADR-0137 forbids inventing a palette")
	m.queue_free()


func _key(keycode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	return e


## Seed a coordinator's screen stack. Via `assign` because `_stack` is `Array[int]` and a plain
## `= [...]` of an untyped literal throws — inside an `await`ed case that aborts the rest of it
## SILENTLY, which is what the assertion COUNT in the PASS line exists to expose.
func _seed_stack(host: Node3D, states: Array) -> void:
	host._stack.assign(states)


func _expect(cond: bool, msg: String) -> void:
	# COUNTED, and the count goes in the PASS line. A coroutine error aborts the rest of an `await`ed
	# case SILENTLY, so a green summary does not by itself mean the assertions ran — the number does.
	_checks += 1
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


## ADR-0137 Amendment 4 — ONE INTENT PER BUTTON, mechanized.
##
## Prose could not hold this. While writing the amendment that removes double-bindings, the MENU
## action was put on Q — which is `rotate_camera_cw`. A new binding that squats on a key already
## meaning something is invisible to review and invisible at runtime (the loser just silently stops
## working), so the table has to be asserted, not described.
##
## Overlaps are admitted BY NAME, and each admitted pair is the SAME intent reached at two depths —
## never two intents on one button, which is the thing this asserts against:
##   ○  `ui_accept` / `cursor_confirm` — confirm. Two actions because the march can refuse the
##      cursor's ○ while a menu's ○ is never refusable (Amendment 2).
##   △  `unit_inspect` / `formation_start_menu` — "show me this unit's menus", on the map cursor and
##      one level in (Amendment 6).
##   d-pad  `ui_*` / `camera_*` — direction. `camera_*` is misnamed: it moves the tile CURSOR, and
##      PlayerCamera only reads it under the free-pan debug flag.
## None can contend, for one reason: while a screen is up it owns the WHOLE pad (`_claim_pad`) and
## marks events handled before `TileCursor._unhandled_input` ever sees them.
const _SHARED_BY_DESIGN := [
	["cursor_confirm", "ui_accept"],
	["formation_start_menu", "unit_inspect"],
	["camera_up", "ui_up"], ["camera_down", "ui_down"],
	["camera_left", "ui_left"], ["camera_right", "ui_right"],
]


## The actions THIS PROJECT defines and is therefore responsible for. Scoped deliberately: Godot
## ships ~120 built-in `ui_*` actions (ui_text_*, ui_graph_*, the file dialog...) that collide with
## each other constantly and are none of our business. Two of them DO overlap our pad —
## `ui_select` on pad 3 and `ui_colorpicker_delete_preset` on pad 2 — and both are inert here:
## nothing in this project drives Control focus traversal (Amendment 2 cleared `ui_focus_next` /
## `ui_focus_prev` for exactly that reason) and there is no ColorPicker in the game scenes. Noted
## rather than asserted, because we do not own them and cannot fix them from here.
const _OWNED_ACTIONS := [
	"ui_accept", "ui_cancel", "cursor_confirm", "unit_inspect", "formation_start_menu",
	"battle_start", "battle_pause", "rotate_camera_cw", "rotate_camera_ccw",
	"camera_up", "camera_down", "camera_left", "camera_right",
	"formation_sort_next", "formation_sort_prev",
	"ui_up", "ui_down", "ui_left", "ui_right",
]


func _test_one_intent_per_button() -> void:
	var by_binding := {}
	for action in _OWNED_ACTIONS:
		_expect(InputMap.has_action(action), "owned action '%s' is missing entirely" % action)
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			var slug := ""
			if ev is InputEventKey:
				slug = "key:%d" % (ev as InputEventKey).physical_keycode
			elif ev is InputEventJoypadButton:
				slug = "pad:%d" % (ev as InputEventJoypadButton).button_index
			else:
				continue
			if not by_binding.has(slug):
				by_binding[slug] = []
			(by_binding[slug] as Array).append(String(action))

	for slug in by_binding:
		var owners: Array = by_binding[slug]
		if owners.size() < 2:
			continue
		owners.sort()
		var ok := false
		for group in _SHARED_BY_DESIGN:
			if owners == group:
				ok = true
				break
		_expect(ok,
			"%s is bound to %s — one intent per button (ADR-0137 Am.4/6); admitted pairs are %s"
			% [slug, str(owners), str(_SHARED_BY_DESIGN)])

	# The table itself, so a binding cannot drift silently. Literals on purpose: reading these back
	# out of InputMap and comparing them to themselves would be a guard that cannot fail.
	var expect := {
		"ui_accept": ["key:4194309", "key:4194310", "pad:1"],   # ○  Enter / KP Enter
		"ui_cancel": ["key:4194308", "pad:0"],                  # ✕  Backspace
		"unit_inspect": ["key:4194306", "pad:3"],               # △  Tab
		"formation_start_menu": ["key:4194306", "pad:3"],       # △  Tab — same intent as unit_inspect
		"battle_pause": ["key:4194305", "pad:4"],               # SELECT  Esc
		"battle_start": ["key:32", "pad:6"],                    # START   Space
		# ADR-0268 dec. 6 — the shoulders rotate the camera on the real hardware and these two
		# carried no pad button at all. Paired BY SIDE with the keys already on them (Q is the
		# left key, so it takes L1). They are pinned HERE and not merely admitted, because the
		# whole reason they could be added without re-opening Amendment 4 is that they add no
		# ACTION: an unpinned binding on an existing action is exactly the silent drift this
		# literal table exists to catch.
		"rotate_camera_cw": ["key:81", "pad:9"],                # L1  Q
		"rotate_camera_ccw": ["key:69", "pad:10"],              # R1  E
	}
	for action in expect:
		var got: Array = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				got.append("key:%d" % (ev as InputEventKey).physical_keycode)
			elif ev is InputEventJoypadButton:
				got.append("pad:%d" % (ev as InputEventJoypadButton).button_index)
		_expect(got == expect[action],
			"%s should be bound to %s, got %s" % [action, str(expect[action]), str(got)])

	# Esc must NOT be cancel any more — that double-binding (cancel AND battle_pause) is half of
	# what this amendment removed, and it would come straight back if ui_cancel were ever deleted
	# from project.godot and fell through to Godot's default.
	for ev in InputMap.action_get_events("ui_cancel"):
		if ev is InputEventKey:
			_expect((ev as InputEventKey).physical_keycode != KEY_ESCAPE,
				"Esc is battle_pause ONLY — ui_cancel must not fall back to Godot's default")


## unit → Character, and the slot number the nameplate prints (ADR-0180).
##
## THE RED ARM THIS WAS WRITTEN AGAINST. `character_for_unit` used to key off
## `roster_index` / `roster_team` metas that only `BaseRoster.spawn_unit` ever set, so it
## returned **null for every navigator-deployed unit** — the deploy seam
## (`NavigatorMain._spawn_owned_unit`) set neither — and `slot_number_for` returned a
## hardcoded `1`. Both failures are SILENT: the map host binds a null and paints nothing,
## which reads exactly like "no unit under the cursor". A test that merely *calls* the two
## functions passes before the fix and after it. So the assertions below are written
## against a unit built the way the production deploy seam builds one ([UnitSpawn.build]),
## never the way the retired roster did, and they were confirmed RED against the pre-fix
## implementation (null, and 1).
##
## Scene-free: the resolution is static and reads the [CharacterCatalog] autoload, so this
## needs no map, no host and no battlefield.
func _test_character_resolution() -> void:
	var made: Array = []
	var units: Array = []
	for i in range(2):
		var c: Character = Character.create_default("Probe%d" % i, "4a", i == 1)
		c.slug = _PROBE_SLUGS[i]
		CharacterCatalog.register(c)
		CharacterCatalog.add_owned(c.slug)
		made.append(c)
		var u = UnitSpawn.build(c)
		add_child(u)
		units.append(u)
	await get_tree().process_frame

	# The resolve itself. Not "returns something" — returns THIS Character, by identity.
	for i in range(2):
		var got = FormationMapHost.character_for_unit(units[i])
		_expect(got != null, "character_for_unit(%s) must not be null" % _PROBE_SLUGS[i])
		_expect(got == made[i],
			"character_for_unit must return the Character the unit was built from (%s)"
			% _PROBE_SLUGS[i])

	# The slot number is the unit's 1-based place in the OWNED order — the same number the
	# out-of-battle screen shows it under. The second probe is what makes this a test: a
	# hardcoded 1 satisfies the first one.
	_expect(FormationMapHost.slot_number_for(units[0]) == _slot_of(_PROBE_SLUGS[0]),
		"slot_number_for(probe 0) should be its 1-based owned position")
	_expect(FormationMapHost.slot_number_for(units[1]) == _slot_of(_PROBE_SLUGS[1]),
		"slot_number_for(probe 1) should be its 1-based owned position, NOT 1")
	_expect(_slot_of(_PROBE_SLUGS[1]) == _slot_of(_PROBE_SLUGS[0]) + 1,
		"the two probes must be adjacent in owned order, or the check above is vacuous")

	# OWNERSHIP is the other question this meta used to answer, and it is the one with a
	# VISIBLE consequence: `selection_is_owned` gates whether the START menu's action rows go
	# disabled. Reading `roster_team` it answered "owned" for anything BaseRoster did not
	# spawn — every navigator-deployed unit AND every ENTD enemy — so the enemy screen offered
	# live action rows. Confirmed RED here against the pre-fix implementation.
	var host := FormationMapHost.new()
	add_child(host)
	for _i in 4:
		await get_tree().process_frame

	var stranger: Character = Character.create_default("Stranger", "4a", false)
	stranger.slug = _STRANGER_SLUG
	CharacterCatalog.register(stranger)   # registered, deliberately NOT owned — an ENTD enemy
	var stranger_unit = UnitSpawn.build(stranger)
	add_child(stranger_unit)
	await get_tree().process_frame

	host._selected_unit = units[0]
	_expect(host.selection_is_owned(), "an owned unit's selection is owned")
	host._selected_unit = stranger_unit
	_expect(not host.selection_is_owned(),
		"a registered-but-NOT-owned unit (an ENTD enemy) must NOT read as owned")
	host._selected_unit = null
	_expect(host.selection_is_owned(), "no selection degrades to owned (the roster host's answer)")
	host.queue_free()
	stranger_unit.queue_free()
	CharacterCatalog.unregister(_STRANGER_SLUG)

	# A unit nobody built from a Character (a ghost actor, a bare instance) has no identity
	# to resolve, and must answer null rather than the first owned entry.
	var bare := Node3D.new()
	add_child(bare)
	_expect(FormationMapHost.character_for_unit(bare) == null,
		"a unit with no character_slug meta resolves to null, not to a default")
	_expect(FormationMapHost.slot_number_for(bare) == 0,
		"an unresolvable unit has NO slot — 0, which the nameplate declines to print")
	bare.queue_free()

	for u in units:
		u.queue_free()
	for slug in _PROBE_SLUGS:
		CharacterCatalog.remove_owned(slug)
		CharacterCatalog.unregister(slug)


## Slugs that cannot collide with a real cast entry, so the probes are additive.
const _PROBE_SLUGS := ["__mapshost_probe_a", "__mapshost_probe_b"]

## A catalogue identity that is registered but NOT in the owned overlay — the case `roster_team`
## got wrong.
##
## It is NOT the shape of a real ENTD enemy, and saying so was this fixture's own defect: every
## ENTD unit fails one step earlier — it is not in the catalogue at all — so this arm passed
## through the whole of ADR-0180 Amendment 2. `_test_uncatalogued_units_resolve` is the arm that
## builds the production shape; this one keeps covering the overlay question on its own.
const _STRANGER_SLUG := "__mapshost_probe_stranger"


## The 1-based owned position `slot_number_for` is expected to report — derived from the
## live overlay, not hardcoded, so seeding order cannot silently drift the expectation.
func _slot_of(slug: String) -> int:
	return int(CharacterCatalog.owned_slugs().find(slug)) + 1


## The population `character_for_unit` resolves against is NOT closed — ADR-0180 Amendment 2.
##
## THE RED ARM THIS WAS WRITTEN AGAINST, and why the arm above could not be it. That one builds
## its "ENTD enemy" by REGISTERING a Character and leaving it out of the owned overlay. Every
## real ENTD unit fails one step earlier: it is not in the catalogue at all. Measured on the
## arena's own Gariland cast, 6 of 13 units resolved to null —
##   - the five ENTD generics, whose slug is the EMPTY STRING (`Character.create_default` leaves
##     the slug for "Catalog promotion" and a nameless enemy is never promoted), and
##   - **Delita**, the ENTD-blue guest fighting on team0, whose slug is real and registered by
##     nobody: the arena folds `owned_seed_deltas()`, which is the `own: true` subset, and an
##     appearance is not one.
## On the map host a null is indistinguishable from an empty tile, so those six units had no
## hover pair and no nameplate — the reported defect.
##
## Both shapes are asserted, and the ownership answer with them: an unresolvable unit degrades
## to OWNED (`selection_is_owned`), so before the fix an enemy would have been handed live
## action rows the moment it resolved at all. Fixing the resolve without the ownership arm would
## trade an invisible enemy for an equippable one.
func _test_uncatalogued_units_resolve() -> void:
	var host := FormationMapHost.new()
	add_child(host)
	for _i in 4:
		await get_tree().process_frame

	# 1. The ENTD GENERIC — no slug at all. `create_default` is the exact constructor
	#    `Character.from_entd_slot` runs for a slot with no `special_name`.
	var generic: Character = Character.create_default("Squire", "4a", false)
	_expect(generic.slug == "",
		"the fixture must have an EMPTY slug or this arm is not the ENTD generic case")
	var generic_unit = UnitSpawn.build(generic)
	add_child(generic_unit)

	# 2. The NAMED but unregistered unit — Delita's shape. A real slug, no registration.
	var guest: Character = Character.create_default("Delita", "4a", false)
	guest.slug = _GUEST_SLUG
	_expect(CharacterCatalog.get_character(_GUEST_SLUG) == null,
		"the fixture must be UNREGISTERED or this arm is the already-covered stranger case")
	var guest_unit = UnitSpawn.build(guest)
	add_child(guest_unit)
	await get_tree().process_frame

	_expect(FormationMapHost.character_for_unit(generic_unit) == generic,
		"an ENTD generic (empty slug, uncatalogued) must resolve to the Character it was built"
		+ " from — a null here IS the empty-tile bug")
	_expect(FormationMapHost.character_for_unit(guest_unit) == guest,
		"an unregistered NAMED unit (the Delita case) must resolve to its own Character")

	# Ownership: neither is in the owned overlay, so neither may read as owned. This is what
	# keeps the enemy screen READ-ONLY (`_apply_ownership` → `set_all_rows_disabled`).
	host._selected_unit = generic_unit
	_expect(not host.selection_is_owned(),
		"an ENTD generic must NOT read as owned — an owned answer hands the enemy live rows")
	host._selected_unit = guest_unit
	_expect(not host.selection_is_owned(),
		"an ENTD-blue GUEST is not yours to re-equip (ADR-0180 dec. 2 names Delita by name)")

	# NO SLOT IS 0, AND 0 IS NOT A NUMBER THE PLATE PRINTS. This read `1` and asserted `1`,
	# which put a confident "1" on the plate over every enemy in the game — the same number
	# Ramza's plate carries, on a unit that is in no overlay at all. `slot_number_for`'s own
	# `find` already yields -1 here; 0 is what that means, and `UIUnitNameplate.set_view`
	# skips the digits for it. The blue orb bullet is a separate mount, so the plate keeps
	# its bullet and loses only the number.
	_expect(FormationMapHost.slot_number_for(generic_unit) == 0,
		"a unit outside the owned overlay has NO slot — 0, not a false 1")

	# The slug lookup stays the FALLBACK, not a casualty: a unit whose Character reference is
	# gone still resolves through the catalogue. Asserted by REMOVING the reference meta.
	var catalogued: Character = Character.create_default("Catalogued", "4a", false)
	catalogued.slug = _FALLBACK_SLUG
	CharacterCatalog.register(catalogued)
	var owned_unit = UnitSpawn.build(catalogued)
	add_child(owned_unit)
	await get_tree().process_frame
	owned_unit.remove_meta(UnitSpawn.CHARACTER_META)
	_expect(FormationMapHost.character_for_unit(owned_unit) == catalogued,
		"with no reference meta the SLUG must still resolve — the fallback is load-bearing for"
		+ " a unit built by another seam")
	CharacterCatalog.unregister(_FALLBACK_SLUG)

	host.queue_free()
	generic_unit.queue_free()
	guest_unit.queue_free()
	owned_unit.queue_free()


## THE STAMP ARM (reports 3 and 5) — the identity is stamped at the BIND seam.
##
## THE RED ARM THIS WAS WRITTEN AGAINST, and the third time this function has been fixed by a
## change that missed a population. `UnitSpawn.build()` stamps both metas and the two arms above
## prove it — but the ENTD cast never passes through `build()`. `ScenarioPlayerScene._spawn_units`
## mints those units itself (its own comment says it *"bypasses UnitSpawn.build"*) and the
## navigator makes them combat-ready through `bind_for_combat` alone, which stamped nothing. So
## every ENTD unit reached the map host carrying NO identity meta, `character_for_unit` returned
## null, and on that host a null is indistinguishable from an empty tile: no vitals and no
## nameplate under the cursor (report 3), and Tab refused to open the screen (report 5).
##
## The fixture is instanced BARE — never through `build()` — because a unit that went through
## `build()` is already stamped and this arm would pass on the pre-fix tree.
func _test_bind_stamps_identity() -> void:
	var c: Character = Character.create_default("BindProbe", "4a", false)
	c.slug = _BIND_SLUG
	var unit = load(_UNIT_SCENE).instantiate()
	add_child(unit)
	await get_tree().process_frame
	_expect(not unit.has_meta(UnitSpawn.CHARACTER_META),
		"the fixture must start UNSTAMPED, or this arm cannot see the bind do it")

	UnitSpawn.bind_for_combat(unit, c, 0)
	_expect(unit.get_meta(UnitSpawn.CHARACTER_META, null) == c,
		"bind_for_combat must stamp CHARACTER_META — the ENTD population reaches the map host"
		+ " through this seam and no other")
	_expect(String(unit.get_meta(UnitSpawn.CHARACTER_SLUG_META, "")) == _BIND_SLUG,
		"and CHARACTER_SLUG_META with it — the DURABLE key stops being build-only")
	_expect(FormationMapHost.character_for_unit(unit) == c,
		"a bind-only unit resolves to its Character — the null here IS reports 3 and 5")

	# ABOVE THE GUARD, and this is the leg that says so. `bind_for_combat` returns early on a
	# Character with no progression (it cannot fight), and a stamp written below that return
	# would leave exactly the bare identities the map host cannot resolve — which is the shape
	# of both previous fixes to this function. The unit is not BOUND here; it is IDENTIFIED.
	var bare_identity: Character = Character.create_default("BareProbe", "4a", false)
	bare_identity.slug = _BIND_BARE_SLUG
	bare_identity.progression = null
	var bare_unit = load(_UNIT_SCENE).instantiate()
	add_child(bare_unit)
	await get_tree().process_frame
	UnitSpawn.bind_for_combat(bare_unit, bare_identity, 0)
	_expect(FormationMapHost.character_for_unit(bare_unit) == bare_identity,
		"a Character the bind REFUSED is still stamped — the stamp sits above the guard")

	unit.queue_free()
	bare_unit.queue_free()


## The one spawn scene, named here because this arm must NOT go through `UnitSpawn.build`.
const _UNIT_SCENE := "res://assets/scenes/Unit.tscn"

## Two unregistered slugs for the stamp arm: the identity it asserts is the OBJECT, so neither
## needs the catalogue, and staying out of it keeps the arm about the meta rather than the lookup.
const _BIND_SLUG := "__mapshost_probe_bind"
const _BIND_BARE_SLUG := "__mapshost_probe_bind_bare"


## An unregistered slug, so the guest fixture cannot be satisfied by a real cast entry.
const _GUEST_SLUG := "__mapshost_probe_guest"

## A REGISTERED slug, for the arm that proves the catalogue lookup survives as the fallback.
const _FALLBACK_SLUG := "__mapshost_probe_fallback"


## ADR-0137 Amendment 9 — the docked pair repaints from the CURSOR, never from a grid cell.
##
## THE RED ARM THIS WAS WRITTEN AGAINST. `FormationScene._update_vitals_for_selection` indexes
## `_roster_characters()` by `selected_cell.y * COLS + selected_cell.x`. The map host has no grid
## and never writes `selected_cell`, so the index was a constant 0 and the pair was repainted with
## the FIRST OWNED UNIT — Ramza — whoever the cursor was actually over. Nothing on the way IN
## reaches it (hover and open both go through `_push_pair_views`), so it only fired on the way
## OUT: `FormationDetailTransition._restore_formation` calls `refresh_selection_readouts()`, which
## is on the ✕-out-of-DETAIL tail. Tab, then Backspace, and the pair was Ramza's.
##
## Not vacuous, and NOT satisfiable by "the pair holds something": the fixture deliberately hovers
## the unit at owned position 1, so an implementation that still reads cell 0 paints a DIFFERENT
## name. Confirmed RED against the inherited implementation before being trusted.
func _test_vitals_repaint_follows_the_cursor() -> void:
	var owned: Array = CharacterCatalog.owned_units()
	if owned.size() < 2:
		_expect(false, "fixture needs >= 2 owned units to tell cell 0 from the cursor")
		return
	var first = owned[0]     # what the inherited grid index resolves to
	var other = owned[1]     # who the cursor is actually over

	var host := FormationMapHost.new()
	add_child(host)
	for _i in 4:
		await get_tree().process_frame
	_expect(host._cluster != null and is_instance_valid(host._cluster),
		"the map host must build its unbound cluster, or this arm asserts on nothing")

	# The state the ✕ tail finds: the cursor is over `other`, and the screen that just closed was
	# `other`'s too. Both fields are set, so a repaint that reads EITHER is right here.
	host._hovered = other
	host._selected = other
	host.refresh_selection_readouts()   # the exact call `_restore_formation` makes
	_expect(host._cluster._nameplate_view.get("name", "") == other.display_name,
		"the pair must repaint with the CURSORED unit (%s), got '%s'"
			% [other.display_name, str(host._cluster._nameplate_view.get("name", ""))])
	_expect(host._cluster._nameplate_view.get("name", "") != first.display_name
			or other.display_name == first.display_name,
		"repainting with owned position 0 (%s) is the defect — the map host has no cell 0"
			% first.display_name)
	_expect(host._cluster._unit_view.get("name", "") == other.display_name,
		"the VITALS half must follow too — one repaint, both views")

	# The cursor MOVED off the unit whose screen was open. The pair follows the cursor, which is
	# the user's own statement of the fix ("they should go back to whoever the cursor is over").
	host._hovered = first
	host.refresh_selection_readouts()
	_expect(host._cluster._nameplate_view.get("name", "") == first.display_name,
		"after the cursor moves, the repaint follows it, not the unit that was inspected")

	# No cursor at all (the pair is parked OFF and nothing is hovered) — fall back to the last
	# selection rather than to a grid cell this host does not have.
	host._hovered = null
	host._selected = other
	host.refresh_selection_readouts()
	_expect(host._cluster._nameplate_view.get("name", "") == other.display_name,
		"with nothing hovered the repaint degrades to the SELECTION, never to owned position 0")

	host.queue_free()


## A catalogue identity for the LIVE-HP arm below — registered + owned so the hover path resolves
## it exactly the way a deployed player unit resolves.
const _LIVE_SLUG := "__mapshost_probe_live"


## THE VITALS PANEL MUST READ THE LIVE UNIT, NOT THE CATALOGUE IDENTITY.
##
## [method FormationScene.vitals_view_from_character] is the OUT-OF-BATTLE builder and it cannot
## report damage: [UnitProgression] holds no current HP at all — only `get_effective_hp()` — so that
## builder writes `current_hp = max_hp` BY CONSTRUCTION. On the roster screen that is right (nobody
## has been hit). On the battlefield the map host pushed the same dict, so the hover panel reported
## FULL HP for every unit in the fight however hurt it was, and MP that never spent. Reported
## against `NavigatorMain`: "let it run so units get damaged some, move the cursor over them and
## they have full HP."
##
## The live half is the [UnitStats] on the battlefield [Unit] ([CombatLoop] writes damage to
## `unit_stats.current_hp`), which is why the fix threads the unit the cursor resolved into the
## repaint instead of re-deriving vitals from the identity.
func _test_vitals_read_the_live_unit() -> void:
	var probe: Array = await _spawn_damaged_probe("LiveProbe", _LIVE_SLUG)
	var c: Character = probe[0]
	var unit = probe[1]
	var full := int(unit.unit_stats.max_hp)
	var full_mp := int(unit.unit_stats.max_mp)
	var hurt := int(unit.unit_stats.current_hp)

	var host := FormationMapHost.new()
	add_child(host)
	for _i in 4:
		await get_tree().process_frame
	_expect(host._cluster != null and is_instance_valid(host._cluster),
		"the map host must build its cluster, or this arm asserts on nothing")

	# The production hover path, driven the way the tile cursor drives it. No CursorRig: the unit
	# the repaint reads must be the one the MOVE resolved, not one re-fetched from a rig — that
	# re-fetch is the plumbing this arm pins.
	host._unit_at = func(_g: Vector2i): return unit
	host._on_cursor_moved(Vector2i(3, 4))

	var panel := host._cluster.vitals_panel()
	_expect(panel != null and is_instance_valid(panel), "the cluster must hold a vitals panel")
	var applied: Dictionary = panel.applied_hp_mp() if panel != null else {}
	_expect(int(applied.get("hp", -1)) == hurt,
		"the gauge must show the LIVE HP %d, got %d (max is %d — reading %d means the panel is"
			% [hurt, int(applied.get("hp", -1)), full, full]
			+ " still built from the catalogue identity, which has no current HP)")
	_expect(int(applied.get("mp", -1)) == 0,
		"MP is live too — spent MP must read 0, got %d (max %d)"
			% [int(applied.get("mp", -1)), full_mp])
	# The DENOMINATOR still comes from the identity's effective stat — the fix overlays the current
	# values, it does not replace the view.
	_expect(int(host._cluster._unit_view.get("max_hp", -1)) == full,
		"max HP must stay the identity's effective %d, got %d"
			% [full, int(host._cluster._unit_view.get("max_hp", -1))])
	_expect(String(host._cluster._unit_view.get("name", "")) == c.display_name,
		"the name still comes from the Character (%s), got '%s'"
			% [c.display_name, String(host._cluster._unit_view.get("name", ""))])

	# PARKED CURSOR. The player who watches a unit get hit is not moving the cursor, so the repaint
	# that fires on a MOVE cannot be the only one — the panel would be correct until the next hit.
	# Drive it the way the readback does: write the field, then emit (`CombatLoop._apply_hp_change`
	# does exactly those two lines).
	var hurt_again := hurt / 2
	unit.unit_stats.current_hp = hurt_again
	unit.unit_stats.hp_changed.emit(hurt, hurt_again)
	var parked: Dictionary = panel.applied_hp_mp() if panel != null else {}
	_expect(int(parked.get("hp", -1)) == hurt_again,
		"a hit under a PARKED cursor must move the gauge to %d without a cursor move, got %d"
			% [hurt_again, int(parked.get("hp", -1))])

	# NO LIVE UNIT — the harness / benched-pick path. The identity view must survive unchanged
	# rather than degrading to zeros.
	host.show_character(c)
	var no_unit: Dictionary = panel.applied_hp_mp() if panel != null else {}
	_expect(int(no_unit.get("hp", -1)) == full,
		"with no battlefield unit the panel falls back to the identity's full %d, got %d"
			% [full, int(no_unit.get("hp", -1))])

	host.queue_free()
	unit.queue_free()
	CharacterCatalog.remove_owned(_LIVE_SLUG)
	CharacterCatalog.unregister(_LIVE_SLUG)


## A second catalogue identity, for the STATUS-SCREEN arm below. Distinct from `_LIVE_SLUG` so the
## two arms cannot contaminate each other's owned overlay — each registers and unregisters its own.
const _STATUS_SLUG := "__mapshost_probe_status"


## THE BATTLEFIELD STATUS SCREEN MUST READ THE LIVE UNIT TOO.
##
## The hover pair was fixed above; the screen you reach with Tab/○ over the same unit was not.
## [FormationDetailTransition] pushed the bare [method FormationScene.vitals_view_from_character]
## into its [DetailScene], and that builder writes `current_hp = max_hp` BY CONSTRUCTION — so the
## Status screen reported FULL HP for a unit the hover panel one keypress earlier had just reported
## as hurt. Same defect, same cause, one surface further in.
##
## The coordinator cannot reach the live unit on its own: it holds a [Character], and the identity
## is precisely the object that has no current HP. Only the MAP host knows which battlefield [Unit]
## the tile cursor latched, so the fix asks it — [method FormationMapHost.selected_battle_unit_for]
## — and degrades to the identity builder on the roster host, where full HP is the true answer.
##
## Asserted on [method DetailScene.rendered_vitals_hp_mp], the numbers the gauges ACTUALLY applied,
## not the dict handed in: a view that reaches the panel and is then overwritten by the preview gate
## is a bug this arm has to be able to see.
func _test_status_screen_reads_the_live_unit() -> void:
	var probe: Array = await _spawn_damaged_probe("StatusProbe", _STATUS_SLUG)
	var c: Character = probe[0]
	var unit = probe[1]
	var full := int(unit.unit_stats.max_hp)
	var full_mp := int(unit.unit_stats.max_mp)
	var hurt := int(unit.unit_stats.current_hp)

	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.host_mode = FormationDetailTransition.Host.MAP
	host.name = "StatusProbeHost"
	add_child(host)
	for _i in 4:
		await get_tree().process_frame
	var map = host._formation
	_expect(map != null and map is FormationMapHost,
		"the MAP coordinator must build a FormationMapHost, or this arm asserts on nothing")
	if map == null or not (map is FormationMapHost):
		host.queue_free(); unit.queue_free()
		CharacterCatalog.remove_owned(_STATUS_SLUG); CharacterCatalog.unregister(_STATUS_SLUG)
		return

	# LATCH the selection through the production door — △/Tab over the unit is the reported gesture
	# ("press Tab over one and look at the panel"). `_open_for` is what pairs the identity with the
	# battlefield unit, and that pairing is the whole seam the fix hangs on.
	map._unit_at = func(_g: Vector2i): return unit
	map._on_cursor_inspected(Vector2i(3, 4))
	_expect(map.selected_character() == c,
		"the inspect door must latch the identity under the cursor as the selection")
	_expect(map.selected_battle_unit_for(c) == unit,
		"the host must hand back the battlefield unit it latched beside that identity")

	# The inspect door ENTERS the screen rather than building it, and the entry is deferred (the map
	# recipe pans before the panels). So settle it rather than calling `open_detail` here: a direct
	# build races the deferred one, which frees it — and a freed DetailScene aborts the whole arm
	# silently in an async test, which is a red this arm must never be able to report as green.
	var d: DetailScene = null
	for _i in 240:
		await get_tree().process_frame
		var cur := host.detail_overlay()
		if cur != null and is_instance_valid(cur) and cur == d:
			break
		d = cur
	_expect(d != null and is_instance_valid(d),
		"Tab/△ over a battlefield unit must settle a DetailScene, got none (state=%d)"
			% host.current_state())
	if d == null or not is_instance_valid(d):
		host.queue_free(); unit.queue_free()
		CharacterCatalog.remove_owned(_STATUS_SLUG); CharacterCatalog.unregister(_STATUS_SLUG)
		return

	var applied: Dictionary = d.rendered_vitals_hp_mp()
	_expect(int(applied.get("hp", -1)) == hurt,
		"the Status screen gauge must show the LIVE HP %d, got %d (max is %d — reading %d means the"
			% [hurt, int(applied.get("hp", -1)), full, full]
			+ " screen is still built from the catalogue identity, which has no current HP)")
	_expect(int(applied.get("mp", -1)) == 0,
		"MP is live on the Status screen too — spent MP must read 0, got %d (max %d)"
			% [int(applied.get("mp", -1)), full_mp])

	# -------------------------------------------------------------------------------------------
	# EQUIPPING ON THE BATTLEFIELD: the numerator must NOT heal, and the denominator MUST move.
	#
	# This is the arm the build-time one cannot stand in for. The two equip repaint sites exist
	# precisely BECAUSE equipment moves max HP, and their roster guards
	# (FormationEquipVitalsRefreshTest / FormationEquipRemoveVitalsTest) assert the identity's
	# numbers — where current == max by construction, so a view that reported either one would look
	# identical. Only a DAMAGED unit separates them, and only the battlefield has one.
	#
	# The rule being pinned: current HP is the unit's and a helmet does not heal it; max HP is the
	# progression's and a helmet raises it. `UnitStats.max_hp` already delegates to
	# `progression.get_effective_hp()`, so the denominator is live on the same object the numerator
	# comes off — which is why one overlay gets both halves right and no clamp is involved.
	# -------------------------------------------------------------------------------------------
	# The START menu is opened EXPLICITLY rather than waited for. △ does bring it up on settle
	# (ADR-0137 Am.6), but that is `_test_one_intent_per_button`'s claim, not this arm's — and
	# hanging this arm off it would make an unrelated regression there read as a vitals failure.
	var m := host.open_action_menu()
	_expect(m != null and is_instance_valid(m),
		"the Status screen must open a START menu (state=%d)" % host.current_state())
	if m == null or not is_instance_valid(m):
		host.queue_free(); unit.queue_free()
		CharacterCatalog.remove_owned(_STATUS_SLUG); CharacterCatalog.unregister(_STATUS_SLUG)
		return
	_expect(not m.is_row_disabled(0),
		"the probe is OWNED and no `steerable` gate is wired, so the Item row must be live —"
			+ " a disabled row would make every assertion below vacuous")
	m.confirm()                                        # row 0 "Item" -> State.EQUIP
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	var m2 := host.action_menu()
	if m2 != null and is_instance_valid(m2):
		m2.confirm()                                   # row 0 "Equip" -> §15.25 slot focus
	_expect(d.is_slot_focused(), "did not reach Eqp slot focus on the MAP host")

	host._input(_action("ui_down"))
	host._input(_action("ui_down"))                    # -> HEAD
	_expect(d.slot_row() == UnitProgression.EquipSlot.HEAD, "slot cursor not on HEAD")
	var max_before := int(unit.unit_stats.max_hp)
	host._input(_action("ui_accept"))                  # open the HEAD picker
	var p = host.equip_picker()
	_expect(p != null, "HEAD picker did not open on the MAP host")
	if p == null:
		host.queue_free(); unit.queue_free()
		CharacterCatalog.remove_owned(_STATUS_SLUG); CharacterCatalog.unregister(_STATUS_SLUG)
		return
	var target := -1
	for i in p.entries.size():
		if int(p.entries[i].get("id", -1)) == HP_HELMET:
			target = i
			break
	_expect(target >= 0, "HP helmet %d not offered in the HEAD catalog (test setup)" % HP_HELMET)
	if target >= 0:
		var guard := 0
		while p.selected_row() != target and guard < 400:
			host._input(_action("ui_down"))
			guard += 1
		host._input(_action("ui_accept"))              # COMMIT
		for _i in 300:
			await get_tree().process_frame
			if host.equip_picker() == null and not d.is_vitals_preview():
				break
		var max_after := int(unit.unit_stats.max_hp)
		_expect(max_after > max_before,
			"test setup: the helmet did not raise the live unit's max HP (%d -> %d)"
				% [max_before, max_after])
		_expect(not d.is_vitals_preview(), "still in vitals preview after commit+close (gauge on dashes)")
		var after: Dictionary = d.rendered_vitals_hp_mp()
		_expect(int(after.get("hp", -1)) == hurt,
			"a helmet must not HEAL: the gauge must still read the live %d, got %d — reading %d means"
				% [hurt, int(after.get("hp", -1)), max_after]
				+ " the equip repaint reverted to the identity, which has no current HP")
		# The other half, and the reason the equip sites exist at all. Asserted on the panel's OWN
		# denominator, not on the view dict: a numerator that survived while the denominator froze
		# would be a different bug wearing the same green.
		_expect(int(after.get("hp_max", -1)) == max_after,
			"the DENOMINATOR must follow the equipment: expected %d, the gauge applied %d"
				% [max_after, int(after.get("hp_max", -1))])

		# ...AND THE OTHER DIRECTION, which is the half that could produce an impossible panel.
		# Take the unit to the RAISED full, then strip the helmet: max collapses back under the
		# numerator. Nothing in this screen clamps — `vitals_view_for` copies both halves straight
		# off the [UnitStats] — so a gauge reading `151/31` would be the honest consequence of the
		# fix if the MODEL did not already handle it. It does:
		# `UnitStats._on_progression_stats_changed` rides the progression's `stats_changed` and
		# clamps current DOWN to the new max (never up — a helmet must not heal, which is the assert
		# above). Pinned here because this arm is what made that clamp OBSERVABLE: on the roster,
		# current == max by construction, so its removal could not show up as a wrong number
		# anywhere, and the first symptom would be an overflowing bar on a battlefield.
		unit.unit_stats.current_hp = max_after
		_strip_head_slot(c)
		# Repainted through the coordinator's OWN funnel and read back off the GAUGE, not off the
		# dict: a view can reach the panel and be overwritten by the preview gate before anything
		# renders, and asserting on the dict we just built cannot tell those apart.
		d.set_unit_view(host._vitals_view(c))
		var stripped: Dictionary = d.rendered_vitals_hp_mp()
		_expect(int(stripped.get("hp_max", -1)) == max_before,
			"stripping the helmet must return the denominator to %d, the gauge applied %d"
				% [max_before, int(stripped.get("hp_max", -1))])
		_expect(int(stripped.get("hp", -1)) == max_before,
			"a numerator above the denominator is not a state the game can be in: current HP must"
				+ " clamp DOWN to %d when the helmet comes off, the gauge applied %d"
				% [max_before, int(stripped.get("hp", -1))])

	host.queue_free()
	unit.queue_free()
	await get_tree().process_frame
	CharacterCatalog.remove_owned(_STATUS_SLUG)
	CharacterCatalog.unregister(_STATUS_SLUG)

	# The funnel census MOVED to tools/check_vitals_funnel.py — see the note below.


## Strip the HEAD slot straight off the progression — NOT through §15.31's slot-remove screen, which
## reaches the same `unequip_item` by a much longer road. Named for the slot because the slot is the
## point: it is the one the helmet went into above.
##
## What that costs is stated rather than hidden: the equip-REMOVE call site
## (`_remove_focused_slot`) is therefore NOT driven by this arm. It is covered structurally, by the
## funnel census below, and behaviourally on the roster host by FormationEquipRemoveVitalsTest.
func _strip_head_slot(c) -> void:
	c.progression.unequip_item(UnitProgression.EquipSlot.HEAD)


## A real progression-backed battlefield unit, already HURT — the shared fixture for both live-vitals
## arms (the hover pair, and the Status screen).
##
## Registered + owned so the catalogue resolves it exactly the way a deployed player unit resolves;
## `bind_for_combat` is what stamps the identity back onto the node and gives [UnitStats] its
## progression, which is what makes `max_hp` a REAL number instead of the 100 default. The damage is
## written the way the GPU readback writes it (`CombatLoop._apply_hp_change` sets
## `unit_stats.current_hp`), because a unit hurt any other way would not prove anything about the
## path that actually hurts units.
##
## Returns `[Character, Unit]`. Half HP and zero MP: both arms need current != max on BOTH rows, or
## a panel reading the identity's full values would be indistinguishable from a correct one.
func _spawn_damaged_probe(display_name: String, slug: String) -> Array:
	var c: Character = Character.create_default(display_name, "4a", false)
	c.slug = slug
	CharacterCatalog.register(c)
	CharacterCatalog.add_owned(c.slug)
	var unit = UnitSpawn.build(c)
	add_child(unit)
	await get_tree().process_frame
	UnitSpawn.bind_for_combat(unit, c, 0)
	var full := int(unit.unit_stats.max_hp)
	_expect(full > 2,
		"the probe needs a real max HP (got %d) or 'damaged' is not a distinct value — a unit whose"
			% full + " bind failed reads the 100 default and every arm below goes vacuous")
	unit.unit_stats.current_hp = full / 2
	unit.unit_stats.current_mp = 0
	return [c, unit]


## THE FUNNEL IS THE WHOLE FIX, so make the funnel checkable — AND THAT CHECK NO
## LONGER LIVES HERE. It is `tools/check_vitals_funnel.py`, run by the pre-flight.
##
## It moved for SCOPE, not for speed, and the distinction is worth stating because the
## cheap reading is wrong: this test boots anyway, so the census cost it nothing, and a
## pre-flight step costs SERIAL wall clock at any N (charter clause 15 — measured at
## 0.063 s, against a 0.05 s median step). What the version here could never do is see a
## fifth push site in a DIFFERENT file: it opened `FormationDetailTransition.gd` by name.
## The builder is named in five production files, and the guard now holds a row for each.
##
## Both properties earned here survive the move, and the guard says why at each:
##   * it counts the BUILDER, not the push — `var v := ...` + `set_unit_view(v)` walks
##     past a push-shaped match while reintroducing the whole bug (seeded, confirmed);
##   * it strips comment lines, so a file's own prose cannot answer for its code. That
##     one got STRONGER by going repo-wide: three production files name the builder
##     ONLY in prose, so without the strip a clean tree reds three times.
##
## The two arms above still prove two of the four `set_unit_view` sites read the LIVE
## unit, which is the behavioural half no static guard can reach.


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev
