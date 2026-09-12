# Logical activity routes through Display activity, never directly to a SEQ

Every [Logical activity](../context/18-sprite-layers.md)
(the GPU's `LOGICAL_ACTIVITY_*`, source: `tools/activity_taxonomy.yaml`)
routes to a [Display activity](../context/18-sprite-layers.md)
(`DisplayActivity.Activity`) through `ActivityTranslator.translate(...)`,
and the BODY layer's render-variant fields (`current_animation_front` /
`current_animation_back`) are set **only** through the Display activity →
[resolver](../context/18-sprite-layers.md) →
`_start_state_animation` path. A raw `type1_playback.start()` on the BODY
layer (anywhere but inside `_start_state_animation`) is forbidden — it
advances the animation clock without updating what the painter reads, so the
unit renders its *old* animation indexed by the *new* clock.

> The original ADR called the GPU side "combat states" (`STATE_*`) and the
> CPU side "unit activities" (`UnitActivity`). The PR2 vocab collapse
> (issue #44) unified these as the **Logical/Display** projections of one
> activity concept; the asymmetry the ADR preserves is real — granularity
> differs by layer — but the *state-vs-activity name* was historical drift.

## Status

accepted

## Context

`_paint_body_variant` (`Unit.gd`) paints the SEQ named by
`current_animation_front`, indexed by `type1_playback.anim_frame`.
`current_animation_front` is set in exactly one place: `_start_state_animation`.
A raw `type1_playback.start("58", …)` resets the clock and `anim_id` but leaves
`current_animation_front` stale, so the painter indexes the *prior* animation's
SEQ with the new SEQ's frame counter.

`LOGICAL_ACTIVITY_CELEBRATING` (pre-PR2: `STATE_VICTORIOUS`) was the sole
violator: it poked `type1_playback.start("58")` directly (`CombatLoop.gd`).
The visible result — winners "moving up and down" while replaying their
pre-victory animation — was a recurring regression because nothing pinned
the rule and successive clock/loop refactors (ADR-0018, ADR-0020, ADR-0025)
kept re-breaking the unguarded one-shot. An audit at decision time
confirmed `CombatLoop`'s victory case was the only raw BODY-layer `start()`
in the codebase; removing it makes this invariant true and enforceable
rather than aspirational.

## Decision

The five rules below were decided by this ADR but were only ever stated as a
flat bullet list. They are numbered here on 2026-08-28 so `ADR-0026 dec. N` is a
checkable citation; the anchor scanner read **zero** anchors of any kind on this
file before the numbering, so no existing citation could break. No word is
removed and no rule is retired by the numbering. Amendment 1 grades each of the
five against the shipped code — the invariant holds, but **two of the nouns it
is written in no longer exist, and dec. 1 is now conditional on a flag that
defaults the other way.**

1. `LOGICAL_ACTIVITY_CELEBRATING` maps to the parameterless Display activity
   `CELEBRATING`, resolved through `AnimationResolutionMap.resolve_for_activity`
   like `IDLE` — including a per-sprite-type `"CELEBRATING"` row in `map.tres`.
   The hardcoded `"58"` slot retires; un-authored sprite types resolve to an
   explicit MISS (surfaced by the
   [Unit Animation Viewer](../context/18-sprite-layers.md)), never a
   TYPE1-as-base fallback (ADR-0021).
2. **FFT battle sprites have no dedicated victory SEQ.** The ROM slot labels
   (`tools/data/animation_names.txt`) confirm there is no "Victory" / "Win" /
   "Cheer" slot in any sprite type — and the retired `"58"` was a mislabel: slot
   58 is `Jump Down Front`, a movement frame (which is *why* the broken victory
   read as "bobbing up and down"). `CELEBRATING` therefore **reuses the Dancing
   pose** — TYPE1 front/back `82`/`83` — as the celebration. The pose is a
   per-sprite-type data choice in `map.tres`, not a fact baked into code.
3. The mapping is applied **per-unit** on the `CELEBRATING` transition via the
   normal Logical→Display dispatch through `ActivityTranslator.translate(...)`.
   The post-victory branch in the
   [combat loop](../context/02-combat-buffer-layout.md) stays a **pure clock pump** (it
   sets nothing; it advances the clock that loops the already-set activity —
   ADR-0020).
4. Victory is **terminal and overrides**: the `→ CELEBRATING` transition is not
   gated by the in-flight cast/attack latch (`_spell_cast_active`). It interrupts
   any lingering cast/attack animation like a normal state change, and rides the
   normal interrupt's VFX/layer cleanup. The override guard lives at the
   `CombatLoop._update_unit_animation` call site (before the
   `ActivityTranslator.translate(...)` call) because `_spell_cast_active` is
   CombatLoop-internal state the translator does not need to know about.
5. The shared `GPUCombatTestBase.on_victory` asserts the invariant for every
   surviving winner: `activity == CELEBRATING`, `current_animation_front ==`
   the resolved celebrate slot, and `last_resolution.source == "atlas"`. The
   binding assertion is the **render field** (`current_animation_front`), not
   `type1_playback.anim_id` — the latter was correct *while the bug was present*,
   so asserting on it is a false green.

## Considered options

- **Raw `type1_playback.start("58")` (the status quo, rejected).** Severs the
  `current_animation_front` link, hardcodes a TYPE1 slot for all sprite types
  (ADR-0021 violation), and is the recurrence itself.
- **Minimal patch: call `_start_state_animation("58", "59")` (rejected).** Fixes
  the render link in one line but keeps the hardcoded slot and the
  non-activity special case, so non-humanoid sprite types still paint the wrong
  pose and the next refactor finds a special case to break.

## References

- ADR-0021 — per-state resolution shape; no TYPE1-as-base fallback
- ADR-0024 — Unit owns the resolution-map call (this ADR extends it to terminal
  states and to the render-variant fields)
- ADR-0020 — one clock per unit; the pump owns time, runners are driven
- `tools/activity_taxonomy.yaml` — **authoritative** Logical↔Display mapping.
  The generator emits the dispatch shell, the constants, and the Markdown
  table embedded in CONTEXT.md.
- CONTEXT.md — [Unit activity (Logical + Display)](../context/18-sprite-layers.md) (the unified vocabulary the original
  Celebrating/Victorious split was retired into).

## Amendment 1 — the invariant survived the refactor that deleted both of its nouns, and the celebration is now off by default

Measured 2026-08-28 against the tree. The rule this ADR exists to protect — a
Logical activity never reaches a SEQ except through the Display activity and the
resolver — is **true and structurally enforced**, more strongly than when it was
written. What has moved is everything the rule was *phrased in*: the one legal
setter was deleted, the render field it binds on became a mirror, and the
mapping in dec. 1 became conditional on a runtime flag whose default is the
opposite of what this ADR describes.

### What is current, per decision

| Decision | Status | Where the live answer is |
| --- | --- | --- |
| dec. 1 | **holds, now conditional** | `ActivityTranslator.gd:53-54` still maps Logical→Display directly, but `CombatLoop._update_unit_animation:1232` intercepts first and calls `settled_victory_activity(celebrate_on_victory, is_dead)` (`:1207`) |
| dec. 2 | **holds exactly** | `AnimationResolutionMap.resolve_celebrating:170-174`; `map.tres` `Resource_celt1` / `Resource_celt3` both `front = 82`, `back = 83` |
| dec. 3 | **holds** | dispatch is `ActivityTranslator.translate(...)` at `CombatLoop.gd:1258`; the victory branch sets an activity and returns — no clock poking |
| dec. 4 | **holds exactly as written** | the override is at the `_update_unit_animation` call site, before the dead and `_spell_cast_active` guards, and clears the latch (`:1233`) |
| dec. 5 | **holds, but can no longer make the distinction it argues for** | `GPUCombatTestBase._assert_celebrating_invariant:154-191`, opted in at `:116` |

### `_start_state_animation` is gone, and the invariant got stronger for it

This ADR's headline rule and its whole Context are written in terms of
`_start_state_animation` as the single legal setter of the render-variant
fields. **That function does not exist** — there is no `func
_start_state_animation` anywhere in the tree; it survives only in comments
recording its retirement (`Unit.gd:861`, `UnitDisplay.gd:279`). The ADR-0053
Path-D refactor replaced it with a single funnel, `UnitDisplay.play_body`
(`:200`), and the only `type1_playback.start()` on the BODY layer in the tree is
now inside `UnitDisplay.apply_resolution` (`:293`), keyed off `current_anim_id`.

This is a **strengthening, not a drift**. The forbidden move — a raw
`type1_playback.start()` that advances the clock without updating what the
painter reads — is no longer merely absent from the codebase; it is
inexpressible, because the clock key is *derived* from the same
`current_anim_id` write that updates the render field, inside one function.

### Which is why dec. 5's argument no longer applies to dec. 5's assertion

Decision 5 binds the invariant on `current_animation_front` rather than
`type1_playback.anim_id`, on the stated ground that "the latter was correct
*while the bug was present*, so asserting on it is a false green." Post-Path-D,
`current_animation_front` is written in exactly one place — `play_body:215`,
`_unit.current_animation_front = str(anim_id)` — three lines after
`current_anim_id = anim_id` and immediately before `_arm_anim_id_clock()`. The
field is now a **back-compat mirror** of the value the clock is armed from, and
`UnitDisplay.gd:210` says so in as many words ("Back-compat: existing tests +
viewer readouts read `current_animation_front`").

So the two assertions can no longer disagree: the desync dec. 5 was written to
catch is not a state the code can reach. The assertion is **not useless** — it
still compares the running slot against `last_resolution.body_slot`, so it
catches a *dispatch* error (the resolver produced one slot, the funnel was
called with another). What it lost is precisely the discriminating power the
decision's rationale claims for it. A reader who follows that rationale to pick
the assertion field today is reasoning from a defect that was designed out.

### Decision 1 is conditional, and the default is the other branch

`CombatLoop.celebrate_on_victory` defaults to **`false`** (`:106`). On the
default path a surviving winner does *not* become `CELEBRATING`: it returns to
`IDLE` (the resolver then picking the `IDLE_LOW_HEALTH` kneel for a critical
unit), and a KO'd winner returns `LEAVE_ACTIVITY` so it stays lying as its
corpse. The GPU win handshake is untouched either way — `stage_victory` still
keys on `LOGICAL_ACTIVITY_CELEBRATING`; only the on-screen pose forks.

The dance this ADR decided is now the **opt-in arena behaviour**. Two hosts opt
in: `GPUCombatTestBase:116` ("the combat suite guards the victory dance, so it
opts into celebrate mode") and the navigator's debug panel
(`NavigatorMain.gd:1287`, `ScenarioDebugSession.gd:52`). Production defaults to
the faithful pose. The anti-recurrence net of dec. 5 is therefore **not
vacuous** — the suite that runs it forces the branch it guards — but it guards a
non-default behaviour, and the opposite arm has its own guard
(`CombatFaithfulPoseTest.gd`, which fails if a winner is still `CELEBRATING`
with the dance disabled). `CombatVictoryPoseTest.gd:62-77` pins
`settled_victory_activity` as a pure function on both flags.

### Two of ten sprite-type rows author CELEBRATING, and that is the decision working

`map.tres` has ten `"IDLE"` rows and two `"CELEBRATING"` rows. That is dec. 1's
"un-authored sprite types resolve to an explicit MISS" holding, not a gap:
`resolve_celebrating`'s comment names it ("Non-humanoid types are intentionally
unauthored → explicit MISS (ADR-0021), never a TYPE1-as-base fallback"), and
dec. 5's net only requires the atlas binding for `TYPE1` / `TYPE3` while still
requiring `activity == CELEBRATING` for every sprite type.

### Closing an open question from ADR-0024's audit

ADR-0024's audit left open whether this ADR ratifies the exception to
**ADR-0001 dec. 2** (which rejected "a hand-authored schema file that emits both
sides"). It does not ratify it — it *causes* it, and ADR-0001 records it. This
ADR's References make `tools/activity_taxonomy.yaml` the authoritative
Logical↔Display mapping; `tools/gen_activity_taxonomy.py` emits from that YAML
both the GDScript block (`GPUConstants.gd:60-77`, marked "Source of truth:
tools/activity_taxonomy.yaml … DO NOT edit") **and** a GLSL block
(`gen_activity_taxonomy.py:233`). That is the rejected shape exactly, and
ADR-0001 dec. 2 already carries the pointer — "See Amendment 1: one constant
family now works the rejected way." The family is this one. Nothing to change
on either file; the question is answered.
