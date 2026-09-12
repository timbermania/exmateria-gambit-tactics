class_name SpriteSlideAnimator
extends RefCounted
## The Formation "Item → Equip" unit sprite-slide (FORMATION_SCREEN.md §15.23,
## RE round 22 — see tmp/equip_re/FINDINGS_corrected_model.md in the RE worktree).
##
## Unlike VitalsSlideAnimator (§15.1) and BoxOpenAnimator (§15.17), there is NO baked
## ROM keyframe table to replay: the slide is EMERGENT per-frame. The OT / GPU packet
## buffer (~0x801f0800+) is rebuilt every frame, so there is no persistent per-unit
## screen-X source variable to mirror — a broad RAM scan across the 30 transition dumps
## found only per-frame OT slots, never an accumulator. Ground truth is the identity-
## tracked (by CLUT) sprite trajectory, which is an ACCELERATING (ease-in) ramp:
## non-selected clut 14741 held x≈185 (f0-5) then ramped 186→248 over f6-20 with the
## per-frame delta GROWING 1,2,2,3,3,4,4,5,5,…,8 px before exiting off the right edge.
##
## So the port models the slide as an ease-in tween (frac = t²) over the measured
## duration, driving each unit between caller-supplied endpoints. The class is generic:
## "selected vs non-selected", "exit-right", and "enter diagonally from top" are just
## endpoint choices the caller supplies —
##   - non-selected → settle OFF the right edge (or a top start for the diagonal class);
##   - selected → settles at SETTLE_PX, barely moving.
## It yields only POSITION, never a size: the unit quads are 24×40 in all 30 oracle
## frames (no scale). Pure/static, guarded by SpriteSlideAnimatorTest.
##
## Vault: [[Equip Sub Screen]]

## The selected unit's settled screen position, measured from oracle png/step/f29.png
## (256×240): bright pixels x[157..174] y[153..193], center ≈(166,173) = x 0.65W,
## y 0.72H = bottom-right quadrant, toward its left side (RE21 ~(168,174); user-confirmed).
const SETTLE_PX := Vector2(166, 173)

## The slide length in logical frames — the measured f6..f20 motion window (~14-16
## frames). The panel-close (f0-5) and settle+reopen (f21-29) phases sit outside this.
const SLIDE_DURATION := 16


## The eased screen position at animation frame `n`, tweening `start` → `settle` with
## an ACCELERATING (ease-in, frac = t²) profile over `duration` frames. Frame 0 is
## exactly `start`; frame >= `duration` holds exactly at `settle`; negative frames hold
## at `start`. At the midpoint only ¼ of the distance is covered (vs ½ for linear) —
## the §15.23 accelerating shape.
static func position_at_frame(start: Vector2, settle: Vector2, frame: int, duration: int) -> Vector2:
	if duration <= 0:
		return settle
	var f := frame
	if f < 0:
		f = 0
	if f > duration:
		f = duration
	var t := float(f) / float(duration)
	var frac := t * t
	return start.lerp(settle, frac)


## The first frame at which the slide has fully settled (reaches `settle` and holds).
static func settle_frame(duration: int) -> int:
	return duration
