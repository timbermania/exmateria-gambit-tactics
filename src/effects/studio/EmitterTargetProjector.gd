extends RefCounted
## The **emitter** target-kind projector (ADR-0073) — the *bare emitter view*. Unlike a
## particle SPAN (EmitterProjector, which leads with an Event section of what the keyframe
## OWNS), an emitter reached directly — from a child-ref link, a provenance edge, or the
## browser — has no owning keyframe. So it shows ONLY the emitter's four characterizing
## groups (Emitter / Particle · born-with / Particle · over-life / Config, from
## `EffectScoreModel.emitter_view`) under an emitter header. NO Event section, NO
## Phase/Frames — those are keyframe facts the emitter doesn't own.
##
## The header's incoming-edge PROVENANCE (which keyframes / parents / callbacks reach this
## emitter) is added in Step 4 (`EffectScoreModel.emitter_provenance`). Model is `load()`ed
## at call time to avoid a parse-time cycle. No `class_name` (ADR-0004).


## The emitter header — its 0-based index and 1-based id (== emitter_id), then its
## INCOMING-EDGE provenance (which keyframes / parents spawn it, ADR-0073) as clickable
## reverse-navigation rows. Deliberately NO Phase/Frames (those are keyframe-owned).
static func header(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var index := int(target.get("ref", {}).get("index", -1))
	if effect_data == null or effect_data.emitters == null \
			or index < 0 or index >= effect_data.emitters.size():
		return []
	var Model = load("res://src/effects/studio/EffectScoreModel.gd")
	var rows: Array = [
		{"label": "Emitter", "value": "index %d (id %d)" % [index, index + 1]},
	]
	rows.append_array(Model.emitter_provenance(effect_data, score, index))
	return rows


## The emitter's four characterizing groups as `[Section]` — the SAME grouped projection a
## span reaches THROUGH its reference, here shown directly with no Event wrapper.
## With no owning span, the used-window (decision 5) for the evolution clock is
## the WIDEST firing span's duration across the score (tooltip says so); an
## emitter no keyframe fires keeps fully-bright sparklines with an honest note.
static func sections(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var Model = load("res://src/effects/studio/EffectScoreModel.gd")
	var index := int(target.get("ref", {}).get("index", -1))
	var widest := -1
	if score != null:
		for lane in score.get("lanes", []):
			if lane.get("kind", "") != "particle":
				continue
			for span in lane.get("spans", []):
				if int(span.get("emitter_index", -1)) == index:
					widest = maxi(widest, int(span.get("end", 0)) - int(span.get("start", 0)))
	var note := "widest firing" if widest >= 0 else "no static firing — full curve shown"
	var out: Array = []
	for group in Model.emitter_view(effect_data, index, widest, note):
		out.append({"title": group.get("title", ""), "fields": group.get("params", []),
			"velocity_formula": group.get("velocity_formula", {}),
			"ribbon": group.get("ribbon", {}),
			# Forwarded — see EmitterProjector for why this re-wrap has to carry them.
			"fold_id": group.get("fold_id", ""), "collapsed": group.get("collapsed", false)})
	return out
