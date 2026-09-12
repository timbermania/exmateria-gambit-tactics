class_name EffectSoundSaver
extends RefCounted
## The SOUND third of the Studio game→json→bin repack (ADR-0085 amendment
## 2026-08-11, slice 4), closing this branch's three previously-unbridged save
## seams in ONE pass — TIER-1 triggers (sound.json), TIER-2 shared containers
## (sound_containers.json), TIER-3 FEDS bytes (feds.bin) — through the unified
## byte-exact Python writer (`write_effect_sound_sections.py` → the F1 registry).
##
## Template: EffectCameraSaver. The live models ARE the writers' input shapes —
## `effect_data.sound` / `.sound_containers` are the raw parsed docs the choke
## point mutates in place, and `effect_data.feds_bank.raw` is the same-size
## patched blob (SoundDefChannel) — so there is no shape bridge here, just
## presence gating: absent sections are omitted (their base bytes stay
## untouched); NOTHING present is a refusal, not a silent no-op. Over-capacity
## trigger tracks are refused by the Python writer (raise-over-cap) and surface
## as the error string.
##
## COMPOSITION. `save` accepts a `base_bin_override` so the host layers this
## patch on TOP of the screen+camera writers' output BIN — all channels' edits
## land in ONE file. With no override it patches the pristine ROM extract.

# Output lives beside the project (gitignore-able), never in the ROM extract.
const OUT_DIR := "res://authored_effects"
# The ROM extract, a sibling of the Godot project (project-assets symlink at repo root).
const BASE_BIN_REL := "../project-assets/fft-extract/EFFECT/%s.BIN"


## Repack the sound sections of effect `effect_id` from the live (possibly edited)
## `effect_data`. Returns {ok, out_path, error}; never raises.
static func save(effect_id: int, effect_data, base_bin_override: String = "") -> Dictionary:
	var eff := "E%03d" % effect_id
	if effect_data == null:
		return {"ok": false, "out_path": "", "error": "no effect data to save"}

	var has_sound: bool = effect_data.sound is Dictionary and not effect_data.sound.is_empty()
	var has_containers: bool = effect_data.sound_containers is Dictionary \
			and not effect_data.sound_containers.is_empty()
	var has_feds: bool = effect_data.feds_bank != null and not effect_data.feds_bank.raw.is_empty()
	if not (has_sound or has_containers or has_feds):
		return {"ok": false, "out_path": "", "error": "no sound sections to save"}

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

	# game→json: the live docs / bytes become the writer's inputs verbatim.
	var args := []
	if has_sound:
		var sound_res := "%s/%s.sound.json" % [OUT_DIR, eff]
		if not _write_text(sound_res, JSON.stringify(effect_data.sound)):
			return {"ok": false, "out_path": "", "error": "cannot write %s" % sound_res}
		args.append_array(["--sound", ProjectSettings.globalize_path(sound_res)])
	if has_containers:
		var cont_res := "%s/%s.sound_containers.json" % [OUT_DIR, eff]
		if not _write_text(cont_res, JSON.stringify(effect_data.sound_containers)):
			return {"ok": false, "out_path": "", "error": "cannot write %s" % cont_res}
		args.append_array(["--containers", ProjectSettings.globalize_path(cont_res)])
	if has_feds:
		var feds_res := "%s/%s.feds.bin" % [OUT_DIR, eff]
		var ff := FileAccess.open(feds_res, FileAccess.WRITE)
		if ff == null:
			return {"ok": false, "out_path": "", "error": "cannot write %s" % feds_res}
		ff.store_buffer(effect_data.feds_bank.raw)
		ff.close()
		args.append_array(["--feds", ProjectSettings.globalize_path(feds_res)])

	var out_bin_res := "%s/%s.BIN" % [OUT_DIR, eff]
	var out_bin_abs := ProjectSettings.globalize_path(out_bin_res)

	# json→bin: one unified writer call patches every present section.
	var full_args := [
		"run", "--project", ProjectSettings.globalize_path("res://tools"),
		"python", ProjectSettings.globalize_path("res://tools/write_effect_sound_sections.py"),
		base_bin,
		ProjectSettings.globalize_path(header_res),
		out_bin_abs,
	]
	full_args.append_array(args)
	var output: Array = []
	var code := OS.execute("uv", full_args, output, true)
	if code != 0:
		return {"ok": false, "out_path": "",
			"error": "writer exit %d: %s" % [code, "\n".join(output)]}

	return {"ok": true, "out_path": out_bin_abs, "error": ""}


static func _write_text(res_path: String, text: String) -> bool:
	var f := FileAccess.open(res_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true
