extends Node3D

## Guard (headful): the DETAIL / Status-screen "frame = movable origin + relative content
## group" refactor. Two invariants:
##
##   A. REGRESSION (visual no-op) — every drawn quad (MeshInstance3D) under the lower-panel
##      root lands on the EXACT same world position as before the refactor. GOLDEN below is
##      the sorted position multiset captured from the PRE-refactor code (independent source
##      of truth), for the fixed _stats_view seeded here. Catches ANY content drift.
##
##   B. CAPABILITY (grab-the-frame) — moving a frame's ORIGIN node by a delta moves every one
##      of its content children by the same delta (chrome + labels/values/icons ride as one).
##      This is the whole point: the frame and its content are ONE coherent thing.
##
## The F3 "Detail Screen" tunable panel remains a pure view over these (DetailFrameTunablesTest).

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

const _VIEW := {
	"move": 4, "jump": 3, "speed": 8,
	"r_power": 9, "r_wev": 5, "l_power": 0, "l_wev": 0,
	"attack": 7, "evade": 12,
}

# Sorted (x,y,z) multiset of every MeshInstance3D under _open_root, captured at the CODE-LITERAL frame
# defaults (all `detail.*` Tune overrides CLEARED — see _ready). Deterministic + machine-independent:
# does NOT depend on the user's persisted tune_overrides.json.
# Regenerated 2026-08-13 (ADR-0077 dec. 7 — no *unauthored depth*): the stats sub-panel migrated
# OFF the Z=0 floor onto the near ladder (it was the last floor holdout, so the F3-draggable vitals
# band composited over it). Only the stats prims' Z changed — count stays 94, x/y byte-identical:
#   • stats value/label glyphs + weapon legend text: Z 0.0000 → 1.7100 (RP_TEXT=9 · UNITS_PER_OT_BUCKET)
#   • stats frame chrome: Z 0.0000 → 0.5700 (RP_WINDOW_FRAME=3), strictly BEHIND its own glyphs
# The lower panel + already-authored legend icons (0.76/0.95/1.14/1.33/1.52 …) are unchanged.
# (Prior provenance: 2026-08-11 §15.29 round 48 ROM-exact stats panel, 102→94 quads, pixel-exact vs
# the sstate1 oracle framebuffer.) Regen via tests/tools/regen_frame_group_golden.tscn.
const GOLDEN := [
	"0.5600,-0.8400,1.9000", "0.8800,-8.8000,0.9500", "0.8800,-8.7600,1.1400", "0.8800,-7.5200,1.1400", "0.9200,-8.1600,0.9500", "0.9200,-8.1200,1.1400",
	"0.9200,-6.8800,0.9500", "0.9200,-6.8800,1.1400", "0.9200,-6.2400,0.9500", "0.9200,-6.2400,1.1400", "0.9600,-7.5200,0.9500", "0.9600,-0.8600,2.0900",
	"0.9600,-0.8400,1.9000", "1.2000,-4.8800,1.7100", "1.3600,-4.4000,1.7100", "1.3600,-3.9200,1.7100", "1.3600,-0.8400,1.9000", "1.5200,-7.1800,0.7600",
	"1.5600,-5.6000,1.5200", "1.8800,-4.8800,1.7100", "1.8800,-4.4000,1.7100", "1.8800,-3.9200,1.7100", "2.1600,-4.8800,1.7100", "2.1600,-4.4000,1.7100",
	"2.1600,-3.9200,1.7100", "2.8800,-4.8800,1.7100", "2.8800,-4.4000,1.7100", "3.1600,-4.8800,1.7100", "3.1600,-4.4000,1.7100", "3.4400,-4.8800,1.7100",
	"3.4400,-4.4000,1.7100", "3.6400,-4.8800,1.7100", "3.6400,-4.4000,1.7100", "3.8400,-4.8800,1.7100", "3.8400,-4.4000,1.7100", "3.8400,-3.9200,1.7100",
	"4.1200,-4.8800,1.7100", "4.1200,-4.4000,1.7100", "4.4000,-4.8800,1.7100", "4.4000,-4.4000,1.7100", "4.6000,-4.8800,1.7100", "4.6000,-4.4000,1.7100",
	"4.8000,-4.8800,1.7100", "4.8000,-4.4000,1.7100", "5.1200,-4.4600,0.5700", "5.1600,-7.3600,0.5700", "5.4400,-4.6000,0.9500", "5.4400,-4.6000,1.1400",
	"5.7600,-7.1800,0.7600", "5.8000,-8.7600,1.3300", "5.8000,-8.1200,1.3300", "5.8000,-7.4800,1.3300", "5.8000,-6.8400,1.3300", "5.8000,-6.2000,1.3300",
	"5.8000,-5.6400,1.5200", "6.0400,-4.8800,1.7100", "6.0400,-4.4000,1.7100", "6.1600,-3.9200,1.7100", "6.2400,-4.8800,1.7100", "6.2400,-4.4000,1.7100",
	"6.5200,-4.8800,1.7100", "6.5200,-4.4000,1.7100", "6.8000,-4.8800,1.7100", "6.8000,-4.4000,1.7100", "6.8000,-3.9200,1.7100", "7.0000,-4.8800,1.7100",
	"7.0000,-4.4000,1.7100", "7.2000,-4.8800,1.7100", "7.2000,-4.4000,1.7100", "7.2400,-3.9200,1.7100", "7.5200,-4.8800,1.7100", "7.5200,-4.4000,1.7100",
	"7.8000,-4.8800,1.7100", "7.8000,-4.4000,1.7100", "7.8400,-3.9200,1.7100", "8.0000,-4.8800,1.7100", "8.0000,-4.4000,1.7100", "8.2000,-4.8800,1.7100",
	"8.2000,-4.4000,1.7100", "8.2400,-3.9200,1.7100", "8.5600,-4.8800,1.7100", "8.5600,-4.4000,1.7100", "8.8400,-4.8800,1.7100", "8.8400,-4.4000,1.7100",
	"8.8400,-3.9200,1.7100", "9.0400,-4.8800,1.7100", "9.0400,-4.4000,1.7100", "9.0400,-0.8400,1.9000", "9.2400,-4.8800,1.7100", "9.2400,-4.4000,1.7100",
	"9.2800,-3.9200,1.7100", "9.4400,-0.8400,1.9000", "9.4600,-0.8600,2.0900", "9.8400,-0.8400,1.9000",
]

# Every detail.* frame slug — cleared at test start so the golden reflects the code-literal defaults.
const _DETAIL_SLUGS := [
	"detail.stats_frame_x", "detail.stats_frame_y", "detail.stats_frame_w", "detail.stats_frame_h",
	"detail.lower_frame_x", "detail.lower_frame_y", "detail.lower_frame_w", "detail.lower_frame_h",
	"detail.lower_frame_equip_x", "detail.lower_frame_equip_y", "detail.lower_frame_equip_w", "detail.lower_frame_equip_h",
	"detail.lower_frame_ability_x", "detail.lower_frame_ability_y", "detail.lower_frame_ability_w", "detail.lower_frame_ability_h",
	"detail.open_container_x", "detail.open_container_y", "detail.open_container_w", "detail.open_container_h",
	"detail.stats_container_x", "detail.stats_container_w",
	"detail.eqp_tab_pos_x", "detail.eqp_tab_pos_y", "detail.abl_tab_pos_x", "detail.abl_tab_pos_y",
	"detail.abl_tab_left_pos_x", "detail.abl_tab_left_pos_y", "detail.stats_panel_nudge_x", "detail.stats_panel_nudge_y",
	"detail.stats_delta_nudge_x", "detail.stats_delta_nudge_y",
	"detail.eqp_band_x0", "detail.eqp_band_x1", "detail.abl_band_x0", "detail.abl_band_x1",
	"detail.abl_band_left_x0", "detail.abl_band_left_x1", "detail.band_top", "detail.band_bot",
]

var _failed := false


func _ready() -> void:
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	# Test against the CODE-LITERAL frame defaults: clear any persisted detail.* Tune overrides so the
	# golden is deterministic and independent of the user's dialed tune_overrides.json. In-memory only
	# (Tune.clear does not persist), and this test process is disposable.
	for slug: String in _DETAIL_SLUGS:
		Tune.clear(slug)
	d.set_stats_view(_VIEW)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- A. regression: the drawn-quad multiset is byte-identical to the golden ---
	var observed := _collect_positions(d._open_root)
	var golden := _parse_golden()
	_expect(observed.size() == golden.size(),
		"quad count drifted: observed %d vs golden %d" % [observed.size(), golden.size()])
	if observed.size() == golden.size():
		var worst := 0.0
		for i in observed.size():
			worst = maxf(worst, (observed[i] - golden[i]).length())
		_expect(worst < 0.001, "content drifted from golden (worst delta %.4f world units)" % worst)

	# --- B. capability: moving a frame origin moves its content by the same delta ---
	_check_origin_moves_content(d, "_stats_origin")
	_check_origin_moves_content(d, "_lower_origin")

	d.queue_free()
	if _failed:
		push_error("[FAIL] DetailFrameGroupTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailFrameGroupTest")
		get_tree().quit(0)


## Move the named origin node by a delta; every MeshInstance3D under it must shift by that
## exact delta (grab-the-frame — chrome + content are one group).
func _check_origin_moves_content(d: DetailScene, origin_prop: String) -> void:
	var origin: Node3D = d.get(origin_prop)
	if origin == null or not is_instance_valid(origin):
		_failed = true
		push_error("[DetailFrameGroupTest] frame origin %s missing (grouping not built)" % origin_prop)
		return
	var before := _collect_positions(origin)
	_expect(before.size() > 0, "%s has no content children" % origin_prop)
	var delta := Vector3(1.234, -0.567, 0.0)
	origin.position += delta
	var after := _collect_positions(origin)
	var ok := after.size() == before.size()
	if ok:
		for i in before.size():
			if ((after[i] - before[i]) - delta).length() >= 0.001:
				ok = false
				break
	_expect(ok, "%s content did not ride the origin move (content decoupled from frame)" % origin_prop)
	origin.position -= delta   # restore


## Sorted (x,y,z) world positions of every MeshInstance3D under `root`.
func _collect_positions(root: Node) -> Array:
	var out: Array = []
	if root != null and is_instance_valid(root):
		_collect(root, out)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if not is_equal_approx(a.x, b.x): return a.x < b.x
		if not is_equal_approx(a.y, b.y): return a.y < b.y
		return a.z < b.z)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append((n as MeshInstance3D).global_position)
	for c in n.get_children():
		_collect(c, out)


func _parse_golden() -> Array:
	var out: Array = []
	for s: String in GOLDEN:
		var p := s.split(",")
		out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if not is_equal_approx(a.x, b.x): return a.x < b.x
		if not is_equal_approx(a.y, b.y): return a.y < b.y
		return a.z < b.z)
	return out


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[DetailFrameGroupTest] %s" % msg)
