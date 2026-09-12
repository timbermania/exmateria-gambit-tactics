shader_type spatial;
// CHANGE-JOB commit CYLINDER — fold variant (ADR-0077 fold member).
//
// The neon-pink striped cylinder that rings the unit through the commit cutscene
// (CHANGE_JOB_COMMIT.md §9): 64 semi-transparent GOURAUD LINES on a computed rcos/rsin ring,
// each a vertical bar that fades in from the screen top, peaks magenta just above the unit and
// fades out below it. `[dynamic]` the emitted packets read code byte 0x52 = LINE_G2 | ABE, and
// the DR_TPAGE in OT slot 0x37 carries **ABR 3** = `B + 0.25xF` — a QUARTER-strength additive,
// not the usual 50/50. That quarter is the whole reason the effect reads as a glow over the
// wheel rather than blowing the sprite out, so it is applied here, once, as CYL_ABR3_GAIN.
//
// The stripes are UNTEXTURED gouraud geometry (colour rides the vertices), so there is no
// palette sample: the mesh interpolates black -> magenta -> black down each bar and this only
// scales it. Raw DISPLAY-space add like the box/orb twins — NO pow(psx_gamma); the fold has no
// tonemap after it, and the resolve quantizes once post-accumulation.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, compositor_layer;
// psx-prim: untextured gouraud — ALBEDO = vertex colour * abr gain (PSX ABR=11: dst + src/4).

// PSX ABR mode 3 (`B + 0.25xF`), the tpage the cylinder installs at `SUB_8002398c(0, 3, 0x100, 0)`.
const float CYL_ABR3_GAIN = 0.25;

varying float fold_depth;
varying vec4 v_color;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = clip;
	fold_depth = clip.z / clip.w;
	v_color = COLOR;
}

void fragment() {
	ALBEDO = clamp(v_color.rgb * CYL_ABR3_GAIN, vec3(0.0), vec3(1.0));
	ALPHA = 1.0;
	DEPTH = fold_depth;
}
