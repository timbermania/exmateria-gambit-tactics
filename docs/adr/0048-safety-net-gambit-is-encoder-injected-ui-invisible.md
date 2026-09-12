# Safety-net gambit is encoder-injected and UI-invisible

## Status

accepted

## Context

The gambit pass walks slots in order, falls through on no-match
(rules A1 / B1 / B2 / B6 in
[`gambit-rules.md`](../../docs/gambit-rules.md)), and
*leaves the unit IDLE* if every slot misses. "Every slot misses" is a real
state — a Monk whose only gambit is Secret Fist will sit there when the
target is out of cast position; a unit whose conditions all fall false will
do nothing.

This is correct in the abstract (no gambit matched → no commitment), but in
practice it's a silent-failure shape — the user sees a unit standing still
and cannot tell whether that's intentional (no condition fired) or a bug
(some rule didn't match a target it should have). Worse, an authoring
mistake — forgetting to include an unconditional fallback — produces this
same shape.

Two related decisions: how to guarantee the pass always has at least one
terminal candidate, and whether to surface when the unit reaches it.

## Decision

The six rules below were decided by this ADR but were only ever stated as
prose bullets. They are numbered here on 2026-08-28 so `ADR-0048 dec. N` is a
checkable citation; the anchor scanner read **zero** decision anchors on this
file before the numbering, so no existing citation could break. Nothing is
added and nothing is retired by the numbering — Amendment 1 records what the
code says about each one.

1. **The system auto-appends one safety-net gambit per unit at battle setup**
   — `ATTACK + NEAREST_ENEMY + ALWAYS` (action `ActionKind.ATTACK`, condition
   target `TargetSelector.nearest_enemy()`, conditions
   `[GambitCondition.always()]`, action target `TargetSelector.triggering()`).
   Same shape for every unit, regardless of job, brave/faith, or authored
   gambit list.

2. **It is invisible in the UI editor.** The authored 5-slot contract is
   unchanged; the UI gambit editor renders 5 slots. The safety-net slot
   exists *only* in the encoded GPU buffer.

3. **Injection happens at the [GambitEncoder](../context/02-combat-buffer-layout.md)
   boundary, not on the domain.** `Gambit`, `GambitList`, persistence
   (`UnitRosterData`), and the UI editor stay unaware. The safety net is a
   pure buffer-layout concern; the domain stays the authorial vocabulary.

4. **Buffer grows by one slot: `MAX_GAMBITS` 5 → 6.** Per-unit gambit storage
   grows from 80 ints to 96; the shader iterates to the new count; the
   authored cap stays 5. Standard combat-buffer-layout change (bump
   `SHADER_VERSION` and `EXPECTED_SHADER_VERSION` per
   [ADR-0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md)).

5. **No runtime observability hook is added.** "This unit always hits the
   safety net" is a regression that belongs to the
   [Gambit scenario suite](../context/02-combat-buffer-layout.md) — a
   liveness predicate such as `no_safety_net_hit(unit, window=N)` over the
   scenario's commit trace. A runtime signal would mostly be noise (the
   safety net firing for one tick after a transient is normal); the scenario
   suite is the right altitude for this concern.

6. **The safety net composes with existing fall-through.** Rule A1 puts it
   last in eval order; rules B1 / B2 / B6 still fire — if no enemies remain
   (`NEAREST_ENEMY` resolves to no candidate), the safety net itself falls
   through past slot 5 and the unit IDLEs, which is the desired post-victory
   terminal state. The safety net does not change "fall off the end →
   IDLE"; it just makes "fall off the end" require all 6 slots to fail
   instead of all 5.

See the `Safety-net gambit` glossary entry in
[CONTEXT.md](../context/02-combat-buffer-layout.md).

## Considered options

- **Author-required safety net.** Every unit's authored gambit list must
  include an unconditional `ATTACK NEAREST_ENEMY` fallback as its last slot;
  tests assert it. Rejected: punishes authors for an invariant the system
  can guarantee itself, and a missing fallback in a scenario file produces
  the same silent-failure shape this decision exists to retire.

- **Reserve slot 4 instead of bumping `MAX_GAMBITS`.** Authored slots drop
  from 5 to 4 to fit the safety net within the existing buffer. Rejected: a
  visible reduction in authorial space for a system concern.

- **Per-unit or per-job safety-net customization.** A Chemist whose intent
  is heal-allies probably *wants* the fallback to be WAIT, not ATTACK
  NEAREST_ENEMY. Rejected for the first pass: the simplification — every
  unit gets the same shape — is worth more than the per-job correctness
  today; the customization can land later as a per-unit `default_safety_net`
  flag without disturbing the architecture.

- **Emit a `safety_net_fired` runtime signal.** A `GPUCombatInterpreter`
  event matched in `CombatLoop`, routed to a debug overlay / regression
  log. Rejected: the scenario suite catches the bug shape this would
  detect, and a per-commit signal is noisy in the case where a unit
  legitimately falls through to the safety net for one tick after a
  transient.

- **Inject on the domain side (in `GambitList.normalize()` or a
  `_with_safety_net()` accessor).** Rejected: leaks the buffer-layout
  concern into the authoring vocabulary; UI editor, persistence
  (`UnitRosterData.to_dict`), and any future domain consumer would have to
  filter the safety net out.

## Consequences

- **`MAX_GAMBITS` 5 → 6 in `GPUConstants.gd` + `combat_common.glslinc`.**
  Buffer grows by 16 ints/unit (~64 bytes/unit); shader version bumped per
  [ADR-0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md).
  Existing scenarios continue to work — they author ≤ 5 slots.

- **`GambitEncoder.pack` gains a fixed-shape safety-net write at slot 5.**
  The encoder remains pure (no `RenderingDevice`); the safety net is just
  one more `_pack_one_gambit` call with a fixed config.

- **Constant naming.** The literal `5` for "user-authored slots" needs a
  distinct constant from `MAX_GAMBITS = 6`. Suggested split:
  `MAX_USER_GAMBITS = 5`, `MAX_TOTAL_GAMBITS = 6`. Pick at implementation
  time. *Implemented as:* `MAX_GAMBITS` stays the buffer total (the shader-
  generated stride, now 6) and a hand-authored `MAX_USER_GAMBITS =
  MAX_GAMBITS - 1` in `GPUConstants.gd` names the authored cap — derived from
  `MAX_GAMBITS` so the one-safety-net invariant survives a future buffer bump.
  `MAX_USER_GAMBITS` is authoring policy, not buffer layout, so it stays
  hand-authored outside the generated region.

- **No `gambit-rules.md` change required.** The safety net is a
  buffer-injection concern, not a rule the GPU evaluator follows; the
  existing rules A1 / B1 / B2 / B6 already describe how the slot is
  evaluated.

- **Scenario suite gains an `no_safety_net_hit`-shape liveness predicate**
  (follow-up). Scenarios that intentionally route to the safety net (e.g.,
  "Chemist with no heal targets in range") opt in via `xfail`-style.

## Amendment 1 — the "5 authored slots" contract was never true on the roster path, and one line in a sibling file is what keeps the safety net reachable

Graded against the tree on 2026-08-28. Five of the six decisions hold as
written and the sixth (decision 2) rests on a slot count the domain has never
used. Two findings are load-bearing.

### Per decision

| dec | held? | measured |
|---|---|---|
| 1 auto-append `ATTACK + NEAREST_ENEMY + ALWAYS` | **holds** | `GambitEncoder._safety_net_gambit()` (`src/gpu/GambitEncoder.gd:120`) builds exactly that shape, cached once and returned as a deep copy so a caller cannot corrupt the template. One naming drift: the decision names `TargetSelector.nearest_enemy()`, which does not exist — the code uses `TargetSelector.enemies()` (`src/data/TargetSelector.gd:107`), whose default resolution is NEAREST. Action target is `TargetSelector.triggering()` (`:91`), as decided. |
| 2 invisible in the UI; authored 5-slot contract | **invisibility holds; the "5" never did** | See "The authored contract is four" below. |
| 3 inject at the encoder boundary, not the domain | **holds** | The append is inside `GambitEncoder.encode_gambits` (`:96`). `Gambit`, `GambitList`, `UnitRosterData`, and the UI editor contain no safety-net code — a grep for `safety` across `src/data/` and `src/ui3/` returns nothing. Both host paths route *through* the encoder rather than around it: `GPUArena._build_encoded_gambits` (`src/scenes/GPUArena.gd:442`) sends even a gambit-less unit through `GambitEncoder.encode_gambits([])` precisely so it still gets the net, and `NavigatorMain._build_encoded_gambits` (`src/scenarios/NavigatorMain.gd:1492`) mirrors it. |
| 4 `MAX_GAMBITS` 5 → 6, 80 → 96 ints | **holds; one comment did not follow** | `MAX_GAMBITS = 6` in both authorities — `src/gpu/shaders/combat_common.glslinc:30` (generated source) and `src/gpu/GPUConstants.gd:16`. Stride is 96: `combat_common.glslinc:614` and `GPUBatchSimulator.gd:101` (`# 96 ints per unit`). But the second GDScript copy, `GPUCombatPacker.gd:686`, still reads `const GAMBITS_PER_UNIT = MAX_GAMBITS * GAMBIT_SIZE  # 80 ints per unit` — the expression is right, the comment is the pre-bump number this decision retired. |
| 5 no runtime observability hook | **holds, and the follow-up it deferred to LANDED** | No `safety_net_fired` signal exists; `GPUCombatInterpreter`'s `EventKind` has no such member. The scenario-suite predicate the decision named instead is built: `no_safety_net_hit(unit='X')` (`tests/gambit_runner/GambitAssertions.gd:332`), which walks `action_committed_events` for a commit whose `current_gambit == GPUConstants.MAX_USER_GAMBITS` — the discrete witness, so host-frame sampling cannot hide a fallback commit. |
| 6 composes with existing fall-through | **holds, and is guarded end-to-end** | `scenarios_B_fallthrough.gd:845` (`B-SAFETYNET`) gives a Monk one authored gambit that heals a nearest ALLY with no allies present, and asserts the ATTACK commit arrives *from slot `MAX_USER_GAMBITS`*. That proves the GPU shader evaluates the injected slot, which the pure `GambitSafetyNetTest` cannot. |

### The authored contract is four, not five — and it was four before this ADR was written

Decision 2 says "The authored 5-slot contract is unchanged; the UI gambit
editor renders 5 slots." Measured:

- `GambitList.VISIBLE_SLOTS = 4` (`src/data/GambitList.gd:68`), and
  `ensure_fixed_size()` (`:71`) is **destructive in both directions** — it pads
  up to 4 and `pop_back()`s down to 4.
- Every roster-side entry point runs it: persistence
  (`GambitList.from_array` → `Character.gd:419`), `Unit.set_gambit_list`
  (`src/units/Unit.gd:1615`), and `GPUCombatTestBase.gd:469`. A fifth authored
  gambit cannot survive a save/load round-trip.
- The encoder's authored cap is genuinely 5 (`MAX_USER_GAMBITS = MAX_GAMBITS - 1`,
  `GPUConstants.gd:99`; `GambitEncoder.gd:83`), and scenario files reach it
  because `GambitScenarioRunner` (`tests/gambit_runner/GambitScenarioRunner.gd:191`)
  passes raw arrays and never constructs a `GambitList`.

So the authored surface is **two-tier**: scenarios may author five, anything
that passes through `GambitList` is capped at four. On the roster path slot 4 is
therefore always the encoder's null pad — 16 ints per unit of permanently dead
buffer, sitting between the last authored slot and the safety net.

This is not drift. `VISIBLE_SLOTS = 4` arrived with the initial project import
(2026-05-24), and this ADR was written 2026-06-17 — the "5 authored slots"
framing was **already wrong on the day it was accepted**. What decision 2
actually secured, and what does hold, is the *invisibility*: no domain or UI
code knows the safety net exists.

### One `is_empty()` in a sibling file is what keeps the safety net reachable

`GambitList._create_empty_gambit()` (`src/data/GambitList.gd:83`) pads short
lists with **"Always: Wait on Self"** — an unconditional WAIT. Under rule A1
(lower slots evaluated first) such a pad *always matches*, so if it ever reached
the encoded buffer the pass would terminate on it and the safety net at slot
`MAX_USER_GAMBITS` would be unreachable for every under-filled unit — silently
re-creating the standing-still shape this ADR exists to retire.

It does not reach the buffer, because both host paths filter on
`Gambit.is_empty()` (`src/data/Gambit.gd:271`), whose four conditions —
`ActionKind.WAIT`, action target `SELF`, condition target `SELF`, exactly one
`always()` condition — are precisely the shape `_create_empty_gambit()`
constructs.

That is an undocumented invariant this decision depends on: **the pad shape and
the `is_empty()` predicate must move together.** Change one without the other
and the safety net dies quietly on the roster path — with no test failure from
`GambitSafetyNetTest`, which only exercises the encoder, and none from
`B-SAFETYNET`, whose scenario feeds a raw array that never sees a `GambitList`
pad at all. Neither guard is positioned where this would break.

### Also fixed here

The Context sentence listing "rules A1 / B1 / B2 / B6" was wrapped so that
`B1 / B2 / B6` began a line, which registered a spurious `b1` **amendment**
anchor on an ADR that has no amendments. The sentence was rewrapped (no words
changed) so the false anchor is gone; the anchor checker stayed green across
the change, which is what proves nothing was citing it.

### References graded

`docs/gambit-rules.md` exists and contains **no** occurrence of "safety",
confirming the "No `gambit-rules.md` change required" consequence held. The
ADR-0001 links resolve to the local
`0001-gpu-combat-buffer-layout-is-shader-authoritative.md`, and its version-bump
rule is live: `SHADER_VERSION` is validated shader-vs-generated at boot
(`GPUBatchSimulator.gd:262-267`).
