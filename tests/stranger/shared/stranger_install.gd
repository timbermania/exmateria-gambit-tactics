extends Node
## ADR-0194's baseline arm, for whichever addon the rig staged: **this addon works
## in a project that did nothing for it.** It is the claim dec. 5 says a source-copy rig buys,
## and it is deliberately weaker than `stranger_sound`'s — that rig stages the
## PUBLISHED tree and can therefore say *"this addon installs the way the ZIP
## installs"*. `exmateria_schema` has no publication, so writing a manifest for it
## would assert one that does not exist (dec. 5/6). The rig prints which of the two
## it is measuring on every run rather than letting a reader assume the stronger.
##
## EVERY LIST HERE IS DERIVED FROM THE TREE. There is no hardcoded roster of class
## names or files: the addon's members are whatever is in `addons/exmateria_schema/`
## on the day the rig runs. A hardcoded list is a second membership register beside
## the one `docs/adr/0139` already owns, and this repo has been bitten by a guard
## whose subject went stale while the guard stayed green.
##
## ONE IMPLEMENTATION, NOT ONE PER RIG. The subject comes from the staged project's
## own `application/config/name` (`stranger_<addon>`) — a rig that stages its deps
## has more than one directory under `res://addons/`, so "the only addon there" is
## not a safe reading. A name that does not resolve to a staged directory is a
## FAILURE and not a skip: it would otherwise be a scene that asserts nothing about
## nothing and prints [PASS].
##
## KNOWN FAILURES ARE NAMED, NEVER COUNTED. A rig whose subject carries debt reads
## `known_failures.tsv` from its own directory — `path <TAB> ticket <TAB> why` — and
## the arm is a SET, both directions: an unlisted file that does not compile is red,
## and a listed file that DOES compile is red too, because a burn-down that only
## grows is a list nobody deletes from. Same shape as
## `check_addon_portability.ARM1_BURN_DOWN`, and deliberately not a threshold.
##
## Run: <declared godot> --path <staged work dir> res://tests/stranger/shared/stranger_install.tscn

const KNOWN_FAILURES := "res://known_failures.tsv"
const SOURCE_SUFFIXES := ["gd", "gdshader", "gdshaderinc", "glsl", "glslinc"]
## Members that are not source and not metadata. Derived, not named: naming
## `fold_layer.tres` here would put the addon's membership list in a second
## place, and an arm keyed on a file that is gone reports nothing at all.
const RESOURCE_SUFFIXES := ["tres", "res", "tscn", "material"]

var _passed: int = 0
var _failed: int = 0
var _addon: String = ""
var _known: Dictionary = {}


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)


func _ready() -> void:
	_addon = _subject()
	_known = _known_failures()
	if _addon == "":
		print("%d passed, %d failed" % [_passed, _failed])
		print("[FAIL] the rig did not name a staged addon — nothing was measured")
		get_tree().quit()
		return
	print("[ok] subject: %s   known failures declared: %d" % [_addon, _known.size()])
	var files := _walk(_addon)
	_test_the_tree_arrived(files)
	_test_every_source_file_loads(files)
	_test_every_global_class_registers(files)
	_test_every_shader_include_compiles(files)
	_test_the_burn_down_names_real_files(files)
	_test_every_resource_member_loads(files)

	# ADR-0194 dec. 12 arm 2. A rig that early-returns when its subject is absent
	# passes by doing nothing, and a green run would describe an empty temp dir.
	if _passed == 0:
		print("[FAIL] ran zero assertions — nothing was checked, which is not a pass")
		_failed += 1
	print("%d passed, %d failed" % [_passed, _failed])
	if _failed == 0:
		if _known.is_empty():
			print("[PASS] %s stands up in a project that did nothing for it: "
				% _addon.get_file() + "%d files, source-copy staging" % files.size())
		else:
			# The weaker sentence, said in full. Goal #5's INSTALL half is not met
			# for an addon with a burn-down and the banner may not read as though it
			# were. It says INSTALL half and not `goal #5`, because goal #5 is a
			# conjunction of this and the cross-system reach count, and this rig
			# cannot see that half (ADR-0232). `tools/score_goals.py` holds the
			# join; a rig that claimed the whole word would be the same
			# two-registers-no-join defect from the other end.
			print("[PASS] %s stands up in a project that did nothing for it EXCEPT for "
				% _addon.get_file() + "%d named file(s) it does not: %d files, "
				% [_known.size(), files.size()] + "source-copy staging. Goal #5's "
				+ "INSTALL half is UNMET for this addon and the rows above say by how "
				+ "much; tools/score_goals.py joins it to the reach half (ADR-0232)")
	else:
		print("[FAIL] %s needs something this project does not provide" % _addon.get_file())
	get_tree().quit()


func _subject() -> String:
	var name := str(ProjectSettings.get_setting("application/config/name", ""))
	if not name.begins_with("stranger_"):
		_check(false, "the staged project is named %s, which does not say `stranger_<addon>` — "
			% name + "the rig has no subject and this scene cannot know what to measure")
		return ""
	var path := "res://addons/%s" % name.substr(9)
	if DirAccess.open(path) == null:
		_check(false, "the project names subject %s but %s is not staged" % [name, path])
		return ""
	return path


func _known_failures() -> Dictionary:
	"""`path <TAB> ticket <TAB> why`, from the rig's own directory. Absent = none."""
	var out := {}
	if not FileAccess.file_exists(KNOWN_FAILURES):
		return out
	for line in FileAccess.get_file_as_string(KNOWN_FAILURES).split("\n"):
		if line.strip_edges() == "" or line.begins_with("#"):
			continue
		var parts := line.split("\t")
		if parts.size() >= 4:
			# Rows are written repo-relative, the way every other register in this
			# repo writes a path; the staged project addresses the same file as
			# `res://…`. Normalising here rather than in the file keeps the row
			# greppable against the tree it describes.
			var path: String = parts[0]
			if not path.begins_with("res://"):
				path = "res://" + path
			out[path] = "%s — %s" % [parts[1], parts[3]]
	return out


func _walk(dir: String) -> PackedStringArray:
	"""Every file under `dir`, recursively, res:// paths, sorted."""
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var path := "%s/%s" % [dir, name]
		if d.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_walk(path))
		else:
			out.append(path)
		name = d.get_next()
	d.list_dir_end()
	var sorted := Array(out)
	sorted.sort()
	return PackedStringArray(sorted)


func _sources(files: PackedStringArray, suffix: String) -> Array:
	var out := []
	for f in files:
		if f.get_extension() == suffix:
			out.append(f)
	return out


func _test_the_tree_arrived(files: PackedStringArray) -> void:
	"""The stage happened. Without this the whole scene is vacuously green."""
	_check(files.size() > 0, "the staged project has no %s at all" % _addon)
	_check(files.has("%s/plugin.cfg" % _addon), "no plugin.cfg — this is not an addon")
	_check(files.has("%s/README.md" % _addon), "no README.md — dec. 7 reads the engine from it")
	var srcs := 0
	for suf in SOURCE_SUFFIXES:
		srcs += _sources(files, suf).size()
	_check(srcs > 0, "the staged tree carries no source file")


func _test_every_source_file_loads(files: PackedStringArray) -> void:
	"""A preload of anything outside the addon fails HERE, in the project that
	does not have it — which is the whole exercise. `Fold.gd` is the live case:
	its `const FOLD_LAYER := preload(fold_layer.tres)` is a parse error on any
	engine without `CompositorRenderLayer`, so it is also the file that makes
	this addon's `engine="fork"` declaration true."""
	for f in _sources(files, "gd"):
		# `load()` IS NOT THE WITNESS, and finding that out cost a seeded run. A
		# GDScript that fails to parse still comes back from `load()` as a
		# non-null GDScript — measured on stock, where `Fold.gd`'s preload of a
		# `CompositorRenderLayer` is a hard parse error and `load()` returns an
		# object regardless. `get_instance_base_type()` is empty for exactly that
		# script and non-empty for every one that compiled, so it is the arm.
		if _known.has(f):
			# NOT LOADED HERE, and the split is not cosmetic. Loading a script that
			# fails to parse emits `SCRIPT ERROR` on stderr, and the rig's rule is
			# that a throw in a stranger project IS the finding — a rule worth
			# keeping strict. So this scene stays throw-free and
			# `stranger_burn_down.tscn` loads exactly these, where a throw is the
			# expected outcome and the rig says so. STATED, not absorbed: a rig
			# that swallows its own debt reports a green meaning something
			# different from every other green.
			print("[ok] KNOWN FAILURE %s — %s" % [f.replace("res://", ""), _known[f]])
			continue
		var s = load(f)
		_check(s != null and s is GDScript, "%s does not load" % f)
		if s == null or not (s is GDScript):
			continue
		_check(s.get_instance_base_type() != "",
			"%s loaded but did not COMPILE — a parse error in this project" % f)


func _test_every_global_class_registers(files: PackedStringArray) -> void:
	"""A stranger uses this addon by naming its types. `ProjectSettings.get_global_class_list()`
	is the project's own register, so this asks the stranger project what it
	learned from the import pass rather than asking the addon about itself."""
	var declared := {}
	for f in _sources(files, "gd"):
		for line in FileAccess.get_file_as_string(f).split("\n"):
			var t := line.strip_edges()
			if t.begins_with("class_name "):
				declared[t.substr(11).split(" ")[0].split("\t")[0].strip_edges()] = f
	_check(declared.size() > 0, "no file in the addon declares a class_name — "
		+ "a stranger would have no way to name any of this")
	var registered := {}
	for e in ProjectSettings.get_global_class_list():
		registered[str(e.get("class", ""))] = str(e.get("path", ""))
	for cname in declared:
		_check(registered.has(cname),
			"class_name %s (%s) is not registered in the stranger project" % [cname, declared[cname]])
		if registered.has(cname):
			_check(registered[cname] == declared[cname],
				"class_name %s resolves to %s, not to the addon's own %s"
				% [cname, registered[cname], declared[cname]])


## The probe declares its OWN uniform after the include, and that is the whole
## witness: a shader that fails to compile exposes no uniforms at all — measured,
## including when the include itself declares five. Counting the INCLUDE's uniforms
## was the first version and it was wrong twice over: it calls a seam that declares
## none (`fft_visible_angles.gdshaderinc`) a failure, and it cannot tell "compiled,
## declares nothing" from "did not compile".
const SHADER_WITNESS := "_rig_include_compiles"
## A seam is written for the shader types it is written for. `tile_overlay` and
## the cursor's fold body are spatial; `color_stack` is type-agnostic. The
## claim is that the seam compiles, not that it compiles as a canvas_item, so the
## probe tries each and passes if any does.
const SHADER_TYPES := ["canvas_item", "spatial"]
const SHADER_BODY := {
	"canvas_item": "void fragment() { COLOR = vec4(1.0); }",
	"spatial": "void fragment() { ALBEDO = vec3(1.0); }",
}


func _test_every_shader_include_compiles(files: PackedStringArray) -> void:
	"""A shader seam is half the addon's interface and no `load()` compiles it."""
	for inc in _sources(files, "gdshaderinc"):
		var ok := false
		var tried := PackedStringArray()
		for st in SHADER_TYPES:
			# Two variants, because a seam may or may not bring its own entry
			# points. `cursor_fold.gdshaderinc` defines BOTH `vertex()` and
			# `fragment()` — its wrappers add nothing but a `render_mode` — so a
			# probe that supplies a body redeclares a function and fails to
			# compile, which the first version of this arm reported as the addon's
			# defect rather than its own.
			for body in [SHADER_BODY[st], ""]:
				var sh := Shader.new()
				sh.code = ("shader_type %s;\n#include \"%s\"\nuniform float %s;\n%s\n"
					% [st, inc, SHADER_WITNESS, body])
				for u in sh.get_shader_uniform_list(true):
					if str(u.get("name", "")) == SHADER_WITNESS:
						ok = true
				tried.append("%s%s" % [st, "" if body != "" else " (bare)"])
				if ok:
					break
			if ok:
				break
		# 🔴 THE STANDALONE PROBE IS NOT THE ONLY EVIDENCE, AND IT IS THE WEAKER ONE.
		# A seam may REQUIRE something from its includer by design:
		# `addons/exmateria_effects/render/effect_particle_fold.gdshaderinc` reads
		# `EFFECT_STP_ALPHA`, which each including stub `#define`s, and the file's own
		# note says the missing default is deliberate — *"with no default, a missing
		# define is an undeclared identifier"*, which is what stops a new blend mode
		# rendering silently at the wrong alpha. No synthetic wrapper can supply that,
		# so the probe above calls a correct seam broken.
		#
		# The addon's OWN shaders can. If a staged `.gdshader` in this addon includes
		# the seam and compiles here, the seam compiles here — the same claim, taken
		# the way the addon actually uses it, and strictly stronger than a wrapper
		# nobody ships. Only reached when the standalone probe already failed, so this
		# can turn a false red green and cannot turn a real red green: the shader
		# carries the include, and a broken include fails with it.
		var via := ""
		if not ok:
			for sdr in _sources(files, "gdshader"):
				var src := FileAccess.get_file_as_string(sdr)
				if src == "" or not src.contains(inc):
					continue
				var sh2 := Shader.new()
				sh2.code = src + "\nuniform float %s;\n" % SHADER_WITNESS
				for u in sh2.get_shader_uniform_list(true):
					if str(u.get("name", "")) == SHADER_WITNESS:
						ok = true
						via = sdr
				if ok:
					break
			if ok:
				print("[ok] #include \"%s\" compiles through %s — the standalone probe "
					% [inc, via.replace("res://", "")]
					+ "cannot supply what this seam takes from its includer")
		_check(ok, "#include \"%s\" did not compile in this project as any of %s, and no "
			% [inc, ", ".join(tried)]
			+ "staged shader in this addon includes it either")


func _test_the_burn_down_names_real_files(files: PackedStringArray) -> void:
	"""A row naming a file that is not in the addon reports nothing forever."""
	for path in _known:
		_check(files.has(path), "known_failures.tsv names %s, which is not in the staged "
			% path + "addon. A burn-down row for a file that does not exist can never be "
			+ "paid off and can never fail — delete it or fix the path")


func _test_every_resource_member_loads(files: PackedStringArray) -> void:
	"""The addon's non-script members. `fold_layer.tres` is the whole population
	today and it is the one file that makes this addon fork-only: it is a
	`CompositorRenderLayer`, a class stock Godot does not have, so on stock it
	fails to load and takes `Fold.gd`'s preload down with it. That is the fact
	`plugin.cfg`'s `engine="fork"` declares.

	NO EARLY RETURN, and that is the point. The first version of this arm asked
	`if not ResourceLoader.exists(path): return` — so deleting the file scored
	20 passed, 0 failed and printed `[PASS]`. ADR-0194 dec. 12 names that exact
	failure: a test that early-returns when its subject is absent passes by doing
	nothing. Deriving the list from the tree does not fix it either; what fixes it
	is that `_test_the_tree_arrived` asserts the tree is there and the assertion
	count is printed, so a member leaving is visible as the count dropping.

	IT READS `known_failures.tsv`, ON THE SAME TERMS AS THE SCRIPT ARM. The
	docstring above used to say `fold_layer.tres` "is the whole population today",
	and that sentence is what dated. ADR-0202 pass 9 moved
	`tile_cursor_opaque.tres` into `exmateria_battlefield`, where its two
	ROM-derived `res://assets/` `ext_resource`s are Class B debt this rig is
	supposed to be able to STATE — the same thing the script arm has always been
	able to state about a `.gd`. Without this, an addon with declared resource
	debt has no green available to it at all, and the burn-down's two directions
	stop applying to half its members."""
	for suf in RESOURCE_SUFFIXES:
		for path in _sources(files, suf):
			if _known.has(path):
				print("[ok] KNOWN FAILURE %s — %s" % [path.replace("res://", ""), _known[path]])
				continue
			var res = ResourceLoader.load(path)
			_check(res != null,
				"%s does not load — the declared engine cannot host this addon" % path)
