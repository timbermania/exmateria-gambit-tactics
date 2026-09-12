extends RefCounted
## The **container** target-kind projector (ADR-0073 / ADR-0085 TIER-2) — the read-only
## SoundContainer view. A timeline sound_id resolves THROUGH a shared, effect-global
## SoundContainer (container_idx = sound_id - 2) before reaching a FEDS pair; this makes
## that selection logic legible: the mode, the DISTINCT ids it can fire, and each id's
## FEDS pair. The header carries the "used by N" reverse-links to every referencing
## trigger — the shared-object blast radius an author must see before editing.
##
## THIN reader: the studio threads the pre-projected views (SoundContainerModel) into the
## SCORE under "sound_containers", so this projector reads score["sound_containers"][index]
## and never touches the resolver / FEDS bank itself — the same way EmitterTargetProjector
## reads emitter_view. A missing view is inert (empty), never a crash. No class_name
## (ADR-0004); load()ed by path.

const _Fields = preload("res://src/effects/studio/ProjectorField.gd")
const InspectionTarget = preload("res://src/effects/studio/InspectionTarget.gd")

## The pre-projected view for this target's container index, or {} if the score carries
## no view for it (an out-of-range index / no sound_containers section).
static func _view(target: Dictionary, score) -> Dictionary:
	if score == null:
		return {}
	var index := int(target.get("ref", {}).get("index", -1))
	var views = score.get("sound_containers", [])
	if not (views is Array) or index < 0 or index >= views.size():
		return {}
	return views[index]


## The header: the container's identity (index + mode) then the "used by" reverse-nav
## links (ADR-0073) to every trigger span that references this shared container. Empty
## when the score has no view for the target.
static func header(target: Dictionary, _effect_data, score) -> Array:
	var view := _view(target, score)
	if view.is_empty():
		return []
	var used_by := int(view.get("used_by", 0))
	var rows: Array = [
		{"label": "Container", "value": "index %d · %s" % [
			int(view.get("index", -1)), str(view.get("mode_author_label", view.get("mode_name", "")))]},
		{"label": "Used by", "value": "%d trigger%s" % [used_by, "" if used_by == 1 else "s"]},
	]
	rows.append_array(view.get("provenance", []))
	return rows


## The sound-selection section, laid out as an AUTHORING workflow, not RE plumbing
## (#289 redesign): (1) the whole 5-mode space as one always-visible radio list, each
## row previewing the sequence it WOULD play off the current Sound A/B/C ids — so a
## mode's audible outcome is readable without auditioning each; (2) the three shared
## Sound A/B/C slots as FEDS-bank-entry pickers (the modes all draw from the same three
## slots), each with a ▶ one-shot preview, dead slots dimmed "(unused)" but still
## editable; (3) one Audition button for the selected mode's full repeat pattern.
## Empty when the score has no view.
static func sections(target: Dictionary, _effect_data, score) -> Array:
	var view := _view(target, score)
	if view.is_empty():
		return []
	# EDITABLE (TIER-2, #289): the raw resolver inputs — mode (radio) + the three ids
	# (bank-entry enums) — lower through the sound_container channel at the choke point; a
	# container is shared/effect-global (ADR-0073) so its address is just the index. The
	# radio details are DERIVED previews that refresh after every edit.
	var index := int(view.get("index", -1))
	var used: Array = view.get("used_slots", ["a", "b", "c"])
	var bank_size := int(view.get("bank_size", 0))
	var fields: Array = [
		_id_edit(index, "id_a", "Sound 1", int(view.get("id_a", 0)), used.has("a"), bank_size),
		_id_edit(index, "id_b", "Sound 2", int(view.get("id_b", 0)), used.has("b"), bank_size),
		_id_edit(index, "id_c", "Sound 3", int(view.get("id_c", 0)), used.has("c"), bank_size),
		_pattern_radio(index, int(view.get("mode", 0)), view.get("mode_choices", [])),
		# HEAR the selected pattern: fire this container repeatedly through the SFX
		# engine (host-wired).
		_audition_action(index),
	]
	# TIER-3 drill-in (ADR-0073 follow-the-reference): each DISTINCT valid FEDS pair
	# this container can emit is a clickable link into the pair editor — the sound
	# CONTENT lives one tier below the selection logic. Author-facing vocabulary: the
	# link names the same "Sound bank entry N" the slot pickers list (pair_idx == N).
	for p in view.get("pairs", []):
		if not bool(p.get("valid", false)):
			continue
		fields.append({
			"name": "Sound content",
			"shape": "link",
			"label": "→ edit Sound bank entry %d (notes & opcodes)" % int(p.get("pair_idx", -1)),
			"target": InspectionTarget.pair(int(p.get("pair_idx", -1))),
			"tooltip": "Open the sound itself — its notes and opcodes — in the sound " +
				"editor. Shared content: every container slot pointing at this entry " +
				"plays the same bytes.",
		})
	# The step truth ("a single event only ever plays step 1") is HOVER-ONLY — it rides
	# the pattern radio + Audition tooltips (_STEP_TRUTH). A long const row here inflated
	# the inspector's shared value column and pushed the whole second column-pair
	# (Sound 2 / pattern / this link) off-window (user feedback 2026-08-11).
	return [{"title": "Sound selection", "fields": fields}]


# The step truth an author must know to ever hear step 2 (the counter advances per
# sound EVENT, and the studio resets it each play) — phrased as the action to take.
# Hover-only: appended to the pattern radio + Audition tooltips, never a row.
const _STEP_TRUTH := "The pattern advances ONE step each time a sound event plays " + \
	"this container — a single event only ever plays step 1 (Sound 1). To hear " + \
	"step 2 in the effect, add a 2nd sound event playing this container."


## An `action` field the inspector renders as a button; pressing it asks the host to fire
## this container repeatedly through the SFX engine so the author hears the step pattern.
static func _audition_action(index: int) -> Dictionary:
	return {
		"name": "Audition",
		"shape": "action",
		"label": "▶ Audition pattern",
		"tooltip": "Fire this container 6 times in a row so the step pattern is audible. "
			+ _STEP_TRUTH,
		"action": {"kind": "audition_container", "index": index},
	}


## The EDITABLE pattern field as an always-visible `radio` list: every mode with its
## slot-number step pattern ("1  2  1  2 …") as the row detail, so the whole pattern
## space is scannable at once and picking is one click. The selected value IS the mode
## byte the encoder writes. Patterns name SLOTS (Sound 1/2/3), not raw ids, so they hold
## still while the author re-points a slot at another bank entry.
static func _pattern_radio(index: int, mode: int, mode_choices: Array) -> Dictionary:
	var choices: Array = []
	for c in mode_choices:
		var value := int(c.get("value", 0))
		choices.append({
			"value": value,
			"label": str(c.get("label", "")),
			"detail": _pattern_detail(value, c.get("pattern", [])),
		})
	return {
		"name": "Play pattern",
		"shape": "edit",
		"editor": "radio",
		"value": mode,
		"choices": choices,
		"tooltip": "Which of Sound 1/2/3 plays on each successive step. " + _STEP_TRUTH,
		"field_ref": _container_ref(index, "mode"),
	}


## A pattern row's step read-out: the slot numbers it plays, in order ("1  2  1  2 …").
## A pass-through mode (5+) plays no slot at all.
static func _pattern_detail(mode: int, pattern: Array) -> String:
	if mode >= 5:
		return "passes the trigger's own sound id through"
	if pattern.is_empty():
		return ""
	var parts: Array = []
	for step in pattern:
		parts.append(str(step))
	return "  ".join(parts) + " …"


## An EDITABLE bank-entry picker for one of the container's shared numbered sound slots
## (Sound 1/2/3 = id_a/id_b/id_c): an `enum` over the effect's Sound bank entries
## (pair_idx = id-1) — picking a sound is a click, not a raw-byte guess — plus a ▶
## `preview_action` so the author can hear the currently-selected entry alone. A raw
## byte outside the bank stays representable (an honest extra choice), so nothing is
## ever silently rewritten.
static func _id_edit(index: int, field: String, label: String, value: int, used: bool, bank_size: int) -> Dictionary:
	# When the selected pattern never reads this slot, the byte is dead — flag it in the
	# name AND tooltip so an author does not waste an edit on a no-op (still editable:
	# the pattern can change to one that plays it).
	var name := label if used else "%s (not played)" % label
	var tip := "A sound this container can play — the pattern below decides on which steps. Press ▶ to hear just this entry." if used \
		else "Unused: not played by the selected pattern — still editable; pick a pattern whose steps include it."
	var choices: Array = []
	if value < 1 or value > bank_size:
		choices.append({"value": value, "label": "raw id %d (no bank entry)" % value})
	for v in range(1, bank_size + 1):
		choices.append({"value": v, "label": "Sound bank entry %d" % (v - 1)})
	return {
		"name": name,
		"shape": "edit",
		"editor": "enum",
		"value": value,
		"choices": choices,
		"preview_action": {"kind": "audition_sound", "id": value},
		"tooltip": tip,
		"field_ref": _container_ref(index, field),
	}


## One field's write-side field_ref for the choke point (EffectEditSession.apply_edit). A
## SoundContainer is shared/effect-global (ADR-0073), so its address is ONE-dimensional —
## just the container `index` — unlike the sound TIMELINE's three.
static func _container_ref(index: int, field: String) -> Dictionary:
	return {"channel": "sound_container", "index": index, "field": field}


