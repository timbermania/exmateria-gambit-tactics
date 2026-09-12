@tool
extends Resource

## Per-sprite-type entry in the animation resolution map.
##
## The sprite_type identity ("type1", "mon", "cyoko", ...) is held by the
## Dictionary key in AnimationResolutionMapResource.sprite_types — not
## stored here, so there's exactly one source of truth.
##
## `seq_file` is the ROM-derived SEQ filename that goes with this sprite
## type — labeled here for cross-reference; not actively used at resolve
## time (Unit's animation_set already knows which SEQ to load).

## The three resource classes lost their global `class_name` in #744 once a boot
## proved `resources/map.tres` still loads without them (the `.tres` addresses each
## script by `ext_resource path=`, and its `script_class=` header is a hint the loader
## does not need). They are aliased back so every use site stays spelled the way it
## was -- ADR-0211 dec. 4, an alias is a per-CLASS declaration, and none of these
## extends another.
const ActivityRowResource = preload("res://addons/exmateria_sprite_rig/resources/ActivityRowResource.gd")

@export var seq_file: String = ""
@export var states: Dictionary[String, ActivityRowResource] = {}


## Lookup by activity name (the Dictionary key — IDLE / WALKING / DYING / …).
func find_row(activity_name: String) -> ActivityRowResource:
	return states.get(activity_name, null)
