extends RefCounted

static func create_palette_texture(palettes_data: Dictionary) -> ImageTexture:
	"""Generate a 16x32 palette texture from palette JSON data.

	Args:
		palettes_data: Dictionary with 'palettes' and 'animation_frames' arrays

	Returns:
		ImageTexture containing all palettes (16x32 RGBA8)
	"""
	# Validate input
	if not palettes_data.has("palettes") or not palettes_data.has("animation_frames"):
		push_error("Invalid palettes_data structure")
		return null

	var palettes = palettes_data.palettes
	var animation_frames = palettes_data.animation_frames

	if palettes.size() != 16:
		push_error("Expected 16 palettes, got %d" % palettes.size())
		return null

	# Create 16x32 image (16 colors wide, 32 palette rows tall)
	var img = Image.create(16, 32, false, Image.FORMAT_RGBA8)

	# Fill rows 0-15: Base palettes
	for palette_id in range(16):
		var palette = palettes[palette_id]

		if not palette.has("colors") or palette.colors.size() != 16:
			push_error("Palette %d doesn't have 16 colors" % palette_id)
			return null

		for color_id in range(16):
			var color_data = palette.colors[color_id]
			var color = Color8(
				color_data.r,
				color_data.g,
				color_data.b,
				color_data.a
			)
			img.set_pixel(color_id, palette_id, color)

	# Fill rows 16-31: Animation frames (or copy base palettes if no animation)
	for frame_id in range(16):
		var frame = null
		if frame_id < animation_frames.size():
			frame = animation_frames[frame_id]

		if frame != null and frame.has("colors") and frame.colors.size() == 16:
			# Use actual animation frame
			for color_id in range(16):
				var color_data = frame.colors[color_id]
				var color = Color8(
					color_data.r,
					color_data.g,
					color_data.b,
					color_data.a
				)
				img.set_pixel(color_id, 16 + frame_id, color)
		else:
			# No animation frame - copy base palette
			var palette = palettes[frame_id]
			for color_id in range(16):
				var color_data = palette.colors[color_id]
				var color = Color8(
					color_data.r,
					color_data.g,
					color_data.b,
					color_data.a
				)
				img.set_pixel(color_id, 16 + frame_id, color)

	# Create texture from image
	var texture = ImageTexture.create_from_image(img)

	# Set texture flags for pixel-perfect sampling
	# (No mipmaps, no filter - we want exact pixel values)
	# In Godot 4, this is handled automatically for small textures

	return texture


static func save_palette_texture_debug(texture: ImageTexture, path: String) -> bool:
	"""Save palette texture as PNG for visual inspection.
	Useful for debugging palette issues.
	"""
	var img = texture.get_image()
	var error = img.save_png(path)

	if error == OK:
		print("Saved palette texture debug image: %s" % path)
		return true
	else:
		push_error("Failed to save palette texture: error %d" % error)
		return false
