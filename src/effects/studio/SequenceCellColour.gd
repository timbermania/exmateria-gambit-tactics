extends RefCounted
## The colour ONE sequence cell draws with, and which emitter's curves it came from —
## the two pure derivations ADR-0103 rests on (CONTEXT.md *Ribbon cut*, *Colour
## provenance*).
##
## Split out from both surfaces on purpose. A tint is invisible to a rect — a tinted
## thumbnail and an untinted one have identical geometry — so the assertable thing is the
## COLOUR HANDED TO THE PAINTER, and that is only assertable if it is a pure function.
## Everything here is a static over plain data: no nodes, no page state, no `_nav` field.
##
## THE CUT IS THE TRACE'S OWN NUMBERS. `SequenceTimeline.trace` accumulates each FRAME
## opcode's dwell as `maxi(1, (duration + 1) >> 1)`, which is exactly
## `ParticleAnimator.bake`'s expansion, and hands the window straight over as
## `cut_start`/`cut_ticks` — so cell k's piece `[a_k, a_k + n_k)` is read off the decode
## the player is already walking rather than re-derived. Indexing this by ROW instead of
## by the cell's own window is the obvious bug here.
##
## EVERY ROW NOW HAS A PIECE (2026-08-20, the ADR-0102 fencepost amendment). It used to
## be that offset and LOOP opcodes append nothing to the baked array, own zero ages and
## get no piece — "the strip has MORE ROWS THAN AGES" — so the first and last cells were
## untinted BY CONSTRUCTION, which is precisely the hole the amendment closes. A row is
## now a POSITION on the animation's clock, every position has a colour, and a row that
## occupies no time gets `cut_ticks == 1`: a still at the boundary it sits on. The
## `IDENTITY` bail below survives, with a narrower meaning — it now says "this is not a
## decoded cell", not "this cell owns no ages".
##
## No `class_name` (ADR-0004).

const EffectCurveClass = ExMateriaEffects.EffectCurve

## What an untinted cell hands the painter — the literal white it drew before ADR-0103,
## so `none` (15.0% of browsable targets) is byte-identical to the shipping look.
const IDENTITY := Color(1, 1, 1, 1)


## Cell `entry`'s colour at loop phase `t` — `colour(a_k + (t mod n_k) + 1)`, where
## `[a_k, a_k + n_k)` is the cell's own `cut_start`/`cut_ticks` window.
##
## ONE EXPRESSION AND NO BRANCH (dec. 2). `n_k == 1` — 83.6% of the corpus, because
## `duration=2` alone is 75.5% of all opcodes — makes the loop a still by arithmetic, and
## `n_k == 16` gives the ramp. A static-versus-animated branch would be two code paths
## for one formula. The amendment kept that promise: a cell owning no dwell is `n_k == 1`
## through `maxi` in the trace, so it arrives here as a still rather than as a case.
##
## THERE IS NO `+1`, AND THE ROM IS WHY (dec. 6-CORRECTED, 2026-08-20). This line carried
## `+ 1` on dec. 6's reasoning: `ParticleSubsystem` processes spawn requests before
## `_physics_step`, so age is 1 by the time `tick` reads `frames[0]`, and the Godot renderer
## therefore pairs baked frame k with colour sample k+1. That trace was correct about Godot
## and dec. 6 filed the correction against the RIBBON pending a read of the ROM it claimed to
## mirror. The ROM says the opposite, at the instruction level:
##
##   `update_all_particles` @ `0x801A2EB4` calls the render-state routine at `0x801A2FE0`
##   and only then, at `0x801A301C`, does `addiu v0,v0,1 / sh v0,0x50(s0)` — the colour
##   phase is incremented AFTER the draw, and wrapped to 0 at `0xa0` (160).
##   `update_particle_render_state` @ `0x801A5EA4` reads that same `0x50` as the sample
##   index (`0x801A5F90`: `curve_index * 0xa0 + base + phase`, gated on `0x4e & 0x40` —
##   `color_curve_enable` itself), and the spawn loop stores `0x50 = 0` on every particle
##   it allocates.
##
## So a particle draws its first baked frame with colour sample **0**. The PSX pairs frame
## k with sample k, no offset — which is what `ColourRibbon` was already doing. The drift is
## in the Godot renderer's spawn-vs-step ordering, and it is the thing to correct; the
## ribbon never needed one. The two studio surfaces agree again, and they agree with the ROM.
##
## STILL OPEN, and deliberately not changed here: the Godot RUNTIME still samples `p.age`
## after the increment (`EffectParticleRenderer._compute_color_modulate`), so the live player
## remains one sample ahead of both studio surfaces. That is a gameplay-visible ordering
## change in shared code, not a studio one.
##
## A missing curve is the IDENTITY, never black: `sample_by_frame` returns 0.0 on an
## empty curve, and a cell tinted to zero is a cell that vanishes under additive blend.
static func cell_color(entry: Dictionary, cr, cg, cb, t: int = 0) -> Color:
	if cr == null or cg == null or cb == null:
		return IDENTITY
	var n: int = int(entry.get("cut_ticks", 0))
	if n <= 0:
		return IDENTITY
	var age: int = int(entry.get("cut_start", 0)) + posmod(t, n)
	# The SHARED resolve the particle renderer paints with — dec. 1's invariant is that
	# this is the real render, so a second sampler here would be the drift it forbids.
	var c: Color = EffectCurveClass.sample_rgb(cr, cg, cb, age)
	return Color(c.r, c.g, c.b, 1.0)


## The colour provenance ladder (dec. 4) for the strip of `animation(anim_index, group)`,
## resolved against the inspection trail `nav`. Always states the rung it fired on:
##
##   `origin` an emitter is on the trail            → that emitter's curves
##   `only`   browsed, exactly ONE applicable       → its curves        (61.5% of targets)
##   `first`  browsed, several applicable           → the first, PLUS the others' count
##   `none`   no colour-enabled emitter             → no curves, no tint (15.0%)
##
## Modelled on `EffectStudioPage._pair_anchor`, which states its `source` the same way.
## "First applicable" is right and only honest LABELLED: 15.9% of browsable targets have
## two or more applicable emitters whose curves genuinely disagree, by a median 144/255.
##
## Returns `{rung, emitter_index, others, r, g, b}` where r/g/b are resolved `EffectCurve`
## objects or null. THE GROUP IS A LENS, NOT AN EMITTER INDEX (ADR-0073's self-contained
## ref) — which is exactly why the emitter has to be recovered from the trail or the
## cohort and cannot be read off the target.
static func provenance(nav: Array, effect_data, anim_index: int, group: int) -> Dictionary:
	for i in range(nav.size() - 1, -1, -1):
		var t = nav[i]
		if not (t is Dictionary) or str(t.get("kind", "")) != "emitter":
			continue
		var ei: int = int((t.get("ref", {}) as Dictionary).get("index", -1))
		if ei >= 0:
			return _rung("origin", ei, 0, effect_data)
	var cohort: Array = applicable_emitters(effect_data, anim_index, group)
	if cohort.is_empty():
		return _rung("none", -1, 0, effect_data)
	if cohort.size() == 1:
		return _rung("only", int(cohort[0]), 0, effect_data)
	return _rung("first", int(cohort[0]), cohort.size() - 1, effect_data)


## Every emitter that could be playing this strip's sequence through this strip's lens
## AND drives colour: `anim_index == index AND anim_param == group AND (flags_lo & 0x40)`,
## with all three curves actually resolvable. The last clause is not paranoia — an
## unresolvable curve samples 0.0, and a cell tinted to black is a cell that vanishes.
static func applicable_emitters(effect_data, anim_index: int, group: int) -> Array:
	var out: Array = []
	if effect_data == null or not (effect_data.emitters is Array):
		return out
	for i in range(effect_data.emitters.size()):
		var em = effect_data.emitters[i]
		if em == null or int(em.anim_index) != anim_index or int(em.anim_param) != group:
			continue
		if not bool(em.flags.get("color_curve_enabled", false)):
			continue
		if _curves(effect_data, i).get("r") == null:
			continue
		out.append(i)
	return out


## The `origin` rung for an emitter named DIRECTLY rather than recovered from the trail.
##
## The ladder above exists because a strip's target is a sequence seen through a lens and
## never an emitter, so the emitter has to be FOUND. On an `emitter` or particle `span`
## target it does not: the target is the emitter, and provenance is a fact about it rather
## than a search. Same rung, same shape, no walk — and no dependence on how the author got
## there, which is what a trail walk would smuggle in (a span drilled to from emitter 3
## would answer 3 for the emitter it actually fires).
static func for_emitter(effect_data, emitter_index: int) -> Dictionary:
	return _rung("origin", emitter_index, 0, effect_data)


## The rung, plus the emitter's resolved curves so a caller never re-walks the data.
static func _rung(rung: String, emitter_index: int, others: int, effect_data) -> Dictionary:
	var c: Dictionary = _curves(effect_data, emitter_index)
	return {"rung": rung, "emitter_index": emitter_index, "others": others,
		"r": c.get("r"), "g": c.get("g"), "b": c.get("b")}


## An emitter's three colour curves, or three nulls when colour is off, the emitter is
## out of range, or any channel is missing/empty. All-or-nothing: a partial resolve would
## tint two channels and zero the third, which reads as a colour cast rather than as the
## absence it is.
static func _curves(effect_data, emitter_index: int) -> Dictionary:
	var none := {"r": null, "g": null, "b": null}
	if effect_data == null or emitter_index < 0:
		return none
	var em = effect_data.get_emitter(emitter_index)
	if em == null or not bool(em.flags.get("color_curve_enabled", false)):
		return none
	var out: Dictionary = {}
	for ch in ["r", "g", "b"]:
		var curve = effect_data.get_curve(int(em.color_curves.get(ch, -1)))
		if curve == null or curve.samples.is_empty():
			return none
		out[ch] = curve
	return out


## The rung, said out loud, as a suffix to the focus block's EXISTING title (dec. 5).
## A title suffix costs 0px in the ~268px inspector row three surfaces already share —
## which is the whole reason the rung is not a row.
static func title_suffix(prov: Dictionary) -> String:
	var ei: int = int(prov.get("emitter_index", -1))
	match str(prov.get("rung", "none")):
		"origin":
			return " · colour from emitter %d (drilled from)" % ei
		"only":
			return " · colour from emitter %d (its only emitter)" % ei
		"first":
			return " · colour from emitter %d (+%d other%s, may differ)" % [ei,
				int(prov.get("others", 0)), "" if int(prov.get("others", 0)) == 1 else "s"]
	return " · no colour-enabled emitter — untinted"
