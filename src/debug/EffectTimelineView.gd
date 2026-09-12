extends Control
## Embedded EffectViewer timeline strip — thin drawing glue over EffectTimelineModel
## (particle channels) + ColorTimelineModel (screen + palette tints). The models
## compute the static "score" (per-channel spans in absolute frames); this Control
## stacks them as lanes and sweeps a live playhead across from the bound
## EffectInstance's clock, so you can see WHAT is playing WHEN and WHERE the phase
## transitions land. Watch-mode only (read-only, no seeking); mouse passes through.
##
## Bound by EffectViewerScene on play_effect(); cleared on stop. See the two
## *Model.gd files (+ their tests) for the testable cores.

const ParticleModel = preload("res://src/debug/EffectTimelineModel.gd")
const ColorModel = preload("res://src/debug/ColorTimelineModel.gd")
const EffectPhaseClass = ExMateriaEffects.EffectPhase

const LABEL_W: float = 104.0
const ROW_H_MAX: float = 15.0
const ROW_GAP: float = 3.0
const TOP_PAD: float = 22.0   # header line
const BOT_PAD: float = 16.0   # axis labels
const SIDE_PAD: float = 8.0

# Phase band tints (behind the lanes), keyed by context.
const _BAND := {
	"phase1": Color(0.16, 0.22, 0.34, 0.55),
	"for_each": Color(0.16, 0.30, 0.22, 0.55),
	"phase2": Color(0.30, 0.20, 0.30, 0.55),
}

var _effect = null            # EffectInstance; scene owns lifetime + calls clear()
var _model: Dictionary = {}         # particle score
var _color_model: Dictionary = {}   # screen + palette score
var _p1d: int = 0
var _p2s: int = 0
var _max_frame: int = 1
var _particle_lane_count: int = 0   # where the color section starts (for the divider)
var _last_frame: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # let camera/UI input pass through
	set_process(true)


## Point the strip at a freshly-played EffectInstance: snapshot its particle + color
## scores once (keyframes don't change during playback) and start tracking its clock.
func bind(effect) -> void:
	_effect = effect
	_model = {}
	_color_model = {}
	_p1d = 0
	_p2s = 0
	_max_frame = 1
	_particle_lane_count = 0
	_last_frame = -1
	if effect != null and effect.effect_data != null:
		if effect.effect_timeline != null:
			_p1d = effect.effect_timeline.phase1_duration
			_p2s = effect.effect_timeline.phase2_start
		if effect.effect_data.timeline != null:
			_model = ParticleModel.build(effect.effect_data.timeline, _p1d, _p2s)
		_color_model = ColorModel.build(effect.effect_data.screen, effect.effect_data.palette, _p1d, _p2s)
		_max_frame = maxi(maxi(1, _p2s), maxi(_model.get("max_frame", 1), _color_model.get("max_frame", 1)))
		_particle_lane_count = _model.get("lanes", []).size()
	queue_redraw()


func clear() -> void:
	_effect = null
	_model = {}
	_color_model = {}
	queue_redraw()


func _process(_delta: float) -> void:
	if _effect != null and not is_instance_valid(_effect):
		clear()
		return
	if _effect == null:
		return
	var f: int = _effect.get_effect_frame()
	if f != _last_frame:
		_last_frame = f
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := 11
	# Backing panel so the strip reads over the 3D scene.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08, 0.88))

	var lanes := _build_lanes()
	if _effect == null or lanes.is_empty():
		draw_string(font, Vector2(SIDE_PAD, TOP_PAD), "No effect playing — press Play",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.6, 0.6, 0.65))
		return

	var max_frame := maxi(1, _max_frame)
	var plot_left := SIDE_PAD + LABEL_W
	var plot_right := size.x - SIDE_PAD
	var plot_w := maxf(1.0, plot_right - plot_left)
	var plot_top := TOP_PAD
	var plot_bot := size.y - BOT_PAD
	var avail_h := maxf(1.0, plot_bot - plot_top)

	var lane_count := maxi(1, lanes.size())
	var row_h := minf(ROW_H_MAX, (avail_h - (lane_count - 1) * ROW_GAP) / lane_count)

	var x_of := func(frame: int) -> float:
		return plot_left + clampf(float(frame) / float(max_frame), 0.0, 1.0) * plot_w

	# Phase bands behind the lanes.
	if _p1d > 0:
		_band(x_of.call(0), x_of.call(_p1d), plot_top, plot_bot, _BAND["phase1"])
	var fe_end: int = _p2s if _p2s > _p1d else max_frame
	_band(x_of.call(_p1d), x_of.call(fe_end), plot_top, plot_bot, _BAND["for_each"])
	if _p2s > _p1d:
		_band(x_of.call(_p2s), x_of.call(max_frame), plot_top, plot_bot, _BAND["phase2"])

	# Lanes: label + span blocks.
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var y := plot_top + i * (row_h + ROW_GAP)
		# Divider between the particle section and the color section.
		if i == _particle_lane_count and _particle_lane_count > 0:
			draw_line(Vector2(SIDE_PAD, y - ROW_GAP * 0.5), Vector2(plot_right, y - ROW_GAP * 0.5),
				Color(0.4, 0.42, 0.5, 0.7), 1.0)
		draw_string(font, Vector2(SIDE_PAD, y + row_h - 3), lane["label"],
			HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 4, fs, Color(0.72, 0.74, 0.80))
		for span in lane["spans"]:
			var x0: float = x_of.call(span["start"])
			var x1: float = x_of.call(span["end"])
			var w := maxf(2.0, x1 - x0)
			var col: Color = span["color"]
			draw_rect(Rect2(x0, y, w, row_h), col)
			draw_rect(Rect2(x0, y, w, row_h), col.darkened(0.4), false, 1.0)
			if lane["particle"] and w >= 16.0:
				draw_string(font, Vector2(x0 + 3, y + row_h - 3), str(span["label"]),
					HORIZONTAL_ALIGNMENT_LEFT, w - 4, fs, Color(0.02, 0.02, 0.02))

	# Phase boundary lines + axis ticks.
	if _p1d > 0:
		_boundary(x_of.call(_p1d), plot_top, plot_bot, font, fs, "p1▸fe")
	if _p2s > _p1d:
		_boundary(x_of.call(_p2s), plot_top, plot_bot, font, fs, "fe▸p2")
	for f in _axis_ticks(max_frame, _p1d, _p2s):
		draw_string(font, Vector2(x_of.call(f) - 6, size.y - 4), str(f),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, Color(0.55, 0.57, 0.62))

	# Live playhead.
	var frame: int = _effect.get_effect_frame() if is_instance_valid(_effect) else 0
	var px: float = x_of.call(frame)
	draw_line(Vector2(px, plot_top - 4), Vector2(px, plot_bot), Color(1.0, 0.85, 0.2), 2.0)
	draw_string(font, Vector2(px - 4, plot_top - 6), "▼",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.85, 0.2))

	# Header: effect · frame · particles · open phase set.
	var phases := "-"
	if is_instance_valid(_effect) and _effect.effect_timeline != null:
		phases = "+".join(_effect.effect_timeline.current_phase())
	var particles: int = _effect.get_active_particle_count() if is_instance_valid(_effect) else 0
	var header := "%s   frame %d/%d   particles %d   [%s]" % [
		_effect.effect_name if is_instance_valid(_effect) else "?",
		frame, max_frame, particles, phases]
	draw_string(font, Vector2(SIDE_PAD, 14), header,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.92, 0.93, 0.98))


## Flatten both models into one row list: particle lanes first (emitter-hued,
## numbered), then color lanes (screen + palette, in their real tint color).
func _build_lanes() -> Array:
	var out: Array = []
	for lane in _model.get("lanes", []):
		var spans: Array = []
		for s in lane["spans"]:
			spans.append({
				"start": s["start"], "end": s["end"],
				"color": _emitter_color(s["emitter_index"]), "label": s["emitter_index"],
			})
		out.append({
			"label": "%s ch%d" % [_ctx_abbrev(lane["context"]), lane["channel_index"]],
			"spans": spans, "particle": true,
		})
	for lane in _color_model.get("lanes", []):
		out.append({
			"label": "%s %s" % [_ctx_abbrev(lane["context"]), _color_abbrev(lane["channel"])],
			"spans": lane["spans"], "particle": false,
		})
	return out


func _band(x0: float, x1: float, top: float, bot: float, col: Color) -> void:
	if x1 - x0 > 0.5:
		draw_rect(Rect2(x0, top, x1 - x0, bot - top), col)


func _boundary(x: float, top: float, bot: float, font, fs: int, label: String) -> void:
	draw_line(Vector2(x, top - 2), Vector2(x, bot), Color(0.85, 0.85, 0.9, 0.7), 1.0)
	draw_string(font, Vector2(x + 2, top + 9), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, Color(0.85, 0.85, 0.9))


## Frames worth an axis tick: 0, both boundaries, and the end.
func _axis_ticks(max_frame: int, p1d: int, p2s: int) -> Array:
	var ticks := {0: true, max_frame: true}
	if p1d > 0 and p1d < max_frame:
		ticks[p1d] = true
	if p2s > p1d and p2s < max_frame:
		ticks[p2s] = true
	var out: Array = ticks.keys()
	out.sort()
	return out


func _ctx_abbrev(context: String) -> String:
	match context:
		EffectPhaseClass.PHASE1: return "p1"
		EffectPhaseClass.PHASE_FOR_EACH: return "fe"
		EffectPhaseClass.PHASE2: return "p2"
		_: return context


## Palette/screen channel short labels for the lane gutter.
func _color_abbrev(channel: String) -> String:
	match channel:
		"screen": return "scr"
		"affected_units": return "map"
		"caster": return "cast"
		"target": return "tgt"
		_: return channel


## Stable, well-spread hue per emitter index (golden-ratio spacing).
func _emitter_color(emitter_index: int) -> Color:
	var hue := fmod(float(emitter_index) * 0.6180339887, 1.0)
	return Color.from_hsv(hue, 0.55, 0.92)
