extends Node

## One-int hand-off across a `reload_current_scene` triggered by click-to-
## rewind in `ScenarioVMDebugPanel`. The autoload survives the reload; the
## scene reads `rewind_target_pc` on boot, fast-forwards to it, and clears
## it back to -1. Panel UI state does NOT need to live here — the panel
## itself is owned by `DebugOverlay` and survives the reload via `rebind`.

## Sentinel for "no pending rewind". Set by the panel before
## `reload_current_scene`; consumed (and cleared) by `ScenarioPlayerScene
## ._ready`.
var rewind_target_pc: int = -1

## Which scenario the ScenarioPlayer should boot into, keyed by the canonical
## scenario id (== TEST.EVT event index == ScenarioDatabase key). Set by the
## "Scenario" picker in `ScenarioVMDebugPanel` right before
## `reload_current_scene`, and read by `ScenarioPlayerScene._ready`. Survives
## the reload because this autoload outlives the scene. `-1` = "use the scene's
## DEFAULT_SCENARIO_ID" (fresh boot, no pick made yet).
var selected_scenario_id: int = -1

## Which scenario is ACTUALLY playing right now — the target member in a [Path]
## walk, else the resolved single-scenario id. Set by `ScenarioPlayerScene._ready`
## on every boot; read by `ScenarioVMDebugPanel._request_rewind` to decide whether
## a rewind of a nested group member should replay from the group ROOT through the
## intermediate members (building the world up as it would be reaching that member
## live) instead of a plain single-chunk rewind. `-1` = not yet booted.
var active_scenario_id: int = -1

## Which scenario the [Path] navigation should WALK to, keyed by canonical scenario
## id. Set by the ScenarioPathDebugPanel front-ends (flat picker / group flowchart)
## right before `reload_current_scene`; read by `ScenarioPlayerScene._ready`, which
## resolves the target's group root, boots that world once, plans the path with
## [ScenarioPath], then swaps each member's chunk onto the same live world. Consumed
## (set back to -1) on boot so a later Ctrl+R doesn't re-walk. `-1` = "no pending
## path walk" — boot the single selected/default scenario instead.
var path_target_scenario_id: int = -1

## --- Game-state NAVIGATOR seek (NavigatorMain) ------------------------------
## Which group root the navigator walk should START at, and which action within
## that plan to BEGIN at ("seek here"). Set by [NavigatorDebugPanel] right before
## `reload_current_scene`; read + consumed by `NavigatorMain._ready`. `-1` = use the
## scene's defaults (start root 1 → stop root 7, from the top). Survives the reload
## because this autoload outlives the scene. `navigator_stop_root` bounds the walk
## (`<=0` = walk the ATTACK chain to its natural end).
var navigator_start_root: int = -1
var navigator_stop_root: int = -1
var navigator_start_action: int = -1

## --- Where a LIVE navigator walk currently IS -------------------------------
## Published by `NavigatorMain` as the walk boots and as each rewindable action is
## dispatched; cleared by `ScenarioPlayerScene._ready` because a plain scenario-player
## boot means no walk is on screen. Unlike the `navigator_start_*` seek above these are
## NOT consumed on boot — they describe the present, not a pending request.
##
## `navigator_resume_root > 0` is therefore also the "a navigator walk is what you are
## looking at" flag, and that is what routes a click-to-rewind back INTO the walk. Without
## it the rewind front-end read `active_scenario_id` (which the navigator branch never
## wrote), took its single-chunk fallback, and the reload booted the story start instead —
## the reported "seek root 28, rewind, land in the Chapel of Orbonne" defect.
var navigator_resume_root: int = -1
var navigator_resume_stop_root: int = -1
var navigator_resume_action: int = -1

## Post-battle pose for the navigator's CombatLoop: `false` (default) = the
## faithful HP-appropriate return-to-normal; `true` = the made-up victory dance
## (ADR-0026). Set by [NavigatorDebugPanel]; read by `NavigatorMain` when it
## builds the battle's CombatLoop (`CombatLoop.celebrate_on_victory`). Persists
## across `reload_current_scene` because this autoload outlives the scene, so it
## is NOT consumed/reset on boot (unlike the seek fields above).
var navigator_celebrate_on_victory: bool = false
