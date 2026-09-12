# Effect Studio inspection is a generic target dispatched through a projector registry

## Status

Accepted

Verified 2026-08-28 — decs. 1–11 built. `InspectorProjectorRegistry` registers
**11 kinds, 9 of them built**, against 15 projector scripts in
`src/effects/studio/`; the two remaining declared seams are `curve` and
`callback`. See `audit-notes/0073.md`.

**Amends** [ADR-0071](0071-a-studio-lane-event-projects-through-a-per-archetype-projector-that-separates-owned-from-referenced.md):
that ADR made a **span** dispatch to a per-archetype projector; this one lifts the
inspector's input from "a span" to a generic **inspection target**, so a span is no
longer the only thing the inspector can render. Relates to
[ADR-0069](0069-effect-studio-is-a-standalone-development-window-not-a-debug-panel.md)
(the Studio itself) and [ADR-0004](0004-rosters-share-a-base-script.md)
(path-preload, no `class_name`).

## Context

The Effect Studio's inspector was reachable **only through the timeline**: you click a
[span](../context/16-effect-studio-authoring-tool.md) (a keyframe interval), the span carries an
`emitter_id`, and the inspector renders that emitter. But `EffectData.emitters[]` is a
**spawn graph**, and a keyframe is only ONE kind of edge into it:

| edge | source | has a span? | reachable before |
|------|--------|-------------|------------------|
| keyframe | `TimelineData.Keyframe.emitter_id` | yes | ✅ |
| on-death | `EffectEmitter.child_emitter_on_death` | no | ❌ |
| mid-life | `EffectEmitter.child_emitter_mid_life` | no | ❌ |
| callback | `spawn_child_from_callback()` (runtime index) | no | ❌ |

An emitter reached by a non-keyframe edge — or referenced by nothing — was an **orphan in
the UI**: it appeared only as a dead-end integer in a parent's Config group
(`"Child on death: 5"`), with no way to open emitter 5's params, curves, or its own
children. And the ambition is broader than emitters: the Studio must be able to inspect
**any** object in an `E###.BIN` atomically. The span is just the timeline's *drill-in
handle* to one such object — not a privileged type. ADR-0071 had already framed a
span-click as "a navigation across a reference, not an inspection of the event"; this ADR
promotes that reference from a concept to a first-class, followable **link**.

## Decision

**The inspector renders a generic `InspectionTarget = {kind, ref}`, dispatched by `kind`
through a projector registry.**

1. **Opaque, kind-specific `ref`.** `ref` is a payload only that kind's projector reads
   (span → `{span_id}`, emitter → `{index}`, frame → `{frameset_id, index}`). The
   registry routes on `kind` and NEVER inspects `ref`, so a new kind brings its own
   (possibly composite) identity with zero core change. A `ref` is a **self-contained
   address**: everything needed to resolve the target is in it, never recovered from how
   the author arrived. (`InspectionTarget.gd`.)

2. **`kind → projector` registry.** `InspectorProjectorRegistry` maps a kind to a projector
   owning `header(target, effect_data, score)` and `sections(target, effect_data, score)`.
   A kind may be registered **before** it is built: `has_kind` answers true for a declared
   seam whose projector is still `null`, and `is_built` separates the two, so an un-built
   kind renders empty rather than erroring. Adding one = write a projector + flip a flag;
   the inspector and `EffectStudioPage` do not change. This generalizes ADR-0071's
   per-archetype dispatch one level up: a `span` target's projector (`SpanProjector`) still
   delegates to the ADR-0071 archetype projectors (particle→`EmitterProjector`,
   screen→`ScreenTweenProjector`, …).

3. **`link` is a first-class field / header shape.** A field `{name, shape:"link", label,
   target}` (or a header row `{label, link:{label, target}}`) renders as a button that
   navigates to another target. The Config child-on-death/mid-life rows and the span
   Event's "Emitter" row are links — the fix for the dead-end integer. Where one cell
   addresses several siblings, a `nav_choice` dropdown collapses those links into one
   cell: picking an item moves the nav stack and writes no byte, so it stays clear of the
   edit choke point. Dec. 7 adds a fourth carrier. All of them register on the same
   navigate seam, which is what lets a caller enumerate links without knowing the shapes.

4. **Bare-emitter view.** An emitter target shows ONLY the four characterizing
   `emitter_view` groups plus an emitter header — **no Event section, no Phase/Frames**
   (those are keyframe facts the emitter does not own). A span target is unchanged.

5. **Incoming-edge provenance** (the inverse of a link). An emitter header enumerates every
   edge that reaches it as a clickable reverse-nav row: keyframe refs (→ span), on-death /
   mid-life parents (→ emitter, by inverting `_emitter_children`). This replaces the
   misleading "shared by N events" (which counted only keyframes → a death-child read
   "shared by 0").

6. **Entry points mint targets; navigation is a stack.** The timeline mints a span target
   (a fresh root); an **exhaustive browser** mints a target for *any* object of its kind —
   the reachability guarantee for orphan and callback-only objects, and there is one per
   browsable kind (emitter, container, frameset, sequence). A `link` drills (push) and a
   step back truncates. The timeline highlight is authoritative ONLY for a span target:
   drilling into an emitter leaves the origin span highlighted rather than trying to select
   a non-span on the timeline.

7. **A `link` may ride an EDIT row — the `follow` affordance — instead of replacing it.**
   The reference fields the drill-down chain needs (an emitter's `Animation set`, a FRAME
   opcode's `Frameset`) are **editable** spinboxes that ADR-0089 tier-1 put there on
   purpose, and dec. 3's `shape: "link"` would have traded shipped authoring capability for
   navigation. So an `edit` field may carry `follow: {label, target, tooltip?, disabled?}`:
   the inspector wraps the editor and a flat link button in one HBox, keeping the value cell
   one grid column — the shape `preview_action` already uses for the ▶ Sound button and
   ADR-0075's suppression checkbox uses for a link. The button registers on `_link_buttons`
   and fires the same navigate callback, so **it IS a link**: every seam that enumerates
   links picks it up without knowing this shape exists.

8. **A `ref` may carry a resolution LENS, and the lens is part of identity.**
   A FRAME opcode's `frameset` field is relative to the frameset group; the absolute index
   is `opcode.frameset + frameset_group_offset(anim_param)`, and `anim_param` belongs to the
   **emitter**, not the sequence. The same opcode therefore resolves to a *different*
   frameset depending on who plays it, and an `opcode → frameset` link has no correct target
   on its own. `animation` and `sequence_op` refs carry a `group`, baked in **at
   link-creation time** — in the emitter projector, where the emitter is known — and threaded
   down every hop. The group is part of the target's identity (`equals` compares the whole
   `ref`), so `animation(4, 0)` and `animation(4, 1)` are different targets and the
   back-stack will not dedupe them. That is correct: they show different sprites. `group`
   defaults to 0, the honest answer for a sequence entered from a browser with no emitter
   context.

   The offset itself is **one derivation**, `EffectData.frameset_group_offset(group)`. It
   once had four independent copies that agreed; a documented truth with an unenumerated
   consumer is the shape that produced two bugs on this line. **Add a caller, do not add a
   fifth copy** — `ActiveEmitter._get_group_offset` survives only as a delegating wrapper.

9. **`anim_param` is a lens, not a destination — ONE button for two fields.**
   `anim_index` names a place (`effect_data.animations[i]`); `anim_param` ("Frameset group")
   does not, and there is no group target kind. The two fields jointly parameterize a single
   destination, so the emitter's Config section grows **one** follow button — on the
   `Animation set` row, labelled with the RESOLVED target (`"sequence 4 · group 1"`) — which
   is what makes editing the `Frameset group` row below it visibly re-aim the button.

10. **A dangling reference degrades; it does not navigate.** `anim_index` / `anim_param` /
    `frameset` are u8s with no validity guarantee. A reference that resolves nowhere sets
    `follow.disabled`, the inspector renders **no button**, and the row wears the ADR-0089
    `relevance` `dead` marker naming the offending index. The **editor stays live** so the
    author fixes it in place.

11. **A nav stack may be *seeded* as a chain in one gesture, and a stack so seeded renders
    every entry.** The push/step-back model is right when the author is exploring — each
    step is a decision. It is wrong when the path is already determined and the author wants
    its end: the intermediate surfaces are things they wanted to *see*, not to *visit*. Two
    rules keep the blast radius at zero:
    - **A one-entry stack renders exactly as a one-entry stack always did.** Each entry
      contributes its projector's `sections()` under its own `header()`; no projector
      changes, so there is no regression surface for any existing kind.
    - **Seeding is opt-in per seed, not per kind.** A seed carries the intent; drilling by
      clicking a `link` does not. `span → emitter` still shows only the emitter.

    A seeded chain has **no trail**: its entries are all on the page, so naming them in the
    path bar would be chrome describing itself. A `link` whose target is already on screen
    degrades to a **scroll-to anchor** rather than a push — the stack does not grow by
    navigating to something it already contains.

    Two pieces of stack-aware machinery take rules from this. `_pair_anchor`'s backward walk
    for the FEDS tick-0 anchor becomes correct **by construction** under a seeded chain,
    where before it held only because of how the author happened to arrive. And the editor
    height latch keys on `_nav[0]` — one latch per chain is the intended granularity — but an
    explicit fold toggle inside a chain **must reset it**, because a deliberate collapse is
    not the rebuild transient the latch exists to absorb.

## The callback edge is deliberately not derived

There is **no static `callback → emitter` field** in `EffectData`. `callback_slots` is
`[{slot, callback_id}]`, and `ParticleSubsystem.spawn_child_from_callback(idx, …)` receives
its emitter index from callback logic **at runtime**. So callback incoming edges cannot be
derived from parsed data. An emitter with no keyframe/parent edge shows a flagged,
**non-link** note ("none static — may spawn via callback at runtime") rather than a
fabricated reverse link — honest about what is and isn't statically knowable.

## Considered options

- **Make only the child refs clickable** (drill-down, no generalization) — rejected: it
  reaches child emitters but not callback-only/orphan emitters, and hard-codes a second
  refactor when the next object kind needs inspecting.
- **`target = {kind, id}` with one scalar id** — rejected: breaks the moment a kind needs a
  composite identity (a frame is `frameset + index`), which is exactly the hole the opaque
  `ref` avoids.
- **Synthesize a fake span around a bare emitter** so the span pipeline runs unchanged —
  rejected: invents Phase/Frames/emitter_id the emitter doesn't own.
- **A separate emitter-detail panel** distinct from the keyframe inspector — rejected:
  duplicates the `emitter_view` group rendering and splits one "inspect a thing" surface in
  two.
- **Read the originating emitter back off the nav stack** instead of dec. 8's baked-in lens
  — rejected: it makes a link's destination depend on *how you arrived*, breaking dec. 1's
  promise that a `ref` is a self-contained address. Capture the context where it is known
  rather than recovering it where it is not.
- **A follow button on both the `Animation set` and `Frameset group` rows** — *(drafted and
  caught in review: the two fields sit adjacent and look symmetrical, and only the target
  model says they are not.)*
- **A live link that lands on an empty inspector** for a dangling reference — rejected: it
  fills the nav stack with dead breadcrumbs and reads as broken.
- **Always-on chain rendering** (every drill renders its whole stack) — one rule, no flag,
  but it silently changes emitter drilling too.
- **Hard-code the sound composite in `EffectStudioPage`** — smallest diff, zero risk to
  other kinds, rejected because it puts kind-specific knowledge back in the page, which is
  what the registry exists to prevent. Adding an inspectable kind is a registration, not a
  page edit; rendering one should not be either.

## Consequences

- Every object of a browsable kind is reachable; child refs and the span's emitter row drill
  into the shared emitter; provenance gives reverse navigation. The dead-end
  `"Child on death: 5"` integer is gone, and the chain
  `emitter → sequence → opcode → frameset → frame → texture` is followable without knowing a
  single index.
- Adding a future object kind is a **registration**, not an inspector change.
- Authoring capability is never traded for navigation (dec. 7), and resolving a `follow` is
  O(1) — which matters because the inspector re-projects on every render.
- Nothing on the write path knows about the nav stack: `EffectEditSession._dispatch` matches
  on `field_ref.channel` alone, and every cell carries its own complete address. That is
  what makes "render the whole stack" a rendering change rather than an architectural one.
- The trail is the **path bar**'s (ADR-0102), not the inspector header's — one trail, and a
  seeded chain suppresses it.

## Verification

- Registry and target: `InspectionTargetTest`, `InspectorProjectorRegistryTest`,
  `SpanProjectorTest`, `EmitterProjectorBareTest`, `EmitterProvenanceTest`,
  `InspectorLinkTest`, `EffectStudioNavStackTest`, `EffectStudioEmitterBrowserTest`,
  `EffectSettingsTargetTest`, `SoundContainerProjectorTest`, `SoundTriggerProjectorTest`,
  plus the unchanged `EmitterProjectorTest` / `EffectKeyframeInspectorTest` /
  `EffectScoreModelTest` that prove the span path is behaviour-preserving.
- Decs. 7–10: `EffectStudioDrillDownTest` (the chain, the lens, identity, degradation, and
  the rendered button), `EffectStudioSequenceEditTest`, `EffectStudioSequenceBrowserTest`,
  `EffectStudioSequenceAcceptanceTest`, `EffectEditabilityManifestTest`.
- Dec. 11: `EffectStudioChainInspectionTest`, whose stated contract is dec. 11's first rule
  — "a one-entry stack renders exactly as it does today".
- **How real is the lens ambiguity?** Measured 2026-08-18 across the effect corpus: of
  **2201** distinct (effect, `anim_index`) pairs, exactly **2** are played with more than one
  `anim_param` — **E241 anim 0** and **E408 anim 4** (both params 0,1) — and **383 of 401**
  effects have a single frameset group, where every offset is 0. A genuine edge case, not
  the common shape; but one where the naive link is *silently wrong* — it points at a real
  frameset, the wrong one — which is the failure mode worth paying for.
