extends RefCounted
## Per-archetype projector for SCREEN tweens (ADR-0071). A screen tween owns its
## params INLINE (no shared referenced entity); its KIND — ScreenData.ScreenMode,
## from ctrl bit-7 — selects which params are live:
##   - BLEND: recolor the whole backdrop through one of 11 blend modes with a single
##     shared RGB param. Live: {Color, Blend mode, Duration}.
##   - GRADIENT: set the backdrop's two stops to explicit top & bottom colors.
##     Live: {Top color, Bottom color, Duration}.
## Live-fields-only (ADR-0071): a field the kind doesn't use is ABSENT, not greyed —
## the discrimination lives here in the model, so the inspector stays a dumb renderer.
## Pure display-string projection; one Section (screen is single-channel).

const ScreenDataClass = ExMateriaEffects.ScreenData
const _Rows = preload("res://src/effects/studio/ColorTweenRows.gd")
const _Chan = preload("res://src/effects/studio/ScreenChannel.gd")


## Project one screen tween (a ScreenData.Keyframe) into the inspector's `[Section]`.
## The kind (kf.mode) selects the section title AND its live field-set — a field the
## kind doesn't use is simply not emitted (live-fields-only, ADR-0071).
##
## `field_ctx` = {context, event_index} — the span's phase + keyframe index — lets the
## Blend "RGB" cell carry per-component write-side field_refs so an author edit lowers
## into the #255 choke point. Absent (bare read-only projection), the RGB cell still
## renders editable but its field_refs address the default (context "", index −1).
static func sections(kf, field_ctx: Dictionary = {}) -> Array:
	# The harmonized rows come from the ONE shared builder (ColorTweenRows, amendment §6);
	# this adapter contributes only screen's facts: the 1-D address, the DERIVED enabled state
	# (identity-no-op bytes OR stash — is_disabled), the ×2 Δ doubling, and a tint row whose
	# seed is runtime-injected by the page (the live folded top colour). Kind + the Gradient
	# stop cells stay screen-only (no palette counterpart).
	# The Spacer note is REMOVED (ADR-0087 dec. 28): an inert spacer is now
	# invisible empty space you can't select, so the only section shown for an inert keyframe is
	# a DELIBERATELY-DISABLED (still-selectable) event, which relies on the Enabled row — no
	# flavour note. is_disabled still derives the Enabled control's state.
	if kf.mode == ScreenDataClass.ScreenMode.BLEND:
		var fields: Array = [_kind_edit(kf, field_ctx)]
		fields.append_array([
			_Rows.enabled_row(not _Chan.is_disabled(kf), _screen_ref(field_ctx, "enabled")),
			_Rows.tint_row("Color", _start_refs(field_ctx)),
			_Rows.delta_row(Vector3i(int(kf.start_r_raw), int(kf.start_g_raw), int(kf.start_b_raw)),
				_start_refs(field_ctx), true),
			_Rows.blend_mode_row(int(kf.blend_mode), _screen_ref(field_ctx, "blend_mode")),
			_Rows.duration_row(int(kf.duration_frames), _screen_ref(field_ctx, "duration")),
		])
		return [{"title": "Blend", "fields": fields}]
	# GRADIENT: an absolute set of the two backdrop stops to explicit colors.
	var gfields: Array = [_kind_edit(kf, field_ctx)]
	gfields.append_array([
		_Rows.enabled_row(not _Chan.is_disabled(kf), _screen_ref(field_ctx, "enabled")),
		_gradient_color_edit("Top color", kf.start_color, field_ctx, "start_r", "start_g", "start_b"),
		_gradient_color_edit("Bottom color", kf.end_color, field_ctx, "end_r", "end_g", "end_b"),
		_Rows.duration_row(int(kf.duration_frames), _screen_ref(field_ctx, "duration")),
	])
	return [{"title": "Gradient", "fields": gfields}]


## Lane summary: the span's label, fill color, and border style. Blend and Gradient
## share the fill (the color the tween produces — its shared/top stop) and are told
## apart by label + border, so a Gradient tween is finally distinguishable from a
## Blend on the screen lane (ADR-0071). The SPACER verdict is NOT summarized here — it is the
## contextual disable-equivalence fold the score model computes lane-wide. Fifth amendment: an
## enabled inert spacer is HIDDEN (invisible empty space), so this produced fill only shows for
## live events (and, dimmed, for a deliberately-disabled one); the border stays kind.
static func summarize(kf) -> Dictionary:
	if kf.mode == ScreenDataClass.ScreenMode.BLEND:
		return {"label": "Blend", "color": kf.start_color, "border": "solid"}
	return {"label": "Grad", "color": kf.start_color, "border": "dashed"}


## The three per-component write-side field_refs for the Blend's shared RGB param — the SAME
## start_r/g/b bytes the picker back-solves (through the host's BlendTargetSolver and the REAL
## forward fold: the param is a SIGNED byte applied doubled, `start << 1`) and the Δ row types.
static func _start_refs(field_ctx: Dictionary) -> Dictionary:
	return {
		"r": _screen_ref(field_ctx, "start_r"),
		"g": _screen_ref(field_ctx, "start_g"),
		"b": _screen_ref(field_ctx, "start_b"),
	}


## An EDITABLE plain-colour Gradient-stop cell (#255 scope B). Unlike the Blend `target_color`
## cell, a Gradient stop is an UNSIGNED ABSOLUTE colour (`colour = raw/255`), so there is NO
## signed solver — the picker fans three direct byte writes (`round(c·255)`) straight through the
## choke point. The cell carries the three per-component write-side field_refs (Top → start_r/g/b,
## Bottom → end_r/g/b) AND a `seed` colour: because the stop IS the keyframe's absolute value, the
## projector knows the seed directly (no host runtime needed, unlike the read-live Blend seed).
static func _gradient_color_edit(name: String, seed: Color, field_ctx: Dictionary, rf: String, gf: String, bf: String) -> Dictionary:
	return {
		"name": name,
		"shape": "edit",
		"editor": "gradient_color",
		"seed": seed,
		"field_refs": {
			"r": _screen_ref(field_ctx, rf),
			"g": _screen_ref(field_ctx, gf),
			"b": _screen_ref(field_ctx, bf),
		},
	}


## The editable KIND selector (CONTEXT §Variant): a `choice` editor that flips the screen
## tween between its two variants. Present in BOTH sections so the author can switch in place;
## flipping reshapes the fields (Blend ↔ Gradient). Choices are INDEX-ALIGNED with
## ScreenData.ScreenMode (0=Gradient, 1=Blend), seeded to the tween's current mode; the
## selected index IS the ScreenMode the encoder writes (ctrl bit-7 + derived mode).
static func _kind_edit(kf, field_ctx: Dictionary) -> Dictionary:
	return {
		"name": "Kind",
		"shape": "edit",
		"editor": "choice",
		"value": int(kf.mode),
		"choices": ["Gradient", "Blend"],
		"field_ref": _screen_ref(field_ctx, "kind"),
	}


## One component's write-side field_ref for the choke point (EffectEditSession.apply_edit):
## channel + on-disk field name, addressed to the span's screen context + keyframe index.
static func _screen_ref(field_ctx: Dictionary, field: String) -> Dictionary:
	return {
		"channel": "screen",
		"context": field_ctx.get("context", ""),
		"event_index": int(field_ctx.get("event_index", -1)),
		"field": field,
	}
