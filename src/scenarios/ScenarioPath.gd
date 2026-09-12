class_name ScenarioPath
extends RefCounted

## The pure [Path] planner — computes the ordered route of [scenario group] members
## to walk to reach a target scenario without a live battle. No scene / VM / GPU
## dependency; fully headless-testable. A scene-side applier executes the plan
## (boot the group root once, then swap each member's chunk onto the same live
## world), and the two F3 front-ends drive this one planner.
##
## The route is **director-chosen, not statically fused** (ADR-0054): each step
## forces the minimal [ForcedDirectorState] that makes the [ScenarioDirector]
## advance to the next member, and the planner then evaluates the director *for
## real* to confirm that state isolates the intended member. If an earlier edge
## preempts (first-match-wins returns a different member), the step is reported
## unverified with `preempted_by` set — the plan never lies about reaching a member
## it cannot isolate.
##
## Member ordering comes from the director's own edge targets (ascending): the
## natural forward progression from the group root through its members. A path stays
## WITHIN one group — inter-group `exit` routing is a separate, later concern.
##
## Scope: the ascending walk models a LINEAR group faithfully (Orbonne 4→5→6). For a
## BRANCHING group (Mandalia's mutually-exclusive menu timelines / multiple endings)
## it walks every earlier-numbered edge target too, so a sibling branch can appear on
## the route; the per-step isolation check still reports honestly whether each member
## is reachable. Precise branch-aware routing is a later concern — see ADR-0054.

## One planned step. `member_scenario_id` is the member to play; `forced_state` is
## the ForcedDirectorState to apply before swapping its chunk in. `verified` is true
## iff the director, given only this forced state, returns this member. `actual` is
## what the director actually returned; `preempted_by` is that member when it differs
## from the intended one, else [constant ScenarioDirector.NONE].
##   { "member_scenario_id": int, "forced_state": ForcedDirectorState,
##     "requirements": Array, "verified": bool, "actual": int, "preempted_by": int }


## Plan the route from `bc_id`'s group root to `target_scenario_id`. Returns the
## ordered steps (empty if the target is the setup root or not a member of the set).
func plan(bc_id: int, target_scenario_id: int) -> Array:
	var steps: Array = []
	var director := ScenarioDirector.new()  # stateless — used only for edges()
	var edges := director.edges(bc_id)
	if edges.is_empty():
		return steps

	# Requirements by member target, walked in ascending (forward-progression) order.
	var reqs_by_target: Dictionary = {}
	var ordered: Array = []
	for e in edges:
		var t := int(e["target"])
		if not reqs_by_target.has(t):
			reqs_by_target[t] = e["requirements"]
			ordered.append(t)
	ordered.sort()

	for t in ordered:
		if t > target_scenario_id:
			break
		var reqs: Array = reqs_by_target[t]
		var forced := ForcedDirectorState.synthesize(reqs)
		var report := ScenarioPath.isolates(bc_id, forced, t)
		steps.append({
			"member_scenario_id": t,
			"forced_state": forced,
			"requirements": reqs,
			"verified": bool(report["isolated"]),
			"actual": int(report["actual"]),
			"preempted_by": int(report["preempted_by"]),
		})
	return steps


## True iff every step of a plan verified (no preemption) — the applier should
## refuse to walk a plan that cannot isolate one of its members.
static func plan_is_walkable(steps: Array) -> bool:
	for s in steps:
		if not bool(s.get("verified", false)):
			return false
	return not steps.is_empty()


## Evaluate the director against `forced` and report whether it isolates
## `intended_member`. Shape: { "isolated": bool, "actual": int, "preempted_by": int }
## (`preempted_by` is the member first-match-wins actually returned when it differs,
## else [constant ScenarioDirector.NONE]). This is where the first-match-wins
## preemption check lives.
static func isolates(bc_id: int, forced: ScenarioDirectorState, intended_member: int) -> Dictionary:
	var actual := ScenarioDirector.new(forced).next_scenario(bc_id)
	var ok := actual == intended_member
	return {
		"isolated": ok,
		"actual": actual,
		"preempted_by": ScenarioDirector.NONE if ok else actual,
	}
