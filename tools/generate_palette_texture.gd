@tool
extends EditorScript

## Tool script to pre-generate palette texture as PNG
## Run this in Godot Editor: File > Run > generate_palette_texture.gd

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const PaletteTextureGenerator = ExMateriaBattlefield.PaletteTextureGenerator


# `PaletteTextureGenerator` is named as a TYPE — ADR-0208 dec. 2 + dec. 3 + dec. 4. The
# const that preloaded it by path is deleted; the name is published, so the call sites
# below are unchanged. An `@tool EditorScript` never ships, and like any standalone entry
# point it has no mount available to it.

func _run():
	print("Generating palette texture from MAP022 palettes.json...")

	# Load palettes data
	var palettes_path = "res://assets/doodads/MAP022/palettes.json"
	var file = FileAccess.open(palettes_path, FileAccess.READ)
	if not file:
		push_error("Failed to open palettes.json")
		return

	var json_text = file.get_as_text()
	file.close()

	var palettes_data = JSON.parse_string(json_text)
	if not palettes_data:
		push_error("Failed to parse palettes.json")
		return

	# Generate palette texture
	var palette_texture = PaletteTextureGenerator.create_palette_texture(palettes_data)
	if not palette_texture:
		push_error("Failed to create palette texture")
		return

	# Save as PNG
	var output_path = "res://assets/doodads/MAP022/palette_texture.png"
	var success = PaletteTextureGenerator.save_palette_texture_debug(palette_texture, output_path)

	if success:
		print("✓ Palette texture saved to: %s" % output_path)
		print("  Now restart Godot to import it, then update DynamicGeometryBuilder to load it")
	else:
		push_error("Failed to save palette texture")
