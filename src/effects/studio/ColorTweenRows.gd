extends RefCounted
## The SHARED colour-row builder (ADR-0087 dec. 14) — the one place the harmonized
## inspector rows for the two colour lanes (the three palette channels + screen) are
## assembled: Enabled · Tint · Tint Δ · Blend mode · Duration. The projectors stay thin
## adapters — variant dispatch plus a per-lane descriptor of facts only the lane knows
## (write-side field_refs / address shape, the engine's ×2 doubling, the derived enabled
## state, the tint seed) — while every row NAME, EDITOR, choice list, and honest-tell label
## lives here exactly once, so the lanes cannot drift to different words for the same op
## (the arrangement §6 kills: parallel projectors sharing only vocabulary). Apply paths stay
## per-channel (bit RMW vs byte-swap + stash genuinely differ — the encoders own that).
## No class_name (ADR-0004).

const _Labels = preload("res://src/effects/studio/ColorModeLabels.gd")


## The harmonized Enabled toggle: one Disabled/Enabled choice row. `enabled` is the lane's
## DERIVED state (palette: ctrl bit-7; screen: not-identity-no-op and no stash) — the caller
## derives, this row just presents. `field_ref` addresses the lane's `enabled` pseudo-field.
static func enabled_row(enabled: bool, field_ref: Dictionary) -> Dictionary:
	return {
		"name": "Enabled",
		"shape": "edit",
		"editor": "choice",
		"value": 1 if enabled else 0,
		"choices": ["Disabled", "Enabled"],
		"field_ref": field_ref,
	}


## The WYSIWYG result-picker tint row (`target_color`). The lane names it ("Tint" /
## "Color") and supplies its byte field_refs; a lane that can compute its own seed (palette:
## the forward fold over the fixed mid-grey reference) passes it, a lane whose seed is
## runtime-injected (screen: the live folded top colour, added by the page) omits it.
static func tint_row(name: String, field_refs: Dictionary, seed = null) -> Dictionary:
	var row := {
		"name": name,
		"shape": "edit",
		"editor": "target_color",
		"field_refs": field_refs,
	}
	if seed != null:
		row["seed"] = seed
	return row


## The precise signed-Δ row (`signed_rgb`) + its "No tint" reset (the inspector renders the
## reset with the editor). Shows the raw STORED byte in signed form; `applied_x2` is the
## lane's engine-doubling fact (screen's `double_param` << 1) told honestly in the label.
static func delta_row(seed: Vector3i, field_refs: Dictionary, applied_x2: bool) -> Dictionary:
	return {
		"name": "Tint Δ (applied ×2)" if applied_x2 else "Tint Δ",
		"shape": "edit",
		"editor": "signed_rgb",
		"seed": seed,
		"field_refs": field_refs,
	}


## The Blend-mode selector: a value-carrying enum over the 11 codes, labels from the ONE
## shared ColorModeLabels map — the row both lanes read so the same op never gets two names.
static func blend_mode_row(mode: int, field_ref: Dictionary) -> Dictionary:
	return {
		"name": "Blend mode",
		"shape": "edit",
		"editor": "enum",
		"value": mode,
		"choices": _Labels.choices(),
		"field_ref": field_ref,
	}


## The editable Duration row (amendment §1): an int cell whose typed value IS the boundary
## edit — the `duration` pseudo-field the channel routes to the sum-preserving trade (tail =
## extend; ripple = shift). The channel snaps to the 8-grid and returns `relayout`, so the
## re-rendered cell shows the SNAPPED number (the honest tell). Min 1: never a zero-width span.
static func duration_row(dur: int, field_ref: Dictionary) -> Dictionary:
	return {
		"name": "Duration",
		"shape": "edit",
		"editor": "int",
		"type": "u16",
		"min": 1,
		"value": dur,
		"field_ref": field_ref,
	}
