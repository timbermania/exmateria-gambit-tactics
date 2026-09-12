extends RefCounted
## The **inspection-target → projector registry** (ADR-0073). Generalizes ADR-0071's
## "a span dispatches to its per-archetype projector" one level up: the inspector renders
## a *target* whose `kind` selects a projector here, and whose opaque `ref` only that
## projector reads. Adding a new inspectable object kind = register a projector below and
## mint its target from wherever — ZERO inspector/model changes.
##
## Most kinds are BUILT; the rest are declared as **seams** so the model
## can honestly answer `has_kind` for them while their projector is still `null`
## (curve/callback — future work, #228-adjacent). A `null`
## projector yields empty header/sections rather than erroring, so an un-built kind is
## inert, not a crash.
##
## No `class_name` (ADR-0004). Projectors are `load()`ed lazily so this file has no
## parse-time dependency on the model graph.

const InspectionTarget = preload("res://src/effects/studio/InspectionTarget.gd")

# The kinds the inspector knows about. A value of true = BUILT (has a projector);
# false = a registered SEAM (recognized, projector not yet written).
const KINDS := {
	"span": true,
	"emitter": true,
	"container": true,
	"pair": true,
	"effect_settings": true,
	"texture": true,
	"frameset": true,
	"frame": true,
	"curve": false,
	"animation": true,
	"callback": false,
}


## The projector script for a kind, or null for an unbuilt seam / unknown kind.
static func projector_for(kind: String):
	match kind:
		"span": return load("res://src/effects/studio/SpanProjector.gd")
		"emitter": return load("res://src/effects/studio/EmitterTargetProjector.gd")
		"container": return load("res://src/effects/studio/SoundContainerProjector.gd")
		"pair": return load("res://src/effects/studio/FedsPairProjector.gd")
		"effect_settings": return load("res://src/effects/studio/EffectSettingsProjector.gd")
		"texture": return load("res://src/effects/studio/TextureProjector.gd")
		"frameset": return load("res://src/effects/studio/FramesetProjector.gd")
		"frame": return load("res://src/effects/studio/FramesetProjector.gd")
		"animation": return load("res://src/effects/studio/SequenceProjector.gd")
	return null


## Is this a kind the inspector recognizes (built OR a declared seam)?
static func has_kind(kind: String) -> bool:
	return KINDS.has(kind)


## Is this kind actually renderable (has a projector), vs a declared-but-unbuilt seam?
static func is_built(kind: String) -> bool:
	return bool(KINDS.get(kind, false))


static func header(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var p = projector_for(InspectionTarget.kind(target))
	return p.header(target, effect_data, score) if p != null else []


static func sections(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var p = projector_for(InspectionTarget.kind(target))
	return p.sections(target, effect_data, score) if p != null else []
