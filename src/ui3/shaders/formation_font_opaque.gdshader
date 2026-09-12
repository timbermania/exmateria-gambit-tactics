shader_type spatial;
// OPAQUE depth-writing variant of ui_font_char.gdshader for the FORMATION info-panel
// proportional text (name / job / "Brave" / "Faith"). ADR-0077: the panel sits on the
// folded subtractive band, so its glyphs must be OPAQUE + depth-writing (write depth
// from their ladder rung) to occlude the band instead of being clobbered by Pass C.
// Same FONT.BIN atlas sampling + nearest-colour palette remap as ui_font_char; the
// ONLY differences: opaque render_mode (writes depth), the transparent-key texels
// `discard`, and ALPHA is NEVER assigned (assigning it opts into the transparent
// pipeline, which skips the depth write). Stroke is dropped (the info panel is
// dark ink on tan — no outline).
render_mode unshaded, cull_disabled;

uniform sampler2D font_atlas : filter_nearest, repeat_disable;   // NO source_color (sRGB atlas)
uniform vec4 char_region;                                         // atlas px: x, y, w, h
uniform vec2 atlas_size;
uniform vec4 font_color = vec4(1.0);

// Palette remap by nearest baked atlas colour (the OFF-WHITE ramp: slots 1/2/3).
// The info panel drives dark ink: palette_light/mid/dark set to a dark-brown ramp.
uniform bool use_palette = false;
uniform vec4 palette_dark = vec4(0.3216, 0.3216, 0.2902, 1.0);   // atlas slot 3 (82,82,74)
uniform vec4 palette_mid = vec4(0.6118, 0.6118, 0.5804, 1.0);    // atlas slot 2 (156,156,148)
uniform vec4 palette_light = vec4(0.9333, 0.9333, 0.9020, 1.0);  // atlas slot 1 (238,238,230)

// Box-open scissor (DetailScene §15.17): the stats-band dot-leaders drawn through this shader
// are revealed through the growing window aperture. `clip_world` is that aperture in WORLD
// space (xy = min, zw = max); default unbounded ⇒ the formation info-panel text that shares
// this shader is byte-identical (it never sets it). See DetailScene.set_open_frame.
uniform vec4 clip_world = vec4(-1e20, -1e20, 1e20, 1e20);
// The SCREEN's inverse global transform. `clip_world` is an axis-aligned rect in the SCREEN's own
// space (display px * ppu), but MODEL_MATRIX * VERTEX is GLOBAL — the two only coincide while the
// screen root happens to sit at the world origin, unrotated and unscaled. That held for as long as
// every UI3 screen had its own camera; it stops holding the moment a screen mounts as a CHILD of
// the map's camera (ADR-0137), where the UI plane is rotated and scaled in world space and every
// clipped fragment silently falls outside the box. Mapping the fragment back into screen space
// first makes the comparison space-correct on any host. Identity default ⇒ unchanged where the
// screen already is the origin.
uniform mat4 clip_basis_inv = mat4(1.0);
varying vec3 v_world;

void vertex() {
	v_world = (clip_basis_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (v_world.x < clip_world.x || v_world.y < clip_world.y
			|| v_world.x > clip_world.z || v_world.y > clip_world.w) {
		discard;  // outside the box-open aperture (§15.17 scissor reveal)
	}
	vec2 char_px = char_region.xy + UV * char_region.zw;
	vec2 texel = (floor(char_px) + 0.5) / atlas_size;
	vec4 color = texture(font_atlas, texel);

	if (color.a < 0.5) {
		discard;  // glyph background — opaque via alpha-test, no ALPHA write
	}

	if (use_palette) {
		float d_dark = distance(color.rgb, vec3(0.3216, 0.3216, 0.2902));
		float d_mid = distance(color.rgb, vec3(0.6118, 0.6118, 0.5804));
		float d_light = distance(color.rgb, vec3(0.9333, 0.9333, 0.9020));
		if (d_dark <= d_mid && d_dark <= d_light) {
			color = palette_dark;
		} else if (d_mid <= d_light) {
			color = palette_mid;
		} else {
			color = palette_light;
		}
	}

	vec3 final_color = color.rgb * font_color.rgb;
	// sRGB → linear for Forward+ (Godot re-encodes to sRGB for display), matching ui_font_char.
	ALBEDO = pow(final_color, vec3(2.2));
	// Do NOT assign ALPHA (ADR-0077): keeps this in the opaque pass so it writes depth.
}
