extends RefCounted
## CPU port of tile_overlay.gdshaderinc's `tile_overlay_color` for the FLAT-FILL case, so a
## flat_fill tile overlay can route through the compositor as a single-color vertex_flat quad instead
## of an in-scene blend material (COMPOSITOR_INPUT_CONTRACT_GENERALIZATION.md §4a).
##
## Why the barber-pole does NOT enter the fold shader: a flat_fill tile samples ONE constant CLUT
## index (`flat_index`), so the whole tile is a single color per (type, phase). The shimmer is the
## discrete 15-phase CLUT rotation `rot = ((idx-1+phase)%15)+1` (FUN_80088EEC) — a permutation of
## palette entries 1..15, index 0 fixed transparent. Rotating a single index each frame is trivial on
## the CPU, so the producer computes the resolved color here and stages it as the quad's per-prim
## modulate; the compositor stays a dumb rasterizer (frag_source=vertex_flat). This mirrors the shader
## math EXACTLY (rotate -> palette lookup -> pow(gamma) -> optional mono -> * tint) so the routed tile
## is byte-identical to the in-scene one, minus the display-space round-trip the compositor owns.
##
## Only flat_fill overlays route (they are the only transparent-blended tile types — the one textured
## barber-pole overlay, CURSOR_ACTIVE, is opaque). A textured tile would instead need the pre-baked
## 135-row palette approach (§4); this helper deliberately does not cover it.

const CYCLE := 15   # colors 1..15 rotate; index 0 stays the fixed/transparent slot


## The discrete barber-pole phase 0..14. `manual_phase` >= 0 freezes it (pause/scrub); otherwise it
## advances from the clock at `phase_rate` phases/sec (FFT ~15/s => a full cycle ~1s). Mirrors the
## shader's `int phase = (manual_phase>=0) ? manual_phase%CYCLE : int(mod(time*phase_rate, CYCLE))`.
static func phase_at(time: float, phase_rate: float, manual_phase: int) -> int:
	if manual_phase >= 0:
		return posmod(manual_phase, CYCLE)
	return int(fmod(time * phase_rate, float(CYCLE)))


## The resolved display color for a flat_fill tile of the given per-type params at `phase`. `palette`
## is the RANGETILE.palette.tga Image (16 wide, rows = BATTLE.BIN slot N). Returns the per-prim modulate
## the fold's vertex_flat path adds RAW (rgb) with the palette coverage alpha (a).
##
## RAW display-space (ADR-0074 endgame): NO pow(gamma). The fold blends in display space, so the CLUT
## value is added straight — mirroring formation_box_fold (whose ×gamma / ×2.2 clipped the bright
## indices and collapsed the gradient; the live box is a deep-amber GRADIENT, not a pale band). The
## sRGB→linear pow lives ONLY on the in-scene path (tile_overlay.gdshaderinc, tonemapped back). Removing
## it here — plus dropping the fold shader's `* psx_brightness` — takes the routed tile off the
## color-space + double-count bugs the box already shed. Guarded: check_no_cpu_color_math_in_fold.py.
static func flat_color(palette: Image, palette_row: int, flat_index: int, anim_mode: int, phase: int,
		mono: bool, tint: Color) -> Color:
	# Barber-pole rotation (anim_mode 1). idx 0 never rotates; here flat_index is a fixed >0 hue so it
	# always animates, but guard it exactly like the shader for parity.
	var rot := flat_index
	if anim_mode == 1 and flat_index > 0:
		rot = (flat_index - 1 + phase) % CYCLE + 1
	# Palette lookup: filter_nearest at texel (rot, palette_row) — the shader's
	# texture(range_palette, ((rot+0.5)/16, (row+0.5)/PALETTE_ROWS)).
	var base := palette.get_pixel(clampi(rot, 0, palette.get_width() - 1),
		clampi(palette_row, 0, palette.get_height() - 1))
	# RAW display-space CLUT value — no pow(gamma). See the docstring (mirror formation_box_fold).
	var r := base.r
	var g := base.g
	var b := base.b
	if mono:
		# Collapse to the ramp's brightness (max channel) so tint supplies the only hue.
		var m: float = maxf(r, maxf(g, b))
		r = m; g = m; b = m
	return Color(r * tint.r, g * tint.g, b * tint.b, base.a * tint.a)
