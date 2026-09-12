extends Node
## Headful DYNAMIC proof for the #255 scope-B Gradient two-picker editor: editing the BOTTOM
## stop (end_r/g/b) of a Gradient screen tween moves the folded BOTTOM backdrop colour and
## leaves the TOP untouched — and vice-versa. This is the independent-endpoint runtime path
## (ScreenSubsystem, slice 1) exercised end-to-end through the real host choke point
## (studio_apply_edit), while the preview is PARKED (paused), with zero re-seek.
##
## Rooted, not eyeballed: we target the screen tween ACTIVE at the probed frame (via the
## score's absolute span window), flip its Kind to Gradient, then drive one stop at a time and
## require a LARGE correct-direction change in that stop's folded colour AND near-zero change
## in the OTHER stop. Run headful:
##   godot --path . --quit-after 320 res://tools/verify_gradient_stop_edit.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const ScreenData = ExMateriaEffects.ScreenData

const MOVED := 0.05    # a real, correct-direction change in the driven stop
const STILL := 0.03    # the other stop must stay within this (independent endpoints)

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
	await _frames(30)   # scene _ready, units, studio page

	_host.studio_select_effect(1)   # E001
	await _frames(20)

	var eff = _host._current_effect
	if eff == null or not is_instance_valid(eff) or eff.screen_controller == null:
		print("[VERIFY] FAIL — no live effect / screen_controller"); get_tree().quit(1); return
	var sc = eff.screen_controller

	# Largest screen span → clearest fold response; probe its MIDPOINT (progress ~0.5).
	var score := Model.build(eff.effect_data)
	var best := {}
	for lane in score.get("lanes", []):
		if lane.get("kind", "") != "screen":
			continue
		for sp in lane.get("spans", []):
			var dur: int = int(sp.get("end", 0)) - int(sp.get("start", 0))
			if best.is_empty() or dur > int(best.get("end", 0)) - int(best.get("start", 0)):
				best = sp
	if best.is_empty():
		print("[VERIFY] FAIL — E001 has no screen span"); get_tree().quit(1); return

	var phase: String = best.get("phase", "")
	var idx: int = int(best.get("keyframe_index", -1))
	var probe: int = int((int(best.get("start", 0)) + int(best.get("end", 0))) / 2)
	print("[VERIFY] targeting screen span phase=%s kf=%d window=[%d,%d] → probe frame %d"
		% [phase, idx, best.get("start", 0), best.get("end", 0), probe])

	# PARK at the probe frame and make this tween a GRADIENT (independent stops).
	_host.studio_seek(probe)
	_host.studio_set_playing(false)
	await _frames(6)
	_host.studio_apply_edit({"channel": "screen", "context": phase, "event_index": idx, "field": "kind"},
		ScreenData.ScreenMode.GRADIENT)
	await _frames(6)

	# Baseline: both stops black.
	_set_stop(phase, idx, "start", 0, 0, 0)
	_set_stop(phase, idx, "end", 0, 0, 0)
	await _frames(6)
	var top0: Color = sc.top_color
	var bot0: Color = sc.bottom_color
	print("[VERIFY] both stops black → top=%s bottom=%s" % [_s(top0), _s(bot0)])

	# Drive the BOTTOM stop blue. Bottom.b must rise; TOP must stay put.
	_set_stop(phase, idx, "end", 0, 0, 255)
	await _frames(6)
	var top1: Color = sc.top_color
	var bot1: Color = sc.bottom_color
	print("[VERIFY] bottom→blue → top=%s bottom=%s" % [_s(top1), _s(bot1)])

	# Drive the TOP stop red. Top.r must rise; BOTTOM must stay where the last edit left it.
	_set_stop(phase, idx, "start", 255, 0, 0)
	await _frames(6)
	var top2: Color = sc.top_color
	var bot2: Color = sc.bottom_color
	print("[VERIFY] top→red → top=%s bottom=%s" % [_s(top2), _s(bot2)])

	var ok := true
	ok = _check(bot1.b - bot0.b > MOVED, "editing the BOTTOM stop raised bottom.b (Δ%.3f)" % (bot1.b - bot0.b)) and ok
	ok = _check(_dist(top1, top0) < STILL, "the TOP stop stayed put while the bottom was edited (Δ%.3f)" % _dist(top1, top0)) and ok
	ok = _check(top2.r - top1.r > MOVED, "editing the TOP stop raised top.r (Δ%.3f)" % (top2.r - top1.r)) and ok
	ok = _check(_dist(bot2, bot1) < STILL, "the BOTTOM stop stayed put while the top was edited (Δ%.3f)" % _dist(bot2, bot1)) and ok

	if ok:
		print("[VERIFY] PASS — the two Gradient stops fold INDEPENDENTLY, live through the host, zero re-seek")
		get_tree().quit(0)
	else:
		print("[VERIFY] FAIL — the stops are not independent")
		get_tree().quit(2)


func _set_stop(phase: String, idx: int, which: String, r: int, g: int, b: int) -> void:
	_host.studio_apply_edit({"channel": "screen", "context": phase, "event_index": idx, "field": which + "_r"}, r)
	_host.studio_apply_edit({"channel": "screen", "context": phase, "event_index": idx, "field": which + "_g"}, g)
	_host.studio_apply_edit({"channel": "screen", "context": phase, "event_index": idx, "field": which + "_b"}, b)


func _check(cond: bool, msg: String) -> bool:
	print("[VERIFY]   %s %s" % ["OK " if cond else "XX ", msg])
	return cond


func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _s(c: Color) -> String:
	return "(%.3f,%.3f,%.3f)" % [c.r, c.g, c.b]
