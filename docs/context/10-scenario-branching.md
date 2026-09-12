# Scenario branching

How the story advances from one [scenario](08-scenario.md) to the next: the FFT
`BattleConditionals` decision layer, the groups it partitions scenarios into, and
the debug-only navigation that walks a chosen route to any scenario without a live
battle. Distinct from the [event-script interpreter](09-event-script-interpreter.md),
which plays *one* scenario's bytecode; this cluster decides *which* scenario plays.

**Scenario director**:
The runtime interpreter for one `BattleConditionals` set — given a
`battle_conditionals_id` and a pluggable [Director state](10-scenario-branching.md) to
read combat/party state from, it evaluates the set's conditions top-to-bottom and
returns the `Run Scenario N` of the **first** condition whose requirements all
hold (the PSX engine writes N to RAM `0x8016A014`). Stateless and read-only —
every `BattleConditional` opcode *except* `Run Scenario` is a requirement check
(`Variable ==` is an equality *test*, not an assignment; `Victory` is a *check*),
so the director never writes game state. First-satisfied-wins is faithful because
the ROM's guards are authored mutually-exclusive. `class_name ScenarioDirector`
(`src/scenarios/`), pure data + evaluator, no scene/VM/GPU dependency; served
records come from `BattleConditionalDatabase`.
_Avoid_: the `Director` bare name or the [ScenarioCameraDirector](09-event-script-interpreter.md)
sense (that is a stateful camera task; this is the branch evaluator); calling the
set a "script" (it is a decision table, not event-script bytecode); modeling
`Variable ==` as an assignment (it is a guard the [Director state](10-scenario-branching.md)
answers, never a write).

**Director state**:
The pluggable read interface the [Scenario director](10-scenario-branching.md) queries —
variable values, unit HP/MP/presence/turn by ENTD id, victory, gil, casualties,
date, location. The base class (`class_name ScenarioDirectorState`) returns an
"empty world" (nothing present, everything zero) so an unwired director never
advances; concrete sources override the parts they can answer. Three intended
subclasses: a live-combat source backed by the GPU engine (the eventual real
wiring), a hand-set stub for tests, and a **forced source** the debug navigation
synthesizes to make a chosen guard true.
_Avoid_: writing game state through it (it is read-only — the director's
faithfulness rests on this); reading these fields from a CPU mirror of battle
state instead of the [Battle-state authority](02-combat-buffer-layout.md) snapshot when
the live source is wired.

**Scenario group**:
A maximal contiguous run of [scenarios](08-scenario.md) sharing one `(map_id,
entd_idx)` — one **root/setup** scenario that loads the world (map + ENTD + music)
plus the **member** scenarios that are event-script *deltas* assuming that world is
already live. The root carries the group's `battle_conditionals_id`; the
[Scenario director](10-scenario-branching.md) evaluated against that set is what selects
which member fires next, and a **[successor](11-campaign-spine.md)** field
(`next-scenario` → the next group's root, or `world-map`) hands off when the group
resolves. Derived by
`tools/export_scenario_groups.py` into `assets/scenarios/scenario_groups.json`
(155 groups). A member scenario's *record* still names the same map/ENTD/music as
its root (so it is cold-bootable), but its *bytecode* carries no load opcode — the
world is the root's doing.
_Avoid_: "scene group" (collides with a Godot `.tscn` **scene** — this is a run of
`Scenario` records); "battle group" (the JSON comment's older name — align to
`scenario group` for the `Scenario*` cluster); treating a member as
self-contained (it is a delta on the root's world — booting it faithfully needs
the root's world, see [Path](10-scenario-branching.md)); conflating the group's
`battle_conditionals_id` with a member's (only the root carries it).

**Path**:
An ordered route of [scenario group](10-scenario-branching.md) members walked to reach a
target scenario without a live battle — the debug-only "get me to scenario 5"
mechanism. The world is booted **once** from the group root; each step forces the
minimal [Director state](10-scenario-branching.md) that makes the director advance to
the next member, then swaps that member's event script onto the *same* live world
(`load_chunk_json` + `start`, units and their positions persisting) — i.e.
concatenating the chosen members' opcode streams on one persistent world. The
route is **director-chosen, not statically fused**: members form a branch graph
(mutually-exclusive menu-choice timelines, multiple endings), so *which* members
concatenate is a per-branch decision, and byte-fusing chunks would also break
intra-chunk jumps and lose per-scenario resets (see ADR-0054). A pure planner
computes the path (headless-testable); a scene-side applier executes it; two F3
front-ends drive it — a **group flowchart** (pick a group, click a member) and a
flat **scenario picker** (pick a scenario, auto-resolve its path).
_Avoid_: "progression" (reserved for `UnitProgression` / leveling — this is
*scenario* routing); fusing member chunk bytes into one program (breaks
PC-indexed jumps + per-scenario `start()` resets — ADR-0054); walking real combat
to reach a mid-battle member (the explorer forces the state the guard reads;
faithful combat auto-firing is a deferred RE task); routing across group `exit`
edges (a path stays *within* the target's own group — the inter-group map is a
later, separate concern).
