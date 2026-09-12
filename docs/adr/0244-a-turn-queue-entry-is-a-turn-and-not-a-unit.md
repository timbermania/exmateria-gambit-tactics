# A turn queue entry is a TURN and not a unit

> **PARTLY SUPERSEDED by [ADR-0269](0269-the-turn-queue-strip-is-a-row-of-framed-cards-on-a-band-up-for-the-whole-battle.md)**
> — decisions **6** (built on `UIPortraitFrame`; the strip is UI3 elements now), **7**
> (mirroring as the ONLY side-marking; it is kept but demoted beside a team-coloured
> underlay) and **9** (the `max_shown` 16 belt and its truncation warning; the cap is a
> live display policy at 8 now, and it is meant to bite). Decisions **1-5** and **8** stand
> unchanged, and dec. 1 (an entry is a TURN) is the premise the whole redesign is built on.
>
> ⚠️ This file's rejection of *emphasising the acting card* is **REOPENED**. ADR-0269's first
> build settled it from the other side — the strip could not need to mark the acting card
> because it was only on screen while there WAS one — and ADR-0269 dec. 8 then reversed that:
> the strip is up for the whole battle, so for most of it the head card is nobody's turn.
> Nothing stands in the argument's place; see that ADR's soft spots.

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §6 asks for the turn queue "shown
**one full round-robin deep**: extend the queue until every living unit appears at
least once", so that it is "self-scaling, so a slow unit's long wait is *visible*
rather than implied". The arithmetic landed with the turn clock (#889, ADR-0236) —
`TurnQueue.forecast` is closed-form, needs no simulation, and `GPUTurnMeterTest`
holds it against the kernel. This file is the view over it, built (#893).

The design settled the DEPTH and left the rest to the build, and the rest is where
a turn queue view goes wrong. "One full round-robin deep" is a statement about how
far to extend, which only makes sense if the queue's element is a **turn** — the
same unit can be several of them — and that single reading decides the data
structure, the redraw policy and what the strip can say. It did not say how often
the projection is re-taken, which matters because the queue is a projection of a
clock running at 60 ticks/sec while the ORDER moves only at turn boundaries. And it
did not say whose plumbing reaches the buffer, which is the question that decides
whether a HUD ends up owning a second copy of the director's reach.

## Status

accepted

## Decision

1. **A queue entry is a TURN, not a unit, and the strip draws one card per
   entry.** This is §6's own sentence read literally, and it is the whole design:
   a unit fast enough to act three times before a slow one acts once contributes
   three cards, and *the pile of cards standing in front of the slow unit is how
   its wait is shown*. Measured at Gariland: the strip is exactly 11 cards over 11
   living units, `[4, 10, 2, 8, 5, 1, 0, 9, 7, 6, 3]`, head `4:Squire3` — the
   director's own taker.

   REJECTED: one card per unit carrying a "next in N" number. That is a roster
   with a countdown attached, it silently collapses the repeat that carries the
   information, and a collapsed repeat reads as "that unit acts once", which is
   the opposite of what the queue says.

2. **The strip carries no numbers.** `ticks_from_now` rides in the data and is
   never rendered. Position is the entire language, which is what §6 means by
   *visible rather than implied*: a wait shown as a number is exactly the implied
   form the design rejects, and it is also the unstable one — the number changes
   sixty times a second while the order it belongs to does not, so drawing it
   would mean either a flickering readout or a per-frame text rebuild, both bought
   for information already on screen.

3. **`forecast()` lives on the `TurnDirector`, not on the HUD.** The reach — loop
   → simulator → this battle's slice → `TurnQueue` rows — is exactly what
   `_open_turn` already walks, and #895's rollout driver and #897's value function
   want the same rows. A view that walked it itself would be a second copy of the
   director's plumbing living in `ui3`, and the two copies would be free to
   disagree about which battle's slice they meant.

   It returns `[]` while `gpu_simulator` is null. That is deployment (ADR-0242
   dec. 2) — a real state, not an error — and it is what makes the strip hide
   itself through the one phase that has no turn order at all, with no phase check
   anywhere in the view.

4. **Two edges, not a poll: `turn_opened` and `resumed`.** That pair is COMPLETE,
   which is why it is two signals and not four: `commit` and `cancel` each end by
   either opening the next turn (which emits `turn_opened` again) or resuming.
   They are also the only two moments the queue can have moved, and the two
   moments the player looks at it.

   REJECTED: a `_process` poll, which buys a GPU readback every frame for a queue
   that changes at turn granularity — and `CombatLoop` drains ~16 ticks in one
   frame at these scene rates, so a frame-granularity view is *coarser than a
   turn* anyway (#891). Also rejected: subscribing to `turn_committed` as well,
   which buys a second readback of a queue that is about to be read a millisecond
   later.

5. **The redraw gate is keyed on the ORDER, and its witness is a counter.** An
   unchanged order does not repaint, so refreshing on every turn edge is not a
   rebuild of every portrait. The gate is only observable as work NOT done, and
   node identity cannot see it — a queue of the same LENGTH reuses its frame
   objects whether the gate fires or not, so an identity assertion alone is
   VACUOUS here. `TurnQueueHud.draws()` is the arm, the shape
   `TunablesRegistryViewTest` already reads a rebuild through. Identity is still
   asserted, for the different defect of a resize that frees and rebuilds a strip
   that did not change size.

6. **Built on `UIPortraitFrame`, not on `UIRosterBar`.** The bar applies its
   portrait template to every frame at once and a queue interleaves the two teams
   entry by entry, so per-entry properties would be fighting the widget. It is
   also the right level for a second reason: the bar's assembly — `CombatUI.tscn`,
   `UICombatManager` — is what ADR-0137 scoped for global demolition, and the
   assembly is the condemned part, not the portrait card underneath it.

7. **The two teams face each other.** An enemy card is mirrored, which is
   `CombatUI.tscn`'s own convention for `EnemyRoster`, applied PER ENTRY because a
   queue interleaves the sides. It costs no colour, no label and no second row,
   and it is the only side-marking the strip carries.

8. **`GambitBattle` frees the inherited legacy `CombatUI`, exactly as `GPUArena`
   does.** Not cosmetic and not scope creep: unbound, that node draws eight empty
   white "Unit" cards down both margins of the screen — captured before the fix —
   which is precisely the real estate a battlefield HUD wants, and no HUD can be
   called readable while it is there. The node arrives inherited from
   `assets/scenes/CombatCamera.tscn` and a child of an instanced scene cannot be
   removed per-consumer (ADR-0204), so freeing it at boot is the only per-host
   move available. **THE THIRD COPY OF THOSE FIVE LINES IS THE SIGNAL TO DO THE
   GLOBAL DEMOLITION ADR-0137 ALREADY SCOPED**, not to copy them again.

9. **Truncation is reported once, on the edge.** `max_shown` is 16 — comfortably
   above a Gariland round-robin — and a strip that had to trim says so with one
   `push_warning` when the trimming STARTS, not on every refresh. A silently short
   strip would read as "the queue ends here", which is the opposite of true; a
   warning per refresh is a log nobody reads.

## Considered options

**A per-unit turn bar (the CT gauge column) instead of a queue.** Rejected by §6
itself: a bar per unit is the *implied* form — every viewer has to do the division
themselves, and the answer changes as speeds change. The queue is the same
information already evaluated. The turn meter's own on-screen home is
`UnitInfoPresenter`'s `ct` row (ADR-0236), which is a different view for a
different question ("how close is THIS unit"), and it stays.

**Emphasising the acting unit — a bigger head, a frame, a highlight.** Not built.
The head of a queue is at the head, and position is the language decision 2 already
committed to; a second marker for the same fact is redundancy the strip has to pay
for in pixels. Recorded as a readability call made from one screenshot, not from a
player (see the soft spots).

**Mounting the HUD on the host scene.** Rejected for the reason design §1 gives for
the director: `NavigatorMain` would replicate it. It mounts on the CAMERA and reads
the director, so #898 inherits it in the same one line the director costs.

**A vertical strip down one edge (the FFX arrangement).** Rejected on measurement,
not taste: at the ~315 virtual pixels this camera's frustum is tall, eleven cards
stacked vertically fill the screen edge to edge, while eleven laid horizontally
occupy about 800 of 1024 across. The aspect picks the axis.

## Consequences

**The strip is a reader and can never be a writer.** It reads
`TurnDirector.forecast` and holds no reference that can freeze, commit or advance
anything, so a HUD defect cannot become a battle defect. `show_entries` is the
pure-view seam that follows from it: a test drives the whole view with fabricated
rows and needs no GPU, no director and no battle.

**A UI3 window host left at the camera's own origin draws perfectly and is
invisible.** `UIWindowHost` places a window by writing only its `x` and `y`, so a
host at `z = 0` puts every window ON the near plane. `CombatCamera.tscn` gives
`CombatUI` its `z = -10` in the SCENE, so nothing in any script says it, and the
first build of this HUD inherited the omission: eleven correct cards, correct
order, correct flips, nothing on screen. **No layout unit test can see this** — the
positions it asserts were all right. The fix is one line in `_ready`
(`position.z = -screen_space_depth`) and the finding is the reason a screenshot was
the acceptance instrument.

**Two things now sit in the camera's seats, and they do not compete.** #941's
deployment picker (ADR-0247) mounts `FormationMapHost` under the same camera, and
its own note says it never collided with the deprecated `CombatUI` because *at rest
it shows nothing at all* — the band is faded out and the pair is parked off both
edges. This strip is the opposite: it lives at the top and is hidden through
deployment, which is exactly when the picker is on screen. Re-captured after the
merge: the same eleven cards, `[4, 10, 2, 8, 5, 1, 0, 9, 7, 6, 3]`, nothing
overlapping. (`FormationMapHost`'s `local_z` comment names `-10` as "the shipped
`CombatUI` depth", which is the same house convention the invisible-host finding
below rediscovered the hard way.)

**`GPUArena` and `GambitBattle` now free the legacy `CombatUI` in two places.**
Deliberate duplication with a trigger attached (decision 8). Nothing else changed
for the arena.

**Measured.** `TurnQueueHudTest` 7 arms green, with FIVE seeded defects each
reddening only its own arms and nothing else: collapsing a repeat entry (arms 1 and
7), never flipping the enemy (arm 3), removing the redraw gate (arm 4), removing
the truncation cap (arm 5), and laying the strip out right-to-left (arm 2).
`TurnQueueTest`, `TurnDirectorTest`, `GambitBattleTest` and `CombatCameraMountTest`
green unchanged.

**Soft spots, stated as such.** The readability calls — no numbers, no emphasis on
the acting card, a mirrored card as the only side-marking — rest on one captured
frame of Gariland and on §6's own wording; they are the parts of this a player
settles, and #939's grilling session is where that happens. `max_shown` 16 has
never been reached in a real battle, so decision 9's warning path is exercised only
by its test. And `NavigatorMain` does not mount this yet: that is #898, and until
it does, the claim that the HUD rides the camera rather than the host is an
argument rather than a demonstration.
