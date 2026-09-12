class_name EmitterChannel
extends RefCounted
## Write-side channel encoder for SHARED emitter parameters (ADR-0089). An emitter
## field's raw PSX integer is authoritative: `apply_raw` writes it into the live
## `EffectEmitter` storage (the `raw_data` slot for converted fields, the field
## itself where the runtime consumes raw), re-derives the converted Godot-unit
## cache through the single PsxMagnitude magnitude seam (ADR-0091: tiles + Y-flip,
## angles, radial, accel — the proven parse_effect.py numbers), and reports the
## undo snapshot.
##
## Particles are born from emitter params at spawn — read-live is impossible — so
## EVERY edit is `invalidates_sim = true` (ADR-0089). Out-of-range raw is a
## REFUSAL (`no_edit`, nothing recorded), never a clamp: a clamp would silently
## diverge from what the author typed. The name "particle" stays reserved for the
## timeline follow-on; this channel edits the shared emitter objects only.
##
## Channels supply encoders, not mutation logic; the single choke point is
## `EffectEditSession.apply_edit` (#255). Mirrors `CameraChannel` / `SoundChannel`.

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


# Vec3 fields ("<prefix>_x|_y|_z"): prefix → [raw_data key, cache attr, conversion kind].
# All are s16 triplets; "pos" and "accel" kinds Y-flip the cache (FFT -Y is up).
const _VEC3 := {
	"position_start": ["position_start", "position_start", "pos"],
	"position_end": ["position_end", "position_end", "pos"],
	"spread_start": ["spread_start", "spread_start", "pos"],
	"spread_end": ["spread_end", "spread_end", "pos"],
	"velocity_base_angle_start": ["angle_start", "velocity_base_angle_start", "angle"],
	"velocity_base_angle_end": ["angle_end", "velocity_base_angle_end", "angle"],
	"velocity_direction_spread_start": ["vel_spread_start", "velocity_direction_spread_start", "angle"],
	"velocity_direction_spread_end": ["vel_spread_end", "velocity_direction_spread_end", "angle"],
	"acceleration_min_start": ["accel_min_start", "acceleration_min_start", "accel"],
	"acceleration_max_start": ["accel_max_start", "acceleration_max_start", "accel"],
	"acceleration_min_end": ["accel_min_end", "acceleration_min_end", "accel"],
	"acceleration_max_end": ["accel_max_end", "acceleration_max_end", "accel"],
	"drag_min_start": ["drag_min_start", "drag_min_start", "accel"],
	"drag_max_start": ["drag_max_start", "drag_max_start", "accel"],
	"drag_min_end": ["drag_min_end", "drag_min_end", "accel"],
	"drag_max_end": ["drag_max_end", "drag_max_end", "accel"],
	"target_offset_start": ["target_start", "target_offset_start", "pos"],
	"target_offset_end": ["target_end", "target_offset_end", "pos"],
}
const _COMPONENT := {"x": 0, "y": 1, "z": 2}

# Converted scalar fields: field → [raw_data key, cache attr, conversion kind]. s16.
const _SCALAR := {
	"radial_velocity_min_start": ["radial_min_start", "radial_velocity_min_start", "vel"],
	"radial_velocity_max_start": ["radial_max_start", "radial_velocity_max_start", "vel"],
	"radial_velocity_min_end": ["radial_min_end", "radial_velocity_min_end", "vel"],
	"radial_velocity_max_end": ["radial_max_end", "radial_velocity_max_end", "vel"],
	"homing_strength_min_start": ["homing_min_start", "homing_strength_min_start", "homing"],
	"homing_strength_max_start": ["homing_max_start", "homing_strength_max_start", "homing"],
	"homing_strength_min_end": ["homing_min_end", "homing_strength_min_end", "homing"],
	"homing_strength_max_end": ["homing_max_end", "homing_strength_max_end", "homing"],
}

# Raw-direct fields (the runtime consumes the raw number; the field IS the storage):
# field/attr name → encoding range. inertia/weight live in the physics formula raw
# (floats on the emitter); lifetime/spawn are u16 frame counts; anim ids are u8.
const _DIRECT := {
	"inertia_min_start": "s16", "inertia_max_start": "s16",
	"inertia_min_end": "s16", "inertia_max_end": "s16",
	"weight_min_start": "s16", "weight_max_start": "s16",
	"weight_min_end": "s16", "weight_max_end": "s16",
	# Lifetime authors SIGNED so the -1 "dies with its animation" sentinel (0xFFFF
	# on disk, how emitters.json parses it) is typeable; the writer masks to bytes.
	"lifetime_min_start": "s16", "lifetime_max_start": "s16",
	"lifetime_min_end": "s16", "lifetime_max_end": "s16",
	"particle_count_start": "u16", "particle_count_end": "u16",
	"spawn_interval_start": "u16", "spawn_interval_end": "u16",
	"anim_index": "u8", "anim_param": "u8",
}

# Curve ASSIGNMENT fields ("curve_<param>"): curves dict key → [byte index in
# curve_indices_raw, bit shift, bit width] — the ROM's nibble packing (parse_effect.py),
# homing strength/blend being 2-bit fields sharing byte 7's high nibble.
#
# Since ADR-0089's curve-ownership amendment this table is READ-ONLY PROVENANCE: authoring
# writes the decoded `em.curves` index (unbounded — every use site owns a private curve),
# and re-packing these nibbles is the deferred compiler's job. The convention on the
# authoring side is unchanged: raw 0 = none, N > 0 = curve N−1.
const _CURVE := {
	"position": [0, 0, 4], "spread": [0, 4, 4],
	"velocity_base_angle": [1, 0, 4], "velocity_dir_spread": [1, 4, 4],
	"inertia": [2, 0, 4],
	"weight": [3, 0, 4], "radial_velocity": [3, 4, 4],
	"acceleration": [4, 0, 4], "drag": [4, 4, 4],
	"lifetime": [5, 0, 4], "target_offset": [5, 4, 4],
	"particle_count": [6, 4, 4],
	"spawn_interval": [7, 0, 4], "homing_strength": [7, 4, 2], "homing_blend": [7, 6, 2],
}

# Colour curve nibbles ("color_curve_r|g|b"): stored decoded in color_curves; the
# writer reconstructs bytes 0x10/0x11 nibble-wise, preserving the unparsed high
# nibble of 0x11.
const _COLOR_CURVE := ["r", "g", "b"]

# Packed control-byte sub-fields (camera-command-word style, master_parser decode):
# field → [raw_data byte key, bit shift, value mask]. An edit masks ONLY its bits
# (unread/vestigial sibling bits are byte-preserved) and re-derives the decoded
# `flags` cache. Bits 0 + 2-4 of motion_type_flag, 4-7 of animation_target_flag,
# 5/7 of flags_lo and 3-7 of flags_hi are not read by the engine — never exposed.
const _PACKED := {
	"align_to_velocity": ["motion_type_flag", 1, 1],
	"target_anchor_mode": ["motion_type_flag", 5, 7],
	"spread_mode": ["animation_target_flag", 0, 1],
	"emitter_anchor_mode": ["animation_target_flag", 1, 7],
	"child_death_mode": ["emitter_flags_lo", 0, 3],
	"child_midlife_mode": ["emitter_flags_lo", 2, 3],
	"velocity_inward": ["emitter_flags_lo", 4, 1],
	"color_curve_enable": ["emitter_flags_lo", 6, 1],
	"homing_arrival_threshold": ["emitter_flags_hi", 0, 3],
	"align_to_facing": ["emitter_flags_hi", 2, 1],
}

# Packed edits whose value feeds a DERIVED row (the combined "Velocity mode"
# const) — they ask the page to re-project the section.
const _PACKED_RELAYOUT := ["velocity_inward", "align_to_facing"]

# Decoded-name maps for the flags recompute — mirror parse_effect.py's
# ANCHOR_MODES / TARGET_ANCHOR_MODES (the ONE ROM decode).
const _ANCHOR_MODES := {0: "WORLD", 1: "CURSOR", 2: "ORIGIN", 3: "TARGET",
	4: "PARENT", 5: "CAMERA", 6: "TRACKED"}
const _TARGET_ANCHOR_MODES := {0x00: "WORLD", 0x20: "WORLD", 0x40: "CAMERA",
	0x60: "ORIGIN", 0x80: "TARGET", 0xA0: "PARENT", 0xC0: "UNKNOWN_C0", 0xE0: "UNKNOWN_E0"}

# Callback params ("callback_param_<hex offset>"): REAL raw values the effect's
# native callback reads (not inert) — field → [callback_params key, encoding].
const _CALLBACK := {
	"callback_param_4C": ["param_4C", "u8"], "callback_param_4E": ["param_4E", "u8"],
	"callback_param_A8": ["param_A8", "s16"], "callback_param_AA": ["param_AA", "s16"],
	"callback_param_AC": ["param_AC", "s16"], "callback_param_AE": ["param_AE", "s16"],
}

# Child wiring (u8, 255 = none): the runtime field stores -1-normalized. Rewiring
# re-projects the score child graph (relayout).
const _CHILD := ["child_emitter_on_death", "child_emitter_mid_life"]


## Write one raw emitter value for the field named by `field_ref` (address:
## `{emitter_index, field}` — emitters are a flat shared table, not per-phase),
## recompute the converted cache, and return the snapshot the choke point records.
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	var em = _resolve_emitter(data, field_ref)
	if em == null:
		push_error("EmitterChannel: no emitter for %s" % str(field_ref))
		return {}
	var field: String = field_ref.get("field", "")
	var raw: int = int(new_raw)

	var prefix := _vec3_prefix(field)
	if prefix != "":
		return _apply_vec3(em, prefix, _COMPONENT[field.right(1)], raw)
	if _SCALAR.has(field):
		return _apply_scalar(em, field, raw)
	if _DIRECT.has(field):
		return _apply_direct(em, field, raw)
	if field.begins_with("color_curve_") and field.trim_prefix("color_curve_") in _COLOR_CURVE:
		return _apply_color_curve(em, field.trim_prefix("color_curve_"), raw)
	if field.begins_with("curve_") and _CURVE.has(field.trim_prefix("curve_")):
		return _apply_curve(em, field.trim_prefix("curve_"), raw)
	if _PACKED.has(field):
		return _apply_packed(em, field, raw)
	if _CALLBACK.has(field):
		return _apply_callback(em, field, raw)
	if field in _CHILD:
		return _apply_child(em, field, raw)

	push_error("EmitterChannel: unknown emitter field '%s'" % field)
	return {}


## The READ side of the one field→storage map: the current raw int for any editable
## emitter field — what the projector seeds its cells with, so the read and write
## sides can never desync. Missing raw_data keys read as 0 (a sparse fixture must
## project, not crash).
static func read_raw(em, field: String) -> int:
	var prefix := _vec3_prefix(field)
	if prefix != "":
		var arr = em.raw_data.get(_VEC3[prefix][0])
		return int(arr[_COMPONENT[field.right(1)]]) if arr is Array else 0
	if _SCALAR.has(field):
		return int(em.raw_data.get(_SCALAR[field][0], 0))
	if _DIRECT.has(field):
		return int(em.get(field))
	if field.begins_with("curve_") and _CURVE.has(field.trim_prefix("curve_")):
		# The DECODED index, not the ROM nibble. Since the ADR-0089 explode a use site's
		# curve index is a private array position that routinely exceeds the nibble's reach,
		# and `em.curves` is the authoring truth; `curve_indices_raw` keeps the original
		# nibble as PROVENANCE for the deferred compiler. Convention unchanged: 0 = none.
		var idx: int = int(em.curves.get(field.trim_prefix("curve_"), -1))
		return 0 if idx < 0 else idx + 1
	# Guard the colour-curve prefix like apply_raw does: "color_curve_enable" is
	# a PACKED flags_lo bit, not a colour nibble — only r/g/b route here.
	if field.begins_with("color_curve_") and field.trim_prefix("color_curve_") in _COLOR_CURVE:
		return int(em.color_curves.get(field.trim_prefix("color_curve_"), 0))
	if _PACKED.has(field):
		var spec: Array = _PACKED[field]
		return (int(em.raw_data.get(spec[0], 0)) >> int(spec[1])) & int(spec[2])
	if _CALLBACK.has(field):
		return int(em.callback_params.get(_CALLBACK[field][0], 0))
	if field in _CHILD:
		var cur: int = int(em.get(field))
		return 255 if cur < 0 else cur
	push_error("EmitterChannel: read_raw unknown field '%s'" % field)
	return 0


## The vec3 table prefix of a component field ("position_start_x" → "position_start"),
## or "" when the field is not a vec3 component.
static func _vec3_prefix(field: String) -> String:
	if field.length() < 3 or field[field.length() - 2] != "_":
		return ""
	if not _COMPONENT.has(field.right(1)):
		return ""
	var prefix := field.left(field.length() - 2)
	return prefix if _VEC3.has(prefix) else ""


## Write one component of an s16 triplet: raw lands in the raw_data array slot, the
## cache Vector3 component is re-derived with the parser's conversion.
static func _apply_vec3(em, prefix: String, comp: int, new_raw: int) -> Dictionary:
	var refusal := _refuse_outside(prefix, "s16", new_raw)
	if not refusal.is_empty():
		return refusal
	var raw_key: String = _VEC3[prefix][0]
	var cache_attr: String = _VEC3[prefix][1]
	var kind: String = _VEC3[prefix][2]
	if not (em.raw_data.get(raw_key) is Array):
		push_error("EmitterChannel: emitter raw_data missing '%s'" % raw_key)
		return {}
	var before: int = int(em.raw_data[raw_key][comp])
	em.raw_data[raw_key][comp] = new_raw
	var vec: Vector3 = em.get(cache_attr)
	vec[comp] = _convert(kind, new_raw, comp)
	em.set(cache_attr, vec)
	return _result(before, new_raw)


## Write a converted scalar (radial velocity / homing strength): raw in raw_data,
## cache float re-derived.
static func _apply_scalar(em, field: String, new_raw: int) -> Dictionary:
	var refusal := _refuse_outside(field, "s16", new_raw)
	if not refusal.is_empty():
		return refusal
	var raw_key: String = _SCALAR[field][0]
	var cache_attr: String = _SCALAR[field][1]
	if not em.raw_data.has(raw_key):
		push_error("EmitterChannel: emitter raw_data missing '%s'" % raw_key)
		return {}
	var before: int = int(em.raw_data[raw_key])
	em.raw_data[raw_key] = new_raw
	em.set(cache_attr, _convert(_SCALAR[field][2], new_raw, -1))
	return _result(before, new_raw)


## Write a raw-direct field — the field is the storage, so write it in place
## (numeric type preserved: float fields stay float, int fields int).
static func _apply_direct(em, field: String, new_raw: int) -> Dictionary:
	var refusal := _refuse_outside(field, _DIRECT[field], new_raw)
	if not refusal.is_empty():
		return refusal
	var before: int = int(em.get(field))
	em.set(field, float(new_raw) if em.get(field) is float else new_raw)
	return _result(before, new_raw)


## Point a param at a curve: `new_raw` is the private index + 1 (0 = none), written to the
## decoded `em.curves` cache the runtime samples.
##
## It used to write the 4-bit NIBBLE in `curve_indices_raw` and derive the cache from it.
## That is a PSX PACKING rule, and ADR-0089's curve-ownership amendment moved packing to the
## compiler: after the explode a use site's index is a private array position (median ~22
## entries, max 67), so a nibble cannot hold it and the old `0..15` refusal would have
## blocked legal edits. The nibble is left alone deliberately — it is the ROM PROVENANCE the
## compiler assigns final indices from, and overwriting it with an authoring-side number
## would destroy exactly what the round-trip is built on.
static func _apply_curve(em, param: String, new_raw: int) -> Dictionary:
	var refusal := _refuse_outside("curve_" + param, "an index + 1 (0 = none)", new_raw, 0, 1 << 30)
	if not refusal.is_empty():
		return refusal
	var cur: int = int(em.curves.get(param, -1))
	var before: int = 0 if cur < 0 else cur + 1
	em.curves[param] = new_raw - 1 if new_raw > 0 else -1
	# Assigning/clearing a curve changes the group's RELEVANCE (curve==none deads
	# the end axis) — the inspector must re-project so the "at end" row and the
	# header glyph appear/disappear. Relayout, not a plain value edit.
	var res := _result(before, new_raw)
	res["relayout"] = true
	return res


## Write one packed control-byte sub-field: mask its bits out of the host byte in
## raw_data, OR the new value in (sibling bits — including engine-unread ones —
## are preserved), and re-derive the decoded flags cache the runtime reads.
static func _apply_packed(em, field: String, new_raw: int) -> Dictionary:
	var byte_key: String = _PACKED[field][0]
	var shift: int = _PACKED[field][1]
	var mask: int = _PACKED[field][2]
	var refusal := _refuse_outside(field, "0..%d" % mask, new_raw, 0, mask)
	if not refusal.is_empty():
		return refusal
	if not em.raw_data.has(byte_key):
		push_error("EmitterChannel: emitter raw_data missing '%s'" % byte_key)
		return {}
	var b: int = int(em.raw_data[byte_key])
	var before: int = (b >> shift) & mask
	em.raw_data[byte_key] = (b & ~(mask << shift)) | (new_raw << shift)
	_recompute_flags(em)
	var res := _result(before, new_raw)
	if field in _PACKED_RELAYOUT:
		res["relayout"] = true
	return res


## Re-derive the decoded `flags` dict from the four packed control bytes — the
## exact parse_effect.py decode, so runtime reads and Config labels stay honest.
static func _recompute_flags(em) -> void:
	var motion: int = int(em.raw_data.get("motion_type_flag", 0))
	var anim_target: int = int(em.raw_data.get("animation_target_flag", 0))
	var lo: int = int(em.raw_data.get("emitter_flags_lo", 0))
	var hi: int = int(em.raw_data.get("emitter_flags_hi", 0))
	em.flags["align_to_velocity"] = bool(motion & 0x02)
	em.flags["target_anchor_mode"] = _TARGET_ANCHOR_MODES.get(motion & 0xE0,
		"UNKNOWN_%02X" % (motion & 0xE0))
	em.flags["spread_mode"] = "BOX" if (anim_target & 0x01) else "SPHERICAL"
	em.flags["emitter_anchor_mode"] = _ANCHOR_MODES.get((anim_target >> 1) & 0x07, "UNKNOWN")
	em.flags["color_curve_enabled"] = bool(lo & 0x40)
	em.flags["velocity_inward"] = bool(lo & 0x10)
	em.flags["child_death_enabled"] = bool(lo & 0x03)
	em.flags["child_midlife_enabled"] = bool(lo & 0x0C)
	em.flags["align_to_facing"] = bool(hi & 0x04)
	em.flags["homing_arrival_threshold"] = hi & 0x03


## Write one callback param in place (the native callback reads it live).
static func _apply_callback(em, field: String, new_raw: int) -> Dictionary:
	var key: String = _CALLBACK[field][0]
	var refusal := _refuse_outside(field, str(_CALLBACK[field][1]), new_raw)
	if not refusal.is_empty():
		return refusal
	var before: int = int(em.callback_params.get(key, 0))
	em.callback_params[key] = new_raw
	return _result(before, new_raw)


## Rewire a child-emitter edge: raw u8 (255 = none) ↔ the -1-normalized runtime
## field. The score child graph re-projects (relayout).
static func _apply_child(em, field: String, new_raw: int) -> Dictionary:
	var refusal := _refuse_outside(field, "u8", new_raw)
	if not refusal.is_empty():
		return refusal
	var cur: int = int(em.get(field))
	var before: int = 255 if cur < 0 else cur
	em.set(field, -1 if new_raw >= 255 else new_raw)
	var res := _result(before, new_raw)
	res["relayout"] = true
	return res


## Point a colour channel at a curve (decoded storage; the compiler re-packs 0x10/0x11).
##
## This refused anything outside `0..15` — the ROM nibble's reach. That is a PSX PACKING
## rule enforced in the AUTHORING layer, and under ADR-0089's curve-ownership amendment
## indices routinely exceed 15, so the check blocked legal edits rather than catching bad
## ones. It belongs to the deferred compiler, which refuses at export with a count and an
## itemised overrun. What survives is the storage floor: -1 means "no curve", and nothing
## below that is an address.
static func _apply_color_curve(em, chan: String, new_raw: int) -> Dictionary:
	var refusal := _refuse_outside("color_curve_" + chan, "an index (-1 = none)", new_raw, -1, 1 << 30)
	if not refusal.is_empty():
		return refusal
	var before: int = int(em.color_curves.get(chan, 0))
	em.color_curves[chan] = new_raw
	# Re-project so the row's sparkline redraws the newly-assigned colour curve.
	var res := _result(before, new_raw)
	res["relayout"] = true
	return res


## The raw→Godot-unit conversion. The MAGNITUDE routes through the single PsxMagnitude
## seam (ADR-0091); component 1 (Y) is negated for position- and accel-scale values
## (chirality — FFT -Y is up, ADR-0052/0057; a separate axis), angles never flip.
static func _convert(kind: String, raw: int, comp: int) -> float:
	var v := -float(raw) if comp == 1 and (kind == "pos" or kind == "accel") else float(raw)
	match kind:
		"pos": return PsxMagnitude.tile_to_game(v)
		"angle": return PsxMagnitude.angle_to_rad(v)
		"vel": return PsxMagnitude.radial_velocity_to_game(v)
		"accel", "homing": return PsxMagnitude.accel_to_game(v)
	return v


## The REFUSAL for raw outside its storage encoding (ADR-0089: never clamp) —
## `no_edit` + a faithful explanation, so the choke point records nothing.
## Empty when the value fits.
static func _refuse_outside(field: String, encoding: String, raw: int, lo: int = 1, hi: int = 0) -> Dictionary:
	if lo > hi:  # no explicit bounds — derive them from the named encoding
		match encoding:
			"s16": lo = -32768; hi = 32767
			"u16": lo = 0; hi = 65535
			"u8": lo = 0; hi = 255
	if raw >= lo and raw <= hi:
		return {}
	push_error("EmitterChannel: refused %s = %d — outside the %s encoding [%d, %d]"
		% [field, raw, encoding, lo, hi])
	return {"no_edit": true, "faithful": {"ok": false, "reason":
		"%s = %d does not fit the %s storage encoding [%d, %d]" % [field, raw, encoding, lo, hi]}}


static func _result(before: int, after: int) -> Dictionary:
	return {
		"before_raw": before,
		"after_raw": after,
		"invalidates_sim": true,
		"faithful": {"ok": true, "reason": ""},
	}


static func _resolve_emitter(data, field_ref: Dictionary):
	if data == null:
		return null
	return data.get_emitter(int(field_ref.get("emitter_index", -1)))
