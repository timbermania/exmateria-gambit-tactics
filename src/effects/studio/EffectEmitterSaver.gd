class_name EffectEmitterSaver
extends RefCounted
## The emitter half of the Studio game→json→bin repack (ADR-0089 slice 4), the
## counterpart to EffectScreenSaver / EffectCameraSaver / EffectPaletteSaver.
## Given an effect id and the LIVE (possibly edited) `EffectData.emitters`, it
## serializes each shared emitter back into the parser-shaped raw dict and shells
## out to the byte-exact Python writer (`write_effect_emitters.py`) to produce a
## PARTIAL-PATCHED E###.BIN — only the known emitter fields are rewritten; every
## unparsed byte (unknown_12/13, 0x4D/0x50-0x53, the 0x11 high nibble,
## reserved_C2/C3) and every other section is copied verbatim from the base.
##
## PRESENT-KEYS-ONLY (the crux): the channel edits raw storage that mirrors what
## the parser surfaced — so the saver emits exactly the keys with live backing
## (raw_data slots, packed bytes, curve nibbles, direct raw fields, callback
## params) and OMITS the rest. The writer patches only present keys, so an
## unedited emitter round-trips byte-identically even against a stale
## emitters.json that predates newer parser keys.
##
## COMPOSITION. `save` accepts a `base_bin_override`: the host layers the emitter
## patch on TOP of the previous section writers' output BIN so every channel's
## edits land in ONE file. With no override it patches the pristine ROM extract.

# Output lives beside the project (gitignore-able), never in the ROM extract.
const OUT_DIR := "res://authored_effects"
# The ROM extract, a sibling of the Godot project (project-assets symlink at repo root).
const BASE_BIN_REL := "../project-assets/fft-extract/EFFECT/%s.BIN"

# raw_data keys that belong to the writer's `raw` sub-dict (vec3 triplets + s16
# scalars) — mirror write_effect_emitters._RAW_VEC3/_RAW_S16.
const _RAW_VEC3_KEYS := [
	"position_start", "position_end", "spread_start", "spread_end",
	"angle_start", "angle_end", "vel_spread_start", "vel_spread_end",
	"accel_min_start", "accel_max_start", "accel_min_end", "accel_max_end",
	"drag_min_start", "drag_max_start", "drag_min_end", "drag_max_end",
	"target_start", "target_end",
]
const _RAW_S16_KEYS := [
	"radial_min_start", "radial_max_start", "radial_min_end", "radial_max_end",
	"homing_min_start", "homing_max_start", "homing_min_end", "homing_max_end",
]
# Packed control + reserved bytes stashed in raw_data, emitted top-level.
const _PACKED_KEYS := ["byte_00", "byte_05", "motion_type_flag",
	"animation_target_flag", "emitter_flags_lo", "emitter_flags_hi"]


## The ROM table slot a LIVE colour-curve address stands for, or -1 when it names none.
##
## `CurveExplode` stamps each private copy's `EffectCurve.index` with the slot it was copied
## from, and `mint_identity` stamps -1 because a minted curve came from no slot. So this is a
## lookup, not a search: the live index addresses the exploded array, and the entry there
## remembers where it came from. Out-of-range and unresolvable addresses (the 60 corpus
## references into an empty curves.json, all in E509/E510) answer -1 too — they read as "no
## curve" everywhere else and must not become slot 0 here.
static func _colour_rom_slot(curves, live_index: int) -> int:
	if curves == null or live_index < 0 or live_index >= curves.size():
		return -1
	var c = curves[live_index]
	if c == null:
		return -1
	var slot := int(c.index)
	return slot if slot >= 0 and slot <= 15 else -1


## Serialize the live emitters into the writer's list-of-dicts shape. Returns
## {ok, json, error}. Emitters are addressed by ARRAY POSITION (the record index
## every channel/keyframe reference uses).
static func to_emitters_json(effect_data) -> Dictionary:
	if effect_data == null or effect_data.emitters == null:
		return {"ok": false, "json": [], "error": "no emitters to save"}
	var out: Array = []
	for i in range(effect_data.emitters.size()):
		out.append(_emitter_to_dict(effect_data.emitters[i], i, effect_data.curves))
	return {"ok": true, "json": out, "error": ""}


## One live EffectEmitter → the parser-shaped raw dict, present-keys-only.
static func _emitter_to_dict(em, index: int, curves = null) -> Dictionary:
	var d := {"index": index, "anim_index": int(em.anim_index), "anim_param": int(em.anim_param)}

	for key in _PACKED_KEYS:
		if em.raw_data.has(key):
			d[key] = int(em.raw_data[key])

	var ci = em.raw_data.get("curve_indices_raw")
	if ci is Array and not ci.is_empty():
		var nibbles: Array = []
		for b in ci:
			nibbles.append(int(b))
		d["curve_indices_raw"] = nibbles

	# COLOUR CURVE ADDRESSES ARE WRITTEN BY PROVENANCE, NOT BY LIVE INDEX (2026-08-21).
	#
	# These three are nibbles in the ROM record — r/g pack byte 0x10, b is 0x11's low nibble —
	# so the only value that can go here is a ROM table slot, 0..15. Since the ADR-0089
	# curve-ownership amendment, `em.color_curves` no longer holds one: `CurveExplode` runs at
	# load and gives every use site its own PRIVATE curve at a fresh index, so a live address is
	# an offset into the exploded array and is routinely > 15. The writer masks with `& 0x0F`,
	# which turned a silent divergence into a silent corruption — index 17 wrote as 1.
	#
	# It regressed the byte-exact round trip for every effect with colour: E001's seven emitters
	# all had `{r:0, g:0, b:0}` (aliased onto ROM slot 0) and saved as seven distinct indices,
	# 14 bytes of drift on a file nothing had edited. `EffectStudioSaveTest` and
	# `EffectEmitterSaveAcceptanceTest` both caught it, at 0x10/0x11 of every record.
	#
	# `EffectCurve.index` carries the slot the private copy came from — the provenance
	# CurveExplode records for exactly this, and which the ADR notes nothing read yet. Writing
	# it restores the untouched round trip by the rule the ADR states ("restore an untouched
	# effect's original indices by provenance first"), and it is not a new mechanism, only its
	# first caller.
	#
	# A channel whose provenance is -1 is OMITTED rather than guessed: -1 means the curve was
	# MINTED (`CurveExplode.mint_identity` — a use site that had no ROM curve at all) or the
	# address does not resolve, and neither has a slot to name. Present-keys-only is exactly
	# the right answer there: the writer leaves 0x10/0x11 as the base has them, so the record
	# keeps saying what the ROM said instead of claiming slot 0. Giving a minted curve a real
	# slot is the deferred compiler's job — dedup by value, re-pack the nibbles, refuse past 15
	# distinct shapes — and it cannot be done one emitter at a time, which is why it is not
	# attempted here.
	var cc := {}
	for chan in em.color_curves:
		var slot := _colour_rom_slot(curves, int(em.color_curves[chan]))
		if slot >= 0:
			cc[chan] = slot
	if not cc.is_empty():
		d["color_curves"] = cc

	var raw := {}
	for key in _RAW_VEC3_KEYS:
		var vec = em.raw_data.get(key)
		if vec is Array and vec.size() >= 3:
			raw[key] = [int(vec[0]), int(vec[1]), int(vec[2])]
	for key in _RAW_S16_KEYS:
		if em.raw_data.has(key):
			raw[key] = int(em.raw_data[key])
	if not raw.is_empty():
		d["raw"] = raw

	# Direct raw fields — always live on the emitter, always emitted.
	d["inertia"] = {"min_start": int(em.inertia_min_start), "max_start": int(em.inertia_max_start),
		"min_end": int(em.inertia_min_end), "max_end": int(em.inertia_max_end)}
	d["weight"] = {"min_start": int(em.weight_min_start), "max_start": int(em.weight_max_start),
		"min_end": int(em.weight_min_end), "max_end": int(em.weight_max_end)}
	d["lifetime"] = {"min_start": int(em.lifetime_min_start), "max_start": int(em.lifetime_max_start),
		"min_end": int(em.lifetime_min_end), "max_end": int(em.lifetime_max_end)}
	d["spawn"] = {"particle_count_start": int(em.particle_count_start),
		"particle_count_end": int(em.particle_count_end),
		"interval_start": int(em.spawn_interval_start), "interval_end": int(em.spawn_interval_end)}

	if not em.callback_params.is_empty():
		var cb := {}
		for key in em.callback_params:
			cb[key] = int(em.callback_params[key])
		d["callback_params"] = cb

	d["child_emitter_on_death"] = 255 if em.child_emitter_on_death < 0 else int(em.child_emitter_on_death)
	d["child_emitter_mid_life"] = 255 if em.child_emitter_mid_life < 0 else int(em.child_emitter_mid_life)
	return d


## Repack the emitter block of effect `effect_id` from the live effect_data.
## `base_bin_override` (absolute path) layers the emitter patch onto an already-
## patched BIN (the previous section writers' output); empty → the pristine ROM
## extract. Returns {ok, out_path, error}; never raises.
static func save(effect_id: int, effect_data, base_bin_override: String = "") -> Dictionary:
	var eff := "E%03d" % effect_id

	var adapted: Dictionary = to_emitters_json(effect_data)
	if not adapted.get("ok", false):
		return {"ok": false, "out_path": "", "error": adapted.get("error", "adapter failed")}

	var header_res := "res://assets/effects/%s/header.json" % eff
	if not FileAccess.file_exists(header_res):
		return {"ok": false, "out_path": "", "error": "no header.json for %s" % eff}

	var base_bin: String = base_bin_override
	if base_bin.is_empty():
		base_bin = ProjectSettings.globalize_path("res://").path_join(BASE_BIN_REL % eff).simplify_path()
	if not FileAccess.file_exists(base_bin):
		return {"ok": false, "out_path": "",
			"error": "base %s.BIN not found at %s" % [eff, base_bin]}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var emitters_res := "%s/%s.emitters.json" % [OUT_DIR, eff]
	var ef := FileAccess.open(emitters_res, FileAccess.WRITE)
	if ef == null:
		return {"ok": false, "out_path": "", "error": "cannot write %s" % emitters_res}
	ef.store_string(JSON.stringify(adapted["json"]))
	ef.close()

	var out_bin_res := "%s/%s.BIN" % [OUT_DIR, eff]
	var out_bin_abs := ProjectSettings.globalize_path(out_bin_res)

	var args := [
		"run", "--project", ProjectSettings.globalize_path("res://tools"),
		"python", ProjectSettings.globalize_path("res://tools/write_effect_emitters.py"),
		base_bin,
		ProjectSettings.globalize_path(emitters_res),
		ProjectSettings.globalize_path(header_res),
		out_bin_abs,
	]
	var output: Array = []
	var code := OS.execute("uv", args, output, true)
	if code != 0:
		return {"ok": false, "out_path": "",
			"error": "writer exit %d: %s" % [code, "\n".join(output)]}

	return {"ok": true, "out_path": out_bin_abs, "error": ""}
