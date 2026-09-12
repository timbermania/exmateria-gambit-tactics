extends Node3D
## §15.26 DEFECT #8 follow-on guard — the delta/compare stats band must RIDE a stats-frame move.
##
## Bug (user report): with the equip-picker preview open (the SECOND, offset stats band showing), scrubbing
## the stats frame position (detail.stats_frame_x → _rebuild_lower_settled) moved the BASE band but left the
## DELTA band behind. Root cause: _rebuild_stats_delta() placed _stats_delta_root at a FRAME-INDEPENDENT
## world position (STATS_DELTA_NUDGE + panel_nudge, no STATS_FRAME term) then reparent(keep-global) pinned
## it there — so a rebuild re-derived the delta ignoring where the frame actually is.
##
## Fix: the delta band is its OWN movable frame group (origin = base origin + STATS_DELTA_NUDGE, both
## re-derived from the live STATS_FRAME each rebuild). This guard drives the LIVE TUNABLE REBUILD PATH the
## node-move DetailFrameGroupTest does not: in preview, after a stats_frame_x scrub, the delta band's world-x
## must shift by the SAME delta as the base chrome (they move together as a 2px-offset pair).
##
## Run: <GODOT> --path . --quit-after 20 res://tests/DetailStatsDeltaFrameRideTest.tscn

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

const _VIEW := {
	"move": 4, "jump": 3, "speed": 8, "r_power": 9, "r_wev": 5, "l_power": 0, "l_wev": 0,
	"r_at": 7, "c_ev": 12, "s_ev": 0, "a_ev": 0, "l_at": 0,
}
const MOVE_PX := 30.0   # scrub stats_frame_x this far (display px)
# The detail.* frame slugs cleared at start so the test is independent of the user's tune_overrides.json.
const _DETAIL_SLUGS := [
	"detail.stats_frame_x", "detail.stats_frame_y", "detail.stats_frame_w", "detail.stats_frame_h",
	"detail.stats_panel_nudge_x", "detail.stats_panel_nudge_y",
	"detail.stats_delta_nudge_x", "detail.stats_delta_nudge_y",
]

var _passed := 0
var _failed := 0


func _ready() -> void:
	for slug: String in _DETAIL_SLUGS:
		Tune.clear(slug)

	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	d.set_stats_view(_VIEW)
	d.set_stats_preview(true)   # bring up the SECOND (delta/compare) band
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(d.stats_delta_active(), "delta band not built in preview (precondition)")

	# --- #6: the sword/rod weapon legend rides the delta band (a legend clone under the delta root,
	# offset from the base legend by exactly STATS_DELTA_NUDGE — the ROM's full second band draw) ---
	var base_legend: Node3D = d._stats_legend_root
	_expect(base_legend != null and is_instance_valid(base_legend), "base weapon legend root missing")
	var delta_legend := d._stats_delta_root.find_child("StatsWeaponLegend", true, false) as Node3D
	_expect(delta_legend != null, "delta band has no weapon-legend clone (sword/rod left behind)")
	if base_legend != null and delta_legend != null:
		var off := delta_legend.global_position - base_legend.global_position
		var want := Vector3(DetailScene.STATS_DELTA_NUDGE.x, -DetailScene.STATS_DELTA_NUDGE.y, 0.0) \
			* DetailScene.PIXELS_PER_UNIT
		_expect(absf(off.x - want.x) < 0.01 and absf(off.y - want.y) < 0.01,
			"legend clone offset %s != delta nudge %s" % [off, want])

	# --- ADR-0088 migration: detail.compare is a STANDARD registered element — its rect IS
	# the true panel box (live STATS_FRAME + the 2px delta nudge), the R44 panel-nudge reveal
	# is `aperture_pad` (not baked into the rect), and its x/y placement is the element's own
	# _place_self under a screen-at-origin _open_root (the LEGACY-FRAME ANCHOR OVERRIDE dies).
	var e: UI3Element = d.stats_compare_element()
	_expect(e != null, "stats_compare_element() missing in preview")
	if e != null:
		var want_rect := Rect2(
			DetailScene.STATS_FRAME.position + DetailScene.STATS_DELTA_NUDGE,
			DetailScene.STATS_FRAME.size)
		_expect(e.rect().is_equal_approx(want_rect),
			"compare rect %s != the true panel box %s (aperture semantics leaked into rect)"
			% [e.rect(), want_rect])
		# The settled aperture must cover BOTH the panel box and its R44-nudged chrome (the
		# behavioral requirement the old merged-rect and the new aperture_pad both encode).
		var nudged := Rect2(want_rect.position + DetailScene.STATS_PANEL_NUDGE, want_rect.size)
		var ap := Rect2(e.aperture()).grow(1.0)
		_expect(ap.encloses(want_rect) and ap.encloses(nudged),
			"settled aperture %s does not cover the panel box %s + its nudged chrome %s"
			% [ap, want_rect, nudged])
		# Placement: the element's world x/y is the world image of its rect corner — the
		# standard element placement, no container-anchored hand override.
		var want_x := want_rect.position.x * DetailScene.PIXELS_PER_UNIT
		var want_y := -want_rect.position.y * DetailScene.PIXELS_PER_UNIT
		_expect(absf(e.global_position.x - want_x) < 0.001 and absf(e.global_position.y - want_y) < 0.001,
			"compare element global (%.3f, %.3f) != its rect corner world (%.3f, %.3f)"
			% [e.global_position.x, e.global_position.y, want_x, want_y])

	var base_x0 := d._stats_frame_node.global_position.x     # base chrome world-x
	var delta_x0 := _mean_mesh_x(d._stats_delta_root)        # delta band world-x (its drawn quads)

	# --- LIVE TUNABLE PATH: scrub stats_frame_x → _rebuild_lower_settled ---
	var start_x := float(DetailScene.STATS_FRAME.position.x)
	Tune.set_value("detail.stats_frame_x", start_x + MOVE_PX)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(d.stats_delta_active(), "delta band disappeared after the frame scrub")

	var base_x1 := d._stats_frame_node.global_position.x
	var delta_x1 := _mean_mesh_x(d._stats_delta_root)

	var base_shift := base_x1 - base_x0
	var delta_shift := delta_x1 - delta_x0
	var expect := MOVE_PX * DetailScene.PIXELS_PER_UNIT   # screen +x → world +x

	_expect(absf(base_shift - expect) < 0.01,
		"base chrome should shift +%.4f, got %+.4f (precondition)" % [expect, base_shift])
	_expect(absf(delta_shift - base_shift) < 0.01,
		"delta band must ride the frame: base shifted %+.4f but delta shifted %+.4f" % [base_shift, delta_shift])

	d.queue_free()
	print("\n=== DetailStatsDeltaFrameRideTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DetailStatsDeltaFrameRideTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailStatsDeltaFrameRideTest: delta band rides the stats-frame tunable move")
		get_tree().quit(0)


func _mean_mesh_x(root: Node3D) -> float:
	var xs: Array[float] = []
	_gather(root, xs)
	assert(not xs.is_empty(), "delta band has no drawn quads")
	var s := 0.0
	for x in xs:
		s += x
	return s / xs.size()


func _gather(n: Node, xs: Array[float]) -> void:
	if n is MeshInstance3D:
		xs.append((n as MeshInstance3D).global_position.x)
	for c in n.get_children():
		_gather(c, xs)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[DetailStatsDeltaFrameRideTest] " + msg)
		print("  [x] " + msg)
