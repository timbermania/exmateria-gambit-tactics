extends RefCounted
## A generic **inspection target** for the Effect Studio inspector: `{kind, ref}`.
## Generalizes ADR-0071's "a span dispatches to its per-archetype projector" one
## level up — the inspector no longer renders "a span", it renders a *target* whose
## `kind` selects a projector (InspectorProjectorRegistry) and whose `ref` is an
## **opaque, kind-specific payload only that kind's projector reads**:
##   span    → {"span_id": String}          (the timeline's drill-in handle)
##   emitter → {"index": int}               (0-based emitter index == emitter_id - 1)
##   frame   → {"frameset_id": …, "index": …}   (a future kind; the registry stays closed)
## The registry routes on `kind` and NEVER inspects `ref`, so a new kind brings its
## own (possibly composite) identity without touching the core — the whole point of
## the opaque ref (grilling session, 2026-07-28).
##
## Pure value type — plain Dictionaries, no nodes. No `class_name` (ADR-0004);
## preloaded by path like the other effect-studio scripts.

## The timeline's drill-in handle to whatever a keyframe span addresses.
static func span(span_id: String) -> Dictionary:
	return {"kind": "span", "ref": {"span_id": span_id}}


## A bare emitter, reached from a child-ref link, a provenance edge, or the browser.
## `index` is the 0-based emitter index (== emitter_id - 1), matching emitter_view /
## emitter_color / _emitter_children so the emitter projector reuses them unchanged.
static func emitter(index: int) -> Dictionary:
	return {"kind": "emitter", "ref": {"index": int(index)}}


## A shared, effect-global SoundContainer (ADR-0085 TIER-2), reached by following a
## trigger's sound_id reference (container_idx = sound_id - 2). `index` is the 0-based
## container index; the SoundContainerProjector reads the pre-projected view from the score.
static func container(index: int) -> Dictionary:
	return {"kind": "container", "ref": {"index": int(index)}}


## A FEDS pair (ADR-0085 TIER-3) — the reusable sound itself, reached by following a
## container's Sound-slot reference (pair_idx = resolved id - 1). The FedsPairProjector
## reads the pre-projected pair view (FedsPairModel) from the score.
static func pair(pair_idx: int) -> Dictionary:
	return {"kind": "pair", "ref": {"pair_idx": int(pair_idx)}}


## The effect-level GLOBAL settings surface (#271) — timeline durations / effect flags /
## time scale. Exactly one per effect, so the ref is degenerate (empty): the projector reads
## the whole effect_data, not an index. The new `Target` kind the small-byte cluster needed.
static func effect_settings() -> Dictionary:
	return {"kind": "effect_settings", "ref": {}}


## The effect's TEXTURE sheet (#280) — the indexed image every frame UVs into, and the
## file's last section. Exactly one per effect, so the ref is degenerate (empty) like
## `effect_settings`: the projector reads the whole effect_data.
static func texture() -> Dictionary:
	return {"kind": "texture", "ref": {}}


## A frameset — the flat-indexed group of frames a sequence's FRAME opcode selects (#278).
## `index` addresses `effect_data.framesets[index]` directly (the flat array, group 0's
## framesets first — see `EffectData.frameset_group_offsets`).
static func frameset(index: int) -> Dictionary:
	return {"kind": "frameset", "ref": {"index": int(index)}}


## A single frame within a frameset (#278) — the 24-byte sprite-rect record (UV, vertices,
## palette_id, blend mode). Two-dimensional address, mirroring FramesetChannel's field_ref:
## `frameset_index` (into the flat framesets array) + `frame_index` (into that frameset's
## `frames` array).
static func frame(frameset_index: int, frame_index: int) -> Dictionary:
	return {"kind": "frame", "ref": {"frameset_index": int(frameset_index), "frame_index": int(frame_index)}}


## An animation SEQUENCE — the opcode stream a particle plays to pick which frameset
## shows for how long (#275). `index` addresses `effect_data.animations[index]`.
##
## `group` is the frameset GROUP the sequence is seen through (an emitter's `anim_param`)
## — the LENS its FRAME opcodes resolve their relative frameset indices against, NOT a
## second place to navigate to (there is no group target kind). It rides the ref because
## a FRAME opcode is ambiguous without it: `opcode.frameset + frameset_group_offset(group)`
## means the same opcode reaches a different sprite depending on which emitter plays it.
## Baking it in at link-creation time — where the emitter is known — keeps a `ref` a
## SELF-CONTAINED address (ADR-0073's core promise) instead of something the projector
## has to recover from the nav stack, which would make a link's destination depend on how
## you arrived (ADR-0073 dec. 8).
##
## The group is part of the target's IDENTITY, so `animation(4, 0)` and `animation(4, 1)`
## are different targets and the back-stack will not dedupe them. It defaults to 0 — the
## honest answer for a sequence entered from the browser with no emitter context, and the
## only answer for the 383-of-401 effects that have a single frameset group.
static func animation(index: int, group: int = 0) -> Dictionary:
	return {"kind": "animation", "ref": {"index": int(index), "group": int(group)}}


static func kind(target: Dictionary) -> String:
	return str(target.get("kind", ""))


## The opaque payload — only the matching projector interprets its shape.
static func ref(target: Dictionary) -> Dictionary:
	return target.get("ref", {})


static func is_empty(target: Dictionary) -> bool:
	return target == null or target.is_empty() or kind(target) == ""


## Value equality (kind + ref) — the back-stack dedupes consecutive equal targets.
static func equals(a: Dictionary, b: Dictionary) -> bool:
	return kind(a) == kind(b) and ref(a) == ref(b)


## The inspector panel title for a target — the span keeps the historical
## "Keyframe — <id>" wording; an emitter reads "Emitter <index>".
static func title(target: Dictionary) -> String:
	match kind(target):
		"span": return "Keyframe — %s" % str(ref(target).get("span_id", ""))
		"emitter": return "Emitter %d" % int(ref(target).get("index", -1))
		"container": return "SoundContainer %d" % int(ref(target).get("index", -1))
		"pair": return "FEDS pair %d" % int(ref(target).get("pair_idx", -1))
		"effect_settings": return "Effect Settings"
		"texture": return "Texture"
		"frameset": return "Frameset %d" % int(ref(target).get("index", -1))
		"frame": return "Frame %d / %d" % [int(ref(target).get("frameset_index", -1)), int(ref(target).get("frame_index", -1))]
		"animation": return "Sequence %d%s" % [int(ref(target).get("index", -1)), _group_suffix(target)]
	return "Inspector"


## A short breadcrumb token for the nav trail, e.g. "emitter 5" or a span's lane.
## `effect_data`/`score` are optional context a kind may use to enrich the token
## (a span borrows its lane label when the score is passed); unknown kinds fall
## back to the raw ref so the trail is never blank.
static func label(target: Dictionary, effect_data = null, score = null) -> String:
	match kind(target):
		"span":
			var sid := str(ref(target).get("span_id", ""))
			if score != null:
				var lane_id := sid.split("#")[0] if "#" in sid else sid
				return "%s span" % lane_id
			return "span"
		"emitter":
			return "emitter %d" % int(ref(target).get("index", -1))
		"container":
			return "container %d" % int(ref(target).get("index", -1))
		"pair":
			return "pair %d" % int(ref(target).get("pair_idx", -1))
		"effect_settings":
			return "effect settings"
		"frameset":
			return "frameset %d" % int(ref(target).get("index", -1))
		"frame":
			return "frame %d/%d" % [int(ref(target).get("frameset_index", -1)), int(ref(target).get("frame_index", -1))]
		"animation":
			return "sequence %d%s" % [int(ref(target).get("index", -1)), _group_suffix(target)]
	return str(kind(target))


## The frameset-group lens, named only when it actually shifts something. Group 0 is the
## default and the whole story for 383 of 401 effects, so spelling it out everywhere would
## be noise in the title bar and the breadcrumb trail; a NON-zero group changes which
## sprites the sequence shows, so it earns the words.
static func _group_suffix(target: Dictionary) -> String:
	var g := int(ref(target).get("group", 0))
	return "" if g == 0 else " · group %d" % g
