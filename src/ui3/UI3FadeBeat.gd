class_name UI3FadeBeat
extends UI3Beat

## The FADE beat (ADR-0269 dec. 3): the WHOLE ELEMENT ramps its `fade` uniform from invisible
## to drawn, and the close is that ramp reversed. The third transition beat, beside the
## aperture (UI3BoxOpenBeat) and the move (UI3MoveSlideBeat).
##
## It exists because the aperture beat cannot say what a turn-queue card needs to say. BOX_OPEN
## is a SCISSOR: it reveals a rect center-out and is meaningful only on a clip = OWN_APERTURE
## element (its own `precondition` says so). A card inside a strip does not own an aperture — it
## rides its bar's — and "a card arrives" is not a rectangle growing, it is a portrait resolving
## out of the frame's fill. Driving that through the aperture would have every card open its own
## private scissor inside the one it is already clipped by.
##
## === Where the curve comes from ==============================================================
##
## The ROM's one observed fade is the PRAYER TEXT DISMISS (living doc Part A / §C.1, transcribed
## in DialogueOverlay): the composed-text primitive's Gouraud RGB is ramped `0x80 -> 0x38` in
## steps of `-8`, one step per 60 Hz fiber yield, and the window handle is then freed. Code
## constants, not a parsed table — fiber loop `0x80131628`, writers `0x8013164c/74/9c`, floor
## test `s1 >= 0x31`. This beat walks that step, at that clock, over that 0x80 domain.
##
## **The recorded divergence is the FLOOR.** The ROM stops at 0x38 (~0.44) and disappears the
## text by freeing its handle — it never draws a fully-faded frame, because it does not have to.
## A UI3 close has no handle to free: ADR-0084 invariant 1 makes leave = the beat reversed, so a
## reverse that stopped at 0.44 would leave the card sitting there at half brightness forever.
## So the same `-8` step runs the full `0x80 -> 0x00`, which is the ROM's ramp continued rather
## than a curve of our own. 16 steps, settling at frame 15.
##
## === Brightness, not alpha, is the ROM's model — and this is alpha ============================
##
## The prayer ramp multiplies Gouraud RGB, which on the PSX's black background is
## indistinguishable from a fade to nothing. Our cards sit on a lit tan window frame, where a
## brightness ramp would fade a portrait to BLACK against the fill instead of away. `fade`
## therefore multiplies ALPHA. Named as the divergence it is; the STEP and the CLOCK are the
## parts that carry the ROM's cadence, and those are unchanged.


## This beat's curve vocabulary (ADR-0097 §1) — its own, sharing only the DEFAULT convention
## with the other two beats'. The units are ramp values over 0x80; the aperture beat's
## percent-of-a-derived-rect names would be nonsense here.
##
## There is deliberately NO FAST, for exactly UI3MoveSlideBeat's reason: the ROM has ONE fade
## ramp and no stride flag over it (`DAT_8015326C`, the fast flag, is read only by the two
## box-open scalers — it never reaches the fiber that walks this). A doubled step is a curve
## this beat COULD walk, but naming it FAST would claim a ROM speed that does not exist, which
## is the mislabelling ADR-0097 exists to stop.
enum Cadence { DEFAULT, NORMAL, IMMEDIATE }


## The house rule DEFAULT resolves to (§2). ONE answer, not the per-verb pair UI3BoxOpenBeat
## carries: ADR-0182's "an open and a close want different curves" is a statement about
## CHOOSING between curves, and this beat has one. A per-verb split here would be two names for
## the same ramp. Static var: the ADR-0068 home for the knob.
static var DEFAULT_FADE := Cadence.NORMAL


## The ROM's step per 60 Hz tick, and the domain it steps over — see the class docstring.
const FADE_STEP := 8
const FADE_FULL := 0x80
## Ramp length in frames: 0x80 / 8. Frame 0 is the FIRST step (one `FADE_STEP` in), never zero —
## the same indexing UI3BoxOpenBeat uses, where frame 0 is the 10% seed box and the fully-shut
## state lives at a NEGATIVE frame. That is what makes a reversed close end shut.
const RAMP_FRAMES := FADE_FULL / FADE_STEP


## Resolve an authored cadence through the house rule (§2).
static func resolve(cadence: int) -> int:
	return DEFAULT_FADE if cadence == Cadence.DEFAULT else cadence


## The curve length for a RESOLVED cadence. IMMEDIATE is 0 — arrived at frame 0, which is what
## lets the engine settle it inside play() without a rendered frame (§3).
static func settle_for(cadence: int) -> int:
	return 0 if cadence == Cadence.IMMEDIATE else RAMP_FRAMES - 1


## The ramp value at `frame`, normalised to 0..1. A NEGATIVE frame is FULLY SHUT (0.0) — the
## state a reversed close ends on, the alpha twin of the box beat's zero-size box.
static func fade_at_frame(frame: int, cadence: int = Cadence.NORMAL) -> float:
	if frame < 0:
		return 0.0
	if cadence == Cadence.IMMEDIATE:
		return 1.0
	return clampf(float(FADE_STEP * (frame + 1)) / float(FADE_FULL), 0.0, 1.0)


## 1/60 — ONE VSYNC, the base-class default, and it is the RIGHT clock here rather than an
## unconsidered inheritance: the ROM ramp steps once per fiber yield at 60 Hz, and the `-8`
## step size already encodes the whole ~0.27 s duration. Stepping it every OTHER vsync (the
## §15.1 slide beat's clock) would halve the cadence the ROM constants specify.
func tick() -> float:
	return 1.0 / 60.0


## FADE drives a `fade` uniform on this element's drawn surfaces, so it is visible only where
## something actually declares one (Amendment 3 §5). A payload shader without the uniform
## swallows `set_shader_parameter` silently — that is the exact bug this reports, rather than an
## element that animates nothing and looks merely slow.
func precondition(element: UI3Element) -> String:
	if not element.is_inside_tree():
		return ""   # nothing to discover yet; not a verdict
	var surfaces := _fade_surfaces(element)
	if surfaces.is_empty():
		return "no effect: no material under this element declares a `fade` uniform"
	return ""


## Every ShaderMaterial this element draws itself with — its payload plus its own chrome — that
## actually declares `fade`. Collected fresh per drive: the strip's cards are built and freed as
## the queue changes, so a cached list would be a list of freed materials.
static func _fade_surfaces(element: UI3Element) -> Array:
	var out: Array = []
	var candidates: Array = element.payload_materials()
	var chrome := element.chrome_material()
	if chrome != null:
		candidates.append(chrome)
	for m: ShaderMaterial in candidates:
		if m.shader == null:
			continue
		for u: Dictionary in m.shader.get_shader_uniform_list():
			if String(u.get("name", "")) == "fade":
				out.append(m)
				break
	return out


## The cadence in force for this element's OPEN / CLOSE: the call-site override if one is live
## (§4), else the authored field — resolved through the house rule either way.
func open_cadence(element: UI3Element) -> int:
	return resolve(element.cadence_for(UI3Element.OPEN_CADENCE))


func close_cadence(element: UI3Element) -> int:
	return resolve(element.cadence_for(UI3Element.CLOSE_CADENCE))


## The FORWARD (open) length — the engine also hands this to reverse_frames, which ignores it:
## a close runs on its own cadence. UI3BoxOpenBeat's split, kept even though this beat's one
## curve makes the two lengths equal today, so a future second ramp cannot introduce the bug.
func settle_frame(element: UI3Element) -> int:
	return settle_for(open_cadence(element))


## The CLOSE length. An IMMEDIATE close is **0** — already shut at reverse frame 0, so the
## engine settles it in `play()` with no stepped frame (§3); every other cadence needs the
## extra frame that lands the fully-transparent state past index 0.
func reverse_frames(_settle: int, element: UI3Element) -> int:
	var c := close_cadence(element)
	return 0 if c == Cadence.IMMEDIATE else settle_for(c) + 1


## Range-check both authored cadences against this beat's vocabulary (ADR-0097 §1). Absence is
## NOT reported here — that is validate_spec's explicit-required audit; this one only rejects an
## int that is not a Cadence.
func cadence_errors(element: UI3Element) -> PackedStringArray:
	var errors := PackedStringArray()
	for field in [UI3Element.OPEN_CADENCE, UI3Element.CLOSE_CADENCE]:
		if not element.spec().has(field):
			continue
		var v: Variant = element.spec()[field]
		if typeof(v) != TYPE_INT or not Cadence.values().has(v):
			errors.append("\"%s\" = %s is not a UI3FadeBeat.Cadence" % [field, v])
	return errors


## The Cadence vocabulary, for the F3 enum-hinted knob and materialise write-back.
func cadence_enum() -> Dictionary:
	var out := {}
	for token: String in Cadence:
		out[token] = Cadence[token]
	return out


func cadence_enum_tokens() -> String:
	return "UI3FadeBeat.Cadence"


## Ramp the element's drawn surfaces to `frame`'s value.
func drive(element: UI3Element, frame: int) -> void:
	_write(element, frame, open_cadence(element))


## Walk the ramp backwards on the CLOSE cadence. `n` runs 1..close_settle+1, and
## `n = close_settle + 1` lands the fully-transparent state (the negative-frame branch of
## fade_at_frame). IMMEDIATE is shut at n = 0 — its identity curve has no frames to walk back
## through. The passed-in open `settle` is discarded, exactly as UI3BoxOpenBeat discards it.
func reverse_drive(element: UI3Element, n: int, _settle: int) -> void:
	var c := close_cadence(element)
	_write(element, -1 if c == Cadence.IMMEDIATE else settle_for(c) - n, c)


## The shared ramp write for both directions.
func _write(element: UI3Element, frame: int, cadence: int) -> void:
	var f := fade_at_frame(frame, cadence)
	for m: ShaderMaterial in _fade_surfaces(element):
		m.set_shader_parameter("fade", f)
