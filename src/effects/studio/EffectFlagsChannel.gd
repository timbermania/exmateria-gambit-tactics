class_name EffectFlagsChannel
extends RefCounted
## Write-side channel archetype for the effect's GLOBAL flags byte (#272, ADR-0092) — the
## single byte @0x00 of the effect_flags section (header `0x18` → `effect_flags_ptr`). Only
## bits 3-6 are read by the engine (proven at `0x801A1530`/`0x801A61E0`/`0x801A3BF8`/
## `0x801A4A5C`): bit3 `terrain_height_adjust`, bit4 `audio_fade`, bit5 `time_scale_pattern1`
## (3-phase slow-mo enable), bit6 `time_scale_pattern2` (1-phase). Bits 0-2/7 are loaded but
## AND-masked away — yet effect files still set them (E001=0x03), so the WHOLE raw byte is the
## round-trip source of truth. The `bitflags` editor recomputes the full word off the seeded
## raw byte and hands it here, so the ignored bits ride along untouched.
##
## Unlike the per-keyframe channels, the flags byte is effect-global and lives on `data.flags`
## (a plain Dictionary), reached through the `effect_settings` inspection target rather than a
## span. An edit writes `flags_byte`, keeps the four decoded bools in sync, AND — for bits 5/6
## — mirrors the enables into `data.time_scale.flags.time_scale_pattern1/2` so a re-fold makes
## the slow-mo enable/disable visible immediately. Every edit therefore declares
## `invalidates_sim`. Scalar undo — the raw byte fully re-derives. The single choke point is
## `EffectEditSession.apply_edit`.

# The four engine-read bit masks (bits 3-6) and the decoded-bool key each drives. The raw byte
# carries every bit; only these are surfaced/decoded. Bits 0-2/7 are engine-ignored padding.
const _BIT_TERRAIN := 0x08
const _BIT_AUDIO_FADE := 0x10
const _BIT_TIME_SCALE_1 := 0x20
const _BIT_TIME_SCALE_2 := 0x40


## Write the full flags byte `new_raw` onto `data.flags`, keeping the decoded bools and the
## time-scale enables (bits 5/6) in lockstep. Returns the snapshot the choke point records for
## scalar undo. Every edit re-folds the sim (the preview honours the time-scale enables).
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	if data == null or not (data.flags is Dictionary) or data.flags.is_empty():
		push_error("EffectFlagsChannel: no flags block to edit for %s" % str(field_ref))
		return {}
	var before: int = int(data.flags.get("flags_byte", 0))
	var word: int = int(new_raw) & 0xFF
	data.flags["flags_byte"] = word
	# Keep the four decoded bools consistent so a read-back before reload agrees with the byte.
	data.flags["terrain_height_adjust"] = (word & _BIT_TERRAIN) != 0
	data.flags["audio_fade"] = (word & _BIT_AUDIO_FADE) != 0
	data.flags["time_scale_pattern1"] = (word & _BIT_TIME_SCALE_1) != 0
	data.flags["time_scale_pattern2"] = (word & _BIT_TIME_SCALE_2) != 0
	# Mirror bits 5/6 into the time-scale block so the preview's slow-mo re-arms on re-fold.
	# A time-scale-less effect (data.time_scale == {}) simply has nothing to sync.
	if data.time_scale is Dictionary and data.time_scale.has("flags") \
			and data.time_scale["flags"] is Dictionary:
		data.time_scale["flags"]["time_scale_pattern1"] = (word & _BIT_TIME_SCALE_1) != 0
		data.time_scale["flags"]["time_scale_pattern2"] = (word & _BIT_TIME_SCALE_2) != 0
	return {
		"before_raw": before,
		"after_raw": word,
		"invalidates_sim": true,
	}


## The live stored flags byte — the seed the inspector's bitflags group reads so unlisted bits
## survive a toggle (mirrors apply_raw's storage; the read half of the choke).
static func read_raw(data, _field_ref: Dictionary) -> int:
	if data == null or not (data.flags is Dictionary):
		return 0
	return int(data.flags.get("flags_byte", 0))
