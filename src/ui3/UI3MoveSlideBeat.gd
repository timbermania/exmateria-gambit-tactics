class_name UI3MoveSlideBeat
extends UI3Beat

## The Move.SLIDE beat (ADR-0097 §5): the WHERE verb, animated. `place_at()` re-homes an
## element onto another key location; with this beat declared, the element's rect WALKS there
## from wherever it stood instead of snapping — and mounted content rides, because the
## authored home stays frozen and only the origin moves (the ADR-0088 movable-origin model).
##
## The curve is VitalsSlideAnimator's §15.1 keyframe table read as a FRACTION OF THE JOURNEY
## rather than as pixels. The ROM table `{144,139,67,31,13,4,0}` is a source-Y offset above the
## settled top and 144 is the whole distance, so `1 − offset/144` is that same easing
## normalised. Reused, not invented: it is the curve the one hand-rolled move in the codebase
## already walks — UnitInfoCluster.set_slide_frame computes exactly this fraction to lerp
## between two layouts — so collapsing that onto this beat is an exact substitution rather
## than a lookalike.
##
## NO REVERSE, by construction (§5): the reverse of place_at("centre") is place_at("docked").
## A move is self-inverse by ARGUMENT, not by polarity, which is why it is a second beat slot
## and not a third direction on the transition beat — `reversed: bool` stays a bool and
## reverse_drive keeps meaning something over its whole domain. reverse_drive/reverse_frames
## are never reached for a move play.

const TunePort = ExMateriaPlatform.TunePort


## This beat's curve vocabulary (ADR-0097 §1) — its OWN, sharing only the DEFAULT convention
## with UI3BoxOpenBeat's. The units are positions between two rects; the aperture beat's
## percent-of-a-derived-rect names would be nonsense here, which is the ADR's whole argument
## against one flat curve enum.
##
## There is deliberately no FAST: the ROM has one slide table and no stride flag over it (that
## flag, `DAT_8015326C`, is read only by the two box-open scalers). Naming a cadence the curve
## cannot actually walk is the mislabelling ADR-0097 exists to stop.
##
## BACK is a **recorded divergence from the ROM**, not a fourth reading of the §15.1 table
## (ADR-0269 dec. 5). It is the SECOND divergence of its exact class: FormationHoverAnimator's
## `pair_fraction_at` already walks this same back-out ease for the hover pair, deliberately and
## on the record. The distinction ADR-0097 §1 actually draws is between a cadence that names a
## curve this beat can walk and one that does not — BACK names a curve, and says in its own name
## that it is not the ROM's.
enum Cadence { DEFAULT, NORMAL, IMMEDIATE, BACK }


## === BACK's two knobs =========================================================================
##
## They are the beat's OWN and are NOT inherited from the hover's, which is the whole reason
## they exist rather than a `FormationHoverAnimator.PAIR_OVERSHOOT_DEFAULT` read.
##
## The hover's `s = 0.7` is bounded by a MEASURED 4px slack on a long journey. Back-out at
## `s` peaks `4s³/27(s+1)²` past the mark, so `s = 0.7` is +1.76% — and on a turn-queue card
## shuffling ONE slot (a ~25.6 display-px pitch) that is **0.45 px**. Sub-pixel: the cadence
## would be indistinguishable from NORMAL at the one place it was added for.
##
## The default below is priced against the queue's 4 px inter-card gap instead: `s = 1.9` peaks
## +12.1%, ~3.1 px on that same pitch — visible against the bar's frame, and still inside the
## gap, so a springing rank never reads as two cards touching. A longer journey (a card entering
## from off the strip's right edge) scales the same 12% into something much larger, which is
## exactly where the pull-back is meant to read.
const BACK_OVERSHOOT_SLUG := "ui3.move.back_overshoot"
static var BACK_OVERSHOOT_DEFAULT := 1.5
const BACK_OVERSHOOT_HINT := {"min": 0.0, "max": 6.0, "step": 0.05}

## BACK's length in beat frames. The §15.1 table's own 6 would put the ease's peak at frame 3.4
## and leave only two frames of pull-back (~66 ms at this beat's ~30 Hz visual cadence) — the
## motion would happen but barely register. 8 keeps the same clock and gives the return three.
const BACK_FRAMES_SLUG := "ui3.move.back_frames"
static var BACK_FRAMES_DEFAULT := 8
const BACK_FRAMES_HINT := {"min": 2, "max": 30, "step": 1}

# Bound on first read rather than in `_static_init`: this class is a beat, constructed by
# UI3Registry._ready, and a static-init bind would have to assume the Tune autoload is already
# up. Lazy + idempotent needs no ordering assumption at all (the GambitSurfaceMenu idiom).
static var _back_bound := false


static func _bind_back_tunables() -> void:
	if _back_bound:
		return
	_back_bound = true
	TunePort.bind(BACK_OVERSHOOT_SLUG, BACK_OVERSHOOT_DEFAULT, BACK_OVERSHOOT_HINT)
	TunePort.bind(BACK_FRAMES_SLUG, BACK_FRAMES_DEFAULT, BACK_FRAMES_HINT)


## The live back-out overshoot `s` (ADR-0068 R5 pull-read, so an F3 scrub lands next frame).
static func back_overshoot() -> float:
	_bind_back_tunables()
	return float(TunePort.get_value(BACK_OVERSHOOT_SLUG, BACK_OVERSHOOT_DEFAULT))


## The live BACK curve length in beat frames.
static func back_frames() -> int:
	_bind_back_tunables()
	return maxi(1, int(TunePort.get_value(BACK_FRAMES_SLUG, BACK_FRAMES_DEFAULT)))


## The house rule DEFAULT resolves to for a move. One direction, so one answer — unlike the
## aperture, whose rule is per-direction (ADR-0182). Static var: the ADR-0068 home for the knob.
static var DEFAULT_MOVE := Cadence.NORMAL


## Resolve an authored move cadence through the house rule (§2).
static func resolve(cadence: int) -> int:
	return DEFAULT_MOVE if cadence == Cadence.DEFAULT else cadence


## The curve length for a RESOLVED cadence. IMMEDIATE is 0 — arrived at frame 0, which is what
## lets the engine settle it inside play_move() (§3). Note the identity here is `settle`, the
## destination itself: there is no universal immediate constant, which is §1's point.
static func settle_for(cadence: int) -> int:
	match cadence:
		Cadence.IMMEDIATE:
			return 0
		Cadence.BACK:
			return back_frames()
		_:
			return VitalsSlideAnimator.settle_frame()


## The fraction of the journey travelled at frame `n`: `1 − offset/144` over the §15.1 table.
## Expressed as a fraction and lerped (rather than adding the raw offset) so BOTH endpoints
## land pixel-exact on their layouts — the reason UnitInfoCluster does the same.
##
## `cadence` defaults to NORMAL so every pre-BACK caller reads the ROM table unchanged.
static func fraction_at_frame(frame: int, cadence: int = Cadence.NORMAL) -> float:
	if cadence == Cadence.BACK:
		return back_fraction_at_frame(frame)
	var span := float(VitalsSlideAnimator.SLIDE_CURVE[0])
	return 1.0 - float(VitalsSlideAnimator.offset_at_frame(frame)) / span


## BACK's curve: the back-out ease `1 + (s+1)u³ + su²` at `u = t − 1`, the same closed form
## FormationHoverAnimator.pair_fraction_at walks — with THIS beat's own `s` (see the knobs
## above). Clamped at both ends, so frame 0 is the journey's start and the settle frame lands
## exactly 1.0 rather than a rounded approach to it: like the NORMAL branch, both endpoints
## have to be pixel-exact on their layouts, and only the MIDDLE is allowed past 1.
static func back_fraction_at_frame(frame: int) -> float:
	var total := back_frames()
	if frame <= 0:
		return 0.0
	if frame >= total:
		return 1.0
	var t := float(frame) / float(total)
	var s := back_overshoot()
	var u := t - 1.0
	return 1.0 + (s + 1.0) * u * u * u + s * u * u


## Seconds per beat frame. 2/60, NOT the UI3Beat default of 1/60, and that is the split the
## base class documents: the §15.1 keyframes are NOT pre-repeated (unlike the box-open curve's
## `[10,10,60,60,...]`), so they are stepped every OTHER vsync to hold each keyframe ~2 frames.
## Same ~30 Hz visual cadence, the other encoding of it.
func tick() -> float:
	return 2.0 / 60.0


## Range-check the authored move cadence against this beat's vocabulary (ADR-0097 §1).
func cadence_errors(element: UI3Element) -> PackedStringArray:
	var errors := PackedStringArray()
	if not element.spec().has(UI3Element.MOVE_CADENCE):
		return errors   # absence is validate_spec's report, not this audit's
	var v: Variant = element.spec()[UI3Element.MOVE_CADENCE]
	if typeof(v) != TYPE_INT or not Cadence.values().has(v):
		errors.append("\"%s\" = %s is not a UI3MoveSlideBeat.Cadence"
			% [UI3Element.MOVE_CADENCE, v])
	return errors


## The Cadence vocabulary, for the F3 enum-hinted knob and materialise write-back.
func cadence_enum() -> Dictionary:
	var out := {}
	for token: String in Cadence:
		out[token] = Cadence[token]
	return out


func cadence_enum_tokens() -> String:
	return "UI3MoveSlideBeat.Cadence"


## The cadence in force for this element's MOVE: the call-site override if one is live (§4),
## else the authored field — resolved through the house rule either way.
func move_cadence(element: UI3Element) -> int:
	return resolve(element.cadence_for(UI3Element.MOVE_CADENCE))


func settle_frame(element: UI3Element) -> int:
	return settle_for(move_cadence(element))


## Walk the rect from where place_at() found the element to the location it re-homed onto.
## Drives through _apply_rect, the same seam a rect scrub uses, so the origin move, the chrome
## resize and the aperture re-derive all follow for free.
func drive(element: UI3Element, frame: int) -> void:
	var cadence := move_cadence(element)
	var to := element.move_to()
	if cadence == Cadence.IMMEDIATE:
		element._apply_rect(to)
		return
	var from := element.move_from()
	var f := fraction_at_frame(frame, cadence)
	element._apply_rect(Rect2(from.position.lerp(to.position, f), from.size.lerp(to.size, f)))
