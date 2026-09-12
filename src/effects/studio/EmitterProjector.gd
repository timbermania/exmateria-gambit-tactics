extends RefCounted
## Per-archetype projector for **particle spans** (ADR-0071). Projects a span into
## the keyframe inspector's uniform `[Section]` list, honoring the two-level split:
## an **Event** section of what the span OWNS (the referenced emitter id + action
## flags), then the SHARED emitter's characterizing groups (Emitter / Particle ·
## born-with / Particle · over-life / Config) a level deeper. Pure projection
## (display strings), the model's job — the inspector is thin glue (ADR-0069).
##
## `Section = { title, fields, note? }`. The Section is the uniform container; the
## field atoms inside stay archetype-appropriate (the Event section's "Emitter" row is
## now a `link` to the emitter's bare view, ADR-0073; the emitter groups' are the rich
## param rows from emitter_view).

const Target = preload("res://src/effects/studio/InspectionTarget.gd")


## Project a particle span + its parsed EffectData into `[Section]`.
static func sections(span: Dictionary, effect_data) -> Array:
	# Loaded at call time (not a const preload) to avoid a parse-time cycle — the score
	# model const-preloads this projector for its inspector dispatcher.
	var Model = load("res://src/effects/studio/EffectScoreModel.gd")
	var out: Array = []
	# Section 1 — what the EVENT owns (ADR-0071): the referenced emitter id + the
	# action flags. `const` name/value rows — NOT the emitter's params, which live a
	# level deeper in the emitter sections below.
	# The "Emitter" row is a LINK to the referenced emitter's bare view (ADR-0073): from a
	# keyframe you can drill into the shared emitter (params/curves/its own children), not
	# just read its id. Action flags stay a const the event owns.
	var emitter_index := int(span.get("emitter_index", -1))
	# The span's WHEN/WHICH controls (ADR-0089 particle_timeline): an Enabled checkbox (mutes
	# the span to a null span, remembering the emitter) and a Fires-emitter retarget picker
	# (editable even while disabled). Both lower through the "particle" channel at this span's
	# flat raw address. The "Emitter" LINK (ADR-0073 drill-in to the shared params) is kept.
	var disabled := bool(span.get("disabled", false))
	var addr := _particle_addr(span)
	out.append({"title": "Event", "fields": [
		{"name": "Emitter", "shape": "link",
			"label": "index %d (id %d)" % [emitter_index, int(span.get("emitter_id", 0))],
			"target": Target.emitter(emitter_index)},
		{"name": "Enabled", "shape": "edit", "editor": "enum",
			"value": 0 if disabled else 1,
			"field_ref": _particle_ref(addr, "enabled"),
			"choices": [{"value": 0, "label": "Disabled"}, {"value": 1, "label": "Enabled"}],
			"tooltip": "Mute this span to a null span (session-only — a saved-disabled span reloads as a gap)"},
		{"name": "Fires emitter", "shape": "edit", "editor": "enum",
			"value": emitter_index,
			"field_ref": _particle_ref(addr, "emitter_index"),
			"choices": _emitter_choices(effect_data),
			"tooltip": "Point this span at a different emitter (retarget — editable even while disabled)"},
		{"name": "Action flags", "shape": "const",
			"value": "0x%02X" % int(span.get("action_flags", 0))},
	]})
	# Sections 2..N — the SHARED emitter's characterizing groups (Emitter / born-with
	# / over-life / Config), reached THROUGH the reference. emitter_view returns
	# {title, params}; the Section's uniform row key is "fields" (params kept as-is).
	# Each carries a "shared by N events" note — the honest fan-out signal (ADR-0071):
	# editing the emitter affects every span that references it.
	var shared := _reference_count(effect_data, int(span.get("emitter_id", 0)))
	var note := "shared by %d event%s" % [shared, "" if shared == 1 else "s"]
	# Used-window (decision 5), span surface: evolution params sample by
	# emitter-elapsed frame, so THIS firing's duration is the window.
	var window := int(span.get("end", 0)) - int(span.get("start", 0))
	for group in Model.emitter_view(effect_data, int(span.get("emitter_index", -1)),
			window, "this firing"):
		out.append({"title": group.get("title", ""), "fields": group.get("params", []), "note": note,
			"velocity_formula": group.get("velocity_formula", {}),
			"ribbon": group.get("ribbon", {}),
			# Forwarded, not invented here: a group states its own fold identity and its
			# opening state (Advanced (raw) asks to arrive shut), and this re-wrap is the
			# only thing between `emitter_view` and the inspector. A key dropped here is a
			# hint the author never sees.
			"fold_id": group.get("fold_id", ""), "collapsed": group.get("collapsed", false)})
	return out


## The span's flat particle address (phase context + channel_index + raw keyframe index) —
## the ParticleTimelineChannel edit address, shared by both Event-section edit rows.
static func _particle_addr(span: Dictionary) -> Dictionary:
	return {
		"context": String(span.get("phase", "")),
		"channel_index": int(span.get("channel_index", -1)),
		"event_index": int(span.get("keyframe_index", -1)),
	}


## A "particle" channel field_ref for `field` at the span's address.
static func _particle_ref(addr: Dictionary, field: String) -> Dictionary:
	var ref := addr.duplicate()
	ref["channel"] = "particle"
	ref["field"] = field
	return ref


## Retarget-picker choices: one entry per defined emitter (0-based index → id index+1). Mirrors
## the child-wiring pickers ("one choice per emitter"), minus the "none" option — a span always
## fires something; muting is the separate Enabled toggle.
static func _emitter_choices(effect_data) -> Array:
	var out: Array = []
	var count: int = effect_data.emitters.size() if effect_data != null else 0
	for i in range(count):
		out.append({"value": i, "label": "E%d (id %d)" % [i, i + 1]})
	return out


## How many spans reference this emitter across every channel/phase — the count the
## "shared by N" note reports. Mirrors the drawn-span filter (`emitter_id != 0`).
static func _reference_count(effect_data, emitter_id: int) -> int:
	if effect_data == null or effect_data.timeline == null or emitter_id == 0:
		return 0
	var count := 0
	for context in effect_data.timeline.channels_by_context:
		for channel in effect_data.timeline.channels_by_context[context]:
			for kf in channel.keyframes:
				if kf.emitter_id == emitter_id:
					count += 1
	return count
