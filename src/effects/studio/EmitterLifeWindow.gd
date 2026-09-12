extends RefCounted
## THE PARTICLE-LIFE WINDOW — how many game frames of an emitter's over-life curves the
## renderer can ever read, and the honest axis for authoring colour (CONTEXT.md *Colour
## dead zone*, ADR-0089's 2026-08-19 dead-zone amendment).
##
## This was one inline derivation inside `EffectScoreModel._emitter_sections`, which was
## fine while the inspector was the only surface that had a colour axis. It is not fine
## now: the ADR-0089 colour-move amendment puts the EDITABLE colour track in the player
## column, and the player column had been drawing its ribbon on
## `get_animation_display_length` instead. Those two windows are not interchangeable —
## measured over all 401 corpus effects, of 2622 colour-enabled emitters they agree for
## 1412 (53.9%) and disagree for 1204 (45.9%), and 698 differ by more than 8 frames. So a
## second copy of this rule does not drift by a pixel, it relocates keyframes.
##
## ONE derivation, therefore, called by both.
##
## The rule itself was CORRECTED on 2026-08-20 — it had been reading two fields the spawner
## never samples. See `for_emitter` for what changed, what it cost, and the primary source.
##
## No `class_name` (ADR-0004); preloaded by path like the other effect-studio scripts.


## `{n, note, kind}` for an emitter's over-life window. `n` is -1 when unresolvable, which
## the callers answer by falling back to the whole 160-sample curve rather than inventing a
## length.
##
## THE WINDOW IS THE UPPER BOUND OF THE LIFETIME THE SPAWNER CAN DRAW, and that is decided
## by whether the emitter has a LIFETIME CURVE — not by counting minus-ones across all four
## fields, which is what this used to do (see the 2026-08-20 correction below).
##
## `ActiveEmitter._create_particle` draws the lifetime through
## `ParticlePhysics.interpolate_range(min_start, max_start, min_end, max_end, curve, …)`,
## and that function's FIRST LINE is `if curve == null: return _srange(min_start, max_start)`.
## So with no lifetime curve the END PAIR IS NEVER SAMPLED AT ALL — it is inert bytes. The
## ROM branches the same way: `emitter_control_routine` (0x801A634C) reads the packed curve
## nibble and, when it is 0 (index −1), takes the `_start` pair straight, only calling
## `lerp_u8(start, end, factor)` on the other branch
## (`research/working_documents/CURVE_ANALYSIS.md`, the radial-velocity block, which is the
## unambiguous instance of the pattern).
##
## Measured over all 401 corpus effects: **9 of 3227 emitters have a lifetime curve** (8 of
## the 2622 colour-enabled ones). For the other 99.7% the last two fields do nothing.
##
##   * no lifetime curve → `max(min_start, max_start)`. `max` of the PAIR and not just
##     `max_start` because `_srange(a, b)` is `randf_range(a, b)`, which honours whichever
##     is larger — one corpus emitter is stored `min_start` > `max_start`.
##   * a lifetime curve → `max` of all four. `min_val` and `max_val` are each a lerp between
##     their start and end, so over t ∈ [0,1] the largest reachable draw is the largest of
##     the four corners. (This is the OLD rule, and for these 9 it was right.)
##   * a negative bound → animation-driven: the particle lives exactly as long as its ONE
##     animation plays, and the window IS `get_animation_display_length`.
##
## THE 2026-08-20 CORRECTION, because this module shipped a rule that was wrong for 313 of
## 2622 colour emitters (11.9%) and the ADR quoted its output as a finding.
## `tools/census_life_window.gd` is the instrument; every number below is its output:
##
## The old rule was `if min(all four) >= 0 → max(all four), else the animation length`. Both
## halves are wrong in the same way — they read the END pair, which nothing reads.
##
##   * 309 emitters got a window LARGER than the renderer can ever sample (median 6 frames
##     of phantom life, p90 12, max 32), because `max(all four)` picked up a `max_end` the
##     spawner never looks at. That is dead zone drawn as live — the exact fault
##     `ColourKeyframeTrack.in_window` exists to prevent, one level up.
##   * 4 got one too SMALL (max 9), the other way to be wrong: live ages hidden.
##   * The rest agreed by luck: the start pair is all-or-nothing in this corpus (1363
##     colour emitters have BOTH start fields at −1, 1258 have both real, 1 is mixed), so
##     "is any of the four −1" usually answers the same as "is the start pair −1".
##
## And the ADR-0089 headline it fed — *"1370 animation-driven emitters agree with the
## animation's display length 100% BY CONSTRUCTION"* — needs restating rather than
## retracting. 1361 of those carry REAL values in their end pair, which looks like the rule
## discarding authored data. It is not: for 1348 of them the −1 sits in the START pair, the
## only pair read, so they genuinely ARE animation-driven and the real numbers beside them
## are inert. The classification was right; the reason given for it was not.
##
## After the correction the split is 1363 animation-driven / 1259 authored (the ADR said
## 1370 / 1246), so the headline moves by 7 emitters and its ARGUMENT moves entirely: the
## two windows agree for animation-driven emitters because that class is DEFINED as the
## animation length, which is a tautology and never was evidence for the life axis. The
## evidence for the axis is that the renderer reads a lifetime — which is also, now, the
## thing this module is finally measuring.
static func resolve(effect_data, emitter_index: int) -> Dictionary:
	if effect_data == null or not (effect_data.emitters is Array) \
			or emitter_index < 0 or emitter_index >= effect_data.emitters.size():
		return {"n": -1, "note": "no emitter", "kind": "unresolved"}
	var em = effect_data.emitters[emitter_index]
	if em == null:
		return {"n": -1, "note": "no emitter", "kind": "unresolved"}
	return for_emitter(em, effect_data)


## The same rule against an already-resolved emitter object — the form `EffectScoreModel`
## calls, since it is already holding one.
static func for_emitter(em, effect_data) -> Dictionary:
	var curved: bool = has_lifetime_curve(em, effect_data)
	var hi: int = maxi(int(em.lifetime_min_start), int(em.lifetime_max_start))
	if curved:
		hi = maxi(hi, maxi(int(em.lifetime_min_end), int(em.lifetime_max_end)))
	if hi >= 0:
		return {"n": hi, "kind": "authored",
			"note": "max authored lifetime%s" % (" (lifetime curve)" if curved else "")}
	# Animation-driven (Life = −1). Unresolvable (no animation, or an `anim_index` pointing
	# nowhere — a u8 with no referential guarantee) keeps the −1 fallback and says so.
	var anim_len: int = -1
	if effect_data != null and effect_data.has_method("get_animation_display_length"):
		anim_len = int(effect_data.get_animation_display_length(int(em.anim_index)))
	if anim_len > 0:
		return {"n": anim_len, "kind": "animation_driven",
			"note": "animation-driven — %d-frame animation" % anim_len}
	return {"n": -1, "kind": "animation_driven",
		"note": "animation-driven (lifetime −1) — the full curve may play"}


## Does this emitter's lifetime actually ramp — i.e. would `ActiveEmitter._get_curve`
## hand `interpolate_range` a curve rather than null? MIRRORS that function exactly
## (missing key, negative index, and an index that resolves to nothing all mean "no"),
## because the whole window rule now hinges on this answer and a looser test here would
## quietly re-admit the end pair.
static func has_lifetime_curve(em, effect_data) -> bool:
	if em == null or not (em.curves is Dictionary) or not em.curves.has("lifetime"):
		return false
	var idx: int = int(em.curves["lifetime"])
	if idx < 0 or effect_data == null or not effect_data.has_method("get_curve"):
		return false
	return effect_data.get_curve(idx) != null
