extends Node
## **A `global uniform` a project has not declared is NOT a compile error outside the
## editor, and this rig is outside the editor.** That single fact is why
## `check_addon_portability.py` arm 4's shader-global DEBT cannot be made enforcing by
## the stranger rigs, and it contradicts a sentence this package repeats in sixteen
## places. ADR-0238.
##
## 🔴 WHAT THE CORPUS SAID, AND WHERE IT CAME FROM. ADR-0169's Measurement quotes the
## engine by file and line:
##
##     `servers/rendering/shader_language.cpp:9866` in the 4.8 fork:
##     > Global uniform '%s' does not exist. Create it in Project Settings.
##
## The string is real and the quote is accurate. The **enclosing `if` four lines above
## it is not in the quote**, and it is the whole story:
##
##     if (uniform_scope == ShaderNode::Uniform::SCOPE_GLOBAL &&
##             Engine::get_singleton()->is_editor_hint()) {
##         // Type checking for global uniforms is not allowed outside the editor.
##
## So the validation is **editor-only, by the engine's own comment**. ADR-0169 dec. 4
## read the error and not its gate, and every later restatement inherited it — arm 4's
## own heading, `addons/exmateria_platform/{README.md,plugin.gd}`, four `.gdshaderinc`
## headers, `addons/exmateria_battlefield/README.md`, ADR-0190 and ADR-0220 dec. 1.
##
## 🔴 THE CONCLUSION SURVIVES; ONLY THE MECHANISM IS WRONG, AND THE TRUTH IS WORSE.
## Nothing here argues that an addon may stop providing its `[shader_globals]` entries.
## ADR-0220 dec. 1, arms 4b/4c, `PROVIDED_GLOBALS` and `PlatformProvidesTest` are all
## correct and all stay. What changes is the FAILURE MODE, and it changes in the
## direction nobody wants: a compile error is loud and fails at install, while what
## actually happens is that the shader compiles clean, exposes its uniforms, draws, and
## reads the missing global at its type's zero-default. Measured on both engines: the
## only report is a DRAW-time warning from `update_uniform_buffer`, *"Shader uses global
## parameter 'X', but it was removed at some point. Material will not display
## correctly."* ADR-0203 dec. 7 already knew what that costs — a `pixel_aspect` of 0.0
## collapses every vertex's clip-space x and the screen goes blank — and that sentence
## never reached the fifteen places that kept saying COMPILE.
##
## WHY THIS SCENE IS RIG-OWNED AND NOT ADDON-OWNED. The claim is only true in a project
## that declares NO `[shader_globals]`, and `godot-learning/project.godot` declares
## seven. An addon-owned test would be falsified by its own host. That is ADR-0194
## dec. 4 read in the other direction, the same argument `rig.sh` makes for the sprite
## rig's rig-owned arm.
##
## 🔴 IT GOES RED ON GOOD NEWS, which is `stranger_fork_absent.gd`'s shape and the
## reason it is worth running. If a future engine validates global uniforms outside the
## editor, arm 2 below flips to ABSENT and this scene fails — and the correct response
## is not to fix the scene, it is to go make arm 4 ENFORCING, because the rigs would at
## last be able to see the debt they are currently blind to.
##
## Run by `tests/stranger/shared/rig.sh` as a rig-owned scene.

## The uniform the probe declares AFTER the subject. A shader that fails to compile
## exposes no uniforms at all, so the witness being PRESENT is the compile succeeding.
## Same witness idiom as `stranger_install._test_every_shader_include_compiles`, and it
## is a live control here rather than an assumption: arm 1 is a shader that genuinely
## does not compile, and the witness must vanish for it.
const WITNESS := "_rig_global_uniform_witness"

## A name no `project.godot` in this repo declares and no addon file mentions. Spelled
## to be greppable: if this string ever appears in a `[shader_globals]` block the arm
## below is measuring nothing, which is what arm 0 exists to catch.
const UNDECLARED := "zzz_global_no_project_declares_this"

## 🔴 THE SEAMS ARE DERIVED, AND THIS SCENE MAY NOT SPELL ITS SUBJECT'S PATH.
## `tests/stranger/README.md` states the rule and gives two reasons; the first is this
## family's own thesis — a guard that hardcodes its subject's directory breaks the day
## the subject moves, which is the single event these rigs exist to survive. So the
## addon root comes from `application/config/name` the way
## `shared/stranger_install.gd:_subject()` does, and the seam list is every
## `.gdshaderinc` under it that actually declares a `global uniform`. A hand-written
## list would also be a third register beside `plugin.gd`'s `PROVIDED_GLOBALS` and arm
## 4's own scan, and this package has been bitten by a guard whose subject went stale
## while the guard stayed green.
var _addon: String = ""
var _seams: PackedStringArray = PackedStringArray()

var _passed: int = 0
var _failed: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)


func _compiles(code: String) -> bool:
	"""True when the shader compiled — witnessed by its uniforms being reachable."""
	var sh := Shader.new()
	sh.code = code
	for u in sh.get_shader_uniform_list(true):
		if str(u.get("name", "")) == WITNESS:
			return true
	return false


func _ready() -> void:
	_addon = _subject()
	if _addon == "":
		print("0 passed, 1 failed")
		print("[FAIL] the rig did not name a staged addon — nothing was measured")
		get_tree().quit()
		return
	_seams = _seams_declaring_a_global()
	print("[ok] subject: %s   seams declaring a `global uniform`: %d"
		% [_addon, _seams.size()])
	_test_the_project_declares_no_shader_globals()
	_test_a_broken_shader_does_not_compile()
	_test_an_undeclared_global_uniform_compiles_anyway()
	_test_the_addons_own_seams_compile_unprovided()

	if _passed == 0:
		print("[FAIL] ran zero assertions — nothing was checked, which is not a pass")
		_failed += 1
	print("%d passed, %d failed" % [_passed, _failed])
	if _failed == 0:
		print("[PASS] a `global uniform` is validated ONLY in the editor "
			+ "(shader_language.cpp, `is_editor_hint()`), so this rig cannot see arm 4's "
			+ "shader-global debt and the debt is SILENT rather than a compile error "
			+ "(ADR-0238)")
	else:
		print("[FAIL] the engine's global-uniform behaviour is not what ADR-0238 measured")
	get_tree().quit()


func _test_the_project_declares_no_shader_globals() -> void:
	"""ANTI-VACUITY, and it is the arm the rest of the scene rests on. Every claim below
	is *"…in a project that declares no `[shader_globals]`"*. The day somebody adds one
	to this rig's `project.godot` to make something else pass, the arms stop measuring
	what they say and would keep printing green."""
	_check(not Engine.is_editor_hint(),
		"this scene is running with `is_editor_hint()` TRUE — the engine's validation "
		+ "gate is OPEN here, so nothing below is a statement about a shipped game")
	var declared := _declared_globals()
	_check(declared.size() > 0,
		"read ZERO `global uniform` declarations out of the addon's seams — the scan "
		+ "below is broken or the seams moved, and the next arm would pass vacuously")
	for gname in declared:
		_check(not ProjectSettings.has_setting("shader_globals/" + gname),
			("this rig's project.godot declares shader_globals/%s — the arms below "
			+ "would then be measuring a DECLARED global and prove nothing") % gname)
	_check(not ProjectSettings.has_setting("shader_globals/%s" % UNDECLARED),
		"shader_globals/%s exists, which it must not — pick another name" % UNDECLARED)


func _subject() -> String:
	"""`stranger_<addon>` -> `res://addons/<addon>`, and a name that does not resolve to
	a staged directory is a FAILURE and not a skip — otherwise this scene asserts
	nothing about nothing and prints [PASS]. `stranger_install.gd`'s argument."""
	var pname := str(ProjectSettings.get_setting("application/config/name", ""))
	if not pname.begins_with("stranger_"):
		return ""
	var path := "res://addons/%s" % pname.substr(9)
	if DirAccess.open(path) == null:
		return ""
	return path


func _walk(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var path := "%s/%s" % [dir, entry]
		if d.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_walk(path))
		else:
			out.append(path)
		entry = d.get_next()
	d.list_dir_end()
	var sorted := Array(out)
	sorted.sort()
	return PackedStringArray(sorted)


func _seams_declaring_a_global() -> PackedStringArray:
	"""Every `.gdshaderinc` under the subject that declares a `global uniform` — which
	is exactly arm 4's DECLARES side, read off the same source arm 4 reads."""
	var out := PackedStringArray()
	for f in _walk(_addon):
		if f.get_extension() != "gdshaderinc":
			continue
		for line in FileAccess.get_file_as_string(f).split("\n"):
			if line.strip_edges().begins_with("global uniform "):
				out.append(f)
				break
	return out


func _declared_globals() -> PackedStringArray:
	"""The `global uniform` names the addon actually declares, READ OFF THE SOURCE.
	A hand-written list here would be a second register beside `plugin.gd`'s
	`PROVIDED_GLOBALS`, and `PlatformProvidesTest` already makes the point that the
	honest oracle reads the declarations rather than restating them."""
	var out := PackedStringArray()
	for seam in _seams:
		for line in FileAccess.get_file_as_string(seam).split("\n"):
			var t := line.strip_edges()
			if t.begins_with("global uniform "):
				var parts := t.substr(15).replace(";", " ").split(" ", false)
				if parts.size() >= 2:
					out.append(parts[1])
	return out


func _test_a_broken_shader_does_not_compile() -> void:
	"""THE LIVE CONTROL. Without it the next two arms pass on a witness that never had
	the power to fail, which is the shape of every expired control this package has
	found. This one throws a SHADER ERROR on purpose, and that is safe for a reason
	worth stating rather than relying on: `rig.sh`'s unexplained-throw filter greps for
	`SCRIPT ERROR`, and a shader that fails to compile emits `SHADER ERROR`. Different
	strings. This rig declares no `known_failures.tsv` and needs none."""
	_check(not _compiles("shader_type canvas_item;\nuniform float %s;\n"
			% WITNESS + "@@@ this is not glsl @@@\nvoid fragment() { COLOR = vec4(1.0); }\n"),
		"a shader with a deliberate syntax error reported as COMPILING — the witness "
		+ "used by every arm here cannot detect a compile failure, so this whole scene "
		+ "is vacuous and so is stranger_install's shader-include arm")


func _test_an_undeclared_global_uniform_compiles_anyway() -> void:
	"""THE FINDING, in its smallest form: a name nothing anywhere declares."""
	_check(_compiles("shader_type canvas_item;\nglobal uniform float %s;\n"
			% UNDECLARED + "uniform float %s;\n" % WITNESS
			+ "void fragment() { COLOR = vec4(%s); }\n" % UNDECLARED),
		"a `global uniform` NO project declares failed to compile outside the editor. "
		+ "That is the behaviour ADR-0169 dec. 4 described and ADR-0238 measured as "
		+ "editor-only — if it is true again, arm 4's debt is now visible to this rig "
		+ "and check_addon_portability.py should be made ENFORCING (ADR-0238 dec. 4)")


func _test_the_addons_own_seams_compile_unprovided() -> void:
	"""ARM 4's ACTUAL SUBJECT, in ARM 4's actual shape. `stranger_install.gd` already
	compiles these five seams and passes; this arm says the part that matters, which is
	that passing there is NOT evidence the `[shader_globals]` entries are present. Same
	files, same result, opposite conclusion — and only one of the two is written down
	anywhere."""
	_check(_seams.size() > 0,
		"no .gdshaderinc under the subject declares a `global uniform` — either the addon "
		+ "stopped declaring any (in which case arm 4's debt for it is gone and this scene "
		+ "has no subject) or the walk is broken; both are reportable, neither is a pass")
	for seam in _seams:
		# Two shader types and a bare body, for `stranger_install`'s reason: a seam is
		# written for the shader types it is written for, and one that brings its own
		# entry points fails a probe that supplies another.
		var ok := false
		for st in ["canvas_item", "spatial"]:
			var tail := "void fragment() { %s }" % (
				"COLOR = vec4(1.0);" if st == "canvas_item" else "ALBEDO = vec3(1.0);")
			for body in [tail, ""]:
				if _compiles("shader_type %s;\n#include \"%s\"\nuniform float %s;\n%s\n"
						% [st, seam, WITNESS, body]):
					ok = true
					break
			if ok:
				break
		_check(ok, "#include \"%s\" did not compile here. If the reason is its `global "
			% seam + "uniform`, arm 4 just became enforceable by this rig — see ADR-0238")
