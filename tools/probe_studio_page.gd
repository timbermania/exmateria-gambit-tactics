extends SceneTree
## [Studio page layout probe] Headful NUMERIC check of the re-scroll behaviour: when an
## emitter span is selected the inspector grows, the channel list fills to the bottom and
## scrolls INTERNALLY (every lane reachable), and the visible lanes DON'T MOVE — the page
## adds the inspector's height delta to the channel scroll (bottom-anchored). We measure a
## reference lane's on-screen Y before vs. after and assert it's unchanged.
##
## Run (NEVER headless), from the package root:
##   godot --path . -s res://tools/probe_studio_page.gd
## Prints the geometry table and PASS/FAIL, then quits.

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")

var _page
var _f := 0
var _before := {}


func _initialize() -> void:
	_page = Page.new()
	root.add_child(_page)
	_page.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_page.position = Vector2(0, 0)
	_page.custom_minimum_size = Vector2(1000, 680)
	_page.size = Vector2(1000, 680)


func _process(_delta: float) -> bool:
	_f += 1
	# Load after the page's _ready has built _timeline (deferred past _initialize).
	if _f == 1:
		_page._load_effect("res://assets/effects/E004")
		return false
	if _f == 3:
		_before = _snapshot()
		var sid := _first_particle_span_id()
		_page._on_span_selected(sid)
		print("[probe] selected span=%s" % sid)
		return false
	# Let the deferred scroll_vertical apply (viewport re-sort happens next frame).
	if _f < 8:
		return false

	var after := _snapshot()
	_report("BEFORE", _before)
	_report("AFTER ", after)

	var bar = _page._scroll.get_v_scroll_bar()
	var content_h: float = _page._timeline.get_combined_minimum_size().y
	var reachable: bool = bar.max_value >= content_h - 0.5   # bottom lane scrollable into view
	var last_moved: float = absf(after["last_lane_screen_y"] - _before["last_lane_screen_y"])
	var overflowed: bool = _before["content_h"] > _before["viewport_h"] or after["content_h"] > after["viewport_h"]

	print("\n[probe] content_h=%.0f  overflowed(before/after)=%s" % [content_h, overflowed])
	print("[probe] req2 all-lanes-reachable (scrollbar max>=content): %s" % reachable)
	print("[probe] req3 last-lane on-screen Δ = %.1f px (want ~0 when overflowed)" % last_moved)
	var ok: bool = reachable and (not overflowed or last_moved <= 1.5)
	print("[probe] %s" % ("PASS" if ok else "FAIL"))
	return true


func _snapshot() -> Dictionary:
	var lanes = _page._timeline._lane_rows
	var last_y: float = lanes[-1]["rect"].position.y if not lanes.is_empty() else 0.0
	var channels_top: float = _page._scroll.position.y
	var sv: int = _page._scroll.scroll_vertical
	return {
		"editor_h": _page._inspector.size.y,
		"channels_top": channels_top,
		"viewport_h": _page._scroll.size.y,
		"scroll_v": sv,
		"content_h": _page._timeline.get_combined_minimum_size().y,
		# On-screen Y of the last lane = viewport top + (lane content-y − scroll offset).
		"last_lane_screen_y": channels_top + (last_y - float(sv)),
	}


func _report(tag: String, s: Dictionary) -> void:
	print("[%s] editor_h=%.0f channels_top=%.0f viewport_h=%.0f scroll_v=%d content_h=%.0f last_lane_screenY=%.1f" % [
		tag, s["editor_h"], s["channels_top"], s["viewport_h"], s["scroll_v"], s["content_h"], s["last_lane_screen_y"]])


func _first_particle_span_id() -> String:
	var score = _page._timeline._score
	for lane in score.get("lanes", []):
		for span in lane.get("spans", []):
			if span.get("kind", "") == "particle" and int(span.get("emitter_index", -1)) >= 0:
				return span.get("id", "")
	return ""
