shader_type spatial;
// The ownership-map DEBUG material (ADR-0088 Amendment 6 §2): faithful false-color for
// a UI payload mesh WITHOUT editing its production shader. While the map is active, an
// owned mesh's material_override is swapped to a per-mesh instance of THIS shader (the
// original is restored on exit — see UI3OwnerColorMap). It samples the mesh's OWN shape
// so glyphs stay glyph-shaped and frames/bands fill their rect, and uses normal blend
// (an opaque alpha-test, exactly like the formation glyph originals) so the on-screen
// color matches the page's swatch even for add/sub fold members — the whole point of a
// swap over a per-shader tint.
render_mode unshaded, cull_disabled;

// Unified PSX Ordering-Table depth (ADR-0009) so swapped meshes still sort sanely on
// the flat ortho UI. TILE_OVERLAY rung; local per-face centroid in CUSTOM0.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

// The element's owner color (or the reserved ALARM color for unowned payload).
uniform vec4 owner_color : source_color = vec4(1.0, 0.0, 1.0, 1.0);

// Shape source:
//   0 = solid quad — the shape IS the rect (frames, bands, orbs, boxes, solid fills);
//       the map WANTS the whole claimed region filled with the owner color.
//   1 = glyph atlas — sample the paletted index atlas for the true glyph silhouette
//       (mirrors formation_text_opaque: cell region, index 0 = transparent key).
uniform int shape_mode = 0;
uniform sampler2D index_atlas : filter_nearest, repeat_disable;
uniform vec4 cell = vec4(0.0, 0.0, 8.0, 8.0);      // atlas px: x, y, w, h
uniform vec2 atlas_size = vec2(256.0, 256.0);

// World-space aperture, copied from the payload so apertured (box-open) content stays
// clipped under the map (xy = min, zw = max; default unbounded).
uniform vec4 clip_world = vec4(-1e20, -1e20, 1e20, 1e20);
// The SCREEN's inverse global transform — see UI3ClipEngine.clip_basis_inv_for. `clip_world` is an
// axis-aligned rect in the SCREEN's space (display px * ppu) while MODEL_MATRIX * VERTEX is GLOBAL;
// the two coincide only while the screen root sits at the world origin, which stops being true the
// moment a screen mounts under the map's camera (ADR-0137). Identity default ⇒ unchanged elsewhere.
uniform mat4 clip_basis_inv = mat4(1.0);
varying vec3 v_world;

void vertex() {
	v_world = (clip_basis_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ot_computed_depth = ot_depth(CUSTOM0.xyz, PROJECTION_MATRIX, MODELVIEW_MATRIX, 7);
}

void fragment() {
	if (v_world.x < clip_world.x || v_world.y < clip_world.y
			|| v_world.x > clip_world.z || v_world.y > clip_world.w) {
		discard;  // outside the box-open aperture — stay clipped under the map
	}
	if (shape_mode == 1) {
		vec2 px = cell.xy + UV * cell.zw;
		vec2 texel = (floor(px) + 0.5) / atlas_size;
		int idx = int(floor(texture(index_atlas, texel).r * 15.0 + 0.5));
		if (idx == 0) {
			discard;  // index 0 is the transparent key — keep the true glyph shape
		}
	}
	ALBEDO = owner_color.rgb;
	DEPTH = ot_computed_depth;
	// Opaque via alpha-test (do NOT assign ALPHA): keeps depth-write like the glyph
	// originals, so overlapping owner rects sort by their depth rung.
}
