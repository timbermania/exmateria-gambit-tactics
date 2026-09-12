extends RefCounted
## The time-scale half of the Studio game→json→bin repack (#270, ADR-0093) — the counterpart to
## EffectFlagsSaver. Given an effect id and the LIVE (possibly edited) time_scale dict, it
## serializes the two pacing curves into a minimal time_scale.json shape and shells out to the
## byte-exact Python writer (`write_effect_time_scale.py`) to produce a PARTIAL-PATCHED E###.BIN —
## only the two 300-byte nibble-packed curve regions @ time_scale_ptr are rewritten, every other
## byte copied verbatim from the base.
##
## COMPOSITION. `save` accepts a `base_bin_override`: the host layers this patch on TOP of the
## previous writer's output BIN. The time_scale region is DISJOINT from every other section (it
## sits between the anim table and the effect_flags byte), so it composes in any order — with no
## override it patches the pristine ROM extract.
##
## The two enable BITS are NOT written here — they live in the effect_flags byte and save through
## EffectFlagsSaver; this saver owns only the curve samples.
##
## No `class_name` (ADR-0004) — savers, like projectors, stay path-preloaded.

const OUT_DIR := "res://authored_effects"
const BASE_BIN_REL := "../project-assets/fft-extract/EFFECT/%s.BIN"


## Serialize a live time_scale dict into the minimal shape the byte writer consumes:
## `{outer_phases, for_each}`, the two 600-int pacing curves. A dict missing either curve is a
## hard error.
static func to_time_scale_json(time_scale: Dictionary) -> Dictionary:
	if time_scale == null or time_scale.is_empty() \
			or not (time_scale.get("outer_phases", null) is Array) \
			or not (time_scale.get("for_each", null) is Array):
		return {"ok": false, "json": {}, "error": "no time_scale curves to save"}
	return {"ok": true, "json": {
		"outer_phases": time_scale["outer_phases"],
		"for_each": time_scale["for_each"],
	}, "error": ""}


## Repack the two pacing curves of effect `effect_id` from the live `time_scale` dict.
## `base_bin_override` (absolute path) layers this patch onto an already-patched BIN; empty →
## patch the pristine ROM extract. Returns {ok, out_path, error}; never raises — a missing base /
## curves / failed writer is a reported error.
static func save(effect_id: int, time_scale: Dictionary, base_bin_override: String = "") -> Dictionary:
	var eff := "E%03d" % effect_id

	var adapted: Dictionary = to_time_scale_json(time_scale)
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
	var ts_res := "%s/%s.time_scale.json" % [OUT_DIR, eff]
	var tf := FileAccess.open(ts_res, FileAccess.WRITE)
	if tf == null:
		return {"ok": false, "out_path": "", "error": "cannot write %s" % ts_res}
	tf.store_string(JSON.stringify(adapted["json"]))
	tf.close()

	var out_bin_res := "%s/%s.BIN" % [OUT_DIR, eff]
	var out_bin_abs := ProjectSettings.globalize_path(out_bin_res)

	var args := [
		"run", "--project", ProjectSettings.globalize_path("res://tools"),
		"python", ProjectSettings.globalize_path("res://tools/write_effect_time_scale.py"),
		base_bin,
		ProjectSettings.globalize_path(ts_res),
		ProjectSettings.globalize_path(header_res),
		out_bin_abs,
	]
	var output: Array = []
	var code := OS.execute("uv", args, output, true)
	if code != 0:
		return {"ok": false, "out_path": "",
			"error": "writer exit %d: %s" % [code, "\n".join(output)]}

	return {"ok": true, "out_path": out_bin_abs, "error": ""}
