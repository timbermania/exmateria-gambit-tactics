shader_type spatial;
render_mode unshaded, depth_draw_opaque;  // Back-face culled, manual PSX-style lighting
// Vault: [[Color Tint Luma Modes]]
// Vault: [[Display Space Blend Fold]]
// Vault: [[Map Tint]]
// Vault: [[Scenario Camera Framing]]

// Unified PSX Ordering-Table depth (ADR-0009): the map is one multi-face mesh,
// so it uses the per-face centroid baked in CUSTOM0 (AVSZ4/AVSZ3 at export),
// STANDARD mode (no bias). Provides ot_depth() + the ot_computed_depth varying.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

// Unified PSX colour-mode stack (ADR-0067). Provides color_apply() + the
// color_layer_* uniforms. The fragment folds the {33} field layer MapComposer pushes
// (identity when no field is active). See the field block in fragment().
#include "res://addons/exmateria_schema/colour_model/color_stack.gdshaderinc"

// FFT per-polygon visible-angles cull (PSX renderer Stage 4).
// CUSTOM1.r carries the polygon's 16-bit bitfield, gated by F3 toggle.
#include "res://addons/exmateria_battlefield/terrain/fft_visible_angles.gdshaderinc"

// PSX ordered dither + 15-bit framebuffer snap. The map is drawn as Gouraud TEXTURED
// polys with the texpage DTD bit set, so it clears both of the GPU's dither gates and
// the real console dithers it — confirmed by measurement, not inferred: on a live
// battle frame the terrain carries the emulator's 4x4 dither signature at very close to
// its full theoretical amplitude, while the flat-rect UI windows in the same frame carry
// none. Provides psx_dither_and_quantize() + the psx_dither_enabled global.
#include "res://addons/exmateria_platform/dither/psx_dither.gdshaderinc"

// Textures (filter_nearest for pixel-perfect sampling)
// No source_color hint - match GaneshaDx's linear color handling (no sRGB conversion)
uniform sampler2D indexed_texture : hint_default_black, filter_nearest;
uniform sampler2D palette_texture : filter_nearest;  // 16x32 (base + animation)

// Perimeter-aware UV snap (neighbor-patch bleed on shared/gutter-less atlas). At a texture
// patch edge a covered fragment snaps to a texel whose CONTENT is the neighbor polygon
// (e.g. green terrain under the boulder's palette). We nudge the sample toward the
// triangle's UV centroid, scaled by how close the fragment is to the perimeter (barycentric
// min): interior fragments barely move, edge fragments move most. Plus a global (x,y) texel
// offset. All in TEXEL units. Defaults = identity (centroid=0) so it's off until dialed.
// ADR-0068 tunables (map.uv_snap_*). Needs the triangle's 3 UV verts (CUSTOM2 + CUSTOM3).
uniform float uv_snap_offx : hint_range(-2.0, 2.0) = 0.0;
uniform float uv_snap_offy : hint_range(-2.0, 2.0) = 0.0;
uniform float uv_snap_centroid : hint_range(0.0, 4.0) = 0.0;   // pull at the perimeter (texels)
uniform float uv_snap_perimeter : hint_range(0.25, 8.0) = 1.0; // edge-concentration exponent

// PSX-style lighting uniforms (loaded from manifest.json via MapLightingConfig)
// GaneshaDx formula: texture × (ambient × 1.5 + diffuse)
uniform vec3 ambient_light = vec3(0.19, 0.21, 0.22);  // From map file (typical ~0.19)

// Directional lights (colors from map, 0.0-1.0 range)
uniform vec3 light1_color = vec3(0.79, 0.81, 0.83);
uniform vec3 light1_direction = vec3(0.0, 1.0, 0.0);

uniform vec3 light2_color = vec3(1.0, 1.0, 1.0);
uniform vec3 light2_direction = vec3(0.0, 1.0, 0.0);

uniform vec3 light3_color = vec3(0.4, 0.53, 0.75);
uniform vec3 light3_direction = vec3(0.0, -1.0, 0.0);

// --- Live lighting debug (set per-material by tools/capture_map_lighting_debug.gd) ---
// 0 normal, 1 normals-as-color, 2 lighting-only(white albedo), 3 ambient-only,
// 4 diffuse-only, 5 albedo-only(no lighting). map_light_boost exaggerates 2/3/4.
uniform int map_light_debug = 0;
uniform float map_light_boost = 1.0;

// Boost (GaneshaDx never sets these - kept for compatibility but always 0)
uniform vec3 light1_boost = vec3(0.0, 0.0, 0.0);
uniform vec3 light2_boost = vec3(0.0, 0.0, 0.0);
uniform vec3 light3_boost = vec3(0.0, 0.0, 0.0);

// Wave configuration
uniform bool enable_waves = false;
uniform float wave_height : hint_range(0.0, 1.0) = 0.05;
uniform float wave_frequency : hint_range(0.0, 20.0) = 5.0;
uniform float wave_speed : hint_range(0.0, 10.0) = 2.0;
uniform float water_surface_offset : hint_range(0.0, 0.1) = 0.0;

// Palette animation configuration — PER PALETTE ID (issue: Igros waterfalls).
//
// On PSX a palette animation belongs to the CLUT: it runs on whatever polygons sample
// that palette, whatever they are. So the schedule is indexed by the polygon's own
// palette id (COLOR.r), and a map's heterogeneous animations no longer have to pretend
// to be one contiguous range sharing one set of parameters. `palette_anim_count[i] == 0`
// means "palette i does not free-run"; the four arrays are otherwise parallel and are
// filled by PaletteAnimationTable.build() from manifest.animations.palette_animations.

// PaletteAnimationMode.ForwardAndReverseLooping (tools/fft_exporter/models/animation.py).
// Every other free-running mode is a plain forward loop; the trigger modes never reach
// here at all, because PaletteAnimationTable gives them a frame count of 0.
const int PALETTE_ANIM_FORWARD_AND_REVERSE = 4;

uniform bool enable_palette_animation = false;
uniform int palette_anim_start[16];       // first animation_frame ROW OFFSET (row = 16 + this)
uniform int palette_anim_count[16];       // frame count; 0 = this palette does not animate
uniform float palette_anim_duration[16];  // ticks per frame
uniform int palette_anim_mode[16];        // PaletteAnimationMode: 3 ForwardLooping, 4 Fwd+Rev

// Animation time (updated by MapAnimationController)
uniform float animation_time = 0.0;

// Combat map tinting (palette effects) now folds through the unified color stack
// (color_apply) BEFORE lighting — the faithful CLUT-engine behaviour, driven by
// MapTintOverlay (ADR-0067, issue #164). The retired additive post-lighting
// `map_tint` uniform is gone; the same seam serves scenario {33} and combat.

// Map ILLUMINATION — the 8-bit ADDITIVE brightness applier (FUN_80090dec, the THIRD
// colour sink: Holy/E015 "white light", Meteor, Ramuh summons). It is INDEPENDENT of
// the CLUT tint above (which recolours the texture): the PSX stamps a single flat
// brightness (DAT_800f5b58) as the Gouraud vertex colour of every terrain poly and
// draws it ADDITIVELY over the lit-and-textured terrain. So it is added post-lighting,
// un-quantized, neutral 0. As of the Holy/E015 rev-5 fix this uniform is INTENTIONALLY
// left at neutral 0 and NO code drives it: the additive only ever tinted the PSX's
// untextured flat-colour terrain class (which Godot doesn't render), so
// PaletteSubsystem._deliver_output no longer delivers it. MapTintOverlay.update_illumination
// + the MapIlluminationDDA are retained-but-unwired for a future untextured-terrain scope.
// See MAP_ILLUMINATION_APPLIER_HOLY_E015.md §11.
uniform vec3 map_illum_add = vec3(0.0);

// {33} Color Field palette-content affine (ScenarioVM). The event-script
// whole-scene fade rewrites the map palette as `entry = entry*scale + bias`
// (5-bit CLUT space in FFT; normalized [0,1] here), broadcast alongside every
// unit sprite's CLUT. Applied to the sampled palette entry BEFORE lighting so
// it faithfully mirrors the CLUT rewrite (the polygon is then lit through the
// modified palette). Identity by default. See ScenarioVM._op_color_field and
// research/working_documents/scenario_1_captures/prayer_screen_tint_quad_decode.md.
// The {33} Color Field whole-scene wash (sepia/door-fade/lightning) is now folded
// through the unified color stack (color_apply, ADR-0067), driven by MapComposer
// pushing color_layer_* uniforms. See ScenarioVM._op_color_field.

// PAR (ADR-0036): Pattern 1, full-stretch. Multiplies clip_pos.x only, after
// PROJECTION_MATRIX * MODELVIEW_MATRIX. The world stays PAR-blind; CUSTOM0 (the
// face centroid feeding GTE depth) is never PAR'd. Via the shared seam
// (ADR-0060) so one debug scrub drives every opt-in subsystem in unison.
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

// Varyings for fragment shader
varying float palette_id;
varying vec3 world_normal;  // For debug (normals-as-color) + per-pixel fallback

// PSX Gouraud: the directional term is computed PER VERTEX (GTE NCDS/NCCS runs at
// each vertex) and the resulting vertex COLORS are interpolated across the polygon.
// That interpolation is a straight line between two lit endpoints -> always
// monotonic. Interpolating the NORMAL and doing max(0,dot) PER PIXEL instead
// produces a dark valley where a face straddles two lights: at mid-face the
// normal faces neither light, both dots clamp to 0, and the pixel collapses to
// ambient-only even though both endpoint vertices are bright. That valley is the
// "dark band" PSX never shows. Compute the diffuse term at the vertex and pass it
// as a varying so the hardware Gouraud-interpolates it, exactly like PSX.
varying vec3 v_diffuse;

// The triangle's 3 UV verts (baked in CUSTOM2.xy/.zw + CUSTOM3.xy), constant across the
// face, for the perimeter-aware snap's barycentric computation.
varying vec2 uv_v0;
varying vec2 uv_v1;
varying vec2 uv_v2;

// A/B toggle: true = faithful PSX per-vertex Gouraud (default), false = the old
// per-pixel path (kept so the band can be reproduced/compared in the same rig).
uniform bool lighting_per_vertex = true;


// Sum the three directional lights against a normal, each clamped at 0 (a light
// behind the surface contributes nothing). Shared by the per-vertex (Gouraud) and
// per-pixel paths so both evaluate identical math — only the sample rate differs.
vec3 psx_diffuse(vec3 n) {
	vec3 lc = vec3(0.0);
	float a;
	a = dot(n, light1_direction); if (a >= 0.0) { lc += light1_color * a; }
	a = dot(n, light2_direction); if (a >= 0.0) { lc += light2_color * a; }
	a = dot(n, light3_direction); if (a >= 0.0) { lc += light3_color * a; }
	return lc;
}

void vertex() {
	// Extract palette ID from vertex color red channel (0.0-1.0 maps to 0-15)
	palette_id = COLOR.r * 15.0;

	// Triangle's 3 UV verts (same on all 3 verts of the face -> constant across it).
	uv_v0 = CUSTOM2.xy;
	uv_v1 = CUSTOM2.zw;
	uv_v2 = CUSTOM3.xy;

	// A diagnostic lift of the water surface, DEFAULT 0.0 (SkirtConfig.PROPERTY_META).
	// It is only ever SET on water-surface materials, and that is exactly why it is
	// off: lifting one side of an edge whose other side is a wall or a shore opens a
	// see-through crack along the join, 1 px per 0.01 of lift. What actually covers
	// that join is the water skirt. Kept as a knob so the artifact can be reproduced
	// on demand; it is NOT part of the wave effect, so it must not ride on
	// `enable_waves`.
	VERTEX.y += water_surface_offset;

	// Optional wave effect
	if (enable_waves) {
		// Combine two sine waves for more natural water motion
		float wave = sin(VERTEX.x * wave_frequency + animation_time * wave_speed);
		wave += sin(VERTEX.z * wave_frequency * 0.7 + animation_time * wave_speed * 1.3) * 0.5;

		// Apply to vertex height
		VERTEX.y += wave * wave_height;

		// Adjust normals for proper lighting on waves
		float offset = 0.1;
		float wave_dx = sin((VERTEX.x + offset) * wave_frequency + animation_time * wave_speed) -
		                sin((VERTEX.x - offset) * wave_frequency + animation_time * wave_speed);
		float wave_dz = sin((VERTEX.z + offset) * wave_frequency * 0.7 + animation_time * wave_speed * 1.3) * 0.5 -
		                sin((VERTEX.z - offset) * wave_frequency * 0.7 + animation_time * wave_speed * 1.3) * 0.5;

		vec3 tangent_x = normalize(vec3(offset * 2.0, wave_dx * wave_height, 0.0));
		vec3 tangent_z = normalize(vec3(0.0, wave_dz * wave_height, offset * 2.0));

		NORMAL = normalize(cross(tangent_z, tangent_x));
	}

	// Pass normal to fragment shader (used for debug + the per-pixel fallback).
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);

	// PSX Gouraud: evaluate the directional term at the vertex; the hardware
	// interpolates the resulting color across the polygon (monotonic, no band).
	v_diffuse = psx_diffuse(world_normal);

	// Per-face centroid in CUSTOM0 (local space) -> MODELVIEW; STANDARD mode (0).
	ot_computed_depth = ot_depth(CUSTOM0.xyz, PROJECTION_MATRIX, MODELVIEW_MATRIX, 0);

	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// FFT visible-angles cull, gated by VISIBLE_ANGLES_CULL_MODE in the seam
	// (a `const`, not a runtime toggle — ADR-0190 dec. 1). Runs
	// BEFORE PAR so the final POSITION write is the seam helper; a culled vertex
	// is already off-screen (2,2,2,1), and scaling its x keeps it off-screen.
	fft_apply_visible_angles_cull(clip_pos, CUSTOM1.r);
	// PAR (Pattern 1, full-stretch, via the shared seam).
	POSITION = pixel_aspect_full(clip_pos);
}

void fragment() {
	// Discretize UV to always sample from texel centers
	// This prevents interpolation artifacts at diagonals
	ivec2 tex_size = textureSize(indexed_texture, 0);
	vec2 ts = vec2(tex_size);

	// Perimeter-aware UV snap (see uv_snap_* uniforms). Work in TEXEL space. Pull the
	// sample toward the triangle's UV centroid, scaled by barycentric perimeter-closeness,
	// then apply the global offset, then snap to the texel center. uv_snap_centroid==0 and
	// zero offset => identity (plain floor snap, today's behavior).
	vec2 p = UV * ts;
	vec2 a = uv_v0 * ts;
	vec2 b = uv_v1 * ts;
	vec2 c = uv_v2 * ts;
	float den = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y);
	if (uv_snap_centroid > 0.0 && abs(den) > 1e-5) {
		float wa = ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / den;
		float wb = ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / den;
		float peri = clamp(1.0 - 3.0 * min(wa, min(wb, 1.0 - wa - wb)), 0.0, 1.0);
		vec2 toc = (a + b + c) / 3.0 - p;
		if (length(toc) > 1e-4) {
			p += normalize(toc) * uv_snap_centroid * pow(peri, uv_snap_perimeter);
		}
	}
	p += vec2(uv_snap_offx, uv_snap_offy);
	vec2 uv_snapped = (floor(p) + vec2(0.5)) / ts;

	// Sample indexed texture to get color index (0-15)
	vec4 indexed = texture(indexed_texture, uv_snapped);
	float color_index = indexed.r * 15.0;  // R channel contains palette index

	// Determine which palette row to use
	float palette_row = palette_id;  // Default: use palette_id directly (0-15)

	// Check if THIS palette animates. The schedule is per palette id, so two palettes
	// on the same polygon batch can run different frame ranges at different rates.
	int palette_id_int = clamp(int(palette_id + 0.5), 0, 15);
	int frame_count = palette_anim_count[palette_id_int];

	if (enable_palette_animation && frame_count > 0) {
		float frame_duration = max(palette_anim_duration[palette_id_int], 1.0);
		int tick = int(animation_time / frame_duration);

		int frame_num;
		if (palette_anim_mode[palette_id_int] == PALETTE_ANIM_FORWARD_AND_REVERSE && frame_count > 2) {
			// 3 frames → sequence 0, 1, 2, 1 (repeat)
			int total_cycle = frame_count * 2 - 2;
			int cycle_pos = tick % total_cycle;
			frame_num = cycle_pos < frame_count ? cycle_pos : total_cycle - cycle_pos;
		} else {
			// ForwardLooping — 4 frames → 0, 1, 2, 3 (repeat). Also the degenerate
			// fwd+rev cases (1 or 2 frames), where the reverse leg is empty.
			frame_num = tick % frame_count;
		}

		// Map to animation frame rows (16-31)
		palette_row = 16.0 + float(palette_anim_start[palette_id_int] + frame_num);
	}

	// Look up final color in palette texture
	vec2 palette_uv = vec2(
		(color_index + 0.5) / 16.0,  // Center of pixel for color
		(palette_row + 0.5) / 32.0   // Center of pixel for palette
	);

	vec4 final_color = texture(palette_texture, palette_uv);

	// Discard fully transparent pixels (index-0 / transparent-black palette slot). The
	// atlas is edge-padded (IndexedAtlasDilator, map.atlas_dilate_passes) so covered
	// fragments at a patch edge sample real terrain instead of a transparent hole — the
	// remaining discards are genuine interior transparency, not seam cracks.
	if (final_color.a < 0.5) {
		discard;
	}

	// {33} Color Field palette-content rewrite — modify the CLUT entry in place
	// (palette space, before lighting) so the whole-scene fade tints the map through
	// its modified palette, exactly as the PSX CLUT rewrite does. Fold the single {33}
	// field layer MapComposer pushed (identity when no field is active); clamp matches
	// the additive-field case (scn8 idx270 mode-0 can overflow). ADR-0067.
	final_color.rgb = clamp(color_apply(final_color.rgb, 0), vec3(0.0), vec3(1.0));

	// ========================================
	// PSX lighting — per-vertex Gouraud (faithful) with a per-pixel A/B fallback
	// ========================================
	vec3 normal = normalize(world_normal);
	// v_diffuse is the Gouraud-interpolated vertex diffuse (matches PSX). The
	// per-pixel branch re-evaluates against the interpolated normal — kept only
	// to reproduce the dark-band artifact side by side.
	vec3 light_color = lighting_per_vertex ? v_diffuse : psx_diffuse(normal);

	// PSX GTE model: pixel = texture × (ambient + Σ lightGain·max(0,N·L)), then
	// clamp the FINAL pixel. light*_color are GAIN coefficients that can exceed
	// 1.0 (the mesh's overbright warm key light) — the end-stage clamp below is
	// the PSX per-vertex saturation. The old `ambient × 1.5` was GaneshaDx's fudge
	// to claw back brightness lost when the lights were clamped to white; with the
	// true (unclamped) light gains that compensation is wrong — drop it.
	vec3 ambient_term = ambient_light;
	vec3 diffuse_term = light_color;
	// Combat map tint already folded into final_color pre-lighting via
	// color_apply (the faithful CLUT rewrite, ADR-0067) — no post-lighting add.
	vec3 lit_color = final_color.rgb * (ambient_term + diffuse_term);

	// Map illumination (FUN_80090dec): the flat 8-bit additive brightness overlay, drawn
	// over the lit terrain (post-lighting, un-quantized). Neutral 0 ⇒ a true no-op on
	// non-effect maps. This is the smooth 8-bit flood the 5-bit CLUT fold couldn't do —
	// the fix for Holy/E015's "clicking". The clamp below saturates it, faithful to PSX.
	lit_color += map_illum_add;

	// Clamp and output
	vec3 final = clamp(lit_color, vec3(0.0), vec3(1.0));

	// PSX framebuffer snap — ordered dither + 15-bit quantize, the last thing the real
	// GPU does before the pixel lands in VRAM. `final` is already in sRGB/display space
	// (this shader deliberately takes no source_color hint, matching GaneshaDx's linear
	// handling), so unlike screen_background.gdshader it needs no round trip to get
	// there. 256.0 is FFT's battle framebuffer width.
	//
	// Deliberately ABOVE the debug overrides: modes 1-5 are diagnostics (normals as
	// colour, lighting with no albedo) where a 5-bit snap is noise on the readout, and
	// each of them overwrites `final` wholesale — so putting the snap here is what makes
	// "only the real path is quantized" true, with no extra branch.
	final = psx_dither_and_quantize(final, FRAGCOORD.xy, VIEWPORT_SIZE, 256.0);

	// --- Live lighting-debug overrides (isolate the pieces to see what's wrong) ---
	if (map_light_debug == 1) {          // normals encoded as color
		final = 0.5 + 0.5 * normal;
	} else if (map_light_debug == 2) {   // lighting only (white albedo, no texture)
		final = clamp((ambient_term + diffuse_term) * map_light_boost, vec3(0.0), vec3(1.0));
	} else if (map_light_debug == 3) {   // ambient contribution only
		final = clamp(ambient_term * map_light_boost, vec3(0.0), vec3(1.0));
	} else if (map_light_debug == 4) {   // directional contribution only
		final = clamp(diffuse_term * map_light_boost, vec3(0.0), vec3(1.0));
	} else if (map_light_debug == 5) {   // albedo only (texture, no lighting)
		final = clamp(final_color.rgb, vec3(0.0), vec3(1.0));
	}

	// Convert sRGB to linear for Forward+ (Godot will convert back to sRGB for display)
	// This prevents the "washed out" colors from double sRGB conversion
	ALBEDO = pow(final, vec3(2.2));

	// Flat per-face OT depth (constant across the face) — unified model.
	DEPTH = ot_computed_depth;
}
