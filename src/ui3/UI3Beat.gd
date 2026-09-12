class_name UI3Beat
extends RefCounted

## One transition beat (ADR-0088 §4; the ADR-0084 "Beat" generalized): a pure
## function of `frame` driving an element's open/close motion. Registered at class
## level with the TransitionEngine per UI3Element.Transition kind; the engine owns
## the accumulator/clamp/cadence mechanics — a beat only maps frames to state.
##
## Reverse is DERIVED by default (drive(settle − n), running the same curve
## backward past frame 0 to the shut state at n = settle+1) so "every open has a
## close" holds by construction; a beat whose exit is genuinely a different motion
## (the Change-Job fling) overrides reverse_drive — and one that CANNOT reverse
## declares `reversible = false`, which the boot audit reports (invariant 1).

## False only for a beat with no reverse path — the boot-time reversibility audit
## (ADR-0084 invariant 1, extended over all of UI3) reports any element naming one.
var reversible := true


## Whether this beat will actually take effect on `element` in its current criteria
## configuration (ADR-0088 Amendment 3 §5) — "" = yes; a non-empty String is the human
## reason it will NOT, for the UI3 page to show beside a disabled Open/Close verb. A
## beat can require a criterion it does not itself set (BOX_OPEN needs OWN_APERTURE);
## this is that requirement, asked of the DECLARED beat rather than hard-coded on the
## page. Default: no precondition (SLIDE, once built, moves the transform and needs no
## aperture) — override only when the beat genuinely depends on another criterion.
func precondition(_element: UI3Element) -> String:
	return ""


## The first frame at which the forward drive has fully settled.
##
## Takes the ELEMENT, not just its spec, because a beat's length depends on the CADENCE in
## force for this play (ADR-0097 §1) — normally the authored spec field, but a call site may
## override it for one invocation (§4) and that override lives on the element for the play's
## duration. So read cadence through `element.cadence_for(...)` and everything else through
## `element.spec()`; a beat that reads `spec()` directly for a cadence silently ignores
## overrides.
func settle_frame(_element: UI3Element) -> int:
	return 0


## Seconds per beat frame (the per-beat tick cadence the engine accumulates at).
##
## 1/60 = ONE VSYNC, and that is deliberate — do NOT "unify" it with
## FormationTransitionEngine.TICK (2/60, the ~30 Hz menu tick). This exact change has been
## made once and reverted as a bug (FORMATION_SCREEN.md §15.17 round log, "the port's open
## ran 2x too slow"): the ROM indexes `world_menu_open_curve` once per builder-loop
## iteration = once per vsync, and that curve ALREADY BAKES the ~2-vsync holds as repeated
## entries `[10,10,60,60,90,90,95,95,100,...]`. Walking it on the menu tick double-counts
## the holds (~18 vsync to settle against the ROM's ~9).
##
## The two clocks are two ENCODINGS of the same ~30 Hz visual cadence, not a discrepancy:
## a pre-repeated curve stepped every vsync, versus a non-repeated curve (the §15.1 slide
## keyframes `[144,139,67,31,13,4,0]`) stepped every other vsync. A beat whose curve is not
## pre-repeated overrides this. See DetailScene._BOX_OPEN_TICK / _MENU_TICK for the same
## split inside one class, and ADR-0097 for where this is going.
func tick() -> float:
	return 1.0 / 60.0


## Drive the forward motion at `frame` (0 = the entry state; settle_frame = settled;
## a NEGATIVE frame = the fully-shut state a reverse play ends on).
func drive(_element: UI3Element, _frame: int) -> void:
	pass


## Drive the REVERSE motion at reverse-frame `n` in 1..settle+1. Default: the same
## curve backward (forward frame settle − n; n = settle+1 lands the shut state).
func reverse_drive(element: UI3Element, n: int, settle: int) -> void:
	drive(element, settle - n)


## Reverse length in frames (the engine finishes a reverse play after this many). Takes the
## element as well as the forward `settle` because a beat may run its close on a DIFFERENT
## cadence than its open (UI3BoxOpenBeat does — ADR-0182's house rule) — the default keeps
## the symmetric derivation. **0 is legal**: an IMMEDIATE close is already shut at reverse
## frame 0, which is what makes the engine settle it without a rendered frame (ADR-0097 §3).
func reverse_frames(settle: int, _element: UI3Element) -> int:
	return settle + 1


## Range-check this element's authored cadence answers against THIS beat's curve vocabulary
## (ADR-0097 §1) — "" entries for a valid spec, one human string per nonsense answer.
##
## There is deliberately NO global curve enum: the units are not interchangeable (the
## aperture's curve is percent of a derived rect, VitalsSlideAnimator's is absolute pixels),
## so only the beat that owns a vocabulary can range-check its names. `UI3Element.validate_spec`
## is static and beat-blind — it can only check that a cadence is PRESENT and an int; this is
## the other half, run by the boot-time audit beside the reversibility check. A beat that
## forgets to implement it lets nonsense authoring through silently (ADR-0097 Consequences).
##
## Convention every cadence vocabulary follows: member 0 is DEFAULT ("use the house rule"),
## because that is what `UI3Element.cadence_for` returns for an unauthored field.
func cadence_errors(_element: UI3Element) -> PackedStringArray:
	return PackedStringArray()


## This beat's cadence vocabulary as an enum dict (token -> int), and the token prefix
## materialise formats an int back through. Empty = this beat has no cadence vocabulary, and
## its cadence fields (if any) mint as plain ints.
##
## Same reason `cadence_errors` exists: the vocabulary is per-beat, so the element cannot
## name the dropdown options for its own cadence knobs — it asks its declared beat. This is
## what makes a cadence an ENUM-hinted F3 row (a live token dropdown) rather than a bare int,
## and what lets the ADR-0068 materialise codemod write `Cadence.FAST` back to the source
## instead of `2`.
func cadence_enum() -> Dictionary:
	return {}


func cadence_enum_tokens() -> String:
	return ""
