extends RefCounted
## Two-axis emitter parameter groups (ADR-0089) — the shared row builder behind
## `EffectScoreModel.emitter_view`, so the span inspector and the bare emitter
## browser project the SAME editable presentation (edit-at-the-reference).
##
## Each parameter is one labeled group: **At start / At end** rows × min/max cells
## (X/Y/Z cells for a vec3; a single cell where the parameter has no randomness
## axis), never collapsed when min == max — collapsing would hide the randomness
## axis. Display names come from the ADR-0089 vocabulary table (renames go through
## the ADR, not here); every cell's tooltip keeps the raw RE name + byte offset so
## cross-referencing survives the rename. Each group closes with its **Curve**
## assignment row — a thumbnail picker over the effect's DISTINCT SHAPE SET, whose verb
## is copy, not reference (ADR-0089 curve-ownership amendment): the group owns its curve
## privately, so a pick writes a shape into it and the painter reshapes the one it has.
## Values author in human units only where proven (ParticleUnits), else raw.
##
## Pure projection: cells seed `EmitterChannel.read_raw` and address the channel's
## field names, so read and write sides share the one field→storage map.

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


const EmitterChannel = preload("res://src/effects/studio/EmitterChannel.gd")
const ParticleUnits = preload("res://src/effects/studio/ParticleUnits.gd")
const CurveShapeSet = preload("res://src/effects/studio/CurveShapeSet.gd")

# The ADR-0089 vocabulary table, joined with each parameter's storage shape:
# kind — "vec3" (evolution only), "range" (randomness × evolution scalars),
# "vec3_range" (both axes, per component), "pair" (evolution-only scalar);
# base — the record byte offset of the first stored value (master_parser layout);
# unit — the proven human-unit descriptor ("" = honest raw int); type — cell range;
# bits — the ROM's curve-assignment field width (nibble, or 2 for the homing pair). Kept
# as documentation of what the deferred compiler has to pack into; authoring no longer
# caps on it, because a private curve index routinely exceeds any of these widths.
const _PARAMS := {
	"position": {"label": "Position", "kind": "vec3", "base": 0x14,
		"unit": "pos", "type": "s16", "curve": "position", "bits": 4},
	"spread": {"label": "Spawn scatter", "kind": "vec3", "base": 0x20,
		"unit": "pos", "type": "s16", "curve": "spread", "bits": 4},
	"velocity_base_angle": {"label": "Launch direction", "kind": "vec3", "base": 0x2C,
		"unit": "angle", "type": "s16", "curve": "velocity_base_angle", "bits": 4},
	"velocity_direction_spread": {"label": "Direction scatter", "kind": "vec3", "base": 0x38,
		"unit": "angle", "type": "s16", "curve": "velocity_dir_spread", "bits": 4},
	"inertia": {"label": "Inertia", "kind": "range", "base": 0x44,
		"unit": "inertia", "type": "s16", "curve": "inertia", "bits": 4},
	"weight": {"label": "Gravity scale", "kind": "range", "base": 0x54,
		"unit": "", "type": "s16", "curve": "weight", "bits": 4},
	"radial_velocity": {"label": "Outward speed", "kind": "range", "base": 0x5C,
		"unit": "", "type": "s16", "curve": "radial_velocity", "bits": 4},
	"acceleration": {"label": "Acceleration", "kind": "vec3_range", "base": 0x64,
		"unit": "", "type": "s16", "curve": "acceleration", "bits": 4},
	"drag": {"label": "Drag", "kind": "vec3_range", "base": 0x7C,
		"unit": "", "type": "s16", "curve": "drag", "bits": 4},
	"lifetime": {"label": "Lifetime", "kind": "range", "base": 0x94,
		"unit": "", "type": "s16", "curve": "lifetime", "bits": 4},
	"target_offset": {"label": "Target offset", "kind": "vec3", "base": 0x9C,
		"unit": "pos", "type": "s16", "curve": "target_offset", "bits": 4},
	"particle_count": {"label": "Particles per burst", "kind": "pair", "base": 0xB0,
		"unit": "", "type": "u16", "curve": "particle_count", "bits": 4},
	"spawn_interval": {"label": "Spawn every N frames", "kind": "pair", "base": 0xB4,
		"unit": "", "type": "u16", "curve": "spawn_interval", "bits": 4},
	"homing_strength": {"label": "Homing strength", "kind": "range", "base": 0xB8,
		"unit": "", "type": "s16", "curve": "homing_strength", "bits": 2},
}

# Directional placement families (ADR-0089 amendment "directional Y authors
# game-up"): the vec3 parameters whose Y sign is VISIBLE on screen — position and
# target-offset (start & end), acceleration, drag. Spread is deliberately absent:
# it is a symmetric EXTENT (`_apply_spread` samples `randf(-s, s)`), so its Y sign
# is inert and flipping it would mislead. Field names reaching `_cells_row` begin
# with one of these tokens (e.g. "acceleration_min_start", "position_end").
const _DIRECTIONAL_Y_FAMILIES := ["position_", "target_offset_", "acceleration_", "drag_"]

# The one group tooltip explaining the two axes (shown on every row of a group).
const _AXES_TIP := "Randomness: each particle rolls a value between min and max when it spawns. " \
	+ "Evolution: the min–max range slides from its At-start to its At-end value over the " \
	+ "emitter's active window, shaped by the group's Curve."


## Author-side chirality predicate (ADR-0089 amendment): true iff `field`'s
## component `comp` is a DIRECTIONAL placement Y — the Y axis (comp 1) of a
## position / target-offset / acceleration / drag field, whose sign is visible on
## screen, so the cell authors game-up (shows the value the sim caches, commits the
## opposite raw). Deliberately EXCLUDES spread (a symmetric extent, Y sign inert)
## and every X/Z. Kept separate from EmitterChannel._convert's sim-cache flip so
## the smallest authoring change can never disturb the test-locked runtime
## negation; EmitterProjectorTest asserts the two agree on all directional fields
## and differ only on spread.
static func is_directional_y(field: String, comp: int) -> bool:
	if comp != 1:
		return false
	for fam in _DIRECTIONAL_Y_FAMILIES:
		if field.begins_with(fam):
			return true
	return false


## The full labeled group for parameter `key`: axis edit rows + the Curve row.
## `used_n`/`window_note` describe the group's used curve window (ADR-0089
## decision 5 — evolution params sample by emitter-elapsed frame, so the caller
## supplies the firing duration; -1 = unknown → fully bright).
static func group(em, emitter_index: int, key: String, shapes: Array,
		used_n: int = -1, window_note: String = "") -> Array:
	var spec: Dictionary = _PARAMS[key]
	var rows: Array = []
	match spec["kind"]:
		"vec3":
			rows.append(_cells_row(em, emitter_index, spec, "at start", "_start",
				[["X", "x", 0], ["Y", "y", 2], ["Z", "z", 4]], key, 0))
			rows.append(_cells_row(em, emitter_index, spec, "at end", "_end",
				[["X", "x", 0], ["Y", "y", 2], ["Z", "z", 4]], key, 6))
		"range":
			rows.append(_cells_row(em, emitter_index, spec, "at start", "",
				[["min", "_min_start", 0], ["max", "_max_start", 2]], key, 0))
			rows.append(_cells_row(em, emitter_index, spec, "at end", "",
				[["min", "_min_end", 4], ["max", "_max_end", 6]], key, 0))
		"pair":
			rows.append(_cells_row(em, emitter_index, spec, "at start", "",
				[["", "_start", 0]], key, 0))
			rows.append(_cells_row(em, emitter_index, spec, "at end", "",
				[["", "_end", 2]], key, 0))
		"vec3_range":
			rows.append(_cells_row(em, emitter_index, spec, "at start (min)", "_min_start",
				[["X", "x", 0], ["Y", "y", 4], ["Z", "z", 8]], key, 0))
			rows.append(_cells_row(em, emitter_index, spec, "at start (max)", "_max_start",
				[["X", "x", 2], ["Y", "y", 6], ["Z", "z", 10]], key, 0))
			rows.append(_cells_row(em, emitter_index, spec, "at end (min)", "_min_end",
				[["X", "x", 0xC], ["Y", "y", 0x10], ["Z", "z", 0x14]], key, 0))
			rows.append(_cells_row(em, emitter_index, spec, "at end (max)", "_max_end",
				[["X", "x", 0xE], ["Y", "y", 0x12], ["Z", "z", 0x16]], key, 0))
	rows.append(curve_row(em, emitter_index, "%s · curve" % spec["label"],
		"curve_" + str(spec["curve"]), shapes, used_n, window_note))
	# Explicit group identity (ADR-0089 inspector presentation): every row of the
	# group — axis rows AND its Curve row — shares one stamp, the fold boundary
	# both surfaces hang on. Replaces the "<Label> · …" name-prefix convention.
	# The stamp also carries the collapsed-header summary (start → end in the
	# cells' units; min == max MAY collapse here — the law binds editing cells),
	# the full uncollapsed values for its tooltip, the inert flag the view dims,
	# and the assigned curve + used window for the header's mini sparkline.
	var stamp := {"id": key, "label": str(spec["label"]), "emitter_index": emitter_index,
		"curve_index": int(em.curves.get(str(spec["curve"]), -1)),
		"used_n": used_n}
	stamp.merge(_summary(em, key, spec))
	for r in rows:
		r["group"] = stamp
	return rows


## The decision-3 summary block for one parameter group: `summary` (collapsed
## form), `summary_tooltip` (full both ends), `inert` (every value zero AND no
## curve assigned — nothing this group does), and `traj` (the [start, end]
## magnitude pair the header glyph slopes between).
##
## HONESTY (field-relevance amendment): with **no curve** the sim pins the value
## to its START and the END is inert (`interpolate_* returns start`). So a
## curve-less group summarises as a **constant** (start value only) and its header
## glyph is **flat**, not a start→end slope — showing a glide that never happens
## was the #291 defect. A curve-assigned group still reads `start → end`.
static func _summary(em, key: String, spec: Dictionary) -> Dictionary:
	var unit := _unit(str(spec["unit"]))
	var has_curve := EmitterChannel.read_raw(em, "curve_" + str(spec["curve"])) != 0
	var start_text := ""
	var end_text := ""
	var start_mag := 0.0
	var end_mag := 0.0
	var full := ""
	var values: Array = []  # every raw value, for the inert test
	match spec["kind"]:
		"vec3":
			var s := _read_vec3(em, key + "_start")
			var e := _read_vec3(em, key + "_end")
			values = s + e
			start_text = _fmt_vec3(s, unit); end_text = _fmt_vec3(e, unit)
			start_mag = _mag(s); end_mag = _mag(e)
			full = "%s → %s" % [start_text, end_text]
		"range":
			var vals := _read_quad(em, key)
			values = vals
			start_text = _fmt_side(vals[0], vals[1], unit); end_text = _fmt_side(vals[2], vals[3], unit)
			start_mag = _mag([vals[0], vals[1]]); end_mag = _mag([vals[2], vals[3]])
			full = "%s–%s → %s–%s" % [_fmt_raw(vals[0], unit), _fmt_raw(vals[1], unit),
				_fmt_raw(vals[2], unit), _fmt_raw(vals[3], unit)]
		"pair":
			var s2 := EmitterChannel.read_raw(em, key + "_start")
			var e2 := EmitterChannel.read_raw(em, key + "_end")
			values = [s2, e2]
			start_text = _fmt_raw(s2, unit); end_text = _fmt_raw(e2, unit)
			start_mag = absf(float(s2)); end_mag = absf(float(e2))
			full = "%s → %s" % [start_text, end_text]
		"vec3_range":
			var mins := _read_vec3(em, key + "_min_start")
			var maxs := _read_vec3(em, key + "_max_start")
			var mine := _read_vec3(em, key + "_min_end")
			var maxe := _read_vec3(em, key + "_max_end")
			values = mins + maxs + mine + maxe
			start_text = _fmt_vec3_side(mins, maxs, unit); end_text = _fmt_vec3_side(mine, maxe, unit)
			start_mag = _mag(mins) + _mag(maxs); end_mag = _mag(mine) + _mag(maxe)
			full = "%s–%s → %s–%s" % [_fmt_vec3(mins, unit), _fmt_vec3(maxs, unit),
				_fmt_vec3(mine, unit), _fmt_vec3(maxe, unit)]
	var inert := not has_curve
	for v in values:
		if int(v) != 0:
			inert = false
			break
	# Curve assigned ⇒ the value glides start→end (show the range + a sloped glyph).
	# No curve ⇒ constant at start (the end is inert) — start only + a flat glyph.
	var text := "%s → %s" % [start_text, end_text] if has_curve else start_text
	var traj := [start_mag, end_mag] if has_curve else [start_mag, start_mag]
	if not has_curve:
		full += "  (end inert — no curve)"
	return {"summary": text, "summary_tooltip": full, "inert": inert, "traj": traj}


## Sum of absolute values — a scalar "how much" magnitude for the linear glyph's
## endpoints (direction between start and end is what the slope shows).
static func _mag(arr: Array) -> float:
	var m := 0.0
	for v in arr:
		m += absf(float(v))
	return m


## The raw min/max × start/end quad of a "range" parameter, channel-read.
static func _read_quad(em, key: String) -> Array:
	return [EmitterChannel.read_raw(em, key + "_min_start"),
		EmitterChannel.read_raw(em, key + "_max_start"),
		EmitterChannel.read_raw(em, key + "_min_end"),
		EmitterChannel.read_raw(em, key + "_max_end")]


static func _read_vec3(em, prefix: String) -> Array:
	return [EmitterChannel.read_raw(em, prefix + "_x"),
		EmitterChannel.read_raw(em, prefix + "_y"),
		EmitterChannel.read_raw(em, prefix + "_z")]


## One raw value in the group's display units, whole numbers shown bare
## (String.num trims trailing zeros but keeps a ".0" — strip that too).
static func _fmt_raw(raw: int, unit: Dictionary) -> String:
	if unit.is_empty():
		return str(raw)
	var s := String.num(ParticleUnits.to_display(raw, unit), int(unit.get("decimals", 1)))
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s


## One min–max side of a range summary — collapsed to a single value when the
## side has no spread (read-only; expanding always reveals both axes).
static func _fmt_side(lo: int, hi: int, unit: Dictionary) -> String:
	if lo == hi:
		return _fmt_raw(lo, unit)
	return "%s–%s" % [_fmt_raw(lo, unit), _fmt_raw(hi, unit)]


static func _fmt_vec3(v: Array, unit: Dictionary) -> String:
	return "(%s, %s, %s)" % [_fmt_raw(v[0], unit), _fmt_raw(v[1], unit), _fmt_raw(v[2], unit)]


static func _fmt_vec3_side(lo: Array, hi: Array, unit: Dictionary) -> String:
	if lo == hi:
		return _fmt_vec3(lo, unit)
	return "%s–%s" % [_fmt_vec3(lo, unit), _fmt_vec3(hi, unit)]


## One axis row: "<Label> · <axis>" + an edit-cell strip. `parts` lists
## [cell label, field suffix piece, byte offset from the group base]; for vec3
## kinds the suffix piece is the component letter appended to `axis_suffix`.
static func _cells_row(em, emitter_index: int, spec: Dictionary, axis: String,
		axis_suffix: String, parts: Array, key: String, end_bias: int) -> Dictionary:
	var cells: Array = []
	for part in parts:
		var field: String
		if axis_suffix == "":
			field = key + str(part[1])          # scalar kinds carry the full suffix
		else:
			field = key + axis_suffix + "_" + str(part[1])  # vec3 kinds append the component
		var offset: int = int(spec["base"]) + end_bias + int(part[2])
		var raw: int = EmitterChannel.read_raw(em, field)
		var cell := {
			"editor": "int", "label": str(part[0]),
			"value": raw,
			"field_ref": {"channel": "emitter", "emitter_index": emitter_index, "field": field},
			"type": str(spec["type"]),
			"tooltip": "raw: %s @0x%02X" % [field, offset],
		}
		var unit := _unit(str(spec["unit"]))
		if not unit.is_empty():
			cell["unit"] = unit
		# Directional Y cells author game-up: mark the cell so the inspector negates
		# raw↔display around it, and surface the signed raw + note so cross-referencing
		# a game-up +1 against a negative byte in a RAM dump still reconciles.
		var comp: int = {"x": 0, "y": 1, "z": 2}.get(str(part[1]), -1)
		if is_directional_y(field, comp):
			cell["flip_sign"] = true
			cell["tooltip"] = "%s = %d (Y shown game-up)" % [cell["tooltip"], raw]
		cells.append(cell)
	return {"name": "%s · %s" % [spec["label"], axis], "shape": "edit", "editor": "cells",
		"cells": cells, "tooltip": _AXES_TIP}


## A Curve assignment row — a `[curve_pick, sparkline]` cells strip.
##
## The ASSIGNMENT cell is a thumbnail picker over the effect's DISTINCT SHAPE SET, and its
## verb is COPY (ADR-0089 curve-ownership amendment, decision 3): there is no shared slot to
## point at, so a pick writes those samples into this use site's own curve. Choices
## therefore carry SAMPLES, not indices, and the field_ref addresses the USE SITE —
## `(emitter, slot)` — on the `curve_assign` channel rather than an emitter nibble.
##
## It is fed shapes, never the post-explode array: median 8 tiles instead of median 22
## showing those same 8 pictures. That also makes the tile count the live PSX budget.
##
## No offer cap. The old row capped the list at the `bits`-wide nibble's reach, which was a
## PSX packing rule in the authoring layer; the count that matters now is distinct shapes
## against 15, and the compiler is what refuses. (The 2-bit homing pair is the tightest
## packing constraint in the ROM and remains a real EXPORT problem — it just is not this
## widget's to enforce.)
##
## The right cell is the curve sparkline (trimmed to the used window `used_n`; -1 =
## whole/bright), and clicking IT opens the painter (a distinct affordance).
static func curve_row(em, emitter_index: int, name: String, field: String,
		shapes: Array, used_n: int = -1, window_note: String = "") -> Dictionary:
	var kind := "colour" if field.begins_with("color_curve_") else "param"
	var slot := field.trim_prefix("color_curve_") if kind == "colour" else field.trim_prefix("curve_")
	var idx: int = int((em.color_curves if kind == "colour" else em.curves).get(slot, -1))
	var ordinal: int = CurveShapeSet.ordinal_for(shapes, emitter_index, slot, kind)
	var choices: Array = [{"value": 0, "label": "none", "samples": []}]
	for i in range(shapes.size()):
		choices.append({"value": i + 1, "label": "Shape %d" % (i + 1),
			"samples": shapes[i]["grid"]})
	return {"name": name, "shape": "edit", "editor": "cells",
		# The row addresses a USE SITE, not an emitter field, so the relevance oracle cannot
		# find its verdict through the field_ref any more — name the key explicitly (the
		# same escape hatch the child-navigation link rows use).
		"relevance_key": field, "cells": [
		{"editor": "curve_pick", "value": ordinal + 1,
			"field_ref": {"channel": "curve_assign", "emitter_index": emitter_index,
				"slot": slot, "kind": kind},
			"choices": choices},
		# The sparkline cell OPENS THE PAINTER, which writes this use site's curve contents
		# through the `curve` channel — so it names that channel and index. It fans no edit
		# itself; the ref is the reach (the editability manifest's "every editable channel is
		# reachable from some projector" invariant), and the painter's commit is the write.
		{"editor": "curve", "name": name, "curve_index": idx, "used_n": used_n,
			"field_ref": {"channel": "curve", "curve_index": idx},
			"tooltip": _window_tip(used_n, window_note)},
	], "tooltip": "Which shape drives this parameter's start→end slide. Picking one COPIES " +
		"it here — this parameter owns its curve, so reshaping it moves nothing else. " +
		"`none` holds the start value (the end is inert)."}


## The honest used-window tooltip (decision 5): states the window in frames and
## whose clock/firing it is; a wrapping (≥160) or unknown window explains itself.
static func _window_tip(used_n: int, note: String) -> String:
	if used_n < 0:
		return note
	if used_n >= 160:
		var wrap := "Window %d frames ≥ 160 samples — the curve wraps; all samples play." % used_n
		return wrap if note == "" else "%s (%s)" % [wrap, note]
	if note == "":
		return "Used window: 0–%d of 160 frames." % used_n
	return "Used window: 0–%d of 160 frames (%s)." % [used_n, note]


## An over-life colour-curve row ("Color (R) · curve" → color_curve_r) — the
## particle-age clock, so `used_n` is the max authored lifetime. The row + its two cells
## carry a `colour_channel` tag so the inspector records the sparkline + curve_pick by channel
## and a recolour can re-feed them in place (ADR-0089 editing-UX amendment, the stale-sparkline
## bug) — a recolour rewrites the channel's samples, so a snapshot goes stale.
static func color_curve_row(em, emitter_index: int, chan: String, shapes: Array,
		used_n: int = -1, window_note: String = "") -> Dictionary:
	var row := curve_row(em, emitter_index, "Color (%s) · curve" % chan.to_upper(),
		"color_curve_" + chan, shapes, used_n, window_note)
	row["colour_channel"] = chan
	for cell in row.get("cells", []):
		cell["colour_channel"] = chan
	return row


## A plain editable int config row (Animation set / Frameset group).
static func int_row(em, emitter_index: int, name: String, field: String, type: String) -> Dictionary:
	return {"name": name, "shape": "edit", "editor": "int", "type": type,
		"value": EmitterChannel.read_raw(em, field),
		"field_ref": {"channel": "emitter", "emitter_index": emitter_index, "field": field},
		"tooltip": "raw: %s" % field}


# Decoded labels for the packed Config enums (master_parser decode; the flags
# recompute in EmitterChannel mirrors the same maps).
const _ON_OFF := [{"value": 0, "label": "off"}, {"value": 1, "label": "on"}]
const _TARGET_ANCHOR_CHOICES := [
	{"value": 0, "label": "WORLD"}, {"value": 1, "label": "WORLD (alt)"},
	{"value": 2, "label": "CAMERA"}, {"value": 3, "label": "ORIGIN"},
	{"value": 4, "label": "TARGET"}, {"value": 5, "label": "PARENT"},
	{"value": 6, "label": "UNKNOWN_C0"}, {"value": 7, "label": "UNKNOWN_E0"}]
const _EMITTER_ANCHOR_CHOICES := [
	{"value": 0, "label": "WORLD"}, {"value": 1, "label": "CURSOR"},
	{"value": 2, "label": "ORIGIN"}, {"value": 3, "label": "TARGET"},
	{"value": 4, "label": "PARENT"}, {"value": 5, "label": "CAMERA"},
	{"value": 6, "label": "TRACKED"}, {"value": 7, "label": "UNKNOWN"}]
const _SPREAD_CHOICES := [{"value": 0, "label": "SPHERICAL"}, {"value": 1, "label": "BOX"}]
const _CHILD_DEATH_CHOICES := [
	{"value": 0, "label": "disabled"}, {"value": 1, "label": "spawn on death"},
	{"value": 2, "label": "spawn on death (alt)"}, {"value": 3, "label": "disabled (3)"}]
const _CHILD_MIDLIFE_CHOICES := [
	{"value": 0, "label": "disabled"}, {"value": 1, "label": "spawn continuous"},
	{"value": 2, "label": "spawn continuous (alt)"}, {"value": 3, "label": "disabled (3)"}]
# Homing "arrival" distance: raw 0-3 → 0/16/32/48 PSX world units (`raw*16`, the
# runtime's ActiveEmitter/ParticleSubsystem conversion). "world units" alone read as
# ambiguous — it is PSX/FFT units (28 = one tile), NOT Godot units — so the label
# leads with the GAME unit (tiles, via the PsxMagnitude seam) and names PSX for provenance.
static func _homing_threshold_choices() -> Array:
	var choices := [{"value": 0, "label": "disabled"}]
	for raw in [1, 2, 3]:
		var psx: int = raw * 16
		choices.append({"value": raw,
			"label": "≈%.1f tiles (%d PSX units)" % [PsxMagnitude.tile_to_game(psx), psx]})
	return choices

# Callback params in record order: [field, display offset, type]. Projected only
# where the parser surfaced the key (an absent key's bytes are writer-preserved).
const _CALLBACK_ROWS := [
	["callback_param_4C", 0x4C, "u8"], ["callback_param_4E", 0x4E, "u8"],
	["callback_param_A8", 0xA8, "s16"], ["callback_param_AA", 0xAA, "s16"],
	["callback_param_AC", 0xAC, "s16"], ["callback_param_AE", 0xAE, "s16"]]

const _CALLBACK_TIP := "Passed to this effect's native callback routine; meaning varies per effect."


## An editable enum row over an emitter channel field.
static func enum_row(em, emitter_index: int, name: String, field: String,
		choices: Array, tooltip: String = "") -> Dictionary:
	return {"name": name, "shape": "edit", "editor": "enum",
		"value": EmitterChannel.read_raw(em, field),
		"field_ref": {"channel": "emitter", "emitter_index": emitter_index, "field": field},
		"choices": choices, "tooltip": tooltip}


## The editable Config decomposition of the packed control bytes (master_parser
## decode; engine-unread bits are never exposed — byte-preserved by the writer).
static func packed_config_rows(em, emitter_index: int) -> Array:
	return [
		enum_row(em, emitter_index, "Target anchor", "target_anchor_mode",
			_TARGET_ANCHOR_CHOICES, "raw: motion_type_flag bits 5-7 @0x02"),
		enum_row(em, emitter_index, "Emitter anchor", "emitter_anchor_mode",
			_EMITTER_ANCHOR_CHOICES, "raw: animation_target_flag bits 1-3 @0x03"),
		enum_row(em, emitter_index, "Spread mode", "spread_mode",
			_SPREAD_CHOICES, "raw: animation_target_flag bit 0 @0x03"),
		enum_row(em, emitter_index, "Sprite faces its velocity", "align_to_velocity",
			_ON_OFF, "raw: motion_type_flag bit 1 @0x02"),
		enum_row(em, emitter_index, "Pull velocity inward", "velocity_inward",
			_ON_OFF, "raw: emitter_flags_lo bit 4 @0x06"),
		enum_row(em, emitter_index, "Align to unit facing", "align_to_facing",
			_ON_OFF, "raw: emitter_flags_hi bit 2 @0x07"),
		enum_row(em, emitter_index, "Colour curves", "color_curve_enable",
			_ON_OFF, "raw: emitter_flags_lo bit 6 @0x06"),
		enum_row(em, emitter_index, "Child death mode", "child_death_mode",
			_CHILD_DEATH_CHOICES, "raw: emitter_flags_lo bits 0-1 @0x06"),
		enum_row(em, emitter_index, "Child mid-life mode", "child_midlife_mode",
			_CHILD_MIDLIFE_CHOICES, "raw: emitter_flags_lo bits 2-3 @0x06"),
		enum_row(em, emitter_index, "Homing arrival", "homing_arrival_threshold",
			_homing_threshold_choices(), "raw: emitter_flags_hi bits 0-1 @0x07"),
	]


## Child-emitter wiring pickers ("Spawn on death: none / emitter N") — rewiring the
## child graph is a headline capability; the score re-projects on edit (relayout).
static func child_picker_rows(em, emitter_index: int, emitter_count: int) -> Array:
	var choices: Array = [{"value": 255, "label": "none"}]
	for i in range(emitter_count):
		choices.append({"value": i, "label": "emitter %d" % i})
	return [
		enum_row(em, emitter_index, "Spawn on death", "child_emitter_on_death",
			choices, "raw: child_emitter_on_death @0xC0 (255 = none). " +
			"Editing rewires the shared child graph."),
		enum_row(em, emitter_index, "Spawn mid-life", "child_emitter_mid_life",
			choices, "raw: child_emitter_mid_life @0xC1 (255 = none). " +
			"Editing rewires the shared child graph."),
	]


## The Advanced (raw) section: real-but-opaque callback params (editable raw ints,
## honest tooltip) + reserved always-zero bytes as const rows. Only keys the parser
## surfaced project a row — absent bytes are preserved untouched by the writer.
static func advanced_rows(em, emitter_index: int) -> Array:
	var rows: Array = []
	for spec in _CALLBACK_ROWS:
		var key: String = str(spec[0]).trim_prefix("callback_param_").to_lower()
		if not em.callback_params.has("param_" + key.to_upper()):
			continue
		var row := int_row(em, emitter_index, "Callback param @0x%02X" % int(spec[1]),
			str(spec[0]), str(spec[2]))
		row["tooltip"] = "%s raw: param_%s @0x%02X" % [_CALLBACK_TIP, key.to_upper(), int(spec[1])]
		rows.append(row)
	for reserved in [["byte_00", 0x00], ["byte_05", 0x05]]:
		if em.raw_data.has(reserved[0]):
			rows.append({"name": str(reserved[0]), "shape": "const",
				"value": "0x%02X" % int(em.raw_data[reserved[0]]),
				"tooltip": "Reserved/always-zero @0x%02X — byte-preserved by the writer." % int(reserved[1])})
	return rows


static func _unit(kind: String) -> Dictionary:
	match kind:
		"pos": return ParticleUnits.POS_TILES
		"angle": return ParticleUnits.ANGLE_DEG
		"inertia": return ParticleUnits.INERTIA_X
	return {}
