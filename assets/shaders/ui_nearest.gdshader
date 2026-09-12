shader_type canvas_item;

// Force nearest-neighbor sampling for pixel-perfect UI rendering.
// Snaps UV coordinates to texel centers to eliminate bilinear filtering artifacts.

void fragment() {
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
    vec2 uv_snapped = (floor(UV * tex_size) + 0.5) / tex_size;
    COLOR = texture(TEXTURE, uv_snapped);
}
