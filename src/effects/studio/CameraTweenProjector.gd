extends RefCounted
const CameraUnits = preload("res://src/effects/studio/CameraUnits.gd")
const CameraValueSemantics = preload("res://src/effects/studio/CameraValueSemantics.gd")
const CameraMotion = preload("res://src/effects/studio/CameraMotion.gd")
## Per-archetype projector for CAMERA tweens (ADR-0071), now AUTHORABLE (#267).
## A camera span is one (phase, sub-channel) slice of a keyframe; the projector
## emits two Sections of F1-kit editable rows, each carrying a write-side
## `field_ref` into the #255 choke point (channel "camera"):
##
##   * "Event" — the sub-channel event's own fields: End frame, plus the command
##     word decomposed into Source (enum) / Motion+Profile (interp enums).
##     channel_mask is NOT here — it is a lowering artifact (ADR-0086); the encoder
##     splits a coalesced keyframe when one sub-channel's Event diverges.
##   * the sub-channel's own value section: angle → Pitch/Yaw/Roll, position →
##     X/Y/Z, zoom → Zoom (only slot 0 is engine-used; slots 1/2 stay verbatim).
##   * "Advanced (raw)" — the command word's Param (bits 3-4) / Flags (bits 13-15)
##     as READ-ONLY const rows. Static RE proved these are DEAD BITS the engine never
##     reads (CAMERA_COMMAND_PARAM_FLAGS_ARE_INERT.md), so they are shown for byte
##     visibility but marked non-functional, never presented as an authoring knob.
##
## Curve tracks stay N/A: the interpolation BETWEEN keyframe values is ROM-fixed,
## so we author the interp MODE (an enum) but never a curve painter here.
## Reads everything from the score-model span's own `fields` + `phase` /
## `keyframe_index` (the write-side address) — pure projection, no runtime.

# Enum choices for the command word — VALUE is the already-positioned bits (the
# enum kit fans the value, not the index). Mirror parse_effect's decode maps.
const _SOURCE_CHOICES := [
	{"value": 0x000, "label": "TARGET"}, {"value": 0x020, "label": "OFFSET"},
	{"value": 0x040, "label": "DIRECT"}, {"value": 0x060, "label": "ORIGIN"},
	{"value": 0x080, "label": "EFFECT_CTR"}, {"value": 0x0C0, "label": "MAP"},
	{"value": 0x100, "label": "SLOT_COPY"}, {"value": 0x140, "label": "CASTER"},
	{"value": 0x180, "label": "ALL_TARGETS"}, {"value": 0x1C0, "label": "CURSOR"},
]
# The interpolation enum now lives in CameraMotion as a Motion binary + kind-scoped Profile.
# Per-sub-channel value rows: display name → the CameraChannel field it fans and
# which Vector3i component seeds it.
const _VALUE_ROWS := {
	"angle": [["Pitch", "angle_x", 0], ["Yaw", "angle_y", 1], ["Roll", "angle_z", 2]],
	"position": [["X", "position_x", 0], ["Y", "position_y", 1], ["Z", "position_z", 2]],
	"zoom": [["Zoom", "zoom", 0]],
}
# The human authoring unit each sub-channel's value cell renders in (raw stays on disk).
const _UNIT := {
	"angle": CameraUnits.ANGLE_DEG,
	"position": CameraUnits.POS_TILES,
	"zoom": CameraUnits.ZOOM_X,
}


static func sections(span: Dictionary) -> Array:
	var f: Dictionary = span.get("fields", {})
	# camera_channel rides on the ref so a shared-field edit knows WHICH sub-channel it
	# addresses — the encoder splits that one out of a coalesced keyframe (ADR-0086).
	var ctx := {
		"context": str(span.get("phase", "")),
		"ordinal": int(span.get("ordinal", -1)),
		"camera_channel": str(f.get("camera_channel", "")),
	}
	var cr := int(f.get("command_raw", 0))

	# No Channels row: channel_mask is a LOWERING artifact (ADR-0086), emitted by the
	# encoder when it packs coincident sub-channel events, never set by the author.
	# Each sub-channel event owns its End frame / Source / Interp / Param / Flags; the
	# encoder splits a coalesced keyframe when one of these diverges from its siblings.
	# Length is READ-ONLY: end_frame is the single editable length knob (moving it is how
	# you change extent, which the packed schedule coalesces/splits). A direct Length edit
	# would be a second, conflicting way to say the same thing — so it stays a const view.
	var length: int = int(span.get("authored_end", 0)) - int(span.get("authored_start", 0))
	var event := {"title": "Event", "fields": [
		_int("End frame", "s16", int(f.get("end_frame", 0)), ctx, "end_frame"),
		_const("Length", str(length)),
		_enum("Source", cr & 0x01E0, _SOURCE_CHOICES, ctx, "source_mode"),
		# The interpolation field (bits 9-12) is one 4-bit slot that is EITHER a move-to-target
		# easing OR a shake — never both (a track can't move and shake at once). Surface that as
		# a Motion binary + a kind-scoped Profile, BOTH writing "interpolation" (CameraMotion).
		# Motion seeds to the kind's representative so it highlights Move/Shake for any active
		# profile; flipping it writes that kind's default profile. A shake also relabels the
		# value rows to "amplitude" (below, via CameraValueSemantics / #281).
		_enum("Motion", CameraMotion.representative(CameraMotion.kind_of(cr & 0x1E00)),
			CameraMotion.KIND_CHOICES, ctx, "interpolation"),
		_enum("Profile", cr & 0x1E00,
			CameraMotion.profile_choices(CameraMotion.kind_of(cr & 0x1E00)), ctx, "interpolation"),
		# Param (bits 3-4) and Flags (bits 13-15) are NOT here — they are dead bits the PSX
		# never reads (see below / the Advanced section), not authorable command-word knobs.
	]}

	var chan := str(f.get("camera_channel", ""))
	var vec: Vector3i = f.get(chan, Vector3i.ZERO)
	# Author each value in a HUMAN unit (degrees / tiles / ×) — the inspector's int cell
	# renders the unit and the edit converts back to raw, so storage/writer/runtime stay raw.
	# The row LABEL is mode-honest (#281): the same stored value is an absolute / offset /
	# delta / amplitude depending on source_mode × interpolation.
	var unit: Dictionary = _UNIT.get(chan, {})
	var source_mode := str(f.get("source_mode", ""))
	var interp := str(f.get("interpolation", ""))
	# Under a SHAKE_* interp the value is a symmetric ± peak (the engine adds a per-frame
	# random_in_range(-amp, +amp)), not a target — so decorate the SAME-unit value with a "±".
	# An INERT row (zoom under OFFSET/CURSOR, which the runtime no-ops) is neither a target nor
	# a shake peak, so it gets no "±" even if the interp is SHAKE_* — the label already says
	# "(inert)".
	var inert := CameraValueSemantics.is_inert(chan, source_mode)
	var amp := CameraValueSemantics.is_amplitude(interp) and not inert
	var value_fields: Array = []
	for row in _VALUE_ROWS.get(chan, []):
		var name: String = CameraValueSemantics.label(row[0], chan, row[2], source_mode, interp)
		var extra := {"unit": unit}
		if amp:
			extra["prefix"] = "±"
		value_fields.append(_int(name, "s16", vec[row[2]], ctx, row[1], extra))
	var title := "Cam %s" % chan

	# Advanced (raw): the command word's Param (bits 3-4) and Flags (bits 13-15). Static RE
	# proved these are DEAD BITS — the PSX engine never masks, tests, or indexes off them on
	# the camera path (research/working_documents/CAMERA_COMMAND_PARAM_FLAGS_ARE_INERT.md), and
	# the data shows Flags is only ever set by one misparsed table. So they are shown for byte
	# visibility but as READ-ONLY const rows (no field_ref) under a note that marks them
	# non-functional — an author can see a non-zero value on a real effect without mistaking it
	# for a working control. The bytes still round-trip byte-exact via command_raw regardless.
	# Shut on arrival, under a stable fold id — same reasoning as the emitter's Advanced
	# section (EffectScoreModel): dead bits are the last thing an author needs the row's
	# scarce height for, and the id is what makes the author's choice outlive a rebuild.
	var advanced := {"title": "Advanced (raw)", "fold_id": "camera-advanced", "collapsed": true,
		"note": "Non-functional — the engine ignores these bits (byte-preserved only).",
		"fields": [
			_const("Param", str(int(f.get("param_index", 0)))),
			_const("Flags", str(int(f.get("flags", 0)))),
		]}

	return [event, {"title": title, "fields": value_fields}, advanced]


## Lane summary: an editor-side hook the score lane draws. Unchanged shape from the
## prior read-only projector (label the sub-channel).
static func summarize(span: Dictionary) -> Dictionary:
	var f: Dictionary = span.get("fields", {})
	return {"label": "Cam %s" % str(f.get("camera_channel", "")), "border": "solid"}


static func _ref(ctx: Dictionary, field: String) -> Dictionary:
	# The write-side address is (camera_channel, ordinal) — the event's position in its
	# sub-channel lane (ADR-0086 dec. 5, #286) — so the edit survives a split/merge
	# that renumbers the packed keyframe array.
	return {
		"channel": "camera",
		"context": ctx.get("context", ""),
		"ordinal": int(ctx.get("ordinal", -1)),
		"camera_channel": ctx.get("camera_channel", ""),
		"field": field,
	}


static func _int(name: String, type: String, value: int, ctx: Dictionary, field: String, extra: Dictionary = {}) -> Dictionary:
	var cell := {"name": name, "shape": "edit", "editor": "int", "type": type,
		"value": value, "field_ref": _ref(ctx, field)}
	for k in extra:
		cell[k] = extra[k]
	return cell


static func _enum(name: String, value: int, choices: Array, ctx: Dictionary, field: String) -> Dictionary:
	return {"name": name, "shape": "edit", "editor": "enum", "value": value,
		"choices": choices, "field_ref": _ref(ctx, field)}


## A read-only display row (no editor, no field_ref) — for facts the author reads but
## must not edit directly, like the derived span Length.
static func _const(name: String, value: String) -> Dictionary:
	return {"name": name, "shape": "const", "value": value}
