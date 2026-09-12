@tool
extends Resource

## Outer Resource for the animation resolution map (hand-authored side).
##
## Holds the per-sprite-type entries. Edited in the Godot Inspector;
## the running viewer scene reloads on save via a file-mtime watcher
## (see ResourceHotReload). Replaces `assets/abilities/state_animations.json`
## as the authoring surface for parameterless-activity routing.
##
## Lives at `res://addons/exmateria_sprite_rig/resources/map.tres`.

## The three resource classes lost their global `class_name` in #744 once a boot
## proved `resources/map.tres` still loads without them (the `.tres` addresses each
## script by `ext_resource path=`, and its `script_class=` header is a hint the loader
## does not need). They are aliased back so every use site stays spelled the way it
## was -- ADR-0211 dec. 4, an alias is a per-CLASS declaration, and none of these
## extends another.
const SpriteTypeResource = preload("res://addons/exmateria_sprite_rig/resources/SpriteTypeResource.gd")

@export var sprite_types: Dictionary[String, SpriteTypeResource] = {}


## Lookup by canonical sprite_type name ("type1", "mon", "cyoko", ...).
## Returns null if no entry for that sprite type.
func find_sprite_type(type_name: String) -> SpriteTypeResource:
	return sprite_types.get(type_name.to_lower(), null)
