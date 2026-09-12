extends RefCounted
## The no-op prune transform (ADR-0085 amendment 2026-08-12 "active corroboration:
## the no-op prune A/B"). Given ONE FEDS track's raw byte stream and the opcode-honesty
## verdicts for that track (FedsOpcodeVerdicts.verdicts), rewrite the byte stream with
## every opcode the verdict system calls a NO-OP pruned:
##
##   • a `Muted` NOTE consumes ticks, so it is substituted by an equal-duration
##     `0x80 Rest` — the clock is preserved, only the sound is removed.
##   • an `Inert` zero-tick opcode (0x82 NOP / 0x9B NOP_Sled) is DELETED.
##   • a `Muted` VOICE-WRITE inside a wholly-Muted track is DELETED — it stages state
##     for notes that never sound.
##
## HARD EXCLUSIONS, regardless of verdict: the instrument opcode (0xAC — it sets the
## running instrument a later audible note inherits, and the `Muted` predicate itself
## depends on it) and structural/flow (STRUCTURAL_OPCODES: Repeat/Coda/EndBar/Rest/
## Fermata/Tempo/… + the note-form Hold/Rest). `Pre-arm` / `Live` / `Live-by-proxy`
## stay. Everything not pruned is re-emitted BYTE-IDENTICAL, so a baseline-vs-pruned
## render Δ isolates exactly the no-ops' contribution.
##
## The whole stream is rebuilt at the BYTE level (never a flattened event list), so a
## pruned note inside a Repeat…Coda loop rests EVERY iteration for free — the loop
## bytes replay the rest each pass. Trailing bytes past the decoder's EndBar stop are
## carried verbatim so the region stays byte-faithful.
##
## Pure value logic — no scene, no SPU. No class_name (ADR-0004); load()ed by path.
## Proof-only: the caller renders the result in a TRANSIENT bank and never saves it
## (ADR-0085 §6 display/QA-only rule).

const SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")
const Verdicts = preload("res://src/effects/studio/FedsOpcodeVerdicts.gd")

# `0x80 Rest` is THE rest (ADR-0085 amendment 2026-08-18c §1). FFT writes it 87,793
# times across music and effects and writes the note-form rest (relative_key 13) ZERO
# times — so the prune, the only thing in this repo that ever produced one, emits the
# corpus's form instead. Two bytes (`80 pp`) express every duration a note can carry
# (the delta table maxes at 192; one param byte holds 0-255) and it carries no dead
# velocity byte for the inspector to show someone. Behaviourally identical after a
# note — advance_track's post-note scan runs `0x80` as a bare `accumulated +=` — so
# this is a choice of notation, and the corpus decides it.
const REST_OPCODE := 0x80


## Rewrite `track_bytes` with the track's no-ops pruned, driven by `verdicts` (the
## FedsOpcodeVerdicts.verdicts() dict for the SAME bytes — its `per_event` map is keyed
## by decode-order event_index, which this re-decode reproduces exactly). Returns the
## modified byte stream (same total ticks, only no-op opcodes changed).
static func prune_track(track_bytes: PackedByteArray, verdicts: Dictionary) -> PackedByteArray:
	var per_event: Dictionary = verdicts.get("per_event", {})
	var events: Array = SMD.decode_track(track_bytes, track_bytes.size())
	var out := PackedByteArray()
	var decoded_len := 0
	for ei in range(events.size()):
		var e = events[ei]
		decoded_len = maxi(decoded_len, e.offset + e.size)
		var v := str(per_event.get(ei, ""))
		if e is SMD.NoteEvent:
			if e.is_note() and v == Verdicts.MUTED:
				# Muted note → an equal-duration `0x80 Rest`. delta_time <= 255 always
				# (table max 192, explicit byte 0-255), so the whole span fits the one
				# param byte. A table-form note (2 bytes) substitutes at the SAME size;
				# an explicit-duration note (3 bytes) shrinks by one — the blob gets
				# smaller, which the byte-level splice + offset fixup already handles.
				out.append(REST_OPCODE)
				out.append(e.delta_time & 0xFF)
			else:
				# An audible note, or a note-form Hold/Rest (structural time) — keep as-is.
				out.append_array(track_bytes.slice(e.offset, e.offset + e.size))
		else:
			var op: int = e.opcode
			if op == 0xAC or op in Verdicts.STRUCTURAL_OPCODES:
				# Hard exclusion: the running instrument + all structural/flow are kept
				# even when the wholly-Muted branch tags them Muted.
				out.append_array(track_bytes.slice(e.offset, e.offset + e.size))
			elif v == Verdicts.INERT or v == Verdicts.MUTED:
				# Inert zero-tick no-op, or a muted voice-write in a wholly-Muted track:
				# delete (consumes no ticks, so the clock is unchanged).
				pass
			else:
				# Pre-arm / Live / Live-by-proxy voice-writes stage or make sound — keep.
				out.append_array(track_bytes.slice(e.offset, e.offset + e.size))
	# Carry any trailing bytes past the decoder's EndBar stop verbatim (alignment
	# padding) so the region stays byte-faithful for the flow-through render.
	if decoded_len < track_bytes.size():
		out.append_array(track_bytes.slice(decoded_len))
	return out
