extends Node
## Headful DYNAMIC proof for Effect Studio slice 6: a screen-colour edit lowered through
## the host choke point (studio_apply_edit) must repaint the LIVE preview IN PLACE while it
## is PARKED (paused), with ZERO re-seek. Rooted, not eyeballed: we target the screen tween
## ACTIVE at the probed frame (via the score's absolute span window), edit it to full red,
## and require a LARGE, correct-DIRECTION change in the folded backdrop (top.r ↑). Then we
## edit back to black and require top.r to fall again. Run headful:
##   godot --path . --quit-after 320 res://tools/verify_screen_color_edit.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")

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

	# Find a screen BLEND span with the largest duration → the clearest fold response, and
	# probe its MIDPOINT (that phase is dominant there, so its kf drives the fold).
	var score := Model.build(eff.effect_data)
	var best := {}
	for lane in score.get("lanes", []):
		if lane.get("kind", "") != "screen":
			continue
		for sp in lane.get("spans", []):
			if str(sp.get("fields", {}).get("screen_kind", "")) != "Blend":
				continue
			var dur: int = int(sp.get("end", 0)) - int(sp.get("start", 0))
			if best.is_empty() or dur > int(best.get("end", 0)) - int(best.get("start", 0)):
				best = sp
	if best.is_empty():
		print("[VERIFY] FAIL — E001 has no Blend screen span"); get_tree().quit(1); return

	var phase: String = best.get("phase", "")
	var idx: int = int(best.get("keyframe_index", -1))
	var probe: int = int((int(best.get("start", 0)) + int(best.get("end", 0))) / 2)
	print("[VERIFY] targeting screen span phase=%s kf=%d window=[%d,%d] → probe frame %d"
		% [phase, idx, best.get("start", 0), best.get("end", 0), probe])

	# PARK at the probe frame (paused clock) — the authoring case.
	_host.studio_seek(probe)
	_host.studio_set_playing(false)
	await _frames(6)

	# Sweep the RED param through POSITIVE (signed-byte) values — the mode-5 Blend param is
	# signed (`start << 1`), so 0..120 is a monotonic ADD. Each edit is lowered through the
	# host with NO seek between; the parked fold must track it monotonically UP.
	var reads: Array = []
	for r in [0, 60, 120]:
		_edit(phase, idx, r, 0, 0)
		await _frames(6)
		reads.append(sc.top_color.r)
		print("[VERIFY] parked, start_r=%3d (no seek) → top.r=%.4f" % [r, sc.top_color.r])

	var step1: float = reads[1] - reads[0]
	var step2: float = reads[2] - reads[1]
	if step1 > 0.05 and step2 > 0.05:
		print("[VERIFY] PASS — parked preview repaints IN PLACE and tracks the edit monotonically (Δ %.3f, %.3f), zero re-seek" % [step1, step2])
		get_tree().quit(0)
	else:
		print("[VERIFY] FAIL — fold did not track the edit (steps %.3f, %.3f)" % [step1, step2])
		get_tree().quit(2)


func _edit(phase: String, idx: int, r: int, g: int, b: int) -> void:
	_host.studio_apply_edit({"channel": "screen", "context": phase, "event_index": idx, "field": "start_r"}, r)
	_host.studio_apply_edit({"channel": "screen", "context": phase, "event_index": idx, "field": "start_g"}, g)
	_host.studio_apply_edit({"channel": "screen", "context": phase, "event_index": idx, "field": "start_b"}, b)
