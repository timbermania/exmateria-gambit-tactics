class_name GPUEffectTimingLoader
extends RefCounted

## Builds the GPU effect-timing buffer from per-effect timeline.json headers.
##
## Mirrors GPUAnimationTimingLoader's shape for the cinematic-spell orchestrator
## landing in issue #53. The buffer is keyed by effect id (E000..E511) and packs
## three ints per effect:
##
##   [effect_id * 3]     = first_hit_frame  (absolute frame of the first
##                                            for_each HIT_REACT, from
##                                            U_CINEMATIC_TIMER == 0)
##   [effect_id * 3 + 1] = for_each_delay   (per-target stride for AoE
##                                            cinematic fan-out, max(1, raw))
##   [effect_id * 3 + 2] = total_frames     (per-effect cinematic length)
##
## Slots with no on-disk timeline.json (or an empty effect bin) stay at the
## -1 sentinel. The shader-side consumer lands in a later commit; this loader
## and its SSBO upload land first so the boot-time wiring is in place.
##
## Clock-rate scaling (#109): the on-disk values are in **CPU effect_frame
## units (30 Hz)** — the same unit the runtime EffectTimeline / PhaseBlock
## fires at. The GPU's BH_CINEMATIC_TIMER ticks once per GPU dispatch, which
## CombatLoop runs at host frame rate (~60 Hz) when ticks_per_frame == 1. The
## ratio is exactly 2 (PSX 30 Hz game-loop : 60 Hz host display), so each
## field is upscaled by GPU_TICKS_PER_EFFECT_FRAME before upload so the GPU
## orchestrator's per-tick compare to new_timer lands on the same wall-clock
## beat the CPU EffectTimeline fires its action_flags on. Without this scale
## the GPU's heal beat fires at half the CPU's HIT_REACT beat, leaving the
## carrier mid-rise for ~100 GPU ticks while the world stays paused.

const _EFFECTS_ROOT := "res://assets/effects/"
const _FIELDS_PER_EFFECT := 3
const _SENTINEL := -1

# GPU-tick : CPU-effect-frame ratio for the cinematic clock. The CPU
# EffectTimeline accumulates real `delta` and fires PhaseBlock action_flags
# at 30 Hz; the GPU's BH_CINEMATIC_TIMER increments once per stage_spell
# dispatch. At ticks_per_frame == 1 (the production + rise-timing-test
# setting) the GPU pump runs at host frame rate ~60 Hz, so the ratio is 2.
# Tests at higher ticks_per_frame (e.g. GPUMoveToUnitTest at TPF=4) don't
# play cinematic spells, so the simple scalar holds for every site that
# actually consumes these fields today.
const GPU_TICKS_PER_EFFECT_FRAME := 2


static func build() -> PackedInt32Array:
	var data := PackedInt32Array()
	data.resize(GPUConstants.MAX_EFFECTS * _FIELDS_PER_EFFECT)

	for i in range(data.size()):
		data[i] = _SENTINEL

	var loaded := 0
	for effect_id in range(GPUConstants.MAX_EFFECTS):
		var path := "%sE%03d/timeline.json" % [_EFFECTS_ROOT, effect_id]
		if not FileAccess.file_exists(path):
			continue

		var file := FileAccess.open(path, FileAccess.READ)
		if not file:
			continue
		var text := file.get_as_text()
		file.close()

		var json := JSON.new()
		if json.parse(text) != OK:
			push_warning("[GPUEffectTimingLoader] failed to parse %s: %s" % [path, json.get_error_message()])
			continue

		var doc: Variant = json.data
		if not doc is Dictionary:
			continue
		var header: Variant = doc.get("header", null)
		if not header is Dictionary:
			continue

		# Staleness guard: the post-#53 parse_effect.py ALWAYS emits
		# first_hit_frame/for_each_delay/total_frames in the header. An
		# old-format timeline.json lacks them, so the cinematic would silently
		# collapse to total_frames=0 (begins and ends in one tick). Fail loud
		# here — same contract as GPUAnimationTimingLoader's `_timings` assert —
		# instead of shipping a broken cinematic.
		assert(header.has("total_frames"),
			"E%03d/timeline.json is stale (pre-#53 parse_effect.py) -- rerun: uv run python tools/parse_all_effects_py.py --force" % effect_id)

		# Convert the 30 Hz CPU effect_frame values on disk into the GPU's
		# host-tick units (BH_CINEMATIC_TIMER increments once per GPU
		# dispatch ≈ host frame). Preserve the -1 sentinel for empty slots
		# so the get_effect_* accessor clamps still see "no on-disk timeline".
		var base := effect_id * _FIELDS_PER_EFFECT
		var fhf := int(header.get("first_hit_frame", _SENTINEL))
		var fed := int(header.get("for_each_delay", _SENTINEL))
		var tf := int(header.get("total_frames", _SENTINEL))
		data[base] = fhf * GPU_TICKS_PER_EFFECT_FRAME if fhf >= 0 else _SENTINEL
		data[base + 1] = fed * GPU_TICKS_PER_EFFECT_FRAME if fed >= 0 else _SENTINEL
		data[base + 2] = tf * GPU_TICKS_PER_EFFECT_FRAME if tf >= 0 else _SENTINEL
		loaded += 1

	if DebugConfig.gpu_debug_enabled:
		print("[GPUEffectTimingLoader] Loaded %d effect timings (max=%d)" % [loaded, GPUConstants.MAX_EFFECTS])

	return data
