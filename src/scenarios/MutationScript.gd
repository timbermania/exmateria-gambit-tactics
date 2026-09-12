class_name MutationScript
extends RefCounted

## A beat-keyed **mutation script** (ADR-0201): the authored `create`/`join`/`leave`/
## `die` deltas that [CatalogueReplay] folds into the Catalog as the walk advances.
## Pure data + a lookup — no scene, no engine coupling. [GameNavigator.plan_actions]
## attaches each action's deltas via `for_action`; the [NavigatorRunner] then folds
## the skipped ones on a seek and applies each beat's delta live.
##
## The table is keyed by a stable per-action string (`action_key`). That is what let the
## ROM generator ADR-0201 dec.10 anticipated drop in without touching the engine or seam
## code: [StoryMutationScript] builds this table from ENTD `join_after_event` flags
## (ADR-0216) where a hand-authored one used to. Each value is the `mutations` list
## carried on that action:
##   { "op": "create"|"join"|"leave"|"die", "slug": String, <source> }
## (see [CatalogueReplay] for the delta/source schema).
##
## An empty script (the default) attaches `[]` to every action — the plumbing is inert
## until a real script is supplied. [StoryMutationScript.build] is the one the walk uses.

## key (String) -> mutations (Array of delta dicts).
var _by_key: Dictionary = {}


func _init(table: Dictionary = {}) -> void:
	_by_key = table


## The stable lookup key for one plan action. A scenario/combat action keys by its
## group `root`; an opener/victory beat keys by the beat's `scenario_id` — so the key
## is well-defined even though a `uid` or member id is not globally unique.
static func action_key(action: Dictionary) -> String:
	var kind := String(action.get("kind", ""))
	match kind:
		"scenario", "combat":
			return "%s:%d" % [kind, int(action.get("root", -1))]
		"opener", "victory":
			return "%s:%d" % [kind, int(action.get("beat", {}).get("scenario_id", -1))]
	return ""


## The mutation deltas authored for `action`, or [] if none. Returned by value-copy so
## a consumer can't mutate the authored table in place.
func for_action(action: Dictionary) -> Array:
	return (_by_key.get(action_key(action), []) as Array).duplicate(true)
