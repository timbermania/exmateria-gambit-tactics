extends RefCounted
## The pure fold-equivalence SPACER oracle (ADR-0087 decs. 17-22): a spacer is an
## event whose **Disable is a visual no-op** — fold the channel's authored op stream
## WITH the event vs WITHOUT it (timing kept, which is exactly the runtime's disabled
## semantics: `PaletteSubsystem._each_keyframe` advances timing only; screen's disable
## byte-swap is the provably-transparent identity Blend) and compare **as colour
## transforms**: equal for every probe base, at every ramp breakpoint. Never "equal on
## the colour the studio currently shows" — the map/unit base varies per battle, and a
## hatch must survive a map change.
##
## The fold is the byte-exact CPU oracle (`ColorStack.fold`) under the CONSUMER'S
## profile, mirroring the two subsystems' push logic (`PaletteSubsystem._push_phase_ops`
## / `ScreenSubsystem._push_phase_ops`) — duplicated here rather than imported so the
## pure score projection never needs a live subsystem. Verdicts fold the SINGLE-PASS
## for_each stream (amendment decision 7) and IGNORE Solo/Mute (decision 5): they
## answer "what is this data", not "what am I previewing".
##
## No `class_name` (ADR-0004) — preloaded by path.

const ColorStackClass = ExMateriaSchema.ColorStack

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const ColorRecipe = ExMateriaSchema.ColorRecipe
const EffectPhaseClass = ExMateriaEffects.EffectPhase
const ScreenDataClass = ExMateriaEffects.ScreenData

## Consumer profiles (amendment decision: the verdict fold mirrors what each consumer
## renders). Palette = the 5-bit CLUT applier (quantize, params ×1, DDA ramp — the
## quantized fold IS what the CLUT shows). Screen = the 8-bit framebuffer applier
## (param DOUBLED `start << 1`, linear ramp over the keyframe duration, output clamped
## to [0,255] like `ScreenSubsystem._fold_color`).
const PALETTE_PROFILE := {"param_max": 31, "quantize": true, "double_param": false, "clamp": false}
const SCREEN_PROFILE := {"param_max": 255, "quantize": false, "double_param": true, "clamp": true}

## Transform equality is checked over a small probe-base set including the 0/1 clamp
## extremes (an affine layer is exact by two probes; the luma modes are covered by the
## channel-asymmetric spread — bases whose luminance differs from every channel).
const _PROBES := [
	Vector3(0.0, 0.0, 0.0),
	Vector3(1.0, 1.0, 1.0),
	Vector3(0.5, 0.5, 0.5),
	Vector3(0.8, 0.4, 0.1),
	Vector3(0.1, 0.6, 0.9),
]

## Well under the smallest real quantum either consumer can show (1/31 palette,
## 2/255 screen) yet far above float noise — the two variants fold identical layer
## sequences for every shared op, so shared float error cancels exactly.
const _EPS := 0.0005


## Per-op spacer verdicts for ONE consumer stream. `ops` is the channel's authored op
## list in stream order (cross-phase, concatenated at absolute offsets — the PSX has no
## phase concept), one entry per PLAYED keyframe:
##   {enabled: bool, at: int (absolute start frame), mode: int, r/g/b: int (raw param
##    bytes), time: int (raw Time byte), dur: int (ramp frames; omit/-1 = the palette
##    fast/slow DDA tables), gradient: bool (screen ctrl-bit-7-clear: an absolute set
##    of the endpoint to r/g/b — mode/time ignored)}
## Returns a parallel Array of bools — true = spacer (disabling it changes nothing).
static func verdicts(ops: Array, profile: Dictionary) -> Array:
	var samples := _sample_frames(ops)
	var quantize := bool(profile.get("quantize", false))
	var param_max := int(profile.get("param_max", 31))
	var clamp_out := bool(profile.get("clamp", false))
	# The baseline series: fold the FULL stream once. Evaluate the packed layer state ONCE
	# per sample frame and fold every probe off that snapshot — the fold is base-independent,
	# so the old per-probe `stack.fold()` re-evaluated the identical layer state five times
	# over (a flat 5x waste on the hottest loop in the studio, ADR-0087 perf).
	var base_stack := _build_stack(ops, -1, profile)
	var with_series := _fold_series_frames(base_stack, samples, quantize, param_max, clamp_out)
	var out: Array = []
	for i in range(ops.size()):
		# A disabled op pushes nothing in either variant — trivially a spacer (this is
		# how the fourth amendment subsumes the intrinsic predicate).
		if not bool(ops[i].get("enabled", true)):
			out.append(true)
			continue
		# An IDENTITY op is disable-equivalent by construction — no fold needed. This is not a
		# micro-optimisation: the two shortcuts in `_is_spacer` both help a REAL event (it
		# diverges at its first active frame and bails), so the whole cost of this function is
		# the spacers, each of which folds every sample from its own frame to the end with
		# nothing to bail on. A colour Move's manufactured padding is exactly that population —
		# which is why a palette reproject went from 74ms to 143ms the moment a fine slide laid
		# its pads down, at 7fps mid-drag against camera's 0.9ms (measured, E317).
		if _is_identity_op(ops[i]):
			out.append(true)
			continue
		out.append(_is_spacer(ops, i, profile, samples, with_series,
			quantize, param_max, clamp_out))
	return out


## Op `i`'s verdict taken THE LONG WAY — the full leave-one-out fold, with none of `verdicts()`'
## no-fold shortcuts consulted. Exists so `SpacerVerdictShortcutParityTest` can hold every
## shortcut to the answer the fold would have given, over the shipped corpus. Not for production
## callers: it rebuilds the baseline series per op, so it is O(N) times slower than `verdicts()`.
static func is_spacer_by_fold(ops: Array, i: int, profile: Dictionary) -> bool:
	var samples := _sample_frames(ops)
	var quantize := bool(profile.get("quantize", false))
	var param_max := int(profile.get("param_max", 31))
	var clamp_out := bool(profile.get("clamp", false))
	var base_stack := _build_stack(ops, -1, profile)
	var with_series := _fold_series_frames(base_stack, samples, quantize, param_max, clamp_out)
	return _is_spacer(ops, i, profile, samples, with_series, quantize, param_max, clamp_out)


## Is this op a pure IDENTITY — `current + 0`, contributing nothing wherever it sits? Mode 0
## lowers to `affine(ONE, ZERO)` (`ColorRecipe.from_mode`), so removing it is provably
## output-preserving, on three counts that between them cover every way an op can matter:
##   * its own contribution is the identity map;
##   * `reads_base()` is FALSE for a mode-0 affine, so it never appears as the "upper settled
##     base-reading layer" `ColorStack._is_shadowed` looks for — it cannot shadow the layer
##     below it, and a mode-8/10 RESTORE therefore folds the same with or without it;
##   * removing it can only break a settled-affine merge RUN, and affine composition is
##     associative, so the packed result is byte-identical either way (ADR-0067; the same
##     argument `_is_spacer`'s frame-skip shortcut already rests on).
##
## Deliberately NARROW. Modes 4/9 lower to `affine_base` — a zero param there RESETS current to
## base, which is emphatically not nothing. A SCREEN `gradient` op is an absolute set of the
## endpoint, so a zero param sets it to black. Both are excluded; anything not proven here just
## takes the fold.
static func _is_identity_op(op: Dictionary) -> bool:
	if bool(op.get("gradient", false)):
		return false
	return int(op.get("mode", -1)) == 0 and int(op.get("r", 0)) == 0 \
		and int(op.get("g", 0)) == 0 and int(op.get("b", 0)) == 0


## Is op `i` disable-equivalent (a spacer)? Fold the stream WITHOUT it and compare to the
## precomputed WITH-all series, sample by sample, with two shortcuts that preserve the exact
## verdict of the old whole-series compare:
##   * skip every sample BEFORE op i's start frame — op i is dormant there (never active), so
##     removing it can only break a settled-affine merge run, which is output-preserving by
##     construction (ADR-0067). The fold is byte-identical, so those samples never decide the
##     verdict.
##   * bail at the FIRST differing probe — a real event diverges the instant it becomes
##     active, so the common (non-spacer) case costs one folded frame, not the whole series.
## This turns the leave-one-out from O(N) folds-of-the-whole-series per op into ~one fold for a
## real event, collapsing the fold from ~O(N^3) toward ~O(N^2) on event-dense lanes.
static func _is_spacer(ops: Array, i: int, profile: Dictionary, samples: Array,
		with_series: Array, quantize: bool, param_max: int, clamp_out: bool) -> bool:
	var start := int(ops[i].get("at", 0))
	var stack := _build_stack(ops, i, profile)
	for s in range(samples.size()):
		var f := int(samples[s])
		if f < start:
			continue  # op i dormant here → identical in both variants (merge is output-preserving)
		var row: Array = _fold_frame(stack, f, quantize, param_max, clamp_out)
		var ref: Array = with_series[s]
		for p in range(row.size()):
			var d: Vector3 = (row[p] as Vector3) - (ref[p] as Vector3)
			if absf(d.x) > _EPS or absf(d.y) > _EPS or absf(d.z) > _EPS:
				return false
	return true


## Per-keyframe verdicts for one palette channel_name folded across ALL phases as one
## continuous stream (`PaletteSubsystem.build_stream` — concatenated at the absolute
## offsets in `offsets: {phase: int}`). Walks the SAME played window and timing rule as
## `_each_keyframe` (0..max_keyframe-2; disabled advances timing only — modeled here as
## an enabled=false op so the verdict index set matches the score's spans). Returns
## `{phase: {keyframe_index: bool}}`.
static func palette_verdicts(palette, channel_name: String, offsets: Dictionary) -> Dictionary:
	var ops: Array = []
	var index_map: Array = []
	if palette != null:
		for phase in EffectPhaseClass.ALL:
			var ch = palette.get_channel(phase, channel_name)
			if ch == null or ch.keyframes.is_empty():
				continue
			var offset := int(offsets.get(phase, 0))
			var start := 0
			var last_idx: int = mini(ch.keyframes.size(), maxi(0, ch.max_keyframe - 1))
			for i in range(last_idx):
				var kf = ch.keyframes[i]
				ops.append({"enabled": kf.enabled, "at": offset + start,
					"mode": int(kf.blend_mode), "r": int(kf.rgb.x), "g": int(kf.rgb.y),
					"b": int(kf.rgb.z), "time": int(kf.time_value)})
				index_map.append({"phase": phase, "index": i})
				start += maxi(1, kf.duration_frames)
	return _map_verdicts(verdicts(ops, PALETTE_PROFILE), index_map)


## Per-keyframe verdicts for the screen channel folded across ALL phases — TWO streams,
## one per backdrop endpoint (`ScreenSubsystem.build_stream`: the TOP stop folds
## start_r/g/b, the BOTTOM folds end_r/g/b; Blend ops are endpoint-agnostic). A spacer
## must be disable-equivalent on BOTH endpoints (disabling one keyframe drops it from
## both folds). Returns `{phase: {keyframe_index: bool}}`.
static func screen_verdicts(screen, offsets: Dictionary) -> Dictionary:
	var top: Array = []
	var bottom: Array = []
	var index_map: Array = []
	if screen != null:
		for phase in EffectPhaseClass.ALL:
			var ch = screen.get_channel(phase)
			if ch == null or ch.keyframes.is_empty():
				continue
			var offset := int(offsets.get(phase, 0))
			var start := 0
			var last_idx: int = mini(ch.keyframes.size(), maxi(0, ch.max_keyframe - 1))
			for i in range(last_idx):
				var kf = ch.get_keyframe(i)
				var dur: int = maxi(1, kf.duration_frames)
				var at := offset + start
				if kf.mode == ScreenDataClass.ScreenMode.BLEND:
					# The shared signed param tints both baselines the same — one op, both streams.
					var blend := {"at": at, "mode": int(kf.blend_mode), "r": int(kf.start_r_raw),
						"g": int(kf.start_g_raw), "b": int(kf.start_b_raw),
						"time": int(kf.time_value), "dur": dur}
					top.append(blend)
					bottom.append(blend)
				else:
					top.append({"gradient": true, "at": at, "dur": dur, "r": int(kf.start_r_raw),
						"g": int(kf.start_g_raw), "b": int(kf.start_b_raw)})
					bottom.append({"gradient": true, "at": at, "dur": dur, "r": int(kf.end_r_raw),
						"g": int(kf.end_g_raw), "b": int(kf.end_b_raw)})
				index_map.append({"phase": phase, "index": i})
				start += dur
	var vt := verdicts(top, SCREEN_PROFILE)
	var vb := verdicts(bottom, SCREEN_PROFILE)
	var both: Array = []
	for k in range(vt.size()):
		both.append(bool(vt[k]) and bool(vb[k]))
	return _map_verdicts(both, index_map)


# --- internals ---------------------------------------------------------------

## Build the consumer's ColorStack for the stream (minus op `skip`; -1 = none). Ops are
## pushed in stream order so a later mode-8/10 restore sees the earlier layers (the
## ColorStack build-time flip). The caller folds it; kept separate so the leave-one-out
## rebuilds the layer list without re-folding.
static func _build_stack(ops: Array, skip: int, profile: Dictionary) -> ColorStackClass:
	var stack: ColorStackClass = ColorStackClass.new()
	stack.set_quantize(bool(profile.get("quantize", false)))
	stack.set_param_max(int(profile.get("param_max", 31)))
	for i in range(ops.size()):
		if i == skip:
			continue
		var op: Dictionary = ops[i]
		if not bool(op.get("enabled", true)):
			continue
		if bool(op.get("gradient", false)):
			# The screen Gradient: an ABSOLUTE set of this endpoint to the explicit bytes —
			# affine(ZERO, target), the ScreenSubsystem._push_gradient_op shape.
			var target := Vector3(int(op.get("r", 0)), int(op.get("g", 0)), int(op.get("b", 0))) / 255.0
			stack.push_layer(ColorRecipe.affine(Vector3.ZERO, target),
				int(op.get("at", 0)), _effective_dur(op), ColorStackClass.MASK_WHOLE)
		else:
			stack.push_op(int(op.get("mode", 0)), int(op.get("r", 0)), int(op.get("g", 0)),
				int(op.get("b", 0)), int(op.get("time", 0)), int(op.get("at", 0)),
				ColorStackClass.MASK_WHOLE, int(op.get("dur", -1)),
				bool(profile.get("double_param", false)))
	return stack


## Fold a built stack over every probe base at every sample frame, returning one row of
## probe-results (Array[Vector3]) per sample. `evaluate` is called ONCE per frame and the
## five probes fold off that single packed snapshot (the fold is base-independent).
static func _fold_series_frames(stack: ColorStackClass, samples: Array,
		quantize: bool, param_max: int, clamp_out: bool) -> Array:
	var out: Array = []
	for f in samples:
		out.append(_fold_frame(stack, int(f), quantize, param_max, clamp_out))
	return out


## Fold one frame: evaluate the packed layer state once, then fold every probe base off it.
static func _fold_frame(stack: ColorStackClass, f: int,
		quantize: bool, param_max: int, clamp_out: bool) -> Array:
	stack.evaluate(f)
	var rgb0 := stack.rgb0()
	var rgb1 := stack.rgb1()
	var meta := stack.meta()
	var cnt := stack.count()
	var row: Array = []
	for base in _PROBES:
		var v: Vector3 = ColorStackClass.fold_packed(rgb0, rgb1, meta, cnt, base, 0, quantize, param_max)
		if clamp_out:
			v = v.clamp(Vector3.ZERO, Vector3.ONE)
		row.append(v)
	return row


## An op's ramp length in frames: explicit `dur` (the screen's linear Time*8 window)
## or the palette fast/slow DDA tables when omitted (`push_op`'s dur=-1 default).
static func _effective_dur(op: Dictionary) -> int:
	var dur := int(op.get("dur", -1))
	if dur >= 0:
		return dur
	return ColorRecipe.ramp_frames_for_time(int(op.get("time", 0)))


## The sample frames: every enabled op's start and ramp end (a restore's flip window is
## the same pair), frame 0, one frame past everything (the settled tail) — PLUS the
## midpoint of every adjacent pair: two part-done ramps compose non-linearly, so two
## streams can agree at every breakpoint yet differ strictly between them (an equal-
## target Gradient overlapping a longer one differs only mid-interval).
static func _sample_frames(ops: Array) -> Array:
	var marks := {0: true}
	var far := 1
	for op in ops:
		if not bool(op.get("enabled", true)):
			continue
		var at := int(op.get("at", 0))
		var end := at + _effective_dur(op)
		marks[at] = true
		marks[end] = true
		far = maxi(far, end + 1)
	marks[far] = true
	var frames := marks.keys()
	frames.sort()
	var out: Array = []
	for k in range(frames.size()):
		out.append(frames[k])
		if k + 1 < frames.size():
			var mid: int = (int(frames[k]) + int(frames[k + 1])) / 2
			if mid != int(frames[k]):
				out.append(mid)
	return out


## Re-key a flat verdict list by the (phase, keyframe_index) each op came from.
static func _map_verdicts(flat: Array, index_map: Array) -> Dictionary:
	var out: Dictionary = {}
	for k in range(flat.size()):
		var at: Dictionary = index_map[k]
		if not out.has(at["phase"]):
			out[at["phase"]] = {}
		out[at["phase"]][at["index"]] = flat[k]
	return out
