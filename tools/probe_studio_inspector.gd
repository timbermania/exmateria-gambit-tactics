extends SceneTree
## [Studio inspector probe] Headful visual check of the keyframe inspector's ONE
## render path (ADR-0071): for a particle span (E004 emitter 0) the Event section +
## the shared emitter's grouped, param-shaped, sparkline-per-param accordion, saved as
## a screenshot. Proves the accordion + per-param sparklines + enabled/disabled greying
## render — the parts TDD asserts structurally but can't judge visually.
##
## Run (NEVER headless), from the package root:
##   godot --path . -s res://tools/probe_studio_inspector.gd
## Writes /tmp/studio_inspector.png then quits.

const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _f := 0
var _insp
var _ed
var _view: Array
var _shown := false


func _initialize() -> void:
	root.title = "Studio inspector probe"
	root.size = Vector2i(720, 900)

	_ed = ExMateriaEffects.EffectData.load_from_directory("res://assets/effects/E004")
	_view = Model.emitter_view(_ed, 0)
	print("[probe] emitters=%d view_groups=%d" % [_ed.emitters.size(), _view.size()])

	_insp = Inspector.new()
	root.add_child(_insp)
	# Capped dock: a realistic narrow width (single-column, where alignment matters)
	# and a height shorter than the content so overflow must scroll inside the panel.
	_insp.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_insp.position = Vector2(10, 10)
	_insp.custom_minimum_size = Vector2(700, 560)


func _process(_delta: float) -> bool:
	_f += 1
	# Render after the inspector's _ready has built its grid (first frame). ONE path
	# now (ADR-0071): header rows + the projector [Section] list — for a particle span
	# that's the Event section + the shared emitter's grouped, sparkline-per-param groups.
	if not _shown:
		_shown = true
		# ADR-0073 replaced the raw-span argument with an INSPECTION TARGET resolved
		# against a real score, and `show_sections` with `show_target`. This probe kept
		# hand-rolling a span dict and calling the ADR-0071 shape, so it has been a PARSE
		# error ("Too few arguments") — an unloadable script, invisible because nothing
		# runs it and a warm .godot/ hides it. #459.
		var score: Dictionary = Model.build(_ed)
		var target: Dictionary = Target.span(_first_particle_span_id(score))
		_insp.show_target(target,
			Model.inspector_header(target, _ed, score),
			Model.inspector_sections(target, _ed, score),
			func(i):
				var c = _ed.get_curve(i)
				return c.samples if c != null else [],
			func(ci, nm): print("[open-curve] curve %d — %s" % [ci, nm]))
		print("[probe] groups=%d param_rows=%d sparklines=%d" % [
			_insp.group_count(), _insp.param_row_count(), _insp.sparklines().size()])
		return false
	if _f < 20:
		return false
	var img := root.get_texture().get_image()
	img.save_png("/tmp/studio_inspector.png")
	print("[probe] saved /tmp/studio_inspector.png")
	return true


## The first `particle` span in the built score — the archetype this probe exists to
## render. Falls back to the first span of any kind so the probe still draws something
## rather than an empty panel if E004's lanes ever change shape.
func _first_particle_span_id(score: Dictionary) -> String:
	var first := ""
	for lane in score.get("lanes", []):
		for span in lane.get("spans", []):
			var sid := String(span.get("id", ""))
			if sid == "":
				continue
			if first == "":
				first = sid
			if String(span.get("kind", "")) == "particle":
				return sid
	return first
