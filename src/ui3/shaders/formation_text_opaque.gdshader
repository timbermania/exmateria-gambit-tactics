shader_type spatial;
// OPAQUE depth-writing variant of vitals_sprite.gdshader for FORMATION sort-value glyphs (ADR-0077).
// The per-cell "Hp cur/max" readout sits at RP_SORT_VALUE — a NEARER depth-ladder rung than the folded
// gold box (RP_BOX_ADD/SUB). The shared vitals_sprite is depth-off (it's used by the battle HUD too, so
// it must not change); a depth-off glyph would be CLOBBERED by the box, because Pass C's coverage-discard
// overwrites any transparent prim under a folded pixel. Drawn OPAQUE here (writes DEPTH from its rung Z),
// the box's fold depth-test is occluded BEHIND the text — so "Hp 081" stays legible over the box.
// Identical sampling + uniforms to vitals_sprite (so FormationScene._mount_glyph drives it unchanged);
// the ONLY differences: opaque render_mode (writes depth) and ALPHA forced to 1 after the transparent-key
// discards (paletted glyphs are hard-edged, so no alpha blend is lost).
render_mode unshaded, cull_disabled;

uniform sampler2D index_atlas : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;   // 16x1 CLUT row
uniform sampler2D palette_bg_tex : filter_nearest, repeat_disable; // §15.21 backgrounded CLUT (default unset → never sampled unless backgrounded)
uniform float backgrounded = 0.0; // 0 = foreground palette_tex; 1 = palette_bg_tex
uniform vec4 cell = vec4(0.0, 0.0, 8.0, 8.0);    // atlas px: x, y, w, h
uniform vec2 atlas_size = vec2(256.0, 256.0);
uniform float brightness = 1.0;
// `mode` is accepted for uniform parity with vitals_sprite (_mount_glyph sets it); this variant only
// draws glyph mode 0, so it is otherwise unused.
uniform int mode = 0;

// Box-open scissor (DetailScene §15.17): stats-band number glyphs are revealed through the
// growing window aperture (clipped mid-glyph, no scaling). `clip_world` is that aperture in
// WORLD space (xy = min, zw = max); default unbounded ⇒ the formation sort-value glyphs that
// share this shader are byte-identical (they never set it). See DetailScene.set_open_frame.
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
	vec2 px = cell.xy + UV * cell.zw;
	vec2 texel = (floor(px) + 0.5) / atlas_size;
	int idx = int(floor(texture(index_atlas, texel).r * 15.0 + 0.5));
	if (idx == 0) {
		discard;  // index 0 is the transparent key everywhere in the atlas
	}
	vec2 _pc = vec2((float(idx) + 0.5) / 16.0, 0.5);
	vec4 c = (backgrounded > 0.5) ? texture(palette_bg_tex, _pc) : texture(palette_tex, _pc);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = pow(clamp(c.rgb * brightness, vec3(0.0), vec3(1.0)), vec3(2.2));
	// Do NOT assign ALPHA (ADR-0077): the transparent-key texels are already `discard`ed above, so this is
	// opaque via alpha-test. Writing ALPHA (even = 1.0) would opt into Godot's transparent pipeline, so the
	// glyph would NOT write depth — and the folded gold box would clobber it instead of being occluded behind.
}
