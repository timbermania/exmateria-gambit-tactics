class_name BoxOpenAnimator
extends RefCounted
## The generic FFT world-map menu-box OPEN animation (FORMATION_SCREEN.md §15.17).
##
## Decoded from `world_menu_window_open_scale` (WORLD.BIN `FUN_800ec954`) — the
## shared box-open used by 9 world-menu screens, including the unit-detail/Status
## screen builder (`world_detail_screen_builder` `FUN_800eaf3c`). The window
## container does NOT unfurl from a 1-px seed line (the §15.7 dynamic misread) —
## the rect grows CENTER-OUT on BOTH axes, driven by a per-frame counter through a
## baked easing table, keeping the rect's centre fixed and growing to `p %` of
## full size. At `p=100` the rect is unchanged (full window); at `p=0` it is a
## zero-size point at the centre.
##
## The math is ROM-integer (PSX GTE), live-confirmed pixel-exact against the
## transition-stage save states: full container rect `{4,126,250,108}` (display),
## at `p=60` the rendered container prim is exactly `{54,148,150,64}`.
##
## This class yields only the growing RECT; it says nothing about how the window is
## drawn into it. The mechanism is a SCISSOR, not a scale (§15.17, live-confirmed
## 2026-08-05 from a user paused mid-open): the fully-rendered window (frame chrome,
## bands, icons, text — all at native size/position) is CLIPPED to this rect and
## revealed center-out; the frame chrome appears only once the rect reaches the panel
## edges. DetailScene feeds this rect to the per-material `clip_world` aperture — it
## does NOT scale any geometry. (The earlier "only the backdrop scales" reading is
## superseded: nothing scales; the rect is the clip window.)
##
## Vault: [[Menu Window Box Open]]

## The easing table `world_menu_open_curve` (WORLD `0x801533b8`, int16[12]),
## PERCENT of full size, each value held ~2 frames. int16[12] so the frame
## counter can be clamped to 11 and stay at 100% forever.
const OPEN_CURVE: Array[int] = [10, 10, 60, 60, 90, 90, 95, 95, 100, 100, 100, 100]

## Last valid curve index (clamp target — `param_3 > 0xb -> 0xb`).
const CURVE_LAST := 11


## The scale percent at animation frame `n`. Normal speed walks the curve one
## index per frame (10,10,60,60,90,90,95,95,100…, ~9 frames to settle); `fast`
## (`DAT_8015326c == 2`) doubles the step (10,60,90,95,100, ~5 frames) — the path
## §15.7 timed. Clamped so `n >= 11` (or `>= 6` fast) holds at 100%.
static func progress_percent(frame: int, fast: bool = false) -> int:
	var i := (frame * 2) if fast else frame
	if i > CURVE_LAST:
		i = CURVE_LAST
	if i < 0:
		i = 0
	return OPEN_CURVE[i]


## The number of the first frame at which the box has fully settled (p reaches
## 100 and holds). Normal = index 8, fast = index 4 (halved step).
static func settle_frame(fast: bool = false) -> int:
	return 4 if fast else 8


## The center-out scaled container rect at scale percent `p` (0..100), using the
## ROM's integer math so it is byte-exact against the live prim:
##   w' = (w·p)/100                x' = x + w/2 − (w·p)/200
##   h' = (h·p)/100                y' = y + h/2 − (h·p)/200
## i.e. the rect keeps its centre and scales to p% in BOTH axes. `full` is the
## settled container rect (display space, e.g. `{4,126,250,108}`).
static func scaled_rect(full: Rect2i, p: int) -> Rect2i:
	var w: int = full.size.x
	var h: int = full.size.y
	var w2: int = (w * p) / 100
	var h2: int = (h * p) / 100
	var x2: int = full.position.x + w / 2 - (w * p) / 200
	var y2: int = full.position.y + h / 2 - (h * p) / 200
	return Rect2i(x2, y2, w2, h2)


## The scaled rect at animation frame `n` (convenience: progress_percent + scaled_rect).
static func rect_at_frame(full: Rect2i, frame: int, fast: bool = false) -> Rect2i:
	return scaled_rect(full, progress_percent(frame, fast))
