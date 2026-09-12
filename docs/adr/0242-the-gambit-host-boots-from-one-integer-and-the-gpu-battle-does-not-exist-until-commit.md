# The gambit host boots from one integer, and the GPU battle does not exist until commit

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §1 asks for "a new host scene beside
`GPUArena`, not a mode flag on it", §10 for a boot "from a **`scenario_id`**, which
hands over map, song, weather, cast, and both deployment zones from one integer",
and §9 for a deployment where "ENTD offers n units, the ATTACK.OUT zone offers m
tiles; **the player assigns which unit goes on which tile and configures it**" —
mechanically "**a turn with the clock stopped and the CT gate removed**", so that
"the deployment screen is not new UI, it is the turn UI in a different mode." This
file is that host, built (#892).

The design settled the shape and left three things to the build. It did not say
**when the GPU battle comes into existence** — and once the squad cap can bench a
unit, that stops being an implementation detail and becomes the thing that decides
how big the battle is. It did not say **who the player may command**, having ruled
in ADR-0239 dec. 5 that the director must never answer that; somebody downstream
has to, and this host is the first one that can. And its "not new UI" is a claim
about the *screen*, which leaves open whether the deployment DECISION is new
state — it is, and making it a pure editable model is what keeps the screen from
becoming a second one.

## Status

accepted

**dec. 1 is superseded by
[ADR-0264](0264-gambit-battle-is-a-seek-into-the-navigator-not-a-second-combat-host.md)**,
which decides that `GambitBattle` stops being a `CombatHost` and that "play one battle"
becomes a seek into `NavigatorMain`. ADR-0264 does not name this file; the marker is added
here by [ADR-0275](0275-the-gambit-lab-is-a-cell-a-mirror-and-a-verdict-the-kernel-writes.md)
dec. 14, which found the contradiction unmarked. Every other decision below stands — the
one-integer boot, the GPU battle not existing until commit, and the deployment model are
untouched by ADR-0264.

## Decision

1. ~~**`GambitBattle` is a third `CombatHost` subclass, thin, beside `GPUArena`.**~~
   **(superseded — see Status.)**
   It boots and it deploys; everything else mounts on the DIRECTOR, which is a
   component on the loop (ADR-0239). `GPUArena` has three subclass tests reading
   state off it (`GPUThrashTest` / `GPUTeleportTest` / `GPUItemFallthroughTest`)
   and a second rules model behind a flag would fork all of them. `CombatHost`
   carries accessor mechanics and no policy (ADR-0018), so a third subclass costs
   nothing there and buys the pump — this host adds none of its own.

2. **The GPU battle does not exist during deployment, and the simulator is sized
   by the squad that took the field.** `GPUArena` boots its simulator before
   placement because its deployment march *runs on it* (ADR-0042); this host has
   no march, and the zone's `max_squad_size` is smaller than the roster — at
   Gariland 5 against 7 — so the cast that boots is not the cast that fights.
   Sizing at boot would either allocate for units that never take the field or
   force the assignment to be final before it is made. `combat_loop.gpu_simulator`
   is therefore **null for the whole of deployment**, which is the mechanical form
   of ADR-0239 dec. 9 — "the units are not in the GPU buffer at all": there is nothing
   to write through to, so placements are CPU-side on the `Unit` nodes by
   construction rather than by discipline, and `start_battle` at commit is the one
   write. The test asserts the null directly.

3. **The deployment decision is a pure, editable model — `DeploymentAssignment` —
   and `clear()` is its only undo.** The screen is not new UI, but the decision is
   new state: which of n units stands on which of m tiles, edited over time, with
   rules (a squad cap, one unit per tile, a mandatory unit) that have to be
   answerable before anything is placed anywhere. Holding it as a scene-free model
   is what lets those rules be tested with no map and no GPU, which is exactly the
   condition deployment runs under. It holds no snapshot and offers no `cancel`,
   for dec. 2's reason: `TurnDirector.cancel` refuses the `DEPLOYMENT` state, and
   "throw my placements away" is a reset over CPU state, not a restore.

4. **`DeploymentPlan` is ONE assignment, computed; `DeploymentAssignment` is the
   assignment the player edits.** The plan predates this (wayfinder #234 D) and
   called itself a deliberate v1 placeholder for exactly this screen. It now
   exists, and the plan stays rather than being replaced, because
   `auto_fill` delegates to it: the debug path and the arena's no-strategy path
   cannot drift apart if they are the same function.

5. **The mandatory flag is honoured BY CONSTRUCTION.** ATTACK.OUT flags bit 0
   (`scenarios.json`'s `ramza_mandatory`, set for scenario 9) makes Ramza
   mandatory, and `auto_fill` hoists the mandatory units to the front of the order
   before filling. `DeploymentPlan`'s own docstring says "Ramza first", but that is
   a claim about what `CharacterCatalog.owned_units()` happens to return; the test
   puts the mandatory unit **last** in roster order, which is the arm that
   distinguishes the two.

6. **The cap bounds the SQUAD, not the edits.** A sixth body is refused; moving an
   already-placed unit is always legal. The cheap version — refuse any `place`
   once the count is at the cap — forbids dragging a unit around a zone you have
   filled, which is the most ordinary thing a player does on that screen.

7. **A mandatory unit is never placed FOR you, and the field holds a slot open for
   it.** The effective cap for a non-mandatory unit is `max_squad_size` less the
   number of mandatory units *not yet placed*, so Gariland is a cap of 4 until
   Ramza is down and 5 afterwards; a mandatory unit is never held back by its own
   slot. Settled by the user in a grilling session on 2026-09-06, after the first
   build of this host, and it replaces the version where `problems()` was the only
   enforcement.

   The argument is where the refusal *lands*. Without the reserve a player fills
   all five tiles with cadets, presses START, and is told "Ramza must be deployed"
   over a full zone with no indication of whom to bench — legal all the way to the
   commit and then refused at it. The commit-time check stays as the backstop
   (`problems()` still names him), but the placement that would strand him is
   refused when it is made, which is the difference between a rule the player can
   act on and a rule that tells them the zone they just filled is wrong. It is also
   why `_report_refusal` names the reserve specifically: the tile is empty and the
   squad is under the cap, so nothing on screen otherwise explains the refusal.

   The auto-fill path is unaffected — it hoists mandatory units to the front (dec.
   5), which discharges the reserve on its first placement.

8. **The ROM places everyone except your squad, and it places them exactly.** The
   ATTACK.OUT zone table is *player start tiles only*; enemies and ENTD-blue guests
   stand on their authored ENTD coords, including `upper_level` (ADR-0219). They are
   placed before the player is asked anything, and no ROM-placed unit stands inside
   the player's zone — both asserted, because an implementation that ran the zone
   assignment over the whole cast looks fine until you notice the enemy party
   standing in your deployment box.

9. **The deployment assignment is what says which units you may steer.** ADR-0239
   dec. 5 has the director announce the taker and refuse to classify sides, because
   `NavigatorMain` composes team0 as owned ∪ ENTD-blue and a guest therefore sits
   on team 0. The host answers instead, and its answer is the assignment itself:
   **the units you deployed are the units you command.** At Gariland that is
   exactly the ROM's own rule — Delita arrives ENTD-blue on team0, fights beside
   you, and takes no orders. A team-based test would hand him to the player; an
   `is_player_controlled`-based one would need a second source of truth for a
   question the player already answered.

10. **The scenario cast is one seam — `ScenarioCast` — moved out of `GPUArena`
   rather than copied.** ADR-0180 retired `PartyRoster`/`EnemyRoster` so that "the
   arena stops being a separate combat universe"; a second host copying the arena's
   spawn-then-compose would rebuild the thing that ADR retired. The same argument folds
   `_build_encoded_gambits` into `GambitEncoder.encode_for_units`, where it was
   already hand-mirrored once (`NavigatorMain.gd:1846` said so in its docstring)
   and was about to be a third time. The navigator's per-unit spawn TAIL is
   deliberately not folded — it stamps `special_name`, carries HP across a walk and
   hands the clock to `SCENARIO` — which is the disagreement `UnitSpawn`'s own
   docstring warns against swallowing.

11. **No new verbs.** Enter commits the open turn (committing with no edits IS
    "wait", ADR-0239 dec. 6), Backspace cancels it, Space commits the deployment
    and starts the battle — the same ADR-0137 Amendment 4 mapping `GPUArena` uses,
    with the phase supplying what acting means rather than the keycode meaning two
    things.

## Considered options

- **A mode flag on `GPUArena`.** Rejected by §1 and by the subclass count: three
  tests read arena state, and a second rules model behind a flag forks all of
  them. The cost of a third host is one `_ready` and a scene file, because
  `CombatHost` already holds the mechanics.

- **Boot the simulator at `_ready` and simply hide the benched units.** Rejected:
  it makes `units_per_battle` a function of the roster rather than the squad, so a
  7-unit roster deploying 5 allocates for 7 and the GPU battle contains units the
  player declined to field. It also destroys dec. 2's structural guarantee — with a
  simulator present, "placements are CPU-side" becomes a convention somebody can
  break by writing through.

- **A `DeploymentScreen` node.** Rejected as the literal thing §9 forbids: a class
  by that name IS the second UI. The deployment MODE is a director state and the
  deployment DECISION is a model; what is left — pick up, set down, bench — is the
  host's dispatch on the cursor's confirm, which is the shape `GPUArena` already
  uses for the march.

- **A snapshot for deployment, so cancel is uniform with a turn's cancel.**
  Rejected by ADR-0239 dec. 9: there is nothing to snapshot. Adding one would mean
  booting the simulator early purely so that cancel could look symmetric, which is
  the previous option wearing a different hat.

- **`auto_fill` in roster order, trusting `owned_units()` to return Ramza first.**
  Rejected: it is true today and unenforced, and the failure mode is a battle that
  starts without your protagonist.

- **Enforcing the mandatory rule at the commit ONLY (`problems()`), with no
  reserve.** This is what the first build did, and it is not wrong — it is refused
  at the wrong moment. See dec. 7.

- **Auto-placing the mandatory unit** so the rule cannot be tripped. Rejected by
  the user in the same session: where Ramza stands is a real decision and the
  screen should not make it for you. The reserve is the version that enforces the
  rule without taking the choice.

- **Classify commandability by team, or by the ENTD's `is_player_controlled`.**
  Rejected: team puts guests under player control, and the ENTD flag is a second
  source of truth for a question the deployment already answered.

- **Copy the arena's cast composition into the new host.** Rejected — ADR-0180's
  reason, restated: two copies of "who is in this battle" is how the separate
  combat universe got built the first time.

## Consequences

`GPUArena` loses 119 lines and gains two call sites; `NavigatorMain` loses its
hand-written gambit-encode mirror. Both keep their behaviour — the moved code is
the same code, and the only intended difference is that the new seam's per-unit
log label is a parameter rather than a hardcoded `[GPUArena]`.

The auto-fill debug path rides `--combat-autostart`, the flag `GPUArena` and
`simulation.skip_march` already use, so a rig reaches a live battle without a
keypress. `GambitBattleTest` deliberately does **not** use it: the assignment is
the subject, so the rig drives the cursor instead.

**A commandable turn has nobody to commit it yet.** The adjustment UI is #894, so
until it lands the host commits your turns on Enter and passes everyone else's
immediately. That is not a placeholder policy — it is ADR-0239 dec. 6's "wait",
which is what a turn with no edits *is*.

**The scenario-booted cast has empty gambit lists.** `UnitSpawn` mints a
`GambitList` and nothing in the boot path authors into it, so all eleven Gariland
units run on ADR-0048's injected safety net. This is not new here (the arena's cast
is the same cast), but it is newly *visible*: #894 opens its editor onto an empty
list, and §7's "seeded per-job playbook" is the thing that fills it.

**Measured — the tick-to-turn rate, which is what #892 existed to make feelable.**
Playing Gariland to annihilation with every turn committed unchanged: **244 turns
over ~1,650 ticks**, which at `TICK_INTERVAL = 1/60` is **a turn every ~0.11 s** of
battle time. Map #886 carries the fog as "a Speed-8 unit is ready every 13 ticks,
0.22 s"; that is the **per-unit** period, and what the player actually sits through
is that divided by the number of living units. At an 11-unit Gariland it is half
again as fast as the fog note assumed, and it gets *faster* as the roster grows —
so the lever cannot be the playback rate alone, which only stretches the gaps
between stops and cannot reduce how many stops there are.

The whole battle runs in **12.6 s** wall clock, so the end-to-end rig is cheap
enough to keep in the suite rather than behind a flag.

Two consumer ratchets move by two each — `ProceduralMapMountTest` 114 → 116 and
`CombatCameraMountTest` 112 → 114 — for the host scene and its rig.
