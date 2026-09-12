// Vault: [[Display Space Blend Fold]]

// Unified PSX Ordering-Table depth (ADR-0009). Provides ot_depth() and the
// ot_computed_depth varying. The unit forward nudge is the UNIT mode; its
// magnitude (ot_unit_forward) is tunable via UnitShaderDebugPanel.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

// Unified PSX colour-mode stack (ADR-0067). Provides color_apply() + the
// color_layer_* / quantize uniforms. The fragment folds the {32}∘{33} scenario
// tint stack ScenarioVM pushes (identity when no tint is active).
#include "res://addons/exmateria_schema/colour_model/color_stack.gdshaderinc"

// PAR is NOT included here (ADR-0189 dec. 6). Only the two battle variants apply it,
// in their own vertex(); a body that pulled it in would have the flat formation variant
// reach the PAR seam transitively while never applying it — precisely the state
// tools/check_par_shaders.py exists to prevent.

// Debug: visualize depth as grayscale (true = show depth instead of sprite).
uniform bool debug_show_depth = false;

// World-up offset from the unit origin (feet/tile) to the sprite's visual
// center, used ONLY for the OT depth sample so the billboard sorts at its
// mid-height — matching how a wall face sorts at its mid-height centroid, and
// fixing a unit drawing behind a taller wall it stands in FRONT of (ADR-0009).
// SET PER BODY FRAME by SpriteLayerManager, DERIVED from the TYPE1 sprite
// pieces (so it auto-scales per sprite); this default is only a fallback before
// the first frame loads.
uniform float depth_center_height = 0.9;

// ============================================================================
// COORDINATE SPACE CONVERSION FUNCTIONS
// ============================================================================

// Converts a single pixel coordinate point to mesh UV space (0.0-1.0 range)
// - Normalizes pixel values by dividing by texture dimensions
// - Adjusts Y coordinate to account for aspect ratio difference between texture and mesh
vec2 pxl_pt_to_mesh(
	vec2 pt,           // Point in pixel coordinates
	vec2 tex_size,     // Texture dimensions in pixels (width, height)
	vec2 mesh_size     // Mesh dimensions (typically 1,1 for unit quad)
){
	float tex_aspect_ratio = tex_size[0] / tex_size[1];
	float mesh_aspect_ratio = mesh_size[0] / mesh_size[1];

	return vec2(
		pt.x / tex_size[0],  // Simple normalization for X
		pt.y / tex_size[1] * mesh_aspect_ratio / tex_aspect_ratio  // Y adjusted for aspect ratio
	);

}

// Converts a pixel rectangle to a 4-point quad in mesh UV space
// Returns array of 4 corner points: [top-left, top-right, bottom-right, bottom-left]
// Performs two key operations:
// 1. Converts pixel values to UV values (0.0-1.0 range)
// 2. Adjusts aspect ratio from texture space to mesh space
vec2[4] pxl_quad_to_mesh(
	vec2 pos,          // Top-left corner position in pixel coordinates
	float width,       // Width of rectangle in pixels
	float height,      // Height of rectangle in pixels
	vec2 tex_size,     // Texture dimensions in pixels
	vec2 mesh_size     // Mesh dimensions
){
	vec2[4] output;
	float tex_aspect_ratio = tex_size[0] / tex_size[1];
	float mesh_aspect_ratio = mesh_size[0] / mesh_size[1];

	// Top-left corner
	output[0] = vec2(
		pos[0] / tex_size[0],
		pos[1] / tex_size[1] * mesh_aspect_ratio / tex_aspect_ratio
	);

	// Top-right corner
	output[1] = vec2(
		(pos[0] + width) / tex_size[0],
		pos[1] / tex_size[1] * mesh_aspect_ratio / tex_aspect_ratio
	);

	// Bottom-right corner
	output[2] = vec2(
		(pos[0] + width) / tex_size[0],
		(pos[1] + height) / tex_size[1] * mesh_aspect_ratio / tex_aspect_ratio
	);

	// Bottom-left corner
	output[3] = vec2(
		pos[0] / tex_size[0],
		(pos[1] + height) / tex_size[1] * mesh_aspect_ratio / tex_aspect_ratio
	);

	return output;
}

// Converts a quad from mesh aspect ratio to texture aspect ratio
// Only adjusts aspect ratio scaling, not absolute scale
vec2[4] mesh_quad_to_tex(vec2[4] quad, vec2 tex_size, vec2 mesh_size){
	vec2[4] output;
	float mesh_ar = mesh_size.x / mesh_size.y;
	float tex_ar = tex_size.x / tex_size.y;
	output[0] = quad[0] * tex_ar / mesh_ar;
	output[1] = quad[1] * tex_ar / mesh_ar;
	output[2] = quad[2] * tex_ar / mesh_ar;
	output[3] = quad[3] * tex_ar / mesh_ar;
	return output;
}

// Converts a quad from texture aspect ratio to mesh aspect ratio
// Inverse of mesh_quad_to_tex()
vec2[4] tex_quad_to_mesh(vec2[4] quad, vec2 tex_size, vec2 mesh_size){
	vec2[4] output;
	float mesh_ar = mesh_size.x / mesh_size.y;
	float tex_ar = tex_size.x / tex_size.y;
	output[0] = quad[0] / tex_ar * mesh_ar;
	output[1] = quad[1] / tex_ar * mesh_ar;
	output[2] = quad[2] / tex_ar * mesh_ar;
	output[3] = quad[3] / tex_ar * mesh_ar;
	return output;
}

// Converts a single point from mesh aspect ratio to texture aspect ratio
// Only adjusts the Y coordinate to account for aspect ratio difference
vec2 mesh_ar_to_tex_ar(vec2 pt, vec2 tex_size, vec2 mesh_size){
	vec2 output = pt;
	output.y *= (tex_size[0] / tex_size[1]) / (mesh_size[0] / mesh_size[1]);
	return output;
}

// Converts a single point from texture aspect ratio to mesh aspect ratio
// Inverse of mesh_ar_to_tex_ar()
vec2 tex_ar_to_mesh_ar(vec2 pt, vec2 tex_size, vec2 mesh_size){
	vec2 output = pt;
	output.y *= (mesh_size[0] / mesh_size[1]) / (tex_size[0] / tex_size[1]);
	return output;
}

// ============================================================================
// GEOMETRIC TRANSFORMATION FUNCTIONS
// ============================================================================

// Translates a point by subtracting a vector
// Note: Uses subtraction, which moves UV in opposite direction of vector
vec2 translate(vec2 start, vec2 vector){
	return vec2(
		start.x - vector.x,
		start.y - vector.y
	);
}

// Calculates the center point of a quad (for use as rotation pivot)
// Takes the average of corner positions
vec2 point_of_rotation(vec2[4] rect){
	return vec2(
		(rect[0].x + rect[1].x)/2.0,  // Average of left and right X
		(rect[0].y + rect[3].y)/2.0   // Average of top and bottom Y
	);
}

// Rotates a point around another point by a given angle
// Uses standard 2D rotation matrix: [cos -sin; sin cos]
vec2 rotation_around_point(vec2 starting_point, vec2 rotation_point, float angle){
	// Negate angle because by convention positive angles rotate counter-clockwise
	// but we want clockwise rotation for this application
	angle = -1.0 * angle;

	// Translate to origin, rotate, translate back
	return vec2(
		rotation_point.x
		+ (starting_point.x - rotation_point.x) * cos(angle)
		- (starting_point.y - rotation_point.y) * sin(angle),
		rotation_point.y
		+ (starting_point.x - rotation_point.x) * sin(angle)
		+ (starting_point.y - rotation_point.y) * cos(angle)
	);
}

// Horizontally flips a UV coordinate within a rectangle's bounds
// Mirrors the point across the rectangle's vertical center line
vec2 revert_within_rect(vec2 uv, vec2[4] rect){
	return vec2(
		uv.x + -2.0 * uv.x + 2.0 * rect[0].x + (rect[1].x - rect[0].x),
		uv.y
	);
}

// Vertically flips a UV coordinate within a rectangle's bounds
// Mirrors the point across the rectangle's horizontal center line
vec2 invert_within_rect(vec2 uv, vec2[4] rect){
	return vec2(
		uv.x,
		uv.y + -2.0 * uv.y + 2.0 * rect[0].y + (rect[3].y - rect[0].y)
	);
}

// ============================================================================
// POLYGON HIT TESTING FUNCTIONS
// ============================================================================

// Calculates the slope of a line given two points
// Returns rise over run: (y2 - y1) / (x2 - x1)
float slope(vec2 pt1, vec2 pt2){
	return ((pt2.y - pt1.y) / (pt2.x - pt1.x));
}

// Calculates the y-intercept of a line given a point and slope
// Uses formula: b = y - mx
float y_intercept(vec2 pt1, float slope){
	return (pt1.y - slope * pt1.x);
}

// Checks if a point is above a line segment (used for point-in-polygon test)
// Returns 1 if point is above the line and within X bounds, 0 otherwise
// Part of ray-casting algorithm for polygon containment
int is_above_line_segment(
	vec2 uv,   // Point to test
	vec2 pt1,  // First endpoint of line segment
	vec2 pt2   // Second endpoint of line segment
){
	float m = slope(pt1, pt2);
	float b = y_intercept(pt1, m);

	// Only check if point's X is within the segment's X range
	if(
		uv.x > min(pt1.x, pt2.x)
		&& uv.x < max(pt1.x, pt2.x)
	){
		return int((uv.y > m * uv.x + b));
	} else {
		return 0;
	}
}

// Determines if a UV point is inside a quad using ray-casting algorithm
// Checks if point is "above" each of the 4 edges
// If the sum is odd (1 or 3), the point is inside the quad
bool within_quad(
	vec2[4] pts,  // Quad corners: [top-left, top-right, bottom-right, bottom-left]
	in vec2 uv    // Point to test
){
	// Count how many edges the point is "above"
	int check_12 = is_above_line_segment(uv, pts[0], pts[1]);  // Top edge
	int check_23 = is_above_line_segment(uv, pts[1], pts[2]);  // Right edge
	int check_34 = is_above_line_segment(uv, pts[2], pts[3]);  // Bottom edge
	int check_41 = is_above_line_segment(uv, pts[3], pts[0]);  // Left edge

	int sum_check = check_12 + check_23 + check_34 + check_41;

	// Odd sum means inside polygon (ray-casting principle)
	return (sum_check == 1 || sum_check == 3);
}

// ============================================================================
// TILE RENDERING FUNCTION
// ============================================================================

// Renders a single sprite tile with full transformation support
// This is the core rendering function that composites one tile onto the mesh.
//
// ALGORITHM:
// For each pixel on the mesh, this function transforms the UV coordinate backwards
// through all operations to determine which pixel from the sprite atlas should be
// displayed. The transformations are applied in reverse order:
// pixel -> translate -> rotate -> flip -> sample texture
//
// PARAMETERS:
// rect_coord  - Position of tile on sprite atlas (in pixels)
// loc_coord   - Where to draw tile on screen (in pixels, relative to sprite center)
// loc_offset  - Additional positioning offset (for fine-tuning alignment)
// width       - Width of tile rectangle in pixels
// height      - Height of tile rectangle in pixels
// deg_rot     - Rotation angle in degrees
// rot_pt      - Pivot point for rotation (in pixels)
// tex_size    - Sprite atlas texture dimensions (width, height)
// mesh_size   - Mesh quad dimensions (typically 1,1)
// invert      - If true, flip tile vertically
// revert      - If true, flip tile horizontally
// uv          - Current pixel's UV coordinate on the mesh
// albedo      - Output color (modified if this tile covers this pixel)
// alpha       - Output alpha (modified if this tile covers this pixel)
// tex         - Sprite atlas texture sampler
void add_tile(
	vec2 rect_coord,
	vec2 loc_coord,
	vec2 loc_offset,
	float width,
	float height,
	float deg_rot,
	vec2 rot_pt,
	vec2 tex_size,
	vec2 mesh_size,
	bool invert,
	bool revert,
	in vec2 uv,
	inout vec3 albedo,
	inout float alpha,
	in sampler2D tex,
){

	vec2 uv_start = uv;  // Save original UV (unused, but kept for debugging)

	// STEP 1: Convert pixel-space rectangles to mesh UV space
	// rect_tex = where the tile is located on the sprite atlas
	// loc_tex = where the tile should appear on screen
	vec2[4] rect_tex = mesh_quad_to_tex(
		pxl_quad_to_mesh(
			rect_coord,
			width,
			height,
			tex_size,
			mesh_size
		),
		tex_size,
		mesh_size
	);

	vec2[4] loc_tex = mesh_quad_to_tex(
		pxl_quad_to_mesh(
			loc_coord,
			width,
			height,
			tex_size,
			mesh_size
		),
		tex_size, mesh_size
	);

	// Convert current UV to texture aspect ratio for processing
	uv = mesh_ar_to_tex_ar(uv, tex_size, mesh_size);

	// Convert quads back to mesh space for calculations
	vec2[4] loc_uv = tex_quad_to_mesh(loc_tex, tex_size, mesh_size);
	vec2[4] rect_uv = tex_quad_to_mesh(rect_tex, tex_size, mesh_size);

	// STEP 2: Apply translation to align screen position with atlas position
	// This moves the UV so that the screen location overlays the atlas location
	uv = mesh_ar_to_tex_ar(translate(
		tex_ar_to_mesh_ar(uv, tex_size, mesh_size),
		vec2(
				loc_uv[0].x - rect_uv[0].x,
				loc_uv[0].y - rect_uv[0].y
		)
	), tex_size, mesh_size);

	// Apply the additional offset (for centering, fine-tuning position)
	uv = mesh_ar_to_tex_ar(translate(
		tex_ar_to_mesh_ar(uv, tex_size, mesh_size),
		pxl_pt_to_mesh(loc_offset, tex_size, mesh_size)
	), tex_size, mesh_size);

	// STEP 3: Adjust rotation pivot point to match the translations
	// The rotation point needs to move along with the UV translations above,
	// otherwise the sprite would rotate around the wrong pivot
	vec2 rot_pt_mesh = translate(
		pxl_pt_to_mesh(rot_pt, tex_size, mesh_size),
		vec2(
				loc_uv[0].x - rect_uv[0].x,
				loc_uv[0].y - rect_uv[0].y
		)
	);
	rot_pt_mesh = translate(
		rot_pt_mesh,
		pxl_pt_to_mesh(loc_offset, tex_size, mesh_size)
	);

	// STEP 4: Apply rotation around the adjusted pivot point
	uv = mesh_ar_to_tex_ar(
		rotation_around_point(
			tex_ar_to_mesh_ar(uv, tex_size, mesh_size),
			rot_pt_mesh,
			deg_rot * PI / 180.0  // Convert degrees to radians
		),
		tex_size,
		mesh_size
	);

	// STEP 5: Apply horizontal flip if requested
	if(revert){
		uv = mesh_ar_to_tex_ar(
			revert_within_rect(
				tex_ar_to_mesh_ar(uv, tex_size, mesh_size),
				tex_quad_to_mesh(rect_tex, tex_size, mesh_size)
			),
			tex_size,
			mesh_size
		);
	}

	// STEP 6: Apply vertical flip if requested
	if(invert){
		uv = mesh_ar_to_tex_ar(
			invert_within_rect(
				tex_ar_to_mesh_ar(uv, tex_size, mesh_size),
				tex_quad_to_mesh(rect_tex, tex_size, mesh_size)
			),
			tex_size,
			mesh_size
		);
	}

	// STEP 7: Check if transformed UV falls within the tile's rectangle
	// If yes, sample the texture and write the pixel
	if(
		within_quad(
			tex_quad_to_mesh(rect_tex, tex_size, mesh_size),
			tex_ar_to_mesh_ar(uv, tex_size, mesh_size)
		)
	){
		vec4 color = texture(tex, uv).rgba;
		// Only write if pixel is not transparent
		if(color.a > 0.001){
			albedo.rgb = color.rgb;
			alpha = color.a;
		}
	}
}


// ADR-0022: paletted variant of add_tile for the BODY layer.
// Identical UV/transform/rotation logic to add_tile; differs only in the
// final sample step — instead of `texture(tex, uv).rgba`, this samples the
// indexed grayscale at uv to get a 0-15 palette index, then looks up
// (index, palette_row) in palette_tex.
//
// The transparency convention is preserved by treating palette-index 0 as
// transparent (FFT's standard "magic 0" — the SPR's color 0 is always the
// transparent color). This matches the pre-baked RGBA path where
// bgr555_to_rgba set alpha=0 for r=g=b=0 pixels.
void add_tile_paletted(
	vec2 rect_coord,
	vec2 loc_coord,
	vec2 loc_offset,
	float width,
	float height,
	float deg_rot,
	vec2 rot_pt,
	vec2 tex_size,
	vec2 mesh_size,
	bool invert,
	bool revert,
	in vec2 uv,
	inout vec3 albedo,
	inout float alpha,
	in sampler2D tex,
	in sampler2D palette_tex,
	int palette_row
){
	vec2 uv_start = uv;
	vec2[4] rect_tex = mesh_quad_to_tex(
		pxl_quad_to_mesh(rect_coord, width, height, tex_size, mesh_size),
		tex_size, mesh_size
	);
	vec2[4] loc_tex = mesh_quad_to_tex(
		pxl_quad_to_mesh(loc_coord, width, height, tex_size, mesh_size),
		tex_size, mesh_size
	);
	uv = mesh_ar_to_tex_ar(uv, tex_size, mesh_size);
	vec2[4] loc_uv = tex_quad_to_mesh(loc_tex, tex_size, mesh_size);
	vec2[4] rect_uv = tex_quad_to_mesh(rect_tex, tex_size, mesh_size);
	uv = mesh_ar_to_tex_ar(translate(
		tex_ar_to_mesh_ar(uv, tex_size, mesh_size),
		vec2(loc_uv[0].x - rect_uv[0].x, loc_uv[0].y - rect_uv[0].y)
	), tex_size, mesh_size);
	uv = mesh_ar_to_tex_ar(translate(
		tex_ar_to_mesh_ar(uv, tex_size, mesh_size),
		pxl_pt_to_mesh(loc_offset, tex_size, mesh_size)
	), tex_size, mesh_size);
	vec2 rot_pt_mesh = translate(
		pxl_pt_to_mesh(rot_pt, tex_size, mesh_size),
		vec2(loc_uv[0].x - rect_uv[0].x, loc_uv[0].y - rect_uv[0].y)
	);
	rot_pt_mesh = translate(rot_pt_mesh, pxl_pt_to_mesh(loc_offset, tex_size, mesh_size));
	uv = mesh_ar_to_tex_ar(
		rotation_around_point(
			tex_ar_to_mesh_ar(uv, tex_size, mesh_size),
			rot_pt_mesh,
			deg_rot * PI / 180.0
		),
		tex_size, mesh_size
	);
	if(revert){
		uv = mesh_ar_to_tex_ar(
			revert_within_rect(
				tex_ar_to_mesh_ar(uv, tex_size, mesh_size),
				tex_quad_to_mesh(rect_tex, tex_size, mesh_size)
			),
			tex_size, mesh_size
		);
	}
	if(invert){
		uv = mesh_ar_to_tex_ar(
			invert_within_rect(
				tex_ar_to_mesh_ar(uv, tex_size, mesh_size),
				tex_quad_to_mesh(rect_tex, tex_size, mesh_size)
			),
			tex_size, mesh_size
		);
	}
	if(
		within_quad(
			tex_quad_to_mesh(rect_tex, tex_size, mesh_size),
			tex_ar_to_mesh_ar(uv, tex_size, mesh_size)
		)
	){
		// Indexed lookup. tex.r is the index scaled to [0,1] by Godot's
		// importer (raw byte / 255); * 15.0 recovers the 0-15 index per the
		// extract_spr_indexed *17 convention.
		float idx_f = texture(tex, uv).r * 15.0;
		int idx = int(idx_f + 0.5);
		// FFT magic-0 transparency: index 0 is the transparent color.
		if(idx == 0){
			return;
		}
		// Sample palette[index, row]. Add 0.5 to sample the center of each
		// texel for filter_nearest correctness.
		vec2 palette_uv = vec2(
			(float(idx) + 0.5) / 16.0,
			(float(palette_row) + 0.5) / 16.0
		);
		vec4 color = texture(palette_tex, palette_uv).rgba;
		if(color.a > 0.001){
			albedo.rgb = color.rgb;
			alpha = color.a;
		}
	}

}

// ============================================================================
// BILLBOARDING AND SHADOW FUNCTIONS
// ============================================================================

// Makes the mesh quad always face the camera (billboard effect)
// Cancels out mesh rotation and replaces it with camera-facing orientation
// while preserving mesh scale and position
// Source: Adapted from Godot example shaders
void billboard(
	inout mat4 model_view_matrix,
	in mat4 view_matrix,
	in mat4 inv_view_matrix,
	in mat4 model_matrix,
	inout mat3 model_view_normal_matrix
){
	// Replace rotation with camera-facing axes, keep translation (model_matrix[3])
	model_view_matrix = view_matrix * mat4(inv_view_matrix[0], inv_view_matrix[1], inv_view_matrix[2], model_matrix[3]);
	// Apply original mesh scale to preserve size
	model_view_matrix = model_view_matrix * mat4(vec4(length(model_matrix[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(model_matrix[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(model_matrix[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	model_view_normal_matrix = mat3(model_view_matrix);
}

// Renders a pixelated circular shadow underneath the sprite
// Creates a retro PSX-style shadow with smooth falloff
//
// PARAMETERS:
// pixel_width      - Size of shadow pixels (larger = chunkier shadow)
// center_pt        - Center of shadow in UV coordinates
// x_stretch        - Horizontal stretch factor (>1 = narrower)
// y_stretch        - Vertical stretch factor (>1 = shorter)
// fall_off_factor  - How quickly shadow fades (more negative = softer edge)
// radius           - Base radius of shadow
// uv               - Current pixel UV coordinate
// alpha            - Output alpha (shadow transparency)
// albedo           - Output color (set to black for shadow)
void paint_shadow(
	float pixel_width,
	vec2 center_pt,
	float x_stretch,
	float y_stretch,
	float fall_off_factor,
	float radius,
	in vec2 uv,
	inout float alpha,
	inout vec3 albedo,
){
	// Shadow color is always black
	albedo.rgb = vec3(0.0,0.0,0.0);

	// Quantize UV coordinates to create pixelated effect
	float shadow_grid_x = round(uv[0] / pixel_width) * pixel_width;
	float shadow_grid_y = round(uv[1] / pixel_width) * pixel_width;

	// Calculate distance from shadow center, applying stretch factors
	// Allows creating elliptical shadows (useful for isometric perspective)
	float dx = center_pt[0] - shadow_grid_x;
	float dy = center_pt[1] - shadow_grid_y;
	float dist = sqrt(pow(dx/x_stretch,2) +  pow(dy/y_stretch, 2));

	// Calculate alpha with exponential falloff for smooth edges
	// Uses exponential function for natural-looking shadow softness
	alpha =  max(1.0 - exp(fall_off_factor * (dist - radius)),0);
}

// ============================================================================
// VERTEX AND FRAGMENT SHADERS
// ============================================================================

// Vertex shader - runs once per vertex
// Applies billboarding so the sprite quad always faces the camera
// vertex() and fragment() are NOT defined here (ADR-0189 dec. 1). `render_mode` has to
// sit in the entry .gdshader — Godot has no runtime blend switch — so the entry files
// exist regardless, and the three of them genuinely differ in both stages: the battle
// pair PAR their POSITION and write OT DEPTH, the flat ortho variant does neither and
// folds the change-job dissolve in between. What they share is published as the four
// names below plus billboard() above; what they don't, each one writes.
//
// The alternative was a `#define UNIT_FLAT_SCREEN` + `#ifdef` inside these two bodies,
// which is refused on a mechanical ground: formation_unit writes POSITION with no PAR
// helper and is carried as debt on check_par_shaders.py's BURN_DOWN list. Under a
// #define that un-PAR'd write relocates INTO this file, which sits on the battle path
// and already holds the PAR'd write. The guard has no preprocessor, sees two writes in
// one file, and reds a Sprite Rig file — while the entry, now writing no POSITION at
// all, reds as a stale BURN_DOWN entry. The debt would be laundered, not paid.


// ============================================================================
// UNIFORMS - Data passed from GDScript to shader
// ============================================================================

// Sprite atlas textures (one for each layer)
// No source_color - PSX textures are not sRGB. We convert to linear at the end.
uniform sampler2D type1_tex :
	filter_nearest,
	hint_default_transparent
;

uniform sampler2D wep1_tex :
	filter_nearest,
	hint_default_transparent
;

uniform sampler2D eff1_tex :
	filter_nearest,
	hint_default_transparent
;

// ADR-0022: TYPE1 (BODY) layer is indexed-color with runtime palette swap.
// type1_tex above is now an indexed-grayscale TGA (each pixel = palette index
// 0-15 scaled to 0-255 by extract_spr_indexed). type1_palette holds the SPR's
// 16-row × 16-color palette table as a 16x16 RGBA. body_palette_row picks the
// row to apply at runtime (default 0 for humanoids; set from job data for
// monsters).
uniform sampler2D type1_palette :
	filter_nearest,
	hint_default_transparent
;
uniform int body_palette_row = 0;

// WEP1 and EFF1 layers — per-item palette swap (ffhacktics "Item Graphics in
// Battle"). wep1_tex / eff1_tex are now indexed-grayscale TGAs (extract_spr.py
// extract_wep_spr); wep1_palette / eff1_palette are 16x16 RGBA tables. The
// row uniforms come from BATTLE.BIN's per-item table at 0x2d3e4 (parsed into
// weapon_graphic_data.json) — X nibble drives wep1_palette_row, Y nibble
// drives eff1_palette_row. Default 0 = sword baseline.
uniform sampler2D wep1_palette :
	filter_nearest,
	hint_default_transparent
;
uniform int wep1_palette_row = 0;
uniform sampler2D eff1_palette :
	filter_nearest,
	hint_default_transparent
;
uniform int eff1_palette_row = 0;

// Mesh and texture dimensions
uniform vec2 mesh_size;         // Mesh quad dimensions (typically 1,1)
uniform vec2 type1_tex_size;    // Character sprite atlas dimensions
uniform vec2 wep1_tex_size;     // Weapon sprite atlas dimensions
uniform vec2 eff1_tex_size;     // Effect sprite atlas dimensions

// TYPE1 LAYER (Character body) - Up to 10 tiles per frame
uniform vec2[10] type1_rects;           // Position of each tile on sprite atlas (pixels)
uniform vec2[10] type1_rect_sizes;      // Width/height of each tile (pixels)
uniform vec2[10] type1_locs;            // Where to draw each tile on screen (pixels)
uniform vec2[10] type1_loc_offsets;     // Additional offset for fine-tuning position
uniform bool[10] type1_inversions;      // Vertical flip flags
uniform bool[10] type1_reversions;      // Horizontal flip flags
uniform float[10] type1_rotations;      // Rotation angles (degrees)
uniform vec2[10] type1_rot_points;      // Rotation pivot points (pixels)

// WEP1 LAYER (Weapon) - Up to 10 tiles per frame
uniform vec2[10] wep1_rects;
uniform vec2[10] wep1_rect_sizes;
uniform vec2[10] wep1_locs;
uniform vec2[10] wep1_loc_offsets;
uniform bool[10] wep1_inversions;
uniform bool[10] wep1_reversions;
uniform float[10] wep1_rotations;
uniform vec2[10] wep1_rot_points;

// EFF1 LAYER (Effects) - Up to 10 tiles per frame
uniform vec2[10] eff1_rects;
uniform vec2[10] eff1_rect_sizes;
uniform vec2[10] eff1_locs;
uniform vec2[10] eff1_loc_offsets;
uniform bool[10] eff1_inversions;
uniform bool[10] eff1_reversions;
uniform float[10] eff1_rotations;
uniform vec2[10] eff1_rot_points;

// Layer enable flags
uniform bool wep_enable;                // Show weapon layer
uniform bool wep_on_top;                // Weapon render order (unused - priority handles this)
uniform bool eff_enable;                // Show effect layer
uniform bool eff_on_top;                // Effect render order (unused - priority handles this)

// Global positioning
uniform vec2 shared_loc_offset;         // Offset applied to all tiles (for centering sprite)

// Layer paint priority (determines z-order)
// 0 = unit body, 1 = weapon, 2 = effect, 3 = text (unused)
// Array order determines paint order (painter's algorithm)
uniform int[4] priority;

// Global sprite reversion (flips entire assembled sprite horizontally)
// Used by state-based animation system to face sprites in different directions
uniform bool global_reversion = false;

// Lighting (matches map shader for consistent appearance)
// Units use flat ambient lighting since they have no normals for directional lights
// Set higher than map's base ambient to compensate for missing directional lights
uniform float ambient_brightness : hint_range(0.0, 3.0) = 1.0;  // Calibrated to PSX (was 1.4, matched map's pre-fix ambient fudge). Fixed 1.0 from unit.tres/this default — the per-machine UserSettings scaling was removed in the principled color/shading alignment.

// Palette-effect unit tint (caster/target flashing during spells, {32} Color Unit)
// AND scenario "Color Unit" ({0x32}) both now fold through the unified color stack
// (color_apply, ADR-0067). ScenarioVM drives the stack for cutscenes;
// UnitTintOverlay drives it for combat effects (issue #164 — the retired additive
// `unit_tint` uniform couldn't express the base-dependent luma / absolute-base modes).

// ============================================================================
// LAYER PAINTING FUNCTIONS
// ============================================================================

// Renders all weapon layer tiles (if enabled). Paletted sampling — wep1_tex is
// indexed grayscale; wep1_palette + wep1_palette_row do the lookup at fragment
// time (the ADR-0022 BODY pattern extended to WEP1).
void paint_wep1(in vec2 uv, inout vec3 albedo, inout float alpha){
	if(wep_enable){
		for(int i = 0; i<wep1_rects.length(); i++){
			// Check if tile is defined (width > 0)
			// Array size must be fixed, so undefined tiles have width=0
			if(wep1_rect_sizes[i][0]>0.0){
				add_tile_paletted(
					wep1_rects[i],
					wep1_locs[i],
					wep1_loc_offsets[i] + shared_loc_offset,  // Apply global offset
					wep1_rect_sizes[i][0],
					wep1_rect_sizes[i][1],
					wep1_rotations[i],
					wep1_rot_points[i] + shared_loc_offset,   // Apply global offset to pivot
					wep1_tex_size,
					mesh_size,
					wep1_inversions[i],
					wep1_reversions[i],
					uv,
					albedo,
					alpha,
					wep1_tex,
					wep1_palette,
					wep1_palette_row
				);
			}
		}
	}
}

// Renders all effect layer tiles (if enabled). Paletted sampling — eff1_tex is
// indexed grayscale; eff1_palette + eff1_palette_row do the lookup at fragment
// time.
void paint_eff1(in vec2 uv, inout vec3 albedo, inout float alpha){
	if(eff_enable){
		for(int i = 0; i<eff1_rects.length(); i++){
			// Check if tile is defined (width > 0)
			if(eff1_rect_sizes[i][0]>0.0){
				add_tile_paletted(
					eff1_rects[i],
					eff1_locs[i],
					eff1_loc_offsets[i] + shared_loc_offset,
					eff1_rect_sizes[i][0],
					eff1_rect_sizes[i][1],
					eff1_rotations[i],
					eff1_rot_points[i] + shared_loc_offset,
					eff1_tex_size,
					mesh_size,
					eff1_inversions[i],
					eff1_reversions[i],
					uv,
					albedo,
					alpha,
					eff1_tex,
					eff1_palette,
					eff1_palette_row
				);
			}
		}
	}
}

// Renders all character body layer tiles
// Always enabled (no enable flag), iterates through type1 tile array.
// Per ADR-0022, BODY layer uses paletted sampling — type1_tex is an indexed
// grayscale texture; the palette is applied at sample time via add_tile_paletted.
void paint_type1(in vec2 uv, inout vec3 albedo, inout float alpha){
	for(int i = 0; i<type1_rects.length(); i++){
		// Check if tile is defined (width > 0)
		if(type1_rect_sizes[i][0]>0.0){
			add_tile_paletted(
				type1_rects[i],
				type1_locs[i],
				type1_loc_offsets[i] + shared_loc_offset,
				type1_rect_sizes[i][0],
				type1_rect_sizes[i][1],
				type1_rotations[i],
				type1_rot_points[i] + shared_loc_offset,
				type1_tex_size,
				mesh_size,
				type1_inversions[i],
				type1_reversions[i],
				uv,
				albedo,
				alpha,
				type1_tex,
				type1_palette,
				body_palette_row
			);
		}
	}
}

// Fragment shader - runs once per pixel on the mesh
// Composites all layers using painter's algorithm (back to front)
// ============================================================================
// THE PUBLISHED STAGES (ADR-0189 dec. 1)
//
// One sprite compositor, three blends. An entry shader calls these in order:
//
//     unit_paint  -> composite the tile layers into ALBEDO + a coverage alpha
//     (discard)      the entry decides what a transparent texel means for ITS blend
//     unit_colour -> the {32}/{33} scenario tint stack, clamped
//     unit_light  -> ambient, then sRGB -> linear for Forward+
//
// The gap between colour and light is not incidental: it is where the PSX applies
// gouraud, and the flat variant's change-job corner tint has to modulate exactly there.
// Publishing the stages rather than the whole fragment is what makes that position
// available to a consumer without a fork.
// ============================================================================

// Composite the three sprite layers at `uv` into `albedo`, accumulating coverage into
// `alpha`. Honours global_reversion (whole-sprite horizontal flip) and the FFT priority
// array — index 0 is foreground, so the loop runs back-to-front and index 0 paints last.
//
// Both are `out`, so the caller cannot forget to zero them.
//
// `alpha` is a LOCAL coverage figure, deliberately not ALPHA: assigning the ALPHA builtin
// opts a spatial material into Godot's transparent pipeline, which drops it out of the
// fold seed and stops it writing depth. The opaque variants never write it; the additive
// one does, on purpose, because blend_add scales by it.
void unit_paint(vec2 uv_in, out vec3 albedo, out float alpha) {
	albedo = vec3(0.0);
	alpha = 0.0;
	vec2 uv = uv_in;
	if (global_reversion) {
		uv.x = 1.0 - uv.x;
	}
	for (int i = 3; i >= 0; i--) {
		switch (priority[i]) {
			case 0:
				paint_type1(uv, albedo, alpha);
				break;
			case 1:
				paint_wep1(uv, albedo, alpha);
				break;
			case 2:
				paint_eff1(uv, albedo, alpha);
				break;
			case 3:
				break;  // Text layer not implemented
			default:
				break;
		}
	}
}

// Coverage below which a texel is not part of the sprite. The entry shaders discard on
// it rather than this file doing so, because the flat variant has a SECOND discard (the
// change-job dissolve) that must run after this one and before anything writes depth.
const float UNIT_ALPHA_CUTOFF = 0.01;

// Scenario Color Unit palette tint. Luma modes (2/3/6/7) mix the entry to a single
// luminance scalar + brown delta in 5-bit space; every other mode is the per-channel
// affine (mul then add). Identity (scale=1, bias=0, div=0) by default. Folds the {32}∘{33}
// scenario stack ScenarioVM pushes AND combat palette-effect flashing from
// UnitTintOverlay. Single-surface consumer -> surface_id 0. ADR-0067.
vec3 unit_colour(vec3 albedo) {
	return clamp(color_apply(albedo, 0), vec3(0.0), vec3(1.0));
}

// Ambient (units have no normals, so this is the whole lighting term — it matches the map
// shader's `color * ambient`), then sRGB -> linear for Forward+, which Godot converts back
// for display. Mirrors indexed_color.gdshader.
vec3 unit_light(vec3 albedo) {
	return pow(albedo * ambient_brightness, vec3(2.2));
}

// Light shader disabled (using unshaded render mode)
//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
