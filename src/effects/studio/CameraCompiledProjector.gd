extends RefCounted
## Per-archetype projector for the CAMERA COMPILED (storage/truth) span — the strictly
## READ-ONLY observability pane over the packed camera keyframe table. It is the storage
## companion to CameraTweenProjector (which AUTHORS the sub-channels, ADR-0086): where
## that emits editable sub-channel rows, this shows what the bytes actually say for ONE
## packed keyframe, so a designer can watch their sub-channel edits coalesce/split into
## the real schedule.
##
## Every row is a `const` (ProjectorField.const_field) — no `edit`, no `link`, no
## `field_ref`. Editing the packed form is impossible BY CONSTRUCTION: the orphan bug
## ADR-0086 killed (an authored channel_mask) can never come back through this surface.
##
## Pure projection: reads the span's own `fields` (the raw packed values the score model
## captured). A compiled keyframe is a point marker, so there is no Length/duration row —
## the storage stores only End frame. No runtime, no effect_data.

const ProjectorField = preload("res://src/effects/studio/ProjectorField.gd")

# mask bit → sub-channel name, low bit first, so a combined mask reads angle→position→zoom.
const _CHANNEL_BITS := [[1, "angle"], [2, "position"], [4, "zoom"]]


static func sections(span: Dictionary) -> Array:
	var f: Dictionary = span.get("fields", {})
	# No Length row: a compiled keyframe is a POINT marker (a target reached at End frame).
	# The storage stores no duration — the real per-sub-channel window lives on the
	# angle/position/zoom lanes, not this storage view (see EffectScoreModel markers).
	return [{"title": "Compiled keyframe", "fields": [
		ProjectorField.const_field("Index", str(int(f.get("index", span.get("keyframe_index", -1))))),
		ProjectorField.const_field("End frame", str(int(f.get("end_frame", 0)))),
		ProjectorField.const_field("Channels", _channels_label(int(f.get("channel_mask", 0)))),
		ProjectorField.const_field("Source", str(f.get("source_mode", ""))),
		ProjectorField.const_field("Interp", str(f.get("interpolation", ""))),
		ProjectorField.const_field("Param", str(int(f.get("param_index", 0)))),
		ProjectorField.const_field("Flags", str(int(f.get("flags", 0)))),
		ProjectorField.const_field("Command word", "0x%04X" % int(f.get("command_raw", 0))),
	]}]


## Decode a channel_mask into the sub-channel names it drives, joined with " + " so the
## coalescing is legible ("angle + position"). An empty mask reads "none".
static func _channels_label(mask: int) -> String:
	var names: Array = []
	for bit in _CHANNEL_BITS:
		if mask & int(bit[0]) != 0:
			names.append(bit[1])
	return " + ".join(names) if not names.is_empty() else "none"
