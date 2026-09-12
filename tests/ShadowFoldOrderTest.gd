extends Node
# test-kind: logic
# seeded-break: set `const FOLD_RANK := 0` in src/units/UnitShadow.gd — the same-bucket arm reds
# ("a tied bucket is BROKEN by the rank" got the two keys equal, want shadow > tile), while every
# separated-bucket arm stays green, which is what shows the rank is the thing carrying the tie and
# not decoration. Alternatively delete `compositor_layer` from the render_mode of
# assets/shaders/shadow_blob_fold.gdshader and the contract arm reds instead, with the ordering
# arms untouched — the two halves of this test fail independently.
## The unit shadow's DISPLAY-SPACE FOLD ORDER — that the blob composites AFTER the additive
## ground decals it overlaps (ADR-0074, ADR-0009).
##
## WHY THIS IS A TEST AND NOT A COMMENT. PSX blends in the 8-bit display framebuffer with a
## per-step clamp, and a clamp is NOT commutative. The cursor tile adds; the shadow subtracts.
##
##     add then sub:  clamp(clamp(ground + tile) - shadow)  ->  255 - shadow   (blob visible)
##     sub then add:  clamp(clamp(ground - shadow) + tile)  ->  255            (blob ERASED)
##
## Both spellings are one line apart in fold order, and the wrong one does not error, log, or
## look broken anywhere except on the pixels under a unit standing on the cursored tile. So the
## order is asserted here rather than eyeballed.
##
## The order itself is not a new mechanism — it is what the ROM does. The tile panel is a prim at
## the TILE's ordering-table slot; the shadow packet goes in at the UNIT's own slot
## (`ot_base + unit[0x128]*4`, FUN_8007d5d0), which is one bucket nearer; the OT paints
## back-to-front, so the panel lands first. Our two keys reproduce exactly that: the tile decal
## stamps its centroid in STANDARD mode, the shadow stamps the UNIT's representative point in
## SHADOW mode. See research/working_documents/UNIT_SHADOW_RENDERING.md §2.
##
## The arms:
##   1. The fold twin exists and IS a fold (compositor_layer + blend_sub), the in-scene twin is
##      NOT, and both write the same subtraction — a pair, not a fork.
##   2. UnitShadow picks between them on the build predicate, never by path.
##   3. A unit standing on the cursored tile sorts its shadow into a NEARER bucket, so the key is
##      strictly greater and the shadow paints last.
##   4. When the two land in the SAME bucket — the degenerate case, and the one nothing else
##      guards — FOLD_RANK is what breaks the tie, and with rank 0 the two keys would be EQUAL
##      (undefined order). Both directions asserted, because "greater" is also true of a rank
##      that never mattered.
##   5. The cursor tile is still the ADDITIVE, textured, routed type this order exists for. If it
##      goes back to opaque/in-scene the ordering above is moot, and this arm says so out loud.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ShadowFoldOrderTest.tscn

const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold
const CellMarking = ExMateriaSchema.CellMarking
const TileOverlayConfig = ExMateriaBattlefield.TileOverlayConfig
# By path: the compositor is an addon INTERNAL (the façade does not publish it), and the two
# constants below are half the claim — the mode and the rank the tile decal actually stamps.
# Naming them beats restating them as literals, which is how a test goes green against a value
# nobody kept.
const TileOverlayCompositor = preload("res://addons/exmateria_battlefield/overlay/TileOverlayCompositor.gd")

var _passed := 0
var _failed := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		print("[FAIL] %s" % msg)
		_failed += 1


func _ready() -> void:
	_test_the_fold_twin_is_a_pair()
	_test_the_shader_pick_is_the_build_predicate()
	_test_the_shadow_outranks_the_decal_it_overlaps()
	_test_the_cursor_tile_is_the_additive_routed_type()

	print("\n=== ShadowFoldOrderTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0:
		print("[FAIL] ShadowFoldOrderTest: ran zero assertions")
	elif _failed:
		print("[FAIL] ShadowFoldOrderTest")
	else:
		print("[PASS] ShadowFoldOrder: fold twin + build-predicate pick + shadow paints AFTER the additive tile it overlaps (bucket, and rank on a tie)")
	get_tree().quit()


## Arm 1 — the twins are a PAIR: same subtraction, one of them folded.
func _test_the_fold_twin_is_a_pair() -> void:
	var fold_src := FileAccess.get_file_as_string(UnitShadow.SHADOW_FOLD_SHADER.resource_path)
	var scene_src := FileAccess.get_file_as_string(UnitShadow.SHADOW_SCENE_SHADER.resource_path)
	_check(not fold_src.is_empty() and not scene_src.is_empty(), "both shadow shaders readable")
	_check(_declares_fold(fold_src), "shadow_blob_fold declares compositor_layer (it routes into the scratch)")
	_check(not _declares_fold(scene_src), "shadow_blob does NOT — it is the off-fork fallback")
	_check("compositor-exempt: off-fork-fallback" in scene_src,
		"and says so in the marker the routing scoreboard verifies against the twin")
	# The same blend and the same write on both sides: a twin that drifted would be a second
	# shadow implementation, which is the thing a `_fold` suffix promises it is not.
	for pair in [["blend_sub", "PSX ABR mode 2"], ["ALBEDO = t.rgb * intensity;", "the subtraction amount"],
			["DEPTH = ot_computed_depth;", "the ADR-0009 depth seam"]]:
		_check(pair[0] in fold_src and pair[0] in scene_src,
			"both twins carry %s (%s)" % [pair[0], pair[1]])


## Arm 2 — which twin is worn is the BUILD predicate, not a path or a version sniff.
func _test_the_shader_pick_is_the_build_predicate() -> void:
	var picked: Shader = Fold.shader(UnitShadow.SHADOW_FOLD_SHADER, UnitShadow.SHADOW_SCENE_SHADER)
	var want: Shader = UnitShadow.SHADOW_FOLD_SHADER if Fold.owns() else UnitShadow.SHADOW_SCENE_SHADER
	_check(picked == want, "Fold.shader picks the %s twin on this build" % ("fold" if Fold.owns() else "in-scene"))
	_check(UnitShadow.SHADOW_FOLD_SHADER != UnitShadow.SHADOW_SCENE_SHADER, "the two consts are two shaders")
	# Still behind the sprite: routing the shadow must not have promoted it past the unit it
	# belongs to. The invariant that survives the change is worth an assertion too.
	_check(DepthMode.SHADOW_FORWARD < DepthMode.UNIT_FORWARD,
		"SHADOW_FORWARD (%f) stays behind UNIT_FORWARD (%f) — the sprite still wins the overlap"
			% [DepthMode.SHADOW_FORWARD, DepthMode.UNIT_FORWARD])


## Arms 3+4 — the order key itself.
func _test_the_shadow_outranks_the_decal_it_overlaps() -> void:
	# A camera above and in front, looking at the origin: the isometric case, where a point
	# HIGHER in Y is nearer the camera. view = world -> view, as every producer computes it.
	var cam := Transform3D(Basis(), Vector3(0.0, 10.0, 10.0)).looking_at(Vector3.ZERO, Vector3.UP)
	var view: Transform3D = cam.affine_inverse()

	# The cursored tile the unit stands on: its lifted centroid, stamped STANDARD / rank 0 by
	# TileOverlayCompositor. The unit's representative point is the sprite's, ~half a tile up.
	var tile_centroid := Vector3(0.0, TileOverlayCompositor.DECAL_LIFT, 0.0)
	var unit_point := Vector3(0.0, 0.5, 0.0)
	var tile_key := DepthMode.render_layer_order_for(
		DepthMode.ot_order_z(tile_centroid, view, TileOverlayCompositor.TILE_DEPTH_MODE), 0)
	var shadow_key := DepthMode.render_layer_order_for(
		DepthMode.ot_order_z(unit_point, view, DepthMode.Mode.SHADOW), UnitShadow.FOLD_RANK)
	_check(shadow_key > tile_key,
		"the shadow's key (%d) is greater than the tile's (%d) — it paints LAST, so the subtraction lands on top of the addition"
			% [shadow_key, tile_key])

	# Arm 4: the DEGENERATE case. Force both keys into ONE bucket (identity view, points chosen so
	# the SHADOW nudge does not cross a bucket boundary: -1.00 and -0.95 both round to bucket -5 at
	# the 0.19 world-unit width). Nothing else in the tree guards this, and it is the case a flat
	# map with a low camera actually produces.
	var flat := Transform3D()
	var tied := Vector3(0.0, 0.0, -1.0)
	var tied_tile_z := DepthMode.ot_order_z(tied, flat, DepthMode.Mode.STANDARD)
	var tied_shadow_z := DepthMode.ot_order_z(tied, flat, DepthMode.Mode.SHADOW)
	var same_bucket: bool = (int(round(tied_tile_z / DepthMode.UNITS_PER_OT_BUCKET))
		== int(round(tied_shadow_z / DepthMode.UNITS_PER_OT_BUCKET)))
	_check(same_bucket, "the fixture really does put both prims in ONE bucket (else arm 4 proves nothing)")
	var tied_tile_key := DepthMode.render_layer_order_for(tied_tile_z, 0)
	_check(DepthMode.render_layer_order_for(tied_shadow_z, UnitShadow.FOLD_RANK) > tied_tile_key,
		"a tied bucket is BROKEN by the rank — the shadow still paints after")
	_check(DepthMode.render_layer_order_for(tied_shadow_z, 0) == tied_tile_key,
		"and with rank 0 the two keys are EQUAL — the rank is load-bearing, not decoration")


## Arm 5 — the prim this order exists to sit behind.
func _test_the_cursor_tile_is_the_additive_routed_type() -> void:
	var cursor: int = CellMarking.Kind.CURSOR_ACTIVE
	_check(int(TileOverlayConfig.get_param(cursor, "blend_mode")) == 1,
		"the active-cursor tile is ADDITIVE (PSX tpage 0x3F / ABR mode 1), not opaque")
	_check(not bool(TileOverlayConfig.get_param(cursor, "flat_fill")),
		"and it is the TEXTURED overlay — it samples the RANGETILE sheet, so it folds on its own carrier")
	_check(TileOverlayCompositor.is_routed(cursor), "so it ROUTES through the display-space fold")
	_check(TileOverlayCompositor.is_textured(cursor), "on the textured carrier, which is the one with its own order key")


func _declares_fold(src: String) -> bool:
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*render_mode\\b[^;]*\\bcompositor_layer\\b")
	return re.search(src) != null
