extends RefCounted
## The **effect_settings** target-kind projector (ADR-0073, #271) — the effect-level GLOBAL
## settings surface. Unlike span/emitter/container (each scoped to one addressable object),
## this renders the effect's *global* knobs that belong to no keyframe: Timeline Header phase
## durations (#271, landed), and — as future sections drop into `sections()` — Effect Flags
## (#272) and Time Scale (#270). The whole small-byte cluster shares this one surface.
##
## Model is `load()`ed at call time to avoid a parse-time cycle. No `class_name` (ADR-0004).

const InspectionTarget = preload("res://src/effects/studio/InspectionTarget.gd")
const EffectScriptPattern = preload("res://src/effects/studio/EffectScriptPattern.gd")

# Pattern -> choice index (the "Convert" selector order — matches EffectScriptChannel).
const _PATTERN_TO_INDEX := {"3-phase": 0, "1-phase": 1}


## A bare header — the effect_settings target owns no index/provenance, so it just names the
## surface. (The inspector already renders the "Effect Settings" title from InspectionTarget.)
static func header(_target: Dictionary, _effect_data, _score: Dictionary) -> Array:
	return []


## The effect's global settings as `[Section]`. Shaped as an array so #272 (flags) / #270
## (time scale) append as pure additions — no restructure. Today: the Timeline section only.
static func sections(_target: Dictionary, effect_data, _score: Dictionary) -> Array:
	var out: Array = []
	var timeline := _timeline_section(effect_data)
	if not timeline.is_empty():
		out.append(timeline)
	var flags := _flags_section(effect_data)
	if not flags.is_empty():
		out.append(flags)
	var script := _script_pattern_section(effect_data)
	if not script.is_empty():
		out.append(script)
	return out


## The Timeline-header phase durations (#271) — the effect's skeleton — as three editable
## `int` rows on the `timeline_header` channel, seeded to the live values. Absent when the
## effect has no timeline. Rows shift the whole score when edited (the channel re-flows the
## phase offsets); the tooltips say what each duration bounds.
static func _timeline_section(effect_data) -> Dictionary:
	if effect_data == null or effect_data.timeline == null:
		return {}
	var tl = effect_data.timeline
	return {
		"title": "Timeline",
		"fields": [
			_duration_row("Phase 1 duration", "phase1_duration", int(tl.phase1_duration),
				"Frames until phase 1 ends and the for-each phase starts. Editing it shifts "
				+ "the for-each and phase 2 bands."),
			_duration_row("Spawn delay", "spawn_delay", int(tl.spawn_delay),
				"Delay between spawns — applies with multiple targets. No visible effect on the "
				+ "single-target preview."),
			_duration_row("Phase 2 delay", "phase2_delay", int(tl.phase2_delay),
				"Frames from the for-each start until phase 2 starts. Editing it shifts the "
				+ "phase 2 band."),
		],
	}


## The Effect Flags byte (#272, ADR-0092) — one `bitflags` checkbox group over the effect's
## GLOBAL flags byte, exposing the four engine-read bits (bit3 terrain-adjust, bit4 audio-fade,
## bit5/6 the two time-scale enables). Seeded with the WHOLE raw byte so the bitflags editor
## recomputes over it and the engine-ignored bits (0-2, 7) survive a toggle. Absent when the
## effect has no parsed flags block. Toggling a bit re-folds the sim (bits 5/6 change the
## preview's slow-mo; bits 3/4 re-fold harmlessly).
static func _flags_section(effect_data) -> Dictionary:
	if effect_data == null or not (effect_data.flags is Dictionary) or effect_data.flags.is_empty():
		return {}
	var raw := int(effect_data.flags.get("flags_byte", 0))
	return {
		"title": "Flags",
		"fields": [{
			"name": "Engine flags",
			"shape": "edit",
			"editor": "bitflags",
			"value": raw,
			"tooltip": "The four engine-read bits of the effect's flags byte. Bits 0-2/7 are "
				+ "loaded but ignored by the engine — they ride along untouched.",
			"field_ref": {"channel": "effect_flags", "field": "flags_byte"},
			"bits": [
				{"mask": 0x08, "label": "Terrain height adjust"},
				{"mask": 0x10, "label": "Audio fade"},
				{"mask": 0x20, "label": "Time scale (3-phase)"},
				{"mask": 0x40, "label": "Time scale (1-phase)"},
			],
		}],
	}


## The Script Pattern (#273, ADR-0094) — the effect's runtime shape (`3-phase` = phase-1 +
## for-each + phase-2, or `1-phase` = for-each only). For a swappable script (DATA-format AND
## strictly canonical) it is a `choice` selector on the `script_pattern` channel — picking the
## other pattern swaps it (structure-preserving section rewrite; the score re-flows). For a
## Custom / CODE-format / non-canonical script it is a read-only `const` row showing the mode
## with the reason in its tooltip. Absent when the effect carries no script_ops.
static func _script_pattern_section(effect_data) -> Dictionary:
	if effect_data == null or not (effect_data.script_ops is Array) or effect_data.script_ops.is_empty():
		return {}
	var cls := EffectScriptPattern.classify(
		effect_data.script_ops, not bool(effect_data.script_code_format))
	var mode := String(cls.get("mode", ""))
	if bool(cls.get("swappable", false)):
		return {
			"title": "Script Pattern",
			"fields": [{
				"name": "Pattern",
				"shape": "edit",
				"editor": "choice",
				"choices": ["3-phase", "1-phase"],
				"value": int(_PATTERN_TO_INDEX.get(mode, 0)),
				"tooltip": "The effect's runtime shape. 3-phase runs phase-1 + for-each + phase-2; "
					+ "1-phase runs the for-each only. Swapping rewrites the script and leaves the "
					+ "phase-1/phase-2 timeline dormant (restored on swap-back).",
				"field_ref": {"channel": "script_pattern"},
			}],
		}
	return {
		"title": "Script Pattern",
		"fields": [{
			"name": "Pattern",
			"shape": "const",
			"value": mode,
			"tooltip": "Read-only — %s" % String(cls.get("read_only_reason", "not swappable")),
		}],
	}


## One editable `int` duration cell for the F1 kit, carrying the write-side field_ref for the
## choke point. `u16` gives the SpinBox a 0..65535 authoring range; the channel's Faithful
## advisory flags a value past the positive 16-bit frame slot (it would not lower correctly).
static func _duration_row(label: String, field: String, value: int, tooltip: String) -> Dictionary:
	return {
		"name": label,
		"shape": "edit",
		"editor": "int",
		"type": "u16",
		"value": value,
		"tooltip": tooltip,
		"field_ref": {"channel": "timeline_header", "field": field},
	}
