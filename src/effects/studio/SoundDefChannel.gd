extends RefCounted
## Write-side channel archetype for TIER-3 FEDS **bounded parameter editing**
## (ADR-0085 amendment 2026-08-11). The pair editor's read model annotates every
## decoded event with its FEDS-blob-absolute byte offset; this encoder patches ONE
## byte at such an offset on the live `EffectData.feds_bank.raw` — always same-size,
## never restructuring the stream (insert/delete/EndBar/form flips are the deferred
## compile path). Because the bank is a shared RefCounted, playback (play_pair),
## audition, ghost renders and the pair views all read the patched bytes live.
##
## Address = {channel:"sound_def", kind, offset, pair_idx}:
##   kind "byte"           — write a raw u8 at `offset` (opcode params, velocity,
##                           explicit-form duration bytes, toggle opcode
##                           substitutions — same-shape swaps like ReverbOn↔Off).
##   kind "s16"            — write a signed 16-bit word (0xD3 PitchBend_Add_16bit:
##                           two bytes ARE one value, high<<8 | low) as BOTH bytes
##                           in one call; `offset` addresses the high byte. One
##                           field_ref, one undo entry — the storage IS two bytes
##                           wide (distinct from a display-only signed byte).
##   kind "note_key"       — the note data-byte's upper field (byte = key*19 +
##                           delta_idx): writes key 0-11 (C..B), PRESERVES the duration
##                           index. 12 (tie) / 13 (note-form rest) are read-only forms.
##   kind "note_delta_idx" — the same byte's lower field, the delta-table index.
##                           REFUSED outright since the 2026-08-19 amendment: it is
##                           same-size but not same-TIME, so it is the parked length
##                           verb (18c §7) wearing a parameter's costume.
##
## STRUCTURAL verbs (ADR-0085 amendment 2026-08-18b) live below `apply_raw`:
## `insert_event` / `delete_event` add and remove whole events; `unrest_event` (the
## 2026-08-19 amendment) is delete's inverse on the time lane — it sounds a rest span. They are addressed by
## a BYTE BOUNDARY, never by a tick — zero-tick opcodes stack, so E317 pair 0 has four
## events at tick 0 and "insert at tick 0" cannot say which of four boundaries is
## meant.
##
## `delete_event` on something that consumes time means putting a REST there
## (ADR-0085 amendment 2026-08-18c). `_advances_the_clock` is no longer a refusal but
## the ROUTER: a zero-tick event is spliced out, a time-carrying one has its whole
## SPAN substituted byte-for-byte with `0x80 Rest`s of identical tick count. The clock
## never moves either way — spans tile the track, so a delete leaves no hole to close.
##
## `invalidates_sim = false` (no framebuffer impact); declares `invalidates_feds`
## — the page's signal to re-derive pair views and re-render the ghost/energy of
## every sound_id resolving into the edited pair. `pair_idx` scopes that fan-out.
##
## No class_name (ADR-0004); load()ed by path.

const SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")
const Catalog = preload("res://src/effects/studio/FedsOpcodeCatalog.gd")
const PairModel = preload("res://src/effects/studio/FedsPairModel.gd")
const GhostProjector = preload("res://src/effects/studio/SoundGhostProjector.gd")
const DragPlan = preload("res://src/effects/studio/SoundDragPlan.gd")

# 0-11 = C..B. The decoder also reads 12 (tie) and 13 (note-form rest), but FFT writes
# ZERO of either in music or effects (ADR-0085 18c §1), so they are forms the studio only
# ever READS: writing one would give the studio a second rest it just finished removing.
const _NOTE_KEY_MAX := 11
const _DELTA_IDX_MAX := 18
# `0x80 Rest` is THE rest (ADR-0085 2026-08-18c §1) — the form FFT writes 87,793 times
# across music and effects, against zero note-form rests and zero ties.
const REST_OPCODE := 0x80
# What an un-rest sounds (ADR-0085 amendment 2026-08-19). Both come from the corpus, not
# from taste: every one of the 6234 FEDS notes has velocity 96 — there is no second value
# to choose between — and C is its most common key (3143, 50.4%). The key is then a
# one-click bounded edit (`note_key`), so this default is a starting point, not a verdict.
## The outro's ceiling. `0x80` chunks past 255 into a run, so any count is spellable — this
## is a fat-finger guard, not an encoding limit: 65535 ticks is ~23 minutes of silence at the
## corpus's one tempo, against a longest authored track of a few seconds.
const MAX_OUTRO_TICKS := 65535

const NOTE_VELOCITY := 96
const NOTE_KEY := 0


## Write one raw sub-field and return the snapshot the choke point records for
## undo (scalar replay through this same path). {} on any invalid address/value.
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	var bank = _resolve_bank(data)
	if bank == null:
		push_error("SoundDefChannel: no FEDS bank on effect data")
		return {}
	var offset: int = int(field_ref.get("offset", -1))
	if offset < 0 or offset >= bank.raw.size():
		push_error("SoundDefChannel: offset %d outside the FEDS blob (%d bytes)"
				% [offset, bank.raw.size()])
		return {}
	var value := int(new_raw)
	var kind: String = str(field_ref.get("kind", "byte"))
	match kind:
		"byte":
			if value < 0 or value > 255:
				push_error("SoundDefChannel: %d is not a byte" % value)
				return {}
			if _is_time_carrying_param(bank, offset):
				# The same costume `note_delta_idx` wore, on the other two forms that carry
				# time (ADR-0085 2026-08-19 §6, extended by 2026-08-19c). A `0x80 Rest`'s and
				# a `0x81 Fermata`'s param byte are same-SIZE but not same-TIME: retyping one
				# slides every later event in this voice while the pair's other voice stays
				# put. Refused at the encoder as well as unoffered by the projector, because
				# a field_ref can be built by any tool.
				push_error("SoundDefChannel: that byte is a rest's or a fermata's tick count "
						+ "— rewriting it re-times every later event in this voice. The drag "
						+ "spends silence under a law (19b §3); the outro is where new time "
						+ "goes (19c). Neither is a bounded parameter.")
				return {}
			var before: int = bank.raw[offset]
			bank.raw[offset] = value
			return _result(before, value)
		"s16":
			# A genuine 16-bit param (0xD3 PitchBend_Add_16bit): two bytes ARE one
			# signed value (high<<8 | low). Write BOTH in one call — one field_ref,
			# one undo entry, one honest number. `offset` addresses the high byte.
			if offset + 1 >= bank.raw.size():
				push_error("SoundDefChannel: s16 at %d needs two bytes in the blob" % offset)
				return {}
			if value < -32768 or value > 32767:
				push_error("SoundDefChannel: %d is not a signed 16-bit value" % value)
				return {}
			var before16: int = _to_s16(bank.raw[offset], bank.raw[offset + 1])
			bank.raw[offset] = (value >> 8) & 0xFF
			bank.raw[offset + 1] = value & 0xFF
			return _result(before16, value)
		"note_key":
			if value < 0 or value > _NOTE_KEY_MAX:
				push_error(("SoundDefChannel: note key %d outside 0–%d (C..B) — 12 (tie) "
						+ "and 13 (note-form rest) are read-only forms: FFT writes neither, "
						+ "and `0x80` is the studio's one rest") % [value, _NOTE_KEY_MAX])
				return {}
			var data_byte: int = bank.raw[offset]
			var before_key: int = data_byte / 19
			bank.raw[offset] = value * 19 + (data_byte % 19)
			return _result(before_key, value)
		"note_delta_idx":
			# REFUSED, always (ADR-0085 amendment 2026-08-19 §6). The write is same-SIZE,
			# which is what made it look like a bounded parameter, but it is not
			# same-TIME: it re-times the span and slides everything after it. That is the
			# length verb 18c §7 parks. Refused here as well as unoffered by the
			# projector, because a field_ref can be built by any tool.
			push_error("SoundDefChannel: a note's duration re-times the span — that is the "
					+ "length verb (ADR-0085 18c §7), whose encoding is parked, not a "
					+ "bounded parameter. Delete (rest) and un-rest hold the clock still.")
			return {}
	push_error("SoundDefChannel: unknown sound_def kind '%s'" % kind)
	return {}


## Is `offset` the PARAM byte of a `0x80 Rest` or a `0x81 Fermata`? The scalar path
## addresses raw blob bytes, so it cannot tell a tick count from a volume without asking the
## decoder: find the track that owns the byte, decode it, and look. Cheap — a FEDS track is
## tens of bytes — and it is what makes the refusal above real rather than cosmetic.
static func _is_time_carrying_param(bank, offset: int) -> bool:
	var owner := -1
	var base := -1
	for t in range(bank.num_tracks):
		var off: int = bank.track_offsets[t]
		if off == 0 or off > offset:
			continue
		if off > base:
			base = off
			owner = t
	if owner < 0:
		return false
	var bytes: PackedByteArray = bank.get_track_bytes(owner)
	for e in SMD.decode_track(bytes, bytes.size()):
		if e is SMD.NoteEvent or not (e.opcode in Catalog.TIME_CARRYING):
			continue
		if base + e.offset + 1 == offset:
			return true
	return false


## Two's-complement reconstruction of a signed 16-bit word from its two stored bytes.
static func _to_s16(hi: int, lo: int) -> int:
	var v: int = ((hi & 0xFF) << 8) | (lo & 0xFF)
	return v - 65536 if v >= 32768 else v


static func _result(before: int, after: int) -> Dictionary:
	return {
		"before_raw": before,
		"after_raw": after,
		"invalidates_sim": false,
		"invalidates_feds": true,
		"faithful": {"ok": true, "reason": ""},
	}


static func _resolve_bank(data):
	if data == null or data.feds_bank == null:
		return null
	return data.feds_bank


## --- Structural verbs (ADR-0085 amendment 2026-08-18b) ----------------------
##
## Address: {channel:"sound_def", pair_idx, track_idx, at}. `at` is a FEDS-blob-
## absolute BYTE BOUNDARY — the same coordinate every decoded event already carries
## as its `offset`, which is why "add after this event" is expressible and "add at
## this tick" is not (§4). Insert also carries `opcode` + `params`.
##
## Both verbs REPLACE the whole FedsBank (`SoundGhostProjector.rebuild_bank_with_track`
## splices the track and fixes the offset table + data_size) rather than mutating it,
## so the session's snapshot undo is exact — the prune's contract verbatim.


## Insert `opcode` at the byte boundary `at`. Returns the choke point's structural
## result, or {} on any refusal (a mid-event address, a time-carrying or flow opcode,
## a null slot, an out-of-track boundary) — refused, never clamped: a clamp would
## write somewhere the author did not point.
static func insert_event(data, field_ref: Dictionary) -> Dictionary:
	var ctx := _track_context(data, field_ref)
	if ctx.is_empty():
		return {}
	var at: int = int(field_ref.get("at", -1))
	var boundaries: Array = ctx["boundaries"]
	if not (at in boundaries):
		push_error("SoundDefChannel: %d is not an event boundary in track %d"
				% [at, int(ctx["track_idx"])])
		return {}
	var op: int = int(field_ref.get("opcode", -1))
	if not Catalog.can_insert(op, at == int(ctx["phantom_boundary"])):
		push_error("SoundDefChannel: opcode 0x%02X is not insertable here" % op)
		return {}
	var blob: PackedByteArray = Catalog.encode(op, field_ref.get("params", PackedByteArray()))
	if blob.is_empty():
		return {}
	var rel: int = at - int(ctx["base"])
	var bytes: PackedByteArray = ctx["bytes"]
	var out := PackedByteArray()
	out.append_array(bytes.slice(0, rel))
	out.append_array(blob)
	out.append_array(bytes.slice(rel))
	# The new event's index = however many events end at or before the boundary.
	return _swap_track(data, ctx, out, boundaries.find(at))


## Delete the event that STARTS at `at`. A zero-tick event is spliced out and the
## selection lands on the anchor — the event the deleted one followed (§8). A
## time-carrying one is RESTED instead (see `_rest_span`), keeping its ticks and its
## own selection. Returns {} when `at` names no event, or on any of `_rest_span`'s
## refusals.
static func delete_event(data, field_ref: Dictionary) -> Dictionary:
	var ctx := _track_context(data, field_ref)
	if ctx.is_empty():
		return {}
	var at: int = int(field_ref.get("at", -1))
	var events: Array = ctx["events"]
	var base: int = int(ctx["base"])
	var idx := -1
	for i in range(events.size()):
		if base + events[i].offset == at:
			idx = i
			break
	if idx < 0:
		push_error("SoundDefChannel: no event starts at %d in track %d"
				% [at, int(ctx["track_idx"])])
		return {}
	if _advances_the_clock(events[idx]):
		return _rest_span(data, ctx, idx)
	var rel: int = at - base
	var bytes: PackedByteArray = ctx["bytes"]
	var out := PackedByteArray()
	out.append_array(bytes.slice(0, rel))
	out.append_array(bytes.slice(rel + events[idx].size))
	return _swap_track(data, ctx, out, maxi(0, idx - 1) if events.size() > 1 else -1)


## Delete a SPAN by resting it (ADR-0085 amendment 2026-08-18c §4): each of the span's
## time-carrying bytes is replaced IN PLACE by a `0x80 Rest` of identical tick count.
##
##   vv dd      →  80 pp   (pp = the DELTA_TIME_TABLE duration, <=192)  same size
##   vv kk tt   →  80 tt   (explicit-duration note, kk = key*19)        one byte smaller
##   81 pp      →  80 pp   (every Fermata segment of the span)          same size
##
## Everything follows from substituting SEGMENT for segment. The interior opcodes keep
## their exact firing tick (1600 of 1619 fermata spans have one). The event COUNT does
## not change, so `event_index` is stable and the ordinals, the verdict keying, the
## borrowed-event identity and the selection all sit still — a delete is not a resize
## in the addressing sense. The byte size is unchanged for 5769 of 6234 notes and for
## every Fermata, so a delete essentially never relocates. And `NoteA … NoteB Ferm`
## deleted at NoteB gives `NoteA … Rest Rest`, where the post-note scan walks both
## `0x80`s as bare `accumulated +=` — NoteA does NOT grow, which is true of a SPAN
## delete and untrue of a byte delete.
##
## Refused, never silently reshaped: a REST span (deleting silence is a literal no-op —
## the only way to remove silence is to make it not silence, so the menu offers no
## Delete row on a grey bar), a span segment addressed instead of its head, and any
## span containing a TIE (zero corpus occurrences, so designing its semantics would
## mean inventing the data to test them).
static func _rest_span(data, ctx: Dictionary, head_idx: int) -> Dictionary:
	var events: Array = ctx["events"]
	var span: Dictionary = {}
	for sp in PairModel.fold_spans(events):
		if int(sp["head_index"]) == head_idx:
			span = sp
			break
	if span.is_empty():
		push_error(("SoundDefChannel: event %d is a SEGMENT of a span, not its head — "
				+ "delete the span at its note, not one of the bytes inside it") % head_idx)
		return {}
	if str(span["kind"]) == "rest":
		push_error("SoundDefChannel: that span is already a rest — deleting a rest is a "
				+ "no-op; the only way to remove silence is to make it not silence")
		return {}
	for ei in span["segments"]:
		var seg = events[int(ei)]
		if seg is SMD.NoteEvent and seg.is_tie():
			push_error(("SoundDefChannel: the span at %d contains a tie, which no FFT "
					+ "sound does — its delete semantics are undesigned, not refused by "
					+ "accident") % head_idx)
			return {}
	# Substitute back-to-front so each earlier segment's offset stays valid, and by
	# slicing the ORIGINAL bytes rather than re-emitting: bytes outside the span —
	# including the interior opcodes and anything past the decoder's EndBar stop — are
	# carried verbatim.
	var out: PackedByteArray = (ctx["bytes"] as PackedByteArray).duplicate()
	var segs: Array = (span["segments"] as Array).duplicate()
	segs.reverse()
	for ei in segs:
		var seg2 = events[int(ei)]
		var ticks: int = seg2.delta_time if seg2 is SMD.NoteEvent \
				else (seg2.params[0] if seg2.params.size() > 0 else 0)
		var spliced := PackedByteArray()
		spliced.append_array(out.slice(0, seg2.offset))
		spliced.append(REST_OPCODE)
		spliced.append(ticks & 0xFF)
		spliced.append_array(out.slice(seg2.offset + seg2.size))
		out = spliced
	# The selection stays on the span's own event — it is the same event_index, now a
	# rest — rather than falling back to an anchor the way a byte delete must (§8).
	return _swap_track(data, ctx, out, head_idx)


## Un-rest a span — delete's inverse (ADR-0085 amendment 2026-08-19). 18c §6 named this
## verb ("the only way to remove silence is to make it not silence") and left it unbuilt,
## so until now a delete had no inverse but Ctrl+Z. Addressed exactly like a delete: the
## byte boundary the span's HEAD starts at.
##
## The span's ticks are re-spelled as ONE note of identical length, at the corpus's only
## velocity and its most common key (`NOTE_VELOCITY` / `NOTE_KEY`):
##
##   80 pp   →  vv dd        (pp is one of DELTA_TIME_TABLE's 18 values, 713 of 779)   same size
##   80 pp   →  vv 00 pp     (the other 66 — the explicit-duration form)          one byte larger
##
## A rest span is ALWAYS one segment — silence closes the open note in `fold_spans`, so
## nothing extends a rest — which is why one note replaces it and the event count, the
## ordinals, the verdict keying and the selection all sit still, exactly as they do for a
## delete. The clock never moves either way.
##
## Refused, never silently reshaped: a NOTE span (already sounding — the no-op in this
## direction), a span segment addressed instead of its head, a span headed by a TIE (zero
## corpus occurrences in either direction) and a ZERO-tick span (no length to sound; a
## delete of the corpus's one 0-tick Fermata is the only way to make one).
##
## Rejected — un-resting a rest that FOLLOWS a note into a `0x81 Fermata`, i.e. giving its
## ticks back to the previous note. That is the parked length verb (18c §7) wearing this
## verb's name; the un-rest makes a note, as `replace_rest_with_note_by_authored_index`
## does in the DAW.
static func unrest_event(data, field_ref: Dictionary) -> Dictionary:
	var ctx := _track_context(data, field_ref)
	if ctx.is_empty():
		return {}
	var grab := _grab_rest_span(ctx, int(field_ref.get("at", -1)), "sound")
	if grab.is_empty():
		return {}
	var idx: int = int(grab["index"])
	var head = grab["head"]
	var ticks: int = int((grab["span"] as Dictionary)["total_ticks"])
	if ticks <= 0 or ticks > 255:
		push_error("SoundDefChannel: a span of %d ticks has no note form — a note carries "
				% ticks + "1-255 ticks, and zero ticks would sound nothing")
		return {}
	# Nothing else in the track moves — the bytes around the span are carried verbatim,
	# as in `_rest_span`.
	var note: PackedByteArray = _encode_note(ticks)
	var bytes: PackedByteArray = ctx["bytes"]
	var out := PackedByteArray()
	out.append_array(bytes.slice(0, head.offset))
	out.append_array(note)
	out.append_array(bytes.slice(head.offset + head.size))
	# Same event, now a note: the selection sits still, exactly as it does for a delete.
	return _swap_track(data, ctx, out, idx)


## The corpus note of `ticks` length, in the SMALLEST form that says that length
## EXACTLY: the 2-byte table form when the count is one of `DELTA_TIME_TABLE`'s 18
## values, else the 3-byte explicit form. The tick count is the one thing a time verb
## must never round, so the choice is forced, not preferred. Shared by the un-rest and
## the paint — one encoder, so the two can never disagree about a byte.
static func _encode_note(ticks: int, velocity: int = NOTE_VELOCITY,
		key: int = NOTE_KEY) -> PackedByteArray:
	var di: int = Array(SMD.DELTA_TIME_TABLE).find(ticks)
	var note := PackedByteArray()
	note.append(velocity)
	if di > 0:
		note.append(key * 19 + di)
	else:
		note.append(key * 19)
		note.append(ticks)
	return note


## `n` ticks of silence as `0x80` rests. One rest carries one param byte, so a deposit past
## 255 is spelled as a RUN — more silence, spelled differently, never a clamp of the gesture.
## Zero ticks emit NOTHING: `80 00` would manufacture the zero-tick span the un-rest refuses
## to sound, and a rest spent to zero is meant to disappear (that is what makes two notes
## adjacent).
static func _encode_rests(ticks: int) -> PackedByteArray:
	var out := PackedByteArray()
	var left: int = ticks
	while left > 0:
		var chunk: int = mini(left, 255)
		out.append(REST_OPCODE)
		out.append(chunk)
		left -= chunk
	return out


## How many `0x80` events `_encode_rests` writes for `ticks` — what the selection has to
## step over when the tiling in front of it changes shape.
static func _rest_event_count(ticks: int) -> int:
	return 0 if ticks <= 0 else int(ceil(float(ticks) / 255.0))


## The rest SPAN whose head starts at byte `at`, or {} with the refusal already reported.
## The un-rest's and the paint's shared gate — a segment addressed instead of its head, a
## span that already sounds, and a span headed by a TIE are refused identically, because
## the two verbs differ only in WHERE inside the silence the note lands.
static func _grab_rest_span(ctx: Dictionary, at: int, verb: String) -> Dictionary:
	var events: Array = ctx["events"]
	var base: int = int(ctx["base"])
	var idx := -1
	for i in range(events.size()):
		if base + events[i].offset == at:
			idx = i
			break
	if idx < 0:
		push_error("SoundDefChannel: no event starts at %d in track %d"
				% [at, int(ctx["track_idx"])])
		return {}
	var span: Dictionary = {}
	for sp in PairModel.fold_spans(events):
		if int(sp["head_index"]) == idx:
			span = sp
			break
	if span.is_empty():
		push_error(("SoundDefChannel: event %d is a SEGMENT of a span, not its head — "
				+ "%s the span at its head, not one of the bytes inside it") % [idx, verb])
		return {}
	if str(span["kind"]) != "rest":
		push_error("SoundDefChannel: that span already sounds — there is no silence in it "
				+ "to %s; to change what it sounds, edit its key" % verb)
		return {}
	var head = events[idx]
	if head is SMD.NoteEvent and head.is_tie():
		push_error(("SoundDefChannel: the span at %d is headed by a tie, which no FFT "
				+ "sound writes — its semantics are undesigned, not refused by accident") % idx)
		return {}
	return {"index": idx, "span": span, "head": head}


## PAINT a note INSIDE a rest span, splitting it (ADR-0085 amendment 2026-08-19b §2):
##
##   80 NN   →   80 aa | <note d> | 80 rr        (a = offset_ticks, r = N - a - d)
##
## Addressed like the un-rest — the span head's byte boundary — PLUS a tick offset within
## the span. 18b §4's byte-boundary rule is not weakened by that: it exists because
## zero-tick opcodes stack, and a rest span is exactly ONE two-byte event with no interior
## (`fold_spans` gives a `0x80` no way to be extended), so there is nothing to
## disambiguate. Span identity for the anchor, ticks for the position — the shape the DAW's
## `replace_rest_with_note_by_authored_index` already takes.
##
## A piece of ZERO length is not written: `80 00` would manufacture the zero-tick span the
## un-rest refuses to sound. So the paint emits two events flush against either end and
## three in the middle, and `paint(0, N)` is the un-rest byte for byte — same encoder.
##
## The clock does not move (a + d + (N-a-d) = N), but the event COUNT does, which is the
## one thing 18c §4's "the ordinals sit still" does not carry over to. The selection
## therefore lands on the NOTE the author just made (§8), not on the rest it split.
##
## Refused, never clamped — a clamp would sound somewhere the author did not point: every
## refusal `_grab_rest_span` makes, plus an offset before the span's start, a duration of
## zero (it would sound nothing) and a placement running past the span's last tick.
static func paint_event(data, field_ref: Dictionary) -> Dictionary:
	var ctx := _track_context(data, field_ref)
	if ctx.is_empty():
		return {}
	var grab := _grab_rest_span(ctx, int(field_ref.get("at", -1)), "paint into")
	if grab.is_empty():
		return {}
	var span: Dictionary = grab["span"]
	var total: int = int(span["total_ticks"])
	var lead: int = int(field_ref.get("offset_ticks", 0))
	var dur: int = int(field_ref.get("duration_ticks", 0))
	if lead < 0 or dur <= 0 or lead + dur > total:
		push_error(("SoundDefChannel: a %d-tick note at +%d does not fit the %d-tick span "
				+ "at %d — refused, never clamped to fit")
				% [dur, lead, total, int(field_ref.get("at", -1))])
		return {}
	var head = grab["head"]
	var out := PackedByteArray()
	var bytes: PackedByteArray = ctx["bytes"]
	out.append_array(bytes.slice(0, head.offset))
	if lead > 0:
		out.append(REST_OPCODE)
		out.append(lead)
	out.append_array(_encode_note(dur))
	var trail: int = total - lead - dur
	if trail > 0:
		out.append(REST_OPCODE)
		out.append(trail)
	out.append_array(bytes.slice(head.offset + head.size))
	return _swap_track(data, ctx, out, int(grab["index"]) + (1 if lead > 0 else 0))


## DRAG a note span through the silence around it (ADR-0085 amendment 2026-08-19b §2/§3) —
## the lane's three gestures behind one verb, because all three write the same kind of number:
##
##   gesture "move"          leading rest `a+k`, trailing rest `b-k`      no note byte
##   gesture "resize_right"  the END moves; one flanking rest absorbs     the duration byte
##   gesture "resize_left"   the START moves; the end sits still          the duration byte
##
## Addressed exactly like the un-rest and the paint — the span HEAD's byte boundary — plus a
## signed `delta_ticks`. The pixel is read once at grab time and converted immediately, so
## every stage downstream of the grab speaks ticks (§5); the address is re-resolved against
## the PRISTINE bytes on every motion of a drag, which is why it stays valid even after a
## motion has spliced a rest out from in front of it.
##
## `SoundDragPlan` owns the whole decision — the clean-run cascade, the three walls, the
## insert-or-splice arithmetic — and this applies it. Everything outside the affected event
## range is carried VERBATIM (interior opcodes, the bytes past the decoder's EndBar stop),
## the way `_rest_span` carries them: the minimum edit, so the author's spelling of the
## silence a drag did not reach survives it.
##
## CLAMPED, not refused, on the way to a wall — a zero-tick drag still swaps the track, so a
## drag that has been pulled back to where it started re-derives the pair views to the
## pristine tiling instead of leaving the picture one motion stale. Refused outright only for
## §8's two parks and for an address that is not a span head; `SoundDragPlan.plan`'s `reason`
## is reported verbatim so the refusal names itself.
static func drag_event(data, field_ref: Dictionary) -> Dictionary:
	var ctx := _track_context(data, field_ref)
	if ctx.is_empty():
		return {}
	var at: int = int(field_ref.get("at", -1))
	var events: Array = ctx["events"]
	var base: int = int(ctx["base"])
	var idx := -1
	for i in range(events.size()):
		if base + events[i].offset == at:
			idx = i
			break
	if idx < 0:
		push_error("SoundDefChannel: no event starts at %d in track %d"
				% [at, int(ctx["track_idx"])])
		return {}
	var cells: Array = DragPlan.build_cells(PairModel.fold_spans(events), events.size())
	var ci: int = DragPlan.cell_of(cells, idx)
	if ci < 0:
		push_error(("SoundDefChannel: event %d is a SEGMENT of a span, not its head — drag "
				+ "the span at its head, not one of the bytes inside it") % idx)
		return {}
	var plan: Dictionary = DragPlan.plan(cells, ci, str(field_ref.get("gesture", DragPlan.MOVE)),
			int(field_ref.get("delta_ticks", 0)))
	if not bool(plan.get("ok", false)):
		push_error("SoundDefChannel: %s" % str(plan.get("reason", "the drag was refused")))
		return {}
	var res: Dictionary = _apply_drag_plan(ctx, plan, idx)
	var out: Dictionary = _swap_track(data, ctx, res["bytes"], int(res["event_index"]))
	if not out.is_empty():
		# What the drag ACHIEVED after clamping — the surface reads it back so the grip stops
		# where the wall is rather than where the cursor is.
		out["delta_ticks"] = int(plan.get("delta", 0))
	return out


## SET THE OUTRO — the only verb on this lane that MOVES THE CLOCK (ADR-0085 amendment
## 2026-08-19c). Every other verb is a substitution inside a fixed tick total; this one
## rewrites the silence between a track's last authored event and its `0x90 EndBar`:
##
##   note(12) EndBar              set 48  ->  note(12) rest(48) EndBar     end_tick 12 -> 60
##   note(12) rest(8) EndBar      set 20  ->  note(12) rest(20) EndBar     one rest, not two
##   note(12) rest(8) EndBar      set 0   ->  note(12) EndBar              the outro is spliced out
##
## Addressed by TRACK, not by a byte boundary — the outro is not an event and is absent from
## 1917 of the corpus's 1928 terminated tracks, so there is nothing to point at until it
## exists. `outro_ticks` is ABSOLUTE, never a delta: one number, so trim is set-to-zero, a
## repeat of the same call is a no-op, and the menu's "+48" is arithmetic the surface does.
##
## It re-times NOTHING. The new bytes go immediately in front of the terminator, after every
## zero-tick opcode the track ends on (482 corpus tracks end on a `Coda`, 7 on an
## `FMod_Disable`), so no authored event's firing tick moves — and the track's ticks are its
## own: the pair's other voice is a separate stream that this does not touch. What DOES move
## is `end_tick`, which is why the result rides the same re-derive as every other structural
## verb rather than a refold.
##
## REFUSED, never clamped:
## - a STUB. It has no terminator, so its own stream stops at a byte edge and everything
##   after it is BORROWED from the next track (`get_track_bytes_from`). Writing silence at
##   that edge would push another track's authored work later in ticks — 19b §3's law broken
##   from the one direction §3 never faced. `insert_event` already offers `EndBar` at exactly
##   that boundary (`FedsOpcodeCatalog.can_insert`), so the path is: say where this track
##   ends, THEN say how long it lasts.
## - a track with no events at all, a negative count, and anything past `MAX_OUTRO_TICKS`.
##
## The selection lands on the outro's first rest when it has one, on the terminator when it
## does not — the author asked for silence, so the picture selects the silence.
static func set_outro(data, field_ref: Dictionary) -> Dictionary:
	var ctx := _track_context(data, field_ref)
	if ctx.is_empty():
		return {}
	var events: Array = ctx["events"]
	if events.is_empty():
		push_error("SoundDefChannel: track %d decodes to no events — there is no end to write in front of"
				% int(ctx["track_idx"]))
		return {}
	var want: int = int(field_ref.get("outro_ticks", -1))
	if want < 0 or want > MAX_OUTRO_TICKS:
		push_error(("SoundDefChannel: an outro of %d ticks is outside 0..%d — refused, not "
				+ "clamped: a clamp would set a length the author did not ask for")
				% [want, MAX_OUTRO_TICKS])
		return {}
	var outro: Dictionary = PairModel.outro_of(events)
	if int(outro["end_bar_index"]) < 0:
		push_error(("SoundDefChannel: track %d is a STUB — it has no EndBar, so everything "
				+ "after its last byte is BORROWED from the next track and silence written "
				+ "here would re-time it. Add an EndBar at its phantom boundary first, then "
				+ "the track has an end to lengthen.") % int(ctx["track_idx"]))
		return {}
	var bytes: PackedByteArray = ctx["bytes"]
	var first: int = int(outro["first_index"])
	var cut: int = events[first].offset
	var out := PackedByteArray()
	out.append_array(bytes.slice(0, cut))
	out.append_array(_encode_rests(want))
	# Everything from the terminator on is carried VERBATIM — including any bytes past the
	# decoder's EndBar stop, which are unreachable but authored.
	out.append_array(bytes.slice(events[int(outro["end_bar_index"])].offset))
	return _swap_track(data, ctx, out, first)


## Re-emit the events a drag plan touches, carrying everything else verbatim. Returns
## {bytes, event_index} — the dragged span's index AFTER the re-tiling, which moves when a
## rest in front of it is spliced out or one is inserted there (the selection follows the
## note the author is holding, never a byte position).
static func _apply_drag_plan(ctx: Dictionary, plan: Dictionary, head_idx: int) -> Dictionary:
	var events: Array = ctx["events"]
	var bytes: PackedByteArray = ctx["bytes"]
	var rests: Dictionary = plan.get("rests", {})
	var insert_before: int = int(plan.get("insert_before", -1))
	var insert_ticks: int = int(plan.get("insert_ticks", 0))
	var note_index: int = int(plan.get("note_index", -1))
	var note_ticks: int = int(plan.get("note_ticks", -1))
	# Where the selection lands: one entry per rest whose event count changed ahead of the
	# span, plus the inserted one when it goes in front.
	var shift: int = 0
	if insert_before >= 0 and insert_before <= head_idx:
		shift += _rest_event_count(insert_ticks)
	for k in rests.keys():
		if int(k) < head_idx:
			shift += _rest_event_count(int(rests[k])) - 1
	var touched: Array = []
	for k in rests.keys():
		touched.append(int(k))
	if note_index >= 0:
		touched.append(note_index)
	if insert_before >= 0:
		# An insert is a BOUNDARY, so the range has to cover the events on both sides of it
		# (`insert_before == events.size()` means "after the last one").
		touched.append(clampi(insert_before, 0, events.size() - 1))
		touched.append(clampi(insert_before - 1, 0, events.size() - 1))
	if touched.is_empty():
		# A drag clamped flat: nothing to write, but still a swap (see the doc comment).
		return {"bytes": bytes.duplicate(), "event_index": head_idx}
	var lo: int = int(touched[0])
	var hi: int = int(touched[0])
	for t in touched:
		lo = mini(lo, int(t))
		hi = maxi(hi, int(t))
	var out := PackedByteArray()
	out.append_array(bytes.slice(0, events[lo].offset))
	for i in range(lo, hi + 1):
		if i == insert_before:
			out.append_array(_encode_rests(insert_ticks))
		if rests.has(i):
			out.append_array(_encode_rests(int(rests[i])))
		elif i == note_index:
			# The note keeps its OWN velocity and key — a resize re-times a note, it does not
			# re-author it (unlike the un-rest, which has no note to preserve).
			out.append_array(_encode_note(note_ticks, events[i].velocity, events[i].relative_key))
		else:
			out.append_array(bytes.slice(events[i].offset, events[i].offset + events[i].size))
	if insert_before == hi + 1:
		out.append_array(_encode_rests(insert_ticks))
	out.append_array(bytes.slice(events[hi].offset + events[hi].size))
	return {"bytes": out, "event_index": head_idx + shift}


## Does this decoded event move the tick? Exactly five forms do: a note, a tie, a
## note-form rest (all three from the note path) and the two time-carrying opcodes.
## The GATE, no longer a refusal (18c): it routes a delete to the span substitution
## instead of to the byte splice.
static func _advances_the_clock(e) -> bool:
	if e is SMD.NoteEvent:
		return true
	return e.opcode in Catalog.TIME_CARRYING


## Resolve + validate one track's editing context: {bank, track_idx, base, bytes,
## events, boundaries, phantom_boundary}. {} when the address does not name a real,
## byte-owning track. `boundaries` are the blob-absolute byte edges an insert may
## address — the track start, then after each decoded event.
static func _track_context(data, field_ref: Dictionary) -> Dictionary:
	var bank = _resolve_bank(data)
	if bank == null:
		push_error("SoundDefChannel: no FEDS bank on effect data")
		return {}
	var t: int = int(field_ref.get("track_idx", -1))
	if t < 0 or t >= bank.num_tracks:
		push_error("SoundDefChannel: track %d outside the bank (%d tracks)" % [t, bank.num_tracks])
		return {}
	var base: int = bank.track_offsets[t]
	if base == 0:
		# A null slot owns no bytes — it is a hole in the table, not an empty track.
		push_error("SoundDefChannel: track %d is a null slot — it owns no bytes to edit" % t)
		return {}
	var bytes: PackedByteArray = bank.get_track_bytes(t)
	var events: Array = SMD.decode_track(bytes, bytes.size())
	var boundaries: Array = [base]
	var last_end := base
	for e in events:
		last_end = base + e.offset + e.size
		boundaries.append(last_end)
	# The phantom's boundary: on a STUB (no decoded EndBar) the byte edge where its own
	# authored stream stops and the borrowing starts — the one place an EndBar belongs.
	var phantom := -1
	var has_end_bar := false
	for e in events:
		if not (e is SMD.NoteEvent) and e.opcode == Catalog.END_BAR:
			has_end_bar = true
	if not has_end_bar:
		phantom = last_end
	return {
		"bank": bank, "track_idx": t, "base": base, "bytes": bytes,
		"pair_idx": int(field_ref.get("pair_idx", -1)),
		"events": events, "boundaries": boundaries, "phantom_boundary": phantom,
	}


## Swap in the rewritten track and report the structural result. `event_index` is
## where the selection lands (§8): the new opcode after an insert, the anchor after a
## delete, -1 when the track emptied.
static func _swap_track(data, ctx: Dictionary, new_bytes: PackedByteArray,
		event_index: int) -> Dictionary:
	var bank = ctx["bank"]
	var rebuilt = GhostProjector.rebuild_bank_with_track(bank, int(ctx["track_idx"]), new_bytes)
	if rebuilt == null:
		push_error("SoundDefChannel: the track splice ran off the blob")
		return {}
	var before: int = bank.raw.size()
	data.feds_bank = rebuilt
	return {
		"structural": true,
		"invalidates_sim": false,
		"invalidates_feds": true,
		"pair_idx": int(ctx.get("pair_idx", -1)),
		"track_idx": int(ctx["track_idx"]),
		"event_index": event_index,
		"before_bytes": before,
		"after_bytes": rebuilt.raw.size(),
	}
