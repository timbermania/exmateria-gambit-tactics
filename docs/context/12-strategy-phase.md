# Strategy phase

The pre-combat phase where units take the field before `start_battle`. It owns
the **placement** of both teams onto the map, and it is entirely
**scenario-sourced**: the real FFT deployment data decides where units stand
(ADR-0043), with no procedural mode and no fallback (ADR-0258).

There are two of them, and they are different phases in different hosts, not two
spellings of one. `GPUArena` **auto-places** — the owned side onto the
[deployment zone](12-strategy-phase.md) by [deployment plan](12-strategy-phase.md),
everything ENTD-spawned onto its authored slot — and starts. `GambitBattle` opens
the [deployment picker](12-strategy-phase.md) and the player edits a
[deployment assignment](12-strategy-phase.md). Neither walks anybody anywhere.

**Deployment zone**:
The set of map tiles where a team may place its units, read from FFT's
**deployment-zone table** (`ATTACK.OUT 0xBBD4`, 768 × 12-byte records). Each
record is a `u32` **5×5 footprint bitmap** (`0x01ffffff` = full 5×5) plus a
center tile `(x, y)`, a facing byte holding the `zone_facing` and `unit_facing`
nibbles (see **start facing** below), and a `max_squad_size`; decoded it yields
up to 25 real tile coordinates. A [scenario](08-scenario.md) points at one via
`first_squad_deployment_idx` (and an optional `second_squad_deployment_idx`).
This is the authoritative source of **player start tiles** — where the squad
stands when the battle begins, and in `GambitBattle` the set of squares the
player is choosing among.
_Avoid_: calling it a "spawn point" (it is a multi-tile region the player
arranges units *within*, not a single point); conflating the **zone** (player
tiles, from this table) with **enemy tiles** (per-unit positions, from the
[ENTD](12-strategy-phase.md)); porting TacticsTemplateG's decode verbatim — its
bitmap loop reads `idx**2` where the format means `1 << idx`.

**Start facing**:
Which way a deployed squad faces before anyone moves — a property of the
[deployment zone](12-strategy-phase.md), **not** of the [ENTD](12-strategy-phase.md).
In a `control == 0` battle (Gariland, Mandalia — the ordinary case) the player's
units are not in the ENTD at all, so the ENTD's per-unit `initial_direction`
answers only for the enemy/guest cast; the squad's facing comes from the
deployment record's **byte `0x07`**, and from **both** its nibbles: the engine
composes them (`R = zone_facing + unit_facing - 1`, ATTACK.OUT overlay
`0x801C5588`, with the four unrolled placement loops writing a facing of
`(-R) & 3`). `parse_placement.start_facing_12bit` is that composition;
`NavigatorMain._deploy_owned_units` applies it as an Orientation pose, consumed
raw. `tools/score_deploy_facing.py` scores the rule against every shipped
battle, with control arms.
_Avoid_: reading the `unit_facing` nibble as an absolute cardinal — it is only
absolute when `zone_facing == 3`, which is why calibrating on Gariland alone
shipped Mandalia's squad standing side-on; and reading the emitted JSON key
`unit_facing_12bit` as "the `unit_facing` nibble lifted" (the key name is frozen
for its consumers, the value carries both nibbles).

**ENTD**:
The **unit-deployment table** (`ENTD*.ENT`, indexed by a scenario's
`entd_idx`): the actual roster of a battle, one 40-byte record per unit
carrying its job/stats/equipment **and** its exact `position_x/position_y`,
`upper_level`, `initial_direction`, and an `is_player_controlled` flag. The
non-player-controlled units' positions are the authoritative source of **enemy
start tiles** — enemies stand on them the way the player's squad stands on the
[deployment zone](12-strategy-phase.md). They are exact tiles, not a zone to choose
from, so an enemy's position is never a decision. When clamping to the enemy roster
size, prefer `team_color == 1` (red) positions over AI **guests**
(`is_player_controlled == false` but not red).
_Avoid_: treating ENTD positions as a zone-to-choose-from (they are fixed,
exact tiles). The old caveat here — that only the *positions* were consumed
while the `PartyRoster`/`EnemyRoster` units still fought — is retired with those
rosters (ADR-0180): the ENTD **is** the enemy side, composed through
`EntdBattle.compose_teams`.

**Deployment plan**:
ONE deployment assignment, **computed** rather than edited (`DeploymentPlan`):
owned units onto [deployment zone](12-strategy-phase.md) tiles in list order,
capped by the [squad cap](12-strategy-phase.md). It is what a host uses when no
player is choosing — `GPUArena`'s placement and `GambitBattle`'s debug auto-fill —
and what [deployment assignment](12-strategy-phase.md)'s own auto-fill delegates to.
It snaps: FFT places, then starts.
_Avoid_: calling it the assignment (the assignment is the thing being EDITED, and it
is a different type); giving it a turn order (nobody takes turns placing).

**Deployment assignment**:
Which of the player's units stands on which [deployment zone](12-strategy-phase.md)
tile — the whole content of the deployment decision, and the thing the player is
EDITING while the deployment screen is open (`DeploymentAssignment`). It answers
two questions at once, because the [squad cap](12-strategy-phase.md) is normally
smaller than the roster: **who fights** and **where they stand**. It is CPU-side
and holds no snapshot — deployment runs before the GPU battle exists, so there is
nothing to write through to and nothing to restore; "throw my placements away" is
a reset (`clear`), not an undo. It also survives the commit, as the record of who
the player chose: the units in it are the units the player may **command**.
_Avoid_: conflating it with `DeploymentPlan`, which is ONE assignment, computed
(the assignment's own auto-fill delegates to it); calling it a *formation* (that
is the out-of-battle roster screen); expecting a `cancel` symmetric with a turn's
(there is no pre-turn image to restore).

**Squad cap**:
How many units may take the field: the [deployment zone](12-strategy-phase.md)
record's `max_squad_size`, floored by the number of tiles and by the size of the
roster, because a cap you cannot reach is not a cap. Gariland's is **5** against a
7-unit roster and 8 tiles, which is what makes deployment a real choice rather
than a placement chore. It bounds the **squad**, not the edits — moving an
already-placed unit is always free. The cap that applies to a given unit is lower
by however many slots are **reserved** for unplaced
[mandatory units](12-strategy-phase.md); a mandatory unit is never held back by
its own slot.
_Avoid_: reading a zone record with no `max_squad_size` as a cap of 0 (it means
"bring everyone who fits"); enforcing it by refusing every `place` once the count
is reached, which forbids rearranging a full zone.

**Bench**:
The units a [deployment assignment](12-strategy-phase.md) left off the field. They
are in the cast and NOT in the battle: the GPU battle is sized by the squad at
commit, so a benched unit is never in the buffer at all.
_Avoid_: modelling the bench as a hidden participant (it has no GPU slot, no turn,
and no index).

**Deployment picker**:
The screen that answers **who fights on this tile** — the 4×2 roster grid, raised
over the live battlefield (not beside it) by ○ on an *empty*
[deployment zone](12-strategy-phase.md) tile, holding the
[bench](12-strategy-phase.md). Arrows walk it, △ opens a one-row menu
("Deploy Unit"), and choosing that row lands the selected unit on **the tile the
picker was opened from** — the placement was already expressed by opening it
there. ✕ backs out having deployed nobody. The grid holds the bench filtered by
what that tile would actually take, so a slot the [reserve](12-strategy-phase.md)
is holding shows exactly one unit.

It **comes in** rather than appearing: one gesture (`FormationPickIn`, ADR-0249)
on one vsync clock, in which the subtractive dim fades up over the battlefield
while the units slide in from the right, staggered a row at a time and
decelerating into their cells. The background receding and the cast arriving are
the same motion seen from two sides, which is why they share a clock and not just
a start.
_Avoid_: showing one unit at a time (the grid's whole contribution is that you see
everyone at once — a scroll is not a picker); asking a second time where the unit
goes; offering a unit the placement would then refuse; driving the come-in off
`delta` (this host runs uncapped at ~1,100 fps, so a delta tween finishes it in
one frame and is indistinguishable from the snap it replaces — ADR-0161);
asserting it landed and calling that a test of it (an animation that never runs
and one that completes instantly end at the same rest state, so the questions that
see the difference — `pick_animating`, `pick_dim_strength`, `pick_slide_offset_px`
— all have to be asked MID-flight).

**Roster grid over the map**:
The map-hosted Formation screen with its grid switched back on
(`build_roster_grid` / `free_roster_grid`), which is what a
[deployment picker](12-strategy-phase.md) is. It is the MAP host, not the roster
host mounted over a battlefield: only the map host answers
`paints_own_backdrop()` **false**, and the roster host's cobble floor and
pillarbox bars would cover the map you are deploying onto. Raised for the length
of a pick and torn down after, with the camera taken so the frozen tile cursor
stops competing for the d-pad.
_Avoid_: asserting it exists by asking what is SELECTED — selection reads the
injected roster by index and navigation falls through to grid-bounds stepping, so
a host with no grid at all still selects, navigates and reports a character
(`has_roster_grid` is the only question that sees the difference).

**Latch**:
The deployment pick, as the map shows it: ○ on an occupied tile lights that tile
`CellMarking.Kind.SELECTED` and leaves the real cursor free, so two tiles are lit
and the second ○ says where the first one goes (a free zone tile MOVES, an
occupied one SWAPS). It is keyed by TILE, not by unit, because every verb the
second press has is a question about tiles. A press outside the zone refuses and
**stays** latched — the second press is the one that spends the selection, so a
misfire must not cost it.
_Avoid_: calling it a *carry* (nothing is picked up, and nothing follows the
cursor); holding it as a host variable with no marking (that is state the player
cannot see); resetting it on a refusal.

**Mandatory unit**:
A unit the scenario refuses to start without — FFT's *Ramza mandatory* rule,
ATTACK.OUT **flags bit 0**, decoded into `scenarios.json` as `ramza_mandatory`.
Gariland (scenario 9) sets it. He is never placed FOR the player; instead the
field holds a **reserved slot** for him — the [squad cap](12-strategy-phase.md) as
it applies to anyone else is `max_squad_size` less the mandatory units *not yet
placed*, so Gariland is a cap of 4 until he is down and 5 after. Enforced at the
placement, with `problems()` still the commit-time backstop, and auto-fill hoists
mandatory units to the FRONT of its order so the flag holds by construction rather
than by roster order.
_Avoid_: enforcing it only at the commit (the player fills the zone and is refused
over a full field, with no indication of whom to bench); auto-placing him instead
(where he stands is a real decision the screen must not make); relying on
`CharacterCatalog.owned_units()` returning him first (true today, unenforced, and
the failure is a battle without your protagonist).

**Scenario cast**:
The two combat sides a `scenario_id` composes, spawned and **unplaced**
(`ScenarioCast`): team0 = the player's owned units ∪ the ENTD's blue slots, team1
= the ENTD's non-blue slots. One seam for both scenario-booting hosts — placement
is deliberately NOT part of it, which is the whole difference between the arena's
strategy phase, its no-strategy default placement, and the gambit host's
deployment assignment.
_Avoid_: copying it per host (that is how the retired `PartyRoster`/`EnemyRoster`
"separate combat universe" was built); folding the navigator's per-unit spawn tail
into it (it stamps `special_name`, carries HP across a walk, and hands the clock to
`SCENARIO` — those disagree on purpose).
