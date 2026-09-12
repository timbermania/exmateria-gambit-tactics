class_name EffectScreenSaver
extends RefCounted
## The game→json→bin disk repack (#255 Option B). Given an effect id and the edited
## screen model as a screen.json dict (ScreenData.to_json), it writes the screen.json to
## a dedicated output dir and shells out to the byte-exact Python writer to produce a
## PARTIAL-PATCHED E###.BIN — only the screen section is rewritten; every other byte is
## copied verbatim from the pristine ROM-extract base. This is the first brick of the
## eventual full from-scratch rebuild (see CONTEXT "Authoring model"); as more channels
## gain writers, the base's role shrinks.
##
## The pristine extract (project-assets/fft-extract/EFFECT/E###.BIN) is READ-ONLY here —
## output goes to res://authored_effects/, never clobbering the source.
##
## THE SHAPE BRIDGE (ADR-0087, mirrors EffectPaletteSaver). The writer writes a FIXED 33
## keyframe slots per channel (the disk layout); the live model after edits is a
## variable-length keyframe list (boundary trades re-time, insert/delete change the count) —
## fed straight to the writer it silently truncates on 34 slots and crashes on 32.
## `to_screen_json` pads each live channel up to 33 slots — dead trailing slots zeroed — and
## refuses a channel whose USED keyframes exceed the 33 native slots.

# The fixed on-disk keyframe slot count per screen channel (parse_effect.MAX_SCREEN_KEYFRAMES).
const MAX_SCREEN_KEYFRAMES := 33
# Output lives beside the project (gitignore-able), never in the ROM extract.
const OUT_DIR := "res://authored_effects"
# The ROM extract, a sibling of the Godot project (project-assets symlink at repo root).
const BASE_BIN_REL := "../project-assets/fft-extract/EFFECT/%s.BIN"


## Serialize a live ScreenData into the FIXED 33-slot screen.json shape the byte writer
## consumes. Returns {ok, json, error}. Each present channel is padded up to 33 keyframes with
## zeroed trailing slots; max_keyframe is carried verbatim. A channel with a USED keyframe past
## slot 33 → {ok:false} with a reason (the ROM has no slot). Absent contexts are omitted (the
## writer then leaves their base bytes untouched).
static func to_screen_json(screen) -> Dictionary:
	if screen == null:
		return {"ok": false, "json": {}, "error": "no screen data to save"}

	var out := {}
	for context in screen.channels_by_context.keys():
		var ch = screen.channels_by_context[context]
		if ch == null:
			continue
		var live: int = ch.keyframes.size()
		if _used_past_slots(ch):
			return {"ok": false, "json": {},
				"error": "screen %s has %d keyframes, over the %d native slots"
					% [context, live, MAX_SCREEN_KEYFRAMES]}
		var kfs: Array = []
		for i in range(MAX_SCREEN_KEYFRAMES):
			kfs.append(ch.keyframes[i].to_json() if i < live else _zero_kf(i))
		out[context] = {"context": context, "max_keyframe": int(ch.max_keyframe), "keyframes": kfs}

	return {"ok": true, "json": out, "error": ""}


## True when a channel would lose a USED keyframe on truncation to the 33 native slots — a live
## keyframe at index ≥ 33 with a non-trivial payload (a real tween, not zero padding).
static func _used_past_slots(ch) -> bool:
	for i in range(MAX_SCREEN_KEYFRAMES, ch.keyframes.size()):
		var kf = ch.keyframes[i]
		if int(kf.time_value) != 0 or int(kf.ctrl) != 0 \
				or int(kf.start_r_raw) != 0 or int(kf.start_g_raw) != 0 or int(kf.start_b_raw) != 0 \
				or int(kf.end_r_raw) != 0 or int(kf.end_g_raw) != 0 or int(kf.end_b_raw) != 0:
			return true
	return false


## A fully zeroed dead slot (past the used window — the runtime never reads it), carrying the
## full raw key set the writer's flat-field fallback requires.
static func _zero_kf(i: int) -> Dictionary:
	return {"index": i, "time_value": 0, "duration_frames": 1,
		"start_r": 0, "start_g": 0, "start_b": 0,
		"end_r": 0, "end_g": 0, "end_b": 0,
		"ctrl": 0, "mode": "FADE", "blend_mode": 0}


## Repack the screen section of effect `effect_id` from the live `screen` model (ScreenData).
## Returns {ok, out_path, error}. Never raises — a missing base BIN / adapter refusal /
## failed writer is a reported error, not a crash.
static func save(effect_id: int, screen) -> Dictionary:
	var eff := "E%03d" % effect_id

	var adapted: Dictionary = to_screen_json(screen)
	if not adapted.get("ok", false):
		return {"ok": false, "out_path": "", "error": adapted.get("error", "adapter failed")}
	var screen_json: Dictionary = adapted["json"]

	var header_res := "res://assets/effects/%s/header.json" % eff
	if not FileAccess.file_exists(header_res):
		return {"ok": false, "out_path": "", "error": "no header.json for %s" % eff}

	var base_bin := ProjectSettings.globalize_path("res://").path_join(BASE_BIN_REL % eff).simplify_path()
	if not FileAccess.file_exists(base_bin):
		return {"ok": false, "out_path": "",
			"error": "base %s.BIN not found (ROM extract absent at %s)" % [eff, base_bin]}

	# Write the edited screen.json into the output dir (the game→json half).
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var screen_res := "%s/%s.screen.json" % [OUT_DIR, eff]
	var sf := FileAccess.open(screen_res, FileAccess.WRITE)
	if sf == null:
		return {"ok": false, "out_path": "", "error": "cannot write %s" % screen_res}
	sf.store_string(JSON.stringify(screen_json))
	sf.close()

	var out_bin_res := "%s/%s.BIN" % [OUT_DIR, eff]

	# json→bin: hand the base BIN + edited screen.json + header to the byte-exact writer.
	var args := [
		"run", "--project", ProjectSettings.globalize_path("res://tools"),
		"python", ProjectSettings.globalize_path("res://tools/write_effect_screen.py"),
		base_bin,
		ProjectSettings.globalize_path(screen_res),
		ProjectSettings.globalize_path(header_res),
		ProjectSettings.globalize_path(out_bin_res),
	]
	var output: Array = []
	var code := OS.execute("uv", args, output, true)
	if code != 0:
		return {"ok": false, "out_path": "",
			"error": "writer exit %d: %s" % [code, "\n".join(output)]}

	return {"ok": true, "out_path": ProjectSettings.globalize_path(out_bin_res), "error": ""}
