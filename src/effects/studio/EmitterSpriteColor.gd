extends RefCounted
## The per-emitter REPRESENTATIVE sprite colour — the base colour an effect particle's
## colour curve is MULTIPLIED against at render time (effect_particle_opaque.gdshader:
## `ALBEDO = col.rgb * COLOR.rgb`, where `col` is the RGBA-baked texture.tga texel and
## `COLOR.rgb` is the colour-curve modulate). The Colour ribbon muxes this in so its
## read-out equals the rendered particle instead of the pure curve colour — otherwise a
## green-only sprite (E138 idx0: R=0/B=0) reads red/orange on the ribbon yet renders green,
## because a multiply can only scale each channel, never add one the sprite lacks.
##
## The representative is the peak-luma VISIBLE texel across the framesets the emitter's
## `anim_index` animation actually visits: `effect_data.animations[anim_index]` FRAME
## opcodes give the relative frameset indices, `frameset_group_offset[anim_param]` shifts
## them to absolute, and `framesets[idx].frames[*].uv` are the texture.tga regions. White
## (the identity for the ribbon's multiply) when there is no texture or the address misses,
## so a pure/asset-free projection leaves the ribbon showing the raw curve unchanged.
##
## No `class_name` (ADR-0004) — preloaded by path.

## Alpha at/above this is a visible texel (the shader discards a < 0.01); anything below is
## fully transparent sheet padding and must not vote for the representative.
const _MIN_ALPHA := 0.01


## The representative sprite colour for `emitter_index`, or white when unresolvable.
static func representative(effect_data, emitter_index: int) -> Color:
	if effect_data == null or effect_data.texture == null:
		return Color.WHITE
	if emitter_index < 0 or emitter_index >= effect_data.emitters.size():
		return Color.WHITE
	var em = effect_data.emitters[emitter_index]
	var img: Image = effect_data.texture.get_image()
	if img == null:
		return Color.WHITE
	var framesets := _animation_framesets(effect_data, int(em.anim_index), int(em.anim_param))
	var best_lum := -1.0
	var best := Color.WHITE
	var w := img.get_width()
	var h := img.get_height()
	for fs_idx in framesets:
		if fs_idx < 0 or fs_idx >= effect_data.framesets.size():
			continue
		var frameset = effect_data.framesets[fs_idx]
		if not (frameset is Dictionary):
			continue
		for frame in frameset.get("frames", []):
			var uv = frame.get("uv", {})
			var x0 := int(uv.get("x", 0))
			var y0 := int(uv.get("y", 0))
			var fw := int(uv.get("width", 0))
			var fh := int(uv.get("height", 0))
			for y in range(maxi(0, y0), mini(y0 + fh, h)):
				for x in range(maxi(0, x0), mini(x0 + fw, w)):
					var c := img.get_pixel(x, y)
					if c.a < _MIN_ALPHA:
						continue
					var lum := c.r + c.g + c.b
					if lum > best_lum:
						best_lum = lum
						best = Color(c.r, c.g, c.b, 1.0)
	return best


## The distinct absolute frameset indices the emitter's animation shows: each FRAME opcode's
## relative frameset shifted by the group's cumulative offset (the SAME derivation the sim
## does — ParticleAnimator._bake_animations + ActiveEmitter._get_group_offset).
static func _animation_framesets(effect_data, anim_index: int, anim_param: int) -> Array:
	if anim_index < 0 or anim_index >= effect_data.animations.size():
		return []
	var group_off: int = effect_data.frameset_group_offset(anim_param)
	var out := {}
	for opcode in effect_data.animations[anim_index].get("opcodes", []):
		if opcode.get("type", "") == "FRAME":
			out[int(opcode.get("frameset", 0)) + group_off] = true
	return out.keys()
