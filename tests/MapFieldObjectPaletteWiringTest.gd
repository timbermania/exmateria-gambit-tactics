extends Node
## Wiring tests for {55} Use Field Object palette-swap, guarding the two
## texture-binding hazards found in review of b521f26a:
##
##   1. (gate) The mutable palette work-texture must only be created — and the
##      map materials only repointed at it — when the map ACTUALLY has a
##      kind:"palette" slot. Otherwise a UV-only door map orphans its palette
##      reference the moment it plays any {55}, silently breaking a later
##      {33}/{66} field-tint commit on that map.
##
##   2. (single owner) After a palette field object plays, MapComposer.palette_texture
##      (the object {66} Commit Palette / commit_field_tint mutates) must be the
##      SAME texture the geometry samples — else the commit paints an orphaned
##      copy and never reaches the screen.
##
## Run: "$GODOT" --path . --quit-after 10 res://tests/MapFieldObjectPaletteWiringTest.tscn

## The host's declared mount for the addon's map composer (ADR-0207 dec. 1). A `.tscn`
## `ext_resource` names a path, never a `class_name`, so the mount is a SCENE — and
## `instantiate()` hands back the same unparented `Node3D` carrying `MapComposer.gd` that
## `MapComposerScript.new()` did, already named `ProceduralMap`, with `_ready` still unfired.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const DynamicGeometryBuilder = ExMateriaBattlefield.DynamicGeometryBuilder
const MapTextureAnimator = ExMateriaBattlefield.MapTextureAnimator

const ProceduralMapScene := preload("res://assets/scenes/ProceduralMap.tscn")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_no_palette_work_texture_without_palette_slot()
	_test_commit_visible_after_palette_object_plays()

	print("\n=== MapFieldObjectPaletteWiringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 or _failed > 0:
		print("[FAIL] MapFieldObjectPaletteWiringTest")
		get_tree().quit(1)
	else:
		print("[PASS] MapFieldObjectPaletteWiringTest")
		get_tree().quit(0)


# A UV-only map (doors, no palette-kind slot) must NOT produce a palette work
# texture, even when a palette texture is supplied to setup(). If it does, the
# composer repoints materials off the shared palette reference for a map that
# never palette-animates, orphaning {33}/{66} commits.
func _test_no_palette_work_texture_without_palette_slot() -> void:
	var anim := MapTextureAnimator.new()
	var uv_slots: Array = [{
		"kind": "uv",
		"animation_mode": "ForwardOnceOnTrigger",
		"frame_count": 1, "frame_duration": 1,
		"size_width": 8, "size_height": 8,
		"first_frame_x": 0, "first_frame_y": 0, "first_frame_texture_page": 0,
		"canvas_x": 0, "canvas_y": 0, "canvas_texture_page": 0,
	}]
	anim.setup(uv_slots, _dummy_atlas(), _dummy_palette())
	_assert(anim.get_work_palette_texture() == null,
		"no palette work TEXTURE for a UV-only slot list")
	_assert(anim.get_work_palette_image() == null,
		"no palette work IMAGE for a UV-only slot list")


# After a palette field object plays (which repoints the geometry at the mutable
# palette work-texture), a {66}/{33} commit_field_tint must land on that SAME
# texture — otherwise the commit paints an orphaned copy and never shows. We
# observe base row 0 (untouched by the palette blit) of the texture the geometry
# actually samples (dynamic_geo_builder.palette_texture): it must change after the
# commit.
func _test_commit_visible_after_palette_object_plays() -> void:
	var composer: Node = ProceduralMapScene.instantiate()
	var builder := DynamicGeometryBuilder.new()
	var shared_palette := _solid_palette(Color(0.8, 0.6, 0.4, 1.0))
	builder.indexed_texture = _dummy_atlas()
	builder.palette_texture = shared_palette
	composer.dynamic_geo_builder = builder
	composer.geometry_mesh = MeshInstance3D.new()
	composer.palette_texture = shared_palette          # one shared reference at load
	composer.manifest_data = {
		"animations": {"texture_animations": [{
			"kind": "palette",
			"animation_mode": "ForwardOnceOnTrigger",
			"overridden_palette_id": 4, "animation_start_index": 0,
			"frame_count": 4, "frame_duration": 15,
		}]}
	}

	composer.play_texture_animation(0)
	var sampled: Texture2D = builder.palette_texture   # now the mutable work copy
	var before := _row(sampled.get_image(), 0)

	composer.commit_field_tint(Vector3(0.5, 0.5, 0.5), Vector3.ZERO)
	var after := _row(sampled.get_image(), 0)

	_assert(before != after,
		"commit_field_tint changes the palette the geometry samples after a {55} palette object")
	composer.geometry_mesh.free()
	composer.free()


# ---- helpers ----

func _solid_palette(c: Color) -> ImageTexture:
	var img := Image.create(16, 32, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _row(img: Image, y: int) -> PackedByteArray:
	var out := PackedByteArray()
	for x in range(16):
		var c := img.get_pixel(x, y)
		out.append(int(round(c.r * 255.0)))
		out.append(int(round(c.g * 255.0)))
		out.append(int(round(c.b * 255.0)))
		out.append(int(round(c.a * 255.0)))
	return out


func _dummy_atlas() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create(256, 1024, false, Image.FORMAT_RGBA8))


func _dummy_palette() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create(16, 32, false, Image.FORMAT_RGBA8))


func _assert(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)
