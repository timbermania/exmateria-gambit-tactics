# A turn nobody can take is spent where it opens

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §11 is one paragraph: *"`GambitBattle`
must drop into the `NavigatorMain` walk the way combat does today. Given that
NavigatorMain runs a bare `CombatLoop` (not `GPUArena`), this is exactly the
requirement that forces §1's component-node decision."* It is a CHECK, not a
feature — ADR-0239 put the [TurnDirector](../../src/gpu/TurnDirector.gd) on the
loop rather than on `CombatHost` because `NavigatorMain` extends no host, and #898
is where that claim either costs one line or is exposed. ADR-0244 left the matching
soft spot for the forecast strip: it rides the CAMERA rather than the host, and
until a second host mounted it, that was *"an argument and not yet a demonstration"*.

The mount is the easy half. The hard half is a question neither the design nor the
ticket asked: **the walk's battle is played by nobody.** It is a spectacle that runs
itself to annihilation while the story walk waits on `CombatLoop.victory`. A turn
director freezes the world and hands the turn to somebody; in the walk there is no
adjustment UI (#894), no rollout driver (#897), and no player — the first crossing
would be handed to no one and the walk would stop there forever.

## Status

accepted

## Decision

1. **`NavigatorMain` mounts the same director, on its bare loop, in one line.** §11's
   check passes: `TurnDirector.mount(_combat_loop)` in `_build_frozen_combat_loop`,
   right after `boot_battle` creates the simulator the director reaches through. No
   `CombatHost`, no host change, and nothing rebuilt — the director is a child of the
   LOOP, which is the property the placement was chosen for. The strip costs a second
   line (`TurnQueueHud.mount(camera, director)`), which is ADR-0244's soft spot
   discharged: it mounts on the camera seat `CombatUI` and the dialogue boxes already
   use, and neither host knows anything about the other.

2. **The stop is a POLICY on the director — `stops_the_world`, WAIT by default — and
   the walk mounts the non-stopping one.** A turn is announced and spent where it
   opens: the gate returns false, the frame's tick drain carries on through the same
   tick, and the turn costs zero ticks. Design §3 already named this shape ("Active
   mode is the same machine that simply does not stop at the next turn"); this is its
   first and smallest form — the stop is gone and nothing else is claimed. No shot
   clock, and no player who may interject.

   REJECTED: **an auto-commit driver in the host**, connected to `turn_opened` — the
   shape `GambitBattle` already uses for enemy turns (`call_deferred("_pass_turn")`).
   It fails on arithmetic. `CombatLoop.turn_gate` returning true BREAKS the frame's
   tick loop, so a commit that lands at idle caps the sim at **one turn per frame**,
   and the walk's Gariland battle spends **225 turns** — the walk would need 225
   frames of battle where it currently resolves in a handful. Committing *synchronously*
   inside the emit instead re-enters `_open_turn` through `commit`'s own drain, which
   is exactly the re-entrancy `GambitBattle` defers to avoid.

   REJECTED: **mounting nothing in the walk.** §11's check is then never made, and
   the strip's "rides the camera" claim stays an argument. It would also leave the
   walk's forecast permanently meaningless — see decision 4.

3. **A turn nobody holds takes no snapshot.** ADR-0239 takes the pre-turn image
   before the freeze because `cancel` returns to it. Under this policy nothing can
   cancel — the turn is spent inside the same call that announced it — so the image
   is dead weight, and `cancel()` correctly refuses (there is no open turn to undo).
   That is also what keeps the policy affordable: a snapshot is four GPU slice
   readbacks, and the walk takes 225 turns in a battle that resolves in about three
   seconds of wall clock.

4. **The walk's battle is DIRECTED even though nobody plays it, and that is the
   point of consuming the turns.** With no director, nothing calls `consume_turn`;
   the kernel stops advancing a meter that has crossed and leaves it at its crossing
   value, so every living unit sits permanently ready and `TurnQueue.forecast`
   degenerates to "everyone, now" forever. Spending the turns is what keeps the meters moving, and
   it is why the strip in the walk shows a queue that MOVES — 11 units, 225 turns,
   all 11 of them taking one, and the strip repainting on every single turn because
   every turn reorders the queue. The kernel writes the meter and never reads it (ADR-0236),
   so no combat outcome can change: the walk's battle is bit-for-bit the battle it
   was, with a clock now legible on screen.

5. **`NavigatorMain._combat_active` keeps its single writer, and this is the
   deliberate answer #891 asked for.** The mirror is the PUMP gate — `_process` calls
   `tick()` only while it is true — and it is not the freeze authority; the loop's own
   `combat_active` is, written in lockstep by `_set_combat_live` and by nothing else.
   Under this policy the director never touches `combat_active` at all, so no second
   writer appears. **#897 is where that changes**: a rollout driver that HOLDS a turn
   needs `stops_the_world` true, and then a director freeze under a player-paused
   mirror would resume a world the player paused. The question is not answered here
   because it cannot be — there is nothing yet that can hold a turn.

6. **The strip is freed with the battle; the director is not.** The director is a
   child of the loop and dies with it. The strip is a child of the CAMERA, which
   outlives every battle in the walk, so both teardown paths (`_teardown_world` and
   `_end_combat_and_advance`) free it explicitly — otherwise the last battle's queue
   draws over the next map.

## Consequences

**A director that stops is a director that hangs an unattended walk, and it is
measured, not argued.** Seeded `stops_the_world = true` in the walk:
`NavigatorTurnDirectorMountTest` times out at its 120s wall-clock budget having
committed **zero** turns, against 3.0s and 225 turns green. The world froze on the
first crossing and stayed there. The same seed reddens the mirror arm, because
`NavigatorMain._combat_active` (true, the pump gate) then disagreed with
`CombatLoop.combat_active` (false, the director's freeze) — decision 5's second
writer arriving exactly where it was predicted to, and a preview of the question
#897 has to answer.

**One turn per frame is the ceiling for any host that defers its commit**, because
the gate breaks the drain. That is fine for a battle a person is playing — nobody
notices a frame between an enemy's turn and its result — and it is a fact #895's
rollout driver should price before it inherits `GambitBattle`'s deferred
`_pass_turn`: at the fast-forward rates the walk and the test rigs use, a frame per
turn is the difference between three seconds and three minutes.

**"The queue moved" is not evidence that a turn was SPENT, and one seeded defect is
what proved it.** Dropping the `consume_turn` call from the non-stopping path — the
one line that makes a turn cost anything — passed BOTH rigs: 20 headful arms green,
the unit test green, and the only visible trace was the walk's wall clock going 3.0s
to 17.0s with nothing asserting on it. The distinct-taker arm cannot see it, because
a meter stops advancing at its crossing and every unit crosses carrying its own
overshoot: an unspent ready set keeps GROWING and each larger overshoot takes the
head, so the queue changes hands whether or not anything is being spent. Units dying
does the same thing at walk scale. The arm that catches it reads the BUFFER —
`TurnDirectorTest` arm 6C announces a turn, reads the meter the announcement named,
and requires it to drop by exactly FULL one tick later (`unit 3 was announced at
meter 108 and reads 108 — expected 8`). A count of who was announced is a claim
about the announcement; only the meter is a claim about the spend.

**Measured.** `NavigatorTurnDirectorMountTest` (headful, real GPU, the real Gariland
walk) 20 arms green — 225 turns committed over 11 units, the strip repainting on
every one of them, at a wall clock of 3.0s against 3.7s for the same walk before the
mount. Both on a quiet box; the same rig reads 8.8s on a contended one, which is the
box and not the policy, and is the reason the comparison is quoted as "not slower"
rather than as a speedup. `TurnDirectorTest` grows arm 6, which drives the SAME fat frame under both
policies (WAIT breaks it off at the first crossing; the walk's policy drains all 60
ticks while turns are announced and spent inside them) and then reads the buffer.
Three seeded defects, each reddening only its own arms: the walk that stops (8 arms,
including the freeze and the mirror), the spend that never lands (arm 6C), and a
strip left on the camera at battle end (2 arms). `GambitBattleTest`,
`TurnQueueHudTest`, `TurnQueueTest` and `NavigatorGarilandVictoryTest` green
unchanged — `stops_the_world` defaults to WAIT, so nothing that was played before is
played differently.

**A freeze arm gated on `combat_active` cannot see a freeze**, which is the second
thing the seeds caught. The first version sampled the director's state only on frames
where the loop was live — and a director that freezes writes `combat_active` false,
so the sample was skipped on exactly the frames that mattered. Seeded, it passed
while the walk hung, and the failure was reported by the mirror arm instead. The
sample is now taken on every frame after the battle has gone live once.

**A freed object compares EQUAL to null in GDScript**, which cost this rig two
false reds before it was understood: the director and the strip are freed when the
battle ends, so `_director != null` after the fact cannot tell "never mounted" from
"mounted and torn down". The rig latches booleans at first sighting instead. Any
test that asserts on an object with a lifetime shorter than its own has this
problem.

**Soft spots, stated as such.** The walk's battles are now turn-ordered and nothing
looks at the order — the strip draws it and no decision is made from it, which is
correct until #897 and is worth remembering when reading the walk's battles. The
forecast costs one GPU readback per turn (the HUD refreshes on `turn_opened`), and
at Gariland's 11 units over 225 turns that is inside the measurement noise; a much
larger cast, or a contended GPU, could make it visible, and the coalescing fix
(recompute at most once per frame) is deliberately not built on a cost nobody has
observed. And `stops_the_world` is a boolean where design §3's Active mode is a
larger thing — a shot clock, a player free to interject mid-stretch. This is not
that, and claiming it would be claiming a mode nobody has played.
