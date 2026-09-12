# Damage application is decoupled from `STATE_ACTING`

For ranged attacks and projectile spells, damage application moves out of the
GPU's `tick_acting_animation` (where it is gated on `state == STATE_ACTING &&
anim_frame >= damage_frame`) and into the projectile-landing event handled by
`projectile_manager`. `STATE_ACTING` then ends when the unit's
[BODY SEQ](../context/19-animation-playback.md) ends, not when its projectile
lands. Melee/instant damage stays where it is — same tick, no projectile to
wait for.

## Status

superseded by [ADR-0032](0032-ranged-damage-waits-in-state-awaiting-impact.md).

The decision below — moving the damage write to a CPU-side
`projectile_manager.projectile_landed` callback — violates
[ADR-0031] (battle state lives only in the GPU). The constant deletion
sub-step landed in commit `a62be945` and is retained; the CPU-callback
shape was never implemented. ADR-0032 keeps damage timing in the GPU
by introducing `STATE_AWAITING_IMPACT` as the firer's flight-tail state.
The "Considered options" of this ADR — stretching the SEQ, splitting
`STATE_ACTING` into a follow-through state — carry forward into
ADR-0032's "Considered options" with their rejection reasons intact.

## Context

`STATE_ACTING` is currently overloaded. For a chemist firing a gun at a target
4 tiles away, it covers three distinct phases inside one state:

1. Playing the attack SEQ (frames 0–44).
2. Holding the recoil pose while the bullet is in flight (frames 44–60).
3. Sitting still while damage applies and a safety pad runs (frames 60–70).

The unit's [activity](../context/18-sprite-layers.md) stays `ATTACKING`
through all three because [ADR-0026](0026-gpu-combat-states-map-to-activities-never-directly-to-a-seq.md)
binds `STATE_ACTING` → `ATTACKING`. So while the SEQ has finished playing,
the body is paint-locked to the last frame of the recoil pose by the
[`PauseAnimation` opcode](../context/19-animation-playback.md), and the
unit reads to the player as frozen mid-shot for several hundred ms.

The naïve fix — shorten the `STATE_ACTING` timer — drops damage entirely: the
GPU writes `U_DAMAGE_TARGET` / `U_DAMAGE_AMOUNT` inside `tick_acting_animation`
(`stage_compute.glsl:704-817`), which only runs while
`state == STATE_ACTING && timer > 0`. Phase 3 is paranoia and was retired
(the `ANIM_BUFFER_MULTIPLIER` and `ANIM_SAFETY_MARGIN` constants), but phase 2
is load-bearing: damage *must* fire after the projectile arrives, and the only
place that fires today is the GPU's `state == STATE_ACTING` gate.

The result is that melee was fixed by the constant removal (SEQ length is the
binding leg of the `max()`) but ranged still holds for `damage_frame -
attack_duration` ticks because `damage_frame = projectile_frame + flight_ticks`
extends past the SEQ end by design.

## Decision

- **Damage gating moves to projectile landing.** For ranged attacks and
  projectile spells, the GPU stops applying damage from `tick_acting_animation`.
  `projectile_manager` already owns the visual flight; on landing it raises a
  typed event that `CombatLoop` consumes to apply HP/MP/status changes, mirroring
  the existing apply path used for melee damage today.
- **`STATE_ACTING` ends at SEQ end.** The timer collapses to
  `max(attack_duration, projectile_frame)` — the SEQ length, or the projectile
  spawn frame if it is later (which is rare and probably never). No `damage_frame`
  in the timer formula at all.
- **Activity follows.** Once `STATE_ACTING` ends, the GPU snaps the unit to
  `STATE_IDLE` and the activity resolves to `IDLE` (ADR-0026 path unchanged);
  the body's idle SEQ plays *while the projectile is in flight*. This matches
  the original PSX behavior — the firing unit returns to neutral while their
  shot crosses the field.
- **The interpreter, not the GPU, owns the projectile→damage coupling.** The
  [combat-step interpreter](../context/02-combat-buffer-layout.md) (ADR-0018)
  remains the only place that emits damage events to the apply pump. Today it
  emits `HpChanged` synthesized from the GPU snapshot; under this decision it
  also emits damage events synthesized from `projectile_manager`'s landing
  callback. The apply pump stays unaware of *which* source produced the event.
- **No new GPU state.** `STATE_ACTING` retains its single meaning — "playing
  the action SEQ" — and does not split into `STATE_ACTING` + `STATE_FOLLOW_THROUGH`.
  The "follow-through" concept is *not a thing the unit is doing*; it is the
  projectile's flight, owned by `projectile_manager`, and the unit has nothing
  to do while it happens (it is idle).

## Considered options

- **Split `STATE_ACTING` into `STATE_ACTING` + `STATE_FOLLOW_THROUGH` (rejected).**
  Promotes phase 2 to a first-class state with its own activity (`RECOVERING`?).
  Rejected: there is no SEQ data for "follow-through" — the BODY attack SEQs already
  end with their own recovery frames inside the existing `STATE_ACTING` window
  (e.g. slot 160 ends with `WeaponSheatheCheck2` + `MoveBackward1` + a final
  hold). Adding a state for nothing-to-do is structural overhead for an empty
  set of animations.
- **Keep damage in `tick_acting_animation` but stretch the SEQ to fill the timer
  (rejected).** Slowing the SEQ so it plays for `damage_frame` ticks instead of
  `attack_duration` ticks. Rejected: a 44-frame SEQ stretched over 70 ticks
  plays at 0.63× speed — the chemist would fire the gun in slow motion.

## Consequences

- `tick_acting_animation` loses its damage-write branch for ranged actions; the
  branch survives for melee/instant only. The state-machine code in
  `stage_compute.glsl:880-924` simplifies.
- `projectile_manager` becomes load-bearing in the combat correctness path, not
  just a visual system. Its landing callback is the *only* trigger for ranged
  damage; if it drops a landing, damage is lost. The combat-step interpreter
  cross-references the GPU's `projectile_fired` event so a missing landing is
  detectable.
- Melee attacks, instant spells, and AOE damage are unaffected — they continue
  to apply damage inside the GPU at `anim_frame == damage_frame` in the same
  tick, because there is no projectile flight to wait for.
- The `MIN_FLIGHT_TICKS = 15` floor is no longer a unit-state concern (the unit
  is idle during flight) and becomes a pure projectile-visual concern — it can
  be retuned without touching the GPU.
- The retired constants stay retired. This ADR replaces their semantics ("pad
  the state so damage has time to fire") with an architectural one ("damage
  doesn't ride state at all").

## References

- ADR-0018 — combat-step interpreter (the consumer of the new projectile-landing
  damage events).
- ADR-0026 — `STATE_ACTING` → `ATTACKING` activity binding (preserved; this ADR
  only changes when `STATE_ACTING` ends, not what it maps to).
- CONTEXT.md — [Combat-step interpreter](../context/02-combat-buffer-layout.md),
  [Animation playback](../context/19-animation-playback.md).
