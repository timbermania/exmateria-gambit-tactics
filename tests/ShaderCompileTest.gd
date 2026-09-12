extends Node
## The shaders are COMPILED here, not text-scanned (candidate 7).
##
## Before this test, no test in the package compiled a single `.gdshader`. The three fold-routing
## tests (CallbackFoldRoutingTest, FormationFoldRoutingTest, FeedbackHudFoldRoutingTest) assert
## against shader SOURCE read with `FileAccess.get_file_as_string`, and the Python guards
## (check_no_pow_in_fold, check_no_psx_brightness_in_fold, check_fold_primitive_kind,
## check_compositor_routing, check_depth_shaders) are regexes over the same text. Every one of
## them is happy with a shader that does not parse. A syntax error in a fold material therefore
## shipped to runtime, where it degrades silently: the engine substitutes nothing, the folded
## carrier just stops compositing.
##
## THE ORACLE. Godot exposes no compile-error string on `Shader`, but it exposes a total
## equivalent: a shader that fails to parse reports an EMPTY `get_shader_uniform_list()`, whatever
## its source declared. Asking "are the uniforms there?" is not enough on its own — a shader with
## no uniforms would be untestable — so each shader is compiled with one inert probe uniform
## appended. The probe must come back. That is a yes/no compile verdict for EVERY `.gdshader`,
## including one that declares nothing. (Appending an unused uniform cannot break a shader that
## otherwise compiles, so "compiles with the probe" implies "compiles".)
##
## NO IMPORT-CACHE TRAP. `.gdshader` is a text resource — Godot parses the file, there is no
## `.godot/imported/` artifact between the source and the verdict. The `.glsl` half sidesteps the
## cache the other way: it reads the source text and compiles it with
## `shader_compile_spirv_from_source(..., allow_cache = false)`, so the import cache is never
## consulted. That is what retired `tools/check_foldsurface_shaders.gd`, which read the IMPORTED
## SPIR-V and was in no runner. Measured, not asserted: with a syntax error seeded into
## foldsurface_seed.glsl and no reimport, the old checker printed `OK` / `RESULT: PASS` for both
## files while this test failed 3 assertions. (Same trap FoldQuantizePolicyTest paid for once.)
##
## Run: <GODOT> --path . res://tests/ShaderCompileTest.tscn

## Appended to every shader before compiling. A name no shader would collide with.
const PROBE := "__shader_compile_probe__"

## The fold bracket's two raw-GLSL passes (FoldSurface Pass A / Pass C). `foldsurface_seed.glsl`
## has no other test at all; `foldsurface_resolve.glsl` is exercised by FoldQuantizePolicyTest,
## which loads it through the import cache.
const FOLD_GLSL := [
	"res://addons/exmateria_render/fold_bracket/foldsurface_seed.glsl",
	"res://addons/exmateria_render/fold_bracket/foldsurface_resolve.glsl",
]

## A walk that finds nothing passes vacuously — the stale-scan-root failure that shipped 14 green
## guards in extraction #1. There are 81 `.gdshader` files at the time of writing; this floor only
## has to be low enough not to churn and high enough to catch a walk that lost a root.
const MIN_SHADERS := 40

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var shaders := _walk("res://", ".gdshader")
	shaders.sort()
	_assert_true(shaders.size() >= MIN_SHADERS,
		"the walk found %d .gdshader files (>= %d)" % [shaders.size(), MIN_SHADERS])

	var folds_in_assets := 0
	var folds_in_ui3 := 0
	var folds_in_addons := 0
	for path: String in shaders:
		var src := FileAccess.get_file_as_string(path)
		if _declares_compositor_layer(src):
			if path.begins_with("res://assets/shaders/"):
				folds_in_assets += 1
			elif path.begins_with("res://src/ui3/shaders/"):
				folds_in_ui3 += 1
			elif path.begins_with("res://addons/"):
				folds_in_addons += 1
		_assert_true(_gdshader_compiles(path), "%s compiles" % path)

	# Both fold roots must still be reachable from the walk. The 16 `compositor_layer` shaders split
	# 6 under assets/shaders/ (Effects), 6 under src/ui3/shaders/ (UI) and 4 under
	# addons/exmateria_battlefield/ (cursor triplet + tile decal); losing either NAMED root would leave
	# this test green while covering part of the fold surface. This comment said "10 and 6" until
	# ADR-0191 dec. 4 — a third of the population was in neither bucket, and the assertion below
	# only checks both named roots are non-zero, so it stayed green over the wrong arithmetic.
	_assert_true(folds_in_assets > 0 and folds_in_ui3 > 0 and folds_in_addons > 0,
		"compositor_layer shaders found under ALL THREE roots (assets/shaders=%d, src/ui3/shaders=%d, addons=%d)"
			% [folds_in_assets, folds_in_ui3, folds_in_addons])

	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		_fail("could not create a local RenderingDevice for the .glsl half")
	else:
		for path: String in FOLD_GLSL:
			_assert_true(_glsl_compiles(rd, path), "%s compiles from SOURCE (no import cache)" % path)
		rd.free()

	_finish()


# --- the .gdshader oracle ----------------------------------------------------------------------

## Compile `path` with an inert probe uniform appended and report whether the probe survived.
## An empty uniform list is how a Godot shader reports a parse failure.
func _gdshader_compiles(path: String) -> bool:
	var sh := ResourceLoader.load(path, "Shader", ResourceLoader.CACHE_MODE_IGNORE) as Shader
	if sh == null:
		return false
	# Loading already compiled the original (and printed any SHADER ERROR); this recompiles it with
	# the probe, which is the assertion. Mutating the resource is safe — CACHE_MODE_IGNORE means
	# nothing else holds this instance.
	sh.code = "%s\nuniform float %s;\n" % [sh.code, PROBE]
	for u: Dictionary in sh.get_shader_uniform_list():
		if u["name"] == PROBE:
			return true
	return false


## True if `src` declares `compositor_layer` in a render_mode (not merely mentions it in a comment).
func _declares_compositor_layer(src: String) -> bool:
	for raw: String in src.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("render_mode") and "compositor_layer" in line:
			return true
	return false


# --- the .glsl oracle --------------------------------------------------------------------------

## Compile a Godot-flavoured `.glsl` (the `#[vertex]` / `#[fragment]` stage markers the importer
## splits on) straight from its SOURCE TEXT, with the SPIR-V cache disabled. Nothing here reads
## `.godot/imported/`, so an edited-but-not-reimported shader is judged as edited.
func _glsl_compiles(rd: RenderingDevice, path: String) -> bool:
	if not FileAccess.file_exists(path):
		_fail("missing: %s" % path)
		return false
	var stages := _split_stages(FileAccess.get_file_as_string(path))
	if not stages.has("vertex") or not stages.has("fragment"):
		_fail("%s has no #[vertex] + #[fragment] stages (found %s)" % [path, stages.keys()])
		return false
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_vertex = stages["vertex"]
	src.source_fragment = stages["fragment"]
	var spirv := rd.shader_compile_spirv_from_source(src, false)
	if spirv.compile_error_vertex != "":
		_fail("%s [vertex] %s" % [path, spirv.compile_error_vertex])
		return false
	if spirv.compile_error_fragment != "":
		_fail("%s [fragment] %s" % [path, spirv.compile_error_fragment])
		return false
	return true


## Split a Godot `.glsl` on its `#[stage]` markers into {stage_name: source}.
func _split_stages(text: String) -> Dictionary:
	var out := {}
	var current := ""
	var lines := PackedStringArray()
	for raw: String in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#[") and line.ends_with("]"):
			if current != "":
				out[current] = "\n".join(lines)
			current = line.substr(2, line.length() - 3)
			lines = PackedStringArray()
			continue
		if current != "":
			lines.append(raw)
	if current != "":
		out[current] = "\n".join(lines)
	return out


# --- res:// walk -------------------------------------------------------------------------------

func _walk(root: String, suffix: String) -> Array:
	var out: Array = []
	var dirs: Array = [root]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var name := da.get_next()
		while name != "":
			var full := d.path_join(name) if not d.ends_with("/") else d + name
			if da.current_is_dir():
				if name != "." and name != ".." and not name.begins_with("."):
					dirs.append(full)
			elif name.ends_with(suffix):
				out.append(full)
			name = da.get_next()
		da.list_dir_end()
	return out


# --- reporting ---------------------------------------------------------------------------------

func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failed += 1
	print("  [FAIL] %s" % label)


func _finish() -> void:
	print("\n=== ShaderCompileTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ShaderCompileTest")
		get_tree().quit(1)
	else:
		print("[PASS] ShaderCompileTest")
		get_tree().quit(0)
