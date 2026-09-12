shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// Vault: [[Event Dialogue Portrait System]]

// EVTFACE event-dialogue portrait: unlike the unit-SPR portrait (indexed +
// runtime palette swap, unit_portrait_3d.gdshader), the {50} EVTFACE face is
// parsed to a fully-resolved 32x48 RGBA texture (tools/parse_evtface.py), so this
// shader just samples it straight. Index-0 background is emitted transparent by
// the parser; we also discard near-zero alpha defensively.
uniform sampler2D face_texture : filter_nearest, repeat_disable;

void fragment() {
    // Sample straight: the un-rotated QuadMesh already has UV (0,0) at the
    // top-left, so the resolved face is upright. (The unit-SPR shader's
    // `1.0 - UV.y` flip compensates for its 90°-rotated landscape source; this
    // path has neither the rotation nor the landscape storage, so no flip.)
    vec4 c = texture(face_texture, UV);
    if (c.a < 0.5) {
        discard;
    }
    // sRGB -> linear (Godot Forward+ re-applies sRGB on output), same convention
    // as unit_portrait_3d.gdshader so colours aren't gamma-doubled.
    ALBEDO = pow(c.rgb, vec3(2.2));
    ALPHA = c.a;
}
