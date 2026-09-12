class_name ChangeJobWheel
extends RefCounted

## The Change-Job screen's job-selection WHEEL model (FORMATION_SCREEN.md §15.24, RE round 28).
##
## Pure, data-derived (ADR-0001): the set of jobs, their names, and their body sprites all come
## from the parsed `JobDatabase`/jobs.json — NOT hand-encoded. The ONE fact jobs.json does not carry
## is the per-job GENDER LOCK (a ROM job flag the parser never exported: Bard is male-only, Dancer
## female-only — both share a single sprite in the asset, `body_sprite_id_male == body_sprite_id_female`).
## That lock is named here as [GENDER_LOCKED_JOBS] with its ROM grounding; everything else derives.
##
## Screen model (dynamic, oracle formation_changejob_dest.sstate; static builder cites in §15.24):
## the settled screen centres the SELECTED unit's own avatar and rings it with one generic body per
## gender-appropriate generic job, arranged on an OVAL (isometric-squashed circle). The current job's
## ring member sits front-bottom-centre; the job title shows bottom-middle.
##
## Vault: [[Change Job Screen]]

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase



## FFT generic (player-usable) jobs occupy contiguous job ids 0x4A..0x5D (Squire..Mime) — the same
## span `JobDatabase.get_all_generic_jobs()` reads. Kept as ints for the gender-lock test below.
const GENERIC_JOB_FIRST := 0x4A
const GENERIC_JOB_LAST := 0x5D

## The two gender-locked generic jobs (ROM job-flag `Male`/`Female` bit; not in jobs.json). A unit can
## only change into jobs its sex allows, so the wheel omits the opposite-sex-locked job — which is why
## the oracle male-Ramza ring is 19, not 20 (0x5C Dancer dropped). job-id → the sex that MAY take it.
const JOB_MALE := "5b"     # Bard  — male-only
const JOB_FEMALE := "5c"   # Dancer — female-only

## --- Oval geometry (virtual px). STATICALLY DERIVED from the ROM placement builder
## `FUN_80119AA0 @0x80119AA0` (WORLD.BIN; §15.24 RE31) and VALIDATED to 0.0px on all 19 live ring
## members (oracle pcsx :8080, primscan of the 24×40 tp=0x0064/65 clut 0x38xx sprites). The oval is a
## COMPUTED rcos/rsin trig ring — NOT a baked table, NOT a 2D slide (the RE28/29 "no trig" was wrong:
## the code is pointer-dispatched via `PTR_FUN_8018baec[3]` with indirect rcos/rsin, so greps missed it).
##
## ROM: full circle = 0x1000 (4096); centre = (DAT_8018c918=124, DAT_8018c919=126) top-left basis;
## radiusX = scaleX·100>>12 = 100, radiusY = scaleY·0x3c>>12 = 60 (settled scale 0x1000). Sprites are
## 24×40 so the SPRITE-CENTRE ellipse is centre (128,126), rX 100, rY 60 (front member centre (128,186)).
## The selected AVATAR (`FormationScene.CHANGEJOB_CENTRE` (128,123)) is drawn separately, NOT on the ring.
const CENTRE := Vector2(128.0, 126.0)
const RADIUS_X := 100.0
const RADIUS_Y := 60.0
## The current job's ring member sits at the FRONT (bottom-centre) of the oval; ring walks from there.
## ROM base angle = 0x400 (a quarter of 0x1000 = +90° screen-space, i.e. straight DOWN → bottom-front).
## Angles measured screen-space (0° = +X right, +90° = DOWN, matching PSX screen Y-down).
const FRONT_ANGLE_DEG := 90.0
## ROM angular step per member = 0x1000/count with INTEGER truncation (4096/19 = 215, NOT 215.6) — the
## ring is very slightly non-uniform on the far side; replicating the truncation is what makes the fit 0px.
const FULL_CIRCLE := 4096.0


## The ordered generic job ids a unit of the given sex can change into — the wheel's ring membership.
## Data-derived from the 0x4A..0x5D span, minus the opposite-sex gender-locked job. Order is job-id
## ascending (the ROM job-table order); the oval placement maps index→angle.
static func job_ids_for_sex(is_female: bool) -> Array:
	var out: Array = []
	for jid in range(GENERIC_JOB_FIRST, GENERIC_JOB_LAST + 1):
		var key := "%02x" % jid
		if is_female and key == JOB_MALE:
			continue        # a female cannot become a Bard
		if not is_female and key == JOB_FEMALE:
			continue        # a male cannot become a Dancer
		out.append(key)
	return out


## The body sprite file id (UNIT atlas) for a wheel member of `job_id` at `is_female` — the exact
## per-sex generic sprite `JobDatabase` resolves (ADR-0013). Feeds the sprite render like the roster.
static func body_sprite_id(job_id: String, is_female: bool) -> int:
	return JobDatabase.get_sprite_id(job_id, is_female)


## The display name for a job id (e.g. "Squire") — the bottom-middle title text (beat 9). From jobs.json.
static func job_name(job_id: String) -> String:
	return JobDatabase.get_job(job_id).get("name", job_id)


## The oval screen position (virtual px) of the ring member at `index` of `count`, walking evenly
## around the oval. `front_index` is the (possibly fractional, for a smooth rotation glide — §15.24
## RE29) member index currently sitting at the FRONT (bottom-centre): member `front_index` lands on
## `FRONT_ANGLE_DEG`, the rest fan out from it. `direction` = +1 clockwise, −1 counter-clockwise.
## Default −1: the ROM loop (FUN_80119AA0) DECREMENTS the job slot as the angle increases (`sVar1--`
## while angle += step), so ascending job-array index walks the oval counter-clockwise (§15.24 RE31).
static func ring_position(index: int, count: int, front_index: float = 0.0, direction: int = -1) -> Vector2:
	if count <= 0:
		return CENTRE
	# ROM-faithful: angle in the 4096-unit circle, per-member step INTEGER-truncated (0x1000/count),
	# base 0x400 = bottom-front (§15.24 RE31, FUN_80119AA0). front_index carries the fractional ←/→
	# rotation glide (the ROM's rotOffset), so it stays smooth between slots.
	var step := float(int(FULL_CIRCLE / float(count)))
	var base := FULL_CIRCLE * (FRONT_ANGLE_DEG / 360.0)   # 0x400 for 90°
	var a := (base + direction * step * (float(index) - front_index)) / FULL_CIRCLE * TAU
	return CENTRE + Vector2(cos(a) * RADIUS_X, sin(a) * RADIUS_Y)


## The painter's-order DEPTH BIAS of the ring member at `index` — a normalized [-0.5, +0.5] priority,
## MONOTONIC in the member's oval screen-Y, that makes a front (bottom, larger screen-Y) member draw
## OVER a back (top, smaller screen-Y) one. STATICALLY DERIVED from the ROM placer `FUN_80119AA0`
## (§15.24 RE31): that loop walks each member's angle and accumulates a per-position OT index `iVar6`
## (start 0x1e, ±1 per member) that it hands the sprite emitter `FUN_8011814c(pos, pal, iVar6)` — larger
## `iVar6` = inserted deeper in the ordering table = drawn LATER / on top. Simulating the accumulator for
## the n=19 ring shows `iVar6` is monotone in screen-Y (front-bottom = max, top-back = min); the only
## departure is a ±1 left/right asymmetry between MIRROR members, which sit on opposite oval sides and
## never overlap — so a pure screen-Y priority reproduces the exact occlusion of every overlapping pair.
## `front_index`/`direction` carry the ←/→ rotation glide, so depth re-sorts as the ring turns (the ROM
## recomputes `iVar6` every frame). The caller maps this bias onto a sub-rung Z within the body's OT band.
static func ring_depth_bias(index: int, count: int, front_index: float = 0.0, direction: int = -1) -> float:
	if count <= 0:
		return 0.0
	var y := ring_position(index, count, front_index, direction).y
	return clampf((y - CENTRE.y) / (2.0 * RADIUS_Y), -0.5, 0.5)


## --- ENTRY animation (§15.24 RE29, dynamic per-vsync capture) -------------------------------------
## The ring members SLIDE IN from OUTSIDE the final oval and CONTRACT onto it, synchronized: a member's
## position is `CENTRE + k·(final − CENTRE)` with the radius factor `k` easing from `ENTRY_K_START`
## (off-screen: top member from y≈0, bottom from y≈235, sides off the L/R edges — measured k≈1.8–1.9)
## down to 1.0 (settled). Pure position — no fade, no scale. Decelerating (ease-out) into place.
const ENTRY_K_START := 1.85
## Entry glide length in menu-ticks (≈30 Hz). Oracle ring entry ran ~f30→f50 (≈20 vsync ≈ 10 ticks).
const ENTRY_DURATION := 10

## The radius factor `k` at entry frame `n` (0..ENTRY_DURATION): ENTRY_K_START → 1.0, ease-out (1−(1−t)²)
## so members decelerate as they settle onto the oval. Clamps to 1.0 once settled.
static func entry_k(frame: int) -> float:
	if frame >= ENTRY_DURATION:
		return 1.0
	if frame <= 0:
		return ENTRY_K_START
	var t := float(frame) / float(ENTRY_DURATION)
	var ease := 1.0 - (1.0 - t) * (1.0 - t)   # ease-out (decelerate)
	return lerp(ENTRY_K_START, 1.0, ease)


## A ring member's on-screen position during the entry contraction: the settled oval position scaled
## out from CENTRE by `k` (k=1 ⇒ settled). Combines with rotation via `final` = ring_position(...).
static func entry_position(final_pos: Vector2, k: float) -> Vector2:
	return CENTRE + (final_pos - CENTRE) * k


## --- EXIT animation (§15.24, user 2026-08-08 + oracle × back-out capture) --------------------------
## Leaving the Change-Job screen (× / keyboard "x"), the ring SPINS while it ENLARGES off-screen until
## every member is gone — the reverse of the entry contraction, but OVERSHOOTING past the oval instead
## of settling onto it. Same `k` scale-from-CENTRE mechanism (entry_position), driven UP from 1.0 →
## EXIT_K_END with an ease-IN (accelerate outward) so the members fling off. The caller advances the
## rotation front continuously alongside k so the ring turns as it grows (oracle: it spins AND enlarges
## in one combined motion — `tmp/cx_*.png`, ring gone by ~frame 8-10).
## EXIT_K_END is big enough that EVERY member clears the 256×240 virtual screen: the front-bottom member
## centre travels (128,186)→(128, 126+60·k); at k=3.4 that is y≈330 (off-bottom), the top member reaches
## y≈-78 (off-top) and the side members x≈128±340 (off both edges).
const EXIT_K_END := 3.4
## Exit glide length in menu-ticks (≈30 Hz). Oracle × back-out ran the ring off in ~8-10 vsync (≈4-5 ticks
## at the sample cadence); a touch longer here for a readable fling before the roster slides back in.
const EXIT_DURATION := 10

## The radius factor `k` at exit frame `n` (0..EXIT_DURATION): 1.0 → EXIT_K_END, ease-IN (frac = t²) so
## the ring accelerates outward as it flies off. Holds at EXIT_K_END once the members are all off-screen.
static func exit_k(frame: int) -> float:
	if frame <= 0:
		return 1.0
	if frame >= EXIT_DURATION:
		return EXIT_K_END
	var t := float(frame) / float(EXIT_DURATION)
	var frac := t * t   # ease-in: accelerate outward
	return lerp(1.0, EXIT_K_END, frac)


## The index of `job_id` within `ids` (the wheel's ring membership) — the member that starts at the
## FRONT (the unit's CURRENT job sits front-bottom on entry, §15.24). −1 if absent (→ caller uses 0).
static func index_of_job(ids: Array, job_id: String) -> int:
	return ids.find(job_id)
