extends RefCounted
## The ADR-0085 TIER-2 "sound-selection logic" model — makes a shared, effect-global
## SoundContainer LEGIBLE. A timeline sound_id resolves THROUGH a container
## (container_idx = sound_id-2) before reaching a FEDS pair; the container's `mode` +
## id_a/id_b/id_c + a stateful per-container fire counter can fire a DIFFERENT concrete
## id on successive fires (parity/cycle). This model surfaces the mode, the DISTINCT
## set of ids the container can fire, and (later) each id's FEDS pair + "used by N".
##
## Depth: the 5-mode truth lives in EffectSoundResolver. This model does NOT re-derive
## which of a/b/c each mode emits — it DRIVES a fresh resolver forward and observes the
## distinct results, so the resolver stays the single source of that truth.
##
## Pure value logic — no scene, no SPU. No class_name (ADR-0004); load()ed by path like
## the other effect-studio scripts.

const Resolver = preload("res://addons/exmateria_sound/runtime/effect_sound_resolver.gd")
const InspectionTarget = preload("res://src/effects/studio/InspectionTarget.gd")

# Fires to drive when enumerating a container's emitted set. Every mode's cycle is
# covered by four fires: DIRECT (period 1), PARITY (2), DIRECT_B (a-then-b), PARITY_B
# and TRIPLE_CYCLE (3). A fresh resolver starts at count 0, so fire 0 is the honest
# first-fire representative (matches SoundGhostProjector.resolve_pair_idx).
const _DRIVE_FIRES := 4

# The resolver's mode vocabulary (effect_sound_resolver.gd §modes). 5+ passes the
# timeline sound_id through unchanged.
const _MODE_NAMES := {
	0: "DIRECT_A", 1: "PARITY_A", 2: "DIRECT_B", 3: "PARITY_B", 4: "TRIPLE_CYCLE",
}

# AUTHOR-facing labels: what the container plays across successive fires. The RE
# mode_name says nothing about the audible result, so authoring reads off these instead
# (mirrors the resolver §modes fire table). Slots are NUMBERED 1/2/3 (id_a/id_b/id_c) —
# the order they enter play — per the #289 redesign; mode 3's label follows the real
# fire table (after step 1 the alternation STARTS on slot 3, not 2). Mode 5+ passes the
# timeline id through.
const _MODE_AUTHOR_LABELS := {
	0: "Always Sound 1",
	1: "Alternate 1 / 2",
	2: "Sound 1 once, then 2",
	3: "1 once, then alternate 3 / 2",
	4: "Cycle 1 → 2 → 3",
}

# Which of the three id slots each mode ever READS (from the fire table). The others are
# dead bytes for that mode — the inspector flags them so an author does not edit a no-op.
const _MODE_USED_SLOTS := {
	0: ["a"],
	1: ["a", "b"],
	2: ["a", "b"],
	3: ["a", "b", "c"],
	4: ["a", "b", "c"],
}

# Fires to show in the ordered "plays on repeat" sequence — two full cycles of the
# longest period (TRIPLE_CYCLE = 3) so the repeat is visible.
const _SEQUENCE_FIRES := 6


## The resolver's name for a container mode; "DEFAULT" (pass-through) for mode 5+.
static func mode_name(mode: int) -> String:
	return _MODE_NAMES.get(mode, "DEFAULT")


## The AUTHOR-facing label for a mode — what it plays across fires, not the RE name.
## Mode 5+ (pass-through) reads as "Pass sound id through".
static func mode_author_label(mode: int) -> String:
	return _MODE_AUTHOR_LABELS.get(mode, "Pass sound id through")


## The id slots (subset of ["a","b","c"], in that order) a mode actually reads. Empty
## for the pass-through modes (5+), which read no slot — the timeline id goes straight out.
static func used_slots(mode: int) -> Array:
	return _MODE_USED_SLOTS.get(mode, [])


## The ORDERED sound_ids a container fires on fires 0..n-1 (NOT the distinct set) — so an
## author sees the repeat pattern (a,b,a,b…). Drives a FRESH resolver so the per-fire
## semantics come from the resolver, not a re-derivation. Empty for an out-of-range index.
static func fire_sequence(containers_doc: Dictionary, index: int, n: int) -> Array:
	var raw: Array = containers_doc.get("containers", [])
	if index < 0 or index >= raw.size():
		return []
	var r = Resolver.from_sound_containers(containers_doc)
	r.reset_counters()
	var timeline_sid := index + 2
	var out: Array = []
	for _fire in range(n):
		out.append(r.resolve(index, timeline_sid))
	return out


## The ORDERED sound_ids container `index` WOULD fire on fires 0..n-1 if its mode were
## `mode` — the what-if preview behind the mode radio list, so an author reads every
## mode's audible outcome (from the container's CURRENT ids) without committing an edit
## or auditioning each. Drives a FRESH resolver over a single-entry doc with the mode
## overridden, so the per-mode semantics still come from the resolver — the model never
## re-derives the fire table. Empty for an out-of-range index.
static func sequence_for_mode(containers_doc: Dictionary, index: int, mode: int, n: int) -> Array:
	var raw: Array = containers_doc.get("containers", [])
	if index < 0 or index >= raw.size():
		return []
	var entry: Dictionary = (raw[index] as Dictionary).duplicate()
	entry["mode"] = mode
	var r = Resolver.from_sound_containers({"containers": [entry]})
	r.reset_counters()
	# The timeline id referencing this container stays index+2 so a pass-through mode
	# (5+) previews the id it would really emit.
	var timeline_sid := index + 2
	var out: Array = []
	for _fire in range(n):
		out.append(r.resolve(0, timeline_sid))
	return out


## The slot-number STEPS (1=id_a, 2=id_b, 3=id_c) mode `mode` plays on fires 0..n-1 —
## the pattern column of the mode radio list. Named in SLOTS, not raw ids, so the
## pattern stays stable when an author re-points a slot at a different bank entry.
## Derived by driving a fresh resolver over sentinel ids 1/2/3, so the fire table stays
## the resolver's. Empty for pass-through modes (5+), which play no slot at all.
static func pattern_for_mode(mode: int, n: int) -> Array:
	if mode >= 5:
		return []
	var r = Resolver.from_sound_containers({"containers": [
		{"mode": mode, "id_a": 1, "id_b": 2, "id_c": 3, "index": 0}]})
	r.reset_counters()
	var out: Array = []
	for _fire in range(n):
		out.append(r.resolve(0, 2))
	return out


## The mode radio-list choices for container `index`: every authorable mode (0-4, plus
## the container's CURRENT mode when it's a 5+ pass-through, so a real byte is never
## unrepresentable) with its author label and its what-if fire sequence off the current
## ids. The projector renders these as one always-visible radio list — the whole mode
## space scannable at once, no dropdown hiding 4/5 of the model.
static func mode_choices(containers_doc: Dictionary, index: int) -> Array:
	var raw: Array = containers_doc.get("containers", [])
	if index < 0 or index >= raw.size():
		return []
	var modes: Array = [0, 1, 2, 3, 4]
	var current: int = int((raw[index] as Dictionary).get("mode", 0))
	if not modes.has(current):
		modes.append(current)
	var out: Array = []
	for m in modes:
		out.append({
			"value": m,
			"label": mode_author_label(m),
			"seq": sequence_for_mode(containers_doc, index, m, _SEQUENCE_FIRES),
			"pattern": pattern_for_mode(m, _SEQUENCE_FIRES),
		})
	return out


# Ordinal words for the fire-choice labels. Six covers _SEQUENCE_FIRES; anything past
# it falls back to "Nth" (unreachable today — no mode has a period above 3).
const _ORDINALS := {1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 5: "5th", 6: "6th"}


## The chain's deepest slot as a CHOICE among this container's fires (ADR-0085 amendment
## 2026-08-21, decision 3) — one entry per DISTINCT pair, in the order the container first
## reaches it, labelled by the ORDINAL of that fire and the SLOT it comes from:
## "1st fire · Sound 1 · entry 0" / "2nd fire · Sound 2 · entry 2".
##
## **No reachability claim is made.** Whether a 2nd fire ever happens in a cast turns on the
## per-container counter — which our runtime resets every cast and the ROM may never reset
## (`0x801B9250` is touched at two addresses, both inside `lookup_sound_effect`; see the
## amendment's "out of scope, but found"). The fire ORDINAL is true under either reading, so
## this label survives however that question lands, and nothing here dims a sibling.
##
## Ids come from `fire_sequence` (a fresh resolver) and slots from `pattern_for_mode` (a
## fresh resolver over sentinel ids), so the fire table stays the resolver's — as everywhere
## else in this file. Empty for an out-of-range index.
static func pair_choices(containers_doc: Dictionary, index: int, bank_size: int) -> Array:
	var ids: Array = fire_sequence(containers_doc, index, _SEQUENCE_FIRES)
	if ids.is_empty():
		return []
	var raw: Array = containers_doc.get("containers", [])
	var mode: int = int((raw[index] as Dictionary).get("mode", 0))
	var slots: Array = pattern_for_mode(mode, _SEQUENCE_FIRES)
	var out: Array = []
	var seen: Array = []
	for k in range(ids.size()):
		var pair_idx: int = int(ids[k]) - 1
		# A dead slot resolves to no pair at all (id 0 → pair_idx −1). It is not a second
		# choice — counting it as one is exactly what put the first corpus figures three
		# points off every derived number.
		if pair_idx < 0 or seen.has(pair_idx):
			continue
		seen.append(pair_idx)
		var slot: int = int(slots[k]) if k < slots.size() else 0
		out.append({
			"ordinal": k + 1,
			"slot": slot,
			"id": int(ids[k]),
			"pair_idx": pair_idx,
			"valid": pair_idx < bank_size,
			"label": "%s fire · %s · entry %d" % [
				str(_ORDINALS.get(k + 1, "%dth" % (k + 1))),
				("Sound %d" % slot) if slot > 0 else "pass-through",
				pair_idx],
		})
	return out


## The DISTINCT concrete sound_ids a container can fire, in first-seen (fire order).
## Element 0 is the count-0 representative. Drives a FRESH resolver forward so the
## per-mode semantics come from the resolver, not a re-derivation here. Empty for an
## out-of-range index or an empty doc.
static func emitted_ids(containers_doc: Dictionary, index: int) -> Array:
	var raw: Array = containers_doc.get("containers", [])
	if index < 0 or index >= raw.size():
		return []
	var r = Resolver.from_sound_containers(containers_doc)
	r.reset_counters()
	# The timeline sound_id that references container `index` is index+2 (>=2, non-skip).
	var timeline_sid := index + 2
	var out: Array = []
	for _fire in range(_DRIVE_FIRES):
		var got: int = r.resolve(index, timeline_sid)
		if got >= 1 and not out.has(got):
			out.append(got)
	return out


## The composite, legible view of one container: its index, raw mode + mode_name, the
## DISTINCT emitted ids, each id's FEDS pair (pair_idx = resolved-1, with in-range
## validity against the bank), and how many timeline triggers reference it. Empty for an
## out-of-range index. This is what SoundContainerProjector renders and the browser lists.
static func container_view(containers_doc: Dictionary, feds_bank, effect_sound,
		index: int) -> Dictionary:
	var raw: Array = containers_doc.get("containers", [])
	if index < 0 or index >= raw.size():
		return {}
	var entry: Dictionary = raw[index]
	var mode: int = int(entry.get("mode", 0))
	var ids: Array = emitted_ids(containers_doc, index)
	var num_pairs: int = feds_bank.num_pairs if feds_bank != null else 0
	var pairs: Array = []
	for id in ids:
		var pair_idx: int = int(id) - 1
		pairs.append({
			"id": int(id),
			"pair_idx": pair_idx,
			"valid": pair_idx >= 0 and pair_idx < num_pairs,
		})
	var provenance := container_provenance(effect_sound, index)
	return {
		"index": index,
		"mode": mode,
		"mode_name": mode_name(mode),
		# Legibility (author-facing, #289 follow-on): the sequence label, the slots this
		# mode actually reads (the rest are dead bytes), and the ORDERED fire sequence so
		# the projector can show "plays on repeat" without re-deriving mode truth.
		"mode_author_label": mode_author_label(mode),
		"used_slots": used_slots(mode),
		"fire_sequence": fire_sequence(containers_doc, index, _SEQUENCE_FIRES),
		# The always-visible mode radio list (every mode + its what-if sequence off the
		# current ids) and the bank extent the Sound A/B/C pickers enumerate.
		"mode_choices": mode_choices(containers_doc, index),
		"bank_size": num_pairs,
		# The raw resolver inputs, so the projector can seed the editable Pick mode + id cells
		# directly off the view (TIER-2 editing, #289) without re-reading the doc.
		"id_a": int(entry.get("id_a", 0)),
		"id_b": int(entry.get("id_b", 0)),
		"id_c": int(entry.get("id_c", 0)),
		"emitted_ids": ids,
		"pairs": pairs,
		"used_by": provenance.size(),
		"provenance": provenance,
	}


## Every container in the doc as a view, in index order — so an orphan container
## (referenced by no trigger) is still present for the exhaustive browser (ADR-0073).
static func container_views(containers_doc: Dictionary, feds_bank,
		effect_sound) -> Array:
	var raw: Array = containers_doc.get("containers", [])
	var out: Array = []
	for i in range(raw.size()):
		out.append(container_view(containers_doc, feds_bank, effect_sound, i))
	return out


## How many timeline sound triggers reference container `index` — the ADR's "used by N
## triggers" honesty for a shared object. Only ACTUALLY-FIRING triggers count (the
## _sound_spans firing window), so an out-of-window terminator or a skip never inflates it.
static func used_by(effect_sound, index: int) -> int:
	return _referencing_triggers(effect_sound, index).size()


## Clickable back-links (ADR-0073 reverse-nav) to every trigger span that references
## this shared container, so an author sees the blast radius before editing it. Each row
## mirrors emitter_provenance: {label, link:{label, target}} where the target is the
## trigger's own span (InspectionTarget.span "sound:<phase>:<ci>#<i>").
static func container_provenance(effect_sound, index: int) -> Array:
	var rows: Array = []
	for t in _referencing_triggers(effect_sound, index):
		var span_id: String = "sound:%s:%d#%d" % [t.phase, t.ci, t.i]
		rows.append({
			"label": "Used by",
			"link": {
				"label": "sound %s ch%d kf%d" % [t.phase, t.ci, t.i],
				"target": InspectionTarget.span(span_id),
			},
		})
	return rows


## The firing triggers that reference container `index`, as [{phase, ci, i}] — the single
## windowed walk both used_by and container_provenance share. A trigger fires only within
## the strict `< max_keyframe` window and only when sound_id_fires (>=2); it references
## container `index` when sound_id-2 == index.
static func _referencing_triggers(effect_sound, index: int) -> Array:
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
			var ci: int = int(ch.get("channel_index", 0))
			var kfs = ch.get("keyframes", [])
			if not (kfs is Array):
				continue
			var last_idx: int = mini(kfs.size(), int(ch.get("max_keyframe", 0)))
			for i in range(last_idx):
				var sid: int = int(kfs[i].get("sound_id", 0))
				if sid >= 2 and sid - 2 == index:
					out.append({"phase": phase, "ci": ci, "i": i})
	return out
