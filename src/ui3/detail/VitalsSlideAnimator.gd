class_name VitalsSlideAnimator
extends RefCounted
## The Formation → Status(detail) ○-press SLIDE animation (FORMATION_SCREEN.md
## §15.1, §15.5, §15.9) — phase 1 of the three-phase transition.
##
## Decoded from `FUN_ROSTER_MENU_OVERLAY__8010d0cc` (WORLD.BIN overlay, base
## 0x800E0000): the vitals-bar + nameplate group rises bottom→top by replaying a
## BAKED keyframe table, NOT a float tween. Each frame the animator reads
## `srcY = *(short*)(0x8018ABD6 + counter*2)` where `counter` increments one step
## per menu tick, and the panel screen-Y = settled_Y + srcY. So the table values
## are the source-Y OFFSET ABOVE the settled top position: 144 px = docked at the
## formation bottom, 0 = settled at the detail top.
##
## The table (RAM 0x8018ABD6 = WORLD.BIN file 0xAABD6, live == disc byte-for-byte)
## is a symmetric bell `{4,13,31,67,139,144,139,67,31,13,4,0}`; the OPENING slide
## plays the descending half (indices 10-16): `{144,139,67,31,13,4,0}`.
##
## Cadence (§15.5/§15.9): each keyframe is held ~2 display frames (≈30 Hz menu
## tick). As with `BoxOpenAnimator`, the HOLD lives in the driver (_process ticks
## every 2/60 s) and `offset_at_frame(n)` walks the table one index per frame — so
## the two animators compose the same way. Pure/static, guarded by
## `VitalsSlideAnimatorTest`.

## The slide keyframe table `world_menu_slide_curve` — descending half of the WORLD
## bell (0x8018ABD6 indices 10-16). PX of source-Y offset ABOVE the settled top.
const SLIDE_CURVE: Array[int] = [144, 139, 67, 31, 13, 4, 0]

## Last valid curve index (clamp target — the counter holds at the settled 0).
const CURVE_LAST := 6


## The source-Y offset (px above the settled top) at animation frame `n`. Walks the
## table one index per frame; clamps to the docked start (144) below 0 and to the
## settled end (0) past the last index, so the panel holds settled forever.
static func offset_at_frame(frame: int) -> int:
	var i := frame
	if i < 0:
		i = 0
	if i > CURVE_LAST:
		i = CURVE_LAST
	return SLIDE_CURVE[i]


## The first frame at which the group has fully settled (offset reaches 0 and holds).
static func settle_frame() -> int:
	return CURVE_LAST
