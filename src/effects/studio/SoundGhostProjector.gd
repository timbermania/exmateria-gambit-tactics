extends RefCounted
## The ADR-0085 tempo-map projection — the read-only "ghost bar" seam.
##
## A sound TRIGGER on the effect timeline fires a FEDS pair that then plays on the
## SPU's own clock (CONTEXT.md *Trigger*). Its real length lives one domain over, in
## the FEDS opcode/tick stream. This projector carries that length across the seam:
##
##     FEDS ticks --(tempo map)--> real SECONDS --(effect frame rate)--> FRAMES
##
## The tempo map is INTEGRATED segment-by-segment (a TEMPO opcode changes the rate
## only for the ticks that follow it), NEVER a single scalar scale over the stream:
## commensurable ≠ phase-locked (ADR-0085 clock-reconciliation). In practice FEDS
## pairs carry no authored tempo and default to 120 BPM (feds_bank.gd), but honoring
## inline TEMPO keeps the projection honest.
##
## Read-only: nothing here mutates audio or effect data. No class_name (ADR-0004) —
## instantiate/reference by path.

const SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")
const Resolver = preload("res://addons/exmateria_sound/runtime/effect_sound_resolver.gd")
const EffectScoreModel = preload("res://src/effects/studio/EffectScoreModel.gd")
const FedsPairModel = preload("res://src/effects/studio/FedsPairModel.gd")
const FedsOpcodeVerdicts = preload("res://src/effects/studio/FedsOpcodeVerdicts.gd")
const FedsNoOpPrune = preload("res://src/effects/studio/FedsNoOpPrune.gd")

const PPQ := 48             # pulses per quarter note (matches SoundOpcodes.PPQ)
const DEFAULT_BPM := 120.0  # FEDS pairs carry no authored tempo (feds_bank.gd:221)
const EFFECT_FPS := 30.0    # EffectTimeline.PHYSICS_TIMESTEP = 1/30

# Render-to-silence policy for the ghost LENGTH (ADR-0085): a sound's real length is
# how long its rendered PCM stays audible, not a tick sum. A frame's RMS at/above
# SILENCE_RMS is audible (matches EffectSoundCaptureTest); the render stops early once
# SILENCE_QUIET_FRAMES consecutive frames fall below it (the tail is trimmed to the
# last audible frame), and never renders past MAX_RENDER_FRAMES (a 30 s safety cap).
const SILENCE_RMS := 0.004
const SILENCE_QUIET_FRAMES := 20
const MAX_RENDER_FRAMES := 900

# The ABSOLUTE "silent in isolation" threshold (ADR-0085 2026-08-12 §6, DISPLAY-ONLY).
# The shared-peak normalize dresses a genuinely-silent track's noise floor UP to full
# height (E001 track A's raw peak 0.0117 rendered as a 0.25 swell), so an author reading
# the normalized band alone is misled. A track whose RAW (un-normalized) peak stays under
# this reads "silent in isolation". Sits BETWEEN E001's empty-instrument floor (track A
# raw peak 0.0117 — silent) and its quiet carrier (track B raw peak 0.0465 — the sound),
# so the marker separates the silent voice from the sounding one instead of flagging both.
# NEVER wired into the opcode verdict (which is decided statically off the opcode stream).
const ABSOLUTE_QUIET := 0.035

# SMD control opcodes this projection reads for timing.
const OP_REST := 0x80
const OP_TEMPO := 0xA0


## Seconds occupied by one tick at `bpm`. A quarter note (PPQ ticks) lasts
## 60/bpm seconds, so one tick is 60/(bpm*PPQ). Falls back to the default tempo
## for a non-positive bpm.
static func seconds_per_tick(bpm: float) -> float:
	if bpm <= 0.0:
		bpm = DEFAULT_BPM
	return 60.0 / (bpm * float(PPQ))


## Real seconds one decoded track occupies, integrating tempo as it goes. Note and
## rest ticks accrue at the CURRENT tempo; a TEMPO opcode retunes the rate for the
## ticks that follow it. Opcodes that consume no time (most control opcodes) add
## nothing.
static func track_seconds(events: Array) -> float:
	var bpm := DEFAULT_BPM
	var secs := 0.0
	for e in events:
		if e is SMD.NoteEvent:
			secs += float(e.delta_time) * seconds_per_tick(bpm)
		elif e is SMD.OpcodeEvent:
			match e.opcode:
				OP_TEMPO:
					if e.params.size() >= 1:
						bpm = SMD.fft_tempo_to_bpm(e.params[0])
				OP_REST:
					if e.params.size() >= 1:
						secs += float(e.params[0]) * seconds_per_tick(bpm)
	return secs


## Real seconds a FEDS pair occupies. Its two tracks play CONCURRENTLY, so the
## pair's length is the longer of the two. 0.0 for a null bank or out-of-range pair.
static func pair_seconds(feds_bank, pair_idx: int) -> float:
	if feds_bank == null or pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		return 0.0
	var pair: Array = feds_bank.get_pair_events(pair_idx)
	return maxf(track_seconds(pair[0]), track_seconds(pair[1]))


## A FEDS pair's length on the effect FRAME axis. Rounds UP so a short but non-zero
## sound still shows at least one frame of ghost; a zero-length pair stays 0.
static func pair_frames(feds_bank, pair_idx: int, fps: float = EFFECT_FPS) -> int:
	return ceili(pair_seconds(feds_bank, pair_idx) * fps)


# Ghost-pip unroll bounds (ADR-0085 TIER-3): pips project note ONSETS, so a
# runaway Repeat must not explode the projection — stop at MAX_PIPS onsets or at
# the 30 s render ceiling (MAX_RENDER_FRAMES), whichever bites first.
const MAX_PIPS := 96


## The pair's note-onset frames (relative to the fire), loops UNROLLED — even
## though the TIER-3 editor keeps them folded (the projection is playback truth,
## the editor is authored truth). Both tracks merge into one sorted, deduped,
## frame-resolution list. Read-only, never a click target; [] for a null bank /
## out-of-range pair. Emulates the sequencer's Repeat/Coda jump (repeat.gd/coda.gd:
## a body plays `count` times total) and integrates tempo as it goes.
static func pair_pips(feds_bank, pair_idx: int, fps: float = EFFECT_FPS) -> Array:
	if feds_bank == null or pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		return []
	var frames := {}
	for t in range(2):
		var ti := pair_idx * 2 + t
		# A STUB track (no EndBar) sounds its FLOW-THROUGH span, not its bounded bytes
		# (ADR-0085 2026-08-14) — so its borrowed onsets are pips too. Read continuously
		# past the boundary when bounded decode never terminates itself.
		# A NULL SLOT (offset 0) is an unused track, not music — never decode the
		# header as bytecode (ADR-0085 2026-08-18). Without this gate the missing
		# EndBar reads as a stub and the flow path walks the feds header.
		if feds_bank.track_offsets[ti] == 0:
			continue
		var events: Array = feds_bank.get_track_events(ti)
		if not _events_have_end_bar(events):
			events = feds_bank.get_track_events_from(ti)
		var bpm := DEFAULT_BPM
		var secs := 0.0
		var loop_stack: Array = []   # [next_event_idx, remaining_jumps]
		var onsets := 0
		var i := 0
		while i < events.size():
			var e = events[i]
			i += 1
			if secs * fps > float(MAX_RENDER_FRAMES) or onsets >= MAX_PIPS:
				break
			if e is SMD.NoteEvent:
				if e.is_note():
					frames[int(round(secs * fps))] = true
					onsets += 1
				secs += float(e.delta_time) * seconds_per_tick(bpm)
			elif e is SMD.OpcodeEvent:
				match e.opcode:
					OP_REST, 0x81:   # Rest adds wait; Fermata extends (both consume time)
						secs += float(e.params[0] if e.params.size() > 0 else 0) \
								* seconds_per_tick(bpm)
					0x98:   # Repeat: body plays `count` times total (count-1 jumps back)
						loop_stack.append([i, (e.params[0] if e.params.size() > 0 else 1) - 1])
					0x99:   # Coda: jump back while the innermost bracket has plays left
						if not loop_stack.is_empty():
							var entry: Array = loop_stack[-1]
							if int(entry[1]) > 0:
								entry[1] = int(entry[1]) - 1
								i = int(entry[0])
							else:
								loop_stack.pop_back()
					OP_TEMPO:
						if e.params.size() > 0:
							bpm = SMD.fft_tempo_to_bpm(e.params[0])
					0x90:
						break
	var out: Array = frames.keys()
	out.sort()
	return out


## Does a decoded event list terminate itself with an EndBar (0x90) opcode? A track
## that does NOT is a stub whose voice flows into the following bytecode.
static func _events_have_end_bar(events: Array) -> bool:
	for e in events:
		if e is SMD.OpcodeEvent and e.opcode == 0x90:
			return true
	return false


## ADR-0085 ANCHOR (authoring-only, no ROM counterpart). A trigger fires at the
## onset; the audible HIT lands `offset` frames into the sound. The hit draws at
## `fire + offset` on the ghost bar, clamped to the sound's real length [0, ghost] —
## you cannot declare a hit before the onset or past the end. The fire marker and the
## on-disk bytes never move; the offset is metadata carried in the authored JSON.
static func anchor_hit_frame(fire: int, offset: int, ghost: int) -> int:
	return fire + clampi(offset, 0, maxi(ghost, 0))


## The drag inverse: a hit position (frame) on the ghost bar becomes the offset from
## the fire marker, clamped into the ghost length. Round-trips with anchor_hit_frame
## for an in-range offset.
static func anchor_offset_from_frame(frame: int, fire: int, ghost: int) -> int:
	return clampi(frame - fire, 0, maxi(ghost, 0))


## RENDERED SOUND PROJECTION (ADR-0085) — the ghost bar's LENGTH and its energy-
## envelope climax cue both come from the ACTUALLY RENDERED sound, not a tick sum. A
## FEDS pair is synthesised offline through the real SPU (deterministic capture, no
## speakers); each timeline frame's PCM is reduced to one RMS sample. The length is how
## long that render stays AUDIBLE (an SFX is often a short note firing a long one-shot
## sample, so the tick projection below badly under-counts); the envelope is that same
## render, peak-normalised. One render feeds both, so the bar, the swell, and what you
## hear always agree.

## RMS of one rendered PCM frame (interleaved-stereo Int32), reported over digital
## full-scale (32767) so a full-scale frame reads ~1.0. sqrt(mean(sample²)); an empty
## frame is silent (0.0). The full-scale divisor is cosmetic under peak-normalisation
## (it cancels) but keeps a lone frame's RMS a meaningful 0..1 amplitude.
static func frame_rms(sub: PackedInt32Array) -> float:
	var n := sub.size()
	if n == 0:
		return 0.0
	var sum_sq := 0.0
	for s in sub:
		sum_sq += float(s) * float(s)
	return sqrt(sum_sq / float(n)) / 32767.0


## Peak-normalise an envelope: divide every sample by the loudest so the curve fills
## the ghost bar 0..1. The constant render-scale cancels, isolating the SHAPE (where
## the sound swells). A silent (all-zero) envelope is returned unchanged — never a
## divide-by-zero — and length is always preserved.
static func normalize_peak(samples: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for v in samples:
		if v > peak:
			peak = v
	if peak <= 0.0:
		return samples.duplicate()
	var out := PackedFloat32Array()
	out.resize(samples.size())
	for i in range(samples.size()):
		out[i] = samples[i] / peak
	return out


## PER-TRACK ENERGY shared normalization (ADR-0085 amendment 2026-08-12 §3): the two
## tracks of a pair each render ALONE (single_track), then BOTH raw RMS envelopes are
## scaled by the PAIR's peak — max(peak_a, peak_b), NOT each track's own — so a silent
## stub reads FLAT and the carrying track reads TALL, answering "which track makes the
## sound?" at a glance. Ratios are preserved (the shared divisor cancels), so each
## band keeps its own shape. An all-silent pair is returned unchanged (never a
## divide-by-zero). Lengths are always preserved. Returns [shared_a, shared_b].
static func normalize_pair_shared(raw_a: PackedFloat32Array,
		raw_b: PackedFloat32Array) -> Array:
	var peak := 0.0
	for v in raw_a:
		peak = maxf(peak, float(v))
	for v in raw_b:
		peak = maxf(peak, float(v))
	if peak <= 0.0:
		return [raw_a.duplicate(), raw_b.duplicate()]
	return [_scale(raw_a, peak), _scale(raw_b, peak)]


static func _scale(samples: PackedFloat32Array, divisor: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples.size())
	for i in range(samples.size()):
		out[i] = samples[i] / divisor
	return out


## The audible length of a raw (un-normalised) per-frame RMS render: the last frame
## at/above `silence`, plus one. A trailing quiet tail is trimmed; a never-audible
## render is length 0. Interior quiet gaps do NOT end the sound — only the final drop
## to silence bounds it. Pure, so the render-loop's stop rule is oracle-testable.
static func audible_length(rms: PackedFloat32Array, silence: float) -> int:
	var last := -1
	for i in range(rms.size()):
		if rms[i] >= silence:
			last = i
	return last + 1


## Render one FEDS pair OFFLINE to its natural silence, returning BOTH its length in
## frames (how long it stays audible) and its peak-normalised per-frame RMS envelope
## (length == that). The pair is synthesised through the real SPU via `engine`
## (ExMateriaEffectSfx); the caller MUST have set `engine.capture_mode = true` so the
## producer is parked and render_subs is deterministic. The loop stops once `quiet_run`
## consecutive frames fall below `silence` (or at `cap`); the trailing quiet is trimmed
## off the length + envelope. Isolated with panic() on both ends so a render never
## bleeds into (or from) live playback. length 0 / empty envelope for a bad pair.
static func render_pair(engine, feds_bank, pair_idx: int, sound_id: int,
		subs_per_frame: int = 8, silence: float = SILENCE_RMS,
		quiet_run: int = SILENCE_QUIET_FRAMES, cap: int = MAX_RENDER_FRAMES,
		single_track: int = -1, normalized: bool = true, trim: bool = true) -> Dictionary:
	# `single_track` (0/1) renders ONE track of the pair alone (ADR-0085 §3 per-track
	# energy); `normalized` false returns the RAW per-frame RMS (the shared-peak
	# normalize is applied across BOTH tracks upstream, so the isolated renders must
	# stay un-normalised here). Defaults reproduce the original whole-pair behaviour.
	var empty := {"length": 0, "energy": PackedFloat32Array()}
	if engine == null or feds_bank == null:
		return empty
	if pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		return empty
	engine.panic()   # isolate from any prior cast before we render this pair
	var token: int = engine.begin_effect()
	if not engine.play_pair(token, feds_bank, pair_idx, sound_id, single_track):
		engine.end_effect(token)
		engine.panic()
		return empty
	var raw := PackedFloat32Array()
	var quiet := 0
	var f := 0
	while f < cap and quiet < quiet_run:
		var rms := frame_rms(engine.render_subs(subs_per_frame))
		raw.append(rms)
		if rms >= silence:
			quiet = 0
		else:
			quiet += 1
		f += 1
	engine.end_effect(token)
	engine.panic()   # leave the engine clean for the next render / live playback
	var length := audible_length(raw, silence)
	# `trim` false keeps the FULL render window (untrimmed) so a baseline-vs-pruned diff
	# compares on a common length — per-render trimming would drop the very tail where the
	# baseline still sounds but the pruned render has gone silent (ADR-0085 no-op A/B §4).
	var env := raw.slice(0, length) if trim else raw
	return {"length": length, "energy": normalize_peak(env) if normalized else env}


## The two per-track energy envelopes for a pair (ADR-0085 §3): render track A alone
## and track B alone (single_track), then SHARE-normalize both by the pair's peak so a
## silent stub reads flat and the carrier tall. ~2 offline renders. Returns
## {a: PackedFloat32Array, b: PackedFloat32Array} — {} tracks for a bad pair. The
## caller MUST hold engine.capture_mode = true (as render_pair requires).
static func render_track_energies(engine, feds_bank, pair_idx: int, sound_id: int,
		subs_per_frame: int = 8) -> Dictionary:
	var ra := render_pair(engine, feds_bank, pair_idx, sound_id, subs_per_frame,
			SILENCE_RMS, SILENCE_QUIET_FRAMES, MAX_RENDER_FRAMES, 0, false)
	var rb := render_pair(engine, feds_bank, pair_idx, sound_id, subs_per_frame,
			SILENCE_RMS, SILENCE_QUIET_FRAMES, MAX_RENDER_FRAMES, 1, false)
	var shared := normalize_pair_shared(ra["energy"], rb["energy"])
	# Carry each track's ABSOLUTE raw peak (§6, display-only): the shared-normalize
	# cancels amplitude, so a silent track's floor would otherwise look like a swell.
	return {
		"a": shared[0], "b": shared[1],
		"a_peak": raw_peak(ra["energy"]), "b_peak": raw_peak(rb["energy"]),
	}


## The loudest RAW per-frame RMS sample of an un-normalized envelope — a track's
## absolute amplitude in isolation (0.0 for an empty envelope).
static func raw_peak(samples: PackedFloat32Array) -> float:
	var peak := 0.0
	for v in samples:
		peak = maxf(peak, float(v))
	return peak


## Does a track's raw peak read "silent in isolation" (§6, DISPLAY-ONLY)? True when the
## absolute amplitude never crosses ABSOLUTE_QUIET — the picture's honesty marker, never
## an input to the opcode verdict (which is decided statically off the opcode stream).
static func is_silent_in_isolation(peak: float) -> bool:
	return peak < ABSOLUTE_QUIET


## Build the studio's sound projection: for every DISTINCT firing sound_id in the
## effect's tracks, render its pair once and record both its rendered ghost LENGTH and
## its energy envelope. Returns {"ghost": {sid→frames}, "energy": {sid→samples}} — the
## two maps EffectScoreModel.build consumes, guaranteed consistent (same render feeds
## both). Requires `engine.capture_mode = true`. Skips (id 0/1) never appear.
static func sound_projection(engine, effect_sound: Dictionary, containers_doc: Dictionary,
		feds_bank, subs_per_frame: int = 8) -> Dictionary:
	var ghost: Dictionary = {}
	var energy: Dictionary = {}
	for sid in firing_sound_ids(effect_sound):
		var pair_idx := resolve_pair_idx(containers_doc, sid)
		var r := render_pair(engine, feds_bank, pair_idx, sid, subs_per_frame)
		ghost[sid] = r["length"]
		energy[sid] = r["energy"]
	return {"ghost": ghost, "energy": energy}


## The DISTINCT firing sound_ids (>=2) across every phase/channel of an effect's sound
## tracks, in first-seen order. The set both the tick projection (ghost_map) and the
## render projection (sound_projection) iterate.
static func firing_sound_ids(effect_sound) -> Array:
	var out: Array = []
	if effect_sound == null:
		return out
	for phase in effect_sound.keys():
		var channels = effect_sound[phase]
		if not (channels is Array):
			continue
		for ch in channels:
			if not (ch is Dictionary):
				continue
			var kfs = ch.get("keyframes", [])
			if not (kfs is Array):
				continue
			for kf in kfs:
				var sid: int = int(kf.get("sound_id", 0))
				if EffectScoreModel.sound_id_fires(sid) and not out.has(sid):
					out.append(sid)
	return out


## Follow a timeline sound_id to its FEDS pair index (ADR-0085 chain, ADR-0073
## reference): SoundContainer[sound_id-2] → (mode) → resolved sound_id → pair
## (resolved-1). Uses a FRESH resolver (counter 0), so stateful containers
## (PARITY / TRIPLE_CYCLE) project their FIRST-fire pair — the honest representative
## the ghost bar draws. Returns -1 when the id skips (0/1) or does not resolve.
static func resolve_pair_idx(containers_doc: Dictionary, sound_id: int) -> int:
	if not EffectScoreModel.sound_id_fires(sound_id):
		return -1
	var r = Resolver.from_sound_containers(containers_doc)
	var resolved: int = r.resolve(sound_id - 2, sound_id)
	if resolved < 1:
		return -1
	return resolved - 1


## The ghost length in frames for one timeline sound_id: resolve it to a pair, then
## project that pair's real length. 0 when it skips or has no pair.
static func ghost_frames_for_sound_id(containers_doc: Dictionary, feds_bank,
		sound_id: int, fps: float = EFFECT_FPS) -> int:
	var pair_idx := resolve_pair_idx(containers_doc, sound_id)
	if pair_idx < 0:
		return 0
	return pair_frames(feds_bank, pair_idx, fps)


## Build the {sound_id → ghost frames} map the studio hands to EffectScoreModel.
## Walks every phase/channel of the effect's sound tracks, collects the DISTINCT
## firing sound_ids (>=2), and projects each once. Because a fresh resolver is used
## per id (counter 0), stateful containers contribute their first-fire length.
static func ghost_map(effect_sound: Dictionary, containers_doc: Dictionary,
		feds_bank, fps: float = EFFECT_FPS) -> Dictionary:
	var out: Dictionary = {}
	for sid in firing_sound_ids(effect_sound):
		out[sid] = ghost_frames_for_sound_id(containers_doc, feds_bank, sid, fps)
	return out


## THE NO-OP PRUNE A/B (ADR-0085 amendment 2026-08-12 "active corroboration"). The
## active counterpart to the passive per-track energy band (§3): prune every opcode the
## verdict system calls a no-op, re-render the MIXED pair, and prove the audible output
## did not change. Static classifier stays the source of truth — this experiment TESTS
## it, never FEEDS it. Proof-only: the pruned bank is transient, never saved (§6 rule).

# The a-priori three-tier metric, keyed on the audibility constants already committed
# above — chosen BEFORE any result, never fitted to make a case pass (ADR-0085 §4).
const NOOP_INERT := "inert"      # Δ < SILENCE_RMS  → the no-ops truly do nothing ✓
const NOOP_FAINT := "faint"      # Δ < ABSOLUTE_QUIET → a sub-audible floor leaks ≈
const NOOP_CHANGED := "changed"  # Δ ≥ ABSOLUTE_QUIET → the classifier over-claimed ✗


## Classify a measured Δ into the three a-priori tiers (reusing the SoundGhostProjector
## audibility constants — NOT a new state; `faint` reuses §3's gray-zone tier). The raw
## number is always shown alongside; this only colours it.
static func noop_verdict_tier(delta: float) -> String:
	if delta < SILENCE_RMS:
		return NOOP_INERT
	if delta < ABSOLUTE_QUIET:
		return NOOP_FAINT
	return NOOP_CHANGED


## The Δ between two RAW (un-normalised) per-frame RMS envelopes, compared on a COMMON
## untrimmed length (the shorter is zero-extended — a render that went silent early
## really is ~0 there). Reports `max_abs` (the largest per-frame |Δ| — the sensitive
## "did any frame change" signal that drives the tier) and `peak_delta` (the change in
## overall loudness, |peak(a) − peak(b)|). A bit-identical prune → both 0 exactly.
static func energy_diff(a: PackedFloat32Array, b: PackedFloat32Array) -> Dictionary:
	var n := maxi(a.size(), b.size())
	var max_abs := 0.0
	for i in range(n):
		var va: float = a[i] if i < a.size() else 0.0
		var vb: float = b[i] if i < b.size() else 0.0
		max_abs = maxf(max_abs, absf(va - vb))
	return {
		"max_abs": max_abs,
		"peak_delta": absf(raw_peak(a) - raw_peak(b)),
		"length": n,
	}


## Render the MIXED pair with ONE track's no-ops pruned (ADR-0085 no-op A/B §2: per-track
## skip, mixed measurement, per-track attribution). Builds a TRANSIENT bank whose target
## track is the pruned byte stream — everything else byte-identical — then renders the full
## mix (single_track = -1), un-normalised and UNTRIMMED so the caller can diff it against an
## equally-untrimmed baseline. `prune_track_local` is 0 or 1 (the pair's track A or B). The
## original bank is never mutated; the transient bank is never saved. {length 0, empty} for
## a bad pair / engine. The caller MUST hold engine.capture_mode = true (as render_pair does).
static func render_pair_pruning_noops(engine, feds_bank, pair_idx: int, sound_id: int,
		prune_track_local: int, subs_per_frame: int = 8) -> Dictionary:
	var empty := {"length": 0, "energy": PackedFloat32Array()}
	if engine == null or feds_bank == null:
		return empty
	if pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		return empty
	if prune_track_local != 0 and prune_track_local != 1:
		return empty
	var bank = build_pruned_bank(feds_bank, pair_idx, [prune_track_local])
	if bank == null:
		return empty
	return render_pair(engine, bank, pair_idx, sound_id, subs_per_frame,
			SILENCE_RMS, SILENCE_QUIET_FRAMES, MAX_RENDER_FRAMES, -1, false, false)


## Build a TRANSIENT bank with the given LOCAL tracks' no-ops pruned (0 = track A, 1 =
## track B; default BOTH — the "de-no-op'd" pair the author auditions). Prunes each track
## in turn, re-splicing between so the offset fixups compose. The original bank is never
## mutated; the result is never saved (proof-only). null on a bad pair / splice.
static func build_pruned_bank(feds_bank, pair_idx: int, locals: Array = [0, 1]):
	if feds_bank == null or pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		return null
	var bank = feds_bank
	for lt in locals:
		if lt != 0 and lt != 1:
			continue
		var track_idx: int = pair_idx * 2 + lt
		if bank.track_offsets[track_idx] == 0:
			continue   # null slot — nothing to prune (ADR-0085 2026-08-18)
		var tv: Dictionary = FedsPairModel._track_view(bank, track_idx)
		var vd: Dictionary = FedsOpcodeVerdicts.verdicts(tv)
		var pruned: PackedByteArray = FedsNoOpPrune.prune_track(bank.get_track_bytes(track_idx), vd)
		bank = rebuild_bank_with_track(bank, track_idx, pruned)
		if bank == null:
			return null
	return bank


## The JOINT (mixed-pair) energy waveform — both voices rendered TOGETHER (single_track
## -1), peak-normalised to fill its band. This is the combined "what the pair sounds
## like" envelope the per-track isolated bands (§3) never showed. Returns
## {samples, raw_peak} — {} for a bad pair. The caller holds engine.capture_mode = true.
static func render_pair_mixed_energy(engine, feds_bank, pair_idx: int, sound_id: int,
		subs_per_frame: int = 8) -> Dictionary:
	if engine == null or feds_bank == null:
		return {}
	if pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		return {}
	var r := render_pair(engine, feds_bank, pair_idx, sound_id, subs_per_frame,
			SILENCE_RMS, SILENCE_QUIET_FRAMES, MAX_RENDER_FRAMES, -1, false, false)
	var raw: PackedFloat32Array = r["energy"]
	return {"samples": normalize_peak(raw), "raw_peak": raw_peak(raw)}


## One button press → the whole no-op A/B (ADR-0085 amendment 2026-08-12 §2), in the
## FEWEST renders: the MIXED baseline is rendered ONCE and reused for every diff. Then each
## track pruned alone (attribution) and BOTH tracks pruned (the joint overlay + what the
## author auditions) — 4 renders total. Returns
##   {0: tell, 1: tell, "joint": {baseline, pruned, raw_peak, max_abs, tier}}
## where a tell = {tier, max_abs, peak_delta}. {} for a bad pair / engine. A track whose
## no-ops truly do nothing reads Δ 0 (inert); a sub-audible floor faint; a real change
## `changed` (the classifier over-claimed). The caller holds engine.capture_mode = true.
static func noop_ab(engine, feds_bank, pair_idx: int, sound_id: int,
		subs_per_frame: int = 8) -> Dictionary:
	if engine == null or feds_bank == null:
		return {}
	if pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		return {}
	# Baseline = the real mix, un-normalised + UNTRIMMED so each pruned diff compares on a
	# common length (the tail where the baseline still sounds is never dropped). Rendered
	# ONCE and reused for the per-track diffs AND the joint overlay.
	var baseline := render_pair(engine, feds_bank, pair_idx, sound_id, subs_per_frame,
			SILENCE_RMS, SILENCE_QUIET_FRAMES, MAX_RENDER_FRAMES, -1, false, false)
	var out: Dictionary = {}
	for t in [0, 1]:
		var pruned := render_pair_pruning_noops(engine, feds_bank, pair_idx, sound_id, t, subs_per_frame)
		var d := energy_diff(baseline["energy"], pruned["energy"])
		var delta := float(d["max_abs"])
		out[t] = {
			"tier": noop_verdict_tier(delta),
			"max_abs": delta,
			"peak_delta": float(d["peak_delta"]),
		}
	# The joint overlay: baseline vs the BOTH-tracks-pruned mix, both scaled by the SAME
	# (baseline) peak so the visible gap between the two curves IS the Δ.
	var pbank = build_pruned_bank(feds_bank, pair_idx, [0, 1])
	if pbank != null:
		var both := render_pair(engine, pbank, pair_idx, sound_id, subs_per_frame,
				SILENCE_RMS, SILENCE_QUIET_FRAMES, MAX_RENDER_FRAMES, -1, false, false)
		var peak := raw_peak(baseline["energy"])
		var dj := energy_diff(baseline["energy"], both["energy"])
		out["joint"] = {
			"baseline": _scale(baseline["energy"], peak) if peak > 0.0 else baseline["energy"].duplicate(),
			"pruned": _scale(both["energy"], peak) if peak > 0.0 else both["energy"].duplicate(),
			"raw_peak": peak,
			"max_abs": float(dj["max_abs"]),
			"tier": noop_verdict_tier(float(dj["max_abs"])),
		}
	return out


## Build a FedsBank whose `track_idx` bytes are replaced by `new_bytes`, every other
## byte identical and the offset table / data_size fixed up by the size delta. A
## byte-faithful splice (not a re-layout), so the flow-through decoder reads the new
## track then identical subsequent bytes — an untouched track cancels in a Δ. Returns
## null when the splice would run off the raw blob.
##
## Shared, not private to the prune: the structural insert/delete verbs (ADR-0085
## amendment 2026-08-18b) resize a track the same way, and this splice is the piece
## `FedsPrunePersistenceTest` already corpus-gates.
static func rebuild_bank_with_track(feds_bank, track_idx: int, new_bytes: PackedByteArray):
	var raw: PackedByteArray = feds_bank.raw
	var start: int = feds_bank.track_offsets[track_idx]
	if start < 0 or start > raw.size():
		return null
	var orig_len: int = feds_bank.get_track_bytes(track_idx).size()
	var delta: int = new_bytes.size() - orig_len
	var blob := PackedByteArray()
	blob.append_array(raw.slice(0, start))
	blob.append_array(new_bytes)
	blob.append_array(raw.slice(start + orig_len))
	_write_u32(blob, 0x04, feds_bank.data_size + delta)
	if feds_bank.data_offset > start:
		_write_u32(blob, 0x0C, feds_bank.data_offset + delta)
	for i in range(feds_bank.num_tracks):
		var o: int = feds_bank.track_offsets[i]
		if o > start:
			_write_u16(blob, 0x18 + i * 2, o + delta)
	return ExMateriaSound.FedsBank.parse(blob)


static func _write_u16(bytes: PackedByteArray, offset: int, value: int) -> void:
	bytes[offset] = value & 0xFF
	bytes[offset + 1] = (value >> 8) & 0xFF


static func _write_u32(bytes: PackedByteArray, offset: int, value: int) -> void:
	bytes[offset] = value & 0xFF
	bytes[offset + 1] = (value >> 8) & 0xFF
	bytes[offset + 2] = (value >> 16) & 0xFF
	bytes[offset + 3] = (value >> 24) & 0xFF
