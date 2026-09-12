extends SceneTree
## Guard: the ENGINE Pass B fold (EngineFoldCompositor) carries a paletted producer's CLUT into the
## fold material. Regression guard for "the tile cursor's subtractive outline is missing under
## engine-fold" (2026-07-28) — the same CLASS of gap as the Shiva level_scale drop: the engine-fold
## consumer silently ignored per-producer features the shipped GLSL fold supported. Here it was
## `use_palette` / the palette texture / `palette_rows` — so a paletted (indexed) sheet folded as raw
## grayscale and the cursor outline lost its color.
##
## THE CLAIM UNDER TEST: given a pool bucket that publishes an INDEXED sheet + a 9-row CLUT
## (use_palette=true, palette_tex_2d set, palette_rows=9 — the RANGETILE cursor shape), the
## MultiMeshInstance3D EngineFoldCompositor materializes for that run wears a fold material with
##   use_palette == true, palette_texture != null, palette_rows == 9.0.
## An RGBA bucket (use_palette=false) must leave the material's use_palette false (no regression to the
## particle path). Exits 0 on PASS, 1 on FAIL.
##
## MUST run on the 4.8-dev engine, Forward+ (EngineFoldCompositor is Forward+-only), NEVER headless:
##   BIN=~/Repos/godot-compositor-consume-material/bin/godot.linuxbsd.editor.dev.x86_64
##   # from the package root
##   "$BIN" --path . --rendering-method forward_plus -s res://tools/probe_cursor_palette_engine_fold.gd

const OTDepthPrimOrder = preload("res://addons/exmateria_effects/render/OTDepthPrimOrder.gd")
const UnifiedPrimStager = ExMateriaEffects.UnifiedPrimStager

const ENGINE_FOLD := "res://addons/exmateria_effects/render/EngineFoldCompositor.gd"


## Stand-in pool: hands EngineFoldCompositor one bucket via the same duck-typed method the real pool
## exposes (get_active_effect_buckets). The bucket's shape mirrors EffectMultiMeshPool exactly.
class StubPool:
	extends Node
	var _buckets: Array = []
	func get_active_effect_buckets() -> Array:
		return _buckets


func _make_bucket(use_palette: bool, palette_rows: int) -> Dictionary:
	# One subtractive (mode 2) cursor-like prim staged the real way, so unified_bytes/runs match prod.
	var stager := UnifiedPrimStager.new()
	stager.begin(Transform3D())
	var basis := Basis(Vector3(-6, -24, 6), Vector3(-24, -6, 0), Vector3(6, 0, 7))
	var color := Color(1.0, 1.0, 1.0, float(4) / 15.0)   # palette_row 4 packed in a (RANGETILE cursor)
	stager.append(basis, Vector3(0, 1, 0), color, Color(0.25, 0.5, 0.05, 0.09), 2, 7, 0.0)
	var result: Dictionary = OTDepthPrimOrder.order(stager.records(), stager.modes(),
		stager.depths(), stager.ages())
	var sheet := PlaceholderTexture2D.new()
	sheet.size = Vector2(256, 256)
	var pal: Variant = null
	if use_palette:
		var p := PlaceholderTexture2D.new()
		p.size = Vector2(16, palette_rows)
		pal = p
	return {
		"unified_bytes": (result["unified"] as PackedFloat32Array).to_byte_array(),
		"runs": result["runs"],
		"count": 1,
		"effect_tex_2d": sheet,
		"palette_tex_2d": pal,
		"use_palette": use_palette,
		"palette_rows": palette_rows,
	}


func _fold_child_material(fold: Node) -> ShaderMaterial:
	var fold_root: Node3D = fold.get("_fold_root")
	if fold_root == null or fold_root.get_child_count() == 0:
		return null
	var inst := fold_root.get_child(0) as MultiMeshInstance3D
	if inst == null:
		return null
	return inst.material_override as ShaderMaterial


func _initialize() -> void:
	var fails: Array[String] = []

	var cam := Camera3D.new()
	root.add_child(cam)

	var pool := StubPool.new()
	root.add_child(pool)

	var fold: Node = load(ENGINE_FOLD).new()
	root.add_child(fold)
	fold.setup(cam)
	# setup() resolves _pool by node name and would bind the REAL EffectMultiMeshPool autoload; inject
	# our stub so _process folds exactly the bucket under test (the autoload's buckets are empty here).
	fold.set("_pool", pool)

	# --- Paletted (cursor) bucket: the fold material must carry the CLUT. ---
	pool._buckets = [_make_bucket(true, 9)]
	fold._process(0.0)
	var mat := _fold_child_material(fold)
	if mat == null:
		fails.append("paletted: no fold MultiMeshInstance3D materialized")
	else:
		if mat.get_shader_parameter("use_palette") != true:
			fails.append("paletted: use_palette not set true on fold material")
		if mat.get_shader_parameter("palette_texture") == null:
			fails.append("paletted: palette_texture null on fold material (CLUT dropped)")
		var rows: float = float(mat.get_shader_parameter("palette_rows"))
		if not is_equal_approx(rows, 9.0):
			fails.append("paletted: palette_rows=%s, want 9.0 (RANGETILE CLUT height)" % rows)

	# --- RGBA (particle) bucket: use_palette must stay false — no regression to the RGBA path. ---
	pool._buckets = [_make_bucket(false, 16)]
	fold._process(0.0)
	var mat2 := _fold_child_material(fold)
	if mat2 == null:
		fails.append("rgba: no fold MultiMeshInstance3D materialized")
	elif mat2.get_shader_parameter("use_palette") == true:
		fails.append("rgba: use_palette wrongly set true on a non-paletted bucket")

	if fails.is_empty():
		print("[cursor-palette-fold] PASS — engine-fold carries the CLUT (use_palette/palette_texture/palette_rows) for a paletted producer; RGBA path unaffected")
		quit(0)
	else:
		for f in fails:
			print("[cursor-palette-fold] FAIL — %s" % f)
		quit(1)
