# Combat buffer layout

**Combat buffer layout**:
The integer-offset schema of the packed unit / gambit / ability SSBO
buffers the GPU combat engine reads and writes — field offsets, struct
sizes (`UNIT_SIZE` etc.), and the action / target / condition enums shared
between the compute shader and the GDScript that drives it.
_Avoid_: just "layout" (collides with UI layout in `ui3/`).

**Battle-state authority**:
The project-wide rule that the GPU compute pipeline is the **only** writer
of battle state — HP / MP / status, position, the unit state machine,
gambit evaluation, damage rolls, ability resolution — and the CPU is a
**snapshot consumer** that derives presentation state (animations, sound,
projectile visuals, VFX) from `get_battle_unit_states()` reads. The CPU
never holds a mutable mirror of battle state and never writes back to the
GPU buffer between ticks. Immutable reference data the GPU loaders already
packed (`AbilityDatabase` constants, sprite mappings, layout offsets) is
the one thing the CPU may read alongside the GPU — it is the same constant
read from two places, not a competing source of truth. This is the
[combat-step interpreter](02-combat-buffer-layout.md)'s read rule
generalised to every CPU consumer. See ADR-0031.
_Avoid_: a CPU manager (`projectile_manager`, an effect manager) writing
battle state via a callback — the failure mode the original ADR-0028
demonstrated, retired by ADR-0032; a "mutable mirror for performance"
cache (the snapshot is already cheap; the cache races it); inventing a
CPU latch where a GPU monotonic id (`MOVE_STEP_ID`, `CAST_STEP_ID`) would
do (the dedup pattern the interpreters already use); adding a new
battle-affecting field on a CPU manager instead of the unit struct (the
default is "extend the struct," even when the buffer grows).

**Combat-visual**:
A CPU-only presentation node that has **no GPU representation** and rides
the combat domain's pause axis — `EffectInstance`, `TrapEffect`,
`TrapChargeLineEffect`, `TrapOrbitalEffect`. The sibling rule to
**Battle-state authority**: that ADR pins the GPU side of the boundary
(battle state is shader-authoritative); this one pins the CPU side (every
presentation node that advances time on its own *belongs* to the combat
domain and freezes with it). Combat pause is **combat-scoped, not
engine-scoped** — camera, menus, future UI overlays, and the
camera-reactive subset (`CameraRelativeRenderer`'s quadrant signal,
shader-side billboarding in `effect_particle_stp.gdshaderinc` and friends)
keep running. The freeze model is a **per-member predicate**:
`should_run = victory_achieved or (combat_active and (not cinematic_manager.is_active() or member_is_on_cinematic_caster))`.
Three axes feed it — `combat_active` (spacebar pause, strategy phase),
`victory_achieved` (battle resolved), and `cinematic_manager.is_active()`
(per-cast cinematic-spell stage takeover). `combat_active` and the cinematic
axis can't be collapsed: `combat_active` also gates the GPU sim, which must
keep running during a cinematic so the cinematic's own `cinematic_caster_idx`
/ `cinematic_timer` advance. **Post-victory does not freeze** — the freeze
exists to clean the strategy-view spectacle around the cinematic spotlight or
to halt motion during pause, neither of which applies once the battle has
resolved; particles, fading charge VFX, and lingering effect playbacks finish
naturally. The mechanism is a `combat_visuals` Godot group whose members get
`process_mode = DISABLED` when the predicate is false and `INHERIT` when true
— refreshed by the `combat_active` setter, the `victory_achieved` setter, and
`CinematicManager`'s `cinematic_began` / `cinematic_ended` signals (all route
to `CombatLoop._refresh_combat_visuals_freeze`). The cinematic spotlight has
two carve-outs: (1) the cinematic `EffectInstance` itself opts out of the
group (`is_cinematic = true`), and (2) the **caster's [Charge VFX]** — a unit-
owned combat-visual parented under the cinematic caster `Unit` — also runs
through the cinematic. The second carve-out is the CPU-side mirror of the
GPU's `U_PAUSED` exemption for the caster: the GPU sets `paused=1` on every
non-caster unit during the cinematic (read by `CombatLoop._get_unit_anim_speed`)
so the caster's body pose keeps animating; charge VFX
has no GPU representation, so the freeze refresh checks group membership
against the caster Unit's children instead. Membership is a one-line opt-in:
`add_to_group("combat_visuals")` in `_ready`. Children with
`PROCESS_MODE_INHERIT` cascade for free, so per-effect subsystems do not
need to enroll separately. `Unit` is **not** a combat-visual (it owns the
camera-reactive sprite-quadrant resolution + depth/shadow marker updates
that must keep running); its animation work rides the GPU tick via the
host-pumped animation clock (ADR-0083). The strategy phase does **not** freeze:
`deploy_active` is a phase input alongside `combat_active`, so deploy marches
animate (ADR-0037 dec. 9). See ADR-0037.
_Avoid_: using `get_tree().paused` for combat pause (also halts the
camera and UI — the whole reason engine-wide pause was rejected); a
combat-visual `_process` that does not join the `combat_visuals` group
(silent failure — combat halts, the visual keeps animating, the very bug
this rule retires); duplicating `combat_active` / `victory_achieved` /
cinematic-active into a parallel `BattleClock`-style autoload (the
predicate is composed from existing sources of truth — `CombatLoop`'s
fields and `CinematicManager.is_active()` — never mirrored into a third);
freezing `combat_visuals` post-victory (the latent bug pre-this rule —
particles must finish naturally because there is no spotlight to clean
around); putting a combat-visual-style `_process(delta)` on `Unit` itself
(Unit stays alive on pause for camera-reactive work — route animation
through a `tick_based` playback driven by `CombatLoop.tick`'s pump, the
pattern the six playbacks already use).

**Charge VFX**:
A unit-owned combat-visual that depicts a unit preparing a cast — the
caster's "I am charging this ability" indicator, parented under the caster
`Unit` (`unit.add_child(effect)` in `EffectManager._spawn_charge_*`) and
tracked per-caster in `EffectManager._active_charge_effects[unit_idx]`.
Three variants today, one per **charging pose**: `TrapChargeLineEffect`
(spell lines contracting to head, pose 1), `TrapOrbitalEffect` (summon orbs,
pose 2), and a `TrapEffect` instance running a charge handler (standard
particles, poses 0/3/4/5 and Charge+N). Domain ownership is the **Unit**,
not the cast `EffectInstance` — charge VFX is hand-coded and has no
`E###.BIN` backing; it is what the unit *does while charging*, not part of
the spell's authored cinematic. This ownership is the reason a charge VFX
opts out of the freeze when its parent Unit is the cinematic caster
([Combat-visual] carve-out 2): the cinematic depicts the unit *casting*, so
the unit's own cast preparation visuals belong to the show. Spawned on the
`SPELL_CHARGING` state edge (`CombatLoop.gd:600`), wound down on exit via
`stop_charge_vfx(force=false)` → `start_fade()` (`EffectManager.gd:332`)
which leaves the effect in its `ENDING` state to drain its remaining
particles before `queue_free`. The fade itself is what the cinematic
exemption protects — without it, `start_fade` runs into the cinematic edge
and locks the effect mid-frame.
_Avoid_: spawning a charge VFX directly as a child of the viewport / map
(loses the Unit-ownership the exemption rule keys off); calling
`stop_charge_vfx(force=true)` for any reason other than replacement on
re-spawn (force-stop skips the fade, defeating the natural-resolution
guarantee post-victory and during cinematic relies on); treating a charge
VFX as part of the spell's `EffectInstance` (it is the unit's, and bundling
them re-opens the ownership question this entry settles).

**Projectile**:
The in-flight visualizer for a unit-fired physical projectile — ranged-weapon
attacks (arrow, bullet, crossbow bolt), throw abilities (`effect_anim_id == 76`:
ninja Throw, Throw Stone, Please Eat), and item-throw abilities (368–381:
Potion, Phoenix Down, etc.). **One system, one manager.** `ProjectileManager`
spawns one `Projectile3D` per fire and ticks it to landing; the visual variant
(`ARROW`, `BULLET`, `SHURIKEN`, `STONE`, `BALL`, `POTION`, `ITEM`,
`WEAPON_SPRITE`) is a spawn-time branch off the firer's weapon type / ability
id, not a separate codepath. "Throw" specifically is **not** its own
sub-system — it is a projectile variant selected when the firing ability has
`effect_anim_id == 76`. A [combat-visual](02-combat-buffer-layout.md): enrolled in the
`combat_visuals` group, so ADR-0037's four-axis predicate applies — spacebar
pause and cinematic spell freeze the projectile in flight, but **victory does
not** (ADR-0037 dec. 8, "post-victory does not freeze" — a rock mid-flight at
the moment the battle resolves still arrives; there is no strategy-view
spectacle to clean around once combat is decided). No cinematic carve-out
either — a projectile fired by a non-cinematic-caster freezes during an
opponent's cinematic; the rock is part of the battlefield the spotlight is
pausing. The firer-snapshot-driven flight model from ADR-0032 (position polled from
the firer's `U_TIMER` every frame) is **superseded** — flight progress is now
a **local countdown advanced one tick per GPU step** by
`Projectile3D.advance_tick()`, called from inside `CombatLoop`'s
`while _tick_accumulator` loop. Flight duration is still the GPU's
SEQ-authored `damage_frame - anim_frame` snapshotted at spawn, so the visual
lands at the same tick the GPU writes damage (the
`_trigger_projectile_reaction` hit heuristic keys off that). The retired
BULLET `/3` and throw/item `flight_speed_mult` special cases are **gone** —
uniform SEQ-derived timing across every projectile family is the
consistent-speed fix the user's "speed feels weird" symptom asked for. The
firer's `LOGICAL_ACTIVITY_AWAITING_IMPACT` state machine and timer-zero
damage write from ADR-0032 are unchanged — the GPU still owns *when damage
applies*; the projectile is *the moving picture* of that flight, advanced
in lockstep. **Death-resilient.** While the target Node is alive, `end_pos` updates each
tick from `target_node.global_position`; once the Node becomes invalid,
`end_pos` sticks at its last seen value so the projectile completes flight to
the target's death-tile. The firer's death never cancels the flight either —
the local countdown is independent of firer state, so the projectile flies on
through. Neither death cancels the landing — `projectile_landed` still emits
for hit VFX / sound (no damage write either way; damage is GPU-authored at
`AWAITING_IMPACT` timer-zero per ADR-0032 / 0031). Sitting-in-the-air or
teleport-to-target on death are bugs, not policies. **Spin / tumble is
PSX-faithful per family.** `STONE_TUMBLE_X_RATE` / `STONE_TUMBLE_Y_RATE` already
cite their PSX constants (256/4096·τ·½ per tick, halved for 60→30 fps);
`WEAPON_SPRITE` / `ITEM` spin is currently a debug knob
(`ProjectileDebugPanel.spin_deg_per_tick`) and is an **open RE follow-up** to
reach the same parity. Spin and tumble advance per-frame (driven by the combat-visual
`Projectile3D._process(delta)` — flight position advances per GPU tick via
`advance_tick()`), so the ADR-0037 freeze halts spin uniformly on every axis;
position freezes naturally when `CombatLoop`'s tick loop short-circuits on
`combat_active = false`.
_Avoid_: treating "Throw" as a separate system from ranged-weapon projectiles
(one `ProjectileManager`, variant-branched at spawn — the unifying view
ADR-0032 already implied; introducing a parallel `ThrowManager` re-opens the
ownership question this entry settles); polling the firer's GPU snapshot every
frame for position (the ADR-0032 shape — flight is now driven by a local
countdown advanced one tick at a time, so the snapshot poll is a leftover
that re-introduces the "sits-in-the-air on firer death" bug); driving flight
position from `Projectile3D._process(delta)` instead of `advance_tick()`
(loses tick-lock with the GPU damage tick at `Engine.time_scale > 1` —
visuals lag by the time-scale's worth of ticks per Godot frame, breaking the
`_trigger_projectile_reaction` hit heuristic the way the test harness'
4.0x scale exposed); writing damage on `projectile_landed`
(the [Battle-state authority](02-combat-buffer-layout.md) line — damage stays GPU /
ADR-0032); per-family flight-speed knobs that diverge from the GPU's authored
timing (the retired BULLET `/3` and throw/item `flight_speed_mult` shape —
both desynced visual landing from `_last_damage_tick`); spawning a projectile
outside the `combat_visuals` group (the bug shape pre-this entry — cinematic
didn't freeze spin at all); reading the per-tick `spin_deg_per_tick` debug
knob from a non-debug codepath after the PSX-authentic constant lands (the
knob is the pre-RE placeholder, not the destination).

**Unit encode schema**:
The single declarative table (`UNIT_CONFIG_SCHEMA` in
`GPUCombatPacker.gd`) that maps a live `Unit` into the combat buffer
layout. One row per config-derived field, carrying its `unit_config`
string key, its `UnitField` offset, a default, an `extract` Callable
(or null), and a `live` flag. Both the producer (`_extract_unit_config`)
and the consumer (`_write_unit_data`) loop this one table, so a field's
key / offset / default exist in exactly one place and cannot drift.
"Two-sided" here means that **encode path** (Unit → dict → buffer:
producer and consumer share the table), **not** encode-vs-decode — the
*decode* side (`SNAPSHOT_FIELDS`) is a separate, **generated** table
(`gen_gpu_layout.py`, from the shader `UnitField` enum, ADR-0001), so it
already covers every named field and the encode↔decode axis cannot drift
by construction. `live` marks fields the production path is expected to
supply today (stats, equipped reaction ability); a `live` row with no
extractor is a tracked gap the schema check reports, never a silent
default. Covers only the simple config-derived fields — init-constants
(`STATE = 0`, the `DBG_*` block) and the status-timer bit-packer stay
hand-written, having no producer to drift against. A second net,
`unit_buffer_coverage_problems()`, asserts `_write_unit_data` writes
**every** offset in `[0, UNIT_SIZE)` (schema rows plus those hand-written
fields), so an enum field with no writer is a boot error, not a silent
zero — the unit analogue of the gambit completeness check. See ADR-0003.
Since ADR-0235 each row also carries a **field behaviour** (below), so the
schema answers not only "where does this value go" but "what happens to the
value already there".
_Avoid_: "unit config" alone (ambiguous with the per-call dict passed to
`set_battle_units`); calling this the encode↔decode drift-killer (that
axis is closed by `SNAPSHOT_FIELDS` generation, not by this table).

**Field behaviour**:
What `reconfigure` does to one unit field, declared per **Unit encode
schema** row as `recompute` | `clamp` | `carry` (ADR-0235). `recompute`
rebuilds the value from the new config; `clamp` keeps the live value and
clamps it to the freshly recomputed ceiling its row names in `clamp_to`
(`hp` to `max_hp`, `mp` to `max_mp`) — clamp, **never scale**; `carry`
leaves the live value untouched. Every one of the 57 offsets with no
schema row is `carry` implicitly. A row that declares nothing is a boot
error, not a `recompute` default: a config-derived field that forgot to
answer would silently reset on the player's first job change. The floor
is not editorial — a field the shader itself writes is live state, so
`overlay_behaviour_problems()` scans `write_unit()` call sites out of
`src/gpu/shaders/` and errors on any of them classified `recompute`.
_Avoid_: "live vs config-derived" as a two-way split for this purpose
(`hp`, `pos_*`, `wp` are both — config-derived at boot, live mid-battle,
which is exactly why the column has three values and not two).

**Reconfigure** (of a live unit):
Applying a job / equipment / ability-slot change to a unit that is
**already fighting** — `GPUBatchSimulator.reconfigure_unit`, an overlay of
the config-derived offsets onto the live block, honouring each field's
**field behaviour** (ADR-0235). Explicitly *not* a round trip: nothing in
the tree reads a config back out of the buffer. Explicitly *not*
`set_battle_units`, whose whole-block write resets all 56 live offsets to
their init constants — correct out of combat, where nothing is live, and
destructive mid-battle.
_Avoid_: "state ⇄ config round-trip" (names a loop with no return leg);
"restore" for this (that is the **Battle snapshot** primitive, a different
thing with a different correctness criterion).

**Battle snapshot**:
Everything that determines one battle's future, captured as four slices —
the battle slice (header + unit blocks), the single-buffered cooldown
SSBO, the gambit SSBO, and the 4-int result record (ADR-0235).
`snapshot_battle` / `restore_battle` on `GPUBatchSimulator`; `restore`
takes a **target** battle id, so a snapshot of one battle can be installed
into another (the shape a rollout fork needs). Only the *current*
ping-pong half is captured and `restore` writes it into **both**: the
kernel opens every tick by copying the read half's whole record forward,
so the other half carries nothing into the future, and keeping the
batch-global ping-pong cursor out of a per-battle artifact is what makes a
restore safe while other battles are running. There is no RNG stream to
capture — `rand_int` is a stateless hash of `(battle_seed, unit_id,
tick)`, both of which live in the captured header.
_Avoid_: calling it a save (it is bytes, not a serialised game state);
assuming it captures a tick cursor shared with other battles.

**Turn meter**:
A unit's progress toward its next **reconfiguration turn**, held in the
GPU unit block as `U_TURN_METER` and advanced by the kernel by
`max(1, Speed)` every tick (ADR-0236). At `TURN_METER_FULL` (3600) the unit
is READY and stops accumulating, so readiness is a comparison on this one
field rather than a companion flag; the host subtracts `TURN_METER_FULL`
when the turn is taken and CARRIES the overshoot. Its width is not a free
parameter — it is the **dwell** times Speed (ADR-0260). The kernel writes it and never reads
it — no combat rule branches on it — so it exists on the GPU to
round-trip inside a **Battle snapshot**, to be correct inside a rollout,
and to be visible to the value function. Only death stops it: not
`U_PAUSED`, not casting, not any activity.
_Avoid_: **CT** for this in code. FFT spells both this and an ability's
charge time CT, and this kernel already spends that spelling on the
second one (`AB_CHARGE_TIME`, `U_CAST_TIMER`, `AbilityView.ct`). The
on-screen LABEL stays "CT", which is a different question; `ct` in a UI
view dict is that label's row key, not this term. Also avoid "turn
charge" (`charge` is the cast-time word) and "turn timer" (every `*_TIMER`
in the unit block counts DOWN; this counts up).

**Dwell**:
How long a unit's **gambit list** stays committed before its next
**reconfiguration turn** re-opens it — the quantity `TURN_METER_FULL`
actually sets, and the reason the meter has the width it has (ADR-0260).
Measured in **ability cooldowns**, not seconds: every ability shares a
300-tick cooldown, so a unit's config can only be judged over the actions
it takes under it, and the dwell is **two of them (600 ticks)**. A dwell
shorter than the thing it governs is the defect it names: a config
re-tunable faster than it can express itself makes the turn meaningless.
_Avoid_: reading it as an action budget ("how often a unit acts") — that
is what a turn is NOT here; and conflating it with **stops per battle**,
which is dwell divided by the living roster and therefore falls with
attrition, not a thing this number sets.

**Turn queue**:
Who acts next and when, projected from the current **turn meter** values
alone — `TurnQueue` (`src/gpu/TurnQueue.gd`), pure statics, no
`RenderingDevice` and no simulation (ADR-0236). Because the gain per tick
and the ceiling are both fixed, the whole queue is closed-form, which is
what lets the forecast be shown **one full round-robin deep**: extended
until every living unit appears at least once, so a slow unit's long wait
is visible as the pile of faster turns in front of it. Order is meter
descending (a larger overshoot crossed the line earlier), then team, then
unit index — nothing random, because the enemy AI replays these positions
inside its rollouts.
_Avoid_: calling a forecast entry a prediction of what a unit will DO
(it says only when it will be asked); treating the queue as exact under
Haste/Slow, deaths or reinforcements, the caveat every turn-queue game
carries.

**Turn queue strip**:
The **turn queue** on screen — `TurnQueueHud` (`src/ui3/TurnQueueHud.gd`),
a row of portrait cards across the top of the battlefield, head on the
left. One card is one TURN and not one unit: a fast unit legitimately
appears more than once in the same round-robin, and the pile of cards
standing in front of a slow one is exactly how its long wait is shown.
The two teams face each other — an enemy card is mirrored, the roster's
own convention — so which side is about to act reads without a label. It
reads the **turn director** and writes nothing, and redraws only when the
order actually moves.
_Avoid_: "turn order bar" (nothing fills and nothing is a meter); calling
a repeated card a duplicate; treating a card as a selector — a card is
information, and the unit you may command is the **taker**.

**Rollout fleet**:
The `K × M` battles the enemy AI runs beside the live one to choose its
gambit edit — `K` candidate edits × `M` common-random-number seeds — every
one of them a **battle snapshot** of the live battle installed into a
neighbouring slot of the *same* `GPUBatchSimulator` batch. Nothing about it
is a second simulator: `_run_tick` already dispatches over every battle in
one compute list, which is why the fleet is nearly free (ADR-0237) — 1024
battles cost 1.41× what one does. Sized at `initialize(…, num_battles, …)`,
which `CombatLoop` still calls with **1**.
_Avoid_: "batch" for it (that is the whole simulator's population, which
includes the live battle); calling a fleet slot a copy of the live battle
after the first tick — it is a fork, and the CRN seed rewrite is what makes
it a different one.

**Thinking beat**:
The enemy turn's cinematic focus pause, and the wall-clock budget the
**rollout fleet** must fit inside. Exactly three legs, and the vocabulary
names them because they price differently: **fill** (installing the snapshot
into every slot), **run** (one `step_tick(H)` carrying the whole fleet `H`
ticks), **score** (reading the fleet back for the value function). At the
Gariland shape the beat is ~65 ms fresh and ~125 ms forked from a mid-battle
position (ADR-0237).
_Avoid_: treating the beat as the run leg alone — score can equal it, and
does the moment a scorer reads unit blocks per battle instead of the result
buffer in bulk.

**Rollout horizon**:
`H`, how many ticks each fleet battle is carried forward before it is scored
— 400 ticks since #897, which is about 6.7 seconds of battle at `CombatLoop`'s
60 ticks/sec (§7's starting shape measured 300; ADR-0253's **knee** chose 400
and ADR-0256 dec. 7 publishes it as `rollout.horizon`).
The **only** budget term whose cost is superlinear: a tick late in a battle
costs several times an opening one, so doubling `H` more than doubles the
beat (ADR-0237). `H` and the value function `f` are substitutes — every tick
simulated is a tick not predicted — so they are one joint choice, not two.
_Avoid_: shortening `H` as a way to make a beat fit; it biases the AI toward
immediate damage, where dropping `K` or `M` only adds noise.

**Fork age**:
How far into the live battle a **rollout fleet** was forked — the tick count
of the position the snapshot was taken at. Not a stored field; a property of
*when* the AI is asked. It matters because rollout cost rises with it: a
fleet forked from a fresh battle runs at about half the cost of one forked
600 ticks in, since by then units are engaged and dying rather than walking
(ADR-0237). Any budget quoted without one is quoting a floor.
_Avoid_: reading a cost measured from a fresh battle as the expected cost of
a real turn.

**Turn director**:
The component that stops the world at a turn, hands it off, and starts it
again — `src/gpu/TurnDirector.gd`, mounted on a `CombatLoop` and on no host,
so `GambitBattle`, `NavigatorMain` and a bare-loop test all get the same one
(ADR-0239). It **gates and never pumps**: `CombatLoop.tick()` is the single
pump and `combat_active` the single freeze, so the director drives those
rather than owning a clock of its own. It also makes no judgement about
sides — it announces which unit is up and lets its host decide what that
means, because team 0 holds guests as well as the player's own units.
It does not decide whether a turn is worth stopping for — that is the
**stop policy**, which its host sets.
_Avoid_: "GambitTurnDirector" (the design's working name — it directs turns;
the gambit-specific parts mount *on* it); calling it an orchestrator or a
controller of the loop (it neither drives ticks nor owns battle state);
confusing it with `ScenarioDirectorState`, which is the scenario director's
question-answering surface and a different domain.

**Stop policy**:
Whether an open turn stops the world, or is spent where it opens —
`TurnDirector.stops_the_world` (ADR-0245). WAIT, the default, is the played
battle: the world freezes and somebody takes the turn. The non-stopping one is
the walk's: `NavigatorMain`'s battle is a spectacle nobody plays, so its turns
are announced and spent inside the same call, cost **zero ticks**, and take no
snapshot — nothing can cancel a turn nobody holds. It is a stop policy and not
an off switch: turns are still ordered and still SPENT, which is what keeps the
meters moving and the [turn queue strip](02-combat-buffer-layout.md) meaningful.
An undirected battle is the degenerate case — the kernel stops advancing a
crossed meter, so every unit sits permanently ready and the forecast reads
"everyone, now" forever.
_Avoid_: calling the non-stopping policy **active mode** (design S3's active
mode is a larger thing — a shot clock, a player free to interject; this is only
the stop); "auto-commit" (nothing commits, because nothing ever froze).

**Taker**:
The unit whose turn is open. Not "the active unit" and not "the current
unit": a turn is a *reconfiguration*, and everyone else is still fighting
through it. `TurnQueue.forecast` already spells it this way, which is why the
word was adopted rather than invented. There is exactly one at a time, or
none — **deployment** is the turn with no taker, and under a non-stopping
[stop policy](02-combat-buffer-layout.md) a taker exists only for the length of
its own announcement.
_Avoid_: assuming the taker is the only unit doing anything (combat is
simultaneous; only the CLOCK stopped); reading a taker as player-controlled.

**Commandable unit**:
A unit the player may steer on its turn. The [turn director](02-combat-buffer-layout.md)
deliberately never answers this — it announces the [taker](02-combat-buffer-layout.md)
and nothing else, because team0 holds **guests** — so the HOST answers, and its
answer is the [deployment assignment](12-strategy-phase.md): the units you deployed
are the units you command. A guest (Delita at Gariland, ENTD-blue on team0) fights
beside you and takes no orders; its turn is spent unchanged.
_Avoid_: equating it with team 0 (that hands guests to the player); reading it off
the ENTD's `is_player_controlled` (a second source of truth for a question the
deployment already answered).

**Between-turn stretch**:
The run of ticks from one commit to the next freeze — the part of the battle
you actually watch, and the only part where the consequences of a gambit edit
become visible. Its length is a **fixed number of ticks**, set by whoever
crosses the meter next, so it is a property of the position and not of the
frame rate.
_Avoid_: making it instantaneous (skipping it severs the feedback loop the
whole mode is built on); describing it in seconds — seconds are what the
**playback rate** buys, ticks are what it is.

**Turn gate**:
The per-tick predicate `CombatLoop` consults at the end of each tick-loop
iteration; returning true breaks the frame's tick loop where it stands. It is
what makes the freeze land on the **exact tick** a unit crosses instead of at
the next frame boundary — a frame drains ~16 ticks and a turn is ~13, so a
frame-granular stop overruns a whole turn (ADR-0239). The loop supplies the
hook and the granularity; the policy belongs to whoever installed it, which
is why Active mode is a change inside the predicate rather than a rewrite.
_Avoid_: giving the gate its own GPU read (its inputs ride the one
version-cached column read `_read_tick_columns` already performs); putting
turn policy in `CombatLoop`; forgetting the dead filter — the kernel freezes
a dead unit's meter, so a corpse that died at full would trip an unfiltered
gate forever.

**Playback rate**:
How fast the **between-turn stretch** plays — a viewing rate, never a
simulation rate. An ADR-0068 `static var` on the **turn director**, forwarded
into `CombatLoop.playback_scale`, which multiplies the delta fed to the
fixed-step accumulator. Because the stretch's length in ticks is fixed and
the stop is exact-tick, no rate can change an outcome; it changes only how
long you spend watching.
_Avoid_: `Engine.time_scale` (engine-scoped, and the test harness already
owns it); calling it a game speed or a time scale — it is scoped to the
stretch, and combat inside a slice is unaffected; treating a rate change as
something that could desync a rollout.

**Gambit encode schema**:
The gambit-side analogue of the **Unit encode schema** — the looped
`GAMBIT_CONFIG_SCHEMA` (`GPUCombatPacker.gd`) that maps an encoded gambit
into the gambit buffer layout. One `{key, field, default}` row per *flat*
field (`enabled`, `cond_target_type`, `action_type`, `action_id`,
`action_target_type`), written by `_pack_gambits` as
`int(g.get(key, default))`. A `const`, not a `static var` — the rows carry no
`extract` Callable, because the value is always a plain read from the dict
`GambitEncoder` already produced. The same separating line ADR-0003 drew holds:
the derived `COND_COUNT` and the repeated `COND_TYPE_*/COND_VAL_*` condition
block stay **hand-packed** in `_pack_gambits`, not in the schema. Two
deliberate differences from the unit schema: (1) it is a **write-side** schema
only — `GambitEncoder` is branchy and cannot loop a table, so the
encoder-keys↔schema-keys drift is *not* auto-closed (a write-side win, not the
producer-and-consumer single-sourcing the unit schema gets — see its entry);
(2) its completeness check (`gambit_config_schema_problems`) can be **pure and
static** — it asserts every offset in `[0, GAMBIT_SIZE)` is written exactly
once, via schema / `_GAMBIT_HAND_PACKED` / `_GAMBIT_RESERVED`, reasoning over
declared lists because the dense gambit buffer's non-schema writes are already a
small declarative block. The unit buffer earns the same completeness guarantee
(`unit_buffer_coverage_problems`) but verifies it **dynamically** (sentinel-fill
a probe, write, check nothing kept the sentinel), because its non-schema writes
are scattered imperative init and a parallel offset list would be new drift. Packing is pure (no `RenderingDevice`); `set_unit_gambits` is
`_pack_gambits` + upload, mirroring `_write_unit_data` + upload. See ADR-0016.
_Avoid_: hand-writing a new `GambitField` offset in `_pack_gambits` instead of
adding a schema row (the boot completeness check will flag an *unwritten*
field, but a hand-write bypasses the single-source-of-truth the schema buys);
folding the condition block into the schema (the structured-packer exclusion
is the ADR-0003 line, not an oversight).

**Gambit→GPU projection**:
The **producer** side of the gambit encoding — `GambitEncoder` (`src/gpu`)
mapping a `Gambit` domain object (its `TargetSelector` / `GambitCondition`
graph) into the flat config dict the **Gambit encode schema** then writes to
the buffer. It is the adapter between the `Gambit` domain and the
shader-authoritative GPU vocabulary, and it lives in `src/gpu` — **not** on the
domain objects (`src/data` stays GPU-agnostic; that would be the first
`src/data → GPUConstants` dependency) and **not** in a standalone `GambitCodec`
(a one-adapter hypothetical seam — a rename, not depth). **Faithful-or-explicit**:
it either maps a domain value correctly or treats it as `UNSUPPORTED` — never
silently substitutes. The declared `UNSUPPORTED` set names every
`GambitCondition.Type` / `TargetSelector.PoolType` / `ResolutionStrategy` value
with no faithful GPU mapping; an unsupported gambit is **skipped + `push_error`**
(the unit falls through to its remaining gambits), and a pure `src/gpu`
completeness test asserts every domain enum value is mapped or in `UNSUPPORTED`
— the producer-side complement to the **Gambit encode schema**'s buffer-coverage
check. `UIGambitEditor` exposes a **superset** of the mapped vocabulary, so the
`UNSUPPORTED` set is also the editor↔engine gap list. See ADR-0023 (and ADR-0016
for the consumer/write side).
_Avoid_: a silent `NEAREST`/`ALWAYS` fallback for an unmapped value (the
meaning-inversion ADR-0023 retired — `ENEMY_IN_RANGE` silently becoming
`ALWAYS`); moving the projection onto `TargetSelector` / `GambitCondition` (the
layering inversion ADR-0023 rejected); extracting a `GambitCodec` (one GPU
target — a rename, not a seam); feeding the encoder a string-keyed dict (that
input path was deleted — the live input is `Gambit` objects).

**KO**:
The condition a unit is in when it is **down on the field but still on it** — the state a
revive answers. The kernel's authority for it is `FLAG_DEAD`, a bit in the unit's flag word
set by `kill_unit` and read by `is_unit_dead()`; the gambit condition that asks about it is
`GambitCondition.is_ko()` → `COND_IS_DEAD`. **KO is not `STATUS_DEAD`.** `STATUS_DEAD` is
status **bit 0**, a different word, and nothing in the tree sets or reads it — so
`HAS_STATUS(&"dead")` is a well-formed, guard-passing, permanently false condition. The two
are kept as separate words precisely because they read as synonyms and are not: one is a
*condition derived from the flag word*, the other a *declared status bit*. Naming the kernel
constant `FLAG_DEAD` and the domain condition `KO` is deliberate — the GPU constant is
generated from the shader and keeps its spelling; the word the domain uses is KO.
_Avoid_: "dead" as the domain word (it collides with the hollow status bit, which is exactly
the confusion that made the obvious revive gambit encode cleanly and never fire); "HP ≤ 0" as
the definition (`is_unit_dead` reads the flag, not the HP field, and `kill_unit` writes both).

**KO-inclusive pool**:
A gambit **target pool that admits KO'd candidates**. Every other pool is KO-*blind*:
`find_unit_by_criteria` and `find_nth_nearest` drop `is_unit_dead` units before any condition
runs, so a **KO** condition over an ordinary ally pool is decidable and unreachable — the
corpse never becomes a candidate. Authored as `TargetSelector.friendlies_or_ko()`
(`include_ko`), projected to the single GPU target type `TARGET_NEAREST_ALLY_OR_KO`.
The pool is deliberately KO-**inclusive** rather than KO-**only**: the pool decides *who may
be looked at* and the condition decides *what must be true*, so `IS_KO` / `IS_ALIVE` stay the
thing that discriminates. It sits in the pass-2 rank walk because the nearest ally is usually
standing — without the walk a revive gambit would fire only when the corpse happened to be
closest. `include_ko` anywhere with no GPU spelling (an enemy pool, `MOST_CRITICAL`, `SELF`,
`TRIGGERING`, and since ADR-0285 `NEAREST_ONLY` — there is no
`TARGET_NEAREST_ALLY_OR_KO_ONLY`) is UNSUPPORTED under **Gambit→GPU projection**, never
demoted to its KO-blind cousin.
_Avoid_: a KO-only pool (it moves deadness into the target type and leaves both conditions
vacuous); reading "the pool filters the dead" as a bug — it is the correct default for every
other gambit, and the KO-inclusive pool is the opt-in; **treating `FLAG_DEAD` as the whole
membership test** — it also marks the battle's **unfilled slots**, so a KO-inclusive pool needs
`is_unit_slot_filled` on top of it (ADR-0293 dec. 8).

**Unfilled slot**:
A **unit slot the roster did not reach**. `set_battle_units` packs team 0 then team 1 into the
low slots of an 8-slot battle and marks the remainder `FLAG_DEAD` + `HP 0`, leaving the rest of
the record zeroed — `U_TEAM` included, so they all read as **team 0**. They are not units: no
name, no stats, standing at tile (0, 0). The packer's comment calls this *"prevents ghost units
from interfering with target selection"*, and it did, for exactly as long as every pool filtered
the dead. A **KO-inclusive pool** is the first one that does not, and it ranks them by path cost
like anything else — so from a tile near the corner a phantom beats the real corpse and a
`KO'd?` slot fires at a non-unit before anyone has died. The discriminator is `U_MAX_HP > 0`
(`is_unit_slot_filled`): the packer writes a maximum for every real unit and zeroes every empty
slot.
_Avoid_: "dead slot" as the name (it is the collision this word exists to break — an unfilled
slot is not **KO**, and the difference is invisible to `FLAG_DEAD`); giving padding a sentinel
`U_TEAM` instead (an enemy pool tests `team != my_team`, so any sentinel reads as *enemy* and
every enemy-side search would admit all of them).

**Revive**:
The act of **undoing KO** — the HP write that clears `FLAG_DEAD` and puts the unit back into
gambit evaluation. The kernel has exactly one: `revive_unit`. Two things reach it, and they
differ in where the HP comes from: a **cast** of an ability whose ROM inflict list names `Dead`
under mode `cancel` (Raise, Raise2, Revive, Oink, Phoenix Down — the whole permission, read off
`AB_INFLICT_MASK` / `AB_INFLICT_MODE`, with no `ABFLAG_` for it), which restores the ability's
own formula; and **RERAISE**, the timer-driven auto-revive off a lethal-damage capture, which
has no ability to read a formula from and so hard-codes `max_hp / RERAISE_HP_DIVISOR`.
_Avoid_: "resurrect" / "raise" as the domain word (Raise is one ability of five, and Reraise is
a *status* that triggers a revive — three near-homographs in one area); "heal the corpse" (a
heal writes HP, and HP is not what `is_unit_dead` reads — writing HP at a corpse leaves it dead,
which is the half-fix the `revived` predicate is written to catch); reading a positive `hp_event`
as evidence one happened.

**Tile distance**:
The **planar grid separation** between two units — `manhattan_distance`, `|dx| + |dz|`,
level-blind and wall-blind — which is FFT's own range metric and what the `TARGET_DISTANCE`
condition (`COND_DISTANCE_LESS` / `COND_DISTANCE_GREATER`) compares its threshold against.
It is one of **three distances the kernel keeps apart on purpose**, and they disagree:
- **Tile distance** — raw geometry. What an author means by "enemy within 3 tiles."
- **Path cost** — `get_distance` over the precomputed level-aware distance field. What ranks
  a `NEAREST` pool, and `-1` when a candidate is unreachable at all.
- **Action reach** — `target_in_action_range`. Whether *this slot's own action* would land,
  which folds in the ability's range, its vertical bound, and the equipped weapon.
A wall between two adjacent tiles leaves them 1 apart by tile distance, far apart by path
cost, and out of range by action reach.
_Avoid_: calling the `NEAREST` resolution "nearest by Manhattan" (it is path cost — the
`TargetSelector` docstring and gambit-rule C1 both said Manhattan and both were wrong);
giving `TARGET_DISTANCE` a level term (vertical is priced per-ability by action reach, which
is a different question).

**Move (the movement command)**:
The single movement action a gambit can take (`ActionKind.MOVE`). There is **one**
move verb. Movement *intent* — "approach", "retreat", "regroup", "relocate" — is
**composed by the player** from a target + conditions; the engine does **not** bless
these as named commands. "Retreat" especially has no single referent (a corner? a
near ally? a far ally? away from the nearest enemy?), so it is deliberately *not*
encodable as one command — the player picks the target that means retreat to them.
The move's target carries a **destination anchor — unit or tile**, the axis the
gambit vocabulary previously lacked (every other action targets a unit; movement
also needs to target a tile):
- **Unit-anchored** — the move chases a unit the existing **unit target**
  (`TargetSelector`) resolves; it re-paths each tick as the unit relocates and stops
  adjacent. E.g. "move to nearest enemy" (the move-and-don't-swing of *approach*).
- **Tile-anchored** — the move heads for an absolute map tile `(x, z)` (the
  "command this unit to that tile" case); the only tile target, already wired via
  `ACTION_MOVE_TO` (`action_id` packs `x*256 + z`).

There is deliberately **no relational tile selector** (e.g. *farthest-from-enemy*)
and **no threat-aware flee primitive** — that would need a battlefield/distance-field
scan that does not exist, and it is exactly the over-broad "retreat" the model
refuses to pin. Such a primitive is an explicit future option, not a planned phase. See ADR-0062.
_Avoid_: naming *Approach* / *Retreat* as first-class `ActionKind`s or editor verbs
(they are player-composed target patterns over the one `MOVE`); assuming "retreat"
has a canonical encoding; "move gambit" without saying which anchor.

**Ability cooldown**:
A per-ability minimum interval between successive uses, **universal across every
ability** but typically subsumed by other rate-limiters (charge time, projectile
flight, AoE caster-lock). Lives as a `cooldown_ticks` field on the ability
record, alongside `mp_cost` and `ct` — the parser writes it at extraction time
(default **300 ticks**, i.e. 5 seconds at 60 Hz; safe globally because the timer
counts from *commit*, so a CT-bearing ability is still charging when it expires
and only CT=0 abilities feel the floor). FFT itself
has no cooldown concept; the original game's turn-based clock rate-limited every
action implicitly. Real-time evaluation breaks that floor for CT=0 abilities
(Knight Skills, Punch Art, Draw Out, Geomancy) — the cooldown is the new
shared-shape floor that fills the gap. The field shape supports per-ability
overrides today; data starts uniform and grows differentiated as balance work
surfaces specific abilities. Veto fires the same shape as the MP-cost veto (B3
in [`gambit-rules.md`](../gambit-rules.md)): a `cooldown_pre_validate` in
`stage_compute.glsl` reads `ability.cooldown_ticks` and the per-unit
`cooldown_ready_at[ability_id]`, falls through if `tick < ready_at`. State is a
flat `MAX_COOLDOWN_ABILITIES = 128`-wide int array in its **own SSBO** (binding
9), indexed `[unit_global_idx * 128 + ability_id]` — deliberately *not* on the
unit struct, which `copy_unit_to_next` walks every tick per unit. `action_id` is
the right granularity (same ability in two gambit slots shares one cooldown), and
an `ability_id` at or above 128 (summons, cinematic spells) skips the floor. Timer starts at **commit-time**, same place MP gets
deducted; cooldown stays set if the action is interrupted mid-flight — same
fire-and-forget model as MP, no refund-on-failure. See ADR-0047.
_Avoid_: a runtime `is_cooldown_class` predicate (collapsed — `cooldown_ticks > 0`
is class membership; the GPU never asks "is this cooldown-class," it just reads
the number); per-gambit-slot timers (would let "same ability in two slots"
double-spam — cooldown must key off `action_id`); refunding cooldown when an
action is interrupted (no refund machinery, matches the MP-cost model); seeding
cooldown values from ROM bytes (no such bytes exist; cooldown is a new
game-design dimension, the parser carries the default as a hand-authored
constant in the family of `tools/_fft_decode.py`'s `ELEMENTS`); rate-limiting
abilities via a separate global GCD across the unit (the floor is **per-ability**
so that an unrelated cooldown doesn't gate Holy Sword behind a just-fired
Potion).

**Safety-net gambit**:
An invisible system-injected gambit slot, the same shape for every unit —
`ATTACK + NEAREST_ENEMY + ALWAYS` — that guarantees a unit's gambit pass always
has at least one terminal candidate before falling off the end. Appended at the
encoder boundary inside [GambitEncoder](02-combat-buffer-layout.md) as buffer slot 5
after the 5 user-authored slots, bumping `MAX_GAMBITS` from 5 to 6. The domain
(`Gambit`, `GambitList`, the UI editor) **stays unaware of it** — the safety net
is purely a buffer-layout concern; UI shows 5 slots, the buffer holds 6, the
authored 5-slot contract is unchanged. Composes with the existing fall-through
machinery: rule A1 ("lower slots eval first") makes the safety net the last try;
B1 / B2 / B6 still fire — the safety net itself can fail (no enemies →
`NEAREST_ENEMY` resolves to no candidate → fall through past it → unit IDLEs,
the desired post-victory terminal state). No new runtime event or observability
hook — "this unit always hits the safety net" is a [Gambit scenario
suite](02-combat-buffer-layout.md) concern, not a runtime alert. See ADR-0048.
_Avoid_: exposing the safety-net slot in the UI gambit editor (it is *not* an
authorial slot — making it visible re-invites players to delete or override it,
defeating the always-terminates guarantee); putting the safety net on the
`Gambit` domain object or `GambitList` (the encoder boundary is where buffer
concerns live; pushing it into the domain would let UI / editor / persistence
code accidentally serialize it and leaks the 5-slot authoring contract);
per-unit or per-job safety-net customization (every unit gets the same shape —
if a Chemist eventually needs different fallback behavior, that is a future
design conversation, not a per-unit knob today); emitting a "safety net fired"
signal (rejected — the scenario suite catches the regression case via
`no_safety_net_hit`-style liveness predicates; a runtime event would mostly be
noise).

**Gambit scenario suite**:
The spec-driven behavioral test suite for the gambit system — every rule the
GPU evaluator is *supposed* to follow, written down and exercised end-to-end.
Lives in `tests/gambit_scenarios/` (one file per rule group: `scenarios_A_*`
through `scenarios_J_*`), aggregated by one runner scene
(`tests/GambitScenarioRunnerTest.tscn`) that posts a single PASS/FAIL line to
`run_all_tests.sh` while logging per-scenario detail. Authoritative rule list:
[`docs/gambit-rules.md`](../gambit-rules.md). Scenarios are
**declarative** — a dict per scenario carrying `rule:`, `map:`, `units:` (with
**real `Gambit` objects** that go through [Gambit→GPU
projection](02-combat-buffer-layout.md) and the [Gambit encode
schema](02-combat-buffer-layout.md), not flat config dicts the existing
`make_attack_gambit()` helpers produce) and an `expect:` block. Real ROM-
derived maps only (a small canonical set — `MapComposer.change_map(...)` once
per map group); no synthetic terrain shims (the production
`TerrainIndex` + `DistanceFieldGenerator` + `Tile` reservation pipeline is too
coupled to recreate cheaply, and the ~125 real maps already cover every
terrain shape worth testing). Expectations mix three forms: **outcome**
(`winner == 0`, final HP), **trace** (`by_tick(50): unit.committed(action)`),
and **liveness** predicates (`no_stuck(unit, max_idle_ticks=10, given='any
enemy alive')`, `no_thrash(window=20, max_changes=4)`) — the third form is
what catches the user-reported pain points (Monk Secret Fist out-of-range
loop, terrain-induced thrash, pass-through "in the way" stalls) that pure
outcome assertions miss. Verdict taxonomy is six-state: `PASS` / `FAIL` /
`XFAIL` (named expectation expected to fail today — the bug-driven scenarios
start here) / `XPASS` (an `xfail` expectation passed — flip it off, loud-but-
green by default) / `ERROR` (setup crashed) / `NORAN` (sim never advanced; the
"did the test actually run" sentinel — checks `current_tick > 0`, every unit
encoded successfully, ≥1 gambit eval recorded). `xfail:` is a list of
*specific* expectation names plus an `xfail_reason:` pointing at the issue —
not a blanket per-scenario marker, so a different expectation regressing
still reports `FAIL`.
_Avoid_: synthesizing maps from ASCII (rebuilds `TerrainIndex` /
`DistanceFieldGenerator` / `Tile` reservation that already work — the [Prefer
real inputs over test shims](#TBD) rule); authoring scenarios with the flat-
dict shape the existing `make_attack_gambit()` helpers produce (bypasses
`GambitEncoder`, hides editor↔engine drift — the whole point of going end-to-
end); locking in current shader behavior as the spec (the bug-driven
scenarios are `XFAIL` until fixed; a snapshot suite would pin the bug); using
`xfail` as a per-scenario marker rather than naming the expectations expected
to fail (loses the regression signal when a *different* expectation breaks);
adding gambit scenarios as new entries to `run_all_tests.sh` (the runner
aggregates them under one entry — shard only when the suite outgrows the
360s timeout).

**Movement Logical activity**:
A Logical activity in which the unit is **between tiles** — one whose logical
position (`U_POS_X`/`U_POS_Z`) is the **destination** of a step rather than
where the sprite is. Four of them: `WALKING`, `WALKING_TO_CAST`, `APPROACHING`,
`RETREATING`. They are exactly the `tools/activity_taxonomy.yaml` rows whose
`routing:` is `visualizer`, and that is a definition rather than a coincidence:
that routing says *the move visualizer authors this row's body activity*, which
is true of a row precisely when the unit is mid-step. So the set is **derived,
never listed on the host** — the generator emits
`GPUConstants.LOGICAL_ACTIVITY_MOVEMENT_STATES`, read through
`GPUConstants.is_movement_state`, and all three host consumers ask it: the
**Movement-step interpreter**, the **Turn gate**'s mid-step term, and
`GPUVisualBridge`'s diagnostics. ⚠️ The kernel's three sites — the turn brake,
the settle brake and `settle_awaited_state` — still write the four states out by
hand, so a fifth move state means editing them too. A shared GLSL function was
tried and reverted: it changes the SPIR-V, which makes the pipeline cache miss
(30 ms -> 3.5 s, measured), and the async warm-up then outlives a short test's
`quit()` into ADR-0299's freed-autoload race. A macro would not help — the cost
is the changed SPIR-V, not the call. Every move state writes the same movement fields
through one `write_movement_step`, which is why one predicate can serve all of
them. It is **not** "a state that can act" (`ACTING` is settle-awaited and not
a move) and **not** a Display concept (all four display as `WALKING`; `JUMPING`
/ `LANDING` are visualizer-chosen phases *inside* a move state).
_Avoid_: hand-listing the states at a new consumer — six sites did, each
docstring promised it matched the others, and they did match, so when ADR-0301
added `RETREATING` to the kernel's three lists and none of the host's, nothing
disagreed and nothing failed; the host classified every retreat as no-move and
a retreating unit teleported, facing what it was fleeing, in an unauthored
pose. Also avoid: reading `routing: visualizer` as a rendering detail (it is
the membership test); adding a move state anywhere but a YAML row; asserting
one hand-picked move state in a test where the generated list can be looped.

**Movement-step interpreter**:
The pure module (`GPUMovementInterpreter`) that reads a unit's per-frame
[combat-buffer](02-combat-buffer-layout.md) snapshot and classifies its movement
fields into a **new step**, a **continuing step**, or **no live move** —
owning the `move_step_id` cross-frame memory and the `timer <= total_ticks`
staleness guard that rejects the GPU's retry/wait timer. It consumes the
**string-keyed snapshot Dictionary** (ADR-0002) and returns a *derived*
`MoveStep` (grid coords + ticks + step id), **not** a typed mirror of the
snapshot — so it does not re-open ADR-0002. `GPUVisualBridge` is its only
consumer and is **apply-only**: it `match`es on the verdict to build, follow,
or clear a movement visualizer, never re-deriving the guard. The split is what
makes the new-step detection and staleness guard unit-testable with no
`RenderingDevice`, tiles, or live `Unit`. See ADR-0017.
_Avoid_: re-deriving the `timer <= total_ticks` guard or `move_step_id` change
at the call site (it lives once, in the interpreter); turning `MoveStep` into a
typed view of the 85-field snapshot (the ADR-0002 line — `MoveStep` is a
derived value, the snapshot stays a dict); reading the raw movement fields
(`prev_move_pos`, `move_step_id`, …) anywhere but the interpreter.

**Combat-step interpreter**:
The pure module (`GPUCombatInterpreter`) that reads a unit's per-frame
[combat-buffer](02-combat-buffer-layout.md) snapshot and emits the frame's
**ordered list of typed combat events** — `Died`,
`HpChanged{delta, was_heal, killed}`, `MpSpent`,
`CastBegan{ability_id, target, defers_trap}`, `CastEnded`,
`ChargeBegan`/`ChargeEnded`, `ProjectileFired`, `StatChanged` — that an
**apply-only** pump matches on. The sibling of the **Movement-step
interpreter**: same shape (pure `RefCounted`, GPU-free, scene-free), but
where movement returns one derived `MoveStep`, the combat interpreter
returns the whole frame's events and **owns the precedence** across them
(a `Died` this frame suppresses the unit's other events — the old loop's
`continue`; a `CastBegan` informs the state-transition event — the old
`spell_cast_triggered` thread). It owns the cross-frame **sample buffers**
(`_prev_hp`, `_prev_state`, …) and keys cast dedup off the GPU's
`CAST_STEP_ID` monotonic counter (twin of `MOVE_STEP_ID`), so it holds
**no invented decision-state** — the retired `_spell_cast_active` latch
(set in one method, cleared by a "safety net" in another) was exactly
that. See ADR-0018.
Its **read rule** is the cluster invariant: **battle state lives only in
the GPU** — the snapshot is the sole read interface, never a CPU-side
mutable mirror — and the only other thing it may read is **immutable
reference data that is itself mirrored into the GPU** (`AbilityDatabase`
weapon-range / formula: the same constants `GPUAbilityLoader` packs into
the ability buffer, so a CPU read is not a competing source of truth, just
the same constant read from two places). Live `Unit` nodes, terrain, and
`RenderingDevice` are forbidden — those belong to the apply pump.
_Avoid_: putting any node / terrain / `effect_manager` touch in the
interpreter (it emits `CastBegan{defers_trap}`; the pump reads world
positions to build the TRAP payload — ADR-0018); inventing a CPU latch
where a GPU monotonic id would do (`CAST_STEP_ID` is the pattern — a latch
is a second source of truth for state the GPU should own); pulling
projectile-*landed* into the diff (it is a `projectile_manager` callback,
not a snapshot edge — only projectile-*fired*, the `anim_flags` bit, is
interpreted); reading mutable battle state from any CPU store instead of
the snapshot.

**Combat loop**:
The combat **`Node`** (`CombatLoop`) that owns the whole game-visible battle:
the GPU simulator + state reader + distance field, the battle setup
(`set_battle_from_units` + gambits), both the **Combat-step** and
**Movement-step** interpreters with `GPUVisualBridge`, the **effect manager**
(`addons/exmateria_effects/cast/EffectManager.gd` — per-unit charge VFX lifecycle, per-caster
deferred TRAP, awaited effect cleanup), the **projectile manager**
(`src/projectiles/ProjectileManager.gd` — ADR-0032's pure visualizer driven by
the firer's snapshot every frame) and the **cinematic manager**
(`src/gpu/CinematicManager.gd` — the per-cast cinematic-spell `EffectInstance`
lifecycle, edge detection on the GPU's `cinematic_caster_idx`, PlayerCamera
takeover; emits `cinematic_began` / `cinematic_ended` so the loop refreshes
the [combat-visuals](02-combat-buffer-layout.md) freeze in lockstep — ADR-0037 dec. 7),
the per-tick **pump** (`step_tick` →
interpret → apply → projectiles → victory), the **animation apply**
(`_update_unit_animation`, `_start_attack_animation`, cast-complete /
effect-spawn), the **reaction routing** (`_trigger_physical_reaction` from the
`POST_GENERIC_ATTACK` SEQ side-effect, `_trigger_projectile_reaction` from
`projectile_landed`, `_on_ability_react` / `_on_refresh_tile` from the
effect-keyframe signals — inlined here because the routing is stateless and
all the timing data it reads (`_last_damage_tick`, `_last_evade_type`, the hit
windows) already lives on `CombatLoop`), and the victory check.
It drives the `Unit` nodes a **host** hands it via
`start_battle(units, gambits, terrain, map, seed)`, and emits **one signal per
semantic event** — `unit_died`, `hp_changed`, `state_changed`, `mp_changed`,
`stat_changed`, `cast_began`, `projectile_fired`, `victory` — so a consumer
connects only to what it needs (the "fat loop, per-event signals" shape).
**Composed, not inherited.** Two **independent sibling hosts** hold a
`CombatLoop` and neither *is* one: `GPUCombatTestBase` (builds units from
`get_*_unit_configs`, connects the signals to `_rlog` + the `on_*` assertion
hooks + timeout-quit — the ~25 GPU tests keep their hook surface and just extend
it) and the production `GPUArena` scene (builds units from the roster, runs the
strategy phase, then `start_battle`, connecting the signals to death cues / UI /
end-screen). Both hosts `extends` a thin `CombatHost` base that holds **only
accessor mechanics** — the composed `combat_loop` field, shared loop-state
references synced via `_sync_loop_refs`, the four mutable forwarding scalars
(`current_tick`, `_tick_accumulator`, `combat_active`, `victory_achieved`), and
the `_process` pump-drive call. The base carries **no policy**: loop creation
/ wiring, `_rlog`, the `on_*` assertion hooks, the victory / quit behaviour,
and production UI all stay in each host, which diverge sharply (test
instrumentation vs production UI). ADR-0018 deferred this extraction ("extract
one later only if real duplication appears"); it landed once real duplication
did, in commit `9819c0c6`. Test-config → battle-spec translation
(`_build_gpu_config`) stays **host-side**, so `CombatLoop`'s interface speaks
`Unit` nodes + a battle spec, never test dicts. See ADR-0018.
_Avoid_: production `extends GPUCombatTestBase` (the inheritance this retired —
production composes a `CombatLoop`); putting `_rlog` / the `on_*` assertion
hooks / test-config dict shapes inside `CombatLoop` (host concerns, driven by
its signals); putting **policy** on `CombatHost` (loop creation / wiring, the
assertion hooks, `_rlog` logging, victory / quit, production UI) — it holds
only accessor/sync mechanics, the two hosts diverge sharply on policy, and
growing `CombatHost` re-introduces exactly the coupling ADR-0018 retired; a
unified "Combat action queue" over the effect / projectile /
reaction routing (the three internal shapes are a per-caster slot, a per-unit
Node lifecycle, and a per-tick visualizer state machine — none of them wants
an ordered-side-effects sink; a future review that re-derives the queue from
the apply pump's surface should stop here); calling this an "orchestrator"
unqualified (the effect-orchestration cluster owns that verb for one cast's
playback; this drives the battle's per-tick GPU→game loop, a different scope).

**Rollout fleet**:
The `K x M` battle slots one **thinking beat** fills with candidate gambit
edits — `K` candidates by `M` **common-random-number** seeds — carried `H`
ticks forward in a single `step_tick`. It is not a second simulator: it is the
same `GPUBatchSimulator`'s whole batch, and **the live battle is one of its
slots**. `step_tick` encodes one compute list over every battle with no
per-battle active mask, so the live battle is carried forward whether or not it
holds a candidate; `restore_battle` putting it back is what makes the beat
invisible, which is why the rollout is the second consumer of the keystone
round trip (ADR-0235). Allocated by `CombatLoop.rollout_fleet_size`, which is 0
— meaning one battle — everywhere until an AI host sets it. See ADR-0246,
ADR-0237.
_Avoid_: "the simulator" for the fleet (it IS the simulator, widened);
"1 + K" (that is the *rejected* widened shape with an active mask, kept for
Active mode); calling the restore cleanup or bookkeeping — it is the only thing
standing between a beat and a battle jumped `H` ticks into a future nobody
played; assuming a fleet slot still shows its candidate after a beat (slot 0
does not — the restore erased its candidacy, and its result record was read
before that).

**Thinking beat**:
One enemy decision: snapshot the live battle, fill the **rollout fleet**, run
the horizon, read the results, restore. Its three legs are **fill**, **run**
and **score**, and ADR-0237 priced each. The beat produces raw per-slot result
records and nothing else — ranking them is the **value function**'s job, so a
beat that also scored would make the horizon sweep unable to vary the scorer.
See ADR-0246 dec. 6.
_Avoid_: "the AI turn" (a beat is what the AI does *within* a turn the **turn
director** opened, and one ply — rollouts do not run the turn machine);
"simulation" unqualified.

**Rollout candidate**:
One entry in a beat: an **encoded gambit image**, `GAMBITS_PER_UNIT` ints, the
same slice `snapshot_battle` hands back. Not a `GambitList` — an image edit is
definitionally installable, whereas a domain-object candidate could fail to
encode (ADR-0023) mid-beat with nothing to do about it. **Candidate 0 is the
unmutated incumbent**, so the beat always carries a "leave it alone" arm.
Generated by five one-step mutation families (swap, condition, action, delete,
insert) plus authored **postures**, interleaved so a small `K` drops each
family's tail rather than whole families. See ADR-0246 dec. 2.
_Avoid_: "mutation" for the whole set (a posture is a whole authored plan, not
a one-step edit); editing slot `MAX_USER_GAMBITS` (ADR-0048's safety net — a
candidate that touches it is scoring a unit that can strand itself).

**Static legality prefilter**:
The only pruning the CPU does to a **rollout candidate**: an ability the unit
does not have, and one whose `mp_cost` exceeds its MAX MP. Both are ceiling
tests read from the same ability table the shader indexes. Everything dynamic —
current MP, the cooldown clock — stays in `spell_pre_validate` /
`cooldown_pre_validate`, because a CPU copy of a runtime rule is a second
implementation that will disagree with the first. A candidate the prefilter
lets through and the shader vetoes is not waste: its slot falls through and it
scores like the plan it degrades to. See ADR-0246 dec. 3.
_Avoid_: "the prefilter reimplements pre_validate" (it deliberately does not);
adding a reachability / LOS / affordability check here — the same duplication
#894 rejects for the imperative-gambit watchdog.

**Common-random-number seeds**:
The `M` battle seeds a beat reuses across *every* candidate, so two candidates
face identical luck and the difference between their outcomes is the gambit
edit alone. Because `rand_int` is a stateless hash of
`battle_seed + unit_id * 1000 + tick`, a battle at `U` unit slots over `H`
ticks draws on `[S, S + (U-1)*1000 + H - 1]` — so the `M` seeds must be at
least `(U-1)*1000 + H` apart or their streams overlap and the replicates stop
being independent. `RolloutHarness.crn_seeds` spaces them; `seeds_are_disjoint`
is the assertion. See ADR-0246 dec. 4.
_Avoid_: "the same seed" (the seeds are shared across candidates and distinct
across replicates — those are different axes); treating an aliasing set as
harmless because nothing crashes — the failure is a bias in the comparison,
with no visible symptom.

**Posture**:
A whole authored gambit plan a **rollout candidate** may jump to in one step —
"press", "finish", one per usable ability, "mend", "raise the fallen",
"withdraw". The MIX
is keyed by `UnitRole` rather than by job id, because role is the widest key
`JobDatabase` already answers for every job (HYBRID covers monsters and
specials) and a per-job table would be invention; whether a posture in that mix
is offered at all is keyed by the unit's own **ability buckets**, so an empty
bucket yields no posture rather than one that cannot fire. Authored as domain
`Gambit` objects and put through the one encoder, so a posture the GPU cannot
express is dropped with ADR-0023's own verdict instead of becoming a silently
different plan inside a rollout nobody watches. See ADR-0246 dec. 5.
_Avoid_: "playbook entry" for a single gambit (a posture is the whole list);
authoring a posture as raw ints (it is the one place the encoder's verdict is
available, and skipping it throws that away).

**Raise-the-fallen posture**:
The one **posture** every role is offered, because the permission to raise the
dead is in the ability data and not in the job (ADR-0293's argument, applied to
authoring): `JOB_ROLES` files Priest — which learns Raise and Raise2 — as MAGE,
and HEALER is Chemist alone. Its first gambits are the **revive bucket**'s ids
in id order (cheapest first) aimed at `friendlies_or_ko()` under `IS_KO`, then a
mend, then attack-nearest. It is one of two postures no one-step mutation can
reach (the **withdraw posture** is the other), since `RolloutCandidates`' menus
hold neither `COND_IS_DEAD` nor `TARGET_NEAREST_ALLY_OR_KO` — and it is the
SCARCER plant of the two, needing an unreachable condition and an unreachable
pool and an ability the action menu omits, so it is authored first and it is the
tail that must NOT be dropped when `K` truncates the playbook family. Built by
#1104.
_Avoid_: gating it on a `UnitRole` (the raisers are not on the healer job);
spelling its condition as a status check on bit 0 (`STATUS_DEAD` is hollow —
it encodes cleanly and never fires); giving it `MOST_CRITICAL` resolution (the
corpse is at 0% HP, so it would win every rank and starve the living — the
encoder refuses that pairing outright).

**Withdraw posture**:
The **posture** that carries the retreat verb — "back off when a foe has closed,
else press": `enemies()` under `target_within(WITHDRAW_TILES)` aimed at the
enemy the condition matched, over an attack-nearest fall-through. Offered to
every role including MELEE, and NOT because the ability data answers the
question the way it does for the **raise-the-fallen posture** — a step needs no
ability, so nothing in the candidate **context** can say which units want to
disengage and the role genuinely is the widest key there is. The role is still
not used as a gate, because planting the verb once puts the whole retreat family
on the mutation lattice: `ACTION_RETREAT_STEP` is in no mutation menu, so no
one-step edit can introduce a retreat into a list that has none, but a slot that
already CARRIES it is one `condition` edit from every distance and self-HP
threshold the menu offers. So the HP-keyed break-off a melee unit wants is
authored nowhere and reachable anyway, and withholding the posture from MELEE
would have withheld the verb from the role for every beat of every rollout.
Second in the playbook, behind the scarcer revive plant. See ADR-0301.
_Avoid_: aiming its retreat at the caster (`retreat_step_cell` refuses
`flee_from == unit_id`, so the row encodes cleanly and is a guaranteed
`VERDICT_NO_RETREAT` fall-through — `GambitOptions.aim_verdict` grades that cell
AIM_FORBIDDEN); leaving no slot beneath the retreat (a cornered unit's
fall-through then lands on ADR-0048's safety net, which walks it back toward
what it was fleeing); picking its threshold freely (it is pinned to
`CONDITION_MENU`'s own distance figure so the slot stays a neighbour of the
menu); authoring a second, HP-keyed withdraw posture (one condition edit apart
is the near-identical flood the per-ability cap exists to stop).

**Revive bucket**:
The third bucket of the **static legality prefilter**'s split, beside
`offensive` and `healing`: the unit's usable abilities whose packed inflict list
names `Dead` under mode `cancel`, read off the same ability table the shader's
`ability_revives` reads. Disjoint from the other two and checked FIRST, because
the healing bit alone files a revive wrongly in both directions — `Raise` is
`receive_heal`, so it became a mend aimed at the worst-off LIVING ally, and
`Revive` (107) is not, so it became "cast at the nearest ENEMY, always".
_Avoid_: treating it as a flag (there is no `ABFLAG_` for reviving and ADR-0293
argues there must not be); reading it from `effects.json` at rollout time (the
packed buffer is the shared copy).

**Result record**:
The per-battle row `stage_victory` writes **every tick for every ongoing
battle** and `GPUBatchSimulator.read_all_results` reads whole in 0.11 ms: the
verdict, the tick, and the **value function**'s features. Fourteen ints wide,
laid out by `R_*` in `combat_common.glslinc` and generated into
`GPUCombatPacker.ResultField` by `tools/gen_gpu_layout.py`, so the shader is its
one author (ADR-0001). Widening it is how a feature gets added — it is
write-only from the shader's side, so a new field touches no combat rule —
and that is the whole reason ADR-0237 dec. 7 put the features here rather than
in a reader. See ADR-0253 dec. 3.
_Avoid_: "the results buffer" when you mean one battle's row; reaching past it
to `read_unit_column` for a feature (a blocking readback per battle, 33-51 ms
across 1024 — as much as running the entire horizon, for one feature); writing
a hand-mirrored copy of the offsets anywhere (there were three, and that is
exactly what could not be widened safely).

**Search objective**:
What the **thinking beat** maximises — the number it ranks its candidates by,
read off one **result record**. Two ship, and they are not the same *kind* of
object: the **value function** `f` is a fitted probability, the **provisional
objective** is a hand-written ordering. Every objective is
**perspective**-complementary, bounds its value in `[0, 1]`, refuses with
`RolloutObjective.CANNOT_SCORE`, and **names itself** — a corpus whose objective
is unrecorded is unattributable later, so the name is on the interface rather
than in a comment. `RolloutObjective` is the supertype; the averaging over
**common random numbers** and the incumbent tie-break live there, because both
are properties of the *search* and not of what it maximises. See ADR-0274.
_Avoid_: "the value function" for whichever one is running (only one of them is
`f`); a run that reports a value without its objective's id.

**Value function** (`f`):
`P(victory)` for the team whose **perspective** it is taken from, a logistic
over the **result record**. That it is a probability is the design, not the
implementation: a hand-weighted score needs a terminal win/loss bonus big enough
to make winning outrank having more HP, and no principled value for it exists,
whereas a probability is already calibrated and already comparable. Fitted by
`tools/fit_value_function.py`, shipped as `assets/gambit/rollout_value_function.json`,
read by `RolloutValueFunction`. See ADR-0253.
⚠️ **Fitted, shipped, guarded — and not the objective the search runs today.** Its
**corpus** predates the ~48× tempo change, and #897's AI is the first thing to
maximise it: it pays `mp_frac_self` +2.23, `hp_frac_self` +2.05 and
`engage_self` +0.0495 per tile, so it rewards spending no MP, taking no damage
and standing off. The owed refit is the *artifact's*, not this class's. See
ADR-0274.
_Avoid_: "score" or "heuristic" (both invite the weight the probability
removes); calling `RolloutHarness` the scorer — it deliberately does not rank,
so the **H-sweep** can vary `f` without touching the machine that produces the
rows; reading `f` as what the AI currently maximises.

**Provisional objective**:
*Kill the enemy, don't die* — the hand-written **search objective** standing in
for `f` until its refit, with **zero free parameters**: the mean of two mirrored
shares (HP, units standing) over the **result record**, and nothing else. It is
an **ordering**, not a probability, and it still drops the invented terminal
bonus — the verdicts take the outer 0.1% of `[0, 1]` at each end and every
ongoing state is clamped strictly inside, so a win is not weighted above an
ongoing state, it is outside the band one can reach. Deliberately crude: there is
nothing in it to over-fit to numbers that are about to move. Two terms because HP
share alone cannot tell six wounded units from three corpses and three untouched
ones. A terminal verdict is a **band** and not a point — it orders inside itself
by what the battle cost — because a flat one was measured making the AI stop
trying once a position was lost, which shortens the very battle this map is
built to measure. See ADR-0274 decs. 3 and 3a.
_Avoid_: adding an MP or standoff term "for completeness" (those two are exactly
the perverse instructions it exists to drop); tuning the 50/50 weight (the free
parameters are the thing it does not have); reading its value as a probability.

**Perspective**:
The team a **value function** reading is taken from. Every feature is per team
and mirrors, so swapping the roles describes the same battle from the other
side and `f(state, team0) + f(state, team1) = 1`. A battle-wide feature with no
per-team split breaks that: it can say how *decided* a battle is but never who
is winning, and mirrored training rows drive its coefficient to zero. See
ADR-0253 dec. 5.
_Avoid_: "the AI's score" (the enemy and the player are two readings of one
state, not two functions); adding an unmirrored term.

**Corpus**:
Battles played to **completion** on the GPU fleet by `tools/rollout_corpus.tscn`,
sampled on a fixed tick grid, every sample labelled with its own battle's
eventual winner. The fleet is the point: the shader IS the gambit AI, so a fleet
battle is a faithful game and not a model of one, and `CombatLoop`'s 60 ticks/s
would put a thousand battles at about a day. The grid is what lets ONE corpus
serve the whole **H-sweep**. See ADR-0253 decs. 1-2.
_Avoid_: a fixed roster (symmetric teams make the label a near coin flip, and an
ATTACK-only roster leaves the MP feature constant so its coefficient means
nothing); sampling a decided battle (its record stops being rewritten, so the
rows are copies of the terminal one).

**Log-loss**:
The metric `f` is scored by, and deliberately not accuracy: accuracy cannot
distinguish a confidently wrong predictor from a hedging one, and only one of
those is safe to act on at a decision point. Always read against the
always-predict-the-base-rate model's `ln 2 = 0.6931` — a stratum that cannot
beat it is a stratum `f` knows nothing about, however good the total looks.
See ADR-0253 dec. 6.
_Avoid_: quoting a total without its **stratification**; comparing two log-losses
taken over different row sets.

**Stratification**:
Bucketing scored states by **remaining battle length** before reading the
log-loss. A predictor scored across all states looks excellent by nailing
trivially-decided endgames while being useless in the mid-game where the
decisions actually are — and it is the only thing that found §8's four named
feature families insufficient (0.7210 early against a base rate of 0.6931,
worse than a coin flip, invisible in the 0.3492 total). See ADR-0253 dec. 6.
_Avoid_: reading a stratum that is empty by construction as missing data — the
common row set needs a landed state at `D + max(H)`, so decision points near the
end of a battle are excluded on purpose.

**H-sweep**:
The accuracy-vs-cost table across the horizon, and §8's primary deliverable.
`H` and `f` are **substitutes** — at `H → ∞` no formula is needed, at `H → 0`
the formula carries everything — so `(H, f)` is one joint choice and neither can
be picked alone. Every horizon must be scored on the SAME held-out decision
points, or the population changes underneath the table and the losses differ for
two reasons at once. See ADR-0253 decs. 7-9.
_Avoid_: reading the **knee** off a table with no cost column, or off the
bench's fresh-fork cost (ADR-0237 dec. 6: the AI forks mid-battle, at ~2x).

**Knee**:
The horizon where marginal return collapses — the last step still returning a
worthwhile share of the best step's log-loss per millisecond, read under a
wall-clock cap on the FORKED beat. A rule that instead takes the last horizon
which improved *at all* selects the largest horizon in any monotone table.
Measured at `H = 400` under a 200 ms cap. See ADR-0253 dec. 8.
_Avoid_: treating `knee_horizon` as the tunable itself. It is an INPUT to
ADR-0256 dec. 7's `rollout.horizon`, which is where the number the game plays at
lives; the driver compares the two at mount, because a refit that moves the knee
and a code default that does not is a divergence with no symptom.


**Beat plan**:
The `(K, M, H)` one **thinking beat** actually runs at, chosen before the beat
by `RolloutDriver.plan` from the **beat cap**, the allocated **rollout fleet**
and `units_per_battle`. A pure function of those — no clock is an input, which
is what makes the AI's choice reproducible on a position (ADR-0256 dec. 1). See
also **cost model**, **degradation ladder**.
_Avoid_: calling the SHIPPED defaults the plan. `K = 64 x M = 4 x H = 400` is
what a plan starts from; what it ends at is a property of the scenario.

**Beat cap**:
The hard wall-clock ceiling on one **thinking beat**, in milliseconds of FORKED
cost, published as the `rollout.cap_ms` tunable (250 ms). Priced as a FROZEN
FRAME and not as a cinematic: the beat runs synchronously inside the turn
freeze, so its cost is a hitch the player sees. It is spent by PREDICTION — the
stopwatch reports afterwards and never re-plans (ADR-0256 decs. 1, 6).
_Avoid_: reading it as a promise about the box. It is only as hard as the **cost
model**, and every knot in that model is one GPU's measurement.

**Cost model**:
`predict_beat_ms(U, N, H)` — ADR-0237's and ADR-0253's measured rows, composed
as three separable axes (horizon x units x fleet) times ADR-0237 dec. 6's ~2x
fork factor. Separability is those ADRs' own claim about the axes: the fleet is
nearly free, `U` is the expensive one, `H` is the only superlinear one. At the
reference shape (`U = 12`, 256 battles) it reproduces ADR-0253 dec. 9's forked
column exactly. See ADR-0256 decs. 2-3.
_Avoid_: reading the fleet axis literally at its low end. The measured row at 4
battles sits 0.02 ms below the row at 1 — repeat noise on a quantity that cannot
fall — so it is read through a monotone envelope, or the **degradation ladder**
becomes a hill climb.

**Degradation ladder**:
§7's fixed order for shrinking a **beat plan** that does not fit: drop `M`
first, then `K`, **never `H`**. A shortened horizon systematically biases the AI
toward immediate damage; fewer seeds only add noise, and bias is worse than
variance. Kept for its reasoning and not for its rungs — the whole ladder
recovers about 25 ms of a 138 ms beat, because the beat is bounded by `H` and
`units_per_battle` rather than by the fleet (ADR-0237 dec. 4, ADR-0256 dec. 4).
_Avoid_: reaching for it as the remedy when a beat blows its cap. Set the cap so
degradation is never the plan; a `degraded` line in the log is a message about
the tunable.

**Refused beat**:
What the **degradation ladder** does at its floor: no beat runs and the turn is
spent unchanged, which is exactly "wait" (ADR-0239). The floor is `K = 2`, the
first `K` at which a search compares anything — `K = 1` would spend the whole
horizon to rank the incumbent against nothing. A refusal names the cap, the
shape and the two tunables that could move (ADR-0256 dec. 5).
_Avoid_: reading it as a bug in the AI. Above about `U = 30` the horizon alone
blows a 250 ms cap and `H` is the one rung that may not be taken; the refusal is
the cap being honest.

**Held decision**:
A **thinking beat** whose winner was candidate 0 — ADR-0246 dec. 2's unmutated
incumbent, which a tie also falls to. Nothing is written to the live battle, so
"the AI changed its mind" and "the AI held" stay distinguishable at the one
place that could tell (ADR-0256 dec. 12).
_Avoid_: applying it anyway as a harmless no-op. It is harmless to the buffer
and not to the log.

**CRN base seed**:
The integer `RolloutHarness.crn_seeds` spaces one beat's `M` **common random
numbers** off, derived by hashing `(battle seed, tick, taker)` out of the
snapshot the beat is about to fork. Two properties at once: the same position
derives the same seeds (reproducibility), and a different turn derives different
luck (a constant base would hand every beat in a battle the identical luck — a
bias averaging over `M` cannot see, because it is the same `M`). See ADR-0256
dec. 11.
_Avoid_: deriving it from anything that is not in the position — a clock, a
counter, a `randi()`. Each of those is the reproducibility requirement lost at
the last step.

**Unread** (of a status bit or unit field):
Declared, and no kernel site consults it. The rule was never written, so the
bit cannot change any outcome no matter who sets it. `STATUS_DARKNESS` and
`U_BRAVE` are both unread. Fixing an unread bit means writing a rule.
_Avoid_: reading a reference count as the verdict — a bit with two references
may be a declaration plus a real rule, or a declaration plus a dead branch.

**Unreachable** (of a status bit or condition):
The rule exists and is correct, and nothing in the shipped data can produce the
state it reads, so no battle ever runs it. `STATUS_TRANSPARENT` has fifteen
kernel sites and no ability that grants it; `COND_IS_DEAD` was decidable and
unreachable until #1102 gave it a KO-inclusive pool. Fixing an unreachable rule
means authoring data or a path, not code.
_Avoid_: calling this "implemented" because the code is there — the whole point
is that shipped code and reachable behaviour are different claims.

**Hollow** (of a status bit):
**Unread** or **unreachable** — the bit cannot participate in a battle from one
end or the other. The word names the *outcome*; the two above name the *causes*,
and they take opposite fixes. `docs/status-conformance.md` carries the per-bit
verdict.
_Avoid_: "unimplemented", which collapses the two causes into one word and hides
which end is broken.

**Clock tick**:
FFT's unit of status time: every clock tick each unit accrues Speed toward 100
and every status counter loses 1. This kernel has no such clock of its own — it
ticks at 60 Hz — so the ratio is read off the **turn meter**, which is the same
accrual written at a different scale: `TURN_METER_FULL / 100` = **36 ticks**
(`TICKS_PER_CLOCK_TICK`). Derived, not chosen, so rescaling the meter moves the
durations with it.
_Avoid_: using the 30 an ability's charge CT is multiplied by
(`GPUAbilityLoader`) — FFT spells both "CT" but charge is speed-independent in
this kernel and a status counter is speed-independent in FFT, so they are
different claims that happen to land near each other.

**Inflict mode**:
Which of the listed statuses an ability's inflict set actually lands. FFT's own
four-valued field — one flag bit in the six-byte `InflictStatusList` record (SCUS
`0x80063FC4`), one `INFLICT_MODE_*` int in the ability buffer: `all` lands every listed
bit, `random` lands exactly one picked uniformly, `separate` rolls each listed bit
independently at the **separate roll**, and `cancel` REMOVES the listed bits instead of
setting them. The mode resolves the set to a mask (`resolve_inflict_mask`) and then one
apply writes it, which is the ROM's own shape. Census over `effects.json`: 114 all, 16
separate, 14 cancel, 11 random. See ADR-0299.
_Avoid_: treating `all` as "the default" and the other three as variants — the ROM's
table is a flat enum and 10 of its 128 entries are blank, not `all`; reading
`mode != cancel` as `mode == all`, which inverts 17 records in both directions (ADR-0278
dec. 5); expecting an inflict record to carry a per-status probability, because six bytes
is one mode byte plus a five-byte status set and there is nowhere to put one.

**Separate roll**:
The flat **24%** a `separate`-mode **inflict mode** gives each status it lists, rolled
once per (target, status) and independent of the ability. The ROM's own number —
`pass_fail_roll(100, 0x18)` at BATTLE.BIN `0x801880E8`, whose passing branch XORs the
status back out of the set — so it is a constant, not a rate derived from anything. The
ability's hit rate is spent upstream deciding whether the inflict site is reached at all;
it does not scale this. A nine-status set lands 2.16 statuses on average.
_Avoid_: calling it the ability's hit rate rolled per status, which is the intuitive
reading of "separate" and is not what the ROM does; composing it with the ROM's
quartering of the predicted-success percentage (`[action + 0x2A] >>= 2`), which is the
DISPLAY booking this same 24% and not a second gate — that halfword is never rolled
against.

**Status duration** (default CT):
How long an inflicted status lasts, in **clock ticks**, read from the ROM's
status-attribute table (SCUS `0x80065DE7 + 0x10*status`, byte 0) and carried as
`StatusRegistry.DEFAULT_CT` / `status_default_ct`. **Sixteen of FFT's forty
statuses have one** — Poison and Regen 36, Protect / Shell / Haste / Faith /
Innocent / Charm / Reflect 32, Slow / Wall / Don't Move / Don't Act 24, Stop 20,
Sleep 60, Death Sentence 3 — and the other twenty-four are permanent until
cancelled. Eleven of the sixteen have a bit in this kernel (#99 owes five).
See ADR-0298.
_Avoid_: reading a zero as a gap (it is the ROM's answer, and the ROM gives those
statuses no byte to count down in); writing a duration for a status the table
leaves at zero.

**Status countdown**:
The live per-status counter that a **status duration** arms: sixteen 16-bit
counters packed two per int across `U_STATUS_TIMER_0..7`, addressed by the
status's own `status_timer_slot` (the ROM's `status - 24`). Armed by
`apply_inflict_all` → `arm_status_default_duration`, decremented by
`tick_status_timers`, cleared by a `cancel`-mode inflict. Reaching zero clears
the flag.
_Avoid_: calling it a pool or a slot the next status takes — it was one until
#1116, and the overflow case that design had (a ninth timed status set with no
countdown, permanently and silently) is the reason it is status-addressed now;
reading or writing one through the CURRENT buffer (two counters share an int, so
a CURRENT-buffer read-modify-write undoes its neighbour); expecting the bit to
clear exactly `duration` ticks after it landed (a cinematic pause freezes the
counter, which is what FFT's stopped clock does too).
