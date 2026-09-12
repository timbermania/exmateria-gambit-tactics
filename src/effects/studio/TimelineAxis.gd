extends RefCounted
## The frame↔pixel transform for the Effect Studio timeline — a small, pure,
## testable deep module the view leans on for every coordinate (draw AND
## hit-test). Ported from the DAW piano-roll's tick↔x math
## (fft-plugin FFTPianoDetailView.cpp:301-309), retargeted from ticks to effect
## frames and given the cursor-anchored zoom the JUCE files left to the caller.
##
## Model:  x = base_x - scroll_x + frame * pixels_per_frame
## where `base_x` is the gutter width + pad (the frame-0 anchor at scroll 0) and
## `scroll_x` is the horizontal pan in pixels. The inverse clamps to frame ≥ 0.
##
## No `class_name` — preloaded by path (ADR-0004 cache-safety), like the effect
## subsystems and the score model.

## Zoom band (pixels per effect frame). Effect timelines run ~0…600 frames, so a
## fraction-of-a-pixel floor still shows the whole thing, and 40 px/frame is a
## deep single-keyframe zoom.
const MIN_PPF: float = 0.15
const MAX_PPF: float = 40.0
const DEFAULT_PPF: float = 1.5

var pixels_per_frame: float = DEFAULT_PPF
var scroll_x: float = 0.0
var base_x: float = 0.0

## The zoom band is PER INSTANCE, defaulting to the shared band above. The FEDS Key
## roll (ADR-0085 amendment 2026-08-21d) needs to open FITTED to one pair, and a pair
## whose tightest note is a single effect frame fits at ~108 px/frame — past MAX_PPF,
## which is the ceiling of the axis the whole editor band SHARES. The roll does not
## share that axis, so it does not inherit its ceiling; every other consumer constructs
## an axis and never touches these, so their band is exactly what it was.
var min_ppf: float = MIN_PPF
var max_ppf: float = MAX_PPF


## Widen (or narrow) THIS axis's zoom band, then re-clamp the live scale into it.
## Call before `configure` when opening at a scale outside the shared band.
func set_zoom_band(p_min_ppf: float, p_max_ppf: float) -> void:
	min_ppf = maxf(0.0001, p_min_ppf)
	max_ppf = maxf(min_ppf, p_max_ppf)
	pixels_per_frame = clampf(pixels_per_frame, min_ppf, max_ppf)


func configure(p_base_x: float, p_pixels_per_frame: float = DEFAULT_PPF) -> void:
	"""Set the gutter anchor and initial scale. scroll_x is left as-is (default 0)."""
	base_x = p_base_x
	pixels_per_frame = clampf(p_pixels_per_frame, min_ppf, max_ppf)


func frame_to_x(frame: float) -> float:
	"""Absolute effect frame → local pixel X."""
	return base_x - scroll_x + frame * pixels_per_frame


func x_to_frame(x: float) -> float:
	"""Local pixel X → absolute effect frame, clamped at 0 (frames are non-negative)."""
	return maxf(0.0, (x - base_x + scroll_x) / pixels_per_frame)


func zoom_at(factor: float, cursor_x: float) -> void:
	"""Multiply the scale by `factor`, keeping the frame under `cursor_x` fixed on
	screen (the pro-feel gesture). Scale is clamped to [MIN_PPF, MAX_PPF]."""
	var frame_under := x_to_frame(cursor_x)
	pixels_per_frame = clampf(pixels_per_frame * factor, min_ppf, max_ppf)
	# Solve scroll so frame_to_x(frame_under) == cursor_x at the new scale.
	scroll_x = base_x + frame_under * pixels_per_frame - cursor_x


## Round a frame to the nearest multiple of `step`. step ≤ 1 is frame-exact
## (plain rounding) — the snap-off / 1-frame grid. Static: the grid is stateless.
static func snap(frame: float, step: int) -> int:
	if step <= 1:
		return int(round(frame))
	return int(round(frame / float(step))) * step
