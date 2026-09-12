shader_type spatial;
// FOLD twin of menu_cursor_shadow.gdshader — the SUBTRACTIVE half of a mixed-STP PSX primitive,
// routed through the engine-fold display-space scratch instead of blending in-scene.
//
// WHY A FOLD TWIN EXISTS AT ALL (this is the whole point): PSX subtracts in the 8-bit FRAMEBUFFER,
// i.e. in DISPLAY (gamma-encoded) space. Godot's Forward+ main target is LINEAR, so an in-scene
// `blend_sub` subtracts a display-magnitude constant from a linear value — the units do not match,
// and the error grows with the background's brightness (measured: up to 34/255 on the dialogue
// page-turn icon's tan, worst on the darkest channel). The fold is what the engine-fold pipeline
// was built to solve (ADR-0074):
//     Pass A (POST_OPAQUE)     seed    = opaque scene colour → DISPLAY
//     Pass B (ENGINE)          fold    = these prims, hardware add/sub — IN DISPLAY SPACE
//     Pass C (PRE_TRANSPARENT) resolve = display → linear + RGB555
// so a folded `blend_sub` IS the ROM's abr=2, byte for byte, and Pass C's RGB555 quantise matches
// the PSX 15-bit framebuffer too. That is why this file passes the raw CLUT colour with NO `pow`:
// inside the scratch the values are already display-space. (The in-scene twin cannot be made exact
// by any constant — byte-space subtraction is not a constant offset in linear light — which is
// what the `pow(psx_gamma)` in formation_box_sub is approximating rather than solving.)
//
// PRECONDITION for a caller: whatever this subtracts FROM must be in the fold's seed, i.e. drawn
// OPAQUE. A transparent backdrop is not in Pass A's seed and the subtraction would eat the wrong
// pixels. DialogueBox sets `UIFrame.opaque = true` for exactly this reason (the formation info
// panel already did the same for its folded band).
//
// psx-ot-depth-exempt: screen-space ortho UI quad — `fold_depth` is the rung-Z the carrier already
// sits at, NOT a battle-OT CUSTOM0 centroid (ADR-0077).
// psx-prim: textured — samples the RANGETILE index atlas through a 16-colour CLUT.
// ADR-0074 color-math clause; `brightness` is the gouraud knob (1.0 = PSX identity).
render_mode unshaded, cull_disabled, depth_draw_never, blend_sub, compositor_layer;

uniform sampler2D index_atlas : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;   // 16x1 CLUT row

uniform vec4 cell = vec4(0.0, 0.0, 16.0, 16.0);   // atlas px: x, y, w, h
uniform vec2 atlas_size = vec2(256.0, 256.0);
uniform float brightness = 1.0;

varying float fold_depth;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = clip;
	fold_depth = clip.z / clip.w;
}

void fragment() {
	vec2 px = cell.xy + UV * cell.zw;
	vec2 texel = (floor(px) + 0.5) / atlas_size;
	int idx = int(floor(texture(index_atlas, texel).r * 15.0 + 0.5));
	if (idx == 0) {
		discard;  // index 0 is the transparent key everywhere in the atlas
	}
	vec4 c = texture(palette_tex, vec2((float(idx) + 0.5) / 16.0, 0.5));
	if (c.a < 0.004) {
		discard;  // fully-transparent CLUT entry
	}
	// Keep STP=1 ONLY — the complement of vitals_sprite's `c.a < 0.9` opaque key, so the two
	// passes PARTITION a mixed-STP palette and never cover the same texel. Mirrors the in-scene twin.
	if (c.a > 0.9) {
		discard;
	}
	// Display-space subtrahend: the raw CLUT colour IS the ROM's per-channel subtract amount. NO pow.
	ALBEDO = clamp(c.rgb * brightness, vec3(0.0), vec3(1.0));
	ALPHA = 1.0;
	DEPTH = fold_depth;
}
