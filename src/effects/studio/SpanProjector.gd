extends RefCounted
## The **span** target-kind projector (ADR-0073). A span is the timeline's *drill-in
## handle* to whatever a keyframe addresses — so this projector resolves the target's
## `span_id` back to the score's span Dictionary and delegates to the archetype
## dispatch (`EffectScoreModel.span_sections` / `span_header_rows`), which routes to the
## per-archetype span projectors (EmitterProjector / ScreenTweenProjector / …, ADR-0071).
##
## This is the SPAN half of the target-kind seam; the EMITTER half is EmitterTargetProjector.
## Both are registered in InspectorProjectorRegistry. Model is `load()`ed at call time
## (not preloaded) to avoid a parse-time cycle — the registry preloads this projector.
## No `class_name` (ADR-0004).


## The archetype-independent context rows (Kind / Phase / Frames / Authored) for the
## addressed span — unchanged from the pre-ADR-0073 `inspector_header`.
static func header(target: Dictionary, _effect_data, score: Dictionary) -> Array:
	var Model = load("res://src/effects/studio/EffectScoreModel.gd")
	var span: Dictionary = Model.find_span(score, str(target.get("ref", {}).get("span_id", "")))
	if span.is_empty():
		return []
	return Model.span_header_rows(span)


## The span's `[Section]` list: a particle span's Event section + the SHARED emitter
## groups, a tween/trigger's single section — the archetype dispatch owned by the model.
static func sections(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var Model = load("res://src/effects/studio/EffectScoreModel.gd")
	var span: Dictionary = Model.find_span(score, str(target.get("ref", {}).get("span_id", "")))
	if span.is_empty():
		return []
	return Model.span_sections(span, effect_data)
