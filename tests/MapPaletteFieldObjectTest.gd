extends Node
## Tests for the PALETTE variety of event-script {55} Use Field Object — the
## `kind:"palette"` slots that swap a base map palette to a cycling sequence of
## animation-frame palettes (PSX texture-animation mode_byte 0x0D). The UV
## (texture-blit / door) variety is covered by MapTextureAnimatorTest; this file
## covers the palette-swap variety that MAP104 (Beoulve Residence) uses for the
## "Balbanes's Death" lighting fade (scenario 14 PC 254-256, Field Objects 0/1/2).
##
## Ground truth is static: MAP104 slots 0/1/2 are ForwardOnceOnTrigger palette
## animations (overridden_palette_id 4/5/6, animation_start_index 0/4/8, 4 frames
## x 15 ticks) whose animation frames progressively DIM the room's lighting
## palettes. The palette texture is 16x32 (PaletteTextureGenerator): base row
## `y = palette_id`, animation row `y = 16 + frame_id`; the map shader samples the
## base row by the polygon's palette_id, so playing a palette field object means
## blitting animation row (16 + start_index + frame) into base row
## overridden_palette_id of a mutable palette texture.
##
## Run: "$GODOT" --path . --quit-after 10 res://tests/MapPaletteFieldObjectTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const MapTextureAnimator = ExMateriaBattlefield.MapTextureAnimator
const PaletteTextureGenerator = ExMateriaBattlefield.PaletteTextureGenerator


const MANIFEST_PATH := "res://assets/maps/MAP104/manifest.json"
const PALETTES_PATH := "res://assets/maps/MAP104/palettes.json"
const TEXTURE_PATH := "res://assets/maps/MAP104/texture_indexed.tga"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var slots := _load_slots()
	var pal_tex := _load_palette_texture()
	var atlas := load(TEXTURE_PATH) as Texture2D
	if slots.is_empty() or pal_tex == null or atlas == null:
		print("[FAIL] MapPaletteFieldObjectTest: missing MAP104 assets (slots=%d pal=%s atlas=%s)"
			% [slots.size(), str(pal_tex), str(atlas)])
		get_tree().quit(1)
		return

	_test_palette_opening_blit(slots, atlas, pal_tex)
	_test_palette_timing_and_hold(slots, atlas, pal_tex)

	print("\n=== MapPaletteFieldObjectTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 or _failed > 0:
		print("[FAIL] MapPaletteFieldObjectTest")
		get_tree().quit(1)
	else:
		print("[PASS] MapPaletteFieldObjectTest")
		get_tree().quit(0)


# Playing palette Field Object 0 (overridden_palette_id 4, start_index 0) must
# immediately recolor base palette row 4 to animation-frame row 0 (the opening
# frame is visible on the very first tick, mirroring the UV path).
func _test_palette_opening_blit(slots: Array, atlas: Texture2D, pal_tex: Texture2D) -> void:
	var slot: Dictionary = slots[0]
	_assert(slot.get("kind") == "palette", "slot 0 is palette kind")
	var opid := int(slot.get("overridden_palette_id", -1))
	var start := int(slot.get("animation_start_index", -1))
	_assert(opid == 4, "slot 0 overridden_palette_id == 4")
	_assert(start == 0, "slot 0 animation_start_index == 0")

	var src := pal_tex.get_image()
	# Frame-0 animation row for this slot, and the (differing) original base row —
	# sanity that the blit is meaningful (base != frame0, else it proves nothing).
	var base_before := _row(src, opid)
	var frame0 := _row(src, 16 + start + 0)
	_assert(base_before != frame0, "base row differs from frame0 (blit is meaningful)")

	var anim := MapTextureAnimator.new()
	anim.setup(slots, atlas, pal_tex)
	anim.play(0)
	_assert(anim.is_active(0), "slot 0 active after play")

	var work := anim.get_work_palette_image()
	_assert(work != null, "animator exposes a working palette image")
	if work != null:
		_assert(_row(work, opid) == frame0, "base row %d recolored to frame0 after opening blit" % opid)


# Slot 1 is a FORWARD once-on-trigger palette fade (overridden_palette_id 5,
# start_index 4, 4 frames x 15 ticks = 60 ticks). It must advance through
# intermediate frames while active, then HOLD the final (dimmed) frame on
# completion — NOT revert to the original bright base palette.
func _test_palette_timing_and_hold(slots: Array, atlas: Texture2D, pal_tex: Texture2D) -> void:
	var slot: Dictionary = slots[1]
	var opid := int(slot.get("overridden_palette_id", -1))
	var start := int(slot.get("animation_start_index", -1))
	_assert(opid == 5 and start == 4, "slot 1 is palette opid=5 start=4")

	var src := pal_tex.get_image()
	var base_original := _row(src, opid)                     # pristine bright base
	var frame_mid := _row(src, 16 + start + 1)               # 2nd frame (partway dim)
	var frame_last := _row(src, 16 + start + 3)              # final dimmed frame

	var anim := MapTextureAnimator.new()
	anim.setup(slots, atlas, pal_tex)
	anim.play(1)

	# ~20 ticks in → frame index 20/15 == 1 (an intermediate, mid-fade frame).
	for i in range(20):
		anim.tick(1.0 / 60.0)
	_assert(anim.is_active(1), "still active mid-fade (< 60 ticks)")
	_assert(_row(anim.get_work_palette_image(), opid) == frame_mid,
		"base row advanced to the mid frame while fading")

	# Past the full 60-tick duration → finished, holding the final dim frame.
	for i in range(45):
		anim.tick(1.0 / 60.0)
	_assert(not anim.is_active(1), "inactive after full 60-tick duration")
	var after := _row(anim.get_work_palette_image(), opid)
	_assert(after == frame_last, "base row holds the final dimmed frame after completion")
	_assert(after != base_original, "base row does NOT revert to the original bright palette")


# ---- helpers ----

func _row(img: Image, y: int) -> PackedByteArray:
	var out := PackedByteArray()
	for x in range(16):
		var c := img.get_pixel(x, y)
		out.append(int(round(c.r * 255.0)))
		out.append(int(round(c.g * 255.0)))
		out.append(int(round(c.b * 255.0)))
		out.append(int(round(c.a * 255.0)))
	return out


func _load_slots() -> Array:
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return []
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var anims: Dictionary = data.get("animations", {})
	return anims.get("texture_animations", [])


func _load_palette_texture() -> Texture2D:
	var f := FileAccess.open(PALETTES_PATH, FileAccess.READ)
	if f == null:
		return null
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	return PaletteTextureGenerator.create_palette_texture(data)


func _assert(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)
