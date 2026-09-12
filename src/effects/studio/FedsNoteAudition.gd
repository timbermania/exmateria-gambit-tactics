extends RefCounted
## PURE parameter builder for the note-chip AUDITION CONSOLE (ADR-0085 amendment
## 2026-08-13 "the note chip is an audition console"). Given a decoded note event
## and a chosen (possibly dropdown-overridden) instrument id, it produces the SPU-
## side HOLD params (real pitch + real duration) and TAIL params (loop point), plus
## the gating verdicts — Sustains? silent? defaulted loop point? — that disable the
## buttons and word the tells.
##
## This is the seam the /tdd guards drive. It is ROM-FREE-TESTABLE: it reads only
## the raw ADPCM loop facts (a dict, from the committed FedsInstrumentMeta table)
## plus the "is this a ·Silence slot?" name flag — never a live waveset. The live
## SPU poke (EffectStudioPage) resolves midi_note→raw pitch and byte-offset→SPU
## address at play time with the waveset instrument's fine_tune / sample_offset.
##
## No class_name (ADR-0004); load()ed by path.

const Meta = preload("res://src/effects/studio/FedsInstrumentMeta.gd")
const InstrumentNames = preload("res://src/effects/studio/FedsInstrumentNames.gd")

# Shown when the auditioned instrument (real OR dropdown-overridden) is silent.
const SILENT_REASON := "Silent — nothing to hear (empty slot)"
# Sub-label under the tail button when the loop point is the end−0x1010 fallback.
const TAIL_DEFAULTED_HINT := "uses the game's fallback point"
const TAIL_LABEL := "▶ Tail only"
const TAIL_LABEL_DEFAULTED := "▶ Tail only (defaulted loop point)"


## Build the console params for `note` auditioned as `instrument_id`, resolving the
## instrument's loop facts + silence from the committed tables. The live convenience.
static func build(note: Dictionary, instrument_id: int) -> Dictionary:
	return build_with_meta(note, instrument_id, Meta.of(instrument_id),
			InstrumentNames.is_silence(instrument_id))


## The pure core (guard seam): `meta` is the raw ADPCM loop facts dict, `name_is_silence`
## is whether the id's name is in the ·Silence category. Kept separate so guards inject
## synthetic one-shot / explicit-loop / heuristic-loop / silent instruments without a ROM.
static func build_with_meta(note: Dictionary, instrument_id: int, meta: Dictionary,
		name_is_silence: bool) -> Dictionary:
	# Silent = a ·Silence-named slot OR a null (no-sample) waveset entry. Either way
	# there is nothing to hear, so BOTH buttons go dead with a reason.
	var silent: bool = name_is_silence or bool(meta.get("is_null", false))
	# Sustains iff the humanized loop verdict says so — one source, no drift.
	var sustains: bool = Meta.loop_summary_of(meta).begins_with("Sustains")

	var octave: int = int(note.get("octave", 4))
	var key: int = int(note.get("relative_key", 0))
	var hold: Dictionary = {
		"midi_note": octave * 12 + key,
		"duration_ticks": int(note.get("duration_ticks", 0)),
		"duration_seconds": float(note.get("duration_seconds", 0.0)),
		"velocity": int(note.get("velocity", 0)),
	}

	var tail_available: bool = sustains and not silent
	var loop: Dictionary = _tail_loop(meta)
	var tail: Dictionary = {
		"available": tail_available,
		"loop_offset_bytes": int(loop.get("offset", -1)),
		"defaulted_loop": bool(loop.get("defaulted", false)),
	}
	var defaulted: bool = tail_available and bool(tail.get("defaulted_loop", false))

	return {
		"instrument_id": instrument_id,
		"silent": silent,
		"sustains": sustains,
		"hold": hold,
		"tail": tail,
		"hold_enabled": not silent,
		"tail_enabled": tail_available,
		"disabled_reason": SILENT_REASON if silent else "",
		"tail_label": TAIL_LABEL_DEFAULTED if defaulted else TAIL_LABEL,
		"tail_hint": TAIL_DEFAULTED_HINT if defaulted else "",
	}


## The tail's loop start — where "▶ Tail only" begins playback to isolate the ring.
## Explicit LOOP_START → its exact byte offset (marked, honest). Otherwise, for a
## looping sample, FFT's fallback point end−0x1010 (clamped ≥0), flagged `defaulted`
## (re-conclusions-static-rooted-dynamic-validated). {offset:-1} when there is no tail.
static func _tail_loop(meta: Dictionary) -> Dictionary:
	if meta.is_empty() or bool(meta.get("is_null", false)):
		return {"offset": -1, "defaulted": false}
	if bool(meta.get("has_explicit_loop_start", false)):
		var lo: int = int(meta.get("loop_offset_bytes", -1))
		if lo >= 0:
			return {"offset": lo, "defaulted": false}
	if bool(meta.get("has_loop_repeat", false)):
		var size: int = int(meta.get("sample_size", 0))
		return {"offset": maxi(0, size - Meta.HEURISTIC_LOOP_SPAN), "defaulted": true}
	return {"offset": -1, "defaulted": false}
