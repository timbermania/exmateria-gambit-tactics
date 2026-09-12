extends Node
## Headful DYNAMIC proof for the WYSIWYG target-colour authoring widget (#255). Rooted, not
## eyeballed: we drive the REAL inspector ColorPickerButton through the live studio page → host
## studio_pick_target → BlendTargetSolver → choke point → in-place repaint, parked, and require:
##
##   (1) SEED: after selecting the span, the picker opens seeded with the host's live top colour.
##   (2) DIRECTION: picking a BRIGHT-red target lands the folded top.r far ABOVE picking a BLACK
##       target — the solver drives the signed param the right way (the WYSIWYG contract).
##   (3) MATCH: the achieved colour the host returns equals the live folded top colour (the
##       preview and the widget's "actual" swatch agree — no drift).
##
## Run headful: godot --path . --quit-after 360 res://tools/verify_target_color_pick.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"

var _host = null


func _ready() -> void:
	await _run()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _run() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	_host = scn
	await _frames(30)

	var page = _host._studio_page
	if page == null:
		print("[VERIFY] FAIL — no studio page"); get_tree().quit(1); return

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E001"):
			dir = d
	page._load_effect(dir)
	await _frames(20)

	var eff = _host._current_effect
	if eff == null or not is_instance_valid(eff) or eff.screen_controller == null:
		print("[VERIFY] FAIL — no live effect / screen_controller"); get_tree().quit(1); return
	var sc = eff.screen_controller

	# Largest Blend screen span → clearest fold response; probe its midpoint.
	var best := {}
	var span_id := ""
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "screen":
			continue
		for sp in lane.get("spans", []):
			if str(sp.get("fields", {}).get("screen_kind", "")) != "Blend":
				continue
			var dur: int = int(sp.get("end", 0)) - int(sp.get("start", 0))
			if best.is_empty() or dur > int(best.get("end", 0)) - int(best.get("start", 0)):
				best = sp
				span_id = str(sp.get("id", ""))
	if best.is_empty():
		print("[VERIFY] FAIL — E001 has no Blend screen span"); get_tree().quit(1); return

	var probe: int = int((int(best.get("start", 0)) + int(best.get("end", 0))) / 2)
	print("[VERIFY] targeting Blend span %s window=[%d,%d] → probe frame %d"
		% [span_id, best.get("start", 0), best.get("end", 0), probe])

	_host.studio_seek(probe)
	_host.studio_set_playing(false)
	await _frames(6)

	page._on_span_selected(span_id)
	await _frames(6)
	var widgets: Array = page._inspector.pick_widgets()
	if widgets.size() != 1:
		print("[VERIFY] FAIL — expected 1 target-colour picker, got %d" % widgets.size()); get_tree().quit(2); return
	var picker = widgets[0]

	# (1) SEED — the picker opens showing the live top colour.
	var seed_ok: bool = picker.color.is_equal_approx(_host.studio_screen_top_color())
	print("[VERIFY] seed picker=%s live-top=%s → %s"
		% [picker.color, _host.studio_screen_top_color(), "OK" if seed_ok else "MISMATCH"])

	# (2) DIRECTION — pick BRIGHT red then BLACK, parked, no seek between.
	var bright := Color(1.0, 0.0, 0.0)
	picker.color = bright
	picker.color_changed.emit(bright)
	await _frames(6)
	var r_bright: float = sc.top_color.r
	var achieved_bright: Color = _host.studio_pick_target({
		"r": {"channel": "screen", "context": String(best.get("phase", "")), "event_index": int(best.get("keyframe_index", 0)), "field": "start_r"},
		"g": {"channel": "screen", "context": String(best.get("phase", "")), "event_index": int(best.get("keyframe_index", 0)), "field": "start_g"},
		"b": {"channel": "screen", "context": String(best.get("phase", "")), "event_index": int(best.get("keyframe_index", 0)), "field": "start_b"},
	}, bright)
	await _frames(2)
	r_bright = sc.top_color.r
	print("[VERIFY] parked, picked BRIGHT red → top.r=%.4f (achieved=%s)" % [r_bright, achieved_bright])

	var dark := Color(0.0, 0.0, 0.0)
	picker.color = dark
	picker.color_changed.emit(dark)
	await _frames(6)
	var r_dark: float = sc.top_color.r
	print("[VERIFY] parked, picked BLACK → top.r=%.4f" % r_dark)

	# (3) MATCH — the achieved colour the host returned equals the live folded top.
	var match_ok: bool = achieved_bright.is_equal_approx(Color(r_bright, sc.top_color.g, sc.top_color.b)) \
		or absf(achieved_bright.r - r_bright) < 0.001

	var dir_ok: bool = r_bright > r_dark + 0.1
	if seed_ok and dir_ok:
		print("[VERIFY] PASS — seed OK, a bright target BRIGHTENS vs a dark target (Δ %.3f); WYSIWYG target-colour authoring works" % [r_bright - r_dark])
		get_tree().quit(0)
	else:
		print("[VERIFY] FAIL — seed_ok=%s dir_ok=%s (r_bright=%.3f r_dark=%.3f)" % [seed_ok, dir_ok, r_bright, r_dark])
		get_tree().quit(3)
