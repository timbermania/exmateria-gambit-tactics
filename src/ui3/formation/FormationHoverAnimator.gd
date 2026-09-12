class_name FormationHoverAnimator
extends RefCounted
## The map host's HOVER cadence (ADR-0137) — the band fading in and the vitals+nameplate pair
## translating in from opposite screen edges when the tile cursor lands on a unit.
##
## ## This cadence is AUTHORED, and that is why it lives here
##
## Every other cadence on this screen is PARSED: [VitalsSlideAnimator]'s `SLIDE_CURVE` is a literal
## ROM keyframe table read out of WORLD.BIN, [SpriteSlideAnimator]'s positions are measured off the
## oracle. This one has **no oracle** — the ROM's Formation screen has no map to hover over, so
## there is nothing to measure and the numbers below are invented.
##
## Root ADR-0001's authored/parsed line therefore decides where they live, and this codebase already
## encodes that line in the declaration keyword: parsed values are `const`, authored ones are
## `static var` bound to a Tune slug (ADR-0068) in their production owner, F3-scrubbed and
## materialised. So these are `static var`s — never a `const` beside `SLIDE_CURVE`, which would file
## invented data in the drawer reserved for measurements.
##
## ## Two curves, not one (ADR-0097)
##
## The band fade and the pair slide take SEPARATE named curves because their units are not
## interchangeable — a 0→1 subtract scalar and an absolute-pixel translation — which is precisely
## the reason ADR-0097 refuses a global curve enum. They also differ in shape, for a reason:
##
## - the PAIR overshoots ("opens a little too much, then settles");
## - the BAND does not, and must not. Its fraction scales `full_sub`, the oracle's 120/255 subtract.
##   Overshooting that is not a flourish, it is subtracting more than the ROM's black — a visibly
##   wrong band, not an energetic one.
##
## ## Not an ADR-0084 beat
##
## Hover is steady-state INTERACTION, which ADR-0084 deliberately keeps out of the recipe engine
## (the same clause that leaves the Change-Job ring ROTATION self-clocked). It has no screen to
## push, no stack entry, and its reverse is genuinely its forward run backward — so it is a
## self-clocked animator, driven by the host's `_process`, and the boot reversibility audit has
## nothing to say about it.

const TunePort = ExMateriaPlatform.TunePort

## Menu-tick cadence (≈30 Hz), the same clock the §15 animators and the ADR-0084 Player run on.
const TICK := 2.0 / 60.0

# --- formation.hover.* (ADR-0068 authored homes) -----------------------------
## How long the pair takes to translate in, in menu ticks.
const PAIR_TICKS_SLUG := "formation.hover.pair_ticks"
static var PAIR_TICKS_DEFAULT := 9
const PAIR_TICKS_HINT := {"min": 1, "max": 40, "step": 1}

## Overshoot STRENGTH of the pair's entrance — the `s` of the standard back-out ease
## `1 + (s+1)(t-1)³ + s(t-1)²`. 0 = a plain cubic ease-out with no overshoot; ~1.7 is the classic
## ~10%-past-the-mark. Scrub this, not a peak percentage: the peak is a consequence of `s`, and
## exposing the consequence as the knob makes the two disagree the moment the ease changes.
##
## The default is BOUNDED by a MEASURED constraint, not chosen for feel alone, and the ceiling is
## lower than it looks. The two pieces overshoot TOWARD each other, and the settled layout leaves
## almost nothing between them: pixel-scanned off a rendered settled frame, the vitals panel's
## rightmost ink (the "Lv./Exp." row) ends at display x=131 and the nameplate's frame begins at
## x=135 — **4 px of slack, total**. So the whole budget is ~2 px per side.
##
## At the classic ~1.7 each piece overshoots ~7.7 px and the nameplate visibly eats the last glyph
## of "Exp.00" for four ticks, which reads as a rendering bug rather than as energy. 0.7 peaks at
## ~2.2 px each — a real flourish (8 screen px past the mark at 4× scale) that still clears.
##
## A LARGER overshoot is not a bigger number here, it is new panel geometry — which ADR-0137's spec
## forbids and which would have to arrive as a deliberate, recorded divergence. That is the whole
## reason this is an F3-scrubbable `static var` and not a decision baked into a curve.
const PAIR_OVERSHOOT_SLUG := "formation.hover.pair_overshoot"
static var PAIR_OVERSHOOT_DEFAULT := 0.7
const PAIR_OVERSHOOT_HINT := {"min": 0.0, "max": 4.0, "step": 0.05}

## How long the band takes to fade in, in menu ticks. Shorter than the pair by default: the band is
## the ground the pair arrives ON, so it wants to be there first.
const BAND_TICKS_SLUG := "formation.hover.band_ticks"
static var BAND_TICKS_DEFAULT := 6
const BAND_TICKS_HINT := {"min": 1, "max": 40, "step": 1}


static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


static func register_tunables() -> void:
	TunePort.bind(PAIR_TICKS_SLUG, PAIR_TICKS_DEFAULT, PAIR_TICKS_HINT)
	TunePort.bind(PAIR_OVERSHOOT_SLUG, PAIR_OVERSHOOT_DEFAULT, PAIR_OVERSHOOT_HINT)
	TunePort.bind(BAND_TICKS_SLUG, BAND_TICKS_DEFAULT, BAND_TICKS_HINT)


## The PAIR curve. Completion fraction at menu tick `frame`, from 0 (parked off-screen at
## [constant UnitInfoCluster.LAYOUT_OFF]) to 1 (docked) — and deliberately PAST 1 in between, which
## is the overshoot. Clamps at both ends so a held hover rests docked forever.
static func pair_fraction_at(frame: int) -> float:
	var total := maxi(1, PAIR_TICKS_DEFAULT)
	if frame <= 0:
		return 0.0
	if frame >= total:
		return 1.0
	var t := float(frame) / float(total)
	var s := PAIR_OVERSHOOT_DEFAULT
	var u := t - 1.0
	return 1.0 + (s + 1.0) * u * u * u + s * u * u


## The BAND curve. Subtract-strength factor at menu tick `frame`, 0 (invisible) → 1 (the oracle
## 120/255). Monotone cosine ease — see the class docstring for why this one must not overshoot.
static func band_fraction_at(frame: int) -> float:
	var total := maxi(1, BAND_TICKS_DEFAULT)
	if frame <= 0:
		return 0.0
	if frame >= total:
		return 1.0
	return 0.5 - 0.5 * cos(PI * float(frame) / float(total))


## The first tick by which BOTH curves have settled — the hover's own "is it done" answer, and the
## length the reverse run counts down from.
static func settle_frame() -> int:
	return maxi(maxi(1, PAIR_TICKS_DEFAULT), maxi(1, BAND_TICKS_DEFAULT))
