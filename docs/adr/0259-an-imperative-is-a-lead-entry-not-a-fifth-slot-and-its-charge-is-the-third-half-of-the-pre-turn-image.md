# An imperative is a lead entry, not a fifth slot, and its charge is the third half of the pre-turn image

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §5 is one paragraph and four bullets: a
one-shot, top-priority "lock-on" that self-removes, removed on
`CombatLoop.action_committed` or by a watchdog, with **no refund** on expiry, from
**finite charges per unit per battle**, **independent** of the turn's gambit edit —
and §4 adds the fifth rule, that **cancel must refund any charge spent that turn, or
cancel becomes a trap**. Every one of those is settled. #1006 executes them.

What it could not execute before now is the first bullet's word *top*. ADR-0252 built
the adjustment turn and ADR-0255 built the surface, and between them a unit's four
gambit slots are readable and editable mid-battle. An imperative is neither: it sits
**above** all four for one action and is then gone, so it is not a rule the player
authored and it is not a thing `GambitList` can hold.

## Status

accepted

## Decision

1. **An imperative is a LEAD ENTRY in the encoded buffer, and it costs no slot.** The
   shader walks slots ascending and takes the first match
   (`evaluate_gambits_up_to`), so "top priority" is a POSITION — nothing in the
   kernel has to learn the word, and no shader changes. The room was already there:
   `GambitList.VISIBLE_SLOTS` is 4 and `GPUConstants.MAX_USER_GAMBITS` is 5, with
   ADR-0048's safety net after both, so a unit with all four slots authored **and** an
   order standing encodes to exactly the five authored words the buffer already holds.

2. **It rides the commit's SECOND write as a parameter, not a third write.** ADR-0252
   dec. 6 splits the crossing in two because the state is in two buffers; an
   imperative is a gambit-list edit, so it belongs to the second of them.
   `AdjustmentTurn.commit` gained a `lead` argument, defaulting to null, and
   `GambitEncoder.encode_for_unit(unit, lead)` is the one place that knows the lead
   goes first. A host that pushed it separately would write that buffer twice per
   commit with only the ordering of the two calls deciding what the kernel reads.

3. **The charge is a THIRD half of the pre-turn image, and it is neither of the other
   two.** The director's snapshot covers the GPU and `AdjustmentTurn`'s
   `Character.to_dict()` covers the CPU roster — a charge is in no SSBO and on no
   Character, so neither would refund one. `ImperativeGambits` is wired to the SAME
   three director signals beside the adjustment turn, and for the same reason:
   `turn_cancelled` is emitted before the turn re-opens, so a cancel is idempotent
   rather than cumulative.

4. **The charges are NOT on the `Character`, and that is a rule about persistence.**
   The Character is the durable representation (ADR-0005) and is saved; a lock-on
   stored on it would still be armed in the next battle, and a charge stored on it
   would be refunded as a side effect of `restore_mutable_from` rather than by a rule
   anyone wrote. Charges are per unit **per battle**, so they are keyed by unit index
   and cleared by `reset()` when the battle starts.

5. **Re-aiming is a new order and costs a charge.** One order may stand at a time;
   issuing again replaces it and spends again. The alternative — a free re-aim while
   one stands — makes the first issue a draft rather than a decision, and the design
   prices a decision at a charge. Within the turn it was spent on, the cancel refunds
   every charge the turn spent, which is where a player who changed their mind gets
   their money back.

6. **Cancel refunds ALL of the turn's charges and restores the order that STOOD.** Not
   one charge, because two issues on one turn is a re-aim and both were paid for; and
   not a bare clear, because an order issued on an earlier turn must survive a later
   cancelled one — a cancel that disarmed a unit the player never disarmed is the same
   trap §4 is about, one level down.

7. **The watchdog is a deadline in TICKS and a pool-emptiness test, and there is no
   third clause.** §5 rules out the cleverer predicate in as many words: reachability,
   LOS and affordability are shader decisions, and a CPU copy of one is a second
   opinion that will eventually disagree with the kernel that actually acts. A clock
   and a liveness count can disagree with nothing.

8. **Ticks and not turns, because the world is frozen for the whole of a turn.** A
   deadline counted in turns would be a deadline in frozen time (ADR-0239). The
   default is **600 ticks, two ability cooldowns** — long enough to survive an approach
   across the map, short enough that a forgotten order does not stand for the battle.

   > **Amended by ADR-0260.** As written this decision set the default at 120 ticks and
   > derived it *from the meter*: "a Speed-7 unit acts about every 14 ticks and 120 is on
   > the order of eight of its own turns" at `TURN_METER_FULL` 100. ADR-0260 widened the
   > meter to 3600, which inverted that derivation — 120 ticks became a fifth of one turn
   > and less than half of one 300-tick cooldown, so an order would routinely expire
   > before its unit could act on it once, and expiry does not refund (dec. 11). The
   > deadline is now priced in the **action cycle** it actually races (dec. 10: only an
   > action spends an imperative), not in the meter, so it no longer moves when the meter
   > does.

9. **§5's "target dead/removed" is the target POOL running out, because the GPU cannot
   express a named target.** `TargetSelector.PoolType.SPECIFIC_UNITS` is in
   `GambitEncoder.UNSUPPORTED_POOL_TYPES`, so an order claiming to lock onto Unit 7
   would encode as something else and the screen would be lying about what it armed.
   An imperative locks onto a **rule** — "the weakest foe" — and the watchdog asks
   whether that rule can still pick anybody out. The answer is a liveness count, which
   is CPU-visible truth and not a re-derivation of anything.

10. **`action_committed` is the right removal edge because a MOVE does not raise it.**
    It is keyed off the GPU's `cast_step_id` bumping (`GPUCombatInterpreter`), so it
    fires once per ACTION — ability or pure attack — and not on movement. An order to
    attack across the map therefore survives the approach and is spent by the blow. A
    signal that fired on movement would consume the order before it landed, and the
    feature would not work at all.

11. **Neither removal edge refunds.** §5: "a wasted lock-on is a real mistake". The
    only refund in the design is the cancel, and it is a refund of a decision not yet
    committed.

12. **The watchdog rides `_process`, which is the first thing `GambitBattle` has ever
    added to the pump.** It cannot go on a turn edge: the world runs BETWEEN turns,
    which is exactly the stretch an unconsumed order is exposed for, and a check that
    only ran at turn boundaries would leave an expired lock-on standing through the
    whole of it. It costs one Dictionary emptiness test per frame in the common case —
    every frame of every battle nobody issues an order in.

13. **The surface gains a LEVEL, not a form** — the payoff ADR-0255 dec. 2 was written
    for. The slot level carries a fifth row that is **not a slot** ("! Imperative (2)",
    or the standing order read back), and taking it opens `Level.IMPERATIVE`: three
    strings and a `_show_level` case, mounted on the same generic
    `GambitSurfaceMenu`.

14. **The order is composed on a DRAFT, and the draft is not a slot.** `_gambit()`
    hands out the draft while an order is in flight and the selected slot otherwise, so
    `choices_for`'s applies are written once and the CHOICE level never learns which it
    is serving. An implementation that reused the slot cursor would silently overwrite
    the rule the player just authored, which is why that is the arm the rig seeds.

15. **The order asks TWO questions — Do and To — and its To is a whole aim spanning
    BOTH selectors.** ADR-0255 dec. 3 reads "a part offers named whole values"; at the
    level an order needs it, the whole value covers `condition_target` (the pool it
    picks out) *and* `action_target` (act on whoever it picked). An imperative that
    matched on one unit and acted on another is not a lock-on. There is no When and no
    If: an imperative is unconditional by construction, which is the whole of what
    "top priority" buys, and a condition on it would make it a rule — which is what the
    four slots already are. "Them" is dropped from its To for the same reason: with no
    standing trigger there is nothing to have been triggered by.

16. **Composing is free; only Issue costs.** The charge count is printed on the Issue
    row and not in the title, so the cost sits next to the press that pays it and a
    refusal ("Issue — none left") is readable before it is made.

17. **The new arms went into the two tests that already had the setup.** Test charter
    clause 13: a test here is a process with a 2.3 s floor, so splitting costs 2.3 s
    forever. The ledger's arithmetic is pure and joined `AdjustmentTurnTest` (51 → 118
    assertions); the end-to-end path needs a Gariland turn and the real coordinator and
    joined `GambitSurfaceTest` (45 → 94). **Zero new processes and zero census bump.**

## Considered options

**A fifth `GambitList` slot.** Rejected on two counts: `ensure_fixed_size` pads to
four and the list is what the durable `Character` persists, so a fifth slot would
survive the battle and read as a rule the player authored. It also would not be
top-priority without a sort.

**A `priority` flag on `Gambit`, plus a shader sort.** Rejected: position already IS
priority in the kernel, so the flag would be a second encoding of the same fact, and
the two would eventually disagree. It buys nothing that prepending does not.

**Naming a specific target unit** — the literal reading of "lock-on". Rejected on the
encoder's own declared gap: `SPECIFIC_UNITS` is unsupported (ADR-0023), so the order
would encode as something else and the screen would be lying about what it armed. The
honest version aims at a rule, and dec. 9 is that reading.

**Refunding the charge when the watchdog takes it.** Rejected by §5 in as many words.

**Charges shared across the squad** rather than per unit. Rejected: it hands the whole
squad one lock-on between them, and the design says per unit per battle. It is also
the implementation that passes every arm about a single unit, which is why
`AdjustmentTurnTest` arm 8 asks about the neighbour.

**Taxing the turn's gambit edit as well** — spending a charge to open the surface, or
refusing an imperative on a turn that also edited a slot. Rejected by §5: "charges are
already the scarcity; double-taxing makes the imperative feel bad to use at all."

**A "stand down" row that withdraws a standing order.** Deliberately not here. The
turn's cancel is the undo, and a stand-down available at any time would let a player
dodge §5's "a wasted lock-on is a real mistake" by simply taking it back.

**A separate `ImperativeSurfaceTest` scene.** Rejected on charter clause 13 — it
would have re-paid a full Gariland boot and joined two census ratchets to assert
things the existing rig is already standing in front of.

**Awaiting real frames to prove the watchdog fires.** Rejected as a hang risk: the
sweep only acts while the world is RUNNING, and a commandable turn opening mid-wait
freezes it for as long as the rig is willing to wait. Arm 13 hand-cranks the host's own
`_process` in a bounded loop instead, committing any turn that opens, with
`action_committed` unhooked for the length of the arm so the only thing that can take
the order is the watchdog. The first version cranked exactly one frame and failed:
`CombatLoop.tick` deliberately KEEPS its accumulator remainder across a turn-gate break
(ADR-0239), so one hand-called frame can drain that remainder, open a turn, and leave
the sweep correctly gated out.

## Consequences

**`GambitEncoder` grew two statics and lost a duplicated filter.** `authored_gambits`
is now the one answer to "what has this unit actually authored" (the list minus the
`ensure_fixed_size` padding), and both `encode_for_units`' no-gambits warning and the
imperative's lead turn on it. `encode_for_unit(unit, lead)` is the single place that
knows a lead goes first, and it is what `AdjustmentTurn.commit` and the host's removal
re-push both call.

**`AdjustmentTurn.commit` gained a fourth parameter and every existing caller is
unchanged** — it defaults to null, and `AdjustmentTurnTest`'s 51 pre-existing
assertions passed untouched on the new signature before a single imperative arm was
written.

**`GambitBattle` overrides `_process` for the first time.** The standing comment there
— "nothing here pumps anything (ADR-0239)" — is now qualified rather than deleted: the
pump is still `CombatHost`'s, and what this adds is a read of a clock that only the
pump advances.

**Two tunables, both ADR-0068 `static var` homes in their production owner:**
`gambit.imperative_charges` (2) and `gambit.imperative_watchdog_ticks` (600, re-derived by
ADR-0260 — see dec. 8). §5 names
the first one's successor itself — "from a `Tune` constant now, job-derived later" —
and map #886 still carries the job-derived charge count as the refinement that
outlives this ticket.

**The measurement that shaped the build.** Five seeded defects, each reddening only
its own arms:

* `cancel` refunds nothing (`if spent > 0` → `if false`) — **4 assertions**, all in
  the refund arm. Notably `cancel()`'s RETURN value stayed correct and green, which is
  what shows the arms separate the report from the effect.
* the lead appended last instead of first — **2 assertions**, exactly the two
  positional ones.
* the watchdog's pool clause dropped (`dead_pool` → `false`) — **2 assertions**, and
  the deadline arm stayed green, which is what shows the two triggers are separated.
* `_gambit()` never hands out the draft — **5 assertions**, including "slot 1 is
  UNTOUCHED", the arm dec. 14 exists for. Every other assertion about the order stayed
  green under it, which is the point: without that one arm the conflation is invisible.
* `_sweep_imperatives()` deleted from `GambitBattle._process` — **1 assertion**, arm 13,
  which exists for exactly that and was worth writing: every other imperative arm calls
  a handler directly, so a watchdog wired to nothing would have been green everywhere
  else. It is why arm 11 also asserts `action_committed.is_connected` outright rather
  than trusting that calling the handler proves anything about the edge.

**What is NOT here.** The lists are still empty. #892 recorded that a scenario-booted
cast has no authored gambits, so on Gariland an imperative is the first and only rule
most units have and the safety net (ADR-0048) is the rest. That is not this ticket's
to fix — §7's seeded per-job playbook is map #886's own fog — but it is why an
imperative issued today looks more decisive than it will once the standing lists mean
something. The `enabled` flag on a `Gambit` remains unexposed for the reason ADR-0255
gave, and the imperative does not use it: an order is removed from the buffer, not
disabled in it, because a disabled slot is a slot and an imperative is not one.
