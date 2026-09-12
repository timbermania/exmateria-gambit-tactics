extends Node3D

## ADR-0088 migration guard: the stats band group (chrome + weapon legend + stats text)
## is the registered element `detail.stats` (the old hand-rolled _stats_origin group).
##   1. IDENTITY — stats_element() returns the registered element (id "detail.stats"),
##      distinct from the compare element.
##   2. ENGINE CLIP — shutting the windows (set_open_frame(-1)) lands the SHUT clip box
##      on EVERY stats payload material via the clip engine's subtree discovery
##      (chrome + legend + glyphs — the hand _stats_*_mats clip pushes retire).
##   3. MOUNT COVERAGE (the stale-clip kill) — rebuilding the stats text while SHUT
##      (set_stats_view) leaves the fresh glyphs carrying the shut aperture too, with
##      no hand re-apply in the rebuild path.
##   4. SWEEP APERTURE — the settled aperture covers the frame chrome AND the full-width
##      §15.17 sweep container (wider than the chrome; aperture_pad carries the delta).
##
## Run: <GODOT> --path . --quit-after 20 res://tests/DetailStatsElementTest.tscn

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

const _VIEW_A := {
	"move": 4, "jump": 3, "speed": 8, "r_power": 9, "r_wev": 5, "l_power": 0, "l_wev": 0,
	"r_at": 7, "c_ev": 12, "s_ev": 0, "a_ev": 0, "l_at": 0,
}
const _VIEW_B := {
	"move": 6, "jump": 5, "speed": 7, "r_power": 12, "r_wev": 10, "l_power": 3, "l_wev": 1,
	"r_at": 19, "c_ev": 20, "s_ev": 8, "a_ev": 2, "l_at": 10,
}
const _DETAIL_SLUGS := [
	"detail.stats_frame_x", "detail.stats_frame_y", "detail.stats_frame_w", "detail.stats_frame_h",
	"detail.stats_container_x", "detail.stats_container_w",
	"detail.stats_panel_nudge_x", "detail.stats_panel_nudge_y",
]

var _passed := 0
var _failed := 0


func _ready() -> void:
	for slug: String in _DETAIL_SLUGS:
		Tune.clear(slug)

	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	d.set_stats_view(_VIEW_A)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- 1. identity -------------------------------------------------------------
	if not d.has_method("stats_element"):
		_expect(false, "stats_element() missing — stats band not migrated to a registered element")
	else:
		var e: UI3Element = d.call("stats_element")
		_expect(e != null and is_instance_valid(e), "stats_element() returned null")
		if e != null:
			_expect(e.id() == "detail.stats", "element id %s != detail.stats" % e.id())
			_expect(e != d.stats_compare_element(), "stats element must be distinct from detail.compare")

			# --- Amendment 4 §2: detail.stats DECLARES its frame drivers (was a bare
			# Callable → empty-DERIVED dead-end). Same eval; drivers now surfaced so the
			# page expands the detail.stats_frame_* knobs inline and the audit exempts it.
			var s_drivers := _rect_drivers(e)
			for slug in ["detail.stats_frame_x", "detail.stats_frame_y",
					"detail.stats_frame_w", "detail.stats_frame_h"]:
				_expect(s_drivers.has(slug),
					"detail.stats must declare driver %s, got %s" % [slug, s_drivers])
			# detail.compare (built on stats-preview) declares STATS_FRAME + STATS_DELTA_NUDGE.
			d.set_stats_preview(true)
			await get_tree().process_frame
			var cmp: UI3Element = d.stats_compare_element()
			_expect(cmp != null, "compare element not built on stats-preview")
			if cmp != null:
				var c_drivers := _rect_drivers(cmp)
				for slug in ["detail.stats_frame_x", "detail.stats_delta_nudge_x",
						"detail.stats_delta_nudge_y"]:
					_expect(c_drivers.has(slug),
						"detail.compare must declare driver %s, got %s" % [slug, c_drivers])
			d.set_stats_preview(false)
			await get_tree().process_frame

			# --- 4. sweep aperture (settled) ---------------------------------------
			# The chrome DRAWS at the R44-nudged box (frame + STATS_PANEL_NUDGE) — that is
			# what the settled aperture must cover (the raw frame rect's un-nudged bottom
			# strip is never drawn).
			var drawn := Rect2(
				DetailScene.STATS_FRAME.position + DetailScene.STATS_PANEL_NUDGE,
				DetailScene.STATS_FRAME.size)
			var ap := Rect2(e.aperture()).grow(1.0)
			_expect(ap.encloses(drawn),
				"settled aperture %s does not cover the drawn stats chrome %s" % [ap, drawn])
			_expect(ap.size.x >= 249.0,
				"settled aperture width %.1f < the full-width §15.17 sweep (~250)" % ap.size.x)

			# --- 2. engine clip: shut → every payload material carries the shut box --
			var mats := e.payload_materials()
			_expect(mats.size() >= 10,
				"stats payload discovery found only %d materials (chrome+legend+glyphs expected)" % mats.size())
			d.set_open_frame(-1)
			_expect(_all_shut(mats), "shut aperture did not reach every stats payload material")

			# --- 3. mount coverage: rebuild text while shut → fresh glyphs shut too --
			d.set_stats_view(_VIEW_B)
			await get_tree().process_frame
			await get_tree().process_frame
			var fresh := e.payload_materials()
			_expect(fresh.size() >= 10, "rebuild dropped the stats payload (%d mats)" % fresh.size())
			_expect(_all_shut(fresh),
				"freshly mounted glyphs missed the SHUT aperture (stale-clip class: mount coverage failed)")

			# reopen fully — the settled aperture returns
			d.set_open_frame(1000)
			_expect(not _all_shut(e.payload_materials()), "settled reopen left the stats band clipped shut")

	d.queue_free()
	print("\n=== DetailStatsElementTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DetailStatsElementTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailStatsElementTest: detail.stats registered element (engine clip + mount coverage + sweep aperture)")
		get_tree().quit(0)


## The declared driver slugs of an element's rect answer ([] when not derived).
func _rect_drivers(e: UI3Element) -> Array:
	for r: Dictionary in e.criteria():
		if String(r["field"]) == "rect":
			return r.get("drivers", [])
	return []


## True when every material carries the inverted (never-passing) shut clip box.
func _all_shut(mats: Array) -> bool:
	if mats.is_empty():
		return false
	for m in mats:
		var cw = m.get_shader_parameter("clip_world")
		if cw == null or cw.x < 1e19:
			return false
	return true


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[DetailStatsElementTest] " + msg)
		print("  [x] " + msg)
