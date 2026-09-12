class_name ScenarioActor
extends RefCounted
## Everything one unit's cutscene *owns* — the home of the per-unit state that
## had none (ADR-0064). A pure data bag: the five formerly-loose VM structures
## (`_unit_tints`, `motions`, `_cinematic_walkers`, `cinematic_unit_atlas_y_offset`,
## `_unit_move_home`) collapse into one value the VM keys by resolved uid.
##
## Holds NO owner node — like [ScenarioMotion] the actor is scene-free so it's
## testable with no VM boot. The VM resolves the live node via `units_by_id` and
## passes it *into* the home-capture methods; the one transitive node ref lives on
## `walker` (CinematicWalkState.unit), intrinsic to how the walker renders.
##
## Two lifecycle concepts the old flat dicts blurred into one `has()` check:
##   * sub-state cleared  — a field is null (Reset Palette drops `tint`); the
##     actor entry survives.
##   * forgotten          — the VM erases the whole entry (`forget`).

## Per-unit {0x32} Color Unit palette tint. Null when the unit has no tint.
var tint: ScenarioColorTint = null

## In-flight scripted motion — a [ScenarioMotion] (Sprite Move {3B}/{6E}, a straight
## lerp) or a [ScenarioPathMotion] (Walk To {28}, the per-tile route/gravity stepper).
## Untyped so both sibling value objects fit the one slot; they share the duck-typed
## `advance`/`position`/`is_done`/`snap_to_end`/`dur_s` surface the VM drives. Null
## when the unit isn't sliding/walking.
var motion = null

## In-flight cinematic-anim walker (ScenarioVM.CinematicWalkState). Untyped so the
## inner class need not be imported here and tests can pass a mock. Null when idle.
var walker = null

## Pending {11}/{8C} Unit Anim latch — the Godot mirror of the PSX writer's
## `unit+0x0C` slot (SCENARIO_WAIT_SEMANTICS.md §6b/§8i). `{11}` dispatch does NOT
## paint the pose; it records the event anim id here (last-write-wins = the PSX
## single-slot latch). `ScenarioVM._consume_pending_body_anims` paints it on the
## NEXT elapsed tick and resets to -1. `-1` = empty (no pose queued). Survives a
## debug park untouched (like `walker`/`motion`) and is cleared only on consume or
## the ADR-0064 single reset path (restart/rewind correctly discards it).
var pending_anim: int = -1

## Signed atlas Y-offset (px) for cinematic frame rendering (PSX unit+0x7a).
var atlas_y: int = 0

## Godot "home" world anchor — the unit's base position, captured at its first
## Sprite Move (the +0x60 offset is 0 then, so position == base). `has_home`
## gates it (Vector3.ZERO is a legal home); `owner_iid` guards node identity.
var home: Vector3 = Vector3.ZERO
var has_home: bool = false

## Instance id of the node `home` was captured from — a guard, NOT a registry
## key. When the live node's iid differs, home is stale (a new node rebound to
## this uid) and re-captured. Folds in the former instance-id keying of
## `_unit_move_home` without a second registry key.
var owner_iid: int = 0


## Capture (or re-capture) the unit's home from `node`, returning it. Sticky for
## the same node — repeated moves slide the +0x60 offset, not the base — but
## re-captures when the node's iid no longer matches `owner_iid` (a different node
## rebound to this uid). Use `clear_home()` to force a re-capture for the SAME
## node (Warp / Walk re-places the base without swapping the node).
func capture_home(node) -> Vector3:
	var iid: int = node.get_instance_id()
	if not has_home or owner_iid != iid:
		home = node.global_position
		owner_iid = iid
		has_home = true
	return home


## The captured home if this actor owns `node`'s current home, else the node's
## live position. Mirrors the former `_unit_move_home.get(iid, unit.global_position)`
## with the owner_iid guard folded in.
func home_or_current(node) -> Vector3:
	if has_home and owner_iid == node.get_instance_id():
		return home
	return node.global_position


## Drop the captured home so the next `capture_home` re-captures from the live
## node. For same-node base re-placement (Warp Unit, Walk To arrival) that the
## iid guard can't detect.
func clear_home() -> void:
	has_home = false
