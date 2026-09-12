extends Node3D

## Guards the two ○-press REFINEMENTS (2026-08-05, user "great start but needs refining"):
##
## (1) BAND CROSS-FADE (§15.6): as the vitals pair slides bottom→top the roster's BOTTOM band
##     fades OUT while the Status screen's TOP stripe fades IN — not a binary enable. Locks the
##     pure `band_crossfade` curve AND that the transition drives both `full_sub`s through it.
##
## (2) OVERLAY DEPTH LIFT (ADR-0077): overlaid over the formation roster, the WHOLE Status
##     screen must sort NEARER than the formation grid (units at RP_UNIT_BODY=5, info panel 14)
##     so the menus occlude the units and the stripe darkens them. Locks the rung arithmetic +
##     that `overlay_rung_offset` is threaded into the shared cluster + nameplate (+ live Z when
##     the fold is active).

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")
const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")
const UnitInfoCluster = preload("res://src/ui3/UnitInfoCluster.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

const TICK := 2.0 / 60.0

var _failed := false


func _ready() -> void:
	_test_crossfade_curve()
	_test_transition_drives_crossfade()
	_test_overlay_rung_arithmetic()
	_test_overlay_offset_threaded()

	if _failed:
		print("[FAIL] FormationDetailRefine test")
	else:
		print("[PASS] FormationDetailRefine: band cross-fade + overlay depth lift (§15.6 / ADR-0077)")
	get_tree().quit()


## (1a) The pure curve: bottom full→gone by s=0.6; top hidden→full, ramping s=0.4→1.0.
func _test_crossfade_curve() -> void:
	var at_start := DetailScene.band_crossfade(0.0)
	_expect(is_equal_approx(at_start.x, 1.0) and is_equal_approx(at_start.y, 0.0),
		"crossfade(0): want (1,0) got %s" % at_start)
	var at_end := DetailScene.band_crossfade(1.0)
	_expect(is_equal_approx(at_end.x, 0.0) and is_equal_approx(at_end.y, 1.0),
		"crossfade(1): want (0,1) got %s" % at_end)
	# Bottom gone by 0.6; top not yet started before 0.4 (a clean "bottom out THEN top in").
	_expect(is_equal_approx(DetailScene.band_crossfade(0.6).x, 0.0),
		"bottom band not gone by s=0.6 (%s)" % DetailScene.band_crossfade(0.6))
	_expect(is_equal_approx(DetailScene.band_crossfade(0.4).y, 0.0),
		"top band started before s=0.4 (%s)" % DetailScene.band_crossfade(0.4))
	# Monotonic: bottom never rises, top never falls across the slide.
	var prev := DetailScene.band_crossfade(0.0)
	for i in range(1, 11):
		var cur := DetailScene.band_crossfade(float(i) / 10.0)
		_expect(cur.x <= prev.x + 0.0001 and cur.y >= prev.y - 0.0001,
			"crossfade not monotonic at s=%.1f" % (float(i) / 10.0))
		prev = cur


## (1b) The transition drives BOTH bands through the curve: docked→(1,0), settled→(0,full).
func _test_transition_drives_crossfade() -> void:
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	d.play_transition()

	# At the docked start: roster band full, this screen's top stripe hidden (NOT a binary pop).
	_expect(is_equal_approx(d.formation_band_factor(), 1.0),
		"transition start: formation band factor %f, want 1.0" % d.formation_band_factor())
	_expect(d._vitals_band_mat != null
		and is_equal_approx(d._vitals_band_mat.get_shader_parameter("full_sub"), 0.0),
		"transition start: detail stripe not hidden (full_sub=%s)"
			% (d._vitals_band_mat.get_shader_parameter("full_sub") if d._vitals_band_mat else "no mat"))

	# Pump to the settled top: bottom fully faded, top at the oracle 120/255.
	for _i in VitalsSlideAnimator.settle_frame() + 1:
		d._process(TICK)
	_expect(is_equal_approx(d.formation_band_factor(), 0.0),
		"after slide: formation band not faded out (%f)" % d.formation_band_factor())
	_expect(is_equal_approx(d._vitals_band_mat.get_shader_parameter("full_sub"), DetailScene.VBAND_FULL_SUB),
		"after slide: detail stripe not at full subtract (%s)"
			% d._vitals_band_mat.get_shader_parameter("full_sub"))
	d.queue_free()


## (2a) The rung arithmetic: detail's LOWEST overlay rung clears formation's HIGHEST content rung.
func _test_overlay_rung_arithmetic() -> void:
	var lowest_detail := DetailScene.RP_VITALS_BAND + DetailScene.DEFAULT_OVERLAY_RUNG_OFFSET
	_expect(lowest_detail > FormationScene.RP_INFO_TEXT,
		"detail's lowest overlay rung (%d) does not clear formation's top rung (%d)"
			% [lowest_detail, FormationScene.RP_INFO_TEXT])
	# ...and comfortably above the grid unit body it must occlude / darken.
	_expect(lowest_detail > FormationScene.RP_UNIT_BODY,
		"detail stripe would sort behind the formation grid units")


## (2b) overlay_rung_offset is threaded into the shared cluster + nameplate; live Z lifts on the fork.
func _test_overlay_offset_threaded() -> void:
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	d.overlay_rung_offset = DetailScene.DEFAULT_OVERLAY_RUNG_OFFSET
	add_child(d)

	var cluster: UnitInfoCluster = d._cluster
	_expect(cluster != null, "cluster not built")
	if cluster != null:
		_expect(cluster._vitals_rung == UnitInfoCluster.RP_VITALS_PANEL + DetailScene.DEFAULT_OVERLAY_RUNG_OFFSET,
			"cluster vitals rung not lifted (got %d)" % cluster._vitals_rung)
		var np = cluster.nameplate()
		_expect(np != null and np.rung_offset == DetailScene.DEFAULT_OVERLAY_RUNG_OFFSET,
			"nameplate rung_offset not threaded (got %s)" % (np.rung_offset if np != null else "no np"))

	# When the engine fold is active the lift is real world-Z: the lower panel + vitals stripe
	# sort nearer than a formation grid unit would. (Off the fold the offset is intentionally inert.)
	if Fold.owns():
		var unit_z := DepthMode.rung_z(FormationScene.RP_UNIT_BODY)
		_expect(d._open_root.position.z > unit_z,
			"lower panel Z %f not above the formation unit rung Z %f" % [d._open_root.position.z, unit_z])
	d.queue_free()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
