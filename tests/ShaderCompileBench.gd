extends SceneTree

## Per-stage shader compilation benchmark.
## Run with:  godot --path . -s res://tests/ShaderCompileBench.gd
##
## Compiles each per-stage shader (matching GPUBatchSimulator._run_tick's
## dispatch order) and reports timing. With a cleared SPIR-V cache, this
## reproduces the cold-launch pipeline_create cost — useful for measuring
## the impact of further shader splits.

const STAGE_FILES = [
	"res://src/gpu/shaders/stage_compute.glsl",
	"res://src/gpu/shaders/stage_resolve.glsl",
	"res://src/gpu/shaders/stage_post_conflict.glsl",
	"res://src/gpu/shaders/stage_damage.glsl",
	"res://src/gpu/shaders/stage_victory.glsl",
	"res://src/gpu/shaders/stage_attack.glsl",
	"res://src/gpu/shaders/stage_spell.glsl",
	"res://src/gpu/shaders/stage_pathfind.glsl",
]

func _init():
	# LOCAL ONLY — no global-device fallback, for the reason in
	# GPUBatchSimulator.initialize(): the global device cannot submit/sync (#430).
	var rd = RenderingServer.create_local_rendering_device()
	if not rd:
		print("ERROR: No LOCAL rendering device available (cannot run headless)")
		quit(1)
		return

	print("")
	print("=== Per-Stage Shader Compilation Benchmark ===")
	print("")
	print("Tip: clear ~/.local/share/godot/app_userdata/learning/shader_cache/")
	print("     before running this to measure cold-cache compile time.")
	print("")

	var pass_total_start = Time.get_ticks_msec()
	var results = []

	for stage_path in STAGE_FILES:
		var src = _load_with_includes(stage_path)
		if src.is_empty():
			print("  FAILED to load: %s" % stage_path)
			continue
		src = src.replace("#[compute]\n", "").replace("#[compute]", "")

		var label = stage_path.get_file().get_basename()
		var result = _compile(rd, src, label)
		results.append(result)
		if result["shader"].is_valid():
			rd.free_rid(result["pipeline"])
			rd.free_rid(result["shader"])

	var pass_total = Time.get_ticks_msec() - pass_total_start

	print("")
	print("--- Per-Stage Results ---")
	for t in results:
		print("  %-22s spirv=%6dms  create=%4dms  pipeline=%6dms  total=%6dms%s" % [
			t["name"] + ":",
			t["spirv_ms"],
			t["create_ms"],
			t["pipeline_ms"],
			t["spirv_ms"] + t["create_ms"] + t["pipeline_ms"],
			"  ERROR" if t["error"] != "" else ""
		])
	print("  %-22s                                                  total=%6dms" % ["COMBINED:", pass_total])

	print("")
	print("=== Done ===")
	print("")

	rd.free()
	quit(0)


func _load_with_includes(shader_path: String, visited: Dictionary = {}) -> String:
	"""Inline `#include "..."` directives. Mirrors GPUBatchSimulator._load_shader_with_includes."""
	if visited.has(shader_path):
		push_error("[ShaderCompileBench] Circular include of %s" % shader_path)
		return ""
	visited[shader_path] = true

	var file = FileAccess.open(shader_path, FileAccess.READ)
	if not file:
		push_error("[ShaderCompileBench] Failed to open %s" % shader_path)
		return ""
	var src = file.get_as_text()
	file.close()

	var include_re := RegEx.new()
	include_re.compile('^\\s*#include\\s+"([^"]+)"\\s*$')
	var base_dir = shader_path.get_base_dir()
	var out: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		var m = include_re.search(line)
		if m == null:
			out.append(line)
			continue
		var inc = m.get_string(1)
		if not inc.begins_with("res://"):
			inc = base_dir.path_join(inc)
		var inc_src = _load_with_includes(inc, visited)
		if inc_src.is_empty():
			return ""
		out.append(inc_src)
	return "\n".join(out)


func _compile(rd: RenderingDevice, source_text: String, label: String) -> Dictionary:
	var shader_src = RDShaderSource.new()
	shader_src.source_compute = source_text

	var t0 = Time.get_ticks_msec()
	var spirv = rd.shader_compile_spirv_from_source(shader_src)
	var spirv_ms = Time.get_ticks_msec() - t0

	var err = ""
	if spirv:
		err = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)

	var shader = RID()
	var pipeline = RID()
	var create_ms = 0
	var pipeline_ms = 0
	if spirv and err == "":
		var t1 = Time.get_ticks_msec()
		shader = rd.shader_create_from_spirv(spirv)
		create_ms = Time.get_ticks_msec() - t1

		var t2 = Time.get_ticks_msec()
		pipeline = rd.compute_pipeline_create(shader)
		pipeline_ms = Time.get_ticks_msec() - t2

		print("  %s: spirv=%dms create=%dms pipeline=%dms" % [label, spirv_ms, create_ms, pipeline_ms])
	else:
		if err != "":
			print("  %s: COMPILE ERROR (spirv=%dms): %s" % [label, spirv_ms, err.substr(0, 200)])
		else:
			print("  %s: SPIRV compilation returned null (spirv=%dms)" % [label, spirv_ms])

	return {
		"name": label,
		"spirv_ms": spirv_ms,
		"create_ms": create_ms,
		"pipeline_ms": pipeline_ms,
		"shader": shader,
		"pipeline": pipeline,
		"error": err
	}
