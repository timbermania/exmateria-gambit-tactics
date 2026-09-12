shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// ADR-0022: portrait texture is indexed-grayscale (extract_spr_indexed
// writes a SPR's whole indexed bitmap, including the portrait region at
// X:80-127); palette is applied at sample time using portrait_palette_row.
// Default row 8 preserves the historical humanoid extraction convention
// (the prior pre-baked pipeline always applied palette row 8 to the portrait
// region via the --portrait-palette extractor flag). Monster portrait color
// variants are known-broken in v1 — they all render with row 8 regardless
// of which Chocobo-variant job is set. v2 follow-up.
uniform sampler2D sprite_texture : filter_nearest, repeat_disable;
uniform sampler2D sprite_palette : filter_nearest, repeat_disable;
uniform int portrait_palette_row = 8;

// Portrait region: (x, y, width, height) in pixels
uniform vec4 portrait_region;

// Texture dimensions for UV calculation
uniform vec2 atlas_size;

// UI3 FADE beat (ADR-0269 dec. 3 / UI3FadeBeat): a 0..1 ALPHA multiplier the beat ramps over
// the ROM's -8-per-tick prayer-dismiss step. 1.0 = fully drawn, so every existing caller that
// never touches it is byte-identical.
uniform float fade = 1.0;

// UI3 clip aperture (UI3ClipEngine): a portrait mounted inside a box-open window must be
// scissored by that window's reveal, or it pops in whole while the frame is still growing.
// `clip_world` is the aperture in the SCREEN's space (xy = min, zw = max); the defaults are
// unbounded, so a portrait outside UI3 is unchanged. See vitals_sprite.gdshader — same pair,
// same convention, same reason.
uniform vec4 clip_world = vec4(-1e20, -1e20, 1e20, 1e20);
uniform mat4 clip_basis_inv = mat4(1.0);
varying vec3 v_world;

void vertex() {
    v_world = (clip_basis_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    if (v_world.x < clip_world.x || v_world.y < clip_world.y
            || v_world.x > clip_world.z || v_world.y > clip_world.w) {
        discard;  // outside the owning element's aperture
    }
    // Flip UV.y to mirror the image vertically
    vec2 uv = vec2(UV.x, 1.0 - UV.y);

    // Map quad UV (0-1) to portrait region in atlas (pixels)
    vec2 pixel_coord = portrait_region.xy + uv * portrait_region.zw;

    // Snap to texel center for pixel-perfect sampling
    vec2 texel = (floor(pixel_coord) + 0.5) / atlas_size;

    // Indexed lookup: sprite_texture.r is the index scaled to [0,1] by
    // Godot's importer (* 17 by extract_spr_indexed); * 15.0 recovers index 0-15.
    float idx_f = texture(sprite_texture, texel).r * 15.0;
    int idx = int(idx_f + 0.5);
    // FFT magic-0 transparency: palette index 0 is the transparent color.
    if (idx == 0) {
        discard;
    }
    vec2 palette_uv = vec2(
        (float(idx) + 0.5) / 16.0,
        (float(portrait_palette_row) + 0.5) / 16.0
    );
    vec4 color = texture(sprite_palette, palette_uv);
    if (color.a < 0.5) {
        discard;
    }
    // Convert sRGB → linear so Godot's Forward+ pipeline can re-apply sRGB
    // on output. Without this, the sRGB palette bytes get treated as linear
    // and the display gamma is applied twice — washing out the colors. Same
    // convention the body shader (unit.gdshader) uses for its paletted output.
    ALBEDO = pow(color.rgb, vec3(2.2));
    ALPHA = color.a * fade;
}
