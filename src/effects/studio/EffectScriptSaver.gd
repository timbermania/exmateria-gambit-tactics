extends RefCounted
## The script-pattern half of the Studio game→json→bin repack (#273, ADR-0094) — the
## VARIABLE-LENGTH counterpart to the fixed-size flags / timeline-header savers. Given an
## effect id and the LIVE (possibly swapped) script_ops, it serializes the target pattern into
## a minimal `{pattern}` json and shells out to the byte-exact Python writer
## (`write_effect_script.py`), which regenerates the canonical section from the base's own
## prologue, splices it in, shifts the whole tail by `delta`, and fixes the downstream header
## pointers. A non-swappable base (Custom / CODE / non-canonical) is copied through unchanged.
##
## COMPOSITION. `save` accepts a `base_bin_override` and runs LAST in the studio_save chain
## (after the flags saver) — it is the only saver that RESIZES a section, so every earlier
## fixed-offset patch is applied first and then shifted wholesale with the tail. With no
## override it rewrites the pristine ROM extract.
##
## No `class_name` (ADR-0004) — savers stay path-preloaded.

const EffectScriptPattern = preload("res://src/effects/studio/EffectScriptPattern.gd")

const OUT_DIR := "res://authored_effects"
const BASE_BIN_REL := "../project-assets/fft-extract/EFFECT/%s.BIN"


## Serialize the live script into the minimal shape the byte writer consumes: `{pattern}` —
## the detected target pattern of the (possibly swapped) root ops. An empty script_ops (or a
## Custom pattern) is a hard error — nothing to repack. The writer itself is authoritative on
## whether the BASE is swappable; this only says which pattern the author wants.
static func to_script_json(script_ops: Array) -> Dictionary:
	if script_ops == null or script_ops.is_empty():
		return {"ok": false, "json": {}, "error": "no script data to save"}
	var pattern := EffectScriptPattern.detect(script_ops)
	if pattern == EffectScriptPattern.P_CUSTOM:
		return {"ok": false, "json": {}, "error": "Custom script is not swappable"}
	return {"ok": true, "json": {"pattern": pattern}, "error": ""}


## Repack the script section of effect `effect_id` to the live pattern. `base_bin_override`
## (absolute path) layers this rewrite onto an already-patched BIN; empty → rewrite the pristine
## ROM extract. Returns {ok, out_path, error}; never raises.
static func save(effect_id: int, script_ops: Array, base_bin_override: String = "") -> Dictionary:
	var eff := "E%03d" % effect_id

	var adapted: Dictionary = to_script_json(script_ops)
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
	var script_res := "%s/%s.script.json" % [OUT_DIR, eff]
	var sf := FileAccess.open(script_res, FileAccess.WRITE)
	if sf == null:
		return {"ok": false, "out_path": "", "error": "cannot write %s" % script_res}
	sf.store_string(JSON.stringify(adapted["json"]))
	sf.close()

	var out_bin_res := "%s/%s.BIN" % [OUT_DIR, eff]
	var out_bin_abs := ProjectSettings.globalize_path(out_bin_res)

	var args := [
		"run", "--project", ProjectSettings.globalize_path("res://tools"),
		"python", ProjectSettings.globalize_path("res://tools/write_effect_script.py"),
		base_bin,
		ProjectSettings.globalize_path(script_res),
		ProjectSettings.globalize_path(header_res),
		out_bin_abs,
	]
	var output: Array = []
	var code := OS.execute("uv", args, output, true)
	if code != 0:
		return {"ok": false, "out_path": "",
			"error": "writer exit %d: %s" % [code, "\n".join(output)]}

	return {"ok": true, "out_path": out_bin_abs, "error": ""}
