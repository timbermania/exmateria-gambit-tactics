extends Node

## B3 / ADR-0222 Q1 — CAN `unit.tres` SHIP WITHOUT ITS `shader =` LINE?
##
## The last production row in criterion 4 is `assets/materials/unit.tres` naming
## `render/unit.gdshader` as an `ext_resource`. Q1 rules that it drains by INJECTING the
## shader the way `for_variant` already injects the base — but only if the injection is
## measurably lossless, because the authored file carries THIRTY-NINE
## `shader_parameter/*` entries and `[resource]` properties are assigned in FILE ORDER,
## so `shader =` currently lands before all of them.
##
## Two halves, both of which must hold:
##
##   (a) LOAD — a shader-less `.tres` must come back carrying all 39 values, and setting
##       the shader afterwards must bind them. If `ShaderMaterial` drops a
##       `shader_parameter/x` set while it has no shader to validate against, the
##       injection silently zeroes the atlas sizes and the calibrated brightness.
##
##   (b) RE-SAVE — `ShaderMaterial::_get_property_list` enumerates the uniforms the
##       CURRENT shader declares. Saving the resource while it is shader-less may write
##       back NONE of the 39, silently, so the next person who touches the file in the
##       editor empties it.
##
## If either half fails the answer is not to force it: the path gets a `DECLARED_MOUNTS`
## entry with the measured reason, and ADR-0222's Prediction section records the
## falsification.
##
## Both paths come in on the command line — `tools/` is inside `check_lattice_scene.py`'s
## corpus and a literal `res://addons/…` here would ADD a criterion-4 site to the very
## register this pass is draining (ADR-0208 dec. 7 scores comments too).
##
##     godot --path . res://tools/probe_unitres_shader_drain.tscn -- \
##         --base=res://assets/materials/unit.tres --shader=res://…/unit.gdshader
##
## Every line is prefixed `[drain]`.

const COPY := "user://probe_unitres_noshader.tres"
const ROUND := "user://probe_unitres_roundtrip.tres"


func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2 and kv[0].lstrip("-") == name:
			return kv[1]
	return ""


## `get_shader_parameter` hands back Variants of four different shapes here. Compare them
## as STRINGS so a `PackedVector2Array` of 20 zeros and a `Texture2D` reference are held to
## the same standard, and so a mismatch prints something a human can read.
func _spell(v: Variant) -> String:
	if v is Resource:
		var r: Resource = v
		return "%s(%s)" % [r.get_class(), r.resource_path]
	return var_to_str(v)


func _ready() -> void:
	var base := _arg("base")
	var shader_path := _arg("shader")
	if base == "" or shader_path == "":
		print("[drain] need --base= and --shader=")
		get_tree().quit(1)
		return

	# --- the authored file, as the control -------------------------------------------
	var text := FileAccess.get_file_as_string(base)
	if text == "":
		print("[drain] %s is empty or unreadable" % base)
		get_tree().quit(1)
		return
	var authored := PackedStringArray()
	for line in text.split("\n"):
		if line.begins_with("shader_parameter/"):
			authored.append(line.split(" = ")[0].substr("shader_parameter/".length()))
	print("[drain] authored keys: %d" % authored.size())

	var orig := load(base) as ShaderMaterial
	if orig == null:
		print("[drain] the authored file does not load as a ShaderMaterial")
		get_tree().quit(1)
		return
	var want := {}
	for k in authored:
		want[k] = _spell(orig.get_shader_parameter(k))
	print("[drain] control: shader=%s  params read back=%d" % [
		"null" if orig.shader == null else str(orig.shader.resource_path), want.size()])

	# --- the shader-less copy ----------------------------------------------------------
	# The `uid=` goes with the `shader =` line: two resources claiming one uid is a
	# different experiment than the one being run.
	var out := PackedStringArray()
	for line in text.split("\n"):
		if line.begins_with("shader = ExtResource"):
			continue
		if line.begins_with("[ext_resource type=\"Shader\""):
			continue
		if line.begins_with("[gd_resource "):
			line = line.replace("load_steps=5", "load_steps=4")
			var uid_at := line.find(" uid=\"")
			if uid_at != -1:
				line = line.substr(0, uid_at) + "]"
		out.append(line)
	var f := FileAccess.open(COPY, FileAccess.WRITE)
	if f == null:
		print("[drain] cannot write %s" % COPY)
		get_tree().quit(1)
		return
	f.store_string("\n".join(out))
	f.close()

	# --- (a) LOAD ----------------------------------------------------------------------
	var m := ResourceLoader.load(COPY, "ShaderMaterial", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	if m == null:
		print("[drain] (a) FAIL — the shader-less .tres does not load as a ShaderMaterial")
		get_tree().quit(1)
		return
	print("[drain] (a) loaded shader-less: shader=%s" % ["null" if m.shader == null else "SET"])

	var before_bad := 0
	for k in authored:
		if _spell(m.get_shader_parameter(k)) != want[k]:
			before_bad += 1
			if before_bad <= 5:
				print("[drain] (a)   pre-inject differs: %s  want=%s got=%s" % [
					k, want[k], _spell(m.get_shader_parameter(k))])
	print("[drain] (a) BEFORE injecting the shader: %d of %d differ from the control"
			% [before_bad, authored.size()])

	var sh := load(shader_path) as Shader
	if sh == null:
		print("[drain] cannot load the shader at %s" % shader_path)
		get_tree().quit(1)
		return
	m.shader = sh

	var after_bad := 0
	for k in authored:
		if _spell(m.get_shader_parameter(k)) != want[k]:
			after_bad += 1
			if after_bad <= 8:
				print("[drain] (a)   AFTER differs: %s  want=%s got=%s" % [
					k, want[k], _spell(m.get_shader_parameter(k))])
	print("[drain] (a) AFTER injecting the shader: %d of %d differ  -> %s"
			% [after_bad, authored.size(), "PASS" if after_bad == 0 else "FAIL"])

	# --- (b) RE-SAVE -------------------------------------------------------------------
	# Save the copy while it is still shader-less. `_get_property_list` walks the current
	# shader's uniforms, so this is where the 39 would vanish without a word.
	var m2 := ResourceLoader.load(COPY, "ShaderMaterial", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	var listed := 0
	for p in m2.get_property_list():
		if str(p.get("name", "")).begins_with("shader_parameter/"):
			listed += 1
	print("[drain] (b) get_property_list() on the shader-less material: %d shader_parameter entries"
			% listed)
	var rc := ResourceSaver.save(m2, ROUND)
	if rc != OK:
		print("[drain] (b) ResourceSaver.save() rc=%d" % rc)
		get_tree().quit(1)
		return
	var back := FileAccess.get_file_as_string(ROUND)
	var kept := 0
	for line in back.split("\n"):
		if line.begins_with("shader_parameter/"):
			kept += 1
	print("[drain] (b) round-tripped file keeps %d of %d shader_parameter lines  -> %s"
			% [kept, authored.size(), "PASS" if kept == authored.size() else "FAIL"])

	print("[drain] VERDICT: (a) %s  (b) %s" % [
		"PASS" if after_bad == 0 else "FAIL",
		"PASS" if kept == authored.size() else "FAIL"])
	get_tree().quit(0 if (after_bad == 0 and kept == authored.size()) else 1)
