// FFT per-polygon visible-angles cull — replicates the PSX renderer's
// Stage 4 backface-cull early-out (DEPTH_MODE_RENDER_ORDER_GUIDE.md).
//
// On disk, each polygon carries a 16-bit bitfield (mesh-resource section
// at header +0xB0). Bits 2-13 (mask 0x3FFC) encode "do not draw at this
// camera-angle slot." The PSX renderer:
//
//     shift1 = ((angle - 1) >> 9) & 7        // 8 sub-quadrant buckets
//     shift2 = (angle >> 10) & 3             // 4 cardinal quadrants
//     if ((angle + 0x200) & 0x3FF) != 0:     // "between quadrants"
//         shift2 = 4
//     cull1 = ((vis & 0x3FFC) >> shift1) & 4
//     cull2 = ((vis & 0x3FFC) >> shift2) & 0x400
//     if cull1 != 0 || cull2 != 0: CULLED
//
// `vis_bits_f` is the per-triangle CUSTOM1.r float — round-trips a 16-bit int
// exactly. `psx_camera_angle` is the active in-game yaw on the PSX 0..0xFFF
// scale (0x000 = north, 0x400 = east, 0x800 = south, 0xC00 = west — matches
// FFT's BATTLE camera angle register). The whole test is gated by
// VISIBLE_ANGLES_CULL_MODE below — there is no runtime toggle, and the one this
// line used to name (`enable_visible_angles_cull`) was never built.
//
// Caller: in the vertex shader, after computing the regular clip POSITION,
// call `fft_apply_visible_angles_cull(POSITION, CUSTOM1.r)`. When culled, this
// pushes POSITION far outside the clip volume so all three vertices of the
// triangle land off-screen and the triangle is discarded by the rasterizer
// without invoking the fragment shader.

// 0 = off, 1 = diagnostic (cull every gated polygon, angle ignored),
// 2 = angle-aware (PSX renderer Stage 4 test against psx_camera_angle).
//
// A `const`, NOT a `global uniform`, and the difference is what a global uniform
// COSTS: its name has to exist in the consuming project's `project.godot`
// `[shader_globals]` block, and if it does not, NOTHING SAYS SO -- outside the editor
// the engine skips global-uniform validation entirely, so this file compiles and the
// name silently reads 0 (ADR-0238, correcting ADR-0169 dec. 4). That is a real install step to charge a consumer for, and
// this knob never justified it — nothing in the tree ever wrote it. There is no
// `RenderingServer.global_shader_parameter_set("visible_angles_cull_mode", …)`
// anywhere, so its only value in any session was the `2` that `project.godot`
// declared. The header above named `enable_visible_angles_cull` as "the F3
// toggle" that gates the test; that identifier does not exist in this repo
// either. A knob with no writer and a switch that was never built is a constant
// wearing a uniform's clothes.
//
// Changing modes is still one line — it is this line. That is not worse than
// editing `project.godot`, and it is one fewer name the addon asks its host for.
const int VISIBLE_ANGLES_CULL_MODE = 2;

// `psx_camera_angle` stays a global uniform, and the asymmetry is the point: it
// is WRITTEN, every frame, by `PSXDisplay.set_camera_angle()` (the platform
// port, #590), and read by every map surface. Pushing a per-frame value to one
// global is exactly what global uniforms are for; the alternative is a
// per-material push on a rebuild-heavy path.
#include "res://addons/exmateria_platform/display_port/psx_camera_angle.gdshaderinc"

bool fft_polygon_is_culled(float vis_bits_f) {
	int vis = int(vis_bits_f) & 0x3FFC;
	if (vis == 0) {
		return false;
	}
	// Mode 1: any polygon with cull bits set gets discarded, no matter where
	// the camera is. Over-culls — proves the data path is intact end-to-end.
	if (VISIBLE_ANGLES_CULL_MODE == 1) {
		return true;
	}
	int angle = psx_camera_angle & 0xFFF;

	int shift1 = ((angle - 1) >> 9) & 7;
	int shift2 = (angle >> 10) & 3;
	if (((angle + 0x200) & 0x3FF) != 0) {
		shift2 = 4;
	}

	int cull1 = (vis >> shift1) & 4;
	int cull2 = (vis >> shift2) & 0x400;
	return (cull1 != 0) || (cull2 != 0);
}

void fft_apply_visible_angles_cull(inout vec4 clip_pos, float vis_bits_f) {
	if (VISIBLE_ANGLES_CULL_MODE == 0) {
		return;
	}
	if (fft_polygon_is_culled(vis_bits_f)) {
		// Push outside the clip volume so all three vertices fall off-screen.
		// w > 0 with x/y/z > w trivially fails the clip test in every plane.
		clip_pos = vec4(2.0, 2.0, 2.0, 1.0);
	}
}
