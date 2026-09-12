extends Node
## Guards TileOverlayCompositor — the routed Move/Attack tile highlights, now a DIRECT baked-mesh node
## in the display-space fold (ADR-0074 ④b, issue #229) rather than a pool-staged UnifiedPrimStager
## producer. This is the LIVE BUG FIX: the tiles are FLAT GROUND DECALS (world_quad); the old pool path's
## engine-fold materialization read only `mode` and billboard-interpreted them, so on Forward+ the tiles
## VANISHED. Baking them as a real world-space mesh wearing a monomorphic world_quad fold material fixes
## it by construction. Locks (1) the monomorphic shader contract, (2) is_routed, (3) that the baked geometry
## DRAPES over the terrain (per-corner Y, ONE shared depth centroid — NOT a billboard), (4) direct-carrier
## routing through Fold.add.
##
## Pure GDScript + file reads, no GPU / no fork. Run: <GODOT> --path . res://addons/exmateria_battlefield/tests/TileOverlayCompositorTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const CellMarking = ExMateriaSchema.CellMarking

const Comp = preload("res://addons/exmateria_battlefield/overlay/TileOverlayCompositor.gd")

# COUNTERS, not a bare bool — gained in the move commit, the ADR-0194 dec. 12 arm 2
# convention this ledger already applied to DepthModeTest and TileCursorCompositorTest.
# A `[PASS]` printed off `not _failed` is true of a run that asserted NOTHING, and a
# GDScript runtime error aborts only its ENCLOSING function while `_ready` carries on —
# so the verdict below pins the TOTAL, not just the absence of failures.
var _passed := 0
var _failed := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		print("[FAIL] %s" % msg)
		_failed += 1


func _declares_fold(src: String) -> bool:
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*render_mode\\b[^;]*\\bcompositor_layer\\b")
	return re.search(src) != null


func _ready() -> void:
	_test_shader_is_monomorphic_world_quad()
	_test_is_routed()
	_test_baked_geometry_drapes_over_the_slope()
	_test_register_builds_direct_carrier()
	_test_cursor_gets_its_own_textured_carrier()

	print("\n=== TileOverlayCompositorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0:
		print("[FAIL] TileOverlayCompositorTest: ran zero assertions")
	elif _failed:
		print("[FAIL] TileOverlayCompositor test")
	else:
		print("[PASS] TileOverlayCompositor: monomorphic world_quad fold shader + is_routed/is_textured + ground decal DRAPED over the slope (per-corner Y, one face depth, not billboard) + direct-carrier Fold.add routing + the cursor's own TEXTURED carrier")
	get_tree().quit()


## The tile_decal_fold shader IS the contract: a compositor_layer material with world_quad geometry baked
## in — crucially NOT billboarded (no INV_VIEW_MATRIX rebuild) and NOT textured (solid CPU color).
func _test_shader_is_monomorphic_world_quad() -> void:
	# `.resource_path` because the const is a preloaded Shader now (ADR-0191 dec. 11), not a
	# String path. Reading the file as TEXT is still the point — the source contract is checked
	# without a GPU or the fork compiling it.
	var src := FileAccess.get_file_as_string(Comp.TILE_DECAL_FOLD_SHADER.resource_path)
	_check(not src.is_empty(), "tile_decal_fold shader readable")
	_check(_declares_fold(src), "tile_decal_fold declares compositor_layer in render_mode (routes into the scratch)")
	_check("blend_add" in src, "baked axis: additive blend (blend_add)")
	_check("pixel_aspect" in src, "baked axis: PAR-full (map-attached stretch)")
	_check(not ("INV_VIEW_MATRIX" in src),
		"baked axis: world_quad, NOT billboard (no INV_VIEW_MATRIX rebuild) — THE FIX")
	_check(not ("texture(" in src), "solid CPU-colored decal (no texture sample)")


## is_routed / is_textured: the TWO-AXIS split. Axis 1 (blend mode) says whether a type folds at
## all; axis 2 (flat_fill) says WHICH carrier it folds on. CURSOR_ACTIVE moved across axis 1 on
## 2026-09-08 (opaque 4 -> additive 1, the ROM's tpage 0x3F / ABR mode 1) and it is the only
## member on the textured side of axis 2, so both axes are asserted here rather than one.
func _test_is_routed() -> void:
	var comp = Comp.new()
	add_child(comp)
	_check(comp.is_routed(CellMarking.Kind.PLACEMENT_PLAYER), "PLACEMENT_PLAYER (additive) routes")
	_check(comp.is_routed(CellMarking.Kind.PLACEMENT_ENEMY), "PLACEMENT_ENEMY (additive) routes")
	_check(comp.is_routed(CellMarking.Kind.CURSOR_ACTIVE), "CURSOR_ACTIVE (additive) routes")
	# ADR-0258 retired PLACEMENT_CONTESTED, which was this arm's third routed member.
	# PLACEMENT_UNAVAILABLE holds the in-scene side on its own now (blend 0, average) alongside
	# SELECTED (blend 4, opaque) — both sides of the routing split still have members.
	_check(not comp.is_routed(CellMarking.Kind.PLACEMENT_UNAVAILABLE),
		"PLACEMENT_UNAVAILABLE (average) stays in-scene")
	_check(not comp.is_routed(CellMarking.Kind.SELECTED), "SELECTED (opaque) stays in-scene")
	# Axis 2. The placement decals resolve to one solid colour on the CPU; the cursor SAMPLES the
	# RANGETILE sheet, which is why it cannot ride the batched flat carrier.
	_check(comp.is_textured(CellMarking.Kind.CURSOR_ACTIVE), "CURSOR_ACTIVE is the TEXTURED routed type")
	_check(not comp.is_textured(CellMarking.Kind.PLACEMENT_PLAYER), "PLACEMENT_PLAYER is flat_fill — the batched carrier")
	comp.free()


## The baked quad DRAPES: on a SLOPED tile each emitted vertex sits on its own corner + DECAL_LIFT, so the
## highlight lies on the incline it marks (ADR-0250). `world_quad` is about how the verts are PRODUCED —
## baked ground positions, never expanded about a centroid at draw time — not about them sharing a Y, and
## conflating the two is what flattened these decals. The DEPTH is the axis that stays flat: CUSTOM0 is one
## shared centroid, one OT depth per face (ADR-0009), and this locks BOTH halves against each other.
func _test_baked_geometry_drapes_over_the_slope() -> void:
	var comp = Comp.new()
	add_child(comp)
	# 🔴 DO NOT GO BACK TO THE LOADED PALETTE. This line used to read "`_ready` loads the
	# palette so `_tile_color` resolves" and was wrong twice: the load is in `_init`, and it
	# resolves ONLY where the host's content exists. `_load_palette()` asks
	# `BattlefieldContent.range_palette_path()`, so in a project that did nothing for this addon
	# there is no palette and `_palette` stays null — correctly. `_process` guards that (`_palette
	# == null` returns early), but this test calls the private `_append_tile` directly and walks
	# straight past the guard into `TileOverlayColor.flat_color(null, ...)` → `get_width()` on null.
	# The stranger rig caught it as "reported PASS while throwing"; the 19 assertions passed either
	# way, so only the script-error arm could see it. Injecting the palette is what the sibling
	# TileOverlayColorTest already does, and it makes this test independent of host content rather
	# than quietly dependent on it.
	comp._palette = _stub_palette()
	_check(comp._palette != null, "the injected palette is what _tile_color reads, not host content")
	var tile := FakeTile.new()
	# A SLOPED tile: the four corners span Y from 0 to 2. The decal must DRAPE over this, not level it.
	var corners := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 1, 0), Vector3(1, 2, 1), Vector3(0, 1, 1)])
	tile.tile_vertices = corners
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()
	var ok: bool = comp._append_tile(tile, CellMarking.Kind.PLACEMENT_PLAYER, 0, positions, colors, uvs, custom0)
	_check(ok, "append_tile accepts a 4-corner tile")
	_check(positions.size() == 6, "one quad = 2 tris = 6 verts baked")

	# EVERY baked vertex sits on ITS OWN corner, lifted — the two tris are (tl,tr,br) and (tl,br,bl),
	# so the six emitted verts are corners 0,1,2,0,2,3. Asked corner by corner rather than as a
	# spread, because "the Ys differ" is also true of a decal draped over the WRONG corners.
	var order := [0, 1, 2, 0, 2, 3]
	var draped := true
	for i in 6:
		var want: Vector3 = corners[order[i]] + Vector3(0.0, Comp.DECAL_LIFT, 0.0)
		if not positions[i].is_equal_approx(want):
			draped = false
	_check(draped, "every baked vertex sits on its OWN corner + DECAL_LIFT — the decal DRAPES over the slope")
	# The defect this replaces, stated as its own check so a regression names itself rather than
	# showing up as a vague position mismatch: the old bake put all six verts at one centroid Y.
	var mean_y := (0.0 + 1.0 + 2.0 + 1.0) / 4.0
	var flattened := true
	for p in positions:
		if not is_equal_approx(p.y, mean_y + Comp.DECAL_LIFT):
			flattened = false
	_check(not flattened, "and NOT all at the lifted centroid Y — that flatten was the slope-dropping bug")

	# All six verts share one color (solid tile) and one CUSTOM0 centroid (ADR-0009 flat face depth).
	var same_color := true
	for col in colors:
		if col != colors[0]:
			same_color = false
	_check(colors.size() == 6 and same_color, "all verts share the tile's single barber-pole color")
	_check(custom0.size() == 18, "CUSTOM0 is RGB per vertex (6 verts x 3)")
	# THE DEPTH STAYS FLAT, and that is a DIFFERENT axis from the geometry (ADR-0250). The quad drapes,
	# but `ot_depth` reads CUSTOM0 and every vertex must carry the SAME centroid — one face, one OT
	# depth, the GTE's own AVSZ4 model. "Make the decal follow the slope" is exactly the change that
	# would tempt someone to make CUSTOM0 per-corner too, and that would be a real regression.
	var shared_centroid := true
	for i in 6:
		if not (is_equal_approx(custom0[i * 3], custom0[0])
				and is_equal_approx(custom0[i * 3 + 1], custom0[1])
				and is_equal_approx(custom0[i * 3 + 2], custom0[2])):
			shared_centroid = false
	_check(shared_centroid, "but CUSTOM0 is ONE shared centroid for all six — depth is per FACE, not per corner")
	_check(is_equal_approx(custom0[1], mean_y + Comp.DECAL_LIFT),
		"and that centroid is the lifted MEAN of the four corners")

	# A FLAT tile must bake identically to the old behaviour — the change is invisible on level ground.
	var flat_tile := FakeTile.new()
	flat_tile.tile_vertices = PackedVector3Array([
		Vector3(0, 5, 0), Vector3(1, 5, 0), Vector3(1, 5, 1), Vector3(0, 5, 1)])
	var fp := PackedVector3Array()
	var fc := PackedColorArray()
	var fu := PackedVector2Array()
	var f0 := PackedFloat32Array()
	comp._append_tile(flat_tile, CellMarking.Kind.PLACEMENT_PLAYER, 0, fp, fc, fu, f0)
	var flat_ok := true
	for p in fp:
		if not is_equal_approx(p.y, 5.0 + Comp.DECAL_LIFT):
			flat_ok = false
	_check(flat_ok, "on a FLAT tile the drape is identical to the old centroid bake — level ground is unchanged")
	flat_tile.free()
	tile.free()
	comp.free()


## register() builds a direct MeshInstance3D carrier wearing the tile_decal_fold material; unregister frees it.
func _test_register_builds_direct_carrier() -> void:
	var comp = Comp.new()
	add_child(comp)
	var tile := FakeTile.new()
	tile.tile_vertices = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)])
	comp.register(tile, CellMarking.Kind.PLACEMENT_PLAYER)
	var mi = comp.carrier()
	_check(mi != null and mi is MeshInstance3D, "register builds a MeshInstance3D carrier")
	_check(mi != null and mi.material_override is ShaderMaterial, "carrier wears a ShaderMaterial")
	if mi != null and mi.material_override is ShaderMaterial:
		var sh: Shader = mi.material_override.shader
		# IDENTITY, not path equality: both sides are the same preloaded Shader resource now, so this
		# asserts the carrier wears THE const — a copy loaded from the same path would no longer pass.
		_check(sh != null and sh == Comp.TILE_DECAL_FOLD_SHADER,
			"carrier wears the tile_decal_fold material")
	comp.unregister(tile)
	_check(comp.carrier() == null, "unregister frees the carrier when the last tile goes")
	tile.free()
	comp.free()


## The TEXTURED carrier is a SEPARATE node with a SEPARATE material — and that separation is the
## point, not an implementation detail. Two things ride on it:
##   * the shader. The flat carrier's tile_decal_fold samples nothing (solid CPU colour); the
##     cursor is a 13x13 texel diamond off the RANGETILE sheet, so it keeps the GPU CLUT path and
##     needs real UVs. Baking it into the flat batch would silently replace the diamond with a
##     solid quad — a regression that renders, which is the worst kind.
##   * the ORDER KEY. One carrier is one `render_layer_order`, and the flat one stamps the MEAN
##     centroid of every routed tile on the map. The unit shadow is ordered against THIS tile
##     (tests/ShadowFoldOrderTest), and a mean-of-everything key cannot answer that question.
func _test_cursor_gets_its_own_textured_carrier() -> void:
	var comp = Comp.new()
	add_child(comp)
	var tile := FakeTile.new()
	tile.tile_vertices = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)])
	comp.register(tile, CellMarking.Kind.CURSOR_ACTIVE)
	var mi = comp.cursor_carrier()
	_check(mi != null and mi is MeshInstance3D, "registering the cursor builds the TEXTURED carrier")
	_check(comp.carrier() == null, "and NOT the flat batched one — the two are separate nodes")
	if mi != null and mi.material_override is ShaderMaterial:
		var sh: Shader = mi.material_override.shader
		_check(sh != null and sh == Comp.TILE_OVERLAY_ADD_FOLD_SHADER,
			"the cursor carrier wears the tile_overlay_add_fold material")

	# The shader contract, read as text (no GPU, no fork): it folds, it ADDS, and it SAMPLES.
	var src := FileAccess.get_file_as_string(Comp.TILE_OVERLAY_ADD_FOLD_SHADER.resource_path)
	_check(_declares_fold(src), "tile_overlay_add_fold declares compositor_layer")
	_check("blend_add" in src, "and blends ADDITIVE — the ROM's tpage 0x3F / ABR mode 1")
	_check("texture(" in src or "tile_overlay_clut" in src, "and SAMPLES the sheet (unlike the flat decal)")
	_check(not ("pow(" in src), "with NO sRGB pow — a fold adds RAW display-space colour (check_no_pow_in_fold)")

	# Real UVs on the textured bake, and STILL Vector2.ZERO on the flat one: the flag has to do
	# something on both sides or `textured` is a parameter nobody reads.
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()
	comp._append_tile(tile, CellMarking.Kind.CURSOR_ACTIVE, 0, positions, colors, uvs, custom0, true)
	_check(uvs.size() == 6, "the textured bake emits a UV per vertex")
	var spans_unit_square := (uvs.has(Vector2(0.0, 0.0)) and uvs.has(Vector2(1.0, 0.0))
		and uvs.has(Vector2(1.0, 1.0)) and uvs.has(Vector2(0.0, 1.0)))
	_check(spans_unit_square, "and they map the four corners to the unit square the shader crops from")

	comp.unregister(tile)
	_check(comp.cursor_carrier() == null, "unregister frees the textured carrier too")
	tile.free()
	comp.free()


class FakeTile:
	extends Node3D
	var tile_vertices: PackedVector3Array


## A 16x1 stand-in for RANGETILE.palette.tga — 16 wide because the shader samples
## `(rot+0.5)/16`, one row because `_tile_color` only ever reads `palette_row`'s row and
## `flat_color` clamps to `get_height() - 1`. Deliberately NOT the real asset: this test asserts
## geometry, not colour, and the real palette lives in host content this addon must run without.
func _stub_palette() -> Image:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for x in range(16):
		var v := float(x) / 15.0
		img.set_pixel(x, 0, Color(v, v, v, 1.0))
	return img
