extends Node3D

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice


func _ready():
	# #463/#504: this scene is a rig, not a test. Declared FIRST so it is on the record
	# even if a step below aborts. The verdict reader scores it NOT_A_TEST — see
	# tests/lib/verdict.sh; it used to score HUNG, which rule 1 takes before any
	# declaration, and rightly: the fix for a hang is to stop hanging.
	print("[NOT_A_TEST] a GPU-init timing diagnostic — it prints two A/B experiments' millisecond marks for a human to read, and asserts nothing; it is a rig")
	print("\n=== STARTUP DIAGNOSTIC v2 ===\n")

	var t0 = Time.get_ticks_msec()
	print("[%dms] Scene _ready() entered" % 0)

	# Check autoload states
	print("[%dms] EffectMultiMeshPool: warmup_created=%d, warmup_done=%s" % [
		Time.get_ticks_msec() - t0,
		EffectMultiMeshPool._warmup_created if EffectMultiMeshPool else -1,
		str(EffectMultiMeshPool._warmup_done) if EffectMultiMeshPool else "N/A"
	])

	# === EXPERIMENT A: GPU pipeline BEFORE any scene components ===
	_mark(t0, "=== EXPERIMENT A: GPU init FIRST (no camera/map) ===")

	var rd_a = RenderingServer.create_local_rendering_device()
	_mark(t0, "A: rendering device created")

	var shader_source = _load_shader_source()
	_mark(t0, "A: shader source loaded (%d chars)" % shader_source.length())

	if rd_a and shader_source.length() > 0:
		var modified = shader_source.replace("#[compute]\n", "").replace("#[compute]", "")

		var shader_src = RDShaderSource.new()
		shader_src.source_compute = modified
		var spirv = rd_a.shader_compile_spirv_from_source(shader_src)
		_mark(t0, "A: SPIRV compiled")

		if spirv:
			var err = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
			if err != "":
				print("  A: COMPILE ERROR: %s" % err)
			else:
				var shader = rd_a.shader_create_from_spirv(spirv)
				_mark(t0, "A: shader created (valid=%s)" % str(shader.is_valid()))
				var pipeline = rd_a.compute_pipeline_create(shader)
				_mark(t0, "A: pipeline created (valid=%s)" % str(pipeline.is_valid()))
				# Cleanup
				rd_a.free_rid(pipeline)
				rd_a.free_rid(shader)

	# Guarded: a null device here would abort _ready() on the .free(), and a GDScript
	# error aborts the enclosing function silently — which lands us back in an idle
	# process with no exit condition, the exact hang this ticket is closing.
	if rd_a:
		rd_a.free()
	_mark(t0, "A: rendering device freed")

	# === Now add scene components ===
	await get_tree().process_frame
	await get_tree().process_frame
	_mark(t0, "2 frames waited (EffectMultiMeshPool warmup_created=%d)" % EffectMultiMeshPool._warmup_created)

	# Add map
	# The host mount (ADR-0207 dec. 1) — its root is already a `Node3D` named
	# `ProceduralMap` carrying `MapComposer.gd`, so the four hand-assembly lines go.
	var map = load("res://assets/scenes/ProceduralMap.tscn").instantiate()
	add_child(map)
	await get_tree().process_frame
	_mark(t0, "MapComposer added (EffectMultiMeshPool warmup_created=%d)" % EffectMultiMeshPool._warmup_created)

	# Add camera
	# The HOST mount (ADR-0204 dec. 1), not the addon scene: it INHERITS the addon's
	# camera, so every node path is byte-identical, and it is what production instances.
	var cam_scene = load("res://assets/scenes/CombatCamera.tscn")
	var cam = cam_scene.instantiate()
	add_child(cam)
	await get_tree().process_frame
	_mark(t0, "PlayerCamera added (EffectMultiMeshPool warmup_created=%d)" % EffectMultiMeshPool._warmup_created)

	# Distance field
	var lattice: Lattice = map.lattice
	if lattice:
		var df = DistanceFieldGenerator.new()
		df.generate(lattice)
		_mark(t0, "DistanceField generated")

	# === EXPERIMENT B: GPU pipeline AFTER camera + map + warmup in progress ===
	_mark(t0, "=== EXPERIMENT B: GPU init AFTER camera/map ===")

	var rd_b = RenderingServer.create_local_rendering_device()
	_mark(t0, "B: rendering device created")

	if rd_b and shader_source.length() > 0:
		var modified = shader_source.replace("#[compute]\n", "").replace("#[compute]", "")

		var shader_src = RDShaderSource.new()
		shader_src.source_compute = modified
		var spirv = rd_b.shader_compile_spirv_from_source(shader_src)
		_mark(t0, "B: SPIRV compiled")

		if spirv:
			var err = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
			if err != "":
				print("  B: COMPILE ERROR: %s" % err)
			else:
				var shader = rd_b.shader_create_from_spirv(spirv)
				_mark(t0, "B: shader created (valid=%s)" % str(shader.is_valid()))
				var pipeline = rd_b.compute_pipeline_create(shader)
				_mark(t0, "B: pipeline created (valid=%s)" % str(pipeline.is_valid()))
				rd_b.free_rid(pipeline)
				rd_b.free_rid(shader)

	if rd_b:
		rd_b.free()
	_mark(t0, "B: rendering device freed")

	print("\n=== DIAGNOSTIC COMPLETE ===\n")
	# The exit condition this rig never had. It is one-shot and its output is already
	# complete by here, so there is nothing to wait for.
	get_tree().quit(0)


func _load_shader_source() -> String:
	"""Load stage_compute.glsl with includes inlined.

	stage_compute is the long pole — the heaviest pipeline_create in the
	per-tick dispatch. Measuring it here captures the worst case.
	"""
	return _load_with_includes("res://src/gpu/shaders/stage_compute.glsl", {})


func _load_with_includes(shader_path: String, visited: Dictionary) -> String:
	if visited.has(shader_path):
		return ""
	visited[shader_path] = true

	var file = FileAccess.open(shader_path, FileAccess.READ)
	if not file:
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


func _mark(t0: int, label: String):
	print("[%dms] %s" % [Time.get_ticks_msec() - t0, label])
