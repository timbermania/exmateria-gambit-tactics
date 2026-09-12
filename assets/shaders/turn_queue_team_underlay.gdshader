shader_type spatial;
render_mode unshaded, cull_disabled;

// The TURN QUEUE card's team underlay (ADR-0269 dec. 2): a flat team-coloured quad behind one
// queue portrait, and the strip's whole answer to "which side is this".
//
// It works because of the portrait shader's own transparency key. FFT portraits are indexed
// with palette index 0 as the magic-0 transparent colour, which unit_portrait_3d.gdshader
// `discard`s — so the negative space around a head is a real hole, and the card's background is
// whatever is drawn behind it. Putting a colour there tints the SILHOUETTE'S SURROUND rather
// than the face, which is the read the mirrored-portrait convention (ADR-0244 dec. 7) could
// never give: mirroring is only legible when two entries sit side by side to compare.
//
// Authored in target sRGB and raised by pow(., 2.2) for the Forward+ pipeline — the same
// convention formation_solid.gdshader and the paletted UI shaders use. NOT depth_test_disabled
// (formation_solid is, for the flat header chrome): this quad sits UNDER a portrait that writes
// depth, and the two have to sort. Ordering is by render_priority, set by the card.

// Team colour, sRGB, straight-alpha. A vec4 uniform fed a Vector4 — never a Color, which Godot
// sRGB-linearizes on the way in and would double-correct against the pow() below.
uniform vec4 tint = vec4(0.35, 0.45, 0.72, 1.0);

// UI3 FADE beat's ramp — see UI3FadeBeat. The underlay is payload of the same card element, so
// it has to carry the uniform or a fading card would leave its team colour behind at full alpha.
uniform float fade = 1.0;

// UI3 clip aperture (UI3ClipEngine) — the card rides its bar's box-open reveal.
uniform vec4 clip_world = vec4(-1e20, -1e20, 1e20, 1e20);
uniform mat4 clip_basis_inv = mat4(1.0);
varying vec3 v_world;

void vertex() {
	v_world = (clip_basis_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (v_world.x < clip_world.x || v_world.y < clip_world.y
			|| v_world.x > clip_world.z || v_world.y > clip_world.w) {
		discard;
	}
	ALBEDO = pow(clamp(tint.rgb, vec3(0.0), vec3(1.0)), vec3(2.2));
	ALPHA = tint.a * fade;
}
