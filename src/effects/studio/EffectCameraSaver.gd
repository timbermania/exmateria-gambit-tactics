class_name EffectCameraSaver
extends RefCounted
## The camera half of the Studio game→json→bin repack, the counterpart to
## EffectScreenSaver. Given an effect id and the LIVE (possibly edited) CameraData,
## it serializes the camera into the fixed native-slot `camera.json` shape and shells
## out to the byte-exact Python writer (`write_effect_camera.py`) to produce a
## PARTIAL-PATCHED E###.BIN — only the three camera SoA tables are rewritten, every
## other byte copied verbatim from the base. This closes the Save gap: before it,
## `studio_save` persisted only the screen section and silently dropped camera edits.
##
## THE SHAPE BRIDGE (the crux). The live model after any edit is a VARIABLE-length
## coalesced PhaseTable (CameraLowering.lower): `keyframes.size()` == the live group
## count, `max_keyframe` == that watermark. The writer is the inverse of
## `parse_camera_keyframes`, which reads FIXED native slots (phase1=21 / for_each=17
## / phase2=21) and indexes `keyframes[i]` for EVERY slot. `to_camera_json` pads each
## live table up to its native count — dead trailing slots (past the watermark) zeroed —
## and carries `max_keyframe` verbatim. An over-capacity table (more live keyframes than
## native slots) cannot be section-written to the ROM's fixed slots and is REFUSED
## (ADR-0086: capacity is post-compile, Free-only — not a disk artifact).
##
## COMPOSITION. `save` accepts a `base_bin_override`: the host layers the camera patch
## on TOP of the screen writer's output BIN (not the pristine extract) so both channels'
## edits land in ONE file. With no override it patches the pristine ROM extract.

const CameraLoweringClass = preload("res://src/effects/studio/CameraLowering.gd")

# Output lives beside the project (gitignore-able), never in the ROM extract.
const OUT_DIR := "res://authored_effects"
# The ROM extract, a sibling of the Godot project (project-assets symlink at repo root).
const BASE_BIN_REL := "../project-assets/fft-extract/EFFECT/%s.BIN"
# The three phase tables, in the writer's expected order.
const PHASES := ["phase1", "for_each", "phase2"]


## Serialize a live CameraData into the FIXED native-slot camera.json shape the byte
## writer consumes. Returns {ok, json, error}. Each present phase table is padded up to
## its native slot count with zeroed trailing keyframes; `max_keyframe` is carried
## verbatim. Over-capacity (live keyframes > native slots) → {ok:false} with a reason,
## because the ROM has no slot to hold the overflow (ADR-0086 Faithful capacity). Absent
## tables are omitted (the writer then leaves their base bytes untouched).
static func to_camera_json(camera) -> Dictionary:
	if camera == null:
		return {"ok": false, "json": {}, "error": "no camera data to save"}

	var out := {}
	for phase in PHASES:
		var table = camera.get_table(phase)
		if table == null:
			continue
		var count: int = int(CameraLoweringClass.NATIVE_SLOTS.get(phase, 21))
		var live: int = table.keyframes.size()

		var cap: Dictionary = CameraLoweringClass.capacity_faithful(live, phase)
		if not cap.get("ok", true):
			return {"ok": false, "json": {}, "error": cap.get("reason", "over capacity")}

		var kfs: Array = []
		for i in range(count):
			if i < live:
				kfs.append(_kf_to_dict(table.keyframes[i]))
			else:
				kfs.append(_zero_kf())
		out[phase] = {"max_keyframe": int(table.max_keyframe), "keyframes": kfs}

	return {"ok": true, "json": out, "error": ""}


## One live CameraData.Keyframe → the writer's flat raw dict (authoritative fields
## only: end_frame + the three s16 vecs + command_raw; decoded siblings are derived
## and the writer ignores them).
static func _kf_to_dict(kf) -> Dictionary:
	return {
		"end_frame": int(kf.end_frame),
		"angle": [int(kf.angle.x), int(kf.angle.y), int(kf.angle.z)],
		"position": [int(kf.position.x), int(kf.position.y), int(kf.position.z)],
		"zoom": [int(kf.zoom.x), int(kf.zoom.y), int(kf.zoom.z)],
		"command_raw": int(kf.command_raw),
	}


## A fully zeroed dead slot (past the watermark — the runtime never reads it).
static func _zero_kf() -> Dictionary:
	return {
		"end_frame": 0, "angle": [0, 0, 0], "position": [0, 0, 0],
		"zoom": [0, 0, 0], "command_raw": 0,
	}


## Repack the camera section of effect `effect_id` from the live `camera` model.
## `base_bin_override` (absolute path) layers the camera patch onto an already-patched
## BIN (e.g. the screen writer's output); empty → patch the pristine ROM extract.
## Returns {ok, out_path, error}; never raises — a missing base / header / adapter
## refusal / failed writer is a reported error.
static func save(effect_id: int, camera, base_bin_override: String = "") -> Dictionary:
	var eff := "E%03d" % effect_id

	var adapted: Dictionary = to_camera_json(camera)
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

	# Write the fixed-slot camera.json into the output dir (the game→json half).
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var camera_res := "%s/%s.camera.json" % [OUT_DIR, eff]
	var cf := FileAccess.open(camera_res, FileAccess.WRITE)
	if cf == null:
		return {"ok": false, "out_path": "", "error": "cannot write %s" % camera_res}
	cf.store_string(JSON.stringify(adapted["json"]))
	cf.close()

	var out_bin_res := "%s/%s.BIN" % [OUT_DIR, eff]
	var out_bin_abs := ProjectSettings.globalize_path(out_bin_res)

	# json→bin: hand the base BIN + camera.json + header to the byte-exact writer.
	var args := [
		"run", "--project", ProjectSettings.globalize_path("res://tools"),
		"python", ProjectSettings.globalize_path("res://tools/write_effect_camera.py"),
		base_bin,
		ProjectSettings.globalize_path(camera_res),
		ProjectSettings.globalize_path(header_res),
		out_bin_abs,
	]
	var output: Array = []
	var code := OS.execute("uv", args, output, true)
	if code != 0:
		return {"ok": false, "out_path": "",
			"error": "writer exit %d: %s" % [code, "\n".join(output)]}

	return {"ok": true, "out_path": out_bin_abs, "error": ""}
