class_name UI3BoxOpenBeat
extends UI3Beat

## The BOX_OPEN beat (§15.17): the FFT center-out scissor. Drives the element's
## aperture through BoxOpenAnimator.rect_at_frame against the LIVE rect — the three
## copy-pasted per-class accumulators (DetailScene / StartActionMenu /
## EquipPickerMenu) collapse into the engine's one clamped stepper playing this.
## Close is the same curve reversed, ending on the shut box — but NOT at the same speed:
## see the cadence rule below.
##
## Beat params: "open_cadence" / "close_cadence" (ADR-0097 §1/§2) — one Cadence per VERB,
## because an element's open and its close do not want the same curve, and that is the whole
## content of ADR-0182. They replace the single "fast" bool, which was attached to the
## ELEMENT rather than to the verb and named a table stride as if it were a speed.
##
## Vault: [[Menu Window Box Open]]


## This beat's curve vocabulary (ADR-0097 §1). A cadence NAMES A CURVE over the §15.17
## easing table — it is not a speed, and it is deliberately NOT a global enum: these names
## mean percent-of-a-derived-rect and would be nonsense on a slide beat.
##
##   DEFAULT   — "use the house rule" (§2). An AUTHORED answer, not silence: it makes
##               "I considered this and chose the default" and "I never thought about this"
##               different states in the source.
##   NORMAL    — one curve index per frame: 10,10,60,60,90,90,95,95,100 (settles at 8).
##   FAST      — the ROM's own doubled index stride (`if (DAT_8015326c == 2) param_3 <<= 1`):
##               10,60,90,95,100 (settles at 4).
##   IMMEDIATE — the identity curve, [100]: already finished at frame 0 (§3). The integer
##               math is exact (w·100/100 = w; x + w/2 − w·100/200 = x), so it lands the
##               settled rect itself, never a rounded one.
enum Cadence { DEFAULT, NORMAL, FAST, IMMEDIATE }


## The house rule DEFAULT resolves to: an OPEN walks the normal curve, a CLOSE the fast one.
## Static vars, so they are the ADR-0068 home for the two knobs and a scrub re-cadences every
## un-overridden element at once — which is the point of having a house rule at all
## (ADR-0097: a global rule makes "closes are fast" a property of the system, where
## explicit-everywhere makes it a convention that holds while everyone remembers).
##
## This is a DELIBERATE DIVERGENCE FROM THE ROM, decided by the user 2026-08-19. The ROM
## animates opens only: `DAT_8015326C` (the fast flag) is read by exactly two functions,
## `world_menu_window_open_scale` @0x800ec9a0 and `world_menu_element_open_scale`
## @0x800ec7d0 — the only two readers of `world_menu_open_curve`, both OPENS. The one
## close anyone has observed is instant: the Learn press is two vsyncs (LEARN_PICKER.md
## §4), beat 1 tears the 0xf panel down and beat 2 already shows the picker opening, so
## that teardown cannot be animated at all; and the picker's own cancel decompiles to a
## mode set + substate flip with no stage counter and no curve read (§10). The port
## animates closes because ADR-0084 invariant 1 makes leave = the beat reversed. Given
## that the close is already a port invention, its SPEED is a port choice too — and a
## fast close reads better than a symmetric one.
static var DEFAULT_OPEN := Cadence.NORMAL
static var DEFAULT_CLOSE := Cadence.FAST


## Resolve an authored cadence for one verb through the house rule (§2). Static so the
## classes that hand-preview an aperture outside the engine (JobPickerMenu's band ramp,
## the three `aperture_at_frame` helpers) resolve it the one same way.
static func resolve(cadence: int, opening: bool) -> int:
	if cadence == Cadence.DEFAULT:
		return DEFAULT_OPEN if opening else DEFAULT_CLOSE
	return cadence


## The curve length for a RESOLVED cadence — the first frame at which the box has fully
## settled. IMMEDIATE is 0: the identity curve is done at frame 0, and that is exactly what
## lets the engine settle an IMMEDIATE play synchronously instead of one rendered frame late.
static func settle_for(cadence: int) -> int:
	match cadence:
		Cadence.IMMEDIATE:
			return 0
		Cadence.FAST:
			return BoxOpenAnimator.settle_frame(true)
		_:
			return BoxOpenAnimator.settle_frame(false)


## The aperture rect a RESOLVED cadence's curve shows at `frame` over `full`. A NEGATIVE
## frame is the fully-shut zero-size box at the centre — the state a reversed close ends on.
static func rect_for(full: Rect2i, frame: int, cadence: int) -> Rect2i:
	if frame < 0:
		return Rect2i(full.get_center(), Vector2i.ZERO)
	if cadence == Cadence.IMMEDIATE:
		return BoxOpenAnimator.scaled_rect(full, 100)
	return BoxOpenAnimator.rect_at_frame(full, frame, cadence == Cadence.FAST)


## BOX_OPEN drives the element's OWN aperture (the §15.17 center-out scissor), so it is
## visible only on a clip = OWN_APERTURE element — that is THIS beat's requirement, not a
## universal rule (Amendment 3 §5). On any other clip mode the open/close is inert; the
## page shows this reason beside a disabled verb instead of a button that does nothing.
func precondition(element: UI3Element) -> String:
	if element.clip_mode() != UI3Element.Clip.OWN_APERTURE:
		return "no effect: BOX_OPEN drives this element's own aperture, but clip is not OWN_APERTURE"
	return ""


## Range-check both authored cadences against this beat's vocabulary (ADR-0097 §1). Absence
## is NOT reported here — that is validate_spec's explicit-required audit; this one only
## rejects an int that is not a Cadence.
func cadence_errors(element: UI3Element) -> PackedStringArray:
	var errors := PackedStringArray()
	for field in ["open_cadence", "close_cadence"]:
		if not element.spec().has(field):
			continue
		var v: Variant = element.spec()[field]
		if typeof(v) != TYPE_INT or not Cadence.values().has(v):
			errors.append("\"%s\" = %s is not a UI3BoxOpenBeat.Cadence" % [field, v])
	return errors


## The Cadence vocabulary, for the F3 enum-hinted cadence knobs and materialise write-back.
func cadence_enum() -> Dictionary:
	var out := {}
	for token: String in Cadence:
		out[token] = Cadence[token]
	return out


func cadence_enum_tokens() -> String:
	return "UI3BoxOpenBeat.Cadence"


## The cadence in force for this element's OPEN / CLOSE: the call-site override if one is
## live (§4), else the authored field — resolved through the house rule either way.
func open_cadence(element: UI3Element) -> int:
	return resolve(element.cadence_for("open_cadence"), true)


func close_cadence(element: UI3Element) -> int:
	return resolve(element.cadence_for("close_cadence"), false)


## The FORWARD (open) length — the engine also hands this to reverse_frames, which
## ignores it: a close runs on its own cadence.
func settle_frame(element: UI3Element) -> int:
	return settle_for(open_cadence(element))


## The CLOSE length. Not `settle + 1` off the open: the close walks its own curve, so it is
## derived from the close cadence and the passed-in open settle is discarded. An IMMEDIATE
## close is **0** — shut at reverse frame 0, so the engine settles it in `play()` with no
## stepped frame at all (§3); every other cadence needs the extra frame that lands the box
## fully shut past index 0.
func reverse_frames(_settle: int, element: UI3Element) -> int:
	var c := close_cadence(element)
	return 0 if c == Cadence.IMMEDIATE else settle_for(c) + 1


func drive(element: UI3Element, frame: int) -> void:
	_write(element, frame, open_cadence(element))


## Walk the close curve backwards on the CLOSE cadence. `n` runs 1..close_settle+1, and
## `n = close_settle + 1` lands the fully-shut box (the negative-frame branch of rect_for).
## IMMEDIATE is shut at n = 0 — its identity curve has no frames to walk back through.
func reverse_drive(element: UI3Element, n: int, _settle: int) -> void:
	var c := close_cadence(element)
	_write(element, -1 if c == Cadence.IMMEDIATE else settle_for(c) - n, c)


## The shared aperture write for both directions. The box = the element's padded_rect
## (ADR-0088 amendment §4): the live rect grown by aperture_pad — the pad widens the whole
## walk, never the per-frame reveal, so frame<0 (the reversed close's end) stays fully shut.
func _write(element: UI3Element, frame: int, cadence: int) -> void:
	element._set_aperture(rect_for(element.padded_rect(), frame, cadence))
