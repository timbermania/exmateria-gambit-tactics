extends RefCounted
## Pure projection of a parsed `EffectData` into the Effect Studio **score** — the
## laid-out schedule the timeline view draws (CONTEXT.md "Effect Studio" cluster).
## No scene, no widgets: this is the testable core, the timeline view is thin glue
## over it — mirroring the TuneDashboardModel / TuneDashboardPanel split.
##
## The score is a projection of authored keyframes, not of a running sim, so it
## exists without playback. One absolute frame axis (0…max_frame) carries every
## lane; a phase's keyframes are offset onto that axis by the phase's start
## (phase model C, ADR-0012 — phase2 overlaps for-each, so phase X-bands overlap):
##   phase1   → 0
##   for_each → phase1_duration
##   phase2   → phase1_duration + phase2_delay   (the single-target formula
##              EffectInstance uses: _p2s = _p1d + phase2_delay)
##
## A **span** is the interval a keyframe owns, `[kf[N-1].time, kf[N].time)` in
## phase-local (authored) frames, translated onto the absolute axis. Each span
## carries a **stable identity** (`lane_id#keyframe_index`) independent of its
## position, and BOTH coordinate planes (authored ↔ absolute) so an editor can
## mutate the authored time without losing the keyframe's identity (DAW spec
## §2/§7 — dual-coordinate identity).
##
## No `class_name` — preloaded by path (ADR-0004 cache-safety), like the other
## effect-subsystem scripts and TuneDashboardModel.

const EffectEmitter = ExMateriaEffects.EffectEmitter
const PaletteData = ExMateriaEffects.PaletteData
const ScreenData = ExMateriaEffects.ScreenData

const EffectPhaseClass = ExMateriaEffects.EffectPhase
const EffectScriptPattern = preload("res://src/effects/studio/EffectScriptPattern.gd")
const InspectionTarget = preload("res://src/effects/studio/InspectionTarget.gd")
const ScreenTweenProjector = preload("res://src/effects/studio/ScreenTweenProjector.gd")
const EmitterProjector = preload("res://src/effects/studio/EmitterProjector.gd")
const PaletteTweenProjector = preload("res://src/effects/studio/PaletteTweenProjector.gd")
const CameraTweenProjector = preload("res://src/effects/studio/CameraTweenProjector.gd")
const CameraCompiledProjector = preload("res://src/effects/studio/CameraCompiledProjector.gd")
const SoundTriggerProjector = preload("res://src/effects/studio/SoundTriggerProjector.gd")
const PaletteChannelClass = preload("res://src/effects/studio/PaletteChannel.gd")
const ScreenChannelClass = preload("res://src/effects/studio/ScreenChannel.gd")
const SpacerVerdictsClass = preload("res://src/effects/studio/SpacerVerdicts.gd")
const CameraValueSemanticsClass = preload("res://src/effects/studio/CameraValueSemantics.gd")
const EmitterParamRows = preload("res://src/effects/studio/EmitterParamRows.gd")
const CurveShapeSet = preload("res://src/effects/studio/CurveShapeSet.gd")
const EmitterChannel = preload("res://src/effects/studio/EmitterChannel.gd")
const EmitterFieldRelevance = preload("res://src/effects/studio/EmitterFieldRelevance.gd")
const EmitterSpriteColor = preload("res://src/effects/studio/EmitterSpriteColor.gd")
const EmitterLifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")


## Build the whole score from a parsed EffectData. Returns:
##   {
##     "max_frame": int,                      # absolute axis length
##     "phases":    Array[{name,label,start,end}],   # phase sections (may overlap in X)
##     "lanes":     Array[lane],              # one lane per channel the effect defines
##   }
## Every channel the effect's data defines becomes a lane — including all-skip /
## no-op ones with zero spans — so the Studio shows the full authoring surface: you
## can't author a channel you can't see (the timeline groups them into collapsible
## phase sections to keep the ~45-lane console navigable).
## where a lane is
##   { "id", "kind", "label", "phase", "channel_index", "spans": Array[span] }
## and a span is documented on _particle_span / _color_span below.
## `ghost_by_sound_id` (optional) maps a firing sound_id → its read-only projected
## length in frames (SoundGhostProjector). When supplied, sound trigger spans carry
## a `ghost_frames` the timeline draws as a ghost bar; absent, ghost_frames is 0 and
## triggers are bare instants. The model stays PURE — the studio computes the map
## from the loaded FEDS bank and passes it in.
## `energy_by_sound_id` (optional) is the audio sibling: a firing sound_id → its 0..1
## energy envelope (SoundGhostProjector, the rendered climax cue). When supplied, a
## trigger span carries that `energy` array for the timeline to paint inside its ghost
## bar; absent, `energy` is empty and no curve is drawn.
## `pair_views` (optional) are the pre-projected FEDS pair views (FedsPairModel,
## ADR-0085 TIER-3) the pair-kind projector reads under score["feds_pairs"].
## `pips_by_sound_id` (optional) maps a firing sound_id → its pair's UNROLLED
## note-onset frames (SoundGhostProjector.pair_pips) — read-only pips the timeline
## draws inside that trigger's ghost bar. The studio scopes the map (open pair /
## selected trigger), so the model just threads it.
static func build(effect_data, ghost_by_sound_id: Dictionary = {},
		energy_by_sound_id: Dictionary = {}, container_views: Array = [],
		pair_views: Array = [], pips_by_sound_id: Dictionary = {}) -> Dictionary:
	var lanes: Array = []
	lanes.append_array(_particle_lanes(effect_data))
	lanes.append_array(_screen_lanes(effect_data))
	lanes.append_array(_palette_lanes(effect_data, {}))
	lanes.append_array(_camera_lanes(effect_data))
	lanes.append_array(_sound_lanes(effect_data, ghost_by_sound_id, energy_by_sound_id,
			pips_by_sound_id))

	# The axis must cover a span's ghost bar (its projected length past the instant),
	# not just the instant itself, so ghost bars are never drawn off the ruler. The sound
	# TERMINATOR is excluded (ADR-0085 Amendment 2026-08-10): it sits at its true frame — often a long
	# silent tail past the real content (E317's 544-frame gap) — but must NOT stretch the
	# content extent / default framing, or every beat crushes into ~10% of the width. It
	# stays reachable by pan/zoom; it just doesn't drive the axis.
	var max_frame := _content_max_frame(lanes)

	return {
		"max_frame": max_frame,
		"phases": _phase_sections(effect_data, lanes),
		"lanes": lanes,
		# The GLOBAL "Time scale" lane (#270, ADR-0093): one non-phase lane carrying the two
		# pacing curves as tiled slowness bands, projected against the same frame axis as the
		# phase lanes (its extent falls inside them, so it never grows the ruler). {} when the
		# effect has no time_scale section. Carried alongside `lanes` (not inside it) so the
		# phase-stacked lane machinery — sections, mute cascade, max_frame — is untouched.
		"pacing_lane": _pacing_lane(effect_data, _phase_sections(effect_data, lanes)),
		# Emitter → the child emitters it spawns (on-death + mid-life). Muting a particle
		# lane cascades to its emitters' PURE children (children with no lane of their own),
		# because in E001-class effects most on-screen particles are child-spawned and carry
		# an index no lane represents — without the cascade "mute all tracks" leaves them
		# visible. A child that HAS its own lane is skipped (governed by that lane).
		"emitter_children": _emitter_children(effect_data),
		# ADR-0085 TIER-2: the effect's shared SoundContainers, pre-projected to legible
		# views (SoundContainerModel) by the studio and read by the container-kind projector
		# / the container browser. Empty when the studio supplies no views (pure builds).
		"sound_containers": container_views,
		# ADR-0085 TIER-3: the FEDS pair views (FedsPairModel) the pair-kind projector
		# reads. Empty when the studio supplies none (pure builds / no FEDS section).
		"feds_pairs": pair_views,
	}


## Rebuild ONLY the lanes of `kind` from the live effect_data, splicing them into an existing
## score while REUSING every other kind's lanes by reference — the sim-free geometry reproject
## a live drag needs (ADR-0089 Drag preview). A drag on one channel (a particle Move/Resize)
## mutates only that channel's data, so the other lanes are byte-for-byte identical; a full
## `build` would needlessly re-run the ~400ms palette/screen spacer oracle every rendered frame.
## Preserves lane ORDER (each kind is a contiguous group `build` appends in a fixed sequence),
## recomputes the cheap max_frame + phase sections (a grow extends the ruler), and carries the
## emitter_children + sound_containers forward unchanged.
##
## The splice drops every group the builder is about to RE-EMIT, not merely the group whose name
## was asked for — see `_emitted_kinds`. Matching on the requested kind alone kept `camera`'s
## `camera_compiled` sibling lanes and then appended fresh ones, so the lane list grew by one
## compiled row per phase on every call: on a live camera Move, once per mouse motion.
static func rebuild_kind_lanes(old_score: Dictionary, effect_data, kind: String,
		ghost_by_sound_id: Dictionary = {}, energy_by_sound_id: Dictionary = {}) -> Dictionary:
	var fresh: Array = _lanes_of_kind(effect_data, kind, ghost_by_sound_id, energy_by_sound_id,
		old_score)
	var replaced: Dictionary = {}
	for k in _emitted_kinds(kind):
		replaced[k] = true
	var lanes: Array = []
	var spliced := false
	for lane in old_score.get("lanes", []):
		if replaced.has(String(lane.get("kind", ""))):
			if not spliced:
				lanes.append_array(fresh)   # drop the stale group, insert the fresh one in place
				spliced = true
		else:
			lanes.append(lane)              # reuse every other lane by reference
	if not spliced:
		lanes.append_array(fresh)           # the kind had no lanes before (rare)
	var out: Dictionary = old_score.duplicate()
	out["lanes"] = lanes
	out["max_frame"] = _content_max_frame(lanes)
	out["phases"] = _phase_sections(effect_data, lanes)
	# The global pacing lane rides along too — a curve edit re-folds via a full rebuild, but a
	# kind-scoped reproject must not drop it (its band extents can shift with a phase resize).
	out["pacing_lane"] = _pacing_lane(effect_data, out["phases"])
	return out


## Which lane KINDS one per-kind builder emits. All but camera emit exactly the kind they are
## named for; `_camera_lanes` emits the three authoring sub-channel lanes AND the read-only
## `camera_compiled` storage view, so a camera reproject owns both groups. Stated here rather
## than inferred from `fresh`, so a kind whose builder legitimately returns nothing (no camera
## data at all) still drops its stale lanes instead of stranding them.
const _EMITTED_KINDS := {
	"camera": ["camera", "camera_compiled"],
}


static func _emitted_kinds(kind: String) -> Array:
	return _EMITTED_KINDS.get(kind, [kind])


## The absolute frame axis's length: the furthest extent of real CONTENT across every lane.
##
## Shared by `build` and `rebuild_kind_lanes` because it forked once and the fork was invisible.
## The reproject's copy omitted the sound-TERMINATOR skip (ADR-0085 Amendment 2026-08-10), so a live drag
## on E317 — whose terminator sits 544 frames past the last real event, the very effect that
## decision is written about — stretched the ruler from 112 to 691 the moment any span moved,
## crushing the whole score into a sixth of the width mid-gesture. Neither builder's own tests
## caught it: the parity guard compared lanes span-for-span and never asked about the axis.
static func _content_max_frame(lanes: Array) -> int:
	var max_frame := 0
	for lane in lanes:
		for span in lane["spans"]:
			# The terminator sits at its true frame — often a long silent tail past the real
			# content — but it is not content, so it must not drive the axis or the default
			# framing (ADR-0085 Amendment 2026-08-10). It stays reachable by pan/zoom.
			if str(span.get("role", "")) == "terminator":
				continue
			max_frame = maxi(max_frame, _span_extent(span))
	return max_frame


## The freshly-built lanes for one `kind` (the per-kind builder). Sound needs the ghost/energy
## maps the studio supplies; the others read effect_data alone.
static func _lanes_of_kind(effect_data, kind: String,
		ghost_by_sound_id: Dictionary, energy_by_sound_id: Dictionary,
		old_score: Dictionary = {}) -> Array:
	match kind:
		"particle": return _particle_lanes(effect_data)
		"screen": return _screen_lanes(effect_data)
		"palette": return _palette_lanes(effect_data, old_score)
		"camera": return _camera_lanes(effect_data)
		"sound": return _sound_lanes(effect_data, ghost_by_sound_id, energy_by_sound_id)
	return []


## Adjacency of each emitter index to the child emitters it spawns — `child_emitter_on_death`
## and `child_emitter_mid_life`, each a 0-based emitter index (>= 0; -1 = none, matching the
## runtime guards in ParticleSubsystem). Keyed by 0-based emitter index (== emitter_id - 1).
static func _emitter_children(effect_data) -> Dictionary:
	var out: Dictionary = {}
	if effect_data == null or effect_data.emitters == null:
		return out
	for i in range(effect_data.emitters.size()):
		var em = effect_data.emitters[i]
		var kids: Array = []
		if em.child_emitter_on_death >= 0:
			kids.append(int(em.child_emitter_on_death))
		if em.child_emitter_mid_life >= 0 and int(em.child_emitter_mid_life) not in kids:
			kids.append(int(em.child_emitter_mid_life))
		if not kids.is_empty():
			out[i] = kids
	return out


## The last frame of PHASE 2's authored content — the max span extent across phase-2 lanes,
## EXCLUDING the read-live tint channels (screen/palette) whose long holds must NOT count as
## "the effect is still running" (the EffectEndModel tail-trim principle: a tint held to f600
## can't extend the cast). Also EXCLUDING the sound TERMINATOR (the inert end-of-track cap
## at the max keyframe index): it sits at its true frame — often a long silent tail past the
## real content — but is not content; build() already excludes it from max_frame for the
## same reason (ADR-0085 Amendment 2026-08-10). The studio floors its DISPLAYED end frame here so a
## scheduled phase 2 (camera/particle/sound) plays live instead of being dimmed as dead when
## particles reap right at the phase-2 boundary (#271 follow-up). EffectEndModel's faithful
## particle-reap is untouched — this is purely the studio's display floor. 0 when phase 2
## has no such content.
static func phase2_content_end(score: Dictionary) -> int:
	var end := 0
	for lane in score.get("lanes", []):
		if String(lane.get("phase", "")) != EffectPhaseClass.PHASE2:
			continue
		var kind := String(lane.get("kind", ""))
		if kind == "screen" or kind == "palette":
			continue
		for span in lane.get("spans", []):
			if str(span.get("role", "")) == "terminator":
				continue
			end = maxi(end, int(span.get("end", span.get("start", 0))))
	return end


## The absolute-axis start frame of a phase (see class doc).
static func phase_offset(effect_data, phase: String) -> int:
	var tl = effect_data.timeline
	if tl == null:
		return 0
	match phase:
		EffectPhaseClass.PHASE1:
			return 0
		EffectPhaseClass.PHASE_FOR_EACH:
			return tl.phase1_duration
		EffectPhaseClass.PHASE2:
			return tl.phase1_duration + tl.phase2_delay
	return 0


## The GLOBAL "Time scale" pacing lane (#270, ADR-0093) — the one non-phase lane. It carries the
## two pacing curves (`outer_phases` = "Phase 1 pacing", `for_each` = "For-each pacing") as tiled
## bands over their played windows: Phase-1 over [0, phase1_duration), For-each over the for-each
## region (that section's content extent, since a per-target for-each has no fixed length).
## Returns {} when the effect has no time_scale section. Each band carries the played-window
## samples (frame-indexed) + its enable flag + the field key the pop-up painter binds. The full
## 600-int tail past the window is preserved on disk but not carried here (it is never sampled).
static func _pacing_lane(effect_data, phases: Array) -> Dictionary:
	if effect_data == null or not (effect_data.time_scale is Dictionary) \
			or effect_data.time_scale.is_empty():
		return {}
	var ts: Dictionary = effect_data.time_scale
	var flags: Dictionary = ts.get("flags", {})
	var p1d := phase_offset(effect_data, EffectPhaseClass.PHASE_FOR_EACH)  # for-each start = phase1_duration
	var bands: Array = []
	# Phase-1 band over the real phase-1 window [0, phase1_duration).
	if p1d > 0 and ts.get("outer_phases", []) is Array and not ts["outer_phases"].is_empty():
		bands.append(_pacing_band("outer_phases", "Phase 1 pacing", 0, p1d,
			ts["outer_phases"], bool(flags.get("time_scale_pattern1", false))))
	# For-each band over the for-each region (its section extent).
	var fe_end := p1d
	for sec in phases:
		if String(sec.get("name", "")) == EffectPhaseClass.PHASE_FOR_EACH:
			fe_end = int(sec.get("end", p1d))
			break
	if fe_end > p1d and ts.get("for_each", []) is Array and not ts["for_each"].is_empty():
		bands.append(_pacing_band("for_each", "For-each pacing", p1d, fe_end,
			ts["for_each"], bool(flags.get("time_scale_pattern2", false))))
	return {
		"id": "time_scale",
		"kind": "time_scale",
		"label": "Time scale",
		"phase": "",
		"global": true,
		"bands": bands,
	}


## One tiled slowness band of the pacing lane: the played-window slice of a 600-int curve laid
## over [start, end) on the absolute axis, with its enable flag and the curve's field key (the
## pop-up painter binds by field). The window is clamped to the curve length.
static func _pacing_band(field: String, label: String, start: int, end: int,
		curve: Array, enabled: bool) -> Dictionary:
	var window: int = clampi(end - start, 0, curve.size())
	var pacing: Array = curve.slice(0, window)
	return {
		"id": "time_scale#%s" % field,
		"lane_id": "time_scale",
		"kind": "time_scale",
		"field": field,
		"label": label,
		"start": start,
		"end": end,
		"pacing": pacing,
		"enabled": enabled,
		# The band IS the editable surface (ADR-0093: authored on the timeline, not a projector
		# row) — it self-describes its write address the same way a projector's shape:"edit" field
		# does, so the band-click routes uniformly and the editability guard's sweep sees it.
		"shape": "edit",
		"field_ref": {"channel": "time_scale", "field": field},
	}


## The band HEIGHT map (#270, ADR-0093): slowness above normal, `(value - 2)/8` clamped to
## 0..1. Value 2 (normal speed, ~94% of corpus samples) reads flat; 10 (max slow) fills the
## lane, so slow-mo swells stand out against the rest of the effect. Pure — the draw and any
## test read the same mapping.
static func pacing_norm(value: int) -> float:
	return clampf((float(value) - 2.0) / 8.0, 0.0, 1.0)


## The pacing PLAYBACK factor at an absolute frame: BASE_PACING(2)/value, gated by the enable flags
## — the same math as EffectTimeline._update_time_scale, exposed pure so the Studio transport can
## slow its clock exactly like the game does (ADR-0093). Phase-1 frames [0, phase1_duration) key
## `outer_phases` under pattern1; later frames key `for_each` (local = frame - phase1_duration)
## under pattern2. A disabled pattern, an empty block, or value 2 (normal) all return 1.0.
const PACING_BASE := 2  # FFT pacing baseline; must match EffectTimeline.BASE_PACING
static func pacing_factor_at(time_scale, phase1_duration: int, abs_frame: int) -> float:
	if not (time_scale is Dictionary) or time_scale.is_empty():
		return 1.0
	var flags: Dictionary = time_scale.get("flags", {})
	var value := PACING_BASE
	if abs_frame < phase1_duration:
		if bool(flags.get("time_scale_pattern1", false)):
			var oc: Array = time_scale.get("outer_phases", [])
			if abs_frame >= 0 and abs_frame < oc.size():
				value = int(oc[abs_frame])
	else:
		if bool(flags.get("time_scale_pattern2", false)):
			var fc: Array = time_scale.get("for_each", [])
			var local := abs_frame - phase1_duration
			if local >= 0 and local < fc.size():
				value = int(fc[local])
	if value <= 0:
		return 1.0
	return float(PACING_BASE) / float(value)


## Absolute offsets for every phase, the shape SpacerVerdicts folds a colour lane's
## cross-phase stream at (the score projects ALL phases as started — decision 7's
## single-pass for_each stream, exactly as every lane already models it).
static func _color_offsets(effect_data) -> Dictionary:
	var offsets: Dictionary = {}
	for phase in EffectPhaseClass.ALL:
		offsets[phase] = phase_offset(effect_data, phase)
	return offsets


# --- Particle lanes -------------------------------------------------------

## One lane per timeline channel the effect defines, in phase then channel-index
## order. Empty channels (all-skip keyframes) are KEPT — with zero spans — so the
## Studio shows every authorable channel, not just the ones that currently fire.
static func _particle_lanes(effect_data) -> Array:
	var out: Array = []
	var tl = effect_data.timeline
	if tl == null:
		return out
	for phase in EffectPhaseClass.ALL:
		var offset := phase_offset(effect_data, phase)
		var channels = tl.get_channels(phase)
		for ch in channels:
			var lane_id := "particle:%s:%d" % [phase, ch.channel_index]
			var spans := _particle_spans(ch, offset, phase, lane_id)
			out.append({
				"id": lane_id,
				"kind": "particle",
				"label": "Particle %d" % ch.channel_index,
				"phase": phase,
				"channel_index": ch.channel_index,
				"spans": spans,
			})
	return out


## Spans for one channel. kf[N] owns `[kf[N-1].time, kf[N].time)` and spawns
## emitter kf[N].emitter_id (0 = skip → a gap, not drawn). kf[0] is the implicit
## origin (PhaseBlock skips it). Zero-length spans are omitted. A DISABLED span
## (emitter_id 0 but a session-remembered id, ADR-0089 particle_timeline) is still
## emitted — drawn dimmed + selectable — via the transient stash the score consults.
static func _particle_spans(channel, offset: int, phase: String, lane_id: String) -> Array:
	var spans: Array = []
	for n in range(1, channel.max_keyframe + 1):
		if n >= channel.keyframes.size():
			break
		var kf = channel.keyframes[n]
		var prev = channel.keyframes[n - 1]
		# The effective identity: live emitter_id, else the session-remembered id (a disabled
		# span). Both zero → a genuine gap: nothing spawns, nothing to draw.
		var effective_id: int = int(kf.emitter_id) if int(kf.emitter_id) != 0 \
			else int(kf.remembered_emitter_id)
		if effective_id == 0:
			continue
		if kf.time <= prev.time:
			continue
		spans.append(_particle_span(kf, prev, n, offset, phase, lane_id,
			channel.channel_index, effective_id))
	return spans


static func _particle_span(kf, prev, n: int, offset: int, phase: String,
		lane_id: String, channel_index: int, effective_id: int) -> Dictionary:
	var emitter_index: int = effective_id - 1
	# Disabled = live emitter_id is 0 but the span carries a remembered identity: draw it
	# dimmed with a dashed (null-span) outline so it reads as "muted, not gone", and keep it
	# selectable (it stays in the lane's span list so the inspector can re-enable/retarget it).
	var disabled: bool = int(kf.emitter_id) == 0
	var base_color: Color = emitter_color(emitter_index)
	return {
		"id": "%s#%d" % [lane_id, n],
		"lane_id": lane_id,
		"kind": "particle",
		"phase": phase,
		"channel_index": channel_index,
		"keyframe_index": n,
		"authored_start": prev.time,
		"authored_end": kf.time,
		"start": offset + prev.time,
		"end": offset + kf.time,
		"emitter_id": effective_id,
		"emitter_index": emitter_index,
		"action_flags": kf.action_flags,
		"disabled": disabled,
		"color": _dim_disabled(base_color) if disabled else base_color,
		"fields": {
			"emitter_index": emitter_index,
			"emitter_id": effective_id,
			"channel": channel_index,
			"phase": phase,
			"action_flags": kf.action_flags,
			"disabled": disabled,
			"border": "dashed" if disabled else "solid",
			"frame_range": "%d–%d" % [offset + prev.time, offset + kf.time],
			"authored_range": "%d–%d" % [prev.time, kf.time],
		},
	}


## Wash an emitter colour back toward the lane slate for a DISABLED (muted) span — dim enough
## to read as inactive, saturated enough to still say which emitter it remembers.
static func _dim_disabled(color: Color) -> Color:
	return color.lerp(Color(0.22, 0.24, 0.30), 0.6)


# --- Screen (background) color lanes --------------------------------------

## One lane per phase the screen animates in. Screen keyframes differ from
## particle keyframes: each carries its OWN `duration_frames` width that
## accumulates within the phase (particle `time` is already cumulative). Only
## enabled (TINT, ctrl bit 7 set) keyframes are drawn; FADE keyframes advance the
## cursor but stay invisible, matching ScreenSubsystem._push_phase_ops.
static func _screen_lanes(effect_data) -> Array:
	var out: Array = []
	var screen = effect_data.screen
	if screen == null:
		return out
	# The SPACER verdict is disable-equivalence over the whole cross-phase stream
	# (ADR-0087 decs. 17-22) — computed lane-wide here at build time by the pure
	# fold oracle, keyed {phase: {keyframe_index: bool}}. Every colour value edit
	# rebuilds the score (unconditional invalidates_layout), so it is never stale.
	var spacer_verdicts: Dictionary = SpacerVerdictsClass.screen_verdicts(
		screen, _color_offsets(effect_data))
	for phase in EffectPhaseClass.ALL:
		var ch = screen.get_channel(phase)
		if ch == null or ch.keyframes.is_empty():
			continue
		var offset := phase_offset(effect_data, phase)
		var lane_id := "screen:%s" % phase
		var spans: Array = []
		var local := 0
		# Faithful window: EXACTLY what ScreenSubsystem._push_phase_ops plays
		# (0..max_keyframe-2). The trailing keyframes are terminators/padding — mostly
		# bit-7-clear (Gradient) — so drawing only the played window is what keeps them
		# from surfacing as phantom Gradient tweens (ADR-0071; the E173 "bound 2 too
		# wide" hand-back). Both kinds draw within it: the lane is fully tiled.
		var last_idx: int = mini(ch.keyframes.size(), maxi(0, ch.max_keyframe - 1))
		for i in range(last_idx):
			var kf = ch.keyframes[i]
			var dur: int = maxi(1, kf.duration_frames)
			# The projector owns the kind discrimination — its summary gives the fill,
			# label ("Blend"/"Grad") and border; the dispatcher later routes the span to
			# ScreenTweenProjector.sections(kf) for the inspector detail.
			var summary: Dictionary = ScreenTweenProjector.summarize(kf)
			# `spacer` = the disable-equivalence verdict (ADR-0087). Fifth amendment: the inert
			# slate is retired and the flavour note removed — the verdict now only DECIDES WHAT
			# TO HIDE (an enabled inert spacer renders as nothing). A span shows its OWN produced
			# colour; a DELIBERATELY-DISABLED event (Enable cleared → stash present) shows it
			# DIMMED ("muted, not gone"). An enabled spacer's real fill only surfaces when it is
			# the selected event.
			var spacer: bool = bool(spacer_verdicts.get(phase, {}).get(i, false))
			var enabled: bool = not ScreenChannelClass.is_author_disabled(kf)
			var fill: Color = summary["color"] if enabled else _dim_disabled(summary["color"])
			spans.append(_color_span(lane_id, "screen", i, phase, offset, local, dur,
				fill, {
					"screen_kind": summary["label"],
					"border": summary["border"],
					"spacer": spacer,
					"enabled": enabled,
					"mode": "TINT" if kf.mode == ScreenData.ScreenMode.BLEND else "FADE",
					"blend_mode": kf.blend_mode,
					"duration_frames": dur,
					"time_value": kf.time_value,
					"start_color": kf.start_color,
				}))
			local += dur
		# Keep the lane even when it is empty (no played keyframe) — the screen channel
		# exists for this phase and stays authorable.
		out.append({
			"id": lane_id,
			"kind": "screen",
			"label": "Screen",
			"phase": phase,
			"channel_index": 0,
			"spans": spans,
		})
	return out


## A color span (screen or palette): the drawn interval a color keyframe owns,
## `[local, local+dur)` phase-local, translated onto the absolute axis. Same
## stable-identity + dual-coordinate shape as a particle span, but hued by its
## own tint and carrying color-typed inspector fields.
static func _color_span(lane_id: String, kind: String, i: int, phase: String,
		offset: int, local: int, dur: int, color: Color, fields: Dictionary) -> Dictionary:
	return {
		"id": "%s#%d" % [lane_id, i],
		"lane_id": lane_id,
		"kind": kind,
		"phase": phase,
		"channel_index": 0,
		"keyframe_index": i,
		"authored_start": local,
		"authored_end": local + dur,
		"start": offset + local,
		"end": offset + local + dur,
		"color": color,
		"fields": fields,
	}


# --- Palette (unit/map tint) color lanes ----------------------------------

const _PALETTE_LABELS := {
	"affected_units": "Affected units",
	"caster": "Caster",
	"target": "Target",
}

## One lane per (phase, palette channel) that has an enabled keyframe. Same
## cumulative-duration projection as screen; enable is the palette keyframe's own
## `enabled` flag (ctrl bit 7). Hued by the keyframe rgb.
static func _palette_lanes(effect_data, old_score: Dictionary = {}) -> Array:
	var out: Array = []
	var palette = effect_data.palette
	if palette == null:
		return out
	# Disable-equivalence spacer verdicts (ADR-0087 decs. 17-22), one cross-phase
	# fold per channel_name (each palette channel is ONE continuous stream through the
	# PSX CLUT DDA — build_stream). Keyed {channel_name: {phase: {keyframe_index: bool}}}.
	#
	# REUSED per channel_name where `old_score` already describes an IDENTICAL stream — the
	# fold is this model's most expensive computation by an order of magnitude and a
	# kind-scoped reproject re-ran every channel's. Measured on E317: a palette reproject cost
	# 74ms pristine and 143ms once a fine Move had laid its padding down (7fps mid-drag, against
	# camera's 0.9ms — camera's spacer test is a LOCAL predicate, colour's is a fold, which is
	# the whole of why the colour Move drags like treacle and camera does not).
	#
	# Exact, not a heuristic: `palette_verdicts` reads ONLY this channel_name's ops across the
	# phases, and an op is (rgb, blend_mode, enabled, time_value) at an absolute frame. If every
	# played keyframe still matches what the old score recorded, the op stream is the same
	# stream and the verdict is the same verdict. A Move touches ONE channel, so the other two
	# reuse. See `_palette_stream_unchanged`.
	var offsets: Dictionary = _color_offsets(effect_data)
	var spacer_verdicts: Dictionary = {}
	for channel_name in PaletteData.ALL_CHANNELS:
		var reused: Dictionary = _reusable_palette_verdicts(palette, old_score, channel_name)
		spacer_verdicts[channel_name] = reused if not reused.is_empty() \
			else SpacerVerdictsClass.palette_verdicts(palette, channel_name, offsets)
	for phase in EffectPhaseClass.ALL:
		var offset := phase_offset(effect_data, phase)
		for channel_name in PaletteData.ALL_CHANNELS:
			var ch = palette.get_channel(phase, channel_name)
			if ch == null or ch.keyframes.is_empty():
				continue
			var lane_id := "palette:%s:%s" % [phase, channel_name]
			var spans: Array = []
			var local := 0
			# Mirror PaletteSubsystem._each_keyframe EXACTLY: the PSX palette stepper
			# breaks at kf_idx >= max_keyframe-1, applying only 0..max_keyframe-2; the
			# rest are terminators/padding it never plays. (The screen window above is
			# now IDENTICAL — the old wider-inclusive screen belief was refuted, see
			# ScreenSubsystem._push_phase_ops.) Walking past it drew phantom tint
			# spans — E077 affected_units showed a bogus [600,5400] keyframe that the
			# runtime never touches.
			var last_idx: int = mini(ch.keyframes.size(), maxi(0, ch.max_keyframe - 1))
			for i in range(last_idx):
				var kf = ch.keyframes[i]
				var dur: int = maxi(1, kf.duration_frames)
				# EVERY played keyframe draws (ADR-0087 fully-tiled lane) — a spacer still
				# occupies its tile so it stays selectable to edit into a real event. A real
				# tint is hued by its rgb; a spacer takes the shared inert slate (the painter
				# hatches it). The verdict is the lane-wide disable-equivalence fold (fourth
				# amendment), not the keyframe's own bytes.
				var fields := _palette_kf_fields(kf, channel_name,
					bool(spacer_verdicts[channel_name].get(phase, {}).get(i, false)))
				# Fifth amendment (ADR-0087): the inert slate is retired. A span shows its OWN
				# rgb; a DELIBERATELY-DISABLED tween (Enable bit clear) shows it DIMMED ("muted,
				# not gone"). An enabled inert spacer is hidden by the painter, so its real fill
				# only surfaces when it is the selected event.
				var real := Color(kf.rgb.x / 255.0, kf.rgb.y / 255.0, kf.rgb.z / 255.0, 1.0)
				var color: Color = real if bool(fields.get("enabled", false)) else _dim_disabled(real)
				spans.append(_color_span(lane_id, "palette", i, phase, offset, local, dur,
					color, fields))
				local += dur
			# Keep the lane even with no enabled keyframe — the palette channel exists
			# for this (phase, channel) and stays authorable.
			out.append({
				"id": lane_id,
				"kind": "palette",
				"label": _PALETTE_LABELS.get(channel_name, channel_name),
				"phase": phase,
				"channel_index": 0,
				"spans": spans,
			})
	return out


## The old score's verdicts for one palette channel_name, but ONLY when the live channel still
## produces the identical op stream — otherwise `{}` and the caller folds. Keyed
## `{phase: {keyframe_index: bool}}`, the shape `palette_verdicts` returns.
##
## The comparison is against the SPAN FIELDS the old score already carries, so nothing extra has
## to be cached: a span records its keyframe's `rgb`, `enabled`, `blend_mode`, `time_value` and
## `duration_frames`, plus the absolute `start` the op fires at. Those five ARE the op
## (`PaletteSubsystem._push_phase_ops` pushes exactly them), so matching them all means the fold
## would walk the same stream and return the same answer.
##
## Conservative in both directions that matter: a missing lane, a differing span count, or any
## field mismatch abandons the reuse for that channel_name and folds it properly.
static func _reusable_palette_verdicts(palette, old_score: Dictionary,
		channel_name: String) -> Dictionary:
	if old_score.is_empty():
		return {}
	var by_lane: Dictionary = {}
	for lane in old_score.get("lanes", []):
		if String(lane.get("kind", "")) == "palette" \
				and String(lane.get("id", "")).ends_with(":%s" % channel_name):
			by_lane[String(lane.get("phase", ""))] = lane.get("spans", [])
	var out: Dictionary = {}
	for phase in EffectPhaseClass.ALL:
		var ch = palette.get_channel(phase, channel_name)
		if ch == null or ch.keyframes.is_empty():
			if by_lane.has(phase) and not (by_lane[phase] as Array).is_empty():
				return {}          # the old score saw content here and the live channel has none
			continue
		if not by_lane.has(phase):
			return {}
		var spans: Array = by_lane[phase]
		var last_idx: int = mini(ch.keyframes.size(), maxi(0, ch.max_keyframe - 1))
		if spans.size() != last_idx:
			return {}
		var local := 0
		var verdicts: Dictionary = {}
		for i in range(last_idx):
			var kf = ch.keyframes[i]
			var sp: Dictionary = spans[i]
			var f: Dictionary = sp.get("fields", {})
			var dur: int = maxi(1, kf.duration_frames)
			if int(sp.get("authored_start", -1)) != local \
					or int(f.get("duration_frames", -1)) != dur \
					or int(f.get("time_value", -1)) != int(kf.time_value) \
					or int(f.get("blend_mode", -1)) != int(kf.blend_mode) \
					or bool(f.get("enabled", not kf.enabled)) != bool(kf.enabled) \
					or f.get("rgb", null) != kf.rgb:
				return {}
			verdicts[i] = bool(f.get("spacer", false))
			local += dur
		out[phase] = verdicts
	return out


## The palette projector's field-set, read straight off a live palette Keyframe.
## Shared by the span builder AND live re-projection. `channel` is lane identity
## (which tint channel), not a keyframe value. Duration mirrors the span width
## (a zero-duration keyframe still gets a visible one-frame slot).
##
## `spacer` is HANDED IN — the lane-wide disable-equivalence verdict (ADR-0087) computed at
## score build; the live re-projection passes the snapshot verdict, safe because every
## verdict-affecting edit rebuilds the score. Fifth amendment: the verdict only DECIDES WHAT
## THE PAINTER HIDES (an enabled inert spacer renders as nothing); the flavour note is gone.
static func _palette_kf_fields(kf, channel_name: String, spacer: bool) -> Dictionary:
	return {
		"channel": channel_name,
		"rgb": kf.rgb,
		"enabled": kf.enabled,
		"blend_mode": kf.blend_mode,
		"duration_frames": maxi(1, kf.duration_frames),
		"time_value": kf.time_value,
		"spacer": spacer,
	}


# --- Camera lanes ---------------------------------------------------------

## Camera keyframes drive three INDEPENDENT sub-channels (angle / position / zoom),
## selected per keyframe by `channel_mask` (bit 0/1/2). The runtime searches each
## sub-channel separately (CameraSubsystem._find_active_keyframe), so the score
## breaks camera into one lane per (phase, sub-channel): `camera:phase1:angle`, …
const _CAMERA_CHANNELS := [
	{"name": "angle", "mask": 1, "label": "Cam angle"},
	{"name": "position", "mask": 2, "label": "Cam position"},
	{"name": "zoom", "mask": 4, "label": "Cam zoom"},
]


static func _camera_lanes(effect_data) -> Array:
	var out: Array = []
	var camera = effect_data.camera
	if camera == null:
		return out
	for phase in EffectPhaseClass.ALL:
		if not camera.has_table(phase):
			continue
		var table = camera.get_table(phase)
		var offset := phase_offset(effect_data, phase)
		for cc in _CAMERA_CHANNELS:
			var lane_id := "camera:%s:%s" % [phase, cc["name"]]
			out.append({
				"id": lane_id,
				"kind": "camera",
				"label": cc["label"],
				"phase": phase,
				"channel_index": cc["mask"],
				"spans": _camera_spans(table, cc["mask"], cc["name"], offset, phase, lane_id),
			})
		# The compiled (storage/truth) lane — the read-only companion to the three
		# sub-channel lanes, appended AFTER them. It shows the PACKED schedule: one
		# span per stored keyframe, so a designer can SEE how their sub-channel edits
		# coalesce/split into the actual byte-level table (ADR-0086 authoring stands;
		# this only observes it). Display-only, never authored — see has_mute_controls.
		var compiled_id := "camera_compiled:%s" % phase
		out.append({
			"id": compiled_id,
			"kind": "camera_compiled",
			"label": "Cam (compiled)",
			"phase": phase,
			"channel_index": 0,
			"spans": _camera_compiled_spans(table, offset, phase, compiled_id),
		})
	return out


## Spans for one camera sub-channel. Mirrors the runtime's per-channel search: among
## the keyframes whose mask selects this channel (indices 0..max_keyframe), each owns
## `[prev_selected.end_frame, end_frame)` phase-local. Zero-width no-ops (the padding
## keyframes with end_frame 0 / UNKNOWN interpolation) collapse away naturally.
static func _camera_spans(table, mask: int, channel_name: String, offset: int,
		phase: String, lane_id: String) -> Array:
	var spans: Array = []
	var last_idx: int = mini(table.keyframes.size(), table.max_keyframe + 1)
	var prev_end := 0
	# The authoring address is the event's ORDINAL within this sub-channel lane (ADR-0086
	# amendment, #286) — stable across a split/merge that renumbers the raw keyframe array.
	# It counts EVERY mask-set keyframe (mirroring CameraLowering.parse), so it lines up with
	# the write-side resolver even where a zero-width no-op emits no visible span. The span id
	# and the projector's field_ref key on it; `keyframe_index` stays the raw slot for live re-read.
	var ordinal := 0
	for i in range(last_idx):
		var kf = table.keyframes[i]
		if kf.channel_mask & mask == 0:
			continue
		var ord := ordinal
		ordinal += 1
		var end: int = kf.end_frame
		if end > prev_end:
			spans.append({
				"id": "%s#%d" % [lane_id, ord],
				"lane_id": lane_id,
				"kind": "camera",
				"phase": phase,
				"channel_index": mask,
				"keyframe_index": i,
				"ordinal": ord,
				"authored_start": prev_end,
				"authored_end": end,
				"start": offset + prev_end,
				"end": offset + end,
				"color": camera_color(channel_name),
				"fields": _camera_kf_fields(kf, channel_name),
			})
		prev_end = maxi(prev_end, end)
	return spans


## Markers for the compiled (storage) lane — one POINT per REAL packed keyframe. "Real"
## is the SAME test CameraLowering.parse applies: `channel_mask != 0` (a keyframe that
## drives no sub-channel is a mask==0 empty SoA slot, not real — verified on E317, whose
## unused native slots all carry mask==0/end==0). The pads drop out.
##
## Each marker is anchored AT its `end_frame` — a keyframe is "a target reached at frame
## N", not an interval. The storage stores no duration, so the compiled view must not
## invent one: an interval `[prev,end)` tile lies whenever tracks interleave (a position
## move over [0,40) rendered [30,40) just because an angle keyframe was packed before it).
## The real per-sub-channel window lives on the angle/position/zoom lanes; here we show
## only the honest fact — a keyframe lands here. `start == end == offset + end_frame` is
## a deliberate zero-width point; consumers key off `marker: true`.
##
## Coincident siblings are load-bearing: when a coalesced keyframe SPLITS, the store grows
## two keyframes at the SAME end_frame (angle@10, position@10) — the whole reason this lane
## exists (ADR-0086 observability). As points they land at the same frame, each keeping its
## own mask; the view fans them so both stay clickable.
static func _camera_compiled_spans(table, offset: int, phase: String, lane_id: String) -> Array:
	var spans: Array = []
	var last_idx: int = mini(table.keyframes.size(), table.max_keyframe + 1)
	for i in range(last_idx):
		var kf = table.keyframes[i]
		if int(kf.channel_mask) == 0:
			continue         # drives no sub-channel → a mask==0 empty slot, not real
		var frame: int = kf.end_frame
		spans.append({
			"id": "%s#%d" % [lane_id, i],
			"lane_id": lane_id,
			"kind": "camera_compiled",
			"phase": phase,
			"channel_index": 0,
			"keyframe_index": i,
			"marker": true,
			"authored_start": frame,
			"authored_end": frame,
			"start": offset + frame,
			"end": offset + frame,
			"color": CAMERA_COMPILED_COLOR,
			"fields": _camera_compiled_fields(kf, i),
		})
	return spans


## Neutral slate hue for the compiled lane — reads as "storage / behind the scenes",
## distinct from the three saturated sub-channel hues (see camera_color).
const CAMERA_COMPILED_COLOR := Color(0.58, 0.60, 0.66)


## The packed keyframe's raw field-set for the compiled span — the byte-level truth
## (index, end_frame, mask, decoded source/interp, param/flags, and the raw command
## word). Distinct from _camera_kf_fields, which is per-sub-channel authoring data.
static func _camera_compiled_fields(kf, index: int) -> Dictionary:
	return {
		"index": index,
		"end_frame": kf.end_frame,
		"channel_mask": kf.channel_mask,
		"source_mode": kf.source_mode,
		"interpolation": kf.interpolation,
		"param_index": kf.param_index,
		"flags": kf.flags,
		"command_raw": kf.command_raw,
	}


## The camera projector's field-set, read straight off a live CameraData.Keyframe.
## Shared by the span builder AND live re-projection (span_sections) so the inspector
## never drifts from a build-time snapshot. `camera_channel` is lane identity (which
## sub-channel the span draws), not a keyframe value.
static func _camera_kf_fields(kf, channel_name: String) -> Dictionary:
	return {
		"camera_channel": channel_name,
		"source_mode": kf.source_mode,
		"interpolation": kf.interpolation,
		"channel_mask": kf.channel_mask,
		# SPACER (ADR-0086 dec. 15): this sub-channel event owns its span and
		# moves nothing, so the timeline draws it as empty space. Per SPAN, not per keyframe —
		# a coalesced keyframe shares one command word but keeps a separate value per
		# sub-channel, so `channel_name` picks the vector the runtime actually reads. Local
		# (no fold): camera events never preempt one another, so there is no stream context.
		"spacer": CameraValueSemanticsClass.is_spacer(
			channel_name, kf.source_mode, kf.get(channel_name)),
		"angle": kf.angle,
		"position": kf.position,
		"zoom": kf.zoom,
		# Raw values the editable projector (#267) seeds from.
		"end_frame": kf.end_frame,
		"command_raw": kf.command_raw,
		"param_index": kf.param_index,
		"flags": kf.flags,
	}


# --- Sound lanes ----------------------------------------------------------

const SOUND_COLOR := Color(0.95, 0.72, 0.30)  # warm amber — the SFX-trigger hue


## Does a sound keyframe's `sound_id` FIRE a sound? The single home for the skip
## threshold: ids 0/1 are skips (silent walls), 2.. are triggers. Both the score
## projection here and the studio's SoundGhostProjector / SoundGapMath ask through
## this so the threshold lives in one place (ADR-0085).
static func sound_id_fires(sid: int) -> bool:
	return sid >= 2


## One lane per (phase, sound channel_index) the effect defines. Sound keyframes are
## triggers, not sustained states: keyframe i FIRES at the cumulative duration of the
## keyframes before it (kf[0] at frame 0), and its own `duration_frames` is the gap
## until the next fires — so the same `[local, local+dur)` projection as the color
## lanes reads as "fires here, holds until the next". A keyframe fires only when its
## `sound_id >= 2` (0/1 are skip). Window mirrors EffectSoundController / the FFT sound
## walker's strict `<` guard (`kf < max`, disasm 0x801A478C phase / 0x801A3408 for-each):
## BOTH phase and for_each fire indices 0..max_keyframe-1, and index==max_keyframe is a
## terminator the runtime never fires. (This is narrower than palette/screen's `< max-1`
## and — contrary to an earlier assumption — for_each does NOT run to the array end.)
static func _sound_lanes(effect_data, ghost_by_sound_id: Dictionary = {},
		energy_by_sound_id: Dictionary = {}, pips_by_sound_id: Dictionary = {}) -> Array:
	var out: Array = []
	var sound = effect_data.sound
	if sound == null or sound.is_empty():
		return out
	for phase in EffectPhaseClass.ALL:
		var channels = sound.get(phase, [])
		if not (channels is Array):
			continue
		var offset := phase_offset(effect_data, phase)
		for ch in channels:
			if not (ch is Dictionary):
				continue
			var ci: int = int(ch.get("channel_index", 0))
			var lane_id := "sound:%s:%d" % [phase, ci]
			out.append({
				"id": lane_id,
				"kind": "sound",
				"label": "Sound %d" % ci,
				"phase": phase,
				"channel_index": ci,
				"spans": _sound_spans(ch, ci, offset, phase, lane_id, ghost_by_sound_id,
						energy_by_sound_id, pips_by_sound_id),
			})
	return out


static func _sound_spans(ch: Dictionary, ci: int, offset: int, phase: String,
		lane_id: String, ghost_by_sound_id: Dictionary = {},
		energy_by_sound_id: Dictionary = {}, pips_by_sound_id: Dictionary = {}) -> Array:
	var spans: Array = []
	var kfs = ch.get("keyframes", [])
	if not (kfs is Array):
		return spans
	# ADR-0085 "every event is accessible via a timeline handle": over the live window
	# `[0, max_keyframe)` EVERY event projects one selectable handle — audible or not (a
	# silent event, sound_id 0/1, is an event that emits no new sound, not a rest). The
	# tail (ghost/energy) is the SOLE tell of sound: it comes from the ghost maps, which
	# only map sound_id >= 2 (SoundGhostProjector), so a silent event's handle carries
	# none. There is no audible-only filter here anymore — the honest projection is the
	# source, and the few audible-only consumers filter downstream.
	var last_idx: int = mini(kfs.size(), int(ch.get("max_keyframe", 0)))
	var local := 0
	for i in range(last_idx):
		var kf = kfs[i]
		var sid: int = int(kf.get("sound_id", 0))
		spans.append(_sound_span("event", lane_id, ci, phase, i, local, offset, kf,
			int(ghost_by_sound_id.get(sid, 0)),
			energy_by_sound_id.get(sid, PackedFloat32Array()),
			pips_by_sound_id.get(sid, [])))
		local += int(kf.get("duration_frames", 0))
	# The terminator (index == max_keyframe): a distinct INERT end-cap at its true frame
	# (last fire + last gap), so the last event's gap points at something visible. It is
	# NOT a fire — the runtime never plays index max_keyframe — so it carries NO tail even
	# if its slot's sound_id looks audible, and it is select-to-inspect only (its byte, the
	# last event's gap, is already owned by that event's Gap field). max_keyframe == 0
	# emits nothing (a lone end-cap would point at nothing).
	var max_kf: int = int(ch.get("max_keyframe", 0))
	if max_kf >= 1 and last_idx == max_kf:
		var term_kf = kfs[max_kf] if max_kf < kfs.size() else {}
		spans.append(_sound_span("terminator", lane_id, ci, phase, max_kf, local, offset,
			term_kf, 0, PackedFloat32Array(), []))
	return spans


## Build one sound-lane span. A trigger is an INSTANT (ADR-0085): zero on-timeline length
## (`start == end`); `duration_frames` is the gap to the NEXT event (it advances `local`,
## it is not a length). `role` is the honest-projection discriminator: "event" (a live-
## window handle) or "terminator" (the inert end-cap at index max_keyframe). `ghost_frames`
## / `energy` are the read-only projected length + climax swell — 0/empty for a silent event
## and ALWAYS for a terminator (the caller passes them, so the terminator never lies).
static func _sound_span(role: String, lane_id: String, ci: int, phase: String,
		index: int, local: int, offset: int, kf, ghost_frames: int,
		energy, pips: Array = []) -> Dictionary:
	return {
		"id": "%s#%d" % [lane_id, index],
		"lane_id": lane_id,
		"kind": "sound",
		"role": role,
		"phase": phase,
		"channel_index": ci,
		"keyframe_index": index,
		"authored_start": local,
		"authored_end": local,
		"start": offset + local,
		"end": offset + local,
		"ghost_frames": ghost_frames,
		"energy": energy,
		# ADR-0085 TIER-3 ghost pips: the resolved pair's unrolled note-onset frames
		# (relative to the fire), drawn read-only inside the ghost bar. [] when the
		# studio hasn't scoped this trigger in (no open pair / not selected).
		"pips": pips,
		# ADR-0085 anchor: authoring-only offset of the audible HIT into the sound's real
		# length. Carried off the live kf — never moves `start`, dropped when lowering.
		"anchor_offset": int(kf.get("anchor_offset", 0)) if kf is Dictionary else 0,
		"color": SOUND_COLOR,
		"fields": _sound_kf_fields(kf if kf is Dictionary else {}, ci),
	}


## A span's rightmost extent on the frame axis: its `end`, plus a sound trigger's
## read-only ghost bar (which reaches `start + ghost_frames` past the instant). Used
## to size the axis and phase sections so ghost bars stay inside their band.
static func _span_extent(span: Dictionary) -> int:
	return maxi(int(span.get("end", 0)),
		int(span.get("start", 0)) + int(span.get("ghost_frames", 0)))


## The sound projector's field-set, read straight off a live sound keyframe dict.
## Shared by the span builder AND live re-projection. `channel` is lane identity
## (the channel_index), not an authored value.
static func _sound_kf_fields(kf: Dictionary, ci: int) -> Dictionary:
	return {
		"channel": ci,
		"sound_id": int(kf.get("sound_id", 0)),
		"duration_frames": int(kf.get("duration_frames", 0)),
		"anchor_offset": int(kf.get("anchor_offset", 0)),
	}


# --- Phase sections -------------------------------------------------------

## A ruler section per phase that has at least one lane, from the phase offset to
## the far end of that phase's spans. Sections can overlap in X (phase2 over
## for-each) — that overlap is the point (CONTEXT: overlapping X-bands).
static func _phase_sections(effect_data, lanes: Array) -> Array:
	var out: Array = []
	# A `1-phase` script (ADR-0094) runs the for-each only; its phase-1/phase-2 timeline
	# data is DORMANT (kept, no longer ticked), so the score hides those sections. A swap
	# back to `3-phase` re-detects and restores them.
	var for_each_only := false
	if effect_data != null and effect_data.script_ops is Array and not effect_data.script_ops.is_empty():
		for_each_only = EffectScriptPattern.detect(effect_data.script_ops) == EffectScriptPattern.P_1PHASE
	for phase in EffectPhaseClass.ALL:
		if for_each_only and phase != EffectPhaseClass.PHASE_FOR_EACH:
			continue
		var start := phase_offset(effect_data, phase)
		var end := start
		var has_lane := false
		for lane in lanes:
			if lane["phase"] != phase:
				continue
			has_lane = true
			for span in lane["spans"]:
				# Exclude the sound terminator (ADR-0085 Amendment 2026-08-10) — its long silent tail
				# would balloon the section band past the real content; it renders at its
				# true frame regardless, reachable by pan/zoom.
				if str(span.get("role", "")) == "terminator":
					continue
				end = maxi(end, _span_extent(span))
		if not has_lane:
			continue
		out.append({
			"name": phase,
			"label": _phase_label(phase),
			"start": start,
			"end": end,
		})
	return out


static func _phase_label(phase: String) -> String:
	match phase:
		EffectPhaseClass.PHASE1: return "Phase 1"
		EffectPhaseClass.PHASE_FOR_EACH: return "For-each"
		EffectPhaseClass.PHASE2: return "Phase 2"
	return phase


# --- Shared helpers -------------------------------------------------------

## A stable, well-separated hue per emitter index — the emitter-hued span fill.
## Golden-ratio hue stepping keeps adjacent emitter indices visually distinct.
static func emitter_color(emitter_index: int) -> Color:
	if emitter_index < 0:
		return Color(0.5, 0.5, 0.5)
	var hue := fmod(float(emitter_index) * 0.61803398875, 1.0)
	return Color.from_hsv(hue, 0.55, 0.9)


## Fixed, distinct hues for the three camera sub-channels so a glance separates an
## angle move from a position dolly from a zoom.
static func camera_color(channel_name: String) -> Color:
	match channel_name:
		"angle": return Color(0.35, 0.75, 0.85)      # cyan
		"position": return Color(0.45, 0.60, 0.95)   # blue
		"zoom": return Color(0.70, 0.55, 0.90)       # violet
	return Color(0.5, 0.6, 0.8)


## Render a generic **inspection target** (ADR-0073): dispatch on target KIND through the
## projector registry. A span resolves to today's archetype dispatch (below); an emitter
## renders the bare emitter view. The registry is `load()`ed (not preloaded) so this file
## keeps no parse-time dependency on the projector graph. `score` lets a span-kind projector
## resolve its opaque `span_id` ref back to the laid-out span; `effect_data` is the parsed
## source both kinds read.
static func inspector_header(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var Registry = load("res://src/effects/studio/InspectorProjectorRegistry.gd")
	return Registry.header(target, effect_data, score)


static func inspector_sections(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var Registry = load("res://src/effects/studio/InspectorProjectorRegistry.gd")
	return Registry.sections(target, effect_data, score)


## The span's archetype-INDEPENDENT context header — the four rows every span kind shares
## (Kind / Phase / Frames / Authored), rendered above the projector sections. The
## kind-specific detail is the projectors' job (span_sections), NOT a per-kind switch here
## (ADR-0071). Owned by the SpanProjector (ADR-0073). Read-only display strings.
static func span_header_rows(span: Dictionary) -> Array:
	# A point marker (camera_compiled storage view) lands AT one frame, not across a range —
	# show a single frame so "8" doesn't read as the misleading interval "8–8".
	if span.get("marker", false):
		return [
			{"label": "Kind", "value": _kind_label(span.get("kind", ""))},
			{"label": "Phase", "value": _phase_label(span.get("phase", ""))},
			{"label": "Frame", "value": "%d" % span.get("start", 0)},
			{"label": "Authored", "value": "%d" % span.get("authored_start", 0)},
		]
	return [
		{"label": "Kind", "value": _kind_label(span.get("kind", ""))},
		{"label": "Phase", "value": _phase_label(span.get("phase", ""))},
		{"label": "Frames", "value": "%d–%d" % [span.get("start", 0), span.get("end", 0)]},
		{"label": "Authored", "value": "%d–%d" % [span.get("authored_start", 0), span.get("authored_end", 0)]},
	]


## Dispatch a selected span to its per-archetype projector → the inspector's `[Section]`
## list (ADR-0071). The god-switch is gone: each arm only ROUTES to a cohesive projector
## that owns its own field-set. A particle span concatenates its Event section with the
## SHARED emitter's grouped sections; a screen tween resolves back to its keyframe so the
## projector can pick Blend vs Gradient; the rest project their own inline fields.
static func span_sections(span: Dictionary, effect_data) -> Array:
	match span.get("kind", ""):
		"particle": return EmitterProjector.sections(span, effect_data)
		"screen":
			var kf = _screen_keyframe(span, effect_data)
			# Thread the span's write-side address (phase = channel context, keyframe index)
			# so the projector's editable colour cell carries field_refs into the #255 choke
			# point — PLUS the score-build spacer verdict (ADR-0087 decs. 17-22): the
			# projector can't fold context from one keyframe, and the snapshot is never
			# stale because every verdict-affecting edit rebuilds the score.
			var field_ctx := {"context": span.get("phase", ""),
				"event_index": int(span.get("keyframe_index", -1)),
				"spacer": span.get("fields", {}).get("spacer", false)}
			return ScreenTweenProjector.sections(kf, field_ctx) if kf != null else []
		"palette": return PaletteTweenProjector.sections(_live_span(span, effect_data))
		"camera": return CameraTweenProjector.sections(_live_span(span, effect_data))
		"camera_compiled": return CameraCompiledProjector.sections(span)
		"sound": return SoundTriggerProjector.sections(_live_span(span, effect_data))
	return []


## Re-read the span's `fields` from the LIVE keyframe before projecting, so the
## inspector reflects the current data — not the snapshot captured when the score was
## built. Screen already resolves live (via _screen_keyframe); this does the same for
## camera / palette / sound at their shared choke point, killing the class of desync
## where an edit folded the keyframe but a re-select showed the old value (#267). The
## address keys (phase / keyframe_index / channel identity) are stable, so only
## `fields` is refreshed; on a resolution miss we fall back to the snapshot.
static func _live_span(span: Dictionary, effect_data) -> Dictionary:
	var live := _live_fields(span, effect_data)
	if live.is_empty():
		return span
	var s: Dictionary = span.duplicate()   # shallow copy; `fields` is replaced wholesale
	s["fields"] = live
	return s


## Rebuild a span's projector fields from the live keyframe it addresses, dispatched by
## kind. Returns {} when the keyframe can't be resolved (caller falls back to the snapshot).
static func _live_fields(span: Dictionary, effect_data) -> Dictionary:
	if effect_data == null:
		return {}
	match span.get("kind", ""):
		"camera":
			var camera = effect_data.camera
			if camera == null or not camera.has_table(span.get("phase", "")):
				return {}
			var kf = camera.get_table(span.get("phase", "")).get_keyframe(int(span.get("keyframe_index", -1)))
			if kf == null:
				return {}
			return _camera_kf_fields(kf, str(span.get("fields", {}).get("camera_channel", "")))
		"palette":
			var pal = effect_data.palette
			if pal == null:
				return {}
			var channel_name := str(span.get("fields", {}).get("channel", ""))
			var ch = pal.get_channel(span.get("phase", ""), channel_name)
			if ch == null:
				return {}
			var kf = ch.get_keyframe(int(span.get("keyframe_index", -1)))
			if kf == null:
				return {}
			# The verdict rides the SNAPSHOT: every verdict-affecting edit flags layout
			# (fourth amendment decision 4), so the score — and this span's fields —
			# was rebuilt before any re-projection can observe a stale verdict.
			return _palette_kf_fields(kf, channel_name,
				bool(span.get("fields", {}).get("spacer", false)))
		"sound":
			var kf = _resolve_sound_keyframe(effect_data, span)
			if kf == null:
				return {}
			return _sound_kf_fields(kf, int(span.get("channel_index", -1)))
	return {}


## Walk EffectData.sound to the raw keyframe dict the span addresses — the SAME
## positional path the write-side SoundChannel._resolve_keyframe takes (channel by
## index, then keyframe by index), so read and write agree on which keyframe is live.
static func _resolve_sound_keyframe(effect_data, span: Dictionary):
	var sound = effect_data.sound
	if not (sound is Dictionary):
		return null
	var channels = sound.get(span.get("phase", ""), null)
	if not (channels is Array):
		return null
	var ci: int = int(span.get("channel_index", -1))
	if ci < 0 or ci >= channels.size() or not (channels[ci] is Dictionary):
		return null
	var kfs = channels[ci].get("keyframes", null)
	if not (kfs is Array):
		return null
	var ei: int = int(span.get("keyframe_index", -1))
	if ei < 0 or ei >= kfs.size() or not (kfs[ei] is Dictionary):
		return null
	return kfs[ei]


## Resolve a screen span back to the ScreenData.Keyframe it draws (phase + index) so
## the screen projector can read the kind (Blend/Gradient) and its live fields.
static func _screen_keyframe(span: Dictionary, effect_data):
	if effect_data == null or effect_data.screen == null:
		return null
	var ch = effect_data.screen.get_channel(span.get("phase", ""))
	if ch == null:
		return null
	return ch.get_keyframe(int(span.get("keyframe_index", -1)))


static func _kind_label(kind: String) -> String:
	match kind:
		"particle": return "Particle"
		"screen": return "Screen"
		"palette": return "Map/unit tint"
		"camera": return "Camera"
		"sound": return "Sound"
	return kind


static func _color_hex(c: Color) -> String:
	return "#%02X%02X%02X" % [int(round(c.r * 255)), int(round(c.g * 255)), int(round(c.b * 255))]


## Project ONE emitter into the keyframe inspector's grouped param view — the seam
## that replaces the old "keyframe → flat curve list" shortcut. Groups its params by
## WHAT THEY CHARACTERIZE (CONTEXT "Emitter field / Particle field"): the emission,
## the born-with particle traits, the over-life traits, then the config constants.
## Each param row is `{ name, shape, from, to, value, curve_index, enabled }`:
##   shape ∈ vec3 | range | vec3_range | int | curve_only | const
##   curve_index = this param's own curve nibble (em.curves[key] / color_curves[ch]),
##     -1 = none; enabled = curve_index ≥ 0. The curve HANGS OFF THE PARAM (never the
##     keyframe): no curve ⇒ the row is DISABLED (its `to` is inert) but its values
##     stay present — the view greys them, it does not hide them.
## Pure projection (display strings), consumed by EmitterProjector.sections (which
## wraps these groups as `[Section]`, ADR-0071). Read-only; the opaque callback_params
## bag is intentionally omitted (door #2 — un-modeled until
## the callbacks are decoded).
static func emitter_view(effect_data, emitter_index: int,
		evolution_window: int = -1, window_note: String = "") -> Array:
	var out: Array = []
	if effect_data.emitters == null or emitter_index < 0 or emitter_index >= effect_data.emitters.size():
		return out
	var em = effect_data.emitters[emitter_index]

	# Editable two-axis parameter groups (ADR-0089): both surfaces that reach this
	# view (span inspector + bare emitter browser) edit the SHARED emitter through
	# the same rows — the group builder seeds RAW values and emitter-channel refs.
	# `evolution_window` is the used curve window (decision 5) for the emitter-
	# elapsed clock: the surface supplies it (span = that firing's duration,
	# browser = the widest firing); -1 = unknown → sparklines stay fully bright.
	# The DISTINCT SHAPE SET, not the curve array (ADR-0089 curve-ownership amendment). Post
	# explode an effect holds a median of 22 curves drawing a median of 8 distinct shapes, and
	# the picker browses shapes: a grid of 22 tiles showing 8 pictures is worse than what
	# shipped. Counting the array where the shape set is meant is the mistake this design is
	# most likely to grow, so the two never share a variable.
	var shapes: Array = CurveShapeSet.shapes(effect_data)

	# Clock-domain tag (ADR-0089 amendment — span-anchored playhead marker): the Emitter
	# group + Particle · born-with are sampled at ActiveEmitter.elapsed_frames (at spawn),
	# so their curves map single-valued to the playhead and carry the span-anchored marker.
	# The over-life section (below) is sampled per-particle by age → clock "age", no marker.
	var emitter_rows: Array = []
	for key in ["position", "spread", "particle_count", "spawn_interval"]:
		emitter_rows += EmitterParamRows.group(em, emitter_index, key, shapes,
			evolution_window, window_note)
	out.append({"title": "Emitter", "params": emitter_rows, "clock": "emitter"})

	var born_rows: Array = []
	for key in ["velocity_base_angle", "velocity_direction_spread", "radial_velocity",
			"weight", "drag", "acceleration", "inertia", "lifetime", "homing_strength",
			"target_offset"]:
		born_rows += EmitterParamRows.group(em, emitter_index, key, shapes,
			evolution_window, window_note)
	out.append({"title": "Particle · born-with", "params": born_rows, "clock": "emitter"})

	# Over-life rows sample by PARTICLE AGE, not emitter-elapsed frame: their
	# window is the max authored lifetime, the same on every surface. Lifetime −1
	# is the animation-driven sentinel → no dimming, honest tooltip.
	#
	# THE RULE MOVED OUT (ADR-0089 colour-move amendment, 2026-08-20). It was inline here,
	# which was fine while the inspector was the only surface with an over-life axis. The
	# editable colour track now lives in the PLAYER COLUMN, so a second copy would decide
	# the same emitter's axis twice — and the two candidate windows are not
	# interchangeable: of 2622 colour-enabled corpus emitters they disagree for 1204
	# (45.9%), 698 of them by more than 8 frames. A drift here does not nudge a keyframe,
	# it relocates it. `EmitterLifeWindowTest` holds this call to the rule as written.
	var life_window: Dictionary = EmitterLifeWindow.for_emitter(em, effect_data)
	var life_n: int = int(life_window["n"])
	var life_note: String = str(life_window["note"])
	# The Colour ribbon payload (CONTEXT.md "Colour ribbon"): the read-only resolved-colour
	# bar the inspector draws under these three curves. Carries the r/g/b curve indices, the
	# colour-enabled flag the RENDERER keys on (so preview and paint agree on when colour is
	# live), and the particle-age window. The inspector resolves the curves via curve_provider.
	out.append({"title": "Particle · over-life", "params": [
		EmitterParamRows.color_curve_row(em, emitter_index, "r", shapes, life_n, life_note),
		EmitterParamRows.color_curve_row(em, emitter_index, "g", shapes, life_n, life_note),
		EmitterParamRows.color_curve_row(em, emitter_index, "b", shapes, life_n, life_note),
		EmitterParamRows.curve_row(em, emitter_index, "Homing blend · curve",
			"curve_homing_blend", shapes, life_n, life_note),
	], "clock": "age", "ribbon": {
		"emitter_index": emitter_index,  # colour authoring targets this emitter's channels
		"r": int(em.color_curves.get("r", -1)),
		"g": int(em.color_curves.get("g", -1)),
		"b": int(em.color_curves.get("b", -1)),
		"enabled": bool(em.flags.get("color_curve_enabled", false)),
		"used_n": life_n,
		# The emitter's representative sprite colour — the ribbon MULTIPLIES the resolved curve
		# by it (renderer's ALBEDO = sprite.rgb * modulate.rgb) so the read-out is the colour the
		# particle actually IS, not the pure curve. White when there's no texture (identity mux).
		"sprite_base": EmitterSpriteColor.representative(effect_data, emitter_index),
	}})

	# Config: the packed control bytes decomposed into named editable enums
	# (ADR-0089 tier 1 — camera-command-word style; unread bits stay unexposed and
	# byte-preserved), the DERIVED "Velocity mode" const (recomputed on relayout),
	# the ADR-0073/0075 child navigation links, and the child-wiring pickers.
	var n_emitters: int = effect_data.emitters.size() if effect_data.emitters != null else 0
	var config_rows: Array = [
		_animation_set_row(em, emitter_index, effect_data),
		_frameset_group_row(em, emitter_index, effect_data),
	]
	config_rows += EmitterParamRows.packed_config_rows(em, emitter_index)
	config_rows.append(_const_param("Velocity mode", _velocity_mode_name(em)))
	config_rows += EmitterParamRows.child_picker_rows(em, emitter_index, n_emitters)
	config_rows.append(_child_emitter_param("Child on death", em.child_emitter_on_death,
		emitter_index, "death", em.is_child_death_enabled()))
	config_rows.append(_child_emitter_param("Child mid-life", em.child_emitter_mid_life,
		emitter_index, "midlife", em.is_child_midlife_enabled()))
	out.append({"title": "Config", "params": config_rows})

	# Tier 2/3 honesty (ADR-0089): real-but-opaque callback params + reserved bytes.
	#
	# SHUT ON ARRIVAL, and it carries a fold id so it stays however the author left it.
	# The rows are honest but they are not what an author clicks an emitter to see, and
	# the inspector row is ~268px tall — a section that is open by default spends that
	# height on the one group whose whole premise is "opaque". The id is CONSTANT, not
	# per-emitter: "I have opened Advanced" is a statement about the author's session,
	# not about emitter 3, and a per-emitter key would re-shut it on every selection.
	# Without an id at all the `collapsed` hint would win on every rebuild and the
	# author would re-open it forever (`EffectKeyframeInspector._build_group`).
	out.append({"title": "Advanced (raw)", "fold_id": "emitter-advanced", "collapsed": true,
		"params": EmitterParamRows.advanced_rows(em, emitter_index)})

	# Field-relevance salience (ADR-0089 amendment): stamp every group + gated/gate
	# field with the oracle's verdict, so the inspector reads as "what is actually
	# in effect". Supersedes the ad-hoc "dim all-zero groups" heuristic.
	_attach_relevance(out, EmitterFieldRelevance.verdicts(em))

	# Velocity-family formula view (ADR-0089 velocity amendment): when the launch
	# direction / outward speed are Dead by mode-annihilation, stamp the descriptor on
	# the section that owns the velocity groups so the inspector renders it once under
	# that section's hidden-Dead reveal. Empty (whole family Live) → no stamp.
	_attach_velocity_formula(out, EmitterFieldRelevance.velocity_formula(em))

	return out


## The emitter's "what do I play" row (ADR-0073 dec. 9) — the head of the
## drill-down chain emitter → sequence → frameset → frame.
##
## It stays the ADR-0089 tier-1 editable `anim_index` spinbox and grows ONE follow button.
## One, not two: `anim_index` names a place (`effect_data.animations[i]`) but `anim_param`
## ("Frameset group") does not — there is no group target kind, and there should not be.
## The group is the LENS the sequence's FRAME opcodes resolve through, so the two fields
## jointly parameterize a single destination, `animation(anim_index, anim_param)`. The
## button therefore names the RESOLVED target ("sequence 4 · group 1"), which is what makes
## editing the Frameset group row below it visibly re-aim this one.
##
## A dangling anim_index (a u8 with no validity guarantee) disables the follow and wears the
## ADR-0089 `relevance` dead marker naming the offending index — the spinbox stays live so
## the author fixes it in place. The relevance oracle has no verdict for anim_index, so
## `_attach_relevance` will not overwrite this stamp.
static func _animation_set_row(em, emitter_index: int, effect_data) -> Dictionary:
	var row := EmitterParamRows.int_row(em, emitter_index, "Animation set", "anim_index", "u8")
	var anim_index := int(row.get("value", -1))
	var group := int(EmitterChannel.read_raw(em, "anim_param"))
	var n: int = effect_data.animations.size() if effect_data.animations is Array else 0
	if anim_index < 0 or anim_index >= n:
		row["follow"] = {"disabled": true}
		row["relevance"] = {"state": "dead",
			"why": "anim_index %d points at no sequence — this effect has %d." % [anim_index, n]}
		return row
	row["follow"] = {
		"label": "sequence %d · group %d" % [anim_index, group],
		"target": InspectionTarget.animation(anim_index, group),
		"tooltip": "Open sequence %d as this emitter plays it — its FRAME opcodes resolve "
			% anim_index
			+ "through frameset group %d (shift %d). Change 'Frameset group' below to re-aim."
			% [group, effect_data.frameset_group_offset(group)],
	}
	return row


## The lens row beside the drill-down head. Carries no follow of its own — `anim_param`
## selects the frameset GROUP the sequence's FRAME opcodes index into, which is not a place
## (there is no group target kind); it re-aims the "Animation set" button above it. The
## tooltip says so, because two adjacent u8 spinboxes give no hint that one steers the other.
static func _frameset_group_row(em, emitter_index: int, effect_data) -> Dictionary:
	var row := EmitterParamRows.int_row(em, emitter_index, "Frameset group", "anim_param", "u8")
	var group := int(row.get("value", 0))
	var n: int = effect_data.frameset_group_offsets.size() \
		if effect_data.frameset_group_offsets is Array else 1
	var shift: int = effect_data.frameset_group_offset(group)
	row["tooltip"] = ("Which frameset GROUP this emitter's sequence indexes into: its FRAME "
		+ "opcodes store frameset numbers RELATIVE to the group, shifted by %d here. " % shift
		+ "Re-aims the 'Animation set' link above — it is a lens on the sequence, not a "
		+ "place of its own. This effect has %d group%s. raw: anim_param"
		% [n, "" if n == 1 else "s"])
	if group < 0 or group >= n:
		row["relevance"] = {"state": "dead",
			"why": "anim_param %d names no frameset group — this effect has %d (no shift applied)."
				% [group, n]}
	return row


## Stamp the velocity-family formula descriptor (or nothing, when empty) on whichever
## section owns a velocity group — the inspector reads `velocity_formula` off the
## section and renders it once under that section's Dead reveal.
static func _attach_velocity_formula(sections: Array, formula: Dictionary) -> void:
	if formula.is_empty():
		return
	for section in sections:
		for row in section.get("params", []):
			var gid := str(row.get("group", {}).get("id", ""))
			if gid in ["velocity_base_angle", "velocity_direction_spread", "radial_velocity"]:
				section["velocity_formula"] = formula
				return


## Attach EmitterFieldRelevance verdicts onto the built emitter sections: each
## parameter group's shared stamp gets `relevance` (whole/end-axis state + gate
## edges); each lone over-life / config gate + gated field gets a row-level
## `relevance`. Matching is by the group id already on the stamp and the field
## name already on the row's field_ref (the ONE field→storage map).
static func _attach_relevance(sections: Array, rel: Dictionary) -> void:
	var groups: Dictionary = rel.get("groups", {})
	var fields: Dictionary = rel.get("fields", {})
	for section in sections:
		for row in section.get("params", []):
			var stamp: Dictionary = row.get("group", {})
			if not stamp.is_empty() and groups.has(stamp.get("id", "")):
				stamp["relevance"] = groups[stamp["id"]]
			var key := _relevance_field_key(row)
			if key != "" and fields.has(key):
				row["relevance"] = fields[key]


## The oracle `fields` key a row addresses, or "" for none. Reads the row's explicit
## `relevance_key`, else its own field_ref (edit rows), else its first cell's field_ref
## (cells strips). The homing blend curve field maps to the oracle's "homing_blend" key.
static func _relevance_field_key(row: Dictionary) -> String:
	# An explicit key wins — a row can address a verdict it cannot name through a field_ref.
	# Link rows (child navigation) carry a `target`, not an edit field; a CURVE row addresses
	# a use site — (emitter, slot) on the `curve_assign` channel — not an emitter field name,
	# since the ADR-0089 curve-ownership amendment changed its verb from assign to copy.
	var field := ""
	if row.has("relevance_key"):
		field = str(row["relevance_key"])
	elif row.has("field_ref"):
		field = str(row["field_ref"].get("field", ""))
	else:
		var cells: Array = row.get("cells", [])
		if not cells.is_empty() and cells[0] is Dictionary and cells[0].has("field_ref"):
			field = str(cells[0]["field_ref"].get("field", ""))
	return "homing_blend" if field == "curve_homing_blend" else field


## The **incoming edges** that reach an emitter (ADR-0073) — the INVERSE of a link, for
## the bare-emitter header. Enumerates every edge that spawns/references this emitter as a
## clickable header row (reverse navigation), fixing the misleading "shared by 0 events" a
## child-only emitter showed under the keyframe-count model:
##   • KEYFRAME edges — particle spans whose emitter_index == this one → a link to the span.
##   • ON-DEATH / MID-LIFE parents — emitters that spawn it (invert child_emitter_*) → a link
##     to the parent emitter's bare view.
##   • CALLBACK edges are NOT statically derivable — `spawn_child_from_callback` takes its
##     index from callback logic at runtime, and there is no static callback→emitter field
##     (ADR-0073 limitation). So an emitter with no keyframe/parent edge shows a flagged,
##     NON-link note (it may still be spawned by a callback, or be dead data) rather than a
##     fabricated reverse link.
## Rows are header rows: `{label, link:{label, target}}` for an edge, `{label, value}` for
## the note. Score supplies the spans; effect_data supplies the parent emitters.
static func emitter_provenance(effect_data, score, emitter_index: int) -> Array:
	var rows: Array = []
	if effect_data == null or emitter_index < 0:
		return rows

	# Keyframe edges — every particle span that references this emitter.
	if score != null and score.has("lanes"):
		for lane in score["lanes"]:
			if lane.get("kind", "") != "particle":
				continue
			for span in lane["spans"]:
				if int(span.get("emitter_index", -2)) == emitter_index:
					rows.append({"label": "Spawned by kf", "link": {
						"label": "%s @%d" % [str(lane.get("id", "")), int(span.get("start", 0))],
						"target": InspectionTarget.span(str(span.get("id", "")))}})

	# Parent edges — emitters that spawn this one on death / at mid-life (invert children).
	if effect_data.emitters != null:
		for i in range(effect_data.emitters.size()):
			var em = effect_data.emitters[i]
			if int(em.child_emitter_on_death) == emitter_index:
				rows.append({"label": "Death-child of", "link": {
					"label": "emitter %d" % i, "target": InspectionTarget.emitter(i)}})
			if int(em.child_emitter_mid_life) == emitter_index:
				rows.append({"label": "Mid-life-child of", "link": {
					"label": "emitter %d" % i, "target": InspectionTarget.emitter(i)}})

	# No static edge → callback-spawned or dead data (the honest, non-link signal).
	if rows.is_empty():
		rows.append({"label": "Incoming", "value": "none static — may spawn via callback at runtime"})
	return rows


static func _curve_of(em, key: String) -> int:
	return int(em.curves.get(key, -1))


## Base row skeleton — every param carries the same keys so the view reads them
## uniformly; enabled follows the curve-presence bit (the load-bearing gate).
static func _param_base(name: String, shape: String, curve_index: int) -> Dictionary:
	return {"name": name, "shape": shape, "curve_index": curve_index,
		"enabled": curve_index >= 0, "from": "", "to": "", "value": ""}


static func _vec3_param(em, name: String, key: String, start: Vector3, end_: Vector3) -> Dictionary:
	var p := _param_base(name, "vec3", _curve_of(em, key))
	p["from"] = _fmt_vec3(start)
	p["to"] = _fmt_vec3(end_)
	return p


static func _int_param(em, name: String, key: String, start: int, end_: int) -> Dictionary:
	var p := _param_base(name, "int", _curve_of(em, key))
	p["from"] = str(start)
	p["to"] = str(end_)
	return p


static func _range_param(em, name: String, key: String, min_s: float, max_s: float, min_e: float, max_e: float) -> Dictionary:
	var p := _param_base(name, "range", _curve_of(em, key))
	p["from"] = _fmt_range(min_s, max_s)
	p["to"] = _fmt_range(min_e, max_e)
	return p


static func _vec3_range_param(em, name: String, key: String, min_s: Vector3, max_s: Vector3, min_e: Vector3, max_e: Vector3) -> Dictionary:
	var p := _param_base(name, "vec3_range", _curve_of(em, key))
	p["from"] = _fmt_vec3_range(min_s, max_s)
	p["to"] = _fmt_vec3_range(min_e, max_e)
	return p


## An over-life particle trait animated over its OWN life — carries only a curve
## (no from/to), read each frame. Color channels and homing blend live here.
static func _curve_only_param(em, name: String, key: String) -> Dictionary:
	return _param_base(name, "curve_only", _curve_of(em, key))


static func _color_param(name: String, curve_index: int) -> Dictionary:
	return _param_base(name, "curve_only", int(curve_index))


## A config constant: no from/to/curve, just a settled value (enabled is always
## false — a constant has no glide to drive).
static func _const_param(name: String, value: String) -> Dictionary:
	var p := _param_base(name, "const", -1)
	p["value"] = value
	return p


## A child-emitter config row: a LINK to that emitter's bare view when it spawns one
## (ADR-0073 — the fix for the dead-end "Child on death: 5" integer), or a plain "none"
## constant when it doesn't. This is what makes the child emitter reachable from a parent.
##
## On a LIVE edge (a real child index AND the authored spawn flag on) the link also
## carries a `toggle` payload `{parent_index, edge}` (ADR-0075) — the inspector renders a
## checkbox there to suppress that parent's spawn of that child. The model only MARKS
## toggleability; it never holds the suppressed state (that lives sim-side). Authored-off
## edges and "none" rows carry no toggle, matching the D1 "off-only, live-edges-only" rule.
static func _child_emitter_param(name: String, child_index: int, parent_index: int, edge: String, authored_enabled: bool) -> Dictionary:
	# The oracle verdict key this row addresses. A LINK row carries a `target`, not a
	# `field_ref.field`, so _attach_relevance cannot match it by field name — tag it explicitly
	# so a disabled child mode deads the navigation link too, not just the editable index row.
	var rel_key := "child_emitter_on_death" if edge == "death" else "child_emitter_mid_life"
	var p: Dictionary
	if child_index < 0:
		p = _const_param(name, "none")
	else:
		p = _link_param(name, "emitter %d" % int(child_index), InspectionTarget.emitter(int(child_index)))
		if authored_enabled:
			p["toggle"] = {"parent_index": int(parent_index), "edge": edge}
	p["relevance_key"] = rel_key
	return p


## A clickable **link** field (ADR-0073): a config row whose value follows a reference
## to another inspectable object. Shares the const 2-column layout (the inspector renders
## the value cell as a navigate button). `label` is the shown text, `target` the
## InspectionTarget to open.
static func _link_param(name: String, label: String, target: Dictionary) -> Dictionary:
	var p := _param_base(name, "link", -1)
	p["label"] = label
	p["target"] = target
	return p


## Trim a float to a compact, deterministic display string (no trailing zeros;
## "-0"/"" → "0"). Keeps tiny converted values legible without a fixed decimal count.
static func _fmt_num(v: float) -> String:
	var s := "%.4f" % v
	if "." in s:
		s = s.rstrip("0").rstrip(".")
	if s == "" or s == "-0":
		return "0"
	return s


static func _fmt_vec3(v: Vector3) -> String:
	return "(%s, %s, %s)" % [_fmt_num(v.x), _fmt_num(v.y), _fmt_num(v.z)]


## A [min, max] range each spawned particle draws within (the stochastic spread).
static func _fmt_range(lo: float, hi: float) -> String:
	return "%s – %s" % [_fmt_num(lo), _fmt_num(hi)]


static func _fmt_vec3_range(lo: Vector3, hi: Vector3) -> String:
	return "lo%s hi%s" % [_fmt_vec3(lo), _fmt_vec3(hi)]


## The particle VELOCITY MODE — the `velocity_inward` + `align_to_facing` flag pair
## (emitter bytes 0x06-0x07, mask 0x0410) that decides how a spawned particle's initial
## velocity VECTOR is built. Distinct from `align_to_velocity` (which rotates the rendered
## sprite quad). See research/wiki_articles/velocity_mode_unit_oriented.txt for the encoding:
##   neither → OUTWARD, inward-only → INWARD, both → OUTWARD_UNIT_ORIENTED,
##   facing-only → SKIP (unimplemented on PSX; particle keeps zero velocity).
static func _velocity_mode_name(em) -> String:
	var inward: bool = em.flags.get("velocity_inward", false)
	var facing: bool = em.flags.get("align_to_facing", false)
	if inward and facing:
		return "OUTWARD_UNIT_ORIENTED"
	if inward:
		return "INWARD"
	if facing:
		return "SKIP"
	return "OUTWARD"


static func _anchor_name(mode) -> String:
	match mode:
		EffectEmitter.AnchorMode.CURSOR: return "CURSOR"
		EffectEmitter.AnchorMode.ORIGIN: return "ORIGIN"
		EffectEmitter.AnchorMode.TARGET: return "TARGET"
		EffectEmitter.AnchorMode.PARENT: return "PARENT"
		EffectEmitter.AnchorMode.CAMERA: return "CAMERA"
	return "WORLD"


## A one-line, copy-to-clipboard **keyframe address** — the string a user pastes to
## reference exactly one keyframe when talking to a collaborator/agent. Every token
## maps back to code: `effect` is the effect dir (E317), `lane_id` encodes
## phase+kind+channel (`particle:for_each:2`), `kf#N` is the event's **address within
## that lane**, `fA–B` is the absolute frame range, then a kind-specific payload
## (emitter/flags, tint hex, or rgb/blend). Empty span → "".
##
## `kf#N` is exactly the token the span **id** carries, so `<lane_id>#<N>` reconstructs the
## id a pasted address must resolve through — which is why it is NOT always the raw storage
## index. CAMERA sub-channel lanes address by ORDINAL (ADR-0086 dec. 5, #286): `lower` re-packs the
## flat keyframe array on every split/merge, so the raw slot goes stale, and printing it here
## made an address point at a DIFFERENT event (E317 for_each angle: the 2nd event sits at raw
## slot 3, and `#3` is a real — but wrong — span). The amendment named selection and undo as
## the address's two consumers; this was an unenumerated third. The raw slot survives as
## `slot N` in the camera payload — it is what the compiled lane and a hex dump show, and it
## is useful provenance; it is simply never the address.
static func keyframe_address(effect_label: String, span: Dictionary) -> String:
	if span.is_empty():
		return ""
	# The lane-local ADDRESS: the ordinal where a kind defines one (camera sub-channels), else
	# the raw keyframe index — which for the lane-event-atomic kinds IS the ordinal.
	var address: int = int(span.get("ordinal", span.get("keyframe_index", -1)))
	var head := "%s · %s · kf#%d · f%d–%d" % [
		effect_label, span.get("lane_id", "?"), address,
		int(span.get("start", 0)), int(span.get("end", 0))]
	var f: Dictionary = span.get("fields", {})
	var tail := ""
	match span.get("kind", ""):
		"particle":
			tail = "emitter idx%d (id%d) · flags 0x%02X" % [
				int(f.get("emitter_index", -1)), int(f.get("emitter_id", 0)),
				int(f.get("action_flags", 0))]
		"screen":
			tail = "TINT %s · blend %d" % [
				_color_hex(span.get("color", Color.BLACK)), int(f.get("blend_mode", 0))]
		"palette":
			var rgb = f.get("rgb", Vector3i.ZERO)
			tail = "rgb(%d,%d,%d) · blend %d" % [rgb.x, rgb.y, rgb.z, int(f.get("blend_mode", 0))]
		"camera":
			# `slot` is the RAW storage index — provenance, not the address (see above). It is
			# what the compiled lane draws and what a byte dump shows, so an address that omits
			# it loses the bridge between the authoring view and the packed table.
			tail = "%s · %s · %s · slot %d" % [
				str(f.get("camera_channel", "")), str(f.get("source_mode", "")),
				str(f.get("interpolation", "")), int(span.get("keyframe_index", -1))]
		"sound":
			# ADR-0085: a trigger is an instant, so its `duration_frames` is the GAP to the
			# next trigger — labelled `gap`, never `dur` (it is not the sound's length).
			tail = "sid %d · gap %d" % [int(f.get("sound_id", 0)), int(f.get("duration_frames", 0))]
	return "%s · %s" % [head, tail] if tail != "" else head


## Find a span anywhere in the score by its stable id, or {} if absent.
static func find_span(score: Dictionary, span_id: String) -> Dictionary:
	for lane in score["lanes"]:
		for span in lane["spans"]:
			if span["id"] == span_id:
				return span
	return {}


# --- Solo / Mute (Effect Studio audibility) -------------------------------

## Resolve the per-lane Solo/Mute selection into the exclusion filters the preview
## enforces. `muted` / `soloed` are set-style Dictionaries keyed by lane id. Returns:
##   {
##     "silenced_lanes":    { lane_id: true },        # the lanes the preview must ignore
##     "disabled_emitters": { emitter_index: true },  # particle projection (per-emitter)
##     "muted_screen":      { phase: true },
##     "muted_palette":     { "<phase>/<channel>": true },
##     "muted_sound":       { "<phase>:<ci>": true },  # per (phase, channel)
##   }
## DAW rule: a lane is silenced if it is MUTED, or if ANY solo is active and the lane
## is NOT soloed. Solo composes with mute — the soloed lane is audible unless it is
## also muted; everything un-soloed goes quiet. CAMERA lanes are display-only (framing,
## not content): they have no S/M and are never silenced, so a solo leaves the camera move
## playing. See has_mute_controls().
##
## Each muteable folded subsystem gets a PER-LANE exclusion filter (screen/palette/sound):
## muting one lane excludes ONLY that lane's events (its phase / phase+channel) from the
## subsystem's on-the-fly recompile, so a single M button does
## exactly what you'd expect and a rescrub re-derives without those events. (The old
## whole-subsystem gate that needed ALL a subsystem's lanes muted is gone.)
##
## `disabled_emitters` is the ONE exception — a VISIBILITY toggle, not an event exclusion
## (the renderer stops DRAWING these; particles keep simulating so positions/child-spawns
## stay correct — you asked for children to survive a parent's mute). It is the union of
## every emitter a silenced particle lane directly spawns, PLUS the transitive PURE-child
## closure (a muted emitter still spawns children the renderer would draw; E001: 53 of 57
## particles are child-spawned). The closure SKIPS any child with its own audible lane.
## Whether a lane KIND gets Solo/Mute controls (and participates in silencing). Camera is
## display-only — framing, not effect content — so it is excluded. Single source of truth
## for both the timeline gutter (which buttons to draw) and resolve_audibility.
static func has_mute_controls(kind: String) -> bool:
	# Both camera kinds are display-only: the sub-channel lanes are framing (not
	# content), and the compiled lane is a strictly read-only storage view.
	return kind != "camera" and kind != "camera_compiled"


static func resolve_audibility(score: Dictionary, muted: Dictionary, soloed: Dictionary) -> Dictionary:
	var any_solo := not soloed.is_empty()
	var silenced: Dictionary = {}
	var disabled_emitters: Dictionary = {}
	# Emitters directly spawned by an AUDIBLE particle lane — the child closure must not
	# hide these (they are governed by their own lane, not a muted parent's).
	var audible_direct: Dictionary = {}
	# Per-lane exclusion filters, one per muteable folded subsystem. Each muted lane's
	# EVENTS are excluded from that subsystem's on-the-fly recompile (build_stream / the
	# trigger dispatch); a rescrub then re-derives without them. Keys are the subsystem's
	# natural coordinates so it can build the same key without parsing lane ids:
	#   muted_screen:  { phase }                    (screen lane = screen:<phase>)
	#   muted_palette: { "<phase>/<channel>" }      (palette lane = palette:<phase>:<channel>)
	#   muted_sound:   { "<phase>:<ci>" }           (sound lane = sound:<phase>:<ci>; the addon
	#                                                trigger reports its firing phase, so the gate
	#                                                builds the same phase-scoped key)
	var muted_screen: Dictionary = {}
	var muted_palette: Dictionary = {}
	var muted_sound: Dictionary = {}
	for lane in score.get("lanes", []):
		var lane_id: String = lane["id"]
		var kind: String = lane.get("kind", "")
		# Camera is display-only (framing, not content): no S/M, never silenced.
		if not has_mute_controls(kind):
			continue
		var is_silenced := muted.has(lane_id) or (any_solo and not soloed.has(lane_id))
		if kind == "particle" and not is_silenced:
			for span in lane.get("spans", []):
				audible_direct[int(span.get("emitter_index", -1))] = true
		if not is_silenced:
			continue
		silenced[lane_id] = true
		var parts := lane_id.split(":")
		match kind:
			"particle":
				for span in lane.get("spans", []):
					disabled_emitters[int(span.get("emitter_index", -1))] = true
			"screen":
				muted_screen[parts[1]] = true
			"palette":
				muted_palette["%s/%s" % [parts[1], parts[2]]] = true
			"sound":
				# Phase-scoped, keyed "<phase>:<ci>" (like palette's "<phase>/<channel>"):
				# each phase carries its OWN channels 0/1/2 (E317: phase1/phase2/for_each all
				# do), so a bare channel-index key collides across phases — muting for_each:0
				# would also silence phase1:0/phase2:0, and soloing for_each:0 would silence
				# its cross-phase twins which then re-mute the soloed lane. The addon reports
				# the firing phase in pair_triggered so the gate can build this same key.
				muted_sound["%s:%d" % [parts[1], int(parts[2])]] = true
	# Cascade the mute to the pure-child closure (skipping children with their own audible
	# lane) — a muted emitter still simulates and spawns children the renderer would draw.
	_expand_child_closure(disabled_emitters, score.get("emitter_children", {}), audible_direct)
	return {
		"silenced_lanes": silenced,
		"disabled_emitters": disabled_emitters,
		"muted_screen": muted_screen,
		"muted_palette": muted_palette,
		"muted_sound": muted_sound,
	}


## Grow `disabled` (set of emitter indices) to include every emitter transitively spawned
## by an already-disabled one, per the `children` adjacency — EXCEPT children in
## `audible_direct` (they have their own audible lane and are governed by it, so a muted
## parent must not hide them; the walk also stops recursing through them). Iterative
## worklist; the already-in-`disabled`/`audible_direct` guards make cycles terminate.
static func _expand_child_closure(disabled: Dictionary, children: Dictionary,
		audible_direct: Dictionary) -> void:
	var stack: Array = disabled.keys()
	while not stack.is_empty():
		var e = stack.pop_back()
		for c in children.get(e, []):
			if audible_direct.has(c) or disabled.has(c):
				continue
			disabled[c] = true
			stack.append(c)
