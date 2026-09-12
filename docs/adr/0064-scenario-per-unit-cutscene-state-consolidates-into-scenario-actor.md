# Scenario per-unit cutscene state consolidates into one ScenarioActor

## Status

Accepted (2026-07-03)

Everything a unit's cutscene owns becomes one
[ScenarioActor](../context/09-event-script-interpreter.md) value in a single
VM-owned `actors:{uid → ScenarioActor}` registry. The actor is a `RefCounted`
data bag holding the unit's `tint` ([ScenarioColorTint](../context/09-event-script-interpreter.md)),
`motion` ([ScenarioMotion](../context/09-event-script-interpreter.md)), `walker`
(`CinematicWalkState`), `atlas_y` offset, `home` anchor, and an `owner_iid` node
guard. Its whole per-unit lifecycle reduces to four verbs — `actor(uid)` (get-or-create),
`peek_actor(uid)` (non-creating), `forget(uid, node)`, `reset_all(units_by_id)` —
and the three previously-disagreeing reset paths (`start`, `set_rewind_target`,
`_forget_unit`) collapse onto `reset_all`/`forget`.

## Decision

Numbered 2026-08-28 so `ADR-0064 dec. N` resolves. Items 1–4 and 7 restate the
opening paragraph; 5–6 and 8 are stated in **Considered options** and
**Consequences**. No prose was removed or reworded.

1. **One registry.** Everything a unit's cutscene owns becomes one
   `ScenarioActor` value in a single VM-owned `actors:{uid → ScenarioActor}`
   registry; the five formerly-loose dicts go **fully internal**, with no
   forwarding properties.
2. **The actor is data.** A `RefCounted` bag holding `tint`, `motion`, `walker`,
   `atlas_y`, `home` and `owner_iid`. It holds **no owner node**, so it is
   testable with no scene boot; the VM resolves nodes and passes them *in*.
3. **Instance-id folds in as a guard, not a key.** `owner_iid` is a guard field —
   home re-captures when the live node's iid differs — preserving the node-identity
   safety at zero cost to the single-key interface.
4. **Four verbs.** `actor(uid)` (get-or-create), `peek_actor(uid)`
   (non-creating), `forget(uid, node)`, `reset_all(units_by_id)`.
5. **`forget` and `reset_all` are deliberately NOT symmetric.** `forget` = "this
   unit is gone": it erases the entry and touches **no** Unit field.
   `reset_all` = "the scene rewound, units persist": it clears the registry
   **and** resets each live unit's Unit-owned fields.
6. **The Unit-field reset lives in `Unit.reset_scenario_cutscene_state()`.** The
   VM never pokes `Unit`'s private `_rotate_state`/`current_anim_id` — ADR-0055's
   "reach rotate to reset, don't own it".
7. **`start` and `set_rewind_target` are both just `reset_all`**, so the
   reset-inconsistency bug becomes unrepresentable rather than merely fixed.
8. **Scope bound.** The effect-timer task-pump is not part of this change, and
   the actor is kept to the five per-unit structures + three Unit fields.

## The forcing bug

"Everything unit `0x13`'s cutscene owns" had **no home**: it was five VM
dictionaries — `_unit_tints`, `motions`, `_cinematic_walkers`,
`cinematic_unit_atlas_y_offset` (all uid-keyed), `_unit_move_home`
(instance-id-keyed) — plus three `Unit` fields never reset by any path
(`facing_angle`, `_rotate_state`, `current_anim_id`). The three reset paths cleared
**different subsets**: `_forget_unit` cleared all five dicts (0 Unit fields);
`start()` and `set_rewind_target()` cleared **only `_unit_move_home`**. On a
live-VM restart (the [`ScenarioPathApplier`](../context/10-scenario-branching.md)
member-walk calls `_vm.start()` without a scene reload) a stale tint, an in-flight
motion, a running cinematic walker, and all three Unit fields **leak across runs**.
Confirmed, not hypothetical — the disagreement is in the code, and the walk path
reaches it.

## Considered options

- **Status quo — five dicts, three brooms.** Each new per-unit structure adds a
  dict, an `erase` in `_forget_unit`, and a clear the two other reset paths silently
  omit. Knowledge of "unit `0x13`'s cutscene" is smeared across eight declarations
  and three reset sites that already disagree. Rejected — this is the friction the
  change exists to remove.

- **Dual-keyed registry (uid **and** instance-id).** Keep `_unit_move_home`'s node
  identity as a real second key on the actor. Rejected: it re-smears the thing we
  consolidate. The iid keying was a **workaround** for `start()` never clearing the
  four uid dicts — once `reset_all` clears *everything*, the only hazard a raw iid
  key still served (the same uid rebinding to a different node with no reset firing)
  is unreachable: remove-then-readd routes through `forget`, restart/rewind through
  `reset_all`. Instance-id folds in as an `owner_iid: int` **guard field** —
  home-capture re-captures when the live node's iid ≠ the stored one — preserving the
  exact node-identity safety at zero cost to the single-key interface.

- **Actor holds the owner `Unit` ref (or absorbs the walker's node).** Convenient —
  `reset()` needs no argument, home-guard reads iid itself. Rejected: it couples the
  actor's lifetime to a scene node, needs `is_instance_valid` guards throughout, and
  breaks the "actor is data" line that makes it testable with no scene boot. The VM
  already owns node resolution (`units_by_id`); it passes the live node **into** the
  two methods that need it (`reset`, home-capture). The one surviving transitive node
  ref is `CinematicWalkState.unit` — intrinsic to how the walker renders, predating
  this change, and not laundered out to chase a purity slogan.

- **`forget` and `reset_all` reset the same state (symmetry).** Rejected: they have
  different jobs and iterate different collections. `forget(uid)` = "this unit is
  gone" — it erases the actor entry and stays **behavior-identical to today's
  `_forget_unit`** (no Unit-field touch), so `ScenarioRemoveUnitTest`'s bookkeeping
  guard passes unmodified. `reset_all(units_by_id)` = "the scene rewound, units
  persist" — it clears the registry **and** resets each live unit's three fields (the
  bug fix). Forcing `forget` to also reset Unit fields is scope creep with no
  observed remove-then-reappear leak.

- **One ScenarioActor + four-verb interface (chosen).** A per-unit data bag in a
  single uid-keyed registry; the five dicts go **fully internal** (no forwarding
  properties — the getter-only-forward member-drop gotcha bites exactly here). The
  reset-inconsistency bug becomes **unrepresentable**: there is one lifecycle, and
  `start`/`set_rewind_target` are both just `reset_all`.

## Consequences

The interface is four methods and the dicts are internal, so `_forget_unit` stops
enumerating five structures by hand and the tick loops (`_advance_motions`,
`_tick_cinematic_walkers`, the per-frame tint tick) iterate one `actors` registry,
skipping null sub-states. Clearing a **sub-state** (Reset Palette drops the tint)
nulls a field; only `forget` erases the entry — two concepts (`peek_actor(uid).tint
== null` vs `peek_actor(uid) == null`) the old flat dicts blurred into one
`has()` check.

The Unit-field reset lives in **`Unit.reset_scenario_cutscene_state()`** — the VM
never pokes `Unit`'s private `_rotate_state`/`current_anim_id`. This honors
[ADR-0055](0055-scenario-motion-waits-collapse-to-one-is-done-predicate.md)'s "reach
rotate to reset, don't own it": `reset_all` calls the Unit method (which mirrors the
PSX `FUN_8013f20c` teardown), keeping `Unit`'s invariants inside `Unit`. Rotate stays
Unit-owned; `ScenarioMotion` stays the pure value the actor *holds*, not the actor —
ADR-0055's fault lines are untouched.

Tests migrate to the seam: `ScenarioSpriteMoveTest`'s `vm.motions[uid]` reads become
`vm.actor(uid).motion`; the `vm.motions.size() == 2` concurrent-motion aggregate
becomes an `active_motion_count()` read-helper;
`ScenarioRemoveUnitTest._test_forget_unit_clears_bookkeeping` becomes the core
`ScenarioActorTest` (the guard for the exact bug this fixes). The actor is a data bag,
so — like [ScenarioMotion](../context/09-event-script-interpreter.md) — most of it is
testable with **no scene boot**; only walker-touching assertions need the mock unit
they already use.

The effect-timer task-pump (the architecture review's Candidate 2) is **not** part of
this change — it reopens the ADR-0055 halt-gate fault line and is a separate axis. This
ADR keeps the actor to the five per-unit structures + three Unit fields.

## Amendment (2026-08-28) — every decision holds and the rejected asymmetry has its own test; the actor then grew past the scope sentence that bounds it, which is the consolidation working

*Audited 2026-08-28 against `src/scenarios/`, `src/units/` and `tests/`.
Decision items numbered the same day.*

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
| --- | --- | --- | --- |
| 1 | one `actors:{uid → ScenarioActor}` registry, five dicts fully internal | **yes** | `_unit_tints`, `_cinematic_walkers`, `cinematic_unit_atlas_y_offset`, `_unit_move_home` and the loose `motions` have **zero** live references in `src/scenarios/`; no forwarding property was added |
| 2 | `RefCounted` data bag, no owner node | **yes** | `ScenarioActor.gd` extends `RefCounted`, holds no node; the one transitive ref is still `walker`'s, exactly as the ADR carves out |
| 3 | iid as a guard field, not a key | **yes, with both halves guarded** | `capture_home` re-captures on iid mismatch, `clear_home` forces one for the same node; `ScenarioActorTest` has an arm for each |
| 4 | four verbs | **yes** | `actor:3265`, `peek_actor:3277`, `forget:3299`, `reset_all:3320` |
| 5 | `forget` / `reset_all` deliberately asymmetric | **yes — and the REJECTION is tested** | `_test_forget_does_not_reset_unit_fields` pins the rejected symmetry option |
| 6 | Unit-field reset lives on `Unit` | **yes** | `Unit.reset_scenario_cutscene_state:1880`; the VM never touches `_rotate_state`/`current_anim_id` |
| 7 | `start` and `set_rewind_target` are both `reset_all` | **yes** | `start:1029` and `set_rewind_target:1139` are the only two call sites in `src/` |
| 8 | scope: five structures + three Unit fields | **exceeded, by design** | six structures and four Unit fields today — see below |

### The forcing bug is gone at the level it was diagnosed

The ADR's complaint was not "a leak" but "three reset paths that clear different
subsets". Today there is one path and two call sites into it, and the state it
clears is the whole registry plus a single Unit method. `_forget_unit` no longer
exists as a symbol; `forget` is one line (`actors.erase(uid)`). The
inconsistency is unrepresentable in the sense the ADR claimed: there is no second
subset to disagree with.

The `_node` parameter of `forget(uid, _node)` survives as an underscore-prefixed
unused argument, kept — the source says — "for call-site parity with the PSX
teardown". That is the ADR's four-verb signature preserved literally even after
its reason (the per-node home erase) folded into `owner_iid` under dec. 3.

### The rejected option is the one with a test

`ScenarioActorTest` carries **fifteen** arms, and among them
`_test_forget_does_not_reset_unit_fields` asserts the *asymmetry* the ADR chose —
that is, it pins a **rejected** option's absence, not just the chosen one's
presence. Across this audit that is the first case of a considered-and-rejected
alternative being mechanized. It is also the arm most likely to matter: "make
`forget` and `reset_all` do the same thing" is exactly the tidying a later reader
would attempt, and the ADR's reason for refusing (different jobs, different
collections, and `ScenarioRemoveUnitTest` passing unmodified) is not visible from
the call sites.

The migrated seams the ADR predicted are all in place: `vm.actor(uid).motion`
replaces `vm.motions[uid]`, and `active_motion_count()` replaces the
`motions.size() == 2` aggregate — with its docstring recording *why* a bare
`actors.size()` cannot substitute (it would over-count tint-only or walker-only
entries), a subtlety the flat-dict version did not have to think about.

### Dec. 8's scope sentence has been overtaken — twice, and in the good direction

"This ADR keeps the actor to the five per-unit structures + three Unit fields."
Today the actor carries **six** and the Unit method resets **four**:

- **`pending_anim: int = -1`** joined as a sixth per-unit structure — the `{11}`/
  `{8C}` Unit Anim latch, the Godot mirror of the PSX writer's `unit+0x0C` slot.
  Its own docstring names why it lives here: it "survives a debug park untouched
  (like `walker`/`motion`) and is cleared only on **the ADR-0064 single reset
  path** (restart/rewind correctly discards it)."
- **The `{92}` SS=1 crystal billboard** joined the Unit-side reset as a fourth
  field, alongside `facing_angle`, `_rotate_state` and `current_anim_id`.

Both are the consolidation paying out. A new piece of per-unit cutscene state
went to the one home and inherited the one reset for free — which is precisely
what the ADR argued the five loose dicts made impossible ("each new per-unit
structure adds a dict, an `erase`, and a clear the two other reset paths silently
omit"). The sentence that is now false is the one bounding the change, not any
rule.

`reset_all` also gained an argument: `reset_all(units_by_id, preserve_poses := false)`,
the combat→scenario pose carry. The verb and its meaning are unchanged; only the
arity moved past what dec. 4 writes.

### Three stale counts, and one stale field name in a comment

- `ScenarioVM.gd:1025` and `:1137` both still say "the three Unit fields" beside
  the two `reset_all` call sites; the method resets four.
- Dec. 8's "five per-unit structures" is six.
- `ScenarioDialogueBoxPool.gd:529` says "the base lives in the VM's
  `_unit_move_home` (captured on the unit's first move)" — naming a field this
  ADR deleted. The behaviour it describes is still right; the address is not.

None of these is load-bearing: each is prose beside code that reads the actor.

### Recorded question — is dec. 8 a bound on the change, or on the actor?

Two readings, and this audit does not choose:

- **(a) A bound on the change.** "This ADR keeps the actor to…" describes what
  landed in *this* commit, in the same breath as excluding the task-pump. Under
  this reading nothing is violated — later state joining the actor is the ADR
  succeeding, and the sentence should simply be read in past tense.
- **(b) A bound on the actor.** The clause sits in the same sentence as a
  genuine, still-honoured scope exclusion (the effect-timer task-pump, which is
  still absent), which argues both halves were meant to constrain going forward.
  Under this reading a sixth structure needed a decision, and the fact that
  `pending_anim` cites this ADR while exceeding it means the growth rule is
  undocumented: nothing says what *may* join the actor, only what did.

The practical difference is whether the effect-timer exclusion is load-bearing on
its own or only as the second half of a sentence whose first half has already
lapsed. **Measured, the exclusion itself still holds** — no effect timer is on the
actor, and none of `ScenarioColorTint`/`ScenarioBgSound`/`ScenarioDarkScreen`/
`ScenarioWeather` has adopted the task contract (ADR-0055 dec. 6, audited the same
week). Note that the *stated reason* for that exclusion — "it reopens the ADR-0055
halt-gate fault line" — is the premise that ADR-0055's own audit found collapsed;
the exclusion holds in the tree either way.

### On mechanizing this ADR

Unusually well covered already: fifteen `ScenarioActorTest` arms reach all four
verbs, both lifecycle concepts, both halves of the iid guard, and the rejected
symmetry. Two arms are absent:

- **Dec. 1 as a negative:** assert the five old dict names have zero occurrences
  in `src/scenarios/`. That is the entire content of "fully internal", the
  regression is a one-line re-add, and the ADR explicitly warns about the
  "getter-only-forward member-drop gotcha" that a forwarding property would
  reintroduce.
- **Dec. 7 as a count:** assert `reset_all` has exactly two call sites in `src/`.
  The bug this ADR fixes was *three paths clearing different subsets*; a third
  call site — or a second path that resets by hand instead — is the shape of its
  return, and nothing today would notice.

Dec. 8 is the one item that should **not** be mechanized until the question above
is answered — a guard on "the actor has six fields" would pin whichever reading
the guard's author happened to hold.
