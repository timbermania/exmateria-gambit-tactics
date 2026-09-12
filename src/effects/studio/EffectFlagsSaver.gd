extends RefCounted
## The effect-flags half of the Studio game→json→bin repack (#272, ADR-0092) — the counterpart
## to EffectTimelineHeaderSaver. Given an effect id and the LIVE (possibly edited) flags dict, it
## serializes the single flags byte into a minimal flags.json shape and shells out to the
## byte-exact Python writer (`write_effect_flags.py`) to produce a PARTIAL-PATCHED E###.BIN —
## only the one flags byte @ effect_flags_ptr is rewritten, every other byte copied verbatim from
## the base (the dead 0x04 override + the 16 sound-channel bytes are untouched).
##
## COMPOSITION. `save` accepts a `base_bin_override`: the host layers this patch on TOP of the
## previous writer's output BIN (it runs after the timeline-header saver — the flags byte
## @effect_flags_ptr is DISJOINT from the timeline durations @timeline_section_ptr), so every
## edit lands in ONE file. With no override it patches the pristine ROM extract.
##
## No `class_name` (ADR-0004) — savers, like projectors, stay path-preloaded.

const OUT_DIR := "res://authored_effects"
const BASE_BIN_REL := "../project-assets/fft-extract/EFFECT/%s.BIN"


## Serialize a live flags dict into the minimal shape the byte writer consumes: `{flags_byte}`,
## read from the raw byte (the round-trip source of truth, kept current by EffectFlagsChannel).
## An empty flags dict is a hard error.
static func to_flags_json(flags: Dictionary) -> Dictionary:
	if flags == null or flags.is_empty() or not flags.has("flags_byte"):
		return {"ok": false, "json": {}, "error": "no flags data to save"}
	return {"ok": true, "json": {"flags_byte": int(flags["flags_byte"])}, "error": ""}


## Repack the flags byte of effect `effect_id` from the live `flags` dict. `base_bin_override`
## (absolute path) layers this patch onto an already-patched BIN; empty → patch the pristine ROM
## extract. Returns {ok, out_path, error}; never raises — a missing base / flags / failed writer
## is a reported error.
static func save(effect_id: int, flags: Dictionary, base_bin_override: String = "") -> Dictionary:
	var eff := "E%03d" % effect_id

	var adapted: Dictionary = to_flags_json(flags)
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
	var flags_res := "%s/%s.flags.json" % [OUT_DIR, eff]
	var ff := FileAccess.open(flags_res, FileAccess.WRITE)
	if ff == null:
		return {"ok": false, "out_path": "", "error": "cannot write %s" % flags_res}
	ff.store_string(JSON.stringify(adapted["json"]))
	ff.close()

	var out_bin_res := "%s/%s.BIN" % [OUT_DIR, eff]
	var out_bin_abs := ProjectSettings.globalize_path(out_bin_res)

	var args := [
		"run", "--project", ProjectSettings.globalize_path("res://tools"),
		"python", ProjectSettings.globalize_path("res://tools/write_effect_flags.py"),
		base_bin,
		ProjectSettings.globalize_path(flags_res),
		ProjectSettings.globalize_path(header_res),
		out_bin_abs,
	]
	var output: Array = []
	var code := OS.execute("uv", args, output, true)
	if code != 0:
		return {"ok": false, "out_path": "",
			"error": "writer exit %d: %s" % [code, "\n".join(output)]}

	return {"ok": true, "out_path": out_bin_abs, "error": ""}
