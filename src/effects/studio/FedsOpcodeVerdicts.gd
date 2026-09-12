extends RefCounted
## Opcode-honesty verdicts for the FEDS pair editor (ADR-0085 amendment 2026-08-12
## §2). The honest-editor pattern (cf. the emitter Live/Inactive/Dead relevance
## oracle): a per-opcode VERDICT with a fixed vocabulary answering "why is this
## opcode here?" — so the author reads the pair-panel chips as a map of what is
## heard, what is staged, what is inert, and what only shapes flow.
##
## v1 is a POSITION + OPCODE-KIND classifier — NO value-tracking (a full voice-state
## simulator that would also catch redundant re-sets needs a "which instrument ids
## are genuinely silent" corpus we don't have; slice 3's energy band is the empirical
## check that promotes an inferred verdict to a confirmed one):
##
##   • NOP (0x82 / 0x9B)                       → Inert       (writes nothing)
##   • flow / timing (EndBar, Loop, Repeat,    → Structural
##     Coda, Rest, Fermata, Tempo, …)
##   • a voice-write BEFORE the first note      → Pre-arm     (staged, load-bearing)
##   • a voice-write AT/AFTER the first note    → Live        (its effect is heard)
##   • a Note (byte 0x00–0x7F)                  → Live
##
## Track-level: a track WITHOUT EndBar (0x90) is a **Stub** whose bytes flow
## into the next track (feds_bank.gd::get_track_bytes_from) — its voice-writes
## pre-arm the track it flows into (the RE's "the stub is the preamble", not cruft).
## A track that ends with EndBar is **Sounding**.
##
## Pure value logic — no scene, no SPU; consumes a FedsPairModel track view (the
## decoded stream). No class_name (ADR-0004); load()ed by path. Mirrors
## FedsParamSemantics.gd's static-func shape.

const InstrumentNames = preload("res://src/effects/studio/FedsInstrumentNames.gd")

# The verdict vocabulary (strings so they read straight in tooltips / test failures).
const LIVE := "Live"
const PREARM := "Pre-arm"
const INERT := "Inert"
const STRUCTURAL := "Structural"
# Two-axis static verdicts (ADR-0085 2026-08-12 amendment): a note whose running
# instrument is trusted-empty (and the voice not noise-armed) is MUTED (→ hatch); a
# confirmed global-scope opcode that colours another voice is LIVE_BY_PROXY (never
# hatched, even inside a wholly-Muted track).
const MUTED := "Muted"
const LIVE_BY_PROXY := "Live-by-proxy"

# Track-level labels.
const SOUNDING := "Sounding"
# NOT "silent": a stub SOUNDS — its voice runs on into the neighbour's bytecode
# and plays notes the track never authored (ADR-0085 2026-08-14/18). The panel
# draws that borrowed span as a NoEnd phantom; the word "silent" was the lie
# this branch set out to remove.
const STUB := "Stub → flows into the next track"

# The two true no-ops (FFT: 0x82 NOP, 0x9B NOP_Sled = jr ra / move v0,a0) — they
# write nothing and are never observed. Deliberate padding, not voice state.
const NOP_OPCODES := [0x82, 0x9B]

# The confirmed GLOBAL-scope allowlist (ADR-0085 2026-08-12 §2): the noise clock
# 0xB4 Noise_EnableAndClock and 0xB5 Noise_ClockAdd write the single shared SPU
# noise-frequency register (SPUCNT[8-13]), so they are heard through ANOTHER voice —
# Live-by-proxy, never hatched even inside a wholly-Muted track. Kept small and
# confirmed; unconfirmed opcodes default to per-voice (hatchable). The per-track
# energy band renders each track in isolation and is BLIND to cross-track effects,
# so this allowlist is the sole guard — it cannot be backstopped by the band.
const LIVE_BY_PROXY_OPCODES := [0xB4, 0xB5]

# Flow / timing opcodes: they shape sequence structure or advance the clock but
# never write voice state. Rest/Fermata extend duration; Repeat/Coda/Loop/EndBar/
# RepeatBreak/TimeSignature are flow; Tempo/TempoSlide are timing.
const STRUCTURAL_OPCODES := [0x80, 0x81, 0x90, 0x91, 0x97, 0x98, 0x99, 0x9A, 0xA0, 0xA2]


## Classify one track view (FedsPairModel `_track_view` output). Returns:
##   {per_event: {event_index → verdict}, reasons: {event_index → String},
##    track: SOUNDING | STUB}
## Every note and every command carries a verdict keyed by its decode-order
## event_index (stable across ghost copies), so the panel can tint chips + note
## bars and ride the reason on the existing chip-hover label.
static func verdicts(track_view: Dictionary) -> Dictionary:
	var notes: Array = track_view.get("notes", [])
	var commands: Array = track_view.get("commands", [])
	var stub := bool(track_view.get("stub", false))

	# The first sounding note anchors "before vs at/after" — a voice-write earlier
	# is Pre-arm, later is Live. -1 = the track has no note of its own (a pure stub
	# preamble): every voice-write pre-arms the track it flows into.
	var first_note_ei := -1
	var first_note_tick := 0
	for n in notes:
		var ei := int(n.get("event_index", -1))
		if ei >= 0 and (first_note_ei < 0 or ei < first_note_ei):
			first_note_ei = ei
			first_note_tick = int(n.get("start_tick", 0))

	# First pass over the notes: mark each Muted (trusted-empty instrument on a voice
	# not noise-armed) and detect whether the track is WHOLLY Muted — no note ever
	# resolves to an audible instrument. A gray-zone-clip note counts as audible for
	# the wholly test (it is not provably silent), so a clip keeps the track sounding.
	var muted_notes: Dictionary = {}
	var any_audible := false
	for n in notes:
		var ei := int(n.get("event_index", -1))
		if _note_muted(n):
			muted_notes[ei] = true
		else:
			any_audible = true
	var wholly := not notes.is_empty() and not any_audible

	var per_event: Dictionary = {}
	var reasons: Dictionary = {}
	var faint: Dictionary = {}
	for n in notes:
		var ei := int(n.get("event_index", -1))
		var instr := int(n.get("active_instrument", -1))
		if muted_notes.has(ei):
			per_event[ei] = MUTED
			reasons[ei] = "muted — note on a trusted-empty instrument (#%d %s)" \
					% [instr, InstrumentNames.NAMES.get(instr, "?")]
		elif _note_faint(n):
			# A gray-zone clip is faint but NONZERO — not provably silent, so Live with
			# a soft tell, never a hatch (we never over-claim silence).
			per_event[ei] = LIVE
			faint[ei] = true
			reasons[ei] = "faint — note on a gray-zone clip instrument (#%d %s): nearly inaudible, not proven silent" \
					% [instr, InstrumentNames.NAMES.get(instr, "?")]
		else:
			per_event[ei] = LIVE
			reasons[ei] = "heard — the sounding note %s" % str(n.get("label", ""))
	for c in commands:
		var ei := int(c.get("event_index", -1))
		var op := int(c.get("opcode", -1))
		var kind := str(c.get("kind", ""))
		var label := str(c.get("label", ""))
		if op in LIVE_BY_PROXY_OPCODES:
			# A confirmed global-scope opcode is heard through another voice — so it
			# matters even to a muted voice and is NEVER hatched (§2).
			per_event[ei] = LIVE_BY_PROXY
			reasons[ei] = "live-by-proxy — %s makes no sound here but colours another voice (shared noise clock)" % label
		elif wholly:
			# A wholly-Muted track hatches every event — the voice-writes stage state
			# for notes that never sound, so they are inert here too.
			per_event[ei] = MUTED
			reasons[ei] = "muted — %s in a wholly-silent track (no note ever sounds)" % label
		else:
			var v := _classify(op, kind, ei, first_note_ei)
			per_event[ei] = v
			reasons[ei] = _reason(v, label, first_note_ei, first_note_tick)
	return {
		"per_event": per_event,
		"reasons": reasons,
		"faint": faint,
		"track": STUB if stub else SOUNDING,
		"wholly_muted": wholly,
	}


## Is this note provably silent (Muted)? Its running instrument is a trusted-empty
## sample AND its voice is not noise-armed — noise (0xB4/0xB6) reroutes the voice off
## its empty sample onto the noise generator, so it is audible under an empty id.
static func _note_muted(n: Dictionary) -> bool:
	return InstrumentNames.is_trusted_empty(int(n.get("active_instrument", -1))) \
			and not bool(n.get("noise_armed", false))


## Is this note FAINT? Its running instrument is a gray-zone clip (nearly inaudible
## but nonzero) and its voice is not noise-armed. Not provably silent → Live + a soft
## ≈ tell, never a hatch.
static func _note_faint(n: Dictionary) -> bool:
	return InstrumentNames.is_gray_zone_clip(int(n.get("active_instrument", -1))) \
			and not bool(n.get("noise_armed", false))


## The single-opcode rule (v1, position + kind, no value-tracking).
static func _classify(op: int, kind: String, ei: int, first_note_ei: int) -> String:
	if op in NOP_OPCODES:
		return INERT
	# The note path's tie and note-form rest carry opcode -1, so no opcode list can
	# reach them — `kind == "time"` is the arm that classifies them (ADR-0085
	# 2026-08-18c collapsed 18b's "hold"/"rest" kinds into the one time lane; the
	# clause has to move with them or every Fermata and Rest re-reads as a voice-write).
	if op in STRUCTURAL_OPCODES or kind == "structure" or kind == "tempo" \
			or kind == "time":
		return STRUCTURAL
	# A voice-write: Pre-arm before the first note (or on a note-less stub), else Live.
	if first_note_ei < 0 or ei < first_note_ei:
		return PREARM
	return LIVE


static func _reason(v: String, label: String, first_note_ei: int,
		first_note_tick: int) -> String:
	match v:
		INERT:
			return "no-op — writes nothing (deliberate padding)"
		STRUCTURAL:
			return "flow / timing — %s shapes the sequence, not the voice" % label
		PREARM:
			if first_note_ei < 0:
				return "%s pre-arms the voice for the track it flows into" % label
			return "%s pre-arms the voice for the note at tick %d" % [label, first_note_tick]
		LIVE:
			return "heard — %s shapes the sounding note" % label
	return ""
