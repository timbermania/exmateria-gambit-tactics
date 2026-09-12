class_name UI3OwnerColors
extends RefCounted

## The ownership-map palette (ADR-0088 Amendment 6 §1/§3): a per-rank owner color, plus
## the ONE reserved ALARM color that unowned payload (the registration-audit failure, §3)
## is painted. Pure + sceneless — the map mechanism (UI3OwnerColorMap) and the page legend
## (UI3RegistryView swatches) both read it, so the swatch beside a row and the pixels on
## screen are the same color.
##
## ROYGBIV down the list (Amendment 6 revision, 2026-08-12): color_for_rank(rank, n) is a
## red→violet ramp keyed to an element's position in the FLATTENED UI3 panel list (the
## depth-first display order), NOT its registration index. Hue steps are equal in OKLCH, so
## "equally spaced" means equal *perceived* difference (HSV hue is not perceptually
## uniform — green sprawls, blue/violet compress). The legend reads top→bottom as a clean
## rainbow.
##
## LIGHTNESS ZIGZAG (Amendment 6 §8, 2026-08-13): hue alone compressed as N grew (adjacent
## OKLab distance 0.083 @N=8 → 0.039 @N=16 — "the colors are too similar"). Chroma is
## already at the gamut edge, so lightness is the free axis: L alternates dark/light by
## rank (even→_L_LOW, odd→_L_HIGH) while hue stays monotonic. Adjacent rows therefore
## always differ in brightness even where their hues are close, without breaking the
## top→bottom rainbow order. Note the ramp is no longer *uniform* in OKLab (L wobbles by
## design); the distinctness guard measures the min pairwise/adjacent OKLab distance.
##
## This REVERSES the prior stability invariant. The old color_for(i) depended only on i so
## a row never changed color as elements registered/unregistered; the ramp instead depends
## on (rank, n), so it re-spreads when the membership or shape of the list changes (N moves,
## ranks shift). That reshuffle is deliberate — it is the cost of an *even* rainbow over
## the current list — and is confined to membership changes: within a single map-on session
## the assignment is fixed. The user asked for spatial (list) order over stability; §1.
##
## ALARM stays reserved by construction: the ramp's hue arc stops at violet (_H_END, short
## of magenta ~328°) at a fixed moderate lightness/chroma, so no rank can ever resolve to
## the full-saturation magenta ALARM. (The old proof was "fixed HSV sat/val plane"; the
## equivalent proof now is "bounded OKLCH arc that never reaches magenta".)

## The reserved alarm color for payload owned by NO registered element (§3) — a
## full-saturation magenta, deliberately outside the ramp's hue arc.
const ALARM := Color(1.0, 0.0, 1.0)

# The ramp steps hue at a fixed chroma, and ZIGZAGS lightness by rank (Amendment 6 §8):
# even ranks take the darker L, odd ranks the lighter, so *adjacent* rows always differ in
# brightness even when their hues have compressed close (the "colors too similar" fix —
# the user asked for a second, brightness dimension). The two L levels straddle the prior
# fixed 0.72; moderate chroma keeps every step inside the sRGB gamut (so gamut-clamping
# never collapses two ranks together) while staying vivid enough to read as swatches.
const _L_LOW := 0.62
const _L_HIGH := 0.82
const _C := 0.125
# The ROYGBIV arc in OKLCH hue degrees: red (~29°) → violet (~300°). The end stops short
# of magenta (~328°) so no owner color can approach the reserved ALARM.
const _H_START := 29.0
const _H_END := 300.0


## The owner color for an element at flattened-list `rank` of `n` total (0-based). A
## perceptually-even red→violet ramp: rank 0 is red, rank n-1 is violet — hue MONOTONIC by
## rank, with lightness ZIGZAGGING dark/light between adjacent ranks so neighbours stay
## distinct even where the hue arc compresses. Deterministic and never equal to ALARM.
static func color_for_rank(rank: int, n: int) -> Color:
	var r := clampi(rank, 0, maxi(n - 1, 0))
	var t := 0.0
	if n > 1:
		t = float(r) / float(n - 1)
	var hue_rad := deg_to_rad(lerpf(_H_START, _H_END, t))
	var l: float = _L_LOW if (r % 2 == 0) else _L_HIGH
	return _oklab_to_color(l, _C * cos(hue_rad), _C * sin(hue_rad))


## The OKLab coordinates (L, a, b) of an sRGB color — the perceptual space the ramp is
## spaced in and the ownership-map distinctness guard measures distance in.
static func oklab(c: Color) -> Vector3:
	var lr := _srgb_to_linear(c.r)
	var lg := _srgb_to_linear(c.g)
	var lb := _srgb_to_linear(c.b)
	var l := 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
	var m := 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
	var s := 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
	var l_ := _cbrt(l)
	var m_ := _cbrt(m)
	var s_ := _cbrt(s)
	return Vector3(
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


## The OKLCH hue of an sRGB color in degrees [0, 360) — used to assert the ramp runs
## red→violet monotonically down the list.
static func oklab_hue_deg(c: Color) -> float:
	var lab := oklab(c)
	return fposmod(rad_to_deg(atan2(lab.z, lab.y)), 360.0)


# --- OKLab <-> sRGB (Björn Ottosson) -----------------------------------------
static func _oklab_to_color(ll: float, aa: float, bb: float) -> Color:
	var l_ := ll + 0.3963377774 * aa + 0.2158037573 * bb
	var m_ := ll - 0.1055613458 * aa - 0.0638541728 * bb
	var s_ := ll - 0.0894841775 * aa - 1.2914855480 * bb
	var l := l_ * l_ * l_
	var m := m_ * m_ * m_
	var s := s_ * s_ * s_
	var r := 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
	var g := -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
	var b := -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
	return Color(
		clampf(_linear_to_srgb(r), 0.0, 1.0),
		clampf(_linear_to_srgb(g), 0.0, 1.0),
		clampf(_linear_to_srgb(b), 0.0, 1.0))


static func _srgb_to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _linear_to_srgb(c: float) -> float:
	var x := clampf(c, 0.0, 1.0)
	return x * 12.92 if x <= 0.0031308 else 1.055 * pow(x, 1.0 / 2.4) - 0.055


static func _cbrt(x: float) -> float:
	return pow(x, 1.0 / 3.0) if x >= 0.0 else -pow(-x, 1.0 / 3.0)
