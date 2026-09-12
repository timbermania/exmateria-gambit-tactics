extends SceneTree
## Compile every shader whose include closure reaches `effect_particle_stp.gdshaderinc`.
##
##     godot --path . -s tools/probe_stp_shaders.gd      # headful, never --headless
##
## WHY THIS EXISTS AND WHY NOTHING ELSE COVERS IT (#1217 (b)/(c), ADR-0287 dec. 3).
## Arm 4b's fix rewrote the shared include's declaration block: `psx_fx_stretch` moved to
## `#include .../psx_sprite_stretch.gdshaderinc` and `psx_gamma` left for four local
## `const`s. Both are edits to a `.gdshaderinc`, and a `.gdshaderinc` has no compile of its
## own — its errors only appear in the SEVEN `.gdshader` files that include it, plus the
## four `tools/probe_shaders/` copies. The static pre-flight never compiles a shader, and
## `godot --path . -e --quit` reimports without necessarily recompiling a cached SPIR-V, so
## neither instrument can see a redeclaration this close to the seam. Binding each shader to
## a `ShaderMaterial` on a `MeshInstance3D` is what forces the real compile.
##
## ⚠️ IT HAS A POSITIVE CONTROL AND THE ZERO IS ONLY WORTH THE CONTROL. Re-adding
## `global uniform float psx_fx_stretch;` beside the new `#include` makes it print
## `SHADER ERROR: Redefinition of 'psx_fx_stretch'.` once per shader, eleven times —
## verified 2026-09-11. Run that seed before trusting a clean pass.
##
## NOT in `tests/run_all_tests.sh`: it is a `tools/` probe like `probe_studio_inspector.gd`,
## because the suite is 736 processes and every test costs a ~2.3 s boot forever
## (`docs/TEST-CHARTER.md`). #1225 moves all eleven of these files and should re-run it.
# 🔴 preload, NOT a String path. `check_fold_shader_preload.py` (ADR-0191 dec. 2 +
# Amendment 4 §2) forbids naming a fold shader as a String from GDScript: a `load()` of a
# mistyped path returns null, a null shader does not raise, and the fold just stops with no
# error — while `preload` makes the same typo a parse error. This probe's first draft used a
# String array and the pre-flight aborted on it, which is the guard doing exactly its job on
# a file whose whole purpose is catching silent shader failures.
const SHADERS := [
	preload("res://addons/exmateria_effects/render/effect_particle_opaque.gdshader"),
	preload("res://addons/exmateria_effects/render/effect_fold_add.gdshader"),
	preload("res://addons/exmateria_effects/render/effect_fold_mix.gdshader"),
	preload("res://addons/exmateria_effects/render/effect_fold_sub.gdshader"),
	preload("res://addons/exmateria_effects/render/effect_native_add.gdshader"),
	preload("res://addons/exmateria_effects/render/effect_native_mix.gdshader"),
	preload("res://addons/exmateria_effects/render/effect_native_sub.gdshader"),
	preload("res://tools/probe_shaders/effect_particle_mode0.gdshader"),
	preload("res://tools/probe_shaders/effect_particle_mode1.gdshader"),
	preload("res://tools/probe_shaders/effect_particle_mode2.gdshader"),
	preload("res://tools/probe_shaders/effect_particle_mode3.gdshader"),
]
func _initialize() -> void:
	var bad := 0
	for sh: Shader in SHADERS:
		if sh == null:
			print("LOAD FAILED (null after preload)"); bad += 1; continue
		var names := []
		for u in sh.get_shader_uniform_list():
			names.append(str(u.get("name", "")))
		var mat := ShaderMaterial.new()
		mat.shader = sh
		var mi := MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		mi.material_override = mat
		get_root().add_child(mi)
		# `psx_gamma` / `psx_fx_stretch` are GLOBAL uniforms and never appear in a
		# per-material list, before or after #1217 — printed as the explicit zero they are,
		# not as a discriminator.
		print("OK  %-62s uniforms=%d  psx_gamma_uniform=%s  psx_fx_stretch_uniform=%s"
			% [sh.resource_path.get_file(), names.size(),
			   "psx_gamma" in names, "psx_fx_stretch" in names])
	print("RESULT: %d of %d loaded" % [SHADERS.size() - bad, SHADERS.size()])
	quit(1 if bad else 0)
