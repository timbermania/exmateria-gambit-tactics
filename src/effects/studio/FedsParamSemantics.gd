extends RefCounted
## Author-facing SEMANTICS for FEDS opcode params — the anti-technobabble layer.
## The bytes stay the storage truth; this module says what a byte MEANS and, where
## a real human unit exists, how to edit in it:
##
##   * ADSR times edit in MILLISECONDS, snapped to the nearest storable SPU rate
##     (the hardware stores rates, not times) via a lookup-map `unit` consumed by
##     the shared CameraUnits/_int_cell seam. The ms tables are derived from THE
##     SAME envelope tables the emulation steps (ADSR.build_tables, from
##     PCSX-Redux adsr.cc) — single source, no drift.
##   * Instrument (0xAC) edits as a NAMED enum — ids come from the generated
##     FedsInstrumentNames table (the DAW picker's names).
##   * Tick params (Rest/Fermata), volume (Dynamics), counts (Repeat) get honest
##     labels + ranges.
##
## `descriptor(op, param_index)` returns {} for anything uncurated — the caller
## falls back to the raw byte cell, honestly labeled. Pure static; no class_name
## (ADR-0004).

const InstrumentNames = preload("res://src/effects/studio/FedsInstrumentNames.gd")
const InstrumentMeta = preload("res://src/effects/studio/FedsInstrumentMeta.gd")
const SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")
const Stats = preload("res://src/effects/studio/FedsParamStats.gd")

const SAMPLE_RATE := 44100.0
# Exponential fades have no exact zero; report time to fall to 1% of full — the
# audible "it's gone" point. Stated in every fade tooltip.
const FALL_TARGET := 0.01

# Lazily-built ms maps (one entry per storable rate). Static so the cost is paid
# once per session.
static var _attack_ms := PackedFloat32Array()
static var _release_ms := PackedFloat32Array()
static var _decay_ms := PackedFloat32Array()


## The author-facing descriptor for one opcode param, or {} when uncurated.
## Keys: label, tooltip, and optionally editor ("enum" + choices), min/max (raw),
## unit ({map, suffix, decimals} for the ms cells).
static func descriptor(op: int, param_index: int) -> Dictionary:
	match op:
		0xAC:   # Instrument
			return {
				"label": "Instrument",
				"editor": "enum",
				"choices": _instrument_choices(),
				# A per-value detail read-out beside the dropdown: the resolved sample's
				# loop verdict (Sustains / One-shot) + size + silent tell — why a held
				# note rings vs. plays once (ADR-0085 amendment).
				"value_detail": func(id: int) -> String: return InstrumentMeta.describe(id),
				"tooltip": "The waveset sample this track plays from here on. " +
					"Names come from the DAW picker table (raw id in parentheses). " +
					"The line below reports whether the sample SUSTAINS (loops a tail " +
					"while a note is held) or is a ONE-SHOT.",
			}
		0xC2:   # ADSR_Attack
			return {
				"label": "Attack time",
				"min": 0, "max": 127,
				"unit": {"map": _attack_map(), "suffix": " ms", "decimals": 1},
				"tooltip": "Time for the envelope to rise 0 → full (linear mode; " +
					"ADSR_AttackMode's exponential runs slower past 75%). Typed ms " +
					"SNAP to the nearest storable SPU attack rate (0–127) — the " +
					"hardware stores rates, not times.",
			}
		0xC5:   # ADSR_Release
			return {
				"label": "Release time",
				"min": 0, "max": 31,
				"unit": {"map": _release_map(), "suffix": " ms", "decimals": 1},
				"tooltip": "Time for the note to fade to 1% after key-off " +
					"(exponential). Typed ms snap to the nearest storable SPU " +
					"release rate (0–31).",
			}
		0xC9:   # ADSR_Decay
			return _decay_descriptor()
		0xC7:   # ADSR_DecayAndSustainLevel: p0 decay, p1 sustain level
			if param_index == 0:
				return _decay_descriptor()
			return _sustain_level_descriptor()
		0xCA:   # ADSR_SustainLevel
			return _sustain_level_descriptor()
		0x80:   # Rest
			return {
				"label": "Rest (ticks)",
				"tooltip": "Silence for this many ticks (48 ticks = 1 beat).",
			}
		0x81:   # Fermata
			return {
				"label": "Hold extra (ticks)",
				"tooltip": "Extends the sustaining note by this many ticks and " +
					"waits them out (48 ticks = 1 beat).",
			}
		0x94:   # Octave
			return {
				"label": "Octave",
				"min": 0, "max": 9,
				"tooltip": "Absolute octave for the notes that follow.",
			}
		0x98:   # Repeat
			return {
				"label": "Play count",
				"min": 1, "max": 255,
				"tooltip": "The Repeat…Coda body plays this many times TOTAL.",
			}
		0xA0:   # Tempo
			return {
				"label": "Tempo",
				"unit": {"map": _tempo_map(), "suffix": " BPM", "decimals": 1},
				"tooltip": "Tick clock speed from here on. Typed BPM snaps to the " +
					"nearest storable tempo byte.",
			}
		0xE0:   # Dynamics
			return {
				"label": "Channel volume",
				"min": 0, "max": 127,
				"tooltip": "The track's volume level, 0–127 (SPU dynamics).",
			}
		0xB4:   # Noise_EnableAndClock
			return {
				"label": "Noise clock",
				"min": 0, "max": 63,
				"tooltip": "SPU noise generator clock (0–63) — higher = brighter " +
					"hiss. Also switches the voice to noise.",
			}
		0xD0:   # SetPitchBend
			return {
				"label": "Pitch bend (set)",
				"tooltip": "Sets the channel pitch-bend amount directly. No physical " +
					"unit is pinned by the RE — the corpus range grounds the scale.",
			}
		0xD1:   # AddPitchBend (signed)
			return {
				"label": "Pitch bend add",
				"tooltip": "Accumulating pitch-bend step added to the channel " +
					"(chan+0x86 += value·32). Signed — a negative value bends pitch " +
					"down. No physical unit is pinned; the corpus range grounds the scale.",
			}
		0xD2:   # PitchBendRel (signed)
			return {
				"label": "Pitch bend (relative)",
				"tooltip": "Relative pitch-bend step. Signed. No pinned unit — the " +
					"corpus range grounds the scale.",
			}
		0xD3:   # PitchBend_Add_16bit (signed 16-bit word)
			return {
				"label": "Pitch bend add (16-bit)",
				"tooltip": "A signed 16-bit pitch-bend added to the channel " +
					"(high<<8 | low), edited as one atomic word — finer resolution " +
					"than the 8-bit add. The corpus range grounds the scale.",
			}
		0xD4:   # Portamento_Init: p0 target, p1 rate
			if param_index == 0:
				return {
					"label": "Glide target",
					"tooltip": "The pitch the portamento glides toward.",
				}
			return {
				"label": "Glide rate",
				"tooltip": "The glide's per-tick pitch delta — NOT milliseconds. Total " +
					"glide time depends on the runtime's starting pitch, so no honest " +
					"ms is derivable; the corpus range grounds the scale.",
			}
		0xD6:   # Detune (signed)
			return {
				"label": "Detune",
				"tooltip": "Signed fine pitch offset. No pinned unit — the corpus " +
					"range grounds the scale.",
			}
		0xE1:   # Dynamics_Add (signed)
			return {
				"label": "Volume add",
				"tooltip": "Accumulating signed volume step (chan+0x98 += value<<24). " +
					"Negative values duck the channel; the corpus range grounds the scale.",
			}
		0xAD:   # Byte76_Adjust (signed)
			return {
				"label": "Slot 0x76 adjust",
				"tooltip": "Signed adjustment added to the channel's 0x76 slot. Not " +
					"fully RE'd — kept honest; the corpus range grounds the scale.",
			}
	return {}


## The storage TYPE for a param cell, from the shared signedness table (feds_param_stats):
## "s16" for a genuine 16-bit word, "s8" for a signed byte (display-only sign-extension),
## "u8" otherwise. The write path stays raw either way — signedness is an authoring display.
static func storage_type(op: int, param_index: int) -> String:
	var st: Dictionary = Stats.of(op, param_index)
	if not bool(st.get("signed", false)):
		return "u8"
	return "s16" if int(st.get("bits", 8)) == 16 else "s8"


## The empirical usage range for a param cell (signed-space), or {} when the corpus never
## uses it. {min, max, median, n} — the honest substitute for a physical unit (ADR-0085).
## With instrument_id ≥ 0 the range is CONDITIONED on the active instrument (the last
## 0xAC in-track, ADR-0085 2026-08-12): returns that instrument's bucket, or {} when the
## corpus has no samples of this param under it (the caller renders the honest "none with
## X" state). The default (−1) keeps the global range — an unchanged call site.
static func usage_range(op: int, param_index: int, instrument_id: int = -1) -> Dictionary:
	var st: Dictionary = Stats.of(op, param_index) if instrument_id < 0 \
			else Stats.of_instrument(op, param_index, instrument_id)
	if st.is_empty():
		return {}
	return {
		"min": int(st.get("min", 0)),
		"max": int(st.get("max", 0)),
		"median": int(st.get("median", 0)),
		"n": int(st.get("n", 0)),
	}


## One-line hover summary for a placed opcode (the lane panel's chip tooltips):
## names the instrument, reports ADSR ≈ms — "" when nothing beyond the raw params
## is worth saying.
static func param_summary(op: int, params: Array) -> String:
	if params.is_empty():
		return ""
	var p0 := int(params[0])
	match op:
		0xAC:
			return str(InstrumentNames.NAMES.get(p0, "unnamed"))
		0xC2:
			return "≈ %.0f ms attack" % _at(_attack_map(), p0)
		0xC5:
			return "≈ %.0f ms release" % _at(_release_map(), p0)
		0xC9, 0xC7:
			return "≈ %.0f ms decay" % _at(_decay_map(), p0)
		0xA0:
			return "≈ %.1f BPM" % SMD.fft_tempo_to_bpm(p0)
	# Chip-hover parity (ADR-0085 §E): a labeled-but-unitless opcode (pitch/portamento
	# family, …) speaks its CELL label + signed-aware value — the same language the
	# inspector cell uses. The corpus-range detail stays in the inspector, not here.
	# A truly uncurated opcode stays silent: the chip already shows its opcode name.
	var d: Dictionary = descriptor(op, 0)
	if d.has("label") and not d.has("unit") and not d.has("editor"):
		var st := storage_type(op, 0)
		var v := p0
		if st == "s16" and params.size() >= 2:
			v = _to_s16(p0, int(params[1]))
		elif st == "s8":
			v = p0 - 256 if p0 >= 128 else p0
		return "%s: %d" % [str(d["label"]), v]
	return ""


## Two's-complement reconstruction of a signed 16-bit word from its two stored bytes.
static func _to_s16(hi: int, lo: int) -> int:
	var v: int = ((hi & 0xFF) << 8) | (lo & 0xFF)
	return v - 65536 if v >= 32768 else v


static func _decay_descriptor() -> Dictionary:
	return {
		"label": "Decay time",
		"min": 0, "max": 15,
		"unit": {"map": _decay_map(), "suffix": " ms", "decimals": 1},
		"tooltip": "Time to fall from full toward the sustain level after the " +
			"attack peaks (exponential, measured to 1%). Typed ms snap to the " +
			"nearest storable SPU decay rate (0–15).",
	}


static func _sustain_level_descriptor() -> Dictionary:
	return {
		"label": "Sustain level",
		"min": 0, "max": 15,
		"tooltip": "The level the decay falls to and holds, 0–15 (15 = full).",
	}


static func _instrument_choices() -> Array:
	var out: Array = []
	var ids: Array = InstrumentNames.NAMES.keys()
	ids.sort()
	for id in ids:
		out.append({"value": int(id), "label": "%d — %s" % [int(id), str(InstrumentNames.NAMES[id])]})
	return out


static func _at(map: PackedFloat32Array, raw: int) -> float:
	if map.is_empty():
		return 0.0
	return map[clampi(raw, 0, map.size() - 1)]


# --- SPU envelope timing (from ADSR's PCSX-Redux tables — single source) -----

## Milliseconds for the linear attack 0 → 32767 at each rate 0-127: one +num_inc
## step every `denominator` samples at 44.1 kHz (the SPU's linear/quarter-speed attack).
static func _attack_map() -> PackedFloat32Array:
	if _attack_ms.is_empty():
		ExMateriaSpu.ADSR.build_tables()
		_attack_ms.resize(128)
		for rate in range(128):
			var steps := ceili(32767.0 / float(ExMateriaSpu.ADSR.num_inc[rate]))
			_attack_ms[rate] = float(steps) * float(ExMateriaSpu.ADSR.denominator[rate]) \
					* 1000.0 / SAMPLE_RATE
	return _attack_ms


## Milliseconds for an exponential fall full → 1% at an internal rate: each step
## multiplies the envelope by (1 + num_dec/32768) every `denominator` samples
## (geometric release / decay). Closed form — the geometric step count.
static func _exp_fall_ms(rate: int) -> float:
	ExMateriaSpu.ADSR.build_tables()
	var m := 1.0 + float(ExMateriaSpu.ADSR.num_dec[rate]) / 32768.0
	var denom := float(ExMateriaSpu.ADSR.denominator[rate])
	if m <= 0.0:
		return denom * 1000.0 / SAMPLE_RATE   # one step to (near) zero
	var steps := log(FALL_TARGET) / log(m)
	return steps * denom * 1000.0 / SAMPLE_RATE


## Release rate 0-31 (the SPU quadruples it internally).
static func _release_map() -> PackedFloat32Array:
	if _release_ms.is_empty():
		_release_ms.resize(32)
		for r in range(32):
			_release_ms[r] = _exp_fall_ms(mini(r * 4, 127))
	return _release_ms


## Decay rate 0-15 (also quadrupled internally).
static func _decay_map() -> PackedFloat32Array:
	if _decay_ms.is_empty():
		_decay_ms.resize(16)
		for d in range(16):
			_decay_ms[d] = _exp_fall_ms(mini(d * 4, 127))
	return _decay_ms


## Tempo byte 0-255 → BPM through the runtime's own conversion.
static func _tempo_map() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(256)
	for t in range(256):
		out[t] = SMD.fft_tempo_to_bpm(t)
	return out
