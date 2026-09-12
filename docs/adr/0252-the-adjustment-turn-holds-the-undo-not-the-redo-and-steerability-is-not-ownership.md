# The adjustment turn holds the undo, not the redo, and steerability is not ownership

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §4 makes the open turn an editing
window: "on your turn you edit **only the unit whose turn it is**", "**all
adjustment types legal** — gambits, equipment, job, ability slots", "edits apply
**on commit**; cancel restores the pre-turn snapshot", and a job change
"auto-prunes gambit slots referencing abilities the new job can't use, **and shows
what was pruned**". #894 is that wiring, and it names the one constraint that
decides its shape: the screen is the `ui3` formation screen, and **it must not be
forked**.

ADR-0239 built the freeze and ADR-0235 built the two GPU primitives. What neither
could build is the half that only a host can see. `TurnDirector` mounts on a bare
`CombatLoop` with no host and no roster, so its snapshot is the GPU's three
buffers — and the formation screen's Equip / Ability / Change-Job flows write
straight through to the durable `Character` (ADR-0005), which is on the CPU and is
in no SSBO. Before this file, `reconfigure_unit_from` had **zero production
callers**: a mid-battle equip or job change on the map-hosted screen mutated the
Character and the kernel never heard, and a cancel restored a GPU that had
forgotten the edit while the Character still remembered it.

## Status

accepted

## Decision

1. **The pre-turn image has two halves, and the host owns the second.**
   `AdjustmentTurn` is pure and scene-free, the shape `DeploymentAssignment`
   already has (ADR-0242 dec. 3): it holds the taker's `Character.to_dict()`, and
   the host wires it to the director's three signals — `turn_opened` takes the
   image, `turn_cancelled` puts it back, `turn_committed` is the one crossing to
   the GPU. It never sees the director, and the director gains no API. The
   ordering this rests on is already the director's: `turn_cancelled` is emitted
   *before* the same turn re-opens, and `turn_committed` *before* the drain, whose
   ready list is recomputed rather than cached "because a cached ready list is a
   claim about a world a `reconfigure_unit` just edited".

2. **Edits are made eagerly on the Character and land late on the GPU — the turn
   holds the UNDO, not the redo.** Staging them would mean the Equip, Ability and
   Change-Job flows all writing into an overlay instead of the Character, which is
   the fork of the formation screen #894 forbids in as many words. Holding the
   undo costs one `to_dict()` per turn and touches none of them. This is a
   constraint acting on the design, not a preference: the eager write is the
   screen's existing behaviour and the ticket ruled the screen off limits.

3. **Steerability is not ownership, and the words stay apart.** The screen already
   asks one question before lighting its action rows — is this selection OWNED
   (ADR-0137: an enemy gets the same screen, read-only). A turn adds a second,
   transient term. `selection_is_steerable()` is the conjunction, and
   `_apply_ownership` asks it instead. Ownership is a property of the UNIT;
   steerability is a property of the MOMENT. One flag for both would be wrong for
   whichever case it was not written for.

4. **The gate is on the EDIT, never on the LOOK.** ADR-0137 Amendment 6 rules that
   △ is never refused — "no phase, no march and no camera driver has a reason to
   refuse a LOOK". So the turn does not close the screen or narrow what it shows;
   it disables the action rows, through the mechanism that already exists for an
   enemy. A non-taker's screen mid-turn is exactly an enemy's screen: complete,
   readable, inert.

5. **Three phases, three answers.** DEPLOYMENT: the whole owned squad is editable —
   no GPU battle exists yet (ADR-0242 dec. 2), so an edit has nothing to diverge
   from and lands at commit by construction. TURN_OPEN: only the taker, because
   under any wider rule your fastest unit becomes a universal remote, every other
   CT bar is decoration, and deployment stops being a real decision. RUNNING:
   nobody — the turn *is* the reconfiguration, so editing while the world plays
   would make the turn order ornamental.

6. **The commit writes TWO buffers, because the state is in two.**
   `reconfigure_unit_from` moves job / equipment / ability slots through
   `UNIT_CONFIG_SCHEMA`'s recompute/clamp/carry column; the gambit list is not in
   the unit block at all but in its own SSBO, so it goes separately through
   `set_unit_gambits`. Either half alone lands half an edit.

7. **The push is skipped on an untouched turn, and that is a COST gate, not a
   correctness one.** ADR-0235's no-op identity arm proves an unedited
   `reconfigure_unit` is bit-exact, so a host that pushed unconditionally would
   still be correct. It is skipped because the enemy and guest turns are the
   common case and a battle spends hundreds of them.

8. **The prune drops only stale ABILITY rows, and returns them.** ATTACK, MOVE and
   WAIT are job-independent verbs every unit always has, so a prune that touched
   them would be deleting the player's work over nothing. The usable set is the
   primary skillset ∪ the secondary's — the ROM's own model of where action
   abilities come from (`AbilityLoadout`). It returns the dropped rows rather than
   a bool, because §4 requires the loss to be SHOWN: a gambit list that looks
   armed and is not is the most confusing failure this design can produce, and it
   is worse than either refusing the job change or leaving a slot that no-ops.

9. **The usable set is NOT filtered by `learned_abilities`.** A gambit naming an
   unlearned ability of a job you are still in is a slot the player is working
   toward; deleting it on an unrelated equip change is the silent destruction the
   prune exists to avoid. The question is "can this JOB do it", not "can it do it
   yet".

10. **`Character.restore_mutable_from` restores IN PLACE, all the way down.** The
    roster index, the catalogue's owned overlay and the battlefield `Unit` all
    hold a reference to the Character (ADR-0005 — one durable representation,
    which is only true while there is one object), so `from_dict`'s fresh instance
    would leave three holders looking at the state being undone. **And the same
    rule applies one level deeper**: a `Unit` binds `unit_progression` and
    `gambit_list` DIRECTLY at spawn and never re-reads them from the Character, so
    assigning fresh composed objects is the identical bug with a smaller radius.
    Fields are copied from the property list rather than a hand-written list,
    because `UnitProgression` gains fields and a list is a restore that silently
    stops covering the newest one.

## Considered options

**A staged edit model** — the screen writes into a pending overlay, applied to the
Character on commit. Rejected: it is the fork. Every edit flow on the formation
screen would have to be re-pointed, and #894's own wording rules that out.

**Putting the CPU image in `TurnDirector`'s snapshot**, so cancel is one call.
Rejected: the director deliberately mounts on a bare loop with no host, no roster
and no `Unit` nodes — `TurnDirectorTest` proves it by running there — and a
`Character` is a thing only a host has. It would also make the walk's director
(ADR-0245, `stops_the_world` false) carry an undo for turns nobody holds.

**Refusing △ on a non-taker**, so the screen only ever opens on the editable unit.
Rejected: that is refusing a LOOK, which ADR-0137 Amendment 6 settled, and it
would make the mode's own inspector unreachable for the entire battle.

**Extending `can_open` to answer per-column.** Rejected for the same reason plus a
mechanical one: `can_open` gates ○ only, △ is deliberately ungated, so the gate
would be on one door of two — and the door it does not cover is the one the design
sends the player through.

**Pruning at the moment of the job change rather than at commit.** Not rejected on
merit — it is better feedback — but there is nothing to hook: the Change-Job screen
is a visual builder with no writeback yet, so there is no job-change edge to
listen to. The prune runs at commit, which cannot be bypassed, and moves earlier
the moment that edge exists.

**Refusing a job change that would strand gambits**, or leaving the slots as
silent no-ops. Both rejected by §4 and restated in dec. 8.

## Consequences

`reconfigure_unit_from` has a production caller for the first time. ADR-0235's
second primitive shipped in April and has been dead code since; the keystone's
own no-op identity arm is what lets dec. 7's skip be an optimisation rather than a
correctness condition.

**`Character.gd` grew a restore verb and a generic property copier.** The copier is
static and takes any two objects; it exists because `UnitProgression` has twenty-odd
fields today and will have more.

**The measurement that changed the build.** `AdjustmentTurnTest` (51/51, five
seeded defects each reddening only their own arms) proves the class against a stub
simulator, and it is *structurally* unable to see whether the host wires it to
anything: a `commit` that is never called and a `commit` on an untouched turn look
identical from inside the class. So `GambitBattleTest` gained arm 4b, which edits a
real `Character` mid-battle and reads the answer back out of the GPU buffer —
`brave`, because it extracts straight from the progression with no derived
`unit_stats` in the way. **That arm caught a real defect on its first run**: the
in-place restore preserved the Character and swapped its composed objects, the
`Unit` kept the old ones, and a cancelled edit (`brave = 13`) was pushed to the GPU
by the NEXT commit where 77 was expected. dec. 10's second half is that finding.
Two further seeds on the host wiring — commit unwired, cancel unwired — redden only
their own assertions.

**What is NOT here.** §5's imperative gambits — the one-shot top-priority lock-on
with finite charges, a watchdog and a cancel refund — are a separate ticket. They
are independent of the turn's gambit edit by the design's own rule ("charges are
already the scarcity; double-taxing makes the imperative feel bad to use at all"),
and their only coupling to this file is that the refund rides the cancel dec. 1
installs.

**And the surface the turn opens onto is still empty.** The gambit editor
(`UIGambitEditor3`) has had no home since ADR-0137 Amendment 2 hid `UICombatManager`,
and `GPUArena` freed the arena's copy outright — its own comment marks the gambit
surface as the one thing that went dark with no new home. This ADR gives the
adjustment turn its contract, its scope rule and its crossing; equipment, job and
ability slots are editable through it today, and **gambits are not, because there is
no screen for them**. That is the follow-on, and it is where §7's "seeded per-job
playbook" has to land too: ADR-0242 already recorded that a scenario-booted cast has
empty gambit lists, so the editor will open onto nothing until something authors
into them.

`GambitBattleTest` is 101 assertions and still ends in annihilation; arm 4b holds
one player turn open (a new `_hold_turns` flag on the rig, because the drive loop
spends every commandable turn the instant it opens) and hands the battle back
afterwards, restoring the probed value so arms 5 and 6 play the battle the seed
describes.
