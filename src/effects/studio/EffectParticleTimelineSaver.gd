class_name EffectParticleTimelineSaver
extends RefCounted
## The particle-timeline half of the Studio game→json→bin repack (ADR-0089 particle_timeline
## amendment) — the counterpart to EffectCameraSaver / EffectScreenSaver. Given an effect id and
## the LIVE (possibly edited) TimelineData, it serializes the 15 particle channels into the
## fixed 25-slot timeline.json shape and shells out to the byte-exact Python writer
## (`write_effect_particle_timeline.py`) to produce a PARTIAL-PATCHED E###.BIN — only the
## particle channels are rewritten, every other byte copied verbatim from the base.
##
## THE SHAPE BRIDGE. The parser reads FIXED native 25-slot channels and indexes `keyframes[i]`
## for EVERY slot; the live model after Add/Delete is a VARIABLE-length array with a
## `max_keyframe` watermark. `to_timeline_json` pads each channel up to 25 slots (dead trailing
## slots zeroed) and carries `max_keyframe` verbatim. A DISABLED span saves as `emitter_id 0`
## (the ROM's only "off") — its session-remembered id is never serialized, so a saved-disabled
## span reloads as an ordinary gap (the deliberate tier-below-colour behaviour).
##
## COMPOSITION. `save` accepts a `base_bin_override`: the host layers the particle patch on TOP
## of the previous writer's output BIN so every channel's edits land in ONE file. With no
## override it patches the pristine ROM extract.

const PARTICLE_SLOTS := 25
const OUT_DIR := "res://authored_effects"
const BASE_BIN_REL := "../project-assets/fft-extract/EFFECT/%s.BIN"
const CONTEXTS := ["for_each", "phase1", "phase2"]


## Serialize a live TimelineData into the fixed 25-slot timeline.json shape the byte writer
## consumes. Returns {ok, json, error}. Every channel is padded up to 25 slots with zeroed
## trailing keyframes; `max_keyframe` is carried verbatim. A null timeline is a hard error.
static func to_timeline_json(timeline) -> Dictionary:
	if timeline == null:
		return {"ok": false, "json": {}, "error": "no timeline data to save"}
	var channels: Array = []
	for context in CONTEXTS:
		for ch in timeline.get_channels(context):
			channels.append(_channel_to_dict(ch))
	return {"ok": true, "json": {"particle_channels": channels}, "error": ""}


## One live TimelineData.Channel → the writer's fixed 25-slot dict. Slots past the live array
## are zeroed (dead — the runtime never reads past max_keyframe). remembered_emitter_id is NOT
## serialized (disable is session-only).
static func _channel_to_dict(ch) -> Dictionary:
	var kfs: Array = []
	for i in range(PARTICLE_SLOTS):
		if i < ch.keyframes.size():
			var kf = ch.keyframes[i]
			kfs.append({"time": int(kf.time), "emitter_id": int(kf.emitter_id),
				"action_flags": int(kf.action_flags)})
		else:
			kfs.append({"time": 0, "emitter_id": 0, "action_flags": 0})
	return {
		"context": ch.context,
		"channel_index": int(ch.channel_index),
		"max_keyframe": int(ch.max_keyframe),
		"keyframes": kfs,
	}


## Repack the particle-timeline of effect `effect_id` from the live `timeline` model.
## `base_bin_override` (absolute path) layers this patch onto an already-patched BIN; empty →
## patch the pristine ROM extract. Returns {ok, out_path, error}; never raises — a missing
## base / header / adapter refusal / failed writer is a reported error.
static func save(effect_id: int, timeline, base_bin_override: String = "") -> Dictionary:
	var eff := "E%03d" % effect_id

	var adapted: Dictionary = to_timeline_json(timeline)
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
	var timeline_res := "%s/%s.particle.json" % [OUT_DIR, eff]
	var tf := FileAccess.open(timeline_res, FileAccess.WRITE)
	if tf == null:
		return {"ok": false, "out_path": "", "error": "cannot write %s" % timeline_res}
	tf.store_string(JSON.stringify(adapted["json"]))
	tf.close()

	var out_bin_res := "%s/%s.BIN" % [OUT_DIR, eff]
	var out_bin_abs := ProjectSettings.globalize_path(out_bin_res)

	var args := [
		"run", "--project", ProjectSettings.globalize_path("res://tools"),
		"python", ProjectSettings.globalize_path("res://tools/write_effect_particle_timeline.py"),
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
