shader_type spatial;
// OPAQUE depth-writing variant of nine_slice_3d.gdshader for the FORMATION info
// panel (ADR-0077). The panel's tan 9-slice frame sits on the full-width
// SUBTRACTIVE gouraud band (§14.6.6, a fold member on the 4.8 fork). To occlude
// the folded band beneath it — instead of being clobbered by Pass C's coverage
// discard — the frame must be OPAQUE and write DEPTH from its ladder rung. This is
// the same trick formation_text_opaque uses for the sort-value glyphs: the
// transparent-key texels `discard`, and ALPHA is NEVER assigned (assigning it,
// even = 1.0, opts into Godot's transparent pipeline, which skips the depth write).
// Identical 9-slice sampling + uniforms to nine_slice_3d, so UIFrame drives it
// unchanged when `opaque = true`; the ONLY difference is the opaque render_mode
// (writes depth) and the dropped ALPHA assignment.
render_mode unshaded, cull_disabled;

uniform sampler2D frame_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 source_region;
uniform vec4 margins;
uniform vec2 output_size;
// Optional atlas patch (x,y,w,h) the TILED CENTER samples instead of the source_region interior;
// borders/corners/edges still come from source_region. ZERO (default) ⇒ off (byte-identical).
uniform vec4 center_region = vec4(0.0);

// §15.21 "send window to background": exact nearest-index CLUT remap 0x7C3C→0x7D3C in DISPLAY space.
// palette_count 0 (default) ⇒ every other caller (formation info panel) byte-identical.
uniform vec3 fg_palette[16];
uniform vec3 bg_palette[16];
uniform int palette_count = 0;
uniform float backgrounded = 0.0;

// Box-open scissor (DetailScene §15.17): the detail-screen box-open reveals the
// fully-rendered window through a growing rectangular aperture (the frame chrome
// appears only once the aperture reaches the panel edges). `clip_world` is that
// aperture in WORLD space (xy = min, zw = max); default unbounded ⇒ every other
// caller (formation info panel) is byte-identical. See DetailScene.set_open_frame.
uniform vec4 clip_world = vec4(-1e20, -1e20, 1e20, 1e20);
// The SCREEN's inverse global transform — see UI3ClipEngine.clip_basis_inv_for. `clip_world` is an
// axis-aligned rect in the SCREEN's space (display px * ppu) while MODEL_MATRIX * VERTEX is GLOBAL;
// the two coincide only while the screen root sits at the world origin, which stops being true the
// moment a screen mounts under the map's camera (ADR-0137). Identity default ⇒ unchanged elsewhere.
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
	vec2 out_px = UV * output_size;

	float src_w = source_region.z;
	float src_h = source_region.w;

	float m_left = margins.x;
	float m_right = margins.y;
	float m_top = margins.z;
	float m_bottom = margins.w;

	float src_inner_left = m_left;
	float src_inner_right = src_w - m_right;
	float src_inner_top = m_top;
	float src_inner_bottom = src_h - m_bottom;

	float out_inner_left = m_left;
	float out_inner_right = output_size.x - m_right;
	float out_inner_top = m_top;
	float out_inner_bottom = output_size.y - m_bottom;

	vec2 src_px;

	if (out_px.x < out_inner_left) {
		src_px.x = out_px.x;
	} else if (out_px.x >= out_inner_right) {
		src_px.x = src_inner_right + (out_px.x - out_inner_right);
	} else {
		float center_src_w = src_inner_right - src_inner_left;
		src_px.x = src_inner_left + mod(out_px.x - out_inner_left, center_src_w);
	}

	if (out_px.y < out_inner_top) {
		src_px.y = out_px.y;
	} else if (out_px.y >= out_inner_bottom) {
		src_px.y = src_inner_bottom + (out_px.y - out_inner_bottom);
	} else {
		float center_src_h = src_inner_bottom - src_inner_top;
		src_px.y = src_inner_top + mod(out_px.y - out_inner_top, center_src_h);
	}

	vec2 atlas_size = vec2(textureSize(frame_texture, 0));
	vec2 atlas_px = source_region.xy + floor(src_px) + 0.5;
	// Center override: in BOTH the tiled center columns AND rows, tile the separate center_region
	// patch instead of the source_region interior (borders/edges unaffected).
	bool in_center_x = out_px.x >= out_inner_left && out_px.x < out_inner_right;
	bool in_center_y = out_px.y >= out_inner_top && out_px.y < out_inner_bottom;
	if (in_center_x && in_center_y && center_region.z > 0.0) {
		float cx = mod(out_px.x - out_inner_left, center_region.z);
		float cy = mod(out_px.y - out_inner_top, center_region.w);
		atlas_px = center_region.xy + floor(vec2(cx, cy)) + 0.5;
	}
	vec2 atlas_uv = atlas_px / atlas_size;

	vec4 color = texture(frame_texture, atlas_uv);
	if (color.a < 0.5) {
		discard;  // the atlas transparent key — opaque via alpha-test, no ALPHA write
	}
	vec3 rgb = color.rgb;   // linear (source_color decoded)
	if (backgrounded > 0.5 && palette_count > 0) {
		vec3 disp = pow(rgb, vec3(1.0 / 2.2));   // linear → display, to match palette entries
		int best = 0; float bd = 1e9;
		for (int i = 0; i < 16; i++) {
			if (i >= palette_count) { break; }
			vec3 d = disp - fg_palette[i];
			float q = dot(d, d);
			if (q < bd) { bd = q; best = i; }
		}
		rgb = pow(max(bg_palette[best], vec3(0.0)), vec3(2.2));  // display → linear
	}
	ALBEDO = rgb;
	// Do NOT assign ALPHA (ADR-0077): keeps this in the opaque pass so it writes depth.
}
