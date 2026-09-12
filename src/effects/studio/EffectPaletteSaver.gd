class_name EffectPaletteSaver
extends RefCounted
## The palette half of the Studio game→json→bin repack (ADR-0087) — the counterpart to
## EffectScreenSaver / EffectCameraSaver. Given an effect id and the LIVE (possibly edited)
## PaletteData, it serializes the nine palette/field-tint channels (for_each / phase1 / phase2 ×
## affected_units / caster / target) into the fixed 33-slot shape the byte-exact Python writer
## (`write_effect_palette.py`) consumes, and shells out to produce a PARTIAL-PATCHED E###.BIN —
## only the palette channels are rewritten, every other byte copied verbatim. This closes the
## palette Save gap: before it, `studio_save` persisted screen + camera and silently dropped
## palette edits.
##
## THE SHAPE BRIDGE. The writer writes a FIXED 33 keyframe slots per channel (the disk layout);
## the live model after edits is a variable-length keyframe list (boundary trades re-time,
## insert/delete change the count). `to_palette_json` pads each live channel up to 33 slots —
## dead trailing slots zeroed — and carries max_keyframe verbatim. A palette keyframe has NO
## raw sub-block: its flat fields (time_value / rgb / ctrl) ARE the disk bytes (parse_palette_
## channel reads them straight), so the adapter emits them straight. A channel whose USED
## keyframes exceed the 33 native slots is REFUSED (no ROM slot to hold the overflow).
##
## COMPOSITION. `save` accepts a `base_bin_override`: the host layers the palette patch on TOP
## of the screen+camera writers' output BIN so every channel's edits land in ONE file. With no
## override it patches the pristine ROM extract.

# The fixed on-disk keyframe slot count per palette channel (parse_effect.MAX_PALETTE_KEYFRAMES).
const MAX_PALETTE_KEYFRAMES := 33
# Output lives beside the project (gitignore-able), never in the ROM extract.
const OUT_DIR := "res://authored_effects"
# The ROM extract, a sibling of the Godot project (project-assets symlink at repo root).
const BASE_BIN_REL := "../project-assets/fft-extract/EFFECT/%s.BIN"


## Serialize a live PaletteData into the FIXED 33-slot palette.json shape the byte writer
## consumes. Returns {ok, json, error}. Each present channel is padded up to 33 keyframes with
## zeroed trailing slots; max_keyframe is carried verbatim. A channel with a USED keyframe past
## slot 33 → {ok:false} with a reason (the ROM has no slot). Absent channels are omitted (the
## writer then leaves their base bytes untouched).
static func to_palette_json(palette) -> Dictionary:
	if palette == null:
		return {"ok": false, "json": {}, "error": "no palette data to save"}

	var out := {}
	for context in palette.channels.keys():
		var ctx_channels: Dictionary = palette.channels[context]
		for channel_name in ctx_channels.keys():
			var ch = ctx_channels[channel_name]
			if ch == null:
				continue
			var live: int = ch.keyframes.size()
			if _used_past_slots(ch):
				return {"ok": false, "json": {},
					"error": "palette %s/%s has %d keyframes, over the %d native slots"
						% [context, channel_name, live, MAX_PALETTE_KEYFRAMES]}
			var kfs: Array = []
			for i in range(MAX_PALETTE_KEYFRAMES):
				kfs.append(_kf_to_dict(ch.keyframes[i]) if i < live else _zero_kf())
			if not out.has(context):
				out[context] = {}
			out[context][channel_name] = {"max_keyframe": int(ch.max_keyframe), "keyframes": kfs}

	return {"ok": true, "json": out, "error": ""}


## True when a channel would lose a USED keyframe on truncation to the 33 native slots — a live
## keyframe at index ≥ 33 with a non-trivial payload (a real tween, not zero padding).
static func _used_past_slots(ch) -> bool:
	for i in range(MAX_PALETTE_KEYFRAMES, ch.keyframes.size()):
		var kf = ch.keyframes[i]
		if int(kf.time_value) != 0 or int(kf.ctrl) != 0 or kf.rgb != Vector3i.ZERO:
			return true
	return false


## One live PaletteData.Keyframe → the writer's flat raw dict (the disk fields, straight).
static func _kf_to_dict(kf) -> Dictionary:
	return {
		"time_value": int(kf.time_value),
		"rgb": [int(kf.rgb.x), int(kf.rgb.y), int(kf.rgb.z)],
		"ctrl": int(kf.ctrl),
	}


## A fully zeroed dead slot (past the used window — the runtime never reads it).
static func _zero_kf() -> Dictionary:
	return {"time_value": 0, "rgb": [0, 0, 0], "ctrl": 0}


## Repack the palette section of effect `effect_id` from the live `palette` model.
## `base_bin_override` (absolute path) layers the palette patch onto an already-patched BIN
## (e.g. the screen+camera writers' output); empty → patch the pristine ROM extract. Returns
## {ok, out_path, error}; never raises — a missing base / header / adapter refusal / failed
## writer is a reported error.
static func save(effect_id: int, palette, base_bin_override: String = "") -> Dictionary:
	var eff := "E%03d" % effect_id

	var adapted: Dictionary = to_palette_json(palette)
	if not adapted.get("ok", false):
		return {"ok": false, "out_path": "", "error": adapted.get("error", "adapter failed")}

	var header_res := "res://assets/effects/%s/header.json" % eff
	if not FileAccess.file_exists(header_res):
		return {"ok": false, "out_path": "", "error": "no header.json for %s" % eff}

	var base_bin: String = base_bin_override
	if base_bin.is_empty():
		base_bin = ProjectSettings.globalize_path("res://").path_join(BASE_BIN_REL % eff).simplify_path()
	if not FileAccess.file_exists(base_bin):
		return {"ok": false, "out_path": "", "error": "base %s.BIN not found at %s" % [eff, base_bin]}

	# Write the fixed-slot palette.json into the output dir (the game→json half).
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var palette_res := "%s/%s.palette.json" % [OUT_DIR, eff]
	var pf := FileAccess.open(palette_res, FileAccess.WRITE)
	if pf == null:
		return {"ok": false, "out_path": "", "error": "cannot write %s" % palette_res}
	pf.store_string(JSON.stringify(adapted["json"]))
	pf.close()

	var out_bin_res := "%s/%s.BIN" % [OUT_DIR, eff]
	var out_bin_abs := ProjectSettings.globalize_path(out_bin_res)

	# json→bin: hand the base BIN + palette.json + header to the byte-exact writer.
	var args := [
		"run", "--project", ProjectSettings.globalize_path("res://tools"),
		"python", ProjectSettings.globalize_path("res://tools/write_effect_palette.py"),
		base_bin,
		ProjectSettings.globalize_path(palette_res),
		ProjectSettings.globalize_path(header_res),
		out_bin_abs,
	]
	var output: Array = []
	var code := OS.execute("uv", args, output, true)
	if code != 0:
		return {"ok": false, "out_path": "", "error": "writer exit %d: %s" % [code, "\n".join(output)]}

	return {"ok": true, "out_path": out_bin_abs, "error": ""}
