class_name MapRenderDebugPanel
extends BaseDebugPanel

## Debug panel for the map's indexed_color render tunables (ADR-0068). Two seam fixes:
## (1) Atlas edge-padding ("Dilate passes") — bleed opaque terrain indices into transparent
## border texels so a covered edge fragment samples real terrain, not a hole. (2) Perimeter-
## aware UV snap ("Centroid pull / Perimeter exponent / Offset X/Y") — nudge each fragment's
## sample toward its triangle's UV centroid (the 3 UV verts ride in CUSTOM2/3), scaled by
## perimeter-closeness, plus a global texel offset, for opaque neighbor-patch bleed.
##
## MapComposer OWNS the values: register_tunables() binds each slug (the single static-var
## home) and each live instance's on_update pushes the shader uniform onto every map material
## (decision 12), so this panel is just a VIEW — a committed override applies at boot in any
## scene, not only while the panel is open. All snap defaults are identity (centroid 0) so the
## snap is off until dialed.
##
## ONE ROW HAS A DIFFERENT OWNER. "PSX framebuffer snap" is `render.psx_dither_enabled`, bound
## by DebugConfig (whose `_apply_dither` pushes the GLOBAL shader uniform, not a per-material
## one) with its default sourced from project.godot [shader_globals]. It sits here because
## this is where you are when you can see its effect, and it is still a pure view row — the
## owner is elsewhere, this file names only the slug.

const TuneField = preload("res://src/debug/TuneField.gd")

# Pure VIEW (ADR-0068 R1 + decision 12): the slug names, scrubbable static-var defaults, and
# hints are OWNED by MapComposer (the production owner that binds/reads/pushes them). This
# panel only names the slugs as strings and reads default+hint back from the Tune registry —
# nothing production depends on. See MapComposer._uv_snap_* / _atlas_dilate_passes_default,
# and DynamicGeometryBuilder._water_waves_default for the "Water" row.


func setup() -> void:
	panel_title = "Map Render"
	panel_category = Category.SHADERS
	_build_ui()


func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(280, 0)
	add_child(vbox)

	add_section_title(vbox, "Water")
	# OFF by default. The sine vertex displacement is an invention — FFT's water moves by
	# cycling its CLUT (the map manifest's palette animations), not by deforming geometry.
	# Owned by DynamicGeometryBuilder; this row names only the slug (ADR-0068 R1).
	TuneField.add(vbox, "Wave displacement", "map.water_waves")

	add_separator(vbox)
	add_section_title(vbox, "Atlas edge-padding (seam fix)")
	TuneField.add(vbox, "Dilate passes", "map.atlas_dilate_passes")

	add_separator(vbox)
	add_section_title(vbox, "Perimeter snap (neighbor bleed)")
	TuneField.add(vbox, "Centroid pull (texels)", "map.uv_snap_centroid")
	add_separator(vbox)
	TuneField.add(vbox, "Perimeter exponent", "map.uv_snap_perimeter")
	add_separator(vbox)
	TuneField.add(vbox, "Offset X (texels)", "map.uv_snap_offx")
	add_separator(vbox)
	TuneField.add(vbox, "Offset Y (texels)", "map.uv_snap_offy")

	add_separator(vbox)
	add_section_title(vbox, "PSX framebuffer")
	# The last thing the real GPU does before the pixel lands in VRAM: 4x4 ordered dither
	# then truncate to 15-bit. ON by default. One toggle covers BOTH halves — the include
	# early-returns un-quantized when it is off — which is the coupling #183 objects to; if
	# that ticket ever splits them this row becomes two.
	#
	# NOT MapComposer's slug (see the header): DebugConfig owns it and pushes a global
	# uniform, so this toggle also moves the battle background gradient, which is the other
	# surface the real console dithers. The map terrain, the background, and nothing else.
	TuneField.add(vbox, "PSX dither + 15-bit snap", "render.psx_dither_enabled")
