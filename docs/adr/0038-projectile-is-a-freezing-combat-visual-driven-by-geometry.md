# Projectile is a freezing combat-visual with tick-locked flight and death-resilient landing

`ProjectileManager` + `Projectile3D` cover **every** in-flight projectile in
combat — ranged-weapon attacks (arrow, bullet, crossbow), throw abilities
(ninja Throw, Throw Stone, Please Eat — `effect_anim_id == 76`), and
item-throw abilities (368–381). One system, variant-branched at spawn. The
`Projectile3D` node joins the `combat_visuals` group
([ADR-0037](0037-combat-pause-is-domain-scoped-via-process-mode-group.md)) so
cinematic spell halts spin/tumble in flight via the group's
`process_mode` flip, spacebar pause halts flight position naturally through
the `combat_active = false` short-circuit in `CombatLoop.tick()`, and
post-victory leaves both running so the projectile still lands. Flight
position advances **one tick at a time** from inside `CombatLoop`'s
`while _tick_accumulator` loop (`Projectile3D.advance_tick()`), keeping
flight tick-locked with the GPU damage tick at any `Engine.time_scale`.
Flight duration is the **GPU's SEQ-authored `damage_frame - anim_frame`**
snapshotted at spawn (per
[ADR-0032](0032-ranged-damage-waits-in-state-awaiting-impact.md)) — uniformly
applied with the retired BULLET `/3` and throw/item `flight_speed_mult`
asymmetric multipliers **gone**, which is the consistent-speed fix the
"speed feels weird" symptom asked for. Target or firer death mid-flight
**does not** strand or teleport the projectile: while the target Node is
alive `end_pos` updates each tick to its live position, once freed it sticks
at the last seen value, and the local countdown runs to completion regardless
of firer state. `projectile_landed` still emits at the natural landing tick
for hit VFX / sound (no damage write — still ADR-0032 /
[ADR-0031](0031-battle-state-is-gpu-authoritative.md)).

## Status

accepted — supersedes
[ADR-0032](0032-ranged-damage-waits-in-state-awaiting-impact.md)'s
`projectile_manager` bullet (the "pure visualiser driven by the firer's
snapshot every frame" model and the "when the firer transitions out, the
bullet despawns" rule). ADR-0032's state-machine half
(`LOGICAL_ACTIVITY_ACTING` → `LOGICAL_ACTIVITY_AWAITING_IMPACT`, timer-zero
damage write, in-shader gambit re-eval block, MIN_FLIGHT_TICKS floor in
`setup_attack_animation`) is unchanged. **Flight duration stays
SEQ-authored**, same value the firer-snapshot model used — what changes is
the *driver* (a local per-tick countdown owned by the projectile, advanced
in lockstep with `step_tick`) and the *freeze axis* (`combat_visuals` group
membership). An earlier draft of this ADR proposed distance-driven flight
time (per-`ProjectileType` family-speed constants) to address the
"speed feels weird" symptom; that draft was retired during implementation
when the heuristic in `_trigger_projectile_reaction` (a 2-tick window
between `current_tick` at landing and `_last_damage_tick`) turned out to be
load-bearing for hit-vs-evade attribution. The asymmetric `flight_speed_mult`
(throw/item) and BULLET `/3` divider were the actual sources of the user's
inconsistent-speed perception; their removal — keeping uniform SEQ timing
across every family — is the consistent-speed fix that landed.

## Context

`ProjectileManager` had three observable bugs in production:

1. **Speed felt inconsistent.** Flight duration came from
   `damage_frame - anim_frame` (firer's SEQ). Two units throwing the same
   weapon across the same distance fly for different durations if their
   abilities authored different `damage_frame` values. A separate
   `flight_speed_mult` debug divider applied to throw/item but not to
   `ARROW` / `SHURIKEN` / `STONE`. The effect over many throws was that
   the projectile didn't *have a speed* — it had whatever the firer's SEQ
   timing made it.
2. **Cinematic spell did not freeze a mid-flight projectile, but spacebar
   did.** Spacebar sets `combat_active = false`, short-circuiting
   `CombatLoop.tick()` before `_run_per_tick_systems` runs — so
   `ProjectileManager.update()` is never called, and spin / position
   advancement stop as a side effect. Cinematic keeps `combat_active = true`
   (it has to — the GPU must keep ticking so the cinematic timer advances)
   and routes its freeze through the `combat_visuals` group ([ADR-0037]).
   `Projectile3D` was spawned as a child of `CombatLoop` and never enrolled
   in the group — so the cinematic freeze passed it by, and the rock kept
   spinning while the spotlight played.
3. **Sits-in-the-air on death.** If the target died mid-flight, the
   stored `target_idx` resolved to a freed node, `end_pos` stopped
   tracking, and the projectile parked there until the firer eventually
   transitioned out. ADR-0032 specified "despawn on firer transition,"
   but the implementation actually *landed* the projectile (jumped
   `progress` to 1.0 and emitted `projectile_landed`) — a different bug:
   a teleport-to-target the frame the firer fell, not a despawn. Either
   shape produces a discontinuity the eye notices.

A fourth observation: spin rate for `WEAPON_SPRITE` / `ITEM` was
`ProjectileDebugPanel.spin_deg_per_tick` — a tunable debug knob with no
PSX reference. (`STONE_TUMBLE_X_RATE` / `STONE_TUMBLE_Y_RATE` are
PSX-faithful, cited inline; the thrown-weapon spin is the gap.)

These are not four bugs — they are one ownership question (what part of the
projectile's lifecycle is the GPU snapshot's, what part is its own) plus a
freeze-axis gap and an RE follow-up.

## Decision

- **Projectile3D joins `combat_visuals`.** `add_to_group("combat_visuals")` in
  `_ready`. Spin and tumble advance per-frame from `Projectile3D._process(delta)`;
  the group's `process_mode` flip from `_refresh_combat_visuals_freeze` halts
  them on every freeze axis uniformly. Flight POSITION advances per GPU tick
  via `advance_tick()` (next bullet) — a separate path because position must
  stay tick-locked with the GPU damage tick, which `_process(delta)` cannot
  guarantee at `Engine.time_scale > 1`. **Post-victory leaves the predicate
  `true` per ADR-0037 dec. 8 — the projectile lands naturally after the battle
  resolves, the same rule that lets fading charge VFX drain.** No cinematic
  carve-out: a projectile fired by a non-cinematic-caster freezes (spin-wise)
  during an opponent's cinematic. The caster-charge carve-out ([Combat-visual]
  carve-out 2) does not apply — a unit does not fire a projectile while their
  own cinematic plays, so the rule would be a theoretical no-op.

- **Flight position advances per GPU tick.** `Projectile3D.advance_tick()`
  increments `elapsed` by `1/60` sec, recomputes XZ-lerp + parabolic-Y arc
  position, and sets `_landed` when `elapsed >= flight_duration`. Called from
  inside `CombatLoop`'s `while _tick_accumulator` loop — one call per
  `step_tick`, so flight stays tick-locked at any `Engine.time_scale` (the
  test harness uses 4.0x; driving from `_process(delta)` instead would lag
  visual landing by ~4 ticks per Godot frame and break the hit heuristic).
  Spacebar pause halts position naturally because the whole `while` loop
  short-circuits on `combat_active = false`; cinematic does not halt
  position (combat_active stays true) but halts spin via the group flip.

- **Flight duration is SEQ-authored, applied uniformly.** Snapshot at spawn
  from `state.damage_frame - state.anim_frame` (the same value
  `setup_attack_animation` would have written to `U_TIMER` for the
  AWAITING_IMPACT phase, just captured CPU-side at projectile_triggered).
  Stored in seconds (`flight_ticks / TICKS_PER_SECOND`) on `Projectile3D`.
  The asymmetric BULLET `/3` divider and the throw/item `flight_speed_mult`
  multiplier — both retired. Every projectile family uses the same
  SEQ-derived clock; the "speed feels weird" symptom traces to those two
  special cases, not to the SEQ timing itself.

- **Death-resilient.** While the target Node is alive, `advance_tick()`
  updates `end_pos = target_node.global_position + TARGET_OFFSET` each tick.
  Once the Node is freed, `is_instance_valid(target_node)` returns false and
  `end_pos` sticks at its last value — the projectile completes its flight
  to that point. The firer's state is never read during flight, so firer
  death (or any other firer transition) does not affect the projectile:
  the local countdown runs to completion regardless. Landing fires
  `projectile_landed` regardless of who died (still no damage write — damage
  belongs to the GPU and was either already written at AWAITING_IMPACT
  timer-zero per ADR-0032 or never gets written if the firer died before
  that edge; the projectile's job is the picture, not the damage).

- **`ProjectileManager` splits advance from dispatch.** Two methods:
  - `advance_one_tick()` — called from inside the while loop; advances each
    active projectile by one tick. No dispatch.
  - `update(current_tick, all_states)` — called once per Godot frame after
    the while loop ends; dispatches `projectile_landed` for any projectile
    whose `_landed` flag was set during this frame's ticks, and cleans up
    nodes freed externally. The post-loop position is load-bearing:
    `_last_damage_tick` is set inside the loop by `_read_tick_columns`,
    but the `_trigger_projectile_reaction` hit heuristic needs that value
    to be settled across the whole frame's GPU damage writes before reading
    it. Dispatch from inside the loop would race the GPU damage write at
    high `Engine.time_scale`; the split keeps tick-locked advance with
    settled dispatch.

- **Spin / tumble use PSX-faithful constants in `Projectile3D._process`.**
  `STONE_TUMBLE_X_RATE_PER_SEC` / `STONE_TUMBLE_Y_RATE_PER_SEC` derive from
  the PSX per-tick rates × 60 (the comment in `Projectile3D.gd` cites the
  conversion). `WEAPON_SPRITE` / `ITEM` continue to use
  `ProjectileDebugPanel.spin_deg_per_tick` until the PSX-authentic rate is
  reverse-engineered from BATTLE.BIN — flagged as an open RE follow-up, the
  knob is the placeholder. The combat-visuals freeze halts both on every
  axis independent of having the PSX rate landed.

## Considered options

- **Distance-driven flight time, per-`ProjectileType` family-speed constants
  (rejected during implementation).** Flight duration = `distance /
  family_speed`. Symptom 1's first-line fix: same distance, same flight time,
  regardless of authored `damage_frame`. Failed because
  `_trigger_projectile_reaction`'s 2-tick hit window
  (`abs(current_tick - _last_damage_tick) <= 2`) is load-bearing for
  attributing hit vs evade — visual landing time and GPU damage tick MUST
  align for the heuristic to work, and family-speed timing diverged from
  the GPU's `damage_frame - anim_frame` value. The user-observed
  inconsistency turned out to live in the per-family multipliers
  (`flight_speed_mult` for throw/item, BULLET `/3`), not in the SEQ timing
  — removing those gave consistent speed without breaking the heuristic.

- **Drive flight position from `Projectile3D._process(delta)` (rejected
  during implementation).** Real-time delta-driven flight. Works at
  `Engine.time_scale = 1` but lags by ~`time_scale` ticks per Godot frame
  at higher scales because Godot's `_process` runs once per frame while
  `CombatLoop`'s `while` loop runs `time_scale` GPU ticks per frame. The
  test harness defaults to 4.0x; the lag broke the hit heuristic the same
  way distance-driven flight did. The fix that landed (`advance_tick()`
  called from inside the loop) keeps tick-lock at any time-scale.

- **Keep ADR-0032's firer-snapshot-driven flight, fix the freeze axis and
  death cases in place (rejected).** Patches the cinematic-freeze and
  sits-in-the-air bugs without touching the speed model. The cinematic
  patch is a one-line `if cinematic_manager.is_active(): return` inside
  `ProjectileManager.update` — cheap, but sidesteps the combat-visual model
  ADR-0037 was written for and re-introduces "this subsystem freezes on
  its own knobs" surface. Rejected: skips an axis ADR-0037 was designed to
  cover. The landed shape uses combat-visuals for spin freeze (the
  cinematic-visible artifact) and rides `combat_active` for position freeze
  (the gameplay-tick path that already gates everything else).

- **Despawn on firer transition (the ADR-0032 letter, rejected).** ADR-0032
  said "despawn on firer transition." The implementation actually landed
  (teleport-to-target) rather than despawning, but even the despawn behavior
  is the wrong shape: the rock you threw should arrive, not disappear. The
  user-visible discontinuity (rock vanishing the moment its thrower falls)
  is the same family of bug as sits-in-the-air — just on the other side.
  Death-resilient landing replaces both.

- **Carve out airborne projectiles from cinematic freeze (rejected).**
  Considered: in-flight projectiles finish through an opponent's cinematic
  rather than freezing. Treats "in flight" as a committed action. Rejected
  on grounds of consistency: ADR-0037's predicate is the *one* rule for
  combat-visual pause; carving out one combat-visual type re-opens the
  per-subsystem-knobs failure mode the group model was written for.

## Consequences

- `ProjectileManager.update`'s firer-state branch (`AWAITING_IMPACT` /
  `ACTING` / `firer_transitioned_out` ladder) is removed. Flight position
  math (`start_pos.lerp(end_pos, progress)` + parabolic arc + ARROW tangent
  rotation) lives on `Projectile3D.advance_tick()`. `target_node` resolution
  to `end_pos` runs there too, with the snapshot-on-free shape described
  above. Spin and tumble stay on `Projectile3D._process(delta)` so combat-
  visuals freeze halts them.

- `ProjectileManager` now exposes two pump methods: `advance_one_tick()`
  (in-loop) and `update()` (post-loop). The CombatLoop tick splits its
  projectile pumping accordingly.

- The `flight_speed_mult` field on `ProjectileDebugPanel` is gone, along
  with the throw/item-only multiplier branch in `spawn_from_gpu`. The
  BULLET `/3` divider is gone too. The panel keeps only `spin_deg_per_tick`
  — placeholder until the PSX-authentic thrown-weapon spin rate is RE'd.

- The original draft's per-`ProjectileType` family-speed constants
  (`arrow_speed`, `bullet_speed`, …) are retired before they shipped —
  the SEQ-derived flight time keeps the GPU as the single timekeeper.
  Anyone tuning ranged-weapon flight time edits the shader's
  `FLIGHT_TICKS_PER_TILE` / `MIN_FLIGHT_TICKS` constants in
  `combat_common.glslinc`, where ADR-0032 already locates them.

- ADR-0032's "pure visualiser driven by the firer's snapshot every frame"
  bullet (the `projectile_manager` paragraph in its Decision) is the part
  superseded. ADR-0032 itself stays accepted — its state machine
  (`ACTING` → `AWAITING_IMPACT` → IDLE), in-shader gambit re-eval block,
  damage rolled at landing tick (against buffed state if buffed
  mid-flight), and `MIN_FLIGHT_TICKS` floor are all unchanged. A reader
  reaching ADR-0032's `projectile_manager` paragraph follows the link to
  this ADR for the current visualiser model.

- `projectile_landed` still fires on natural landing AND on death-induced
  landing. Consumers (`CombatLoop._on_projectile_landed` for VFX / sound /
  reactions) need no special-case for the death path — they only see "the
  projectile arrived." Reactions on a dead target are already a CombatLoop
  concern, not a projectile-manager one.

- Post-victory: `CombatLoop.tick()`'s victory branch pumps
  `projectile_manager.update()` so any projectile mid-flight at the moment
  the battle resolves still dispatches and queue_frees. Without that, the
  visual would sit at end_pos with `_landed = true` until scene reload.

- Thrown-weapon spin's PSX-authentic constant is an **open follow-up** —
  the placeholder (`ProjectileDebugPanel.spin_deg_per_tick`) lives behind
  the F3 overlay until BATTLE.BIN's thrown-weapon spin rate is RE'd. The
  freeze-axis fix lands without it; the knob disappears when the constant
  does.

- A `Projectile` entry in `CONTEXT.md` (in the `Combat buffer layout`
  cluster, next to [Charge VFX]) names the system, the tick-locked flight
  model, the freeze axes, and the death-resilient policy. The "one system,
  not two" rule (no separate `ThrowManager`) is in the _Avoid_.

## References

- ADR-0031 — battle-state authority. Damage stays GPU-authored;
  `projectile_landed` continues to *not* write battle state.
- ADR-0032 — the originating ranged-damage / `AWAITING_IMPACT` ADR. Its
  state-machine half is unchanged; this ADR supersedes its
  `projectile_manager` shape only.
- ADR-0037 — combat-pause / `combat_visuals` group. The freeze axis
  Projectile now joins.
- CONTEXT.md — [Projectile](../context/02-combat-buffer-layout.md) entry (this ADR is
  the decision link).
- CONTEXT.md — [Combat-visual](../context/02-combat-buffer-layout.md) (the family
  Projectile joins).
- `src/projectiles/ProjectileManager.gd` — the spawn-record owner; the
  per-frame position branch retires here.
- `src/projectiles/Projectile3D.gd` — the per-frame advancement gains its
  new home (`_process(delta)`).
