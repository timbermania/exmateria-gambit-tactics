extends RefCounted
## Per-archetype projector for PALETTE tweens (ADR-0071) — the unit/map tint lanes
## (affected_units / caster / target). A palette tween owns its params inline; unlike
## screen it has a single kind, so it projects one Section. See CONTEXT "Tween".
##
## EDITABLE via the F1 shared kit: the RGB tint is a SIGNED Δ through the blend mode
## (ADR-0087), so it is a WYSIWYG result-picker (`target_color`) — the author picks the
## colour a fixed mid-grey reference should BECOME and the host back-solves the Δ
## (PaletteTintSolver) through the same forward fold the preview uses, exactly like screen's
## Blend. (The #266 absolute-unsigned `gradient_color` reuse — colour = raw/255 — was the
## "seek-color renders the wrong hue" bug and is retired here.) The blend mode is a
## value-carrying `enum` (ctrl bits 0-6, codes 0-10). Both lower through the palette channel
## encoder at the
## single choke point (EffectEditSession.apply_edit). Palette colour is read-live so an
## edit repaints in place (EffectInstance.redeliver_colors). Enabling/disabling a track
## (ctrl bit-7) is a SCALAR in-place toggle (ADR-0087), NOT structural: it never adds or
## removes a lane span — a disabled tween keeps its tile (fully-tiled lane) and holds the
## prior keyframe's still-live tint (a null tween), so the fold stays contiguous.
##
## The write-side address is derived from the SPAN itself: phase (channel context),
## fields.channel (affected_units/caster/target — palette's second address dimension),
## and keyframe_index. No `class_name` (ADR-0004).

const _Fields = preload("res://src/effects/studio/ProjectorField.gd")
const _Rows = preload("res://src/effects/studio/ColorTweenRows.gd")
const _TintSolver = preload("res://src/effects/studio/PaletteTintSolver.gd")

# The two restore modes (8/10) ignore the Δ — their tint cell is ABSENT (a mode-shaped
# field set, ADR-0087), so a keyframe in either mode carries no colour to author.
const _RESTORE_MODES := [8, 10]


static func sections(span: Dictionary) -> Array:
	var f: Dictionary = span.get("fields", {})
	var mode := int(f.get("blend_mode", 0))
	var rgb = f.get("rgb", Vector3i.ZERO)
	# The harmonized rows come from the ONE shared builder (ColorTweenRows, amendment §6);
	# this adapter contributes only palette's facts: the 2-D address, the enabled bit's
	# derived state, the self-computable tint seed (the forward fold of the stored bytes over
	# the fixed mid-grey reference — no host runtime needed), and the 1× Δ (no doubling).
	var fields: Array = [
		_Fields.const_field("Channel", str(f.get("channel", ""))),
	]
	# The Spacer note is REMOVED (ADR-0087 dec. 28): an inert spacer is now
	# invisible empty space you can't select, so the only section shown for an inert keyframe is
	# a DELIBERATELY-DISABLED (still-selectable) event, which relies on the Enabled row below —
	# no flavour note. The oracle still computes the verdict (to decide what to hide); it just
	# no longer narrates it.
	fields.append(_Rows.enabled_row(bool(f.get("enabled", false)), _palette_ref(span, "enabled")))
	# The tint is a signed Δ through the mode — absent for the restores (they carry no colour).
	# Two views of the SAME rgb bytes: the WYSIWYG result-picker (pick a colour) and a precise
	# signed-Δ row (see/type the raw delta; 0,0,0 = the unambiguous no-op the picker can't show).
	if not (mode in _RESTORE_MODES):
		fields.append(_Rows.tint_row("Tint", _rgb_refs(span),
			_TintSolver.result(mode, int(rgb.x), int(rgb.y), int(rgb.z))))
		fields.append(_Rows.delta_row(rgb, _rgb_refs(span), false))
	fields.append(_Rows.blend_mode_row(mode, _palette_ref(span, "blend_mode")))
	fields.append(_Rows.duration_row(int(f.get("duration_frames", 0)),
		_palette_ref(span, "duration")))
	return [{"title": "Palette tint", "fields": fields}]


## Lane summary: label + fill colour (the tint the keyframe produces).
static func summarize(span: Dictionary) -> Dictionary:
	return {"label": "Tint", "color": span.get("color", Color.BLACK), "border": "solid"}


## The three per-component write-side field_refs for the tint bytes — the SAME r/g/b bytes
## the picker back-solves and the Δ row types.
static func _rgb_refs(span: Dictionary) -> Dictionary:
	return {
		"r": _palette_ref(span, "r"),
		"g": _palette_ref(span, "g"),
		"b": _palette_ref(span, "b"),
	}


## One field's write-side field_ref for the choke point (EffectEditSession.apply_edit).
## Palette has a TWO-dimensional address — phase context AND channel_name — unlike
## screen's single context.
static func _palette_ref(span: Dictionary, field: String) -> Dictionary:
	return {
		"channel": "palette",
		"context": str(span.get("phase", "")),
		"channel_name": str(span.get("fields", {}).get("channel", "")),
		"event_index": int(span.get("keyframe_index", -1)),
		"field": field,
	}
