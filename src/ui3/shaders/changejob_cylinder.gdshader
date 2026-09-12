shader_type spatial;
// CHANGE-JOB commit CYLINDER — in-scene Mobile blend twin of changejob_cylinder_fold.
// See that file for the RE (CHANGE_JOB_COMMIT.md §9: 64 LINE_G2|ABE stripes at ABR 3).
// compositor-exempt: off-fork-fallback — OFF-FORK in-scene fallback ONLY (ADR-0077). On the 4.8 Forward+ fork the
// stripes fold through the display-space scratch like every other PSX add/sub prim; this twin is
// the degraded path when the engine-fold does NOT own compositing (stock 4.7 / test runner). It
// blends into the linear buffer instead of the display-space scratch, so the glow reads a little
// hot — slightly-wrong-but-present, never blank.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_add;
// psx-prim: untextured gouraud — ALBEDO = vertex colour * abr gain (PSX ABR=11: dst + src/4).

const float CYL_ABR3_GAIN = 0.25;

varying vec4 v_color;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_color = COLOR;
}

void fragment() {
	ALBEDO = clamp(v_color.rgb * CYL_ABR3_GAIN, vec3(0.0), vec3(1.0));
	ALPHA = 1.0;
}
