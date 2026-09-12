shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// Frame texture atlas
uniform sampler2D frame_texture : source_color, filter_nearest, repeat_disable;

// Region in atlas to use: (x, y, width, height) in pixels
uniform vec4 source_region;

// 9-slice margins in source pixels: (left, right, top, bottom)
uniform vec4 margins;

// Optional atlas patch (x, y, w, h) the TILED CENTER samples instead of the source_region
// interior; borders/corners/edges still come from source_region. ZERO (default) ⇒ off, so the
// center tiles source_region as before and every existing caller is byte-identical.
uniform vec4 center_region = vec4(0.0);

// Output size in virtual pixels (how big the dialog is in FFT pixels)
uniform vec2 output_size;

// §15.21 "send window to background": exact nearest-index CLUT remap 0x7C3C→0x7D3C in DISPLAY space.
// palette_count 0 (default) ⇒ every existing caller (dialogue, panels, vitals/info frames) byte-identical.
uniform vec3 fg_palette[16];
uniform vec3 bg_palette[16];
uniform int palette_count = 0;
uniform float backgrounded = 0.0;

void fragment() {
    // UV (0-1) to output pixel coordinates
    vec2 out_px = UV * output_size;

    float src_w = source_region.z;
    float src_h = source_region.w;

    float m_left = margins.x;
    float m_right = margins.y;
    float m_top = margins.z;
    float m_bottom = margins.w;

    // Source inner bounds (where the stretchable center lives)
    float src_inner_left = m_left;
    float src_inner_right = src_w - m_right;
    float src_inner_top = m_top;
    float src_inner_bottom = src_h - m_bottom;

    // Output inner bounds
    float out_inner_left = m_left;
    float out_inner_right = output_size.x - m_right;
    float out_inner_top = m_top;
    float out_inner_bottom = output_size.y - m_bottom;

    vec2 src_px;

    // X mapping: left edge, center (tiled), right edge
    if (out_px.x < out_inner_left) {
        // Left column - direct 1:1 mapping
        src_px.x = out_px.x;
    } else if (out_px.x >= out_inner_right) {
        // Right column - map from right edge
        src_px.x = src_inner_right + (out_px.x - out_inner_right);
    } else {
        // Center - tile the source center region
        float center_src_w = src_inner_right - src_inner_left;
        src_px.x = src_inner_left + mod(out_px.x - out_inner_left, center_src_w);
    }

    // Y mapping: top edge, center (tiled), bottom edge
    if (out_px.y < out_inner_top) {
        // Top row - direct 1:1 mapping
        src_px.y = out_px.y;
    } else if (out_px.y >= out_inner_bottom) {
        // Bottom row - map from bottom edge
        src_px.y = src_inner_bottom + (out_px.y - out_inner_bottom);
    } else {
        // Center - tile the source center region
        float center_src_h = src_inner_bottom - src_inner_top;
        src_px.y = src_inner_top + mod(out_px.y - out_inner_top, center_src_h);
    }

    // Convert to atlas UV (snap to texel center for nearest-neighbor)
    vec2 atlas_size = vec2(textureSize(frame_texture, 0));
    vec2 atlas_px = source_region.xy + floor(src_px) + 0.5;
    // Center override: when this pixel is in BOTH the tiled center columns AND rows, tile the
    // separate `center_region` patch instead of the source_region interior (borders unaffected).
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
        discard;
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
    ALPHA = color.a;
}
