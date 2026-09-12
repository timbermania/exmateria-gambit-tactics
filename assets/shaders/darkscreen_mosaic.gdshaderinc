// Shared body for {76} Dark Screen's mosaic — the uniforms, the NDC vertex map and the
// per-slot coverage test. Two shaders include it and differ ONLY in their render_mode:
// the in-scene `blend_mix` twin, and the `compositor_layer` fold twin that a build whose
// engine fold owns compositing wears instead.
//
// 🔴 THE DIM MUST FOLD WHENEVER {78}'s BANNER DOES. The fold resolves at
// PRE_TRANSPARENT, so anything left in-scene as a transparent draws OVER the resolved
// layer. With the banner folded and the dim in-scene, the dim covered the banner —
// measured: at dim = 1.0 the brightest pixel in the whole banner band was (48,40,16),
// the fog colour, i.e. the text had vanished. The PSX orders them the other way (text
// at OT bucket 0, tint at bucket 1), and inside the fold `Fold.add`'s order_z restores
// that: the dim sits one rung BELOW the banner's two passes.
//
// {76} Dark Screen — the mosaic of growing, spinning squares that dims the whole
// frame (a dim, NOT a fade to black — the map stays readable) while {78} paints the
// victory-condition banner or the results sequence over it. Read line by line out of
// the task body `0x801CA664`:
// research/working_documents/DARKSCREEN_OPCODE_76_INVESTIGATION.md §13, validated
// against the running emulator in §14.
//
// This mirrors the camera-background pattern (screen_background.gdshader): the
// vertex() maps the quad corners straight to NDC so the mesh always fills the
// screen regardless of camera zoom/position. Flipped to the FOREGROUND: high
// render_priority + depth_test_disabled so it composites OVER the map/units as
// an overlay, and blend_mix so ALPHA does the PSX ½·bg+½·F blend in hardware.
//
// PSX facts baked in:
//   - Primitive colour F = RGB(48,40,16) — but not a packet constant: `0x801CACCC`
//     re-reads the live global `0x801D0078..7A` into every square every frame.
//   - Blend = abr mode 0 = ½·bg + ½·F, ONE packet per square per frame. The 72-byte
//     slot's second packet is its A/B double buffer, not a second draw (§13), so
//     there is no ¾·F core and the mosaic matches the single full-screen quad the
//     body swaps to at `0x801CADE4` exactly — which is why that hand-off is invisible.
//   - Squares SPIN. Corners sit at `angle + 512` and `angle + 1536` of a `size/4`
//     radius, so a slot is an axis-aligned square at angle 0 and the settled diamond
//     only at the 512 (= 45°) cap. In that rotated basis the shape is exactly the L1
//     ball of radius `size/4`, which is the coverage test below.
//   - Centres are the 288-slot quincunx lattice, basis (24,0)+(12,12); at full size
//     the balls tessellate exactly (L1 ball r=12 area 288 = cell 24*12), so the
//     settled field is a uniform half-blend over the whole screen.
//
// NO TIMING LIVES HERE. ScenarioDarkScreen evaluates the per-slot law — the
// `d²/(256·ScreenExpansionSpeed)` spawn delay that `Shape` picks the metric for, the
// `size`/`angle` ramps, and the retract that runs all of it backwards — and uploads
// the 288 `(size, angle)` pairs into `slot_state`. That keeps one testable source of
// truth for what is drawn instead of a copy of the law in each language.

// 24x12 RG-float: texel (col, row) = that slot's current (size 0..48, angle 0..512).
uniform sampler2D slot_state : filter_nearest, repeat_disable;
// The hold phase between expansion and retract: the body stops submitting the mosaic
// and submits ONE full-screen POLY_F4 instead (`0x801CADE4`). Identical coverage —
// this flag just spares the lattice walk and any float seam between the 288 balls.
uniform bool settled = false;
// Overlay colour F (RGB 48,40,16), supplied as the raw PSX 0..255 fraction (the same
// literal-value convention as psx_screen_blend.gdshaderinc — no source_color).
uniform vec3 fog_color = vec3(0.18823, 0.15686, 0.06274);
// In-square alpha = the PSX abr-0 half blend.
uniform float dim = 0.5;
// PSX native framebuffer the lattice pitch is measured against.
uniform vec2 fb_size = vec2(256.0, 240.0);

const float TAU_ = 6.28318530717958648;
// PSX angles are 4096 to the turn.
const float ANGLE_TURN = 4096.0;

void vertex() {
	// Map quad corners directly to NDC (fills the screen); depth_test_disabled
	// means the z we pick is irrelevant — the overlay always composites on top.
	// pixel-aspect-exempt: fullscreen NDC quad, not battle-space geometry — nothing to align to.
	POSITION = vec4(sign(VERTEX.xy), 0.0, 1.0);
}

void fragment() {
	float cov = settled ? 1.0 : 0.0;
	if (cov < 0.5) {
		vec2 px = SCREEN_UV * fb_size;
		// Lattice: centre = a*(24,0) + b*(12,12)  =>  a=(x-y)/24, b=y/12. Round to
		// the nearest (a,b) and scan the 3x3 neighbourhood — the nearest centres are
		// 17 px apart and a square's circumradius caps at 12, so 3x3 always contains
		// whichever slot covers this fragment.
		float a0 = floor((px.x - px.y) / 24.0 + 0.5);
		float b0 = floor(px.y / 12.0 + 0.5);
		for (int da = -1; da <= 1; da++) {
			for (int db = -1; db <= 1; db++) {
				vec2 c = vec2(24.0 * (a0 + float(da)) + 12.0 * (b0 + float(db)),
						12.0 * (b0 + float(db)));
				// Back to (col, row): cx = -12 + 12*col, and cy's origin depends on
				// the column's parity (the quincunx half-cell offset).
				float colf = (c.x + 12.0) / 12.0;
				if (colf < -0.5 || colf > 23.5) { continue; }
				int col = int(colf + 0.5);
				float rowf = ((col & 1) == 0) ? (c.y + 12.0) / 24.0 : (c.y + 24.0) / 24.0;
				if (rowf < -0.5 || rowf > 11.5) { continue; }
				vec2 st = texelFetch(slot_state, ivec2(col, int(rowf + 0.5)), 0).rg;
				float r = st.x * 0.25;          // half-diagonal px = size/4 (the >>14)
				if (r <= 0.0) { continue; }
				// Corner A is at `angle + 512`, corner B a quarter turn on; the quad
				// (c+A, c+B, c-A, c-B) is the L1 ball of radius r in that basis.
				float t = (st.y + 512.0) * (TAU_ / ANGLE_TURN);
				vec2 av = vec2(cos(t), sin(t));
				vec2 d = px - c;
				// +0.5 px so the exact tessellation at full size cannot show a seam
				// between two balls that meet on a shared edge; coverage is binary,
				// so the overlap it creates costs nothing.
				if (abs(dot(d, av)) + abs(d.x * -av.y + d.y * av.x) <= r + 0.5) {
					cov = 1.0;
				}
			}
		}
	}
	ALBEDO = fog_color;
	ALPHA = cov * dim;
}
