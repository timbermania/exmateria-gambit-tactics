extends RefCounted
## The game-JSON save half of curve authoring. The game LOADS effects from JSON
## (EffectData.load_from_directory), so persisting the live curve table to curves.json and
## repointing emitters.json's curve addresses by FULL INDEX is what makes an authored curve
## real. Mirrors the Effect*Saver two-half pattern but writes the JSON half ONLY — the
## byte-exact BIN pack (dedup by value, restore indices by provenance, re-pack the nibbles,
## refuse past 15 distinct shapes) is the deferred COMPILER pass.
##
## It began as the colour-keyframe half (ADR-0089 Amendment 2026-08-12 (colour-keyframe) item 9), when only colour forked its
## curves. Since the curve-ownership amendment EVERY use site owns a private curve, so both
## address dicts move, not just `color_curves` — writing one and not the other would leave a
## curves.json that its own emitters.json no longer indexes correctly.
##
## Expect the file to GROW: an effect's curves.json goes from 15 entries to ~22 (the median
## use-site count) the first time it is saved, even untouched. That is documented diff noise on
## an intermediate artifact, not a fidelity loss — the compiler restores the original indices by
## provenance, so the compiled output is identical.
##
## Non-destructive: output goes to res://authored_effects/E###/, never clobbering the ROM-derived
## source under res://assets/effects/ (same rule as the other savers). curves.json is serialized
## from the live table; emitters.json is the SOURCE emitters.json with only each emitter's curve
## addresses repointed — every other field is copied verbatim (present-keys-only, so an untouched
## emitter round-trips exactly).
##
## No `class_name` (ADR-0004) — preloaded by path.

const OUT_DIR := "res://authored_effects"
const SOURCE_DIR := "res://assets/effects"


## Serialize the live curve table as the parser's curves.json shape: one {index, values} per
## curve, samples renormalized float [0,1] → int [0,255] (the inverse of load's `÷ 255`).
static func to_curves_json(effect_data) -> Array:
	var out: Array = []
	if effect_data == null or effect_data.curves == null:
		return out
	for i in range(effect_data.curves.size()):
		var samples: Array = effect_data.curves[i].samples
		var values: Array = []
		values.resize(samples.size())
		for j in range(samples.size()):
			values[j] = clampi(roundi(float(samples[j]) * 255.0), 0, 255)
		out.append({"index": i, "values": values})
	return out


## Return the source emitters JSON with each emitter's CURVE ADDRESSES — both the param
## `curves` dict and `color_curves` — repointed to the live private indices, every other key
## preserved. Emitters are addressed by ARRAY POSITION (the same record index every reference
## uses); emitters beyond the live list are copied untouched.
##
## BOTH dicts, because a use site is an (emitter, slot) pair and the explode repoints every one
## of them. Patching only `color_curves` — which is all this did while colour was the only kind
## that forked — would write an exploded curves.json alongside param addresses still naming ROM
## slots, and every param curve would reload as some other use site's shape.
static func patch_curve_addresses(original_emitters: Array, effect_data) -> Array:
	var patched: Array = original_emitters.duplicate(true)
	var live = effect_data.emitters if effect_data != null else []
	for i in range(patched.size()):
		if i >= live.size():
			continue
		var cc: Dictionary = live[i].color_curves
		if not cc.is_empty():
			patched[i]["color_curves"] = {
				"r": int(cc.get("r", -1)),
				"g": int(cc.get("g", -1)),
				"b": int(cc.get("b", -1)),
			}
		var pc: Dictionary = live[i].curves
		if not pc.is_empty():
			var out := {}
			for key in pc:
				out[key] = int(pc[key])
			patched[i]["curves"] = out
	return patched


## Write curves.json + emitters.json for effect `effect_id` into authored_effects/E###/.
## Returns {ok, out_path, error}; never raises.
static func save(effect_id: int, effect_data) -> Dictionary:
	var eff := "E%03d" % effect_id
	if effect_data == null:
		return {"ok": false, "out_path": "", "error": "no effect data"}

	var src_emitters := "%s/%s/emitters.json" % [SOURCE_DIR, eff]
	var original = _load_json_array(src_emitters)
	if original == null:
		return {"ok": false, "out_path": "", "error": "no source emitters.json for %s" % eff}

	var out_dir := "%s/%s" % [OUT_DIR, eff]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	var curves_res := "%s/curves.json" % out_dir
	if not _write_json(curves_res, to_curves_json(effect_data)):
		return {"ok": false, "out_path": "", "error": "cannot write %s" % curves_res}

	var emitters_res := "%s/emitters.json" % out_dir
	if not _write_json(emitters_res, patch_curve_addresses(original, effect_data)):
		return {"ok": false, "out_path": "", "error": "cannot write %s" % emitters_res}

	return {"ok": true, "out_path": ProjectSettings.globalize_path(out_dir), "error": ""}


static func _load_json_array(res_path: String):
	if not FileAccess.file_exists(res_path):
		return null
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Array else null


static func _write_json(res_path: String, data) -> bool:
	var f := FileAccess.open(res_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true
