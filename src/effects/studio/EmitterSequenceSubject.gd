extends RefCounted
## WHICH SEQUENCE THE PLAYER SHOWS on a target that addresses an EMITTER — the pure
## derivation ADR-0100's amended decision 1 rests on (CONTEXT.md *Column subject*).
##
## The inspector row has one right-hand column. Until now only two target kinds claimed
## it: a `frame` parks the frameset canvas, an `animation` parks the sequence player. An
## `emitter` or a particle `span` claimed neither — so on the screen an author spends the
## most time in, 512px of the row sat empty beside 2000+px of fields that had to scroll.
##
## They claimed nothing for want of an ADDRESS, not for want of a reason. An emitter
## already carries both halves of one:
##
##   * `anim_index` — the animation sequence its particles play;
##   * `anim_param` — the frameset GROUP those FRAME opcodes resolve their relative
##     indices against (the LENS, ADR-0073 dec. 8). Not decoration: the same opcode
##     reaches a different sprite per group, so defaulting it to 0 draws the wrong sprite
##     convincingly rather than visibly.
##
## So the subject is derivable, and this is the one derivation of it.
##
## PURE, AND THE PURITY IS THE GUARD. What can go wrong here is invisible: an emitter
## index read as an animation index decodes a real sequence and draws real sprites, and
## the only way to see the mistake is to already know the right answer. The page therefore
## does not re-derive this from `_nav` at each of the three places that need it — it
## resolves once, stores what it BOUND, and the surfaces read that
## (`EffectStudioEmitterSequenceSubjectTest`).
##
## No `class_name` (ADR-0004); preloaded by path like the other effect-studio scripts.

const Target = preload("res://src/effects/studio/InspectionTarget.gd")


## `{emitter_index, anim_index, group}` for a target that addresses an emitter, or `{}`.
##
## `{}` is the honest answer for four different things, and the column treats them alike
## because the author's question is the same in all four — there is nothing to play:
## a target of another kind, a span that fires no emitter, an emitter index out of range,
## and an `anim_index` pointing nowhere. That last is not defensive padding: `anim_index`
## is a u8 with no referential guarantee (EffectKeyframeInspector says so where it disables
## the follow-link for exactly this reason), and out-of-range values are in the corpus.
static func resolve(target: Dictionary, effect_data, score: Dictionary) -> Dictionary:
	var ei: int = emitter_index_of(target, score)
	if ei < 0 or effect_data == null or not (effect_data.emitters is Array) \
			or ei >= effect_data.emitters.size():
		return {}
	var em = effect_data.emitters[ei]
	if em == null:
		return {}
	var anim_idx: int = int(em.anim_index)
	if not (effect_data.animations is Array) \
			or anim_idx < 0 or anim_idx >= effect_data.animations.size() \
			or not (effect_data.animations[anim_idx] is Dictionary):
		return {}
	return {"emitter_index": ei, "anim_index": anim_idx, "group": int(em.anim_param)}


## The emitter a target is ABOUT, or -1 — the whole of this module's kind-dispatch.
##
## An `animation` target answers -1 DELIBERATELY, and it is the one answer worth arguing.
## It has a perfectly good emitter in reach (the provenance ladder finds one for 85% of
## browsable targets) and answering with it would give the animation screen two sources of
## truth for the same column: its own ref, and a ladder rung. The ref wins there because
## the group in it is part of the target's IDENTITY — `animation(4, 0)` and `animation(4, 1)`
## are different targets — and a ladder cannot see which one the author asked for.
##
## A SPAN reaches its emitter only through the score, which is the reason `score` is a
## parameter at all: `span_id` is an opaque drill-in handle (ADR-0073) and the emitter it
## fires is a fact about the timeline, not about the ref. Non-particle spans carry no
## `emitter_index` key, so they fall out here without a lane-kind test.
static func emitter_index_of(target: Dictionary, score: Dictionary) -> int:
	match Target.kind(target):
		"emitter":
			return int(Target.ref(target).get("index", -1))
		"span":
			return _span_emitter_index(score, str(Target.ref(target).get("span_id", "")))
	return -1


## `EffectScoreModel.find_span`'s answer, reached through a guard it does not carry:
## `find_span` indexes `score["lanes"]` and `lane["spans"]` directly, which throws on the
## empty score the page holds before the first effect is loaded. `load()`ed at call time,
## not preloaded, to keep this out of the projectors' parse-time cycle.
static func _span_emitter_index(score: Dictionary, span_id: String) -> int:
	if score == null or span_id == "" or not score.has("lanes"):
		return -1
	var Model = load("res://src/effects/studio/EffectScoreModel.gd")
	var span: Dictionary = Model.find_span(score, span_id)
	return int(span.get("emitter_index", -1))
