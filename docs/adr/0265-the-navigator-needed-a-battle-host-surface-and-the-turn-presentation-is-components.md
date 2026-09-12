# The navigator needed a battle-host surface, and the turn presentation is components

ADR-0264 decided that "play one battle" is a **seek into `NavigatorMain`** and that
`GambitBattle` stops being a second `CombatHost`. #1061 mounted `TurnDirector` on the
navigator's bare `CombatLoop` and #1064 gave it a stop policy
(`navigator.stop_on_turn`). The clock worked. Then somebody played it:

> it gets the turn but it doesn't do all the things that gambit battle does… it doesn't
> have the camera-go-to-unit when it's their turn. it didn't even have a map cursor.
> I mean this is nothing like a real battle.

Both specifics were real, and the framing they point at is the reason for this ADR.

## What was actually missing

ADR-0239 put `TurnDirector` on the **CombatLoop** precisely so a non-`CombatHost` could
mount it, and #1061 proved that works. What nobody checked is that **everything else a
turn needs was still on `GambitBattle`** — not on `CombatHost`, which holds only loop
accessors and carries no policy at all, so "make the navigator a `CombatHost`" would
have inherited none of it.

```
GambitBattle   extends CombatHost              ← every turn-presentation feature lived here
NavigatorMain  extends ScenarioPlayerScene     ← got TurnDirector, and nothing else
```

Twelve things sat on that host. Two of them are what the report names, and neither is
the missing-feature it reads as:

**The map cursor was a control-flow fact.** `_enter_command_cursor()` was called inside
`run_pre_battle`'s `if roster_fed:` block — **below** the `skip_pre_battle` early return.
That gate is on in every seek and every autoplay path, which is to say in every way a
human reaches a battle here, so **the "play battle N" path mounted no `CursorRig` at
all**. The feature was present, complete, and unreachable.

**Steerability did not exist.** `_go_live` arms combat gambits for every unit and there
was no `_commandable` set, so a stop froze a world in which the GPU auto-battle still
held all the controls, on **every** turn in the round-robin — the player's, the guest's
and the enemy's alike. That is what made a just-shipped feature read as "a pause button
with extra steps", and it is a bigger part of "nothing like a real battle" than any of
the visuals.

## Decision

**The turn-presentation features become components mounted by both hosts, and the
navigator grows a steerability set.** Composition, not inheritance: GDScript has no
multiple inheritance and the two hosts are two lineages, so this is the only shape
available — and it is the shape `TurnDirector.mount`, `CursorRig.mount` and
`TurnQueueHud.mount` already established on this exact seam.

Four decisions, in the order "make one stopped turn legible":

1. **The map cursor belongs to the BATTLE, not to pre-battle — and its SEAT belongs to
   the BUILD.** `run_combat` mounts it, after `_ensure_battle_world` has settled the
   opener — the same point in the lifecycle the pre-battle path reached it from, and it
   must not be earlier: the mount forces `PlayerCamera.camera_mode = CURSOR`, which under
   a live cinematic wakes a cursor beneath a screen. The seat also falls back from the
   leader to the first unit of the booted cast, so a **predetermined** battle (Orbonne
   deploys no owned units) stops being a battlefield you cannot point at.

   The pre-battle mount is **unconditional**. It was `if roster_fed:`, so on a
   predetermined battle `_pre_battle_active` was set with no loop and no cursor under it:
   the player parked over a field they could not point at and the cursor appeared only
   once combat started. A cursor and a frozen loop are what *"the battle is set up"*
   MEANS; neither is a question about how the cast was fed. (`_is_roster_fed` used to
   decide this too — see dec. 3 for what it answers now.)

   With both calls live, `_enter_command_cursor` runs **twice** on every battle, so the
   cursor is seated once — when the rig is BUILT — and not on each entry. This decision
   first said the opposite: *"the rig is built once and re-seeded, so the linear walk gets
   the same cursor it already had, re-seated on the leader as combat opens."* The re-seat
   was harmless only while pre-battle mounted no cursor on most paths. Once it mounted one
   always, the second call re-seated the cursor on the leader,
   `CursorController._on_cursor_moved` forwarded that to `PlayerCamera.track_cursor`, and
   pressing Space at deployment panned the battlefield away from wherever the player had
   walked the cursor. On a direct seek nothing has built a rig yet, so that call builds it
   AND seats it; the linear walk keeps the cursor where it was left.

2. **[`TurnBeat`](../../src/gpu/TurnBeat.gd) owns the beat** — the AT marker, the
   `help_message_popup` cue, the camera travel, the two battlefield input gates it
   closes, and `Home`'s recentre. `GambitBattle` keeps the third input gate, because
   Space and Esc reach neither the cursor rig nor the camera and only the host's
   `_unhandled_input` can swallow them; it keeps its own `print`, because two hosts write
   two log prefixes; and it keeps the *decision* to arm a beat at all.

   **Five components, not four.** `TurnBeat`, [`StopBadge`](../../src/ui3/elements/StopBadge.gd),
   `TurnQueueHud`, `CursorRig` and
   [`FeedbackHudManager`](../../src/ui3/elements/FeedbackHudManager.gd) — the over-unit
   damage/heal numbers and status bubbles, which had exactly ONE mount in the tree
   (`GPUArena`) and were therefore absent from both battle hosts. Each is mounted per host
   by hand, because the mounts happen at different lifecycle points and no one place knows
   all of them; what makes that safe rather than the drift it resembles is that each
   component has a single `mount()` and the sites grep as one census.

   ⚠️ **Space is ONE rule, differently reachable** — the gap this decision was accused of
   opening, and it does not. `GambitBattle.gd:1610` already states the rule: *"Space is GO
   — the one key that ends a stop the player is expected to end, in BOTH states that have
   one. It is still never a pause key."* The navigator lacks the tactical stop, so it
   cannot reach that arm. A missing state, not a conflicting meaning, and not a reason to
   keep `GambitBattle`.

3. **Steerability is a fact on the UNIT.** `Unit.commandable` answers whose turn is
   yours, read as a FILTER at turn-open rather than cached. Two writers, one field: the
   ENTD slot's `flags2_decoded.control` for a predetermined cast (through
   `BattleDeployment.slot_is_commandable`) and roster deployment for a roster-fed one.
   **A turn that is not yours is spent where it opens**, inside the freeze the director
   already took.

   This decision first read `NavigatorMain._commandable` *"off the same `_deployed_owned`
   list the team composition was built from"* — the derivation
   `GambitBattle.commit_deployment` does off its assignment — and excluded the ENTD-blue
   guests: *"a guest is on team 0 and is not the player's to steer."* Right at Gariland,
   false at Orbonne, and the word carrying the error is **guest**. `_deployed_owned` is
   filled only through `_ensure_owned_deployed`, which self-gates on `_is_roster_fed`, so
   on a predetermined battle it is empty, `_commandable` is empty, and
   `_on_director_turn_opened` finds no commandable taker for **any** unit: every turn is
   `call_deferred("_pass_turn")`'d and **the world never stops.** Orbonne is the one
   predetermined battle in the game, and its ENTD-blue cast is Ramza, Delita **and
   Algus** — all three the player's to steer in the original. So a rule written to exclude
   one guest excluded the player's entire side, and `stop_on_turn`'s narrowing —
   *"it stops on your turns"*, called out below as the point of the change — became
   "it stops on no turns" there. Strictly worse than the round-robin stop it replaced, and
   the same failure on any battle where `CharacterCatalog.owned_units()` is empty.

   The flag was already read to conclude *"deploy nobody"* — `is_predetermined()` is
   defined as `control_count() > 0`, and `BattleDeployment.control_count()` threw the
   number away after a `print`. Reading it once more, to answer *"steer whom"*, is the
   whole correction. Reading it per turn rather than caching also retires "resolved once
   per battle", and with it a set that cannot see a unit added mid-battle.

   **An empty steerable set stays legal but must be NAMED**, and is guarded by one test
   over every shipping battle root — no combat needed, it asserts on the composed teams.
   `NavigatorTurnStopTest` could not have found this: it walks Gariland only, where its
   arm (g) proves *enemy* turns existed and nothing proves the steerable set is non-empty
   in any battle.

   `_is_roster_fed` answers ONE question now. It used to decide (a) place the saved
   roster, (b) build the loop and mount the cursor at pre-battle, and (c) transitively,
   through `_deployed_owned`, who may be steered. Only (a) is a question about
   roster-feeding: (b) is dec. 1's unconditional mount, and (c) is this decision.

4. **[`StopBadge`](../../src/ui3/elements/StopBadge.gd) owns the seat, each host owns the
   sentence.** Deployment, an Esc pause and an open turn are three motionless
   battlefields ended by three different keys, and they were pixel-identical on the
   navigator exactly as they had been on gambit. What is shared is a CanvasLayer and an
   outlined label; what is not is the vocabulary — a badge that derived the sentence
   would need each host's steerability set, director and pause model handed to it one
   accessor at a time.

`stop_on_turn`'s meaning narrows with (3): it stops on **your** turns. That is a change
to a feature shipped nine days earlier and it is the point of the change, not a
side effect of it.

**The order this ADR suggested is superseded.** It read cursor verbs → steering → Space →
pause → picker → rollout, and it was written before four player-reported bugs. The order
is now **instrument → the guard test → steerability → the stop-toggle wiring → the
handback → the tactical stop and pause screen → steering → deployment**, and it lives in
[ADR-0177](0177-focus-is-a-stack-of-states-and-godot-can-make-the-bad-state-unrepresentable.md)
Amendment 3, which is where this work now runs. The reason is not that the handback work is
cheaper, though it is (~300 lines against ~1,300): deployment, steering and the rollout
driver each **add** an ownership edge — a phase that must hand off, a per-turn input claim,
a second decider — and landing any of them on a host that cannot hand anything back
multiplies the bug class those four reports are instances of.

**Amendment 1 (2026-09-09)** is folded into the decisions above rather than stacked beside
them, and this paragraph is the anchor its citations resolve against. It corrected dec. 3
(steerability is a fact on the unit, not a set difference against a deployment array), it
is why dec. 1's pre-battle mount is unconditional, it superseded the suggested order, and
it refuted the claim that Space means two things. It came from a grilling of four
player-reported bugs and was written by the author of the decision it corrects.

## Considered and rejected

**Make `NavigatorMain` a `CombatHost` (or gain one).** Rejected on inspection, not on
taste: `CombatHost` holds loop accessors and shared data holders and **explicitly no
policy** (ADR-0018's caution about re-introducing the coupling C8 removed). Not one of
the twelve features lives there. Becoming one would have inherited nothing and still
required composition, because `NavigatorMain extends ScenarioPlayerScene`.

**Accept that the spine's battle is a spectator view** and keep `GambitBattle` as the
playable host, retiring ADR-0264's PR 3. Cheapest, contradicts the ADR, and the user's
report reads as a rejection of it.

**Port the deployment picker first** (the largest of the twelve — ~600 lines, ~26
functions). Rejected as an ordering: the picker is what you use *before* a battle, and
every one of the four decisions above is visible the first time the player stops on a
turn. The picker and the rollout driver stay on `GambitBattle` for now, which is why
this ADR does not complete ADR-0264's PR 3.

**Duplicate the beat rather than touch `GambitBattle`.** It is a hot file — three
commits inside one hour on 2026-09-08, and a sibling worktree holds uncommitted
`TurnDirector` work. Rejected because a duplicated beat is a second copy of the
three-gate input swallow, whose whole content is that gating fewer than three is not a
swallow. Mitigated instead: **every name `GambitBattleTest` and `GambitSurfaceTest`
already read survives** — `_turn_beat_running()`, `show_turn_marker()`,
`turn_marker_unit`, `_turn_marker`, `_pause_badge` — as thin wrappers over the
components.

⚠️ **ADR-0264 rejected "extract a shared component" for BATTLE ENTRY only**, on the
ground that battle entry's invariants are entangled with the runner's action list so the
component converges on being most of `NavigatorMain`. That argument is about entry and
does not reach the presentation features, which depend on a cursor, a camera, a lattice
and a unit array and nothing else. Citing that rejection against this decision would be
citing it for a claim it does not make.

## Consequences

- `turn_marker_unit` and `_turn_marker` on `GambitBattle` are now **get+set forwarding
  pairs**. Getter-*only* properties are the hazard: GDScript drops a run of them, and
  every member after it, from the subclass-visible member table — which is why
  `CombatHost` writes its four scalars as pairs and why `GambitSurfaceTest`, a subclass,
  can still read these.
- `StopBadge` builds its label in `mount()` rather than in `_ready()`. A child added to
  an **out-of-tree** parent has its `_ready` deferred until the parent enters, and a
  badge whose label is null for that stretch is indistinguishable from a badge that
  refused to say anything.
- `_start_battle` keeps a `_commandable` guard even though non-commandable turns are
  passed. The pass is `call_deferred`, so there is exactly one frame in which an enemy's
  turn is open and a Space would spend a turn the player was never offered.
- The turn surface is cleared with the battle (`_free_turn_queue_hud`). The sprite is a
  child of a unit that is being freed anyway; the load-bearing part is the two
  **indices** — a `marker_unit` or `beat_taker` carried into the next battle names a
  unit in a cast that no longer exists.
- **This work is judged by playing it.** Both reported defects were found in about a
  minute at the keyboard while every test passed, and the tests that passed were not
  wrong — they asserted the clock, which worked.

## Status

accepted.

⚠️ **The number was claimed by scanning all worktrees (high-water 0264) *and* `gh pr
list` for numbers claimed by unmerged branches** — ADR-0258 records four collisions
caused by scanning only the filesystem. The window between claiming and pushing is still
open; this is a mitigation, not a fix.
