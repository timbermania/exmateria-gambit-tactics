extends RefCounted
## The colour mux and its inverse — the pure math of authoring effect colour in MUXED
## (output) space (ADR-0089 colour-keyframe amendment, CONTEXT.md "Muxed colour" /
## "Reachable box" / "Inverse mux").
##
## Render is `ALBEDO = S ⊙ curve` (per-channel multiply; effect_particle_opaque.gdshader),
## where `S` is the emitter's representative sprite texel (EmitterSpriteColor) and `curve`
## is the three per-channel colour-curve values in [0,1]. So the author cares about the
## OUTPUT `T` (what renders), not the abstract curve inputs. This module:
##   • `mux(curve, S)`         — forward: T = S ⊙ curve (byte-identical to the ribbon read);
##   • `inverse_mux(T, S)`     — curve = T ⊘ S per channel, dead channel (S.k == 0) → 0;
##   • `clamp_to_box(T, S)`    — keep T inside the reachable box [0,S.r]×[0,S.g]×[0,S.b];
##   • `clamp_unit(c)`         — keep a CURVE triple inside [0,1]³.
##
## AUTHORING NO LONGER HAPPENS IN MUXED SPACE (the 2026-08-21 amendment — decision 4 amended
## a second time). The picker now authors the CURVE directly, so `clamp_to_box` and
## `inverse_mux` are out of the write path; what is left of this module on that path is
## `clamp_unit`. `mux` stays, and stays load-bearing: the ribbon and the picker's "renders
## as" swatch both need it to show what the multiply actually produces. `inverse_mux` and
## `clamp_to_box` remain the definition of the reachable box, which is still the thing the
## dead-channel report is about.
##
## No `class_name` (ADR-0004) — preloaded by path.


## Forward mux: the colour a particle renders for these curve values against sprite `s`.
## Per-channel multiply, identical to ColourRibbon.frame_colors' `c.k * sprite_base.k`, so
## the picker's preview and the ribbon can never disagree. Alpha forced opaque.
static func mux(curve: Color, s: Color) -> Color:
	return Color(curve.r * s.r, curve.g * s.g, curve.b * s.b, 1.0)


## Inverse mux: the curve values that render as muxed colour `t` against sprite `s`.
## `t ⊘ s` per channel. A dead channel (s.k == 0) can never be lit, so it locks at 0
## rather than dividing by zero — the target's value in that channel is unreachable and
## simply ignored. Result is NOT clamped; feed an in-box `t` (see clamp_to_box) for a
## curve in [0,1].
static func inverse_mux(t: Color, s: Color) -> Color:
	return Color(
		_div(t.r, s.r),
		_div(t.g, s.g),
		_div(t.b, s.b),
		1.0)


## Clamp muxed colour `t` into the reachable box [0,s.r]×[0,s.g]×[0,s.b] — the set of
## colours the multiply can actually produce. A dead channel clamps to exactly 0.
static func clamp_to_box(t: Color, s: Color) -> Color:
	return Color(
		clampf(t.r, 0.0, s.r),
		clampf(t.g, 0.0, s.g),
		clampf(t.b, 0.0, s.b),
		1.0)


## Clamp a CURVE triple into [0,1]³ — the authoring space since the picker stopped muxing.
## Every curve value in the unit cube is renderable (the sample table is bytes 0..255), so
## unlike `clamp_to_box` this refuses nothing an author can express; it only keeps a colour
## that arrived out of range from writing a sample the packer would have to clip.
static func clamp_unit(c: Color) -> Color:
	return Color(
		clampf(c.r, 0.0, 1.0),
		clampf(c.g, 0.0, 1.0),
		clampf(c.b, 0.0, 1.0),
		1.0)


static func _div(num: float, den: float) -> float:
	if den <= 0.0:
		return 0.0
	return num / den
