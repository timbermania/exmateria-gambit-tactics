shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Font atlas texture - NO source_color to match GL Compatibility behavior
uniform sampler2D font_atlas : filter_nearest, repeat_disable;

// Character region in atlas: (x, y, width, height) in pixels
uniform vec4 char_region;

// Atlas dimensions for UV calculation
uniform vec2 atlas_size;

// Tint color for the text - NO source_color
uniform vec4 font_color = vec4(1.0);

// Palette remapping - replaces atlas colors based on luminance thresholds
// NO source_color - values are in sRGB space
uniform bool use_palette = false;
uniform vec4 palette_outline = vec4(0.275, 0.247, 0.200, 1.0);  // Darkest (outline)
uniform vec4 palette_shadow = vec4(0.420, 0.408, 0.333, 1.0);   // Middle (shadow)
uniform vec4 palette_main = vec4(0.471, 0.439, 0.376, 1.0);     // Brightest (main body)

// Black outline around text (1-pixel stroke)
uniform bool stroke_enabled = false;
uniform vec4 stroke_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float stroke_padding = 0.0;  // Extra pixels around char for stroke (set to 1.0 when stroke enabled)

// Check if a pixel coordinate is within the character region bounds
bool is_in_char_region(vec2 pixel_coord, vec4 region) {
    return pixel_coord.x >= region.x && pixel_coord.x < (region.x + region.z) &&
           pixel_coord.y >= region.y && pixel_coord.y < (region.y + region.w);
}

// Sample neighbor only if within character region, otherwise return 0 alpha
float sample_neighbor_alpha(vec2 neighbor_pixel, vec4 region, vec2 atlas_sz) {
    if (!is_in_char_region(neighbor_pixel, region)) {
        return 0.0;  // Out of bounds = transparent
    }
    vec2 neighbor_texel = (floor(neighbor_pixel) + 0.5) / atlas_sz;
    return texture(font_atlas, neighbor_texel).a;
}

void fragment() {
    // Map quad UV (0-1) to expanded region (char_region + stroke_padding on each side)
    // UV 0,0 maps to (char_region.x - padding, char_region.y - padding)
    // UV 1,1 maps to (char_region.x + width + padding, char_region.y + height + padding)
    vec2 expanded_size = char_region.zw + vec2(stroke_padding * 2.0);
    vec2 char_uv = (char_region.xy - vec2(stroke_padding)) + UV * expanded_size;

    // Current pixel coordinate in atlas (not normalized)
    vec2 current_pixel = floor(char_uv);

    // Check if we're inside the character region (vs in stroke padding area)
    bool in_char_region = is_in_char_region(current_pixel, char_region);

    // Sample atlas only if inside character region, otherwise start transparent
    vec4 color;
    if (in_char_region) {
        vec2 texel = (current_pixel + 0.5) / atlas_size;
        color = texture(font_atlas, texel);
    } else {
        color = vec4(0.0);  // Start transparent in padding area
    }

    bool is_stroke_pixel = false;

    // Stroke: if current pixel is transparent, check if neighbors have content
    // Only check neighbors within the character region to avoid atlas bleeding
    if (stroke_enabled && color.a < 0.5) {
        bool has_neighbor = false;

        // Check 8 neighbors, clamped to character region
        if (sample_neighbor_alpha(current_pixel + vec2(1.0, 0.0), char_region, atlas_size) > 0.5) has_neighbor = true;
        if (sample_neighbor_alpha(current_pixel + vec2(-1.0, 0.0), char_region, atlas_size) > 0.5) has_neighbor = true;
        if (sample_neighbor_alpha(current_pixel + vec2(0.0, 1.0), char_region, atlas_size) > 0.5) has_neighbor = true;
        if (sample_neighbor_alpha(current_pixel + vec2(0.0, -1.0), char_region, atlas_size) > 0.5) has_neighbor = true;
        // Diagonals
        if (sample_neighbor_alpha(current_pixel + vec2(1.0, 1.0), char_region, atlas_size) > 0.5) has_neighbor = true;
        if (sample_neighbor_alpha(current_pixel + vec2(-1.0, 1.0), char_region, atlas_size) > 0.5) has_neighbor = true;
        if (sample_neighbor_alpha(current_pixel + vec2(1.0, -1.0), char_region, atlas_size) > 0.5) has_neighbor = true;
        if (sample_neighbor_alpha(current_pixel + vec2(-1.0, -1.0), char_region, atlas_size) > 0.5) has_neighbor = true;

        if (has_neighbor) {
            color = stroke_color;
            is_stroke_pixel = true;
        }
    }

    // Palette remapping: detect which color based on luminance
    // Skip for stroke pixels - they keep their stroke_color
    // Font has 2 source tones: dark (~0.25 lum) and light (~0.45 lum)
    // Map to palette_outline (brightest) and palette_main (medium)
    if (use_palette && color.a > 0.5 && !is_stroke_pixel) {
        float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));

        if (lum < 0.35) {
            color = palette_outline;  // Dark source → bright output
        } else {
            color = palette_main;     // Light source → medium output
        }
    }

    vec3 final_color = color.rgb * font_color.rgb;

    // Convert sRGB to linear for Forward+ (Godot will convert back to sRGB for display)
    ALBEDO = pow(final_color, vec3(2.2));
    ALPHA = color.a * font_color.a;
}
