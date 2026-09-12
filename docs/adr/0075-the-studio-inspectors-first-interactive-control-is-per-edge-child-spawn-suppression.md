# The Studio inspector's first interactive control is per-edge child-spawn suppression

**Status:** accepted (design; TDD build to follow). Makes the previously **read-only**
[keyframe inspector](../context/16-effect-studio-authoring-tool.md) ([ADR-0073](0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md))
**interactive** for the first time. Relates to
[ADR-0069](0069-effect-studio-is-a-standalone-development-window-not-a-debug-panel.md)
(the Studio is a development window), [ADR-0070](0070-effect-replay-is-deterministic-within-an-instance-via-a-per-instance-seeded-rng.md)
(deterministic per-instance seeded replay — the thing that makes the re-seek below reproducible),
and the thin-glue/model-projects split of
[ADR-0071](0071-a-studio-lane-event-projects-through-a-per-archetype-projector-that-separates-owned-from-referenced.md).

> **ADR numbering:** numbering is contended on this line — two `0073` files already exist and a
> `0074` (fold-material-contract) is pending uncommitted on the compositor branch. `0075` was chosen
> to dodge that; renumber at merge if it still collides.

## Context

Diagnosing "which emitter is problematic" is hard because soloing a particle
[channel](../context/15-effect-orchestration.md) shows **three** emitters at once — the
span-referenced emitter plus its `child_emitter_on_death` and `child_emitter_mid_life`
children — with no way to isolate them from *inside the inspector* where you're already
looking. (The F3 "Effect Viewer" panel's per-emitter checkbox list can hide any emitter by
index, but it is a flat list keyed by raw index with no spatial correspondence to the
inspector's child-link rows.)

Two mechanisms could power an inspector toggle, and they are **not** the same thing:

- **(a) render-filter hide** — the existing `EffectParticleRenderer.disabled_emitters` set:
  skip a particle at draw time by `emitter_index`. Global per-index, holds the simulation
  **identical** (no RNG perturbation), and updates by a cheap in-place re-publish of the
  current particle list — no re-seek.
- **(b) per-edge spawn suppression** — guard the two spawn sites
  (`ParticleSubsystem._process_particle_deaths` / `_process_midlife_children`) so a specific
  **(parent emitter, edge)** never spawns its child. Per-edge (can isolate `P→K` without
  hiding `Q→K`), but it changes the *simulation*, so a frozen frame must be re-derived by
  **re-seek** (`reset()` + re-pump to the current playhead), and skipping the spawn's RNG
  draws **ripples** into every downstream emitter's cloud.

## Decision

**The two child rows in the [emitter view](../context/16-effect-studio-authoring-tool.md)'s Config group
("Child on death" / "Child mid-life") get a checkbox that performs (b) — per-edge child-spawn
suppression — deliberately *not* (a).**

1. **Per-edge, keyed by (parent emitter index, edge kind).** Unchecking suppresses that
   parent's spawn of that child at the spawn site. The child *and its descendants* never
   spawn. This is a **counterfactual** ("what if P never spawned this child?"), not a
   hold-everything-fixed hide — and we **accept the downstream RNG ripple** it causes.

2. **Live update = re-seek, not re-publish.** A simulation change cannot be shown by
   re-filtering an already-simulated frame, so a toggle re-seeks the preview to the current
   playhead. Deterministic via the ADR-0070 per-instance seeded RNG; works paused, scrubbed,
   or playing. "Re-scrub is OK" was the explicit sign-off.

3. **Off-only, on live edges only (D1).** The checkbox appears **only** where the edge
   actually spawns — `child_index ≥ 0` **and** the authored `is_child_death_enabled()` /
   `is_child_midlife_enabled()` flag is on. Default **checked** (spawning); it can only turn
   a live spawn **off**. It never *enables* an authored-off edge (that speculative
   "both-ways enable mirror", **D2**, was rejected for a diagnostic tool — the index could be
   stale). "none" rows and authored-off edges render as before, with no checkbox.

4. **Model projects toggleability; view + a provider/callback carry the state.** Per
   ADR-0071's split, `EffectScoreModel` marks a child row toggleable (extending the existing
   `link` field with an optional toggle payload — **not** a new field shape) only for a live
   edge; the pure model stays stateless. The runtime suppression **set lives sim-side** on
   `ParticleSubsystem`. The inspector renders the checkbox beside the existing link button in
   the same const 2-column cell and is fed a **suppressed-state provider** (query) plus a
   **toggle callback** (mutate), mirroring the existing `curve_provider` / `on_open` /
   `navigate` seams. Flow: inspector → `EffectStudioPage` → host
   `studio_set_child_edge_suppressed(parent, edge, suppressed)` → `EffectInstance` sets the
   flag and re-seeks.

5. **Ephemeral, per-effect.** The suppression set is in-memory, cleared on effect change,
   keyed by emitter (survives span re-selection / drilling / the ADR-0073 nav stack), and
   survives `reset()` (it is config, re-applied on every re-pump).

## Considered options

- **(a) render-filter hide** — rejected as the *primary* mechanism: it can't isolate one edge
  from a shared child, and the workflow asked for a per-edge "these are P's two options"
  toggle. (It remains available and orthogonal via the F3 panel; see below.)
- **(b) with RNG-preserved draws** (draw-and-discard so downstream stays byte-identical) —
  rejected: recursively fiddly (grandchildren too) for a diagnostic tool; the ripple is
  acceptable and is arguably the honest counterfactual.
- **D2 both-ways effective-enable mirror** — rejected for now: enabling an authored-off edge
  is speculative; revisit when authoring lands.

## Consequences

- The Studio inspector is now **interactive** — this is the first write path through it. Edit
  widgets for real param authoring can follow the same provider/callback seam.
- **Orthogonal to `disabled_emitters`.** This does not touch the render filter or the F3
  "Effect Viewer" emitter list (a global render-hide by index — a different mechanism).
  Retiring that panel remains follow-on; the Studio already owns effect selection, transport,
  camera, and per-lane Solo/Mute, leaving only this (now covered) and the React toggle.
- A toggle re-simulates the whole instance up to the current frame — fine for short effects;
  the RNG ripple means it is a counterfactual, not an A/B-clean isolation.
- Guards to add (TDD): the model's live-edge toggleable predicate; the spawn-guard skips a
  suppressed edge; the toggle → host → re-seek path with a fake host; the inspector renders
  the checkbox and emits. Keep `InspectorLinkTest`, `EffectKeyframeInspectorTest`,
  `EffectScoreModelTest`, `EffectStudioNavStackTest`, `EffectStudioEmitterBrowserTest` green.
