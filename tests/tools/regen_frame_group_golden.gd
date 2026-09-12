extends Node3D
## One-off: regenerate the DetailFrameGroupTest GOLDEN multiset (same setup, same
## collection + sort). Prints the const-ready lines to stdout; paste into the test.
const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

const _VIEW := {
	"move": 4, "jump": 3, "speed": 8,
	"r_power": 9, "r_wev": 5, "l_power": 0, "l_wev": 0,
	"attack": 7, "evade": 12,
}
const _DETAIL_SLUGS := [
	"detail.stats_frame_x", "detail.stats_frame_y", "detail.stats_frame_w", "detail.stats_frame_h",
	"detail.lower_frame_x", "detail.lower_frame_y", "detail.lower_frame_w", "detail.lower_frame_h",
	"detail.lower_frame_equip_x", "detail.lower_frame_equip_y", "detail.lower_frame_equip_w", "detail.lower_frame_equip_h",
	"detail.lower_frame_ability_x", "detail.lower_frame_ability_y", "detail.lower_frame_ability_w", "detail.lower_frame_ability_h",
	"detail.stats_container_x", "detail.stats_container_w", "detail.open_container_x", "detail.open_container_w",
	"detail.mjs_value_x", "detail.wp_value_x", "detail.at_val_x", "detail.weapon_icon_pos_x", "detail.weapon_icon_pos_y",
	"detail.eqp_tab_pos_x", "detail.eqp_tab_pos_y", "detail.abl_tab_pos_x", "detail.abl_tab_pos_y",
	"detail.abl_tab_left_pos_x", "detail.abl_tab_left_pos_y", "detail.stats_panel_nudge_x", "detail.stats_panel_nudge_y",
	"detail.stats_delta_nudge_x", "detail.stats_delta_nudge_y",
	"detail.eqp_band_x0", "detail.eqp_band_x1", "detail.abl_band_x0", "detail.abl_band_x1",
	"detail.abl_band_left_x0", "detail.abl_band_left_x1", "detail.band_top", "detail.band_bot",
]

func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a one-off GOLDEN regenerator — it prints const-ready lines to paste into DetailFrameGroupTest")
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	for slug: String in _DETAIL_SLUGS:
		Tune.clear(slug)
	d.set_stats_view(_VIEW)
	await get_tree().process_frame
	await get_tree().process_frame
	var out: Array = []
	_collect(d._open_root, out)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if not is_equal_approx(a.x, b.x): return a.x < b.x
		if not is_equal_approx(a.y, b.y): return a.y < b.y
		return a.z < b.z)
	print("GOLDEN_COUNT=", out.size())
	var line := ""
	for i in out.size():
		var v: Vector3 = out[i]
		line += "\"%.4f,%.4f,%.4f\", " % [v.x, v.y, v.z]
		if (i + 1) % 6 == 0:
			print("\t" + line.strip_edges())
			line = ""
	if line != "":
		print("\t" + line.strip_edges())
	get_tree().quit(0)

func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append((n as Node3D).global_position)
	for c in n.get_children():
		_collect(c, out)
