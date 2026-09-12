extends RefCounted
## The ADR-0085 TIER-3 pair view model — projects one FEDS pair (2 opcode tracks)
## into the track-lane strip's presentation data: notes as duration bars, opcodes
## as chips, loops FOLDED (REPEAT bracket + ×N badge), on the pair's own tick axis
## with a tick→seconds tell (integrated tempo map, 120 BPM fallback). A near-port
## of the DAW plugin's lane structs (fft_smd_inspector.h FFTSmdLaneNoteBlock /
## LaneCommandBlock) at FEDS scale.
##
## The read model is THE runtime decoder (`SoundOpcodes.decode_track`, the code path
## the sequencer plays) with per-event byte offsets annotated; every event view
## carries its FEDS-blob-ABSOLUTE offset (track_offset + event offset) so the
## slice-2 write path patches bytes in place — feds.json is never an input.
##
## Provenance leads (ADR honesty): which shared containers resolve into this pair
## ("used by container C → N triggers") via SoundContainerModel — the resolver
## stays the single source of the mode/fire truth. A track without EndBar is a
## STUB whose bytes flow into the next track (FFT's RAM byte-walker); the view
## badges it — a tell, never a block.
##
## Pure value logic — no scene, no SPU. No class_name (ADR-0004); load()ed by path.

const SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")
const ContainerModel = preload("res://src/effects/studio/SoundContainerModel.gd")
const DragPlan = preload("res://src/effects/studio/SoundDragPlan.gd")

const _NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const _FALLBACK_BPM := 120.0  # Trackset.initial_tempo = 0 → sequencer fallback


## The composite view of one FEDS pair, or {valid: false, tracks: []} when the
## bank is null / the index is out of range (inert, never a crash).
static func pair_view(feds_bank, pair_idx: int, containers_doc: Dictionary,
		effect_sound) -> Dictionary:
	if feds_bank == null or pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		return {"pair_idx": pair_idx, "valid": false, "tracks": [],
				"used_by_containers": [], "total_ticks": 0}
	var tracks: Array = []
	var total_ticks := 0
	for t in range(2):
		var track_idx := pair_idx * 2 + t
		var tv := _track_view(feds_bank, track_idx)
		# A stub track carries its derived, read-only flow-through span (ADR-0085
		# 2026-08-14) — the borrowed bytecode the lane draws; empty for a sounding track.
		if bool(tv.get("stub", false)):
			tv["flow_through"] = flow_through_span(feds_bank, track_idx)
		total_ticks = maxi(total_ticks, int(tv.get("end_tick", 0)))
		tracks.append(tv)
	return {
		"pair_idx": pair_idx,
		"valid": true,
		"tracks": tracks,
		"total_ticks": total_ticks,
		"used_by_containers": _used_by_containers(containers_doc, effect_sound, pair_idx),
	}


## The containers whose EMITTED ids resolve into this pair (pair_idx = id - 1),
## each with its firing-trigger count — the shared-object blast radius. Driven
## through SoundContainerModel so the resolver remains the one fire-table truth.
static func _used_by_containers(containers_doc: Dictionary, effect_sound,
		pair_idx: int) -> Array:
	var out: Array = []
	var raw: Array = containers_doc.get("containers", [])
	for i in range(raw.size()):
		var hits := false
		for id in ContainerModel.emitted_ids(containers_doc, i):
			if int(id) - 1 == pair_idx:
				hits = true
				break
		if hits:
			out.append({"index": i, "used_by": ContainerModel.used_by(effect_sound, i)})
	return out


## One track lane: notes (duration bars), commands (chips), folded loop brackets,
## the stub tell, and the tick axis with its seconds projection. The bounded
## (authored) decode — verdict/prune consume this, so it never flows through.
static func _track_view(feds_bank, track_idx: int) -> Dictionary:
	# A track the OFFSET TABLE does not carry is refused explicitly, the same way
	# `pair_view` refuses an out-of-range pair — "inert, never a crash". This read used to
	# be unguarded, so a bank whose `track_offsets` is short (or empty) failed the index
	# read; the error aborted this function, which returned the `Dictionary` default `{}`,
	# and the lane assertions above it went green about views that were never decoded.
	# An absent row is exactly the null slot the sentinel below already models — no bytes
	# to sound, nothing to borrow — so it degrades there rather than inventing a case. #468.
	var base_off: int = 0
	if track_idx >= 0 and track_idx < feds_bank.track_offsets.size():
		base_off = feds_bank.track_offsets[track_idx]
	# A NULL SLOT is an unused track, not music (ADR-0085 2026-08-18). The feds
	# magic + header + offset table occupy the blob's first bytes, so offset 0 can
	# never address bytecode — it is the table's "no track here" sentinel. Ten
	# corpus effects carry one, always a pair's track B (E097/E185/E332/E336/E376/
	# E382 pair 1, E343 pair 2, E248/E249 pair 3, E089 pair 5 — that one MID-table,
	# so it is not trailing padding: a pair may simply have one voice).
	# Decoding it walks the HEADER as opcodes (11 phantom notes in the guard's
	# fixture) and, finding no EndBar, misreads it as a stub that flows. It is
	# neither: no bytes to sound, nothing to borrow.
	if base_off == 0:
		return {
			"track_idx": track_idx,
			"offset": 0,
			"size_bytes": 0,
			"null_track": true,
			"stub": false,
			"notes": [],
			"commands": [],
			"spans": [],
			"loops": [],
			"end_tick": 0,
			"end_seconds": 0.0,
			"outro_ticks": 0,
			"has_terminator": false,
		}
	var bytes: PackedByteArray = feds_bank.get_track_bytes(track_idx)
	var events: Array = SMD.decode_track(bytes, bytes.size())
	var proj: Dictionary = _project_events(events, base_off)
	var outro: Dictionary = outro_of(events)
	return {
		"track_idx": track_idx,
		"offset": base_off,
		"size_bytes": bytes.size(),
		"null_track": false,
		"stub": not bool(proj["has_end_bar"]),
		"notes": proj["notes"],
		"commands": proj["commands"],
		"spans": proj["spans"],
		"loops": proj["loops"],
		"end_tick": proj["end_tick"],
		"end_seconds": proj["end_seconds"],
		# The OUTRO (ADR-0085 2026-08-19c): how much of `end_tick` is trailing silence the
		# terminator has nothing after. -1 on a stub, which owns no terminator to write in
		# front of. The lane reads it to name its two rows; the verb recomputes it from the
		# same function, so the picture and the write cannot disagree about the number.
		"outro_ticks": int(outro["ticks"]),
		"has_terminator": int(outro["end_bar_index"]) >= 0,
	}


## The FLOW-THROUGH span of a STUB track (ADR-0085 2026-08-14): the bytecode the
## voice actually executes — decode CONTINUOUSLY from the stub's offset to the first
## DECODED EndBar (never a byte-scan; a 0x90 can be an opcode PARAM), walking past the
## track boundary into the following bytecode (FFT's linear byte-walker). Returns {}
## for a non-stub track (it terminates itself, borrows nothing) or a bad bank/index.
## The authored `_track_view` is untouched — this is ADDITIVE, read-only metadata.
##
## Each note/command is tagged `flowed` = its blob-absolute offset has crossed into a
## LATER track's region (own → borrowed boundary). Running state accumulates across the
## whole stream, so a borrowed note carries the instrument/octave the voice picked up
## walking the neighbour's opcodes AND the stub's own pre-flow pitch-bend. Fields:
##   {flowed_from_track, into_track, own_boundary_offset, end_bar_offset,
##    crosses_pair, own_pitch_bend_total, notes, commands, loops, end_tick, end_seconds}
static func flow_through_span(feds_bank, track_idx: int) -> Dictionary:
	if feds_bank == null or track_idx < 0 or track_idx >= feds_bank.num_tracks:
		return {}
	var base_off: int = feds_bank.track_offsets[track_idx]
	# A null slot (offset 0) has no bytes — it is not a stub and borrows nothing.
	if base_off == 0:
		return {}
	# Stub-ness is decided by the AUTHORED (bounded) decode, not the continuous one
	# (which always ends in an EndBar). A track with its own EndBar borrows nothing.
	var bounded: PackedByteArray = feds_bank.get_track_bytes(track_idx)
	if bool(_project_events(SMD.decode_track(bounded, bounded.size()), base_off)["has_end_bar"]):
		return {}
	# Where the stub's OWN bytes end = the next track's offset (or end-of-data). Events
	# at/after this offset are borrowed from a later track.
	var own_boundary: int = feds_bank.data_size
	if track_idx + 1 < feds_bank.num_tracks:
		own_boundary = feds_bank.track_offsets[track_idx + 1]
	var proj: Dictionary = _project_events(feds_bank.get_track_events_from(track_idx), base_off)
	var own_bend := 0
	for c in proj["commands"]:
		c["flowed"] = int(c["offset"]) >= own_boundary
		# 0xD2 PitchBendRel on the OWN portion is the "+N detune" the source tell reports.
		if not bool(c["flowed"]) and int(c.get("opcode", -1)) == 0xD2 \
				and (c.get("params", []) as Array).size() > 0:
			own_bend += int(c["params"][0])
	for n in proj["notes"]:
		n["flowed"] = int(n["offset"]) >= own_boundary
	# Cross-track identity (ADR-0085 2026-08-18): a borrowed event is EDITED WHERE
	# ITS BYTES LIVE, so stamp each flowed event with its owner track and that
	# track's OWN event_index. Identity is the blob-absolute offset — this walk's
	# ordinal counts from the stub's start and means nothing to the owner. The panel
	# routes a click on a borrowed item to (owner_track, owner_event_index), so the
	# selection highlight lands on the real chip and the inspector edits the byte.
	_stamp_owners(feds_bank, proj["notes"])
	_stamp_owners(feds_bank, proj["commands"])
	# The terminating EndBar (decode_track stops at the first 0x90 opcode, so at most one).
	var end_bar_offset := -1
	for c in proj["commands"]:
		if int(c.get("opcode", -1)) == 0x90:
			end_bar_offset = int(c["offset"])
			break
	# Cross-pair: the flow's EndBar lands in (or past) the NEXT pair's bytes — the
	# safety-rail case (zero in the corpus). next-pair start = data_size for a last pair.
	var next_pair_track: int = (track_idx / 2 + 1) * 2
	var next_pair_off: int = feds_bank.data_size
	if next_pair_track < feds_bank.num_tracks:
		next_pair_off = feds_bank.track_offsets[next_pair_track]
	return {
		"flowed_from_track": track_idx,
		"into_track": track_idx + 1 if track_idx + 1 < feds_bank.num_tracks else -1,
		"own_boundary_offset": own_boundary,
		"end_bar_offset": end_bar_offset,
		"crosses_pair": end_bar_offset >= 0 and end_bar_offset >= next_pair_off,
		"own_pitch_bend_total": own_bend,
		"notes": proj["notes"],
		"commands": proj["commands"],
		# The borrowed stream folds into spans TOO (they are the same `_project_events`
		# call), so a borrowed 160-tick note draws as 160 ticks on the stub's lane and
		# on its owner's alike. Spans are references into `notes`/`commands`, so the
		# `flowed` tag and `_stamp_owners`' ownership stamp are already on them.
		"spans": proj["spans"],
		"loops": proj["loops"],
		"end_tick": proj["end_tick"],
		"end_seconds": proj["end_seconds"],
	}


## Stamp every FLOWED event with the track that owns its bytes and that track's own
## event_index (resolved by blob-absolute offset — never by ordinal). A borrowed
## event the owner's bounded decode does not reach keeps owner_event_index = -1.
static func _stamp_owners(feds_bank, events: Array) -> void:
	var cache := {}
	for e in events:
		if not bool(e.get("flowed", false)):
			continue
		var off := int(e.get("offset", -1))
		var owner := _owner_track_of(feds_bank, off)
		e["owner_track"] = owner
		e["owner_event_index"] = -1
		if owner < 0:
			continue
		if not cache.has(owner):
			var ob: PackedByteArray = feds_bank.get_track_bytes(owner)
			cache[owner] = _project_events(SMD.decode_track(ob, ob.size()),
					feds_bank.track_offsets[owner])
		var op: Dictionary = cache[owner]
		for lst in [op["notes"], op["commands"]]:
			for oe in lst:
				if int(oe.get("offset", -1)) == off:
					e["owner_event_index"] = int(oe.get("event_index", -1))
					break


## The track whose region contains `offset`: the greatest track offset ≤ it. Null
## slots (offset 0) are skipped — they own no bytes.
static func _owner_track_of(feds_bank, offset: int) -> int:
	var best := -1
	var best_off := -1
	for i in range(feds_bank.num_tracks):
		var o: int = feds_bank.track_offsets[i]
		if o == 0 or o > offset or o <= best_off:
			continue
		best = i
		best_off = o
	return best


## PURE: fold a decoded event list into SPANS (ADR-0085 amendment 2026-08-18c §4).
##
## A span is the unit of TIME: a run of ticks that is either one **note** or one
## **rest**. Spans TILE the track — every tick belongs to exactly one, and there is
## no empty space between them, which is why nothing on this lane ripples.
##
## Two kinds of tick (§2): `0x81 Fermata` and `0x80 Rest` each add exactly `param`
## ticks; the difference is whose ticks they are. A Fermata's are SOUNDING when a
## note is playing (it is more of that note, so it JOINS the note's span as a further
## segment) and SILENT otherwise (24 corpus Fermatas sound with nothing playing — the
## runtime's pre-note path treats them as a bare wait, so they are rest spans). The
## fold therefore reads no opcode names: it asks one question per event, *is a note
## sounding?*, which is the question the sequencer answers.
##
## Segments are kept, never summed away. `Note C(16) · Portamento_Init · Fermata 144`
## is ONE 160-tick C whose portamento fires 16 ticks in — the split point IS the
## opcode's timing, and 1600 of 1619 fermata spans carry such an interior opcode. A
## delete substitutes segment-for-segment (`vv dd`→`80 pp`, `81 pp`→`80 pp`) so those
## firing ticks survive; re-spelling the span canonically would move nearly all of them.
##
## Decode order, exactly like `_project_events` — no loop awareness (404 spans have a
## Repeat or Coda between the note and its fermata; the substitution preserves ticks
## per pass either way, so the clock is right in every reading).
##
## Returns [{head_index, kind, segments, start_tick, note_ticks, extension_ticks,
## silent_ticks, total_ticks}] in start order. Shared by the read model and
## `SoundDefChannel.delete_event` so the picture and the verb fold identically.
static func fold_spans(events: Array) -> Array:
	var spans: Array = []
	var tick := 0
	var open_note := -1     # index into `spans` of the sounding note span, -1 = silence
	for ei in range(events.size()):
		var e = events[ei]
		var ticks := 0
		var sounding := false     # does this event add time to the note already playing?
		var opens_note := false
		if e is SMD.NoteEvent:
			ticks = e.delta_time
			opens_note = e.is_note()
			sounding = e.is_tie()   # a tie holds the note; a note-form rest silences it
		elif e.opcode == 0x80:
			ticks = e.params[0] if e.params.size() > 0 else 0
		elif e.opcode == 0x81:
			ticks = e.params[0] if e.params.size() > 0 else 0
			sounding = true
		else:
			continue                # zero-tick: an interior opcode, not a segment
		if sounding and open_note >= 0:
			var sp: Dictionary = spans[open_note]
			(sp["segments"] as Array).append(ei)
			sp["extension_ticks"] = int(sp["extension_ticks"]) + ticks
			sp["total_ticks"] = int(sp["total_ticks"]) + ticks
		else:
			spans.append({
				"head_index": ei,
				"kind": "note" if opens_note else "rest",
				"segments": [ei],
				"start_tick": tick,
				"note_ticks": ticks if opens_note else 0,
				"extension_ticks": 0,
				"silent_ticks": 0 if opens_note else ticks,
				"total_ticks": ticks,
			})
			# A note opens a span later Fermatas extend; anything else is silence, and
			# silence closes the note (a Fermata after a Rest is a rest of its own —
			# zero corpus occurrences, so this is a guard, not a path).
			open_note = spans.size() - 1 if opens_note else -1
		tick += ticks
	return spans


## The OUTRO (ADR-0085 amendment 2026-08-19c): the run of `0x80` rests sitting between a
## track's last authored event and its terminating `0x90 EndBar` — the ONE place in a track
## where time can be added or taken away without re-timing anything. Returns
## {ticks, first_index, end_bar_index}, where `first_index` is the event the rewrite starts
## at (== `end_bar_index` when the outro is empty, which is 1917 of the corpus's 1928
## terminated tracks) and `end_bar_index` is -1 on a STUB.
##
## The run stops at the first non-rest, exactly as the drag's cascade does (19b §3's third
## wall): `note(12) Coda rest(120) EndBar` has a 120-tick outro, but `note(12) rest(8) Coda
## EndBar` has NONE — writing in front of that `Coda` would move when it fires, and 482
## corpus tracks end on precisely that shape.
##
## Shared by the read model (`_track_view` stamps `outro_ticks`) and `SoundDefChannel.
## set_outro`, so the number the lane names and the number the verb writes are one function.
static func outro_of(events: Array) -> Dictionary:
	var end_bar := -1
	for ei in range(events.size()):
		var e = events[ei]
		if not (e is SMD.NoteEvent) and e.opcode == 0x90:
			end_bar = ei
			break
	if end_bar < 0:
		return {"ticks": 0, "first_index": -1, "end_bar_index": -1}
	var ticks := 0
	var first := end_bar
	var i := end_bar - 1
	while i >= 0:
		var e = events[i]
		if e is SMD.NoteEvent or e.opcode != 0x80:
			break
		ticks += int(e.params[0]) if e.params.size() > 0 else 0
		first = i
		i -= 1
	return {"ticks": ticks, "first_index": first, "end_bar_index": end_bar}


## PURE: project a decoded event list (from `base_off`) into the lane sub-structures
## {notes, commands, loops, end_tick, end_seconds, has_end_bar}. Shared by the bounded
## `_track_view` and the continuous `flow_through_span` so both project identically.
static func _project_events(events: Array, base_off: int) -> Dictionary:
	var notes: Array = []
	var commands: Array = []
	var loops: Array = []
	var open_loops: Array = []      # [{start_tick, count}] LIFO, mirrors ts.loop_stack
	var tempo_map: Array = [[0, _FALLBACK_BPM]]   # [tick, bpm] change points
	var tick := 0
	var octave := 4                 # sequencer default before an Octave opcode
	# Per-voice running state the opcode-honesty classifier needs (ADR-0085
	# 2026-08-12 §1/§5): the active instrument (last 0xAC; -1 = none set yet, so
	# never mistaken for a trusted-empty id) and whether noise is armed on the voice
	# (0xB4/0xB6 arm, 0xB7 clears). Both march in decode order like `octave`, and
	# every note is stamped with the state in force when it plays.
	var instrument := -1
	var noise_armed := false
	var has_end_bar := false

	for ei in range(events.size()):
		var e = events[ei]
		if e is SMD.NoteEvent:
			if e.is_note():
				var n := {
					"event_index": ei,
					"offset": base_off + e.offset,
					"size": e.size,
					"start_tick": tick,
					"duration_ticks": e.delta_time,
					"relative_key": e.relative_key,
					"octave": octave,
					"active_instrument": instrument,
					"noise_armed": noise_armed,
					"velocity": e.velocity,
					"label": "%s%d" % [_NOTE_NAMES[e.relative_key], octave],
					"explicit_duration": e.size == 3,
					"has_fermata": false,
					"fermata_extension_ticks": 0,
					"start_seconds": 0.0,
					"duration_seconds": 0.0,
				}
				notes.append(n)
			else:
				# A tie (12) or a note-form rest (13). Neither occurs anywhere in the
				# corpus — FFT writes zero of both — but the decoder reads them, so the
				# model draws them: they carry time, so they live on the TIME lane.
				commands.append(_command(ei, base_off, e.offset, e.size, tick, -1,
						"time", "Hold" if e.is_tie() else "Rest", [e.delta_time]))
			tick += e.delta_time
		else:
			var op: int = e.opcode
			var label := _opcode_label(op)
			var kind := _opcode_kind(op)
			commands.append(_command(ei, base_off, e.offset, e.size, tick, op,
					kind, label, Array(e.params)))
			match op:
				0x80:   # Rest: adds wait
					tick += e.params[0] if e.params.size() > 0 else 0
				0x81:   # Fermata: sounding or silent time (§2) — `fold_spans` decides which
					tick += e.params[0] if e.params.size() > 0 else 0
				0x90:
					has_end_bar = true
				0xAC:   # Instrument: the running-instrument axis (§1)
					instrument = e.params[0] if e.params.size() > 0 else -1
				0xB4, 0xB6:   # Noise_EnableAndClock / Noise_EnableNoArm: arm the voice (§5)
					noise_armed = true
				0xB7:   # Noise_Disable: clear the voice's noise-arm
					noise_armed = false
				0x94:
					octave = e.params[0] if e.params.size() > 0 else 4
				0x95:
					octave += 1
				0x96:
					octave -= 1
				0x98:   # Repeat: open a folded bracket (count = body plays N times)
					open_loops.append({"start_tick": tick,
							"count": e.params[0] if e.params.size() > 0 else 0})
				0x99:   # Coda: close the innermost bracket
					if not open_loops.is_empty():
						var lp: Dictionary = open_loops.pop_back()
						loops.append({"start_tick": int(lp["start_tick"]),
								"end_tick": tick, "count": int(lp["count"])})
				0xA0:   # Tempo: change point for the integrated seconds tell
					if e.params.size() > 0:
						tempo_map.append([tick, SMD.fft_tempo_to_bpm(e.params[0])])
				0xA2:   # TempoSlide: approximate the tell with the target tempo
					if e.params.size() > 1:
						tempo_map.append([tick, SMD.fft_tempo_to_bpm(e.params[1])])

	# Never-closed Repeat: keep the bracket honest to the byte truth (open to end).
	while not open_loops.is_empty():
		var lp: Dictionary = open_loops.pop_back()
		loops.append({"start_tick": int(lp["start_tick"]), "end_tick": tick,
				"count": int(lp["count"])})

	# Seconds projection: integrate the (possibly variable) tempo map. Every event
	# AND every loop boundary carries integrated seconds — the ONE tempo number the
	# frame-axis panel and the ghost pips both project (ADR-0085 frame-axis §3).
	for n in notes:
		n["start_seconds"] = _seconds_at(tempo_map, int(n["start_tick"]))
		n["duration_seconds"] = _seconds_at(tempo_map,
				int(n["start_tick"]) + int(n["duration_ticks"])) - float(n["start_seconds"])
	for c in commands:
		c["seconds"] = _seconds_at(tempo_map, int(c["tick"]))
	for lp in loops:
		lp["start_seconds"] = _seconds_at(tempo_map, int(lp["start_tick"]))
		lp["end_seconds"] = _seconds_at(tempo_map, int(lp["end_tick"]))

	# The SPAN layer (ADR-0085 2026-08-18c). It LAYERS OVER the event list, it does
	# not replace it: `spans` holds REFERENCES to the head note / command dicts that
	# `notes` and `commands` already carry, stamped with the span's shape. So every
	# byte is still projected and still keyed by decode-order `event_index` — the
	# verdicts, `_stamp_owners`' borrowed-event identity and the panel's addressing
	# all keep working — while the time lane draws, numbers and addresses SPANS.
	var by_event: Dictionary = {}
	for n in notes:
		by_event[int(n["event_index"])] = n
	for c in commands:
		by_event[int(c["event_index"])] = c
	var spans: Array = []
	var folded: Array = fold_spans(events)
	for sp in folded:
		var head: Dictionary = by_event.get(int(sp["head_index"]), {})
		if head.is_empty():
			continue
		var start: int = int(sp["start_tick"])
		var note_end: int = start + int(sp["note_ticks"])
		var span_end: int = start + int(sp["total_ticks"])
		var start_sec: float = _seconds_at(tempo_map, start)
		var note_end_sec: float = _seconds_at(tempo_map, note_end)
		head["span_kind"] = str(sp["kind"])
		head["span_segments"] = sp["segments"]
		head["span_start_tick"] = start
		head["span_note_ticks"] = int(sp["note_ticks"])
		head["span_extension_ticks"] = int(sp["extension_ticks"])
		head["span_total_ticks"] = int(sp["total_ticks"])
		head["span_start_seconds"] = start_sec
		head["span_note_seconds"] = note_end_sec - start_sec
		head["span_extension_seconds"] = _seconds_at(tempo_map, span_end) - note_end_sec
		head["span_total_seconds"] = _seconds_at(tempo_map, span_end) - start_sec
		# The note's own fermata tell, now DERIVED from the span rather than
		# accumulated a second time in the walk (18b left both representations live,
		# which is what drew E317's 160-tick C as a 16-tick bar plus a lonely chip).
		if str(sp["kind"]) == "note":
			head["has_fermata"] = int(sp["extension_ticks"]) > 0
			head["fermata_extension_ticks"] = int(sp["extension_ticks"])
			head["fermata_extension_seconds"] = float(head["span_extension_seconds"])
		spans.append(head)

	# The DRAG's reach (ADR-0085 2026-08-19b §3), stamped on the span head beside its shape:
	# how many ticks of CURRENCY — consecutive rests with no opcode between them — sit on each
	# side, and whether an opcode fires inside the span. This is what the lane draws a grip
	# from, so a handle is never painted over a drag that cannot move: 5932 of 6234 corpus
	# notes have a rest on NEITHER side and correctly draw none.
	var cells: Array = DragPlan.build_cells(folded, events.size())
	for ci in range(cells.size()):
		var cell: Dictionary = cells[ci]
		if str(cell["kind"]) != "note":
			continue
		var nh: Dictionary = by_event.get(int(cell["head_index"]), {})
		if nh.is_empty():
			continue
		nh["span_left_ticks"] = DragPlan.currency(cells, ci, -1)
		nh["span_right_ticks"] = DragPlan.currency(cells, ci, 1)
		nh["span_interior_opcode"] = bool(cell["interior_opcode"])

	return {
		"notes": notes,
		"commands": commands,
		"spans": spans,
		"loops": loops,
		"end_tick": tick,
		"end_seconds": _seconds_at(tempo_map, tick),
		"has_end_bar": has_end_bar,
	}


static func _command(event_index: int, base_off: int, rel_off: int, size: int,
		tick: int, opcode: int, kind: String, label: String, params: Array) -> Dictionary:
	return {
		"event_index": event_index,
		"offset": base_off + rel_off,
		"size": size,
		"tick": tick,
		"opcode": opcode,
		"kind": kind,
		"label": label,
		"params": params,
		"seconds": 0.0,
	}


## Integrated tick→seconds: piecewise-constant BPM segments (PPQ ticks/quarter),
## variable tempo INTEGRATED, not scaled (ADR-0085 clock reconciliation).
static func _seconds_at(tempo_map: Array, tick: int) -> float:
	var secs := 0.0
	for i in range(tempo_map.size()):
		var seg_start: int = tempo_map[i][0]
		if seg_start >= tick:
			break
		var seg_end: int = tick
		if i + 1 < tempo_map.size():
			seg_end = mini(tick, int(tempo_map[i + 1][0]))
		var bpm: float = tempo_map[i][1]
		secs += float(seg_end - seg_start) * 60.0 / (bpm * float(SMD.PPQ))
	return secs


static func _opcode_label(op: int) -> String:
	if SMD.OPCODE_INFO.has(op):
		return SMD.OPCODE_INFO[op][0]
	return "Unknown_%02X" % op


## The lane-command kind vocabulary, grouped by DOES THIS ADVANCE THE CLOCK?
## (ADR-0085 amendment 2026-08-18b §5) rather than by encoding form.
##
## 18c collapses 18b's *list*: `0x80 Rest` and `0x81 Fermata` are not two lanes but
## two ways of adding time to the SAME lane — sounding time and silent time (§2) —
## so both carry kind **"time"**, as do the note path's tie and note-form rest. The
## time lane draws them as SPANS (`fold_spans`), one bar per span with three fills,
## rather than as chips: 18b's arrangement drew E317's 160-tick C as a 16-tick bar
## on Notes plus an unrelated-looking Fermata chip on Holds, which is the complaint
## §5 raised about Fermata sitting beside Octave, moved one lane over rather than
## fixed. What is left on "opcode" is voice settings ONLY.
##
## "structure" is flow (EndBar/Repeat/Coda/Loop) and "tempo" is 0xA0/0xA2 — both
## zero-tick; tempo keeps its own lane because it bends the wall clock without
## touching the tick, which is a tell, not a restriction.
##
## Shared with FedsOpcodeVerdicts, which reads `kind == "time"` to classify the note
## path's tie / note-form rest as Structural (0x80 and 0x81 also reach that verdict
## through `STRUCTURAL_OPCODES`, the OPCODE list the prune consults directly and no
## kind can reach).
static func _opcode_kind(op: int) -> String:
	match op:
		0x80, 0x81:
			return "time"
		0x90, 0x91, 0x98, 0x99, 0x9A:
			return "structure"
		0xA0, 0xA2:
			return "tempo"
	return "opcode"
