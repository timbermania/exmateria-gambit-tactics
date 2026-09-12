class_name EffectTimelineHeaderSaver
extends RefCounted
## The timeline-header half of the Studio game→json→bin repack (#271) — the counterpart to
## EffectParticleTimelineSaver. Given an effect id and the LIVE (possibly edited) TimelineData,
## it serializes the three GLOBAL phase durations into a minimal timeline.json shape and shells
## out to the byte-exact Python writer (`write_effect_timeline_header.py`) to produce a
## PARTIAL-PATCHED E###.BIN — only the three duration u16s are rewritten, every other byte
## copied verbatim from the base.
##
## COMPOSITION. `save` accepts a `base_bin_override`: the host layers this patch on TOP of the
## previous writer's output BIN (it runs after the particle-timeline saver — same section, the
## header words are disjoint from the particle channels), so every edit lands in ONE file. With
## no override it patches the pristine ROM extract.

const OUT_DIR := "res://authored_effects"
const BASE_BIN_REL := "../project-assets/fft-extract/EFFECT/%s.BIN"


## Serialize a live TimelineData into the minimal header shape the byte writer consumes:
## `{header: {phase1_duration, spawn_delay, phase2_delay}}`, read from the live vars (the
## sim's own source of truth, kept in sync by TimelineHeaderChannel). Null timeline is a hard
## error.
static func to_timeline_header_json(timeline) -> Dictionary:
	if timeline == null:
		return {"ok": false, "json": {}, "error": "no timeline data to save"}
	return {"ok": true, "json": {"header": {
		"phase1_duration": int(timeline.phase1_duration),
		"spawn_delay": int(timeline.spawn_delay),
		"phase2_delay": int(timeline.phase2_delay),
	}}, "error": ""}


## Repack the timeline-header durations of effect `effect_id` from the live `timeline` model.
## `base_bin_override` (absolute path) layers this patch onto an already-patched BIN; empty →
## patch the pristine ROM extract. Returns {ok, out_path, error}; never raises — a missing
## base / header / adapter refusal / failed writer is a reported error.
static func save(effect_id: int, timeline, base_bin_override: String = "") -> Dictionary:
	var eff := "E%03d" % effect_id

	var adapted: Dictionary = to_timeline_header_json(timeline)
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
	var timeline_res := "%s/%s.timeline_header.json" % [OUT_DIR, eff]
	var tf := FileAccess.open(timeline_res, FileAccess.WRITE)
	if tf == null:
		return {"ok": false, "out_path": "", "error": "cannot write %s" % timeline_res}
	tf.store_string(JSON.stringify(adapted["json"]))
	tf.close()

	var out_bin_res := "%s/%s.BIN" % [OUT_DIR, eff]
	var out_bin_abs := ProjectSettings.globalize_path(out_bin_res)

	var args := [
		"run", "--project", ProjectSettings.globalize_path("res://tools"),
		"python", ProjectSettings.globalize_path("res://tools/write_effect_timeline_header.py"),
		base_bin,
		ProjectSettings.globalize_path(timeline_res),
		ProjectSettings.globalize_path(header_res),
		out_bin_abs,
	]
	var output: Array = []
	var code := OS.execute("uv", args, output, true)
	if code != 0:
		return {"ok": false, "out_path": "",
			"error": "writer exit %d: %s" % [code, "\n".join(output)]}

	return {"ok": true, "out_path": out_bin_abs, "error": ""}
