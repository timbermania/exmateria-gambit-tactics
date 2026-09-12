extends RefCounted
## The **pair** target-kind projector (ADR-0073 / ADR-0085 TIER-3) — the FEDS pair
## editor's inspector surface. A container's Sound slot resolves to a FEDS pair
## (pair_idx = id - 1); this renders the pair's 2 opcode tracks: the pair overview
## (tick axis + seconds tell), then one section per track lane with its note bars
## and opcode chips. Slice 1 is READ-ONLY const cells; slice 2 upgrades the
## parameterized rows to edit cells through the SoundDefChannel encoder.
##
## Honesty leads (the ADR's rules): the header opens with provenance — which shared
## containers resolve into this pair and how many triggers each fires for — and a
## stub track's flow-through is a badge on its section title (a tell, never a block).
##
## THIN reader: the studio threads pre-projected pair views (FedsPairModel) into
## the score under "feds_pairs"; this reads score["feds_pairs"] and never touches
## the bank itself (the EmitterTargetProjector/SoundContainerProjector pattern).
## A missing view is inert (empty), never a crash. No class_name (ADR-0004).

const _Fields = preload("res://src/effects/studio/ProjectorField.gd")
const _Target = preload("res://src/effects/studio/InspectionTarget.gd")
const _SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")
const _Semantics = preload("res://src/effects/studio/FedsParamSemantics.gd")
const _InstrumentNames = preload("res://src/effects/studio/FedsInstrumentNames.gd")
const _Audition = preload("res://src/effects/studio/FedsNoteAudition.gd")

const _INSTRUMENT_OP := 0xAC   # the last one in-track sets the active waveset

const _TRACK_LETTERS := ["A", "B"]

# Ring 3 (ADR-0085): paired 0-param toggles are SAME-SHAPE opcode substitutions —
# an enum whose value IS the opcode byte, written in place. author label + the pair.
const _TOGGLE_PAIRS := {
	0xB0: ["Slur", [0xB0, 0xB1]], 0xB1: ["Slur", [0xB0, 0xB1]],
	0xB2: ["FMod", [0xB2, 0xB3]], 0xB3: ["FMod", [0xB2, 0xB3]],
	0xB6: ["Noise", [0xB6, 0xB7]], 0xB7: ["Noise", [0xB6, 0xB7]],
	0xBA: ["Reverb", [0xBA, 0xBB]], 0xBB: ["Reverb", [0xBA, 0xBB]],
	0xAE: ["Percussion", [0xAE, 0xAF]], 0xAF: ["Percussion", [0xAE, 0xAF]],
	0xDA: ["Flag 0xFE", [0xDA, 0xDB]], 0xDB: ["Flag 0xFE", [0xDA, 0xDB]],
	0xE6: ["LFO sub-slot 1", [0xE6, 0xE7]], 0xE7: ["LFO sub-slot 1", [0xE6, 0xE7]],
}

# The twelve writable keys. The decoder's other two readings — 12 "hold (tie)" and 13
# "note-form rest" — are NOT here: FFT writes zero of either (ADR-0085 18c §1), they draw
# as Hold / Rest chips on the time lane where they already exist, and offering them here
# would let an author write a second rest form the moment the studio settled on `0x80`.
const _NOTE_KEY_LABELS := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# The two opcodes whose param IS time (`0x80 Rest`, `0x81 Fermata`) — mirrors
# FedsOpcodeCatalog.TIME_CARRYING, which this file does not otherwise depend on.
const _TIME_CARRYING := [0x80, 0x81]


## The pre-projected view for this target's pair, or {} when the score carries none.
static func _view(target: Dictionary, score) -> Dictionary:
	if score == null:
		return {}
	var pair_idx := int(target.get("ref", {}).get("pair_idx", -1))
	for v in score.get("feds_pairs", []):
		if v is Dictionary and int(v.get("pair_idx", -1)) == pair_idx and bool(v.get("valid", false)):
			return v
	return {}


## Header: pair identity, then the provenance links (ADR-0073 reverse-nav) back to
## every shared container that resolves into this pair — the blast radius an author
## must see before editing shared sound content.
static func header(target: Dictionary, _effect_data, score) -> Array:
	var view := _view(target, score)
	if view.is_empty():
		return []
	var rows: Array = [
		{"label": "Pair", "value": "FEDS pair %d · %d ticks (%s s)" % [
			int(view.get("pair_idx", -1)), int(view.get("total_ticks", 0)),
			String.num(_pair_seconds(view), 3).pad_decimals(3)]},
	]
	var used: Array = view.get("used_by_containers", [])
	if used.is_empty():
		rows.append({"label": "Used by", "value": "no container (orphan pair)"})
	for u in used:
		var idx := int(u.get("index", -1))
		var n := int(u.get("used_by", 0))
		rows.append({
			"label": "Used by",
			"link": {
				"label": "container %d → %d trigger%s" % [idx, n, "" if n == 1 else "s"],
				"target": _Target.container(idx),
			},
		})
	return rows


## Sections: the pair overview, plus ONE Event section scoped to the view's
## `selected` annotation ({track, event_index}, set by the page from the lane
## panel's selection). The panel IS the event listing (ADR-0085 2026-08-11
## amendment) — no per-track event dump rides the inspector grid, so the grid's
## multi-column wrap can never garble the stream's byte order. A missing or
## stale selection renders the overview alone.
static func sections(target: Dictionary, _effect_data, score) -> Array:
	var view := _view(target, score)
	if view.is_empty():
		return []
	# The Event section LEADS when present — the clicked event's cells must be
	# visible even when the inspector band is short (its overflow scrolls).
	var out: Array = []
	var ev := _event_section(view)
	if not ev.is_empty():
		out.append(ev)
	out.append(_overview_section(view))
	return out


## The scoped Event section for the view's selection, or {} when nothing valid
## is selected. Reuses the ring cells (_event_fields/_note_fields) unchanged —
## same shapes, same blob-absolute field_refs.
static func _event_section(view: Dictionary) -> Dictionary:
	var sel: Dictionary = view.get("selected", {})
	if sel.is_empty():
		return {}
	var tracks: Array = view.get("tracks", [])
	var t := int(sel.get("track", -1))
	if t < 0 or t >= tracks.size():
		return {}
	var track: Dictionary = tracks[t]
	var ei := int(sel.get("event_index", -1))
	var event: Dictionary = {}
	for n in track.get("notes", []):
		if int(n.get("event_index", -1)) == ei:
			event = n
	for c in track.get("commands", []):
		if int(c.get("event_index", -1)) == ei:
			event = c
	if event.is_empty():
		return {}
	var letter: String = _TRACK_LETTERS[t] if t < _TRACK_LETTERS.size() else str(t)
	var label := str(event.get("label", ""))
	var tick := int(event.get("start_tick", event.get("tick", 0)))
	return {
		"title": "Event — %s @ tick %d (Track %s)" % [label, tick, letter],
		"fields": _event_fields(event, int(view.get("pair_idx", -1)),
				_active_instrument(track, ei), int(view.get("audition_override", -1))),
	}


## The active instrument for the selected event = the last 0xAC's value at an
## event_index STRICTLY LESS than the selection's, in THIS track only (per-TrackState
## runtime state, ADR-0085 2026-08-12 — never crossing the pair's two voices). −1 when
## no 0xAC precedes it (nothing to condition on). The commands ride in stream order,
## so we take the greatest qualifying event_index.
static func _active_instrument(track: Dictionary, event_index: int) -> int:
	var inst := -1
	var best := -1
	for c in track.get("commands", []):
		if int(c.get("opcode", -1)) != _INSTRUMENT_OP:
			continue
		var ei := int(c.get("event_index", -1))
		if ei < event_index and ei > best:
			var params: Array = c.get("params", [])
			if not params.is_empty():
				best = ei
				inst = int(params[0])
	return inst


static func _overview_section(view: Dictionary) -> Dictionary:
	var fields: Array = [
		# The pair's visual surface is the PAGE-LEVEL lane panel (FedsPairLanePanel,
		# ADR-0085 2026-08-11 amendment) — no strip field rides the inspector grid.
		_Fields.const_field("Axis", "%d ticks · %s s at the pair's own tempo" % [
			int(view.get("total_ticks", 0)),
			String.num(_pair_seconds(view), 3).pad_decimals(3)],
			"The pair plays on its OWN tick clock (the SPU side), not effect frames — " +
			"the seconds tell integrates the tempo map (120 BPM fallback) so you can " +
			"relate it to the timeline's ghost bar."),
		# Manual Audition (the ADR rejects auto-replay-on-edit): one pair IS one resolved
		# sound id (pair_idx + 1), so this rides the existing "audition_sound" host seam
		# — same ghost-queue holdoff as the container's ▶ previews.
		{
			"name": "Audition",
			"shape": "action",
			"label": "▶ Audition pair",
			"tooltip": "Play this pair once through the SFX engine (both tracks), " +
				"exactly as a trigger resolving to it would.",
			"action": {"kind": "audition_sound", "id": int(view.get("pair_idx", -1)) + 1},
		},
		# The no-op prune A/B (ADR-0085 amendment 2026-08-12), seated right beside the plain
		# Audition so the two are an obvious ear A/B: play the SAME pair with every no-op
		# opcode pruned (muted notes → rests, inert deleted), and drop the measured Δ + the
		# joint-waveform overlay onto the lane panel. Proof-only — nothing is saved.
		{
			"name": "Audition pruned",
			"shape": "action",
			"label": "▶ Audition (no-ops pruned)",
			"tooltip": "Play this pair with every opcode the classifier calls a no-op removed, " +
				"and A/B its energy against the baseline — hear + see whether the no-ops " +
				"really do nothing.",
			"action": {"kind": "audition_pruned", "pair_idx": int(view.get("pair_idx", -1))},
		},
		# Prune-for-real (ADR-0085 2026-08-13): the REAL delete, beside the proof-only audition.
		# Rewrites this pair's two tracks with every no-op opcode gone and swaps the smaller,
		# byte-exact bank into the live model (undoable; persisted on the next Save). Destructive,
		# so it is clearly labelled and separated from the play buttons above.
		{
			"name": "Delete no-ops",
			"shape": "action",
			"label": "🗑 Delete no-ops (permanent)",
			"tooltip": "DELETE every opcode the classifier calls a no-op from this pair " +
				"(muted notes → equal-length rests, inert opcodes removed) and write the smaller " +
				"stream back. Undoable (Ctrl+Z); saved to E###.BIN on the next Save.",
			"action": {"kind": "prune_noops_commit", "pair_idx": int(view.get("pair_idx", -1))},
		},
	]
	return {"title": "Pair", "fields": fields}


## One event's inspector cells — the ADR's three rings, all SAME-SIZE byte patches
## through the sound_def choke point. Structure placement (EndBar/Loop/Coda/
## RepeatBreak), unknowns, and the note-form hold/rest chips stay read-only const.
static func _event_fields(r: Dictionary, pair_idx: int, active_instrument: int = -1,
		audition_override: int = -1) -> Array:
	if r.has("relative_key"):
		return _note_fields(r, pair_idx, audition_override)
	var label := str(r.get("label", ""))
	var op := int(r.get("opcode", -1))
	var params: Array = r.get("params", [])
	# Unknown opcodes render read-only raw ("preserved verbatim" — the camera
	# Param/Flags precedent). This includes param-count-known Unknown_XX extras.
	if label.begins_with("Unknown_") or op < 0:
		var parts: Array = []
		for p in params:
			parts.append(str(p))
		return [_Fields.const_field(label,
				"%s (unknown opcode — preserved verbatim)" % (", ".join(parts) if not parts.is_empty() else "—"),
				"Not yet RE'd; the byte(s) are kept exactly as authored.")]
	# Ring 3: paired 0-param toggles as same-shape opcode substitutions.
	if params.is_empty() and _TOGGLE_PAIRS.has(op):
		return [_toggle_field(r, op, pair_idx)]
	# The two TIME-CARRYING opcodes are TELLS, not cells (ADR-0085 2026-08-19c). Their param
	# is a tick count: same-size, but not same-TIME, so retyping one slides every later event
	# in this voice while the pair's other voice stays put. That is §6's costume, worn by the
	# other two forms that carry time — closed here the same way, and refused at the encoder
	# too. The verbs that move these numbers lawfully are the drag (spends silence against a
	# wall) and the outro (the one place new time can go).
	if op in _TIME_CARRYING and not params.is_empty():
		return [_time_carrying_tell(op, params)]
	# Ring 1: every parameterized opcode's param bytes as int cells (Repeat's COUNT
	# included — only its placement is structural).
	if not params.is_empty():
		return _param_fields(r, label, params, pair_idx, active_instrument)
	# Param-less structure / flow chips (EndBar, Loop, Coda, NOP…): placement is the
	# deferred compile path — read-only const.
	return [_Fields.const_field(label, "—", "@ tick %d — placement is structural (not editable in v1)" % int(r.get("tick", 0)))]


## Ring 2: velocity (own byte, capped 127 — 0x80+ would BECOME an opcode), key +
## duration sharing the data byte (key*19 + delta_idx), duration as an enum over
## the 18 storable table values — the snap made explicit — or a free 0–255 int
## where the note already uses the explicit-duration byte form.
static func _note_fields(r: Dictionary, pair_idx: int, audition_override: int = -1) -> Array:
	var offset := int(r.get("offset", -1))
	var head := _Fields.const_field("Note", "%s · tick %d · %s s" % [str(r.get("label", "")),
			int(r.get("start_tick", 0)),
			String.num(float(r.get("start_seconds", 0.0)), 3).pad_decimals(3)],
			"A note bar on the pair's tick axis. The cells below edit its bytes in place.")
	var vel := {
		"name": "Note velocity",
		"shape": "edit",
		"editor": "int",
		"type": "u8",
		"min": 0,
		"max": 127,
		"value": int(r.get("velocity", 0)),
		"tooltip": "The note's first byte (0–127). 128+ would turn the byte into an " +
			"opcode — a structural change — so the range is capped.",
		"field_ref": _ref("byte", offset, pair_idx),
	}
	var key_choices: Array = []
	for k in range(_NOTE_KEY_LABELS.size()):
		key_choices.append({"value": k, "label": _NOTE_KEY_LABELS[k]})
	var key := {
		"name": "Note key",
		"shape": "edit",
		"editor": "enum",
		"value": int(r.get("relative_key", 0)),
		"choices": key_choices,
		"tooltip": "Key within the current octave (the data byte's upper field — " +
			"key*19 + duration index), C..B. Octave comes from the Octave opcodes. " +
			"The byte can also encode a tie or a note-form rest; FFT writes neither, " +
			"so the studio reads those and never writes them.",
		"field_ref": _ref("note_key", offset + 1, pair_idx),
	}
	var out: Array = [head, vel, key]
	out.append(_note_duration_tell(r))
	# The AUDITION CONSOLE (ADR-0085 2026-08-13): a transient override dropdown + the
	# three live-SPU buttons, on the same note chip that carries the real pitch/duration.
	out.append_array(_audition_console(r, audition_override))
	return out


## Duration is a TELL, not a cell (ADR-0085 amendment 2026-08-19 §6). Changing a span's
## length is the ONE verb that moves a track's clock — 18c §7 named it, transferred its
## rule from ADR-0095 (a note grows by eating the run of rests after it; the next note
## clamps) and **parked its encoding**. This row shipped as a bounded enum over the 18
## table values, and for the explicit-byte form as a free 0-255 int, so the parked verb
## was reachable through a costume: a "parameter" that silently re-timed everything after
## it, with no ripple rule and no tell.
##
## The row keeps SHOWING the length — hiding it would trade one dishonesty for another —
## and names where the verb went. The other two time verbs (delete = rest it, un-rest =
## sound it) both hold the clock still, so nothing about editing what SOUNDS is lost.
static func _note_duration_tell(r: Dictionary) -> Dictionary:
	var ticks := int(r.get("duration_ticks", 0))
	var value := "%d ticks · %s s" % [ticks,
			String.num(float(r.get("duration_seconds", 0.0)), 3).pad_decimals(3)]
	var ext := int(r.get("fermata_extension_ticks", 0))
	if ext > 0:
		value += "  (+%d held — the span is %d)" % [ext, ticks + ext]
	var form := "its own third byte, freely 0-255" if bool(r.get("explicit_duration", false)) \
			else "an index into the shared 18-value delta-time table"
	return _Fields.const_field("Note duration", value,
			("Stored as %s. READ-ONLY as a typed number: a span's length is not a bounded " +
			"parameter, it is a re-tiling. Drag the bar's end grip to resize it — the note " +
			"grows by eating the rest beside it and clamps at the next wall (ADR-0085 19b " +
			"§3), which is why only 302 of the corpus's 6234 notes can move at all. Delete " +
			"(rest it) and the un-rest change what sounds without moving the clock; the " +
			"outro is where new time comes from.") % form)


## A `0x80 Rest` / `0x81 Fermata` tick count, said out loud and not offered as an edit
## (ADR-0085 2026-08-19c). The row NAMES where each of its two lawful verbs lives, the way
## the note-duration tell does — a dead read-only row teaches nothing.
static func _time_carrying_tell(op: int, params: Array) -> Dictionary:
	var ticks: int = int(params[0]) if params.size() > 0 else 0
	var beats := "%s beat" % String.num(float(ticks) / float(_SMD.PPQ), 2).pad_decimals(2)
	var is_rest := op == 0x80
	return _Fields.const_field("Rest (ticks)" if is_rest else "Hold extra (ticks)",
			"%d ticks · %ss" % [ticks, beats],
			("READ-ONLY: this byte is a tick count, so retyping it re-times every later event " +
			"in THIS voice and leaves the pair's other voice where it was. %s " +
			"To put NEW time in the track, extend its outro — the silence before the EndBar, " +
			"which is the one place a write moves no authored event's firing tick.")
			% ("Drag the bar's end or body to spend this silence against the notes around it "
				+ "(ADR-0085 19b §3), or sound it outright with the un-rest." if is_rest
				else "It extends the note it follows; drag that note's end grip to re-time the "
				+ "span, or delete the span to rest it."))


## The note-chip audition console (ADR-0085 2026-08-13 amendment): built on the existing
## inspector seams — a value_detail-carrying `enum` (the transient "Audition as" override,
## routed through a NON-writing "audition" channel so it never touches E###.BIN) and three
## `action` buttons (Hear-held / Tail-only / Stop). The dropdown DRIVES both buttons: the
## disabled state + tells come from the PURE FedsNoteAudition builder keyed on the EFFECTIVE
## instrument (the transient override when set, else the note's running instrument), so
## overriding onto a silent / one-shot sample re-gates the buttons live (an inaudible press
## never reads as broken). The real pitch and duration ride each action dict; `default_instrument`
## is always the running instrument (the page resolves the same override at press time).
static func _audition_console(r: Dictionary, audition_override: int = -1) -> Array:
	var running: int = int(r.get("active_instrument", -1))
	if running < 0:
		running = 0   # no in-track 0xAC yet → default to slot 0 (the channel default)
	# The dropdown default + all gating follow the EFFECTIVE instrument (override wins).
	var effective: int = audition_override if audition_override >= 0 else running
	var params: Dictionary = _Audition.build(r, effective)
	var inst_desc: Dictionary = _Semantics.descriptor(_INSTRUMENT_OP, 0)
	# The note payload every audition action carries (real pitch + real duration).
	var note_payload: Dictionary = {
		"default_instrument": running,
		"relative_key": int(r.get("relative_key", 0)),
		"octave": int(r.get("octave", 4)),
		"duration_ticks": int(r.get("duration_ticks", 0)),
		"duration_seconds": float(r.get("duration_seconds", 0.0)),
		"velocity": int(r.get("velocity", 0)),
	}
	var hold: Dictionary = params.get("hold", {})
	var out: Array = [
		{
			"name": "Audition as",
			"shape": "edit",
			"editor": "enum",
			"value": effective,
			"choices": inst_desc.get("choices", []),
			"value_detail": inst_desc.get("value_detail"),
			"tooltip": "A TRANSIENT instrument override for auditioning this note — hear it as " +
				"another sample without editing. NEVER written to E###.BIN. Drives both buttons below.",
			"field_ref": {"channel": "audition", "kind": "instrument"},
		},
		{
			"name": "Hear this note",
			"shape": "action",
			"hold": true,
			"label": "▶ Hear this note (hold)",
			"disabled": not bool(params.get("hold_enabled", false)),
			"disabled_reason": str(params.get("disabled_reason", "")),
			"hint": "hold to sound · release to stop",
			"tooltip": "Press and HOLD to sound this note at its real pitch; release to stop. " +
				"Hold it to hear the sample SUSTAIN (its tail loops for as long as you hold).",
			"action": _merge({"kind": "audition_note_hold"}, note_payload),
			"release_action": {"kind": "audition_note_release"},
		},
		{
			"name": "Tail only",
			"shape": "action",
			"hold": true,
			"label": str(params.get("tail_label", "▶ Tail only")) + " (hold)",
			"disabled": not bool(params.get("tail_enabled", false)),
			"disabled_reason": _tail_disabled_reason(params),
			# A defaulted (heuristic) loop point is the load-bearing honesty tell; otherwise the
			# plain hold hint. (Shown only when enabled — the inspector prefers disabled_reason.)
			"hint": str(params.get("tail_hint")) if str(params.get("tail_hint", "")) != ""
				else "hold to ring the loop · release to stop",
			"tooltip": "Press and HOLD to sound ONLY the looping tail (from the loop point, " +
				"skipping the attack) — the pure ring; release to stop. Disabled for a one-shot sample.",
			"action": _merge({"kind": "audition_note_tail"}, note_payload),
			"release_action": {"kind": "audition_note_release"},
		},
	]
	return out


## The tail button's dim reason WHEN disabled: the silent tell wins; otherwise a one-shot
## has no looping tail to isolate. "" when the tail is enabled (a defaulted-loop sustain
## rides the separate `tail_hint`, not a disabled reason).
static func _tail_disabled_reason(params: Dictionary) -> String:
	if bool(params.get("tail_enabled", false)):
		return ""
	if bool(params.get("silent", false)):
		return str(params.get("disabled_reason", ""))
	return "One-shot — no looping tail to isolate"


static func _merge(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate()
	out.merge(extra)
	return out


static func _delta_idx_of(ticks: int) -> int:
	for idx in range(1, _SMD.DELTA_TIME_TABLE.size()):
		if _SMD.DELTA_TIME_TABLE[idx] == ticks:
			return idx
	return 1


static func _toggle_field(r: Dictionary, op: int, pair_idx: int) -> Dictionary:
	var pair: Array = _TOGGLE_PAIRS[op]
	var choices: Array = []
	for v in pair[1]:
		choices.append({"value": v, "label": _opcode_name(v)})
	return {
		"name": str(pair[0]),
		"shape": "edit",
		"editor": "enum",
		"value": op,
		"choices": choices,
		"tooltip": "A same-shape opcode substitution (both take no params), so the " +
			"swap is a 1-byte patch — structurally free. @ tick %d" % int(r.get("tick", 0)),
		"field_ref": _ref("byte", int(r.get("offset", -1)), pair_idx),
	}


## Param cells consult the semantics layer (FedsParamSemantics): a curated param
## gets its author label, range, and — where a real human unit exists — a unit
## (ADSR ms, tempo BPM) or a named enum (Instrument). The write path is IDENTICAL
## either way: the same field_ref addressing the same raw byte. Uncurated params
## keep the honest raw-byte cell.
static func _param_fields(r: Dictionary, label: String, params: Array, pair_idx: int,
		active_instrument: int = -1) -> Array:
	var offset := int(r.get("offset", -1))
	var op := int(r.get("opcode", -1))
	# 0xD3 PitchBend_Add_16bit's two bytes ARE one signed 16-bit value (high<<8|low) —
	# ONE s16 word cell, fanned through the atomic word write, not two byte cells.
	if op == 0xD3 and params.size() >= 2:
		return [_word_field(r, label, params, pair_idx, active_instrument)]
	var out: Array = []
	for i in range(params.size()):
		var d: Dictionary = _Semantics.descriptor(op, i)
		# Author label, confident-else-honest-generic — a curated label, else a name
		# that says what the byte touches (the opcode), NEVER the opaque "p2" (ADR §1).
		var generic := label if i == 0 else "%s param %d" % [label, i + 1]
		var cell := {
			"name": str(d.get("label", generic)),
			"shape": "edit",
			"editor": str(d.get("editor", "int")),
			# Signedness is a shared-table display transform (ADR §2): _int_cell sign-
			# extends the seed and masks the fanned write; the byte writer stays raw.
			"type": _Semantics.storage_type(op, i),
			"value": int(params[i]),
			"tooltip": str(d.get("tooltip",
					"Raw param byte %d of %s — patched in place." % [i + 1, label])) +
				" (%s @ tick %d)" % [label, int(r.get("tick", 0))],
			"field_ref": _ref("byte", offset + 1 + i, pair_idx),
		}
		if d.has("choices"):
			cell["choices"] = d["choices"]
		if d.has("min"):
			cell["min"] = int(d["min"])
		if d.has("max"):
			cell["max"] = int(d["max"])
		if d.has("unit"):
			cell["unit"] = d["unit"]
		_attach_range(cell, op, i, active_instrument)
		out.append(cell)
	return out


## The empirical usage range — the honest substitute for a physical unit (ADR §4) —
## attaches ONLY where no unit or enum already grounds the value (else redundant noise).
## When an instrument is active (ADR-0085 2026-08-12) the cell ALSO carries a second,
## instrument-conditional range: a populated bucket {id, name, min, max, median, n}, or
## the explicit empty-bucket marker {id, name, empty} when the corpus has zero samples
## of this param under that instrument (states c and b). No instrument → global only.
static func _attach_range(cell: Dictionary, op: int, param_index: int,
		active_instrument: int = -1) -> void:
	if cell.has("unit") or cell.has("choices"):
		return
	var rng: Dictionary = _Semantics.usage_range(op, param_index)
	if rng.is_empty():
		return
	cell["range"] = rng
	if active_instrument < 0:
		return
	var ri := {"id": active_instrument, "name": _instrument_label(active_instrument)}
	var cond: Dictionary = _Semantics.usage_range(op, param_index, active_instrument)
	if cond.is_empty():
		ri["empty"] = true
	else:
		ri.merge(cond)
	cell["range_instrument"] = ri


## The active-instrument display label: the DAW picker name plus the raw id in
## parentheses ("Timpani (64)"), or a bare "id N" when the id is unnamed.
static func _instrument_label(id: int) -> String:
	if _InstrumentNames.NAMES.has(id):
		return "%s (%d)" % [str(_InstrumentNames.NAMES[id]), id]
	return "id %d" % id


## The single s16 cell for a genuine 16-bit param (0xD3): seeded to the signed word
## reconstructed from its two bytes, addressing the high byte through the atomic "s16"
## write. Consults the semantics layer for a curated label/unit exactly like _param_fields.
static func _word_field(r: Dictionary, label: String, params: Array, pair_idx: int,
		active_instrument: int = -1) -> Dictionary:
	var offset := int(r.get("offset", -1))
	var d: Dictionary = _Semantics.descriptor(int(r.get("opcode", -1)), 0)
	var cell := {
		"name": str(d.get("label", label)),
		"shape": "edit",
		"editor": "int",
		"type": "s16",
		"value": _s16(int(params[0]), int(params[1])),
		"tooltip": str(d.get("tooltip",
				"A signed 16-bit pitch-bend value (high<<8 | low) added to the channel " +
				"pitch — edited as one atomic word.")) +
			" (%s @ tick %d)" % [label, int(r.get("tick", 0))],
		"field_ref": _ref("s16", offset + 1, pair_idx),
	}
	if d.has("min"):
		cell["min"] = int(d["min"])
	if d.has("max"):
		cell["max"] = int(d["max"])
	if d.has("unit"):
		cell["unit"] = d["unit"]
	_attach_range(cell, int(r.get("opcode", -1)), 0, active_instrument)
	return cell


## Two's-complement reconstruction of a signed 16-bit word from its two stored bytes.
static func _s16(hi: int, lo: int) -> int:
	var v: int = ((hi & 0xFF) << 8) | (lo & 0xFF)
	return v - 65536 if v >= 32768 else v


static func _ref(kind: String, offset: int, pair_idx: int) -> Dictionary:
	return {"channel": "sound_def", "kind": kind, "offset": offset, "pair_idx": pair_idx}


static func _opcode_name(op: int) -> String:
	if _SMD.OPCODE_INFO.has(op):
		return _SMD.OPCODE_INFO[op][0]
	return "Unknown_%02X" % op


static func _pair_seconds(view: Dictionary) -> float:
	var secs := 0.0
	for t in view.get("tracks", []):
		secs = maxf(secs, float(t.get("end_seconds", 0.0)))
	return secs
