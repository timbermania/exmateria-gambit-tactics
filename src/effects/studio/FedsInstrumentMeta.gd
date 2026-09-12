extends RefCounted
## Reader for assets/feds_instrument_meta.json (ADR-0085 amendment: the
## instrument-chip loop verdict). The FEDS Instrument opcode (0xAC) picks a waveset
## sample; on a HELD note the SPU decides — from that sample's ADPCM block-loop
## flags — whether it SUSTAINS (loops a tail) or is a ONE-SHOT. This humanizes those
## raw facts for the inspector so an author sees "why one note rings" without reading
## bytes. The generator (tools/generate_feds_instrument_meta.py) and this reader share
## the committed file; drift guard tools/test_feds_instrument_meta_drift.py.
##
## No class_name (ADR-0004); load()ed by path. Names come from FedsInstrumentNames.

const InstrumentNames = preload("res://src/effects/studio/FedsInstrumentNames.gd")
const _PATH := "res://assets/feds_instrument_meta.json"
# FFT's default loop point when a sample loops but marks no explicit LOOP_START:
# loop_addr = sample_end − 0x1010 (clamped to start). See fft_spu_voice_runtime.cpp.
const HEURISTIC_LOOP_SPAN := 0x1010

static var _meta: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(_PATH):
		push_warning("FedsInstrumentMeta: %s absent — loop verdicts unavailable" % _PATH)
		return
	var f := FileAccess.open(_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		var m = json.data.get("meta", {})
		if typeof(m) == TYPE_DICTIONARY:
			_meta = m
	f.close()


## Raw ADPCM loop facts for a 0xAC id — {sample_size, has_loop_repeat,
## has_explicit_loop_start, loop_offset_bytes, is_null} — or {} when unknown.
static func of(id: int) -> Dictionary:
	_ensure()
	var e = _meta.get(str(id))
	return e if typeof(e) == TYPE_DICTIONARY else {}


## The loop verdict line, PURE over the raw facts (no name needed). "" for an empty
## slot / missing data. Honest about the heuristic loop point when no explicit
## LOOP_START block marks it.
static func loop_summary_of(meta: Dictionary) -> String:
	if meta.is_empty() or bool(meta.get("is_null", false)):
		return ""
	var size := int(meta.get("sample_size", 0))
	if bool(meta.get("has_explicit_loop_start", false)):
		var lo := int(meta.get("loop_offset_bytes", -1))
		if lo >= 0:
			return "Sustains — loops its tail (last %d of %d bytes)" % [size - lo, size]
	if bool(meta.get("has_loop_repeat", false)):
		if size <= HEURISTIC_LOOP_SPAN:
			return "Sustains — loops the whole sample (%d bytes; loop point is a heuristic)" % size
		return ("Sustains — loops its tail (~last %d of %d bytes; loop point is a heuristic)"
			% [HEURISTIC_LOOP_SPAN, size])
	return "One-shot — plays once, then stops"


## Full humanized detail for the instrument-chip inspector cell: name · category,
## sample size, and the loop verdict — or the silent tell for a ·Silence instrument
## (reusing FedsInstrumentNames' trusted-empty / gray-zone-clip split).
static func describe(id: int) -> String:
	var parts: Array = []
	var name := String(InstrumentNames.NAMES.get(id, ""))
	if name != "":
		parts.append(name)
	var meta := of(id)
	if meta.is_empty():
		return " · ".join(parts)
	if bool(meta.get("is_null", false)):
		parts.append("empty slot (no sample)")
		return " · ".join(parts)
	parts.append("%d-byte sample" % int(meta.get("sample_size", 0)))
	if InstrumentNames.is_silence(id):
		var flavour := InstrumentNames.silence_flavour(id)
		parts.append("Silent — no audible output" if flavour == "Empty"
			else "Nearly silent (%s)" % flavour)
	else:
		var ls := loop_summary_of(meta)
		if ls != "":
			parts.append(ls)
	return " · ".join(parts)
